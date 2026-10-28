"""Builds the game's sounds: sirens cut from a real recording, explosions synthesized."""
import sys, numpy as np, soundfile as sf
from scipy import signal

SR = 44100
src, out = sys.argv[1], sys.argv[2]
rng = np.random.default_rng(7)

def norm(x, peak=0.89):
    return x / (np.max(np.abs(x)) + 1e-9) * peak

def fade(x, a=0.01, b=0.05):
    n1, n2 = int(a*SR), int(b*SR)
    x = x.copy()
    if n1: x[:n1] *= np.linspace(0, 1, n1)
    if n2: x[-n2:] *= np.linspace(1, 0, n2) ** 2
    return x

def save(name, x):
    sf.write(f"{out}/{name}", norm(x).astype(np.float32), SR, subtype="PCM_16")

def t(d): return np.arange(int(d*SR)) / SR

def lp(x, fc, order=2):
    b, a = signal.butter(order, fc/(SR/2), "low"); return signal.lfilter(b, a, x)
def hp(x, fc, order=2):
    b, a = signal.butter(order, fc/(SR/2), "high"); return signal.lfilter(b, a, x)
def bp(x, lo, hi, order=2):
    b, a = signal.butter(order, [lo/(SR/2), hi/(SR/2)], "band"); return signal.lfilter(b, a, x)

def sweep_lp(x, f0, f1, tau):
    """One-pole low-pass whose cutoff falls from f0 to f1 with time constant tau."""
    n = len(x); tt = np.arange(n)/SR
    fc = f1 + (f0-f1)*np.exp(-tt/tau)
    a = np.exp(-2*np.pi*fc/SR)
    y = np.empty(n); s = 0.0
    for i in range(n):
        s = a[i]*s + (1-a[i])*x[i]; y[i] = s
    # second pass for a steeper slope
    z = np.empty(n); s = 0.0
    for i in range(n):
        s = a[i]*s + (1-a[i])*y[i]; z[i] = s
    return z

def brown(n):
    w = rng.standard_normal(n); b = np.cumsum(w); b = hp(b, 15); return b/np.max(np.abs(b))

def reverb(x, decay=1.6, mix=0.35, echoes=((0.23, .35), (0.41, .22), (0.67, .14)), lpf=2500):
    """Outdoor tail: diffuse decaying noise plus slapback echoes off buildings."""
    n = int(decay*SR*1.2)
    ir = rng.standard_normal(n) * np.exp(-np.arange(n)/SR * 6.9/decay)
    ir = lp(ir, lpf); ir /= np.sqrt(np.sum(ir**2))
    wet = signal.fftconvolve(x, ir)[:len(x)+n]
    wet = np.pad(wet, (0, len(x)+n-len(wet)))
    y = np.concatenate([x, np.zeros(n)])
    for d, g in echoes:
        k = int(d*SR); e = lp(np.concatenate([np.zeros(k), x]), lpf*0.7)[:len(y)]
        y[:len(e)] += g*e
    return (1-mix)*y + mix*wet*np.max(np.abs(x))/(np.max(np.abs(wet))+1e-9)

def boom(dur, thump_f=(95, 32), body=1.0, crack=1.0, rumble=1.0, bright=3200, tail=1.8, debris=0.0):
    n = int(dur*SR); tt = np.arange(n)/SR; x = np.zeros(n)
    # Shock: a few ms of broadband crack.
    c = rng.standard_normal(n) * np.exp(-tt/0.006)
    x += crack * 0.45 * lp(hp(c, 300), 6000)
    # Fireball: noise whose brightness collapses fast.
    f = rng.standard_normal(n) * (1-np.exp(-tt/0.002)) * np.exp(-tt/0.22)
    x += body * 1.1 * sweep_lp(f, bright, 180, 0.06)
    # Thump: falling sine, the chest punch.
    fr = thump_f[1] + (thump_f[0]-thump_f[1])*np.exp(-tt/0.12)
    ph = 2*np.pi*np.cumsum(fr)/SR
    x += body * 2.2 * np.sin(ph) * (1-np.exp(-tt/0.003)) * np.exp(-tt/0.35)
    # Rumble: brown noise rolling on, swelling a little and dying slowly.
    r = brown(n) * (1-np.exp(-tt/0.05)) * np.exp(-tt/tail)
    am = 1 + 0.35*lp(rng.standard_normal(n), 3)*12
    x += rumble * 1.3 * lp(r*am, 260)
    # Debris: scattered small impacts.
    if debris:
        d = np.zeros(n)
        for _ in range(int(60*debris)):
            at = rng.uniform(0.15, min(dur*0.8, 2.2)); k = int(at*SR)
            ln = int(rng.uniform(0.004, 0.03)*SR)
            if k+ln >= n: continue
            g = rng.uniform(0.05, 0.25) * np.exp(-at/0.9)
            d[k:k+ln] += g*rng.standard_normal(ln)*np.exp(-np.arange(ln)/(ln/4))
        x += 0.6 * bp(d, 600, 4500)
    x = lp(x, 7000)
    x = np.tanh(1.8*x/np.max(np.abs(x))) # punch
    return x

def siren_cut(a, b):
    x, sr = sf.read(src)
    if x.ndim > 1: x = x.mean(axis=1)
    if sr != SR: x = signal.resample_poly(x, SR, sr)
    y = x[int(a*SR):int(b*SR)]
    return hp(y, 120)

# Sirens from the real recording (Ukraine, 2022).
alert = siren_cut(46.9, 59.2)                        # one full wail: rise, hold, fall
save("alert.wav", fade(alert, 0.05, 1.2))
clear = siren_cut(66.6, 74.0)                        # the long final wind-down
save("all_clear.wav", fade(clear, 0.3, 1.5))
fast = siren_cut(58.6, 64.6)                         # rise and hold, sped up and raised
fast = signal.resample_poly(fast, 4, 5)              # 1.25x faster, higher
save("ballistic_warning.wav", fade(fast, 0.03, 0.6))

# Explosions and the rest, synthesized.
save("explosion_a.wav",       fade(reverb(boom(3.0, (90, 30), debris=0.6, tail=1.4), 1.8, 0.35), 0.0, 0.4))
save("explosion_b.wav",       fade(reverb(boom(4.5, (70, 24), rumble=1.5, tail=2.4, debris=1.2), 2.6, 0.4,
                                         ((0.31,.4),(0.58,.3),(0.95,.2),(1.4,.1))), 0.0, 0.6))
save("explosion_small_a.wav", fade(reverb(boom(1.6, (130, 45), rumble=0.5, bright=4500, tail=0.6, debris=0.25), 1.1, 0.3), 0.0, 0.25))
# Air burst far up: no thump, muffled crack, long rolling echo.
ib = boom(1.2, (140, 60), crack=0.6, body=0.8, rumble=0.7, bright=2500, tail=0.5)
save("intercept.wav",         fade(reverb(lp(ib, 1800), 1.4, 0.5, ((0.35,.4),(0.7,.25),(1.1,.12)), 1500), 0.0, 0.3))
# Launch: ignition bang, then a roar that recedes (falls in pitch and level).
d = 2.6; tt = t(d); n = len(tt)
roar = sweep_lp(rng.standard_normal(n), 3000, 450, 0.9) * (1-np.exp(-tt/0.08)) * np.exp(-tt/1.0)
crackle = lp(hp(rng.standard_normal(n) * (rng.random(n) < 0.02), 1200), 4000) * np.exp(-tt/0.7) * 0.25
ign = boom(d, (110, 50), crack=0.8, rumble=0.3, tail=0.3) * 0.5
save("launch.wav", fade(reverb(roar + crackle + ign, 1.2, 0.3), 0.0, 0.4))
# Wreck: a building coming down, long grinding rumble full of debris.
d = 3.4; tt = t(d); n = len(tt)
grind = lp(brown(n), 300) * np.exp(-((tt-0.9)/0.9)**2) * 1.4
w = boom(d, (70, 28), crack=0.4, rumble=1.3, tail=1.6, debris=2.0) + grind
save("wreck.wav", fade(reverb(w, 1.6, 0.3), 0.0, 0.5))
print("ok")
