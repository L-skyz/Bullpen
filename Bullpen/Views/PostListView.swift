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
    let board: Board
    @StateObject private var vm = PostListViewModel()
    @State private var tab: ListTab = .realtime

    enum ListTab: String, CaseIterable {
        case realtime = "실시간"
        case weekly   = "주간"
        case monthly  = "월간"
    }

    var body: some View {
        List {
            // 탭 세그먼트
            Section {
                Picker("", selection: $tab) {
                    ForEach(ListTab.allCases, id: \.self) { t in
                        Text(t.rawValue).tag(t)
                    }
                }
                .pickerStyle(.segmented)
            }
            .listRowInsets(.init(top: 8, leading: 8, bottom: 8, trailing: 8))
            .listRowBackground(Color.clear)

            ForEach(vm.posts) { post in
                NavigationLink(value: post) {
                    PostRowView(post: post)
                }
                .onAppear {
                    // 마지막 항목 근처에서 다음 페이지 로드
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
            }
        }
        .listStyle(.plain)
        .navigationTitle(board.name)
        .navigationBarTitleDisplayMode(.large)
        .task { await vm.load(boardId: board.id, reset: true) }
        .refreshable { await vm.load(boardId: board.id, reset: true) }
        .onChange(of: tab) { _ in Task { await vm.load(boardId: board.id, reset: true) } }
    }
}

struct PostRowView: View {
    let post: Post

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .top, spacing: 6) {
                if !post.maemuri.isEmpty {
                    Text(post.maemuri)
                        .font(.caption2)
                        .fontWeight(.semibold)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.blue.opacity(0.12))
                        .foregroundColor(.blue)
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                        .fixedSize()
                }
                Text(post.title)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .lineLimit(2)
                if post.commentCount > 0 {
                    Text("[\(post.commentCount)]")
                        .font(.caption)
                        .foregroundColor(.red)
                        .fixedSize()
                }
            }
            HStack(spacing: 8) {
                Text(post.author)
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text(post.date)
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
                Label("\(post.views)", systemImage: "eye")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 3)
    }
}
