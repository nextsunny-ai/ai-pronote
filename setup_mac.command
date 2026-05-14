#!/bin/bash
# ═══════════════════════════════════════════════════════════════════
# AI PRONOTE — Mac 자동 설치 (4단계)
# 더블클릭 = Homebrew + Python + Claude CLI + 의존성 자동 설치
# ═══════════════════════════════════════════════════════════════════

set -e
cd "$(dirname "$0")"

echo ""
echo "════════════════════════════════════════════"
echo "  AI PRONOTE — Mac 자동 설치 (3~10분)"
echo "════════════════════════════════════════════"
echo ""

# ─────────────────────────────────────────────────
# 1) Homebrew 확인·설치
# ─────────────────────────────────────────────────
echo "▶ 1/4 Homebrew 확인..."
if ! command -v brew &> /dev/null; then
  echo "  Homebrew 없음. 자동 설치 시작 (약 3-5분, 비밀번호 한 번 입력 필요)..."
  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
  # Apple Silicon = /opt/homebrew, Intel = /usr/local
  if [[ -f /opt/homebrew/bin/brew ]]; then
    eval "$(/opt/homebrew/bin/brew shellenv)"
  elif [[ -f /usr/local/bin/brew ]]; then
    eval "$(/usr/local/bin/brew shellenv)"
  fi
else
  echo "  ✅ Homebrew 박혀있음"
fi

# ─────────────────────────────────────────────────
# 2) Python 3.11+ 확인·설치
# ─────────────────────────────────────────────────
echo ""
echo "▶ 2/4 Python 3.11+ 확인..."
if ! command -v python3 &> /dev/null || [[ $(python3 -c 'import sys; print(sys.version_info >= (3, 11))') != "True" ]]; then
  echo "  Python 3.11+ 없음. 설치 시작..."
  brew install python@3.11
else
  echo "  ✅ Python $(python3 --version) 박혀있음"
fi

# ─────────────────────────────────────────────────
# 3) Claude Code CLI 확인·설치 (= 비용 0 path 의무)
# ─────────────────────────────────────────────────
echo ""
echo "▶ 3/4 Claude Code CLI 확인..."
if ! command -v claude &> /dev/null; then
  echo "  Claude CLI 없음. Node.js + Claude CLI 설치..."
  if ! command -v node &> /dev/null; then
    brew install node
  fi
  npm install -g @anthropic-ai/claude-code
  echo ""
  echo "  ★ Claude 로그인 = 본인 Pro/Max 구독으로 인증 (= 비용 0)"
  echo "  ★ 터미널이 열리면 = 로그인 진행 (= 본인 Claude 계정)"
  echo ""
  read -p "  Enter 누르면 'claude login' 실행..."
  claude login || true
else
  echo "  ✅ Claude CLI 박혀있음"
  # OAuth 토큰 검증
  if [[ ! -f "$HOME/.claude/.credentials.json" ]]; then
    echo "  ⚠ OAuth 토큰 없음. 'claude login' 실행..."
    claude login || true
  fi
fi

# ─────────────────────────────────────────────────
# 4) Python 의존성 + 첫 실행 준비
# ─────────────────────────────────────────────────
echo ""
echo "▶ 4/4 Python 의존성 설치..."
python3 -m pip install --upgrade pip --quiet
python3 -m pip install -r requirements.txt --quiet

# .env.local 템플릿 신설 (= Supabase URL·ANON_KEY 기본값 = 옛 프로젝트 재사용)
if [[ ! -f ".env.local" ]]; then
  cat > .env.local <<'EOF'
SUPABASE_URL=https://pddasonkizwviwqzdhpu.supabase.co
SUPABASE_ANON_KEY=sb_publishable_g_WkmPy-txtru1D93pl8iA_kddaB4GQ
BYPASS_AUTH=false
WHISPER_MODEL=medium
EOF
  echo "  ✅ .env.local 신설"
fi

# 바탕화면 바로가기 (= start_mac.command 호출)
DESKTOP="$HOME/Desktop"
SHORTCUT="$DESKTOP/AI PRONOTE.command"
SCRIPT_DIR="$(pwd)"
cat > "$SHORTCUT" <<EOF
#!/bin/bash
cd "$SCRIPT_DIR"
./start_mac.command
EOF
chmod +x "$SHORTCUT" "$SCRIPT_DIR/start_mac.command" 2>/dev/null || true

echo ""
echo "════════════════════════════════════════════"
echo "  ✅ AI PRONOTE 설치 완료"
echo "════════════════════════════════════════════"
echo ""
echo "  사용 = 바탕화면 'AI PRONOTE.command' 더블클릭"
echo "  또는 = 이 폴더의 'start_mac.command' 더블클릭"
echo ""
echo "  본 창은 5초 후 자동 닫힘..."
sleep 5
