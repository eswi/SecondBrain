#!/bin/bash
# macOS 자동 분류 스케줄 설치 (launchd LaunchAgent).
# 매시간 :00 에 classify.py를 실행한다. 미분류 줄이 없으면 API 호출 없이 끝난다.
#
# 사용:  automation/setup-mac.sh
# 제거:  automation/uninstall-mac.sh
#
# 설계서 §0-A: 분류(쓰기)는 데스크톱에서만, **두 기기 동시 자동 실행 금지**.
# → 이 스케줄은 "한 대"에만 설치할 것. 다른 기기로 옮기려면 여기서 제거 후 그 기기에 설치.
set -euo pipefail

LABEL="com.secondbrain.classify"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
WRAPPER="$SCRIPT_DIR/run-classify.sh"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
LOG="$HOME/Library/Logs/secondbrain-classify.log"
LAUNCHD_LOG="$HOME/Library/Logs/secondbrain-classify.launchd.log"
UID_NUM="$(id -u)"

# 1) anthropic을 import할 수 있는 python3 확인
PY="$(command -v python3 || true)"
[ -n "$PY" ] || { echo "python3를 찾을 수 없습니다. Python 설치 후 다시 실행하세요."; exit 1; }
if ! "$PY" -c 'import anthropic' 2>/dev/null; then
  echo "경고: $PY 에 anthropic 패키지가 없습니다. 'pip install anthropic' 후 다시 실행하세요."
  exit 1
fi
echo "python: $PY ($("$PY" -c 'import anthropic; print("anthropic", anthropic.__version__)'))"

# 2) API 키 확인 — launchd는 셸 환경변수를 못 받으므로 키 '파일'이 필요
KEYFILE="${XDG_CONFIG_HOME:-$HOME/.config}/secondbrain/anthropic_key"
if [ ! -f "$KEYFILE" ]; then
  echo ""
  echo "경고: 키 파일이 없습니다: $KEYFILE"
  echo "launchd는 셸 환경변수(ANTHROPIC_API_KEY)를 못 읽으므로 키를 파일로 둬야 합니다:"
  echo "  mkdir -p \"$(dirname "$KEYFILE")\""
  echo "  printf %s 'sk-ant-...' > \"$KEYFILE\" && chmod 600 \"$KEYFILE\""
  echo "키 파일을 만든 뒤 이 스크립트를 다시 실행하세요."
  exit 1
fi
echo "key file: $KEYFILE (권한 $(stat -f '%Lp' "$KEYFILE"))"

chmod +x "$WRAPPER"
mkdir -p "$HOME/Library/LaunchAgents"

# 3) 플리스트 생성 (경로/파이썬은 이 기기 기준으로 확정해 박아 넣는다)
cat > "$PLIST" <<PLISTEOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>$LABEL</string>
  <key>ProgramArguments</key>
  <array>
    <string>/bin/bash</string>
    <string>$WRAPPER</string>
  </array>
  <key>EnvironmentVariables</key>
  <dict>
    <key>SECONDBRAIN_PYTHON</key><string>$PY</string>
    <key>SECONDBRAIN_LOG</key><string>$LOG</string>
  </dict>
  <key>StartCalendarInterval</key>
  <dict>
    <key>Minute</key><integer>0</integer>
  </dict>
  <key>StandardOutPath</key><string>$LAUNCHD_LOG</string>
  <key>StandardErrorPath</key><string>$LAUNCHD_LOG</string>
  <key>RunAtLoad</key><false/>
</dict>
</plist>
PLISTEOF
echo "plist:  $PLIST"

# 4) (재)등록: 최신 launchctl(bootstrap) 우선, 안 되면 load 폴백
launchctl bootout "gui/$UID_NUM/$LABEL" 2>/dev/null || true
if launchctl bootstrap "gui/$UID_NUM" "$PLIST" 2>/dev/null; then
  echo "launchd: bootstrap 완료"
else
  launchctl unload "$PLIST" 2>/dev/null || true
  launchctl load -w "$PLIST"
  echo "launchd: load 완료 (fallback)"
fi

echo ""
echo "설치 완료 — 매시간 :00 에 자동 분류가 실행됩니다."
echo "  로그:        $LOG"
echo "  지금 1회 실행: launchctl kickstart -k gui/$UID_NUM/$LABEL"
echo "  상태 확인:    launchctl print gui/$UID_NUM/$LABEL | grep -E 'state|program'"
echo "  제거:        $SCRIPT_DIR/uninstall-mac.sh"
