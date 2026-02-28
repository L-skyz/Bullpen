import SwiftUI
import WebKit

@MainActor
class PostDetailViewModel: ObservableObject {
    @Published var detail: PostDetail?
    @Published var isLoading = false
    @Published var error: String?
    @Published var commentInput = ""
    @Published var isSubmittingComment = false
    @Published var actionError: String?

    func load(boardId: String, postId: String) async {
        isLoading = true; error = nil
        do {
            detail = try await MLBParkService.shared.fetchPostDetail(boardId: boardId, postId: postId)
        } catch {
            self.error = error.localizedDescription
        }
        isLoading = false
    }

    func submitComment(boardId: String, postId: String) async {
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
            try await MLBParkService.shared.writeComment(boardId: boardId, postId: postId, content: trimmed)
            commentInput = ""
            await load(boardId: boardId, postId: postId)
        } catch {
            actionError = error.localizedDescription
        }
        isSubmittingComment = false
    }

    func deletePost(boardId: String, postId: String) async -> Bool {
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
        do {
            try await MLBParkService.shared.deleteComment(boardId: boardId, postId: postId,
                                                          commentSeq: comment.seq)
            await load(boardId: boardId, postId: postId)
        } catch {
            actionError = error.localizedDescription
        }
    }

    func editComment(boardId: String, postId: String, comment: Comment, newContent: String) async {
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
}

struct PostDetailView: View {
    let boardId: String
    let postId: String
    @StateObject private var vm = PostDetailViewModel()
    @EnvironmentObject var auth: AuthService
    @Environment(\.dismiss) private var dismiss
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
        return auth.isLoggedIn && !auth.nickname.isEmpty && d.author == auth.nickname
    }

    private var currentBoard: Board? {
        Board.all.first(where: { $0.id == boardId })
    }

    private var editCategories: [BoardCategory] {
        currentBoard?.writeCategories ?? []
    }

    var body: some View {
        Group {
            if vm.isLoading {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let d = vm.detail {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {

                        // ── 헤더 ──
                        VStack(alignment: .leading, spacing: 8) {
                            if !d.maemuri.isEmpty {
                                Text(d.maemuri)
                                    .font(.caption).fontWeight(.semibold)
                                    .padding(.horizontal, 7).padding(.vertical, 3)
                                    .background(Color.blue.opacity(0.12))
                                    .foregroundColor(.blue)
                                    .clipShape(RoundedRectangle(cornerRadius: 5))
                            }
                            Text(d.title)
                                .font(.title3).fontWeight(.bold)

                            HStack(spacing: 10) {
                                AsyncImage(url: URL(string: d.avatarUrl)) { phase in
                                    switch phase {
                                    case .success(let img):
                                        img.resizable().scaledToFill()
                                    default:
                                        ZStack {
                                            Circle().fill(avatarColor(d.author))
                                            Text(String(d.author.prefix(1)))
                                                .font(.system(size: 14, weight: .semibold))
                                                .foregroundColor(.white)
                                        }
                                    }
                                }
                                .frame(width: 36, height: 36)
                                .clipShape(Circle())
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(d.author)
                                        .font(.subheadline).fontWeight(.semibold)
                                    Text(d.date)
                                        .font(.caption).foregroundColor(.secondary)
                                }
                                Spacer()
                                // 내 게시글: 수정/삭제 메뉴
                                if isMyPost {
                                    Menu {
                                        Button("수정") {
                                            editTitle      = d.title
                                            editContent    = stripHTML(d.contentHTML)
                                            editCategoryId = resolveCategoryId(from: d.maemuri)
                                            showEditPost   = true
                                        }
                                        Button("삭제", role: .destructive) {
                                            showDeletePostAlert = true
                                        }
                                    } label: {
                                        Image(systemName: "ellipsis.circle")
                                            .font(.title3)
                                            .foregroundColor(.secondary)
                                    }
                                }
                            }

                            HStack(spacing: 16) {
                                Label("\(d.recommendCount)", systemImage: "hand.thumbsup")
                                Label("\(d.views)",          systemImage: "eye")
                                Label("\(d.comments.count)", systemImage: "bubble.left")
                            }
                            .font(.caption).foregroundColor(.secondary)
                        }
                        .padding()
                        .background(Color(.secondarySystemBackground))

                        Divider()

                        // ── 본문 (WKWebView, div.ar_txt만) ──
                        HTMLContentView(html: d.contentHTML, height: $contentHeight)
                            .frame(height: contentHeight)

                        Divider().padding(.top, 4)

                        // ── 댓글 목록 ──
                        VStack(alignment: .leading, spacing: 0) {
                            HStack {
                                Image(systemName: "bubble.left.and.bubble.right")
                                    .foregroundColor(.secondary)
                                Text("댓글 \(d.comments.count)개")
                                    .font(.headline)
                            }
                            .padding(.horizontal).padding(.top, 12).padding(.bottom, 4)

                            ForEach(d.comments) { c in
                                CommentRowView(comment: c) {
                                    // 수정
                                    editCommentText  = c.content
                                    editingComment   = c
                                } onDelete: {
                                    // 삭제 확인
                                    deletingComment = c
                                }
                                Divider().padding(.leading, 58)
                            }
                        }

                        // ── 댓글 입력 ──
                        if auth.isLoggedIn {
                            HStack(spacing: 8) {
                                TextField("댓글을 입력하세요", text: $vm.commentInput)
                                    .textFieldStyle(.roundedBorder)
                                    .focused($commentFocused)
                                Button {
                                    Task { await vm.submitComment(boardId: boardId, postId: postId) }
                                } label: {
                                    if vm.isSubmittingComment {
                                        ProgressView().frame(width: 44, height: 36)
                                    } else {
                                        Image(systemName: "paperplane.fill")
                                            .frame(width: 44, height: 36)
                                    }
                                }
                                .disabled(
                                    vm.commentInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                                    vm.commentInput.trimmingCharacters(in: .whitespacesAndNewlines).count > 300 ||
                                    vm.isSubmittingComment
                                )
                            }
                            .padding()
                        }

                        Spacer(minLength: 40)
                    }
                }
            } else if let err = vm.error {
                ContentUnavailableView(err, systemImage: "exclamationmark.triangle")
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .background(SwipeBackEnabler())
        .task { await vm.load(boardId: boardId, postId: postId) }
        // 게시글 삭제 확인
        .alert("게시글을 삭제하시겠습니까?", isPresented: $showDeletePostAlert) {
            Button("삭제", role: .destructive) {
                Task {
                    let ok = await vm.deletePost(boardId: boardId, postId: postId)
                    if ok { dismiss() }
                }
            }
            Button("취소", role: .cancel) {}
        }
        // 댓글 삭제 확인
        .alert("댓글을 삭제하시겠습니까?", isPresented: Binding(
            get: { deletingComment != nil },
            set: { if !$0 { deletingComment = nil } }
        )) {
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
        let wv = WKWebView()
        wv.navigationDelegate = context.coordinator
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
          a    { color: #007AFF; text-decoration: none; }
          p    { margin: 6px 0; }
          iframe, .kakao_ad_unit, .kakao_ad_area,
          [class*='adsbygoogle'], .powerlink, .ad_wrap,
          .icon_ad, .tool_cont { display: none !important; }
        </style></head>
        <body>\(html)</body></html>
        """
        wv.loadHTMLString(styled, baseURL: URL(string: "https://mlbpark.donga.com"))
    }

    class Coordinator: NSObject, WKNavigationDelegate {
        let parent: HTMLContentView
        var lastHTML: String = ""
        init(_ p: HTMLContentView) { parent = p }

        func webView(_ wv: WKWebView, didFinish _: WKNavigation!) {
            wv.evaluateJavaScript("document.body.scrollHeight") { result, _ in
                if let h = result as? CGFloat {
                    DispatchQueue.main.async { self.parent.height = max(h + 20, 60) }
                }
            }
        }

        func webView(_ wv: WKWebView, decidePolicyFor action: WKNavigationAction,
                     decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            decisionHandler(action.navigationType == .linkActivated ? .cancel : .allow)
        }
    }
}

// MARK: - 댓글 행

struct CommentRowView: View {
    let comment: Comment
    var onEdit: (() -> Void)? = nil
    var onDelete: (() -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 10) {
                AsyncImage(url: URL(string: comment.avatarUrl)) { phase in
                    switch phase {
                    case .success(let img):
                        img.resizable().scaledToFill()
                    default:
                        ZStack {
                            Circle().fill(avatarColor(comment.author))
                            Text(String(comment.author.prefix(1)))
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(.white)
                        }
                    }
                }
                .frame(width: 36, height: 36)
                .clipShape(Circle())
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(comment.author).font(.subheadline).fontWeight(.semibold)
                        if !comment.ip.isEmpty {
                            Text(comment.ip).font(.caption2).foregroundColor(.secondary)
                        }
                        Spacer()
                        Text(comment.date).font(.caption2).foregroundColor(.secondary)
                        // 내 댓글 수정/삭제 메뉴
                        if comment.isOwn, onEdit != nil || onDelete != nil {
                            Menu {
                                if let onEdit {
                                    Button("수정") { onEdit() }
                                }
                                if let onDelete {
                                    Button("삭제", role: .destructive) { onDelete() }
                                }
                            } label: {
                                Image(systemName: "ellipsis")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .padding(4)
                            }
                        }
                    }
                    Text(comment.content)
                        .font(.subheadline)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.horizontal).padding(.vertical, 10)

            ForEach(comment.replies) { reply in
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "arrow.turn.down.right")
                        .font(.caption).foregroundColor(.secondary)
                        .frame(width: 36).padding(.top, 2)
                    VStack(alignment: .leading, spacing: 3) {
                        HStack {
                            Text(reply.author).font(.caption).fontWeight(.semibold)
                            Spacer()
                            Text(reply.date).font(.caption2).foregroundColor(.secondary)
                        }
                        Text(reply.content).font(.caption)
                    }
                }
                .padding(.horizontal).padding(.vertical, 6)
                .background(Color(.secondarySystemBackground))
            }
        }
    }

}

private func avatarColor(_ name: String) -> Color {
    let palette: [Color] = [.blue, .green, .orange, .purple, .pink, .teal, .indigo, .red]
    let hash = name.unicodeScalars.reduce(0) { $0 + Int($1.value) }
    return palette[abs(hash) % palette.count]
}
