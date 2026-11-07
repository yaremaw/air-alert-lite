"""A 3-minute video for a voice-over: six questions players ask about Strike Alert,
each answered with a staged scene recorded from the game. A cinematic cold open (the
3D interception from tools/intercept_video.py), a title, then for each question a
glitching question card and the scene, graded and grained, with a handheld camera that
shakes on every blast, a war-room HUD and short data tags. Ends on the end card.

    python tools/record_short.py drones REC/drones --rng=1
    python tools/record_short.py sam REC/sam --rng=1
    python tools/record_short.py bait REC/bait --rng=9 --lite-atsam=1 --lite-fwd=70 --boost=1
    python tools/record_short.py swarm REC/swarm --boost=1
    python tools/record_short.py tot REC/tot --boost=1
    python tools/record_short.py epic REC/epic --boost=1
    python tools/voiceover_video.py REC itch/voiceover

writes, in the output folder:
    strike-alert-voiceover-16x9.mp4   the video with music-free sound design, no voice
    strike-alert-voiceover-guide.mp4  720p, the script on screen in time, to read along
    strike-alert-voiceover-bed.wav    the sound on its own, for mixing under the voice
    strike-alert-voiceover.srt        the script as subtitles
The voice lines live in SHOTS below, each at a second inside its shot; the tool warns
when a line can't be read in the time before the next one.
Needs ffmpeg (pip install imageio-ffmpeg).
"""
import math
import os
import subprocess
import sys
import tempfile
import wave
from multiprocessing import Pool

import imageio_ffmpeg
import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageFont

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
FF = imageio_ffmpeg.get_ffmpeg_exe()
INTER = os.path.join(ROOT, "assets", "fonts", "Inter.ttf")
MONO = r"C:\Windows\Fonts\consolab.ttf"
LOGO = os.path.join(ROOT, "itch", "logo-v2.png")
INTERCEPT = os.path.join(ROOT, "itch", "strike-alert-intercept-16x9.mp4")
CLICK = os.path.join(ROOT, "assets", "audio", "click.wav")
FPS, SR = 30, 48000
W, H = 1920, 1080
GW, GH = 1280, 720
RED = (232, 75, 60)
BLUE = (78, 161, 255)
YELLOW = (229, 173, 22)
GOOD = (70, 196, 126)
TEXT = (232, 234, 238)
MUTED = (139, 145, 157)
WORDS_PER_S = 2.7   # a calm, clear read; the tool checks every line fits at this pace
CARD_MIN = 2.6

# The video, shot by shot. A clip is a stretch of a recording (seconds a..b) with the camera
# moving from box0 to box1 (x, y, width of the 16:9 part of the 1920x1080 frame it shows);
# tags are the HUD's data lines; vo the voice lines, at seconds into the shot.
SHOTS = [
    dict(kind="clip", src="intercept", a=0.0, b=12.9, box0=(20, 11, 1880), box1=(90, 50, 1760), bars=True,
         caption="03:00  ·  AIR RAID ALERT  ·  BALLISTIC THREAT",
         vo=[(0.3, "Three a.m."),
             (1.3, "Somewhere above the clouds, a missile is falling."),
             (4.7, "One interceptor. One shot."),
             (7.7, "That was the easy part."),
             (10.0, "The hard part is everything else.")]),
    dict(kind="title", dur=4.3,
         vo=[(0.6, "You keep asking how to win this. Okay.")]),

    dict(kind="card", n=1, q="Where do I put my air defence?", bg=("drones", 0.6)),
    dict(kind="clip", src="drones", a=0.6, b=18.6, box0=(0, 125, 1470), box1=(70, 190, 1240),
         tags=[(0.6, "CONTACT  ·  8 DRONES  ·  HEADING WEST"),
               (4.6, "AA GUN  $70  ·  HIT CHANCE vs DRONE 25%"),
               (11.0, "SAM  $240  ·  TWICE THE REACH OF A GUN"),
               (15.0, "RESULT  ·  8 DOWN  ·  0 HITS")],
         vo=[(0.3, "Not around the target. In front of it. On the way in."),
             (4.9, "Drones are slow. A gun hits one in four, but it gets lots of tries."),
             (10.8, "Guns up front, in layers. The SAM deeper, by what matters."),
             (15.6, "Eight in. Eight down.")]),

    dict(kind="card", n=2, q="How do I get through their air defence?", bg=("sam", 2.4)),
    dict(kind="clip", src="sam", a=2.4, b=21.5, box0=(0, 125, 1470), box1=(110, 200, 1250),
         tags=[(1.7, "3 × CRUISE  ·  $165  ·  STRAIGHT IN"),
               (6.1, "RESULT  ·  3 OF 3 SHOT DOWN"),
               (7.5, "3 × CRUISE  ·  ROUTE AROUND THE SAM"),
               (17.2, "RESULT  ·  FACTORY DESTROYED")],
         vo=[(0.3, "See that red circle? That's their SAM's reach."),
             (3.8, "Three cruise missiles, straight in."),
             (6.3, "Gone. A hundred and sixty-five bucks, gone."),
             (9.4, "Same three missiles. This time I draw the route around the circle."),
             (14.4, "Takes longer. Who cares."),
             (17.4, "Factory's gone.")]),

    dict(kind="card", n=3, q="Why send drones when I have ballistic missiles?", bg=("bait", 0.6)),
    dict(kind="clip", src="bait", a=0.6, b=19.5, box0=(0, 125, 1470), box1=(170, 250, 1120), rack=True,
         tags=[(1.2, "INCOMING  ·  BALLISTIC  ·  $130"),
               (2.5, "INTERCEPTED"),
               (5.6, "INCOMING  ·  DRONES  ·  $12 EACH"),
               (16.2, "OUR SAM  ·  DESTROYED")],
         vo=[(0.2, "A ballistic missile, coming for my factory."),
             (3.2, "My SAM takes it down."),
             (5.6, "Then: twelve-dollar drones. Lots of them."),
             (8.4, "A SAM carries six missiles. Then it has to reload."),
             (12.6, "Six missiles wasted on junk. Now the sky is open."),
             (16.9, "That's why drones.")]),

    dict(kind="card", n=4, q="Kill their air defence first, or go straight for the target?", bg=("swarm", 1.2)),
    dict(kind="clip", src="swarm", a=1.2, b=22.5, box0=(0, 125, 1470), box1=(190, 230, 1150), rack=True,
         tags=[(0.6, "INCOMING  ·  BALLISTIC  ·  TARGET: FACTORY"),
               (1.4, "INTERCEPTED"),
               (4.5, "INCOMING  ·  DRONE SWARM  ·  TARGET: AIR DEFENCE"),
               (11.8, "OUR SAM  ·  DESTROYED"),
               (15.4, "AIR DEFENCE LEFT  ·  0"),
               (18.5, "FACTORY  ·  DESTROYED")],
         vo=[(0.2, "Straight for the target?"),
             (2.4, "Shot down. Never had a chance."),
             (5.1, "So they do it properly. The drones hit my guns and SAMs first."),
             (10.3, "Not the factory. The things protecting it."),
             (15.5, "Both SAMs gone."),
             (17.0, "Now the missile walks in."),
             (19.3, "Air defence first. Always.")]),

    dict(kind="card", n=5, q="Which missile is the best?", bg=("tot", 0.5)),
    dict(kind="specs", dur=12.6, bg=("tot", 0.5), at=(0.0, 4.0, 8.0),
         vo=[(0.3, "Drones: cheap, slow, and they set off alerts everywhere."),
             (4.1, "Cruise missiles: fast, accurate, and a SAM loves them."),
             (8.1, "Ballistic: guns can't touch it, and SAMs miss half the time.")]),
    dict(kind="clip", src="tot", a=0.5, b=13.9, box0=(60, 30, 1800), box1=(260, 120, 1480),
         tags=[(0.5, "TIME ON TARGET  ·  16 DRONES  ·  6 CRUISE  ·  4 BALLISTIC"),
               (9.6, "IMPACT  ·  14 HITS IN 0.1 SECONDS")],
         vo=[(0.3, "So which one's the best? Wrong question."),
             (3.3, "The best is all three. Different directions, different speeds..."),
             (7.2, "...landing in the same second."),
             (10.8, "Twenty-six targets. One SAM. No chance.")]),

    dict(kind="card", n=6, q="Are factories worth hitting? What if I destroy them all?", bg=("epic", 2.0)),
    dict(kind="clip", src="epic", a=2.0, b=25.3, box0=(0, 0, 1880), box1=(200, 110, 1520),
         tags=[(0.3, "FACTORY  ·  +$4 A SECOND  ·  REPAIRS THE CAPITAL"),
               (6.4, "DESTROYED FACTORY  ·  SITE DEAD FOR 3 MINUTES"),
               (14.0, "TARGETS  ·  EVERY SAM, GUN AND FACTORY"),
               (18.3, "ENEMY INCOME  ·  $3 A SECOND  ·  REPAIRS 0")],
         vo=[(0.3, "Every factory makes them four dollars a second."),
             (3.7, "And it keeps repairing their capital."),
             (6.4, "Destroy one, and nothing gets built there for three minutes."),
             (14.0, "Now. Destroy all of them."),
             (18.3, "Their whole income? Three dollars a second. No repairs.")]),

    dict(kind="end", dur=9.0,
         vo=[(0.2, "That's when you go for the capital."),
             (3.4, "Strike Alert. It's free on itch.io."),
             (6.4, "Hold the sky. Strike back.")]),
]
N_Q = sum(1 for s in SHOTS if s["kind"] == "card")


# ---------------------------------------------------------------- helpers

def est(text):
    """Seconds to read a line aloud at a calm pace."""
    return 0.3 + len(text.replace("...", " ").split()) / WORDS_PER_S


def font(size, weight="Bold"):
    f = ImageFont.truetype(INTER, size)
    f.set_variation_by_name(weight)
    return f


def mono(size):
    return ImageFont.truetype(MONO if os.path.exists(MONO) else INTER, size)


def wrap(text, f, width):
    words, lines, cur = text.split(), [], ""
    for w in words:
        t = (cur + " " + w).strip()
        if f.getlength(t) <= width or not cur:
            cur = t
        else:
            lines.append(cur)
            cur = w
    return lines + [cur] if cur else lines


def smooth(x):
    x = min(max(x, 0.0), 1.0)
    return x * x * (3 - 2 * x)


def movie_of(rec, src):
    return INTERCEPT if src == "intercept" else os.path.join(rec, src, "movie.avi")


def read_frames(path, a, n):
    """n decoded frames from frame a of a recording, as uint8 arrays."""
    p = subprocess.Popen([FF, "-hide_banner", "-loglevel", "error", "-i", path, "-vf",
                          "trim=start_frame=%d:end_frame=%d,setpts=PTS-STARTPTS,scale=%d:%d" % (a, a + n, W, H),
                          "-frames:v", str(n), "-f", "rawvideo", "-pix_fmt", "rgb24", "-"], stdout=subprocess.PIPE)
    last = None
    for _ in range(n):
        buf = p.stdout.read(W * H * 3)
        if len(buf) < W * H * 3:
            break
        last = np.frombuffer(buf, np.uint8).reshape(H, W, 3)
        yield last
    p.stdout.close()
    p.wait()


def fx_log(rec, src):
    """[(frame, kind, size)] of a recording's effects; kind 0 is a blast."""
    path = os.path.join(rec, src, "fx.txt")
    out = []
    if os.path.exists(path):
        for line in open(path, encoding="utf-8"):
            p = line.split()
            if len(p) >= 5 and p[0] == "[fx]":
                out.append((int(p[1]), int(p[2]), float(p[4])))
    return out


def ammo_log(rec, src):
    """frame -> missiles left in the watched SAM (-1 once it is destroyed)."""
    path = os.path.join(rec, src, "ammo.txt")
    out = {}
    if os.path.exists(path):
        for line in open(path, encoding="utf-8"):
            p = line.split()
            if len(p) >= 3 and p[0] == "[ammo]":
                out[int(p[1])] = int(p[2])
    return out


def timeline(quiet=False):
    """Each shot's duration in frames, its first frame, and every voice line in seconds."""
    q = 0
    for s in SHOTS:
        if s["kind"] == "card":
            q = s["n"]
        s["q_n"] = q
    for s in SHOTS:
        if s["kind"] == "card":
            s["dur"] = max(CARD_MIN, 0.75 + est(s["q"]))
            s["vo"] = [(0.3, s["q"])]
        elif s["kind"] == "clip":
            s["dur"] = s["b"] - s["a"]
        s["frames"] = int(round(s["dur"] * FPS))
    f0 = 0
    for s in SHOTS:
        s["f0"] = f0
        f0 += s["frames"]
    cues = []
    for i, s in enumerate(SHOTS):
        for t, text in s["vo"]:
            cues.append([s["f0"] / FPS + t, text, i])
    cues.sort()
    for k, c in enumerate(cues):
        nxt = cues[k + 1][0] if k + 1 < len(cues) else f0 / FPS
        c.append(min(c[0] + est(c[1]), nxt - 0.05))
        if c[0] + est(c[1]) > nxt + 0.05 and not quiet:
            print("warning: %.1fs \"%s\" needs %.1fs, has %.1fs" % (c[0], c[1], est(c[1]), nxt - c[0]))
    return f0, cues


# ---------------------------------------------------------------- look

def make_vignette():
    """The vignette as a 0..128 scale, in integers (so 255 x 128 still fits an int16)."""
    y, x = np.mgrid[0:H, 0:W].astype(np.float32)
    r = np.sqrt(((x - W / 2) / (W / 2)) ** 2 + ((y - H / 2) / (H / 2)) ** 2)
    v = 1.0 - 0.42 * np.clip(r - 0.35, 0, None) ** 1.6
    return np.round(v * 128).astype(np.int16)[..., None]


def make_grain(rng):
    small = rng.normal(0, 1, (H // 2, W // 2)).astype(np.float32)
    g = np.asarray(Image.fromarray(small).resize((W, H), Image.BILINEAR), np.float32)
    return np.round(g * 7.0).astype(np.int16)[..., None]


def make_luts():
    """Per channel: more contrast, cold shadows, warm highlights."""
    v = np.arange(256, dtype=np.float32)
    base = (v - 128.0) * 1.12 + 128.0
    shadow = np.clip((110 - v) / 110, 0, 1)
    high = np.clip((v - 140) / 115, 0, 1)
    luts = []
    for cold, warm in ((-4.0, 6.0), (1.0, 2.0), (7.0, -5.0)):
        luts.append(np.clip(base + shadow * cold * 1.4 + high * warm, 0, 255).astype(np.uint8))
    return luts


class Look:
    def __init__(self, seed):
        self.rng = np.random.default_rng(seed)
        self.vig = make_vignette()
        self.grains = [make_grain(self.rng) for _ in range(5)]
        self.luts = make_luts()

    def grade(self, f, flash=0.0, chroma=0):
        """Contrast, a cold tint in the shadows and warm highlights, vignette, grain."""
        x = np.empty(f.shape, np.int16)
        for c in range(3):
            x[:, :, c] = self.luts[c][f[:, :, c]]
        if flash > 0:
            k = int(flash * 0.55 * 128)
            x += ((255 - x) * k >> 7) + int(flash * 40)
        x *= self.vig
        x >>= 7
        x += self.grains[self.rng.integers(len(self.grains))]
        np.clip(x, 0, 255, out=x)
        out = x.astype(np.uint8)
        if chroma:
            out[:, :, 0] = np.roll(out[:, :, 0], chroma, axis=1)
            out[:, :, 2] = np.roll(out[:, :, 2], -chroma, axis=1)
        return out

    def glitch(self, img, s):
        """Torn scan lines, split colour and blocks of static; s from 0 to 1."""
        if s <= 0:
            return img
        rng = self.rng
        out = img.copy()
        for _ in range(int(3 + 14 * s)):
            y = int(rng.integers(0, H))
            h = int(rng.integers(3, int(8 + 90 * s)))
            out[y:y + h] = np.roll(out[y:y + h], int(rng.normal(0, 90 * s)), axis=1)
        k = int(3 + 18 * s)
        out[:, :, 0] = np.roll(out[:, :, 0], k, axis=1)
        out[:, :, 2] = np.roll(out[:, :, 2], -k, axis=1)
        for _ in range(int(6 * s)):
            y, x = int(rng.integers(0, H - 60)), int(rng.integers(0, W - 300))
            h, w = int(rng.integers(8, 60)), int(rng.integers(60, 300))
            out[y:y + h, x:x + w] = rng.integers(0, 255, (h, w, 1), dtype=np.uint8)
        if rng.random() < 0.5 * s:
            out = (out.astype(np.float32) * rng.uniform(0.4, 1.4)).clip(0, 255).astype(np.uint8)
        return out


def camera(src, box, dx, dy):
    """The part of the frame in box (x, y, width), moved by (dx, dy), scaled to the video."""
    x, y, w = box
    h = w * 9 / 16
    x = min(max(x + dx, 0), W - w)
    y = min(max(y + dy, 0), H - h)
    return np.asarray(Image.fromarray(src).resize((W, H), Image.BILINEAR, box=(x, y, x + w, y + h)))


# ---------------------------------------------------------------- overlays

class Hud:
    def __init__(self):
        self.small = mono(26)
        self.tag = mono(30)
        self.cap = mono(28)

    def draw(self, img, shot, t, k_global, rack=None):
        im = Image.fromarray(img)
        d = ImageDraw.Draw(im)
        if not shot.get("bars"):
            # REC and a clock: a feed from the war room.
            if int(t * 2) % 2 == 0:
                d.ellipse([58, 52, 78, 72], fill=RED)
            d.text((90, 62), "REC", font=self.small, fill=TEXT, anchor="lm")
            secs = 3 * 3600 + 12 * 60 + k_global / FPS
            d.text((W - 60, 62), "%02d:%02d:%02d" % (secs // 3600, secs // 60 % 60, secs % 60),
                   font=self.small, fill=TEXT, anchor="rm")
            d.text((W - 60, 98), "FIELD NOTES  ·  Q%02d" % shot["q_n"], font=self.small, fill=MUTED, anchor="rm")
        # The data tag: the newest one types itself out, bottom left.
        tags = [tg for tg in shot.get("tags", []) if tg[0] <= t]
        if tags:
            t0, text = tags[-1]
            n = int((t - t0) * 55)
            shown = text[:n]
            y = H - 92
            w = self.tag.getlength(text) + 40
            ov = Image.new("RGBA", (int(w), 52), (10, 12, 16, 170))
            im.paste(ov, (56, y - 26), ov)
            d.rectangle([56, y - 26, 61, y + 26], fill=RED if "DESTROYED" in text or "INCOMING" in text else BLUE)
            d.text((80, y), shown + ("_" if n < len(text) or int(t * 3) % 2 == 0 else ""), font=self.tag, fill=TEXT,
                   anchor="lm")
        if rack is not None:
            x0, y0 = 60, 130
            label = "SAM RACK" if rack >= 0 else "SAM  ·  DESTROYED"
            d.text((x0, y0), label, font=self.small, fill=RED if rack <= 0 else TEXT, anchor="lm")
            if rack >= 0:
                for i in range(6):
                    c = BLUE if i < rack else (60, 64, 72)
                    d.rectangle([x0 + 160 + i * 26, y0 - 11, x0 + 178 + i * 26, y0 + 11], fill=c)
        if shot.get("bars"):
            bar = 138
            d.rectangle([0, 0, W, bar], fill=(0, 0, 0))
            d.rectangle([0, H - bar, W, H], fill=(0, 0, 0))
            text = shot["caption"]
            n = int(max(0.0, t - 0.6) * 30)
            if n > 0:
                d.text((W / 2, H - bar / 2), text[:n], font=self.cap,
                       fill=RED if int(t * 2) % 2 == 0 or n < len(text) else (150, 50, 40), anchor="mm")
        return np.asarray(im)


class Guide:
    """The 720p read-along: the line to say now, a bar for its time, the next line."""
    def __init__(self, cues):
        self.cues = cues
        self.f_now = font(38, "Bold")
        self.f_next = font(24, "Medium")
        self.f_time = mono(22)

    def draw(self, img, t):
        im = Image.fromarray(img).resize((GW, GH), Image.BILINEAR)
        ov = Image.new("RGBA", (GW, 190), (8, 9, 12, 205))
        im.paste(ov, (0, GH - 190), ov)
        d = ImageDraw.Draw(im)
        d.text((24, 24), "%02d:%04.1f" % (t // 60, t % 60), font=self.f_time, fill=YELLOW)
        now = [c for c in self.cues if c[0] <= t < c[3] + 0.25]
        nxt = [c for c in self.cues if c[0] > t]
        y = GH - 160
        if now:
            c = now[-1]
            for line in wrap(c[1], self.f_now, GW - 80)[:2]:
                d.text((40, y), line, font=self.f_now, fill=(255, 255, 255))
                y += 48
            k = min(1.0, (t - c[0]) / max(0.1, c[3] - c[0]))
            d.rectangle([40, GH - 58, 40 + (GW - 80) * k, GH - 52], fill=YELLOW)
        else:
            gap = nxt[0][0] - t if nxt else 0
            d.text((40, y), "(pause)" if gap > 0.6 else "", font=self.f_now, fill=MUTED)
        if nxt:
            c = nxt[0]
            lead = c[0] - t
            label = ("NEXT in %.1f:  " % lead if lead < 3 else "NEXT:  ") + c[1]
            d.text((40, GH - 40), label[:110], font=self.f_next, fill=MUTED)
        return np.asarray(im)


# ---------------------------------------------------------------- shots

def blur_bg(rec, src, sec):
    f = next(read_frames(movie_of(rec, src), int(round(sec * FPS)), 1))
    im = Image.fromarray(f).filter(ImageFilter.GaussianBlur(16))
    return np.asarray(im).astype(np.float32) * np.array([0.50, 0.40, 0.40], np.float32)


def scanlines(x):
    x = x.copy()
    x[::3] *= 0.78
    return x


def render_clip(s, rec, look, hud, emit):
    path = movie_of(rec, s["src"])
    a = int(round(s["a"] * FPS))
    n = s["frames"]
    shake = np.zeros(n + 1)
    flash = np.zeros(n + 1)
    tear = np.zeros(n + 1)
    for fr, kind, size in fx_log(rec, s["src"]):
        k = fr - a
        if kind == 0 and 0 <= k < n:
            shake[k] += max(0.0, size - 9.0) * 1.3
            if size >= 20:
                flash[k] += 0.35
                if look.rng.random() < 0.6:
                    tear[k] = 0.35
    if s["src"] == "intercept":
        # The hit, 6.3 s in, and the later interceptions.
        for sec, amp in ((6.3, 16.0), (9.4, 6.0), (10.6, 6.0), (11.8, 5.0)):
            k = int(sec * FPS)
            shake[k] += amp
            flash[k] += 0.25 if amp > 10 else 0.08
        tear[int(6.3 * FPS)] = 0.5
    for k in range(1, n + 1):
        shake[k] += shake[k - 1] * math.exp(-6.0 / FPS)
        flash[k] = max(flash[k], flash[k - 1] * math.exp(-14.0 / FPS))
    ammo = ammo_log(rec, s["src"]) if s.get("rack") else None
    last_rack = 6
    for k, src in enumerate(read_frames(path, a, n)):
        t = k / FPS
        e = smooth(k / max(1, n - 1))
        box = tuple(s["box0"][i] + (s["box1"][i] - s["box0"][i]) * e for i in range(3))
        # A hand on the camera: slow drift, and a kick on every blast.
        drift = (math.sin(t * 0.9 + s["f0"]) * 5 + math.sin(t * 2.3) * 2, math.cos(t * 0.7 + s["f0"]) * 4)
        amp = shake[k]
        jig = (look.rng.normal(0, 1) * amp, look.rng.normal(0, 1) * amp)
        img = camera(src, box, drift[0] + jig[0], drift[1] + jig[1])
        img = look.grade(img, flash[k], int(min(10, amp * 0.6)))
        if ammo is not None:
            last_rack = ammo.get(a + k, last_rack)
        img = hud.draw(img, s, t, s["f0"] + k, last_rack if ammo is not None else None)
        g = tear[k] if tear[k] > 0 else (tear[k - 1] * 0.5 if k > 0 else 0)
        g = max(g, (1 - k / 5) * 0.8 if k < 5 else 0, (1 - (n - 1 - k) / 3) * 0.5 if k >= n - 3 else 0)
        emit(look.glitch(img, g))


def render_card(s, rec, look, emit):
    bg = blur_bg(rec, *s["bg"])
    f_num, f_q = mono(34), font(84, "Bold")
    lines = wrap(s["q"], f_q, 1500)
    n = s["frames"]
    for k in range(n):
        t = k / FPS
        z = 1.0 + 0.05 * k / n
        x = Image.fromarray(np.clip(bg, 0, 255).astype(np.uint8))
        cw, ch = W / z, H / z
        x = x.transform((W, H), Image.EXTENT, ((W - cw) / 2, (H - ch) / 2, (W + cw) / 2, (H + ch) / 2), Image.BILINEAR)
        img = scanlines(np.asarray(x).astype(np.float32))
        im = Image.fromarray(np.clip(img, 0, 255).astype(np.uint8))
        d = ImageDraw.Draw(im)
        top = 540 - len(lines) * 50 - 30
        d.text((200, top), "QUESTION %02d / %02d" % (s["n"], N_Q), font=f_num, fill=RED, anchor="lm")
        typed = int(max(0.0, t - 0.2) * 34)
        y = top + 60
        left = typed
        for line in lines:
            part = line[:max(0, left)]
            d.text((200, y), part, font=f_q, fill=(255, 255, 255))
            if 0 < left <= len(line) or (left > len(line) and line is lines[-1] and int(t * 3) % 2 == 0):
                cx = 200 + f_q.getlength(part) + 10
                d.rectangle([cx, y + 18, cx + 36, y + 100], fill=RED)
            left -= len(line) + 1
            y += 100
        grow = smooth((t - 0.2) / 1.0)
        d.rectangle([200, y + 30, 200 + 600 * grow, y + 36], fill=RED)
        img = look.grade(np.asarray(im))
        g = max((1 - k / 4) * 0.9 if k < 4 else 0, (1 - (n - 1 - k) / 3) * 0.7 if k >= n - 3 else 0)
        if look.rng.random() < 0.04:
            g = max(g, 0.25)
        emit(look.glitch(img, g))


def render_title(s, look, emit):
    lg = Image.open(LOGO).convert("RGBA")
    lw = 1100
    lg = lg.resize((lw, round(lg.height * lw / lg.width)), Image.LANCZOS)
    f_sub = mono(36)
    sub = "FIELD NOTES  //  %d QUESTIONS. STRAIGHT ANSWERS." % N_Q
    n = s["frames"]
    for k in range(n):
        t = k / FPS
        im = Image.new("RGB", (W, H), (6, 7, 9))
        # The logo flickers on like a bad signal, then holds.
        on = t > 0.15 and (t > 0.75 or look.rng.random() < 0.55)
        if on:
            z = 1.0 + 0.04 * t / s["dur"]
            l2 = lg.resize((int(lg.width * z), int(lg.height * z)), Image.BILINEAR)
            im.paste(l2, ((W - l2.width) // 2, 470 - l2.height // 2), l2)
        d = ImageDraw.Draw(im)
        m = int(max(0.0, t - 1.0) * 40)
        d.text((W / 2, 690), sub[:m], font=f_sub, fill=MUTED, anchor="mm")
        img = look.grade(np.asarray(im))
        g = 0.0
        if t < 0.8:
            g = 0.6 * look.rng.random()
        if k >= n - 4:
            g = (1 - (n - 1 - k) / 4) * 0.9
        emit(look.glitch(img, g))


SPECS = [
    ("DRONE", 12, 26, 90, 25, 1, "Every region it crosses goes on alert. Factories there slow down."),
    ("CRUISE MISSILE", 55, 72, 80, 8, 2, "The most accurate. Flies the route you draw."),
    ("BALLISTIC MISSILE", 130, 220, 45, 0, 3, "No route: straight down. The biggest blast."),
]


def render_specs(s, rec, look, emit):
    bg = blur_bg(rec, *s["bg"]) * 0.8
    f_head, f_name, f_row, f_note = mono(30), font(46, "Bold"), mono(28), font(27, "Medium")
    n = s["frames"]
    cw, gap = 520, 60
    x0 = (W - 3 * cw - 2 * gap) // 2
    for k in range(n):
        t = k / FPS
        im = Image.fromarray(np.clip(scanlines(bg), 0, 255).astype(np.uint8)).convert("RGBA")
        d = ImageDraw.Draw(im)
        d.text((x0, 190), "ARSENAL  ·  WHAT EACH ONE IS FOR", font=f_head, fill=RED, anchor="lm")
        g = 0.0
        for i, (name, cost, speed, sam, gun, dmg, note) in enumerate(SPECS):
            at = s["at"][i]
            if t < at:
                continue
            u = smooth((t - at) / 0.35)
            if t - at < 0.15:
                g = max(g, 0.6)
            x, y = x0 + i * (cw + gap), 250 + int((1 - u) * 40)
            active = i == len([a for a in s["at"] if a <= t]) - 1
            card = Image.new("RGBA", (cw, 600), (14, 16, 21, int(225 * u)))
            im.paste(card, (x, y), card)
            d.rectangle([x, y, x + cw, y + 6], fill=YELLOW if active else (70, 74, 84))
            d.text((x + 30, y + 60), name, font=f_name, fill=(255, 255, 255), anchor="lm")
            rows = [("COST", "$%d" % cost), ("SPEED", None), ("SAM HITS IT", "%d%%" % sam),
                    ("AA GUN HITS IT", "%d%%" % gun if gun else "NEVER"), ("DAMAGE", "■" * dmg + "□" * (3 - dmg))]
            ry = y + 140
            for label, val in rows:
                d.text((x + 30, ry), label, font=f_row, fill=MUTED, anchor="lm")
                if val is None:
                    bw = 200 * speed / 220
                    d.rectangle([x + cw - 30 - 200, ry - 7, x + cw - 30, ry + 7], fill=(50, 54, 62))
                    d.rectangle([x + cw - 30 - 200, ry - 7, x + cw - 30 - 200 + bw, ry + 7], fill=BLUE)
                else:
                    d.text((x + cw - 30, ry), val, font=f_row, fill=TEXT, anchor="rm")
                ry += 58
            ny = ry + 20
            for line in wrap(note, f_note, cw - 60):
                d.text((x + 30, ny), line, font=f_note, fill=YELLOW)
                ny += 38
        img = look.grade(np.asarray(im.convert("RGB")))
        if k >= n - 3:
            g = max(g, (1 - (n - 1 - k) / 3) * 0.7)
        emit(look.glitch(img, g))


def render_end(s, look, emit):
    n = s["frames"]
    src = list(read_frames(INTERCEPT, int(13.0 * FPS), int(3.0 * FPS)))
    for k in range(n):
        f = src[min(k, len(src) - 1)]
        z = 1.0 + 0.035 * k / n
        cw, ch = W / z, H / z
        im = Image.fromarray(f).transform((W, H), Image.EXTENT, ((W - cw) / 2, (H - ch) / 2, (W + cw) / 2,
                                                                 (H + ch) / 2), Image.BILINEAR)
        img = look.grade(np.asarray(im)).astype(np.float32)
        fade = smooth((k - (n - 0.8 * FPS)) / (0.8 * FPS))
        img *= 1 - fade
        g = (1 - k / 4) * 0.8 if k < 4 else 0
        emit(look.glitch(img.astype(np.uint8), g))


def encoder(path, w, h, crf):
    return subprocess.Popen([FF, "-hide_banner", "-loglevel", "error", "-y", "-f", "rawvideo", "-pix_fmt", "rgb24",
                             "-s", "%dx%d" % (w, h), "-r", str(FPS), "-i", "-", "-c:v", "libx264", "-preset", "medium",
                             "-crf", str(crf), "-pix_fmt", "yuv420p", "-g", str(FPS * 2), path], stdin=subprocess.PIPE)


def render_shot(job):
    i, rec, tmp, cues = job
    if "frames" not in SHOTS[i]:   # a fresh worker process
        timeline(quiet=True)
    s = SHOTS[i]
    look = Look(1000 + i)
    hud = Hud()
    guide = Guide(cues)
    clean = encoder(os.path.join(tmp, "shot%02d.mp4" % i), W, H, 16)
    read = encoder(os.path.join(tmp, "guide%02d.mp4" % i), GW, GH, 24)
    count = [0]

    def emit(img):
        if count[0] >= s["frames"]:
            return
        clean.stdin.write(np.ascontiguousarray(img).tobytes())
        read.stdin.write(guide.draw(img, (s["f0"] + count[0]) / FPS).tobytes())
        count[0] += 1

    if s["kind"] == "clip":
        render_clip(s, rec, look, hud, emit)
    elif s["kind"] == "card":
        render_card(s, rec, look, emit)
    elif s["kind"] == "title":
        render_title(s, look, emit)
    elif s["kind"] == "specs":
        render_specs(s, rec, look, emit)
    elif s["kind"] == "end":
        render_end(s, look, emit)
    black = np.zeros((H, W, 3), np.uint8)
    while count[0] < s["frames"]:   # a recording that ran short: hold black rather than drift
        emit(black)
    for e in (clean, read):
        e.stdin.close()
        e.wait()
    return i


# ---------------------------------------------------------------- sound

def load_audio(path, start, dur):
    p = subprocess.run([FF, "-hide_banner", "-loglevel", "error", "-ss", "%.3f" % start, "-t", "%.3f" % dur, "-i", path,
                        "-f", "f32le", "-ac", "2", "-ar", str(SR), "-"], capture_output=True)
    x = np.frombuffer(p.stdout, np.float32).reshape(-1, 2).copy()
    return x


def lowpass(x, hz):
    X = np.fft.rfft(x)
    X[np.fft.rfftfreq(len(x), 1 / SR) > hz] = 0
    return np.fft.irfft(X, len(x))


def highpass(x, hz):
    X = np.fft.rfft(x)
    X[np.fft.rfftfreq(len(x), 1 / SR) < hz] = 0
    return np.fft.irfft(X, len(x))


def boom(rng, secs=2.2, f0=70, f1=28):
    """A sub hit: a falling sine, a noise thump and a long low tail."""
    n = int(secs * SR)
    t = np.arange(n) / SR
    f = (f0 - f1) * np.exp(-t * 2.5) + f1
    x = np.sin(2 * math.pi * np.cumsum(f) / SR) * np.exp(-t * 2.0)
    x += lowpass(rng.normal(0, 1, n), 300) * np.exp(-t * 14) * 0.6
    x += lowpass(rng.normal(0, 1, n), 120) * np.exp(-t * 1.6) * 0.5
    return x / (np.abs(x).max() + 1e-9)


def braam(rng, secs=2.6):
    """A low brass-like stab for the question cards."""
    n = int(secs * SR)
    t = np.arange(n) / SR
    env = np.minimum(1, t / 0.03) * np.exp(-t * 1.4)
    x = np.zeros(n)
    for hz, g in ((55, 1.0), (55.4, 0.8), (82.4, 0.5), (110, 0.35), (164.8, 0.15)):
        ph = 2 * math.pi * hz * t + rng.uniform(0, 6.28)
        x += g * (2 * ((ph / (2 * math.pi)) % 1) - 1)   # a saw
    x = lowpass(x * env, 900) + boom(rng, secs, 60, 30) * 0.7
    return x / (np.abs(x).max() + 1e-9)


def whoosh(rng, secs=0.7, rise=True):
    n = int(secs * SR)
    t = np.arange(n) / SR
    x = highpass(lowpass(rng.normal(0, 1, n), 4000), 300)
    env = (t / secs) ** 2.2 if rise else np.sin(np.pi * t / secs) ** 2
    return x / (np.abs(x).max() + 1e-9) * env


def static(rng, secs):
    n = int(secs * SR)
    x = highpass(rng.normal(0, 1, n), 1500)
    x *= (rng.random(n // 400 + 1) > 0.3).repeat(400)[:n]
    return x / (np.abs(x).max() + 1e-9)


def pad(secs, rng):
    """A dark, slowly breathing drone in D, low under everything."""
    n = int(secs * SR)
    t = np.arange(n) / SR
    x = np.zeros(n)
    for hz, g in ((36.7, 1.0), (73.4, 0.6), (73.9, 0.5), (110.0, 0.3), (87.3, 0.18)):
        x += g * np.sin(2 * math.pi * hz * t + rng.uniform(0, 6.28) + 0.4 * np.sin(2 * math.pi * 0.07 * t))
    x += lowpass(rng.normal(0, 1, n), 200) * 0.3
    x *= 0.65 + 0.35 * np.sin(2 * math.pi * t / 9.0) ** 2
    return x / (np.abs(x).max() + 1e-9)


def click_sample():
    with wave.open(CLICK) as w:
        ch, sw, fr, nf = w.getnchannels(), w.getsampwidth(), w.getframerate(), w.getnframes()
        raw = np.frombuffer(w.readframes(nf), np.int16 if sw == 2 else np.int8).astype(np.float32)
    x = raw.reshape(-1, ch).mean(axis=1) / 32768.0
    idx = np.arange(0, len(x), fr / SR)
    return np.interp(idx, np.arange(len(x)), x)


def sound(rec, total):
    rng = np.random.default_rng(5)
    out = np.zeros((total + SR * 3, 2), np.float32)

    def put(x, at, gain, pan=0.0):
        i = int(at * SR)
        if i < 0:
            x, i = x[-i:], 0
        if x.ndim == 1:
            x = np.stack([x * (1 - max(0, pan)), x * (1 + min(0, pan))], axis=1)
        j = min(len(out), i + len(x))
        out[i:j] += (x[: j - i] * gain).astype(np.float32)

    clk = click_sample()
    for i, s in enumerate(SHOTS):
        t0, dur = s["f0"] / FPS, s["frames"] / FPS
        if s["kind"] == "clip":
            a = load_audio(movie_of(rec, s["src"]), s["a"], dur)
            ramp = min(len(a) // 2, int(0.06 * SR))
            a[:ramp] *= np.linspace(0, 1, ramp)[:, None]
            a[len(a) - ramp:] *= np.linspace(1, 0, ramp)[:, None]
            put(a, t0, 1.0 if s["src"] == "intercept" else 0.85)
            # Weight under the biggest blasts.
            for fr, kind, size in fx_log(rec, s["src"]):
                at = (fr - int(round(s["a"] * FPS))) / FPS
                if kind == 0 and size >= 20 and 0 <= at < dur:
                    put(boom(rng, 1.6, 55, 26), t0 + at, 0.32)
            if s["src"] == "intercept":
                put(boom(rng, 2.6), t0 + 6.3, 0.55)
            put(static(rng, 0.15), t0, 0.10)
        elif s["kind"] == "card":
            put(whoosh(rng, 0.6), t0 - 0.6, 0.22)
            put(braam(rng), t0, 0.5)
            put(static(rng, 0.14), t0, 0.12)
            typed = len(s["q"])
            for c in range(typed):
                if s["q"][c] != " ":
                    put(clk * rng.uniform(0.5, 1.0), t0 + 0.2 + c / 34, 0.08, rng.uniform(-0.3, 0.3))
            put(static(rng, 0.1), t0 + dur - 0.1, 0.10)
        elif s["kind"] == "title":
            put(whoosh(rng, 1.4), t0 - 1.0, 0.3)
            put(boom(rng, 3.5, 80, 24), t0 + 0.15, 0.7)
            put(static(rng, 0.7), t0, 0.08)
            for c in range(46):
                put(clk * 0.6, t0 + 1.0 + c / 40, 0.05, rng.uniform(-0.3, 0.3))
        elif s["kind"] == "specs":
            for at in s["at"]:
                put(boom(rng, 1.2, 90, 40), t0 + at, 0.35)
                put(static(rng, 0.12), t0 + at, 0.08)
        elif s["kind"] == "end":
            a = load_audio(INTERCEPT, 13.0, 3.0)
            put(a, t0, 0.9)
            put(boom(rng, 3.0, 70, 26), t0, 0.5)
    # The drone runs from the title to the end, louder over the cards.
    start = SHOTS[1]["f0"] / FPS
    p = pad(total / SR - start, rng) * 0.10
    put(np.stack([p, np.roll(p, 900)], axis=1), start, 1.0)
    out = out[:total]
    tail = int(1.0 * SR)
    out[-tail:] *= np.linspace(1, 0, tail)[:, None]
    return out


def write_wav(path, x):
    x = np.clip(x, -1, 1)
    with wave.open(path, "wb") as w:
        w.setnchannels(2)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes((x * 32767).astype(np.int16).tobytes())


def srt_time(t):
    ms = int(round(t * 1000))
    return "%02d:%02d:%02d,%03d" % (ms // 3600000, ms // 60000 % 60, ms // 1000 % 60, ms % 1000)


# ---------------------------------------------------------------- main

def main():
    rec, out_dir = os.path.abspath(sys.argv[1]), os.path.abspath(sys.argv[2])
    frames, cues = timeline()
    print("%d shots, %.1f s, %d voice lines" % (len(SHOTS), frames / FPS, len(cues)))
    if "--check" in sys.argv:
        for c in cues:
            print("%6.1f  %6.1f  %s" % (c[0], c[3], c[1]))
        return
    os.makedirs(out_dir, exist_ok=True)
    tmp = tempfile.mkdtemp()
    jobs = [(i, rec, tmp, cues) for i in range(len(SHOTS))]
    # The longest shots first, so the pool finishes together.
    jobs.sort(key=lambda j: -SHOTS[j[0]]["frames"])
    with Pool(max(1, (os.cpu_count() or 2))) as pool:
        for i in pool.imap_unordered(render_shot, jobs):
            print("shot", i, "done")
    base = os.path.join(out_dir, "strike-alert-voiceover")
    bed = sound(rec, int(round(frames / FPS * SR)))
    raw_wav = os.path.join(tmp, "bed.wav")
    write_wav(raw_wav, bed)
    # loudnorm aims at -20 LUFS; with the long quiet stretches the bed measures about -22.
    subprocess.run([FF, "-hide_banner", "-loglevel", "error", "-y", "-i", raw_wav, "-af",
                    "loudnorm=I=-20:TP=-2:LRA=14", "-ar", str(SR), base + "-bed.wav"], check=True)
    for name, out in (("shot", base + "-16x9.mp4"), ("guide", base + "-guide.mp4")):
        lst = os.path.join(tmp, name + ".txt")
        with open(lst, "w") as f:
            for i in range(len(SHOTS)):
                f.write("file '%s'\n" % os.path.join(tmp, "%s%02d.mp4" % (name, i)).replace("\\", "/"))
        joined = os.path.join(tmp, name + "_all.mp4")
        subprocess.run([FF, "-hide_banner", "-loglevel", "error", "-y", "-f", "concat", "-safe", "0", "-i", lst,
                        "-c", "copy", joined], check=True)
        subprocess.run([FF, "-hide_banner", "-loglevel", "error", "-y", "-i", joined, "-i", base + "-bed.wav",
                        "-map", "0:v", "-map", "1:a", "-c:v", "copy", "-c:a", "aac", "-b:a", "256k", "-shortest",
                        "-movflags", "+faststart", out], check=True)
        print("wrote", out)
    with open(base + ".srt", "w", encoding="utf-8") as f:
        for k, c in enumerate(cues):
            f.write("%d\n%s --> %s\n%s\n\n" % (k + 1, srt_time(c[0]), srt_time(c[3]), c[1]))
    print("wrote", base + ".srt", "and", base + "-bed.wav")


if __name__ == "__main__":
    main()
