import SwiftUI

/// Music: artwork, title, progress and controls on the left; where it plays and the
/// volume on the right. macOS does not expose an "up next" queue, so there is none.
struct MusicTab: View {
    @ObservedObject var player: NowPlaying

    var body: some View {
        HStack(spacing: 10) {
            Card {
                if let track = player.track {
                    PlayerCard(track: track, player: player)
                } else {
                    VStack(spacing: 8) {
                        Image(systemName: "music.note")
                            .font(.system(size: 22, weight: .light))
                            .foregroundStyle(Theme.textSecondary)
                        Text("Er speelt niets")
                            .font(.system(size: 13, weight: .semibold))
                        Text("Start muziek in Spotify, Muziek of YouTube.")
                            .font(.system(size: 11))
                            .foregroundStyle(Theme.textSecondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .frame(width: 331)

            Card { OutputCard(player: player) }
        }
    }
}

private struct PlayerCard: View {
    let track: NowPlayingTrack
    let player: NowPlaying

    var body: some View {
        HStack(spacing: 14) {
            Artwork(image: track.artwork, size: 120, corner: 14)
                .onTapGesture { player.openSource() }
                .help("Open \(track.sourceName ?? "de bron")")

            VStack(alignment: .leading, spacing: 0) {
                Text(track.title)
                    .font(.system(size: 15, weight: .semibold))
                    .lineLimit(1)
                Text([track.artist, track.album].filter { !$0.isEmpty }.joined(separator: " · "))
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(1)
                    .padding(.top, 2)

                Spacer(minLength: 6)
                Progress(track: track)
                Spacer(minLength: 6)

                HStack(spacing: 0) {
                    ControlButton(symbol: "backward.end.fill", action: player.previousTrack)
                    PlayPauseButton(isPlaying: track.isPlaying, action: player.playPause)
                        .padding(.horizontal, 6)
                    ControlButton(symbol: "forward.end.fill", action: player.nextTrack)
                    Spacer(minLength: 0)
                    Equalizer(playing: track.isPlaying, barWidth: 3, spacing: 2.5)
                        .frame(height: 16)
                }
            }
            .padding(.vertical, 2)
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
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

/// Previous / next: a soft round highlight on hover, a bounce on click.
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
                .background(Circle().fill(hovered ? Theme.activeTab : .clear))
                .contentShape(Circle())
        }
        .buttonStyle(PressableStyle())
        .onHover { hovered = $0 }
        .animation(.easeOut(duration: 0.15), value: hovered)
    }
}

/// The white play / pause key: grows a little on hover, the icon morphs between states.
private struct PlayPauseButton: View {
    let isPlaying: Bool
    let action: () -> Void
    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.black)
                .contentTransition(.symbolEffect(.replace))
                .frame(width: 40, height: 34)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(.white.opacity(hovered ? 1 : 0.92)))
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

private struct OutputCard: View {
    @ObservedObject var player: NowPlaying
    @State private var volume: Double = Double(AudioOutput.volume ?? 0)
    @State private var hasVolume = AudioOutput.volume != nil
    @State private var device = AudioOutput.current

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Speelt via")
                .font(.system(size: 12))
                .foregroundStyle(Theme.textSecondary)

            if let track = player.track {
                Button { player.openSource() } label: {
                    row(icon: AnyView(appIcon(track.sourceIcon)),
                        title: track.sourceName ?? "Onbekende app", subtitle: "Openen")
                }
                .buttonStyle(.plain)
            }
            row(icon: AnyView(symbolTile(device?.isBluetooth == true ? "headphones" : "hifispeaker")),
                title: device?.name ?? "Geen uitvoer", subtitle: "Uitvoer")

            Spacer(minLength: 0)

            HStack(spacing: 10) {
                Image(systemName: "speaker.wave.1")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.textSecondary)
                Slider(value: $volume, in: 0...1) { _ in }
                    .controlSize(.mini)
                    .tint(.white)
                    .disabled(!hasVolume)
                    .onChange(of: volume) { _, new in AudioOutput.setVolume(Float(new)) }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onAppear {
            device = AudioOutput.current
            hasVolume = AudioOutput.volume != nil
            volume = Double(AudioOutput.volume ?? 0)
        }
    }

    private func row(icon: AnyView, title: String, subtitle: String) -> some View {
        HStack(spacing: 10) {
            icon
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.system(size: 13, weight: .semibold)).lineLimit(1)
                Text(subtitle).font(.system(size: 11)).foregroundStyle(Theme.textSecondary)
            }
        }
    }

    private func appIcon(_ image: NSImage?) -> some View {
        Group {
            if let image { Image(nsImage: image).resizable() } else { symbolTile("app") }
        }
        .frame(width: 30, height: 30)
    }

    private func symbolTile(_ symbol: String) -> some View {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(Theme.control)
            .frame(width: 30, height: 30)
            .overlay(Image(systemName: symbol).font(.system(size: 13)).foregroundStyle(Theme.textPrimary))
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

    var body: some View {
        RoundedRectangle(cornerRadius: corner, style: .continuous)
            .fill(Color(hex: 0x34486B))
            .overlay {
                if let image {
                    Image(nsImage: image).resizable().aspectRatio(contentMode: .fill)
                } else {
                    Image(systemName: "music.note")
                        .font(.system(size: size * 0.4, weight: .light))
                        .foregroundStyle(.white.opacity(0.85))
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: corner, style: .continuous))
            .frame(width: size, height: size)
    }
}

/// Green bars that bounce while playing and sink to dots when paused.
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
                        .fill(Theme.ok)
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
