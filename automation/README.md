# `automation/` — ⛔ **지금은 쓰지 않는 폴더다** (한 파일만 예외)

> **자동 분류는 멈춰 있다.** 2026-08-18에 앱에서 진입점 둘을 막았고(`ClassifyPause`),
> **2026-08-21에 zero base로 새로 설계**하기로 정해졌다(`CLAUDE.md` 항시 규칙 8).
> **이 폴더는 그 결정 「이전」에 만들어졌다** — 그래서 경고가 코드보다 늦게 붙었다.
> ⛔ **고치지 않는다. 지우지 않는다. 표시만 해 둔다.** 되살릴지는 **사용자가 정한다.**

## 등급 — 파일마다

| 파일 | 등급 | 돌리면 무슨 일이 나나 |
|---|---|---|
| `setup-mac.sh` | ⛔ **되살린다** | **매시간 :00에 `classify.py`를 도는 launchd LaunchAgent를 설치한다.** 지금 유일한 제동은 **키 파일이 없으면 멈추는 것**뿐이다 |
| `run-classify.sh` | ⛔ **되살린다** | launchd 래퍼인데 **직접 돌려도 그대로 돈다** — `classify.py` 1회 실행. ⛔ **화면에 아무것도 안 나온다**(로그에만 찍힌다) |
| `uninstall-mac.sh` | ✅ **안전하다 — 오히려 있어야 한다** | 위 LaunchAgent를 **끄고 플리스트를 지운다.** 지금 상태를 **지키는 쪽**이다 |

⚠️ **폴더 전체를 위험으로 읽지 말 것** — 그러면 정작 끌 때 `uninstall-mac.sh`를 안 쓴다.

## ⛔ 되살릴 때 **먼저 고쳐야 하는 것** — 파일 꼴이 바뀌었다 (2026-08-31)

**`classify.py`는 `inbox*.md`를 직접 파싱하는데, 그 사이 저장 꼴이 두 번 바뀌었다.**
⛔ **되살리면 조용히 틀린다** — 파싱은 되고 값만 어긋나는 종류다.

| 언제 | 무엇이 바뀌었나 | `classify.py`에서 어떻게 보이나 |
|---|---|---|
| 2026-08-23 | **자료 포인터가 자료마다 별도 필드**가 됐다(`photo.<자료id>`) — 한 항목에 여럿 | `photo` 하나만 찾으면 **새 꼴을 못 본다** |
| **2026-08-31** | **원문의 줄바꿈이 `\n`(두 글자)으로 접혀 저장된다**(`RawLine`) | 줄바꿈이 **글자 `\n`으로 그대로 보인다** — 분류 프롬프트에 그렇게 들어간다 |

⚠️ **이것은 「고쳐 둔다」가 아니라 「사실을 적어 둔다」다**(항시 규칙 8: 문서에서 사실을 바로잡는 것은 해도 된다).
⛔ **코드는 한 줄도 안 건드렸다.**
★ **웹 v0(`parser.js`·`app.js`)도 같은 두 가지에 걸린다** — 그 세대 표시는 루트 `README.md` 맨 위에 있다.

## 이 폴더 밖에도 있다

| 자리 | 등급 | 무엇 |
|---|---|---|
| **루트 `classify.py`** | ⛔ **되살린다** | 인수 없이 돌리면 iCloud `inbox.md`에 **`type`·`due`·`resurface`·`status`·`question`을 직접 쓴다**(결정 C 위반). ⛔⛔ **`SYSTEM_PROMPT`에 `discard`가 그대로 있고, 앱에 있는 discard 거부 방어가 여기엔 없다** — 2026-07-24에 이 경로가 **사람이 확정한 기억(`D6E4950B`)까지 버렸다.** 저장 안 하는 모드: `--plan`(API 호출 없음) · `--dry-run` |
| **웹 v0 (`app.js` 등)** | ⚠️ **다른 축을 되돌린다** | 자동이 아니라 사람이 누르는 것이지만 `writeToFile()`이 `inbox.md`에 **`due`·`resurface`를 덮어써** 2026-08-18 축 결정(**미확정에는 시점이 붙지 않는다**)을 되돌린다 → 루트 `README.md` 맨 위 |
| `native/tools/2026-08-18-strip-auto-fields.py` | ⚠️ **방향이 반대다** | 자동이 쓴 필드를 **걷어내는** 일회성 기록(실행 완료). **재실행 금지**가 그 파일 머리와 `CLAUDE.md`에 이미 있다 — **더 붙이지 않았다**(2026-08-21 판단) |

## 진입점 전수 — **2026-08-21에 여기를 봤다** (다음에 같은 훑기를 할 때의 출발점)

**자동으로 도는 것은 launchd 하나뿐이다.** 다음을 확인했다:

- `automation/` = **셋뿐**(`setup-mac.sh` · `run-classify.sh` · `uninstall-mac.sh`).
- **`.github` 없다** · **`Makefile` 없다** · **`package.json` 없다** → CI·태스크러너 진입점 **0**.
- `launchd|LaunchAgent|crontab|StartCalendarInterval`을 코드에서 훑으면 **automation 셋** +
  `native/Sources/App/ClassifyPause.swift`(앱 쪽 **차단** 코드) +
  `native/tools/2026-08-18-strip-auto-fields.py`(문서용 언급)뿐이다.
- git 추적 스크립트 전수: 위 셋 · `classify.py` · `native/tools/inbox-state.py`(읽기 전용) ·
  `native/tools/2026-08-18-strip-auto-fields.py` · `add-2-inbox.ps1`.
- 실행 비트(`100755`)가 켜진 것: automation 셋 + `inbox-state.py` + `strip-auto-fields.py`.

⚠️ **`native/tools/`의 swift 계측 도구들은 자동 분류와 무관하다**(`CLAUDE.md` 계측 규칙 5에 목록이 있다).
그중 `measure-icloud-download.swift`는 **상태를 바꾸지만**(dataless → 다운로드) 그 경고는 이미 그 자리에 있다.

**두 기기 상태 (2026-08-19까지 확인):** 회사 맥북 = **차단 완료**(08-18) · 집 맥미니 = **애초에 없었다**(08-19).
확인 방법 셋: `launchctl print` · `~/Library/LaunchAgents`의 plist · `crontab`. → `HANDOFF.md` 맨 위.
