# 작업 로그 — 2026-07-21 (MacBook · 성능 이슈 종결 + 탭 튐 진단 착수)

> **재개 한 줄 (집에서 제일 먼저):** `git pull` → `cd native && xcodegen generate` → **탭 튐 진단 빌드를 디버거 없이**
> 실행(⌘R 말고: command line/devicectl 설치 후 홈 탭, 또는 Edit Scheme▸Run▸Info▸"Debug executable" 해제).
> 다른 앱 갔다 **복귀 반복**해 탭 튐 재현 → 화면 상단 **TAB DEBUG** 로그에서 "복귀(scenePhase→active/onAppear) 때 tab이
> 무엇→무엇으로 바뀌는지" 읽기. **⚠️ 이 커밋의 진단 코드는 빌드 미검증(작업 중 종료)** — 빌드부터 확인할 것.

## 1. 성능 이슈 — 종결 (커밋 3aff80b)
- "새 설치 첫 실행 ~10.8s + STT '듣는 중' ~5s"는 **Xcode ⌘R 디버거(lldb attach) pre-main 비용**이었음. 코드·버전 무관.
- 계측: ⌘R premain 9.8s vs 디버거 없이(devicectl) 62ms. baseline A(13caaa9) 9803ms ≈ B(321001f) 9826ms. STT도 디버거 없이는 재현 안 됨.
- **어제 STT·비동기 로드 코드 완전 무죄. 실사용(홈탭/스토어) 빠름.** 전말: `docs/lessons/2026-07-21-perf-cmdr-debugger-premain.md`, 규칙: `CLAUDE.md` §성능 측정 규칙.

## 2. 탭 튐 버그 — 진단 착수 (이 커밋, WIP·미검증)
- **증상 확인(사용자):** **다른 앱 갔다 돌아올 때** 탭이 튐. 목적지는 **매번 다름**(특정 탭 아님).
- **해석/가설:** 코드에서 `tab`을 특정 값으로 쓰는 곳은 `launcher.showCapture→.new` 뿐인데 "매번 다름"과 안 맞음
  → **SwiftUI `@SceneStorage("selectedTab")` 상태복원이 복귀 시 엉뚱하게 되살리는** 정황. (07-20 `@State→@SceneStorage`
  "수정"이 안 먹힌 것도 이 방향과 정합 — @SceneStorage가 해결책이 아니라 범인일 수 있음.)
- **왜 화면 오버레이 진단인가:** 이건 백그라운드/복귀 버그라 **⌘R 디버거로 띄우면 상태복원 동작이 바뀔 수 있음**(성능 건 교훈:
  측정조건이 결과 지배). 그래서 콘솔(⌘R) 대신 **화면에 로그를 띄워 디버거 없는 실사용 조건에서** 본다.
- **심은 것(임시, 실험 후 제거):**
  - `native/Sources/App/TabDebug.swift` — tab/scenePhase 변화를 **UserDefaults에 기록**(프로세스 죽어 복원돼도 유지) + 화면 오버레이용.
  - `RootView.swift` — `tabDebugOverlay`(상단), `.onChange(of: tab)`·`scenePhase` 로그·`.onAppear` 로그, `@State tabDebugEntries`.
  - `project.yml` — `schemes: SecondBrainApp-iOS` 명시 추가 (**재생성 때 iOS 공유 스킴이 자꾸 누락되던 문제 해결**; xcodebuild/Xcode 둘 다 스킴 인식).

## 3. 집에서 할 일 (순서)
1. 위 재개 한 줄대로 **디버거 없이** 빌드·실행 → 탭 튐 재현 → TAB DEBUG 로그 판독.
2. 원인 확정 후 **수정**: 유력안 = `@SceneStorage` → `@AppStorage`(UserDefaults, scene 복원 비의존) 교체, 또는 복원 로직 교정. (추측 말고 로그로 확인 후.)
3. 실사용(복귀 반복)으로 **수정 검증** — "고쳤다" 단정 말고 여러 번 재현 시도로 확인.
4. **진단 제거**: `TabDebug.swift` 삭제 + `RootView.swift`·`project.yml` 정리(수정만 남기고 진단 걷어내기).
5. (그 뒤) STT 실기기 기능 확인 → 사양서 반영, 비동기 로드 유지/되돌림 결정, question UI, ⑥ 레거시 코드 제거.

## 4. 상태
- main = 이 커밋(3aff80b 위 WIP). 성능 기록(CLAUDE.md 규칙·lesson·worklog §6)은 3aff80b에 이미 포함.
- 폰: 순수 최신 B(계측 없음) 설치돼 있음(진단 빌드는 아직 안 깔림).
