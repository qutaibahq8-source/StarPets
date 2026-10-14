#!/usr/bin/env python3
"""Draw the map the server actually builds, so it can be LOOKED AT.

Every previous round of "the map looks the same" was answered by describing
what had been written, which is worth nothing to somebody staring at their
screen. Running the real builder and painting what comes out is worth
something: if the picture does not change, the work did not land.

Top-down, painter's algorithm — lowest parts first, so what you see is what you
would see standing above the map. Flat colour, no lighting, because the point
is what is THERE rather than how it is lit.

    python3 tools/render_map.py out.png
"""
import sys
from pathlib import Path

try:
    from PIL import Image, ImageDraw
except ImportError:
    sys.exit("pillow is not installed (pip install pillow)")

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "tools"))
import check_map  # noqa: E402

WIDTH = 1700
PAD = 40


def main():
    dest = Path(sys.argv[1]) if len(sys.argv) > 1 else ROOT / "build/map.png"
    label = sys.argv[2] if len(sys.argv) > 2 else ""

    lua, mock, cfg = check_map.build()
    parts = []
    for p in check_map.parts_of(mock):
        pr = p._p
        pos, size = p["Position"], pr.Size
        col = pr.Color
        if col is None:
            continue
        parts.append((
            float(pos.X), float(pos.Y), float(pos.Z),
            float(size.X), float(size.Y), float(size.Z),
            (round(float(col.R) * 255), round(float(col.G) * 255),
             round(float(col.B) * 255)),
            float(pr.Transparency or 0),
        ))
    if not parts:
        sys.exit("nothing was built")

    xs0 = min(p[0] - p[3] / 2 for p in parts)
    xs1 = max(p[0] + p[3] / 2 for p in parts)
    zs0 = min(p[2] - p[5] / 2 for p in parts)
    zs1 = max(p[2] + p[5] / 2 for p in parts)
    span_x, span_z = xs1 - xs0, zs1 - zs0
    scale = (WIDTH - PAD * 2) / span_x
    height = int(span_z * scale) + PAD * 2 + 46

    img = Image.new("RGB", (WIDTH, height), (18, 18, 24))
    d = ImageDraw.Draw(img)

    def to_px(x, z):
        return (PAD + (x - xs0) * scale, PAD + (z - zs0) * scale)

    # Lowest first: a tree crown must land on top of the ground, not under it.
    parts.sort(key=lambda p: p[1] - p[4] / 2)
    for x, y, z, sx, sy, sz, col, tr in parts:
        if tr >= 0.95:
            continue
        x0, z0 = to_px(x - sx / 2, z - sz / 2)
        x1, z1 = to_px(x + sx / 2, z + sz / 2)
        if x1 - x0 < 1:
            x1 = x0 + 1
        if z1 - z0 < 1:
            z1 = z0 + 1
        d.rectangle([x0, z0, x1, z1], fill=col)

    cap = "%s  -  %d parts" % (label or "StarPets map", len(parts))
    d.rectangle([0, height - 40, WIDTH, height], fill=(12, 12, 16))
    d.text((PAD, height - 28), cap, fill=(228, 228, 236))

    dest.parent.mkdir(parents=True, exist_ok=True)
    img.save(dest)
    print("wrote %s (%dx%d, %d parts)" % (dest, WIDTH, height, len(parts)))
    return 0


if __name__ == "__main__":
    sys.exit(main())
