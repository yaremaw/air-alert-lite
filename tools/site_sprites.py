"""Builds assets/ui/sites.png: the map's site sprites, 16x16 pixel art each,
in the order of LiteKind (CAPITAL, FACTORY, GUN, SAM, DEPOT, RADAR, LAUNCHER,
POWER, JAMMER), standing in the top row and damaged in the bottom row; and
(the 16-pixel flying weapons below are kept only for the preview; the
game's are 32-pixel, from tools/weapon_sprites.py). Drawn by hand below, one
character a pixel.

    python tools/site_sprites.py [--preview out.png]
"""
import sys
from PIL import Image

PAL = {
    '.': None,
    'k': (16, 20, 26),     # outline
    'g': (58, 66, 80),     # dark grey
    'G': (95, 108, 124),   # grey
    'l': (150, 162, 176),  # light grey
    'w': (222, 228, 236),  # white
    'y': (255, 204, 85),   # lit window
    'o': (240, 138, 58),   # orange
    'r': (226, 74, 58),    # red light
    'b': (74, 93, 120),    # slate roof
    'B': (106, 128, 158),  # light slate
    'n': (52, 62, 38),     # dark olive
    'N': (93, 107, 61),    # olive
    'M': (128, 144, 92),   # light olive
    'd': (98, 74, 48),     # dark earth
    'D': (143, 115, 80),   # earth
    'c': (69, 209, 224),   # cyan
    's': (176, 184, 196),  # steam
}

SPRITES = {
'CAPITAL': [
"........r.......",
".......kgk......",
".......kwk......",
"......kwlwk.....",
".....kwllllk....",
"....kkkkkkkkk...",
"...kwwwwwwwwwk..",
"...kwGwGwGwGwk..",
"..kwwwwwwwwwwwk.",
"..kwGkGkwkGkGwk.",
"..kwGkGkwkGkGwk.",
"..kwGkGkwkGkGwk.",
"..kwwwwkkkwwwwk.",
".kllllllllllllk.",
".kkkkkkkkkkkkkk.",
"................",
],
'FACTORY': [
"...........kk...",
"...........kgk..",
"...........kgk..",
"..k...k....kgk..",
".kbk.kbk..kbgk..",
"kbBbkbBbkkbBbk..",
"kbbbbbbbbbbbbbk.",
"kGGGGGGGGGGGGGk.",
"kGyyGyyGyyGyyGk.",
"kGyyGyyGyyGyyGk.",
"kGGGGGGGGGGGGGk.",
"kGGkkkkGGGGGGGk.",
"kGGkggkGGGGGGGk.",
"kkkkkkkkkkkkkkk.",
"................",
"................",
],
# A self-propelled anti-aircraft gun: tracked hull, twin autocannons, radar dish.
'GUN': [
"................",
"..kkk.......k.k.",
".kwlwk.....klkl.",
"..kkk.....klklk.",
"...k.....klklk..",
"..kkkkkkklklk...",
".kMMMMMMkGlk....",
".kNNNNNNNGk.....",
".kNnNNNNNNk.....",
"kkkkkkkkkkkkkkk.",
"kMNNNNNNNNNNNNNk",
"kNNnNNNNNNNNNNk.",
".kkkkkkkkkkkkk..",
".kgGkGkGkGkGgk..",
"..kkkkkkkkkkk...",
"................",
],
# A SAM launcher (S-300V-like): a tracked chassis, its pack of launch tubes
# standing upright at the back end (left), the radar's mast raised at the
# front (right) with its panel on top (the panel turns: see LiteCmdView).
'SAM': [
"kkkkk......kkkk.",
"kwlwk......kllk.",
"kMNNk......kMlk.",
"kMNNk......kkkk.",
"kMNNk.......kNk.",
"kMNNk.......kNk.",
"kMNNk.......kNk.",
"kMNNk.......kNk.",
"kMNNkk......kNk.",
"kMNNkNk.....kNk.",
"kMNNkkkkkkkkkkkk",
"kMNNkMMMMMMMMMMk",
"kMNNkNNnNNNNNNNk",
"kkkkkkkkkkkkkkkk",
".kgGkGkGkGkGkgk.",
"..kkkkkkkkkkkk..",
],
'DEPOT': [
"................",
"................",
"......kkkkk.....",
"....kkDDDDDkk...",
"...kDDMDDDMDDk..",
"..kDDDDDDDDDDDk.",
"..kDDDkkkkkDDDk.",
".kDDDkgggggkDDDk",
".kkkkkkkkkkkkkkk",
"..kkkk.kkkk.....",
"..kNNk.kNNk.....",
"..kMNk.kMNk.....",
"..kkkk.kkkk.....",
"................",
"................",
"................",
],
# A long-range radar: a wide antenna array on a lattice mast over its
# shelter (the array turns; see LiteCmdView).
'RADAR': [
"................",
"..kkkkkkkkkkkk..",
".kwlwlwlwlwlwlk.",
".kGlGlGlGlGlGlk.",
"..kkkkkkkkkkkk..",
"......kggk......",
"......kgGk......",
".....kgkkGk.....",
".....kGkkgk.....",
"....kgk..kGk....",
"...kkkkkkkkkkk..",
"...kBBBBBBBBBk..",
"...kbbbbbbrbbk..",
"...kbbkkbbbbbk..",
"..kkkkkkkkkkkkk.",
"................",
],
'LAUNCHER': [
"..............kk",
".............kwk",
"...........kkwk.",
"..........kwwk..",
"........kkggk...",
"......kkggk.....",
"....kkggk.......",
"...kggk.........",
".kkkkkkkkkkkk...",
".kNNNNNNNkMMk...",
".kNnNNNNNkwwk...",
".kkkkkkkkkkkk...",
".kgk..kgk.kgk...",
"..k....k...k....",
"................",
"................",
],
'POWER': [
"..sss...........",
".sssss....kk....",
"sssssss...krk...",
".kkkkkk...kwk...",
".kGGGGk...krk...",
"..kGGk....kwk...",
"..kGGk....krk...",
"..kGGk....kwk...",
".kGGGGk...kwk...",
"kGGGGGGk..kwk...",
"kGGGGGGkkkkkkk..",
"kGlGGGGkGGGGGk..",
"kkkkkkkkkkkkkk..",
"................",
"................",
"................",
],
'JAMMER': [
"..k......k......",
".kck....kck.....",
"..k..c...k..c...",
"..k......k......",
"..k.c....k.c....",
"..k......k......",
".kkkkkkkkkkk....",
".kGGGGGGGGGkkk..",
".kGcGcGGGGGkwk..",
".kGGGGGGGGGkMk..",
".kkkkkkkkkkkkk..",
".kgk....kgk.kgk.",
"..k......k...k..",
"................",
"................",
"................",
],
# A technical: a pickup, its cab at the front with its windows, the open
# bed behind with a heavy machine gun on a post, its shield, the barrel
# over the cab.
'MOBILE': [
"................",
"................",
"....kk..........",
"...kGk..........",
".kkkGkkkkkkkkkk.",
".kgkGlllllllllk.",
".kkkGkkkkkkkkkk.",
"...kGk..kkkkk...",
"....kk.kNNNNNk..",
"kkkkgkkNBkBBBkkk",
"kMMMgMMNBkBBBNNk",
"kNNNNNNNNNNNNNNk",
"kNnNNDNNNNNNnNNk",
"kkkkgggkkkkgggkk",
"...kgGgk..kgGgk.",
"....kkk....kkk..",
],
# A mobile radar: a truck with a flat phased-array panel raised on its mount.
'MRADAR': [
"................",
"......kkkkkkk...",
".....kllwlllk...",
"....klGlGlGlk...",
"....kllGlGllk...",
"...klGlGlGlk....",
"...kllllllk.....",
"....kkkgkk......",
"......kgk.......",
".kkkkkkkkkkkkkk.",
".kNNNNNNNNNkMwk.",
".kNnNnNNNNNkwwk.",
".kkkkkkkkkkkkkk.",
"..kgk.kgk..kgk..",
"...k...k....k...",
"................",
],
# An oil well's pumpjack: the walking beam on its A-frame, the horsehead at
# the left over the well, the motor and counterweight on the right.
'OILRIG': [
"................",
".kkk............",
"kDDDkkk.........",
"kDdkDDDkkk......",
".kk.kkDDDDkk....",
".kgk...kkDDDkk..",
".kgk...kgkkDDk..",
".kgk..kgkgk.kkk.",
".kgk..kgkgk.kGGk",
".kgk.kgk.kgkkGGk",
"kkgkkkgk.kgkkkkk",
"kGGGkkkkkkkkkGGk",
"kkkkkDDDDDDDDDDk",
"....kkkkkkkkkkkk",
"................",
"................",
],
# A refinery: two storage tanks, a distillation column, a flare burning.
'REFINERY': [
"...........kk...",
"..........koyk..",
"...........kk...",
"....kk.....kk...",
"...klGk....klk..",
"...kGgk....klk..",
"...klGk....klk..",
"...kGgk..kkklk..",
"...klGk.klllkGk.",
"..kkkkkkkGGGkGk.",
".kwllk.kwlkGkGk.",
".klGGk.klGkkkkk.",
".kGGgk.kGgkGGGk.",
"kkkkkkkkkkkkkkkk",
"................",
"................",
],
# A power substation: a gantry with insulators over two transformers.
'SUBSTATION': [
"................",
".kkkkkkkkkkkkkk.",
".kGkkwkkkkwkkGk.",
".kGk.kk..kk.kGk.",
".kGk.......kkGk.",
".kGk........kGk.",
".kGk........kGk.",
"kkkkkkk.kkkkkkk.",
"kGlGlGk.kGlGlGk.",
"kGGGGGk.kGGGGGk.",
"kGlGlGk.kGlGlGk.",
"kgggggk.kgggggk.",
"kkkkkkkkkkkkkkk.",
"kDDDDDDDDDDDDDk.",
"kkkkkkkkkkkkkkk.",
"................",
],
# A pumping station: the pump house and its big pipe down to the water.
'PUMP': [
"................",
"................",
"....kkkkkkk.....",
"...kbbbbbbbk....",
"..kbBBBBBBBbk...",
"..kkkkkkkkkkk...",
"..kGGGGGGGGGk...",
"..kGyGGGyGGGk...",
"..kGGGkkkGGGkkkk",
"..kGGGkgkGGGklGk",
"..kkkkkkkkkkklGk",
"............klGk",
"...........kklGk",
"...........kcccc",
"...........kkkkk",
"................",
],
# A grain elevator: a row of silos and the tall working house beside them.
'SILO': [
"......kkk.......",
".....kwGk.......",
".kkk.klGk.......",
"kwlGkklGkkkkk...",
"klGGkklGkkwlGk..",
"kwlGkklGkklGGk..",
"klGGkklGkkwlGk..",
"kwlGkklGkklGGk..",
"klGGkklGkkwlGk..",
"kwlGkklGkklGGk..",
"klGGkklGkkwlGk..",
"kkkkkkkkkkkkkkk.",
"kDDDDDDDDDDDDDk.",
"kkkkkkkkkkkkkkk.",
"................",
"................",
],

# The driving guns side on, for the map: as GUN and MOBILE without their
# barrels (the game draws those, turned to where the gun aims; the hull is
# mirrored when it faces left). Their mounts: GUN_SIDE's turret front at
# (9.5, 8.5), MOBILE_SIDE's gun at (5.5, 5.5).
'GUN_SIDE': [
"................",
"................",
"................",
"..kkk...........",
".kwlwk..........",
"..kkk...........",
"...k............",
"..kkkkkkkkk.....",
".kMMMMMMMMk.....",
".kNNNNNNNNNk....",
"kkkkkkkkkkkkkkk.",
"kMNNNNNNNNNNNNNk",
"kNNnNNNNNNNNNNk.",
".kkkkkkkkkkkkk..",
".kgGkGkGkGkGgk..",
"..kkkkkkkkkkk...",
],
'MOBILE_SIDE': [
"................",
"................",
"....kk..........",
"...kGk..........",
".kkkGkk.........",
".kgkGlk.........",
".kkkGkk.........",
"...kGk..kkkkk...",
"....kk.kNNNNNk..",
"kkkkgkkNBkBBBkkk",
"kMMMgMMNBkBBBNNk",
"kNNNNNNNNNNNNNNk",
"kNnNNDNNNNNNnNNk",
"kkkkgggkkkkgggkk",
"...kgGgk..kgGgk.",
"....kkk....kkk..",
],

}

ORDER = ['CAPITAL', 'FACTORY', 'GUN', 'SAM', 'DEPOT', 'RADAR', 'LAUNCHER', 'POWER', 'JAMMER',
         'MOBILE', 'MRADAR', 'OILRIG', 'REFINERY', 'SUBSTATION', 'PUMP', 'SILO',
         'GUN_SIDE', 'MOBILE_SIDE']

# Flying weapons, nose to the right, in light greys: the game tints them by
# side (ours blue, theirs red), so the outline stays dark and the body takes
# the colour. Order: attack drone, recon drone, cruise missile, ballistic.
WEAPONS = {
'ATTACK': [
"................",
"..kk............",
"..kwk...........",
"..kwlk..........",
".kkwllk.........",
"kgkkwllkk.......",
"kgkkwlllllkkk...",
"kgggklllllllwkk.",
"kgkkwlllllkkk...",
"kgkkwllkk.......",
".kkwllk.........",
"..kwlk..........",
"..kwk...........",
"..kk............",
"................",
"................",
],
'RECON': [
"................",
"................",
"................",
".......kk.......",
".......kwk......",
".kk....kwk......",
".kwk...kwk...kk.",
"kkwkkkkkwlkkkwgk",
"kkwkkkkkwlkkkwgk",
".kwk...kwk...kk.",
".kk....kwk......",
".......kwk......",
".......kk.......",
"................",
"................",
"................",
],
'CRUISE': [
"................",
"................",
"................",
"................",
"..kk............",
".kgk....kk......",
".kgkkkkkkwkkkk..",
"kgllllllllllwwkk",
"kglllllllllllkk.",
".kgkkkkkkwkkkk..",
".kgk....kk......",
"..kk............",
"................",
"................",
"................",
"................",
],
'BALLISTIC': [
"................",
"................",
"................",
"................",
"..k.............",
".kgk............",
"kgggkkkkkkkkk...",
"kgkkllllllllwkk.",
"gkklllllllllllwk",
"kgkkllllllllwkk.",
"kgggkkkkkkkkk...",
".kgk............",
"..k.............",
"................",
"................",
"................",
],
}
WEAPON_ORDER = ['ATTACK', 'RECON', 'CRUISE', 'BALLISTIC']

def _sheet(sprites, order):
    img = Image.new('RGBA', (16 * len(order), 16), (0, 0, 0, 0))
    for i, name in enumerate(order):
        rows = sprites[name]
        assert len(rows) == 16, name
        for y, row in enumerate(rows):
            row = row.ljust(16, '.')[:16]
            for x, ch in enumerate(row):
                c = PAL[ch]
                if c is not None:
                    img.putpixel((i * 16 + x, y), c + (255,))
    return img

def damaged(img):
    """The same sprites, hit: darker, scorched through, embers glowing."""
    out = img.copy()
    w, h = img.size
    for x in range(w):
        for y in range(h):
            r, g, b, a = img.getpixel((x, y))
            if a == 0:
                continue
            i, lx = x // 16, x % 16
            if (lx * 7 + y * 13 + i * 5) % 11 == 0:
                out.putpixel((x, y), (16, 20, 26, 255))
            elif (lx * 5 + y * 11 + i * 3) % 53 == 0:
                out.putpixel((x, y), PAL['o'] + (255,))
            elif (lx * 3 + y * 7 + i) % 71 == 0:
                out.putpixel((x, y), PAL['r'] + (255,))
            else:
                out.putpixel((x, y), (int(r * 0.62), int(g * 0.6), int(b * 0.58), 255))
    return out

def snowy(img):
    """The same sprites in winter: snow lying on every surface that faces up
    (the first pixel of a shape from the top in each column, and a little on
    the one under it)."""
    out = img.copy()
    w, h = img.size
    px = img.load()
    snow = (232, 238, 245)
    for x in range(w):
        for y in range(h):
            r, g, b, a = px[x, y]
            if a == 0 or (r, g, b) == PAL['k']:
                continue
            up = px[x, y - 1] if y > 0 else (0, 0, 0, 0)
            up2 = px[x, y - 2] if y > 1 else (0, 0, 0, 0)
            if up[3] == 0 or up[:3] == PAL['k']:
                if up2[3] == 0 or up2[:3] == PAL['k'] or up[3] == 0:
                    out.putpixel((x, y), snow + (255,))
            elif up[:3] != PAL['k'] and (up2[3] == 0 or up2[:3] == PAL['k']):
                out.putpixel((x, y), (int((r + snow[0]) / 2), int((g + snow[1]) / 2), int((b + snow[2]) / 2), 255))
    return out

def build() -> Image.Image:
    """Four rows: the sites as they stand, hit (see damaged), and both in
    winter (see snowy)."""
    row = _sheet(SPRITES, ORDER)
    img = Image.new('RGBA', (row.width, 64), (0, 0, 0, 0))
    img.paste(row, (0, 0))
    img.paste(damaged(row), (0, 16))
    win = snowy(row)
    img.paste(win, (0, 32))
    img.paste(damaged(win), (0, 48))
    return img

if __name__ == '__main__':
    img = build()
    img.save('assets/ui/sites.png')
    # The flying weapons are 32-pixel sprites now: tools/weapon_sprites.py.
    weapons = _sheet(WEAPONS, WEAPON_ORDER)
    if '--preview' in sys.argv:
        out = sys.argv[sys.argv.index('--preview') + 1]
        n = len(ORDER)
        big = Image.new('RGBA', (n * 136, 5 * 136), (40, 52, 70, 255))
        for r in range(4):
            for i in range(n):
                tile = img.crop((i * 16, r * 16, i * 16 + 16, r * 16 + 16)).resize((128, 128), Image.NEAREST)
                big.paste(tile, (i * 136, r * 136), tile)
        tints = [(1, 1, 1), (0.45, 0.75, 1.0), (1.0, 0.45, 0.4), (0.45, 0.75, 1.0)]
        for i in range(len(WEAPON_ORDER)):
            tile = weapons.crop((i * 16, 0, i * 16 + 16, 16))
            t = tints[i]
            px = tile.load()
            for x in range(16):
                for y in range(16):
                    r, g, b, a = px[x, y]
                    px[x, y] = (int(r * t[0]), int(g * t[1]), int(b * t[2]), a)
            tile = tile.resize((128, 128), Image.NEAREST)
            big.paste(tile, (i * 136, 4 * 136), tile)
        big.save(out)
    print('ok', img.size, weapons.size)
