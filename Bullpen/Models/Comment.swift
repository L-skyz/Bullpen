import Foundation

struct Comment: Identifiable {
    let id: String          // "\(postId)_c\(i)" — ForEach용 고유키
    let seq: String         // DOM id "reply_{seq}" → API 수정/삭제에 사용
    let author: String
    let avatarUrl: String
    let date: String
    let ip: String
    let content: String
    let isOwn: Bool         // my_con 클래스 = 내 댓글
    var replies: [Comment]

    init(id: String, seq: String = "", author: String, avatarUrl: String = "",
         date: String, ip: String, content: String,
         isOwn: Bool = false, replies: [Comment] = []) {
        self.id       = id
        self.seq      = seq
        self.author   = author
        self.avatarUrl = avatarUrl
        self.date     = date
        self.ip       = ip
        self.content  = content
        self.isOwn    = isOwn
        self.replies  = replies
    }
}
