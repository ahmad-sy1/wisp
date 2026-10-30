import AppKit

/// What the focus session is about, and where that came from.
struct FocusTask: Equatable {
    enum Source: Equatable {
        /// The calendar event that is on right now.
        case calendar
        /// Guessed from the app in front (and its Claude Code project, if any).
        case automatic(app: String, project: String?)
        /// Typed by the user.
        case manual
    }

    var name: String
    var source: Source
    /// Key under which a correction is remembered ("com.jetbrains.intellij|wisp").
    var learnKey: String?
}

/// The focus timer (board 4): 25 / 50 / 90 minutes, today's sessions, and a guess of
/// what you are working on.
///
/// No timer ticks in here: a running session is an end date plus one scheduled work
/// item for the moment it ends. Views that show the countdown redraw themselves (once a
/// second, only while visible).
@MainActor
final class FocusStore: ObservableObject {
    static let shared = FocusStore()

    enum Phase: Equatable {
        case idle
        case running(end: Date)
        case paused(remaining: TimeInterval)
        case finished
    }

    static let durations = [25, 50, 90]

    @Published private(set) var phase: Phase = .idle
    @Published private(set) var task: FocusTask?
    @Published private(set) var todaySessions = 0
    @Published private(set) var todaySeconds: TimeInterval = 0
    /// Learned corrections: app (and project) → task name.
    @Published private(set) var learned: [String: String]

    @Published var minutes: Int {
        didSet { defaults.set(minutes, forKey: Key.minutes) }
    }
    @Published var doNotDisturb: Bool {
        didSet { defaults.set(doNotDisturb, forKey: Key.dnd) }
    }
    @Published var startMusic: Bool {
        didSet { defaults.set(startMusic, forKey: Key.music) }
    }

    /// Called when a session runs out (the notch opens on the Focus tab).
    var onFinished: () -> Void = {}

    /// The Shortcuts wisp runs for "Do not disturb" (macOS has no API for Focus modes).
    static let shortcutOn = "wisp Focus On"
    static let shortcutOff = "wisp Focus Off"

    private let defaults = UserDefaults.standard
    private var endWork: DispatchWorkItem?
    /// When the current stretch of running began, for today's focused time.
    private var runStart: Date?

    private enum Key {
        static let minutes = "focusMinutes"
        static let dnd = "focusDoNotDisturb"
        static let music = "focusStartMusic"
        static let learned = "focusLearnedTasks"
        static let day = "focusDay"
        static let sessions = "focusDaySessions"
        static let seconds = "focusDaySeconds"
    }

    private init() {
        let saved = defaults.integer(forKey: Key.minutes)
        minutes = Self.durations.contains(saved) ? saved : 25
        doNotDisturb = defaults.bool(forKey: Key.dnd)
        startMusic = defaults.bool(forKey: Key.music)
        learned = defaults.dictionary(forKey: Key.learned) as? [String: String] ?? [:]
        loadToday()
    }

    // MARK: - Timer

    var isActive: Bool {
        switch phase {
        case .running, .paused: true
        case .idle, .finished: false
        }
    }

    var total: TimeInterval { TimeInterval(minutes * 60) }

    func remaining(at now: Date) -> TimeInterval {
        switch phase {
        case .idle: total
        case .finished: 0
        case .running(let end): max(0, end.timeIntervalSince(now))
        case .paused(let remaining): remaining
        }
    }

    /// 1 when a session starts, 0 when it ends.
    func progress(at now: Date) -> Double {
        switch phase {
        case .idle: 1
        case .finished: 0
        case .running, .paused: remaining(at: now) / total
        }
    }

    func start() {
        let now = Date()
        let left: TimeInterval
        switch phase {
        case .running: return
        case .paused(let remaining): left = remaining
        case .idle, .finished:
            left = total
            if task?.source != .manual { refreshTask() }
            if doNotDisturb { Self.runShortcut(Self.shortcutOn) }
            if startMusic, let track = NowPlaying.shared.track, !track.isPlaying { NowPlaying.shared.playPause() }
        }
        runStart = now
        phase = .running(end: now.addingTimeInterval(left))
        scheduleEnd(after: left)
    }

    func pause() {
        guard case .running(let end) = phase else { return }
        let now = Date()
        addFocused(until: now)
        endWork?.cancel()
        phase = .paused(remaining: max(0, end.timeIntervalSince(now)))
    }

    func reset() {
        if case .running = phase { addFocused(until: Date()) }
        let wasActive = isActive
        endWork?.cancel()
        phase = .idle
        if wasActive && doNotDisturb { Self.runShortcut(Self.shortcutOff) }
    }

    private func scheduleEnd(after seconds: TimeInterval) {
        endWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.finish() }
        endWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: work)
    }

    private func finish() {
        guard case .running(let end) = phase else { return }
        addFocused(until: end)
        rollDayIfNeeded()
        todaySessions += 1
        defaults.set(todaySessions, forKey: Key.sessions)
        phase = .finished
        if doNotDisturb { Self.runShortcut(Self.shortcutOff) }
        if Preferences.shared.soundsEnabled { NSSound(named: "Glass")?.play() }
        onFinished()
    }

    // MARK: - Today

    private func addFocused(until now: Date) {
        guard let runStart else { return }
        self.runStart = nil
        rollDayIfNeeded()
        todaySeconds += max(0, now.timeIntervalSince(runStart))
        defaults.set(todaySeconds, forKey: Key.seconds)
    }

    /// Re-reads today's numbers; called when the tab opens, so a new day starts at zero.
    func loadToday() {
        if defaults.string(forKey: Key.day) == Self.dayKey(.now) {
            todaySessions = defaults.integer(forKey: Key.sessions)
            todaySeconds = defaults.double(forKey: Key.seconds)
        } else {
            todaySessions = 0
            todaySeconds = 0
        }
    }

    private func rollDayIfNeeded() {
        let today = Self.dayKey(.now)
        guard defaults.string(forKey: Key.day) != today else { return }
        defaults.set(today, forKey: Key.day)
        todaySessions = 0
        todaySeconds = 0
        defaults.set(0, forKey: Key.sessions)
        defaults.set(0.0, forKey: Key.seconds)
    }

    private static func dayKey(_ date: Date) -> String {
        let c = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return "\(c.year ?? 0)-\(c.month ?? 0)-\(c.day ?? 0)"
    }

    // MARK: - What am I working on?

    /// Guesses the task: the calendar event that is on now, otherwise the app in front.
    /// A task the user typed stays until the next reset.
    func refreshTask() {
        if task?.source == .manual, isActive { return }
        if let event = AgendaStore.shared.eventNow() {
            task = FocusTask(name: event, source: .calendar)
            return
        }
        guard let app = Self.frontApp() else {
            task = nil
            return
        }
        let name = app.localizedName ?? String(localized: "Work")
        let bundle = app.bundleIdentifier ?? name
        // A Claude Code session in that app tells which project it is.
        let project = ClaudeSessions.shared.sessions.values
            .filter { $0.host.bundleId == app.bundleIdentifier }
            .max { $0.lastEventAt < $1.lastEventAt }?.project
        let key = project.map { "\(bundle)|\($0)" } ?? bundle
        let guess = learned[key] ?? learned[bundle] ?? Self.defaultTask(for: bundle, name: name)
        task = FocusTask(name: guess, source: .automatic(app: name, project: project), learnKey: key)
    }

    /// The user typed a task. When it corrects a guess from an app, remember it for next time.
    func setTask(_ name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if let key = task?.learnKey, task?.name != trimmed {
            learned[key] = trimmed
            defaults.set(learned, forKey: Key.learned)
        }
        task = FocusTask(name: trimmed, source: .manual, learnKey: task?.learnKey)
    }

    func forget(_ key: String) {
        learned[key] = nil
        defaults.set(learned, forKey: Key.learned)
    }

    /// The app in front, leaving out wisp itself and macOS's own screens (login window,
    /// screen saver), which say nothing about the work.
    private static func frontApp() -> NSRunningApplication? {
        guard let app = NSWorkspace.shared.frontmostApplication,
              let id = app.bundleIdentifier,
              id != Bundle.main.bundleIdentifier,
              !["com.apple.loginwindow", "com.apple.ScreenSaver.Engine"].contains(id),
              app.activationPolicy == .regular else { return nil }
        return app
    }

    private static func defaultTask(for bundle: String, name: String) -> String {
        let id = bundle.lowercased()
        let coding = ["com.jetbrains.", "com.microsoft.vscode", "com.apple.dt.xcode", "com.apple.terminal",
                      "com.googlecode.iterm2", "dev.warp.", "com.mitchellh.ghostty", "dev.zed."]
        if coding.contains(where: { id.hasPrefix($0) }) { return String(localized: "Coding") }
        return name
    }

    // MARK: - Do not disturb

    /// Runs one of the user's Shortcuts by name, if it exists. macOS lets apps switch a
    /// Focus mode only through Shortcuts, so "Do not disturb" relies on these two.
    private static func runShortcut(_ name: String) {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/shortcuts")
        task.arguments = ["run", name]
        task.standardOutput = FileHandle.nullDevice
        task.standardError = FileHandle.nullDevice
        try? task.run()
    }
}
