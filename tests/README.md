# Tests

```
lua tests/run.lua                # everything
lua tests/run.lua gear maps      # only suites whose name contains these
```

Any Lua 5.1 interpreter will do; nothing is installed and nothing is
downloaded. The runner exits non-zero on failure, so it works as a gate.

## What these do and do not cover

They run the gamemode's **shared** files — `gamemode/shared.lua` and
everything it includes — against a stub of the GMod API, outside the game.
That covers the config tables, the lookups over them, and the pure functions:
armor tiers, ranks, gear prices, game types, capture-point maths, map configs,
weapon discovery, and the utility helpers.

They do **not** cover the server files. Those are hook and net plumbing whose
behaviour is the engine calling them in an order this harness does not
reproduce, and a test that fakes that order would pass without meaning
anything. Nor do they cover the client HUD, which is drawing code with no
return values to assert on.

For anything that needs a real server — round transitions, spawning, ACE
integration, persistence — boot one and drive it. That is what
[gmodkit](https://github.com/KemGus/gmodkit) is for; these tests are the fast
tier that runs first.

**A passing run proves the gamemode's own logic, not that GMod behaves the way
`harness/gmod.lua` claims it does.** Where the stub imitates a real engine
behaviour rather than being an obvious no-op, it says so in a comment — those
are the places where it could drift away from the engine and quietly make a
passing test meaningless.

## Layout

```
tests/
  run.lua              the runner: registry, assertions, reporting
  harness/
    gmod.lua           the GMod API stub, and fake players/SWEPs
    load.lua           loads the shared chain under the stub
    preprocess.lua     rewrites GMod's `continue` for stock Lua
    lexer.lua          just enough scanning for preprocess to be safe
  test_*.lua           one suite per area
```

New suites go in `SUITES` at the top of `run.lua`. That list is explicit
rather than globbed: stock Lua cannot list a directory without an extra
library, and a manifest also means a new file is not silently skipped because
of a typo in its name.

## Writing a test

```lua
describe("gear: the cooldown key")

it("keeps armor ids and weapon classes in separate namespaces", function()
    expect.eq(TPG.Gear.Key("armor", 3), "armor:3")
    expect.ne(TPG.Gear.Key("armor", 3), TPG.Gear.Key("weapon", 3))
end)
```

`expect` has `eq`, `ne`, `near`, `truthy`, `falsy`, `nils` and `raises`, all
taking an optional trailing message. The stub state is reset before every
case, so a test can register players and SWEPs without cleaning up:

```lua
local gmod = expect.load.gmod

local ply = gmod.player(TEAM_GREEN)     -- a fake player on a team
weapons.Register({ Base = "weapon_ace_base", Spawnable = true, Slot = 4 }, "w_x")
TPG.Weapons.Discover()
```

What is *not* reset is anything a test writes onto `TPG` itself — the
gamemode is loaded once for the whole run. A test that mutates a config value
or swaps a function has to put it back; see the `withACE` helper in
`test_config.lua`.

## The `continue` rewrite

GMod runs a patched LuaJIT with a `continue` statement that stock Lua refuses
to compile, so `harness/preprocess.lua` rewrites it before anything loads:

```lua
for x in y do BODY-with-continue end
-->
for x in y do repeat BODY-with-break until true end
```

It is a source rewrite, so it is only as good as its guards — and it fails
loudly rather than miscompiling. A loop that uses both `continue` and its own
`break` is refused (the inserted `repeat` would swallow the `break` and turn
"leave the loop" into "skip an iteration"), as is `continue` inside a `repeat`
loop. Neither exists in this repo today. `test_preprocess.lua` runs first and
checks the rewrite against real behaviour, including that the one file that
needs it — `config/sh_weapons.lua` — still compiles afterwards.

## What a test here is for

Prefer asserting the things the game will not tell you about:

- **Invariants between files.** Every `subCategory` an override names has to
  exist in `SubCategoryTabs`; every armor id with a gear price has to be a
  real tier. Neither errors when broken, they just quietly stop working.
- **Documented behaviour that is easy to regress.** `GetArmor` falls back to
  Light rather than None; `GetGameType` never returns nil; capture speed
  stalls on an evenly contested point.
- **Numbers that were tuned against a specific bad outcome.** The speed floor
  exists because a Juggernaut summed to exactly zero and Source then ignored
  the clamp, making the heaviest armour the fastest thing on the field. That
  is a test, not a comment.

`TPG.Config` is the clearest case: nearly every read site is
`TPG.Config.xyz or <fallback>`, so a renamed key does not error — it silently
reads as the fallback everywhere, forever.
