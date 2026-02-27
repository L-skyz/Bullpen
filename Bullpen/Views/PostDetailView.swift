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
                                    .font(.caption)
                                    .fontWeight(.semibold)
                                    .padding(.horizontal, 7).padding(.vertical, 3)
                                    .background(Color.blue.opacity(0.12))
                                    .foregroundColor(.blue)
                                    .clipShape(RoundedRectangle(cornerRadius: 5))
                            }
                            Text(d.title)
                                .font(.title3).fontWeight(.bold)

                            HStack(spacing: 4) {
                                Image(systemName: "person.circle")
                                    .font(.caption).foregroundColor(.secondary)
                                Text(d.author).font(.subheadline).foregroundColor(.secondary)
                                Spacer()
                                Text(d.date).font(.caption).foregroundColor(.secondary)
                            }
                            Divider()
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

                        // ── 본문 ──
                        HTMLContentView(html: d.contentHTML, height: $contentHeight)
                            .frame(height: contentHeight)
                            .padding(.horizontal, 4)

                        Divider().padding(.top, 8)

                        // ── 댓글 목록 ──
                        if !d.comments.isEmpty {
                            VStack(alignment: .leading, spacing: 0) {
                                Text("댓글 \(d.commentCount)개")
                                    .font(.headline).padding()
                                ForEach(d.comments) { c in
                                    CommentRowView(comment: c)
                                    Divider().padding(.leading)
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
                            .background(Color(.systemBackground))
                        }
                    }
                }
            } else if let err = vm.error {
                ContentUnavailableView(err, systemImage: "exclamationmark.triangle")
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .task { await vm.load(boardId: boardId, postId: postId) }
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
        let dark = UITraitCollection.current.userInterfaceStyle == .dark
        let fg = dark ? "#f0f0f0" : "#1a1a1a"
        let styled = """
        <html><head>
        <meta name='viewport' content='width=device-width,initial-scale=1,shrink-to-fit=no'>
        <style>
          body{font-family:-apple-system,Helvetica;font-size:16px;color:\(fg);
               background:transparent;padding:8px;margin:0;word-break:break-word;line-height:1.7}
          img{max-width:100%;height:auto;border-radius:8px;display:block;margin:10px auto}
          a{color:#007AFF;text-decoration:none}
          p{margin:6px 0}
        </style></head><body>\(html)</body></html>
        """
        wv.loadHTMLString(styled, baseURL: URL(string: "https://mlbpark.donga.com"))
    }

    class Coordinator: NSObject, WKNavigationDelegate {
        let parent: HTMLContentView
        init(_ p: HTMLContentView) { parent = p }

        func webView(_ wv: WKWebView, didFinish _: WKNavigation!) {
            wv.evaluateJavaScript("document.body.scrollHeight") { result, _ in
                if let h = result as? CGFloat {
                    DispatchQueue.main.async { self.parent.height = h + 16 }
                }
            }
        }
    }
}

// MARK: - 댓글 행

struct CommentRowView: View {
    let comment: Comment

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text(comment.author).font(.subheadline).fontWeight(.semibold)
                if !comment.ip.isEmpty {
                    Text(comment.ip).font(.caption2).foregroundColor(.secondary)
                }
                Spacer()
                Text(comment.date).font(.caption2).foregroundColor(.secondary)
            }
            Text(comment.content).font(.subheadline)

            // 대댓글
            if !comment.replies.isEmpty {
                ForEach(comment.replies) { reply in
                    HStack(alignment: .top, spacing: 6) {
                        Image(systemName: "arrow.turn.down.right")
                            .font(.caption2).foregroundColor(.secondary).padding(.top, 2)
                        VStack(alignment: .leading, spacing: 2) {
                            HStack {
                                Text(reply.author).font(.caption).fontWeight(.semibold)
                                Spacer()
                                Text(reply.date).font(.caption2).foregroundColor(.secondary)
                            }
                            Text(reply.content).font(.caption)
                        }
                    }
                    .padding(.top, 4)
                }
            }
        }
        .padding(.horizontal).padding(.vertical, 10)
    }
}
