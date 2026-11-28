import CoreGraphics
import Foundation

/// One scroll event, stripped of AppKit so it can be tested.
struct NotchScrollEvent: Equatable {
    enum Phase: Equatable { case none, began, changed, ended }

    var dx: CGFloat = 0
    var dy: CGFloat = 0
    /// A trackpad or Magic Mouse (or a smooth-scrolling mouse): deltas in points.
    var precise = false
    var phase: Phase = .none
    /// The glide after the fingers lifted; the pager settles by itself instead.
    var momentum = false
    /// The deltas follow the content (natural scrolling) instead of the device.
    var inverted = false
    var time: TimeInterval = 0
}

/// Turns scroll events on the closed notch into what the pager should do.
///
/// - Trackpad (two fingers) and Magic Mouse (one finger): a gesture with phases. Horizontal
///   gestures drag the content along; a gesture that starts vertical is left alone, and so is
///   the glide afterwards. The direction follows the system's natural-scrolling setting, like
///   any scroll view.
/// - A scroll wheel (no phases): one click is one alert, down or right for the next, with a
///   short rest so a fast spin doesn't race through the list.
struct NotchScrollReader {
    enum Action: Equatable {
        case none
        case dragBegan
        case drag(CGFloat)
        case dragEnded
        case step(Int)
    }

    /// Seconds between two wheel steps.
    static let wheelRest: TimeInterval = 0.25
    /// Wheel travel for one step: a notched wheel sends about 1 per click, a smooth one many small deltas.
    static let wheelStep: CGFloat = 1
    static let smoothWheelStep: CGFloat = 12

    private enum Axis { case undecided, horizontal, vertical }
    private var axis: Axis?
    private var wheel: CGFloat = 0
    private var lastStep: TimeInterval = -.infinity

    init() {}

    mutating func read(_ event: NotchScrollEvent) -> Action {
        if event.momentum { return .none }
        switch event.phase {
        case .began:
            axis = .undecided
            return decide(event)
        case .changed:
            return decide(event)
        case .ended:
            defer { axis = nil }
            return axis == .horizontal ? .dragEnded : .none
        case .none:
            return readWheel(event)
        }
    }

    private mutating func decide(_ event: NotchScrollEvent) -> Action {
        switch axis {
        case .undecided?:
            guard event.dx != 0 || event.dy != 0 else { return .none }
            if abs(event.dx) > abs(event.dy) {
                axis = .horizontal
                return .dragBegan
            }
            axis = .vertical
            return .none
        case .horizontal?:
            // Fingers to the left (natural scrolling) move the content left: on to the next.
            return .drag(-event.dx)
        case .vertical?, nil:
            return .none
        }
    }

    private mutating func readWheel(_ event: NotchScrollEvent) -> Action {
        // Which way the wheel turned, whatever natural scrolling does to the deltas:
        // down and right go to the next alert.
        let flip: CGFloat = event.inverted ? 1 : -1
        let delta = abs(event.dy) >= abs(event.dx) ? event.dy * flip : event.dx * flip
        guard delta != 0 else { return .none }
        if wheel != 0 && (wheel > 0) != (delta > 0) { wheel = 0 }
        wheel += delta
        let needed = event.precise ? Self.smoothWheelStep : Self.wheelStep
        guard abs(wheel) >= needed else { return .none }
        let direction = wheel > 0 ? 1 : -1
        wheel = 0
        guard event.time - lastStep >= Self.wheelRest else { return .none }
        lastStep = event.time
        return .step(direction)
    }
}
