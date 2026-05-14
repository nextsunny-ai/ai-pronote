"""PWA용 다양 사이즈 아이콘 생성 (옛 디자인)"""
from PIL import Image, ImageDraw
from pathlib import Path

ROOT = Path(__file__).parent
OUT_DIR = ROOT / "static" / "icons"
OUT_DIR.mkdir(parents=True, exist_ok=True)

def draw_icon(size: int) -> Image.Image:
    """옛 시안 디자인 = 검은 둥근 사각형 + 흰 노트 + 갈색 마이크 동그라미 + 흰 +"""
    img = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    # 검은 배경 둥근 사각형
    pad = int(size * 0.04)
    radius = int(size * 0.18)
    d.rounded_rectangle([pad, pad, size - pad, size - pad], radius=radius, fill=(26, 26, 26))
    # 흰 노트
    npx, npy = int(size * 0.16), int(size * 0.20)
    nrx, nry = int(size * 0.70), int(size * 0.74)
    nrad = int(size * 0.10)
    d.rounded_rectangle([npx, npy, nrx, nry], radius=nrad, fill=(250, 250, 247))
    # 노트 줄 3개
    line_color = (26, 26, 26)
    line_w = max(2, int(size * 0.014))
    # 첫째 줄
    d.line([(int(size * 0.22), int(size * 0.32)), (int(size * 0.62), int(size * 0.32))], fill=line_color, width=line_w)
    d.line([(int(size * 0.22), int(size * 0.43)), (int(size * 0.62), int(size * 0.43))], fill=line_color, width=line_w)
    d.line([(int(size * 0.22), int(size * 0.54)), (int(size * 0.50), int(size * 0.54))], fill=line_color, width=line_w)
    # 갈색 마이크 동그라미 (오른쪽 위)
    cx, cy = int(size * 0.78), int(size * 0.30)
    cr = int(size * 0.13)
    d.ellipse([cx - cr, cy - cr, cx + cr, cy + cr], fill=(160, 130, 109))
    # 흰 +
    d.line([(cx - cr * 0.5, cy), (cx + cr * 0.5, cy)], fill=(250, 250, 247), width=max(2, int(size * 0.018)))
    d.line([(cx, cy - cr * 0.5), (cx, cy + cr * 0.5)], fill=(250, 250, 247), width=max(2, int(size * 0.018)))
    return img

# PWA 표준 사이즈
SIZES = [72, 96, 128, 144, 152, 192, 256, 384, 512]
for s in SIZES:
    img = draw_icon(s)
    out = OUT_DIR / f"icon-{s}.png"
    img.save(out, format="PNG")
    print(f"[OK] {out.name} ({s}x{s})")

# Apple touch icon = 180
img180 = draw_icon(180)
img180.save(OUT_DIR / "apple-touch-icon.png", format="PNG")
print(f"[OK] apple-touch-icon.png (180x180)")

# Maskable (safe-zone 80%)
def draw_maskable(size: int) -> Image.Image:
    """maskable = 80% safe zone에 디자인 + 외부 = 같은 검정"""
    img = Image.new("RGBA", (size, size), (26, 26, 26, 255))
    d = ImageDraw.Draw(img)
    inner = int(size * 0.8)
    pad = (size - inner) // 2
    inner_img = draw_icon(inner)
    img.paste(inner_img, (pad, pad), inner_img)
    return img

img_maskable = draw_maskable(512)
img_maskable.save(OUT_DIR / "icon-maskable-512.png", format="PNG")
print(f"[OK] icon-maskable-512.png")

print(f"\n총 {len(SIZES) + 2}개 아이콘 = {OUT_DIR}")
