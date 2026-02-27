import SwiftUI

struct ContentView: View {
    @EnvironmentObject var auth: AuthService

    var body: some View {
        TabView {
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
