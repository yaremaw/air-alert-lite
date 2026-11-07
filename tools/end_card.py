"""The end card for Strike Alert videos: the cover art (with the logo in it), one
"play free" button and the link, nothing else. Writes a still (PNG) and a 3-second
animated version (MP4, 60 fps, with the all-clear tone) in 9:16 and 16:9.

    python tools/end_card.py itch/shorts

Edit the TEXT block below to change the words.
"""
import os
import subprocess
import sys

import imageio_ffmpeg
import numpy as np
from PIL import Image, ImageDraw, ImageFont

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
FONT = os.path.join(ROOT, "assets", "fonts", "Inter.ttf")
ART = os.path.join(ROOT, "itch", "cover-pixel.png")
SOUND = os.path.join(ROOT, "assets", "audio", "all_clear.wav")
FF = imageio_ffmpeg.get_ffmpeg_exe()
FPS, SECS = 60, 3.0

PAGE = (0x10, 0x12, 0x18)
TEXT_C = (0xEE, 0xF0, 0xF3)
MUTED = (0x9A, 0xA0, 0xAC)
RED = (0xE8, 0x4B, 0x3C)

TEXT = dict(
    cta="PLAY FREE IN YOUR BROWSER",
    url="tenchery.itch.io/strike-alert",
)


def font(size, weight):
    f = ImageFont.truetype(FONT, size)
    f.set_variation_by_name(weight)
    return f


def text_img(text, f, fill):
    """A line of text on its own transparent image, trimmed to the letters plus a margin."""
    l, t, r, b = f.getbbox(text)
    img = Image.new("RGBA", (r - l + 8, b - t + 8), (0, 0, 0, 0))
    ImageDraw.Draw(img).text((4 - l, 4 - t), text, font=f, fill=fill)
    return img


def pill_img(text, f, colour):
    l, t, r, b = f.getbbox(text)
    h = round(f.size * 2.0)
    w = r - l + h
    img = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    d.rounded_rectangle([0, 0, w - 1, h - 1], radius=h // 2, fill=colour)
    d.text((w / 2, h / 2), text, font=f, fill=(255, 255, 255), anchor="mm")
    return img


class Item:
    """One element of the card: an image whose centre sits at (cx, cy), shown from `at` seconds."""

    def __init__(self, img, cx, cy, at, rise=26, pop=False):
        self.img, self.cx, self.cy, self.at, self.rise, self.pop = img, cx, cy, at, rise, pop

    def draw(self, canvas, t):
        k = 1.0 if t is None else min(max((t - self.at) / 0.42, 0.0), 1.0)
        if k <= 0:
            return
        e = 1 - (1 - k) ** 3
        img = self.img
        if self.pop and t is not None:
            if k < 1:
                s = 0.86 + 0.14 * e + 0.05 * np.sin(np.pi * k)
            else:     # once in, it breathes gently so the eye goes to it
                s = 1.0 + 0.035 * np.sin(2 * np.pi * 0.9 * (t - self.at - 0.42))
            img = img.resize((max(1, round(img.width * s)), max(1, round(img.height * s))), Image.LANCZOS)
        if e < 1:
            img = img.copy()
            img.putalpha(img.getchannel("A").point(lambda a: int(a * e)))
        dy = 0 if self.pop else round(self.rise * (1 - e))
        canvas.alpha_composite(img, (round(self.cx - img.width / 2), round(self.cy - img.height / 2 + dy)))


def fade_mask(w, h, edges):
    """An alpha mask, opaque in the middle and fading over `edges` = {side: pixels}."""
    m = np.ones((h, w), np.float32)
    ys, xs = np.arange(h, dtype=np.float32), np.arange(w, dtype=np.float32)
    for side, n in edges.items():
        if side == "top":
            m *= np.clip(ys / n, 0, 1)[:, None]
        elif side == "bottom":
            m *= np.clip((h - 1 - ys) / n, 0, 1)[:, None]
        elif side == "right":
            m *= np.clip((w - 1 - xs) / n, 0, 1)[None, :]
    m = m * m * (3 - 2 * m)
    return Image.fromarray((m * 255).astype(np.uint8))


class Card:
    def __init__(self, W, H, art_box, art_edges, items):
        self.W, self.H = W, H
        self.src = Image.open(ART).convert("RGB")
        self.art_box = art_box            # (x, y, w, h) on the card
        self.mask = fade_mask(art_box[2], art_box[3], art_edges)
        self.items = items
        self.crop0 = self.cover_crop(art_box[2], art_box[3])

    def cover_crop(self, w, h):
        """The part of the art that fills a w x h box (centred, keeping the top)."""
        sw, sh = self.src.size
        if sw / sh > w / h:
            cw = sh * w / h
            return ((sw - cw) / 2, 0.0, (sw + cw) / 2, float(sh))
        ch = sw * h / w
        return (0.0, 0.0, float(sw), ch)

    def frame(self, t=None):
        canvas = Image.new("RGBA", (self.W, self.H), PAGE + (255,))
        x, y, w, h = self.art_box
        z = 1.0 if t is None else 1.0 + 0.045 * (t / SECS)       # a slow push in
        x0, y0, x1, y1 = self.crop0
        cx, cy = (x0 + x1) / 2, (y0 + y1) / 2
        hw, hh = (x1 - x0) / 2 / z, (y1 - y0) / 2 / z
        art = self.src.resize((w, h), Image.LANCZOS, box=(cx - hw, cy - hh, cx + hw, cy + hh))
        if t is not None:
            k = min(t / 0.5, 1.0)
            art = Image.blend(Image.new("RGB", (w, h), PAGE), art, 1 - (1 - k) ** 2)
        canvas.paste(art, (x, y), self.mask)
        for it in self.items:
            it.draw(canvas, t)
        return canvas.convert("RGB")


def tall():
    """The cover art big, with the logo in it, then one button and the link. The bottom
    is left empty: TikTok and Reels put their own buttons and caption there."""
    W, H = 1080, 1920
    items = [Item(pill_img(TEXT["cta"], font(50, "Black"), RED), W / 2, 1395, 0.55, pop=True),
             Item(text_img(TEXT["url"], font(46, "Bold"), TEXT_C), W / 2, 1505, 0.8)]
    return Card(W, H, (0, 100, 1080, 1200), {"top": 110, "bottom": 300}, items)


def wide():
    """The cover art across the whole frame, the button and the link at the bottom."""
    W, H = 1920, 1080
    items = [Item(pill_img(TEXT["cta"], font(46, "Black"), RED), W / 2, 845, 0.55, pop=True),
             Item(text_img(TEXT["url"], font(42, "Bold"), TEXT_C), W / 2, 950, 0.8)]
    return Card(W, H, (0, 0, 1920, 1080), {"bottom": 430}, items)


def render(card, out_dir, tag):
    png = os.path.join(out_dir, "end-card-%s.png" % tag)
    card.frame(None).save(png)
    mp4 = os.path.join(out_dir, "end-card-%s.mp4" % tag)
    enc = subprocess.Popen([FF, "-hide_banner", "-loglevel", "error", "-y",
                            "-f", "rawvideo", "-pix_fmt", "rgb24", "-s", "%dx%d" % (card.W, card.H), "-r", str(FPS), "-i", "-",
                            "-i", SOUND,
                            "-filter_complex", "[1:a]atrim=0:%.2f,afade=t=out:st=%.2f:d=0.6,volume=0.7,aformat=channel_layouts=stereo[a]"
                            % (SECS, SECS - 0.6),
                            "-map", "0:v", "-map", "[a]", "-c:v", "libx264", "-preset", "slow", "-crf", "16",
                            "-pix_fmt", "yuv420p", "-colorspace", "bt709", "-color_primaries", "bt709", "-color_trc", "bt709",
                            "-c:a", "aac", "-b:a", "192k", "-shortest", "-movflags", "+faststart", mp4], stdin=subprocess.PIPE)
    for i in range(int(SECS * FPS)):
        enc.stdin.write(card.frame(i / FPS).tobytes())
    enc.stdin.close()
    enc.wait()
    print("wrote", png, mp4)


def main():
    out_dir = sys.argv[1] if len(sys.argv) > 1 else os.path.join(ROOT, "itch", "shorts")
    os.makedirs(out_dir, exist_ok=True)
    render(tall(), out_dir, "9x16")
    render(wide(), out_dir, "16x9")


if __name__ == "__main__":
    main()
