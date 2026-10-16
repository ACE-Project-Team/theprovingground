"""Draw the two showcase GIFs for the Workshop page: media/modes.gif and media/loadout.gif.

    python tools/media/make_showcase.py

modes.gif plays all five game modes in turn, each in the header's style: Control
Points, King of the Hill, Rush, Capture the Flag and Deathmatch, with the ticket
bars at the top and the chat lines the server really broadcasts at the bottom.

loadout.gif is the player side: the five armour tiers with their real health,
armour, speed and cost, a few weapon kits, the rank ladder climbing from
Traffic Cone to Global Proving Elite, and the end-of-round commendations. The soldiers
are the tiers' real player models, rendered by render_tiers.py into media/tiers/.

Every number and name comes from the gamemode's own config (sh_armor.lua,
sh_gear.lua, sh_ranks.lua, sh_gametypes.lua, sv_commendations.lua) and the
point names from the map configs. Player names and ticket counts are made up.

Needs Pillow. Drawn at twice the size and scaled down, like the header.
"""

import math
import os

from PIL import Image, ImageDraw, ImageFont

REPO = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
FONTS = os.path.join(REPO, "resource", "fonts")
MEDIA = os.path.join(REPO, "media")

W, H = 960, 400
S = 2                      # supersampling
FPS = 10
GROUND = 340

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
NEUTRAL = (255, 214, 64)
WARN = (255, 140, 50)
RUSH = (255, 190, 60)      # sv_rush.lua's chat colour
# The icon's tank
OLIVE = (115, 160, 0)
OLIVE_DARK = (80, 112, 0)
TRACK = (44, 40, 52)
WHEEL = (168, 168, 40)
INK = (11, 6, 20)          # silhouettes
DIRT = (17, 9, 29)
PLATE = (92, 84, 110)      # armour plates
PLATE_DARK = (62, 56, 78)

TEAMS = {"green": ("The Green Terror", GREEN, GREEN_TEXT), "red": ("The Red Menace", RED, RED_TEXT)}

# sh_ranks.lua
RANKS = [
    (0, "Traffic Cone", (255, 140, 0)),
    (850, "Cannon Fodder", (170, 170, 170)),
    (950, "Cardboard Corporal", (196, 164, 132)),
    (1050, "Rust Bucket", (183, 110, 60)),
    (1150, "Scrap Sergeant", (140, 150, 160)),
    (1250, "Duct Tape Engineer", (120, 180, 210)),
    (1400, "Certified Road Hazard", (240, 200, 60)),
    (1550, "Turret Whisperer", (120, 210, 120)),
    (1700, "Sabot Sommelier", (190, 120, 220)),
    (1900, "Steel Baron", (90, 160, 255)),
    (2150, "Ballistic Computer With Legs", (255, 90, 90)),
    (2400, "Global Proving Elite", (255, 215, 0)),
]

# sh_armor.lua, with the costs from sh_gear.lua (None to Medium are free)
ARMOR = [
    ("None", 30, 0, 10, None),
    ("Light", 75, 50, 0, None),
    ("Medium", 100, 120, -10, None),
    ("Heavy", 150, 200, -15, 300),
    ("Juggernaut", 2000, 400, -40, 1200),
]

# Primary, secondary, special; prices from sh_gear.lua, anything unlisted is free
KITS = [
    (("AK-47", None), ("Deagle", None), ("AT-4", None)),
    (("M249 SAW", None), ("Glock", None), ("FGM-148 Javelin", 700)),
    (("Anti Materiel Rifle", 350), ("USP", None), ("FIM-92 Stinger", 500)),
    (("MP5", None), ("Five Seven", None), ("XM25", 500)),
]

SWATCHES = [PANEL, TROUGH, CARD, PURPLE, PURPLE_LIGHT, ACCENT, TEXT, MUTED, GREEN, GREEN_TEXT,
            RED, RED_TEXT, NEUTRAL, WARN, RUSH, OLIVE, OLIVE_DARK, TRACK, WHEEL, INK, DIRT,
            PLATE, PLATE_DARK] + [c for _, _, c in RANKS]


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
    return tuple(int(round(lerp(x, y, t))) for x, y in zip(c1, c2))


def span(t, a, b):
    return ease((t - a) / (b - a))


class Pen:
    """ImageDraw in 1x coordinates, scaled to the supersampled canvas."""

    def __init__(self, im):
        self.im = im
        self.d = ImageDraw.Draw(im)

    def rect(self, x0, y0, x1, y1, fill=None, outline=None, width=1, r=0):
        box = [x0 * S, y0 * S, x1 * S, y1 * S]
        if r:
            self.d.rounded_rectangle(box, r * S, fill=fill, outline=outline, width=int(width * S))
        else:
            self.d.rectangle(box, fill=fill, outline=outline, width=int(width * S))

    def ellipse(self, cx, cy, rx, ry, fill=None, outline=None, width=1):
        self.d.ellipse([(cx - rx) * S, (cy - ry) * S, (cx + rx) * S, (cy + ry) * S],
                       fill=fill, outline=outline, width=int(width * S))

    def poly(self, pts, fill):
        self.d.polygon([(x * S, y * S) for x, y in pts], fill=fill)

    def line(self, pts, fill, width):
        self.d.line([(x * S, y * S) for x, y in pts], fill=fill, width=max(1, int(width * S)))

    def text(self, x, y, s, f, fill, anchor="la"):
        self.d.text((x * S, y * S), s, font=f, fill=fill, anchor=anchor)

    def tlen(self, s, f):
        return self.d.textlength(s, font=f) / S


# ---------------------------------------------------------------- the field

def flat_ground(x):
    return GROUND + 5 * math.sin(x * 0.011 + 0.7) + 3 * math.sin(x * 0.031)


def hill_ground(x):
    return GROUND + 2 - 84 * math.exp(-((x - W / 2) / 190) ** 2)


def backdrop(ground):
    """Sky, two ridges and the ground. Static, so drawn once per terrain."""
    im = Image.new("RGB", (W * S, H * S), PANEL)
    p = Pen(im)
    for i, c in enumerate([PANEL, (27, 15, 46), (35, 20, 60), TROUGH, (58, 30, 98)]):
        p.rect(0, i * 52, W, H, fill=c)
    for sx, sy in [(70, 150), (190, 172), (300, 140), (610, 160), (720, 146), (880, 178), (420, 182)]:
        p.rect(sx, sy, sx + 2, sy + 2, fill=MUTED)
    for base, amp, seed, c in ((282, 16, 1.3, (30, 17, 52)), (310, 11, 4.1, (24, 13, 41))):
        pts = [(0, H)] + [(x, base + amp * (math.sin(x * 0.006 + seed) * 0.6 + math.sin(x * 0.017 + seed * 2) * 0.4))
                          for x in range(0, W + 40, 40)] + [(W, H)]
        p.poly(pts, c)
    p.poly([(0, H)] + [(x, ground(x)) for x in range(0, W + 8, 8)] + [(W, H)], DIRT)
    return im


def tank(p, x, gy, facing, recoil=0.0, flash=0.0, pennant=None, t=0.0, wreck=False):
    """The icon's tank, flat, facing +1 (right) or -1 (left)."""
    k = 0.8

    def P(px, py):
        return (x + px * facing * k, gy - py * k)

    body, dark = (OLIVE, OLIVE_DARK) if not wreck else (TRACK, INK)
    p.poly([P(-62, 6), P(62, 6), P(70, 18), P(-70, 18)], TRACK)
    for wx in (-44, -22, 0, 22, 44):
        cx, cy = P(wx, 12)
        p.ellipse(cx, cy, 6 * k, 6 * k, fill=WHEEL if not wreck else PLATE_DARK)
    p.poly([P(-66, 18), P(66, 18), P(58, 34), P(-62, 34)], body)
    p.poly([P(-66, 18), P(66, 18), P(64, 22), P(-64, 22)], dark)
    if wreck:
        return
    p.poly([P(-30, 34), P(24, 34), P(18, 52), P(-24, 52)], body)
    gun = 96 - recoil
    p.poly([P(14, 42), P(gun, 42), P(gun, 47), P(14, 47)], dark)
    p.poly([P(-20, 52), P(-17, 52), P(-17, 84), P(-20, 84)], INK)
    if pennant:
        tx, ty = P(-18.5, 84)
        wave = math.sin(t * 7) * 2
        p.poly([(tx, ty), (tx - 16 * facing, ty + 3 + wave), (tx, ty + 7)], pennant)
    if flash:
        mx, my = P(gun + 10, 44.5)
        r = 12 * flash
        p.poly([(mx - r * 0.2 * facing, my - r), (mx + r * 1.4 * facing, my), (mx - r * 0.2 * facing, my + r)], NEUTRAL)
        p.ellipse(mx, my, r * 0.6, r * 0.6, fill=TEXT)


def muzzle(x, gy, facing):
    return (x + 106 * facing * 0.8, gy - 44.5 * 0.8)


def soldier(p, x, gy, facing, colour, phase, scale=1.0, running=False):
    bob = abs(math.sin(phase)) * 2
    stride = math.sin(phase) * (11 if running else 7)
    lean = 4 if running else 0

    def L(x1, y1, x2, y2, w):
        p.line([(x + x1 * facing * scale, gy - y1 * scale), (x + x2 * facing * scale, gy - y2 * scale)], INK, w * scale)

    L(0, 20 + bob, -stride, 0, 5)
    L(0, 20 + bob, stride, 0, 5)
    L(0, 20 + bob, 2 + lean, 40 + bob, 8)
    hx, hy = x + (3 + lean) * facing * scale, gy - (47 + bob) * scale
    p.ellipse(hx, hy, 6 * scale, 6 * scale, fill=INK)
    p.rect(hx - 6 * scale, hy - 2 * scale, hx + 6 * scale, hy + 1 * scale, fill=colour)
    L(-2 + lean, 34 + bob, 22 + lean, 37 + bob, 3)
    L(4 + lean, 36 + bob, 14 + lean, 33 + bob, 4)
    return hx, hy


def point(p, cx, gy, colour, height, t, f_label=None, label=None, size=1.0, ring=None):
    """A control point: disc, pole, flag at `height` (0 bottom, 1 top)."""
    disc = mix(PANEL, colour, 0.75)
    p.ellipse(cx, gy, 56 * size, 8 * size, fill=disc)
    p.ellipse(cx, gy, 36 * size, 5 * size, fill=mix(disc, colour, 0.6))
    if ring is not None:
        r = (56 + ring * 46) * size
        p.ellipse(cx, gy, r, r * 0.14, outline=mix(colour, PANEL, ring), width=2.5)
    pole_top = gy - 82 * size
    p.rect(cx - 2, pole_top, cx + 2, gy, fill=MUTED)
    fy = lerp(gy - 30 * size, pole_top + 2, height)
    fw, fh = 48 * size, 28 * size
    top, bottom = [], []
    for i in range(0, int(fw) + 1, 4):
        wob = math.sin(t * 6 - i * 0.14) * (i / fw) * 4
        top.append((cx + 2 + i, fy + wob))
        bottom.append((cx + 2 + i, fy + fh + wob))
    p.poly(top + bottom[::-1], colour)
    if label:
        p.ellipse(cx, pole_top - 14, 11, 11, fill=PANEL, outline=colour, width=2)
        p.text(cx, pole_top - 14, label, f_label, colour, anchor="mm")


def tracer(p, a, b, prog, colour=NEUTRAL):
    """A shell in flight, prog 0..1 from a to b."""
    if not 0 <= prog <= 1:
        return
    x, y = lerp(a[0], b[0], prog), lerp(a[1], b[1], prog) - math.sin(prog * math.pi) * 10
    dx, dy = b[0] - a[0], b[1] - a[1]
    n = math.hypot(dx, dy) or 1
    p.line([(x - dx / n * 26, y - dy / n * 26), (x, y)], colour, 3)
    p.ellipse(x, y, 2.5, 2.5, fill=TEXT)


def boom(p, x, y, age, big=1.0):
    """An explosion that's `age` seconds old, then smoke."""
    if age < 0:
        return
    if age < 0.7:
        a = age / 0.7
        r = (14 + 46 * ease(a)) * big
        p.ellipse(x, y, r, r * 0.8, fill=mix(WARN, DIRT, a))
        p.ellipse(x, y, r * 0.65, r * 0.55, fill=mix(NEUTRAL, WARN, a))
        if a < 0.5:
            p.ellipse(x, y, r * 0.35, r * 0.3, fill=TEXT)
        for k in range(6):
            ang = k * 1.05 + 0.4
            dist = (20 + 60 * a) * big
            p.rect(x + math.cos(ang) * dist - 2, y - math.sin(ang) * dist * 0.9 + a * 30 - 2,
                   x + math.cos(ang) * dist + 2, y - math.sin(ang) * dist * 0.9 + a * 30 + 2, fill=NEUTRAL)
    for k in range(4):
        sa = age - 0.3 - k * 0.45
        if sa < 0:
            continue
        sa %= 1.8
        r = (8 + sa * 10) * big
        p.ellipse(x + math.sin(k * 2.1 + sa) * 8, y - 10 - sa * 40, r, r, fill=mix((58, 30, 98), TROUGH, sa / 1.8))


def puff(p, x, y, age):
    if 0 <= age < 0.5:
        r = 6 + age * 30
        p.ellipse(x, y, r, r * 0.6, fill=mix(MUTED, DIRT, age / 0.5))


# --------------------------------------------------------- HUD and chrome

def chat(p, t, lines, f):
    """The last two chat lines whose time has come, newest at the bottom."""
    shown = [ln for ln in lines if t >= ln[0]][-2:]
    y = H - 12
    for k, (start, s, c) in enumerate(reversed(shown)):
        a = clamp((t - start) / 0.25)
        dim = 1.0 if k == 0 else 0.55
        w = p.tlen(s, f)
        p.rect(16, y - 26, 16 + w + 26, y, fill=mix(DIRT, CARD, a))
        p.rect(16, y - 26, 19, y, fill=mix(DIRT, c, a * dim))
        p.text(30, y - 13, s, f, mix(DIRT, c, a * dim), anchor="lm")
        y -= 30


def ticket_bars(p, t, green, red, top, fonts, overtime=False):
    f_name, f_num, f_pill = fonts
    p.rect(0, 0, W, 44, fill=PANEL)
    p.rect(0, 44, W, 46, fill=PURPLE)
    for side, value, x0, x1, num_x, anchor in (("green", green, 16, 350, 362, "la"),
                                               ("red", red, W - 350, W - 16, W - 362, "ra")):
        name, col, tcol = TEAMS[side]
        p.text(x0 if side == "green" else x1, 7, name.upper(), f_name, tcol, anchor=anchor)
        p.rect(x0, 25, x1, 35, fill=TROUGH)
        fill = (x1 - x0) * clamp(value / top)
        if side == "green":
            p.rect(x0, 25, x0 + fill, 35, fill=col)
        else:
            p.rect(x1 - fill, 25, x1, 35, fill=col)
        p.text(num_x, 22, "%d" % max(0, value), f_num, TEXT, anchor="lm" if side == "green" else "rm")
    if overtime:
        a = 0.6 + 0.4 * math.sin(t * 9)
        p.rect(W / 2 - 52, 12, W / 2 + 52, 34, fill=mix(PANEL, WARN, a), r=11)
        p.text(W / 2, 23, "OVERTIME", f_pill, PANEL, anchor="mm")


def title(p, name, desc, fonts):
    f_title, f_desc = fonts
    p.text(W / 2 + 3, 58 + 3, name.upper(), f_title, PURPLE, anchor="mt")
    p.text(W / 2, 58, name.upper(), f_title, TEXT, anchor="mt")
    p.text(W / 2, 108, desc, f_desc, MUTED, anchor="mt")


def tabs(p, items, current, f, y=136):
    gap = 26
    widths = [p.tlen(s, f) for s in items]
    x = W / 2 - (sum(widths) + gap * (len(items) - 1)) / 2
    for i, (s, w) in enumerate(zip(items, widths)):
        on = i == current
        p.text(x, y, s, f, ACCENT if on else mix(PANEL, MUTED, 0.6))
        if on:
            p.rect(x, y + 18, x + w, y + 20, fill=ACCENT)
        x += w + gap


def wipe(p, t):
    """Opens each scene: a purple slab that slides off to the right."""
    a = span(t, 0.0, 0.35)
    if a >= 1:
        return
    x = a * (W + 80)
    p.poly([(x - 80, 0), (W + 80, 0), (W + 80, H), (x, H)], PURPLE)
    p.poly([(x - 80, 0), (x - 66, 0), (x + 14, H), (x, H)], ACCENT)


def brand(p, icon_small):
    p.im.paste(icon_small, ((W - 52) * S, (H - 50) * S), icon_small)


# ------------------------------------------------------------ the modes

MODES = ["CONTROL POINTS", "KING OF THE HILL", "RUSH", "CAPTURE THE FLAG", "DEATHMATCH"]


def scene_cp(p, t, f):
    g, r = flat_ground, None
    t_cap = (0.9, 3.4)
    h = span(t, *t_cap)
    owned = t >= t_cap[1]
    point(p, 200, g(200), GREEN, 1.0, t, f["label"], "A")
    point(p, 480, g(480), GREEN if owned else NEUTRAL, h, t, f["label"], "B",
          ring=clamp((t - t_cap[1]) / 0.5) if 0 <= t - t_cap[1] < 0.5 else None)
    point(p, 760, g(760), RED, 1.0, t, f["label"], "C")
    for k, off in enumerate((0, 34, 70)):
        sx = lerp(300, 400, ease(t / 3)) + off
        soldier(p, sx, g(sx), 1, GREEN, t * 7 + k * 1.7)
    for k, off in enumerate((0, 40)):
        sx = lerp(700, 610, span(t, 3.0, 6.0)) + off
        soldier(p, sx, g(sx), -1, RED, t * 7 + k * 2.1)
    fire(p, t, g, 70, 890, [1.2, 4.0], [2.4, 5.2])
    cap = max(0.0, t - t_cap[1])
    return 512 - 2 * t, 547 - 3 * t - 9 * cap, [
        (t_cap[1], "[Bridge] captured by The Green Terror!", GREEN_TEXT),
    ]


def fire(p, t, g, gx, rx, g_shots, r_shots, miss=True):
    """Two tanks at the ends of the field trading shots that land short."""
    for x, facing, shots, col in ((gx, 1, g_shots, GREEN), (rx, -1, r_shots, RED)):
        since = min([t - s for s in shots if t >= s] or [9])
        tank(p, x, g(x), facing, recoil=7 * max(0.0, 1 - since / 0.35), flash=max(0.0, 1 - since / 0.15),
             pennant=col, t=t)
        if miss:
            for s in shots:
                a = muzzle(x, g(x), facing)
                hit_x = x + facing * 330
                b = (hit_x, g(hit_x) - 4)
                tracer(p, a, b, (t - s) / 0.3)
                puff(p, b[0], b[1], t - s - 0.3)


def scene_koth(p, t, f):
    g = hill_ground
    cx = W / 2
    lower, raise_ = (0.6, 2.4), (2.6, 4.4)
    if t < lower[1]:
        colour, h = GREEN, 1 - span(t, *lower)
    elif t < raise_[0]:
        colour, h = NEUTRAL, 0.0
    else:
        colour, h = (RED if t >= raise_[1] else NEUTRAL), span(t, *raise_)
    ring = None
    for ev in (lower[1], raise_[1]):
        if 0 <= t - ev < 0.5:
            ring = (t - ev) / 0.5
    point(p, cx, g(cx), colour, h, t, size=1.15, ring=ring)
    for k, off in enumerate((0, 36, 74, 110)):
        sx = lerp(760, 590, ease(t / 3.5)) + off
        soldier(p, sx, g(sx), -1, RED, t * 7 + k * 1.3)
    for k, off in enumerate((0, 40)):
        sx = lerp(360, 250, span(t, 1.0, 4.0)) - off
        soldier(p, sx, g(sx), 1, GREEN, t * 7 + k * 2.3)
    fire(p, t, g, 70, 890, [2.0], [0.8, 3.4])
    held = max(0.0, t - raise_[1])
    return 431 - 2 * t - 22 * held, 389 - 4 * min(t, lower[1]), [
        (lower[1], "[The Hill] has been neutralized!", NEUTRAL),
        (raise_[1], "[The Hill] captured by The Red Menace!", RED_TEXT),
    ]


RUSH_STAGES = [(180, "Docks"), (410, "Bridge"), (640, "Warehouse"), (850, "Beach House")]


def scene_rush(p, t, f):
    g = flat_ground
    hold = (0.7, 3.6)
    taken = t >= hold[1]
    for i, (x, name) in enumerate(RUSH_STAGES):
        gy = g(x)
        if i == 0:
            p.ellipse(x, gy, 40, 6, fill=mix(PANEL, GREEN, 0.35))
            p.rect(x - 1.5, gy - 46, x + 1.5, gy, fill=PLATE)
            p.poly([(x + 1.5, gy - 46), (x + 26, gy - 39), (x + 1.5, gy - 32)], mix(PANEL, GREEN, 0.6))
        elif i == 1:
            fill = span(t, *hold)
            colour = GREEN if taken else NEUTRAL
            pulse = None if taken else (t * 0.9) % 1
            point(p, x, gy, colour, fill, t, f["label"], "2", ring=pulse)
            if not taken:
                bx = x - 60
                p.rect(bx, gy - 136, bx + 120, gy - 126, fill=TROUGH, r=3)
                p.rect(bx, gy - 136, bx + 120 * fill, gy - 126, fill=GREEN, r=3)
                p.text(x, gy - 140, "HOLD  0:%02d" % round(60 * (1 - fill)), f["small"], TEXT, anchor="mb")
        else:
            reveal = i == 2 and t >= 4.8
            a = 0.5 + 0.5 * math.sin(t * 6) if reveal else 0.35
            p.ellipse(x, gy - 30, 16, 16, fill=PANEL, outline=mix(PANEL, RUSH if reveal else MUTED, a), width=2)
            p.text(x, gy - 30, "?", f["label"], mix(PANEL, RUSH if reveal else MUTED, a), anchor="mm")
    # Stage pips under the tabs
    for i in range(4):
        x = W / 2 - 66 + i * 44
        done = i == 0 or (i == 1 and taken)
        col = GREEN if done else (RUSH if i == 1 else mix(PANEL, MUTED, 0.35))
        p.rect(x - 16, 168, x + 16, 174, fill=col, r=3)
    for k, off in enumerate((0, 30, 62)):
        sx = lerp(250, 360, ease(t / 2.4)) + off
        soldier(p, sx, g(sx), 1, GREEN, t * 7 + k * 1.9)
    sx = lerp(620, 520, span(t, 1.5, 4.5))
    soldier(p, sx, g(sx), -1, RED, t * 7)
    fire(p, t, g, 70, 890, [2.6], [1.4, 4.6])
    return 466 - 2 * t, 452 - 2 * t - (40 if taken else 0), [
        (0.2, "[TPG] STAGE 2 of 4: Bridge is live. Hold it for 60s to take the stage.", RUSH),
        (hold[1], "[TPG] The Green Terror takes stage 2. 2 - 0.", GREEN_TEXT),
        (4.8, "[TPG] Next point in 30 seconds. Location unknown until then - kills still bleed tickets.", RUSH),
    ]


def spawn_pad(p, x, gy, colour, f):
    p.ellipse(x, gy, 60, 8, fill=mix(DIRT, colour, 0.25))
    p.ellipse(x, gy, 60, 8, outline=mix(DIRT, colour, 0.7), width=2)
    p.text(x, gy + 14, "SPAWN", f["tiny"], mix(DIRT, colour, 0.8), anchor="mt")


def ctf_status(p, status, colour, f):
    """The CTF box the HUD draws under the objectives (cl_hud_ctf.lua)."""
    w = max(250, p.tlen(status, f["small"]) + 40)
    p.rect(W / 2 - w / 2, 162, W / 2 + w / 2, 206, fill=mix(PANEL, INK, 0.6), r=6)
    p.text(W / 2, 175, "CAPTURE THE FLAG", f["label"], TEXT, anchor="mm")
    p.text(W / 2, 194, status, f["small"], colour, anchor="mm")


def scene_ctf(p, t, f):
    g = flat_ground
    home_x, gs, rs = W / 2, 110, 800
    grab, home = 1.7, 4.6
    if t < grab:
        x, facing = lerp(250, home_x - 6, t / grab), 1
    elif t < home:
        x, facing = lerp(home_x - 6, gs, (t - grab) / (home - grab)), -1
    else:
        x, facing = gs, 1
    carrying = grab <= t < home
    back = t >= home + 0.7
    spawn_pad(p, gs, g(gs), GREEN, f)
    spawn_pad(p, rs, g(rs), RED, f)
    # The flag's home: the map's KOTH point
    hy = g(home_x)
    p.ellipse(home_x, hy, 40, 6, fill=mix(PANEL, NEUTRAL, 0.4))
    if not carrying and (t < grab or back):
        a = 1.0 if t < grab else clamp((t - home - 0.7) / 0.3)
        p.rect(home_x - 1.5, hy - 60, home_x + 1.5, hy, fill=mix(DIRT, MUTED, a))
        pts = [(home_x + 1.5 + i, hy - 60 + math.sin(t * 6 - i * 0.2) * (i / 34) * 3) for i in range(0, 35, 4)]
        p.poly(pts + [(px, py + 20) for px, py in pts][::-1], mix(DIRT, NEUTRAL, a))
    tank(p, 250, g(250), 1, pennant=GREEN, t=t)
    since = min([t - s for s in (1.1, 3.0) if t >= s] or [9])
    tank(p, 700, g(700), -1, recoil=7 * max(0.0, 1 - since / 0.35), flash=max(0.0, 1 - since / 0.15),
         pennant=RED, t=t)
    for s, lead in ((1.1, 50), (3.0, -60)):
        a = muzzle(700, g(700), -1)
        aim = lerp(250, home_x, s / grab) if s < grab else lerp(home_x, gs, (s - grab) / (home - grab))
        b = (aim + lead, g(aim + lead) - 3)
        tracer(p, a, b, (t - s) / 0.3)
        puff(p, b[0], b[1], t - s - 0.3)
    if t >= grab + 0.2:
        cx = lerp(home_x + 160, gs + 120, clamp((t - grab - 0.2) / (home - grab)))
        soldier(p, cx, g(cx), -1, RED, t * 12, running=t < home)
    hx, hy2 = soldier(p, x, g(x), facing, GREEN, t * 13, running=t < home)
    if carrying:
        px = hx - facing * 8
        p.rect(px - 1.5, hy2 - 26, px + 1.5, hy2 + 22, fill=MUTED)
        wave = math.sin(t * 9) * 2
        p.poly([(px, hy2 - 26), (px - facing * 26, hy2 - 21 + wave), (px - facing * 26, hy2 - 7 + wave),
                (px, hy2 - 12)], NEUTRAL)
    if 0 <= t - home < 0.5:
        r = 60 + (t - home) / 0.5 * 50
        p.ellipse(gs, g(gs), r, r * 0.14, outline=GREEN, width=2.5)
    if carrying:
        ctf_status(p, "HELD BY THE GREEN TERROR  (Duct Tape Dave)", GREEN, f)
    else:
        ctf_status(p, "NEUTRAL", (255, 255, 0), f)
    return 401 - 2 * t, 488 - 2 * t - (100 if t >= home else 0), [
        (home, "[CTF] Duct Tape Dave delivered the flag for The Green Terror!", GREEN_TEXT),
    ]


def scene_dm(p, t, f):
    g = flat_ground
    kills = {660: 2.4, 300: 4.0}
    shots = [(120, 1, 1.0, 660, False), (300, 1, 2.1, 660, True), (840, -1, 1.6, 300, False),
             (660, -1, 1.9, 300, False), (840, -1, 3.7, 300, True), (120, 1, 4.5, 840, False)]
    for x, facing, col in ((120, 1, GREEN), (300, 1, GREEN), (660, -1, RED), (840, -1, RED)):
        dead = x in kills and t >= kills[x]
        mine = [s for s in shots if s[0] == x and t >= s[2]]
        since = min([t - s[2] for s in mine] or [9])
        tank(p, x, g(x), facing, recoil=7 * max(0.0, 1 - since / 0.35), flash=max(0.0, 1 - since / 0.15),
             pennant=col, t=t, wreck=dead)
    for x, facing, s, target, hit in shots:
        a = muzzle(x, g(x), facing)
        tx = target if hit else target - facing * 70
        b = (tx, g(tx) - (22 if hit else 3))
        tracer(p, a, b, (t - s) / 0.3)
        if not hit:
            puff(p, b[0], b[1], t - s - 0.3)
    for x, when in kills.items():
        boom(p, x, g(x) - 24, t - when)
    for k, x in enumerate((420, 455)):
        soldier(p, x + math.sin(t + k) * 6, g(x), 1, GREEN, t * 6 + k * 2)
    for k, x in enumerate((520, 560)):
        soldier(p, x - math.sin(t + k) * 6, g(x), -1, RED, t * 6 + k * 2)
    for x, when, side in ((660, 2.4, "red"), (300, 4.0, "green")):
        a = t - when
        if 0 <= a < 1.4:
            col = TEAMS[side][2]
            p.text(x, g(x) - 70 - a * 24, "-1 VEHICLE", f["small"], mix(DIRT, col, 1 - max(0.0, a - 0.9) / 0.5),
                   anchor="mb")
    overtime = t >= 4.6
    bleed = max(0.0, t - 4.6) * 6
    green = 212 - (24 if t >= 4.0 else 0) - bleed
    red = 198 - (24 if t >= 2.4 else 0) - bleed
    return green, red, [
        (4.6, "[TPG] OVERTIME! Both teams are now bleeding tickets - force the fight!", WARN),
    ], overtime


MODE_SCENES = [
    ("Control Points", "Capture and hold control points", flat_ground, scene_cp, 6.0),
    ("King of the Hill", "Hold the central point", hill_ground, scene_koth, 6.0),
    ("Rush", "One point at a time - take it and hold it", flat_ground, scene_rush, 6.6),
    ("Capture the Flag", "One neutral flag - carry it to your spawn", flat_ground, scene_ctf, 6.4),
    ("Deathmatch", "Destroy enemy vehicles", flat_ground, scene_dm, 6.4),
]


def modes_frames(icon_small, fonts):
    bgs = {}
    frames = []
    for i, (name, desc, ground, fn, length) in enumerate(MODE_SCENES):
        if ground not in bgs:
            bgs[ground] = backdrop(ground)
        for n in range(int(length * FPS)):
            t = n / FPS
            im = bgs[ground].copy()
            p = Pen(im)
            res = fn(p, t, fonts)
            green, red, lines = res[:3]
            overtime = res[3] if len(res) > 3 else False
            title(p, name, desc, (fonts["title"], fonts["desc"]))
            tabs(p, ["CP", "KOTH", "RUSH", "CTF", "DM"], i, fonts["tab"])
            ticket_bars(p, t, green, red, 600, (fonts["name"], fonts["num"], fonts["pill"]), overtime)
            chat(p, t, lines, fonts["chat"])
            brand(p, icon_small)
            wipe(p, t)
            frames.append(im.resize((W, H), Image.LANCZOS))
    return frames


# --------------------------------------------------------- the player side

TIER_FILES = ["none", "light", "medium", "heavy", "juggernaut"]
SPRITES = []               # filled by load_sprites()


def load_sprites():
    """The tier renders from render_tiers.py, each with a team-green outline."""
    from PIL import ImageFilter
    for name in TIER_FILES:
        im = Image.open(os.path.join(MEDIA, "tiers", name + ".png")).convert("RGBA")
        alpha = im.getchannel("A")
        rim = alpha.filter(ImageFilter.MaxFilter(7))
        out = Image.new("RGBA", im.size, GREEN + (0,))
        out.putalpha(rim)
        out.alpha_composite(im)
        SPRITES.append(out)


def paste_sprite(p, tier, cx, feet, fade=1.0):
    sp = SPRITES[tier]
    if fade < 1:
        sp = sp.copy()
        sp.putalpha(sp.getchannel("A").point(lambda v: int(v * fade)))
    p.im.paste(sp, (int(cx * S - sp.width / 2), int(feet * S - sp.height + 6 * S)), sp)


def stat_bar(p, x, y, label, value_text, frac, colour, f_label, f_value, width=250):
    p.text(x, y, label, f_label, MUTED, anchor="lm")
    bx = x + 90
    p.rect(bx, y - 5, bx + width, y + 5, fill=TROUGH, r=4)
    p.rect(bx, y - 5, bx + max(8, width * clamp(frac)), y + 5, fill=colour, r=4)
    p.text(bx + width + 14, y, value_text, f_value, TEXT, anchor="lm")


def scene_loadout(p, t, f):
    step = 1.7
    tier = min(4, int(t // step))
    blend = span(t - tier * step, 0, 0.4)
    prev = max(0, tier - 1) if tier else 0
    gy = 352
    p.ellipse(220, gy, 120, 14, fill=CARD)
    p.ellipse(220, gy, 90, 9, fill=TROUGH)
    pop = 1 - blend
    if pop > 0 and tier:
        p.ellipse(220, gy, 90 + pop * 50, 9 + pop * 6, outline=mix(DIRT, ACCENT, pop), width=2)
    if tier and blend < 1:
        paste_sprite(p, prev, 220, gy - 2, 1 - blend)
    paste_sprite(p, tier, 220, gy - 2, blend if tier else 1.0)

    x0 = 430
    # Tier pills
    px = x0
    for i, (name, *_rest) in enumerate(ARMOR):
        w = p.tlen(name, f["pill"]) + 22
        on = i == tier
        p.rect(px, 168, px + w, 192, fill=PURPLE if on else CARD, outline=ACCENT if on else None, width=1.5, r=12)
        p.text(px + w / 2, 180, name, f["pill"], TEXT if on else MUTED, anchor="mm")
        px += w + 8

    name, hp, armour, speed, cost = ARMOR[tier]
    _, hp0, armour0, speed0, _ = ARMOR[prev]
    hp_v = lerp(hp0, hp, blend)
    ar_v = lerp(armour0, armour, blend)
    sp_v = lerp(speed0, speed, blend)
    stat_bar(p, x0, 216, "HEALTH", "%d" % round(hp_v), math.sqrt(hp_v / 2000), GREEN, f["label"], f["value"])
    stat_bar(p, x0, 242, "ARMOUR", "%d" % round(ar_v), ar_v / 400, ACCENT, f["label"], f["value"])
    stat_bar(p, x0, 268, "SPEED", "%+d" % round(sp_v), (sp_v + 50) / 60, NEUTRAL, f["label"], f["value"])
    p.text(x0, 292, "COST", f["label"], MUTED, anchor="lm")
    p.text(x0 + 90, 292, "Free" if cost is None else "%d points" % cost, f["value"], TEXT if cost is None else NEUTRAL,
           anchor="lm")
    if tier == 4:
        a = clamp((t - tier * step) / 0.3)
        p.text(x0 + 220, 292, "Can't use vehicle seats", f["value"], mix(PANEL, WARN, a), anchor="lm")

    # Weapon kit cards, changing on their own beat
    kit_i = int(t // 2.5) % len(KITS)
    k_blend = span(t - (t // 2.5) * 2.5, 0, 0.3)
    for slot, (label, (wname, wcost)) in enumerate(zip(("PRIMARY", "SECONDARY", "SPECIAL"), KITS[kit_i])):
        cx0 = x0 + slot * 158
        p.rect(cx0, 312, cx0 + 150, 364, fill=CARD, outline=TROUGH, width=1.5, r=6)
        p.text(cx0 + 10, 322, label, f["tiny"], ACCENT, anchor="lm")
        y = lerp(360, 342, k_blend)
        wf = f["kit"] if p.tlen(wname, f["kit"]) < 130 else f["value"]
        p.text(cx0 + 10, y, wname, wf, mix(CARD, TEXT, k_blend), anchor="lm")
        p.text(cx0 + 140, 322, "Free" if wcost is None else str(wcost), f["tiny"],
               MUTED if wcost is None else NEUTRAL, anchor="rm")
        p.rect(cx0, 362, cx0 + 150, 368, fill=PANEL)


def rank_of(rating):
    best = 0
    for i, (mn, _, _) in enumerate(RANKS):
        if rating >= mn:
            best = i
    return best


def scene_ranks(p, t, f):
    rating = lerp(830, 2460, span(t, 0.4, 6.4) ** 1.15)
    idx = rank_of(rating)
    mn, name, col = RANKS[idx]
    nxt = RANKS[idx + 1] if idx + 1 < len(RANKS) else None
    prog = 1.0 if nxt is None else clamp((rating - mn) / (nxt[0] - mn))

    # Ladder, two columns of six
    for i, (rmn, rname, rcol) in enumerate(RANKS):
        colx = 440 if i < 6 else 700
        y = 180 + (i % 6) * 30
        on = i == idx
        passed = i < idx
        if on:
            p.rect(colx - 8, y - 12, colx + 256, y + 12, fill=TROUGH, r=4)
            p.rect(colx - 8, y - 12, colx - 5, y + 12, fill=rcol)
        p.rect(colx, y - 5, colx + 10, y + 5, fill=rcol if (on or passed) else mix(PANEL, rcol, 0.3), r=2)
        p.text(colx + 18, y, rname, f["rank"], rcol if on else (MUTED if passed else mix(PANEL, MUTED, 0.45)),
               anchor="lm")
        p.text(colx + 250, y, str(rmn), f["tiny"], MUTED if (on or passed) else mix(PANEL, MUTED, 0.45), anchor="rm")

    # The current one, big
    p.text(60, 178, "RATING", f["label"], MUTED, anchor="lm")
    p.text(60, 214, "%d" % rating, f["rating"], TEXT, anchor="lm")
    p.text(60, 268, name, f["rankbig"] if p.tlen(name, f["rankbig"]) < 380 else f["rankmid"], col, anchor="lm")
    p.rect(60, 300, 420, 310, fill=TROUGH, r=5)
    p.rect(60, 300, 60 + max(10, 360 * prog), 310, fill=col, r=5)
    p.text(60, 326, "Next: %s at %d" % (nxt[1], nxt[0]) if nxt else "Top of the ladder", f["value"], MUTED,
           anchor="lm")


MEDALS = [("Most Kills", GREEN), ("Most Kills Per Ton", RED), ("Most Objective Kills", GREEN),
          ("Most Captures", RED)]


def medal(p, cx, cy, ribbon, a, t):
    r = 30 * ease(a)
    if r <= 0:
        return
    p.poly([(cx - 16, cy - 64), (cx - 4, cy - 64), (cx + 6, cy - 22), (cx - 6, cy - 22)], ribbon)
    p.poly([(cx + 4, cy - 64), (cx + 16, cy - 64), (cx + 6, cy - 22), (cx - 6, cy - 22)], mix(ribbon, PANEL, 0.4))
    p.ellipse(cx, cy, r, r, fill=WARN)
    p.ellipse(cx, cy, r * 0.8, r * 0.8, fill=NEUTRAL)
    pts = []
    for k in range(10):
        ang = -math.pi / 2 + k * math.pi / 5
        rr = r * (0.5 if k % 2 == 0 else 0.22)
        pts.append((cx + math.cos(ang) * rr, cy + math.sin(ang) * rr))
    p.poly(pts, WARN)
    shine = (t * 0.7) % 1.6
    if shine < 1 and a >= 1:
        sx = cx - r * 0.5 + shine * r
        p.line([(sx - 4, cy - r * 0.5), (sx + 4, cy + r * 0.5)], (255, 240, 180), 3)


def scene_medals(p, t, f):
    for i, (cat, ribbon) in enumerate(MEDALS):
        a = clamp((t - 0.4 - i * 0.5) / 0.4)
        cx = 140 + i * 227
        p.rect(cx - 100, 160, cx + 100, 300, fill=mix(PANEL, CARD, a), r=8)
        medal(p, cx, 222, ribbon, a, t + i)
        p.text(cx, 276, cat, f["kit"], mix(CARD, TEXT, a), anchor="mm")
    a = clamp((t - 2.6) / 0.4)
    p.rect(W / 2 - 300, 318, W / 2 + 300, 352, fill=mix(PANEL, PURPLE, a), r=17)
    p.text(W / 2, 335, "Global leaderboard incoming - check out acegmod.com", f["kit"], mix(PURPLE, TEXT, a),
           anchor="mm")


PLAYER_SCENES = [
    ("Loadout", "Pick an armour tier and a kit before you spawn", scene_loadout, 9.6),
    ("Ranks", "One rating across every map and session - everyone starts at 1000", scene_ranks, 7.6),
    ("Commendations", "Stats, ranks and medals are saved on the server", scene_medals, 5.8),
]


def player_frames(icon_small, fonts):
    base = Image.new("RGB", (W * S, H * S), PANEL)
    bp = Pen(base)
    bp.rect(0, 0, W, 44, fill=PANEL)
    bp.rect(0, 44, W, 46, fill=PURPLE)
    for k in range(-2, 30):
        x = k * 46
        bp.poly([(x, 46), (x + 14, 46), (x - 240, H), (x - 254, H)], (23, 13, 38))
    frames = []
    for i, (name, desc, fn, length) in enumerate(PLAYER_SCENES):
        for n in range(int(length * FPS)):
            t = n / FPS
            im = base.copy()
            p = Pen(im)
            p.text(16, 22, "THE PROVING GROUND", fonts["name"], MUTED, anchor="lm")
            title(p, name, desc, (fonts["title"], fonts["desc"]))
            lines = fn(p, t, fonts) or []
            chat(p, t, lines, fonts["chat"])
            brand(p, icon_small)
            wipe(p, t)
            frames.append(im.resize((W, H), Image.LANCZOS))
    return frames


# ---------------------------------------------------------------- output

def save_gif(frames, path):
    # One shared palette, so flat areas don't shimmer between frames. The
    # palette colours are put in exactly; the rest is the edge blends.
    picks = [frames[int(len(frames) * k / 6)] for k in range(6)]
    probe = Image.new("RGB", (W, H * len(picks)))
    for k, fr in enumerate(picks):
        probe.paste(fr, (0, H * k))
    swatches = list(dict.fromkeys(SWATCHES))
    rest = probe.quantize(colors=256 - len(swatches), method=Image.MEDIANCUT, dither=Image.NONE)
    colours = [v for c in swatches for v in c] + rest.getpalette()[:3 * (256 - len(swatches))]
    pal = Image.new("P", (1, 1))
    pal.putpalette(colours)
    out = [fr.quantize(palette=pal, dither=Image.NONE) for fr in frames]
    out[0].save(path, save_all=True, append_images=out[1:], duration=int(1000 / FPS), loop=0,
                optimize=False, disposal=1)
    print("%d frames, %.1f s, %.0f KB -> %s" % (len(frames), len(frames) / FPS, os.path.getsize(path) / 1024, path))


def main():
    icon = Image.open(os.path.join(REPO, "icon512.png")).convert("RGBA")
    load_sprites()
    icon_small = icon.resize((40 * S, 40 * S), Image.LANCZOS)
    fonts = {
        "title": font(800, 40), "desc": font(600, 16), "tab": font(700, 13), "name": font(700, 12),
        "num": font(800, 22), "pill": font(700, 13), "chat": font(600, 14), "label": font(700, 13),
        "small": font(700, 12), "tiny": font(700, 11), "value": font(600, 14), "kit": font(700, 15),
        "rank": font(700, 14), "rating": font(800, 48), "rankbig": font(800, 30), "rankmid": font(800, 24),
    }
    save_gif(modes_frames(icon_small, fonts), os.path.join(MEDIA, "modes.gif"))
    save_gif(player_frames(icon_small, fonts), os.path.join(MEDIA, "loadout.gif"))


if __name__ == "__main__":
    main()
