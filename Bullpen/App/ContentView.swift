import SwiftUI
import UIKit

// UIScreenEdgePanGestureRecognizer를 SwiftUI에 연결
struct EdgePanGestureView: UIViewRepresentable {
    var onOpen: () -> Void
    var onClose: () -> Void
    var isEnabled: Bool

    func makeCoordinator() -> Coordinator { Coordinator(onOpen: onOpen, onClose: onClose) }

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.backgroundColor = .clear

        // 왼쪽 엣지에서 오른쪽으로 → 드로어 열기
        let openGesture = UIScreenEdgePanGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleOpen(_:))
        )
        openGesture.edges = .left
        view.addGestureRecognizer(openGesture)

        // 전체 영역 오른→왼 스와이프 → 드로어 닫기
        let closeGesture = UIPanGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleClose(_:))
        )
        view.addGestureRecognizer(closeGesture)

        context.coordinator.openGesture = openGesture
        context.coordinator.closeGesture = closeGesture
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        context.coordinator.onOpen = onOpen
        context.coordinator.onClose = onClose
        context.coordinator.openGesture?.isEnabled = isEnabled
        context.coordinator.closeGesture?.isEnabled = isEnabled
    }

    class Coordinator: NSObject {
        var onOpen: () -> Void
        var onClose: () -> Void
        weak var openGesture: UIScreenEdgePanGestureRecognizer?
        weak var closeGesture: UIPanGestureRecognizer?

        init(onOpen: @escaping () -> Void, onClose: @escaping () -> Void) {
            self.onOpen = onOpen
            self.onClose = onClose
        }

        @objc func handleOpen(_ r: UIScreenEdgePanGestureRecognizer) {
            if r.state == .ended { onOpen() }
        }

        @objc func handleClose(_ r: UIPanGestureRecognizer) {
            if r.state == .ended {
                let t = r.translation(in: r.view)
                if t.x < -60 && abs(t.y) < 80 { onClose() }
            }
        }
    }
}

enum AppSection: Equatable {
    case board
    case best
    case write
    case profile
}

struct ContentView: View {
    @EnvironmentObject var auth: AuthService
    @State private var section: AppSection = .board
    @State private var selectedBoard: Board = Board.all.first(where: { $0.id == "bullpen" }) ?? Board.all[0]
    @State private var showDrawer = false
    @State private var navPath = NavigationPath()

    var body: some View {
        NavigationStack(path: $navPath) {
            ZStack {
                Group {
                    switch section {
                    case .board:
                        PostListView(board: $selectedBoard)
                    case .best:
                        BestPostsView()
                    case .write:
                        WritePostView()
                    case .profile:
                        if auth.isLoggedIn { ProfileView() } else { LoginView() }
                    }
                }

                if showDrawer {
                    AppDrawer(selectedBoard: $selectedBoard, section: $section, isShowing: $showDrawer)
                        .transition(.move(edge: .leading))
                }
            }
            .overlay {
                EdgePanGestureView(
                    onOpen:  { withAnimation(.easeInOut(duration: 0.25)) { showDrawer = true } },
                    onClose: { withAnimation(.easeInOut(duration: 0.25)) { showDrawer = false } },
                    isEnabled: navPath.isEmpty
                )
                .allowsHitTesting(true)
                .ignoresSafeArea()
            }
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button {
                        withAnimation(.easeInOut(duration: 0.25)) { showDrawer = true }
                    } label: {
                        Image(systemName: "list.bullet.rectangle")
                    }
                }
            }
        }
    }
}

// MARK: - App Drawer

struct AppDrawer: View {
    @Binding var selectedBoard: Board
    @Binding var section: AppSection
    @Binding var isShowing: Bool

    var body: some View {
        ZStack(alignment: .leading) {
            Color.black.opacity(0.35)
                .ignoresSafeArea()
                .onTapGesture {
                    withAnimation(.easeInOut(duration: 0.25)) { isShowing = false }
                }

            VStack(alignment: .leading, spacing: 0) {
                Text("메뉴")
                    .font(.title3).fontWeight(.bold)
                    .padding(.horizontal, 20).padding(.vertical, 16)

                Divider()

                List {
                    Section("게시판") {
                        ForEach(Board.all) { board in
                            Button {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    selectedBoard = board
                                    section = .board
                                    isShowing = false
                                }
                            } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: "bubble.left.and.bubble.right.fill")
                                        .foregroundColor(section == .board && board.id == selectedBoard.id ? .blue : .secondary)
                                        .frame(width: 24)
                                    Text(board.name).font(.body).foregroundColor(.primary)
                                    Spacer()
                                    if section == .board && board.id == selectedBoard.id {
                                        Image(systemName: "checkmark")
                                            .foregroundColor(.blue).fontWeight(.semibold)
                                    }
                                }
                                .padding(.vertical, 6)
                            }
                        }
                    }

                    Section {
                        drawerItem(label: "베스트", icon: "star.fill", target: .best)
                        drawerItem(label: "글쓰기", icon: "square.and.pencil", target: .write)
                        drawerItem(label: "로그인 / 내 정보", icon: "person.circle", target: .profile)
                    }
                }
                .listStyle(.plain)
            }
            .frame(width: min(UIScreen.main.bounds.width * 0.72, 300))
            .background(Color(.systemBackground))
        }
    }

    @ViewBuilder
    private func drawerItem(label: String, icon: String, target: AppSection) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                section = target
                isShowing = false
            }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .foregroundColor(section == target ? .blue : .secondary)
                    .frame(width: 24)
                Text(label).font(.body).foregroundColor(.primary)
                Spacer()
                if section == target {
                    Image(systemName: "checkmark")
                        .foregroundColor(.blue).fontWeight(.semibold)
                }
            }
            .padding(.vertical, 6)
        }
    }
}
