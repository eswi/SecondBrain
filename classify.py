#!/usr/bin/env python3
# ⛔ 이 파일은 「지금은 쓰지 않는 것」이다.
#    자동 분류는 2026-08-18에 앱에서 진입점 둘을 막았고(`ClassifyPause`),
#    2026-08-21에 **zero base로 새로 설계**하기로 정해졌다(CLAUDE.md 항시 규칙 8).
#    이 파일은 그 결정 '이전'에 만들어졌고, 인수 없이 돌리면 iCloud inbox.md에
#    **type·due·resurface·status·question을 직접 써넣는다** — 결정 C(자동의 제안은
#    항목 필드에 쓰지 않는다)를 정면으로 위반한다.
#    ⛔⛔ **그리고 아래 SYSTEM_PROMPT에 `discard`가 그대로 있다.** 앱(`classifyFields`)에는
#         「AI가 사람이 수집한 기억을 조용히 삭제하면 안 됨」 방어가 있지만 **여기엔 없다.**
#         2026-07-24에 이 경로가 `D6E4950B`(사람이 확정한 기억)까지 버렸다.
#    ⚠️ 저장하지 않는 모드 둘: --plan(API 호출 없음 · 대상만 표시) · --dry-run(호출하되 저장 안 함).
#    고치거나 지우지 말 것 — 표시만 해 둔다. 되살릴지는 사용자가 정한다.
#    근거: CLAUDE.md 항시 규칙 8 · docs/native/memory-philosophy.md §2-1-B
#          (그 절의 「자동은 준비까지, 결정은 사용자가」).
#
"""classify.py — 받은함 자동 분류기 (설계서 §3·§6-2)

데스크톱(Mac/Windows)에서 수동 실행한다. iCloud의 inbox.md에서 '아직 분류 안 된 줄'만
골라 Claude로 분류하고, 원문은 절대 바꾸지 않고 그 아래에 type/due/resurface/status
필드만 덧붙여 저장한다. iCloud가 결과를 아이폰에 동기화 → 웹 앱(리더)이 읽는다.

  실행:   python3 classify.py            # 실제 분류 + 저장
          python3 classify.py --dry-run  # 분류만 해보고 저장 안 함(미리보기)
          python3 classify.py --plan     # API 없이, 어떤 줄이 분류 대상인지만 표시
          python3 classify.py --inbox /경로/inbox.md   # 경로 직접 지정

  API 키: 환경변수 ANTHROPIC_API_KEY 우선. 없으면 홈 설정폴더의 anthropic_key.
          (저장소·iCloud 어디에도 키를 두지 않는다.)
"""
import argparse
import json
import os
import platform
import re
import shutil
import sys
from datetime import datetime

# 지능 층은 소모품(설계서 §0) — 필요하면 claude-sonnet-5(저렴) / claude-haiku-4-5로 교체.
MODEL = "claude-opus-4-8"

# 한 줄 항목: "- 날짜 시각 | source | 원문"  /  필드: 들여쓴 "key: value"
ITEM_RE = re.compile(r"^-\s+(\d{4}-\d{2}-\d{2})\s+(\d{1,2}:\d{2})\s+\|\s+([^|]+?)\s+\|\s+(.*)$")
FIELD_RE = re.compile(r"^\s+([A-Za-z_]+):\s*(.*)$")
INDENTED_RE = re.compile(r"^\s+\S")

SYSTEM_PROMPT = """다음은 사용자의 받은함(inbox)의 미가공 수집 줄들이다. 각 줄을 아래 규칙으로 분류하라.

분류(type): event(예정된 일) / promise(부탁·약속) / info-action(이걸로 뭘 해야겠다) / info(행동은 필요 없지만 나중에 참고할 사실·정보) / idea(생각) / discard(버릴 것)

각 항목에 붙일 것:
- type
- due: 날짜가 명시되거나 맥락에서 추론되면 YYYY-MM-DD, 없으면 "none"
- resurface: due가 있으면 그 며칠 전 날짜(YYYY-MM-DD), 없으면 "none"
- status: 항상 "open"
- question: info-action인데 "구체적으로 뭘, 언제 할지"가 불명확하면 그 한 줄 질문. 아니면 빈 문자열.

규칙:
- 짧다는 이유만으로 버리지 마라. 파편이라도 다음이면 info(정보·참고)로 보존하라:
  (1) 장소·위치 정보(예: 주차 위치 "지하 왼쪽 구멍"), (2) 특정 인물에 대한 메모·평가(예: "김형석대표는 책임감으로 산 책 다 읽는다"), (3) 나중에 참고할 사실.
- discard는 테스트/시스템 입력('시험 중', '음성 메모 추가' 등)이나, 받아쓰기 실패로 의미를 알 수 없는 조각에만 한정하라.
- 사람과의 약속(promise)은 절대 놓치지 말고 보수적으로 잡아라.
- 시점(due) 추출을 적극적으로 하라. 상대 표현은 반드시 '오늘 날짜' 기준 구체 날짜(YYYY-MM-DD)로 환산한다:
  "오늘"=오늘, "내일"=오늘+1, "모레"=오늘+2, "이번 주"=이번 주 일요일, "다음 주"=다음 주 일요일,
  "이번 달 말"=이달 마지막 날, "N일까지/N월 N일"=그 날짜. 연도가 없으면 오늘 기준 가장 가까운 미래로 잡는다.
- due가 잡히면 resurface는 그 며칠 전(promise/event는 2~3일 전, 여유가 없으면 due 하루 전)으로 둬라.
  단 resurface는 **마감보다 최소 하루 빨라야 한다(규칙 1)** — 마감 당일이 될 만큼 여유가 없으면 resurface는 "none"으로 둬라.
- 명시적·추론 가능한 시점이 전혀 없으면 due는 "none". 시점은 확정이 아니라 추정이며, 앱이 "~까지"로 표시하고 사람이 확인한다.
- 하루를 시작할 때의 다짐·생활 원칙 같은 반복 인지용 문장은 type을 principle 로 하라(원칙).
- 원문은 절대 바꾸지 마라. 너는 분류 결과(JSON)만 돌려준다. 원문 텍스트는 반환하지 않는다.
- 각 입력 줄에는 index가 붙어 있다. 반드시 그 index로 결과를 대응시키고, 모든 줄을 빠짐없이 분류하라."""

SCHEMA = {
    "type": "object",
    "properties": {
        "classifications": {
            "type": "array",
            "items": {
                "type": "object",
                "properties": {
                    "index": {"type": "integer"},
                    "type": {"type": "string", "enum": ["event", "promise", "info-action", "info", "idea", "principle", "discard"]},
                    "due": {"type": "string"},
                    "resurface": {"type": "string"},
                    "status": {"type": "string"},
                    "question": {"type": "string"},
                },
                "required": ["index", "type", "due", "resurface", "status", "question"],
                "additionalProperties": False,
            },
        }
    },
    "required": ["classifications"],
    "additionalProperties": False,
}


def default_inbox_path():
    sysname = platform.system()
    if sysname == "Darwin":
        return os.path.expanduser("~/Library/Mobile Documents/com~apple~CloudDocs/SecondBrain/inbox.md")
    if sysname == "Windows":
        # iCloud Drive on Windows: %USERPROFILE%\iCloudDrive\SecondBrain (실제 사용자 홈으로 해석)
        return os.path.join(os.path.expanduser("~"), "iCloudDrive", "SecondBrain", "inbox.md")
    # Linux 등: 명시 지정 필요
    return os.path.expanduser("~/SecondBrain/inbox.md")


def get_api_key():
    k = os.environ.get("ANTHROPIC_API_KEY")
    if k:
        return k
    if platform.system() == "Windows":
        p = os.path.join(os.environ.get("APPDATA", ""), "secondbrain", "anthropic_key")
    else:
        p = os.path.expanduser("~/.config/secondbrain/anthropic_key")
    if os.path.exists(p):
        with open(p, encoding="utf-8") as f:
            return f.read().strip()
    return None


def parse_blocks(lines):
    """각 항목을 블록으로 나눈다. classified = 이미 type: 필드가 있는지.
    insert_after = 이 인덱스의 줄 '뒤'에 새 필드를 끼워 넣는다(= 블록의 마지막 줄)."""
    blocks = []
    i, n = 0, len(lines)
    while i < n:
        m = ITEM_RE.match(lines[i])
        if not m:
            i += 1
            continue
        start = i
        last = i  # 블록의 마지막 줄 인덱스
        classified = False
        j = i + 1
        while j < n:
            line = lines[j]
            if ITEM_RE.match(line) or line.strip() == "":
                break
            if INDENTED_RE.match(line):
                fm = FIELD_RE.match(line)
                if fm and fm.group(1).lower() == "type":
                    classified = True
                last = j
                j += 1
            else:
                break
        blocks.append({
            "start": start, "insert_after": last, "classified": classified,
            "date": m.group(1), "time": m.group(2), "source": m.group(3).strip(), "raw": m.group(4).strip(),
        })
        i = j
    return blocks


def _parse_day(s):
    try:
        return datetime.strptime((s or "").strip(), "%Y-%m-%d").date()
    except (ValueError, TypeError):
        return None


def resurface_after_rule1(due, resurface, today):
    """규칙 1(미리 알림 ≤ 마감 − 1일) 코드 방어 — 프롬프트 지시만으로는 새던 위반값을 최종적으로 막는다.
    마감이 **미래**이고 미리 알림이 마감과 같거나 늦으면 → 미리 알림을 쓰지 않는다("none").
    마감이 오늘/과거거나 없으면 제약 없음(지난 것을 미루는 건 필요한 동작)."""
    d, r, t = _parse_day(due), _parse_day(resurface), _parse_day(today)
    if d and r and t and d > t and r >= d:
        return "none"
    return resurface


def field_lines(c):
    today = datetime.now().strftime("%Y-%m-%d")
    resurface = resurface_after_rule1(c.get("due"), c.get("resurface"), today)
    out = [
        f"  type: {c['type']}",
        f"  due: {(c.get('due') or 'none').strip() or 'none'}",
        f"  resurface: {(resurface or 'none').strip() or 'none'}",
        f"  status: {(c.get('status') or 'open').strip() or 'open'}",
    ]
    q = (c.get("question") or "").strip()
    if q:
        out.append(f"  ? {q}")
    return out


def classify_via_api(api_key, unclassified):
    """unclassified: [(index, raw), ...] → {index: classification}"""
    try:
        import anthropic
    except ImportError:
        sys.exit("anthropic SDK가 필요합니다.  설치:  pip install anthropic")

    client = anthropic.Anthropic(api_key=api_key) if api_key else anthropic.Anthropic()
    today = datetime.now().strftime("%Y-%m-%d")
    listing = "\n".join(f"[{idx}] {raw}" for idx, raw in unclassified)
    user = f"오늘 날짜: {today}\n\n미가공 줄:\n{listing}"

    # 무인(cron) 실행을 고려해, 흔한 API 오류는 traceback 대신 한 줄 메시지 + 종료(exit 1).
    # (구체적 예외를 먼저, 마지막에 상태오류 포괄. 예상 못 한 오류는 그대로 터뜨려 traceback 남긴다.)
    try:
        resp = client.messages.create(
            model=MODEL,
            max_tokens=16000,
            thinking={"type": "adaptive"},
            output_config={"effort": "high", "format": {"type": "json_schema", "schema": SCHEMA}},
            system=SYSTEM_PROMPT,
            messages=[{"role": "user", "content": user}],
        )
    except anthropic.AuthenticationError:
        sys.exit("API 키가 유효하지 않습니다(401). 환경변수 ANTHROPIC_API_KEY 또는 키 파일(~/.config/secondbrain/anthropic_key)을 확인하세요.")
    except anthropic.PermissionDeniedError:
        sys.exit("권한 없음/결제 문제일 수 있습니다(403). 콘솔에서 API 접근·크레딧을 확인하세요.")
    except anthropic.RateLimitError:
        sys.exit("레이트리밋(429). 잠시 후 다시 실행하세요.")
    except anthropic.APIConnectionError:
        sys.exit("네트워크 연결 실패. 인터넷 연결을 확인하고 다시 실행하세요.")
    except anthropic.APIStatusError as e:
        sys.exit(f"API 오류({getattr(e, 'status_code', '?')}): {getattr(e, 'message', str(e))}")
    if resp.stop_reason == "refusal":
        sys.exit("분류가 거부되었습니다(refusal). 내용을 확인하세요.")
    if resp.stop_reason == "max_tokens":
        sys.exit("출력이 max_tokens에 걸렸습니다. 줄 수를 나눠 다시 실행하세요.")

    text = next((b.text for b in resp.content if b.type == "text"), None)
    if not text:
        sys.exit("모델 응답에 텍스트가 없습니다.")
    data = json.loads(text)
    return {c["index"]: c for c in data["classifications"]}


def main():
    ap = argparse.ArgumentParser(description="받은함 자동 분류기")
    ap.add_argument("--inbox", help="inbox.md 경로(미지정 시 OS별 iCloud 경로 자동)")
    ap.add_argument("--dry-run", action="store_true", help="분류만 하고 저장 안 함")
    ap.add_argument("--plan", action="store_true", help="API 없이 분류 대상 줄만 표시")
    args = ap.parse_args()

    path = args.inbox or os.environ.get("SECONDBRAIN_INBOX") or default_inbox_path()
    if not os.path.exists(path):
        sys.exit(f"inbox.md를 찾을 수 없습니다: {path}\n  --inbox 로 경로를 지정하세요.")
    print(f"받은함: {path}")

    with open(path, encoding="utf-8") as f:
        text = f.read()
    lines = text.split("\n")

    blocks = parse_blocks(lines)
    unclassified = [(b["start"], b["raw"]) for b in blocks if not b["classified"]]
    print(f"전체 항목 {len(blocks)}개 · 이미 분류됨 {len(blocks) - len(unclassified)}개 · 분류 대상 {len(unclassified)}개")

    if not unclassified:
        print("분류할 새 줄이 없습니다.")
        return

    if args.plan:
        print("\n--- 분류 대상(미리보기, API 호출 안 함) ---")
        for idx, raw in unclassified:
            print(f"  line {idx + 1}: {raw}")
        return

    key = get_api_key()
    if not key and not os.environ.get("ANTHROPIC_API_KEY"):
        # anthropic SDK가 ant 프로필로도 인증될 수 있으니 키가 없어도 시도는 가능.
        print("경고: ANTHROPIC_API_KEY가 없습니다. `ant auth login` 프로필이 있으면 그대로 진행합니다.")

    results = classify_via_api(key, unclassified)

    # 미리보기 출력
    TYPE_KO = {"event": "예정", "promise": "약속", "info-action": "정보·행동", "info": "정보·참고", "idea": "생각", "principle": "원칙", "discard": "버림"}
    print("\n--- 분류 결과 ---")
    for idx, raw in unclassified:
        c = results.get(idx)
        if not c:
            print(f"  [!] line {idx + 1} 분류 누락: {raw}")
            continue
        due = c.get("due", "none")
        tail = f" · ~{due}까지?" if due and due != "none" else ""
        q = (c.get("question") or "").strip()
        qtail = f"  (?: {q})" if q else ""
        print(f"  {TYPE_KO.get(c['type'], c['type'])}{tail}{qtail}  ← {raw[:50]}")

    missing = [idx for idx, _ in unclassified if idx not in results]
    if missing:
        sys.exit(f"\n일부 줄이 분류되지 않아 저장을 중단합니다(줄 {[m+1 for m in missing]}).")

    if args.dry_run:
        print("\n[dry-run] 저장하지 않았습니다.")
        return

    # 새 파일 구성: 원문 줄은 그대로, 미분류 블록의 마지막 줄 뒤에 필드만 삽입
    inserts = {}  # insert_after 인덱스 -> [필드 줄...]
    for b in blocks:
        if b["classified"]:
            continue
        c = results.get(b["start"])
        if c:
            inserts[b["insert_after"]] = field_lines(c)

    new_lines = []
    for idx, line in enumerate(lines):
        new_lines.append(line)
        if idx in inserts:
            new_lines.extend(inserts[idx])
    new_text = "\n".join(new_lines)

    # 안전: 타임스탬프 백업 → 임시파일 → 원자적 교체
    folder = os.path.dirname(path)
    backup_dir = os.path.join(folder, "backups")
    os.makedirs(backup_dir, exist_ok=True)
    stamp = datetime.now().strftime("%Y%m%d-%H%M%S")
    backup = os.path.join(backup_dir, f"inbox.md.bak-{stamp}")
    shutil.copy2(path, backup)

    tmp = path + ".tmp"
    with open(tmp, "w", encoding="utf-8") as f:
        f.write(new_text)
    os.replace(tmp, path)

    print(f"\n저장 완료 · {len(inserts)}개 항목에 분류 필드 추가")
    print(f"백업: {backup}")


if __name__ == "__main__":
    main()
