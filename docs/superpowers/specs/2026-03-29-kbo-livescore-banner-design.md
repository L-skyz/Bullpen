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

- **URL:** `https://www.statiz.co.kr` 라이브스코어 페이지 (구현 단계에서 정확한 경로 및 DOM 셀렉터 확인)
- **방식:** URLSession HTTP GET → HTML 파싱 (SwiftSoup 또는 정규식)
- **파싱 결과:** 기존 `KboGame` / `KboTeamScore` 모델로 매핑

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
│ 🔴 LG    3  │  ← 홈팀: 로고 + 팀명 + 스코어 (이긴 팀 볼드)
│ 🔵 KIA   2  │  ← 어웨이팀
│ 잠실        │  ← 구장
└──────────────┘
```

- 카드 너비: ~120pt, 세로: ~130pt
- LIVE 카드: 빨간 테두리 또는 배경 강조
- 스코어 미시작: `-` 표시
- 팀 로고: `AsyncImage`, 실패 시 팀명 첫 글자 원형 폴백

### 3-3. 헤더 바

- 좌: `🏟 KBO` + LIVE N경기 (빨간 점)
- 우: 마지막 갱신 시각 + 새로고침 아이콘 버튼

---

## 4. 갱신 정책

| 상태 | 폴링 간격 |
|------|-----------|
| 라이브 경기 있음 | 30초 |
| 라이브 없음 (예정/종료만) | 5분 |
| 백그라운드 | 중단 (Task 자동 suspend) |
| 포그라운드 복귀 | 즉시 1회 fetch |

- `Task` 기반 폴링 루프 (`Task.sleep`)
- `@Environment(\.scenePhase)` 감지로 포그라운드/백그라운드 전환 처리

---

## 5. 파일 구성

| 파일 | 변경 내용 |
|------|-----------|
| `Services/MLBParkService.swift` | `fetchKboScores() async throws -> [KboGame]` 추가 |
| `ViewModels/KboScoreViewModel.swift` | 신규: 폴링 로직, `@Published var games` |
| `Views/KboScoreBannerView.swift` | 신규: 배너 + 카드 뷰 |
| `Views/PostListView.swift` | `kbotown` 조건으로 배너 삽입 |
| `Models/KboGame.swift` | 변경 없음 |

---

## 6. 스코프 외 (이번 작업에 포함하지 않음)

- 경기 카드 탭 → 상세 경기 화면 이동
- MLB 게시판용 MLB 스코어 배너
- 위젯 / 알림 연동
