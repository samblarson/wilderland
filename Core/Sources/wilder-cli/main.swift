// Mac command-line tester: runs the same identification code as the app over audio files.
//
//   swift run -c release wilder-cli <models-dir> [--lat 44.06 --lon -121.3] [--month 6] [--all-windows] file.wav ...
//
// When a file is named Genus_species_N.ext the tool also scores itself against that name.

import Foundation
import WilderCore

var args = Array(CommandLine.arguments.dropFirst())
guard !args.isEmpty else {
    print("usage: wilder-cli <models-dir> [--lat N --lon N] [--month N] [--sensitivity low|medium|high] files...")
    exit(2)
}
let directory = URL(fileURLWithPath: args.removeFirst())
var latitude: Double?, longitude: Double?, month: Int?
var sensitivity = Sensitivity.medium
var files: [String] = []
while !args.isEmpty {
    let arg = args.removeFirst()
    switch arg {
    case "--lat": latitude = Double(args.removeFirst())
    case "--lon": longitude = Double(args.removeFirst())
    case "--month": month = Int(args.removeFirst())
    case "--sensitivity": sensitivity = Sensitivity(rawValue: args.removeFirst()) ?? .medium
    default: files.append(arg)
    }
}

let started = Date()
let identifier = try WildlifeIdentifier(directory: directory)
print(String(format: "Loaded %d classes in %.1fs", identifier.catalog.count, Date().timeIntervalSince(started)))

var filter = Filter(sensitivity: sensitivity)
if let latitude, let longitude {
    var date = Date()
    if let month {
        date = Calendar(identifier: .gregorian).date(from: DateComponents(year: 2026, month: month, day: 15)) ?? date
    }
    let plausible = try identifier.ranges.plausibleSpecies(latitude: latitude, longitude: longitude, date: date)
    filter.plausible = plausible
    var counts: [AnimalGroup: Int] = [:]
    for (i, ok) in plausible.enumerated() where ok { counts[identifier.catalog[i].g, default: 0] += 1 }
    let summary = AnimalGroup.selectable.map { "\($0.rawValue) \(counts[$0] ?? 0)" }.joined(separator: ", ")
    print("Plausible at \(latitude), \(longitude): \(summary)")
}

var top1 = 0, top3 = 0, scored = 0
let window = SoundClassifier.windowSamples
for path in files {
    let url = URL(fileURLWithPath: path)
    let samples = try AudioFileReader.samples(from: url)
    var best: [Int: Float] = [:]
    var count: [Int: Int] = [:]
    var start = 0, windows = 0
    var elapsed = 0.0
    repeat {
        let end = min(samples.count, start + window)
        let t = Date()
        for hit in try identifier.identify(Array(samples[start..<end]), filter: filter) {
            best[hit.speciesIndex] = max(best[hit.speciesIndex] ?? -.infinity, hit.score)
            count[hit.speciesIndex, default: 0] += 1
        }
        elapsed += Date().timeIntervalSince(t)
        windows += 1
        start += window / 2
    } while start + window / 2 < samples.count && windows < 24

    let ranked = best.sorted { $0.value > $1.value }
    let name = url.deletingPathExtension().lastPathComponent
    let truth = name.split(separator: "_").prefix(2).joined(separator: " ")
    let names = ranked.map { identifier.catalog[$0.key].s }
    var mark = "  "
    if identifier.catalog.species.contains(where: { $0.s == truth }) {
        scored += 1
        if names.first == truth { top1 += 1; top3 += 1; mark = "✓ " } else if names.prefix(3).contains(truth) { top3 += 1; mark = "~ " } else { mark = "✗ " }
    }
    let listing = ranked.prefix(4).map { entry -> String in
        let sp = identifier.catalog[entry.key]
        return String(format: "%@ %@ %.1f×%d", sp.emoji, sp.displayName, entry.value, count[entry.key] ?? 0)
    }.joined(separator: " | ")
    print(String(format: "%@%@ (%.0fs, %.0f ms/window): %@", mark, name, Double(samples.count) / 32000, elapsed / Double(windows) * 1000, listing.isEmpty ? "nothing detected" : listing))
}
if scored > 0 { print("Top-1 \(top1)/\(scored), top-3 \(top3)/\(scored)") }
