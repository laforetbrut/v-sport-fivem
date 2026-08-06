--[[
    client/passive.lua

    Training that happens without a prop: sprinting, cycling, swimming and diving.

    All four are deliberately small. They exist so that a long swim or a run across the city is
    not worth literally nothing, not as a substitute for the gym - see the balance notes at the
    top of Config.Passive for the three separate mechanisms that keep the equipment ahead.

    ---------------------------------------------------------------------------------------
    WHAT THIS COSTS
    ---------------------------------------------------------------------------------------

    One loop at one second, and every branch of it returns immediately unless the player is
    actually doing the thing. When the section is switched off, or all four activities are, the
    thread ends at its first lines and never runs again.

    Progress accumulates locally and is reported in a batch every `reportInterval` seconds: one
    event per player per thirty seconds carrying four numbers, rather than an event per metre.

    ---------------------------------------------------------------------------------------
    THE CLIENT MEASURES, THE SERVER DECIDES
    ---------------------------------------------------------------------------------------

    Nothing here is trusted. This file reports distances and durations; the server clamps each
    one to what the interval could physically hold, applies the caps from its own count, checks
    the ceiling against the stat it holds, and puts the result through the allowance ledger. A
    modified client can lie about how far it swam and gain, at most, what an honest player would
    have gained by actually swimming that far - and the daily cap bounds even that.
]]

Passive = {}

--[[
    THE FOUR ACTIVITIES, and the shape is deliberate: the payload field names are declared here
    once and the server reads the same list, so adding a fifth activity is a matter of adding a
    row in both places rather than finding every mention of a magic string.
]]
local DISTANCE = {
    { key = 'running',  field = 'runMetres' },
    { key = 'cycling',  field = 'bikeMetres' },
    { key = 'swimming', field = 'swimMetres' },
}

-- Accumulated since the last report, keyed by payload field.
local pending = {
    runMetres = 0.0,
    bikeMetres = 0.0,
    swimMetres = 0.0,
    diveSeconds = 0.0,
}

local diveStarted = nil         -- game timer when the current dive began
local lastCoords = nil          -- for the distance measurement
local lastAt = 0

--- Is this activity switched on, taking the master switch into account?
local function on(key)
    if not Config.Passive.enabled then return false end
    local cfg = Config.Passive[key]
    return cfg ~= nil and cfg.enabled == true
end

--- Send whatever has accumulated, and reset. Nothing is sent when there is nothing to say,
--- which is the usual case - a player standing still reports never.
local function report()
    --[[
        Send nothing until something is worth sending, and then send ALL of it.

        The threshold is per field but the reset is total: once any one activity has a metre or a
        second to report, every accumulator goes in the same payload and every one is cleared.
        Thresholding each field independently would quietly discard the 0.6 of a metre that a
        player swam between two sprints, every thirty seconds, forever.
    ]]
    local anything = false
    for _, amount in pairs(pending) do
        if amount >= 1.0 then
            anything = true
            break
        end
    end

    if not anything then return end

    local payload = {}
    for field, amount in pairs(pending) do
        payload[field] = Sport.round(amount, 1)
        pending[field] = 0.0
    end

    TriggerServerEvent('vsport:server:Passive', payload)

    Sport.debug(('passive report: %.0fm run, %.0fm bike, %.0fm swim, %.0fs under')
        :format(payload.runMetres or 0, payload.bikeMetres or 0,
                payload.swimMetres or 0, payload.diveSeconds or 0))
end

--[[
    Which distance activity, if any, the player is engaged in right now.

    One function rather than three branches because the three share everything except their
    test: the measurement, the speed window and the teleport rejection are identical, and only
    the question "what is this player doing" differs. Returns the payload field and the
    activity's config, or nil.
]]
local function currentDistanceActivity(ped)
    -- Swimming first: a swimming ped is not in a vehicle and is not sprinting, so testing it
    -- early costs one native and removes it from the other two questions.
    if on('swimming') and IsPedSwimming(ped) and not IsPedSwimmingUnderWater(ped) then
        return 'swimMetres', Config.Passive.swimming
    end

    if IsPedInAnyVehicle(ped, false) then
        if not on('cycling') then return nil end

        local cfg = Config.Passive.cycling
        local vehicle = GetVehiclePedIsIn(ped, false)
        if not vehicle or vehicle == 0 then return nil end

        -- The rider, not a passenger on the handlebars.
        if GetPedInVehicleSeat(vehicle, -1) ~= ped then return nil end

        -- Class 13 is Cycles. A motorbike shares almost every other test with a bicycle and is
        -- not exercise, so the class check is the whole guard.
        local class = GetVehicleClass(vehicle)
        local allowed = false
        for _, wanted in ipairs(cfg.vehicleClasses or { 13 }) do
            if class == wanted then allowed = true end
        end
        if not allowed then return nil end

        --[[
            PEDALLING, NOT COASTING. `GetIsTaskActive(ped, 306)` is the bicycle pedalling task,
            and without it a player who freewheels down from Chiliad earns the whole descent.

            It is a task id rather than a named native because there is no named native for it;
            306 is CTaskBicyclePedal. If a future build renumbers the tasks this test simply
            stops paying out, which is the safe direction to fail in.
        ]]
        if cfg.requirePedalling and not GetIsTaskActive(ped, 306) then return nil end

        return 'bikeMetres', cfg
    end

    if on('running') then
        local cfg = Config.Passive.running
        if cfg.requireSprint == false or IsPedSprinting(ped) then
            return 'runMetres', cfg
        end
    end

    return nil
end

CreateThread(function()
    if not Config.Passive.enabled then return end

    -- Nothing to do at all. End the thread rather than looping on four false flags forever.
    if not (on('running') or on('cycling') or on('swimming') or on('diving')) then return end

    local reportEvery = math.max(5, tonumber(Config.Passive.reportInterval) or 30)
    local sinceReport = 0

    while true do
        Wait(1000)

        if State.ready and not IsPauseMenuActive() then
            local ped = PlayerPedId()
            local now = GetGameTimer()

            if IsEntityDead(ped) then
                -- A death cancels an in-progress dive rather than crediting it, and breaks the
                -- distance chain so the respawn teleport is not measured as a sprint.
                diveStarted = nil
                lastCoords = nil

            else
                -- --- The three distance activities ---------------------------------------
                local field, cfg = currentDistanceActivity(ped)
                local coords = GetEntityCoords(ped)

                if field and lastCoords and lastAt > 0 then
                    local elapsed = (now - lastAt) / 1000.0

                    -- A gap longer than a few seconds means the loop was starved or the player
                    -- teleported. Either way the distance between the two points was not
                    -- covered under their own power, so it is discarded.
                    if elapsed > 0.0 and elapsed <= 3.0 then
                        local dx = coords.x - lastCoords.x
                        local dy = coords.y - lastCoords.y
                        local dz = coords.z - lastCoords.z
                        local moved = math.sqrt(dx * dx + dy * dy + dz * dz)
                        local speed = moved / elapsed

                        local minSpeed = tonumber(cfg.minSpeed) or 0.0
                        local maxSpeed = tonumber(cfg.maxSpeed) or 12.0

                        if speed >= minSpeed and speed <= maxSpeed then
                            pending[field] = (pending[field] or 0.0) + moved
                        end
                    end
                end

                -- The chain is kept across a switch of activity but broken when the player is
                -- doing none of them, so the walk between two sprints is not credited to either.
                if field then
                    lastCoords = coords
                    lastAt = now
                else
                    lastCoords = nil
                end

                -- --- Diving, measured in time -------------------------------------------
                if on('diving') then
                    local dive = Config.Passive.diving

                    if IsPedSwimmingUnderWater(ped) then
                        diveStarted = diveStarted or now
                    elseif diveStarted then
                        local seconds = (now - diveStarted) / 1000.0
                        diveStarted = nil

                        -- Only a real dive counts, and it only counts once the player surfaces.
                        -- The upper bound rejects a trainer or an infinite-breath script.
                        local floor = tonumber(dive.minDiveSeconds) or 8
                        local roof = tonumber(dive.maxDiveSeconds) or 600

                        if seconds >= floor and seconds <= roof then
                            pending.diveSeconds = pending.diveSeconds + seconds
                        end
                    end
                end
            end

            sinceReport = sinceReport + 1
            if sinceReport >= reportEvery then
                sinceReport = 0
                report()
            end
        end
    end
end)

--[[
    The payout toast, off by default. See Config.Passive.notify: a notification every thirty
    seconds while jogging is noise, but being able to switch it on is what makes the feature
    testable without reading the server console.
]]
RegisterNetEvent('vsport:client:PassiveGain', function(gains)
    if type(gains) ~= 'table' then return end
    if not Config.Passive.notify then return end

    local parts = {}
    for _, key in ipairs(Stats.keys()) do
        local amount = tonumber(gains[key])
        if amount and amount > 0 then
            local def = Stats.def(key)
            parts[#parts + 1] = L('notify.gained', amount, L(def.label))
        end
    end

    if #parts > 0 then
        Compat.notify(table.concat(parts, '   '), 'success')
    end
end)

--- Do not lose an unreported batch when the player disconnects or the resource stops. The
--- event still leaves the client in both cases; the server sanity-checks it like any other.
AddEventHandler('onResourceStop', function(resource)
    if resource ~= Sport.resource then return end
    report()
end)
