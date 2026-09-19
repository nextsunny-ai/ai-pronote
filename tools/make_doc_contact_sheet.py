from pathlib import Path
import sys

from PIL import Image, ImageDraw


source = Path(sys.argv[1])
output = Path(sys.argv[2])
pages = sorted(source.glob("page-*.png"), key=lambda p: int(p.stem.split("-")[-1]))
thumb_width = 420
gap = 24
label_height = 34
columns = 3
thumbs = []
for page in pages:
    image = Image.open(page).convert("RGB")
    height = round(image.height * thumb_width / image.width)
    thumbs.append((page, image.resize((thumb_width, height))))
cell_height = max(image.height for _, image in thumbs) + label_height
rows = (len(thumbs) + columns - 1) // columns
sheet = Image.new("RGB", (columns * thumb_width + (columns + 1) * gap, rows * cell_height + (rows + 1) * gap), "#DADADA")
draw = ImageDraw.Draw(sheet)
for index, (page, image) in enumerate(thumbs):
    row, column = divmod(index, columns)
    x = gap + column * (thumb_width + gap)
    y = gap + row * cell_height
    sheet.paste(image, (x, y + label_height))
    draw.text((x, y + 7), page.stem, fill="#111111")
output.parent.mkdir(parents=True, exist_ok=True)
sheet.save(output, quality=92)
