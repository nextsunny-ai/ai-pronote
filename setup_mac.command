#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
SETUP="$ROOT/mac/1_FIRST_SETUP.command"

if [[ ! -x "$SETUP" ]]; then
  echo "Mac 설치 파일을 찾을 수 없습니다: mac/1_FIRST_SETUP.command"
  echo "ZIP 압축을 완전히 푼 뒤 다시 실행하세요."
  read -r -p "Enter를 누르면 닫힙니다."
  exit 2
fi

exec "$SETUP"
