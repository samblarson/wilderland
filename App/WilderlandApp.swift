import SwiftUI

@main
struct WilderlandApp: App {
    @State private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            TabView {
                ListenView()
                    .tabItem { Label("Listen", systemImage: "waveform") }
                HistoryView()
                    .tabItem { Label("History", systemImage: "clock") }
            }
            .environment(model)
            .tint(Theme.accent)
            .task { await model.load() }
        }
    }
}

enum Theme {
    static let accent = Color(red: 0.16, green: 0.50, blue: 0.38)
    static let panel = Color(red: 12 / 255, green: 17 / 255, blue: 22 / 255)
}
