"""Cuts the game's weapon and explosion sounds out of real recordings on
Wikimedia Commons (credited in CREDITS.md).

    python tools/cut_sounds.py <cache folder> assets/audio

Needs numpy, imageio-ffmpeg (for its ffmpeg) and curl. The recordings are
downloaded into the cache folder once. Each clip is loudness-matched to the
file it replaces in the output folder, so the in-game volumes keep their
balance. The one-shot sirens are cut by hand (see CREDITS.md); clicks are untouched.
"""
import os, subprocess, sys, time, urllib.parse, wave
import numpy as np
import imageio_ffmpeg

SR = 44100
CACHE, OUT = sys.argv[1:3]

SOURCES = {
    "shahed": "Ukrainian f16 destroys shahed type drone.webm",
    "gepard": "Flakpanzer Gepards engage long range simulated targets.webm",
    "patriot": "Patriot Live Fire (563866).webm",
    "war": "Dragout - War sounds (cc0) (freesound).ogg",
    "tomahawk": "USS Spruance (DDG 111) Fires a Tomahawk Land Attack Missile (997803).webm",
    "demolition": "Sprengung Dach Deutschlandhalle.ogv",
    "siren": "Air Raid Alert - Ukraine during russian invasion 2022.ogg",
}


def fetch(key):
    """Downloads a recording once and decodes it to 44.1 kHz mono."""
    wav = os.path.join(CACHE, key + ".wav")
    if not os.path.exists(wav):
        title = SOURCES[key]
        src = os.path.join(CACHE, key + os.path.splitext(title)[1])
        url = "https://commons.wikimedia.org/wiki/Special:FilePath/" + urllib.parse.quote(title.replace(" ", "_"))
        for attempt in range(5):
            subprocess.run(["curl", "-sSL", "-A", "AirAlertSounds/1.0", "-o", src, url], check=True)
            if open(src, "rb").read(15) != b"<!DOCTYPE html>":
                break
            time.sleep(45)    # Commons rate-limits quick downloads
        else:
            sys.exit(f"could not download {title}")
        subprocess.run([imageio_ffmpeg.get_ffmpeg_exe(), "-v", "error", "-y", "-i", src, "-vn",
                        "-ac", "1", "-ar", str(SR), "-c:a", "pcm_s16le", wav], check=True)
    return read(wav)


def read(path):
    with wave.open(path) as w:
        return np.frombuffer(w.readframes(w.getnframes()), "<i2").astype(float) / 32768


def highpass(x, cut):
    a = np.exp(-2 * np.pi * cut / SR)
    y = np.empty_like(x)
    s = prev = 0.0
    for i, v in enumerate(x):
        s = a * (s + v - prev)
        prev = v
        y[i] = s
    return y


def lowpass(x, cut):
    a = 1 - np.exp(-2 * np.pi * cut / SR)
    y = np.empty_like(x)
    s = 0.0
    for i, v in enumerate(x):
        s += a * (v - s)
        y[i] = s
    return y


def clip(key, start, end, fade_in=0.004, fade_out=0.3, high=None):
    """The stretch start..end seconds of a recording, rumble-filtered and faded."""
    x = highpass(fetch(key)[int(start * SR):int(end * SR)], 35)
    if high:
        x = lowpass(lowpass(x, high), high)
    n = int(fade_in * SR)
    x[:n] *= np.linspace(0, 1, n)
    n = int(fade_out * SR)
    x[-n:] *= np.linspace(1, 0, n) ** 2
    return x


def flatten(x, window=0.4):
    """Evens out slow swells (something passing by) so a loop does not pulse."""
    n = int(window * SR)
    env = np.sqrt(np.convolve(x * x, np.ones(n) / n, mode="same")) + 1e-4
    return x / env * np.median(env)


def loop(x, xfade):
    """A seamless loop: the end cross-fades into the start."""
    n = int(xfade * SR)
    t = np.linspace(0, 1, n)
    return np.concatenate([x[n:-n], x[-n:] * np.cos(t * np.pi / 2) + x[:n] * np.sin(t * np.pi / 2)])


def seam_loop(key, start, end, xfade, search):
    """A loop from start to end, both at the same point of a repeating sound (a
    siren's lowest note, a gun's shot). The end is nudged by up to `search`
    seconds to where the waveform best matches the start, and the two cross-fade."""
    x = highpass(fetch(key), 35)
    a, n, s = int(start * SR), int(xfade * SR), int(search * SR)
    b = max(range(int(end * SR) - s, int(end * SR) + s + 1), key=lambda b: float(np.dot(x[b:b + n], x[a:a + n])))
    out = x[a + n:b + n].copy()
    t = np.linspace(0, 1, n)
    out[-n:] = x[b:b + n] * (1 - t) + x[a:a + n] * t
    return out


def body_rms(x):
    """RMS over the louder half of 20 ms frames: the sound itself, not its silences."""
    n = SR // 50
    frames = np.sqrt(np.mean(x[:len(x) // n * n].reshape(-1, n) ** 2, axis=1))
    return float(np.sqrt(np.mean(np.sort(frames)[len(frames) // 2:] ** 2)))


def save(name, x, like=None, peak=0.89):
    """Writes a clip as loud as the file it replaces, or as `like` for a new one."""
    path = os.path.join(OUT, name)
    match = os.path.join(OUT, like or name)
    if os.path.exists(match):
        x = x * body_rms(read(match)) / body_rms(x)
    m = np.max(np.abs(x))
    if m > peak * 1.6:      # a much louder peak is soft-limited rather than squashing the whole clip
        x = np.tanh(x / m * 1.4) / np.tanh(1.4) * peak
    elif m > peak:
        x = x / m * peak
    with wave.open(path, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes((np.clip(x, -1, 1) * 32767).astype("<i2").tobytes())
    print(f"{name}: {len(x) / SR:.2f} s")


os.makedirs(CACHE, exist_ok=True)
# A Shahed's engine, filmed by the Ukrainian Air Force, evened out and looped.
save("drone_loop.wav", loop(flatten(clip("shahed", 9.0, 12.7, fade_out=0.01, high=4000)), 0.7))
# A missile flying off, low-passed into the cruise missile's roar.
save("cruise_loop.wav", loop(flatten(clip("patriot", 20.0, 26.6, fade_out=0.01, high=2200), 0.8), 1.5))
# A 35 mm Gepard burst.
save("gun.wav", clip("gepard", 10.45, 12.75, fade_out=0.45))
# A Patriot leaving its launcher.
save("sam_launch.wav", clip("patriot", 0.42, 3.4, fade_out=1.2))
# Distant booms: an interceptor's hit in the air, and a drone's small warhead.
save("intercept.wav", clip("war", 10.40, 12.18, fade_out=0.6, high=5000))
save("explosion_small_a.wav", clip("war", 12.20, 14.33, fade_out=0.7))
# Our drone or missile leaving: a Tomahawk's booster lighting.
save("launch.wav", clip("tomahawk", 0.66, 3.3, fade_out=1.0))
# A demolition blast and the collapse after it.
save("explosion_a.wav", clip("demolition", 0.97, 4.4, fade_out=1.6))
save("explosion_b.wav", clip("demolition", 0.97, 6.95, fade_out=2.5))
save("wreck.wav", clip("demolition", 1.35, 6.95, fade_in=0.12, fade_out=2.0))
# The air-raid siren held for as long as an alert lasts: two full wails, lowest note to lowest note.
save("alert_loop.wav", seam_loop("siren", 23.54 - 0.125, 47.24 - 0.125, 0.25, 0.01), like="alert.wav")
# Our guns firing, for exactly as long as they fire: two Gepard barrels in turn, shot to shot.
save("gun_loop.wav", seam_loop("gepard", 11.195, 12.062, 0.003, 0.001), like="gun.wav")
