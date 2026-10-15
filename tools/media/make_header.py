"""Draw the animated README header, media/header.gif.

    python tools/media/make_header.py

A hill with a control point, Green and Red on either side, and the point
changing hands on a loop: neutral, captured by Green, neutralized, captured
by Red, neutralized again. The messages are the ones the control point
really broadcasts (entities/entities/tpg_controlpoint/init.lua), and every
colour is from the HUD palette (gamemode/config/sh_palette.lua), itself
sampled off the TPG icon. icon512.png is drawn in the corner as the brand
mark.

Needs Pillow. Drawn at twice the size and scaled down, so edges are smooth
but the art stays flat.
"""

import math
import os

from PIL import Image, ImageDraw, ImageFont

REPO = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
FONTS = os.path.join(REPO, "resource", "fonts")
OUT = os.path.join(REPO, "media", "header.gif")

W, H = 1280, 420
S = 2                      # supersampling
FPS = 10
PHASE = 3.0                # seconds per capture / neutralize
HOLD = 1.5                 # seconds the point sits after each change
LOOP = 4 * (PHASE + HOLD)

# sh_palette.lua
PANEL = (19, 11, 32)
TROUGH = (44, 27, 74)
PURPLE = (88, 24, 167)
PURPLE_LIGHT = (132, 78, 220)
ACCENT = (0, 148, 255)
TEXT = (240, 238, 246)
MUTED = (170, 158, 190)
GREEN = (0, 255, 33)
GREEN_TEXT = (110, 255, 130)
RED = (255, 0, 0)
RED_TEXT = (255, 110, 110)
NEUTRAL = (255, 214, 64)
WARN = (255, 140, 50)
# The icon's tank
OLIVE = (115, 160, 0)
OLIVE_DARK = (80, 112, 0)
TRACK = (44, 40, 52)
WHEEL = (168, 168, 40)
INK = (11, 6, 20)          # silhouettes

POINT = "The Hill"
SWATCHES = [PANEL, TROUGH, PURPLE, PURPLE_LIGHT, ACCENT, TEXT, MUTED, GREEN, GREEN_TEXT, RED,
            RED_TEXT, NEUTRAL, OLIVE, OLIVE_DARK, TRACK, WHEEL, INK]
TEAMS = {"green": ("The Green Terror", GREEN, GREEN_TEXT), "red": ("The Red Menace", RED, RED_TEXT)}


def font(weight, size):
    return ImageFont.truetype(os.path.join(FONTS, "Exo2-%d.ttf" % weight), size * S)


def lerp(a, b, t):
    return a + (b - a) * t


def mix(c1, c2, t):
    return tuple(int(round(lerp(x, y, t))) for x, y in zip(c1, c2))


def ease(t):
    t = max(0.0, min(1.0, t))
    return t * t * (3 - 2 * t)


def state(t):
    """Owner colour of the flag, how far up the pole it is, and the last
    message with its age, for time t in the loop."""
    step = PHASE + HOLD
    i, local = int(t // step) % 4, t % step
    # (team doing the work, what it ends as)
    plan = [("green", "green"), ("red", None), ("red", "red"), ("green", None)]
    actor, result = plan[i]
    p = ease(local / PHASE)
    done = local >= PHASE
    if result:                      # raising from neutral
        height = p
        colour = TEAMS[result][1] if done else NEUTRAL
        owner_before = None
    else:                           # lowering someone else's flag
        height = 1 - p
        prev = plan[i - 1][1]
        colour = NEUTRAL if done else TEAMS[prev][1]
        owner_before = prev
    if done:
        if result:
            msg = ("[%s] captured by %s!" % (POINT, TEAMS[result][0]), TEAMS[result][2])
        else:
            msg = ("[%s] has been neutralized!" % POINT, NEUTRAL)
        age = local - PHASE
    else:
        msg, age = None, 0
    return actor, colour, height, msg, age, done and local - PHASE < 0.4, owner_before


def ridge(d, base, amp, seed, colour, step=40):
    pts = [(0, H * S)]
    for x in range(0, W + step, step):
        y = base + amp * (math.sin(x * 0.006 + seed) * 0.6 + math.sin(x * 0.017 + seed * 2) * 0.4)
        pts.append((x * S, y * S))
    pts.append((W * S, H * S))
    d.polygon(pts, fill=colour)


def hill_y(x):
    # The hill the point sits on; peak at the centre.
    return 362 - 92 * math.exp(-((x - W / 2) / 250) ** 2)


def tank(d, x, ground, facing, recoil, flash):
    """The icon's tank, flat, facing +1 (right) or -1 (left)."""
    def P(px, py):
        return ((x + px * facing) * S, (ground - py) * S)

    def poly(points, colour):
        d.polygon([P(*p) for p in points], fill=colour)

    poly([(-62, 6), (62, 6), (70, 18), (-70, 18)], TRACK)
    for wx in (-44, -22, 0, 22, 44):
        cx, cy = P(wx, 12)
        d.ellipse([cx - 6 * S, cy - 6 * S, cx + 6 * S, cy + 6 * S], fill=WHEEL)
    poly([(-66, 18), (66, 18), (58, 34), (-62, 34)], OLIVE)
    poly([(-66, 18), (66, 18), (64, 22), (-64, 22)], OLIVE_DARK)
    poly([(-30, 34), (24, 34), (18, 52), (-24, 52)], OLIVE)
    gun = 96 - recoil
    poly([(14, 42), (gun, 42), (gun, 47), (14, 47)], OLIVE_DARK)
    poly([(-20, 52), (-17, 52), (-17, 84), (-20, 84)], INK)   # antenna
    if flash:
        mx, my = P(gun + 10, 44.5)
        r = 14 * S * flash
        d.polygon([(mx - r * 0.2 * facing, my - r), (mx + r * 1.4 * facing, my), (mx - r * 0.2 * facing, my + r)], fill=NEUTRAL)
        d.ellipse([mx - r * 0.6, my - r * 0.6, mx + r * 0.6, my + r * 0.6], fill=TEXT)


def pennant(d, x, ground, facing, colour, t):
    tx, ty = (x - 18.5 * facing) * S, (ground - 84) * S
    wave = math.sin(t * 7) * 2 * S
    d.polygon([(tx, ty), (tx - 20 * facing * S, ty + 4 * S + wave), (tx, ty + 9 * S)], fill=colour)


def soldier(d, x, ground, facing, colour, phase):
    bob = abs(math.sin(phase)) * 2
    stride = math.sin(phase) * 7
    g = ground

    def L(x1, y1, x2, y2, w):
        d.line([((x + x1 * facing) * S, (g - y1) * S), ((x + x2 * facing) * S, (g - y2) * S)], fill=INK, width=int(w * S))

    L(0, 20 + bob, -stride, 0, 5)
    L(0, 20 + bob, stride, 0, 5)
    L(0, 20 + bob, 2, 40 + bob, 8)                      # body
    hx, hy = (x + 3 * facing) * S, (g - 47 - bob) * S
    d.ellipse([hx - 6 * S, hy - 6 * S, hx + 6 * S, hy + 6 * S], fill=INK)
    d.rectangle([hx - 6 * S, hy - 2 * S, hx + 6 * S, hy + 1 * S], fill=colour)   # helmet band
    L(-2, 34 + bob, 22, 37 + bob, 3)                    # rifle
    L(4, 36 + bob, 14, 33 + bob, 4)                     # arms


def text_centered(d, cx, y, s, f, fill, spacing=0):
    if spacing:
        widths = [d.textlength(ch, font=f) + spacing * S for ch in s]
        x = cx * S - (sum(widths) - spacing * S) / 2
        for ch, w in zip(s, widths):
            d.text((x, y * S), ch, font=f, fill=fill)
            x += w
    else:
        w = d.textlength(s, font=f)
        d.text((cx * S - w / 2, y * S), s, font=f, fill=fill)


def frame(t, icon, fonts):
    im = Image.new("RGB", (W * S, H * S), PANEL)
    d = ImageDraw.Draw(im)

    # Sky in flat bands, darkest at the top.
    bands = [PANEL, (27, 15, 46), (35, 20, 60), TROUGH, (58, 30, 98)]
    for i, c in enumerate(bands):
        d.rectangle([0, int(i * 55 * S), W * S, H * S], fill=c)
    for sx, sy in [(90, 30), (210, 70), (330, 22), (520, 48), (760, 30), (905, 64), (1040, 26), (1190, 52), (1120, 100), (60, 120)]:
        tw = 0.5 + 0.5 * math.sin(t * 2 + sx)
        d.rectangle([sx * S, sy * S, (sx + 2) * S, (sy + 2) * S], fill=mix(TROUGH, MUTED, tw))

    ridge(d, 292, 18, 1.3, (30, 17, 52))
    ridge(d, 322, 12, 4.1, (24, 13, 41))

    # The hill.
    pts = [(0, H * S)] + [(x * S, hill_y(x) * S) for x in range(0, W + 8, 8)] + [(W * S, H * S)]
    d.polygon(pts, fill=(17, 9, 29))
    d.rectangle([0, 362 * S, W * S, H * S], fill=PANEL)

    actor, colour, height, msg, age, burst, _ = state(t)
    cx, top = W / 2, hill_y(W / 2)

    # Capture disc, like the in-game point.
    disc = mix(PANEL, colour, 0.75)
    d.ellipse([(cx - 70) * S, (top - 9) * S, (cx + 70) * S, (top + 9) * S], fill=disc)
    d.ellipse([(cx - 46) * S, (top - 5) * S, (cx + 46) * S, (top + 5) * S], fill=mix(disc, colour, 0.6))
    if burst:
        r = 70 + (age / 0.4) * 50
        d.ellipse([(cx - r) * S, (top - r * 0.13) * S, (cx + r) * S, (top + r * 0.13) * S], outline=colour, width=3 * S)

    # Pole and flag.
    pole_top = top - 96
    d.rectangle([(cx - 2) * S, pole_top * S, (cx + 2) * S, top * S], fill=MUTED)
    fy = lerp(top - 34, pole_top + 2, height)
    fw, fh = 60, 34
    poly = []
    for i in range(0, fw + 1, 5):
        wob = math.sin(t * 6 - i * 0.12) * (i / fw) * 5
        poly.append(((cx + 2 + i) * S, (fy + wob) * S))
    for i in range(fw, -1, -5):
        wob = math.sin(t * 6 - i * 0.12) * (i / fw) * 5
        poly.append(((cx + 2 + i) * S, (fy + fh + wob) * S))
    d.polygon(poly, fill=colour)

    # The two sides. Each tank fires twice a loop, a little out of step.
    for side, facing, base_x in (("green", 1, 175), ("red", -1, W - 175)):
        tcol = TEAMS[side][1]
        g = 362
        shots = [0.9, 0.9 + LOOP / 2] if side == "green" else [3.2, 3.2 + LOOP / 2]
        since = min(((t - s) % LOOP) for s in shots)
        recoil = 8 * max(0.0, 1 - since / 0.35)
        flash = max(0.0, 1 - since / 0.15)
        tank(d, base_x, g, facing, recoil, flash)
        pennant(d, base_x, g, facing, tcol, t)
        # Infantry pushing up when their side is working the point.
        push = 1.0 if actor == side else 0.0
        for k, off in enumerate((150, 190, 232)):
            sx = base_x + facing * (off + 18 * push)
            soldier(d, sx, min(362, hill_y(sx) + 2), facing, tcol, t * 7 + k * 1.7)

    # Title block.
    f_title, f_sub, f_msg = fonts
    text_centered(d, W / 2 + 4, 14 + 4, "CONQUER", f_title, PURPLE, spacing=6)
    text_centered(d, W / 2, 14, "CONQUER", f_title, TEXT, spacing=6)
    bw = 150
    d.rectangle([(W / 2 - bw - 5) * S, 130 * S, (W / 2 - 5) * S, 135 * S], fill=GREEN)
    d.rectangle([(W / 2 + 5) * S, 130 * S, (W / 2 + bw + 5) * S, 135 * S], fill=RED)
    text_centered(d, W / 2, 142, "THE PROVING GROUND", f_sub, MUTED, spacing=4)

    # Kill-feed style message, bottom left, as the HUD shows it.
    if msg:
        a = min(1.0, age / 0.2) * (1 - max(0.0, (age - (HOLD - 0.3)) / 0.3))
        s, c = msg
        tw = d.textlength(s, font=f_msg)
        box = [28 * S, 374 * S, 28 * S + tw + 28 * S, 410 * S]
        d.rectangle(box, fill=mix(PANEL, TROUGH, a))
        d.rectangle([box[0], box[1], box[0] + 4 * S, box[3]], fill=mix(PANEL, c, a))
        d.text((box[0] + 16 * S, box[1] + 6 * S), s, font=f_msg, fill=mix(PANEL, c, a))

    # icon512.png as the brand mark.
    big = icon.resize((96 * S, 96 * S), Image.LANCZOS)
    im.paste(big, (28 * S, 24 * S), big)
    d.text(((28 + 96 + 14) * S, 44 * S), "TPG", font=fonts[1], fill=ACCENT)
    d.text(((28 + 96 + 14) * S, 72 * S), "for ACE", font=fonts[2], fill=MUTED)

    return im.resize((W, H), Image.LANCZOS)


def main():
    icon = Image.open(os.path.join(REPO, "icon512.png")).convert("RGBA")
    fonts = (font(800, 92), font(700, 22), font(600, 17))
    n = int(LOOP * FPS)
    frames = [frame(i / FPS, icon, fonts) for i in range(n)]

    # One shared palette, so flat areas don't shimmer between frames. The
    # HUD colours are put in exactly; the rest is the edge blends.
    probe = Image.new("RGB", (W, H * 4))
    for k, i in enumerate((int(FPS * 4), int(FPS * 8.5), int(FPS * 13), int(FPS * 17.5))):
        probe.paste(frames[i], (0, H * k))
    rest = probe.quantize(colors=256 - len(SWATCHES), method=Image.MEDIANCUT, dither=Image.NONE)
    colours = [v for c in SWATCHES for v in c] + rest.getpalette()[:3 * (256 - len(SWATCHES))]
    pal = Image.new("P", (1, 1))
    pal.putpalette(colours)
    out = [f.quantize(palette=pal, dither=Image.NONE) for f in frames]

    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    out[0].save(OUT, save_all=True, append_images=out[1:], duration=int(1000 / FPS),
                loop=0, optimize=False, disposal=1)
    print("%d frames, %.0f KB -> %s" % (n, os.path.getsize(OUT) / 1024, OUT))


if __name__ == "__main__":
    main()
