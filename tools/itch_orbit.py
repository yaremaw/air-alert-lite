"""A cover for Strike Alert: the game's country at night seen from orbit, the
air-raid alert map lit on it, ballistic missiles arcing over the front, our
interceptors meeting them, drones and cruise missiles crossing the border.

    python tools/itch_orbit.py itch/extra/geo itch [--preview]

GEO holds ids.png (the game's region raster for map 7) and map.json (regions
with their alert state mid-raid, capitals, sites, weapons in the air), exported
from the game. Writes cover-orbit.png (630x500) and cover-orbit-1260.png.
World units are km: x east, y north, z up, the Earth's surface touching z = 0
at the map's centre.
"""
import json
import math
import os
import random
import sys

import numpy as np
from PIL import Image, ImageChops, ImageDraw, ImageFilter

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from itch_logo2 import SHAHED  # noqa: E402

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
LOGO = os.path.join(ROOT, "itch", "logo-v2.png")
R = 6371.0          # the Earth
KM = 1.35           # km per map unit
U0, V0 = 490.0, 360.0
SEA_V = 400.0       # map rows south of this are sea where the game has no land
LOW_N, LOW_PX = 3200, 1.8   # the world texture: pixels, km per pixel
CAM = (-1000.0, -250.0, 450.0)   # camera: km east, km north, altitude
LOOK = (60.0, 80.0)              # the ground point it looks at
FOCAL = 2.0                      # of the frame width
SUN_AZ, SUN_DIP = 22.0, 1.5      # degrees right of straight ahead, and below the horizon

AIR = np.array([0xD4, 0xA0, 0x17], np.float32)
MISSILE = np.array([0xE0, 0x57, 0x4A], np.float32)
RED = (255, 80, 60)
BLUE = (90, 170, 255)


def fbm(n, cell, octaves, seed):
    rng = np.random.default_rng(seed)
    total = np.zeros((n, n), np.float32)
    amp = norm = 0.0
    amp = 1.0
    for o in range(octaves):
        g = max(2, int(n / cell * 2 ** o))
        grid = Image.fromarray((rng.random((g, g)) * 255).astype(np.uint8))
        total += np.asarray(grid.resize((n, n), Image.BICUBIC), np.float32) / 255 * amp
        norm += amp
        amp *= 0.5
    return total / norm


def to_world(u, v):
    return (np.asarray(u) - U0) * KM, -(np.asarray(v) - V0) * KM


def to_map(x, y):
    return np.asarray(x) / KM + U0, -np.asarray(y) / KM + V0


def _box(a, k, axis):
    """A moving average k wide along one axis, edges held."""
    pad = [(0, 0)] * a.ndim
    pad[axis] = (k // 2 + 1, k // 2)
    c = np.cumsum(np.pad(a, pad, mode="edge"), axis=axis, dtype=np.float64)
    n = a.shape[axis]
    return ((np.take(c, range(k, n + k), axis=axis) - np.take(c, range(0, n), axis=axis)) / k).astype(np.float32)


def blur(a, sigma):
    """A Gaussian blur of a float array, as three box blurs each way."""
    k = max(1, int(round(math.sqrt(4 * sigma * sigma + 1)))) | 1  # odd, so it stays centred
    if k <= 1:
        return a.astype(np.float32)
    out = a.astype(np.float32)
    for axis in (0, 1):
        for _ in range(3):
            out = _box(out, k, axis)
    return out


# --- the ground ----------------------------------------------------------------------

class Geo:
    def __init__(self, folder):
        self.ids = np.asarray(Image.open(os.path.join(folder, "ids.png")))
        self.data = json.load(open(os.path.join(folder, "map.json"), encoding="utf-8"))
        self.S = self.data["S"]
        regs = self.data["regions"]
        n = 256
        self.side = np.full(n, -1, np.int16)
        self.alert = np.zeros(n, np.int8)  # 0 none, 1 air, 2 missile
        self.city = np.zeros(n, bool)
        for r in regs:
            self.side[r["id"]] = r["side"]
            self.city[r["id"]] = r["city"]
            if r["alert"] and r["side"] == 0:
                self.alert[r["id"]] = 2 if r["missile"] else 1

    def id_at(self, u, v):
        h, w = self.ids.shape
        i = np.clip((np.asarray(v) * self.S).astype(np.int64), 0, h - 1)
        j = np.clip((np.asarray(u) * self.S).astype(np.int64), 0, w - 1)
        out = self.ids[i, j].copy()
        inside = (u >= 0) & (u < self.data["W"]) & (v >= 0) & (v < self.data["H"])
        out[~inside] = 255
        return out


def neighbour_land(u, v, noise):
    """Land round the game's countries: a continent to the north, west and east, sea to the south."""
    south = (v - SEA_V) * KM
    bias = np.clip(-south / 260, -1.2, 0.7)
    return noise - 0.5 + bias * 0.5 > 0


def lights_points(geo, rng):
    """City lights as (x, y, brightness, spread km) in world km."""
    pts = []
    d = geo.data
    centres = []
    for r in d["regions"]:
        if r["city"]:
            continue
        x, y = to_world(*r["center"])
        centres.append((float(x), float(y)))
    for cap in d["capitals"]:
        x, y = to_world(*cap)
        centres.append((float(x), float(y)))
        pts.append((float(x), float(y), 9.0, 16.0, 2200))
    for x, y in centres:
        pts.append((x, y, rng.uniform(2.5, 4.5), rng.uniform(6, 10), 500))
    # Towns over the whole continent, more near the cities.
    for _ in range(1400):
        x, y = rng.uniform(-2600, 2600), rng.uniform(-900, 2600)
        pts.append((x, y, rng.uniform(0.6, 1.8), rng.uniform(1.5, 4), 40))
    for _ in range(900):
        cx, cy = rng.choice(centres)
        a, r = rng.uniform(0, math.tau), abs(rng.gauss(0, 140))
        pts.append((cx + math.cos(a) * r, cy + math.sin(a) * r, rng.uniform(0.7, 2.0), rng.uniform(1.5, 3.5), 40))
    # Roads: strings of lights between neighbouring cities.
    for i, (x0, y0) in enumerate(centres):
        near = sorted(range(len(centres)), key=lambda j: (centres[j][0] - x0) ** 2 + (centres[j][1] - y0) ** 2)[1:4]
        for j in near:
            x1, y1 = centres[j]
            n = int(math.hypot(x1 - x0, y1 - y0) / 5)
            wob = rng.uniform(-0.15, 0.15)
            for k in range(n):
                t = k / max(1, n)
                bend = math.sin(t * math.pi) * wob
                x = x0 + (x1 - x0) * t - (y1 - y0) * bend
                y = y0 + (y1 - y0) * t + (x1 - x0) * bend
                if rng.random() < 0.3:
                    pts.append((x, y, rng.uniform(0.3, 0.9), 1.2, 6))
    return pts


def splat(points, x0, y0, px, shape, rng, land):
    """Lights on a grid: every point scatters `count` specks round itself, then a soft blur."""
    h, w = shape
    acc = np.zeros(shape, np.float32)
    for x, y, b, spread, count in points:
        xs = x + rng.normal(0, spread, count)
        ys = y + rng.normal(0, spread, count)
        j = ((xs - x0) / px).astype(np.int64)
        i = ((y0 - ys) / px).astype(np.int64)
        ok = (i >= 0) & (i < h) & (j >= 0) & (j < w)
        np.add.at(acc, (i[ok], j[ok]), b * rng.uniform(0.4, 1.0, ok.sum()).astype(np.float32))
    acc *= land
    return blur(acc, 0.8) + blur(acc, 3.0) * 0.6


def colour_ground(land, terrain, lights, game_side=None):
    """Night ground: dark land with relief, near-black sea, sodium city lights."""
    gy, gx = np.gradient(terrain)
    shade = np.clip(0.75 + (gx - gy) * 60, 0.4, 1.3)
    landc = (np.array([16, 20, 18], np.float32) + terrain[..., None] * np.array([20, 22, 16], np.float32)) * shade[..., None]
    seac = np.array([6, 9, 16], np.float32) + terrain[..., None] * np.array([2, 3, 6], np.float32)
    col = np.where(land[..., None], landc, seac)
    l = lights[..., None]
    col = col + np.clip(l * 42, 0, 255) * np.array([1.0, 0.62, 0.28], np.float32) + np.clip(l * 42 - 200, 0, 255) * np.array([0.0, 0.35, 0.45], np.float32)
    return col


def build_low(geo, noise, terrain, pts, rng):
    n, px = LOW_N, LOW_PX
    half = n * px / 2
    jj, ii = np.meshgrid(np.arange(n), np.arange(n))
    x = -half + (jj + 0.5) * px
    y = half - (ii + 0.5) * px
    u, v = to_map(x, y)
    gid = geo.id_at(u, v)
    land = (gid != 255) | neighbour_land(u, v, noise)
    lights = splat(pts, -half, half, px, (n, n), rng, land)
    return colour_ground(land, terrain, lights), (-half, half, px)


def build_high(geo, noise_low, terrain_low, pts, rng):
    """The game's countries at full detail, with the alert map over them."""
    ids = geo.ids
    h, w = ids.shape
    S = geo.S
    jj, ii = np.meshgrid(np.arange(w), np.arange(h))
    u, v = (jj + 0.5) / S, (ii + 0.5) / S
    x, y = to_world(u, v)
    # The low-resolution fields, read at these points.
    half = LOW_N * LOW_PX / 2
    lj = np.clip(((x + half) / LOW_PX).astype(np.int64), 0, LOW_N - 1)
    li = np.clip(((half - y) / LOW_PX).astype(np.int64), 0, LOW_N - 1)
    nz = blur(noise_low, 1.0)[li, lj]
    detail = fbm(max(h, w), 60, 4, 77)[:h, :w]
    terrain = blur(terrain_low, 1.0)[li, lj] * 0.75 + detail * 0.25
    game = ids != 255
    land = game | neighbour_land(u, v, nz)
    px = KM / S
    lights = splat(pts, float(x[0, 0]) - px / 2, float(y[0, 0]) + px / 2, px, (h, w), rng, land)
    col = colour_ground(land, terrain, lights)
    side = np.where(game, geo.side[ids], -1)
    alert = np.where(game, geo.alert[ids], 0)
    # Enemy land a shade redder, as on the game's map.
    col = np.where((side == 1)[..., None], col * 0.85 + np.array([16, 3, 4], np.float32), col)
    col = np.where((side == 0)[..., None], col * 0.7 + np.array([40, 46, 62], np.float32) * 0.3, col)
    # The alert map: regions under alert washed in yellow or red, their edges bright.
    tint = np.where((alert == 2)[..., None], MISSILE, AIR)
    a = np.where(alert > 0, 0.42, 0.0)[..., None]
    col = col * (1 - a) + tint * 0.85 * a + tint * a * np.clip(lights[..., None] * 0.15, 0, 0.4)
    # Borders: between regions faint, the front bright, alerted regions outlined in their colour.
    diff_r = np.zeros((h, w), bool)
    diff_s = np.zeros((h, w), bool)
    for dy, dx in ((0, 1), (1, 0)):
        a_ids, b_ids = ids[: h - dy, : w - dx], ids[dy:, dx:]
        dr = (a_ids != b_ids) & (a_ids != 255) & (b_ids != 255) & ~geo.city[a_ids] & ~geo.city[b_ids]
        ds = dr & (geo.side[a_ids] != geo.side[b_ids])
        diff_r[: h - dy, : w - dx] |= dr
        diff_s[: h - dy, : w - dx] |= ds
    edge_r = np.clip(blur(diff_r.astype(np.float32), 0.7) * 3, 0, 1)[..., None]
    edge_s = np.clip(blur(diff_s.astype(np.float32), 1.2) * 3, 0, 1)[..., None]
    alerted_edge = edge_r * (alert > 0)[..., None]
    col = col * (1 - edge_r * 0.35) + np.array([120, 125, 135], np.float32) * edge_r * 0.35
    col = col + tint * alerted_edge * 0.3
    col = col * (1 - edge_s * 0.8) + np.array([255, 235, 220], np.float32) * edge_s * 0.8
    outer = np.zeros((h, w), bool)
    for dy, dx in ((0, 1), (1, 0)):
        outer[: h - dy, : w - dx] |= game[: h - dy, : w - dx] != game[dy:, dx:]
    outer &= neighbour_land(u, v, nz)
    col = col + np.array([150, 150, 160], np.float32) * np.clip(blur(outer.astype(np.float32), 0.9) * 2, 0, 1)[..., None] * 0.45
    # The coast of the game's countries, a soft line where land meets sea.
    coast = np.zeros((h, w), bool)
    for dy, dx in ((0, 1), (1, 0)):
        coast[: h - dy, : w - dx] |= game[: h - dy, : w - dx] != game[dy:, dx:]
    coast &= ~neighbour_land(u, v, nz)
    col = col + np.array([60, 80, 100], np.float32) * np.clip(blur(coast.astype(np.float32), 0.8) * 2, 0, 1)[..., None] * 0.5
    return col, (float(x[0, 0]) - px / 2, float(y[0, 0]) + px / 2, px)


def sample(tex, frame, x, y):
    """Bilinear lookup of world points in a texture; returns colours and which were inside."""
    x0, y0, px = frame
    h, w, _ = tex.shape
    fj = (x - x0) / px - 0.5
    fi = (y0 - y) / px - 0.5
    inside = (fj >= 0) & (fj < w - 1) & (fi >= 0) & (fi < h - 1)
    j = np.clip(np.floor(fj).astype(np.int64), 0, w - 2)
    i = np.clip(np.floor(fi).astype(np.int64), 0, h - 2)
    a = np.clip(fj - j, 0, 1)[:, None]
    b = np.clip(fi - i, 0, 1)[:, None]
    out = (tex[i, j] * (1 - a) * (1 - b) + tex[i, j + 1] * a * (1 - b) + tex[i + 1, j] * (1 - a) * b
           + tex[i + 1, j + 1] * a * b)
    return out, inside


# --- the camera ---------------------------------------------------------------------------

def surface(x, y, alt=0.0):
    """A ground point (km east, km north) and height to 3D, on the sphere."""
    s = math.hypot(x, y)
    th, ph = s / R, math.atan2(y, x)
    r = R + alt
    return np.array([r * math.sin(th) * math.cos(ph), r * math.sin(th) * math.sin(ph), r * math.cos(th) - R])


class Cam:
    def __init__(self, w, h):
        self.w, self.h = w, h
        self.pos = surface(CAM[0], CAM[1], CAM[2])
        f = surface(*LOOK) - self.pos
        self.fwd = f / np.linalg.norm(f)
        up = (self.pos - np.array([0, 0, -R])) / np.linalg.norm(self.pos - np.array([0, 0, -R]))
        r = np.cross(self.fwd, up)
        self.right = r / np.linalg.norm(r)
        self.up = np.cross(self.right, self.fwd)
        self.f = FOCAL * w

    def project(self, p):
        d = p - self.pos
        z = float(d @ self.fwd)
        return self.w / 2 + self.f * float(d @ self.right) / z, self.h / 2 - self.f * float(d @ self.up) / z, z

    def at(self, u, v, alt=0.0):
        x, y = to_world(u, v)
        return self.project(surface(float(x), float(y), alt))


def sun_dir(cam):
    up = (cam.pos + np.array([0, 0, R])) / np.linalg.norm(cam.pos + np.array([0, 0, R]))
    ahead = cam.fwd - (cam.fwd @ up) * up
    ahead /= np.linalg.norm(ahead)
    side = np.cross(ahead, up)
    az = math.radians(SUN_AZ)
    el = -math.acos(R / (R + CAM[2])) - math.radians(SUN_DIP)
    flat = ahead * math.cos(az) + side * math.sin(az)
    return flat * math.cos(el) + up * math.sin(el)


def render_globe(cam, low, high):
    w, h = cam.w, cam.h
    xs = (np.arange(w, dtype=np.float64) - w / 2) / cam.f
    ys = (h / 2 - np.arange(h, dtype=np.float64)) / cam.f
    d = cam.fwd[None, None] + xs[None, :, None] * cam.right[None, None] + ys[:, None, None] * cam.up[None, None]
    d = (d / np.linalg.norm(d, axis=2, keepdims=True)).reshape(-1, 3)
    oc = cam.pos - np.array([0.0, 0.0, -R])
    b = d @ oc
    c = oc @ oc - R * R
    disc = b * b - c
    hit = disc > 0
    t = -b[hit] - np.sqrt(disc[hit])
    p = cam.pos + d[hit] * t[:, None] + np.array([0, 0, R])
    n = p / R
    th = np.arccos(np.clip(n[:, 2], -1, 1))
    ph = np.arctan2(n[:, 1], n[:, 0])
    gx, gy = R * th * np.cos(ph), R * th * np.sin(ph)
    col = np.zeros((len(d), 3), np.float32)
    lo, _ = sample(*low, gx, gy)
    hi, inside = sample(*high, gx, gy)
    g = np.where(inside[:, None], hi, lo)
    # Haze: the more slanting the view of the ground, the more air in the way.
    sun = sun_dir(cam)
    toward = np.clip(d @ sun, -1, 1)
    warm_wide = np.exp((toward - 1) / 0.14)
    warm_near = np.exp((toward - 1) / 0.02)
    mu = np.clip(-(d[hit] * n).sum(1), 0, 1)
    haze = np.exp(-mu / 0.09)[:, None]
    hazec = np.array([14, 30, 70], np.float32) * (1 - warm_wide[hit][:, None]) + warm_wide[hit][:, None] * np.array([150, 75, 30], np.float32)
    g = g * (1 - 0.85 * haze) + hazec * haze
    col[hit] = g
    # The atmosphere at the limb, airglow above it, stars in the dark.
    ray_alt = np.sqrt(np.maximum(oc @ oc - b * b, 0)) - R
    sky = ~hit
    ra = ray_alt[sky]
    ww, wn = warm_wide[sky][:, None], warm_near[sky][:, None]
    glow = np.exp(-np.clip(ra, 0, None) / 28)[:, None] * np.array([40, 110, 230], np.float32) * (1 - 0.85 * ww)
    glow += np.exp(-np.clip(ra, 0, None) / 9)[:, None] * (np.array([60, 140, 255], np.float32) * (1 - ww)
                                                         + np.array([255, 150, 60], np.float32) * ww)
    # Dawn: an orange band on the limb towards the sun, gold where it is about to rise.
    glow += np.exp(-np.clip(ra, 0, None) / 45)[:, None] * ww * np.array([200, 90, 30], np.float32)
    glow += np.exp(-np.clip(ra, 0, None) / 150)[:, None] * ww * np.array([60, 28, 22], np.float32)
    glow += np.exp(-np.clip(ra, 0, None) / 26)[:, None] * wn * np.array([255, 175, 80], np.float32) * 1.3
    glow += np.exp(-((ra - 95) / 9) ** 2)[:, None] * np.array([6, 22, 12], np.float32)
    col[sky] = glow
    rng = np.random.default_rng(2)
    star = rng.random(len(d)) < 0.0012
    col[sky & star] += rng.uniform(60, 200, (sky & star).sum())[:, None]
    return col.reshape(h, w, 3)


# --- the battle ---------------------------------------------------------------------------------

def arc_points(cam, a, b, apex, n=160, upto=1.0):
    """A ballistic arc from map point a to map point b, `apex` km high, up to fraction `upto`."""
    out = []
    for t in np.linspace(0, upto, n):
        u, v = a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t
        out.append(cam.at(u, v, apex * 4 * t * (1 - t)))
    return out


def trail(d, pts, colour, width, tail=1.4):
    n = len(pts)
    for i in range(n - 1):
        if pts[i][2] < 1 or pts[i + 1][2] < 1:
            continue
        k = (i / (n - 1)) ** tail
        c = tuple(int(x * (0.08 + 0.92 * k)) for x in colour)
        d.line([pts[i][:2], pts[i + 1][:2]], fill=c, width=max(1, int(round(width * (0.5 + 0.5 * k)))))


def dot(d, x, y, r, colour):
    d.ellipse([x - r, y - r, x + r, y + r], fill=colour)


# Glyphs for the sites, as in the game: in a box from -1 to 1, y down.
STAR = [(math.cos(math.radians(-90 + 36 * k)) * (1 if k % 2 == 0 else 0.42),
         math.sin(math.radians(-90 + 36 * k)) * (1 if k % 2 == 0 else 0.42)) for k in range(10)]
FACTORY = [(-1, 1), (-1, -0.1), (-0.5, -0.55), (-0.5, -0.1), (0, -0.55), (0, -0.1), (0.42, -0.55),
           (0.42, -1), (0.8, -1), (0.8, 1)]
ROCKET = [(0, -1), (0.24, -0.6), (0.24, 0.45), (0.55, 0.95), (0.24, 0.8), (-0.24, 0.8), (-0.55, 0.95),
          (-0.24, 0.45), (-0.24, -0.6)]
GUN = [(-0.85, 0.95), (-0.85, 0.35), (-0.25, 0.35), (0.55, -0.85), (0.85, -0.6), (0.2, 0.35), (0.85, 0.35),
       (0.85, 0.95)]
# A cruise missile from above, nose along +x: body, swept wings, tail fins.
CRUISE = [(1.0, 0), (0.86, -0.07), (0.15, -0.07), (-0.05, -0.42), (-0.17, -0.42), (-0.1, -0.07),
          (-0.8, -0.07), (-0.98, -0.22), (-1.05, -0.22), (-1.0, 0), (-1.05, 0.22), (-0.98, 0.22),
          (-0.8, 0.07), (-0.1, 0.07), (-0.17, 0.42), (-0.05, 0.42), (0.15, 0.07), (0.86, 0.07)]
OUR_RIM, THEIR_RIM = (80, 165, 255), (235, 80, 65)


def shape(pts, x, y, size, angle=0.0):
    c, s_ = math.cos(angle), math.sin(angle)
    return [(x + (px * c - py * s_) * size, y + (px * s_ + py * c) * size) for px, py in pts]


def badge(o, light, x, y, r, glyph, rim):
    """A site on the ground: a dark disc with a coloured rim and a white glyph."""
    dot(light, x, y, r * 1.6, tuple(int(c * 0.35) for c in rim))
    o.ellipse([x - r, y - r, x + r, y + r], fill=(18, 22, 32, 255), outline=rim + (255,), width=max(2, int(r * 0.2)))
    o.polygon(shape(glyph, x, y, r * 0.52), fill=(245, 246, 250, 255))


def ground_ring(d, cam, u0, v0, radius, colour, width):
    pts = [cam.at(u0 + math.cos(a) * radius, v0 + math.sin(a) * radius)[:2] for a in np.linspace(0, math.tau, 120)]
    d.line(pts, fill=colour, width=width)


def heading(cam, u, v, du, dv, alt=2.0):
    """Screen position, screen angle and depth of something at (u, v) moving along (du, dv)."""
    x0, y0, z = cam.at(u, v, alt)
    x1, y1, _ = cam.at(u + du, v + dv, alt)
    return x0, y0, math.atan2(y1 - y0, x1 - x0), z


def explosion(o, light, x, y, r, rng, smoke=True):
    """A fireball with smoke round it and burning debris falling out of it."""
    if smoke:
        for _ in range(9):
            a, dist = rng.uniform(0, math.tau), r * rng.uniform(0.5, 1.4)
            rr = r * rng.uniform(0.6, 1.0)
            px, py = x + math.cos(a) * dist, y + math.sin(a) * dist - r * 0.4
            o.ellipse([px - rr, py - rr, px + rr, py + rr], fill=(46, 40, 40, 120))
    for _ in range(7):
        a, dist = rng.uniform(0, math.tau), r * rng.uniform(0, 0.55)
        rr = r * rng.uniform(0.35, 0.6)
        px, py = x + math.cos(a) * dist, y + math.sin(a) * dist
        dot(light, px, py, rr, (255, rng.randint(120, 170), 50))
    dot(light, x, y, r * 0.4, (255, 245, 220))
    for _ in range(12):
        a = rng.uniform(-0.25 * math.pi, 1.25 * math.pi)
        px, py = x + math.cos(a) * r * 0.8, y + math.sin(a) * r * 0.5
        ln = r * rng.uniform(0.8, 1.8)
        light.line([(px, py), (px + math.cos(a) * ln * 0.5, py + ln)], fill=(255, 150, 60), width=max(1, int(r * 0.07)))


def battle(img, cam, geo):
    data = geo.data
    rng = random.Random(4)
    w, h = img.size
    sc = w / 2520
    light = Image.new("RGB", img.size)
    d = ImageDraw.Draw(light)
    ours = data["capitals"][0]
    theirs = data["capitals"][1]
    kinds = data["kinds"]
    # A few sites each side: the capitals, air defence round ours, factories.
    sites = [(0, kinds["capital"], ours), (0, kinds["sam"], (322, 300)), (0, kinds["sam"], (366, 349)),
             (0, kinds["factory"], (325, 235)), (0, kinds["factory"], (333, 351)), (0, kinds["gun"], (311, 229)),
             (1, kinds["capital"], theirs), (1, kinds["sam"], (844, 350)), (1, kinds["factory"], (770, 341)),
             (1, kinds["factory"], (700, 215))]
    sites = [t for t in sites if geo.side[geo.id_at(np.array([t[2][0]]), np.array([t[2][1]]))[0]] == t[0]]
    sams = [p for side, k, p in sites if side == 0 and k == kinds["sam"]]

    # A ballistic missile met by two of our SAMs over the capital, another still coming.
    hit_t = 0.9
    a_, b_ = (905, 250), (ours[0] + 8, ours[1] - 4)
    full = arc_points(cam, a_, b_, 150, 200, 1.0)
    upto = int(len(full) * hit_t)
    trail(d, full[:upto], (255, 120, 70), 7 * sc)
    trail(d, full[:upto], (255, 225, 190), 2.5 * sc, 2.5)
    hx, hy, hz = full[upto - 1]
    hit_uv = (a_[0] + (b_[0] - a_[0]) * hit_t, a_[1] + (b_[1] - a_[1]) * hit_t)
    hit_alt = 150 * 4 * hit_t * (1 - hit_t)
    for s0 in sams[:2]:
        pts = []
        for t in np.linspace(0, 1, 60):
            u = s0[0] + (hit_uv[0] - s0[0]) * t ** 1.6
            v = s0[1] + (hit_uv[1] - s0[1]) * t ** 1.6
            pts.append(cam.at(u, v, hit_alt * (1 - (1 - t) ** 2)))
        trail(d, pts, BLUE, 5 * sc, 1.1)
    pts = arc_points(cam, (960, 430), (380, 340), 140, 200, 0.68)
    trail(d, pts, (255, 120, 70), 6 * sc)
    trail(d, pts, (255, 225, 190), 2 * sc, 2.5)
    x, y, _ = pts[-1]
    dot(d, x, y, 8 * sc, (150, 50, 25))
    dot(d, x, y, 3.5 * sc, (255, 240, 220))

    # A few drones and two cruise missiles crossing the front, heading west.
    craft = [(0, (560, 250)), (0, (585, 300)), (0, (530, 330)), (0, (610, 210)), (0, (500, 280)),
             (0, (545, 395)), (1, (640, 360)), (1, (690, 250))]
    bodies = []
    for arm, (u, v) in craft:
        du, dv = -1.0, rng.uniform(-0.15, 0.15)
        pts = [cam.at(u - du * 160 * (1 - t), v - dv * 160 * (1 - t), 2) for t in np.linspace(0, 1, 24)]
        colour = (200, 60, 50) if arm == 0 else (230, 120, 60)
        for j in range(0, len(pts) - 1, 2):
            k = (j / len(pts)) ** 1.5
            d.line([pts[j][:2], pts[j + 1][:2]], fill=tuple(int(c * 0.5 * k) for c in colour), width=max(1, int(2 * sc)))
        bodies.append((arm,) + heading(cam, u, v, du * 5, dv * 5))
    # One drone just hit by an AA gun.
    gun = sams[-1]
    bx, by, bz = cam.at(470, 395, 2)
    gx, gy, _ = cam.at(*gun)
    d.line([(gx, gy), (bx, by)], fill=(50, 100, 170), width=max(1, int(2 * sc)))
    zs = sorted(b[4] for b in bodies)
    zref = zs[len(zs) // 2]

    img = img.convert("RGB")
    for r in (2 * sc, 8 * sc, 22 * sc):
        img = ImageChops.screen(img, light.filter(ImageFilter.GaussianBlur(r)))
    img = ImageChops.screen(img, light)

    # Sites on the ground, then what flies over them.
    over = Image.new("RGBA", img.size, (0, 0, 0, 0))
    o = ImageDraw.Draw(over)
    glow = Image.new("RGB", img.size)
    g = ImageDraw.Draw(glow)
    glyphs = {kinds["capital"]: STAR, kinds["factory"]: FACTORY, kinds["sam"]: ROCKET, kinds["gun"]: GUN}
    for side, k, (u, v) in sorted(sites, key=lambda t: -cam.at(*t[2])[2]):
        x, y, z = cam.at(u, v)
        r = 21 * sc * min(1.5, max(0.7, (zref / z) ** 0.8)) * (1.35 if k == kinds["capital"] else 1.0)
        badge(o, g, x, y, r, glyphs[k], OUR_RIM if side == 0 else THEIR_RIM)
    for arm, x, y, ang, z in sorted(bodies, key=lambda b_: -b_[4]):
        size = 30 * sc * min(1.5, max(0.7, (zref / z) ** 0.8))
        if arm == 0:
            for part in SHAHED:
                o.polygon(shape(part, x, y, size, ang), fill=(196, 50, 42, 255), outline=(120, 26, 22, 255))
        else:
            tx, ty = x - math.cos(ang) * size * 1.4, y - math.sin(ang) * size * 1.4
            g.line([(tx, ty), (x, y)], fill=(255, 190, 110), width=max(2, int(size * 0.2)))
            o.polygon(shape(CRUISE, x, y, size * 1.25, ang), fill=(220, 110, 64, 255), outline=(130, 50, 30, 255))
    img = ImageChops.screen(img, glow.filter(ImageFilter.GaussianBlur(4 * sc)))
    img = img.convert("RGBA")
    img.alpha_composite(over)
    img = img.convert("RGB")

    # The interception, the drone hit by the gun, and two fires where strikes landed.
    smoke = Image.new("RGBA", img.size, (0, 0, 0, 0))
    fire = Image.new("RGB", img.size)
    so, fi = ImageDraw.Draw(smoke), ImageDraw.Draw(fire)
    erng = random.Random(9)
    explosion(so, fi, hx, hy, 48 * sc, erng)
    explosion(so, fi, bx, by, 24 * sc, erng)
    for u, v, s_ in ((770, 330, 1.0), (430, 300, 0.8)):
        x, y, z = cam.at(u, v)
        dot(fi, x, y, 11 * sc * s_, (255, 120, 40))
        dot(fi, x, y, 4.5 * sc * s_, (255, 230, 170))
        for _ in range(5):
            so.ellipse([x - 14 * sc * s_, y - 30 * sc * s_ - _ * 9 * sc, x + 14 * sc * s_, y - 4 * sc * s_ - _ * 9 * sc],
                       fill=(40, 36, 38, 70))
    img = img.convert("RGBA")
    img.alpha_composite(smoke.filter(ImageFilter.GaussianBlur(5 * sc)))
    img = img.convert("RGB")
    img = ImageChops.screen(img, fire.filter(ImageFilter.GaussianBlur(9 * sc)))
    img = ImageChops.screen(img, fire.filter(ImageFilter.GaussianBlur(1.5 * sc)))
    return img


def grade(img):
    arr = np.asarray(img, np.float32) / 255
    w, h = img.size
    lum = arr @ np.array([0.3, 0.59, 0.11], np.float32)
    hi = Image.fromarray((np.clip(lum - 0.5, 0, 1) / 0.5 * 255).astype(np.uint8))
    for r, s in ((w * 0.01, 0.3), (w * 0.04, 0.25)):
        bl = np.asarray(hi.filter(ImageFilter.GaussianBlur(r)), np.float32)[..., None] / 255
        arr = 1 - (1 - arr) * (1 - bl * s * np.array([1.0, 0.8, 0.6], np.float32))
    yy, xx = np.mgrid[0:h, 0:w].astype(np.float32)
    v = 1 - 0.35 * (((xx - w / 2) / (w * 0.75)) ** 2 + ((yy - h / 2) / (h * 0.75)) ** 2)
    arr *= np.clip(v, 0.5, 1)[..., None]
    arr = arr * 255 + np.random.default_rng(5).normal(0, 2.0, (h, w))[..., None]
    return Image.fromarray(np.clip(arr, 0, 255).astype(np.uint8))


def with_logo(img):
    w, h = img.size
    out = img.convert("RGBA")
    lg = Image.open(LOGO).convert("RGBA")
    lw = int(w * 0.66)
    lg = lg.resize((lw, round(lg.height * lw / lg.width)), Image.LANCZOS)
    out.alpha_composite(lg, ((w - lw) // 2, int(h * 0.045)))
    return out.convert("RGB")


def main():
    geo_dir, out = sys.argv[1], sys.argv[2]
    preview = "--preview" in sys.argv
    w, h = (630, 500) if preview else (2520, 2000)
    rng = np.random.default_rng(11)
    noise = fbm(LOW_N, 330, 6, 3)
    terrain = fbm(LOW_N, 90, 6, 9)
    pts = lights_points(Geo(geo_dir), random.Random(6))
    geo = Geo(geo_dir)
    low = build_low(geo, noise, terrain, pts, rng)
    high = build_high(geo, noise, terrain, pts, rng)
    cam = Cam(w, h)
    img = Image.fromarray(np.clip(render_globe(cam, low, high), 0, 255).astype(np.uint8))
    img = battle(img, cam, geo)
    img = with_logo(grade(img))
    if preview:
        img.save(os.path.join(out, "orbit-preview.png"))
    else:
        img.resize((1260, 1000), Image.LANCZOS).save(os.path.join(out, "cover-orbit-1260.png"))
        img.resize((630, 500), Image.LANCZOS).save(os.path.join(out, "cover-orbit.png"))
    print("wrote", out)


if __name__ == "__main__":
    main()
