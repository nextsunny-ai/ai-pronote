#!/bin/bash
set -euo pipefail

if [[ $# -ne 2 ]]; then
  echo "사용법: $0 <Windows에서 만든 후보 ZIP> <Mac용 출력 ZIP>" >&2
  exit 2
fi

INPUT_ZIP="$(cd "$(dirname "$1")" && pwd)/$(basename "$1")"
OUTPUT_ZIP="$(cd "$(dirname "$2")" && pwd)/$(basename "$2")"

if [[ ! -f "$INPUT_ZIP" ]]; then
  echo "입력 ZIP을 찾을 수 없습니다: $INPUT_ZIP" >&2
  exit 2
fi
if [[ -e "$OUTPUT_ZIP" ]]; then
  echo "기존 후보를 덮어쓰지 않습니다: $OUTPUT_ZIP" >&2
  exit 2
fi

STAGE="$(mktemp -d "${TMPDIR:-/tmp}/ai-pronote-macos-package.XXXXXX")"
VERIFY="$(mktemp -d "${TMPDIR:-/tmp}/ai-pronote-macos-verify.XXXXXX")"
cleanup() {
  rm -rf "$STAGE" "$VERIFY"
}
trap cleanup EXIT

ditto -x -k "$INPUT_ZIP" "$STAGE"
PACKAGE_ROOT=""
ROOT_COUNT=0
for CANDIDATE_ROOT in "$STAGE"/*; do
  if [[ -d "$CANDIDATE_ROOT" ]]; then
    PACKAGE_ROOT="$CANDIDATE_ROOT"
    ROOT_COUNT=$((ROOT_COUNT + 1))
  fi
done
if [[ $ROOT_COUNT -ne 1 ]]; then
  echo "후보 ZIP에는 최상위 앱 폴더가 정확히 하나 있어야 합니다." >&2
  exit 2
fi

SCRIPTS=(
  "$PACKAGE_ROOT/setup_mac.command"
  "$PACKAGE_ROOT/start_mac.command"
  "$PACKAGE_ROOT/uninstall_mac.command"
  "$PACKAGE_ROOT/mac/1_FIRST_SETUP.command"
  "$PACKAGE_ROOT/mac/2_AI_LOGIN.command"
  "$PACKAGE_ROOT/mac/3_START_AI_PRONOTE.command"
  "$PACKAGE_ROOT/mac/STOP_AI_PRONOTE.command"
)
for SCRIPT in "${SCRIPTS[@]}"; do
  [[ -f "$SCRIPT" ]] || { echo "필수 Mac 실행 파일이 없습니다: $SCRIPT" >&2; exit 2; }
  if LC_ALL=C grep -q $'\r' "$SCRIPT"; then
    echo "Mac 실행 파일에 CRLF가 남아 있습니다: $SCRIPT" >&2
    exit 2
  fi
  chmod 755 "$SCRIPT"
  bash -n "$SCRIPT"
done

while IFS= read -r -d '' EXECUTABLE; do
  chmod 755 "$EXECUTABLE"
done < <(find "$PACKAGE_ROOT/mac" -path '*/Contents/MacOS/*' -type f -print0)

ditto -c -k --sequesterRsrc --keepParent "$PACKAGE_ROOT" "$OUTPUT_ZIP"
ditto -x -k "$OUTPUT_ZIP" "$VERIFY"
VERIFIED_ROOT="$VERIFY/$(basename "$PACKAGE_ROOT")"
for SCRIPT in "${SCRIPTS[@]}"; do
  RELATIVE="${SCRIPT#"$PACKAGE_ROOT/"}"
  VERIFIED="$VERIFIED_ROOT/$RELATIVE"
  MODE="$(stat -f '%Lp' "$VERIFIED")"
  [[ "$MODE" == "755" ]] || { echo "실행권한 검증 실패: $RELATIVE ($MODE)" >&2; exit 2; }
  bash -n "$VERIFIED"
done

shasum -a 256 "$OUTPUT_ZIP"
