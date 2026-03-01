import AVFoundation

// web-main avp.swift 기반 이식
// private init()에서 세션 설정 + 무음 재생 자동 시작
// → 앱 어디서든 SilentAudioPlayer.shared 접근 시 즉시 활성화

final class SilentAudioPlayer: @unchecked Sendable {
    static let shared = SilentAudioPlayer()

    private let engine     = AVAudioEngine()
    private let playerNode = AVAudioPlayerNode()

    private init() {
        configureAudioSession()
        startSilentPlayback()
    }

    // MARK: - web-main avp.swift: configureAudioSession()
    private func configureAudioSession() {
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, options: [.mixWithOthers])
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            print("[SilentAudioPlayer] session error: \(error)")
        }
    }

    // MARK: - web-main avp.swift: playSilentAudio() — mp3 대신 PCM 버퍼 사용
    private func startSilentPlayback() {
        guard !engine.isRunning else { return }
        engine.attach(playerNode)
        let format = AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 1)!
        engine.connect(playerNode, to: engine.mainMixerNode, format: format)
        playerNode.volume = 0
        let frameCount: AVAudioFrameCount = 44100
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else { return }
        buffer.frameLength = frameCount
        do {
            try engine.start()
        } catch {
            print("[SilentAudioPlayer] engine error: \(error)")
            return
        }
        playerNode.scheduleBuffer(buffer, at: nil, options: .loops)
        playerNode.play()
    }

    // 웹뷰에서 다시 음소거될 때 세션 점유를 재확보
    func reclaimSession() {
        configureAudioSession()
        if !engine.isRunning || !playerNode.isPlaying {
            startSilentPlayback()
        }
    }
}
