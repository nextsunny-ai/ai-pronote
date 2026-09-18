"""
AI PRONOTE — V1.3
Whisper 받아쓰기 + 화자 분리 + Claude 회의록 자동 정리 + 자동 제목 + Supabase 인증

★ V1.3 변경 (2026-05-18):
  - Claude 호출 = OAuth 토큰 직접 API → claude CLI subprocess 로 정정
    (OAuth 토큰 직접 Messages API = Anthropic 2026-04-04 정책으로 401 차단됨)
  - 회의록 자동 제목 생성 기능 (/api/llm/title)
  - 화자 분리 (pyannote) 통합 — diarize.py
  - 한국어 받아쓰기 정확도 개선 (initial_prompt + beam_size 선택)
"""
import os
import re
import sys
import time
import uuid
import json
import shutil
import tempfile
import subprocess
import urllib.request
import urllib.error
import threading
from pathlib import Path
from typing import Literal, Optional

# pythonw.exe (콘솔 X) 환경 = sys.stdout/stderr = None → print() 즉사 방지
# 디버그 = 로그 파일로 redirect (server.log·server.err.log 살리기)
_LOG_DIR = Path(__file__).parent
if sys.stdout is None:
    sys.stdout = open(_LOG_DIR / "server.log", "w", encoding="utf-8", buffering=1)
if sys.stderr is None:
    sys.stderr = open(_LOG_DIR / "server.err.log", "w", encoding="utf-8", buffering=1)

from fastapi import FastAPI, File, UploadFile, HTTPException, Form, Request
from fastapi.responses import FileResponse, HTMLResponse, JSONResponse, Response, RedirectResponse
from fastapi.staticfiles import StaticFiles
from starlette.middleware.trustedhost import TrustedHostMiddleware
from starlette.background import BackgroundTask
from pydantic import BaseModel
from faster_whisper import WhisperModel, BatchedInferencePipeline
from pronote_p0 import (
    APP_VERSION as P0_APP_VERSION,
    MAX_UPLOAD_BYTES,
    JobQueueView,
    allowed_upload,
    purge_managed_data,
    safe_data_root,
)
from provider_api import ProviderRegistry
from secure_credentials import MemoryCredentialStore, WindowsCredentialStore

ROOT = Path(__file__).parent
STATIC_DIR = ROOT / "static"
DATA_ROOT = safe_data_root(Path(os.environ.get("PRONOTE_DATA_DIR", ROOT / "data_v15")))
UPLOAD_DIR = DATA_ROOT / "uploads"
RESULT_DIR = DATA_ROOT / "results"

# ── 로그 ───────────────────────────────────────────────────────────
# 이 앱은 pythonw(콘솔 없음)로 뜨기 때문에 print 는 화면에 남지 않는다.
# 사고가 나도 원인을 되짚을 기록이 없어서, 날짜별 로그 파일에 남긴다.
LOG_DIR = DATA_ROOT / "logs"
LOG_DIR.mkdir(exist_ok=True)
LOG_KEEP_DAYS = 30


def log(msg: str, level: str = "INFO") -> None:
    line = f"{time.strftime('%Y-%m-%d %H:%M:%S')} [{level}] {msg}"
    try:
        with (LOG_DIR / f"pronote_{time.strftime('%Y-%m-%d')}.log").open("a", encoding="utf-8") as f:
            print(line, file=f)
    except Exception:
        pass
    try:
        print(line)
    except Exception:
        pass


def _prune_logs() -> None:
    """오래된 로그 정리 — 디스크에 계속 쌓이지 않게."""
    try:
        cutoff = time.time() - LOG_KEEP_DAYS * 86400
        for f in LOG_DIR.glob("pronote_*.log"):
            if f.stat().st_mtime < cutoff:
                f.unlink()
    except Exception:
        pass


_prune_logs()

# .env.local 로드 (수동 — python-dotenv 의존성 X)
ENV_PATH = ROOT / ".env.local"
if ENV_PATH.exists():
    for line in ENV_PATH.read_text(encoding="utf-8").splitlines():
        line = line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        k, v = line.split("=", 1)
        os.environ.setdefault(k.strip(), v.strip())

SUPABASE_URL = os.environ.get("SUPABASE_URL", "")
SUPABASE_ANON_KEY = os.environ.get("SUPABASE_ANON_KEY", "")
BYPASS_AUTH = os.environ.get("BYPASS_AUTH", "false").lower() == "true"

# Whisper — 모델별 캐시 (small / medium 등 = 사용자 선택)
# 검증 결과 (1시간 14분 회의):
#   - small  = 8분 처리, 75~80% 정확도, 466 MB
#   - medium = 19분 처리, 80~85% 정확도, 514 MB (디폴트)
ALLOWED_MODELS = {"tiny", "base", "small", "medium", "large-v3-turbo"}
DEFAULT_MODEL = os.environ.get("WHISPER_MODEL", "medium")
DEVICE = "cpu"
COMPUTE_TYPE = "int8"

# ★ V1.3 — 한국어 받아쓰기 정확도 개선용 컨텍스트 힌트.
# faster-whisper initial_prompt = 어조·맞춤법·문장부호 인식을 도움.
KOREAN_INITIAL_PROMPT = "다음은 한국어 회의 녹음입니다. 존댓말과 구어체가 섞여 있습니다."

# 2026-07-14 대표님 실제 회의 녹음으로 검증한 후처리 (v1.3 반영분 → v1.4 병합).
# 유튜브 자막 환각("이 영상은…") 3건→0, 어절 반복 74건→0, 고유명사 교정 확인.
try:
    from postprocess import clean_segment as _pp_clean_segment, KOREAN_HOTWORDS
except Exception as _e:  # postprocess.py 가 없어도 앱은 떠야 한다
    _pp_clean_segment, KOREAN_HOTWORDS = None, None
    print(f"[AI PRONOTE] postprocess 미탑재 — 기본 후처리로 동작합니다: {_e}")


def _clean_text(raw: str) -> str:
    """세그먼트 후처리 = 검증된 후처리(어절 반복·유튜브 환각) + v1.4 문장 반복 압축.
    둘은 잡는 대상이 달라 하나로 대체하지 않고 이어서 적용한다."""
    st = (raw or "").strip()
    if not st:
        return ""
    if _pp_clean_segment is not None:
        st = _pp_clean_segment(st) or ""
        if not st:
            return ""
    else:
        if _is_prompt_leak(st):
            return ""
        st = _scrub_prompt_hallucination(st)
    return _collapse_repeats(st) or ""

# ★ initial_prompt 누출 제거: Whisper가 무음·잡음 구간에서 initial_prompt 문장을
# 그대로 받아쓰기 결과로 출력하는 현상(hallucination) 완화. 정확도 힌트는 유지하고
# 누출된 힌트 문장만 후처리로 걸러낸다.
def _is_prompt_leak(text: str) -> bool:
    norm = "".join(ch for ch in (text or "") if ch.isalnum())
    if len(norm) < 6:
        return False
    prompt_norm = "".join(ch for ch in KOREAN_INITIAL_PROMPT if ch.isalnum())
    return norm in prompt_norm or prompt_norm in norm


# ★ 변형 환청 제거: Whisper가 무음 구간에서 힌트를 변형해 출력
#   ("한국어 회의 녹음을 시작합니다" / "이 영상은 한국어 회의 녹음입니다" 등).
#   실제 회의에서 나올 일 없는 키 문구 포함 문장만 제거 = 본문 보존.
_HALLUCINATION_KEY = "한국어회의녹음"


def _scrub_prompt_hallucination(text: str) -> str:
    if _HALLUCINATION_KEY not in (text or "").replace(" ", ""):
        return text
    import re
    parts = re.split(r"(?<=[.!?])\s+", text)
    kept = [p for p in parts if _HALLUCINATION_KEY not in p.replace(" ", "")]
    return " ".join(kept).strip()


# ★ v1.4 — 반복 환각 제거: Whisper가 무음·저품질 구간에서 같은 구절을
#   "X, X, X, X…" 로 수~수십 회 반복 출력하는 현상(회의 받아쓰기 끝 "한국과 일본의
#   관광 정책이 다 달라서" 18회 반복 사고). 같은 구절(4자+)이 3회 이상 연속이면 1회로.
_REPEAT_RE = re.compile(r'(.{4,}?)(?:[\s,，.。!?]+\1){2,}')


def _collapse_repeats(text: str) -> str:
    if not text:
        return text
    out = text
    for _ in range(3):  # 중첩 반복 대비 최대 3회 적용
        new = _REPEAT_RE.sub(r'\1', out)
        if new == out:
            break
        out = new
    return out.strip()


_model_cache: dict = {}

# ═══════════════════════════════════════════════════════════════════
# Claude 호출 = claude CLI subprocess  (★ V1.3 정정 2026-05-18)
#   옛 v1.2 = OAuth 토큰을 Authorization: Bearer 로 Messages API 직접 호출.
#   → Anthropic 2026-04-04 정책으로 HTTP 401 차단됨 (테오_learnings 2026-05-13 사고).
#   정공법 = 사용자 PC에 설치된 claude CLI 를 subprocess 로 호출.
#   사용자가 `claude login` 1회 = Pro/Max 구독으로 호출 = 추가 비용 0 (BYOK).
# ═══════════════════════════════════════════════════════════════════
CREDENTIALS_PATH = Path.home() / ".claude" / ".credentials.json"

CLAUDE_MODELS = {
    "haiku": "claude-haiku-4-5-20251001",
    "sonnet": "claude-sonnet-4-6",
    "opus": "claude-opus-4-7",
}
DEFAULT_LLM_MODEL = "sonnet"


def _subprocess_extra() -> dict:
    """claude subprocess 공통 옵션 (★ V1.3 — Firefly Indexer claude_cli.rs 이식):
    - 부모 Claude Code 세션 env(CLAUDE_*/ANTHROPIC_*) 격리 = 컨텍스트 흡수 방지
    - Windows = CREATE_NO_WINDOW = 콘솔창 깜빡임 0 (글로벌 룰 15 silent 앱)
    """
    scrubbed = {k: v for k, v in os.environ.items()
                if not (k.startswith("CLAUDE") or k.startswith("ANTHROPIC"))}
    extra: dict = {"env": scrubbed}
    if sys.platform == "win32":
        extra["creationflags"] = subprocess.CREATE_NO_WINDOW
    return extra


def claude_bin() -> Optional[str]:
    """claude CLI 실행 파일 경로. 없으면 None.

    ★ V1.3 — PATH 탐색 + 알려진 설치 위치 직접 확인 (Firefly Indexer find_bin 이식).
    사용자가 방금 설치한 직후 = 서버 프로세스 PATH는 아직 옛 값 → shutil.which 못 찾음
    (= 재시작 전까지 '미설치' 오인). 네이티브 설치·npm 글로벌·노드 버전 매니저
    (nvm/volta/fnm) 위치까지 직접 확인해 해결.
    """
    found = shutil.which("claude")
    if found:
        return found
    names = ["claude.cmd", "claude.exe", "claude"] if sys.platform == "win32" else ["claude"]
    home = Path.home()
    dirs = [home / ".local" / "bin"]   # 네이티브 설치 (Anthropic 공식) — 최우선
    if sys.platform == "win32":
        for ev in ("APPDATA", "LOCALAPPDATA"):
            v = os.environ.get(ev)
            if v:
                dirs.append(Path(v) / "npm")
        dirs += [home / ".npm-global", home / "AppData" / "Roaming" / "npm",
                 Path("C:/Program Files/nodejs")]
    elif sys.platform == "darwin":
        dirs += [Path("/usr/local/bin"), Path("/opt/homebrew/bin"), Path("/opt/local/bin"),
                 home / ".npm-global" / "bin", home / ".volta" / "bin",
                 home / ".fnm" / "aliases" / "default" / "bin",
                 home / ".nvm" / "versions" / "node" / "current" / "bin"]
    else:
        dirs += [Path("/usr/local/bin"), Path("/usr/bin"), home / ".npm-global" / "bin"]
    for d in dirs:
        for n in names:
            p = d / n
            if p.is_file():
                return str(p)
    return None


def claude_available() -> bool:
    return claude_bin() is not None


# 로그인 판정 캐시 — 온보딩 모달이 5초마다 상태를 물으므로 매번 CLI를 부르지 않는다.
_auth_cache: dict = {"value": None, "at": 0.0}
AUTH_CACHE_TTL = 60.0


def invalidate_auth_cache() -> None:
    """실제 호출이 인증 실패로 끝났을 때 캐시를 버린다.
    → 다음 /api/llm/status 가 곧바로 진짜 상태를 보고 = 로그인 안내가 즉시 뜬다."""
    _auth_cache["value"] = None
    _auth_cache["at"] = 0.0


def _probe_logged_in() -> bool:
    """claude 로그인 여부 실측.

    옛 판정은 `.credentials.json 이 있으면 로그인된 것`으로 보았다. 그 파일에는
    MCP 플러그인 토큰도 함께 저장되므로 Claude 본인 인증이 만료돼 사라진 뒤에도
    파일은 남는다 → 앱이 "준비 완료"를 표시한 채 회의가 끝난 뒤에야 회의록
    생성이 실패했다. 그래서 `claude auth status` 의 loggedIn 을 1순위로 삼는다.
    """
    bin_path = claude_bin()
    if bin_path:
        try:
            base = ["cmd", "/c", bin_path] if sys.platform == "win32" else [bin_path]
            r = subprocess.run(
                base + ["auth", "status"], capture_output=True, text=True,
                encoding="utf-8", errors="replace", timeout=15, **_subprocess_extra(),
            )
            out = (r.stdout or "").strip()
            try:
                data = json.loads(out)
                if isinstance(data, dict) and "loggedIn" in data:
                    return bool(data["loggedIn"])
            except json.JSONDecodeError:
                pass
            low = out.lower()
            if "not logged in" in low:
                return False
            if "logged in" in low:
                return True
        except Exception:
            pass  # CLI 구버전 등 = 아래 대체 경로

    # 대체 ① 자격증명 파일 안에 Claude 본인 OAuth 항목이 살아 있는지 (만료시각까지 확인)
    try:
        data = json.loads(CREDENTIALS_PATH.read_text(encoding="utf-8"))
        oauth = data.get("claudeAiOauth") or {}
        if oauth.get("accessToken"):
            exp = oauth.get("expiresAt")
            if not exp or float(exp) / 1000.0 > time.time():
                return True
    except Exception:
        pass

    # 대체 ② macOS Keychain
    if sys.platform == "darwin":
        try:
            r = subprocess.run(
                ["security", "find-generic-password", "-s", "Claude Code-credentials", "-w"],
                capture_output=True, text=True, timeout=5,
            )
            return r.returncode == 0 and bool(r.stdout.strip())
        except Exception:
            return False
    return False


def _is_logged_in() -> bool:
    now = time.time()
    if _auth_cache["value"] is not None and (now - _auth_cache["at"]) < AUTH_CACHE_TTL:
        return bool(_auth_cache["value"])
    v = _probe_logged_in()
    _auth_cache["value"] = v
    _auth_cache["at"] = now
    return v


def claude_state() -> dict:
    """Claude 사용 준비 상태 = 온보딩 모달이 정확한 안내를 띄우기 위한 3단계.
       not_installed  → claude CLI 미설치
       not_logged_in  → 설치됨, 로그인 필요 (claude login)
       ready          → 호출 준비 완료
    """
    bin_path = claude_bin()
    if not bin_path:
        return {"state": "not_installed", "bin": None, "logged_in": False}
    logged_in = _is_logged_in()
    return {
        "state": "ready" if logged_in else "not_logged_in",
        "bin": bin_path,
        "logged_in": logged_in,
    }


# ── 멀티 AI 프로바이더 (클로드 외 = 제미나이·챗GPT, 전부 사용자 본인 로그인 = 비용 0) ──

def _find_cli(names) -> Optional[str]:
    for n in names:
        f = shutil.which(n)
        if f:
            return f
    home = Path.home()
    dirs = []
    if sys.platform == "win32":
        for ev in ("APPDATA", "LOCALAPPDATA"):
            v = os.environ.get(ev)
            if v:
                dirs.append(Path(v) / "npm")
        dirs += [home / "AppData" / "Roaming" / "npm", Path("C:/Program Files/nodejs")]
    else:
        dirs += [Path("/usr/local/bin"), Path("/opt/homebrew/bin"), home / ".npm-global" / "bin"]
    for d in dirs:
        for n in names:
            p = Path(d) / n
            if p.is_file():
                return str(p)
    return None


def gemini_bin() -> Optional[str]:
    return _find_cli(["gemini.cmd", "gemini.exe", "gemini"] if sys.platform == "win32" else ["gemini"])


def codex_bin() -> Optional[str]:
    return _find_cli(["codex.cmd", "codex.exe", "codex"] if sys.platform == "win32" else ["codex"])


def provider_status() -> dict:
    """AI 엔진별 상태.

    Gemini CLI OAuth를 제3자 앱에서 사용하는 경로는 Google 공식 정책상 허용되지
    않으므로 상태 탐지나 호출을 제공하지 않는다. Gemini는 공식 API BYOK만 쓴다.
    Codex의 로컬 로그인 파일은 실제 호출 자격까지 증명하지 못한다.
    """
    cs = claude_state()
    out = {"claude": cs["state"]}
    out["gemini"] = "policy_blocked"
    if codex_bin():
        out["codex"] = "login_unverified" if (Path.home() / ".codex" / "auth.json").exists() else "not_logged_in"
    else:
        out["codex"] = "not_installed"
    return out


def _run_cli_text(cmd: list, stdin_text: str, timeout: int, label: str) -> str:
    with tempfile.TemporaryDirectory(prefix=f"pronote_{label}_") as tmpdir:
        proc = subprocess.run(
            cmd, input=stdin_text, capture_output=True, text=True,
            encoding="utf-8", errors="replace", timeout=timeout, cwd=tmpdir,
            **_subprocess_extra(),
        )
    if proc.returncode != 0:
        raw = (proc.stderr or proc.stdout or "").strip() or f"종료 코드 {proc.returncode}"
        kind, msg = _classify_llm_error(raw, label)
        log(f"{label} 호출 실패 [{kind}] rc={proc.returncode}: {raw[:1000]}", "ERROR")
        raise LLMError(f"{label}: {msg}", kind, raw[:1500])
    return (proc.stdout or "").strip()


def call_gemini(system: str, prompt: str, content: str = "", timeout: int = 600) -> str:
    raise LLMError(
        "Gemini CLI 로그인은 공급자 정책상 앱 연결에 사용할 수 없습니다. 공식 Gemini API (BYOK)를 사용해 주세요.",
        "policy", "",
    )


def call_codex(system: str, prompt: str, content: str = "", timeout: int = 600) -> str:
    b = codex_bin()
    if not b:
        raise RuntimeError("ChatGPT(Codex) CLI 없음 — 설치: npm i -g @openai/codex → 'codex' 1회 실행해 로그인")
    full = (system + "\n\n" + prompt + (("\n\n" + content) if content else "")).strip()
    cmd = (["cmd", "/c", b] if sys.platform == "win32" else [b]) + ["exec", "--skip-git-repo-check", "-"]
    return _run_cli_text(cmd, full, timeout, "codex")


def call_llm(provider: str, system: str, prompt: str, content: str = "",
             model_alias: str = DEFAULT_LLM_MODEL, timeout: int = 600,
             allowed_tools: Optional[str] = None, retries: int = 2) -> str:
    """실험 CLI 라우팅 — Claude·Codex만 허용. Gemini는 공식 API BYOK 전용.

    회의가 끝난 뒤 한 번 실패하면 그 회의록은 그대로 날아간다. 그래서 사용량 한도·
    혼잡·네트워크처럼 잠시 뒤에는 되는 실패는 여기서 조용히 다시 시도한다.
    로그인 만료(auth)는 다시 걸어도 같은 결과이므로 즉시 실패시켜 안내로 넘긴다.
    """
    p = (provider or "").strip().lower()
    if p in {"gemini", "gemini_cli"}:
        raise LLMError(
            "Gemini CLI 로그인은 공급자 정책상 앱 연결에 사용할 수 없습니다. 설정에서 공식 Gemini API (BYOK)를 사용해 주세요.",
            "policy", "",
        )
    if p in {"openai", "openai_api", "gemini_api", "anthropic", "anthropic_api"}:
        raise LLMError("공식 API 제공자는 공식 BYOK 실행 경로에서만 사용할 수 있습니다.", "policy", "")
    if p not in {"claude_cli", "codex_cli"}:
        raise LLMError("알 수 없거나 지원하지 않는 AI 제공자입니다. 설정에서 다시 선택해 주세요.", "policy", "")
    if os.environ.get("PRONOTE_EXPERIMENTAL_CLI", "false").lower() != "true":
        raise LLMError("구독형 CLI 경로는 공개 기본 설정에서 비활성화되어 있습니다.", "policy", "")

    def _once() -> str:
        if p == "codex_cli":
            return call_codex(system, prompt, content, timeout=timeout)
        if p == "claude_cli":
            return call_claude(system, prompt, content, model_alias=model_alias,
                               timeout=timeout, allowed_tools=allowed_tools)
        raise LLMError("지원하지 않는 AI 제공자입니다.", "policy", "")

    delay = 4.0
    for attempt in range(retries + 1):
        try:
            return _once()
        except LLMError as e:
            if e.kind not in RETRYABLE_KINDS or attempt == retries:
                raise
            log(f"AI 호출 재시도 {attempt + 1}/{retries} — 원인 {e.kind}, {delay:.0f}초 후")
            time.sleep(delay)
            delay *= 2
    raise LLMError("AI 호출에 실패했습니다.", "unknown", "")


def _llm_http_error(e: Exception) -> HTTPException:
    """AI 실패 → HTTP 응답. 화면이 원인별로 다르게 안내할 수 있게 kind 를 함께 보낸다.
    (kind='auth' 면 화면이 곧바로 Claude 로그인 안내를 띄운다)"""
    if isinstance(e, LLMError):
        return HTTPException(
            status_code=503 if e.kind in RETRYABLE_KINDS else 502,
            detail={"message": str(e), "kind": e.kind, "raw": (e.detail or "")[:600]},
        )
    return HTTPException(500, detail={"message": f"AI 호출에 실패했습니다: {e}",
                                      "kind": "unknown", "raw": str(e)[:600]})


class LLMError(RuntimeError):
    """AI 호출 실패 — 화면에 그대로 보여줄 한국어 message, 원인 분류 kind, 원문 detail."""

    def __init__(self, message: str, kind: str = "unknown", detail: str = ""):
        super().__init__(message)
        self.kind = kind
        self.detail = detail


def _classify_llm_error(raw: str, provider: str = "AI") -> tuple:
    """실패 원문에서 원인을 가려낸다.
    재시도가 소용없는 것(auth)과 잠시 뒤 되는 것(rate·network·overloaded)을 나눈다.
    옛 코드는 원문을 300자에서 잘라버려 정작 원인("OAuth session expired")이
    화면에 닿지 못했다 = 무엇이 잘못됐는지 알 수 없었다.
    """
    low = (raw or "").lower()
    display_name = {"claude": "Claude", "gemini": "Gemini", "codex": "Codex"}.get(
        (provider or "").lower(), provider or "AI"
    )
    if ("ineligibletiererror" in low or "unsupported_client" in low
            or "client is no longer supported" in low):
        return ("account_unsupported",
                f"{display_name} 로그인은 발견했지만 이 계정·클라이언트 조합은 사용할 수 없습니다. "
                "공식 API 연결을 사용하거나 공급자 계정 정책을 확인해 주세요.")
    if ("failed to authenticate" in low or "oauth session expired" in low
            or "not logged in" in low or "invalid api key" in low
            or "authentication_error" in low or "401" in low):
        return ("auth", f"{display_name} 로그인이 만료됐습니다. 로그인 안내에서 다시 로그인해 주세요.")
    if "rate limit" in low or "429" in low or "usage limit" in low or "quota" in low:
        return ("rate", f"{display_name} 사용량 한도에 걸렸습니다. 잠시 후 다시 시도합니다.")
    if "overloaded" in low or "529" in low or "503" in low:
        return ("overloaded", f"{display_name} 서버가 혼잡합니다. 잠시 후 다시 시도합니다.")
    if any(k in low for k in ("econnreset", "etimedout", "enotfound", "socket hang up",
                              "fetch failed", "network", "getaddrinfo", "econnrefused")):
        return ("network", "네트워크 연결이 끊겼습니다. 연결을 확인해 주세요.")
    if "timeout" in low or "시간 초과" in raw:
        return ("timeout", "AI 응답이 제한 시간을 넘었습니다.")
    return ("unknown", "AI 호출에 실패했습니다.")


RETRYABLE_KINDS = ("rate", "overloaded", "network", "timeout", "unknown")


def call_claude(system: str, prompt: str, content: str = "",
                model_alias: str = DEFAULT_LLM_MODEL, timeout: int = 600,
                allowed_tools: Optional[str] = None) -> str:
    """Claude 호출 = claude CLI subprocess.

    - system  → --system-prompt (역할·출력 형식 지시, 전체 override)
    - prompt  → -p 인자 (= 명령 한 줄)
    - content → stdin (= 긴 받아쓰기 본문. 명령행 길이 제한 회피)
    - allowed_tools → --allowed-tools (예: "WebSearch") = AI 비서 자료조사용
    - 응답    → --output-format json 엔벨로프의 result 필드

    cwd = 임시 디렉터리 → 프로젝트 CLAUDE.md 미로드 = 깨끗한 호출.
    """
    bin_path = claude_bin()
    if not bin_path:
        raise RuntimeError("claude CLI 없음. 터미널에서 'claude login' 1회 실행 필요.")
    model_alias = model_alias if model_alias in CLAUDE_MODELS else DEFAULT_LLM_MODEL

    # ★ V1.3 — --system-prompt(전체 override) = 기본 Claude Code 시스템 프롬프트·
    # 페르소나 컨텍스트 배제 = 회의록 정리에 깨끗한 호출 (Firefly Indexer 패턴).
    args = ["-p", prompt, "--output-format", "json", "--model", model_alias]
    # ★ AI 비서 자료조사 = WebSearch/WebFetch 도구 허용 (회의 중 웹 검색)
    #   도구 사용 시 = --system-prompt(전체 override)면 도구 인식이 사라져 검색 불가 →
    #   --append-system-prompt 로 기본 시스템(도구 설명) 유지 + 비서 역할 추가.
    #   --allowed-tools 화이트리스트 = 그 외 도구(Bash·Edit 등) 호출 차단 = 안전.
    #   --permission-mode acceptEdits = 비대화형 도구 자동 승인.
    if allowed_tools:
        args += ["--append-system-prompt", system,
                 "--allowed-tools", allowed_tools,
                 "--permission-mode", "acceptEdits"]
    else:
        # 일반 호출 = 전체 override (페르소나·컨텍스트 배제 = 깨끗)
        args += ["--system-prompt", system]
    # Windows = npm 설치 claude.cmd → cmd /c 경유 (.cmd 직접 실행 회피)
    if sys.platform == "win32":
        cmd = ["cmd", "/c", bin_path] + args
    else:
        cmd = [bin_path] + args

    with tempfile.TemporaryDirectory(prefix="pronote_claude_") as tmpdir:
        try:
            proc = subprocess.run(
                cmd, input=content, capture_output=True, text=True,
                encoding="utf-8", errors="replace", timeout=timeout, cwd=tmpdir,
                **_subprocess_extra(),
            )
        except subprocess.TimeoutExpired:
            log(f"claude 호출 시간 초과 ({timeout}초)", "ERROR")
            raise LLMError(f"AI 응답이 제한 시간({timeout}초)을 넘었습니다.", "timeout", "TimeoutExpired")

    out = (proc.stdout or "").strip()

    def _fail(raw: str):
        """실패 처리 — 원문을 보존해 로그에 남기고, 화면에는 사람이 읽을 말로 준다."""
        kind, msg = _classify_llm_error(raw, "claude")
        if kind == "auth":
            invalidate_auth_cache()   # 다음 상태 조회가 곧바로 '로그인 필요'를 보고하게
        log(f"claude 호출 실패 [{kind}] rc={proc.returncode}: {raw[:1000]}", "ERROR")
        raise LLMError(msg, kind, raw[:1500])

    if proc.returncode != 0 or not out:
        # --output-format json 은 실패해도 JSON 을 stdout 으로 준다 → result 안에 진짜 원인이 있다
        raw = ""
        try:
            raw = str(json.loads(out).get("result") or "")
        except Exception:
            pass
        if not raw:
            parts = [x for x in ((proc.stderr or "").strip(), out) if x]
            raw = "; ".join(parts) or f"claude CLI 종료 코드 {proc.returncode} (출력 없음)"
        _fail(raw)

    try:
        env = json.loads(out)
    except json.JSONDecodeError:
        # --output-format json 파싱 실패 = 원문 그대로 반환 (fallback)
        return out
    if env.get("is_error") or env.get("subtype") not in (None, "success"):
        _fail(str(env.get("result") or out))
    return env.get("result", "")


# 시나리오별 system prompt (사용자가 어드민·시나리오 모달에서 선택)
SCENARIO_PROMPTS = {
    "meeting": """당신은 회의록 정리 전문가입니다. 받아쓰기 텍스트를 한국어로 다음 형식으로 정리하세요. 마크다운 사용. 받아쓰기에 없는 내용 추측 X.

# 회의록

## 회의 정보
- 날짜·시간·참석자 (메타에 있으면)

## 한눈에 보는 요약
회의의 핵심 = 3~5줄

## 회의 노트 (주제별)
1. **주제명**
   - 상세 내용 (문장)
   - 핵심 발언 인용 (있으면)
2. ...

## 결정 사항
- 명확히 결정된 것만

## 다음 준비 사항
- 후속 작업·담당자

## AI 제안
- 결정 안 난 것 / 추후 검토 권유 사항""",

    "lecture": """당신은 강의 노트 정리 전문가입니다. 받아쓰기 텍스트를 한국어로 다음 형식으로:

# 강의 노트

## 강의 개요
한눈에 보는 핵심

## 단원 구조
1. **단원 1 제목**
   - 핵심 요점 (3~5개)
   - 예시·인용
2. ...

## Q&A
질문·답변 (있으면)

## 핵심 인용
강사가 특히 강조한 발언

## 추가 학습 권유""",

    "interview": """당신은 인터뷰·대화 정리 전문가입니다.

# 대화·인터뷰 정리

## 개요
참여자·주제

## 주제별 정리
**주제 1**
- Q: ...
- A: ...

## 결론·합의
- ...

## 인사이트 (AI)
대화에서 얻은 중요한 인사이트""",

    "ideation": """당신은 아이디어 정리 전문가입니다.

# 아이데이션

## 아이디어 리스트
1. ...
2. ...

## 카테고리 분류
- A 그룹: ...
- B 그룹: ...

## 발전 방향
유망한 아이디어·이유

## 다음 단계
- 검증·실행 액션""",

    "memo": """당신은 사용 메모·매뉴얼 정리 전문가입니다.

# 사용 메모

## 개요

## 단계별 정리
1. ...
2. ...

## 주의사항

## 체크리스트
- [ ] ...
- [ ] ...""",

    "free": """당신은 텍스트 정리 전문가입니다. 받아쓰기 텍스트를 자연스러운 한국어 문서로 정리하세요. 내용·문맥에 맞는 구조로 자유롭게. 마크다운 사용. 추측 X."""
}

# ★ V1.3 — 회의록 자동 제목 생성용 system prompt
TITLE_SYSTEM = """당신은 회의록 제목 전문가입니다. 받아쓰기 텍스트를 보고 회의의 핵심 주제를 담은 짧은 제목 하나를 만드세요.

[필수 규칙]
- 한국어, 공백 포함 24자 이내 (★ 반드시 엄수. 길면 안 됨).
- 핵심 주제 하나만. 쉼표·괄호·부제로 늘이지 말 것.
- 따옴표·마침표·줄바꿈·이모지·마크다운 기호(*, #) 없이 제목 텍스트만 출력.
- 받아쓰기에 나온 내용만 사용 = 추측 금지.

[좋은 예] 스폰서십 등급·티켓 판매 전략 회의
[좋은 예] 11월 성수동 팝업스토어 기획
[나쁜 예] 11월 팝업스토어 성수동 개설 결정, 신규 굿즈 라인업 출시 확정 (← 너무 길고 주제가 둘)"""


class SummarizeRequest(BaseModel):
    transcript: str
    scenario: str = "meeting"  # meeting | lecture | interview | ideation | memo | free
    model: str = DEFAULT_LLM_MODEL  # haiku | sonnet | opus
    provider: str = "claude_cli"
    title: Optional[str] = None
    attendees: Optional[str] = None
    tag: Optional[str] = None
    date: Optional[str] = None
    auto_title: bool = True  # ★ V1.3 — title 없으면 자동 생성
    external_consent: bool = False


class TitleRequest(BaseModel):
    transcript: str
    model: str = "haiku"  # 제목은 가벼운 작업 = haiku 디폴트
    provider: Literal["claude_cli", "codex_cli"] = "claude_cli"
    external_consent: bool = False


class SetupRequest(BaseModel):
    step: str  # "install" | "login"


class PurgeDataRequest(BaseModel):
    confirmation: str


IPAD_MODE = os.environ.get("PRONOTE_IPAD_MODE", "false").lower() == "true"
LAN_TOKEN = os.environ.get("PRONOTE_LAN_TOKEN", "")
LAN_SESSION_SECONDS = max(300, min(int(os.environ.get("PRONOTE_LAN_SESSION_SECONDS", "14400")), 86400))
_lan_sessions: dict[str, float] = {}
_lan_token_consumed = False
_lan_token_lock = threading.Lock()
_IPAD_BLOCKED_PATHS = {
    "/api/setup/run",
    "/api/llm/status",
    "/api/auth/config",
    "/api/auth/mark-logged-in",
    "/api/auth/clear-session",
    "/api/data/purge",
}

app = FastAPI(title="AI PRONOTE V1.5")
_trusted_hosts = ["127.0.0.1", "localhost", "testserver"]
if IPAD_MODE:
    _trusted_hosts.extend(h.strip() for h in os.environ.get("PRONOTE_LAN_HOSTS", "").split(",") if h.strip())
app.add_middleware(TrustedHostMiddleware, allowed_hosts=_trusted_hosts)
app.mount("/static", StaticFiles(directory=STATIC_DIR), name="static")


@app.middleware("http")
async def ipad_session_guard(request: Request, call_next):
    """LAN 공개는 명시적 iPad 모드 + 일회 연결 토큰으로 만든 만료 세션만 허용한다."""
    if not IPAD_MODE or request.url.path == "/companion/connect":
        return await call_next(request)
    if request.url.path in _IPAD_BLOCKED_PATHS:
        return JSONResponse({"detail": "host administration is unavailable in iPad mode"}, status_code=403)
    now = time.time()
    session_id = request.cookies.get("pronote_lan_session", "")
    expires = _lan_sessions.get(session_id, 0)
    if not session_id or expires <= now:
        if session_id:
            _lan_sessions.pop(session_id, None)
        return JSONResponse({"detail": "iPad companion session required or expired"}, status_code=401)
    if request.method not in {"GET", "HEAD", "OPTIONS"}:
        expected_origin = f"{request.url.scheme}://{request.headers.get('host', '')}"
        if request.headers.get("origin", "") != expected_origin:
            return JSONResponse({"detail": "same-origin request required"}, status_code=403)
    response = await call_next(request)
    response.headers["Cache-Control"] = "no-store" if request.url.path.startswith("/api/") else response.headers.get("Cache-Control", "")
    return response


@app.get("/companion/connect", response_class=HTMLResponse)
def companion_connect_form():
    if not IPAD_MODE:
        raise HTTPException(status_code=404, detail="iPad mode is disabled")
    return HTMLResponse(
        "<!doctype html><html lang='ko'><meta name='viewport' content='width=device-width,initial-scale=1'>"
        "<title>AI PRONOTE 연결</title><main><h1>AI PRONOTE 연결</h1>"
        "<p>PC 창에 표시된 일회용 연결 코드를 입력하세요.</p>"
        "<form method='post' autocomplete='off'><label>연결 코드 "
        "<input name='token' type='password' required minlength='32' autocomplete='one-time-code'></label>"
        "<button type='submit'>이 iPad 연결</button></form></main></html>",
        headers={"Cache-Control": "no-store", "Referrer-Policy": "no-referrer"},
    )


@app.post("/companion/connect")
def companion_connect(token: str = Form("")):
    global _lan_token_consumed
    if not IPAD_MODE:
        raise HTTPException(status_code=404, detail="iPad mode is disabled")
    with _lan_token_lock:
        if _lan_token_consumed or not LAN_TOKEN or not __import__("hmac").compare_digest(token, LAN_TOKEN):
            raise HTTPException(status_code=401, detail="invalid companion token")
        _lan_token_consumed = True
    session_id = __import__("secrets").token_urlsafe(32)
    _lan_sessions[session_id] = time.time() + LAN_SESSION_SECONDS
    response = RedirectResponse(url="/", status_code=303)
    response.set_cookie(
        "pronote_lan_session", session_id, max_age=LAN_SESSION_SECONDS,
        secure=True, httponly=True, samesite="strict", path="/",
    )
    response.headers["Referrer-Policy"] = "no-referrer"
    response.headers["Cache-Control"] = "no-store"
    return response


@app.post("/companion/logout")
def companion_logout(request: Request):
    session_id = request.cookies.get("pronote_lan_session", "")
    if session_id:
        _lan_sessions.pop(session_id, None)
    response = JSONResponse({"ok": True})
    response.delete_cookie("pronote_lan_session", path="/", secure=True, httponly=True, samesite="strict")
    return response


def get_model(size: str):
    """모델 캐시 — 같은 size 재사용 (메모리 절약)"""
    if size not in ALLOWED_MODELS:
        size = DEFAULT_MODEL
    if size not in _model_cache:
        print(f"[AI PRONOTE] 모델 로드: {size} · CPU · int8 · cpu_threads=8")
        wm = WhisperModel(size, device=DEVICE, compute_type=COMPUTE_TYPE, cpu_threads=8, num_workers=1)
        _model_cache[size] = BatchedInferencePipeline(model=wm)
        print(f"[AI PRONOTE] {size} 준비 완료")
    return _model_cache[size]


def generate_title(transcript: str, model_alias: str = "haiku",
                   provider: str = "claude_cli") -> str:
    """받아쓰기 → 회의록 제목 한 줄 (★ V1.3)."""
    excerpt = (transcript or "").strip()[:4000]
    if not excerpt:
        return ""
    raw = call_llm(
        provider, TITLE_SYSTEM,
        "위 입력 받아쓰기 텍스트를 보고 회의록 제목을 한 줄로 지어라.",
        excerpt, model_alias=model_alias, timeout=120,
    )
    raw = (raw or "").strip()
    # 첫 줄만 + 따옴표·마크다운(**, #) 기호 제거
    line = raw.splitlines()[0].strip() if raw else ""
    title = line.strip("\"'`*#  ").strip()
    # 모델이 규칙을 어기고 길게 만든 경우 = 첫 쉼표 앞까지로 자름 (자연스러운 컷)
    if len(title) > 28:
        for sep in (", ", ",", " - ", " — ", "("):
            if sep in title and len(title.split(sep)[0]) >= 6:
                title = title.split(sep)[0].strip()
                break
    return title[:32].strip()


@app.get("/")
def index():
    return FileResponse(STATIC_DIR / "index.html")


APP_VERSION = P0_APP_VERSION
BUILD_DATE = "2026-09-18"
BUILD_NOTE = "회의록 빈 상태 정리, 카메라 영상·음성 동시 녹화, 세션별 임시저장·복구를 포함한 외부 베타 4"


@app.get("/api/health")
def health():
    return {
        "status": "ok",
        "default_model": DEFAULT_MODEL,
        "device": DEVICE,
        "loaded_models": list(_model_cache.keys()),
        "allowed_models": list(ALLOWED_MODELS),
        "version": APP_VERSION,
        "build_date": BUILD_DATE,
    }


@app.get("/api/version")
def version_info():
    """버전 자료 (= 어드민·UI에서 fetch)"""
    return {
        "version": APP_VERSION,
        "build_date": BUILD_DATE,
        "build_note": BUILD_NOTE,
        "drive_master": "Drive/SUNNY_TEAM/AI_PRONOTE/source_v1.3/",
        "github": "https://github.com/nextsunny-ai/ai-pronote",
        "release": "https://github.com/nextsunny-ai/ai-pronote/releases/tag/v1.5.0-beta5-20260918",
    }


@app.get("/api/v15/providers")
def official_provider_status():
    """Read-only BYOK readiness. This endpoint never accepts or returns API keys."""
    try:
        store = WindowsCredentialStore()
    except RuntimeError:
        store = MemoryCredentialStore()
    allow_cli = os.environ.get("PRONOTE_EXPERIMENTAL_CLI", "false").lower() == "true"
    return {
        "providers": ProviderRegistry(store, allow_experimental_cli=allow_cli).statuses(),
        "credential_store": "windows_credential_manager" if isinstance(store, WindowsCredentialStore) else "memory_test_only",
        "experimental_cli": allow_cli,
        "ipad_gate": "iPad는 API 키를 직접 저장하지 않고 승인된 백엔드 프록시가 필요합니다.",
    }


@app.get("/api/auth/config")
def auth_config():
    """클라이언트 사이드 Supabase 인증용 설정 응답 (anon key = 브라우저 노출 OK)"""
    # OAuth provider 활성화 = AI PRONOTE Supabase Dashboard에서 = Google/Kakao/Apple 등록 후 = true로 변경
    OAUTH_ENABLED = os.environ.get("OAUTH_ENABLED", "false").lower() == "true"
    return {
        "supabaseUrl": SUPABASE_URL,
        "supabaseAnonKey": SUPABASE_ANON_KEY,
        "bypassAuth": BYPASS_AUTH,
        "oauthEnabled": OAUTH_ENABLED,
    }


# 세션 flag = start.vbs가 다음 더블클릭 시 = Chrome --app vs 일반 탭 분기 위해 사용
SESSION_FLAG_PATH = Path.home() / ".ai-pronote" / "session.flag"


@app.post("/api/auth/mark-logged-in")
def mark_logged_in():
    """로그인 성공 시 = flag 파일 생성. 다음 더블클릭 = Chrome --app 자체 창 진입."""
    SESSION_FLAG_PATH.parent.mkdir(exist_ok=True)
    SESSION_FLAG_PATH.write_text("1", encoding="utf-8")
    return {"ok": True, "flag": str(SESSION_FLAG_PATH)}


@app.post("/api/auth/clear-session")
def clear_session():
    """로그아웃 시 = flag 파일 삭제. 다음 더블클릭 = 일반 Chrome 탭 (가입·로그인 페이지)."""
    if SESSION_FLAG_PATH.exists():
        SESSION_FLAG_PATH.unlink()
    return {"ok": True}


@app.get("/api/llm/status")
def llm_status():
    """Claude 호출 가능 상태 (★ V1.3 — claude CLI 기준).
    온보딩 모달이 5초 폴링으로 이 엔드포인트를 확인 = state 보고 안내."""
    cs = claude_state()
    state = cs["state"]
    # 상태별 사용자 안내 문구 (모달이 그대로 표시)
    messages = {
        "not_installed": "AI 회의록 정리를 쓰려면 Claude를 한 번 설치해야 합니다.",
        "not_logged_in": "Claude 설치 완료. 이제 로그인 한 번만 하면 됩니다.",
        "ready": "Claude 준비 완료. AI 회의록 정리를 바로 쓸 수 있습니다.",
    }
    return {
        "state": state,                       # not_installed | not_logged_in | ready
        "authenticated": state == "ready",    # (구버전 호환)
        "method": "claude-cli-subprocess",
        "claude_bin": cs["bin"],
        "platform": sys.platform,
        "message": messages.get(state, ""),
        "credentials_path": str(CREDENTIALS_PATH),
        "credentials_exists": CREDENTIALS_PATH.exists(),
        "models": list(CLAUDE_MODELS.keys()),
        "default_model": DEFAULT_LLM_MODEL,
        "scenarios": list(SCENARIO_PROMPTS.keys()),
        "providers": provider_status(),  # claude·gemini·codex 각각 not_installed | not_logged_in | ready
    }


@app.post("/api/setup/run")
def setup_run(req: SetupRequest):
    """온보딩 — 터미널 창을 열어 claude 설치 또는 로그인을 실행.
    창은 사용자에게 보이게 띄움(진행 확인). 완료 = /api/llm/status 폴링으로 자동 감지.
    설치 명령 = Claude 공식 문서 (code.claude.com/docs/en/setup) 기준."""
    step = (req.step or "").strip()
    if step not in ("install", "login"):
        raise HTTPException(400, "step = install | login")
    plat = sys.platform
    try:
        if step == "install":
            if plat == "win32":
                # PowerShell 창 = 네이티브 설치 (공식: irm https://claude.ai/install.ps1 | iex)
                subprocess.Popen(
                    ["cmd", "/c", "start", "", "powershell", "-NoExit", "-Command",
                     "irm https://claude.ai/install.ps1 | iex"]
                )
            elif plat == "darwin":
                subprocess.Popen([
                    "osascript",
                    "-e", 'tell application "Terminal" to activate',
                    "-e", 'tell application "Terminal" to do script '
                          '"curl -fsSL https://claude.ai/install.sh | bash"',
                ])
            else:  # linux
                subprocess.Popen([
                    "x-terminal-emulator", "-e", "bash", "-lc",
                    "curl -fsSL https://claude.ai/install.sh | bash; "
                    "echo; echo '설치 완료 — 이 창을 닫아도 됩니다'; exec bash",
                ])
        else:  # login = claude 실행 → 브라우저 OAuth
            bin_path = claude_bin() or "claude"
            if plat == "win32":
                subprocess.Popen(["cmd", "/c", "start", "", "cmd", "/k", bin_path])
            elif plat == "darwin":
                subprocess.Popen([
                    "osascript",
                    "-e", 'tell application "Terminal" to activate',
                    "-e", f'tell application "Terminal" to do script "{bin_path}"',
                ])
            else:
                subprocess.Popen([
                    "x-terminal-emulator", "-e", "bash", "-lc", f"'{bin_path}'; exec bash",
                ])
    except FileNotFoundError as e:
        raise HTTPException(500, f"터미널 실행 도구를 찾을 수 없음: {e}")
    except Exception as e:
        raise HTTPException(500, f"터미널 실행 실패: {e}")
    return {
        "ok": True, "step": step, "platform": plat,
        "note": "열린 터미널 창에서 진행하세요. 완료되면 자동으로 인식됩니다.",
    }


@app.post("/api/llm/title")
def llm_title(req: TitleRequest):
    """받아쓰기 → 회의록 제목 자동 생성 (★ V1.3)"""
    if not req.transcript or not req.transcript.strip():
        raise HTTPException(400, "transcript 비어있음")
    if not req.external_consent:
        raise HTTPException(403, "외부 AI 전송 동의가 필요합니다")
    t0 = time.time()
    try:
        title = generate_title(req.transcript, model_alias=req.model, provider=req.provider)
    except Exception as e:
        log(f"제목 생성 실패: {e}", "ERROR")
        raise _llm_http_error(e)
    if not title:
        raise HTTPException(500, "제목 생성 결과 비어있음")
    provider_id = req.provider
    model_name = req.model if provider_id == "claude_cli" else "configured-default"
    model_id = (CLAUDE_MODELS.get(req.model) if provider_id == "claude_cli"
                else "codex-cli-configured-default")
    return {
        "title": title,
        "provider": provider_id,
        "model": model_name,
        "model_id": model_id,
        "elapsed_sec": round(time.time() - t0, 1),
    }


def build_summary(transcript: str, scenario: str = "meeting",
                  model_alias: str = DEFAULT_LLM_MODEL, provider: str = "claude_cli",
                  title: str = "", attendees: str = "", tag: str = "",
                  date: str = "", auto_title: bool = True) -> dict:
    """받아쓰기 → 회의록. 화면 요청과 서버 자동 생성이 함께 쓰는 본체."""
    if not transcript or not transcript.strip():
        raise ValueError("받아쓰기 본문이 비어 있습니다")
    if scenario not in SCENARIO_PROMPTS:
        scenario = "meeting"
    system = SCENARIO_PROMPTS[scenario]

    title = (title or "").strip()
    title_auto = False
    if not title and auto_title:
        try:
            title = generate_title(transcript, model_alias="haiku", provider=provider)
            title_auto = bool(title)
        except Exception as e:
            log(f"자동 제목 생략(오류): {e}", "WARN")

    meta_lines = []
    if title: meta_lines.append(f"제목: {title}")
    if attendees: meta_lines.append(f"참석자: {attendees}")
    if tag: meta_lines.append(f"종류: {tag}")
    if date: meta_lines.append(f"날짜: {date}")
    meta_block = "\n".join(meta_lines) if meta_lines else "(메타 없음)"

    content = f"""[메타 정보]
{meta_block}

[받아쓰기 본문]
{transcript}"""

    t0 = time.time()
    text = call_llm(
        provider, system,
        "위 입력은 받아쓰기로 변환된 회의·강의·대화 텍스트다. "
        "system prompt 형식대로 한국어로 정리하라.",
        content, model_alias=model_alias,
    )
    provider_id = (provider or "").strip().lower()
    model_name = model_alias if provider_id == "claude_cli" else "configured-default"
    model_id = (CLAUDE_MODELS.get(model_alias) if provider_id == "claude_cli"
                else "codex-cli-configured-default" if provider_id == "codex_cli" else None)
    return {
        "scenario": scenario,
        "provider": provider_id,
        "model": model_name,
        "model_id": model_id,
        "elapsed_sec": round(time.time() - t0, 1),
        "title": title,
        "title_auto": title_auto,
        "summary": text,
        "char_count": len(text),
    }


@app.post("/api/llm/summarize")
def llm_summarize(req: SummarizeRequest):
    """transcript → 시나리오별 회의록 자동 정리. title 없으면 자동 생성."""
    if not req.transcript or not req.transcript.strip():
        raise HTTPException(400, "transcript 비어있음")
    if req.scenario not in SCENARIO_PROMPTS:
        raise HTTPException(400, f"scenario X = {list(SCENARIO_PROMPTS.keys())}")
    if not req.external_consent:
        raise HTTPException(403, "외부 AI 전송 동의가 필요합니다")
    try:
        return build_summary(
            req.transcript, req.scenario, req.model, req.provider,
            req.title or "", req.attendees or "", req.tag or "",
            req.date or "", req.auto_title,
        )
    except Exception as e:
        log(f"회의록 생성 실패 (scenario={req.scenario}, model={req.model}): {e}", "ERROR")
        raise _llm_http_error(e)


# ═══════════════════════════════════════════════════════════════════
# AI 비서 — 회의 중 양방향 대화 + 자료조사 (claude CLI + WebSearch)
# ═══════════════════════════════════════════════════════════════════
ASSISTANT_SYSTEM = """당신은 회의 비서 '{name}'입니다.{expertise} {tone} 말투로 회의 참석자를 돕습니다.

[절대 규칙 — 반드시 지킬 것]
1. '[웹 검색 결과]'가 함께 주어지면 그것을 근거로 핵심을 정리하고, 끝에 참고한 출처(제목·URL)를 1~3개
   제시하세요. 검색 결과가 없으면 보유 지식으로 답하되, 검색/권한/활성화 같은 안내는 하지 마세요.
2. 사용자를 '대표님·사장님·고객님·님' 등 어떤 직함·호칭으로도 부르지 마세요. 직함 없이 답합니다.
3. '죄송합니다' 같은 과한 사과 없이 바로 본론으로 답하세요. 인사·자기소개 반복 금지.

[역할]
- 회의 맥락(받아쓰기·노트)을 참고해 질문에 답하고, 아이디어·정리·다음 할 일을 제안합니다.
- 자료 조사 요청 시 제공된 웹 검색 결과를 요약해 출처와 함께 알려줍니다.

[답변] 한국어, 간결하게(2~6문장). 표·짧은 목록 활용. 과장·영업 문구 금지. 추측 금지."""

RESEARCH_HINT_WORDS = ("찾아", "조사", "검색", "알아봐", "최신", "뉴스", "시세",
                       "통계", "자료", "리서치", "검토해", "비교해", "트렌드", "사례")


def web_search(query: str, max_results: int = 5) -> list:
    """무료 웹 검색 (DuckDuckGo, API key 불필요 = 비용 0). 실패 시 빈 리스트."""
    try:
        from ddgs import DDGS
        with DDGS() as d:
            return list(d.text(query, region="kr-kr", max_results=max_results))
    except Exception as e:
        print(f"[AI PRONOTE] 웹 검색 실패(무시): {e}")
        return []


def _strip_research_query(msg: str) -> str:
    """검색어 정리 = 명령형 표현 제거."""
    q = msg
    for w in ("좀", "찾아줘", "찾아봐", "조사해줘", "조사해", "알아봐줘", "알아봐",
              "검색해줘", "검색해", "검토해줘", "알려줘", "정리해줘", "?", "!"):
        q = q.replace(w, " ")
    return " ".join(q.split()).strip() or msg


def _clean_assistant_reply(text: str) -> str:
    """비서 답변 후처리 = 한국어 LLM이 습관적으로 붙이는 직함 호칭·과한 인사 제거.
    (시스템 프롬프트로 억제해도 일부 새는 것을 확실히 정리)"""
    import re
    t = (text or "").strip()
    # 직함 호칭 먼저 제거 (위치 무관) — "대표님, 안녕하세요"처럼 직함이 인사 앞에 와도 그 다음 인사 제거가 걸리도록
    t = re.sub(r"(대표님|사장님|고객님|팀장님)[,，·]?[ \t]*", "", t).strip()
    # 맨 앞 인사·자기소개 제거 ("안녕하세요, 노아입니다" / "안녕하세요. 저는 비서…")
    t = re.sub(r"^안녕하세요[.,!?\s]*(저는\s*)?([^.\n]{0,15}(비서|노아))?[^.\n]{0,8}(입니다|이에요|예요)?[.\s]*", "", t).strip()
    # 본론 앞 군더더기 도입 문장 제거 ("…하신 …를 조사해드렸습니다." 처럼 바로 다음 줄에 본론이 오는 경우)
    lines = t.split("\n")
    if len(lines) > 1:
        first = lines[0].strip()
        rest = "\n".join(lines[1:]).strip()
        if (len(first) <= 60
                and re.search(r"(해드렸습니다|드리겠습니다|정리했습니다|알려드릴게요|조사했습니다)[.!]?$", first)
                and rest):
            t = rest
    # 호칭·인사 제거 후 맨 앞에 남은 구두점/공백 잔재 정리
    t = re.sub(r"^[\s,，.·、:]+", "", t)
    return t.strip()


class AssistantRequest(BaseModel):
    message: str
    context: str = ""               # 회의 받아쓰기 + 내 노트
    history: list = []              # [{"role":"user|assistant","text":"..."}]
    name: str = "노아"
    tone: str = "정중한"
    expertise: str = ""             # ★ v1.4 회의별 에이전트 전문 분야 (예: 음원·페스티벌)
    model: str = "haiku"  # 회의 중 비서 = 빠르고 지시 준수 우수한 haiku 기본
    provider: str = "claude_cli"
    research: Optional[bool] = None  # (현재 미사용 — 웹검색은 BYOK 환경 제약으로 보류)
    external_consent: bool = False


@app.post("/api/assistant/chat")
def assistant_chat(req: AssistantRequest):
    """AI 비서 양방향 대화 (+ 필요 시 웹 자료조사)."""
    msg = (req.message or "").strip()
    if not msg:
        raise HTTPException(400, "message 비어있음")
    if not req.external_consent:
        raise HTTPException(403, "외부 AI 전송 동의가 필요합니다")
    # ★ 자료조사 = 무료 웹 검색(DuckDuckGo) → 검색 결과를 claude에 근거로 전달 → 요약·출처.
    #   비용 0 (검색 무료 + claude OAuth). server tool(WebSearch)의 API 과금 회피.
    research = req.research
    if research is None:
        research = any(w in msg for w in RESEARCH_HINT_WORDS)
    sources = []
    search_block = ""
    if research:
        hits = web_search(_strip_research_query(msg), max_results=5)
        if hits:
            lines = []
            for h in hits:
                title = (h.get("title") or "").strip()
                href = (h.get("href") or "").strip()
                body = (h.get("body") or "").strip()
                lines.append(f"- {title}\n  {body[:240]}\n  출처: {href}")
                if href:
                    sources.append({"title": title, "url": href})
            search_block = "[웹 검색 결과]\n" + "\n".join(lines)
        else:
            research = False  # 검색 실패 = 지식 기반으로 폴백
    system = ASSISTANT_SYSTEM.format(
        name=req.name or "노아", tone=req.tone or "정중한",
        expertise=(" 전문 분야는 " + req.expertise + " 입니다. 그 분야 전문가 관점에서 도우세요." if req.expertise else ""),
    )
    parts = []
    if search_block:
        parts.append(search_block)
    ctx = (req.context or "").strip()
    if ctx:
        parts.append(f"[회의 맥락 — 받아쓰기·노트]\n{ctx[:6000]}")
    if req.history:
        hist = []
        for m in req.history[-8:]:
            who = "사용자" if m.get("role") == "user" else (req.name or "비서")
            hist.append(f"{who}: {m.get('text', '')}")
        parts.append("[지금까지 대화]\n" + "\n".join(hist))
    parts.append(f"[사용자 질문]\n{msg}")
    content = "\n\n".join(parts)
    t0 = time.time()
    try:
        reply = call_llm(
            req.provider, system,
            "위 입력을 참고해 사용자에게 비서로서 한국어로 답하라."
            + (" 웹 검색 결과를 근거로 핵심을 정리하고 출처를 함께 제시하라." if search_block else ""),
            content,
            model_alias="haiku",  # 회의 비서 = 빠르고 지시 준수 우수 (검색 요약 포함)
            timeout=180 if search_block else 120,
        )
    except Exception as e:
        log(f"AI 비서 호출 실패: {e}", "ERROR")
        raise _llm_http_error(e)
    return {
        "reply": _clean_assistant_reply(reply),
        "research": bool(search_block),
        "sources": sources,
        "elapsed_sec": round(time.time() - t0, 1),
    }


# ══════════════════════════════════════════════════════════════════
# 받아쓰기 작업(job) 관리
#
# 한 시간짜리 녹음은 받아쓰는 데 20분이 넘게 걸린다. 옛 구조는 그동안 브라우저가
# HTTP 응답 하나를 붙들고 기다렸다 = 노트북이 절전에 들거나 Wi-Fi 가 끊기면
# 서버는 멀쩡히 끝냈는데도 결과가 화면에 닿지 못하고 사라졌다(실측 2026-08-20).
# 게다가 성공하면 표식을 지워버려서 "이어서 받아쓰기" 안내조차 뜨지 않았다.
#
# 그래서 업로드 요청은 job_id 만 즉시 돌려주고, 실제 작업은 뒤에서 돌린다.
# 화면은 진행률을 물어보고, 창을 닫았다 열어도 job_id 로 결과를 되찾는다.
# ══════════════════════════════════════════════════════════════════
import threading

_job_lock = threading.Lock()   # 받아쓰기는 한 번에 하나 (Whisper 모델 메모리 공유)
_job_state_lock = threading.RLock()
_summary_claim_lock = threading.Lock()
MAX_PENDING_JOBS = 8
_upload_reservations = 0
_maintenance_mode = False
_active_data_operations = 0
JOB_ID_PATTERN = re.compile(r"^[0-9a-f]{12}$")

JOB_ACTIVE = ("queued", "running")
JOB_RESUMABLE = ("interrupted", "error")


def _job_path(job_id: str) -> Path:
    if not JOB_ID_PATTERN.fullmatch(job_id or ""):
        raise HTTPException(400, "올바르지 않은 작업 번호입니다")
    return UPLOAD_DIR / f"{job_id}.job.json"


def _job_read(job_id: str) -> Optional[dict]:
    with _job_state_lock:
        try:
            return json.loads(_job_path(job_id).read_text(encoding="utf-8"))
        except HTTPException:
            raise
        except Exception:
            return None


def _atomic_json_write(path: Path, value: dict) -> None:
    temp = path.with_name(f".{path.name}.{uuid.uuid4().hex}.tmp")
    try:
        temp.write_text(json.dumps(value, ensure_ascii=False), encoding="utf-8")
        temp.replace(path)
    finally:
        temp.unlink(missing_ok=True)


def _atomic_text_write(path: Path, value: str) -> None:
    temp = path.with_name(f".{path.name}.{uuid.uuid4().hex}.tmp")
    try:
        temp.write_text(value, encoding="utf-8")
        temp.replace(path)
    finally:
        temp.unlink(missing_ok=True)


def _job_write(job_id: str, **fields) -> dict:
    with _job_state_lock:
        d = _job_read(job_id) or {"job_id": job_id}
        d.update(fields)
        d["updated_at"] = time.time()
        _atomic_json_write(_job_path(job_id), d)
        return d


def _job_audio(job_id: str) -> Optional[Path]:
    """그 작업의 원본 녹음 파일 (있어야 다시 돌릴 수 있다)"""
    _job_path(job_id)  # strict validation before using the value in a glob
    for f in UPLOAD_DIR.glob(job_id + ".*"):
        if f.suffix.lower() != ".json":
            return f
    return None


def _active_job_count() -> int:
    count = 0
    for path in UPLOAD_DIR.glob("*.job.json"):
        try:
            if json.loads(path.read_text(encoding="utf-8")).get("status") in JOB_ACTIVE:
                count += 1
        except Exception:
            continue
    return count


def _reserve_queue_slot() -> None:
    global _upload_reservations
    with _job_state_lock:
        if _maintenance_mode:
            raise HTTPException(503, "데이터 정리 중입니다. 잠시 후 다시 시도해 주세요")
        if _active_job_count() + _upload_reservations >= MAX_PENDING_JOBS:
            raise HTTPException(429, "처리 대기 작업이 많습니다. 완료 후 다시 시도해 주세요")
        _upload_reservations += 1


def _release_queue_slot() -> None:
    global _upload_reservations
    with _job_state_lock:
        _upload_reservations = max(0, _upload_reservations - 1)


def _begin_data_operation() -> None:
    global _active_data_operations
    with _job_state_lock:
        if _maintenance_mode:
            raise HTTPException(503, "데이터 정리 중입니다. 잠시 후 다시 시도해 주세요")
        _active_data_operations += 1


def _end_data_operation() -> None:
    global _active_data_operations
    with _job_state_lock:
        _active_data_operations = max(0, _active_data_operations - 1)


def _startup_recover_jobs() -> None:
    """서버가 켜질 때 — 돌던 중 죽은 작업을 '중단됨'으로 표시해 되살릴 수 있게 남긴다."""
    # 옛 버전의 표식(.pending.json)도 작업 기록으로 옮겨 온다
    for f in UPLOAD_DIR.glob("*.pending.json"):
        try:
            d = json.loads(f.read_text(encoding="utf-8"))
            jid = d.get("job_id")
            if jid and not _job_path(jid).exists():
                _job_write(jid, status="interrupted", phase="중단됨", progress=0,
                           error="이전 버전에서 끝내지 못한 작업입니다",
                           filename=d.get("filename"), language=d.get("language", "ko"),
                           model=d.get("model", DEFAULT_MODEL),
                           beam_size=int(d.get("beam_size", 1)),
                           diarize=bool(d.get("diarize", False)))
            f.unlink()
        except Exception:
            continue
    for f in UPLOAD_DIR.glob("*.job.json"):
        try:
            d = json.loads(f.read_text(encoding="utf-8"))
            if d.get("status") in JOB_ACTIVE:
                d.update(status="interrupted", phase="중단됨",
                         error="서버가 종료되어 중단됐습니다", updated_at=time.time())
                _atomic_json_write(f, d)
                log(f"중단된 받아쓰기 발견 — 다시 돌릴 수 있음: {d.get('filename')} ({d.get('job_id')})")
            if d.get("summary_status") == "running":
                d.update(summary_status="pending",
                         summary_error="서버 종료로 AI 정리가 중단되어 다시 대기합니다",
                         summary_next_at=time.time(), updated_at=time.time())
                _atomic_json_write(f, d)
        except Exception:
            continue


_startup_recover_jobs()


def _keep_awake(on: bool) -> None:
    """작업이 도는 동안 PC가 저절로 잠들지 않게 한다(끝나면 해제).

    회의가 끝나고 노트북을 열어둔 채 자리를 비워도 받아쓰기가 계속된다.
    뚜껑을 덮으면 절전에는 들어가지만, 다시 열었을 때 하던 자리에서 이어진다.
    (뚜껑을 덮었을 때의 동작은 사용자의 Windows 설정이므로 건드리지 않는다)
    """
    if sys.platform != "win32":
        return
    try:
        import ctypes
        ES_CONTINUOUS = 0x80000000
        ES_SYSTEM_REQUIRED = 0x00000001
        ctypes.windll.kernel32.SetThreadExecutionState(
            (ES_CONTINUOUS | ES_SYSTEM_REQUIRED) if on else ES_CONTINUOUS)
    except Exception as e:
        log(f"절전 방지 설정 실패(무시): {e}", "WARN")


def _job_worker(job_id: str, upload_path: Path, filename: str,
                language: str, model: str, beam_size: int, diarize: bool) -> None:
    """뒤에서 도는 받아쓰기 본체. 결과는 results/ 에 남으므로 화면이 꺼져도 잃지 않는다."""
    with _job_lock:
        _keep_awake(True)
        _job_write(job_id, status="running", phase="받아쓰기 준비 중", progress=1)
        try:
            def on_progress(pct: int, phase: str) -> None:
                _job_write(job_id, progress=pct, phase=phase)

            result = _run_transcription(upload_path, filename, job_id, language,
                                        model, beam_size, diarize, on_progress=on_progress)
            _job_write(job_id, status="done", phase="완료", progress=100,
                       finished_at=time.time(),
                       duration=result.get("duration"),
                       elapsed_sec=result.get("elapsed_sec"),
                       diarization=result.get("diarization"),
                       char_count=len(result.get("full_text") or ""))
            log(f"받아쓰기 완료: {filename} · {result.get('duration')}초 음성 → "
                f"{result.get('elapsed_sec')}초 처리 ({job_id})")
            # 화면이 떠 있든 아니든 서버가 회의록까지 만든다 (실패하면 대기열로)
            if (_job_read(job_id) or {}).get("auto_summarize"):
                _job_write(job_id, summary_status="pending",
                           summary_first_try_at=time.time())
                _try_summarize(job_id)
        except Exception as e:
            log(f"받아쓰기 실패 {job_id}: {e}", "ERROR")
            _job_write(job_id, status="error", phase="실패",
                       error=str(e)[:500], finished_at=time.time())
        finally:
            _keep_awake(False)


# ── 회의록 자동 생성 ───────────────────────────────────────────────
# 받아쓰기가 끝나면 서버가 곧바로 회의록까지 만든다. 화면이 떠 있든 아니든 상관없다.
# 인터넷이 끊겼거나 Claude 로그인이 만료됐으면 대기열에 남겨 두고,
# 조건이 회복되면 아래 지킴이 스레드가 알아서 다시 만든다.

SUMMARY_RETRY_DELAYS = (60, 180, 600, 1800, 3600)   # 1분 → 3분 → 10분 → 30분 → 1시간
SUMMARY_GIVEUP_SEC = 7 * 86400                       # 일주일까지는 포기하지 않는다


def _summary_path(job_id: str) -> Path:
    _job_path(job_id)
    return RESULT_DIR / f"{job_id}.summary.json"


def _next_retry_delay(attempts: int) -> int:
    idx = min(max(attempts - 1, 0), len(SUMMARY_RETRY_DELAYS) - 1)
    return SUMMARY_RETRY_DELAYS[idx]


def _try_summarize(job_id: str) -> bool:
    """그 작업의 회의록을 만들어 저장한다. 성공 True / 나중에 다시 할 것 False."""
    with _summary_claim_lock:
        with _job_state_lock:
            if _maintenance_mode:
                return False
            job = _job_read(job_id)
            if job and job.get("summary_status") == "running":
                return False
            if job:
                _job_write(job_id, summary_status="running")
    if not job:
        return False
    if not job.get("external_consent"):
        _job_write(job_id, summary_status="error", summary_error="외부 AI 전송 동의가 필요합니다", summary_error_kind="consent")
        return False
    rf = RESULT_DIR / f"{job_id}.json"
    if not rf.exists():
        _job_write(job_id, summary_status="error", summary_error="받아쓰기 결과가 없습니다")
        return False
    try:
        data = json.loads(rf.read_text(encoding="utf-8"))
    except Exception as e:
        _job_write(job_id, summary_status="error", summary_error=f"결과를 읽지 못했습니다: {e}")
        return False

    transcript = data.get("speaker_text") or data.get("full_text") or ""
    if not transcript.strip():
        _job_write(job_id, summary_status="error",
                   summary_error="녹음에서 말소리가 잡히지 않아 회의록을 만들 수 없습니다. "
                                 "마이크 상태를 확인한 뒤 다시 시도해 주세요.")
        log(f"회의록 생략 — 받아쓰기가 비어 있음 ({job_id})", "WARN")
        return False

    attempts = int(job.get("summary_attempts") or 0) + 1
    stored_provider = job.get("provider")
    provider = {"claude": "claude_cli", "codex": "codex_cli"}.get(
        stored_provider, stored_provider or "claude_cli"
    )
    if provider != stored_provider:
        _job_write(job_id, provider=provider)
    _job_write(job_id, summary_status="running", summary_attempts=attempts)
    try:
        out = build_summary(
            transcript,
            scenario=job.get("scenario") or "meeting",
            model_alias=job.get("llm_model") or "haiku",
            provider=provider,
            title=job.get("title") or "",
            attendees=job.get("attendees") or "",
            tag=job.get("tag") or "",
            date=job.get("date") or time.strftime("%Y-%m-%d"),
        )
    except Exception as e:
        kind = getattr(e, "kind", "unknown")
        first_at = job.get("summary_first_try_at") or time.time()
        waited = time.time() - first_at
        # 잠시 뒤면 되는 실패(인터넷·한도·혼잡) + 로그인 만료 = 계속 기다린다
        keep_waiting = (kind in RETRYABLE_KINDS or kind == "auth") and waited < SUMMARY_GIVEUP_SEC
        delay = _next_retry_delay(attempts)
        _job_write(job_id,
                   summary_status="pending" if keep_waiting else "error",
                   summary_error=str(e)[:400],
                   summary_error_kind=kind,
                   summary_first_try_at=first_at,
                   summary_next_at=(time.time() + delay) if keep_waiting else None)
        log(f"회의록 자동 생성 {'대기' if keep_waiting else '중단'} [{kind}] "
            f"{job.get('filename')} ({job_id}) — 시도 {attempts}회", "WARN")
        return False

    try:
        md_path = RESULT_DIR / f"{job_id}.summary.md"
        md_temp = md_path.with_name(f".{md_path.name}.{uuid.uuid4().hex}.tmp")
        md_temp.write_text(out.get("summary") or "", encoding="utf-8")
        md_temp.replace(md_path)
        # JSON is the completion marker and is committed last.
        _atomic_json_write(_summary_path(job_id), out)
    except Exception as e:
        log(f"회의록 저장 실패 {job_id}: {e}", "ERROR")
        _job_write(job_id, summary_status="error", summary_error=f"회의록 저장 실패: {e}")
        return False
    _job_write(job_id, summary_status="done", summary_error=None, summary_next_at=None,
               summary_title=out.get("title"), summary_char_count=out.get("char_count"),
               summary_done_at=time.time())
    log(f"회의록 자동 생성 완료: {out.get('title') or job.get('filename')} "
        f"({out.get('char_count')}자, {out.get('elapsed_sec')}초) ({job_id})")
    return True


def _run_summary_operation(job_id: str) -> bool:
    _begin_data_operation()
    try:
        return _try_summarize(job_id)
    finally:
        _end_data_operation()


def _summary_thread_entry(job_id: str) -> None:
    try:
        _try_summarize(job_id)
    finally:
        _end_data_operation()


def _start_summary_thread(job_id: str) -> None:
    _begin_data_operation()
    try:
        threading.Thread(target=_summary_thread_entry, args=(job_id,), daemon=True).start()
    except Exception:
        _end_data_operation()
        raise


def _process_pending_summary_file(path: Path, now: float) -> None:
    """Process one retry marker while holding the purge/write reservation."""
    try:
        _begin_data_operation()
    except HTTPException:
        return
    try:
        try:
            d = json.loads(path.read_text(encoding="utf-8"))
        except Exception:
            return
        if d.get("summary_status") != "pending" or (d.get("summary_next_at") or 0) > now:
            return
        if d.get("summary_error_kind") == "auth" and not _is_logged_in():
            _job_write(d["job_id"], summary_next_at=now + 60)
            return
        log(f"밀린 회의록 다시 시도: {d.get('filename')} ({d.get('job_id')})")
        _run_summary_operation(d["job_id"])
    finally:
        _end_data_operation()


def _summary_guard_loop() -> None:
    """대기열 지킴이 — 인터넷이 돌아오거나 다시 로그인하면 밀린 회의록을 알아서 만든다."""
    while True:
        try:
            time.sleep(30)
            now = time.time()
            for f in sorted(UPLOAD_DIR.glob("*.job.json"), key=lambda x: x.stat().st_mtime):
                _process_pending_summary_file(f, now)
        except Exception as e:
            log(f"회의록 지킴이 오류(무시): {e}", "WARN")


threading.Thread(target=_summary_guard_loop, daemon=True).start()


def _job_start(job_id: str, upload_path: Path, filename: str,
               language: str, model: str, beam_size: int, diarize: bool) -> None:
    _begin_data_operation()
    try:
        def run_worker() -> None:
            try:
                _job_worker(job_id, upload_path, filename, language, model, beam_size, diarize)
            finally:
                _end_data_operation()
        threading.Thread(
            target=run_worker,
            daemon=True,
        ).start()
    except Exception:
        _end_data_operation()
        raise


@app.get("/api/jobs")
def list_jobs(limit: int = 50):
    """받아쓰기 작업 목록 (최근 순)"""
    out = []
    for f in sorted(UPLOAD_DIR.glob("*.job.json"), key=lambda x: x.stat().st_mtime, reverse=True)[:limit]:
        try:
            d = json.loads(f.read_text(encoding="utf-8"))
        except Exception:
            continue
        d["has_audio"] = _job_audio(d.get("job_id")) is not None
        d["queue_view"] = JobQueueView.from_job(d).as_dict()
        out.append(d)
    return out


@app.get("/api/jobs/{job_id}")
def get_job(job_id: str):
    """진행 상황 조회 — 화면이 이걸 주기적으로 물어본다 (결과 본문은 /api/results 로 따로)"""
    d = _job_read(job_id)
    if not d:
        raise HTTPException(404, "작업을 찾을 수 없습니다")
    d["has_audio"] = _job_audio(job_id) is not None
    d["has_result"] = (RESULT_DIR / f"{job_id}.json").exists()
    d["queue_view"] = JobQueueView.from_job(d).as_dict()
    return d


@app.get("/api/audio/{job_id}")
def get_audio(job_id: str):
    """그 회의의 원본 녹음. 화면이 결과만 되찾은 경우에도 듣고 내려받을 수 있게."""
    f = _job_audio(job_id)
    if not f or not f.exists():
        raise HTTPException(404, "녹음 파일이 없습니다")
    mt = {".webm": "audio/webm", ".mp3": "audio/mpeg", ".wav": "audio/wav",
          ".m4a": "audio/mp4", ".mp4": "audio/mp4", ".ogg": "audio/ogg",
          ".flac": "audio/flac"}.get(f.suffix.lower(), "application/octet-stream")
    job = _job_read(job_id) or {}
    name = job.get("filename") or f.name
    return FileResponse(str(f), media_type=mt, filename=name)


@app.get("/api/results")
def list_results(limit: int = 100):
    """서버에 저장된 받아쓰기 결과 목록.
    화면이 결과를 놓쳤을 때(네트워크 끊김·창 닫음) 여기서 되찾는다."""
    out = []
    for f in sorted(RESULT_DIR.glob("*.json"), key=lambda x: x.stat().st_mtime, reverse=True)[:limit]:
        try:
            d = json.loads(f.read_text(encoding="utf-8"))
        except Exception:
            continue
        text = d.get("speaker_text") or d.get("full_text") or ""
        out.append({
            "job_id": f.stem,
            "filename": d.get("filename"),
            "duration": d.get("duration"),
            "elapsed_sec": d.get("elapsed_sec"),
            "model": d.get("model"),
            "diarization": d.get("diarization"),
            "char_count": len(text),
            "saved_at": f.stat().st_mtime,
            "preview": text[:200],
        })
    return out


@app.get("/api/results/{job_id}")
def get_result(job_id: str):
    """받아쓰기 결과 전문 + 서버가 만들어 둔 회의록.
    화면이 결과를 놓쳤어도(창을 닫았든 연결이 끊겼든) 여기서 그대로 되찾는다."""
    _job_path(job_id)
    f = RESULT_DIR / f"{job_id}.json"
    if not f.exists():
        raise HTTPException(404, "저장된 결과가 없습니다")
    try:
        data = json.loads(f.read_text(encoding="utf-8"))
    except Exception as e:
        raise HTTPException(500, f"결과를 읽지 못했습니다: {e}")

    job = _job_read(job_id) or {}
    sf = _summary_path(job_id)
    if sf.exists() and job.get("summary_status") == "done":
        try:
            data["summary_result"] = json.loads(sf.read_text(encoding="utf-8"))
        except Exception:
            pass
    data["job"] = {k: job.get(k) for k in (
        "status", "phase", "progress", "scenario", "title", "attendees", "tag", "date",
        "summary_status", "summary_error", "summary_error_kind", "summary_attempts",
        "auto_summarize", "llm_model", "provider",
    )}
    return JSONResponse(data)


@app.post("/api/summarize/redo/{job_id}")
def summarize_redo(job_id: str, scenario: Optional[str] = None,
                   llm_model: Optional[str] = None, provider: Optional[str] = None,
                   external_consent: bool = False):
    """회의록 다시 만들기 — 화면의 [회의록 다시 만들기] 버튼이 부른다.
    실패하면 대기열에 남아 조건이 회복될 때 서버가 알아서 다시 만든다."""
    _begin_data_operation()
    try:
        if not external_consent:
            raise HTTPException(403, "외부 AI 전송 동의가 필요합니다")
        job = _job_read(job_id)
        if not job:
            if not (RESULT_DIR / f"{job_id}.json").exists():
                raise HTTPException(404, "작업을 찾을 수 없습니다")
            job = _job_write(job_id, filename=f"{job_id}", status="done",
                             started_at=time.time(), auto_summarize=True)
        patch = {"summary_status": "pending", "summary_attempts": 0,
                 "summary_error": None, "summary_error_kind": None,
                 "summary_first_try_at": time.time(), "summary_next_at": None,
                 "auto_summarize": True, "external_consent": True}
        if scenario:
            patch["scenario"] = scenario
        if llm_model:
            patch["llm_model"] = llm_model
        if provider:
            patch["provider"] = provider
        _job_write(job_id, **patch)
        _start_summary_thread(job_id)
        log(f"회의록 다시 만들기 요청: {job.get('filename')} ({job_id})")
        return {"job_id": job_id, "summary_status": "pending"}
    finally:
        _end_data_operation()


@app.get("/api/summarize/{job_id}")
def get_summary(job_id: str):
    """회의록만 조회 (진행 상태 포함) — 화면이 완성될 때까지 이걸 물어본다."""
    job = _job_read(job_id) or {}
    out = {
        "job_id": job_id,
        "summary_status": job.get("summary_status") or "none",
        "summary_error": job.get("summary_error"),
        "summary_error_kind": job.get("summary_error_kind"),
        "summary_attempts": job.get("summary_attempts") or 0,
        "summary_next_at": job.get("summary_next_at"),
    }
    sf = _summary_path(job_id)
    if sf.exists() and job.get("summary_status") == "done":
        try:
            out["result"] = json.loads(sf.read_text(encoding="utf-8"))
            out["summary_status"] = "done"
        except Exception:
            pass
    return out


@app.get("/api/pending")
def list_pending():
    """끝내지 못한 받아쓰기 = 중단·실패했고 원본 녹음이 남아 있어 다시 돌릴 수 있는 것"""
    jobs = []
    for f in sorted(UPLOAD_DIR.glob("*.job.json"), key=lambda x: x.stat().st_mtime, reverse=True):
        try:
            d = json.loads(f.read_text(encoding="utf-8"))
        except Exception:
            continue
        if d.get("status") in JOB_RESUMABLE and _job_audio(d.get("job_id")):
            d.setdefault("started_at_label",
                         time.strftime("%Y-%m-%d %H:%M", time.localtime(d.get("started_at") or f.stat().st_mtime)))
            jobs.append(d)
    return jobs


@app.delete("/api/pending/{job_id}")
def delete_pending(job_id: str):
    """다시 안 하겠다 = 작업 기록만 지운다 (원본 녹음·결과는 그대로 둔다)"""
    _begin_data_operation()
    try:
        _job_path(job_id).unlink(missing_ok=True)
        return {"ok": True}
    finally:
        _end_data_operation()


@app.post("/api/data/purge")
def purge_local_data(req: PurgeDataRequest, request: Request):
    """Permanently remove this installation's local meeting data."""
    if IPAD_MODE:
        raise HTTPException(403, "iPad companion에서 전체 삭제를 실행할 수 없습니다")
    client_host = request.client.host if request.client else ""
    if client_host not in {"127.0.0.1", "::1", "testclient"}:
        raise HTTPException(403, "이 PC에서만 전체 삭제를 실행할 수 있습니다")
    expected_origin = f"{request.url.scheme}://{request.headers.get('host', '')}"
    origin = request.headers.get("origin", "")
    if origin and origin != expected_origin:
        raise HTTPException(403, "same-origin request required")
    if req.confirmation != "AI PRONOTE 데이터 영구 삭제":
        raise HTTPException(400, "삭제 확인 문구가 일치하지 않습니다")
    global _maintenance_mode
    with _job_state_lock:
        if _maintenance_mode:
            raise HTTPException(409, "이미 데이터 정리 중입니다")
        summary_running = any(
            (_job_read(path.name[:12]) or {}).get("summary_status") == "running"
            for path in UPLOAD_DIR.glob("*.job.json")
            if JOB_ID_PATTERN.fullmatch(path.name[:12])
        )
        if (_active_job_count() > 0 or _upload_reservations > 0
                or _active_data_operations > 0 or summary_running):
            raise HTTPException(409, "처리 중인 작업이 있습니다. 작업 완료 후 다시 시도하세요")
        _maintenance_mode = True

    try:
        try:
            removed_entries = purge_managed_data(DATA_ROOT, (UPLOAD_DIR, RESULT_DIR, LOG_DIR))
            SESSION_FLAG_PATH.unlink(missing_ok=True)
        except (OSError, ValueError) as error:
            return JSONResponse(
                {"ok": False, "partial": True, "detail": "일부 파일을 지우지 못했습니다. 앱을 종료한 뒤 다시 시도하세요.",
                 "error_type": type(error).__name__},
                status_code=500,
            )

        removed_credentials = []
        failed_credentials = []
        try:
            store = WindowsCredentialStore()
        except RuntimeError:
            store = None
        if store is not None:
            for provider_name in ("openai", "gemini", "anthropic"):
                try:
                    store.delete(provider_name)
                    removed_credentials.append(provider_name)
                except Exception as error:
                    failed_credentials.append(provider_name)
                    log(f"자격 증명 삭제 실패: {provider_name}: {type(error).__name__}", "WARN")
        payload = {
            "ok": not failed_credentials,
            "partial": bool(failed_credentials),
            "removed_entries": removed_entries,
            "removed_credentials": removed_credentials,
            "failed_credentials": failed_credentials,
            "note": "외부 CLI 계정 로그인 정보는 해당 CLI에서 별도로 로그아웃해야 합니다.",
        }
        return JSONResponse(payload, status_code=207 if failed_credentials else 200)
    finally:
        with _job_state_lock:
            _maintenance_mode = False


@app.post("/api/transcribe/redo/{job_id}")
def transcribe_redo(job_id: str):
    """끊긴 작업 = 저장된 원본 녹음으로 다시 받아쓰기 (뒤에서 처리)"""
    _begin_data_operation()
    try:
        info = _job_read(job_id)
        if not info:
            raise HTTPException(404, "미완료 작업이 없습니다")
        audio = _job_audio(job_id)
        if not audio:
            raise HTTPException(404, "원본 녹음 파일이 없습니다")
        if info.get("status") in JOB_ACTIVE:
            return {"job_id": job_id, "status": info.get("status"), "note": "이미 처리 중입니다"}
        _job_write(job_id, status="queued", phase="대기 중", progress=0,
                   error=None, started_at=time.time())
        _job_start(job_id, audio, info.get("filename") or audio.name,
                   info.get("language", "ko"), info.get("model", DEFAULT_MODEL),
                   int(info.get("beam_size", 1)), bool(info.get("diarize", False)))
        log(f"받아쓰기 다시 시작: {info.get('filename')} ({job_id})")
        return {"job_id": job_id, "status": "queued"}
    finally:
        _end_data_operation()


@app.post("/api/export/mp3")
async def export_mp3(file: UploadFile = File(...)):
    """녹음(webm 등) → MP3 변환 — 어디서나 열리는 형식으로 저장용. 로컬 변환, 비용 0."""
    _begin_data_operation()
    src = UPLOAD_DIR / f"_mp3src_{uuid.uuid4().hex[:8]}.bin"
    dst = src.with_suffix(".mp3")
    response_ready = False
    try:
        total = 0
        with src.open("wb") as destination:
            while chunk := await file.read(1024 * 1024):
                total += len(chunk)
                if total > MAX_UPLOAD_BYTES:
                    raise HTTPException(413, "파일은 512MB 이하여야 합니다")
                destination.write(chunk)
        if total == 0:
            raise HTTPException(400, "빈 파일")
        import av
        inp = av.open(str(src))
        out = av.open(str(dst), "w")
        ist = inp.streams.audio[0]
        ost = out.add_stream("libmp3lame", rate=44100)
        resampler = av.AudioResampler(format="s16", layout="stereo", rate=44100)
        for frame in inp.decode(ist):
            for rf in resampler.resample(frame):
                rf.pts = None
                for pkt in ost.encode(rf):
                    out.mux(pkt)
        for pkt in ost.encode(None):
            out.mux(pkt)
        out.close()
        inp.close()
        src.unlink(missing_ok=True)
        response_ready = True
        def finish_response() -> None:
            try:
                dst.unlink(missing_ok=True)
            finally:
                _end_data_operation()
        return FileResponse(str(dst), media_type="audio/mpeg", filename="AI_PRONOTE.mp3",
                            background=BackgroundTask(finish_response))
    except HTTPException:
        raise
    except Exception as e:
        print(f"[AI PRONOTE] mp3 변환 에러: {e}")
        raise HTTPException(500, f"MP3 변환 실패: {e}")
    finally:
        for p in (src, dst):
            try:
                if p.exists() and (p != dst or not response_ready):
                    p.unlink()
            except Exception:
                pass
        if not response_ready:
            _end_data_operation()


# ═══════════════════════════════════════════════════════════════════
# 회의록 → 워드(.docx) 내보내기 (★ v1.4)
#   맑은 고딕 본문 + 파란 제목(#2E74B5) = 보고서 디자인 표준(글로벌 룰 24).
#   어디서나 열어 수정·공유 (텍스트뿐이던 것 → 정식 문서).
# ═══════════════════════════════════════════════════════════════════
class DocxRequest(BaseModel):
    title: str = "회의록"
    summary: str = ""              # markdown (AI 회의록 본문)
    attendees: str = ""
    date: str = ""
    transcript: str = ""
    include_transcript: bool = False


def _docx_add_runs(p, text):
    """**굵게** 마크다운을 docx run 으로."""
    parts = re.split(r'(\*\*[^*]+\*\*)', text)
    for seg in parts:
        if len(seg) > 4 and seg.startswith('**') and seg.endswith('**'):
            r = p.add_run(seg[2:-2]); r.bold = True
        elif seg:
            p.add_run(seg)


def _md_to_docx(doc, md):
    from docx.shared import RGBColor
    BLUE = RGBColor(0x2E, 0x74, 0xB5)
    for raw in (md or "").split("\n"):
        line = raw.rstrip()
        if not line.strip():
            continue
        s = line.lstrip()
        if s.startswith("### "):
            h = doc.add_heading(s[4:], level=3)
            for r in h.runs: r.font.color.rgb = BLUE
        elif s.startswith("## "):
            h = doc.add_heading(s[3:], level=2)
            for r in h.runs: r.font.color.rgb = BLUE
        elif s.startswith("# "):
            h = doc.add_heading(s[2:], level=1)
            for r in h.runs: r.font.color.rgb = BLUE
        elif s.startswith(("- ", "* ")):
            _docx_add_runs(doc.add_paragraph(style="List Bullet"), s[2:])
        elif re.match(r"^\d+\.\s", s):
            _docx_add_runs(doc.add_paragraph(style="List Number"), re.sub(r"^\d+\.\s", "", s))
        else:
            _docx_add_runs(doc.add_paragraph(), line)


@app.post("/api/export/docx")
def export_docx(req: DocxRequest):
    """회의록 markdown → 워드(.docx) 바이트 반환."""
    try:
        import io
        from docx import Document
        from docx.shared import Pt, RGBColor
        from docx.oxml.ns import qn
        doc = Document()
        normal = doc.styles["Normal"]
        normal.font.name = "맑은 고딕"
        normal.font.size = Pt(11)
        try:
            normal.element.get_or_add_rPr().get_or_add_rFonts().set(qn("w:eastAsia"), "맑은 고딕")
        except Exception:
            pass
        title = (req.title or "회의록").strip()
        h = doc.add_heading(title, level=0)
        for r in h.runs:
            r.font.color.rgb = RGBColor(0x2E, 0x74, 0xB5)
        meta = []
        if req.date: meta.append(f"날짜: {req.date}")
        if req.attendees: meta.append(f"참석자: {req.attendees}")
        if meta:
            doc.add_paragraph(" · ".join(meta))
        _md_to_docx(doc, req.summary)
        if req.include_transcript and req.transcript:
            ht = doc.add_heading("전체 받아쓰기", level=1)
            for r in ht.runs:
                r.font.color.rgb = RGBColor(0x2E, 0x74, 0xB5)
            for ln in req.transcript.split("\n"):
                if ln.strip():
                    doc.add_paragraph(ln.strip())
        buf = io.BytesIO()
        doc.save(buf)
        data = buf.getvalue()
    except Exception as e:
        raise HTTPException(500, f"워드 생성 실패: {e}")
    from urllib.parse import quote
    safe = "".join(c for c in title if c.isalnum() or c in " _-").strip()[:40] or "회의록"
    return Response(
        content=data,
        media_type="application/vnd.openxmlformats-officedocument.wordprocessingml.document",
        headers={"Content-Disposition": f"attachment; filename*=UTF-8''{quote(safe)}.docx"},
    )


# ═══════════════════════════════════════════════════════════════════
# 번역 (★ v1.4) — 해외/화상 회의. 받아쓰기·회의록을 다른 언어로 (Claude, 비용 0).
# ═══════════════════════════════════════════════════════════════════
TRANSLATE_LANGS = {
    "ko": "한국어", "en": "영어", "ja": "일본어",
    "zh": "중국어", "vi": "베트남어", "es": "스페인어", "fr": "프랑스어",
}


class TranslateRequest(BaseModel):
    text: str
    target: str = "en"
    provider: str = "claude_cli"
    external_consent: bool = False


@app.post("/api/llm/translate")
def llm_translate(req: TranslateRequest):
    if not req.text or not req.text.strip():
        raise HTTPException(400, "text 비어있음")
    if not req.external_consent:
        raise HTTPException(403, "외부 AI 전송 동의가 필요합니다")
    lang = TRANSLATE_LANGS.get(req.target, req.target)
    system = (f"당신은 전문 번역가입니다. 입력 텍스트를 자연스럽고 정확한 {lang}로 번역하세요. "
              f"회의·강의 맥락을 살리고, 번역문만 출력하세요(설명·원문 병기 금지).")
    t0 = time.time()
    try:
        out = call_llm(req.provider, system, f"위 입력을 {lang}로 번역하라.",
                       req.text, model_alias="sonnet", timeout=600)
    except Exception as e:
        raise HTTPException(500, f"번역 실패: {e}")
    return {"translated": (out or "").strip(), "target": req.target,
            "lang": lang, "elapsed_sec": round(time.time() - t0, 1)}


@app.post("/api/transcribe/partial")
async def transcribe_partial(
    file: UploadFile = File(...),
    language: str = Form("ko"),
    model: str = Form("small"),     # 실시간 초안 = 속도 우선
    offset_sec: float = Form(0.0),
):
    """실시간 받아쓰기용 부분 변환 — 독립 webm 청크 1개를 빠르게 텍스트로.
    pending 마커 생성 X (이어하기와 무관한 일회성 처리). 결과 저장 X."""
    _begin_data_operation()
    tmp_path = None
    try:
        partial_limit = 25 * 1024 * 1024
        contents = await file.read(partial_limit + 1)
        if not contents:
            raise HTTPException(400, "빈 청크")
        if len(contents) > partial_limit:
            raise HTTPException(413, "실시간 녹음 청크는 25MB 이하여야 합니다")
        tmp_path = UPLOAD_DIR / f"_partial_{uuid.uuid4().hex[:8]}.webm"
        tmp_path.write_bytes(contents)
        m = get_model(model)
        kwargs = dict(language=language, beam_size=1, batch_size=8,
                      vad_filter=True, vad_parameters=dict(min_silence_duration_ms=500),
                      no_repeat_ngram_size=3, repetition_penalty=1.15,
                      compression_ratio_threshold=2.4, log_prob_threshold=-1.0,
                      no_speech_threshold=0.6)
        if language == "ko":
            kwargs["initial_prompt"] = KOREAN_INITIAL_PROMPT
            if KOREAN_HOTWORDS:
                kwargs["hotwords"] = KOREAN_HOTWORDS
        try:
            segments_iter, info = m.transcribe(str(tmp_path), **kwargs)
        except TypeError:
            segments_iter, info = m.transcribe(str(tmp_path), language=language, beam_size=1, batch_size=8)
        segs = []
        for seg in segments_iter:
            st = _clean_text(seg.text)
            if not st:
                continue
            segs.append({
                "start": round(seg.start + offset_sec, 2),
                "end": round(seg.end + offset_sec, 2),
                "text": st,
            })
        return JSONResponse({"segments": segs, "duration": round(getattr(info, "duration", 0.0), 1)})
    except HTTPException:
        raise
    except Exception as e:
        print(f"[AI PRONOTE] partial 에러: {e}")
        raise HTTPException(500, f"부분 변환 실패: {e}")
    finally:
        try:
            if tmp_path is not None:
                tmp_path.unlink()
        except Exception:
            pass
        _end_data_operation()


@app.post("/api/transcribe")
async def transcribe(
    file: UploadFile = File(...),
    language: str = Form("ko"),
    model: str = Form(DEFAULT_MODEL),
    beam_size: int = Form(1),       # ★ V1.3 — 1=빠름 / 5=정확
    diarize: bool = Form(False),    # ★ V1.3 — 화자 분리 (pyannote)
    # ↓ 회의 정보 — 화면이 꺼져 있어도 서버 혼자 회의록까지 만들 수 있도록 함께 받는다
    auto_summarize: bool = Form(True),
    scenario: str = Form("meeting"),
    llm_model: str = Form("haiku"),
    provider: str = Form("claude_cli"),
    external_consent: bool = Form(False),
    title: str = Form(""),
    attendees: str = Form(""),
    tag: str = Form(""),
    date: str = Form(""),
):
    """음성 파일 받아쓰기 시작 — 즉시 job_id 를 돌려주고 실제 처리는 뒤에서 한다.

    진행 상황 = GET /api/jobs/{job_id} · 결과 = GET /api/results/{job_id}
    (옛 방식은 여기서 20분 넘게 응답을 붙들었고, 그 사이 연결이 끊기면 결과가 사라졌다)
    """
    if not file.filename:
        raise HTTPException(400, "파일 이름이 없습니다")
    if auto_summarize and not external_consent:
        raise HTTPException(403, "회의록 생성을 위한 외부 AI 전송 동의가 필요합니다")

    declared_size = getattr(file, "size", None)
    if declared_size is not None:
        ok, reason = allowed_upload(file.filename, declared_size)
        if not ok:
            raise HTTPException(400, reason)
    suffix = Path(file.filename).suffix.lower()
    # Validate the suffix before reserving queue capacity or writing any bytes.
    ok, reason = allowed_upload(file.filename, 1)
    if not ok:
        raise HTTPException(400, reason)
    _reserve_queue_slot()
    job_id = uuid.uuid4().hex[:12]
    upload_path = UPLOAD_DIR / f"{job_id}{suffix}"
    partial_path = upload_path.with_suffix(upload_path.suffix + ".part")
    total_bytes = 0
    registered = False
    try:
        with partial_path.open("wb") as destination:
            while chunk := await file.read(1024 * 1024):
                total_bytes += len(chunk)
                if total_bytes > MAX_UPLOAD_BYTES:
                    raise HTTPException(413, "파일은 512MB 이하여야 합니다")
                destination.write(chunk)
        ok, reason = allowed_upload(file.filename, total_bytes)
        if not ok:
            raise HTTPException(400, reason)
        partial_path.replace(upload_path)
        size_mb = round(total_bytes / 1024 / 1024, 1)
        log(f"업로드: {file.filename} ({size_mb} MB) -> {upload_path.name} · 모델 {model} · beam {beam_size}")

        _job_write(job_id, status="queued", phase="대기 중", progress=0,
                   filename=file.filename, size_mb=size_mb, language=language,
                   model=model, beam_size=int(beam_size), diarize=bool(diarize),
                   started_at=time.time(), error=None,
                   auto_summarize=bool(auto_summarize), scenario=scenario,
                   llm_model=llm_model, provider=provider, title=title,
                   attendees=attendees, tag=tag, date=date or time.strftime("%Y-%m-%d"),
                   external_consent=bool(external_consent),
                   summary_status="none", summary_attempts=0)
        registered = True
        _job_start(job_id, upload_path, file.filename, language, model, int(beam_size), bool(diarize))
    except Exception:
        partial_path.unlink(missing_ok=True)
        if not registered:
            upload_path.unlink(missing_ok=True)
        raise
    finally:
        _release_queue_slot()
    return JSONResponse({"job_id": job_id, "status": "queued", "async": True,
                         "filename": file.filename, "size_mb": size_mb})


def _run_transcription(upload_path: Path, filename: str, job_id: str,
                       language: str, model: str, beam_size: int, diarize: bool,
                       on_progress=None) -> dict:
    """받아쓰기 본체 — /api/transcribe 와 /api/transcribe/redo 공용.
    on_progress(퍼센트, 문구) = 진행 상황 보고 (없으면 조용히 처리)"""
    size_mb = round(upload_path.stat().st_size / 1024 / 1024, 1)

    def report(pct: int, phase: str) -> None:
        if on_progress:
            try:
                on_progress(pct, phase)
            except Exception:
                pass

    try:
        report(2, "받아쓰기 모델 준비 중")
        m = get_model(model)
        t_start = time.time()
        # 한국어 정확도 개선 + 환각·반복 억제 (2026-07-14 실측 반영).
        #   no_repeat_ngram_size/repetition_penalty = "한 번에 한 번에…" 루프 차단
        #   compression/log_prob/no_speech_threshold = 무음 구간 환각 세그먼트 폐기
        tx_kwargs = dict(
            language=language,
            beam_size=max(1, min(int(beam_size), 5)),
            batch_size=8,
            vad_filter=True,
            vad_parameters=dict(min_silence_duration_ms=500),
            no_repeat_ngram_size=3,
            repetition_penalty=1.15,
            compression_ratio_threshold=2.4,
            log_prob_threshold=-1.0,
            no_speech_threshold=0.6,
        )
        if language == "ko":
            tx_kwargs["initial_prompt"] = KOREAN_INITIAL_PROMPT
            if KOREAN_HOTWORDS:
                # 고유명사 힌트 — initial_prompt 와 달리 본문에 새어 나오지 않는다
                tx_kwargs["hotwords"] = KOREAN_HOTWORDS
        try:
            segments_iter, info = m.transcribe(str(upload_path), **tx_kwargs)
        except TypeError:
            # 설치된 faster-whisper 버전이 일부 인자 미지원 = 핵심 인자만 재시도
            segments_iter, info = m.transcribe(
                str(upload_path), language=language,
                beam_size=tx_kwargs["beam_size"], batch_size=8,
            )
        segments = []
        full_text_parts = []
        prev_text = None
        total_sec = float(getattr(info, "duration", 0) or 0)
        last_pct, last_report_at = -1, 0.0
        for seg in segments_iter:
            # 진행률 = 음성에서 어디까지 왔는지 (초 단위라 정확하다)
            if total_sec > 0:
                pct = min(96, 3 + int(seg.end / total_sec * 93))
                now_ts = time.time()
                if pct != last_pct and (now_ts - last_report_at) >= 1.0:
                    report(pct, f"받아쓰기 중 {pct}%")
                    last_pct, last_report_at = pct, now_ts
            st = _clean_text(seg.text)
            if not st:
                continue
            # ★ v1.4 — 직전 세그먼트와 완전히 동일 = 반복 환각 → 1회만 남김
            if prev_text is not None and st == prev_text:
                continue
            prev_text = st
            segments.append({
                "id": seg.id,
                "start": round(seg.start, 2),
                "end": round(seg.end, 2),
                "text": st,
            })
            full_text_parts.append(st)
        elapsed = round(time.time() - t_start, 1)

        # ★ V1.3 — 화자 분리 (옵션). pyannote·HF_TOKEN 없으면 자동 skip.
        diarization = "off"
        speaker_text = None
        if diarize:
            report(97, "화자 분리 중")
            try:
                import diarize as _dz
                ok, reason = _dz.diarization_available()
                if ok:
                    turns = _dz.diarize_audio(str(upload_path))
                    segments = _dz.assign_speakers(segments, turns)
                    speaker_text = _dz.speaker_transcript(segments)
                    speakers = sorted({s.get("speaker") for s in segments if s.get("speaker")})
                    diarization = f"on · 화자 {len(speakers)}명"
                else:
                    diarization = f"unavailable: {reason}"
            except Exception as e:
                diarization = f"error: {e}"
                print(f"[AI PRONOTE] 화자 분리 오류: {e}")

        result = {
            "job_id": job_id,
            "filename": filename,
            "size_mb": size_mb,
            "language": info.language,
            "duration": round(info.duration, 1),
            "elapsed_sec": elapsed,
            "model": model,
            "beam_size": tx_kwargs["beam_size"],
            "diarization": diarization,
            "full_text": "\n".join(full_text_parts),
            "speaker_text": speaker_text,
            "segments": segments,
        }

        # 결과 저장 (JSON + TXT)
        _atomic_text_write(
            RESULT_DIR / f"{job_id}.json",
            json.dumps(result, ensure_ascii=False, indent=2),
        )
        _atomic_text_write(
            RESULT_DIR / f"{job_id}.txt",
            speaker_text or "\n".join(full_text_parts),
        )

        print(f"[AI PRONOTE] 완료: {filename} · {info.duration}초 음성 → {elapsed}초 처리 · 화자분리 {diarization}")
        return result

    except HTTPException:
        raise


if __name__ == "__main__":
    import uvicorn
    # P0 기본값은 이 PC에서만 접근 가능. iPad 테스트는 인증·HTTPS를 붙인 뒤 별도 승인한다.
    HOST = os.environ.get("PRONOTE_HOST", "127.0.0.1")
    if HOST not in {"127.0.0.1", "localhost"} and not IPAD_MODE:
        raise RuntimeError("LAN 바인딩은 PRONOTE_IPAD_MODE=true일 때만 허용됩니다")
    if IPAD_MODE and (not LAN_TOKEN or len(LAN_TOKEN) < 32):
        raise RuntimeError("iPad 모드는 32자 이상의 PRONOTE_LAN_TOKEN이 필요합니다")
    cert_file = os.environ.get("PRONOTE_HTTPS_CERT", "")
    key_file = os.environ.get("PRONOTE_HTTPS_KEY", "")
    if IPAD_MODE and (not Path(cert_file).is_file() or not Path(key_file).is_file()):
        raise RuntimeError("iPad 모드는 유효한 HTTPS 인증서와 개인키 파일이 필요합니다")
    # 기존 v1.3/v1.4의 8771과 분리한 검증 포트.
    PORT = int(os.environ.get("PRONOTE_PORT", "8795"))
    exposure = "이 PC 전용" if HOST in {"127.0.0.1", "localhost"} else f"네트워크 바인딩: {HOST}"
    print(f"[AI PRONOTE] {APP_VERSION} 서버 시작: http://localhost:{PORT}  ({exposure})")
    uvicorn.run(
        app, host=HOST, port=PORT, log_level="info",
        ssl_certfile=cert_file or None, ssl_keyfile=key_file or None,
        access_log=not IPAD_MODE,
    )
