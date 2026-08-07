# Error log

Every non-trivial problem hit while working on this resource, its root cause, and the rule that
stops it recurring. Read it before working in an area that already appears here.

---

## [2026-08-07 16:20] — A studio-measured vertical shipped enabled, for the fourth time

**Context:** `leg_press` on `prop_muscle_bench_06`, measured in the alignment studio, released
enabled in 1.0.1 and 1.0.2.

**Error:** Reported in play: the body lands in the wrong place on the machine. The same symptom
already cost `prop_muscle_bench_02`, `_04` and `_05` their place in the bench press.

**Root cause:** Not the measurement. `animOffset` is measured from the prop's ORIGIN, and how high
that origin sits above the ground is decided by whoever placed the prop in the map. The studio
spawns its own copy on flat ground, so it can only ever produce a vertical that is right for a copy
placed the way the studio places it. The horizontal components and the two rotations are properties
of the MODEL and do transfer; the Z is a property of the PLACEMENT and does not.

**Fix:** `enabled = false` on the entry, everything else kept, and one comment replacing the two
contradictory ones the entry had been carrying - one saying the placement was never measured, one
saying it was measured on real ground. Both were written honestly on the day they were written.

**Prevention:** An entry whose vertical came only from the studio must not ship enabled. The studio
answers "where does this body sit on a copy I placed", and shipping treats the answer as though it
were "where does this body sit on the copy YOUR map placed". Those are different questions and the
tool cannot tell them apart, so the judgement has to be made outside it. When in doubt the entry
ships off with its numbers intact and a one-line route back, which costs an operator one config line
and costs a player nothing, against a body sitting in mid-air for everyone.

**What this does not change:** an entry measured against a model the map really places, and then
confirmed on a second instance somewhere else, is verified in the sense that matters. That is what
`verifiedModels` records and why it is not the same field as `tunedAgainst`.

---

## [2026-08-07 15:40] — type() == 'function' rejected a callable proxy, and no stats ever loaded

**Context:** The first install by somebody other than the author, on a stock qb-core server.

**Error:** `[v-sport] could not resolve an identifier for <name>; not loading their stats`, for every
player, on every join. On the client: `no stats received from the server after 10 attempts`, then
`the server did not answer a session request`.

**Root cause:** `try()` in `bridge/server/framework.lua` gated on `type(fn) ~= 'function'`. FiveM
passes an object across a resource boundary as a proxy, so `QBCore.Functions.GetPlayer` is a TABLE
with a `__call` metamethod. Measured in game: `type=table`, `getmetatable(gp).__call=function`, and
`gp(src)` returns the player. The guard rejected it, and the forty-retry loop asked the same wrong
question forty times over twenty seconds.

It needed a second condition to surface at all: the adapter tries `exports['qb-core']:GetPlayer`
first and only falls through to the gated path when that export is missing, which it is on a stock
qb-core.

**Fix:** `Sport.callable(value)` - function, table or userdata - with the pcall around the call as
the real guard, which is what it always was. Applied to both `try()` implementations and to the two
ESX registration paths carrying the same gate.

**Prevention:** Never ask `type(x) == 'function'` about a value that came from another resource. The
question is "can I call this", and only calling it answers that. `tools/check.py` now fails on the
pattern anywhere under `bridge/` or `server/`.

**What should have caught it sooner:** the evidence was in the same boot log. `registered 4 usable
items` printed on the server where the player lookup failed, because that path reaches its method
through truthiness plus a pcall. Two code paths to one object disagreeing about whether it exists is
a description of the bug, and it was already on screen.

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

## [2026-08-06 16:10] — A local used before it was declared, twice

**Context:** Adding the condition mechanics. `Profiles.addDrain` in `server/stats.lua` called
`newId`, which was declared further down next to the buff code. `ApplyPackage` in
`server/api.lua` called `Exhaust`, which is a local declared in a later section of the same
file.

**Error:** No error at load. Both would have been `nil` at call time - "attempt to call a nil
value" the first time a drug script used a drain or a package.

**Root cause:** A Lua `local` is only visible to code written **after** it. Both files are long
and organised into commented sections, which makes it easy to add a caller above the thing it
calls and never notice, because nothing complains until the line actually runs.

**Fix:** Moved the id generator to the top of `server/stats.lua`, above every user. In
`server/api.lua`, replaced the `Exhaust` call with the two-line `TriggerClientEvent` it wraps,
with a comment saying why.

**Prevention:** **In a long file, a helper that more than one section uses goes at the top, not
next to its first caller.** Before calling a local from a new section, check where it is
declared - `Ctrl+F` for `local function <name>` and compare line numbers. A forward reference to
a local is silent until runtime, which is the worst kind.

---

## [2026-08-06 16:35] — Fatigue was setting the pace instead of guarding against macros

**Context:** The brief asked for all three stats to reach 100% in about a fortnight. Measuring
it found three months.

**Error:** Not a crash. A design error, found only because the balance got measured rather than
reasoned about.

**Root cause:** Two mechanisms were both trying to bound progression - `Config.Allowance` (the
hard cap per cycle) and `Config.Progression.fatigue` (the diminishing return within a session
block) - and fatigue was tuned so aggressively (`perSession = 0.30`, `floor = 0.12`) that a
player's fourth workout was worth 12% of their first. Fatigue, not the allowance, became what
every player felt. The allowance of 50 per cycle was never reached by anybody, so it did nothing
at all, and the documented number was three times the intended one.

**Fix:** Gave the two mechanisms distinct jobs and said so in the config:
fatigue is anti-macro (`perSession = 0.03`, `floor = 0.55` - a hard hour at the gym costs about
10%), the allowance is the wall. Then built a day-by-day simulator in the check script that runs
the real progression functions with the real allowance ledger and the real decay rules, and
reports days-to-max for five kinds of player. It now asserts the headline figure.

**Prevention:** **Never document a balance figure that has not been measured.** A progression
curve with four interacting mechanisms cannot be reasoned about in your head, and "roughly three
weeks" written in a README is a promise. The simulator is part of the check script now, so
changing any of the four numbers re-measures all five scenarios and fails if the headline moves
outside 12 to 17 days.

**Also:** when two mechanisms bound the same thing, write down which one is supposed to bind
first. If the answer is "both", one of them is doing nothing.

---

## [2026-08-06 19:40] — The cleanup swept away the gym equipment itself

**Context:** The placed-animation path attaches the PED to the PROP. Cleanup then diffed
"objects attached to the ped" before and after the session, to catch props a scenario had
spawned, and deleted the difference.

**Error:** The bench disappeared. Off the client's map, permanently, one piece of gym equipment
per workout.

**Root cause:** `IsEntityAttachedToEntity` reports the relationship in **both directions**.
Attaching the ped to the bench therefore made the bench come back as "an object attached to the
ped that was not there before", and it was deleted as though the game had spawned it.

**Fix:** Two guards. The equipment entity is passed into the cleanup and excluded by handle, and
the diff only runs when a SCENARIO actually ran - the only case where an object exists that this
resource did not create. Everything the placed path spawns is already tracked by handle in
`ownProps`.

**Prevention:** **A delete sweep must have an allow-list, never only a deny-list.** "Everything
that appeared since I last looked" will eventually include something that belongs to the map. If
the code creates the object, keep its handle and delete that; only fall back to a diff where
there is genuinely no handle to keep, and exclude every entity that was there first.

---

## [2026-08-06 19:52] — A clip that was a pose, not a movement

**Context:** The bench press was correctly placed, holding the bar in both hands, and completely
static - arms locked out, no pressing motion.

**Error:** Not an error. `amb@prop_human_seat_muscle_bench_press@base` / `base` was playing
exactly as asked.

**Root cause:** That clip is **1966 ms** long. Every other exercise's `@base` runs for several
seconds and is the real movement - push-ups 4833, chin-ups 13333, free weights 9500. The bench
press's is under two seconds because it is the SETTLED POSE: lying down holding the bar still.
Looping a pose looks like a broken animation. The movement is in `@idle_a` / `idle_a`, 9433 ms.

**Prevention:** **When an animation looks static, check the clip LENGTH before assuming the clip
name is wrong.** Published dumps list durations. Anything under about two seconds in an
`amb@...@base` dictionary is probably an idle pose and its `@idle_a` sibling is the motion. The
naming does not tell you which is which; the duration does.

---

## [2026-08-06 20:30] — The same key-label bug, a third time

**Context:** The stats panel footer read `[b_1004] Fermer`.

**Error:** Identical to the bug fixed for the workout HUD and again for the interaction prompts:
`GetControlInstructionalButton` answers with an internal token rather than a key name for a good
number of controls, and BACKSPACE is one of them.

**Root cause:** Not the native. `UI.keyLabel` was written to handle exactly this and
`client/menu.lua` never started using it - it kept its own two-line copy of the raw lookup, and a
fix applied to two of the three copies looks complete.

**Fix:** `menu.lua` calls `UI.keyLabel`. Then a check-script guard: any use of
`GetControlInstructionalButton` in `client/` outside `ui.lua` now fails the build.

**Prevention:** **When a fix is applied to a duplicated two-liner, grep for the other copies
before calling it done.** Better: the guard. A rule enforced by the checker cannot be forgotten
by the next person, and the third occurrence of the same bug is the point at which writing one is
obviously cheaper than finding it again.

**Also worth noting:** the guard's first run flagged its own explanatory `--[[ ]]` comment block,
because inner lines of a block comment do not start with `--`. A linter that scans source text has
to strip comments properly, and blanking them while preserving line numbers is the way to keep the
reported location useful.

---

## [2026-08-06 22:15] — The alignment tool's camera mirrored the mouse

**Context:** The new scripted orbit camera in `client/tune.lua`. First use in game: vertical look
correct, horizontal look reversed.

**Error:** Dragging the mouse right turned the camera left.

**Root cause:** `camYaw = camYaw - GetDisabledControlNormal(0, 1) * 12.0`. The camera sits at
`(sin yaw, cos yaw)` around the target, so it looks along `-(sin yaw, cos yaw)`, giving a view
heading of `180 - yaw`. Turning the view right means dropping that heading, which means RAISING the
yaw. Subtracting mirrored the axis.

**Fix:** One sign. `+` instead of `-`.

**Prevention:** For a spherical camera, derive the sign from the view direction rather than guessing
it. Write down what the position formula implies about which way the camera looks, and the sign
follows. Copying the sign convention from a follow camera does not work, because a follow camera is
positioned behind the ped rather than in front of the target.

---

## [2026-08-06 22:40] — The height readout reported the offset, not the body

**Context:** The tuner's `feet above floor` row, used to judge whether a body is on the equipment or
floating above it.

**Error:** On the yoga mats it read `+1.03` while the body was visibly flat on the mat. Two separate
faults, one hiding the other.

**Root cause 1:** `GetGroundZFor_3dCoord` traces against map geometry, and the studio is a hundred
metres above open sea. It returned nothing, so the row was blank in exactly the mode that needed it
most - standing exercises with no visual reference at all.

**Root cause 2, the worse one:** the row read `GetEntityCoords(ped)`. **An attached ped's
coordinates are its attach point, around the pelvis, not its feet.** So the row was echoing back the
`animOffset` it had just been given, minus the prop's origin - it agreed with itself no matter what
the body was doing. A readout that cannot disagree with the input is worse than a blank one, because
it looks like confirmation.

**Fix:** Measure the lowest of `SKEL_L_Foot` (14201) and `SKEL_R_Foot` (52301) with
`GetPedBoneCoords`, which is where the body actually is in every mode. In the studio, compare against
the drawn grid's height, taken from the prop's own `GetModelDimensions` rather than from the map.

**Prevention:** **A diagnostic must be derived from a different quantity than the one it checks.**
Reading back a transform of the input and calling it a measurement is the failure mode; going to the
skeleton is what makes it independent. Related: `GetEntityCoords` and `GetPedBoneCoords` do not agree
on an attached ped, and the difference is about a metre - roughly the number that appeared in four
mat measurements before anyone questioned it.

---

## [2026-08-06 23:40] — The balance simulator let a day run past 24 hours

**Context:** Lowering `Config.Allowance.total` from 50 to 24. The simulator was re-run at several
values to measure the cost, and one of its rows did not add up: the grinder scenario reached 300
points in 7 days, which is 43 points a day against an allowance of 24 per 25 hours.

**Error:** Two numbers that cannot both be true. The allowance was being applied correctly, so the
days were wrong.

**Root cause:** The schedule places 2 hours between blocks of three sessions. Sixty sessions is
twenty blocks, which is **53 hours** — and the day advanced with
`now = math.max(now, day * 86400)`, which keeps the larger value. So any scenario dense enough to
overflow reported "days" that were not days. The grinder's `~5 days` was really about eleven, and
the four less dense scenarios were correct only because they happened to fit inside 24 hours.

**Fix:** The clock is the authority. `sessionsPerDay` is now a ceiling: sessions are placed until
the day is full and the remainder are dropped and reported. The grinder scenario now reads
`15 days, 420 sessions (480 asked for and dropped - the day was full)`.

**Prevention:** **A simulated clock has to be constrained by the thing it is simulating.** The bug
was a `math.max` that silently accepted an impossible state instead of refusing it; had the day
boundary been an assertion rather than a maximum, it would have failed on the first dense scenario
ever added.

**Worth recording separately:** the corrected figure is *better* than the wrong one. Grinding buys
one day, not eight, which is exactly what the allowance exists to do. But `~5 days` had been quoted
in README.md, CONFIG.md and the config comments as evidence that grinding is bounded — a wrong
number that happened to support a true conclusion, which is the kind that survives review longest.

---

## [2026-08-07 01:20] — The alignment studio had no floor, so every measurement taken in it was low

**Context:** `/vsporttour` was added to review every animation on every prop. A player then reported
that on props resting on the ground, their feet went through the ground.

**Error:** Bodies measured too low, by between 7 cm and 50 cm depending on the prop.

**Root cause:** The studio spawned the prop a hundred metres over open water - no ground, chosen for
a clean silhouette - so the floor it drew and measured against came from `GetModelDimensions`. That
returns the model's **bounding box**, which is not the visible bottom of a prop: it is frequently
lower, because it wraps collision and stray geometry. So the drawn floor sat below where the prop
really rests, and every offset measured against it was short by that difference.

Worse, the error was **proportional to the prop**: a barbell with 100 kg discs has a deeper box than
a bare bar, so each model was wrong by a different amount. That produced a table of nine
measurements ordering the barbells by disc size - internally consistent, physically plausible, and
entirely an artefact of the instrument. On real ground all thirteen land within 4 cm of each other.

**Fix:** The studio stands on the LSIA apron. The prop is settled with
`PlaceObjectOnGroundProperly`, the native the map itself uses, and the ground height comes from a
trace rather than from the model. The ped is no longer frozen - freezing was only needed because
there was no floor, and it actively hid the fault, since a frozen ped holds whatever height it is
given and feet sunk into tarmac look identical to feet on it.

**Prevention:** **Do not build a measuring instrument that has to infer its own reference.** The
studio existed to avoid hunting for a real prop in a real gym, and it threw away the one thing the
real world was providing for free. Where a measurement has a ground truth available, use it, even
when a synthetic environment is more convenient.

**And a second prevention, which is the more expensive lesson.** The squat rack's 0.09 was
*re-checked* when it looked wrong, against the same grid, and confirmed - with a paragraph written
here explaining why a squat rack would sit that low. **A confirmation that reuses the broken
instrument is not a second opinion**, and a written rationalisation makes a wrong number harder to
question later, not easier. What actually caught it was a player describing a symptom.

---

## [2026-08-07 01:35] — The interaction prompt ignored where the player was looking

**Context:** A player facing a gym machine the catalogue does not know was offered the bench press,
and using it lay their character down in mid-air.

**Error:** The wrong equipment offered, and a session started at a prop that was not on screen.

**Root cause:** `Detect.closestVisible()` returned the nearest candidate within eight metres and
performed no visibility or aim test whatsoever. The name had said otherwise since it was written.
Muscle Beach is the worst case: a dozen recognised props inside eight metres of each other, so the
prompt could be about any of them, and the body was then placed at whichever one won - off screen,
which reads as mid-air.

**Fix:** Aim decides and distance only breaks ties. The dot product of the camera's forward vector
against the direction to each candidate, with the cone in `Config.Interaction.aimCone`. When nothing
falls inside the cone the nearest still wins, so the prompt never disappears just because the player
looked away from equipment they are standing on.

**Prevention:** **A function whose name states a property it does not check will be trusted for that
property.** `closestVisible` was called from the prompt for months on the assumption the name was
true. Either implement the name or rename the function.

---

## [2026-08-07 02:10] — Every session that ended early was rejected as cheating

**Context:** A server log full of `rejected a session ... impossibly fast - 2124ms against an
expected 7515ms`, from a player testing normally.

**Error:** Any workout that stopped before the last repetition paid nothing and was logged as a
suspected cheat. Four consecutive misses end a session, and holding the cancel key stops one, so
this was a large share of all real play.

**Root cause:** `Equipment.minimumDurationMs(entry)` answered for the FULL rep count and took no
argument. The server compared the elapsed time against that, so three reps of twelve looked
impossibly fast for twelve.

**The part that makes it worth writing down:** fifty lines below the rejection, the same file
carefully worked out what a partial set was worth -

    -- A session cut short pays for the part that was done.
    local completion = reps / Equipment.reps(entry)

- and the README promised it in as many words. **Two rules in one file disagreed about the same
feature, and the one that ran first silently won.** The partial-payment code could never execute.

**Fix:** `minimumDurationMs(entry, reps)` takes the claimed reps, and the server parses reps before
judging duration rather than after. Asserted against the real function: a 2124 ms session may now
claim one rep and is still rejected for claiming two.

**Prevention:** **A guard placed before the logic it guards must be expressed in the same terms as
that logic.** The check knew about durations and the payment knew about completion, and nothing
connected them. Where a feature has a partial case, every gate in front of it needs to know that.

---

## [2026-08-07 02:45] — The studio traced the ground before moving the player to it

**Context:** The studio had just been moved onto real tarmac specifically so it would stop guessing
its own floor. A `/vsporttour` log then showed, on every single studio spawn:

    the studio ground would not stream in; falling back to the configured height

**Error:** The ground trace failed 100% of the time, so the studio silently went back to guessing -
the exact bug the rewrite existed to fix.

**Root cause:** Ordering. `spawnStudioProp` requested collision and traced the ground at the top of
the function, and teleported the player at the BOTTOM. Streaming follows the player, so the trace ran
while they were still hundreds of metres away and there was no tarmac to hit.

**Fix:** The player is moved first, frozen briefly at a safe height while the collision loads, and
only then is the ground traced and the prop placed. The retry window went to 10 seconds and requests
collision on each attempt.

**Prevention:** **A warning nobody reads is not a diagnostic.** The message was correct, printed
every time, and sat in the log through an entire 43-pair review without being noticed - it took
reading a log for a different reason to see it. Where a fallback silently degrades the thing the code
exists to do, it should be loud enough to stop the operation, not a line among forty others.

**Worth separating clearly:** this did NOT invalidate that review's verdicts. The ped is ATTACHED to
the prop, so the body's position relative to the prop - which is what "does this animation look
right" asks - is unaffected by where either of them is in the world. What it did invalidate is the
grid, the height readout, and any Z offset measured against them.

---

## [2026-08-07 03:30] — No modelOverrides ever applied on a server with a target

**Context:** Repeated reports of "it offers the bench press on a prop and places my character
anywhere", with a screenshot of a body lying flat on the floor between two incline benches. Three
separate wrong theories were investigated first: the interaction prompt ignoring aim, stale offsets
measured in the sky studio, and a mis-assigned model. All three were real problems and none of them
was this one.

**Error:** `Equipment.staging(entry, nil)`, on every single session, so the entry's generic numbers
were used and **no per-model placement was ever applied**. Two of the six `prop_muscle_bench` models
are incline benches with their own `animRot`; both got the flat bench's offset and laid a body out in
mid-air beside them.

**Root cause:** One missing field. `client/interact.lua`'s target integration builds a candidate from
the entity the target hands back:

    Session.start({ entity = entity, coords = coords, keys = { key }, ... }, key)

`model` was not in that table, and `Equipment.staging` returns early without it.

**Why it survived so long, which is the interesting part.** Every other path was right:

- the alignment tool passes its own hash, so `/vsportprop` was always correct
- `/vsporttour` uses the alignment tool, so a 43-pair review passed with nothing marked wrong
- the built-in key prompt passes a real detection candidate, so a server with no target was fine

So the fault appeared only on servers running a target - which is most of them - and only as
"the placement is wrong", which pointed at the measurements. Two full re-measurement passes were
done, and the numbers were fine all along.

**Fix:** the target candidate sets `model`, and `Session.start` derives it from the entity when a
caller omits it. Both, deliberately: the second means the next integration written against this
function cannot repeat it.

**Prevention:** **A function that silently degrades on a missing argument will be called without it.**
`Equipment.staging(entry, modelHash)` returning the generic staging for a nil hash is a reasonable
default and an invisible failure. Where an optional argument changes behaviour that much, either
derive it from what is available, or refuse.

**And a diagnostic note.** What found it was one line printed at session start naming the model, the
offset and the resulting height. `hash nil` in that line answered in ten seconds a question that
three rounds of reasoning had got wrong. Print what was chosen, not just what happened.

---

## [2026-08-07 04:00] — A raycast flag that crashed the client

**Context:** The tuner was given a raycast so it would find the prop the player is looking at, on the
theory that a bench missing from `GetGamePool('CObject')` is map-embedded geometry.

**Error:** An immediate hard crash, not a Lua error:

    SCRIPT ERROR: native 9f47b058362c84b5: exception at address gta-streaming-five.dll+2BD0E
    > GetEntityModel  > nearestPropFor (client/tune.lua:255)

**Root cause:** The probe used flag **17** - 16 for objects plus 1 for map geometry. A map hit returns
a handle that passes `DoesEntityExist` and is not an entity the model natives accept, so
`GetEntityModel` faulted inside the streaming DLL instead of returning nil or 0.

**Fix:** Flag 16 only, and every model read behind a `pcall`. Flag 1 bought nothing anyway: map
geometry has no entity to attach a ped to, so a successful hit would have been useless.

**Prevention:** **`DoesEntityExist` is not "this is a usable entity".** It answers a narrower question
than it looks like it answers, and a shape test is exactly the place that produces handles which pass
it and nothing else. Where a handle comes from the engine rather than from a pool walk, guard the
first native that reads it.

**Applied to all three:** the resource had two other raycasts by then, in `client/custom.lua` and
`client/commands.lua`. One already checked `GetEntityType == 3`, which would probably have caught it -
and "probably" against a client crash is not a trade worth making, so both got the same guard rather
than only the one that had already fired.

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
