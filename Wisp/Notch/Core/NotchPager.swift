import CoreGraphics

/// Browsing through the closed notch's alerts: which one shows, how far the fingers have
/// dragged, how wide the wings are on the way, and what happens when the list changes.
///
/// Pure state. The controller feeds it scroll deltas and list changes and draws what it says;
/// it starts nothing by itself, so with no input nothing runs.
struct NotchPager: Equatable {
    /// One alert as the pager needs it: its place and the width of one of its wings.
    struct Page: Equatable {
        let slot: ClosedNotchSlot
        let wing: CGFloat
    }

    /// Seconds after the mouse leaves before the most important alert shows again.
    static let returnDelay: Double = 4
    /// How far past the first or last alert the content may follow the fingers.
    static let maxStretch: CGFloat = 14
    /// Dots of alerts that don't show (the one that shows is at 1).
    static let inactiveDot = 0.32

    private(set) var pages: [Page] = []
    /// The alert chosen by browsing; nil shows the first one, whichever that is.
    private(set) var chosen: ClosedNotchSlot?
    /// Finger travel since the drag began, in points; positive moves on to the next alert.
    private(set) var drag: CGFloat = 0
    private(set) var isDragging = false
    /// An urgent alert that arrived during a drag: shown when the fingers lift.
    private(set) var pendingJump: ClosedNotchSlot?
    /// Focus with *Do not disturb*, or a permission request: no browsing.
    private(set) var isQuiet = false

    init() {}

    // MARK: - Reading

    /// Index of the alert that shows when no drag is going.
    var index: Int {
        guard let chosen, let found = pages.firstIndex(where: { $0.slot == chosen }) else { return 0 }
        return found
    }

    /// The alert that shows, the one a click opens.
    var visible: ClosedNotchSlot? { pages.isEmpty ? nil : pages[index].slot }

    /// Swiping makes sense: something to browse, and nothing that wants quiet.
    var canBrowse: Bool { pages.count > 1 && !isQuiet }

    /// Somebody browsed away from the first alert: it comes back `returnDelay` after the mouse leaves.
    var needsReturn: Bool { chosen != nil }

    /// Nothing in progress: no drag and no jump waiting. The notch needs no timer or animation.
    var isIdle: Bool { !isDragging && drag == 0 && pendingJump == nil }

    /// Where the content stands, in alerts: 1.5 is halfway from the second to the third. Past
    /// the first or last alert it stretches a little (`maxStretch`).
    var position: Double {
        guard !pages.isEmpty else { return 0 }
        var at = index
        var left = drag
        while left > 0, at < pages.count - 1 {
            let step = distance(at, at + 1)
            if left < step { return Double(at) + Double(left / step) }
            left -= step
            at += 1
        }
        while left < 0, at > 0 {
            let step = distance(at - 1, at)
            if -left < step { return Double(at) - Double(-left / step) }
            left += step
            at -= 1
        }
        // At either end: the rest of the travel stretches, ever less.
        let edge = at == 0 ? distance(0, min(1, pages.count - 1)) : distance(at - 1, at)
        return Double(at) + Double(Self.stretch(left) / max(edge, 1))
    }

    /// `position` without the stretch at the ends: what the width and the dots follow.
    var settledPosition: Double { min(max(position, 0), Double(max(pages.count - 1, 0))) }

    /// Width of one wing: between the two alerts the content is between, in proportion.
    /// The stretch at the ends doesn't change it.
    var wing: CGFloat {
        guard !pages.isEmpty else { return 0 }
        let p = settledPosition
        let low = Int(p.rounded(.down))
        let high = min(low + 1, pages.count - 1)
        let t = CGFloat(p - Double(low))
        return pages[low].wing + (pages[high].wing - pages[low].wing) * t
    }

    /// How far page `i` sits from the camera now, in points; 0 is in place.
    func offset(of i: Int) -> CGFloat {
        let p = position
        let base = Int(p.rounded(.down))
        func x(_ k: Int) -> CGFloat {
            var total: CGFloat = 0
            if k > 0 { for j in 0..<k { total += distance(j, j + 1) } }
            return total
        }
        let clampedBase = min(max(base, 0), max(pages.count - 1, 0))
        let current = x(clampedBase) + CGFloat(p - Double(clampedBase)) * stepAfter(clampedBase)
        return x(i) - current
    }

    /// The pages worth drawing: the one in place and, while it moves, its neighbour.
    var drawnPages: [Int] {
        guard !pages.isEmpty else { return [] }
        let p = position
        return pages.indices.filter { abs(Double($0) - p) < 1 }
    }

    /// Opacity of the dot of page `i`: full for the alert that shows, `inactiveDot` for the
    /// others, in between while the fingers move (both about 0.66 halfway).
    func dotOpacity(_ i: Int) -> Double {
        let closeness = max(0, 1 - abs(settledPosition - Double(i)))
        return Self.inactiveDot + (1 - Self.inactiveDot) * closeness
    }

    // MARK: - Changes

    /// The list changed. Keeps showing the same alert; if that one went, the one that takes
    /// its place. An urgent alert that is new while you browse shows straight away, or when the
    /// fingers lift. Returns the alert it jumped to, so the notch can tick.
    @discardableResult
    mutating func update(_ new: [Page]) -> ClosedNotchSlot? {
        let old = pages
        let oldIndex = index
        pages = new
        guard !new.isEmpty else {
            reset()
            return nil
        }
        if let chosen, !new.contains(where: { $0.slot == chosen }) {
            // The alert that showed went: the next one moves into its place.
            choose(min(oldIndex, new.count - 1))
            endDrag()
        }
        if let pendingJump, !new.contains(where: { $0.slot == pendingJump }) { self.pendingJump = nil }
        guard !isQuiet, chosen != nil || isDragging else { return nil }
        let arrived = new.filter { page in page.slot.isUrgent && !old.contains { $0.slot == page.slot } }
        guard let urgent = arrived.first?.slot else { return nil }
        if isDragging {
            if pendingJump.map({ urgent < $0 }) ?? true { pendingJump = urgent }
            return nil
        }
        guard urgent != visible, let found = pages.firstIndex(where: { $0.slot == urgent }) else { return nil }
        choose(found)
        return urgent
    }

    mutating func setQuiet(_ quiet: Bool) {
        isQuiet = quiet
        if quiet { reset() }
    }

    mutating func dragBegan() {
        guard canBrowse else { return }
        isDragging = true
        drag = 0
    }

    /// Fingers moved by `delta` points; positive moves on to the next alert.
    mutating func dragChanged(by delta: CGFloat) {
        guard isDragging else { return }
        drag += delta
    }

    /// Fingers lifted: settles on the nearest alert, or on an urgent one that arrived meanwhile.
    /// Returns that urgent alert, so the notch can tick.
    @discardableResult
    mutating func dragEnded() -> ClosedNotchSlot? {
        guard isDragging else { return nil }
        let target: Int
        let jumped: ClosedNotchSlot?
        if let pendingJump, let found = pages.firstIndex(where: { $0.slot == pendingJump }) {
            target = found
            jumped = pendingJump
        } else {
            target = Int(settledPosition.rounded())
            jumped = nil
        }
        endDrag()
        choose(target)
        return jumped
    }

    /// One step without following the fingers: a scroll wheel, or a swipe under Reduce Motion.
    mutating func step(by delta: Int) {
        guard canBrowse, !isDragging else { return }
        choose(min(max(index + delta, 0), pages.count - 1))
    }

    /// Back to the most important alert, `returnDelay` after the mouse left.
    mutating func returnToFirst() {
        guard !isDragging else { return }
        chosen = nil
    }

    /// The panel or a peek opened over the closed notch: any drag ends, the first alert shows.
    mutating func stop() { reset() }

    // MARK: - Private

    /// The first alert isn't pinned: landing on it means "show whatever is most important",
    /// so something more important that arrives later goes in front.
    private mutating func choose(_ i: Int) {
        chosen = i == 0 || !pages.indices.contains(i) ? nil : pages[i].slot
    }

    private mutating func endDrag() {
        isDragging = false
        drag = 0
        pendingJump = nil
    }

    private mutating func reset() {
        endDrag()
        chosen = nil
    }

    /// Finger travel from one alert to the next: the mean of their wing widths, so content in a
    /// wing moves about as fast as the fingers.
    private func distance(_ a: Int, _ b: Int) -> CGFloat {
        guard pages.indices.contains(a), pages.indices.contains(b), a != b else { return pages.first?.wing ?? 1 }
        return (pages[a].wing + pages[b].wing) / 2
    }

    private func stepAfter(_ i: Int) -> CGFloat {
        i < pages.count - 1 ? distance(i, i + 1) : (i > 0 ? distance(i - 1, i) : distance(0, 0))
    }

    /// Ever less movement the further past the end: never more than `maxStretch`.
    private static func stretch(_ travel: CGFloat) -> CGFloat {
        let sign: CGFloat = travel < 0 ? -1 : 1
        let x = abs(travel)
        return sign * maxStretch * (1 - 1 / (x / (maxStretch * 2) + 1))
    }
}
