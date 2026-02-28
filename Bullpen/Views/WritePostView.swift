import SwiftUI

struct WritePostView: View {
    @EnvironmentObject var auth: AuthService

    // 글쓰기 가능한 게시판만
    private let writableBoards = Board.all.filter { $0.isWritable }

    @State private var selectedBoard: Board
    @State private var categoryId: String
    @State private var title = ""
    @State private var content = ""
    @State private var isSubmitting = false
    @State private var showSuccess = false
    @State private var errorMessage: String?

    init() {
        let first = Board.all.first(where: { $0.isWritable }) ?? Board.all[0]
        _selectedBoard = State(initialValue: first)
        _categoryId = State(initialValue: first.writeCategories.first?.id ?? "")
    }

    var body: some View {
        Group {
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
                            ForEach(writableBoards) { board in
                                Text(board.name).tag(board)
                            }
                        }
                    }

                    Section("말머리 (필수)") {
                        Picker("말머리", selection: $categoryId) {
                            ForEach(selectedBoard.writeCategories) { cat in
                                Text(cat.name).tag(cat.id)
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
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        if isSubmitting {
                            ProgressView()
                        } else {
                            Button("등록") { Task { await submit() } }
                                .disabled(title.isEmpty || content.isEmpty || categoryId.isEmpty)
                        }
                    }
                }
                .alert("등록 완료", isPresented: $showSuccess) {
                    Button("확인") { title = ""; content = "" }
                } message: {
                    Text("게시글이 등록되었습니다.")
                }
            }
        }
        .onChange(of: selectedBoard) { _, newBoard in
            // 게시판 변경 시 해당 게시판 첫 번째 말머리 자동 선택
            categoryId = newBoard.writeCategories.first?.id ?? ""
        }
        .navigationTitle("글쓰기")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func submit() async {
        isSubmitting = true
        errorMessage = nil
        do {
            try await MLBParkService.shared.writePost(
                boardId: selectedBoard.id,
                categoryId: categoryId,
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
