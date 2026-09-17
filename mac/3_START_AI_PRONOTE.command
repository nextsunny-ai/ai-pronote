#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"; cd "$ROOT"
URL="http://127.0.0.1:8795"; LOCK="/tmp/ai_pronote_v15_${UID}.lock"
if python3 -c "import urllib.request; urllib.request.urlopen('$URL/api/health', timeout=2)" >/dev/null 2>&1; then open "$URL"; exit 0; fi
if ! mkdir "$LOCK" 2>/dev/null; then sleep 2; open "$URL"; exit 0; fi
trap 'rmdir "$LOCK" 2>/dev/null || true' EXIT
mkdir -p data_v15/logs
export PRONOTE_HOST="127.0.0.1" PRONOTE_PORT="8795" PRONOTE_DATA_DIR="$ROOT/data_v15" PRONOTE_EXPERIMENTAL_CLI="true"
nohup python3 main.py >>data_v15/logs/server.log 2>&1 &
echo $! >data_v15/server.pid
for _ in {1..90}; do if python3 -c "import urllib.request; urllib.request.urlopen('$URL/api/health', timeout=1)" >/dev/null 2>&1; then open "$URL"; exit 0; fi; sleep 0.5; done
echo "서버가 시작되지 않았습니다."; open -a TextEdit data_v15/logs/server.log; exit 1
