import Foundation
import Security

@MainActor
class AuthService: ObservableObject {
    static let shared = AuthService()

    private static let persistedCookiesKey = "persistedCookies"
    private static let persistedProfileKey = "persistedProfile"
    private static let likelyAuthCookieNames: Set<String> = [
        "mlbuser",
        "mpuser"
    ]
    private static let keychainService = "com.bullpen.auth"
    private static let keychainAccount = "login_credentials"

    @Published var isLoggedIn = false
    @Published var nickname: String = ""
    @Published var avatarUrl: String = ""

    private let base = "https://mlbpark.donga.com"
    private let session: URLSession
    private var isReloginInProgress = false
    private var lastValidatedDate: Date? = nil

    private init() {
        let config = URLSessionConfiguration.default
        config.httpCookieStorage = HTTPCookieStorage.shared
        config.httpShouldSetCookies = true
        config.httpCookieAcceptPolicy = .always
        session = URLSession(configuration: config)
        restorePersistedCookies()
        purgeInvalidCookies()
        persistCookies()

        if hasRestorableLoginCookies(),
           let saved = UserDefaults.standard.dictionary(forKey: Self.persistedProfileKey) as? [String: String],
           let name = saved["nickname"], !name.isEmpty {
            isLoggedIn = true
            nickname = name
            avatarUrl = saved["avatarUrl"] ?? ""
        } else {
            UserDefaults.standard.removeObject(forKey: Self.persistedProfileKey)
        }
    }

    // MARK: - 로그인

    func login(id: String, password: String) async throws {
        let loginPageURL = "https://secure.donga.com/mlbpark/login.php"
        let loginActionURL = "https://secure.donga.com/mlbpark/trans_exe.php"
        let ua = "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15"

        if let getURL = URL(string: loginPageURL) {
            var getReq = URLRequest(url: getURL)
            getReq.setValue(ua, forHTTPHeaderField: "User-Agent")
            _ = try? await session.data(for: getReq)
        }

        guard let postURL = URL(string: loginActionURL) else { return }
        var req = URLRequest(url: postURL)
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        req.setValue(ua, forHTTPHeaderField: "User-Agent")
        req.setValue(loginPageURL, forHTTPHeaderField: "Referer")

        let params: [String: String] = [
            "bid": id,
            "bpw": password,
            "gourl": "https://mlbpark.donga.com/mp",
            "mlbuser": "1",
            "errorChk": "",
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

        let finalHost = (resp as? HTTPURLResponse)?.url?.host ?? ""
        if finalHost.contains("secure.donga.com") || finalHost.isEmpty {
            let html = MLBParkService.decodeServerText(data, response: resp) ?? ""
            if html.contains("회원이 아니시거나") || html.contains("비밀번호가 틀립니다") ||
               html.contains("layerPop") {
                throw MLBParkError.networkError("아이디 또는 비밀번호가 올바르지 않습니다.")
            }
            throw MLBParkError.networkError("로그인에 실패했습니다. 다시 시도해주세요.")
        }

        saveCredentials(id: id, password: password)
        persistCookies()
        await fetchProfile()
        persistProfile()
    }

    // MARK: - 로그아웃

    func logout() {
        clearLoginState(deleteCookies: true, clearCredentials: true)
    }

    // MARK: - 로그인 상태 + 닉네임 확인

    func updateLoginState(from html: String) {
        if html.contains("로그아웃") {
            isLoggedIn = true
            if let start = html.range(of: "로그아웃 ("),
               let end = html[start.upperBound...].range(of: ")") {
                let extracted = String(html[start.upperBound..<end.lowerBound])
                if !extracted.isEmpty { nickname = extracted }
            }
            updateAvatarUrl()
            persistCookies()
            persistProfile()
            lastValidatedDate = Date()
        } else {
            Task { await fetchProfile() }
        }
    }

    func fetchProfile() async {
        if let last = lastValidatedDate, Date().timeIntervalSince(last) < 10 { return }

        do {
            let html = try await MLBParkService.shared.fetchHTML("\(base)/mp/b.php?b=bullpen")
            if html.contains("로그아웃") {
                isLoggedIn = true
                if let start = html.range(of: "로그아웃 ("),
                   let end = html[start.upperBound...].range(of: ")") {
                    let extracted = String(html[start.upperBound..<end.lowerBound])
                    if !extracted.isEmpty { nickname = extracted }
                }
                updateAvatarUrl()
                persistCookies()
                persistProfile()
                lastValidatedDate = Date()
            } else if !isReloginInProgress, let (id, pw) = loadCredentials() {
                isReloginInProgress = true
                defer { isReloginInProgress = false }
                deleteLoginCookies()
                UserDefaults.standard.removeObject(forKey: Self.persistedCookiesKey)

                do {
                    try await login(id: id, password: pw)
                } catch {
                    clearLoginState(deleteCookies: true, clearCredentials: true)
                }
            } else {
                clearLoginState(deleteCookies: true)
            }
        } catch {
            // 네트워크 오류 시 기존 상태 유지
        }
    }

    // MARK: - 아바타 URL 구성

    private func updateAvatarUrl() {
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

    // MARK: - 프로필 영속화

    private func persistProfile() {
        guard isLoggedIn, !nickname.isEmpty else { return }
        UserDefaults.standard.set(
            ["nickname": nickname, "avatarUrl": avatarUrl],
            forKey: Self.persistedProfileKey
        )
    }

    // MARK: - Keychain 자격증명

    private func saveCredentials(id: String, password: String) {
        guard let data = try? JSONSerialization.data(withJSONObject: ["id": id, "pw": password]) else { return }
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: Self.keychainService,
            kSecAttrAccount: Self.keychainAccount,
            kSecValueData: data,
            kSecAttrAccessible: kSecAttrAccessibleWhenUnlocked
        ]
        SecItemDelete(query as CFDictionary)
        SecItemAdd(query as CFDictionary, nil)
    }

    private func loadCredentials() -> (id: String, password: String)? {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: Self.keychainService,
            kSecAttrAccount: Self.keychainAccount,
            kSecReturnData: true,
            kSecMatchLimit: kSecMatchLimitOne
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data,
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: String],
              let id = dict["id"],
              let pw = dict["pw"] else { return nil }
        return (id, pw)
    }

    private func clearCredentials() {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: Self.keychainService,
            kSecAttrAccount: Self.keychainAccount
        ]
        SecItemDelete(query as CFDictionary)
    }

    // MARK: - 쿠키 영속화

    private func persistCookies() {
        let saved: [[String: String]] = (HTTPCookieStorage.shared.cookies ?? [])
            .filter { shouldPersistCookie($0) }
            .compactMap { cookie in
                var item: [String: String] = [
                    "name": cookie.name,
                    "value": cookie.value,
                    "domain": cookie.domain,
                    "path": cookie.path
                ]
                if cookie.isSecure { item["secure"] = "1" }
                if let expiry = cookie.expiresDate {
                    item["expires"] = String(expiry.timeIntervalSince1970)
                }
                return item
            }

        if saved.isEmpty {
            UserDefaults.standard.removeObject(forKey: Self.persistedCookiesKey)
        } else {
            UserDefaults.standard.set(saved, forKey: Self.persistedCookiesKey)
        }
    }

    private func restorePersistedCookies() {
        guard let saved = UserDefaults.standard.array(forKey: Self.persistedCookiesKey) as? [[String: String]] else { return }

        for dict in saved {
            guard let name = dict["name"],
                  let value = dict["value"],
                  let domain = dict["domain"],
                  let exp = dict["expires"],
                  let ts = TimeInterval(exp) else { continue }

            let expiry = Date(timeIntervalSince1970: ts)
            guard expiry > Date() else { continue }

            var props: [HTTPCookiePropertyKey: Any] = [
                .name: name,
                .value: value,
                .domain: domain,
                .path: dict["path"] ?? "/",
                .expires: expiry
            ]
            if dict["secure"] == "1" { props[.secure] = "TRUE" }

            if let cookie = HTTPCookie(properties: props) {
                HTTPCookieStorage.shared.setCookie(cookie)
            }
        }
    }

    private func shouldPersistCookie(_ cookie: HTTPCookie) -> Bool {
        guard cookie.domain.contains("donga.com"),
              !cookie.value.isEmpty,
              cookie.value != "deleted",
              let expiry = cookie.expiresDate,
              expiry > Date() else {
            return false
        }
        return true
    }

    private func purgeInvalidCookies() {
        let stale = (HTTPCookieStorage.shared.cookies ?? []).filter { cookie in
            guard cookie.domain.contains("donga.com") else { return false }
            if cookie.value.isEmpty || cookie.value == "deleted" { return true }
            if let expiry = cookie.expiresDate {
                return expiry <= Date()
            }
            return false
        }

        stale.forEach { HTTPCookieStorage.shared.deleteCookie($0) }
    }

    private func hasRestorableLoginCookies() -> Bool {
        (HTTPCookieStorage.shared.cookies ?? []).contains { cookie in
            guard cookie.domain.contains("donga.com"),
                  Self.likelyAuthCookieNames.contains(cookie.name),
                  !cookie.value.isEmpty,
                  cookie.value != "deleted" else {
                return false
            }

            if let expiry = cookie.expiresDate {
                return expiry > Date()
            }
            return true
        }
    }

    private func clearLoginState(deleteCookies: Bool, clearCredentials: Bool = false) {
        isLoggedIn = false
        nickname = ""
        avatarUrl = ""
        lastValidatedDate = nil
        UserDefaults.standard.removeObject(forKey: Self.persistedCookiesKey)
        UserDefaults.standard.removeObject(forKey: Self.persistedProfileKey)
        if clearCredentials { self.clearCredentials() }
        if deleteCookies { deleteLoginCookies() }
    }

    private func deleteLoginCookies() {
        HTTPCookieStorage.shared.cookies?
            .filter { shouldDeleteCookie($0) }
            .forEach { HTTPCookieStorage.shared.deleteCookie($0) }
    }

    private func shouldDeleteCookie(_ cookie: HTTPCookie) -> Bool {
        cookie.domain.contains("donga.com") && cookie.name != "GsCK_AC"
    }
}
