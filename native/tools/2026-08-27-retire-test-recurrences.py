#!/usr/bin/env python3
"""**시험용 되풀이 열 개를 그만두기(삭제)한다.** (2026-08-27 · 사용자 결정)

⛔ **이것은 「쓰는 도구」가 아니다 — 그날 그 데이터를 고친 기록이다.** 실행 완료.
**재실행 금지.** 파일명에 날짜가 있는 이유가 그것이고, 다시 필요하면 **날짜를 새로 붙여 복제**한다.
(선례: `2026-08-18-strip-auto-fields.py` — 그 머리주석의 지시를 그대로 따랐다.)

## 왜 했나
사용자: *"'지금 챙길 것'에 너무 많은 '되풀이' 기억이 빨간색으로 놓친 날짜가 많이 쌓인 채로 남아 있어.
… 개발 과정에서 시험용으로 만든 기억들이 많다. … 실제로 중요한 것들을 놓치게 하는 방해 요소야."*

## 무엇을 하나
`inbox-cleanup-20260827.md`를 새로 만들어 **`delete` op 열 줄만** 넣는다.
- ⛔ **기존 파일을 한 글자도 안 건드린다** — 앱은 `inbox`로 시작하는 `.md`를 **전부** 읽는다
  (`InboxStore`·`FragmentFolder`의 `hasPrefix("inbox")`). 그래서 새 파일로 충분하다.
- ⚠️ **맥 앱이 돌고 있어서 그렇게 했다** — 그 앱의 dev 파일에 끼어들지 않는다.
- ✅ **되돌릴 수 있다** — 삭제는 tombstone이고 「보관된 기억」의 왼쪽 스와이프 「되돌리기」로 살아난다.
  이 파일을 통째로 지워도 원상복구된다(op이 사라지므로).

## 안 지운 둘
- `E036A094` 「아침 간염 약 먹기!」 — op 50개 · **유일하게 정상 동작 중**(다음 회차가 미래).
- `616D4DCE` 「주차 위치」 — 시점이 없어 「지금 챙길 것」에 안 뜬다.
"""
import glob, os, re, sys, time

FOLDER = os.path.expanduser("~/Library/Mobile Documents/com~apple~CloudDocs/SecondBrain")
OUT    = "inbox-cleanup-20260827.md"
DEVICE = "cleanup-20260827"          # 파일명 ↔ 기기 id 대응(기존 규칙 그대로)

# 사용자가 고른 열 — 8자 접두 + 왜 골랐나
TARGETS = [
    ("EAB3BB92", "약 먹기 시험 용  E-6"),
    ("90D927B2", "감기약 먹기 시험용 감기약 먹기"),
    ("5ACEA309", "약 먹기 시험용"),
    ("131B923C", "나 -완료 시험"),
    ("092C76F1", "새 기억 하나만 됩니다"),
    ("AF9BAB30", "항목 가"),
    ("A9099FA3", "C D to 쉬다"),
    ("8BA73F15", "F-1"),
    ("9F950B73", "G-7 회기 08-11"),
    ("01781308", "복약 : 놓치는 약 먹기!"),
]

OP   = re.compile(r"^@ (\S+) \| ([0-9A-Fa-f-]{36}) \| (.*)$")
HEAD = re.compile(r"^- \d{4}-\d{2}-\d{2} \d{2}:\d{2} \| (\S+) \| ")

def scan(folder):
    """id 접두 → 전체 UUID · 지금 삭제 상태 · 파일 전체의 최대 HLC 밀리초."""
    full, deleted, maxms = {}, set(), 0
    for f in sorted(glob.glob(os.path.join(folder, "inbox*.md"))):
        for ln in open(f, encoding="utf-8", errors="replace"):
            m = OP.match(ln.rstrip("\n"))
            if not m: continue
            hlc, uid, verb = m.groups()
            try: maxms = max(maxms, int(hlc.split(".")[0]))
            except ValueError: pass
            full[uid[:8].upper()] = uid
            if verb.strip() == "delete":   deleted.add(uid)
            if verb.strip() == "undelete": deleted.discard(uid)
    return full, deleted, maxms

def main():
    apply = "--apply" in sys.argv
    folder = FOLDER
    full, deleted, maxms = scan(folder)

    nowms = int(time.time() * 1000)
    base = max(nowms, maxms + 1)          # ⛔ 기존 op보다 반드시 뒤여야 한다
    print(f"기존 최대 HLC 밀리초 = {maxms} · 지금 = {nowms} · 쓸 시작값 = {base}")
    if base != nowms:
        print("⚠️ 시계보다 앞선 op이 있어 최대값+1을 쓴다")

    lines, skipped = [], []
    for i, (short, text) in enumerate(TARGETS):
        uid = full.get(short)
        if not uid:
            skipped.append((short, text, "데이터에 없다")); continue
        if uid in deleted:
            skipped.append((short, text, "이미 삭제돼 있다")); continue
        lines.append(f"@ {base + i}.0.{DEVICE} | {uid} | delete\n")
        print(f"  쓸 것: {short}  {text}")

    for short, text, why in skipped:
        print(f"  ⛔ 건너뜀: {short}  {text}  — {why}")

    out = os.path.join(folder, OUT)
    if not apply:
        print(f"\n--- dry-run: {len(lines)}줄을 {OUT}에 쓸 것이다 (아직 안 썼다) ---")
        print("".join(lines), end="")
        print("--- 여기까지 · 실제로 쓰려면 --apply ---")
        return
    if os.path.exists(out):
        print(f"⛔ {OUT}가 이미 있다 — 재실행 금지(머리주석). 멈춘다."); sys.exit(1)
    with open(out, "w", encoding="utf-8") as fh:
        fh.write("".join(lines))
    print(f"\n✅ 썼다: {out}  ({len(lines)}줄)")

main()
