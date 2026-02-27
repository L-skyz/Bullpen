import Foundation

struct Board: Identifiable, Hashable, Codable {
    let id: String
    let name: String
    /// 게시판별 고정 말머리 목록 (없으면 빈 배열)
    let maemuri: [String]

    var listURL: URL {
        URL(string: "https://mlbpark.donga.com/mp/b.php?b=\(id)")!
    }

    // Codable 자동 합성을 위해 maemuri 기본값 지원
    init(id: String, name: String, maemuri: [String] = []) {
        self.id = id
        self.name = name
        self.maemuri = maemuri
    }

    static let all: [Board] = [
        Board(id: "mlbtown", name: "MLB타운", maemuri: [
            "WBC", "MLB", "LAD", "NYY", "SF", "TB", "SD", "BOS", "KC", "LAA",
            "BAL", "NYM", "PHI", "ATL", "MIA", "PIT", "TOR", "ATH", "CHC", "TEX",
            "HOU", "CLE", "CHW", "SEA", "DET", "ARI", "STL", "CIN", "MIN", "WSH",
            "COL", "MIL", "직관", "오피셜", "NPB", "VS",
        ]),
        Board(id: "kbotown", name: "한국야구", maemuri: [
            "WBC", "LG", "한화", "SSG", "삼성", "NC", "kt", "롯데",
            "KIA", "두산", "키움", "최강야구", "KBO", "스토브리그/FA", "오피셜",
        ]),
        Board(id: "bullpen", name: "불펜", maemuri: [
            "야구", "축구", "해축", "러닝/헬스", "농구", "NBA", "NFL", "격투기",
            "e스포츠", "라면대학", "유머/짤/펌", "동물", "여행", "패션", "영화", "만화",
            "음식", "역사", "과학", "군사", "자동차", "IT", "아이돌", "방송/연예",
            "코/주/부", "고민상담", "결혼/연애", "정치", "주번나/17금/19금", "핫딜",
        ]),
        Board(id: "worldbullpen", name: "해외야구", maemuri: [
            "야구", "축구", "해축", "러닝/헬스", "농구", "NBA", "NFL", "격투기",
            "e스포츠", "라면대학", "유머/짤/펌", "동물", "여행", "패션", "영화", "만화",
            "음식", "역사", "과학", "군사", "자동차", "IT", "아이돌", "방송/연예",
            "코/주/부", "고민상담", "결혼/연애", "정치", "주번나/17금/19금", "핫딜",
        ]),
        Board(id: "suggestion", name: "건의/제안"),
    ]
}
