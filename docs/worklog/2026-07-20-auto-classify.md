# 작업 로그 — 2026-07-20 (SecondBrain · 자동 분류 Claude API + 토스트/탭복원/AI삭제금지)

> **재개 한 줄:** 자동 분류(Claude API 직접 호출) 구현 — 설정에 API 키(Keychain)·"지금 분류하기"(인라인), 앱 재진입 시 미분류 모아 분류·**화면 중앙 토스트(1.5초)**, 탭 `@SceneStorage` 복원, **AI 삭제 금지**(discard 스킵) 확정까지 main 커밋·push 완료. **다음(내일 MacBook Pro): ①실기기 최종 재확인(discard 수정 후) ②사양서 §1·§3·§0-A + memory-philosophy에 자동 분류·AI삭제금지 반영 ③question UI(공백 직렬화) 후속 ④"총 기억" 정의 재결정.** 살아있는 메모리: `ai-never-discards`, `autoclassify-question-followup`.

## 0. 한 일 요약
worklog·사양서가 가리키던 다음 1순위 **자동 분류(Claude API)**를 구현. 엔진·병합·직렬화 **무변경(순수 가법)**, 코어 64 테스트 유지. iPhone이 Claude API를 직접 호출(§0-A)해 미분류를 §3 프롬프트로 분류하고 결과를 **기존 `.edit` 이벤트 경로**로 append.

## 1. 신규 파일 (App 층, 4종)
| 파일 | 내용 |
|---|---|
| `KeychainStore.swift` | API 키를 **iOS Keychain에만** 저장(§7·classify.py 원칙: 저장소·iCloud엔 안 둠). 앱 전체 로그 호출 0건 — 키·요청·원문이 로그로 새는 경로 없음. |
| `ClassifyPrompt.swift` | §3 `SYSTEM_PROMPT`·SCHEMA를 classify.py에서 **그대로 이식**(살아있는 자산, 규칙 #5). |
| `ClaudeClassifier.swift` | `URLSession` 원시 HTTP로 Messages API 직접 호출(Swift는 SDK 없음 → 스킬 지침). classify.py 요청 형태(opus-4-8·thinking adaptive·`output_config.format` json_schema·system+user) 미러링. HTTP 상태별 한국어 오류. 보내는 건 원문(raw)+오늘 날짜뿐 — 수집 메타(시각·기기·source) 미전송. |
| (통합) `InboxModel` | `unclassifiedItems`·`classifyUnclassified(auto:)`·`classifyFields`. 미분류 전체를 **한 요청**으로 보내고 결과를 검증 후 반영. |

## 2. 결정 (사용자 확인)
- **API 키**: 설정에서 붙여넣기 → Keychain(§7).
- **분류 시점**: 앱 열 때 모아 분류 + 수동 버튼. (백그라운드 자동은 iOS 제약 → §0-A 권장안.)
- **AI 삭제 금지(확정)**: 모델이 `discard`로 분류해도 **반영 안 함**(미분류 보존). 삭제는 사람만·단방향. 메모리 `ai-never-discards`.

## 3. 안전장치 (실사용/사용자 우려 반영)
- **수집·분류 완전 분리**: capture가 항목을 즉시 저장, classify는 읽고 성공 시에만 append. 실패(네트워크/키/타임아웃/깨진 응답)면 아무것도 안 씀 → 항목은 미분류로 **손상 없이 보존**, 크래시 없음(타입화된 오류 catch).
- **반영 전 검증**: type이 §2 밖이거나 discard면 스킵. due/resurface는 `ItemSchedule.parseDay`로 실제 날짜만 씀(weekly/none/깨진 값=시점 없음). "받은 대로"가 아니라 "검증 후 반영".
- **부분 성공 안전**: 한 요청 = 전체. 일부 index만 오면 나머지는 미분류로 남아 다음 스윕 대상. 각 edit 독립이라 롤백 불필요.
- **중복 차단**: `.running`을 첫 await 전 세팅(메인 액터 직렬화) + 수동 버튼 `.disabled` + 분류 후 재로드로 type 생겨 재전송 안 됨.

## 4. UI
- **설정 → 자동 분류**: API 키 SecureField·저장·키 지우기·"지금 분류하기 (N)"(인라인 진행/결과) + footer 안내.
- **자동 스윕 토스트**: `RootView` 중앙 오버레이(카드형, `allowsHitTesting=false`). 진행중 스피너 → 성공/실패 **1.5초 뒤 자동 소멸**. 설정으로 안 끌고 감. (수동 버튼은 토스트 안 씀 — 설정 그 자리 인라인.)
- **탭 복원**: `tab`을 `@State`→`@SceneStorage("selectedTab")`(AppTab에 String raw값). 재진입 시 탭이 보관/설정으로 튀던 버그(iOS 상태복원 충돌) 해결 → 마지막 머문 탭 결정적 복원.

## 5. 잡은 버그
- **재진입 시 자동분류 후 새 기억이 사라지고 카운트 줄던 것**: 원인 = 모델이 discard 분류 → 파이프라인이 삭제 취급(trashed 이동, liveNonDone 감소) + 토스트는 1개로 셈(불일치). 처방 = **discard 반영 금지**(위 §2·§3). 두 증상 동시 해결.

## 6. 검증
- iOS·macOS **빌드 둘 다 성공**. 코어 `swift test` **64개 통과**(엔진 무변경).
- 앱 전체 로그 호출 0건(grep).
- **실기기**: 반복 검증 중 — 키 저장·수동 분류·자동 토스트·탭 복원·discard 보존까지 사용자가 확인하며 버그 3건(탭 튐·토스트 위치·discard 삭제) 발견→수정. **discard 수정 후 최종 재확인은 내일 이어서.**

## 7. 상태
- main 커밋·push 완료. `.xcodeproj`는 XcodeGen 재생성(git 미추적).

## 8. 다음 할 일 (내일 · MacBook Pro)
1. **실기기 최종 재확인** — discard 수정본에서: 수집→재진입 자동분류 후 항목 유지·토스트 카운트 일치·탭 복원.
2. **사양서 반영**(규칙 #2) — §1 입구 "자동 분류는 다음 단계" 갱신 / §0-A "앱 열 때 모아 분류" 구현됨 / §3 또는 memory-philosophy에 **AI 삭제 금지** 원칙 명시.
3. **question UI** — 공백 안전한 필드 인코딩(EventWriter/FragmentParser, merge-design 영향 검토) 뒤 재확인 질문 노출(메모리 `autoclassify-question-followup`).
4. 보류 승계: "총 기억" 대시보드 정의 재결정, 원칙 각인 방식(§3 큰 과제), 완전 삭제·완전 이력 등.
