#!/usr/bin/env python3
"""Generate PinDrop's original 1024x1024 app icon (map pin on a gradient).

Pure PIL drawing code, no external artwork. Usage:
    python3 scripts/make_icon.py [output.png]
Default output: RoamControl/Resources/Assets.xcassets/AppIcon.appiconset/PinDrop-AppIcon.png
"""
import math
import sys
from pathlib import Path

from PIL import Image, ImageChops, ImageDraw, ImageFilter

SIZE = 1024
SS = 2  # supersampling factor for smooth edges
S = SIZE * SS

ROOT = Path(__file__).resolve().parent.parent
DEFAULT_OUT = ROOT / "RoamControl/Resources/Assets.xcassets/AppIcon.appiconset/PinDrop-AppIcon.png"


def lerp(a, b, t):
    return tuple(round(a[i] + (b[i] - a[i]) * t) for i in range(3))


def gradient_background():
    """Diagonal gradient: teal (top-left) -> indigo -> violet (bottom-right)."""
    c0, c1, c2 = (24, 214, 190), (36, 110, 235), (112, 62, 220)
    small = 256
    img = Image.new("RGB", (small, small))
    px = img.load()
    for y in range(small):
        for x in range(small):
            t = (x + y) / (2 * (small - 1))
            px[x, y] = lerp(c0, c1, t / 0.5) if t < 0.5 else lerp(c1, c2, (t - 0.5) / 0.5)
    return img.resize((S, S), Image.BICUBIC)


def pin_mask(cx, cy_head, r):
    """Teardrop map pin: circle head + tangent lines converging on the tip."""
    m = Image.new("L", (S, S), 0)
    d = ImageDraw.Draw(m)
    tip_y = cy_head + r * 2.35
    d.ellipse((cx - r, cy_head - r, cx + r, cy_head + r), fill=255)
    # tangent points from tip to the circle
    dist = tip_y - cy_head
    ang = math.acos(r / dist)
    pts = []
    for sign in (-1, 1):
        a = math.pi / 2 + sign * ang  # angle measured from +x, y down
        pts.append((cx + r * math.cos(a), cy_head + r * math.sin(a)))
    d.polygon([pts[0], (cx, tip_y), pts[1], (cx, cy_head)], fill=255)
    return m, tip_y


def main():
    out = Path(sys.argv[1]) if len(sys.argv) > 1 else DEFAULT_OUT
    img = gradient_background().convert("RGBA")

    cx = S / 2
    r = S * 0.19
    cy_head = S * 0.32
    mask, tip_y = pin_mask(cx, cy_head, r)

    # ripple rings around the landing point
    ring = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    rd = ImageDraw.Draw(ring)
    for i, (rx, alpha) in enumerate(((0.25, 130), (0.37, 75))):
        w = S * rx
        h = w * 0.34
        rd.ellipse((cx - w, tip_y - h, cx + w, tip_y + h),
                   outline=(255, 255, 255, alpha), width=int(S * 0.011))
    img = Image.alpha_composite(img, ring)

    # soft drop shadow under pin
    shadow = Image.new("L", (S, S), 0)
    shadow.paste(mask, (0, int(S * 0.018)))
    shadow = shadow.filter(ImageFilter.GaussianBlur(S * 0.02))
    shadow_rgba = Image.new("RGBA", (S, S), (10, 20, 80, 0))
    shadow_rgba.putalpha(shadow.point(lambda v: int(v * 0.6)))
    img = Image.alpha_composite(img, shadow_rgba)

    # pin body: vertical white -> warm coral gradient
    body = Image.new("RGB", (S, S))
    bd = ImageDraw.Draw(body)
    top, bot = (255, 255, 255), (255, 214, 224)
    y0, y1 = int(cy_head - r), int(tip_y)
    for y in range(S):
        t = min(max((y - y0) / max(y1 - y0, 1), 0), 1)
        bd.line([(0, y), (S, y)], fill=lerp(top, bot, t))
    body_rgba = body.convert("RGBA")
    body_rgba.putalpha(mask)
    img = Image.alpha_composite(img, body_rgba)

    # hole in the head (shows gradient-coloured dot)
    hole_r = r * 0.42
    hole = Image.new("L", (S, S), 0)
    ImageDraw.Draw(hole).ellipse((cx - hole_r, cy_head - hole_r, cx + hole_r, cy_head + hole_r), fill=255)
    dot = gradient_background().convert("RGBA")
    dot.putalpha(hole)
    img = Image.alpha_composite(img, dot)

    # glossy highlight on the head
    hl = Image.new("L", (S, S), 0)
    ImageDraw.Draw(hl).ellipse((cx - r * 0.78, cy_head - r * 0.86, cx - r * 0.18, cy_head - r * 0.30), fill=90)
    hl = hl.filter(ImageFilter.GaussianBlur(S * 0.012))
    hl = ImageChops.multiply(hl, mask)
    white = Image.new("RGBA", (S, S), (255, 255, 255, 0))
    white.putalpha(hl)
    img = Image.alpha_composite(img, white)

    final = img.convert("RGB").resize((SIZE, SIZE), Image.LANCZOS)  # no alpha channel (App Store requirement)
    out.parent.mkdir(parents=True, exist_ok=True)
    final.save(out, "PNG", optimize=True)
    print(f"wrote {out} {final.size} mode={final.mode}")


if __name__ == "__main__":
    main()
