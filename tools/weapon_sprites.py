"""Builds assets/ui/weapons.png: the flying weapons as pixel art drawn at the
size they are seen in the game (about one sprite pixel a screen pixel at
1080p), nose to the right, in greys the game tints by side (ours blue, theirs
red), the outline staying dark. Each sits in the middle of a 32x32 cell, in
this order:

0 attack drone: a Shahed-136-style flying-wing delta, the leading edge swept
  far back, the trailing edge straight, a narrow body running out ahead of
  the wing to a pointed nose, winglets at the tips, a pusher propeller behind.
1 recon drone: a fixed-wing UAV (Orlan-style): straight wings longer than the
  body, a slender body, a tailplane, a propeller at the nose.
2 cruise missile: a Tomahawk-style long thin body with an ogive nose, small
  straight wings a little behind the middle, a cruciform tail.
3 ballistic missile: a short, thick body with a conical nose, a darker band
  where the warhead joins, four tail fins, a nozzle.
4 jet attack drone (Geran-3 style): the delta of 0, longer and darker, a jet
  engine's pod on its back at the rear.

Drawn one pixel at a time below ('#' body, 'w' highlight, 'd' dark part),
shaded from the top left, then outlined.

    python tools/weapon_sprites.py [--preview out.png]
"""
import sys
from PIL import Image

N = 32
K = (16, 20, 26)        # outline
G0 = (52, 60, 72)       # darkest grey
G1 = (92, 104, 120)     # dark grey
G2 = (150, 162, 176)    # grey
G3 = (200, 208, 218)    # light grey
W = (238, 242, 248)     # highlight

def _delta(length, half, le_at, jet=False):
    """A Shahed-style delta from above, nose at the right: a body three rows
    tall along the middle to a rounded nose at `length`, the wing's trailing
    edge straight across the back, its leading edge from the tips (half-span
    `half`) to the body at `le_at`, fins at the tips; a jet one darker, its
    engine's pod on the body at the back."""
    rows = []
    for y in range(half * 2 + 1):
        d = abs(y - half)
        r = ['.'] * length
        top = y < half
        if d == half:
            r[0] = 't'
            r[1] = 't'
        else:
            le = int(round(le_at * (1.0 - d / half)))
            for x in range(0, max(1, le) + 1):
                r[x] = ('1' if jet else '3') if top else ('0' if jet else '2')
        if d <= 1:
            for x in range(0, length - (1 if d == 1 else 0)):
                r[x] = ('1' if jet else '3') if y < half else (('w' if not jet else '1') if d == 0 else ('0' if jet else '2'))
            r[length - 4] = 'd'
            if d == 0:
                r[length - 1] = 'w'
        rows.append(''.join(r))
    if jet:
        # The engine's pod, riding on the body at the back.
        for y in range(half - 2, half + 3):
            r = list(rows[y])
            for x in range(0, 8):
                r[x] = 'e'
            r[0] = 'n'
            if y == half - 1:
                for x in range(2, 7):
                    r[x] = 'w'
            rows[y] = ''.join(r)
    return rows


# Shahed-136 and the jet one (Geran-3 style), from above.
ATTACK = _delta(20, 8, 13)
JET = _delta(22, 8, 14, jet=True)

# 12 x 13: straight wings across the middle, a tailplane at the back, the
# propeller at the nose drawn on after the outline.
RECON = [
    "......##....",
    "......##....",
    "......##....",
    "......##....",
    "##....##....",
    ".##########.",
    "dw##########",
    ".##########.",
    "##....##....",
    "......##....",
    "......##....",
    "......##....",
    "......##....",
]

# 20 x 9.
CRUISE = [
    "........1...........",
    "........32..........",
    "#t......32..........",
    "d#################w.",
    "d###################",
    "d##################.",
    "#t......21..........",
    "........21..........",
    "........1...........",
]

# 20 x 9.
BALLISTIC = [
    "#t..................",
    "####................",
    ".###########d####w..",
    "d############d######",
    "d############d######",
    "d############d#####.",
    ".###########d####...",
    "####................",
    "#t..................",
]


def draw(rows, extra=None):
    img = Image.new('RGBA', (N, N), (0, 0, 0, 0))
    h = len(rows)
    w = len(rows[0])
    ox = (N - w) // 2
    oy = (N - h) // 2
    for y, row in enumerate(rows):
        for x, ch in enumerate(row):
            if ch == '.':
                continue
            k = y / max(1, h - 1)
            if ch == 'w':
                c = W
            elif ch == 'd':
                c = G0
            elif ch == 't':
                c = G1
            elif ch == 'e':
                c = (118, 124, 132)
            elif ch == 'n':
                c = (40, 40, 44)
            elif ch in '0123':
                c = (G0, G1, G2, G3)[int(ch)]
            elif k < 0.3:
                c = G3
            elif k < 0.55:
                c = W if abs(y - (h - 1) / 2) < 0.6 else G3
            elif k < 0.8:
                c = G2
            else:
                c = G1
            img.putpixel((ox + x, oy + y), c + (255,))
    outline(img)
    if extra:
        extra(img, ox, oy)
    return img


def outline(img):
    """A dark pixel round every shape, 4-connected."""
    src = img.copy().load()
    for y in range(N):
        for x in range(N):
            if src[x, y][3]:
                continue
            for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                xx, yy = x + dx, y + dy
                if 0 <= xx < N and 0 <= yy < N and src[xx, yy][3] and src[xx, yy][:3] != K:
                    img.putpixel((x, y), K + (255,))
                    break


def prop_back(img, ox, oy):
    # The pusher propeller: a faint blur across the back of the body.
    for y in range(4, 13):
        img.putpixel((ox - 2, oy + y), G3 + (140 if y in (4, 12) else 200,))


def prop_nose(img, ox, oy):
    for y in range(4, 9):
        img.putpixel((ox + 13, oy + y), G3 + (150 if y in (4, 8) else 210,))


def build():
    sheet = Image.new('RGBA', (N * 5, N), (0, 0, 0, 0))
    for i, img in enumerate([draw(ATTACK, prop_back), draw(RECON, prop_nose), draw(CRUISE), draw(BALLISTIC), draw(JET)]):
        sheet.paste(img, (i * N, 0))
    return sheet


if __name__ == '__main__':
    out = build()
    out.save('assets/ui/weapons.png')
    if '--preview' in sys.argv:
        p = sys.argv[sys.argv.index('--preview') + 1]
        big = Image.new('RGBA', (N * 5 * 8, N * 8 + N * 2), (40, 48, 40, 255))
        big.paste(out.resize((N * 5 * 8, N * 8), Image.NEAREST), (0, 0), out.resize((N * 5 * 8, N * 8), Image.NEAREST))
        # Also at true size, tinted red and blue, on a terrain-ish ground.
        for i in range(5):
            cell = out.crop((i * N, 0, i * N + N, N))
            for j, tint in enumerate([(1.0, 0.45, 0.42), (0.5, 0.7, 1.0)]):
                px = cell.load()
                t = Image.new('RGBA', (N, N))
                tp = t.load()
                for y in range(N):
                    for x in range(N):
                        r, g, b, a = px[x, y]
                        if (r, g, b) == K:
                            tp[x, y] = (r, g, b, a)
                        else:
                            tp[x, y] = (int(r * tint[0]), int(g * tint[1]), int(b * tint[2]), a)
                big.paste(t, (i * N * 2 + j * N, N * 8 + N // 2), t)
        big.save(p)
    print('ok', out.size)
