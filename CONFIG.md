# Configuration

The server owner's guide. `config.lua` itself is heavily commented and is the reference; this
file is the part that does not fit in comments - how the pieces interact, and what to change
when you want a particular outcome.

## Contents

- [The four numbers that decide everything](#the-four-numbers-that-decide-everything)
- [Balancing: how long should a maxed character take?](#balancing-how-long-should-a-maxed-character-take)
- [The effect table: what a maxed character actually gets](#the-effect-table-what-a-maxed-character-actually-gets)
- [Finding the sport props on your own map](#finding-the-sport-props-on-your-own-map)
- [Equipment baked into an MLO](#equipment-baked-into-an-mlo)
- [Adding or changing equipment](#adding-or-changing-equipment)
- [Passive training: running, cycling, swimming, diving](#passive-training-running-cycling-swimming-diving)
- [Aligning a body onto a prop](#aligning-a-body-onto-a-prop)
- [Adding a fourth stat](#adding-a-fourth-stat)
- [Commands, and who may run them](#commands-and-who-may-run-them)
- [Exercises with no equipment at all](#exercises-with-no-equipment-at-all)
- [The database](#the-database)
- [Notifications and the interface](#notifications-and-the-interface)
- [The minigame](#the-minigame)
- [Performance](#performance)
- [Anti-cheat, honestly](#anti-cheat-honestly)
- [Common recipes](#common-recipes)

---

## The four numbers that decide everything

Read these together. Changing one without the others is how a server ends up either trivial or
impossible.

```lua
Config.Allowance.total   = 24.0          -- points per cycle, across every stat
Config.Allowance.perStat = 12.0          -- ...and into any single stat
Config.Allowance.window  = 25 * 3600     -- how long a spent allowance takes to come back
Config.Decay.amount      = 5.0           -- points lost per day of not training
```

The relationship is the design:

- **The allowance is the ceiling on a day.** A player cannot out-grind it. Logging in for
  twelve hours is worth no more than logging in for one, which is the point.
- **Fatigue is the pace inside a day, and it is the number that actually decides how long a
  maxed character takes.** The first three workouts of an evening are worth more than the next
  thirty combined, so nobody realistically *reaches* the allowance ceiling: eight sessions
  spread across an evening measure at about **3.5 points**, against an allowance of 24.
- **Decay is the pressure to keep coming back.** -5 per day of absence against those 3.5 a
  day of gains, so a player who trains every other day roughly stands still. It was -10 and read
  as too harsh in play: two days away cost a fifth of everything, which stops people logging in
  rather than making them train. Note that it changes progression by nothing, because the one-day
  grace means a player who trains daily never decays at all - it is a dial on what absence costs.
- **Peak protection is what stops that being futile.** At 20, a character who once reached 80
  never falls below 60 however long they are gone.

Two consequences worth understanding before tuning anything:

**The ceiling is something you hold, not something you reach and bank.** If that is not what
you want, raise `Config.Decay.grace`, lower `Config.Decay.amount`, or raise
`Config.Decay.peakProtection`.

**Whey buys back the wall, not the road.** It shortens the allowance recovery, which only
matters to a player who genuinely trained enough to hit the ceiling. For a player limited by
fatigue - which is most players most days - it does nothing. That is the correct behaviour: it
is a way to make a heavy day possible, not a way to shorten the month.

---

## Balancing: how long should a maxed character take?

`Config.Stats.*.sessionsToMax` decides the number of **sessions** (100 by default, so one
perfect session is worth one point). Three stats is therefore 300 sessions, and how long those
take is decided by how many a player gets through in a day.

Measured against the real progression functions, day by day, with the allowance ledger and the
decay rules in play. **All three stats to 100%:**

| Player | Sessions/day | Form | Days |
|---|---|---|---|
| Casual, one rest day in three | 9 | 85% | ~59 |
| Dedicated, one rest day a week | 18 | 90% | ~22 |
| Dedicated, every day | 21 | 90% | ~16 |
| **Dedicated, every day, plays the QTE well** | **21** | **100%** | **~16** |
| Tries to grind it | 60 requested, 28 fit | 100% | ~15 |

**A fortnight is the design target**, and the last row is the one that matters most: a player
attempting sixty sessions a day gets fifteen days against the dedicated player's sixteen.
**Grinding buys one day.** The allowance stops paying long before the day runs out, and most of
those sessions are refused outright - only about 28 even fit into 24 hours at a realistic pace.

That row used to read `~5 days`, and it was wrong: the simulator let a simulated day run past 24
hours whenever a scenario asked for more sessions than fit in one. See ERROR_LOG.md. The corrected
figure is much better news than the claim it replaces.

### To make it slower or faster

Three levers, in the order you should reach for them:

1. **`Config.Stats.*.sessionsToMax`** — the honest one. 150 makes everything take half again as
   long, uniformly and predictably. This is the knob to use.
2. **`Config.Allowance.total`** — lowers the *floor*, which is what a grinder hits. At the shipped
   24 there is barely a floor left: a player attempting sixty sessions a day measures at **fifteen
   days** against the dedicated player's sixteen, because the allowance refuses most of those
   sessions. Grinding buys one day. Raising `total` back to 30 restores the old thirteen-day
   headline and hands the grinder six days; going below about 22 makes the allowance, rather than
   fatigue, what every ordinary player feels. See the trade-off note in section 5b.
3. **`Config.Progression.fatigue`** — anti-macro, not pace. At the defaults it costs a hard hour
   at the gym about 10% of its value. Making it harsh enough to set the pace is what turns a
   fortnight into three months, and it is a bad way to do it: the player just sees their gains
   quietly shrink with no explanation.

**Do not let the allowance become the pace.** If `Config.Allowance.total` drops near what an
ordinary player banks in a day, the fatigue curve stops mattering, every session feels
arbitrary, and the whole thing reads as a random refusal. Keep the wall above the road.

Three internally consistent presets - arcade, default, hardcore - are written out at the end of
section 5 in `config.lua`, ready to paste. Each one moves the allowance, the fatigue curve and
the decay together, because they only make sense together.

### Rolling or block recovery

```lua
Config.Allowance.mode = 'rolling'
```

- **`'rolling'`** - each point frees itself exactly `window` seconds after it was earned, so
  the allowance trickles back. A player is never fully locked out for a whole day. Fairer, and
  the default.
- **`'block'`** - the whole allowance resets at once, `window` after the first point of the
  cycle. Simpler to explain, harsher to be on the wrong side of.

### Whey

`Config.Allowance.reducedWindow` (8h by default) is the window a player gets after taking whey.
That is the entire mechanic: a consumable that turns a 25 hour wait into an 8 hour one. See
[ITEMS.md](ITEMS.md) to add the item, and `ReduceRecovery` in [API.md](API.md) to drive it from
your own resource.

### Turning the allowance off entirely

```lua
Config.Allowance.enabled = false
```

Fatigue then becomes the only limiter, and a determined player reaches 100% in roughly five
days of hard grinding. Not recommended, and stated plainly in the config so nobody does it by
accident.

---

## The effect table: what a maxed character actually gets

At the shipped defaults, a character at 100% in everything:

| | Vanilla | At 100% | Native |
|---|---|---|---|
| Unarmed and melee damage | 1.0 | **1.25** | `SetPlayerMeleeWeaponDamageModifier` |
| Melee damage taken | 1.0 | **/1.15** | `SetPlayerMeleeWeaponDefenseModifier` |
| Seconds underwater | ~45 | **75** | `SetPedMaxTimeUnderwater` |
| Swim speed | 1.0 | **1.12** | `SetSwimMultiplierForPlayer` |
| Sprint speed | 1.0 | **1.12** | `SetRunSprintMultiplierForPlayer` |
| Health regeneration | 1.0 | **1.30** | `SetPlayerHealthRechargeMultiplier` |
| Stamina recovery | - | **+20%/s** while stood still | `RestorePlayerStamina` |
| Max health | 200 | **off by default** | `SetEntityMaxHealth` |

That is a fit person, not a superhero. A trained character wins a fist fight against an
untrained one and does not one-shot a stranger.

**Two knobs move all of it:**

```lua
Config.Effects.enabled     = false   -- stats become a pure roleplay number, nothing else
Config.Effects.globalScale = 0.5     -- every bonus at half strength
```

`globalScale` interpolates back towards the vanilla value, so it can never push a multiplier
*below* what base GTA does.

### The GTA character stats

```lua
Config.Effects.writeGameStats = true
```

Separately from the table above, v-sport writes the real character stats the engine already
has: `MP0_STRENGTH`, `MP0_STAMINA`, `MP0_LUNG_CAPACITY` (and their `SP0_` twins, since which
slot is live depends on your framework).

This is the honest path and it is why the three stats are what they are: GTA already models
strength, stamina and lung capacity, so writing the real value gives the player exactly the
behaviour the base game intended for a maxed character. It is bounded by the game rather than
by this config, and it costs nothing.

### Engine ceilings you cannot raise

`SetSwimMultiplierForPlayer` and `SetRunSprintMultiplierForPlayer` are **ignored above 1.49**
by the engine. Setting `max = 2.0` gets you 1.49 and a config that lies about what it does. The
values are clamped before they are written so the resource does not pretend otherwise.

### Max health

Off by default and it should usually stay off. Most frameworks, every ambulance job and every
armour script assume 200 and will fight this. If you turn it on, test it against your medical
resource first.

---

## Finding the sport props on your own map

The shipped catalogue in `shared/equipment.lua` covers the base-game sport props and a spread
of names used by common gym MLOs - 17 exercises across 30 verified model names. **It cannot know what
your map has.** No shipped list can.

So: stand in your gym and run

```
/vsportscan
```

It lists every object within 20 metres, nearest first, with:

- the distance
- `YES` or `-` for whether the catalogue already knows it
- the model name where it can be resolved, and the raw hash where it cannot
- which exercises it offers, for the known ones

Anything marked `-` is a prop your map has and this resource does not. Add it to
`Config.ExtraEquipment` (section 9b) and it becomes usable.

```
/vsportscan 8
```

...for a tighter radius in a crowded interior.

**A model name that does not exist in your game costs nothing.** It hashes to a number no
entity will ever carry, so it simply never matches. That is why the shipped lists are
generous and include several spellings of the same idea - over-listing is free, under-listing
means a prop nobody can use. Be generous in your own additions too.

Where a name cannot be resolved, add the hash as a number instead of a string:

```lua
Config.ExtraEquipment = {
    bench_press = {
        models = { 'prop_gym_bench_01', 'prop_gym_bench_02', 'prop_gym_bench_03',
                   'mygym_bench_a', 1234567890 },
    },
}
```

Note that an entry with an existing key **patches** the shipped one, so three extra models is
three lines rather than a restated block. A key that does not exist creates new equipment.

### Seeing what was matched, in game

```lua
Config.Debug.drawDetected = true
```

Draws a label over every prop the scan matched, with its exercises and distance, and `[BUSY]`
when somebody else is on it. The fastest way to find out why a bench is offering nothing.

---

## Equipment baked into an MLO

Some gym equipment in a custom MLO is part of the map model rather than placed as an object.
There is no entity, so there is nothing for a scan to find. Those need a coordinate.

Stand where the player should be and run:

```
/vsportspot pull_ups
```

It prints a ready-to-paste line:

```lua
{ equipment = 'pull_ups', coords = vector3(-1202.44, -1566.10, 3.62), heading = 35.0 },
```

Paste it into `Config.Spots` (section 9). The `z` is your position minus 1.0, which puts it on
the floor.

Static spots keep the built-in key prompt even on a server that uses ox_target or qb-target,
because a target has nothing to attach to. They can also carry their own label, radius, marker
and job restriction - see the field list in section 9.

```lua
Config.Debug.drawSpots = true
```

...draws them as spheres so you can see where they actually landed.

---

## Adding or changing equipment

Everything about a piece of equipment lives in one entry. The field list is at the top of
`shared/equipment.lua`. The fields that matter most:

```lua
Config.ExtraEquipment = {
    squat_rack = {
        order = 14,
        label = 'Squat rack',              -- plain text is fine; a locale key is used if it exists
        description = 'Heavy compound lifting.',
        models = { 'mygym_squatrack' },

        -- What one PERFECT session is worth, in SESSIONS of that stat.
        -- 1.0 = one full session = one point at the default sessionsToMax.
        gains = { strength = 1.2 },

        reps = 6,                          -- how many repetitions the minigame asks for
        difficulty = 'hard',               -- a key from Config.Minigame.difficulties
        cooldown = 120,                    -- seconds before the same player may use it again

        scenario = 'WORLD_HUMAN_MUSCLE_FREE_WEIGHTS',
        offset = vector3(0.0, 0.6, 0.0),   -- where the player stands, in the PROP's space
        heading = 180.0,                   -- added to the prop's own heading
        snap = true,                       -- actually move them there

        require = { stats = { strength = 40 } },
    },
}
```

**`gains` is in sessions, not points.** `{ strength = 1.0 }` is one full session of strength.
`{ strength = 0.5, stamina = 0.5 }` is half a session of each - which is what the heavy bag
does, and why it is worth using for both. The totals do not have to add to 1.0: equipment that
is simply better can be worth more.

**More reps is not more reward.** Reps are how long the session is and how many chances there
are to miss. `gains` is the reward.

**`trains` caps a piece of equipment.** `trains = { strength = 60 }` makes a home dumbbell
useless above 60 strength and pushes players towards a real gym.

**Animations.** `anim` is preferred when it is set and its dictionary loads; `scenario`
otherwise. Both can fail on a given map or game build, and neither failing stops the session -
the minigame is the workout, the animation is the dressing. Scenarios are the safer choice
because they handle their own prop attachment.

---

## Passive training: running, cycling, swimming, diving

Section 13. A body does not only improve in a gym, so four activities pay out on their own:
sprinting on foot and riding a bicycle build stamina, swimming builds both, and holding your
breath underwater is the best outdoor source of lung capacity in the resource.

Each activity takes any number of stats. Distance activities are priced **per kilometre**, diving
**per minute**:

```lua
Config.Passive.swimming = {
    enabled = true,
    gains = { stamina = 0.30, breath = 0.15 },   -- per kilometre
    minSpeed = 0.6,
    maxSpeed = 4.0,
    dailyCap = 1.0,
    ceiling = nil,          -- nil uses Config.Passive.ceiling
}
```

### The equipment has to stay better, and three mechanisms make sure of it

**The rates are low.** A dedicated gym player earns about 18.75 points a day. `dailyCapTotal` holds
every passive activity combined to 2.0, so the best possible day of swimming and cycling is 9% of
a day in the gym. The check script asserts that ratio stays under 50% and fails the build if a
config change breaks it.

**A ceiling per activity.** `ceiling` stops an activity raising a stat past a value *at all* -
not tapering, stopping. At the default 60, swimming carries your lung capacity to 60 and the last
40 needs yoga or a bench. Diving gets 75 because it trains the stat that is otherwise hard to
raise outdoors. **This is the strongest lever in the section** and the first one to reach for.

**It does not stop decay.** `countsAsTraining = false` means a passive gain does not reset the
decay clock. A player who cycles daily and never trains still loses 5 a day against a 2.0 cap, so
they lose ground. Passive training supplements a routine and cannot be one. Turning it on suits a
survival or fishing server; know that it removes the pressure to use the equipment.

All of it goes through the allowance ledger, so running across the map is not a way around the
50-points-per-25-hours rule either.

### What it costs, and what is trusted

One client loop at one second whose every branch returns immediately unless the player is
actually doing the thing, reporting in batches every 30 seconds. With the section off the thread
ends at its first line.

Nothing the client sends is trusted. The server clamps each amount to what the interval could
physically hold - worked out from that activity's own `maxSpeed` - applies the caps from its own
running count, checks the ceiling against the stat it holds, and puts the remainder through the
allowance. A modified client can claim it swam further and will gain, at most, what an honest
player would have gained by actually swimming that far, bounded by the daily cap.

`Config.Passive.notify = true` shows a toast on each payout. Off by default because a
notification every thirty seconds while jogging is noise; turn it on once to confirm the feature
works.

Only pedal cycles count for `cycling` (vehicle class 13) and only while the pedalling task is
active, so freewheeling down Mount Chiliad earns nothing. A motorbike is not exercise.

---

## Aligning a body onto a prop

`placeAnim` exercises attach the ped to the prop at an offset in the prop's own space, which is
what makes a player lie *on* a bench rather than jog beside it. Those offsets are measured, not
guessed, and there is a tool for it:

```
/vsportprop bench_press prop_muscle_bench_05
```

It puts you and a copy of that prop **in the sky over open water**, hands you a scripted camera,
and lets you move the body and the held prop a hundredth of a metre at a time. `ENTER` prints a
paste-ready block for `shared/equipment.lua`.

The studio is the default because none of it needs a real specimen: with the ped attached there
is no physics, no ground and no collision, so a model the map places nowhere aligns exactly as
well as one in a gym - and a clean sky shows a floating limb that a cluttered gym floor hides.

```lua
Config.Debug.tuneStudio = {
    coords = vector3(-1900.0, -3400.0, 120.0),
    always = true,          -- false = align against the real thing, wherever it stands
}
```

With `always = false` the tool looks for the nearest loaded prop, then sweeps the known
locations in `Config.Debug.searchSpots`, and only conjures one as a last resort.

The keys are on the panel. The two worth knowing before you start: **TAB** cycles how the prop
is held (right hand / centred / both hands, the last being derived rather than tuned), and
**mouse + wheel** drive the camera instead of the character.

`/vsportgoto <exercise>` teleports to a real one, and `/vsportfind <model>` sweeps the whole map
for a single model. A sweep proves presence; it never proves absence.

---

## Adding a fourth stat

It is a config change, not a code change. Add an entry to `Config.Stats`:

```lua
flexibility = {
    order = 4,
    label = 'stat.flexibility',
    description = 'stat.flexibility_desc',
    colour = { 180, 120, 200 },
    icon = 'F',
    max = 100.0,
    start = 0.0,
    sessionsToMax = 100,
    gameStat = '',                 -- GTA has no flexibility stat; '' writes nothing
},
```

Then:

1. Add `stat.flexibility` and `stat.flexibility_desc` to **both** `locales/en.lua` and
   `locales/fr.lua`. They must stay key-for-key identical.
2. Give some equipment a gain for it: `gains = { flexibility = 1.0 }` on yoga or stretching.
3. Optionally add a `Config.Effects.flexibility` block, and read it in `client/effects.lua`.

It then appears in the stats panel, in every export, in the allowance and in the database with
no other change. The database stores stats as JSON precisely so that this is not a migration.

---

## Commands, and who may run them

Section 16. Every command is prefixed `vsport` so nothing here can collide with a `/sport` from
another resource. Set any name to `''` and it is not registered at all.

| Command | Who | What |
|---|---|---|
| `/vsport` | everyone | the stats panel |
| `/vsportdev` | everyone | re-ask whether you may use the tools below |
| `/vsportinfo` | admin | what was detected, and which framework was found |
| `/vsportscan [radius]` | admin | every object nearby, and whether v-sport knows it |
| `/vsportspot <exercise>` | admin | a `Config.Spots` line for where you stand |
| `/vsportoffset` | admin | a `modelOverrides` offset for the prop you face |
| `/vsportprop <exercise> [model]` | admin | the live alignment studio |
| `/vsportgoto [exercise]` | admin | teleport to a machine, or list what is nearby |
| `/vsportfind <model>` | admin | sweep the whole map for one model |
| `/vsportadmin ...` | admin | set, add to or reset a player's training |
| `/vsportmissing` | admin | ask the game whether any sport prop is missing from the catalogue |
| `/vsportadd <exercise> [model]` | admin | add the prop you are looking at, live |
| `/vsportremove <exercise> [model]` | admin | take one back out |
| `/vsportcustom` | admin | list what has been added in game |
| `/vsportexport` | admin | print your additions as a `config.lua` block |
| `/vsportreload` | admin | re-read `data/custom.json` |
| `/vsportreset [exercise]` | admin | forget one exercise's additions, or all |
| `/vsportitems [inventory]` | admin | the item blocks to paste into your inventory |

**The admin restriction is real and it matters.** `/vsportgoto` teleports across the map and
`/vsportprop` teleports into the sky, so left open they are a free teleport in every player's chat
suggestions. The check is made **server-side** by `Bridge.isAdmin` and pushed to the client, which
refuses everything until an answer arrives - so a dropped event fails closed, not open.

```lua
Config.Commands.adminAce = 'command.vsportadmin'   -- the ace to grant
Config.Commands.restrictDevCommands = true         -- false only on a dev server
```

`Bridge.isAdmin` checks that ace first, then falls back to the framework's own idea of staff, so a
server that never set an ace up is not locked out of its own tools. The console is always allowed.
An admin promoted mid-session, or one whose ace comes from a permissions resource that loaded after
this one, runs `/vsportdev` rather than reconnecting.

---

## Exercises with no equipment at all

Section 9c. Push-ups, sit-ups, yoga and stretching can be done anywhere - from the radial menu, an
export, or a command - with no prop in sight.

```lua
Config.Anywhere = {
    enabled = true,
    allowed = { 'push_ups', 'sit_ups', 'yoga', 'stretching' },

    -- Worth less than the same exercise on a mat. 1.0 removes the distinction.
    gainScale = 1.0,

    requireFlatGround = true,
    maxGroundAngle = 20.0,       -- degrees, measured from three ground samples
    respectCooldowns = true,     -- shares the cooldown with the equipment version
}
```

This is what stops a server with no gym MLO from having nothing to do, and it is why switching an
equipment exercise off costs less than the model count suggests. Wire it to your own menu with
`GetAnywhereExercises()` and `StartAnywhere(key)` - see API.md.

---

## The database

Section 2. One table, created for you on first boot.

```lua
Config.Persistence = {
    table = 'v_sport_stats',
    scope = 'character',         -- 'character' or 'license'
    autoCreateTable = true,
    saveInterval = 60,          -- seconds; only dirty profiles are written
    saveOnDrop = true,
    saveOnResourceStop = true,
    pruneAfterDays = 0,         -- 0 keeps everything forever
}
```

**`scope` is the decision that is painful to change later.** `'character'` gives every character on
an account their own body, which is what a roleplay server almost always wants. `'license'` ties
progress to the account, so every character shares one physique. Switching after players have
trained orphans the old rows rather than migrating them.

Stats are stored as JSON precisely so that adding a fourth stat is not a migration.
`sql/v_sport.sql` is there if you would rather create the table yourself.

---

## Notifications and the interface

Sections 15 and 12. Each notification is its own switch, because "the resource is too chatty" and
"the resource never tells me anything" are both real complaints.

```lua
Config.Notifications = {
    sessionComplete = true,
    sessionFailed = true,
    statMilestone = true,
    milestoneEvery = 25.0,       -- every 25 points, not every point
    decayApplied = true,
    buffApplied = true,
    cooldownActive = true,
    requirementFailed = true,    -- "not from a vehicle", "get up first"
    preferOwnToast = false,      -- true ignores the framework and uses this resource's toast
}
```

`Config.UI` holds `scale`, the colour table, the workout HUD position, the panel and the toast.
Everything drawn is native - there is no NUI in this resource - so the numbers are screen-space
fractions from 0 to 1. `hideHudDuringSession` and `hideRadarDuringSession` are off by default.

`Config.Buffs` bounds what other resources may do to a player: how large a single change may be,
how long a buff may last, and how far a buff may push the effective value past a stat's maximum.
It cannot push the section 7 **effects** past their own maximum - that ceiling is hard, and the
check script asserts it. Full detail in API.md.

`Config.Items` is the four consumables. Each entry holds both the gameplay fields - the effect, the
amount, the duration, the cooldown - and the inventory metadata: `label`, `description`, `weight`
and `image`. The metadata is there so that renaming `whey` to `proteine` is one edit rather than two:
`/vsportitems` generates the registration block for qb-core, ox_inventory or ESX **from these
values**, so the block can never be out of date with the config. Full detail in ITEMS.md, and the
icons plus conversion instructions in `images/README.md`.

---

## The minigame

Four difficulty presets in `Config.Minigame.difficulties`. Each piece of equipment names one
and can override any field of it.

```lua
normal = {
    keys = { 2, 3 },                 -- keys per rep, picked randomly in this range
    window = 1250,                   -- ms the bar takes to fill for one key
    perfectZone = { 0.60, 0.80 },    -- fraction of the bar that scores 1.0
    goodZone    = { 0.42, 0.95 },    -- the wider band that scores Config.Minigame.goodScore
    restBetween = 750,               -- ms of animation between reps
},
```

`goodZone` **must contain** `perfectZone`. Yoga is the worked example of an override: a 2600ms
window, one key per rep and a very wide perfect band, so it feels like breathing rather than
button mashing.

`Config.Minigame.keyPool` is the set of keys sequences are drawn from. All of them are disabled
for the duration of a session and read back with `IsDisabledControlJustPressed`, so pressing W
to hit a prompt does not also walk the player off the bench. Keep the labels to one or two
characters - the box is drawn to fit.

To make sessions easier without touching the timing, raise `Config.Minigame.goodScore` (how
much a merely-good press is worth) or `Config.Minigame.maxMisses`.

---

## Performance

Nothing runs when nothing is happening. Three tiers, switched automatically:

| Tier | When | Cost |
|---|---|---|
| Idle | No equipment in range | One loop at `Config.Performance.idleTick` (1s) |
| Nearby | Equipment in range | One loop at `nearbyTick` (250ms) + drawing inside marker range |
| Session | A workout is running | One loop per frame, one player, a couple of minutes |

If you are chasing frame time, two knobs, in this order:

```lua
Config.Detection.interval = 750     -- ms between object-pool scans
Config.Detection.radius   = 20.0    -- metres
```

The scan already skips entirely when the player has not moved `Config.Detection.idleDistance`,
compares squared distances, reuses its result table, and stops at
`Config.Detection.maxObjects` (400). Raising `interval` to 1500 halves an already small number.

On the server there is no per-player loop at all: one timer flushes dirty rows in batches
(`Config.Performance.flushInterval`), one sweeps expired buffs, one re-checks decay every
`Config.Decay.onlineInterval`. Everything else is event-driven.

State bags are written only on a real change and at most every
`Config.Performance.stateBagInterval`. `stateBagReplicated` is off by default because it is one
network message per player per change; only turn it on if another resource needs to read *other*
players' stats on the client.

---

## Anti-cheat, honestly

The minigame runs on the client, so the client knows the score. No FiveM resource can change
that - judging frame-accurate input on the server would need a round trip per key press.
Anybody claiming their training script is cheat-proof is selling something.

What the server does enforce, all from its own clock and its own state:

- A session must have been **authorised**. No token, no payout - so firing the finish event in
  a loop pays nothing.
- A token is **single-use and owned**. It cannot be replayed or borrowed.
- A result that arrives **faster than the reps could have been performed** is rejected
  (`Config.Security.minDurationFactor`).
- A result from somebody who has since **walked away** is rejected (`maxDriftDistance`).
- Cooldowns, the per-hour rate limit and the allowance are all checked server-side.
- Reps are clamped to what the equipment actually has.

That leaves one hole: a cheater can play a plausibly-shaped session and lie about their
accuracy, gaining at most what an excellent player would have gained anyway. **The allowance is
what bounds the damage** - the best possible player and the cheater hit the same ceiling.

Every check fails closed. A session that cannot be verified pays nothing.

```lua
Config.Security.fireSuspicionEvent = true
Config.Security.suspicionThreshold = 5
```

v-sport never kicks or bans anybody. It fires `vsport:server:CheatSuspected` once a player has
collected five rejections inside an hour, and your anticheat decides what that means. One
rejection on its own is a desync and is not worth acting on.

---

## Common recipes

**"Training should be roleplay only, no mechanical advantage."**

```lua
Config.Effects.enabled = false
```

**"Halve every bonus but keep the progression."**

```lua
Config.Effects.globalScale = 0.5
```

**"Players should not lose everything when they go on holiday."**

```lua
Config.Decay.peakProtection = 25.0    -- never fall more than 25 below your best
Config.Decay.grace = 72 * 3600        -- three free days
```

**"Police and EMS train as part of the job."**

```lua
Config.Decay.exemptJobs = { ['police'] = true, ['ambulance'] = true }
```

**"Only one person per bench."** Already the default (`Config.General.exclusiveEquipment`).
It is enforced server-side by proximity, so it works on props with no network identity.

**"I want the target instead of the E prompt."** Automatic when ox_target, qb-target or
qtarget is installed. To force one way or the other:

```lua
Config.Interaction.mode = 'target'    -- or 'key', or 'auto'
Config.Compat.forceTarget = 'ox_target'
```

**"Keep the markers even though I use a target."**

```lua
Config.Interaction.marker.enabled = true
```

**"Test the progression without doing a hundred workouts."**

```lua
Config.Debug.autoPerfect = true       -- every press scores perfect
Config.Debug.gainMultiplier = 20.0    -- and each session is worth twenty
```

Both are debug switches. Turn them off before anybody plays on it.

---
---

# Configuration (Version Française)

Cette page est maintenue en anglais, comme le code. Voici les points essentiels.

## Les quatre nombres qui décident de tout

```lua
Config.Allowance.total   = 50.0          -- points par cycle, toutes stats confondues
Config.Allowance.perStat = 25.0          -- ...et dans une seule stat
Config.Allowance.window  = 25 * 3600     -- temps de récupération du quota
Config.Decay.amount      = 10.0          -- points perdus par jour sans entraînement
```

La relation entre eux **est** le design : le quota plafonne la journée (impossible de farmer
au-delà), la fatigue fixe le rythme à l'intérieur de la journée (les trois premières séances
valent plus que les vingt suivantes, donc on banque 6 à 9 points par jour, pas 50), et la perte
crée la pression de revenir (-5 par jour contre +6 à +9 réalistes : qui s'entraîne un jour sur
deux progresse encore un peu). La perte était de 10 et paraissait trop dure : deux jours
d'absence coûtaient un cinquième de tout. Elle ne change en rien la vitesse de progression, la
grâce d'un jour faisant que celui qui s'entraîne quotidiennement ne perd jamais rien.

Avec les valeurs par défaut, **le maximum est quelque chose qu'on maintient, pas quelque chose
qu'on atteint et qu'on garde.** Si ce n'est pas ce que vous voulez : augmentez
`Config.Decay.grace`, baissez `Config.Decay.amount`, ou activez
`Config.Decay.peakProtection`.

## Durée pour atteindre le maximum

Mesuré en simulant les vraies fonctions de progression jour par jour, quota et pertes compris.
**Les trois statistiques à 100 % :**

| Joueur | Séances/jour | Forme | Jours |
|---|---|---|---|
| Occasionnel, un jour de repos sur trois | 9 | 85 % | ~59 |
| Assidu, un jour de repos par semaine | 18 | 90 % | ~22 |
| Assidu, tous les jours | 21 | 90 % | ~16 |
| **Assidu, tous les jours, joue bien le QTE** | **21** | **100 %** | **~13** |
| Ne fait rien d'autre | 60 | 100 % | ~5 |

**Deux semaines est la cible visée**, pour un joueur qui s'entraîne chaque jour et réussit ses
touches. Bien jouer le minijeu vaut environ trois jours, ce qui est tout l'intérêt d'avoir un
minijeu.

### Pour ralentir ou accélérer

Trois leviers, dans l'ordre où il faut les envisager :

1. **`Config.Stats.*.sessionsToMax`** — le levier honnête. 150 rend tout une fois et demie plus
   long, uniformément et prévisiblement. C'est celui à utiliser.
2. **`Config.Allowance.total`** — abaisse le *plancher*, celui qu'un farmeur atteint. Aux 24
   fournis il n'en reste presque rien : qui tente soixante séances par jour mesure **quinze jours**
   contre seize pour le joueur assidu, le quota refusant la plupart de ces séances. Le farm rapporte
   un jour. Remonter `total` à 30 restaure les treize jours d'origine et donne six jours au farmeur ;
   descendre sous 22 fait du quota, et non de la fatigue, ce que ressent tout joueur ordinaire.
3. **`Config.Progression.fatigue`** — de l'anti-macro, pas du rythme. Aux valeurs par défaut,
   une heure d'affilée à la salle coûte environ 10 % de sa valeur. La rendre assez dure pour
   fixer le rythme, c'est ce qui transforme deux semaines en trois mois, et c'est une mauvaise
   façon de le faire : le joueur voit juste ses gains fondre sans explication.

**Ne laissez pas le quota devenir le rythme.** Si `Config.Allowance.total` descend près de ce
qu'un joueur ordinaire gagne dans une journée, la courbe de fatigue cesse de compter, chaque
séance paraît arbitraire, et l'ensemble se lit comme un refus aléatoire. Gardez le mur au-dessus
de la route.

Trois préréglages cohérents (arcade, défaut, hardcore) sont écrits en fin de section 5 de
`config.lua`, prêts à coller.

## Ce qu'obtient réellement un personnage au maximum

Dégâts au corps à corps **1,25**, dégâts subis **/1,15**, apnée **75 s** au lieu de 45, nage
**1,12**, sprint **1,12**, régénération **1,30**, récupération d'endurance **+20 %/s** à
l'arrêt. Vie maximale désactivée par défaut.

Deux réglages déplacent tout : `Config.Effects.enabled = false` rend les stats purement
roleplay, `Config.Effects.globalScale = 0.5` divise chaque bonus par deux.

**Plafonds du moteur.** `SetSwimMultiplierForPlayer` et `SetRunSprintMultiplierForPlayer` sont
**ignorés au-delà de 1.49** par le jeu. Mettre `max = 2.0` donne 1.49 et une config qui ment.

**Les vraies stats GTA.** Séparément, v-sport écrit `MP0_STRENGTH`, `MP0_STAMINA` et
`MP0_LUNG_CAPACITY`. C'est la voie honnête, et c'est pourquoi les trois stats sont celles-là :
GTA les modélise déjà.

## Trouver les props de votre carte

Placez-vous dans votre salle et tapez `/vsportscan`. La commande liste chaque objet dans un
rayon de 20 m avec sa distance, `YES` ou `-` selon que le catalogue le connaît, le nom du
modèle quand il est résoluble, et les exercices proposés.

Tout ce qui est marqué `-` s'ajoute à `Config.ExtraEquipment` (section 9b).

**Un nom de modèle inexistant ne coûte rien** : il se hache en un nombre qu'aucune entité ne
portera. Les listes fournies sont donc volontairement généreuses, y compris avec plusieurs
orthographes. Soyez généreux dans vos ajouts aussi.

Une entrée dont la clé existe déjà **complète** celle fournie : trois modèles de plus, c'est
trois lignes.

`Config.Debug.drawDetected = true` affiche une étiquette au-dessus de chaque prop reconnu.

## Matériel intégré à un MLO

Certain matériel fait partie du modèle de la carte, pas un objet : rien à trouver pour le scan.
Placez-vous dessus et tapez `/vsportspot pull_ups` pour obtenir une ligne `Config.Spots` prête à
coller. `Config.Debug.drawSpots = true` les affiche en sphères.

## Entrainement passif : course, velo, nage, apnee

Section 13. Quatre activites payent d'elles-memes : le sprint a pied et le velo montent
l'endurance, la nage monte les deux, et l'apnee sous l'eau est la meilleure source d'apnee en
exterieur du script. Chaque activite accepte autant de stats qu'on veut, tarifees **par
kilometre** pour les trois activites de distance et **par minute** pour l'apnee.

```lua
Config.Passive.swimming = {
    enabled = true,
    gains = { stamina = 0.30, breath = 0.15 },   -- par kilometre
    minSpeed = 0.6, maxSpeed = 4.0,
    dailyCap = 1.0,
    ceiling = nil,          -- nil utilise Config.Passive.ceiling
}
```

### Trois mecanismes garantissent que l'equipement reste meilleur

**Les taux sont faibles.** Un joueur assidu en salle gagne environ 18,75 points par jour ;
`dailyCapTotal` plafonne tout le passif cumule a 2.0, soit 11 % d'une journee de salle. Le script
de verification impose ce rapport sous 50 % et echoue si une modification de config le casse.

**Un plafond par activite.** `ceiling` empeche une activite de depasser une valeur, net et sans
degressivite. A 60 par defaut, la nage porte l'apnee a 60 et les 40 derniers exigent du yoga ou un
banc. L'apnee monte a 75 parce qu'elle entraine la stat la plus difficile a monter dehors. **C'est
le levier le plus fort de la section.**

**Ca n'arrete pas les pertes.** `countsAsTraining = false` : un gain passif ne remet pas le
compteur de perte a zero. Qui fait du velo tous les jours sans jamais s'entrainer perd toujours 5
par jour contre un plafond de 2.0, donc recule. Le passif complete une routine, il ne la remplace
pas. Le passer a `true` convient a un serveur de survie ou de peche, mais supprime toute pression
a utiliser l'equipement.

Tout passe par le registre du quota : courir a travers la carte ne contourne pas la regle des 50
points par 25 heures.

### Cout et confiance

Une boucle client a une seconde dont chaque branche sort immediatement si le joueur ne fait pas
l'activite, avec un envoi groupe toutes les 30 secondes. Section desactivee, le thread s'arrete a
sa premiere ligne.

Rien de ce qu'envoie le client n'est cru. Le serveur borne chaque quantite a ce que l'intervalle
peut physiquement contenir, d'apres le `maxSpeed` de l'activite, applique ses propres compteurs de
plafond, verifie le plafond contre la stat qu'il detient, et passe le reste par le quota. Un
client modifie gagne au mieux ce qu'un joueur honnete aurait gagne, dans la limite du plafond
journalier.

Seuls les velos comptent pour `cycling` (classe 13) et seulement quand la tache de pedalage est
active : descendre le Chiliad en roue libre ne rapporte rien. Une moto n'est pas du sport.

## Aligner un corps sur un prop

Les exercices `placeAnim` attachent le ped au prop avec un décalage exprimé dans le repère du
prop : c'est ce qui fait qu'un joueur s'allonge *sur* le banc. Ces décalages se mesurent :

```
/vsportprop bench_press prop_muscle_bench_05
```

Vous êtes envoyé dans le ciel au-dessus de l'eau avec une copie du prop et une caméra scriptée.
Les touches sont affichées ; `ENTRÉE` imprime un bloc prêt à coller dans `shared/equipment.lua`.

Le studio est le mode par défaut : le ped étant attaché, il n'y a ni physique, ni sol, ni
collision, donc un modèle que la carte ne place nulle part s'aligne aussi bien qu'un modèle en
salle, et un ciel vide montre un membre qui flotte là où un sol de salle le cache.

```lua
Config.Debug.tuneStudio = { coords = vector3(-1900.0, -3400.0, 120.0), always = true }
```

Avec `always = false`, l'outil cherche le prop le plus proche, puis balaie
`Config.Debug.searchSpots`, et n'en crée un qu'en dernier recours.

**TAB** change le mode de prise (main droite / centré / deux mains, ce dernier étant calculé et
non réglé), **souris et molette** pilotent la caméra. `/vsportgoto <exercice>` téléporte vers un
vrai exemplaire, `/vsportfind <modele>` balaie toute la carte. Un balayage prouve une présence,
jamais une absence.

## Ajouter une quatrième stat

C'est une modification de configuration, pas de code. Ajoutez l'entrée à `Config.Stats`, les
deux clés de locale dans **les deux** fichiers, et un `gains` sur un équipement. Elle apparaît
alors dans le panneau, dans tous les exports, dans le quota et en base. Les stats sont stockées
en JSON précisément pour que ce ne soit pas une migration.

## Anti-triche, honnêtement

Le minijeu tourne côté client, donc le client connaît le score. Aucune ressource FiveM ne peut
changer ça. Ce que le serveur impose : une séance doit être **autorisée** (pas de jeton, pas de
gain), un jeton est **à usage unique et nominatif**, un résultat **trop rapide** est rejeté, un
joueur qui **s'est éloigné** est rejeté, et les temps de recharge, la limite horaire et le quota
sont vérifiés côté serveur.

Il reste un trou : un tricheur peut mentir sur sa précision et gagner au mieux ce qu'un
excellent joueur aurait gagné. **Le quota borne les dégâts** : le meilleur joueur possible et
le tricheur touchent le même plafond.

v-sport n'expulse et ne bannit jamais. Il émet `vsport:server:CheatSuspected` après cinq rejets
dans l'heure, et votre anticheat décide.

## Recettes courantes

Voir la section anglaise : roleplay pur, bonus divisés par deux, protection des vacances,
métiers exemptés, forcer le target, et les deux interrupteurs de debug pour tester la
progression sans faire cent séances (`Config.Debug.autoPerfect` et
`Config.Debug.gainMultiplier`).
