import Foundation

struct KboTeamScore {
    let name: String
    let logoURL: String
    let score: String   // "-" if not started
}

struct KboGame: Identifiable {
    let id: String          // 합성 키: "{away}_{home}_{yyyyMMdd KST}"  e.g. "KIA_LG_20260329"
    let isLive: Bool
    let inning: String      // "6회말", "경기종료", "경기예정" 등
    let location: String    // 구장명만 (e.g. "잠실")
    let gameTime: String    // 시작 시각 KST (e.g. "18:30"), 예정 경기만 유효
    let home: KboTeamScore
    let away: KboTeamScore
    // 라이브 중 상황 (비라이브 시 -1)
    let outs: Int           // 0-2
    let balls: Int          // 0-3
    let strikes: Int        // 0-2
    let base1: Bool
    let base2: Bool
    let base3: Bool
}
