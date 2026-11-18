import Foundation
import OnnxRuntimeBindings

public enum WilderError: Error, LocalizedError {
    case badInput(String)
    case missingOutput(String)
    case audio(String)

    public var errorDescription: String? {
        switch self {
        case .badInput(let m), .missingOutput(let m), .audio(let m): return m
        }
    }
}

enum Runtime {
    static let env: ORTEnv = try! ORTEnv(loggingLevel: .warning)
}

private func floatTensor(_ values: [Float], shape: [Int]) throws -> ORTValue {
    let data = values.withUnsafeBufferPointer { NSMutableData(bytes: $0.baseAddress, length: $0.count * MemoryLayout<Float>.stride) }
    return try ORTValue(tensorData: data, elementType: .float, shape: shape.map { NSNumber(value: $0) })
}

private func floats(_ value: ORTValue) throws -> [Float] {
    let data = try value.tensorData() as Data
    return data.withUnsafeBytes { Array($0.bindMemory(to: Float.self)) }
}

/// Google's Perch 2.0 bioacoustics classifier: 5 s of 32 kHz mono audio in, one score per species out.
public final class SoundClassifier: @unchecked Sendable {
    public static let sampleRate = 32_000
    public static let windowSamples = 160_000

    private let session: ORTSession
    private let lock = NSLock()

    public init(modelURL: URL, threads: Int32 = 0) throws {
        let options = try ORTSessionOptions()
        if threads > 0 { try options.setIntraOpNumThreads(threads) }
        try options.setGraphOptimizationLevel(.all)
        session = try ORTSession(env: Runtime.env, modelPath: modelURL.path, sessionOptions: options)
    }

    /// Scores (logits) for one window. Shorter input is zero-padded at the front.
    public func scores(for samples: [Float]) throws -> [Float] {
        var window = samples
        let n = Self.windowSamples
        if window.count > n { window = Array(window.suffix(n)) }
        if window.count < n { window = [Float](repeating: 0, count: n - window.count) + window }
        let input = try floatTensor(window, shape: [1, n])
        lock.lock(); defer { lock.unlock() }
        let out = try session.run(withInputs: ["inputs": input], outputNames: ["label"], runOptions: nil)
        guard let label = out["label"] else { throw WilderError.missingOutput("Sound model returned no scores") }
        return try floats(label)
    }
}

/// BirdNET's geomodel: latitude, longitude and week of year in, likelihood of occurrence per species out.
public final class RangeModel: @unchecked Sendable {
    public static let weeks = 48
    private let session: ORTSession

    public init(modelURL: URL) throws {
        let options = try ORTSessionOptions()
        try options.setIntraOpNumThreads(1)
        session = try ORTSession(env: Runtime.env, modelPath: modelURL.path, sessionOptions: options)
    }

    /// Occurrence scores for every week of the 48-week year: `result[week - 1][rangeIndex]`.
    public func yearScores(latitude: Double, longitude: Double) throws -> [[Float]] {
        var input: [Float] = []
        for week in 1...Self.weeks { input += [Float(latitude), Float(longitude), Float(week)] }
        let tensor = try floatTensor(input, shape: [Self.weeks, 3])
        let out = try session.run(withInputs: ["input": tensor], outputNames: ["probabilities"], runOptions: nil)
        guard let value = out["probabilities"] else { throw WilderError.missingOutput("Range model returned nothing") }
        let flat = try floats(value)
        let width = flat.count / Self.weeks
        return (0..<Self.weeks).map { Array(flat[($0 * width)..<(($0 + 1) * width)]) }
    }

    /// BirdNET divides the year into 48 weeks, four per month.
    public static func week(for date: Date) -> Int {
        let parts = Calendar(identifier: .gregorian).dateComponents([.month, .day], from: date)
        let month = parts.month ?? 1, day = parts.day ?? 1
        return (month - 1) * 4 + min(4, (day - 1) / 7 + 1)
    }
}
