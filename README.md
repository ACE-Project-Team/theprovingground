<img src="logo.svg" alt="The Proving Ground" width="640">

# The Proving Ground
A gamemode heavily inspired by the Baiknor combined arms gamemode, but for ACE

To install:
Garrysmod/garrysmod/gamemodes

Requires ACE (Armored Combat Extended) installed under `garrysmod/addons/`. On
startup TPG checks for ACE/CFW and prints a warning to the server console if
either is missing (see `TPG.Config.ValidateACE()` in `gamemode/config/sh_config.lua`).

## E2 and Starfall functions

The `tpg*` chip functions (team roster, loadouts, teammate checks) are a separate addon,
[tpg_e2sf](https://github.com/ACE-Project-Team/tpg_e2sf), so they also work in plain sandbox.
Its README lists every function.

GMod only loads Wire and Starfall extensions from a real addon under `garrysmod/addons/`, never
from inside a gamemode, so install it there like any other addon. On startup TPG prints a
warning to the server console if it isn't (`TPG.Config.ValidateE2SFSandbox()` in
`gamemode/config/sh_config.lua`).

For development this repo carries it as a submodule at `addons/tpg_e2sf_sandbox`. Clone with
`git clone --recurse-submodules`, or run `git submodule update --init` in an existing clone,
then link the folder into `garrysmod/addons/` once per machine so the copy you edit is the one
the game loads:

```powershell
New-Item -ItemType Junction -Path "<garrysmod>\addons\tpg_e2sf_sandbox" -Target "<garrysmod>\gamemodes\theprovingground\addons\tpg_e2sf_sandbox"
```

```bash
ln -s "<garrysmod>/gamemodes/theprovingground/addons/tpg_e2sf_sandbox" "<garrysmod>/addons/tpg_e2sf_sandbox"
```

The addon is its own repository: commit and push changes to it there, then commit the updated
submodule here. Anything it reads from TPG is pinned by `tests/test_e2sf_contract.lua`.

WIP
