"""
AI PRONOTE — 프로토타입
Whisper 받아쓰기 + Claude OAuth 회의록 자동 정리 + Supabase 인증
"""
import os
import sys
import time
import uuid
import json
import urllib.request
import urllib.error
from pathlib import Path
from typing import Optional

# pythonw.exe (콘솔 X) 환경 = sys.stdout/stderr = None → print() 즉사 방지
# 디버그 = 로그 파일로 redirect (server.log·server.err.log 살리기)
_LOG_DIR = Path(__file__).parent
if sys.stdout is None:
    sys.stdout = open(_LOG_DIR / "server.log", "w", encoding="utf-8", buffering=1)
if sys.stderr is None:
    sys.stderr = open(_LOG_DIR / "server.err.log", "w", encoding="utf-8", buffering=1)

from fastapi import FastAPI, File, UploadFile, HTTPException, Form
from fastapi.responses import FileResponse, JSONResponse
from fastapi.staticfiles import StaticFiles
from pydantic import BaseModel
from faster_whisper import WhisperModel, BatchedInferencePipeline

ROOT = Path(__file__).parent
UPLOAD_DIR = ROOT / "uploads"
STATIC_DIR = ROOT / "static"
RESULT_DIR = ROOT / "results"

UPLOAD_DIR.mkdir(exist_ok=True)
RESULT_DIR.mkdir(exist_ok=True)

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

_model_cache: dict = {}

# ═══════════════════════════════════════════════════════════════════
# Claude OAuth (옛 스토리메이커 LOCAL 패턴 — Pro 구독 그대로 사용, API key X)
# ═══════════════════════════════════════════════════════════════════
CREDENTIALS_PATH = Path.home() / ".claude" / ".credentials.json"

CLAUDE_MODELS = {
    "haiku": "claude-haiku-4-5-20251001",
    "sonnet": "claude-sonnet-4-6",
    "opus": "claude-opus-4-7",
}
DEFAULT_LLM_MODEL = "sonnet"

def get_oauth_token() -> Optional[str]:
    """~/.claude/.credentials.json에서 OAuth accessToken 추출"""
    if not CREDENTIALS_PATH.exists():
        return None
    try:
        data = json.loads(CREDENTIALS_PATH.read_text(encoding="utf-8"))
        return data.get("claudeAiOauth", {}).get("accessToken") or data.get("accessToken")
    except Exception:
        return None

def call_claude(system: str, user: str, model_alias: str = DEFAULT_LLM_MODEL,
                max_tokens: int = 8000) -> str:
    """Claude API 직접 호출 (OAuth 토큰, urllib 사용 = 의존성 X)"""
    token = get_oauth_token()
    if not token:
        raise RuntimeError("Claude OAuth 토큰 없음. 'claude login' 실행 필요.")
    model_id = CLAUDE_MODELS.get(model_alias, CLAUDE_MODELS[DEFAULT_LLM_MODEL])
    body = json.dumps({
        "model": model_id,
        "max_tokens": max_tokens,
        "system": system,
        "messages": [{"role": "user", "content": user}],
    }).encode("utf-8")
    req = urllib.request.Request(
        "https://api.anthropic.com/v1/messages",
        data=body,
        headers={
            "Authorization": f"Bearer {token}",
            "anthropic-version": "2023-06-01",
            "anthropic-beta": "oauth-2025-04-20",
            "content-type": "application/json",
        },
        method="POST",
    )
    try:
        with urllib.request.urlopen(req, timeout=300) as res:
            data = json.loads(res.read().decode("utf-8"))
    except urllib.error.HTTPError as e:
        err_body = e.read().decode("utf-8", errors="replace")
        raise RuntimeError(f"Claude API HTTP {e.code}: {err_body[:300]}")
    # content = [{"type": "text", "text": "..."}]
    parts = data.get("content", [])
    text_parts = [p.get("text", "") for p in parts if p.get("type") == "text"]
    return "\n".join(text_parts)


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


class SummarizeRequest(BaseModel):
    transcript: str
    scenario: str = "meeting"  # meeting | lecture | interview | ideation | memo | free
    model: str = DEFAULT_LLM_MODEL  # haiku | sonnet | opus
    title: Optional[str] = None
    attendees: Optional[str] = None
    tag: Optional[str] = None
    date: Optional[str] = None


app = FastAPI(title="AI PRONOTE 프로토타입")
app.mount("/static", StaticFiles(directory=STATIC_DIR), name="static")


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


@app.get("/")
def index():
    return FileResponse(STATIC_DIR / "index.html")


@app.get("/api/health")
def health():
    return {
        "status": "ok",
        "default_model": DEFAULT_MODEL,
        "device": DEVICE,
        "loaded_models": list(_model_cache.keys()),
        "allowed_models": list(ALLOWED_MODELS),
    }


@app.get("/api/auth/config")
def auth_config():
    """클라이언트 사이드 Supabase 인증용 설정 응답 (anon key = 브라우저 노출 OK)"""
    # OAuth provider 활성화 = AI PRONOTE Supabase Dashboard에서 = Google/Kakao/Apple 등록 후 = true로 변경
    # 활성화 단계: (1) Google Cloud `interbuilder` 프로젝트 → 새 OAuth Client (= AI PRONOTE)
    #             (2) Authorized redirect = https://pddasonkizwviwqzdhpu.supabase.co/auth/v1/callback
    #             (3) Supabase Dashboard → Authentication → Providers → Google → Enable + Client ID/Secret
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
    """Claude OAuth 토큰 상태 (사용자 = 인증됐는지)"""
    token = get_oauth_token()
    return {
        "authenticated": token is not None,
        "credentials_path": str(CREDENTIALS_PATH),
        "credentials_exists": CREDENTIALS_PATH.exists(),
        "models": list(CLAUDE_MODELS.keys()),
        "default_model": DEFAULT_LLM_MODEL,
        "scenarios": list(SCENARIO_PROMPTS.keys()),
    }


@app.post("/api/llm/summarize")
def llm_summarize(req: SummarizeRequest):
    """transcript → 시나리오별 회의록 자동 정리 (Claude OAuth)"""
    if not req.transcript or not req.transcript.strip():
        raise HTTPException(400, "transcript 비어있음")
    if req.scenario not in SCENARIO_PROMPTS:
        raise HTTPException(400, f"scenario X = {list(SCENARIO_PROMPTS.keys())}")

    system = SCENARIO_PROMPTS[req.scenario]
    # 메타 정보 추가 (있으면)
    meta_lines = []
    if req.title: meta_lines.append(f"제목: {req.title}")
    if req.attendees: meta_lines.append(f"참석자: {req.attendees}")
    if req.tag: meta_lines.append(f"종류: {req.tag}")
    if req.date: meta_lines.append(f"날짜: {req.date}")
    meta_block = "\n".join(meta_lines) if meta_lines else ""
    user = f"""다음은 받아쓰기로 변환된 회의·강의·대화 텍스트입니다.

[메타 정보]
{meta_block if meta_block else '(메타 없음)'}

[받아쓰기 본문]
{req.transcript}

위 텍스트를 system prompt 형식대로 한국어로 정리해주세요."""

    t0 = time.time()
    try:
        text = call_claude(system, user, model_alias=req.model)
    except Exception as e:
        raise HTTPException(500, f"Claude 호출 실패: {e}")
    elapsed = round(time.time() - t0, 1)
    return {
        "scenario": req.scenario,
        "model": req.model,
        "model_id": CLAUDE_MODELS.get(req.model),
        "elapsed_sec": elapsed,
        "summary": text,
        "char_count": len(text),
    }


@app.post("/api/transcribe")
async def transcribe(
    file: UploadFile = File(...),
    language: str = Form("ko"),
    model: str = Form(DEFAULT_MODEL),
):
    """음성 파일 받아쓰기 (모델 선택 가능: small | medium 등)"""
    if not file.filename:
        raise HTTPException(400, "파일 이름이 없습니다")

    # 파일 저장
    job_id = uuid.uuid4().hex[:12]
    suffix = Path(file.filename).suffix.lower() or ".bin"
    upload_path = UPLOAD_DIR / f"{job_id}{suffix}"
    contents = await file.read()
    upload_path.write_bytes(contents)
    size_mb = round(len(contents) / 1024 / 1024, 1)
    print(f"[AI PRONOTE] 업로드: {file.filename} ({size_mb} MB) → {upload_path.name} · 모델 {model}")

    # 받아쓰기 (모델별 캐시 + Batched + beam_size=1)
    try:
        m = get_model(model)
        t_start = time.time()
        segments_iter, info = m.transcribe(
            str(upload_path),
            language=language,
            beam_size=1,
            batch_size=8,
            vad_filter=True,
            vad_parameters=dict(min_silence_duration_ms=500),
        )
        segments = []
        full_text_parts = []
        for seg in segments_iter:
            segments.append({
                "id": seg.id,
                "start": round(seg.start, 2),
                "end": round(seg.end, 2),
                "text": seg.text.strip(),
            })
            full_text_parts.append(seg.text.strip())
        elapsed = round(time.time() - t_start, 1)

        result = {
            "job_id": job_id,
            "filename": file.filename,
            "size_mb": size_mb,
            "language": info.language,
            "duration": round(info.duration, 1),
            "elapsed_sec": elapsed,
            "model": model,
            "full_text": "\n".join(full_text_parts),
            "segments": segments,
        }

        # 결과 저장 (JSON + TXT)
        import json
        (RESULT_DIR / f"{job_id}.json").write_text(
            json.dumps(result, ensure_ascii=False, indent=2), encoding="utf-8"
        )
        (RESULT_DIR / f"{job_id}.txt").write_text(
            "\n".join(full_text_parts), encoding="utf-8"
        )

        print(f"[AI PRONOTE] 완료: {file.filename} · {info.duration}초 음성 → {elapsed}초 처리")
        return JSONResponse(result)

    except Exception as e:
        print(f"[AI PRONOTE] 에러: {e}")
        raise HTTPException(500, f"받아쓰기 실패: {e}")


if __name__ == "__main__":
    import uvicorn
    print("[AI PRONOTE] 서버 시작: http://localhost:8765")
    uvicorn.run(app, host="127.0.0.1", port=8765, log_level="info")
