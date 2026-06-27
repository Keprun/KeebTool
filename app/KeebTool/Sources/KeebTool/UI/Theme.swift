import SwiftUI

extension Color {
    init(hex: UInt32) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255,
                  opacity: 1)
    }
}

/// "Nightshade Cockpit" — dark RGB-peripheral palette + shared keycap gradients.
enum Theme {
    static let bg = Color(hex: 0x0A0B0F)
    static let surface = Color(hex: 0x14161D)
    static let surfaceAlt = Color(hex: 0x1A1C24)
    static let accent = Color(hex: 0x21D4D9)
    static let accent2 = Color(hex: 0x926DDE)
    static let textPrimary = Color(hex: 0xE8EAF0)
    static let textSecondary = Color(hex: 0x8A90A0)
    static let border = Color(hex: 0x23262F)
    static let legendRest = Color(hex: 0xC7CBD6)
    static let legendSelected = Color(hex: 0xA6F4F7)

    // Precomputed shared gradients (one allocation, reused by all 82 keycaps).
    static let capRest = LinearGradient(colors: [Color(hex: 0x2A2D38), Color(hex: 0x191B22), Color(hex: 0x101218)], startPoint: .top, endPoint: .bottom)
    static let capHover = LinearGradient(colors: [Color(hex: 0x333744), Color(hex: 0x22242E), Color(hex: 0x181A21)], startPoint: .top, endPoint: .bottom)
    static let capSelected = LinearGradient(colors: [Color(hex: 0x1B3A44), Color(hex: 0x13313C), Color(hex: 0x0E2630)], startPoint: .top, endPoint: .bottom)
    static let capModifier = LinearGradient(colors: [Color(hex: 0x23202B), Color(hex: 0x171520), Color(hex: 0x0F0E16)], startPoint: .top, endPoint: .bottom)
    static let capBorder = LinearGradient(colors: [Color.white.opacity(0.16), Color.white.opacity(0.08)], startPoint: .top, endPoint: .bottom)
    static let accentFill = LinearGradient(colors: [Color(hex: 0x21D4D9), Color(hex: 0x0E8F93)], startPoint: .topLeading, endPoint: .bottomTrailing)
    static let paneVignette = RadialGradient(colors: [Color(hex: 0x14161D), Color(hex: 0x0A0B0F)], center: .top, startRadius: 6, endRadius: 760)
}

enum KeyVisualState { case rest, hover, selected, modifier }

/// One convex keycap. Equatable so unchanged caps skip re-render when one key flips state.
struct KeycapView: View, Equatable {
    let label: String
    let symbol: String?
    let w: CGFloat
    let h: CGFloat
    let state: KeyVisualState

    static let UNIT: CGFloat = 46
    static let GUTTER: CGFloat = 5

    static func == (a: KeycapView, b: KeycapView) -> Bool {
        a.label == b.label && a.symbol == b.symbol && a.state == b.state && a.w == b.w && a.h == b.h
    }

    private var fill: LinearGradient {
        switch state {
        case .rest: return Theme.capRest
        case .hover: return Theme.capHover
        case .selected: return Theme.capSelected
        case .modifier: return Theme.capModifier
        }
    }

    private var borderStyle: AnyShapeStyle {
        switch state {
        case .selected: return AnyShapeStyle(Theme.accent)
        case .modifier: return AnyShapeStyle(Theme.accent2.opacity(0.5))
        default: return AnyShapeStyle(Theme.capBorder)
        }
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 9, style: .continuous)
        ZStack {
            shape.fill(fill)
            shape.strokeBorder(borderStyle, lineWidth: state == .selected ? 1 : 0.5)
            legend
        }
        .frame(width: w * Self.UNIT - Self.GUTTER, height: h * Self.UNIT - Self.GUTTER)
        .shadow(color: .black.opacity(0.55), radius: 5, x: 0, y: 3)
        .modifier(SelectionGlow(active: state == .selected))
    }

    @ViewBuilder private var legend: some View {
        let color = state == .selected ? Theme.legendSelected : Theme.legendRest
        if let symbol {
            Image(systemName: symbol).font(.system(size: 12, weight: .medium)).foregroundStyle(color)
        } else {
            Text(label)
                .font(.system(size: label.count == 1 ? 12 : 9.5, weight: state == .selected ? .semibold : .medium))
                .foregroundStyle(color)
                .lineLimit(1).minimumScaleFactor(0.6).padding(.horizontal, 2)
        }
    }
}

/// The single-glow law: only the selected keycap emits a cyan halo.
struct SelectionGlow: ViewModifier {
    let active: Bool
    func body(content: Content) -> some View {
        if active {
            content
                .shadow(color: Theme.accent.opacity(0.55), radius: 14)
                .shadow(color: Theme.accent.opacity(0.85), radius: 4)
        } else {
            content
        }
    }
}

/// SF Symbol for icon-style keys; nil → render the text legend.
func keySymbol(_ label: String) -> String? {
    switch label {
    case "Up": return "arrow.up"
    case "Down": return "arrow.down"
    case "Left": return "arrow.left"
    case "Right": return "arrow.right"
    case "Backspace": return "delete.left"
    case "Enter": return "return"
    case "Tab": return "arrow.right.to.line"
    case "Caps Lock": return "capslock"
    default: return nil
    }
}
