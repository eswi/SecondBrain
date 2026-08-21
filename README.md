> # ⛔⛔ 이 README가 말하는 「웹 앱(PWA)」은 **지금은 쓰지 않는 세대다** (2026-08-21 표시)
>
> **이 저장소는 두 층이다.** 실사용은 **네이티브 v1(`native/`, Swift)로 넘어갔다.**
> 아래 문서는 **웹 v0**을 설명하는 것이고, 웹 v0는 **이전 세대이며 유지되지 않는다.**
>
> **⛔ 열어서 쓰지 말 것 — 세대 전체가 표시 대상이다:**
> `index.html` · `app.js` · `app.css` · `parser.js` · `sw.js` · `manifest.webmanifest` · `icons/`
> · `add-2-inbox.ps1`. **각 파일 머리에도 같은 표시를 붙였다**(`manifest.webmanifest`는 JSON이라
> 주석을 못 넣는다 — 이 줄이 그 파일의 표시다).
>
> **왜 세대 단위인가:** `app.js` 하나만 경고하면 **다른 웹 파일을 여는 사람은 그것을 못 본다.**
> (2026-08-21 사용자 판단 — `automation/setup-mac.sh` 한 곳에만 경고가 있어 다른 파일이
> 그냥 남아 있던 것에서 배운 것이다.)
>
> **⛔ 특히 `app.js`:** 아래 *"읽기 전용. `inbox.md`엔 쓰지 않는다"* 는 **사실이 아니다** —
> `writeToFile()`이 File System Access API로 **inbox.md를 덮어쓴다**(`due`·`resurface`).
> 그것은 2026-08-18 축 결정(**미확정에는 시점이 붙지 않는다**)을 되돌린다.
> 자세히는 `app.js` 머리주석 · `docs/native/sample-pending-checks.md` A그룹.
>
> **지우지 않는다 — 표시만 해 둔다.** 근거: `CLAUDE.md` 항시 규칙 8.

---

# 세컨드 브레인 — 1층 웹 앱 (PWA)

받은함(`inbox.md`)을 **종류별로 분류·검색·다시보기** 하는 소비(출구) 앱.
설계 근거는 함께 넣어둔 [`second-brain-v0-spec.md`](./second-brain-v0-spec.md)에 있다.
이 저장소는 **코드만** 담는다. 데이터(`inbox.md`)는 iCloud의 `SecondBrain` 폴더에만 있고, 여기엔 절대 커밋하지 않는다(`.gitignore`).

## 무엇인가 (설계서 §0-A, §6-1)

- **0층 = 얇은 입구(수집)** / **1층 = 하나의 앱(소비).** 이 저장소는 1층.
- 경로 1: **로컬 웹 앱(PWA) → (나중에) iPhone 네이티브.** 웹으로 다기기(iPhone·iPad·Mac·Windows)에 한 벌로 먼저 검증.
- 소비 우선순위: **push(시점 알림) 1순위 → pull(검색) 기본 → ambient(상시 원칙) 그다음.**

## 데이터를 읽는 방식 — 정적 PWA + 파일 선택

브라우저는 임의 경로를 못 읽지만, `inbox.md`는 iCloud Drive에 있어 **모든 기기에 이미 동기화**돼 있다.
그래서 각 기기에서 **파일 선택기로 `inbox.md`를 직접 읽는다.**

- **개인 데이터는 앱 셸에 들어가지 않는다.** 코드(HTML/CSS/JS)엔 받은함 내용이 전혀 없고, 데이터는 런타임에 기기에서만 로드된다. → 어디로도 전송되지 않음(설계서 §6-4 "외부 전송 최소화").
- ⛔ **~~읽기 전용. `inbox.md`엔 쓰지 않는다.~~ — 이 줄은 틀렸다** (2026-08-21 훑기에서 발견).
  확인·묶음 점 같은 상태는 이 기기(`localStorage`)에만 저장하는 것이 맞다. **그런데 쓰기 경로가 있다** —
  `app.js`의 `writeToFile()`/`confirmAllPending()`이 `inbox.md`에 **`due`·`resurface`를 덮어쓴다.**
  ⚠️ **옛 서술을 지우지 않고 남긴다** — 「읽기 전용」이라고 믿고 지나간 자리가 여기다.
- **데스크톱 Chrome/Edge:** File System Access API로 파일을 한 번 고르면 핸들을 저장해 이후 "다시 불러오기"로 실시간 재읽기.
- **iOS Safari 등:** 표준 파일 선택기로 iCloud Drive의 `inbox.md`를 고른다(데이터 바뀌면 다시 불러오기). 마지막으로 읽은 내용은 캐시돼 오프라인에서도 열린다.

## 로컬에서 실행

정적 파일이라 어떤 정적 서버로도 열린다(서비스워커·PWA 설치는 `file://`이 아니라 `localhost`/HTTPS가 필요).

```bash
cd ~/Documents/Projects/SecondBrain
python3 -m http.server 8765
# 브라우저에서 http://localhost:8765/ 열기 → "불러오기" → iCloud의 inbox.md 선택
```

같은 WiFi의 iPhone에서 테스트하려면 Mac의 LAN 주소(`http://<Mac-IP>:8765/`)로 접속.
(단, `localhost`가 아닌 http에선 iOS가 서비스워커/설치를 제한할 수 있다. iPhone 정식 설치는 아래 배포 참고.)

## iPhone에 "홈 화면에 추가" (PWA)

1. 앱을 **HTTPS 주소**로 연다(로컬 http로는 iOS PWA 설치가 제한됨 → 배포 필요).
2. Safari 공유 시트 → **홈 화면에 추가** → 아이콘·전체화면으로 앱처럼 실행.
3. 앱에서 **불러오기** → 파일 앱에서 iCloud Drive의 `SecondBrain/inbox.md` 선택.

### 배포 (선택) — GitHub Pages 등

앱 셸엔 개인 데이터가 없으므로 **공개 정적 호스팅에 올려도 데이터는 노출되지 않는다**(데이터는 기기에서만 로드).
GitHub Pages / Netlify / Vercel 어디든 이 폴더를 그대로 올리면 HTTPS 주소가 생겨 iPhone에서 설치·사용 가능.

## 화면 구성

- **오늘의 원칙 (ambient):** `type: principle` 항목을 상단에 상시 노출.
- **곧 닥칠 것 (push, 1순위):** 유효 시점(`due` 또는 임시 지정)이 **이번 주(7일) 내이거나 지난** 항목, `resurface` 도래 항목을 맨 위에 **지난 것 / 오늘 / 이번 주** 버킷으로 들이민다. 각 항목엔 **D-day 배지**(지남 `D+n`·오늘 `D-DAY`·남음 `D-n`). 설계서 §4·§5.
- **검색 (pull):** 원문·"왜"·URL 전문 검색. **필터:** 종류(행동 필요/생각·고민/원칙/정보·참고/정리 필요), 출처(voice/web/…).
- **시점 지정 (push, §5):** 각 항목의 **＋ 시점**으로 "다시 들이밀 날짜"를 지정.
  - **데스크톱(Chrome/Edge):** 고르는 즉시 `inbox.md`에 안전하게 기록(백업 후 원자적 쓰기, 해당 블록에 `due`/`resurface`만 덧붙임 — 원문 불변). 파일이 진실원이라 iCloud로 전 기기에 동기화.
  - **아이폰(읽기 전용):** 파일에 못 쓰므로 **임시(미확정)** 로 이 기기(localStorage)에만 저장 → 그 폰의 D-day는 즉시 작동. **점선·⏳ 미확정**으로 확정 항목과 구분.
  - **확정 대기 패널:** 임시 시점은 상단 "확정 대기" 목록에 상시 노출(저절로 사라지지 않음). 데스크톱에서 열면 **확정** 한 번으로 파일에 기록. (폰→데스크톱 자동 전달 배관은 없음 — 데스크톱에서 재지정/확정. §0-A 쓰기=데스크톱.)
- **묶음 점 ●:** `grouped: true`(또는 `group:`) 항목에 일회성 확인 점. 클릭하면 사라짐(설계서 §5).
- **출처 아이콘:** 🎙️voice 🌐web 🖼️image ✉️mail 📄doc 💬chat 🗓️meeting.

## 데이터 형식 (설계서 §1)

```
- 2026-06-29 10:40 | voice | 김형석 대표 만나야 됩니다
  type: promise        # event/promise/info-action/idea/discard, (+ principle → 원칙)
  due: 2026-07-11      # YYYY-MM-DD 또는 none
  resurface: 2026-07-10# 날짜 또는 none
  status: open
```

- `type` 없는 미가공 줄은 **정리 필요**로 모인다(아직 분류 안 된 줄).
- 분류 필드가 붙으면 자동으로 제자리 버킷·다이제스트로 흘러간다.

## 다른 컴퓨터에서 이어서 개발하기 (예: 집 Mac mini)

코드는 GitHub, 데이터는 iCloud라 이동이 간단하다.

```bash
# 1) 코드 받기 (원하는 위치에)
git clone https://github.com/eswi/SecondBrain.git
cd SecondBrain

# 2) 분류기 의존성
pip install anthropic

# 3) 웹 앱 로컬 실행 (선택 — 배포본은 이미 https://eswi.github.io/SecondBrain/ 에서 동작)
python3 -m http.server 8765     # → http://localhost:8765
```

- **데이터(`inbox.md`)는 옮길 필요 없다.** 같은 Apple ID로 iCloud에 로그인돼 있으면 `~/Library/Mobile Documents/com~apple~CloudDocs/SecondBrain/inbox.md`가 자동 동기화된다. (Mac mini에서 iCloud Drive 켜져 있는지만 확인. 파일이 "다운로드 대기" 상태면 Finder에서 한 번 열어 내려받기.)
- **API 키는 저장소에 없다(의도).** Mac mini에서 다시 설정: 환경변수 `ANTHROPIC_API_KEY` 또는 `~/.config/secondbrain/anthropic_key`. 키를 안 적어뒀으면 console.anthropic.com에서 새로 발급.
- **크레딧/결제는 계정 단위**라 기기와 무관하게 그대로다(현재 미해결 — 충전 후 분류기 사용 가능).
- **작업 이어가기:** Claude Code로 이 폴더를 열고 "README와 `second-brain-v0-spec.md`를 읽고 이어서 작업하자"고 하면 맥락을 잡는다. 다음 할 일은 아래 "다음 단계" 참고.
- 커밋/푸시는 평소처럼: `git add -A && git commit -m "..." && git push` → GitHub Pages 자동 재빌드.

## 자동 분류 (설계서 §3·§6-2) — `classify.py`

데스크톱(Mac/Windows)에서 수동 실행하는 얇은 분류기. **아이폰=읽기, 데스크톱=분류/쓰기**로 역할이 나뉘고 서버는 필요 없다. iCloud가 분류된 `inbox.md`를 아이폰에 동기화한다.

```bash
# 1) API 키 (저장소·iCloud엔 절대 두지 않음)
export ANTHROPIC_API_KEY=sk-ant-...          # 또는 홈 설정폴더에 저장(아래)
# 2) 미리보기 (API 호출 없이 분류 대상만)
python3 classify.py --plan
# 3) 분류만 해보기 (저장 안 함)
python3 classify.py --dry-run
# 4) 실제 분류 + 저장
python3 classify.py
```

- **미분류 줄만** 처리한다(아래에 `type:` 필드가 없는 항목). 이미 분류된 건 스킵 — 반복 실행해도 안전(멱등).
- **원문은 절대 바꾸지 않는다.** 원문은 인덱스로만 모델에 전달되고, 결과(JSON)만 받아 각 항목 아래에 `type/due/resurface/status` 필드만 덧붙인다.
- **시점**은 내용 맥락에서 추출하되 확정이 아니라 추정 — 앱이 "~까지 ?"로 표시(재확인).
- **안전장치:** 쓰기 전 `backups/`에 타임스탬프 백업, 임시파일→원자적 교체.
- **모델 교체 가능:** `classify.py`의 `MODEL` 상수(기본 `claude-opus-4-8`)를 `claude-sonnet-5`(저렴)/`claude-haiku-4-5`로 바꿀 수 있다(지능 층은 소모품, §0).
- **키 보관 대안:** 환경변수 대신 홈 설정폴더 파일에 둬도 된다 — `~/.config/secondbrain/anthropic_key`(Mac) / `%APPDATA%\secondbrain\anthropic_key`(Windows).

의존성: `pip install anthropic`.

### 자동 실행 (cron) — macOS `launchd`

수동 실행이 거슬릴 때, **한 기기에서** 정해진 시간에 자동 분류하도록 스케줄을 건다. (설계서 §0-A: 분류는 데스크톱에서만, **두 기기 동시 자동 실행 금지** — iCloud 덮어쓰기 위험. 그래서 스케줄은 한 대에만 설치한다.)

```bash
# 설치 (매시간 :00 실행). anthropic 설치된 python3 + 키 파일이 있으면 자동 구성
automation/setup-mac.sh

# 지금 1회 실행 / 상태 / 제거
launchctl kickstart -k gui/$(id -u)/com.secondbrain.classify
launchctl print gui/$(id -u)/com.secondbrain.classify | grep -E 'state|program'
automation/uninstall-mac.sh
```

- **키는 파일로 둬야 한다.** launchd는 셸 환경변수(`ANTHROPIC_API_KEY`)를 못 받으므로 `~/.config/secondbrain/anthropic_key`(권한 600)가 필요하다. `classify.py`가 이 파일에서 키를 읽는다.
- **미분류 줄이 없으면 API 호출 없이 즉시 끝난다**(멱등) → 매시간 돌려도 비용·부담 없음.
- 로그: `~/Library/Logs/secondbrain-classify.log` (실행 때마다 타임스탬프 블록, 자동으로 길이 제한).
- **다른 기기로 옮기려면** 이 기기에서 `uninstall-mac.sh`로 먼저 끄고 그 기기에 설치. (동시 실행 금지 유지.)
- Windows(작업 스케줄러) 설정은 아직 없음 — 필요할 때 추가.

## 파일 구조

```
index.html            앱 셸
app.css               스타일 (라이트/다크, 반응형, iOS 세이프에어리어)
app.js                UI·상태 (로드/렌더/검색/필터). window.SBApp 디버그 훅 노출
parser.js             inbox.md 파서 (순수 함수, DOM 무관)
manifest.webmanifest  PWA 매니페스트
sw.js                 서비스워커 (앱 셸만 오프라인 캐시, 개인 데이터 캐시 안 함)
icons/                PWA 아이콘 (192/512/apple-touch)
classify.py           자동 분류기 (§3·§6-2, Mac/Win, 읽기 앱과 분리)
automation/           자동 실행 스케줄 (macOS launchd): setup-mac.sh / run-classify.sh / uninstall-mac.sh
second-brain-v0-spec.md  설계서 사본 (코드와 근거 동봉)
add-2-inbox.ps1       0층 Windows 수집 스크립트 (참고용)
```

## 다음 단계 (설계서 §7 순서: A → D → C)

- **A. push (시점 알림) — ✅ 이번 구현.** 시점 채우기(분류 자동 추출 + 검토 화면 직접 지정) + 화면 강조(D-day·버킷). 잠금화면 푸시 알림은 iOS 제약·서버 문제로 보류(며칠 써보고 네이티브 전환 때 검토).
- **D. 분류 자동화 (cron) — ✅ macOS 구현.** `automation/setup-mac.sh`로 launchd 스케줄(매시간 :00)을 **한 기기에만** 설치(§0-A 동시 실행 금지). Windows 작업 스케줄러는 필요 시 추가.
- **C. 입구 개선:** 이미지 수집 4경로(촬영/복붙/파일지정/앱공유), URL 원클릭.
- **(선택) 폰→데스크톱 임시 시점 전달:** 재지정이 잦아 거슬리면 텍스트 내보내기/가져오기를 얹는다(지금은 열어만 둠).
- **네이티브 전환:** 웹 사용성 검증 후 iPhone 네이티브(진짜 백그라운드 알림·위젯).

> v0 성공 기준(§7): 기능 개수가 아니라 — **"30일 동안 매일 썼고, 잊을 뻔한 것을 시스템이 도로 들이밀어준 적이 있는가."**
