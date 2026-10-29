import AppKit
import CoreImage
import Foundation

/// System-wide "now playing": whatever macOS shows in Control Center (YouTube in a
/// browser, Spotify, Music…). MediaRemote refuses third-party processes since macOS 15.4,
/// so we run the Apple-signed /usr/bin/perl with our bundled NowPlayingBridge dylib,
/// which streams JSON lines on stdout and takes commands on stdin. Event-driven, no polling.
@MainActor
final class NowPlayingService {
    static let shared = NowPlayingService()
    private init() {}

    private var process: Process?
    private var input: FileHandle?
    private var buffer = Data()
    private var restarts = 0
    private var hideWork: DispatchWorkItem?

    /// Keeps the closed-notch indicator through short gaps (track change, buffering).
    private let pauseGrace: TimeInterval = 2.0

    private static let perlScript = """
    use DynaLoader;
    my $lib = DynaLoader::dl_load_file($ARGV[0], 0) or die DynaLoader::dl_error();
    my $sym = DynaLoader::dl_find_symbol($lib, "nb_now_playing_run") or die "symbol missing";
    &{DynaLoader::dl_install_xsub("main::run", $sym)};
    """

    func start() {
        #if !APPSTORE
        guard process == nil,
              let dylib = Bundle.main.url(forResource: "libNowPlayingBridge", withExtension: "dylib")
        else { return }

        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/perl")
        p.arguments = ["-e", Self.perlScript, dylib.path]
        let out = Pipe(), inPipe = Pipe(), err = Pipe()
        p.standardOutput = out
        p.standardInput = inPipe
        p.standardError = err

        out.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            Task { @MainActor in NowPlayingService.shared.receive(data) }
        }
        err.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            appendAppLog("nowplaying.log", String(decoding: data, as: UTF8.self))
        }
        p.terminationHandler = { proc in
            let status = proc.terminationStatus
            Task { @MainActor in NowPlayingService.shared.bridgeExited(status: status) }
        }
        do {
            try p.run()
            process = p
            input = inPipe.fileHandleForWriting
        } catch {
            appendAppLog("nowplaying.log", "launch failed: \(error)")
        }
        #endif
    }

    private func bridgeExited(status: Int32) {
        appendAppLog("nowplaying.log", "bridge exited (\(status))")
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
        let previous = AppState.shared.nowPlaying
        let bundleId = (json["parent"] as? String) ?? (json["bundle"] as? String)

        // Artwork is only sent when it changes ("" = the new item has none).
        var artwork = previous?.artwork
        var tint = previous?.tint
        if let b64 = json["artwork"] as? String {
            artwork = Data(base64Encoded: b64).flatMap(NSImage.init(data:))
            tint = artwork.flatMap(Self.averageColor)
        }
        apply(NowPlayingTrack(
            title: title,
            artist: json["artist"] as? String ?? "",
            album: json["album"] as? String ?? "",
            isPlaying: json["playing"] as? Bool ?? false,
            sourceBundleId: bundleId,
            artwork: artwork,
            tint: tint,
            duration: json["duration"] as? Double ?? 0,
            elapsed: json["elapsed"] as? Double ?? 0,
            elapsedAt: (json["timestamp"] as? Double).map(Date.init(timeIntervalSince1970:)) ?? Date(),
            rate: json["rate"] as? Double ?? 1
        ))
    }

    private func apply(_ track: NowPlayingTrack?) {
        let state = AppState.shared
        if state.nowPlaying != track { state.nowPlaying = track }

        // Closed-notch indicator: on immediately, off only after a short pause.
        hideWork?.cancel()
        if track?.isPlaying == true {
            if !state.musicActive { state.musicActive = true }
        } else if state.musicActive {
            let work = DispatchWorkItem { AppState.shared.musicActive = false }
            hideWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + pauseGrace, execute: work)
        }
    }

    // MARK: - Controls

    func playPause()     { send("toggle") }
    func nextTrack()     { send("next") }
    func previousTrack() { send("previous") }

    /// Brings the app that is playing (the browser for YouTube) to the front.
    func openSource() {
        guard let id = AppState.shared.nowPlaying?.sourceBundleId else { return }
        if let app = NSRunningApplication.runningApplications(withBundleIdentifier: id).first {
            app.activate()
        } else if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) {
            NSWorkspace.shared.open(url)
        }
    }

    private func send(_ command: String) {
        input?.write(Data((command + "\n").utf8))
    }

    // MARK: - Artwork tint

    /// Average artwork colour, lifted so it stays visible on the black notch.
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

    func progress(at date: Date = Date()) -> Double {
        duration > 0 ? position(at: date) / duration : 0
    }

    /// "Brave Browser", "Spotify"… for the card header.
    var sourceName: String {
        guard let id = sourceBundleId,
              let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id)
        else { return "Now playing" }
        return FileManager.default.displayName(atPath: url.path)
            .replacingOccurrences(of: ".app", with: "")
    }

    var sourceIcon: NSImage? {
        guard let id = sourceBundleId,
              let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) else { return nil }
        return NSWorkspace.shared.icon(forFile: url.path)
    }

    static func == (a: Self, b: Self) -> Bool {
        a.title == b.title && a.artist == b.artist && a.album == b.album
            && a.isPlaying == b.isPlaying && a.sourceBundleId == b.sourceBundleId
            && a.artwork === b.artwork && a.duration == b.duration
            && a.elapsed == b.elapsed && a.elapsedAt == b.elapsedAt
    }
}
