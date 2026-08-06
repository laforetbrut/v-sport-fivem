# API

Everything another resource may call, every event this one fires, and the state bags it
publishes.

Nothing here is required to use v-sport. It exists so a drug script can boost gains and hand
out debuffs, a supplement item can bypass the recovery timer, an inventory can read a carry
weight, and an admin menu can fix a number.

**Conventions used by every export in this file:**

- A bad argument returns `nil` or `false`. Nothing here raises.
- Tables are copies. Mutating a returned stats table changes nothing inside v-sport.
- An unknown or not-yet-loaded player is not an error - it returns `nil`/`false`. A player can
  disconnect between your resource deciding to buff them and the call arriving.
- Changes are clamped by `Config.Buffs.maxSingleChange` and logged when clamped, so a loop
  with a sign error costs a console warning rather than somebody's progress.
- Every server export has an event twin: `vsport:server:<Name>`. Events cannot return a
  value, so use exports when you need one.

---

## Contents

- [Quick start for a drug script](#quick-start-for-a-drug-script)
- [Server exports: reading](#server-exports-reading)
- [Server exports: the training allowance](#server-exports-the-training-allowance)
- [Server exports: changing stats](#server-exports-changing-stats)
- [Server exports: buffs and debuffs](#server-exports-buffs-and-debuffs)
- [Server exports: decay](#server-exports-decay)
- [Server exports: conditions — smoking, addiction, injury](#server-exports-conditions--smoking-addiction-injury)
- [Server exports: packages](#server-exports-packages)
- [Server exports: training control](#server-exports-training-control)
- [Server exports: the body](#server-exports-the-body)
- [Server exports: items](#server-exports-items)
- [Client events, for a radial menu](#client-events-for-a-radial-menu)
- [Client exports](#client-exports)
- [Events this resource fires](#events-this-resource-fires)
- [State bags](#state-bags)
- [Worked examples](#worked-examples)

---

## Quick start for a drug script

The five calls that cover most of what a drug wants to do:

```lua
-- Training is worth double for half an hour
exports['v-sport']:ApplyMultiplier(source, nil, 2.0, 1800)

-- Temporarily stronger, or temporarily weaker
exports['v-sport']:ApplyBuff(source, 'strength', 20, 600)
exports['v-sport']:ApplyDebuff(source, 'stamina', 25, 600)

-- Do not lose the daily 5 points while this is in your system
exports['v-sport']:SetDecayImmunity(source, 24 * 3600)

-- Skip the recovery wait: some of it, or all of it
exports['v-sport']:AddAllowance(source, 20)
exports['v-sport']:ResetAllowance(source)

-- Winded and unable to sprint
exports['v-sport']:Exhaust(source, 0.0, 60)
```

Read [Worked examples](#worked-examples) at the bottom for three complete drug items.

---

## Server exports: reading

| Export | Returns |
|---|---|
| `GetStats(src)` | `{ strength = 42.5, breath = 10.0, stamina = 31.25 }` - the trained values. `nil` if not loaded. |
| `GetStat(src, stat)` | One trained value, or `nil`. |
| `GetEffectiveStats(src)` | The same shape, with active buffs folded in. These are the numbers driving the natives. |
| `GetEffectiveStat(src, stat)` | One effective value, or `nil`. |
| `GetProfile(src)` | Everything about a player in one call. See below. |
| `IsReady(src)` | `true` once the character's stats have loaded. Check this before anything that runs at spawn. |
| `GetBuffs(src)` | The active buff list. |
| `GetMultipliers(src)` | The active training multipliers. |
| `GetPeak(src[, stat])` | The highest value ever reached. One stat, or all of them. |
| `GetTotalSessions(src)` | How many workouts this character has ever finished. |
| `GetLeaderboard(stat, limit)` | `{ { identifier = '...', value = 87.5 }, ... }`, read from the database. |

`GetProfile` is the one to reach for when building a UI:

```lua
local profile = exports['v-sport']:GetProfile(source)
--[[ {
    identifier = 'ABC12345',
    stats      = { strength = 42.5, breath = 10.0, stamina = 31.25 },
    effective  = { strength = 57.5, breath = 10.0, stamina = 31.25 },  -- a +15 buff is live
    peak       = { strength = 48.0, ... },
    buffs      = { { id = 'b7', stat = 'strength', amount = 15, expires = 1700000900 } },
    multipliers = { },
    totalSessions = 214,
    lastSession   = 1700000000,
    decayPaused   = false,
    decayImmuneUntil = 0,
    blocked       = false,
    blockReason   = nil,
    allowance = {
        spent       = { total = 31.5, stats = { strength = 25.0, stamina = 6.5 } },
        left        = 18.5,                       -- nil when the global cap is disabled
        perStatLeft = { strength = 0.0, breath = 25.0, stamina = 18.5 },
        resetsIn    = 47200,                      -- seconds
        exhausted   = false,
    },
    training = { equipment = 'bench_press', startedAt = 1700000000, coords = {...} },
} ]]
```

`GetLeaderboard` reads up to two thousand rows and sorts them in Lua, because the stats are
stored as JSON and cannot be an `ORDER BY`. Call it for a command, not on a timer.

---

## Server exports: the training allowance

The recovery mechanic from section 5b of the config, and the group most likely to be what you
came here for.

A character may gain `Config.Allowance.total` points across every stat per
`Config.Allowance.window`, and no more than `Config.Allowance.perStat` into any single one.
Once spent, training pays nothing until it recovers.

| Export | Effect |
|---|---|
| `GetAllowance(src)` | The full picture. See below. |
| `IsAllowanceExhausted(src)` | `true` when a workout right now would pay nothing. |
| `AddAllowance(src, amount)` | Give back `amount` points of spent allowance, oldest first. |
| `ResetAllowance(src)` | Wipe the ledger. The full bypass. |
| `ReduceRecovery(src, seconds)` | Put the player on the shortened window for `seconds`. This is whey. |
| `ClearRecoveryBoost(src)` | Take the shortened window away again. |

```lua
local allowance = exports['v-sport']:GetAllowance(source)
--[[ {
    total       = 50.0,          -- the configured cap
    perStat     = 25.0,
    spent       = { total = 31.5, stats = { strength = 25.0, stamina = 6.5 } },
    left        = 18.5,          -- nil when the global cap is disabled
    perStatLeft = { strength = 0.0, breath = 25.0, stamina = 18.5 },
    resetsIn    = 47200,         -- seconds until meaningful allowance frees up
    window      = 90000,         -- the window in effect right now, in seconds
    reduced     = false,         -- whether whey (or ReduceRecovery) is active
    reducedUntil = 0,
    exhausted   = false,
} ]]
```

**`ReduceRecovery`'s argument is how long the boost lasts, not the new window.** The new window
comes from `Config.Allowance.reducedWindow`. So:

```lua
-- For the next 25 hours, this character's allowance recovers in 8 hours instead of 25.
exports['v-sport']:ReduceRecovery(source, 25 * 3600)
```

**`AddAllowance` vs `ResetAllowance`.** `AddAllowance(src, 15)` is a partial refund and is what
a consumable should usually do - it is balanceable. `ResetAllowance(src)` removes the recovery
mechanic entirely for that cycle and should be an admin tool or a genuinely expensive item.

---

## Server exports: changing stats

**These bypass the training allowance by default.** An admin fixing a number and a drug
granting a bonus are not workouts. Pass `respectAllowance = true` where it is available to
make the change count against the player's cycle the way real training would.

| Export | Effect |
|---|---|
| `AddStat(src, stat, amount[, respectAllowance])` | Add to the trained value. Returns the new value. |
| `RemoveStat(src, stat, amount)` | Subtract. Always positive `amount`. |
| `SetStat(src, stat, value)` | Set outright. |
| `SetStats(src, values)` | `{ strength = 50, stamina = 20 }`. Returns how many moved. |
| `ResetStats(src)` | Back to a new character: stats, peak, allowance, session count. |
| `AddSession(src, equipment, quality)` | Award a session through the **full** pipeline. |

`AddSession` is the interesting one. Unlike `AddStat` it goes through fatigue, multipliers, the
allowance, milestones and the events - so it is what a coach NPC, a scripted montage or a
piece of equipment owned by another resource should use:

```lua
-- As though they had just done a perfect bench press
local gains = exports['v-sport']:AddSession(source, 'bench_press', 1.0)
-- { strength = 1.15, stamina = 0.17 }   -- or {} if their allowance is spent
```

Valid equipment keys come from `exports['v-sport']:GetItems()`'s neighbour on the client,
`GetEquipment()`, or from `shared/equipment.lua`.

---

## Server exports: buffs and debuffs

A buff adds to a stat's **effective** value. The trained value is untouched, so the moment it
expires the character is exactly where they were - which is what makes it genuinely temporary
rather than a permanent gift with extra steps.

| Export | Effect |
|---|---|
| `ApplyBuff(src, stat, amount, seconds[, id])` | Points onto the effective value. Negative for a debuff. Returns the id. |
| `ApplyDebuff(src, stat, amount, seconds[, id])` | The same with the sign flipped, for readability. |
| `ApplyMultiplier(src, stat, value, seconds[, id])` | Multiply what **training** gains. `stat = nil` for all stats. |
| `RemoveBuff(src, id)` | Remove one by id. |
| `ClearBuffs(src[, stat])` | Remove all, or all on one stat. |

```lua
-- Stronger for five minutes
local id = exports['v-sport']:ApplyBuff(source, 'strength', 15, 300)

-- Weaker for ten
exports['v-sport']:ApplyDebuff(source, 'stamina', 20, 600)

-- Every stat trains 50% faster for half an hour
exports['v-sport']:ApplyMultiplier(source, nil, 1.5, 1800)

-- Strength training is halved - a steroid crash
exports['v-sport']:ApplyMultiplier(source, 'strength', 0.5, 600)

-- Later
exports['v-sport']:RemoveBuff(source, id)
```

**Notes that matter:**

- `seconds = 0` means indefinite. Use it only when something else will definitely remove the
  buff, because a buff nobody clears never expires.
- A buff can push the effective value up to `Config.Buffs.overcap` (default 20) above the
  stat's max. Effective values are never negative however large a debuff is.
- `Config.Buffs.stacking` decides what two buffs on one stat do: `'stack'` (both apply),
  `'replace'` (newest wins), `'highest'` (strongest wins).
- Multipliers compose by product. Two 1.5x supplements give 2.25x.
- `ApplyMultiplier` with `stat = nil` creates one entry per stat sharing an id prefix.
  `RemoveBuff` with that id removes the whole group.
- Buffs do **not** survive a server restart, by design. A supplement that outlives the server
  it was taken on is a bug.

---

## Server exports: decay

Decay is -`Config.Decay.amount` points per `Config.Decay.interval` of not training, after
`Config.Decay.grace`. It is computed from a timestamp, so it runs while the player is offline.

| Export | Effect |
|---|---|
| `SetDecayPaused(src, paused)` | Stop the clock indefinitely. |
| `SetDecayImmunity(src, seconds)` | Stop it for `seconds`, then it resumes on its own. |
| `IsDecayPaused(src)` | Whether either of the above is in effect. |
| `ApplyDecayNow(src)` | Charge whatever is owed right now. Returns what was lost. |

**Use `SetDecayImmunity`, not `SetDecayPaused`, for a consumable.** A pause with no expiry
that somebody forgets to clear is a character who never decays again.

```lua
-- "While this is in your system you do not lose condition"
exports['v-sport']:SetDecayImmunity(source, 48 * 3600)
```

Both of them move the decay anchors forward, so the protected period is **not** billed
retroactively when protection ends. A pause that saves the bill up is not a pause.

For a permanent, job-based exemption use `Config.Decay.exemptJobs` instead - it matches on job
name, job type and `gang:<name>`.

---

## Server exports: conditions — smoking, addiction, injury

**A habit is not an event.** `RemoveStat(src, 'stamina', 5)` models somebody who had one bad
cigarette. It does not model a smoker. What models a smoker is being *held back for as long as
they smoke*.

These are the three shapes that takes. None of them touches a stat at the moment it is applied,
which is exactly what makes them read as a condition rather than a punishment.

| Export | Effect |
|---|---|
| `SetStatCeiling(src, stat, value, seconds)` | Training on that stat cannot pass `value`. |
| `ClearStatCeiling(src[, stat])` | Lift one ceiling, or all of them. |
| `GetStatCeiling(src, stat)` | The ceiling in force, or `nil`. |
| `AddDrain(src, stat, perHour, seconds[, id])` | Lose `perHour` points an hour while it lasts. Returns an id. |
| `RemoveDrain(src[, id])` | Stop one drain, or all of them. |
| `GetDrains(src)` | Every active drain. |
| `SetDecayMultiplier(src, value, seconds)` | Decay runs `value` times faster. Below 1.0 slows it. |
| `GetDecayMultiplier(src)` | What is in force. 1.0 is normal. |
| `GetConditions(src)` | Everything active on a player, in one read. |
| `GetGainMultiplier(src, stat)` | The combined training multiplier right now. |

### A ceiling: "you can train, you just cannot get fit while you smoke"

```lua
exports['v-sport']:SetStatCeiling(source, 'stamina', 60.0, 0)
```

`seconds = 0` means until it is cleared, which is the right shape for a habit - your script
clears it when they quit. The player can still train, still play the minigame, still gain up to
60, and stops there.

By default a ceiling does **not** pull a stat that is already above it back down; it only stops
further gains. Taking up smoking should not delete last month's work.
`Config.Buffs.ceilingTrimsExisting = true` changes that if you disagree.

Bounded by `Config.Buffs.minStatCeiling` (10 by default), because a smoker whose stamina cannot
pass 60 is a mechanic and one whose stamina cannot pass 2 is a bug report.

### A drain: "your body is giving up while this is in your system"

```lua
exports['v-sport']:AddDrain(source, 'stamina', 1.5, 6 * 3600)
-- 1.5 stamina an hour for six hours: about nine points over a heavy night
```

Charged from **real elapsed time** on the same slow timer that re-checks decay, so the total
does not depend on that timer being punctual. It will never take a stat below its decay floor.

Bounded by `Config.Buffs.maxDrainPerHour` (10), which can already empty a maxed stat in ten
hours.

### Faster decay: "the gym costs you more when you smoke"

```lua
exports['v-sport']:SetDecayMultiplier(source, 2.0, 7 * 86400)
-- while they are a heavy smoker, a day off the gym costs 20 rather than 10
```

Below 1.0 slows decay down, which is a gentler alternative to `SetDecayImmunity` for something
that helps rather than protects. `0.0` is the same as immunity. Bounded by
`Config.Buffs.maxDecayMultiplier` (5).

### Reading what is active

```lua
local conditions = exports['v-sport']:GetConditions(source)
--[[ {
    buffs           = { { id = 'b3', stat = 'strength', amount = 20, expires = ... } },
    gainMultipliers = { strength = 2.0, breath = 1.0, stamina = 1.0 },
    ceilings        = { strength = nil, breath = nil, stamina = 60.0 },
    drains          = { { id = 'd1', stat = 'stamina', perHour = 1.5, expires = ... } },
    decayMultiplier = 2.0,
    decayPaused     = false,
    decayImmuneUntil = 0,
    blocked         = false,
    blockReason     = nil,
} ]]
```

### None of this survives a restart, and that is the right split

Ceilings, drains, buffs and the decay multiplier are **per session**. They are cleared on
disconnect and on a resource restart, exactly like buffs.

That is deliberate. v-sport holds the *transient effect*; the resource that owns the
*condition* - the addiction level, the cigarettes-per-day counter, the untreated injury - owns
persisting it, and re-applies on player load:

```lua
AddEventHandler('vsport:server:PlayerLoaded', function(src)
    local level = MySmokingScript.getAddictionLevel(src)   -- your own persisted state
    if level > 0 then
        exports['v-sport']:SetStatCeiling(src, 'stamina', 100 - level * 8, 0)
        exports['v-sport']:SetStatCeiling(src, 'breath', 100 - level * 12, 0)
        exports['v-sport']:SetDecayMultiplier(src, 1.0 + level * 0.25, 0)
    end
end)
```

A drain that outlived the server it was started on would belong to nobody.

---

## Server exports: packages

A drug is rarely one effect. Rather than six calls with six sets of error handling, hand
`ApplyPackage` a table and get back a record of what took.

| Export | Effect |
|---|---|
| `ApplyPackage(src, package)` | Apply a whole bundle. Returns what was applied. |
| `ClearPackage(src, applied)` | Undo it, using the record `ApplyPackage` returned. |

```lua
local applied = exports['v-sport']:ApplyPackage(source, {
    buffs       = { { stat = 'strength', amount = 20, seconds = 900 } },
    multipliers = { { stat = nil, value = 2.0, seconds = 900 } },   -- nil = every stat
    ceilings    = { { stat = 'stamina', value = 70, seconds = 900 } },
    drains      = { { stat = 'breath', perHour = 2.0, seconds = 3600 } },
    decayMultiplier = { value = 1.5, seconds = 86400 },
    decayImmunity   = nil,                    -- seconds
    exhaust     = { factor = 0.5, seconds = 120 },
    allowance   = 10,                         -- points of spent allowance refunded
    reduceRecovery = nil,                     -- seconds of shortened window
    stats       = { strength = -3 },          -- permanent changes
})

--[[ applied = {
    buffs = { 'b7' }, multipliers = { 'm8', 'm9', 'm10' },
    ceilings = { 'stamina' }, drains = { 'd2' },
    decayMultiplier = true, exhaust = true, allowance = true,
    stats = { strength = 39.5 },
} ]]

-- Later, to undo everything that is undoable:
exports['v-sport']:ClearPackage(source, applied)
```

Every field is optional, and an unknown field is **ignored rather than an error** - so a caller
written against a later version degrades instead of failing.

`ClearPackage` removes buffs, multipliers and drains by id, and clears the named ceilings and
the decay multiplier outright. It cannot undo `stats` (a permanent change is permanent) or
`allowance` (you cannot un-refund).

---

## Server exports: training control

| Export | Effect |
|---|---|
| `BlockTraining(src, blocked[, reason])` | Stop the player training at all. Ends any running session. |
| `IsTrainingBlocked(src)` | Whether they are blocked. |
| `IsTraining(src)` | Whether a workout is running. |
| `GetSession(src)` | `{ equipment, startedAt, coords }`, or `nil`. |
| `StopSession(src[, reason])` | End a running workout. |
| `GetCooldown(src, equipment)` | Seconds until they may use that equipment again. |
| `ClearCooldown(src[, equipment])` | Clear one cooldown, or all of them. |

`BlockTraining`'s `reason` is shown to the player, so write it for them:

```lua
exports['v-sport']:BlockTraining(source, true, 'You are in no state to be lifting anything')
-- ...later
exports['v-sport']:BlockTraining(source, false)
```

---

## Server exports: the body

These reach through to the client and act on the ped directly. They have nothing to do with
the stats, which is usually what a drug script actually wants: "this character cannot run for
a minute", not "this character's stamina is temporarily lower".

| Export | Effect |
|---|---|
| `Exhaust(src, factor, seconds)` | Wind the player. `factor` is how much sprint bonus survives; `0` removes the sprint key. |
| `RestoreStamina(src, fraction)` | Refill the sprint bar. `fraction` is 0..1. |
| `GetCustomEquipment()` | The equipment added in game, as an `ExtraEquipment`-shaped table. |
| `GetItemBlocks(inventory)` | The item registration block for `'qb-core'`, `'ox_inventory'` or `'esx'`, as lines. |
| `SetEffectOverride(src, name, value, seconds, mode)` | Force one effect, bypassing its stat. |
| `ClearEffectOverride(src[, name])` | Clear one override, or all of them. |
| `GetCarryWeight(src)` | The carry weight strength has earned, or `nil`. |

```lua
exports['v-sport']:Exhaust(source, 0.0, 45)     -- cannot sprint at all for 45 seconds
exports['v-sport']:Exhaust(source, 0.4, 120)    -- winded for two minutes
```

**What `Exhaust` can and cannot do.** GTA exposes `RestorePlayerStamina`, which *fills* the
sprint bar, and nothing that empties it or sets it to a value. There is no `SetPlayerStamina`.
So exhaustion is implemented as what a drained player experiences - the sprint bonus is scaled
by `factor`, and at `factor = 0` the sprint control is disabled outright. You get a character
who cannot run away. You cannot get a specific bar value, because the engine will not give
anybody one.

`SetEffectOverride`'s `name` is a key from `Config.Effects`: `meleeDamage`, `meleeDefense`,
`underwaterTime`, `swimSpeed`, `sprintSpeed`, `healthRecharge`, `maxHealth`. `mode` is `'set'`
or `'multiply'`; `seconds = 0` means until cleared.

```lua
-- Everything is a bit slower and a bit softer while high
exports['v-sport']:SetEffectOverride(source, 'sprintSpeed', 0.85, 300, 'multiply')
exports['v-sport']:SetEffectOverride(source, 'meleeDamage', 1.4, 300, 'set')
```

`GetCarryWeight` is read-only and nothing applies it: inventories all handle weight
differently and this resource does not reach into somebody else's. Read it from your own
inventory's weight calculation. It returns `nil` unless
`Config.Effects.strength.carryWeight.enabled` is on.

---

## Server exports: items

| Export | Effect |
|---|---|
| `UseItem(src, configKey)` | Run a `Config.Items` entry. Returns whether the item should be consumed. |
| `GetItems()` | What is configured, and what each does. |

For an inventory v-sport does not know about. See [ITEMS.md](ITEMS.md).

```lua
local shouldConsume = exports['v-sport']:UseItem(source, 'whey')
if shouldConsume then
    -- remove one, however your inventory does that
end
```

---

## Client events, for a radial menu

Net events rather than exports, so a resource that loads **before** v-sport can still reference
them - an export has to exist at the moment it is called, an event does not.

| Event | Effect |
|---|---|
| `vsport:client:OpenPanel` | Open the stats panel |
| `vsport:client:ClosePanel` | Close it |
| `vsport:client:TogglePanel` | Toggle it |
| `vsport:client:StartNearest` | Start a workout on the nearest usable equipment. Optional argument names the exercise. |
| `vsport:client:StartAnywhere` | Start an exercise that needs no equipment. Argument is the exercise key. |
| `vsport:client:PushUps` | Shorthand for `StartAnywhere('push_ups')` |
| `vsport:client:SitUps` | Shorthand for `StartAnywhere('sit_ups')` |
| `vsport:client:Yoga` | Shorthand for `StartAnywhere('yoga')` |
| `vsport:client:Stretch` | Shorthand for `StartAnywhere('stretching')` |
| `vsport:client:StopSession` | End a running workout |

The shorthands exist because most radial menus can fire an event but cannot pass it an argument.

### qb-radialmenu

Paste into `qb-radialmenu/config.lua`, in `Config.MenuItems`:

```lua
{
    id = 'vsport',
    title = 'Condition physique',
    icon = 'dumbbell',
    type = 'client',
    event = 'vsport:client:OpenPanel',
    shouldClose = true,
},
```

To also offer "train here" on the wheel, which only shows up when there is something to train
on, add a second entry and let the resource refuse when nothing is in range:

```lua
{
    id = 'vsport_train',
    title = 'S\'entrainer',
    icon = 'person-running',
    type = 'client',
    event = 'vsport:client:StartNearest',
    shouldClose = true,
},
```

`StartNearest` shows the player the reason when it refuses - too far, on cooldown, allowance
spent - so it does not need a `canInteract`.

### Push-ups and yoga anywhere, from the F1 wheel

Push-ups need a floor and yoga needs somewhere to sit. Neither needs a prop, so there is nothing
in the world to walk up to and press E on — the **menu is the interaction**. A submenu:

```lua
{
    id = 'vsport_bodyweight',
    title = 'Exercices',
    icon = 'dumbbell',
    items = {
        {
            id = 'vsport_pushups',
            title = 'Pompes',
            icon = 'person-falling',
            type = 'client',
            event = 'vsport:client:PushUps',
            shouldClose = true,
        },
        {
            id = 'vsport_situps',
            title = 'Abdominaux',
            icon = 'person-running',
            type = 'client',
            event = 'vsport:client:SitUps',
            shouldClose = true,
        },
        {
            id = 'vsport_yoga',
            title = 'Yoga',
            icon = 'spa',
            type = 'client',
            event = 'vsport:client:Yoga',
            shouldClose = true,
        },
        {
            id = 'vsport_stretch',
            title = 'Etirements',
            icon = 'child-reaching',
            type = 'client',
            event = 'vsport:client:Stretch',
            shouldClose = true,
        },
    },
},
```

Which exercises are allowed this way is `Config.Anywhere.allowed`, and **the server enforces that
list from its own copy** — a client asking to bench press in mid-air is refused. The full
progression applies: the allowance, fatigue, cooldowns and the minigame are all the same as at a
real bench, so this is not a way around anything.

To build the menu from the config instead of hardcoding it:

```lua
local exercises = exports['v-sport']:GetAnywhereExercises()
-- { { key = 'push_ups', label = 'Push-ups', description = '...', cooldownLeft = 0 }, ... }

for _, exercise in ipairs(exercises) do
    -- exports['v-sport']:StartAnywhere(exercise.key)
end
```

It refuses on ground too steep to lie down on (`Config.Anywhere.maxGroundAngle`) and tells the
player why. `Config.Anywhere.gainScale` makes these worth less than the same exercise on a mat if
you want a reason to visit a gym; it ships at 1.0, because a push-up is a push-up.

### ox_lib radial

```lua
lib.registerRadial({
    id = 'vsport_radial',
    items = {
        { label = 'Condition', icon = 'dumbbell', onSelect = function()
            TriggerEvent('vsport:client:OpenPanel')
        end },
        { label = 'S\'entrainer', icon = 'person-running', onSelect = function()
            TriggerEvent('vsport:client:StartNearest')
        end },
    },
})
```

### Anything else

Any resource that can fire a client event can open the panel:

```lua
TriggerEvent('vsport:client:OpenPanel')
```

---

## Client exports

| Export | Returns |
|---|---|
| `GetStats()` | The local player's trained values. |
| `GetEffectiveStats()` | With buffs folded in. |
| `GetStat(stat)` / `GetEffectiveStat(stat)` | One value, or 0. |
| `GetBuffs()` | The active buff list. |
| `IsReady()` | Whether stats have loaded. |
| `IsTraining()` | Whether a workout is running. |
| `GetSession()` | `{ equipment, label, startedAt, reps }`, or `nil`. |
| `StopSession([reason])` | End the running workout. |
| `StartNearest([equipment])` | Start one on the nearest usable equipment. |
| `GetNearbyEquipment()` | Everything in detection range. Allocates - not for a per-frame call. |
| `StartAnywhere(equipment)` | Start an exercise that needs no equipment, where the player stands. |
| `GetAnywhereExercises()` | The list of those, with labels and live cooldowns. |
| `IsAnywhereExercise(equipment)` | Whether that one key can be done without equipment. |
| `OpenPanel()` / `ClosePanel()` / `IsPanelOpen()` | The stats panel. |
| `GetEffectValue(stat, effectName)` | The computed value of one effect right now. |
| `GetEquipment()` | The catalogue, with labels, gains and live cooldowns. |
| `Exhaust(factor, seconds)` | Wind the local player. |
| `RestoreStamina(fraction)` | Refill the sprint bar. |
| `GetExhaustion()` | `winded, secondsLeft`. |
| `SetEffectOverride(name, value, seconds, mode)` | As the server export. |
| `ClearEffectOverride([name])` | Clear one override. |
| `ClearEffectOverrides()` | Clear every override at once. |

```lua
local nearby = exports['v-sport']:GetNearbyEquipment()
--[[ { {
    equipment = { 'push_ups', 'sit_ups', 'yoga', 'stretching' },   -- a yoga mat
    coords = vector3(...), distance = 1.8, busy = false, isSpot = false,
} } ]]
```

---

## Events this resource fires

Listen for these instead of polling.

### Server

| Event | Arguments | When |
|---|---|---|
| `vsport:server:PlayerLoaded` | `src, stats` | A character's stats have loaded. |
| `vsport:server:SessionStarted` | `src, equipment` | A workout was authorised. |
| `vsport:server:SessionCompleted` | `src, equipment, gains, quality` | A workout paid out. |
| `vsport:server:StatChanged` | `src, stat, before, after` | Any change outside a session. |
| `vsport:server:StatsReset` | `src` | `ResetStats` was called. |
| `vsport:server:BuffExpired` | `src, id, stat` | A buff or multiplier ran out. |
| `vsport:server:ItemUsed` | `src, configKey, effect` | A `Config.Items` entry was used. |
| `vsport:server:CheatSuspected` | `src, reason, detail` | Rejections passed the threshold. |

**`vsport:server:CheatSuspected` is the hook for your anticheat.** v-sport never kicks or bans
anybody itself. One rejection is a desync; the event only fires once a player has collected
`Config.Security.suspicionThreshold` of them inside an hour.

**`vsport:server:BuffExpired` is how you build a comedown.** Buffs applied by a `Config.Items`
entry carry the id `item:<config key>`:

```lua
AddEventHandler('vsport:server:BuffExpired', function(src, id, stat)
    if id == 'item:steroids' then
        exports['v-sport']:ApplyDebuff(src, 'strength', 10, 600)
        exports['v-sport']:Exhaust(src, 0.2, 120)
    end
end)
```

### Client

| Event | Arguments | When |
|---|---|---|
| `vsport:client:Ready` | `stats` | The first sync arrived. |
| `vsport:client:StatsChanged` | `trained, effective` | Any change. |
| `vsport:client:BuffsChanged` | `buffs, multipliers` | The buff lists changed. |
| `vsport:client:BuffExpired` | `id, stat` | A buff ran out. |
| `vsport:client:SessionStarted` | `equipment, label` | A workout began. |
| `vsport:client:SessionEnded` | `equipment, result` | A workout ended. `result` is `nil` if it never really started. |

```lua
AddEventHandler('vsport:client:SessionEnded', function(equipment, result)
    if result and result.status == 'complete' then
        print(('finished %s with %.0f%% form'):format(equipment, result.quality * 100))
    end
end)
```

---

## State bags

The cheapest way to read a player's stats: no export call, no round trip.

```lua
-- Server, any player
local stats = Player(source).state.sportStats

-- Client, the local player
local stats = LocalPlayer.state.sportStats
```

Written only when a value actually changes, and at most once per
`Config.Performance.stateBagInterval` (2s). Turn it off with
`Config.Performance.stateBags = false` if nothing on your server reads it.

Reading **another** player's stats on the client needs
`Config.Performance.stateBagReplicated = true`, which is off by default because it is one
network message per player per change.

---

## Worked examples

### A performance-enhancing drug

Doubles training and makes you stronger, then costs you for it.

```lua
-- server side
RegisterNetEvent('mydrugs:server:useSteroids', function()
    local src = source
    if not exports['v-sport']:IsReady(src) then return end

    exports['v-sport']:ApplyBuff(src, 'strength', 20, 900, 'steroid')
    exports['v-sport']:ApplyMultiplier(src, nil, 2.0, 900, 'steroid_gains')
    exports['v-sport']:SetDecayImmunity(src, 24 * 3600)

    -- The comedown, fifteen minutes later
    SetTimeout(900 * 1000, function()
        if not exports['v-sport']:IsReady(src) then return end
        exports['v-sport']:ApplyDebuff(src, 'strength', 12, 1200)
        exports['v-sport']:ApplyMultiplier(src, nil, 0.5, 1200)
        exports['v-sport']:Exhaust(src, 0.1, 180)
    end)
end)
```

### Smoking — a habit that holds you back

This is the shape most people are actually looking for. Nothing is deducted when they light up;
they are simply worse off for as long as they smoke.

```lua
-- Your resource owns the habit. v-sport owns what it does to the body.
local cigarettesToday = {}     -- src -> count, your own persisted state

local function applyHabit(src)
    local level = math.min(5, math.floor((cigarettesToday[src] or 0) / 4))   -- 0..5

    if level == 0 then
        exports['v-sport']:ClearStatCeiling(src)
        exports['v-sport']:SetDecayMultiplier(src, 1.0, 0)
        exports['v-sport']:RemoveDrain(src)
        return
    end

    -- Lungs first, then stamina. A pack-a-day smoker tops out around 40 lung capacity.
    exports['v-sport']:SetStatCeiling(src, 'breath',  100 - level * 12, 0)
    exports['v-sport']:SetStatCeiling(src, 'stamina', 100 - level * 8,  0)

    -- Condition slips away faster than it would otherwise.
    exports['v-sport']:SetDecayMultiplier(src, 1.0 + level * 0.2, 0)
end

RegisterNetEvent('mysmoking:server:smoked', function()
    local src = source
    cigarettesToday[src] = (cigarettesToday[src] or 0) + 1

    -- The immediate hit: winded for a moment, and a small ongoing cost.
    exports['v-sport']:Exhaust(src, 0.5, 45)
    exports['v-sport']:AddDrain(src, 'breath', 0.4, 3600, 'smoke:' .. src)

    applyHabit(src)
end)

-- Re-apply on load: v-sport does not persist conditions, your resource does.
AddEventHandler('vsport:server:PlayerLoaded', function(src)
    cigarettesToday[src] = MySmoking.loadCount(src)
    applyHabit(src)
end)

-- Quitting lifts everything.
RegisterNetEvent('mysmoking:server:quit', function()
    cigarettesToday[source] = 0
    applyHabit(source)
end)
```

The player can still go to the gym. They can still train stamina. They just cannot get past 60,
and everyone who does not smoke can. That reads as a consequence rather than as a fine.

### Drug abuse — using too much costs you your condition

```lua
local doses = {}    -- src -> doses in the last day, your own state

RegisterNetEvent('mydrugs:server:used', function(drug)
    local src = source
    doses[src] = (doses[src] or 0) + 1

    if doses[src] <= 2 then
        -- Moderate use: the good part only.
        exports['v-sport']:ApplyPackage(src, {
            multipliers = { { stat = nil, value = 1.5, seconds = 1200 } },
            buffs = { { stat = 'strength', amount = 10, seconds = 1200 } },
        })
        return
    end

    -- Past the third dose it starts taking things. Permanent loss, plus a condition that
    -- lingers, plus faster decay - the three ways of saying "you did this to yourself".
    exports['v-sport']:ApplyPackage(src, {
        stats = { strength = -2, stamina = -3, breath = -3 },
        ceilings = {
            { stat = 'stamina', value = 65, seconds = 24 * 3600 },
            { stat = 'breath',  value = 55, seconds = 24 * 3600 },
        },
        drains = { { stat = 'stamina', perHour = 1.0, seconds = 8 * 3600 } },
        decayMultiplier = { value = 2.0, seconds = 48 * 3600 },
        exhaust = { factor = 0.0, seconds = 90 },
    })

    exports['v-sport']:BlockTraining(src, true, 'Your body has had enough for today')
    SetTimeout(4 * 3600 * 1000, function()
        exports['v-sport']:BlockTraining(src, false)
    end)
end)
```

### A drug that doubles gains and pays out in one category

```lua
RegisterNetEvent('mydrugs:server:useBooster', function()
    local src = source

    local applied = exports['v-sport']:ApplyPackage(src, {
        -- Everything trains twice as fast for half an hour
        multipliers = { { stat = nil, value = 2.0, seconds = 1800, id = 'booster' } },

        -- And a straight gift of five strength points, which counts against their
        -- allowance because `respectAllowance` is what AddStat would need - here it is a
        -- flat grant, so it does not.
        stats = { strength = 5 },

        -- The recovery timer is pushed back so they can actually use the half hour
        allowance = 15,

        -- No condition loss while it is in their system
        decayImmunity = 6 * 3600,
    })

    -- The comedown, wired to the multiplier running out rather than to a second timer.
    SetTimeout(1800 * 1000, function()
        exports['v-sport']:ApplyPackage(src, {
            multipliers = { { stat = nil, value = 0.5, seconds = 1800 } },
            drains = { { stat = 'stamina', perHour = 1.5, seconds = 1800 } },
            exhaust = { factor = 0.2, seconds = 120 },
        })
    end)
end)
```

Note the shape: **one call in, one record out.** `applied` can be handed straight to
`ClearPackage` if something needs to cancel the whole thing early — an ambulance treating them,
for instance.

### A recovery supplement that skips the wait

```lua
RegisterNetEvent('mydrugs:server:useRecovery', function()
    local src = source
    local allowance = exports['v-sport']:GetAllowance(src)
    if not allowance then return end

    if (allowance.spent.total or 0) <= 0 then
        -- Nothing to recover from. Do not eat the item.
        return
    end

    -- Half the spent allowance back, and the short window for a day
    exports['v-sport']:AddAllowance(src, (allowance.spent.total or 0) * 0.5)
    exports['v-sport']:ReduceRecovery(src, 24 * 3600)
end)
```

### A downer that leaves you useless

No stat is touched: the character is just physically worse for a while.

```lua
RegisterNetEvent('mydrugs:server:useDowner', function()
    local src = source

    exports['v-sport']:Exhaust(src, 0.0, 90)                                    -- no sprint
    exports['v-sport']:SetEffectOverride(src, 'meleeDamage', 0.7, 300, 'multiply')
    exports['v-sport']:SetEffectOverride(src, 'swimSpeed', 1.0, 300, 'set')
    exports['v-sport']:BlockTraining(src, true, 'Not in this state')

    SetTimeout(300 * 1000, function()
        exports['v-sport']:ClearEffectOverride(src)
        exports['v-sport']:BlockTraining(src, false)
    end)
end)
```

### A gym membership that gates the equipment

Two ways, and the config one is better.

```lua
-- Config-driven: no code at all. In Config.ExtraEquipment:
bench_press = { require = { item = 'gym_membership' } },
```

```lua
-- Or dynamically, if membership is not an item:
AddEventHandler('vsport:server:SessionStarted', function(src, equipment)
    if not hasMembership(src) then
        exports['v-sport']:StopSession(src, 'no membership')
    end
end)
```

The config version refuses before the workout starts and tells the player why. The dynamic
version stops it a moment after it began. Prefer the config version.

### A leaderboard command

```lua
RegisterCommand('strongest', function(src)
    local rows = exports['v-sport']:GetLeaderboard('strength', 10)
    for index, row in ipairs(rows) do
        print(('%2d. %s  %.1f'):format(index, row.identifier, row.value))
    end
end, false)
```

---
---

# API (Version Française)

Cette page est maintenue en anglais, comme le code. Les points qu'il faut connaître avant de
brancher quoi que ce soit dessus :

**Conventions.** Un mauvais argument renvoie `nil` ou `false` ; rien ne lève d'erreur. Les
tables renvoyées sont des copies. Un joueur inconnu ou pas encore chargé n'est pas une erreur.
Les changements sont bornés par `Config.Buffs.maxSingleChange`. Chaque export serveur a un
équivalent en événement `vsport:server:<Nom>`.

**Les appels qui couvrent l'essentiel pour un script de drogue ou de fumette :**

```lua
-- Booster
exports['v-sport']:ApplyMultiplier(source, nil, 2.0, 1800)   -- gains x2 pendant 30 min
exports['v-sport']:ApplyBuff(source, 'strength', 20, 600)    -- +20 force temporaire
exports['v-sport']:AddStat(source, 'strength', 5)            -- 5 points definitifs
exports['v-sport']:SetDecayImmunity(source, 24 * 3600)       -- pas de perte pendant 24 h
exports['v-sport']:AddAllowance(source, 15)                  -- rend du quota consomme
exports['v-sport']:ResetAllowance(source)                    -- contourne tout le quota
exports['v-sport']:ReduceRecovery(source, 25 * 3600)         -- ce que fait la whey

-- Penaliser
exports['v-sport']:ApplyDebuff(source, 'stamina', 25, 600)   -- -25 endurance temporaire
exports['v-sport']:RemoveStat(source, 'stamina', 3)          -- 3 points perdus definitivement
exports['v-sport']:Exhaust(source, 0.0, 60)                  -- ne peut plus sprinter

-- Une HABITUDE, pas un evenement. C'est la partie qui manquait :
exports['v-sport']:SetStatCeiling(source, 'breath', 55.0, 0) -- fumeur : plafonne a 55 d'apnee
exports['v-sport']:AddDrain(source, 'stamina', 1.5, 3600)    -- perd 1,5/h pendant une heure
exports['v-sport']:SetDecayMultiplier(source, 2.0, 86400)    -- perd 20/jour au lieu de 10

-- Tout d'un coup, et l'annuler d'un coup
local applied = exports['v-sport']:ApplyPackage(source, { ... })
exports['v-sport']:ClearPackage(source, applied)
```

**Le point important : une habitude n'est pas un evenement.** `RemoveStat(src, 'stamina', 5)`
modelise quelqu'un qui a mal fume une fois. Ce qui modelise un fumeur, c'est d'etre **bride tant
qu'il fume** : un plafond de statistique, un drain continu, une perte accelérée. Aucun des trois
ne touche une statistique au moment ou il est pose, et c'est ce qui les fait ressentir comme une
condition plutot que comme une amende.

**Rien de tout ca ne survit a un redemarrage, volontairement.** v-sport detient l'effet
transitoire ; la ressource qui detient la *condition* (le niveau d'addiction, le nombre de
cigarettes, la blessure non soignee) detient sa persistance et re-applique sur
`vsport:server:PlayerLoaded`. La section anglaise contient l'exemple complet.

Les exemples travailles complets - fumette avec niveaux d'habitude, abus de drogue qui coute des
points, et booster x2 avec descente - sont dans la section anglaise sous *Worked examples*.

**Les buffs ne touchent pas la valeur entraînée.** Ils s'ajoutent à la valeur *effective* :
dès l'expiration, le personnage est exactement là où il était. C'est ce qui les rend
réellement temporaires. Ils ne survivent pas à un redémarrage du serveur, volontairement.

**Utilisez `SetDecayImmunity`, pas `SetDecayPaused`, pour un consommable.** Une pause sans
expiration que personne ne retire donne un personnage qui ne perd plus jamais rien. Les deux
avancent les ancres de perte : la période protégée n'est donc pas facturée rétroactivement.

**`ReduceRecovery(src, secondes)` : l'argument est la durée du bonus, pas la nouvelle
fenêtre.** La nouvelle fenêtre vient de `Config.Allowance.reducedWindow`.

**`AddAllowance` contre `ResetAllowance`.** Le premier est un remboursement partiel et
équilibrable, c'est ce qu'un consommable devrait faire. Le second retire complètement le
système de récupération pour ce cycle : réservez-le à un outil d'admin ou à un item vraiment
coûteux.

**Ce que `Exhaust` peut et ne peut pas faire.** GTA expose `RestorePlayerStamina`, qui
*remplit* la barre de sprint, et rien qui la vide ou la fixe à une valeur. Il n'existe pas de
`SetPlayerStamina`. L'épuisement est donc implémenté comme ce que vit un joueur épuisé : le
bonus de sprint est réduit par `factor`, et à `factor = 0` la touche de sprint est désactivée.
Vous obtenez un personnage qui ne peut pas s'enfuir. Vous ne pouvez pas obtenir une valeur de
barre précise, parce que le moteur ne la donne à personne.

**`vsport:server:CheatSuspected` est le point d'accroche de votre anticheat.** v-sport
n'expulse et ne bannit jamais personne. Un rejet isolé est une désynchronisation ;
l'événement ne part qu'après `Config.Security.suspicionThreshold` rejets dans l'heure.

**`AddSession` contre `AddStat`.** `AddSession` passe par toute la chaîne (fatigue,
multiplicateurs, quota, paliers, événements) : c'est ce qu'un PNJ coach doit utiliser.
`AddStat` contourne tout, comme une commande d'admin.

**State bags.** `Player(source).state.sportStats` côté serveur,
`LocalPlayer.state.sportStats` côté client. Écrit uniquement en cas de changement réel, au
maximum toutes les 2 secondes. Lire les stats d'un *autre* joueur côté client demande
`Config.Performance.stateBagReplicated = true`, désactivé par défaut car cela coûte un message
réseau par joueur et par changement.

Les tableaux d'exports complets, les signatures et les exemples complets (drogue dopante,
supplément de récupération, calmant, abonnement de salle, classement) sont dans la section
anglaise ci-dessus.
