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
        let loginPageURL = "https://secure.donga.com/mlbpark/login.php"
        // JS가 form action을 trans_exe.php로 동적 변경 후 submit — 실제 엔드포인트
        let loginActionURL = "https://secure.donga.com/mlbpark/trans_exe.php"
        let ua = "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15"

        // Step 1: GET 로그인 페이지 → 세션 쿠키(gourl 등) 수신
        if let getURL = URL(string: loginPageURL) {
            var getReq = URLRequest(url: getURL)
            getReq.setValue(ua, forHTTPHeaderField: "User-Agent")
            _ = try? await session.data(for: getReq)
        }

        // Step 2: POST to trans_exe.php (브라우저와 동일한 실제 엔드포인트)
        guard let postURL = URL(string: loginActionURL) else { return }
        var req = URLRequest(url: postURL)
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        req.setValue(ua, forHTTPHeaderField: "User-Agent")
        req.setValue(loginPageURL, forHTTPHeaderField: "Referer")

        let params: [String: String] = [
            "bid":          id,
            "bpw":          password,
            "gourl":        "https://mlbpark.donga.com/mp",
            "mlbuser":      "1",
            "errorChk":     "",
            "idsave_value": ""
        ]
        req.httpBody = params.urlEncoded.data(using: .utf8)

        let (data, resp) = try await session.data(for: req)

        if let http = resp as? HTTPURLResponse, http.statusCode >= 400 {
            throw MLBParkError.networkError("로그인 실패 (\(http.statusCode))")
        }

        // Step 3: 성공/실패 판단
        // 실패: 200 OK, secure.donga.com에서 에러 HTML 반환
        // 성공: 302 redirect → mlbpark.donga.com (URLSession 자동 팔로우)
        let finalHost = (resp as? HTTPURLResponse)?.url?.host ?? ""
        if finalHost.contains("secure.donga.com") || finalHost.isEmpty {
            let html = String(data: data, encoding: .utf8) ?? ""
            if html.contains("회원이 아니시거나") || html.contains("비밀번호가 틀립니다") ||
               html.contains("layerPop") {
                throw MLBParkError.networkError("아이디 또는 비밀번호가 올바르지 않습니다.")
            }
            throw MLBParkError.networkError("로그인에 실패했습니다. 다시 시도해주세요.")
        }

        // Step 4: 성공 — 쿠키에서 닉네임 읽기 (dongausernick)
        let allCookies = HTTPCookieStorage.shared.cookies ?? []
        if let nick = allCookies.first(where: {
            $0.domain.contains("donga.com") &&
            ($0.name == "dongausernick" || $0.name == "dongausernickuni") &&
            !$0.value.isEmpty && $0.value != "deleted"
        })?.value {
            nickname = nick.removingPercentEncoding ?? nick
        }

        isLoggedIn = true
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
        let allCookies = HTTPCookieStorage.shared.cookies ?? []
        let authCookie = allCookies.first { c in
            c.domain.contains("donga.com") &&
            ["dongauserid", "dusr", "mlbuser", "login_id"].contains(c.name) &&
            !c.value.isEmpty && c.value != "deleted"
        }
        isLoggedIn = authCookie != nil

        if isLoggedIn {
            if let nick = allCookies.first(where: {
                $0.domain.contains("donga.com") &&
                ($0.name == "dongausernick" || $0.name == "dongausernickuni") &&
                !$0.value.isEmpty && $0.value != "deleted"
            })?.value {
                nickname = nick.removingPercentEncoding ?? nick
            }
        }
    }
}

import SwiftSoup
