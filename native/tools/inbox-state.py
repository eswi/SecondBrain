#!/usr/bin/env python3
"""실데이터(`inbox*.md`)를 병합해 **항목의 지금 상태**를 찍는다. (2026-08-18 신설)

쓰는 법 (iCloud 폴더에서 실행하거나 --dir로 지정):
    python3 native/tools/inbox-state.py --dir ~/Library/Mobile\\ Documents/com~apple~CloudDocs/SecondBrain
    python3 native/tools/inbox-state.py --type recurrence          # 되풀이만
    python3 native/tools/inbox-state.py --unconfirmed              # 미확정(임시)만
    python3 native/tools/inbox-state.py --id 01781308              # 한 항목 전체 필드

**왜 있나 — 계측 규칙 7의 「목록·소속·이름」을 데이터에서 계산하려고.**
`CLAUDE.md`는 *"표본은 이름이 닮았나로 고르지 말고 「무엇이 이것을 그것이게 하는가」를
데이터에서 계산한다"*고 못 박는다. 그런데 그러려면 **op 로그를 순서대로 접어야** 하고,
그때마다 즉석 스크립트를 쓰면 **다음 세션·다른 기기가 처음부터 다시 짠다.**
2026-08-18 세션에서 세 번 다시 짰다(미확정 집계 · 되풀이 전수 · 삭제 후보 판정).

⚠️ **읽기 전용이다.** 파일을 쓰지 않는다. 판정 근거를 만들 뿐 조작은 사람이 폰에서 한다.

────────────────────────────────────────────────────────────────────────
**밟은 함정 넷 (이 파서가 그래서 이렇게 생겼다):**

① **`resurface: weekly`는 날짜가 아니다.** 레거시 웹 v0가 넣은 값이라 「시점 있음」으로 세면
   미확정 항목의 소속 섹션이 통째로 틀린다. **날짜꼴(`YYYY-MM-DD`)인지 봐야 한다.**
   2026-08-18에 이걸로 한 번 잘못 셌다(8개 → 실제 0개).
② **`edit` op의 값은 다음 줄 `fields.v1:` JSON에 있다.** `키=값` 정규식만 쓰면 원문·분류 편집을 통째로 놓친다.
③ **op은 HLC 순서로 접어야 한다.** 파일 순서가 아니다(조각 파일이 여러 개고 기기마다 따로 쓴다).
   HLC = `<밀리초>.<카운터>.<기기>`.
④ **삭제는 tombstone**(`delete` op)이고 `undelete`로 되살아난다. `status: done`과 다른 축이다.

⚠️ **이 도구가 모르는 것 — 분류 게이트.** `ItemSchedule`은 **분류마다 쓰는 시점 칸이 다르다**
   (`deadlineDay`·`gatedResurface`). 여기서는 **필드가 있나만** 본다. 「지금 챙길 것에 뜨나」를
   정확히 가르려면 그 게이트까지 봐야 한다 — **결론은 앱 화면에서 닫을 것**(계측 규칙 4).

⚠️ **iCloud 지연.** 폰이 방금 한 것이 맥에 아직 안 왔을 수 있다(2026-08-14에 **한 시간 넘게** 늦었다).
   파일 mtime을 함께 찍는 이유다. **폰 화면과 어긋나면 파일이 뒤처진 것으로 볼 것.**
"""
import argparse, glob, json, os, re, sys, datetime

DATEISH = re.compile(r"^\d{4}-\d{2}-\d{2}")
HEAD = re.compile(r"^- (\d{4}-\d{2}-\d{2}) (\d{2}:\d{2}) \| (\S+) \| (.*)$")
OP = re.compile(r"^@ (\S+) \| ([0-9A-Fa-f-]+) \| (.*)$")
FIELD = re.compile(r"^\s{2,}(\w+):\s*(.*)$")
FIELDS_V1 = re.compile(r"^\s+fields\.v1:\s*(\{.*\})\s*$")


def hlc_key(h):
    p = h.split(".")
    ms = int(p[0]) if p[0].isdigit() else 0
    ctr = int(p[1]) if len(p) > 1 and p[1].isdigit() else 0
    return (ms, ctr, h)


def load(directory):
    """`inbox*.md` 전부를 읽어 {id: {raw, fields, ops}}로 접는다."""
    items, ops = {}, []
    files = sorted(glob.glob(os.path.join(directory, "inbox*.md")))
    if not files:
        sys.exit(f"inbox*.md를 못 찾았다: {directory}")
    for path in files:
        cur = None
        for line in open(path, encoding="utf-8").read().splitlines():
            m = HEAD.match(line)
            if m:                                   # create(항목 머리 줄)
                cur = {"date": m.group(1), "time": m.group(2), "source": m.group(3),
                       "raw": m.group(4), "fields": {}, "file": os.path.basename(path)}
                continue
            o = OP.match(line)
            if o:                                   # op 줄 — 머리 줄 블록이 끝난다
                cur = None
                ops.append([o.group(1), o.group(2), o.group(3)])
                continue
            fv = FIELDS_V1.match(line)
            if fv and cur is None and ops:          # 함정 ② — 직전 edit op의 값
                ops[-1][2] = "JSON " + fv.group(1)
                continue
            if cur is not None:
                f = FIELD.match(line)
                if f:
                    k, v = f.group(1), f.group(2).strip()
                    if k == "id":
                        cur["id"] = v
                        items[v] = cur
                    else:
                        cur["fields"][k] = v
    opcount = {}
    for hlc, iid, body in sorted(ops, key=lambda x: hlc_key(x[0])):   # 함정 ③
        it = items.setdefault(iid, {"raw": None, "fields": {}, "file": "?"})
        opcount[iid] = opcount.get(iid, 0) + 1
        if body.startswith("JSON "):
            for k, v in json.loads(body[5:]).items():
                it["fields"][k] = str(v)
        elif body.strip() == "delete":                                # 함정 ④
            it["fields"]["deleted"] = "true"
        elif body.strip() == "undelete":
            it["fields"].pop("deleted", None)
        else:
            for k, v in re.findall(r"(\w+)=([^\s]*)", body):
                it["fields"][k] = v
    for iid, it in items.items():
        it["ops"] = opcount.get(iid, 0)
    return items


def has_schedule(f):
    """시점(마감·미리 알림)이 **날짜로** 있나. 함정 ① — `weekly` 같은 레거시 값은 아니다."""
    return bool(DATEISH.match(f.get("due", "") or "")) or bool(DATEISH.match(f.get("resurface", "") or ""))


def section(f):
    """앱의 세 섹션 중 어디로 가나 (`InboxModel.partition`을 따라감). 분류 게이트는 안 본다 — 머리주석 참조."""
    if f.get("deleted") == "true" or f.get("type") == "discard":
        return "삭제된 기억"
    if f.get("status") == "done":
        return "완료된 기억"
    if f.get("type") == "principle":
        return "원칙 띠"
    if has_schedule(f):
        return "지금 챙길 것"
    return "새 기억들" if f.get("confirmed") != "true" else "살아있는 기억"


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--dir", default=os.path.expanduser(
        "~/Library/Mobile Documents/com~apple~CloudDocs/SecondBrain"))
    ap.add_argument("--type", help="분류로 거르기 (recurrence·idea·principle …)")
    ap.add_argument("--unconfirmed", action="store_true", help="미확정(임시)만")
    ap.add_argument("--section", help="섹션으로 거르기 (새 기억들·지금 챙길 것 …)")
    ap.add_argument("--id", help="한 항목의 전체 필드를 찍는다 (앞 8자리로도 됨)")
    ap.add_argument("--all", action="store_true", help="삭제·완료된 것까지 포함")
    args = ap.parse_args()

    items = load(args.dir)
    for p in sorted(glob.glob(os.path.join(args.dir, "inbox*.md"))):
        mt = datetime.datetime.fromtimestamp(os.path.getmtime(p))
        print(f"  {os.path.basename(p):32} 마지막 쓰기 {mt:%Y-%m-%d %H:%M}")
    print(f"  ⚠️ iCloud 지연이 한 시간 넘은 적이 있다 — 폰 화면과 어긋나면 이 파일이 뒤처진 것이다.\n")

    if args.id:
        for iid, it in items.items():
            if iid.upper().startswith(args.id.upper()):
                print(f"{iid}  ({it.get('file')})\n  원문: {it.get('raw')}\n  op {it.get('ops', 0)}개"
                      f"  → 섹션: {section(it['fields'])}")
                for k, v in sorted(it["fields"].items()):
                    print(f"    {k:16} {v}")
        return

    today = datetime.date.today()
    rows = []
    for iid, it in items.items():
        f = it["fields"]
        sec = section(f)
        if not args.all and sec in ("삭제된 기억", "완료된 기억"):
            continue
        if args.type and f.get("type") != args.type:
            continue
        if args.unconfirmed and f.get("confirmed") == "true":
            continue
        if args.section and sec != args.section:
            continue
        due = f.get("due", "") or "-"
        dd = ""
        if DATEISH.match(due):
            d = datetime.date(*map(int, due[:10].split("-")))
            dd = f"D+{(today - d).days}" if (today - d).days > 0 else str((today - d).days)
        rows.append((iid, (it.get("raw") or "")[:24], f.get("type", "-"), sec, due, dd,
                     f.get("recur", "-"),
                     "없음" if not f.get("lastDoneDue") else "있음",
                     "예" if f.get("confirmed") == "true" else "아니오",
                     f.get("recurPaused", "-"), it.get("ops", 0)))
    rows.sort(key=lambda r: (r[3], r[4]))
    print(f"{'id':10}{'원문':26}{'분류':12}{'섹션':14}{'due':20}{'D+':6}"
          f"{'recur':8}{'lastDoneDue':12}{'확정':6}{'꺼둠':6}{'op'}")
    for r in rows:
        print(f"{r[0][:8]:10}{r[1]:26}{r[2]:12}{r[3]:14}{r[4]:20}{r[5]:6}"
              f"{r[6]:8}{r[7]:12}{r[8]:6}{r[9]:6}{r[10]}")
    print(f"\n합계 {len(rows)}개")


if __name__ == "__main__":
    main()
