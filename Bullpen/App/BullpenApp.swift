import SwiftUI

@main
struct BullpenApp: App {
    @StateObject private var auth   = AuthService.shared
    @StateObject private var filter = BlockFilter.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(auth)
                .environmentObject(filter)
                .task {
                    await auth.fetchProfile()
                }
        }
    }
}
