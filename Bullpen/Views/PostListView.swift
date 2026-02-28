import SwiftUI

// SearchScope는 SearchView.swift에 정의

@MainActor
class PostListViewModel: ObservableObject {
    @Published var posts: [Post] = []
    @Published var isLoading = false
    @Published var error: String?
    @Published var hasMore = true
    private var page = 1

    func load(boardId: String, maemuri: String? = nil, reset: Bool = false) async {
        let startPage = reset ? 1 : page
        if reset { hasMore = true }
        guard hasMore else { return }
        isLoading = true; error = nil
        do {
            let newPosts: [Post]
            if let m = maemuri, !m.isEmpty {
                newPosts = try await MLBParkService.shared.fetchPostsByMaemuri(boardId: boardId, maemuri: m, page: startPage)
            } else {
                newPosts = try await MLBParkService.shared.fetchPosts(boardId: boardId, page: startPage)
            }
            if reset { posts = [] }
            page = startPage + 1
            if newPosts.isEmpty { hasMore = false }
            posts.append(contentsOf: newPosts)
        } catch is CancellationError {
        } catch let e as URLError where e.code == .cancelled {
        } catch { self.error = error.localizedDescription }
        isLoading = false
    }
}

struct PostListView: View {
    @Binding var board: Board
    @EnvironmentObject var auth: AuthService
    @StateObject private var vm = PostListViewModel()
    @State private var selectedMaemuri = "전체"
    @State private var scrollPosition = ScrollPosition(idType: String.self)
    @State private var showSearch = false
    @State private var showLoginAlert = false
    @State private var pendingPost: Post? = nil

    private var maemurList: [String] {
        board.maemuri.isEmpty ? [] : ["전체"] + board.maemuri
    }
    private var activeMaemuri: String? {
        selectedMaemuri == "전체" ? nil : selectedMaemuri
    }

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(vm.posts) { post in
                    VStack(spacing: 0) {
                        Button {
                            if isRestricted(post.maemuri) && !auth.isLoggedIn {
                                showLoginAlert = true
                            } else {
                                pendingPost = post
                            }
                        } label: {
                            PostRowView(post: post)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                        }
                        .buttonStyle(.plain)
                        Divider().padding(.leading, 44)
                    }
                    .id(post.id)
                    .onAppear {
                        if post.id == vm.posts.last?.id {
                            Task { await vm.load(boardId: board.id, maemuri: activeMaemuri) }
                        }
                    }
                }
                if vm.isLoading { HStack { Spacer(); ProgressView(); Spacer() }.padding() }
                if let err = vm.error { Text(err).foregroundColor(.red).font(.caption).padding() }
            }
        }
        .scrollPosition($scrollPosition)
        .refreshable {
            scrollPosition = ScrollPosition(idType: String.self)
            await vm.load(boardId: board.id, maemuri: activeMaemuri, reset: true)
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    showSearch = true
                } label: {
                    Image(systemName: "magnifyingglass")
                }
            }
            ToolbarItem(placement: .principal) {
                if !maemurList.isEmpty {
                    Menu {
                        ForEach(maemurList, id: \.self) { m in
                            Button {
                                guard m != selectedMaemuri else { return }
                                selectedMaemuri = m
                                scrollPosition = ScrollPosition(idType: String.self)
                                Task { await vm.load(boardId: board.id, maemuri: activeMaemuri, reset: true) }
                            } label: {
                                if m == selectedMaemuri { Label(m, systemImage: "checkmark") }
                                else { Text(m) }
                            }
                        }
                    } label: {
                        HStack(spacing: 3) {
                            Text(selectedMaemuri == "전체" ? board.name : "\(board.name) · \(selectedMaemuri)")
                                .font(.headline).fontWeight(.semibold).foregroundColor(.primary)
                            Image(systemName: "chevron.down")
                                .font(.caption2).fontWeight(.semibold).foregroundColor(.secondary)
                        }
                    }
                } else {
                    Text(board.name).font(.headline).fontWeight(.semibold)
                }
            }
        }
        .navigationDestination(item: $pendingPost) { post in
            PostDetailView(boardId: post.boardId, postId: post.id)
        }
        .navigationDestination(isPresented: $showSearch) {
            SearchView(boardId: board.id)
        }
        .alert("로그인이 필요합니다", isPresented: $showLoginAlert) {
            Button("로그인") {
                NotificationCenter.default.post(name: .navigateToLogin, object: nil)
            }
            Button("취소", role: .cancel) {}
        } message: {
            Text("성인 콘텐츠는 로그인 후 이용할 수 있습니다.")
        }
        .task(id: board.id) {
            selectedMaemuri = "전체"
            scrollPosition = ScrollPosition(idType: String.self)
            await vm.load(boardId: board.id, reset: true)
        }
    }

    private func isRestricted(_ maemuri: String) -> Bool {
        maemuri.contains("17금") || maemuri.contains("19금") || maemuri.contains("주번나")
    }
}

// MARK: - Post Row

struct PostRowView: View {
    let post: Post

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            AsyncImage(url: URL(string: post.avatarUrl)) { phase in
                switch phase {
                case .success(let img): img.resizable().scaledToFill()
                default:
                    ZStack {
                        Circle().fill(avatarColor(for: post.author))
                        Text(String(post.author.prefix(1)))
                            .font(.system(size: 9, weight: .bold)).foregroundColor(.white)
                    }
                }
            }
            .frame(width: 28, height: 28).clipShape(Circle())

            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .center, spacing: 4) {
                    if !post.maemuri.isEmpty {
                        Text(post.maemuri)
                            .font(.caption2).fontWeight(.semibold)
                            .foregroundColor(.blue).lineLimit(1)
                    }
                    Text(post.title).font(.subheadline).lineLimit(1).truncationMode(.tail)
                    if post.commentCount > 0 {
                        Text("[\(post.commentCount)]")
                            .font(.caption).fontWeight(.semibold)
                            .foregroundColor(.red).lineLimit(1)
                    }
                }
                HStack {
                    Text(post.author).font(.caption).foregroundColor(.secondary).lineLimit(1)
                    Spacer()
                    Text(post.date).font(.caption).foregroundColor(.secondary)
                }
            }
        }
        .padding(.vertical, 4)
    }

    private func avatarColor(for name: String) -> Color {
        let palette: [Color] = [.blue, .green, .orange, .purple, .pink, .teal, .indigo, .red, .cyan]
        let hash = name.unicodeScalars.reduce(0) { $0 + Int($1.value) }
        return palette[abs(hash) % palette.count]
    }
}
