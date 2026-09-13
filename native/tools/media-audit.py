#!/usr/bin/env python3
"""자료 검산 — **포인터와 파일이 서로 맞나.**

## 왜 있나 — 옛 검산식이 「항목 id와 1:1」 위에 서 있었다

2026-08-20 이관은 **「포인터 고유 수 = 항목 id와 1:1 · 고아 0 · 누락 0」**으로 검산했다.
2026-08-23에 **조회의 축이 파일명으로 바뀌고**(C) **한 항목이 자료를 여럿 가질 수 있게** 되면서
**그 전제가 깨졌다.** 그래서 검산식을 다시 세운 것이 이 도구다
(설계 `docs/native/media-expansion-design.md` §3-X).

## 새 검산식 — 셋

    누락   포인터가 가리키는 이름인데 파일이 없다        ← 화면에서 「어디에도 없다」로 보인다
    고아   파일은 있는데 아무 포인터도 안 가리킨다        ← 지워도 업로더가 다시 올릴 수 있다
    겹침   한 파일 이름을 포인터 둘 이상이 가리킨다        ← ⛔ 삭제가 남의 자료를 지운다

⛔ **「항목당 하나」는 이제 검산 대상이 아니다** — 여럿이 정상이다. 검산하는 것은 **이름의 대응**이다.

## ★★ 포인터는 **쌓는 것이 아니라 해소하는 것**이다 (2026-09-13에 고쳤다)

⛔ **옛 꼴(지우지 않고 적어 둔다): 본 포인터를 전부 쌓았다** — `set photo.<자료id>=` 처럼
**빈 값으로 지운 것도 그대로 세고 있었다.** 그래서 **2026-09-03에 「사진 지우기」로 지운 여섯 장**이
**「누락 6」**으로 나왔다(파일은 이미 지워졌고 포인터도 이미 비워졌는데).
★ **도구가 그 기능보다 오래됐다** — 검산식은 맞았고 **읽는 법이 낡았다.**

✅ **지금은 조각 전부를 합쳐 「지금 값」을 구한 뒤 그것으로 검산한다** — 앱과 같은 규칙으로:
- **필드별 LWW · 엄격한 `>`** (같은 HLC는 안 덮는다) — Core `MergeEngine.merge`
- **빈 값은 자료가 아니다** — Core `MediaPointer.pointers`가 `!v.isEmpty`로 거른다
  (⚠️ **`MergeEngine`은 빈 값을 「지움」으로 접지 않고 `""`로 들고 있는다** — 거르는 쪽이 읽는 쪽이다)

## ⛔ URL은 이 셋의 대상이 **아니다** (2026-08-24 · 설계 §3-Z)

**URL 자료는 파일이 없다** — 포인터 값이 자료 자신이다. 그래서 **누락·고아·겹침 셋이 성립하지 않는다**
(가리킬 파일이 없고, 남을 파일이 없고, 겹칠 파일이 없다).
✅ **그래도 세어서 보인다** — ⛔ 안 보이면 다음 세션이 **「자료 총수」를 잘못 센다**
(이 도구가 URL을 아예 안 읽던 것이 2026-08-24에 발견됐다).
⚠️ **URL에는 「미리보기 캐시」가 딸릴 수 있는데 그것도 검산 대상이 아니다** — **기기에만 있고
iCloud에 없다**(설계 §3-Z-2 E). 폴더에서 찾으려 하지 말 것.

## 쓰기

    python3 native/tools/media-audit.py                 # iCloud 기본 경로
    python3 native/tools/media-audit.py <폴더>           # 조각 파일과 audio/·photo/가 있는 폴더

⚠️ **파일 내용을 안 읽는다 — 이름만 본다.** 그래서 **dataless를 받아오지 않는다**(상태를 안 바꾼다).
⚠️ iCloud 동기화 지연이 있다 — 폰에서 방금 한 것은 아직 안 보일 수 있다(`inbox-state.py`와 같은 주의).
"""
import os
import re
import sys
from collections import defaultdict

DEFAULT = os.path.expanduser("~/Library/Mobile Documents/com~apple~CloudDocs/SecondBrain")

# 종류 → 하위 폴더·확장자 (Core의 `MediaKind`와 같아야 한다)
# ⚠️ **여기에 url을 더하지 말 것** — `MediaKind`에 url이 없는 것과 같은 이유다(파일이 아니다).
KINDS = {"audio": "m4a", "photo": "jpg"}

# 파일이 없는 종류 — 세기만 한다(검산 셋의 대상이 아니다). Core의 `MediaPointer.Kind`와 짝.
FILELESS = ("url",)

# 포인터 필드: 옛 단일(`photo`)과 새 꼴(`photo.<자료id>`) 둘 다. url도 함께 읽는다(세기용).
FIELD = re.compile(r"^(audio|photo|url)(?:\.([0-9a-f]+))?$")


ZERO = (0, 0, "")


def hlc(s):
    """`<밀리초>.<카운터>.<기기>` → 견줄 수 있는 값. Core `HLC.init?(serialized:)`와 같은 꼴."""
    parts = s.split(".", 2)                 # ⚠️ 기기 이름에 `.`이 있을 수 있어 앞 둘만 가른다
    if len(parts) != 3:
        return ZERO
    try:
        return (int(parts[0]), int(parts[1]), parts[2])
    except ValueError:
        return ZERO


def put(state, item, key, value, at):
    """필드별 LWW — ⛔ **엄격한 `>`**(Core `MergeEngine`과 같다: 같은 HLC는 안 덮는다)."""
    if not item:
        return
    cur = state[item].get(key)
    if cur is None or at > cur[0]:
        state[item][key] = (at, value)


def resolve(folder):
    """{항목: {필드: (HLC, 값)}} — 조각 전부를 합친 **지금 값.** 빈 값도 그대로 들고 있는다."""
    state = defaultdict(dict)
    for fn in sorted(os.listdir(folder)):
        if not (fn.startswith("inbox") and fn.endswith(".md")):
            continue
        # create 블록은 **`hlc:`를 읽은 뒤에야** 적용할 수 있다 — 그래서 모았다가 블록 끝에서 넣는다.
        item, at, block = None, ZERO, []
        for line in open(os.path.join(folder, fn), encoding="utf-8", errors="replace"):
            s = line.strip()
            if line.startswith("- ") and "|" in line:      # create 블록 머리 — 앞 블록을 닫는다
                for k, v in block:
                    put(state, item, k, v, at)
                item, at, block = None, ZERO, []
                continue
            if line.startswith("@"):                       # 변이 줄 — `set k=v …`
                for k, v in block:
                    put(state, item, k, v, at)
                item, at, block = None, ZERO, []
                parts = [p.strip() for p in line[1:].split("|")]
                if len(parts) >= 3 and parts[2].startswith("set "):
                    ophlc, mid = hlc(parts[0]), parts[1]
                    for tok in parts[2][4:].split():
                        k, _, v = tok.partition("=")
                        if FIELD.match(k):
                            put(state, mid, k, v, ophlc)   # ★ 빈 값도 넣는다 — 그것이 「지웠다」다
                continue
            if s.startswith("id:"):
                item = s[3:].strip()
                continue
            if s.startswith("hlc:"):
                at = hlc(s[4:].strip())
                continue
            if item and (s.startswith("audio") or s.startswith("photo") or s.startswith("url")):
                k, _, v = s.partition(":")
                if FIELD.match(k.strip()):
                    block.append((k.strip(), v.strip()))
                continue
        for k, v in block:                                 # 파일 끝 — 마지막 블록을 닫는다
            put(state, item, k, v, at)
    return state


def pointers(folder):
    """{종류: {파일명: [항목 id…]}} — **지금 값**에서 살아 있는 포인터만 모은다."""
    out = {k: defaultdict(list) for k in list(KINDS) + list(FILELESS)}
    for item, fields in resolve(folder).items():
        for k, (_, v) in fields.items():
            if not v:                                      # ★ 빈 값 = 지웠다 — 자료가 아니다
                continue
            m = FIELD.match(k)
            if m:
                out[m.group(1)][v].append(item)
    return out


def files(folder, kind):
    """그 종류의 파일 이름들 — 하위 폴더와 `sb-` 폴백 자리 둘 다(Core `MediaPlace`)."""
    names = set()
    sub = os.path.join(folder, kind)
    if os.path.isdir(sub):
        names |= {n for n in os.listdir(sub) if n.endswith("." + KINDS[kind])}
    for n in os.listdir(folder):
        if n.startswith("sb-") and n.endswith("." + KINDS[kind]):
            names.add(n[3:])                                # 폴백 접두사를 뗀 「이름」으로 센다
    return names


def main():
    folder = sys.argv[1] if len(sys.argv) > 1 else DEFAULT
    if not os.path.isdir(folder):
        sys.exit(f"폴더가 없다: {folder}")
    ptr = pointers(folder)
    bad = 0
    print(f"폴더: {folder}\n")
    for kind in KINDS:
        have, want = files(folder, kind), ptr[kind]
        missing = sorted(n for n in want if n not in have)
        orphan = sorted(n for n in have if n not in want)
        dup = sorted(n for n, ids in want.items() if len(set(ids)) > 1)
        print(f"[{kind}] 포인터 {len(want)}개 · 파일 {len(have)}개")
        print(f"  누락 {len(missing)} · 고아 {len(orphan)} · 겹침 {len(dup)}")
        for label, names in (("누락", missing), ("고아", orphan), ("겹침", dup)):
            for n in names[:20]:
                extra = f"  ← {sorted(set(want[n]))}" if label != "고아" else ""
                print(f"    {label}: {n}{extra}")
            if len(names) > 20:
                print(f"    … {len(names) - 20}개 더")
        bad += len(missing) + len(orphan) + len(dup)
        print()

    # 파일이 없는 종류 — **세기만 한다.** ⛔ 검산 셋에 더하지 않는다(성립하지 않는다).
    for kind in FILELESS:
        vals = ptr[kind]
        print(f"[{kind}] 포인터 {len(vals)}개 — ⛔ 파일이 없는 종류라 누락·고아·겹침을 안 본다")
        for v in sorted(vals)[:10]:
            print(f"    {v}  ← {sorted(set(vals[v]))}")
        if len(vals) > 10:
            print(f"    … {len(vals) - 10}개 더")
        print()

    print("✅ 셋 다 0" if bad == 0 else f"⚠️ 어긋난 것 {bad}개 — 위 목록을 본다")
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
