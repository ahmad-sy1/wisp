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

    var onTapCollapsed: () -> Void = {}
    var onOpenSettings: () -> Void = {}

    /// How much the resting notch swells while the mouse is on it.
    static let hoverGrow = CGSize(width: 14, height: 4)

    var isExpanded: Bool { phase == .expanded }

    var shapeSize: CGSize {
        if isExpanded { return CGSize(width: Theme.panelWidth, height: Theme.panelHeight) }
        guard hovering else { return notchSize }
        return CGSize(width: notchSize.width + Self.hoverGrow.width,
                      height: notchSize.height + Self.hoverGrow.height)
    }

    /// Bottom corner radius: the hardware notch is softly rounded, the panel more so.
    var bottomRadius: CGFloat {
        isExpanded ? Theme.panelCorner : min(10, notchSize.height / 3)
    }
}
