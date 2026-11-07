"""A cover for Strike Alert: 21:10, a courtyard between Soviet panel blocks. A cruise
missile crosses the strip of sky just over the roofs, caught in a searchlight, tracers
climbing after it, a fire glowing beyond the far block. Over it, the game's own alert
screen, see-through.

    python tools/itch_night.py itch [--preview]

Writes cover-night.png (630x500) and cover-night-1260.png (--preview: night-preview.png
at 1260x1000). World units are metres: x east, y north (straight ahead), z up, the
camera on the ground looking up.
"""
import math
import os
import sys

import numpy as np
from PIL import Image, ImageDraw, ImageFont

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from itch_dawn import blur, fbm, glow_dot, glow_path, smooth, splat  # noqa: E402

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
LOGO = os.path.join(ROOT, "itch", "logo-v2.png")
FONT = os.path.join(ROOT, "assets", "fonts", "Inter.ttf")
SHOT = os.path.join(ROOT, "itch", "screenshots", "2-ballistic-hit.png")

CAM_H, PITCH, FOCAL = 1.6, 35.0, 0.652   # metres, degrees up, focal length over the frame width
CLOUD = 900.0                           # the cloud deck, metres
FH, CW = 2.8, 3.2                       # a floor's height, a window bay's width
SODIUM = np.array([1.0, 0.55, 0.22], np.float32)
BEAM = np.array([0.75, 0.86, 1.0], np.float32)

# The blocks: corners (west, south, bottom) and (east, north, top), floors, seed.
BLOCKS = [
    ((-34.0, 2.0, 0.0), (-22.0, 74.0, 45.8), 16, 1),    # left, sixteen storeys
    ((18.0, -8.0, 0.0), (30.0, 44.0, 45.8), 16, 2),     # right, sixteen storeys
    ((-80.0, 96.0, 0.0), (44.0, 108.0, 26.2), 9, 3),    # across the yard, nine storeys
]
# Lift-machine rooms on the roofs.
ROOFS = [((-31.0, 20.0, 45.8), (-25.0, 26.0, 49.0)), ((-31.0, 52.0, 45.8), (-25.0, 58.0, 49.0)),
         ((21.0, 10.0, 45.8), (27.0, 16.0, 49.0)), ((-40.0, 99.0, 26.2), (-34.0, 105.0, 29.4)),
         ((2.0, 99.0, 26.2), (8.0, 105.0, 29.4))]
MISSILE = np.array([-4.0, 58.0, 71.0])  # where the missile is
HEADING = 163.0                         # degrees, from east toward north: going west, away a little
MLEN = 15.0                             # metres long
SEARCH = np.array([70.0, 260.0, 20.0])  # the searchlight, beyond the far block
FIRE_AT = np.array([-60.0, 520.0, 0.0])  # a fire burning beyond the far block


# --- noise ----------------------------------------------------------------------------------

def _hash(ix, iy, seed):
    n = (ix * 73856093) ^ (iy * 19349663) ^ (seed * 83492791)
    n = (n ^ (n >> 13)) * 1274126177
    n = n ^ (n >> 16)
    return (n & 0xFFFFFF).astype(np.float32) / float(0x1000000)


def vnoise(x, y, seed):
    xi, yi = np.floor(x), np.floor(y)
    xf, yf = (x - xi).astype(np.float32), (y - yi).astype(np.float32)
    xi, yi = xi.astype(np.int64), yi.astype(np.int64)
    u, v = xf * xf * (3 - 2 * xf), yf * yf * (3 - 2 * yf)
    a, b = _hash(xi, yi, seed), _hash(xi + 1, yi, seed)
    c, d = _hash(xi, yi + 1, seed), _hash(xi + 1, yi + 1, seed)
    return a + (b - a) * u + (c - a) * v + (a - b - c + d) * u * v


def fbm_xy(x, y, octaves, seed, gain=0.5):
    tot, amp, norm = 0.0, 1.0, 0.0
    for o in range(octaves):
        tot = tot + vnoise(x, y, seed + o) * amp
        norm += amp
        amp *= gain
        x, y = x * 2.03 + 17.1, y * 2.03 - 9.7
    return tot / norm


# --- the camera ---------------------------------------------------------------------------

class Cam:
    def __init__(self, w, h):
        self.w, self.h, self.f, self.sc = w, h, FOCAL * w, w / 2520
        p = math.radians(PITCH)
        self.pos = np.array([0.0, 0.0, CAM_H])
        self.fwd = np.array([0.0, math.cos(p), math.sin(p)])
        self.right = np.array([1.0, 0.0, 0.0])
        self.up = np.array([0.0, -math.sin(p), math.cos(p)])

    def project(self, P):
        d = np.asarray(P, np.float64) - self.pos
        z = d @ self.fwd
        return self.w / 2 + self.f * (d @ self.right) / z, self.h / 2 - self.f * (d @ self.up) / z, z

    def rays(self, y0, y1):
        xs = (np.arange(self.w) - self.w / 2) / self.f
        ys = (self.h / 2 - np.arange(y0, y1)) / self.f
        d = (self.fwd[None, None] + xs[None, :, None] * self.right[None, None]
             + ys[:, None, None] * self.up[None, None])
        return d / np.linalg.norm(d, axis=2, keepdims=True)


# --- the sky ------------------------------------------------------------------------------

def beam_axis():
    b = MISSILE + np.array([1.5, 0.0, 0.5]) - SEARCH
    return b / np.linalg.norm(b)


def sky(d):
    """Night over a city: low cloud lit orange from below, a darker sky in the gaps, the glow
    of the city along the bottom, the searchlight's spot and the fire's glow on the cloud."""
    n = len(d)
    el = np.arcsin(np.clip(d[:, 2], -1, 1))
    t = (CLOUD - CAM_H) / np.maximum(d[:, 2], 1e-3)
    x, y = d[:, 0] * t, d[:, 1] * t
    # Rolling stratocumulus: broad lumps, thinner gaps, drifting rows.
    q = fbm_xy(x / 520 + y / 2600, y / 380, 6, 5)
    cov = smooth((q - 0.42) / 0.2)
    thick = smooth((q - 0.48) / 0.3)
    dark = np.array([0.012, 0.016, 0.03], np.float32)
    rng = np.random.default_rng(3)
    stars = (rng.random(n) < 0.0008) * rng.uniform(0.1, 0.5, n)
    col = dark + (stars * smooth((el - 0.35) / 0.3))[:, None].astype(np.float32)
    lit = np.array([0.26, 0.14, 0.07], np.float32) * (0.55 + 0.8 * thick)[:, None]
    lit = lit * (0.7 + 0.6 * np.exp(-el / 0.35))[:, None]       # brighter toward the horizon
    # The searchlight's spot on the cloud base, and the fire's glow.
    b = beam_axis()
    s = (CLOUD - SEARCH[2]) / b[2]
    spot = SEARCH + b * s
    r2 = ((x - spot[0]) ** 2 + (y - spot[1]) ** 2) / 26.0 ** 2
    lit = lit + BEAM[None] * (1.6 * np.exp(-r2) + 0.25 * np.exp(-r2 / 12))[:, None] * (0.4 + 0.6 * thick)[:, None]
    r2 = ((x - FIRE_AT[0]) ** 2 + (y - FIRE_AT[1]) ** 2) / 420.0 ** 2
    lit = lit + np.array([0.9, 0.38, 0.1], np.float32) * (0.9 * np.exp(-r2))[:, None]
    col = col * (1 - cov[:, None]) + lit * cov[:, None]
    # Haze over the city low down: sodium glow.
    glow = np.exp(-np.maximum(el, 0) / 0.12)[:, None]
    col = col * (1 - 0.6 * glow) + np.array([0.32, 0.17, 0.08], np.float32) * glow * 0.9
    return col.astype(np.float32)


# --- the blocks -------------------------------------------------------------------------------

def hit_box(C, d, lo, hi):
    dd = np.where(np.abs(d) < 1e-9, 1e-9, d)
    t0, t1 = (np.asarray(lo) - C) / dd, (np.asarray(hi) - C) / dd
    tmin, tmax = np.minimum(t0, t1), np.maximum(t0, t1)
    tn, tf = tmin.max(1), tmax.min(1)
    return (tn <= tf) & (tn > 0), tn, tmin.argmax(1)


def facade(P, axis, d, lo, hi, floors, seed, dist):
    """Concrete panels and windows: most dark (people are in the corridors), a few lit warm,
    a stairwell lit all the way up, lamps lighting the walls from below."""
    n = len(P)
    if axis == 0:
        u, along = P[:, 1] - lo[1], hi[1] - lo[1]
    else:
        u, along = P[:, 0] - lo[0], hi[0] - lo[0]
    v = P[:, 2]
    i = np.floor(u / CW).astype(np.int64)
    j = np.floor(v / FH).astype(np.int64)
    fu, fv = u - i * CW, v - j * FH
    panel = 0.9 + 0.2 * _hash(i, j, seed + 40)
    seam = (np.minimum(fu, CW - fu) < 0.06) | (np.minimum(fv, FH - fv) < 0.05)
    alb = 0.34 * panel * np.where(seam, 0.62, 1.0)
    light = (SODIUM[None] * (0.75 * np.exp(-v / 14.0) + 0.12)[:, None]
             + np.array([0.16, 0.10, 0.07], np.float32)[None])
    col = alb[:, None] * light
    if along > 30:
        stair = (i % 9) == 4
        loggia = (_hash(i, np.zeros_like(i), seed + 5) < 0.4) & ~stair
        ww = np.where(loggia, 2.5, 1.45)
        inside = (j >= 0) & (j < floors)
        win = inside & (np.abs(fu - CW / 2) < ww / 2) & (fv > 0.9) & (fv < 2.3) & ~stair
        sv = np.mod(v + FH / 2, FH)
        swin = inside & stair & (np.abs(fu - CW / 2) < 0.55) & (sv > 1.0) & (sv < 2.0)
        r = _hash(i, j, seed)
        r2 = _hash(i, j, seed + 7)
        r3 = _hash(i, j, seed + 9)
        lit = win & (r < 0.17)
        slit = swin & (_hash(i, j, seed + 3) < 0.7)
        warm = np.array([1.0, 0.66, 0.34], np.float32)
        pale = np.array([1.0, 0.85, 0.66], np.float32)
        tv = np.array([0.45, 0.6, 1.0], np.float32)
        lc = np.where((r2 < 0.65)[:, None], warm, np.where((r2 < 0.9)[:, None], pale, tv))
        lc = lc * (0.55 + 0.6 * r3)[:, None] * (0.75 + 0.35 * smooth((fv - 0.9) / 1.4))[:, None]
        mull = np.abs(fu - CW / 2) < 0.05
        glass = (np.array([0.018, 0.016, 0.02], np.float32)[None]
                 + np.array([0.05, 0.028, 0.014], np.float32)[None] * smooth((fv - 0.9) / 1.4)[:, None])
        wcol = np.where(lit[:, None], lc, glass) * np.where(mull, 0.35, 1.0)[:, None]
        col = np.where((win | swin)[:, None], wcol, col)
        col = np.where(slit[:, None], np.array([0.75, 0.9, 0.8], np.float32) * 0.8, col)
        # Loggia fronts below the glazing, some painted lighter.
        front = inside & loggia & (np.abs(fu - CW / 2) < 1.4) & (fv < 0.9) & (fv > 0.08)
        tint = np.where((_hash(i, np.zeros_like(i), seed + 6) < 0.5)[:, None],
                        np.array([1.0, 0.95, 0.85], np.float32), np.array([0.7, 0.8, 0.95], np.float32))
        col = np.where(front[:, None], col * 1.25 * tint, col)
    T = np.exp(-dist / 900.0)[:, None]
    return col * T + np.array([0.2, 0.11, 0.05], np.float32) * (1 - T) * 0.6


def background(cam):
    w, h = cam.w, cam.h
    img = np.zeros((h, w, 3), np.float32)
    depth = np.full((h, w), np.inf, np.float32)
    boxes = [(lo, hi, fl, sd) for lo, hi, fl, sd in BLOCKS] + [(lo, hi, 0, 90 + k) for k, (lo, hi) in enumerate(ROOFS)]
    for y0 in range(0, h, 250):
        y1 = min(h, y0 + 250)
        d = cam.rays(y0, y1).reshape(-1, 3)
        best = np.full(len(d), np.inf)
        which = np.full(len(d), -1)
        axes = np.zeros(len(d), np.int64)
        for k, (lo, hi, fl, sd) in enumerate(boxes):
            hit, tn, ax = hit_box(cam.pos, d, lo, hi)
            m = hit & (tn < best)
            best[m], which[m], axes[m] = tn[m], k, ax[m]
        out = np.zeros((len(d), 3), np.float32)
        s = which < 0
        out[s] = sky(d[s])
        for k, (lo, hi, fl, sd) in enumerate(boxes):
            m = which == k
            if not m.any():
                continue
            P = cam.pos + d[m] * best[m, None]
            out[m] = shade_box(P, axes[m], d[m], lo, hi, fl, sd, best[m])
        img[y0:y1] = out.reshape(y1 - y0, w, 3)
        depth[y0:y1] = best.reshape(y1 - y0, w)
    return img, depth


def shade_box(P, axes, d, lo, hi, floors, seed, dist):
    out = np.zeros((len(P), 3), np.float32)
    for ax in (0, 1, 2):
        m = axes == ax
        if not m.any():
            continue
        if ax == 2 or floors == 0:
            v = P[m, 2]
            c = 0.2 * (SODIUM[None] * (0.42 * np.exp(-v / 10.0) + 0.05)[:, None] + 0.06)
            out[m] = c * np.exp(-dist[m] / 900.0)[:, None]
        else:
            out[m] = facade(P[m], ax, d[m], lo, hi, floors, seed, dist[m])
    return out


# --- what flies --------------------------------------------------------------------------------

def missile_faces():
    """A long cruise missile, nose along +x, 1 long: a faceted body, short wings at the
    middle, small tail fins, its engine slung under the tail on a pylon."""
    F = []
    xs = [0.5, 0.475, 0.44, 0.38, 0.28, -0.42, -0.47, -0.5]
    rs = [0.0, 0.013, 0.025, 0.036, 0.042, 0.042, 0.037, 0.03]
    m = 8
    ang = [2 * math.pi * (j + 0.5) / m for j in range(m)]
    rings = [[(x, r * math.cos(a), r * 0.9 * math.sin(a)) for a in ang] for x, r in zip(xs, rs)]
    for i in range(len(xs) - 1):
        for j in range(m):
            F.append(([rings[i][j], rings[i][(j + 1) % m], rings[i + 1][(j + 1) % m], rings[i + 1][j]], "body"))
    F.append((rings[-1], "body"))
    for s in (1, -1):
        F.append(([(0.13, 0.04 * s, 0), (0.0, 0.23 * s, 0), (-0.06, 0.23 * s, 0), (-0.02, 0.04 * s, 0)], "wing"))
        F.append(([(-0.42, 0.035 * s, 0.005), (-0.47, 0.1 * s, 0.005), (-0.5, 0.1 * s, 0.005),
                   (-0.5, 0.035 * s, 0.005)], "fin"))
    F.append(([(-0.42, 0, 0.035), (-0.48, 0, 0.1), (-0.5, 0, 0.1), (-0.5, 0, 0.035)], "fin"))
    # The engine pod under the tail.
    pm = 8
    pr = 0.026
    px = [-0.31, -0.33, -0.48, -0.5]
    prs = [0.0, pr, pr, pr * 0.85]
    pr_rings = [[(x, r * math.cos(a), -0.075 + r * math.sin(a)) for a in ang] for x, r in zip(px, prs)]
    for i in range(len(px) - 1):
        for j in range(pm):
            F.append(([pr_rings[i][j], pr_rings[i][(j + 1) % pm], pr_rings[i + 1][(j + 1) % pm],
                       pr_rings[i + 1][j]], "pod"))
    F.append(([(-0.36, 0, -0.03), (-0.44, 0, -0.03), (-0.46, 0, -0.06), (-0.36, 0, -0.06)], "fin"))
    return [(np.array(v, np.float64), k) for v, k in F]


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


def missile(img, cam):
    """The missile, lit by the searchlight and the city below, smeared a little with speed."""
    h, w = img.shape[:2]
    M = orient(math.radians(HEADING), math.radians(-4), math.radians(12))
    to_light = -beam_axis()
    polys = []
    for verts, kind in missile_faces():
        V = MISSILE + MLEN * (verts @ M.T)
        X, Y, Z = cam.project(V)
        n = newell(V)
        view = cam.pos - V.mean(0)
        if n @ view < 0:
            n = -n
        vdir = view / np.linalg.norm(view)
        alb = 0.42 if kind != "pod" else 0.3
        city = SODIUM * 0.45 * max(0.0, -n[2] * 0.8 + 0.2)
        beam = BEAM * 2.6 * max(0.0, float(n @ to_light)) ** 0.8
        hv = to_light + vdir
        hv /= np.linalg.norm(hv)
        spec = BEAM * 2.0 * max(0.0, float(n @ hv)) ** 24
        c = alb * (city + beam + 0.03) + spec
        polys.append((float(np.linalg.norm(view)), np.stack([X, Y], 1), c))
    allp = np.concatenate([p[1] for p in polys])
    pad = int(60 * cam.sc * 4)
    x0, y0 = int(max(0, allp[:, 0].min() - pad)), int(max(0, allp[:, 1].min() - pad))
    x1, y1 = int(min(w, allp[:, 0].max() + pad)), int(min(h, allp[:, 1].max() + pad))
    lay = Image.new("RGB", (x1 - x0, y1 - y0))
    mask = Image.new("L", (x1 - x0, y1 - y0))
    dl, dm = ImageDraw.Draw(lay), ImageDraw.Draw(mask)
    for _, pts, c in sorted(polys, key=lambda p: -p[0]):
        q = [(px - x0, py - y0) for px, py in pts]
        dl.polygon(q, fill=tuple(int(min(1, v) * 255) for v in c))
        dm.polygon(q, fill=255)
    col = np.asarray(lay, np.float32) / 255
    a = np.asarray(mask, np.float32) / 255
    # Motion: smear backwards along the flight path on the screen.
    fwd = MISSILE + M[:, 0] * 10
    fx, fy, _ = cam.project(np.stack([MISSILE, fwd]))
    mv = np.array([fx[1] - fx[0], fy[1] - fy[0]])
    mv /= np.linalg.norm(mv)
    steps = 10
    length = 26 * cam.sc * 4
    acc_c, acc_a, wsum = np.zeros_like(col), np.zeros_like(a), 0.0
    for k in range(steps):
        sx, sy = -mv * length * k / steps
        wt = 1.0 - k / steps * 0.85
        sh_c = np.roll(np.roll(col * a[..., None], int(round(sy)), 0), int(round(sx)), 1)
        sh_a = np.roll(np.roll(a, int(round(sy)), 0), int(round(sx)), 1)
        acc_c += sh_c * wt
        acc_a += sh_a * wt
        wsum += wt
    sharp = 0.55
    pc = col * a[..., None] * sharp + acc_c / wsum * (1 - sharp)
    pa = np.clip(a * sharp + acc_a / wsum * (1 - sharp), 0, 1)
    img[y0:y1, x0:x1] = img[y0:y1, x0:x1] * (1 - pa[..., None]) + pc
    # The engine: a hot point at the nozzle and a faint heat trail behind it.
    noz = MISSILE + MLEN * (M @ np.array([-0.52, 0.0, -0.075]))
    nx, ny, _ = cam.project(noz[None])
    nx, ny = float(nx[0]), float(ny[0])
    k = cam.sc * 4
    tail = np.stack([nx - mv[0] * np.linspace(0, 140 * k, 20), ny - mv[1] * np.linspace(0, 140 * k, 20)], 1)
    glow_path(img, tail, np.linspace(0.6, 0.0, 20), 3 * k, (1.0, 0.5, 0.2), [(2 * k, 0.5), (8 * k, 0.3)])
    glow_dot(img, nx, ny, 1.8 * k, (2.5, 1.8, 1.1))
    glow_dot(img, nx, ny, 6 * k, (0.8, 0.35, 0.12))
    glow_dot(img, nx, ny, 20 * k, (0.1, 0.05, 0.02))
    return mv


def searchlight(img, depth, cam):
    """A beam out of the haze beyond the far block, through the missile, into the cloud."""
    h, w = img.shape[:2]
    b = beam_axis()
    end = (CLOUD - SEARCH[2]) / b[2]
    for y0 in range(0, h, 250):
        y1 = min(h, y0 + 250)
        d = cam.rays(y0, y1)
        w0 = cam.pos - SEARCH
        bb = d @ b
        dd = d @ w0
        e = float(b @ w0)
        den = 1 - bb * bb + 1e-9
        sr = (bb * e - dd) / den
        sb = (e - bb * dd) / den
        sb = np.clip(sb, 0, end)
        sr = np.maximum(sr, 0)
        cp = cam.pos + d * sr[..., None]
        qp = SEARCH + b[None, None] * sb[..., None]
        dist = np.linalg.norm(cp - qp, axis=2)
        r = 0.9 + sb * math.tan(math.radians(0.75))
        inten = np.exp(-(dist / r) ** 2) * 22.0 / r * np.exp(-sb / 1600.0)
        inten += np.exp(-(dist / (r * 3)) ** 2) * 2.0 / r * np.exp(-sb / 1600.0)
        vis = (sr < depth[y0:y1]).astype(np.float32)
        img[y0:y1] += BEAM * (inten * vis)[..., None] * 0.07


def tracers(img, depth, cam, gun, aim, rng, n=30):
    """Anti-aircraft fire: glowing dashes climbing on a falling curve toward aim."""
    k = cam.sc * 4
    v = aim - gun
    rng_len = np.linalg.norm(v)
    v = v / rng_len
    layer = np.zeros_like(img)
    s = rng.uniform(0, 8)
    while s < rng_len * 1.12:
        ln = 3.0 + rng.uniform(-0.6, 0.6)
        ss = np.linspace(s, s + ln, 5)
        P = gun[None] + v[None] * ss[:, None] - np.array([0, 0, 1.0])[None] * (ss ** 2 / 2600.0)[:, None]
        X, Y, Z = cam.project(P)
        pts = np.stack([X, Y], 1)
        fade = 1.0 - 0.5 * s / rng_len
        glow_path(layer, pts, np.full(5, 0.95 * fade), max(1.2 * k, 0.22 * cam.f / float(Z.mean())),
                  (1.5, 0.5, 0.18), [(0, 1.1), (1.5 * k, 0.6), (5 * k, 0.22)])
        s += ln + 4.0 + rng.uniform(-1.0, 1.0)
    dist = np.linalg.norm(gun - cam.pos)
    layer *= (depth > dist - 4)[..., None]
    img += layer


def fire_beyond(img, depth, cam):
    """A fire burning beyond the far block: its glow over the roofline and smoke climbing."""
    h, w = img.shape[:2]
    rng = np.random.default_rng(31)
    x, y, z = cam.project((FIRE_AT + [0, 0, 120])[None])
    x, y = float(x[0]), float(y[0])
    k = cam.sc * 4
    glow = np.zeros_like(img)
    glow_dot(glow, x, y, 50 * k, (1.1, 0.45, 0.12))
    glow_dot(glow, x, y, 140 * k, (0.3, 0.12, 0.03))
    glow_dot(glow, x, y, 380 * k, (0.07, 0.03, 0.01))
    far = float(np.linalg.norm(FIRE_AT - cam.pos))
    vis = (depth > far * 0.5)[..., None]
    # The smoke: particles rising and leaning east.
    n = 700
    s = rng.random(n) ** 0.9
    c = FIRE_AT[None] + np.stack([s ** 1.6 * 220, s * 60, s ** 0.85 * 520], 1)
    rad = 18 + 90 * s ** 1.1
    P = c + rng.normal(0, 1, (n, 3)) * (rad * 0.45)[:, None]
    rad = rad * rng.uniform(0.5, 1.0, n)
    X, Y, Z = cam.project(P)
    sig = rad * cam.f / Z * 0.6
    res = splat(w, h, X, Y, sig, (1.2 - 0.6 * s) * rad ** 0.3, extra=s)
    img += glow * vis
    if res is None:
        return
    x0, y0, D, S = res
    hh, ww = D.shape
    sm = S / (D + 1e-6)
    D *= 3.0 / (np.percentile(D[D > D.max() * 0.02], 85) + 1e-6)
    N = fbm(hh, ww, float(np.median(sig)) * 1.6, 4, 77)
    t = np.maximum(D * np.exp(0.6 * N) - 0.1, 0)
    a = (1 - np.exp(-t)) * vis[y0:y0 + hh, x0:x0 + ww, 0]
    under = np.array([1.0, 0.42, 0.12], np.float32) * np.exp(-sm / 0.3)[..., None]
    col = 0.3 * (np.array([0.16, 0.10, 0.07], np.float32) + under * 1.6) * np.exp(-0.25 * t)[..., None] + under * 0.15
    img[y0:y0 + hh, x0:x0 + ww] = img[y0:y0 + hh, x0:x0 + ww] * (1 - a[..., None]) + col * a[..., None]


def antennas(img, cam):
    """TV aerials and rails on the roofs, black against the cloud."""
    m = Image.new("L", (cam.w, cam.h))
    d = ImageDraw.Draw(m)
    k = cam.sc * 4
    rng = np.random.default_rng(12)
    for lo, hi, fl, sd in BLOCKS:
        top = hi[2]
        along_y = (hi[1] - lo[1]) > (hi[0] - lo[0])
        for _ in range(7):
            if along_y:
                p = np.array([rng.uniform(lo[0] + 2, hi[0] - 2), rng.uniform(lo[1] + 3, hi[1] - 3), top])
            else:
                p = np.array([rng.uniform(lo[0] + 3, hi[0] - 3), rng.uniform(lo[1] + 2, hi[1] - 2), top])
            mast = rng.uniform(2.5, 5.0)
            X, Y, Z = cam.project(np.stack([p, p + [0, 0, mast]]))
            width = max(1, int(round(0.12 * cam.f / Z[0])))
            d.line([(X[0], Y[0]), (X[1], Y[1])], fill=255, width=width)
            for hgt in (mast * 0.7, mast * 0.95):
                q = p + [0, 0, hgt]
                arm = np.array([1.2, 0, 0]) if rng.random() < 0.5 else np.array([0, 1.2, 0])
                X, Y, Z = cam.project(np.stack([q - arm, q + arm]))
                d.line([(X[0], Y[0]), (X[1], Y[1])], fill=255, width=max(1, width - 1))
    a = np.asarray(m, np.float32)[..., None] / 255
    img[:] = img * (1 - a) + np.array([0.01, 0.01, 0.012], np.float32) * a


def trees(img, cam):
    """Birches and poplars in the yard, dark against the far block, lamp-lit underneath."""
    rng = np.random.default_rng(21)
    k = cam.sc * 4
    for bx, by, hgt, cr in ((-36, 62, 15, 6.5), (-14, 70, 17, 7.0), (12, 66, 14, 6.0), (34, 74, 16, 6.5),
                           (-58, 80, 13, 6.0)):
        base = np.array([bx, by, 0.0])
        cen = base + [0, 0, hgt - cr]
        X, Y, Z = cam.project(np.stack([base, cen, cen + [0, 0, cr]]))
        cx, cy = float(X[1]), float(Y[1])
        r = abs(float(Y[2] - Y[1]))
        if r < 2:
            continue
        x0, y0 = int(cx - r * 1.4), int(cy - r * 1.4)
        size = int(r * 2.8)
        hh, ww = size, size
        yy, xx = np.mgrid[0:hh, 0:ww].astype(np.float32)
        dx, dy = (xx + x0 - cx) / r, (yy + y0 - cy) / (r * 1.15)
        N = fbm(hh, ww, r * 0.35, 4, int(rng.integers(1e6)))
        a = smooth((1 - (dx * dx + dy * dy) + 0.35 * N) / 0.25)
        tw = max(1, int(0.35 * cam.f / float(Z[0])))
        trunk = Image.new("L", (ww, hh))
        ImageDraw.Draw(trunk).line([(float(X[0]) - x0, float(Y[0]) - y0), (cx - x0, cy - y0)], fill=255, width=tw)
        a = np.maximum(a, np.asarray(trunk, np.float32) / 255)
        sx0, sy0 = max(0, x0), max(0, y0)
        sx1, sy1 = min(cam.w, x0 + ww), min(cam.h, y0 + hh)
        if sx1 <= sx0 or sy1 <= sy0:
            continue
        a = a[sy0 - y0:sy1 - y0, sx0 - x0:sx1 - x0]
        under = smooth(dy[sy0 - y0:sy1 - y0, sx0 - x0:sx1 - x0] * 0.9 + 0.2)
        col = np.array([0.008, 0.011, 0.008], np.float32) + SODIUM * 0.06 * under[..., None]
        img[sy0:sy1, sx0:sx1] = img[sy0:sy1, sx0:sx1] * (1 - a[..., None]) + col * a[..., None]


# --- the game's screen -----------------------------------------------------------------------

def font(size, weight):
    f = ImageFont.truetype(FONT, size)
    f.set_variation_by_name(weight)
    return f


def banner(w):
    """The game's alert header, as it shows mid-raid."""
    k = w / 630
    bw, bh = int(250 * k), int(52 * k)
    im = Image.new("RGBA", (bw, bh), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    red = (232, 92, 78, 255)
    d.rounded_rectangle([1, 1, bw - 2, bh - 2], radius=int(8 * k), fill=(22, 24, 30, 205), outline=red,
                        width=max(1, int(1.4 * k)))
    cx, cy, r = int(24 * k), bh // 2, int(10 * k)
    d.ellipse([cx - r, cy - r, cx + r, cy + r], outline=red, width=max(1, int(2 * k)))
    d.line([(cx, cy), (cx, cy - r * 0.6)], fill=red, width=max(1, int(2 * k)))
    d.line([(cx, cy), (cx + r * 0.5, cy + r * 0.2)], fill=red, width=max(1, int(2 * k)))
    d.text((int(44 * k), int(9 * k)), "Missile threat · 12 regions", font=font(int(15 * k), "SemiBold"), fill=red)
    d.text((int(44 * k), int(29 * k)), "Since 21:00 · 11 in the air", font=font(int(11.5 * k), "Medium"),
           fill=(200, 203, 210, 255))
    return im


def map_card(w):
    """A see-through piece of the game's map: the capital under missile alert, glowing over
    the scene like a display, its dark background falling away."""
    k = w / 630
    shot = Image.open(SHOT).convert("RGB").crop((260, 150, 1240, 900))
    cw = int(172 * k)
    chh = round(shot.height * cw / shot.width)
    shot = shot.resize((cw, chh), Image.LANCZOS)
    arr = np.asarray(shot, np.float32) / 255
    arr = np.clip(arr - 0.07, 0, 1) * 0.85          # the game's dark page drops to nothing
    yy, xx = np.mgrid[0:chh, 0:cw].astype(np.float32)
    edge = np.minimum(np.minimum(xx, cw - 1 - xx), np.minimum(yy, chh - 1 - yy)) / (14 * k)
    arr *= smooth(edge)[..., None]
    return arr


# --- finishing -----------------------------------------------------------------------------------

def finish(img):
    h, w = img.shape[:2]
    bright = np.maximum(img - 0.7, 0)
    img = img + blur(bright, w * 0.004) * 0.5 + blur(bright, w * 0.016) * 0.35 + blur(bright, w * 0.05) * 0.18
    knee = 0.6
    img = np.where(img < knee, img, knee + (1 - knee) * (1 - np.exp(-(img - knee) / (1 - knee))))
    lum = img @ np.array([0.3, 0.59, 0.11], np.float32)
    img = img + np.array([-0.004, 0.004, 0.012], np.float32) * (1 - smooth(lum / 0.2))[..., None]
    yy, xx = np.mgrid[0:h, 0:w].astype(np.float32)
    v = 1 - 0.5 * (((xx - w / 2) / (w * 0.7)) ** 2 + ((yy - h * 0.45) / (h * 0.8)) ** 2)
    img = img * np.clip(v, 0.4, 1)[..., None]
    # Darken the bottom for the title.
    g = smooth((yy / h - 0.72) / 0.25)
    img = img * (1 - 0.55 * g)[..., None]
    img = img * 255 + np.random.default_rng(5).normal(0, 1.8, (h, w))[..., None]
    return Image.fromarray(np.clip(img, 0, 255).astype(np.uint8))


def overlay(img):
    w, h = img.size
    out = img.convert("RGBA")
    b = banner(w)
    out.alpha_composite(b, ((w - b.width) // 2, int(h * 0.035)))
    m = map_card(w)
    mx, my = int(w * 0.965) - m.shape[1], int(h * 0.44)
    base = np.asarray(out, np.float32)[..., :3] / 255
    reg = base[my:my + m.shape[0], mx:mx + m.shape[1]]
    hh, ww = m.shape[:2]
    yy, xx = np.mgrid[0:hh, 0:ww].astype(np.float32)
    inner = smooth(np.minimum(np.minimum(xx, ww - 1 - xx), np.minimum(yy, hh - 1 - yy)) / (6 * w / 630))
    reg = reg * (1 - 0.72 * inner)[..., None] + np.array([0.03, 0.035, 0.05], np.float32) * inner[..., None]
    base[my:my + m.shape[0], mx:mx + m.shape[1]] = 1 - (1 - reg) * (1 - m)
    out = Image.fromarray((np.clip(base, 0, 1) * 255).astype(np.uint8)).convert("RGBA")
    d = ImageDraw.Draw(out)
    k = w / 630
    d.rounded_rectangle([mx - 2 * k, my - 2 * k, mx + m.shape[1] + 2 * k, my + m.shape[0] + 2 * k],
                        radius=int(9 * k), outline=(232, 92, 78, 150), width=max(1, int(1.2 * k)))
    lg = Image.open(LOGO).convert("RGBA")
    lw = int(w * 0.64)
    lg = lg.resize((lw, round(lg.height * lw / lg.width)), Image.LANCZOS)
    out.alpha_composite(lg, ((w - lw) // 2, int(h * 0.96) - lg.height))
    return out.convert("RGB")


def main():
    out = sys.argv[1]
    preview = "--preview" in sys.argv
    w, h = (1260, 1000) if preview else (2520, 2000)
    cam = Cam(w, h)
    img, depth = background(cam)
    fire_beyond(img, depth, cam)
    searchlight(img, depth, cam)
    rng = np.random.default_rng(4)
    for gun, aim in ((np.array([-23.5, 68.0, 46.6]), MISSILE + np.array([20.0, 6.0, 10.0])),
                     (np.array([19.5, 40.0, 46.6]), MISSILE + np.array([24.0, -3.0, 14.0]))):
        tracers(img, depth, cam, gun, aim, rng)
        gx, gy, _ = cam.project(gun[None])
        k = cam.sc * 4
        glow_dot(img, float(gx[0]), float(gy[0]), 2.5 * k, (3.0, 2.2, 1.2))
        glow_dot(img, float(gx[0]), float(gy[0]), 10 * k, (0.9, 0.45, 0.15))
        glow_dot(img, float(gx[0]), float(gy[0]), 34 * k, (0.15, 0.07, 0.02))
    antennas(img, cam)
    trees(img, cam)
    missile(img, cam)
    img = overlay(finish(img))
    if preview:
        img.save(os.path.join(out, "night-preview.png"))
    else:
        img.resize((1260, 1000), Image.LANCZOS).save(os.path.join(out, "cover-night-1260.png"))
        img.resize((630, 500), Image.LANCZOS).save(os.path.join(out, "cover-night.png"))
    print("wrote", out)


if __name__ == "__main__":
    main()
