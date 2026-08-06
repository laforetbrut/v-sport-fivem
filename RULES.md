# Project Rules & AI/IDE Instructions

The single source of truth for anyone — human or assistant — working on this resource.
Read it before changing anything.

## 1. Project Identity

| Field | Value |
|---|---|
| Project name | v-sport |
| Resource name | `v-sport` |
| Version | Whatever `fxmanifest.lua` says. Do not restate it here. |
| Tech stack | Lua 5.4 (`lua54 'yes'`), native UI only, optional MySQL |
| Author | vyrriox |
| Hard dependencies | **None.** That is a feature, defend it. |
| Optional, all runtime-detected | qb-core, qbx_core, es_extended, ox_core, ox_target, qb-target, qtarget, ox_lib, okokNotify, ox_inventory, oxmysql, mysql-async, ghmattimysql, interact-sound |

**The server owns every decision; the client draws and reads input.** No number the client
sends is trusted. Every payout is re-derived server-side from a session the server authorised,
its own clock and its own state. Every new net event must fit that split.

**There is no NUI, and there will not be one.** The whole interface is DrawRect and DrawText.
That is why the resource costs nothing when nobody is training, and why there is no focus to
get stuck. A feature that "needs" HTML needs a different design.

## 2. Git Workflow

- `main` is the only long-lived branch. Ordinary changes go straight to it.
- Feature branches `feat/<slug>`, fixes `fix/<slug>`, when a change wants review first.
- Commit messages: `type: lowercase summary` — `feat`, `fix`, `docs`, `perf`, `refactor`,
  `chore`. Present tense, no trailing full stop.
- **Never** put AI/assistant attribution in a commit, a comment, or any file.
- **Never** commit personal information. Git identity is the GitHub noreply address.
- **Never** commit `test-procedures/`, `.claude/` or `CLAUDE.md` — gitignored.
- Releases are cut by the maintainer. A contributor never bumps the version.
- Release titles: `vX.Y.Z — Short subtitle`, subtitle from the first CHANGELOG bullet.

## 3. Code Conventions

**Language.** All code, comments and log lines in **English**. User-facing text goes in
`locales/en.lua` **and** `locales/fr.lua`, never inline. The two files must stay key-for-key
identical, with matching format specifiers — the check script enforces both.

**Naming.** Lua locals `camelCase`. The globals this resource defines are `Sport`, `Locale`,
`Locales`, `L`, `Config`, `Equipment`, `Stats`, `Compat`, `Bridge`, `UI`, `State`, `Effects`,
`Detect`, `Minigame`, `Session`, `Interact`, `Passive`, `Menu`, `Profiles`, `Sessions`,
`Database`, `Items`. Config keys: `PascalCase` sections, `camelCase` fields. The database table
is `v_sport_stats`; events are `vsport:side:Name`.

**Architecture rules.**
- Framework, target, notification, inventory and database code lives in `bridge/` or
  `server/database.lua`, behind a `Compat.*` (client) or `Bridge.*` (server) function with a
  `Config.Compat` entry. **Never a resource name in a feature file.**
- Anything both sides need to agree on lives in `shared/`. `Stats.sessionGains`,
  `Stats.decayPeriods`, `Stats.allowanceLeft` and `Equipment.minimumDurationMs` are all called
  from both, and computing any of them twice is how the two drift and start rejecting honest
  players.
- A missing optional dependency degrades, never errors. Choose the fail direction on purpose
  and write it down: an item requirement fails **closed** (no readable inventory, no session);
  a session that cannot be verified pays **nothing**; an unknown wall clock charges **no**
  decay.
- The catalogue is data. Adding equipment, a stat, a difficulty or an item must never require
  touching the session path.
- **No per-player loop on the server.** One timer flushes, one sweeps buffs, one re-checks
  decay. Everything else is event-driven.
- **One `Wait(0)` in the resource**, in `client/minigame.lua`, and only while a session runs.
  Anything else that thinks it needs a per-frame loop is wrong; use the tier model in
  `Config.Performance`.

**Gotchas already paid for — all of these are in ERROR_LOG.md with the full story.**
- **`os`, `io`, `package` are server-only.** The client clock is `GetCloudTimeAsInt()`, and it
  returns **0** for the first frames after joining. `Sport.now()` returns 0 for "unknown" and
  every decay path refuses to charge against it.
- **Never `Set-Content -Encoding utf8`** on Windows PowerShell 5.1 — it writes a BOM, and a BOM
  breaks the Lua parse. The check script fails on one.
- **A section assignment ends with `}`, not `},`.** `Config.X = { ... }` is a statement.
- **Never a nil in an array literal.** `#` on a table with a hole is undefined.
- **`left`, `right`, `top`, `cursor`, `width` are geometry** inside a draw function. A quantity
  gets a name that says what it counts.
- **`IsDisabledControlJustPressed`, not `IsControlJustPressed`,** during the minigame. The pool
  keys are held disabled so that pressing W does not walk the player off the bench.
- **DrawRect takes fractions of the screen, and the screen is not square.** Anything that must
  look square is sized with `UI.square()`.
- **Text commands are a state machine.** Every text draw sets every property it cares about,
  every time.
- **Map props have no network identity.** Exclusivity is server-side proximity to an authorised
  session, not a state bag on the prop.
- **The engine ignores swim and sprint multipliers above 1.49.** Clamp before writing so the
  cache is honest about what took effect.
- **Backtick hash literals are CFX Lua, not Lua.** Correct to write; no general parser
  understands them. The checker rewrites them for the parse only.
- **When a native for something does not exist, say so and implement the observable
  behaviour.** Never write a line whose only purpose is to look like the missing feature.

**What NOT to do.** No hard dependency. No NUI. No placeholders or `TODO` in committed code. No
version bump unless asked. No emoji or em dashes in authored prose. No reformatting.

## 4. Project Structure

```
fxmanifest.lua              Manifest. THE version lives here. Files load in dependency order.
config.lua                  Every operator knob, one file, 19 commented sections.
bridge/shared/sport.lua     `Sport`: maths, time, tables, JSON, the debug printer. Loads first.
bridge/shared/locale.lua    `L(key, ...)`. English is the fallback for every missing key.
bridge/client/compat.lua    `Compat`: runtime detection of everything optional (client).
bridge/server/framework.lua `Bridge`: the four framework adapters, identifiers, permissions.
locales/en.lua, fr.lua      Key-for-key identical, enforced by the check script.
shared/equipment.lua        THE catalogue. A config file in everything but its folder.
shared/stats.lua            Progression, decay, allowance and effect maths. Called by BOTH sides.
client/ui.lua               Every pixel. DrawRect, DrawText, markers, toasts.
client/state.lua            `State`: the client's mirror of the server's numbers.
client/effects.lua          Where a number becomes something the player feels. Writes on change only.
client/detect.lua           The object-pool scan and the static spots. Three-tier cadence.
client/minigame.lua         The rhythm QTE and the workout HUD. The only Wait(0).
client/session.lua          One workout, start to finish. Asks the server for permission.
client/interact.lua         Target registration, the key prompt, markers.
client/passive.lua          Sprinting and diving, reported in batches.
client/menu.lua             The stats panel. A readout, not a menu: nothing to select.
client/commands.lua         /sport, /sportinfo, /sportscan, /sportspot, and every client export.
server/database.lua         Optional persistence. Three drivers, off silently when none is found.
server/stats.lua            THE authority: profiles, the allowance ledger, decay, buffs, saving.
server/session.lua          Token issue and result validation. Every check fails closed.
server/api.lua              Fifty exports and their event twins. The contract other resources use.
server/items.lua            Whey and the other consumables, on all three inventories.
server/commands.lua         /sportadmin and the boot banner.
sql/v_sport.sql             The schema, for operators who cannot grant DDL rights.
```

## 5. Adding a New Feature (Step by Step)

1. Read `ERROR_LOG.md` and apply its prevention rules.
2. Add the `Config.<Feature>` knobs with comments explaining the *why* of each, and where the
   feature interacts with the balance, say so in the comment — sections 5, 5b and 6 are read
   together and a knob that silently breaks one of them is worse than no knob.
3. Anything both sides must agree on goes in `shared/`. One implementation.
4. Anything framework- or resource-touching goes behind `Compat.*` / `Bridge.*`.
5. Server first (it owns every decision), then client, then drawing.
6. Both locale files, both languages, matching specifiers.
7. Add the export to `server/api.lua`'s `API` table — the event twin and the registration are
   automatic — and document it in `API.md`.
8. Run the checks in section 6.
9. Update `CHANGELOG.md` (English then French) and `README.md` if the surface moved.

## 6. Testing Checklist

```bash
python <scratchpad>/check.py
```

That script does all of the following, and a change is not done until it passes clean:

- parses every `.lua`, and fails on a UTF-8 BOM
- loads the whole shared chain in a real Lua 5.4 with the FiveM natives stubbed
- asserts every config section exists
- asserts every piece of equipment trains a stat that exists, resolves a difficulty, has
  `perfectZone` inside `goodZone`, and produces a positive minimum duration
- runs the progression maths: a perfect session pays, a spent allowance pays nothing, a maxed
  per-stat allowance blocks that stat and only that stat
- proves decay is idempotent — 10 idle days charges once, a second call charges nothing
- proves no effect at 100% exceeds an engine ceiling, and that the buff overcap holds
- locale parity both ways, format-specifier parity, and that every `L()` key used in code exists
- manifest completeness both ways

Then, in game:

- [ ] Server console clean on boot; client F8 clean.
- [ ] `/sportinfo` names the right framework, target and notification provider.
- [ ] `/sportscan` in a gym finds the props; `Config.Debug.drawDetected` agrees with it.
- [ ] A full session on each difficulty. Perfect, good and missed presses all judge correctly.
- [ ] Cancel mid-session — the reps done still pay, the animation clears, no stuck state.
- [ ] Die mid-session, get in a car mid-session, get blocked mid-session.
- [ ] Two players on one bench: the second is refused.
- [ ] Spend a whole allowance and confirm the refusal happens BEFORE the workout, with the
      remaining time named.
- [ ] Take whey and confirm the panel's recovery line drops.
- [ ] Stop every optional dependency in turn: the resource still boots and degrades as
      documented. With no database it says so once, in the console and to the player.
- [ ] Both locales, every screen.

## 7. Environment Setup

1. Clone into `resources/`, or junction a working copy — which is how the test server runs.
2. Nothing to build. `pip install luaparser lupa` for the checks.
3. Test server: `server-test/` at the repo neighbour level — `db-start.bat`, then FXServer.

## 8. AI Assistant Instructions

1. **Read this file and `ERROR_LOG.md` first.** Every gotcha in section 3 was paid for once
   already.
2. **Never bump the version** unless explicitly asked.
3. **Never write personal information** anywhere. `vyrriox` is the only identity permitted.
4. **Never add AI attribution** to a commit, comment, or file.
5. **Both locale files, every time.** The check script will catch you; run it first.
6. **Never trust the client.** New events re-validate server-side; new payouts re-derive from
   server state.
7. **No new hard dependency, ever.** Detection goes in `Config.Compat` + `bridge/`.
8. **No NUI.** See section 1.
9. **Balance changes are not free.** Sections 5, 5b and 6 are one system. Changing the
   allowance, fatigue or decay in isolation produces a server that is trivial or impossible;
   state what a change does to "days to reach 100%" before making it.
10. **Test before reporting done.** Run section 6. Say explicitly what could not be verified —
    "the checks pass" is not "it works in game".
11. **Fix adjacent bugs you find**, and log them in `ERROR_LOG.md` with a prevention rule.
