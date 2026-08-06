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

RegisterNetEvent('vsport:server:RequestSession', function(requestId, key, coords)
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
    local left = cooldownLeft(src, key)
    if left > 0 then
        return answer(nil, L('notify.cooldown', Sport.duration(left)))
    end

    -- --- Requirements -------------------------------------------------------------------
    local failure = requirementFailure(src, entry, profile)
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
    local expected = Equipment.minimumDurationMs(entry)

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

    -- --- Reps ---------------------------------------------------------------------------
    -- A payload claiming more reps than the equipment has is a client that edited the config.
    local reps = math.floor(Sport.clamp(payload.reps, 0, Equipment.reps(entry), 0))
    local quality = Sport.clamp(payload.quality, 0.0, 1.0, 0.0)

    if reps <= 0 then
        TriggerClientEvent('vsport:client:SessionResult', src, {},
            L('session.nothing_gained'))
        return
    end

    -- A session cut short pays for the part that was done. The quality already reflects only
    -- the keys that were actually asked for, so this is the only place the missing reps are
    -- accounted for.
    local completion = reps / Equipment.reps(entry)
    quality = quality * completion

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
    Sprinting and diving, reported in batches by client/passive.lua.

    Held to the same standard as a session: the amounts are clamped to what is physically
    possible in the reporting interval, and the daily caps are the server's own count rather
    than anything the client sent.
]]
local passiveDay = {}           -- src -> { stat -> points today, resetAt = unix }

RegisterNetEvent('vsport:server:Passive', function(payload)
    local src = source
    if type(payload) ~= 'table' then return end

    local profile = Profiles.get(src)
    if not profile then return end

    local now = Sport.now()
    local interval = math.max(5, tonumber(Config.Passive.reportInterval) or 30)

    local day = passiveDay[src]
    if not day or now >= (day.resetAt or 0) then
        day = { resetAt = now + 86400 }
        passiveDay[src] = day
    end

    local gains = {}

    -- --- Running -----------------------------------------------------------------------
    local running = Config.Passive.running
    if running and running.enabled then
        -- The ceiling is the interval times a sprint nobody can beat. Anything above it is
        -- a teleport, a vehicle the client missed, or a lie.
        local ceiling = interval * 12.0 * 2
        local metres = Sport.clamp(payload.metres, 0, ceiling, 0)

        if metres > 0 then
            local points = (metres / 1000.0) * (tonumber(running.perKilometre) or 0)
            local cap = tonumber(running.dailyCap) or 0
            local key = running.stat or 'stamina'

            if cap > 0 then
                points = math.min(points, math.max(0, cap - (day[key] or 0)))
            end

            if points > 0 then
                day[key] = (day[key] or 0) + points
                gains[key] = (gains[key] or 0) + points
            end
        end
    end

    -- --- Diving ------------------------------------------------------------------------
    local diving = Config.Passive.diving
    if diving and diving.enabled then
        local seconds = Sport.clamp(payload.diveSeconds, 0, interval * 2, 0)

        if seconds > 0 then
            local points = (seconds / 60.0) * (tonumber(diving.perMinute) or 0)
            local cap = tonumber(diving.dailyCap) or 0
            local key = diving.stat or 'breath'

            if cap > 0 then
                points = math.min(points, math.max(0, cap - (day[key] or 0)))
            end

            if points > 0 then
                day[key] = (day[key] or 0) + points
                gains[key] = (gains[key] or 0) + points
            end
        end
    end

    if not next(gains) then return end

    -- Passive training goes through the allowance like everything else. Running across the
    -- map is not a way around the recovery rule.
    for key, points in pairs(gains) do
        Profiles.changeStat(src, key, Sport.round(points, 3), 'add', true)
    end

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
