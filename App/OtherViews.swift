import SwiftUI
import WilderCore

struct SpeciesDetailView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let detection: Detection

    var body: some View {
        List {
            if let species = model.species(detection) {
                Section {
                    VStack(spacing: 8) {
                        SpeciesIcon(species: species, size: 84)
                        Text(species.displayName).font(.title2.bold()).multilineTextAlignment(.center)
                        if species.hasCommonName {
                            Text(species.scientificName).italic().foregroundStyle(.secondary)
                        }
                        ConfidenceBadge(confidence: detection.confidence)
                    }
                    .frame(maxWidth: .infinity)
                    .listRowBackground(Color.clear)
                }
                Section {
                    LabeledContent("Group", value: species.group.title)
                    if !species.f.isEmpty { LabeledContent("Family", value: species.f) }
                    LabeledContent("Times recognized", value: "\(detection.hits)")
                    LabeledContent("Best match score", value: String(format: "%.1f", detection.bestScore))
                } footer: {
                    Text(explanation)
                }
                if let url = species.infoURL {
                    Section {
                        Link(destination: url) {
                            Label("Photos and reference recordings on iNaturalist", systemImage: "safari")
                        }
                    } footer: {
                        Text("Compare what you heard with known recordings before trusting a match, especially for crickets and frogs that sound alike.")
                    }
                }
            }
        }
        .navigationTitle("Match")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
        }
    }

    private var explanation: String {
        switch detection.confidence {
        case .strong: return "The sound closely matched this species in at least one 5-second window."
        case .likely: return "A good match, though a similar-sounding species is possible."
        case .possible: return "A weak match. Treat it as a hint and listen for it again."
        }
    }
}

struct HistoryView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        NavigationStack {
            Group {
                if model.history.isEmpty {
                    ContentUnavailableView("No sessions yet", systemImage: "clock", description: Text("Each time you listen and something is recognized, the session is saved here."))
                } else {
                    List {
                        ForEach(model.history) { session in
                            NavigationLink(value: session) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(session.date.formatted(date: .abbreviated, time: .shortened)).font(.headline)
                                    Text(summary(session)).font(.subheadline).foregroundStyle(.secondary).lineLimit(2)
                                }
                            }
                        }
                        .onDelete { model.delete(sessions: $0) }
                    }
                }
            }
            .navigationTitle("History")
            .navigationDestination(for: SavedSession.self) { SessionView(session: $0) }
        }
    }

    private func summary(_ session: SavedSession) -> String {
        let names = session.detections.compactMap { model.species($0) }.map(\.displayName)
        return names.isEmpty ? "\(session.detections.count) animals" : names.joined(separator: " · ")
    }
}

private struct SessionView: View {
    @Environment(AppModel.self) private var model
    let session: SavedSession
    @State private var selected: Detection?

    var body: some View {
        List {
            Section {
                ForEach(session.detections) { detection in
                    Button { selected = detection } label: { DetectionRow(detection: detection) }
                        .buttonStyle(.plain)
                }
            } footer: {
                Text("\(session.source == "Live" ? "Live session" : session.source) · \(Duration.seconds(session.seconds).formatted(.time(pattern: .minuteSecond)))\(session.usedLocation ? " · narrowed by location" : "")")
            }
        }
        .navigationTitle(session.date.formatted(date: .abbreviated, time: .shortened))
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $selected) { detection in
            NavigationStack { SpeciesDetailView(detection: detection) }
                .presentationDetents([.medium, .large])
        }
    }
}

struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        @Bindable var model = model
        NavigationStack {
            Form {
                Section {
                    ForEach(AnimalGroup.selectable, id: \.self) { group in
                        Toggle(group.title, isOn: Binding(
                            get: { model.settings.groups.contains(group) },
                            set: { on in
                                if on { model.settings.groups.insert(group) } else { model.settings.groups.remove(group) }
                            }))
                    }
                } header: {
                    Text("Show")
                } footer: {
                    Text("Hidden groups are still recognized behind the scenes, so a bird won't be mistaken for the nearest-sounding frog.")
                }

                Section {
                    Picker("Sensitivity", selection: $model.settings.sensitivity) {
                        ForEach(Sensitivity.allCases, id: \.self) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                } header: {
                    Text("Sensitivity")
                } footer: {
                    Text("High catches fainter and more distant calls but makes more wrong guesses.")
                }

                Section {
                    Toggle("Only animals found near me", isOn: $model.settings.useLocation)
                } footer: {
                    Text("Your location stays on this iPhone. It is used with a built-in range map to rule out species that don't live in your region.")
                }

                Section("About") {
                    Text("Sounds are identified on this iPhone by Perch 2.0, a bioacoustics model from Google DeepMind (Apache 2.0) trained on recordings from Xeno-canto, iNaturalist and the Animal Sound Archive.")
                    Text("Species ranges come from the BirdNET geomodel by the K. Lisa Yang Center for Conservation Bioacoustics and Chemnitz University of Technology (CC BY-SA 4.0), and from iNaturalist observations. Names and taxonomy are from iNaturalist.")
                    Text("Matches are suggestions, not confirmations. Many insects and frogs sound alike, and quiet animals such as deer are rarely identifiable by sound.")
                }
                .font(.footnote)
                .foregroundStyle(.secondary)
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
    }
}
