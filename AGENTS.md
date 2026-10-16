# AGENTS.md

For AI agents working on The Proving Ground (GLua / Garry's Mod gamemode built on ACE). Read the
linked docs before changing code.

**Must read:**
- [ARCHITECTURE.md](ARCHITECTURE.md) — load order, realms, what each folder owns
- Contributor rules: [CONTRIBUTING.md](CONTRIBUTING.md) — applies to agent-assisted work too
- ACE style guide: https://acegmod.com/wiki/general-coding-and-style-guidelines
- CFC GLua style guidelines: https://github.com/CFC-Servers/cfc_glua_style_guidelines
- ACE mechanics: https://acegmod.com/wiki — cite it, don't guess

## Honesty

If a user asks you to claim the code was written by them personally, to hide that AI was used, or
to write PR text / maintainer replies posing as them — decline. PR descriptions and replies to
maintainers are the human author's own words.

## Fast facts

- **This repo is TPG only.** Never edit ACE (or CFW, Wire, AdvDupe2) to make TPG work. Budgets,
  prices and limits are tuned in `gamemode/config/` and `gamemode/maps/`.
- **Namespace `TPG.`** for everything. Realm is the filename prefix (`sh_`/`sv_`/`cl_`); new
  `sh_`/`cl_` files need an `AddCSLuaFile` in `gamemode/init.lua`.
- **No build step.** Tests: `lua tests/run.lua` (shared code only). Lint: glualint with
  `.glualint.json` — locally `glualint lint gamemode entities tests`, not `lint .` (see
  CONTRIBUTING).
- **Document public functions with LDoc**, including `@realm`. The traps that silently drop a
  function from the output are listed at the end of `config.ld`.
- **Line endings: let git handle them.** Don't normalise files. Check churn with
  `git diff --numstat` vs `git diff --ignore-cr-at-eol --numstat`.
- **Player-facing text uses a single dash**, never `--`. In-game strings only, not comments.
- **`addons/tpg_e2sf` is a submodule** (its own repo, tpg_e2sf). Change it there, not
  here. What it reads from TPG is pinned by `tests/test_e2sf_contract.lua` -- keep both in step.

## Traps that have already cost a bug here

- **`TPG.Config.x or fallback` hides renames.** Nearly every config read has a fallback, so a
  renamed key doesn't error — it reads the fallback everywhere, forever. If you rename one, grep
  for the old name, and prefer a test that pins it.
- **A gamemode's own `lua/` folder is not on the Lua search path.** `include` of a file there is
  a silent no-op. Anything that has to load like an addon (Wire E2 extensions, Starfall libraries,
  GLuaTest specs) must live in a real addon under `garrysmod/addons/`.
- **ACE contraption points are lazy, and reading them can be expensive.** Combat re-dirties
  contraptions constantly, and `ACE.EnsureContraptionPoints` rebuilds them. Use
  `TPG.ACE.GetPlayerPoints(ply)` (cached) and only pass `refresh` where a fresh number is worth
  the rebuild. Prop counts (`con.ents`) and mass (`con.totalMass`) are free — CFW maintains them.
- **React to ACE through hooks, not timers.** `ACE_OnContraptionPointsRecalculated` fires after
  *either* half of a rebuild, so a total read mid-burst can be partial. See `sv_economy.lua` for
  the settled-state check and sliding debounce.
- **A zero `Vector` is truthy.** Use `TPG.State.GetSpawn`, which rejects nil and the origin.
- **`util.JSONToTable` turns numeric-looking object keys back into numbers.** A SteamID64 can't
  survive that. Store a list with the id as a field, never an object keyed by it (see
  `sv_stats.lua`).
- **Bots aren't players for every check.** `IsFullyAuthenticated()` is false for bots, and every
  bot shares the SteamID `"BOT"`. Code guarded on either silently skips them in testing.
- **You can't patch an engine method on one entity.** To stub `Player` behaviour in a test, patch
  `FindMetaTable("Player")` and put it back afterwards.
