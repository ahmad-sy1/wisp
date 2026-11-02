import AppKit
import Carbon.HIToolbox
import SwiftUI

/// Owns the notch window and drives collapse/expand.
///
/// The window is always exactly as big as what is drawn (plus a small hover margin
/// when collapsed), so nothing around the notch is blocked and no polling is needed:
/// hover comes from a tracking area, clicks from SwiftUI.
@MainActor
final class NotchController {
    let model = NotchModel()
    var openSettings: () -> Void = {}
    /// False while something needs an answer (a permission request): stay open.
    var canCollapse: () -> Bool = { true }

    private var geometry = NotchGeometry.current()
    private let panel: NotchPanel
    private var collapseWork: DispatchWorkItem?
    /// Opened with the shortcut: stays until the shortcut, Esc or a click elsewhere.
    private var keyboardOpen = false
    private var outsideClickMonitor: Any?
    /// The wings each source asks for; shown only on a screen with a notch.
    private var wantedWings: [ReferenceWritableKeyPath<NotchModel, Bool>: Bool] = [:]
    /// Asked of the window, not remembered from enter and exit events: those don't come
    /// when the window changes size under a mouse that stands still.
    private var mouseInside: Bool { panel.frame.contains(NSEvent.mouseLocation) }

    private let openSpring = Animation.spring(response: 0.42, dampingFraction: 0.82)
    private let closeSpring = Animation.spring(response: 0.32, dampingFraction: 0.95)

    init() {
        panel = NotchPanel(frame: .zero)
        applyGeometry()

        let host = NotchHostingView(rootView: NotchRootView(model: model, prefs: .shared))
        host.onMouseEntered = { [weak self] in self?.mouseEntered() }
        host.onMouseExited = { [weak self] in self?.mouseExited() }
        panel.contentView = host

        model.onTapCollapsed = { [weak self] in self?.expand() }
        model.onCollapse = { [weak self] in self?.collapse() }
        model.onOpenSettings = { [weak self] in
            self?.collapse()
            self?.openSettings()
        }

        panel.onKey = { [weak self] in self?.handleKey($0) ?? false }
        panel.onEscape = { [weak self] in self?.collapse() }

        panel.setFrame(collapsedFrame, display: true)
        panel.orderFrontRegardless()

        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.screensChanged() }
        }
    }

    // MARK: - Open / close

    func expand(to tab: WispTab? = nil) {
        collapseWork?.cancel()
        if let tab { model.tab = tab }
        // A tab switched off in Settings doesn't open; Home always can.
        if Preferences.shared.hiddenTabs.contains(model.tab) { model.tab = .home }
        guard !model.isExpanded else {
            // The cancel above must not leave it open for good.
            if !mouseInside && !keyboardOpen { scheduleCollapse(after: 4) }
            return
        }
        panel.setFrame(geometry.frame(for: CGSize(width: Theme.panelWidth, height: Theme.panelHeight)),
                       display: true)
        withAnimation(openSpring) {
            model.phase = .expanded
            model.hovering = false
        }
        // Opened from the menu or by an event: close again unless the mouse comes in.
        if !mouseInside && !keyboardOpen { scheduleCollapse(after: 4) }
    }

    func collapse() {
        collapseWork?.cancel()
        guard !model.isCollapsed, canCollapse() else { return }
        endKeyboardOpen()
        withAnimation(closeSpring) {
            model.phase = .collapsed
        } completion: { [weak self] in
            guard let self, self.model.isCollapsed else { return }
            self.model.peekMail = nil
            self.panel.setFrame(self.collapsedFrame, display: true)
            self.giveBackKeyboard()
        }
    }

    /// Peeks out with a new message (board 8) and closes again after a few seconds,
    /// unless the mouse is on it. Only from closed: an open panel isn't interrupted.
    func peek(_ mail: MailMessage) {
        guard model.isCollapsed else { return }
        collapseWork?.cancel()
        model.peekMail = mail
        panel.setFrame(geometry.frame(for: CGSize(width: Theme.peekWidth, height: Theme.peekHeight)), display: true)
        withAnimation(openSpring) {
            model.phase = .peek
            model.hovering = false
        }
        if !mouseInside { scheduleCollapse(after: 6) }
    }

    /// The global shortcut: opens (a peek too) ready for the keyboard, or closes.
    func toggleFromKeyboard() {
        guard !model.isExpanded else { return collapse() }
        keyboardOpen = true
        expand()
        panel.makeKey()
        // Only while open, and it only sees clicks: nothing runs on the closed notch.
        outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            MainActor.assumeIsolated { self?.collapse() }
        }
    }

    private func endKeyboardOpen() {
        keyboardOpen = false
        if let outsideClickMonitor { NSEvent.removeMonitor(outsideClickMonitor) }
        outsideClickMonitor = nil
    }

    /// A key window keeps the keyboard even when it is only the closed notch; ordering it
    /// out for a moment hands typing back to the app you were in.
    private func giveBackKeyboard() {
        guard panel.isKeyWindow else { return }
        panel.orderOut(nil)
        panel.orderFrontRegardless()
    }

    /// ← and → walk through the tabs, Esc closes.
    private func handleKey(_ event: NSEvent) -> Bool {
        guard model.isExpanded else { return false }
        switch Int(event.keyCode) {
        case kVK_Escape:
            collapse()
        case kVK_LeftArrow:
            moveTab(by: -1)
        case kVK_RightArrow:
            moveTab(by: 1)
        default:
            return false
        }
        return true
    }

    private func moveTab(by step: Int) {
        let tabs = Preferences.shared.visibleTabs
        guard let index = tabs.firstIndex(of: model.tab) else { return }
        let next = tabs[(index + step + tabs.count) % tabs.count]
        withAnimation(.easeInOut(duration: 0.18)) { model.tab = next }
    }

    #if DEBUG
    /// Draws the panel into a PNG. Unlike `screencapture` this also works while the
    /// screen is locked or asleep, so a coding agent can check its work at night.
    @discardableResult
    func snapshot(to url: URL) -> Bool {
        guard let view = panel.contentView,
              let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return false }
        view.cacheDisplay(in: view.bounds, to: rep)
        guard let png = rep.representation(using: .png, properties: [:]) else { return false }
        return (try? png.write(to: url)) != nil
    }
    #endif

    /// Shows or hides the music wings on the closed notch.
    func setMusicWings(_ on: Bool) { setWings(\.musicWings, on) }

    /// Shows or hides the focus timer's wings on the closed notch.
    func setFocusWings(_ on: Bool) { setWings(\.focusWings, on) }

    /// Shows or hides the unread-mail wings on the closed notch.
    func setMailWings(_ on: Bool) { setWings(\.mailWings, on) }

    private func setWings(_ wings: ReferenceWritableKeyPath<NotchModel, Bool>, _ wanted: Bool) {
        wantedWings[wings] = wanted
        let on = wanted && model.hasNotch
        guard model[keyPath: wings] != on else { return }
        // Already wide (the other wings show), or open: only the content changes.
        if !model.isCollapsed || (on ? model.showsWings : model.restingSize == restingSize(without: wings)) {
            withAnimation(.easeInOut(duration: 0.2)) { model[keyPath: wings] = on }
            return
        }
        if on {
            // Grow the window first, then let the shape spring out into it.
            model[keyPath: wings] = true
            panel.setFrame(collapsedFrame, display: true)
            model[keyPath: wings] = false
            withAnimation(openSpring) { model[keyPath: wings] = true }
        } else {
            withAnimation(closeSpring) {
                model[keyPath: wings] = false
            } completion: { [weak self] in
                guard let self, self.model.isCollapsed else { return }
                self.panel.setFrame(self.collapsedFrame, display: true)
            }
        }
    }

    /// Close after the usual delay, unless the mouse is on the panel.
    func collapseSoon() {
        guard !mouseInside else { return }
        scheduleCollapse(after: Preferences.shared.closeDelay)
    }

    private func scheduleCollapse(after delay: TimeInterval) {
        collapseWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            // Still on it (the window can grow under a mouse that doesn't move): look again.
            if self.mouseInside && !self.model.isCollapsed {
                self.scheduleCollapse(after: 1)
            } else {
                self.collapse()
            }
        }
        collapseWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    // MARK: - Mouse

    private func mouseEntered() {
        collapseWork?.cancel()
        guard model.isCollapsed else { return }
        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) { model.hovering = true }
    }

    private func mouseExited() {
        if keyboardOpen { return }
        if !model.isCollapsed {
            scheduleCollapse(after: Preferences.shared.closeDelay)
        } else {
            withAnimation(.spring(response: 0.28, dampingFraction: 0.9)) { model.hovering = false }
        }
    }

    // MARK: - Geometry

    /// The resting size if these wings were off (the other wings may keep it wide).
    private func restingSize(without wings: ReferenceWritableKeyPath<NotchModel, Bool>) -> CGSize {
        let all: [ReferenceWritableKeyPath<NotchModel, Bool>] = [\.musicWings, \.focusWings, \.mailWings]
        let others = all.contains { $0 != wings && model[keyPath: $0] }
        return CGSize(width: model.notchSize.width + (others ? 2 * model.wingWidth : 0),
                      height: model.notchSize.height)
    }

    private var collapsedFrame: NSRect {
        let n = model.restingSize
        let g = NotchModel.hoverGrow
        return geometry.frame(for: CGSize(width: n.width + g.width + 8, height: n.height + g.height + 2))
    }

    private func applyGeometry() {
        model.notchSize = geometry.notchSize
        model.hasNotch = geometry.hasNotch
    }

    private func screensChanged() {
        geometry = .current()
        applyGeometry()
        // The lid closed or opened: wings only make sense next to a real notch.
        for (wings, wanted) in wantedWings { setWings(wings, wanted) }
        let frame = model.isCollapsed ? collapsedFrame : geometry.frame(for: model.shapeSize)
        panel.setFrame(frame, display: true)
    }
}
