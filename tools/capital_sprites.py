"""Builds assets/ui/capitals.png: each capital's landmarks, standing in the
middle of its city (the city itself is the map's own, see LiteTerrain): no
ground of their own, just the buildings, seen from the front and a little
above like the map's other sites.

Columns: 0 ours (a white domed government house with a columned portico and
a flag, a TV tower beside it), 1 the enemy's (a red fortress wall with two
towers under green tent roofs and red stars, a cathedral's gold onion domes
behind, a spired high-rise).
Rows: 0 standing, 1 damaged, 2 in ruins; 3, 4, 5 their lit windows (black
elsewhere: drawn added on at night).

    python tools/capital_sprites.py [--preview out.png]
"""
import sys
import random
from PIL import Image

N = 64
K = (16, 20, 26)


class Art:
    def __init__(self):
        self.day = Image.new('RGBA', (N, N), (0, 0, 0, 0))
        self.lit = Image.new('RGBA', (N, N), (0, 0, 0, 0))

    def put(self, x, y, c):
        if 0 <= x < N and 0 <= y < N:
            self.day.putpixel((x, y), tuple(c) + (255,))

    def rect(self, x0, y0, w, h, c):
        for y in range(y0, y0 + h):
            for x in range(x0, x0 + w):
                self.put(x, y, c)

    def window(self, x, y, wall, rng, chance=0.6):
        self.put(x, y, tuple(int(k * 0.5) for k in wall))
        if rng.random() < chance:
            self.lit.putpixel((x, y), (255, 205, 120, 255) if rng.random() < 0.8 else (255, 170, 90, 255))

    def windows(self, x0, y0, w, h, wall, rng, sx=2, sy=2, chance=0.6):
        for y in range(y0, y0 + h, sy):
            for x in range(x0, x0 + w, sx):
                self.window(x, y, wall, rng, chance)

    def disc(self, cx, cy, r, c, c2=None, squash=1.0):
        for y in range(-r, r + 1):
            for x in range(-r, r + 1):
                if x * x + (y / squash) ** 2 <= r * r:
                    self.put(cx + x, cy + y, c2 if (c2 and x > 0) else c)

    def outline(self):
        src = self.day.copy().load()
        for y in range(N):
            for x in range(N):
                if src[x, y][3]:
                    continue
                for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                    xx, yy = x + dx, y + dy
                    if 0 <= xx < N and 0 <= yy < N and src[xx, yy][3] and src[xx, yy][:3] != K:
                        self.put(x, y, K)
                        break


def ours():
    rng = random.Random(3)
    a = Art()
    white = (232, 230, 222)
    shade = (196, 194, 186)
    roof = (178, 182, 186)
    # The TV tower behind, right: a tall shaft, its pod, a red light.
    a.rect(51, 6, 2, 46, (168, 172, 178))
    a.rect(52, 6, 1, 46, (132, 136, 144))
    a.rect(48, 14, 8, 3, (210, 214, 220))
    a.rect(48, 17, 8, 1, (120, 126, 134))
    a.rect(49, 18, 6, 1, (150, 156, 164))
    a.rect(51, 2, 1, 4, (190, 190, 196))
    a.put(51, 1, (235, 70, 60))
    a.lit.putpixel((51, 1), (255, 90, 70, 255))
    for x in range(49, 55, 2):
        a.window(x, 15, (210, 214, 220), rng, 0.9)
    # Wings either side of the main house.
    for x0 in (6, 40):
        a.rect(x0, 40, 16, 4, roof)
        a.rect(x0, 44, 16, 12, white)
        a.rect(x0 + (15 if x0 == 6 else 0), 44, 1, 12, shade)
        a.windows(x0 + 2, 46, 13, 9, white, rng, 3, 3)
    # The main house: its roof, its front.
    a.rect(16, 36, 32, 4, roof)
    a.rect(16, 40, 32, 16, white)
    a.windows(18, 43, 29, 12, white, rng, 3, 4)
    # The dome on its drum, a flag over it.
    a.rect(25, 30, 14, 6, white)
    for x in range(26, 39, 2):
        a.put(x, 31, shade)
        a.put(x, 33, shade)
    a.disc(32, 29, 7, (240, 240, 236), (210, 210, 206), squash=0.8)
    a.rect(31, 18, 2, 6, (226, 226, 222))
    a.rect(32, 12, 1, 7, (90, 90, 96))
    # The flag: our side's blue, a white band across.
    a.rect(33, 12, 6, 4, (70, 130, 220))
    a.rect(33, 13, 6, 1, (240, 244, 250))
    # The portico: a pediment and six columns, steps under.
    for k in range(6):
        a.rect(22 + k, 36 - k // 2, 21 - 2 * k, 1, white)
    a.rect(22, 36, 21, 1, shade)
    for x in range(23, 43, 4):
        a.rect(x, 38, 2, 15, (246, 246, 242))
        a.rect(x + 1, 38, 1, 15, shade)
    a.rect(20, 53, 25, 2, (184, 182, 176))
    a.rect(18, 55, 29, 2, (168, 166, 160))
    # Trees by the lawn.
    for (tx, ty) in ((3, 52), (60, 53), (14, 58), (50, 58)):
        a.disc(tx, ty, 3, (70, 112, 64), (52, 88, 50))
    a.outline()
    return a


def theirs():
    rng = random.Random(11)
    a = Art()
    brick = (164, 60, 48)
    brick2 = (130, 46, 38)
    green = (74, 118, 90)
    gold = (232, 190, 74)
    gold2 = (190, 146, 52)
    # The spired high-rise behind, right.
    tower = (196, 186, 162)
    a.rect(48, 16, 12, 38, tower)
    a.rect(59, 16, 1, 38, (156, 146, 124))
    a.rect(50, 10, 8, 6, tower)
    a.rect(52, 5, 4, 5, tower)
    a.rect(53, 0, 2, 5, (220, 196, 110))
    a.put(53, 0, (240, 70, 60))
    a.windows(50, 18, 9, 34, tower, rng, 2, 3, 0.5)
    # The cathedral behind the wall: its body and onion domes.
    cw = (226, 214, 190)
    a.rect(16, 28, 24, 18, cw)
    a.windows(18, 32, 21, 12, cw, rng, 4, 4, 0.4)
    for (dx, dy, r) in ((20, 24, 3), (36, 24, 3), (28, 19, 5)):
        a.rect(dx - 1, dy + r - 1, 3, 5, cw)
        a.disc(dx, dy, r, gold, gold2, squash=1.15)
        a.rect(dx, dy - r - 3, 1, 3, (246, 226, 150))
        a.put(dx - 1, dy - r - 2, (246, 226, 150))
        a.put(dx + 1, dy - r - 2, (246, 226, 150))
    # The fortress wall across the front, battlements along its top.
    a.rect(2, 44, 46, 12, brick)
    a.rect(2, 52, 46, 1, brick2)
    for x in range(2, 48, 3):
        a.rect(x, 42, 2, 2, brick)
    # Two towers in it, green tent roofs, red stars on top.
    for tx in (4, 34):
        a.rect(tx, 30, 10, 26, brick)
        a.rect(tx + 9, 30, 1, 26, brick2)
        for k in range(7):
            a.rect(tx + k // 2 + 1, 23 + k, 8 - k // 2 * 2 + (k % 2), 1, green)
        a.rect(tx + 4, 17, 2, 6, green)
        a.put(tx + 4, 15, (236, 60, 52))
        a.put(tx + 5, 15, (236, 60, 52))
        a.put(tx + 4, 16, (236, 60, 52))
        a.put(tx + 5, 16, (236, 60, 52))
        a.lit.putpixel((tx + 4, 15), (255, 80, 60, 255))
        a.lit.putpixel((tx + 5, 16), (255, 80, 60, 255))
        a.rect(tx + 3, 36, 4, 6, (60, 30, 26))
        a.window(tx + 4, 46, brick, rng, 0.8)
        a.window(tx + 4, 49, brick, rng, 0.8)
        # Its clock face.
        a.disc(tx + 5, 33, 1, (236, 232, 214))
    a.outline()
    return a


def damage(day, lit, k, seed):
    """`k` of it hit: blackened, holes, rubble, a few embers; its windows dark there."""
    rng = random.Random(seed)
    d = day.copy()
    l = lit.copy()
    px = d.load()
    lp = l.load()
    for _ in range(int(16 * k)):
        cx, cy = rng.randrange(4, 60), rng.randrange(14, 58)
        r = rng.choice([2, 3, 4])
        for y in range(cy - r, cy + r + 1):
            for x in range(cx - r, cx + r + 1):
                if not (0 <= x < N and 0 <= y < N) or not px[x, y][3]:
                    continue
                if (x - cx) ** 2 + (y - cy) ** 2 > r * r:
                    continue
                c = px[x, y]
                h = rng.random()
                if h < 0.3 and k > 0.7:
                    px[x, y] = (0, 0, 0, 0)
                elif h < 0.55:
                    px[x, y] = (34, 28, 24, 255)
                else:
                    px[x, y] = (int(c[0] * 0.5), int(c[1] * 0.46), int(c[2] * 0.42), 255)
                lp[x, y] = (0, 0, 0, 0)
        if rng.random() < 0.5 and px[cx, cy][3]:
            px[cx, cy] = (255, 140, 40, 255)
    # Rubble at its foot.
    for _ in range(int(40 * k)):
        x, y = rng.randrange(4, 60), rng.randrange(54, 61)
        px[x, y] = rng.choice([(96, 86, 74, 255), (60, 54, 48, 255), (130, 120, 104, 255)])
    return d, l


def build():
    sheet = Image.new('RGBA', (N * 2, N * 6), (0, 0, 0, 0))
    for col, c in enumerate([ours(), theirs()]):
        for row, k in enumerate([0.0, 0.5, 1.0]):
            day, lit = (c.day, c.lit) if k == 0.0 else damage(c.day, c.lit, k, 7 + col)
            sheet.paste(day, (col * N, row * N))
            sheet.paste(lit, (col * N, (row + 3) * N))
    return sheet


if __name__ == '__main__':
    s = build()
    s.save('assets/ui/capitals.png')
    if '--preview' in sys.argv:
        out = sys.argv[sys.argv.index('--preview') + 1]
        big = Image.new('RGBA', (N * 2 * 5, N * 3 * 5), (58, 66, 62, 255))
        day = s.crop((0, 0, N * 2, N * 3)).resize((N * 10, N * 15), Image.NEAREST)
        big.paste(day, (0, 0), day)
        big.save(out)
    print('ok', s.size)
