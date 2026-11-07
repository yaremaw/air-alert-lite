"""A cinematic cover for Strike Alert: the game's own alert map laid out like a
glowing war-room table, tilted away to the horizon, with the raid rising off it
in 3D: red drone and missile arcs coming over the horizon, a ballistic missile
diving out of the sky, blue interceptors meeting them in bright flashes, our
strike arcing back at their capital, the logo in the sky above.

    python tools/itch_warroom.py itch/extra/warroom-map.png itch

MAP.png is a 1924x1050 shot of the game mid-raid with the interface hidden.
Writes cover-warroom.png (630x500) and cover-warroom-1260.png (1260x1000).
"""
import math
import os
import random
import sys

import numpy as np
from PIL import Image, ImageChops, ImageDraw, ImageFilter

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
LOGO = os.path.join(ROOT, "itch", "logo.png")
W, H = 2520, 2000  # drawn at four times the cover
RED = (255, 70, 55)
BLUE = (80, 170, 255)
PAD = 1600  # dark ground added round the map, so the table reaches the frame edges
# The camera: where it stands (map point and height) and the map point it looks at.
EYE = (420.0, 1080.0, 150.0)
TARGET = (1020.0, 500.0)
FOCAL = 0.7  # of the frame width
HAZE = np.array([92, 32, 28], np.float32)  # the far ground and the sky at the horizon
# Places on the map shot (pixels): our capital, our SAMs, cities the raid is after,
# their capital.
CAPITAL = (657, 495)
SAMS = [(750, 435), (738, 563), (705, 523)]
CITIES = [(760, 356), (750, 598), (866, 763), (890, 450), (993, 628), (620, 648)]
THEIR_CAPITAL = (1333, 560)


class Cam:
    """A camera south-west of our country, looking north-east across the front and down
    at the map. Ground points are map pixels (u right, v down the shot); heights are in
    the same units, so a point is (u, v, height)."""

    def __init__(self, map_h):
        self.depth0 = map_h
        self.pos = self.world(*EYE)
        fwd = self.world(*TARGET) - self.pos
        self.fwd = fwd / np.linalg.norm(fwd)
        r = np.cross(np.array([0.0, 1.0, 0.0]), self.fwd)
        self.right = r / np.linalg.norm(r)
        self.up = np.cross(self.fwd, self.right)
        self.f = W * FOCAL

    def world(self, u, v, height=0.0):
        return np.array([u, height, self.depth0 - v], np.float64)

    def project(self, u, v, height=0.0):
        d = self.world(u, v, height) - self.pos
        z = float(d @ self.fwd)
        return W / 2 + self.f * float(d @ self.right) / z, H / 2 - self.f * float(d @ self.up) / z, z

    @property
    def horizon(self):
        return H / 2 - self.f * math.tan(math.asin(-self.fwd[1]))


def perspective_coeffs(dst, src):
    """PIL's PERSPECTIVE coefficients mapping output points `dst` back to input points `src`."""
    rows = []
    for (x, y), (u, v) in zip(dst, src):
        rows.append([x, y, 1, 0, 0, 0, -u * x, -u * y])
        rows.append([0, 0, 0, x, y, 1, -v * x, -v * y])
    a = np.array(rows, np.float64)
    b = np.array([c for p in src for c in p], np.float64)
    return np.linalg.solve(a, b).tolist()


def table(shot, cam):
    """The map, padded with its own background, warped onto the tilted ground: the
    mapping comes from the map's own corners, which are all in front of the camera."""
    bg = shot.getpixel((4, 4))
    big = Image.new("RGB", (shot.width + 2 * PAD, shot.height + 2 * PAD), bg)
    big.paste(shot, (PAD, PAD))
    corners = [(500, 300), (1500, 300), (1500, 900), (500, 900)]
    screen = [cam.project(u, v)[:2] for u, v in corners]
    src = [(u + PAD, v + PAD) for u, v in corners]
    coeffs = perspective_coeffs(screen, src)
    warped = big.transform((W, H), Image.PERSPECTIVE, coeffs, Image.BICUBIC)
    mask = Image.new("L", big.size, 255).transform((W, H), Image.PERSPECTIVE, coeffs, Image.BILINEAR)
    return warped, mask


def sky(horizon_y):
    yy = np.arange(H, dtype=np.float32)[:, None]
    t = np.clip((horizon_y - yy) / horizon_y, 0, 1)
    top = np.array([5, 7, 14], np.float32)
    mid = np.array([22, 18, 34], np.float32)
    low = HAZE
    col = np.where(t > 0.35, mid + (top - mid) * ((t - 0.35) / 0.65), low + (mid - low) * (t / 0.35) ** 0.7)
    img = np.broadcast_to(col[:, None, :], (H, W, 3)).copy()
    xx = np.arange(W, dtype=np.float32)[None, :]
    # The burning east glows brightest over their capital and the front.
    img += (np.exp(-((xx - W * 0.66) / (W * 0.3)) ** 2) * np.exp(-np.clip(horizon_y - yy, 0, None) / 160))[:, :, None] * np.array([90, 30, 12], np.float32)
    rng = np.random.default_rng(4)
    for _ in range(260):
        x, y = rng.integers(0, W), rng.integers(0, int(horizon_y * 0.8))
        img[y, x] += rng.uniform(40, 140) * (1 - y / horizon_y)
    return img


def glow(base, layer, radii):
    for r in radii:
        base = ImageChops.screen(base, layer.filter(ImageFilter.GaussianBlur(r)))
    return ImageChops.screen(base, layer)


def arc(cam, a, b, height, steps=90):
    """A trajectory from ground point a to ground point b, `height` at its top."""
    pts = []
    for i in range(steps + 1):
        t = i / steps
        u, v = a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t
        pts.append(cam.project(u, v, height * 4 * t * (1 - t)))
    return pts


def trail(d, pts, upto, colour, width, head=None):
    """The arc from its start to `upto` (0..1), brightening towards its head."""
    n = max(2, int(len(pts) * upto))
    for i in range(n - 1):
        k = (i / n) ** 1.6
        c = tuple(int(x * (0.15 + 0.85 * k)) for x in colour)
        d.line([pts[i][:2], pts[i + 1][:2]], fill=c, width=max(2, int(width * (0.5 + 0.5 * k))))
    x, y = pts[n - 1][:2]
    if head:
        r = head
        d.ellipse([x - r * 2.4, y - r * 2.4, x + r * 2.4, y + r * 2.4], fill=tuple(int(c * 0.55) for c in colour))
        d.ellipse([x - r, y - r, x + r, y + r], fill=(255, 250, 240))
    return x, y


def flash(d, x, y, r, rng, colour=(255, 200, 120)):
    for k, c in ((2.6, tuple(int(v * 0.35) for v in colour)), (1.5, colour), (0.7, (255, 250, 235))):
        d.ellipse([x - r * k, y - r * k, x + r * k, y + r * k], fill=c)
    for _ in range(26):
        a = rng.uniform(0, math.tau)
        r0, r1 = r * rng.uniform(0.9, 1.4), r * rng.uniform(2.2, 4.5)
        d.line([(x + math.cos(a) * r0, y + math.sin(a) * r0), (x + math.cos(a) * r1, y + math.sin(a) * r1)],
               fill=colour, width=3)


def ground_ring(d, cam, u, v, radius, colour, width):
    pts = [cam.project(u + math.cos(a) * radius, v + math.sin(a) * radius)[:2] for a in np.linspace(0, math.tau, 80)]
    d.line(pts, fill=colour, width=width)


def bez(a, c, b, n=100):
    """Points along a quadratic curve through (u, v, height) control points."""
    a, c, b = (np.array(x, np.float64) for x in (a, c, b))
    return [tuple((1 - t) ** 2 * a + 2 * (1 - t) * t * c + t * t * b) for t in np.linspace(0, 1, n)]


def path(cam, pts):
    return [cam.project(*p) for p in pts]


def line(d, sp, colour, width, fade=1.6, dotted=False):
    """A trail along screen points `sp`, faint at its tail and bright at its head."""
    n = len(sp)
    for i in range(n - 1):
        if sp[i][2] < 5 or sp[i + 1][2] < 5 or (dotted and i % 3 == 2):
            continue
        k = (i / (n - 1)) ** fade
        c = tuple(int(x * (0.12 + 0.88 * k)) for x in colour)
        d.line([sp[i][:2], sp[i + 1][:2]], fill=c, width=max(1, int(round(width * (0.45 + 0.55 * k)))))


def head(d, x, y, r, colour):
    d.ellipse([x - r * 2.6, y - r * 2.6, x + r * 2.6, y + r * 2.6], fill=tuple(int(c * 0.5) for c in colour))
    d.ellipse([x - r, y - r, x + r, y + r], fill=(255, 250, 240))


def burst(d, x, y, r, rng, colour=(255, 190, 110)):
    for k, c in ((3.2, tuple(int(v * 0.3) for v in colour)), (1.8, colour), (0.8, (255, 250, 238))):
        d.ellipse([x - r * k, y - r * k, x + r * k, y + r * k], fill=c)
    for _ in range(34):
        a = rng.uniform(0, math.tau)
        r0, r1 = r * rng.uniform(1.0, 1.6), r * rng.uniform(2.6, 6.0)
        d.line([(x + math.cos(a) * r0, y + math.sin(a) * r0), (x + math.cos(a) * r1, y + math.sin(a) * r1)],
               fill=colour, width=max(2, int(r * 0.12)))


def dome(d, cam, centre, radius, colour):
    """An air-defence umbrella: a faint wire dome over a SAM's reach."""
    u0, v0 = centre
    for lat in np.linspace(0, 1.25, 6):
        rr, h = radius * math.cos(lat), radius * math.sin(lat) * 0.55
        pts = [cam.project(u0 + math.cos(a) * rr, v0 + math.sin(a) * rr, h) for a in np.linspace(0, math.tau, 90)]
        k = 1.0 - lat / 1.6
        d.line([p[:2] for p in pts], fill=tuple(int(c * k) for c in colour), width=3 if lat == 0 else 2)
    for a in np.linspace(0, math.tau, 13)[:-1]:
        pts = [cam.project(u0 + math.cos(a) * radius * math.cos(l), v0 + math.sin(a) * radius * math.cos(l),
                           radius * math.sin(l) * 0.55) for l in np.linspace(0, math.pi / 2, 30)]
        d.line([p[:2] for p in pts], fill=tuple(int(c * 0.55) for c in colour), width=2)


def pillar(img, cam, u, v, height, colour, width):
    """Fire and smoke rising off a burning city: a soft column of light."""
    x0, y0, z0 = cam.project(u, v)
    x1, y1, _ = cam.project(u, v, height)
    w = max(6, cam.f * width / z0)
    lay = Image.new("RGB", img.size)
    d = ImageDraw.Draw(lay)
    steps = 30
    for i in range(steps):
        t = i / steps
        x, y = x0 + (x1 - x0) * t, y0 + (y1 - y0) * t
        k = (1 - t) ** 2.2
        r = w * (0.6 + 1.6 * t)
        d.ellipse([x - r, y - r, x + r, y + r], fill=tuple(int(c * k) for c in colour))
    d.ellipse([x0 - w * 0.7, y0 - w * 0.4, x0 + w * 0.7, y0 + w * 0.4], fill=(255, 230, 170))
    return ImageChops.screen(img, lay.filter(ImageFilter.GaussianBlur(w * 0.6)))


def battle(img, cam):
    rng = random.Random(3)
    light = Image.new("RGB", img.size)
    d = ImageDraw.Draw(light)
    # Our air defence umbrella over the capital.
    dome(d, cam, CAPITAL, 125, (40, 110, 200))
    # The raid: drones and cruise missiles low over the horizon from the east, at our cities.
    for i in range(16):
        src = (rng.uniform(1700, 2700), rng.uniform(-200, 900))
        dst = rng.choice(CITIES)
        dst = (dst[0] + rng.uniform(-40, 40), dst[1] + rng.uniform(-40, 40))
        cruise = i % 4 == 0
        h = rng.uniform(25, 60) if not cruise else rng.uniform(15, 30)
        mid = ((src[0] + dst[0]) / 2, (src[1] + dst[1]) / 2, h * 2)
        pts = bez((*src, h), mid, (*dst, 8), 120)
        upto = int(len(pts) * rng.uniform(0.55, 0.9))
        sp = path(cam, pts[:upto])
        line(d, sp, (255, 90, 60) if cruise else (230, 60, 50), 5 if cruise else 3, dotted=not cruise)
        x, y, z = sp[-1]
        head(d, x, y, max(3, cam.f * 3 / z), RED)
        if rng.random() < 0.35:  # shot down by the guns
            burst(d, x, y, max(5, cam.f * 4 / z), rng)
    # The ballistic missile, diving out of space at our capital, met by our SAMs.
    hit = (800, 470, 215)
    sp = path(cam, bez((1750, 780, 1250), (1260, 640, 760), hit, 140))
    line(d, sp, (255, 120, 60), 16, fade=1.2)
    line(d, sp, (255, 220, 160), 5, fade=2.5)
    for s0 in SAMS:
        end = (hit[0] + rng.uniform(-8, 8), hit[1] + rng.uniform(-8, 8), hit[2] + rng.uniform(-10, 10))
        ctrl = (s0[0] + (end[0] - s0[0]) * 0.15, s0[1] + (end[1] - s0[1]) * 0.15, end[2] * 1.05)
        line(d, path(cam, bez((*s0, 2), ctrl, end, 80)), BLUE, 10, fade=1.1)
    x, y, z = cam.project(*hit)
    r = cam.f * 15 / z
    burst(d, x, y, r, rng)
    # Its shock wave, and burning debris falling away.
    d.ellipse([x - r * 5.5, y - r * 5.5, x + r * 5.5, y + r * 5.5], outline=(150, 110, 80), width=4)
    d.ellipse([x - r * 7.5, y - r * 7.5, x + r * 7.5, y + r * 7.5], outline=(70, 50, 40), width=3)
    for _ in range(22):
        a = rng.uniform(0.1 * math.pi, 0.9 * math.pi)
        dist = r * rng.uniform(1.8, 5.0)
        px, py = x + math.cos(a) * dist, y + math.sin(a) * dist
        q = max(3, r * rng.uniform(0.08, 0.16))
        d.ellipse([px - q, py - q, px + q, py + q], fill=(255, 175, 95))
        d.line([(px, py), (px - math.cos(a) * q * 4, py - math.sin(a) * q * 4)], fill=(150, 80, 40), width=int(q))
    # A second ballistic missile still diving in, further out.
    b2 = path(cam, bez((1500, 950, 1000), (1380, 900, 600), (1180, 830, 120), 120))[:104]
    line(d, b2, (255, 120, 60), 11, fade=1.2)
    line(d, b2, (255, 220, 160), 3, fade=2.5)
    head(d, b2[-1][0], b2[-1][1], max(6, cam.f * 4 / b2[-1][2]), (255, 120, 60))
    # Our strike back: cruise missiles arcing over the front at their capital.
    for k in range(3):
        a = (820 + k * 25, 640 - k * 20, 2)
        pts = bez(a, (1080, 430 - k * 40, 380 + k * 30), (THEIR_CAPITAL[0] - 30 + k * 20, THEIR_CAPITAL[1] - 10, 10), 110)
        sp = path(cam, pts)[:int(110 * (0.78 + 0.07 * k))]
        line(d, sp, (110, 190, 255), 6, fade=1.4)
        head(d, sp[-1][0], sp[-1][1], max(4, cam.f * 3 / sp[-1][2]), BLUE)
    img = glow(img, light, [4, 16, 50])
    # Fires where the raid got through.
    for (u, v), h in ((CITIES[2], 260), (CITIES[3], 200), ((1350, 420), 320)):
        img = pillar(img, cam, u, v, h, (255, 120, 50), 9)
    return img


def logo_on(img):
    lg = Image.open(LOGO).convert("RGBA")
    lw = int(W * 0.66)
    lg = lg.resize((lw, round(lg.height * lw / lg.width)), Image.LANCZOS)
    out = img.convert("RGBA")
    yy = np.clip((np.arange(H, dtype=np.float32) - H * 0.66) / (H * 0.3), 0, 1) ** 1.2
    shade = Image.new("RGBA", out.size, (6, 7, 12, 0))
    shade.putalpha(Image.fromarray(np.broadcast_to((yy * 235)[:, None], (H, W)).astype(np.uint8)))
    out.alpha_composite(shade)
    out.alpha_composite(lg, ((W - lw) // 2, H - lg.height - int(H * 0.05)))
    return out.convert("RGB")


def grade(img):
    arr = np.asarray(img, np.float32) / 255
    lum = arr @ np.array([0.3, 0.59, 0.11], np.float32)
    hi = Image.fromarray((np.clip(lum - 0.55, 0, 1) / 0.45 * 255).astype(np.uint8))
    for r, s in ((30, 0.35), (110, 0.35)):
        b = np.asarray(hi.filter(ImageFilter.GaussianBlur(r)), np.float32)[:, :, None] / 255
        arr = 1 - (1 - arr) * (1 - b * s * np.array([1.0, 0.8, 0.65], np.float32))
    arr = 0.5 + (arr - 0.5) * 1.08
    yy, xx = np.mgrid[0:H, 0:W].astype(np.float32)
    v = 1 - 0.45 * (((xx - W / 2) / (W * 0.72)) ** 2 + ((yy - H * 0.55) / (H * 0.8)) ** 2)
    arr *= np.clip(v, 0.3, 1)[:, :, None]
    out = np.clip(arr, 0, 1)
    out[:, 3:, 0] = out[:, :-3, 0]
    out[:, :-3, 2] = out[:, 3:, 2]
    arr = out * 255 + np.random.default_rng(5).normal(0, 3, (H, W))[:, :, None]
    return Image.fromarray(np.clip(arr, 0, 255).astype(np.uint8))


def render(shot):
    cam = Cam(shot.height)
    ground, mask = table(shot, cam)
    horizon = cam.horizon
    # The table: the map, glowing where alerts burn, fading into the haze far away.
    hz = HAZE
    m = np.asarray(mask, np.float32)[:, :, None] / 255
    g = np.asarray(ground, np.float32) * m + hz * (1 - m)
    yy = np.arange(H, dtype=np.float32)[:, None, None]
    near = np.clip((yy - horizon) / (H * 0.3), 0, 1) ** 0.7
    g = g * near + hz * (1 - near)
    img = np.where(yy >= horizon, g, sky(horizon))
    img = Image.fromarray(np.clip(img, 0, 255).astype(np.uint8))
    sat = np.asarray(ground.convert("HSV"), np.float32)[:, :, 1] / 255
    lit = Image.fromarray((np.clip(sat - 0.35, 0, 1) / 0.65 * 255).astype(np.uint8))
    hot = Image.merge("RGB", [ImageChops.multiply(ch, lit) for ch in ground.split()])
    img = glow(img, hot.point(lambda x: int(x * 0.5)), [25, 90])
    return img, cam


def main():
    shot = Image.open(sys.argv[1]).convert("RGB")
    out = sys.argv[2]
    img, cam = render(shot)
    img = battle(img, cam)
    img = logo_on(grade(img))
    img.resize((1260, 1000), Image.LANCZOS).save(os.path.join(out, "cover-warroom-1260.png"))
    img.resize((630, 500), Image.LANCZOS).save(os.path.join(out, "cover-warroom.png"))
    print("wrote", out)


if __name__ == "__main__":
    main()
