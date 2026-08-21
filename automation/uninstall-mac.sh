#!/bin/bash
# ✅ 이 파일은 **안전하다 — 오히려 있어야 하는 것이다.**
#    같은 폴더의 setup-mac.sh가 설치한 launchd LaunchAgent를 **끄고 플리스트를 지운다.**
#    자동 분류를 멈춰 둔 지금 상태를 **지키는 쪽**이고, 다른 기기로 옮길 때도 이걸 먼저 돈다.
#    ⚠️ automation/ 폴더 전체를 위험으로 읽지 말 것 — **이 파일은 반대 방향이다.**
#    (돌려도 로그·API 키 파일은 남고, 손으로 python3 classify.py 하는 길은 그대로 열려 있다
#     — 그 길은 ⛔다. classify.py 머리 참조.)
#
# macOS 자동 분류 스케줄 제거 (launchd LaunchAgent 언로드 + 플리스트 삭제).
# 로그 파일과 API 키 파일은 남긴다. 다른 기기로 옮길 때 이 기기에서 먼저 실행하면
# 설계서 §0-A "두 기기 동시 자동 실행 금지"를 지킬 수 있다.
set -u

LABEL="com.secondbrain.classify"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
UID_NUM="$(id -u)"

launchctl bootout "gui/$UID_NUM/$LABEL" 2>/dev/null \
  || launchctl unload "$PLIST" 2>/dev/null \
  || true
rm -f "$PLIST"

echo "제거 완료: launchd 언로드 + $PLIST 삭제."
echo "(로그와 API 키 파일은 그대로 둡니다. 수동 실행 python3 classify.py 는 계속 가능.)"
