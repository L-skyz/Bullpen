import Foundation

/// 더그아웃 내게시글/내댓글 항목
struct DugoutItem: Identifiable, Hashable {
    /// 더그아웃 row ID (내게시글 = postId, 내댓글 = 댓글ID)
    let id: String
    /// 게시판 ID (e.g. "bullpen", "kbotown")
    let boardId: String
    /// 게시판 표시명 (e.g. "BULLPEN")
    let boardName: String
    /// 게시글 제목 (댓글은 원글 제목)
    let title: String
    /// 작성 날짜
    let date: String
    /// true = 내댓글, false = 내게시글
    let isComment: Bool
    /// 열람할 원글 postId (내게시글=id 동일, 내댓글=원글 ID)
    let originalPostId: String
    /// 댓글 삭제용 sequence 값 (내댓글 전용, op.php data-sequence)
    let deleteSeq: String
}
