#!/bin/bash
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
