--[[
    ===========================================================================================
    v-sport / config.lua
    ===========================================================================================

    Every operator knob, in one file, in nineteen commented sections.

        1.  General               10. Interaction
        2.  Compatibility         11. Minigame
        3.  Persistence           12. UI
        4.  Stats                 13. Passive training
        5.  Progression           14. Buffs
        6.  Decay                 15. Notifications
        7.  Effects               16. Commands
        8.  Detection             17. Anti-cheat
        9.  Spots                 18. Performance
        9b. Your own equipment    19. Debug

    The equipment catalogue - which prop is which exercise, and what each one trains - is the
    other half of the configuration and lives in `shared/equipment.lua`. It is a config file
    in everything but its folder; edit it freely. Section 8 below explains how to find the
    props on YOUR map, including the ones inside custom MLOs that no shipped list can know.

    -------------------------------------------------------------------------------------------
    A WORD ON BALANCE, BEFORE YOU RAISE ANYTHING
    -------------------------------------------------------------------------------------------

    The defaults in section 7 are deliberately small. A character at 100% in every stat is a
    fit person, not a superhero: about a quarter more damage with their fists, a fifth longer
    underwater, and a slightly longer sprint. That is enough for a player to feel the training
    paid off and not enough to break a fight, a chase or a heist for everybody else.

    Two knobs move the whole thing at once:

        Config.Effects.enabled     = false   -- stats become a pure roleplay number
        Config.Effects.globalScale = 0.5     -- every bonus at half strength

    Raise individual ceilings only after reading the table at the top of section 7, which
    states what each native actually does and where the game itself stops caring.
]]

Config = {}

-- ===========================================================================================
-- 1. GENERAL
-- ===========================================================================================

Config.General = {
    -- The locale. 'auto' reads the `sport_locale` convar, then `qb_locale`, then falls back
    -- to English. Set it to 'en' or 'fr' to pin it regardless of the server's other settings.
    locale = 'auto',

    -- Distance in metres at which a player must be standing to use a piece of equipment.
    -- Also the distance the server re-checks on a finished session (section 17).
    useDistance = 2.5,

    -- Whether a player may train while another player is already using the same prop. Off
    -- means one person per bench, which is the immersive answer and also stops two players
    -- clipping into the same animation.
    exclusiveEquipment = true,

    -- Refuse to start a session when the player is in any of these states. Each one is a
    -- separate flag so an operator can allow, say, training while handcuffed on a prison
    -- server that wants a yard workout.
    refuseWhen = {
        inVehicle       = true,
        dead            = true,
        cuffed          = true,     -- reads the framework's own cuffed flag where it has one
        swimming        = true,
        inCombat        = true,     -- weapon drawn or recently shot at
        ragdoll         = true,
        falling         = true,
    },

    -- Holster the weapon before the animation starts. A barbell in one hand and a rifle in
    -- the other looks wrong and breaks most workout animations.
    holsterWeapon = true,
}

-- ===========================================================================================
-- 2. COMPATIBILITY
-- ===========================================================================================
--
-- Everything here is detected at runtime. Nothing in this section is required, and a missing
-- optional resource degrades rather than errors. Run /sportinfo in game to print what was
-- actually found.

Config.Compat = {
    -- Skip framework detection. '' detects; otherwise one of:
    -- 'qb-core' | 'qbx_core' | 'es_extended' | 'ox_core'
    -- Set this on a server that has two frameworks installed at once.
    forceFramework = '',

    -- Skip target detection. '' detects; otherwise 'ox_target' | 'qb-target' | 'qtarget'
    -- | 'none'. 'none' forces the built-in key prompt even when a target resource is
    -- installed, which is what you want if your target is reserved for something else.
    forceTarget = '',

    -- Skip notification detection. '' detects; otherwise
    -- 'ox_lib' | 'qb-core' | 'esx' | 'okokNotify' | 'native'.
    forceNotify = '',

    -- Use ox_lib's progress bar for the recovery pause between reps when ox_lib is present.
    -- Off draws the resource's own native bar instead, which matches the rest of the HUD.
    useOxProgress = false,

    -- interact-sound, for the rep and the session-complete cues. Silently skipped when the
    -- resource is not started.
    soundResource = 'interact-sound',
}

-- ===========================================================================================
-- 3. PERSISTENCE
-- ===========================================================================================

Config.Persistence = {
    -- The table. Created on first start when it does not exist; sql/v_sport.sql is shipped
    -- for operators who would rather import a schema by hand.
    table = 'v_sport_stats',

    -- What a row is keyed on.
    --   'character' - qb citizenid / ESX identifier / ox stateId. Each character trains
    --                 separately, which is the roleplay answer and the default.
    --   'license'   - the Rockstar licence. Every character on the account shares one body.
    scope = 'character',

    -- Create the table at boot when it is missing. Turn this off on a server where the
    -- database user is not allowed to run DDL; import sql/v_sport.sql instead.
    autoCreateTable = true,

    -- Write a dirty row to the database at most this often, in seconds. Stats change a
    -- fraction of a point at a time, so writing on every change would be one query per rep.
    saveInterval = 60,

    -- Also save on these. Dropping is the one that matters: a server that crashes loses at
    -- most `saveInterval` seconds of progress, and a clean disconnect loses none.
    saveOnDrop = true,
    saveOnResourceStop = true,

    -- Keep a row for a character who has not logged in for this many days, then delete it on
    -- boot. 0 keeps every row forever. 365 is a year of inactivity.
    pruneAfterDays = 0,
}

-- ===========================================================================================
-- 4. STATS
-- ===========================================================================================
--
-- The three trainable stats. Adding a fourth is a data change: add an entry here, give some
-- equipment a gain for it in shared/equipment.lua, add its two locale keys, and it appears in
-- the panel, in the exports and in the database with no code change.
--
--   order          Position in the stats panel. Low first.
--   label          Locale key for the name.
--   description    Locale key for the one-line explanation under it.
--   colour         { r, g, b } for its bar.
--   icon           A single character drawn in the panel. Native text, so ASCII only.
--   max            The ceiling. 100 makes every number a percentage, which is what the
--                  panel and every export assume; changing it is not recommended.
--   start          What a brand new character begins at.
--   sessionsToMax  How many perfect sessions of equipment that trains ONLY this stat it
--                  takes to go from `start` to `max`. This is the number that sets the pace
--                  of the whole resource. 100 is the default.
--   gameStat       The GTA character stat this feeds, without the MP0_/SP0_ prefix. The
--                  game already has strength, stamina and lung capacity as first-class
--                  stats, so training them is a matter of writing the real value rather
--                  than faking an effect. '' writes nothing.
--   decay          Per-stat decay, overriding section 6. Omit to use the global setting.

Config.Stats = {
    strength = {
        order = 1,
        label = 'stat.strength',
        description = 'stat.strength_desc',
        colour = { 214, 69, 65 },
        icon = 'S',
        max = 100.0,
        start = 0.0,
        sessionsToMax = 100,
        gameStat = 'STRENGTH',
    },

    breath = {
        order = 2,
        label = 'stat.breath',
        description = 'stat.breath_desc',
        colour = { 64, 156, 214 },
        icon = 'B',
        max = 100.0,
        start = 0.0,
        sessionsToMax = 100,
        gameStat = 'LUNG_CAPACITY',

        -- Lung capacity is the slowest thing on this list to build and the slowest to lose.
        -- Half the global decay rate, and a longer grace period.
        decay = { amount = 5.0, interval = 24 * 3600, grace = 48 * 3600, floor = 0.0 },
    },

    stamina = {
        order = 3,
        label = 'stat.stamina',
        description = 'stat.stamina_desc',
        colour = { 96, 186, 96 },
        icon = 'E',
        max = 100.0,
        start = 0.0,
        sessionsToMax = 100,
        gameStat = 'STAMINA',
    },
}

-- ===========================================================================================
-- 5. PROGRESSION
-- ===========================================================================================

Config.Progression = {
    --[[
        HOW A SESSION BECOMES POINTS

            points = gain x quality x fatigue x diminishing x multiplier

        `gain`         comes from the equipment (shared/equipment.lua) and is expressed in
                       SESSIONS, not points. A bench press with `strength = 1.0` is worth one
                       full session of strength; the punching bag's `{ strength = 0.5,
                       stamina = 0.5 }` is worth half a session of each. One session is
                       `max / sessionsToMax` points, so 1.0 point at the defaults.

        `quality`      is what the player scored in the minigame, 0.0 to 1.0. See section 11
                       and `minQuality` below.

        `fatigue`      falls as the player trains repeatedly in a short window and recovers
                       when they stop. It is the anti-grind mechanism.

        `diminishing`  optionally slows the last stretch towards 100. OFF by default, because
                       it silently breaks the promise that `sessionsToMax` sessions get you
                       there.

        `multiplier`   is whatever another resource set through the exports - a supplement, a
                       coach NPC, a gym membership, a drug. Section 14.
    ]]

    -- A session scoring below this is worth nothing at all. Set to 0 to always pay out
    -- something. 0.15 means a player who stood there missing every prompt gains nothing,
    -- and a player who half-tried gains half.
    minQuality = 0.15,

    -- Multiply the gain of a session that scored a perfect 1.0. A small carrot for playing
    -- the minigame well rather than adequately.
    perfectBonus = 1.15,

    -- Round the stored value to this many decimals. One decimal means a gain of 0.05 is
    -- lost; two means every rep counts. Two is the default because equipment that trains a
    -- stat at 0.2 of a session would otherwise round away on a mediocre run.
    decimals = 2,

    -- --- Fatigue ---------------------------------------------------------------------
    --
    -- Fatigue is what stops a BURST. The gain multiplier drops by `perSession` for each
    -- session finished inside `window` seconds, down to `floor`, and recovers by
    -- `recoverPerHour` for every hour of rest.
    --
    -- At the defaults, a player's afternoon looks like this:
    --
    --     1st session   x1.00        4th session   x0.25
    --     2nd session   x0.75        5th onwards   x0.15
    --     3rd session   x0.50
    --
    -- So the first three workouts are worth more than the next twenty combined. Grinding is
    -- not forbidden, it is simply pointless, which is a better deterrent than a refusal.
    fatigue = {
        enabled = true,
        window = 5400,              -- 90 minutes counts as "recent"
        perSession = 0.25,
        floor = 0.15,
        recoverPerHour = 0.35,      -- fully rested again after about three hours
    },

    -- --- Caps ------------------------------------------------------------------------
    --
    -- The hard ceiling on how much a character may gain before they have to rest lives in
    -- its own section, 5b, immediately below. It is the mechanism that decides how many
    -- DAYS a maxed character takes, and it is the one to read next.
    --
    -- The most a single session may ever pay, whatever the equipment or the multipliers.
    -- A backstop against a badly configured piece of equipment or an external resource
    -- handing out a x50 multiplier.
    sessionCap = 2.0,

    -- Sessions a single player may finish per hour, whatever the equipment. This one is a
    -- macro guard, not a balance knob - fatigue and the caps already handle balance.
    sessionsPerHour = 12,

    -- --- Diminishing returns ---------------------------------------------------------
    --
    -- Optional, and OFF by default. When on, gains scale by `(1 - progress) ^ curve` above
    -- `from`, which makes the last stretch cost several times what the first did.
    --
    -- It is off because it silently breaks the promise that `sessionsToMax` sessions get
    -- you there: with it on at the defaults, 100 is not reachable in 100 sessions, it is
    -- reachable in about 150. Turn it on if you want the top of the ladder to be rare, and
    -- say so to your players rather than letting them work it out.
    diminishing = {
        enabled = false,
        from = 70.0,                -- below this, no slowdown at all
        curve = 0.5,
    },

    -- -------------------------------------------------------------------------------------
    -- READY-MADE BALANCES
    -- -------------------------------------------------------------------------------------
    --
    -- Paste one of these over the values above. Each is internally consistent - the caps,
    -- the fatigue and the decay in section 6 are balanced against each other, so changing
    -- one number out of a preset changes the whole feel.
    --
    -- ARCADE - noticeable in a week, maxed in a fortnight. For a server where training is
    -- a side activity rather than a career.
    --     sessionsToMax (section 4)  = 60
    --     sessionsPerHour            = 20
    --     fatigue     = { enabled = true, window = 3600, perSession = 0.15,
    --                     floor = 0.30, recoverPerHour = 0.5 }
    --     Config.Allowance.total     = 60.0   perStat = 40.0   window = 12 * 3600
    --     Config.Decay.amount        = 5.0    Config.Decay.grace = 48 * 3600
    --
    -- DEFAULT - what ships. Read section 5b for what that actually works out to.
    --
    -- HARDCORE - a maxed character is a genuine rarity and a visible achievement.
    --     sessionsToMax (section 4)  = 150
    --     sessionsPerHour            = 8
    --     fatigue     = { enabled = true, window = 7200, perSession = 0.35,
    --                     floor = 0.10, recoverPerHour = 0.25 }
    --     diminishing = { enabled = true, from = 60.0, curve = 0.6 }
    --     Config.Allowance.total     = 30.0   perStat = 15.0   window = 36 * 3600
    --     Config.Decay.amount        = 12.0   Config.Decay.grace = 24 * 3600
    --     Config.Decay.peakProtection = 25.0
}

-- ===========================================================================================
-- 5b. TRAINING ALLOWANCE
-- ===========================================================================================
--
--  THE RECOVERY SYSTEM. A body can only take so much before it needs a rest, and this is that
--  rule: a character may gain a fixed number of points, and once they have, they are BLOCKED
--  from gaining any more until they have recovered.
--
--  At the defaults:
--
--      A character may gain 50 points in total across every stat inside one 25 hour window,
--      and no more than 25 points into any single stat.
--
--      So 25 strength and 25 stamina is a full window. So is 25 strength, 15 stamina and 10
--      lung capacity. Once the 50 is spent, training still runs, the minigame still plays,
--      and it pays nothing until the window rolls over.
--
--      Whey (section 5c) cuts that 25 hour wait to 8 hours.
--
--  HOW THIS RELATES TO FATIGUE. Fatigue in section 5 is the SOFT limit and the allowance is
--  the HARD one, and they do different jobs:
--
--      Fatigue says   "your fifth workout this afternoon is worth 15% of your first"
--      Allowance says "you have gained enough this cycle, come back tomorrow"
--
--  Because fatigue collapses so fast, a player realistically banks 6 to 9 points a day rather
--  than the full 50 - they would have to spread thirty-odd sessions across an entire day to
--  spend a whole allowance. The allowance is the wall that stops a no-life run; fatigue is
--  what sets the everyday pace. Both are needed, and neither replaces the other.
--
--  WHAT THAT MEANS IN DAYS, for a committed player at the defaults:
--
--      one stat to 100%       roughly 3 weeks
--      all three to 100%      roughly 7 to 8 weeks
--      with whey every cycle  roughly a third off both, and it costs money
--
--  Read it with section 6. Decay takes 10 points a day back the moment somebody stops, so
--  the ceiling is something you HOLD rather than something you reach and bank.

Config.Allowance = {
    enabled = true,

    -- Points across ALL stats per window. 0 disables the global part.
    total = 50.0,

    -- ...and into any one stat. 0 disables the per-stat part. Setting this to `total` lets a
    -- player pour a whole window into one stat, which is faster to max but leaves the other
    -- two at zero.
    perStat = 25.0,

    -- How long a spent allowance takes to come back, in seconds.
    window = 25 * 3600,

    -- 'rolling' - each point earned frees itself again exactly `window` seconds later, so
    --             the allowance trickles back rather than arriving all at once. Fairer, and
    --             it means a player is never fully locked out for a whole day.
    -- 'block'   - the whole allowance resets in one go, `window` seconds after the FIRST
    --             point of the cycle. Simpler to explain, harsher to be on the wrong side of.
    mode = 'rolling',

    -- What the window drops to for a player who has taken whey, in seconds. Also the value
    -- the ReduceRecovery export sets when it is called with no duration of its own.
    reducedWindow = 8 * 3600,

    -- Tell the player the first time a session pays nothing because the allowance is spent,
    -- and again when it comes back. Without this a blocked player thinks the resource broke.
    notifyBlocked = true,
    notifyRestored = true,

    -- Show the remaining allowance in the stats panel.
    showInPanel = true,
}

-- ===========================================================================================
-- 5c. ITEMS
-- ===========================================================================================
--
--  Consumables that touch the training system. Every one of them is OPTIONAL: an item that is
--  not registered in your inventory simply never gets used, and nothing errors.
--
--  ADDING THE ITEMS TO YOUR INVENTORY IS A MANUAL STEP, and it is different on every
--  framework. ITEMS.md walks through qb-core, ESX and ox_inventory line by line, with the
--  exact blocks to paste. This resource registers the USE handler; it cannot create an item
--  in somebody else's inventory definition, and a resource that tried to edit qb-core's
--  items.lua behind your back would be a worse resource.
--
--  Each entry:
--
--    item          The inventory item name. '' disables the entry entirely.
--    effect        What using it does. See below.
--    amount        The magnitude, meaning depends on the effect.
--    duration      Seconds, where the effect is timed. 0 is instant or permanent.
--    consume       Whether to remove one from the inventory on use.
--    cooldown      Seconds before the same player may use this item again.
--    notify        Locale key or plain text shown on use.
--
--  Effects:
--
--    'recovery'     Cut the allowance window to Config.Allowance.reducedWindow for
--                   `duration` seconds. This is what whey does.
--    'allowance'    Immediately give back `amount` points of spent allowance.
--    'multiplier'   Multiply training gains by `amount` for `duration` seconds.
--                   `stat` names one stat, or nil for all of them.
--    'buff'         Add `amount` points to a stat's EFFECTIVE value for `duration`.
--    'decay_pause'  Stop decay for `duration` seconds.
--    'stamina'      Refill the sprint bar. `amount` is 0..1.

Config.Items = {
    -- The one the whole recovery mechanic is built around.
    whey = {
        item = 'whey',
        effect = 'recovery',
        duration = 25 * 3600,       -- the shortened window lasts a full cycle
        consume = true,
        cooldown = 300,
        notify = 'item.whey_used',
    },

    -- A protein bar: a small immediate refund of spent allowance.
    protein_bar = {
        item = 'protein_bar',
        effect = 'allowance',
        amount = 10.0,
        consume = true,
        cooldown = 600,
        notify = 'item.protein_used',
    },

    -- A pre-workout: gains are worth more for half an hour.
    pre_workout = {
        item = 'pre_workout',
        effect = 'multiplier',
        amount = 1.5,
        duration = 1800,
        stat = nil,                 -- all stats
        consume = true,
        cooldown = 1800,
        notify = 'item.preworkout_used',
    },

    -- A sports drink: refill the sprint bar. Purely a convenience item.
    sports_drink = {
        item = 'sports_drink',
        effect = 'stamina',
        amount = 1.0,
        consume = true,
        cooldown = 60,
        notify = 'item.drink_used',
    },
}

-- ===========================================================================================
-- 6. DECAY
-- ===========================================================================================
--
-- Skip the gym and the body forgets. Decay is computed from a timestamp, so it runs while the
-- player is offline: coming back after a fortnight costs a fortnight of decay, which is the
-- whole point of measuring it in real hours.

Config.Decay = {
    enabled = true,

    -- Points lost per `interval`, once `grace` has elapsed since the last session.
    -- These are ABSOLUTE POINTS, not a percentage of the current value: 100 -> 90 -> 80,
    -- not 100 -> 90 -> 81. Absolute is more punishing at the top, which is where you want
    -- the pressure, and it is what an operator reading "-10 per day" expects.
    amount = 10.0,
    interval = 24 * 3600,

    -- Nothing decays until this long after the last session. One free day.
    grace = 24 * 3600,

    -- Never fall below this. 0.0 means an absent player eventually returns to a blank slate.
    -- Set it to something like 20.0 if losing everything makes people quit rather than train.
    floor = 0.0,

    -- Also stop decaying below the highest value the character has ever reached, minus this
    -- many points. 0 disables it. This is the gentler alternative to `floor`: a player who
    -- once hit 80 never drops below 80 - `peakProtection`, so long absences cost a known
    -- amount rather than everything.
    peakProtection = 0.0,

    -- Re-check while the player is online, in seconds. The offline catch-up happens once on
    -- load regardless of this.
    onlineInterval = 900,

    -- Tell the player what they lost the moment they load in, once.
    notifyOnLoad = true,

    -- Jobs, job types and gangs exempt from decay entirely. Keys are matched against the job
    -- name, the job type, and 'gang:' .. gang name. A police officer or a firefighter
    -- arguably trains as part of the job.
    exemptJobs = {
        -- ['police'] = true,
        -- ['ambulance'] = true,
        -- ['gang:vagos'] = true,
    },
}

-- ===========================================================================================
-- 7. EFFECTS
-- ===========================================================================================
--
--  READ THIS BEFORE RAISING A CEILING.
--
--  Every bonus below is interpolated from the stat's current value: at 0 the character gets
--  `min`, at 100 they get `max`, linearly in between. `min` should almost always be the
--  game's own default, so an untrained character plays exactly like vanilla GTA.
--
--  | Native                             | Vanilla | What it actually does                    |
--  |------------------------------------|---------|------------------------------------------|
--  | SetPlayerMeleeWeaponDamageModifier | 1.0     | Fist and melee damage. 2.0 is a one-punch|
--  |                                    |         | knockout on most peds.                   |
--  | SetPlayerMeleeWeaponDefenseModifier| 1.0     | Melee damage TAKEN is divided by this.   |
--  | SetPedMaxTimeUnderwater            | ~45s    | Seconds before drowning starts.          |
--  | SetSwimMultiplierForPlayer         | 1.0     | Swim speed. The game ignores above 1.49. |
--  | SetRunSprintMultiplierForPlayer    | 1.0     | Sprint speed. Ignored above 1.49.        |
--  | SetPlayerHealthRechargeMultiplier  | 1.0     | Passive regeneration rate.               |
--  | SetPlayerStaminaRegen (stat)       | -       | The real MP0_STAMINA character stat.     |
--
--  The character stats (`gameStat` in section 4) are the honest path: GTA already models
--  strength, stamina and lung capacity, so writing the real value gives the player the exact
--  behaviour the base game intended for a maxed character. The multipliers below are the
--  extra layer on top, and they are the ones that turn into a superhero if you let them.

Config.Effects = {
    -- The master switch. Off makes every stat a roleplay number with no mechanical effect
    -- whatsoever - the training, the panel and the exports all still work.
    enabled = true,

    -- Scale every bonus at once, between the vanilla value and the configured maximum.
    -- 1.0 applies the table below as written. 0.5 gives half of every bonus. 0.0 is the same
    -- as `enabled = false` for the multipliers, but still writes the GTA character stats.
    globalScale = 1.0,

    -- Write the real GTA character stats named by `gameStat` in section 4. This is the
    -- cheapest and most authentic effect there is, and it is bounded by the game.
    -- Both the MP0_ and SP0_ variants are written, because which one is live depends on
    -- whether the server put the player in a multiplayer character slot.
    writeGameStats = true,

    -- How often the effects are re-applied, in milliseconds. Several of these natives are
    -- reset by the game on respawn, on a model change and on some cutscenes, so they are
    -- re-asserted on a slow loop rather than set once.
    refreshInterval = 5000,

    -- Per-stat bonuses. Delete a block to disable that bonus; set `enabled = false` to keep
    -- it in the file as documentation.
    strength = {
        -- +25% unarmed and melee damage at 100. A trained character wins a fist fight
        -- against an untrained one; they do not one-shot a stranger.
        meleeDamage = { enabled = true, min = 1.0, max = 1.25 },

        -- Melee damage taken is divided by this. +15% at 100.
        meleeDefense = { enabled = true, min = 1.0, max = 1.15 },

        -- Maximum health. OFF by default and it should usually stay off: most frameworks,
        -- most ambulance jobs and every armour script assume 200 and will fight this.
        maxHealth = { enabled = false, min = 200, max = 225 },

        -- Carry weight handed to the inventory through the export in section 14. Nothing
        -- reads it unless your inventory is wired up to ask; see API.md.
        carryWeight = { enabled = false, min = 0, max = 15000 },
    },

    breath = {
        -- Seconds underwater before drowning. Vanilla is about 45. 75 at 100 is a long
        -- dive, not an aqualung.
        underwaterTime = { enabled = true, min = 45.0, max = 75.0 },

        -- Swim speed. The engine ignores anything above 1.49, so 1.12 is a real but modest
        -- difference rather than a rocket.
        swimSpeed = { enabled = true, min = 1.0, max = 1.12 },
    },

    stamina = {
        -- Sprint speed. Same 1.49 engine ceiling as swimming.
        sprintSpeed = { enabled = true, min = 1.0, max = 1.12 },

        -- Passive health regeneration.
        healthRecharge = { enabled = true, min = 1.0, max = 1.30 },

        -- Restore a fraction of the stamina bar every `staminaTickInterval` ms while the
        -- player is on foot and not sprinting. This is the one that players feel most, and
        -- it is capped low on purpose: at 100 it is a noticeably quicker breather between
        -- sprints, not infinite running.
        recovery = { enabled = true, min = 0.0, max = 0.20 },
        tickInterval = 1000,
    },
}

-- ===========================================================================================
-- 8. DETECTION
-- ===========================================================================================
--
--  HOW THE RESOURCE FINDS SPORT EQUIPMENT ON YOUR MAP
--
--  Two mechanisms, and you will want both:
--
--  1. A PROP SCAN. Every `interval` milliseconds the resource walks the object pool around
--     the player and matches each model hash against the catalogue in shared/equipment.lua.
--     This finds anything that is a real world object, including props placed by another
--     resource and props inside a streamed MLO.
--
--  2. STATIC SPOTS (section 9). Some gym equipment in a custom MLO is baked into the map
--     model rather than placed as an object, so nothing is there for a scan to find. Those
--     need a coordinate.
--
--  FINDING WHAT IS ACTUALLY AROUND YOU. The shipped catalogue lists the base-game sport props
--  and a spread of names used by common gym MLOs. It cannot know what your map has. Stand in
--  your gym and run:
--
--      /sportscan          every object within 20m, with its model hash, distance and
--                          whether the catalogue already knows it
--      /sportspot <key>    prints a ready-to-paste Config.Spots entry for where you stand
--
--  A model name in the catalogue that does not exist in your game costs nothing - it hashes
--  to a number no entity will ever have. Over-listing is safe; that is why the shipped list
--  is generous.

Config.Detection = {
    enabled = true,

    -- Milliseconds between scans. 750 is imperceptible to the player and about a tenth of a
    -- millisecond of frame time. Raise it to 1500 on a server that is fighting for frames.
    interval = 750,

    -- Metres. Nothing beyond this is considered. Keep it tight: the cost of a scan is
    -- proportional to how many objects come back, not to the radius itself, but a big radius
    -- in a dense interior returns a lot of objects.
    radius = 20.0,

    -- Skip the scan entirely when the player is in a vehicle, dead, or already training.
    -- There is nothing to find in any of those states.
    skipInVehicle = true,
    skipWhenBusy = true,

    -- When the player has not moved more than this many metres since the last scan, reuse
    -- the previous result instead of scanning again. A player standing still in a gym is the
    -- common case, and this makes it free.
    idleDistance = 1.5,

    -- Give up after this many objects in a single scan. A pathological interior with
    -- thousands of objects would otherwise cost a visible frame spike. The nearest ones come
    -- back first in practice, so a truncated scan still finds the bench you are standing at.
    maxObjects = 400,

    -- Also match on the model of the prop a player is holding or attached to. Off by
    -- default: it is only useful for hand-held equipment like a skipping rope.
    matchAttached = false,
}

-- ===========================================================================================
-- 9. SPOTS
-- ===========================================================================================
--
-- Fixed positions that offer an exercise with no prop at all - equipment baked into an MLO,
-- a patch of grass someone decided is the yoga corner, a prison yard.
--
-- Stand where you want it and run `/sportspot pushups` to get a line to paste here.
--
--   equipment  A key from shared/equipment.lua.
--   coords     vector3. The centre of the interaction.
--   heading    Which way the player faces. nil keeps their own heading.
--   radius     Metres. Defaults to Config.General.useDistance.
--   label      Locale key or plain text, overriding the equipment's own name.
--   marker     false to draw nothing. Useful when the spot is already visually obvious.
--   job        Restrict to a job, job type or 'gang:name'. nil is everybody.

Config.Spots = {
    -- Two worked examples, commented out. The coordinates are the base-game Muscle Sands
    -- area on Vespucci Beach; verify them on your own map before enabling either.
    --
    -- { equipment = 'pull_ups', coords = vector3(-1202.0, -1566.0, 4.6), heading = 35.0 },
    -- { equipment = 'yoga',     coords = vector3(-1180.0, -1573.0, 4.6), radius = 3.0,
    --   label = 'Beach yoga', marker = true },
}

-- -------------------------------------------------------------------------------------------
-- 9b. YOUR OWN EQUIPMENT
-- -------------------------------------------------------------------------------------------
--
-- Add equipment, or patch what ships, WITHOUT editing shared/equipment.lua - which is the file
-- an update overwrites. Same field shape; see the header of that file.
--
-- A key that already exists PATCHES the shipped entry, so three extra models for the bench
-- press is three lines rather than a restated block. A key that does not exist creates a new
-- piece of equipment, and it appears everywhere the shipped ones do.

Config.ExtraEquipment = {
    -- Patch: teach the shipped bench press about two MLO models.
    -- bench_press = {
    --     models = { 'prop_gym_bench_01', 'prop_gym_bench_02', 'prop_gym_bench_03',
    --                'mymlo_bench_01', 'mymlo_bench_02' },
    -- },

    -- New: a squat rack that only exists in your gym.
    -- squat_rack = {
    --     order = 14,
    --     label = 'Squat rack',
    --     description = 'Heavy compound lifting.',
    --     models = { 'mymlo_squatrack' },
    --     gains = { strength = 1.2 },
    --     reps = 6,
    --     difficulty = 'hard',
    --     cooldown = 120,
    --     scenario = 'WORLD_HUMAN_MUSCLE_FREE_WEIGHTS',
    --     offset = vector3(0.0, 0.6, 0.0),
    --     heading = 180.0,
    --     snap = true,
    --     require = { stats = { strength = 40 } },
    -- },
}

-- ===========================================================================================
-- 10. INTERACTION
-- ===========================================================================================

Config.Interaction = {
    -- 'auto'   - ox_target / qb-target / qtarget when one is installed, key prompt otherwise
    -- 'target' - target only; nothing happens when no target resource is installed
    -- 'key'    - the built-in key prompt only, even when a target is installed
    mode = 'auto',

    -- The key for the built-in prompt. 38 is E (INPUT_PICKUP).
    key = 38,

    -- A yoga mat offers push-ups, sit-ups, yoga and stretching. This key cycles between the
    -- exercises a single prop supports; the prompt says so when there is more than one.
    -- 47 is G (INPUT_DETONATE).
    cycleKey = 47,

    -- How the prompt is drawn when `mode` resolves to 'key'.
    --   'help3d'  - floating text above the prop, drawn in 3D
    --   'help'    - the game's own top-left help box
    --   'both'
    prompt = 'help3d',

    -- Draw a marker on the ground under usable equipment. Cheap, and it makes a gym read as
    -- interactive at a glance.
    marker = {
        enabled = true,
        type = 27,                          -- 27 is the flat ring
        scale = vector3(0.7, 0.7, 0.25),
        colour = { 255, 255, 255, 90 },
        distance = 8.0,                     -- draw within this many metres
        zOffset = 0.03,
        bobUpAndDown = false,
        rotate = false,
    },

    -- Target settings, used when the mode resolves to 'target'.
    target = {
        distance = 2.0,
        icon = 'fa-solid fa-dumbbell',
    },

    -- Blips on the map for the static spots in section 9. Prop-based equipment never gets a
    -- blip - a blip per dumbbell would bury the map.
    blips = {
        enabled = false,
        sprite = 311,
        colour = 2,
        scale = 0.7,
        shortRange = true,
    },
}

-- ===========================================================================================
-- 11. MINIGAME
-- ===========================================================================================
--
--  THE RHYTHM QTE
--
--  A session is `reps` repetitions. Each rep asks for a short sequence of randomly chosen
--  keys. Each key gets a bar that fills left to right; the player presses it as the marker
--  crosses the target zone.
--
--      pressed inside `perfectZone`   PERFECT   scores 1.0
--      pressed inside `goodZone`      GOOD      scores `goodScore`
--      pressed outside, or wrong key  MISS      scores 0
--      not pressed before the bar ends MISS     scores 0
--
--  The session's quality is the mean of every key's score, and that is what multiplies the
--  gain in section 5. `maxMisses` consecutive misses ends the session early.

Config.Minigame = {
    -- Difficulty presets. Each piece of equipment names one in shared/equipment.lua, and
    -- anything it does not override comes from here.
    --
    --   keys        How many keys in a rep's sequence. { min, max }, picked per rep.
    --   window      Milliseconds the bar takes to fill for one key.
    --   perfectZone Fraction of the bar that scores a perfect. { start, finish }.
    --   goodZone    The wider band that still scores. Must contain perfectZone.
    --   restBetween Milliseconds of animation between reps, with no input asked for.
    difficulties = {
        easy = {
            keys = { 1, 2 },
            window = 1600,
            perfectZone = { 0.55, 0.85 },
            goodZone    = { 0.35, 0.98 },
            restBetween = 900,
        },
        normal = {
            keys = { 2, 3 },
            window = 1250,
            perfectZone = { 0.60, 0.80 },
            goodZone    = { 0.42, 0.95 },
            restBetween = 750,
        },
        hard = {
            keys = { 2, 4 },
            window = 950,
            perfectZone = { 0.64, 0.78 },
            goodZone    = { 0.50, 0.92 },
            restBetween = 600,
        },
        brutal = {
            keys = { 3, 5 },
            window = 750,
            perfectZone = { 0.66, 0.76 },
            goodZone    = { 0.56, 0.88 },
            restBetween = 450,
        },
    },

    -- Scores.
    goodScore = 0.55,
    -- Consecutive misses that abort the session. The player keeps whatever the completed
    -- reps were worth, scaled by the quality they actually achieved. 0 never aborts.
    maxMisses = 4,

    -- Each rep completed without a single miss adds this to a streak multiplier, up to
    -- `streakMax`. It multiplies the quality, not the gain, so it cannot push quality past
    -- 1.0 - it just makes a clean run reach a perfect score.
    streakPerRep = 0.04,
    streakMax = 1.20,

    -- The keys the sequences are drawn from. `control` is the GTA control index; `label` is
    -- what the box draws. The whole list is disabled for the duration of the session, and
    -- read back with IsDisabledControlJustPressed, so pressing W does not also walk.
    --
    -- Keep the labels one or two characters: the box is drawn to fit.
    keyPool = {
        { label = 'W', control = 32 },      -- INPUT_MOVE_UP_ONLY
        { label = 'A', control = 34 },      -- INPUT_MOVE_LEFT_ONLY
        { label = 'S', control = 33 },      -- INPUT_MOVE_DOWN_ONLY
        { label = 'D', control = 35 },      -- INPUT_MOVE_RIGHT_ONLY
        { label = 'E', control = 38 },      -- INPUT_PICKUP
        { label = 'Q', control = 44 },      -- INPUT_COVER
        { label = 'R', control = 45 },      -- INPUT_RELOAD
        { label = 'F', control = 23 },      -- INPUT_ENTER
        { label = 'SPC', control = 22 },    -- INPUT_JUMP
    },

    -- Never ask for the same key twice in a row inside one sequence. Two identical boxes
    -- side by side read as one long press and players hate it.
    noRepeats = true,

    -- The key that cancels a session in progress. 177 is BACKSPACE (INPUT_CELLPHONE_CANCEL).
    -- A cancelled session pays out for the reps already completed.
    cancelKey = 177,

    -- Hold the cancel key for this long, in milliseconds, before it takes. Stops a stray
    -- press ending a long workout. 0 cancels on tap.
    cancelHold = 400,

    -- Sounds, from the game's own audio banks. Set a name to '' to silence that cue.
    sounds = {
        enabled = true,
        perfect = { name = 'CHECKPOINT_PERFECT', set = 'HUD_MINI_GAME_SOUNDSET' },
        good    = { name = 'CHECKPOINT_NORMAL',  set = 'HUD_MINI_GAME_SOUNDSET' },
        miss    = { name = 'CHECKPOINT_MISSED',  set = 'HUD_MINI_GAME_SOUNDSET' },
        finish  = { name = 'RACE_PLACED',        set = 'HUD_AWARDS' },
        fail    = { name = 'LOSER',              set = 'HUD_AWARDS' },
    },
}

-- ===========================================================================================
-- 12. UI
-- ===========================================================================================
--
-- Everything is drawn with the game's own natives - DrawRect, DrawSprite and the text
-- commands. There is no NUI page, no HTML and no browser: the HUD costs a few draw calls
-- while a session is running and literally nothing when one is not.
--
-- Positions are fractions of the screen, so they hold at any resolution and on an ultrawide.

Config.UI = {
    -- Global scale for the workout HUD. 1.0 is designed against 1080p.
    scale = 1.0,

    -- The palette. { r, g, b } or { r, g, b, a }; alpha defaults to 255.
    colours = {
        panel        = { 12, 14, 18, 200 },
        panelEdge    = { 255, 255, 255, 26 },
        accent       = { 240, 76, 88 },
        text         = { 255, 255, 255 },
        textDim      = { 175, 180, 190 },
        barTrack     = { 255, 255, 255, 32 },
        barFill      = { 240, 76, 88 },
        zoneGood     = { 232, 190, 74, 120 },
        zonePerfect  = { 106, 214, 118, 170 },
        keyIdle      = { 26, 30, 38, 225 },
        keyActive    = { 240, 76, 88 },
        keyHit       = { 106, 214, 118 },
        keyMiss      = { 196, 62, 62 },
        judgePerfect = { 106, 214, 118 },
        judgeGood    = { 232, 190, 74 },
        judgeMiss    = { 214, 78, 78 },
    },

    -- The workout HUD.
    workout = {
        -- Anchor of the whole panel, as a fraction of the screen. { 0.5, 0.82 } is bottom
        -- centre, clear of the minimap on the left and the weapon wheel on the right.
        x = 0.5,
        y = 0.82,

        -- Shrink the panel to nothing but the key row and the timing bar. For operators who
        -- already have a busy HUD.
        compact = false,

        showExerciseName = true,
        showRepCounter = true,
        showQualityBar = true,
        showStatGains = true,       -- the live "+0.42 STR" readout
        showJudgement = true,       -- the PERFECT / GOOD / MISS flash
        judgementMs = 550,
    },

    -- Hide the rest of the game's HUD while a session runs, so the workout panel is the only
    -- thing on screen. The radar is a separate flag because a player who cannot see the map
    -- also cannot see somebody walking up behind them.
    hideHudDuringSession = false,
    hideRadarDuringSession = false,

    -- The stats panel, opened with /sport. Also drawn natively.
    panel = {
        x = 0.5,
        y = 0.5,
        width = 0.30,               -- fraction of screen width
        openKey = '',               -- a key name like 'F7' registers a keybind. '' is none.
        showEffects = true,         -- list what each stat is currently granting
        showNextDecay = true,       -- when the next decay lands
        showSessionCount = true,
        closeKeys = { 177, 200 },   -- BACKSPACE, ESC
    },

    -- Toast notifications drawn by this resource when no notification provider is found.
    -- Section 15 chooses whether they are used at all.
    toast = {
        x = 0.5,
        y = 0.14,
        durationMs = 3500,
        maxStacked = 3,
    },
}

-- ===========================================================================================
-- 13. PASSIVE TRAINING
-- ===========================================================================================
--
-- Training that happens without a prop, because a body does not only improve in a gym. Both
-- are small on purpose: they exist so that a long swim or a cross-city run is not worth
-- literally nothing, not as an alternative to the equipment.

Config.Passive = {
    -- Sprinting on foot builds stamina.
    running = {
        enabled = true,
        stat = 'stamina',
        -- Points per kilometre sprinted. At 0.08, a full marathon is about 3.4 points -
        -- roughly three and a half gym sessions for 42km of running, which is the ratio you
        -- want between "went to the gym" and "happened to run somewhere".
        perKilometre = 0.08,
        -- Only count movement above this speed in m/s. 4.0 excludes walking and jogging.
        minSpeed = 4.0,
        -- Stop counting after this many points in one 24h period. 0 is uncapped.
        dailyCap = 1.0,
    },

    -- Holding your breath underwater builds lung capacity.
    diving = {
        enabled = true,
        stat = 'breath',
        -- Points per minute spent underwater without surfacing.
        perMinute = 0.25,
        -- Ignore the first few seconds, so bobbing under a wave repeatedly earns nothing.
        minDiveSeconds = 8,
        dailyCap = 1.5,
    },

    -- Both of the above report to the server in batches this often, in seconds, rather than
    -- on every tick. Fewer, larger events are cheaper and easier to sanity-check.
    reportInterval = 30,
}

-- ===========================================================================================
-- 14. BUFFS
-- ===========================================================================================
--
-- The hook for every other resource: a drug script, a supplement item, a coach NPC, a gym
-- membership, a steroid. See API.md for the full surface.
--
--   ApplyBuff(src, stat, amount, seconds)     temporary points on top of the trained value
--   ApplyMultiplier(src, stat, mult, seconds) temporary multiplier on what training gains
--   AddStat / RemoveStat / SetStat            permanent changes to the trained value
--   SetDecayPaused(src, bool)                 stop the clock, for as long as a cycle lasts

Config.Buffs = {
    enabled = true,

    -- A buff can push the EFFECTIVE value this far above the stat's max. 20 means a 100
    -- strength character on a supplement plays as 120 for its duration. The trained value is
    -- untouched; only the effective value moves, and only the effective value drives
    -- section 7. Set to 0 to make buffs a way of reaching the ceiling faster and never a way
    -- of passing it.
    overcap = 20.0,

    -- And this far below zero, for a debuff. Effective values are clamped at 0 regardless.
    undercap = 0.0,

    -- The largest number a single call may pass, as a guard against a bug in somebody else's
    -- resource wiping a player's progress. A call outside this is clamped and logged.
    maxSingleChange = 100.0,
    maxDurationSeconds = 24 * 3600,

    -- Stack two buffs on the same stat, or let the newer one replace the older.
    --   'stack'   - both apply, both expire on their own clock
    --   'replace' - the newest wins
    --   'highest' - the strongest wins, and its duration is the one that counts
    stacking = 'stack',

    -- Tell the player when a buff lands and when it wears off.
    notifyApply = true,
    notifyExpire = true,

    -- Fire `vsport:server:BuffExpired` and its client twin so a drug script can hook a
    -- comedown onto the end of its own buff without polling.
    fireExpiryEvents = true,
}

-- ===========================================================================================
-- 15. NOTIFICATIONS
-- ===========================================================================================

Config.Notifications = {
    -- Which of the resource's messages are worth interrupting the player for.
    sessionComplete = true,
    sessionFailed = true,
    statMilestone = true,           -- every `milestoneEvery` points
    decayApplied = true,
    buffApplied = true,
    cooldownActive = true,
    requirementFailed = true,       -- "you cannot train in a vehicle"

    milestoneEvery = 25.0,

    -- Prefer the resource's own native toast over the framework's notification, even when a
    -- framework is present. Off uses the framework's, which is the consistent answer on a
    -- server whose players already know what its notifications look like.
    preferOwnToast = false,
}

-- ===========================================================================================
-- 16. COMMANDS
-- ===========================================================================================
--
-- Set a name to '' to not register that command at all.

Config.Commands = {
    stats = 'sport',                -- open the stats panel
    info = 'sportinfo',             -- print what was detected, to F8
    scan = 'sportscan',             -- list nearby objects and whether they are known
    spot = 'sportspot',             -- print a Config.Spots line for where you stand
    admin = 'sportadmin',           -- set / add / reset another player's stats

    -- The ace a player needs for `admin` and for the developer commands. The framework's own
    -- idea of an admin is accepted as a fallback, so a server that never set an ace up is
    -- not locked out.
    adminAce = 'command.sportadmin',

    -- `scan` and `spot` are developer tools that print model names to the console. They are
    -- restricted to admins by default; on a development server you may want them open.
    restrictDevCommands = true,
}

-- ===========================================================================================
-- 17. ANTI-CHEAT
-- ===========================================================================================
--
-- The client runs the minigame, so the client knows the score - there is no way around that
-- in a FiveM resource. What the server can do is refuse a result that is not physically
-- possible, and that is what this section is.
--
-- Every check here fails CLOSED: a session that cannot be verified pays out nothing.

Config.Security = {
    -- The server issues a token when a session starts and will not accept a result without
    -- one. This stops a client simply firing the "I finished" event in a loop. Leave it on.
    requireToken = true,

    -- Reject a result that arrives faster than the reps could physically have taken. The
    -- expected floor is `reps x (window x minKeys + restBetween)`, times this factor. 0.75
    -- leaves room for latency and for a player who hit every prompt early.
    minDurationFactor = 0.75,

    -- And reject one that took absurdly long, which usually means a client that paused the
    -- session and came back. 4.0 times the expected duration.
    maxDurationFactor = 4.0,

    -- Re-check on the server that the player is still within this many metres of where they
    -- said they were training. 0 disables the check.
    maxDriftDistance = 12.0,

    -- Refuse a second session on the same equipment within this many seconds. Equipment can
    -- override it in shared/equipment.lua.
    defaultCooldown = 45,

    -- Log every rejection to the server console with the player's name and the reason.
    logRejections = true,

    -- Fire `vsport:server:CheatSuspected(src, reason, detail)` on a rejection so an
    -- anticheat resource can decide what to do about it. This resource never kicks or bans
    -- anybody by itself.
    fireSuspicionEvent = true,

    -- Rejections in a rolling hour before the suspicion event is fired. One rejection is a
    -- desync; ten is somebody probing.
    suspicionThreshold = 5,
}

-- ===========================================================================================
-- 18. PERFORMANCE
-- ===========================================================================================
--
--  WHAT THIS RESOURCE COSTS, AND WHERE
--
--  The design rule is that nothing runs when nothing is happening. A player standing in the
--  street with no sport equipment nearby runs ONE loop, at `idleTick` milliseconds, which does
--  a distance check and goes back to sleep. There is no NUI, so there is no browser process,
--  no page to keep painting and no message traffic.
--
--  Three tiers, switched automatically:
--
--    IDLE        No equipment within the detection radius.
--                One loop at `idleTick` (default 1000ms). Effectively free.
--
--    NEARBY      Equipment is in range, so a prompt or a marker may need drawing.
--                One loop at `nearbyTick` (default 250ms) plus a draw loop only while the
--                player is inside the marker distance.
--
--    SESSION     A workout is running.
--                One loop per frame, because the minigame is frame-accurate. This is the only
--                Wait(0) in the resource and it exists for at most a couple of minutes at a
--                time, for one player.
--
--  On the server there is no per-player loop at all. One timer flushes dirty rows, one
--  timer expires buffs, and everything else is event-driven.
--
--  If you are chasing frame time, the two knobs that matter are `Config.Detection.interval`
--  and `Config.Detection.radius`, in that order.

Config.Performance = {
    -- Milliseconds between checks when there is no equipment anywhere near the player.
    idleTick = 1000,

    -- ...and when there is. This is what decides how quickly a prompt appears as you walk up
    -- to a bench, so it is the one to lower if the resource feels sluggish, and the one to
    -- raise if you are counting microseconds.
    nearbyTick = 250,

    -- Stop drawing markers and prompts entirely beyond this many metres, whatever
    -- Config.Interaction.marker.distance says. A hard backstop so a mis-set marker distance
    -- cannot put the resource into a per-frame draw loop across a whole gym.
    drawCutoff = 15.0,

    -- The maximum number of markers drawn in one frame. A gym with forty dumbbells on the
    -- floor would otherwise be forty draw calls; the nearest few are the only ones a player
    -- can read anyway.
    maxMarkers = 6,

    -- Pause every loop when the player is dead or the game is paused. Nothing useful can
    -- happen in either state and both can last minutes.
    pauseWhenDead = true,
    pauseWhenGamePaused = true,

    -- --- Statebags -------------------------------------------------------------------
    -- Publish the player's stats on their state bag, so any other resource can read them
    -- with no export call and no round trip:
    --
    --     Player(source).state.sportStats          -- server
    --     LocalPlayer.state.sportStats             -- client, own stats
    --
    -- Written only when a value actually changes, and at most once per `stateBagInterval`
    -- milliseconds. Turn it off if nothing on your server reads it.
    stateBags = true,
    stateBagInterval = 2000,

    -- Replicate the state bag to every client rather than keeping it server-side. Only turn
    -- this on if another resource needs to read OTHER players' stats on the client - it is
    -- one network message per player per change.
    stateBagReplicated = false,

    -- --- Server --------------------------------------------------------------------
    -- How often the dirty-row flush runs, in seconds. Rows are batched into one transaction,
    -- so this is one query per flush and not one per player.
    flushInterval = 30,

    -- Rows written in a single batch. A server with 200 players all training at once still
    -- writes in chunks rather than building one enormous statement.
    flushBatchSize = 50,

    -- How often expired buffs are swept, in seconds. Expiry is also checked lazily on every
    -- read, so this timer only exists to fire the expiry events on time.
    buffSweepInterval = 5,
}

-- ===========================================================================================
-- 19. DEBUG
-- ===========================================================================================

Config.Debug = {
    -- Console output on both sides: what was detected, every scan result, every session,
    -- every server decision and why.
    enabled = false,

    -- Draw a box around every prop the scan matched, with its equipment key and distance.
    -- The fastest way to find out why a bench is not offering anything.
    drawDetected = false,

    -- Draw the static spots from section 9 as spheres, whether or not they have a marker.
    drawSpots = false,

    -- Skip every timing check in the minigame: every key press scores a perfect. For
    -- testing progression and decay without doing a hundred workouts by hand.
    autoPerfect = false,

    -- Multiply every gain, for the same reason. 1.0 is off.
    gainMultiplier = 1.0,
}
