# 작업 로그 — 2026-07-21 (mac mini · 탭 튐 버그 해결 + 진단 제거)

> **재개 한 줄:** 탭 튐 종결됨(원인=홈 제스처 중 하단 탭바 스침, 정상 시스템 동작). 다음은 worklog §4
> "남은 일" — STT 실기기 기능 확인 → 사양서 반영, 비동기 로드 유지/되돌림 결정, question UI 후속, ⑥ 레거시 코드 제거.

## 0. 상태 맞추기 (집→mac mini)
- `git pull` 로 집 커밋 3개 수신(`321001f..ee156f9`). 성능 이슈 종결(3aff80b) + CLAUDE.md 성능 규칙 + 탭 튐 진단 WIP(ee156f9) 포함.
- `xcodegen generate` 재생성, 스킴 3개(iOS/macOS/Core) 인식 확인.
- **WIP 빌드 미검증분 검증**: 진단 코드 오류 없음 — iOS/macOS 빌드 exit 0, 코어 테스트 64/64 통과.

## 1. 탭 튐 버그 — 근본 원인 확정 + 해결
- **진짜 원인**: `@SceneStorage` 복원도 앱전환기 스냅샷도 아니고, **홈으로 나가려 하단을 쓸어 올릴 때 손가락이
  하단 탭바 버튼을 스치며 그 탭이 선택**되던 것. 애플 버그/TabView 오용 아님 = 정상 시스템 동작 + 하단 탭바 UX 엣지.
- **확정 방법**: 디버거 없는 실사용 조건에서 화면 오버레이 로그 판독 + 나가는 방법 A/B(오른손/왼손 스와이프,
  톱 제어센터, 전원버튼). 결정타 = **전원버튼(터치0)이면 백그라운드 내려가도 안 튐 vs 홈스와이프면 튐**.
- **전말/2×2 표/원칙**: `docs/lessons/2026-07-21-tab-jump-home-gesture-touch.md`.
- **수정**(`native/Sources/App/RootView.swift`):
  - `@State stableTab` — scene이 `.active`일 때의 탭 변경만(=진짜 사용자 선택) 기억.
  - `onChange(of: tab)` — `.active` 아닌데 stableTab과 달라지면(우발적 선택) 화면 밖일 때 즉시 원복.
  - `onChange(of: scenePhase)` — 복귀 시 보강 원복. `onAppear` — 복원된 탭을 기준값으로.
  - 원복은 `Transaction.disablesAnimations`로 **무애니메이션**(첫 시도에서 복귀 시 인디케이터 슬라이드가 보였던 걸 해결).
  - 교훈: SwiftUI 상태 타이밍은 **Binding setter(mid-render, stale)가 아니라 onChange(확정 후)에서 판단**해야 함.
- **실기기 검증(사용자 확인)**: 튐/REVERT/RESTORE 로그로 동작 확인 → 진단 제거 후 "정상, 안 튐, 깜빡임 없음, 오버레이 사라짐" 확인.

## 2. 진단 코드 제거
- `TabDebug.swift` 삭제. `RootView.swift`에서 오버레이·복사/지우기 버튼·로그·`tabDebugEntries`·UIKit/AppKit import 제거.
- 수정 로직(stableTab/원복)만 남김. `project.yml` 스킴 명시는 유지(진단 아님, 스킴 누락 방지용).
- 제거 후 재빌드·재검증: iOS/macOS exit 0, 코어 64/64, 실기기 육안 정상.

## 3. 상태
- main = 이 세션 커밋(진단 제거 + 탭 튐 수정). `.xcodeproj`는 xcodegen 산출물이라 미추적.
- 폰: 진단 없는 최종 빌드 설치·검증됨.

## 4. 다음 할 일 (순서)
1. **STT 이어받기 실기기 기능 확인** → 사양서 반영 여부 판단.
2. **비동기 로드(a08d3e4) 유지/되돌림 결정** — 성능 건 종결됐으니 유지가 기본, 재확인만.
3. **자동분류 question 필드 후속** — 공백 직렬화 미지원으로 아직 파일에 안 씀(미분류 보존 원칙과 연계).
4. **⑥ 레거시 코드 제거** (마이그레이션 안정화 후).
