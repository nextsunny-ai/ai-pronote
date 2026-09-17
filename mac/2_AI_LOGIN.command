#!/bin/bash
set -euo pipefail
echo "사용할 AI 로그인을 선택하세요."
echo "1) Claude   2) Gemini   3) ChatGPT/Codex   4) 세 가지 모두"
read -r -p "번호: " choice
ensure_node() { if ! command -v npm >/dev/null 2>&1; then echo "Node.js 공식 페이지를 엽니다."; open "https://nodejs.org/en/download"; exit 2; fi; }
login_claude() { if ! command -v claude >/dev/null 2>&1; then curl -fsSL https://claude.ai/install.sh | bash; export PATH="$HOME/.local/bin:$PATH"; fi; claude; }
login_gemini() { ensure_node; command -v gemini >/dev/null 2>&1 || npm install -g @google/gemini-cli; gemini; }
login_codex() { ensure_node; command -v codex >/dev/null 2>&1 || npm install -g @openai/codex; codex; }
case "$choice" in 1) login_claude;; 2) login_gemini;; 3) login_codex;; 4) login_claude; login_gemini; login_codex;; *) echo "선택 오류"; exit 2;; esac
echo "로그인 확인을 마쳤습니다. 앱 설정에서 같은 AI를 선택하세요."
read -r -p "Enter를 누르면 닫힙니다."
