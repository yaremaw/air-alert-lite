"""A 5-second end card for the Strike Alert videos, in 16:9 and 9:16.

A night city with a burning factory (itch/outro/background.jpg). An air raid siren, searchlights, gun tracers. One
twelve-dollar drone comes up out of the fire and flies at the camera. Time slows, the HUD
finds its target (TARGET: YOU), the drone fills the frame and the picture dies like an old
TV. Then a flash: the HUD's reticle flies into the logo, "PLAY FREE IN YOUR BROWSER", a
PLAY NOW button that a cursor clicks, and the itch.io address.

    python tools/outro_video.py itch/outro
    python tools/outro_video.py itch/outro --still 2,4.6,5.6,6.3,7.4,10.4

writes strike-alert-outro-16x9.mp4, strike-alert-outro-9x16.mp4 and strike-alert-outro.wav;
--still writes PNG frames at those seconds instead (both formats), to check the look fast.
The drone is a small 3D model drawn here with numpy and PIL; the sound uses the game's own
siren, drone and gun samples. Needs ffmpeg (pip install imageio-ffmpeg).
"""
import math
import os
import subprocess
import sys
import tempfile
import wave
from multiprocessing import Pool

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import voiceover_video as vv  # noqa: E402
from voiceover_video import (FF, FPS, SR, RED, TEXT, MUTED, font, mono, smooth, boom, braam,  # noqa: E402
                             whoosh, static, pad, lowpass, click_sample, write_wav, encoder)

ROOT = vv.ROOT
COVER = os.path.join(ROOT, "itch", "outro", "background.jpg")
ICON = os.path.join(ROOT, "itch", "logo-v2-icon.png")
LOGO = os.path.join(ROOT, "itch", "logo-v2.png")
AUDIO = os.path.join(ROOT, "assets", "audio")
URL = "tenchery.itch.io/strike-alert"
FORMATS = {"16x9": (1920, 1080), "9x16": (1080, 1920)}

# The story, in seconds.
T_HUD = 0.2       # the static clears, the camera's HUD comes up
T_EMERGE = 0.25   # the drone comes up out of the fire
T_LOCK = 1.15     # the searchlights find it
T_SLOW = 1.6      # slow motion
T_YOU = 1.95      # TARGET: YOU
T_RUSH = 2.2      # it lunges at the lens
T_CUT = 2.5       # the picture dies
T_FLASH = 2.58    # white, and the reticle flies into the logo
T_TEXT = 2.85     # STRIKE ALERT slams in
T_TAG = 3.1       # PLAY FREE IN YOUR BROWSER, typed
T_BTN = 3.45      # the PLAY NOW button
T_URL = 3.6
T_CLICK = 4.3     # a cursor clicks it
T_END = 5.0
FRAMES = int(round(T_END * FPS))

Z0 = 260.0                 # metres away when it appears
ANCHOR = (1080.0, 640.0)   # where it comes from, in the background: out of the smoke over the factory
GUNS = ((0, 0.55, 1.0), (1, 0.75, 1.25), (0, 1.1, 1.55), (1, 1.3, 1.6))   # gun, first and last second
BLASTS = (((560, 1180), 0.35, -0.5), ((1450, 1150), 0.9, 0.5))           # far away: where, when, pan
SLOWMO = 0.22


def clamp01(x):
    return min(max(x, 0.0), 1.0)


def ease_out(x):
    x = clamp01(x)
    return 1 - (1 - x) ** 3


def ease_back(x, k=1.9):
    x = clamp01(x) - 1
    return 1 + (k + 1) * x ** 3 + k * x ** 2


def tau(t):
    """Scene time: it runs at a fifth of the speed in the slow motion."""
    if t < T_SLOW:
        return t
    if t < T_RUSH:
        return T_SLOW + (t - T_SLOW) * SLOWMO
    return T_SLOW + (T_RUSH - T_SLOW) * SLOWMO + (t - T_RUSH)


def drone_z(t):
    """Distance from the lens: fast over the city, almost floating in the slow motion, then a lunge."""
    if t < T_SLOW:
        p = (t - T_EMERGE) / (T_SLOW - T_EMERGE)
        return Z0 + (14.0 - Z0) * p
    if t < T_RUSH:
        p = (t - T_SLOW) / (T_RUSH - T_SLOW)
        return 14.0 - 9.5 * (0.85 * (1 - (1 - p) ** 3) + 0.15 * p)
    p = (t - T_RUSH) / (T_CUT - T_RUSH)
    return 4.5 - 2.9 * (0.15 * p + 0.85 * p * p)


def lock_amount(t):
    return smooth((t - T_LOCK) / 0.35)


def shake_amp(t):
    a = 2.2
    if GUNS[0][1] < t < T_SLOW:
        a += 3.0
    if T_SLOW <= t < T_RUSH:
        a *= 0.35
    if T_RUSH <= t < T_CUT:
        a += 24 * smooth((t - T_RUSH) / (T_CUT - T_RUSH))
    if t >= T_FLASH:
        a = 36 * math.exp(-(t - T_FLASH) * 5) + 1.0
        if t >= T_TEXT:
            a += 10 * math.exp(-(t - T_TEXT) * 9)
        if t >= T_CLICK:
            a += 3 * math.exp(-(t - T_CLICK) * 10)
    return a


def shake(t):
    a = shake_amp(t)
    dx = math.sin(t * 7.3 + 1.1) * 0.5 + math.sin(t * 13.7 + 0.3) * 0.3 + math.sin(t * 23.1 + 2.0) * 0.2
    dy = math.sin(t * 8.9 + 2.3) * 0.5 + math.sin(t * 15.3 + 1.7) * 0.3 + math.sin(t * 27.7 + 0.9) * 0.2
    return dx * a, dy * a


# ---------------------------------------------------------------- the drone

def drone_mesh():
    """A delta-wing drone, 3.5 m long and 2.5 m across: nose at +z, up at +y, right at +x.
    Faces: (points, outward normal, colour, see-through)."""
    faces = []

    def add(pts, n, col, glass=False):
        n = np.array(n, float)
        faces.append((np.array(pts, float), n / np.linalg.norm(n), np.array(col, float), glass))

    body, wing, fin, nose = (58, 60, 56), (50, 52, 48), (44, 46, 42), (74, 74, 70)
    rings = [(1.75, 0.0), (1.48, 0.12), (1.1, 0.19), (0.3, 0.19), (-0.5, 0.19), (-1.38, 0.19), (-1.62, 0.12)]
    seg = 12
    for (z1, r1), (z2, r2) in zip(rings, rings[1:]):
        for k in range(seg):
            a0, a1 = 2 * math.pi * k / seg, 2 * math.pi * (k + 1) / seg
            am = (a0 + a1) / 2
            pts = [(r1 * math.cos(a0), r1 * math.sin(a0), z1), (r1 * math.cos(a1), r1 * math.sin(a1), z1),
                   (r2 * math.cos(a1), r2 * math.sin(a1), z2), (r2 * math.cos(a0), r2 * math.sin(a0), z2)]
            add(pts, (math.cos(am), math.sin(am), -(r2 - r1) / (z2 - z1)), nose if z1 > 1.2 else body)
    z, r = rings[-1]
    add([(r * math.cos(a), r * math.sin(a), z) for a in np.linspace(0, 2 * math.pi, seg, endpoint=False)],
        (0, 0, -1), body)
    th = 0.035
    plan = [(0.17, 0.55), (1.22, -1.15), (1.22, -1.52), (0.17, -1.52)]
    for s in (1, -1):
        add([(s * x, th, z) for x, z in plan], (0, 1, 0), wing)
        add([(s * x, -th, z) for x, z in plan], (0, -1, 0), wing)
        add([(s * 0.17, th, 0.55), (s * 1.22, th, -1.15), (s * 1.22, -th, -1.15), (s * 0.17, -th, 0.55)],
            (s * 1.70, 0, 1.05), wing)
        add([(s * 1.22, th, -1.15), (s * 1.22, th, -1.52), (s * 1.22, -th, -1.52), (s * 1.22, -th, -1.15)],
            (s, 0, 0), wing)
        add([(s * 0.17, th, -1.52), (s * 1.22, th, -1.52), (s * 1.22, -th, -1.52), (s * 0.17, -th, -1.52)],
            (0, 0, -1), wing)
        f = [(s * 1.235, -0.18, -1.18), (s * 1.235, 0.30, -1.30), (s * 1.235, 0.30, -1.55), (s * 1.235, -0.18, -1.55)]
        add(f, (1, 0, 0), fin)
        add(f, (-1, 0, 0), fin)
    add([(0.42 * math.cos(a), 0.42 * math.sin(a), -1.70) for a in np.linspace(0, 2 * math.pi, 24, endpoint=False)],
        (0, 0, 1), (34, 34, 34), glass=True)   # the propeller, a blur
    return faces


def orient(C, pitch, roll):
    """Nose at the lens, then pitched up (showing the belly) and rolled."""
    fwd = -C / np.linalg.norm(C)
    right = np.cross(np.array([0.0, 1.0, 0.0]), fwd)
    right /= np.linalg.norm(right)
    up = np.cross(fwd, right)
    B = np.stack([right, up, fwd], axis=1)
    cp, sp = math.cos(-pitch), math.sin(-pitch)
    Rx = np.array([[1, 0, 0], [0, cp, -sp], [0, sp, cp]])
    cr, sr = math.cos(roll), math.sin(roll)
    Rz = np.array([[cr, -sr, 0], [sr, cr, 0], [0, 0, 1]])
    return B @ Rx @ Rz


# Lights, in camera space (x right, y up, z into the screen), as (direction to the light, colour).
AMBIENT = np.array([0.10, 0.11, 0.17])
MOON = (np.array([-0.5, 0.8, -0.3]), np.array([0.50, 0.58, 0.82]))
CITY = (np.array([0.0, -1.0, 0.25]), np.array([0.95, 0.45, 0.22]))
SEARCH = (np.array([0.15, -0.75, -0.65]), np.array([0.85, 0.92, 1.05]))
for _d, _c in (MOON, CITY, SEARCH):
    _d /= np.linalg.norm(_d)
RIM = np.array([255.0, 150.0, 70.0])
GLOW = np.array([255.0, 110.0, 45.0])


# ---------------------------------------------------------------- one format

def ring_and_drone(icon):
    """The logo's reticle split in two: the red ring, and the white drone inside it."""
    a = np.asarray(icon.convert("RGBA")).copy()
    red = (a[:, :, 0] > 150) & (a[:, :, 1] < 140)
    ring, sil = a.copy(), a.copy()
    ring[~red, 3] = 0
    sil[red, 3] = 0
    return Image.fromarray(ring), Image.fromarray(sil)


def composite(dst, spr, x, y):
    """alpha_composite that allows the sprite to hang off the edges."""
    l, t = max(0, -x), max(0, -y)
    r, b = min(spr.width, dst.width - x), min(spr.height, dst.height - y)
    if r > l and b > t:
        dst.alpha_composite(spr.crop((l, t, r, b)), (x + l, y + t))


class Scene:
    def __init__(self, fmt):
        self.fmt = fmt
        self.W, self.H = W, H = FORMATS[fmt]
        self.m = min(W, H)
        self.u = self.m / 1080
        self.f = 1.1 * self.m
        vv.W, vv.H = W, H
        self.look = vv.Look(77)
        self.mesh = drone_mesh()
        cover = Image.open(COVER).convert("RGB")
        self.cw0, self.ch0 = cover.size
        self.up = 2 if self.cw0 < 1600 else 1   # sample a small picture from a 2x copy
        self.cover2 = cover.resize((self.cw0 * self.up, self.ch0 * self.up), Image.LANCZOS)
        cw0, ch0 = self.cw0, self.ch0
        if fmt == "16x9":   # (t, centre x, centre y, crop height) in background pixels
            full = cw0 * 9 / 16
            self.keys = [(0.0, cw0 / 2, 0.50 * ch0, full), (T_SLOW, 0.51 * cw0, 0.55 * ch0, 0.54 * ch0),
                         (T_CUT, 0.51 * cw0, 0.51 * ch0, 0.47 * ch0)]
        else:
            self.keys = [(0.0, cw0 / 2, 0.50 * ch0, ch0), (T_SLOW, 0.51 * cw0, 0.54 * ch0, 0.77 * ch0),
                         (T_CUT, 0.51 * cw0, 0.51 * ch0, 0.67 * ch0)]
        # Quarter-size grids for the light effects.
        self.Wq, self.Hq = W // 4, H // 4
        ys, xs = np.mgrid[0:self.Hq, 0:self.Wq].astype(np.float32)
        self.xs, self.ys = xs, ys
        self.lights = [(0.17 * W, 1.04 * H), (0.86 * W, 1.04 * H)]
        self.beam_fields = []
        for sx, sy in self.lights:
            dx, dy = xs - sx / 4, sy / 4 - ys
            self.beam_fields.append((np.arctan2(dx, dy), np.hypot(dx, dy)))
        r = np.hypot((xs - self.Wq / 2) / (self.Wq / 2), (ys - self.Hq / 2) / (self.Hq / 2))
        self.edge = np.clip(r - 0.55, 0, None) ** 1.5
        self.guns = [(0.03 * W, 1.03 * H), (0.97 * W, 1.03 * H)]
        rng = np.random.default_rng(3)
        self.rounds = []
        for g, a, b in GUNS:
            for k in range(int((b - a) * 11)):
                self.rounds.append((g, a + k / 11 + rng.uniform(0, 0.03), rng.normal(0, 0.08, 2), rng.uniform(0.85, 1.2)))
        self.embers = rng.uniform(0, 1, (120, 5))
        self.static = [rng.integers(0, 255, (self.Hq, self.Wq), dtype=np.uint8) for _ in range(6)]
        # The end card.
        self.ring, self.sil = ring_and_drone(Image.open(ICON))
        logo = Image.open(LOGO).convert("RGBA")
        lw = (0.6 if fmt == "16x9" else 0.88) * W
        s = lw / logo.width
        self.logo_c = (W / 2, (0.34 if fmt == "16x9" else 0.36) * H)
        lx0 = W / 2 - lw / 2
        ly0 = self.logo_c[1] - logo.height * s / 2
        self.icon_c = (lx0 + 180 * s, ly0 + 180 * s)
        self.icon_size = 512 * (302 / 455) * s
        txt = logo.crop((380, 0, logo.width, logo.height))
        self.text = txt.resize((int(txt.width * s), int(txt.height * s)), Image.LANCZOS)
        self.text_c = (lx0 + 380 * s + self.text.width / 2, ly0 + self.text.height / 2)
        self.ring_end = self.ring.resize((int(self.icon_size), int(self.icon_size)), Image.LANCZOS)
        self.sil_end = self.sil.resize((int(self.icon_size), int(self.icon_size)), Image.LANCZOS)
        self.ring_glow = self.ring_end.getchannel("A").filter(ImageFilter.GaussianBlur(18 * self.u))
        self.make_card()
        self.make_end_bg()

    # ---- the camera on the cover art
    def view(self, t):
        """(x0, y0, scale) of the frame in cover pixels, shake included."""
        keys = self.keys
        t = min(max(t, keys[0][0]), keys[-1][0])
        for (ta, *a), (tb, *b) in zip(keys, keys[1:]):
            if t <= tb:
                p = smooth((t - ta) / (tb - ta))
                cx, cy, ch = (a[i] + (b[i] - a[i]) * p for i in range(3))
                break
        k = self.H / ch
        cw = self.W / k
        dx, dy = shake(t)
        x0 = min(max(cx - cw / 2 + dx / k, 0), self.cw0 - cw)
        y0 = min(max(cy - ch / 2 + dy / k, 0), self.ch0 - ch)
        return x0, y0, k

    def to_screen(self, p, t):
        x0, y0, k = self.view(t)
        return (p[0] - x0) * k, (p[1] - y0) * k

    def backdrop(self, t):
        x0, y0, k = self.view(t)
        u2 = self.up
        box = (u2 * x0, u2 * y0, u2 * (x0 + self.W / k), u2 * (y0 + self.H / k))
        return self.cover2.transform((self.W, self.H), Image.EXTENT, box, Image.BICUBIC)

    # ---- the drone
    def drone(self, t):
        if t < T_EMERGE or t >= T_CUT:
            return None
        z = drone_z(t)
        ax, ay = self.to_screen(ANCHOR, t)
        dx, dy = shake(t)
        w = 1 - (z / Z0) ** 0.6
        ta = tau(t)
        amp = 0.04 * self.m * (1 - smooth((t - T_SLOW) / 0.8))
        sx = ax * (1 - w) + (self.W / 2 + dx) * w + amp * math.sin(1.7 * ta) * w
        sy = ay * (1 - w) + (0.45 * self.H + dy) * w + 0.35 * amp * math.sin(2.3 * ta + 1) * w
        C = np.array([(sx - self.W / 2) * z / self.f, -(sy - self.H / 2) * z / self.f, z])
        pitch = math.radians(5 + 14 * (1 - min(1.0, z / 30)))
        roll = math.radians(16 * math.cos(1.7 * ta) * (1 - smooth((t - T_SLOW) / 0.8))
                            - 14 * smooth((t - T_SLOW) / 1.0))
        return dict(z=z, C=C, sx=sx, sy=sy, R=orient(C, pitch, roll), span=self.f * 2.5 / z,
                    vis=smooth((t - T_EMERGE) / 0.35))

    def draw_drone(self, st, lit, acc, weight):
        """Draws the drone into the accumulators (colour, cover, glow), weighted for motion blur."""
        W, H, f, R, C = self.W, self.H, self.f, st["R"], st["C"]
        lights = [MOON, CITY, (SEARCH[0], SEARCH[1] * lit)]
        polys = []
        for pts, n, col, glass in self.mesh:
            P = C + pts @ R.T
            if P[:, 2].min() < 0.12:
                continue
            nc = R @ n
            cen = P.mean(axis=0)
            if not glass and nc @ cen >= 0:
                continue
            light = AMBIENT.copy()
            for d, c in lights:
                light += max(0.0, float(nc @ d)) * c
            rgb = col * light if not glass else col
            scr = np.stack([W / 2 + f * P[:, 0] / P[:, 2], H / 2 - f * P[:, 1] / P[:, 2]], axis=1)
            polys.append((1e9 if glass else cen[2], scr, np.clip(rgb, 0, 255), glass))
        if not polys:
            return
        polys.sort(key=lambda p: -p[0])
        allp = np.concatenate([p[1] for p in polys])
        span = st["span"]
        rg = 2 + span * 0.012
        pad = int(rg * 3) + 3
        x0, y0 = max(0, int(allp[:, 0].min()) - pad), max(0, int(allp[:, 1].min()) - pad)
        x1, y1 = min(W, int(allp[:, 0].max()) + pad + 1), min(H, int(allp[:, 1].max()) + pad + 1)
        if x1 - x0 < 2 or y1 - y0 < 2:
            return
        ss = 3 if span < 150 else 2 if span < 900 else 1
        size = ((x1 - x0) * ss, (y1 - y0) * ss)
        img, msk = Image.new("RGB", size), Image.new("L", size)
        di, dm = ImageDraw.Draw(img), ImageDraw.Draw(msk)
        for _, scr, rgb, glass in polys:
            pts = [((x - x0) * ss, (y - y0) * ss) for x, y in scr]
            if glass:
                di.polygon(pts, fill=tuple(int(v * 0.35) for v in rgb))
                dm.polygon(pts, fill=90)
            else:
                di.polygon(pts, fill=tuple(int(v) for v in rgb))
                dm.polygon(pts, fill=255)
        if ss > 1:
            img = img.resize((x1 - x0, y1 - y0), Image.BOX)
            msk = msk.resize((x1 - x0, y1 - y0), Image.BOX)
        rgb = np.asarray(img, np.float32)
        m = np.asarray(msk, np.float32) / 255
        k = max(1, int(span * 0.012))
        below = np.zeros_like(m)
        below[:-k] = m[k:]
        rim = m * (1 - below)              # the lower edges glow with the fire, like the cover art
        rgb = rgb + rim[..., None] * RIM * 0.9
        g = np.asarray(msk.filter(ImageFilter.GaussianBlur(rg)), np.float32) / 255
        glow = (g * (1 - m))[..., None] * GLOW * 0.5
        acc[0][y0:y1, x0:x1] += rgb * weight
        acc[1][y0:y1, x0:x1] += m * weight
        acc[2][y0:y1, x0:x1] += glow * weight

    def strobe(self, st, t):
        """The red light under the belly: a double blink."""
        p = st["C"] + st["R"] @ np.array([0.0, -0.21, 0.45])
        if p[2] < 0.2:
            return None
        ph = tau(t) % 1.1
        on = 1.0 if ph < 0.05 or 0.16 < ph < 0.21 else 0.12
        return self.W / 2 + self.f * p[0] / p[2], self.H / 2 - self.f * p[1] / p[2], on

    # ---- the reticle on the drone
    def reticle(self, t):
        if t < T_EMERGE + 0.25 or t >= T_CUT:
            return None
        st = self.drone(max(T_EMERGE + 0.01, t - 0.07))
        size = min(max(st["span"] * 1.9, 0.12 * self.m), 0.62 * self.m)
        j = (1 - lock_amount(t)) * 7 * self.u
        x = st["sx"] + j * math.sin(t * 31.0)
        y = st["sy"] + j * math.cos(t * 27.0)
        rot = 90 * (1 - ease_out((t - T_EMERGE - 0.25) / 0.8))
        return x, y, size, rot

    # ---- light effects at quarter size
    def glow_at(self, q, x, y, radius, col, amount):
        d2 = ((self.xs - x / 4) ** 2 + (self.ys - y / 4) ** 2) / max(radius / 4, 1) ** 2
        q += np.exp(-d2)[..., None] * (np.array(col, np.float32) * amount)

    def beams(self, t, q, st):
        ta = tau(t)
        lk = lock_amount(t)
        for i, ((theta, dist), (lx, ly)) in enumerate(zip(self.beam_fields, self.lights)):
            start = 0.05 + 0.2 * i
            on = clamp01((t - start) / 0.15)
            if on <= 0:
                continue
            if t - start < 0.2 and int(t * 30) % 3 == 0:   # it flickers on
                on *= 0.3
            free = (-0.28 + 0.34 * math.sin(0.8 * ta + 0.3)) if i == 0 else (0.22 + 0.3 * math.sin(0.65 * ta + 2.0))
            a = free
            if st is not None and lk > 0:
                a = free * (1 - lk) + math.atan2(st["sx"] - lx, ly - st["sy"]) * lk
            d = theta - a
            fall = np.exp(-dist / (0.85 * self.Hq)) * 0.85 + 0.15
            beam = (np.exp(-(d / 0.028) ** 2) + 0.16 * np.exp(-(d / 0.10) ** 2)) * fall * on
            q += beam[..., None] * np.array([105, 120, 160], np.float32)

    def effects(self, t, st):
        """Additive light: beams, distant blasts, gun flashes; plus tracers and embers drawn sharp."""
        q = np.zeros((self.Hq, self.Wq, 3), np.float32)
        add = Image.new("RGB", (self.W, self.H))
        d = ImageDraw.Draw(add)
        self.beams(t, q, st)
        for (px, py), at, _ in BLASTS:
            e = t - at
            if 0 <= e < 1.5:
                x, y = self.to_screen((px, py), t)
                self.glow_at(q, x, y, 150 * self.u, (255, 140, 60), 1.6 * math.exp(-e * 3.5))
        ta = tau(t)
        for g, at, miss, spd in self.rounds:
            age = ta - at
            if not 0 <= age < 0.9:
                continue
            ox, oy = self.guns[g]
            aim = self.drone(min(max(at + 0.3, T_EMERGE + 0.01), T_SLOW - 0.01))
            ax = aim["sx"] + miss[0] * self.m
            ay = aim["sy"] + miss[1] * self.m - 0.12 * self.m
            vx, vy = (ax - ox) / 0.45 * spd, (ay - oy) / 0.45 * spd
            x, y = ox + vx * age, oy + vy * age
            b = (1 - age / 0.9) ** 0.7
            col = (int(255 * b), int(205 * b), int(120 * b))
            d.line([(x, y), (x - vx * 0.04, y - vy * 0.04)], fill=col, width=max(2, int(3 * self.u)))
        for g, a, b in GUNS:
            if a <= ta < b and int(ta * 22) % 2 == 0:
                self.glow_at(q, *self.guns[g], 260 * self.u, (255, 170, 80), 0.9)
        if st is not None:
            lk = lock_amount(t) * st["vis"]
            if lk > 0:
                self.glow_at(q, st["sx"], st["sy"], max(st["span"] * 0.9, 40), (150, 165, 210), 0.5 * lk)
            sb = self.strobe(st, t)
            if sb:
                r = (2.0 + st["span"] * 0.006) * sb[2]
                d.ellipse([sb[0] - r, sb[1] - r, sb[0] + r, sb[1] + r], fill=(255, int(70 + 120 * sb[2]), 60))
                self.glow_at(q, sb[0], sb[1], 18 + st["span"] * 0.05, (255, 40, 30), 0.8 * sb[2] * st["vis"])
        self.draw_embers(d, t, 70)
        qa = add.resize((self.Wq, self.Hq), Image.BILINEAR).filter(ImageFilter.GaussianBlur(2.2))
        q += np.asarray(qa, np.float32) * 2.2
        up = Image.fromarray(np.clip(q, 0, 255).astype(np.uint8)).resize((self.W, self.H), Image.BILINEAR)
        return np.asarray(up, np.float32) + np.asarray(add, np.float32)

    def draw_embers(self, d, t, n):
        ta = tau(t)
        W, H = self.W, self.H
        for x0, sp, ph, sz, fl in self.embers[:n]:
            v = (0.05 + 0.10 * sp) * H
            y = H * 1.05 - ((ta * v + ph * H * 1.3) % (H * 1.3))
            x = x0 * W + 0.03 * W * math.sin(ta * (0.6 + sp) + ph * 9)
            b = 0.45 + 0.55 * abs(math.sin(ta * (3 + 5 * fl) + ph * 20))
            r = (1.0 + 2.2 * sz) * self.u
            d.ellipse([x - r, y - r, x + r, y + r], fill=(int(255 * b), int(120 * b), int(40 * b)))

    # ---- the HUD
    def hud(self, t, st):
        W, H, u = self.W, self.H, self.u
        ov = Image.new("RGBA", (W, H))
        d = ImageDraw.Draw(ov)
        if t < T_HUD + 0.15 and int(t * 30) % 2 == 0:
            return ov
        m = int(40 * u)
        L = int(70 * u)
        lw = max(2, int(4 * u))
        for cx, cy, sx, sy in ((m, m, 1, 1), (W - m, m, -1, 1), (m, H - m, 1, -1), (W - m, H - m, -1, -1)):
            d.line([(cx, cy + sy * L), (cx, cy), (cx + sx * L, cy)], fill=(255, 255, 255, 170), width=lw)
        f = mono(int(30 * u))
        x, y = m + int(26 * u), m + int(22 * u)
        if int(t * 2) % 2 == 0:
            r = 10 * u
            d.ellipse([x, y + 6 * u, x + 2 * r, y + 6 * u + 2 * r], fill=RED + (255,))
        d.text((x + 30 * u, y), "REC", font=f, fill=(255, 255, 255, 230))
        tc = 14 * FPS + int(t * FPS)
        d.text((x + 110 * u, y), "03:00:%02d:%02d" % (tc // FPS, tc % FPS), font=f, fill=(255, 255, 255, 200))
        d.text((x, y + 44 * u), "CAM 2  ROOFTOP", font=mono(int(22 * u)), fill=(255, 255, 255, 130))
        label = "AIR RAID ALERT"
        tw = f.getlength(label)
        bx1, by0 = W - m - int(26 * u), m + int(18 * u)
        on = (t * 1.4) % 1 < 0.7
        d.rectangle([bx1 - tw - 28 * u, by0, bx1, by0 + 46 * u], fill=RED + ((255,) if on else (70,)))
        d.text((bx1 - tw - 14 * u, by0 + 7 * u), label, font=f, fill=(255, 255, 255, 255 if on else 140))
        ret = self.reticle(t)
        if ret:
            rx, ry, rs, rot = ret
            a = 0.9 if t > T_EMERGE + 0.45 or int(t * 30) % 2 else 0.3
            spr = self.ring.resize((int(rs), int(rs)), Image.BICUBIC).rotate(rot, Image.BICUBIC)
            if a < 1:
                spr.putalpha(spr.getchannel("A").point(lambda v: int(v * a)))
            ov.alpha_composite(spr, (int(rx - rs / 2), int(ry - rs / 2))) if rx - rs / 2 >= 0 and ry - rs / 2 >= 0 \
                else ov.paste(spr, (int(rx - rs / 2), int(ry - rs / 2)), spr)
            if t < T_SLOW and st is not None:
                fl = mono(int(26 * u))
                lines = [("DRONE  $12", (255, 255, 255, 235)),
                         ("RANGE  %.2f KM" % (st["z"] * 0.009), (255, 255, 255, 200)),
                         ("SPEED  185 KM/H", (255, 255, 255, 200))]
                if t > T_LOCK + 0.2:
                    lines.append(("TRACKED", RED + (255,)))
                lwid = max(fl.getlength(s) for s, _ in lines)
                lx = rx + rs * 0.45 + 14 * u
                if lx + lwid > W - m:
                    lx = rx - rs * 0.45 - 14 * u - lwid
                ly = ry - rs * 0.32
                for s, c in lines:
                    d.text((lx, ly), s, font=fl, fill=c)
                    ly += 34 * u
        if t >= T_YOU - 0.5:
            self.target_you(d, t)
        return ov

    def target_you(self, d, t):
        u = self.u
        fb = font(int(86 * u), "Black")
        a, b = "TARGET: ", "YOU"
        wa, wb = fb.getlength(a), fb.getlength("YOU")
        x = self.W / 2 - (wa + wb) / 2
        y = self.H * (0.80 if self.fmt == "16x9" else 0.70)
        n = int(len(a) * clamp01((t - (T_YOU - 0.5)) / 0.25))
        d.rectangle([x - 26 * u, y - 18 * u, x + wa + wb + 26 * u, y + 108 * u], fill=(10, 4, 4, 150))
        d.text((x, y), a[:n], font=fb, fill=(255, 255, 255, 255))
        if t >= T_YOU - 0.25:
            if t < T_YOU:
                rng = np.random.default_rng(int(t * FPS))
                word = "".join(rng.choice(list("ABCDEFGHKMNPRSTUVWXZ0123456789#%&"), 3))
                d.text((x + wa, y), word, font=fb, fill=(255, 255, 255, 170))
            else:
                d.text((x + wa, y), b, font=fb, fill=RED + (255,))

    # ---- the end card
    def make_card(self):
        W, H, u, v = self.W, self.H, self.u, self.fmt == "16x9"
        size = int((60 if v else 52) * u)
        words = [("PLAY ", TEXT), ("FREE", RED), (" IN YOUR BROWSER", TEXT)]
        while True:
            fb = font(size, "Black")
            sp = 0.06 * size
            chars = [(ch, c) for w, c in words for ch in w]
            width = sum(fb.getlength(ch) + sp for ch, _ in chars) - sp
            if width < 0.9 * W:
                break
            size -= 2
        self.tag = Image.new("RGBA", (int(width) + 4, int(size * 1.3)))
        d = ImageDraw.Draw(self.tag)
        x, self.tag_edges = 0.0, []
        for ch, c in chars:
            d.text((x, 0), ch, font=fb, fill=c + (255,))
            x += fb.getlength(ch) + sp
            self.tag_edges.append(x)
        logo_h = self.text.height
        self.tag_c = (W / 2, self.logo_c[1] + logo_h / 2 + (78 if v else 70) * u)
        bw, bh = int((440 if v else 500) * u), int((108 if v else 124) * u)
        self.btn = Image.new("RGBA", (bw, bh))
        d = ImageDraw.Draw(self.btn)
        d.rounded_rectangle([0, 0, bw - 1, bh - 1], radius=bh // 2, fill=RED + (255,))
        fbtn = font(int(bh * 0.40), "Black")
        label = "PLAY NOW"
        lw = fbtn.getlength(label)
        tri = bh * 0.30
        x0 = bw / 2 - (lw + tri + bh * 0.16) / 2
        cy = bh / 2
        d.polygon([(x0, cy - tri / 2), (x0, cy + tri / 2), (x0 + tri * 0.87, cy)], fill=(255, 255, 255, 255))
        d.text((x0 + tri + bh * 0.16, cy), label, font=fbtn, fill=(255, 255, 255, 255), anchor="lm")
        self.btn_white = Image.new("RGBA", (bw, bh))
        ImageDraw.Draw(self.btn_white).rounded_rectangle([0, 0, bw - 1, bh - 1], radius=bh // 2, fill=(255, 255, 255, 255))
        gl = Image.new("L", (bw + int(120 * u), bh + int(120 * u)))
        ImageDraw.Draw(gl).rounded_rectangle([60 * u, 60 * u, 60 * u + bw, 60 * u + bh], radius=bh // 2, fill=255)
        self.btn_glow = gl.filter(ImageFilter.GaussianBlur(26 * u))
        self.btn_c = (W / 2, (0.66 if v else 0.53) * H)
        fu = mono(int(42 * u))
        self.url = Image.new("RGBA", (int(fu.getlength(URL)) + 4, int(56 * u)))
        ImageDraw.Draw(self.url).text((0, 0), URL, font=fu, fill=TEXT + (255,))
        self.url_c = (W / 2, (0.80 if v else 0.615) * H)
        fs = font(int(30 * u), "Medium")
        sub = "No download. No sign-up."
        self.sub = Image.new("RGBA", (int(fs.getlength(sub)) + 4, int(44 * u)))
        ImageDraw.Draw(self.sub).text((0, 0), sub, font=fs, fill=MUTED + (255,))
        self.sub_c = (W / 2, self.url_c[1] + 58 * u)
        s = 1.6 * u
        pts = [(0, 0), (0, 34), (9, 26), (15, 40), (21, 37), (15, 24), (26, 24)]
        self.cursor = Image.new("RGBA", (int(34 * s), int(46 * s)))
        ImageDraw.Draw(self.cursor).polygon([(2 + x * s, 2 + y * s) for x, y in pts], fill=(255, 255, 255, 255),
                                            outline=(0, 0, 0, 255), width=max(2, int(2 * u)))

    def make_end_bg(self):
        """The city behind the logo: blurred, darker, redder, a little larger to zoom out of."""
        W, H = self.W, self.H
        ch = 0.67 * self.ch0 if self.fmt == "16x9" else self.ch0
        cw = ch * W / H
        cx, cy = self.cw0 / 2, 0.57 * self.ch0 if self.fmt == "16x9" else self.ch0 / 2
        u2 = self.up
        box = (u2 * (cx - cw / 2), u2 * (cy - ch / 2), u2 * (cx + cw / 2), u2 * (cy + ch / 2))
        big = (int(W * 1.12), int(H * 1.12))
        im = self.cover2.transform(big, Image.EXTENT, box, Image.BICUBIC).filter(ImageFilter.GaussianBlur(14 * self.u))
        a = np.asarray(im, np.float32) * np.array([0.50, 0.30, 0.30], np.float32)
        self.end_bg = Image.fromarray(np.clip(a, 0, 255).astype(np.uint8))

    def paste(self, img, spr, c, scale=1.0, alpha=1.0, rot=0.0, mask=None):
        if alpha <= 0.004 or scale <= 0.01:
            return
        s = spr
        if abs(scale - 1) > 1e-3:
            s = s.resize((max(1, int(s.width * scale)), max(1, int(s.height * scale))), Image.BICUBIC)
        if rot:
            s = s.rotate(rot, Image.BICUBIC, expand=True)
        a = s.getchannel("A") if mask is None else mask
        if alpha < 1:
            a = a.point(lambda v: int(v * alpha))
        img.paste(s.convert("RGB") if mask is None else s, (int(round(c[0] - s.width / 2)), int(round(c[1] - s.height / 2))), a)

    def end_card(self, t):
        W, H, u = self.W, self.H, self.u
        e = t - T_FLASH
        dx, dy = shake(t)
        z = 1.0 + 0.10 * (1 - ease_out(e / 2.4))
        bw, bh = self.end_bg.size
        vw, vh = W * z, H * z
        cx, cy = bw / 2 + dx, bh / 2 + dy
        bg = self.end_bg.transform((W, H), Image.EXTENT, (cx - vw / 2, cy - vh / 2, cx + vw / 2, cy + vh / 2),
                                   Image.BILINEAR)
        F = np.asarray(bg, np.float32).copy()
        add = Image.new("RGB", (W, H))
        self.draw_embers(ImageDraw.Draw(add), t, 120)
        q = np.zeros((self.Hq, self.Wq, 3), np.float32)
        if e < 0.7:   # the shockwave
            r = np.hypot(self.xs - self.Wq / 2, self.ys - self.Hq / 2)
            R = e / 0.7 * math.hypot(self.Wq, self.Hq) * 0.6
            q += (np.exp(-((r - R) / (3 + 10 * e)) ** 2) * (1 - e / 0.7))[..., None] * np.array([255, 170, 120], np.float32)
        pulse = 0.5 + 0.5 * math.sin(2 * math.pi * 0.55 * t)
        self.glow_at(q, self.icon_c[0], self.icon_c[1], self.icon_size * 0.9, (255, 60, 40), 0.25 + 0.15 * pulse)
        qa = add.resize((self.Wq, self.Hq), Image.BILINEAR).filter(ImageFilter.GaussianBlur(2.2))
        q += np.asarray(qa, np.float32) * 2.2
        F += np.asarray(Image.fromarray(np.clip(q, 0, 255).astype(np.uint8)).resize((W, H), Image.BILINEAR), np.float32)
        F += np.asarray(add, np.float32)
        flash = math.exp(-e * 9)
        F += (255 - F) * (flash ** 1.5) * np.array([1.0, 0.93, 0.85], np.float32)   # a warm white flash
        img = self.look.grade(np.clip(F, 0, 255).astype(np.uint8), chroma=int(2 + 10 * flash))
        im = Image.fromarray(img)
        # The reticle flies from the drone into the logo.
        r0 = self.last_reticle
        p = ease_back(e / 0.25, 1.4)
        c = (r0[0] + (self.icon_c[0] - r0[0]) * p + dx, r0[1] + (self.icon_c[1] - r0[1]) * p + dy)
        size = r0[2] + (self.icon_size - r0[2]) * p
        rot = 70 * (1 - ease_out(e / 0.25))
        self.paste(im, self.ring_end, c, scale=size / self.icon_size, rot=rot)
        sh = (dx, dy)
        if t >= T_TEXT:
            et = t - T_TEXT
            glow = 0.5 + 0.2 * pulse
            self.paste(im, Image.new("RGBA", self.ring_glow.size, RED + (255,)), (c[0], c[1]), alpha=glow, mask=self.ring_glow)
            self.paste(im, self.ring_end, c)
            self.paste(im, self.sil_end, c, alpha=clamp01((et - 0.05) / 0.1))
            sc = 1 + 0.35 * (1 - ease_out(et / 0.16))
            self.paste(im, self.text, (self.text_c[0] + sh[0], self.text_c[1] + sh[1]), scale=sc, alpha=clamp01(et / 0.08))
        if t >= T_TAG:
            n = int(len(self.tag_edges) * clamp01((t - T_TAG) / 0.35))
            if n > 0:
                cut = self.tag.crop((0, 0, int(self.tag_edges[n - 1]), self.tag.height))
                full = Image.new("RGBA", self.tag.size)
                full.paste(cut, (0, 0))
                self.paste(im, full, (self.tag_c[0] + sh[0], self.tag_c[1] + sh[1]))
            if t < T_TAG + 0.45 and int(t * 8) % 2 == 0:
                x = self.tag_c[0] - self.tag.width / 2 + (self.tag_edges[n - 1] if n else 0) + 6 * u
                ImageDraw.Draw(im).rectangle([x, self.tag_c[1] - self.tag.height * 0.42, x + 0.35 * self.tag.height * 0.6,
                                              self.tag_c[1] + self.tag.height * 0.30], fill=RED)
        if t >= T_BTN:
            sc = ease_back((t - T_BTN) / 0.3)
            if t >= T_CLICK:
                sc *= 1 - 0.06 * math.sin(math.pi * clamp01((t - T_CLICK) / 0.16))
            gl = (0.55 + 0.3 * math.sin(2 * math.pi * 1.1 * (t - T_BTN))) * clamp01((t - T_BTN) / 0.3)
            self.paste(im, Image.new("RGBA", self.btn_glow.size, RED + (255,)), self.btn_c, scale=sc, alpha=gl,
                       mask=self.btn_glow.resize((max(1, int(self.btn_glow.width * sc)), max(1, int(self.btn_glow.height * sc)))))
            self.paste(im, self.btn, self.btn_c, scale=sc)
            if t >= T_CLICK:
                self.paste(im, self.btn_white, self.btn_c, scale=sc, alpha=0.85 * math.exp(-(t - T_CLICK) * 7))
        if t >= T_URL:
            a = clamp01((t - T_URL) / 0.3)
            self.paste(im, self.url, (self.url_c[0], self.url_c[1] + 20 * u * (1 - ease_out((t - T_URL) / 0.3))), alpha=a)
            self.paste(im, self.sub, self.sub_c, alpha=clamp01((t - T_URL - 0.25) / 0.3))
        click = (self.btn_c[0] + self.btn.width * 0.22, self.btn_c[1] + self.btn.height * 0.18)
        if t >= T_CLICK - 0.6:
            p = ease_out((t - (T_CLICK - 0.6)) / 0.5)
            sx, sy = W * 0.86 + (click[0] - W * 0.86) * p, H * 1.04 + (click[1] - H * 1.04) * p
            if t >= T_CLICK:
                d = ImageDraw.Draw(im, "RGBA")
                pr = clamp01((t - T_CLICK) / 0.45)
                if pr < 1:
                    R = (30 + 280 * ease_out(pr)) * u
                    d.ellipse([click[0] - R, click[1] - R, click[0] + R, click[1] + R], outline=(255, 255, 255, int(230 * (1 - pr))),
                              width=max(2, int(5 * u * (1 - pr) + 1)))
            press = 1 - 0.12 * math.sin(math.pi * clamp01((t - T_CLICK) / 0.16)) if t >= T_CLICK else 1.0
            cur = self.cursor if press == 1 else self.cursor.resize((int(self.cursor.width * press), int(self.cursor.height * press)))
            im.paste(cur, (int(sx), int(sy)), cur)
        out = np.asarray(im)
        g = 0.0
        if e < 0.15:
            g = 0.7
        elif 0 <= t - T_TEXT < 0.12:
            g = 0.45
        elif 0 <= t - T_CLICK < 0.08:
            g = 0.2
        elif t > T_END - 0.2:
            g = 0.5
        out = self.look.glitch(out, g)
        if t > T_END - 0.3:
            out = (out.astype(np.float32) * (1 - smooth((t - (T_END - 0.3)) / 0.3))).astype(np.uint8)
        return out

    # ---- one frame
    def frame(self, t):
        vv.W, vv.H = self.W, self.H
        self.look.rng = np.random.default_rng(int(t * FPS) + 1)
        W, H = self.W, self.H
        if t >= T_CUT:
            if t >= T_FLASH:
                if not hasattr(self, "last_reticle"):
                    self.last_reticle = self.reticle(T_CUT - 1 / FPS)[:3]
                return self.end_card(t)
            # the picture dies like an old TV: a white band that shrinks to a line, then a dot
            out = np.zeros((H, W, 3), np.uint8)
            k = int((t - T_CUT) * FPS)
            if k == 0:
                h = int(0.05 * H)
                out[H // 2 - h // 2:H // 2 + h // 2] = 235
            elif k == 1:
                out[H // 2 - 2:H // 2 + 2, int(0.1 * W):int(0.9 * W)] = 255
            else:
                out[H // 2 - 3:H // 2 + 3, W // 2 - 6:W // 2 + 6] = 200
            return out
        st = self.drone(t)
        bg = self.backdrop(t)
        if st is not None:
            r = 4.5 * smooth((40 - st["z"]) / 36)
            if r > 0.4:
                bg = bg.filter(ImageFilter.GaussianBlur(r * self.u))
        F = np.asarray(bg, np.float32) + self.effects(t, st)
        if st is not None:
            acc = [np.zeros((H, W, 3), np.float32), np.zeros((H, W), np.float32), np.zeros((H, W, 3), np.float32)]
            subs = [t, t - 1 / FPS / 3, t - 2 / FPS / 3] if t >= T_RUSH else [t]
            for ts in subs:
                s2 = self.drone(max(ts, T_EMERGE + 0.001))
                self.draw_drone(s2, lock_amount(ts), acc, 1 / len(subs))
            v = st["vis"]
            F = F * (1 - acc[1][..., None] * v) + acc[0] * v + acc[2] * v
        if t >= T_YOU:
            pulse = math.exp(-(t - T_YOU) * 3) * 0.8 + 0.25
            edge = Image.fromarray((self.edge * 255).clip(0, 255).astype(np.uint8)).resize((W, H), Image.BILINEAR)
            F += (np.asarray(edge, np.float32) / 255 * pulse)[..., None] * np.array([150, 10, 0], np.float32)
        if t < T_HUD:   # it starts as static
            s = 1 - smooth(t / T_HUD)
            noise = Image.fromarray(self.static[int(t * FPS) % len(self.static)]).resize((W, H), Image.NEAREST)
            F = F * (1 - s) + np.asarray(noise, np.float32)[..., None] * s * 0.8
        chroma = int(2 + shake_amp(t) * 0.3)
        img = Image.fromarray(self.look.grade(np.clip(F, 0, 255).astype(np.uint8), chroma=chroma))
        ov = self.hud(t, st)
        img.paste(ov, (0, 0), ov)
        out = np.asarray(img)
        g = 0.0
        if t < T_HUD:
            g = 0.6 * (1 - t / T_HUD)
        elif 0 <= t - T_LOCK < 0.1:
            g = 0.25
        elif 0 <= t - T_YOU < 0.1:
            g = 0.35
        elif t >= T_RUSH:
            g = 0.55 * smooth((t - T_RUSH) / (T_CUT - T_RUSH))
        return self.look.glitch(out, g)


_SCENES = {}


def scene(fmt):
    if fmt not in _SCENES:
        _SCENES[fmt] = Scene(fmt)
    return _SCENES[fmt]


def render_chunk(job):
    fmt, a, b, path = job
    sc = scene(fmt)
    sc.last_reticle = sc.reticle(T_CUT - 1 / FPS)[:3]
    enc = encoder(path, sc.W, sc.H, 14)
    for k in range(a, b):
        enc.stdin.write(np.ascontiguousarray(sc.frame(k / FPS)).tobytes())
    enc.stdin.close()
    enc.wait()
    return path


# ---------------------------------------------------------------- sound

def load_wav(name):
    with wave.open(os.path.join(AUDIO, name)) as w:
        ch, fr, n = w.getnchannels(), w.getframerate(), w.getnframes()
        x = np.frombuffer(w.readframes(n), np.int16).astype(np.float32) / 32768
    x = x.reshape(-1, ch).mean(axis=1)
    return np.interp(np.arange(0, len(x), fr / SR), np.arange(len(x)), x).astype(np.float32)


def varispeed(x, rate):
    """Plays x looped at a speed (and pitch) that changes per output sample."""
    pos = np.cumsum(rate) % len(x)
    return np.interp(pos, np.arange(len(x)), x).astype(np.float32)


def soundtrack():
    rng = np.random.default_rng(7)
    n = int(T_END * SR)
    out = np.zeros((n + SR * 4, 2), np.float32)

    def put(x, at, gain, pan=0.0, buf=None):
        buf = out if buf is None else buf
        i = int(at * SR)
        if i < 0:
            x, i = x[-i:], 0
        if x.ndim == 1:
            x = np.stack([x * (1 - max(0, pan)), x * (1 + min(0, pan))], axis=1)
        j = min(len(buf), i + len(x))
        buf[i:j] += (x[:j - i] * gain).astype(np.float32)

    t = np.arange(n) / SR
    slow = np.array([smooth((s - T_SLOW) / 0.15) * (1 - smooth((s - T_RUSH + 0.1) / 0.15)) for s in t[::480]])
    slow = np.interp(t, t[::480], slow).astype(np.float32)

    # Before the cut, into its own buffer so the cut can be hard.
    pre = np.zeros_like(out)
    put(static(rng, T_HUD), 0, 0.35, buf=pre)
    siren = load_wav("alert.wav")
    sl = np.zeros(n, np.float32)
    siren = siren[int(1.5 * SR):]   # skip the wind-up: it's already wailing
    k = min(n, len(siren))
    sl[:k] = siren[:k] * np.minimum(1, np.arange(k) / (0.15 * SR))
    sl = sl * (1 - slow) + lowpass(sl, 380).astype(np.float32) * slow * 1.4
    sl = sl + 0.45 * np.roll(sl, int(0.23 * SR)) + 0.25 * np.roll(sl, int(0.51 * SR))   # off the buildings
    put(sl, 0, 0.30, buf=pre)
    # The drone's engine, from the game, pitched by distance and by the slow motion.
    eng = load_wav("drone_loop.wav")
    z = np.array([drone_z(max(s, T_EMERGE)) for s in t[::480]])
    z = np.interp(t, t[::480], z)
    amp = 1 / (1 + (np.maximum(z, 0.5) / 16) ** 1.3)   # z goes negative after the cut
    amp *= np.clip((t - T_EMERGE) / 0.4, 0, 1)
    rate = 1.12 * (1 - 0.48 * slow) * (1 + 0.35 * np.clip((t - T_RUSH) / (T_CUT - T_RUSH), 0, 1))
    e = varispeed(eng, rate)
    e = e * (1 - slow) + lowpass(e, 500).astype(np.float32) * slow * 1.5
    put(e * amp, 0, 0.9, buf=pre)
    # Distant blasts, heard after they're seen.
    small = load_wav("explosion_small_a.wav")
    for _, at, pan in BLASTS:
        put(lowpass(small, 700).astype(np.float32), at + 0.35, 0.55, pan, buf=pre)
    # The guns.
    gl = load_wav("gun_loop.wav")
    for g, a, b in GUNS:
        k = int((b - a) * SR)
        x = np.tile(gl, k // len(gl) + 1)[:k]
        x[-int(0.03 * SR):] *= np.linspace(1, 0, int(0.03 * SR))
        put(x, a, 0.55, -0.7 if g == 0 else 0.7, buf=pre)
    # Lock-on beeps.
    beep = np.sin(2 * np.pi * 1900 * np.arange(int(0.07 * SR)) / SR).astype(np.float32)
    beep *= np.minimum(1, np.linspace(0, 8, len(beep))) * np.linspace(1, 0.6, len(beep))
    for at in (T_LOCK + 0.12, T_LOCK + 0.26):
        put(beep, at, 0.12, buf=pre)
    # Into slow motion: a whoosh down and a heartbeat.
    put(whoosh(rng, 0.6, rise=False), T_SLOW - 0.3, 0.35, buf=pre)
    put(boom(rng, 1.4, 70, 30), T_SLOW, 0.45, buf=pre)
    for at in (T_SLOW + 0.12,):
        put(boom(rng, 0.35, 62, 40), at, 0.55, buf=pre)
        put(boom(rng, 0.30, 58, 40), at + 0.21, 0.35, buf=pre)
    # TARGET: YOU.
    clk = click_sample()
    for k in range(10):
        put(clk * 0.8, T_YOU - 0.5 + k * 0.045, 0.10, rng.uniform(-0.3, 0.3), buf=pre)
    put(braam(rng, 1.6), T_YOU, 0.55, buf=pre)
    # The lunge.
    put(whoosh(rng, T_CUT - T_RUSH + 0.3), T_RUSH - 0.3, 0.75, buf=pre)
    pre[int(T_CUT * SR):] = 0
    fade = int(0.004 * SR)
    i = int(T_CUT * SR)
    pre[i - fade:i] *= np.linspace(1, 0, fade)[:, None]
    out += pre

    # After the cut.
    put(boom(rng, 4.0, 85, 22), T_FLASH, 1.0)
    put(load_wav("explosion_b.wav"), T_FLASH, 0.8)
    put(braam(rng, 3.0), T_FLASH, 0.5)
    put(static(rng, 0.25), T_FLASH, 0.3)
    k = int(3.0 * SR)
    tt = np.arange(k) / SR
    put((np.sin(2 * np.pi * 3600 * tt) * np.exp(-tt * 1.1)).astype(np.float32), T_FLASH, 0.03)   # ears ringing
    put(boom(rng, 0.7, 140, 50), T_FLASH + 0.25, 0.45)                                          # the reticle lands
    put(boom(rng, 1.8, 95, 30), T_TEXT, 0.6)
    put(static(rng, 0.12), T_TEXT, 0.2)
    for c in range(25):
        put(clk * rng.uniform(0.6, 1.0), T_TAG + c * 0.35 / 25, 0.09, rng.uniform(-0.3, 0.3))
    put(whoosh(rng, 0.3), T_BTN - 0.25, 0.25)
    blip = np.arange(int(0.12 * SR)) / SR
    for hz, at in ((880, T_BTN), (1320, T_BTN + 0.06)):
        put((np.sin(2 * np.pi * hz * blip) * np.exp(-blip * 30)).astype(np.float32), at, 0.12)
    put(clk, T_CLICK, 0.6)
    put((np.sin(2 * np.pi * 660 * blip) * np.exp(-blip * 25)).astype(np.float32), T_CLICK, 0.15)
    put(boom(rng, 1.0, 80, 40), T_CLICK, 0.25)
    # A dark bed: muffled at first (the ears are still ringing), then opening up.
    p = pad(T_END - T_FLASH, rng).astype(np.float32)
    dark = lowpass(p, 150).astype(np.float32)
    k = len(p)
    w = np.clip(np.arange(k) / SR / 1.6, 0, 1).astype(np.float32)
    bed = dark * (1 - w) + p * w
    put(np.stack([bed, np.roll(bed, 900)], axis=1), T_FLASH, 0.22)
    p0 = pad(T_CUT, rng).astype(np.float32) * np.linspace(0.3, 1, int(T_CUT * SR)).astype(np.float32)
    p0[-fade:] *= np.linspace(1, 0, fade)
    put(np.stack([p0, np.roll(p0, 900)], axis=1), 0, 0.12)
    out = out[:n]
    tail = int(0.3 * SR)
    out[-tail:] *= np.linspace(1, 0, tail)[:, None]
    return out


# ---------------------------------------------------------------- main

def main():
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    out = os.path.abspath(args[0] if args else os.path.join(ROOT, "itch", "outro"))
    os.makedirs(out, exist_ok=True)
    stills = next((a.split("=", 1)[1] if "=" in a else sys.argv[sys.argv.index(a) + 1]
                   for a in sys.argv if a.startswith("--still")), None)
    if stills:
        for fmt in FORMATS:
            sc = scene(fmt)
            sc.last_reticle = sc.reticle(T_CUT - 1 / FPS)[:3]
            for s in stills.split(","):
                Image.fromarray(sc.frame(float(s))).save(os.path.join(out, "still-%s-%05.2f.png" % (fmt, float(s))))
        print("stills in", out)
        return
    base = os.path.join(out, "strike-alert-outro")
    tmp = tempfile.mkdtemp(prefix="outro_")
    chunks = 4
    jobs = []
    for fmt in FORMATS:
        for c in range(chunks):
            a, b = FRAMES * c // chunks, FRAMES * (c + 1) // chunks
            jobs.append((fmt, a, b, os.path.join(tmp, "%s_%d.mp4" % (fmt, c))))
    with Pool(max(1, (os.cpu_count() or 2) - 1)) as pool:
        for p in pool.imap_unordered(render_chunk, jobs):
            print("done", os.path.basename(p), flush=True)
    raw = os.path.join(tmp, "raw.wav")
    write_wav(raw, soundtrack())
    subprocess.run([FF, "-hide_banner", "-loglevel", "error", "-y", "-i", raw, "-af", "loudnorm=I=-16:TP=-1.5:LRA=11",
                    "-ar", str(SR), base + ".wav"], check=True)
    for fmt in FORMATS:
        lst = os.path.join(tmp, fmt + ".txt")
        with open(lst, "w") as fh:
            for c in range(chunks):
                fh.write("file '%s'\n" % os.path.join(tmp, "%s_%d.mp4" % (fmt, c)).replace("\\", "/"))
        joined = os.path.join(tmp, fmt + ".mp4")
        subprocess.run([FF, "-hide_banner", "-loglevel", "error", "-y", "-f", "concat", "-safe", "0", "-i", lst,
                        "-c", "copy", joined], check=True)
        subprocess.run([FF, "-hide_banner", "-loglevel", "error", "-y", "-i", joined, "-i", base + ".wav",
                        "-map", "0:v", "-map", "1:a", "-c:v", "copy", "-c:a", "aac", "-b:a", "256k", "-shortest",
                        "-movflags", "+faststart", "%s-%s.mp4" % (base, fmt)], check=True)
        print("wrote %s-%s.mp4" % (base, fmt))


if __name__ == "__main__":
    main()
