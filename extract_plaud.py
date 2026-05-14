"""PLAUD docx → 텍스트 추출 (Whisper와 비교용)"""
from docx import Document
from pathlib import Path

NOTEMAKER = Path(r"C:\Users\nexts\Desktop\NOTEMAKER")
OUT = Path(r"C:\AI_PRONOTE_proto\results")
OUT.mkdir(exist_ok=True)

files = {
    "transcript": "04-24_주간_회의_스폰서십_종류_및_티켓_판매_전략-transcript.docx",
    "summary": "04-24_주간_회의_스폰서십_종류_및_티켓_판매_전략-요약.docx",
    "highlight": "04-24_주간_회의_스폰서십_종류_및_티켓_판매_전략-하이라이트.docx",
}

for kind, fname in files.items():
    src = NOTEMAKER / fname
    if not src.exists():
        print(f"[SKIP] {fname} 없음")
        continue
    doc = Document(str(src))
    paras = [p.text for p in doc.paragraphs if p.text.strip()]
    text = "\n".join(paras)
    out_path = OUT / f"04-24_plaud_{kind}.txt"
    out_path.write_text(text, encoding="utf-8")
    print(f"[OK] {kind}: {len(paras)} paragraphs · {len(text)} chars · → {out_path.name}")
    print(f"     첫 200자: {text[:200]}")
    print()
