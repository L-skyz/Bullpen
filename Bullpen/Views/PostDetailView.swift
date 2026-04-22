import SwiftUI
import WebKit
import UIKit

private let detailScreenBackground = Color(red: 0.984, green: 0.984, blue: 0.989)
private let detailCardBackground = Color.white
private let detailCardBorder = Color.black.opacity(0.06)
private let detailChipBackground = Color(red: 0.969, green: 0.957, blue: 1.0)
private let detailChipBorder = Color(red: 0.847, green: 0.816, blue: 1.0)
private let detailAccent = Color(red: 0.451, green: 0.376, blue: 0.875)
private let detailReplyBackground = Color(red: 0.969, green: 0.957, blue: 1.0)
private let detailReplyBorder = Color(red: 0.902, green: 0.882, blue: 0.988)
private let detailThreadColor = Color(red: 0.839, green: 0.839, blue: 0.859)
private let detailReplyIndent: CGFloat = 0
private let detailCommentsSectionID = "detail-comments-section"

@MainActor
class PostDetailViewModel: ObservableObject {
    @Published var detail: PostDetail?
    @Published var isLoading = false
    @Published var error: String?
    @Published var commentInput = ""
    @Published var isSubmittingComment = false
    @Published var isTogglingRecommend = false
    @Published var actionError: String?
    @Published var replyingTo: Comment? = nil
    @Published var newCommentCount = 0
    private var loadGeneration = 0
    private var pendingFreshDetail: PostDetail?
    private var pollingTask: Task<Void, Never>?

    // MARK: - 자동 폴링 (봇 탐지 회피: 30~60초 랜덤 간격)

    func startPolling(boardId: String, postId: String) {
        stopPolling()
        pollingTask = Task { [weak self] in
            var backoff: UInt64 = 0
            while !Task.isCancelled {
                let delay = backoff > 0 ? backoff : UInt64.random(in: 30_000_000_000...60_000_000_000)
                try? await Task.sleep(nanoseconds: delay)
                guard !Task.isCancelled, let self else { break }
                let failed = await self.silentRefresh(boardId: boardId, postId: postId)
                if failed {
                    backoff = min((backoff == 0 ? 60_000_000_000 : backoff) * 2, 240_000_000_000)
                } else {
                    backoff = 0
                }
            }
        }
    }

    func stopPolling() {
        pollingTask?.cancel()
        pollingTask = nil
    }

    /// 성공 시 false, 실패 시 true 반환 (폴링 백오프 제어용)
    @discardableResult
    private func silentRefresh(boardId: String, postId: String) async -> Bool {
        guard !isLoading, let existing = detail else { return false }
        do {
            let fresh = try await MLBParkService.shared.fetchPostDetail(boardId: boardId, postId: postId)
            guard !Task.isCancelled else { return false }
            let existingSeqs = allCommentSeqs(in: existing)
            let freshSeqs = allCommentSeqs(in: fresh)
            let newSeqs = freshSeqs.subtracting(existingSeqs)
            if !newSeqs.isEmpty {
                pendingFreshDetail = fresh
                newCommentCount = newSeqs.count
            }
            return false
        } catch is CancellationError {
            return false
        } catch let e as URLError where e.code == .cancelled {
            return false
        } catch {
            return true
        }
    }

    private func allCommentSeqs(in detail: PostDetail) -> Set<String> {
        var seqs = Set<String>()
        for comment in detail.comments {
            seqs.insert(comment.seq)
            for reply in comment.replies {
                seqs.insert(reply.seq)
            }
        }
        return seqs
    }

    func applyPendingComments() {
        guard let fresh = pendingFreshDetail else { return }
        detail = fresh
        pendingFreshDetail = nil
        newCommentCount = 0
    }

    func clearPendingComments() {
        pendingFreshDetail = nil
        newCommentCount = 0
    }

    func load(boardId: String, postId: String) async {
        loadGeneration += 1
        let generation = loadGeneration

        await Task.detached(priority: .userInitiated) { [weak self] in
            guard let self else { return }
            await self.runLoad(boardId: boardId, postId: postId, generation: generation)
        }.value
    }

    private func runLoad(boardId: String, postId: String, generation: Int) async {
        clearPendingComments()
        isLoading = true
        error = nil
        defer {
            if generation == loadGeneration {
                isLoading = false
            }
        }

        do {
            let detail = try await MLBParkService.shared.fetchPostDetail(boardId: boardId, postId: postId)
            guard generation == loadGeneration else { return }
            self.detail = detail
        } catch is CancellationError {
        } catch let e as URLError where e.code == .cancelled {
        } catch {
            guard generation == loadGeneration else { return }
            self.error = error.localizedDescription
        }
    }

    func submitComment(boardId: String, postId: String) async {
        actionError = nil
        let trimmed = commentInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            actionError = "댓글 내용을 입력해주세요."
            return
        }
        guard trimmed.count <= 300 else {
            actionError = "댓글은 300자 이하로 입력해주세요."
            return
        }
        isSubmittingComment = true
        do {
            let parentPrid = replyingTo?.replyPrid ?? ""
            let parentSeq: String
            if let replyingTo, replyingTo.depth >= 2 {
                parentSeq = replyingTo.replySource
            } else {
                parentSeq = replyingTo?.seq ?? ""
            }
            try await MLBParkService.shared.writeComment(
                boardId: boardId, postId: postId, content: trimmed,
                parentPrid: parentPrid, parentSeq: parentSeq
            )
            commentInput = ""
            replyingTo = nil
            await load(boardId: boardId, postId: postId)
        } catch {
            actionError = error.localizedDescription
        }
        isSubmittingComment = false
    }

    func deletePost(boardId: String, postId: String) async -> Bool {
        actionError = nil
        do {
            try await MLBParkService.shared.deletePost(boardId: boardId, postId: postId)
            return true
        } catch {
            actionError = error.localizedDescription
            return false
        }
    }

    func editPost(boardId: String, postId: String, categoryId: String,
                  title: String, content: String) async -> Bool {
        actionError = nil
        do {
            try await MLBParkService.shared.editPost(boardId: boardId, postId: postId,
                                                     categoryId: categoryId,
                                                     title: title, content: content)
            await load(boardId: boardId, postId: postId)
            return true
        } catch {
            actionError = error.localizedDescription
            return false
        }
    }

    func deleteComment(boardId: String, postId: String, comment: Comment) async {
        actionError = nil
        do {
            try await MLBParkService.shared.deleteComment(boardId: boardId, postId: postId,
                                                          commentSeq: comment.seq)
            await load(boardId: boardId, postId: postId)
        } catch {
            actionError = error.localizedDescription
        }
    }

    func editComment(boardId: String, postId: String, comment: Comment, newContent: String) async {
        actionError = nil
        let trimmed = newContent.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            actionError = "댓글 내용을 입력해주세요."
            return
        }
        guard trimmed.count <= 300 else {
            actionError = "댓글은 300자 이하로 입력해주세요."
            return
        }
        do {
            try await MLBParkService.shared.editComment(boardId: boardId, postId: postId,
                                                        commentSeq: comment.seq, content: trimmed)
            await load(boardId: boardId, postId: postId)
        } catch {
            actionError = error.localizedDescription
        }
    }

    func toggleRecommend(boardId: String, postId: String) async {
        guard !isTogglingRecommend, var detail else { return }

        actionError = nil
        isTogglingRecommend = true
        defer { isTogglingRecommend = false }

        do {
            let result = try await MLBParkService.shared.toggleRecommend(
                boardId: boardId,
                postId: postId,
                isRecommended: detail.isRecommended
            )
            detail.isRecommended = result.isRecommended
            detail.recommendCount = max(0, detail.recommendCount + result.delta)
            self.detail = detail
        } catch {
            actionError = error.localizedDescription
        }
    }
}

struct PostDetailView: View {
    let boardId: String
    let postId: String
    @StateObject private var vm = PostDetailViewModel()
    @EnvironmentObject var auth: AuthService
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @State private var contentHeight: CGFloat = 200
    @FocusState private var commentFocused: Bool

    // 게시글 수정
    @State private var showEditPost = false
    @State private var editTitle = ""
    @State private var editContent = ""
    @State private var editCategoryId = ""
    // 게시글 삭제
    @State private var showDeletePostAlert = false
    // 댓글 수정
    @State private var editingComment: Comment? = nil
    @State private var editCommentText = ""
    // 댓글 삭제
    @State private var deletingComment: Comment? = nil

    private var isMyPost: Bool {
        guard let d = vm.detail else { return false }
        let myNick = auth.nickname.trimmingCharacters(in: .whitespacesAndNewlines)
        let postAuthor = d.author.trimmingCharacters(in: .whitespacesAndNewlines)
        return auth.isLoggedIn && !myNick.isEmpty && postAuthor == myNick
    }

    private var currentBoard: Board? {
        Board.all.first(where: { $0.id == boardId })
    }

    private var editCategories: [BoardCategory] {
        currentBoard?.writeCategories ?? []
    }

    var body: some View {
        Group {
            if let d = vm.detail {
                ScrollViewReader { proxy in
                    ZStack(alignment: .top) {
                        ScrollView {
                            VStack(alignment: .leading, spacing: 18) {
                                headerCard(for: d)

                                HTMLContentView(html: d.contentHTML, height: $contentHeight)
                                    .frame(height: contentHeight)
                                    .padding(18)
                                    .background(detailCardBackground)
                                    .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                                            .stroke(detailCardBorder, lineWidth: 1)
                                    )

                                DetailReactionBar(
                                    recommendCount: d.recommendCount,
                                    commentCount: d.commentCount,
                                    isRecommended: d.isRecommended,
                                    isTogglingRecommend: vm.isTogglingRecommend,
                                    shareURL: d.detailURL,
                                    onRecommend: {
                                        Task {
                                            await vm.toggleRecommend(boardId: boardId, postId: postId)
                                        }
                                    },
                                    onComment: {
                                        withAnimation(.easeInOut(duration: 0.2)) {
                                            proxy.scrollTo(detailCommentsSectionID, anchor: .top)
                                        }
                                    }
                                )

                                commentsSection(for: d)
                                    .id(detailCommentsSectionID)

                                if auth.isLoggedIn {
                                    commentComposer
                                }

                                BurningWidgetView(boardId: boardId)

                                Spacer(minLength: 24)
                            }
                            .padding(.horizontal, 16)
                            .padding(.top, 16)
                            .padding(.bottom, 20)
                        }
                        .background(detailScreenBackground)
                        .refreshable {
                            await vm.load(boardId: boardId, postId: postId)
                        }

                        if vm.newCommentCount > 0 {
                            NewCommentBanner(count: vm.newCommentCount) {
                                vm.applyPendingComments()
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    proxy.scrollTo(detailCommentsSectionID, anchor: .top)
                                }
                            }
                            .transition(.move(edge: .top).combined(with: .opacity))
                            .animation(.spring(response: 0.35, dampingFraction: 0.8), value: vm.newCommentCount)
                            .padding(.top, 8)
                            .zIndex(1)
                        }
                    }
                }
            } else if vm.isLoading {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let err = vm.error {
                ContentUnavailableView(err, systemImage: "exclamationmark.triangle")
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .background(SwipeBackEnabler())
        .background(detailScreenBackground.ignoresSafeArea())
        .task {
            await vm.load(boardId: boardId, postId: postId)
            vm.startPolling(boardId: boardId, postId: postId)
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                vm.startPolling(boardId: boardId, postId: postId)
            } else {
                vm.stopPolling()
            }
        }
        // 게시글 삭제 확인
        .confirmationDialog("게시글을 삭제하시겠습니까?",
                            isPresented: $showDeletePostAlert,
                            titleVisibility: .visible) {
            Button("삭제", role: .destructive) {
                Task {
                    let ok = await vm.deletePost(boardId: boardId, postId: postId)
                    if ok { dismiss() }
                }
            }
            Button("취소", role: .cancel) { }
        }
        // 댓글 삭제 확인
        .confirmationDialog("댓글을 삭제하시겠습니까?",
                            isPresented: Binding(
            get: { deletingComment != nil },
            set: { if !$0 { deletingComment = nil } }
        ),
                            titleVisibility: .visible) {
            Button("삭제", role: .destructive) {
                if let c = deletingComment {
                    Task { await vm.deleteComment(boardId: boardId, postId: postId, comment: c) }
                }
                deletingComment = nil
            }
            Button("취소", role: .cancel) { deletingComment = nil }
        }
        // 댓글 수정 시트
        .sheet(item: $editingComment) { c in
            EditCommentSheet(text: $editCommentText) {
                Task {
                    await vm.editComment(boardId: boardId, postId: postId,
                                        comment: c, newContent: editCommentText)
                }
            }
        }
        // 게시글 수정 시트
        .sheet(isPresented: $showEditPost) {
            EditPostSheet(
                categoryId: $editCategoryId,
                categories: editCategories,
                title: $editTitle,
                content: $editContent
            ) {
                Task {
                    let ok = await vm.editPost(boardId: boardId, postId: postId,
                                               categoryId: editCategoryId,
                                               title: editTitle, content: editContent)
                    if ok { showEditPost = false }
                }
            }
        }
        // 오류 토스트
        .alert("오류", isPresented: Binding(
            get: { vm.actionError != nil },
            set: { if !$0 { vm.actionError = nil } }
        )) {
            Button("확인", role: .cancel) { vm.actionError = nil }
        } message: {
            Text(vm.actionError ?? "")
        }
    }

    @ViewBuilder
    private func headerCard(for detail: PostDetail) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            if !detail.maemuri.isEmpty {
                Text(detail.maemuri)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(detailAccent)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(detailChipBackground)
                    .overlay(
                        Capsule()
                            .stroke(detailChipBorder, lineWidth: 1)
                    )
                    .clipShape(Capsule())
            }

            Text(detail.title)
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(alignment: .center, spacing: 12) {
                DetailAvatarView(url: detail.avatarUrl, author: detail.author, size: 38)

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(detail.author)
                            .font(.subheadline.weight(.semibold))
                        DetailAuthorBadge()
                    }

                    Text(detail.date)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 12)

                HStack(spacing: 10) {
                    Label("\(detail.views)", systemImage: "eye")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    if isMyPost {
                        Menu {
                            Button("수정") {
                                vm.actionError = nil
                                editTitle      = detail.title
                                editContent    = stripHTML(detail.contentHTML)
                                editCategoryId = resolveCategoryId(from: detail.maemuri)
                                showEditPost   = true
                            }
                            Button("삭제", role: .destructive) {
                                showDeletePostAlert = true
                            }
                        } label: {
                            Image(systemName: "ellipsis")
                                .font(.headline)
                                .foregroundStyle(.secondary)
                                .frame(width: 28, height: 28)
                        }
                    }
                }
            }

        }
        .padding(18)
        .background(detailCardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(detailCardBorder, lineWidth: 1)
        )
    }

    @ViewBuilder
    private func commentsSection(for detail: PostDetail) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("댓글 \(detail.commentCount)")
                    .font(.system(size: 22, weight: .bold))
                Spacer()
                Button {
                    Task { await vm.load(boardId: boardId, postId: postId) }
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 28, height: 28)
                }
                .disabled(vm.isLoading)
            }

            if detail.comments.isEmpty {
                Text("첫 댓글을 남겨보세요.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 24)
                    .background(detailCardBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .stroke(detailCardBorder, lineWidth: 1)
                    )
            } else {
                VStack(spacing: 12) {
                    ForEach(detail.comments) { comment in
                        CommentRowView(
                            comment: comment,
                            postAuthorName: detail.author,
                            onEdit: {
                                editCommentText = comment.content
                                editingComment  = comment
                            },
                            onDelete: {
                                deletingComment = comment
                            },
                            onReply: auth.isLoggedIn ? {
                                vm.replyingTo = comment
                                commentFocused = true
                            } : nil,
                            onEditReply: { reply in
                                editCommentText = reply.content
                                editingComment  = reply
                            },
                            onDeleteReply: { reply in
                                deletingComment = reply
                            },
                            onReplyToReply: auth.isLoggedIn ? { reply in
                                vm.replyingTo = reply
                                commentFocused = true
                            } : nil
                        )
                    }
                }
            }
        }
    }

    private var commentComposer: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let replyTo = vm.replyingTo {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.turn.down.left")
                        .font(.caption)
                        .foregroundStyle(detailAccent)
                    Text("@\(replyTo.author)에게 답글")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button {
                        vm.replyingTo = nil
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal, 4)
            }

            HStack(alignment: .center, spacing: 10) {
                TextField(
                    vm.replyingTo == nil ? "댓글을 입력해주세요." : "답글을 입력해주세요.",
                    text: $vm.commentInput,
                    axis: .vertical
                )
                .lineLimit(1...4)
                .padding(.horizontal, 14)
                .padding(.vertical, 14)
                .focused($commentFocused)

                Button {
                    Task { await vm.submitComment(boardId: boardId, postId: postId) }
                } label: {
                    Group {
                        if vm.isSubmittingComment {
                            ProgressView()
                                .tint(detailAccent)
                        } else {
                            Image(systemName: "paperplane.fill")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(detailAccent)
                        }
                    }
                    .frame(width: 38, height: 38)
                    .background(detailChipBackground)
                    .clipShape(Circle())
                }
                .disabled(
                    vm.commentInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                    vm.commentInput.trimmingCharacters(in: .whitespacesAndNewlines).count > 300 ||
                    vm.isSubmittingComment
                )
            }
            .padding(4)
            .background(detailCardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(detailCardBorder, lineWidth: 1)
            )
        }
    }

    private func resolveCategoryId(from maemuri: String) -> String {
        guard let board = currentBoard else { return "" }
        if let exact = board.writeCategories.first(where: { $0.name == maemuri }) {
            return exact.id
        }

        let normalized = normalizeCategoryName(maemuri)
        if let match = board.writeCategories.first(where: { normalizeCategoryName($0.name) == normalized }) {
            return match.id
        }
        return board.writeCategories.first?.id ?? ""
    }

    private func normalizeCategoryName(_ value: String) -> String {
        value.lowercased()
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "/", with: "")
    }

    private func stripHTML(_ html: String) -> String {
        guard let data = html.data(using: .utf8),
              let attr = try? NSAttributedString(
                data: data,
                options: [.documentType: NSAttributedString.DocumentType.html,
                          .characterEncoding: String.Encoding.utf8.rawValue],
                documentAttributes: nil)
        else {
            return html.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        }
        return attr.string
    }
}

// MARK: - 댓글 수정 시트

struct EditCommentSheet: View {
    @Binding var text: String
    let onSubmit: () -> Void
    @Environment(\.dismiss) private var dismiss
    @FocusState private var focused: Bool

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 12) {
                TextEditor(text: $text)
                    .frame(minHeight: 120)
                    .padding(8)
                    .background(Color(.secondarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .focused($focused)
                Spacer()
            }
            .padding()
            .navigationTitle("댓글 수정")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("취소") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("수정") {
                        onSubmit()
                        dismiss()
                    }
                    .disabled(
                        text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                        text.trimmingCharacters(in: .whitespacesAndNewlines).count > 300
                    )
                }
            }
            .onAppear { focused = true }
        }
    }
}

// MARK: - 게시글 수정 시트

struct EditPostSheet: View {
    @Binding var categoryId: String
    let categories: [BoardCategory]
    @Binding var title: String
    @Binding var content: String
    let onSubmit: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                if !categories.isEmpty {
                    Section("말머리") {
                        Picker("말머리", selection: $categoryId) {
                            ForEach(categories) { c in
                                Text(c.name).tag(c.id)
                            }
                        }
                        .pickerStyle(.menu)
                    }
                }
                Section("제목") {
                    TextField("제목", text: $title)
                }
                Section("내용") {
                    TextEditor(text: $content)
                        .frame(minHeight: 240)
                }
            }
            .navigationTitle("게시글 수정")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("취소") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("수정") {
                        onSubmit()
                    }
                    .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty ||
                              content.trimmingCharacters(in: .whitespaces).isEmpty ||
                              (!categories.isEmpty && categoryId.isEmpty))
                }
            }
            .onAppear {
                if categoryId.isEmpty {
                    categoryId = categories.first?.id ?? ""
                }
            }
        }
    }
}

// MARK: - 뒤로가기 버튼 숨김 + 스와이프백 유지

private struct SwipeBackEnabler: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> Enabler { Enabler() }
    func updateUIViewController(_ uiViewController: Enabler, context: Context) {}

    final class Enabler: UIViewController {
        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            navigationController?.interactivePopGestureRecognizer?.isEnabled = true
            navigationController?.interactivePopGestureRecognizer?.delegate = nil
        }
    }
}

// MARK: - HTML 본문 렌더링 (WKWebView)

struct HTMLContentView: UIViewRepresentable {
    let html: String
    @Binding var height: CGFloat

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        // 미디어 재생 설정
        config.allowsInlineMediaPlayback = true
        config.allowsPictureInPictureMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []

        // WKPreferences — Apple doc 확인: fullscreen + site quirks + JS popup
        config.preferences.isElementFullscreenEnabled = true
        config.preferences.isSiteSpecificQuirksModeEnabled = true
        config.preferences.javaScriptCanOpenWindowsAutomatically = true

        // 초기 음소거만 적용 (이후 사용자 언뮤트/볼륨 조작 허용)
        let js = """
        (function() {
            function appendParam(src, key, value) {
                if (src.indexOf(key + '=') !== -1) return src;
                return src + (src.indexOf('?') !== -1 ? '&' : '?') + key + '=' + value;
            }

            function applyInitialMute(video) {
                if (!video) return;
                video.setAttribute('playsinline', '');
                video.setAttribute('webkit-playsinline', '');
                if (!video.dataset.bpInitialMuted) {
                    video.setAttribute('muted', '');
                    video.defaultMuted = true;
                    video.muted = true;
                    video.dataset.bpInitialMuted = '1';
                }
            }

            function processMedia(doc) {
                if (!doc) return;
                doc.querySelectorAll('video').forEach(function(v) {
                    applyInitialMute(v);
                });
                doc.querySelectorAll('iframe').forEach(function(f) {
                    var src = f.src || f.getAttribute('src') || '';
                    var lower = src.toLowerCase();
                    if (lower.indexOf('youtube') !== -1 || lower.indexOf('youtu') !== -1) {
                        f.setAttribute('allow', 'autoplay; encrypted-media; picture-in-picture; fullscreen');
                        if (!f.dataset.bpMuteApplied) {
                            src = appendParam(src, 'playsinline', '1');
                            src = appendParam(src, 'mute', '1');
                            f.src = src;
                            f.dataset.bpMuteApplied = '1';
                        }
                    }
                });
            }
            processMedia(document);
        })();
        """
        let script = WKUserScript(source: js, injectionTime: .atDocumentEnd, forMainFrameOnly: false)
        let controller = WKUserContentController()
        controller.addUserScript(script)
        config.userContentController = controller

        let wv = WKWebView(frame: .zero, configuration: config)
        // YouTube가 WKWebView를 차단하지 않도록 Mobile Safari UA로 위장
        wv.customUserAgent = "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1"
        wv.navigationDelegate = context.coordinator
        wv.uiDelegate = context.coordinator
        wv.isOpaque = false
        wv.backgroundColor = .clear
        wv.scrollView.isScrollEnabled = false
        wv.scrollView.bounces = false
        return wv
    }

    func updateUIView(_ wv: WKWebView, context: Context) {
        guard context.coordinator.lastHTML != html else { return }
        context.coordinator.lastHTML = html

        let dark = UITraitCollection.current.userInterfaceStyle == .dark
        let fg   = dark ? "#f0f0f0" : "#1a1a1a"
        let bg   = dark ? "#1c1c1e" : "#ffffff"

        let styled = """
        <html><head>
        <meta charset='utf-8'>
        <meta name='viewport' content='width=device-width,initial-scale=1,shrink-to-fit=no'>
        <style>
          body { font-family: -apple-system, Helvetica, sans-serif;
                 font-size: 16px; color: \(fg); background: \(bg);
                 padding: 12px 8px; margin: 0;
                 word-break: break-word; line-height: 1.75; }
          img  { max-width: 100%; height: auto; display: block;
                 margin: 10px auto; border-radius: 6px; }
          video { max-width: 100%; border-radius: 6px; }
          a    { color: #FF9500; text-decoration: none; }
          p    { margin: 6px 0; }
          iframe {
            width: 100% !important; max-width: 100%;
            aspect-ratio: 16/9; min-height: 180px;
            border: none; border-radius: 8px;
            display: block; margin: 10px auto; }
          .kakao_ad_unit, .kakao_ad_area,
          [class*='adsbygoogle'], .powerlink, .ad_wrap,
          .icon_ad, .tool_cont { display: none !important; }
        </style></head>
        <body>\(html)</body></html>
        """
        wv.loadHTMLString(styled, baseURL: URL(string: "https://mlbpark.donga.com"))
    }

    class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate {
        let parent: HTMLContentView
        var lastHTML: String = ""
        init(_ p: HTMLContentView) { parent = p }

        private func openExternal(_ url: URL) {
            DispatchQueue.main.async {
                UIApplication.shared.open(url)
            }
        }

        func webView(_ wv: WKWebView, didFinish _: WKNavigation!) {
            wv.evaluateJavaScript("document.body.scrollHeight") { result, _ in
                if let h = result as? CGFloat {
                    DispatchQueue.main.async { self.parent.height = max(h + 20, 60) }
                }
            }
        }

        func webView(_ wv: WKWebView, decidePolicyFor action: WKNavigationAction,
                     decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            guard let url = action.request.url else {
                decisionHandler(.allow)
                return
            }

            let shouldOpenExternally =
                action.navigationType == .linkActivated || action.targetFrame == nil

            guard shouldOpenExternally else {
                decisionHandler(.allow)
                return
            }

            openExternal(url)
            decisionHandler(.cancel)
        }

        func webView(_ webView: WKWebView,
                     createWebViewWith configuration: WKWebViewConfiguration,
                     for navigationAction: WKNavigationAction,
                     windowFeatures: WKWindowFeatures) -> WKWebView? {
            if let url = navigationAction.request.url {
                openExternal(url)
            }
            return nil
        }
    }
}

// MARK: - 댓글 행

struct CommentRowView: View {
    let comment: Comment
    let postAuthorName: String
    var onEdit: (() -> Void)? = nil
    var onDelete: (() -> Void)? = nil
    var onReply: (() -> Void)? = nil
    var onEditReply: ((Comment) -> Void)? = nil
    var onDeleteReply: ((Comment) -> Void)? = nil
    var onReplyToReply: ((Comment) -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 10) {
                DetailAvatarView(url: comment.avatarUrl, author: comment.author, size: 32)

                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .top, spacing: 8) {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(spacing: 6) {
                                Text(comment.author)
                                    .font(.subheadline.weight(.semibold))

                                if isPostAuthor(comment.author) {
                                    DetailAuthorBadge()
                                }

                                Text(comment.date)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)

                                if !comment.ip.isEmpty {
                                    Text(comment.ip)
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                            }

                            Text(comment.content)
                                .font(.subheadline)
                                .foregroundStyle(.primary)
                                .fixedSize(horizontal: false, vertical: true)
                        }

                        Spacer(minLength: 8)

                        if comment.isOwn, onEdit != nil || onDelete != nil {
                            commentMenu(onEdit: onEdit, onDelete: onDelete)
                        }
                    }

                    if let onReply {
                        Button("답글", action: onReply)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(detailAccent)
                    }
                }
            }

            if !comment.replies.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(comment.replies) { reply in
                        replyCard(reply)
                    }
                }
                .padding(.leading, detailReplyIndent)
            }
        }
        .padding(16)
        .background(detailCardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(detailCardBorder, lineWidth: 1)
        )
    }

    @ViewBuilder
    private func replyCard(_ reply: Comment) -> some View {
        HStack(alignment: .top, spacing: 12) {
            if reply.depth >= 2 {
                Color.clear.frame(width: detailReplyIndent)
            }

            ReplyConnectorView()

            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top, spacing: 8) {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 6) {
                            Text(reply.author)
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(.primary)

                            if isPostAuthor(reply.author) {
                                DetailAuthorBadge()
                            }

                            Text(reply.date)
                                .font(.caption2)
                                .foregroundStyle(.secondary)

                            if !reply.ip.isEmpty {
                                Text(reply.ip)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }

                        if !reply.replyToAuthor.isEmpty {
                            Text("@\(reply.replyToAuthor)에게 답글")
                                .font(.caption)
                                .foregroundStyle(detailAccent)
                        }

                        Text(reply.content)
                            .font(.subheadline)
                            .foregroundStyle(.primary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    if reply.isOwn {
                        Spacer(minLength: 8)
                        commentMenu(
                            onEdit: onEditReply.map { handler in { handler(reply) } },
                            onDelete: onDeleteReply.map { handler in { handler(reply) } }
                        )
                    }
                }

                if let onReplyToReply {
                    Button("답글") { onReplyToReply(reply) }
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(detailAccent)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(detailReplyBackground)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(detailReplyBorder, lineWidth: 1)
            )
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func commentMenu(onEdit: (() -> Void)?, onDelete: (() -> Void)?) -> some View {
        Menu {
            if let onEdit {
                Button("수정") { onEdit() }
            }
            if let onDelete {
                Button("삭제", role: .destructive) { onDelete() }
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(width: 24, height: 24)
        }
    }

    private func isPostAuthor(_ author: String) -> Bool {
        author.trimmingCharacters(in: .whitespacesAndNewlines)
            == postAuthorName.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

private struct DetailAvatarView: View {
    let url: String
    let author: String
    let size: CGFloat

    var body: some View {
        AsyncImage(url: URL(string: url)) { phase in
            switch phase {
            case .success(let image):
                image.resizable().scaledToFill()
            default:
                ZStack {
                    Circle().fill(avatarColor(author))
                    Text(String(author.prefix(1)))
                        .font(.system(size: max(size * 0.38, 12), weight: .semibold))
                        .foregroundColor(.white)
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
    }
}

private struct DetailAuthorBadge: View {
    var body: some View {
        Text("작성자")
            .font(.caption2.weight(.bold))
            .foregroundStyle(detailAccent)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(detailChipBackground)
            .clipShape(Capsule())
    }
}

private struct DetailReactionBar: View {
    let recommendCount: Int
    let commentCount: Int
    let isRecommended: Bool
    let isTogglingRecommend: Bool
    let shareURL: URL?
    let onRecommend: () -> Void
    let onComment: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            Button(action: onRecommend) {
                item(
                    systemName: "heart.fill",
                    title: "좋아요",
                    value: recommendCount,
                    tint: isRecommended ? .pink : .secondary
                )
            }
            .buttonStyle(.plain)
            .disabled(isTogglingRecommend)

            Divider()

            Button(action: onComment) {
                item(
                    systemName: "bubble.left.fill",
                    title: "댓글",
                    value: commentCount,
                    tint: detailAccent
                )
            }
            .buttonStyle(.plain)

            Divider()

            if let shareURL {
                ShareLink(item: shareURL) {
                    item(systemName: "square.and.arrow.up", title: "공유", tint: .secondary)
                }
                .buttonStyle(.plain)
            } else {
                item(systemName: "square.and.arrow.up", title: "공유", tint: .secondary)
            }
        }
        .frame(height: 44)
        .background(detailCardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(detailCardBorder, lineWidth: 1)
        )
    }

    private func item(systemName: String, title: String, value: Int, tint: Color) -> some View {
        HStack(spacing: 6) {
            Image(systemName: systemName)
            Text("\(title) \(value)")
        }
        .font(.footnote.weight(.medium))
        .foregroundStyle(tint)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
    }

    private func item(systemName: String, title: String, tint: Color) -> some View {
        HStack(spacing: 6) {
            Image(systemName: systemName)
            Text(title)
        }
        .font(.footnote.weight(.medium))
        .foregroundStyle(tint)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
    }
}

private struct ReplyConnectorView: View {
    var body: some View {
        Path { path in
            path.move(to: CGPoint(x: 8, y: 0))
            path.addLine(to: CGPoint(x: 8, y: 18))
            path.addLine(to: CGPoint(x: 16, y: 18))
        }
        .stroke(detailThreadColor, style: StrokeStyle(lineWidth: 1.6, lineCap: .square, lineJoin: .miter))
        .frame(width: 16, height: 22)
        .padding(.top, 4)
    }
}

// MARK: - Burning 위젯

@MainActor
class BurningWidgetViewModel: ObservableObject {
    @Published var data: BurningData?
    @Published var isLoading = false

    func load() async {
        guard data == nil, !isLoading else { return }
        isLoading = true
        data = try? await MLBParkService.shared.fetchBurningWidget()
        isLoading = false
    }
}

struct BurningWidgetView: View {
    let boardId: String
    @StateObject private var vm = BurningWidgetViewModel()

    private func boardPosts(from data: BurningData) -> BurningData.BoardPosts {
        switch boardId {
        case "kbotown": return data.kbo
        case "bullpen":  return data.bullpen
        default:         return data.mlb
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // 헤더
            HStack {
                Image(systemName: "flame.fill").foregroundColor(.orange)
                Text("BURNING")
                    .font(.headline).fontWeight(.bold).foregroundColor(.orange)
                Spacer()
            }
            .padding(.horizontal).padding(.top, 16).padding(.bottom, 8)

            if vm.isLoading {
                HStack { Spacer(); ProgressView(); Spacer() }.padding()
            } else if let data = vm.data {
                BurningBoardSection(bp: boardPosts(from: data))
            }
        }
        .task { await vm.load() }
    }
}

struct BurningBoardSection: View {
    let bp: BurningData.BoardPosts
    @State private var period = 0 // 0=실시간 1=주간 2=월간
    @State private var selectedPost: BurningPost?

    private var posts: [BurningPost] {
        switch period {
        case 1:  return bp.weekly
        case 2:  return bp.monthly
        default: return bp.realtime
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // 기간 탭
            HStack(alignment: .bottom, spacing: 4) {
                ForEach(["실시간", "주간", "월간"].indices, id: \.self) { i in
                    Button { period = i } label: {
                        Text(["실시간", "주간", "월간"][i])
                            .font(.subheadline)
                            .fontWeight(period == i ? .semibold : .regular)
                            .foregroundColor(period == i ? .orange : .secondary)
                            .padding(.horizontal, 18)
                            .padding(.vertical, 8)
                            // 선택탭: 위+좌+우 3면 주황 테두리, 하단 없음 (콘텐츠와 이어짐)
                            // 비선택탭: 테두리 없음
                            .background(Color(.systemBackground))
                            .clipShape(UnevenRoundedRectangle(topLeadingRadius: 6, bottomLeadingRadius: 0, bottomTrailingRadius: 0, topTrailingRadius: 6))
                            .overlay(
                                ThreeSidedBorder(radius: 6)
                                    .stroke(period == i ? Color.orange : Color(.systemGray4), lineWidth: 1.5)
                            )
                            // 선택탭이 콘텐츠 테두리를 덮도록 1pt 아래로 연장
                            .padding(.bottom, period == i ? 1.5 : 0)
                            .zIndex(period == i ? 1 : 0)
                    }
                    .buttonStyle(.plain)
                }
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.top, 10)

            // 콘텐츠 영역 (주황 상단 테두리로 탭과 연결)
            VStack(spacing: 0) {
                ForEach(Array(posts.enumerated()), id: \.element.id) { idx, post in
                    Button {
                        selectedPost = post
                    } label: {
                        HStack(spacing: 8) {
                            Text("\(idx + 1)")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundColor(idx < 3 ? .orange : .primary)
                                .frame(width: 20, alignment: .center)
                            Text(post.title)
                                .font(.subheadline)
                                .foregroundColor(.primary)
                                .lineLimit(1)
                            Spacer()
                            if post.replyCount > 0 {
                                Text("[\(post.replyCount)]")
                                    .font(.caption).fontWeight(.semibold)
                                    .foregroundColor(.orange)
                            }
                        }
                        .padding(.horizontal).padding(.vertical, 8)
                    }
                    .buttonStyle(.plain)
                    if idx < posts.count - 1 {
                        Divider().padding(.leading, 36)
                    }
                }
            }
            .background(Color(.systemBackground))
        }
        .navigationDestination(item: $selectedPost) { post in
            PostDetailView(boardId: post.boardId, postId: post.id)
        }
    }
}

// 상단 3면(위+좌+우)만 그리는 테두리 Shape
private struct ThreeSidedBorder: Shape {
    let radius: CGFloat

    func path(in rect: CGRect) -> Path {
        var p = Path()
        let r = min(radius, rect.height / 2, rect.width / 2)
        p.move(to: CGPoint(x: rect.minX, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.minX, y: rect.minY + r))
        p.addArc(center: CGPoint(x: rect.minX + r, y: rect.minY + r),
                 radius: r, startAngle: .degrees(180), endAngle: .degrees(270), clockwise: false)
        p.addLine(to: CGPoint(x: rect.maxX - r, y: rect.minY))
        p.addArc(center: CGPoint(x: rect.maxX - r, y: rect.minY + r),
                 radius: r, startAngle: .degrees(270), endAngle: .degrees(0), clockwise: false)
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        return p
    }
}

// MARK: - New Comment Banner

struct NewCommentBanner: View {
    let count: Int
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 6) {
                Image(systemName: "arrow.down")
                    .font(.caption.weight(.bold))
                Text("새 댓글 \(count)개")
                    .font(.caption.weight(.semibold))
            }
            .foregroundColor(.white)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(detailAccent.opacity(0.92))
            .clipShape(Capsule())
            .shadow(color: .black.opacity(0.18), radius: 4, y: 2)
        }
        .buttonStyle(.plain)
    }
}

private func avatarColor(_ name: String) -> Color {
    let palette: [Color] = [.orange, .green, .orange, .purple, .pink, .teal, .indigo, .red]
    let hash = name.unicodeScalars.reduce(0) { $0 + Int($1.value) }
    return palette[abs(hash) % palette.count]
}

