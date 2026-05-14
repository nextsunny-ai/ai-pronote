"""
whisper.cpp 1.8.4 BLAS 직접 호출 (wait 제거)
"""
import json, time, subprocess, sys
from pathlib import Path
from datetime import datetime

ROOT = Path(__file__).parent
WHISPER_CLI = ROOT / "whisper_cpp" / "Release" / "whisper-cli.exe"
MODEL = Path(r"C:\Users\nexts\AppData\Roaming\com.meetily.ai\models\ggml-large-v3-turbo.bin")
WAV = ROOT / "results" / "04-24_temp.wav"
OUT_BASE = ROOT / "results" / "04-24_whispercpp_turbo"

print(f"[whisper.cpp] 시작 = {datetime.now().isoformat()}", flush=True)
print(f"[whisper.cpp] CLI = {WHISPER_CLI}", flush=True)
print(f"[whisper.cpp] 모델 = {MODEL.name} ({MODEL.stat().st_size / 1024 / 1024:.0f} MB)", flush=True)
print(f"[whisper.cpp] WAV = {WAV.name} ({WAV.stat().st_size / 1024 / 1024:.0f} MB)", flush=True)

t = time.time()
proc = subprocess.run([
    str(WHISPER_CLI),
    "-m", str(MODEL),
    "-f", str(WAV),
    "-l", "ko",
    "-t", "8",
    "-bs", "1",
    "-otxt",
    "-oj",
    "-of", str(OUT_BASE),
    "--print-progress",
], capture_output=True, text=True, encoding="utf-8", errors="replace")
elapsed = time.time() - t

print(f"[whisper.cpp] return code = {proc.returncode}", flush=True)
print(f"[whisper.cpp] 시간 = {elapsed:.1f}초 ({elapsed/60:.1f}분)", flush=True)
if proc.stderr:
    print(f"[whisper.cpp] stderr (first 1000 chars):\n{proc.stderr[:1000]}", flush=True)
if proc.stdout:
    print(f"[whisper.cpp] stdout (first 500 chars):\n{proc.stdout[:500]}", flush=True)

if proc.returncode != 0:
    sys.exit(1)

# 결과 read + 메타
txt_path = OUT_BASE.with_suffix(".txt")
text = txt_path.read_text(encoding="utf-8") if txt_path.exists() else ""
duration_sec = 4456.8

result = {
    "tool": "whisper.cpp 1.8.4 BLAS · CPU · ggml-large-v3-turbo (Meetily 동일 모델)",
    "model": "large-v3-turbo (ggml)",
    "duration_sec": duration_sec,
    "duration_label": "1h 14m 16s",
    "transcribe_time_sec": round(elapsed, 1),
    "transcribe_time_label": f"{int(elapsed//3600)}h {int(elapsed%3600//60)}m {int(elapsed%60)}s",
    "ratio": round(elapsed / duration_sec, 3),
    "started_at": datetime.now().isoformat(),
    "full_text": text,
    "char_count": len(text),
}
json_path = OUT_BASE.with_suffix(".json")
json_path.write_text(json.dumps(result, ensure_ascii=False, indent=2), encoding="utf-8")
print(f"[whisper.cpp] 완료 = {datetime.now().isoformat()}", flush=True)
print(f"[whisper.cpp] 처리 = {result['transcribe_time_label']} (비율 {result['ratio']}배)", flush=True)
print(f"[whisper.cpp] 텍스트 = {len(text)}자", flush=True)
print(f"[whisper.cpp] 첫 200자: {text[:200]}", flush=True)
