import SwiftUI

// MARK: - ViewModel

@MainActor
class DugoutViewModel: ObservableObject {
    @Published var items: [DugoutItem] = []
    @Published var isLoading = false
    @Published var error: String?
    @Published var hasMore = true
    private var page = 1
    private var currentSource = ""

    func load(source: String, reset: Bool = false) async {
        currentSource = source
        let startPage = reset ? 1 : page
        if reset { hasMore = true }
        guard hasMore else { return }
        isLoading = true; error = nil
        do {
            let newItems = try await MLBParkService.shared.fetchDugout(source: source, page: startPage)
            if reset { items = [] }
            page = startPage + 1
            if newItems.isEmpty { hasMore = false }
            items.append(contentsOf: newItems)
        } catch { self.error = error.localizedDescription }
        isLoading = false
    }

    func delete(_ item: DugoutItem) async {
        do {
            if item.isComment {
                try await MLBParkService.shared.deleteMyComment(itemId: item.id, seq: item.deleteSeq)
            } else {
                try await MLBParkService.shared.deleteMyPost(boardId: item.boardId, postId: item.id)
            }
            withAnimation { items.removeAll { $0.id == item.id } }
        } catch {
            self.error = error.localizedDescription
        }
    }

    func deleteSelected(_ ids: Set<String>) async {
        for id in ids {
            guard let item = items.first(where: { $0.id == id }) else { continue }
            await delete(item)
        }
    }
}

// MARK: - View

struct DugoutView: View {
    let source: String   // "my" | "mycomment"

    @StateObject private var vm = DugoutViewModel()
    @State private var editMode: EditMode = .inactive
    @State private var selectedIds: Set<String> = []
    @State private var confirmBulkDelete = false
    @State private var navigateItem: DugoutItem? = nil

    private var navTitle: String { source == "my" ? "내 게시글" : "내 댓글" }

    var body: some View {
        List(selection: $selectedIds) {
            ForEach(vm.items) { item in
                Button {
                    navigateItem = item
                } label: {
                    DugoutItemRow(item: item)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                    Button(role: .destructive) {
                        Task { await vm.delete(item) }
                    } label: {
                        Label("삭제", systemImage: "trash")
                    }
                }
            }

            // 더 보기
            if !vm.items.isEmpty && vm.hasMore && !vm.isLoading {
                Button {
                    Task { await vm.load(source: source) }
                } label: {
                    Text("더 보기")
                        .frame(maxWidth: .infinity, alignment: .center)
                        .foregroundColor(.blue)
                }
                .listRowBackground(Color(.systemBackground))
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
        .environment(\.editMode, $editMode)
        .navigationDestination(item: $navigateItem) { item in
            PostDetailView(boardId: item.boardId, postId: item.originalPostId)
        }
        .navigationTitle(navTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                EditButton()
            }
            ToolbarItemGroup(placement: .bottomBar) {
                if editMode == .active {
                    Button("전체 선택") {
                        selectedIds = Set(vm.items.map { $0.id })
                    }
                    .font(.subheadline)
                    Spacer()
                    Button {
                        guard !selectedIds.isEmpty else { return }
                        confirmBulkDelete = true
                    } label: {
                        Text(selectedIds.isEmpty ? "선택 삭제" : "삭제 (\(selectedIds.count))")
                            .font(.subheadline)
                            .foregroundColor(selectedIds.isEmpty ? .secondary : .red)
                    }
                    .disabled(selectedIds.isEmpty)
                }
            }
        }
        .confirmationDialog(
            "\(selectedIds.count)개를 삭제하시겠습니까?",
            isPresented: $confirmBulkDelete,
            titleVisibility: .visible
        ) {
            Button("삭제", role: .destructive) {
                let ids = selectedIds
                selectedIds = []
                editMode = .inactive
                Task { await vm.deleteSelected(ids) }
            }
        }
        .overlay {
            if vm.items.isEmpty && !vm.isLoading {
                VStack(spacing: 12) {
                    Image(systemName: source == "my" ? "doc.text" : "bubble.left")
                        .font(.system(size: 44)).foregroundColor(.secondary)
                    Text(source == "my" ? "작성한 게시글이 없습니다" : "작성한 댓글이 없습니다")
                        .foregroundColor(.secondary)
                }
            }
        }
        .task { await vm.load(source: source, reset: true) }
    }
}

// MARK: - Row

struct DugoutItemRow: View {
    let item: DugoutItem

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(item.title)
                .font(.subheadline)
                .lineLimit(2)
                .foregroundColor(.primary)
            HStack(spacing: 6) {
                if !item.boardName.isEmpty && item.boardName != "댓글" {
                    Text(item.boardName)
                        .font(.caption2).fontWeight(.semibold)
                        .foregroundColor(.blue)
                        .padding(.horizontal, 5).padding(.vertical, 2)
                        .background(Color.blue.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                } else if item.isComment {
                    Label("댓글", systemImage: "bubble.left.fill")
                        .font(.caption2).foregroundColor(.green)
                }
                Spacer()
                Text(item.date)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}
