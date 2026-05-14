#!/usr/bin/env python3
"""
AI PRONOTE — Drive 자동 처리 워커 (= 24/7 PM2 가동)
대표님 아이디어 (2026-05-14) = 모바일·iPad 어디서나 = Drive에 녹음 업로드 = 맥미니가 자동 정리

흐름:
1. Drive `AI_PRONOTE/inbox/` 폴더 = 30초마다 새 음성 파일 감지
2. 발견 = main.py /api/transcribe + /api/llm/summarize 호출 (= 비용 0)
3. 결과 = Drive `AI_PRONOTE/results/{YYYY-MM-DD}_{원본명}/` 저장:
   - 회의록.md (= Claude 정리)
   - 받아쓰기_full.txt
   - 받아쓰기_segments.json
4. 원본 음성 = `AI_PRONOTE/inbox/.processed/` 이동 (= 중복 처리 차단)
5. 텔레그램 한국어 알림 발송

설정 = .env.local:
  PRONOTE_DRIVE_ROOT=...
  PRONOTE_API=http://127.0.0.1:8765
  PRONOTE_SCENARIO=meeting   (= meeting/lecture/interview/ideation/memo/free)
  PRONOTE_MODEL=sonnet       (= haiku/sonnet/opus)
  PRONOTE_WHISPER=medium     (= small/medium)
  TELEGRAM_BEARER=sunny-worker-2026
  TELEGRAM_CHAT_ID=8019272482
"""
import os
import sys
import json
import time
import shutil
import urllib.request
from pathlib import Path
from datetime import datetime

# ─────────────────────────────────────────────────
# 설정
# ─────────────────────────────────────────────────
HOME = Path.home()
DEFAULT_DRIVE_ROOT = HOME / "Library/CloudStorage/GoogleDrive-nextsunny@gmail.com/내 드라이브/SUNNY_TEAM/AI_PRONOTE"

DRIVE_ROOT = Path(os.environ.get("PRONOTE_DRIVE_ROOT", str(DEFAULT_DRIVE_ROOT)))
INBOX_DIR = DRIVE_ROOT / "inbox"
RESULTS_DIR = DRIVE_ROOT / "results"
PROCESSED_DIR = INBOX_DIR / ".processed"

API_BASE = os.environ.get("PRONOTE_API", "http://127.0.0.1:8765")
SCENARIO = os.environ.get("PRONOTE_SCENARIO", "meeting")
MODEL = os.environ.get("PRONOTE_MODEL", "sonnet")
WHISPER_MODEL = os.environ.get("PRONOTE_WHISPER", "medium")

TELEGRAM_BEARER = os.environ.get("TELEGRAM_BEARER", "sunny-worker-2026")
TELEGRAM_CHAT_ID = int(os.environ.get("TELEGRAM_CHAT_ID", "8019272482"))
NOTIFY_URL = "http://158.179.166.111:8000/api/notify"

AUDIO_EXTS = {".mp3", ".wav", ".m4a", ".webm", ".ogg", ".flac", ".aac", ".mp4"}
POLL_INTERVAL = int(os.environ.get("PRONOTE_POLL_INTERVAL", "30"))

# ─────────────────────────────────────────────────
# 폴더 준비
# ─────────────────────────────────────────────────
INBOX_DIR.mkdir(parents=True, exist_ok=True)
RESULTS_DIR.mkdir(parents=True, exist_ok=True)
PROCESSED_DIR.mkdir(parents=True, exist_ok=True)


def telegram_notify(text: str):
    """텔레그램 한국어 알림 (= /api/notify)"""
    try:
        req = urllib.request.Request(
            NOTIFY_URL,
            data=json.dumps({"text": text, "chat_id": TELEGRAM_CHAT_ID}).encode("utf-8"),
            headers={
                "Authorization": f"Bearer {TELEGRAM_BEARER}",
                "Content-Type": "application/json",
            },
            method="POST",
        )
        with urllib.request.urlopen(req, timeout=10) as res:
            data = json.loads(res.read().decode("utf-8"))
            return data.get("ok", False)
    except Exception as e:
        print(f"[ALERT FAIL] {e}", flush=True)
        return False


def api_post_form(path: str, files: dict, data: dict = None):
    """multipart/form-data POST (= /api/transcribe 호출)"""
    import requests
    r = requests.post(f"{API_BASE}{path}", files=files, data=data or {}, timeout=3600)
    r.raise_for_status()
    return r.json()


def api_post_json(path: str, body: dict):
    """JSON POST (= /api/llm/summarize 호출)"""
    req = urllib.request.Request(
        f"{API_BASE}{path}",
        data=json.dumps(body).encode("utf-8"),
        headers={"Content-Type": "application/json"},
        method="POST",
    )
    with urllib.request.urlopen(req, timeout=600) as res:
        return json.loads(res.read().decode("utf-8"))


def process_audio(audio_path: Path):
    """음성 파일 1개 처리 = 받아쓰기 + 회의록 정리 + 저장"""
    started = datetime.now()
    name = audio_path.name
    base = audio_path.stem
    size_mb = round(audio_path.stat().st_size / 1024 / 1024, 1)

    print(f"\n[{started.strftime('%H:%M:%S')}] 처리 시작: {name} ({size_mb} MB)", flush=True)
    telegram_notify(f"★ AI 프로 노트 = 회의 자료 감지\n파일: {name} ({size_mb} MB)\n처리 시작 (= 받아쓰기 → AI 정리)")

    # 1) 받아쓰기 (= /api/transcribe)
    try:
        with audio_path.open("rb") as f:
            tx = api_post_form(
                "/api/transcribe",
                files={"file": (name, f, "audio/*")},
                data={"language": "ko", "model": WHISPER_MODEL},
            )
        transcript = tx.get("full_text", "")
        duration_min = round(tx.get("duration", 0) / 60, 1)
        elapsed_min = round(tx.get("elapsed_sec", 0) / 60, 1)
        print(f"  ✅ 받아쓰기 = {duration_min}분 음성 → {elapsed_min}분 처리", flush=True)
    except Exception as e:
        print(f"  ❌ 받아쓰기 실패: {e}", flush=True)
        telegram_notify(f"★ AI 프로 노트 에러 (받아쓰기 실패): {name}\n{str(e)[:300]}")
        return False

    # 2) AI 회의록 정리 (= /api/llm/summarize)
    try:
        summary = api_post_json(
            "/api/llm/summarize",
            {
                "transcript": transcript,
                "scenario": SCENARIO,
                "model": MODEL,
                "title": base,
                "date": started.strftime("%Y-%m-%d %H:%M"),
            },
        )
        summary_text = summary.get("summary", "")
        ai_elapsed = round(summary.get("elapsed_sec", 0), 1)
        print(f"  ✅ AI 정리 = {ai_elapsed}초", flush=True)
    except Exception as e:
        print(f"  ❌ AI 정리 실패: {e}", flush=True)
        # 받아쓰기는 성공했으니 = 그래도 저장
        summary_text = f"# AI 정리 실패\n\n{str(e)}\n\n원본 받아쓰기 = 받아쓰기_full.txt 참조."
        ai_elapsed = 0

    # 3) Drive 결과 폴더 저장
    date_prefix = started.strftime("%Y-%m-%d_%H%M")
    out_dir = RESULTS_DIR / f"{date_prefix}_{base}"
    out_dir.mkdir(parents=True, exist_ok=True)

    (out_dir / "회의록.md").write_text(summary_text, encoding="utf-8")
    (out_dir / "받아쓰기_full.txt").write_text(transcript, encoding="utf-8")
    (out_dir / "받아쓰기_segments.json").write_text(
        json.dumps(tx.get("segments", []), ensure_ascii=False, indent=2), encoding="utf-8"
    )
    (out_dir / "메타.json").write_text(
        json.dumps({
            "name": name, "size_mb": size_mb,
            "duration_min": duration_min, "transcribe_elapsed_min": elapsed_min,
            "ai_elapsed_sec": ai_elapsed, "scenario": SCENARIO, "model": MODEL,
            "whisper_model": WHISPER_MODEL, "started_at": started.isoformat(),
        }, ensure_ascii=False, indent=2), encoding="utf-8"
    )

    # 4) 원본 음성 = .processed/ 이동 (= 중복 처리 차단)
    target = PROCESSED_DIR / name
    if target.exists():
        target = PROCESSED_DIR / f"{base}_{started.strftime('%H%M%S')}{audio_path.suffix}"
    shutil.move(str(audio_path), str(target))

    # 5) 텔레그램 한국어 알림 = 완료
    drive_path_short = str(out_dir).replace(str(HOME), "~")
    telegram_notify(
        f"★ AI 프로 노트 = 회의록 완료\n"
        f"파일: {name}\n"
        f"음성: {duration_min}분 → 받아쓰기 {elapsed_min}분 + AI {ai_elapsed}초\n"
        f"위치: Drive/SUNNY_TEAM/AI_PRONOTE/results/{out_dir.name}/\n\n"
        f"회의록.md + 받아쓰기_full.txt + 메타.json 다 박힘"
    )
    print(f"  ✅ 결과 저장: {out_dir}", flush=True)
    return True


def main():
    print("=" * 60, flush=True)
    print(f"AI PRONOTE Drive Watcher 시작 (= 24/7)", flush=True)
    print(f"  inbox  : {INBOX_DIR}", flush=True)
    print(f"  results: {RESULTS_DIR}", flush=True)
    print(f"  API    : {API_BASE}", flush=True)
    print(f"  시나리오: {SCENARIO} · 모델: {MODEL} · Whisper: {WHISPER_MODEL}", flush=True)
    print(f"  폴링   : {POLL_INTERVAL}초", flush=True)
    print("=" * 60, flush=True)

    while True:
        try:
            # 새 음성 파일 감지 (= .processed/·.tmp 제외)
            audio_files = sorted([
                p for p in INBOX_DIR.iterdir()
                if p.is_file()
                and p.suffix.lower() in AUDIO_EXTS
                and not p.name.startswith(".")
                and ".tmp" not in p.name.lower()
            ])
            for audio in audio_files:
                # Drive sync 도중 = 파일 크기 변하면 = 1 cycle 더 대기
                size1 = audio.stat().st_size
                time.sleep(2)
                size2 = audio.stat().st_size
                if size1 != size2:
                    print(f"  ⏳ sync 중 = 대기: {audio.name}", flush=True)
                    continue
                process_audio(audio)
        except KeyboardInterrupt:
            print("\n  종료", flush=True)
            break
        except Exception as e:
            print(f"  ⚠ loop 에러: {e}", flush=True)
        time.sleep(POLL_INTERVAL)


if __name__ == "__main__":
    main()
