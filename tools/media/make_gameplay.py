"""Build media/gameplay.gif, the README's slideshow of real matches.

    python tools/media/make_gameplay.py SCREENSHOT_DIR
    python tools/media/make_gameplay.py SCREENSHOT_DIR --stills OUT_DIR

SCREENSHOT_DIR is the Steam screenshot folder the shots below came from
(userdata/<id>/760/remote/4000/screenshots). They are 1920x1080 frames from
a July 2026 match on gm_diprip_refinery, plus one from The Hill.

Player chat, names and the playtime overlay are blurred out of every shot
before anything else happens, and the caption panel is laid over where the
chat was, so nobody's messages end up in the repository.

With --stills it writes the same shots as full-size JPGs into OUT_DIR
instead, blurred and captioned the same way, for the Workshop gallery.

Needs Pillow.
"""

import os
import sys

from PIL import Image, ImageDraw, ImageFilter, ImageFont

REPO = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
FONTS = os.path.join(REPO, "resource", "fonts")
OUT = os.path.join(REPO, "media", "gameplay.gif")

W, H = 880, 495
HOLD_MS = 2400
FADE_FRAMES = 3
FADE_MS = 90

# File, caption. Single dashes only - this is text people read.
SHOTS = [
    ("20260718230738_1.jpg", "Two teams. One front."),
    ("20260718233053_1.jpg", "Stand on the point to take it"),
    ("20260718232407_1.jpg", "Infantry and armour, side by side"),
    ("20260718233450_1.jpg", "Build it in spawn. Drive it out."),
    ("20260718233657_1.jpg", "Every shell is ACE ballistics"),
    ("20260718234011_1.jpg", "Hold it, whatever it costs"),
    ("20260802004452_1.jpg", "Hold the hill"),
]

# 1920x1080 regions that hold someone's chat, name or an overlay. Chat and
# the console notice line can be on any shot; the caption panel sits exactly
# over the chat.
CHAT = (0, 730, 780, 840)
NOTICE = (0, 0, 1920, 50)
SCRUB = {
    "20260718230738_1.jpg": [(1690, 60, 1910, 135)],                     # playtime
    "20260802004452_1.jpg": [(1690, 60, 1910, 135), (1590, 880, 1900, 955)],  # playtime, name popup
}

# sh_palette.lua
PANEL = (19, 11, 32)
PURPLE = (88, 24, 167)
ACCENT = (0, 148, 255)
TEXT = (240, 238, 246)
MUTED = (170, 158, 190)
GREEN = (0, 255, 33)
RED = (255, 0, 0)


def scrub(im, name):
    for box in [CHAT, NOTICE] + SCRUB.get(name, []):
        region = im.crop(box).filter(ImageFilter.GaussianBlur(30))
        im.paste(region, box[:2])
    return im


def photo(path):
    return scrub(Image.open(path).convert("RGB"), os.path.basename(path)).resize((W, H), Image.LANCZOS)


def load_fonts(k=1):
    return (ImageFont.truetype(os.path.join(FONTS, "Exo2-800.ttf"), round(25 * k)),
            ImageFont.truetype(os.path.join(FONTS, "Exo2-600.ttf"), round(13 * k)))


def overlay_for(caption, number, total, icon, fonts, size=(W, H)):
    # Laid out for the GIF's W x H; k scales it up for the full-size stills.
    k = size[0] / W
    overlay = Image.new("RGBA", size, (0, 0, 0, 0))
    d = ImageDraw.Draw(overlay)
    f_cap, f_small = fonts

    def px(*v):
        return [round(n * k) for n in v]

    # Caption panel, bottom left, over where the chat was.
    text = caption.upper()
    tw = d.textlength(text, font=f_cap) / k
    sx = W / 1920
    x0, y0, y1 = 0, int(CHAT[1] * sx) - 6, int(CHAT[3] * sx) + 6
    x1 = max(int(CHAT[2] * sx) + 6, x0 + tw + 46)
    d.rectangle(px(x0, y0, x1, y1), fill=PANEL + (225,))
    d.rectangle(px(x0, y0, x0 + 5, y1), fill=ACCENT + (255,))
    d.text(px(x0 + 22, y0 + 9), "%02d / %02d" % (number, total), font=f_small, fill=MUTED + (255,))
    d.text(px(x0 + 22, y0 + 26), text, font=f_cap, fill=TEXT + (255,))

    # Brand chip, top left: icon512.png and the logo's two bars.
    d.rectangle(px(14, 14, 14 + 48 + 196, 14 + 48 + 12), fill=PANEL + (200,))
    d.text(px(14 + 60, 22), "THE PROVING GROUND", font=f_small, fill=TEXT + (255,))
    d.rectangle(px(14 + 60, 44, 14 + 60 + 80, 47), fill=GREEN + (255,))
    d.rectangle(px(14 + 60 + 86, 44, 14 + 60 + 166, 47), fill=RED + (255,))
    d.rectangle(px(14, 14, 14 + 48 + 196, 14 + 60), outline=PURPLE + (255,), width=round(2 * k))
    overlay.alpha_composite(icon.resize(tuple(px(48, 48)), Image.LANCZOS), tuple(px(20, 20)))

    return overlay


def compose(im, overlay):
    return Image.alpha_composite(im.convert("RGBA"), overlay).convert("RGB")


def stills(src, out):
    os.makedirs(out, exist_ok=True)
    icon = Image.open(os.path.join(REPO, "icon512.png")).convert("RGBA")
    for i, (f, caption) in enumerate(SHOTS):
        path = os.path.join(out, "gameplay_%02d.jpg" % (i + 1))
        im = scrub(Image.open(os.path.join(src, f)).convert("RGB"), f)
        overlay = overlay_for(caption, i + 1, len(SHOTS), icon, load_fonts(im.width / W), im.size)
        compose(im, overlay).save(path, quality=88)
        print("-> %s" % path)


def main():
    if len(sys.argv) == 4 and sys.argv[2] == "--stills":
        return stills(sys.argv[1], sys.argv[3])
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    src = sys.argv[1]
    icon = Image.open(os.path.join(REPO, "icon512.png")).convert("RGBA")
    fonts = load_fonts()

    photos = [photo(os.path.join(src, f)) for f, _ in SHOTS]
    overlays = [overlay_for(c, i + 1, len(SHOTS), icon, fonts) for i, (_, c) in enumerate(SHOTS)]

    # Only the photos cross-fade; the caption swaps halfway, so two captions
    # are never drawn over each other.
    frames, durations = [], []
    for i in range(len(SHOTS)):
        j = (i + 1) % len(SHOTS)
        frames.append(compose(photos[i], overlays[i]))
        durations.append(HOLD_MS)
        for k in range(1, FADE_FRAMES + 1):
            t = k / (FADE_FRAMES + 1)
            frames.append(compose(Image.blend(photos[i], photos[j], t), overlays[i if t < 0.5 else j]))
            durations.append(FADE_MS)

    out = [f.quantize(colors=256, method=Image.MEDIANCUT, dither=Image.FLOYDSTEINBERG) for f in frames]
    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    out[0].save(OUT, save_all=True, append_images=out[1:], duration=durations, loop=0)
    print("%d frames, %.0f KB -> %s" % (len(out), os.path.getsize(OUT) / 1024, OUT))


if __name__ == "__main__":
    main()
