import Foundation

struct Board: Identifiable, Hashable, Codable {
    let id: String
    let name: String

    var listURL: URL {
        URL(string: "https://mlbpark.donga.com/mp/b.php?b=\(id)")!
    }

    static let all: [Board] = [
        Board(id: "mlbtown",       name: "MLB타운"),
        Board(id: "kbotown",       name: "한국야구"),
        Board(id: "bullpen",       name: "불펜"),
        Board(id: "worldbullpen",  name: "해외야구"),
        Board(id: "phone",         name: "스마트폰"),
        Board(id: "suggestion",    name: "건의/제안"),
    ]
}
