import SwiftUI

@main
struct DenisVoiceApp: App {
    @StateObject private var appState = AppState()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appState)
                .environmentObject(appState.webSocket)
                .environmentObject(appState.audio)
                .environmentObject(appState.vad)
                .environmentObject(appState.stt)
                .environmentObject(appState.faceID)
                .environmentObject(appState.foundationModels)
                .environmentObject(appState.vision)
                .environmentObject(appState.ml)
                .environmentObject(appState.worker)
                .environmentObject(appState.bargeIn)
                .onAppear {
                    appState.webSocket.connect()
                    appState.startAppleEdge()
                }
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active {
                        appState.startAppleEdge()
                    }
                    // With UIBackgroundModes=audio, capture continues while
                    // backgrounded. iPadOS remains the lifecycle authority.
                }
        }
    }
}
