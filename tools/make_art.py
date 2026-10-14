#!/usr/bin/env python3
"""The game's icon and thumbnails, drawn from code.

    python3 tools/make_art.py OUT_DIR [FONT_DIR]

Writes icon.png (512x512) and thumbnail_1.png / thumbnail_2.png (1920x1080),
the sizes Roblox asks for. FONT_DIR may hold LilitaOne-Regular.ttf and Fredoka
(Google Fonts, OFL); without them the titles fall back to Inter Black.

Everything is drawn at twice the size and scaled down, so edges are smooth.
The pets are the game's own species (cat, dog, dragon, bunny, and a Mythic),
drawn in the chunky cartoon style pet games use on Roblox.
"""
import math
import random
import sys
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter, ImageFont

SS = 2  # supersampling

# ---------------------------------------------------------------------------
# colour
# ---------------------------------------------------------------------------


def mix(a, b, t):
    return tuple(int(round(a[i] + (b[i] - a[i]) * t)) for i in range(3))


def lighter(c, t=0.45):
    return mix(c, (255, 255, 255), t)


def darker(c, t=0.45):
    return mix(c, (0, 0, 0), t)


# ---------------------------------------------------------------------------
# masks and stamping
# ---------------------------------------------------------------------------


def ellipse_mask(w, h):
    m = Image.new("L", (max(1, int(w)), max(1, int(h))), 0)
    ImageDraw.Draw(m).ellipse((0, 0, m.width - 1, m.height - 1), fill=255)
    return m


def poly_mask(points):
    xs = [p[0] for p in points]
    ys = [p[1] for p in points]
    x0, y0 = int(math.floor(min(xs))), int(math.floor(min(ys)))
    w, h = int(math.ceil(max(xs))) - x0 + 2, int(math.ceil(max(ys))) - y0 + 2
    m = Image.new("L", (max(1, w), max(1, h)), 0)
    ImageDraw.Draw(m).polygon([(x - x0, y - y0) for x, y in points], fill=255)
    return m, x0, y0


def dilate(mask, r):
    """Grow a mask by about r pixels, rounded."""
    if r <= 0:
        return mask
    pad = int(r) + 2
    big = Image.new("L", (mask.width + 2 * pad, mask.height + 2 * pad), 0)
    big.paste(mask, (pad, pad))
    grown = big.filter(ImageFilter.GaussianBlur(r * 0.55)).point(lambda v: 255 if v > 12 else 0)
    return grown.filter(ImageFilter.GaussianBlur(0.8)), pad


def shaded(w, h, base, hx=0.36, hy=0.28, light=0.42, dark=0.32):
    """A fill that is light at (hx, hy) of the box and darker at the rim."""
    w, h = max(1, int(w)), max(1, int(h))
    R = max(w, h) * 1.15
    g = Image.radial_gradient("L").resize((int(2 * R) + 2, int(2 * R) + 2))
    left, top = int(R - hx * w), int(R - hy * h)
    m = g.crop((left, top, left + w, top + h))
    hi, lo = lighter(base, light), darker(base, dark)
    # 0..128: highlight -> base ; 128..255: base -> rim
    a = m.point(lambda v: min(255, v * 2))
    b = m.point(lambda v: max(0, (v - 128) * 2))
    img = Image.composite(Image.new("RGB", (w, h), base), Image.new("RGB", (w, h), hi), a)
    img = Image.composite(Image.new("RGB", (w, h), lo), img, b)
    return img


def stamp(canvas, mask, x, y, fill, outline=None, ow=0, alpha=255):
    x, y = int(round(x)), int(round(y))
    if outline is not None and ow > 0:
        grown, pad = dilate(mask, ow)
        if alpha < 255:
            grown = grown.point(lambda v: v * alpha // 255)
        canvas.paste(Image.new("RGBA", grown.size, outline + (255,)), (x - pad, y - pad), grown)
    if isinstance(fill, tuple):
        fill = Image.new("RGB", mask.size, fill)
    m = mask if alpha >= 255 else mask.point(lambda v: v * alpha // 255)
    canvas.paste(fill.convert("RGBA"), (x, y), m)


def blob(canvas, cx, cy, w, h, color, ow=0, outline=None, shade=True, hx=0.36, hy=0.28, alpha=255):
    m = ellipse_mask(w, h)
    fill = shaded(w, h, color, hx, hy) if shade else color
    stamp(canvas, m, cx - w / 2, cy - h / 2, fill, outline, ow, alpha)


def poly(canvas, points, color, ow=0, outline=None, shade=True, hx=0.36, hy=0.28):
    m, x0, y0 = poly_mask(points)
    fill = shaded(m.width, m.height, color, hx, hy) if shade else color
    stamp(canvas, m, x0, y0, fill, outline, ow)


def glow(canvas, cx, cy, r, color, strength=200):
    """A soft light, drawn only in its own square."""
    size = int(r * 2.6)
    layer = Image.new("RGBA", (size, size), color + (0,))
    m = Image.new("L", (size, size), 0)
    ImageDraw.Draw(m).ellipse((size * 0.2, size * 0.2, size * 0.8, size * 0.8), fill=strength)
    m = m.filter(ImageFilter.GaussianBlur(r * 0.35))
    layer.putalpha(m)
    canvas.alpha_composite(layer, (int(cx - size / 2), int(cy - size / 2)))


def sparkle(canvas, cx, cy, r, color=(255, 255, 255)):
    glow(canvas, cx, cy, r * 1.2, color, 150)
    pts = []
    for i in range(8):
        a = math.pi / 4 * i - math.pi / 2
        rr = r if i % 2 == 0 else r * 0.22
        pts.append((cx + math.cos(a) * rr, cy + math.sin(a) * rr))
    m, x0, y0 = poly_mask(pts)
    stamp(canvas, m, x0, y0, color)


def rays(canvas, cx, cy, n, color, alpha, length):
    layer = Image.new("RGBA", canvas.size, color + (0,))
    m = Image.new("L", canvas.size, 0)
    d = ImageDraw.Draw(m)
    for i in range(n):
        a0 = 2 * math.pi * i / n
        a1 = a0 + math.pi / n
        d.polygon([(cx, cy), (cx + math.cos(a0) * length, cy + math.sin(a0) * length),
                   (cx + math.cos(a1) * length, cy + math.sin(a1) * length)], fill=alpha)
    layer.putalpha(m.filter(ImageFilter.GaussianBlur(6)))
    canvas.alpha_composite(layer)


def radial_bg(size, center, inner, outer, reach=1.0):
    w, h = size
    R = int(max(w, h) * reach)
    g = Image.radial_gradient("L").resize((2 * R, 2 * R))
    left, top = int(R - center[0] * w), int(R - center[1] * h)
    m = g.crop((left, top, left + w, top + h))
    return Image.composite(Image.new("RGB", size, outer), Image.new("RGB", size, inner), m).convert("RGBA")


# ---------------------------------------------------------------------------
# things: pets, eggs, coins, gems
# ---------------------------------------------------------------------------

PETS = {
    "cat":    {"base": (247, 158, 64), "eye": (90, 60, 30)},
    "dog":    {"base": (214, 160, 104), "eye": (80, 50, 30)},
    "dragon": {"base": (92, 204, 112), "eye": (40, 110, 60)},
    "bunny":  {"base": (250, 246, 252), "eye": (170, 60, 130)},
    "mythic": {"base": (150, 84, 255), "eye": (40, 210, 255)},
}


def eyes(canvas, cx, cy, s, iris, gap=0.40):
    for side in (-1, 1):
        ex = cx + side * gap * s
        ey = cy + 0.06 * s
        blob(canvas, ex, ey, 0.36 * s, 0.46 * s, (35, 22, 48), shade=False)
        blob(canvas, ex, ey + 0.08 * s, 0.30 * s, 0.26 * s, iris, shade=True, hx=0.5, hy=0.9)
        blob(canvas, ex - 0.06 * s, ey - 0.1 * s, 0.17 * s, 0.17 * s, (255, 255, 255), shade=False)
        blob(canvas, ex + 0.07 * s, ey + 0.1 * s, 0.07 * s, 0.07 * s, (255, 255, 255), shade=False)


def face(canvas, cx, cy, s, iris, mouth="w"):
    eyes(canvas, cx, cy, s, iris)
    for side in (-1, 1):
        blob(canvas, cx + side * 0.66 * s, cy + 0.36 * s, 0.28 * s, 0.15 * s, (255, 120, 160),
             shade=False, alpha=150)
    d = ImageDraw.Draw(canvas)
    lw = max(2, int(0.045 * s))
    mc = (60, 30, 50)
    my = cy + 0.34 * s
    if mouth == "w":
        r = 0.09 * s
        d.arc((cx - 2 * r, my - r, cx, my + r), 10, 170, fill=mc, width=lw)
        d.arc((cx, my - r, cx + 2 * r, my + r), 10, 170, fill=mc, width=lw)
    else:
        r = 0.16 * s
        d.chord((cx - r, my - r * 0.9, cx + r, my + r * 0.9), 0, 180, fill=(120, 30, 60))
        blob(canvas, cx, my + r * 0.45, r * 0.9, r * 0.5, (255, 120, 140), shade=False)


def pet(canvas, cx, cy, s, kind):
    """A chibi pet: head centred at (cx, cy), head radius s."""
    p = PETS[kind]
    base = p["base"]
    ol = darker(base, 0.62) if kind != "bunny" else (120, 100, 150)
    ow = 0.07 * s
    # shadow on the ground
    blob(canvas, cx, cy + 1.42 * s, 1.7 * s, 0.32 * s, (20, 10, 40), shade=False, alpha=70)
    if kind == "mythic":
        glow(canvas, cx, cy + 0.3 * s, 1.9 * s, (200, 120, 255), 230)
    # tails and wings, behind everything
    if kind in ("cat", "mythic"):
        # A tapering tail that rises from behind the body and curls over at
        # the tip: a run of overlapping circles, outlined as one shape.
        dots = []
        for i in range(28):
            t = i / 27
            x = cx + 0.55 * s + 0.62 * s * math.sin(t * math.pi * 0.62)
            y = cy + 1.15 * s - 1.05 * s * t
            if t > 0.72:
                k = (t - 0.72) / 0.28
                x -= 0.3 * s * k * k
                y -= 0.08 * s * k
            dots.append((x, y, (0.17 - 0.07 * t) * s))
        x0 = min(x - r for x, y, r in dots); y0 = min(y - r for x, y, r in dots)
        x1 = max(x + r for x, y, r in dots); y1 = max(y + r for x, y, r in dots)
        m = Image.new("L", (int(x1 - x0) + 2, int(y1 - y0) + 2), 0)
        dm = ImageDraw.Draw(m)
        for x, y, r in dots:
            dm.ellipse((x - x0 - r, y - y0 - r, x - x0 + r, y - y0 + r), fill=255)
        stamp(canvas, m, x0, y0, shaded(m.width, m.height, base, 0.3, 0.3), ol, ow)
    if kind == "dragon":
        for side in (-1, 1):
            wx = cx + side * 0.75 * s
            pts = [(wx, cy + 0.55 * s), (wx + side * 0.95 * s, cy - 0.15 * s),
                   (wx + side * 0.85 * s, cy + 0.25 * s), (wx + side * 1.05 * s, cy + 0.35 * s),
                   (wx + side * 0.75 * s, cy + 0.55 * s), (wx + side * 0.85 * s, cy + 0.75 * s),
                   (wx + side * 0.2 * s, cy + 0.95 * s)]
            poly(canvas, pts, darker(base, 0.18), ow, ol)
    if kind == "dog":
        blob(canvas, cx + 0.95 * s, cy + 0.55 * s, 0.32 * s, 0.6 * s, base, ow, ol)
    if kind == "bunny":
        blob(canvas, cx + 0.72 * s, cy + 1.05 * s, 0.38 * s, 0.38 * s, (255, 255, 255), ow, ol)
    # body and feet
    blob(canvas, cx, cy + 0.92 * s, 1.35 * s, 1.0 * s, base, ow, ol)
    blob(canvas, cx, cy + 1.0 * s, 0.75 * s, 0.6 * s, lighter(base, 0.45), shade=False, alpha=200)
    for side in (-1, 1):
        blob(canvas, cx + side * 0.36 * s, cy + 1.36 * s, 0.46 * s, 0.3 * s, base, ow, ol)
    # ears behind the head
    if kind in ("cat", "mythic"):
        for side in (-1, 1):
            pts = [(cx + side * 0.25 * s, cy - 0.78 * s), (cx + side * 0.9 * s, cy - 1.28 * s),
                   (cx + side * 0.92 * s, cy - 0.35 * s)]
            poly(canvas, pts, base, ow, ol)
            inner = [(cx + side * 0.42 * s, cy - 0.72 * s), (cx + side * 0.84 * s, cy - 1.08 * s),
                     (cx + side * 0.84 * s, cy - 0.5 * s)]
            poly(canvas, inner, (255, 150, 185), shade=False)
    if kind == "bunny":
        for side in (-1, 1):
            blob(canvas, cx + side * 0.38 * s, cy - 1.15 * s, 0.42 * s, 1.25 * s, base, ow, ol)
            blob(canvas, cx + side * 0.38 * s, cy - 1.1 * s, 0.2 * s, 0.9 * s, (255, 170, 200), shade=False)
    if kind == "dragon":
        for side in (-1, 1):
            pts = [(cx + side * 0.32 * s, cy - 0.82 * s), (cx + side * 0.62 * s, cy - 1.38 * s),
                   (cx + side * 0.66 * s, cy - 0.7 * s)]
            poly(canvas, pts, (255, 236, 170), ow, (150, 110, 40))
    # head
    blob(canvas, cx, cy, 2.12 * s, 1.88 * s, base, ow, ol)
    if kind == "dog":
        for side in (-1, 1):
            blob(canvas, cx + side * 0.95 * s, cy + 0.12 * s, 0.52 * s, 1.0 * s, darker(base, 0.25), ow, ol)
        blob(canvas, cx, cy + 0.38 * s, 0.78 * s, 0.5 * s, lighter(base, 0.55), shade=False)
    if kind == "cat":
        d = ImageDraw.Draw(canvas)
        for dx in (-0.18, 0, 0.18):
            d.line((cx + dx * s, cy - 0.85 * s, cx + dx * s * 0.6, cy - 0.6 * s),
                   fill=darker(base, 0.25), width=int(0.07 * s))
    if kind == "dragon":
        blob(canvas, cx, cy + 0.45 * s, 0.8 * s, 0.42 * s, lighter(base, 0.35), shade=False)
        for side in (-1, 1):
            blob(canvas, cx + side * 0.13 * s, cy + 0.38 * s, 0.07 * s, 0.05 * s, darker(base, 0.5), shade=False)
    if kind == "mythic":
        rnd = random.Random(7)
        for _ in range(9):
            a = rnd.uniform(0, 2 * math.pi)
            r = rnd.uniform(0.2, 0.85) * s
            sparkle(canvas, cx + math.cos(a) * r * 1.05, cy - 0.35 * s + math.sin(a) * r * 0.5,
                    rnd.uniform(0.05, 0.1) * s)
    face(canvas, cx, cy + (0.02 * s if kind != "dog" else -0.06 * s), s, p["eye"],
         mouth="open" if kind in ("mythic", "dragon") else "w")
    if kind == "dog":
        blob(canvas, cx, cy + 0.22 * s, 0.22 * s, 0.15 * s, (60, 35, 30), shade=False)


def egg(canvas, cx, cy, h, color, spots=(255, 255, 255), cracked=False):
    w = 0.78 * h
    pts = []
    for i in range(60):
        t = 2 * math.pi * i / 60
        y = math.sin(t) * h / 2
        x = math.cos(t) * w / 2 * (1 + 0.16 * math.sin(t))
        pts.append((cx + x, cy + y))
    ol = darker(color, 0.55)
    if cracked:
        glow(canvas, cx, cy - 0.1 * h, 0.75 * h, lighter(color, 0.6), 240)
    poly(canvas, pts, color, 0.05 * h, ol, hx=0.35, hy=0.25)
    rnd = random.Random(int(cx + cy))
    for _ in range(5):
        a = rnd.uniform(0, 2 * math.pi)
        r = rnd.uniform(0.1, 0.3)
        blob(canvas, cx + math.cos(a) * r * w, cy + math.sin(a) * r * h * 1.1,
             rnd.uniform(0.1, 0.18) * h, rnd.uniform(0.08, 0.14) * h, spots, shade=False, alpha=210)
    blob(canvas, cx - 0.17 * w, cy - 0.26 * h, 0.16 * w, 0.24 * h, (255, 255, 255), shade=False, alpha=160)
    if cracked:
        d = ImageDraw.Draw(canvas)
        zig = [(cx - w * 0.5, cy - 0.05 * h)]
        for i in range(1, 9):
            zig.append((cx - w * 0.5 + i * w / 8, cy - 0.05 * h + (0.09 * h if i % 2 else -0.06 * h)))
        d.line(zig, fill=ol, width=int(0.035 * h), joint="curve")
        for i in range(7):
            a = -math.pi / 2 + (i - 3) * 0.38
            sparkle(canvas, cx + math.cos(a) * 0.62 * h, cy - 0.1 * h + math.sin(a) * 0.62 * h,
                    0.06 * h, (255, 250, 210))


def coin(canvas, cx, cy, r, tilt=1.0):
    gold, ol = (255, 196, 40), (170, 100, 10)
    blob(canvas, cx, cy, 2 * r * tilt, 2 * r, gold, 0.12 * r, ol)
    blob(canvas, cx, cy, 1.45 * r * tilt, 1.45 * r, (255, 214, 80), shade=False)
    blob(canvas, cx, cy, 1.25 * r * tilt, 1.25 * r, (250, 180, 30), shade=True, hx=0.7, hy=0.75)
    # a paw, as on the game's coins
    pc = (205, 130, 15)
    blob(canvas, cx, cy + 0.18 * r, 0.62 * r * tilt, 0.48 * r, pc, shade=False)
    for dx, dy in ((-0.38, -0.25), (-0.13, -0.45), (0.13, -0.45), (0.38, -0.25)):
        blob(canvas, cx + dx * r * tilt, cy + dy * r, 0.22 * r * tilt, 0.26 * r, pc, shade=False)
    blob(canvas, cx - 0.45 * r * tilt, cy - 0.5 * r, 0.35 * r * tilt, 0.22 * r, (255, 255, 230),
         shade=False, alpha=170)


def gem(canvas, cx, cy, r, color=(70, 210, 255)):
    pts = [(cx - r, cy - 0.3 * r), (cx - 0.6 * r, cy - 0.8 * r), (cx + 0.6 * r, cy - 0.8 * r),
           (cx + r, cy - 0.3 * r), (cx, cy + r)]
    ol = darker(color, 0.6)
    poly(canvas, pts, color, 0.1 * r, ol, hx=0.3, hy=0.2)
    d = ImageDraw.Draw(canvas)
    lw = max(2, int(0.06 * r))
    lc = lighter(color, 0.6)
    d.line([(cx - r, cy - 0.3 * r), (cx + r, cy - 0.3 * r)], fill=lc, width=lw)
    for x in (-0.6, -0.2, 0.2, 0.6):
        d.line([(cx + x * r, cy - 0.3 * r), (cx, cy + r)], fill=lc, width=lw)
    poly(canvas, [(cx - 0.6 * r, cy - 0.8 * r), (cx - 0.2 * r, cy - 0.3 * r), (cx - r, cy - 0.3 * r)],
         lighter(color, 0.7), shade=False)


# ---------------------------------------------------------------------------
# title text
# ---------------------------------------------------------------------------
FONTS = {}


def font(path, size, variation=None):
    key = (str(path), size, variation)
    if key not in FONTS:
        try:
            f = ImageFont.truetype(str(path), size)
            if variation:
                f.set_variation_by_name(variation)
        except Exception:  # noqa: BLE001
            f = ImageFont.truetype("/usr/share/fonts/opentype/inter/Inter-Black.otf", size)
        FONTS[key] = f
    return FONTS[key]


def title(canvas, text, cx, cy, size, face_path, top=(255, 245, 120), bottom=(255, 160, 30),
          stroke=(55, 12, 95), rim=(255, 255, 255), rotation=-3, variation=None, weight=0.14):
    f = font(face_path, size, variation)
    sw = max(2, int(size * weight))
    rw = max(1, int(size * 0.05))
    l, t, r, b = f.getbbox(text, stroke_width=sw)
    pad = sw * 2
    W, H = r - l + pad * 2, b - t + pad * 2 + int(size * 0.12)
    layer = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    org = (pad - l, pad - t)
    d.text((org[0], org[1] + int(size * 0.09)), text, font=f, fill=(20, 0, 40, 150),
           stroke_width=sw, stroke_fill=(20, 0, 40, 150))
    d.text(org, text, font=f, fill=stroke, stroke_width=sw, stroke_fill=stroke)
    d.text(org, text, font=f, fill=rim, stroke_width=rw, stroke_fill=rim)
    m = Image.new("L", (W, H), 0)
    ImageDraw.Draw(m).text(org, text, font=f, fill=255)
    grad = Image.linear_gradient("L").resize((W, H))
    fill = Image.composite(Image.new("RGB", (W, H), bottom), Image.new("RGB", (W, H), top), grad)
    layer.paste(fill, (0, 0), m)
    # a glossy band across the upper half of the letters
    gm = m.point(lambda v: v * 90 // 255)
    band = Image.new("L", (W, H), 0)
    ImageDraw.Draw(band).rectangle((0, 0, W, int(org[1] + (b - t) * 0.42)), fill=255)
    from PIL import ImageChops
    gm = ImageChops.multiply(gm, band)
    layer.paste(Image.new("RGB", (W, H), (255, 255, 255)), (0, 0), gm)
    if rotation:
        layer = layer.rotate(rotation, resample=Image.BICUBIC, expand=True)
    canvas.alpha_composite(layer, (int(cx - layer.width / 2), int(cy - layer.height / 2)))
    return layer.size


def pill(canvas, cx, cy, text, color, size, face_path, variation="Bold"):
    f = font(face_path, size, variation)
    l, t, r, b = f.getbbox(text)
    w, h = r - l + size * 1.2, size * 1.5
    x0, y0 = cx - w / 2, cy - h / 2
    d = ImageDraw.Draw(canvas)
    d.rounded_rectangle((x0 - size * 0.12, y0 - size * 0.12, x0 + w + size * 0.12, y0 + h + size * 0.12),
                        radius=h, fill=darker(color, 0.55))
    d.rounded_rectangle((x0, y0, x0 + w, y0 + h), radius=h, fill=color)
    d.rounded_rectangle((x0 + h * 0.2, y0 + h * 0.12, x0 + w - h * 0.2, y0 + h * 0.45),
                        radius=h, fill=lighter(color, 0.3))
    d.text((cx - (r - l) / 2 - l, cy - (b - t) / 2 - t), text, font=f, fill=(255, 255, 255),
           stroke_width=max(2, int(size * 0.1)), stroke_fill=darker(color, 0.55))


# ---------------------------------------------------------------------------
# the pieces
# ---------------------------------------------------------------------------


def scatter_sparkles(canvas, n, seed, region, rmin, rmax):
    rnd = random.Random(seed)
    x0, y0, x1, y1 = region
    for _ in range(n):
        sparkle(canvas, rnd.uniform(x0, x1), rnd.uniform(y0, y1), rnd.uniform(rmin, rmax),
                rnd.choice([(255, 255, 255), (255, 240, 170), (200, 230, 255)]))


def make_icon(fonts):
    W = H = 512 * SS
    c = radial_bg((W, H), (0.5, 0.36), (170, 110, 255), (34, 12, 96), 1.0)
    rays(c, W * 0.5, H * 0.36, 18, (255, 255, 255), 34, W)
    scatter_sparkles(c, 22, 3, (0, 0, W, H * 0.62), W * 0.006, W * 0.018)
    egg(c, W * 0.78, H * 0.30, H * 0.26, (90, 200, 255), cracked=True)
    pet(c, W * 0.25, H * 0.36, W * 0.085, "dragon")
    pet(c, W * 0.52, H * 0.33, W * 0.15, "cat")
    coin(c, W * 0.13, H * 0.62, W * 0.05)
    coin(c, W * 0.86, H * 0.58, W * 0.045, 0.75)
    gem(c, W * 0.9, H * 0.12, W * 0.04, (210, 120, 255))
    gem(c, W * 0.1, H * 0.12, W * 0.035)
    lilita = fonts / "LilitaOne-Regular.ttf"
    title(c, "MYSTIC", W * 0.5, H * 0.715, int(W * 0.2), lilita, rotation=-4)
    title(c, "PETS", W * 0.5, H * 0.875, int(W * 0.21), lilita,
          top=(130, 255, 255), bottom=(40, 150, 255), rotation=-4)
    return c.resize((512, 512), Image.LANCZOS).convert("RGB")


def landscape(W, H):
    c = radial_bg((W, H), (0.5, 0.42), (175, 235, 255), (72, 96, 230), 0.95)
    rays(c, W * 0.5, H * 0.42, 22, (255, 255, 255), 40, W)
    # clouds
    for cx, cy, s in ((0.1, 0.22, 1.0), (0.9, 0.18, 1.2), (0.78, 0.36, 0.7), (0.2, 0.42, 0.6)):
        for dx, dy, r in ((0, 0, 1), (0.6, 0.15, 0.75), (-0.6, 0.18, 0.7), (0.25, -0.35, 0.7)):
            blob(c, W * cx + dx * W * 0.04 * s, H * cy + dy * W * 0.04 * s, W * 0.07 * s * r,
                 W * 0.055 * s * r, (255, 255, 255), shade=True, hx=0.4, hy=0.25, alpha=235)
    # hills
    blob(c, W * 0.2, H * 1.02, W * 0.9, H * 0.62, (110, 210, 120), H * 0.012, (60, 140, 70), hx=0.5, hy=0.1)
    blob(c, W * 0.85, H * 1.04, W * 0.8, H * 0.6, (110, 210, 120), H * 0.012, (60, 140, 70), hx=0.5, hy=0.1)
    blob(c, W * 0.5, H * 1.12, W * 1.3, H * 0.62, (90, 196, 100), H * 0.012, (50, 125, 60), hx=0.5, hy=0.1)
    # the path from spawn
    path = [(W * 0.44, H * 1.0), (W * 0.56, H * 1.0), (W * 0.52, H * 0.82), (W * 0.48, H * 0.82)]
    poly(c, path, (225, 205, 160), shade=False)
    return c


def make_thumb_1(fonts):
    W, H = 1920 * SS, 1080 * SS
    c = landscape(W, H)
    scatter_sparkles(c, 26, 11, (0, 0, W, H * 0.55), W * 0.003, W * 0.009)
    lilita = fonts / "LilitaOne-Regular.ttf"
    fredoka = fonts / "Fredoka"
    title(c, "MYSTIC PETS", W * 0.5, H * 0.17, int(H * 0.2), lilita, rotation=-2)
    title(c, "HATCH  •  LEVEL UP  •  REBIRTH", W * 0.5, H * 0.335, int(H * 0.07), lilita,
          top=(255, 255, 255), bottom=(220, 236, 255), stroke=(40, 30, 110), rotation=-2,
          weight=0.11)
    egg(c, W * 0.37, H * 0.6, H * 0.2, (255, 200, 70), cracked=True)
    egg(c, W * 0.64, H * 0.6, H * 0.18, (120, 210, 255))
    pet(c, W * 0.14, H * 0.68, H * 0.085, "dragon")
    pet(c, W * 0.3, H * 0.76, H * 0.095, "dog")
    pet(c, W * 0.5, H * 0.68, H * 0.13, "mythic")
    pet(c, W * 0.7, H * 0.76, H * 0.095, "bunny")
    pet(c, W * 0.86, H * 0.68, H * 0.09, "cat")
    for x, y, r, t in ((0.06, 0.42, 0.04, 1), (0.93, 0.44, 0.036, 0.7), (0.24, 0.5, 0.028, 0.8),
                       (0.79, 0.52, 0.03, 1)):
        coin(c, W * x, H * y, H * r, t)
    gem(c, W * 0.12, H * 0.92, H * 0.035, (210, 120, 255))
    gem(c, W * 0.9, H * 0.93, H * 0.035)
    return c.resize((1920, 1080), Image.LANCZOS).convert("RGB")


def make_thumb_2(fonts):
    W, H = 1920 * SS, 1080 * SS
    c = radial_bg((W, H), (0.5, 0.55), (150, 80, 255), (20, 8, 60), 0.9)
    rays(c, W * 0.5, H * 0.55, 26, (255, 220, 255), 30, W)
    scatter_sparkles(c, 60, 21, (0, 0, W, H), W * 0.002, W * 0.007)
    lilita = fonts / "LilitaOne-Regular.ttf"
    fredoka = fonts / "Fredoka"
    title(c, "HATCH A MYTHIC!", W * 0.5, H * 0.14, int(H * 0.16), lilita,
          top=(255, 150, 255), bottom=(150, 70, 255), stroke=(40, 5, 70), rim=(255, 255, 255))
    egg(c, W * 0.5, H * 0.52, H * 0.38, (190, 120, 255), spots=(255, 220, 255), cracked=True)
    pet(c, W * 0.5, H * 0.66, H * 0.12, "mythic")
    rarities = [("COMMON", (150, 150, 160)), ("UNCOMMON", (60, 190, 70)), ("RARE", (50, 110, 255)),
                ("EPIC", (160, 40, 220)), ("LEGENDARY", (255, 160, 0)), ("MYTHIC", (0, 190, 255))]
    for i, (name, col) in enumerate(rarities):
        pill(c, W * 0.15, H * (0.3 + i * 0.1), name, col, int(H * 0.035), fredoka)
    pill(c, W * 0.85, H * 0.4, "SHINY  x4", (60, 200, 255), int(H * 0.042), fredoka)
    pill(c, W * 0.85, H * 0.55, "RAINBOW  x10", (255, 90, 170), int(H * 0.042), fredoka)
    pill(c, W * 0.85, H * 0.7, "PET LEVELS 1-50", (255, 170, 30), int(H * 0.042), fredoka)
    coin(c, W * 0.3, H * 0.85, H * 0.04)
    coin(c, W * 0.7, H * 0.86, H * 0.035, 0.7)
    gem(c, W * 0.38, H * 0.92, H * 0.03, (210, 120, 255))
    gem(c, W * 0.62, H * 0.93, H * 0.03)
    return c.resize((1920, 1080), Image.LANCZOS).convert("RGB")


def main():
    out = Path(sys.argv[1]) if len(sys.argv) > 1 else Path("art")
    fonts = Path(sys.argv[2]) if len(sys.argv) > 2 else Path(__file__).resolve().parent.parent / "art" / "fonts"
    out.mkdir(parents=True, exist_ok=True)
    make_icon(fonts).save(out / "icon.png")
    make_thumb_1(fonts).save(out / "thumbnail_1.png")
    make_thumb_2(fonts).save(out / "thumbnail_2.png")
    print("wrote icon.png (512x512), thumbnail_1.png and thumbnail_2.png (1920x1080) to %s" % out)


if __name__ == "__main__":
    main()
