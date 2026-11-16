"""The YouTube channel banner, 2560x1440.

Kept simple: the logo, PLAY FREE IN YOUR BROWSER and one drone over the burning factory.
YouTube crops the banner per device: TVs show all of it, desktops a 2560x423 strip through
the middle, phones only the 1546x423 middle of that strip, so all three sit in that box.

    python tools/channel_banner.py              writes itch/youtube-banner.jpg
    python tools/channel_banner.py --guides     also a copy with the crop boxes drawn on

The background is itch/outro/background.jpg; the drone is the 3D model from outro_video.py.
"""
import math
import os
import sys

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import voiceover_video as vv  # noqa: E402
import outro_video as ov  # noqa: E402
from voiceover_video import RED, TEXT, font  # noqa: E402

ROOT = vv.ROOT
W, H = 2560, 1440
STRIP = (0, 508, W, 932)          # what a desktop shows
SAFE = (507, 508, 2053, 932)      # what every device shows


def background():
    """The burning factory, scaled up so the fire sits right of centre and dark buildings left."""
    im = Image.open(ov.COVER).convert("RGB")
    s = 1.6
    big = im.resize((int(im.width * s), int(im.height * s)), Image.LANCZOS)
    ox, oy = 0, 560
    return np.asarray(big.crop((ox, oy, ox + W, oy + H)), np.float32)


def light(F):
    """Searchlights, a darker left side for the text, and embers."""
    ys, xs = np.mgrid[0:H // 4, 0:W // 4].astype(np.float32)
    q = np.zeros((H // 4, W // 4, 3), np.float32)
    for sx, a in ((0.36 * W, 0.42), (0.93 * W, -0.38)):
        sy = 1.05 * H
        dx, dy = xs - sx / 4, sy / 4 - ys
        th, dist = np.arctan2(dx, dy), np.hypot(dx, dy)
        d = th - a
        fall = np.exp(-dist / (0.8 * H / 4)) * 0.85 + 0.15
        q += ((np.exp(-(d / 0.022) ** 2) + 0.15 * np.exp(-(d / 0.09) ** 2)) * fall)[..., None] * \
            np.array([95, 110, 150], np.float32)
    up = Image.fromarray(np.clip(q, 0, 255).astype(np.uint8)).resize((W, H), Image.BILINEAR)
    F = F + np.asarray(up, np.float32)
    x = np.arange(W, dtype=np.float32) / W
    shade = 0.40 + 0.60 * np.clip((x - 0.58) / 0.16, 0, 1) ** 1.5
    F *= shade[None, :, None]
    add = Image.new("RGB", (W, H))
    d = ImageDraw.Draw(add)
    rng = np.random.default_rng(11)
    for _ in range(260):
        ex, ey = rng.uniform(0, W), rng.uniform(0, H)
        near = math.exp(-((ex - 0.66 * W) / (0.3 * W)) ** 2)
        b = rng.uniform(0.3, 1.0) * (0.35 + 0.65 * near)
        r = rng.uniform(1.2, 3.6)
        d.ellipse([ex - r, ey - r, ex + r, ey + r], fill=(int(255 * b), int(120 * b), int(40 * b)))
    glow = add.filter(ImageFilter.GaussianBlur(5))
    return F + np.asarray(add, np.float32) + np.asarray(glow, np.float32) * 2.0


def drone(F, cx, cy, span):
    """The 3D drone from the outro, flying at the viewer, lit by the searchlights."""
    sc = ov.Scene.__new__(ov.Scene)
    sc.W, sc.H, sc.f, sc.mesh = W, H, 1.1 * H, ov.drone_mesh()
    z = 2.5 * sc.f / span
    C = np.array([(cx - W / 2) * z / sc.f, -(cy - H / 2) * z / sc.f, z])
    st = dict(C=C, R=ov.orient(C, math.radians(20), math.radians(-10)), span=span)
    acc = [np.zeros((H, W, 3), np.float32), np.zeros((H, W), np.float32), np.zeros((H, W, 3), np.float32)]
    sc.draw_drone(st, 1.0, acc, 1.0)
    F = F * (1 - acc[1][..., None]) + acc[0] + acc[2]
    p = C + st["R"] @ np.array([0.0, -0.21, 0.45])   # the red strobe under the belly
    sx, sy = W / 2 + sc.f * p[0] / p[2], H / 2 - sc.f * p[1] / p[2]
    g = Image.new("RGB", (W, H))
    ImageDraw.Draw(g).ellipse([sx - 5, sy - 5, sx + 5, sy + 5], fill=(255, 190, 60))
    F += np.asarray(g, np.float32) + np.asarray(g.filter(ImageFilter.GaussianBlur(14)), np.float32) * 6 * \
        np.array([1.0, 0.25, 0.2], np.float32)
    return F


def paste(img, spr, x, y):
    img.paste(spr, (int(x), int(y)), spr)


def overlay(img):
    """Just the logo and one line, left of the fire; the channel page shows the link right below."""
    d = ImageDraw.Draw(img, "RGBA")
    logo = Image.open(ov.LOGO).convert("RGBA")
    lw = 1000
    logo = logo.resize((lw, int(logo.height * lw / logo.width)), Image.LANCZOS)
    fb = font(50, "Black")
    block = logo.height + 26 + 56
    x0 = SAFE[0] + 70
    y0 = (SAFE[1] + SAFE[3]) / 2 - block / 2
    glow = Image.new("RGBA", logo.size, (0, 0, 0, 0))
    glow.putalpha(logo.getchannel("A").filter(ImageFilter.GaussianBlur(10)).point(lambda v: v * 0.8))
    paste(img, glow, x0 - 24, y0)
    paste(img, logo, x0 - 24, y0)
    x, y = x0, y0 + logo.height + 26
    for word, col in (("PLAY ", TEXT), ("FREE", RED), (" IN YOUR BROWSER", TEXT)):
        for ch in word:
            d.text((x, y), ch, font=fb, fill=col + (255,))
            x += fb.getlength(ch) + 4


def main():
    out = os.path.join(ROOT, "itch", "youtube-banner.jpg")
    F = light(background())
    dcx, dcy, span = 1830, 690, 290
    F = drone(F, dcx, dcy, span)
    vv.W, vv.H = W, H
    look = vv.Look(5)
    img = Image.fromarray(look.grade(np.clip(F, 0, 255).astype(np.uint8), chroma=2))
    overlay(img)
    img.save(out, quality=93, subsampling=0)
    print("wrote", out, "%.1f MB" % (os.path.getsize(out) / 1e6))
    if "--guides" in sys.argv:
        g = img.copy()
        d = ImageDraw.Draw(g)
        d.rectangle(STRIP, outline=(0, 255, 255), width=4)
        d.rectangle(SAFE, outline=(255, 255, 0), width=4)
        gp = os.path.join(os.path.dirname(out), "youtube-banner-guides.jpg")
        g.save(gp, quality=85)
        print("wrote", gp)


if __name__ == "__main__":
    main()
