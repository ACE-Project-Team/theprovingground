"""Pack the gamemode into a Workshop .gma.

    python tools/build_gma.py [--gmad PATH] [--out FILE]

gmad can't pack this repo as it stands. A gamemode inside a .gma has to sit
under gamemodes/theprovingground/, and gmad's whitelist rejects everything
that doesn't, so pointing it at the repo root fails on the first file. This
stages the files that ship into that layout in a temporary folder, copies
addon.json next to them and runs gmad there.

Only files git tracks are shipped, so local leftovers (doc/, old folders)
never end up on the Workshop. Fonts go to resource/fonts/ at the top of the
.gma, where resource.AddFile in gamemode/init.lua looks for them; gmad
refuses them under the gamemode folder anyway.

Standard library only. gmad is looked for in the Garry's Mod install this
repo is cloned into (garrysmod/gamemodes/theprovingground); pass --gmad if
yours is elsewhere.
"""

import argparse
import os
import shutil
import subprocess
import sys
import tempfile

NAME = "theprovingground"
REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

# Tracked paths that ship, and where they go inside the .gma. Prefixes end in
# "/"; anything not matched here stays out.
SHIP = [
    ("gamemode/", "gamemodes/" + NAME + "/gamemode/"),
    ("entities/", "gamemodes/" + NAME + "/entities/"),
    ("resource/fonts/", "resource/fonts/"),
    ("icon24.png", "gamemodes/" + NAME + "/icon24.png"),
    ("logo.png", "gamemodes/" + NAME + "/logo.png"),
]


def tracked_files():
    out = subprocess.run(["git", "ls-files", "-z"], cwd=REPO, check=True,
                         capture_output=True).stdout
    return [p for p in out.decode("utf-8").split("\0") if p]


def destination(path):
    # The descriptor has to be lower-case to match the folder name; the
    # tracked file isn't on every checkout, so match it case-insensitively.
    if path.lower() == NAME + ".txt":
        return "gamemodes/" + NAME + "/" + NAME + ".txt"
    for src, dst in SHIP:
        if path == src or (src.endswith("/") and path.startswith(src)):
            return dst + path[len(src):]
    return None


def default_gmad():
    bindir = os.path.normpath(os.path.join(REPO, "..", "..", "..", "bin"))
    for exe in ("gmad.exe", "gmad_linux", "gmad"):
        candidate = os.path.join(bindir, exe)
        if os.path.isfile(candidate):
            return candidate
    return None


def main():
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--gmad", default=default_gmad(),
                        help="path to gmad (default: the GMod install around this repo)")
    parser.add_argument("--out", default=os.path.join(REPO, "build", NAME + ".gma"),
                        help="output .gma (default: build/%s.gma)" % NAME)
    args = parser.parse_args()

    if not args.gmad or not os.path.isfile(args.gmad):
        sys.exit("gmad not found; pass --gmad PATH")

    shipped = [(p, destination(p)) for p in tracked_files()]
    shipped = [(p, d) for p, d in shipped if d]
    if not any(d.endswith("/" + NAME + ".txt") for _, d in shipped):
        sys.exit(NAME + ".txt is not tracked; nothing to build")

    with tempfile.TemporaryDirectory() as stage:
        for src, dst in shipped:
            target = os.path.join(stage, *dst.split("/"))
            os.makedirs(os.path.dirname(target), exist_ok=True)
            shutil.copyfile(os.path.join(REPO, *src.split("/")), target)
        shutil.copyfile(os.path.join(REPO, "addon.json"), os.path.join(stage, "addon.json"))

        os.makedirs(os.path.dirname(os.path.abspath(args.out)), exist_ok=True)
        result = subprocess.run([args.gmad, "create", "-folder", stage,
                                 "-out", os.path.abspath(args.out)],
                                capture_output=True, text=True)
        if result.returncode != 0:
            sys.stdout.write(result.stdout)
            sys.stderr.write(result.stderr)
            sys.exit("gmad failed")

    print("%d files -> %s" % (len(shipped), os.path.abspath(args.out)))


if __name__ == "__main__":
    main()
