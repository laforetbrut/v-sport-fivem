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
-- optional resource degrades rather than errors. Run /vsportinfo in game to print what was
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

    --[[
        `soundResource` USED TO BE HERE AND IS GONE, because it silenced the resource rather than
        routing it.

        The idea was to send the rep and completion cues through interact-sound for servers that
        route all audio through one place. It cannot work for these cues: they are GTA FRONTEND
        sounds with a soundset, and interact-sound plays files from its own resource and takes no
        soundset. So the cues vanished, and because the routing counted a fired event as success the
        native fallback was never reached. Any server with interact-sound installed had a silent
        minigame.

        Sounds now always go through PlaySoundFrontend. If you want them routed, the place to do it
        is Config.Minigame.sounds - name your own cues there and change one function.
    ]]
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
    -- FATIGUE IS THE ANTI-MACRO MEASURE, NOT THE PACE. That distinction is the whole reason
    -- the numbers below look mild, and getting it wrong in either direction breaks the game:
    --
    --   too harsh   a normal evening's training is worth nothing, the allowance in section 5b
    --               never comes into play, and reaching 100% takes months
    --   too soft    somebody can sit at a bench for eight hours and there is no downside
    --               except the allowance
    --
    -- At the defaults, a player's hour at the gym looks like this:
    --
    --     1st session   x1.00        6th session   x0.70
    --     2nd session   x0.94        10th session  x0.46
    --     3rd session   x0.88        13th onwards  x0.45  (the floor)
    --
    -- So training normally is fully productive, and sitting there for an hour straight is
    -- worth about 60% of what the same number of sessions spread out would be. Two hours of
    -- rest puts a player back at x1.00.
    --
    -- The WALL is Config.Allowance in section 5b. Read the two together: fatigue decides what
    -- an ordinary session is worth, and the allowance decides how much a day can ever hold.
    fatigue = {
        enabled = true,
        window = 3600,              -- an hour counts as "recent"
        perSession = 0.03,
        floor = 0.55,
        recoverPerHour = 0.60,      -- back to full after about an hour of rest
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
    -- ARCADE - all three stats inside a week. For a server where training is a side activity
    -- rather than a career.
    --     sessionsToMax (section 4)   = 50
    --     Config.Allowance.total      = 60.0   perStat = 40.0   window = 12 * 3600
    --     Config.Decay.amount         = 5.0    Config.Decay.grace = 48 * 3600
    --     Config.Decay.peakProtection = 30.0
    --
    -- DEFAULT - what ships. A fortnight for a dedicated player who hits their prompts.
    -- Section 5b has the measured table across five kinds of player.
    --
    -- HARDCORE - a maxed character is a genuine rarity and a visible achievement. Roughly six
    -- weeks for the same dedicated player, and a grinder cannot get under a fortnight.
    --     sessionsToMax (section 4)   = 150
    --     sessionsPerHour             = 8
    --     Config.Allowance.total      = 22.0   perStat = 12.0   window = 25 * 3600
    --     diminishing = { enabled = true, from = 60.0, curve = 0.6 }
    --     Config.Decay.amount         = 12.0   Config.Decay.grace = 24 * 3600
    --     Config.Decay.peakProtection = 15.0
    --
    -- Note that none of the three touches `fatigue`. It is an anti-macro measure and it works
    -- at the shipped values for every pace; using it to set the pace is the mistake section 5b
    -- warns about.
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
--      A character may gain 24 points in total across every stat inside one 25 hour window,
--      and no more than 12 points into any single stat.
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
--  WHAT THE DEFAULTS ACTUALLY WORK OUT TO
--
--  These are MEASURED, by simulating the real progression functions day by day with the
--  allowance ledger and the decay rules in play - not estimated. All three stats to 100%:
--
--      player                                    sessions/day  form   days
--      ----------------------------------------  ------------  -----  ----
--      casual, one rest day in three                        9    85%    59
--      dedicated, one rest day a week                      18    90%    22
--      dedicated, every day                                21    90%    16
--      dedicated, every day, plays the QTE well            21   100%    13
--      does nothing else                                   60   100%     5
--
--  So a fortnight is the target for somebody who trains every day and hits their prompts, and
--  playing the minigame well is worth about three days of it. One stat on its own is roughly a
--  third of those figures.
--
--  THE LAST ROW IS THE FLOOR THIS SECTION SETS, and at 24 per cycle there is barely a floor left
--  to speak of: a grinder who tries sixty sessions a day measures at FIFTEEN days against the
--  dedicated player's sixteen. Grinding buys one day.
--
--  That figure used to read "about five days", and it was wrong - the simulator was letting a
--  simulated day run past 24 hours whenever a scenario asked for more sessions than fit in one.
--  See ERROR_LOG.md. The corrected number is much better news than the claim it replaces.
--
--  If you want to loosen it, `total` going back up to 30 restores the old thirteen-day headline
--  and hands the grinder six days. Going below about 22 makes the allowance, rather than fatigue,
--  what every ordinary player feels, and hitting the wall daily is a worse experience than
--  simply having a lot of training left to do. The default leaves the wall where a no-life run
--  finds it and nobody else does.
--
--  WHEY BUYS BACK THE WALL, NOT THE ROAD. It shortens the allowance recovery, which only
--  matters to somebody who genuinely trained enough to hit the ceiling. For a player limited
--  by fatigue or by hours in the day it does nothing, and that is correct: it makes a heavy
--  day possible, it does not shorten the fortnight.
--
--  Read it with section 6. Decay takes 5 points a day back the moment somebody stops, so
--  the ceiling is something you HOLD rather than something you reach and bank.

Config.Allowance = {
    enabled = true,

    --[[
        Points across ALL stats per window. 0 disables the global part.

        TWENTY-FOUR, AND IT WAS FIFTY. Fifty was chosen to express the original design - half of
        everything per cycle - and measurement showed it never did anything at all: a dedicated
        player at the fastest sustainable pace banks about 23 points a day, so a ceiling of 50 was
        never once reached. A limit nobody meets is not a limit, it is a number on a panel.

        At 24 the quota is the ACTIVE constraint, which is the whole point of the mechanic: it is
        now what decides how fast a character can improve, rather than fatigue and the hours in a
        day. Measured cost, from tools/check.py:

            allowance 50    dedicated + perfect form maxes everything in 13 days, a grinder in 5
            allowance 24    the same player takes 16 days, and a grinder takes 7

        So it slows the honest player by three days and the grinder by two - which is the right way
        round, and the reason 20 was rejected: it read well on the panel and cost 6 days, taking the
        headline to 19 and breaking the fortnight this resource is balanced around.
    ]]
    total = 24.0,

    --[[
        ...and into any one stat. 0 disables the per-stat part.

        HALF OF `total`, deliberately: two stats at 12 fill a window exactly. That is the shape of
        the original rule - "25% endurance and 25% strength, then you are blocked" - kept intact at
        the smaller number. A third stat in the same window means splitting, which is the trade-off
        it is there to create.

        Setting this to `total` lets a player pour a whole window into one stat, which maxes that
        one faster and leaves the other two at zero.
    ]]
    perStat = 12.0,

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

--[[
    EVERY FIELD AN INVENTORY NEEDS IS HERE, not just the gameplay ones.

    `label`, `description`, `weight` and `image` are not used by this resource at all - it never
    draws an inventory slot. They are here because the alternative is worse: adding these items
    means pasting a block into qb-core/shared/items.lua, ESX's database or ox_inventory's data file,
    and if the name and weight live only in that block then renaming `whey` to `proteine` means
    editing two files and remembering that you did.

    So they live here, and `/vsportitems` prints the paste-ready block for whichever inventory the
    server is running, generated from these values. Rename anything, run it again, paste.

    THE EFFECTS, which are what this resource actually reads:

      recovery     cut the allowance recovery wait. `duration` is how long the shortened window
                   lasts; the shortened length itself is Config.Allowance.reducedWindow.
      allowance    hand back `amount` points of spent allowance immediately.
      multiplier   multiply training gains by `amount` for `duration` seconds. `stat` limits it to
                   one stat; nil is all of them.
      buff         add `amount` points to `stat` for `duration` seconds, effective value only.
      decay_pause  stop the decay clock for `duration` seconds.
      stamina      refill the sprint bar by `amount` (0..1). No lasting effect.

    Add an item by adding an entry. Add a new KIND of item by adding an effect to server/items.lua.
]]

Config.Items = {
    -- The one the whole recovery mechanic is built around.
    whey = {
        item = 'whey',
        effect = 'recovery',
        duration = 25 * 3600,       -- the shortened window lasts a full cycle
        consume = true,
        cooldown = 300,
        notify = 'item.whey_used',

        -- Inventory metadata. Only /vsportitems reads these.
        label = 'Whey Protein',
        description = 'A scoop after training. Your body recovers in a third of the time.',
        weight = 500,
        image = 'whey.png',
    },

    -- A protein bar: a small immediate refund of spent allowance.
    protein_bar = {
        item = 'protein_bar',
        effect = 'allowance',
        amount = 10.0,
        consume = true,
        cooldown = 600,
        notify = 'item.protein_used',

        label = 'Protein Bar',
        description = 'Twenty grams of protein and a wrapper. Worth one more set.',
        weight = 150,
        image = 'protein_bar.png',
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

        label = 'Pre-Workout',
        description = 'Caffeine, beta-alanine and optimism. Half an hour of feeling unstoppable.',
        weight = 200,
        image = 'pre_workout.png',
    },

    -- A sports drink: refill the sprint bar. Purely a convenience item.
    sports_drink = {
        item = 'sports_drink',
        effect = 'stamina',
        amount = 1.0,
        consume = true,
        cooldown = 60,
        notify = 'item.drink_used',

        label = 'Sports Drink',
        description = 'Electrolytes and food colouring. You get your breath back.',
        weight = 400,
        image = 'sports_drink.png',
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

    --[[
        Points lost per `interval`, once `grace` has elapsed since the last session.

        ABSOLUTE POINTS, not a percentage of the current value: 100 -> 95 -> 90, not
        100 -> 95 -> 90.25. Absolute is more punishing at the top, which is where the pressure
        belongs, and it is what an operator reading "-5 per day" expects.

        FIVE, NOT TEN. Ten was the first figure and it read as too harsh in play: two days away
        from the server cost a fifth of everything, which is the kind of number that makes people
        stop logging in rather than train. Five means a week of absence costs 30 points against
        the peak protection below, which is a bad week rather than a lost month.

        IT CHANGES THE HEADLINE PROGRESSION BY NOTHING AT ALL, which is worth knowing before
        anyone tunes it expecting otherwise. The check script's scenarios still reach 100 in every
        stat in 13, 16, 22 and 59 days after the change, because `grace` below is a full day: a
        player who trains daily never decays at all, whatever this number says.

        So this is a dial on what ABSENCE costs, and only that. It does not make progression
        faster, it makes coming back after a fortnight less bleak.
    ]]
    amount = 5.0,
    interval = 24 * 3600,

    -- Nothing decays until this long after the last session. One free day.
    grace = 24 * 3600,

    -- Never fall below this. 0.0 means an absent player eventually returns to a blank slate.
    -- Set it to something like 20.0 if losing everything makes people quit rather than train.
    floor = 0.0,

    -- Also stop decaying below the highest value the character has ever reached, minus this
    -- many points. 0 disables it.
    --
    -- ON BY DEFAULT, and it is load-bearing. Read it against section 5: a player banks about
    -- 4 to 6 points a day and loses 5 per day of absence, so without a bound a long trip away
    -- still grinds a character down to nothing and the ceiling becomes unreachable for anybody
    -- with a job. 20 means a long absence costs a known, recoverable amount: a character who
    -- once reached 80 never falls below 60, however long they are gone.
    --
    -- Set it to 0 for a genuinely punishing server, and expect players to say so.
    peakProtection = 20.0,

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
--      /vsportscan          every object within 20m, with its model hash, distance and
--                          whether the catalogue already knows it
--      /vsportspot <key>    prints a ready-to-paste Config.Spots entry for where you stand
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

    --[[
        The most pieces of equipment a single scan will return.

        This caps RESULTS, not how much of the object pool is examined - the whole pool is always
        walked. An earlier version capped the pool walk instead, and because the pool comes back
        in arbitrary order rather than nearest-first, equipment past that index became invisible:
        on a busy map the resource reported nothing in range while standing at a usable bench.

        Walking the whole pool is cheap. The model check is one hash lookup per object and runs
        for all of them; reading coordinates costs something and runs only for the few that are
        sport equipment. Raise this if a gym has more than 60 usable props within the radius.
    ]]
    maxObjects = 60,

    --[[
        `matchAttached` USED TO BE HERE and was read by nothing.

        It described matching on the model of a prop the player is holding, which sounds useful for a
        skipping rope and was never implemented. Detection walks GetGamePool('CObject') and matches
        world objects; nothing anywhere looked at what was in a hand. A commented behaviour with no
        code behind it is a claim, and this file's comments are its documentation.
    ]]
}

-- ===========================================================================================
-- 9. SPOTS
-- ===========================================================================================
--
-- Fixed positions that offer an exercise with no prop at all - equipment baked into an MLO,
-- a patch of grass someone decided is the yoga corner, a prison yard.
--
-- Stand where you want it and run `/vsportspot pushups` to get a line to paste here.
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
-- 9c. TRAINING WITH NO EQUIPMENT AT ALL
-- ===========================================================================================
--
--  Push-ups need a floor. Yoga needs somewhere to sit. Neither needs a prop, and a player who
--  wants to drop and do twenty in the street should be able to.
--
--  These exercises are offered through a MENU rather than a prompt, because there is nothing in
--  the world to walk up to and press E on. Three ways in, all of them already wired:
--
--      the radial menu      fire `vsport:client:StartAnywhere` with the exercise key.
--                           API.md has the qb-radialmenu block, F1 by default.
--      an export            exports['v-sport']:StartAnywhere('push_ups')
--      the stats panel      it lists them, and they can be started from there
--
--  Only the exercises listed below may be started this way, and THE SERVER ENFORCES THAT from
--  its own copy of this list - a client asking to bench press in mid-air is refused. Any key
--  from shared/equipment.lua works here, so an operator who wants burpees in the street adds
--  the exercise and its key.

Config.Anywhere = {
    enabled = true,

    -- Exercises that need no equipment. Everything here must be an exercise whose animation
    -- plays correctly in the open: a WORLD_ scenario or a plain animation, never a PROP_ one.
    -- A PROP_ scenario with nothing to grip leaves the character hanging in the air.
    allowed = {
        'push_ups',
        'sit_ups',
        'yoga',
        'stretching',
        'muscle_flex',
    },

    -- Scale what these are worth against doing the same exercise on real equipment. 1.0 means
    -- a mat gives no advantage, which is honest - a push-up is a push-up. Drop it to 0.8 if you
    -- would rather players had a reason to go to a gym.
    gainScale = 1.0,

    -- Refuse when the ground is not flat enough to lie down on. Nothing looks worse than
    -- push-ups on a 40-degree hillside.
    requireFlatGround = true,
    maxGroundAngle = 20.0,          -- degrees

    -- Keep the normal cooldowns. Off would let a player alternate the five exercises above
    -- forever, which fatigue already makes pointless but which still looks silly.
    respectCooldowns = true,
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

    --[[
        A marker on the ground under usable equipment.

        OFF BY DEFAULT, because it looks bad. The native markers are a fixed set of flat
        sprites, and the ring - type 27, the least bad of them - draws a hard white circle that
        clips through the prop it is meant to highlight and does not follow its shape. On a rack
        of dumbbells it reads as a rendering fault rather than as a hint.

        The floating prompt above the prop already says what the equipment is and what key to
        press, which is the whole job. Turn this on if you want the extra cue anyway; the
        values below are tuned to be as unobtrusive as the natives allow.
    ]]
    --[[
        HOW DIRECTLY YOU HAVE TO BE LOOKING AT SOMETHING FOR THE PROMPT TO BE ABOUT IT.

        The dot product of the camera's forward vector against the direction to the equipment:
        1.0 is dead ahead, 0.0 is straight out to the side, so a higher number is a narrower cone.

            0.85    tight - you must be looking almost straight at it
            0.55    the default, roughly a 57 degree half-angle
            0.0     anything in front of you at all
           -1.0     aim is ignored entirely, and the nearest piece of equipment always wins

        THIS EXISTS BECAUSE THE PROMPT USED TO IGNORE AIM. It offered whatever was nearest inside
        eight metres, which in a gym is a dozen things: standing in front of a machine this resource
        does not know, with a bench behind you, it offered the bench press - and pressing the key
        lay the player down at that bench, off screen, which looks exactly like a character doing a
        bench press in mid-air.

        When nothing at all falls inside the cone the nearest still wins, so the prompt never
        vanishes just because you looked away from a bench you are standing on.
    ]]
    aimCone = 0.55,

    marker = {
        enabled = false,
        type = 27,                          -- 27 is the flat ring; 1 is a cylinder
        scale = vector3(0.45, 0.45, 0.15),
        colour = { 255, 255, 255, 45 },
        distance = 6.0,                     -- draw within this many metres
        zOffset = 0.02,
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

    --[[
        THE KEYS.

        Six keys, all under the left hand, and nothing else. A QTE that reaches for SPACE or R
        makes the player move their hand off the cluster and miss the next prompt for a reason
        that has nothing to do with timing.

        `control` is the GTA control index. THE CONTROLS ARE THE SAME ON EVERY KEYBOARD - the
        game maps them to physical key POSITIONS - so the six below are:

            AZERTY      A  Z  E  Q  S  D
            QWERTY      Q  W  E  A  S  D

        ...which is the same six physical keys either way. Only the letters printed on them
        differ, which is what `keyboardLayout` below is for.

        The whole list is held disabled for the duration of a session and read back with
        IsDisabledControlJustPressed, so hitting a prompt never also walks the player off the
        bench.
    ]]
    keyPool = {
        { control = 44, azerty = 'A', qwerty = 'Q' },    -- INPUT_COVER
        { control = 32, azerty = 'Z', qwerty = 'W' },    -- INPUT_MOVE_UP_ONLY
        { control = 38, azerty = 'E', qwerty = 'E' },    -- INPUT_PICKUP
        { control = 34, azerty = 'Q', qwerty = 'A' },    -- INPUT_MOVE_LEFT_ONLY
        { control = 33, azerty = 'S', qwerty = 'S' },    -- INPUT_MOVE_DOWN_ONLY
        { control = 35, azerty = 'D', qwerty = 'D' },    -- INPUT_MOVE_RIGHT_ONLY
    },

    -- Which letters to draw in the boxes.
    --   'auto'   - azerty when the locale is French, qwerty otherwise
    --   'azerty' | 'qwerty'
    --
    -- The game cannot be asked this reliably: GetControlInstructionalButton returns an internal
    -- token like `b_1004` for several controls rather than a letter, which is exactly how a
    -- prompt ends up reading "hold [b_1004] to stop".
    keyboardLayout = 'auto',

    -- Never ask for the same key twice in a row inside one sequence. Two identical boxes
    -- side by side read as one long press and players hate it.
    noRepeats = true,

    -- The key that cancels a session in progress. 177 is BACKSPACE (INPUT_CELLPHONE_CANCEL).
    -- A cancelled session pays out for the reps already completed.
    cancelKey = 177,

    -- What to call it on screen. '' asks the game, which answers `b_1004` for this one - so it
    -- is written out instead. Change it if you change `cancelKey`.
    cancelLabel = 'RETOUR',

    --[[
        Collapse when the player fails.

        `maxMisses` consecutive misses means the character could not hold the weight, and one
        who simply stands up and walks off looks like nothing happened. Dropping them on the
        floor is the feedback: it costs nothing, it is unmistakable, and it is funny.

        Applied AFTER the animation is cleared, because clearing tasks cancels a ragdoll.
        Cancelling a session by hand does NOT ragdoll - that is giving up, not failing.
    ]]
    ragdollOnFail = {
        enabled = true,
        durationMs = 2200,
    },

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
        --[[
            `showStatGains` USED TO BE HERE. It promised a live "+0.42 STR" readout during a workout,
            and there is nothing to draw it from: the client is never told what a session is worth,
            because the SERVER derives the payout from the player's stored state, their fatigue and
            their allowance, and only answers once the session is over. Showing a running total would
            mean either duplicating that maths on the client or having the client guess - and the
            first is the drift this resource avoids everywhere else.

            The finished total is shown when the session pays out, which is the honest moment for it.
        ]]
        showJudgement = true,       -- the PERFECT / GOOD / MISS flash
        judgementMs = 550,
    },

    -- Hide the rest of the game's HUD while a session runs, so the workout panel is the only
    -- thing on screen. The radar is a separate flag because a player who cannot see the map
    -- also cannot see somebody walking up behind them.
    hideHudDuringSession = false,
    hideRadarDuringSession = false,

    -- The stats panel, opened with /vsport. Also drawn natively.
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
-- Training that happens without a prop, because a body does not only improve in a gym. Four
-- activities: sprinting on foot, riding a bicycle, swimming on the surface and diving under it.
--
-- ------------------------------------------------------------------------------------------
-- THE EQUIPMENT HAS TO STAY BETTER, AND THREE SEPARATE MECHANISMS MAKE SURE OF IT
-- ------------------------------------------------------------------------------------------
--
--   1. THE RATES ARE LOW. A dedicated gym player earns roughly 7.7 points a day. `dailyCapTotal`
--      below holds every passive activity combined to 2.0, so the best possible day of swimming
--      and cycling is about a quarter of a day in the gym.
--
--   2. A CEILING PER ACTIVITY. `ceiling` stops an activity raising a stat past a value at all.
--      At the default 60, swimming will carry your lung capacity to 60% and not one point
--      further - the last 40 needs yoga, or a bench, or a bar. This is the strongest lever in
--      the section and the one to reach for first if passive training feels too generous.
--
--   3. IT DOES NOT STOP DECAY. `countsAsTraining` is false, so a passive gain does not reset
--      the decay clock. A player who cycles every day and never trains still loses 5 a day, and
--      since the cap is 2.0 they lose ground. Passive training supplements a routine; it cannot
--      be one.
--
-- All of it goes through the allowance ledger like a real session, so running across the map is
-- not a way around the 50-points-per-25-hours rule either.
--
-- ------------------------------------------------------------------------------------------
-- WHAT A REAL DAY LOOKS LIKE
-- ------------------------------------------------------------------------------------------
--
--   a 10 km sprint across the city        0.80 stamina
--   an hour on a bicycle (~25 km)         1.00 stamina  (capped), 0.25 breath
--   twenty minutes of diving             1.50 breath   (capped), 0.75 stamina -> capped
--   one perfect session on a bench       1.15 strength, 0.17 stamina, in ninety seconds
--
-- Every number below is yours to change. Setting `enabled = false` on all four ends the client
-- thread at its first line, so the feature costs literally nothing when it is off.

Config.Passive = {
    -- The master switch. False disables all four activities regardless of their own flags.
    enabled = true,

    -- Multiplies every gain in this section. The one number to turn if the whole idea is either
    -- too generous or too stingy on your server. 0.5 halves everything; 2.0 doubles it.
    globalScale = 1.0,

    --[[
        Ceiling shared by every activity that does not name its own.

        Passive training may not raise a stat above this. A player at or above it earns nothing
        from the activity - not a reduced amount, nothing - and the equipment becomes the only
        route. Set to 100.0 to remove the idea entirely, or to 0 to make passive training purely
        cosmetic.
    ]]
    ceiling = 60.0,

    --[[
        Whether a passive gain counts as having trained, for the decay clock and for fatigue.

        FALSE is the balanced answer and the default. A player who swims all day has earned some
        lung capacity but has not been to the gym, so the 10-per-day decay keeps running and the
        fatigue window stays clear.

        TRUE turns passive activity into a way of holding condition without ever training, which
        is a legitimate choice for a survival or a fishing server - just know that it removes the
        pressure to use the equipment at all.
    ]]
    countsAsTraining = false,

    -- Every activity combined may earn this many points in one 24 hour period. 0 is uncapped.
    -- This is the ceiling on the whole section and the number to compare against a gym day.
    dailyCapTotal = 2.0,

    -- Show a toast when a batch pays out. Off by default: a notification every thirty seconds
    -- while jogging is noise. Turn it on to confirm the feature works, then turn it back off.
    notify = false,

    -- Reports go to the server in batches this often, in seconds, rather than every tick.
    -- Fewer, larger events are cheaper and easier to sanity-check. Minimum 5.
    reportInterval = 30,

    -- ---------------------------------------------------------------------------------------
    -- THE ACTIVITIES
    -- ---------------------------------------------------------------------------------------
    --
    -- Each one takes:
    --
    --   enabled     its own switch
    --   gains       { stat = points } PER KILOMETRE for the distance activities, PER MINUTE for
    --               diving. Any number of stats, including ones you added yourself in section 3.
    --   dailyCap    points from THIS activity in 24 hours, across all its stats. 0 is uncapped.
    --   ceiling     overrides Config.Passive.ceiling for this activity only. nil uses the shared
    --               one.
    --   minSpeed    m/s below which movement does not count, so walking earns nothing
    --   maxSpeed    m/s above which it is a teleport or a vehicle rather than the activity. Also
    --               what the SERVER uses to work out the most a report could honestly contain.

    --[[
        Sprinting on foot. `minSpeed = 4.0` excludes walking and jogging, so this is a real run.

        At 0.08 a kilometre, a full marathon is 3.4 points before the cap - about three gym
        sessions for 42 km, which is the ratio you want between "went to the gym" and "happened
        to run somewhere".
    ]]
    running = {
        enabled = true,
        gains = { stamina = 0.08 },
        requireSprint = true,       -- holding the sprint key, not merely moving fast
        minSpeed = 4.0,
        maxSpeed = 12.0,
        dailyCap = 1.0,
    },

    --[[
        A bicycle. Deliberately the WORST of the four per kilometre, because a bike in this game
        covers ground almost for free: 25 km of cycling and 10 km of running come out about the
        same, which is roughly the honest ratio.

        Only pedal cycles count - vehicle class 13. A motorbike is not exercise.
    ]]
    cycling = {
        enabled = true,
        gains = { stamina = 0.05, breath = 0.01 },
        vehicleClasses = { 13 },    -- 13 is Cycles. Add classes at your own risk.
        requirePedalling = true,    -- moving under the rider's own power, not coasting downhill
        minSpeed = 4.0,
        maxSpeed = 18.0,
        dailyCap = 1.0,
    },

    --[[
        Swimming on the surface. Worth far more per kilometre than running, and it has to be:
        a swimmer moves at about 1.5 m/s, so a kilometre is eleven minutes of real time against
        under two for the same distance sprinting.
    ]]
    swimming = {
        enabled = true,
        gains = { stamina = 0.30, breath = 0.15 },
        minSpeed = 0.6,
        maxSpeed = 4.0,
        dailyCap = 1.0,
    },

    --[[
        Underwater, and measured in TIME rather than distance, because holding your breath is
        the exercise whether or not you go anywhere.

        The best passive source of lung capacity in the resource, and still under a fifth of what
        yoga pays per minute. `minDiveSeconds` is what stops bobbing under a wave twenty times
        from earning anything: a dive is only credited once the player surfaces, and only if it
        lasted.
    ]]
    diving = {
        enabled = true,
        gains = { breath = 0.25, stamina = 0.08 },
        minDiveSeconds = 8,
        maxDiveSeconds = 600,       -- longer than this is a bug or a trainer, not a dive
        dailyCap = 1.5,

        -- Diving trains the one stat that is otherwise hard to raise outdoors, so it gets a
        -- higher ceiling than the rest. Still not 100: yoga stays the way to the top.
        ceiling = 75.0,
    },
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

    --[[
        A buff can push the EFFECTIVE value this far above the stat's max. The trained value is
        never touched.

        WHAT IT DOES NOT DO, and this was documented wrongly for a while: it does NOT push the
        section 7 effects past their configured maximum. `Stats.bonus` clamps the value to the
        stat's own max before interpolating, so a character buffed to 120 strength hits melee for
        exactly the 1.25 that a character at 100 does. Same for the GTA character stats, which
        clamp the same way.

        So the ceilings in section 7 are HARD. No combination of supplements, drugs or admin
        commands can take melee damage past its `max`, which is the guarantee that nobody becomes
        a superhero however many resources are stacking buffs. The check script asserts it.

        What overcap is actually for: the number the panel shows, and what GetEffectiveStat
        reports to other resources. A drug script can see that its supplement is working and can
        drive its own consequences from the overshoot. Set it to 0 if even that is unwanted.
    ]]
    overcap = 20.0,

    -- And this far below zero, for a debuff. Effective values are clamped at 0 regardless.
    undercap = 0.0,

    -- The largest number a single call may pass, as a guard against a bug in somebody else's
    -- resource wiping a player's progress. A call outside this is clamped and logged.
    maxSingleChange = 100.0,
    maxDurationSeconds = 24 * 3600,

    -- --- Bounds on the harsher external mechanics -------------------------------------
    --
    -- These four exist because a drug or smoking script asking to make somebody worse can do
    -- more damage than one asking to make them better, and a bug in it should cost a console
    -- warning rather than a character.
    --
    -- All of them are documented, with worked smoking and addiction examples, in API.md.

    -- How much faster another resource may make decay run for a player.
    -- SetDecayMultiplier(src, 2.0, ...) makes a heavy smoker lose condition twice as fast.
    maxDecayMultiplier = 5.0,

    -- Points per hour a continuous drain may take. AddDrain is the "your body is giving up
    -- while this is in your system" mechanic, and at 10 it can empty a maxed stat in ten
    -- hours, which is already brutal.
    maxDrainPerHour = 10.0,

    -- The lowest a resource may cap a stat at with SetStatCeiling. A smoker whose stamina
    -- cannot pass 60 is a mechanic; one whose stamina cannot pass 2 is a bug report.
    minStatCeiling = 10.0,

    -- Whether a ceiling also pulls a stat that is ALREADY above it down to the cap.
    -- false (the default) only stops further gains, which is the kinder and more predictable
    -- reading: taking up smoking does not delete training you already did, it stops you
    -- building on it.
    ceilingTrimsExisting = false,

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

-- Every command is prefixed so that nothing this resource registers can collide with a
-- `/sport` from somebody else's script. Rename any of them freely; '' does not register it.
Config.Commands = {
    stats = 'vsport',               -- open the stats panel
    info = 'vsportinfo',            -- print what was detected, to F8
    scan = 'vsportscan',            -- list nearby objects and whether they are known
    spot = 'vsportspot',            -- print a Config.Spots line for where you stand
    offset = 'vsportoffset',        -- print a modelOverrides offset for the prop you face
    tune = 'vsportprop',            -- LIVE alignment: nudge the body and the prop until it fits
    goto_ = 'vsportgoto',           -- teleport to a machine, or list what is streamed in nearby
    find = 'vsportfind',            -- sweep the WHOLE MAP for one prop model and report where
    admin = 'vsportadmin',          -- set / add / reset another player's stats
    dev = 'vsportdev',              -- re-ask the server whether you may use the tools above

    --[[
        ADDING EQUIPMENT FROM INSIDE THE GAME. See PROPS.md.

        The short version, standing in your own gym MLO:

            /vsportadd treadmill        the prop you are LOOKING AT becomes a treadmill
            /vsportprop treadmill       align the body, press K to save it for everyone
            /vsportexport               print it as a config.lua block when it is proven

        Nothing is edited and nothing is restarted: the addition lives in data/custom.json, is
        pushed to every client, and both sides rebuild the catalogue in place. Set any of these
        to '' to remove that command; the file-backed system keeps working without it.
    ]]
    add = 'vsportadd',              -- add the prop you face to an exercise
    remove = 'vsportremove',        -- take it back out
    custom = 'vsportcustom',        -- list what has been added in game
    export = 'vsportexport',        -- print it all as a config.lua block
    reload = 'vsportreload',        -- re-read data/custom.json from disk
    reset = 'vsportreset',          -- forget one exercise's additions, or all of them

    -- Print the item blocks to paste into your inventory, generated from Config.Items so a
    -- rename or a weight change never leaves the documentation lying.
    items = 'vsportitems',

    -- Ask the GAME whether any sport prop is missing from the catalogue, in both directions.
    -- Tests Config.Debug.candidateModels with IsModelValid; add your MLO's names to that list.
    missing = 'vsportmissing',

    -- Walk every prop of every exercise in the studio, judge each animation with 1 or 2, and get
    -- a list of the wrong ones in F8 at the end. The only way to know an animation looks right on
    -- a given prop is to look at it, and this is 43 looks without 43 commands.
    tour = 'vsporttour',

    -- The ace a player needs for `admin` and for the developer commands. The framework's own
    -- idea of an admin is accepted as a fallback, so a server that never set an ace up is
    -- not locked out.
    adminAce = 'command.vsportadmin',

    --[[
        WHICH COMMANDS ARE RESTRICTED, AND WHY IT MATTERS MORE THAN IT SOUNDS.

        `info`, `scan`, `spot`, `offset`, `tune`, `goto_` and `find` are developer tools. Two of
        them TELEPORT the player - `goto_` across the map, `tune` into the sky - and `find` drives
        the player over the entire map for half an hour. Left open they are a free teleport sitting
        in every player's chat suggestions.

        `stats` is never restricted: the panel is for players.

        The check is made SERVER-SIDE by Bridge.isAdmin - the configured ace first, the framework's
        own idea of staff as a fallback - and pushed to the client, which refuses everything until
        an answer arrives. An admin promoted mid-session can run `/vsportdev` to ask again.

        Set to false on a development server. Nowhere else.
    ]]
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
    --[[
        `requireToken` USED TO BE HERE and was read by nothing, so "leave it on" described something
        that was never a choice: a session with no valid token has always been refused, and there is
        no code path that would honour false. Offering a switch that cannot move is worse than not
        offering one - somebody sets it, believes they changed something, and reasons from that.
    ]]

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
    --[[
        `flushInterval` USED TO BE HERE. The save cadence is Config.Persistence.saveInterval, which
        is where the documentation always said it was and which nothing read until 1.0.1: this field
        was in force at 30 while the documented one sat at 60 with no effect. One behaviour, one
        setting, and it lives with the rest of persistence.
    ]]

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

    --[[
        Prop models the live alignment tool (/vsportprop) can cycle through.

        Which object goes in a player's hands is as much a judgement call as where it goes, and
        it cannot be settled from outside the game: several of these names do not exist in every
        build, and the ones that do look different from what you would guess. So the tool cycles
        them with the arrow keys and you pick the one that looks right.

        The exercise's own configured prop is always offered first, and 'none' is always an
        option. A name that does not exist is skipped with a note rather than breaking the cycle.

        Only this tool reads this list. It has no effect on normal play.
    ]]
    tuneProps = {
        -- Confirmed to exist.
        'prop_barbell_01',
        'prop_bench_08',
        'prop_weight_squat',
        -- Plausible, and worth a look. Both spellings of dumbbell on purpose.
        'prop_barbell_02',
        'prop_dumbbell_01', 'prop_dumbell_01',
        'prop_curl_bar_01',
        'prop_kettlebell_01',
        'prop_skipping_rope_01',
        'prop_boxing_glove_01',
        'prop_yoga_mat_01',
        -- Not gym equipment, but useful for judging scale and grip while aligning.
        'prop_tool_sledgeham',
        'prop_cs_bottle_01',
    },

    --[[
        Known-good starting position and rotation per prop model, for the alignment tool.

        A hand bone's local frame is tilted, so a prop attached at rot (0, 0, 0) does not
        necessarily start level - which makes it fiddly to place from scratch every time. Once
        you have levelled a model with /vsportprop, put its numbers here and every future
        alignment of that model starts straight.

        Cycling to a model with no entry starts it at zero, which is the bone's own orientation
        and the same baseline the game uses for objects it puts in a ped's hands.

        Only the alignment tool reads this. What normal play uses is the `props` block on the
        exercise itself, in shared/equipment.lua.
    ]]
    --[[
        Places /vsportgoto will hop to when the model it is looking for is not streamed in.

        THE OBJECT POOL ONLY CONTAINS WHAT IS LOADED - a few hundred metres. A prop that exists
        only on the far side of the map is invisible to any search, so "find me one" cannot work
        from where you are standing. The command teleports to each of these in turn, waits for the
        world to stream, and scans; the first hit is where you stay, and if nothing is found
        anywhere you are put back where you started.

        THIS LIST IS A STARTING POINT AND IT IS INCOMPLETE. Only the first entry is confirmed by
        having been played on. Adding one is easy: stand where the equipment is, run
        /vsportspot <anything>, and copy the coordinates it prints into a new line here. The name
        is only used in the console log.

        Only /vsportgoto reads this. It has no effect on normal play.
    ]]
    --[[
        MEASURED, not guessed. Every coordinate below came out of a real /vsportfind sweep of the
        whole map, so each one is a place where the named prop actually is.

        This is what makes the targeted search fast: /vsportgoto tries these before giving up, so
        finding a specific model takes seconds instead of half an hour.
    ]]
    searchSpots = {
        -- Muscle Sands, the outdoor gym on the Vespucci Beach sidewalk.
        { name = 'Muscle Sands, Vespucci Beach', coords = vector3(-1200.31, -1568.46, 4.61) },

        -- Where the sweep found each thing. The count is how many were visible from that stop.
        { name = 'freeweights x2',        coords = vector3(-1800.0, -680.0, 16.15) },
        { name = 'barbells x2',           coords = vector3(-3000.0, 400.0, 16.90) },
        { name = 'barbell_02 x1',         coords = vector3(-960.0, 160.0, 67.25) },
        { name = 'curl bars x5',          coords = vector3(-2040.0, 3280.0, 34.81) },
        { name = 'squat rack + plates',   coords = vector3(1680.0, 2440.0, 57.17) },
        { name = 'beach bars x3',         coords = vector3(-1800.0, 160.0, 70.77) },
        { name = 'rings x2',              coords = vector3(-2040.0, 3280.0, 34.81) },
        { name = 'dip bars x5',           coords = vector3(-1920.0, 3280.0, 35.00) },
        { name = 'yoga mats x4',          coords = vector3(-1440.0, 880.0, 186.70) },
        { name = 'exercise bikes x4',     coords = vector3(-2040.0, -320.0, 26.17) },
        { name = 'skipping rope x1',      coords = vector3(-1320.0, 520.0, 105.66) },
        { name = 'volleyballs x4',        coords = vector3(-1800.0, -800.0, 9.88) },
        { name = 'park benches x20',      coords = vector3(-1200.0, 400.0, 76.55) },
    },

    --[[
        THE WHOLE-MAP SWEEP, for a model that is in none of the spots above.

        A curated list can only ever cover places somebody already knew about, and every gym MLO
        on every server is somewhere different. So `/vsportfind <model>` walks a GRID across the
        map instead: teleport, wait for the world to stream, scan, move on. It reports EVERY
        location it finds, as lines ready to paste into `searchSpots` above - so the slow search
        happens once and the result is reusable.

        BE HONEST ABOUT THE COST. At the defaults this is roughly 600 stops at about a second
        each, so ten to fifteen minutes, and it is cancellable at any point. It is a development
        task you run once per model you cannot find, not something to leave enabled.

        The bounds cover the land mass and skip most of the ocean. `step` should stay under the
        object streaming radius or props will be missed between stops.
    ]]
    --[[
        A SWEEP PROVES PRESENCE. IT NEVER PROVES ABSENCE. Read that before trusting a result.

        The first version ran at a 400 metre step and reported 38 models as "not placed anywhere
        on this map" - including two the operator had walked up to and used minutes earlier. The
        step was simply larger than the distance at which small props stream in, so anything
        sitting between two stops was invisible and got reported as non-existent.

        `step` must stay UNDER the object streaming radius, which is roughly 150 metres for small
        props - not the several hundred that terrain and buildings load at. That is why the honest
        default is slow: covering the map at 150m is about four thousand stops.

        So: a hit is a fact. A miss means "not seen at the stops that were made", and the way to
        settle it is a targeted /vsportgoto once you are in the right district.
    ]]
    sweep = {
        fromX = -3600.0, toX = 4400.0,
        fromY = -4400.0, toY = 7600.0,

        --[[
            Under the small-prop streaming radius, with margin.

            Small props stream at roughly 100 to 180 metres depending on the client's graphics
            settings, so 120 leaves room for the low end rather than sitting on the optimistic
            estimate. This is the number that decides whether a MISS means anything, and it is
            the only reason the sweep is slow.
        ]]
        step = 120.0,

        -- Milliseconds spent at each stop waiting for props to appear. Below about 300 the scan
        -- runs against a half-loaded world and misses things that are right there.
        dwellMs = 350,

        --[[
            Skip stops that are over open water.

            Roughly half of the bounding box is sea, and nothing in this catalogue is ever placed
            on it. Skipping those costs one cheap native and saves an hour, which is the
            difference between a sweep somebody actually runs and one they abandon.

            Turn it off if your map adds floating platforms or a boat gym.
        ]]
        skipWater = true,
    },

    --[[
        THE STUDIO. Where /vsportprop spawns a piece of equipment when it cannot find a real one.

        This removes the whole "go and find one" problem, and it works because the alignment tool
        ATTACHES the ped to the prop: with no physics in play there is no need for ground, for
        collision, or for the model to exist anywhere on the map. A model that is in the game files
        but placed nowhere can be aligned perfectly, in the sky, in ten seconds.

        High over open water on purpose. Nothing to clash with, nothing to fall on, and a clean
        silhouette against the sky - which makes a floating limb or a bar at the wrong angle far
        easier to see than the same thing against a cluttered gym floor.
    ]]
    --[[
        CANDIDATE MODEL NAMES FOR /vsportmissing.

        "Have we missed a prop?" cannot be answered from a list, because every published GTA prop
        dump is incomplete - the one used to build this list has no prop_weight_squat and no
        prop_pris_bench_01, and both are real and in use here. So the question is put to the GAME:
        /vsportmissing runs IsModelValid over every name below and reports the ones that exist in
        your build and are NOT in the catalogue.

        It answers in both directions, which is the useful part:

          exists here, not in the catalogue     a real gap - add it with /vsportadd
          in the catalogue, does not exist      a dead entry, harmless but worth knowing

        The second column is how the original 85 phantom names were found. A name that does not
        exist hashes to a number no object will ever carry, so it fails silently and forever.

        ADD YOUR OWN. Names from your gym MLO belong here: run the command once and it tells you
        which of them the game actually has, which beats guessing at spellings in a config file.
    ]]
    candidateModels = {
        -- The prison yard. Both of these were missing from the catalogue until a player reported
        -- that the beach worked and the yard did not.
        'prop_pris_bench_01', 'prop_pris_bench_02',
        'prop_pris_bars_01', 'prop_pris_bars_02',
        'prop_pris_weight_01', 'prop_pris_bench_03',

        -- Heavy bags. prop_punch_bag_l came out of a prop dump cross-check.
        'prop_punch_bag_l', 'prop_punch_bag_s', 'prop_punch_bag_01',
        'prop_boxing_bag', 'prop_boxing_bag_01', 'prop_speed_bag_01',

        -- Benches and racks, past the six the catalogue knows.
        'prop_muscle_bench_07', 'prop_muscle_bench_08',
        -- The 02s of both families turned out to exist and the 01 of the bench does not, so the
        -- neighbours are worth asking about too. A family is not necessarily numbered from one.
        'prop_weight_bench_01', 'prop_weight_bench_03', 'prop_weight_bench_04',
        'prop_weight_rack_03', 'prop_weight_rack_04',
        'prop_weight_squat_01', 'prop_weight_squat_02',

        -- Bars, rings and beach fitness.
        'prop_beach_bars_03', 'prop_beach_rings_02', 'prop_beach_dip_bars_03',
        'prop_beach_fitness_01', 'prop_chinup_bar_01', 'prop_pullup_bar_01',

        -- Free weights, past the thirteen the catalogue knows.
        'prop_freeweight_03', 'prop_dumbbell_01', 'prop_dumbell_01',
        'prop_curl_bar_02', 'prop_barbell_03',

        -- Cardio machines. All of these are the names gym MLOs use; the base game has none.
        'prop_treadmill_01', 'prop_treadmill_02', 'prop_gym_treadmill',
        'prop_exer_bike_02', 'prop_exercise_bike_01',
        'prop_rowing_machine_01', 'prop_rower_01',
        'prop_leg_press_01', 'prop_cable_machine_01', 'prop_lat_pulldown_01',
        'prop_kettlebell_01', 'prop_kettlebell_02', 'prop_battle_rope_01',

        -- Mats.
        'prop_yoga_mat_04', 'prop_gym_mat_01', 'prop_exercise_mat_01',

        -- Generic gym names, and the interior variants some maps use.
        'prop_gym_bench_01', 'prop_gym_bench_02', 'prop_gym_bench_03',
        'prop_gym_rack_01', 'prop_gym_weight_01',
        'v_ilev_gym_bench', 'v_ilev_gym_weights',
    },

    tuneStudio = {
        --[[
            REAL GROUND, AND THAT IS THE WHOLE POINT OF THIS COORDINATE.

            The studio used to be a hundred metres over open water: nothing to stand in, nothing to
            clash with, a clean silhouette. It was also WRONG, in a way that took a while to surface.

            With no ground, the floor the tool drew came from GetModelDimensions - the model's
            bounding box. A bounding box is not the visible bottom of a prop: it is frequently
            lower, because it wraps collision and any stray geometry. So the drawn floor sat below
            where the prop really rests, every body aligned against it was measured too low, and in
            the world the player's feet went through the ground. Every ground prop measured in the
            sky inherited the same error.

            This is the north end of the LSIA runway apron: a very large, very flat, reliably
            streamed piece of tarmac with nothing on it. The prop is placed on it with
            PlaceObjectOnGroundProperly - the same native the map itself uses - and the player
            stands on the same surface. What you see is then exactly what a player will see, which
            is the only property that makes a measurement worth taking.
        ]]
        coords = vector3(-1336.0, -3044.0, 13.95),

        --[[
            USE THE STUDIO ALWAYS, OR ONLY AS A FALLBACK.

            OFF BY DEFAULT, and this was on for a while and produced wrong numbers. The reasoning is
            worth reading before turning it back on.

            `animOffset` is measured from the PROP'S ORIGIN. How high that origin sits above the
            ground is decided by whoever placed the prop on the map, not by the model - the squat
            rack at Muscle Beach has its origin 90 cm up. The studio cannot know that. It settles the
            prop with PlaceObjectOnGroundProperly, which produces its own height, and any offset
            measured against that is wrong in the world by the difference between the two.

            That is exactly what happened: the squat rack measured 0.59 in the studio and put the
            player's pelvis a metre and a half above the ground in the gym, half a metre too high.

            THE EVIDENCE IS ONE-SIDED. Every offset in this resource that has survived contact with
            the game was measured against a REAL prop in its real place - prop_muscle_bench_03 among
            them, still correct after everything. Every offset measured in the studio has needed
            redoing at least once.

            So: the real prop first, the studio only when no specimen can be found. The studio is
            still worth having - a model that the map places nowhere has no ground truth to measure
            against anyway, and a server whose own MLO places one can align it there - but it is a
            last resort rather than the method.
        ]]
        always = false,
    },

    tunePropDefaults = {
        -- ['prop_barbell_01'] = {
        --     pos = vector3(0.140, 0.050, 0.000),
        --     rot = vector3(0.0, 90.0, 0.0),
        -- },
    },
}
