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

    var body: some View {
        NavigationStack {
            List {
                ForEach(vm.posts) { post in
                    NavigationLink(value: post) {
                        PostRowView(post: post)
                    }
                    .listRowSeparator(.visible)
                    .listRowInsets(.init(top: 8, leading: 12, bottom: 8, trailing: 12))
                    .onAppear {
                        if post.id == vm.posts.last?.id {
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
            .navigationTitle(board.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        withAnimation(.easeInOut(duration: 0.25)) {
                            showBoardDrawer = true
                        }
                    } label: {
                        Image(systemName: "list.bullet.rectangle")
                    }
                }
            }
            .navigationDestination(for: Post.self) { post in
                PostDetailView(boardId: post.boardId, postId: post.id)
            }
            .task(id: board.id) { await vm.load(boardId: board.id, reset: true) }
            .refreshable { await vm.load(boardId: board.id, reset: true) }
        }
        .gesture(
            DragGesture(minimumDistance: 40, coordinateSpace: .local)
                .onEnded { v in
                    if v.translation.width < -60 && abs(v.translation.height) < 60 {
                        withAnimation(.easeInOut(duration: 0.25)) {
                            showBoardDrawer = true
                        }
                    }
                }
        )
        .overlay {
            if showBoardDrawer {
                BoardDrawer(selectedBoard: $board, isShowing: $showBoardDrawer)
                    .transition(.opacity)
            }
        }
    }
}

// MARK: - Post Row

struct PostRowView: View {
    let post: Post

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            // 아바타 원형
            ZStack {
                Circle()
                    .fill(avatarColor(for: post.author))
                    .frame(width: 42, height: 42)
                Text(String(post.author.prefix(1)))
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(.white)
            }

            VStack(alignment: .leading, spacing: 5) {
                // 작성자 + 날짜
                HStack(alignment: .center, spacing: 0) {
                    Text(post.author)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .lineLimit(1)
                    Spacer()
                    Text(post.date)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                // 말머리 + 제목 + 댓글수
                HStack(alignment: .top, spacing: 4) {
                    if !post.maemuri.isEmpty {
                        Text(post.maemuri)
                            .font(.caption2)
                            .fontWeight(.semibold)
                            .foregroundColor(.blue)
                            .fixedSize()
                    }
                    Text(post.title)
                        .font(.subheadline)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                    if post.commentCount > 0 {
                        Text("[\(post.commentCount)]")
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundColor(.red)
                            .fixedSize()
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

// MARK: - Board Drawer

struct BoardDrawer: View {
    @Binding var selectedBoard: Board
    @Binding var isShowing: Bool

    var body: some View {
        ZStack(alignment: .trailing) {
            Color.black.opacity(0.35)
                .ignoresSafeArea()
                .onTapGesture {
                    withAnimation(.easeInOut(duration: 0.25)) { isShowing = false }
                }

            VStack(alignment: .leading, spacing: 0) {
                Text("게시판")
                    .font(.title3)
                    .fontWeight(.bold)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 16)

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
                            Text(board.name)
                                .font(.body)
                                .foregroundColor(.primary)
                            Spacer()
                            if board.id == selectedBoard.id {
                                Image(systemName: "checkmark")
                                    .foregroundColor(.blue)
                                    .fontWeight(.semibold)
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
