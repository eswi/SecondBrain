#!/usr/bin/env python3
"""미확정 항목에서 **자동이 쓴 필드를 걷어낸다.** (일회성 — 2026-08-18 실행 완료)

**파일명에 날짜가 있는 이유:** 이건 재사용 도구가 아니라 **그날 그 데이터를 고친 기록**이다.
`inbox-state.py`(상시 조사 도구)와 성격이 다르다. 다시 쓸 일이 생기면 **날짜를 새로 붙여 복제**한다.

────────────────────────────────────────────────────────────────────────
## 근거 — 결정 C (2026-08-18 사용자 결정)

> **자동 분류의 제안은 항목 필드에 쓰지 않는다.**
> 자동은 **제안을 준비**하고, 사람이 수락할 때 비로소 필드에 쓰이면서 함께 확정된다.
> **→ 미확정 항목의 필드는 비어 있는 것이 정상이다.**

정본은 `docs/native/memory-philosophy.md` §2-1-B. 이 스크립트는 **그 원칙 이전에 이미 써진 값**을
되돌린 것이다. **재개발 과정에서 또 걷어낼 일이 생길 수 있다** — 그때 이 파일을 본뜬다.

**왜 앱 화면으로 못 했나:** 임시 항목의 분류 변경은 **[기억하기]와 함께만 커밋**된다
(임시 상세엔 [저장]이 없다 — `edit-policy.md` §1-A). 지우려 하면 **확정돼 버린다.**
미확정을 유지한 채 필드를 비우는 길은 **파일 수정이 유일하다.**

────────────────────────────────────────────────────────────────────────
## 2026-08-18 실행 결과 (15:01:25 · 회사 맥북)

| 확인 | 전 | 후 |
|---|---|---|
| 미확정 8개의 분류 | idea 4 · 미분류 4 | **전부 미분류** |
| `inbox.md` 줄 | 490 | 478 (**−12**) |
| `inbox-dev-155f307a.md` op | 125 | 123 (**−2**) |
| **항목 수** | 72 | **72** (유실 0) |
| **`id`/`hlc`/`device`** | 71/71/71 | **71/71/71** (신원·성역 불변) |

**삭제한 것 = 14줄.** `inbox.md`에서 세 항목 × 4줄(`type: idea`·`due: none`·`resurface: weekly`·
`status: open`), `inbox-dev-155f307a.md`에서 `0E4B8C7F`의 `set type=idea` op 2줄.

**백업:** `backups/inbox.md.bak-20260818-150125` · `backups/inbox-dev-155f307a.md.bak-20260818-150125`

────────────────────────────────────────────────────────────────────────
**남기는 것:** 헤더 줄(원문·수집시각·방식) · `id:` · `hlc:` · `device:` — 신원과 성역이다.
  신원 근거: `EventLog.swift:53-55` — id/hlc가 있으면 그것이 신원(없을 때만 원문 해시 폴백).
  `status: open` 삭제 안전: `CompletionRoutingTests.testOpenOrNoStatus_isLive` — open이든 없든 live.
  `due: none`·`resurface: weekly`는 **날짜꼴이 아니라 원래 「시점 없음」**이다(기능 변화 없음 —
  자동이 쓴 값이라 지운 것). `resurface: weekly`는 레거시 웹 v0가 남긴 값이다.

쓰는 법:
    python3 2026-08-18-strip-auto-fields.py            # dry-run (기본) — diff만 보여준다
    python3 2026-08-18-strip-auto-fields.py --apply    # 백업 후 실제 수정

⚠️ **실행 전 앱을 모두 종료할 것**(폰·맥). 그리고 **`classify.py`의 launchd가 꺼져 있어야 한다** —
   살아 있으면 매시 :00에 `inbox.md`를 다시 덮어써 이 수정을 되돌린다
   (`automation/uninstall-mac.sh` · 2026-08-18 회사 맥북 차단 완료).

★ 설계 원칙 셋:
  ① **줄번호를 믿지 않는다.** `id:`로 블록을 찾고 그 안에서만 지운다 —
     한 줄 지우면 아래가 밀리는 문제가 원천적으로 없다.
  ② **정확히 일치할 때만 지운다.** 값까지 대조한다(`type: idea`이지 `type:`이 아니다).
     하나라도 어긋나면 **아무것도 안 건드리고 중단**한다(all-or-nothing).
  ③ **블록 경계를 파서와 같게 본다**(`EventLog.swift:36-42`) — 다음 `- ` 헤더 · 빈 줄 ·
     `@` 시작 · 들여쓰기 없는 줄에서 끊는다. 옆 항목을 침범할 수 없다.

※ 이미 실행됐으므로 지금 다시 돌리면 ②에 걸려 **「지울 필드를 못 찾았다」로 중단**한다. 정상이다.
"""
import os, re, sys, shutil, datetime, difflib

FOLDER = os.path.expanduser("~/Library/Mobile Documents/com~apple~CloudDocs/SecondBrain")

# id → 지울 (키, 값) 목록. **값까지 명시**한다 — 다른 값이면 사람이 바꾼 것일 수 있으므로 중단한다.
INBOX_TARGETS = {
    "F5433F49-B67C-467E-9941-EB7A94FF273C": [
        ("type", "idea"), ("due", "none"), ("resurface", "weekly"), ("status", "open")],
    "99E2B834-600D-4D9C-97C8-79527328ACFB": [
        ("type", "idea"), ("due", "none"), ("resurface", "weekly"), ("status", "open")],
    "516C17F0-2ED0-45C5-956A-87DBF927971C": [
        ("type", "idea"), ("due", "none"), ("resurface", "weekly"), ("status", "open")],
}

# 조각 파일에서 지울 op 줄 — **한 글자도 안 틀리게** 대조한다.
FRAGMENT_FILE = "inbox-dev-155f307a.md"
FRAGMENT_TARGETS = [
    "@ 1784851167908.173.dev-155f307a | 0E4B8C7F-E704-4866-BB47-CDE409608C48 | set type=idea",
    "@ 1784851167908.300.dev-155f307a | 0E4B8C7F-E704-4866-BB47-CDE409608C48 | set type=idea",
]

ITEM_RE = re.compile(r"^- \d{4}-\d{2}-\d{2} \d{2}:\d{2} \| ")
FIELD_RE = re.compile(r"^[ \t]+([A-Za-z_]+):[ \t]*(.*)$")


class Abort(Exception):
    pass


def block_end(lines, start):
    """`id:` 줄 다음부터 블록이 어디서 끝나는지. EventLog.swift의 경계 규칙과 같게."""
    j = start
    while j < len(lines):
        l = lines[j]
        t = l.strip()
        if ITEM_RE.match(l):            break   # 다음 항목 헤더
        if t == "":                     break   # 빈 줄
        if l.startswith("@"):           break   # 변이 이벤트
        if not (l[:1] == " " or l[:1] == "\t"): break   # 들여쓰기 없음
        j += 1
    return j


def fix_inbox(path):
    lines = open(path, encoding="utf-8").readlines()
    kill = set()
    for uid, targets in INBOX_TARGETS.items():
        idx = [i for i, l in enumerate(lines) if l.strip() == f"id: {uid}"]
        if len(idx) != 1:
            raise Abort(f"{uid}: `id:` 줄이 {len(idx)}개다(1개여야 한다). 중단.")
        i = idx[0]
        # 블록의 시작(헤더)과 끝을 잡는다. 헤더는 id 줄 바로 위쪽에서 거슬러 찾는다.
        h = i
        while h >= 0 and not ITEM_RE.match(lines[h]):
            h -= 1
        if h < 0:
            raise Abort(f"{uid}: 항목 헤더를 못 찾았다. 중단.")
        end = block_end(lines, i + 1)

        found = {}
        for j in range(h + 1, end):
            m = FIELD_RE.match(lines[j].rstrip("\n"))
            if not m:
                continue
            k, v = m.group(1).lower(), m.group(2).strip()
            for tk, tv in targets:
                if k == tk:
                    if v != tv:
                        raise Abort(
                            f"{uid}: `{k}`의 값이 예상과 다르다 — 예상 {tv!r}, 실제 {v!r}. "
                            f"사람이 바꿨을 수 있다. 중단.")
                    found[tk] = j
        missing = [tk for tk, _ in targets if tk not in found]
        if missing:
            raise Abort(f"{uid}: 지울 필드를 못 찾았다 — {missing}. 이미 고쳤나? 중단.")
        kill.update(found.values())

    expect = sum(len(v) for v in INBOX_TARGETS.values())
    if len(kill) != expect:
        raise Abort(f"지울 줄 수가 안 맞는다 — 예상 {expect}, 실제 {len(kill)}. 중단.")
    new = [l for i, l in enumerate(lines) if i not in kill]
    return lines, new, sorted(i + 1 for i in kill)


def fix_fragment(path):
    lines = open(path, encoding="utf-8").readlines()
    kill = set()
    for target in FRAGMENT_TARGETS:
        idx = [i for i, l in enumerate(lines) if l.rstrip("\n") == target]
        if len(idx) != 1:
            raise Abort(f"op 줄이 {len(idx)}개다(1개여야 한다):\n  {target}\n중단.")
        kill.add(idx[0])
    if len(kill) != len(FRAGMENT_TARGETS):
        raise Abort("op 줄 수가 안 맞는다. 중단.")
    new = [l for i, l in enumerate(lines) if i not in kill]
    return lines, new, sorted(i + 1 for i in kill)


def show(path, old, new, killed):
    print(f"\n{'='*72}\n{path}\n  지울 줄: {killed}  ({len(old)} → {len(new)}줄)\n{'='*72}")
    for d in difflib.unified_diff(old, new, "before", "after", n=3):
        print("  " + d.rstrip("\n"))


def main():
    apply = "--apply" in sys.argv
    inbox = os.path.join(FOLDER, "inbox.md")
    frag = os.path.join(FOLDER, FRAGMENT_FILE)
    for p in (inbox, frag):
        if not os.path.isfile(p):
            sys.exit(f"파일이 없다: {p}")

    try:
        i_old, i_new, i_kill = fix_inbox(inbox)
        f_old, f_new, f_kill = fix_fragment(frag)
    except Abort as e:
        sys.exit(f"\n⛔ 중단 — 아무것도 안 건드렸다.\n   {e}")

    show(inbox, i_old, i_new, i_kill)
    show(frag, f_old, f_new, f_kill)

    if not apply:
        print("\n※ dry-run이다. 파일은 안 건드렸다. 실제로 고치려면 --apply 를 붙인다.")
        return

    stamp = datetime.datetime.now().strftime("%Y%m%d-%H%M%S")
    bdir = os.path.join(FOLDER, "backups")
    os.makedirs(bdir, exist_ok=True)
    for src, new in ((inbox, i_new), (frag, f_new)):
        bak = os.path.join(bdir, f"{os.path.basename(src)}.bak-{stamp}")
        shutil.copy2(src, bak)
        print(f"백업: {bak}")
        with open(src, "w", encoding="utf-8") as fh:
            fh.writelines(new)
        print(f"수정: {src}")
    print(f"\n✅ 완료. 되돌리려면:\n"
          f"  cp {bdir}/inbox.md.bak-{stamp} {inbox}\n"
          f"  cp {bdir}/{FRAGMENT_FILE}.bak-{stamp} {frag}")


if __name__ == "__main__":
    main()
