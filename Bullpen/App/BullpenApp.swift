import SwiftUI

@main
struct BullpenApp: App {
    @StateObject private var auth   = AuthService.shared
    @StateObject private var filter = BlockFilter.shared
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(auth)
                .environmentObject(filter)
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                Task { await MLBParkService.shared.resetWarmup() }
            }
        }
    }
}
