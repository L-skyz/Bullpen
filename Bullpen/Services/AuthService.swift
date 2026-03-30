import Foundation
import Security

@MainActor
class AuthService: ObservableObject {
    static let shared = AuthService()

    @Published var isLoggedIn = false
    @Published var nickname: String = ""
    @Published var avatarUrl: String = ""

    private let base = "https://mlbpark.donga.com"
    private let session: URLSession
    private var isReloginInProgress = false

    private init() {
        let config = URLSessionConfiguration.default
        config.httpCookieStorage = HTTPCookieStorage.shared
        config.httpShouldSetCookies = true
        config.httpCookieAcceptPolicy = .always
        session = URLSession(configuration: config)
        restorePersistedCookies()
        // 저장된 프로필이 있으면 즉시 복원 (네트워크 대기 없이 UI 표시)
        if let saved = UserDefaults.standard.dictionary(forKey: "persistedProfile") as? [String: String],
           let name = saved["nickname"], !name.isEmpty {
            isLoggedIn = true
            nickname   = name
            avatarUrl  = saved["avatarUrl"] ?? ""
        }
        // 실제 검증은 BullpenApp.task에서 fetchProfile()로 수행
    }

    // MARK: - 로그인

    func login(id: String, password: String) async throws {
        let loginPageURL = "https://secure.donga.com/mlbpark/login.php"
        let loginActionURL = "https://secure.donga.com/mlbpark/trans_exe.php"
        let ua = "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15"

        // Step 1: GET 로그인 페이지 → 세션 쿠키 수신
        if let getURL = URL(string: loginPageURL) {
            var getReq = URLRequest(url: getURL)
            getReq.setValue(ua, forHTTPHeaderField: "User-Agent")
            _ = try? await session.data(for: getReq)
        }

        // Step 2: POST to trans_exe.php
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

        // Step 3: 성공/실패 판단 (실패 시 secure.donga.com에 머뭄)
        let finalHost = (resp as? HTTPURLResponse)?.url?.host ?? ""
        if finalHost.contains("secure.donga.com") || finalHost.isEmpty {
            let html = MLBParkService.decodeServerText(data, response: resp) ?? ""
            if html.contains("회원이 아니시거나") || html.contains("비밀번호가 틀립니다") ||
               html.contains("layerPop") {
                throw MLBParkError.networkError("아이디 또는 비밀번호가 올바르지 않습니다.")
            }
            throw MLBParkError.networkError("로그인에 실패했습니다. 다시 시도해주세요.")
        }

        // Step 4: 성공 — 자격증명·쿠키 저장 후 프로필 확인
        saveCredentials(id: id, password: password)
        persistCookies()
        await fetchProfile()
        persistProfile()
    }

    // MARK: - 로그아웃

    func logout() {
        isLoggedIn = false
        nickname = ""
        avatarUrl = ""
        clearCredentials()
        UserDefaults.standard.removeObject(forKey: "persistedCookies")
        UserDefaults.standard.removeObject(forKey: "persistedProfile")
        HTTPCookieStorage.shared.cookies?
            .filter { $0.domain.contains("donga.com") }
            .forEach { HTTPCookieStorage.shared.deleteCookie($0) }
    }

    // MARK: - 로그인 상태 + 닉네임 확인 (HTML 기준)

    func fetchProfile() async {
        do {
            let html = try await MLBParkService.shared.fetchHTML("\(base)/mp/b.php?b=bullpen")
            if html.contains("로그아웃") {
                isLoggedIn = true
                if let start = html.range(of: "로그아웃 ("),
                   let end   = html[start.upperBound...].range(of: ")") {
                    let extracted = String(html[start.upperBound..<end.lowerBound])
                    if !extracted.isEmpty { nickname = extracted }
                }
                updateAvatarUrl()
                persistProfile()
            } else {
                // 세션 만료 — Keychain 자격증명으로 자동 재로그인 시도
                if !isReloginInProgress, let (id, pw) = loadCredentials() {
                    isReloginInProgress = true
                    defer { isReloginInProgress = false }
                    // 만료된 쿠키 정리 후 재로그인
                    HTTPCookieStorage.shared.cookies?
                        .filter { $0.domain.contains("donga.com") }
                        .forEach { HTTPCookieStorage.shared.deleteCookie($0) }
                    UserDefaults.standard.removeObject(forKey: "persistedCookies")
                    do {
                        try await login(id: id, password: pw)
                        // login()이 내부적으로 fetchProfile()까지 완료함
                    } catch {
                        // 재로그인 실패 (비번 변경 등) → 자격증명 폐기, 로그아웃 처리
                        clearCredentials()
                        isLoggedIn = false
                        nickname   = ""
                        avatarUrl  = ""
                        UserDefaults.standard.removeObject(forKey: "persistedProfile")
                    }
                } else {
                    isLoggedIn = false
                    nickname   = ""
                    avatarUrl  = ""
                    UserDefaults.standard.removeObject(forKey: "persistedProfile")
                }
            }
        } catch {
            // 네트워크 오류 시 기존 상태 유지
        }
    }

    // MARK: - 아바타 URL 구성

    private func updateAvatarUrl() {
        // mpuser 쿠키 → uid 각 문자를 디렉토리로 분리 + @ 패딩으로 총 12개
        // 예: uid="sm12011"(7자) → s/m/1/2/0/1/1/@/@/@/@/@/sm12011@@@@@@d.png
        guard let uid = HTTPCookieStorage.shared.cookies?.first(where: {
            $0.domain.contains("donga.com") && $0.name == "mpuser" && !$0.value.isEmpty
        })?.value else { return }
        let totalDirs = 12
        let padding = max(0, totalDirs - uid.count)
        let dirPart = uid.map { String($0) }.joined(separator: "/")
            + String(repeating: "/@", count: padding)
        let atPadding = String(repeating: "@", count: padding + 1)
        avatarUrl = "https://dimg.donga.com/ugc/WWW/Profile/\(dirPart)/\(uid)\(atPadding)d.png"
    }

    // MARK: - 프로필 영속화 (빠른 복원용)

    private func persistProfile() {
        guard isLoggedIn, !nickname.isEmpty else { return }
        UserDefaults.standard.set(
            ["nickname": nickname, "avatarUrl": avatarUrl],
            forKey: "persistedProfile"
        )
    }

    // MARK: - Keychain 자격증명 (자동 재로그인용)

    private static let keychainService = "com.bullpen.auth"
    private static let keychainAccount = "login_credentials"

    private func saveCredentials(id: String, password: String) {
        guard let data = try? JSONSerialization.data(withJSONObject: ["id": id, "pw": password]) else { return }
        let query: [CFString: Any] = [
            kSecClass:           kSecClassGenericPassword,
            kSecAttrService:     Self.keychainService,
            kSecAttrAccount:     Self.keychainAccount,
            kSecValueData:       data,
            kSecAttrAccessible:  kSecAttrAccessibleWhenUnlocked
        ]
        SecItemDelete(query as CFDictionary)
        SecItemAdd(query as CFDictionary, nil)
    }

    private func loadCredentials() -> (id: String, password: String)? {
        let query: [CFString: Any] = [
            kSecClass:        kSecClassGenericPassword,
            kSecAttrService:  Self.keychainService,
            kSecAttrAccount:  Self.keychainAccount,
            kSecReturnData:   true,
            kSecMatchLimit:   kSecMatchLimitOne
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data,
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: String],
              let id = dict["id"], let pw = dict["pw"] else { return nil }
        return (id, pw)
    }

    private func clearCredentials() {
        let query: [CFString: Any] = [
            kSecClass:       kSecClassGenericPassword,
            kSecAttrService: Self.keychainService,
            kSecAttrAccount: Self.keychainAccount
        ]
        SecItemDelete(query as CFDictionary)
    }

    // MARK: - 쿠키 영속화 (세션 유지용)

    private func persistCookies() {
        let saved: [[String: String]] = (HTTPCookieStorage.shared.cookies ?? [])
            .filter { $0.domain.contains("donga.com") && !$0.value.isEmpty && $0.value != "deleted" }
            .compactMap { c in
                if let exp = c.expiresDate, exp <= Date() { return nil }
                var d: [String: String] = ["name": c.name, "value": c.value,
                                           "domain": c.domain, "path": c.path]
                if c.isSecure { d["secure"] = "1" }
                if let exp = c.expiresDate { d["expires"] = String(exp.timeIntervalSince1970) }
                return d
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
            if let exp = dict["expires"], let ts = TimeInterval(exp), Date(timeIntervalSince1970: ts) <= Date() { continue }
            var props: [HTTPCookiePropertyKey: Any] = [
                .name: name, .value: value, .domain: domain, .path: dict["path"] ?? "/"
            ]
            if dict["secure"] == "1" { props[.secure] = "TRUE" }
            if let exp = dict["expires"], let ts = TimeInterval(exp) {
                props[.expires] = Date(timeIntervalSince1970: ts)
            }
            if let cookie = HTTPCookie(properties: props) {
                HTTPCookieStorage.shared.setCookie(cookie)
            }
        }
    }
}
