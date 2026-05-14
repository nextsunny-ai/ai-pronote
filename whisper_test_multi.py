"""
AI PRONOTE — Whisper 4모델 비교 (CPU 최적화)
  - tiny (75 MB)
  - small (466 MB)
  - medium (514 MB) — 이미 완료된 것 = SKIP
  - large-v3-turbo (1.5 GB)

각 모델 = 04-24 회의 mp3 (1시간 14분) → JSON·TXT 저장 + 시간 측정
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

MP3 = Path(r"C:\Users\nexts\Desktop\NOTEMAKER\04-24_주간_회의_스폰서십_종류_및_티켓_판매_전략.mp3")

# medium = 이미 완료 = SKIP
MODELS = [
    ("tiny", "tiny"),
    ("small", "small"),
    ("large-v3-turbo", "large-v3-turbo"),
]

print(f"[MULTI] 시작 = {datetime.now().isoformat()}")
print(f"[MULTI] 파일 = {MP3.name} ({MP3.stat().st_size / 1024 / 1024:.1f} MB)")
print(f"[MULTI] 모델 = {[m[0] for m in MODELS]}\n")

results_summary = []

for label, size in MODELS:
    out_json = RESULT_DIR / f"04-24_whisper_{label}.json"
    out_txt = RESULT_DIR / f"04-24_whisper_{label}.txt"
    if out_json.exists():
        print(f"[{label}] 이미 결과 있음 — SKIP")
        continue

    print(f"\n=== [{label}] 시작 ===")
    print(f"[{label}] 모델 로드 = {size} · CPU · int8 · cpu_threads=8 ...")
    t0 = time.time()
    try:
        m = WhisperModel(size, device="cpu", compute_type="int8", cpu_threads=8, num_workers=1)
        bm = BatchedInferencePipeline(model=m)
        load_time = time.time() - t0
        print(f"[{label}] 모델 로드 = {load_time:.1f}초")
    except Exception as e:
        print(f"[{label}] 모델 로드 실패 = {e}")
        results_summary.append({"label": label, "error": str(e)})
        continue

    print(f"[{label}] 받아쓰기 시작 ...")
    t1 = time.time()
    try:
        seg_iter, info = bm.transcribe(
            str(MP3), language="ko",
            beam_size=1, batch_size=8,
            vad_filter=True,
            vad_parameters=dict(min_silence_duration_ms=500),
        )
        segments, full_text = [], []
        last_log = time.time()
        for seg in seg_iter:
            segments.append({
                "id": seg.id, "start": round(seg.start, 2), "end": round(seg.end, 2),
                "text": seg.text.strip(),
            })
            full_text.append(seg.text.strip())
            now = time.time()
            if now - last_log > 30:
                pct = round(seg.end / info.duration * 100, 1)
                em = (now - t1) / 60
                print(f"[{label}] {pct}% · 경과 {em:.1f}분")
                last_log = now
        elapsed = time.time() - t1
        text_full = "\n".join(full_text)

        result = {
            "tool": f"faster-whisper {size} · CPU · int8 · beam_size=1 · batched",
            "model": size,
            "filename": MP3.name,
            "size_mb": round(MP3.stat().st_size / 1024 / 1024, 2),
            "duration_sec": round(info.duration, 1),
            "duration_label": f"{int(info.duration//3600)}h {int(info.duration%3600//60)}m {int(info.duration%60)}s",
            "language": info.language,
            "load_time_sec": round(load_time, 1),
            "transcribe_time_sec": round(elapsed, 1),
            "transcribe_time_label": f"{int(elapsed//3600)}h {int(elapsed%3600//60)}m {int(elapsed%60)}s",
            "ratio": round(elapsed / info.duration, 3),
            "started_at": datetime.now().isoformat(),
            "full_text": text_full,
            "segments": segments,
            "segment_count": len(segments),
            "char_count": len(text_full),
        }
        out_json.write_text(json.dumps(result, ensure_ascii=False, indent=2), encoding="utf-8")
        out_txt.write_text(text_full, encoding="utf-8")
        print(f"[{label}] 완료 · 음성 {result['duration_label']} → 처리 {result['transcribe_time_label']} (비율 {result['ratio']}배) · 세그먼트 {len(segments)}개 · {len(text_full)}자")
        results_summary.append({
            "label": label, "model": size,
            "transcribe_time_sec": round(elapsed, 1),
            "transcribe_time_label": result['transcribe_time_label'],
            "ratio": round(elapsed / info.duration, 3),
            "segments": len(segments),
            "chars": len(text_full),
        })
    except Exception as e:
        print(f"[{label}] 받아쓰기 실패 = {e}")
        results_summary.append({"label": label, "error": str(e)})
    finally:
        # 메모리 해제
        del m, bm
        try:
            import gc
            gc.collect()
        except Exception:
            pass

# 최종 요약
summary_path = RESULT_DIR / "04-24_whisper_multi_summary.json"
summary_path.write_text(json.dumps({
    "completed_at": datetime.now().isoformat(),
    "results": results_summary,
}, ensure_ascii=False, indent=2), encoding="utf-8")
print(f"\n[MULTI] 모든 모델 완료 = {datetime.now().isoformat()}")
print(f"[MULTI] 요약 = {summary_path}")
for r in results_summary:
    print(f"  - {r}")
