import Foundation

struct Post: Identifiable, Hashable {
    let id: String
    let boardId: String
    let maemuri: String
    let title: String
    let author: String
    let avatarUrl: String
    let date: String
    let views: Int
    let commentCount: Int
    let recommendCount: Int

    init(id: String, boardId: String, maemuri: String, title: String,
         author: String, avatarUrl: String = "", date: String,
         views: Int, commentCount: Int, recommendCount: Int) {
        self.id = id
        self.boardId = boardId
        self.maemuri = maemuri
        self.title = title
        self.author = author
        self.avatarUrl = avatarUrl
        self.date = date
        self.views = views
        self.commentCount = commentCount
        self.recommendCount = recommendCount
    }

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
    let avatarUrl: String
    let date: String
    let views: Int
    let commentCount: Int
    let recommendCount: Int
    let contentHTML: String
    let comments: [Comment]
}
