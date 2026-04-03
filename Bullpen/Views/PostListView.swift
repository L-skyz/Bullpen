import SwiftUI

// SearchScope는 SearchView.swift에 정의

@MainActor
class PostListViewModel: ObservableObject {
    private struct LoadKey: Hashable {
        let generation: Int
        let page: Int
    }

    @Published var posts: [Post] = []
    @Published var isLoading = false
    @Published var error: String?
    @Published var hasMore = true
    @Published var newPostCount = 0

    private var page = 1
    private var generation = 0
    private var loadingPages: Set<LoadKey> = []
    private var pendingNewPosts: [Post] = []
    private var pollingTask: Task<Void, Never>?

    // MARK: - 일반 로드

    func load(boardId: String, maemuri: String? = nil, reset: Bool = false) async {
        await Task.detached(priority: reset ? .userInitiated : .utility) { [weak self] in
            guard let self else { return }
            await self.runLoad(boardId: boardId, maemuri: maemuri, reset: reset)
        }.value
    }

    private func runLoad(boardId: String, maemuri: String? = nil, reset: Bool = false) async {
        if reset {
            generation += 1
            page = 1
            hasMore = true
            loadingPages.removeAll()
            isLoading = false
            // 풀 리셋 시 대기 중인 새 게시글 초기화
            pendingNewPosts = []
            newPostCount = 0
        }

        let currentGeneration = generation
        let startPage = reset ? 1 : page
        let loadKey = LoadKey(generation: currentGeneration, page: startPage)
        guard hasMore else { return }
        guard reset || !loadingPages.contains(loadKey) else { return }

        loadingPages.insert(loadKey)
        if !reset { isLoading = true }
        error = nil
        defer {
            loadingPages.remove(loadKey)
            isLoading = !loadingPages.isEmpty
        }

        do {
            let newPosts: [Post]
            if let m = maemuri, !m.isEmpty {
                newPosts = try await MLBParkService.shared.fetchPostsByMaemuri(boardId: boardId, maemuri: m, page: startPage)
            } else {
                newPosts = try await MLBParkService.shared.fetchPosts(boardId: boardId, page: startPage)
            }

            guard currentGeneration == generation else { return }

            page = startPage + 1
            if newPosts.isEmpty { hasMore = false }
            if reset {
                posts = newPosts
            } else {
                posts.append(contentsOf: newPosts)
            }
        } catch is CancellationError {
        } catch let e as URLError where e.code == .cancelled {
        } catch {
            self.error = error.localizedDescription
        }
    }

    // MARK: - 자동 폴링 (봇 탐지 회피: 60-90초 랜덤 간격)

    func startPolling(boardId: String, maemuri: String?) {
        stopPolling()
        pollingTask = Task { [weak self] in
            while !Task.isCancelled {
                // 60~90초 랜덤 지터 → 고정 주기 패턴 방지
                let jitter = UInt64.random(in: 60_000_000_000...90_000_000_000)
                try? await Task.sleep(nanoseconds: jitter)
                guard !Task.isCancelled, let self else { break }
                await self.silentRefresh(boardId: boardId, maemuri: maemuri)
            }
        }
    }

    func stopPolling() {
        pollingTask?.cancel()
        pollingTask = nil
    }

    private func silentRefresh(boardId: String, maemuri: String?) async {
        // 사용자가 페이지를 로드 중이면 건너뜀 (요청 중복 방지)
        guard !isLoading, !posts.isEmpty else { return }
        do {
            let fresh: [Post]
            if let m = maemuri, !m.isEmpty {
                fresh = try await MLBParkService.shared.fetchPostsByMaemuri(boardId: boardId, maemuri: m, page: 1)
            } else {
                fresh = try await MLBParkService.shared.fetchPosts(boardId: boardId, page: 1)
            }
            guard !Task.isCancelled else { return }

            let existingIds = Set(posts.prefix(60).map { $0.id })
            let incoming = fresh.filter { !existingIds.contains($0.id) }
            guard !incoming.isEmpty else { return }

            pendingNewPosts = incoming
            newPostCount = incoming.count
        } catch {
            // 백그라운드 갱신 실패는 조용히 무시
        }
    }

    /// 배너를 탭했을 때 대기 중인 새 게시글을 목록 상단에 삽입
    func applyPendingPosts() {
        guard !pendingNewPosts.isEmpty else { return }
        posts = pendingNewPosts + posts
        pendingNewPosts = []
        newPostCount = 0
    }

    func clearPendingPosts() {
        pendingNewPosts = []
        newPostCount = 0
    }
}

struct PostListView: View {
    @Binding var board: Board
    var reloadTrigger: Int = 0
    @EnvironmentObject var auth: AuthService
    @EnvironmentObject var filter: BlockFilter
    @StateObject private var vm = PostListViewModel()
    @StateObject private var kboVM = KboScoreViewModel()
    @Environment(\.scenePhase) private var scenePhase
    @State private var selectedMaemuri = "전체"
    @State private var initializedBoardID: String?
    @State private var scrollToTopTrigger = 0
    @State private var showSearch = false
    @State private var showLoginAlert = false
    @State private var pendingPost: Post? = nil
    @State private var isAtTop = true

    private var maemurList: [String] {
        board.maemuri.isEmpty ? [] : ["전체"] + board.maemuri
    }
    private var activeMaemuri: String? {
        selectedMaemuri == "전체" ? nil : selectedMaemuri
    }
    /// 차단 필터 적용된 게시글 목록
    private var filteredPosts: [Post] {
        vm.posts.filter { !filter.isBlocked($0) }
    }

    var body: some View {
        ZStack(alignment: .top) {
        ScrollViewReader { proxy in
        List {
            // 상단 감지용 앵커 (스크롤 위치 추적)
            Color.clear.frame(height: 0)
                .id("__top__")
                .listRowInsets(EdgeInsets())
                .listRowSeparator(.hidden)
                .onAppear { isAtTop = true }
                .onDisappear { isAtTop = false }

            if board.id == "kbotown" {
                KboScoreBannerView(vm: kboVM)
                    .listRowInsets(EdgeInsets())
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
            }
            ForEach(filteredPosts) { post in
                Button {
                    if isRestricted(post.maemuri) && !auth.isLoggedIn {
                        showLoginAlert = true
                    } else {
                        pendingPost = post
                    }
                } label: {
                    PostRowView(post: post)
                }
                .buttonStyle(.plain)
                .listRowInsets(EdgeInsets(top: 0, leading: 12, bottom: 0, trailing: 12))
                .listRowSeparator(.hidden)
                .id(post.id)
                .onAppear {
                    // 마지막 5개 안에 들어오면 미리 로드 (빠른 스크롤 대응)
                    if vm.posts.suffix(5).contains(where: { $0.id == post.id }) {
                        Task { await vm.load(boardId: board.id, maemuri: activeMaemuri) }
                    }
                }
            }
            if vm.isLoading {
                HStack { Spacer(); ProgressView(); Spacer() }.padding()
                    .listRowSeparator(.hidden)
            }
            if let err = vm.error {
                Text(err).foregroundColor(.red).font(.caption).padding()
                    .listRowSeparator(.hidden)
            }
        }
        .listStyle(.plain)
        .refreshable {
            vm.clearPendingPosts()
            await withTaskGroup(of: Void.self) { group in
                group.addTask { await vm.load(boardId: board.id, maemuri: activeMaemuri, reset: true) }
                if board.id == "kbotown" { group.addTask { await kboVM.refresh() } }
            }
            if let first = filteredPosts.first { proxy.scrollTo(first.id, anchor: .top) }
        }
        .onChange(of: scrollToTopTrigger) { _, _ in
            proxy.scrollTo("__top__", anchor: .top)
        }
        .onChange(of: vm.newPostCount) { _, count in
            // 이미 상단에 있으면 자동 적용 후 스크롤 유지
            if count > 0 && isAtTop {
                vm.applyPendingPosts()
                proxy.scrollTo("__top__", anchor: .top)
            }
        }
        } // ScrollViewReader

        // 새 게시글 알림 배너 (스크롤 내려가 있을 때만 표시)
        if vm.newPostCount > 0 && !isAtTop {
            NewPostBanner(count: vm.newPostCount) {
                vm.applyPendingPosts()
                scrollToTopTrigger += 1
            }
            .transition(.move(edge: .top).combined(with: .opacity))
            .animation(.spring(response: 0.35, dampingFraction: 0.8), value: vm.newPostCount)
            .padding(.top, 8)
            .zIndex(1)
        }
        } // ZStack
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
                                scrollToTopTrigger += 1
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
            guard initializedBoardID != board.id else { return }
            initializedBoardID = board.id
            selectedMaemuri = "전체"
            scrollToTopTrigger += 1
            await vm.load(boardId: board.id, reset: true)
            if board.id == "kbotown" { kboVM.start() }
            vm.startPolling(boardId: board.id, maemuri: activeMaemuri)
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                vm.startPolling(boardId: board.id, maemuri: activeMaemuri)
                if board.id == "kbotown" { kboVM.start() }
            } else {
                vm.stopPolling()
                if board.id == "kbotown" { kboVM.stop() }
            }
        }
        .onChange(of: reloadTrigger) { _, _ in
            selectedMaemuri = "전체"
            scrollToTopTrigger += 1
            Task { await vm.load(boardId: board.id, reset: true) }
            vm.startPolling(boardId: board.id, maemuri: activeMaemuri)
        }
    }

    private func isRestricted(_ maemuri: String) -> Bool {
        maemuri.contains("17금") || maemuri.contains("19금") || maemuri.contains("주번나")
    }
}

// MARK: - New Post Banner

struct NewPostBanner: View {
    let count: Int
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 6) {
                Image(systemName: "arrow.up")
                    .font(.caption.weight(.bold))
                Text("새 게시글 \(count)개")
                    .font(.caption.weight(.semibold))
            }
            .foregroundColor(.white)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(Color.orange.opacity(0.92))
            .clipShape(Capsule())
            .shadow(color: .black.opacity(0.18), radius: 4, y: 2)
        }
        .buttonStyle(.plain)
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
                            .font(post.maemuri == "└" ? .body : .caption2)
                            .fontWeight(.semibold)
                            .foregroundColor(.orange).lineLimit(1)
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
        let palette: [Color] = [.orange, .green, .orange, .purple, .pink, .teal, .indigo, .red, .cyan]
        let hash = name.unicodeScalars.reduce(0) { $0 + Int($1.value) }
        return palette[abs(hash) % palette.count]
    }
}

