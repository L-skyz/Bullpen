import Foundation

@MainActor
class AuthService: ObservableObject {
    static let shared = AuthService()

    @Published var isLoggedIn = false
    @Published var nickname: String = ""

    private let base = "https://mlbpark.donga.com"
    private let session: URLSession

    private init() {
        let config = URLSessionConfiguration.default
        config.httpCookieStorage = HTTPCookieStorage.shared
        config.httpShouldSetCookies = true
        config.httpCookieAcceptPolicy = .always
        session = URLSession(configuration: config)
        checkLoginStatus()
    }

    // MARK: - 로그인

    func login(id: String, password: String) async throws {
        // 실제 로그인 엔드포인트: secure.donga.com
        guard let loginURL = URL(string: "https://secure.donga.com/mlbpark/login.php") else { return }

        var req = URLRequest(url: loginURL)
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        req.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15", forHTTPHeaderField: "User-Agent")
        req.setValue("https://secure.donga.com/mlbpark/login.php", forHTTPHeaderField: "Referer")

        // 실제 폼 필드: bid=아이디, bpw=비밀번호
        let params: [String: String] = [
            "bid":     id,
            "bpw":     password,
            "gourl":   "https://mlbpark.donga.com/mp",
            "mlbuser": "1"
        ]
        req.httpBody = params.urlEncoded.data(using: .utf8)

        let (_, resp) = try await session.data(for: req)

        if let http = resp as? HTTPURLResponse, http.statusCode >= 400 {
            throw MLBParkError.networkError("로그인 실패 (\(http.statusCode))")
        }

        // 성공 여부 = .donga.com 도메인에 인증 쿠키가 실제로 세팅됐는지로 판단
        // (실패 시 서버가 모든 쿠키를 deleted로 초기화함)
        let authCookieNames = ["dongauserid", "dusr", "mlbuser", "login_id"]
        let allCookies = HTTPCookieStorage.shared.cookies ?? []
        let loggedIn = allCookies.contains { cookie in
            cookie.domain.contains("donga.com") &&
            authCookieNames.contains(cookie.name) &&
            !cookie.value.isEmpty && cookie.value != "deleted"
        }

        guard loggedIn else {
            throw MLBParkError.networkError("아이디 또는 비밀번호가 올바르지 않습니다.")
        }

        await fetchProfile()
    }

    // MARK: - 로그아웃

    func logout() {
        isLoggedIn = false
        nickname = ""
        if let cookies = HTTPCookieStorage.shared.cookies(for: URL(string: base)!) {
            cookies.forEach { HTTPCookieStorage.shared.deleteCookie($0) }
        }
    }

    // MARK: - 프로필 조회

    func fetchProfile() async {
        guard let url = URL(string: "\(base)/mp/mypage.php") else { return }
        var req = URLRequest(url: url)
        req.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 17_0)", forHTTPHeaderField: "User-Agent")

        do {
            let (data, _) = try await session.data(for: req)
            let html = String(data: data, encoding: .utf8) ?? ""

            if let doc = try? SwiftSoup.parse(html),
               let nick = try? doc.select(".nick, .nickname, #user_nick").first()?.text() {
                nickname = nick
            }
            isLoggedIn = html.contains("로그아웃")
        } catch {
            isLoggedIn = false
        }
    }

    // MARK: - 저장된 세션 확인

    private func checkLoginStatus() {
        let authCookieNames = ["dongauserid", "dusr", "mlbuser", "login_id"]
        let allCookies = HTTPCookieStorage.shared.cookies ?? []
        isLoggedIn = allCookies.contains { cookie in
            cookie.domain.contains("donga.com") &&
            authCookieNames.contains(cookie.name) &&
            !cookie.value.isEmpty && cookie.value != "deleted"
        }
    }
}

import SwiftSoup
