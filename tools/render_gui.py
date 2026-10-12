#!/usr/bin/env python3
"""Draw the screen a player sees: every ScreenGui, laid out the way Roblox does.

The HUD and the panels are built in code, so the only way to see one without
Studio was to imagine it from a few hundred lines of UDim2s. That is how a
counter ended up 103 points off the left of a phone, and how six panels
ended up mostly off screen: every number was right on its own line and wrong
together.

This boots the real client (check_client.boot), sets a screen size, and lays
out every GuiObject with Roblox's rules: scale and offset against the parent,
AnchorPoint, UIScale (which zooms a subtree about its anchor),
UISizeConstraint, UIAspectRatioConstraint, UIPadding, UIListLayout,
UIGridLayout, ScrollingFrame canvases and ClipsDescendants. Then it draws:
UICorner, UIStroke, UIGradient, text (Inter standing in for Gotham, widened to
Gotham's measure, with real colour emoji), images and viewports as
placeholders.

It is not a screenshot. It is the geometry, drawn, which is what every HUD bug
in this project has actually been. `layout()` is used by check_ui to measure
the HUD at phone and desktop sizes; the drawing is for a person to look at.

    python3 tools/render_gui.py out.png                 1536x1024
    python3 tools/render_gui.py out.png 390 844         a portrait phone
    python3 tools/render_gui.py out.png 844 390 --open PetsPanel
"""
import math
import re
import sys
from pathlib import Path

try:
    from PIL import Image, ImageDraw, ImageFont
except ImportError:
    sys.exit("pillow is not installed (pip install pillow)")

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "tools"))

# Roblox's own top bar. A ScreenGui without IgnoreGuiInset starts below it.
TOPBAR = 58

# ---------------------------------------------------------------------------
# Reading the GUI out of the running client
# ---------------------------------------------------------------------------
# One pass in Lua turns every property into plain data, so the layout below
# never has to ask the mock what kind of value something is.
DUMP_LUA = r"""
function(root, typeof)
  local function enc(v)
    local t = type(v)
    if t == "number" or t == "string" or t == "boolean" then return v end
    if t ~= "table" then return nil end
    local ty = typeof(v)
    if ty == "UDim2" then return { "U2", v.X.Scale or 0, v.X.Offset or 0, v.Y.Scale or 0, v.Y.Offset or 0 } end
    if ty == "Color3" then return { "C3", v.R or 0, v.G or 0, v.B or 0 } end
    if ty == "EnumItem" then return { "E", tostring(v.Name) } end
    if ty == "Instance" or ty == "Vector3" or ty == "CFrame" then return nil end
    if rawget(v, "Scale") ~= nil and rawget(v, "Offset") ~= nil then
      return { "U", v.Scale, v.Offset }
    end
    if type(rawget(v, "X")) == "number" and type(rawget(v, "Y")) == "number" then
      return { "V2", v.X, v.Y }
    end
    if #v > 0 then
      local seq = { "SEQ" }
      -- ColorSequence.new({kp, kp}) arrives as a list holding that list.
      local items = v
      if #v == 1 and type(v[1]) == "table" and #v[1] > 0 and typeof(v[1]) == "table"
         and v[1].Time == nil and v[1].R == nil then
        items = v[1]
      end
      for _, k in ipairs(items) do
        if type(k) == "table" and k.Time ~= nil then
          local val = k.Value
          if type(val) == "table" and typeof(val) == "Color3" then
            seq[#seq + 1] = { k.Time, val.R, val.G, val.B }
          elseif type(val) == "number" then
            seq[#seq + 1] = { k.Time, val }
          end
        elseif type(k) == "table" and typeof(k) == "Color3" then
          seq[#seq + 1] = { -1, k.R, k.G, k.B }
        elseif type(k) == "number" then
          seq[#seq + 1] = { -1, k }
        end
      end
      return seq
    end
    return nil
  end
  local function node(inst)
    local p = rawget(inst, "_p")
    local props = {}
    for k, v in pairs(p) do
      if type(k) == "string" and k ~= "Parent" then
        local e = enc(v)
        if e ~= nil then props[k] = e end
      end
    end
    local kids = {}
    for i, c in ipairs(rawget(inst, "_c")) do kids[i] = node(c) end
    local attrs = {}
    for k, v in pairs(rawget(inst, "_a") or {}) do
      local e = enc(v); if e ~= nil then attrs[k] = e end
    end
    return { cls = p.ClassName, name = p.Name, p = props, a = attrs, kids = kids, inst = inst }
  end
  return node(root)
end
"""


def _py(x, depth=0):
    """A lupa table, all the way down, as Python lists and dicts."""
    import lupa
    if lupa.lua_type(x) != "table":
        return x
    keys = list(x.keys())
    if keys and all(isinstance(k, int) for k in keys):
        return [_py(x[k], depth + 1) for k in sorted(keys)]
    out = {}
    for k in keys:
        out[k] = x[k] if k == "inst" else _py(x[k], depth + 1)
    return out


def dump(lua, root):
    fn = lua.eval(DUMP_LUA)
    return _py(fn(root, lua.globals().typeof))


# ---------------------------------------------------------------------------
# Value helpers, with Roblox's defaults for anything never set
# ---------------------------------------------------------------------------
GUI_CLASSES = {"Frame", "TextLabel", "TextButton", "TextBox", "ImageLabel",
               "ImageButton", "ScrollingFrame", "ViewportFrame", "CanvasGroup",
               "VideoFrame"}
TEXT_CLASSES = {"TextLabel", "TextButton", "TextBox"}
IMAGE_CLASSES = {"ImageLabel", "ImageButton"}

DEFAULT_SIZE = {"TextLabel": (0, 200, 0, 50), "TextButton": (0, 200, 0, 50),
                "TextBox": (0, 200, 0, 50)}


def u2(p, key, default=(0, 0, 0, 0)):
    v = p.get(key)
    if isinstance(v, list) and v and v[0] == "U2":
        return tuple(float(a) for a in v[1:5])
    return default


def c3(p, key, default):
    v = p.get(key)
    if isinstance(v, list) and v and v[0] == "C3":
        return tuple(max(0, min(255, int(round(float(a) * 255)))) for a in v[1:4])
    return default


def num(p, key, default):
    v = p.get(key)
    return float(v) if isinstance(v, (int, float)) and not isinstance(v, bool) else default


def boolp(p, key, default):
    v = p.get(key)
    return v if isinstance(v, bool) else default


def enum(p, key, default):
    v = p.get(key)
    if isinstance(v, list) and v and v[0] == "E":
        return str(v[1])
    return default


def udim(p, key, default=(0, 0)):
    v = p.get(key)
    if isinstance(v, list) and v and v[0] == "U":
        return float(v[1]), float(v[2])
    return default


def v2(p, key, default=(0, 0)):
    v = p.get(key)
    if isinstance(v, list) and v and v[0] == "V2":
        return float(v[1]), float(v[2])
    return default


def kid(node, cls):
    for c in node["kids"]:
        if c["cls"] == cls:
            return c
    return None


# ---------------------------------------------------------------------------
# Layout
# ---------------------------------------------------------------------------
class Box:
    """Where one GuiObject ended up, in screen pixels."""
    __slots__ = ("node", "x", "y", "w", "h", "k", "clip", "gui", "depth")

    def __init__(self, node, x, y, w, h, k, clip, gui, depth):
        self.node, self.x, self.y, self.w, self.h = node, x, y, w, h
        self.k, self.clip, self.gui, self.depth = k, clip, gui, depth

    @property
    def name(self):
        return str(self.node["name"])

    @property
    def rect(self):
        return (self.x, self.y, self.w, self.h)

    def visible_rect(self):
        """The part of it that can be seen, after every clipping ancestor."""
        x0, y0, x1, y1 = self.x, self.y, self.x + self.w, self.y + self.h
        if self.clip:
            cx0, cy0, cx1, cy1 = self.clip
            x0, y0, x1, y1 = max(x0, cx0), max(y0, cy0), min(x1, cx1), min(y1, cy1)
        if x1 <= x0 or y1 <= y0:
            return None
        return (x0, y0, x1 - x0, y1 - y0)


def _constrain(node, w, h):
    for c in node["kids"]:
        if c["cls"] == "UISizeConstraint":
            mn = v2(c["p"], "MinSize", (0, 0))
            mx = v2(c["p"], "MaxSize", (math.inf, math.inf))
            w = min(max(w, mn[0]), mx[0]) if mx[0] > 0 else w
            h = min(max(h, mn[1]), mx[1]) if mx[1] > 0 else h
    for c in node["kids"]:
        if c["cls"] == "UIAspectRatioConstraint":
            ar = num(c["p"], "AspectRatio", 1.0) or 1.0
            kind = enum(c["p"], "AspectType", "FitWithinMaxSize")
            axis = enum(c["p"], "DominantAxis", "Width")
            if kind == "ScaleWithParentSize":
                if axis == "Width":
                    h = w / ar
                else:
                    w = h * ar
            elif h > 0 and w / h > ar:
                w = h * ar
            else:
                h = w / ar
    return w, h


def _size(node, pw, ph):
    sx, ox, sy, oy = u2(node["p"], "Size", DEFAULT_SIZE.get(node["cls"], (0, 100, 0, 100)))
    return _constrain(node, sx * pw + ox, sy * ph + oy)


def _scale_of(node):
    s = kid(node, "UIScale")
    return num(s["p"], "Scale", 1.0) if s else 1.0


def _sort_key(node, by_name):
    if by_name:
        return str(node["name"])
    return num(node["p"], "LayoutOrder", 0)


def _flow(node, pw, ph, items):
    """Positions a UIListLayout or UIGridLayout imposes: {id: (x, y, w, h)}."""
    lay = kid(node, "UIListLayout") or kid(node, "UIGridLayout")
    if not lay or not items:
        return {}
    lp = lay["p"]
    by_name = enum(lp, "SortOrder", "LayoutOrder") == "Name"
    order = sorted(items, key=lambda n: _sort_key(n, by_name))
    halign = enum(lp, "HorizontalAlignment", "Left")
    valign = enum(lp, "VerticalAlignment", "Top")
    out = {}
    if lay["cls"] == "UIListLayout":
        vertical = enum(lp, "FillDirection", "Vertical") == "Vertical"
        ps, po = udim(lp, "Padding", (0, 0))
        pad = ps * (ph if vertical else pw) + po
        sizes = [_size(n, pw, ph) for n in order]
        total = sum(s[1] if vertical else s[0] for s in sizes) + pad * (len(order) - 1)
        if vertical:
            cur = {"Top": 0, "Center": (ph - total) / 2, "Bottom": ph - total}.get(valign, 0)
        else:
            cur = {"Left": 0, "Center": (pw - total) / 2, "Right": pw - total}.get(halign, 0)
        for n, (w, h) in zip(order, sizes):
            if vertical:
                x = {"Left": 0, "Center": (pw - w) / 2, "Right": pw - w}.get(halign, 0)
                out[id(n)] = (x, cur, w, h)
                cur += h + pad
            else:
                y = {"Top": 0, "Center": (ph - h) / 2, "Bottom": ph - h}.get(valign, 0)
                out[id(n)] = (cur, y, w, h)
                cur += w + pad
        return out
    # grid
    csx, cox, csy, coy = u2(lp, "CellSize", (0, 100, 0, 100))
    psx, pox, psy, poy = u2(lp, "CellPadding", (0, 5, 0, 5))
    cw, ch = csx * pw + cox, csy * ph + coy
    px, py = psx * pw + pox, psy * ph + poy
    horizontal = enum(lp, "FillDirection", "Horizontal") == "Horizontal"
    maxc = int(num(lp, "FillDirectionMaxCells", 0))
    if horizontal:
        per = max(1, int((pw + px) // (cw + px))) if cw + px > 0 else 1
    else:
        per = max(1, int((ph + py) // (ch + py))) if ch + py > 0 else 1
    if maxc > 0:
        per = min(per, maxc)
    n = len(order)
    cols = min(n, per) if horizontal else math.ceil(n / per)
    rows = math.ceil(n / per) if horizontal else min(n, per)
    tw, th = cols * cw + (cols - 1) * px, rows * ch + (rows - 1) * py
    x0 = {"Left": 0, "Center": (pw - tw) / 2, "Right": pw - tw}.get(halign, 0)
    y0 = {"Top": 0, "Center": (ph - th) / 2, "Bottom": ph - th}.get(valign, 0)
    for i, it in enumerate(order):
        a, b = (i % per, i // per) if horizontal else (i // per, i % per)
        out[id(it)] = (x0 + a * (cw + px), y0 + b * (ch + py), cw, ch)
    return out


def _lay(node, tx, ty, k, pw, ph, clip, gui, depth, out, forced=None):
    p = node["p"]
    if not boolp(p, "Visible", True):
        return
    if forced is not None:
        x, y, w, h = forced
        ax = ay = 0.0
    else:
        w, h = _size(node, pw, ph)
        psx, pox, psy, poy = u2(p, "Position")
        ax, ay = v2(p, "AnchorPoint", (0, 0))
        x = psx * pw + pox - ax * w
        y = psy * ph + poy - ay * h
    s = _scale_of(node)
    if s != 1.0:
        cx, cy = x + ax * w, y + ay * h
        x, y = cx - ax * w * s, cy - ay * h * s
    X, Y, kk = tx + k * x, ty + k * y, k * s
    box = Box(node, X, Y, w * kk, h * kk, kk, clip, gui, depth)
    out.append(box)

    # What its children are laid out in.
    pad = kid(node, "UIPadding")
    pl = pt = pr = pb = 0.0
    if pad:
        pp = pad["p"]
        sl, ol = udim(pp, "PaddingLeft"); sr, orr = udim(pp, "PaddingRight")
        st, ot = udim(pp, "PaddingTop"); sb, ob = udim(pp, "PaddingBottom")
        pl, pr = sl * w + ol, sr * w + orr
        pt, pb = st * h + ot, sb * h + ob
    cw, ch = max(0.0, w - pl - pr), max(0.0, h - pt - pb)
    ctx, cty = X + kk * pl, Y + kk * pt
    child_clip = clip
    if node["cls"] == "ScrollingFrame" or boolp(p, "ClipsDescendants", False):
        r = (X, Y, X + w * kk, Y + h * kk)
        child_clip = r if clip is None else (max(r[0], clip[0]), max(r[1], clip[1]),
                                             min(r[2], clip[2]), min(r[3], clip[3]))
    if node["cls"] == "ScrollingFrame":
        csx, cox, csy, coy = u2(p, "CanvasSize", (0, 0, 2, 0))
        cw, ch = csx * w + cox, csy * h + coy
        cpx, cpy = v2(p, "CanvasPosition", (0, 0))
        ctx, cty = ctx - kk * cpx, cty - kk * cpy

    guis = [c for c in node["kids"] if c["cls"] in GUI_CLASSES]
    flow = _flow(node, cw, ch, [c for c in guis if boolp(c["p"], "Visible", True)])
    ordered = sorted(enumerate(guis), key=lambda t: (num(t[1]["p"], "ZIndex", 1), t[0]))
    for _, c in ordered:
        _lay(c, ctx, cty, kk, cw, ch, child_clip, gui, depth + 1, out, flow.get(id(c)))


def layout(tree_or_guis, W, H, inset=TOPBAR):
    """Every visible GuiObject, in draw order, as Boxes in screen pixels.

    Takes a dumped PlayerGui (or a list of dumped ScreenGuis)."""
    guis = tree_or_guis if isinstance(tree_or_guis, list) else [
        c for c in tree_or_guis["kids"] if c["cls"] == "ScreenGui"]
    guis = [g for g in guis if boolp(g["p"], "Enabled", True)]
    guis.sort(key=lambda g: num(g["p"], "DisplayOrder", 0))
    out = []
    for g in guis:
        top = 0 if boolp(g["p"], "IgnoreGuiInset", False) else inset
        kids = [c for c in g["kids"] if c["cls"] in GUI_CLASSES]
        kids = sorted(enumerate(kids), key=lambda t: (num(t[1]["p"], "ZIndex", 1), t[0]))
        for _, c in kids:
            _lay(c, 0.0, float(top), 1.0, float(W), float(H - top), None, g["name"], 0, out)
    return out


# ---------------------------------------------------------------------------
# Drawing
# ---------------------------------------------------------------------------
FONT_DIR = Path("/usr/share/fonts/opentype/inter")
EMOJI_FONT = Path("/usr/share/fonts/truetype/noto/NotoColorEmoji.ttf")
FALLBACK_FONT = Path("/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf")
MONO_FONT = Path("/usr/share/fonts/truetype/dejavu/DejaVuSansMono.ttf")

WEIGHT = {
    "GothamBlack": "Black", "FredokaOne": "Black", "LuckiestGuy": "Black",
    "Bangers": "Black", "GothamBold": "Bold", "SourceSansBold": "Bold",
    "ArialBold": "Bold", "Highway": "Bold", "GothamMedium": "SemiBold",
    "GothamSemibold": "SemiBold", "SourceSansSemibold": "SemiBold",
}
# Gotham sets wider than Inter, and Fredoka One a little wider than Inter
# Black. Drawing Inter at the real font's width keeps a label that only just
# fits in the drawing only just fitting in the game.
GOTHAM_WIDTH = 1.08
FREDOKA_WIDTH = 1.04


def _widen(face):
    if face.startswith("Gotham"):
        return GOTHAM_WIDTH
    if face == "FredokaOne":
        return FREDOKA_WIDTH
    return 1.0

_fonts = {}


def _font(face, size):
    size = max(1, int(round(size)))
    key = (face, size)
    if key not in _fonts:
        if face == "Code":
            path = MONO_FONT
        else:
            path = FONT_DIR / ("Inter-%s.otf" % WEIGHT.get(face, "Regular"))
            if not path.exists():
                path = FALLBACK_FONT
        _fonts[key] = ImageFont.truetype(str(path), size)
    return _fonts[key]


_fallback_fonts = {}


def _fallback(size):
    size = max(1, int(round(size)))
    if size not in _fallback_fonts:
        _fallback_fonts[size] = ImageFont.truetype(str(FALLBACK_FONT), size)
    return _fallback_fonts[size]


_emoji_font = None
_emoji_cache = {}
_has_glyph = {}


def _emoji_img(cluster, size):
    global _emoji_font
    key = (cluster, int(size))
    if key in _emoji_cache:
        return _emoji_cache[key]
    if _emoji_font is None:
        _emoji_font = ImageFont.truetype(str(EMOJI_FONT), 109)
    im = Image.new("RGBA", (160, 140), (0, 0, 0, 0))
    ImageDraw.Draw(im).text((4, 4), cluster, font=_emoji_font, embedded_color=True)
    bb = im.getbbox()
    if bb:
        im = im.crop(bb)
    t = max(1, int(size))
    im = im.resize((max(1, int(im.width * t / max(1, im.height))), t), Image.LANCZOS)
    _emoji_cache[key] = im
    return im


def _is_emoji(ch):
    o = ord(ch)
    if o < 0x2190:
        return False
    if ch in _has_glyph:
        return _has_glyph[ch]
    global _emoji_font
    if _emoji_font is None:
        _emoji_font = ImageFont.truetype(str(EMOJI_FONT), 109)
    try:
        im = Image.new("RGBA", (160, 140), (0, 0, 0, 0))
        ImageDraw.Draw(im).text((4, 4), ch, font=_emoji_font, embedded_color=True)
        missing = Image.new("RGBA", (160, 140), (0, 0, 0, 0))
        ImageDraw.Draw(missing).text((4, 4), "", font=_emoji_font, embedded_color=True)
        ok = im.getbbox() is not None and im.tobytes() != missing.tobytes()
    except Exception:  # noqa: BLE001
        ok = False
    _has_glyph[ch] = ok
    return ok


JOINERS = {"️", "︎", "‍"}


_inter_has = {}


def _in_inter(ch):
    """Inter lacks some symbols (the close cross, the ellipsis); Roblox's own
    font falls back for them, and so does this."""
    if ord(ch) < 0x2000:
        return True
    if ch not in _inter_has:
        f = _font("GothamBold", 40)

        def ink(c):
            im = Image.new("L", (80, 60), 0)
            ImageDraw.Draw(im).text((4, 4), c, font=f, fill=255)
            return im.tobytes()
        _inter_has[ch] = ink(ch) != ink(chr(0x0378))
    return _inter_has[ch]


def _runs(text):
    """Split a line into ("t", text), ("f", fallback) and ("e", emoji) runs."""
    runs, buf, i = [], "", 0
    while i < len(text):
        ch = text[i]
        if ch in JOINERS:
            if runs and runs[-1][0] == "e" and not buf:
                runs[-1] = ("e", runs[-1][1] + ch)
            i += 1
            continue
        if _is_emoji(ch) or not _in_inter(ch):
            if buf:
                runs.append(("t", buf)); buf = ""
            if not _is_emoji(ch):
                runs.append(("f", ch))
                i += 1
                continue
            if runs and runs[-1][0] == "e" and runs[-1][1].endswith("‍"):
                runs[-1] = ("e", runs[-1][1] + ch)
            else:
                runs.append(("e", ch))
        else:
            buf += ch
        i += 1
    if buf:
        runs.append(("t", buf))
    return runs


def _run_width(run, face, size):
    kind, s = run
    if kind == "e":
        return size * 1.15
    if kind == "f":
        return _fallback(size).getlength(s)
    w = _font(face, size).getlength(s)
    return w * _widen(face)


def _line_width(line, face, size):
    return sum(_run_width(r, face, size) for r in _runs(line))


def _wrap(text, face, size, width, wrap):
    lines = []
    for para in text.split("\n"):
        if not wrap:
            lines.append(para)
            continue
        words, cur = para.split(" "), ""
        for wd in words:
            trial = wd if not cur else cur + " " + wd
            if _line_width(trial, face, size) <= width or not cur:
                cur = trial
            else:
                lines.append(cur); cur = wd
        lines.append(cur)
    return lines


def _strip_rich(text):
    return re.sub(r"<[^>]+>", "", text)


def text_fit(node, w, h, k):
    """The text size Roblox would draw at, and the lines it would draw."""
    p = node["p"]
    text = str(p.get("Text", "Label" if node["cls"] != "TextBox" else ""))
    if boolp(p, "RichText", False):
        text = _strip_rich(text)
    face = enum(p, "Font", "Legacy")
    wrap = boolp(p, "TextWrapped", False)
    lim = kid(node, "UITextSizeConstraint")
    mx = num(lim["p"], "MaxTextSize", 100) if lim else 100
    mn = num(lim["p"], "MinTextSize", 1) if lim else 1
    if boolp(p, "TextScaled", False):
        lo, hi, best = 1, int(min(100, mx) * k) or 1, 1
        while lo <= hi:
            mid = (lo + hi) // 2
            lines = _wrap(text, face, mid, w, wrap)
            fits = len(lines) * mid <= h + 0.5 and all(
                _line_width(ln, face, mid) <= w + 0.5 for ln in lines)
            if fits:
                best, lo = mid, mid + 1
            else:
                hi = mid - 1
        size = max(best, mn * k)
    else:
        size = num(p, "TextSize", 14) * k
    return face, size, _wrap(text, face, size, w, wrap)


def _rgba(col, transparency):
    return (col[0], col[1], col[2], int(round(255 * (1 - max(0.0, min(1.0, transparency))))))


def _gradient(node):
    g = kid(node, "UIGradient")
    if not g or not boolp(g["p"], "Enabled", True):
        return None
    seq = g["p"].get("Color")
    cols = []
    if isinstance(seq, list) and seq and seq[0] == "SEQ":
        pts = seq[1:]
        n = len(pts)
        for i, pt in enumerate(pts):
            t = pt[0] if pt[0] >= 0 else (i / (n - 1) if n > 1 else 0)
            cols.append((t, tuple(int(round(c * 255)) for c in pt[1:4])))
    if not cols:
        cols = [(0, (255, 255, 255)), (1, (255, 255, 255))]
    tseq = g["p"].get("Transparency")
    trs = []
    if isinstance(tseq, list) and tseq and tseq[0] == "SEQ":
        pts = tseq[1:]
        n = len(pts)
        for i, pt in enumerate(pts):
            t = pt[0] if pt[0] >= 0 else (i / (n - 1) if n > 1 else 0)
            trs.append((t, pt[1]))
    return cols, trs, num(g["p"], "Rotation", 0)


def _sample(points, t):
    if not points:
        return None
    if t <= points[0][0]:
        return points[0][1]
    for (t0, a), (t1, b) in zip(points, points[1:]):
        if t0 <= t <= t1:
            f = 0 if t1 == t0 else (t - t0) / (t1 - t0)
            if isinstance(a, tuple):
                return tuple(int(round(a[i] + (b[i] - a[i]) * f)) for i in range(3))
            return a + (b - a) * f
    return points[-1][1]


def _fill_layer(w, h, col, transparency, grad):
    """A w*h RGBA tile of the background, gradient applied."""
    w, h = max(1, int(round(w))), max(1, int(round(h)))
    if not grad:
        return Image.new("RGBA", (w, h), _rgba(col, transparency))
    cols, trs, rot = grad
    # Sample along the gradient's axis at a modest resolution, then stretch.
    steps = 64
    strip = Image.new("RGBA", (steps, 1))
    for i in range(steps):
        t = i / (steps - 1)
        gc = _sample(cols, t) or (255, 255, 255)
        gt = _sample(trs, t)
        tr = transparency if gt is None else 1 - (1 - transparency) * (1 - gt)
        strip.putpixel((i, 0), _rgba(tuple(col[j] * gc[j] // 255 for j in range(3)), tr))
    big = max(w, h) * 2
    layer = strip.resize((big, big), Image.BILINEAR).rotate(-rot, resample=Image.BILINEAR)
    left, top = (big - w) // 2, (big - h) // 2
    return layer.crop((left, top, left + w, top + h))


def _mask(w, h, radius):
    m = Image.new("L", (max(1, int(round(w))), max(1, int(round(h)))), 0)
    ImageDraw.Draw(m).rounded_rectangle((0, 0, m.width - 1, m.height - 1),
                                        radius=max(0, int(round(radius))), fill=255)
    return m


def _radius(node, w, h):
    c = kid(node, "UICorner")
    if not c:
        return None
    s, o = udim(c["p"], "CornerRadius", (0, 8))
    return min(min(w, h) / 2, s * min(w, h) + o * (w / max(1e-6, w)))


def _paste(canvas, tile, x, y, clip):
    x, y = int(round(x)), int(round(y))
    if clip:
        cx0, cy0, cx1, cy1 = (int(round(v)) for v in clip)
        l, t = max(0, cx0 - x), max(0, cy0 - y)
        r, b = min(tile.width, cx1 - x), min(tile.height, cy1 - y)
        if r <= l or b <= t:
            return
        tile = tile.crop((l, t, r, b))
        x, y = x + l, y + t
    canvas.alpha_composite(tile, (max(0, x), max(0, y)),
                           (max(0, -x), max(0, -y)))


def _draw_text(canvas, box, face, size, lines, col, tr, stroke, grad):
    p = box.node["p"]
    pad = kid(box.node, "UIPadding")
    x, y, w, h = box.x, box.y, box.w, box.h
    if pad:
        pp = pad["p"]
        sl, ol = udim(pp, "PaddingLeft"); sr, orr = udim(pp, "PaddingRight")
        st, ot = udim(pp, "PaddingTop"); sb, ob = udim(pp, "PaddingBottom")
        uw, uh = w / box.k, h / box.k
        x += (sl * uw + ol) * box.k; w -= (sl * uw + ol + sr * uw + orr) * box.k
        y += (st * uh + ot) * box.k; h -= (st * uh + ot + sb * uh + ob) * box.k
    xa = enum(p, "TextXAlignment", "Center")
    ya = enum(p, "TextYAlignment", "Center")
    lh = size
    total = lh * len(lines)
    top = {"Top": y, "Bottom": y + h - total}.get(ya, y + (h - total) / 2)
    font = _font(face, size)
    widen = _widen(face)
    pad_px = int(size) + 8
    for i, line in enumerate(lines):
        lw = _line_width(line, face, size)
        lx = {"Left": x, "Right": x + w - lw}.get(xa, x + (w - lw) / 2)
        ly = top + i * lh
        tile = Image.new("RGBA", (int(lw / widen) + pad_px * 2 + 4, int(lh) + pad_px * 2), (0, 0, 0, 0))
        d = ImageDraw.Draw(tile)
        cx = pad_px
        for kind, s in _runs(line):
            if kind == "e":
                em = _emoji_img(s, size * 0.95)
                if tr > 0:
                    a = em.getchannel("A").point(lambda v: int(v * (1 - tr)))
                    em = em.copy(); em.putalpha(a)
                tile.alpha_composite(em, (int(cx + size * 0.08 / widen), int(pad_px + (lh - em.height) / 2)))
                cx += size * 1.15 / widen
            elif kind == "f":
                fb = _fallback(size)
                d.text((cx, pad_px + lh / 2), s, font=fb, fill=_rgba(col, tr), anchor="lm")
                cx += fb.getlength(s) / widen
            else:
                kw = {}
                if stroke:
                    kw = {"stroke_width": max(1, int(round(stroke[0] / widen))),
                          "stroke_fill": _rgba(stroke[1], stroke[2])}
                d.text((cx, pad_px + lh / 2), s, font=font, fill=_rgba(col, tr), anchor="lm", **kw)
                cx += font.getlength(s)
        if widen != 1.0:
            tile = tile.resize((int(tile.width * widen), tile.height), Image.LANCZOS)
        _paste(canvas, tile, lx - pad_px * widen, ly - pad_px, box.clip)


def _viewport_blob(canvas, box):
    """A viewport is a 3D model; drawn as a soft blob in the model's colours."""
    colors = []

    def walk(n):
        for c in n["kids"]:
            col = c["p"].get("Color")
            if isinstance(col, list) and col and col[0] == "C3":
                colors.append(tuple(int(v * 255) for v in col[1:4]))
            walk(c)
    walk(box.node)
    if not colors:
        return
    main = max(set(colors), key=colors.count)
    w, h = int(box.w), int(box.h)
    if w < 4 or h < 4:
        return
    tile = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    d = ImageDraw.Draw(tile)
    r = min(w, h) * 0.34
    cx, cy = w / 2, h * 0.55
    d.ellipse((cx - r, cy - r * 0.9, cx + r, cy + r * 0.9), fill=main + (255,),
              outline=tuple(max(0, v - 60) for v in main) + (255,), width=max(1, int(r / 12)))
    hr = r * 0.62
    d.ellipse((cx - hr, cy - r * 1.35, cx + hr, cy - r * 0.15), fill=main + (255,),
              outline=tuple(max(0, v - 60) for v in main) + (255,), width=max(1, int(r / 12)))
    for ex in (-0.25, 0.25):
        er = r * 0.09
        d.ellipse((cx + ex * r - er, cy - r * 0.8 - er, cx + ex * r + er, cy - r * 0.8 + er),
                  fill=(20, 20, 30, 255))
    _paste(canvas, tile, box.x, box.y, box.clip)


def _image_placeholder(canvas, box):
    p = box.node["p"]
    img = str(p.get("Image", ""))
    if not img:
        return
    tr = num(p, "ImageTransparency", 0)
    w, h = int(box.w), int(box.h)
    if w < 2 or h < 2:
        return
    tile = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    d = ImageDraw.Draw(tile)
    if "AvatarHeadShot" in img or "Avatar" in img:
        d.rectangle((0, 0, w, h), fill=(120, 170, 235, 255))
        d.ellipse((w * 0.25, h * 0.18, w * 0.75, h * 0.68), fill=(250, 210, 160, 255))
        d.rectangle((w * 0.25, h * 0.15, w * 0.75, h * 0.32), fill=(70, 45, 30, 255))
        d.ellipse((w * 0.15, h * 0.7, w * 0.85, h * 1.3), fill=(40, 90, 200, 255))
    else:
        tint = c3(p, "ImageColor3", (255, 255, 255))
        d.rectangle((0, 0, w, h), fill=(tint[0] // 2, tint[1] // 2, tint[2] // 2, 160))
        d.line((0, 0, w, h), fill=(255, 255, 255, 90)); d.line((0, h, w, 0), fill=(255, 255, 255, 90))
    if tr > 0:
        tile.putalpha(tile.getchannel("A").point(lambda v: int(v * (1 - tr))))
    r = _radius(box.node, box.w / box.k, box.h / box.k)
    if r:
        m = _mask(w, h, r * box.k)
        tile.putalpha(Image.composite(tile.getchannel("A"), Image.new("L", tile.size, 0), m))
    _paste(canvas, tile, box.x, box.y, box.clip)


def draw(canvas, boxes):
    for box in boxes:
        node, p = box.node, box.node["p"]
        w, h = box.w, box.h
        if w < 0.5 or h < 0.5:
            continue
        uw, uh = w / box.k, h / box.k
        r = _radius(node, uw, uh)
        rr = (r or 0) * box.k
        grad = _gradient(node)
        bt = num(p, "BackgroundTransparency", 0)
        if node["cls"] == "ViewportFrame":
            bt = num(p, "BackgroundTransparency", 0)
        if bt < 1:
            col = c3(p, "BackgroundColor3", (163, 162, 165))
            tile = _fill_layer(w, h, col, bt, grad)
            if rr > 0:
                m = _mask(tile.width, tile.height, rr)
                tile.putalpha(Image.composite(tile.getchannel("A"), Image.new("L", tile.size, 0), m))
            elif num(p, "BorderSizePixel", 1) > 0 and node["cls"] != "ScrollingFrame":
                bc = c3(p, "BorderColor3", (27, 42, 53))
                ImageDraw.Draw(tile).rectangle((0, 0, tile.width - 1, tile.height - 1),
                                               outline=_rgba(bc, bt))
            _paste(canvas, tile, box.x, box.y, box.clip)

        text_stroke = None
        for s in node["kids"]:
            if s["cls"] != "UIStroke" or not boolp(s["p"], "Enabled", True):
                continue
            sp = s["p"]
            th = num(sp, "Thickness", 1) * box.k
            sc = c3(sp, "Color", (0, 0, 0))
            st = num(sp, "Transparency", 0)
            mode = enum(sp, "ApplyStrokeMode", "Contextual")
            if node["cls"] in TEXT_CLASSES and mode == "Contextual":
                text_stroke = (th, sc, st)
                continue
            pad = int(math.ceil(th)) + 1
            tw, thh = int(round(w)) + pad * 2, int(round(h)) + pad * 2
            ring = Image.new("L", (tw, thh), 0)
            dr = ImageDraw.Draw(ring)
            dr.rounded_rectangle((pad - th, pad - th, pad + w + th - 1, pad + h + th - 1),
                                 radius=max(0, int(rr + th)), fill=255)
            dr.rounded_rectangle((pad, pad, pad + w - 1, pad + h - 1), radius=max(0, int(rr)), fill=0)
            tile = Image.new("RGBA", (tw, thh), _rgba(sc, st))
            tile.putalpha(Image.composite(Image.new("L", tile.size, int(255 * (1 - st))),
                                          Image.new("L", tile.size, 0), ring))
            _paste(canvas, tile, box.x - pad, box.y - pad, box.clip)

        if node["cls"] in IMAGE_CLASSES:
            _image_placeholder(canvas, box)
        if node["cls"] == "ViewportFrame":
            _viewport_blob(canvas, box)
        if node["cls"] in TEXT_CLASSES:
            face, size, lines = text_fit(node, w, h, box.k)
            col = c3(p, "TextColor3", (27, 42, 53))
            tr = num(p, "TextTransparency", 0)
            if text_stroke is None and num(p, "TextStrokeTransparency", 1) < 1:
                text_stroke = (max(1.0, size / 16), c3(p, "TextStrokeColor3", (0, 0, 0)),
                               num(p, "TextStrokeTransparency", 1))
            if lines and any(ln.strip() for ln in lines) and tr < 1:
                _draw_text(canvas, box, face, size, lines, col, tr, text_stroke, grad)


def backdrop(W, H, image=None):
    """Something for the HUD to sit on: a render of the world, or a sky."""
    if image and Path(image).exists():
        im = Image.open(image).convert("RGBA")
        # render_iso writes a caption along the bottom; it is not the world.
        im = im.crop((0, 0, im.width, im.height - 40))
        s = max(W / im.width, H / im.height)
        im = im.resize((int(im.width * s) + 1, int(im.height * s) + 1), Image.LANCZOS)
        l, t = (im.width - W) // 2, (im.height - H) // 2
        return im.crop((l, t, l + W, t + H))
    im = Image.new("RGBA", (W, H))
    d = ImageDraw.Draw(im)
    horizon = int(H * 0.45)
    for yy in range(H):
        if yy < horizon:
            f = yy / max(1, horizon)
            c = (int(110 + 60 * f), int(170 + 50 * f), int(235 + 10 * f))
        else:
            f = (yy - horizon) / max(1, H - horizon)
            c = (int(95 - 30 * f), int(170 - 50 * f), int(70 - 25 * f))
        d.line((0, yy, W, yy), fill=c + (255,))
    return im


def render(lua, mock, gui, W, H, dest, bg=None, inset=TOPBAR):
    boxes = layout(dump(lua, gui), W, H, inset)
    canvas = backdrop(W, H, bg)
    draw(canvas, boxes)
    # Roblox's own buttons, so anything drawn under them shows as covered.
    d = ImageDraw.Draw(canvas)
    for i in range(2):
        x = 12 + i * 52
        d.rounded_rectangle((x, 8, x + 44, 52), radius=12, fill=(20, 20, 24, 210))
    canvas.convert("RGB").save(dest)
    return boxes


def set_screen(lua, W, H):
    lua.execute("""
        local cam = workspace.CurrentCamera or Instance.new("Camera")
        cam.ViewportSize = Vector2.new(%d, %d)
        workspace.CurrentCamera = cam
    """ % (W, H))
    mp = lua.globals()._G.MysticPets
    if mp is not None and mp.layoutHUD is not None:
        mp.layoutHUD()


DEMO_LUA = r"""
function(dm, ps, player)
    -- A player some way in: six pets, two rebirths, VIP. Only for looking at.
    local d = dm.GetData(player)
    d.Coins = 1250000; d.Gems = 8450; d.TotalCoinsEarned = 3200000
    d.GP_VIP = true; d.GP_PetSlots = true; d.GP_AutoCollect = true
    d.Rebirths = 2; d.RebirthMultiplier = 2
    local list = {
        { "Void Serpent", "Mythic" }, { "snow ram", "Legendary" }, { "dragon", "Epic", "Shiny" },
        { "panda", "Rare" }, { "fox", "Uncommon", "Golden" }, { "cat", "Common" },
    }
    d.EquippedPets = {}
    for i, e in ipairs(list) do
        ps.GrantPet(player, { name = e[1], rarity = e[2], mutation = e[3],
            uniqueId = "demo" .. i, locked = (i == 2) }, true)
        table.insert(d.EquippedPets, "demo" .. i)
    end
    game.ReplicatedStorage.Remotes.DataUpdated.OnClientEvent:Fire(d)
end
"""


def demo(lua, mock):
    sss = mock["ServerScriptService"]
    holder = sss["FindFirstChild"](sss, "Server", True)
    dm = mock["MODULES"][holder["FindFirstChild"](holder, "DataManager")]
    ps = mock["MODULES"][holder["FindFirstChild"](holder, "PetService")]
    lua.eval(DEMO_LUA)(dm, ps, mock["Players"].LocalPlayer)


def main():
    import check_client
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    flags = sys.argv[1:]
    dest = Path(args[0]) if args else ROOT / "build/gui.png"
    W = int(args[1]) if len(args) > 1 else 1536
    H = int(args[2]) if len(args) > 2 else 1024
    open_panel = None
    bg = None
    for i, f in enumerate(flags):
        if f == "--open" and i + 1 < len(flags):
            open_panel = flags[i + 1]
        if f == "--bg" and i + 1 < len(flags):
            bg = flags[i + 1]
    import io
    import contextlib
    with contextlib.redirect_stdout(io.StringIO()):
        lua, mock, gui, _ = check_client.boot(loopback=True, screen=(W, H))
    if lua is None:
        sys.exit("the client did not boot; run check_client.py to see why")
    lua.execute("task.spawn = function() end; task.defer = function() end")
    if lua.globals().__DELIVER is not None:
        lua.globals().__DELIVER()
    # The loading screen is still up in a booted client: the fade that removes
    # it runs on a two-second delay the harness never lets pass.
    lua.execute("""
        local g = game:GetService("Players").LocalPlayer.PlayerGui
        for _, n in ipairs({"LoadScreen", "WelcomeGui", "StarPetsBuildBadge"}) do
            local x = g:FindFirstChild(n); if x then x:Destroy() end
        end
    """)
    set_screen(lua, W, H)
    if "--demo" in flags:
        demo(lua, mock)
    if open_panel:
        ui = lua.eval('game:GetService("StarterPlayer").StarterPlayerScripts.Client.UI')
        ctrl = mock["MODULES"][ui["FindFirstChild"](ui, "UIController")]
        data = lua.globals()._G.MysticPets.getData()
        ctrl.Open(open_panel, data)
    mock["FLUSH_TWEENS"]()
    set_screen(lua, W, H)
    dest.parent.mkdir(parents=True, exist_ok=True)
    boxes = render(lua, mock, gui, W, H, dest, bg)
    print("drew %d GUI objects at %dx%d -> %s" % (len(boxes), W, H, dest))


if __name__ == "__main__":
    main()
