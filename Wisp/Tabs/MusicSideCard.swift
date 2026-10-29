import SwiftUI

/// Right card of the Music tab: live lyrics or a live spectrum, with the volume below.
///
/// Lyrics show when LRCLIB has them, the spectrum otherwise. A manual choice wins
/// until the next song.
struct SideCard: View {
    @ObservedObject var player: NowPlaying
    @ObservedObject var lyrics: Lyrics
    @ObservedObject var spectrum: Spectrum

    enum Mode { case text, spectrum }

    /// The user's own choice, and the song it was made for.
    @State private var manual: (mode: Mode, song: String)?
    @State private var volume: Double = Double(AudioOutput.volume ?? 0)
    @State private var hasVolume = AudioOutput.volume != nil
    @State private var quality = AudioOutput.qualityLabel

    private var songKey: String? { player.track.map { SongQuery(track: $0).key } }

    private var hasLyrics: Bool { !lyrics.lines.isEmpty }

    private var mode: Mode {
        if let manual, manual.song == songKey, manual.mode == .spectrum || hasLyrics { return manual.mode }
        return hasLyrics ? .text : .spectrum
    }

    private var needsConsent: Bool {
        mode == .spectrum && spectrum.consent == .notAsked && player.track?.isPlaying == true
    }

    var body: some View {
        Group {
            if needsConsent {
                ConsentView(spectrum: spectrum)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    header
                    Group {
                        switch mode {
                        case .text:     LyricsView(lyrics: lyrics, track: player.track)
                        case .spectrum: SpectrumView(spectrum: spectrum, track: player.track)
                        }
                    }
                    .frame(maxHeight: .infinity)
                    volumeRow
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onAppear {
            refreshOutput()
            spectrum.setVisible(mode == .spectrum, by: "tab")
        }
        .onDisappear { spectrum.setVisible(false, by: "tab") }
        .onChange(of: mode) { _, new in spectrum.setVisible(new == .spectrum, by: "tab") }
    }

    // MARK: Header: Tekst | Spectrum, and a status on the right

    private var header: some View {
        HStack(spacing: 8) {
            HStack(spacing: 2) {
                segment("Tekst", .text, enabled: hasLyrics)
                segment("Spectrum", .spectrum, enabled: true)
            }
            .padding(2)
            .background(RoundedRectangle(cornerRadius: Theme.buttonCorner + 2, style: .continuous)
                .fill(Theme.control))

            Spacer(minLength: 4)
            Text(status)
                .font(.system(size: 11))
                .foregroundStyle(Theme.textSecondary)
                .lineLimit(2)
                .multilineTextAlignment(.trailing)
        }
    }

    private var status: String {
        guard player.track != nil else { return "Wacht op geluid" }
        if lyrics.state == .notFound && mode == .spectrum { return "Geen tekst gevonden" }
        return quality ?? ""
    }

    private func segment(_ title: String, _ value: Mode, enabled: Bool) -> some View {
        let active = mode == value
        return Button {
            if let songKey { manual = (value, songKey) }
        } label: {
            Text(title)
                .font(.system(size: 12, weight: active ? .semibold : .regular))
                .foregroundStyle(active ? Theme.textPrimary : Theme.textSecondary.opacity(enabled ? 1 : 0.45))
                .padding(.horizontal, 10)
                .frame(height: 24)
                .background(RoundedRectangle(cornerRadius: Theme.buttonCorner, style: .continuous)
                    .fill(active ? Theme.activeTab : .clear))
        }
        .buttonStyle(.plain)
        .disabled(!enabled || player.track == nil)
    }

    // MARK: Volume

    private var volumeRow: some View {
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

    private func refreshOutput() {
        hasVolume = AudioOutput.volume != nil
        volume = Double(AudioOutput.volume ?? 0)
        quality = AudioOutput.qualityLabel
    }
}

// MARK: - Lyrics (board 9.1)

private struct LyricsView: View {
    @ObservedObject var lyrics: Lyrics
    let track: NowPlayingTrack?

    var body: some View {
        // Four checks a second keep the highlighted line in step; only while visible.
        TimelineView(.periodic(from: .now, by: 0.25)) { context in
            let index = track.flatMap { lyrics.lineIndex(at: $0.position(at: context.date)) }
            let lines = lyrics.lines
            let playing = track?.isPlaying == true
            VStack(alignment: .leading, spacing: 4) {
                line(index.flatMap { $0 > 0 ? lines[$0 - 1].text : nil }, size: 11, weight: .regular,
                     color: Theme.textSecondary.opacity(0.7))
                line(index.map { lines[$0].text } ?? lines.first?.text, size: 15, weight: .semibold,
                     color: playing ? Theme.textPrimary : Theme.textSecondary)
                line(index.map { $0 + 1 < lines.count ? lines[$0 + 1].text : nil } ?? lines.dropFirst().first?.text,
                     size: 11, weight: .regular, color: Theme.textSecondary.opacity(0.7))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .animation(.easeInOut(duration: 0.25), value: index)
        }
    }

    private func line(_ text: String?, size: CGFloat, weight: Font.Weight, color: Color) -> some View {
        Text(text ?? " ")
            .font(.system(size: size, weight: weight))
            .foregroundStyle(color)
            .lineLimit(size > 12 ? 2 : 1)
            .fixedSize(horizontal: false, vertical: true)
    }
}

// MARK: - Spectrum (boards 9.2, 9.4, 9.5)

private struct SpectrumView: View {
    @ObservedObject var spectrum: Spectrum
    let track: NowPlayingTrack?

    var body: some View {
        let live = spectrum.isRunning && track?.isPlaying == true
        VStack(alignment: .leading, spacing: 6) {
            SpectrumBars(bands: spectrum.frame.bands, live: live)
                .frame(maxHeight: .infinity)
            footer(live: live)
                .font(.system(size: 11))
                .monospacedDigit()
                .foregroundStyle(Theme.textSecondary)
                .lineLimit(1)
        }
    }

    @ViewBuilder
    private func footer(live: Bool) -> some View {
        if track == nil {
            Text("Spectrum start zodra er iets speelt")
        } else if track?.isPlaying != true {
            Text("Gepauzeerd")
        } else if spectrum.consent == .declined {
            HStack(spacing: 6) {
                Text("Spectrum staat uit")
                Button("Aanzetten") { spectrum.allow() }
                    .buttonStyle(.plain)
                    .foregroundStyle(Preferences.shared.accent.color)
            }
        } else if live {
            let f = spectrum.frame
            HStack {
                Text("Bas \(pct(f.bass)) · Mid \(pct(f.mid)) · Hoog \(pct(f.high))")
                Spacer(minLength: 4)
                Text("Luid · \(Int(f.loudness.rounded())) dB")
            }
        } else {
            Text("Luisteren…")
        }
    }

    private func pct(_ value: Float) -> String { "\(Int((value * 100).rounded()))%" }
}

/// 24 bars from bass to treble; flat grey dashes when nothing is live.
struct SpectrumBars: View {
    let bands: [Float]
    let live: Bool

    var body: some View {
        GeometryReader { geo in
            let count = bands.count
            let gap: CGFloat = 3
            let width = max(1, (geo.size.width - gap * CGFloat(count - 1)) / CGFloat(count))
            HStack(alignment: .bottom, spacing: gap) {
                ForEach(0..<count, id: \.self) { i in
                    RoundedRectangle(cornerRadius: min(2, width / 2), style: .continuous)
                        .fill(live ? Theme.ok : Theme.textSecondary.opacity(0.35))
                        .frame(width: width,
                               height: live ? max(3, geo.size.height * CGFloat(bands[i])) : 3)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height, alignment: .bottomLeading)
            .animation(.linear(duration: 1.0 / 30), value: bands)
            .animation(.easeOut(duration: 0.4), value: live)
        }
    }
}

// MARK: - Permission (board 9.6)

private struct ConsentView: View {
    @ObservedObject var spectrum: Spectrum

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Theme.control)
                    .frame(width: 34, height: 34)
                    .overlay(Image(systemName: "chart.bar.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(Theme.ok))
                VStack(alignment: .leading, spacing: 4) {
                    Text("Laat wisp meeluisteren?")
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                    Text("Voor het spectrum analyseert wisp live het geluid van je Mac. Er wordt niets opgenomen of verstuurd.")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.textSecondary)
                        .lineLimit(4)
                }
            }
            Spacer(minLength: 0)
            HStack(spacing: 8) {
                Button { spectrum.allow() } label: { Text("Toestaan").frame(maxWidth: .infinity) }
                    .buttonStyle(AccentButtonStyle())
                Button { spectrum.decline() } label: { Text("Niet nu").frame(maxWidth: .infinity) }
                    .buttonStyle(SecondaryButtonStyle())
            }
        }
        .padding(12)
    }
}
