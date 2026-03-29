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

    /// nil이면 폴링 중단
    private func nextInterval() -> Double? {
        if games.isEmpty { return nil }
        if games.allSatisfy({ $0.inning == "경기종료" }) { return nil }
        if games.contains(where: { $0.isLive }) { return 30 }
        return 300
    }
}
