import Foundation

public enum Confidence: Int, Codable, Comparable, Sendable {
    case possible, likely, strong

    public static func < (a: Confidence, b: Confidence) -> Bool { a.rawValue < b.rawValue }

    public init(score: Float) {
        if score >= 12 { self = .strong } else if score >= 10.5 { self = .likely } else { self = .possible }
    }

    public var title: String {
        switch self {
        case .possible: return "Possible"
        case .likely: return "Likely"
        case .strong: return "Strong match"
        }
    }
}

public enum Sensitivity: String, Codable, CaseIterable, Sendable {
    case low, medium, high

    /// Minimum model score for a species to be reported. Pure noise tops out around 8.
    public var minimumScore: Float {
        switch self {
        case .low: return 11
        case .medium: return 9.5
        case .high: return 8.7
        }
    }

    public var title: String { rawValue.capitalized }
}

public struct Hit: Sendable {
    public let speciesIndex: Int
    public let score: Float
    public var confidence: Confidence { Confidence(score: score) }
}

/// What the user wants to hear about: which groups, how sensitive, and optionally where they are.
public struct Filter: Sendable {
    public var groups: Set<AnimalGroup>
    public var sensitivity: Sensitivity
    /// Per-species plausibility from `RangeFilter`, or nil to consider species from anywhere.
    public var plausible: [Bool]?

    public init(groups: Set<AnimalGroup> = Set(AnimalGroup.selectable), sensitivity: Sensitivity = .medium, plausible: [Bool]? = nil) {
        self.groups = groups
        self.sensitivity = sensitivity
        self.plausible = plausible
    }
}

/// Loads the models and turns 5-second windows of audio into species hits.
public final class WildlifeIdentifier: Sendable {
    public let catalog: SpeciesCatalog
    public let classifier: SoundClassifier
    public let ranges: RangeFilter

    /// A window reports at most this many species, and only those scoring close to its best one.
    static let maxHitsPerWindow = 3
    static let scoreMargin: Float = 2.5

    /// `directory` must contain `perch_v2_f16.onnx`, `geomodel.onnx` and `species.json`.
    public init(directory: URL) throws {
        catalog = try SpeciesCatalog(url: directory.appendingPathComponent("species.json"))
        classifier = try SoundClassifier(modelURL: directory.appendingPathComponent("perch_v2_f16.onnx"))
        ranges = try RangeFilter(modelURL: directory.appendingPathComponent("geomodel.onnx"), catalog: catalog)
    }

    public func identify(_ samples: [Float], filter: Filter) throws -> [Hit] {
        let scores = try classifier.scores(for: samples)
        guard scores.count == catalog.count else {
            throw WilderError.badInput("Model has \(scores.count) classes but the catalog has \(catalog.count)")
        }
        return Self.hits(scores: scores, catalog: catalog, filter: filter)
    }

    static func hits(scores: [Float], catalog: SpeciesCatalog, filter: Filter) -> [Hit] {
        // Rank across every plausible animal first, then drop the groups the user switched off.
        // That way a bird call isn't reported as the closest-sounding frog just because birds are hidden.
        var candidates: [Hit] = []
        for (i, score) in scores.enumerated() where score >= filter.sensitivity.minimumScore {
            if catalog[i].g == .sound { continue }
            if let plausible = filter.plausible, !plausible[i] { continue }
            candidates.append(Hit(speciesIndex: i, score: score))
        }
        candidates.sort { $0.score > $1.score }
        guard let best = candidates.first else { return [] }
        return candidates
            .prefix(maxHitsPerWindow)
            .filter { $0.score >= best.score - scoreMargin && filter.groups.contains(catalog[$0.speciesIndex].g) }
    }
}
