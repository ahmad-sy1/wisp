import SwiftUI

/// Right card of the Music tab: a live spectrum of what plays, with the volume below.
struct SideCard: View {
    @ObservedObject var player: NowPlaying
    @ObservedObject var spectrum: Spectrum

    @State private var volume: Double = Double(AudioOutput.volume ?? 0)
    @State private var hasVolume = AudioOutput.volume != nil
    @State private var quality = AudioOutput.qualityLabel

    private var needsConsent: Bool {
        spectrum.consent == .notAsked && player.track?.isPlaying == true
    }

    var body: some View {
        Group {
            if needsConsent {
                ConsentView(spectrum: spectrum)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    header
                    SpectrumView(spectrum: spectrum, track: player.track)
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
            spectrum.setVisible(true, by: "tab")
        }
        .onDisappear { spectrum.setVisible(false, by: "tab") }
    }

    // MARK: Header: label and output quality

    private var header: some View {
        HStack(spacing: 8) {
            Text("SPECTRUM")
                .font(.system(size: 10.5, weight: .medium))
                .tracking(0.6)
                .foregroundStyle(Theme.textSecondary)
            Spacer(minLength: 4)
            Text(player.track == nil ? "Wacht op geluid" : quality ?? "")
                .font(.system(size: 11))
                .foregroundStyle(Theme.textSecondary)
                .lineLimit(1)
        }
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

// MARK: - Spectrum (boards 9.1, 9.3, 9.4)

private struct SpectrumView: View {
    @ObservedObject var spectrum: Spectrum
    let track: NowPlayingTrack?

    var body: some View {
        let live = spectrum.isRunning && track?.isPlaying == true
        VStack(alignment: .leading, spacing: 6) {
            SpectrumBars(levels: spectrum.levels, live: live)
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
            LevelsReadout(levels: spectrum.levels)
        } else {
            Text("Luisteren…")
        }
    }
}

/// "Bas 44% · Mid 52% · Hoog 4%   −17 dB", refreshed four times a second.
private struct LevelsReadout: View {
    @ObservedObject var levels: SpectrumLevels

    var body: some View {
        let f = levels.summary
        HStack(spacing: 4) {
            Text("Bas \(pct(f.bass)) · Mid \(pct(f.mid)) · Hoog \(pct(f.high))")
                .minimumScaleFactor(0.8)
            Spacer(minLength: 2)
            Text("\(Int(f.loudness.rounded())) dB")
                .help("Luidheid")
        }
    }

    private func pct(_ value: Float) -> String { "\(Int((value * 100).rounded()))%" }
}

/// 24 bars from bass to treble, drawn in one Canvas pass; flat grey dashes when
/// nothing is live.
struct SpectrumBars: View {
    @ObservedObject var levels: SpectrumLevels
    let live: Bool

    var body: some View {
        let bands = levels.bands
        let color = live ? Theme.ok : Theme.textSecondary.opacity(0.35)
        Canvas { context, size in
            let count = bands.count
            let gap: CGFloat = 3
            let width = max(1, (size.width - gap * CGFloat(count - 1)) / CGFloat(count))
            for i in 0..<count {
                let height = live ? max(3, size.height * CGFloat(bands[i])) : 3
                let rect = CGRect(x: CGFloat(i) * (width + gap), y: size.height - height,
                                  width: width, height: height)
                context.fill(Path(roundedRect: rect, cornerRadius: min(2, width / 2)), with: .color(color))
            }
        }
    }
}

// MARK: - Permission (board 9.5)

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
