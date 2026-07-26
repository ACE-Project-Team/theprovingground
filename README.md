# The Proving Ground
A gamemode heavily inspired by the Baiknor combined arms gamemode, but for ACE

To install:
Garrysmod/garrysmod/gamemodes

Requires ACE (Armored Combat Extended) installed under `garrysmod/addons/`. On
startup TPG checks for ACE/CFW and prints a warning to the server console if
either is missing (see `TPG.Config.ValidateACE()` in `gamemode/config/sh_config.lua`).

## E2/SF sandbox testing addon

`standalone_addon/tpg_e2sf_sandbox/` holds the Wire Expression2 and Starfall
`tpg*` chip functions (team roster, loadout, teammate checks, etc). Wire/SF
autoload these from wherever they're currently mounted, and a gamemode's own
`lua/` folder is only mounted while that gamemode is the active one -- so as
shipped, those functions only work while a TPG match is actually running.

To make them usable in plain sandbox too (for chip testing outside a live
match), this folder needs to also exist as a real top-level addon under
`garrysmod/addons/`, since real addons mount regardless of active gamemode.
Since git only tracks the repo at its gamemode path, that means creating a
directory junction (Windows) or symlink (Linux) that makes the same files
appear at both locations. This is filesystem-level and NOT tracked by git --
it has to be (re)created by hand on every machine/server this repo is deployed
to, including after a fresh clone.

Windows (run once per machine, adjust drive/paths as needed):
```powershell
New-Item -ItemType Junction -Path "<garrysmod>\addons\tpg_e2sf_sandbox" -Target "<garrysmod>\gamemodes\theprovingground\standalone_addon\tpg_e2sf_sandbox"
```

Linux:
```bash
ln -s "<garrysmod>/gamemodes/theprovingground/standalone_addon/tpg_e2sf_sandbox" "<garrysmod>/addons/tpg_e2sf_sandbox"
```

On startup TPG checks whether this addon is mounted and prints a warning to
the server console if it isn't (see `TPG.Config.ValidateE2SFSandbox()` in
`gamemode/config/sh_config.lua`). Once mounted, `tpg_test_team <green|red|none>`
(console command, added by the stub) fakes your team in plain sandbox so a
chip can be pointed at `tpgTeamCount()` / `tpg.getRoster()` etc. and see it
return real data. The stub always steps aside the instant a real TPG match is
running (`TPG.State` exists), so it never interferes with an actual round.

WIP
