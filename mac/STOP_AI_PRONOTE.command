#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"; PIDFILE="$ROOT/data_v15/server.pid"
if [[ -f "$PIDFILE" ]]; then PID="$(cat "$PIDFILE")"; if kill -0 "$PID" 2>/dev/null; then kill "$PID"; fi; rm -f "$PIDFILE"; fi
echo "서버를 종료했습니다. 저장된 회의와 녹음은 삭제하지 않았습니다."
