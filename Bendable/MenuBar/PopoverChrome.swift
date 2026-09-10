import SwiftUI

/// Shared metrics and small controls, so no section has to restate a padding.
enum Metrics {
    static let previewPane: CGFloat = 292
    static let controlPane: CGFloat = 316
    static let width = previewPane + controlPane
    static let bodyHeight: CGFloat = 400

    static let gutter: CGFloat = 14
    static let corner: CGFloat = 8
    static let labelWidth: CGFloat = 94
    static let valueWidth: CGFloat = 40
}

extension Font {
    static let rowLabel = Font.system(size: 12)
    static let rowValue = Font.system(size: 11).monospacedDigit()
    static let groupTitle = Font.system(size: 10, weight: .semibold)
    static let note = Font.system(size: 11)
}

/// A titled group of rows.
///
/// The title is small and set in the secondary colour so the controls under it stay
/// the loudest thing in the pane.
struct SettingsGroup<Content: View>: View {
    let title: String
    var trailing: AnyView?
    @ViewBuilder let content: Content

    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.trailing = nil
        self.content = content()
    }

    init<Trailing: View>(
        _ title: String, @ViewBuilder trailing: () -> Trailing, @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.trailing = AnyView(trailing())
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 0) {
                Text(title.uppercased())
                    .font(.groupTitle)
                    .tracking(0.6)
                    .foregroundStyle(.tertiary)
                Spacer(minLength: 8)
                trailing
            }
            .padding(.leading, 2)

            VStack(spacing: 0) { content }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 3)
                .background(
                    .quaternary.opacity(0.35),
                    in: RoundedRectangle(cornerRadius: Metrics.corner, style: .continuous)
                )
        }
    }
}

private struct RowPadding: ViewModifier {
    func body(content: Content) -> some View {
        content.padding(.horizontal, 10).padding(.vertical, 3)
    }
}

extension View {
    func rowPadding() -> some View { modifier(RowPadding()) }
}

struct SwitchRow: View {
    let title: String
    var help: String = ""
    @Binding var isOn: Bool

    var body: some View {
        // Laid out by hand rather than with a labelled `Toggle`, which hugs its label
        // and leaves the switch floating in the middle of the group.
        HStack(spacing: 8) {
            Text(title).font(.rowLabel)
            Spacer(minLength: 8)
            Toggle("", isOn: $isOn)
                .toggleStyle(.switch)
                .controlSize(.mini)
                .labelsHidden()
        }
        .rowPadding()
        .help(help)
    }
}

/// A labelled slider with its value on the right.
///
/// Double-clicking the label puts the control back to where it shipped. Small enough
/// to be worth having, and it saves anyone from hunting for a Reset they cannot find.
struct SliderRow<Readout: View>: View {
    let title: String
    @Binding var value: Double
    var range: ClosedRange<Double> = 0...1
    var defaultValue: Double?
    var help: String = ""
    @ViewBuilder let readout: Readout

    var body: some View {
        HStack(spacing: 8) {
            Text(title)
                .font(.rowLabel)
                .frame(width: Metrics.labelWidth, alignment: .leading)
                .onTapGesture(count: 2) {
                    if let defaultValue { value = defaultValue }
                }
            Slider(value: $value, in: range)
                .controlSize(.mini)
            readout
                .font(.rowValue)
                .foregroundStyle(.secondary)
                .frame(width: Metrics.valueWidth, alignment: .trailing)
        }
        .rowPadding()
        .help(help)
    }
}

struct PercentSlider: View {
    let title: String
    @Binding var value: Double
    var defaultValue: Double = 1
    var help: String = ""

    var body: some View {
        SliderRow(
            title: title, value: $value, defaultValue: defaultValue, help: help
        ) {
            Text(value.formatted(.percent.precision(.fractionLength(0))))
        }
    }
}

struct DegreeSlider: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    var defaultValue: Double?
    var help: String = ""

    var body: some View {
        SliderRow(
            title: title, value: $value, range: range, defaultValue: defaultValue, help: help
        ) {
            Text(String(format: "%.0f°", value))
        }
    }
}

struct Readout: View {
    let title: String
    let value: String

    var body: some View {
        HStack(spacing: 8) {
            Text(title).font(.rowLabel)
            Spacer(minLength: 8)
            Text(value)
                .font(.rowValue)
                .foregroundStyle(.secondary)
        }
        .rowPadding()
    }
}

struct Note: View {
    let text: String

    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(.note)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 2)
    }
}

/// A small text button that reads as a link without the underline.
struct QuietButton: View {
    let title: String
    let action: () -> Void

    init(_ title: String, action: @escaping () -> Void) {
        self.title = title
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 11))
                .foregroundStyle(.tint)
        }
        .buttonStyle(.plain)
    }
}
