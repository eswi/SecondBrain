# 합치기 엔진 설계 — 이벤트 소싱 (네이티브 v1 Phase 2)

> 이 문서는 **"왜 이렇게 병합하는가"의 근거**다. 코드보다 이 문서가 규칙의 정본.
> 관련: 저장소 루트 `second-brain-v0-spec.md` §0-A(아키텍처), `native-v1-design-draft.md`(전환 배경).
> 결정일 2026-07-16. 삭제 정책 = **P1** 확정.

## 0. 큰 그림
- 조각 파일 `inbox-<device>.md` = 기기별 **append-only 이벤트 로그**(평문·grep 가능). 각 기기는 **자기 파일에만** append → iCloud "마지막이 이긴다" 충돌 원천 차단(§0-A).
- **합치기 엔진 = 순수 함수** `merge([Event]) -> MergeResult`. 파일 I/O와 분리 → 테스트가 이벤트 배열을 직접 넣어 급소를 겨냥. **결정적·순서무관·멱등**이 핵심 계약.
- 상태 해소 = **항목별·필드별 LWW(Last-Writer-Wins) 레지스터**, 순서 기준 = **HLC(Hybrid Logical Clock)**.

## 1. 급소 ① 항목 ID — 전역 고유
- **UUID v4.** 생성 기기가 최초 캡처 때 1회 발급 → **영구 불변.** 수정·삭제 이벤트는 이 `id`만 참조.
- v0의 "내용 해시(`date time|source|raw`)" id는 **금지** — 원문 수정 시 id가 바뀌어 이벤트 사슬이 끊긴다. id는 내용과 독립이어야 한다.
- **레거시 편입:** 기존 `inbox.md`(id 없는 줄)는 읽을 때 내용 해시로 안정 id를 부여하고 `deviceId="legacy"`, `wall=0`의 아주 낮은 HLC create로 취급 → 어떤 실 이벤트에도 지는 최하 우선순위로 안전하게 편입.

## 2. 급소 ② 이벤트 순서 — HLC
단순 wall-clock은 시계 오차·동시 편집에서 흔들린다. HLC로 해결.
- 이벤트마다 `hlc = (wallMillis, counter, deviceId)`.
- **쓸 때:** `wall = max(직전 wall, now())`; 같으면 `counter+1`, 크면 `counter=0`.
- **읽을(합칠) 때:** 로컬 시계를 방금 본 이벤트들의 최대치 이상으로 끌어올린다(HLC receive). → 이후 내 편집은 "내가 본 것보다 반드시 뒤"가 보장(인과성).
- **전순서 키 = (wall, counter, deviceId).** deviceId 최종 tiebreak → **무승부 없는 완전한 전순서** → 병합 순서와 무관하게 항상 같은 결과.
- **효과:** 기기 B가 A의 편집을 동기화로 본 뒤 편집하면, B의 물리 시계가 A보다 느려도 **B가 최신으로 판정**(receive로 시계를 끌어올렸으므로). 순수 시각이면 뒤집혔을 케이스.
- **진짜 동시(둘 다 오프라인·서로 못 봄):** wall→counter→deviceId로 결정적 승자. 같은 사용자라 무방하고, 로그가 append-only라 **진 이벤트도 보존**(복구 가능).

## 3. 필드 병합 — 항목별·필드별 LWW
- 항목은 `id`로 묶고, 각 콘텐츠 필드(`type`/`due`/`resurface`/`status`/`raw`/`date`/`time`/`source`)는 **그 필드를 세팅한 이벤트 중 HLC 최대**의 값.
- 두 기기가 **다른 필드** 동시 편집 → 둘 다 반영(무손실). **같은 필드** 충돌만 HLC 최신 승.

## 4. 급소 ③ 삭제 — 정책 P1 (확정)
`deleted`는 특수 제어 필드. **일반 필드 LWW와 다르게** 아래 규칙으로 판정:
- **항목의 삭제 여부 = 그 항목의 최고 HLC 이벤트가 `deleted=true`인가.**
  - 최고 HLC 이벤트가 delete → **숨김(deleted).**
  - 최고 HLC 이벤트가 콘텐츠 편집(=`deleted` 안 건드림) 또는 undelete → **live(부활).**
- 이렇게 하면 P1이 정확히 구현된다: **"delete보다 HLC 큰 편집이 오면 자동 부활"**(편집=유지 의도), **마지막 행동이 delete면 숨김.**
- **좀비 방지:** delete보다 HLC 낮은(오래된/뒤늦게 도착한) create·edit 재유입은 최고 HLC를 못 넘으니 되살리지 못함.
- **무손실:** 병합 결과가 무엇이든 이벤트는 로그에 그대로 남는다(append-only). 숨겨진 항목은 `MergeResult.deleted`로 나와 UI가 "다른 기기에서 삭제됨 — 복구?"로 사람이 되살릴 수 있다.
- (숨겨진 항목도 콘텐츠 필드는 per-field LWW로 다 해소해 둔다 → 복구 시 최신 내용 유지.)
- P2("편집은 삭제를 항상 이김")는 기각: 무손실은 이미 append 로그+복구 UI로 보장되므로 추가 복잡도 불필요.

## 5. 관통 원칙 — 무손실
이벤트는 절대 지우거나 되쓰지 않고 **append만**. "잊는 걸 막는다"는 대전제와 정합 — 잘못 이겨도 원본이 파일에 남아 복구 가능.

## 6. 이벤트 파일 포맷 (평문·grep)
- **create**(익숙한 항목 블록 + `id`/`hlc`):
  ```
  - 2026-07-16 09:00 | voice | 우유 사오기
    id: 0190a1b2-...        (UUID)
    hlc: 1721.0.iphone      (<wall>.<counter>.<deviceId>)
    type: info-action
    due: none
  ```
- **변이 이벤트**(한 줄):
  ```
  @ 1725.0.iphone | 0190a1b2-... | set type=discard due=2026-07-20
  @ 1730.0.mac    | 0190a1b2-... | delete
  @ 1740.0.iphone | 0190a1b2-... | undelete
  ```
- 파서는 관용적: 알 수 없는/깨진 줄은 스킵(크래시 없음), 나머지는 정상 파싱.

## 7. 엔진 계약 & 타입
- `HLC(wallMillis, counter, deviceId)` — Comparable(전순서).
- `HLCClock` — send(now)/receive(remote, now)로 HLC 발급·수신(쓰기·동기화 경로).
- `Event(id, hlc, fields:[String:String])` — 팩토리 create/edit/delete/undelete.
- `MergeEngine.merge([Event]) -> MergeResult{ live:[ResolvedItem], deleted:[ResolvedItem] }` — **결정적·순서무관·멱등.** 정렬은 최신 캡처(createdHLC) 우선, 동률 시 id.

## 8. 테스트 목록 (먼저 두껍게, 통과가 완료 기준)
**기본기:** 1 create · 2 같은필드 최신승 · 3 다른필드 둘다 · 4 순서무관 · 5 멱등.
**ID:** 6 두 기기 별개 id → 별개 항목 · 7 같은 id 병합 · 8 edit가 create보다 먼저.
**순서/HLC:** 9 wall 우선 · 10 counter · 11 deviceId tiebreak · 12 **인과성(느린 시계라도 나중에 본 쪽 승, HLCClock)** · 13 오프라인 동시 결정적.
**삭제(P1):** 14 편집후 삭제 · 15 삭제후 편집=부활 · 16 삭제 vs 동시편집 결정적 · 17 삭제→undelete · 18 좀비 방지.
**연쇄(추가):** 19b **긴 사슬**(create→편집→미루기→삭제→부활, 여러 기기 번갈아) 결정적 + 순서무관.
**견고성/포맷:** 19 깨진 이벤트 줄 스킵 · 20 레거시 v0 줄 편입.

**범위 밖(v1 이후):** 벡터클록 기반 동시성 "감지"(지금은 HLC 전순서로 자동 해소), 아카이브 청소(§0-A).
