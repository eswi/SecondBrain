# 레거시 → UUID 일괄 마이그레이션 — 설계 (실행 전)

> ⚠️ **이 문서는 설계이며 아직 실행되지 않았다(NOT YET EXECUTED).** 실데이터(iCloud `inbox*.md`)를
> 변형하는 작업이라 `merge-design.md`급으로 신중히 다룬다. 실행은 위대표 검토 후, 단계로 나눠서 한다.
> 관련 정본: `merge-design.md`(병합 규칙 — **이 마이그레이션으로 안 바뀜**), `edit-policy.md`(§7 레거시·§8 원문 잠금).
> 작성 2026-07-20.

## 0. 목적
레거시 항목(웹+classify.py 시절, `inbox.md`의 id 없는 줄)은 내용 해시 id `legacy:<16hex>`를 받는다.
원문을 손대면 해시가 흔들려 이벤트 사슬이 끊기므로 **원문 수정이 잠겨** 있다(edit-policy §8).
이들을 **영구 UUID로 승격**하면 그 제약이 풀리고, 이후 레거시 처리 코드(해시 id·§7 역산·원문 잠금)를
제거할 수 있다. **엔진·병합 규칙·분류(§2/§3)는 건드리지 않는다.**

## 1. 현황 (실데이터 조사 — 2026-07-20)
| 항목 | 값 |
|---|---|
| `inbox.md` 레거시 줄(id 없는 create) | **71줄** (voice 62 · web 9) — 사양서 §7 "68"과 다름 → **D1: dry-run으로 규명** |
| `inbox.md`의 native(id/hlc) 블록 | 0 (순수 레거시) |
| 조각 파일 | **1개** `inbox-dev-155f307a.md` |
| 조각 legacy 참조 변이 | 80건 (set 61·delete 16·undelete 3), 고유 legacy id 36개 |
| 조각 native(UUID) 참조 변이 | 31건 (레거시 아님 → 건드리지 않음) |
| 모든 이벤트의 hlc deviceId | **단일 `dev-155f307a`** — 다른 기기 기록 없음 |
| 미다운로드 iCloud placeholder | 없음 (로컬 완전) |

**D2 확인(2026-07-20):** 오늘 iPhone 실기기 시험은 이 실폴더에 **쓰지 않았다**(iphone 조각·iphone deviceId·placeholder 전무, 전부 dev-155f307a). → 대상 조각 1개뿐. 단 **apply 직전 iPhone 재확인**은 유지.

## 2. 급소
레거시 항목은 `inbox.md`에서 해시 id를 받고, 편집/기억하기/삭제하면 조각에
`@ hlc | legacy:<hex> | verb`로 **그 해시 id를 참조**해 쌓인다(`confirm`은 `set confirmed=true`).
따라서 "id만 바꾸면" 참조가 끊긴다 → **해시 id를 UUID로 치환(rename-in-data)**하고 참조도 함께 옮긴다.

## 3. 방식 — 데이터 내 id 리네임 (엔진 무변경)
1. `inbox.md` 71줄 각각 `Event.legacyID(date,time,source,raw)` 해시 계산 → **해시→UUID(v4) 1:1 맵**.
2. 각 레거시 블록을 정상 UUID create 블록으로 재작성:
   - `id:` = 해시 → **UUID**
   - `hlc:` = 현재 resolve되는 값(`0.<index>.legacy`)을 **바이트 동일**하게 명시(최하 우선순위 유지 → edit이 계속 이김)
   - `device:` = §7 역산값 **동결**(voice→iPhone 16 Pro / 그 외→MacBook Pro) — 이후 §7 코드 제거 가능
   - 원문·시각·source·기존 분류 필드 = 그대로(성역)
3. 조각의 모든 `@ hlc | legacy:<hex> | verb` 줄에서 `legacy:<hex>`를 맵의 UUID로 치환.
   verb·hlc·필드는 그대로(편집/기억하기/삭제 이력이 새 UUID에 그대로 이어짐). native 참조 31건은 무변경.

## 4. 무손실 보장
- **개수 불변**: 모든 원본 이벤트(create 71 + 변이 80 + native 51) 하나도 안 사라지고 안 늘어남. id 토큰만 변경.
- **이력 안 끊김**: 변이의 hlc·필드 그대로 → 순서·인과성·`historySummary` 보존.
- **confirmed/편집/principle 유지**: `confirmed=true`·`set type=…`·`set type=principle`·`order=…`가 새 UUID로 이어져 병합 결과 동일.
- **엔진 무변경**: 좀비 방지·삭제 P1·per-field LWW 그대로 — 마이그레이션은 엔진 "안에서" 도는 데이터 변환.

## 5. 백업 (첫 단계, 무조건)
iCloud **밖** 로컬 `~/SecondBrain-backup-<YYYYMMDD-HHMM>/` 에 `inbox.md`+`inbox-*.md` 복사 + `.zip` 1벌 + 해시 대조.
데이터는 git 밖이라 파일 복사가 유일한 안전망.
**실행됨(2026-07-20 19:12):** `~/SecondBrain-backup-20260720-1912/` + `.zip`, 원본=백업 해시 일치 확인.

## 6. 검증 — 같은 MergeEngine으로 before == after
내용키 `k=(raw,date,time,source)`(=해시 원재료)로:
1. 개수: `merge(after)` live+deleted 수 == `merge(before)`.
2. 전단사: before ↔ after 항목이 내용키로 1:1(고아·유령 0).
3. 상태 동일: 짝마다 `type·due·resurface·status·confirmed·deleted·order` 완전 일치.
4. id: 레거시였던 것 → 유효 UUID, native → 불변.
5. device: after 레거시 항목의 `device`가 §7 역산과 일치.
6. 이력: 내용키별 이벤트 개수 before==after.
7. 사전점검: 71 해시 **유일**(내용≠해시면 충돌=위험), 조각의 모든 `legacy:` 참조 ∈ 71 집합(고아 0).

하나라도 실패 → 중단 + 문제 항목 출력. 전부 통과해야 산출물 승인. 대조 리포트를 파일로 남긴다.

## 7. 도구 (Swift CLI, D5)
`native/tools/sb-migrate` — **앱과 동일한 코어 코드**로 해시·병합·검증(재구현 divergence 방지).
앱 Xcode 프로젝트와 분리된 별도 SwiftPM 패키지(앱 빌드 영향 0). 원본 **in-place 무변경**:
- `--dry-run <folder>`: 사전점검#7 + before==after 시뮬 + D1 규명 리포트. 파일 안 건드림.
- `--apply <folder> --out <dir>`: 산출물을 **새 디렉터리**에 생성 후 재검증(D4). 원본 무변경.
- 원본 교체(④)는 검토 후 수동/가드된 별도 단계.

## 8. 실행 순서 (각 단계 후 정지·보고)
```
①백업(로컬+zip) → ②dry-run(리포트) → [검토] → ③apply(새 디렉터리) → [검토]
→ ④원본 교체(수동) → ⑤앱 실사용 재확인 → (며칠 뒤 별도) ⑥레거시 코드 제거
```

## 9. 한 기기에서만 + 동기화 펜스
- 이 MacBook에서만. 실행~검증~동기화 완료까지 mac mini·iPhone 앱 열지 않음(못 본 새 조각이 고아 참조 유발).
- 완료 후 iCloud가 mac mini·iPhone에 전파(데이터는 iCloud 동기, git 아님).

## 10. 코드 제거 (⑥ — 별도 단계, 마이그레이션과 절대 동시 금지)
검증 완료 + 실사용 확신 후 별도 커밋: `Event.legacyID`/`fromLegacy`·`EventLog.parse` id-없는 분기 ·
`CaptureDevice` §7 역산 · DetailView 원문 잠금(§8). **데이터는 이미 UUID라 코드만 정리.**

## 11. 결정 로그 (D)
- D1(닫힌 집합 68 vs 71): **dry-run으로 규명 후 확정** — 71 확정 시 사양서 §7 갱신 검토.
- D2(iPhone 기록 여부): **없음 확인**(2026-07-20). apply 직전 재확인 유지.
- D3(device 동결): **동의**.
- D4(새 디렉터리 후 수동 교체): **동의**.
- D5(Swift CLI): **동의**.
