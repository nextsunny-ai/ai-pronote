#!/bin/bash
# AI PRONOTE — Mac 제거 스크립트

cd "$(dirname "$0")"

echo ""
echo "AI PRONOTE 제거..."
echo ""

# 바탕화면 바로가기 제거
rm -f "$HOME/Desktop/AI PRONOTE.command" 2>/dev/null

# 옛 인스턴스 정리
lsof -ti:8765 2>/dev/null | xargs kill -9 2>/dev/null || true

# 세션 자료 정리
rm -rf "$HOME/.ai-pronote" 2>/dev/null

# Whisper 캐시·Python 의존성·Homebrew·Claude CLI = ★ 보존 (= 다른 도구도 사용 가능)

echo "✅ AI PRONOTE 바로가기·세션 자료 정리 완료"
echo ""
echo "본 폴더 = 직접 삭제 (Finder = 이 폴더 = 휴지통)"
echo ""
sleep 3
