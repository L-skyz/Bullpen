import SwiftUI

@MainActor
final class KboScoreViewModel: ObservableObject {
    @Published var games: [KboGame] = []
    @Published var error: String? = nil
    @Published var lastUpdated: Date? = nil

    private var pollingTask: Task<Void, Never>? = nil

    func start() {
        guard pollingTask == nil else { return }
        pollingTask = Task { [weak self] in await self?.pollLoop() }
    }

    func stop() {
        pollingTask?.cancel()
        pollingTask = nil
    }

    func refresh() async {
        await fetch()
    }

    private func pollLoop() async {
        while !Task.isCancelled {
            await fetch()
            guard !Task.isCancelled else { return }
            guard let interval = nextInterval() else { return }
            try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
        }
    }

    private func fetch() async {
        do {
            let result = try await MLBParkService.shared.fetchKboScores()
            games = result
            error = nil
            lastUpdated = Date()
        } catch {
            self.error = error.localizedDescription
        }
    }

    /// 다음 폴링까지 대기 시간(초). nil이면 폴링 중단.
    private func nextInterval() -> Double? {
        if games.isEmpty { return nil }
        if games.allSatisfy({ $0.inning == "경기종료" }) { return nil }
        if games.contains(where: { $0.isLive }) { return 30 }

        // 예정 경기만 있음 → 가장 빠른 경기 시작 시각까지 대기
        if let delay = secondsUntilFirstGame() {
            // 경기 시작 1분 전부터 폴링 시작, 최소 60초 대기
            return max(delay - 60, 60)
        }
        // 시각 파싱 실패 시 5분
        return 300
    }

    /// KST 기준 가장 빠른 예정 경기 시작까지 남은 초. 이미 지났으면 0.
    private func secondsUntilFirstGame() -> Double? {
        let kst = TimeZone(identifier: "Asia/Seoul")!
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyyMMdd HH:mm"
        fmt.timeZone = kst

        let todayStr = {
            let d = DateFormatter()
            d.dateFormat = "yyyyMMdd"
            d.timeZone = kst
            return d.string(from: Date())
        }()

        let times: [Date] = games.compactMap { game in
            guard game.inning == "경기예정", !game.gameTime.isEmpty else { return nil }
            return fmt.date(from: "\(todayStr) \(game.gameTime)")
        }

        guard let earliest = times.min() else { return nil }
        return max(earliest.timeIntervalSinceNow, 0)
    }
}
