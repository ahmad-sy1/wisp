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
    private var flashEnd: DispatchWorkItem?
    /// Opened with the shortcut: stays until the shortcut, Esc or a click elsewhere.
    private var keyboardOpen = false
    private var outsideClickMonitors: [Any] = []
    /// The wings each source asks for; shown only on a screen with a notch.
    private var wantedWings: [ReferenceWritableKeyPath<NotchModel, Bool>: Bool] = [:]
    private var wantedStatus: StatusWings?
    /// Asked of the window, not remembered from enter and exit events: those don't come
    /// when the window changes size under a mouse that stands still. `NSMouseInRect`: on the
    /// top row of pixels the mouse is at maxY, which `contains` leaves out.
    private var mouseInside: Bool { NSMouseInRect(NSEvent.mouseLocation, panel.frame, false) }

    private let openSpring = Animation.spring(response: 0.42, dampingFraction: 0.82)
    private let closeSpring = Animation.spring(response: 0.32, dampingFraction: 0.95)

    init() {
        panel = NotchPanel(frame: .zero)
        applyGeometry()

        let host = NotchHostingView(rootView: NotchRootView(model: model, prefs: .shared))
        host.onMouseEntered = { [weak self] in self?.mouseEntered() }
        host.onMouseExited = { [weak self] in self?.mouseExited() }
        panel.contentView = host

        model.onTapCollapsed = { [weak self] in
            guard let self else { return }
            // A status on the notch: a click opens where it comes from.
            if case .status(let status) = self.model.wings {
                self.expand(to: status.tab)
            } else {
                self.expand()
            }
        }
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
            if !keyboardOpen { scheduleCollapse(after: 4) }
            return
        }
        panel.setFrame(
            geometry.frame(for: CGSize(width: Theme.panelWidth, height: Theme.panelHeight)),
            display: true)
        withAnimation(openSpring) {
            model.phase = .expanded
            model.hovering = false
        }
        // Opened from the menu or by an event: close again unless the mouse comes in. Always
        // scheduled: a mouse already there sends no enter, and so maybe no exit either.
        if !keyboardOpen { scheduleCollapse(after: 4) }
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
        scheduleCollapse(after: 6)
    }

    /// The global shortcut: opens (a peek too) ready for the keyboard, or closes.
    func toggleFromKeyboard() {
        guard !model.isExpanded else { return collapse() }
        keyboardOpen = true
        expand()
        panel.makeKey()
        // Only while open, and they only see clicks: nothing runs on the closed notch.
        let clicks: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown]
        let global = NSEvent.addGlobalMonitorForEvents(matching: clicks) { [weak self] _ in
            MainActor.assumeIsolated { self?.collapse() }
        }
        // Clicks in wisp's own windows, such as Settings, don't reach the global one.
        let local = NSEvent.addLocalMonitorForEvents(matching: clicks) { [weak self] event in
            MainActor.assumeIsolated {
                if event.window !== self?.panel { self?.collapse() }
            }
            return event
        }
        outsideClickMonitors = [global, local].compactMap { $0 }
    }

    private func endKeyboardOpen() {
        keyboardOpen = false
        outsideClickMonitors.forEach(NSEvent.removeMonitor)
        outsideClickMonitors = []
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
                let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds)
            else { return false }
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

    /// Shows a status (CI, reviews, departure) on the closed notch; nil takes it away.
    func setStatus(_ status: StatusWings?) {
        wantedStatus = status
        changeWings(\.statusWings, to: model.hasNotch ? status : nil)
    }

    /// The notch drops 2 pt and springs back, once per event.
    func tick() {
        guard model.isCollapsed else { return }
        withAnimation(.spring(response: 0.16, dampingFraction: 0.5)) { model.tickOffset = 2 }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.14) { [weak self] in
            withAnimation(.spring(response: 0.3, dampingFraction: 0.55)) { self?.model.tickOffset = 0 }
        }
    }

    /// A short flash of colour over the closed notch. A new flash gets its full time, and a
    /// failure that is still showing isn't replaced by a pass from the same moment.
    func flash(_ color: Color) {
        guard model.isCollapsed else { return }
        if model.flash == Theme.badge && color != Theme.badge { return }
        flashEnd?.cancel()
        withAnimation(.easeOut(duration: 0.12)) { model.flash = color }
        let end = DispatchWorkItem { [weak self] in
            withAnimation(.easeOut(duration: 0.45)) { self?.model.flash = nil }
        }
        flashEnd = end
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: end)
    }

    private func setWings(_ wings: ReferenceWritableKeyPath<NotchModel, Bool>, _ wanted: Bool) {
        wantedWings[wings] = wanted
        changeWings(wings, to: wanted && model.hasNotch)
    }

    /// Changes what the wings show. Growing: the window first, then the shape springs out into
    /// it. Shrinking: the shape first, then the window. Same size: only the content changes.
    private func changeWings<Value: Equatable>(_ wings: ReferenceWritableKeyPath<NotchModel, Value>, to new: Value) {
        let old = model[keyPath: wings]
        guard old != new else { return }
        let before = model.restingSize
        model[keyPath: wings] = new
        let after = model.restingSize
        model[keyPath: wings] = old
        if !model.isCollapsed || after == before {
            withAnimation(.easeInOut(duration: 0.2)) { model[keyPath: wings] = new }
        } else if after.width > before.width {
            model[keyPath: wings] = new
            panel.setFrame(collapsedFrame, display: true)
            model[keyPath: wings] = old
            withAnimation(openSpring) { model[keyPath: wings] = new }
        } else {
            withAnimation(closeSpring) {
                model[keyPath: wings] = new
            } completion: { [weak self] in
                guard let self, self.model.isCollapsed else { return }
                self.panel.setFrame(self.collapsedFrame, display: true)
            }
        }
    }

    /// Close after the usual delay, unless the mouse is on the panel.
    func collapseSoon() {
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
        setStatus(wantedStatus)
        let frame = model.isCollapsed ? collapsedFrame : geometry.frame(for: model.shapeSize)
        panel.setFrame(frame, display: true)
    }
}
