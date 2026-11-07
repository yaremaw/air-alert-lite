"""Adds the air defence to the itch cover (itch/cover-pixel.png): two searchlights from the
rooftops crossing on the big drone, anti-aircraft tracer fire climbing towards the small
drones, a flak burst and an interceptor missile rising on a smoke trail. Everything is
drawn at a quarter of the size and scaled up without smoothing, so it sits on the same
pixel grid as the art.

    python tools/itch_cover_fx.py itch/cover-pixel.png itch/cover-defence.png
"""
import math
import sys

import numpy as np
from PIL import Image, ImageFilter

PX = 4                                  # one art pixel is this many image pixels


def smooth(e0, e1, x):
    t = np.clip((x - e0) / (e1 - e0), 0, 1)
    return t * t * (3 - 2 * t)


def beam(w, h, origin, target, half_angle, length, strength, stop=False):
    """A searchlight cone at low resolution: bright near the lamp, fading with distance.
    With stop, it ends where it meets the target (the drone's underside) in a lit patch."""
    ys, xs = np.mgrid[0:h, 0:w].astype(np.float32)
    ox, oy = origin[0] / PX, origin[1] / PX
    tx, ty = target[0] / PX, target[1] / PX
    ang = math.atan2(ty - oy, tx - ox)
    dx, dy = xs - ox, ys - oy
    dist = np.sqrt(dx * dx + dy * dy) + 1e-3
    off = np.abs(np.arctan2(dy, dx) - ang)
    off = np.minimum(off, 2 * math.pi - off)
    cone = 1 - smooth(half_angle * 0.35, half_angle, off)
    fall = np.clip(1 - dist / (length / PX), 0, 1) ** 1.1
    core = 1 - smooth(0, half_angle * 0.4, off)
    v = strength * cone * fall * (0.6 + 0.4 * core)
    if stop:
        hit = math.hypot(tx - ox, ty - oy)
        v *= 1 - smooth(hit - 1.5, hit + 1.0, dist)
        spot = np.exp(-(((xs - tx) / 17.0) ** 2 + ((ys - ty) / 4.5) ** 2))
        v += 0.26 * spot
    lamp = np.exp(-(dist ** 2) / (2 * 1.6 ** 2))
    v += 1.4 * lamp
    return np.round(v * 9) / 9         # banded, like hand-placed pixel shading


def curve(p0, p1, p2, n):
    return [((1 - t) ** 2 * p0[0] + 2 * (1 - t) * t * p1[0] + t * t * p2[0],
             (1 - t) ** 2 * p0[1] + 2 * (1 - t) * t * p1[1] + t * t * p2[1]) for t in np.linspace(0, 1, n)]


def dot(layer, x, y, colour, a=1.0):
    xi, yi = int(round(x / PX)), int(round(y / PX))
    if 0 <= yi < layer.shape[0] and 0 <= xi < layer.shape[1]:
        layer[yi, xi] = np.maximum(layer[yi, xi], np.array(colour) * a)


def main():
    src, out = sys.argv[1], sys.argv[2]
    img = np.asarray(Image.open(src).convert("RGB"), np.float32) / 255
    H, W = img.shape[:2]
    w, h = W // PX, H // PX
    add = np.zeros((h, w, 3), np.float32)       # light, added on top
    smoke = np.zeros((h, w), np.float32)        # smoke, laid over

    # Two searchlights from the rooftops, crossing under the big drone and lighting its belly.
    cool = np.array([0.80, 0.86, 1.0], np.float32)
    for origin, target, half, length, k, stop in (((328, 548), (520, 428), 0.13, 900, 0.36, True),
                                                  ((884, 518), (690, 424), 0.13, 900, 0.36, True)):
        add += beam(w, h, origin, target, half, length, k, stop)[..., None] * cool

    # Tracer fire: dashed streams climbing from the city towards the small drones.
    hot = (1.0, 0.72, 0.30)
    for p0, p1, p2, n in (((700, 772), (640, 690), (566, 604), 34),
                          ((470, 770), (480, 680), (478, 572), 30),
                          ((760, 776), (850, 640), (918, 478), 40),
                          ((735, 774), (800, 660), (860, 520), 34)):
        pts = curve(p0, p1, p2, n)
        for i, (x, y) in enumerate(pts):
            if (i // 2) % 3 == 2:           # dashes: two lit, one gap
                continue
            fade = 0.45 + 0.55 * (1 - i / n)
            dot(add, x, y, hot, fade)
    # A flak burst just short of the drone on the right.
    for a in range(0, 360, 30):
        r = 18
        dot(add, 905 + r * math.cos(math.radians(a)), 492 + r * math.sin(math.radians(a)), (1.0, 0.6, 0.25), 0.8)
    for a in range(0, 360, 60):
        dot(add, 905 + 8 * math.cos(math.radians(a)), 492 + 8 * math.sin(math.radians(a)), (1.0, 0.9, 0.6), 1.0)

    # The interceptor: a smoke trail from behind the city up towards the drone's right wing.
    trail = curve((782, 790), (790, 620), (742, 476), 80)
    rng = np.random.default_rng(5)
    for i, (x, y) in enumerate(trail[:-3]):
        t = i / len(trail)
        rad = 0.8 + 3.6 * (1 - t) ** 0.8 + rng.uniform(-0.4, 0.4) * (1 - t)
        cx, cy = x / PX + rng.normal(0, 0.35 * (1 - t)) + 2.0 * (1 - t) ** 2, y / PX
        ys, xs = np.ogrid[0:h, 0:w]
        m = ((xs - cx) ** 2 + (ys - cy) ** 2) <= rad * rad
        smoke[m] = np.maximum(smoke[m], 0.30 + 0.30 * t)
    hx, hy = trail[-1]
    dot(add, hx, hy, (1.0, 1.0, 1.0), 1.0)
    for ddx, ddy in ((PX, 0), (-PX, 0), (0, PX), (0, -PX)):
        dot(add, hx + ddx, hy + ddy, (1.0, 0.85, 0.6), 0.9)
    tx, ty = trail[-5]
    dot(add, tx, ty, (1.0, 0.55, 0.2), 0.9)

    # Up to full size on the pixel grid, then a soft glow round the bright bits.
    big_add = np.repeat(np.repeat(add, PX, 0), PX, 1)[:H, :W]
    big_smoke = np.repeat(np.repeat(smoke, PX, 0), PX, 1)[:H, :W]
    smoke_col = np.array([0.52, 0.50, 0.58], np.float32)
    out_img = img * (1 - big_smoke[..., None]) + smoke_col * big_smoke[..., None]
    glow_src = Image.fromarray((np.clip(big_add, 0, 1) * 255).astype(np.uint8))
    glow = np.asarray(glow_src.filter(ImageFilter.GaussianBlur(10)), np.float32) / 255
    out_img = out_img + big_add * 0.9 + glow * 0.55
    Image.fromarray((np.clip(out_img, 0, 1) * 255).astype(np.uint8)).save(out)
    print("wrote", out)


if __name__ == "__main__":
    main()
