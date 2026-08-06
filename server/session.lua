--[[
    server/session.lua

    Authorising a workout, and judging the result that comes back.

    ---------------------------------------------------------------------------------------
    WHAT THIS CAN AND CANNOT DEFEND AGAINST, STATED HONESTLY
    ---------------------------------------------------------------------------------------

    The minigame runs on the client, so the client knows the score. No FiveM resource can
    change that: moving frame-accurate input judging to the server would need a round trip per
    key press. Anybody claiming their training script is cheat-proof is selling something.

    What the server CAN do, and what this file does, is refuse a result that is not physically
    possible:

      * A session must have been AUTHORISED. No token, no payout - so firing the finish event
        in a loop pays nothing.
      * A token is single-use and belongs to one player. It cannot be replayed or borrowed.
      * A result that arrives faster than the reps could have been performed is rejected.
      * A result from somebody who has since walked twelve metres away is rejected.
      * Cooldowns, the per-hour rate limit and the training allowance are all enforced HERE,
        from the server's own clock, not from anything the client sent.

    That leaves one hole: a cheater can play the session honestly-shaped and lie about their
    accuracy, gaining at most what an excellent player would have gained anyway. The
    allowance in section 5b is what bounds the damage - the very best possible player and the
    cheater hit the same daily ceiling.

    Every check fails CLOSED. A session that cannot be verified pays nothing.
]]

Sessions = {}

local active = {}               -- token -> session
local bySource = {}             -- src -> token
local cooldowns = {}            -- src -> { equipment key -> unix timestamp }

-- Where every running session is, published to clients so a prompt can be greyed out.
local occupied = {}

-- ---------------------------------------------------------------------------------------
-- Tokens
-- ---------------------------------------------------------------------------------------

local tokenCounter = 0

--[[
    A token.

    Not a security boundary on its own - the client is told the token, so it knows it. What
    it provides is a HANDLE: the server looks the token up in its own table to find the
    session it authorised, with the equipment, the coordinates and the clock it recorded at
    the time. A forged token matches nothing.
]]
local function newToken(src)
    tokenCounter = tokenCounter + 1
    return ('%d.%d.%d'):format(src, tokenCounter, math.random(100000, 999999))
end

-- ---------------------------------------------------------------------------------------
-- Occupancy
-- ---------------------------------------------------------------------------------------

local function publishOccupied()
    if not Config.General.exclusiveEquipment then return end

    local list = {}
    for _, session in pairs(active) do
        list[#list + 1] = {
            id = session.src,
            x = session.coords.x,
            y = session.coords.y,
            z = session.coords.z,
        }
    end

    occupied = list
    TriggerClientEvent('vsport:client:Occupied', -1, list)
end

--- Whether somebody other than `src` is training within `radius` of `coords`.
local function isOccupied(src, coords, radius)
    if not Config.General.exclusiveEquipment then return false end

    local limit = (tonumber(radius) or 1.4) ^ 2

    for _, session in pairs(active) do
        if session.src ~= src then
            local dx = session.coords.x - coords.x
            local dy = session.coords.y - coords.y
            local dz = session.coords.z - coords.z
            if (dx * dx + dy * dy + dz * dz) <= limit then return true end
        end
    end

    return false
end

-- ---------------------------------------------------------------------------------------
-- Rejections
-- ---------------------------------------------------------------------------------------

--[[
    Log a refusal, and raise a flag if one player is collecting them.

    One rejection is a desync - a dropped packet, a player who walked away mid-rep, a server
    that lagged. Five in an hour is somebody probing. This resource never kicks or bans; it
    fires an event and lets whatever the server uses for that decide.
]]
local function reject(src, reason, detail)
    if Config.Security.logRejections then
        Sport.warn(('rejected a session from %s (%s): %s%s'):format(
            GetPlayerName(src) or '?', src, reason, detail and (' - ' .. detail) or ''))
    end

    local profile = Profiles.get(src)
    if not profile or not Config.Security.fireSuspicionEvent then return end

    local now = Sport.now()
    for index = #profile.rejections, 1, -1 do
        if (now - profile.rejections[index]) > 3600 then
            table.remove(profile.rejections, index)
        end
    end

    profile.rejections[#profile.rejections + 1] = now

    local threshold = math.floor(tonumber(Config.Security.suspicionThreshold) or 5)
    if threshold > 0 and #profile.rejections >= threshold then
        profile.rejections = {}
        Sport.warn(('%s has hit the rejection threshold; firing vsport:server:CheatSuspected')
            :format(GetPlayerName(src) or src))
        TriggerEvent('vsport:server:CheatSuspected', src, reason, detail)
    end
end

-- ---------------------------------------------------------------------------------------
-- Cooldowns
-- ---------------------------------------------------------------------------------------

local function cooldownLeft(src, key)
    local held = cooldowns[src]
    if not held or not held[key] then return 0 end

    local left = held[key] - Sport.now()
    if left <= 0 then
        held[key] = nil
        return 0
    end

    return left
end

local function startCooldown(src, key, seconds)
    if (tonumber(seconds) or 0) <= 0 then return end
    cooldowns[src] = cooldowns[src] or {}
    cooldowns[src][key] = Sport.now() + seconds
end

-- ---------------------------------------------------------------------------------------
-- Requirements
-- ---------------------------------------------------------------------------------------

--[[
    A static spot's own job restriction, enforced HERE rather than trusted from the client.

    Config.Spots entries carry an optional `job`. The client's spot builder stored it and nothing ever
    read it, so a gym an operator believed was locked to the police was open to everyone. A documented
    restriction that does not exist is worse than not offering one.

    The server is never told WHICH spot was used, only the coordinates the client asked about, so the
    spot is found by proximity against the server's own copy of Config.Spots - the same list, and
    nothing the client said about it has to be believed.
]]
local function spotJobFailure(src, coords)
    if type(Config.Spots) ~= 'table' then return nil end

    for _, spot in ipairs(Config.Spots) do
        local job = spot.job
        local at = spot.coords

        if type(job) == 'string' and job ~= '' and type(at) ~= 'nil' then
            -- A little wider than the spot's own radius: the request carries the position the
            -- player was standing at, which is up to `useDistance` from the spot itself.
            local radius = (tonumber(spot.radius) or Config.General.useDistance or 2.5) + 1.5
            local dx, dy, dz = at.x - coords.x, at.y - coords.y, at.z - coords.z

            if (dx * dx + dy * dy + dz * dz) <= (radius * radius) then
                local roles = Bridge.roles(src)
                if roles.job ~= job and roles.jobType ~= job
                    and ('gang:' .. tostring(roles.gang)) ~= job then
                    return L('notify.requirement_job')
                end

                -- Inside a spot they are allowed to use. Nearer spots cannot also apply.
                return nil
            end
        end
    end

    return nil
end

--- Why `src` may not use `entry`, or nil. Re-checked here even though the client checked:
--- the client's copy of the config is whatever the client feels like reporting.
local function requirementFailure(src, entry, profile)
    local require_ = entry.require
    if type(require_) ~= 'table' then return nil end

    if type(require_.stats) == 'table' then
        for key, needed in pairs(require_.stats) do
            local def = Stats.def(key)
            if def and (profile.stats[key] or 0) < (tonumber(needed) or 0) then
                return L('notify.requirement_stat', L(def.label), math.floor(needed))
            end
        end
    end

    if type(require_.job) == 'string' and require_.job ~= '' then
        local roles = Bridge.roles(src)
        if roles.job ~= require_.job
            and roles.jobType ~= require_.job
            and ('gang:' .. roles.gang) ~= require_.job then
            return L('notify.requirement_job')
        end
    end

    if type(require_.item) == 'string' and require_.item ~= '' then
        if not Bridge.hasItem(src, require_.item) then
            return L('notify.requirement_item', require_.item)
        end
    end

    return nil
end

-- ---------------------------------------------------------------------------------------
-- Request
-- ---------------------------------------------------------------------------------------

RegisterNetEvent('vsport:server:RequestSession', function(requestId, key, coords, anywhere)
    local src = source

    local function answer(token, refusal)
        TriggerClientEvent('vsport:client:SessionAnswer', src, requestId, token, refusal)
    end

    -- --- Shape --------------------------------------------------------------------------
    -- Everything below indexes into these, so they are proved to be what they claim first.
    if type(requestId) ~= 'number' or type(key) ~= 'string' or type(coords) ~= 'table' then
        return answer(nil, nil)
    end

    local x, y, z = tonumber(coords.x), tonumber(coords.y), tonumber(coords.z)
    if not x or not y or not z then return answer(nil, nil) end

    local profile = Profiles.get(src)
    if not profile then return answer(nil, nil) end

    if profile.blocked then
        return answer(nil, profile.blockReason or L('notify.blocked'))
    end

    local entry = Equipment.get(key)
    if not entry then
        reject(src, 'unknown equipment', key)
        return answer(nil, nil)
    end

    --[[
        Training with no equipment.

        The client says "this one needs no equipment"; the server does not take its word for it.
        The key is checked against the server's own Config.Anywhere.allowed, so a client asking
        to bench press in mid-air, or to use a piece of equipment nobody is near, is refused
        here rather than trusted.

        This is also the one case where the distance check below is meaningless - the coordinates
        ARE the player - so the allowance, the cooldowns and this list are what bound it.
    ]]
    local isAnywhere = anywhere == true

    if isAnywhere then
        if not Config.Anywhere.enabled then
            return answer(nil, L('refuse.no_equipment'))
        end

        if not Sport.contains(Config.Anywhere.allowed, key) then
            reject(src, 'asked to do a prop exercise with no equipment', key)
            return answer(nil, L('refuse.no_equipment'))
        end
    end

    -- --- One at a time -------------------------------------------------------------------
    local existing = bySource[src]
    if existing then
        -- A stale session from a client that crashed mid-workout. Clear it rather than
        -- refusing forever.
        local held = active[existing]
        if held and (Sport.now() - held.startedAt) < 900 then
            return answer(nil, nil)
        end
        active[existing] = nil
        bySource[src] = nil
    end

    -- --- Distance -------------------------------------------------------------------------
    local ped = GetPlayerPed(src)
    if not ped or ped == 0 then return answer(nil, nil) end

    local pedCoords = GetEntityCoords(ped)
    local dx, dy, dz = pedCoords.x - x, pedCoords.y - y, pedCoords.z - z
    local distanceSquared = dx * dx + dy * dy + dz * dz

    -- A generous tolerance on top of the configured use distance: the client measured from
    -- where it thought the prop was, and the two positions are a frame or two apart.
    local allowed = (tonumber(Config.General.useDistance) or 2.5) + 4.0
    if distanceSquared > (allowed * allowed) then
        reject(src, 'too far from the equipment',
            ('%.1fm'):format(math.sqrt(distanceSquared)))
        return answer(nil, L('refuse.distance'))
    end

    -- --- Exclusivity ----------------------------------------------------------------------
    if isOccupied(src, { x = x, y = y, z = z }, 1.4) then
        return answer(nil, L('prompt.busy'))
    end

    -- --- Cooldown and rate ------------------------------------------------------------------
    local checkCooldown = (not isAnywhere) or Config.Anywhere.respectCooldowns ~= false

    if checkCooldown then
        local left = cooldownLeft(src, key)
        if left > 0 then
            return answer(nil, L('notify.cooldown', Sport.duration(left)))
        end
    end

    -- --- Requirements -------------------------------------------------------------------
    local failure = requirementFailure(src, entry, profile)
    if failure then return answer(nil, failure) end

    -- And a static spot's own job restriction, which until 1.0.1 was stored and never checked.
    failure = spotJobFailure(src, coords)
    if failure then return answer(nil, failure) end

    -- --- Allowance ------------------------------------------------------------------------
    -- Warn BEFORE the workout rather than after it. Fifteen reps for nothing, with the reason
    -- arriving at the end, is the single most irritating way this could behave.
    local spent = Profiles.allowanceSpent(profile)
    if Stats.allowanceExhausted(spent) then
        profile.announcedBlocked = true
        local resets = Profiles.allowanceResetsIn(profile)
        return answer(nil, L('allowance.blocked', resets and Sport.duration(resets) or '?'))
    end

    --[[
        The per-stat case, which is the one that actually bites.

        With the defaults, a player who only ever benches hits the 25 point per-stat cap
        while 25 points of their global 50 are still unspent. The global check above passes,
        this one catches it, and the message names the stat - so they are told to go and
        train something else rather than left wondering why the bench pays nothing.
    ]]
    local _, perStatLeft = Stats.allowanceLeft(spent)
    local blockedStat = nil

    for statKey in pairs(entry.gains or {}) do
        if Stats.def(statKey) then
            if (perStatLeft[statKey] or math.huge) > 0.001 then
                blockedStat = nil
                break
            end
            blockedStat = blockedStat or statKey
        end
    end

    if blockedStat then
        return answer(nil, L('allowance.blocked_stat', L(Stats.def(blockedStat).label)))
    end

    -- --- Grant --------------------------------------------------------------------------
    local token = newToken(src)

    active[token] = {
        src = src,
        key = key,
        entry = entry,
        coords = { x = x, y = y, z = z },
        startedAt = Sport.now(),
        startedAtMs = GetGameTimer(),
        anywhere = isAnywhere,
    }
    bySource[src] = token

    publishOccupied()
    answer(token, nil)

    Sport.debug(('%s started %s'):format(GetPlayerName(src) or src, key))
    TriggerEvent('vsport:server:SessionStarted', src, key)
end)

-- ---------------------------------------------------------------------------------------
-- Finish
-- ---------------------------------------------------------------------------------------

local function clearSession(token, session)
    active[token] = nil
    if session and bySource[session.src] == token then
        bySource[session.src] = nil
    end
    publishOccupied()
end

RegisterNetEvent('vsport:server:FinishSession', function(token, payload)
    local src = source

    if type(token) ~= 'string' or type(payload) ~= 'table' then return end

    local session = active[token]
    if not session then
        reject(src, 'no such session token')
        return
    end

    -- The token belongs to whoever it was issued to and to nobody else.
    if session.src ~= src then
        reject(src, 'session token belongs to another player')
        return
    end

    clearSession(token, session)

    local profile = Profiles.get(src)
    if not profile then return end

    local entry = session.entry
    startCooldown(src, session.key, Equipment.cooldown(entry))

    -- --- Duration -------------------------------------------------------------------------
    -- Measured on the SERVER's clock. The client also reports its own elapsed time, and that
    -- number is never trusted for anything - it is only logged when the two disagree.
    local elapsedMs = (GetGameTimer() - session.startedAtMs)

    --[[
        HOW MANY REPS, READ BEFORE THE DURATION IS JUDGED.

        This used to be parsed further down, and the duration check above it compared the elapsed
        time against the minimum for a FULL set. So every session that ended early - four misses in a
        row, or the player holding the cancel key - was rejected as impossibly fast and paid nothing,
        while the code fifty lines below carefully worked out what a partial set was worth. The
        rejection came first, so the partial-payment logic could never run.

        A payload claiming more reps than the equipment has is a client that edited the config.
    ]]
    local reps = math.floor(Sport.clamp(payload.reps, 0, Equipment.reps(entry), 0))

    if reps <= 0 then
        TriggerClientEvent('vsport:client:SessionResult', src, {},
            L('session.nothing_gained'))
        return
    end

    local expected = Equipment.minimumDurationMs(entry, reps)

    local minFactor = tonumber(Config.Security.minDurationFactor) or 0.75
    local maxFactor = tonumber(Config.Security.maxDurationFactor) or 4.0

    if expected > 0 and elapsedMs < (expected * minFactor) then
        reject(src, 'session finished impossibly fast',
            ('%dms against an expected %dms'):format(elapsedMs, math.floor(expected * minFactor)))
        TriggerClientEvent('vsport:client:SessionResult', src, {}, nil)
        return
    end

    if expected > 0 and maxFactor > 0 and elapsedMs > (expected * maxFactor) then
        reject(src, 'session took far too long',
            ('%dms against an expected %dms'):format(elapsedMs, math.floor(expected * maxFactor)))
        TriggerClientEvent('vsport:client:SessionResult', src, {}, nil)
        return
    end

    -- --- Drift --------------------------------------------------------------------------
    local drift = tonumber(Config.Security.maxDriftDistance) or 0
    if drift > 0 then
        local ped = GetPlayerPed(src)
        if ped and ped ~= 0 then
            local pedCoords = GetEntityCoords(ped)
            local dx = pedCoords.x - session.coords.x
            local dy = pedCoords.y - session.coords.y
            local dz = pedCoords.z - session.coords.z

            if (dx * dx + dy * dy + dz * dz) > (drift * drift) then
                reject(src, 'moved away from the equipment during the session')
                TriggerClientEvent('vsport:client:SessionResult', src, {}, nil)
                return
            end
        end
    end

    -- --- Quality ------------------------------------------------------------------------
    local quality = Sport.clamp(payload.quality, 0.0, 1.0, 0.0)

    -- A session cut short pays for the part that was done. The quality already reflects only
    -- the keys that were actually asked for, so this is the only place the missing reps are
    -- accounted for.
    local completion = reps / Equipment.reps(entry)
    quality = quality * completion

    -- Exercises done with no equipment can be worth less than the same exercise on a mat, if
    -- the operator wants a reason to go to a gym. Ships at 1.0: a push-up is a push-up.
    if session.anywhere then
        quality = quality * Sport.clamp(Config.Anywhere.gainScale, 0.0, 1.0, 1.0)
    end

    -- --- Pay ------------------------------------------------------------------------------
    local gains, note = Profiles.awardSession(src, entry, quality)

    TriggerClientEvent('vsport:client:SessionResult', src, gains, note)
    TriggerClientEvent('vsport:client:Cooldown', src, session.key, Equipment.cooldown(entry))

    Sport.debug(('%s finished %s: quality %.2f, %d reps -> %s'):format(
        GetPlayerName(src) or src, session.key, quality, reps, json.encode(gains)))
end)

--- The client gave up before the minigame produced a result, or the resource stopped.
RegisterNetEvent('vsport:server:AbandonSession', function(token)
    local src = source
    if type(token) ~= 'string' then return end

    local session = active[token]
    if not session or session.src ~= src then return end

    clearSession(token, session)
    Sport.debug(('%s abandoned %s'):format(GetPlayerName(src) or src, session.key))
end)

-- ---------------------------------------------------------------------------------------
-- Passive training
-- ---------------------------------------------------------------------------------------

--[[
    Sprinting, cycling, swimming and diving, reported in batches by client/passive.lua.

    Held to the same standard as a session. Nothing the client sends is trusted:

      * every amount is clamped to what the reporting interval could physically hold, worked out
        from the activity's own `maxSpeed` rather than from a number hidden in here
      * the caps - per activity, and across the whole section - are the server's own running
        count, not anything the client mentioned
      * the ceiling is checked against the stat the SERVER holds
      * what survives goes through the allowance ledger, so running across the map is not a way
        around the fifty-points-per-twenty-five-hours rule

    The activity list is data. Adding a fifth means a row here and a row in client/passive.lua,
    with no other change on either side.
]]
local passiveDay = {}           -- src -> { total = points today, [stat] = points, resetAt = unix }

--[[
    unit  'distance' converts metres to kilometres, 'time' converts seconds to minutes. That
          division is the only difference between the four, so it is the only thing stored.
    fallbackMax  the speed used to size the honesty ceiling when the activity's config has no
          `maxSpeed`. For a timed activity it is unused: a dive cannot exceed the wall clock.
]]
local PASSIVE_ACTIVITIES = {
    { key = 'running',  field = 'runMetres',   unit = 'distance', fallbackMax = 12.0 },
    { key = 'cycling',  field = 'bikeMetres',  unit = 'distance', fallbackMax = 18.0 },
    { key = 'swimming', field = 'swimMetres',  unit = 'distance', fallbackMax = 4.0 },
    { key = 'diving',   field = 'diveSeconds', unit = 'time' },
}

--- The most this activity could honestly have accumulated in one reporting interval. Doubled,
--- because a report can arrive late and carry two intervals' worth rather than one.
local function honestCeiling(activity, cfg, interval)
    if activity.unit == 'time' then return interval * 2 end

    local top = tonumber(cfg.maxSpeed) or activity.fallbackMax or 12.0
    return interval * top * 2
end

RegisterNetEvent('vsport:server:Passive', function(payload)
    local src = source
    if type(payload) ~= 'table' then return end
    if not Config.Passive.enabled then return end

    local profile = Profiles.get(src)
    if not profile then return end

    local now = Sport.now()
    local interval = math.max(5, tonumber(Config.Passive.reportInterval) or 30)
    local scale = tonumber(Config.Passive.globalScale) or 1.0

    local day = passiveDay[src]
    if not day or now >= (day.resetAt or 0) then
        day = { resetAt = now + 86400, total = 0.0 }
        passiveDay[src] = day
    end

    -- The whole-section cap, as room remaining rather than as a total, so every activity below
    -- draws from the same pool in the order they are declared.
    local totalCap = tonumber(Config.Passive.dailyCapTotal) or 0
    local totalRoom = totalCap > 0 and math.max(0.0, totalCap - (day.total or 0.0)) or math.huge

    local gains = {}

    for _, activity in ipairs(PASSIVE_ACTIVITIES) do
        local cfg = Config.Passive[activity.key]

        if cfg and cfg.enabled and totalRoom > 0 then
            local amount = Sport.clamp(payload[activity.field], 0,
                honestCeiling(activity, cfg, interval), 0)

            if amount > 0 then
                local divisor = activity.unit == 'time' and 60.0 or 1000.0
                local units = amount / divisor

                -- This activity's own remaining allowance for the day, across all its stats.
                local ownCap = tonumber(cfg.dailyCap) or 0
                local ownRoom = ownCap > 0
                    and math.max(0.0, ownCap - (day[activity.key] or 0.0))
                    or math.huge

                for statKey, perUnit in pairs(cfg.gains or {}) do
                    local def = Stats.def(statKey)

                    --[[
                        THE CEILING, AND IT IS CHECKED AGAINST THE SERVER'S OWN VALUE.

                        Passive training stops dead at this figure rather than tapering, so the
                        rule is easy to explain to a player: swimming takes your lungs to 75 and
                        the rest is yoga. A stat already at or above it earns nothing here, which
                        also means the arithmetic below never has to think about partial credit.
                    ]]
                    local ceiling = tonumber(cfg.ceiling)
                        or tonumber(Config.Passive.ceiling) or 100.0
                    local held = tonumber(profile.stats[statKey]) or 0.0

                    if def and held < ceiling then
                        local points = units * (tonumber(perUnit) or 0.0) * scale

                        -- Three bounds, cheapest first: the stat's own headroom to the ceiling,
                        -- this activity's day, and the section's day.
                        points = math.min(points, ceiling - held, ownRoom, totalRoom)

                        if points > 0 then
                            day[activity.key] = (day[activity.key] or 0.0) + points
                            day.total = (day.total or 0.0) + points
                            ownRoom = ownRoom - points
                            totalRoom = totalRoom - points

                            gains[statKey] = (gains[statKey] or 0.0) + points
                        end
                    end
                end
            end
        end
    end

    if not next(gains) then return end

    for key, points in pairs(gains) do
        gains[key] = Sport.round(points, 3)
        Profiles.changeStat(src, key, gains[key], 'add', true)
    end

    --[[
        Whether that counted as training, for the decay clock and for fatigue.

        FALSE by default, and it is the single most important number in Config.Passive: with it
        off, a player who cycles all day has earned a little stamina and has still not trained,
        so the ten-a-day decay keeps running against a two-a-day cap and they lose ground. That
        is what stops passive activity from replacing the equipment.
    ]]
    if Config.Passive.countsAsTraining then
        Profiles.markTrained(src, gains)
    end

    TriggerClientEvent('vsport:client:PassiveGain', src, gains)

    Sport.debug(('%s passive: %s'):format(GetPlayerName(src) or src, json.encode(gains)))
end)

-- ---------------------------------------------------------------------------------------
-- Housekeeping
-- ---------------------------------------------------------------------------------------

AddEventHandler('playerDropped', function()
    local src = source

    local token = bySource[src]
    if token then clearSession(token, active[token]) end

    bySource[src] = nil
    cooldowns[src] = nil
    passiveDay[src] = nil
end)

--- Force a player's session to end. Used by the exports and by the admin command.
function Sessions.forceStop(src, reason)
    local token = bySource[src]
    if not token then return false end

    clearSession(token, active[token])
    TriggerClientEvent('vsport:client:Blocked', src, false, nil)
    TriggerClientEvent('vsport:client:ForceStop', src, reason)
    return true
end

--- Whether `src` is training, and on what.
function Sessions.current(src)
    local token = bySource[src]
    local session = token and active[token]
    if not session then return nil end

    return {
        equipment = session.key,
        startedAt = session.startedAt,
        coords = session.coords,
    }
end

--- Seconds left on an equipment cooldown for `src`.
function Sessions.cooldownLeft(src, key)
    return cooldownLeft(src, key)
end

--- Clear one cooldown, or all of them. The "bypass the recovery" hook for a drug script.
function Sessions.clearCooldowns(src, key)
    if not cooldowns[src] then return false end

    if key == nil then
        cooldowns[src] = {}
    else
        cooldowns[src][key] = nil
    end

    return true
end
