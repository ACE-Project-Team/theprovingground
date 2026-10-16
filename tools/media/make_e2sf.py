"""Draw the animated README figure for the E2/Starfall addon, media/e2sf.gif.

    python tools/media/make_e2sf.py

One E2 chip, the tpg_e2sf addon and the chip's outputs, shown twice on a
loop: first on a TPG server, where the addon reads the real teams and
loadouts, then in sandbox, where `tpg_test_team green` puts the owner on a
stand-in team. The output values are the ones the harness run returned
(gmodkit, out/tpg-repro/e2sf_run.lua); the names are made up.

Same look as make_header.py: HUD palette, Exo 2, icon512.png as the brand
mark. Needs Pillow.
"""

import os

from PIL import Image, ImageDraw, ImageFont

REPO = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
FONTS = os.path.join(REPO, "resource", "fonts")
OUT = os.path.join(REPO, "media", "e2sf.gif")

W, H = 1280, 420
S = 2                      # supersampling
FPS = 10
PHASE = 7.0                # seconds per gamemode
LOOP = 2 * PHASE

# sh_palette.lua
PANEL = (19, 11, 32)
TROUGH = (44, 27, 74)
CARD = (30, 18, 51)
PURPLE = (88, 24, 167)
PURPLE_LIGHT = (132, 78, 220)
ACCENT = (0, 148, 255)
TEXT = (240, 238, 246)
MUTED = (170, 158, 190)
GREEN = (0, 255, 33)
GREEN_TEXT = (110, 255, 130)
RED_TEXT = (255, 110, 110)
NEUTRAL = (255, 214, 64)

SWATCHES = [PANEL, TROUGH, CARD, PURPLE, PURPLE_LIGHT, ACCENT, TEXT, MUTED, GREEN, GREEN_TEXT,
            RED_TEXT, NEUTRAL]

# (tokens, colour) per code line; the chip is the same in both phases.
CODE = [
    [("Team", TEXT), ("  = ", MUTED), ("tpgTeamName", ACCENT), ("()", MUTED)],
    [("Count", TEXT), (" = ", MUTED), ("tpgTeamCount", ACCENT), ("()", MUTED)],
    [("Mates", TEXT), (" = ", MUTED), ("tpgTeammateNames", ACCENT), ("()", MUTED)],
    [("Armor", TEXT), (" = ", MUTED), ("Buddy", TEXT), (":", MUTED), ("tpgArmor", ACCENT), ("()", MUTED)],
]

MODES = [
    {
        "tab": "THE PROVING GROUND",
        "console": "gamemode  theprovingground",
        "typed": False,
        "source": "real teams and loadouts",
        "rows": [("Team", '"The Green Terror"'), ("Count", "3"),
                 ("Mates", '["Gunner", "Driver", "Spotter"]'), ("Armor", '"Light"')],
        "caption": "On a TPG server it reads the real teams and loadouts.",
    },
    {
        "tab": "SANDBOX",
        "console": "] tpg_test_team green",
        "typed": True,
        "source": "stand-in teams",
        "rows": [("Team", '"GREEN (test)"'), ("Count", "2"),
                 ("Mates", '["Gunner", "Driver"]'), ("Armor", '"Unknown"')],
        "caption": "In sandbox it adds stand-in teams, so chips are ready before the match.",
    },
]

# Times within a phase, in seconds.
T_TYPE = (0.5, 1.9)
T_PACKETS = (1.9, 3.1)
T_ROWS = 3.1
ROW_GAP = 0.4
T_FADE = PHASE - 0.4


def font(weight, size):
    return ImageFont.truetype(os.path.join(FONTS, "Exo2-%d.ttf" % weight), size * S)


def clamp(t):
    return max(0.0, min(1.0, t))


def mix(c1, c2, t):
    t = clamp(t)
    return tuple(int(round(a + (b - a) * t)) for a, b in zip(c1, c2))


def box(d, x0, y0, x1, y1, fill, outline=None, width=2):
    d.rectangle([x0 * S, y0 * S, x1 * S, y1 * S], fill=fill,
                outline=outline, width=width * S if outline else 0)


def text(d, x, y, s, f, fill):
    d.text((x * S, y * S), s, font=f, fill=fill)


def tokens(d, x, y, parts, f, fade=1.0):
    for s, c in parts:
        text(d, x, y, s, f, mix(CARD, c, fade))
        x += d.textlength(s, font=f) / S


def frame(t, icon, fonts):
    f_title, f_head, f_body, f_small = fonts
    im = Image.new("RGB", (W * S, H * S), PANEL)
    d = ImageDraw.Draw(im)

    mode_i = int(t // PHASE) % 2
    mode = MODES[mode_i]
    local = t % PHASE
    fade_out = 1 - clamp((local - T_FADE) / 0.4)

    # Brand mark and title.
    small = icon.resize((64 * S, 64 * S), Image.LANCZOS)
    im.paste(small, (28 * S, 22 * S), small)
    text(d, 108, 22, "E2 & STARFALL", f_title, TEXT)
    text(d, 110, 66, "tpg_e2sf - team functions for your chips", f_small, MUTED)

    # Gamemode tabs, top right; the active one is filled.
    x = W - 40
    for i in (1, 0):
        label = MODES[i]["tab"]
        tw = d.textlength(label, font=f_small) / S
        x0 = x - tw - 32
        active = i == mode_i
        box(d, x0, 34, x, 70, PURPLE if active else PANEL, outline=PURPLE_LIGHT if not active else None)
        text(d, x0 + 16, 42, label, f_small, TEXT if active else MUTED)
        x = x0 - 12

    # The chip.
    cx0, cy0, cx1, cy1 = 40, 120, 430, 356
    box(d, cx0, cy0, cx1, cy1, CARD)
    box(d, cx0, cy0, cx0 + 4, cy1, ACCENT)
    text(d, cx0 + 22, cy0 + 14, "EXPRESSION 2", f_head, MUTED)
    for k, line in enumerate(CODE):
        tokens(d, cx0 + 22, cy0 + 56 + k * 40, line, f_body)

    # The addon, with the console strip above it.
    ax0, ay0, ax1, ay1 = 530, 206, 750, 356
    sx0, sy0, sx1, sy1 = 490, 120, 790, 158
    d.line([((ax0 + ax1) / 2 * S, sy1 * S), ((ax0 + ax1) / 2 * S, ay0 * S)], fill=TROUGH, width=2 * S)
    box(d, sx0, sy0, sx1, sy1, (11, 6, 20))
    s = mode["console"]
    if mode["typed"]:
        n = int(len(s) * clamp((local - T_TYPE[0]) / (T_TYPE[1] - T_TYPE[0])))
        s = s[:n] + ("_" if int(local * 3) % 2 == 0 else "")
        colour = TEXT
    else:
        colour = MUTED
    text(d, sx0 + 14, sy0 + 8, s, f_small, colour)

    lit = clamp((local - T_PACKETS[0]) / 0.3) * fade_out
    box(d, ax0, ay0, ax1, ay1, CARD, outline=mix(TROUGH, PURPLE_LIGHT, lit))
    text(d, ax0 + 22, ay0 + 18, "tpg_e2sf", f_head, TEXT)
    text(d, ax0 + 22, ay0 + 50, "garrysmod/addons/", f_small, MUTED)
    text(d, ax0 + 22, ay0 + 92, "reads", f_small, MUTED)
    text(d, ax0 + 22, ay0 + 114, mode["source"], f_small, mix(CARD, GREEN_TEXT, lit))

    # Calls travel chip -> addon, results addon -> outputs.
    p = (local - T_PACKETS[0]) / (T_PACKETS[1] - T_PACKETS[0])
    for x0, x1, y, start in ((cx1, ax0, 281, 0.0), (ax1, 850, 281, 0.5)):
        d.line([(x0 * S, y * S), (x1 * S, y * S)], fill=TROUGH, width=2 * S)
        q = (p - start) / 0.5
        for k in range(3):
            r = q - k * 0.18
            if 0 <= r <= 1:
                px = x0 + (x1 - x0) * r
                d.ellipse([(px - 5) * S, (y - 5) * S, (px + 5) * S, (y + 5) * S], fill=ACCENT)

    # The chip's outputs, filled in one by one.
    ox0, oy0, ox1, oy1 = 850, 120, 1240, 356
    box(d, ox0, oy0, ox1, oy1, CARD)
    box(d, ox0, oy0, ox0 + 4, oy1, GREEN)
    text(d, ox0 + 22, oy0 + 14, "OUTPUTS", f_head, MUTED)
    for k, (name, value) in enumerate(mode["rows"]):
        a = clamp((local - T_ROWS - k * ROW_GAP) / 0.25) * fade_out
        y = oy0 + 52 + k * 37
        text(d, ox0 + 22, y, name, f_body, mix(CARD, MUTED, a))
        colour = {'"': GREEN_TEXT, "[": TEXT}.get(value[0], NEUTRAL)
        text(d, ox0 + 110, y, value, f_body, mix(CARD, colour, a))
    a = clamp((local - T_ROWS - 4 * ROW_GAP) / 0.25) * fade_out
    text(d, ox0 + 22, oy1 - 30, "Red players never show up", f_small, mix(CARD, RED_TEXT, a))

    # What this phase means, bottom centre.
    a = clamp(local / 0.4) * fade_out
    cap = mode["caption"]
    tw = d.textlength(cap, font=f_body) / S
    text(d, (W - tw) / 2, 378, cap, f_body, mix(PANEL, TEXT, a))

    return im.resize((W, H), Image.LANCZOS)


def main():
    icon = Image.open(os.path.join(REPO, "icon512.png")).convert("RGBA")
    fonts = (font(800, 36), font(700, 18), font(600, 20), font(600, 16))
    n = int(LOOP * FPS)
    frames = [frame(i / FPS, icon, fonts) for i in range(n)]

    # One shared palette, as in make_header.py, so flat areas don't shimmer.
    probe = Image.new("RGB", (W, H * 2))
    for k, i in enumerate((int(FPS * 6), int(FPS * (PHASE + 6)))):
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
