import SwiftUI
import UIKit

// web-main MyBrowserAppApp.swift 기반 이식
// init()에서 _ = SilentAudioPlayer.shared → 자동 세션 설정 + 무음 재생 시작
// background deactivate 없음 — 세션 항상 유지 (web-main 방식)

@main
struct BullpenApp: App {
    @StateObject private var auth   = AuthService.shared
    @StateObject private var filter = BlockFilter.shared

    init() {
        _ = SilentAudioPlayer.shared
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(auth)
                .environmentObject(filter)
        }
    }
}
