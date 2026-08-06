--[[
    client/session.lua

    One workout, start to finish.

        check -> ask the server -> get into position -> play the animation ->
        run the minigame -> tell the server what happened -> clean up

    The client never decides what a session is WORTH. It reports what happened and the server
    re-derives the payout from the equipment, the player's own stored state and its own clock.
    Everything checked here is checked again there; these checks exist so the player gets a
    reason instead of a silent refusal after a round trip.
]]

Session = {}

local current = nil             -- the running session, or nil
local occupied = {}             -- server-published list of coords other players are training at
local ownServerId = 0

CreateThread(function()
    while ownServerId == 0 do
        ownServerId = GetPlayerServerId(PlayerId())
        if ownServerId == 0 then Wait(500) end
    end
end)

--- Whether a workout is running right now.
function Session.active()
    return current ~= nil
end

--- What is running, as a copy. For the exports; nothing internal reads it.
function Session.info()
    if not current then return nil end
    return {
        equipment = current.key,
        label = current.label,
        startedAt = current.startedAt,
        reps = current.reps,
    }
end

-- ---------------------------------------------------------------------------------------
-- Exclusivity
-- ---------------------------------------------------------------------------------------
--
-- Two players cannot share a bench. The check is SERVER-SIDE - the server knows where every
-- active session is and refuses a request that lands on top of one - and this list is the
-- client's copy of the same information, used only so the prompt can say "someone is already
-- using this" instead of letting the player press E and be told no.
--
-- Published on session start and stop, which is a handful of small events a minute on a busy
-- server, and not at all when Config.General.exclusiveEquipment is off.

RegisterNetEvent('vsport:client:Occupied', function(list)
    occupied = type(list) == 'table' and list or {}
end)

--- Whether another player is training within `radius` metres of `coords`.
function Session.isOccupied(coords, radius)
    if not Config.General.exclusiveEquipment then return false end

    local limit = (tonumber(radius) or 1.4) ^ 2

    for _, entry in ipairs(occupied) do
        if entry.id ~= ownServerId then
            local dx, dy, dz = entry.x - coords.x, entry.y - coords.y, entry.z - coords.z
            if (dx * dx + dy * dy + dz * dz) <= limit then return true end
        end
    end

    return false
end

-- ---------------------------------------------------------------------------------------
-- Asking the server
-- ---------------------------------------------------------------------------------------
--
-- A tiny request/response over two net events rather than a framework callback, because
-- qb-core, ESX and ox_core each have a different callback API and this resource does not
-- name any of them outside the bridge.

local pending = {}
local nextRequest = 0

RegisterNetEvent('vsport:client:SessionAnswer', function(id, token, refusal)
    local entry = pending[id]
    if not entry or entry.done then return end

    entry.done = true
    pending[id] = nil
    entry.promise:resolve({ token = token, refusal = refusal })
end)

--- Ask for permission. Returns a token, or nil plus a reason. nil/nil means the server never
--- answered, which is a dropped event or a server that is not running this resource.
local function requestPermission(key, coords)
    nextRequest = nextRequest + 1
    local id = nextRequest

    local entry = { promise = promise.new(), done = false }
    pending[id] = entry

    TriggerServerEvent('vsport:server:RequestSession', id, key,
        { x = coords.x, y = coords.y, z = coords.z })

    -- A request that is never answered must not leave the player frozen mid-animation.
    SetTimeout(6000, function()
        if entry.done then return end
        entry.done = true
        pending[id] = nil
        entry.promise:resolve({ token = nil, refusal = nil })
    end)

    local answer = Citizen.Await(entry.promise)
    return answer.token, answer.refusal
end

-- ---------------------------------------------------------------------------------------
-- Local checks
-- ---------------------------------------------------------------------------------------

--- Why the player cannot train right now, or nil. Ordered cheapest first, and by how likely
--- each one is to be the actual answer.
local function refusal(entry)
    local ped = PlayerPedId()
    local refuse = Config.General.refuseWhen

    if current then return '' end                       -- already training; say nothing

    local allowed, reason = State.canTrain()
    if not allowed then return reason end

    if refuse.dead and IsEntityDead(ped) then return L('refuse.dead') end
    if refuse.inVehicle and IsPedInAnyVehicle(ped, false) then return L('refuse.in_vehicle') end
    if refuse.swimming and IsPedSwimming(ped) then return L('refuse.swimming') end
    if refuse.ragdoll and IsPedRagdoll(ped) then return L('refuse.ragdoll') end
    if refuse.falling and IsPedFalling(ped) then return L('refuse.falling') end
    if refuse.cuffed and Compat.isCuffed() then return L('refuse.cuffed') end

    if refuse.inCombat then
        if IsPedInMeleeCombat(ped) or IsPedShooting(ped) then return L('refuse.combat') end
        -- A drawn weapon counts. Holstering is offered as a convenience below, so this only
        -- refuses when the operator turned that off.
        if not Config.General.holsterWeapon and GetSelectedPedWeapon(ped) ~= `WEAPON_UNARMED` then
            return L('refuse.combat')
        end
    end

    local left = State.cooldownLeft(entry.key)
    if left > 0 then return L('notify.cooldown', Sport.duration(left)) end

    -- Requirements. The server checks these again; here they buy a useful message.
    local require_ = entry.require
    if type(require_) == 'table' then
        if type(require_.stats) == 'table' then
            for statKey, needed in pairs(require_.stats) do
                local def = Stats.def(statKey)
                if def and State.raw(statKey) < (tonumber(needed) or 0) then
                    return L('notify.requirement_stat', L(def.label), math.floor(needed))
                end
            end
        end

        if type(require_.job) == 'string' and require_.job ~= '' then
            local roles = Compat.roles()
            if roles.job ~= require_.job and ('gang:' .. roles.gang) ~= require_.job then
                return L('notify.requirement_job')
            end
        end
    end

    return nil
end

-- ---------------------------------------------------------------------------------------
-- Positioning and animation
-- ---------------------------------------------------------------------------------------

--[[
    Walk the player onto the mark.

    TaskGoStraightToCoord rather than SetEntityCoords, so the character walks the last metre
    instead of teleporting. It is given a deadline, and the position is forced afterwards -
    the task fails silently against a doorway, a step or another ped, and a workout that
    plays a metre to the left of the bench looks worse than one that snapped.
]]
local function moveIntoPosition(target, heading)
    if not target then return end

    local ped = PlayerPedId()

    TaskGoStraightToCoord(ped, target.x, target.y, target.z, 1.0, 3000,
        heading or GetEntityHeading(ped), 0.15)

    local deadline = GetGameTimer() + 3200
    while GetGameTimer() < deadline do
        local coords = GetEntityCoords(ped)
        local dx, dy = coords.x - target.x, coords.y - target.y
        if (dx * dx + dy * dy) < 0.09 then break end
        Wait(100)
    end

    ClearPedTasks(ped)
    SetEntityCoords(ped, target.x, target.y, target.z, false, false, false, false)
    if heading then SetEntityHeading(ped, heading) end
    Wait(150)
end

--- Load an animation dictionary, or give up. A dictionary that does not exist never becomes
--- ready, so the wait is bounded and the caller falls through to the scenario.
local function loadAnimDict(dict)
    if type(dict) ~= 'string' or dict == '' then return false end
    if HasAnimDictLoaded(dict) then return true end

    RequestAnimDict(dict)

    local deadline = GetGameTimer() + 2000
    while not HasAnimDictLoaded(dict) and GetGameTimer() < deadline do
        Wait(50)
    end

    return HasAnimDictLoaded(dict)
end

--[[
    Start the exercise animation.

    An animation dictionary is preferred when the catalogue names one AND it loads; a scenario
    otherwise. Both can fail on a given map or game build, and neither failing stops the
    session - the minigame is the workout, the animation is the dressing.
]]
local function startAnimation(entry)
    local ped = PlayerPedId()

    if type(entry.anim) == 'table' and loadAnimDict(entry.anim.dict) then
        TaskPlayAnim(ped, entry.anim.dict, entry.anim.clip,
            8.0, -8.0, -1, entry.anim.flag or 1, 0.0, false, false, false)
        return 'anim'
    end

    if type(entry.scenario) == 'string' and entry.scenario ~= '' then
        TaskStartScenarioInPlace(ped, entry.scenario, 0, true)
        return 'scenario'
    end

    return 'none'
end

local function stopAnimation(entry)
    local ped = PlayerPedId()

    ClearPedTasksImmediately(ped)

    if type(entry.anim) == 'table' and type(entry.anim.dict) == 'string' then
        -- Let the streamer reclaim it. Keeping every workout dictionary resident for the
        -- session is a few megabytes for no reason.
        RemoveAnimDict(entry.anim.dict)
    end
end

-- ---------------------------------------------------------------------------------------
-- Start
-- ---------------------------------------------------------------------------------------

--[[
    Begin a workout.

    `candidate` is a Detect entry - the prop or the static spot. `key` names which of the
    exercises that prop offers; nil takes the first, which is the one the prompt was showing.

    Returns false when it refused, with the reason already shown to the player.
]]
function Session.start(candidate, key)
    if current then return false end
    if type(candidate) ~= 'table' then return false end

    local equipmentKey = key or candidate.keys[1]
    local entry = Equipment.get(equipmentKey)
    if not entry then return false end

    local reason = refusal(entry)
    if reason ~= nil then
        if reason ~= '' and Config.Notifications.requirementFailed then
            Compat.notify(reason, 'error')
        end
        return false
    end

    -- Snapshot what the session needs, because `candidate` points into a table the detection
    -- loop reuses and will have overwritten by the next frame.
    local coords = vector3(candidate.coords.x, candidate.coords.y, candidate.coords.z)
    local entity = candidate.entity
    local spot = candidate.spot

    if Session.isOccupied(coords) then
        Compat.notify(L('prompt.busy'), 'error')
        return false
    end

    current = {
        key = equipmentKey,
        entry = entry,
        label = Locale.text(entry.label or equipmentKey),
        coords = coords,
        startedAt = GetGameTimer(),
        reps = Equipment.reps(entry),
    }

    CreateThread(function()
        local ped = PlayerPedId()

        -- --- Permission ---------------------------------------------------------------
        local token, refused = requestPermission(equipmentKey, coords)

        if not token then
            current = nil
            if refused then
                Compat.notify(refused, 'error')
            else
                Sport.warn('the server did not answer a session request')
            end
            return
        end

        current.token = token

        -- --- Position -----------------------------------------------------------------
        if Config.General.holsterWeapon then
            SetCurrentPedWeapon(ped, `WEAPON_UNARMED`, true)
        end

        local heading
        local target

        if spot then
            target = spot.coords
            heading = spot.heading
        elseif entity and entry.snap ~= false and entry.offset then
            target = GetOffsetFromEntityInWorldCoords(entity,
                entry.offset.x, entry.offset.y, entry.offset.z)
            if entry.heading then
                heading = GetEntityHeading(entity) + entry.heading
            end
        end

        if target then
            moveIntoPosition(target, heading)
        elseif heading then
            SetEntityHeading(ped, heading)
        end

        -- The player may have died, been dragged into a car or been blocked while walking to
        -- the mark. Nothing below is worth doing if so.
        if not current then return end
        local late = refusal(entry)
        if late ~= nil and late ~= '' then
            Compat.notify(late, 'error')
            Session.finish(nil)
            return
        end

        -- --- Go ------------------------------------------------------------------------
        startAnimation(entry)
        TriggerEvent('vsport:client:SessionStarted', equipmentKey, current.label)

        if Config.UI.hideHudDuringSession then DisplayHud(false) end
        if Config.UI.hideRadarDuringSession then DisplayRadar(false) end

        local result = Minigame.run({
            entry = entry,
            label = current.label,
            shouldStop = function()
                -- Anything that makes continuing absurd. Checked every frame, and cheap:
                -- three natives and a flag.
                if not current then return true end
                if State.blocked then return true end
                local p = PlayerPedId()
                return IsEntityDead(p) or IsPedInAnyVehicle(p, false)
            end,
        })

        Session.finish(result)
    end)

    return true
end

-- ---------------------------------------------------------------------------------------
-- Finish
-- ---------------------------------------------------------------------------------------

--[[
    Clean up and report.

    `result` of nil means the session never really started, so nothing is reported and no
    cooldown is taken. Everything else is reported, including a failure - the server pays out
    for the reps that were completed, and it needs to know the session is over either way so
    it can release the exclusivity claim.
]]
function Session.finish(result)
    if not current then return end

    local session = current
    current = nil

    stopAnimation(session.entry)

    if Config.UI.hideHudDuringSession then DisplayHud(true) end
    if Config.UI.hideRadarDuringSession then DisplayRadar(true) end

    Detect.invalidate()

    if not result then
        if session.token then
            TriggerServerEvent('vsport:server:AbandonSession', session.token)
        end
        TriggerEvent('vsport:client:SessionEnded', session.key, nil)
        return
    end

    local elapsed = GetGameTimer() - session.startedAt

    TriggerServerEvent('vsport:server:FinishSession', session.token, {
        quality = Sport.round(result.quality, 4),
        reps = result.reps,
        misses = result.misses,
        perfects = result.perfects,
        status = result.status,
        elapsed = elapsed,
        coords = { x = session.coords.x, y = session.coords.y, z = session.coords.z },
    })

    State.startCooldown(session.key, Equipment.cooldown(session.entry))

    if result.status == 'failed' and Config.Notifications.sessionFailed then
        Compat.notify(L('session.aborted'), 'error')
    end

    TriggerEvent('vsport:client:SessionEnded', session.key, result)
end

--- Stop a running session from outside. Used by the block event, by the exports and by
--- anything that decides the player has better things to do.
function Session.stop(reason)
    if not current then return false end

    Sport.debug('session stopped:', reason or 'external')

    -- The minigame's own shouldStop closure sees `current` go nil on the next frame and
    -- returns 'cancelled', which routes through Session.finish with a real result. Clearing
    -- the flag here rather than calling finish directly is what stops the two paths racing.
    local session = current
    current = nil

    stopAnimation(session.entry)

    if session.token then
        TriggerServerEvent('vsport:server:AbandonSession', session.token)
    end

    if Config.UI.hideHudDuringSession then DisplayHud(true) end
    if Config.UI.hideRadarDuringSession then DisplayRadar(true) end

    Detect.invalidate()
    TriggerEvent('vsport:client:SessionEnded', session.key, nil)
    return true
end

-- ---------------------------------------------------------------------------------------
-- What the server says happened
-- ---------------------------------------------------------------------------------------

--- The payout. Sent after the server has re-derived it, so this is the first time the client
--- learns what the session was actually worth.
RegisterNetEvent('vsport:client:SessionResult', function(gains, note)
    if type(gains) ~= 'table' or not next(gains) then
        if note and Config.Notifications.sessionComplete then
            Compat.notify(note, 'error')
        elseif Config.Notifications.sessionComplete then
            Compat.notify(L('session.nothing_gained'), 'error')
        end
        return
    end

    if not Config.Notifications.sessionComplete then return end

    -- One line listing everything that moved, rather than one notification per stat.
    local parts = {}
    for _, key in ipairs(Stats.keys()) do
        local amount = tonumber(gains[key])
        if amount and amount > 0 then
            local def = Stats.def(key)
            parts[#parts + 1] = L('notify.gained', amount, L(def.label))
        end
    end

    if #parts > 0 then
        Compat.notify(L('notify.gained_multi', table.concat(parts, '   ')), 'success')
    end
end)

--- Interrupt on death, which the minigame's own check also catches but which can happen
--- between frames of the walk-into-position phase.
AddEventHandler('gameEventTriggered', function(name, args)
    if name ~= 'CEventNetworkEntityDamage' then return end
    if not current then return end

    local victim = args[1]
    if victim == PlayerPedId() and IsEntityDead(victim) then
        Session.stop('death')
    end
end)

AddEventHandler('onResourceStop', function(resource)
    if resource ~= Sport.resource then return end
    if current then Session.stop('resource stopped') end
end)
