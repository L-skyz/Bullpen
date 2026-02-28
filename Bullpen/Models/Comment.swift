import Foundation

struct Comment: Identifiable {
    let id: String
    let author: String
    let avatarUrl: String
    let date: String
    let ip: String
    let content: String
    var replies: [Comment]

    init(id: String, author: String, avatarUrl: String = "", date: String, ip: String,
         content: String, replies: [Comment] = []) {
        self.id = id
        self.author = author
        self.avatarUrl = avatarUrl
        self.date = date
        self.ip = ip
        self.content = content
        self.replies = replies
    }
}
