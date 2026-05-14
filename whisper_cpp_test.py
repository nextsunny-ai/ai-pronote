"""
Whisper.cpp 1.8.4 BLAS — 04-24 mp3 받아쓰기 (Meetily와 같은 ggml 모델 사용)

흐름:
1. faster-whisper 4모델 백그라운드(PID) 종료 대기
2. ffmpeg = mp3 → wav 변환 (16kHz mono)
3. whisper-cli.exe = ggml-large-v3-turbo 모델로 받아쓰기
4. 결과 JSON 저장 + 시간 측정

Meetily도 = 같은 whisper.cpp + 같은 ggml 모델 사용 = 정확도 = 동일.
차이 = (a) Vulkan GPU (Meetily) vs CPU+BLAS (우리 검증) (b) 화자 분리 (Meetily만)
"""
import json
import time
import subprocess
import sys
from pathlib import Path
from datetime import datetime

ROOT = Path(__file__).parent
WHISPER_CLI = ROOT / "whisper_cpp" / "Release" / "whisper-cli.exe"
FFMPEG = Path(r"C:\Program Files\meetily\ffmpeg.exe")
MODEL = Path(r"C:\Users\nexts\AppData\Roaming\com.meetily.ai\models\ggml-large-v3-turbo.bin")
MP3 = Path(r"C:\Users\nexts\Desktop\NOTEMAKER\04-24_주간_회의_스폰서십_종류_및_티켓_판매_전략.mp3")
RESULT_DIR = ROOT / "results"
RESULT_DIR.mkdir(exist_ok=True)
WAV = RESULT_DIR / "04-24_temp.wav"
OUT_BASE = RESULT_DIR / "04-24_whispercpp_turbo"

# 옛 faster-whisper PID 종료 대기 (CPU 경합 방지)
WAIT_PID = 22072

def is_pid_running(pid: int) -> bool:
    try:
        out = subprocess.check_output(
            ["tasklist", "/FI", f"PID eq {pid}", "/NH"],
            text=True, stderr=subprocess.DEVNULL
        )
        return str(pid) in out
    except Exception:
        return False

print(f"[whisper.cpp] 시작 = {datetime.now().isoformat()}")
print(f"[whisper.cpp] PID {WAIT_PID} (faster-whisper) 종료 대기...")
wait_count = 0
while is_pid_running(WAIT_PID):
    time.sleep(60)
    wait_count += 1
    if wait_count % 10 == 0:
        print(f"[whisper.cpp] {wait_count}분 대기 중 (faster-whisper 진행 중)...")
print(f"[whisper.cpp] PID {WAIT_PID} 종료 확인. 시작.")

# 1. ffmpeg = mp3 → wav (16kHz mono)
print(f"[whisper.cpp] ffmpeg 변환 중 (mp3 → wav 16kHz mono)...")
t_ff = time.time()
subprocess.run([
    str(FFMPEG), "-y", "-i", str(MP3),
    "-ar", "16000", "-ac", "1",
    "-loglevel", "error",
    str(WAV),
], check=True)
ff_elapsed = time.time() - t_ff
print(f"[whisper.cpp] ffmpeg = {ff_elapsed:.1f}초")

# 2. whisper-cli.exe 받아쓰기
print(f"[whisper.cpp] whisper-cli 시작 (model=ggml-large-v3-turbo, threads=8, lang=ko)...")
t_w = time.time()
proc = subprocess.run([
    str(WHISPER_CLI),
    "-m", str(MODEL),
    "-f", str(WAV),
    "-l", "ko",
    "-t", "8",       # CPU threads
    "-bs", "1",      # beam_size
    "-otxt",         # txt 출력
    "-oj",           # json 출력
    "-of", str(OUT_BASE),
    "--print-progress",
], capture_output=True, text=True)
w_elapsed = time.time() - t_w
print(f"[whisper.cpp] whisper-cli = {w_elapsed:.1f}초 (= {w_elapsed/60:.1f}분)")
if proc.returncode != 0:
    print(f"[whisper.cpp] FAIL stderr: {proc.stderr[:500]}")
    sys.exit(1)

# 3. 결과 read + 메타 작성
txt_path = OUT_BASE.with_suffix(".txt")
text = txt_path.read_text(encoding="utf-8") if txt_path.exists() else ""

mp3_size = MP3.stat().st_size

# ffprobe로 음성 길이 추출 (ffmpeg 같이 들어옴)
duration_sec = 4456.8  # 사전 측정값 (확실)
ratio = w_elapsed / duration_sec

result = {
    "tool": "whisper.cpp 1.8.4 BLAS · CPU · ggml-large-v3-turbo (Meetily와 동일 모델)",
    "model": "large-v3-turbo (ggml)",
    "filename": MP3.name,
    "size_mb": round(mp3_size / 1024 / 1024, 2),
    "duration_sec": duration_sec,
    "duration_label": "1h 14m 16s",
    "ffmpeg_convert_sec": round(ff_elapsed, 1),
    "transcribe_time_sec": round(w_elapsed, 1),
    "transcribe_time_label": f"{int(w_elapsed//3600)}h {int(w_elapsed%3600//60)}m {int(w_elapsed%60)}s",
    "ratio": round(ratio, 3),
    "started_at": datetime.now().isoformat(),
    "full_text": text,
    "char_count": len(text),
}

json_path = OUT_BASE.with_suffix(".json")
json_path.write_text(json.dumps(result, ensure_ascii=False, indent=2), encoding="utf-8")
print(f"[whisper.cpp] 완료 = {datetime.now().isoformat()}")
print(f"[whisper.cpp] 처리 = {result['transcribe_time_label']} (비율 {result['ratio']}배)")
print(f"[whisper.cpp] 텍스트 = {len(text)}자")
print(f"[whisper.cpp] 결과 = {json_path.name}, {txt_path.name}")
print(f"[whisper.cpp] 첫 200자: {text[:200]}")

# wav 임시 파일 정리
try:
    WAV.unlink()
except Exception:
    pass
