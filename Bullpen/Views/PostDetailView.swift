import SwiftUI
import WebKit
import UIKit

private let postDetailHeaderBackground = Color.orange.opacity(0.08)
private let postAuthorHighlightBackground = Color.orange.opacity(0.16)

@MainActor
class PostDetailViewModel: ObservableObject {
    @Published var detail: PostDetail?
    @Published var isLoading = false
    @Published var error: String?
    @Published var commentInput = ""
    @Published var isSubmittingComment = false
    @Published var actionError: String?
    @Published var replyingTo: Comment? = nil
    private var loadGeneration = 0

    func load(boardId: String, postId: String) async {
        loadGeneration += 1
        let generation = loadGeneration

        await Task.detached(priority: .userInitiated) { [weak self] in
            guard let self else { return }
            await self.runLoad(boardId: boardId, postId: postId, generation: generation)
        }.value
    }

    private func runLoad(boardId: String, postId: String, generation: Int) async {
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
            let parentSeq  = replyingTo?.seq ?? ""
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
            if let d = vm.detail {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {

                        // ── 헤더 ──
                        VStack(alignment: .leading, spacing: 8) {
                            if !d.maemuri.isEmpty {
                                Text(d.maemuri)
                                    .font(.caption).fontWeight(.semibold)
                                    .padding(.horizontal, 7).padding(.vertical, 3)
                                    .background(Color.orange.opacity(0.12))
                                    .foregroundColor(.orange)
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
                                            vm.actionError = nil
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
                        .background(postDetailHeaderBackground)

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
                                CommentRowView(
                                    comment: c,
                                    isPostAuthor: c.author.trimmingCharacters(in: .whitespacesAndNewlines)
                                        == d.author.trimmingCharacters(in: .whitespacesAndNewlines),
                                    onEdit: {
                                        editCommentText = c.content
                                        editingComment  = c
                                    },
                                    onDelete: {
                                        deletingComment = c
                                    },
                                    onReply: auth.isLoggedIn ? {
                                        vm.replyingTo = c
                                        commentFocused = true
                                    } : nil
                                )
                                Divider().padding(.leading, 64)
                            }
                        }

                        // ── 댓글 입력 ──
                        if auth.isLoggedIn {
                            VStack(spacing: 0) {
                                if let replyTo = vm.replyingTo {
                                    HStack(spacing: 6) {
                                        Image(systemName: "arrow.turn.down.left")
                                            .font(.caption).foregroundColor(.orange)
                                        Text("@\(replyTo.author)에게 답글")
                                            .font(.caption).foregroundColor(.secondary)
                                        Spacer()
                                        Button {
                                            vm.replyingTo = nil
                                        } label: {
                                            Image(systemName: "xmark.circle.fill")
                                                .foregroundColor(.secondary)
                                        }
                                    }
                                    .padding(.horizontal).padding(.vertical, 6)
                                    .background(Color(.secondarySystemBackground))
                                }
                                VStack(alignment: .trailing, spacing: 8) {
                                    TextField(
                                        vm.replyingTo == nil ? "댓글을 입력하세요" : "답글을 입력하세요",
                                        text: $vm.commentInput,
                                        axis: .vertical
                                    )
                                    .lineLimit(5...10)
                                    .frame(minHeight: 110, alignment: .top)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 12)
                                    .background(Color.white)
                                    .clipShape(RoundedRectangle(cornerRadius: 12))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 12)
                                            .stroke(Color(.systemGray4), lineWidth: 1.5)
                                    )
                                    .focused($commentFocused)
                                    Button {
                                        Task { await vm.submitComment(boardId: boardId, postId: postId) }
                                    } label: {
                                        if vm.isSubmittingComment {
                                            ProgressView()
                                                .frame(width: 72, height: 36)
                                                .background(Color.purple.opacity(0.15))
                                                .clipShape(RoundedRectangle(cornerRadius: 8))
                                        } else {
                                            Text("등록")
                                                .font(.subheadline).fontWeight(.semibold)
                                                .foregroundColor(.purple)
                                                .frame(width: 72, height: 36)
                                                .background(Color.purple.opacity(0.15))
                                                .clipShape(RoundedRectangle(cornerRadius: 8))
                                        }
                                    }
                                    .disabled(
                                        vm.commentInput.trimmingCharacters(in: .whitespacesAndNewlines).count > 300 ||
                                        vm.isSubmittingComment
                                    )
                                }
                                .padding()
                            }
                        }

                        // ── Burning 위젯 (실시간/주간/월간) ──
                        BurningWidgetView(boardId: boardId)

                        Spacer(minLength: 40)
                    }
                }
                .refreshable {
                    await vm.load(boardId: boardId, postId: postId)
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
        .task {
            await vm.load(boardId: boardId, postId: postId)
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
            guard action.navigationType == .linkActivated,
                  let url = action.request.url else {
                decisionHandler(.allow)
                return
            }

            UIApplication.shared.open(url)
            decisionHandler(.cancel)
        }
    }
}

// MARK: - 댓글 행

struct CommentRowView: View {
    let comment: Comment
    var isPostAuthor: Bool = false
    var onEdit: (() -> Void)? = nil
    var onDelete: (() -> Void)? = nil
    var onReply: (() -> Void)? = nil

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
                        // 답글 버튼
                        if let onReply {
                            Button(action: onReply) {
                                Image(systemName: "arrow.turn.down.left")
                                    .font(.caption)
                                    .foregroundColor(.orange.opacity(0.8))
                                    .padding(4)
                            }
                        }
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
            .padding(.horizontal).padding(.vertical, 14)
            .background(isPostAuthor ? postAuthorHighlightBackground : Color.clear)

            ForEach(comment.replies) { reply in
                HStack(alignment: .top, spacing: 10) {
                    // depth=2(replied_re)이면 추가 들여쓰기
                    if reply.depth >= 2 {
                        Color.clear.frame(width: 20)
                    }
                    Image(systemName: "arrow.turn.down.right")
                        .font(.caption).foregroundColor(.purple.opacity(0.6))
                        .frame(width: 36).padding(.top, 2)
                    VStack(alignment: .leading, spacing: 3) {
                        HStack {
                            Text(reply.author).font(.footnote).fontWeight(.semibold).foregroundColor(.primary)
                            Spacer()
                            Text(reply.date).font(.caption2).foregroundColor(.secondary)
                        }
                        if !reply.replyToAuthor.isEmpty {
                            Text("@\(reply.replyToAuthor)에게 답글")
                                .font(.footnote).foregroundColor(.primary)
                                .padding(.bottom, 4)
                        }
                        Text(reply.content).font(.caption)
                    }
                }
                .padding(.horizontal).padding(.vertical, 8)
                .background(isPostAuthor ? Color.orange.opacity(0.12) : Color.purple.opacity(0.07))
            }
        }
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
            .overlay(alignment: .top) {
                Rectangle().fill(Color.orange).frame(height: 1.5)
            }
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

private func avatarColor(_ name: String) -> Color {
    let palette: [Color] = [.orange, .green, .orange, .purple, .pink, .teal, .indigo, .red]
    let hash = name.unicodeScalars.reduce(0) { $0 + Int($1.value) }
    return palette[abs(hash) % palette.count]
}

