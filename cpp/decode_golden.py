import glob, os
import zxingcpp
from PIL import Image

SCALE, QUIET = 12, 4
for path in sorted(glob.glob(os.path.join("tests", "golden", "*.txt"))):
    rows = []
    for line in open(path):
        line = line.strip()
        if line.startswith(("TEXT", "SIZE")):
            continue
        if line == "END":
            break
        rows.append(line)
    h, w = len(rows), len(rows[0])
    img = Image.new("L", ((w + 2 * QUIET) * SCALE, (h + 2 * QUIET) * SCALE), 255)
    px = img.load()
    for y, row in enumerate(rows):
        for x, c in enumerate(row):
            if c == "#":
                for dy in range(SCALE):
                    for dx in range(SCALE):
                        px[(x + QUIET) * SCALE + dx, (y + QUIET) * SCALE + dy] = 0
    res = zxingcpp.read_barcodes(img, formats=zxingcpp.BarcodeFormat.DataMatrix)
    text = res[0].text if res else "NO DECODE"
    print(f"{os.path.basename(path):24} {w}x{h:<3} -> {text}")
