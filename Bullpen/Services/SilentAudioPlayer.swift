import AVFoundation

/// AVAudioSession을 끊김 없이 유지하기 위해 무음 PCM 버퍼를 루프 재생한다.
/// YouTube WKWebView의 음소거 버튼이 첫 번째 탭에 반응하지 않는 문제를
/// (세션 재협상 지연) 방지하는 역할을 한다.
final class SilentAudioPlayer: @unchecked Sendable {
    static let shared = SilentAudioPlayer()

    private let engine     = AVAudioEngine()
    private let playerNode = AVAudioPlayerNode()

    private init() {}

    func start() {
        guard !engine.isRunning else { return }

        engine.attach(playerNode)

        let format = AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 1)!
        engine.connect(playerNode, to: engine.mainMixerNode, format: format)

        // 볼륨 0 — 실제로 소리가 나지 않음
        playerNode.volume = 0

        // 1초짜리 무음 버퍼 (zero-fill, 파일 불필요)
        let frameCount: AVAudioFrameCount = 44100
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else { return }
        buffer.frameLength = frameCount

        do {
            try engine.start()
        } catch {
            print("[SilentAudioPlayer] engine start failed: \(error)")
            return
        }

        playerNode.scheduleBuffer(buffer, at: nil, options: .loops)
        playerNode.play()
    }

    func stop() {
        playerNode.stop()
        engine.stop()
    }
}
