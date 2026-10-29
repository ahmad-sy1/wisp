import Foundation

/// Live spectrum of what is playing, for the Music tab and the closed-notch wings.
///
/// Runs only while something shows it and music plays; otherwise the tap is torn
/// down and nothing runs.
@MainActor
final class Spectrum: ObservableObject {
    static let shared = Spectrum()
    nonisolated static let bandCount = 24
    nonisolated static let miniBandCount = 8

    enum Consent: String { case notAsked, allowed, declined }

    @Published private(set) var frame = SpectrumFrame.silent
    @Published private(set) var isRunning = false
    @Published private(set) var consent: Consent {
        didSet { UserDefaults.standard.set(consent.rawValue, forKey: Self.consentKey) }
    }

    private static let consentKey = "spectrumConsent"
    private let tap = AudioTap()
    private var source: String?
    private var playing = false
    /// Who currently shows the spectrum ("tab", "wings"); it runs only while someone does.
    private var viewers: Set<String> = []
    private var lastPublish = Date.distantPast

    private init() {
        consent = Consent(rawValue: UserDefaults.standard.string(forKey: Self.consentKey) ?? "") ?? .notAsked
    }

    /// The eight wider bands for the closed notch.
    var miniBands: [Float] {
        let group = Self.bandCount / Self.miniBandCount
        return (0..<Self.miniBandCount).map { i in
            frame.bands[(i * group)..<((i + 1) * group)].max() ?? 0
        }
    }

    func allow() {
        consent = .allowed
        reevaluate()
    }

    func decline() {
        consent = .declined
        reevaluate()
    }

    /// A view that shows the spectrum appeared (`true`) or went away.
    func setVisible(_ visible: Bool, by viewer: String) {
        if visible { viewers.insert(viewer) } else { viewers.remove(viewer) }
        reevaluate()
    }

    /// What plays now: the app's bundle id and whether it is playing.
    func setPlayback(source newSource: String?, playing isPlaying: Bool) {
        let sourceChanged = newSource != source
        source = newSource
        playing = isPlaying
        if sourceChanged && isRunning { stop() }
        reevaluate()
    }

    private func reevaluate() {
        let want = consent == .allowed && playing && !viewers.isEmpty
        if want && !isRunning { start() } else if !want && isRunning { stop() }
    }

    private func start() {
        let deliver: @Sendable (SpectrumFrame) -> Void = { frame in
            Task { @MainActor in Spectrum.shared.publish(frame) }
        }
        do {
            try tap.start(bundlePrefix: source, onFrame: deliver)
            isRunning = true
        } catch AudioTap.TapError.noProcess {
            // The playing app isn't an audio process we can see (yet): listen to everything.
            do {
                try tap.start(bundlePrefix: nil, onFrame: deliver)
                isRunning = true
            } catch {
                isRunning = false
            }
        } catch {
            NSLog("wisp: spectrum tap failed: \(error)")
            isRunning = false
        }
    }

    private func stop() {
        guard isRunning else { return }
        tap.stop()
        isRunning = false
        frame = .silent
    }

    private func publish(_ new: SpectrumFrame) {
        guard isRunning else { return }
        // 30 updates a second is plenty for the eye.
        let now = Date()
        guard now.timeIntervalSince(lastPublish) >= 1.0 / 30 else { return }
        lastPublish = now
        frame = new
    }
}
