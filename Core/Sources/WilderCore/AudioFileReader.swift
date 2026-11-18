import AVFoundation

public enum AudioFileReader {
    /// Decodes any audio file the system understands into 32 kHz mono samples.
    public static func samples(from url: URL) throws -> [Float] {
        let file = try AVAudioFile(forReading: url)
        let source = file.processingFormat
        guard let target = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: Double(SoundClassifier.sampleRate), channels: 1, interleaved: false),
              let converter = AVAudioConverter(from: source, to: target),
              let input = AVAudioPCMBuffer(pcmFormat: source, frameCapacity: 32_768) else {
            throw WilderError.audio("Couldn't read this audio format")
        }
        var result: [Float] = []
        result.reserveCapacity(Int(Double(file.length) * target.sampleRate / source.sampleRate) + 1024)
        var finished = false
        var readError: Error?

        while true {
            guard let output = AVAudioPCMBuffer(pcmFormat: target, frameCapacity: 32_768) else { break }
            var error: NSError?
            let status = converter.convert(to: output, error: &error) { _, outStatus in
                if finished || file.framePosition >= file.length {
                    finished = true
                    outStatus.pointee = .endOfStream
                    return nil
                }
                do {
                    try file.read(into: input)
                } catch {
                    readError = error
                    input.frameLength = 0
                }
                if input.frameLength == 0 {
                    finished = true
                    outStatus.pointee = .endOfStream
                    return nil
                }
                outStatus.pointee = .haveData
                return input
            }
            if let error { throw error }
            if let readError { throw readError }
            if output.frameLength > 0, let channel = output.floatChannelData?[0] {
                result.append(contentsOf: UnsafeBufferPointer(start: channel, count: Int(output.frameLength)))
            }
            if status == .endOfStream || (status == .inputRanDry && finished) || output.frameLength == 0 { break }
        }
        return result
    }
}
