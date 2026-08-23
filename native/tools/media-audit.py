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
KINDS = {"audio": "m4a", "photo": "jpg"}

# 포인터 필드: 옛 단일(`photo`)과 새 꼴(`photo.<자료id>`) 둘 다.
FIELD = re.compile(r"^(audio|photo)(?:\.([0-9a-f]+))?$")


def pointers(folder):
    """{종류: {파일명: [항목 id…]}} — 조각 파일 전부에서 포인터 값을 모은다."""
    out = {k: defaultdict(list) for k in KINDS}
    for fn in sorted(os.listdir(folder)):
        if not (fn.startswith("inbox") and fn.endswith(".md")):
            continue
        item = None
        for line in open(os.path.join(folder, fn), encoding="utf-8", errors="replace"):
            s = line.strip()
            if line.startswith("- ") and "|" in line:      # create 블록 머리
                item = None
                continue
            if s.startswith("id:"):
                item = s[3:].strip()
                continue
            if line.startswith("@"):                       # 변이 줄 — `set k=v …`
                parts = [p.strip() for p in line[1:].split("|")]
                if len(parts) >= 3:
                    mid, verb = parts[1], parts[2]
                    if verb.startswith("set "):
                        for tok in verb[4:].split():
                            k, _, v = tok.partition("=")
                            m = FIELD.match(k)
                            if m and v:
                                out[m.group(1)][v].append(mid)
                continue
            if item and (s.startswith("audio") or s.startswith("photo")):
                k, _, v = s.partition(":")
                m = FIELD.match(k.strip())
                if m and v.strip():
                    out[m.group(1)][v.strip()].append(item)
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
    print("✅ 셋 다 0" if bad == 0 else f"⚠️ 어긋난 것 {bad}개 — 위 목록을 본다")
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
