import AVFoundation
import Accelerate
import CoreGraphics
import WilderCore

/// Captures the microphone as 32 kHz mono and keeps the most recent few seconds.
final class AudioCapture: @unchecked Sendable {
    let spectrogram = SpectrogramStore()

    private let engine = AVAudioEngine()
    private let lock = NSLock()
    private var recent: [Float] = []
    private var total = 0
    private let keep = SoundClassifier.sampleRate * 6

    func start() throws {
        #if os(iOS)
        let session = AVAudioSession.sharedInstance()
        // Measurement mode turns off the voice processing that would otherwise filter out wildlife.
        try session.setCategory(.record, mode: .measurement)
        try session.setActive(true)
        #endif
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0,
              let target = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: Double(SoundClassifier.sampleRate), channels: 1, interleaved: false),
              let converter = AVAudioConverter(from: format, to: target) else {
            throw WilderError.audio("No microphone is available")
        }
        lock.lock(); recent.removeAll(keepingCapacity: true); total = 0; lock.unlock()
        spectrogram.reset()
        input.removeTap(onBus: 0)
        input.installTap(onBus: 0, bufferSize: 4096, format: format) { [weak self] buffer, _ in
            self?.process(buffer, converter: converter, target: target)
        }
        engine.prepare()
        try engine.start()
    }

    func stop() {
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        #if os(iOS)
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        #endif
    }

    /// The last `seconds` of audio (fewer if not that much has been captured yet).
    func latest(seconds: Double) -> [Float] {
        lock.lock(); defer { lock.unlock() }
        return Array(recent.suffix(Int(seconds * Double(SoundClassifier.sampleRate))))
    }

    var secondsCaptured: Double {
        lock.lock(); defer { lock.unlock() }
        return Double(total) / Double(SoundClassifier.sampleRate)
    }

    private func process(_ buffer: AVAudioPCMBuffer, converter: AVAudioConverter, target: AVAudioFormat) {
        let ratio = target.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 64
        guard let output = AVAudioPCMBuffer(pcmFormat: target, frameCapacity: capacity) else { return }
        var fed = false
        var error: NSError?
        converter.convert(to: output, error: &error) { _, status in
            if fed { status.pointee = .noDataNow; return nil }
            fed = true
            status.pointee = .haveData
            return buffer
        }
        guard error == nil, output.frameLength > 0, let channel = output.floatChannelData?[0] else { return }
        let samples = UnsafeBufferPointer(start: channel, count: Int(output.frameLength))
        lock.lock()
        recent.append(contentsOf: samples)
        total += samples.count
        if recent.count > keep * 2 { recent.removeFirst(recent.count - keep) }
        lock.unlock()
        spectrogram.feed(samples)
    }
}

/// A scrolling spectrogram of recent audio, rendered to an image for display.
final class SpectrogramStore: @unchecked Sendable {
    static let columns = 280
    static let bands = 72
    private static let frame = 1024

    private let lock = NSLock()
    private var cells = [UInt8](repeating: 0, count: columns * bands)
    private var head = 0
    private var pending: [Float] = []

    private let setup = vDSP_create_fftsetup(10, FFTRadix(kFFTRadix2))!
    private var window = [Float](repeating: 0, count: frame)
    private var bandRanges: [Range<Int>] = []
    private let palette: [UInt8]

    init() {
        vDSP_hann_window(&window, vDSP_Length(Self.frame), Int32(vDSP_HANN_NORM))
        // Log-spaced bands from 150 Hz to 15 kHz; each FFT bin is 31.25 Hz wide.
        let low = log(150.0), high = log(15_000.0)
        var ranges: [Range<Int>] = []
        for b in 0..<Self.bands {
            let f0 = exp(low + (high - low) * Double(b) / Double(Self.bands))
            let f1 = exp(low + (high - low) * Double(b + 1) / Double(Self.bands))
            let start = min(Self.frame / 2 - 1, Int(f0 / 31.25))
            let end = min(Self.frame / 2, max(start + 1, Int(f1 / 31.25)))
            ranges.append(start..<end)
        }
        bandRanges = ranges

        let stops: [(Double, [Double])] = [
            (0.0, [12, 17, 22]), (0.3, [18, 62, 70]), (0.6, [52, 158, 122]),
            (0.82, [226, 208, 112]), (1.0, [255, 250, 236]),
        ]
        var lut = [UInt8](repeating: 255, count: 256 * 4)
        for i in 0..<256 {
            let t = Double(i) / 255
            let upper = stops.firstIndex { $0.0 >= t } ?? stops.count - 1
            let lower = max(0, upper - 1)
            let span = stops[upper].0 - stops[lower].0
            let k = span > 0 ? (t - stops[lower].0) / span : 0
            for c in 0..<3 {
                lut[i * 4 + c] = UInt8(stops[lower].1[c] + (stops[upper].1[c] - stops[lower].1[c]) * k)
            }
        }
        palette = lut
    }

    deinit { vDSP_destroy_fftsetup(setup) }

    func reset() {
        lock.lock(); defer { lock.unlock() }
        cells = [UInt8](repeating: 0, count: Self.columns * Self.bands)
        pending.removeAll(keepingCapacity: true)
        head = 0
    }

    func feed(_ samples: UnsafeBufferPointer<Float>) {
        lock.lock(); defer { lock.unlock() }
        pending.append(contentsOf: samples)
        var offset = 0
        while pending.count - offset >= Self.frame {
            appendColumn(from: offset)
            offset += Self.frame
        }
        if offset > 0 { pending.removeFirst(offset) }
    }

    private func appendColumn(from offset: Int) {
        let n = Self.frame, half = n / 2
        var windowed = [Float](repeating: 0, count: n)
        pending.withUnsafeBufferPointer { p in
            vDSP_vmul(p.baseAddress! + offset, 1, window, 1, &windowed, 1, vDSP_Length(n))
        }
        var real = [Float](repeating: 0, count: half)
        var imag = [Float](repeating: 0, count: half)
        var power = [Float](repeating: 0, count: half)
        real.withUnsafeMutableBufferPointer { r in
            imag.withUnsafeMutableBufferPointer { i in
                var split = DSPSplitComplex(realp: r.baseAddress!, imagp: i.baseAddress!)
                windowed.withUnsafeBytes { raw in
                    vDSP_ctoz(raw.bindMemory(to: DSPComplex.self).baseAddress!, 2, &split, 1, vDSP_Length(half))
                }
                vDSP_fft_zrip(setup, &split, 1, 10, FFTDirection(FFT_FORWARD))
                vDSP_zvmags(&split, 1, &power, 1, vDSP_Length(half))
            }
        }
        let base = head * Self.bands
        for (b, range) in bandRanges.enumerated() {
            var peak: Float = 0
            for bin in range { peak = max(peak, power[bin]) }
            let db = 10 * log10(peak + 1e-9)
            // Roughly -32 dB (quiet room) to +28 dB (loud, close call) across the palette.
            let level = max(0, min(1, (db + 32) / 60))
            cells[base + b] = UInt8(level * 255)
        }
        head = (head + 1) % Self.columns
    }

    /// Oldest audio on the left, newest on the right, low frequencies at the bottom.
    func image() -> CGImage? {
        lock.lock()
        let snapshot = cells, start = head
        lock.unlock()
        let width = Self.columns, height = Self.bands
        var pixels = [UInt8](repeating: 255, count: width * height * 4)
        for x in 0..<width {
            let column = ((start + x) % width) * height
            for y in 0..<height {
                let value = Int(snapshot[column + (height - 1 - y)])
                let p = (y * width + x) * 4
                pixels[p] = palette[value * 4]
                pixels[p + 1] = palette[value * 4 + 1]
                pixels[p + 2] = palette[value * 4 + 2]
            }
        }
        guard let provider = CGDataProvider(data: Data(pixels) as CFData) else { return nil }
        return CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
                       space: CGColorSpaceCreateDeviceRGB(),
                       bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
                       provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent)
    }
}
