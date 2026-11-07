"""A chill 9:16 short from a 4K scene recorded by tools/record_short.py: a dark
flash-forward hook, a thud to black, "N seconds earlier", then the scene full screen
at the game's own speed with meme-style captions and a counter of the SAM's missiles.
No logo, no end card. Writes a captioned cut and a clean one (no captions) for adding
your own text, memes and voice.

    python tools/record_short.py bait REC --rng=9 --size=3840x2160 --lite-atsam=1 --lite-fwd=70
    python tools/meme_video.py bait REC itch/shorts

Needs ffmpeg (pip install imageio-ffmpeg).
"""
import math
import os
import subprocess
import sys
import wave

import imageio_ffmpeg
import numpy as np
from PIL import Image, ImageDraw, ImageFont

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
FONT = os.path.join(ROOT, "assets", "fonts", "Inter.ttf")
FF = imageio_ffmpeg.get_ffmpeg_exe()
FPS, W, H, SR = 30, 1080, 1920, 48000
PAGE = (0x16, 0x18, 0x1D)
RED = (0xF0, 0x4E, 0x3E)

# The scene: where the vertical frame sits (x centre in the 4K recording), the hook
# (marker, seconds before, seconds after; where it centres: a site's index in track.txt
# or a point in the recording; its zoom; its look), and the captions (scene frame they
# start on, text with | where a line breaks or None for none, sites to ring: (index in
# track.txt, tag or "")). Each caption stays up until the next.
VIDEOS = {
    "swarm": dict(
        out="drone-swarm",
        centre_x=1420,
        hook=("finale", 0.33, 2.2),
        hook_centre=(1290, 1080),
        hook_zoom=(1.12, 1.22),
        hook_look="punchy",
        counter=False,
        rumble=False,
        sfx=True,
        hook_lines=[(0.0, "they sent 40 drones|at my air defence"), (1.25, "this is what's left")],
        earlier="18 seconds earlier",
        take=("start", "end"),
        captions=[
            (28, "my factory.|2 SAMs. 2 AA guns.", [(0, ""), (1, ""), (2, ""), (3, ""), (4, "FACTORY")]),
            (62, "they fire a|ballistic missile", []),
            (100, "blocked.", []),
            (160, "so they send|40 drones", []),
            (250, "12 missiles.|40 drones.", []),
            (326, "out of missiles", []),
            (380, None, []),
            (520, "air defence: gone", []),
            (548, "now the ballistic|gets through", []),
            (600, "drones aren't the weapon.|they're the bill.", []),
        ],
    ),
    "bait": dict(
        out="drones-vs-sam",
        centre_x=1480,
        hook=("empty", 0.8, 1.6),
        hook_lines=[(0.0, "my SAM just ran|out of missiles"), (1.1, "and 6 drones|are still coming")],
        earlier="8 seconds earlier",
        take=("start", "end"),
        captions=[
            (28, "one factory.|one SAM with 6 missiles.", [(0, "SAM"), (1, "FACTORY")]),
            (62, "they fire a ballistic|missile ($130)", []),
            (104, "my SAM:|blocked. easy.", []),
            (165, "then 10 drones show up|($12 each)", []),
            (215, "and they're going|for the SAM", []),
            (270, "0 missiles left.|6 drones still coming.", []),
            (360, "it reloads one|every 3.5 seconds", []),
            (430, "too slow", []),
            (505, "$120 of drones just|killed a $240 SAM", []),
            (552, "drones aren't the weapon.|they're the bill.", []),
        ],
    ),
}


def font(size, weight):
    f = ImageFont.truetype(FONT, size)
    f.set_variation_by_name(weight)
    return f


def markers(path):
    marks = {}
    for line in open(path, encoding="utf-8"):
        p = line.split()
        if len(p) >= 3 and p[2].isdigit():
            marks[p[1]] = int(p[2])
    return marks


def per_frame(path, kind):
    out = {}
    if os.path.exists(path):
        for line in open(path, encoding="utf-8"):
            p = line.split()
            if len(p) >= 3 and p[1].isdigit():
                v = [float(x) for x in p[2:]]
                out[int(p[1])] = list(zip(v[0::2], v[1::2])) if kind == "xy" else v
    return out


def frames(movie, a, b, crop, scale=None):
    """Frames a..b-1 of the recording, cropped (w, h, x, y) and optionally scaled, as RGB."""
    w, h, x, y = crop
    vf = "trim=start_frame=%d:end_frame=%d,crop=%d:%d:%d:%d" % (a, b, w, h, x, y)
    if scale:
        vf += ",scale=%d:%d:flags=lanczos" % scale
        w, h = scale
    p = subprocess.Popen([FF, "-hide_banner", "-loglevel", "error", "-i", movie, "-vf", vf, "-frames:v", str(b - a),
                          "-f", "rawvideo", "-pix_fmt", "rgb24", "-"], stdout=subprocess.PIPE)
    n = w * h * 3
    while True:
        buf = p.stdout.read(n)
        if len(buf) < n:
            break
        yield np.frombuffer(buf, np.uint8).reshape(h, w, 3)
    p.wait()


# --- pictures ---------------------------------------------------------------------------------

def wrap(text, f, width):
    if f.getlength(text) <= width:
        return [text]
    words = text.split()
    best = None
    for i in range(1, len(words)):
        a, b = " ".join(words[:i]), " ".join(words[i:])
        m = max(f.getlength(a), f.getlength(b))
        if best is None or m < best[0]:
            best = (m, [a, b])
    return best[1]


def caption_img(text):
    """Big white words with a heavy black outline, as captions on Reels and TikTok go."""
    f = font(74, "Black")
    lines = text.split("|") if "|" in text else wrap(text, f, 860)
    pad = 20
    img = Image.new("RGBA", (W, len(lines) * 92 + 2 * pad), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    for i, line in enumerate(lines):
        d.text((W // 2, pad + i * 92 + 46), line, font=f, fill=(255, 255, 255), anchor="mm",
               stroke_width=9, stroke_fill=(0, 0, 0))
    return img


def paste(img, layer, x, y, alpha=1.0):
    """Alpha-blends an RGBA PIL layer onto a float RGB frame at (x, y)."""
    a = np.asarray(layer, np.float32)
    h, w = a.shape[:2]
    x0, y0 = max(0, int(x)), max(0, int(y))
    x1, y1 = min(img.shape[1], int(x) + w), min(img.shape[0], int(y) + h)
    if x1 <= x0 or y1 <= y0:
        return
    sub = a[y0 - int(y):y1 - int(y), x0 - int(x):x1 - int(x)]
    k = sub[..., 3:] / 255 * alpha
    img[y0:y1, x0:x1] = img[y0:y1, x0:x1] * (1 - k) + sub[..., :3] * k


def pop(layer, t):
    """A caption popping in: a little small and see-through for its first frames."""
    e = min(1.0, t / 0.13)
    s = 0.88 + 0.12 * (1 - (1 - e) ** 3)
    if s < 0.999:
        layer = layer.resize((max(1, int(layer.width * s)), max(1, int(layer.height * s))), Image.BILINEAR)
    return layer, e


def ammo_pill(ammo, dead):
    """The SAM's missiles: six dots, hollow when spent; red when there are none left."""
    f = font(30, "Black")
    img = Image.new("RGBA", (330, 64), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    red = ammo <= 0 or dead
    d.rounded_rectangle([2, 2, 327, 61], radius=30, fill=(18, 20, 26, 225),
                        outline=RED + (255,) if red else (255, 255, 255, 90), width=3)
    if dead:
        d.text((165, 32), "SAM DESTROYED", font=f, fill=RED, anchor="mm")
        return img
    d.text((22, 32), "SAM", font=f, fill=(255, 255, 255), anchor="lm")
    for i in range(6):
        cx = 112 + i * 34
        if i < ammo:
            d.ellipse([cx - 11, 21, cx + 11, 43], fill=(255, 255, 255))
        else:
            d.ellipse([cx - 11, 21, cx + 11, 43], outline=RED + (255,) if red else (255, 255, 255, 140), width=3)
    return img


def ring(img, x, y, tag, alpha, t, f):
    over = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    d = ImageDraw.Draw(over)
    r = 34 + 5 * (0.5 + 0.5 * math.sin(t * 5))
    d.ellipse([x - r, y - r, x + r, y + r], outline=(255, 255, 255, int(240 * alpha)), width=5)
    tw = f.getlength(tag)
    x0 = x + r + 12 if x + r + 12 + tw + 30 < W - 20 else x - r - 12 - tw - 30
    d.rounded_rectangle([x0, y - 24, x0 + tw + 30, y + 24], radius=24, fill=(255, 255, 255, int(240 * alpha)))
    d.text((x0 + 15 + tw / 2, y), tag, font=f, fill=PAGE + (int(255 * alpha),), anchor="mm")
    paste(img, over, 0, 0)


def scary(img, k):
    """The hook's look: darker, less colour, a red cast, heavy vignette."""
    lum = img @ np.array([0.3, 0.59, 0.11], np.float32)
    img = img * 0.55 + lum[..., None] * 0.45
    img = img * np.array([1.05, 0.88, 0.86], np.float32) * 0.62
    yy, xx = np.mgrid[0:H, 0:W].astype(np.float32)
    v = 1 - 0.85 * (((xx - W / 2) / (W * 0.62)) ** 2 + ((yy - H * 0.52) / (H * 0.62)) ** 2)
    return img * np.clip(v, 0.12, 1)[..., None] * k


def punchy(img):
    """The hook's look when it should stay in colour: a touch more contrast, a vignette."""
    img = np.clip((img - 128) * 1.12 + 128, 0, 255)
    yy, xx = np.mgrid[0:H, 0:W].astype(np.float32)
    v = 1 - 0.5 * (((xx - W / 2) / (W * 0.7)) ** 2 + ((yy - H * 0.5) / (H * 0.7)) ** 2)
    return img * np.clip(v, 0.35, 1)[..., None]


# --- sound ----------------------------------------------------------------------------------------

def lowpass(x, hz):
    X = np.fft.rfft(x)
    f = np.fft.rfftfreq(len(x), 1 / SR)
    X[f > hz] = 0
    return np.fft.irfft(X, len(x))


def rumble(secs, rng):
    n = int(secs * SR)
    t = np.arange(n) / SR
    noise = lowpass(rng.normal(0, 1, n), 140)
    noise /= np.abs(noise).max() + 1e-9
    x = 0.6 * noise + 0.5 * np.sin(2 * math.pi * 43 * t)
    return x * (t / secs) ** 1.6 * 0.5


def thud(rng):
    n = int(0.9 * SR)
    t = np.arange(n) / SR
    f = 75 * np.exp(-t * 2.2) + 30
    x = np.sin(2 * math.pi * np.cumsum(f) / SR) * np.exp(-t * 4.5)
    x += lowpass(rng.normal(0, 1, n), 400) * np.exp(-t * 30) * 0.25
    return x * 0.9


def whoosh(rng):
    n = int(0.9 * SR)
    t = np.arange(n) / SR
    x = lowpass(rng.normal(0, 1, n), 1800) - lowpass(rng.normal(0, 1, n), 250) * 0.5
    x /= np.abs(x).max() + 1e-9
    return x * np.sin(np.pi * t / 0.9) ** 2 * 0.22


AUDIO = os.path.join(ROOT, "assets", "audio")
_samples = {}


def sample(name, start=0.0, length=None, fade=0.3, rate=1.0):
    """A game sound as 48 kHz mono: a piece of it, faded out, optionally pitched."""
    key = (name, start, length, fade, round(rate, 3))
    if key in _samples:
        return _samples[key]
    with wave.open(os.path.join(AUDIO, name)) as w:
        sr, n, ch = w.getframerate(), w.getnframes(), w.getnchannels()
        x = np.frombuffer(w.readframes(n), np.int16).astype(np.float64).reshape(-1, ch).mean(1) / 32768
    x = x[int(start * sr):]
    if length:
        x = x[:int(length * sr)]
    m = int(len(x) * SR / sr / rate)
    x = np.interp(np.arange(m) * (sr * rate / SR), np.arange(len(x)), x)
    k = min(len(x), int(fade * SR))
    if k:
        x[-k:] *= np.linspace(1, 0, k) ** 2
    _samples[key] = x
    return x


def sfx(rec, marks, f_from, f_to, rng):
    """The scene's sound laid from its event log: a short launch for each SAM shot, a pop
    for each kill, soft ticks for the guns, a crack for each drone hit, a big blast for a
    ballistic one, wreckage when a site goes, a short warning when a ballistic flies;
    sounds of a kind kept a little apart so they never pile into noise."""
    out = np.zeros(int((f_to - f_from) / FPS * SR) + SR)
    last = {}

    def put(kind, f, x, gain, gap):
        t = (f - f_from) / FPS
        if t < 0 or f >= f_to or t - last.get(kind, -9) < gap:
            return
        last[kind] = t
        i = int(t * SR)
        out[i:i + len(x)] += x[: len(out) - i] * gain

    for line in open(os.path.join(rec, "fx.txt"), encoding="utf-8"):
        q = line.split()
        if len(q) < 6 or not q[1].isdigit():
            continue
        f, kind, side, size, life = int(q[1]), int(q[2]), int(q[3]), float(q[4]), float(q[5])
        jit = 1 + rng.uniform(-0.06, 0.06)
        if kind == 5 and side == 0 and life < 0.6:        # a SAM fires
            put("sam", f, sample("sam_launch.wav", 0, 1.0, 0.45, jit), 0.32, 0.4)
        elif kind == 2:                                    # something shot down
            put("pop", f, sample("intercept.wav", 0, 0.8, 0.35, jit), 0.42, 0.15)
        elif kind == 4:                                    # a gun shot
            put("gun", f, sample("gun_loop.wav", 0, 0.16, 0.06, jit), 0.12, 0.3)
        elif kind == 0 and size >= 20:                     # a ballistic missile lands
            put("big", f, sample("explosion_b.wav", 0, 5.5, 2.5), 0.95, 0.2)
            put("sub", f, thud(rng), 0.6, 0.2)
        elif kind == 0:                                    # a drone hits
            put("hit", f, sample("explosion_small_a.wav", 0, 1.4, 0.7, jit), 0.55, 0.25)
    # Sites destroyed, from the state log.
    prev = None
    for line in open(os.path.join(rec, "ammo.txt"), encoding="utf-8"):
        q = line.split()
        if len(q) < 3 or not q[1].isdigit():
            continue
        f, st = int(q[1]), q[2:]
        if prev is not None:
            for i, (a, b) in enumerate(zip(prev, st)):
                if a != "-1" and b == "-1" and i != len(st) - 2:      # (the drone count is not a site)
                    put("wreck%d" % i, f, sample("wreck.wav", 0, 2.6, 1.2), 0.5, 0.0)
        prev = st
    for m in ("ballistic", "finale"):
        if m in marks:
            put("warn" + m, marks[m], sample("ballistic_warning.wav", 0, 1.1, 0.4), 0.22, 0.0)
    return np.stack([out, out], 1)


def game_audio(movie, a_s, b_s):
    p = subprocess.run([FF, "-hide_banner", "-loglevel", "error", "-ss", "%.3f" % a_s, "-to", "%.3f" % b_s,
                        "-i", movie, "-vn", "-ac", "2", "-ar", str(SR), "-f", "f32le", "-"], capture_output=True)
    return np.frombuffer(p.stdout, np.float32).reshape(-1, 2).astype(np.float64)


# --- the cut ---------------------------------------------------------------------------------------

def render(name, rec, out_dir):
    cfg = VIDEOS[name]
    movie = os.path.join(rec, "movie.avi")
    marks = markers(os.path.join(rec, "markers.txt"))
    track = per_frame(os.path.join(rec, "track.txt"), "xy")
    ammo = per_frame(os.path.join(rec, "ammo.txt"), "v")
    probe = subprocess.run([FF, "-hide_banner", "-i", movie], capture_output=True, text=True).stderr
    src_h = 2160 if "3840x2160" in probe else 1080
    cw = round(src_h * 9 / 16 / 2) * 2
    cx0 = int(cfg["centre_x"] * src_h / 2160 - cw / 2)
    s = H / src_h
    caps = [(f0, caption_img(text) if text else None, rings) for f0, text, rings in cfg["captions"]]
    tag_font = font(28, "Black")
    rng = np.random.default_rng(1)

    # The hook: around the moment the SAM runs dry, pushed in on it, dark.
    hm, before, after = cfg["hook"]
    ha, hb = marks[hm] - int(before * FPS), marks[hm] + int(after * FPS)
    focus = cfg.get("hook_centre", 0)
    sam0 = track[ha][focus] if isinstance(focus, int) else focus
    hook_w = cw
    hx0 = int(min(max(sam0[0] - hook_w / 2, 0), 3840 * src_h / 2160 - hook_w))
    z0, z1 = cfg.get("hook_zoom", (1.3, 1.42))
    hook_lines = [(t, caption_img(text)) for t, text in cfg["hook_lines"]]
    a, b = marks[cfg["take"][0]], marks[cfg["take"][1]]

    outs = {}
    for variant in ("captions", "clean"):
        path = os.path.join(out_dir, "%s-9x16%s.mp4" % (cfg["out"], "" if variant == "captions" else "-clean"))
        silent = path + ".video.mp4"
        enc = subprocess.Popen([FF, "-hide_banner", "-loglevel", "error", "-y", "-f", "rawvideo", "-pix_fmt",
                                "rgb24", "-s", "%dx%d" % (W, H), "-r", str(FPS), "-i", "-", "-c:v", "libx264",
                                "-preset", "slow", "-crf", "17", "-pix_fmt", "yuv420p", silent], stdin=subprocess.PIPE)

        def put(img):
            enc.stdin.write(np.clip(img, 0, 255).astype(np.uint8).tobytes())

        def overlays(img, f, to_out, show_caps, k):
            """The SAM's counter (and, with captions, the caption and its rings) on frame f."""
            if cfg.get("counter", True) and f in ammo and f in track:
                n, dead = int(ammo[f][0]), ammo[f][0] < 0
                last_alive = max((g for g in ammo if g <= f and ammo[g][0] >= 0), default=None)
                if not dead or (last_alive is not None and f - last_alive < 45):
                    sx, sy = to_out(*track[f][0])
                    pill = ammo_pill(n, dead)
                    paste(img, pill, sx - pill.width / 2, sy + 52)
            if not show_caps:
                return
            cur = [c for c in caps if c[0] <= f]
            if not cur:
                return
            f0, layer, rings = cur[-1]
            if layer is None:
                return
            nxt = [c[0] for c in caps if c[0] > f]
            t = (f - f0) / FPS
            lay, e = pop(layer, t)
            fade = min(1.0, (nxt[0] - f) / 3) if nxt else 1.0
            paste(img, lay, (W - lay.width) / 2, 520 - lay.height / 2, e * fade)
            for idx, tag in rings:
                if f in track:
                    ring(img, *to_out(*track[f][idx]), tag, e * fade, t, tag_font)

        # 1. the hook
        for i, fr in enumerate(frames(movie, ha, hb, (hook_w, src_h, hx0, 0))):
            f = ha + i
            p = i / (hb - ha)
            z = z0 + (z1 - z0) * p                 # a slow push in
            zw, zh = hook_w / z, src_h / z
            sx, sy = (track[f][focus] if f in track else sam0) if isinstance(focus, int) else focus
            zx = min(max(sx - hx0 - zw / 2, 0), hook_w - zw)
            zy = min(max(sy - zh * 0.55, 0), src_h - zh)
            im = Image.fromarray(fr).resize((W, H), Image.LANCZOS, box=(zx, zy, zx + zw, zy + zh))
            img = np.asarray(im, np.float32)
            img = scary(img, 1.0) if cfg.get("hook_look", "scary") == "scary" else punchy(img)

            def to_out(x, y, zx=zx, zy=zy, z=z):
                return (x - hx0 - zx) * W / zw, (y - zy) * H / zh
            overlays(img, f, to_out, False, 1.0)
            if variant == "captions":
                t = i / FPS
                cur = [h for h in hook_lines if h[0] <= t]
                if cur:
                    lay, e = pop(cur[-1][1], t - cur[-1][0])
                    paste(img, lay, (W - lay.width) / 2, 600 - lay.height / 2, e)
            put(img)
        hook_frames = hb - ha
        # 2. black, then "N seconds earlier"
        black = np.zeros((H, W, 3), np.float32)
        for _ in range(int(0.3 * FPS)):
            put(black)
        card = Image.new("RGBA", (W, 120), (0, 0, 0, 0))
        ImageDraw.Draw(card).text((W // 2, 60), cfg["earlier"], font=font(52, "Bold"), fill=(235, 235, 235),
                                  anchor="mm")
        n_card = int(1.1 * FPS)
        for i in range(n_card):
            img = black.copy()
            e = min(1.0, i / 6, (n_card - i) / 6)
            paste(img, card, 0, H / 2 - 60, e)
            put(img)
        # 3. the scene, full screen
        for i, fr in enumerate(frames(movie, a, b, (cw, src_h, cx0, 0), (W, H))):
            f = a + i
            img = fr.astype(np.float32)
            if i < 8:                              # out of black
                img *= i / 8

            def to_out(x, y):
                return (x - cx0) * s, y * s
            overlays(img, f, to_out, variant == "captions", 1.0)
            put(img)
        enc.stdin.close()
        enc.wait()
        outs[variant] = path
        print("video", variant, "hook", hook_frames, "scene", b - a)

    # Sound: the game under the hook with a rumble rising into a thud; a whoosh over the
    # card; the game's own sound under the scene.
    hook_s, gap_s, card_s = (hb - ha) / FPS, 0.3, 1.1
    total = hook_s + gap_s + card_s + (b - a) / FPS
    mix = np.zeros((int(total * SR) + SR, 2))

    def add(x, at, gain=1.0):
        x = np.asarray(x, np.float64)
        if x.ndim == 1:
            x = np.stack([x, x], 1)
        i = int(at * SR)
        mix[i:i + len(x)] += x[: len(mix) - i] * gain

    g = sfx(rec, marks, ha, hb, rng) if cfg.get("sfx") else game_audio(movie, ha / FPS, hb / FPS)
    g = g[: int(hook_s * SR)]
    g[-int(0.05 * SR):] *= np.linspace(1, 0, int(0.05 * SR))[:, None]
    add(g, 0.0, 0.9)
    if cfg.get("rumble", True):
        add(rumble(hook_s, rng), 0.0, 0.5)
    add(thud(rng), hook_s, 0.8)
    add(whoosh(rng), hook_s + gap_s, 1.0)
    g = sfx(rec, marks, a, b, rng) if cfg.get("sfx") else game_audio(movie, a / FPS, b / FPS)
    fi = int(0.25 * SR)
    g[:fi] *= np.linspace(0, 1, fi)[:, None]
    add(g, hook_s + gap_s + card_s, 1.0)
    mix = mix[: int(total * SR)]
    wav = os.path.join(out_dir, "%s.mix.wav" % cfg["out"])
    with wave.open(wav, "wb") as wf:
        wf.setnchannels(2)
        wf.setsampwidth(2)
        wf.setframerate(SR)
        wf.writeframes((np.clip(mix / max(1e-9, np.abs(mix).max()) * 0.9, -1, 1) * 32767).astype(np.int16).tobytes())
    meas = subprocess.run([FF, "-hide_banner", "-i", wav, "-af", "ebur128=framelog=quiet", "-f", "null", "-"],
                          capture_output=True, text=True).stderr
    lufs = float([ln for ln in meas.splitlines() if ln.strip().startswith("I:")][-1].split()[1])
    gain = max(-20.0, min(20.0, -16.0 - lufs))
    for variant, path in outs.items():
        silent = path + ".video.mp4"
        subprocess.run([FF, "-hide_banner", "-loglevel", "error", "-y", "-i", silent, "-i", wav, "-map", "0:v",
                        "-map", "1:a", "-c:v", "copy", "-af", "volume=%.1fdB,alimiter=limit=0.85:level=0,aresample=48000" % gain,
                        "-c:a", "aac", "-b:a", "192k", "-shortest", "-movflags", "+faststart", path], check=True)
        os.remove(silent)
        print("wrote", path)
    os.remove(wav)


def main():
    name, rec, out_dir = sys.argv[1], sys.argv[2], sys.argv[3]
    os.makedirs(out_dir, exist_ok=True)
    render(name, rec, out_dir)


if __name__ == "__main__":
    main()
