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
    @State private var selectedPost: Post? = nil
    @State private var debounceTask: Task<Void, Never>? = nil
    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(spacing: 0) {

            // ── 검색 입력창 ──
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(isFocused ? .orange : .secondary)
                    .animation(.easeInOut(duration: 0.2), value: isFocused)
                TextField("검색어 입력", text: $searchText)
                    .focused($isFocused)
                    .onSubmit { runSearch() }
                    .submitLabel(.search)
                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                        activeKeyword = nil
                        debounceTask?.cancel()
                        vm.clear()
                    } label: {
                        Image(systemName: "xmark.circle.fill").foregroundColor(.secondary)
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(isFocused ? Color(.systemBackground) : Color(.secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(isFocused ? Color.orange : Color.clear, lineWidth: 1.5)
            )
            .shadow(color: isFocused ? Color.orange.opacity(0.2) : .clear, radius: 6, y: 2)
            .animation(.easeInOut(duration: 0.2), value: isFocused)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)

            // ── 칩 필터 ──
            HStack(spacing: 6) {
                ForEach(SearchScope.allCases, id: \.self) { scope in
                    Button {
                        guard scope != searchScope else { return }
                        searchScope = scope
                        if let kw = activeKeyword {
                            vm.clear()
                            Task { await vm.search(boardId: boardId, keyword: kw, select: scope.rawValue, reset: true) }
                        }
                    } label: {
                        Text(scope.label)
                            .font(.subheadline)
                            .fontWeight(searchScope == scope ? .semibold : .regular)
                            .foregroundColor(searchScope == scope ? .white : .secondary)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 6)
                            .background(
                                Capsule()
                                    .fill(searchScope == scope ? Color.orange : Color(.secondarySystemBackground))
                                    .shadow(color: searchScope == scope ? Color.orange.opacity(0.3) : .clear,
                                            radius: 4, y: 2)
                            )
                    }
                    .buttonStyle(.plain)
                    .animation(.spring(response: 0.25, dampingFraction: 0.8), value: searchScope)
                }
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 10)
            .frame(maxWidth: .infinity, alignment: .leading)

            Divider()

            // ── 상태별 콘텐츠 ──
            Group {
                if activeKeyword == nil {
                    emptyPrompt(
                        icon: "magnifyingglass",
                        message: "게시글 검색",
                        description: "제목, 내용, 닉네임으로\n게시글을 찾을 수 있어요"
                    )
                } else if vm.isLoading && vm.results.isEmpty {
                    Spacer(); ProgressView(); Spacer()
                } else if vm.results.isEmpty {
                    emptyPrompt(
                        icon: "doc.text.magnifyingglass",
                        message: "검색 결과가 없습니다",
                        error: vm.error
                    )
                } else {
                    resultList
                }
            }
        }
        .background(Color(.systemBackground))
        .navigationTitle("검색")
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(item: $selectedPost) { post in
            PostDetailView(boardId: post.boardId, postId: post.id)
        }
        .onAppear { isFocused = true }
        .onChange(of: searchText) { _, newValue in
            debounceTask?.cancel()
            let kw = newValue.trimmingCharacters(in: .whitespaces)
            guard !kw.isEmpty else {
                activeKeyword = nil
                vm.clear()
                return
            }
            debounceTask = Task {
                try? await Task.sleep(nanoseconds: 400_000_000) // 0.4초
                guard !Task.isCancelled else { return }
                activeKeyword = kw
                vm.clear()
                await vm.search(boardId: boardId, keyword: kw, select: searchScope.rawValue, reset: true)
            }
        }
    }

    // MARK: - 서브뷰

    @ViewBuilder
    private func emptyPrompt(icon: String, message: String, description: String? = nil, error: String? = nil) -> some View {
        Spacer()
        VStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 14)
                    .fill(Color(.secondarySystemBackground))
                    .frame(width: 56, height: 56)
                Image(systemName: icon)
                    .font(.system(size: 26))
                    .foregroundColor(.secondary)
            }
            Text(message)
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundColor(.primary)
            if let desc = description {
                Text(desc)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
            if let e = error {
                Text(e).font(.caption).foregroundColor(.red)
            }
        }
        Spacer()
    }

    @ViewBuilder
    private var resultList: some View {
        // 결과 수 표시
        if let kw = activeKeyword {
            HStack(spacing: 0) {
                Text("'\(kw)' 검색 결과 ")
                    .foregroundColor(.secondary)
                Text("\(vm.results.count)건")
                    .foregroundColor(.orange)
                    .fontWeight(.semibold)
            }
            .font(.caption)
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.systemBackground))

            Divider()
        }

        List {
            ForEach(vm.results) { post in
                Button {
                    selectedPost = post
                } label: {
                    PostRowView(post: post, keyword: activeKeyword)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
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
