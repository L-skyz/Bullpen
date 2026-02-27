import SwiftUI

struct ContentView: View {
    @EnvironmentObject var auth: AuthService
    @State private var selectedBoard: Board = Board.all.first(where: { $0.id == "bullpen" }) ?? Board.all[0]
    @State private var showProfileDrawer = false

    var body: some View {
        TabView {
            // 불펜 탭
            NavigationStack {
                PostListView(board: $selectedBoard)
            }
            .tabItem { Label("불펜", systemImage: "flame") }

            // 베스트 탭
            BestPostsView()
                .tabItem { Label("베스트", systemImage: "star.fill") }

            // 글쓰기 탭
            WritePostView()
                .tabItem { Label("글쓰기", systemImage: "square.and.pencil") }

            // 로그인/내정보 탭 — 사이드바 포함
            NavigationStack {
                ZStack {
                    Group {
                        if auth.isLoggedIn {
                            ProfileView()
                        } else {
                            LoginView()
                        }
                    }

                    if showProfileDrawer {
                        BoardDrawer(selectedBoard: $selectedBoard, isShowing: $showProfileDrawer)
                            .transition(.move(edge: .leading))
                    }
                }
                .toolbar {
                    ToolbarItem(placement: .navigationBarLeading) {
                        Button {
                            withAnimation(.easeInOut(duration: 0.25)) { showProfileDrawer = true }
                        } label: {
                            Image(systemName: "list.bullet.rectangle")
                        }
                    }
                }
                .gesture(
                    DragGesture(minimumDistance: 40, coordinateSpace: .local)
                        .onEnded { v in
                            let dx = v.translation.width
                            let dy = abs(v.translation.height)
                            if dx > 60 && dy < 80 {
                                withAnimation(.easeInOut(duration: 0.25)) { showProfileDrawer = true }
                            } else if dx < -60 && dy < 80 {
                                withAnimation(.easeInOut(duration: 0.25)) { showProfileDrawer = false }
                            }
                        }
                )
            }
            .tabItem { Label(auth.isLoggedIn ? "내 정보" : "로그인", systemImage: "person.circle") }
        }
    }
}
