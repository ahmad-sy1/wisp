import SwiftUI

/// UI state of the notch, shared by the controller and the SwiftUI views.
@MainActor
final class NotchModel: ObservableObject {
    enum Phase { case collapsed, expanded }

    @Published var phase: Phase = .collapsed
    @Published var hovering = false
    @Published var tab: WispTab = .home
    /// Red count badges on tab icons (e.g. unread mail).
    @Published var badges: [WispTab: Int] = [:]

    @Published var notchSize = CGSize(width: 185, height: 32)
    @Published var hasNotch = true
    /// Music is playing: the closed notch grows a wing on each side (artwork, equalizer).
    @Published var musicWings = false
    /// A focus session runs: the wings show its ring and time instead (they win over music).
    @Published var focusWings = false

    var onTapCollapsed: () -> Void = {}
    var onOpenSettings: () -> Void = {}

    /// How much the resting notch swells while the mouse is on it.
    static let hoverGrow = CGSize(width: 14, height: 4)

    var isExpanded: Bool { phase == .expanded }

    /// Width of one music wing: about square with the notch height.
    var wingWidth: CGFloat { notchSize.height + 2 }

    var showsWings: Bool { musicWings || focusWings }

    /// The closed notch, including the wings when they show.
    var restingSize: CGSize {
        CGSize(width: notchSize.width + (showsWings ? 2 * wingWidth : 0), height: notchSize.height)
    }

    var shapeSize: CGSize {
        if isExpanded { return CGSize(width: Theme.panelWidth, height: Theme.panelHeight) }
        guard hovering else { return restingSize }
        return CGSize(width: restingSize.width + Self.hoverGrow.width,
                      height: restingSize.height + Self.hoverGrow.height)
    }

    /// Bottom corner radius: the hardware notch is softly rounded, the panel more so.
    var bottomRadius: CGFloat {
        isExpanded ? Theme.panelCorner : min(10, notchSize.height / 3)
    }
}
