import AppKit
import Metal
import QuartzCore

/// Hosts the Metal layer and pushes frames on the display's own cadence.
///
/// The display link is created lazily and paused whenever nothing is moving, so an
/// idle Bendable does no per-frame work at all.
final class MetalPresetView: NSView {
    private let renderer: PresetRenderer?
    private var displayLink: CADisplayLink?
    private var pendingFrame: FrameDescription?
    private var lastRenderedFrame: FrameDescription?

    /// Asked for a frame on every display refresh, with the interval since the last
    /// one. Pulling rather than being pushed is what decouples the animation from the
    /// sensor's quantised, irregular reporting.
    var frameProvider: ((CFTimeInterval) -> FrameDescription?)?

    /// Called on every drawn frame with the measured frame interval, for the debug pane.
    var onFrameTiming: ((Double) -> Void)?
    /// Called on every display link callback, drawn or not. Diagnostics only.
    var onDisplayLinkTick: (() -> Void)?
    private var lastFrameTimestamp: CFTimeInterval = 0

    init(renderer: PresetRenderer?) {
        self.renderer = renderer
        super.init(frame: .zero)
        wantsLayer = true
        layerContentsRedrawPolicy = .duringViewResize
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not supported") }

    override var isOpaque: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { false }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func makeBackingLayer() -> CALayer {
        let layer = CAMetalLayer()
        layer.device = MTLCreateSystemDefaultDevice()
        layer.pixelFormat = PresetRenderer.pixelFormat
        // The desktop still is captured and uploaded as sRGB. Leaving the layer
        // untagged lets the window server treat those values as display-native, which
        // on a P3 panel stretches every colour on the way to the screen.
        layer.colorspace = CGColorSpace(name: CGColorSpace.sRGB)
        layer.isOpaque = false
        layer.framebufferOnly = true
        // Two drawables is the lowest-latency choice, but it lets `nextDrawable()`
        // block the main thread whenever the compositor is still holding one, and this
        // view draws from a display link on that same thread, so a stall shows up as a
        // dropped frame. Three costs one frame of buffering and does not stall.
        layer.maximumDrawableCount = 3
        layer.presentsWithTransaction = false
        layer.needsDisplayOnBoundsChange = true
        return layer
    }

    private var metalLayer: CAMetalLayer? { layer as? CAMetalLayer }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        updateDrawableSize()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        updateDrawableSize()
        // The drawable has no size until the view is in a window, so the first frame
        // submitted before that point never reached the screen. Draw it now.
        if let pendingFrame, lastRenderedFrame == nil {
            renderImmediately(pendingFrame)
        }
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        updateDrawableSize()
    }

    private func updateDrawableSize() {
        guard let metalLayer, let window else { return }
        let scale = window.backingScaleFactor
        metalLayer.contentsScale = scale
        let size = CGSize(width: bounds.width * scale, height: bounds.height * scale)
        guard size.width > 0, size.height > 0, size != metalLayer.drawableSize else { return }
        metalLayer.drawableSize = size
        Log.trace(Log.overlay, "drawable \(Int(size.width))x\(Int(size.height)) at \(scale)x")
    }

    func setCapturedImage(_ image: CGImage?) {
        renderer?.setTexture(image)
    }

    /// Uploads on a background queue, so the main thread stays free to draw.
    func uploadCapturedImage(_ image: CGImage) async {
        guard let renderer else { return }
        let context = renderer.uploadContext
        let uploaded = await MetalTextureLoader.makeMipmappedTexture(
            from: image, device: context.device, queue: context.queue
        )
        guard let uploaded else { return }
        renderer.adopt(uploaded)
    }

    /// Queues a frame. Rendering happens on the next display refresh.
    func submit(_ frame: FrameDescription) {
        pendingFrame = frame
        startDisplayLinkIfNeeded()
    }

    /// Draws one frame immediately, without starting the display link.
    /// Used by the preview scrubber, where updates are driven by user input.
    func renderImmediately(_ frame: FrameDescription) {
        pendingFrame = frame
        guard let renderer, let metalLayer, window != nil else { return }
        updateDrawableSize()
        renderer.render(frame, in: metalLayer)
        lastRenderedFrame = frame
    }

    func startDisplayLinkIfNeeded() {
        guard displayLink == nil, window != nil else { return }
        let link = displayLink(target: self, selector: #selector(step(_:)))
        link.add(to: .main, forMode: .common)
        displayLink = link
    }

    func stopDisplayLink() {
        displayLink?.invalidate()
        displayLink = nil
        lastFrameTimestamp = 0
    }

    @objc private func step(_ link: CADisplayLink) {
        guard let renderer, let metalLayer else { return }

        onDisplayLinkTick?()
        let interval = lastFrameTimestamp > 0 ? link.timestamp - lastFrameTimestamp : link.duration
        lastFrameTimestamp = link.timestamp

        guard let frame = frameProvider?(interval) ?? pendingFrame else { return }
        // Once the animation has converged the frames stop differing, so a parked lid
        // costs a comparison rather than a draw.
        if frame == lastRenderedFrame { return }

        renderer.render(frame, in: metalLayer)
        lastRenderedFrame = frame
        onFrameTiming?(interval)
    }

    // No deinit: a scheduled CADisplayLink retains its target, so the view cannot be
    // deallocated while the link is live. `stopDisplayLink()` is what breaks the cycle.
}
