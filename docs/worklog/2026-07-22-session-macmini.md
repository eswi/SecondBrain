# 작업 로그 — 2026-07-22 (mac mini · 세션 마무리)

> **재개 한 줄 (내일, MacBook 또는 mac mini):** `git pull` → `cd native && xcodegen generate` → 빌드 확인.
> **내일 1순위 = "화면 아래로 당기면 분류"(pull-to-classify) 구현** — 오늘 끈 자동 스윕(`RootView.autoClassifyOnOpen=false`)을
> 이 방식으로 대체(플래그 지우거나 pull 경로로 교체). 설정 "지금 분류하기" 수동 버튼은 이미 살아있음.

## 오늘 한 일 (커밋 순)
1. **탭 튐 버그 종결** (`c7dc963`) — 원인=홈 제스처 중 하단 탭바 스침(터치). 실기기 A/B로 확정(전원버튼=안 튐 vs 홈스와이프=튐).
   수정=우발적 선택을 무애니메이션 원복(scene active일 때만 stableTab 기록). 진단 코드 제거. 전말: `docs/lessons/2026-07-21-tab-jump-home-gesture-touch.md`.
2. **CLAUDE.md 작업 기기 규칙** (`25e1704`) — 집=맥미니 / 회사=맥북프로.
3. **원본 음성 보존** (`a343761`) — STT와 함께 녹음→저장(`<uuid>.m4a`, write-once)→상세화면 "다시 듣기".
   여러 take(정지→재개)가 한 파일에 시간순으로 이어짐(실기기 A/B/C 검증). Core 접촉=EventWriter 화이트리스트 1줄뿐(병합 무변경).
   정본: `docs/native/audio-capture-design.md`. 상세 worklog: `docs/worklog/2026-07-22-audio-capture.md`.
4. **사양서 반영** (`5b9f09e`) — §1(이미지 포인터 옆 음성 포인터·다시듣기·기기전용)·§6(음성 기기전용·향후 iCloud 옵트인).
5. **앱 열 때 자동 분류 끔** (`25a793c`) — `autoClassifyOnOpen=false` 플래그로 .task·scenePhase 두 호출 지점 동시 무효.
   수동 "지금 분류하기"는 유지. **내일 pull-to-classify로 대체 예정.**

## 상태
- main = `25a793c`, 로컬=원격 동기 완료(push됨). working tree clean. 브랜치/worktree 정리 불필요(main 단일).
- 폰: 최신 빌드(자동분류 꺼짐 포함) 설치·검증됨.

## 다음 할 일
1. **pull-to-classify** (내일 1순위) — 화면 아래로 당기면 분류. `autoClassifyOnOpen` 대체.
2. 원본 음성 **항목별 iCloud 동기화 옵트인** (설계 §7, 구조 헤드룸만 둠 — 지금 미구현).
3. STT **question 필드 후속** (공백 직렬화 미지원 — 미분류 보존 원칙과 연계).
4. **⑥ 원문 편집** ("음성 들으며 텍스트 고치기" 토대 마련됨).

## 사양서 반영 확인 (규칙 #2)
- 음성 보존 → 이미 §1·§6 반영 완료(`5b9f09e`).
- 자동 분류 끔 → §0-A가 "앱 열 때 자동 분류"로 서술 중이나, **오늘은 과도기(내일 pull-to-classify로 대체)** 라
  지금 반영하지 않음. **pull-to-classify 확정 시 §0-A를 그 방식으로 갱신**하는 게 맞음(사용자 확인 대기).
