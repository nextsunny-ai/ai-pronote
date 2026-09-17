"""
AI PRONOTE — 화자 분리 (speaker diarization)  ★ V1.3 신규
faster-whisper 받아쓰기 segments + pyannote.audio = 화자별 라벨링.

회의록이 "화자 1: ... / 화자 2: ..." 형태로 정리되어 = 누가 무슨 말을 했는지 구분.

──────────────────────────────────────────────────────────────────
★ 사용 전 준비 (대표님 1회만 — 그 후 자동)
──────────────────────────────────────────────────────────────────
  1. HuggingFace 계정 생성 = https://huggingface.co/join
  2. 액세스 토큰 발급 = https://huggingface.co/settings/tokens
       → "New token" → Type: Read → 토큰 복사 (hf_ 로 시작)
  3. 모델 약관 동의 (각 페이지에서 "Agree and access repository" 클릭만):
       - https://huggingface.co/pyannote/speaker-diarization-3.1
       - https://huggingface.co/pyannote/segmentation-3.0
  4. .env.local 에 한 줄 추가:
       HF_TOKEN=hf_여기에토큰
  5. 의존성 설치 (1회, torch 포함 ≈ 2GB):
       pip install pyannote.audio

HF_TOKEN 또는 pyannote 가 없으면 = 화자 분리는 자동으로 건너뜀.
(받아쓰기·회의록 정리는 영향 없이 정상 동작)
──────────────────────────────────────────────────────────────────
"""
import os
from typing import List, Dict, Tuple

_pipeline = None  # pyannote Pipeline 캐시 (최초 1회 로드 후 재사용)


def diarization_available() -> Tuple[bool, str]:
    """화자 분리 사용 가능 여부 + 사유 문자열."""
    if not os.environ.get("HF_TOKEN"):
        return False, "HF_TOKEN 미설정 (.env.local 에 추가 필요)"
    try:
        import pyannote.audio  # noqa: F401
    except ImportError:
        return False, "pyannote.audio 미설치 (pip install pyannote.audio)"
    return True, "ok"


def _get_pipeline():
    """pyannote 화자 분리 파이프라인 (캐시). GPU 있으면 자동 사용."""
    global _pipeline
    if _pipeline is None:
        from pyannote.audio import Pipeline
        import torch
        token = os.environ.get("HF_TOKEN")
        try:
            _pipeline = Pipeline.from_pretrained(
                "pyannote/speaker-diarization-3.1", token=token,
            )
        except TypeError:
            # 옛 pyannote(3.x) = use_auth_token 인자
            _pipeline = Pipeline.from_pretrained(
                "pyannote/speaker-diarization-3.1", use_auth_token=token,
            )
        if torch.cuda.is_available():
            _pipeline.to(torch.device("cuda"))
    return _pipeline


def _load_waveform(audio_path: str) -> Dict:
    """오디오 파일 → pyannote 입력 dict {waveform, sample_rate}.

    pyannote 4.x 내장 디코딩(torchcodec)은 Windows에서 FFmpeg DLL이 없으면 실패.
    PyAV(faster-whisper 의존성으로 이미 설치됨)로 직접 16kHz mono 디코딩.
    """
    import av
    import numpy as np
    import torch

    container = av.open(audio_path)
    stream = container.streams.audio[0]
    resampler = av.AudioResampler(format="flt", layout="mono", rate=16000)
    chunks = []
    for frame in container.decode(stream):
        for f in resampler.resample(frame):
            chunks.append(f.to_ndarray())
    container.close()
    if not chunks:
        raise RuntimeError(f"오디오 디코딩 실패 (빈 스트림): {audio_path}")
    wave = np.concatenate(chunks, axis=1).astype(np.float32)
    return {"waveform": torch.from_numpy(wave), "sample_rate": 16000}


def diarize_audio(audio_path: str) -> List[Dict]:
    """오디오 파일 → 화자 발화 구간 리스트 [{start, end, speaker}]."""
    pipeline = _get_pipeline()
    annotation = pipeline(_load_waveform(audio_path))
    # pyannote 4.x = DiarizeOutput 래퍼 반환 → 내부 Annotation 추출 (3.x = Annotation 그대로)
    annotation = getattr(annotation, "speaker_diarization", annotation)
    turns: List[Dict] = []
    for turn, _, speaker in annotation.itertracks(yield_label=True):
        turns.append({
            "start": round(turn.start, 2),
            "end": round(turn.end, 2),
            "speaker": speaker,  # 예: SPEAKER_00
        })
    return turns


def assign_speakers(segments: List[Dict], turns: List[Dict]) -> List[Dict]:
    """whisper segment 각각에 = 시간상 가장 많이 겹치는 화자 라벨을 부여.

    pyannote 화자 코드(SPEAKER_00 …)는 등장 순서대로 '화자 1·화자 2…' 로 한글화.
    """
    if not turns:
        return segments

    label_map: Dict[str, str] = {}

    def label(code: str) -> str:
        if code not in label_map:
            label_map[code] = f"화자 {len(label_map) + 1}"
        return label_map[code]

    out: List[Dict] = []
    for seg in segments:
        s, e = seg["start"], seg["end"]
        best_speaker, best_overlap = None, 0.0
        for t in turns:
            overlap = min(e, t["end"]) - max(s, t["start"])
            if overlap > best_overlap:
                best_overlap, best_speaker = overlap, t["speaker"]
        new_seg = dict(seg)
        new_seg["speaker"] = label(best_speaker) if best_speaker else "화자 ?"
        out.append(new_seg)
    return out


def speaker_transcript(segments: List[Dict]) -> str:
    """화자 라벨이 붙은 segments → '화자 1: ...' 형식의 받아쓰기 텍스트.

    같은 화자가 연속으로 말한 구간은 한 줄로 합침.
    """
    lines: List[str] = []
    cur_speaker = None
    buf: List[str] = []

    def flush():
        if buf:
            lines.append(f"{cur_speaker}: {' '.join(buf)}")

    for seg in segments:
        sp = seg.get("speaker", "화자 ?")
        text = seg.get("text", "").strip()
        if not text:
            continue
        if sp != cur_speaker:
            flush()
            cur_speaker, buf = sp, [text]
        else:
            buf.append(text)
    flush()
    return "\n".join(lines)
