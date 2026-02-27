import SwiftUI

@MainActor
class PostListViewModel: ObservableObject {
    @Published var posts: [Post] = []
    @Published var isLoading = false
    @Published var error: String?
    @Published var hasMore = true
    private var page = 1

    func load(boardId: String, reset: Bool = false) async {
        if reset { page = 1; posts = []; hasMore = true }
        guard hasMore else { return }
        isLoading = true
        error = nil
        do {
            let newPosts = try await MLBParkService.shared.fetchPosts(boardId: boardId, page: page)
            if newPosts.isEmpty { hasMore = false }
            posts.append(contentsOf: newPosts)
            page += 1
        } catch {
            self.error = error.localizedDescription
        }
        isLoading = false
    }
}

struct PostListView: View {
    @Binding var board: Board
    @StateObject private var vm = PostListViewModel()
    @State private var showBoardDrawer = false
    @State private var selectedMaemuri: String = "전체"

    // 로드된 게시글에서 고유 말머리 추출
    private var uniqueMaemuris: [String] {
        let found = vm.posts.compactMap { $0.maemuri.isEmpty ? nil : $0.maemuri }
        let unique = Array(Set(found)).sorted()
        return ["전체"] + unique
    }

    // 말머리 필터 적용된 게시글
    private var filteredPosts: [Post] {
        guard selectedMaemuri != "전체" else { return vm.posts }
        return vm.posts.filter { $0.maemuri == selectedMaemuri }
    }

    var body: some View {
        ZStack {
            List {
                ForEach(filteredPosts) { post in
                    NavigationLink(value: post) {
                        PostRowView(post: post)
                    }
                    .listRowSeparator(.visible)
                    .listRowInsets(.init(top: 8, leading: 12, bottom: 8, trailing: 12))
                    .onAppear {
                        // 필터 없을 때만 무한스크롤
                        if selectedMaemuri == "전체", post.id == vm.posts.last?.id {
                            Task { await vm.load(boardId: board.id) }
                        }
                    }
                }

                if vm.isLoading {
                    HStack { Spacer(); ProgressView(); Spacer() }
                        .listRowBackground(Color.clear)
                }
                if let err = vm.error {
                    Text(err).foregroundColor(.red).font(.caption)
                        .listRowBackground(Color.clear)
                }
            }
            .listStyle(.plain)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                // 좌측: 게시판 드로어 토글 버튼
                ToolbarItem(placement: .navigationBarLeading) {
                    Button {
                        withAnimation(.easeInOut(duration: 0.25)) { showBoardDrawer = true }
                    } label: {
                        Image(systemName: "list.bullet.rectangle")
                    }
                }

                // 중앙: 게시판 제목 + 말머리 필터 드롭다운
                ToolbarItem(placement: .principal) {
                    if uniqueMaemuris.count > 1 {
                        Menu {
                            ForEach(uniqueMaemuris, id: \.self) { m in
                                Button {
                                    selectedMaemuri = m
                                } label: {
                                    if m == selectedMaemuri {
                                        Label(m, systemImage: "checkmark")
                                    } else {
                                        Text(m)
                                    }
                                }
                            }
                        } label: {
                            HStack(spacing: 3) {
                                Text(selectedMaemuri == "전체"
                                     ? board.name
                                     : "\(board.name) · \(selectedMaemuri)")
                                    .font(.headline).fontWeight(.semibold)
                                    .foregroundColor(.primary)
                                Image(systemName: "chevron.down")
                                    .font(.caption2).fontWeight(.semibold)
                                    .foregroundColor(.secondary)
                            }
                        }
                    } else {
                        Text(board.name)
                            .font(.headline).fontWeight(.semibold)
                    }
                }
            }
            .navigationDestination(for: Post.self) { post in
                PostDetailView(boardId: post.boardId, postId: post.id)
            }
            .task(id: board.id) {
                selectedMaemuri = "전체"
                await vm.load(boardId: board.id, reset: true)
            }
            .refreshable {
                selectedMaemuri = "전체"
                await vm.load(boardId: board.id, reset: true)
            }

            // 왼쪽에서 슬라이드되는 게시판 드로어
            if showBoardDrawer {
                BoardDrawer(selectedBoard: $board, isShowing: $showBoardDrawer)
                    .transition(.move(edge: .leading))
            }
        }
        // 오른쪽 스와이프 → 드로어 열기, 왼쪽 스와이프 → 닫기
        .gesture(
            DragGesture(minimumDistance: 40, coordinateSpace: .local)
                .onEnded { v in
                    let dx = v.translation.width
                    let dy = abs(v.translation.height)
                    if dx > 60 && dy < 80 {
                        withAnimation(.easeInOut(duration: 0.25)) { showBoardDrawer = true }
                    } else if dx < -60 && dy < 80 {
                        withAnimation(.easeInOut(duration: 0.25)) { showBoardDrawer = false }
                    }
                }
        )
    }
}

// MARK: - Post Row

struct PostRowView: View {
    let post: Post

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            ZStack {
                Circle()
                    .fill(avatarColor(for: post.author))
                    .frame(width: 42, height: 42)
                Text(String(post.author.prefix(1)))
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(.white)
            }

            VStack(alignment: .leading, spacing: 5) {
                HStack(alignment: .center) {
                    Text(post.author)
                        .font(.subheadline).fontWeight(.semibold)
                        .lineLimit(1)
                    Spacer()
                    Text(post.date)
                        .font(.caption).foregroundColor(.secondary)
                }

                HStack(alignment: .top, spacing: 4) {
                    if !post.maemuri.isEmpty {
                        Text(post.maemuri)
                            .font(.caption2).fontWeight(.semibold)
                            .foregroundColor(.blue).fixedSize()
                    }
                    Text(post.title)
                        .font(.subheadline).lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                    if post.commentCount > 0 {
                        Text("[\(post.commentCount)]")
                            .font(.caption).fontWeight(.semibold)
                            .foregroundColor(.red).fixedSize()
                    }
                }
            }
        }
        .padding(.vertical, 2)
    }

    private func avatarColor(for name: String) -> Color {
        let palette: [Color] = [.blue, .green, .orange, .purple, .pink, .teal, .indigo, .red, .cyan]
        let hash = name.unicodeScalars.reduce(0) { $0 + Int($1.value) }
        return palette[abs(hash) % palette.count]
    }
}

// MARK: - Board Drawer (왼쪽에서 슬라이드)

struct BoardDrawer: View {
    @Binding var selectedBoard: Board
    @Binding var isShowing: Bool

    var body: some View {
        ZStack(alignment: .leading) {
            // 배경 딤 - 탭하면 닫기
            Color.black.opacity(0.35)
                .ignoresSafeArea()
                .onTapGesture {
                    withAnimation(.easeInOut(duration: 0.25)) { isShowing = false }
                }

            // 왼쪽 패널
            VStack(alignment: .leading, spacing: 0) {
                Text("게시판")
                    .font(.title3).fontWeight(.bold)
                    .padding(.horizontal, 20).padding(.vertical, 16)

                Divider()

                List(Board.all) { board in
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            selectedBoard = board
                            isShowing = false
                        }
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "bubble.left.and.bubble.right.fill")
                                .foregroundColor(board.id == selectedBoard.id ? .blue : .secondary)
                                .frame(width: 24)
                            Text(board.name).font(.body).foregroundColor(.primary)
                            Spacer()
                            if board.id == selectedBoard.id {
                                Image(systemName: "checkmark")
                                    .foregroundColor(.blue).fontWeight(.semibold)
                            }
                        }
                        .padding(.vertical, 6)
                    }
                }
                .listStyle(.plain)
            }
            .frame(width: min(UIScreen.main.bounds.width * 0.72, 300))
            .background(Color(.systemBackground))
            .ignoresSafeArea(edges: .vertical)
        }
    }
}
