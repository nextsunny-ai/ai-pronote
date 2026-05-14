#!/bin/bash
# AI PRONOTE — Mac 실행 스크립트 (더블클릭)
# FastAPI 서버 시작 + 브라우저 자동 열림

cd "$(dirname "$0")"

# 옛 인스턴스 정리 (= 포트 충돌 차단)
PORT=8765
lsof -ti:$PORT 2>/dev/null | xargs kill -9 2>/dev/null || true

# Whisper 모델 자동 다운 안내 (= 첫 실행 시 ~500MB)
if [[ ! -d "$HOME/.cache/huggingface/hub/models--Systran--faster-whisper-medium" ]]; then
  echo ""
  echo "★ 첫 실행 = Whisper medium 모델 자동 다운 (= ~514MB, 5-10분)"
  echo "  진행 중인 자료 = 백그라운드 = 다운 끝나면 = 자동 작동"
  echo ""
fi

# 서버 시작 (백그라운드) + 브라우저 자동 열림
echo "▶ AI PRONOTE 서버 시작 중..."
python3 main.py &
SERVER_PID=$!

# 서버 준비 대기 (최대 10초)
for i in {1..20}; do
  if curl -s "http://127.0.0.1:$PORT/api/auth/config" > /dev/null 2>&1; then
    break
  fi
  sleep 0.5
done

# 브라우저 자동 열림
open "http://127.0.0.1:$PORT"

echo ""
echo "════════════════════════════════════════════"
echo "  AI PRONOTE 가동 중 — http://127.0.0.1:$PORT"
echo "════════════════════════════════════════════"
echo ""
echo "  ⌘+C 또는 본 창 닫음 = 서버 종료"
echo ""

# Foreground 대기 (= 창 닫으면 서버도 종료)
wait $SERVER_PID
