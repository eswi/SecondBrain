# 작업 로그 — 2026-07-16 저녁 (SecondBrain · 네이티브 v1 Phase 2·3)

> 이 세션은 **MacBook Pro**에서 진행됐고, 작성 당시 worklog가 누락됐다. 2026-07-17에
> 커밋 5개(`3e6ad81`→`2247d0b`)와 코드를 되짚어 사후 기록한다.
> 같은 날 오전 `2026-07-16.md`(Mac mini 환경세팅)와는 **다른 세션**이다.

## 0. 한 일 요약
네이티브 v1의 **Phase 2(합치기 엔진 + 읽기 + 쓰기)** 와 **Phase 3(알림 순수로직)** 을 통째로 구현.
Phase 1(걷는 뼈대)에서 실제 데이터·항목 행동·다기기 병합까지 코어를 채웠다. 코어 테스트 35개 통과.

## 1. 커밋 (전부 push, `main == origin/main`)
| 커밋 | 시각 | 내용 |
|---|---|---|
| `3e6ad81` | 18:41 | Phase 2 **합치기 엔진(이벤트 소싱)** + 설계문서 `docs/native/merge-design.md` + 테스트 21개 |
| `e894bdb` | 19:04 | Phase 2 **읽기 경로**: 다중 조각 로드·병합 → 앱 표시 |
| `5f20f3a` | 19:40 | Phase 2 **쓰기 경로**: 항목 행동(삭제·완료·미루기)을 이벤트로 append |
| `2ea1b95` | 19:55 | native 서명 Team(`4W2HHUZTYT`)을 `project.yml`에 명시 — 자동 서명, 재생성·타 Mac 유지 |
| `2247d0b` | 20:29 | Phase 3 **알림**: 순수 `NotificationPlanner` + 테스트 |

## 2. 확정된 설계 결정 (`docs/native/merge-design.md`, 결정일 07-16)
> 07-16 오전 worklog가 "Phase 2 착수 전 필수 미결"로 지목한 **"수정 이벤트 범위"** 가 여기서 해소됐다.
- **이벤트 소싱**: 조각 파일 `inbox-<device>.md` = 기기별 **append-only 로그**(평문·grep 가능). 각 기기는 자기 파일에만 append → iCloud "마지막이 이긴다" 충돌 원천 차단.
- **합치기 엔진 = 순수 함수** `merge([Event]) -> MergeResult` — **결정적·순서무관·멱등**.
- 항목 id = **UUID 영구불변**(내용 해시 id 금지 — 원문 수정 시 사슬 끊김).
- 순서 = **HLC(Hybrid Logical Clock)** 전순서 `(wall, counter, deviceId)` → 인과성 보장·무승부 없음.
- 필드 병합 = **항목별·필드별 LWW**(다른 필드 동시편집 무손실, 같은 필드만 HLC 최신 승).
- 삭제 = **정책 P1 확정**: 항목의 최고 HLC 이벤트가 delete면 숨김, 그보다 최신 편집이 오면 **자동 부활**. append-only라 진 이벤트도 보존(복구 UI 가능).
- 레거시 v0 편입: id 없는 줄은 내용해시 `legacy:` id + `deviceId="legacy"`, `wall=0` 최하 우선순위 create로 흡수.

## 3. 코드 지도 (SecondBrainCore = 순수, Sources/App = 플랫폼)
**코어:** `HLC.swift`(클록·전순서) · `Event.swift`(create/edit/delete/undelete + fromLegacy) · `EventLog.swift`(평문→이벤트 관용 파서, 깨진 줄 스킵) · `EventWriter.swift`(이벤트→평문 직렬화 + append-only) · `MergeEngine.swift`(병합) · `InboxStore.swift`(디렉터리 `inbox*.md` 로드·병합) · `NotificationPlanner.swift`(시점→알림계획, 순수).
**앱:** `InboxModel.swift`(상태 + 행동→이벤트 append→재읽기) · `InboxListView.swift`(스와이프 삭제/완료/미루기) · `DeviceStore.swift`(기기 id·HLC 영속, 조각 파일 위치).

## 4. 검증
- `swift test` → **35개 전부 통과**(MergeEngine 21 · EventWriter · InboxStore · NotificationPlanner · FragmentParser 등).
- 앱은 **번들 2기기 데모**(`inbox-iphone.md`/`inbox-mac.md`)로 읽기·병합·스와이프 행동 동작.

## 5. 아직 안 된 것 (중요 — 다음에 헷갈리지 말 것)
- ⛔ **iCloud 배선 없음.** `DeviceStore.documents()`가 iCloud가 아니라 **앱 로컬 샌드박스**(`.documentDirectory`)를 가리킴. 코드 전체에 ubiquity/iCloud 참조·entitlement 없음.
- ⛔ **실 데이터 미연결.** 실 `inbox.md`(iCloud Drive `SecondBrain/`, 07-16 기준 **68개**)를 앱이 안 봄. 레거시 편입 *능력*은 있으나(엔진·test20) 그 파일을 가리키는 런타임 경로가 없음.
- ⛔ **알림 실배선 없음.** `NotificationPlanner`는 순수 계산만 — `UNUserNotificationCenter`·권한요청·스케줄링이 앱에 없음("계획은 나오지만 울리진 않음").
- ❓ **실기기 검증 기록 없음.** 시뮬레이터 BUILD SUCCEEDED는 이 커밋들 *이전* 기록. 실 아이폰/맥 append·구동 확인 미문서.

## 6. 다음 단계 (07-17 논의 시작)
- **iCloud 배선 + 레거시 68개 실편입**이 ①(연결)·③(쓰기 반영)을 진짜로 만드는 핵심. 방식 확정 후 착수 예정 — 특히 (a)조각 파일이 iCloud "어디"에 사는가(앱 컨테이너 vs iCloud Drive 열린 폴더), (b)기존 inbox.md 편입, (c)웹 v0 공존 기간·방식.
- 참고: iCloud 컨테이너(ubiquity) entitlement는 **유료 Apple Developer 멤버십** 필요 가능성 — 무료서명 원칙(설계 §6)과 충돌 여부 배선 전 확인 필요.
