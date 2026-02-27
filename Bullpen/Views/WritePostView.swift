import SwiftUI

struct WritePostView: View {
    @EnvironmentObject var auth: AuthService
    @State private var selectedBoard = Board.all[0]
    @State private var maemuri = ""
    @State private var title = ""
    @State private var content = ""
    @State private var isSubmitting = false
    @State private var showSuccess = false
    @State private var errorMessage: String?

    // 말머리 목록 (게시판별로 다를 수 있음)
    let maemuriOptions = ["없음", "잡담", "정보", "분석", "질문", "사진", "동영상", "뉴스"]

    var body: some View {
        NavigationStack {
            if !auth.isLoggedIn {
                ContentUnavailableView {
                    Label("로그인 필요", systemImage: "lock.circle")
                } description: {
                    Text("글을 쓰려면 로그인이 필요합니다.")
                }
            } else {
                Form {
                    Section("게시판") {
                        Picker("게시판", selection: $selectedBoard) {
                            ForEach(Board.all) { board in
                                Text(board.name).tag(board)
                            }
                        }
                    }

                    Section("말머리") {
                        Picker("말머리", selection: $maemuri) {
                            ForEach(maemuriOptions, id: \.self) { opt in
                                Text(opt).tag(opt == "없음" ? "" : opt)
                            }
                        }
                        .pickerStyle(.menu)
                    }

                    Section("제목") {
                        TextField("제목을 입력하세요", text: $title)
                    }

                    Section("내용") {
                        TextEditor(text: $content)
                            .frame(minHeight: 240)
                    }

                    if let err = errorMessage {
                        Section {
                            Text(err).foregroundColor(.red).font(.caption)
                        }
                    }
                }
                .navigationTitle("글쓰기")
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("등록") { Task { await submit() } }
                            .disabled(title.isEmpty || content.isEmpty || isSubmitting)
                    }
                }
                .alert("등록 완료", isPresented: $showSuccess) {
                    Button("확인") { title = ""; content = ""; maemuri = "" }
                } message: {
                    Text("게시글이 등록되었습니다.")
                }
            }
        }
    }

    private func submit() async {
        isSubmitting = true; errorMessage = nil
        do {
            try await MLBParkService.shared.writePost(
                boardId: selectedBoard.id,
                maemuri: maemuri,
                title: title,
                content: content
            )
            showSuccess = true
        } catch {
            errorMessage = error.localizedDescription
        }
        isSubmitting = false
    }
}
