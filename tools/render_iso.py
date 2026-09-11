#!/usr/bin/env python3
"""Draw the map in 3D, from a player's angle, so it can be judged.

A top-down diagram answers "is the thing there". It cannot answer "does this
look good", which is the only question that matters when somebody says the game
looks bad — and being shown a floor plan when you asked what your game looks
like is worse than being shown nothing.

So: isometric projection, painter's algorithm, three shaded faces per box.
Not a screenshot, and it ignores Roblox's lighting entirely, but it shows
shape, height, colour and crowding — which is where every map problem in this
project has actually lived.

    python3 tools/render_iso.py out.png            whole map
    python3 tools/render_iso.py out.png Meadow     one world, close up
"""
import math
import sys
from pathlib import Path

try:
    from PIL import Image, ImageDraw
except ImportError:
    sys.exit("pillow is not installed (pip install pillow)")

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "tools"))
import check_map  # noqa: E402

WIDTH, HEIGHT = 1500, 860
COS30, SIN30 = math.cos(math.radians(30)), math.sin(math.radians(30))

# Faces are lit by which way they point, not by any light in the game. Top
# brightest, then the two visible sides — enough separation that a cube reads as
# a cube instead of a flat hexagon.
TOP, LEFT, RIGHT = 1.0, 0.72, 0.52


def shade(col, f):
    return tuple(max(0, min(255, int(c * f))) for c in col)


def project(x, y, z):
    return ((x - z) * COS30, (x + z) * SIN30 - y)


# The perimeter walls and the locked-world gates are 36-stud dark slabs. They
# are doing a job in the game — you are not meant to walk out of the map, and a
# gate is meant to look shut — but in a review render they stand between the
# camera and everything worth looking at, and paint over it.
SKIP_PREFIXES = ("Wall", "Barrier_", "BStripe")


def collect(mock):
    """Every part as an axis-aligned box in world space, plus its colour."""
    out = []
    for p in check_map.parts_of(mock):
        pr = p._p
        if str(pr.Name).startswith(SKIP_PREFIXES):
            continue
        pos, size, col = p["Position"], pr.Size, pr.Color
        if col is None or size is None:
            continue
        if float(pr.Transparency or 0) >= 0.9:
            continue
        sx, sy, sz = float(size.X), float(size.Y), float(size.Z)

        shape = str(pr.Shape) if pr.Shape is not None else "Block"
        if shape.endswith("Cylinder"):
            # A Roblox cylinder runs along its LOCAL X. column() stands one up
            # with Orientation (0,0,90), which swaps X and Y in world terms —
            # so a "height" of size.X becomes the vertical extent. Drawing it
            # as authored would lay every tree trunk and pillar on its side.
            o = pr.Orientation
            roll = abs(float(o.Z)) if o is not None else 0.0
            if 45 < (roll % 180) < 135:
                sx, sy = sy, sx
        out.append((
            float(pos.X), float(pos.Y), float(pos.Z), sx, sy, sz,
            (round(float(col.R) * 255), round(float(col.G) * 255),
             round(float(col.B) * 255)),
            "ball" if shape.endswith("Ball") else "box",
        ))
    return out


def main():
    dest = Path(sys.argv[1]) if len(sys.argv) > 1 else ROOT / "build/iso.png"
    world = sys.argv[2] if len(sys.argv) > 2 else None

    lua, mock, cfg = check_map.build()
    boxes = collect(mock)
    if not boxes:
        sys.exit("nothing was built")

    label = "whole map"
    if world:
        ws = mock["workspace"]
        cx = 0.0
        for p in check_map.parts_of(mock):
            if str(p._p.Name) == "Biome_" + world:
                cx = float(p["Position"].X)
                break
        # OVERLAP, not centre. Filtering by a part's centre drops anything
        # large that merely passes through the region — and the first thing
        # that kills is the ground, an 820-stud slab whose centre is nowhere
        # near any single world. The render came out with the plaza and its
        # trees floating on empty sky.
        # CLIP to the region rather than select by centre.
        #
        # Selecting by centre drops the ground — an 820-stud slab whose centre
        # is nowhere near any one world — and the plaza came out floating on
        # empty sky. But merely INCLUDING it is just as wrong: an 820-wide box
        # swallows the framing, and the painter's sort orders by centre, so a
        # slab centred far to the east draws last and paints over the entire
        # world standing on it.
        #
        # Clipping gives a slab the size of the view, which frames correctly
        # and sorts correctly.
        half = 78
        lo, hi = cx - half, cx + half
        clipped = []
        for x, y, z, sx, sy, sz, col, shape in boxes:
            x0, x1 = x - sx / 2, x + sx / 2
            if x1 < lo or x0 > hi:
                continue
            if shape == "box":
                x0, x1 = max(x0, lo), min(x1, hi)
                x, sx = (x0 + x1) / 2, max(x1 - x0, 0.05)
            elif not (lo <= x <= hi):
                continue
            clipped.append((x, y, z, sx, sy, sz, col, shape))
        boxes = clipped
        if not boxes:
            sys.exit("no world called %r" % world)
        label = world
    else:
        # The whole map end to end is very wide; drop the outer walls so the
        # islands themselves get the pixels.
        pass

    pts = []
    for x, y, z, sx, sy, sz, _, _ in boxes:
        for dx in (-sx / 2, sx / 2):
            for dy in (-sy / 2, sy / 2):
                for dz in (-sz / 2, sz / 2):
                    pts.append(project(x + dx, y + dy, z + dz))
    minx = min(p[0] for p in pts); maxx = max(p[0] for p in pts)
    miny = min(p[1] for p in pts); maxy = max(p[1] for p in pts)
    pad = 30
    scale = min((WIDTH - pad * 2) / (maxx - minx),
                (HEIGHT - pad * 2 - 34) / (maxy - miny))

    def to_px(x, y, z):
        u, v = project(x, y, z)
        return ((u - minx) * scale + pad, (v - miny) * scale + pad)

    img = Image.new("RGB", (WIDTH, HEIGHT), (150, 186, 214))
    d = ImageDraw.Draw(img)

    # Painter's algorithm, sorted on each box's FARTHEST corner rather than its
    # centre.
    #
    # Centre-based depth is fine for props of similar size and completely wrong
    # for a ground slab: 300 studs deep, its centre sits further toward the
    # camera than the spawn plaza standing on top of it, so the ground drew
    # last and painted over the plaza, the egg terrace and the paths. The first
    # render of this showed a field with no spawn in it.
    #
    # The far corner is (x - sx/2) + (z - sz/2) + (y - sy/2): the point of the
    # box furthest from the viewer. Big flat things sort early, which is what
    # ground is.
    boxes.sort(key=lambda b: (b[0] - b[3] / 2) + (b[2] - b[5] / 2)
               + (b[1] - b[4] / 2))

    for x, y, z, sx, sy, sz, col, shape in boxes:
        hx, hy, hz = sx / 2, sy / 2, sz / 2
        if shape == "ball":
            # An ellipse through the projected extremes. Cheaper than a sphere
            # and reads correctly at this size, which is what tree crowns and
            # boulders need.
            cxp, cyp = to_px(x, y, z)
            wpx = (sx + sz) * 0.5 * COS30 * scale
            hpx = (sy * 0.5 + (sx + sz) * 0.25 * SIN30) * scale
            d.ellipse([cxp - wpx, cyp - hpx, cxp + wpx, cyp + hpx],
                      fill=shade(col, 0.88))
            continue
        top = [to_px(x - hx, y + hy, z - hz), to_px(x + hx, y + hy, z - hz),
               to_px(x + hx, y + hy, z + hz), to_px(x - hx, y + hy, z + hz)]
        left = [to_px(x - hx, y + hy, z + hz), to_px(x + hx, y + hy, z + hz),
                to_px(x + hx, y - hy, z + hz), to_px(x - hx, y - hy, z + hz)]
        right = [to_px(x + hx, y + hy, z - hz), to_px(x + hx, y + hy, z + hz),
                 to_px(x + hx, y - hy, z + hz), to_px(x + hx, y - hy, z - hz)]
        d.polygon(left, fill=shade(col, LEFT))
        d.polygon(right, fill=shade(col, RIGHT))
        d.polygon(top, fill=shade(col, TOP))

    cap = "StarPets - %s - %d parts in view" % (label, len(boxes))
    d.rectangle([0, HEIGHT - 30, WIDTH, HEIGHT], fill=(12, 12, 16))
    d.text((14, HEIGHT - 20), cap, fill=(228, 228, 236))

    dest.parent.mkdir(parents=True, exist_ok=True)
    img.save(dest)
    print("wrote %s (%d parts)" % (dest, len(boxes)))
    return 0


if __name__ == "__main__":
    sys.exit(main())
