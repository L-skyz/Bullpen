import SwiftUI

struct ProfileView: View {
    @EnvironmentObject var auth: AuthService
    @EnvironmentObject var filter: BlockFilter

    var body: some View {
        Form {
            // ── 프로필 ──
            Section {
                HStack {
                    Image(systemName: "person.circle.fill")
                        .font(.system(size: 48))
                        .foregroundColor(.orange)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(auth.nickname.isEmpty ? "회원" : auth.nickname)
                            .font(.headline)
                        Text("mlbpark.donga.com")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .padding(.vertical, 8)
            }

            // ── 내 활동 ──
            Section("내 활동") {
                NavigationLink(destination: DugoutView(source: "my")) {
                    Label("내 게시글", systemImage: "doc.text")
                }
                NavigationLink(destination: DugoutView(source: "mycomment")) {
                    Label("내 댓글", systemImage: "bubble.left.and.bubble.right")
                }
            }

            // ── 차단 설정 ──
            Section("차단 설정") {
                NavigationLink(destination: BlockSettingsView(type: .maemuri)) {
                    HStack {
                        Label("말머리 차단", systemImage: "tag.slash")
                        Spacer()
                        if !filter.blockedMaemuri.isEmpty {
                            Text("\(filter.blockedMaemuri.count)")
                                .font(.caption).foregroundColor(.secondary)
                        }
                    }
                }
                NavigationLink(destination: BlockSettingsView(type: .keyword)) {
                    HStack {
                        Label("키워드 차단", systemImage: "text.badge.xmark")
                        Spacer()
                        if !filter.blockedKeywords.isEmpty {
                            Text("\(filter.blockedKeywords.count)")
                                .font(.caption).foregroundColor(.secondary)
                        }
                    }
                }
                NavigationLink(destination: BlockSettingsView(type: .nickname)) {
                    HStack {
                        Label("닉네임 차단", systemImage: "person.slash")
                        Spacer()
                        if !filter.blockedNicknames.isEmpty {
                            Text("\(filter.blockedNicknames.count)")
                                .font(.caption).foregroundColor(.secondary)
                        }
                    }
                }
            }

            // ── 개발 ──
            Section("개발") {
                NavigationLink(destination: LogView()) {
                    Label("시작 로그", systemImage: "list.bullet.rectangle")
                }
            }

            // ── 로그아웃 ──
            Section {
                Button(role: .destructive) {
                    auth.logout()
                } label: {
                    Text("로그아웃").frame(maxWidth: .infinity)
                }
            }
        }
        .navigationTitle("내 정보")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - LogView (임시 진단용)

struct LogView: View {
    @ObservedObject private var logger = AppLogger.shared

    var body: some View {
        List {
            if logger.entries.isEmpty {
                Text("로그 없음\n앱 완전 종료 후 재시작하세요.")
                    .foregroundColor(.secondary).font(.caption)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .listRowBackground(Color.clear)
            } else {
                ForEach(logger.entries) { entry in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(entry.timeStr)
                            .font(.caption2.monospaced()).foregroundColor(.orange)
                        Text(entry.message)
                            .font(.caption.monospaced()).lineLimit(5)
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
                Button("복사") {
                    let text = logger.entries
                        .map { "\($0.timeStr) \($0.message)" }
                        .joined(separator: "\n")
                    UIPasteboard.general.string = text
                }
            }
            ToolbarItem(placement: .navigationBarLeading) {
                Button("초기화") { logger.clear() }
            }
        }
    }
}
