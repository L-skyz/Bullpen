import Foundation
import SwiftSoup

enum MLBParkError: LocalizedError {
    case invalidURL
    case encodingError
    case parseError(String)
    case networkError(String)
    case authRequired

    var errorDescription: String? {
        switch self {
        case .invalidURL:             return "잘못된 URL입니다."
        case .encodingError:          return "인코딩 오류가 발생했습니다."
        case .parseError(let m):      return "파싱 오류: \(m)"
        case .networkError(let m):    return "네트워크 오류: \(m)"
        case .authRequired:           return "로그인이 필요합니다."
        }
    }
}

actor MLBParkService {
    static let shared = MLBParkService()
    private static let listPageSize = 30
    private static let utf8Charsets: Set<String> = ["utf-8", "utf8"]
    private static let legacyKoreanCharsets: Set<String> = [
        "euc-kr",
        "cp949",
        "x-windows-949",
        "windows-949",
        "ks_c_5601-1987",
        "ks-c-5601-1987",
        "cseuckr"
    ]

    private let base = "https://mlbpark.donga.com"
    private let session: URLSession
    private var warmupTask: Task<Void, Never>? = nil
    private var lastWarmupDate: Date = .distantPast

    // CP949 (= Windows-949 = kCFStringEncodingDOSKorean = 0x0422)
    // String(data:encoding:) 경로는 NSStringEncoding 변환 레이어를 거쳐 간헐적으로 실패함
    // (Swift Forums #53109). CFStringCreateWithBytes 직접 호출이 iOS에서 가장 안정적.
    nonisolated static func decodeCP949(_ data: Data) -> String? {
        data.withUnsafeBytes { ptr -> String? in
            guard let base = ptr.bindMemory(to: UInt8.self).baseAddress else { return nil }
            guard let cf = CFStringCreateWithBytes(
                kCFAllocatorDefault, base, data.count,
                CFStringEncoding(0x0422), false   // kCFStringEncodingDOSKorean
            ) else { return nil }
            return cf as String
        }
    }

    nonisolated static func decodeServerText(_ data: Data, response: URLResponse?) -> String? {
        let declaredCharset = extractDeclaredCharset(data: data, response: response)

        if let charset = declaredCharset, legacyKoreanCharsets.contains(charset) {
            return decodeCP949(data) ?? String(decoding: data, as: UTF8.self)
        }

        if let charset = declaredCharset, utf8Charsets.contains(charset) {
            // 엠팍이 UTF-8 헤더를 보내도 간헐적으로 깨진 바이트가 섞인다.
            return String(data: data, encoding: .utf8) ?? String(decoding: data, as: UTF8.self)
        }

        return String(data: data, encoding: .utf8)
            ?? decodeCP949(data)
            ?? String(decoding: data, as: UTF8.self)
    }

    nonisolated private static func extractDeclaredCharset(data: Data, response: URLResponse?) -> String? {
        if let contentType = (response as? HTTPURLResponse)?.value(forHTTPHeaderField: "Content-Type"),
           let headerCharset = extractCharset(from: contentType) {
            return headerCharset
        }

        let head = String(decoding: data.prefix(4096), as: UTF8.self)
        return extractCharset(from: head)
    }

    nonisolated private static func extractCharset(from rawValue: String) -> String? {
        let lowercased = rawValue.lowercased()
        guard let range = lowercased.range(of: "charset=") else { return nil }

        let tail = lowercased[range.upperBound...]
        let trimmed = tail.drop(while: { $0 == " " || $0 == "\t" || $0 == "\r" || $0 == "\n" || $0 == "\"" || $0 == "'" })
        let allowed = Set("abcdefghijklmnopqrstuvwxyz0123456789-_")
        let charset = trimmed.prefix { allowed.contains($0) }

        guard !charset.isEmpty else { return nil }
        return String(charset)
    }

    private init() {
        let config = URLSessionConfiguration.default
        config.httpCookieStorage = HTTPCookieStorage.shared
        config.httpShouldSetCookies = true
        config.httpCookieAcceptPolicy = .always
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.urlCache = nil
        let s = URLSession(configuration: config)
        session = s
        // 앱 시작 즉시 warmup → 첫 게시판 로드 지연 최소화
        // httpShouldHandleCookies = false: 저장된 auth 쿠키(.donga.com)를 gather에 보내지 않음
        // → 로그인 상태에서 gather 서버의 불필요한 인증 처리를 방지해 응답 속도 개선
        warmupTask = Self.makeWarmupTask(session: s)
        lastWarmupDate = Date()
    }

    // 포그라운드 복귀 시 호출 — 30분 이상 지났을 때만 세션 재워밍
    func resetWarmup() {
        guard Date().timeIntervalSince(lastWarmupDate) > 1800 else { return }
        lastWarmupDate = Date()
        warmupTask?.cancel()
        warmupTask = Self.makeWarmupTask(session: session)
    }

    // gather 쿠키 갱신 + mlbpark 세션 ping 동시 실행
    nonisolated private static func makeWarmupTask(session: URLSession) -> Task<Void, Never> {
        Task {
            async let gather: Void = gatherWarmup(session: session)
            async let ping: Void   = sessionPing(session: session)
            _ = await (gather, ping)
        }
    }

    nonisolated private static func gatherWarmup(session: URLSession) async {
        guard let url = URL(string: "https://gather.donga.com/?cookie=1") else { return }
        var req = URLRequest(url: url)
        req.timeoutInterval = 5
        req.httpShouldHandleCookies = false
        req.setValue("https://mlbpark.donga.com/", forHTTPHeaderField: "Referer")
        guard let result = try? await session.data(for: req),
              let httpResp = result.1 as? HTTPURLResponse else { return }
        var fields: [String: String] = [:]
        for (key, value) in httpResp.allHeaderFields {
            if let k = key as? String, let v = value as? String { fields[k] = v }
        }
        HTTPCookie.cookies(withResponseHeaderFields: fields, for: url)
            .forEach { HTTPCookieStorage.shared.setCookie($0) }
    }

    // mlbpark 세션 쿠키를 서버에 전송해 서버 측 세션 TTL 갱신
    // 만료된 세션이라면 이 요청이 "첫 느린 요청"을 대신 부담 → 이후 fetchPosts는 워밍된 세션으로 빠르게 응답
    nonisolated private static func sessionPing(session: URLSession) async {
        guard let url = URL(string: "https://mlbpark.donga.com/mp/") else { return }
        var req = URLRequest(url: url)
        req.timeoutInterval = 8
        req.setValue("Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36", forHTTPHeaderField: "User-Agent")
        _ = try? await session.data(for: req)
    }

    private func performRequest(_ req: URLRequest) async throws -> (Data, URLResponse) {
        try await session.data(for: req)
    }

    // gather.donga.com 쿠키 없으면 mlbpark이 테이블 없는 JS 페이지만 반환
    // Task? 패턴: 동시 요청 시 모든 호출자가 같은 warmup Task를 await → 완료 보장
    private func warmupIfNeeded() async {
        await warmupTask?.value
    }

    // MARK: - 공통 요청

    /// AuthService 등 외부에서 warmup+인코딩 처리된 HTML이 필요할 때 사용
    func fetchHTML(_ urlStr: String) async throws -> String {
        return try await fetch(urlStr)
    }

    private func fetch(_ urlStr: String) async throws -> String {
        await warmupIfNeeded()
        guard let url = URL(string: urlStr) else { throw MLBParkError.invalidURL }
        var req = URLRequest(url: url)
        req.cachePolicy = .reloadIgnoringLocalCacheData
        req.setValue("Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36", forHTTPHeaderField: "User-Agent")
        req.setValue(base, forHTTPHeaderField: "Referer")
        req.setValue("ko-KR,ko;q=0.9", forHTTPHeaderField: "Accept-Language")
        req.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
        req.setValue("no-cache", forHTTPHeaderField: "Pragma")
        let (data, response) = try await performRequest(req)
        guard let result = Self.decodeServerText(data, response: response) else {
            throw MLBParkError.encodingError
        }
        return result
    }

    // MARK: - KBO 라이브스코어

    func fetchKboScores() async throws -> [KboGame] {
        let kboBase = "https://www.koreabaseball.com"
        guard let url = URL(string: "\(kboBase)/Schedule/ScoreBoard.aspx") else {
            throw MLBParkError.invalidURL
        }
        var req = URLRequest(url: url)
        req.cachePolicy = .reloadIgnoringLocalCacheData
        req.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1", forHTTPHeaderField: "User-Agent")
        req.setValue(kboBase, forHTTPHeaderField: "Referer")
        req.setValue("ko-KR,ko;q=0.9", forHTTPHeaderField: "Accept-Language")
        let (data, response) = try await performRequest(req)
        guard let html = Self.decodeServerText(data, response: response) else {
            throw MLBParkError.encodingError
        }

        let doc = try SwiftSoup.parse(html)
        let today = Self.kstDateString()
        let rows = try doc.select(".smsScore")
        guard !rows.isEmpty() else { return [] }

        return try rows.array().compactMap { row -> KboGame? in
            let awayName  = try row.select(".leftTeam .teamT").first()?.text() ?? ""
            let awayLogo  = try row.select(".leftTeam .team img").first()?.attr("src") ?? ""
            let awayScore = try row.select(".leftTeam .score span").first()?.text() ?? "-"
            let homeName  = try row.select(".rightTeam .teamT").first()?.text() ?? ""
            let homeLogo  = try row.select(".rightTeam .team img").first()?.attr("src") ?? ""
            let homeScore = try row.select(".rightTeam .score span").first()?.text() ?? "-"
            let inning    = try row.select(".flag span").first()?.text() ?? ""
            let place     = try row.select(".place").first()?.text() ?? ""

            guard !awayName.isEmpty, !homeName.isEmpty else { return nil }

            let isLive = inning != "경기종료" && inning != "경기예정" && !inning.isEmpty

            // BSO + 베이스 (라이브 중에만 유효)
            var outs = -1; var balls = -1; var strikes = -1
            var base1 = false; var base2 = false; var base3 = false
            if isLive {
                base1 = (try? row.select(".base1 img").first()?.attr("src"))?.contains("base_on") ?? false
                base2 = (try? row.select(".base2 img").first()?.attr("src"))?.contains("base_on") ?? false
                base3 = (try? row.select(".base3 img").first()?.attr("src"))?.contains("base_on") ?? false
                // ".base p" 텍스트: "3-2 2out" 형식
                if let bsoText = try? row.select(".base p").first()?.text() {
                    // 아웃 수: span 안 숫자
                    if let outStr = try? row.select(".base p span").first()?.text() {
                        outs = Int(outStr) ?? -1
                    }
                    // 볼-스트라이크: "3-2" 부분
                    let bsoPart = bsoText.components(separatedBy: " ").first ?? ""
                    let bsParts = bsoPart.components(separatedBy: "-")
                    if bsParts.count == 2 {
                        balls   = Int(bsParts[0]) ?? -1
                        strikes = Int(bsParts[1]) ?? -1
                    }
                }
            }

            // ".place" 텍스트: "잠실 18:30" → 구장명 + 시각 분리
            let placeParts = place.components(separatedBy: " ")
            let locationName = placeParts.first ?? place
            let gameTime = placeParts.count >= 2 ? placeParts.last ?? "" : ""

            let logoPrefix = "https:"
            return KboGame(
                id: "\(awayName)_\(homeName)_\(today)",
                isLive: isLive,
                inning: inning,
                location: locationName,
                gameTime: gameTime,
                home: KboTeamScore(name: homeName, logoURL: homeLogo.hasPrefix("//") ? logoPrefix + homeLogo : homeLogo, score: homeScore),
                away: KboTeamScore(name: awayName, logoURL: awayLogo.hasPrefix("//") ? logoPrefix + awayLogo : awayLogo, score: awayScore),
                outs: outs, balls: balls, strikes: strikes,
                base1: base1, base2: base2, base3: base3
            )
        }
    }

    private static func kstDateString() -> String {
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyyMMdd"
        fmt.timeZone = TimeZone(identifier: "Asia/Seoul")
        return fmt.string(from: Date())
    }

    // MARK: - 게시글 목록

    func fetchPosts(boardId: String, page: Int = 1) async throws -> [Post] {
        let html = try await fetch("\(base)/mp/b.php?b=\(boardId)&p=\(listOffset(for: page))")
        // 첫 페이지 응답에서 로그인 상태 파싱 → fetchProfile() 별도 요청 불필요
        if page == 1 { Task { @MainActor in AuthService.shared.updateLoginState(from: html) } }
        return try parsePostList(html: html, boardId: boardId)
    }

    /// 키워드 검색 (select: stt=제목, sct=제목+내용, swt=닉네임)
    func fetchPostsByKeyword(boardId: String, keyword: String, select: String = "stt", page: Int = 1) async throws -> [Post] {
        // 검색 쿼리는 UTF-8 퍼센트 인코딩 (서버가 검색 API에서 UTF-8 기대)
        let encoded = keyword.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? keyword
        let urlStr = "\(base)/mp/b.php?b=\(boardId)&m=search&select=\(select)&query=\(encoded)&p=\(listOffset(for: page))"
        let html = try await fetch(urlStr)
        return try parsePostList(html: html, boardId: boardId, isSearch: true)
    }

    /// 말머리 필터 (서버사이드 검색 API 사용)
    func fetchPostsByMaemuri(boardId: String, maemuri: String, page: Int = 1) async throws -> [Post] {
        let encoded = maemuri.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? maemuri
        let urlStr = "\(base)/mp/b.php?search_select=sct&search_input=&select=spf&m=search&b=\(boardId)&query=\(encoded)&p=\(listOffset(for: page))"
        let html = try await fetch(urlStr)
        return try parsePostList(html: html, boardId: boardId, isSearch: true)
    }

    private func parsePostList(html: String, boardId: String, isSearch: Bool = false) throws -> [Post] {
        let doc = try SwiftSoup.parse(html)
        var posts: [Post] = []

        // 일반목록: td[0]=번호(숫자 5자리↑), td[1]=말머리+제목, td[2]=작성자, td[3]=날짜, td[4]=조회수
        // 검색결과: td[0]=게시판명(문자열),   td[1]=말머리+제목, td[2]=작성자, td[3]=날짜, td[4]=조회수
        let rows = try doc.select("table tr")
        for row in rows {
            let tds = try row.select("td")
            guard tds.size() >= 4 else { continue }

            // 광고 행 스킵: row/td class에 ad 관련 키워드 포함
            let rowClass = (try? row.attr("class")) ?? ""
            guard !rowClass.contains("ad") && !rowClass.contains("banner") else { continue }
            // colspan이 있으면 광고/공지 배너 행
            let firstTdColspan = (try? tds.get(0).attr("colspan")) ?? ""
            guard firstTdColspan.isEmpty else { continue }

            let firstTd = try tds.get(0).text().trimmingCharacters(in: .whitespaces)

            // 공지 배너 행 명시적 스킵 (WBC 이벤트 등)
            guard firstTd != "공지" else { continue }

            // 건의사항 관리자 답변 행: td[0]="└" (U+2514 = &#9492;)
            // SwiftSoup이 HTML entity를 text()에서 디코딩 안 할 수도 있으므로 3중 체크
            let firstTdHtml = (try? tds.get(0).html()) ?? ""
            let isReplyRow = firstTd == "└"
                          || firstTdHtml.contains("9492")
                          || (firstTd.count == 1 && !(firstTd.first?.isNumber ?? true))

            if isSearch {
                // 헤더 행("게시판") 및 빈 행 제외
                guard !firstTd.isEmpty, firstTd != "게시판" else { continue }
            } else {
                // 글번호가 숫자 5자리 이상인 행 또는 관리자 답변 행(└)
                guard (firstTd.allSatisfy({ $0.isNumber }) && firstTd.count >= 5) || isReplyRow else { continue }
            }

            let titleTd = tds.get(1)

            // 말머리: a.list_word (답변 행은 "└" 표시)
            let maemuri = isReplyRow ? "└" : (try titleTd.select("a.list_word").first()?.text() ?? "")

            // 제목: a.txt (답변행은 a.txt 없을 수 있으므로 a 폴백)
            let titleLink: Element?
            if isReplyRow {
                titleLink = try titleTd.select("a.txt").first() ?? titleTd.select("a").first()
            } else {
                titleLink = try titleTd.select("a.txt").first()
            }
            guard let titleLink else { continue }
            let title = try titleLink.text().trimmingCharacters(in: .whitespacesAndNewlines)
            guard !title.isEmpty else { continue }
            let href  = try titleLink.attr("href")
            guard let postId = extractParam("id", from: href) else { continue }
            let postBoardId = extractParam("b", from: href) ?? boardId

            // 댓글수: a.replycnt → "[8]" → 8
            let replyRaw     = try titleTd.select("a.replycnt").first()?.text() ?? "[0]"
            let commentCount = Int(replyRaw.filter { $0.isNumber }) ?? 0

            let authorTd  = tds.get(2)
            let author    = try authorTd.select("span.nick").first()?.text() ?? authorTd.text()
            let avatarUrl = try authorTd.select("span.photo img").first()?.attr("src") ?? ""
            let date      = try tds.get(3).select("span.date").first()?.text() ?? tds.get(3).text()
            let views     = Int(try tds.get(4).select("span.viewV").first()?.text() ?? "0") ?? 0

            posts.append(Post(
                id: postId, boardId: postBoardId, maemuri: maemuri,
                title: title, author: author, avatarUrl: avatarUrl,
                date: date, views: views, commentCount: commentCount,
                recommendCount: 0
            ))
        }
        return posts
    }

    // MARK: - 베스트글

    /// best.php?b={boardId}&m=like|reply|view → 10개 목록
    func fetchBestPosts(boardId: String, type: String) async throws -> [Post] {
        let html = try await fetch("\(base)/mp/best.php?b=\(boardId)&m=\(type)")
        return try parseBestPosts(html: html, boardId: boardId)
    }

    private func parseBestPosts(html: String, boardId: String) throws -> [Post] {
        let doc = try SwiftSoup.parse(html)
        var posts: [Post] = []
        let rows = try doc.select("table tr")
        for row in rows {
            let tds = try row.select("td")
            guard tds.size() >= 3 else { continue }
            let rank = try tds.get(0).text().trimmingCharacters(in: .whitespaces)
            guard !rank.isEmpty, rank.allSatisfy({ $0.isNumber }) else { continue }
            guard let titleLink = try tds.get(1).select("a.txt").first() else { continue }
            let title  = try titleLink.text()
            let href   = try titleLink.attr("href")
            guard let postId = extractParam("id", from: href) else { continue }
            let author = try tds.get(2).select("span.nick").first()?.text() ?? tds.get(2).text()
            let date   = tds.size() > 3
                ? (try tds.get(3).select("span.date").first()?.text() ?? tds.get(3).text())
                : ""
            posts.append(Post(
                id: postId, boardId: boardId, maemuri: "",
                title: title, author: author,
                date: date, views: 0, commentCount: 0, recommendCount: 0
            ))
        }
        return posts
    }

    // MARK: - 게시글 상세

    func fetchPostDetail(boardId: String, postId: String) async throws -> PostDetail {
        let html = try await fetch("\(base)/mp/b.php?b=\(boardId)&id=\(postId)&m=view")
        return try parsePostDetail(html: html, boardId: boardId, postId: postId)
    }

    private func parsePostDetail(html: String, boardId: String, postId: String) throws -> PostDetail {
        let doc = try SwiftSoup.parse(html)

        // 말머리: div.titles > a > span.word
        let titleEl = try doc.select("div.titles").first()
        let maemuri = try titleEl?.select("span.word").first()?.text() ?? ""

        // 제목: div.titles 전체 텍스트에서 말머리 제거
        let titleFull = try titleEl?.text() ?? ""
        let title = maemuri.isEmpty ? titleFull
            : titleFull.replacingOccurrences(of: maemuri, with: "").trimmingCharacters(in: .whitespacesAndNewlines)

        // 작성자: div.text1 span.nick (닉네임), ul.view_head span.photo img (프로필)
        // div.text1 안의 img는 배지 아이콘이므로 ul.view_head에서 프로필 이미지 가져옴
        let author       = try doc.select("div.text1 span.nick").first()?.text() ?? ""
        let authorAvatar = try doc.select("ul.view_head span.photo img").first()?.attr("src") ?? ""

        // 날짜: div.text3 span.val
        let date = try doc.select("div.text3 span.val").first()?.text() ?? ""

        // 추천/조회/댓글: div.text2 span.val (3개)
        let vals      = try doc.select("div.text2 span.val")
        let recommend = vals.count > 0 ? (Int(try vals.get(0).text()) ?? 0) : 0
        let views     = vals.count > 1 ? (Int(try vals.get(1).text()) ?? 0) : 0
        let commentCount = vals.count > 2 ? (Int(try vals.get(2).text()) ?? 0) : 0

        // 본문: div.ar_txt (사이드바/광고 제외한 순수 본문)
        // 프로토콜 없는 //youtube... src를 https://youtube...로 보정
        var contentHTML = try doc.select("div.ar_txt").first()?.html() ?? ""
        contentHTML = contentHTML.replacingOccurrences(
            of: "src=\"//", with: "src=\"https://", options: .caseInsensitive
        )

        // 댓글: reply row(div#reply_{seq}) 기준으로 파싱
        // 내 댓글은 my_con/my_reply, 타인 댓글은 other_con/other_reply 변형이 있어
        // row 단위로 잡아야 누락이 없다.
        struct FlatComment {
            var comment: Comment
            var isNested: Bool      // replied or replied_re = 대댓글
            var isRepliedRe: Bool   // replied_re = 답글의 답글 (replyPrid → 부모 replied seq)
        }
        var flatList: [FlatComment] = []
        let commentRows = try doc.select(".reply_list div[id^=reply_]")
        for (i, row) in commentRows.enumerated() {
            guard let bodyEl = try row.select(".other_reply, .my_reply").first() else { continue }

            let nick   = try bodyEl.select("span.name").first()?.text() ?? ""
            guard !nick.isEmpty else { continue }
            let avatar = try row.select("span.photo img").first()?.attr("src") ?? ""
            let cDate  = try bodyEl.select("span.date").first()?.text() ?? ""
            let ip     = try bodyEl.select("span.ip").first()?.text() ?? ""

            // 대댓글 대상 닉네임: re_txt 내 span.name_re
            let reTxtEl = try bodyEl.select("span.re_txt").first()
            let replyToAuthor = try reTxtEl?.select("span.name_re").first()?.text() ?? ""
            // name_re 제거 후 순수 텍스트 추출
            try reTxtEl?.select("span.name_re").remove()
            let text = try reTxtEl?.text() ?? ""

            // seq: row id = "reply_{seq}"
            let rowId = (try? row.attr("id")) ?? ""
            let seq   = rowId.hasPrefix("reply_") ? String(rowId.dropFirst(6)) : ""

            // 내 댓글 여부: btn_edit/btn_redel 존재 여부로 판단 (my_con은 무관)
            let rowCls  = (try? row.attr("class")) ?? ""
            let bodyCls = (try? bodyEl.attr("class")) ?? ""
            let isOwn   = (try? row.select("a.btn_edit").first()) != nil
                       || (try? row.select("a.btn_redel").first()) != nil

            // 대댓글 여부: replied(직접 답글) 또는 replied_re(답글의 답글)
            // — replied: replyPrid == own seq (DOM 순서상 이전 최상위 댓글의 자식)
            // — replied_re: replyPrid == 부모 replied 항목의 seq
            let isReplied   = rowCls.contains("replied")    || bodyCls.contains("replied")
            let isNested    = isReplied

            // 웹은 viewReply(idClass, prid, source)로 댓글 팝업을 연다.
            // 답댓글 등록은 이 prid/source 조합을 그대로 action.php에 넘겨야 한다.
            let replyTargets = extractReplyTargets(from: row, fallbackSeq: seq)
            let replyPrid = replyTargets.prid
            let replySource = replyTargets.source

            let isRepliedRe = rowCls.contains("replied_re") || bodyCls.contains("replied_re")
            let depth = isRepliedRe ? 2 : (isNested ? 1 : 0)
            let c = Comment(
                id: "\(postId)_c\(i)", seq: seq,
                replyPrid: replyPrid, replySource: replySource,
                author: nick, avatarUrl: avatar,
                date: cDate, ip: ip, content: text, isOwn: isOwn,
                replyToAuthor: replyToAuthor, depth: depth
            )
            flatList.append(FlatComment(comment: c, isNested: isNested, isRepliedRe: isRepliedRe))
        }

        // 계층 구조 빌드
        // — replied: 바로 이전 최상위 댓글의 자식 (replyPrid == own seq이라 부모 특정 불가 → 마지막 top에 추가)
        // — replied_re: replyPrid가 부모 replied 항목의 seq → 해당 replied가 속한 top-level에 추가
        var topLevel: [Comment] = []
        for flat in flatList {
            if !flat.isNested {
                topLevel.append(flat.comment)
            } else if flat.isRepliedRe {
                // replyPrid → replied 항목을 보유한 top-level 찾기
                if let tlIdx = topLevel.firstIndex(where: {
                    $0.seq == flat.comment.replyPrid ||
                    $0.replies.contains(where: { $0.seq == flat.comment.replyPrid })
                }) {
                    topLevel[tlIdx].replies.append(flat.comment)
                } else if !topLevel.isEmpty {
                    topLevel[topLevel.count - 1].replies.append(flat.comment)
                }
            } else {
                // replied: 마지막 top-level의 replies에 추가
                if !topLevel.isEmpty {
                    topLevel[topLevel.count - 1].replies.append(flat.comment)
                } else {
                    topLevel.append(flat.comment)
                }
            }
        }
        let comments = topLevel

        return PostDetail(
            id: postId,
            boardId: boardId,
            maemuri: maemuri,
            title: title,
            author: author,
            avatarUrl: authorAvatar,
            date: date,
            views: views,
            commentCount: flatList.count > 0 ? flatList.count : commentCount,
            recommendCount: recommend,
            contentHTML: contentHTML,
            comments: comments
        )
    }

    // MARK: - 글쓰기

    func writePost(boardId: String, categoryId: String, title: String, content: String) async throws {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedContent = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty, !trimmedContent.isEmpty else {
            throw MLBParkError.networkError("제목과 내용을 입력해주세요.")
        }

        await warmupIfNeeded()
        guard let url = URL(string: "\(base)/mp/action.php") else { throw MLBParkError.invalidURL }

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded; charset=UTF-8", forHTTPHeaderField: "Content-Type")
        req.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 17_0)", forHTTPHeaderField: "User-Agent")
        req.setValue("\(base)/mp/b.php?b=\(boardId)&m=write", forHTTPHeaderField: "Referer")
        req.setValue("XMLHttpRequest", forHTTPHeaderField: "X-Requested-With")

        let info = buildPostInfo(boardId: boardId, categoryId: categoryId, upimg: "")
        req.httpBody = buildUTF8Form([
            "b":        boardId,
            "m":        "board_INSERT",
            "id":       "",
            "category": categoryId,
            "subject":  trimmedTitle,
            "content":  trimmedContent,
            "upimg":    "",
            "info":     info,
        ])

        let (data, resp) = try await performRequest(req)
        if let http = resp as? HTTPURLResponse, http.statusCode >= 400 {
            throw MLBParkError.networkError("HTTP \(http.statusCode)")
        }

        if let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let status = obj["status"] as? String {
            guard status == "ok" else {
                throw MLBParkError.networkError("게시글 등록 실패(\(status))")
            }
            return
        }

        let raw = Self.decodeServerText(data, response: resp)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if raw.isEmpty {
            throw MLBParkError.networkError("게시글 등록 실패(빈 응답)")
        }
        throw MLBParkError.networkError("게시글 등록 실패(\(raw))")
    }

    // MARK: - 댓글쓰기

    func writeComment(boardId: String, postId: String, content: String,
                      parentPrid: String = "", parentSeq: String = "") async throws {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw MLBParkError.networkError("댓글 내용을 입력해주세요.")
        }
        guard trimmed.count <= 300 else {
            throw MLBParkError.networkError("댓글은 300자 이하로 입력해주세요.")
        }

        guard let url = URL(string: "\(base)/mp/action.php") else { throw MLBParkError.invalidURL }

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        // 댓글은 웹의 serialize() 동작과 맞춰 UTF-8 폼 인코딩으로 전송
        req.setValue("application/x-www-form-urlencoded; charset=UTF-8", forHTTPHeaderField: "Content-Type")
        req.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 17_0)", forHTTPHeaderField: "User-Agent")
        req.setValue("\(base)/mp/b.php?b=\(boardId)&id=\(postId)&m=view", forHTTPHeaderField: "Referer")
        req.setValue("XMLHttpRequest", forHTTPHeaderField: "X-Requested-With")

        req.httpBody = buildUTF8Form([
            "m":       "reply_INSERT",
            "b":       boardId,
            "id":      postId,
            "prid":    parentPrid,
            "source":  parentSeq,
            "info":    "{\"replyId\":\"\"}",
            "content": trimmed,
        ])

        let (data, resp) = try await performRequest(req)
        if let http = resp as? HTTPURLResponse, http.statusCode >= 400 {
            throw MLBParkError.networkError("HTTP \(http.statusCode)")
        }

        let result = Self.decodeServerText(data, response: resp)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        switch result {
        case "ok":
            return
        case "notfound":
            throw MLBParkError.networkError("존재하지 않는 게시물입니다.")
        case "nologin":
            throw MLBParkError.networkError("로그인 후 이용해주세요.")
        case "reallogin":
            throw MLBParkError.networkError("2군 회원은 댓글 작성이 제한됩니다.")
        case "null":
            throw MLBParkError.networkError("댓글 내용을 입력해주세요.")
        case "deleted":
            throw MLBParkError.networkError("기기 시간을 현재 시간으로 맞춘 후 다시 시도해주세요.")
        case "permission":
            throw MLBParkError.networkError("댓글 작성 권한이 없습니다.")
        case "lowlevel":
            throw MLBParkError.networkError("회원 가입 후 7일이 지나야 댓글 작성이 가능합니다.")
        case "over":
            throw MLBParkError.networkError("동일한 내용의 댓글은 등록할 수 없습니다.")
        case "fail":
            throw MLBParkError.networkError("댓글 등록 중 오류가 발생했습니다.")
        case "ip":
            throw MLBParkError.networkError("해당 아이피는 차단된 상태입니다.")
        case "rpDeleted":
            throw MLBParkError.networkError("이미 삭제된 댓글입니다.")
        case "rpMaxdepth":
            throw MLBParkError.networkError("댓글은 최대 3단계까지만 작성할 수 있습니다.")
        case "rpMaxLength":
            throw MLBParkError.networkError("댓글 글자 수 제한(300자)을 초과했습니다.")
        case "rpNotFound":
            throw MLBParkError.networkError("대상 댓글을 찾을 수 없습니다.")
        case "":
            throw MLBParkError.networkError("댓글 등록 실패(빈 응답).")
        default:
            // 금칙어 응답은 해당 단어 문자열이 그대로 내려온다.
            throw MLBParkError.networkError("댓글 등록 실패: \(result)")
        }
    }

    // MARK: - 댓글 삭제 (게시글 상세)

    func deleteComment(boardId: String, postId: String, commentSeq: String) async throws {
        guard let url = URL(string: "\(base)/mp/action.php") else { throw MLBParkError.invalidURL }

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded; charset=EUC-KR", forHTTPHeaderField: "Content-Type")
        req.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 17_0)", forHTTPHeaderField: "User-Agent")
        req.setValue("\(base)/mp/b.php?b=\(boardId)&id=\(postId)&m=view", forHTTPHeaderField: "Referer")
        req.setValue("XMLHttpRequest", forHTTPHeaderField: "X-Requested-With")

        req.httpBody = buildCP949Form([
            "m":    "reply_DELETE",
            "b":    boardId,
            "id":   postId,
            "info": "{\"replyId\":\"\(commentSeq)\"}",
        ])

        let (data, resp) = try await performRequest(req)
        if let http = resp as? HTTPURLResponse, http.statusCode >= 400 {
            throw MLBParkError.networkError("HTTP \(http.statusCode)")
        }
        let body = Self.decodeServerText(data, response: resp) ?? ""
        if body.contains("nologin") || body.contains("error") || body.contains("fail") {
            throw MLBParkError.networkError("댓글 삭제 실패")
        }
    }

    // MARK: - 댓글 수정 (게시글 상세)

    func editComment(boardId: String, postId: String, commentSeq: String, content: String) async throws {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw MLBParkError.networkError("댓글 내용을 입력해주세요.")
        }
        guard trimmed.count <= 300 else {
            throw MLBParkError.networkError("댓글은 300자 이하로 입력해주세요.")
        }
        guard !commentSeq.isEmpty else {
            throw MLBParkError.networkError("수정할 댓글 식별값이 비어 있습니다. 새로고침 후 다시 시도해주세요.")
        }

        guard let url = URL(string: "\(base)/mp/action.php") else { throw MLBParkError.invalidURL }

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        // 웹 수정 폼 serialize()와 동일하게 UTF-8 전송
        req.setValue("application/x-www-form-urlencoded; charset=UTF-8", forHTTPHeaderField: "Content-Type")
        req.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 17_0)", forHTTPHeaderField: "User-Agent")
        req.setValue("\(base)/mp/b.php?b=\(boardId)&id=\(postId)&m=view", forHTTPHeaderField: "Referer")
        req.setValue("XMLHttpRequest", forHTTPHeaderField: "X-Requested-With")

        req.httpBody = buildUTF8Form([
            "m":       "reply_UPDATE",
            "b":       boardId,
            "id":      postId,
            "prid":    "",
            "source":  "",
            "info":    "{\"replyId\":\"\(commentSeq)\"}",
            "content": trimmed,
        ])

        let (data, resp) = try await performRequest(req)
        if let http = resp as? HTTPURLResponse, http.statusCode >= 400 {
            throw MLBParkError.networkError("HTTP \(http.statusCode)")
        }

        let result = Self.decodeServerText(data, response: resp)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        switch result {
        case "ok":
            return
        case "notfound":
            throw MLBParkError.networkError("존재하지 않는 게시물입니다.")
        case "nologin":
            throw MLBParkError.networkError("로그인 후 이용해주세요.")
        case "reallogin":
            throw MLBParkError.networkError("2군 회원은 댓글 수정이 제한됩니다.")
        case "null":
            throw MLBParkError.networkError("댓글 내용을 입력해주세요.")
        case "deleted":
            throw MLBParkError.networkError("기기 시간을 현재 시간으로 맞춘 후 다시 시도해주세요.")
        case "permission":
            throw MLBParkError.networkError("댓글 수정 권한이 없습니다.")
        case "lowlevel":
            throw MLBParkError.networkError("회원 가입 후 7일이 지나야 댓글 수정이 가능합니다.")
        case "over":
            throw MLBParkError.networkError("동일한 내용의 댓글은 등록할 수 없습니다.")
        case "fail":
            throw MLBParkError.networkError("댓글 수정 중 오류가 발생했습니다.")
        case "ip":
            throw MLBParkError.networkError("해당 아이피는 차단된 상태입니다.")
        case "rpDeleted":
            throw MLBParkError.networkError("이미 삭제된 댓글입니다.")
        case "rpMaxdepth":
            throw MLBParkError.networkError("댓글은 최대 3단계까지만 작성할 수 있습니다.")
        case "rpMaxLength":
            throw MLBParkError.networkError("댓글 글자 수 제한(300자)을 초과했습니다.")
        case "rpNotFound":
            throw MLBParkError.networkError("수정할 댓글을 찾을 수 없습니다.")
        case "":
            throw MLBParkError.networkError("댓글 수정 실패(빈 응답).")
        default:
            throw MLBParkError.networkError("댓글 수정 실패: \(result)")
        }
    }

    // MARK: - 게시글 삭제/수정 (게시글 상세)

    /// 게시글 삭제 (게시글 상세에서 호출 — action.php board_DELETE)
    func deletePost(boardId: String, postId: String) async throws {
        guard let url = URL(string: "\(base)/mp/action.php") else { throw MLBParkError.invalidURL }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        req.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 17_0)", forHTTPHeaderField: "User-Agent")
        req.setValue("\(base)/mp/b.php?b=\(boardId)&id=\(postId)&m=view", forHTTPHeaderField: "Referer")
        req.httpBody = "m=board_DELETE&b=\(boardId)&id=\(postId)&info=%7B%22notice%22%3A%22%22%7D"
            .data(using: .utf8)
        let (data, resp) = try await performRequest(req)
        if let http = resp as? HTTPURLResponse, http.statusCode >= 400 {
            throw MLBParkError.networkError("HTTP \(http.statusCode)")
        }
        let body = Self.decodeServerText(data, response: resp) ?? ""
        if body.contains("nologin") || body.contains("permission") || body.contains("error") {
            throw MLBParkError.networkError("게시글 삭제 실패. 로그인 상태를 확인하세요.")
        }
    }

    /// 게시글 수정 (게시글 상세에서 호출 — b.php board_UPDATE)
    func editPost(boardId: String, postId: String, categoryId: String,
                  title: String, content: String) async throws {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedContent = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty, !trimmedContent.isEmpty else {
            throw MLBParkError.networkError("제목과 내용을 입력해주세요.")
        }
        let prefill = (try? await fetchUpdateFormParams(boardId: boardId, postId: postId)) ?? [:]
        let effectiveCategory = categoryId.isEmpty ? (prefill["category"] ?? "") : categoryId
        guard !effectiveCategory.isEmpty else {
            throw MLBParkError.networkError("말머리 값(category)을 확인할 수 없습니다.")
        }

        guard let url = URL(string: "\(base)/mp/action.php") else { throw MLBParkError.invalidURL }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded; charset=UTF-8", forHTTPHeaderField: "Content-Type")
        req.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 17_0)", forHTTPHeaderField: "User-Agent")
        req.setValue("\(base)/mp/b.php?b=\(boardId)&id=\(postId)&m=update", forHTTPHeaderField: "Referer")
        req.setValue("XMLHttpRequest", forHTTPHeaderField: "X-Requested-With")

        let upimg = prefill["upimg"] ?? ""
        let info = buildPostInfo(boardId: boardId, categoryId: effectiveCategory, upimg: upimg)
        req.httpBody = buildUTF8Form([
            "b":        boardId,
            "m":        "board_UPDATE",
            "id":       postId,
            "category": effectiveCategory,
            "subject":  trimmedTitle,
            "content":  trimmedContent,
            "upimg":    upimg,
            "info":     info,
        ])

        let (data, resp) = try await performRequest(req)
        if let http = resp as? HTTPURLResponse, http.statusCode >= 400 {
            throw MLBParkError.networkError("HTTP \(http.statusCode)")
        }

        if let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let status = obj["status"] as? String {
            guard status == "ok" else {
                throw MLBParkError.networkError("게시글 수정 실패(\(status))")
            }
            return
        }

        let raw = Self.decodeServerText(data, response: resp)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if raw.isEmpty {
            throw MLBParkError.networkError("게시글 수정 실패(빈 응답)")
        }
        throw MLBParkError.networkError("게시글 수정 실패(\(raw))")
    }

    // MARK: - 더그아웃 (내게시글 / 내댓글)

    func fetchDugout(source: String, page: Int = 1) async throws -> [DugoutItem] {
        let html = try await fetch("\(base)/mp/dugout.php?source=\(source)&p=\(page)")
        return try parseDugout(html: html, isComment: source == "mycomment")
    }

    private func parseDugout(html: String, isComment: Bool) throws -> [DugoutItem] {
        let doc = try SwiftSoup.parse(html)
        var items: [DugoutItem] = []

        let rows = try doc.select("tr[id^=dugout_list_]")
        for row in rows {
            // row id = "dugout_list_{id}"
            let rowId = try row.attr("id").replacingOccurrences(of: "dugout_list_", with: "")
            guard !rowId.isEmpty else { continue }

            let tds = try row.select("td")
            guard tds.size() >= 4 else { continue }

            // 제목 td 내 두 번째 <a> = 제목 링크
            // (첫 번째 <a> 는 아바타 링크)
            let titleTd  = tds.get(0)
            let allLinks = try titleTd.select("a")
            guard allLinks.size() >= 2 else { continue }
            let titleLink = allLinks.get(1)

            let href         = try titleLink.attr("href")
            let boardId      = extractParam("b", from: href) ?? ""
            let originalPost = extractParam("id", from: href) ?? rowId
            guard !boardId.isEmpty else { continue }

            // 제목 텍스트: 링크의 직접 텍스트 (span.allim 제외)
            let title = try titleLink.text().trimmingCharacters(in: .whitespacesAndNewlines)
            guard !title.isEmpty else { continue }

            // 게시판 표시명: td[1]
            let boardName = try tds.get(1).text().trimmingCharacters(in: .whitespaces)

            // 날짜: td[3]
            let date = try tds.get(3).text().trimmingCharacters(in: .whitespaces)

            // 삭제용 data-id / data-sequence — 버튼 속성에서 직접 파싱
            let delBtn    = try row.select(".dugout_delete_item").first()
            let deleteId  = (try delBtn?.attr("data-id")) ?? rowId
            let deleteSeq = (try delBtn?.attr("data-sequence")) ?? ""

            items.append(DugoutItem(
                id: rowId,
                boardId: boardId,
                boardName: boardName,
                title: title,
                date: date,
                isComment: isComment,
                originalPostId: originalPost,
                deleteId: deleteId,
                deleteSeq: deleteSeq
            ))
        }
        return items
    }

    /// 더그아웃 항목 삭제 — 게시글/댓글 공통 (op.php deleteDugoutList)
    func deleteDugoutItem(itemId: String, seq: String) async throws {
        let urlStr = "\(base)/mp/op.php?id=\(itemId)&seq=\(seq)&p=1&l=30&m=deleteDugoutList"
        guard let url = URL(string: urlStr) else { throw MLBParkError.invalidURL }
        var req = URLRequest(url: url)
        req.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 17_0)", forHTTPHeaderField: "User-Agent")
        req.setValue("\(base)/mp/dugout.php", forHTTPHeaderField: "Referer")
        let (data, resp) = try await performRequest(req)
        if let http = resp as? HTTPURLResponse, http.statusCode >= 400 {
            throw MLBParkError.networkError("HTTP \(http.statusCode)")
        }
        let result = Self.decodeServerText(data, response: resp) ?? ""
        if result.contains("nologin") {
            throw MLBParkError.networkError("로그인이 필요합니다")
        }
    }

    // MARK: - 유틸

    /// 게시글 수정폼(m=update)의 기본 파라미터(category/upimg)를 회수한다.
    private func fetchUpdateFormParams(boardId: String, postId: String) async throws -> [String: String] {
        let updateURL = "\(base)/mp/b.php?b=\(boardId)&id=\(postId)&m=update"
        let html = try await fetch(updateURL)
        let doc = try SwiftSoup.parse(html)
        var params: [String: String] = [:]
        if let form = try doc.select("form#writeForm").first() {
            if let upimg = try form.select("input[name=upimg]").first()?.attr("value") {
                params["upimg"] = upimg
            }
            if let selected = try form.select("select[name=category] option[selected]").first()?.attr("value"),
               !selected.isEmpty, selected != "0" {
                params["category"] = selected
            }
        }
        return params
    }

    /// update 폼의 info와 동일한 JSON 문자열 생성
    private func buildPostInfo(boardId: String, categoryId: String, upimg: String) -> String {
        let obj: [String: String] = [
            "b": boardId,
            "category": categoryId,
            "upimg": upimg,
        ]
        if let data = try? JSONSerialization.data(withJSONObject: obj, options: []),
           let json = String(data: data, encoding: .utf8) {
            return json
        }
        return "{}"
    }

    private func extractParam(_ key: String, from path: String) -> String? {
        // /mp/b.php?... 형태(슬래시 시작 상대경로)는 base + path, 그 외 상대경로는 base/path
        let urlStr: String
        if path.hasPrefix("http") {
            urlStr = path
        } else if path.hasPrefix("/") {
            urlStr = "\(base)\(path)"
        } else {
            urlStr = "\(base)/\(path)"
        }
        guard let url = URL(string: urlStr),
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let item = components.queryItems?.first(where: { $0.name == key })
        else { return nil }
        return item.value
    }

    /// 댓글 row의 viewReply(prid, source) 값을 파싱한다.
    private func extractReplyTargets(from row: Element, fallbackSeq: String) -> (prid: String, source: String) {
        let selectors = ["a.btn_replied", ".txt_box .txt > a"]

        for selector in selectors {
            guard let target = try? row.select(selector).first(),
                  let onclick = try? target.attr("onclick"),
                  let parsed = parseViewReplyTargets(onclick)
            else { continue }

            let prid = parsed.prid.isEmpty ? fallbackSeq : parsed.prid
            let source = parsed.source.isEmpty ? fallbackSeq : parsed.source
            return (prid, source)
        }

        return (fallbackSeq, fallbackSeq)
    }

    /// onclick='return viewReply("reply_x", "123", "456")' 형태에서 prid/source를 회수한다.
    private func parseViewReplyTargets(_ onclick: String) -> (prid: String, source: String)? {
        let pattern = #"viewReply\("[^"]*",\s*"([^"]*)",\s*"([^"]*)"\)"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }

        let nsOnclick = onclick as NSString
        let fullRange = NSRange(location: 0, length: nsOnclick.length)
        guard let match = regex.firstMatch(in: onclick, options: [], range: fullRange),
              match.numberOfRanges >= 3
        else { return nil }

        let pridRange = match.range(at: 1)
        let sourceRange = match.range(at: 2)
        guard pridRange.location != NSNotFound, sourceRange.location != NSNotFound else { return nil }

        return (
            nsOnclick.substring(with: pridRange),
            nsOnclick.substring(with: sourceRange)
        )
    }

    /// 폼 파라미터를 CP949로 인코딩한 Data 반환 (한글 깨짐 방지)
    private func buildCP949Form(_ params: [String: String]) -> Data {
        // Dictionary.map 클로저는 (key, value) 튜플 하나를 받음 → 괄호 필수
        let body = params.map { (key, value) in
            let ek = key.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? key
            let ev = percentEncodeCP949(value)
            return "\(ek)=\(ev)"
        }.joined(separator: "&")
        return body.data(using: .ascii) ?? Data()
    }

    /// 문자열을 CP949 바이트로 변환 후 퍼센트 인코딩
    private func percentEncodeCP949(_ value: String) -> String {
        let cp949NS = String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(0x0422))
        guard let data = value.data(using: cp949NS) else {
            return value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? value
        }
        var result = ""
        for byte in data {
            // 안전한 ASCII 문자(alphanumeric + - . _ ~)는 그대로, 나머지는 퍼센트 인코딩
            switch byte {
            case 0x41...0x5A,  // A-Z
                 0x61...0x7A,  // a-z
                 0x30...0x39,  // 0-9
                 0x2D, 0x2E, 0x5F, 0x7E:  // - . _ ~
                result += String(bytes: [byte], encoding: .ascii) ?? ""
            default:
                result += String(format: "%%%02X", byte)
            }
        }
        return result
    }

    /// 폼 파라미터를 UTF-8 퍼센트 인코딩한 Data 반환
    private func buildUTF8Form(_ params: [String: String]) -> Data {
        let body = params.map { (key, value) in
            let ek = key.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? key
            let ev = value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? value
            return "\(ek)=\(ev)"
        }.joined(separator: "&")
        return body.data(using: .ascii) ?? Data()
    }

    /// MLBPark 목록/검색의 p는 페이지 번호가 아니라 1-based 시작 오프셋이다.
    private func listOffset(for page: Int) -> Int {
        let normalizedPage = max(page, 1)
        return ((normalizedPage - 1) * Self.listPageSize) + 1
    }

    // MARK: - Burning 위젯 (실시간/주간/월간)

    func fetchBurningWidget() async throws -> BurningData {
        let raw = try await fetch("\(base)/mp/api/getBurningWidget.php")
        return try parseBurningWidget(raw)
    }

    private func parseBurningWidget(_ raw: String) throws -> BurningData {
        guard let data = raw.data(using: .utf8),
              let arr = try? JSONSerialization.jsonObject(with: data) as? [Any],
              arr.count >= 2,
              let htmlStr = arr[1] as? String else {
            throw MLBParkError.parseError("burning widget JSON")
        }
        let doc = try SwiftSoup.parse(htmlStr)
        var result = BurningData()

        func posts(in divId: String, cls: String) throws -> [BurningPost] {
            guard let ul = try doc.select("div#\(divId) ul.lists.\(cls)").first() else { return [] }
            return try ul.select("li.items").compactMap { li -> BurningPost? in
                guard let a = try? li.select("a.title").first() else { return nil }
                let href   = (try? a.attr("href")) ?? ""
                guard let postId  = extractParam("id", from: href),
                      let boardId = extractParam("b",  from: href) else { return nil }
                let title  = ((try? a.select("span.txt").first()?.text()) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                guard !title.isEmpty else { return nil }
                let replyT = (try? a.select("span.replycont").first()?.text()) ?? ""
                let viewsT = (try? a.select("span.views").first()?.text()) ?? ""
                let reply  = Int(replyT.filter { $0.isNumber }) ?? 0
                let views  = Int(viewsT.filter { $0.isNumber }) ?? 0
                return BurningPost(id: postId, boardId: boardId, title: title, replyCount: reply, views: views)
            }
        }

        result.mlb.realtime = try posts(in: "burning_list_mlb",     cls: "realtime")
        result.mlb.weekly   = try posts(in: "burning_list_mlb",     cls: "weekly")
        result.mlb.monthly  = try posts(in: "burning_list_mlb",     cls: "monthly")
        result.kbo.realtime = try posts(in: "burning_list_kbo",     cls: "realtime")
        result.kbo.weekly   = try posts(in: "burning_list_kbo",     cls: "weekly")
        result.kbo.monthly  = try posts(in: "burning_list_kbo",     cls: "monthly")
        result.bullpen.realtime = try posts(in: "burning_list_bullpen", cls: "realtime")
        result.bullpen.weekly   = try posts(in: "burning_list_bullpen", cls: "weekly")
        result.bullpen.monthly  = try posts(in: "burning_list_bullpen", cls: "monthly")
        return result
    }
}
