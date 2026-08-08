# How The Proving Ground is put together

This is the page to read first. It covers what loads when, what each folder is
responsible for, and how to add a game type — which is the change most people
turn up here wanting to make.

Everything hangs off one global table, `TPG`. There are no Lua modules and
nothing is `require`d; each file adds its own sub-table (`TPG.Rounds`,
`TPG.Stats`, `TPG.Maps`, …) and the load order in `gamemode/init.lua` and
`gamemode/shared.lua` decides what exists by the time your file runs.

## Realms

Garry's Mod runs the same repository in two places, and the filename prefix
says which:

| prefix | runs on | example |
|---|---|---|
| `sh_` | both server and client | `config/sh_gear.lua` |
| `sv_` | server only | `systems/sv_stats.lua` |
| `cl_` | client only | `ui/cl_hud.lua` |

A `sv_` file is never sent to clients. A `sh_` or `cl_` file has to be listed
in an `AddCSLuaFile` call in `gamemode/init.lua` or the client never receives
it — adding a file and forgetting that line is the single most common way to
end up with something that works in singleplayer and not on a server.

## Load order

`gamemode/init.lua` is the server entry point. It does three things in order:

1. `AddCSLuaFile`s everything the client needs.
2. `include`s `shared.lua`, which pulls in every `config/` file, then
   `core/sh_utils.lua`, `objectives/sh_controlpoint.lua` and `maps/_loader.lua`.
   `shared.lua` also declares the constants — `TEAM_GREEN`, `TEAM_RED`,
   `GAMEMODE_CP` and friends — so anything that mentions them must load after it.
3. `include`s the server files, roughly core → player → systems → objectives →
   voting.

`GM:Initialize` then waits three seconds (so addons have finished mounting)
before validating that ACE is present, loading the map config, and opening the
wait-for-players window that leads into the first round.

## What lives where

| folder | holds |
|---|---|
| `config/` | Data, almost no behaviour: teams, armor, weapons, prices, ranks, colours and fonts, and the game type table. Shared, so the menus can read the same numbers the server enforces. |
| `core/` | The round loop, the authoritative game state, networking, the prep window, console commands, ULX compatibility. |
| `player/` | Everything that happens to a player: spawning, loadout, team assignment, safezone protection, AFK. |
| `systems/` | Self-contained features that the round loop doesn't need to know about: stats and rating, the per-player economy, prop tracking, ACE integration, underdog assistance, commendations, duplicator rules, vehicles. |
| `objectives/` | Control point capture logic and the CTF flag round. |
| `maps/` | Per-map spawns, budgets and objective positions, plus the admin-placed points saved under `data/tpg/points/`. |
| `ui/` | The HUD and every menu. Client only. |
| `voting/` | Rock the vote, scramble votes, end-of-map map votes. |
| `entities/` | The control point, the flag, the safezone marker, the point tool, the disposable AT weapon. |
| `addons/tpg_e2sf_sandbox/` | Wire Expression 2 and Starfall bindings. See the README for why this needs a junction. |

## The round loop

    GM:Initialize
      └─ TPG.Rounds.BeginInitialWait      wait for enough players
           └─ TPG.Rounds.Setup            per round, from here on
                ├─ TPG.Maps.Load                    map config + custom points
                ├─ TPG.SelectRandomGameType         which mode this round is
                ├─ game.CleanUpMap / State.ResetRound
                ├─ TPG.Objectives.SpawnAll          control points for this mode
                ├─ TPG.Objectives.SpawnSafezones
                ├─ TPG.CTF.SpawnFlags               no-op unless this is CTF
                └─ TPG.Prep.Begin                   build window, teams confined

Once the round is live, a `Think` hook in `core/sv_rounds.lua` ticks
`TPG.Objectives.ProcessScoring` and then `TPG.Rounds.CheckWinCondition` on a
fixed interval.

Both teams start with a pool of tickets in `TPG.State.scores`. Scoring drains
the *losing* side's pool rather than adding to the winner's, and a round ends
when either pool hits zero — so every mode is expressed as "what makes the
other team bleed". Control points drain by ownership, deathmatch drains by
deaths, capture the flag drains by deliveries.

## Adding a game type

Say you want a mode called Assault. Five places, in order:

**1. A constant** — `gamemode/shared.lua`, next to the others:

```lua
GAMEMODE_ASSAULT = 6
```

**2. A definition** — `gamemode/config/sh_gametypes.lua`, in `TPG.GameTypes`:

```lua
[GAMEMODE_ASSAULT] = {
    id              = GAMEMODE_ASSAULT,
    name            = "Assault",
    shortName       = "Assault",     -- what the HUD pill shows
    description     = "Push the line",
    useDeathTickets = false,         -- true makes deaths the drain, as in DM
    defaultCapMul   = 0.05,          -- ticket drain per unit of point ownership
},
```

**3. A slice of the roll** — the `WEIGHTS` table in the same file. Weights are
independent and normalised at roll time, so adding one only dilutes the others
in proportion; you do not have to take a band off anything, and changing one
number cannot silently starve a mode the way the old cumulative thresholds did.

If your mode can't run on every map, add an entry to `SUPPORTED` alongside it —
a function returning whether this map can host it. A mode that answers no is
dropped from the draw entirely and its weight is shared out among the rest;
`GAMEMODE_CTF` (needs a flag point) and `GAMEMODE_RUSH` (needs control points)
both do this.

**4. Objectives per map, if your mode needs its own** — `gamemode/maps/_loader.lua`.
Every map config is a table keyed by game type, so add a `[GAMEMODE_ASSAULT]`
block to `TPG.Maps.Default` and to each map in `TPG.Maps.Configs` that should
host it:

```lua
[GAMEMODE_ASSAULT] = {
    capMultiplier = 0.05,
    objectives = {
        { pos = Vector(0, 0, 100), name = "The Line" },
    },
},
```

A map with no block for your mode gets no objectives, which for most modes
means a round that can never end — so either cover the maps or gate the roll.

You can also skip this step by borrowing a list another mode already has, which
is what `TPG.Rush.BuildStages` does with `[GAMEMODE_CP]`: it costs you the
ability to place points for your mode specifically, and buys support on every
map already configured with zero authoring.

**5. Scoring, if the drain isn't enough.** If the mode is "hold these points
and the other team bleeds", you are already finished: `ProcessScoring` reads
control point ownership and `capMultiplier` and does the rest. If it needs its
own rules, add a file under `objectives/`, `include` it from `init.lua`, and
have `TPG.Rounds.Setup` call into it the way it calls `TPG.CTF.SpawnFlags` —
that function returns immediately unless the round is CTF, which is the pattern
to copy. If the mode also needs a clock, hang it off the fixed-step loop in the
`TPG_RoundThink` hook next to `TPG.Rush.Think`, rather than a timer of its own:
that step is what keeps the scoring tickrate-independent.

Nothing else has to change. The HUD reads the mode's name and description
straight off `TPG.GetGameType`, and the map vote screen reads budgets off the
map config.

## Where a player's data goes

Two stores, on purpose:

- **PData** (`TPG.Util.GetPData` / `SetPData`) — the player's own choices:
  loadout, armor, medals. Keyed by SteamID in the server's database, prefixed
  `TPG_` so nothing collides with another addon.
- **`data/tpg/stats.json`** (`TPG.Stats`) — the lifetime record and rating. A
  file rather than PData because a leaderboard has to see players who aren't
  connected. See the comments at the top of `systems/sv_stats.lua`; that file
  has been broken twice in ways worth reading about before touching it.

## Running the tests

```bash
lua tests/run.lua
```

Any Lua 5.1 will do; nothing needs installing. These load the **shared** files
against a stub of the GMod API and assert on the config tables, the lookups
over them, and the pure functions — the part that is honest to test outside the
game. The server files are hook and net plumbing whose behaviour is the engine
calling them in an order the harness does not reproduce, so they are out of
scope here; boot a real server for those. `tests/README.md` covers what a test
in this repo is for, and where the stub could drift.

Adding a shared config or a lookup means adding a case. Cross-file invariants
are the highest-value ones: a `subCategory` override naming a tab that does not
exist, or a gear price for an armor id with no tier, breaks nothing loudly — it
just quietly stops working.

## Generating the reference

```bash
ldoc .
```

Output goes to `doc/`, which is not tracked. Every documented function carries
a **Realm** line saying where it exists, because calling a server-only function
from the client just produces a nil index error with no hint as to why.
