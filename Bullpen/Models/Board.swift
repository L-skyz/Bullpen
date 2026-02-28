import Foundation

// 글쓰기 폼용 말머리 (서버 숫자 ID + 표시명)
struct BoardCategory: Identifiable, Hashable, Codable {
    let id: String    // 서버 category 숫자값 (e.g. "54")
    let name: String  // 표시명 (e.g. "야구")
}

struct Board: Identifiable, Hashable, Codable {
    let id: String
    let name: String
    /// 게시판 목록 필터 탭용 말머리 (없으면 빈 배열)
    let maemuri: [String]
    /// 글쓰기 폼 category select 목록 (없으면 글쓰기 불가 게시판)
    let writeCategories: [BoardCategory]

    var isWritable: Bool { !writeCategories.isEmpty }

    var listURL: URL {
        URL(string: "https://mlbpark.donga.com/mp/b.php?b=\(id)")!
    }

    init(id: String, name: String, maemuri: [String] = [], writeCategories: [BoardCategory] = []) {
        self.id = id
        self.name = name
        self.maemuri = maemuri
        self.writeCategories = writeCategories
    }

    static let all: [Board] = [
        Board(id: "mlbtown", name: "MLB타운",
              maemuri: [
                "WBC", "MLB", "LAD", "NYY", "SF", "TB", "SD", "BOS", "KC", "LAA",
                "BAL", "NYM", "PHI", "ATL", "MIA", "PIT", "TOR", "ATH", "CHC", "TEX",
                "HOU", "CLE", "CHW", "SEA", "DET", "ARI", "STL", "CIN", "MIN", "WSH",
                "COL", "직관", "오피셜", "NPB", "VS",
              ],
              writeCategories: [
                .init(id: "127", name: "WBC"),
                .init(id: "146", name: "직관"),
                .init(id: "96",  name: "MLB"),
                .init(id: "46",  name: "알동"),
                .init(id: "61",  name: "NYY"),
                .init(id: "62",  name: "BOS"),
                .init(id: "63",  name: "TOR"),
                .init(id: "64",  name: "BAL"),
                .init(id: "65",  name: "TB"),
                .init(id: "47",  name: "알중"),
                .init(id: "66",  name: "CLE"),
                .init(id: "67",  name: "MIN"),
                .init(id: "68",  name: "CHW"),
                .init(id: "69",  name: "DET"),
                .init(id: "70",  name: "KC"),
                .init(id: "48",  name: "알서"),
                .init(id: "71",  name: "LAA"),
                .init(id: "72",  name: "ATH"),
                .init(id: "73",  name: "HOU"),
                .init(id: "74",  name: "TEX"),
                .init(id: "75",  name: "SEA"),
                .init(id: "49",  name: "늘동"),
                .init(id: "76",  name: "ATL"),
                .init(id: "77",  name: "NYM"),
                .init(id: "78",  name: "WSH"),
                .init(id: "79",  name: "PHI"),
                .init(id: "80",  name: "MIA"),
                .init(id: "50",  name: "늘중"),
                .init(id: "81",  name: "STL"),
                .init(id: "82",  name: "PIT"),
                .init(id: "83",  name: "CHC"),
                .init(id: "84",  name: "MIL"),
                .init(id: "85",  name: "CIN"),
                .init(id: "51",  name: "늘서"),
                .init(id: "86",  name: "LAD"),
                .init(id: "87",  name: "SF"),
                .init(id: "88",  name: "SD"),
                .init(id: "89",  name: "ARI"),
                .init(id: "90",  name: "COL"),
                .init(id: "52",  name: "포시"),
                .init(id: "53",  name: "스캠"),
                .init(id: "91",  name: "스토브리그"),
                .init(id: "97",  name: "FA"),
                .init(id: "98",  name: "트레이드"),
                .init(id: "99",  name: "드래프트"),
                .init(id: "59",  name: "VS"),
                .init(id: "29",  name: "아마야구"),
                .init(id: "114", name: "NPB"),
                .init(id: "140", name: "오피셜"),
              ]),

        Board(id: "kbotown", name: "한국야구",
              maemuri: [
                "WBC", "LG", "한화", "SSG", "삼성", "NC", "kt", "롯데",
                "KIA", "두산", "키움", "최강야구", "KBO", "스토브리그/FA", "오피셜",
              ],
              writeCategories: [
                .init(id: "127", name: "WBC"),
                .init(id: "154", name: "프리미어12"),
                .init(id: "13",  name: "두산"),
                .init(id: "14",  name: "롯데"),
                .init(id: "15",  name: "삼성"),
                .init(id: "18",  name: "키움"),
                .init(id: "16",  name: "한화"),
                .init(id: "17",  name: "KIA"),
                .init(id: "26",  name: "kt"),
                .init(id: "19",  name: "LG"),
                .init(id: "25",  name: "NC"),
                .init(id: "12",  name: "SSG"),
                .init(id: "37",  name: "KBO"),
                .init(id: "128", name: "최강야구"),
                .init(id: "29",  name: "아마야구"),
                .init(id: "52",  name: "포시"),
                .init(id: "53",  name: "스캠"),
                .init(id: "91",  name: "스토브리그"),
                .init(id: "97",  name: "FA"),
                .init(id: "98",  name: "트레이드"),
                .init(id: "99",  name: "드래프트"),
                .init(id: "59",  name: "VS"),
                .init(id: "138", name: "아시안게임"),
                .init(id: "140", name: "오피셜"),
                .init(id: "146", name: "직관"),
                .init(id: "148", name: "이벤트"),
              ]),

        Board(id: "bullpen", name: "불펜",
              maemuri: [
                "야구", "축구", "해축", "러닝/헬스", "농구", "NBA", "NFL", "격투기",
                "e스포츠", "라면대학", "유머/짤/펌", "동물", "여행", "패션", "영화", "만화",
                "음식", "역사", "과학", "군사", "자동차", "IT", "아이돌", "방송/연예",
                "코/주/부", "고민상담", "결혼/연애", "정치", "주번나/17금/19금", "핫딜",
              ],
              writeCategories: [
                .init(id: "1",   name: "정치"),
                .init(id: "54",  name: "야구"),
                .init(id: "55",  name: "축구"),
                .init(id: "129", name: "해축"),
                .init(id: "57",  name: "배구"),
                .init(id: "56",  name: "농구"),
                .init(id: "130", name: "NBA"),
                .init(id: "150", name: "헬스"),
                .init(id: "149", name: "러닝"),
                .init(id: "131", name: "격투기"),
                .init(id: "136", name: "테니스"),
                .init(id: "137", name: "골프"),
                .init(id: "132", name: "당구"),
                .init(id: "133", name: "NFL"),
                .init(id: "134", name: "e스포츠"),
                .init(id: "135", name: "F1"),
                .init(id: "30",  name: "기타스포츠"),
                .init(id: "116", name: "올림픽"),
                .init(id: "128", name: "아시안게임"),
                .init(id: "5",   name: "게임"),
                .init(id: "125", name: "결혼/연애"),
                .init(id: "23",  name: "경제"),
                .init(id: "60",  name: "고민상담"),
                .init(id: "58",  name: "과학"),
                .init(id: "93",  name: "군사"),
                .init(id: "118", name: "낚시"),
                .init(id: "126", name: "도서"),
                .init(id: "41",  name: "동물"),
                .init(id: "139", name: "라면대학"),
                .init(id: "151", name: "만화"),
                .init(id: "32",  name: "문화"),
                .init(id: "34",  name: "방송"),
                .init(id: "120", name: "부동산"),
                .init(id: "11",  name: "뻘글"),
                .init(id: "31",  name: "사회"),
                .init(id: "121", name: "썰"),
                .init(id: "24",  name: "아이돌"),
                .init(id: "92",  name: "여행"),
                .init(id: "42",  name: "역사"),
                .init(id: "33",  name: "연예"),
                .init(id: "38",  name: "영화"),
                .init(id: "103", name: "유머"),
                .init(id: "39",  name: "음식"),
                .init(id: "8",   name: "음악"),
                .init(id: "148", name: "이벤트"),
                .init(id: "102", name: "일상"),
                .init(id: "119", name: "자동차"),
                .init(id: "28",  name: "주번나"),
                .init(id: "40",  name: "주식"),
                .init(id: "6",   name: "질문"),
                .init(id: "22",  name: "짤방"),
                .init(id: "36",  name: "코인"),
                .init(id: "152", name: "패션"),
                .init(id: "4",   name: "펌글"),
                .init(id: "43",  name: "포인트"),
                .init(id: "95",  name: "프로토"),
                .init(id: "20",  name: "후기"),
                .init(id: "94",  name: "IT"),
                .init(id: "35",  name: "LOL"),
                .init(id: "59",  name: "VS"),
                .init(id: "7",   name: "17금"),
                .init(id: "2",   name: "19금"),
              ]),

        Board(id: "worldbullpen", name: "해외야구",
              maemuri: [
                "야구", "축구", "해축", "러닝/헬스", "농구", "NBA", "NFL", "격투기",
                "e스포츠", "라면대학", "유머/짤/펌", "동물", "여행", "패션", "영화", "만화",
                "음식", "역사", "과학", "군사", "자동차", "IT", "아이돌", "방송/연애",
                "코/주/부", "고민상담", "결혼/연애", "정치", "주번나/17금/19금", "핫딜",
              ]),  // 글쓰기 불가 (사이트 write form에 없음)

        Board(id: "suggestion", name: "건의/제안",
              writeCategories: [
                .init(id: "106", name: "신고합니다"),
                .init(id: "107", name: "광고 신고합니다"),
                .init(id: "108", name: "문의합니다"),
                .init(id: "109", name: "멀티 문의합니다"),
                .init(id: "110", name: "프록시 문의합니다"),
                .init(id: "117", name: "긴급신고"),
                .init(id: "122", name: "불법영상물 긴급신고"),
                .init(id: "123", name: "허위영상물 긴급신고"),
                .init(id: "124", name: "아동청소년 성착취물 긴급신고"),
              ]),
    ]
}
