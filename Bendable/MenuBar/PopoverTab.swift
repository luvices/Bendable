import SwiftUI

enum PopoverTab: String, CaseIterable, Identifiable {
    case style
    case hinge
    case status

    var id: String { rawValue }

    var title: String {
        switch self {
        case .style: "Style"
        case .hinge: "Hinge"
        case .status: "Status"
        }
    }

    var symbol: String {
        switch self {
        case .style: "square.on.square"
        case .hinge: "laptopcomputer"
        case .status: "waveform.path.ecg"
        }
    }
}

/// A pill selector for the control pane.
///
/// Not `Picker(.segmented)`: that draws a bordered control the width of its pane, which
/// fights a popover with no other borders in it.
struct TabBar: View {
    @Binding var selection: PopoverTab
    @Namespace private var pill

    var body: some View {
        HStack(spacing: 1) {
            ForEach(PopoverTab.allCases) { tab in
                let isSelected = tab == selection
                Button {
                    selection = tab
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: tab.symbol)
                            .font(.system(size: 9.5, weight: .medium))
                        Text(tab.title)
                            .font(.system(size: 11, weight: isSelected ? .semibold : .regular))
                    }
                    .foregroundStyle(isSelected ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
                    .padding(.horizontal, 9)
                    .padding(.vertical, 4)
                    .background {
                        if isSelected {
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(.tint.opacity(0.14))
                                .matchedGeometryEffect(id: "pill", in: pill)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(isSelected ? [.isSelected] : [])
            }
            Spacer(minLength: 0)
        }
        .animation(.snappy(duration: 0.18), value: selection)
    }
}
