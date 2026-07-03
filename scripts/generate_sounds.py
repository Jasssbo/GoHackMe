#!/usr/bin/env python3
"""
generate_sounds.py – Synthesise all GoHackMe audio assets.

Produces 18 WAV files (mono, 22 kHz, 16-bit PCM) in app/assets/audio/.
All sounds are cyberpunk / networking-themed and matched to their in-game
context: stone placement, captures, attacks, timers, lobby, etc.

Usage:
    python3 scripts/generate_sounds.py
    python3 scripts/generate_sounds.py /custom/output/dir

Requirements: Python 3.8+ – stdlib only (wave, struct, math, random).
"""

import math
import os
import random
import struct
import sys
import wave

RATE = 22050  # Hz – good balance of quality vs file size

random.seed(42)  # reproducible results

# ── Low-level primitives ─────────────────────────────────────────────────────

def _clip(s: float) -> float:
    return max(-0.999, min(0.999, s))

def write_wav(path: str, samples: list) -> None:
    with wave.open(path, 'w') as f:
        f.setnchannels(1)
        f.setsampwidth(2)
        f.setframerate(RATE)
        data = struct.pack(f'<{len(samples)}h',
                           *[int(_clip(s) * 32767) for s in samples])
        f.writeframes(data)

def sine_wave(freq: float, dur: float, amp: float = 0.6) -> list:
    n = int(dur * RATE)
    return [amp * math.sin(2 * math.pi * freq * i / RATE) for i in range(n)]

def square_wave(freq: float, dur: float, amp: float = 0.5) -> list:
    n = int(dur * RATE)
    return [amp * (1.0 if math.sin(2 * math.pi * freq * i / RATE) >= 0 else -1.0)
            for i in range(n)]

def sawtooth_wave(freq: float, dur: float, amp: float = 0.45) -> list:
    n = int(dur * RATE)
    period = RATE / freq
    return [amp * (2.0 * ((i % period) / period) - 1.0) for i in range(n)]

def noise(dur: float, amp: float = 0.35) -> list:
    n = int(dur * RATE)
    return [amp * (random.random() * 2 - 1) for _ in range(n)]

def silence(dur: float) -> list:
    return [0.0] * int(dur * RATE)

def env(samples: list, attack: float = 0.005, decay: float = 0.05,
        sustain: float = 0.7, release: float = 0.05) -> list:
    """ADSR envelope."""
    n = len(samples)
    a = int(attack * RATE)
    d = int(decay * RATE)
    r = int(release * RATE)
    s_len = max(0, n - a - d - r)
    result = []
    for i in range(n):
        if i < a:
            e = i / max(a, 1)
        elif i < a + d:
            e = 1.0 - (1.0 - sustain) * (i - a) / max(d, 1)
        elif i < a + d + s_len:
            e = sustain
        else:
            env_i = i - a - d - s_len
            e = sustain * max(0.0, 1.0 - env_i / max(r, 1))
        result.append(samples[i] * e)
    return result

def fade_out(samples: list, dur: float = 0.03) -> list:
    n = len(samples)
    f = int(dur * RATE)
    out = list(samples)
    for i in range(f):
        if n - f + i < n:
            out[n - f + i] *= max(0.0, 1.0 - i / f)
    return out

def mix(*tracks: list) -> list:
    length = max(len(t) for t in tracks)
    result = [0.0] * length
    for t in tracks:
        for i, s in enumerate(t):
            result[i] += s
    peak = max((abs(s) for s in result), default=1.0)
    if peak > 0.92:
        result = [s / peak * 0.92 for s in result]
    return result

def concat(*tracks: list) -> list:
    out = []
    for t in tracks:
        out.extend(t)
    return out

def pitch_sweep(start_hz: float, end_hz: float, dur: float,
                amp: float = 0.55) -> list:
    """Linear frequency sweep using phase accumulation."""
    n = int(dur * RATE)
    phase = 0.0
    result = []
    for i in range(n):
        t = i / n
        freq = start_hz + (end_hz - start_hz) * t
        phase += 2 * math.pi * freq / RATE
        result.append(amp * math.sin(phase))
    return result

def fm_synth(carrier_hz: float, mod_hz: float, mod_depth: float,
             dur: float, amp: float = 0.55) -> list:
    """Classic FM synthesis: carrier modulated by a sine LFO."""
    n = int(dur * RATE)
    result = []
    carrier_phase = 0.0
    mod_phase = 0.0
    for i in range(n):
        mod_val = mod_depth * math.sin(mod_phase)
        carrier_phase += 2 * math.pi * (carrier_hz + mod_val) / RATE
        mod_phase += 2 * math.pi * mod_hz / RATE
        result.append(amp * math.sin(carrier_phase))
    return result


# ── Core game sounds ─────────────────────────────────────────────────────────

def make_place_node() -> list:
    """Node deployed on the network grid: sharp electronic click with ping."""
    click = env(square_wave(1200, 0.04, 0.45), attack=0.001, decay=0.02, sustain=0.2,  release=0.015)
    ping  = env(sine_wave(2400,  0.08, 0.28), attack=0.002, decay=0.04, sustain=0.15, release=0.030)
    body  = env(sine_wave(600,   0.07, 0.22), attack=0.001, decay=0.03, sustain=0.30, release=0.030)
    return fade_out(mix(click, ping, body), 0.01)

def make_capture() -> list:
    """Group of nodes purged from the network: descending glitch sweep."""
    sweep  = fade_out(pitch_sweep(800, 120, 0.40, amp=0.50), 0.06)
    glitch = env(noise(0.12, 0.40), attack=0.001, decay=0.08, sustain=0.0, release=0.03)
    crunch = env(square_wave(180, 0.25, 0.32), attack=0.001, decay=0.12, sustain=0.0, release=0.10)
    return fade_out(mix(sweep, glitch, crunch), 0.06)

def make_turn_start() -> list:
    """Double ascending ping: your uplink is active."""
    p1  = env(sine_wave(880,  0.07, 0.44), attack=0.003, decay=0.04, sustain=0.0, release=0.02)
    gap = silence(0.04)
    p2  = env(sine_wave(1320, 0.07, 0.40), attack=0.003, decay=0.04, sustain=0.0, release=0.02)
    return fade_out(concat(p1, gap, p2), 0.01)

def make_pass_turn() -> list:
    """Soft downward blip: skipping the turn, passing the token."""
    sweep = fade_out(pitch_sweep(440, 220, 0.15, amp=0.44), 0.04)
    return env(sweep, attack=0.005, decay=0.08, sustain=0.3, release=0.05)

def make_game_win() -> list:
    """Ascending fanfare: G4-B4-D5-G5, then sustained chord."""
    freqs = [392, 494, 587, 784]
    notes = []
    for f in freqs:
        n = env(square_wave(f, 0.12, 0.38), attack=0.005, decay=0.04, sustain=0.65, release=0.03)
        notes.append(n)
        notes.append(silence(0.025))
    chord = mix(
        env(sine_wave(392, 0.50, 0.24), attack=0.01, decay=0.10, sustain=0.60, release=0.18),
        env(sine_wave(494, 0.50, 0.20), attack=0.01, decay=0.10, sustain=0.60, release=0.18),
        env(sine_wave(784, 0.50, 0.20), attack=0.01, decay=0.10, sustain=0.60, release=0.18),
    )
    return fade_out(concat(*notes, chord), 0.08)

def make_game_over() -> list:
    """Descending somber sequence: G4-E4-C4-G3."""
    freqs = [392, 330, 262, 196]
    notes = []
    for f in freqs:
        n = env(sawtooth_wave(f, 0.18, 0.38), attack=0.008, decay=0.06, sustain=0.55, release=0.07)
        notes.append(n)
        notes.append(silence(0.03))
    return fade_out(concat(*notes), 0.08)

def make_boot_beep() -> list:
    """Classic terminal boot beep: single pure sine pulse."""
    return fade_out(env(sine_wave(880, 0.08, 0.50),
                        attack=0.003, decay=0.03, sustain=0.6, release=0.02), 0.01)

def make_menu_select() -> list:
    """Mechanical keypress: square click + noise transient."""
    click = env(square_wave(600, 0.05, 0.45), attack=0.001, decay=0.02, sustain=0.1, release=0.02)
    tick  = env(noise(0.025, 0.28),          attack=0.001, decay=0.015, sustain=0.0, release=0.007)
    return fade_out(mix(click, tick), 0.008)

def make_connect() -> list:
    """Handshake established: two ascending digital pings."""
    p1  = env(sine_wave(660, 0.08, 0.44), attack=0.004, decay=0.04, sustain=0.20, release=0.02)
    gap = silence(0.05)
    p2  = env(sine_wave(880, 0.10, 0.44), attack=0.004, decay=0.05, sustain=0.25, release=0.03)
    return fade_out(concat(p1, gap, p2), 0.01)

def make_timebomb_tick() -> list:
    """Sharp relay click: each tick of the psyche countdown."""
    click = env(square_wave(1000, 0.04, 0.52),
                attack=0.0005, decay=0.010, sustain=0.0, release=0.005)
    return fade_out(click, 0.005)


# ── Attack sounds ─────────────────────────────────────────────────────────────

def make_ddos() -> list:
    """DDOS.sh – flood of junk packets: aggressive burst of digital noise."""
    body  = env(noise(0.35, 0.55),           attack=0.005, decay=0.05, sustain=0.80, release=0.10)
    tone  = env(square_wave(240, 0.35, 0.28), attack=0.003, decay=0.08, sustain=0.50, release=0.08)
    alarm = pitch_sweep(800, 300, 0.30, amp=0.34)
    return fade_out(mix(body, tone, alarm), 0.06)

def make_trojan() -> list:
    """TROJAN.sh – starts sweet (gift), ends corrupt (payload detonates)."""
    sweet   = env(sine_wave(880, 0.22, 0.38),        attack=0.010, decay=0.05, sustain=0.60, release=0.03)
    corrupt = env(fm_synth(220, 60, 180, 0.28, 0.44), attack=0.020, decay=0.08, sustain=0.40, release=0.10)
    glitch  = env(noise(0.16, 0.30),                  attack=0.050, decay=0.05, sustain=0.00, release=0.05)
    pad_short  = [0.0] * int(0.05 * RATE)
    pad_medium = [0.0] * int(0.18 * RATE)
    pad_long   = [0.0] * int(0.26 * RATE)
    total = len(sweet) + int(0.05 * RATE)
    clen = max(total, len(pad_medium) + len(corrupt))
    glen = max(clen,  len(pad_long)  + len(glitch))
    def pad_to(lst, length):
        return lst + [0.0] * max(0, length - len(lst))
    s = pad_to(pad_short + sweet,   glen)
    c = pad_to(pad_medium + corrupt, glen)
    g = pad_to(pad_long  + glitch,  glen)
    return fade_out(mix(s, c, g), 0.06)

def make_mitm() -> list:
    """MITM.sh – hijack: two signals cross as control is seized."""
    rise = pitch_sweep(330, 990, 0.22, amp=0.38)   # attacker rising
    fall = pitch_sweep(990, 220, 0.22, amp=0.34)   # victim falling
    merged = env(mix(rise, fall), attack=0.005, decay=0.08, sustain=0.55, release=0.08)
    snap = env(mix(square_wave(1400, 0.05, 0.40), noise(0.05, 0.28)),
               attack=0.0005, decay=0.015, sustain=0.0, release=0.01)
    return fade_out(concat(silence(0.02), merged, silence(0.01), snap), 0.06)

def make_backdoor() -> list:
    """BACKDOOR.sh – silent infiltration then double-action click."""
    low    = env(sine_wave(80, 0.24, 0.28), attack=0.03, decay=0.08, sustain=0.40, release=0.08)
    click1 = env(square_wave(1000, 0.04, 0.38), attack=0.001, decay=0.015, sustain=0.0, release=0.010)
    gap    = silence(0.06)
    click2 = env(square_wave(1000, 0.04, 0.44), attack=0.001, decay=0.015, sustain=0.0, release=0.010)
    return fade_out(concat(low, click1, gap, click2), 0.01)

def make_patch() -> list:
    """PATCH.sh – shield raised: rising harmonic barrier."""
    body   = pitch_sweep(300, 900, 0.18, amp=0.44)
    fifth  = pitch_sweep(450, 1350, 0.18, amp=0.24)  # perfect fifth (×1.5)
    sheen  = env(mix(body, fifth), attack=0.010, decay=0.05, sustain=0.60, release=0.07)
    ping   = env(sine_wave(1800, 0.06, 0.32), attack=0.003, decay=0.03, sustain=0.0, release=0.02)
    return fade_out(concat(sheen, ping), 0.04)

def make_worm() -> list:
    """WORM.sh – rapidly modulated signal spreading through the network."""
    body = fm_synth(220, 28, 160, 0.38, 0.50)
    body_env = env(body, attack=0.005, decay=0.10, sustain=0.70, release=0.12)
    tail = env(fm_synth(180, 35, 120, 0.22, 0.30), attack=0.010, decay=0.05, sustain=0.50, release=0.10)
    return fade_out(concat(body_env, tail), 0.05)

def make_knightseye() -> list:
    """KNIGHTS_EYE.sh – hidden trap resonates, then springs shut."""
    hum  = env(fm_synth(330, 5, 14, 0.30, 0.28), attack=0.02, decay=0.08, sustain=0.55, release=0.10)
    snap = env(mix(square_wave(1400, 0.04, 0.44), noise(0.04, 0.32)),
               attack=0.0005, decay=0.012, sustain=0.0, release=0.02)
    spread = env(pitch_sweep(400, 1200, 0.20, amp=0.34),
                 attack=0.003, decay=0.05, sustain=0.40, release=0.08)
    return fade_out(concat(hum, snap, spread), 0.04)

def make_psyche() -> list:
    """PSYCHE.sh – dissonant tritone; the mind destabilised."""
    # Tritone interval (augmented fourth): root + 6 semitones ≈ ×2^(6/12)
    a = env(sine_wave(330, 0.42, 0.36), attack=0.015, decay=0.05, sustain=0.65, release=0.12)
    b = env(sine_wave(466, 0.42, 0.32), attack=0.015, decay=0.05, sustain=0.65, release=0.12)
    # Subtle FM distortion for unease
    c = env(fm_synth(396, 3, 9, 0.42, 0.18), attack=0.010, decay=0.05, sustain=0.65, release=0.12)
    return fade_out(mix(a, b, c), 0.06)


# ── Registry ─────────────────────────────────────────────────────────────────

SOUNDS: dict = {
    # Core gameplay
    'place_node':    make_place_node,
    'capture':       make_capture,
    'turn_start':    make_turn_start,
    'pass_turn':     make_pass_turn,
    'game_win':      make_game_win,
    'game_over':     make_game_over,
    'timebomb_tick': make_timebomb_tick,
    # UI
    'boot_beep':     make_boot_beep,
    'menu_select':   make_menu_select,
    'connect':       make_connect,
    # Attack types (one per AttackType enum value in go_engine)
    'atk_ddos':      make_ddos,
    'atk_trojan':    make_trojan,
    'atk_mitm':      make_mitm,
    'atk_backdoor':  make_backdoor,
    'atk_patch':     make_patch,
    'atk_worm':      make_worm,
    'atk_knightseye': make_knightseye,
    'atk_psyche':    make_psyche,
}


if __name__ == '__main__':
    repo_root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    out_dir = (sys.argv[1]
               if len(sys.argv) > 1
               else os.path.join(repo_root, 'app', 'assets', 'audio'))
    os.makedirs(out_dir, exist_ok=True)

    print(f'Writing {len(SOUNDS)} sounds to: {out_dir}\n')
    ok = 0
    for name, fn in SOUNDS.items():
        path = os.path.join(out_dir, f'{name}.wav')
        print(f'  {name}.wav ... ', end='', flush=True)
        try:
            samples = fn()
            write_wav(path, samples)
            size_kb = os.path.getsize(path) / 1024
            print(f'ok  ({size_kb:.1f} kB)')
            ok += 1
        except Exception as exc:
            print(f'FAILED: {exc}')

    print(f'\n{ok}/{len(SOUNDS)} sounds generated.')
