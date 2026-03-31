import Foundation

struct Comment: Identifiable {
    let id: String          // "\(postId)_c\(i)" — ForEach용 고유키
    let seq: String         // DOM id "reply_{seq}" → API 수정/삭제에 사용
    let replyPrid: String   // 대댓글 등록 시 prid 값 (depth2 답글은 부모 replied seq)
    let replySource: String // 대댓글 등록 시 source 값 (웹 viewReply의 세 번째 인자)
    let author: String
    let avatarUrl: String
    let date: String
    let ip: String
    let content: String
    let isOwn: Bool         // my_con 클래스 = 내 댓글
    let replyToAuthor: String // 대댓글 대상 닉네임 (span.name_re 파싱)
    let depth: Int          // 0=최상위, 1=replied, 2=replied_re
    var replies: [Comment]

    init(id: String, seq: String = "", replyPrid: String = "", replySource: String = "",
         author: String, avatarUrl: String = "",
         date: String, ip: String, content: String,
         isOwn: Bool = false, replyToAuthor: String = "", depth: Int = 0, replies: [Comment] = []) {
        self.id            = id
        self.seq           = seq
        self.replyPrid     = replyPrid.isEmpty ? seq : replyPrid
        self.replySource   = replySource.isEmpty ? seq : replySource
        self.author        = author
        self.avatarUrl     = avatarUrl
        self.date          = date
        self.ip            = ip
        self.content       = content
        self.isOwn         = isOwn
        self.replyToAuthor = replyToAuthor
        self.depth         = depth
        self.replies       = replies
    }
}
