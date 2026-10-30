import SwiftUI

/// Design tokens for wisp: pure black panel, flat cards, no gradients, no glass.
enum Theme {
    // Colours
    static let panel         = Color(hex: 0x000000)
    static let card          = Color(hex: 0x141416)
    static let cardBorder    = Color(hex: 0x1F1F22)
    static let control       = Color(hex: 0x1C1C1E)
    static let controlHover  = Color(hex: 0x222225)
    static let activeTab     = Color(hex: 0x2A2A2D)
    static let textPrimary   = Color.white
    static let textSecondary = Color(hex: 0xA1A1AA)
    static let badge         = Color(hex: 0xFF453A)
    static let ok            = Color(hex: 0x30D158)
    static let warning       = Color(hex: 0xFF9F0A)

    // Panel geometry (expanded)
    static let panelWidth: CGFloat     = 600
    static let panelTopInset: CGFloat  = 40
    static let panelInset: CGFloat     = 14
    static let panelCorner: CGFloat    = 26
    static let tabBarHeight: CGFloat   = 28
    static let tabBarGap: CGFloat      = 10
    static let contentHeight: CGFloat  = 150

    // Mail peek (board 8)
    static let peekWidth: CGFloat  = 420
    static let peekHeight: CGFloat = 132

    static var panelHeight: CGFloat {
        panelTopInset + tabBarHeight + tabBarGap + contentHeight + panelInset
    }

    // Shapes
    static let cardCorner: CGFloat   = 16
    static let buttonCorner: CGFloat = 9
    static let buttonHeight: CGFloat = 28
    static let tabSize = CGSize(width: 32, height: 28)
}

/// Accent colours offered in Settings.
enum Accent: String, CaseIterable, Identifiable {
    case blue, green, orange, purple

    var id: String { rawValue }

    var color: Color {
        switch self {
        case .blue:   Color(hex: 0x0A84FF)
        case .green:  Color(hex: 0x30D158)
        case .orange: Color(hex: 0xFF9F0A)
        case .purple: Color(hex: 0xBF5AF2)
        }
    }
}

extension Color {
    init(hex: UInt32) {
        self.init(red:   Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue:  Double(hex & 0xFF) / 255)
    }
}
