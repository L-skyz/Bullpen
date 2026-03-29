# KBO 라이브스코어 배너 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** `kbotown` 게시판 상단에 스탯티즈 KBO 라이브스코어를 가로 스크롤 카드 배너로 표시하고, 라이브 경기 중 자동 폴링한다.

**Architecture:** `MLBParkService`(actor)에 `fetchKboScores()`를 추가해 스탯티즈 HTML을 SwiftSoup으로 파싱한다. `KboScoreViewModel`이 데이터 기반 폴링 루프를 담당하고, `KboScoreBannerView`가 mlbpark 카드 스타일 UI를 렌더링한다. `PostListView`는 `kbotown` 보드일 때만 배너를 List 첫 행으로 삽입한다.

**Tech Stack:** SwiftUI, Swift Concurrency (actor, Task, AsyncStream), SwiftSoup (기존 의존성), URLSession

---

## 파일 구성

| 파일 | 작업 |
|------|------|
| `Bullpen/Models/KboGame.swift` | `id` 필드 주석 수정 |
| `Bullpen/Services/MLBParkService.swift` | `fetchKboScores() async throws -> [KboGame]` 추가 |
| `Bullpen/ViewModels/KboScoreViewModel.swift` | 신규 (디렉토리도 신규) |
| `Bullpen/Views/KboScoreBannerView.swift` | 신규 |
| `Bullpen/Views/PostListView.swift` | 배너 삽입, refreshable 연동 |

---

## Task 0: 스탯티즈 DOM 분석 (사전 필수)

> ⚠️ 이 Task는 코드 작성 전에 완료되어야 한다. 여기서 확인한 셀렉터가 Task 2 파싱 코드의 기반이 된다.

**Files:**
- 없음 (분석만)

- [ ] **Step 1: 스탯티즈 라이브스코어 URL 확인**

  WebFetch 또는 Chrome DevTools로 아래 URL을 시도해 KBO 경기 목록이 포함된 페이지를 찾는다:
  - `https://www.statiz.co.kr/schedule.php`
  - `https://www.statiz.co.kr/`

  목표: 오늘 경기 목록 HTML이 실제로 포함된 URL 확인.

- [ ] **Step 2: DOM 셀렉터 확인**

  경기 HTML에서 아래 항목의 CSS 셀렉터를 확인하고 메모한다:

  | 항목 | 셀렉터 (예시) | 실제 값 |
  |------|--------------|---------|
  | 경기 행 컨테이너 | `.game_listitem` | ? |
  | 홈팀 이름 | `.home .name` | ? |
  | 어웨이팀 이름 | `.away .name` | ? |
  | 홈팀 스코어 | `.home .score` | ? |
  | 어웨이팀 스코어 | `.away .score` | ? |
  | 라이브 여부 | `.live` 존재 여부 | ? |
  | 이닝/상태 텍스트 | `.inning` | ? |
  | 구장 | `.location` | ? |
  | 경기 시작 전 시간 | `.game_time` | ? |
  | 종료 표시 | `.end` | ? |

- [ ] **Step 3: 인코딩 확인**

  응답 HTTP 헤더의 `Content-Type` charset 확인 (UTF-8이면 일반 처리, EUC-KR이면 `decodeCP949` 사용).

- [ ] **Step 4: 셀렉터 확정 후 이 플랜 파일의 Step 2 표를 직접 채워 기록**

  위 표의 "실제 값" 컬럼을 확인된 셀렉터로 채운 뒤 저장한다.
  이 기록이 Task 2 파싱 코드 작성의 유일한 근거가 된다 — 세션이 달라도 정보가 유지되어야 한다.
  경기가 없는 날이라면 날짜를 바꾸거나 archived 페이지로 셀렉터만 확인한다.

---

## Task 1: KboGame.swift 주석 수정

**Files:**
- Modify: `Bullpen/Models/KboGame.swift`

- [ ] **Step 1: id 필드 주석 교체**

  `Bullpen/Models/KboGame.swift` 10번째 줄:

  ```swift
  // 변경 전:
  let id: String          // matchId from linkMatchPage(...)

  // 변경 후:
  let id: String          // 합성 키: "{away}_{home}_{yyyyMMdd KST}"  e.g. "KIA_LG_20260329"
  ```

- [ ] **Step 2: 커밋**

  ```bash
  git add Bullpen/Models/KboGame.swift
  git commit -m "chore: KboGame.id 주석 → 합성 키 방식으로 업데이트"
  ```

---

## Task 2: MLBParkService에 fetchKboScores() 추가

> `MLBParkService`는 `actor`이므로 메서드는 `actor` 내부에 추가. 스탯티즈는 UTF-8 응답이므로 `String(data:encoding:.utf8)` 사용 (Task 0 Step 3에서 EUC-KR 확인 시 `decodeCP949` 사용).

**Files:**
- Modify: `Bullpen/Services/MLBParkService.swift`

- [ ] **Step 1: today 헬퍼 추가**

  `MLBParkService` actor 바디 내부 (private 메서드 섹션)에 추가:

  ```swift
  private static func kstDateString() -> String {
      let fmt = DateFormatter()
      fmt.dateFormat = "yyyyMMdd"
      fmt.timeZone = TimeZone(identifier: "Asia/Seoul")
      return fmt.string(from: Date())
  }
  ```

- [ ] **Step 2: fetchKboScores() 구현**

  Task 0에서 확인한 셀렉터를 사용해 아래 뼈대를 완성한다.
  `MLBParkService` actor 바디 내부에 추가:

  ```swift
  func fetchKboScores() async throws -> [KboGame] {
      // Task 0에서 확인한 실제 URL로 교체
      guard let url = URL(string: "https://www.statiz.co.kr/schedule.php") else {
          throw MLBParkError.invalidURL
      }
      var req = URLRequest(url: url)
      req.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1", forHTTPHeaderField: "User-Agent")
      req.setValue("https://www.statiz.co.kr/", forHTTPHeaderField: "Referer")

      let (data, _) = try await performRequest(req)
      guard let html = String(data: data, encoding: .utf8)
                    ?? String(data: data, encoding: .windowsCP949) else {
          throw MLBParkError.encodingError
      }

      let doc = try SwiftSoup.parse(html)
      let today = Self.kstDateString()

      // Task 0에서 확인한 셀렉터로 교체
      let rows = try doc.select("GAME_ROW_SELECTOR_HERE")
      guard !rows.isEmpty() else { return [] }

      return try rows.array().compactMap { row -> KboGame? in
          let isLive = (try? row.select("LIVE_SELECTOR").first()) != nil

          // 이닝: LIVE면 이닝 텍스트, 종료면 "종료", 예정이면 시작 시간
          let inning: String
          if isLive {
              inning = (try? row.select("INNING_SELECTOR").first()?.text()) ?? ""
          } else if (try? row.select("END_SELECTOR").first()) != nil {
              inning = "종료"
          } else {
              inning = (try? row.select("TIME_SELECTOR").first()?.text()) ?? ""
          }

          let location = (try? row.select("LOCATION_SELECTOR").first()?.text()) ?? ""

          let homeName  = (try? row.select("HOME_NAME_SELECTOR").first()?.text()) ?? ""
          let awayName  = (try? row.select("AWAY_NAME_SELECTOR").first()?.text()) ?? ""
          let homeScore = (try? row.select("HOME_SCORE_SELECTOR").first()?.text()) ?? "-"
          let awayScore = (try? row.select("AWAY_SCORE_SELECTOR").first()?.text()) ?? "-"

          guard !homeName.isEmpty, !awayName.isEmpty else { return nil }

          return KboGame(
              id: "\(awayName)_\(homeName)_\(today)",
              isLive: isLive,
              inning: inning,
              location: location,
              home: KboTeamScore(name: homeName, logoURL: "", score: homeScore),
              away: KboTeamScore(name: awayName, logoURL: "", score: awayScore)
          )
      }
  }
  ```

- [ ] **Step 3: 실기기 또는 시뮬레이터에서 경기 있는 날 빌드 후 콘솔 확인**

  `PostListView` 진입 전 임시로 `BullpenApp.swift` 또는 `ContentView`에서 호출해 파싱 결과를 print:
  ```swift
  Task {
      let games = try? await MLBParkService.shared.fetchKboScores()
      print("KBO games:", games ?? [])
  }
  ```
  결과가 비어있으면 셀렉터 재확인. 완료 후 임시 코드 제거.

- [ ] **Step 4: 커밋**

  ```bash
  git add Bullpen/Services/MLBParkService.swift
  git commit -m "feat: MLBParkService에 fetchKboScores() 추가 (스탯티즈 파싱)"
  ```

---

## Task 3: KboScoreViewModel 신규

**Files:**
- Create: `Bullpen/ViewModels/KboScoreViewModel.swift` (디렉토리도 신규)

- [ ] **Step 1: 파일 생성**

  ```swift
  // Bullpen/ViewModels/KboScoreViewModel.swift
  import SwiftUI

  @MainActor
  final class KboScoreViewModel: ObservableObject {
      @Published var games: [KboGame] = []
      @Published var error: String? = nil
      @Published var lastUpdated: Date? = nil

      private var pollingTask: Task<Void, Never>? = nil

      // MARK: - Public

      func start() {
          guard pollingTask == nil else { return }
          pollingTask = Task { [weak self] in
              await self?.pollLoop()
          }
      }

      func stop() {
          pollingTask?.cancel()
          pollingTask = nil
      }

      func refresh() async {
          await fetch()
      }

      // MARK: - Private

      private func pollLoop() async {
          while !Task.isCancelled {
              await fetch()
              guard !Task.isCancelled else { return }

              let interval = nextInterval()
              // 종료 or 빈 배열이면 폴링 중단
              if interval == nil { return }

              try? await Task.sleep(nanoseconds: UInt64(interval! * 1_000_000_000))
          }
      }

      private func fetch() async {
          do {
              let result = try await MLBParkService.shared.fetchKboScores()
              games = result
              error = nil
              lastUpdated = Date()
          } catch {
              self.error = error.localizedDescription
          }
      }

      /// 다음 폴링까지 대기 시간(초). nil이면 폴링 중단.
      private func nextInterval() -> Double? {
          if games.isEmpty { return nil }                           // 오늘 경기 없음 → 중단
          if games.allSatisfy({ $0.inning == "종료" }) { return nil } // 전부 종료 → 중단
          if games.contains(where: { $0.isLive }) { return 30 }    // 라이브 있음 → 30초
          return 300                                                 // 예정만 있음 → 5분
      }
  }
  ```

- [ ] **Step 2: Xcode에서 ViewModels 그룹 추가**

  Xcode Project Navigator에서 `Bullpen` 폴더 우클릭 → New Group → `ViewModels`. `KboScoreViewModel.swift`를 해당 그룹으로 이동/추가.

- [ ] **Step 3: 커밋**

  ```bash
  git add Bullpen/ViewModels/KboScoreViewModel.swift
  git commit -m "feat: KboScoreViewModel 추가 — 데이터 기반 폴링 로직"
  ```

---

## Task 4: KboScoreBannerView 신규

**Files:**
- Create: `Bullpen/Views/KboScoreBannerView.swift`

- [ ] **Step 1: 파일 생성**

  mlbpark `.game_listitem` 카드 스타일 재현:

  ```swift
  // Bullpen/Views/KboScoreBannerView.swift
  import SwiftUI

  struct KboScoreBannerView: View {
      @ObservedObject var vm: KboScoreViewModel

      var body: some View {
          // 오류 또는 경기 없음: 배너 숨김
          if vm.error != nil || vm.games.isEmpty { return AnyView(EmptyView()) }

          return AnyView(
              VStack(alignment: .leading, spacing: 6) {
                  // 헤더 바
                  HStack {
                      HStack(spacing: 4) {
                          Text("🏟 KBO")
                              .font(.caption).fontWeight(.semibold)
                          let liveCount = vm.games.filter { $0.isLive }.count
                          if liveCount > 0 {
                              HStack(spacing: 3) {
                                  Circle().fill(Color.red).frame(width: 6, height: 6)
                                  Text("LIVE \(liveCount)경기")
                                      .font(.caption).foregroundColor(.red).fontWeight(.semibold)
                              }
                          }
                      }
                      Spacer()
                      if let updated = vm.lastUpdated {
                          Text(updated, style: .time)
                              .font(.caption2).foregroundColor(.secondary)
                      }
                      Button {
                          Task { await vm.refresh() }
                      } label: {
                          Image(systemName: "arrow.clockwise")
                              .font(.caption2).foregroundColor(.secondary)
                      }
                  }
                  .padding(.horizontal, 12)

                  // 가로 스크롤 카드
                  ScrollView(.horizontal, showsIndicators: false) {
                      HStack(spacing: 8) {
                          ForEach(vm.games) { game in
                              KboGameCard(game: game)
                          }
                      }
                      .padding(.horizontal, 12)
                  }
              }
              .padding(.vertical, 8)
          )
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

              Divider().padding(.vertical, 4)

              // 홈팀
              teamRow(team: game.home, opponent: game.away)
                  .padding(.horizontal, 8)

              // 어웨이팀
              teamRow(team: game.away, opponent: game.home)
                  .padding(.horizontal, 8)

              // 구장
              if !game.location.isEmpty {
                  Text(game.location)
                      .font(.system(size: 9)).foregroundColor(.secondary)
                      .frame(maxWidth: .infinity, alignment: .leading)
                      .padding(.horizontal, 8)
                      .padding(.bottom, 6)
              }
          }
          .frame(width: 120)
          .background(Color(.secondarySystemBackground))
          .cornerRadius(8)
          .overlay(
              RoundedRectangle(cornerRadius: 8)
                  .stroke(game.isLive ? Color.red.opacity(0.6) : Color.clear, lineWidth: 1.5)
          )
      }

      @ViewBuilder
      private var statusBadge: some View {
          if game.isLive {
              HStack(spacing: 4) {
                  Text("LIVE")
                      .font(.system(size: 9, weight: .bold))
                      .foregroundColor(.white)
                      .padding(.horizontal, 4).padding(.vertical, 2)
                      .background(Color.red).cornerRadius(3)
                  Text(game.inning)
                      .font(.system(size: 10)).foregroundColor(.primary)
              }
          } else if game.inning == "종료" {
              Text("종료")
                  .font(.system(size: 10)).foregroundColor(.secondary)
          } else {
              Text(game.inning.isEmpty ? "예정" : game.inning)
                  .font(.system(size: 10)).foregroundColor(.secondary)
          }
      }

      private func teamRow(team: KboTeamScore, opponent: KboTeamScore) -> some View {
          let myScore = Int(team.score) ?? -1
          let oppScore = Int(opponent.score) ?? -1
          let isWinning = myScore >= 0 && myScore > oppScore

          return HStack {
              // 팀명 첫 글자 원형 (로고 없음)
              ZStack {
                  Circle().fill(teamColor(for: team.name))
                  Text(String(team.name.prefix(1)))
                      .font(.system(size: 8, weight: .bold)).foregroundColor(.white)
              }
              .frame(width: 18, height: 18)

              Text(team.name)
                  .font(.system(size: 11))
                  .lineLimit(1)

              Spacer()

              Text(team.score)
                  .font(.system(size: 13, weight: isWinning ? .bold : .regular))
                  .foregroundColor(isWinning ? .primary : .secondary)
          }
          .padding(.vertical, 2)
      }

      private func teamColor(for name: String) -> Color {
          // KBO 팀 컬러 매핑 (대표색)
          switch name {
          case "LG":    return Color(red: 0.80, green: 0.00, blue: 0.00)
          case "KIA":   return Color(red: 0.85, green: 0.15, blue: 0.15)
          case "삼성":  return Color(red: 0.00, green: 0.32, blue: 0.65)
          case "두산":  return Color(red: 0.00, green: 0.00, blue: 0.00)
          case "롯데":  return Color(red: 0.85, green: 0.10, blue: 0.10)
          case "한화":  return Color(red: 0.95, green: 0.45, blue: 0.00)
          case "SSG":   return Color(red: 0.85, green: 0.10, blue: 0.20)
          case "NC":    return Color(red: 0.00, green: 0.42, blue: 0.65)
          case "kt":    return Color(red: 0.00, green: 0.00, blue: 0.00)
          case "키움":  return Color(red: 0.55, green: 0.00, blue: 0.20)
          default:
              let hash = name.unicodeScalars.reduce(0) { $0 + Int($1.value) }
              let palette: [Color] = [.orange, .green, .purple, .teal, .indigo]
              return palette[abs(hash) % palette.count]
          }
      }
  }
  ```

- [ ] **Step 2: 빌드 확인 (컴파일 오류 없음)**

  `Cmd+B`. 오류 없으면 통과.

- [ ] **Step 3: 커밋**

  ```bash
  git add Bullpen/Views/KboScoreBannerView.swift
  git commit -m "feat: KboScoreBannerView + KboGameCard — mlbpark 카드 스타일 UI"
  ```

---

## Task 5: PostListView 통합

**Files:**
- Modify: `Bullpen/Views/PostListView.swift`

- [ ] **Step 1: KboScoreViewModel @StateObject 추가**

  `PostListView` struct 내 프로퍼티 선언부에 추가:

  ```swift
  @StateObject private var kboVM = KboScoreViewModel()
  ```

- [ ] **Step 2: List 첫 행에 KboScoreBannerView 삽입**

  `PostListView.body`의 `List { ForEach(...) }` 블록 안, `ForEach` 바로 앞에 삽입:

  ```swift
  List {
      // ── KBO 라이브스코어 배너 (kbotown 전용) ──
      if board.id == "kbotown" {
          KboScoreBannerView(vm: kboVM)
              .listRowInsets(EdgeInsets())
              .listRowSeparator(.hidden)
              .listRowBackground(Color.clear)
      }
      // ─────────────────────────────────────────
      ForEach(filteredPosts) { post in
          ...
      }
  ```

- [ ] **Step 3: scenePhase 감지로 폴링 제어**

  `PostListView` struct 상단 프로퍼티에 추가:
  ```swift
  @Environment(\.scenePhase) private var scenePhase
  ```

  `body` 안 기존 `.task(id: board.id)` modifier 뒤에 추가:

  ```swift
  .onChange(of: scenePhase) { _, newPhase in
      guard board.id == "kbotown" else { return }
      if newPhase == .active {
          kboVM.start()
      } else {
          kboVM.stop()
      }
  }
  ```

- [ ] **Step 4: task modifier에서 kbotown 진입 시 start()**

  기존 `.task(id: board.id)` 블록 안에 추가:

  ```swift
  .task(id: board.id) {
      guard initializedBoardID != board.id else { return }
      initializedBoardID = board.id
      selectedMaemuri = "전체"
      scrollToTopTrigger += 1
      await vm.load(boardId: board.id, reset: true)
      // kbotown 진입 시 스코어 폴링 시작
      if board.id == "kbotown" { kboVM.start() }
  }
  ```

- [ ] **Step 5: pull-to-refresh 연동**

  기존 `.refreshable` 블록에 `kboVM.refresh()` 추가:

  ```swift
  .refreshable {
      await withTaskGroup(of: Void.self) { group in
          group.addTask { await vm.load(boardId: board.id, maemuri: activeMaemuri, reset: true) }
          group.addTask { await kboVM.refresh() }
      }
      if let first = filteredPosts.first { proxy.scrollTo(first.id, anchor: .top) }
  }
  ```
  > `proxy`는 `ScrollViewReader` 클로저 내부에 있으므로 `await` 이후에도 캡처된 값으로 접근 가능. `filteredPosts.first`는 로드 완료 후 갱신된 상태를 반영한다.

- [ ] **Step 6: 빌드 + 수동 확인**

  1. `Cmd+B` — 컴파일 오류 없음
  2. 시뮬레이터에서 한국야구 게시판 진입 → 배너 표시 확인
  3. 다른 게시판(MLB타운, 불펜)에서는 배너 없음 확인
  4. Pull-to-refresh → 배너 갱신 시각 업데이트 확인
  5. 배너 새로고침 버튼 동작 확인

- [ ] **Step 7: 커밋**

  ```bash
  git add Bullpen/Views/PostListView.swift
  git commit -m "feat: kbotown 게시판 상단에 KBO 라이브스코어 배너 통합"
  ```

---

## 완료 체크리스트

- [ ] Task 0: 스탯티즈 DOM 분석 완료, 셀렉터 확정
- [ ] Task 1: KboGame.swift 주석 수정
- [ ] Task 2: fetchKboScores() 파싱 동작 확인
- [ ] Task 3: 폴링 로직 동작 확인 (30초/5분/중단)
- [ ] Task 4: 카드 UI 렌더링 확인
- [ ] Task 5: kbotown 통합, 타 게시판 영향 없음 확인
