"""The interface sounds: short, soft ticks with nothing low in them, so a
click never thumps like a pop.

    python tools/ui_sounds.py assets/audio

writes click.wav (buttons, building, launching: a light glassy tick) and
click_off.wav (a refusal, or a site finished: a duller double tick).
"""
import os
import sys
import wave

import numpy as np

RATE = 44100


def tick(freq_from, freq_to, decay, length=0.05, level=0.3):
    """A sine that falls from freq_from to freq_to, dying away in `decay`
    seconds, with a little octave-up shimmer and a soft 0.5 ms attack."""
    t = np.arange(int(RATE * length)) / RATE
    freq = freq_to + (freq_from - freq_to) * np.exp(-t / 0.012)
    phase = 2 * np.pi * np.cumsum(freq) / RATE
    env = (1 - np.exp(-t / 0.0005)) * np.exp(-t / decay)
    wave_ = np.sin(phase) + 0.18 * np.sin(2 * phase) * np.exp(-t / (decay * 0.5))
    out = wave_ * env
    return out / np.max(np.abs(out)) * level


def save(path, x):
    # Fade the last 5 ms so the file ends at silence, not on a click of its own.
    n = int(RATE * 0.005)
    x[-n:] *= np.linspace(1, 0, n)
    data = (np.clip(x, -1, 1) * 32767).astype("<i2")
    with wave.open(path, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(RATE)
        w.writeframes(data.tobytes())


def main():
    out = sys.argv[1] if len(sys.argv) > 1 else os.path.join("assets", "audio")
    save(os.path.join(out, "click.wav"), tick(2900, 1900, 0.009, 0.045, 0.32))
    first = tick(1250, 950, 0.012, 0.05, 0.28)
    second = tick(1050, 800, 0.012, 0.05, 0.2)
    gap = int(RATE * 0.055)
    both = np.zeros(gap + len(second))
    both[: len(first)] += first
    both[gap:] += second
    save(os.path.join(out, "click_off.wav"), both)
    print("wrote click.wav and click_off.wav to", out)


if __name__ == "__main__":
    main()
