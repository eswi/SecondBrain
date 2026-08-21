#!/bin/bash
# ⛔ 이 파일은 「지금은 쓰지 않는 것」이다.
#    자동 분류는 2026-08-18에 앱에서 진입점 둘을 막았고(`ClassifyPause`),
#    2026-08-21에 **zero base로 새로 설계**하기로 정해졌다(CLAUDE.md 항시 규칙 8).
#    이 스크립트는 그 결정 '이전'에 만들어졌고, **launchd 없이 직접 돌려도 그대로 돈다** —
#    classify.py를 1회 실행해 iCloud inbox.md에 분류 필드를 쓴다.
#    ⛔ **화면에 아무것도 안 나온다** — 결과는 로그에만 찍힌다.
#       「래퍼니까 안전하다」로 읽지 말 것. 분류가 실제로 일어난다.
#    고치거나 지우지 말 것 — 표시만 해 둔다. 되살릴지는 사용자가 정한다.
#    근거: CLAUDE.md 항시 규칙 8 · docs/native/memory-philosophy.md §2-1-B
#          (그 절의 「자동은 준비까지, 결정은 사용자가」).
#
# 스케줄 실행용 분류기 래퍼 (macOS launchd / 기타 cron).
# - classify.py를 이 스크립트 기준 상위(=repo 루트)에서 찾는다.
# - python은 $SECONDBRAIN_PYTHON(플리스트가 지정) 우선, 없으면 PATH의 python3.
# - 실행 때마다 타임스탬프 블록을 로그에 덧붙이고, 로그가 너무 길면 자른다.
# - classify.py는 미분류 줄이 없으면 API 호출 없이 즉시 끝난다(멱등) → 자주 돌려도 안전.
set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
PY="${SECONDBRAIN_PYTHON:-python3}"
LOG="${SECONDBRAIN_LOG:-$HOME/Library/Logs/secondbrain-classify.log}"

mkdir -p "$(dirname "$LOG")"

# 로그가 2000줄을 넘으면 마지막 500줄만 남긴다(무한 증식 방지).
if [ -f "$LOG" ] && [ "$(wc -l < "$LOG")" -gt 2000 ]; then
  tail -n 500 "$LOG" > "$LOG.tmp" && mv "$LOG.tmp" "$LOG"
fi

{
  echo "===== $(date '+%Y-%m-%d %H:%M:%S %z') ====="
  "$PY" "$REPO_DIR/classify.py"
  code=$?
  echo "[exit $code]"
  echo ""
} >> "$LOG" 2>&1
