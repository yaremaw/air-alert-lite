"""A cinematic trailer for Strike Alert rendered from a small 3D scene: an air
raid over a night city, a ballistic missile diving out of the clouds, an
interceptor launching from the rooftop beside the camera to meet it, the hit in
slow motion, more interceptions over the city, then the logo and an end card.
Enemies are red and the air defence blue, as on the game's map.

    python tools/intercept_video.py itch                        # both formats
    python tools/intercept_video.py itch 9x16                   # just one
    python tools/intercept_video.py --stills DIR 9x16 2.0 6.4   # preview frames at these seconds

writes strike-alert-intercept-9x16.mp4 (1080x1920) and -16x9.mp4 (1920x1080),
with sound mixed from the game's own effects. World units are metres: x right,
y up, z away from the camera. Needs ffmpeg (pip install imageio-ffmpeg).
"""
import math
import os
import random
import subprocess
import sys
import tempfile
import wave
from multiprocessing import Pool

import imageio_ffmpeg
import numpy as np
from PIL import Image, ImageChops, ImageDraw, ImageFilter

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from itch_poster3d import drone_mesh, fbm, norm, place, reflect, v3  # noqa: E402
from promo_video import GOOD, MUTED, PAGE, TEXT, font, logo, pill  # noqa: E402

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
AUDIO = os.path.join(ROOT, "assets", "audio")
FPS, SR = 30, 44100
SCENE, END = 13.0, 3.0  # seconds of the scene, then of the end card
FORMATS = {
    # size, focal length in pixels, camera pitch at the start, at the launch, at the hit and at the end,
    # how far the camera zooms in on the hit
    "9x16": ((1080, 1920), 1144, (5, 8, 21, 24), 0.16),
    "16x9": ((1920, 1080), 1333, (-2, 1, 20, 21), 0.0),
}

RED = (255, 62, 50)
BLUE = (70, 160, 255)
CAM0 = v3(0, 66, 0)          # on a rooftop, 66 m up
ROOF_Y, ROOF_Z = 56.0, 46.0  # the lower roof in front of the camera, and its far edge
CLOUD_Y = 900.0
T_LAUNCH, T_HIT = 3.3, 6.3


def toward(dist, elev, az):
    e, a = math.radians(elev), math.radians(az)
    return CAM0 + dist * v3(math.sin(a) * math.cos(e), math.sin(e), math.cos(a) * math.cos(e))


def smooth(a, b, x):
    t = min(max((x - a) / (b - a), 0.0), 1.0)
    return t * t * (3 - 2 * t)


def bez(a, c, b, s):
    s = np.asarray(s, np.float64)[..., None]
    return (1 - s) ** 2 * a + 2 * (1 - s) * s * c + s * s * b


def flight(tau, t0, t1):
    """How far along its path a missile launched at t0 to arrive at t1 is: it accelerates."""
    return min(max((tau - t0) / (t1 - t0), 0.0), 1.0) ** 1.5


# --- the story ------------------------------------------------------------------

# The launcher on the lower roof, its four-tube pod raised towards the threat.
LAUNCHER = v3(4.0, ROOF_Y, 15.0)
POD = norm(v3(-0.18, 0.45, 0.88))
PIVOT = LAUNCHER + v3(0, 1.8, -1.8)
MOUTH = PIVOT + POD * 6.4
# The ballistic missile breaks out of the clouds at T_SEEN and is hit at H.
H = toward(950, 32, -9)
T_SEEN = 1.3
B_START = toward(4000, 39, -19)
B_DIR = norm(H - B_START)
B_SPEED = float(np.linalg.norm(H - B_START)) / (T_HIT - T_SEEN)
CTRL = MOUTH + POD * 380


def ballistic_at(tau):
    return H + B_DIR * B_SPEED * (tau - T_HIT)


# A stream of attack drones from the far horizon to right over the camera.
SWARM_A = toward(2600, 2.5, 16)
SWARM_B = CAM0 + v3(-25, 40, 30)
SWARM_DIR = norm(SWARM_B - SWARM_A)
SWARM_LEN = float(np.linalg.norm(SWARM_B - SWARM_A))
SWARM_SIDE = norm(np.cross(v3(0, 1, 0), SWARM_DIR))
DRONE_SPEED = 48.0


def make_swarm():
    rng = random.Random(5)
    drones, s = [], 60.0
    while s < 2050:
        drones.append((s, rng.uniform(-60, 60), rng.uniform(-25, 25), rng.uniform(-0.25, 0.25)))
        s += rng.uniform(70, 120)
    return drones


DRONES = make_swarm()


def drone_at(k, tau):
    s, lat, vert, _ = DRONES[k]
    return SWARM_A + SWARM_DIR * (s + DRONE_SPEED * tau) + SWARM_SIDE * lat + v3(0, vert, 0)


# Two cruise missiles skimming low across the city.
CRUISE = [v3(760, 150, 1150), v3(1000, 125, 1480)]
CRUISE_V = v3(-235, 0, 0)


def cruise_at(j, tau):
    return CRUISE[j] + CRUISE_V * (tau - 3.0)


# Air defence sites in the city and what they shoot down: (site, launch, hit, kind, index).
SITES = [v3(-420, 0, 1500), v3(380, 0, 1300), v3(-80, 0, 2300)]


def pick_drone(tau, dist, taken):
    def score(k):
        p = drone_at(k, tau) - CAM0
        az = math.degrees(math.atan2(p[0], p[2]))
        return abs(np.linalg.norm(p) - dist) + 40 * abs(az - 2)
    return min((k for k in range(len(DRONES)) if k not in taken), key=score)


K1 = pick_drone(8.3, 700, ())
K2 = pick_drone(9.5, 950, (K1,))
SHOTS = [(1, 5.2, 7.8, "cruise", 0), (0, 5.9, 8.3, "drone", K1), (2, 6.9, 9.5, "drone", K2)]


def target_at(kind, i, tau):
    return cruise_at(i, tau) if kind == "cruise" else drone_at(i, tau)


def shot_path(site, kind, i, t_hit):
    end = target_at(kind, i, t_hit)
    start = SITES[site] + v3(0, 4, 0)
    ctrl = v3(start[0], end[1] * 0.85, start[2]) + (end - start) * v3(0.2, 0, 0.2)
    return start, ctrl, end


# Explosions: (time, position, size in metres, the big one?, seed).
EXPLOSIONS = [(T_HIT, H, 60.0, True, 1)] + [
    (t1, target_at(kind, i, t1), 16.0, False, 2 + n) for n, (_, _, t1, kind, i) in enumerate(SHOTS)]
KILLED = {(kind, i): t1 for _, _, t1, kind, i in SHOTS}


def flash_level(tau):
    a = tau - T_HIT
    if a < 0:
        return 0.0
    return 1.6 * math.exp(-a / 0.35) * (1 - math.exp(-a / 0.02)) + 0.25 * math.exp(-a / 2.0)


def launch_level(tau):
    a = tau - T_LAUNCH
    if a < 0:
        return 0.0
    return 1.2 * math.exp(-a / 0.35) + 0.35 * math.exp(-a / 1.5)


def make_puffs():
    """Smoke: (birth, position, drift velocity, full radius, life, kind)."""
    rng = random.Random(9)
    puffs = []
    for _ in range(46):  # the launch cloud billowing round the launcher
        a = rng.uniform(0, math.tau)
        vel = v3(math.cos(a) * rng.uniform(2, 7), rng.uniform(0.3, 2.5), math.sin(a) * rng.uniform(2, 7)) - POD * rng.uniform(2, 7)
        pos = MOUTH - POD * rng.uniform(0, 6) + v3(rng.uniform(-1.5, 1.5), rng.uniform(-1, 0.5), rng.uniform(-1.5, 1.5))
        puffs.append((T_LAUNCH + rng.uniform(0, 0.35), pos, vel, rng.uniform(1.2, 2.8), 6.0, "launch"))
    for i in range(30):  # along the first part of the climb
        b = T_LAUNCH + 0.04 + i * 0.03
        p = bez(MOUTH, CTRL, H, flight(b, T_LAUNCH, T_HIT))
        along = float(np.linalg.norm(p - MOUTH))
        jit = v3(rng.uniform(-1, 1), rng.uniform(-1, 1), rng.uniform(-1, 1)) * (0.5 + along * 0.01)
        puffs.append((b, p + jit, v3(rng.uniform(-1.5, 1.5), rng.uniform(0, 1.5), rng.uniform(-1.5, 1.5)),
                      2.2 + along * 0.025, 4.5, "launch"))
    for t0, pos, size, big, seed in EXPLOSIONS:
        r = random.Random(seed)
        for _ in range(16 if big else 6):
            dirn = norm(v3(r.uniform(-1, 1), r.uniform(-0.6, 1), r.uniform(-1, 1)))
            puffs.append((t0 + r.uniform(0.05, 0.3), pos + dirn * size * r.uniform(0.1, 0.5), dirn * size * r.uniform(0.4, 0.9),
                          size * r.uniform(0.5, 0.9), 7.0, "blast"))
    return puffs


PUFFS = make_puffs()


def make_towers():
    rng = random.Random(21)
    towers = []
    while len(towers) < 18:
        x, z = rng.uniform(-1200, 1200), rng.uniform(320, 2700)
        if any(math.hypot(x - s[0], z - s[2]) < 220 for s in SITES):
            continue
        hgt = rng.uniform(40, 120) * (1.6 if rng.random() < 0.25 else 1.0)
        half = (rng.uniform(12, 23), hgt / 2, rng.uniform(12, 23))
        yaw = math.radians(28 + rng.choice((0, 90)) + rng.uniform(-4, 4))
        axes = (v3(math.cos(yaw), 0, -math.sin(yaw)), v3(0, 1, 0), v3(math.sin(yaw), 0, math.cos(yaw)))
        # Lit windows on each side, as (across, up) offsets from the face centre.
        windows = []
        for side in range(4):
            across = half[2] if side < 2 else half[0]
            lit = []
            for u in np.arange(-across + 2.5, across - 1.5, 3.4):
                for v in np.arange(-half[1] + 3, half[1] - 2, 3.6):
                    if rng.random() < 0.16:
                        lit.append((float(u), float(v), rng.uniform(0.5, 1.0)))
            windows.append(lit)
        towers.append((v3(x, hgt / 2, z), axes, half, windows))
    return towers


TOWERS = make_towers()


# --- the camera ---------------------------------------------------------------------

class Cam:
    def __init__(self, w, h, pos, pitch, yaw, f):
        self.w, self.h, self.pos, self.f = w, h, pos, f
        p, y = math.radians(pitch), math.radians(yaw)
        self.fwd = v3(math.sin(y) * math.cos(p), math.sin(p), math.cos(y) * math.cos(p))
        self.right = norm(np.cross(v3(0, 1, 0), self.fwd))
        self.up = np.cross(self.fwd, self.right)

    def depth(self, p):
        return float(np.dot(p - self.pos, self.fwd))

    def project(self, p):
        d = p - self.pos
        z = float(np.dot(d, self.fwd))
        zc = max(z, 0.05)
        return self.w / 2 + self.f * float(np.dot(d, self.right)) / zc, self.h / 2 - self.f * float(np.dot(d, self.up)) / zc, z

    def project_all(self, pts):
        d = np.asarray(pts, np.float64) - self.pos
        z = d @ self.fwd
        zc = np.maximum(z, 0.05)
        return self.w / 2 + self.f * (d @ self.right) / zc, self.h / 2 - self.f * (d @ self.up) / zc, z

    def rays(self):
        xs = (np.arange(self.w, dtype=np.float32) - self.w / 2) / self.f
        ys = (self.h / 2 - np.arange(self.h, dtype=np.float32)) / self.f
        d = (self.fwd.astype(np.float32)[None, None, :] + xs[None, :, None] * self.right.astype(np.float32)[None, None, :]
             + ys[:, None, None] * self.up.astype(np.float32)[None, None, :])
        return d / np.linalg.norm(d, axis=2, keepdims=True)


def camera(fmt, tau):
    (w, h), f0, (p0, p1, p2, p3), push = FORMATS[fmt]
    pitch = (p0 + (p1 - p0) * smooth(0, T_LAUNCH, tau) + (p2 - p1) * smooth(T_LAUNCH, T_HIT, tau)
             + (p3 - p2) * smooth(T_HIT, 11.5, tau))
    yaw = -3 - 4 * smooth(3.0, T_HIT, tau) + 2 * smooth(T_HIT + 0.3, 11.5, tau)
    zoom = (1 + 0.06 * smooth(0, T_LAUNCH, tau) + push * smooth(5.0, T_HIT + 0.1, tau)
            - (push - 0.02) * smooth(T_HIT + 0.6, 9.0, tau))
    # The launch and the hit shake the camera; otherwise it breathes a little, held by hand.
    for t0, amp, decay in ((T_LAUNCH, 0.35, 0.35), (T_HIT, 0.6, 0.6)):
        if tau > t0:
            a = amp * math.exp(-(tau - t0) / decay)
            pitch += a * math.sin((tau - t0) * 55)
            yaw += a * math.sin((tau - t0) * 43 + 1.3)
    pitch += 0.12 * math.sin(tau * 0.9)
    yaw += 0.1 * math.sin(tau * 0.7 + 2)
    return Cam(w, h, CAM0 + v3(0, 0, 0.25 * tau), pitch, yaw, f0 * zoom)


def timeline():
    """Seconds of film and, for each frame, the scene time: the hit plays in slow motion."""
    n = int(round((SCENE + END) * FPS))
    r = np.arange(n) / FPS
    rc = T_HIT
    for _ in range(40):
        speed = 1 - 0.8 * np.exp(-((r - rc) / 0.85) ** 4)
        tau = np.concatenate([[0.0], np.cumsum(speed[:-1]) / FPS])
        rc += T_HIT + 0.08 - np.interp(rc, r, tau)
    return r, tau, speed


# --- the world: sky, clouds, city and roof, traced per pixel -----------------------------

_TEX = {}
SKY_E = [-1, 0, 2.5, 8, 18, 35, 90]
SKY_C = np.array([(150, 50, 40), (215, 78, 48), (160, 50, 44), (74, 28, 50), (30, 26, 60), (14, 18, 42), (6, 8, 20)], np.float32)


def city_map(size, seed):
    """The city from above, 3 m to a texel, drawn like the game's map: dark blocks and glowing streets."""
    rng = random.Random(seed)
    img = Image.new("RGB", (size, size), (9, 11, 22))
    d = ImageDraw.Draw(img)
    for _ in range(size * size // 300):  # roofs of slightly different shades
        x, y = rng.randrange(size), rng.randrange(size)
        s = rng.randint(3, 9)
        g = rng.randint(10, 22)
        d.rectangle([x, y, x + s, y + s], fill=(g, g + 2, g + 12))
    for vertical in (True, False):
        pos = 0
        while pos < size:
            pos += rng.randint(18, 34)
            avenue = rng.random() < 0.2
            d.line([(pos, 0), (pos, size)] if vertical else [(0, pos), (size, pos)],
                   fill=(255, 196, 84) if avenue else (170, 118, 50), width=3 if avenue else 1)
    for _ in range(size * size // 70):  # windows
        x, y = rng.randrange(size), rng.randrange(size)
        a = rng.uniform(0.3, 0.9)
        d.point((x, y), fill=(int(255 * a), int(205 * a), int(140 * a)))
    for _ in range(40):  # fires
        x, y, r = rng.randrange(size), rng.randrange(size), rng.uniform(3, 9)
        d.ellipse([x - r, y - r, x + r, y + r], fill=(255, 120, 40))
    return [np.asarray(img.filter(ImageFilter.GaussianBlur(s))) for s in (0.6, 2.0, 5.0)]


def puff_sprite(size=256):
    yy, xx = np.mgrid[0:size, 0:size].astype(np.float32)
    r = np.hypot(xx - size / 2, yy - size / 2) / (size / 2)
    n = fbm(size, 48, 4, 17)
    a = np.clip(1 - r, 0, 1) ** 1.4 * (0.55 + 0.45 * n) * 1.5
    return Image.fromarray((np.clip(a, 0, 1) * 255).astype(np.uint8), "L")


def textures():
    if not _TEX:
        _TEX["clouds"] = fbm(1024, 260, 4, 4)
        _TEX["city"] = city_map(2048, 12)
        _TEX["puff"] = puff_sprite()
        rng = np.random.default_rng(3)
        stars = rng.normal(size=(500, 3))
        stars[:, 1] = np.abs(stars[:, 1]) + 0.25
        _TEX["stars"] = (stars / np.linalg.norm(stars, axis=1, keepdims=True), rng.uniform(40, 170, 500), rng.uniform(0, 6.3, 500))
    return _TEX


def bilinear(tex, u, v):
    n = tex.shape[0]
    u0, v0 = np.floor(u), np.floor(v)
    fu, fv = (u - u0)[:, None], (v - v0)[:, None]
    i0, i1, j0, j1 = reflect(u0, n), reflect(u0 + 1, n), reflect(v0, n), reflect(v0 + 1, n)
    return (tex[j0, i0] * (1 - fu) * (1 - fv) + tex[j0, i1] * fu * (1 - fv)
            + tex[j1, i0] * (1 - fu) * fv + tex[j1, i1] * fu * fv)


def backdrop(cam, tau, fl, la):
    T = textures()
    d = cam.rays().reshape(-1, 3)
    dx, dy, dz = d[:, 0], d[:, 1], d[:, 2]
    elev = np.degrees(np.arcsin(np.clip(dy, -1, 1)))
    col = np.empty(d.shape, np.float32)
    for i in range(3):
        col[:, i] = np.interp(elev, SKY_E, SKY_C[:, i])
    az = np.degrees(np.arctan2(dx, dz))
    col += (np.exp(-((az + 14) / 32) ** 2) * np.exp(-np.abs(elev) / 5))[:, None] * np.array([80, 26, 10], np.float32)
    hd = norm(H - cam.pos).astype(np.float32)
    c = d @ hd
    col += (fl * np.exp(-2 * (1 - c) / 0.5 ** 2))[:, None] * np.array([70, 48, 36], np.float32)

    # The cloud ceiling, lit from below by the city and by the blast.
    cloud = np.zeros(len(d), np.float32)
    up = np.nonzero(dy > 0.01)[0]
    t = (CLOUD_Y - cam.pos[1]) / dy[up]
    n = T["clouds"][reflect((cam.pos[2] + t * dz[up]) / 3200 * 1024, 1024), reflect((cam.pos[0] + t * dx[up]) / 3200 * 1024, 1024)]
    dens = np.clip((n - 0.45) / 0.16, 0, 1) * np.exp(-t / 9000)
    lit = np.exp(-elev[up] / 14)[:, None]
    ccol = np.array([16, 18, 34], np.float32) + lit * np.array([150, 58, 48], np.float32)
    ccol += (fl * np.exp(-2 * (1 - c[up]) / 0.26 ** 2))[:, None] * np.array([255, 165, 90], np.float32)
    edge = (1 - 0.4 * np.clip((n - 0.58) / 0.18, 0, 1))[:, None]
    a = (dens * 0.92)[:, None]
    col[up] = col[up] * (1 - a) + ccol * edge * a
    cloud[up] = dens

    # Stars where the sky is clear.
    sd, sb, sp = T["stars"]
    z = sd @ cam.fwd
    sx = cam.w / 2 + cam.f * (sd @ cam.right) / np.maximum(z, 1e-3)
    sy = cam.h / 2 - cam.f * (sd @ cam.up) / np.maximum(z, 1e-3)
    ok = (z > 0.05) & (sx >= 0) & (sx < cam.w - 1) & (sy >= 0) & (sy < cam.h - 1)
    idx = sy[ok].astype(np.int64) * cam.w + sx[ok].astype(np.int64)
    b = sb[ok] * (0.75 + 0.25 * np.sin(tau * 3 + sp[ok])) * (1 - cloud[idx])
    np.add.at(col, idx, b[:, None] * np.array([0.85, 0.9, 1.0], np.float32))

    # Below the horizon: the lower roof in front, the city beyond it.
    down = np.nonzero(dy < -1e-4)[0]
    dd = -dy[down]
    tr = (cam.pos[1] - ROOF_Y) / dd
    rx, rz = cam.pos[0] + tr * dx[down], cam.pos[2] + tr * dz[down]
    on = (rz < ROOF_Z) & (np.abs(rx) < 90)
    g, gd = down[~on], dd[~on]
    tg = cam.pos[1] / gd
    X, Z = cam.pos[0] + tg * dx[g], cam.pos[2] + tg * dz[g]
    ca, sa = math.cos(math.radians(28)), math.sin(math.radians(28))
    u, v = (X * ca - Z * sa) / 3, (X * sa + Z * ca) / 3
    # Texels covered by a pixel picks how blurred a copy of the map to read: no shimmer far away.
    lvl = np.clip(np.log2(np.maximum(tg / (cam.f * gd) / 3, 1e-3) / 1.2), 0, 2)[:, None]
    L0, L1, L2 = T["city"]
    w1, w2 = np.clip(lvl, 0, 1), np.clip(lvl - 1, 0, 1)
    lights = (bilinear(L0, u, v) * (1 - w1) + bilinear(L1, u, v) * w1) * (1 - w2) + bilinear(L2, u, v) * w2
    hz = (1 - np.exp(-tg / 5000))[:, None]
    haze = np.array([150, 60, 42], np.float32) + np.exp(-((az[g] + 14) / 32) ** 2)[:, None] * np.array([70, 26, 8], np.float32)
    col[g] = lights * 1.5 * (1 - 0.85 * hz) + haze * hz
    r, X, Z = down[on], rx[on], rz[on]
    roof = np.tile(np.array([15, 16, 24], np.float32), (len(r), 1))
    roof *= (0.8 + 0.4 * T["clouds"][reflect(Z * 6, 1024), reflect(X * 6, 1024)])[:, None]
    roof += np.exp(-(ROOF_Z - Z) / 9)[:, None] * np.array([40, 20, 15], np.float32)
    dl = (X - LAUNCHER[0]) ** 2 + (Z - LAUNCHER[2]) ** 2
    roof += (la * 0.6 * np.exp(-dl / 10 ** 2))[:, None] * np.array([80, 120, 255], np.float32)
    roof += fl * np.array([36, 26, 20], np.float32)
    roof[Z > ROOF_Z - 0.45] = (96, 50, 38)  # the parapet, lit by the city below
    col[r] = roof
    return col.reshape(cam.h, cam.w, 3)


def beams(img, cam, tau, sc):
    """Searchlights sweeping up from the city."""
    lay = Image.new("L", img.size, 0)
    for base, phase in ((SITES[0], 0.0), (SITES[1], 2.1), (v3(150, 0, 900), 4.0)):
        dirn = norm(v3(0.5 * math.sin(0.33 * tau + phase), 1.0, 0.3 + 0.25 * math.cos(0.27 * tau + phase)))
        one = Image.new("L", img.size, 0)
        d = ImageDraw.Draw(one)
        steps = 14
        for i in range(steps):
            a0, a1 = i / steps, (i + 1) / steps
            p0, p1 = base + dirn * 2600 * a0, base + dirn * 2600 * a1
            x0, y0, z0 = cam.project(p0)
            x1, y1, z1 = cam.project(p1)
            if z0 < 5 or z1 < 5:
                continue
            w0, w1 = cam.f * (2 + 68 * a0) / z0, cam.f * (2 + 68 * a1) / z1
            L = math.hypot(x1 - x0, y1 - y0) or 1
            nx, ny = -(y1 - y0) / L, (x1 - x0) / L
            d.polygon([(x0 + nx * w0, y0 + ny * w0), (x1 + nx * w1, y1 + ny * w1),
                       (x1 - nx * w1, y1 - ny * w1), (x0 - nx * w0, y0 - ny * w0)], fill=int(255 * (1 - a0) ** 1.3))
        lay = ImageChops.lighter(lay, one)
    lay = lay.filter(ImageFilter.GaussianBlur(6 * sc))
    beam = Image.merge("RGB", [lay.point(lambda v, k=k: int(v * k)) for k in (0.2, 0.28, 0.48)])
    return ImageChops.screen(img, beam)


# --- objects ---------------------------------------------------------------------

L_CITY = norm(v3(-0.1, -0.75, 0.65))  # towards the burning city: below and ahead


def lit(base, n, c, fl, la):
    col = np.array(base, np.float64) * 0.6
    col += np.array([120, 56, 36]) * max(0.0, float(n @ L_CITY)) * 0.55
    col += np.array([36, 46, 84]) * max(0.0, float(n[1])) * 0.5
    if la > 0.01:
        dv = MOUTH - c
        dist = float(np.linalg.norm(dv))
        col += np.array([110, 160, 255]) * la * max(0.0, float(n @ dv) / dist) * min(1.0, (14 / dist) ** 2)
    if fl > 0.01:
        col += np.array([255, 170, 90]) * fl * 0.5 * max(0.0, float(n @ norm(H - c)))
    return tuple(int(x) for x in np.clip(col, 0, 255))


def box(c, axes, half):
    """A box's six faces as (corners, outward normal)."""
    ex, ey, ez = (a * s for a, s in zip(axes, half))
    out = []
    for n, u, v in ((ex, ey, ez), (-ex, ez, ey), (ey, ez, ex), (-ey, ex, ez), (ez, ex, ey), (-ez, ey, ex)):
        f = c + n
        out.append(([f - u - v, f + u - v, f + u + v, f - u + v], norm(n)))
    return out


def solid(cam, items, corners, colour, masks=None):
    xs, ys, zs = cam.project_all(corners)
    if (zs < 0.3).any():
        return None
    poly = list(zip(xs.tolist(), ys.tolist()))
    items.append((float(zs.mean()), "poly", (poly, colour)))
    if masks is not None:
        masks.append(poly)
    return poly


def visible_faces(cam, faces):
    for corners, n in faces:
        c = np.mean(corners, axis=0)
        if float(n @ (cam.pos - c)) > 0:
            yield corners, n, c


def polyline(d, cam, pts, colours, width_m, cap, floor=1.5):
    xs, ys, zs = cam.project_all(pts)
    for i in range(len(xs) - 1):
        if zs[i] < 1 or zs[i + 1] < 1:
            continue
        w = min(cap, max(floor, cam.f * width_m / zs[i]))
        d.line([(xs[i], ys[i]), (xs[i + 1], ys[i + 1])], fill=colours[i], width=max(1, int(round(w))))
        if w > 3:
            d.ellipse([xs[i] - w / 2, ys[i] - w / 2, xs[i] + w / 2, ys[i] + w / 2], fill=colours[i])


def dot(d, x, y, r, colour):
    d.ellipse([x - r, y - r, x + r, y + r], fill=colour)


def scaled(c, k):
    return tuple(int(max(0, min(255, v * k))) for v in c)


def ring(d, cam, centre, radius, colour, width):
    a = np.linspace(0, math.tau, 72)
    pts = centre + np.stack([np.cos(a) * radius, np.zeros_like(a), np.sin(a) * radius], axis=1)
    xs, ys, zs = cam.project_all(pts)
    for i in range(len(a) - 1):
        if zs[i] > 1 and zs[i + 1] > 1:
            d.line([(xs[i], ys[i]), (xs[i + 1], ys[i + 1])], fill=colour, width=width)


def towers(cam, items, de, fl):
    for c, axes, half, windows in TOWERS:
        if cam.depth(c) < 10:
            continue
        faces = box(c, axes, half)
        for k, (corners, n) in enumerate(faces):
            fc = np.mean(corners, axis=0)
            if k == 3 or float(n @ (cam.pos - fc)) <= 0:
                continue
            solid(cam, items, corners, lit((20, 24, 44), n, fc, fl, 0))
            if k == 2:
                continue
            # Sides 0, 1 face along x; 4, 5 along z (see box()).
            side = {0: 0, 1: 1, 4: 2, 5: 3}[k]
            across = axes[2] if side < 2 else axes[0]
            for u, v, b in windows[side]:
                p = fc + across * u + axes[1] * v
                x, y, z = cam.project(p)
                if z < 5 or not (-5 < x < cam.w + 5 and -5 < y < cam.h + 5):
                    continue
                s = max(0.7, cam.f * 0.7 / z)
                de.rectangle([x - s, y - s * 1.4, x + s, y + s * 1.4], fill=scaled((255, 190, 110), b))


def drones(cam, tau, items, de, fl):
    faces, _ = drone_mesh()
    for k in range(len(DRONES)):
        if ("drone", k) in KILLED and tau >= KILLED[("drone", k)]:
            continue
        if DRONES[k][0] + DRONE_SPEED * tau > SWARM_LEN - 12:
            continue
        p = drone_at(k, tau)
        x, y, z = cam.project(p)
        if z < 3:
            continue
        dist = float(np.linalg.norm(p - cam.pos))
        scale = 1 + 3.0 * min(1.0, dist / 300)
        size = cam.f * 3.5 * scale / z
        tail = cam.project(p - SWARM_DIR * 1.6 * scale)
        dot(de, tail[0], tail[1], min(8.0, max(1.6, size * 0.09)), (255, 120, 70))
        if size < 6:
            dot(de, x, y, max(1.4, size * 0.4), RED)
            continue
        roll = DRONES[k][3]
        polys = []
        for f in faces:
            world = [place(q * scale, p, SWARM_DIR, roll) for q in f]
            n = np.cross(world[1] - world[0], world[2] - world[0])
            if np.linalg.norm(n) < 1e-9:
                continue
            n = norm(n)
            fc = np.mean(world, axis=0)
            if float(n @ (cam.pos - fc)) < 0:
                n = -n
            xs, ys, zs = cam.project_all(world)
            polys.append((float(zs.mean()), list(zip(xs.tolist(), ys.tolist())), lit((150, 22, 26), n, fc, fl, 0)))
        polys.sort(key=lambda t: -t[0])
        items.append((z, "polys", [(pl, c) for _, pl, c in polys]))
        w = max(1, int(size / 45))
        for _, pl, _ in polys:
            de.line(pl + [pl[0]], fill=RED, width=w)


CRUISE_FACES = [f for f, _ in box(v3(0, 0, 0), (v3(1, 0, 0), v3(0, 1, 0), v3(0, 0, 1)), (0.25, 0.25, 2.9))] + [
    [v3(0, 0, 0.8), v3(1.4, 0, -0.6), v3(-1.4, 0, -0.6)],
    [v3(0, 0, -2.2), v3(0, 0.8, -2.9), v3(0, 0.05, -2.9)],
]


def cruises(cam, tau, items, de, fl):
    fwd = norm(CRUISE_V)
    for j in range(len(CRUISE)):
        if ("cruise", j) in KILLED and tau >= KILLED[("cruise", j)]:
            continue
        p = cruise_at(j, tau)
        x, y, z = cam.project(p)
        if z < 10:
            continue
        # A thin trail of hot exhaust behind it.
        pts = [p - fwd * 300 * a for a in np.linspace(0, 1, 16)]
        polyline(de, cam, pts, [scaled((255, 110, 70), (1 - a) ** 1.5) for a in np.linspace(0, 1, 16)], 1.2, 3)
        polys = []
        for f in CRUISE_FACES:
            world = [place(q * 4, p, fwd, 0.0) for q in f]
            n = norm(np.cross(world[1] - world[0], world[2] - world[0]))
            fc = np.mean(world, axis=0)
            if float(n @ (cam.pos - fc)) < 0:
                n = -n
            xs, ys, zs = cam.project_all(world)
            polys.append((float(zs.mean()), list(zip(xs.tolist(), ys.tolist())), lit((150, 22, 26), n, fc, fl, 0)))
        polys.sort(key=lambda t: -t[0])
        items.append((z, "polys", [(pl, c) for _, pl, c in polys]))
        for _, pl, _ in polys:
            de.line(pl + [pl[0]], fill=RED, width=1)
        tail = cam.project(p - fwd * 12)
        dot(de, tail[0], tail[1], max(2.0, cam.f * 1.2 / z), (255, 170, 110))


def puffs(cam, tau, items, fl, la):
    for birth, pos, vel, rmax, life, kind in PUFFS:
        age = tau - birth
        if age < 0:
            continue
        p = pos + vel * 1.2 * (1 - math.exp(-age / 1.2)) + v3(1.5 * age, 1.5 * age, 0)
        x, y, z = cam.project(p)
        if z < 1:
            continue
        r = rmax * (0.35 + 0.65 * (1 - math.exp(-age / 0.7))) * (1 + 0.04 * age)
        rp = cam.f * r / z
        alpha = 0.8 * min(1.0, age / 0.06) * math.exp(-age / life)
        if kind == "launch":
            near = min(1.0, (25 / max(1.0, float(np.linalg.norm(p - MOUTH)))) ** 1.5)
            colour = np.array([70, 80, 104]) + np.array([100, 140, 230]) * la * near + np.array([30, 18, 12])
        else:
            colour = np.array([36, 28, 30]) + np.array([210, 100, 45]) * math.exp(-age / 0.45) + np.array([200, 130, 70]) * fl * 0.1
        items.append((z, "puff", (x, y, rp, tuple(int(c) for c in np.clip(colour, 0, 255)), alpha)))


def blit(img, sprite, x, y, r, colour, alpha):
    size = int(2 * r)
    if size < 3 or alpha < 0.01:
        return
    x0, y0 = int(x - r), int(y - r)
    w, h = img.size
    l, t, rr, bb = max(0, -x0), max(0, -y0), min(size, w - x0), min(size, h - y0)
    if rr <= l or bb <= t:
        return
    a = sprite.resize((size, size), Image.BILINEAR).crop((l, t, rr, bb)).point(lambda v: int(v * alpha))
    tile = Image.new("RGBA", a.size, colour + (0,))
    tile.putalpha(a)
    img.alpha_composite(tile, (x0 + l, y0 + t))


def launcher(cam, tau, items, masks, dn, fl, la):
    """The launcher on the lower roof: a truck carrying a four-tube pod with glowing blue edges."""
    yaw = math.radians(-10)
    fx, fz = v3(math.cos(yaw), 0, -math.sin(yaw)), v3(math.sin(yaw), 0, math.cos(yaw))
    flat = (fx, v3(0, 1, 0), fz)
    side = norm(np.cross(v3(0, 1, 0), POD))
    lift = np.cross(POD, side)
    pod = (side, lift, POD)
    parts = [(LAUNCHER + v3(0, 1.3, 0), flat, (1.3, 0.55, 3.4), (62, 72, 98), False),          # the bed
             (LAUNCHER + v3(0, 1.75, 0) + fz * 3.9, flat, (1.25, 1.0, 0.9), (70, 80, 108), False),  # the cab
             (PIVOT + POD * 3.2, pod, (1.05, 1.05, 3.2), (72, 86, 118), True),                 # the pod
             (PIVOT + POD * 1.4 - lift * 0.9, pod, (0.3, 0.45, 1.1), (40, 46, 62), False)]     # its strut
    for sx in (-1, 1):
        for sz in (-2.4, 0.2, 3.9):
            parts.append((LAUNCHER + v3(0, 0.5, 0) + fx * sx * 1.15 + fz * sz, flat, (0.25, 0.5, 0.5), (14, 15, 20), False))
    edges = []
    for c, axes, half, base, glowing in parts:
        for corners, n, fc in visible_faces(cam, box(c, axes, half)):
            poly = solid(cam, items, corners, lit(base, n, fc, fl, la), masks)
            if poly and glowing:
                edges.append(poly)
    if dn is None:
        return
    if float(POD @ (cam.pos - MOUTH)) <= 0:
        for poly in edges:
            dn.line(poly + [poly[0]], fill=scaled(BLUE, 0.6), width=2)
        return
    # The pod's mouth: four tubes, the fired one glowing.
    hot = min(1.0, max(0.0, (tau - T_LAUNCH) * 30)) * (0.25 + 0.75 * math.exp(-max(0.0, tau - T_LAUNCH) / 0.5))
    for i, (a, b) in enumerate(((-1, -1), (1, -1), (-1, 1), (1, 1))):
        c = MOUTH + side * a * 0.55 + lift * b * 0.55
        pts = [c + side * math.cos(t) * 0.42 + lift * math.sin(t) * 0.42 for t in np.linspace(0, math.tau, 17)]
        xs, ys, zs = cam.project_all(pts)
        if (zs < 0.3).any():
            continue
        poly = list(zip(xs.tolist(), ys.tolist()))
        dn.polygon(poly, fill=scaled((190, 225, 255), hot) if i == 0 else (6, 8, 14), outline=scaled(BLUE, 0.9))
    for poly in edges:
        dn.line(poly + [poly[0]], fill=scaled(BLUE, 0.6), width=2)


def props(cam, tau, items, masks, dn, fl, la):
    """Boxes on the roof and a mast with a blinking red light: the scale of the shot."""
    for c, half in ((v3(-13, ROOF_Y + 1.0, 24), (1.6, 1.0, 1.2)), (v3(-22, ROOF_Y + 1.3, 36), (2.2, 1.3, 1.6)),
                    (v3(19, ROOF_Y + 0.8, 33), (1.4, 0.8, 2.4))):
        for corners, n, fc in visible_faces(cam, box(c, (v3(1, 0, 0), v3(0, 1, 0), v3(0, 0, 1)), half)):
            solid(cam, items, corners, lit((22, 24, 34), n, fc, fl, la), masks)


def explosion(cam, de, t0, pos, size, big, tau, seed, sc):
    a = tau - t0
    if a < 0 or a > 4:
        return
    x, y, z = cam.project(pos)
    if z < 5:
        return
    px = cam.f / z
    rng = np.random.default_rng(seed)
    if big and a > 0:
        # The shock wave racing out: a faint, broken ring.
        R = size * 11 * (1 - math.exp(-a / 0.45)) * px
        al = 0.55 * math.exp(-a / 0.45) * (1 - math.exp(-a / 0.04))
        segs = 48
        k = rng.uniform(0.3, 1.0, segs)
        for i in range(segs):
            a0, a1 = 360 * i / segs, 360 * (i + 1) / segs
            de.arc([x - R, y - R, x + R, y + R], a0, a1, fill=scaled((255, 225, 190), al * k[i]), width=max(1, int(3 * sc)))
    # Sparks and burning debris: flung out, slowed by the air, falling.
    count = 70 if big else 18
    dirs = rng.normal(size=(count, 3))
    dirs /= np.linalg.norm(dirs, axis=1, keepdims=True)
    speed = rng.uniform(0.3, 1.0, count) * size * (5 if big else 4)
    life = rng.uniform(1.0, 3.2, count)
    blue = rng.random(count) < 0.2
    for i in range(count):
        if a > life[i]:
            continue
        def at(t):
            return pos + dirs[i] * speed[i] * 0.8 * (1 - math.exp(-t / 0.8)) + v3(0, -6 * t * t, 0)
        p0, p1 = at(max(0.0, a - 0.06)), at(a)
        x0, y0, z0 = cam.project(p0)
        x1, y1, z1 = cam.project(p1)
        if z0 < 1 or z1 < 1:
            continue
        k = (1 - a / life[i]) ** 1.5
        de.line([(x0, y0), (x1, y1)], fill=scaled((150, 200, 255) if blue[i] else (255, 190, 100), k), width=max(1, int(2 * sc)))
    # The fireball.
    ib = math.exp(-a / 0.55) * (1 - math.exp(-a / 0.03))
    rb = size * (0.35 + 0.75 * (1 - math.exp(-a / 0.22))) * px
    offs = rng.normal(size=(7, 2)) * 0.45
    for k, colour in ((1.0, (190, 50, 20)), (0.75, (255, 120, 40)), (0.45, (255, 210, 130))):
        for ox, oy in offs:
            r = rb * 0.62 * k
            dot(de, x + ox * rb * k, y + oy * rb * k, r, scaled(colour, ib))
    # The flash.
    fl = math.exp(-a / 0.12)
    if fl > 0.01:
        rf = size * 0.55 * (1 + 3 * a) * px
        dot(de, x, y, rf * 2.2, scaled((255, 180, 90), fl * 0.6))
        dot(de, x, y, rf, scaled((255, 250, 240), fl))


def streak(img, x, y, k, colour, sc):
    """An anamorphic lens streak through a bright light."""
    if k < 0.02 or not (-50 < y < img.height + 50):
        return img
    w, bh = img.width, int(12 * sc)
    gx = np.arange(w, dtype=np.float32)
    line = np.exp(-((gx - x) / (w * 0.35)) ** 2)
    prof = np.exp(-(np.arange(-bh, bh + 1, dtype=np.float32) / (2.2 * sc)) ** 2)
    band = (prof[:, None, None] * line[None, :, None] * np.array(colour, np.float32) * k).clip(0, 255).astype(np.uint8)
    lay = Image.new("RGB", img.size)
    lay.paste(Image.fromarray(band), (0, int(y) - bh))
    return ImageChops.screen(img, lay)


# --- the frame ----------------------------------------------------------------------

_VIG = {}


def grade(img):
    w, h = img.size
    sc = min(w, h) / 1080
    arr = np.asarray(img, np.float32) / 255
    lum = arr @ np.array([0.3, 0.59, 0.11], np.float32)
    hi = Image.fromarray((np.clip(lum - 0.5, 0, 1) / 0.5 * 255).astype(np.uint8))
    for r, s in ((22 * sc, 0.35), (80 * sc, 0.3)):
        b = np.asarray(hi.filter(ImageFilter.GaussianBlur(r)), np.float32)[:, :, None] / 255
        arr = 1 - (1 - arr) * (1 - b * s * np.array([1.0, 0.75, 0.6], np.float32))
    lum = (arr @ np.array([0.3, 0.59, 0.11], np.float32))[:, :, None]
    arr += (1 - lum) ** 3 * np.array([-0.01, 0.01, 0.04], np.float32)
    arr = 0.5 + (arr - 0.5) * 1.08
    if (w, h) not in _VIG:
        yy, xx = np.mgrid[0:h, 0:w].astype(np.float32)
        v = 1 - 0.5 * (((xx - w / 2) / (w * 0.8)) ** 2 + ((yy - h * 0.5) / (h * 0.8)) ** 2)
        _VIG[(w, h)] = np.clip(v, 0.3, 1)[:, :, None]
    out = np.clip(arr * _VIG[(w, h)], 0, 1)
    s = max(1, int(2 * sc))
    out[:, s:, 0] = out[:, :-s, 0]
    out[:, :-s, 2] = out[:, s:, 2]
    return Image.fromarray((out * 255).astype(np.uint8))


def scene(fmt, tau):
    cam = camera(fmt, tau)
    w, h = cam.w, cam.h
    sc = min(w, h) / 1080
    fl, la = flash_level(tau), launch_level(tau)
    img = Image.fromarray(np.clip(backdrop(cam, tau, fl, la), 0, 255).astype(np.uint8))
    img = beams(img, cam, tau, sc).convert("RGBA")
    ef = Image.new("RGB", (w, h))
    de = ImageDraw.Draw(ef)

    # Solid things, painted back to front.
    items, masks = [], []
    towers(cam, items, de, fl)
    drones(cam, tau, items, de, fl)
    cruises(cam, tau, items, de, fl)
    puffs(cam, tau, items, fl, la)
    launcher(cam, tau, items, masks, None, fl, la)
    props(cam, tau, items, masks, None, fl, la)
    di = ImageDraw.Draw(img)
    sprite = textures()["puff"]
    near = []
    for depth, kind, data in sorted(items, key=lambda t: -t[0]):
        if kind == "poly":
            di.polygon(data[0], fill=data[1] + (255,))
        elif kind == "polys":
            for pl, c in data:
                di.polygon(pl, fill=c + (255,))
        else:
            blit(img, sprite, *data[:3], data[3], data[4])

    # Light: air defence rings, the threats, the shots, the blasts. The launcher and the
    # props were drawn into this layer as they were placed; mask what they hide, then add
    # what is in front of them.
    for i, s in enumerate(SITES):
        ring(de, cam, s, 260, scaled(BLUE, 0.7), max(1, int(2 * sc)))
        k = (tau * 0.5 + i * 0.33) % 1.0
        ring(de, cam, s, 260 * k, scaled(BLUE, 0.6 * (1 - k)), max(1, int(2 * sc)))
        x, y, z = cam.project(s + v3(0, 3, 0))
        if z > 1:
            dot(de, x, y, max(2.0, 4 * sc), (180, 220, 255))
    if T_SEEN < tau < T_HIT + 3:
        ts = np.linspace(max(T_SEEN, tau - 2.6), min(tau, T_HIT), 50)
        pts = H + B_DIR * B_SPEED * (ts - T_HIT)[:, None]
        fade = 1.0 if tau < T_HIT else math.exp(-(tau - T_HIT) / 0.7)
        cols = []
        for t in ts:
            age = tau - t
            mix = min(1.0, age / 0.6)
            c = np.array([255, 170, 80]) * (1 - mix) + np.array([230, 45, 35]) * mix
            cols.append(scaled(c, math.exp(-age / 1.3) * fade * smooth(T_SEEN, T_SEEN + 0.4, tau)))
        polyline(de, cam, pts, cols, 10, 14 * sc, 2.5)
        if tau < T_HIT:
            x, y, z = cam.project(ballistic_at(tau))
            k = smooth(T_SEEN, T_SEEN + 0.4, tau)
            if z > 1:
                dot(de, x, y, max(4 * sc, cam.f * 9 / z), scaled((255, 70, 50), k))
                dot(de, x, y, max(2.5 * sc, cam.f * 4 / z), scaled((255, 235, 215), k))
    for site, t0, t1, kind, i in SHOTS:
        if tau < t0:
            continue
        a, c, b = shot_path(site, kind, i, t1)
        s = flight(tau, t0, t1)
        ss = np.linspace(0, s, 40)
        fade = 1.0 if tau < t1 else math.exp(-(tau - t1) / 1.2)
        cols = [scaled(BLUE, (0.25 + 0.75 * (k / 39) ** 1.5) * fade) for k in range(40)]
        polyline(de, cam, bez(a, c, b, ss), cols, 1.2, 4 * sc)
        if tau < t1:
            x, y, z = cam.project(bez(a, c, b, s))
            if z > 1:
                dot(de, x, y, max(2.5, 3.5 * sc), (230, 245, 255))
    for t0, pos, size, big, seed in EXPLOSIONS:
        explosion(cam, de, t0, pos, size, big, tau, seed, sc)
    for poly in masks:
        de.polygon(poly, fill=(0, 0, 0))
    launcher(cam, tau, [], None, de, fl, la)
    props(cam, tau, [], None, de, fl, la)
    ring(de, cam, LAUNCHER + v3(0, 0.05, 0), 7, scaled(BLUE, 0.7), max(1, int(3 * sc)))
    k = (tau * 0.6) % 1.0
    ring(de, cam, LAUNCHER + v3(0, 0.05, 0), 7 * k, scaled(BLUE, 0.6 * (1 - k)), max(1, int(2 * sc)))
    if tau >= T_LAUNCH:
        # The interceptor: a white-hot head on a long electric-blue trail.
        s = flight(tau, T_LAUNCH, T_HIT)
        n = 90
        fade = 1.0 if tau < T_HIT else math.exp(-(tau - T_HIT) / 1.5)
        cols = [scaled(np.array(BLUE) * (1 - (k / n) ** 4) + np.array([220, 240, 255]) * (k / n) ** 4,
                       (0.3 + 0.7 * (k / n) ** 1.2) * fade) for k in range(n)]
        polyline(de, cam, bez(MOUTH, CTRL, H, np.linspace(0, s, n)), cols, 1.8, 16 * sc, 2)
        if tau < T_HIT:
            x, y, z = cam.project(bez(MOUTH, CTRL, H, s))
            if z > 1:
                dot(de, x, y, max(4 * sc, min(30 * sc, cam.f * 1.5 / z)), (240, 250, 255))
        if la > 0.05:
            x, y, z = cam.project(MOUTH + POD * 1.5)
            if z > 1:
                for k, c in ((1.0, (40, 70, 160)), (0.55, (110, 170, 255)), (0.25, (235, 245, 255))):
                    dot(de, x, y, cam.f * 1.6 * k * min(1.0, la) / z, scaled(c, min(1.0, la)))

    img = img.convert("RGB")
    for r in (2 * sc, 7 * sc, 22 * sc):
        img = ImageChops.screen(img, ef.filter(ImageFilter.GaussianBlur(r)))
    img = ImageChops.screen(img, ef)
    x, y, z = cam.project(H)
    if z > 1:
        img = streak(img, x, y, min(1.0, flash_level(tau) * 0.8), (90, 150, 255), sc)
    x, y, z = cam.project(MOUTH)
    if z > 1:
        img = streak(img, x, y, min(0.6, la * 0.5), (90, 150, 255), sc)
    return grade(img)


def alert_layer(w, h):
    """The game's air-raid pill at the top of the frame."""
    out = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    pill(ImageDraw.Draw(out), w // 2, int(h * 0.07), "AIR RAID ALERT", (0xE0, 0x57, 0x4A), font(42, "Black"))
    return out


def title_layer(w, h):
    """The logo over a shadow at the bottom of the frame."""
    out = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    shade = np.zeros((h, w), np.float32)
    yy = np.linspace(0, 1, h, dtype=np.float32)[:, None]
    shade += np.clip((yy - 0.55) / 0.45, 0, 1) ** 1.3 * 0.85
    out.putalpha(Image.fromarray((np.broadcast_to(shade, (h, w)) * 255).astype(np.uint8)))
    lg = logo(int(w * 0.84) if h > w else int(w * 0.5))
    x = (w - lg.width) // 2 if h > w else int(w * 0.045)
    out.alpha_composite(lg, (x, h - lg.height - int(h * (0.1 if h > w else 0.09))))
    return out


def end_card(w, h):
    img = Image.new("RGBA", (w, h), PAGE + (255,))
    d = ImageDraw.Draw(img)
    lg = logo(900)
    top = (h - (lg.height + 60 + 78 + 80 + 54 + 40 + 40)) // 2
    img.alpha_composite(lg, ((w - lg.width) // 2, top))
    y = top + lg.height + 60
    pill(d, w // 2, y, "FREE ON ITCH.IO", GOOD, font(46, "Black"))
    d.text((w // 2, y + 78 + 80), "Play in your browser", font=font(54, "Bold"), fill=TEXT, anchor="mm")
    d.text((w // 2, y + 78 + 80 + 75), "tenchery.itch.io/strike-alert", font=font(40, "Medium"), fill=MUTED, anchor="mm")
    return img


_CARDS = {}


def frame(job):
    """One finished frame: the scene, the title over its last seconds, then the end card."""
    fmt, r, tau, seed = job
    (w, h) = FORMATS[fmt][0]
    if fmt not in _CARDS:
        _CARDS[fmt] = (alert_layer(w, h), title_layer(w, h), end_card(w, h))
    alert, title, card = _CARDS[fmt]
    if r < SCENE:
        img = scene(fmt, tau).convert("RGBA")
        for layer, a in ((alert, smooth(0.3, 0.6, r) * (1 - smooth(2.6, 3.0, r)) * (0.75 + 0.25 * math.cos(r * 9))),
                         (title, smooth(SCENE - 2.6, SCENE - 2.0, r))):
            if a > 0:
                t = layer.copy()
                t.putalpha(t.getchannel("A").point(lambda v: int(v * a)))
                img.alpha_composite(t)
        dark = smooth(SCENE - 0.3, SCENE, r)
    else:
        img = card.copy()
        dark = 1 - smooth(SCENE, SCENE + 0.35, r)
    if dark > 0:
        img = Image.blend(img, Image.new("RGBA", (w, h), PAGE + (255,)), dark)
    arr = np.asarray(img.convert("RGB"), np.float32)
    arr += np.random.default_rng(seed).normal(0, 2.2, (h, w))[:, :, None]
    return np.clip(arr, 0, 255).astype(np.uint8).tobytes()


# --- the sound ------------------------------------------------------------------------

def load(name):
    with wave.open(os.path.join(AUDIO, name)) as f:
        sr, ch = f.getframerate(), f.getnchannels()
        data = np.frombuffer(f.readframes(f.getnframes()), np.int16).astype(np.float32) / 32768
    if ch == 2:
        data = data.reshape(-1, 2).mean(axis=1)
    if sr != SR:
        data = np.interp(np.arange(0, len(data), sr / SR), np.arange(len(data)), data).astype(np.float32)
    return data


def soundtrack(r, tau, speed, path):
    total = SCENE + END
    mix = np.zeros(int(total * SR) + SR, np.float32)
    t = np.arange(len(mix)) / SR

    def at(scene_time):
        return float(np.interp(scene_time, tau, r))

    def put(sig, start, gain=1.0):
        i = int(start * SR)
        n = min(len(sig), len(mix) - i)
        mix[i:i + n] += sig[:n] * gain

    # Everything but the blast drops away while the hit plays in slow motion.
    slow = np.interp(t, r, speed)
    duck = 1 - 0.7 * (1 - slow) / 0.8
    scene_env = np.clip(t / 0.3, 0, 1) * np.clip((SCENE - t) / 2.0, 0, 1) * duck
    siren = load("alert_loop.wav")
    bed = np.zeros_like(mix)
    bed[:min(len(siren), len(bed))] = siren[:len(bed)] * 0.55
    hum = load("drone_loop.wav")
    hum = np.tile(hum, int(len(mix) / len(hum)) + 1)[:len(mix)]
    bed += hum * (0.12 + 0.18 * np.clip(t / SCENE, 0, 1))
    mix += bed * scene_env
    put(load("ballistic_warning.wav"), at(1.0), 0.45)
    put(load("sam_launch.wav"), at(T_LAUNCH), 1.0)
    for _, t0, t1, _, _ in SHOTS:
        put(load("launch.wav"), at(t0), 0.3)
        put(load("explosion_small_a.wav"), at(t1), 0.45)
    put(load("intercept.wav"), at(T_HIT), 0.8)
    boom = load("explosion_b.wav")
    boom = np.interp(np.arange(0, len(boom), 0.7), np.arange(len(boom)), boom).astype(np.float32)  # slowed: deeper
    put(boom, at(T_HIT), 1.0)
    clear = load("all_clear.wav")[:int(END * SR)]
    clear *= np.clip((END - np.arange(len(clear)) / SR) / 0.8, 0, 1)
    put(clear, SCENE - 0.1, 0.7)
    mix /= max(1.0, float(np.abs(mix).max()) / 0.95)
    with wave.open(path, "wb") as f:
        f.setnchannels(1)
        f.setsampwidth(2)
        f.setframerate(SR)
        f.writeframes((mix[:int(total * SR)] * 32767).astype(np.int16).tobytes())


# --- output -------------------------------------------------------------------------------

def encode(fmt, r, tau, wav, out):
    (w, h) = FORMATS[fmt][0]
    cmd = [imageio_ffmpeg.get_ffmpeg_exe(), "-hide_banner", "-loglevel", "error", "-y",
           "-f", "rawvideo", "-pix_fmt", "rgb24", "-s", "%dx%d" % (w, h), "-r", str(FPS), "-i", "-", "-i", wav,
           "-filter_complex", "[0:v]scale=out_color_matrix=bt709:out_range=tv,format=yuv420p[v];"
           "[1:a]loudnorm=I=-14:TP=-1.5:LRA=11,aresample=48000,aformat=channel_layouts=stereo[a]",
           "-map", "[v]", "-map", "[a]", "-c:v", "libx264", "-preset", "slow", "-crf", "17",
           "-colorspace", "bt709", "-color_primaries", "bt709", "-color_trc", "bt709", "-color_range", "tv",
           "-c:a", "aac", "-b:a", "192k", "-movflags", "+faststart", out]
    proc = subprocess.Popen(cmd, stdin=subprocess.PIPE)
    jobs = [(fmt, float(r[i]), float(tau[i]), i) for i in range(len(r))]
    with Pool() as pool:
        for i, data in enumerate(pool.imap(frame, jobs, chunksize=2)):
            proc.stdin.write(data)
            if i % 60 == 0:
                print("%s: frame %d of %d" % (fmt, i, len(jobs)), flush=True)
    proc.stdin.close()
    if proc.wait():
        raise SystemExit("ffmpeg failed")
    print("wrote", out)


def main():
    r, tau, speed = timeline()
    if sys.argv[1] == "--stills":
        out, fmt, times = sys.argv[2], sys.argv[3], [float(x) for x in sys.argv[4:]]
        os.makedirs(out, exist_ok=True)
        (w, h) = FORMATS[fmt][0]
        for x in times:
            i = min(len(r) - 1, int(round(x * FPS)))
            data = frame((fmt, float(r[i]), float(tau[i]), i))
            Image.frombytes("RGB", (w, h), data).save(os.path.join(out, "%s_%05.2f.png" % (fmt, x)))
            print("still at %.2f s (scene time %.2f)" % (x, tau[i]))
        return
    out = sys.argv[1]
    wav = os.path.join(tempfile.mkdtemp(), "sound.wav")
    soundtrack(r, tau, speed, wav)
    for fmt in sys.argv[2:] or list(FORMATS):
        encode(fmt, r, tau, wav, os.path.join(out, "strike-alert-intercept-%s.mp4" % fmt))


if __name__ == "__main__":
    main()
