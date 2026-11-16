"""Synthesises assets/audio/minigun_loop.wav: the armoured AA gun's rotary
cannon firing, a seamless one-second loop. About 50 rounds a second, so the
shots blur into a growl ("brrrt"), each a sharp crack over a low thump, with
the faint whine of the motor spinning the barrels and a little room behind.

    python tools/minigun_sound.py
"""
import wave
import numpy as np

SR = 44100
RATE = 50          # rounds a second
LOOP = 1.0         # seconds (a whole number of rounds, so it loops clean)
rng = np.random.default_rng(11)


def lowpass(x, cut):
    a = 1.0 - np.exp(-2 * np.pi * cut / SR)
    y = np.empty_like(x)
    s = 0.0
    for i in range(len(x)):
        s += a * (x[i] - s)
        y[i] = s
    return y


def shot(n):
    t = np.arange(n) / SR
    crack = lowpass(rng.standard_normal(n), 3400) * np.exp(-t / 0.0045)
    thump = np.sin(2 * np.pi * (95 + 60 * np.exp(-t / 0.004)) * t) * np.exp(-t / 0.009)
    return crack * 1.0 + thump * 0.9


def build():
    total = int(SR * LOOP * 3)
    out = np.zeros(total + SR)
    period = SR / RATE
    k = 0
    while k * period < total:
        i = int(k * period + rng.integers(-25, 25))
        s = shot(int(0.03 * SR)) * (0.85 + 0.3 * rng.random())
        if i >= 0:
            out[i:i + len(s)] += s
        k += 1
    out = out[:total]
    t = np.arange(total) / SR
    # The motor's whine, and the hum of the rotating barrels at the firing rate.
    out += 0.05 * np.sin(2 * np.pi * 420 * t) + 0.03 * np.sin(2 * np.pi * 840 * t)
    out += 0.12 * np.sin(2 * np.pi * RATE * t)
    # A short slap back off the ground: a few delayed, dulled copies.
    room = np.zeros_like(out)
    for d_ms, g in [(23, 0.35), (41, 0.22), (67, 0.12)]:
        d = int(d_ms * SR / 1000)
        room[d:] += g * out[:-d]
    out = out + lowpass(room, 1800)
    # The middle second: the room has filled it, its rounds fall on the grid,
    # so it joins its own start without a seam.
    mid = out[int(SR * LOOP): int(SR * LOOP * 2)]
    x = np.tanh(2.2 * mid / np.max(np.abs(mid)))
    return x / np.max(np.abs(x)) * 0.85


if __name__ == '__main__':
    x = build()
    with wave.open('assets/audio/minigun_loop.wav', 'wb') as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes((x * 32767).astype('<i2').tobytes())
    print('ok', len(x) / SR)
