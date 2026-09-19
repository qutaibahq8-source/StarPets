#!/usr/bin/env python3
"""Draw a place that was described to us, rather than one we built ourselves.

render_iso.py renders the map THIS CODE builds. That is the wrong thing to look
at when the question is "why does my game look like that", because a place with
a baked map keeps its own copy and the server never rebuilds over it. The two
can differ by everything.

This reads a description of the real place — the one actually open in Studio,
sent over by the plugin — and draws it with the same projection. So the answer
to "what does it look like" stops depending on someone taking a screenshot.

    python3 tools/render_place.py place.json out.png [World]

The JSON is what StarPetsSync's "Send to Claude" button produces:

    {"parts": [[name, x,y,z, sx,sy,sz, r,g,b, shapeCode, transparency], ...],
     "text": "the snapshot report"}

A flat array per part rather than an object: a map is well over a thousand
parts and the key names would be most of the payload.
"""
import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "tools"))
import render_iso  # noqa: E402

# Same as the renderer's own: gates and perimeter walls are 36-stud slabs that
# stand between the camera and everything worth seeing.
SKIP_PREFIXES = ("Wall", "Barrier_", "BStripe")


def boxes_from(doc, world=None, keep_walls=False):
    out = []
    for row in doc.get("parts", []):
        try:
            name, x, y, z, sx, sy, sz, r, g, b, shape, transparency = row
        except ValueError:
            continue
        if not keep_walls and str(name).startswith(SKIP_PREFIXES):
            continue
        if float(transparency or 0) >= 0.9:
            continue
        out.append((float(x), float(y), float(z),
                    float(sx), float(sy), float(sz),
                    (int(r), int(g), int(b)),
                    "ball" if shape == 1 else "box"))
    return out


def clip_to_world(boxes, cx, half=78):
    """Same clipping rule as render_iso: cut slabs, do not drop them.

    Selecting by a part's centre drops the ground — one slab hundreds of studs
    wide whose centre is nowhere near any single world — and the render comes
    out with the buildings floating on empty sky.
    """
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
    return clipped


def main():
    if len(sys.argv) < 3:
        sys.exit(__doc__.strip().splitlines()[-1])
    src, dest = Path(sys.argv[1]), Path(sys.argv[2])
    world = sys.argv[3] if len(sys.argv) > 3 else None

    doc = json.loads(src.read_text())
    boxes = boxes_from(doc, world)
    if not boxes:
        sys.exit("that description has no drawable parts in it")

    label = doc.get("place") or "their place"
    if world:
        cx = None
        for row in doc.get("parts", []):
            if str(row[0]) == "Biome_" + world:
                cx = float(row[1])
                break
        if cx is None:
            known = sorted({str(r[0])[6:] for r in doc.get("parts", [])
                            if str(r[0]).startswith("Biome_")})
            sys.exit("no world called %r in this place (found: %s)"
                     % (world, ", ".join(known) or "none"))
        boxes = clip_to_world(boxes, cx)
        label = "%s - %s" % (label, world)

    n = render_iso.draw(boxes, dest, label)
    print("wrote %s (%d parts of %d sent)" % (dest, n, len(doc.get("parts", []))))

    if doc.get("text"):
        print()
        print(doc["text"])
    return 0


if __name__ == "__main__":
    sys.exit(main())
