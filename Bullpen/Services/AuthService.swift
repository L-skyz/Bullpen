import Foundation

@MainActor
class AuthService: ObservableObject {
    static let shared = AuthService()
    private static let persistedAuthCookieNames: Set<String> = [
        "LoginAdult",
        "SolonAuth",
        "adult",
        "adult14",
        "adultuserok",
        "classid",
        "classidpw",
        "dJoinCert",
        "drsid",
        "dusr",
        "login_id",
        "mlbuser"
    ]

    @Published var isLoggedIn = false
    @Published var nickname: String = ""

    private let base = "https://mlbpark.donga.com"
    private let session: URLSession

    private init() {
        appLog("[Auth] init start")
        let config = URLSessionConfiguration.default
        config.httpCookieStorage = HTTPCookieStorage.shared
        config.httpShouldSetCookies = true
        config.httpCookieAcceptPolicy = .always
        session = URLSession(configuration: config)
        restorePersistedCookies()
        pruneNonAuthDongaCookies()
        persistCookies()
        appLog("[Auth] cookies restored")
        checkLoginStatus()
        appLog("[Auth] checkLoginStatus → isLoggedIn=\(isLoggedIn)")
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
        req.httpBody = params
            .map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? $0.value)" }
            .joined(separator: "&")
            .data(using: .utf8)

        let (data, resp) = try await session.data(for: req)

        if let http = resp as? HTTPURLResponse, http.statusCode >= 400 {
            throw MLBParkError.networkError("로그인 실패 (\(http.statusCode))")
        }

        // Step 3: 성공/실패 판단
        // 실패: 200 OK, secure.donga.com에서 에러 HTML 반환
        // 성공: 302 redirect → mlbpark.donga.com (URLSession 자동 팔로우)
        let finalHost = (resp as? HTTPURLResponse)?.url?.host ?? ""
        if finalHost.contains("secure.donga.com") || finalHost.isEmpty {
            let html = MLBParkService.decodeServerText(data, response: resp) ?? ""
            if html.contains("회원이 아니시거나") || html.contains("비밀번호가 틀립니다") ||
               html.contains("layerPop") {
                throw MLBParkError.networkError("아이디 또는 비밀번호가 올바르지 않습니다.")
            }
            throw MLBParkError.networkError("로그인에 실패했습니다. 다시 시도해주세요.")
        }

        // Step 4: 성공 — 쿠키에서 닉네임 읽기
        // dongausernickuni (UTF-8 유니코드) 우선, 없으면 dongausernick (EUC-KR)
        let allCookies = HTTPCookieStorage.shared.cookies ?? []
        let nickValue = allCookies.first(where: {
            $0.domain.contains("donga.com") && $0.name == "dongausernickuni" &&
            !$0.value.isEmpty && $0.value != "deleted"
        })?.value
        ?? allCookies.first(where: {
            $0.domain.contains("donga.com") && $0.name == "dongausernick" &&
            !$0.value.isEmpty && $0.value != "deleted"
        })?.value
        if let n = nickValue { nickname = n.removingPercentEncoding ?? n }

        isLoggedIn = true
        persistCookies()
    }

    // MARK: - 로그아웃

    func logout() {
        isLoggedIn = false
        nickname = ""
        UserDefaults.standard.removeObject(forKey: "persistedCookies")
        // mlbpark뿐 아니라 donga.com 전체 쿠키 삭제
        let all = HTTPCookieStorage.shared.cookies ?? []
        all.filter { $0.domain.contains("donga.com") }
           .forEach { HTTPCookieStorage.shared.deleteCookie($0) }
    }

    // MARK: - 프로필 조회 / 세션 검증

    func fetchProfile() async {
        // MLBParkService.fetchHTML 사용 → warmup + 인코딩 처리 자동 포함
        // (자체 session으로 직접 요청 시 gather.donga.com warmup 쿠키 누락으로
        //  mlbpark가 로그인 상태 HTML 미반환하는 문제 방지)
        do {
            let html = try await MLBParkService.shared.fetchHTML("\(base)/mp/b.php?b=bullpen", caller: "fetchProfile")

            if html.contains("로그아웃") {
                isLoggedIn = true
                // raw HTML 패턴: class='login'>로그아웃 (닉네임)</a>
                if let start = html.range(of: "로그아웃 ("),
                   let end   = html[start.upperBound...].range(of: ")") {
                    let extracted = String(html[start.upperBound..<end.lowerBound])
                    if !extracted.isEmpty { nickname = extracted }
                }
            } else {
                isLoggedIn = false
                nickname   = ""
            }
        } catch {
            // 네트워크 오류 시 기존 상태 유지
        }
    }

    // MARK: - 쿠키 영속화

    private func isActiveCookie(_ cookie: HTTPCookie) -> Bool {
        guard !cookie.value.isEmpty, cookie.value != "deleted" else { return false }
        if let expiresDate = cookie.expiresDate {
            return expiresDate > Date()
        }
        return true
    }

    private func shouldPersistAuthCookie(_ cookie: HTTPCookie) -> Bool {
        guard cookie.domain.contains("donga.com"), isActiveCookie(cookie) else { return false }
        return cookie.name.hasPrefix("dongauser") ||
               Self.persistedAuthCookieNames.contains(cookie.name)
    }

    private func pruneNonAuthDongaCookies() {
        let all = HTTPCookieStorage.shared.cookies ?? []
        all.filter { $0.domain.contains("donga.com") && !shouldPersistAuthCookie($0) }
           .forEach { HTTPCookieStorage.shared.deleteCookie($0) }
    }

    private func persistCookies() {
        // 로그인 복원에 필요한 인증 쿠키만 저장한다.
        let all = HTTPCookieStorage.shared.cookies ?? []
        let saved: [[String: String]] = all.compactMap { c in
            guard shouldPersistAuthCookie(c) else { return nil }

            var dict: [String: String] = [
                "name": c.name,
                "value": c.value,
                "domain": c.domain,
                "path": c.path
            ]
            if c.isSecure { dict["secure"] = "1" }
            if c.isHTTPOnly { dict["httpOnly"] = "1" }
            if let expiresDate = c.expiresDate {
                dict["expires"] = String(expiresDate.timeIntervalSince1970)
            }
            return dict
        }
        if saved.isEmpty {
            UserDefaults.standard.removeObject(forKey: "persistedCookies")
        } else {
            UserDefaults.standard.set(saved, forKey: "persistedCookies")
        }
    }

    private func restorePersistedCookies() {
        guard let saved = UserDefaults.standard.array(forKey: "persistedCookies")
                as? [[String: String]] else { return }
        for dict in saved {
            guard let name = dict["name"], let value = dict["value"],
                  let domain = dict["domain"] else { continue }
            var props: [HTTPCookiePropertyKey: Any] = [
                .name:    name,
                .value:   value,
                .domain:  domain,
                .path:    dict["path"] ?? "/"
            ]
            if dict["secure"] == "1" { props[.secure] = "TRUE" }
            if dict["httpOnly"] == "1" {
                props[HTTPCookiePropertyKey(rawValue: "HttpOnly")] = "TRUE"
            }
            if let expires = dict["expires"], let timestamp = TimeInterval(expires) {
                props[.expires] = Date(timeIntervalSince1970: timestamp)
            }
            if let cookie = HTTPCookie(properties: props) {
                HTTPCookieStorage.shared.setCookie(cookie)
            }
        }
    }

    // MARK: - 저장된 세션 확인

    private func checkLoginStatus() {
        let allCookies = HTTPCookieStorage.shared.cookies ?? []

        // 닉네임 쿠키가 있으면 확실히 로그인 상태
        // dongausernickuni (UTF-8) 우선, 없으면 dongausernick (EUC-KR)
        let nickValue = allCookies.first(where: {
            $0.domain.contains("donga.com") && $0.name == "dongausernickuni" &&
            !$0.value.isEmpty && $0.value != "deleted"
        })?.value
        ?? allCookies.first(where: {
            $0.domain.contains("donga.com") && $0.name == "dongausernick" &&
            !$0.value.isEmpty && $0.value != "deleted"
        })?.value
        if let n = nickValue {
            nickname = n.removingPercentEncoding ?? n
            isLoggedIn = true
            return
        }

        // 닉네임 쿠키가 없어도 인증 쿠키가 남아 있으면 로그인 상태로 유지한다.
        let hasAuthCookie = allCookies.contains(where: shouldPersistAuthCookie)
        let hasPersistedData = UserDefaults.standard.array(forKey: "persistedCookies") != nil
        isLoggedIn = hasAuthCookie && hasPersistedData
    }
}

import SwiftSoup

// MARK: - AppLogger (임시 진단용)

struct LogEntry: Identifiable {
    let id = UUID()
    let elapsed: Double
    let message: String
    var timeStr: String { String(format: "+%.3fs", elapsed) }
}

/// 어느 actor/스레드에서든 await 없이 호출 가능
func appLog(_ message: String) {
    DispatchQueue.main.async { AppLogger.shared.append(message) }
}

@MainActor
class AppLogger: ObservableObject {
    static let shared = AppLogger()
    private let t0 = Date()
    @Published private(set) var entries: [LogEntry] = []
    private init() {}

    fileprivate func append(_ message: String) {
        let elapsed = Date().timeIntervalSince(t0)
        entries.append(LogEntry(elapsed: elapsed, message: message))
        print("[AppLog] +\(String(format: "%.3f", elapsed))s \(message)")
    }

    func clear() { entries.removeAll() }
}
