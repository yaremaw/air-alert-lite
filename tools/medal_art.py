"""Builds the achievements' pictures, assets/ui/achievements/<id>.png: a
medal each, pixel art at 64x64 scaled up 4x. The harder the achievement,
the grander the medal:

0 bronze  - a plain round medal on a one-colour ribbon
1 silver  - a medal with a beaded rim on a striped ribbon
2 gold    - an eight-pointed star order, enamel centre, a glint
3 legend  - a gold star in a laurel wreath, a gem, rays behind it
4 special - the bomb's: a black and yellow disc, the trefoil, a green glow

Each carries its own emblem (EMBLEMS), engraved in the metal or set in
white on the enamel. Replace any picture with your own: the game takes
whatever PNG is at that path.

    python tools/medal_art.py [--sheet preview.png]
"""
import math
import sys
from PIL import Image

N = 64
OUT = 'assets/ui/achievements/'
K = (14, 16, 22)

# Each achievement: (tier, emblem, ribbon colours).
MEDALS = {
    'first_down':     (0, 'drone',     [(150, 40, 40)]),
    'salvo':          (0, 'salvo',     [(60, 90, 150)]),
    'hand_25':        (1, 'crosshair', [(40, 70, 130), (220, 220, 220)]),
    'hand_streak':    (1, 'bullets',   [(150, 40, 40), (230, 190, 70)]),
    'hand_cruise':    (1, 'missile',   [(40, 110, 80), (220, 220, 220)]),
    'black_gold':     (1, 'flame',     [(30, 30, 34), (230, 150, 40)]),
    'blind':          (1, 'radar',     [(70, 60, 120), (200, 200, 210)]),
    'stopped_cold':   (1, 'tank',      [(90, 110, 60), (220, 220, 220)]),
    'derailed':       (1, 'train',     [(120, 70, 40), (230, 190, 70)]),
    'left_behind':    (1, 'truck',     [(40, 90, 150), (240, 210, 80)]),
    'downs_500':      (2, 'shield',    [(40, 80, 160), (240, 210, 80), (40, 80, 160)]),
    'swarm':          (2, 'swarm',     [(150, 40, 40), (30, 30, 34), (150, 40, 40)]),
    'no_sam':         (2, 'noshield',  [(90, 40, 120), (230, 230, 230), (90, 40, 120)]),
    'untouched':      (2, 'dome',      [(40, 80, 160), (230, 230, 230), (40, 80, 160)]),
    'lightning':      (2, 'bolt',      [(40, 40, 50), (230, 190, 50), (40, 40, 50)]),
    'veteran':        (2, 'chevrons',  [(110, 30, 30), (230, 190, 70), (110, 30, 30)]),
    'ballistic_exec': (3, 'rocket',    [(140, 20, 20), (20, 20, 24), (140, 20, 20)]),
    'war_hard':       (3, 'swords',    [(20, 20, 24), (170, 30, 30), (20, 20, 24)]),
    'flawless':       (3, 'star',      [(120, 120, 130), (40, 40, 48), (120, 120, 130)]),
    'campaign':       (3, 'flag',      [(40, 80, 170), (240, 210, 60), (40, 80, 170)]),
    'oppenheimer':    (4, 'atom',      [(240, 200, 30), (20, 20, 20)]),
}

# Emblems, 13x13: '#' the shape.
EMBLEMS = {
'drone': [
"......#......",
".....###.....",
".....###.....",
"....#####....",
"...#######...",
"..#########..",
".###########.",
"#####.#.#####",
"###...#...###",
"#.....#.....#",
"......#......",
".....###.....",
".............",
],
'salvo': [
"#.....#.....#",
"#.....#.....#",
"##...###...##",
"##...###...##",
"##...###...##",
"##...###...##",
"##...###...##",
"##...###...##",
"#.#.#####.#.#",
"...#.###.#...",
"....#.#.#....",
".............",
"..#########..",
],
'crosshair': [
"......#......",
"....#####....",
"...#..#..#...",
"..#...#...#..",
".#....#....#.",
".#.........#.",
"#####.#.#####",
".#.........#.",
".#....#....#.",
"..#...#...#..",
"...#..#..#...",
"....#####....",
"......#......",
],
'bullets': [
".............",
".#...#...#...",
"###.###.###..",
"###.###.###..",
"###.###.###..",
"###.###.###..",
"###.###.###..",
"###.###.###..",
"###.###.###..",
"###.###.###..",
"#.#.#.#.#.#..",
"###.###.###..",
".............",
],
'missile': [
".............",
".............",
"##...........",
".##.....##...",
"..###########",
"..############",
"..###########",
".##.....##...",
"##...........",
".............",
".............",
".............",
".............",
],
'flame': [
"......#......",
".....##......",
".....###.....",
"....####.....",
"...######....",
"...#######...",
"..###.####...",
"..##...###...",
"..##...####..",
"..###.#####..",
"...#######...",
"....#####....",
".............",
],
'radar': [
"#...........#",
".##.......##.",
"..###...###..",
"...#######...",
"....#####....",
".....###.....",
"......#......",
"......#......",
".....###.....",
"....#####....",
"...#######...",
"..#########..",
".............",
],
'tank': [
".............",
".............",
".............",
"....####.....",
"...######....",
"...###########",
"..#######....",
".###########.",
"#############",
"#.#.#.#.#.#.#",
".###########.",
".............",
".............",
],
'train': [
".............",
"..##.........",
"..##..#######",
".####.#.#.#.#",
"#############",
"#############",
"#############",
"#############",
"#############",
".##.##..##.##",
".##.##..##.##",
"#############",
".............",
],
'truck': [
".............",
".............",
".............",
"........###..",
"........#.##.",
"........#..##",
"#############",
"#############",
"#############",
".##......##..",
".##......##..",
".............",
".............",
],
'shield': [
"#############",
"#############",
"##.........##",
"##....#....##",
"##...###...##",
"##.#######.##",
"##..#####..##",
".##.##.##.##.",
".##.#...#.##.",
"..##.....##..",
"...##...##...",
"....##.##....",
"......#......",
],
'swarm': [
"..#..........",
".###.....#...",
"#####...###..",
"#.#.#..#####.",
"..#....#.#.#.",
".........#...",
"....#........",
"...###.......",
"..#####......",
"..#.#.#......",
"....#........",
".............",
".............",
],
'noshield': [
"##.........##",
"###.......###",
"##.#.....#.##",
"##..#...#..##",
"##...#.#...##",
"##....#....##",
"##...#.#...##",
".##.#...#.##.",
".###.....###.",
"..#.......#..",
"...##...##...",
"....##.##....",
"......#......",
],
'dome': [
"......#......",
".....###.....",
"....#####....",
"...#######...",
"..#########..",
"..#########..",
".###########.",
".#.#.#.#.#.#.",
".#.#.#.#.#.#.",
".#.#.#.#.#.#.",
".###########.",
"#############",
".............",
],
'bolt': [
".......####..",
"......####...",
".....####....",
"....####.....",
"...########..",
"..########...",
"......###....",
".....###.....",
"....###......",
"...##........",
"..#..........",
".............",
".............",
],
'chevrons': [
"#...........#",
"##.........##",
".##.......##.",
"..##.....##..",
"#..##...##..#",
"##..##.##..##",
".##..###..##.",
"..##..#..##..",
"#..##...##..#",
"##..##.##..##",
".##..###..##.",
"..##..#..##..",
"......#......",
],
'rocket': [
"......#......",
".....###.....",
".....###.....",
".....###.....",
".....#.#.....",
".....###.....",
".....###.....",
".....###.....",
"....#####....",
"...##.#.##...",
"..##..#..##..",
"......#......",
".....#.#.....",
],
'swords': [
"#...........#",
".#.........#.",
"..#.......#..",
"...#.....#...",
"....#...#....",
".....#.#.....",
"......#......",
".....#.#.....",
"..#.#...#.#..",
"...#.....#...",
"..#.#...#.#..",
".#...........",
"#...........#",
],
'star': [
"......#......",
"......#......",
".....###.....",
".....###.....",
"#############",
".###########.",
"...#######...",
"....#####....",
"...#######...",
"...###.###...",
"..###...###..",
"..##.....##..",
".#.........#.",
],
'fist': [
".............",
"..##.##.##...",
".#########...",
".##########..",
".##########..",
".#########.#.",
".##########..",
"..#########..",
"..########...",
"...######....",
"...######....",
"...######....",
".............",
],
'flag': [
"#............",
"##########...",
"###########..",
"##########...",
"#########....",
"##########...",
"###########..",
"#............",
"#............",
"#............",
"#............",
"#............",
"#............",
],
'atom': [
"......#......",
".....###.....",
"....#####....",
"....#####....",
".....###.....",
"......#......",
".....#.#.....",
"....##.##....",
"..####.####..",
".#####.#####.",
"######.######",
".............",
".............",
],
}

METALS = {
    0: [(110, 60, 30), (170, 100, 50), (215, 145, 85), (250, 200, 150)],
    1: [(90, 96, 108), (150, 158, 172), (200, 208, 220), (245, 248, 252)],
    2: [(120, 78, 18), (200, 140, 30), (245, 195, 60), (255, 240, 160)],
    3: [(120, 78, 18), (210, 150, 30), (250, 205, 70), (255, 248, 190)],
    4: [(20, 20, 22), (200, 160, 20), (245, 210, 40), (255, 245, 150)],
}


class Pic:
    def __init__(self):
        self.img = Image.new('RGBA', (N, N), (0, 0, 0, 0))
        self.px = self.img.load()

    def put(self, x, y, c, a=255):
        x, y = int(x), int(y)
        if 0 <= x < N and 0 <= y < N:
            if a >= 255 or self.px[x, y][3] == 0:
                self.px[x, y] = tuple(c[:3]) + (a,)
            else:
                o = self.px[x, y]
                t = a / 255.0
                self.px[x, y] = tuple(int(o[i] * (1 - t) + c[i] * t) for i in range(3)) + (max(o[3], a),)

    def disc(self, cx, cy, r, col_at):
        for y in range(N):
            for x in range(N):
                dx, dy = x + 0.5 - cx, y + 0.5 - cy
                d = math.hypot(dx, dy)
                if d <= r:
                    c = col_at(dx, dy, d)
                    if c is not None:
                        self.put(x, y, c)

    def poly(self, pts, col_at):
        xs = [p[0] for p in pts]
        ys = [p[1] for p in pts]
        for y in range(int(min(ys)), int(max(ys)) + 1):
            for x in range(int(min(xs)), int(max(xs)) + 1):
                if _inside(x + 0.5, y + 0.5, pts):
                    c = col_at(x, y)
                    if c is not None:
                        self.put(x, y, c)

    def outline(self):
        src = self.img.copy().load()
        for y in range(N):
            for x in range(N):
                if src[x, y][3] > 200:
                    continue
                for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                    xx, yy = x + dx, y + dy
                    if 0 <= xx < N and 0 <= yy < N and src[xx, yy][3] > 200 and src[xx, yy][:3] != K:
                        self.put(x, y, K)
                        break


def _inside(x, y, pts):
    c = False
    j = len(pts) - 1
    for i in range(len(pts)):
        xi, yi = pts[i]
        xj, yj = pts[j]
        if (yi > y) != (yj > y) and x < (xj - xi) * (y - yi) / (yj - yi + 1e-9) + xi:
            c = not c
        j = i
    return c


def shade(m, dx, dy, d, r):
    """Metal lit from the upper left: four steps."""
    l = (-dx - dy) / (r * 1.4) + 0.15
    if d > r - 1.2:
        return m[0]
    if l > 0.45:
        return m[3]
    if l > 0.0:
        return m[2]
    if l > -0.45:
        return m[1]
    return m[0]


def ribbon(p, cols, tier):
    """The ribbon above the medal: stripes across, cut in a V at the top
    for the plain ones, a bar with gold edges for the grand ones."""
    w = 20 if tier < 2 else 24
    x0 = 32 - w // 2
    top, bot = 3, 22
    n = len(cols)
    for y in range(top, bot):
        for x in range(x0, x0 + w):
            k = (x - x0) * n // w
            c = cols[k]
            # Folds: darker on the right half, lighter on the left.
            f = 0.85 if (x - x0) > w * 0.62 else (1.12 if (x - x0) < w * 0.2 else 1.0)
            p.put(x, y, tuple(min(255, int(v * f)) for v in c))
    if tier >= 2:
        g = METALS[2]
        for x in range(x0 - 1, x0 + w + 1):
            p.put(x, top - 1, g[2])
            p.put(x, top, g[3])
            p.put(x, bot - 1, g[1])
    if tier >= 3:
        # A clasp bar with a small star on it.
        for x in range(x0 - 2, x0 + w + 2):
            for y in range(11, 15):
                p.put(x, y, METALS[3][2] if y < 13 else METALS[3][1])
        for (sx, sy) in ((32, 11), (31, 12), (32, 12), (33, 12), (32, 13), (31, 14), (33, 14)):
            p.put(sx, sy, (255, 255, 230))


def rays(p, cx, cy, col, n=16, r0=18, r1=31):
    for k in range(n):
        a = k * math.tau / n
        w = 0.09
        for rr in range(r0, r1):
            for s in (-1, 0, 1):
                aa = a + s * w * (1 - rr / r1)
                p.put(cx + math.cos(aa) * rr, cy + math.sin(aa) * rr, col, int(150 * (1 - (rr - r0) / (r1 - r0))))


def emblem(p, name, cx, cy, ink, light, scale=1):
    rows = EMBLEMS[name]
    h = len(rows)
    w = max(len(r) for r in rows)
    x0 = cx - (w * scale) // 2
    y0 = cy - (h * scale) // 2
    # A light edge down and right of each mark: engraved.
    for y, row in enumerate(rows):
        for x, ch in enumerate(row):
            if ch == '#':
                for sy in range(scale):
                    for sx in range(scale):
                        if light is not None:
                            p.put(x0 + x * scale + sx + 1, y0 + y * scale + sy + 1, light)
    for y, row in enumerate(rows):
        for x, ch in enumerate(row):
            if ch == '#':
                for sy in range(scale):
                    for sx in range(scale):
                        p.put(x0 + x * scale + sx, y0 + y * scale + sy, ink)


def star(cx, cy, r_out, r_in, n):
    pts = []
    for k in range(n * 2):
        r = r_out if k % 2 == 0 else r_in
        a = -math.pi / 2 + k * math.pi / n
        pts.append((cx + math.cos(a) * r, cy + math.sin(a) * r))
    return pts


def laurel(p, cx, cy, r):
    """Two laurel branches up the sides from the bottom: a stem, and a leaf
    either side of it every few pixels."""
    dark, mid, lite = (34, 80, 36), (64, 136, 56), (120, 196, 92)
    for side in (-1, 1):
        steps = 60
        for i in range(steps):
            a = math.pi / 2 + side * (0.25 + i / steps * 2.2)
            p.put(cx + math.cos(a) * r, cy + math.sin(a) * r, dark)
        for k in range(8):
            a = math.pi / 2 + side * (0.4 + k * 0.27)
            x = cx + math.cos(a) * r
            y = cy + math.sin(a) * r
            tx, ty = -math.sin(a) * side, math.cos(a) * side
            for o, col in ((1.0, lite), (-1.0, mid)):
                nx, ny = math.cos(a) * o * 1.6, math.sin(a) * o * 1.6
                for t in range(3):
                    p.put(x + nx + tx * (t - 0.5), y + ny + ty * (t - 0.5), col)
                    p.put(x + nx * 1.6 + tx * t, y + ny * 1.6 + ty * t, col)


def build(aid):
    tier, emb, cols = MEDALS[aid]
    m = METALS[tier]
    p = Pic()
    cx, cy = 32, 40
    if tier == 3:
        rays(p, cx, cy, (255, 220, 120), 16, 17, 32)
    if tier == 4:
        for y in range(N):
            for x in range(N):
                d = math.hypot(x + 0.5 - cx, y + 0.5 - cy)
                if 15 < d < 30:
                    p.put(x, y, (120, 255, 90), int(110 * (1 - (d - 15) / 15)))
    ribbon(p, cols, tier)
    # The ring the medal hangs from.
    for (x, y) in ((31, 21), (32, 21), (33, 21), (30, 22), (34, 22), (30, 23), (34, 23), (31, 24), (32, 24), (33, 24)):
        p.put(x, y, m[1])
    if tier == 0:
        r = 15
        p.disc(cx, cy, r, lambda dx, dy, d: shade(m, dx, dy, d, r))
        p.disc(cx, cy, r - 3, lambda dx, dy, d: m[0] if d > r - 4 else None)
        emblem(p, emb, cx, cy, m[0], m[3])
    elif tier == 1:
        r = 16
        def rim(dx, dy, d):
            if d > r - 2.6:
                a = math.atan2(dy, dx)
                return m[3] if math.cos(a * 16) > 0.2 else m[1]
            return shade(m, dx, dy, d, r)
        p.disc(cx, cy, r, rim)
        p.disc(cx, cy, r - 3, lambda dx, dy, d: m[0] if d > r - 3.8 else None)
        emblem(p, emb, cx, cy, m[0], m[3])
    elif tier in (2, 3):
        rs = 21 if tier == 3 else 19
        pts = star(cx, cy, rs, rs * 0.62, 8)
        p.poly(pts, lambda x, y: shade(m, x + 0.5 - cx, y + 0.5 - cy, 0, rs))
        # Ridges from the centre to each point.
        for k in range(8):
            a = -math.pi / 2 + k * math.pi / 4
            for rr in range(11, rs - 1):
                p.put(cx + math.cos(a) * rr, cy + math.sin(a) * rr, m[3] if k < 4 else m[1])
        if tier == 3:
            laurel(p, cx, cy, 22)
        enamel = cols[0]
        er = 11
        p.disc(cx, cy, er, lambda dx, dy, d: m[0] if d > er - 1.4 else (enamel if d > er - 2.6 or dy > -er * 0.2 else tuple(min(255, int(v * 1.25)) for v in enamel)))
        emblem(p, emb, cx, cy, (250, 250, 245), None)
        if tier == 3:
            # A gem at the top point.
            for (x, y, c) in ((32, 18, (255, 90, 90)), (31, 19, (210, 30, 40)), (32, 19, (255, 140, 140)), (33, 19, (170, 20, 30)), (32, 20, (150, 10, 20))):
                p.put(x, y, c)
        # A glint.
        for (x, y) in ((44, 27), (43, 28), (44, 28), (45, 28), (44, 29), (44, 26), (44, 30), (42, 28), (46, 28)):
            p.put(x, y, (255, 255, 240), 230 if (x, y) == (44, 28) else 170)
    else:
        r = 17
        def hazard(dx, dy, d):
            if d > r - 1.2:
                return (10, 10, 12)
            if d > r - 4:
                a = math.atan2(dy, dx)
                return m[2] if int((a + math.pi) / math.tau * 16) % 2 == 0 else (25, 25, 28)
            return (30, 30, 34) if d > 11.5 else m[2]
        p.disc(cx, cy, r, hazard)
        # The trefoil, black on the yellow centre.
        for y in range(N):
            for x in range(N):
                dx, dy = x + 0.5 - cx, y + 0.5 - cy
                d = math.hypot(dx, dy)
                if d < 11:
                    a = (math.atan2(dy, dx) + math.pi / 2) % (math.tau / 3)
                    if d < 2.2 or (3.5 < d < 10 and a < math.tau / 6):
                        p.put(x, y, (20, 20, 22))
    p.outline()
    return p.img.resize((N * 4, N * 4), Image.NEAREST)


if __name__ == '__main__':
    pics = {aid: build(aid) for aid in MEDALS}
    for aid, img in pics.items():
        img.save(OUT + aid + '.png')
    if '--sheet' in sys.argv:
        out = sys.argv[sys.argv.index('--sheet') + 1]
        cols = 7
        rows = (len(pics) + cols - 1) // cols
        sheet = Image.new('RGBA', (cols * 140, rows * 140), (12, 16, 24, 255))
        for i, img in enumerate(pics.values()):
            t = img.resize((128, 128), Image.NEAREST)
            sheet.paste(t, ((i % cols) * 140 + 6, (i // cols) * 140 + 6), t)
        sheet.save(out)
    print('ok', len(pics))
