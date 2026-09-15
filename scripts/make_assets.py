"""Generate app icon (.ico/.png) and short UI SFX for EWarGame."""
from __future__ import annotations

import math
import struct
import wave
from pathlib import Path

from PIL import Image, ImageDraw

ROOT = Path(r"E:\EWarGame")
ICON_DIR = ROOT / "game" / "assets" / "icons"
AUDIO_DIR = ROOT / "game" / "assets" / "audio"
ICON_DIR.mkdir(parents=True, exist_ok=True)
AUDIO_DIR.mkdir(parents=True, exist_ok=True)

# Palette: cream paper, charcoal, gold, vermilion
BG = (21, 44, 44)
PANEL = (32, 56, 56)
PAPER = (236, 232, 217)
GOLD = (198, 170, 109)
VERM = (197, 82, 58)
BLUE = (88, 123, 141)


def hexagon_points(cx, cy, r):
    pts = []
    for i in range(6):
        a = math.radians(60 * i - 30)
        pts.append((cx + r * math.cos(a), cy + r * math.sin(a)))
    return pts


def draw_icon(size: int) -> Image.Image:
    img = Image.new("RGBA", (size, size), BG + (255,))
    d = ImageDraw.Draw(img)
    # soft panel circle
    m = size * 0.06
    d.ellipse([m, m, size - m, size - m], fill=PANEL + (255,))
    # large hex (map cell)
    r = size * 0.34
    cx = cy = size / 2
    d.polygon(hexagon_points(cx, cy, r), outline=GOLD + (255,), fill=(40, 70, 68, 255))
    # inner smaller hex
    d.polygon(hexagon_points(cx, cy, r * 0.55), outline=PAPER + (200,), fill=BG + (220,))
    # vermilion counter mark
    cr = size * 0.1
    d.ellipse([cx - cr, cy - cr * 0.2, cx + cr, cy + cr * 1.6], fill=VERM + (255,))
    d.ellipse([cx - cr * 0.55, cy + cr * 0.25, cx + cr * 0.55, cy + cr * 1.15], fill=PAPER + (255,))
    # blue allied dot
    br = size * 0.08
    d.ellipse([cx - r * 0.75 - br, cy + r * 0.35 - br, cx - r * 0.75 + br, cy + r * 0.35 + br], fill=BLUE + (255,))
    return img


def save_ico(path: Path, sizes=(16, 24, 32, 48, 64, 128, 256)):
    images = [draw_icon(s) for s in sizes]
    # Pillow ICO
    images[-1].save(path, format="ICO", sizes=[(s, s) for s in sizes])


def write_wav(path: Path, samples, rate=22050):
    with wave.open(str(path), "w") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(rate)
        frames = b"".join(struct.pack("<h", max(-32767, min(32767, int(s * 32767)))) for s in samples)
        w.writeframes(frames)


def tone(freq, dur, vol=0.25, attack=0.01, release=0.05, rate=22050):
    n = int(rate * dur)
    out = []
    for i in range(n):
        t = i / rate
        env = 1.0
        if t < attack:
            env = t / attack
        elif t > dur - release:
            env = max(0.0, (dur - t) / release)
        # soft square-ish sine
        s = math.sin(2 * math.pi * freq * t) * 0.7 + math.sin(2 * math.pi * freq * 2 * t) * 0.15
        out.append(s * vol * env)
    return out


def click_sfx():
    # short filtered click
    rate = 22050
    n = int(rate * 0.06)
    out = []
    for i in range(n):
        t = i / rate
        env = math.exp(-t * 80)
        s = math.sin(2 * math.pi * 880 * t) * env * 0.35
        out.append(s)
    return out


def confirm_sfx():
    a = tone(523.25, 0.08, 0.22)
    b = tone(784.0, 0.12, 0.2)
    return a + b


def alert_sfx():
    a = tone(220, 0.1, 0.25)
    b = tone(165, 0.16, 0.22)
    return a + b


def turn_sfx():
    # low soft drum-like thump + shimmer
    rate = 22050
    n = int(rate * 0.35)
    out = []
    for i in range(n):
        t = i / rate
        env = math.exp(-t * 8)
        s = math.sin(2 * math.pi * 70 * t) * env * 0.45
        s += math.sin(2 * math.pi * 140 * t) * env * 0.12
        if t > 0.12:
            s += math.sin(2 * math.pi * 523 * (t - 0.12)) * math.exp(-(t - 0.12) * 18) * 0.08
        out.append(s)
    return out


def main():
    icon = draw_icon(256)
    icon.save(ICON_DIR / "ewargame_icon.png")
    save_ico(ICON_DIR / "ewargame.ico")
    # Godot also accepts svg; keep a simple companion
    print("icons:", list(ICON_DIR.glob("ewargame*")))
    write_wav(AUDIO_DIR / "ui_click.wav", click_sfx())
    write_wav(AUDIO_DIR / "ui_confirm.wav", confirm_sfx())
    write_wv = write_wav
    write_wv(AUDIO_DIR / "ui_alert.wav", alert_sfx())
    write_wav(AUDIO_DIR / "turn_resolve.wav", turn_sfx())
    # quiet ambient pad (very short loop-friendly 2s)
    rate = 22050
    n = int(rate * 2.0)
    pad = []
    for i in range(n):
        t = i / rate
        s = 0.03 * math.sin(2 * math.pi * 110 * t)
        s += 0.02 * math.sin(2 * math.pi * 165 * t + 0.5)
        s += 0.015 * math.sin(2 * math.pi * 220 * t + 1.0)
        # gentle attack/release to avoid click if looped poorly
        if t < 0.05:
            s *= t / 0.05
        if t > 1.9:
            s *= (2.0 - t) / 0.1
        pad.append(s)
    write_wav(AUDIO_DIR / "ambient_pad.wav", pad)
    print("audio:", list(AUDIO_DIR.glob("*.wav")))


if __name__ == "__main__":
    main()
