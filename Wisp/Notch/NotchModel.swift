import SwiftUI

/// UI state of the notch, shared by the controller and the SwiftUI views.
@MainActor
final class NotchModel: ObservableObject {
    /// `peek`: the short mail notification (board 8), between closed and open.
    enum Phase { case collapsed, peek, expanded }

    @Published var phase: Phase = .collapsed
    @Published var hovering = false
    @Published var tab: WispTab = .home
    /// The *More* menu of the tab bar is open.
    @Published var moreOpen = false
    /// Red count badges on tab icons (e.g. unread mail).
    @Published var badges: [WispTab: Int] = [:]

    @Published var notchSize = CGSize(width: 185, height: 32)
    @Published var hasNotch = true
    /// Everything that wants to stay on the closed notch, in order (`ClosedNotchSlot`). The
    /// wings show the first; empty on a screen without a notch.
    @Published var alerts = ClosedNotchList<Wings>()
    /// Which alert shows, and where a swipe through them stands.
    @Published var pager = NotchPager()
    /// System setting, read when a swipe starts: no sliding, just switching.
    var reduceMotion = false
    @Published var unreadCount = 0
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

    var showsWings: Bool { !alerts.isEmpty }

    /// How one alert looks on the wings: a focus session's ring and time, the artwork and
    /// equalizer, unread mail, or a status (CI, reviews, departure) with text on both sides.
    enum Wings: Equatable {
        case focus
        case status(StatusWings)
        case music, mail
    }

    /// What the wings show now: the alert the pager stands on (the most important one unless
    /// you browsed), or nil.
    var wings: Wings? { pager.visible.flatMap { alerts[$0] } }

    /// The width of one wing for `wings`: its own, always.
    func wingWidth(for wings: Wings) -> CGFloat {
        if case .status(let status) = wings { return status.wingWidth + 12 }
        return wingWidth
    }

    /// The alerts as the pager needs them.
    func pages(for alerts: ClosedNotchList<Wings>) -> [NotchPager.Page] {
        alerts.entries.map { NotchPager.Page(slot: $0.slot, wing: wingWidth(for: $0.content)) }
    }

    /// The width of one wing as things are now: during a swipe between the two alerts, in
    /// proportion; under Reduce Motion the one that shows.
    var currentWingWidth: CGFloat {
        guard !pager.pages.isEmpty else { return wingWidth }
        return reduceMotion ? pager.pages[pager.index].wing : pager.wing
    }

    /// The widest the wings can get while browsing: the window makes room for it during a drag.
    var widestWing: CGFloat { pager.pages.map(\.wing).max() ?? wingWidth }

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
        return CGSize(
            width: restingSize.width + Self.hoverGrow.width,
            height: restingSize.height + Self.hoverGrow.height)
    }

    /// Bottom corner radius: the hardware notch is softly rounded, the panel more so.
    var bottomRadius: CGFloat {
        isCollapsed ? min(10, notchSize.height / 3) : Theme.panelCorner
    }
}
