import Foundation

@MainActor
class AuthService: ObservableObject {
    static let shared = AuthService()

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
        appLog("[Auth] cookies restored")
        checkLoginStatus()
        appLog("[Auth] checkLoginStatus → isLoggedIn=\(isLoggedIn)")
        // 쿠키 복원 후 서버로 실제 세션 유효 여부 검증
        if isLoggedIn {
            Task {
                appLog("[Auth] fetchProfile start")
                await fetchProfile()
                appLog("[Auth] fetchProfile done → isLoggedIn=\(isLoggedIn)")
            }
        }
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
            let html = try await MLBParkService.shared.fetchHTML("\(base)/mp/b.php?b=bullpen")

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

    private func persistCookies() {
        // mlbpark.donga.com만이 아닌 *.donga.com 전체 저장
        // (인증 쿠키가 secure.donga.com에서 .donga.com 도메인으로 세팅될 수 있음)
        let all = HTTPCookieStorage.shared.cookies ?? []
        let saved: [[String: String]] = all.compactMap { c in
            guard c.domain.contains("donga.com"),
                  !c.value.isEmpty, c.value != "deleted" else { return nil }
            return ["name": c.name, "value": c.value,
                    "domain": c.domain, "path": c.path]
        }
        UserDefaults.standard.set(saved, forKey: "persistedCookies")
    }

    private func restorePersistedCookies() {
        guard let saved = UserDefaults.standard.array(forKey: "persistedCookies")
                as? [[String: String]] else { return }
        for dict in saved {
            guard let name = dict["name"], let value = dict["value"],
                  let domain = dict["domain"] else { continue }
            let props: [HTTPCookiePropertyKey: Any] = [
                .name:    name,
                .value:   value,
                .domain:  domain,
                .path:    dict["path"] ?? "/",
                .expires: Date(timeIntervalSinceNow: 30 * 24 * 60 * 60)
            ]
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

        // 닉네임 쿠키가 없어도 복원된 donga.com 쿠키가 있으면 일단 로그인 간주
        // (fetchProfile이 비동기로 서버 검증하여 최종 결정)
        let hasDongaCookie = allCookies.contains {
            $0.domain.contains("donga.com") &&
            !$0.value.isEmpty && $0.value != "deleted"
        }
        let hasPersistedData = UserDefaults.standard.array(forKey: "persistedCookies") != nil
        isLoggedIn = hasDongaCookie && hasPersistedData
    }
}

import SwiftSoup
