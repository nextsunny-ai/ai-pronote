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
PYTHON=""
PYTHON_CANDIDATES=(
  python3.12 python3.11 python3.10
  /opt/homebrew/opt/python@3.12/bin/python3.12
  /usr/local/opt/python@3.12/bin/python3.12
  /Library/Frameworks/Python.framework/Versions/3.12/bin/python3.12
  python3
)
for CANDIDATE in "${PYTHON_CANDIDATES[@]}"; do
  if command -v "$CANDIDATE" >/dev/null 2>&1 && "$CANDIDATE" -c 'import platform,struct,sys; assert (3,10) <= sys.version_info[:2] <= (3,12); assert struct.calcsize("P")*8 == 64 and platform.machine().lower() in {"arm64","x86_64"}' >/dev/null 2>&1; then
    PYTHON="$(command -v "$CANDIDATE")"
    break
  fi
done
if [[ -z "$PYTHON" ]]; then
  echo "Python 3.10~3.12 64비트가 필요합니다. 공식 다운로드 페이지를 엽니다."
  open "https://www.python.org/downloads/macos/"
  read -r -p "Enter를 누르면 닫힙니다."
  exit 2
fi
"$PYTHON" -c 'import sys; print("Python", sys.version.split()[0], "확인")'
if [[ ! -x ".venv/bin/python" ]]; then
  echo "AI PRONOTE 전용 Python 환경을 만듭니다."
  "$PYTHON" -m venv .venv
fi
".venv/bin/python" -c 'import platform,struct,sys; machine=platform.machine().lower(); assert (3,10) <= sys.version_info[:2] <= (3,12), "기존 .venv의 Python이 지원 범위가 아닙니다"; assert struct.calcsize("P")*8 == 64 and machine in {"arm64","x86_64"}, f"기존 .venv가 지원 Mac 64비트 환경이 아닙니다: {machine}"'
".venv/bin/python" -m pip install --disable-pip-version-check 'pip==26.2.1'
".venv/bin/python" -m pip install --disable-pip-version-check -r requirements-lock.txt
".venv/bin/python" -c 'import fastapi, uvicorn, multipart, faster_whisper, requests; print("핵심 구성요소 확인 완료")'
mkdir -p data_v15
echo "설치 완료. 다음으로 mac/2_AI_LOGIN.command를 실행하세요."
read -r -p "Enter를 누르면 닫힙니다."
