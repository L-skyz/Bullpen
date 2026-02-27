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

@MainActor
class MLBParkService {
    static let shared = MLBParkService()

    private let base = "https://mlbpark.donga.com"
    private let session: URLSession

    private init() {
        let config = URLSessionConfiguration.default
        config.httpCookieStorage = HTTPCookieStorage.shared
        config.httpShouldSetCookies = true
        config.httpCookieAcceptPolicy = .always
        session = URLSession(configuration: config)
    }

    // MARK: - 공통 요청

    private func fetch(_ urlStr: String) async throws -> String {
        guard let url = URL(string: urlStr) else { throw MLBParkError.invalidURL }
        var req = URLRequest(url: url)
        req.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15", forHTTPHeaderField: "User-Agent")
        req.setValue(base, forHTTPHeaderField: "Referer")
        let (data, _) = try await session.data(for: req)
        guard let html = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) else {
            throw MLBParkError.encodingError
        }
        return html
    }

    // MARK: - 게시글 목록

    func fetchPosts(boardId: String, page: Int = 1) async throws -> [Post] {
        let html = try await fetch("\(base)/mp/b.php?b=\(boardId)&p=\(page)")
        return try parsePostList(html: html, boardId: boardId)
    }

    private func parsePostList(html: String, boardId: String) throws -> [Post] {
        let doc = try SwiftSoup.parse(html)
        var posts: [Post] = []

        // table tr 구조: td[0]=번호, td[1]=말머리+제목, td[2]=작성자, td[3]=날짜, td[4]=조회수
        let rows = try doc.select("table tr")
        for row in rows {
            let tds = try row.select("td")
            guard tds.size() >= 4 else { continue }

            // 첫번째 td가 숫자(글번호)인 행만 처리 (공지 제외)
            let numText = try tds.get(0).text().trimmingCharacters(in: .whitespaces)
            guard numText.allSatisfy({ $0.isNumber }), numText.count >= 5 else { continue }

            let titleTd = tds.get(1)

            // 말머리: a.list_word
            let maemuri = try titleTd.select("a.list_word").first()?.text() ?? ""

            // 제목: a.txt
            guard let titleLink = try titleTd.select("a.txt").first() else { continue }
            let title = try titleLink.text()
            let href  = try titleLink.attr("href")
            guard let postId = extractParam("id", from: href) else { continue }

            // 댓글수: a.replycnt → "[8]" → 8
            let replyRaw     = try titleTd.select("a.replycnt").first()?.text() ?? "[0]"
            let commentCount = Int(replyRaw.filter { $0.isNumber }) ?? 0

            let author = try tds.get(2).text()
            let date   = try tds.get(3).text()
            let views  = Int(try tds.get(4).text().filter { $0.isNumber }) ?? 0

            posts.append(Post(
                id: postId,
                boardId: boardId,
                maemuri: maemuri,
                title: title,
                author: author,
                date: date,
                views: views,
                commentCount: commentCount,
                recommendCount: 0
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

        let titleEl   = try doc.select("div.titles").first()
        let titleFull = try titleEl?.text() ?? ""

        // 말머리 (div.titles 안 span.mark 등)
        let maemuri   = try titleEl?.select("span.mark, span.label, em").first()?.text() ?? ""
        let title     = maemuri.isEmpty ? titleFull :
            titleFull.replacingOccurrences(of: maemuri, with: "")
                      .trimmingCharacters(in: .whitespacesAndNewlines)

        let author = try doc.select(".view_head .nick").first()?.text() ?? ""
        let date   = try doc.select(".view_head .text3 span.val").first()?.text() ?? ""

        // 추천/조회/댓글 수
        let vals         = try doc.select(".view_head .text2 span.val")
        let recommend    = vals.count > 0 ? (Int(try vals.get(0).text()) ?? 0) : 0
        let views        = vals.count > 1 ? (Int(try vals.get(1).text()) ?? 0) : 0
        let commentCount = vals.count > 2 ? (Int(try vals.get(2).text()) ?? 0) : 0

        let contentHTML = try doc.select("div.contents").first()?.html() ?? ""

        // 댓글
        var comments: [Comment] = []
        let commentEls = try doc.select(".reply_list .other_reply")
        for (i, el) in commentEls.enumerated() {
            let nick  = try el.select(".name").first()?.text() ?? ""
            let cDate = try el.select(".date").first()?.text() ?? ""
            let ip    = try el.select(".ip").first()?.text() ?? ""
            let text  = try el.select(".re_txt").first()?.text() ?? ""
            comments.append(Comment(id: "\(postId)_c\(i)", author: nick, date: cDate, ip: ip, content: text))
        }

        return PostDetail(
            id: postId,
            boardId: boardId,
            maemuri: maemuri,
            title: title,
            author: author,
            date: date,
            views: views,
            commentCount: commentCount,
            recommendCount: recommend,
            contentHTML: contentHTML,
            comments: comments
        )
    }

    // MARK: - 글쓰기

    func writePost(boardId: String, maemuri: String, title: String, content: String) async throws {
        guard let url = URL(string: "\(base)/mp/b.php") else { throw MLBParkError.invalidURL }

        // 글쓰기 폼 페이지에서 hidden 토큰 추출
        let formHTML = try await fetch("\(base)/mp/b.php?b=\(boardId)&m=write")
        let doc      = try SwiftSoup.parse(formHTML)
        let token    = try doc.select("input[name=_token], input[name=csrf]").first()?.val() ?? ""

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        req.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 17_0)", forHTTPHeaderField: "User-Agent")
        req.setValue("\(base)/mp/b.php?b=\(boardId)&m=write", forHTTPHeaderField: "Referer")

        var params: [String: String] = [
            "b":        boardId,
            "mode":     "write",
            "maemuri":  maemuri,
            "subject":  title,
            "content":  content,
        ]
        if !token.isEmpty { params["_token"] = token }
        req.httpBody = params.urlEncoded.data(using: .utf8)

        let (_, resp) = try await session.data(for: req)
        if let http = resp as? HTTPURLResponse, http.statusCode >= 400 {
            throw MLBParkError.networkError("HTTP \(http.statusCode)")
        }
    }

    // MARK: - 댓글쓰기

    func writeComment(boardId: String, postId: String, content: String) async throws {
        guard let url = URL(string: "\(base)/mp/b.php") else { throw MLBParkError.invalidURL }

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        req.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 17_0)", forHTTPHeaderField: "User-Agent")
        req.setValue("\(base)/mp/b.php?b=\(boardId)&id=\(postId)&m=view", forHTTPHeaderField: "Referer")

        let params: [String: String] = [
            "b":       boardId,
            "id":      postId,
            "mode":    "comment",
            "content": content,
        ]
        req.httpBody = params.urlEncoded.data(using: .utf8)

        let (_, resp) = try await session.data(for: req)
        if let http = resp as? HTTPURLResponse, http.statusCode >= 400 {
            throw MLBParkError.networkError("HTTP \(http.statusCode)")
        }
    }

    // MARK: - 유틸

    private func extractParam(_ key: String, from path: String) -> String? {
        let urlStr = path.hasPrefix("http") ? path : "\(base)/\(path)"
        guard let url = URL(string: urlStr),
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let item = components.queryItems?.first(where: { $0.name == key })
        else { return nil }
        return item.value
    }
}

extension Dictionary where Key == String, Value == String {
    var urlEncoded: String {
        map { k, v in
            let ek = k.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? k
            let ev = v.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? v
            return "\(ek)=\(ev)"
        }.joined(separator: "&")
    }
}
