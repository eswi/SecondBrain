# 작업 로그 — 2026-07-17 (SecondBrain · 네이티브 v1: iCloud 배선 + 알림 실배선 + 실기기 검증)

> 하루에 두 세션. **오전 세션**(iCloud 배선·레거시 id 교정·체크리스트, macOS 실데이터 검증)과
> **오후 세션**(아이폰 실기기 검증 A~D, 알림 실배선 + 실기기 검증 A·B·C, 머지)로 나뉜다.
> 이 로그로 네이티브 v1의 **핵심 3대 조각(코어·iCloud·알림)** 이 실기기 검증까지 완료됐다.

## 0. 한 일 요약
- **iCloud 배선 완성** — 앱이 문서 피커로 고른 iCloud Drive `SecondBrain/` 폴더의 실 `inbox.md`(68개)를 읽고, 행동은 기기 조각에 append. iCloud entitlement 없이(무료 서명 유지).
- **레거시 id 버그 발견·교정** — v0 줄 id의 `|`·공백이 이벤트 줄을 깨뜨려 행동 유실 위험 → 토큰 안전 해시 `legacy:<16hex>`로 교정.
- **아이폰 실기기 검증 통과** — iCloud 양방향 동기화(아이폰↔맥) 확인.
- **알림 실배선 완성·머지** — `NotificationPlanner`(순수 계산)를 `UNUserNotificationCenter`로 실제 등록. 아이폰에서 발화·멱등·정리 검증 통과.

## 1. 커밋 (전부 push, `main == origin/main`)
| 커밋 | 시각 | 내용 |
|---|---|---|
| `3d5cb5e` | 10:32 | worklog: 어제(07-16 저녁) Phase 2·3 세션 **사후 기록** |
| `615340a` | 10:44 | 네이티브 v1: **iCloud 열린 폴더 배선 + 레거시 id 교정** |
| `ba3c6b4` | 10:46 | docs: **아이폰 실기기 검증 체크리스트**(iCloud 배선) |
| `9bc650c` | 12:07 | **Phase 3 배달: 로컬 알림 실배선**(UNUserNotificationCenter) — PR #1 squash |

## 2. iCloud 배선 (`615340a`) — 확정된 방식
- **iCloud Drive 열린 폴더** 방식 채택(앱 ubiquity 컨테이너 아님). 사용자가 문서 피커로 기존
  `iCloud Drive/SecondBrain/` 폴더를 고르면 **보안스코프 북마크**로 지속 접근.
  → **iCloud entitlement 불필요 = 무료 서명(개인 팀) 유지**(유료 $99 안 씀). 웹 v0와 같은 폴더 공존.
- 접근은 `NSFileCoordinator` 조율 읽기/쓰기 + iCloud 다운로드 트리거.
- **읽기**: 폴더의 `inbox*.md`(레거시 `inbox.md` 포함) 전부 병합. **쓰기**: 행동을 이 기기 조각
  `inbox-<deviceId>.md`에만 이벤트로 append → **`inbox.md`는 바이트 단위 불변**.
- 로컬샌드박스·번들 데모 폴백 **제거**(이전엔 `.documentDirectory` 가리킴 — 07-16 worklog §5 지적 해소).

## 3. 레거시 id 교정 (중요)
- v0 줄 id를 `date time|source|raw` **원문** → 토큰 안전 해시 **`legacy:<16hex>`**(FNV-1a)로 변경.
- 이유: 변이 이벤트 줄 형식이 `@ <hlc> | <id> | <verb>` 인데, 원문 id에 `|`·공백이 들어가면
  파서가 줄을 잘못 쪼개 **레거시 항목(내 68개 전부!)의 미루기·삭제가 유실**될 뻔함.
- regression 테스트 추가.

## 4. 알림 실배선 (`9bc650c`, PR #1) — 이번 세션 신규
- **`Sources/App/NotificationScheduler.swift`**(신규): `UNUserNotificationCenter` 얇은 래퍼.
  - 권한 요청(`notDetermined`일 때 최초 1회만 시스템 프롬프트).
  - **멱등 재등록**: 앱이 모든 로컬 알림 소유 → 매번 전부 지우고 다시 등록. 삭제·완료로 계획에서
    빠진 항목은 알림도 자동 소멸. 식별자 `sb:<id>`.
  - 로컬 알림이라 **entitlement 불필요 = 무료 서명 유지**(iCloud와 동일 원칙).
- **`InboxModel.load()` 배선**: 병합 직후 `NotificationPlanner.plan(살아있는 항목)` → `reschedule`.
  파일이 진실원이고 모든 행동이 `load()`를 다시 부르므로 **매 행동마다 알림 자동 재조정**
  (미루기 → 그날 오전 9시 등록, 삭제 → 제거).
- 결정 로직은 어제 만든 순수 `NotificationPlanner`(테스트 36개) 그대로 재사용, App엔 얇은 글루만.

## 5. 검증
### 코어·빌드 (헤드리스)
- `swift test` → **36개 전부 통과**.
- iOS(`generic/platform=iOS Simulator`)·macOS 빌드 **BUILD SUCCEEDED**.

### iCloud 실데이터 (macOS, 오전)
- 진짜 `inbox.md` **68개 로드** 확인. 미루기·삭제 → 조각 파일에 append·재병합 반영,
  **`inbox.md` 바이트 단위 불변** 확인.

### 아이폰 실기기 — iCloud (오후, 체크리스트 A~D)
- ✅ 무료 서명 설치 → iCloud `SecondBrain` 폴더에서 68개 로드.
- ✅ 삭제·미루기 시 `inbox.md` 불변.
- ✅ **아이폰↔맥 양방향 동기화** — 아이폰 삭제·미루기(7/24 날짜 포함)가 Mac 앱에 정확히 반영.

### 아이폰 실기기 — 알림 (오후, 체크리스트 A~C)
- ✅ **A. 권한 팝업** 뜸 → 허용.
- ✅ **B. 실제 발화** — 시계를 07-24 09시로 앞당겨 "받은함 · 곧 닥칠 것" 배너 뜸 확인.
- ✅ **C. 멱등·정리** — A·B 항목 각 1회 발화(중복 없음), **삭제된 C 항목은 미발화**.
- (D. macOS 알림은 선택이라 건너뜀. 코드가 iOS·macOS 공유라 로직 동일, 빌드는 통과.)

## 6. 상태 — v1 핵심 완성
- **코어(SecondBrainCore)**: 이벤트 소싱 병합 엔진·HLC·LWW·삭제정책 P1·레거시 흡수·알림 planner (테스트 36).
- **iCloud 배선**: 열린 폴더 + 보안스코프 북마크, 무료 서명. 실기기 양방향 동기화 검증.
- **알림 실배선**: UNUserNotificationCenter, 멱등 재등록. 실기기 발화·정리 검증.
- 공존 원칙 유지: **분류=웹 v0 / 행동=네이티브**, 원문 텍스트는 손으로 안 고침(레거시 id가 원문 해시).

## 7. 운영 메모 (이번 세션 삽질·환경)
- `gh` CLI 미설치 → `brew install gh` + `gh auth login`(device flow) 후 PR 생성·머지.
- PR #1 머지 시 `--delete-branch`의 **로컬** 정리가 `fatal: 'main' is already used by worktree`로
  실패 — 원격 머지·브랜치 삭제는 정상 완료됨(worktree가 main을 점유해서 생긴 로컬 단계 오류).
- worklog·알림 배선 작업 모두 격리 worktree에서 진행 후 머지(사용자 체크아웃 보호).

## 8. 다음 후보 (미확정)
- 알림 **탭 동작** — 지금은 기본(앱 열기)만. 특정 항목으로 점프.
- 포그라운드 알림 표시(`willPresent` 델리게이트) — 현재 앱 켜져 있으면 배너 억제(iOS 기본).
- macOS 알림 실기기 검증(D).
- done 항목 정리/복구 UI(엔진은 부활 지원).
- 무료 서명 7일 만료 → 재설치 흐름.
