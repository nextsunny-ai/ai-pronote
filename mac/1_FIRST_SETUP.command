#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
on_error() {
  code=$?
  echo
  echo "설치 중 오류가 발생했습니다. 위의 마지막 오류 내용을 확인하세요."
  echo "기존 회의와 녹음은 변경되지 않았습니다."
  read -r -p "Enter를 누르면 닫힙니다."
  exit "$code"
}
trap on_error ERR
echo "AI PRONOTE v1.5 비공개 베타 설치"
if ! command -v python3 >/dev/null 2>&1; then
  echo "Python 3이 필요합니다. 공식 다운로드 페이지를 엽니다."
  open "https://www.python.org/downloads/macos/"
  read -r -p "Enter를 누르면 닫힙니다."
  exit 2
fi
python3 -c 'import sys; assert (3,10) <= sys.version_info[:2] <= (3,12), "Python 3.10~3.12가 필요합니다"; print("Python", sys.version.split()[0], "확인")'
if [[ ! -x ".venv/bin/python" ]]; then
  echo "AI PRONOTE 전용 Python 환경을 만듭니다."
  python3 -m venv .venv
fi
".venv/bin/python" -c 'import sys; assert (3,10) <= sys.version_info[:2] <= (3,12), "기존 .venv의 Python이 지원 범위가 아닙니다"'
".venv/bin/python" -m pip install --disable-pip-version-check --upgrade pip
".venv/bin/python" -m pip install --disable-pip-version-check -r requirements.txt
".venv/bin/python" -c 'import fastapi, uvicorn, multipart, faster_whisper, requests; print("핵심 구성요소 확인 완료")'
mkdir -p data_v15
echo "설치 완료. 다음으로 mac/2_AI_LOGIN.command를 실행하세요."
read -r -p "Enter를 누르면 닫힙니다."
