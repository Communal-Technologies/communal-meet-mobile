"""Renders the hand-authored SVGs to a PNG contact sheet, so they can be looked at.

This box has no SVG rasteriser and no way to install one, and shipping artwork
nobody has seen is how you find out at review that a path is inside out. So this
is a deliberately small interpreter for the only SVG subset assets/images uses:
path (M, L, H, V, A, Z, absolute and relative), rect with rx, circle, and the
stroke/fill attributes those carry. It is a checking tool, not a renderer —
Flutter draws these with flutter_svg, which supports all of SVG.

    python3 tool/preview_svg.py            # writes tool/preview.png
"""

import glob
import math
import os
import re
import xml.etree.ElementTree as ET

from PIL import Image, ImageDraw

SS = 4  # supersample, then downsample: the only antialiasing Pillow will give us
NS = "{http://www.w3.org/2000/svg}"
NUM = re.compile(r"[-+]?[0-9]*\.?[0-9]+(?:[eE][-+]?[0-9]+)?")
CMD = re.compile(r"([MmLlHhVvAaZzCc])([^MmLlHhVvAaZzCc]*)")


def arc_points(x0, y0, rx, ry, rot, large, sweep, x, y, steps=48):
    """Endpoint-parameterised elliptical arc → polyline, per the SVG spec's appendix."""
    if rx == 0 or ry == 0 or (x0, y0) == (x, y):
        return [(x, y)]
    phi = math.radians(rot)
    dx2, dy2 = (x0 - x) / 2, (y0 - y) / 2
    x1 = math.cos(phi) * dx2 + math.sin(phi) * dy2
    y1 = -math.sin(phi) * dx2 + math.cos(phi) * dy2
    rx, ry = abs(rx), abs(ry)
    lam = x1 * x1 / (rx * rx) + y1 * y1 / (ry * ry)
    if lam > 1:
        rx, ry = rx * math.sqrt(lam), ry * math.sqrt(lam)
    num = rx * rx * ry * ry - rx * rx * y1 * y1 - ry * ry * x1 * x1
    den = rx * rx * y1 * y1 + ry * ry * x1 * x1
    co = math.sqrt(max(0.0, num / den)) * (-1 if large == sweep else 1)
    cx1, cy1 = co * rx * y1 / ry, -co * ry * x1 / rx
    cx = math.cos(phi) * cx1 - math.sin(phi) * cy1 + (x0 + x) / 2
    cy = math.sin(phi) * cx1 + math.cos(phi) * cy1 + (y0 + y) / 2

    def ang(ux, uy, vx, vy):
        d = (ux * vx + uy * vy) / (math.hypot(ux, uy) * math.hypot(vx, vy))
        a = math.acos(max(-1.0, min(1.0, d)))
        return -a if ux * vy - uy * vx < 0 else a

    th0 = ang(1, 0, (x1 - cx1) / rx, (y1 - cy1) / ry)
    dth = ang((x1 - cx1) / rx, (y1 - cy1) / ry, (-x1 - cx1) / rx, (-y1 - cy1) / ry)
    if not sweep and dth > 0:
        dth -= 2 * math.pi
    elif sweep and dth < 0:
        dth += 2 * math.pi
    pts = []
    for i in range(1, steps + 1):
        th = th0 + dth * i / steps
        px = math.cos(phi) * rx * math.cos(th) - math.sin(phi) * ry * math.sin(th) + cx
        py = math.sin(phi) * rx * math.cos(th) + math.cos(phi) * ry * math.sin(th) + cy
        pts.append((px, py))
    return pts


def cubic(p0, p1, p2, p3, steps=24):
    out = []
    for i in range(1, steps + 1):
        t = i / steps
        u = 1 - t
        out.append(
            (
                u ** 3 * p0[0] + 3 * u * u * t * p1[0] + 3 * u * t * t * p2[0] + t ** 3 * p3[0],
                u ** 3 * p0[1] + 3 * u * u * t * p1[1] + 3 * u * t * t * p2[1] + t ** 3 * p3[1],
            )
        )
    return out


def subpaths(d):
    """A path's `d` as a list of (points, closed)."""
    out, pts, start, cur = [], [], (0.0, 0.0), (0.0, 0.0)
    for cmd, body in CMD.findall(d):
        n = [float(v) for v in NUM.findall(body)]
        rel = cmd.islower()
        c = cmd.upper()
        if c == "M":
            if len(pts) > 1:
                out.append((pts, False))
            x, y = n[0], n[1]
            cur = (cur[0] + x, cur[1] + y) if rel else (x, y)
            start, pts = cur, [cur]
            for i in range(2, len(n), 2):  # implicit lineto
                x, y = n[i], n[i + 1]
                cur = (cur[0] + x, cur[1] + y) if rel else (x, y)
                pts.append(cur)
        elif c in "LHV":
            vals = n if c == "L" else [v for v in n]
            i = 0
            while i < len(vals):
                if c == "L":
                    x, y = vals[i], vals[i + 1]
                    cur = (cur[0] + x, cur[1] + y) if rel else (x, y)
                    i += 2
                elif c == "H":
                    x = vals[i]
                    cur = (cur[0] + x, cur[1]) if rel else (x, cur[1])
                    i += 1
                else:
                    y = vals[i]
                    cur = (cur[0], cur[1] + y) if rel else (cur[0], y)
                    i += 1
                pts.append(cur)
        elif c == "A":
            for i in range(0, len(n), 7):
                rx, ry, rot, la, sw, x, y = n[i : i + 7]
                end = (cur[0] + x, cur[1] + y) if rel else (x, y)
                pts += arc_points(cur[0], cur[1], rx, ry, rot, int(la), int(sw), *end)
                cur = end
        elif c == "C":
            for i in range(0, len(n), 6):
                a, b, e = n[i : i + 2], n[i + 2 : i + 4], n[i + 4 : i + 6]
                if rel:
                    a = [cur[0] + a[0], cur[1] + a[1]]
                    b = [cur[0] + b[0], cur[1] + b[1]]
                    e = [cur[0] + e[0], cur[1] + e[1]]
                pts += cubic(cur, a, b, e)
                cur = (e[0], e[1])
        elif c == "Z":
            out.append((pts + [start], True))
            pts, cur = [start], start
    if len(pts) > 1:
        out.append((pts, False))
    return out


def rgba(colour, opacity=1.0):
    if not colour or colour in ("none", "currentColor"):
        colour = "#6B7280" if colour == "currentColor" else None
    if colour is None:
        return None
    h = colour.lstrip("#")
    return tuple(int(h[i : i + 2], 16) for i in (0, 2, 4)) + (int(255 * opacity),)


def render(path, box):
    tree = ET.parse(path)
    root = tree.getroot()
    vx, vy, vw, vh = [float(v) for v in root.get("viewBox").split()]
    scale = min(box / vw, box / vh) * SS
    img = Image.new("RGBA", (box * SS, box * SS), (0, 0, 0, 0))
    dr = ImageDraw.Draw(img)
    ox = (box * SS - vw * scale) / 2
    oy = (box * SS - vh * scale) / 2

    def P(x, y):
        return ((x - vx) * scale + ox, (y - vy) * scale + oy)

    def walk(el, inherited):
        attrs = dict(inherited)
        attrs.update({k: v for k, v in el.attrib.items() if k != "d"})
        tag = el.tag.replace(NS, "")
        stroke = rgba(attrs.get("stroke"), float(attrs.get("stroke-opacity", 1)))
        fill = rgba(attrs.get("fill"), float(attrs.get("fill-opacity", 1)))
        w = max(1, round(float(attrs.get("stroke-width", 1)) * scale))
        rnd = attrs.get("stroke-linecap") == "round" or attrs.get("stroke-linejoin") == "round"

        shapes = []
        if tag == "path":
            shapes = subpaths(el.get("d"))
        elif tag == "rect":
            x, y = float(attrs["x"]), float(attrs["y"])
            rw, rh = float(attrs["width"]), float(attrs["height"])
            r = float(attrs.get("rx", 0))
            d = (
                f"M{x + r} {y}H{x + rw - r}A{r} {r} 0 0 1 {x + rw} {y + r}"
                f"V{y + rh - r}A{r} {r} 0 0 1 {x + rw - r} {y + rh}"
                f"H{x + r}A{r} {r} 0 0 1 {x} {y + rh - r}"
                f"V{y + r}A{r} {r} 0 0 1 {x + r} {y}Z"
            )
            shapes = subpaths(d)
        elif tag == "circle":
            cx, cy, r = float(attrs["cx"]), float(attrs["cy"]), float(attrs["r"])
            pts = [
                (cx + r * math.cos(2 * math.pi * i / 64), cy + r * math.sin(2 * math.pi * i / 64))
                for i in range(65)
            ]
            shapes = [(pts, True)]

        for pts, closed in shapes:
            sp = [P(*p) for p in pts]
            if fill and closed:
                dr.polygon(sp, fill=fill)
            if stroke:
                dr.line(sp, fill=stroke, width=w, joint="curve" if rnd else None)
                if rnd:
                    for px, py in (sp[0], sp[-1]):
                        dr.ellipse([px - w / 2, py - w / 2, px + w / 2, py + w / 2], fill=stroke)
        for child in el:
            walk(child, attrs)

    walk(root, {})
    return img.resize((box, box), Image.LANCZOS)


here = os.path.dirname(os.path.abspath(__file__))
os.chdir(os.path.join(here, ".."))
files = sorted(glob.glob("assets/images/*.svg"))
BOX, PAD = 176, 16
cols = 4
rows = (len(files) + cols - 1) // cols
sheet = Image.new("RGBA", (cols * (BOX + PAD) + PAD, rows * (BOX + PAD + 18) + PAD), (247, 247, 251, 255))
dark = Image.new("RGBA", (BOX, BOX), (11, 11, 15, 255))
for i, f in enumerate(files):
    cell = dark.copy() if "waiting_room" in f else Image.new("RGBA", (BOX, BOX), (255, 255, 255, 255))
    art = render(f, BOX)
    cell.alpha_composite(art)
    x = PAD + (i % cols) * (BOX + PAD)
    y = PAD + (i // cols) * (BOX + PAD + 18)
    sheet.paste(cell, (x, y))
    ImageDraw.Draw(sheet).text((x + 2, y + BOX + 4), os.path.basename(f), fill=(107, 114, 128, 255))
sheet.save("tool/preview.png")
print("tool/preview.png", sheet.size, f"{len(files)} files")
