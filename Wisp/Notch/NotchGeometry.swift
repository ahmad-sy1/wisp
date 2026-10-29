import AppKit

/// Where the notch is and how big it is. Screens without a notch get a small bar
/// of the same height as the menu bar.
struct NotchGeometry {
    let screen: NSScreen
    let notchSize: CGSize
    let hasNotch: Bool

    static func current() -> NotchGeometry {
        let screens = NSScreen.screens
        let screen = screens.first { $0.safeAreaInsets.top > 0 } ?? NSScreen.main ?? screens[0]

        if screen.safeAreaInsets.top > 0,
           let left = screen.auxiliaryTopLeftArea, let right = screen.auxiliaryTopRightArea {
            let width = screen.frame.width - left.width - right.width
            return NotchGeometry(screen: screen,
                                 notchSize: CGSize(width: width, height: screen.safeAreaInsets.top),
                                 hasNotch: true)
        }

        let menuBar = max(24, screen.frame.maxY - screen.visibleFrame.maxY)
        return NotchGeometry(screen: screen,
                             notchSize: CGSize(width: 180, height: menuBar),
                             hasNotch: false)
    }

    /// Window frame for a panel of `size`, centred under the top edge of the screen.
    func frame(for size: CGSize) -> NSRect {
        let s = screen.frame
        return NSRect(x: (s.midX - size.width / 2).rounded(),
                      y: s.maxY - size.height,
                      width: size.width, height: size.height)
    }
}
