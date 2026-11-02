"""Synthesises the Air Alert sound set into a folder of 44.1 kHz mono WAVs."""
import sys, wave
import numpy as np

SR = 44100
OUT = sys.argv[1]
rng = np.random.default_rng(7)


def t_of(sec):
    return np.arange(int(sec * SR)) / SR


def lowpass(x, cutoff):
    """One-pole low-pass; cutoff may be a number or an array (per sample)."""
    cut = np.broadcast_to(np.asarray(cutoff, dtype=float), x.shape)
    a = 1.0 - np.exp(-2 * np.pi * cut / SR)
    y = np.empty_like(x)
    s = 0.0
    for i in range(len(x)):
        s += a[i] * (x[i] - s)
        y[i] = s
    return y


def highpass(x, cutoff):
    return x - lowpass(x, cutoff)


def osc(freq, shape="sine"):
    """Oscillator following a per-sample frequency array."""
    ph = 2 * np.pi * np.cumsum(freq) / SR
    if shape == "sine":
        return np.sin(ph)
    if shape == "siren":
        # A rotor siren: strong odd harmonics, rounded.
        return np.sin(ph) + 0.45 * np.sin(3 * ph) + 0.22 * np.sin(5 * ph) + 0.1 * np.sin(7 * ph)
    if shape == "pulse":
        # A buzzy engine: narrow pulse, rich in harmonics.
        return np.tanh(6 * (np.sin(ph) - 0.55))
    raise ValueError(shape)


def env(n, attack, release, total=None):
    e = np.ones(n)
    a = max(1, int(attack * SR))
    r = max(1, int(release * SR))
    e[:a] = np.linspace(0, 1, a)
    e[-r:] *= np.linspace(1, 0, r)
    return e


def decay(t, tau):
    return np.exp(-t / tau)


def reverb(x, wet=0.3, size=1.0):
    """A small Schroeder reverb: four combs and two all-passes."""
    out = np.zeros(len(x) + int(SR * 1.2 * size))
    src = np.concatenate([x, np.zeros(len(out) - len(x))])
    acc = np.zeros_like(out)
    for d_ms, g in [(29.7, 0.78), (37.1, 0.76), (41.1, 0.74), (43.7, 0.72)]:
        d = int(d_ms * size * SR / 1000)
        y = src.copy()
        for i in range(d, len(y)):
            y[i] += g * y[i - d]
        acc += y
    acc /= 4
    for d_ms, g in [(5.0, 0.7), (1.7, 0.7)]:
        d = int(d_ms * SR / 1000)
        y = np.zeros_like(acc)
        for i in range(len(acc)):
            xd = acc[i - d] if i >= d else 0.0
            yd = y[i - d] if i >= d else 0.0
            y[i] = -g * acc[i] + xd + g * yd
        acc = y
    out = src * (1 - wet) + acc * wet
    # Trim the silent tail.
    nz = np.nonzero(np.abs(out) > 1e-4)[0]
    return out[: nz[-1] + 1] if len(nz) else out


def noise(n):
    return rng.standard_normal(n)


def save(name, x, peak=0.89, drive=0.0):
    x = np.asarray(x, dtype=float)
    m = np.max(np.abs(x))
    if drive > 0 and m > 0:
        # Compress: the body of a boom as loud as its first crack.
        x = np.tanh(drive * x / m)
        m = np.max(np.abs(x))
    if m > 0:
        x = x / m * peak
    fade = min(len(x), int(0.004 * SR))
    x[-fade:] *= np.linspace(1, 0, fade)
    data = (x * 32767).astype("<i2").tobytes()
    with wave.open(f"{OUT}/{name}", "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(data)
    print(f"{name}: {len(x) / SR:.2f} s")


def boom(length, low, tau, crack=0.6, bright=2400, rumble=0.5):
    """An explosion: a falling low thump, a bright crack, and a rumbling tail."""
    t = t_of(length)
    f = low * (1 + 1.6 * np.exp(-t / 0.05))
    thump = osc(f) * decay(t, tau * 0.35)
    n = noise(len(t))
    cr = lowpass(n, bright) * decay(t, 0.04) * crack
    body = lowpass(n, 380 + 1800 * np.exp(-t / 0.12)) * decay(t, tau) * 1.2
    rum = lowpass(noise(len(t)), 90) * decay(t, tau * 1.6) * rumble * 6
    return reverb(thump * 1.4 + cr + body + rum, wet=0.25, size=1.3)


# ---------------------------------------------------------------- sirens

def siren():
    # Rises, holds with a slight wobble, falls: the classic air raid wail.
    t = t_of(7.5)
    up, hold, down = 2.4, 2.4, 2.7
    f = np.where(t < up, 170 + (620 - 170) * np.sin(np.minimum(t / up, 1) * np.pi / 2) ** 1.5,
                 np.where(t < up + hold, 620 + 8 * np.sin(2 * np.pi * 0.7 * t),
                          620 - (620 - 160) * (np.clip(t - up - hold, 0, None) / down) ** 0.8))
    x = osc(f, "siren") + 0.7 * osc(f * 1.006, "siren")      # two rotors, a touch apart
    x = lowpass(x, 2600)
    x *= env(len(t), 0.4, 1.4)
    return reverb(x, wet=0.38, size=1.6)


def all_clear():
    # A calm, falling three-note chime.
    out = np.zeros(int(SR * 3.4))
    for k, (f, at) in enumerate([(784, 0.0), (659, 0.45), (523, 0.9)]):
        t = t_of(2.4)
        tone = (np.sin(2 * np.pi * f * t) + 0.35 * np.sin(2 * np.pi * 2 * f * t) + 0.12 * np.sin(2 * np.pi * 3.01 * f * t)) * decay(t, 0.75)
        tone *= env(len(t), 0.01, 0.3)
        i = int(at * SR)
        out[i:i + len(tone)] += tone * (1.0 if k < 2 else 1.15)
    return reverb(out, wet=0.35, size=1.4)


def ballistic_warning():
    # Fast, urgent up-and-down yelp.
    t = t_of(2.8)
    f = 760 + 360 * (0.5 + 0.5 * np.sign(np.sin(2 * np.pi * 3.2 * t))) * 0 + 360 * np.abs((t * 3.2) % 1 * 2 - 1)
    x = osc(f, "siren")
    x = lowpass(x, 3400) * env(len(t), 0.05, 0.5)
    return reverb(x, wet=0.25, size=1.0)


# ---------------------------------------------------------------- engines

def loop_of(x, xfade=0.25):
    """Makes a seamless loop by cross-fading the end into the start."""
    n = int(xfade * SR)
    head, body, tail = x[:n], x[n:-n], x[-n:]
    ramp = np.linspace(0, 1, n)
    return np.concatenate([body, tail * (1 - ramp) + head * ramp])


def drone_loop():
    # A two-stroke moped engine: a buzzing pulse with a wandering pitch.
    t = t_of(4.25)
    wob = 1 + 0.02 * np.sin(2 * np.pi * 0.6 * t) + 0.008 * np.sin(2 * np.pi * 3.1 * t)
    f = 96 * wob
    x = osc(f, "pulse") + 0.5 * osc(f * 2.01, "pulse")
    x = lowpass(x, 1500) + 0.12 * lowpass(noise(len(t)), 900)
    x *= 1 + 0.15 * np.sin(2 * np.pi * 9 * t)
    return loop_of(x)


def cruise_loop():
    # A jet: a hiss and a high, steady whine.
    t = t_of(4.25)
    hiss = highpass(lowpass(noise(len(t)), 3800), 500)
    whine = np.sin(2 * np.pi * (1460 + 12 * np.sin(2 * np.pi * 0.4 * t)) * t) * 0.18
    x = hiss + whine + 0.4 * lowpass(noise(len(t)), 160) * 3
    return loop_of(x)


# ---------------------------------------------------------------- air defence

def gun():
    # A short anti-aircraft burst: five quick shots.
    out = np.zeros(int(SR * 0.9))
    for k in range(5):
        t = t_of(0.18)
        n = noise(len(t))
        shot = (lowpass(n, 2600) * decay(t, 0.025) + osc(np.full(len(t), 120.0)) * decay(t, 0.03) * 0.8)
        i = int(k * 0.085 * SR + rng.integers(0, 200))
        out[i:i + len(shot)] += shot * (1 - 0.08 * k)
    return reverb(out, wet=0.22, size=1.1)


def sam_launch():
    # A missile leaving its launcher: a roaring whoosh that brightens and fades.
    t = t_of(1.8)
    n = noise(len(t))
    cut = 300 + 3200 * (1 - np.exp(-t / 0.25))
    roar = lowpass(n, cut) * env(len(t), 0.02, 1.2) * decay(t, 0.9)
    thump = osc(np.full(len(t), 70.0)) * decay(t, 0.08)
    return reverb(roar * 1.2 + thump, wet=0.3, size=1.4)


def intercept():
    # An interception overhead: a sharp crack and a scattering tail.
    t = t_of(1.4)
    n = noise(len(t))
    crack = lowpass(n, 5200) * decay(t, 0.03)
    tail = lowpass(n, 900) * decay(t, 0.35) * 0.6
    pop = osc(140 * (1 + np.exp(-t / 0.02))) * decay(t, 0.06) * 0.7
    return reverb(crack + tail + pop, wet=0.35, size=1.5)


def launch():
    # One of ours going up: a lighter whoosh.
    t = t_of(1.3)
    n = noise(len(t))
    cut = 500 + 2600 * (1 - np.exp(-t / 0.2))
    return reverb(lowpass(n, cut) * env(len(t), 0.03, 0.9) * decay(t, 0.6), wet=0.25, size=1.2)


def wreck():
    # A site collapsing: rumble and falling debris.
    t = t_of(3.0)
    rum = lowpass(noise(len(t)), 110) * decay(t, 1.0) * 5
    out = rum
    for k in range(14):
        at = rng.uniform(0.05, 1.8)
        d = t_of(0.12)
        hit = lowpass(noise(len(d)), rng.uniform(1200, 3500)) * decay(d, 0.02) * rng.uniform(0.2, 0.6)
        i = int(at * SR)
        out[i:i + len(hit)] += hit
    return reverb(out, wet=0.3, size=1.3)


save("alert.wav", siren())
save("all_clear.wav", all_clear())
save("ballistic_warning.wav", ballistic_warning())
save("drone_loop.wav", drone_loop(), 0.7)
save("cruise_loop.wav", cruise_loop(), 0.6)
save("gun.wav", gun(), drive=3.0)
save("sam_launch.wav", sam_launch())
save("intercept.wav", intercept(), drive=3.5)
save("launch.wav", launch())
save("explosion_small_a.wav", boom(1.6, 70, 0.28, crack=0.5, bright=2600, rumble=0.35), drive=4.0)
save("explosion_a.wav", boom(2.6, 55, 0.45, crack=0.7, bright=2200, rumble=0.6), drive=4.0)
save("explosion_b.wav", boom(3.6, 42, 0.7, crack=0.9, bright=1900, rumble=0.9), drive=4.0)
save("wreck.wav", wreck(), drive=3.0)
