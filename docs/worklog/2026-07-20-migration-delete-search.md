# 작업 로그 — 2026-07-20 (MacBook Pro · 삭제확인+검색 / 레거시 UUID 마이그레이션)

> **재개 한 줄:** MacBook Pro로 환경 이관(git pull·xcodegen·iPhone 16 Pro 시뮬 생성) 후 ①삭제 확인 팝업(표준 대화상자 공용화)+검색 실동작(터치→상세·독립 필터), ②**레거시 71개→UUID 일괄 마이그레이션 설계·도구·실행 완료(①백업~⑤실기기 확인, 무손실 검증 6/6)**. 커밋·push 완료(`ccbe262`, main=origin/main). **다음: ⑥레거시 코드 제거(며칠 실사용 뒤 별도) · 탭 튐 버그(최우선 보류, @SceneStorage 처방 안 먹힘) · question UI.** 살아있는 메모리: `legacy-uuid-migration`, `tab-jump-bug-pending`, `build-sim-target`.

## 0. 환경 이관 (MacBook Pro — 다른 기기)
- git pull(어제 mac mini 자동분류 커밋 수신), `cd native && xcodegen generate`로 `.xcodeproj` 재생성. iOS·macOS 빌드 + 코어 64테스트 통과.
- **시뮬**: iPhone 16 Pro 고아(런타임 미설치)뿐 → iOS 26.5 위에 새로 생성. 기본 빌드 타깃=iPhone 16 Pro(이름으로 지정, project.yml엔 안 박힘). 메모리 `build-sim-target`.

## 1. 삭제 확인 팝업 + 검색 (커밋 `54baeb9`)
- **공용 대화상자 추출**: DetailView private였던 대화상자를 `Components.swift`의 `StandardDialog`/`DialogButton`/`ConfirmDialog`로 뽑아 공용화(기억하기·원칙자동도 재사용).
- **삭제 재확인 2경로**: 상세 [삭제하기]=로컬 확인 후 delete+dismiss / 리스트 스와이프·컨텍스트 5곳=`model.pendingDelete` → RootView 오버레이 한 곳에서 공용 팝업. 삭제 로직 무변경(tombstone→보관).
- **검색**: 결과 터치→DetailView(NavigationLink 재사용), FilterChipsBar를 `@Binding`으로 바꿔 살아있는 기억(model.filter)과 검색(독립 @State) 분리, 2단계 필터(원문 일치→타입), query/filter 유지. 범위=live+done(삭제 제외).
- 실기기 확인 완료.

## 2. 레거시 71개 → UUID 마이그레이션 (커밋 `e93e7ee`·`ccbe262`)
- **merge-design급 신중 작업.** 설계 정본 `docs/native/legacy-uuid-migration.md`, 도구 `native/tools/sb-migrate`(앱과 동일 코어 재사용, 별도 SwiftPM → 앱 빌드 영향 0).
- **방식**: 데이터 내 id 리네임(엔진 무변경). 해시 id `legacy:<hex>`→UUID, §7 기기 역산값을 `device` 필드로 동결, 조각의 legacy 참조도 UUID로 치환.
- **실행 5단계(각 단계 정지·보고)**: ①백업(`~/SecondBrain-backup-20260720-1912/`+zip) ②dry-run ③apply(새 디렉터리, 원본 무변경) ④원본 교체(드리프트 검증 후) ⑤실기기 확인.
- **무손실 증명**: 같은 MergeEngine으로 before==after 6/6(항목 수·전단사·상태·id·device·이력). `--stats`로 현재=백업 전 칸 동일. 역대 91 = 살아있는 50 + 보관 41(삭제 24·discard 15·완료 2). 실기기 71개·기억하기 11·원칙 7 그대로.
- **D1 규명**: "68"은 오래된 수 → 실제 71 전부 고유(중복·충돌 0). `edit-policy.md §7`·§4-1 71로 갱신.
- **D2**: iPhone은 이 폴더에 기록 없음(전 이벤트 단일 dev-155f307a). 교체 직전 드리프트 검증도 통과. 마이그레이션 내내 이 MacBook만 사용.

## 3. 검증
- iOS·macOS 빌드 성공, 코어 64테스트 유지(엔진 무변경). 마이그레이션 무손실 검증 통과 + 실기기 확인.

## 4. 상태
- main 커밋·push 완료(`ccbe262`, 로컬=원격). 데이터는 iCloud 전파, 코드는 GitHub. 백업은 ⑥ 전까지 보존.

## 5. 다음 할 일
1. **⑥ 레거시 코드 제거** (며칠 실사용 뒤 **별도** — 마이그레이션과 안 섞음): `Event.legacyID`/`fromLegacy`·`EventLog` id-없는 분기·`CaptureDevice` §7 역산·`DetailView` 원문 잠금·"68" 주석. 데이터는 이미 UUID라 코드만. 메모리 `legacy-uuid-migration`.
2. **탭 튐 버그** (최우선 보류) — `@SceneStorage` 처방이 실제론 안 먹힘, 원인 재진단. 메모리 `tab-jump-bug-pending`.
3. **question UI** — 공백 안전 필드 인코딩 후 재확인 질문 노출.
4. 보류 승계: "총 기억" 정의 재결정, 원칙 각인 방식, 완전 삭제·완전 이력.
