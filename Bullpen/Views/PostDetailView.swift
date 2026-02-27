import SwiftUI
import WebKit

@MainActor
class PostDetailViewModel: ObservableObject {
    @Published var detail: PostDetail?
    @Published var isLoading = false
    @Published var error: String?
    @Published var commentInput = ""
    @Published var isSubmittingComment = false

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
        guard !commentInput.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        isSubmittingComment = true
        do {
            try await MLBParkService.shared.writeComment(boardId: boardId, postId: postId, content: commentInput)
            commentInput = ""
            await load(boardId: boardId, postId: postId)
        } catch {}
        isSubmittingComment = false
    }
}

struct PostDetailView: View {
    let boardId: String
    let postId: String
    @StateObject private var vm = PostDetailViewModel()
    @EnvironmentObject var auth: AuthService
    @State private var contentHeight: CGFloat = 200
    @FocusState private var commentFocused: Bool

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
                                ZStack {
                                    Circle()
                                        .fill(avatarColor(d.author))
                                        .frame(width: 36, height: 36)
                                    Text(String(d.author.prefix(1)))
                                        .font(.system(size: 14, weight: .semibold))
                                        .foregroundColor(.white)
                                }
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(d.author)
                                        .font(.subheadline).fontWeight(.semibold)
                                    Text(d.date)
                                        .font(.caption).foregroundColor(.secondary)
                                }
                                Spacer()
                            }

                            HStack(spacing: 16) {
                                Label("\(d.recommendCount)", systemImage: "hand.thumbsup")
                                Label("\(d.views)",           systemImage: "eye")
                                Label("\(d.commentCount)",    systemImage: "bubble.left")
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
                        if !d.comments.isEmpty {
                            VStack(alignment: .leading, spacing: 0) {
                                HStack {
                                    Image(systemName: "bubble.left.and.bubble.right")
                                        .foregroundColor(.secondary)
                                    Text("댓글 \(d.commentCount)개")
                                        .font(.headline)
                                }
                                .padding(.horizontal).padding(.top, 12).padding(.bottom, 4)

                                ForEach(d.comments) { c in
                                    CommentRowView(comment: c)
                                    Divider().padding(.leading, 58)
                                }
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
                                .disabled(vm.commentInput.isEmpty || vm.isSubmittingComment)
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
        .task { await vm.load(boardId: boardId, postId: postId) }
    }

    private func avatarColor(_ name: String) -> Color {
        let palette: [Color] = [.blue, .green, .orange, .purple, .pink, .teal, .indigo, .red]
        let hash = name.unicodeScalars.reduce(0) { $0 + Int($1.value) }
        return palette[abs(hash) % palette.count]
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
        // 같은 HTML이면 재로딩 안함 → 영상 깜박거림 방지
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

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 10) {
                ZStack {
                    Circle().fill(avatarColor(comment.author)).frame(width: 36, height: 36)
                    Text(String(comment.author.prefix(1)))
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.white)
                }
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(comment.author).font(.subheadline).fontWeight(.semibold)
                        if !comment.ip.isEmpty {
                            Text(comment.ip).font(.caption2).foregroundColor(.secondary)
                        }
                        Spacer()
                        Text(comment.date).font(.caption2).foregroundColor(.secondary)
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

    private func avatarColor(_ name: String) -> Color {
        let palette: [Color] = [.blue, .green, .orange, .purple, .pink, .teal, .indigo, .red]
        let hash = name.unicodeScalars.reduce(0) { $0 + Int($1.value) }
        return palette[abs(hash) % palette.count]
    }
}
