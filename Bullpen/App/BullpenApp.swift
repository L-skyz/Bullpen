import SwiftUI
import AVFoundation

@main
struct BullpenApp: App {
    @StateObject private var auth   = AuthService.shared
    @StateObject private var filter = BlockFilter.shared

    init() {
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, options: [.mixWithOthers])
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            print("Audio session setup failed: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(auth)
                .environmentObject(filter)
        }
    }
}
