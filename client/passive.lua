--[[
    client/passive.lua

    Training that happens without a prop: sprinting builds stamina, holding your breath
    underwater builds lung capacity.

    Both are deliberately small. They exist so that a long swim or a run across the city is
    not worth literally nothing, not as a substitute for the gym - the numbers in
    Config.Passive are set so that a marathon is worth about three sessions.

    ---------------------------------------------------------------------------------------
    WHAT THIS COSTS
    ---------------------------------------------------------------------------------------

    One loop at one second, and it returns immediately unless the player is actually
    sprinting or actually underwater. When both features are switched off in the config, the
    thread ends at the first line and never runs again.

    Progress is accumulated locally and reported in a batch every `reportInterval` seconds.
    One event every thirty seconds per active player, carrying two numbers, instead of an
    event per metre.
]]

Passive = {}

local pendingDistance = 0.0     -- metres sprinted since the last report
local pendingDiveSeconds = 0.0  -- seconds underwater in completed dives since the last report

local diveStarted = nil         -- game timer when the current dive began
local lastCoords = nil
local lastAt = 0

--- Send whatever has accumulated, and reset. Nothing is sent when there is nothing to say,
--- which is the usual case.
local function report()
    local distance = pendingDistance
    local dive = pendingDiveSeconds

    if distance < 1.0 and dive < 1.0 then return end

    pendingDistance = 0.0
    pendingDiveSeconds = 0.0

    TriggerServerEvent('vsport:server:Passive', {
        metres = Sport.round(distance, 1),
        diveSeconds = Sport.round(dive, 1),
    })

    Sport.debug(('passive report: %.0fm sprinted, %.0fs underwater'):format(distance, dive))
end

CreateThread(function()
    local running = Config.Passive.running
    local diving = Config.Passive.diving

    local trackRunning = running and running.enabled
    local trackDiving = diving and diving.enabled

    -- Nothing to do at all. End the thread rather than looping on two false flags forever.
    if not trackRunning and not trackDiving then return end

    local minSpeed = tonumber(running and running.minSpeed) or 4.0
    local minDive = tonumber(diving and diving.minDiveSeconds) or 8
    local reportEvery = math.max(5, tonumber(Config.Passive.reportInterval) or 30)

    local sinceReport = 0

    while true do
        Wait(1000)

        if State.ready and not IsPauseMenuActive() then
            local ped = PlayerPedId()
            local now = GetGameTimer()

            if IsEntityDead(ped) then
                -- A death cancels an in-progress dive rather than crediting it.
                diveStarted = nil
                lastCoords = nil

            else
                -- --- Sprinting ----------------------------------------------------------
                if trackRunning and not IsPedInAnyVehicle(ped, false) then
                    local coords = GetEntityCoords(ped)

                    if lastCoords and lastAt > 0 then
                        local elapsed = (now - lastAt) / 1000.0

                        -- A gap longer than a few seconds means the loop was starved or the
                        -- player teleported. Either way the distance between the two points
                        -- was not run, so it is discarded.
                        if elapsed > 0.0 and elapsed <= 3.0 then
                            local dx = coords.x - lastCoords.x
                            local dy = coords.y - lastCoords.y
                            local dz = coords.z - lastCoords.z
                            local moved = math.sqrt(dx * dx + dy * dy + dz * dz)
                            local speed = moved / elapsed

                            -- Sprinting, at a plausible speed, on foot. The upper bound is
                            -- what rejects a teleport or a ride in something the vehicle
                            -- check missed.
                            if IsPedSprinting(ped) and speed >= minSpeed and speed <= 12.0 then
                                pendingDistance = pendingDistance + moved
                            end
                        end
                    end

                    lastCoords = coords
                    lastAt = now
                else
                    lastCoords = nil
                end

                -- --- Diving -------------------------------------------------------------
                if trackDiving then
                    if IsPedSwimmingUnderWater(ped) then
                        diveStarted = diveStarted or now
                    elseif diveStarted then
                        local seconds = (now - diveStarted) / 1000.0
                        diveStarted = nil

                        -- Bobbing under a wave repeatedly earns nothing; only a real dive
                        -- counts, and it only counts once the player surfaces.
                        if seconds >= minDive then
                            pendingDiveSeconds = pendingDiveSeconds + seconds
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

--- Do not lose an unreported batch when the player disconnects or the resource stops. The
--- event still leaves the client in both cases; the server sanity-checks it like any other.
AddEventHandler('onResourceStop', function(resource)
    if resource ~= Sport.resource then return end
    report()
end)
