"""Render the five armour tiers' player models into media/tiers/, for the loadout GIF.

    python tools/media/render_tiers.py

The models are the ones config/sh_armor.lua gives each tier, read straight out of
Garry's Mod's own VPKs and drawn front-on in their bind pose, which for these
is a T-pose. It reads the .mdl/.vvd/.dx90.vtx meshes and the .vtf textures
itself, so nothing needs installing and GMod never has to start. Flat lighting
only: the result is a cut-out to sit in the flat art, not a beauty render.

Needs numpy and Pillow, and a Garry's Mod install (found from this repo's
location, or pass --gmod <path to the GarrysMod folder>).
"""

import argparse
import os
import re
import struct

import numpy as np
from PIL import Image

REPO = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
OUT = os.path.join(REPO, "media", "tiers")
HEIGHT = 460               # pixels; the GIF draws them at half this, supersampled

# sh_armor.lua; Male_0%d is a random variant in game, 07 here
TIERS = [
    ("none", "models/player/group01/male_07.mdl"),
    ("light", "models/player/group03/male_07.mdl"),
    ("medium", "models/player/barney.mdl"),
    ("heavy", "models/player/police.mdl"),
    ("juggernaut", "models/player/combine_super_soldier.mdl"),
]


# ------------------------------------------------------------------ VPK
class VPK:
    def __init__(self, dir_path):
        self.dir_path = dir_path
        self.base = dir_path[:-len("_dir.vpk")]
        self.files = {}
        with open(dir_path, "rb") as f:
            sig, ver, tree = struct.unpack("<III", f.read(12))
            assert sig == 0x55AA1234, dir_path
            if ver == 2:
                f.read(16)
            self.header = 12 + (16 if ver == 2 else 0)
            self.tree_end = self.header + tree
            def cstr():
                b = bytearray()
                while True:
                    c = f.read(1)
                    if c == b"\0": return b.decode("latin-1")
                    b += c
            while True:
                ext = cstr()
                if not ext: break
                while True:
                    path = cstr()
                    if not path: break
                    while True:
                        name = cstr()
                        if not name: break
                        crc, pre, arc, off, ln, term = struct.unpack("<IHHIIH", f.read(18))
                        preload = f.read(pre)
                        full = (path + "/" if path.strip() else "") + name + "." + ext
                        self.files[full.lower()] = (arc, off, ln, preload)

    def read(self, name):
        arc, off, ln, preload = self.files[name.lower()]
        if ln == 0:
            return preload
        if arc == 0x7FFF:
            with open(self.dir_path, "rb") as f:
                f.seek(self.tree_end + off); return preload + f.read(ln)
        with open("%s_%03d.vpk" % (self.base, arc), "rb") as f:
            f.seek(off); return preload + f.read(ln)

class FS:
    """Search loose files first, then VPKs, like the engine does."""
    def __init__(self, roots, vpks):
        self.roots = roots
        self.vpks = [VPK(v) for v in vpks]
    def read(self, name):
        name = name.replace("\\", "/").lower()
        for r in self.roots:
            p = os.path.join(r, name)
            if os.path.isfile(p):
                return open(p, "rb").read()
        for v in self.vpks:
            if name in v.files:
                return v.read(name)
        raise FileNotFoundError(name)

# --------------------------------------------------------------- models
def cstr(b, off):
    return b[off:b.index(b"\0", off)].decode("latin-1")

def load_mdl(fs, path, body=0, skin=0):
    mdl = fs.read(path)
    base = path[:-4]
    vvd = fs.read(base + ".vvd")
    vtx = fs.read(base + ".dx90.vtx")
    ver = struct.unpack_from("<i", mdl, 4)[0]
    (numtex, texidx, numcd, cdidx, nskinref, nskinfam, skinidx, nbp, bpidx) = struct.unpack_from("<9i", mdl, 204)
    # textures and cd paths
    tex = [cstr(mdl, texidx + i * 64 + struct.unpack_from("<i", mdl, texidx + i * 64)[0]) for i in range(numtex)]
    cds = [cstr(mdl, struct.unpack_from("<i", mdl, cdidx + i * 4)[0]) for i in range(numcd)]
    skins = struct.unpack_from("<%dh" % (nskinref * nskinfam), mdl, skinidx)
    skinrow = skins[skin * nskinref:(skin + 1) * nskinref]
    # vvd
    (vid, vver, vck, nlods) = struct.unpack_from("<4i", vvd, 0)
    lodverts = struct.unpack_from("<8i", vvd, 16)
    nfix, fixstart, vstart, tstart = struct.unpack_from("<4i", vvd, 48)
    nall = (tstart - vstart) // 48 if tstart > vstart else (len(vvd) - vstart) // 48
    raw = np.frombuffer(vvd, dtype=np.uint8, count=nall * 48, offset=vstart).reshape(nall, 48)
    f = raw[:, 16:48].copy().view("<f4").reshape(nall, 8)
    pos_all, nrm_all, uv_all = f[:, 0:3], f[:, 3:6], f[:, 6:8]
    if nfix:
        order = []
        for i in range(nfix):
            lod, src, n = struct.unpack_from("<3i", vvd, fixstart + i * 12)
            if lod >= 0:
                order.extend(range(src, src + n))
        order = np.array(order)
        pos_all, nrm_all, uv_all = pos_all[order], nrm_all[order], uv_all[order]
    # vtx header
    vtx_ver, vcs, mbs, mbt, mbv, ck, vnl, mro, vnbp, vbpo = struct.unpack_from("<iiHHiiiiii", vtx, 0)
    sg_size = 33 if ver >= 49 else 25
    tris = []   # (i0,i1,i2, material)
    for bp in range(nbp):
        b_off = bpidx + bp * 16
        nmodels, mbase, midx = struct.unpack_from("<3i", mdl, b_off + 4)
        pick = body // mbase % nmodels if nmodels else 0
        m_off = b_off + midx + pick * 148
        nmeshes, meshidx, nverts, vertidx = struct.unpack_from("<4i", mdl, m_off + 72)
        # vtx side
        vb = vbpo + bp * 8
        vnm, vmo = struct.unpack_from("<2i", vtx, vb)
        vm = vb + vmo + pick * 8
        nl, lo = struct.unpack_from("<2i", vtx, vm)
        vl = vm + lo
        nme, meo = struct.unpack_from("<2i", vtx, vl)
        for mi in range(nmeshes):
            ms = m_off + meshidx + mi * 116
            material, _mi, mnv, mvoff = struct.unpack_from("<4i", mdl, ms)
            vme = vl + meo + mi * 9
            nsg, sgo = struct.unpack_from("<2i", vtx, vme)
            for g in range(nsg):
                sg = vme + sgo + g * sg_size
                nv, vo, ni, io = struct.unpack_from("<4i", vtx, sg)
                verts = [struct.unpack_from("<H", vtx, sg + vo + k * 9 + 4)[0] for k in range(nv)]
                idx = struct.unpack_from("<%dH" % ni, vtx, sg + io)
                off = vertidx // 48 + mvoff
                for k in range(0, ni - 2, 3):
                    tris.append((verts[idx[k]] + off, verts[idx[k + 1]] + off, verts[idx[k + 2]] + off,
                                 skinrow[material] if material < len(skinrow) else material))
    tris = np.array(tris, dtype=np.int64)
    return dict(pos=pos_all, nrm=nrm_all, uv=uv_all, tris=tris, textures=tex, cdtextures=cds)

# ------------------------------------------------------ textures, render
def dxt_colors(c0, c1, alpha_mode):
    def rgb(c):
        r = ((c >> 11) & 31) * 255 // 31; g = ((c >> 5) & 63) * 255 // 63; b = (c & 31) * 255 // 31
        return np.stack([r, g, b], -1).astype(np.int32)
    a, b = rgb(c0), rgb(c1)
    four = (c0 > c1) | ~alpha_mode
    c2 = np.where(four[:, None], (2 * a + b) // 3, (a + b) // 2)
    c3 = np.where(four[:, None], (a + 2 * b) // 3, 0)
    return np.stack([a, b, c2, c3], 1)  # n,4,3

def decode_dxt(data, w, h, fmt):
    bw, bh = max(1, w // 4), max(1, h // 4)
    n = bw * bh
    bs = 8 if fmt == "dxt1" else 16
    blk = np.frombuffer(data, np.uint8, n * bs).reshape(n, bs)
    cb = blk[:, -8:]
    c0 = cb[:, 0].astype(np.int32) | (cb[:, 1].astype(np.int32) << 8)
    c1 = cb[:, 2].astype(np.int32) | (cb[:, 3].astype(np.int32) << 8)
    pal = dxt_colors(c0, c1, np.full(n, fmt == "dxt1"))
    bits = cb[:, 4:8].copy().view("<u4")[:, 0]
    idx = np.stack([(bits >> (2 * i)) & 3 for i in range(16)], 1)
    rgb = np.take_along_axis(pal, idx[:, :, None].repeat(3, 2), 1)
    alpha = np.full((n, 16), 255, np.int32)
    if fmt == "dxt1":
        alpha = np.where((c0 <= c1)[:, None] & (idx == 3), 0, 255)
    elif fmt == "dxt5":
        a0 = blk[:, 0].astype(np.int32); a1 = blk[:, 1].astype(np.int32)
        ab = np.zeros(n, np.uint64)
        for i in range(6):
            ab |= blk[:, 2 + i].astype(np.uint64) << np.uint64(8 * i)
        ai = np.stack([((ab >> np.uint64(3 * i)) & np.uint64(7)).astype(np.int32) for i in range(16)], 1)
        tbl = np.zeros((n, 8), np.int32); tbl[:, 0] = a0; tbl[:, 1] = a1
        big = a0 > a1
        for i in range(2, 8):
            tbl[:, i] = np.where(big, ((8 - i) * a0 + (i - 1) * a1) // 7, 0)
        for i in range(2, 6):
            tbl[:, i] = np.where(big, tbl[:, i], ((6 - i) * a0 + (i - 1) * a1) // 5)
        tbl[:, 6] = np.where(big, tbl[:, 6], 0); tbl[:, 7] = np.where(big, tbl[:, 7], 255)
        alpha = np.take_along_axis(tbl, ai, 1)
    elif fmt == "dxt3":
        ab = blk[:, :8]
        alpha = np.stack([((ab[:, i // 2] >> (4 * (i % 2))) & 15) * 17 for i in range(16)], 1).astype(np.int32)
    px = np.concatenate([rgb, alpha[:, :, None]], 2).reshape(bh, bw, 4, 4, 4).transpose(0, 2, 1, 3, 4)
    return px.reshape(bh * 4, bw * 4, 4)[:h, :w].astype(np.uint8)

FMT = {13: ("dxt1", 0.5), 14: ("dxt3", 1), 15: ("dxt5", 1), 0: ("rgba", 4), 2: ("rgb", 3), 3: ("bgr", 3),
       12: ("bgra", 4), 1: ("abgr", 4)}

def load_vtf(b):
    hs = struct.unpack_from("<I", b, 12)[0]
    w, h = struct.unpack_from("<HH", b, 16)
    frames = struct.unpack_from("<H", b, 24)[0]
    fmt = struct.unpack_from("<i", b, 52)[0]
    name, bpp = FMT[fmt]
    size = max(4, w) * max(4, h) * bpp if name.startswith("dxt") else w * h * bpp
    size = int(size)
    start = len(b) - frames * size
    data = b[start:start + size]
    if name.startswith("dxt"):
        return decode_dxt(data, w, h, name)
    a = np.frombuffer(data, np.uint8).reshape(h, w, len(name))
    order = {"rgba": [0, 1, 2, 3], "rgb": [0, 1, 2], "bgr": [2, 1, 0], "bgra": [2, 1, 0, 3], "abgr": [3, 2, 1, 0]}[name]
    a = a[:, :, order]
    if a.shape[2] == 3:
        a = np.concatenate([a, np.full((h, w, 1), 255, np.uint8)], 2)
    return a

def find_texture(fs, model, i):
    name = model["textures"][i]
    for cd in model["cdtextures"]:
        p = ("materials/" + cd.replace("\\", "/") + name + ".vmt").replace("//", "/")
        try:
            vmt = fs.read(p).decode("latin-1")
        except FileNotFoundError:
            continue
        m = re.search(r'"?\$basetexture"?\s+"?([^"\s]+)', vmt, re.I)
        if not m:
            return None
        try:
            return load_vtf(fs.read("materials/" + m.group(1).replace("\\", "/") + ".vtf"))
        except FileNotFoundError:
            return None
    return None

def render(fs, path, height_px, light=(0.35, 0.8, 0.5)):
    """Front view, orthographic, half-Lambert lit; the model faces -y in its bind pose."""
    m = load_mdl(fs, path)
    texs = [find_texture(fs, m, i) for i in range(len(m["textures"]))]
    pos, nrm, uv, tris = m["pos"].copy(), m["nrm"].copy(), m["uv"], m["tris"]
    pos[:, :2] *= -1           # turn it round to face the camera
    nrm[:, :2] *= -1
    lo, hi = pos.min(0), pos.max(0)
    scale = height_px / (hi[2] - lo[2])
    pad = 6
    W = int((hi[0] - lo[0]) * scale) + 2 * pad
    H = height_px + 2 * pad
    sx = (pos[:, 0] - lo[0]) * scale + pad
    sy = (hi[2] - pos[:, 2]) * scale + pad
    depth = pos[:, 1]
    zbuf = np.full((H, W), -1e9)
    img = np.zeros((H, W, 4), np.float64)
    L = np.array(light); L = L / np.linalg.norm(L)
    for t in tris:
        i0, i1, i2, mat = t
        tex = texs[mat] if mat < len(texs) else None
        xs, ys = sx[[i0, i1, i2]], sy[[i0, i1, i2]]
        x0, x1 = int(max(0, np.floor(xs.min()))), int(min(W - 1, np.ceil(xs.max())))
        y0, y1 = int(max(0, np.floor(ys.min()))), int(min(H - 1, np.ceil(ys.max())))
        if x1 < x0 or y1 < y0:
            continue
        gx, gy = np.meshgrid(np.arange(x0, x1 + 1) + 0.5, np.arange(y0, y1 + 1) + 0.5)
        d = (ys[1] - ys[2]) * (xs[0] - xs[2]) + (xs[2] - xs[1]) * (ys[0] - ys[2])
        if abs(d) < 1e-9:
            continue
        w0 = ((ys[1] - ys[2]) * (gx - xs[2]) + (xs[2] - xs[1]) * (gy - ys[2])) / d
        w1 = ((ys[2] - ys[0]) * (gx - xs[2]) + (xs[0] - xs[2]) * (gy - ys[2])) / d
        w2 = 1 - w0 - w1
        inside = (w0 >= -1e-6) & (w1 >= -1e-6) & (w2 >= -1e-6)
        if not inside.any():
            continue
        z = w0 * depth[i0] + w1 * depth[i1] + w2 * depth[i2]
        zb = zbuf[y0:y1 + 1, x0:x1 + 1]
        hit = inside & (z > zb)
        if not hit.any():
            continue
        n = w0[..., None] * nrm[i0] + w1[..., None] * nrm[i1] + w2[..., None] * nrm[i2]
        n /= np.linalg.norm(n, axis=-1, keepdims=True) + 1e-9
        ln = n @ (L * np.array([1, -1, 1]))
        shade = 0.6 + 0.5 * np.clip(ln * 0.5 + 0.5, 0, 1)
        if tex is not None:
            u = w0 * uv[i0, 0] + w1 * uv[i1, 0] + w2 * uv[i2, 0]
            v = w0 * uv[i0, 1] + w1 * uv[i1, 1] + w2 * uv[i2, 1]
            th, tw = tex.shape[:2]
            tx = (np.mod(u, 1) * tw).astype(int).clip(0, tw - 1)
            ty = (np.mod(v, 1) * th).astype(int).clip(0, th - 1)
            col = tex[ty, tx, :3].astype(np.float64)
        else:
            col = np.full(hit.shape + (3,), 200.0)
        reg = img[y0:y1 + 1, x0:x1 + 1]
        reg[hit, :3] = (col * shade[..., None])[hit]
        reg[hit, 3] = 255
        zb[hit] = z[hit]
    return Image.fromarray(img.clip(0, 255).astype(np.uint8), "RGBA")

def main():
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--gmod", default=os.path.normpath(os.path.join(REPO, "..", "..", "..")))
    args = ap.parse_args()
    g = os.path.join(args.gmod, "garrysmod")
    se = os.path.join(args.gmod, "sourceengine")
    fs = FS([g], [os.path.join(g, "garrysmod_dir.vpk"), os.path.join(se, "hl2_misc_dir.vpk"),
                  os.path.join(se, "hl2_textures_dir.vpk")])
    os.makedirs(OUT, exist_ok=True)
    for name, path in TIERS:
        im = render(fs, path, HEIGHT)
        im.save(os.path.join(OUT, name + ".png"), optimize=True)
        print("%s: %s %dx%d" % (name, path, im.width, im.height))


if __name__ == "__main__":
    main()
