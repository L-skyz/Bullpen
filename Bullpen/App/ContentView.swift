import SwiftUI

struct ContentView: View {
    @EnvironmentObject var auth: AuthService

    var body: some View {
        TabView {
            // 불펜을 첫 번째 기본 탭으로
            PostListView(board: Board(id: "bullpen", name: "불펜"))
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
