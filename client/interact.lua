--[[
    client/interact.lua

    Getting from "there is a bench there" to "a workout has started".

    Two routes, and the resource takes whichever the server has:

      TARGET   ox_target, qb-target or qtarget. Options are registered once at boot, one per
               exercise, against every model that offers it. The target resource owns the
               loop, so this file costs nothing after registration.

      PROMPT   The built-in one. A key hint above the prop, a marker on the floor, and a
               cycle key when a prop offers more than one exercise.

    THE DRAW LOOP ONLY EXISTS WHEN THERE IS SOMETHING TO DRAW. It is started by the detection
    tier changing and it ends itself the moment nothing is in range, rather than running at
    Wait(0) all session behind an `if`.
]]

Interact = {}

-- Which exercise is selected on a prop that offers several. Keyed by the equipment list
-- itself, so walking between two yoga mats keeps the choice and walking to a bench resets it.
local selectedIndex = 1
local selectedFor = nil

local drawLoopRunning = false

-- ---------------------------------------------------------------------------------------
-- Selection
-- ---------------------------------------------------------------------------------------

--- The exercise key currently chosen on `candidate`, and how many it offers.
local function selection(candidate)
    local keys = candidate.keys
    local count = #keys

    if selectedFor ~= keys then
        selectedFor = keys
        selectedIndex = 1
    end

    if selectedIndex > count then selectedIndex = 1 end
    return keys[selectedIndex], count
end

local function cycle(candidate)
    local count = #candidate.keys
    if count <= 1 then return end

    selectedIndex = selectedIndex + 1
    if selectedIndex > count then selectedIndex = 1 end
end

-- ---------------------------------------------------------------------------------------
-- The prompt text
-- ---------------------------------------------------------------------------------------

--- The label shown for `key`, translated when the catalogue named a locale key and used
--- verbatim when an operator wrote plain text in Config.ExtraEquipment.
local function labelFor(key, spot)
    if spot and spot.label then return Locale.text(spot.label) end

    local entry = Equipment.get(key)
    if not entry then return key end
    return Locale.text(entry.label or key)
end

local useKeyName, cycleKeyName

local function promptText(candidate)
    local key, count = selection(candidate)
    local label = labelFor(key, candidate.spot)

    if candidate.busy then
        return L('prompt.busy')
    end

    local left = State.cooldownLeft(key)
    if left > 0 then
        return L('prompt.cooldown', Sport.duration(left))
    end

    if count > 1 then
        return L('prompt.choose', useKeyName, label, cycleKeyName)
    end

    return L('prompt.key', useKeyName, label)
end

-- ---------------------------------------------------------------------------------------
-- The draw loop
-- ---------------------------------------------------------------------------------------

--[[
    Draw markers and the prompt, and take the key press.

    Started when detection reports something in range, and it ends itself when nothing is.
    That is why there is no `if nearby then ... end` wrapped around a permanent Wait(0): the
    thread simply does not exist most of the time.
]]
local function runDrawLoop()
    if drawLoopRunning then return end
    drawLoopRunning = true

    CreateThread(function()
        local markerDistance = math.min(
            tonumber(Config.Interaction.marker.distance) or 8.0,
            tonumber(Config.Performance.drawCutoff) or 15.0)
        local markerDistanceSquared = markerDistance * markerDistance
        local maxMarkers = math.max(1, math.floor(tonumber(Config.Performance.maxMarkers) or 6))

        local useKey = Config.Interaction.key or 38
        local cycleKey = Config.Interaction.cycleKey or 47
        local promptMode = Config.Interaction.prompt or 'help3d'

        -- Gated on the DRAW budget, not on the detection radius. Those are 6 m and 20 m, so this
        -- used to run at Wait(0) for the whole 14 m of walking towards a bench, drawing nothing.
        while Detect.nearestSquared() <= markerDistanceSquared do
            if not Session.active() then
                -- --- Markers ---------------------------------------------------------
                if Config.Interaction.marker.enabled then
                    local drawn = 0
                    for candidate in Detect.each() do
                        if drawn >= maxMarkers then break end
                        if candidate.distanceSquared <= markerDistanceSquared
                            and (candidate.spot == nil or candidate.spot.marker) then
                            UI.marker(candidate.coords)
                            drawn = drawn + 1
                        end
                    end
                end

                -- --- Prompt ----------------------------------------------------------
                -- With a target installed it owns every prop, so the built-in prompt speaks only
                -- for static spots. Without one it speaks for everything.
                local closest = Detect.closestVisible(Compat.usesTarget())

                if closest then
                    local text = promptText(closest)

                    if promptMode == 'help3d' or promptMode == 'both' then
                        UI.text3d(
                            vector3(closest.coords.x, closest.coords.y, closest.coords.z + 0.75),
                            text, { scale = 0.32 })
                    end
                    if promptMode == 'help' or promptMode == 'both' then
                        UI.help(text)
                    end

                    -- Only inside the real use distance does the key do anything, so a
                    -- player reading a prompt from six metres away cannot start a workout
                    -- across the room.
                    local useDistanceSquared = (Config.General.useDistance or 2.5) ^ 2

                    if closest.distanceSquared <= useDistanceSquared then
                        if #closest.keys > 1 and IsControlJustReleased(0, cycleKey) then
                            cycle(closest)
                        end

                        if IsControlJustReleased(0, useKey) and not closest.busy then
                            local key = selection(closest)
                            Session.start(closest, key)
                        end
                    end
                end
            end

            Wait(0)
        end

        drawLoopRunning = false
    end)
end

--[[
    Watch for the detection tier changing.

    A slow loop whose only job is to start the fast one. `nearbyTick` is the same cadence the
    detection loop runs at, so the prompt appears within one tick of the bench coming into
    range and never sooner than the data exists.
]]
CreateThread(function()
    -- The glyph strings need the game to have booted; asking too early returns nothing.
    Wait(2000)
    useKeyName = UI.keyLabel(Config.Interaction.key or 38, 'E')
    cycleKeyName = UI.keyLabel(Config.Interaction.cycleKey or 47, 'G')

    if Compat.usesTarget() then
        --[[
            The target resource owns the interaction for PROPS - a prompt of our own would duplicate
            it. Two things it cannot own, so the loop still has to run for them:

              markers, when the operator explicitly asked for them
              Config.Spots, which are COORDINATES and have no entity for a target to attach to

            Spots were the bug. config.lua promises "Static spots keep the built-in key prompt even
            on a server that uses ox_target or qb-target, because a target has nothing to attach
            to" - and this return made that false on every target server, so any equipment baked
            into an MLO was unreachable. The documentation was right about the design and the code
            never implemented it.
        ]]
        if not Config.Interaction.marker.enabled and #(Config.Spots or {}) == 0 then return end
    end

    local watchBudget = math.min(
        tonumber(Config.Interaction.marker.distance) or 8.0,
        tonumber(Config.Performance.drawCutoff) or 15.0)
    local watchBudgetSquared = watchBudget * watchBudget

    local tick = math.max(50, tonumber(Config.Performance.nearbyTick) or 250)

    while true do
        -- Same budget as the loop's own condition, or the watcher would start a thread that
        -- immediately exits and start it again on the next tick, forever.
        if not drawLoopRunning and Detect.nearestSquared() <= watchBudgetSquared then
            runDrawLoop()
        end
        Wait(tick)
    end
end)

-- ---------------------------------------------------------------------------------------
-- Target registration
-- ---------------------------------------------------------------------------------------
--
-- One option per exercise, registered against every model that offers it. Registered once at
-- boot; after that the target resource does all the work and nothing in this file runs.

local registeredModels = {}
local registeredNames = {}

local function registerTargets()
    if not Compat.usesTarget() then return end

    for _, key in ipairs(Equipment.keys) do
        local entry = Equipment.get(key)
        if entry and type(entry.models) == 'table' and #entry.models > 0 then
            local models = {}
            for _, model in ipairs(entry.models) do
                models[#models + 1] = model
                registeredModels[model] = true
            end

            registeredNames[#registeredNames + 1] = 'vsport:' .. key

            Compat.addTargetModels(models, {
                key = key,
                label = Locale.text(entry.label or key),

                onSelect = function(entity)
                    --[[
                        The target hands back the entity, not a detection candidate, so one is
                        built here. Its coords are the prop's, which is what everything
                        downstream needs.

                        `model` WAS MISSING FROM THIS TABLE, and it is the field that decides which
                        prop the body is placed against. Without it Equipment.staging returns the
                        entry's own numbers and applies no modelOverrides at all - so on a server
                        with a target, which is most of them, NONE of the per-model placement in
                        this resource had ever been used. Every incline bench got the flat bench's
                        offset and laid a body out in mid-air beside it.

                        It was invisible from every angle we looked: the alignment tool passes its
                        own hash so it was always right, and the built-in key prompt passes a real
                        detection candidate so it was always right too. Only the target path was
                        wrong, and only in a way that looked like bad measurements.
                    ]]
                    local coords = entity and DoesEntityExist(entity)
                        and GetEntityCoords(entity)
                        or GetEntityCoords(PlayerPedId())

                    Session.start({
                        entity = entity,
                        model = entity and DoesEntityExist(entity)
                            and GetEntityModel(entity) or nil,
                        coords = coords,
                        keys = { key },
                        spot = nil,
                        busy = Session.isOccupied(coords, 1.4),
                        distanceSquared = 0.0,
                    }, key)
                end,

                canInteract = function(entity, distance)
                    if Session.active() then return false end
                    if State.blocked then return false end
                    if State.cooldownLeft(key) > 0 then return false end

                    local coords = entity and DoesEntityExist(entity)
                        and GetEntityCoords(entity) or nil
                    if coords and Session.isOccupied(coords, 1.4) then return false end

                    return true
                end,
            })
        end
    end

    Sport.debug('registered', #registeredNames, 'target options on',
        Sport.count(registeredModels), 'models')
end

--[[
    Static spots have no prop, so a target resource has nothing to attach to. They keep the
    built-in prompt even on a server that uses a target, which is why the draw loop above
    stays alive for them.
]]
CreateThread(function()
    -- Give the target resource time to start. Registering against a resource that has not
    -- booted silently does nothing on every one of them.
    Wait(3000)
    registerTargets()
end)

AddEventHandler('onResourceStop', function(resource)
    if resource ~= Sport.resource then return end
    if #registeredNames == 0 then return end

    local models = {}
    for model in pairs(registeredModels) do models[#models + 1] = model end
    Compat.removeTargetModels(models, registeredNames)
end)
