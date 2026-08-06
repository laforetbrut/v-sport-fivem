--[[
    shared/stats.lua

    The progression, decay and effect maths.

    Shared, and that is the point: the server computes a gain and the client shows the player
    what a session is about to be worth, and the two have to agree to the decimal. One
    implementation, no drift.

    Nothing in this file touches state. Every function takes what it needs and returns a
    number or a table; the server owns the storage and the client owns the display.
]]

Stats = {}

-- ===========================================================================================
-- Definitions
-- ===========================================================================================

--- Every stat key, in panel order. Built from Config.Stats, so adding a fourth stat is a
--- config change and this list picks it up.
function Stats.keys()
    return Sport.sortedKeys(Config.Stats)
end

--- The definition for `key`, or nil. Anything arriving from a client goes through here
--- before it is used as a table index.
function Stats.def(key)
    if type(key) ~= 'string' then return nil end
    local def = Config.Stats[key]
    return type(def) == 'table' and def or nil
end

--- A fresh stats table for a character who has never trained.
function Stats.blank()
    local out = {}
    for key, def in pairs(Config.Stats) do
        out[key] = Sport.clamp(def.start, 0.0, def.max or 100.0, 0.0)
    end
    return out
end

--- Coerce a stored or received stats table into a valid one: every configured key present,
--- every value a number in range, and nothing else. A row written by an older version that
--- had a stat this one does not is silently dropped rather than carried forward.
function Stats.sanitise(raw)
    local out = Stats.blank()
    if type(raw) ~= 'table' then return out end

    for key, def in pairs(Config.Stats) do
        local value = Sport.clamp(raw[key], 0.0, def.max or 100.0, nil)
        if value ~= nil then
            out[key] = Sport.round(value, Config.Progression.decimals or 2)
        end
    end

    return out
end

-- ===========================================================================================
-- Progression
-- ===========================================================================================

--- Points that one full session of `key` is worth, before any modifier.
--- `max / sessionsToMax` - with the defaults, exactly 1.0.
function Stats.pointsPerSession(key)
    local def = Stats.def(key)
    if not def then return 0.0 end

    local sessions = math.max(1, math.floor(tonumber(def.sessionsToMax) or 100))
    return (def.max or 100.0) / sessions
end

--[[
    The fatigue multiplier for a player who has finished `recent` sessions inside the fatigue
    window and rested `restedHours` since the last one.

    Two forces: each recent session costs `perSession`, and each hour of rest gives back
    `recoverPerHour`. The result never falls below `floor` and never rises above 1.0.
]]
function Stats.fatigue(recent, restedHours)
    local cfg = Config.Progression.fatigue
    if not cfg or not cfg.enabled then return 1.0 end

    local lost = (tonumber(recent) or 0) * (tonumber(cfg.perSession) or 0)
    local regained = (tonumber(restedHours) or 0) * (tonumber(cfg.recoverPerHour) or 0)

    return Sport.clamp(1.0 - lost + regained, tonumber(cfg.floor) or 0.25, 1.0, 1.0)
end

--- The diminishing-returns multiplier at `value`. 1.0 below `from`, and falling towards 0 as
--- the stat approaches its ceiling. Disabled by default; see Config.Progression.diminishing.
function Stats.diminishing(key, value)
    local cfg = Config.Progression.diminishing
    if not cfg or not cfg.enabled then return 1.0 end

    local def = Stats.def(key)
    if not def then return 1.0 end

    local max = def.max or 100.0
    local from = Sport.clamp(cfg.from, 0.0, max, 70.0)
    local current = Sport.clamp(value, 0.0, max, 0.0)
    if current <= from then return 1.0 end

    -- How far into the diminishing band we are, 0 at `from` and 1 at `max`.
    local span = max - from
    if span <= 0 then return 1.0 end

    local into = (current - from) / span
    return Sport.clamp((1.0 - into) ^ (tonumber(cfg.curve) or 0.5), 0.0, 1.0, 1.0)
end

--[[
    What a finished session pays, per stat.

    `context` carries everything the maths needs that is not the equipment itself:

        current      = { stat = value }  the player's trained values right now
        quality      = 0.0 .. 1.0        what they scored in the minigame
        recent       = n                 sessions inside the fatigue window
        restedHours  = n                 hours since the last one
        multipliers  = { stat = m }      from another resource, section 14 of the config
        allowance    = { total = n,      how much of the training allowance is already spent
                         stats = {...} } in this window - see Stats.allowanceLeft

    Returns a table of stat -> points, containing only the stats that actually moved.

    The stats are walked in a DEFINED order rather than with `pairs`. That only matters when
    the global daily cap is in play - whichever stat is served first eats the remaining
    allowance - and a payout that depends on hash iteration order is a payout that differs
    between two identical sessions. Panel order is the order.
]]
function Stats.sessionGains(entry, context)
    local out = {}
    if type(entry) ~= 'table' or type(entry.gains) ~= 'table' then return out end

    context = context or {}
    local quality = Sport.clamp(context.quality, 0.0, 1.0, 0.0)
    local progression = Config.Progression

    -- Below the floor the session was not a workout. Nothing at all, for every stat.
    if quality < (tonumber(progression.minQuality) or 0) then return out end

    -- A flawless run is worth a little more than a merely complete one.
    if quality >= 0.999 then
        quality = quality * (tonumber(progression.perfectBonus) or 1.0)
    end

    local fatigue = Stats.fatigue(context.recent, context.restedHours)
    local current = context.current or {}
    local multipliers = context.multipliers or {}
    local decimals = progression.decimals or 2

    -- What the training allowance still permits. Decremented as stats are served, so one
    -- session can never hand out more than the whole remaining allowance however many stats
    -- the equipment trains.
    local globalLeft, perStatLeft = Stats.allowanceLeft(context.allowance)

    for _, key in ipairs(Stats.keys()) do
        local def = Stats.def(key)
        local sessions = tonumber(entry.gains[key])

        if def and sessions and sessions > 0 then
            local value = Sport.clamp(current[key], 0.0, def.max or 100.0, 0.0)

            local points = Stats.pointsPerSession(key)
                * sessions
                * quality
                * fatigue
                * Stats.diminishing(key, value)
                * Sport.clamp(multipliers[key], 0.0, 100.0, 1.0)
                * (tonumber(Config.Debug.gainMultiplier) or 1.0)

            --[[
                Two kinds of ceiling, and the lower of the two wins.

                `entry.trains` is the EQUIPMENT's own limit - a home dumbbell that stops being
                useful past 60 strength, pushing players towards a real gym.

                `context.ceilings` is a limit another resource imposed on this PLAYER, through
                SetStatCeiling: a heavy smoker whose stamina cannot pass 60 however hard they
                train. See Config.Buffs.minStatCeiling and API.md.
            ]]
            local ceiling = type(entry.trains) == 'table' and tonumber(entry.trains[key]) or nil
            local imposed = type(context.ceilings) == 'table' and tonumber(context.ceilings[key]) or nil

            if imposed and (not ceiling or imposed < ceiling) then ceiling = imposed end

            if ceiling and value >= ceiling then
                points = 0.0
            elseif ceiling and value + points > ceiling then
                points = ceiling - value
            end

            -- Caps. Both ship disabled; see Config.Progression.
            local sessionCap = tonumber(progression.sessionCap) or 0
            if sessionCap > 0 and points > sessionCap then points = sessionCap end

            -- The allowance, per stat and then across all of them.
            local statLeft = perStatLeft[key]
            if statLeft and points > statLeft then points = statLeft end
            if points > globalLeft then points = globalLeft end

            -- And the stat's own ceiling.
            local room = (def.max or 100.0) - value
            if points > room then points = room end

            points = Sport.round(points, decimals)
            if points > 0 then
                out[key] = points
                globalLeft = globalLeft - points
                if perStatLeft[key] then
                    perStatLeft[key] = perStatLeft[key] - points
                end
            end
        end
    end

    return out
end

-- ===========================================================================================
-- The training allowance
-- ===========================================================================================
--
-- A character may gain a fixed number of points before their body needs a rest. The ledger
-- of what has been spent lives on the server (server/stats.lua); everything here is the
-- arithmetic over it, shared so the panel's countdown and the server's refusal agree.

--[[
    How much allowance is left, globally and per stat.

    `spent` is { total = n, stats = { key = n } } - what has already been used in the current
    window. Returns the global remainder and a table of per-stat remainders. Both are
    `math.huge` when that part of the allowance is disabled, so a caller can compare against
    them without checking whether the feature is on.
]]
function Stats.allowanceLeft(spent)
    local cfg = Config.Allowance
    local perStat = {}

    if not cfg or not cfg.enabled then
        for key in pairs(Config.Stats) do perStat[key] = math.huge end
        return math.huge, perStat
    end

    spent = type(spent) == 'table' and spent or {}
    local spentStats = type(spent.stats) == 'table' and spent.stats or {}

    local totalCap = tonumber(cfg.total) or 0
    local statCap = tonumber(cfg.perStat) or 0

    local globalLeft = math.huge
    if totalCap > 0 then
        globalLeft = math.max(0.0, totalCap - (tonumber(spent.total) or 0))
    end

    for key in pairs(Config.Stats) do
        if statCap > 0 then
            perStat[key] = math.max(0.0, statCap - (tonumber(spentStats[key]) or 0))
        else
            perStat[key] = math.huge
        end
    end

    return globalLeft, perStat
end

--- Whether the allowance is completely spent, so a session would pay nothing at all. Used to
--- warn the player BEFORE they do fifteen reps for no reward.
function Stats.allowanceExhausted(spent)
    local cfg = Config.Allowance
    if not cfg or not cfg.enabled then return false end

    local globalLeft, perStat = Stats.allowanceLeft(spent)
    if globalLeft <= 0.001 then return true end

    -- Every individual stat maxed out is the same thing as no allowance left.
    for key in pairs(Config.Stats) do
        if (perStat[key] or math.huge) > 0.001 then return false end
    end

    return true
end

--- The recovery window for a player, in seconds. `reduced` is true while whey is in effect.
function Stats.allowanceWindow(reduced)
    local cfg = Config.Allowance
    if reduced then
        return math.max(60, tonumber(cfg.reducedWindow) or 8 * 3600)
    end
    return math.max(60, tonumber(cfg.window) or 25 * 3600)
end

--[[
    Why a session paid what it paid, as a list of { reason, value } entries.

    Purely for display: the panel and the console log show it so a player who gained less than
    they expected can see whether it was fatigue, the allowance or simply a bad run, rather
    than concluding the resource is broken. Nothing reads the result to make a decision.
]]
function Stats.explain(context)
    context = context or {}
    local out = {}

    out[#out + 1] = { reason = 'quality', value = Sport.clamp(context.quality, 0.0, 1.0, 0.0) }

    local fatigue = Stats.fatigue(context.recent, context.restedHours)
    if fatigue < 0.999 then
        out[#out + 1] = { reason = 'fatigue', value = fatigue }
    end

    if Config.Allowance.enabled then
        local globalLeft, perStat = Stats.allowanceLeft(context.allowance)

        if globalLeft <= 0.001 then
            out[#out + 1] = { reason = 'allowance_spent', value = 0.0 }
        else
            for _, key in ipairs(Stats.keys()) do
                if (perStat[key] or math.huge) <= 0.001 then
                    out[#out + 1] = { reason = 'allowance_stat', value = 0.0, stat = key }
                end
            end
        end
    end

    return out
end

-- ===========================================================================================
-- Decay
-- ===========================================================================================

--- The decay settings for `key`: the stat's own block when it has one, the global one
--- otherwise. Per-stat overrides are how lung capacity decays at half the rate of strength.
function Stats.decayConfig(key)
    local global = Config.Decay
    local def = Stats.def(key)
    local own = def and type(def.decay) == 'table' and def.decay or nil

    return {
        amount   = tonumber(own and own.amount   or global.amount)   or 0.0,
        interval = tonumber(own and own.interval or global.interval) or 86400,
        grace    = tonumber(own and own.grace    or global.grace)    or 86400,
        floor    = tonumber(own and own.floor    or global.floor)    or 0.0,
    }
end

--[[
    How much decay is owed, and up to when.

    `lastSession` is when the player last trained; `anchor` is the boundary decay was last
    applied up to. Taking the later of the two is what makes this idempotent: calling it twice
    in a row cannot charge the same period twice, which matters because it runs both on load
    and on a timer.

    Returns `periods` (whole intervals owed) and `newAnchor` (the timestamp to store). A
    caller that applies the loss MUST store `newAnchor`.
]]
function Stats.decayPeriods(key, now, lastSession, anchor)
    if not Config.Decay.enabled then return 0, anchor or 0 end

    local cfg = Stats.decayConfig(key)
    if cfg.amount <= 0 or cfg.interval <= 0 then return 0, anchor or 0 end

    local last = tonumber(lastSession) or 0
    local base = math.max(last + cfg.grace, tonumber(anchor) or 0)

    -- `now` is 0 while the client is still waiting on the cloud time service. Charging decay
    -- from a zero clock would wipe every stat, so an unknown clock owes nothing.
    local current = tonumber(now) or 0
    if current <= 0 or current <= base then return 0, math.max(base, tonumber(anchor) or 0) end

    local periods = math.floor((current - base) / cfg.interval)
    if periods <= 0 then return 0, math.max(base, tonumber(anchor) or 0) end

    return periods, base + periods * cfg.interval
end

--[[
    The value `key` decays to after `periods` intervals, honouring both floors.

    `peak` is the highest value the character ever reached; pass 0 to ignore peak protection.

    `multiplier` scales how much each period costs, and is how another resource makes a
    character lose condition faster than normal - a heavy smoker at 2.0 loses 20 a day rather
    than 10. See SetDecayMultiplier in API.md. nil is 1.0.
]]
function Stats.applyDecay(key, value, periods, peak, multiplier)
    local def = Stats.def(key)
    if not def or periods <= 0 then return value end

    local cfg = Stats.decayConfig(key)
    local floor = cfg.floor
    local scale = Sport.clamp(multiplier, 0.0, tonumber(Config.Buffs.maxDecayMultiplier) or 5.0, 1.0)

    -- Peak protection is the gentler floor: it is relative to what the character achieved
    -- rather than absolute, so a long absence costs a known amount instead of everything.
    local protection = tonumber(Config.Decay.peakProtection) or 0
    if protection > 0 then
        local protected = (tonumber(peak) or 0) - protection
        if protected > floor then floor = protected end
    end

    local out = (tonumber(value) or 0) - cfg.amount * periods * scale
    if out < floor then out = floor end

    return Sport.round(math.max(0.0, out), Config.Progression.decimals or 2)
end

--- Seconds until the next decay lands for `key`, or nil when nothing is owed and nothing
--- will be. Drives the "next decay in 4h 12m" line in the stats panel.
function Stats.nextDecayIn(key, now, lastSession, anchor)
    if not Config.Decay.enabled then return nil end

    local cfg = Stats.decayConfig(key)
    if cfg.amount <= 0 or cfg.interval <= 0 then return nil end

    local current = tonumber(now) or 0
    if current <= 0 then return nil end

    local base = math.max((tonumber(lastSession) or 0) + cfg.grace, tonumber(anchor) or 0)
    if current < base then return base - current end

    local into = (current - base) % cfg.interval
    return cfg.interval - into
end

-- ===========================================================================================
-- Effects
-- ===========================================================================================

--[[
    The value of one configured bonus at a given stat level.

    `bonus` is a { enabled, min, max } block from Config.Effects. The result is interpolated
    between min and max by the stat's fraction of its ceiling, and then pulled back towards
    `min` by Config.Effects.globalScale.

    globalScale is applied here rather than at the call sites so that there is exactly one
    place where "half of every bonus" is decided, and so that scaling can never push a
    multiplier below the game's vanilla value.
]]
function Stats.bonus(key, bonus, value)
    if type(bonus) ~= 'table' or bonus.enabled == false then return nil end
    if not Config.Effects.enabled then return nil end

    local def = Stats.def(key)
    if not def then return nil end

    local min = tonumber(bonus.min)
    local max = tonumber(bonus.max)
    if not min or not max then return nil end

    local fraction = Sport.clamp(value, 0.0, def.max or 100.0, 0.0) / (def.max or 100.0)
    local scale = Sport.clamp(Config.Effects.globalScale, 0.0, 10.0, 1.0)

    return min + (max - min) * fraction * scale
end

--- The GTA character stat value for `key`: the trained value mapped onto the 0-100 the game
--- itself uses. Returns nil when the stat has no `gameStat`, or when writing them is off.
function Stats.gameStatValue(key, value)
    if not Config.Effects.enabled or not Config.Effects.writeGameStats then return nil end

    local def = Stats.def(key)
    if not def or not def.gameStat or def.gameStat == '' then return nil end

    local max = def.max or 100.0
    return math.floor(Sport.clamp(value, 0.0, max, 0.0) / max * 100.0 + 0.5)
end

-- ===========================================================================================
-- Effective values
-- ===========================================================================================

--[[
    The trained values with every active buff folded in.

    `buffs` is a list of { stat, amount, expires }. Expired entries are ignored rather than
    removed - pruning belongs to whoever owns the list, and this function is called from the
    client too, where the list is a read-only copy.

    The trained value is never touched. Only this result drives the natives in
    client/effects.lua, which is what makes a buff temporary in the honest sense: the moment
    it expires the next call returns the trained number again.
]]
function Stats.effective(trained, buffs, now)
    local out = Stats.sanitise(trained)
    if not Config.Buffs.enabled or type(buffs) ~= 'table' then return out end

    local current = tonumber(now) or Sport.now()
    local overcap = tonumber(Config.Buffs.overcap) or 0
    local undercap = tonumber(Config.Buffs.undercap) or 0

    for _, buff in ipairs(buffs) do
        local key = type(buff) == 'table' and buff.stat or nil
        local def = Stats.def(key)

        if def and out[key] ~= nil then
            local expires = tonumber(buff.expires) or 0
            -- expires == 0 means indefinite: a buff that lasts until something removes it.
            if expires == 0 or expires > current then
                out[key] = out[key] + (tonumber(buff.amount) or 0)
            end
        end
    end

    for key, def in pairs(Config.Stats) do
        out[key] = Sport.round(
            Sport.clamp(out[key], 0.0 - undercap, (def.max or 100.0) + overcap, 0.0),
            Config.Progression.decimals or 2
        )
        if out[key] < 0.0 then out[key] = 0.0 end
    end

    return out
end

--- The combined training multiplier for `key` from every active multiplier buff. 1.0 when
--- nothing is active. Multipliers compose by product, so two 1.5x supplements give 2.25x.
function Stats.multiplier(key, multipliers, now)
    if not Config.Buffs.enabled or type(multipliers) ~= 'table' then return 1.0 end

    local current = tonumber(now) or Sport.now()
    local out = 1.0

    for _, entry in ipairs(multipliers) do
        if type(entry) == 'table' and entry.stat == key then
            local expires = tonumber(entry.expires) or 0
            if expires == 0 or expires > current then
                out = out * (tonumber(entry.value) or 1.0)
            end
        end
    end

    return Sport.clamp(out, 0.0, 100.0, 1.0)
end
