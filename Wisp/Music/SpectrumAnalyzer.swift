import Accelerate
import Foundation

/// One analysed slice of audio.
struct SpectrumFrame: Sendable, Equatable {
    /// 0…1 per band, from bass (first) to treble (last).
    var bands: [Float]
    /// Share of the energy below 250 Hz, 250 Hz–4 kHz and above 4 kHz (sums to 1).
    var bass: Float, mid: Float, high: Float
    /// RMS level in dBFS (0 is full scale, silence is about −90).
    var loudness: Float

    static let silent = SpectrumFrame(bands: Array(repeating: 0, count: Spectrum.bandCount),
                                      bass: 0, mid: 0, high: 0, loudness: -90)
}

/// FFT of the incoming samples, grouped into log-spaced bands.
///
/// Only ever used on the tap's audio queue, so it needs no locking. All buffers are
/// allocated up front; analysing a block allocates nothing.
final class SpectrumAnalyzer: @unchecked Sendable {
    private let size = 2048
    private let log2n: vDSP_Length
    private let setup: FFTSetup
    private var window: [Float]
    private var ring: [Float]
    private var ringIndex = 0
    private var filled = 0
    private var windowed: [Float]
    private var real: [Float]
    private var imag: [Float]
    private var magnitudes: [Float]
    private var smoothed: [Float]
    private var bandRanges: [Range<Int>] = []
    private var bassBins = 0..<0, midBins = 0..<0, highBins = 0..<0
    private var sampleRate: Double = 0

    init() {
        log2n = vDSP_Length(log2(Double(size)))
        setup = vDSP_create_fftsetup(log2n, FFTRadix(kFFTRadix2))!
        window = [Float](repeating: 0, count: size)
        vDSP_hann_window(&window, vDSP_Length(size), Int32(vDSP_HANN_NORM))
        ring = [Float](repeating: 0, count: size)
        windowed = [Float](repeating: 0, count: size)
        real = [Float](repeating: 0, count: size / 2)
        imag = [Float](repeating: 0, count: size / 2)
        magnitudes = [Float](repeating: 0, count: size / 2)
        smoothed = [Float](repeating: 0, count: Spectrum.bandCount)
    }

    deinit { vDSP_destroy_fftsetup(setup) }

    /// Appends mono samples; returns a frame once enough audio has arrived.
    func process(_ samples: UnsafeBufferPointer<Float>, sampleRate rate: Double) -> SpectrumFrame? {
        if rate != sampleRate { configure(for: rate) }
        for s in samples {
            ring[ringIndex] = s
            ringIndex = (ringIndex + 1) % size
        }
        filled += samples.count
        // About 45 analyses a second at 48 kHz (every 1024 samples).
        guard filled >= size / 2 else { return nil }
        filled = 0
        return analyse()
    }

    private func configure(for rate: Double) {
        sampleRate = rate
        let binHz = rate / Double(size)
        func bin(_ hz: Double) -> Int { min(size / 2 - 1, max(1, Int(hz / binHz))) }

        // Log-spaced bands from 40 Hz to 16 kHz; every band gets at least one bin.
        let low = 40.0, high = min(16_000.0, rate / 2)
        var ranges: [Range<Int>] = []
        var start = bin(low)
        for i in 1...Spectrum.bandCount {
            let edge = low * pow(high / low, Double(i) / Double(Spectrum.bandCount))
            let end = max(start + 1, bin(edge))
            ranges.append(start..<end)
            start = end
        }
        bandRanges = ranges
        bassBins = bin(20)..<bin(250)
        midBins = bin(250)..<bin(4_000)
        highBins = bin(4_000)..<bin(min(16_000, rate / 2))
    }

    private func analyse() -> SpectrumFrame {
        // Unroll the ring buffer (oldest sample first) and apply the window.
        let tail = size - ringIndex
        ring.withUnsafeBufferPointer { r in
            windowed.withUnsafeMutableBufferPointer { w in
                for i in 0..<tail { w[i] = r[ringIndex + i] }
                for i in 0..<ringIndex { w[tail + i] = r[i] }
            }
        }
        var rms: Float = 0
        vDSP_rmsqv(windowed, 1, &rms, vDSP_Length(size))
        vDSP_vmul(windowed, 1, window, 1, &windowed, 1, vDSP_Length(size))

        real.withUnsafeMutableBufferPointer { re in
            imag.withUnsafeMutableBufferPointer { im in
                var split = DSPSplitComplex(realp: re.baseAddress!, imagp: im.baseAddress!)
                windowed.withUnsafeBufferPointer { w in
                    w.baseAddress!.withMemoryRebound(to: DSPComplex.self, capacity: size / 2) {
                        vDSP_ctoz($0, 2, &split, 1, vDSP_Length(size / 2))
                    }
                }
                vDSP_fft_zrip(setup, &split, 1, log2n, FFTDirection(FFT_FORWARD))
                vDSP_zvmags(&split, 1, &magnitudes, 1, vDSP_Length(size / 2))
            }
        }

        var bands = [Float](repeating: 0, count: Spectrum.bandCount)
        for (i, range) in bandRanges.enumerated() {
            var peak: Float = 0
            for b in range { peak = max(peak, magnitudes[b]) }
            // Power → dB, then −70…−10 dB onto 0…1.
            let db = 10 * log10(peak / Float(size * size) + 1e-12)
            let level = min(1, max(0, (db + 70) / 60))
            // Fast attack, slow release: lively but not jittery.
            let previous = smoothed[i]
            smoothed[i] = level > previous ? level : previous * 0.82 + level * 0.18
            bands[i] = smoothed[i]
        }

        func energy(_ r: Range<Int>) -> Float {
            r.isEmpty ? 0 : magnitudes[r].reduce(0, +)
        }
        let b = energy(bassBins), m = energy(midBins), h = energy(highBins)
        let total = max(b + m + h, 1e-12)

        return SpectrumFrame(bands: bands, bass: b / total, mid: m / total, high: h / total,
                             loudness: max(-90, 20 * log10(rms + 1e-9)))
    }
}
