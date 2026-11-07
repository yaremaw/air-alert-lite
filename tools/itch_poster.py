"""A poster for Strike Alert: a city at night under a drone and missile attack,
interceptors rising to meet it, the logo below. Drawn from shapes, no
screenshots.

    python tools/itch_poster.py itch

writes cover.png (630x500, the itch.io cover) and poster.png (1260x1000).
"""
import math
import os
import random
import sys

import numpy as np
from PIL import Image, ImageChops, ImageDraw, ImageFilter

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
LOGO = os.path.join(ROOT, "itch", "logo.png")
W, H = 2520, 2000  # drawn at four times the cover, then scaled down

RED = (0xE0, 0x57, 0x4A)
ENEMY = (0xFF, 0x5A, 0x48)
YELLOW = (0xE5, 0xAD, 0x16)
BLUE = (0x4E, 0xA1, 0xFF)
# A delta-wing attack drone from above, nose along +x: body, swept wings with
# fins at the tips, the engine at the back.
DRONE = [(6.5, 0), (4.5, -0.9), (-4.6, -7.6), (-5.6, -7.6), (-5.2, -1.0), (-6.4, -0.7),
         (-6.4, 0.7), (-5.2, 1.0), (-5.6, 7.6), (-4.6, 7.6), (4.5, 0.9)]
# A cruise missile from above: a long body, short wings, tail fins.
CRUISE = [(10, 0), (8.5, -0.9), (1.5, -0.9), (-1, -4), (-2.2, -4), (-1.2, -0.9), (-7, -0.9),
          (-8.2, -2.6), (-9, -2.6), (-9, 2.6), (-8.2, 2.6), (-7, 0.9), (-1.2, 0.9), (-2.2, 4),
          (-1, 4), (1.5, 0.9), (8.5, 0.9)]


def P(x, y):
    return (x * W, y * H)


def shape(pts, at, size, angle):
    c, s = math.cos(angle), math.sin(angle)
    x0, y0 = P(*at)
    return [(x0 + (px * c - py * s) * size, y0 + (px * s + py * c) * size) for px, py in pts]


def light():
    return Image.new("RGB", (W, H), (0, 0, 0))


def glow(base, layer, radii):
    """Screens `layer`, blurred at each radius and sharp, onto `base`: light, not paint."""
    for r in radii:
        base = ImageChops.screen(base, layer.filter(ImageFilter.GaussianBlur(r)))
    return ImageChops.screen(base, layer)


def bezier(a, c, b, n=60):
    return [((1 - t) ** 2 * a[0] + 2 * (1 - t) * t * c[0] + t * t * b[0],
             (1 - t) ** 2 * a[1] + 2 * (1 - t) * t * c[1] + t * t * b[1]) for t in (i / n for i in range(n + 1))]


def sky():
    y = np.linspace(0, 1, H)[:, None]
    stops = [(0.0, (6, 7, 10)), (0.35, (14, 16, 26)), (0.58, (40, 20, 24)), (0.74, (150, 52, 32)), (0.80, (60, 20, 18))]
    img = np.zeros((H, W, 3))
    for (y0, c0), (y1, c1) in zip(stops, stops[1:]):
        t = np.clip((y - y0) / (y1 - y0), 0, 1)
        m = (y >= y0) & (y <= y1)
        for k in range(3):
            img[:, :, k] += (m * (c0[k] + (c1[k] - c0[k]) * t)).repeat(W, axis=1)
    # Fires behind the city: a wide glow along the horizon.
    yy, xx = np.mgrid[0:H, 0:W]
    d = ((xx - W * 0.52) / (W * 0.55)) ** 2 + ((yy - H * 0.76) / (H * 0.16)) ** 2
    g = np.exp(-d * 1.6)[:, :, None] * np.array([120, 40, 18])
    return Image.fromarray(np.clip(img + g, 0, 255).astype(np.uint8))


def stars(img, rng):
    d = ImageDraw.Draw(img)
    for _ in range(140):
        x, y = rng.random() * W, rng.random() * H * 0.45
        r = rng.choice([1.5, 2, 2.5, 3.5])
        a = rng.randint(60, 170)
        d.ellipse([x - r, y - r, x + r, y + r], fill=(a, a, a + 10))


def searchlights(img):
    """Cold beams from the city, bright at the lamp and fading as they rise."""
    yy, xx = np.mgrid[0:H, 0:W]
    total = np.zeros((H, W, 3))
    for (x, y), ang, spread in [((0.17, 0.75), -1.05, 0.05), ((0.84, 0.75), -2.2, 0.045), ((0.55, 0.76), -1.75, 0.035)]:
        ox, oy = P(x, y)
        L = H * 1.2
        a1, a2 = ang - spread, ang + spread
        layer = Image.new("L", (W, H), 0)
        ImageDraw.Draw(layer).polygon([(ox, oy), (ox + math.cos(a1) * L, oy + math.sin(a1) * L),
                                       (ox + math.cos(a2) * L, oy + math.sin(a2) * L)], fill=255)
        beam = np.asarray(layer.filter(ImageFilter.GaussianBlur(16))) / 255.0
        fall = np.clip(1 - np.hypot(xx - ox, yy - oy) / L, 0, 1) ** 1.6
        total += (beam * fall)[:, :, None] * np.array([70, 88, 120])
    return ImageChops.screen(img, Image.fromarray(np.clip(total, 0, 255).astype(np.uint8)))


def trail_dots(d, head, direction, n, gap, r, colour):
    hx, hy = P(*head)
    for i in range(1, n + 1):
        a = 1 - i / (n + 1)
        x, y = hx - direction[0] * gap * i, hy - direction[1] * gap * i
        rr = r * (0.5 + 0.5 * a)
        d.ellipse([x - rr, y - rr, x + rr, y + rr], fill=tuple(int(c * a) for c in colour))


def drones(img, positions, exploding):
    ang = math.atan2(0.58, -1)
    dirv = (math.cos(ang), math.sin(ang))
    trails = light()
    dt = ImageDraw.Draw(trails)
    for i, p in enumerate(positions):
        if i != exploding:
            trail_dots(dt, p, dirv, 9, 46, 6, ENEMY)
    img = glow(img, trails, [6])
    engines = light()
    de = ImageDraw.Draw(engines)
    for i, p in enumerate(positions):
        if i == exploding:
            continue
        tail = shape([(-6.6, 0)], p, 11, ang)[0]
        de.ellipse([tail[0] - 13, tail[1] - 13, tail[0] + 13, tail[1] + 13], fill=(255, 150, 80))
    img = glow(img, engines, [10, 26])
    d = ImageDraw.Draw(img)
    for i, p in enumerate(positions):
        if i == exploding:
            continue
        d.polygon(shape(DRONE, p, 11, ang), fill=(84, 24, 26), outline=ENEMY, width=5)
    return img


def cruise(img, head):
    ang = math.atan2(0.2, -1)
    hx, hy = P(*head)
    layer = light()
    d = ImageDraw.Draw(layer)
    for i in range(40):
        t = i / 40
        x0, y0 = hx + math.cos(ang) * -(60 + t * 900), hy + math.sin(ang) * -(60 + t * 900)
        x1, y1 = hx + math.cos(ang) * -(60 + (t + 0.025) * 900), hy + math.sin(ang) * -(60 + (t + 0.025) * 900)
        a = int(150 * (1 - t))
        d.line([(x0, y0), (x1, y1)], fill=(a, a, a), width=int(10 * (1 - t) + 3))
    img = glow(img, layer, [8])
    eng = light()
    de = ImageDraw.Draw(eng)
    tx, ty = hx - math.cos(ang) * 140, hy - math.sin(ang) * 140
    de.ellipse([tx - 22, ty - 22, tx + 22, ty + 22], fill=(255, 170, 90))
    img = glow(img, eng, [14, 34])
    ImageDraw.Draw(img).polygon(shape(CRUISE, head, 15, ang), fill=(84, 24, 26), outline=ENEMY, width=5)
    return img


def ballistic(img, head, tail):
    hx, hy = P(*head)
    tx, ty = P(*tail)
    layer = light()
    d = ImageDraw.Draw(layer)
    n = 60
    for i in range(n):
        t0, t1 = i / n, (i + 1) / n
        a = t1 ** 1.6
        col = (int(255 * a), int(150 * a ** 1.5), int(60 * a ** 3))
        d.line([(tx + (hx - tx) * t0, ty + (hy - ty) * t0), (tx + (hx - tx) * t1, ty + (hy - ty) * t1)],
               fill=col, width=int(4 + 30 * a))
    d.ellipse([hx - 26, hy - 26, hx + 26, hy + 26], fill=(255, 245, 220))
    return glow(img, layer, [10, 30, 70])


def interceptor(img, start, control, head, colour=BLUE):
    pts = bezier(P(*start), P(*control), P(*head))
    layer = light()
    d = ImageDraw.Draw(layer)
    for i in range(len(pts) - 1):
        a = (i / len(pts)) ** 1.3
        d.line([pts[i], pts[i + 1]], fill=tuple(int(c * (0.25 + 0.75 * a)) for c in (210, 230, 255)), width=int(4 + 9 * a))
    hx, hy = pts[-1]
    d.ellipse([hx - 16, hy - 16, hx + 16, hy + 16], fill=(255, 255, 255))
    img = glow(img, layer, [6, 18])
    tint = light()
    ImageDraw.Draw(tint).line(pts, fill=tuple(c // 2 for c in colour), width=24)
    return ImageChops.screen(img, tint.filter(ImageFilter.GaussianBlur(26)))


def blast(img, at, size, rng):
    x, y = P(*at)
    smoke = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    ds = ImageDraw.Draw(smoke)
    for _ in range(7):
        ox, oy, r = rng.uniform(-1, 1) * size * 0.9, rng.uniform(-0.6, 0.9) * size, size * rng.uniform(0.5, 0.9)
        ds.ellipse([x + ox - r, y + oy - r, x + ox + r, y + oy + r], fill=(20, 16, 18, 150))
    img = Image.alpha_composite(img.convert("RGBA"), smoke.filter(ImageFilter.GaussianBlur(size * 0.25))).convert("RGB")
    layer = light()
    d = ImageDraw.Draw(layer)
    for rr, col in [(1.0, (200, 50, 20)), (0.75, (255, 120, 30)), (0.5, (255, 200, 80)), (0.25, (255, 250, 230))]:
        r = size * rr
        d.ellipse([x - r, y - r, x + r, y + r], fill=col)
    for _ in range(26):
        a = rng.uniform(0, math.tau)
        r0, r1 = size * rng.uniform(0.7, 1.0), size * rng.uniform(1.4, 2.6)
        d.line([(x + math.cos(a) * r0, y + math.sin(a) * r0), (x + math.cos(a) * r1, y + math.sin(a) * r1)],
               fill=(255, 190, 90), width=5)
    return glow(img, layer, [size * 0.3, size * 0.9, size * 1.8])


def puff(img, at, size, rng):
    x, y = P(*at)
    smoke = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    d = ImageDraw.Draw(smoke)
    for _ in range(9):
        ox, oy, r = rng.uniform(-1.4, 1.4) * size, rng.uniform(-0.8, 0.8) * size, size * rng.uniform(0.5, 1.0)
        d.ellipse([x + ox - r, y + oy - r, x + ox + r, y + oy + r], fill=(46, 40, 44, 120))
    return Image.alpha_composite(img.convert("RGBA"), smoke.filter(ImageFilter.GaussianBlur(size * 0.35))).convert("RGB")


def fbm(w, h, cell, octaves, seed):
    """Fractal noise in 0..1: random grids, each twice as fine and half as strong."""
    rng = np.random.default_rng(seed)
    total = np.zeros((h, w), np.float32)
    amp, norm = 1.0, 0.0
    for o in range(octaves):
        gw, gh = max(2, int(w / cell * 2 ** o)), max(2, int(h / cell * 2 ** o))
        grid = Image.fromarray((rng.random((gh, gw)) * 255).astype(np.uint8))
        total += np.asarray(grid.resize((w, h), Image.BICUBIC), np.float32) / 255 * amp
        norm += amp
        amp *= 0.5
    return total / norm


def smooth(a, b, x):
    t = np.clip((x - a) / (b - a), 0, 1)
    return t * t * (3 - 2 * t)


def clouds(img, lights):
    """Ragged clouds across the upper sky, lit from below by the fires and by `lights`."""
    arr = np.asarray(img, np.float32)
    n = fbm(W, H, 650, 6, 11)
    yy = np.linspace(0, 1, H, dtype=np.float32)[:, None]
    band = smooth(0.0, 0.16, yy) * (1 - smooth(0.42, 0.66, yy))
    mask = np.clip((n - 0.47) / 0.22, 0, 1) * band * 0.9
    t = np.clip((yy - 0.05) / 0.6, 0, 1)[:, :, None]
    col = np.array([16, 17, 26], np.float32) * (1 - t) + np.array([120, 48, 36], np.float32) * t
    col = np.broadcast_to(col, (H, W, 3)).copy()
    gy, gx = np.mgrid[0:H, 0:W].astype(np.float32)
    for (lx, ly), r, c in lights:
        x, y = P(lx, ly)
        col += np.exp(-((gx - x) ** 2 + (gy - y) ** 2) / (r * W) ** 2)[:, :, None] * np.array(c, np.float32)
    # Thicker cloud is darker inside and brighter at its ragged edges.
    edge = 1 - np.clip((n - 0.55) / 0.2, 0, 1)[:, :, None] * 0.5
    a = mask[:, :, None]
    arr = arr * (1 - a) + col * edge * a
    return Image.fromarray(np.clip(arr, 0, 255).astype(np.uint8))


def skyline(img, rng, base, hmin, hmax, colour, lit_chance):
    d = ImageDraw.Draw(img)
    x = -20
    windows = []
    while x < W:
        w = rng.uniform(0.022, 0.055) * W
        h = rng.uniform(hmin, hmax) * H
        if rng.random() < 0.12:
            h *= 1.5
        d.rectangle([x, base - h, x + w, H], fill=colour)
        if rng.random() < 0.25:
            d.rectangle([x + w * 0.45, base - h - 0.02 * H, x + w * 0.52, base - h], fill=colour)
        for _ in range(int(w * h / 9000)):
            if rng.random() < lit_chance:
                windows.append((x + rng.uniform(0.1, 0.85) * w, base - h + rng.uniform(0.08, 0.9) * h))
        x += w + rng.uniform(0, 0.006) * W
    return windows


def plume(img, base, height, width, drift, seed):
    """A column of smoke rising from a fire, lit orange at its foot."""
    arr = np.asarray(img, np.float32)
    bx, by = P(*base)
    hh, ww = int(height * H), int(width * W)
    x0, x1 = int(max(0, bx - ww * 2.2)), int(min(W, bx + drift * hh + ww * 2.2))
    y0, y1 = int(max(0, by - hh)), int(by)
    gy, gx = np.mgrid[y0:y1, x0:x1].astype(np.float32)
    v = (by - gy) / hh
    cx = bx + drift * hh * v ** 1.4
    hw = ww * (0.35 + 1.3 * v)
    n = fbm(x1 - x0, y1 - y0, 140, 5, seed)
    m = np.exp(-((gx - cx) / hw) ** 2) * smooth(0, 0.05, v) * (1 - v) ** 0.7 * (0.35 + 0.65 * n)
    # Lit by the fire at its foot, by the burning city further up, dark at the top.
    fire = np.exp(-v * 6)[:, :, None]
    mid = np.exp(-((v - 0.35) / 0.3) ** 2)[:, :, None]
    col = (np.array([48, 40, 46], np.float32) * (1 - fire) * (1 - mid) + np.array([110, 66, 54], np.float32) * mid
           + np.array([230, 110, 45], np.float32) * fire)
    a = (np.clip(m * 2.0, 0, 0.94))[:, :, None]
    arr[y0:y1, x0:x1] = arr[y0:y1, x0:x1] * (1 - a) + col * a
    return Image.fromarray(np.clip(arr, 0, 255).astype(np.uint8))


def fog(img, top, bottom, colour, strength):
    arr = np.asarray(img, np.float32)
    yy = np.linspace(0, 1, H, dtype=np.float32)[:, None]
    a = (smooth(top, (top + bottom) / 2, yy) * (1 - smooth((top + bottom) / 2, bottom, yy)) * strength)[:, :, None]
    arr = arr * (1 - a) + np.array(colour, np.float32) * a
    return Image.fromarray(np.clip(arr, 0, 255).astype(np.uint8))


def launcher(img, ground, x, rng):
    """A SAM launcher in the foreground firing up to the left: flash, smoke, the missile."""
    gx, gy = x * W, ground * H
    pivot = (gx + 0.03 * W, gy - 0.045 * H)
    ang = math.radians(-138)
    L, T = 0.13 * W, 0.05 * H
    ux, uy = math.cos(ang), math.sin(ang)
    px, py = -uy, ux
    mouth = (pivot[0] + ux * L, pivot[1] + uy * L)
    # The missile leaves along the tubes, then pitches up towards its target.
    path = bezier(mouth, (mouth[0] + ux * 0.1 * W, mouth[1] + uy * 0.1 * W), P(0.64, 0.42), 80)
    head = path[-1]
    # The smoke trail: thick and lit by the motor near the launcher, thinning higher up.
    smoke = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    ds = ImageDraw.Draw(smoke)
    for i, (sx, sy) in enumerate(path[:-3]):
        t = i / len(path)
        warm = (1 - t) ** 3
        # Several uneven puffs per step: billowing exhaust, not a smooth cone.
        for _ in range(3):
            r = (115 * (1 - t) ** 1.2 + 20) * rng.uniform(0.55, 1.15)
            ox, oy = rng.uniform(-0.6, 0.6) * r, rng.uniform(-0.6, 0.6) * r
            g = rng.uniform(0.75, 1.0)
            c = (int((120 + 110 * warm) * g), int((112 + 60 * warm) * g), int((112 + 10 * warm) * g))
            ds.ellipse([sx + ox - r, sy + oy - r, sx + ox + r, sy + oy + r], fill=c + (int(120 - 55 * t),))
    for _ in range(18):
        r = rng.uniform(70, 150)
        sx, sy = pivot[0] - rng.uniform(-0.04, 0.1) * W, gy - rng.uniform(0, 0.04) * H
        ds.ellipse([sx - r, sy - r * 0.6, sx + r, sy + r * 0.6], fill=(150, 110, 90, 120))
    img = Image.alpha_composite(img.convert("RGBA"), smoke.filter(ImageFilter.GaussianBlur(9))).convert("RGB")
    # The motor's flame and the flash it lights the smoke with.
    flash = light()
    df = ImageDraw.Draw(flash)
    bx, by = path[-6]
    df.line([(bx, by), head], fill=(255, 210, 140), width=26)
    df.ellipse([head[0] - 20, head[1] - 20, head[0] + 20, head[1] + 20], fill=(255, 252, 240))
    df.ellipse([mouth[0] - 30, mouth[1] - 30, mouth[0] + 30, mouth[1] + 30], fill=(255, 170, 90))
    img = glow(img, flash, [16, 50, 140])
    # The launcher itself, black against the smoke and the glow.
    d = ImageDraw.Draw(img)
    k = (5, 5, 7)
    d.rectangle([gx - 0.005 * W, gy - 0.032 * H, gx + 0.13 * W, gy - 0.008 * H], fill=k)
    d.rectangle([gx - 0.02 * W, gy - 0.05 * H, gx + 0.025 * W, gy - 0.02 * H], fill=k)
    for wx in (0.0, 0.035, 0.08, 0.11):
        cx = gx + wx * W
        d.ellipse([cx - 34, gy - 0.016 * H - 34, cx + 34, gy - 0.016 * H + 34], fill=k)
    d.polygon([(pivot[0] + px * T / 2, pivot[1] + py * T / 2), (pivot[0] - px * T / 2, pivot[1] - py * T / 2),
               (mouth[0] - px * T / 2, mouth[1] - py * T / 2), (mouth[0] + px * T / 2, mouth[1] + py * T / 2)], fill=k)
    d.polygon([(pivot[0], pivot[1]), (pivot[0] + 0.02 * W, gy - 0.02 * H), (pivot[0] - 0.03 * W, gy - 0.02 * H)], fill=k)
    # Seams between the four canisters, faintly lit by the flash.
    seam = (40, 30, 28)
    d.line([pivot, mouth], fill=seam, width=4)
    for f in (0.33, 0.66):
        a = (pivot[0] + ux * L * f + px * T / 2, pivot[1] + uy * L * f + py * T / 2)
        b = (pivot[0] + ux * L * f - px * T / 2, pivot[1] + uy * L * f - py * T / 2)
        d.line([a, b], fill=seam, width=3)
    return img


def streak(img, at, length, colour):
    """An anamorphic lens streak: a thin horizontal line of light through a bright point."""
    x, y = P(*at)
    arr = np.zeros((H, W, 3), np.float32)
    gx = np.arange(W, dtype=np.float32)
    line = np.exp(-((gx - x) / (length * W)) ** 2)
    for dy, a in [(0, 1.0), (-2, 0.7), (2, 0.7), (-5, 0.3), (5, 0.3)]:
        arr[int(y) + dy] += line[:, None] * np.array(colour, np.float32) * a
    lay = Image.fromarray(np.clip(arr, 0, 255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(5))
    return ImageChops.screen(img, lay)


def grade(img):
    """Bloom, teal shadows and warm highlights, a little more contrast, a vignette."""
    arr = np.asarray(img, np.float32) / 255
    lum = arr @ np.array([0.3, 0.59, 0.11], np.float32)
    hi = Image.fromarray((np.clip(lum - 0.55, 0, 1) / 0.45 * 255).astype(np.uint8))
    for r, s in [(40, 0.35), (140, 0.3)]:
        b = np.asarray(hi.filter(ImageFilter.GaussianBlur(r)), np.float32)[:, :, None] / 255
        arr = 1 - (1 - arr) * (1 - b * s * np.array([1.0, 0.75, 0.55], np.float32))
    lum = (arr @ np.array([0.3, 0.59, 0.11], np.float32))[:, :, None]
    arr += (1 - lum) ** 3 * np.array([-0.015, 0.02, 0.045], np.float32)
    arr += lum ** 2 * np.array([0.05, 0.015, -0.03], np.float32)
    arr = 0.5 + (arr - 0.5) * 1.1
    yy, xx = np.mgrid[0:H, 0:W].astype(np.float32)
    v = 1 - 0.6 * (((xx - W / 2) / (W * 0.72)) ** 2 + ((yy - H * 0.42) / (H * 0.8)) ** 2)
    arr *= np.clip(v, 0.25, 1)[:, :, None]
    # A colour fringe that grows towards the edges, as in a real lens.
    out = np.clip(arr, 0, 1)
    out[:, 3:, 0] = out[:, :-3, 0]
    out[:, :-3, 2] = out[:, 3:, 2]
    return Image.fromarray((out * 255).astype(np.uint8))


def grain(img, amount):
    arr = np.asarray(img, np.float32)
    n = np.random.default_rng(5).normal(0, amount, arr.shape[:2])[:, :, None]
    return Image.fromarray(np.clip(arr + n, 0, 255).astype(np.uint8))


def city(img, rng):
    # Far towers in the haze, then the near city in black.
    far = skyline(img, rng, H * 0.80, 0.08, 0.2, (40, 22, 28), 0.05)
    img = fog(img, 0.6, 0.82, (110, 46, 36), 0.55)
    d = ImageDraw.Draw(img)
    base = H * 0.80
    x = -20
    windows = []
    while x < W:
        w = rng.uniform(0.022, 0.055) * W
        h = rng.uniform(0.03, 0.09) * H
        if rng.random() < 0.12:
            h *= 1.5
        d.rectangle([x, base - h, x + w, H], fill=(9, 9, 12))
        if rng.random() < 0.25:
            d.rectangle([x + w * 0.45, base - h - 0.02 * H, x + w * 0.52, base - h], fill=(9, 9, 12))
        for _ in range(int(w * h / 9000)):
            if rng.random() < 0.18:
                wx, wy = x + rng.uniform(0.1, 0.85) * w, base - h + rng.uniform(0.08, 0.9) * h
                windows.append((wx, wy))
        x += w + rng.uniform(0, 0.006) * W
    # The TV tower.
    tx = W * 0.66
    d.polygon([(tx - 34, base), (tx - 10, base - H * 0.2), (tx + 10, base - H * 0.2), (tx + 34, base)], fill=(9, 9, 12))
    d.ellipse([tx - 42, base - H * 0.215, tx + 42, base - H * 0.18], fill=(9, 9, 12))
    d.rectangle([tx - 5, base - H * 0.29, tx + 5, base - H * 0.2], fill=(9, 9, 12))
    lit = light()
    dl = ImageDraw.Draw(lit)
    for wx, wy in far:
        dl.rectangle([wx, wy, wx + 9, wy + 13], fill=(90, 60, 30))
    for wx, wy in windows:
        dl.rectangle([wx, wy, wx + 9, wy + 13], fill=(170, 120, 40))
    dl.ellipse([tx - 8, base - H * 0.295, tx + 8, base - H * 0.285], fill=(255, 60, 50))
    img = glow(img, lit, [6])
    d = ImageDraw.Draw(img)
    d.rectangle([0, base, W, H], fill=(8, 8, 11))
    return img


def poster():
    rng = random.Random(7)
    blast_at = (0.705, 0.225)
    img = sky()
    stars(img, rng)
    img = clouds(img, [(blast_at, 0.22, (190, 110, 50)), ((0.33, 0.30), 0.12, (120, 80, 40))])
    img = searchlights(img)
    img = puff(img, (0.16, 0.14), 70, rng)
    img = ballistic(img, (0.33, 0.30), (0.02, -0.08))
    positions = [(0.95, 0.07), (0.87, 0.125), (0.79, 0.175), blast_at, (0.63, 0.29)]
    img = drones(img, positions, exploding=3)
    img = cruise(img, (0.86, 0.47))
    img = interceptor(img, (0.36, 0.76), (0.44, 0.36), (0.695, 0.235))
    img = interceptor(img, (0.50, 0.77), (0.55, 0.50), (0.60, 0.335))
    img = blast(img, blast_at, 62, rng)
    img = streak(img, blast_at, 0.32, (90, 150, 255))
    img = city(img, rng)
    for base, h, w, drift, seed in [((0.24, 0.79), 0.5, 0.055, 0.35, 21), ((0.47, 0.795), 0.38, 0.04, 0.4, 22)]:
        img = plume(img, base, h, w, drift, seed)
    img = launcher(img, 0.80, 0.80, rng)
    img = grade(img)
    # The logo on the dark ground below the city.
    lg = Image.open(LOGO).convert("RGBA")
    lw = int(W * 0.86)
    lg = lg.resize((lw, round(lg.height * lw / lg.width)), Image.LANCZOS)
    out = img.convert("RGBA")
    out.alpha_composite(lg, ((W - lw) // 2, int(H * 0.985) - lg.height))
    return out.convert("RGB")


if __name__ == "__main__":
    out = sys.argv[1] if len(sys.argv) > 1 else os.path.join(ROOT, "itch")
    big = poster()
    grain(big.resize((1260, 1000), Image.LANCZOS), 4).save(os.path.join(out, "poster.png"))
    grain(big.resize((630, 500), Image.LANCZOS), 3).save(os.path.join(out, "cover.png"))
    print("wrote poster.png and cover.png to", out)
