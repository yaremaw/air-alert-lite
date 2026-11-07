"""A cinematic Strike Alert poster rendered from a small 3D scene: from a
rooftop at night, a swarm of attack drones streams in over a burning city,
one exploding, searchlights and interceptors rising to meet them.

    python tools/itch_poster3d.py itch

writes cover.png (630x500) and poster.png (1260x1000). World units are metres:
x right, y up, z away from the camera.
"""
import math
import os
import random
import sys

import numpy as np
from PIL import Image, ImageChops, ImageDraw, ImageFilter

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
LOGO = os.path.join(ROOT, "itch", "logo.png")
HAZE = np.array([176, 74, 40], np.float32)


def v3(x, y, z):
    return np.array([x, y, z], np.float64)


def norm(a):
    return a / np.linalg.norm(a)


class Camera:
    def __init__(self, w, h, pos, pitch_deg, yaw_deg, focal):
        self.w, self.h, self.pos, self.f = w, h, pos, focal * w
        self.yaw = yaw_deg
        p, y = math.radians(pitch_deg), math.radians(yaw_deg)
        self.fwd = norm(v3(math.sin(y) * math.cos(p), math.sin(p), math.cos(y) * math.cos(p)))
        self.right = norm(np.cross(v3(0, 1, 0), self.fwd))
        self.up = np.cross(self.fwd, self.right)

    def depth(self, p):
        return float(np.dot(p - self.pos, self.fwd))

    def project(self, p):
        d = p - self.pos
        z = max(np.dot(d, self.fwd), 0.05)
        return (self.w / 2 + self.f * np.dot(d, self.right) / z, self.h / 2 - self.f * np.dot(d, self.up) / z)

    def toward(self, dist, elev, az):
        """The point `dist` metres away, `elev` degrees up, `az` degrees right of where the camera looks."""
        e, a = math.radians(elev), math.radians(az + self.yaw)
        return self.pos + dist * v3(math.sin(a) * math.cos(e), math.sin(e), math.cos(a) * math.cos(e))

    def rays(self):
        xs = (np.arange(self.w, dtype=np.float32) - self.w / 2) / self.f
        ys = (self.h / 2 - np.arange(self.h, dtype=np.float32)) / self.f
        d = (self.fwd[None, None, :] + xs[None, :, None] * self.right[None, None, :]
             + ys[:, None, None] * self.up[None, None, :]).astype(np.float32)
        return d / np.linalg.norm(d, axis=2, keepdims=True)


def fbm(size, cell, octaves, seed):
    """Tiling fractal noise in 0..1."""
    rng = np.random.default_rng(seed)
    total = np.zeros((size, size), np.float32)
    amp, normal = 1.0, 0.0
    for o in range(octaves):
        g = max(2, int(size / cell * 2 ** o))
        grid = rng.random((g + 1, g + 1)).astype(np.float32)
        grid[-1, :], grid[:, -1] = grid[0, :], grid[:, 0]
        img = Image.fromarray((grid * 255).astype(np.uint8)).resize((size + size // g, size + size // g), Image.BICUBIC)
        total += np.asarray(img, np.float32)[:size, :size] / 255 * amp
        normal += amp
        amp *= 0.5
    return total / normal


def reflect(x, size):
    """Texture coordinates that mirror at the edges, so a texture repeats without a seam."""
    q = np.mod(x, 2 * size)
    return np.where(q >= size, 2 * size - 1 - q, q).astype(np.int64).clip(0, size - 1)


def screen(base, layer):
    return ImageChops.screen(base, layer)


def glow(base, layer, radii):
    for r in radii:
        base = screen(base, layer.filter(ImageFilter.GaussianBlur(r)))
    return screen(base, layer)


def blank(w, h):
    return Image.new("RGB", (w, h), (0, 0, 0))


# --- the city below and the sky above --------------------------------------------

def city_lights(size, seed):
    """A night city seen from above, 3 m to a pixel: lit streets, scattered windows, fires."""
    rng = random.Random(seed)
    img = Image.new("RGB", (size, size), (6, 6, 9))
    d = ImageDraw.Draw(img)
    for vertical in (True, False):
        pos = 0
        while pos < size:
            pos += rng.randint(16, 32)
            bright = rng.random() < 0.25  # avenues are brighter and busier
            d.line([(pos, 0), (pos, size)] if vertical else [(0, pos), (size, pos)],
                   fill=(46, 30, 16) if bright else (24, 16, 10), width=2 if bright else 1)
            step = 2 if bright else 4
            for k in range(0, size, step):
                if rng.random() < 0.75:
                    a = rng.uniform(0.5, 1.0)
                    c = (int(255 * a), int(180 * a), int(100 * a))
                    x, y = (pos, k) if vertical else (k, pos)
                    d.point((x, y), fill=c)
    for _ in range(size * size // 40):
        x, y = rng.randrange(size), rng.randrange(size)
        a = rng.uniform(0.2, 0.7)
        d.point((x, y), fill=(int(220 * a), int(190 * a), int(140 * a)))
    # Downtown: blocks of densely lit towers.
    for _ in range(40):
        cx, cy, r = rng.randrange(size), rng.randrange(size), rng.randint(12, 40)
        for _ in range(r * r // 2):
            x, y = cx + rng.randint(-r, r), cy + rng.randint(-r, r)
            a = rng.uniform(0.4, 1.0)
            d.point((x % size, y % size), fill=(int(255 * a), int(215 * a), int(160 * a)))
    fires = Image.new("RGB", (size, size), (0, 0, 0))
    df = ImageDraw.Draw(fires)
    for _ in range(70):
        x, y, r = rng.randrange(size), rng.randrange(size), rng.uniform(3, 11)
        df.ellipse([x - r, y - r, x + r, y + r], fill=(255, 120, 40))
    img = glow(img, fires, [6, 18])
    sharp = np.asarray(img, np.float32)
    soft = np.asarray(img.filter(ImageFilter.GaussianBlur(2.2)), np.float32)
    return sharp, soft


def world(cam, blast_dir):
    d = cam.rays()
    elev = np.degrees(np.arcsin(np.clip(d[:, :, 1], -1, 1)))
    az = np.degrees(np.arctan2(d[:, :, 0], d[:, :, 2]))
    stops = [(0, (190, 80, 42)), (3, (140, 52, 34)), (9, (66, 28, 32)), (20, (26, 22, 32)), (38, (10, 11, 18)), (90, (4, 5, 8))]
    col = np.zeros(d.shape, np.float32)
    for (e0, c0), (e1, c1) in zip(stops, stops[1:]):
        t = np.clip((elev - e0) / (e1 - e0), 0, 1)[:, :, None]
        m = ((elev >= e0) & (elev < e1))[:, :, None]
        col += m * (np.array(c0, np.float32) * (1 - t) + np.array(c1, np.float32) * t)
    col += (np.exp(-((az + 10) / 30) ** 2) * np.exp(-np.clip(elev, 0, None) / 7))[:, :, None] * np.array([90, 32, 12], np.float32)
    # The cloud ceiling, 900 m up, lit from below by the city and the blast.
    n = fbm(1024, 150, 6, 4)
    sky = d[:, :, 1] > 0.004
    dy = np.clip(d[:, :, 1], 0.004, None)
    t = (900 - cam.pos[1]) / dy
    u = reflect((cam.pos[0] + t * d[:, :, 0]) / 3000 * 1024, 1024)
    v = reflect((cam.pos[2] + t * d[:, :, 2]) / 3000 * 1024, 1024)
    nn = n[v, u]
    dens = np.clip((nn - 0.48) / 0.2, 0, 1) * np.exp(-t / 9000) * sky
    lit = np.exp(-np.clip(elev, 0, None) / 16)[:, :, None]
    ccol = np.array([22, 20, 28], np.float32) + lit * np.array([160, 68, 42], np.float32)
    ang = np.degrees(np.arccos(np.clip(np.tensordot(d, blast_dir.astype(np.float32), axes=([2], [0])), -1, 1)))
    ccol += np.exp(-(ang / 12) ** 2)[:, :, None] * np.array([220, 140, 70], np.float32)
    edge = 1 - 0.45 * np.clip((nn - 0.56) / 0.2, 0, 1)[:, :, None]
    a = (dens * 0.9)[:, :, None]
    col = col * (1 - a) + ccol * edge * a
    rng = np.random.default_rng(9)
    ys, xs = rng.integers(0, cam.h, 600), rng.integers(0, cam.w, 600)
    keep = (elev[ys, xs] > 22) & (dens[ys, xs] < 0.1)
    col[ys[keep], xs[keep]] += rng.uniform(60, 160, keep.sum())[:, None]
    # The city: where a ray meets the ground, the lights there, fading into the haze.
    ground = d[:, :, 1] < -0.0005
    if ground.any():
        sharp, soft = city_lights(2048, 12)
        gy = np.clip(-d[:, :, 1], 0.0005, None)
        tg = cam.pos[1] / gy
        X = cam.pos[0] + tg * d[:, :, 0]
        Z = cam.pos[2] + tg * d[:, :, 2]
        ca, sa = math.cos(math.radians(28)), math.sin(math.radians(28))
        gu = reflect((X * ca - Z * sa) / 3, 2048)
        gv = reflect((X * sa + Z * ca) / 3, 2048)
        far = np.clip((tg - 600) / 2500, 0, 1)[:, :, None]
        lights = sharp[gv, gu] * (1 - far) + soft[gv, gu] * far
        lights *= 2.1
        h = (1 - np.exp(-tg / 4200))[:, :, None]
        gcol = lights * (1 - h * 0.8) + HAZE * h
        col = np.where(ground[:, :, None], gcol, col)
    return Image.fromarray(np.clip(col, 0, 255).astype(np.uint8))


# --- light in the air ----------------------------------------------------------

def beam(img, cam, start, direction, length, r0, r1, colour):
    """A searchlight: a cone from `start` along `direction`, fading with distance."""
    acc = np.zeros((cam.h, cam.w), np.float32)
    steps = 40
    for i in range(steps):
        a, b = i / steps, (i + 1) / steps
        p0, p1 = start + direction * length * a, start + direction * length * b
        if cam.depth(p0) < 1 or cam.depth(p1) < 1:
            continue
        s0, s1 = cam.project(p0), cam.project(p1)
        w0 = cam.f * (r0 + (r1 - r0) * a) / cam.depth(p0)
        w1 = cam.f * (r0 + (r1 - r0) * b) / cam.depth(p1)
        dx, dy = s1[0] - s0[0], s1[1] - s0[1]
        L = math.hypot(dx, dy) or 1
        nx, ny = -dy / L, dx / L
        layer = Image.new("L", (cam.w, cam.h), 0)
        ImageDraw.Draw(layer).polygon([(s0[0] + nx * w0, s0[1] + ny * w0), (s1[0] + nx * w1, s1[1] + ny * w1),
                                       (s1[0] - nx * w1, s1[1] - ny * w1), (s0[0] - nx * w0, s0[1] - ny * w0)],
                                      fill=int(255 * (1 - a) ** 1.4))
        acc = np.maximum(acc, np.asarray(layer, np.float32) / 255)
    lay = Image.fromarray((acc[:, :, None] * np.array(colour, np.float32)).clip(0, 255).astype(np.uint8))
    return screen(img, lay.filter(ImageFilter.GaussianBlur(cam.w * 0.005)))


def curve(a, c, b, n=60):
    return [(1 - t) ** 2 * a + 2 * (1 - t) * t * c + t * t * b for t in (i / n for i in range(n + 1))]


def trail(img, cam, pts, width, colour):
    """An interceptor's trail, brighter towards its head."""
    sp = [cam.project(p) for p in pts]
    layer = blank(cam.w, cam.h)
    d = ImageDraw.Draw(layer)
    for i in range(len(sp) - 1):
        a = (i / len(sp)) ** 1.3
        wd = max(2, int(width * cam.f / max(cam.depth(pts[i]), 1)))
        d.line([sp[i], sp[i + 1]], fill=tuple(int(c * (0.18 + 0.82 * a)) for c in colour), width=wd)
    hx, hy = sp[-1]
    r = cam.w * 0.0045
    d.ellipse([hx - r, hy - r, hx + r, hy + r], fill=(255, 255, 255))
    return glow(img, layer, [cam.w * 0.003, cam.w * 0.009])


def blast(img, cam, at, radius, rng):
    x, y = cam.project(at)
    r = cam.f * radius / max(cam.depth(at), 1)
    smoke = Image.new("RGBA", (cam.w, cam.h), (0, 0, 0, 0))
    ds = ImageDraw.Draw(smoke)
    for _ in range(10):
        ox, oy, rr = rng.uniform(-1.4, 1.4) * r, rng.uniform(-0.8, 1.2) * r, r * rng.uniform(0.5, 1.0)
        ds.ellipse([x + ox - rr, y + oy - rr, x + ox + rr, y + oy + rr], fill=(30, 22, 22, 170))
    img = Image.alpha_composite(img.convert("RGBA"), smoke.filter(ImageFilter.GaussianBlur(r * 0.35))).convert("RGB")
    layer = blank(cam.w, cam.h)
    d = ImageDraw.Draw(layer)
    for k, col in [(1.0, (190, 50, 18)), (0.7, (255, 120, 30)), (0.42, (255, 205, 90)), (0.18, (255, 250, 235))]:
        d.ellipse([x - r * k, y - r * k, x + r * k, y + r * k], fill=col)
    for _ in range(18):
        a = rng.uniform(0, math.tau)
        r0, r1 = r * rng.uniform(0.7, 1.0), r * rng.uniform(1.3, 2.1)
        d.line([(x + math.cos(a) * r0, y + math.sin(a) * r0), (x + math.cos(a) * r1, y + math.sin(a) * r1)],
               fill=(255, 180, 80), width=max(2, int(r * 0.05)))
    img = glow(img, layer, [r * 0.35, r * 1.0, r * 2.6])
    d = ImageDraw.Draw(img)
    for _ in range(10):
        a = rng.uniform(0, math.tau)
        dist = r * rng.uniform(1.3, 2.4)
        px, py = x + math.cos(a) * dist, y + math.sin(a) * dist
        s = r * rng.uniform(0.05, 0.12)
        q = rng.uniform(0, math.tau)
        d.polygon([(px + math.cos(q + k * 2.1) * s, py + math.sin(q + k * 2.1) * s) for k in range(3)], fill=(14, 10, 10))
    arr = np.zeros((cam.h, cam.w, 3), np.float32)
    line = np.exp(-((np.arange(cam.w, dtype=np.float32) - x) / (cam.w * 0.28)) ** 2)
    for dy, k in [(0, 1.0), (-2, 0.6), (2, 0.6), (-5, 0.25), (5, 0.25)]:
        yy = int(y) + dy
        if 0 <= yy < cam.h:
            arr[yy] += line[:, None] * np.array([90, 150, 255], np.float32) * k
    return screen(img, Image.fromarray(arr.clip(0, 255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(5)))


# --- the drones ----------------------------------------------------------------

def drone_mesh():
    """A delta-wing attack drone, about 3.5 m long and 2.5 m across. Local axes:
    x right, y up, z forward. Returns (faces, propeller centre)."""
    t = 0.06
    faces = [[v3(0, t, 1.2), v3(1.25, t, -1.3), v3(-1.25, t, -1.3)],
             [v3(0, -t, 1.2), v3(-1.25, -t, -1.3), v3(1.25, -t, -1.3)]]
    bw, bh, z0, z1 = 0.15, 0.16, -1.45, 1.6
    c = [v3(sx * bw, sy * bh + 0.08, sz) for sz in (z0, z1) for sy in (-1, 1) for sx in (-1, 1)]
    for a, b, cc, dd in [(0, 1, 3, 2), (4, 6, 7, 5), (0, 2, 6, 4), (1, 5, 7, 3), (2, 3, 7, 6), (0, 4, 5, 1)]:
        faces.append([c[a], c[b], c[cc], c[dd]])
    nose = v3(0, 0.05, 1.95)
    faces += [[c[4], c[5], nose], [c[5], c[7], nose], [c[7], c[6], nose], [c[6], c[4], nose]]
    for sx in (-1, 1):
        faces.append([v3(sx * 1.22, -0.22, -1.3), v3(sx * 1.22, 0.4, -1.3), v3(sx * 1.1, 0.4, -1.0), v3(sx * 1.02, -0.22, -0.7)])
    return faces, v3(0, 0.08, -1.55)


def place(p, pos, fwd, roll):
    right = norm(np.cross(v3(0, 1, 0), fwd))
    up = np.cross(fwd, right)
    cr, sr = math.cos(roll), math.sin(roll)
    right, up = right * cr + up * sr, -right * sr + up * cr
    return pos + p[0] * right + p[1] * up + p[2] * fwd


def shade(normal, centre, lights, base):
    col = np.array(base, np.float64) * 0.8
    for kind, a, colour, k in lights:
        if kind == "dir":
            ld, fall = a, 1.0
        else:
            dv = a - centre
            dist = np.linalg.norm(dv)
            ld, fall = dv / dist, min(1.0, (40 / dist) ** 2)
        col += np.array(colour) * max(0.0, float(np.dot(normal, ld))) * k * fall
    return tuple(int(c) for c in np.clip(col, 0, 255))


def draw_drone(img, cam, pos, fwd, roll, lights, rim=None, blur=0.0, scale=1.0):
    faces, prop = drone_mesh()
    world_faces = [[place(p * scale, pos, fwd, roll) for p in f] for f in faces]
    world_faces.sort(key=lambda f: -np.mean([cam.depth(p) for p in f]))
    layer = Image.new("RGBA", (cam.w, cam.h), (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    rim_w = max(1, int(cam.f * 0.03 * scale / max(cam.depth(pos), 1)))
    for f in world_faces:
        n = np.cross(f[1] - f[0], f[2] - f[0])
        if np.linalg.norm(n) < 1e-9:
            continue
        n = norm(n)
        centre = np.mean(f, axis=0)
        if np.dot(n, cam.pos - centre) < 0:
            n = -n
        col = shade(n, centre, lights, (40, 36, 40))
        d.polygon([cam.project(p) for p in f], fill=col + (255,), outline=(rim or (10, 9, 11)) + (255,), width=rim_w)
    ring = [cam.project(place((prop + v3(math.cos(a) * 0.5, math.sin(a) * 0.5, 0)) * scale, pos, fwd, roll))
            for a in np.linspace(0, math.tau, 24)]
    d.polygon(ring, fill=(110, 100, 100, 55))
    if blur > 0:
        s0, s1 = cam.project(pos), cam.project(pos + fwd * blur)
        dx, dy = s1[0] - s0[0], s1[1] - s0[1]
        acc = np.zeros((cam.h, cam.w, 4), np.float32)
        steps = 36
        for i in range(steps):
            k = i / (steps - 1) - 0.5
            acc += np.asarray(layer.transform(layer.size, Image.AFFINE, (1, 0, -dx * k, 0, 1, -dy * k)), np.float32)
        layer = Image.fromarray((acc / steps).clip(0, 255).astype(np.uint8))
    return Image.alpha_composite(img.convert("RGBA"), layer).convert("RGB")


def engines(img, cam, drones, heading):
    """Each drone's engine as a small warm light, so even the far ones read as a stream of lights."""
    layer = blank(cam.w, cam.h)
    d = ImageDraw.Draw(layer)
    for p in drones:
        dist = np.linalg.norm(p - cam.pos)
        x, y = cam.project(p - heading * 1.7 * (1 + 1.7 * min(1.0, dist / 220)))
        r = min(cam.w * 0.0035, max(cam.w * 0.0016, cam.f * 0.3 / max(cam.depth(p), 1)))
        d.ellipse([x - r, y - r, x + r, y + r], fill=(255, 170, 90))
    return glow(img, layer, [cam.w * 0.003, cam.w * 0.009])


def horizon(img, cam, rng):
    """The far edge of the city: a low skyline against the glow and smoke rising from fires."""
    w, h = img.size
    hy = cam.project(cam.pos + v3(0, -cam.pos[1], 0) + cam.fwd * 0 + v3(0, 0, 1) * 1e6)[1]
    hy = cam.h / 2 + cam.f * math.tan(math.asin(cam.fwd[1]))
    d = ImageDraw.Draw(img)
    x = 0
    while x < w:
        bw = rng.uniform(0.004, 0.02) * w
        bh = rng.uniform(0.002, 0.012) * h * (2.5 if rng.random() < 0.08 else 1)
        d.rectangle([x, hy - bh, x + bw, hy + 2], fill=(70, 28, 22))
        x += bw
    arr = np.asarray(img, np.float32).copy()
    for fx, height, width, drift, seed in [(0.18, 0.38, 0.03, 0.5, 31), (0.47, 0.3, 0.022, 0.6, 32), (0.83, 0.46, 0.04, 0.45, 33)]:
        bx, by = fx * w, hy
        hh, ww = int(height * h), int(width * w)
        x0, x1 = int(max(0, bx - ww * 2.5)), int(min(w, bx + drift * hh + ww * 2.5))
        y0, y1 = int(max(0, by - hh)), int(by)
        gy, gx = np.mgrid[y0:y1, x0:x1].astype(np.float32)
        v = np.clip((by - gy) / hh, 0, 1)
        cx = bx + drift * hh * v ** 1.5
        hw = ww * (0.3 + 1.6 * v)
        n = fbm(256, 40, 5, seed)
        nn = n[(gy.astype(np.int32) * 3) % 256, (gx.astype(np.int32) * 3) % 256]
        m = np.exp(-((gx - cx) / hw) ** 2) * (1 - v) ** 0.8 * (0.35 + 0.65 * nn)
        fire = np.exp(-v * 7)[:, :, None]
        col = np.array([58, 34, 34], np.float32) * (1 - fire) + np.array([240, 120, 50], np.float32) * fire
        a = np.clip(m * 1.6, 0, 0.85)[:, :, None]
        arr[y0:y1, x0:x1] = arr[y0:y1, x0:x1] * (1 - a) + col * a
    return Image.fromarray(np.clip(arr, 0, 255).astype(np.uint8))


# --- the rooftop in the foreground ------------------------------------------------

def rooftop(img):
    w, h = img.size
    d = ImageDraw.Draw(img)
    k = (5, 5, 7)
    edge = [(0, h * 0.815), (w * 0.62, h * 0.87), (w * 0.62, h), (0, h)]
    d.polygon(edge, fill=k)
    d.line([(0, h * 0.815), (w * 0.62, h * 0.87)], fill=(110, 52, 30), width=max(2, w // 500))
    d.rectangle([w * 0.62 - w * 0.004, h * 0.87, w * 0.62, h], fill=k)
    # The mast, its stays and the warning light on top.
    mx, top, base = w * 0.1, h * 0.46, h * 0.83
    d.rectangle([mx - w * 0.003, top, mx + w * 0.003, base], fill=k)
    for f in (0.25, 0.5, 0.75):
        y = top + (base - top) * f
        d.line([(mx - w * 0.012, y), (mx + w * 0.012, y)], fill=k, width=max(2, w // 700))
    d.line([(mx, top + (base - top) * 0.2), (mx - w * 0.06, base)], fill=k, width=max(1, w // 1200))
    d.line([(mx, top + (base - top) * 0.2), (mx + w * 0.05, base + h * 0.005)], fill=k, width=max(1, w // 1200))
    lamp = blank(w, h)
    r = w * 0.004
    ImageDraw.Draw(lamp).ellipse([mx - r, top - r * 2, mx + r, top], fill=(255, 50, 40))
    return glow(img, lamp, [w * 0.004, w * 0.012])


# --- grading -----------------------------------------------------------------------

def grade(img):
    w, h = img.size
    arr = np.asarray(img, np.float32) / 255
    lum = arr @ np.array([0.3, 0.59, 0.11], np.float32)
    hi = Image.fromarray((np.clip(lum - 0.55, 0, 1) / 0.45 * 255).astype(np.uint8))
    for r, s in [(w * 0.016, 0.35), (w * 0.055, 0.3)]:
        b = np.asarray(hi.filter(ImageFilter.GaussianBlur(r)), np.float32)[:, :, None] / 255
        arr = 1 - (1 - arr) * (1 - b * s * np.array([1.0, 0.75, 0.55], np.float32))
    lum = (arr @ np.array([0.3, 0.59, 0.11], np.float32))[:, :, None]
    arr += (1 - lum) ** 3 * np.array([-0.015, 0.02, 0.045], np.float32)
    arr += lum ** 2 * np.array([0.05, 0.015, -0.03], np.float32)
    arr = 0.5 + (arr - 0.5) * 1.1
    yy, xx = np.mgrid[0:h, 0:w].astype(np.float32)
    v = 1 - 0.5 * (((xx - w / 2) / (w * 0.75)) ** 2 + ((yy - h * 0.5) / (h * 0.8)) ** 2)
    arr *= np.clip(v, 0.25, 1)[:, :, None]
    out = np.clip(arr, 0, 1)
    out[:, 3:, 0] = out[:, :-3, 0]
    out[:, :-3, 2] = out[:, 3:, 2]
    return Image.fromarray((out * 255).astype(np.uint8))


def grain(img, amount):
    arr = np.asarray(img, np.float32)
    n = np.random.default_rng(5).normal(0, amount, arr.shape[:2])[:, :, None]
    return Image.fromarray(np.clip(arr + n, 0, 255).astype(np.uint8))


# --- the scene ----------------------------------------------------------------------

def scene(w, h, pitch=10, yaw=-4, focal=0.8):
    rng = random.Random(3)
    cam = Camera(w, h, v3(0, 60, 0), pitch, yaw, focal)
    # The swarm, from specks low over the far city to one passing just overhead:
    # (distance, degrees up, degrees right of centre).
    swarm = [(1400, 4, -23), (1050, 5.5, -20), (800, 7, -17), (600, 9, -13.5), (450, 11, -10), (330, 13.5, -6),
             (240, 16, -2), (170, 19, 3), (115, 22, 8), (72, 25, 13), (44, 21, 8), (21, 25, 21)]
    jit = random.Random(8)
    for k in range(16):
        base = swarm[jit.randrange(1, len(swarm) - 3)]
        swarm.append((base[0] * jit.uniform(0.85, 1.2), base[1] + jit.uniform(-2.5, 2.5), base[2] + jit.uniform(-4, 4)))
    swarm.sort(key=lambda t: -t[0])
    near = swarm[-2:]
    swarm = [t for t in swarm if t not in near] + near
    drones = [cam.toward(*s) for s in swarm]
    heading = norm(drones[-1] - drones[0])
    blast_i = min(range(len(swarm)), key=lambda i: abs(swarm[i][0] - 170))
    img = world(cam, norm(drones[blast_i] - cam.pos))
    img = horizon(img, cam, rng)
    for start, aim, colour in [(v3(-420, 0, 1900), v3(-150, 520, 900), (60, 72, 100)),
                               (v3(260, 0, 1300), v3(-60, 480, 700), (55, 66, 92)),
                               (v3(-60, 0, 800), v3(60, 420, 520), (46, 55, 80))]:
        img = beam(img, cam, start, norm(aim - start), 1600, 1.5, 40, colour)
    for start, end in [(v3(-160, 0, 900), drones[blast_i] + v3(-2, -1.5, 3)),
                       (v3(120, 0, 1300), drones[blast_i + 3] + v3(10, -8, 20)),
                       (v3(-380, 0, 1600), drones[blast_i - 4] + v3(-20, -15, 40))]:
        # Straight up off the launcher, then over towards the target.
        img = trail(img, cam, curve(start, v3(start[0], end[1] * 0.9, start[2]), end), 1.6, (215, 230, 255))
    lights = [("dir", norm(v3(0.1, -1, 0.5)), (200, 90, 44), 0.55),   # the burning city below
              ("dir", norm(v3(-0.3, -0.7, 0.4)), (90, 110, 150), 0.25),  # searchlights
              ("point", drones[blast_i], (255, 170, 80), 1.8)]
    for i, p in sorted(enumerate(drones), key=lambda t: -cam.depth(t[1])):
        if i == blast_i:
            img = blast(img, cam, p, 6.5, rng)
            continue
        near = i >= len(drones) - 2
        dist = np.linalg.norm(p - cam.pos)
        img = draw_drone(img, cam, p, heading, math.radians(rng.uniform(-10, 10)), lights,
                         rim=(170, 80, 44) if near else (120, 50, 34), blur=(0.22 if i == len(drones) - 1 else 0.1) if near else 0,
                         scale=1 + 1.7 * min(1.0, dist / 220))
    img = engines(img, cam, [p for i, p in enumerate(drones) if i != blast_i and np.linalg.norm(p - cam.pos) > 60], heading)
    img = rooftop(img)
    return grade(img)


def with_logo(img, width_frac, at):
    lg = Image.open(LOGO).convert("RGBA")
    lw = int(img.width * width_frac)
    lg = lg.resize((lw, round(lg.height * lw / lg.width)), Image.LANCZOS)
    out = img.convert("RGBA")
    out.alpha_composite(lg, (int(at[0] * img.width), int(at[1] * img.height)))
    return out.convert("RGB")


if __name__ == "__main__":
    out = sys.argv[1] if len(sys.argv) > 1 else os.path.join(ROOT, "itch")
    big = with_logo(scene(2520, 2000), 0.54, (0.035, 0.855))
    grain(big.resize((1260, 1000), Image.LANCZOS), 4).save(os.path.join(out, "poster.png"))
    grain(big.resize((630, 500), Image.LANCZOS), 3).save(os.path.join(out, "cover.png"))
    print("wrote poster.png and cover.png to", out)
