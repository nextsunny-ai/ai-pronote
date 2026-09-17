"""Pure P0 helpers shared by the server and regression tests."""
from dataclasses import asdict, dataclass
from enum import Enum
from pathlib import Path
from typing import Optional
import time

APP_VERSION = "v1.5.0-p0"
ALLOWED_AUDIO_EXTENSIONS = {".mp3", ".wav", ".m4a", ".webm", ".ogg", ".flac", ".mp4"}
MAX_UPLOAD_BYTES = 512 * 1024 * 1024

class LaunchDecision(str, Enum):
    REUSE = "reuse"
    START = "start"
    CONFLICT = "conflict"

def select_launch_action(port_healthy: bool, running_version: Optional[str], expected_version: str) -> LaunchDecision:
    if not port_healthy:
        return LaunchDecision.START
    return LaunchDecision.REUSE if running_version == expected_version else LaunchDecision.CONFLICT

def safe_data_root(path: Path) -> Path:
    root = path.expanduser().resolve()
    for child in ("uploads", "results", "logs"):
        (root / child).mkdir(parents=True, exist_ok=True)
    return root

def allowed_upload(filename: str, size_bytes: int) -> tuple[bool, str]:
    if size_bytes <= 0:
        return False, "빈 파일은 업로드할 수 없습니다."
    if size_bytes > MAX_UPLOAD_BYTES:
        return False, "파일이 너무 큽니다. 최대 512MB까지 지원합니다."
    if Path(filename or "").suffix.lower() not in ALLOWED_AUDIO_EXTENSIONS:
        names = ", ".join(sorted(x.lstrip(".").upper() for x in ALLOWED_AUDIO_EXTENSIONS))
        return False, f"지원 형식이 아닙니다. 지원: {names}"
    return True, ""

def estimate_remaining_seconds(progress: int, elapsed_seconds: float) -> Optional[int]:
    progress = max(0, min(int(progress or 0), 100))
    if progress == 0:
        return None
    if progress >= 100:
        return 0
    return max(0, round(float(elapsed_seconds) * (100 - progress) / progress))

@dataclass(frozen=True)
class JobQueueView:
    job_id: str
    stage: str
    label: str
    progress: int
    eta_seconds: Optional[int]
    error: str
    can_retry: bool

    @classmethod
    def from_job(cls, job: dict) -> "JobQueueView":
        status = job.get("status") or "queued"
        summary = job.get("summary_status") or "none"
        if status in ("error", "interrupted") or summary == "error": stage = "failed"
        elif status == "queued": stage = "queued"
        elif status != "done": stage = "transcribing"
        elif summary in ("pending", "running"): stage = "summarizing"
        else: stage = "done"
        progress = int(job.get("progress") or 0)
        elapsed = float(job.get("processing_elapsed_sec") or job.get("elapsed_sec") or 0)
        if stage == "transcribing" and not elapsed and job.get("started_at"):
            elapsed = max(0.0, time.time() - float(job["started_at"]))
        return cls(str(job.get("job_id") or ""), stage, str(job.get("phase") or stage), progress,
                   estimate_remaining_seconds(progress, elapsed) if stage == "transcribing" else None,
                   str(job.get("error") or job.get("summary_error") or ""),
                   stage == "failed" and bool(job.get("has_audio")))

    def as_dict(self) -> dict:
        return asdict(self)
