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
                        .foregroundColor(.blue)
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
