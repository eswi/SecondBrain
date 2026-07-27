# SecondBrain — 인수인계 노트 (HANDOFF)

> 생성: 2026-07-26 (mac mini). 저장소 전체 훑어 작성. **추측 배제 — 각 항목에 근거 파일 경로·커밋 표기.**
> 정본 문서는 그대로 두고, 이 문서는 **현재 상태의 지도**다. 상충 시 각 정본(사양서·정책 문서)이 우선.
> 두 층: 웹 v0(PWA, `app.js`, iCloud `inbox.md` 실사용) · **네이티브 v1**(`native/`, Swift+SwiftUI). 이 노트는 v1 중심.
> **네이티브 v1 대상 플랫폼 = Mac 앱 + iPhone 앱 둘 다**(iOS 전용 아님). 하나의 코드베이스에서 두 타깃(`SecondBrainApp-iOS`·`SecondBrainApp-macOS`)을 빌드하며, 진입점·뷰를 공유하고 플랫폼 차이는 `#if os()`로 분기한다. 근거: `native/project.yml`(두 타깃, deploymentTarget iOS/macOS 26.0), `native/Sources/App/SecondBrainApp.swift`("iOS·macOS 공유"), **`second-brain-v0-spec.md`**(**저장소 루트**에 위치 — 다른 정본 문서는 `docs/native/`에 있으나 이 사양서만 루트) §0-A("v1 = Mac 앱 + iPhone 앱, 둘로 국한"). iPad·Windows는 나중 확장(설계가 막지 않음).

---

## 1. 프로젝트 철학 (3~5줄)

근거: `docs/native/memory-philosophy.md` §0~§1.

- **SecondBrain은 to-do 앱이 아니다.** 근본 고통은 "내가 무엇을 잊었는지조차 모른다" — 당장 할 일이 아니라서 to-do에선 버려지는 것들(스친 생각·파편·직관·들은 지식)을 지킨다. 그래서 **"버림 편향 금지"**가 원칙. (`memory-philosophy.md` §0)
- 느슨해진 자연 기억의 두 작동(recall·연결)을 **인위적으로 대신 해주는 도구** → "살아있는 기억". (§1)
- '살아있는 기억'의 진짜 역할은 저장이 아니라 **적절한 순간에 다시 들이밀기(refresh/push)** — 날짜·날씨·키워드 등 실마리로 관련 기억을 꺼내 보여준다. 바깥(기사·노래)까지 끌어오는 능동 에이전트. (§1)
- 수집의 목적 = 단순 보관이 아니라 **미래 refresh의 연료 축적.** (§1)

**정본 문서 전체** (각 문서 머리말·`memory-philosophy.md` "관계" 절 기준. 경로 표기):

| 정본 | 역할 (한 줄) | 근거(머리말) |
|------|------------|------|
| `second-brain-v0-spec.md` (**저장소 루트**) | 아키텍처 정본 — 데이터 형식·입구·빌드 3층. 아래 문서들을 링크로 가리킴 | §0-A·"관계" |
| `docs/native/memory-philosophy.md` | "이 앱은 무엇인가" — 존재 이유·기억 3영역·화면 개념의 정본 | "관계" 절 |
| `docs/native/edit-policy.md` | 편집·기억하기·시간 정책의 "왜"의 정본 | `memory-philosophy.md` "관계" 절 |
| `docs/native/merge-design.md` | 병합 엔진의 "왜"의 정본 ("코드보다 이 문서가 규칙의 정본") | 머리말 |
| `docs/native/photo-capture-design.md` | 사진·공통 미디어 인프라 + 유연층 첫 분류(주차) 설계 정본 | 머리말 "정본 위치" |
| `docs/native/audio-capture-design.md` | 음성 원본 보존(녹음·저장·다시 듣기) 설계 정본 | 머리말 "정본 위치" |

**정본 아님(참고 문서):** `docs/native/classification-redesign-open-questions.md` — 머리말이 "논의(결정·미결)…여기 적힌 결정도 아직 **문서상 결정**이지 코드 반영이 아니다"라 밝히므로 **정본이 아닌 논의·결정 기록**. 분류 재설계 결정(D1~D5)·미결(O1~O4)의 근거로만 인용. (`legacy-uuid-migration.md`도 설계+실행 기록 문서.)

---

## 2. 확정된 용어 정의

| 용어 | 정의 | 근거 |
|------|------|------|
| **기억하기** (구 "확정") | 사람이 이 기억을 살려두겠다는 **명시적 선언**. 최종 지위 승격의 유일한 길. **단방향**(되돌리려면 삭제). 2026-07-19 개명. | `edit-policy.md` §1~3, 용어절 |
| **[저장]** (구 "[확인]") | **내용 수정 마무리**("이 수정을 반영한다"). 기억하기와 별개 — 저장해도 미기억일 수 있음. | `edit-policy.md` §2 |
| **성역 (불변)** | 최초 수집 **시각·기기·방식**, 원본 미디어(음성·사진)는 절대 안 고침. "원본 미디어=불변, 텍스트 층=가변." | `edit-policy.md` §4-1·§6; `second-brain-v0-spec.md` §1 |
| **세부정보 = field / 그릇** | 모든 기억이 공유하는 **공통 이벤트 소싱 `[String:String]` fields + 미디어 포인터**. 분류가 늘어도 그릇 불변. | `docs/native/photo-capture-design.md` §2·§6; `memory-philosophy.md` §7; 코드 `native/SecondBrainCore/Sources/SecondBrainCore/Event.swift` |
| **분류 = 그릇 위의 정의** | 분류는 새 구조가 아니라, 각 세부정보의 **쓸지·제목(=의미)·동작·누가 값 정하나**를 정하는 정의(코드로). | `memory-philosophy.md` §7-1 |
| **question** | `info-action`인데 "구체적으로 뭘·언제 할지"가 불명확할 때 **자동분류(§3)가 붙이는 한 줄 재확인 질문**(불명확 아니면 빈 문자열). 공백이 있어 **`fields.v1` 편집 블록으로 직렬화**돼 파일에 저장(앱 재실행에도 유지)되고, 상세 화면에 **"확인이 필요해요" 카드(읽기전용)**로 뜬다. | `native/Sources/App/ClassifyPrompt.swift`(L19·L52); `ClaudeClassifier.swift`(L10 `question`); 커밋 `f80724c`(`InboxModel.classifyFields`·`DetailView` L69 `questionSection`) |
| **조각 파일** | 기기별 `inbox-<device>.md`(append 전용). 각 기기는 **자기 파일에만** 씀 → iCloud "마지막이 이긴다" 원천 회피. 레거시 `inbox.md`는 불변. | `second-brain-v0-spec.md` §0-A |
| **HLC** (Hybrid Logical Clock) | 이벤트 전순서 키 `(wall, counter, deviceId)` — 무승부 없는 완전한 전순서. | `docs/native/merge-design.md` §2 |
| **LWW** (Last-Writer-Wins) | 항목별·**필드별** 레지스터. 다른 필드 동시편집=둘 다 반영(무손실), 같은 필드 충돌만 HLC 최신 승. | `merge-design.md` §3 |
| **레거시 id** | v0 줄에 `legacy:<16hex>`(FNV-1a 해시) 부여. `|` 깨짐 방지 + 최하 우선순위 편입. | `merge-design.md` §1; `SecondBrainCore/.../EventLog.swift` |
| **confirmed** | 기억하기의 코드 표현 = **OR-머지(grow-only)** — 하나라도 true면 영원히 true(단방향 이중 보장). | 커밋 `f63cf5d`; `SecondBrainCore/.../MergeEngine.swift` |
| **source** | 입구 종류: voice / web / doc / chat / mail / meeting / image. | `second-brain-v0-spec.md` §1 |
| **type (§2 6종)** | promise·event·info-action·info·idea·principle (+ 미분류 nil). `discard`는 **개념 제거 → 삭제 취급**. | `native/Sources/App/Theme.swift`(`TypeCatalog`); `second-brain-v0-spec.md` §2 |
| **분류 2층 구조** (구 개념) | 2026-07-23 정한 구분: **기본층**(고정 6 = §2, 시스템 논리가 기대는 뼈대) + **유연층**(사람이 자유롭게 추가/삭제하는 살점). 공통 그릇이 두 층 모두 받음. → **`memory-philosophy.md` §7에서 "모든 분류 평등"으로 재구성됨**(층 구분 폐기). 재구성 이유: 분류를 코드로 고정하면(§7) 층을 나눌 필요 없이 모든 분류가 그릇 위 정의로 평등. | `classification-redesign-open-questions.md` D1(→§7 포인터 포함); `memory-philosophy.md` §7 |
| **유연층** (구 개념 → D1에서 흡수) | 한때 기본층(§2 6종) 밖 분류를 담던 별도 레지스터 `FlexTypeCatalog`(주차위치 하나). **§7 Stage D1(`84f6d2f`)에서 `ClassCatalog`(모든 분류 평등한 한 목록)로 흡수·삭제됨** — 층 구분 폐기. 이제 주차도 6종과 나란히 한 항목. 자동분류는 **지금도** 주차(유연층 출신)를 안 찍음(수동 지정만 — O4 "아직 안 함"). | `native/Sources/App/ClassDef.swift`(`ClassCatalog`·`ClassDef`)·`ClassRegistry.swift`; 커밋 `84f6d2f`; `classification-redesign-open-questions.md` O4 |
| **소비 3방식** | pull(검색) · push(적시 재노출) · ambient(원칙 상시). | `second-brain-v0-spec.md` §0-A·§5 |
| **AI 삭제 금지** | 자동분류가 `discard`로 판단해도 반영 안 함 → 미분류 보존. 삭제는 사람만·단방향. | `second-brain-v0-spec.md` §0-A; `memory-philosophy.md` §5 |

---

## 3. 구현 완료된 기능

근거: `native-v1-state` 메모리 · 각 커밋 · worklog. 코어 테스트 `swift test` **71개 통과**(2026-07-25 확인) — SwiftPM 패키지라 **macOS 호스트에서 실행**(iOS 기기/시뮬 아님). 코어 로직은 플랫폼 무관이나 **실행 호스트는 Mac**이다.

> "검증 플랫폼" = 저장소에 **명시된 근거**로만 표기. 근거 없으면 **미확인**(구현은 됐어도 검증 기록이 없다는 뜻). "실기기"는 이 프로젝트에서 iPhone 16 Pro(worklog·`docs/native/iphone-verify-checklist.md`).
> **"코어 테스트" = SwiftPM `swift test`로 macOS 호스트에서 실행**(iOS 아님) — 코어 로직은 플랫폼 무관이나 실행 호스트는 Mac이다. 즉 "코어 테스트" 표기는 곧 **macOS 호스트 실행**을 뜻한다. 근거: `native/SecondBrainCore/Package.swift`(주석 "`swift test`로 CLI에서 검증"), 실행 로그 타깃 `arm64-apple-macos`, CI 없음(`.github/workflows` 부재).

| 기능 | 상태 | 검증 플랫폼 | 근거 |
|------|------|-----------|------|
| **코어 병합 엔진** (HLC 전순서·필드별 LWW·삭제정책·레거시 흡수·직렬화·알림 planner) | ✅ | **코어 테스트**(71) + **Mac**(실데이터 `inbox.md` 68 로드·쓰기·불변) | `native/SecondBrainCore/`; `merge-design.md`; 메모리 [[native-v1-state]]("검증됨(실데이터, macOS)") |
| **iCloud 배선** (조각 파일 읽기·병합, 자기 조각에만 append, `inbox.md` 불변, 무료 서명) | ✅ | **iPhone 실기기** + **Mac**(실데이터 로직) | 커밋 `615340a`; `docs/native/iphone-verify-checklist.md`; [[native-v1-state]] |
| **로컬 알림 실배선** (resurface/due 날짜 오전 9시, 멱등 재등록) | ✅ | **iPhone 실기기** + **코어 테스트**(planner). **Mac(D) 미검증**(선택이라 건너뜀) | 커밋 `9bc650c`; `docs/native/notify-verify-checklist.md`(D "선택"); `NotificationScheduler.swift` |
| **기억하기(confirm) 엔진** (OR-머지 단방향) | ✅ | **코어 테스트**(ConfirmTests) + **iPhone 실기기**(세 영역 흐름: 기억하기→살아있는 기억) | 커밋 `f63cf5d`; [[native-v1-state]] |
| **세 영역 UI** (새로운·살아있는·보관된 기억 + 대시보드 5숫자, 시점 유무가 최상위 축) | ✅ | **iPhone 실기기** | 커밋 `59b4d71`; `memory-philosophy.md` §5; `InboxView.swift`/`LivingView.swift`/`ArchiveView.swift` |
| **원칙(principle)** (목록 화면·ambient 띠·상위 N 각인·드래그 정렬) | ✅ 구현(각인 "방식"은 미결) | **iPhone 실기기**(ambient 띠, 세 영역 검증에 포함) · **목록·드래그·'0개 밴드숨김' 미확인**(B2) | `memory-philosophy.md` §3(주의); `PrincipleListView.swift` |
| **자동분류** (pull-to-classify, Claude API 직접 호출, §3 프롬프트, 키체인, AI 삭제금지) | ✅ 구현 | **미확인**(스윕 자체 실기기 검증 기록 없음). 단 **관련 question 배선은 iPhone 실기기**(커밋 `f80724c`) | `second-brain-v0-spec.md` §0-A; `ClaudeClassifier.swift`/`ClassifyPrompt.swift`/`KeychainStore.swift`; `docs/worklog/2026-07-24-macmini.md` |
| **수집** (온디바이스 한국어 STT, 텍스트, App Intent·액션버튼) | ✅ 구현 | **미확인**(실기기 검증 기록 없음) | `CaptureSheet.swift`/`SpeechCapture.swift`/`CaptureIntents.swift`; `memory-philosophy.md` §5 |
| **상세 화면** (원문·성역 메타·[기억하기]·시간설정·삭제 재확인 대화상자) | ✅ 구현 | **iPhone 실기기**(삭제·기억하기·사진·주차 흐름) | `memory-philosophy.md` §6; `DetailView.swift`; worklog 2026-07-24 |
| **검색** (원문 부분일치 + 필터, 상세 재사용) | ✅ 구현 | **iPhone 실기기**(필터 재사용 E 검증) | `SearchView.swift`; 커밋 `f79e69a` |
| **편집 이벤트 완전형** (삭제·완료·미루기 + **분류변경 `set type=`**, 레거시 안전) | ✅ | **iPhone 실기기** + **코어 테스트** | `second-brain-v0-spec.md` §0-A; `EventWriter.swift`; `iphone-verify-checklist.md` C |
| **사진 첨부** (카메라 촬영만·본문 먼저·리사이즈2048/JPEG·성역 불변 `photo:` 포인터) | ✅ | **iPhone 실기기** | 커밋 `ae81a50`·`a067682`; `docs/worklog/2026-07-24-macmini.md`(Stage 2 통과); `PhotoStore.swift`/`CameraCapture.swift` |
| **사진 EXIF GPS** (촬영 위치를 사진 EXIF에만·평문 그릇 X·상세에 지도) | ✅ 구현 | **미확인**(worklog상 "확인 진행됨"뿐 — 명확한 통과 기록 없음) | 커밋 `8262265`; `docs/worklog/2026-07-24-macmini.md`(Stage 3 "확인 진행됨"); `LocationProvider.swift`; `photo-capture-design.md` §5 |
| **주차위치 분류** (유연층 첫 사례, 재설계로 이중입력 제거 = 사진·GPS·본문으로 충분) | ✅ | **iPhone 실기기** | 커밋 `923d4a1`·`ca844f7`; `docs/worklog/2026-07-24-macbook.md`; `FlexType.swift` |
| **필터 ClassRegistry 통일** (실재 분류만 동적 노출, 주차 포함, 선택칩 갇힘 방지) | ✅ | **iPhone 실기기**(A~E 검증) | 커밋 `f79e69a`(2026-07-25); `docs/worklog/2026-07-25-macmini.md`; `InboxView.swift`(`FilterChipsBar`) |
| **fields.v1 편집 블록** (공백 담는 긴 텍스트·구조화 데이터를 JSON으로 직렬화, 병합 무영향) | ✅ | **코어 테스트** + **iPhone 실기기**(question 배선) | 커밋 `7e5fbf1`·`f80724c`; `EventLog.swift`/`EventWriter.swift`; `photo-capture-design.md` §3 |
| **§7 분류–세부정보 모델 Stage A~D2** (분류=코드 고정 + 그릇 위 정의층. §7 (a)쓸지·(b)제목이 **화면에서 작동**) | ✅ (단 D3 한계 有, 아래) | **iPhone 실기기**(각 단계 통과) + **코어 테스트**(71 불변) | `memory-philosophy.md` §7; `ClassDef.swift`/`ClassRegistry.swift`/`DetailView.swift`; 커밋 아래 |

> **§7 Stage A~D2 세부** (전부 §2·§3·`MergeEngine`·`TypeMeta` 무변경 — 위에 얹은 표시 정책 층):
> - **A** 분류 관리 화면 제거(`e118a69`) — 분류는 코드 고정, 사용자가 안 만듦.
> - **B** `ClassDef` 틀 도입(`c04b999`) — 동작 0, 현재 동작의 거울.
> - **C** 주차 마감(due) 숨김(`e6cfe96`) — 첫 분류별 차등(표시 전용).
> - **D1** `FlexTypeCatalog` 흡수(`84f6d2f`) — 모든 분류 평등한 `ClassCatalog` 한 목록(동작 0).
> - **(a) 씀 여부**(`d00b8de`) — 정보·아이디어·원칙 due·resurface 안 씀 → 시간 섹션 통째 숨김. **§7 (a) 작동.**
> - **D2 (b) 라벨**(`8bfb603`) — 약속 due"언제"·resurface"미리 알림", 일정 "일시"·"미리 알림". 접미사 "(Due)/(Resurface)" 제거. **§7 (b) 작동.**

---

## 4. 미해결 / 알려진 이슈 (우선순위)

> 저장소가 별도 버그 트래커를 두지 않으므로, 문서·메모리·교훈에 기록된 것만 근거로 나열. **없는 버그를 지어내지 않음.**

| # | 이슈 | 상태·우선순위 | 근거 |
|---|------|------------|------|
| B1 | **탭 점프 버그** — 다른 앱 갔다 복귀 시 탭이 튐 | **해결됨** (홈 제스처 중 하단 탭바 우발 터치가 원인 → `stableTab`+`onChange` 무애니메이션 원복). 재발 관측되면 재조사. | 커밋 `c7dc963`; `native/Sources/App/RootView.swift`; `docs/lessons/2026-07-21-tab-jump-home-gesture-touch.md`; 메모리 [[tab-jump-bug-resolved]] |
| B2 | **'원칙 0개면 밴드 숨김'** — 코드 처리했으나 실기기 미검증 | 열림 · **낮음** | `memory-philosophy.md` §3 주의 |
| B3 | **'총 기억' 정의** 재검토 중 (현재 = 살아있는 전체) | 열림 · 낮음 | `memory-philosophy.md` §5 |
| C1 | 스크롤 위치 기반 접힘/요약 = SwiftUI `List` 제약으로 **폐기**(버그 아님, 제약) | 종결 | `native-v1-state` 메모리 교훈 |
| C2 | 무료 서명 앱은 **7일 뒤 만료**(재설치 갱신) — 환경 제약 | 상시 | `iphone-verify-checklist.md` A |
| **D3한계** | **§7 (a) uses 조정이 "표시만 숨김"** — 정보·아이디어·원칙의 due/resurface를 상세에서 안 보이게 했으나(`d00b8de`), **기존 저장된 값·예약된 알림은 안 건드림**(비파괴적). 그 분류에 옛 due/resurface 값이 있으면 화면엔 없어도 **알림 planner가 여전히 발화**할 수 있음. | 열림 · **중간** (§7 (c)/D3에서 값 무효화·알림 정리 필요). **이거 안 하면 사양서에 "안 씀" 박기 위험** | `ClassDef.swift`(주석 "§7 (c) 몫"); `DetailView.timeSection`; `NotificationScheduler.swift` |

**환경 주의(맥미니 고유, 2026-07-25):** ① 최초 `git`/`xcodebuild`가 Xcode 라이선스 미동의로 막힘 → `sudo xcodebuild -license`. ② Xcode 26.6은 iOS SDK 26.5뿐 → 시뮬 런타임 26.5 설치(`xcodebuild -downloadPlatform iOS`) + iPhone 16 Pro(26.5) 시뮬 생성 필요. 근거: `docs/worklog/2026-07-25-macmini.md`.

### Mac 타깃 현황 (빌드 설정은 있으나 검증·상태 문서는 없음)

- **빌드 타깃 존재:** `native/project.yml`에 `SecondBrainApp-macOS`(platform macOS, deploymentTarget 26.0) 정의. 진입점 `SecondBrainApp.swift`는 iOS·macOS 공유.
- **플랫폼 분기 존재:** 13개 파일에 `#if os()` 분기. Mac 전용 처리 예 — `FragmentFolder.swift`(폴더 접근), `DeviceStore.swift`(기기 식별), `CaptureSheet.swift`("macOS: STT 없이 텍스트 입력"), `SettingsView.swift`(리스트 스타일), `NotificationScheduler.swift`(macOS 알림도 entitlement 불필요).
- **Mac에서 검증된 것:** ① 코어 테스트 **71개 전체가 SwiftPM `swift test`로 macOS 호스트에서 실행**됨 → 코어 로직(병합·직렬화·planner 등) 전반이 **Mac에서 exercised**. ② 코어 병합 엔진의 **실데이터(inbox.md 68) 로드·쓰기·불변 검증도 macOS에서** 이뤄짐(메모리 [[native-v1-state]]). ③ iOS·macOS 양쪽 **빌드 통과** 기록. **단, ①②는 코어(CLI 패키지) 검증이지 macOS *앱 UI/실사용* 검증이 아니다.**
- **Mac에서 미검증:** macOS 로컬 알림(검증 체크리스트 D는 "선택"이라 건너뜀 — `notify-verify-checklist.md`). 그 외 대부분 기능의 **Mac 실사용 검증 기록 없음**(위 3장 "검증 플랫폼"이 대부분 iPhone/코어인 이유).
- **없는 것:** **Mac 전용 상태·검증 체크리스트 문서가 없다**(iPhone은 `iphone-verify-checklist.md`·`notify-verify-checklist.md`가 있으나 Mac 대응물 없음). → 5장 열린 항목으로 등록.

### 검증 부채 (3장 "검증 플랫폼"이 미확인인 것만)

> 아래는 **3장 표를 근거로만** 모은 것 — 구현은 됐으나 검증 기록이 없거나 부분뿐인 항목. 새 항목을 지어내지 않음.

| 기능 | 왜 미확인 | 검증에 필요한 것 | 플랫폼 |
|------|----------|----------------|--------|
| **자동분류(pull-to-classify)** | 스윕 자체 실기기 통과 기록 없음(관련 question 배선만 iPhone 실기기 — `f80724c`) | 미분류 여러 개를 당겨 분류 → 결과(type/due)가 조각 파일에 반영·토스트 표시 실기기 확인 | iPhone 실기기 |
| **수집(STT·텍스트·App Intent)** | 실기기 검증 기록 없음 | 온디바이스 STT 받아쓰기·텍스트·액션버튼으로 항목 생성 실기기 확인(마이크 필요) | iPhone 실기기 |
| **사진 EXIF GPS** | worklog상 "확인 진행됨"뿐, 명확한 통과 기록 없음 | 촬영 위치가 EXIF에 기록되고 상세 지도에 뜨는지, 실내·권한거부 시 graceful한지 실기기 통과 | iPhone 실기기(카메라·위치) |
| **원칙 — 목록·드래그·'0개 밴드숨김'** | 세 영역 검증엔 ambient 띠만 포함, 목록 진입·드래그·밴드숨김 검증 기록 없음(B2) | 원칙 목록 진입·꾹눌러 드래그 정렬·원칙 0개 시 밴드 숨김 실기기 확인 | iPhone 실기기 |

(참고: macOS 로컬 알림(D)은 "미확인"이 아니라 "미검증(선택이라 건너뜀)"이라 위 표에서 제외 — 근거는 위 "Mac에서 미검증".)

---

## 5. 다음에 논의할 열린 질문

| 주제 | 내용 | 근거 |
|------|------|------|
| **§7 분류–세부정보 모델 구현** | **A~D2 완료**(A 관리화면 제거·B ClassDef 틀·C 주차 마감숨김·D1 FlexTypeCatalog 흡수·(a) 씀 여부·(b) 라벨). §7 **(a) 쓸지·(b) 제목이 화면에서 작동**. **남은 것 = D3(§7 (c) 동작)** — 아래 별행. | `memory-philosophy.md` §7; 커밋 `e118a69`·`c04b999`·`e6cfe96`·`84f6d2f`·`d00b8de`·`8bfb603` |
| **§7 (c) 동작 = Stage D3 (다음)** | **알림 규칙 + 안 쓰는 분류의 값·알림 정리.** 특히 (a)에서 "표시만 숨긴" 정보·아이디어·원칙 due/resurface의 **값 무효화·예약 알림 취소**(§4 D3한계 해소). 이걸 해야 사양서에 "안 씀"을 안전하게 박음. | `memory-philosophy.md` §7 (c); §4 "D3한계"; `NotificationScheduler.swift` |
| **주차 resurface "기억마다 다름" = §7 (d) 위임** | 지금 주차 resurface는 분류 차원 "씀" 고정. "기억마다 쓸지 다름"은 §7 (d) **세 상태(분류 고정/안 씀/기억에게 위임)** = 새 메커니즘 → **대기**(D3 이후 또는 별도). | `memory-philosophy.md` §7 (d); 2026-07-28 세션 결정 |
| **O4 유연층 자동분류** | 지금 수동뿐 = "안 하기로 한 것 아니라 아직 안 한 것". 유연층 쌓이고 "분류마다 자동분류 규칙" 서면 편입. | `classification-redesign-open-questions.md` O4; 메모리 [[flex-autoclassify-deferred]] |
| **해시태그 설계** | 분류 안의 가벼운 세분(저장·표시·검색). 분류 폭발 대신. | `memory-philosophy.md` §7; open-questions §7-2 |
| **반복 규칙 (O3)** | 반복=속성(D3 확정)이나 표현·resurface 연동·다음 회차 생성은 미결. | `classification-redesign-open-questions.md` O3 |
| **일정 세분화(O1)·추억 분류(O2)** | 열림. | open-questions O1·O2 |
| **원칙 각인 방식** | "지속·반복적이되 불편하지 않게 각인" = 별도 큰 과제. | `memory-philosophy.md` §3 미결 |
| **'살아있는 기억' refresh/push 본격 기획** | 앱의 심장. 급함 문법(D-day) 아닌 소중함의 접근 — 재기획 영역. | `memory-philosophy.md` §1·§2-2 |
| **완전 삭제** | 엔진 hard-delete + 재확인 절차 후 구현(보류). | `edit-policy.md` §8 |
| **Mac 쪽 상태 문서화 안 됨** | macOS 타깃은 빌드 설정·`#if os()` 분기가 있고 코어는 Mac 실데이터로 검증됐으나(4장 "Mac 타깃 현황"), **Mac 실사용/UI 검증 체크리스트·상태 문서가 없다.** iPhone처럼 Mac 검증 절차를 문서화할지 논의 필요. | `native/project.yml`; 4장 "Mac 타깃 현황"; iPhone 대응물 = `iphone-verify-checklist.md`(Mac 없음) |
| **question 답변 경로 없음** | 자동분류가 붙인 `question`(§2 용어)은 상세 화면에 **"확인이 필요해요" 카드로 읽기전용** 표시될 뿐 — **사용자가 그 자리에서 답할 경로가 없다.** 미결: 답변 경로를 만들 것인가? 만든다면 (a) 답이 **어느 field로 들어가나**(예: `raw` 보강 vs 새 `answer` field vs `question` 해소 후 삭제), (b) **병합에서 어떻게 다루나**(field별 LWW라 두 기기 답변 충돌 시 HLC 최신 승 — 손실 없나?), (c) 답하면 `info-action`이 명확해져 due가 생기는 흐름과 어떻게 잇나. | `native/Sources/App/DetailView.swift`(L69 `questionSection` 읽기전용); `ClaudeClassifier.swift`(question 생성); `docs/native/merge-design.md` §3(필드별 LWW) |

---

## 6. 아직 사양서에 반영 안 된 결정 (규칙 #2 추적)

> 정본 사양서 = `second-brain-v0-spec.md`. 아래는 **결정·구현됐으나 사양서 §2 등에 아직 안 박힌** 것. (사진·EXIF 프라이버시는 이미 반영됨 → 표기 제외.)

| 결정 | 현재 어디에 있나 | 사양서 반영 | 근거 |
|------|----------------|-----------|------|
| **§7 분류–세부정보 모델** (분류=코드 고정, 그릇+분류별 정의, 모든 분류 평등, 해시태그) | `memory-philosophy.md` §7; **코드 = Stage A~D2 구현됨**(`ClassDef.swift` 등) | ❌ 미반영. **A~D2 구현됐어도 D3(§7 (c) 값·알림 정리)까지 굳은 뒤 반영** — 특히 정보·아이디어·원칙 "안 씀"은 D3 전엔 표시만이라 사양에 박기 위험(§4 D3한계). | `memory-philosophy.md` §7; §4 "D3한계"; `docs/worklog/2026-07-28-macmini.md` |
| **분류 2층→평등 재구성 / 주차위치(유연층 흡수)** | open-questions D1(→§7 포인터); **D1에서 `ClassCatalog`로 흡수**(`FlexTypeCatalog` 삭제) | ❌ 사양서 §2는 여전히 고정 6종만 | open-questions D1; 커밋 `84f6d2f`; `second-brain-v0-spec.md` §2 |
| **필터 동적화**(실재 분류만·유연층 포함) | 구현됨 `f79e69a` | ❌ 사양서 §2 부근 L176은 고정 필터 전제 서술 | `second-brain-v0-spec.md`(L176 부근) |
| **유연층 자동분류 상태(O4)** | open-questions O4 | ❌(개념 문서에만) | open-questions O4 |
| **참고 — 이미 반영됨** | 사진·카메라·성역·EXIF 프라이버시 | ✅ 반영 완료 | `second-brain-v0-spec.md` "네이티브 v1 확정" 소절(커밋 `db83c9a`) |

**보류 사유:** Stage 4(사진·주차)를 2026-07-24 통째로 재설계한 직후라, 며칠 실사용으로 방향이 굳은 뒤 사양서에 박는다(곧 또 바뀔 것을 미리 박지 않음). 근거: `docs/worklog/2026-07-25-macmini.md` "사양서 반영 확인".

---

*이 문서는 스냅샷이다. 최신 상태는 각 정본 문서·최근 worklog(`docs/worklog/`)·`git log`를 확인할 것.*
