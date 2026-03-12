import SwiftUI

struct ProfileView: View {
    @EnvironmentObject var auth: AuthService
    @EnvironmentObject var filter: BlockFilter
    @State private var showLogoutAlert = false

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {

                // ── 프로필 헤더 ──────────────────────────────
                VStack(spacing: 12) {
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
                                    .font(.system(size: 38))
                                    .foregroundColor(.white)
                            }
                        }
                    }
                    .frame(width: 80, height: 80)
                    .clipShape(Circle())
                    .shadow(color: .orange.opacity(0.3), radius: 8, y: 4)

                    Text(auth.nickname.isEmpty ? "회원" : auth.nickname)
                        .font(.title3).fontWeight(.bold)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 32)
                .background(Color(.systemBackground))

                Divider()

                // ── 내 활동 ──────────────────────────────────
                menuSection(title: "내 활동") {
                    menuRow(icon: "doc.text", iconColor: .orange, label: "내 게시글") {
                        DugoutView(source: "my")
                    }
                    Divider().padding(.leading, 52)
                    menuRow(icon: "bubble.left.and.bubble.right", iconColor: .orange, label: "내 댓글") {
                        DugoutView(source: "mycomment")
                    }
                }

                // ── 차단 설정 ────────────────────────────────
                menuSection(title: "차단 설정") {
                    menuRow(icon: "tag.slash", iconColor: .indigo, label: "말머리 차단",
                            badge: filter.blockedMaemuri.isEmpty ? nil : "\(filter.blockedMaemuri.count)") {
                        BlockSettingsView(type: .maemuri)
                    }
                    Divider().padding(.leading, 52)
                    menuRow(icon: "text.badge.xmark", iconColor: .indigo, label: "키워드 차단",
                            badge: filter.blockedKeywords.isEmpty ? nil : "\(filter.blockedKeywords.count)") {
                        BlockSettingsView(type: .keyword)
                    }
                    Divider().padding(.leading, 52)
                    menuRow(icon: "person.slash", iconColor: .indigo, label: "닉네임 차단",
                            badge: filter.blockedNicknames.isEmpty ? nil : "\(filter.blockedNicknames.count)") {
                        BlockSettingsView(type: .nickname)
                    }
                }

                // ── 로그아웃 ─────────────────────────────────
                VStack(spacing: 0) {
                    Button {
                        showLogoutAlert = true
                    } label: {
                        HStack {
                            Image(systemName: "rectangle.portrait.and.arrow.right")
                                .foregroundColor(.red)
                                .frame(width: 28)
                            Text("로그아웃")
                                .foregroundColor(.red)
                            Spacer()
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 14)
                        .background(Color(.secondarySystemGroupedBackground))
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 32)
            }
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("내 정보")
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog("로그아웃 하시겠습니까?", isPresented: $showLogoutAlert, titleVisibility: .visible) {
            Button("로그아웃", role: .destructive) { auth.logout() }
        }
    }

    // MARK: - 헬퍼

    @ViewBuilder
    private func menuSection<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundColor(.secondary)
                .padding(.horizontal, 16)
                .padding(.top, 20)
                .padding(.bottom, 6)

            VStack(spacing: 0) {
                content()
            }
            .background(Color(.secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .padding(.horizontal, 16)
        }
    }

    @ViewBuilder
    private func menuRow<Dest: View>(
        icon: String,
        iconColor: Color,
        label: String,
        badge: String? = nil,
        destination: () -> Dest
    ) -> some View {
        NavigationLink(destination: destination()) {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 7)
                        .fill(iconColor)
                        .frame(width: 28, height: 28)
                    Image(systemName: icon)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.white)
                }
                Text(label)
                    .foregroundColor(.primary)
                Spacer()
                if let badge {
                    Text(badge)
                        .font(.caption)
                        .foregroundColor(.white)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .background(Color.secondary.opacity(0.5))
                        .clipShape(Capsule())
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 13)
        }
    }
}
