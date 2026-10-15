# Contributing to The Proving Ground

TPG is a combined-arms gamemode for [ACE](https://github.com/ACE-Project-Team/ArmoredCombatExtended),
maintained by a small volunteer team, so keep pull requests easy to review.

- Discord: https://discord.gg/Y8aEYU6 — discuss non-trivial changes first
- Issues: https://github.com/ACE-Project-Team/theprovingground/issues
- Start with [`ARCHITECTURE.md`](ARCHITECTURE.md): what loads when, what each folder owns, and
  how to add a game type.

## Workflow

- Branch off `main` and open PRs against `main`.
- One issue, or a closely related set, per PR. Split unrelated work.
- Say what changed, why, and how you verified it — in your own words.
- Balance changes (armour, prices, budgets, income, cooldowns) need before/after numbers or a
  repro. "Feels better" is a starting point, not a justification.

## Code style

Follow the [ACE style guide](https://acegmod.com/wiki/general-coding-and-style-guidelines) and the
[CFC GLua guidelines](https://github.com/CFC-Servers/cfc_glua_style_guidelines) it builds on. Lint
rules live in [`.glualint.json`](.glualint.json) and are enforced by CI. Things specific to TPG:

- **Four-space indentation.**
- **Everything hangs off `TPG.`** — new code goes in a sub-table (`TPG.Rounds`, `TPG.Economy`, …),
  never a bare global.
- **The filename prefix is the realm**: `sh_` both, `sv_` server, `cl_` client. A new `sh_`/`cl_`
  file also needs an `AddCSLuaFile` line in `gamemode/init.lua`, or it works in singleplayer and
  silently does nothing on a server.
- **Text players read uses a single dash** (`-`), never `--`. It renders badly in GMod chat and
  on the HUD. This is about strings that appear in game, not code comments.
- **Balance TPG through TPG.** Budgets, prices and limits live in `gamemode/config/` and
  `gamemode/maps/`. Don't change ACE to make a TPG number work out; if ACE is genuinely wrong,
  that is an ACE issue.
- Keep diffs free of unrelated whitespace changes. Git handles line endings
  ([`.gitattributes`](.gitattributes)); check a diff's churn is real with
  `git diff --numstat` against `git diff --ignore-cr-at-eol --numstat`.

## Documenting code (LDoc)

Public functions you add or change (anything on `TPG.`, plus entity and SWEP methods) get an
[LDoc](https://stevedonovan.github.io/ldoc/) `---` doc-comment with TPG's `@realm` tag:

```lua
--- Stable identifier for one item, used as the cooldown key on both realms.
-- @tparam string kind `"armor"` or `"weapon"` (anything else is treated as a
--  weapon).
-- @tparam string|number id Armor id or weapon class/virtual id.
-- @treturn string `"armor:<id>"` for armor, `tostring(id)` otherwise.
-- @realm shared
function TPG.Gear.Key(kind, id)
```

Local functions don't need one. Build with `ldoc .`; output goes to `doc/`, which is not tracked.
LDoc drops functions **silently** in several situations — read the list of traps at the bottom of
[`config.ld`](config.ld) before wondering why something is missing.

## Testing

| What | Command / where |
|------|-----------------|
| Shared-code tests | `lua tests/run.lua` (any Lua 5.1 or LuaJIT, nothing to install) |
| Lint (glualint) | CI, config [`.glualint.json`](.glualint.json); locally `glualint lint gamemode entities tests` |
| Everything else | a real server |

The tests cover the shared files — config tables, lookups, pure logic — against a stub of the GMod
API. They don't cover server or client files. [`tests/README.md`](tests/README.md) explains what's
worth a test here and how to write one.

Name the folders when you lint locally. On Windows, glualint joins the paths it walks with `\` and
its ignore patterns never match, so `glualint lint .` reports the E2 file under `addons/`, which
is Wire's preprocessor syntax and not Lua. CI runs on Linux and doesn't have the problem.

Server behaviour — rounds, spawning, the economy, anything touching ACE — has to be checked on a
running server. Say in the PR what you ran and what you saw.

## AI-assisted contributions

AI tools may be used as coding tools, but they must not replace the author's own understanding or
judgment.

Authors must:

- Be honest and disclose when AI tools were used.
- Use AI only to help with coding. PR text and replies must be written by the author; maintainers
  need to be talking to the contributor, not an AI toolchain.
- Understand the submitted code well enough to explain it, justify it, audit it for side effects,
  and make requested changes themselves.
- Make requested changes that actually fix the problem, rather than blindly resubmitting tool
  output.
- Keep each contribution focused on one issue or a closely related set of issues per PR. Large
  all-in-one PRs are not accepted when AI is doing the coding.

AI use does not relax TPG's style, cleanliness, or review requirements. Slop is slop regardless of
how it was made.

Maintainers are not LLM code auditors. Breaking these rules, or giving maintainers reason to
believe they are being broken, may result in a repository ban.

If you develop with an agent, see [`AGENTS.md`](AGENTS.md).
