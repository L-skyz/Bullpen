import SwiftUI

enum AppSection: Equatable {
    case board
    case best
    case write
    case profile
}

struct ContentView: View {
    @EnvironmentObject var auth: AuthService
    @State private var section: AppSection = .board
    @State private var selectedBoard: Board = Board.all.first(where: { $0.id == "bullpen" }) ?? Board.all[0]
    @State private var showDrawer = false

    var body: some View {
        NavigationStack {
            ZStack {
                Group {
                    switch section {
                    case .board:
                        PostListView(board: $selectedBoard)
                    case .best:
                        BestPostsView()
                    case .write:
                        WritePostView()
                    case .profile:
                        if auth.isLoggedIn { ProfileView() } else { LoginView() }
                    }
                }

                if showDrawer {
                    AppDrawer(selectedBoard: $selectedBoard, section: $section, isShowing: $showDrawer)
                        .transition(.move(edge: .leading))
                }
            }
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button {
                        withAnimation(.easeInOut(duration: 0.25)) { showDrawer = true }
                    } label: {
                        Image(systemName: "list.bullet.rectangle")
                    }
                }
            }
        }
        .gesture(
            DragGesture(minimumDistance: 40, coordinateSpace: .local)
                .onEnded { v in
                    let dx = v.translation.width
                    let dy = abs(v.translation.height)
                    if dx > 60 && dy < 80 {
                        withAnimation(.easeInOut(duration: 0.25)) { showDrawer = true }
                    } else if dx < -60 && dy < 80 {
                        withAnimation(.easeInOut(duration: 0.25)) { showDrawer = false }
                    }
                }
        )
    }
}

// MARK: - App Drawer

struct AppDrawer: View {
    @Binding var selectedBoard: Board
    @Binding var section: AppSection
    @Binding var isShowing: Bool

    var body: some View {
        ZStack(alignment: .leading) {
            Color.black.opacity(0.35)
                .ignoresSafeArea()
                .onTapGesture {
                    withAnimation(.easeInOut(duration: 0.25)) { isShowing = false }
                }

            VStack(alignment: .leading, spacing: 0) {
                Text("메뉴")
                    .font(.title3).fontWeight(.bold)
                    .padding(.horizontal, 20).padding(.vertical, 16)

                Divider()

                List {
                    Section("게시판") {
                        ForEach(Board.all) { board in
                            Button {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    selectedBoard = board
                                    section = .board
                                    isShowing = false
                                }
                            } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: "bubble.left.and.bubble.right.fill")
                                        .foregroundColor(section == .board && board.id == selectedBoard.id ? .blue : .secondary)
                                        .frame(width: 24)
                                    Text(board.name).font(.body).foregroundColor(.primary)
                                    Spacer()
                                    if section == .board && board.id == selectedBoard.id {
                                        Image(systemName: "checkmark")
                                            .foregroundColor(.blue).fontWeight(.semibold)
                                    }
                                }
                                .padding(.vertical, 6)
                            }
                        }
                    }

                    Section {
                        drawerItem(label: "베스트", icon: "star.fill", target: .best)
                        drawerItem(label: "글쓰기", icon: "square.and.pencil", target: .write)
                        drawerItem(label: "로그인 / 내 정보", icon: "person.circle", target: .profile)
                    }
                }
                .listStyle(.plain)
            }
            .frame(width: min(UIScreen.main.bounds.width * 0.72, 300))
            .background(Color(.systemBackground))
        }
    }

    @ViewBuilder
    private func drawerItem(label: String, icon: String, target: AppSection) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                section = target
                isShowing = false
            }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .foregroundColor(section == target ? .blue : .secondary)
                    .frame(width: 24)
                Text(label).font(.body).foregroundColor(.primary)
                Spacer()
                if section == target {
                    Image(systemName: "checkmark")
                        .foregroundColor(.blue).fontWeight(.semibold)
                }
            }
            .padding(.vertical, 6)
        }
    }
}
