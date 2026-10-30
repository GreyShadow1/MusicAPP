import SwiftUI

@main
struct FLACPlayerApp: App {
    @StateObject private var appState = AppState()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(appState)
                .environmentObject(appState.library)
                .environmentObject(appState.favorites)
                .environmentObject(appState.player)
                .environment(\.coverLoader, appState.coverLoader)
                .preferredColorScheme(.dark)
                .task { appState.start() }
        }
        .onChange(of: scenePhase) { phase in
            appState.sceneDidChange(to: phase)
        }
    }
}
