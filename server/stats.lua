--[[
    server/stats.lua

    The authority. Every number a player has, and every rule about how it changes.

    ---------------------------------------------------------------------------------------
    WHAT LIVES HERE
    ---------------------------------------------------------------------------------------

      Profiles       one per connected player, keyed on the server id
      The allowance  the ledger of how much a character has gained this cycle
      Decay          computed from a timestamp, so it runs while a player is offline
      Buffs          temporary points and temporary multipliers from other resources
      Persistence    a dirty set flushed on a timer, in batches, never per change

    ---------------------------------------------------------------------------------------
    WHAT IT COSTS
    ---------------------------------------------------------------------------------------

    There is NO PER-PLAYER LOOP. Three timers exist for the whole server however many people
    are on it: one flushes dirty rows, one sweeps expired buffs, one re-checks decay. A player
    who is not doing anything costs nothing at all.
]]

Profiles = {}

local profiles = {}             -- src -> profile
local dirty = {}                -- src -> true
local loading = {}              -- src -> true, so two load events do not both fetch

-- ---------------------------------------------------------------------------------------
-- Profile shape
-- ---------------------------------------------------------------------------------------

local function blankProfile(identifier)
    return {
        identifier = identifier,

        -- Persisted
        stats = Stats.blank(),
        peak = {},
        decayAnchor = {},
        allowance = { entries = {}, cycleStart = 0 },
        lastSession = 0,
        totalSessions = 0,
        recoveryUntil = 0,          -- whey: the shortened window applies until this time

        -- Runtime only. A buff does not survive a restart, and that is the right answer:
        -- a supplement that outlives the server it was taken on is a bug, not a feature.
        buffs = {},
        multipliers = {},
        decayPaused = false,
        decayImmuneUntil = 0,
        blocked = false,
        blockReason = nil,
        recentSessions = {},        -- timestamps, for fatigue
        sessionTimes = {},          -- timestamps, for the per-hour rate limit
        itemCooldowns = {},
        rejections = {},            -- timestamps, for the suspicion threshold
        announcedBlocked = false,
    }
end

--- The profile for `src`, or nil when the player has not finished loading.
function Profiles.get(src)
    return profiles[tonumber(src)]
end

--- Mark a profile for the next flush. Cheap on purpose: called from everywhere.
function Profiles.touch(src)
    if profiles[src] then dirty[src] = true end
end

-- ---------------------------------------------------------------------------------------
-- The allowance ledger
-- ---------------------------------------------------------------------------------------
--
-- Every point a character gains is written into the ledger with a timestamp. How much they
-- may still gain is the configured allowance minus what the ledger holds for the current
-- window. Two modes, both driven from the same entries:
--
--   'rolling'  an entry ages out exactly `window` seconds after it was written, so the
--              allowance trickles back and a player is never fully locked out for a whole day
--   'block'    every entry is cleared at once, `window` seconds after the first of the cycle

--- The recovery window this character is on, in seconds. Shorter while whey is in effect.
local function windowFor(profile)
    local reduced = (tonumber(profile.recoveryUntil) or 0) > Sport.now()
    return Stats.allowanceWindow(reduced)
end

--- Drop entries that have aged out. Returns whether anything was dropped, so the caller can
--- decide whether the player is worth telling.
local function pruneAllowance(profile)
    local cfg = Config.Allowance
    if not cfg.enabled then return false end

    local ledger = profile.allowance
    if type(ledger) ~= 'table' then
        profile.allowance = { entries = {}, cycleStart = 0 }
        return false
    end

    ledger.entries = type(ledger.entries) == 'table' and ledger.entries or {}

    local now = Sport.now()
    if now <= 0 then return false end

    local window = windowFor(profile)
    local changed = false

    if cfg.mode == 'block' then
        local start = tonumber(ledger.cycleStart) or 0
        if start > 0 and (now - start) >= window then
            ledger.entries = {}
            ledger.cycleStart = 0
            changed = true
        end
        return changed
    end

    -- Rolling. Walk backwards so removing an entry does not skip the next one.
    for index = #ledger.entries, 1, -1 do
        local entry = ledger.entries[index]
        if type(entry) ~= 'table' or (now - (tonumber(entry.at) or 0)) >= window then
            table.remove(ledger.entries, index)
            changed = true
        end
    end

    return changed
end

--- What the ledger currently holds: { total = n, stats = { key = n } }.
function Profiles.allowanceSpent(profile)
    pruneAllowance(profile)

    local out = { total = 0.0, stats = {} }
    for key in pairs(Config.Stats) do out.stats[key] = 0.0 end

    for _, entry in ipairs(profile.allowance.entries or {}) do
        local amount = tonumber(entry.amount) or 0
        out.total = out.total + amount
        if out.stats[entry.stat] ~= nil then
            out.stats[entry.stat] = out.stats[entry.stat] + amount
        end
    end

    return out
end

--- Write points into the ledger.
local function spendAllowance(profile, statKey, amount)
    if not Config.Allowance.enabled then return end
    if (tonumber(amount) or 0) <= 0 then return end

    local ledger = profile.allowance
    local now = Sport.now()

    if ledger.cycleStart == 0 or ledger.cycleStart == nil then
        ledger.cycleStart = now
    end

    ledger.entries[#ledger.entries + 1] = { at = now, stat = statKey, amount = amount }

    -- A ledger cannot grow without bound: entries age out. This is a backstop against a
    -- misconfigured window of zero, which would otherwise never prune.
    while #ledger.entries > 500 do
        table.remove(ledger.entries, 1)
    end
end

--- Seconds until the allowance frees up meaningfully, or nil when nothing is spent.
function Profiles.allowanceResetsIn(profile)
    if not Config.Allowance.enabled then return nil end

    pruneAllowance(profile)
    local entries = profile.allowance.entries or {}
    if #entries == 0 then return nil end

    local now = Sport.now()
    local window = windowFor(profile)

    if Config.Allowance.mode == 'block' then
        local start = tonumber(profile.allowance.cycleStart) or now
        return math.max(0, (start + window) - now)
    end

    -- Rolling: the next entry to age out is the oldest one.
    local oldest = math.huge
    for _, entry in ipairs(entries) do
        local at = tonumber(entry.at) or now
        if at < oldest then oldest = at end
    end

    if oldest == math.huge then return nil end
    return math.max(0, (oldest + window) - now)
end

--[[
    Give allowance back.

    `amount` of nil clears the ledger entirely - that is the "bypass the recovery time"
    export a drug script calls. A number refunds that many points, oldest entries first,
    which is the fair order: the points a player earned longest ago are the ones closest to
    expiring anyway.
]]
function Profiles.refundAllowance(src, amount)
    local profile = profiles[src]
    if not profile then return false end

    if amount == nil then
        profile.allowance = { entries = {}, cycleStart = 0 }
        profile.announcedBlocked = false
        Profiles.touch(src)
        Profiles.sync(src)
        return true
    end

    local remaining = math.max(0, tonumber(amount) or 0)
    local entries = profile.allowance.entries or {}

    table.sort(entries, function(a, b)
        return (tonumber(a.at) or 0) < (tonumber(b.at) or 0)
    end)

    for index = 1, #entries do
        if remaining <= 0 then break end
        local held = tonumber(entries[index].amount) or 0

        if held <= remaining then
            remaining = remaining - held
            entries[index].amount = 0
        else
            entries[index].amount = held - remaining
            remaining = 0
        end
    end

    for index = #entries, 1, -1 do
        if (tonumber(entries[index].amount) or 0) <= 0 then
            table.remove(entries, index)
        end
    end

    profile.announcedBlocked = false
    Profiles.touch(src)
    Profiles.sync(src)
    return true
end

--- Put the character on the shortened recovery window for `seconds`. This is whey.
function Profiles.reduceRecovery(src, seconds)
    local profile = profiles[src]
    if not profile then return false end

    local duration = math.max(0, tonumber(seconds) or Config.Allowance.window)
    profile.recoveryUntil = Sport.now() + duration

    -- Shortening the window may have aged entries out immediately, which is the whole point.
    if pruneAllowance(profile) then
        profile.announcedBlocked = false
    end

    Profiles.touch(src)
    Profiles.sync(src)
    return true
end

-- ---------------------------------------------------------------------------------------
-- Fatigue and rate limiting
-- ---------------------------------------------------------------------------------------

--- Sessions inside the fatigue window, and hours since the last one.
local function fatigueContext(profile)
    local cfg = Config.Progression.fatigue
    local now = Sport.now()
    local window = math.max(60, tonumber(cfg.window) or 5400)

    for index = #profile.recentSessions, 1, -1 do
        if (now - profile.recentSessions[index]) > window then
            table.remove(profile.recentSessions, index)
        end
    end

    local rested = 0.0
    if profile.lastSession > 0 and now > profile.lastSession then
        rested = (now - profile.lastSession) / 3600.0
    end

    return #profile.recentSessions, rested
end

--- Whether the player has finished too many sessions in the last hour.
local function rateLimited(profile)
    local limit = math.floor(tonumber(Config.Progression.sessionsPerHour) or 0)
    if limit <= 0 then return false end

    local now = Sport.now()
    for index = #profile.sessionTimes, 1, -1 do
        if (now - profile.sessionTimes[index]) > 3600 then
            table.remove(profile.sessionTimes, index)
        end
    end

    return #profile.sessionTimes >= limit
end

-- ---------------------------------------------------------------------------------------
-- Decay
-- ---------------------------------------------------------------------------------------

--[[
    Charge whatever decay is owed.

    Runs on load - which is how offline decay happens - and on a slow timer while the player
    is connected. Idempotent: `Stats.decayPeriods` takes the anchor into account, so calling
    this twice in a row charges the second call nothing.

    Returns a table of stat -> points lost, empty when nothing was owed.
]]
function Profiles.applyDecay(src, silent)
    local profile = profiles[src]
    if not profile or not Config.Decay.enabled then return {} end

    local now = Sport.now()
    if now <= 0 then return {} end

    -- Every reason a character might be spared.
    if profile.decayPaused then return {} end
    if (tonumber(profile.decayImmuneUntil) or 0) > now then return {} end
    if Bridge.decayExempt(src) then return {} end

    -- A character who has never trained has nothing to lose, and charging decay from a zero
    -- timestamp would take a brand new character straight to the floor.
    if (tonumber(profile.lastSession) or 0) <= 0 then return {} end

    local lost = {}

    for _, key in ipairs(Stats.keys()) do
        local periods, anchor = Stats.decayPeriods(key, now, profile.lastSession,
            profile.decayAnchor[key])

        profile.decayAnchor[key] = anchor

        if periods > 0 then
            local before = profile.stats[key] or 0
            local after = Stats.applyDecay(key, before, periods, profile.peak[key])

            if after < before then
                profile.stats[key] = after
                lost[key] = Sport.round(before - after, Config.Progression.decimals or 2)
            end
        end
    end

    if next(lost) then
        Profiles.touch(src)

        if not silent and Config.Decay.notifyOnLoad and Config.Notifications.decayApplied then
            local parts = {}
            for _, key in ipairs(Stats.keys()) do
                if lost[key] then
                    parts[#parts + 1] = L('notify.lost', lost[key], L(Stats.def(key).label))
                end
            end
            if #parts > 0 then
                Bridge.notify(src, L('notify.decay_applied', table.concat(parts, '   ')), 'error')
            end
        end
    end

    return lost
end

-- ---------------------------------------------------------------------------------------
-- Awarding
-- ---------------------------------------------------------------------------------------

--- Track the highest value ever reached, for peak protection in section 6.
local function updatePeak(profile, key)
    local value = profile.stats[key] or 0
    if value > (tonumber(profile.peak[key]) or 0) then
        profile.peak[key] = value
    end
end

--- Fire the milestone notification when a stat crosses a multiple of `milestoneEvery`.
local function checkMilestone(src, key, before, after)
    if not Config.Notifications.statMilestone then return end

    local step = tonumber(Config.Notifications.milestoneEvery) or 0
    if step <= 0 then return end

    local crossedBefore = math.floor(before / step)
    local crossedAfter = math.floor(after / step)
    if crossedAfter <= crossedBefore or crossedAfter == 0 then return end

    local def = Stats.def(key)
    local max = def.max or 100.0

    if after >= max then
        Bridge.notify(src, L('notify.maxed', L(def.label)), 'success')
    else
        Bridge.notify(src, L('notify.milestone', L(def.label), crossedAfter * step), 'success')
    end
end

--[[
    Pay out a finished session.

    `entry` is the catalogue entry, `quality` is what the client scored, already validated by
    server/session.lua. Returns the gains and a note explaining an empty payout.

    This is the ONLY path that turns training into points. The exports in server/api.lua bypass
    it deliberately - an admin command or a drug script is not a workout and is not subject to
    the allowance unless the caller asks for it.
]]
function Profiles.awardSession(src, entry, quality)
    local profile = profiles[src]
    if not profile then return {}, nil end

    if rateLimited(profile) then
        return {}, L('refuse.rate_limit')
    end

    local recent, restedHours = fatigueContext(profile)
    local spent = Profiles.allowanceSpent(profile)

    -- Say so when the player has ground themselves down to the fatigue floor. Without this
    -- the gains just quietly shrink and it reads as a bug rather than as the mechanic.
    local fatigueNow = Stats.fatigue(recent, restedHours)
    local floor = tonumber(Config.Progression.fatigue.floor) or 0.15
    if Config.Progression.fatigue.enabled and fatigueNow <= (floor + 0.001) then
        Bridge.notify(src, L('notify.too_tired'), 'error')
    end

    -- Tell the player their allowance is gone BEFORE blaming their form.
    if Stats.allowanceExhausted(spent) then
        local note = nil
        if Config.Allowance.notifyBlocked then
            local resets = Profiles.allowanceResetsIn(profile)
            note = L('allowance.blocked', resets and Sport.duration(resets) or '?')
        end
        return {}, note
    end

    local multipliers = {}
    for _, key in ipairs(Stats.keys()) do
        multipliers[key] = Stats.multiplier(key, profile.multipliers, Sport.now())
    end

    local gains = Stats.sessionGains(entry, {
        current = profile.stats,
        quality = quality,
        recent = recent,
        restedHours = restedHours,
        multipliers = multipliers,
        allowance = spent,
    })

    local now = Sport.now()

    -- The session counts towards fatigue and the rate limit whether or not it paid, because
    -- a session that paid nothing was still a session and still tired the character out.
    profile.recentSessions[#profile.recentSessions + 1] = now
    profile.sessionTimes[#profile.sessionTimes + 1] = now
    profile.lastSession = now
    profile.totalSessions = profile.totalSessions + 1

    for key, points in pairs(gains) do
        local before = profile.stats[key] or 0
        profile.stats[key] = Sport.round(before + points, Config.Progression.decimals or 2)

        spendAllowance(profile, key, points)
        updatePeak(profile, key)
        checkMilestone(src, key, before, profile.stats[key])

        -- Training resets this stat's decay clock. Without it, a player who trains daily
        -- would still be charged decay for the days before they started.
        profile.decayAnchor[key] = now + Stats.decayConfig(key).grace
    end

    profile.announcedBlocked = false
    Profiles.touch(src)
    Profiles.sync(src)

    if not next(gains) then
        return {}, L('session.nothing_gained')
    end

    TriggerEvent('vsport:server:SessionCompleted', src, entry.key, gains, quality)
    return gains, nil
end

--[[
    Change a stat outside of training.

    `mode` is 'add' | 'set' | 'remove'. `respectAllowance` makes the change go through the
    training allowance like a workout would; the default is false, because an admin fixing a
    number and a drug granting a bonus are both explicitly NOT workouts.
]]
function Profiles.changeStat(src, key, amount, mode, respectAllowance)
    local profile = profiles[src]
    local def = Stats.def(key)
    if not profile or not def then return nil end

    local value = tonumber(amount)
    if not value then return nil end

    -- Guard against another resource with a bug wiping somebody's progress.
    local guard = tonumber(Config.Buffs.maxSingleChange) or 100.0
    if math.abs(value) > guard then
        Sport.warn(('a change of %.1f to %s was clamped to %.1f (Config.Buffs.maxSingleChange)')
            :format(value, key, guard))
        value = value > 0 and guard or -guard
    end

    local before = profile.stats[key] or 0
    local after

    if mode == 'set' then
        after = value
    elseif mode == 'remove' then
        after = before - math.abs(value)
    else
        after = before + value
    end

    if respectAllowance and after > before then
        local globalLeft, perStat = Stats.allowanceLeft(Profiles.allowanceSpent(profile))
        local room = math.min(globalLeft, perStat[key] or math.huge)
        if (after - before) > room then after = before + room end
    end

    after = Sport.round(Sport.clamp(after, 0.0, def.max or 100.0, before),
        Config.Progression.decimals or 2)

    if after == before then return before end

    profile.stats[key] = after

    if respectAllowance and after > before then
        spendAllowance(profile, key, after - before)
    end

    updatePeak(profile, key)
    checkMilestone(src, key, before, after)

    Profiles.touch(src)
    Profiles.sync(src)

    TriggerEvent('vsport:server:StatChanged', src, key, before, after)
    return after
end

-- ---------------------------------------------------------------------------------------
-- Buffs
-- ---------------------------------------------------------------------------------------

local nextBuffId = 0

local function newId(prefix)
    nextBuffId = nextBuffId + 1
    return ('%s%d'):format(prefix, nextBuffId)
end

--- Add temporary points to a stat's effective value. Returns the id, for RemoveBuff.
function Profiles.addBuff(src, key, amount, seconds, id)
    local profile = profiles[src]
    if not profile or not Config.Buffs.enabled or not Stats.def(key) then return nil end

    local guard = tonumber(Config.Buffs.maxSingleChange) or 100.0
    local value = Sport.clamp(amount, -guard, guard, 0.0)
    if value == 0 then return nil end

    local maxDuration = tonumber(Config.Buffs.maxDurationSeconds) or 86400
    local duration = math.floor(Sport.clamp(seconds, 0, maxDuration, 0))

    local buff = {
        id = id or newId('b'),
        stat = key,
        amount = value,
        expires = duration > 0 and (Sport.now() + duration) or 0,
    }

    local stacking = Config.Buffs.stacking

    if stacking == 'replace' or stacking == 'highest' then
        for index = #profile.buffs, 1, -1 do
            local existing = profile.buffs[index]
            if existing.stat == key then
                if stacking == 'replace' then
                    table.remove(profile.buffs, index)
                elseif math.abs(existing.amount) >= math.abs(value) then
                    -- A stronger one is already running; the new one is discarded.
                    return existing.id
                else
                    table.remove(profile.buffs, index)
                end
            end
        end
    end

    profile.buffs[#profile.buffs + 1] = buff
    Profiles.syncBuffs(src)

    if Config.Buffs.notifyApply and Config.Notifications.buffApplied then
        Bridge.notify(src, L('notify.buff_applied', L(Stats.def(key).label), value,
            duration > 0 and Sport.duration(duration) or '-'), 'primary')
    end

    return buff.id
end

--- Multiply what training gains for a while. Composes by product with any other active one.
function Profiles.addMultiplier(src, key, value, seconds, id)
    local profile = profiles[src]
    if not profile or not Config.Buffs.enabled then return nil end

    -- nil `key` means every stat, which is what a pre-workout wants.
    if key ~= nil and not Stats.def(key) then return nil end

    local maxDuration = tonumber(Config.Buffs.maxDurationSeconds) or 86400
    local duration = math.floor(Sport.clamp(seconds, 0, maxDuration, 0))
    local factor = Sport.clamp(value, 0.0, 10.0, 1.0)

    local ids = {}
    local keys = key and { key } or Stats.keys()

    for _, statKey in ipairs(keys) do
        local entry = {
            id = id and (#keys > 1 and (id .. ':' .. statKey) or id) or newId('m'),
            stat = statKey,
            value = factor,
            expires = duration > 0 and (Sport.now() + duration) or 0,
        }
        profile.multipliers[#profile.multipliers + 1] = entry
        ids[#ids + 1] = entry.id
    end

    Profiles.syncBuffs(src)

    if Config.Buffs.notifyApply and Config.Notifications.buffApplied then
        local label = key and L(Stats.def(key).label) or ''
        Bridge.notify(src, L('notify.multiplier_applied', label, factor,
            duration > 0 and Sport.duration(duration) or '-'), 'primary')
    end

    return ids[1], ids
end

--- Remove one buff or multiplier by id. Returns whether anything was removed.
function Profiles.removeBuff(src, id)
    local profile = profiles[src]
    if not profile or type(id) ~= 'string' then return false end

    local removed = false

    for _, list in ipairs({ profile.buffs, profile.multipliers }) do
        for index = #list, 1, -1 do
            -- A multiplier applied to every stat produced one entry per stat, all sharing a
            -- prefix, so a prefix match removes the whole group with one call.
            if list[index].id == id or list[index].id:sub(1, #id + 1) == (id .. ':') then
                table.remove(list, index)
                removed = true
            end
        end
    end

    if removed then Profiles.syncBuffs(src) end
    return removed
end

--- Remove every buff, or every buff on one stat.
function Profiles.clearBuffs(src, key)
    local profile = profiles[src]
    if not profile then return false end

    if key == nil then
        profile.buffs = {}
        profile.multipliers = {}
    else
        for _, list in ipairs({ profile.buffs, profile.multipliers }) do
            for index = #list, 1, -1 do
                if list[index].stat == key then table.remove(list, index) end
            end
        end
    end

    Profiles.syncBuffs(src)
    return true
end

--- Drop expired entries and announce them. Returns whether anything changed.
local function sweepBuffs(src, profile)
    local now = Sport.now()
    if now <= 0 then return false end

    local changed = false

    for _, list in ipairs({ profile.buffs, profile.multipliers }) do
        for index = #list, 1, -1 do
            local entry = list[index]
            local expires = tonumber(entry.expires) or 0

            if expires > 0 and expires <= now then
                table.remove(list, index)
                changed = true

                if Config.Buffs.notifyExpire and Stats.def(entry.stat) then
                    Bridge.notify(src, L('notify.buff_expired',
                        L(Stats.def(entry.stat).label)), 'primary')
                end

                if Config.Buffs.fireExpiryEvents then
                    TriggerEvent('vsport:server:BuffExpired', src, entry.id, entry.stat)
                    TriggerClientEvent('vsport:client:BuffExpired', src, entry.id, entry.stat)
                end
            end
        end
    end

    return changed
end

-- ---------------------------------------------------------------------------------------
-- Synchronising
-- ---------------------------------------------------------------------------------------

local lastStateBag = {}

--[[
    Publish the stats on the player's state bag.

    Only when they changed, and at most once per `stateBagInterval`. A state bag write is
    cheap but not free, and a replicated one is a network message; a resource that wrote one
    every time a fraction of a point moved would be a bad neighbour.
]]
local function publishStateBag(src, profile)
    if not Config.Performance.stateBags then return end

    local now = GetGameTimer()
    local last = lastStateBag[src]
    local interval = math.max(250, tonumber(Config.Performance.stateBagInterval) or 2000)

    if last and (now - last.at) < interval then return end

    local encoded = Sport.encode(profile.stats)
    if last and last.encoded == encoded then return end

    lastStateBag[src] = { at = now, encoded = encoded }

    local player = Player(src)
    if player and player.state then
        player.state:set('sportStats', profile.stats,
            Config.Performance.stateBagReplicated == true)
    end
end

--- Everything the client needs, in one payload.
function Profiles.sync(src)
    local profile = profiles[src]
    if not profile then return end

    local spent = Profiles.allowanceSpent(profile)
    local recent = select(1, fatigueContext(profile))

    TriggerClientEvent('vsport:client:Sync', src, {
        stats = profile.stats,
        buffs = profile.buffs,
        multipliers = profile.multipliers,
        decayPaused = profile.decayPaused or (tonumber(profile.decayImmuneUntil) or 0) > Sport.now(),
        blocked = profile.blocked,
        blockReason = profile.blockReason,
        totalSessions = profile.totalSessions,
        lastSession = profile.lastSession,
        decayAnchor = profile.decayAnchor,
        recentSessions = recent,
        peak = profile.peak,
        allowanceSpent = spent,
        allowanceResetsIn = Profiles.allowanceResetsIn(profile),
        allowanceWindow = windowFor(profile),
    })

    publishStateBag(src, profile)
end

--- Just the buff lists, for when nothing else moved.
function Profiles.syncBuffs(src)
    local profile = profiles[src]
    if not profile then return end

    TriggerClientEvent('vsport:client:Buffs', src, profile.buffs, profile.multipliers,
        profile.decayPaused or (tonumber(profile.decayImmuneUntil) or 0) > Sport.now())
end

-- ---------------------------------------------------------------------------------------
-- Load and save
-- ---------------------------------------------------------------------------------------

local function load(src)
    if profiles[src] or loading[src] then return end
    loading[src] = true

    CreateThread(function()
        Database.waitReady()

        -- The identifier is not readable until the framework has finished loading the
        -- character. Ask for a while rather than giving up on the first miss.
        local identifier
        for _ = 1, 40 do
            identifier = Bridge.identifier(src)
            if identifier then break end
            Wait(500)
        end

        loading[src] = nil

        if not GetPlayerName(src) then return end          -- dropped while we waited

        if not identifier then
            Sport.warn(('could not resolve an identifier for %s; not loading their stats')
                :format(GetPlayerName(src) or src))
            return
        end

        if profiles[src] then return end                   -- a second load event won the race

        local profile = blankProfile(identifier)
        local row = Database.load(identifier)

        if row then
            profile.stats = Stats.sanitise(row.stats)
            profile.peak = type(row.peak) == 'table' and row.peak or {}
            profile.decayAnchor = type(row.decayAnchor) == 'table' and row.decayAnchor or {}
            profile.allowance = type(row.allowance) == 'table' and row.allowance or
                { entries = {}, cycleStart = 0 }
            profile.allowance.entries = type(profile.allowance.entries) == 'table'
                and profile.allowance.entries or {}
            profile.lastSession = tonumber(row.lastSession) or 0
            profile.totalSessions = tonumber(row.totalSessions) or 0
            profile.recoveryUntil = tonumber(row.recoveryUntil) or 0
        end

        profiles[src] = profile

        -- Offline decay. This is the whole reason the timestamps are stored.
        Profiles.applyDecay(src, false)
        pruneAllowance(profile)

        Profiles.sync(src)

        if not Database.available() then
            Bridge.notify(src, L('notify.not_saved'), 'error')
        end

        Sport.debug(('loaded %s (%s)'):format(GetPlayerName(src) or src, identifier))
        TriggerEvent('vsport:server:PlayerLoaded', src, Sport.copy(profile.stats))
    end)
end

local function unload(src)
    local profile = profiles[src]
    if not profile then return end

    if Config.Persistence.saveOnDrop then
        Database.save(profile.identifier, profile)
    end

    profiles[src] = nil
    dirty[src] = nil
    lastStateBag[src] = nil
end

Bridge.onPlayerLoaded(load)

AddEventHandler('playerDropped', function()
    unload(source)
end)

-- ---------------------------------------------------------------------------------------
-- The three timers
-- ---------------------------------------------------------------------------------------

--- Flush dirty rows, in batches. One timer for the whole server.
CreateThread(function()
    local interval = math.max(5, tonumber(Config.Performance.flushInterval) or 30) * 1000
    local batchSize = math.max(1, math.floor(tonumber(Config.Performance.flushBatchSize) or 50))

    while true do
        Wait(interval)

        if Database.available() then
            local written = 0

            for src in pairs(dirty) do
                if written >= batchSize then break end

                local profile = profiles[src]
                if profile then
                    Database.save(profile.identifier, profile)
                    written = written + 1
                end
                dirty[src] = nil
            end

            if written > 0 then Sport.debug('flushed', written, 'profiles') end
        end
    end
end)

--- Sweep expired buffs. Also one timer, not one per player.
CreateThread(function()
    local interval = math.max(1, tonumber(Config.Performance.buffSweepInterval) or 5) * 1000

    while true do
        Wait(interval)

        for src, profile in pairs(profiles) do
            if #profile.buffs > 0 or #profile.multipliers > 0 then
                if sweepBuffs(src, profile) then
                    Profiles.syncBuffs(src)
                end
            end
        end
    end
end)

--[[
    Re-check decay and the allowance for everybody online.

    Slow: fifteen minutes by default. Decay is measured in days, so checking it four times an
    hour is already far more often than it can possibly change anything, and the offline
    catch-up on load is what actually matters.
]]
CreateThread(function()
    local interval = math.max(60, tonumber(Config.Decay.onlineInterval) or 900) * 1000

    while true do
        Wait(interval)

        for src, profile in pairs(profiles) do
            local lost = Profiles.applyDecay(src, false)

            local freed = pruneAllowance(profile)
            if freed then Profiles.touch(src) end

            -- Tell a player who was blocked that they are not any more, once.
            if freed and profile.announcedBlocked and Config.Allowance.notifyRestored then
                if not Stats.allowanceExhausted(Profiles.allowanceSpent(profile)) then
                    profile.announcedBlocked = false
                    Bridge.notify(src, L('allowance.restored'), 'success')
                end
            end

            if next(lost) or freed then Profiles.sync(src) end
        end
    end
end)

--- Save everybody on a clean stop. A crash loses at most one flush interval.
AddEventHandler('onResourceStop', function(resource)
    if resource ~= Sport.resource then return end
    if not Config.Persistence.saveOnResourceStop then return end

    for _, profile in pairs(profiles) do
        Database.save(profile.identifier, profile)
    end
end)
