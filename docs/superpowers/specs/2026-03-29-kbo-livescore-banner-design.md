# KBO 라이브스코어 배너 — 디자인 스펙

**날짜:** 2026-03-29
**대상 플랫폼:** iOS (SwiftUI), Bullpen 앱
**범위:** 한국야구(`kbotown`) 게시판 상단 라이브스코어 배너

---

## 1. 목표

`kbotown` 게시판 진입 시 오늘의 KBO 경기 스코어를 상단에 가로 스크롤 카드 형태로 표시한다.
라이브 경기 중에는 자동 폴링으로 실시간 업데이트한다.

---

## 2. 데이터 소스

- **URL:** `https://www.statiz.co.kr` 라이브스코어 페이지
  - ⚠️ 구현 시작 전 Chrome DevTools로 정확한 경로 및 DOM 셀렉터를 먼저 확인한다 (사전 분석 필수 단계)
  - 예상 후보: `https://www.statiz.co.kr/schedule.php` 또는 유사 경로
- **방식:** URLSession HTTP GET → HTML 파싱 (SwiftSoup — 프로젝트에 이미 의존성 존재)
- **파싱 결과:** 기존 `KboGame` / `KboTeamScore` 모델로 매핑

### KboGame.id 합성 규칙
Statiz HTML에 mlbpark의 `linkMatchPage()` 같은 match ID가 없을 수 있으므로, 다음 키를 사용:
```
id = "\(away.name)_\(home.name)_\(today)"   // e.g. "KIA_LG_20260329"
// today = DateFormatter format "yyyyMMdd", timezone "Asia/Seoul" (KST 기준)
```

### KboTeamScore.logoURL
Statiz는 팀 로고 URL을 제공하지 않을 수 있다.
- `logoURL`은 빈 문자열(`""`)로 설정
- 카드 UI는 항상 팀명 첫 글자 원형 폴백을 사용

### KboGame 모델 (기존, 변경 없음)
```swift
struct KboTeamScore {
    let name: String
    let logoURL: String
    let score: String   // "-" if not started
}

struct KboGame: Identifiable {
    let id: String
    let isLive: Bool
    let inning: String      // "4회말", "종료", "18:30" 등
    let location: String
    let home: KboTeamScore
    let away: KboTeamScore
}
```

---

## 3. UI 디자인

### 3-1. 전체 구조

```
PostListView (board == "kbotown")
├── KboScoreBannerView          ← 상단 고정 (List 첫 번째 행)
│   ├── 헤더 바 (타이틀 + LIVE N경기 + 갱신 시각 + 새로고침 버튼)
│   └── ScrollView(.horizontal)
│       └── HStack
│           ├── KboGameCard (경기 1)
│           ├── KboGameCard (경기 2)
│           └── ...
└── ForEach(filteredPosts) ...  ← 기존 게시글 목록
```

### 3-2. 카드 UI (mlbpark `.game_listitem` 스타일 재현)

```
┌──────────────┐
│ [LIVE] 4회말 │  ← 배지 영역: LIVE(빨강) / 종료(회색) / 시간(기본)
│ ──────────── │
│ 🅛 LG    3  │  ← 홈팀: 팀명 첫 글자 원형 + 팀명 + 스코어 (이긴 팀 볼드)
│ 🅚 KIA   2  │  ← 어웨이팀
│ 잠실        │  ← 구장
└──────────────┘
```

- 카드 너비: ~120pt, 세로: ~130pt
- LIVE 카드: 빨간 테두리 또는 배경 강조
- 스코어 미시작: `-` 표시
- 팀 로고: 팀명 첫 글자 원형 (logoURL 항상 빈 값이므로 폴백만 사용)

### 3-3. 헤더 바

- 좌: `🏟 KBO` + LIVE N경기 (빨간 점)
- 우: 마지막 갱신 시각 + 새로고침 아이콘 버튼

---

## 4. 갱신 정책

시간 하드코딩 없이 **스탯티즈 응답 데이터로 폴링 여부를 판단**한다.

| fetch 결과 | 다음 동작 |
|------------|-----------|
| LIVE 경기 있음 | 30초 후 재fetch |
| 예정 경기만 있음 | 5분 후 재fetch (경기 시작 감지) |
| 전부 종료 | 폴링 중단, 배너는 종료 스코어 유지 |
| 빈 배열 (오늘 경기 없음) | 폴링 중단, 배너 숨김 |
| 백그라운드 | scenePhase 감지 시 Task cancel |
| 포그라운드 복귀 | scenePhase 감지 시 Task 재시작 + 즉시 1회 fetch |

- `Task` 기반 폴링 루프 (`Task.sleep`)
- `@Environment(\.scenePhase)` onChange에서 `.active` → Task 시작, 그 외 → Task cancel
- Task는 배경 전환 시 자동으로 멈추지 않으므로, 반드시 명시적 cancel 처리
- 매 fetch 후 결과 상태에 따라 다음 sleep 간격 결정 (위 표 기준)

### 오류 처리
- `@Published var error: String?` 보유
- fetch 실패 시 `error` 설정, 배너 전체 숨김 (게시글 목록 영향 없음)
- 다음 폴링 사이클에서 재시도, 성공 시 `error` 초기화

### Pull-to-refresh 연동
`PostListView`의 `.refreshable` 블록에서 게시글 로드와 함께 `KboScoreViewModel.refresh()`도 호출한다.
배너의 수동 새로고침 버튼도 동일한 `refresh()` 메서드를 호출한다.

---

## 5. 파일 구성

| 파일 | 변경 내용 |
|------|-----------|
| `Services/MLBParkService.swift` | `fetchKboScores() async throws -> [KboGame]` 추가 |
| `ViewModels/KboScoreViewModel.swift` | 신규 (디렉토리 `Bullpen/ViewModels/` 도 신규 생성): 폴링 로직, `@Published var games`, `@Published var error: String?`, `refresh()` |
| `Views/KboScoreBannerView.swift` | 신규: 배너 + 카드 뷰 (오류 시 배너 숨김) |
| `Views/PostListView.swift` | `kbotown` 조건으로 배너 삽입, `.refreshable`에 `refresh()` 추가 |
| `Models/KboGame.swift` | `id` 필드 주석 업데이트: `linkMatchPage` → 합성 키 방식으로 변경 |

---

## 6. 구현 사전 단계

1. Chrome DevTools로 `statiz.co.kr` 라이브스코어 페이지 DOM 분석
2. 경기 행 컨테이너 셀렉터, 팀명, 스코어, 이닝/상태, 구장 셀렉터 확인
3. `fetchKboScores()` 파싱 로직 작성 전에 셀렉터 목록 확정

---

## 7. 스코프 외 (이번 작업에 포함하지 않음)

- 경기 카드 탭 → 상세 경기 화면 이동
- MLB 게시판용 MLB 스코어 배너
- 위젯 / 알림 연동
