# -*- coding: utf-8 -*-
"""
받아쓰기 후처리 필터 (AI PRONOTE)
────────────────────────────────────────────────────────────────
근거 = 2026-07-14 실제 회의 녹음 테스트에서 드러난 3대 약점.
faster-whisper(medium)가 실제 회의의 조용한 구간에서 만들어낸 문제를
"본문은 100% 보존"하는 보수적 규칙으로만 정리한다.

1) 유튜브 자막투 환각  — "이 영상은 ~입니다" 등 회의에서 나올 수 없는 문장
2) 무한 반복          — "한 번에 한 번에 한 번에 …" 같은 토큰 루프
3) initial_prompt 누출 — 힌트 문장이 받아쓰기에 새어나오는 현상(기존 로직 이관)

설계 원칙 = 실제 발화를 지우면 안 된다. 명백한 환각·반복만 제거하고,
애매하면 남긴다(false-positive 최소화).
"""
from __future__ import annotations
import re

# ── 1. initial_prompt 누출 (기존 main.py 로직 이관, 하위호환 유지) ────────
KOREAN_INITIAL_PROMPT = "다음은 한국어 회의 녹음입니다. 존댓말과 구어체가 섞여 있습니다."
_HALLUCINATION_KEY = "한국어회의녹음"


def _alnum(s: str) -> str:
    return "".join(ch for ch in (s or "") if ch.isalnum())


def is_prompt_leak(text: str) -> bool:
    """initial_prompt 문장이 그대로 누출된 세그먼트인지."""
    norm = _alnum(text)
    if len(norm) < 6:
        return False
    prompt_norm = _alnum(KOREAN_INITIAL_PROMPT)
    return norm in prompt_norm or prompt_norm in norm


def scrub_prompt_hallucination(text: str) -> str:
    """initial_prompt 변형 환청("이 영상은 한국어 회의 녹음입니다" 등) 문장 제거."""
    if _HALLUCINATION_KEY not in (text or "").replace(" ", ""):
        return text
    parts = re.split(r"(?<=[.!?])\s+", text)
    kept = [p for p in parts if _HALLUCINATION_KEY not in p.replace(" ", "")]
    return " ".join(kept).strip()


# ── 2. 유튜브 자막투 환각 상용구 ────────────────────────────────────────
# faster-whisper 한국어가 무음/배경음 구간에서 학습데이터(유튜브 자막)를
# 그대로 뱉는 전형적 문장들. 실제 회의 발화와 겹치지 않는 것만 보수적으로 등록.
_HALLUCINATION_PATTERNS = [
    r"^\s*이\s*영상은\b.*$",                       # "이 영상은 ~입니다/제작되었습니다/있습니다"
    r"시청\s*해?\s*주셔서\s*감사",                  # "시청해 주셔서 감사합니다"
    r"구독\s*(과|,|및|하고)?\s*좋아요",             # "구독과 좋아요"
    r"다음\s*(영상|시간|편)에서?\s*(뵙|만나)",       # "다음 영상에서 만나요"
    r"^\s*(한글|영어|한국어)?\s*자막\s*(제공|by|:).*$",
    r"^\s*번역\s*[:：].*$",
    r"(MBC|KBS|SBS|YTN)\s*뉴스\s*[가-힣]{0,4}\s*입니다",
    r"^\s*채널\s*(구독|알림).*$",
]
_HALLU_RE = [re.compile(p) for p in _HALLUCINATION_PATTERNS]


def is_youtube_hallucination(text: str) -> bool:
    """유튜브 자막투 환각 문장인지 (회의에 나올 수 없는 것만)."""
    t = (text or "").strip()
    if not t:
        return False
    return any(rx.search(t) for rx in _HALLU_RE)


# ── 3. 무한 반복 축약 ───────────────────────────────────────────────────
def collapse_repetitions(text: str, max_run: int = 4) -> str:
    """같은 어절 구(주기 1~5)가 max_run회 이상 연속 반복되면 1회로 축약.

    "한 번에 한 번에 한 번에 …"(20회+) → "한 번에".
    강조성 3회 반복("진짜 진짜 진짜")은 max_run=4 미만이라 보존.
    """
    words = (text or "").split()
    n = len(words)
    if n < max_run:
        return text
    out: list[str] = []
    i = 0
    while i < n:
        collapsed = False
        for p in range(1, 6):                       # 반복 단위 길이(어절 수)
            if i + p * 2 > n:
                continue
            unit = words[i:i + p]
            reps = 1
            while words[i + reps * p: i + (reps + 1) * p] == unit:
                reps += 1
            if reps >= max_run:
                out.extend(unit)                    # 한 번만 유지
                i += reps * p
                collapsed = True
                break
        if not collapsed:
            out.append(words[i])
            i += 1
    return " ".join(out)


# ── 통합 파이프라인 ─────────────────────────────────────────────────────
def clean_segment(text: str) -> str | None:
    """세그먼트 1개 후처리. 통째로 버릴 환각이면 None 반환."""
    st = (text or "").strip()
    if not st:
        return None
    if is_prompt_leak(st):
        return None
    if is_youtube_hallucination(st):
        return None
    st = scrub_prompt_hallucination(st)
    if not st.strip():
        return None
    st = collapse_repetitions(st)
    return st.strip() or None


def clean_full_text(text: str) -> str:
    """완성된 전체 텍스트(줄바꿈 구분)에 후처리 일괄 적용. 재받아쓰기 없이도 정리."""
    lines = (text or "").splitlines()
    kept = []
    for ln in lines:
        c = clean_segment(ln)
        if c:
            kept.append(c)
    return "\n".join(kept)


# ── 4. 고유명사 hotwords (누출 없는 정확도 힌트) ─────────────────────────
# faster-whisper hotwords = initial_prompt와 달리 받아쓰기 결과로 누출되지 않음.
# 회사 도메인 고유명사를 등록해 오인식(맘스터치→"맘서치" 등)을 줄인다.
KOREAN_HOTWORDS = (
    "써니엔터테인먼트 넥스트아트 굿즈모먼트 버치사운드 "
    "타이토 뮤지엄 스페이스인베이더 버블버블 시티커넥션 "
    "조선요괴전 화산귀환 전지적독자시점 롯데월드 맘스터치 "
    "팝업스토어 굿즈 스토리텔링 일러스트 미디어아트 디오라마 "
    "디즈니플러스 웹툰 캐스팅 콜라보 예약특전 유료전시 XR"
)
