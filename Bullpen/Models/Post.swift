import Foundation

struct Post: Identifiable, Hashable {
    let id: String
    let boardId: String
    let maemuri: String
    let title: String
    let author: String
    let date: String
    let views: Int
    let commentCount: Int
    let recommendCount: Int

    var detailURL: URL? {
        URL(string: "https://mlbpark.donga.com/mp/b.php?b=\(boardId)&id=\(id)&m=view")
    }
}

struct PostDetail: Identifiable {
    let id: String
    let boardId: String
    let maemuri: String
    let title: String
    let author: String
    let date: String
    let views: Int
    let commentCount: Int
    let recommendCount: Int
    let contentHTML: String
    let comments: [Comment]
}
