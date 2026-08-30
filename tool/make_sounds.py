"""Meet's three sounds, synthesised rather than sourced.

DESIGN.md §3.7 sets the grammar: join is two ascending notes because arrival is
resolved, knock is one note struck twice because repetition is what a knock is
and it stays unresolved on purpose, and the ringback is the double-ring cadence
Nigerian networks inherited from NITEL's UK practice — 400Hz and 450Hz together,
0.4s on, 0.2s off, 0.4s on, 2s silent.

Synthesised because a downloaded tone carries a licence into a fintech app's
store listing, and because these need to be *quiet*: every free notification
sound on the internet is mastered loud, which is the one thing a sound that
fires during a meeting must not be.

WAV, not the .ogg the design first assumed: this machine has no vorbis encoder,
and Flutter's audioplayers plays WAV on both platforms. 16kHz mono is above
Nyquist for every partial here, and 16-bit keeps the decay tails clean — 8-bit
quantisation noise is audible under a fade to silence, which is exactly where
these end.

    python3 tool/make_sounds.py
"""

import math
import struct
import wave

RATE = 16000
PEAK = 32767


def envelope(i, n, attack=0.008, release=0.030, tau=0.070):
    """Attack, exponential decay, and a forced release to true zero.

    The release matters more than it looks: a tone cut off mid-cycle produces a
    click, and a click is what makes a synthesised sound read as synthesised.
    """
    t = i / RATE
    total = n / RATE
    a = min(1.0, t / attack) if attack else 1.0
    d = math.exp(-t / tau) if tau else 1.0
    left = total - t
    r = min(1.0, left / release) if release else 1.0
    return a * d * r


def tone(freq, seconds, gain, partials=((1.0, 1.0), (2.0, 0.14)), **env):
    n = int(RATE * seconds)
    out = []
    for i in range(n):
        t = i / RATE
        v = sum(amp * math.sin(2 * math.pi * freq * mult * t) for mult, amp in partials)
        v /= sum(amp for _, amp in partials)
        out.append(v * gain * envelope(i, n, **env))
    return out


def dual(f1, f2, seconds, gain):
    """Two frequencies at equal weight — a telephone tone, not a musical note."""
    n = int(RATE * seconds)
    out = []
    for i in range(n):
        t = i / RATE
        v = 0.5 * (math.sin(2 * math.pi * f1 * t) + math.sin(2 * math.pi * f2 * t))
        # Square-ish gating, softened at both ends so the cadence does not click.
        edge = 0.006
        ramp = min(1.0, t / edge, (seconds - t) / edge)
        out.append(v * gain * max(0.0, ramp))
    return out


def silence(seconds):
    return [0.0] * int(RATE * seconds)


def write(name, samples):
    frames = bytearray()
    for v in samples:
        frames += struct.pack("<h", max(-PEAK, min(PEAK, int(round(v * PEAK)))))
    with wave.open("assets/sounds/" + name, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(RATE)
        w.writeframes(bytes(frames))
    peak = max(abs(v) for v in samples) if samples else 0
    print(
        f"{name:16} {len(samples) / RATE:.2f}s  "
        f"{(len(samples) * 2 + 44) / 1024:6.1f}KB  peak {peak:.2f}"
    )


# Join — E5 then B5, a rising fifth. Quiet, because it fires while people talk.
write("join.wav", tone(659.25, 0.10, 0.26) + silence(0.02) + tone(987.77, 0.16, 0.24))

# Knock — D5 twice at the same pitch. Going nowhere is the point: someone is
# still outside.
write("knock.wav", tone(587.33, 0.11, 0.30, tau=0.055) * 1 + silence(0.085) + tone(587.33, 0.13, 0.30, tau=0.055))

# Ringback — the double ring, then two seconds of nothing. The player loops it,
# so the silence has to live in the file for the cadence to survive the loop.
write(
    "ringback.wav",
    dual(400, 450, 0.40, 0.30)
    + silence(0.20)
    + dual(400, 450, 0.40, 0.30)
    + silence(2.00),
)
