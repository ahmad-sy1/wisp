import SwiftUI

/// UI state of the notch, shared by the controller and the SwiftUI views.
@MainActor
final class NotchModel: ObservableObject {
    /// `peek`: the short mail notification (board 8), between closed and open.
    enum Phase { case collapsed, peek, expanded }

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
    /// Unread mail: an envelope and the count (only when nothing else uses the wings).
    @Published var mailWings = false
    @Published var unreadCount = 0
    /// CI, reviews, departure: a status that needs room on both sides of the camera.
    @Published var statusWings: StatusWings?
    /// How far the closed notch has dropped during a tick (2 pt and back).
    @Published var tickOffset: CGFloat = 0
    /// A short flash of colour over the closed notch (CI passed or failed).
    @Published var flash: Color?
    /// The message the peek shows.
    @Published var peekMail: MailMessage?

    var onTapCollapsed: () -> Void = {}
    var onOpenSettings: () -> Void = {}
    var onCollapse: () -> Void = {}

    /// How much the resting notch swells while the mouse is on it.
    static let hoverGrow = CGSize(width: 14, height: 4)

    var isExpanded: Bool { phase == .expanded }
    var isCollapsed: Bool { phase == .collapsed }

    /// Width of one music wing: about square with the notch height.
    var wingWidth: CGFloat { notchSize.height + 2 }

    var showsWings: Bool { musicWings || focusWings || mailWings || statusWings != nil }

    /// What the wings show now. One thing at a time, most urgent first: a focus session, an
    /// urgent status, music, a calm status (a run going), unread mail.
    enum Wings: Equatable { case none, focus, status(StatusWings), music, mail }

    var wings: Wings {
        if focusWings { return .focus }
        if let statusWings, statusWings.urgent { return .status(statusWings) }
        if musicWings { return .music }
        if let statusWings { return .status(statusWings) }
        if mailWings { return .mail }
        return .none
    }

    /// The width of one wing as things are now.
    var currentWingWidth: CGFloat {
        if case .status(let status) = wings { return status.wingWidth + 12 }
        return wingWidth
    }

    /// The closed notch, including the wings when they show.
    var restingSize: CGSize {
        CGSize(width: notchSize.width + (showsWings ? 2 * currentWingWidth : 0), height: notchSize.height)
    }

    var shapeSize: CGSize {
        if isExpanded { return CGSize(width: Theme.panelWidth, height: Theme.panelHeight) }
        if phase == .peek { return CGSize(width: Theme.peekWidth, height: Theme.peekHeight) }
        guard hovering else {
            return CGSize(width: restingSize.width, height: restingSize.height + tickOffset)
        }
        return CGSize(width: restingSize.width + Self.hoverGrow.width,
                      height: restingSize.height + Self.hoverGrow.height)
    }

    /// Bottom corner radius: the hardware notch is softly rounded, the panel more so.
    var bottomRadius: CGFloat {
        isCollapsed ? min(10, notchSize.height / 3) : Theme.panelCorner
    }
}
