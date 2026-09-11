# Architecture

Bendable is one process in four layers. Each depends only on the one below it, and the
boundary between them is a small value type rather than a protocol hierarchy.

```
 hardware -> Hinge -> HingeState -> LidStateMachine -> LidTransition
                                          |
                                          v
                      AnimationEngine -> FrameDescription -> PresetRenderer
```

`HingeState` and `FrameDescription` are the two contracts that matter. Above the hinge
layer nothing knows where the readings came from; below the animation layer nothing
knows what a preset is.

## Hinge providers

`HingeProvider` is a source of `HingeSample` values. Three implementations ship.

**`LidAngleSensorProvider`** reads the built-in sensor on Apple silicon MacBooks. The
device is polled as a feature report at display rate while the lid is moving, so every
frame draws a reading of its own. Its pushed input reports are used only as a doorbell,
to say that movement has begun; the polling thread waits on a condition otherwise and
costs nothing. [docs/HARDWARE.md](docs/HARDWARE.md) covers the device in detail and
explains why polling rather than subscribing is the decision the whole feel rests on.

**`LidStateProvider`** is the fallback, using `IOPMrootDomain` clamshell notifications.
Open and closed edges, no polling, which is all the platform offers without a sensor.

**`SimulatedHingeProvider`** drives the pipeline from code. It backs the debug pane and
the whole test suite, so no hardware is needed to exercise any path above the provider.

`HingeService.makeProvider()` probes in order of quality and reports what it found as a
`HingeCapability`. If the preferred provider throws on start, the service falls back to
the discrete one rather than leaving the app inert.

## Turning readings into state

`HingeNormalizer` is a plain struct with no I/O, which is what makes the whole sensor to
animation contract testable. Per sample it rejects implausible readings, feeds the
learned calibration, resolves the angle, maps it to `progress` (1 open, 0 shut),
converts the angular rate into progress units, and decides a direction.

### Reading a signal quantised to whole degrees

The sensor reports integers. Almost everything awkward in this layer follows from that.

Differencing consecutive readings for a rate is close to useless: each estimate is
either zero or one-over-the-interval, a square wave rather than a speed. A lid moved
slowly makes it worse, because a degree of dither across the boundary can send the
estimate briefly backwards.

`AngularFit` fits an exponentially weighted line through recent readings and takes both
the position and the rate from it. Quantisation averages out, dither cancels, and the
position comes from the line evaluated at the newest reading's own timestamp. That last
detail matters: a low-pass filter suppresses dither precisely by lagging behind it,
whereas a line fitted to steady movement passes through it and costs no delay. The
result is held to within a degree of the reading it was fitted to, so it stays an
estimate of the lid rather than an extrapolation away from it.

The fit's memory follows the speed of the lid. Its precision goes as the noise over the
root of the sample count, and at walking pace a short window's error is the same size as
the movement between one frame and the next. A longer window fixes that and costs
almost nothing, since a line fitted to steady movement has no lag however far back it
reaches.

A light One Euro filter follows, with its cutoff driven by the fitted rate: firm while
the lid is parked so dither does not reach the screen, wide open the moment it moves.
The filter's own derivative could never tell dither from movement on a signal this
coarse, which is why the rate is measured separately.

### Calibration

The closed end is a hardware floor: the lowest angle the sensor has ever reported. That
is stable, because a lid resting shut reads the same every time.

The open end is the interesting one, and it is not a constant. Learn it as a maximum and
somebody who once pushed the lid right back is left permanently short of 1.0, so the
effect sits partly applied while they work and the last stretch of travel does nothing.
Pin it to a fixed number and it is wrong for everyone whose posture differs from
whoever chose the number.

`OpenReference` follows the lid instead. Wherever the panel comes to rest is what open
means. It moves up readily, after a second or so of stillness, because opening wider is
unambiguous. It moves down only after six seconds parked and then eases over a few
more, so hesitating halfway through closing does not quietly cancel the animation while
genuinely working at a lower angle eventually becomes the new normal. A lid below 25
degrees of its floor teaches it nothing, which is what stops a shut lid or a clamshell
session redefining open. A gap in the samples restarts the dwell, because the lid could
have moved unobserved.

One trap worth recording: the dwell gate originally rejected sample gaps of a second or
more as discontinuities. A parked lid emits about one report a second, so every reading
taken while it was still, which is exactly when the reference is meant to learn, reset
the timer. It could never adapt.

### The animation band

The resting angle is not where the animation starts. Running the effect across the whole
travel means every small adjustment of the screen moves the picture, and the part worth
watching is spread so thin it reads as a slow dim rather than a fold.

So the animation lives in a band immediately above closed, 45 degrees by default and
adjustable. The band is capped at three quarters of the available travel, so somebody
who works with the lid barely open does not find the effect already applied at rest.

A hard band turned out to be half the answer. Putting everything near the stop also
means nothing happens at all for the first stretch of movement, and a lid moved slowly
can go a second or more with the screen inert, which reads as the app not responding.
So about a sixth of the effect tracks the whole travel. Move the lid anywhere and
something answers immediately; the bulk still waits for the band.

### Keeping the animation path clear

Two rules earn most of the responsiveness.

Sensor updates are coalesced rather than queued. A `Task` per sample allocates at the
sensor's rate and lets a backlog build, so the frame being drawn describes an angle the
lid has already left. A small mailbox holds only the newest reading and schedules a
single main-thread delivery.

Nothing on the animation path touches observable state. Writing the hinge angle into an
`@Observable` object every sample invalidates the popover, including its rendered
thumbnails, on the main thread at the sensor's rate, competing with the animation it is
describing. Diagnostics are published at 10 Hz; phase changes go through immediately
because they are rare.

## State machine

`LidStateMachine` is an explicit transition table rather than a pile of flags, because
lid notifications, display power changes and sleep do not arrive in a fixed order, and
closing the lid does not always mean sleeping.

```
        movement                 <=2% open              sleep
 idle ----------> tracking --------------> nearlyClosed -----> sleeping
   ^                 |  ^                       |                 |
   |  fully open     |  |  reopened             | displays slept  | wake
   +-----------------+  +-----------------------+ with external   v
                                                +--------------> clamshell -> waking
```

It returns a `LidTransition` describing what to do (show, hide, capture, release,
render) rather than doing it, so every path can be driven in a test.

Two thresholds matter. The overlay engages at 99.7% open, far earlier than the fold
becomes perceptible: the window and the desktop still have to be ready before the
movement is visible, or the overlay appears part way through and reads as lag. It
disengages at 99.95% open, or at the engage threshold once movement has settled, since
filtered readings converge just short of the top of the calibrated range.

### Sleep, wake and clamshell

`PowerMonitor` bridges `NSWorkspace` sleep, wake and screen lock notifications. Bendable
never takes a power assertion and never delays a transition; it only observes. If it
misses an event the worst case is a stale overlay, which the next hinge reading clears.

The desktop still is dropped on sleep and on screen lock, so a pre-sleep desktop cannot
survive into a locked session. On wake the app re-captures, which yields whatever is
genuinely on screen. The sensor's SPU endpoint does not survive system sleep, so
`HingeService.reconnect()` rebuilds it.

Closing the lid with an external display attached keeps the Mac awake. That path ends in
`clamshell` rather than `sleeping`; reopening re-engages from there.

## Animation engine

```swift
protocol AnimationPreset {
    func frame(progress: Double, velocity: Double,
               direction: HingeDirection, context: AnimationContext) -> FrameDescription
}
```

Presets are pure functions. They touch no AppKit and no GPU, so they can be tested by
feeding progress values and asserting on the result, and the popover's scrubber drives
the identical code path as the lid. There is no separate preview implementation.

`FrameDescription` is the full vocabulary: fold angle and crease position, perspective,
curvature, crease highlight, scale, translation, blur and its gradient, washout,
brightness, opacity, vignette, edge occlusion, corner radius, an optional geometric
mask, and whether the captured desktop is used at all.

`AnimationEngine` applies user settings and substitutes Fade for a capture-requiring
preset when Screen Recording has not been granted. It reports that through
`isSubstituting`, because falling back silently is indistinguishable from the chosen
preset being broken, and macOS never tells an app when TCC changes. The permission is
re-read whenever the popover opens.

`PresetTuning` carries the user-facing strengths, each scaling one of the ramps a preset
produces. A preset declares which it responds to via `supportedControls`, and the
popover builds its sliders from that declaration. Tuning is stored per preset. Tests
assert the declaration is honest in both directions: every declared control must change
the frame somewhere in the travel, and no undeclared one may change it anywhere.

### Fold

The transform is a keystone. The image is a rigid rectangle hinged along its bottom
edge and seen in perspective, so the top recedes and narrows while the bottom stays put.
Nothing is warped, creased or scaled non-uniformly, which is what keeps it reading as a
screen rather than as an effect applied to a picture.

The camera sits a long way back, about six screen heights. That gives strong vertical
foreshortening with only gentle convergence at the sides; a short viewing distance turns
the keystone into a caricature.

The tilt is linear in the hinge angle, eased into a ceiling past about 55 degrees where
the keystone collapses faster than the eye reads as a screen. Easing rather than
clipping matters: a hard cap leaves the panel visibly frozen through the last of the
close, which is when the lid is moving fastest.

Linear, but not necessarily one to one. The band is narrow by design, and turning the
panel by exactly the degrees the hinge swept would leave it barely tipped across it, so
a band under about 75 degrees is mapped onto a fuller rotation. What makes the picture
feel attached is that there is no easing curve of its own between lid and panel, not
that the constant of proportionality is exactly one.

On top of the transform, three ramps, all keyed off the hinge, all monotonic, and all
graded along the panel. Focus goes first, so detail is visibly dissolving before
anything gets dark. Colour drains next, toward grey and then out, never toward white:
the panel is fading into black and lifting it would fight the thing it is fading into.
Light goes last.

The falloff runs to nothing. The far edge sits against the black the overlay is painted
on, and anything short of the same black shows as a seam. It runs along the panel's own
length rather than by depth alone, because depth is near zero at the hinge however far
the panel has turned, which would leave the lower half at full brightness.

Blur also scales with speed. A lid is shut in well under a second, so the panel can turn
a degree and a half between one refresh and the next, and a large change per frame reads
as stepping however evenly it is interpolated. Film has the same problem and the same
answer. A lid moved slowly stays sharp, which is exactly when there is no stepping to
hide.

`CreasePreset` is a book fold over the same machinery: the sheet is creased through the
middle and only the half above rotates, turning by the angle the hinge has swept. Fold
and Crease differ only in where the crease sits and how the ramps are shaped, which is
the clearest evidence that the preset layer is doing real work.

## Rendering

`PresetRenderer` owns a single Metal pipeline covering every preset. Presets differ only
in the uniforms they produce, so adding one never touches the renderer. The mesh is a
48 by 48 grid, enough for the bow to read as a curve.

The vertex shader emits a genuine clip-space `w` and leaves x and y in NDC, so the
rasteriser performs both the perspective divide and perspective-correct texture
interpolation. Pre-multiplying by `w` there cancels the divide and projects
orthographically, which is a silent and surprisingly convincing bug.

Defocus samples an explicit mip level rather than running a separate blur pass, with
five taps spread across one texel of that level to dissolve the mip grid, and stops
three levels short of the top so full blur leaves broad colour fields rather than flat
grey.

Every surface is `bgra8Unorm_srgb`, and the suffix is load-bearing. Without it the
shader samples encoded bytes as though they were light, and multiplying those by a
brightness follows the encoding curve rather than the physical one: the picture lingers
as a grey haze and arrives at black by a different route than the black it is sitting
on, so a fade never blends with its own backdrop. With it the GPU decodes on read and
re-encodes on write, so the dimming, the blending and the mipmap averaging all happen in
light.

Behind the panel the pass clears to opaque black and the panel composites over it with
premultiplied source-over blending, so the area the panel has vacated is darkness rather
than a hole onto the live desktop, and its rounded corners antialias against that black.
Mask presets clear to transparent instead and paint black only where the mask covers,
which is why they need no screen capture. Corner rounding is a rounded-rectangle
distance field evaluated in image space, so the corners travel with the content through
the keystone.

`MetalPresetView` drives frames from a `CADisplayLink` created lazily and torn down
whenever nothing moves. It pulls a frame each refresh rather than being pushed one.

`ProgressAnimator` carries the value between readings by easing toward the newest one
over roughly half the interval between them. It never goes past one. An earlier version
predicted ahead using the measured rate, which is smoother while the lid moves evenly
and is also why letting go of the lid left the animation still running: a prediction has
no way to know the movement has stopped, and inferring it from a timeout trades one
failure for the other. An exponential approach cannot overshoot by construction. What
that costs is lag, and the lag is the time constant times the rate, so easing over half
an interval leaves the picture about half a degree of lid behind at any speed.

## Overlay

`OverlayWindow` is borderless, click-through, never becomes key, sits at the screen
saver level so it covers full-screen apps, and joins all Spaces. It is placed only on
the display returned by `CGDisplayIsBuiltin`; external displays are never animated.

`OverlayCoordinator` fetches the desktop still on the first reading that shows real
movement, well before anything is drawn, because a screenshot takes tens of milliseconds
and waiting for the engage threshold would put the overlay on screen after the lid had
visibly moved. The window is built while that runs. A still older than two seconds is
refreshed in the background while the previous one keeps rendering, and is released as
soon as the lid stops without engaging.

Movement is detected from velocity rather than progress. Above the band progress is
nearly pinned, so it cannot say whether the lid is moving; velocity comes from the
angular rate and can.

`SCScreenshotManager.captureImage` takes one still of the built-in display, excluding
Bendable's own windows. A still is enough, since by the time the overlay appears the lid
is already moving, and it avoids running a capture stream for the life of the app. The
shareable-content list is cached and pre-warmed.

## Failure behaviour

Bendable controls nothing essential and is built to fail open. No power assertions, no
sleep delays, no hooks in the display path. If Metal is unavailable the overlay is never
created; if the sensor disappears the app falls back or goes idle; if capture fails the
preset degrades to one that does not need it. Nothing the animation does prevents the
Mac from sleeping, waking, locking or shutting down.

## Staying awake with the lid shut

The one feature that breaks the rule above, and it is kept at arm's length because of
it.

No public API can do this. `IOPMLib.h` says of the strongest sleep assertion it offers
that "the system may still sleep for lid close", and the type that sounds right,
`kIOPMAssertionTypePreventSystemSleep`, is documented as unsupported in any release.
The only switch that works is `pmset disablesleep`, a system setting, and it needs
root.

`SleepGuard` therefore holds no privilege at all. Each change puts up the standard
authorization dialog and runs one fixed command with a single digit this file produced
itself; nothing from a preference, a user or a network reaches that shell. There is no
helper tool and no daemon, so between one toggle and the next Bendable is an ordinary
unprivileged app. The cost is a password prompt every time, which is the trade that
was chosen deliberately.

Three consequences shape the code around it. The setting is global, so another app or a
terminal can change it underneath: `SleepGuardStatus.resolve` compares what Bendable
asked for against what `IOPMrootDomain` actually reports, and the switch follows the
machine rather than the preference. It outlives the process, so a run that is killed
leaves it on, which is `onFromElsewhere` and is said out loud. And clearing it needs
authorization exactly as much as setting it did, so it cannot be tidied away on quit:
`applicationShouldTerminate` asks instead, and refuses to leave if the password dialog
is cancelled. The status item's icon changes while it is on, because a machine that
will not sleep in a bag should not require opening a popover to discover.

## Adding a preset

1. Add a type conforming to `AnimationPreset` under `Animation/Presets`.
2. Implement `frame(progress:velocity:direction:context:)` as a pure function. Return an
   identity frame at `progress == 1` or the overlay will flash when it appears, and
   handle `context.reduceMotion`; `ReduceMotionFallback` is there for that.
3. Add it to `AnimationPresetCatalog.all`.

Nothing else changes. The catalogue drives the menu, the style picker and the tests that
sweep every preset across the full travel.
