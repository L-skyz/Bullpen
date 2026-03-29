import SwiftUI

struct KboScoreBannerView: View {
    @ObservedObject var vm: KboScoreViewModel

    var body: some View {
        Group {
            if vm.error == nil && !vm.games.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    // 헤더
                    HStack(spacing: 6) {
                        Text("🏟 KBO")
                            .font(.caption).fontWeight(.semibold)
                        let liveCount = vm.games.filter { $0.isLive }.count
                        if liveCount > 0 {
                            HStack(spacing: 3) {
                                Circle().fill(Color.red).frame(width: 6, height: 6)
                                Text("LIVE \(liveCount)경기")
                                    .font(.caption2).foregroundColor(.red).fontWeight(.bold)
                            }
                        }
                        Spacer()
                        if let updated = vm.lastUpdated {
                            Text(updated, style: .time)
                                .font(.caption2).foregroundColor(.secondary)
                        }
                        Button { Task { await vm.refresh() } } label: {
                            Image(systemName: "arrow.clockwise")
                                .font(.caption2).foregroundColor(.secondary)
                        }
                    }
                    .padding(.horizontal, 12)

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(vm.games) { game in
                                KboGameCard(game: game)
                            }
                        }
                        .padding(.horizontal, 12)
                        .padding(.bottom, 2)
                    }
                }
                .padding(.vertical, 8)
            }
        }
    }
}

// MARK: - 경기 카드

struct KboGameCard: View {
    let game: KboGame

    var body: some View {
        VStack(spacing: 0) {
            // 상태 배지
            statusBadge
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 8)
                .padding(.top, 6)

            Divider().padding(.vertical, 3)

            // 어웨이팀
            teamRow(team: game.away, opponentScore: game.home.score)
                .padding(.horizontal, 8)
            // 홈팀
            teamRow(team: game.home, opponentScore: game.away.score)
                .padding(.horizontal, 8)

            // 베이스 + 아웃카운트 (라이브 중에만)
            if game.isLive && game.outs >= 0 {
                Divider().padding(.vertical, 3)
                situationRow
                    .padding(.horizontal, 8)
                    .padding(.bottom, 5)
            } else {
                // 구장
                if !game.location.isEmpty {
                    Text(game.location)
                        .font(.system(size: 9)).foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 8)
                        .padding(.bottom, 5)
                }
            }
        }
        .frame(width: 130)
        .background(Color(.secondarySystemBackground))
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(game.isLive ? Color.red.opacity(0.5) : Color.clear, lineWidth: 1.5)
        )
    }

    // MARK: 상태 배지
    @ViewBuilder
    private var statusBadge: some View {
        if game.isLive {
            HStack(spacing: 4) {
                Text("LIVE")
                    .font(.system(size: 8, weight: .bold)).foregroundColor(.white)
                    .padding(.horizontal, 4).padding(.vertical, 2)
                    .background(Color.red).cornerRadius(3)
                Text(game.inning)
                    .font(.system(size: 10)).foregroundColor(.primary)
            }
        } else if game.inning == "경기종료" {
            Text("종료").font(.system(size: 10)).foregroundColor(.secondary)
        } else {
            Text(game.inning.isEmpty ? "예정" : game.inning)
                .font(.system(size: 10)).foregroundColor(.secondary)
        }
    }

    // MARK: 팀 행
    private func teamRow(team: KboTeamScore, opponentScore: String) -> some View {
        let mine = Int(team.score) ?? -1
        let opp  = Int(opponentScore) ?? -1
        let isWin = mine >= 0 && mine > opp
        return HStack(spacing: 5) {
            AsyncImage(url: URL(string: team.logoURL)) { phase in
                switch phase {
                case .success(let img): img.resizable().scaledToFit()
                default:
                    ZStack {
                        Circle().fill(teamColor(for: team.name))
                        Text(String(team.name.prefix(1)))
                            .font(.system(size: 7, weight: .bold)).foregroundColor(.white)
                    }
                }
            }
            .frame(width: 18, height: 18)

            Text(team.name)
                .font(.system(size: 11)).lineLimit(1)
            Spacer()
            Text(team.score)
                .font(.system(size: 13, weight: isWin ? .bold : .regular))
                .foregroundColor(isWin ? .primary : .secondary)
        }
        .padding(.vertical, 2)
    }

    // MARK: 베이스 + BSO 상황
    private var situationRow: some View {
        HStack(spacing: 6) {
            // 베이스 다이아몬드
            BasesDiamondView(base1: game.base1, base2: game.base2, base3: game.base3)
                .frame(width: 28, height: 28)
            // 아웃카운트
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 3) {
                    ForEach(0..<3) { i in
                        Circle()
                            .fill(i < game.outs ? Color.red : Color(.systemGray4))
                            .frame(width: 6, height: 6)
                    }
                }
                if game.balls >= 0 {
                    Text("\(game.balls)B \(game.strikes)S")
                        .font(.system(size: 9)).foregroundColor(.secondary)
                }
            }
            Spacer()
        }
    }

    private func teamColor(for name: String) -> Color {
        switch name {
        case "LG":   return Color(red: 0.80, green: 0.00, blue: 0.00)
        case "KIA":  return Color(red: 0.85, green: 0.15, blue: 0.15)
        case "삼성": return Color(red: 0.00, green: 0.32, blue: 0.65)
        case "두산": return Color(red: 0.10, green: 0.10, blue: 0.10)
        case "롯데": return Color(red: 0.85, green: 0.10, blue: 0.10)
        case "한화": return Color(red: 0.95, green: 0.45, blue: 0.00)
        case "SSG":  return Color(red: 0.85, green: 0.10, blue: 0.20)
        case "NC":   return Color(red: 0.00, green: 0.42, blue: 0.65)
        case "kt":   return Color(red: 0.10, green: 0.10, blue: 0.10)
        case "키움": return Color(red: 0.55, green: 0.00, blue: 0.20)
        default:
            let hash = name.unicodeScalars.reduce(0) { $0 + Int($1.value) }
            let palette: [Color] = [.orange, .green, .purple, .teal, .indigo]
            return palette[abs(hash) % palette.count]
        }
    }
}

// MARK: - 베이스 다이아몬드

struct BasesDiamondView: View {
    let base1: Bool   // 1루 (오른쪽)
    let base2: Bool   // 2루 (위)
    let base3: Bool   // 3루 (왼쪽)

    var body: some View {
        ZStack {
            // 홈
            diamond(filled: false)
                .frame(width: 7, height: 7)
                .offset(x: 0, y: 10)
            // 1루
            diamond(filled: base1)
                .frame(width: 7, height: 7)
                .offset(x: 10, y: 3)
            // 2루
            diamond(filled: base2)
                .frame(width: 7, height: 7)
                .offset(x: 0, y: -5)
            // 3루
            diamond(filled: base3)
                .frame(width: 7, height: 7)
                .offset(x: -10, y: 3)
        }
    }

    private func diamond(filled: Bool) -> some View {
        Rectangle()
            .fill(filled ? Color.yellow : Color(.systemGray4))
            .rotationEffect(.degrees(45))
    }
}
