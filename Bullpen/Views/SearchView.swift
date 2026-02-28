import SwiftUI

// MARK: - SearchScope

enum SearchScope: String, CaseIterable, Hashable {
    case title       = "stt"   // 제목
    case titleContent = "sct"  // 제목+내용
    case author      = "swt"   // 닉네임

    var label: String {
        switch self {
        case .title:        return "제목"
        case .titleContent: return "제목+내용"
        case .author:       return "닉네임"
        }
    }
}

// MARK: - ViewModel

@MainActor
class SearchViewModel: ObservableObject {
    @Published var results: [Post] = []
    @Published var isLoading = false
    @Published var error: String?
    @Published var hasMore = true
    private var page = 1

    func search(boardId: String, keyword: String, select: String, reset: Bool = false) async {
        let startPage = reset ? 1 : page
        if reset { hasMore = true }
        guard hasMore else { return }
        isLoading = true; error = nil
        do {
            let newPosts = try await MLBParkService.shared.fetchPostsByKeyword(
                boardId: boardId, keyword: keyword, select: select, page: startPage)
            if reset { results = [] }
            page = startPage + 1
            if newPosts.isEmpty { hasMore = false }
            results.append(contentsOf: newPosts)
        } catch is CancellationError {
        } catch let e as URLError where e.code == .cancelled {
        } catch { self.error = error.localizedDescription }
        isLoading = false
    }

    func clear() {
        results = []; page = 1; hasMore = true; error = nil
    }
}

// MARK: - View

struct SearchView: View {
    let boardId: String

    @StateObject private var vm = SearchViewModel()
    @State private var searchText = ""
    @State private var searchScope: SearchScope = .title
    @State private var activeKeyword: String? = nil
    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(spacing: 0) {

            // ── 검색 입력창 ──
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundColor(.secondary)
                TextField("검색어 입력", text: $searchText)
                    .focused($isFocused)
                    .onSubmit { runSearch() }
                    .submitLabel(.search)
                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                        activeKeyword = nil
                        vm.clear()
                    } label: {
                        Image(systemName: "xmark.circle.fill").foregroundColor(.secondary)
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(Color(.secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .padding(.horizontal, 16)
            .padding(.vertical, 8)

            // ── 검색 범위 피커 ──
            Picker("", selection: $searchScope) {
                ForEach(SearchScope.allCases, id: \.self) { scope in
                    Text(scope.label).tag(scope)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 16)
            .padding(.bottom, 8)
            .onChange(of: searchScope) { _, _ in
                guard let kw = activeKeyword else { return }
                vm.clear()
                Task { await vm.search(boardId: boardId, keyword: kw, select: searchScope.rawValue, reset: true) }
            }

            Divider()

            // ── 상태별 콘텐츠 ──
            Group {
                if activeKeyword == nil {
                    emptyPrompt(icon: "magnifyingglass", message: "검색어를 입력하세요")
                } else if vm.isLoading && vm.results.isEmpty {
                    Spacer(); ProgressView(); Spacer()
                } else if vm.results.isEmpty {
                    emptyPrompt(icon: "doc.text.magnifyingglass",
                                message: "검색 결과가 없습니다",
                                sub: vm.error)
                } else {
                    resultList
                }
            }
        }
        .background(Color(.systemBackground))
        .navigationTitle("검색")
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(for: Post.self) { post in
            PostDetailView(boardId: post.boardId, postId: post.id)
        }
        .onAppear { isFocused = true }
    }

    // MARK: - 서브뷰

    @ViewBuilder
    private func emptyPrompt(icon: String, message: String, sub: String? = nil) -> some View {
        Spacer()
        VStack(spacing: 12) {
            Image(systemName: icon).font(.system(size: 44)).foregroundColor(.secondary)
            Text(message).foregroundColor(.secondary)
            if let s = sub { Text(s).font(.caption).foregroundColor(.red) }
        }
        Spacer()
    }

    @ViewBuilder
    private var resultList: some View {
        List {
            ForEach(vm.results) { post in
                NavigationLink(value: post) {
                    PostRowView(post: post)
                }
                .listRowInsets(EdgeInsets(top: 4, leading: 12, bottom: 4, trailing: 12))
                .listRowBackground(Color(.systemBackground))
                .onAppear {
                    if post.id == vm.results.last?.id, let kw = activeKeyword {
                        Task { await vm.search(boardId: boardId, keyword: kw, select: searchScope.rawValue) }
                    }
                }
            }
            if vm.isLoading {
                HStack { Spacer(); ProgressView(); Spacer() }
                    .listRowBackground(Color(.systemBackground))
            }
            if let err = vm.error {
                Text(err).font(.caption).foregroundColor(.red)
                    .listRowBackground(Color(.systemBackground))
            }
        }
        .listStyle(.plain)
    }

    // MARK: - 검색 실행

    private func runSearch() {
        let kw = searchText.trimmingCharacters(in: .whitespaces)
        guard !kw.isEmpty else { return }
        isFocused = false
        activeKeyword = kw
        vm.clear()
        Task { await vm.search(boardId: boardId, keyword: kw, select: searchScope.rawValue, reset: true) }
    }
}
