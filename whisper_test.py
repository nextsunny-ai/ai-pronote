"""
AI PRONOTE — Whisper 받아쓰기 단독 테스트
04-24 회의 mp3 → faster-whisper medium → 결과 JSON
CPU 최적화 (beam_size=1, cpu_threads=8, BatchedInferencePipeline)
"""
import json
import time
import sys
from pathlib import Path
from datetime import datetime

from faster_whisper import WhisperModel, BatchedInferencePipeline

ROOT = Path(__file__).parent
RESULT_DIR = ROOT / "results"
RESULT_DIR.mkdir(exist_ok=True)

MP3_PATH = Path(r"C:\Users\nexts\Desktop\NOTEMAKER\04-24_주간_회의_스폰서십_종류_및_티켓_판매_전략.mp3")
OUTPUT_BASE = RESULT_DIR / "04-24_whisper"

print(f"[Whisper] 시작 = {datetime.now().isoformat()}")
print(f"[Whisper] 파일 = {MP3_PATH.name} ({MP3_PATH.stat().st_size / 1024 / 1024:.1f} MB)")

# 모델 로드
print(f"[Whisper] 모델 로드 = medium · CPU · int8 · cpu_threads=8 ...")
t0 = time.time()
model = WhisperModel(
    "medium",
    device="cpu",
    compute_type="int8",
    cpu_threads=8,
    num_workers=1,
)
batched_model = BatchedInferencePipeline(model=model)
load_time = time.time() - t0
print(f"[Whisper] 모델 로드 완료 = {load_time:.1f}초")

# 받아쓰기
print(f"[Whisper] 받아쓰기 시작 (beam_size=1, batch_size=8, language=ko, vad_filter=True)...")
t1 = time.time()
segments_iter, info = batched_model.transcribe(
    str(MP3_PATH),
    language="ko",
    beam_size=1,
    batch_size=8,
    vad_filter=True,
    vad_parameters=dict(min_silence_duration_ms=500),
)

segments = []
full_text_parts = []
last_log = time.time()
for seg in segments_iter:
    segments.append({
        "id": seg.id,
        "start": round(seg.start, 2),
        "end": round(seg.end, 2),
        "text": seg.text.strip(),
    })
    full_text_parts.append(seg.text.strip())
    # 진행 로그 (10초 간격)
    now = time.time()
    if now - last_log > 10:
        elapsed_min = (now - t1) / 60
        progress = round(seg.end / info.duration * 100, 1)
        print(f"[Whisper] 진행: {progress}% (음성 {seg.end:.0f}s / {info.duration:.0f}s) · 경과 {elapsed_min:.1f}분")
        last_log = now

elapsed = time.time() - t1

result = {
    "tool": "faster-whisper 1.2.1 (CPU·int8·medium·beam_size=1·batched)",
    "filename": MP3_PATH.name,
    "size_mb": round(MP3_PATH.stat().st_size / 1024 / 1024, 2),
    "duration_sec": round(info.duration, 1),
    "duration_label": f"{int(info.duration//3600)}h {int(info.duration%3600//60)}m {int(info.duration%60)}s",
    "language": info.language,
    "load_time_sec": round(load_time, 1),
    "transcribe_time_sec": round(elapsed, 1),
    "transcribe_time_label": f"{int(elapsed//3600)}h {int(elapsed%3600//60)}m {int(elapsed%60)}s",
    "ratio": round(elapsed / info.duration, 2),  # 처리시간 / 음성길이
    "started_at": datetime.now().isoformat(),
    "full_text": "\n".join(full_text_parts),
    "segments": segments,
    "segment_count": len(segments),
}

# 결과 저장
json_path = OUTPUT_BASE.with_suffix(".json")
txt_path = OUTPUT_BASE.with_suffix(".txt")
json_path.write_text(json.dumps(result, ensure_ascii=False, indent=2), encoding="utf-8")
txt_path.write_text("\n".join(full_text_parts), encoding="utf-8")

print(f"[Whisper] 완료 = {datetime.now().isoformat()}")
print(f"[Whisper] 음성 {result['duration_label']} → 처리 {result['transcribe_time_label']} (비율 {result['ratio']}배)")
print(f"[Whisper] 세그먼트 = {len(segments)}개")
print(f"[Whisper] 결과 = {json_path.name}, {txt_path.name}")
print(f"[Whisper] 첫 200자: {result['full_text'][:200]}")
