"""A cover for Strike Alert: dawn over the front, seen from high up. A column of
attack drones comes in out of the sunrise, ballistic missiles fall, interceptors
climb to meet them, and the strikes that got through burn under tall smoke.

    python tools/itch_dawn.py itch [--preview]

Writes cover-dawn.png (630x500) and cover-dawn-1260.png (--preview: dawn-preview.png
at 1260x1000, quicker). World units are km: x east (straight ahead), y north (to
the left), z up, the camera over (0, 0) and the Earth's centre at (0, 0, -R). Not
to scale: the drones and the smoke are far bigger than life so they read on a
thumbnail.
"""
import math
import os
import sys

import numpy as np
from PIL import Image, ImageDraw

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
LOGO = os.path.join(ROOT, "itch", "logo-v2.png")

R = 6371.0
CAM_ALT = 20.0       # km
FOCAL = 0.8          # focal length over the frame width: about 64 degrees across
HORIZON_Y = 0.52     # where the horizon crosses the middle of the frame, of the height
SUN_X, SUN_UP = 0.45, -0.7   # the sun: across the frame, degrees above the horizon
SHADOW = 27.0        # km: above this the sun has already risen
LH, LA = 170.0, 380.0  # km: haze over the ground, in the air
BIG, OLD = (0.40, 0.585), (0.85, 0.565)   # where the strikes burn, in the frame
NEAR, FAR = (0.90, 0.17), (0.56, 0.475)     # the ends of the column of drones, in the frame
ALT_N, ALT_F = 26.0, 20.5                  # km: its height at each end
HEAD_N, HEAD_F = 212.0, 172.0              # degrees: its heading at each end (180 = straight at us)
SIZE, SHOT = 0.8, 5                        # drone half-length km, which one is hit
HIT, LAUNCH = (0.17, 0.14), (0.12, 0.645)  # the interception and the launcher under it
OTHER = (0.565, 0.235)                     # the warhead still falling

ZEN = np.array([0.016, 0.028, 0.068], np.float32)
HAZE = np.array([0.060, 0.088, 0.150], np.float32)
DUSK = np.array([0.075, 0.05, 0.085], np.float32)
DAWN = np.array([0.80, 0.33, 0.10], np.float32)
GOLD = np.array([1.10, 0.72, 0.34], np.float32)
WARM = np.array([0.30, 0.16, 0.08], np.float32)
TEAL = np.array([0.010, 0.030, 0.040], np.float32)
GROUND = np.array([0.016, 0.019, 0.024], np.float32)
SUNC = np.array([2.2, 1.2, 0.55], np.float32)
FIRE = np.array([1.0, 0.42, 0.12], np.float32)


# --- tools --------------------------------------------------------------------------------

def _box(a, k, axis):
    pad = [(0, 0)] * a.ndim
    pad[axis] = (k // 2 + 1, k // 2)
    c = np.cumsum(np.pad(a, pad, mode="edge"), axis=axis, dtype=np.float64)
    n = a.shape[axis]
    return ((np.take(c, range(k, n + k), axis=axis) - np.take(c, range(0, n), axis=axis)) / k).astype(np.float32)


def blur(a, sigma):
    """A Gaussian blur of a float array (2D, or 2D with channels), as three box blurs each way."""
    k = max(1, int(round(math.sqrt(4 * sigma * sigma + 1)))) | 1
    out = a.astype(np.float32)
    if k <= 1:
        return out
    for axis in (0, 1):
        for _ in range(3):
            out = _box(out, k, axis)
    return out


def fbm(h, w, cell, octaves, seed, gain=0.55):
    """Fractal noise over an h x w grid, features about `cell` pixels, normalised to mean 0, sd 1."""
    rng = np.random.default_rng(seed)
    total = np.zeros((h, w), np.float32)
    amp = 1.0
    for o in range(octaves):
        c = max(1.5, cell / 2 ** o)
        gh, gw = int(h / c) + 3, int(w / c) + 3
        grid = Image.fromarray(rng.random((gh, gw)).astype(np.float32), "F")
        big = np.asarray(grid.resize((max(w, int(gw * c)), max(h, int(gh * c))), Image.BICUBIC), np.float32)
        total += big[:h, :w] * amp
        amp *= gain
    total -= total.mean()
    return total / (total.std() + 1e-6)


def splat(w, h, X, Y, sig, amp, extra=None):
    """Gaussian blobs summed on the smallest box of the frame that holds them."""
    pad = 3 * sig
    x0, x1 = int(max(0, np.floor(np.min(X - pad)))), int(min(w, np.ceil(np.max(X + pad)) + 1))
    y0, y1 = int(max(0, np.floor(np.min(Y - pad)))), int(min(h, np.ceil(np.max(Y + pad)) + 1))
    if x1 - x0 < 2 or y1 - y0 < 2:
        return None
    D = np.zeros((y1 - y0, x1 - x0), np.float32)
    E = None if extra is None else np.zeros_like(D)
    for i in range(len(X)):
        s = max(0.6, float(sig[i]))
        r = 3 * s + 1
        cx, cy = X[i] - x0, Y[i] - y0
        ax0, ax1 = max(0, int(cx - r)), min(D.shape[1], int(cx + r) + 1)
        ay0, ay1 = max(0, int(cy - r)), min(D.shape[0], int(cy + r) + 1)
        if ax1 <= ax0 or ay1 <= ay0:
            continue
        gx = np.exp(-((np.arange(ax0, ax1) - cx) ** 2) / (2 * s * s)).astype(np.float32)
        gy = np.exp(-((np.arange(ay0, ay1) - cy) ** 2) / (2 * s * s)).astype(np.float32)
        g = np.outer(gy, gx) * float(amp[i])
        D[ay0:ay1, ax0:ax1] += g
        if E is not None:
            E[ay0:ay1, ax0:ax1] += g * float(extra[i])
    return x0, y0, D, E


def smooth(x):
    x = np.clip(x, 0, 1)
    return x * x * (3 - 2 * x)


# --- the camera, the sky and the ground ----------------------------------------------------

class Cam:
    def __init__(self, w, h):
        self.w, self.h = w, h
        self.f = FOCAL * w
        self.sc = w / 2520
        self.pos = np.array([0.0, 0.0, CAM_ALT])
        self.dip = math.acos(R / (R + CAM_ALT))
        a = math.atan((0.5 - HORIZON_Y) * h / self.f)
        p = -self.dip - a
        self.fwd = np.array([math.cos(p), 0.0, math.sin(p)])
        self.right = np.array([0.0, -1.0, 0.0])
        self.up = np.cross(self.right, self.fwd)
        d = self.ray(SUN_X * w, HORIZON_Y * h)
        self.sun_az = math.atan2(-d[1], d[0])
        es = -self.dip + math.radians(SUN_UP)
        self.sun = np.array([math.cos(es) * math.cos(self.sun_az), -math.cos(es) * math.sin(self.sun_az), math.sin(es)])
        self.sun_flat = np.array([math.cos(self.sun_az), -math.sin(self.sun_az), 0.0])
        self.sun_xy = self.project(self.pos + self.sun * 1e5)[:2]

    def project(self, P):
        d = np.asarray(P, np.float64) - self.pos
        z = d @ self.fwd
        return self.w / 2 + self.f * (d @ self.right) / z, self.h / 2 - self.f * (d @ self.up) / z, z

    def ray(self, X, Y):
        d = self.fwd + ((X - self.w / 2) / self.f) * self.right + ((self.h / 2 - Y) / self.f) * self.up
        return d / np.linalg.norm(d)

    def at(self, fx, fy, dist):
        """The point `dist` km out along the ray through a spot of the frame (fractions)."""
        return self.pos + self.ray(fx * self.w, fy * self.h) * dist

    def at_alt(self, fx, fy, alt):
        """Where the ray through a spot of the frame is `alt` km above the ground."""
        d = self.ray(fx * self.w, fy * self.h)
        oc = self.pos + np.array([0, 0, R])
        b, c = d @ oc, oc @ oc - (R + alt) ** 2
        q = math.sqrt(b * b - c)
        return self.pos + d * (-b + q if c < 0 else -b - q)

    def ground(self, fx, fy):
        d = self.ray(fx * self.w, fy * self.h)
        oc = self.pos + np.array([0, 0, R])
        b, c = d @ oc, oc @ oc - R * R
        return self.pos + d * (-b - math.sqrt(b * b - c))

    def to_sun(self, x, y):
        """A unit screen vector from (x, y) toward the sun."""
        v = np.array([self.sun_xy[0] - x, self.sun_xy[1] - y])
        return v / (np.linalg.norm(v) + 1e-9)

    def sky(self, d, dip=None):
        dip = self.dip if dip is None else dip
        e = np.arcsin(np.clip(d[..., 2], -1, 1))
        eh = np.maximum(e + dip, 0)[..., None]
        g = np.arccos(np.clip(d @ self.sun.astype(np.float32), -1, 1))[..., None]
        phi = np.arctan2(-d[..., 1], d[..., 0])
        side = (0.5 + 0.5 * np.cos(phi - self.sun_az))[..., None].astype(np.float32)
        col = ZEN + (HAZE - ZEN) * np.exp(-eh / 0.32)
        s8 = side ** 8
        col = col + (DUSK * (1 - s8) + DAWN * s8) * np.exp(-eh / (0.02 + 0.08 * side ** 3))
        col = col + TEAL * np.exp(-((eh - 0.2) / 0.12) ** 2) * side
        col = col + GOLD * np.exp(-g / 0.075) * np.exp(-eh / 0.03)
        col = col + WARM * np.exp(-g / 0.4) * np.exp(-eh / 0.16)
        return col

    def horizon_col(self, d):
        """The sky just over the horizon in the same direction as d."""
        phi = np.arctan2(-d[..., 1], d[..., 0])
        e = -self.dip + 0.002
        h = np.stack([np.cos(e) * np.cos(phi), -np.cos(e) * np.sin(phi), np.full(phi.shape, math.sin(e))], -1)
        return self.sky(h.astype(np.float32))


class Ground:
    """Dark land, one river catching the dawn, and the glow of the fires."""

    def __init__(self, cam):
        self.cam = cam
        self.x0, self.y0, self.px = 0.0, 520.0, 0.5
        self.noise = (fbm(2080, 1400, 50, 6, 3) * 0.7 + fbm(2080, 1400, 8, 3, 4) * 0.3)
        self.fires = []
        self.river = None

    def tex(self, x, y):
        fj = np.clip((x - self.x0) / self.px, 0, self.noise.shape[1] - 2)
        fi = np.clip((self.y0 - y) / self.px, 0, self.noise.shape[0] - 2)
        j, i = fj.astype(np.int64), fi.astype(np.int64)
        a, b = fj - j, fi - i
        n = self.noise
        return n[i, j] * (1 - a) * (1 - b) + n[i, j + 1] * a * (1 - b) + n[i + 1, j] * (1 - a) * b + n[i + 1, j + 1] * a * b

    def river_y(self, x):
        xs, ys = self.river
        return np.interp(x, xs, ys) + 6 * np.sin(x / 24 + 1.0) + 2.2 * np.sin(x / 9.7 + 2.0)

    def shade(self, d, t):
        cam = self.cam
        P = cam.pos + d * t[:, None]
        x, y = P[:, 0], P[:, 1]
        col = GROUND * (0.8 + 0.22 * self.tex(x, y))[:, None]
        n = (P + np.array([0, 0, R])) / R
        mu = np.clip(-(d * n).sum(1), 1e-3, 1)
        if self.river is not None:
            off = np.abs(y - self.river_y(x))
            foot = t / cam.f / np.maximum(mu, 0.03)   # km of ground under one pixel, across the river
            half = 0.7 + 0.005 * t
            water = np.clip((half - off) / np.maximum(foot, 1e-3) + 0.5, 0, 1)
            wet = water > 0
            if wet.any():
                dw = d[wet] + 2 * mu[wet, None] * n[wet]
                fres = 0.03 + 0.97 * (1 - mu[wet]) ** 5
                refl = cam.sky(dw.astype(np.float32), dip=0.0) * fres[:, None] * 0.9
                col[wet] = col[wet] * (1 - water[wet, None]) + (refl + GROUND * 0.4) * water[wet, None]
        for fx, fy, c, s in self.fires:
            r2 = ((x - fx) ** 2 + (y - fy) ** 2) / (s * s)
            col = col + c * (np.exp(-r2) + 0.18 / (1 + r2 / 9))[:, None].astype(np.float32)
        T = np.exp(-t / LH)[:, None]
        return col * T + cam.horizon_col(d) * 0.32 * (1 - T) ** 2.2


def background(cam, ground):
    w, h = cam.w, cam.h
    xs = ((np.arange(w) - w / 2) / cam.f).astype(np.float32)
    img = np.zeros((h, w, 3), np.float32)
    oc = cam.pos + np.array([0, 0, R])
    rng = np.random.default_rng(2)
    for y0 in range(0, h, 250):               # in bands, to keep memory down
        ys = ((h / 2 - np.arange(y0, min(h, y0 + 250))) / cam.f).astype(np.float32)
        d = (cam.fwd[None, None] + xs[None, :, None] * cam.right[None, None]
             + ys[:, None, None] * cam.up[None, None]).astype(np.float32)
        d /= np.linalg.norm(d, axis=2, keepdims=True)
        bh = d.shape[0]
        d = d.reshape(-1, 3)
        b = d @ oc.astype(np.float32)
        disc = b * b - float(oc @ oc - R * R)
        hit = (disc > 0) & (b < 0)
        out = np.zeros((len(d), 3), np.float32)
        sky = ~hit
        out[sky] = cam.sky(d[sky])
        star = sky & (rng.random(len(d)) < 0.0005 * cam.sc ** -2 / 4)
        if star.any():
            e = np.arcsin(d[star, 2]) + cam.dip
            out[star] += (rng.uniform(0.05, 0.35, star.sum()) * smooth((e - 0.12) / 0.2))[:, None]
        if hit.any():
            t = -b[hit] - np.sqrt(disc[hit])
            out[hit] = ground.shade(d[hit].astype(np.float64), t.astype(np.float64)).astype(np.float32)
        img[y0:y0 + bh] = out.reshape(bh, w, 3)
    return img


# --- smoke, fire and light ------------------------------------------------------------------

def smoke(img, cam, P, rad, dens, alb, *, seed, sky=(0.18, 0.22, 0.32), glow=(0.40, 0.22, 0.11), fwd=0.5,
          lights=(), sunlit=True, noise=0.6, tau=1.0, edge=0.1, cellk=1.6):
    """Billowing smoke from particles (world points, radii in km): dark where thick, glowing
    at the thin edges with the light behind it, lit from below by fires and, high up, by
    the sun."""
    h, w = img.shape[:2]
    X, Y, Z = cam.project(P)
    ok = Z > 0.5
    if not ok.any():
        return
    X, Y, Z, rad, dens, alt = X[ok], Y[ok], Z[ok], rad[ok], dens[ok], P[ok, 2]
    sig = rad * cam.f / Z * 0.6
    res = splat(w, h, X, Y, sig, dens * rad ** 0.3, extra=alt)
    if res is None:
        return
    x0, y0, D, A = res
    hh, ww = D.shape
    altm = A / (D + 1e-6)
    D *= 3.0 / (np.percentile(D[D > D.max() * 0.02], 85) + 1e-6)
    cell = float(np.median(sig)) * cellk
    N = fbm(hh, ww, cell, 4, seed)
    t = np.maximum(D * np.exp(noise * N) - edge, 0) * tau
    alpha = 1 - np.exp(-t)
    bg = img[y0:y0 + hh, x0:x0 + ww]
    bgb = blur(bg, cell * 0.8)
    alb = np.asarray(alb, np.float32)
    gy, gx = np.mgrid[0:hh, 0:ww].astype(np.float32)
    char = cell

    def march(ux, uy, length):
        acc = np.zeros_like(t)
        for k in range(1, 7):
            s = length * k / 6
            xx = np.clip(np.rint(gx + ux * s), 0, ww - 1).astype(np.int32)
            yy = np.clip(np.rint(gy + uy * s), 0, hh - 1).astype(np.int32)
            acc += t[yy, xx]
        return np.exp(-acc / 6 * length / char * 1.2)

    up = march(0.0, -1.0, char * 1.2)
    ux, uy = cam.to_sun(x0 + ww / 2, y0 + hh / 2)
    toward = march(ux, uy, char * 1.5)
    lit = smooth((altm - SHADOW + 3) / 8) if sunlit else np.zeros_like(t)
    col = (alb * np.asarray(sky, np.float32) * (0.3 + 0.7 * up)[..., None]
           + alb * np.asarray(glow, np.float32) * (toward * (1 - 0.5 * lit))[..., None]
           + alb * SUNC * (toward * lit * 0.8)[..., None]
           + bgb * fwd * np.exp(-t * 0.9)[..., None]
           + SUNC * (lit * np.exp(-1.3 * t) * (0.25 + 0.75 * toward) * 0.9)[..., None])
    for lx, ly, lc, reach in lights:
        vx, vy = (lx - x0) - gx, (ly - y0) - gy
        dist = np.sqrt(vx * vx + vy * vy) + 1e-3
        T = march(vx / dist, vy / dist, np.minimum(dist, reach))
        col += alb * np.asarray(lc, np.float32) * (T / (1 + (dist / reach) ** 2))[..., None]
    dist = float(np.median(Z))
    Th = math.exp(-dist / LA)
    col = col * Th + bgb * 0.35 * (1 - Th)
    img[y0:y0 + hh, x0:x0 + ww] = bg * (1 - alpha[..., None]) + col * alpha[..., None]


def fire_rgb(E):
    E = np.minimum(E, 4.0)[..., None]
    return np.concatenate([1.3 * E, 0.62 * E ** 1.5, 0.22 * E ** 2.8], -1).astype(np.float32)


def fire(img, cam, P, rad, heat, *, seed, noise=1.0, gain=1.0):
    """Flames and fireballs: glowing particles, broken up by noise, coloured by heat."""
    h, w = img.shape[:2]
    X, Y, Z = cam.project(P)
    ok = Z > 0.5
    X, Y, Z, rad, heat = X[ok], Y[ok], Z[ok], rad[ok], heat[ok]
    sig = rad * cam.f / Z * 0.6
    res = splat(w, h, X, Y, sig, heat)
    if res is None:
        return
    x0, y0, E, _ = res
    hh, ww = E.shape
    E *= 0.75 / (np.percentile(E[E > E.max() * 0.02], 90) + 1e-6)
    N = fbm(hh, ww, float(np.median(sig)) * 1.6, 3, seed)
    E = np.maximum(E * np.exp(noise * N * 0.6) - 0.05, 0) * gain
    Th = math.exp(-float(np.median(Z)) / (LA * 1.5))
    img[y0:y0 + hh, x0:x0 + ww] += fire_rgb(E) * Th


def glow_dot(img, x, y, sigma, colour):
    h, w = img.shape[:2]
    r = int(3 * sigma) + 2
    ax0, ax1, ay0, ay1 = max(0, int(x) - r), min(w, int(x) + r), max(0, int(y) - r), min(h, int(y) + r)
    if ax1 <= ax0 or ay1 <= ay0:
        return
    gx = np.exp(-((np.arange(ax0, ax1) - x) ** 2) / (2 * sigma * sigma))
    gy = np.exp(-((np.arange(ay0, ay1) - y) ** 2) / (2 * sigma * sigma))
    img[ay0:ay1, ax0:ax1] += (np.outer(gy, gx)[..., None] * np.asarray(colour)).astype(np.float32)


def glow_path(img, pts, inten, width, colour, blurs):
    """A line of light: pts screen points, inten per point (0..1), blurred at a few radii."""
    h, w = img.shape[:2]
    m = Image.new("L", (w, h))
    d = ImageDraw.Draw(m)
    for i in range(len(pts) - 1):
        v = int(255 * max(0.0, min(1.0, (inten[i] + inten[i + 1]) / 2)))
        if v:
            d.line([tuple(pts[i]), tuple(pts[i + 1])], fill=v, width=max(1, int(round(width))))
    box = m.getbbox()
    if not box:
        return
    pad = int(3 * max(s for s, _ in blurs)) + 2
    x0, y0, x1, y1 = max(0, box[0] - pad), max(0, box[1] - pad), min(w, box[2] + pad), min(h, box[3] + pad)
    a = np.asarray(m, np.float32)[y0:y1, x0:x1] / 255
    for s, k in blurs:
        img[y0:y1, x0:x1] += (blur(a, s) if s > 0.3 else a)[..., None] * np.asarray(colour, np.float32) * k


# --- the drones -----------------------------------------------------------------------------

def shahed():
    """A delta-wing attack drone, nose along +x, about 2 long: (vertices, part) faces."""
    F = []
    xs = [1.0, 0.95, 0.86, 0.7, 0.35, -0.55, -0.76, -0.86]
    rs = [0.0, 0.042, 0.07, 0.09, 0.1, 0.1, 0.085, 0.07]
    m = 10
    rings = [[(x, r * math.cos(2 * math.pi * j / m), 0.85 * r * math.sin(2 * math.pi * j / m)) for j in range(m)]
             for x, r in zip(xs, rs)]
    for i in range(len(xs) - 1):
        for j in range(m):
            F.append(([rings[i][j], rings[i][(j + 1) % m], rings[i + 1][(j + 1) % m], rings[i + 1][j]], "body"))
    F.append((rings[-1], "body"))
    for s in (1, -1):
        wing = [(0.32, 0.09 * s), (-0.56, 0.74 * s), (-0.74, 0.74 * s), (-0.68, 0.09 * s)]
        F.append(([(x, y, 0.014) for x, y in wing], "wing"))
        F.append(([(x, y, -0.014) for x, y in wing], "wing"))
        F.append(([(-0.46, 0.74 * s, -0.07), (-0.6, 0.74 * s, 0.19), (-0.8, 0.74 * s, 0.19),
                   (-0.8, 0.74 * s, -0.07)], "fin"))
    return [(np.array(v, np.float64), k) for v, k in F]


FACES = shahed()


def orient(yaw, pitch, roll):
    cy, sy = math.cos(yaw), math.sin(yaw)
    cp, sp = math.cos(pitch), math.sin(pitch)
    cr, sr = math.cos(roll), math.sin(roll)
    Rz = np.array([[cy, -sy, 0], [sy, cy, 0], [0, 0, 1]])
    Ry = np.array([[cp, 0, -sp], [0, 1, 0], [sp, 0, cp]])
    Rx = np.array([[1, 0, 0], [0, cr, -sr], [0, sr, cr]])
    return Rz @ Ry @ Rx


def newell(V):
    n = np.zeros(3)
    for i in range(len(V)):
        a, b = V[i], V[(i + 1) % len(V)]
        n += [(a[1] - b[1]) * (a[2] + b[2]), (a[2] - b[2]) * (a[0] + b[0]), (a[0] - b[0]) * (a[1] + b[1])]
    return n / (np.linalg.norm(n) + 1e-12)


def drone(img, cam, C, L, M):
    """One drone, shaded: sky light from above, the dawn glow and (high up) the sun from the
    east, a thin warm rim on the side toward the sun, and air in front of it."""
    h, w = img.shape[:2]
    lit = float(smooth((C[2] - SHADOW + 3) / 8))
    polys = []
    for verts, kind in FACES:
        V = C + L * (verts @ M.T)
        X, Y, Z = cam.project(V)
        if np.any(Z < 0.5):
            return
        n = newell(V)
        view = cam.pos - V.mean(0)
        if n @ view < 0:
            n = -n
        amb = np.array([0.10, 0.13, 0.20]) * (0.55 + 0.45 * n[2])
        glow = np.array([0.55, 0.30, 0.15]) * max(0.0, 0.35 + 0.65 * float(n @ cam.sun_flat)) ** 2
        sun = SUNC * max(0.0, float(n @ cam.sun)) * lit
        under = np.array([0.10, 0.06, 0.04]) * (0.5 - 0.5 * n[2])
        c = 0.2 * (amb + glow + sun + under)
        polys.append((float(np.linalg.norm(view)), np.stack([X, Y], 1), c))
    allp = np.concatenate([p[1] for p in polys])
    pad = 8
    x0, y0 = int(max(0, allp[:, 0].min() - pad)), int(max(0, allp[:, 1].min() - pad))
    x1, y1 = int(min(w, allp[:, 0].max() + pad)), int(min(h, allp[:, 1].max() + pad))
    if x1 - x0 < 1 or y1 - y0 < 1:
        return
    span = max(allp[:, 0].max() - allp[:, 0].min(), allp[:, 1].max() - allp[:, 1].min())
    cx, cy = (x0 + x1) // 2, (y0 + y1) // 2
    bg = img[min(h - 1, max(0, cy)), min(w - 1, max(0, cx))].copy()
    dist = float(np.linalg.norm(C - cam.pos))
    T = math.exp(-dist / LA)
    lay = Image.new("RGB", (x1 - x0, y1 - y0))
    mask = Image.new("L", (x1 - x0, y1 - y0))
    dl, dm = ImageDraw.Draw(lay), ImageDraw.Draw(mask)
    ux, uy = cam.to_sun(cx, cy)
    off = max(1.2 * cam.sc * 4, span * 0.022)
    rim = (np.array([0.75, 0.42, 0.2]) * (0.35 + 0.65 * lit)) * T + bg * (1 - T)
    for _, pts, _ in polys:
        q = [(px - x0 + ux * off, py - y0 + uy * off) for px, py in pts]
        dl.polygon(q, fill=tuple(int(min(1, v) * 255) for v in rim))
        dm.polygon(q, fill=255)
    for _, pts, c in sorted(polys, key=lambda p: -p[0]):
        c = c * T + bg * (1 - T)
        q = [(px - x0, py - y0) for px, py in pts]
        dl.polygon(q, fill=tuple(int(min(1, v) * 255) for v in c))
        dm.polygon(q, fill=255)
    a = np.asarray(mask, np.float32)[..., None] / 255
    src = np.asarray(lay, np.float32) / 255
    img[y0:y1, x0:x1] = img[y0:y1, x0:x1] * (1 - a) + src * a


def bezier(a, b, c, u):
    u = np.asarray(u)[..., None]
    return (1 - u) ** 2 * a + 2 * u * (1 - u) * b + u ** 2 * c


def through(a, m, c):
    """The middle control point of a quadratic Bezier from a to c that passes through m."""
    return 2 * m - 0.5 * (a + c)


# --- the scene ------------------------------------------------------------------------------

def plume(rng, base, height, r0, r1, lean, n, spread=0.0):
    """Particles of a smoke column: rising, leaning downwind, spreading out at the top."""
    s = rng.random(n) ** 0.9
    lean = np.asarray(lean, np.float64)
    c = base[None] + lean[None] * (s ** 1.8)[:, None] * height
    c[:, 2] += height * s ** 0.85
    rad = r0 + (r1 - r0) * s ** 1.1
    top = np.clip((s - 0.75) / 0.25, 0, 1)
    c += lean[None] / (np.linalg.norm(lean) + 1e-9) * (top * spread * rng.random(n))[:, None]
    P = c + rng.normal(0, 1, (n, 3)) * (rad * 0.45)[:, None]
    rad = rad * rng.uniform(0.55, 1.0, n)
    dens = 1.2 - 0.6 * s
    return P, rad, dens, s


def smoke_path(img, pts, widths, alpha, colour, soft):
    """A thin trail of smoke along screen points, wider and fainter with age (alpha per point)."""
    h, w = img.shape[:2]
    m = Image.new("L", (w, h))
    d = ImageDraw.Draw(m)
    for i in range(len(pts) - 1):
        v = int(255 * max(0.0, min(1.0, (alpha[i] + alpha[i + 1]) / 2)))
        if v:
            d.line([tuple(pts[i]), tuple(pts[i + 1])], fill=v, width=max(1, int(round(widths[i]))))
    box = m.getbbox()
    if not box:
        return
    pad = int(3 * soft) + 2
    x0, y0, x1, y1 = max(0, box[0] - pad), max(0, box[1] - pad), min(w, box[2] + pad), min(h, box[3] + pad)
    a = blur(np.asarray(m, np.float32)[y0:y1, x0:x1] / 255, soft)[..., None]
    img[y0:y1, x0:x1] = img[y0:y1, x0:x1] * (1 - a) + np.asarray(colour, np.float32) * a


def burst(img, cam, rng, P0, size, seed, pieces=6):
    """A blast in the air: a flash, a ragged cloud lit from inside, a few burning pieces
    dropping out of it on smoky trails."""
    x, y, z = cam.project(P0[None])
    x, y, z = float(x[0]), float(y[0]), float(z[0])
    px = size * cam.f / z     # screen pixels per km of the blast
    k = cam.sc * 4
    for _ in range(pieces):
        a = rng.uniform(-math.pi, 0) if rng.random() < 0.6 else rng.uniform(0, math.pi)
        sp = px * rng.uniform(0.5, 1.1)
        vx, vy = math.cos(a) * sp, math.sin(a) * sp * 0.6
        ts = np.linspace(0, rng.uniform(0.8, 1.4), 24)
        pts = np.stack([x + vx * ts, y + vy * ts + px * 1.3 * ts ** 2], 1)
        age = 1 - ts / ts[-1]
        smoke_path(img, pts, (1.2 + 3.5 * age) * k, 0.55 * (1 - age) ** 0.3 * (0.4 + 0.6 * age),
                   (0.07, 0.07, 0.08), 1.2 * k)
        glow_dot(img, pts[-1, 0], pts[-1, 1], 1.3 * k, (1.6, 0.9, 0.4))
        glow_dot(img, pts[-1, 0], pts[-1, 1], 4 * k, (0.25, 0.1, 0.03))
    n = 90
    P = P0[None] + rng.normal(0, 1, (n, 3)) * size * np.array([0.42, 0.42, 0.32])
    rad = size * rng.uniform(0.25, 0.6, n)
    smoke(img, cam, P, rad, np.ones(n), (0.30, 0.29, 0.28), seed=seed, fwd=0.35,
          lights=[(x, y, FIRE * 4.0, px * 0.6)], noise=0.8, edge=0.25)
    m = 30
    Pf = P0[None] + rng.normal(0, 1, (m, 3)) * size * 0.2
    fire(img, cam, Pf, size * rng.uniform(0.12, 0.28, m), rng.uniform(0.5, 1.0, m), seed=seed + 1, gain=1.5)
    glow_dot(img, x, y, px * 0.1, (2.5, 2.2, 1.8))
    glow_dot(img, x, y, px * 0.45, (0.6, 0.3, 0.1))
    glow_dot(img, x, y, px * 1.8, (0.08, 0.04, 0.02))


def ballistic(img, cam, head, v, length, bright=True):
    """A warhead falling: a white-hot point with a glowing streak behind it."""
    ls = np.linspace(0, length, 90)
    P = head[None] - v[None] * ls[:, None]
    X, Y, Z = cam.project(P)
    ok = Z > 1
    pts = np.stack([X[ok], Y[ok]], 1)
    k = cam.sc * 4
    glow_path(img, pts, np.exp(-ls[ok] / (0.2 * length)) * 0.9 + 0.14 * np.exp(-ls[ok] / length),
              1.8 * k, (1.0, 0.86, 0.68), [(0, 0.7), (2.5 * k, 0.55), (9 * k, 0.3), (26 * k, 0.1)])
    if bright:
        x, y = float(X[0]), float(Y[0])
        glow_dot(img, x, y, 2.0 * k, (3.0, 2.8, 2.5))
        glow_dot(img, x, y, 7 * k, (0.8, 0.55, 0.3))
        glow_dot(img, x, y, 24 * k, (0.12, 0.08, 0.05))


def interceptor(img, cam, rng, a, c, seed, upto=1.0, motor=True):
    """A missile climbing from the ground at a: a vertical launch that bends over toward c,
    a white smoke trail, a bright motor at the head."""
    ctrl = a + np.array([0, 0, 0.7 * np.linalg.norm(c - a)])
    n = 900
    u = np.sort(rng.random(n)) * upto
    path = bezier(a, ctrl, c, u)
    age = (upto - u) / upto
    rad = 0.3 + 1.6 * age ** 0.8
    drift = np.array([0, 1.0, 0]) * (age ** 1.5 * 5)[:, None]
    P = path + drift + rng.normal(0, 1, (n, 3)) * (rad * 0.22)[:, None]
    head = bezier(a, ctrl, c, upto)
    hx, hy, hz = cam.project(head[None])
    hx, hy = float(hx[0]), float(hy[0])
    k = cam.sc * 4
    lights = [(hx, hy, (1.4, 1.0, 0.6), 50 * k)] if motor else []
    smoke(img, cam, P, rad, 0.6 + 0.4 * (1 - age), (0.85, 0.85, 0.88), seed=seed, sky=(0.22, 0.26, 0.34),
          glow=(0.5, 0.3, 0.16), fwd=0.5, lights=lights, noise=0.45, tau=0.55, edge=0.04, cellk=2.5)
    if motor:
        glow_dot(img, hx, hy, 2.0 * k, (3.0, 2.7, 2.2))
        glow_dot(img, hx, hy, 7 * k, (1.0, 0.6, 0.3))
        glow_dot(img, hx, hy, 24 * k, (0.15, 0.08, 0.04))
    return head


def ground_fire(img, cam, rng, base, width, seed, blast=False):
    """A strike burning on the ground: low flames, and if fresh, a fireball rising out of them."""
    n = 80
    ang = rng.uniform(0, math.tau, n)
    r = width * np.sqrt(rng.random(n)) * 0.5
    P = base[None] + np.stack([np.cos(ang) * r, np.sin(ang) * r, rng.random(n) ** 2 * width * 0.3], 1)
    fire(img, cam, P, width * rng.uniform(0.06, 0.15, n), rng.uniform(0.25, 0.9, n), seed=seed, gain=1.2)
    x, y, z = cam.project(base[None])
    px = width * cam.f / float(z[0])
    if blast:
        m = 120
        d = rng.normal(0, 1, (m, 3))
        d[:, 2] = np.abs(d[:, 2])
        Pb = base[None] + d * width * np.array([0.38, 0.38, 0.45]) + [0, 0, width * 0.15]
        fire(img, cam, Pb, width * rng.uniform(0.16, 0.3, m), rng.uniform(0.3, 1.0, m), seed=seed + 7,
             gain=1.5, noise=1.3)
        glow_dot(img, float(x[0]), float(y[0]) - px * 0.25, px * 0.5, (0.7, 0.32, 0.1))
    glow_dot(img, float(x[0]), float(y[0]) - px * 0.1, px * 1.4, (0.22, 0.09, 0.03))


def scene(img, cam):
    rng = np.random.default_rng(7)
    k = cam.sc * 4
    ops = []   # (distance, draw): drawn far to near
    wind = np.array([0.0, 1.0, 0.0])

    # The strikes: a fresh blast under a tall column of smoke in front of the sunrise, an
    # older fire to the left, both leaning west with the wind.
    big, old = cam.ground(*BIG), cam.ground(*OLD)

    def big_strike():
        P, rad, dens, s = plume(np.random.default_rng(11), big, 44.0, 2.0, 9.5, wind * 0.42, 1400, spread=14)
        x, y, _ = cam.project(big[None])
        smoke(img, cam, P, rad, dens, (0.24, 0.22, 0.21), seed=21, fwd=0.55,
              lights=[(float(x[0]), float(y[0]) - 20 * k, FIRE * 6.0, 160 * k)], tau=1.1)
        ground_fire(img, cam, np.random.default_rng(12), big, 13.0, 31, blast=True)

    def old_strike():
        P, rad, dens, s = plume(np.random.default_rng(13), old, 18.0, 1.0, 4.5, wind * 0.6, 700, spread=6)
        x, y, _ = cam.project(old[None])
        smoke(img, cam, P, rad, dens, (0.22, 0.21, 0.2), seed=22, fwd=0.45,
              lights=[(float(x[0]), float(y[0]) - 10 * k, FIRE * 3.5, 90 * k)], tau=1.0)
        ground_fire(img, cam, np.random.default_rng(14), old, 4.0, 32)

    ops.append((np.linalg.norm(big - cam.pos), big_strike))
    ops.append((np.linalg.norm(old - cam.pos), old_strike))

    # Two warheads coming down from the east: one met by an interceptor on the left, one
    # still falling through the middle.
    v = np.array([-0.3, 0.42, -1.0])
    v /= np.linalg.norm(v)
    hit = cam.at(*HIT, 95.0)
    other = cam.at(*OTHER, 200.0)
    launch = cam.ground(*LAUNCH)

    def interception():
        ballistic(img, cam, hit, v, 150.0, bright=False)
        interceptor(img, cam, np.random.default_rng(15), launch, hit, 41, motor=False)
        burst(img, cam, np.random.default_rng(16), hit, 3.4, 51)

    ops.append((np.linalg.norm(hit - cam.pos), interception))
    ops.append((np.linalg.norm(other - cam.pos), lambda: ballistic(img, cam, other, v, 170.0)))

    # The column of drones: out of the sunrise, sweeping in and banking across us on the right.
    near, far = cam.at_alt(*NEAR, ALT_N), cam.at_alt(*FAR, ALT_F)
    hn, hf = math.radians(HEAD_N), math.radians(HEAD_F)
    dn, df = np.array([math.cos(hn), math.sin(hn)]), np.array([math.cos(hf), math.sin(hf)])
    # The corner where the two headings meet is the middle control point.
    A = np.array([[-dn[0], -df[0]], [-dn[1], -df[1]]])
    a_, b_ = np.linalg.solve(A, far[:2] - near[:2])
    ctrl = np.r_[near[:2] - dn * a_, 0.0]

    def column(u):
        u = np.asarray(u, np.float64)
        xy = bezier(np.r_[far[:2], 0.0], ctrl, np.r_[near[:2], 0.0], u)[..., :2]
        alt = ALT_F + (ALT_N - ALT_F) * u
        c = np.array([0, 0, -R])
        v = np.concatenate([xy, np.zeros(xy.shape[:-1] + (1,))], -1) - c
        v[..., 2] = R
        return c + v / np.linalg.norm(v, axis=-1, keepdims=True) * (R + alt)[..., None]

    us = np.linspace(0, 1, 3000)
    X, Y, _ = cam.project(column(us))
    seg = np.r_[0, np.cumsum(np.hypot(np.diff(X), np.diff(Y)))]
    n = 11
    q = 1 / 0.84   # each gap on screen this much wider than the one before, toward us
    gaps = q ** np.arange(n - 1)
    at = np.r_[0, np.cumsum(gaps)] / gaps.sum() * seg[-1]
    picks = np.interp(at, seg, us)
    for i, u in enumerate(picks):
        C = column(u)
        d1 = column(min(1.0, u + 1e-3)) - column(max(0.0, u - 1e-3))
        yaw = math.atan2(d1[1], d1[0])
        roll = -(0.15 + 0.45 * u) + rng.uniform(-0.05, 0.05)
        M = orient(yaw, 0.0, roll)
        dist = float(np.linalg.norm(C - cam.pos))
        if i == SHOT:
            ops.append((dist, lambda C=C: burst(img, cam, np.random.default_rng(18), C, 1.3, 52, pieces=5)))
            continue
        ops.append((dist, lambda C=C, M=M: drone(img, cam, C, SIZE, M)))

    for _, op in sorted(ops, key=lambda o: -o[0]):
        op()


def finish(img):
    """Bloom, a soft shoulder for the highlights, a cool-warm grade, vignette and grain."""
    h, w = img.shape[:2]
    bright = np.maximum(img - 0.75, 0)
    img = img + blur(bright, w * 0.004) * 0.45 + blur(bright, w * 0.018) * 0.3 + blur(bright, w * 0.06) * 0.15
    knee = 0.6
    img = np.where(img < knee, img, knee + (1 - knee) * (1 - np.exp(-(img - knee) / (1 - knee))))
    lum = img @ np.array([0.3, 0.59, 0.11], np.float32)
    img = img + (np.array([-0.004, 0.003, 0.012], np.float32) * (1 - smooth(lum / 0.25))[..., None])
    yy, xx = np.mgrid[0:h, 0:w].astype(np.float32)
    v = 1 - 0.45 * (((xx - w / 2) / (w * 0.72)) ** 2 + ((yy - h / 2) / (h * 0.8)) ** 2)
    img = img * np.clip(v, 0.45, 1)[..., None]
    img = img * 255 + np.random.default_rng(5).normal(0, 1.6, (h, w))[..., None]
    return Image.fromarray(np.clip(img, 0, 255).astype(np.uint8))


def with_logo(img):
    w, h = img.size
    out = img.convert("RGBA")
    lg = Image.open(LOGO).convert("RGBA")
    lw = int(w * 0.70)
    lg = lg.resize((lw, round(lg.height * lw / lg.width)), Image.LANCZOS)
    out.alpha_composite(lg, ((w - lw) // 2, int(h * 0.955) - lg.height))
    return out.convert("RGB")


def main():
    out = sys.argv[1]
    preview = "--preview" in sys.argv
    w, h = (1260, 1000) if preview else (2520, 2000)
    cam = Cam(w, h)
    ground = Ground(cam)
    big, old = cam.ground(*BIG), cam.ground(*OLD)
    near = cam.ground(0.5, 0.97)
    sun_far = 520.0
    ground.river = ([near[0], big[0], sun_far],
                    [near[1], big[1] - 4.0, -math.tan(cam.sun_az) * sun_far])
    ground.fires = [(big[0], big[1], FIRE * 0.9, 9.0), (old[0], old[1], FIRE * 0.5, 6.0)]
    img = background(cam, ground)
    scene(img, cam)
    img = with_logo(finish(img))
    if preview:
        img.save(os.path.join(out, "dawn-preview.png"))
    else:
        img.resize((1260, 1000), Image.LANCZOS).save(os.path.join(out, "cover-dawn-1260.png"))
        img.resize((630, 500), Image.LANCZOS).save(os.path.join(out, "cover-dawn.png"))
    print("wrote", out)


if __name__ == "__main__":
    main()
