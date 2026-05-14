"""
AI PRONOTE 아이콘 생성 (옛 시안 SVG 디자인 → .ico)
검은 배경 + 흰 노트 + 갈색 마이크 원
"""
from PIL import Image, ImageDraw
from pathlib import Path

ROOT = Path(__file__).parent
SIZES = [16, 32, 48, 64, 128, 256]

# 색상 (옛 시안)
BG_COLOR = (26, 26, 26, 255)          # #1A1A1A 검정
NOTE_COLOR = (250, 250, 247, 235)     # #FAFAF7 약간 투명
LINE_COLOR = (26, 26, 26, 255)        # 검정 줄
MIC_COLOR = (160, 130, 109, 255)      # #A0826D 갈색
MIC_PLUS_COLOR = (250, 250, 247, 255) # 흰

def render(size: int) -> Image.Image:
    s = size
    img = Image.new("RGBA", (s, s), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)

    # 둥근 검은 배경 사각형
    margin = max(1, s // 32)
    radius = max(2, s // 8)
    d.rounded_rectangle(
        [margin, margin, s - margin, s - margin],
        radius=radius,
        fill=BG_COLOR,
    )

    # 노트 (흰 사각형)
    # 옛 SVG: x=8 y=12 width=40 height=44 (64 viewBox 기준)
    nx0 = int(s * 8 / 64)
    ny0 = int(s * 12 / 64)
    nx1 = int(s * (8 + 40) / 64)
    ny1 = int(s * (12 + 44) / 64)
    note_radius = max(1, int(s * 6 / 64))
    d.rounded_rectangle([nx0, ny0, nx1, ny1], radius=note_radius, fill=NOTE_COLOR)

    # 노트 줄 3개 (검정 가로줄)
    line_width = max(1, int(s * 2 / 64))
    for ry in [24, 32, 40]:
        y = int(s * ry / 64)
        x0 = int(s * 16 / 64)
        # 마지막 줄은 짧게 (옛 SVG 디자인)
        x1 = int(s * (38 if ry < 40 else 30) / 64)
        d.line([x0, y, x1, y], fill=LINE_COLOR, width=line_width)

    # 마이크 원 (갈색)
    cx = int(s * 50 / 64)
    cy = int(s * 20 / 64)
    cr = int(s * 8 / 64)
    d.ellipse([cx - cr, cy - cr, cx + cr, cy + cr], fill=MIC_COLOR)

    # 플러스 (흰)
    plus_w = max(1, int(s * 1.6 / 64))
    d.line([cx - cr + 4 * s // 64, cy, cx + cr - 4 * s // 64, cy], fill=MIC_PLUS_COLOR, width=plus_w)
    d.line([cx, cy - cr + 4 * s // 64, cx, cy + cr - 4 * s // 64], fill=MIC_PLUS_COLOR, width=plus_w)

    return img

# 다중 사이즈 ICO 생성
images = [render(s) for s in SIZES]
biggest = images[-1]
ico_path = ROOT / "icon.ico"
biggest.save(
    ico_path,
    format="ICO",
    sizes=[(s, s) for s in SIZES],
)
print(f"[OK] {ico_path} ({ico_path.stat().st_size} bytes)")

# PNG도 같이 저장 (디버깅·다른 용도)
png_path = ROOT / "icon_256.png"
images[-1].save(png_path, format="PNG")
print(f"[OK] {png_path}")
