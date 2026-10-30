import AppKit
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
    private var mouseInside = false

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
        model.onOpenSettings = { [weak self] in
            self?.collapse()
            self?.openSettings()
        }

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
        guard !model.isExpanded else { return }
        panel.setFrame(geometry.frame(for: CGSize(width: Theme.panelWidth, height: Theme.panelHeight)),
                       display: true)
        withAnimation(openSpring) {
            model.phase = .expanded
            model.hovering = false
        }
        // Opened from the menu or a shortcut: close again unless the mouse comes in.
        if !mouseInside { scheduleCollapse(after: 4) }
    }

    func collapse() {
        collapseWork?.cancel()
        guard model.isExpanded, canCollapse() else { return }
        withAnimation(closeSpring) {
            model.phase = .collapsed
        } completion: { [weak self] in
            guard let self, !self.model.isExpanded else { return }
            self.panel.setFrame(self.collapsedFrame, display: true)
        }
    }

    func toggle() { model.isExpanded ? collapse() : expand() }

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
    func setMusicWings(_ on: Bool) {
        guard model.musicWings != on else { return }
        if model.isExpanded {
            model.musicWings = on
            return
        }
        if on {
            // Grow the window first, then let the shape spring out into it.
            model.musicWings = true
            panel.setFrame(collapsedFrame, display: true)
            model.musicWings = false
            withAnimation(openSpring) { model.musicWings = true }
        } else {
            withAnimation(closeSpring) {
                model.musicWings = false
            } completion: { [weak self] in
                guard let self, !self.model.isExpanded else { return }
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
        let work = DispatchWorkItem { [weak self] in self?.collapse() }
        collapseWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    // MARK: - Mouse

    private func mouseEntered() {
        mouseInside = true
        collapseWork?.cancel()
        guard !model.isExpanded else { return }
        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) { model.hovering = true }
    }

    private func mouseExited() {
        mouseInside = false
        if model.isExpanded {
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
        let frame = model.isExpanded
            ? geometry.frame(for: CGSize(width: Theme.panelWidth, height: Theme.panelHeight))
            : collapsedFrame
        panel.setFrame(frame, display: true)
    }
}
