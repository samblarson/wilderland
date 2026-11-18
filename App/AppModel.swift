import AVFoundation
import CoreLocation
import Observation
import SwiftUI
import WilderCore

struct Detection: Identifiable, Codable, Hashable {
    var speciesIndex: Int
    var bestScore: Float
    var hits: Int
    var first: Date
    var last: Date

    var id: Int { speciesIndex }
    var confidence: Confidence { Confidence(score: bestScore) }
}

struct SavedSession: Identifiable, Codable, Hashable {
    var id = UUID()
    var date: Date
    /// "Live" or the name of an imported file.
    var source: String
    var seconds: Double
    var usedLocation: Bool
    var detections: [Detection]
}

struct Settings: Codable, Equatable {
    var groups: Set<AnimalGroup> = Set(AnimalGroup.selectable)
    var sensitivity: Sensitivity = .medium
    var useLocation = true
}

enum PlaceState: Equatable {
    case off, unknown, locating, located, denied, failed
}

@MainActor
@Observable
final class AppModel {
    enum Phase: Equatable { case loading, ready, failed(String) }

    private(set) var phase: Phase = .loading
    private(set) var isListening = false
    /// Everything the model has flagged this session, including unconfirmed weak matches.
    private var candidates: [Detection] = []
    /// What the user sees: a weak match must be heard in two windows before it is shown.
    var detections: [Detection] {
        candidates.filter { $0.hits >= 2 || $0.confidence >= .likely }
    }
    private(set) var history: [SavedSession] = []
    private(set) var place: PlaceState = .unknown
    private(set) var fileProgress: Double?
    private(set) var sessionSource = "Live"
    var alert: String?

    var settings = Settings() {
        didSet {
            guard settings != oldValue else { return }
            if let data = try? JSONEncoder().encode(settings) { UserDefaults.standard.set(data, forKey: "settings") }
            if settings.useLocation != oldValue.useLocation { refreshLocation() }
        }
    }

    let capture = AudioCapture()
    private(set) var catalog: SpeciesCatalog?
    private var identifier: WildlifeIdentifier?
    private var plausible: [Bool]?
    private var loop: Task<Void, Never>?
    private var locating: Task<Void, Never>?
    private var sessionStart = Date()
    private let locator = Locator()

    private var filter: Filter {
        Filter(groups: settings.groups, sensitivity: settings.sensitivity, plausible: settings.useLocation ? plausible : nil)
    }

    private static var historyURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("history.json")
    }

    init() {
        if let data = UserDefaults.standard.data(forKey: "settings"), let saved = try? JSONDecoder().decode(Settings.self, from: data) {
            settings = saved
        }
        if let data = try? Data(contentsOf: Self.historyURL), let saved = try? JSONDecoder().decode([SavedSession].self, from: data) {
            history = saved
        }
    }

    func species(_ detection: Detection) -> Species? {
        guard let catalog, detection.speciesIndex < catalog.count else { return nil }
        return catalog[detection.speciesIndex]
    }

    // MARK: Loading

    func load() async {
        guard identifier == nil else { return }
        guard let directory = Bundle.main.resourceURL else { phase = .failed("App resources are missing"); return }
        do {
            let loaded = try await Task.detached(priority: .userInitiated) { try WildlifeIdentifier(directory: directory) }.value
            identifier = loaded
            catalog = loaded.catalog
            phase = .ready
            refreshLocation()
            #if DEBUG && targetEnvironment(simulator)
            // Simulator testing aid: `simctl launch <device> com.wilderland.app -analyzeFile /path/on/mac.wav`
            if let path = UserDefaults.standard.string(forKey: "analyzeFile") {
                await analyze(file: URL(fileURLWithPath: path))
            }
            #endif
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }

    // MARK: Location

    func refreshLocation() {
        guard settings.useLocation else { place = .off; return }
        guard let identifier else { return }
        place = .locating
        locating = Task {
            switch await locator.locate() {
            case .denied: place = .denied
            case .failed: place = plausible == nil ? .failed : .located
            case .found(let coordinate):
                let result = try? await Task.detached {
                    try identifier.ranges.plausibleSpecies(latitude: coordinate.latitude, longitude: coordinate.longitude)
                }.value
                if let result { plausible = result; place = .located } else { place = .failed }
            }
        }
    }

    // MARK: Live listening

    func toggleListening() {
        if isListening { stopListening() } else { Task { await startListening() } }
    }

    private func startListening() async {
        guard phase == .ready, !isListening, fileProgress == nil else { return }
        guard await AVAudioApplication.requestRecordPermission() else {
            alert = "Wilderland needs the microphone to hear wildlife. You can allow it in Settings › Privacy › Microphone."
            return
        }
        do {
            try capture.start()
        } catch {
            alert = "Couldn't start the microphone: \(error.localizedDescription)"
            return
        }
        candidates = []
        sessionSource = "Live"
        sessionStart = Date()
        isListening = true
        setIdleTimer(disabled: true)
        if place == .failed || place == .unknown { refreshLocation() }

        loop = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1.5))
                guard let self, !Task.isCancelled, let identifier = self.identifier else { return }
                let samples = self.capture.latest(seconds: 5)
                guard samples.count >= SoundClassifier.sampleRate * 2 else { continue }
                let filter = self.filter
                let hits = await Task.detached(priority: .userInitiated) {
                    (try? identifier.identify(samples, filter: filter)) ?? []
                }.value
                if Task.isCancelled { return }
                self.record(hits, at: Date())
            }
        }
    }

    func stopListening() {
        guard isListening else { return }
        loop?.cancel()
        loop = nil
        capture.stop()
        isListening = false
        setIdleTimer(disabled: false)
        save(seconds: capture.secondsCaptured)
    }

    private func record(_ hits: [Hit], at time: Date) {
        for hit in hits {
            if let i = candidates.firstIndex(where: { $0.speciesIndex == hit.speciesIndex }) {
                candidates[i].bestScore = max(candidates[i].bestScore, hit.score)
                candidates[i].hits += 1
                candidates[i].last = time
            } else {
                candidates.insert(Detection(speciesIndex: hit.speciesIndex, bestScore: hit.score, hits: 1, first: time, last: time), at: 0)
            }
        }
    }

    // MARK: Imported recordings

    func analyze(file url: URL) async {
        guard phase == .ready, !isListening, fileProgress == nil, let identifier else { return }
        // Wait for the range filter so species from other continents aren't suggested.
        await locating?.value
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        fileProgress = 0
        candidates = []
        sessionSource = url.lastPathComponent
        sessionStart = Date()
        defer { fileProgress = nil }
        do {
            let samples = try await Task.detached(priority: .userInitiated) { try AudioFileReader.samples(from: url) }.value
            guard !samples.isEmpty else { alert = "That file doesn't contain any audio."; return }
            let window = SoundClassifier.windowSamples, hop = window / 2
            let filter = self.filter
            var start = 0
            repeat {
                let chunk = Array(samples[start..<min(samples.count, start + window)])
                let hits = try await Task.detached(priority: .userInitiated) { try identifier.identify(chunk, filter: filter) }.value
                record(hits, at: sessionStart.addingTimeInterval(Double(start) / Double(SoundClassifier.sampleRate)))
                start += hop
                fileProgress = min(1, Double(start) / Double(samples.count))
            } while start + hop < samples.count
            candidates.sort { $0.bestScore > $1.bestScore }
            save(seconds: Double(samples.count) / Double(SoundClassifier.sampleRate))
        } catch {
            alert = "Couldn't analyze that recording: \(error.localizedDescription)"
        }
    }

    // MARK: History

    private func save(seconds: Double) {
        guard !detections.isEmpty else { return }
        let session = SavedSession(date: sessionStart, source: sessionSource, seconds: seconds,
                                   usedLocation: settings.useLocation && plausible != nil,
                                   detections: detections.sorted { $0.bestScore > $1.bestScore })
        history.insert(session, at: 0)
        persistHistory()
    }

    func delete(sessions offsets: IndexSet) {
        history.remove(atOffsets: offsets)
        persistHistory()
    }

    private func persistHistory() {
        if let data = try? JSONEncoder().encode(history) { try? data.write(to: Self.historyURL, options: .atomic) }
    }

    private func setIdleTimer(disabled: Bool) {
        #if os(iOS)
        UIApplication.shared.isIdleTimerDisabled = disabled
        #endif
    }
}

/// One-shot location lookup. The coordinate never leaves the device: it only feeds the on-device range model.
@MainActor
final class Locator: NSObject, CLLocationManagerDelegate {
    enum Result { case found(CLLocationCoordinate2D), denied, failed }

    private let manager = CLLocationManager()
    private var waiting: [CheckedContinuation<Result, Never>] = []

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyThreeKilometers
    }

    func locate() async -> Result {
        await withCheckedContinuation { continuation in
            waiting.append(continuation)
            guard waiting.count == 1 else { return }
            switch manager.authorizationStatus {
            case .notDetermined: manager.requestWhenInUseAuthorization()
            case .denied, .restricted: finish(.denied)
            default: manager.requestLocation()
            }
        }
    }

    private func finish(_ result: Result) {
        let pending = waiting
        waiting = []
        pending.forEach { $0.resume(returning: result) }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor in
            guard !self.waiting.isEmpty else { return }
            switch status {
            case .notDetermined: break
            case .denied, .restricted: self.finish(.denied)
            default: self.manager.requestLocation()
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let coordinate = locations.last?.coordinate else { return }
        Task { @MainActor in self.finish(.found(coordinate)) }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in self.finish(.failed) }
    }
}
