import Foundation

struct LogEntry: Identifiable {
    let id = UUID()
    let elapsed: Double
    let message: String
    var timeStr: String { String(format: "+%.3fs", elapsed) }
}

/// 어디서든 await 없이 호출 가능 (DispatchQueue.main.async 사용)
func appLog(_ message: String) {
    DispatchQueue.main.async {
        AppLogger.shared.append(message)
    }
}

@MainActor
class AppLogger: ObservableObject {
    static let shared = AppLogger()
    private let t0 = Date()
    @Published private(set) var entries: [LogEntry] = []

    private init() {}

    fileprivate func append(_ message: String) {
        let elapsed = Date().timeIntervalSince(t0)
        entries.append(LogEntry(elapsed: elapsed, message: message))
        print("[AppLog] +\(String(format: "%.3f", elapsed))s \(message)")
    }

    func clear() { entries.removeAll() }
}
