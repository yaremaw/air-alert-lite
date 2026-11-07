"""A 9:16 promo video (1080x1920, about 12 s) for Instagram and TikTok, cut from
a Movie Maker recording of the game with captions and an end card.

    python tools/promo_video.py MOVIE.avi itch/strike-alert-9x16.mp4

MOVIE.avi is a 1080x1920, 30 fps recording (godot --write-movie) whose frames
match SEGMENTS below. Needs ffmpeg (pip install imageio-ffmpeg).
"""
import os
import subprocess
import sys
import tempfile

import imageio_ffmpeg
from PIL import Image, ImageDraw, ImageFont

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
FONT = os.path.join(ROOT, "assets", "fonts", "Inter.ttf")
LOGO = os.path.join(ROOT, "itch", "logo.png")
ALL_CLEAR = os.path.join(ROOT, "assets", "audio", "all_clear.wav")
W, H, FPS = 1080, 1920, 30
PAGE = (0x16, 0x18, 0x1D)
TEXT = (0xE8, 0xEA, 0xEE)
MUTED = (0x8B, 0x91, 0x9D)
RED = (0xE0, 0x57, 0x4A)
YELLOW = (0xE5, 0xAD, 0x16)
BLUE = (0x4E, 0xA1, 0xFF)
GOOD = (0x46, 0xC4, 0x7E)

# (first frame, last frame, pill text, pill colour, headline)
SEGMENTS = [
    (25, 115, "AIR RAID ALERT", RED, "DRONES ARE\nCOMING"),
    (175, 265, "AIR DEFENCE", YELLOW, "SHOOT THEM\nDOWN"),
    (450, 548, "STRIKE BACK", BLUE, "HIT THEIR\nFACTORIES"),
]
END_SECONDS = 3.0


def font(size, weight):
    f = ImageFont.truetype(FONT, size)
    f.set_variation_by_name(weight)
    return f


def logo(width):
    lg = Image.open(LOGO).convert("RGBA")
    return lg.resize((width, round(lg.height * width / lg.width)), Image.LANCZOS)


def shade(img, top):
    """Darkens the top of the frame so the caption reads over any map."""
    d = ImageDraw.Draw(img)
    for y in range(top):
        d.line([(0, y), (W, y)], fill=PAGE + (int(225 * (1 - y / top) ** 1.4),))


def pill(d, cx, y, text, colour, f):
    tw = f.getlength(text)
    x0 = cx - tw / 2 - 30
    d.rounded_rectangle([x0, y, x0 + tw + 60, y + 78], radius=39, fill=colour)
    d.text((cx, y + 39), text, font=f, fill=PAGE if colour in (YELLOW, GOOD) else (255, 255, 255), anchor="mm")


def caption(label, colour, headline):
    img = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    shade(img, 900)
    lg = logo(420)
    img.alpha_composite(lg, ((W - lg.width) // 2, 170))
    d = ImageDraw.Draw(img)
    pill(d, W // 2, 330, label, colour, font(42, "Black"))
    d.multiline_text((W // 2, 440), headline, font=font(118, "Black"), fill=(255, 255, 255),
                     anchor="ma", align="center", spacing=8, stroke_width=4, stroke_fill=PAGE)
    return img


def end_card():
    img = Image.new("RGBA", (W, H), PAGE + (255,))
    d = ImageDraw.Draw(img)
    lg = logo(900)
    img.alpha_composite(lg, ((W - lg.width) // 2, 700))
    pill(d, W // 2, 1000, "FREE ON ITCH.IO", GOOD, font(46, "Black"))
    d.text((W // 2, 1135), "Play in your browser", font=font(54, "Bold"), fill=TEXT, anchor="mm")
    d.text((W // 2, 1210), "tenchery.itch.io/strike-alert", font=font(40, "Medium"), fill=MUTED, anchor="mm")
    return img


def main():
    movie, out = sys.argv[1], sys.argv[2]
    ff = imageio_ffmpeg.get_ffmpeg_exe()
    tmp = tempfile.mkdtemp()
    inputs = ["-i", movie]
    for i, (_, _, label, colour, headline) in enumerate(SEGMENTS):
        path = os.path.join(tmp, "cap%d.png" % i)
        caption(label, colour, headline).save(path)
        inputs += ["-loop", "1", "-framerate", str(FPS), "-i", path]
    end = os.path.join(tmp, "end.png")
    end_card().save(end)
    inputs += ["-loop", "1", "-framerate", str(FPS), "-t", str(END_SECONDS), "-i", end, "-i", ALL_CLEAR]

    parts, labels = [], []
    for i, (a, b, *_) in enumerate(SEGMENTS):
        dur = (b - a + 1) / FPS
        t0, t1 = a / FPS, (b + 1) / FPS
        cap = i + 1
        parts.append(
            # Godot records full-range JPEG frames; phones expect the standard (tv) range.
            "[0:v]trim=start_frame=%d:end_frame=%d,setpts=PTS-STARTPTS,"
            "scale=in_range=pc:out_range=tv,format=yuv420p[v%d];" % (a, b + 1, i)
            + "[%d:v]trim=duration=%.3f,format=rgba,fade=in:st=0:d=0.25:alpha=1,setpts=PTS-STARTPTS[c%d];" % (cap, dur, i)
            + "[v%d][c%d]overlay=0:0:shortest=1,format=yuv420p[sv%d];" % (i, i, i)
            + "[0:a]atrim=%.3f:%.3f,asetpts=PTS-STARTPTS,afade=in:d=0.04,afade=out:st=%.3f:d=0.06[sa%d];"
            % (t0, t1, dur - 0.06, i)
        )
        labels.append("[sv%d][sa%d]" % (i, i))
    n = len(SEGMENTS)
    endv, enda = n + 1, n + 2
    parts.append(
        "[%d:v]format=yuv420p,fade=in:st=0:d=0.35,setpts=PTS-STARTPTS[ev];" % endv
        + "[%d:a]aformat=sample_rates=48000:channel_layouts=stereo,atrim=0:%.2f,afade=in:d=0.2,afade=out:st=%.2f:d=0.8[ea];"
        % (enda, END_SECONDS, END_SECONDS - 0.8)
    )
    labels.append("[ev][ea]")
    # Loudness as Instagram and TikTok play it back (-14 LUFS).
    graph = ("".join(parts) + "".join(labels) + "concat=n=%d:v=1:a=1[outv][cat];" % (n + 1)
             + "[cat]loudnorm=I=-14:TP=-1.5:LRA=11,aresample=48000[outa]")
    cmd = [ff, "-hide_banner", "-loglevel", "error", "-y", *inputs, "-filter_complex", graph,
           "-map", "[outv]", "-map", "[outa]", "-r", str(FPS),
           "-c:v", "libx264", "-preset", "slow", "-crf", "18", "-pix_fmt", "yuv420p", "-color_range", "tv",
           "-c:a", "aac", "-b:a", "192k", "-movflags", "+faststart", out]
    subprocess.run(cmd, check=True)
    print("wrote", out)


if __name__ == "__main__":
    main()
