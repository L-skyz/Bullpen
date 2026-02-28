import SwiftUI

enum SearchScope: String, CaseIterable {
    case title     = "stt"
    case titleBody = "sct"
    case nickname  = "swt"

    var label: String {
        switch self {
        case .title:     return "제목"
        case .titleBody: return "제목+내용"
        case .nickname:  return "닉네임"
        }
    }
}

@MainActor
class PostListViewModel: ObservableObject {
    @Published var posts: [Post] = []
    @Published var searchResults: [Post] = []
    @Published var isLoading = false
    @Published var isSearching = false
    @Published var error: String?
    @Published var searchError: String?
    @Published var hasMore = true
    @Published var hasMoreSearch = true
    private var page = 1
    private var searchPage = 1

    func load(boardId: String, maemuri: String? = nil, reset: Bool = false) async {
        let startPage = reset ? 1 : page
        if reset { hasMore = true }
        guard hasMore else { return }
        isLoading = true; error = nil
        do {
            let newPosts: [Post] = try await (maemuri.map { m in
                MLBParkService.shared.fetchPostsByMaemuri(boardId: boardId, maemuri: m, page: startPage)
            } ?? MLBParkService.shared.fetchPosts(boardId: boardId, page: startPage))
            if reset { posts = [] }
            page = startPage + 1
            if newPosts.isEmpty { hasMore = false }
            posts.append(contentsOf: newPosts)
        } catch is CancellationError {
        } catch let e as URLError where e.code == .cancelled {
        } catch { self.error = error.localizedDescription }
        isLoading = false
    }

    func search(boardId: String, keyword: String, select: String, reset: Bool = false) async {
        let startPage = reset ? 1 : searchPage
        if reset { hasMoreSearch = true }
        guard hasMoreSearch else { return }
        isSearching = true; searchError = nil
        do {
            let newPosts = try await MLBParkService.shared.fetchPostsByKeyword(
                boardId: boardId, keyword: keyword, select: select, page: startPage)
            if reset { searchResults = [] }
            searchPage = startPage + 1
            if newPosts.isEmpty { hasMoreSearch = false }
            searchResults.append(contentsOf: newPosts)
        } catch is CancellationError {
        } catch let e as URLError where e.code == .cancelled {
        } catch { self.searchError = error.localizedDescription }
        isSearching = false
    }

    func clearSearch() {
        searchResults = []; searchPage = 1; hasMoreSearch = true; searchError = nil
    }
}

struct PostListView: View {
    @Binding var board: Board
    @StateObject private var vm = PostListViewModel()
    @State private var selectedMaemuri = "전체"
    @State private var scrollPosition = ScrollPosition(idType: String.self)

    // 검색: .searchable() 없이 툴바 TextField로 직접 구현
    @State private var isSearchActive = false
    @State private var searchText = ""
    @State private var activeKeyword: String? = nil
    @State private var searchScope: SearchScope = .title
    @FocusState private var searchFocused: Bool

    private var maemurList: [String] {
        board.maemuri.isEmpty ? [] : ["전체"] + board.maemuri
    }
    private var activeMaemuri: String? {
        selectedMaemuri == "전체" ? nil : selectedMaemuri
    }

    var body: some View {
        ZStack {
            // ── 일반 게시글 목록 ──
            normalList

            // ── 검색 결과 오버레이 ──
            if activeKeyword != nil {
                searchOverlay
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.18), value: activeKeyword != nil)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            // 검색 활성화 시: 타이틀 자리에 TextField + 취소 버튼
            if isSearchActive {
                ToolbarItem(placement: .principal) {
                    TextField("검색어 입력", text: $searchText)
                        .textFieldStyle(.plain)
                        .font(.body)
                        .focused($searchFocused)
                        .onSubmit { runSearch() }
                        .submitLabel(.search)
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("취소") {
                        closeSearch()
                    }
                }
            } else {
                // 검색 비활성화 시: 돋보기 버튼 + 타이틀/말머리 메뉴
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        isSearchActive = true
                        searchFocused = true
                    } label: {
                        Image(systemName: "magnifyingglass")
                    }
                }
                ToolbarItem(placement: .principal) {
                    if activeKeyword != nil {
                        Text("검색 결과 \(vm.searchResults.count)건")
                            .font(.headline).fontWeight(.semibold)
                    } else if !maemurList.isEmpty {
                        maemurMenu
                    } else {
                        Text(board.name).font(.headline).fontWeight(.semibold)
                    }
                }
            }
        }
        .navigationDestination(for: Post.self) { post in
            PostDetailView(boardId: post.boardId, postId: post.id)
        }
        .task(id: board.id) {
            closeSearch()
            selectedMaemuri = "전체"
            scrollPosition = ScrollPosition(idType: String.self)
            await vm.load(boardId: board.id, reset: true)
        }
    }

    // MARK: - 검색 동작

    private func runSearch() {
        let kw = searchText.trimmingCharacters(in: .whitespaces)
        guard !kw.isEmpty else { return }
        activeKeyword = kw
        isSearchActive = false   // 키보드/TextField 닫기
        searchFocused = false
        vm.clearSearch()
        Task { await vm.search(boardId: board.id, keyword: kw, select: searchScope.rawValue, reset: true) }
    }

    private func closeSearch() {
        isSearchActive = false
        searchFocused = false
        searchText = ""
        activeKeyword = nil
        searchScope = .title
        vm.clearSearch()
    }

    // MARK: - 말머리 메뉴

    @ViewBuilder
    private var maemurMenu: some View {
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
    }

    // MARK: - 일반 목록

    @ViewBuilder
    private var normalList: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(vm.posts) { post in
                    VStack(spacing: 0) {
                        NavigationLink(value: post) {
                            PostRowView(post: post)
                                .padding(.horizontal, 12).padding(.vertical, 8)
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
    }

    // MARK: - 검색 결과 오버레이

    @ViewBuilder
    private var searchOverlay: some View {
        ZStack {
            Color(.systemBackground).ignoresSafeArea()

            VStack(spacing: 0) {
                // 검색 범위 세그먼트
                Picker("", selection: $searchScope) {
                    ForEach(SearchScope.allCases, id: \.self) { scope in
                        Text(scope.label).tag(scope)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 16).padding(.vertical, 8)
                .onChange(of: searchScope) { _, _ in
                    guard let kw = activeKeyword else { return }
                    vm.clearSearch()
                    Task { await vm.search(boardId: board.id, keyword: kw, select: searchScope.rawValue, reset: true) }
                }

                Divider()

                if vm.isSearching && vm.searchResults.isEmpty {
                    Spacer(); ProgressView(); Spacer()
                } else if vm.searchResults.isEmpty {
                    Spacer()
                    VStack(spacing: 12) {
                        Image(systemName: "doc.text.magnifyingglass")
                            .font(.system(size: 44)).foregroundColor(.secondary)
                        Text("검색 결과가 없습니다").foregroundColor(.secondary)
                        if let err = vm.searchError {
                            Text(err).font(.caption).foregroundColor(.red)
                        }
                    }
                    Spacer()
                } else {
                    List {
                        ForEach(vm.searchResults) { post in
                            NavigationLink(value: post) { PostRowView(post: post) }
                                .listRowInsets(EdgeInsets(top: 4, leading: 12, bottom: 4, trailing: 12))
                                .listRowBackground(Color(.systemBackground))
                                .onAppear {
                                    if post.id == vm.searchResults.last?.id, let kw = activeKeyword {
                                        Task { await vm.search(boardId: board.id, keyword: kw, select: searchScope.rawValue) }
                                    }
                                }
                        }
                        if vm.isSearching {
                            HStack { Spacer(); ProgressView(); Spacer() }
                                .listRowBackground(Color(.systemBackground))
                        }
                    }
                    .listStyle(.plain)
                }
            }
        }
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
