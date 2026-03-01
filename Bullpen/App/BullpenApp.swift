import SwiftUI
import AVFoundation
import UIKit

@main
struct BullpenApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var auth   = AuthService.shared
    @StateObject private var filter = BlockFilter.shared

    private func applyAudioSession() {
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback, options: [.mixWithOthers])
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            print("Audio session setup failed: \(error)")
        }
        SilentAudioPlayer.shared.start()
    }

    private func deactivateAudioSession() {
        SilentAudioPlayer.shared.stop()
        try? AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(auth)
                .environmentObject(filter)
                .onAppear {
                    applyAudioSession()
                }
                .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
                    applyAudioSession()
                }
                .onChange(of: scenePhase) { phase in
                    switch phase {
                    case .active:     applyAudioSession()
                    case .background: deactivateAudioSession()
                    default:          break
                    }
                }
        }
    }
}
