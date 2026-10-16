"""Draw the Workshop thumbnails and the tpg_e2sf icon, into media/workshop/.

    python tools/media/make_workshop.py

tpg_thumb.gif and tpg_e2sf_thumb.gif are the animated previews for the two
Workshop items. They are square because the Workshop grid and GMod's addon
list show square tiles, and anything wider gets black bars. Each opens on its
logo filling the tile, splits it along the green/red seam, then shrinks it to
the top for the title and grows it back, so the first frame works as a still.
They stay under the 1 MB Steam allows for a preview.

tpg_e2sf_icon.png is the addon's own logo, drawn in the style of icon512.png:
the same frame, split and blocky blue letters, with a chip where the tank is.

Same palette and Exo 2 as the other media scripts. Needs Pillow.
"""

import math
import os

from PIL import Image, ImageChops, ImageDraw, ImageFont

REPO = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
FONTS = os.path.join(REPO, "resource", "fonts")
OUT = os.path.join(REPO, "media", "workshop")

W, H = 512, 512
S = 2                      # supersampling
FPS = 12
LOOP = 6.0
LIMIT = 1024 * 1024        # Steam's preview size cap

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
RED = (255, 0, 0)
RED_TEXT = (255, 110, 110)
WHITE = (255, 255, 255)
# icon512.png
ICON_GREEN = (0, 255, 33)
ICON_RED = (255, 0, 0)
SHADOW_GREEN = (0, 153, 20)
SHADOW_RED = (153, 0, 0)
TRACK = (50, 50, 50)
HULL = (74, 74, 74)
OLIVE = (127, 174, 0)
WHEEL = (163, 176, 0)
SLATE = (62, 90, 99)

SWATCHES = [PANEL, TROUGH, CARD, PURPLE, PURPLE_LIGHT, ACCENT, TEXT, MUTED, GREEN, GREEN_TEXT,
            RED, RED_TEXT, WHITE, SHADOW_GREEN, SHADOW_RED, TRACK, HULL, OLIVE, WHEEL, SLATE]

# Times in the loop, in seconds.
T_SPLIT = (0.8, 1.4)
T_ASIDE = (1.6, 2.2)
T_TEXT_IN = (2.0, 2.6)
T_SHINE = (3.4, 4.0)
T_TEXT_OUT = (4.5, 4.9)
T_BACK = (4.8, 5.4)


def font(weight, size):
    return ImageFont.truetype(os.path.join(FONTS, "Exo2-%d.ttf" % weight), int(size * S))


def clamp(t):
    return max(0.0, min(1.0, t))


def ease(t):
    t = clamp(t)
    return t * t * (3 - 2 * t)


def lerp(a, b, t):
    return a + (b - a) * t


def mix(c1, c2, t):
    t = clamp(t)
    return tuple(int(round(lerp(a, b, t))) for a, b in zip(c1, c2))


def span(t, window):
    return clamp((t - window[0]) / (window[1] - window[0]))


# -- tpg_e2sf icon ------------------------------------------------------------

LETTERS = {
    "E": ["###", "#..", "##.", "#..", "###"],
    "2": ["###", "..#", "###", "#..", "###"],
    "S": ["###", "#..", "###", "..#", "###"],
    "F": ["###", "#..", "##.", "#..", "#.."],
}


def e2sf_icon(lit=()):
    """The addon logo at 512 px, RGBA. Pins whose index is in `lit` glow blue."""
    k = 2
    im = Image.new("RGBA", (512 * k, 512 * k), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)

    def R(x0, y0, x1, y1):
        return [x0 * k, y0 * k, x1 * k, y1 * k]

    d.rounded_rectangle(R(0, 0, 511, 511), radius=72 * k, fill=PURPLE)
    face = Image.new("L", im.size, 0)
    ImageDraw.Draw(face).rounded_rectangle(R(30, 30, 481, 481), radius=40 * k, fill=255)
    halves = Image.new("RGBA", im.size, ICON_RED)
    ImageDraw.Draw(halves).rectangle(R(0, 0, 256, 512), fill=ICON_GREEN)
    im.paste(halves, (0, 0), face)

    # Shadow under the chip, darker on each side, as under the tank.
    d.rounded_rectangle(R(128, 300, 384, 316), radius=8 * k, fill=SHADOW_RED)
    d.rounded_rectangle(R(128, 300, 264, 316), radius=8 * k, fill=SHADOW_GREEN)
    d.rectangle(R(250, 300, 256, 316), fill=SHADOW_GREEN)

    # Pins, four a side, numbered clockwise from the top left.
    pins = []
    for i in range(4):
        x = 186 + i * 40
        pins.append(R(x, 78, x + 20, 112))
    for i in range(4):
        y = 128 + i * 38
        pins.append(R(390, y, 424, y + 20))
    for i in range(4):
        x = 306 - i * 40
        pins.append(R(x, 274, x + 20, 290))
    for i in range(4):
        y = 242 - i * 38
        pins.append(R(88, y, 122, y + 20))
    for i, box in enumerate(pins):
        d.rectangle(box, fill=ACCENT if i in lit else SLATE)

    # The chip: dark rim and lighter face like the tank's tracks, an olive
    # label like its hull, and four wheel-coloured dots.
    d.rounded_rectangle(R(114, 104, 398, 282), radius=26 * k, fill=TRACK)
    d.rounded_rectangle(R(130, 120, 382, 266), radius=16 * k, fill=HULL)
    d.rectangle(R(162, 142, 350, 178), fill=OLIVE)
    d.ellipse(R(140, 128, 156, 144), fill=WHEEL)
    for i in range(4):
        cx = 196 + i * 40
        d.ellipse(R(cx - 14, 214, cx + 14, 242), fill=WHEEL)

    # E2SF in the TPG letters' blue, on a 26 x 22 grid.
    x = 73
    for ch in "E2SF":
        for row, line in enumerate(LETTERS[ch]):
            for col, cell in enumerate(line):
                if cell == "#":
                    d.rectangle(R(x + col * 26, 358 + row * 22, x + col * 26 + 26, 358 + row * 22 + 22),
                                fill=ACCENT)
        x += 78 + 18

    return im.resize((512, 512), Image.LANCZOS)


# -- thumbnails -------------------------------------------------------------

def backdrop():
    """Dark panel, green on the left and red on the right, split on a slant."""
    im = Image.new("RGB", (W * S, H * S), PANEL)
    d = ImageDraw.Draw(im)
    seam_top, seam_bottom = W / 2 + 60, W / 2 - 60
    d.polygon([(0, 0), (seam_top * S, 0), (seam_bottom * S, H * S), (0, H * S)],
              fill=mix(PANEL, GREEN, 0.07))
    d.polygon([(seam_top * S, 0), (W * S, 0), (W * S, H * S), (seam_bottom * S, H * S)],
              fill=mix(PANEL, RED, 0.07))
    for i in range(-20, 40):
        x = i * 36
        d.line([(x * S, H * S), ((x + H) * S, 0)], fill=mix(PANEL, PURPLE, 0.18), width=6 * S)
    d.rectangle([0, (H - 6) * S, W * S, H * S], fill=PURPLE)
    return im


def logo(icon, size, split, shine):
    """The icon at `size` px, opened along its seam by `split` (0..1) and swept by
    a light band at `shine` (0..1, None for none). Returns RGBA and its offset."""
    px = int(size * S)
    im = icon.resize((px, px), Image.LANCZOS)
    if shine is not None:
        band = Image.new("L", im.size, 0)
        x = lerp(-0.6, 1.4, shine) * px
        ImageDraw.Draw(band).polygon([(x, 0), (x + 0.22 * px, 0), (x - 0.18 * px, px),
                                      (x - 0.4 * px, px)], fill=120)
        band = ImageChops.multiply(band, im.getchannel("A"))
        im.paste(Image.new("RGBA", im.size, WHITE + (255,)), (0, 0), band)
    if split <= 0:
        return im, 0
    gap = int(split * 14 * S)
    out = Image.new("RGBA", (px + 2 * gap, px), (0, 0, 0, 0))
    half = px // 2
    out.paste(im.crop((0, 0, half, px)), (0, 0))
    out.paste(im.crop((half, 0, px, px)), (half + 2 * gap, 0))
    d = ImageDraw.Draw(out)
    mid = half + gap
    d.rectangle([mid - gap * 0.8, px * 0.06, mid + gap * 0.8, px * 0.94], fill=ACCENT + (255,))
    d.rectangle([mid - gap * 0.3, 0, mid + gap * 0.3, px], fill=WHITE + (255,))
    return out, gap


def text(d, x, y, s, f, fill):
    d.text((x * S, y * S), s, font=f, fill=fill)


def centred(d, y, s, f, fill):
    text(d, W / 2 - d.textlength(s, font=f) / S / 2, y, s, f, fill)


def tpg_extra(d, t, x, y, a, fonts):
    """Tug of war between the teams under the TPG title."""
    w = 300
    p = 0.5 + 0.18 * math.sin((t - T_TEXT_IN[1]) * 1.6)
    split = x + w * p
    d.rectangle([x * S, y * S, (x + w) * S, (y + 12) * S], fill=mix(PANEL, SHADOW_RED, a))
    d.rectangle([x * S, y * S, split * S, (y + 12) * S], fill=mix(PANEL, SHADOW_GREEN, a))
    d.rectangle([(split - 2) * S, (y - 4) * S, (split + 2) * S, (y + 16) * S], fill=mix(PANEL, TEXT, a))
    text(d, x, y + 20, "GREEN", fonts["small"], mix(PANEL, GREEN_TEXT, a))
    tw = d.textlength("RED", font=fonts["small"]) / S
    text(d, x + w - tw, y + 20, "RED", fonts["small"], mix(PANEL, RED_TEXT, a))


def e2sf_extra(d, t, x, y, a, fonts):
    """A chip line and what it returns, typed out under the title."""
    f = fonts["code"]
    d.rectangle([x * S, y * S, (x + 300) * S, (y + 64) * S], fill=mix(PANEL, CARD, a))
    d.rectangle([x * S, y * S, (x + 3) * S, (y + 64) * S], fill=mix(PANEL, ACCENT, a))
    cx = x + 14
    for s, c in (("Team", TEXT), (" = ", MUTED), ("tpgTeamName", ACCENT), ("()", MUTED)):
        text(d, cx, y + 8, s, f, mix(PANEL, c, a))
        cx += d.textlength(s, font=f) / S
    result = '"The Green Terror"'
    n = int(len(result) * clamp((t - T_TEXT_IN[1] - 0.2) / 0.8))
    text(d, x + 14, y + 34, result[:n], f, mix(PANEL, GREEN_TEXT, a))


def frame(t, base, icon_for, item, fonts):
    im = base.copy()
    d = ImageDraw.Draw(im)

    aside = ease(span(t, T_ASIDE)) * (1 - ease(span(t, T_BACK)))
    reveal = ease(span(t, T_TEXT_IN)) * (1 - ease(span(t, T_TEXT_OUT)))
    s = span(t, T_SPLIT)
    split = math.sin(math.pi * s) ** 0.6 if 0 < s < 1 else 0
    shine = span(t, T_SHINE) if T_SHINE[0] <= t <= T_SHINE[1] else None

    size = lerp(476, 220, aside)
    cx = W / 2
    cy = lerp(H / 2, 136, aside)
    img, gap = logo(icon_for(t), size, split, shine)
    im.paste(img, (int(cx * S - img.width / 2), int(cy * S - img.height / 2)), img)

    # The title, centred under the logo, wipes in from the left.
    if reveal > 0:
        layer = Image.new("RGB", im.size, PANEL)
        mask = Image.new("L", im.size, 0)
        ld = ImageDraw.Draw(layer)
        lines = len(item["title"])
        y0 = 262 + (2 - lines) * 26
        centred(ld, y0, item["kicker"], fonts["kicker"], ACCENT)
        for i, line in enumerate(item["title"]):
            centred(ld, y0 + 18 + i * 52, line, fonts["title"], TEXT)
        y1 = y0 + 26 + lines * 52
        centred(ld, y1, item["subtitle"], fonts["sub"], MUTED)
        item["extra"](ld, t, W / 2 - 150, y1 + 36, 1.0, fonts)
        top = 250
        right = lerp(0, W, reveal)
        ImageDraw.Draw(mask).rectangle([0, top * S, right * S, H * S], fill=255)
        # Text pixels only, so the backdrop stripes show through.
        ink = ImageChops.difference(layer, Image.new("RGB", im.size, PANEL)).convert("L")
        ink = ink.point(lambda v: 255 if v > 4 else 0)
        im.paste(layer, (0, 0), ImageChops.multiply(mask, ink))
        if reveal < 1:
            d.rectangle([(right - 2) * S, top * S, (right + 1) * S, (H - 10) * S], fill=ACCENT)

    return im.resize((W, H), Image.LANCZOS)


def save_gif(frames, path):
    probe = Image.new("RGB", (W, H * 3))
    for k, i in enumerate((0, int(FPS * 1.1), int(FPS * 3.6))):
        probe.paste(frames[i], (0, H * k))
    rest = probe.quantize(colors=256 - len(SWATCHES), method=Image.MEDIANCUT, dither=Image.NONE)
    colours = [v for c in SWATCHES for v in c] + rest.getpalette()[:3 * (256 - len(SWATCHES))]
    pal = Image.new("P", (1, 1))
    pal.putpalette(colours)
    out = [f.quantize(palette=pal, dither=Image.NONE) for f in frames]
    out[0].save(path, save_all=True, append_images=out[1:], duration=int(1000 / FPS),
                loop=0, optimize=False, disposal=1)
    size = os.path.getsize(path)
    print("%d frames, %.0f KB -> %s" % (len(frames), size / 1024, path))
    if size > LIMIT:
        raise SystemExit("too big for a Steam preview (1 MB)")


def main():
    os.makedirs(OUT, exist_ok=True)
    fonts = {"kicker": font(700, 15), "title": font(800, 46), "sub": font(600, 19),
             "small": font(700, 13), "code": font(600, 17)}
    base = backdrop()

    tpg_icon = Image.open(os.path.join(REPO, "icon512.png")).convert("RGBA")
    chip = e2sf_icon()
    chip.save(os.path.join(OUT, "tpg_e2sf_icon.png"))
    print("-> %s" % os.path.join(OUT, "tpg_e2sf_icon.png"))
    lit_cache = {}

    def chip_for(t):
        # Pins light up in turn while the chip line runs.
        if not (T_TEXT_IN[1] <= t <= T_TEXT_OUT[0]):
            return chip
        n = int((t - T_TEXT_IN[1]) * 12) % 16
        lit = tuple((n - j) % 16 for j in range(3))
        if lit not in lit_cache:
            lit_cache[lit] = e2sf_icon(lit)
        return lit_cache[lit]

    items = [
        ("tpg_thumb.gif", lambda t: tpg_icon, {
            "kicker": "A GAMEMODE FOR ACE",
            "title": ["THE PROVING", "GROUND"],
            "subtitle": "Combined arms, green against red.",
            "extra": tpg_extra,
        }),
        ("tpg_e2sf_thumb.gif", chip_for, {
            "kicker": "THE PROVING GROUND",
            "title": ["E2 & STARFALL"],
            "subtitle": "Team functions for your chips.",
            "extra": e2sf_extra,
        }),
    ]
    n = int(LOOP * FPS)
    for name, icon_for, item in items:
        frames = [frame(i / FPS, base, icon_for, item, fonts) for i in range(n)]
        save_gif(frames, os.path.join(OUT, name))


if __name__ == "__main__":
    main()
