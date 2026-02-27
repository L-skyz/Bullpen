import SwiftUI

struct ContentView: View {
    @EnvironmentObject var auth: AuthService
    @State private var selectedBoard: Board = Board.all.first(where: { $0.id == "bullpen" }) ?? Board.all[0]

    var body: some View {
        TabView {
            // 불펜 탭 - NavigationStack은 여기서만 1번 감싸기
            NavigationStack {
                PostListView(board: $selectedBoard)
            }
            .tabItem { Label("불펜", systemImage: "flame") }

            BoardsView()
                .tabItem { Label("게시판", systemImage: "list.bullet.rectangle") }

            WritePostView()
                .tabItem { Label("글쓰기", systemImage: "square.and.pencil") }

            Group {
                if auth.isLoggedIn {
                    ProfileView()
                } else {
                    LoginView()
                }
            }
            .tabItem { Label(auth.isLoggedIn ? "내 정보" : "로그인", systemImage: "person.circle") }
        }
    }
}
