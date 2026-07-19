# 작업 로그 — 2026-07-19 (SecondBrain · 상세 화면 §6 + "확정 → 기억하기" 재정의)

> **재개 한 줄:** 상세 화면(§6)·"기억하기" 재정의·용어 정합화·대시보드 라벨·원칙 기능 + **앱 안 실시간 한국어 STT 음성 수집(온디바이스, 우상단 마이크)**까지 main 커밋·push 완료(`5446995` + 문서 정합), 실기기 확인됨(전사·저장·성역 스탬프·iPhone 16 Pro·음성). **다음: ①자동 분류(Claude API) ②액션 버튼 연동(이 STT에) ③"총 기억" 대시보드 정의 재결정 ④원칙 각인 방식(§3 큰 과제)·원칙 0개 밴드 숨김 검증.**

## 0. 한 일 요약
상세 화면(§6 "편집의 무대")을 처음부터 만들고, 그 과정에서 "확정" 개념을 **"기억하기"**로 재정의했다. §2·§3 원칙(수정≠기억하기, 단방향)은 이름만 바뀌고 그대로. 재확인 팝업은 커스텀 대화상자로 안착.

## 1. 커밋 (main 직접, push 완료)
| 커밋 | 내용 |
|---|---|
| `cd2b4ae` | **feat(core)** 상세 편집 엔진 — `EditDiff`(draft 커밋 diff, confirmed 미포함) + `CaptureDevice`(§7 기기 역산) + `ResolvedItem: Hashable` + 테스트 2종. 코어 50→62 |
| `a51be75` | **fix(app)** macOS 빌드 복구 — `SettingsView`의 `.insetGrouped`를 `groupedListStyle()` 플랫폼 가드로(직전 59b4d71 유입 파손) |
| `3f2873d` | **feat(app)** 상세 화면(§6) — 편집의 무대 + "기억하기" + 커스텀 재확인 대화상자. `DetailView` 신규, `InboxModel`(commitEdits·historySummary), 행 탭 배선(InboxView·LivingView) |

## 2. 상세 화면 설계 요점 (정본 = edit-policy.md)
- **draft 편집**: 분류·시점 수정은 [저장] 전까지 로컬에만. 커밋 시 이벤트 1개 = 이력 한 묶음. 병합 엔진 무변경.
- **2층 구조**: 기본정보(원문🔒 + 메타: 언제·기기·방식) 아래 **[기억하기]**(미기억에만 노출, 최소 관문). 맨 아래 필수 바 **[삭제하기] … [취소][저장]**.
- **"확정" → "기억하기"**: "이 기억을 (단기/장기) 기억하기로 한다"는 결정. 단방향(되돌리려면 삭제).
- **단방향 삼중 차단**: 엔진 unconfirm 없음 + `model.confirm` 멱등 + `isRemembered`면 버튼·배지 미렌더.
- **재확인**: 표준 alert는 제목 크기 못 키움 → **커스텀 가운데 대화상자**("정말로 기억하시겠습니까?", 제목 크게). → 이 스타일을 **앞으로 확인·경고 팝업 표준**으로 채택(메모리 `confirm-dialog-style` 저장).
- 원문 잠금(§8) 유지, [저장]은 분류·시점만.

## 3. 검증
- 코어 `swift test` **62개 통과**(신규 EditDiff 8·CaptureDevice 4 포함).
- iOS·macOS **빌드 둘 다 성공**.
- **실기기(iPhone) 동작 확인 완료**(사용자): 탭→상세, draft 저장/취소, 기억하기 대화상자, 삭제하기, 메타(방식) 표시, 하단 바.

## 4. 용어 정합화 "확정 → 기억하기" (`3a14e69`)
- **개념·이름만 변경**, 원칙(수정≠기억하기, 단방향)은 그대로. [확인]→[저장]도 함께.
- **골라내기 원칙**: 기억-확정 개념만 "기억하기"로. 일반 뜻("확정된 아키텍처/범위", "정책을 확정=결정", "시각 자동 고정")은 유지.
- 문서 3종: `edit-policy.md`(제목·§1~3·§4 필드 리워드 + 용어 노트), `memory-philosophy.md`(흐름·§2·§4·§5·§6·관계, §6은 실제 2층 배치로 갱신), `second-brain-v0-spec.md`(항목-행동 표현만; §2·§3 프롬프트 불변).
- 앱 라벨: 대시보드 "미확정·확정"→"미기억·기억함", 스와이프·컨텍스트 "확정"→"기억하기", 설정·안내문. (엔진 식별자 confirm/confirmed 불변.)

## 4-b. 대시보드·설정 라벨 정합 (`82a8830`·`779cd98`)
- 대시보드 숫자는 각 영역 개수를 세므로 라벨도 **영역 이름**으로: "미기억"→"새 기억", "기억함"→"살아있는 기억"(동사 활용 아님). 설정 현황 행도 동일 통일 → 앱 전체가 세 영역 이름으로 일관.
- `memory-philosophy.md §5` 대시보드 설명도 같은 라벨 + 이유 명시.

## 4-c. 원칙(principle) 정식화 (`6470b3f`)
- **개념 정본 = `memory-philosophy.md §3`** 전면 정식화: 살아있는 기억 중 습관 체화 대상. 지정 무제한·**동작 상위 N개(기본 3, 상한이지 강제 아님)**. 지정=분류 principle(원영역서 빠짐), 해제=분류 바꿈(독립 버튼 없음, 일부러 불편). 두 자리(상단 상위 N 띠 / **원칙 목록 화면=신규·미구현**). 순서=포함 순서→드래그. 미결(큰 과제)=각인 방식.
- **구현된 것 하나**: 미기억 항목을 원칙으로 지정+[저장] → "'기억하기'로 자동 결정됩니다" **표준 안내 팝업** → 저장+자동 기억하기. 표준 대화상자를 **공용 헬퍼 `standardDialog`/`dialogButton`로 추출**(DetailView 내, 2곳 재사용). 나머지 원칙 기능(목록·N·순서·상세진입)은 **미구현 설계**로 문서 명시.
- spec: 옛 3영역 서술에 §3 포인터 플래그만. §2·§3 프롬프트·merge-design 불변.

## 4-d. 원칙 기능 구현 (`ee7b4f8` + 문서 정합)
- **엔진 무변경**: 순서는 `order` 필드(정수, LWW). 드래그 재정렬 → 새 순서대로 0..n-1 재부여(바뀐 것만, `appendBatch`로 1회 재로드). 미지정 기본값 = 포함 순서(type=principle 세팅 HLC, `allEvents`서 계산). `InboxModel.orderedPrinciples`/`reorderPrinciples`.
- **원칙 목록 화면**(`PrincipleListView` 신규): 전체 순서대로, 꾹 눌러 드래그(편집모드 없이 — 실기기 동작 확인), 항목 터치 → DetailView 재사용, 상위 N=동작(그 아래 "대기" 흐리게).
- **상단 밴드**: 상위 N만, 밴드 터치 → 목록(Button+NavigationPath로 chevron 제거). 별→"원칙" 제목 앞, 항목 1·2·3 번호, 바탕 균일 틴트(그라데이션 제거).
- **N 설정**: SettingsView Stepper(기본 3, 1–10, 최소 1), `@AppStorage("principleActiveCount")`. 상한이지 강제 아님.
- `memory-philosophy.md §3·§5` 구현 상태 "구현됨"으로 정합. (`.xcodeproj`는 XcodeGen 재생성 — 새 파일 인식 위해 `xcodegen generate` 했음, git 미추적.)

## 4-e. 앱 안 음성/텍스트 수집 — 실시간 한국어 STT (`5446995`)
- **네이티브 create**: `InboxModel.capture(text:source:)` — UUID 항목, 시각·기기·방식을 create에 성역 스탬프, `inbox-iphone-*.md`에 append. 자동 분류 뒤로 → 미분류로 "새 기억들".
- **Core(가법적)**: EventWriter create 블록에 `device`; CaptureDevice `currentLabel()`/`label(stored:)`. 테스트 62→64.
- **STT**: `SpeechCapture` — SFSpeechRecognizer ko-KR, **온디바이스 강제**(프라이버시 §7). iPhone 16 Pro에서 ko-KR 온디바이스 지원 확인. 권한 = 마이크·음성인식 usage string(entitlement 불필요, 무료 서명).
- **크래시 해결(핵심 교훈)**: `@MainActor` 클래스면 콜백 클로저가 격리돼 오디오 스레드 실행 시 `dispatch_assert_queue_fail` 크래시(실기기 3회 재현, 스크린샷으로 진단). → **@MainActor 제거 + `@unchecked Sendable` + @Published·엔진 조작 전부 메인 큐 dispatch**로 근본 해결. (Swift 6 strict concurrency + AVAudioEngine/Speech 패턴.)
- **UI**: `CaptureSheet`(열리면 바로 STT→실시간 전사→교정→저장), 헤더 폴더→마이크(폴더는 설정으로). `memory-philosophy §5` 수집 서술 갱신.

## 5. 상태
- main = origin/main = `5446995`(+문서 정합 커밋). working tree clean. worktree·브랜치·열린 PR 잔재 없음.

## 6. 다음 할 일
1. **자동 분류(Claude API)** — 수집된 새 항목 자동 분류(다음 단계로 미뤄둔 것).
2. **액션 버튼 연동** — 아이폰 16 Pro 액션 버튼 → 이 STT 수집(App Intent/URL 스킴, 익스텐션 불필요·무료 서명 OK — 조사 완료).
3. **"총 기억" 대시보드 정의 재결정** (현재 = 살아있는 전체).
4. 원칙 **각인 방식**(§3 큰 과제) · 원칙 0개 밴드 숨김 검증.
5. 보류: 완전 삭제(edit-policy §8), 완료취소 재확인(§5) 강제, 원문 성역 코드 강제, 완전 이력(§4-4), 원문 여러 줄 보존(현재 수집은 줄바꿈→공백), 대화상자 헬퍼 앱 전역 공용화.
