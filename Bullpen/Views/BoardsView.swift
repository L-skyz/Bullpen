import SwiftUI

struct BoardsView: View {
    var body: some View {
        NavigationStack {
            List(Board.all) { board in
                NavigationLink(value: board) {
                    HStack {
                        Image(systemName: "bubble.left.and.bubble.right")
                            .foregroundColor(.blue)
                        Text(board.name)
                            .font(.headline)
                    }
                    .padding(.vertical, 4)
                }
            }
            .navigationTitle("불펜")
            .navigationDestination(for: Board.self) { board in
                PostListView(board: board)
            }
            .navigationDestination(for: Post.self) { post in
                PostDetailView(boardId: post.boardId, postId: post.id)
            }
        }
    }
}
