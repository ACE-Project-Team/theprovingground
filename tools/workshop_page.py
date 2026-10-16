"""Set a Workshop item's page: animated preview, description, gallery, required items.

    python tools/workshop_page.py tpg|tpg_e2sf [--dry-run]

gmpublish uploads the .gma and a 512x512 JPG icon, and nothing else. This
does the rest through the Steamworks API in Garry's Mod's own
steam_api64.dll, so Steam has to be running and logged in to the account
that owns the item. Visibility is left alone: a hidden item stays hidden.

Each run replaces the gallery rather than adding to it, so it can be rerun
after any change. The gallery JPGs come from
`python tools/media/make_gameplay.py <screenshots> --stills build/workshop`,
the previews from `python tools/media/make_workshop.py`. The showcase GIFs are
over the ~1 MB Steam takes for a gallery file, so they only appear in the
description, from
`python tools/media/make_showcase.py`.

Standard library only.
"""

import argparse
import ctypes
import os
import sys
import time

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
BIN = os.path.normpath(os.path.join(REPO, "..", "..", "..", "bin", "win64"))
APP_ID = 4000

ACE = 3333669763
CFW = 3154971187

ITEMS = {
    "tpg": {
        "id": 3820591474,
        "preview": "media/workshop/tpg_thumb.gif",
        "description": "workshop/tpg.bbcode",
        "gallery": ["build/workshop/gameplay_%02d.jpg" % i for i in range(1, 8)],
        "requires": [ACE, CFW, 3820591473],
    },
    "tpg_e2sf": {
        "id": 3820591473,
        "preview": "media/workshop/tpg_e2sf_thumb.gif",
        "description": "workshop/tpg_e2sf.bbcode",
        "gallery": ["media/e2sf.gif"],
        "requires": [],
    },
}

PREVIEW_LIMIT = 1024 * 1024
DESCRIPTION_LIMIT = 8000

# Callback ids (k_iSteamUGCCallbacks = 3400) and their structs, packed to 8 as
# Steam's are on Windows.
SUBMIT_RESULT = 3404
QUERY_COMPLETED = 3401
DEPENDENCY_RESULT = 3412


class SubmitItemUpdateResult(ctypes.Structure):
    _fields_ = [("result", ctypes.c_int32), ("needs_legal", ctypes.c_bool),
                ("file_id", ctypes.c_uint64)]


class SteamUGCQueryCompleted(ctypes.Structure):
    _fields_ = [("handle", ctypes.c_uint64), ("result", ctypes.c_int32),
                ("num_results", ctypes.c_uint32), ("total", ctypes.c_uint32),
                ("cached", ctypes.c_bool), ("next_cursor", ctypes.c_char * 256)]


class AddUGCDependencyResult(ctypes.Structure):
    _fields_ = [("result", ctypes.c_int32), ("parent", ctypes.c_uint64),
                ("child", ctypes.c_uint64)]


class Steam:
    def __init__(self):
        os.environ["SteamAppId"] = str(APP_ID)
        os.environ["SteamGameId"] = str(APP_ID)
        os.add_dll_directory(BIN)
        api = ctypes.CDLL(os.path.join(BIN, "steam_api64.dll"))
        self.api = api
        P, U64, U32, B, S = ctypes.c_void_p, ctypes.c_uint64, ctypes.c_uint32, ctypes.c_bool, ctypes.c_char_p
        sig = {
            "SteamAPI_InitFlat": (ctypes.c_int, [ctypes.c_char_p]),
            "SteamAPI_Shutdown": (None, []),
            "SteamAPI_RunCallbacks": (None, []),
            "SteamAPI_SteamUGC_v021": (P, []),
            "SteamAPI_SteamUtils_v010": (P, []),
            "SteamAPI_ISteamUGC_StartItemUpdate": (U64, [P, U32, U64]),
            "SteamAPI_ISteamUGC_SetItemDescription": (B, [P, U64, S]),
            "SteamAPI_ISteamUGC_SetItemPreview": (B, [P, U64, S]),
            "SteamAPI_ISteamUGC_AddItemPreviewFile": (B, [P, U64, S, ctypes.c_int]),
            "SteamAPI_ISteamUGC_RemoveItemPreview": (B, [P, U64, U32]),
            "SteamAPI_ISteamUGC_SubmitItemUpdate": (U64, [P, U64, S]),
            "SteamAPI_ISteamUGC_AddDependency": (U64, [P, U64, U64]),
            "SteamAPI_ISteamUGC_CreateQueryUGCDetailsRequest": (U64, [P, ctypes.POINTER(U64), U32]),
            "SteamAPI_ISteamUGC_SetReturnAdditionalPreviews": (B, [P, U64, B]),
            "SteamAPI_ISteamUGC_SendQueryUGCRequest": (U64, [P, U64]),
            "SteamAPI_ISteamUGC_GetQueryUGCNumAdditionalPreviews": (U32, [P, U64, U32]),
            "SteamAPI_ISteamUGC_ReleaseQueryUGCRequest": (B, [P, U64]),
            "SteamAPI_ISteamUtils_IsAPICallCompleted": (B, [P, U64, ctypes.POINTER(B)]),
            "SteamAPI_ISteamUtils_GetAPICallResult": (B, [P, U64, P, ctypes.c_int, ctypes.c_int,
                                                          ctypes.POINTER(B)]),
        }
        for name, (res, args) in sig.items():
            fn = getattr(api, name)
            fn.restype, fn.argtypes = res, args

        err = ctypes.create_string_buffer(1024)
        if api.SteamAPI_InitFlat(err) != 0:
            sys.exit("Steam didn't start the API: %s (is Steam running and logged in?)"
                     % err.value.decode(errors="replace"))
        self.ugc = api.SteamAPI_SteamUGC_v021()
        self.utils = api.SteamAPI_SteamUtils_v010()

    def call(self, name, *args):
        return getattr(self.api, "SteamAPI_ISteamUGC_" + name)(self.ugc, *args)

    def wait(self, handle, struct, callback_id, what):
        failed = ctypes.c_bool(False)
        while not self.api.SteamAPI_ISteamUtils_IsAPICallCompleted(self.utils, handle, ctypes.byref(failed)):
            self.api.SteamAPI_RunCallbacks()
            time.sleep(0.1)
        out = struct()
        ok = self.api.SteamAPI_ISteamUtils_GetAPICallResult(
            self.utils, handle, ctypes.byref(out), ctypes.sizeof(out), callback_id, ctypes.byref(failed))
        if not ok or failed.value:
            sys.exit("%s: Steam call failed" % what)
        return out

    def submit(self, update, note, what, fatal=True):
        res = self.wait(self.call("SubmitItemUpdate", update, note.encode()),
                        SubmitItemUpdateResult, SUBMIT_RESULT, what)
        if res.needs_legal:
            sys.exit("%s: accept the Workshop legal agreement on the item page first" % what)
        if res.result != 1:
            # 25 is LimitExceeded: the file is over Steam's size cap for that slot.
            msg = "%s: Steam returned EResult %d" % (what, res.result)
            if fatal:
                sys.exit(msg)
            print(msg + ", skipped")
            return
        print("%s: done" % what)

    def gallery_count(self, file_id):
        ids = (ctypes.c_uint64 * 1)(file_id)
        query = self.call("CreateQueryUGCDetailsRequest", ids, 1)
        self.call("SetReturnAdditionalPreviews", query, True)
        res = self.wait(self.call("SendQueryUGCRequest", query), SteamUGCQueryCompleted,
                        QUERY_COMPLETED, "query")
        n = self.call("GetQueryUGCNumAdditionalPreviews", query, 0) if res.num_results else 0
        self.call("ReleaseQueryUGCRequest", query)
        return n


def check(item):
    for key in ("preview", "description"):
        if not os.path.isfile(os.path.join(REPO, item[key])):
            sys.exit("missing %s; see the header of this script" % item[key])
    for path in item["gallery"]:
        if not os.path.isfile(os.path.join(REPO, path)):
            sys.exit("missing %s; see the header of this script" % path)
    if os.path.getsize(os.path.join(REPO, item["preview"])) > PREVIEW_LIMIT:
        sys.exit("%s is over Steam's 1 MB preview limit" % item["preview"])
    with open(os.path.join(REPO, item["description"]), encoding="utf-8") as f:
        text = f.read().strip()
    if len(text) > DESCRIPTION_LIMIT:
        sys.exit("%s is %d characters; Steam takes %d" % (item["description"], len(text), DESCRIPTION_LIMIT))
    return text


def main():
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("item", choices=sorted(ITEMS))
    ap.add_argument("--dry-run", action="store_true", help="check the files, don't touch Steam")
    args = ap.parse_args()
    item = ITEMS[args.item]
    text = check(item)
    fid = item["id"]
    print("item %d: preview %s, %d-character description, %d gallery file(s), %d required item(s)"
          % (fid, item["preview"], len(text), len(item["gallery"]), len(item["requires"])))
    if args.dry_run:
        return

    steam = Steam()
    try:
        # Preview and description go together; each gallery file is its own
        # update, so one rejected image is skipped without taking the rest down.
        update = steam.call("StartItemUpdate", APP_ID, fid)
        steam.call("SetItemPreview", update, os.path.join(REPO, item["preview"]).encode())
        steam.call("SetItemDescription", update, text.encode("utf-8"))
        steam.submit(update, "", "preview and description")

        old = steam.gallery_count(fid)
        if old:
            update = steam.call("StartItemUpdate", APP_ID, fid)
            for i in reversed(range(old)):
                steam.call("RemoveItemPreview", update, i)
            steam.submit(update, "", "removed %d old gallery file(s)" % old)
        for path in item["gallery"]:
            update = steam.call("StartItemUpdate", APP_ID, fid)
            steam.call("AddItemPreviewFile", update, os.path.join(REPO, path).encode(), 0)
            steam.submit(update, "", "gallery " + path, fatal=False)

        # Adding a dependency that is already there is harmless.
        for child in item["requires"]:
            res = steam.wait(steam.call("AddDependency", fid, child), AddUGCDependencyResult,
                             DEPENDENCY_RESULT, "required item %d" % child)
            print("required item %d: %s" % (child, "done" if res.result == 1 else "EResult %d" % res.result))
    finally:
        steam.api.SteamAPI_Shutdown()
    print("https://steamcommunity.com/sharedfiles/filedetails/?id=%d" % fid)


if __name__ == "__main__":
    main()
