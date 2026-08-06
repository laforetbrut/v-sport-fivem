--[[
    ===========================================================================================
    v-sport / shared/equipment.lua
    ===========================================================================================

    THE EQUIPMENT CATALOGUE. This is a configuration file; it lives in `shared/` only because
    both sides read it. Edit it freely.

    Each entry maps a set of prop models onto one exercise, and says what that exercise trains.

    -------------------------------------------------------------------------------------------
    FIELDS
    -------------------------------------------------------------------------------------------

      order         Sort position in menus and in /sportinfo. Low first.
      label         Locale key, or plain text if you would rather not translate it.
      description   Locale key for the line under the name.

      models        Prop model names. Hashed once at load into a lookup table.

                    A NAME THAT DOES NOT EXIST IN YOUR GAME COSTS NOTHING. It hashes to a
                    number no entity will ever carry, so it simply never matches. That is why
                    the lists below are generous and include several spellings of the same
                    idea: over-listing is free, under-listing means a prop nobody can use.

                    A raw hash works too, for a model whose name you do not know:
                        models = { 1234567890 }

      gains         What one PERFECT session is worth, expressed in SESSIONS of that stat.
                    { strength = 1.0 } is one full session, so with the default
                    sessionsToMax = 100 it is one point. { strength = 0.5, stamina = 0.5 }
                    trains both at half rate. The totals do not have to add up to 1.0 - a
                    piece of equipment that is simply better can be worth more, and a lazy
                    one less.

      reps          How many repetitions a session asks for. More reps is a longer session
                    and more chances to miss, not a bigger reward: the reward is `gains`.

      difficulty    A key from Config.Minigame.difficulties.
      minigame      Optional per-equipment overrides of that preset, same shape.

      cooldown      Seconds before the same player may use this equipment again. Defaults to
                    Config.Security.defaultCooldown.

      scenario      A GTA scenario name, played for the whole session. Scenarios handle their
                    own prop attachment and their own transitions, which is why they are the
                    default choice here.
      anim          { dict, clip, flag } played instead when it is set AND the dictionary
                    loads. Falls back to `scenario` when the dictionary is missing, and to
                    nothing at all when neither works - the session still runs.

      offset        vector3, in the PROP's local space, where the player is placed.
                    Positive Y is in front of the prop. nil leaves the player where they are.
      heading       Degrees added to the prop's own heading for the player to face.
                    nil keeps the player's heading.
      snap          Whether to actually move the player to `offset`. false uses the offset
                    only to decide which side of the prop the prompt appears on.

      trains        Optional. Restrict which stats this equipment may raise past a value,
                    e.g. `trains = { strength = 60 }` makes a home dumbbell useless above 60
                    strength and pushes players towards a real gym. nil is no ceiling.

      require       Optional gate. { stats = { strength = 40 }, job = 'police',
                    item = 'gymmembership' }. An unmet requirement shows the reason.

      enabled       false keeps the entry as documentation without registering it.
]]

Equipment = {}

-- ===========================================================================================
-- The catalogue
-- ===========================================================================================

Equipment.catalogue = {

    -- --- Free weights ----------------------------------------------------------------

    bench_press = {
        order = 10,
        label = 'equip.bench_press',
        description = 'equip.bench_press_desc',
        models = {
            'prop_gym_bench_01', 'prop_gym_bench_02', 'prop_gym_bench_03',
            'prop_bench_press_01', 'prop_weight_bench_01', 'prop_bench_press',
            'v_ilev_gym_bench', 'prop_gym_bench_press',
        },
        gains = { strength = 1.0, stamina = 0.15 },
        reps = 8,
        difficulty = 'normal',
        cooldown = 90,
        scenario = 'WORLD_HUMAN_MUSCLE_FREE_WEIGHTS',
        offset = vector3(0.0, -0.85, 0.0),
        heading = 0.0,
        snap = true,
    },

    free_weights = {
        order = 11,
        label = 'equip.free_weights',
        description = 'equip.free_weights_desc',
        models = {
            -- Both spellings on purpose: the community list has carried the single-L
            -- misspelling for years and some MLOs ship it that way.
            'prop_dumbbell_01', 'prop_dumbell_01', 'prop_dumbbell_02', 'prop_dumbell_02',
            'prop_barbell_01', 'prop_barbell_02', 'prop_curl_bar_01',
            'prop_gym_dumbbell_01', 'prop_weight_01', 'prop_weights_01',
            'prop_gym_weights_01', 'prop_gym_weight_rack',
        },
        gains = { strength = 0.85, stamina = 0.1 },
        reps = 10,
        difficulty = 'normal',
        cooldown = 60,
        scenario = 'WORLD_HUMAN_MUSCLE_FREE_WEIGHTS',
        offset = vector3(0.0, 0.7, 0.0),
        heading = 180.0,
        snap = true,
    },

    weight_rack = {
        order = 12,
        label = 'equip.weight_rack',
        description = 'equip.weight_rack_desc',
        models = {
            'prop_gym_rack_01', 'prop_squat_rack_01', 'prop_weight_rack_01',
            'prop_gym_weight_rack_01', 'prop_power_rack_01',
        },
        gains = { strength = 1.1 },
        reps = 6,
        difficulty = 'hard',
        cooldown = 120,
        scenario = 'WORLD_HUMAN_MUSCLE_FREE_WEIGHTS',
        offset = vector3(0.0, 0.6, 0.0),
        heading = 180.0,
        snap = true,
    },

    kettlebell = {
        order = 13,
        label = 'equip.kettlebell',
        description = 'equip.kettlebell_desc',
        models = {
            'prop_kettlebell_01', 'prop_gym_kettlebell_01', 'prop_kettle_bell_01',
        },
        gains = { strength = 0.6, stamina = 0.4 },
        reps = 12,
        difficulty = 'normal',
        cooldown = 60,
        scenario = 'WORLD_HUMAN_MUSCLE_FREE_WEIGHTS',
        offset = vector3(0.0, 0.6, 0.0),
        heading = 180.0,
        snap = true,
    },

    -- --- Bodyweight ------------------------------------------------------------------

    pull_ups = {
        order = 20,
        label = 'equip.pull_ups',
        description = 'equip.pull_ups_desc',
        models = {
            'prop_beach_fitness_01', 'prop_beach_fitness_02', 'prop_beach_fitness_03',
            'prop_beach_fitness_04', 'prop_beach_fitness_05',
            'prop_chin_up_bar_01', 'prop_pullup_bar_01', 'prop_gym_chinup_01',
            'prop_muscle_bench_01', 'prop_pull_up_bar',
        },
        gains = { strength = 0.9, stamina = 0.25 },
        reps = 8,
        difficulty = 'hard',
        cooldown = 75,
        -- The chin-up scenario is a PROP_ scenario: it expects to be run at a bar and
        -- positions the ped itself, which is why `snap` is off here.
        scenario = 'PROP_HUMAN_MUSCLE_CHIN_UPS',
        anim = { dict = 'amb@prop_human_muscle_chin_ups@male@base', clip = 'base', flag = 1 },
        offset = vector3(0.0, 0.35, 0.0),
        heading = 180.0,
        snap = false,
    },

    dip_bars = {
        order = 21,
        label = 'equip.dip_bars',
        description = 'equip.dip_bars_desc',
        models = {
            'prop_dip_bars_01', 'prop_gym_dip_01', 'prop_parallel_bars_01',
        },
        gains = { strength = 0.75, stamina = 0.2 },
        reps = 10,
        difficulty = 'normal',
        cooldown = 60,
        scenario = 'PROP_HUMAN_MUSCLE_CHIN_UPS',
        offset = vector3(0.0, 0.0, 0.0),
        snap = false,
    },

    push_ups = {
        order = 22,
        label = 'equip.push_ups',
        description = 'equip.push_ups_desc',
        models = {
            'prop_yoga_mat_01', 'prop_yoga_mat_02', 'prop_yoga_mat_03',
            'prop_gym_mat_01', 'prop_gym_mat_02', 'prop_gym_mat_03',
            'prop_exercise_mat_01', 'prop_fitness_mat_01',
        },
        gains = { strength = 0.55, stamina = 0.45 },
        reps = 12,
        difficulty = 'normal',
        cooldown = 45,
        scenario = 'WORLD_HUMAN_PUSH_UPS',
        anim = { dict = 'amb@world_human_push_ups@male@base', clip = 'base', flag = 1 },
        offset = vector3(0.0, 0.0, 0.0),
        heading = 0.0,
        snap = true,
    },

    sit_ups = {
        order = 23,
        label = 'equip.sit_ups',
        description = 'equip.sit_ups_desc',
        models = {
            'prop_yoga_mat_01', 'prop_yoga_mat_02', 'prop_yoga_mat_03',
            'prop_gym_mat_01', 'prop_gym_mat_02', 'prop_gym_mat_03',
            'prop_ab_bench_01', 'prop_gym_abbench_01',
        },
        gains = { strength = 0.4, stamina = 0.6 },
        reps = 14,
        difficulty = 'normal',
        cooldown = 45,
        scenario = 'WORLD_HUMAN_SIT_UPS',
        anim = { dict = 'amb@world_human_sit_ups@male@base', clip = 'base', flag = 1 },
        offset = vector3(0.0, 0.0, 0.0),
        heading = 0.0,
        snap = true,
    },

    muscle_flex = {
        order = 24,
        label = 'equip.muscle_flex',
        description = 'equip.muscle_flex_desc',
        models = {
            'prop_gym_mirror_01', 'prop_mirror_01', 'prop_gym_mirror',
        },
        -- Posing in the mirror is not training. It is here because a gym should let you do
        -- it, and it pays almost nothing on purpose.
        gains = { strength = 0.1 },
        reps = 4,
        difficulty = 'easy',
        cooldown = 300,
        scenario = 'WORLD_HUMAN_MUSCLE_FLEX',
        anim = { dict = 'amb@world_human_muscle_flex@arms_at_side@base', clip = 'base', flag = 1 },
        offset = vector3(0.0, 0.8, 0.0),
        heading = 180.0,
        snap = true,
    },

    -- --- Combat ----------------------------------------------------------------------

    punching_bag = {
        order = 30,
        label = 'equip.punching_bag',
        description = 'equip.punching_bag_desc',
        models = {
            'prop_boxing_bag_01', 'prop_boxing_bag_02', 'prop_boxing_bag_03',
            'prop_boxing_bag_04', 'prop_punch_bag_01', 'prop_heavy_bag_01',
            'prop_gym_punchbag_01',
        },
        gains = { strength = 0.5, stamina = 0.5, breath = 0.2 },
        reps = 14,
        difficulty = 'hard',
        cooldown = 60,
        -- No shipped scenario punches a bag. The melee idle reads correctly against one and
        -- degrades to a neutral stance if the dictionary is missing.
        anim = { dict = 'melee@unarmed@streamed_core', clip = 'idle', flag = 1 },
        offset = vector3(0.0, 0.9, 0.0),
        heading = 180.0,
        snap = true,
    },

    speed_bag = {
        order = 31,
        label = 'equip.speed_bag',
        description = 'equip.speed_bag_desc',
        models = {
            'prop_speed_bag_01', 'prop_boxing_speedbag_01', 'prop_gym_speedbag_01',
        },
        gains = { stamina = 0.4, strength = 0.2 },
        reps = 16,
        difficulty = 'brutal',
        cooldown = 60,
        anim = { dict = 'melee@unarmed@streamed_core', clip = 'idle', flag = 1 },
        offset = vector3(0.0, 0.7, 0.0),
        heading = 180.0,
        snap = true,
    },

    -- --- Cardio ----------------------------------------------------------------------

    treadmill = {
        order = 40,
        label = 'equip.treadmill',
        description = 'equip.treadmill_desc',
        models = {
            'prop_treadmill_01', 'prop_gym_treadmill_01', 'v_ilev_treadmill',
            'prop_running_machine_01', 'prop_gym_running_01',
        },
        gains = { stamina = 1.0, breath = 0.35 },
        reps = 12,
        difficulty = 'normal',
        cooldown = 90,
        scenario = 'WORLD_HUMAN_JOG_STANDING',
        offset = vector3(0.0, -0.4, 0.0),
        heading = 0.0,
        snap = true,
    },

    exercise_bike = {
        order = 41,
        label = 'equip.exercise_bike',
        description = 'equip.exercise_bike_desc',
        models = {
            'prop_ex_bike_01', 'prop_gym_bike_01', 'prop_exercise_bike_01',
            'prop_spin_bike_01', 'prop_gym_cycle_01',
        },
        gains = { stamina = 0.9, breath = 0.3 },
        reps = 12,
        difficulty = 'easy',
        cooldown = 75,
        scenario = 'WORLD_HUMAN_JOG_STANDING',
        offset = vector3(0.0, -0.3, 0.0),
        heading = 0.0,
        snap = true,
    },

    rowing_machine = {
        order = 42,
        label = 'equip.rowing_machine',
        description = 'equip.rowing_machine_desc',
        models = {
            'prop_rowing_machine_01', 'prop_gym_rower_01', 'prop_rower_01',
        },
        gains = { stamina = 0.7, strength = 0.35, breath = 0.25 },
        reps = 12,
        difficulty = 'normal',
        cooldown = 75,
        scenario = 'WORLD_HUMAN_SIT_UPS',
        offset = vector3(0.0, -0.5, 0.0),
        heading = 0.0,
        snap = true,
    },

    skipping_rope = {
        order = 43,
        label = 'equip.skipping_rope',
        description = 'equip.skipping_rope_desc',
        models = {
            'prop_skipping_rope_01', 'prop_skip_rope_01', 'prop_jump_rope_01',
            'prop_gym_rope_01',
        },
        gains = { stamina = 0.65, breath = 0.45 },
        reps = 16,
        difficulty = 'hard',
        cooldown = 60,
        scenario = 'WORLD_HUMAN_JOG_STANDING',
        offset = vector3(0.0, 0.5, 0.0),
        heading = 180.0,
        snap = true,
    },

    battle_ropes = {
        order = 44,
        label = 'equip.battle_ropes',
        description = 'equip.battle_ropes_desc',
        models = {
            'prop_battle_ropes_01', 'prop_gym_ropes_01', 'prop_battleropes_01',
        },
        gains = { stamina = 0.6, strength = 0.45, breath = 0.2 },
        reps = 14,
        difficulty = 'hard',
        cooldown = 75,
        scenario = 'WORLD_HUMAN_MUSCLE_FREE_WEIGHTS',
        offset = vector3(0.0, 0.9, 0.0),
        heading = 180.0,
        snap = true,
    },

    -- --- Breathing and recovery ------------------------------------------------------

    yoga = {
        order = 50,
        label = 'equip.yoga',
        description = 'equip.yoga_desc',
        models = {
            'prop_yoga_mat_01', 'prop_yoga_mat_02', 'prop_yoga_mat_03',
            'prop_gym_mat_01', 'prop_gym_mat_02', 'prop_gym_mat_03',
            'prop_exercise_mat_01',
        },
        -- The best breath training in the catalogue, and almost the only thing that trains it
        -- indoors. Slow, easy, and long.
        gains = { breath = 1.0, stamina = 0.15 },
        reps = 8,
        difficulty = 'easy',
        cooldown = 120,
        minigame = {
            -- Yoga is held poses, not reps. A long window and a wide perfect band make it
            -- feel like breathing rather than button mashing.
            window = 2600,
            perfectZone = { 0.55, 0.90 },
            goodZone    = { 0.30, 0.99 },
            restBetween = 1600,
            keys = { 1, 1 },
        },
        scenario = 'WORLD_HUMAN_YOGA',
        anim = { dict = 'amb@world_human_yoga@male@base', clip = 'base', flag = 1 },
        offset = vector3(0.0, 0.0, 0.0),
        heading = 0.0,
        snap = true,
    },

    stretching = {
        order = 51,
        label = 'equip.stretching',
        description = 'equip.stretching_desc',
        models = {
            'prop_yoga_mat_01', 'prop_yoga_mat_02', 'prop_yoga_mat_03',
            'prop_gym_mat_01', 'prop_gym_mat_02', 'prop_gym_mat_03',
            'prop_foam_roller_01', 'prop_stretch_mat_01',
        },
        gains = { breath = 0.35, stamina = 0.2 },
        reps = 6,
        difficulty = 'easy',
        cooldown = 90,
        scenario = 'WORLD_HUMAN_YOGA',
        offset = vector3(0.0, 0.0, 0.0),
        heading = 0.0,
        snap = true,
    },

    -- --- Machines --------------------------------------------------------------------

    leg_press = {
        order = 60,
        label = 'equip.leg_press',
        description = 'equip.leg_press_desc',
        models = {
            'prop_leg_press_01', 'prop_gym_legpress_01', 'prop_leg_machine_01',
        },
        gains = { strength = 0.8, stamina = 0.3 },
        reps = 8,
        difficulty = 'normal',
        cooldown = 90,
        scenario = 'WORLD_HUMAN_SIT_UPS',
        offset = vector3(0.0, -0.6, 0.0),
        heading = 0.0,
        snap = true,
    },

    cable_machine = {
        order = 61,
        label = 'equip.cable_machine',
        description = 'equip.cable_machine_desc',
        models = {
            'prop_cable_machine_01', 'prop_gym_cable_01', 'prop_lat_pulldown_01',
            'prop_gym_machine_01', 'prop_gym_machine_02',
        },
        gains = { strength = 0.7, stamina = 0.2 },
        reps = 10,
        difficulty = 'normal',
        cooldown = 75,
        scenario = 'WORLD_HUMAN_MUSCLE_FREE_WEIGHTS',
        offset = vector3(0.0, 0.7, 0.0),
        heading = 180.0,
        snap = true,
    },
}

-- ===========================================================================================
-- Indexing
-- ===========================================================================================
--
-- Built once at load. Every scan is a hash lookup after this, not a walk of the catalogue.

Equipment.byModel = {}          -- model hash -> { equipment key, ... }, in catalogue order
Equipment.keys = {}             -- every enabled key, sorted by `order`

--- Merge the operator's additions from Config.ExtraEquipment, then build the indexes. Called
--- once at the bottom of this file, and again by /sportreload on a debug server.
function Equipment.build()
    Equipment.byModel = {}
    Equipment.keys = {}

    -- Operator additions. Declared in config.lua so that adding a piece of equipment never
    -- means editing a file under shared/, which is the one an update overwrites.
    if type(Config.ExtraEquipment) == 'table' then
        for key, entry in pairs(Config.ExtraEquipment) do
            if type(entry) == 'table' then
                if type(Equipment.catalogue[key]) == 'table' then
                    -- An entry with the same key PATCHES the shipped one, so an operator can
                    -- add three models to the bench press without restating all of it.
                    Sport.merge(Equipment.catalogue[key], entry)
                else
                    Equipment.catalogue[key] = Sport.copy(entry)
                end
            end
        end
    end

    for key, entry in pairs(Equipment.catalogue) do
        if entry.enabled ~= false then
            entry.key = key
            Equipment.keys[#Equipment.keys + 1] = key

            for _, model in ipairs(entry.models or {}) do
                -- A number is already a hash; a string has to be joaat'd. GetHashKey is
                -- available on both sides and is the same function as joaat().
                local hash = type(model) == 'number' and model or GetHashKey(model)
                if hash and hash ~= 0 then
                    local holders = Equipment.byModel[hash]
                    if not holders then
                        holders = {}
                        Equipment.byModel[hash] = holders
                    end
                    holders[#holders + 1] = key
                end
            end
        end
    end

    -- Sort the key list, and every model's holder list, by `order`. A yoga mat offers push
    -- ups, sit ups, yoga and stretching; without this the option order would change between
    -- restarts, because `pairs` makes no promises.
    local function byOrder(a, b)
        local left = tonumber(Equipment.catalogue[a].order) or 999
        local right = tonumber(Equipment.catalogue[b].order) or 999
        if left ~= right then return left < right end
        return a < b
    end

    table.sort(Equipment.keys, byOrder)
    for _, holders in pairs(Equipment.byModel) do
        table.sort(holders, byOrder)
    end
end

--- The catalogue entry for `key`, or nil. Every caller treats nil as "refuse the session":
--- an equipment key arriving from the client is untrusted input like any other.
function Equipment.get(key)
    if type(key) ~= 'string' then return nil end
    local entry = Equipment.catalogue[key]
    if type(entry) ~= 'table' or entry.enabled == false then return nil end
    return entry
end

--- Every exercise a given model offers, in display order. Empty when the model is not sport
--- equipment, which is the answer for almost every object in the pool.
function Equipment.forModel(hash)
    return Equipment.byModel[hash] or {}
end

--- The difficulty preset for `entry`, with its own `minigame` overrides merged in. Returns a
--- fresh table every call, so a caller may safely scale a field for one session.
function Equipment.difficulty(entry)
    local presets = Config.Minigame.difficulties
    local preset = presets[entry and entry.difficulty or ''] or presets.normal or {}
    local out = Sport.copy(preset)

    if type(entry) == 'table' and type(entry.minigame) == 'table' then
        Sport.merge(out, entry.minigame)
    end

    -- Defend the fields the minigame divides by or indexes with, so a hand-edited preset
    -- cannot produce a divide by zero or an endless rep.
    out.window = Sport.clamp(out.window, 200, 10000, 1250)
    out.restBetween = Sport.clamp(out.restBetween, 0, 10000, 750)
    out.keys = type(out.keys) == 'table' and out.keys or { 2, 3 }
    out.keys[1] = math.floor(Sport.clamp(out.keys[1], 1, 8, 2))
    out.keys[2] = math.floor(Sport.clamp(out.keys[2], out.keys[1], 8, out.keys[1]))
    out.perfectZone = type(out.perfectZone) == 'table' and out.perfectZone or { 0.60, 0.80 }
    out.goodZone = type(out.goodZone) == 'table' and out.goodZone or { 0.42, 0.95 }

    return out
end

--- The number of reps for `entry`, clamped. A catalogue entry with reps = 0 would finish
--- instantly and pay out in full, so the floor is 1.
function Equipment.reps(entry)
    return math.floor(Sport.clamp(entry and entry.reps, 1, 60, 8))
end

--[[
    The shortest time in milliseconds a session of `entry` can physically take.

    Shared because BOTH sides need it and they must agree: the client uses it for nothing at
    all, and the server multiplies it by Config.Security.minDurationFactor to reject a result
    that arrived faster than the reps could have been performed. Computing it twice, once per
    side, is how the two drift apart and start rejecting honest players.

    The fastest possible run presses every key the instant its good band opens, takes the
    minimum number of keys per rep, and never pauses.
]]
function Equipment.minimumDurationMs(entry)
    local difficulty = Equipment.difficulty(entry)
    local reps = Equipment.reps(entry)

    -- 110ms is the settle beat client/minigame.lua holds after each resolved key.
    local perKey = difficulty.window * (difficulty.goodZone[1] or 0.42) + 110
    return reps * difficulty.keys[1] * perKey + (reps - 1) * difficulty.restBetween
end

--- Seconds before the same player may use this equipment again.
function Equipment.cooldown(entry)
    local own = entry and tonumber(entry.cooldown)
    if own then return math.max(0, own) end
    return math.max(0, tonumber(Config.Security.defaultCooldown) or 0)
end

Equipment.build()
