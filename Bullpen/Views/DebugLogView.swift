import SwiftUI

@MainActor
final class AppLogger: ObservableObject {
    static let shared = AppLogger()
    @Published var logs: [String] = []

    private init() {}

    func log(_ msg: String) {
        let time = DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .medium)
        logs.insert("[\(time)] \(msg)", at: 0)
        if logs.count > 200 { logs.removeLast() }
    }

    func clear() { logs.removeAll() }
}

struct DebugLogView: View {
    @StateObject private var logger = AppLogger.shared

    private var allText: String {
        logger.logs.reversed().joined(separator: "\n")
    }

    var body: some View {
        List(logger.logs, id: \.self) { line in
            Text(line)
                .font(.system(size: 12, design: .monospaced))
                .foregroundColor(color(for: line))
        }
        .navigationTitle("디버그 로그")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Menu {
                    Button {
                        UIPasteboard.general.string = allText
                    } label: {
                        Label("복사", systemImage: "doc.on.doc")
                    }
                    ShareLink(item: allText) {
                        Label("내보내기", systemImage: "square.and.arrow.up")
                    }
                    Divider()
                    Button(role: .destructive) {
                        logger.clear()
                    } label: {
                        Label("지우기", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
    }

    private func color(for line: String) -> Color {
        if line.contains("❌") { return .red }
        if line.contains("⚠️") { return .orange }
        if line.contains("✅") { return .green }
        return .primary
    }
}
