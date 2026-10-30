import SwiftUI

/// Music: artwork, title, progress and controls on the left; a live spectrum on the
/// right (boards 9.1–9.5). The output device sits in the tab bar.
struct MusicTab: View {
    @ObservedObject var player: NowPlaying

    var body: some View {
        HStack(spacing: 10) {
            Card {
                if let track = player.track {
                    PlayerCard(track: track, player: player)
                } else {
                    NothingPlayingCard()
                }
            }
            .frame(width: 331)

            // The card never grows past the fixed content height.
            Card { SideCard(player: player, spectrum: .shared) }
                .frame(maxHeight: .infinity)
                .clipped()
        }
    }
}

private struct PlayerCard: View {
    let track: NowPlayingTrack
    let player: NowPlaying

    var body: some View {
        HStack(spacing: 14) {
            Artwork(image: track.artwork, size: 120, corner: 14, isVideo: track.isVideo)
                .onTapGesture { player.openSource() }
                .help(String(localized: "Open \(track.sourceName ?? String(localized: "the source"))"))

            VStack(alignment: .leading, spacing: 0) {
                Text(track.sourceLabel.uppercased())
                    .font(.system(size: 10.5, weight: .medium))
                    .tracking(0.6)
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(1)
                Text(track.title)
                    .font(.system(size: 15, weight: .semibold))
                    .lineLimit(1)
                    .padding(.top, 2)
                Text([track.artist, track.album].filter { !$0.isEmpty }.joined(separator: " · "))
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(1)
                    .padding(.top, 1)

                Spacer(minLength: 6)
                Progress(track: track)
                Spacer(minLength: 6)

                HStack(spacing: 0) {
                    ControlButton(symbol: "backward.end.fill", action: player.previousTrack)
                    PlayPauseButton(isPlaying: track.isPlaying, action: player.playPause)
                        .padding(.horizontal, 6)
                    ControlButton(symbol: "forward.end.fill", action: player.nextTrack)
                    Spacer(minLength: 0)
                }
            }
            .padding(.vertical, 2)
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }
}

/// Board 9.4: nothing is playing.
private struct NothingPlayingCard: View {
    var body: some View {
        HStack(spacing: 14) {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Theme.control)
                .frame(width: 120, height: 120)
                .overlay(Image(systemName: "music.note")
                    .font(.system(size: 44, weight: .light))
                    .foregroundStyle(Theme.textSecondary.opacity(0.6)))

            VStack(alignment: .leading, spacing: 4) {
                Text("NOTHING PLAYING")
                    .font(.system(size: 10.5, weight: .medium))
                    .tracking(0.6)
                    .foregroundStyle(Theme.textSecondary)
                Text("Nothing is playing")
                    .font(.system(size: 15, weight: .semibold))
                Text("Start something in Spotify or YouTube")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(1)
                Button("Open Spotify") { Self.openSpotify() }
                    .buttonStyle(WhiteButtonStyle())
                    .padding(.top, 8)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    private static func openSpotify() {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.spotify.client") {
            NSWorkspace.shared.openApplication(at: url, configuration: .init())
        } else if let web = URL(string: "https://open.spotify.com") {
            NSWorkspace.shared.open(web)
        }
    }
}

struct WhiteButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(.black)
            .padding(.horizontal, 14)
            .frame(height: Theme.buttonHeight + 2)
            .background(RoundedRectangle(cornerRadius: Theme.buttonCorner, style: .continuous).fill(.white))
            .scaleEffect(configuration.isPressed ? 0.95 : 1)
            .animation(.spring(response: 0.2, dampingFraction: 0.6), value: configuration.isPressed)
    }
}

private struct Progress: View {
    let track: NowPlayingTrack

    var body: some View {
        // Ticks once a second, only while the Music tab is visible.
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let position = track.position(at: context.date)
            let fraction = track.duration > 0 ? position / track.duration : 0
            VStack(spacing: 4) {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.white.opacity(0.18))
                        Capsule().fill(Color.white).frame(width: geo.size.width * fraction)
                    }
                }
                .frame(height: 4)
                HStack {
                    Text(Self.time(position))
                    Spacer()
                    Text(track.duration > 0 ? "-" + Self.time(track.duration - position) : "")
                }
                .font(.system(size: 10.5))
                .monospacedDigit()
                .foregroundStyle(Theme.textSecondary)
            }
        }
    }

    static func time(_ seconds: Double) -> String {
        let s = max(0, Int(seconds.rounded()))
        return s >= 3600 ? String(format: "%d:%02d:%02d", s / 3600, s / 60 % 60, s % 60)
                         : String(format: "%d:%02d", s / 60, s % 60)
    }
}

/// Previous / next: a round glass key that lights up on hover, a bounce on click.
private struct ControlButton: View {
    let symbol: String
    let action: () -> Void
    @State private var hovered = false
    @State private var taps = 0

    var body: some View {
        Button {
            taps += 1
            action()
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 14))
                .foregroundStyle(hovered ? Theme.textPrimary : Theme.textPrimary.opacity(0.8))
                .symbolEffect(.bounce, value: taps)
                .frame(width: 32, height: 32)
                .glass(in: Circle())
                .contentShape(Circle())
        }
        .buttonStyle(PressableStyle())
        .onHover { hovered = $0 }
        .animation(.easeOut(duration: 0.15), value: hovered)
    }
}

/// The play / pause key: a slightly larger glass key that grows a little on hover;
/// the icon morphs between states.
private struct PlayPauseButton: View {
    let isPlaying: Bool
    let action: () -> Void
    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white)
                .contentTransition(.symbolEffect(.replace))
                .frame(width: 40, height: 34)
                .glass(in: RoundedRectangle(cornerRadius: 12, style: .continuous),
                       tint: .white.opacity(hovered ? 0.22 : 0.14))
                .scaleEffect(hovered ? 1.06 : 1)
        }
        .buttonStyle(PressableStyle())
        .onHover { hovered = $0 }
        .animation(.spring(response: 0.25, dampingFraction: 0.7), value: hovered)
    }
}

/// Sinks in while pressed, springs back on release.
struct PressableStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.88 : 1)
            .animation(.spring(response: 0.2, dampingFraction: 0.6), value: configuration.isPressed)
    }
}

/// Right side of the tab bar on the Music tab: the current output device.
struct MusicToolbar: View {
    @State private var device = AudioOutput.current

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: device?.isBluetooth == true ? "headphones" : "hifispeaker")
            Text(device?.name ?? "")
                .lineLimit(1)
        }
        .font(.system(size: 12))
        .foregroundStyle(Theme.textSecondary)
        .onAppear { device = AudioOutput.current }
    }
}

// MARK: - Shared music pieces

struct Artwork: View {
    let image: NSImage?
    var size: CGFloat
    var corner: CGFloat
    /// Without artwork a video gets a dark red tile with a play icon (board 9.2).
    var isVideo = false

    var body: some View {
        RoundedRectangle(cornerRadius: corner, style: .continuous)
            .fill(isVideo ? Color(hex: 0x3A1E22) : Color(hex: 0x34486B))
            .overlay {
                if let image {
                    Image(nsImage: image).resizable().aspectRatio(contentMode: .fill)
                } else {
                    Image(systemName: isVideo ? "play.rectangle" : "music.note")
                        .font(.system(size: size * 0.4, weight: .light))
                        .foregroundStyle(.white.opacity(0.85))
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: corner, style: .continuous))
            .frame(width: size, height: size)
    }
}

/// Green bars that bounce while playing and sink to grey dots when paused.
struct Equalizer: View {
    let playing: Bool
    var barWidth: CGFloat = 2.5
    var spacing: CGFloat = 2

    var body: some View {
        // A fresh view per play state, so the repeating bounce starts from scratch.
        Bars(playing: playing, barWidth: barWidth, spacing: spacing)
            .id(playing)
    }

    private struct Bars: View {
        let playing: Bool
        let barWidth: CGFloat
        let spacing: CGFloat
        @State private var up = false

        private let durations: [Double] = [0.42, 0.55, 0.38, 0.5]

        var body: some View {
            HStack(alignment: .bottom, spacing: spacing) {
                ForEach(durations.indices, id: \.self) { i in
                    Capsule()
                        .fill(playing ? Theme.ok : Theme.textSecondary.opacity(0.5))
                        .frame(width: barWidth)
                        .scaleEffect(y: playing ? (up ? 1 : 0.3 + 0.15 * Double(i % 2)) : barWidth / 16,
                                     anchor: .bottom)
                        .animation(.easeInOut(duration: durations[i]).repeatForever(autoreverses: true),
                                   value: up)
                }
            }
            .onAppear { if playing { up = true } }
        }
    }
}
