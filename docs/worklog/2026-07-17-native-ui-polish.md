# 작업 로그 — 2026-07-17 (SecondBrain · 네이티브 v1 받은함 UI/UX 정리)

> iCloud·알림 배선(오전·오후, 별도 worklog `2026-07-17-native-icloud-notify.md`)에 이어,
> **받은함을 실제로 쓸 만한 화면으로 다듬은** 세션. 브랜치 `worktree-native-ui-polish`, **PR #3(아직 미머지)**.
> 범위 원칙: 수집/분류를 새로 만들지 않고, 이미 있는 읽기·처리·알림을 화면으로 다듬기만.

## 0. 한 일 요약
- 받은함을 **다크 테마 + 섹션 구조**(원칙·곧 닥칠 것·최근)로 재구성, 탭바(받은함·검색·[+수집]·보관함·원칙) 추가.
- **분류 변경 UI**(종류 아이콘 탭 → 메뉴)를 기존 이벤트 엔진에 연결(레거시 포함).
- **버림(discard) 개념 제거** — discard는 삭제로 통일.
- 웹앱(app.css) 참고 **영역 스타일**(cyan 원칙 / D-day 틴트 카드 / 옅은 최근 줄).
- 접힘/요약 바를 여러 방식으로 시도했으나 **최종적으로 제거**하고 순수 네이티브 스크롤로 확정(아래 §4).

## 1. Core 추가 (순수 함수 + 테스트, 로직은 UI에 안 박음)
- `ItemSchedule.effectiveDay` — resurface 우선/due 시점 단일 진실원. `NotificationPlanner`도 이걸 사용(중복 제거).
- `DDay` — 지남/오늘/미래 버킷 + D-n 계산.
- `InboxSections` — 시점 있음(곧 닥칠 것)/없음(최근) 분할, D-day 오름차순.
- `EventLog` — `set` 파서가 빈 값(`type=`) 왕복 지원(미분류 되돌리기용).
- 테스트 **36 → 44개**: ItemSchedule·DDay·InboxSections + 레거시 타입변경(`legacy:` id 위 `set type=` 병합)·빈 값 왕복.

## 2. App (다크 테마, native/Sources/App)
- `RootView` — 탭바 5개, 다크 강제. `[+수집]`은 placeholder("곧 나옴").
- `InboxView` — 원칙·곧 닥칠 것·최근 섹션(필터 칩은 최근 섹션 고정 헤더). 전 영역 스와이프(삭제·완료·미루기)+컨텍스트 메뉴. 회계 요약줄(합계·표시·원칙·완료·삭제).
- `Theme` — 웹 app.css 다크 토큰 정합(bg/surface/border, radius14, 종류색), `areaStyle`(틴트 그라데이션+테두리), `TypeCatalog`(classify.py TYPE_KO), `SourceIcon`.
- `Components` — DDayBadge·SourceBadge·TypeMenuButton(분류 변경)·TypeGlyph·itemCaption.
- `ArchiveView`(보관함=완료/삭제 2섹션+되돌리기)·`SearchView`(pull 최소)·`PrincipleView`(원칙 전체).
- `InboxModel` 확장 — liveNonDone/doneItems/trashed, 필터, 섹션 계산, `changeType`/`restore`/`restoreFromTrash`. discard→trashed 취급.
- `SampleData` — **DEBUG·시뮬레이터 전용** 시드(렌더 확인용, 릴리스·실기기 미포함).
- `project.yml` — `INFOPLIST_KEY_UILaunchScreen_Generation`(전체 화면, letterbox 방지).

## 3. 분류 변경 — 레거시 안전(사용자 특별 확인 요청)
- 종류 아이콘 탭 → `changeType` → `@ <hlc> | <id> | set type=<v>` append → 재병합.
- 레거시 항목도 동일 경로(`legacy:<hex>` id, `|`·공백 없어 파싱 안전). 실기기에서 68개 로드·필터·삭제 확인 완료.

## 4. 접힘/요약 시도와 최종 결정 (중요 교훈)
사용자 요청으로 "원칙·곧닥칠을 스크롤에 따라 접고 최소 1개는 고정"을 여러 방식으로 시도:
- 오프셋 구동 단계적 접힘(고정 헤더 안에서) → **깜빡임**(List 고정 섹션 헤더가 단일 셀이라, 내용 변하면 셀 전체를 위에서부터 재렌더).
- `scrollTransition`(GPU 페이드) → 부드럽지만 "핀 고정"은 아님.
- 상시 요약 바(원칙1+곧닥칠1) → 동작하나 상단 중복.
- "영역 사라질 때만 요약 줄 표시" → **List가 행의 PreferenceKey/좌표공간/`onScrollVisibilityChange`를 전달 못 해** 감지 실패(디버그로 확인).
- `onScrollGeometryChange`(이건 List에서 동작)로 스크롤 깊이 추정 → 콘텐츠(줄 수) 바뀌면 어긋남.
- **결론(사용자 결정): 접힘·요약 기능 전면 제거.** 순수 네이티브 List 스크롤이 가장 부드럽고 콘텐츠에 강건. 섹션 구조·스와이프·웹앱풍 스타일은 유지.

> 핵심 교훈: **SwiftUI `List`는 행 내부 geometry/preference를 밖으로 안 내보낸다.** 스크롤-위치 기반 정밀 UI가 필요하면 `ScrollView`(+커스텀 스와이프)로 가야 하고, `List`에선 `onScrollGeometryChange`(컨테이너 오프셋)만 신뢰 가능.

## 5. 검증
- Core `swift test` **44개 통과**. iOS·macOS 빌드 통과(반복). 시뮬레이터 렌더 다수 스크린샷 확인.
- 실기기: iCloud 68개 로드·필터·**레거시 분류 변경**·삭제(=버림 포함 10) 확인. 접힘/요약은 실기기 피드백으로 폐기.

## 6. 상태 / 다음
- **PR #3 미머지** — 실기기 최종 확인 후 머지 예정. 브랜치에 20커밋(+1117/−125).
- 남은 자잘한 UI(보관함 회색 항목 등)는 다음에 한꺼번에 정리하기로.
- 다음 큰 것 후보: 수집([+]) 실구현, 알림 탭→항목 점프, done 정리 UI.
