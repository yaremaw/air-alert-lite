"""Short videos of Strike Alert (about 25 s) from a scene recorded by
tools/record_short.py: one continuous take of the game at its own speed, a caption
for each beat, a title card as the first frames (it doubles as the thumbnail) and
an end card. Writes a 9:16 cut (Reels, TikTok, Shorts) and a 16:9 one, plus both
thumbnails as PNG.

    python tools/record_short.py sam REC
    python tools/short_video.py sam REC itch/shorts

Needs ffmpeg (pip install imageio-ffmpeg).
"""
import math
import os
import subprocess
import sys

import imageio_ffmpeg
import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageFont

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
FONT = os.path.join(ROOT, "assets", "fonts", "Inter.ttf")
LOGO = os.path.join(ROOT, "itch", "logo-v2.png")
ALL_CLEAR = os.path.join(ROOT, "assets", "audio", "all_clear.wav")
FF = imageio_ffmpeg.get_ffmpeg_exe()
FPS = 30
THUMB_S, END_S, FADE_S = 0.7, 2.6, 0.3
PAGE = (0x16, 0x18, 0x1D)
TEXT = (0xE8, 0xEA, 0xEE)
MUTED = (0x8B, 0x91, 0x9D)
RED = (0xE8, 0x4B, 0x3C)
YELLOW = (0xE5, 0xAD, 0x16)
BLUE = (0x4E, 0xA1, 0xFF)
GOOD = (0x46, 0xC4, 0x7E)

# Each video: the take (from marker + seconds to marker + seconds), where the 9:16 cut's
# square sits in the frame, the topic pill, the title card (marker + seconds for its
# frame, title lines), and the captions (from marker + seconds, headline, small line,
# sites to point out: (index in the recording's track.txt, tag)): each caption stays up
# until the next.
VIDEOS = {
    "sam": dict(
        take=("start", 0.0, "end", 0.0),
        square_x=195,
        pill=("STRIKE BACK", YELLOW),
        title=("hit", 0.45, ["HOW TO GET", "PAST A SAM"]),
        captions=[
            ("start", 0.0, "Their factory is guarded by a SAM", "The red circle is how far the SAM can shoot",
             [(0, "SAM"), (1, "FACTORY")]),
            ("straight", 0.0, "Three cruise missiles, straight in", None, []),
            ("straight", 2.5, "The SAM shoots down all three", None, []),
            ("route", 0.0, "Now draw a route around its reach", None, []),
            ("route", 2.9, "Same three missiles, the long way round", None, []),
            ("hit", 0.0, "All three get through. Factory destroyed.", None, []),
        ],
    ),
    "drones": dict(
        take=("start", 0.0, "end", 0.0),
        square_x=40,
        pill=("AIR DEFENCE", BLUE),
        title=("guns", 3.2, ["8 DRONES", "VS 4 AA GUNS"]),
        captions=[
            ("start", 0.0, "Eight enemy drones cross the front", "You only see them once they're over your land", []),
            ("alert", 0.3, "Every region they fly over goes on alert", "Yellow means drones overhead", []),
            ("guns", 0.0, "Four AA guns stand in their way", None, [(1, ""), (2, ""), (3, ""), (4, "")]),
            ("guns", 4.0, "Each shot has a 1 in 4 chance", "Drones are slow, so the guns get many tries", []),
            ("last", 0.0, "All eight down. None reached the factory.", None, [(0, "FACTORY")]),
            ("clear", 0.0, "All clear. The map goes grey again.", None, []),
        ],
    ),
}


def font(size, weight):
    f = ImageFont.truetype(FONT, size)
    f.set_variation_by_name(weight)
    return f


def logo(width):
    lg = Image.open(LOGO).convert("RGBA")
    return lg.resize((width, round(lg.height * width / lg.width)), Image.LANCZOS)


def wrap(text, f, width):
    """One line if it fits, else two of about the same width."""
    if f.getlength(text) <= width:
        return [text]
    words = text.split()
    best = None
    for i in range(1, len(words)):
        a, b = " ".join(words[:i]), " ".join(words[i:])
        w = max(f.getlength(a), f.getlength(b))
        if best is None or w < best[0]:
            best = (w, [a, b])
    return best[1]


def pill(d, x, y, text, colour, f, anchor="mm"):
    tw = f.getlength(text)
    h = f.size * 1.75
    x0 = x - tw / 2 - h * 0.5 if anchor == "mm" else x
    d.rounded_rectangle([x0, y - h / 2, x0 + tw + h, y + h / 2], radius=h / 2, fill=colour)
    d.text((x0 + tw / 2 + h / 2, y), text, font=f, fill=PAGE if colour in (YELLOW, GOOD) else (255, 255, 255),
           anchor="mm")


def markers(path):
    marks = {}
    with open(path, encoding="utf-8") as f:
        for line in f:
            parts = line.split()
            if len(parts) >= 3 and parts[2].isdigit():
                marks[parts[1]] = int(parts[2])
    return marks


def track(path):
    """frame -> [(x, y), ...]: where the scene's key sites were in the recorded frame."""
    out = {}
    if not os.path.exists(path):
        return out
    with open(path, encoding="utf-8") as f:
        for line in f:
            parts = line.split()
            if len(parts) >= 2 and parts[1].isdigit():
                v = [float(x) for x in parts[2:]]
                out[int(parts[1])] = list(zip(v[0::2], v[1::2]))
    return out


def frames(movie, a, b, crop=None):
    """Decoded frames a..b-1 of the recording, as RGB arrays."""
    vf = "trim=start_frame=%d:end_frame=%d" % (a, b)
    if crop:
        vf += ",crop=%d:%d:%d:%d" % crop
    w, h = (crop[0], crop[1]) if crop else (1920, 1080)
    p = subprocess.Popen([FF, "-hide_banner", "-loglevel", "error", "-i", movie, "-vf", vf, "-frames:v", str(b - a),
                          "-f", "rawvideo", "-pix_fmt", "rgb24", "-"], stdout=subprocess.PIPE)
    n = w * h * 3
    while True:
        buf = p.stdout.read(n)
        if len(buf) < n:
            break
        yield np.frombuffer(buf, np.uint8).reshape(h, w, 3)
    p.wait()


# --- layouts ---------------------------------------------------------------------------------

class Tall:
    """1080x1920: the caption over the top, the footage as a square, the logo below."""
    W, H = 1080, 1920
    TOP = 430          # the footage square starts here

    def __init__(self, cfg):
        self.cfg = cfg
        base = Image.new("RGBA", (self.W, self.H), PAGE + (255,))
        d = ImageDraw.Draw(base)
        pill(d, self.W // 2, 78, cfg["pill"][0], cfg["pill"][1], font(32, "Black"))
        lg = logo(600)
        base.alpha_composite(lg, ((self.W - lg.width) // 2, 1610))
        d.text((self.W // 2, 1610 + lg.height + 46), "Free  ·  play in your browser on itch.io",
               font=font(30, "SemiBold"), fill=MUTED, anchor="mm")
        self.base = np.asarray(base.convert("RGB"), np.float32)

    def crop(self):
        return (1080, 1080, self.cfg["square_x"], 0)

    def place(self, x, y):
        return x - self.cfg["square_x"], y + self.TOP

    def frame(self, shot):
        out = self.base.copy()
        out[self.TOP:self.TOP + 1080] = shot
        return out

    def caption(self, headline, sub):
        img = Image.new("RGBA", (self.W, 330), (0, 0, 0, 0))
        d = ImageDraw.Draw(img)
        f = font(62, "Black")
        lines = wrap(headline, f, 960)
        y = 150 if sub or len(lines) > 1 else 182
        if sub and len(lines) > 1:
            y = 128
        for line in lines:
            d.text((self.W // 2, y), line, font=f, fill=(255, 255, 255), anchor="mm")
            y += 74
        if sub:
            d.text((self.W // 2, y - 6), sub, font=font(34, "SemiBold"), fill=MUTED, anchor="mm")
        return np.asarray(img, np.float32), 0     # the layer and its top in the frame

    def title(self, shot, lines):
        img = Image.fromarray(self.frame(shot).astype(np.uint8)).convert("RGBA")
        d = ImageDraw.Draw(img)
        d.rectangle([0, 0, self.W, self.TOP - 1], fill=PAGE)
        f = font(116, "Black")
        y = 140
        for i, line in enumerate(lines):
            d.text((self.W // 2, y), line, font=f, fill=(255, 255, 255) if i == 0 else RED, anchor="mm")
            y += 138
        return np.asarray(img.convert("RGB"), np.float32)

    def end(self):
        img = Image.new("RGBA", (self.W, self.H), PAGE + (255,))
        d = ImageDraw.Draw(img)
        lg = logo(880)
        img.alpha_composite(lg, ((self.W - lg.width) // 2, 720))
        pill(d, self.W // 2, 720 + lg.height + 120, "FREE ON ITCH.IO", GOOD, font(44, "Black"))
        d.text((self.W // 2, 720 + lg.height + 250), "Play in your browser", font=font(54, "Bold"), fill=TEXT, anchor="mm")
        d.text((self.W // 2, 720 + lg.height + 330), "tenchery.itch.io/strike-alert", font=font(40, "Medium"),
               fill=MUTED, anchor="mm")
        return np.asarray(img.convert("RGB"), np.float32)


class Wide:
    """1920x1080: the whole screen, the caption low on the left over a shadow."""
    W, H = 1920, 1080

    def __init__(self, cfg):
        self.cfg = cfg
        down = np.clip((np.arange(self.H) - 700) / 380, 0, 1) ** 1.3
        across = np.clip((1480 - np.arange(self.W)) / 200, 0, 1)
        self.shadow = (0.85 * down[:, None] * across[None, :])[..., None].astype(np.float32)

    def crop(self):
        return None

    def place(self, x, y):
        return x, y

    def frame(self, shot):
        return shot * (1 - self.shadow) + np.array(PAGE, np.float32) * self.shadow

    def caption(self, headline, sub):
        img = Image.new("RGBA", (1480, 300), (0, 0, 0, 0))
        d = ImageDraw.Draw(img)
        pill(d, 64, 70, self.cfg["pill"][0], self.cfg["pill"][1], font(30, "Black"), anchor="lm")
        d.text((64, 190), headline, font=font(62, "Black"), fill=(255, 255, 255), anchor="ls",
               stroke_width=3, stroke_fill=PAGE)
        if sub:
            d.text((66, 248), sub, font=font(34, "SemiBold"), fill=TEXT, anchor="ls", stroke_width=2, stroke_fill=PAGE)
        return np.asarray(img, np.float32), self.H - 300

    def title(self, shot, lines):
        img = Image.fromarray((shot * 0.5 + np.array(PAGE, np.float32) * 0.1).astype(np.uint8)).convert("RGBA")
        d = ImageDraw.Draw(img)
        f = font(150, "Black")
        y = 380
        for i, line in enumerate(lines):
            d.text((90, y), line, font=f, fill=(255, 255, 255) if i == 0 else RED, anchor="lm",
                   stroke_width=7, stroke_fill=PAGE)
            y += 170
        lg = logo(620)
        img.alpha_composite(lg, (92, y + 10))
        return np.asarray(img.convert("RGB"), np.float32)

    def end(self):
        img = Image.new("RGBA", (self.W, self.H), PAGE + (255,))
        d = ImageDraw.Draw(img)
        lg = logo(1000)
        top = 300
        img.alpha_composite(lg, ((self.W - lg.width) // 2, top))
        pill(d, self.W // 2, top + lg.height + 110, "FREE ON ITCH.IO", GOOD, font(44, "Black"))
        d.text((self.W // 2, top + lg.height + 220), "tenchery.itch.io/strike-alert", font=font(44, "Medium"),
               fill=MUTED, anchor="mm")
        return np.asarray(img.convert("RGB"), np.float32)


def point_out(img, lay, pts, marks_, alpha, t, f):
    """A white ring round each site named in the caption, with its name beside it."""
    over = Image.new("RGBA", (lay.W, lay.H), (0, 0, 0, 0))
    d = ImageDraw.Draw(over)
    pulse = 0.5 + 0.5 * math.sin(t * 5.0)
    for idx, tag in marks_:
        x, y = lay.place(*pts[idx])
        r = 30 + 5 * pulse
        d.ellipse([x - r, y - r, x + r, y + r], outline=(255, 255, 255, int(235 * alpha)), width=4)
        if not tag:
            continue
        tw = f.getlength(tag)
        x0, y0 = x + r + 10, y - 22
        if x0 + tw + 28 > lay.W - 12:          # no room on the right: put the name on the left
            x0 = x - r - 10 - tw - 28
        d.rounded_rectangle([x0, y0, x0 + tw + 28, y0 + 44], radius=22, fill=(255, 255, 255, int(235 * alpha)))
        d.text((x0 + 14 + tw / 2, y0 + 22), tag, font=f, fill=PAGE + (int(255 * alpha),), anchor="mm")
    o = np.asarray(over, np.float32)
    k = o[..., 3:] / 255
    return img * (1 - k) + o[..., :3] * k


# --- the cut ------------------------------------------------------------------------------------

def render(name, rec, out_dir, layout_cls, suffix):
    cfg = VIDEOS[name]
    lay = layout_cls(cfg)
    movie = os.path.join(rec, "movie.avi")
    marks = markers(os.path.join(rec, "markers.txt"))

    def at(m, s):
        return marks[m] + int(round(s * FPS))

    a, b = at(*cfg["take"][:2]), at(*cfg["take"][2:])
    caps = []
    for i, (m, s, head, sub, marks_) in enumerate(cfg["captions"]):
        start = at(m, s) - a
        end = (at(*cfg["captions"][i + 1][:2]) - a) if i + 1 < len(cfg["captions"]) else b - a
        layer, top = lay.caption(head, sub)
        caps.append((start, end, layer, top, marks_))
    where = track(os.path.join(rec, "track.txt"))
    tag_font = font(26, "Black")
    tm, ts, lines = cfg["title"]
    shot = next(frames(movie, at(tm, ts), at(tm, ts) + 1, lay.crop())).astype(np.float32)
    title = lay.title(shot, lines)
    end_card = lay.end()
    base = os.path.join(out_dir, "strike-alert-%s-%s" % (name, suffix))
    Image.fromarray(title.astype(np.uint8)).save(base + "-thumb.png")

    silent = base + "-video.mp4"
    enc = subprocess.Popen([FF, "-hide_banner", "-loglevel", "error", "-y", "-f", "rawvideo", "-pix_fmt", "rgb24",
                            "-s", "%dx%d" % (lay.W, lay.H), "-r", str(FPS), "-i", "-", "-c:v", "libx264",
                            "-preset", "slow", "-crf", "18", "-pix_fmt", "yuv420p", silent], stdin=subprocess.PIPE)

    def put(img):
        enc.stdin.write(np.clip(img, 0, 255).astype(np.uint8).tobytes())

    for _ in range(int(THUMB_S * FPS)):
        put(title)
    fade = int(FADE_S * FPS)
    last = None
    for k, shot in enumerate(frames(movie, a, b, lay.crop())):
        img = lay.frame(shot.astype(np.float32))
        for start, end, layer, top, marks_ in caps:
            if not (start - fade <= k < end + fade):
                continue
            # In over FADE_S, rising a little; out over FADE_S as the next comes in.
            if k < start:
                continue
            t_in = min(1.0, (k - start + 1) / fade)
            t_out = min(1.0, max(0.0, (end - k) / fade)) if end < b - a else 1.0
            alpha = min(t_in, t_out)
            rise = int(round((1 - t_in) ** 2 * 18))
            h = layer.shape[0]
            y0 = top + rise
            region = img[y0:y0 + h]
            la = layer[: region.shape[0], :, 3:] / 255 * alpha
            region[:, : layer.shape[1]] = region[:, : layer.shape[1]] * (1 - la) + layer[: region.shape[0], :, :3] * la
            if marks_ and (a + k) in where:
                img = point_out(img, lay, where[a + k], marks_, alpha, k / FPS, tag_font)
        put(img)
        last = img
    for k in range(int(END_S * FPS)):
        e = min(1.0, k / (0.4 * FPS))
        put(last * (1 - e) + end_card * e)
    enc.stdin.close()
    enc.wait()

    # The game's own sound under the take, a quiet all-clear over the end card.
    take_s = (b - a) / FPS
    final = base + ".mp4"
    graph = ("[0:a]atrim=%.3f:%.3f,asetpts=PTS-STARTPTS,afade=in:d=0.05,afade=out:st=%.3f:d=0.5,"
             "adelay=%d|%d[g];" % (a / FPS, b / FPS, take_s - 0.5, THUMB_S * 1000, THUMB_S * 1000)
             + "[1:a]aformat=sample_rates=48000:channel_layouts=stereo,volume=0.35,atrim=0:%.2f,"
               "afade=in:d=0.3,afade=out:st=%.2f:d=0.8,adelay=%d|%d[e];" % (END_S, END_S - 0.8,
                                                                            (THUMB_S + take_s - 0.2) * 1000,
                                                                            (THUMB_S + take_s - 0.2) * 1000)
             + "[g][e]amix=inputs=2:normalize=0,loudnorm=I=-16:TP=-1.5:LRA=11,aresample=48000[a]")
    subprocess.run([FF, "-hide_banner", "-loglevel", "error", "-y", "-i", movie, "-i", ALL_CLEAR, "-i", silent,
                    "-filter_complex", graph, "-map", "2:v", "-map", "[a]", "-c:v", "copy", "-c:a", "aac", "-b:a",
                    "192k", "-shortest", "-movflags", "+faststart", final], check=True)
    os.remove(silent)
    print("wrote", final)


def main():
    name, rec, out_dir = sys.argv[1], sys.argv[2], sys.argv[3]
    os.makedirs(out_dir, exist_ok=True)
    render(name, rec, out_dir, Tall, "9x16")
    render(name, rec, out_dir, Wide, "16x9")


if __name__ == "__main__":
    main()
