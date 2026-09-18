#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"; cd "$ROOT"
URL="http://127.0.0.1:8795"; EXPECTED_VERSION="v1.5.0-beta6.20260918"; LOCK="/tmp/ai_pronote_v15_${UID}.lock"
PYTHON="$ROOT/.venv/bin/python"
if [[ ! -x "$PYTHON" ]]; then
  echo "처음 설치가 필요합니다. mac/1_FIRST_SETUP.command를 먼저 실행하세요."
  open "$ROOT/mac/1_FIRST_SETUP.command"
  exit 2
fi
health_version() {
  "$PYTHON" -c "import json,urllib.request; print(json.load(urllib.request.urlopen('$URL/api/health',timeout=2)).get('version',''))" 2>/dev/null || true
}
current_version="$(health_version)"
if [[ "$current_version" == "$EXPECTED_VERSION" ]]; then open "$URL"; exit 0; fi
if [[ -n "$current_version" ]]; then echo "포트 8795에서 다른 버전($current_version)이 실행 중입니다. 종료하지 않았습니다."; exit 2; fi
if ! mkdir "$LOCK" 2>/dev/null; then
  for _ in {1..90}; do
    current_version="$(health_version)"
    if [[ "$current_version" == "$EXPECTED_VERSION" ]]; then open "$URL"; exit 0; fi
    if [[ -n "$current_version" ]]; then echo "포트 8795에서 다른 버전($current_version)이 실행 중입니다. 종료하지 않았습니다."; exit 2; fi
    sleep 0.5
  done
  owner="$(cat "$LOCK/pid" 2>/dev/null || true)"
  if [[ "$owner" =~ ^[0-9]+$ ]] && kill -0 "$owner" 2>/dev/null; then
    echo "다른 AI PRONOTE 시작 작업이 아직 실행 중입니다. 잠시 후 다시 실행하세요."
    exit 1
  fi
  rm -f "$LOCK/pid"
  rmdir "$LOCK" 2>/dev/null || { echo "오래된 시작 잠금을 정리하지 못했습니다: $LOCK"; exit 1; }
  mkdir "$LOCK" || exit 1
fi
echo "$$" >"$LOCK/pid"
trap 'rm -f "$LOCK/pid"; rmdir "$LOCK" 2>/dev/null || true' EXIT
mkdir -p data_v15/logs
export PRONOTE_HOST="127.0.0.1" PRONOTE_PORT="8795" PRONOTE_DATA_DIR="$ROOT/data_v15" PRONOTE_EXPERIMENTAL_CLI="true"
nohup "$PYTHON" main.py >>data_v15/logs/server.log 2>&1 &
echo $! >data_v15/server.pid
for _ in {1..90}; do
  current_version="$(health_version)"
  if [[ "$current_version" == "$EXPECTED_VERSION" ]]; then open "$URL"; exit 0; fi
  if [[ -n "$current_version" ]]; then echo "포트 8795에서 다른 버전($current_version)이 실행 중입니다. 종료하지 않았습니다."; exit 2; fi
  sleep 0.5
done
echo "서버가 시작되지 않았습니다."; open -a TextEdit data_v15/logs/server.log; exit 1
