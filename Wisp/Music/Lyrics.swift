import CryptoKit
import Foundation

struct LyricLine: Codable, Equatable, Sendable {
    let time: Double
    let text: String
}

/// Time-synced lyrics from LRCLIB (lrclib.net, free, no account).
///
/// Only artist, title, album and duration are sent. Results, including "not found",
/// are cached on disk so a song loads instantly the next time.
@MainActor
final class Lyrics: ObservableObject {
    static let shared = Lyrics()

    enum State: Equatable {
        case off, idle, loading
        case found([LyricLine])
        case notFound
    }

    @Published private(set) var state: State = .idle

    private var currentKey: String?
    private var task: Task<Void, Never>?

    /// Not-found results are tried again after a week (LRCLIB keeps growing).
    private static let retryNotFoundAfter: TimeInterval = 7 * 24 * 3600

    private static var cacheDir: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/wisp/lyrics", isDirectory: true)
    }

    var lines: [LyricLine] {
        if case .found(let lines) = state { return lines }
        return []
    }

    /// Index of the line being sung at `position` seconds.
    func lineIndex(at position: Double) -> Int? {
        lines.lastIndex { $0.time <= position + 0.25 }
    }

    /// Looks up lyrics when the track changes.
    func update(for track: NowPlayingTrack?, enabled: Bool) {
        guard enabled else {
            task?.cancel()
            currentKey = nil
            state = .off
            return
        }
        guard let track else {
            task?.cancel()
            currentKey = nil
            state = .idle
            return
        }
        let query = SongQuery(track: track)
        guard query.key != currentKey else { return }
        currentKey = query.key
        task?.cancel()

        if let cached = Self.readCache(query.key) {
            state = cached
            return
        }
        state = .loading
        task = Task { [weak self] in
            let result = await Self.fetch(query)
            guard !Task.isCancelled, let self, self.currentKey == query.key else { return }
            if let result {
                Self.writeCache(query.key, result)
                self.state = result
            } else {
                // Network trouble: say "not found" for now, but don't cache it.
                self.state = .notFound
            }
        }
    }

    // MARK: - LRCLIB

    /// nil means the request itself failed (offline); `.notFound` means LRCLIB has nothing.
    private static func fetch(_ query: SongQuery) async -> State? {
        var exact = URLComponents(string: "https://lrclib.net/api/get")!
        exact.queryItems = [
            URLQueryItem(name: "track_name", value: query.title),
            URLQueryItem(name: "artist_name", value: query.artist),
            URLQueryItem(name: "duration", value: String(Int(query.duration.rounded()))),
        ]
        if !query.album.isEmpty { exact.queryItems?.append(URLQueryItem(name: "album_name", value: query.album)) }

        switch await request(exact.url!) {
        case .failure: return nil
        case .success(let json):
            if let record = json as? [String: Any], let lines = synced(record) { return .found(lines) }
        }

        // No exact match (videos, different album name): search, and accept a result
        // whose length is within a few seconds of what's playing.
        var search = URLComponents(string: "https://lrclib.net/api/search")!
        search.queryItems = [URLQueryItem(name: "track_name", value: query.title),
                             URLQueryItem(name: "artist_name", value: query.artist)]
        switch await request(search.url!) {
        case .failure: return nil
        case .success(let json):
            let records = json as? [[String: Any]] ?? []
            let match = records.first { record in
                let duration = record["duration"] as? Double ?? 0
                return query.duration <= 0 || abs(duration - query.duration) <= 3
            }
            if let match, let lines = synced(match) { return .found(lines) }
            return .notFound
        }
    }

    private enum Response { case success(Any?), failure }

    private static func request(_ url: URL) async -> Response {
        var request = URLRequest(url: url, timeoutInterval: 8)
        request.setValue("wisp (https://github.com/ahmad-sy1/wisp)", forHTTPHeaderField: "User-Agent")
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse else { return .failure }
        if http.statusCode == 404 { return .success(nil) }
        guard http.statusCode == 200 else { return .failure }
        return .success(try? JSONSerialization.jsonObject(with: data))
    }

    /// Parses `[mm:ss.xx] text` lines; nil when the record has no synced lyrics.
    private static func synced(_ record: [String: Any]) -> [LyricLine]? {
        guard let lrc = record["syncedLyrics"] as? String, !lrc.isEmpty else { return nil }
        let lines: [LyricLine] = lrc.split(separator: "\n").compactMap { raw in
            guard raw.hasPrefix("["), let close = raw.firstIndex(of: "]") else { return nil }
            let stamp = raw[raw.index(after: raw.startIndex)..<close].split(separator: ":")
            guard stamp.count == 2, let minutes = Double(stamp[0]), let seconds = Double(stamp[1]) else { return nil }
            let text = raw[raw.index(after: close)...].trimmingCharacters(in: .whitespaces)
            return LyricLine(time: minutes * 60 + seconds, text: text.isEmpty ? "♪" : text)
        }
        return lines.isEmpty ? nil : lines
    }

    // MARK: - Cache

    private struct CacheEntry: Codable {
        let lines: [LyricLine]?
        let savedAt: Date
    }

    private static func cacheURL(_ key: String) -> URL {
        let hash = SHA256.hash(data: Data(key.utf8)).prefix(12).map { String(format: "%02x", $0) }.joined()
        return cacheDir.appendingPathComponent("\(hash).json")
    }

    private static func readCache(_ key: String) -> State? {
        guard let data = try? Data(contentsOf: cacheURL(key)),
              let entry = try? JSONDecoder().decode(CacheEntry.self, from: data) else { return nil }
        if let lines = entry.lines { return .found(lines) }
        return Date().timeIntervalSince(entry.savedAt) < retryNotFoundAfter ? .notFound : nil
    }

    private static func writeCache(_ key: String, _ state: State) {
        let lines: [LyricLine]?
        switch state {
        case .found(let l): lines = l
        case .notFound:     lines = nil
        default:            return
        }
        try? FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)
        if let data = try? JSONEncoder().encode(CacheEntry(lines: lines, savedAt: Date())) {
            try? data.write(to: cacheURL(key), options: .atomic)
        }
    }
}

/// Artist and title to search for. Video titles ("Artist - Title (Official Video)")
/// are split and cleaned; channel names lose suffixes like " - Topic" and "VEVO".
struct SongQuery {
    let artist: String
    let title: String
    let album: String
    let duration: Double

    var key: String { "\(artist.lowercased())|\(title.lowercased())|\(Int(duration.rounded()))" }

    init(track: NowPlayingTrack) {
        var artist = Self.cleanArtist(track.artist)
        var title = Self.cleanTitle(track.title)
        // "Artist - Title" in the title (typical for videos) wins over the channel name.
        for separator in [" - ", " – ", " — "] {
            let parts = title.components(separatedBy: separator)
            if parts.count == 2, !parts[0].isEmpty, !parts[1].isEmpty {
                artist = parts[0].trimmingCharacters(in: .whitespaces)
                title = parts[1].trimmingCharacters(in: .whitespaces)
                break
            }
        }
        self.artist = artist
        self.title = title
        album = track.album
        duration = track.duration
    }

    private static let noise = [
        "official video", "official music video", "official audio", "official lyric video",
        "lyric video", "lyrics", "audio", "visualizer", "visualiser", "music video", "video",
        "hd", "hq", "4k", "clip officiel", "videoclip",
    ]

    static func cleanTitle(_ raw: String) -> String {
        var title = raw
        // Drop bracketed noise: "(Official Video)", "[4K]", "【MV】"…
        let pattern = #"\s*[\(\[【]([^\)\]】]*)[\)\]】]"#
        if let regex = try? NSRegularExpression(pattern: pattern) {
            for match in regex.matches(in: title, range: NSRange(title.startIndex..., in: title)).reversed() {
                guard let whole = Range(match.range, in: title), let inner = Range(match.range(at: 1), in: title) else { continue }
                let content = title[inner].lowercased()
                if noise.contains(where: { content.contains($0) }) { title.removeSubrange(whole) }
            }
        }
        return title.replacingOccurrences(of: "  ", with: " ").trimmingCharacters(in: .whitespaces)
    }

    static func cleanArtist(_ raw: String) -> String {
        var artist = raw
        for suffix in [" - Topic", "VEVO", " Official"] where artist.hasSuffix(suffix) {
            artist = String(artist.dropLast(suffix.count))
        }
        return artist.trimmingCharacters(in: .whitespaces)
    }
}
