import Foundation

/// Decides which species are plausible at a place and time of year.
///
/// Two sources, both offline:
/// - the BirdNET geomodel, for species it covers (most birds and mammals, some frogs and insects);
/// - a coarse grid of iNaturalist observations (20° x 30° cells) for everything else.
/// Species with no range information at all are always allowed.
public final class RangeFilter: Sendable {
    public struct Thresholds: Sendable {
        /// Birds move with the seasons, so they are checked against the current week (and its neighbours).
        public var bird: Float = 0.03
        /// Other animals are checked against their best week of the year: observation data for
        /// frogs, insects and mammals is sparse and seasonal in ways that don't match when they call.
        public var nonBird: Float = 0.01
        public init() {}
    }

    private let catalog: SpeciesCatalog
    private let model: RangeModel
    public let thresholds: Thresholds

    public init(modelURL: URL, catalog: SpeciesCatalog, thresholds: Thresholds = Thresholds()) throws {
        self.catalog = catalog
        self.model = try RangeModel(modelURL: modelURL)
        self.thresholds = thresholds
    }

    /// One flag per species in catalog order: true when the species could occur here.
    public func plausibleSpecies(latitude: Double, longitude: Double, date: Date = Date()) throws -> [Bool] {
        let year = try model.yearScores(latitude: latitude, longitude: longitude)
        let week = RangeModel.week(for: date) - 1
        let weeks = RangeModel.weeks
        let nearWeeks = [(week + weeks - 1) % weeks, week, (week + 1) % weeks]
        let cells = Self.cells(near: latitude, longitude: longitude)

        return catalog.species.map { sp in
            if sp.g == .sound { return false }
            if sp.geo >= 0, sp.geo < year[0].count {
                if sp.g == .bird {
                    return nearWeeks.contains { year[$0][sp.geo] >= thresholds.bird }
                }
                return year.contains { $0[sp.geo] >= thresholds.nonBird }
            }
            guard let range = sp.r, !range.isEmpty else { return true }
            return range.contains { cells.contains($0) }
        }
    }

    // MARK: Coarse grid

    static let rows = 7, cols = 12
    static let cellHeight = 20.0, cellWidth = 30.0, south = -60.0

    static func cell(latitude: Double, longitude: Double) -> Int? {
        let row = Int(((latitude - south) / cellHeight).rounded(.down))
        guard (0..<rows).contains(row) else { return nil }
        var lon = longitude.truncatingRemainder(dividingBy: 360)
        if lon < -180 { lon += 360 }
        if lon >= 180 { lon -= 360 }
        let col = min(cols - 1, Int(((lon + 180) / cellWidth).rounded(.down)))
        return row * cols + col
    }

    /// The cell containing the point, plus neighbours within about 3° so cell edges don't cut ranges off.
    static func cells(near latitude: Double, longitude: Double) -> Set<Int> {
        var result = Set<Int>()
        for dLat in [-3.0, 0, 3.0] {
            for dLon in [-3.0, 0, 3.0] {
                if let c = cell(latitude: latitude + dLat, longitude: longitude + dLon) { result.insert(c) }
            }
        }
        return result
    }
}
