import AppKit
import CoreImage
import Foundation

/// The players Settings → Music can switch off.
enum MusicSource: String, CaseIterable {
    case spotify, appleMusic, browser
}

struct NowPlayingTrack: Equatable {
    let title: String
    let artist: String
    let album: String
    let isPlaying: Bool
    let sourceBundleId: String?
    let artwork: NSImage?
    let tint: NSColor?
    let duration: Double
    let elapsed: Double
    let elapsedAt: Date
    let rate: Double

    /// Playback position now, extrapolated from the last report.
    func position(at date: Date = Date()) -> Double {
        guard duration > 0 else { return 0 }
        let moving = isPlaying ? date.timeIntervalSince(elapsedAt) * max(rate, 0) : 0
        return min(duration, max(0, elapsed + moving))
    }

    /// "Brave Browser", "Spotify"…
    var sourceName: String? {
        sourceURL.map { FileManager.default.displayName(atPath: $0.path).replacingOccurrences(of: ".app", with: "") }
    }

    var sourceIcon: NSImage? { sourceURL.map { NSWorkspace.shared.icon(forFile: $0.path) } }

    /// Playing in a web browser (YouTube and other video or audio sites).
    var isVideo: Bool {
        guard let id = sourceBundleId else { return false }
        return Self.browsers.contains { id.hasPrefix($0) }
    }

    /// Which switch in Settings → Music this falls under; nil for any other app.
    var source: MusicSource? {
        if isVideo { return .browser }
        switch sourceBundleId {
        case "com.spotify.client": return .spotify
        case "com.apple.Music":    return .appleMusic
        default:                   return nil
        }
    }

    /// Small label above the title: "Spotify", "Muziek", "Brave Browser"…
    var sourceLabel: String { sourceName ?? String(localized: "Now playing") }

    private static let browsers = [
        "com.apple.Safari", "com.google.Chrome", "com.brave.Browser", "company.thebrowser",
        "org.mozilla.firefox", "com.microsoft.edgemac", "com.operasoftware", "com.vivaldi",
    ]

    private var sourceURL: URL? {
        sourceBundleId.flatMap { NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0) }
    }

    static func == (a: Self, b: Self) -> Bool {
        a.title == b.title && a.artist == b.artist && a.album == b.album
            && a.isPlaying == b.isPlaying && a.sourceBundleId == b.sourceBundleId
            && a.artwork === b.artwork && a.duration == b.duration
            && a.elapsed == b.elapsed && a.elapsedAt == b.elapsedAt
    }
}

/// System-wide "now playing": whatever macOS shows in Control Center (YouTube in a
/// browser, Spotify, Music…). MediaRemote refuses third-party processes since macOS 15.4,
/// so the Apple-signed /usr/bin/perl runs our bundled NowPlayingBridge dylib, which
/// streams JSON lines on stdout and takes commands on stdin. Event-driven, no polling.
@MainActor
final class NowPlaying: ObservableObject {
    static let shared = NowPlaying()

    /// What plays, unless its player is switched off in Settings → Music.
    @Published private(set) var track: NowPlayingTrack?
    /// True while something plays, and for a minute after it pauses, so the closed-notch
    /// wings don't flicker on track changes and show the paused state for a while.
    @Published private(set) var isActive = false

    /// What macOS reports, whatever the switches say.
    private var reported: NowPlayingTrack?
    private var process: Process?
    private var input: FileHandle?
    private var buffer = Data()
    private var restarts = 0
    private var hideWork: DispatchWorkItem?
    /// `hideWork` is the short grace, for when there is no track.
    private var hidingEmpty = false
    /// Board 9.6: after a pause the wings stay (greyed) for a minute, then go.
    private let pauseGrace: TimeInterval = 60
    /// No track at all: the wings would be empty, so this only bridges a track change.
    private let emptyGrace: TimeInterval = 3

    private static let perlScript = """
    use DynaLoader;
    my $lib = DynaLoader::dl_load_file($ARGV[0], 0) or die DynaLoader::dl_error();
    my $sym = DynaLoader::dl_find_symbol($lib, "wisp_now_playing_run") or die "symbol missing";
    &{DynaLoader::dl_install_xsub("main::run", $sym)};
    """

    func start() {
        guard process == nil,
              let dylib = Bundle.main.url(forResource: "libNowPlayingBridge", withExtension: "dylib")
        else { return }

        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/perl")
        p.arguments = ["-e", Self.perlScript, dylib.path]
        let out = Pipe(), inPipe = Pipe()
        p.standardOutput = out
        p.standardInput = inPipe
        p.standardError = FileHandle.nullDevice

        out.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            Task { @MainActor in NowPlaying.shared.receive(data) }
        }
        p.terminationHandler = { _ in
            Task { @MainActor in NowPlaying.shared.bridgeExited() }
        }
        do {
            try p.run()
            process = p
            input = inPipe.fileHandleForWriting
        } catch {
            NSLog("wisp: now playing bridge failed to launch: \(error.localizedDescription)")
        }
    }

    private func bridgeExited() {
        process = nil
        input = nil
        buffer.removeAll()
        apply(nil)
        // A few retries with backoff; a bridge that keeps dying stays off until relaunch.
        guard restarts < 3 else { return }
        restarts += 1
        DispatchQueue.main.asyncAfter(deadline: .now() + Double(restarts) * 5) { [weak self] in
            self?.start()
        }
    }

    // MARK: - Controls

    func playPause()     { send("toggle") }
    func nextTrack()     { send("next") }
    func previousTrack() { send("previous") }

    /// Brings the app that is playing (the browser for YouTube) to the front.
    func openSource() {
        guard let id = track?.sourceBundleId else { return }
        if let app = NSRunningApplication.runningApplications(withBundleIdentifier: id).first {
            app.activate()
        } else if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) {
            NSWorkspace.shared.open(url)
        }
    }

    private func send(_ command: String) {
        input?.write(Data((command + "\n").utf8))
    }

    // MARK: - Incoming lines

    private func receive(_ data: Data) {
        guard !data.isEmpty else { return }
        buffer.append(data)
        while let nl = buffer.firstIndex(of: 0x0A) {
            let line = buffer[buffer.startIndex..<nl]
            buffer.removeSubrange(buffer.startIndex...nl)
            guard let json = try? JSONSerialization.jsonObject(with: line) as? [String: Any] else { continue }
            handle(json)
        }
    }

    private func handle(_ json: [String: Any]) {
        guard let title = json["title"] as? String, !title.isEmpty else { apply(nil); return }

        // Artwork is only sent when it changes ("" = the new item has none).
        var artwork = reported?.artwork
        var tint = reported?.tint
        if let b64 = json["artwork"] as? String {
            artwork = Data(base64Encoded: b64).flatMap(NSImage.init(data:))
            tint = artwork.flatMap(Self.averageColor)
        }
        apply(NowPlayingTrack(
            title: title,
            artist: json["artist"] as? String ?? "",
            album: json["album"] as? String ?? "",
            isPlaying: json["playing"] as? Bool ?? false,
            sourceBundleId: (json["parent"] as? String) ?? (json["bundle"] as? String),
            artwork: artwork,
            tint: tint,
            duration: json["duration"] as? Double ?? 0,
            elapsed: json["elapsed"] as? Double ?? 0,
            elapsedAt: (json["timestamp"] as? Double).map(Date.init(timeIntervalSince1970:)) ?? Date(),
            rate: json["rate"] as? Double ?? 1
        ))
    }

    /// A player was switched on or off in Settings → Music.
    func sourcesChanged() { apply(reported) }

    private func apply(_ report: NowPlayingTrack?) {
        reported = report
        var new = report
        if let source = report?.source, Preferences.shared.hiddenMusicSources.contains(source) { new = nil }
        if track != new { track = new }

        // On immediately, off only after a while.
        if new?.isPlaying == true {
            hideWork?.cancel()
            hideWork = nil
            if !isActive { isActive = true }
        } else if isActive, hideWork == nil || hidingEmpty != (new == nil) {
            // More reports of the same kind don't extend the grace; a paused track replaces
            // the short one for an empty notch, and the other way round.
            hideWork?.cancel()
            hidingEmpty = new == nil
            let work = DispatchWorkItem { [weak self] in
                self?.isActive = false
                self?.hideWork = nil
            }
            hideWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + (new == nil ? emptyGrace : pauseGrace), execute: work)
        }
    }

    // MARK: - Artwork tint

    /// Average artwork colour, lifted so it stays visible on black.
    private static func averageColor(_ image: NSImage) -> NSColor? {
        guard let tiff = image.tiffRepresentation, let ci = CIImage(data: tiff),
              let filter = CIFilter(name: "CIAreaAverage",
                                    parameters: [kCIInputImageKey: ci,
                                                 kCIInputExtentKey: CIVector(cgRect: ci.extent)]),
              let output = filter.outputImage else { return nil }
        var px = [UInt8](repeating: 0, count: 4)
        CIContext(options: [.workingColorSpace: NSNull()])
            .render(output, toBitmap: &px, rowBytes: 4,
                    bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
                    format: .RGBA8, colorSpace: nil)
        let c = NSColor(red: CGFloat(px[0]) / 255, green: CGFloat(px[1]) / 255,
                        blue: CGFloat(px[2]) / 255, alpha: 1)
        guard let hsb = c.usingColorSpace(.deviceRGB) else { return c }
        return NSColor(hue: hsb.hueComponent,
                       saturation: min(1, hsb.saturationComponent * 1.2),
                       brightness: max(0.75, hsb.brightnessComponent), alpha: 1)
    }
}
