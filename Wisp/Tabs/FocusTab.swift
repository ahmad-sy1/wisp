import SwiftUI

/// Focus timer (board 4): the ring and the task on the left, duration and options on
/// the right. Redraws once a second while a session runs and the tab is visible.
struct FocusTab: View {
    @ObservedObject var focus: FocusStore

    var body: some View {
        HStack(spacing: 10) {
            Card { TimerCard(focus: focus) }
                .frame(width: 315)
            Card { OptionsCard(focus: focus) }
        }
        .onAppear {
            focus.loadToday()
            focus.refreshTask()
        }
    }
}

// MARK: - Timer

private struct TimerCard: View {
    @ObservedObject var focus: FocusStore
    @ObservedObject private var prefs = Preferences.shared

    var body: some View {
        // Only a running session needs a ticking clock.
        if focus.phase.isRunning {
            TimelineView(.periodic(from: .now, by: 1)) { context in content(now: context.date) }
        } else {
            content(now: .now)
        }
    }

    private func content(now: Date) -> some View {
        HStack(spacing: 22) {
            FocusRing(progress: focus.progress(at: now), color: prefs.accent.color, lineWidth: 7) {
                VStack(spacing: 0) {
                    Text(verbatim: FocusClock.text(focus.remaining(at: now)))
                        .font(.system(size: 26, weight: .bold))
                        .monospacedDigit()
                    Text(stateLabel)
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.textSecondary)
                }
            }
            .frame(width: 108, height: 108)

            VStack(alignment: .leading, spacing: 10) {
                TaskTitle(focus: focus)
                HStack(spacing: 8) {
                    if focus.phase.isRunning {
                        Button("Pause") { focus.pause() }.buttonStyle(AccentButtonStyle())
                    } else {
                        Button("Start") { focus.start() }.buttonStyle(AccentButtonStyle())
                    }
                    Button("Reset") { focus.reset() }
                        .buttonStyle(SecondaryButtonStyle())
                        .disabled(focus.phase == .idle)
                }
                TaskSource(task: focus.task)
            }
        }
        .padding(.horizontal, 20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    private var stateLabel: String {
        switch focus.phase {
        case .idle: String(localized: "ready")
        case .running: String(localized: "focus")
        case .paused: String(localized: "paused")
        case .finished: String(localized: "done")
        }
    }
}

/// The task name with a pencil; a click on it turns it into a text field.
private struct TaskTitle: View {
    @ObservedObject var focus: FocusStore
    @State private var editing = false
    @State private var draft = ""
    @FocusState private var fieldFocused: Bool

    var body: some View {
        if editing {
            TextField("What are you working on?", text: $draft)
                .textFieldStyle(.plain)
                .font(.system(size: 15, weight: .semibold))
                .focused($fieldFocused)
                .onSubmit {
                    focus.setTask(draft)
                    editing = false
                }
                .onExitCommand { editing = false }
                .onAppear { fieldFocused = true }
                .frame(width: 150)
        } else {
            Button {
                draft = focus.task?.name ?? ""
                editing = true
            } label: {
                HStack(spacing: 6) {
                    Text(focus.task?.name ?? String(localized: "Focus"))
                        .font(.system(size: 15, weight: .semibold))
                        .lineLimit(1)
                    Image(systemName: "pencil")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.textSecondary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Change the task")
        }
    }
}

/// "Automatic · IntelliJ · wisp" (green), "From your calendar", "Chosen by you" (grey).
private struct TaskSource: View {
    let task: FocusTask?

    var body: some View {
        if let task {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Circle()
                    .fill(task.source == .manual ? Theme.textSecondary : Theme.ok)
                    .frame(width: 7, height: 7)
                Text(label(task.source))
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func label(_ source: FocusTask.Source) -> String {
        switch source {
        case .calendar: String(localized: "From your calendar")
        case .manual: String(localized: "Chosen by you")
        case .automatic(let app, let project?): String(localized: "Automatic · \(app) · \(project)")
        case .automatic(let app, nil): String(localized: "Automatic · \(app) active")
        }
    }
}

// MARK: - Options

private struct OptionsCard: View {
    @ObservedObject var focus: FocusStore

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Duration")
                .font(.system(size: 12))
                .foregroundStyle(Theme.textSecondary)
            HStack(spacing: 6) {
                ForEach(FocusStore.durations, id: \.self) { minutes in
                    DurationPill(minutes: minutes, selected: focus.minutes == minutes) {
                        focus.minutes = minutes
                    }
                    .disabled(focus.isActive)
                }
            }
            Toggle("Do not disturb during focus", isOn: $focus.doNotDisturb)
                .help("Runs your Shortcuts “\(FocusStore.shortcutOn)” and “\(FocusStore.shortcutOff)”")
            Toggle("Start music when it begins", isOn: $focus.startMusic)
        }
        .toggleStyle(.checkbox)
        .font(.system(size: 13))
        .padding(.horizontal, 14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }
}

private struct DurationPill: View {
    let minutes: Int
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text("\(minutes) min")
                .font(.system(size: 13, weight: selected ? .semibold : .regular))
                .foregroundStyle(selected ? Theme.textPrimary : Theme.textSecondary)
                .frame(maxWidth: .infinity)
                .frame(height: 30)
                .background(RoundedRectangle(cornerRadius: Theme.buttonCorner, style: .continuous)
                    .fill(selected ? Theme.activeTab : Theme.control))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Shared pieces

/// A progress ring that empties clockwise from the top, with content in the middle.
struct FocusRing<Content: View>: View {
    let progress: Double
    let color: Color
    let lineWidth: CGFloat
    @ViewBuilder var content: Content

    var body: some View {
        ZStack {
            Circle().stroke(Theme.control, lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: max(0, min(1, progress)))
                .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
            content
        }
        .padding(lineWidth / 2)
    }
}

enum FocusClock {
    /// "24:13", "90:00".
    static func text(_ seconds: TimeInterval) -> String {
        let s = Int(seconds.rounded(.up))
        return String(format: "%02d:%02d", s / 60, s % 60)
    }
}

extension FocusStore.Phase {
    var isRunning: Bool {
        if case .running = self { return true }
        return false
    }
}

/// Right side of the tab bar on the Focus tab: "Today 3 sessions · 1h 45m".
struct FocusToolbar: View {
    @ObservedObject var focus: FocusStore

    var body: some View {
        let minutes = Int(focus.todaySeconds / 60)
        let time = minutes < 60
            ? String(localized: "\(minutes)m")
            : String(localized: "\(minutes / 60)h \(minutes % 60)m")
        Text("Today \(focus.todaySessions) sessions · \(time)")
            .font(.system(size: 13))
            .foregroundStyle(Theme.textSecondary)
            .lineLimit(1)
    }
}
