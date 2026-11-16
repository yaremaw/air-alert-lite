"""Builds assets/ui/terrain.png: the stamps the terrain is painted with (see
src/Lite/command/lite_terrain_bake.gdshader), one art pixel each, at the
same density as the site sprites (1.25 map units a pixel).

Row 0 (y 0, cells 8x8): trees: conifer, broadleaf, bush, dark conifer.
Row 1 (y 8, cells 16x12): mountains: peak, twin peak, hill, ridge.
Row 2 (y 20, cells 8x6): buildings, 4x4: house, apartment block, works,
grey-roofed house.

    python tools/terrain_sprites.py [--preview out.png]
"""
import sys
from PIL import Image

PAL = {
    '.': None,
    # trees
    'k': (17, 27, 21), 'd': (34, 57, 36), 'g': (52, 86, 48), 'h': (82, 118, 62), 't': (66, 48, 32),
    'D': (28, 45, 31),
    # rock
    'K': (34, 32, 36), 'S': (196, 196, 186), 'r': (146, 136, 116), 'R': (112, 104, 90), 'Q': (78, 72, 66),
    # buildings
    'o': (152, 74, 56), 'O': (112, 52, 42), 'w': (188, 178, 158), 'W': (136, 128, 114), 'y': (232, 196, 110),
    'G': (112, 118, 126), 'B': (82, 88, 96),
}

TREES = [
[  # conifer
"..k..",
".khk.",
".kgk.",
"khgdk",
"kgddk",
".kkk.",
"..t..",
],
[  # broadleaf
".kkk.",
"khhgk",
"khggk",
"kgddk",
".kdk.",
"..t..",
"..t..",
],
[  # bush
".....",
".....",
".....",
".kk..",
"khgk.",
"kgdk.",
".kk..",
],
[  # dark conifer
"..k..",
".kgk.",
".kdk.",
"kgdDk",
"kdDDk",
".kkk.",
"..t..",
],
]

MOUNTAINS = [
[  # peak
".......K.......",
"......KSK......",
".....KSrQK.....",
"....KrrRQQK....",
"...KrrRRQQQK...",
"..KrrRRRQQQQK..",
".KrrRRRRQQQQQK.",
"KrRRRRRRQQQQQQK",
"KKKKKKKKKKKKKKK",
],
[  # twin peak
"....K.....K....",
"...KSK...KSK...",
"..KrRQK.KrRQK..",
".KrrRQQKrRRQQK.",
".KrRRQQQRRRQQK.",
"KrrRRRQQRRQQQQK",
"KrRRRRQQQRQQQQK",
"KRRRRQQQQQQQQQK",
"KKKKKKKKKKKKKKK",
],
[  # hill
".........",
".........",
".........",
".........",
"...KKK...",
"..KrRQK..",
".KrRRQQK.",
"KrRRRQQQK",
"KKKKKKKKK",
],
[  # ridge
"...........",
"...........",
"....KK.....",
"...KSQK.K..",
"..KrRQQKQK.",
".KrRRQQQQQK",
"KrRRRRQQQQK",
"KRRRRQQQQQK",
"KKKKKKKKKKK",
],
]

HOUSES = [
[  # house
".kk.",
"kooO",
"kwwW",
"kkkk",
],
[  # apartment block
"kkkk",
"kGGB",
"kyWW",
"kWyW",
],
[  # works
"..kk",
"kkGk",
"kGGB",
"kWWW",
],
[  # grey-roofed house
".kk.",
"kGGB",
"kwyW",
"kkkk",
],
]

def put(img, ox, oy, rows):
    for y, row in enumerate(rows):
        for x, ch in enumerate(row):
            c = PAL[ch]
            if c is not None:
                img.putpixel((ox + x, oy + y), c + (255,))

def build():
    img = Image.new('RGBA', (64, 32), (0, 0, 0, 0))
    for i, t in enumerate(TREES):
        put(img, i * 8, 0, t)
    for i, m in enumerate(MOUNTAINS):
        put(img, i * 16, 8, m)
    for i, h in enumerate(HOUSES):
        put(img, i * 8, 20, h)
    return img

if __name__ == '__main__':
    img = build()
    img.save('assets/ui/terrain.png')
    if '--preview' in sys.argv:
        out = sys.argv[sys.argv.index('--preview') + 1]
        big = Image.new('RGBA', (64 * 10, 32 * 10), (60, 80, 52, 255))
        z = img.resize((640, 320), Image.NEAREST)
        big.paste(z, (0, 0), z)
        big.save(out)
    print('ok', img.size)
