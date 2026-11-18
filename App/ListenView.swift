import SwiftUI
import UniformTypeIdentifiers
import WilderCore

struct ListenView: View {
    @Environment(AppModel.self) private var model
    @State private var showSettings = false
    @State private var showImporter = false
    @State private var selected: Detection?

    var body: some View {
        @Bindable var model = model
        NavigationStack {
            VStack(spacing: 0) {
                SpectrogramPanel()
                    .padding(.horizontal)
                    .padding(.top, 8)
                PlaceLine()
                    .padding(.horizontal)
                    .padding(.vertical, 10)
                content
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                ListenButton()
                    .padding(.vertical, 14)
            }
            .navigationTitle("Wilderland")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { showImporter = true } label: { Label("Analyze a recording", systemImage: "square.and.arrow.down") }
                        .disabled(model.phase != .ready || model.isListening || model.fileProgress != nil)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showSettings = true } label: { Label("Settings", systemImage: "slider.horizontal.3") }
                }
            }
            .sheet(isPresented: $showSettings) { SettingsView() }
            .sheet(item: $selected) { detection in
                NavigationStack { SpeciesDetailView(detection: detection) }
                    .presentationDetents([.medium, .large])
            }
            .fileImporter(isPresented: $showImporter, allowedContentTypes: [.audio]) { result in
                if case .success(let url) = result { Task { await model.analyze(file: url) } }
            }
            .alert("Wilderland", isPresented: Binding(get: { model.alert != nil }, set: { if !$0 { model.alert = nil } })) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(model.alert ?? "")
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch model.phase {
        case .loading:
            VStack(spacing: 12) {
                ProgressView()
                Text("Loading the sound model…").foregroundStyle(.secondary)
            }
        case .failed(let message):
            ContentUnavailableView("Couldn't load the sound model", systemImage: "exclamationmark.triangle", description: Text(message))
        case .ready:
            if let progress = model.fileProgress, model.detections.isEmpty {
                VStack(spacing: 12) {
                    ProgressView(value: progress).frame(width: 180)
                    Text("Analyzing \(model.sessionSource)…").foregroundStyle(.secondary)
                }
            } else if model.detections.isEmpty {
                if model.isListening {
                    ContentUnavailableView("Listening…", systemImage: "ear", description: Text("Animals appear here as soon as one is recognized. Hold the phone still and point it toward the sound."))
                } else {
                    ContentUnavailableView("What's making that sound?", systemImage: "pawprint", description: Text("Tap the microphone to identify frogs, crickets, coyotes and other wildlife by their calls."))
                }
            } else {
                List {
                    Section {
                        ForEach(model.detections) { detection in
                            Button { selected = detection } label: {
                                DetectionRow(detection: detection, live: model.isListening)
                            }
                            .buttonStyle(.plain)
                        }
                    } header: {
                        if let progress = model.fileProgress {
                            ProgressView(value: progress)
                        } else {
                            Text(model.sessionSource == "Live" ? "Heard this session" : model.sessionSource)
                        }
                    }
                }
                .listStyle(.plain)
                .animation(.default, value: model.detections.map(\.id))
            }
        }
    }
}

private struct SpectrogramPanel: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        ZStack {
            Theme.panel
            if model.isListening {
                TimelineView(.animation(minimumInterval: 1.0 / 15)) { _ in
                    if let image = model.capture.spectrogram.image() {
                        Image(decorative: image, scale: 1)
                            .resizable()
                            .interpolation(.medium)
                    }
                }
            } else {
                Label("Spectrogram appears while listening", systemImage: "waveform")
                    .font(.footnote)
                    .foregroundStyle(.white.opacity(0.45))
            }
        }
        .frame(height: 132)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .accessibilityLabel("Live spectrogram")
    }
}

private struct PlaceLine: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
            Text(text)
            Spacer(minLength: 0)
        }
        .font(.footnote)
        .foregroundStyle(.secondary)
    }

    private var icon: String {
        switch model.place {
        case .located: return "location.fill"
        case .locating: return "location"
        default: return "globe"
        }
    }

    private var text: String {
        switch model.place {
        case .located: return "Showing only animals that live around here"
        case .locating, .unknown: return "Finding your region…"
        case .off: return "Location is off — considering animals worldwide"
        case .denied: return "No location access — considering animals worldwide"
        case .failed: return "Couldn't get your location — considering animals worldwide"
        }
    }
}

private struct ListenButton: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Button {
            model.toggleListening()
        } label: {
            ZStack {
                Circle()
                    .fill(model.isListening ? Color.red : Theme.accent)
                    .frame(width: 76, height: 76)
                    .shadow(color: .black.opacity(0.18), radius: 6, y: 3)
                Image(systemName: model.isListening ? "stop.fill" : "mic.fill")
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundStyle(.white)
            }
        }
        .disabled(model.phase != .ready || model.fileProgress != nil)
        .opacity(model.phase == .ready && model.fileProgress == nil ? 1 : 0.4)
        .accessibilityLabel(model.isListening ? "Stop listening" : "Start listening")
    }
}

struct DetectionRow: View {
    @Environment(AppModel.self) private var model
    let detection: Detection
    var live = false

    var body: some View {
        if let species = model.species(detection) {
            HStack(spacing: 12) {
                SpeciesIcon(species: species, size: 48)
                VStack(alignment: .leading, spacing: 2) {
                    Text(species.displayName)
                        .font(.headline)
                    if species.hasCommonName {
                        Text(species.scientificName)
                            .font(.subheadline)
                            .italic()
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 8)
                VStack(alignment: .trailing, spacing: 4) {
                    ConfidenceBadge(confidence: detection.confidence)
                    if live {
                        TimelineView(.periodic(from: .now, by: 1)) { context in
                            let active = context.date.timeIntervalSince(detection.last) < 4
                            HStack(spacing: 3) {
                                Image(systemName: active ? "dot.radiowaves.left.and.right" : "clock")
                                Text(active ? "Now" : "Earlier")
                            }
                            .font(.caption2)
                            .foregroundStyle(active ? Theme.accent : .secondary)
                        }
                    }
                }
            }
            .padding(.vertical, 4)
            .contentShape(Rectangle())
            .alignmentGuide(.listRowSeparatorLeading) { _ in 60 }
            .alignmentGuide(.listRowSeparatorTrailing) { $0[.trailing] }
        }
    }
}

struct ConfidenceBadge: View {
    let confidence: Confidence

    var body: some View {
        Text(confidence.title)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .foregroundStyle(color)
            .background(color.opacity(0.14), in: Capsule())
    }

    private var color: Color {
        switch confidence {
        case .strong: return Theme.accent
        case .likely: return .orange
        case .possible: return .secondary
        }
    }
}

struct SpeciesIcon: View {
    let species: Species
    var size: CGFloat = 48

    var body: some View {
        Image(systemName: species.symbol)
            .font(.system(size: size * 0.44))
            .foregroundStyle(color)
            .frame(width: size, height: size)
            .background(color.opacity(0.15), in: Circle())
            .accessibilityLabel(species.group.title)
    }

    private var color: Color {
        switch species.group {
        case .mammal: return .brown
        case .amphibian: return .green
        case .insect: return .orange
        case .reptile: return .teal
        case .bird: return .blue
        case .other, .sound: return .gray
        }
    }
}
