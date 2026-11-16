"""Builds assets/ui/vehicles.png: the AA guns that drive about, seen from
above, nose to the right, each hull and its turret apart (the game turns the
hull with the way it drives and the turret to where it aims). 32x32 cells:

0 gun truck's hull: a dark pickup, the cab at the front, its windscreen and
  roof, the open bed behind with a mount in it, four wheels showing.
1 gun truck's turret: a camouflaged box mount and its heavy machine gun.
2 armoured AA gun's hull (Gepard-like): tracks either side, an olive hull
  between, the engine deck's grilles at the back.
3 armoured AA gun's turret: a boxy turret, a cannon either side of it, the
  search radar's dish on its back, the tracking radar at its front.

The turrets turn about their cell's middle; the hulls' mounts sit there too.

    python tools/vehicle_sprites.py [--preview out.png]
"""
import sys
from PIL import Image

N = 32
K = (16, 20, 26)


class Cell:
    def __init__(self):
        self.img = Image.new('RGBA', (N, N), (0, 0, 0, 0))

    def put(self, x, y, c):
        if 0 <= x < N and 0 <= y < N:
            self.img.putpixel((x, y), tuple(c) + (255,))

    def rect(self, x0, y0, w, h, c):
        for y in range(y0, y0 + h):
            for x in range(x0, x0 + w):
                self.put(x, y, c)

    def outline(self):
        src = self.img.copy().load()
        for y in range(N):
            for x in range(N):
                if src[x, y][3]:
                    continue
                for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                    xx, yy = x + dx, y + dy
                    if 0 <= xx < N and 0 <= yy < N and src[xx, yy][3] and src[xx, yy][:3] != K:
                        self.put(x, y, K)
                        break


def truck_hull():
    c = Cell()
    body = (58, 62, 60)
    hi = (88, 94, 92)
    dark = (34, 37, 38)
    # Wheels, sticking out a pixel at the corners.
    for (x, y) in ((8, 9), (8, 20), (20, 9), (20, 20)):
        c.rect(x, y, 4, 3, (24, 24, 26))
    # The body: 22 long, 11 wide, centred on (16, 15.5).
    c.rect(5, 10, 22, 12, body)
    # The cab at the front: its roof lighter, the windscreen dark in front of it.
    c.rect(17, 11, 6, 10, hi)
    c.rect(23, 11, 2, 10, (40, 52, 64))
    c.rect(24, 12, 1, 8, (70, 92, 110))
    # The bonnet.
    c.rect(25, 11, 2, 10, body)
    c.rect(26, 12, 1, 8, hi)
    # The bed behind the cab: its floor darker, its sides.
    c.rect(6, 11, 10, 10, dark)
    c.rect(5, 10, 12, 1, hi)
    c.rect(5, 21, 12, 1, body)
    # Tail lights.
    c.put(5, 11, (200, 50, 40))
    c.put(5, 20, (200, 50, 40))
    c.outline()
    return c.img


def truck_turret():
    c = Cell()
    camo = [(74, 94, 58), (58, 74, 46), (92, 108, 70)]
    # The box mount round the middle, camouflage blotches on it.
    for y in range(12, 20):
        for x in range(11, 20):
            c.put(x, y, camo[(x * 3 + y * 5 + (x // 3) * (y // 2)) % 3])
    c.rect(11, 12, 9, 1, (110, 124, 86))
    # The machine gun: a receiver, a barrel out to the front.
    c.rect(17, 14, 4, 4, (40, 42, 44))
    c.rect(21, 15, 8, 2, (70, 74, 78))
    c.rect(21, 15, 8, 1, (110, 114, 118))
    c.rect(28, 14, 1, 4, (50, 52, 56))
    c.outline()
    return c.img


def gepard_hull():
    c = Cell()
    olive = (86, 98, 62)
    olive_d = (64, 74, 46)
    track = (34, 36, 34)
    # The tracks, their links in a lighter grey every other pixel.
    for side_y in (7, 21):
        c.rect(2, side_y, 28, 4, track)
        for x in range(2, 30, 2):
            c.put(x, side_y + (0 if side_y == 7 else 3), (64, 66, 62))
    # The hull between them, a camouflage blotch or two.
    c.rect(3, 10, 27, 11, olive)
    c.rect(3, 10, 27, 1, (110, 122, 80))
    for (x, y, w, h) in ((5, 12, 4, 3), (22, 16, 5, 3), (14, 18, 4, 2)):
        c.rect(x, y, w, h, olive_d)
    c.rect(8, 11, 2, 2, (94, 72, 46))
    # The engine deck's grilles at the back.
    for x in range(4, 10, 2):
        c.rect(x, 13, 1, 5, (46, 52, 36))
    # The glacis at the front.
    c.rect(28, 11, 2, 9, (100, 112, 72))
    c.outline()
    return c.img


def gepard_turret():
    c = Cell()
    olive = (96, 108, 70)
    olive_d = (70, 80, 52)
    # The turret: a box round the middle.
    c.rect(10, 11, 12, 10, olive)
    c.rect(10, 11, 12, 1, (124, 136, 92))
    c.rect(12, 17, 5, 3, olive_d)
    # A cannon on each side of it, long, out to the front.
    for y in (9, 22):
        c.rect(13, y, 9, 2, olive_d)
        c.rect(22, y, 9, 1, (60, 62, 64))
        c.rect(22, y + 1, 9, 1, (40, 42, 44))
        c.put(30, y, (30, 30, 32))
    # The search radar's dish on its back, the tracking radar at its front.
    c.rect(7, 12, 3, 8, (170, 176, 180))
    c.rect(8, 13, 1, 6, (120, 126, 132))
    c.rect(22, 13, 3, 6, (140, 146, 150))
    c.rect(23, 14, 1, 4, (60, 64, 70))
    c.outline()
    return c.img


def build():
    sheet = Image.new('RGBA', (N * 4, N), (0, 0, 0, 0))
    for i, img in enumerate([truck_hull(), truck_turret(), gepard_hull(), gepard_turret()]):
        sheet.paste(img, (i * N, 0))
    return sheet


if __name__ == '__main__':
    s = build()
    s.save('assets/ui/vehicles.png')
    if '--preview' in sys.argv:
        out = sys.argv[sys.argv.index('--preview') + 1]
        big = Image.new('RGBA', (N * 4 * 8, N * 8 * 2), (120, 110, 80, 255))
        up = s.resize((N * 4 * 8, N * 8), Image.NEAREST)
        big.paste(up, (0, 0), up)
        # Hull and turret together.
        for j, (h, t) in enumerate(((0, 1), (2, 3))):
            comp = Image.new('RGBA', (N, N), (0, 0, 0, 0))
            hull = s.crop((h * N, 0, h * N + N, N))
            tur = s.crop((t * N, 0, t * N + N, N)).rotate(30)
            comp.paste(hull, (0, 0), hull)
            comp.paste(tur, (0, 0), tur)
            comp = comp.resize((N * 8, N * 8), Image.NEAREST)
            big.paste(comp, (j * N * 8, N * 8), comp)
        big.save(out)
    print('ok', s.size)
