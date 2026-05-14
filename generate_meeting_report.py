"""
04-24 transcript → Claude Sonnet → 회의록 자동 생성 (시연용)
"""
import json
import urllib.request
from pathlib import Path

ROOT = Path(__file__).parent

# whisper.cpp turbo (가장 정확) transcript 사용
TRANSCRIPT_PATH = ROOT / "results" / "04-24_whispercpp_turbo.txt"
text = TRANSCRIPT_PATH.read_text(encoding="utf-8")
# whisper-cli output = "[00:00:00.000 --> 00:00:02.680]   본문" 형식. 본문만 추출.
import re
clean_lines = []
for line in text.splitlines():
    m = re.match(r"\[\d{2}:\d{2}:\d{2}\.\d{3} --> \d{2}:\d{2}:\d{2}\.\d{3}\]\s*(.*)", line)
    if m:
        clean_lines.append(m.group(1).strip())
    else:
        # 형식 다른 줄 = 그대로 보존
        if line.strip():
            clean_lines.append(line.strip())
clean_text = "\n".join(clean_lines)
print(f"[gen] transcript = {len(clean_text)}자, {len(clean_lines)}줄")

# /api/llm/summarize 호출
import sys
model_alias = sys.argv[1] if len(sys.argv) > 1 else "haiku"
body = json.dumps({
    "transcript": clean_text,
    "scenario": "meeting",
    "model": model_alias,
    "title": "04-24 주간 회의 — 스폰서십 종류 및 티켓 판매 전략",
    "attendees": "유희정, Speaker 2, Speaker 3, Speaker 4 (PLAUD 화자 분리 결과)",
    "tag": "주간 · 내부",
    "date": "2026-04-24",
}, ensure_ascii=False).encode("utf-8")

print(f"[gen] Claude Sonnet 호출 중... (transcript {len(clean_text)}자 = 약 {len(clean_text)//1000}k tokens)")
import time
t0 = time.time()
req = urllib.request.Request(
    "http://localhost:8765/api/llm/summarize",
    data=body,
    headers={"content-type": "application/json"},
    method="POST",
)
try:
    with urllib.request.urlopen(req, timeout=300) as res:
        data = json.loads(res.read().decode("utf-8"))
except urllib.error.HTTPError as e:
    err = e.read().decode("utf-8", errors="replace")
    print(f"[gen] FAIL HTTP {e.code}: {err[:500]}")
    exit(1)
elapsed = time.time() - t0
print(f"[gen] Claude 응답 = {elapsed:.1f}초, {data.get('char_count')}자")

# 회의록 MD로 저장
out_md = ROOT / "results" / "04-24_meeting_report.md"
header = f"""# 04-24 주간 회의 — Claude Sonnet 자동 생성 회의록

> **소스**: `04-24_whispercpp_turbo.txt` ({len(clean_text)}자)
> **모델**: {data.get('model')} → {data.get('model_id')}
> **시나리오**: {data.get('scenario')}
> **처리 시간**: {data.get('elapsed_sec')}초
> **생성 일시**: {time.strftime('%Y-%m-%d %H:%M:%S')}

---

"""
out_md.write_text(header + data["summary"], encoding="utf-8")
print(f"[gen] 저장 = {out_md}")
print(f"\n========== 회의록 본문 ==========\n")
print(data["summary"])
