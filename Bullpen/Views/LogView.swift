import SwiftUI

struct LogView: View {
    @ObservedObject private var logger = AppLogger.shared

    var body: some View {
        List {
            if logger.entries.isEmpty {
                Text("로그 없음\n앱을 완전히 종료 후 재시작하세요.")
                    .foregroundColor(.secondary)
                    .font(.caption)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .listRowBackground(Color.clear)
            } else {
                ForEach(logger.entries) { entry in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(entry.timeStr)
                            .font(.caption2.monospaced())
                            .foregroundColor(.orange)
                        Text(entry.message)
                            .font(.caption.monospaced())
                            .lineLimit(5)
                    }
                    .listRowInsets(EdgeInsets(top: 6, leading: 12, bottom: 6, trailing: 12))
                }
            }
        }
        .listStyle(.plain)
        .navigationTitle("시작 로그")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button("초기화") { logger.clear() }
            }
        }
    }
}
