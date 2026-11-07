"""A gameplay trailer for Strike Alert: footage of the game itself with a
caption on each beat, in 16:9 (itch.io, YouTube) and 9:16 (TikTok, Reels,
Shorts), ending on the logo and where to play.

    python tools/record_trailer.py REC              # plays and records a staged war
    python tools/gameplay_trailer.py REC itch

writes strike-alert-gameplay-16x9.mp4 (1920x1080) and -9x16.mp4 (1080x1920).
The 16:9 cut shows the whole screen; the 9:16 one shows the part of it where
each beat happens, between a caption above and the logo below. Needs ffmpeg
(pip install imageio-ffmpeg).
"""
import os
import subprocess
import sys
import tempfile

import imageio_ffmpeg
import numpy as np
from PIL import Image, ImageDraw

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from promo_video import BLUE, GOOD, MUTED, PAGE, RED, TEXT, YELLOW, font, logo, pill  # noqa: E402

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ALL_CLEAR = os.path.join(ROOT, "assets", "audio", "all_clear.wav")
FPS = 30
END_SECONDS = 3.0
FULL = (0, 0, 1920, 1080)
MAP = (0, 0, 1470, 1080)  # the map, left of the panel
ACTION = (240, 0, 1680, 1080)  # the front and the panel, for beats that use both
# (from marker, seconds after it, to marker, seconds after it, pill, its colour, headline,
#  the part of the screen the 9:16 cut shows: x, y, width, height)
BEATS = [
    ("alert", 0.0, "alert_end", 0.0, "AIR RAID ALERT", RED, "Drones and missiles cross the front", MAP),
    ("build", 0.0, "build_end", 0.0, "BUILD AIR DEFENCE", BLUE, "AA guns and SAMs, right in their path", ACTION),
    ("defend", 1.0, "defend", 7.0, "SHOOT THEM DOWN", BLUE, "Keep your cities and your capital standing", (0, 0, 1080, 1080)),
    ("strike", 0.0, "strike_end", 0.0, "STRIKE BACK", YELLOW, "Draw a route around their air defence", ACTION),
    ("impact", 0.0, "impact_end", 0.0, "STRIKE BACK", YELLOW, "Take out their factories", (400, 0, 1080, 1080)),
    ("stats", 0.0, "stats_end", 0.0, "WAR STATISTICS", GOOD, "Every raid on the record", FULL),
]
TALL_MIDDLE = 1095  # the 9:16 cut centres the footage on this line


def markers(path):
    marks = {}
    with open(path, encoding="utf-8") as f:
        for line in f:
            parts = line.split()
            if len(parts) >= 3 and parts[2].isdigit():
                marks[parts[1]] = int(parts[2])
    return marks


def wrap(text, f, width):
    lines, line = [], ""
    for word in text.split():
        trial = (line + " " + word).strip()
        if line and f.getlength(trial) > width:
            lines.append(line)
            line = word
        else:
            line = trial
    return lines + [line]


def pill_left(d, x, y, text, colour, f):
    pill(d, x + f.getlength(text) / 2 + 30, y, text, colour, f)


def caption_wide(label, colour, headline):
    """Bottom left of the map, over a shadow that leaves the panel clear."""
    down = np.clip((np.arange(1080) - 700) / 380, 0, 1) ** 1.3
    across = np.clip((1480 - np.arange(1920)) / 180, 0, 1)
    img = Image.new("RGBA", (1920, 1080), PAGE + (0,))
    img.putalpha(Image.fromarray((235 * down[:, None] * across[None, :]).astype(np.uint8)))
    d = ImageDraw.Draw(img)
    pill_left(d, 64, 858, label, colour, font(40, "Black"))
    d.text((64, 1010), headline, font=font(64, "Black"), fill=(255, 255, 255), anchor="ls",
           stroke_width=3, stroke_fill=PAGE)
    return img


def caption_tall(label, colour, headline):
    """A caption above the footage and the logo below it."""
    img = Image.new("RGBA", (1080, 1920), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    pill(d, 540, 170, label, colour, font(44, "Black"))
    f = font(82, "Black")
    for i, line in enumerate(wrap(headline, f, 980)):
        d.text((540, 300 + i * 96), line, font=f, fill=(255, 255, 255), anchor="ma")
    lg = logo(760)
    img.alpha_composite(lg, ((1080 - lg.width) // 2, 1690))
    return img


def end_card(w, h):
    img = Image.new("RGBA", (w, h), PAGE + (255,))
    d = ImageDraw.Draw(img)
    lg = logo(900)
    top = (h - (lg.height + 60 + 78 + 80 + 54 + 40 + 40)) // 2
    img.alpha_composite(lg, ((w - lg.width) // 2, top))
    y = top + lg.height + 60
    pill(d, w // 2, y, "FREE ON ITCH.IO", GOOD, font(46, "Black"))
    d.text((w // 2, y + 78 + 80), "Play in your browser", font=font(54, "Bold"), fill=TEXT, anchor="mm")
    d.text((w // 2, y + 78 + 80 + 75), "tenchery.itch.io/strike-alert", font=font(40, "Medium"), fill=MUTED, anchor="mm")
    return img


def cut(rec, out, tall):
    marks = markers(os.path.join(rec, "markers.txt"))
    w, h = (1080, 1920) if tall else (1920, 1080)
    tmp = tempfile.mkdtemp()
    inputs = ["-i", os.path.join(rec, "movie.avi")]
    for i, beat in enumerate(BEATS):
        path = os.path.join(tmp, "cap%d.png" % i)
        (caption_tall if tall else caption_wide)(*beat[4:7]).save(path)
        inputs += ["-loop", "1", "-framerate", str(FPS), "-i", path]
    end = os.path.join(tmp, "end.png")
    end_card(w, h).save(end)
    inputs += ["-loop", "1", "-framerate", str(FPS), "-t", str(END_SECONDS), "-i", end, "-i", ALL_CLEAR]

    parts, labels = [], []
    for i, (m0, s0, m1, s1, label, _, _, (cx, cy, cw, ch)) in enumerate(BEATS):
        a = marks[m0] + int(round(s0 * FPS))
        b = marks[m1] + int(round(s1 * FPS))
        dur = (b - a) / FPS
        # Godot records full-range JPEG frames; players expect the standard (tv) range.
        video = "[0:v]trim=start_frame=%d:end_frame=%d,setpts=PTS-STARTPTS," % (a, b)
        if tall:
            sh = round(ch * 1080 / cw / 2) * 2
            video += "crop=%d:%d:%d:%d,scale=1080:%d:flags=lanczos,pad=1080:1920:0:%d:color=0x%02X%02X%02X," % (
                cw, ch, cx, cy, sh, TALL_MIDDLE - sh // 2, *PAGE)
        video += "scale=in_range=pc:out_range=tv,setsar=1,format=yuv420p[v%d];" % i
        # The caption fades in when it changes, and stays put when the next beat keeps it.
        fade = "fade=in:st=0:d=0.25:alpha=1," if i == 0 or BEATS[i - 1][4] != label else ""
        parts.append(
            video
            + "[%d:v]trim=duration=%.3f,format=rgba,%ssetpts=PTS-STARTPTS[c%d];" % (i + 1, dur, fade, i)
            + "[v%d][c%d]overlay=0:0:shortest=1,format=yuv420p[sv%d];" % (i, i, i)
            + "[0:a]atrim=%.3f:%.3f,asetpts=PTS-STARTPTS,afade=in:d=0.04,afade=out:st=%.3f:d=0.06[sa%d];"
            % (a / FPS, b / FPS, dur - 0.06, i)
        )
        labels.append("[sv%d][sa%d]" % (i, i))
    n = len(BEATS)
    parts.append(
        "[%d:v]format=yuv420p,fade=in:st=0:d=0.35,setpts=PTS-STARTPTS[ev];" % (n + 1)
        + "[%d:a]aformat=sample_rates=48000:channel_layouts=stereo,atrim=0:%.2f,afade=in:d=0.2,afade=out:st=%.2f:d=0.8[ea];"
        % (n + 2, END_SECONDS, END_SECONDS - 0.8)
    )
    labels.append("[ev][ea]")
    # Loudness as YouTube, Instagram and TikTok play it back (-14 LUFS).
    graph = ("".join(parts) + "".join(labels) + "concat=n=%d:v=1:a=1[outv][cat];" % (n + 1)
             + "[cat]loudnorm=I=-14:TP=-1.5:LRA=11,aresample=48000[outa]")
    cmd = [imageio_ffmpeg.get_ffmpeg_exe(), "-hide_banner", "-loglevel", "error", "-y", *inputs,
           "-filter_complex", graph, "-map", "[outv]", "-map", "[outa]", "-r", str(FPS),
           "-c:v", "libx264", "-preset", "slow", "-crf", "18", "-pix_fmt", "yuv420p", "-color_range", "tv",
           "-c:a", "aac", "-b:a", "192k", "-movflags", "+faststart", out]
    subprocess.run(cmd, check=True)
    print("wrote", out)


def main():
    rec, out = sys.argv[1], sys.argv[2]
    cut(rec, os.path.join(out, "strike-alert-gameplay-16x9.mp4"), tall=False)
    cut(rec, os.path.join(out, "strike-alert-gameplay-9x16.mp4"), tall=True)


if __name__ == "__main__":
    main()
