import SwiftUI

/// Design tokens for wisp (board 0.2): pure black panel, flat cards, no gradients, no glass.
enum Theme {
    // Colours
    static let panel = Color(hex: 0x000000)
    static let card = Color(hex: 0x141416)
    static let cardBorder = Color(hex: 0x1F1F22)
    static let control = Color(hex: 0x1C1C1E)
    static let controlHover = Color(hex: 0x222225)
    static let activeTab = Color(hex: 0x2A2A2D)
    /// A switched-off track and the chosen segment.
    static let trackOff = Color(hex: 0x3A3A3E)
    static let sidebar = Color(hex: 0x0B0B0D)
    static let modal = Color(hex: 0x0E0E10)
    static let rowHover = Color(hex: 0x18181B)
    /// The border of fields, modals and chips.
    static let lineStrong = Color(hex: 0x2A2A2D)
    static let textPrimary = Color.white
    /// Field labels and chip text.
    static let textLabel = Color(hex: 0xD4D4D8)
    static let textSecondary = Color(hex: 0xA1A1AA)
    /// Meta, section labels and placeholders.
    static let textFaint = Color(hex: 0x71717A)
    static let textDisabled = Color(hex: 0x52525B)
    static let badge = Color(hex: 0xFF453A)
    /// Red that stays readable as text on black; `badge` is for filled shapes.
    static let redText = Color(hex: 0xFF6961)
    static let ok = Color(hex: 0x30D158)
    static let warning = Color(hex: 0xFF9F0A)
    /// Review requests: the blue badge and dot, whatever the accent colour.
    static let info = Color(hex: 0x0A84FF)
    /// Rain on the closed notch.
    static let rain = Color(hex: 0x64D2FF)
    /// The NS badge in a route.
    static let nsYellow = Color(hex: 0xFFC917)

    // Panel geometry (expanded)
    static let panelWidth: CGFloat = 600
    static let panelTopInset: CGFloat = 40
    static let panelInset: CGFloat = 14
    static let panelCorner: CGFloat = 26
    static let tabBarHeight: CGFloat = 28
    static let tabBarGap: CGFloat = 10
    static let contentHeight: CGFloat = 150

    // Mail peek (board 8)
    static let peekWidth: CGFloat = 420
    static let peekHeight: CGFloat = 132

    static var panelHeight: CGFloat {
        panelTopInset + tabBarHeight + tabBarGap + contentHeight + panelInset
    }

    // Shapes
    static let cardCorner: CGFloat = 14
    static let modalCorner: CGFloat = 16
    static let buttonCorner: CGFloat = 8
    static let smallCorner: CGFloat = 6
    static let iconCorner: CGFloat = 11
    static let buttonHeight: CGFloat = 28
    static let tabSize = CGSize(width: 32, height: 28)
}

/// Accent colours offered in Settings.
enum Accent: String, CaseIterable, Identifiable {
    case blue, green, orange, purple

    var id: String { rawValue }

    var color: Color {
        switch self {
        case .blue: Color(hex: 0x0A84FF)
        case .green: Color(hex: 0x30D158)
        case .orange: Color(hex: 0xFF9F0A)
        case .purple: Color(hex: 0xBF5AF2)
        }
    }

    var hover: Color {
        switch self {
        case .blue: Color(hex: 0x3395FF)
        case .green: Color(hex: 0x4FD871)
        case .orange: Color(hex: 0xFFAD2F)
        case .purple: Color(hex: 0xC973F4)
        }
    }

    var pressed: Color {
        switch self {
        case .blue: Color(hex: 0x0071E3)
        case .green: Color(hex: 0x2AB84D)
        case .orange: Color(hex: 0xE08C09)
        case .purple: Color(hex: 0xA84FD5)
        }
    }
}

extension Color {
    init(hex: UInt32) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255)
    }
}
