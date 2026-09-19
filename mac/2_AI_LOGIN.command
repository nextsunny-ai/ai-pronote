#!/bin/bash
set -euo pipefail

echo "사용할 AI 로그인을 선택하세요."
echo "AI 연결 없이도 녹음, 영상, 기본 받아쓰기와 필기를 사용할 수 있습니다."
echo "AI 회의록과 에이전트 기능이 필요할 때 연결하세요."
echo
echo "1) Claude"
echo "2) ChatGPT / Codex"
echo "0) 종료"
echo "Gemini 연결은 준비 중입니다."
read -r -p "번호: " choice

case "$choice" in
  1)
    if ! command -v claude >/dev/null 2>&1; then
      echo "Claude Code가 설치되어 있지 않습니다."
      echo "Anthropic 공식 안내에서 설치한 뒤 이 파일을 다시 실행하세요."
      open "https://docs.anthropic.com/en/docs/claude-code/setup"
      exit 2
    fi
    echo "Claude 로그인 화면을 엽니다. 완료 후 종료하세요."
    claude
    ;;
  2)
    if ! command -v codex >/dev/null 2>&1; then
      echo "Codex CLI가 설치되어 있지 않습니다."
      echo "OpenAI 공식 안내에서 설치한 뒤 이 파일을 다시 실행하세요."
      open "https://developers.openai.com/codex/cli"
      exit 2
    fi
    echo "ChatGPT / Codex 로그인 화면을 엽니다. 완료 후 종료하세요."
    codex
    ;;
  0)
    exit 0
    ;;
  *)
    echo "선택한 번호를 확인해 주세요."
    exit 2
    ;;
esac

echo
echo "로그인 확인을 마쳤습니다. AI PRONOTE 설정에서 같은 AI를 선택하세요."
read -r -p "Enter를 누르면 닫힙니다."
