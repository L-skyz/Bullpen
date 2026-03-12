import SwiftUI

struct ProfileView: View {
    @EnvironmentObject var auth: AuthService
    @EnvironmentObject var filter: BlockFilter
    @State private var showLogoutAlert = false

    var body: some View {
        List {
            // ── 프로필 헤더 ──────────────────────────────
            Section {
                HStack(spacing: 16) {
                    AsyncImage(url: URL(string: auth.avatarUrl)) { phase in
                        switch phase {
                        case .success(let img):
                            img.resizable().scaledToFill()
                        default:
                            ZStack {
                                Circle()
                                    .fill(LinearGradient(
                                        colors: [.orange, .orange.opacity(0.6)],
                                        startPoint: .topLeading, endPoint: .bottomTrailing))
                                Image(systemName: "person.fill")
                                    .font(.system(size: 28))
                                    .foregroundColor(.white)
                            }
                        }
                    }
                    .frame(width: 60, height: 60)
                    .clipShape(Circle())

                    Text(auth.nickname.isEmpty ? "회원" : auth.nickname)
                        .font(.title3).fontWeight(.semibold)
                }
                .padding(.vertical, 8)
            }

            // ── 내 활동 ──────────────────────────────────
            Section("내 활동") {
                NavigationLink(destination: DugoutView(source: "my")) {
                    Label("내 게시글", systemImage: "doc.text")
                }
                NavigationLink(destination: DugoutView(source: "mycomment")) {
                    Label("내 댓글", systemImage: "bubble.left.and.bubble.right")
                }
            }

            // ── 차단 설정 ────────────────────────────────
            Section("차단 설정") {
                NavigationLink(destination: BlockSettingsView(type: .maemuri)) {
                    LabeledContent {
                        if !filter.blockedMaemuri.isEmpty {
                            Text("\(filter.blockedMaemuri.count)")
                                .foregroundColor(.secondary)
                        }
                    } label: {
                        Label("말머리 차단", systemImage: "tag.slash")
                    }
                }
                NavigationLink(destination: BlockSettingsView(type: .keyword)) {
                    LabeledContent {
                        if !filter.blockedKeywords.isEmpty {
                            Text("\(filter.blockedKeywords.count)")
                                .foregroundColor(.secondary)
                        }
                    } label: {
                        Label("키워드 차단", systemImage: "text.badge.xmark")
                    }
                }
                NavigationLink(destination: BlockSettingsView(type: .nickname)) {
                    LabeledContent {
                        if !filter.blockedNicknames.isEmpty {
                            Text("\(filter.blockedNicknames.count)")
                                .foregroundColor(.secondary)
                        }
                    } label: {
                        Label("닉네임 차단", systemImage: "person.slash")
                    }
                }
            }

            // ── 로그아웃 ─────────────────────────────────
            Section {
                Button(role: .destructive) {
                    showLogoutAlert = true
                } label: {
                    Label("로그아웃", systemImage: "rectangle.portrait.and.arrow.right")
                }
                .alert("로그아웃", isPresented: $showLogoutAlert) {
                    Button("로그아웃", role: .destructive) { auth.logout() }
                    Button("취소", role: .cancel) {}
                } message: {
                    Text("로그아웃 하시겠습니까?")
                }
            }
        }
        .listStyle(.insetGrouped)
        .background(Color(.systemBackground))
        .scrollContentBackground(.hidden)
        .tint(.orange)
        .navigationTitle("내 정보")
        .navigationBarTitleDisplayMode(.inline)
    }
}
