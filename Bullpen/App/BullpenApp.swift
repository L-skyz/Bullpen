import SwiftUI

@main
struct BullpenApp: App {
    init() { appLog("[App] BullpenApp.init") }
    @StateObject private var auth   = AuthService.shared
    @StateObject private var filter = BlockFilter.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(auth)
                .environmentObject(filter)
        }
    }
}
