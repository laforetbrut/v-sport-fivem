# Error log

Every non-trivial problem hit while working on this resource, its root cause, and the rule that
stops it recurring. Read it before working in an area that already appears here.

---

## [2026-08-06 14:05] — Trailing comma after every config section

**Context:** First write of `config.lua`, nineteen sections of the form `Config.X = { ... }`.

**Error:** `luaparser` rejected the file. Every section closed with `},` at column 0.

**Root cause:** The sections were written as though they were fields of one table literal. They
are not - each one is a separate assignment STATEMENT, and a statement cannot be followed by a
comma. Seventeen occurrences, all identical.

**Fix:** Replaced `(?m)^\},$` with `}`.

**Prevention:** A config file made of `Config.Section = { ... }` assignments ends each one with
a bare `}`. If a section close is indented, it is a nested table and keeps its comma; if it is
at column 0, it does not. Parse the file before moving on - the whole class of error is
invisible on read and obvious to a parser.

---

## [2026-08-06 14:07] — PowerShell wrote a UTF-8 BOM into config.lua

**Context:** Fixing the trailing commas above with `Set-Content -Encoding utf8`.

**Error:** `luaparser`: `line 1:0 token recognition error at: '﻿'`.

**Root cause:** Windows PowerShell 5.1's `-Encoding utf8` means **UTF-8 with BOM**. The
regex fix was correct; writing it back added three bytes to the front of the file.

**Fix:** Read the bytes, detected `EF BB BF`, wrote the remainder back with
`New-Object System.Text.UTF8Encoding $false`. Then swept every `.lua` in the resource for the
same three bytes.

**Prevention:** **Never use `Set-Content`/`Out-File -Encoding utf8` on a file another tool will
parse** on Windows PowerShell 5.1. Use the `Write`/`Edit` tools, or
`[System.IO.File]::WriteAllText($path, $text, (New-Object System.Text.UTF8Encoding $false))`.
The check script now fails on a BOM in any Lua file, so this cannot come back silently.

---

## [2026-08-06 14:32] — A deliberate nil in the middle of an array literal

**Context:** `client/minigame.lua`, the `DISABLED` list of controls held down during a session.
A trailing sentinel was added so that "adding one more control is a one-line diff", then
stripped with `DISABLED[#DISABLED] = nil`.

**Error:** No error - which is the problem. The sentinel was an undeclared global, so it was
`nil`, so `#DISABLED` was already undefined behaviour before the strip ran.

**Root cause:** Cleverness for no benefit. Appending to a plain list is already a one-line diff.

**Prevention:** **Never put a nil, or anything that might be nil, in an array literal.** `#` on
a table with a hole is undefined in Lua, not zero and not the count. If a list needs a
placeholder, it needs a comment instead.

---

## [2026-08-06 14:40] — Assigning to a global to mean "do nothing"

**Context:** `Effects.exhaust` in `client/effects.lua`. There is no native that empties the
sprint bar, and the first draft papered over that with
`SetPlayerSprintStaminaDrainRateMultiplier = nil` inside a guard.

**Error:** Silently created a global named after a native that does not exist. Did nothing, and
read as though it did something.

**Root cause:** Writing code to represent a capability the engine does not have, rather than
writing down that the capability does not exist.

**Fix:** Implemented exhaustion as what a drained player actually experiences - the sprint
bonus scaled by a factor, and `DisableControlAction(0, 21, ...)` at factor 0 - and documented
the limitation in the function header and in API.md.

**Prevention:** When a native for something does not exist, **say so in the comment and
implement the observable behaviour instead**. Never write a line whose only purpose is to look
like the missing feature. If a caller needs to know the difference, it goes in API.md.

---

## [2026-08-06 14:44] — Invalid Lua from an "existence probe"

**Context:** `registerOxInventory` in `server/items.lua` tried to test for an export with
`exports.ox_inventory:registerHook and nil` as a statement.

**Error:** Syntax error. Lua has no expression statements; `a and nil` on its own line does not
parse.

**Root cause:** Attempting to probe for a capability that was never needed - the item flow uses
the `ox_inventory:usedItem` event, not a hook.

**Fix:** Deleted the probe. One event handler dispatching from an item-name map, registered
once rather than once per item.

**Prevention:** In Lua, a bare expression is not a statement. To call something for its side
effect only, assign it (`local _ = ...`) or wrap it in `pcall`. And check whether the probe is
needed at all before writing it.

---

## [2026-08-06 15:02] — A local shadowed the panel's left margin

**Context:** Adding the training-allowance block to `client/menu.lua`. The draw function
already had `local left = x - width * 0.5 + 0.014` as the left text margin. The new block
declared `local left = math.max(0.0, total - spent)` for the remaining allowance.

**Error:** Every text draw in the allowance block positioned itself at an x of `18.5`, far off
screen. Compounded by a typo (`left_`) that made the first one land at 0.

**Root cause:** A short, generic name for a coordinate, reused for a quantity in the same
function.

**Fix:** Renamed the allowance value to `remaining` and used the outer `left` for positioning.

**Prevention:** In a draw function, **`left`, `right`, `top`, `cursor` and `width` are reserved
for geometry.** A quantity gets a name that says what it counts (`remaining`, `spent`,
`total`). Lua will not warn about a shadow, and an off-screen draw looks like nothing rendered
at all rather than like a bug.

---

## [2026-08-06 15:20] — The check script's own false positive on `%%`

**Context:** Verifying that `locales/en.lua` and `locales/fr.lua` use the same format
specifiers for each key.

**Error:** Reported `notify.requirement_stat` as mismatched: `en=['%s','%d','% f']` against
`fr=['%s','%d','% p']`. Both files were correct.

**Root cause:** The specifier regex `%[-+ #0]*[\d.]*[a-zA-Z]` includes a **space** in the flag
class, which is valid printf. So in `"at %d%% for this"` the second `%` of `%%` matched as
`% f`. The locales were fine; the checker was wrong.

**Fix:** Strip `%%` before searching.

**Prevention:** When comparing printf specifiers, **remove the literal-percent escape first**.
And when a check fails on a file that reads correctly, suspect the check - a validator's own
bugs cost more than the bugs it finds, because they get "fixed" in the source.

---

## Notes that are not errors but were paid for once

**`os`, `io` and `package` are server-only in FiveM.** The client's wall clock is
`GetCloudTimeAsInt()`, and it returns **0** for the first few frames after joining, before the
time service answers. Treating 0 as a real timestamp would make everything look ancient and
charge a full decay. `Sport.now()` returns 0 for "unknown" and every decay path refuses to
charge anything against it.

**Backtick hash literals are CFX Lua, not Lua.** `` `WEAPON_UNARMED` `` is a compile-time joaat
and is the right thing to write in a FiveM resource, but no general Lua parser understands it.
The check script rewrites them to `GetHashKey("...")` for the parse only; the files keep the
backticks.

**`GetGamePool('CObject')` returns handles, and most of them are not sport equipment.** The
scan does one table lookup per object and only then reads coordinates. Reading
`GetEntityCoords` for every object first, and filtering after, was measurably worse in a dense
interior for exactly the same result.

**Map props have no network identity.** The first design put a `sportUser` state bag on the
prop to mark it occupied. Map props mostly have no net ID, so there was nothing to hang it on.
Exclusivity is now decided server-side by proximity to an authorised session, and the client's
copy of that list is display-only.

**`IsDisabledControlJustPressed`, not `IsControlJustPressed`, during the minigame.** The pool
keys are held disabled for the whole session so that pressing W does not also walk the player
off the bench. A disabled control does not report through the normal check.
