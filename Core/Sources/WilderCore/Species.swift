import Foundation

public enum AnimalGroup: String, Codable, CaseIterable, Sendable {
    case mammal, amphibian, insect, reptile, bird, other
    /// Non-animal sound classes the model also knows (speech, engines, music...). Never shown.
    case sound

    /// Groups a user can switch on and off.
    public static let selectable: [AnimalGroup] = [.mammal, .amphibian, .insect, .reptile, .bird, .other]

    public var title: String {
        switch self {
        case .mammal: return "Mammals"
        case .amphibian: return "Frogs & toads"
        case .insect: return "Insects"
        case .reptile: return "Reptiles"
        case .bird: return "Birds"
        case .other: return "Other animals"
        case .sound: return "Other sounds"
        }
    }
}

/// One class the sound model can predict. Array order in the catalog matches the model's output order.
public struct Species: Codable, Sendable {
    /// Scientific name (or a sound-event label for `.sound` classes).
    public let s: String
    /// English common name; empty when none is known.
    public let c: String
    public let g: AnimalGroup
    /// Index into the range model's output, or -1 when the range model doesn't cover this species.
    public let geo: Int
    /// iNaturalist taxon id (0 when unknown).
    public let id: Int
    /// Taxonomic order and family.
    public let o: String
    public let f: String
    /// Coarse grid cells where the species has been observed; only present when `geo` is -1.
    public let r: [Int]?

    public var scientificName: String { s }
    public var group: AnimalGroup { g }
    public var displayName: String { c.isEmpty ? s : c }
    public var hasCommonName: Bool { !c.isEmpty }

    public var infoURL: URL? {
        id > 0 ? URL(string: "https://www.inaturalist.org/taxa/\(id)") : nil
    }

    /// SF Symbol name for the species' icon.
    public var symbol: String {
        switch g {
        case .bird: return "bird.fill"
        case .amphibian: return "drop.fill"
        case .reptile: return o == "Testudines" ? "tortoise.fill" : "lizard.fill"
        case .insect: return o == "Orthoptera" ? "ant.fill" : "ladybug.fill"
        case .mammal:
            if f == "Canidae" { return "dog.fill" }
            if f == "Felidae" { return "cat.fill" }
            if o == "Lagomorpha" { return "hare.fill" }
            return "pawprint.fill"
        case .other, .sound: return "pawprint.fill"
        }
    }

    /// Emoji for text output (used by the command-line tester).
    public var emoji: String {
        switch g {
        case .bird:
            if o == "Strigiformes" { return "🦉" }
            if o == "Anseriformes" { return "🦆" }
            return "🐦"
        case .amphibian: return "🐸"
        case .reptile:
            if o == "Crocodylia" { return "🐊" }
            return "🦎"
        case .insect:
            if o == "Orthoptera" { return "🦗" }
            if o == "Hymenoptera" { return "🐝" }
            if o == "Diptera" { return "🦟" }
            return "🪲"
        case .mammal:
            switch o {
            case "Chiroptera": return "🦇"
            case "Rodentia": return f == "Sciuridae" ? "🐿️" : (f == "Castoridae" ? "🦫" : "🐭")
            case "Primates": return "🐒"
            case "Lagomorpha": return "🐇"
            case "Cetacea": return "🐋"
            case "Artiodactyla":
                if f == "Cervidae" { return "🦌" }
                if f == "Suidae" { return "🐗" }
                if f == "Bovidae" { return "🐐" }
                return "🦌"
            case "Carnivora":
                switch f {
                case "Canidae": return "🐺"
                case "Felidae": return "🐈"
                case "Ursidae": return "🐻"
                case "Procyonidae": return "🦝"
                case "Mustelidae": return "🦦"
                case "Otariidae", "Phocidae": return "🦭"
                default: return "🐾"
                }
            default: return "🐾"
            }
        case .other, .sound: return "🐾"
        }
    }
}

public final class SpeciesCatalog: Sendable {
    public let species: [Species]

    public init(url: URL) throws {
        species = try JSONDecoder().decode([Species].self, from: Data(contentsOf: url))
    }

    public var count: Int { species.count }
    public subscript(index: Int) -> Species { species[index] }
}
