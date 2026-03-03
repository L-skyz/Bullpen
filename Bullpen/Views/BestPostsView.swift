import SwiftUI

// MARK: - ViewModel

@MainActor
class BestPostsViewModel: ObservableObject {
    enum BestType: String, CaseIterable, Identifiable {
        case like  = "최다추천"
        case reply = "최다댓글"
        case view  = "최고조회"
        var id: String { rawValue }
        var param: String {
            switch self { case .like: "like"; case .reply: "reply"; case .view: "view" }
        }
    }

    struct Section: Identifiable {
        let board: Board
        var posts: [Post] = []
        var id: String { board.id }
    }

    static let bestBoards: [Board] = Board.all.filter {
        ["bullpen", "kbotown", "worldbullpen"].contains($0.id)
    }.sorted {
        let order = ["bullpen": 0, "kbotown": 1, "worldbullpen": 2]
        return (order[$0.id] ?? 9) < (order[$1.id] ?? 9)
    }

    @Published var sections: [Section] = bestBoards.map { Section(board: $0) }
    @Published var isLoading = false
    @Published var selectedType: BestType = .like
    private var loadGeneration = 0

    func load(type: BestType) async {
        loadGeneration += 1
        let generation = loadGeneration
        isLoading = true
        sections = Self.bestBoards.map { Section(board: $0) }
        await withTaskGroup(of: (String, [Post]).self) { group in
            for board in Self.bestBoards {
                group.addTask {
                    let posts = (try? await MLBParkService.shared.fetchBestPosts(boardId: board.id, type: type.param)) ?? []
                    return (board.id, posts)
                }
            }
            for await (boardId, posts) in group {
                guard generation == loadGeneration else { continue }
                if let idx = sections.firstIndex(where: { $0.board.id == boardId }) {
                    sections[idx].posts = posts
                }
            }
        }
        guard generation == loadGeneration else { return }
        isLoading = false
    }
}

// MARK: - View

struct BestPostsView: View {
    @StateObject private var vm = BestPostsViewModel()

    var body: some View {
        Group {
            if vm.isLoading && vm.sections.allSatisfy({ $0.posts.isEmpty }) {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0, pinnedViews: .sectionHeaders) {
                        Section {
                            ForEach(vm.sections) { section in
                                BestBoardSection(section: section)
                            }
                        } header: {
                            Picker("", selection: $vm.selectedType) {
                                ForEach(BestPostsViewModel.BestType.allCases) { t in
                                    Text(t.rawValue).tag(t)
                                }
                            }
                            .pickerStyle(.segmented)
                            .padding(.horizontal, 16).padding(.vertical, 8)
                            .background(Color(.systemBackground))
                        }
                    }
                }
                .scrollBounceBehavior(.always)
                .refreshable {
                    await vm.load(type: vm.selectedType)
                }
            }
        }
        .navigationTitle("베스트")
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(for: Post.self) { post in
            PostDetailView(boardId: post.boardId, postId: post.id)
        }
        .task { await vm.load(type: vm.selectedType) }
        .onChange(of: vm.selectedType) { _, newType in
            Task { await vm.load(type: newType) }
        }
    }
}

// MARK: - 게시판 섹션

struct BestBoardSection: View {
    let section: BestPostsViewModel.Section

    var body: some View {
        VStack(spacing: 0) {
            // 섹션 헤더
            HStack {
                Text(section.board.name)
                    .font(.subheadline).fontWeight(.bold)
                    .foregroundColor(.primary)
                Spacer()
            }
            .padding(.horizontal, 16).padding(.vertical, 10)
            .background(Color(.secondarySystemBackground))

            Divider()

            if section.posts.isEmpty {
                HStack { Spacer(); ProgressView().padding(); Spacer() }
            } else {
                ForEach(Array(section.posts.enumerated()), id: \.element.id) { idx, post in
                    NavigationLink(value: post) {
                        BestPostRow(rank: idx + 1, post: post)
                    }
                    .buttonStyle(.plain)

                    if idx < section.posts.count - 1 {
                        Divider().padding(.leading, 44)
                    }
                }
            }

            Divider()
        }
    }
}

// MARK: - 베스트 포스트 행

struct BestPostRow: View {
    let rank: Int
    let post: Post

    var body: some View {
        HStack(spacing: 10) {
            // 순위
            Text("\(rank)")
                .font(.system(size: 13, weight: .bold))
                .foregroundColor(rank <= 3 ? .orange : .secondary)
                .frame(width: 22, alignment: .center)

            VStack(alignment: .leading, spacing: 2) {
                Text(post.title)
                    .font(.subheadline)
                    .lineLimit(1)
                    .truncationMode(.tail)
                HStack {
                    Text(post.author)
                        .font(.caption).foregroundColor(.secondary)
                    Spacer()
                    Text(post.date)
                        .font(.caption).foregroundColor(.secondary)
                }
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 8)
    }
}
