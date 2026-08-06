--[[
    client/detect.lua

    Finding sport equipment in the world.

    ---------------------------------------------------------------------------------------
    HOW, AND WHAT IT COSTS
    ---------------------------------------------------------------------------------------

    `GetGamePool('CObject')` hands back every object the client has streamed in - in a dense
    interior that can be a few thousand handles. Walking it is the expensive part, so the
    whole design is about walking it as rarely as possible:

      * The loop sleeps for `idleTick` (1s) when there was nothing nearby last time, and
        `nearbyTick` (250ms) when there was. Standing in the street is the cheap case and it
        is the case almost everybody is in almost always.

      * A player who has not moved `idleDistance` metres since the last scan gets the previous
        result handed back with no scan at all. Standing at a bench is free.

      * Distances are compared SQUARED. A square root per object per scan, several hundred
        objects, four scans a second, is real arithmetic for no information: the ordering of
        squared distances is the ordering of distances.

      * The object loop breaks at `maxObjects`. A pathological interior costs a bounded
        amount rather than a frame spike.

      * The result table is rebuilt into a REUSED table rather than allocated fresh. Four
        allocations a second of a table that lives 250ms is exactly the kind of garbage that
        turns into a stutter an hour later.

    None of this matters on its own. All of it together is why the resource does not show up
    in a profiler.
]]

Detect = {}

-- The current result. Reused between scans; never handed out by reference.
local nearby = {}
local nearbyCount = 0

local lastScanCoords = vector3(0.0, 0.0, 0.0)
local lastScanAt = 0
local haveScanned = false

-- The static spots from Config.Spots, resolved once at boot into a flat list with their
-- equipment entry already looked up.
local spots = {}

-- ---------------------------------------------------------------------------------------
-- Spots
-- ---------------------------------------------------------------------------------------

local function buildSpots()
    spots = {}

    for index, raw in ipairs(Config.Spots or {}) do
        local entry = Equipment.get(raw.equipment)

        if not entry then
            Sport.warn(("Config.Spots[%d] names unknown equipment '%s'")
                :format(index, tostring(raw.equipment)))
        elseif type(raw.coords) ~= 'vector3' and type(raw.coords) ~= 'table' then
            Sport.warn(("Config.Spots[%d] has no usable coords"):format(index))
        else
            spots[#spots + 1] = {
                key = raw.equipment,
                entry = entry,
                coords = raw.coords,
                heading = tonumber(raw.heading),
                radius = tonumber(raw.radius) or Config.General.useDistance,
                label = raw.label,
                marker = raw.marker ~= false,
                job = raw.job,
                index = index,
            }
        end
    end

    Sport.debug('static spots:', #spots)
end

--- Blips for the static spots. Created once; there is no update path because a spot cannot
--- move.
local function buildBlips()
    local cfg = Config.Interaction.blips
    if not cfg.enabled then return end

    for _, spot in ipairs(spots) do
        local blip = AddBlipForCoord(spot.coords.x, spot.coords.y, spot.coords.z)
        SetBlipSprite(blip, cfg.sprite or 311)
        SetBlipColour(blip, cfg.colour or 2)
        SetBlipScale(blip, cfg.scale or 0.7)
        SetBlipAsShortRange(blip, cfg.shortRange ~= false)
        BeginTextCommandSetBlipName('STRING')
        AddTextComponentSubstringPlayerName(
            Locale.text(spot.label or spot.entry.label or spot.key))
        EndTextCommandSetBlipName(blip)
    end
end

-- ---------------------------------------------------------------------------------------
-- The scan
-- ---------------------------------------------------------------------------------------

--[[
    Whether somebody else is already training here.

    Answered from the list the SERVER publishes of where every active session is, rather than
    from an entity state bag. Map props are not networked entities and mostly have no net ID,
    so there is nothing to hang a state bag on; the server knows where every session is
    anyway, because it authorised each one.

    This is only ever used to grey out a prompt. The refusal that matters happens server-side
    when the session is requested.
]]
local function inUseByAnother(coords)
    if not Config.General.exclusiveEquipment then return false end
    return Session.isOccupied(coords, 1.4)
end

--[[
    Rebuild `nearby` from the object pool.

    Returns how many entries were written. The table keeps its old entries past that count,
    which is the point of reusing it - `nearbyCount` is the length, `#nearby` is not.
]]
local function scan(playerCoords)
    local cfg = Config.Detection
    local radius = tonumber(cfg.radius) or 20.0
    local radiusSquared = radius * radius
    local limit = math.floor(tonumber(cfg.maxObjects) or 400)
    local count = 0

    local pool = GetGamePool('CObject')

    --[[
        THE WHOLE POOL IS WALKED. This used to stop after `maxObjects` POOL ENTRIES, on the
        assumption - written down as a comment, never checked - that the pool comes back roughly
        nearest-first. IT DOES NOT. The order is arbitrary.

        The symptom was ugly and hard to attribute: on a map with 718 objects streamed in,
        /vsportinfo reported "0 in range" while /vsportscan, which has no such limit, listed a
        usable bench two metres away. Equipment simply became invisible past whatever index the
        engine happened to put it at.

        Walking all of it is cheap because of the order of the two filters: GetEntityModel plus
        one hash lookup runs for every object, and that is a few hundred nanoseconds each;
        GetEntityCoords, which actually costs something, runs only for the handful that are sport
        equipment. Seven hundred objects is not a measurable amount of work.

        `maxObjects` now caps RESULTS instead, which is what a limit should protect: a gym with a
        hundred dumbbells on the floor produces a bounded list, and no equipment ever disappears
        because of where it sits in a pool.
    ]]
    for index = 1, #pool do
        if count >= limit then
            Sport.debug('detection hit the result cap of', limit)
            break
        end

        local entity = pool[index]
        local model = GetEntityModel(entity)
        local holders = Equipment.byModel[model]

        -- The overwhelmingly common case: an object that is not sport equipment. One table
        -- lookup and on to the next.
        if holders then
            local coords = GetEntityCoords(entity)
            local dx, dy, dz = coords.x - playerCoords.x, coords.y - playerCoords.y, coords.z - playerCoords.z
            local distanceSquared = dx * dx + dy * dy + dz * dz

            if distanceSquared <= radiusSquared then
                count = count + 1

                local slot = nearby[count]
                if not slot then
                    slot = {}
                    nearby[count] = slot
                end

                slot.entity = entity
                slot.model = model
                slot.coords = coords
                slot.keys = holders
                slot.distanceSquared = distanceSquared
                slot.spot = nil
                slot.busy = inUseByAnother(coords)
            end
        end
    end

    -- Static spots. Appended to the same list so every consumer sees one kind of thing.
    for _, spot in ipairs(spots) do
        local dx = spot.coords.x - playerCoords.x
        local dy = spot.coords.y - playerCoords.y
        local dz = spot.coords.z - playerCoords.z
        local distanceSquared = dx * dx + dy * dy + dz * dz

        if distanceSquared <= radiusSquared then
            count = count + 1

            local slot = nearby[count]
            if not slot then
                slot = {}
                nearby[count] = slot
            end

            slot.entity = nil
            slot.model = nil
            slot.coords = spot.coords
            slot.keys = { spot.key }
            slot.distanceSquared = distanceSquared
            slot.spot = spot
            slot.busy = inUseByAnother(spot.coords)
        end
    end

    nearbyCount = count
    return count
end

-- ---------------------------------------------------------------------------------------
-- Public
-- ---------------------------------------------------------------------------------------

--- How many pieces of equipment are in range.
function Detect.count()
    return nearbyCount
end

--- Iterate the current result. A plain closure rather than a copied table: this is called
--- from draw loops and must not allocate.
function Detect.each()
    local index = 0
    return function()
        index = index + 1
        if index > nearbyCount then return nil end
        return nearby[index]
    end
end

--[[
    The nearest usable piece of equipment, or nil.

    "Usable" excludes anything another player is on and anything beyond `useDistance`. The
    result is a reference into the reused table, so a caller must not hold it across a frame.
]]
function Detect.closest(maxDistance)
    local limit = tonumber(maxDistance) or Config.General.useDistance
    local limitSquared = limit * limit

    local best, bestDistance = nil, math.huge

    for index = 1, nearbyCount do
        local candidate = nearby[index]
        if not candidate.busy and candidate.distanceSquared <= limitSquared
            and candidate.distanceSquared < bestDistance then
            best, bestDistance = candidate, candidate.distanceSquared
        end
    end

    return best
end

--[[
    The camera's forward vector. No native returns it, and the sign convention is easy to get
    wrong: GTA's yaw is measured anticlockwise from north, which is where the negated sine comes
    from. Same maths as client/custom.lua's, kept local because a shared file that touches a
    camera native would break on the server.
]]
local function camForward()
    local rotation = GetGameplayCamRot(2)
    local pitch = math.rad(rotation.x)
    local yaw = math.rad(rotation.z)
    local flat = math.abs(math.cos(pitch))

    return -math.sin(yaw) * flat, math.cos(yaw) * flat, math.sin(pitch)
end

--[[
    The piece of equipment the player is LOOKING AT, or the nearest one when they are not looking
    at any of it. Whether usable or not, so the prompt can say "someone is already using this"
    rather than nothing.

    THIS USED TO IGNORE AIM ENTIRELY, and the function name said otherwise for months. It returned
    the nearest candidate within 8 metres, full stop - so standing in a gym in front of a machine
    that this resource does not know, with a bench four metres behind you, the prompt offered the
    bench press. Pressing E then lay the player down at the bench, off screen, which reads exactly
    like "my character does a bench press in mid-air".

    Muscle Beach is the worst case for it: a dozen pieces of equipment inside eight metres of each
    other, most of which the catalogue knows, and one prompt that could be about any of them.

    So aim decides, and distance only breaks ties. The dot product of the camera's forward vector
    against the direction to each candidate is the whole test: 1.0 is dead ahead, 0.0 is straight
    out to the side. Candidates outside `Config.Interaction.aimCone` are not eligible at all unless
    nothing is, in which case the nearest wins and the old behaviour is what you get.
]]
--[[
    How far the nearest candidate is, squared, or math.huge.

    Exists so the per-frame draw loop can gate itself on the DRAW budget rather than on the detection
    radius. Those are 6 m and 20 m: the loop used to run at Wait(0) from the moment anything was
    detected, so walking within 20 m of a bench started a per-frame thread that drew nothing for the
    next 14 m of approach.
]]
function Detect.nearestSquared()
    local nearest = math.huge
    for index = 1, nearbyCount do
        if nearby[index].distanceSquared < nearest then
            nearest = nearby[index].distanceSquared
        end
    end
    return nearest
end

--- `spotsOnly` restricts the answer to Config.Spots entries. A target resource owns every PROP, so
--- with one installed the built-in prompt must only speak for coordinates, which a target cannot
--- attach to - otherwise both offer the same bench and the player sees two prompts.
function Detect.closestVisible(spotsOnly)
    local limit = math.min(
        tonumber(Config.Interaction.marker.distance) or 8.0,
        tonumber(Config.Performance.drawCutoff) or 15.0)
    local limitSquared = limit * limit

    local cone = tonumber(Config.Interaction.aimCone) or 0.55
    local from = GetGameplayCamCoord()
    local fx, fy, fz = camForward()

    local aimed, aimedScore = nil, cone
    local nearest, nearestDistance = nil, math.huge

    for index = 1, nearbyCount do
        local candidate = nearby[index]

        if candidate.distanceSquared <= limitSquared
            and (not spotsOnly or candidate.spot ~= nil) then

            if candidate.distanceSquared < nearestDistance then
                nearest, nearestDistance = candidate, candidate.distanceSquared
            end

            -- Aim, measured from the camera rather than from the ped: the prompt is about what is
            -- on screen, and in third person those two are a couple of metres apart.
            local dx = candidate.coords.x - from.x
            local dy = candidate.coords.y - from.y
            local dz = candidate.coords.z - from.z
            local length = math.sqrt(dx * dx + dy * dy + dz * dz)

            if length > 0.01 then
                local score = (dx * fx + dy * fy + dz * fz) / length
                if score > aimedScore then
                    aimed, aimedScore = candidate, score
                end
            end
        end
    end

    return aimed or nearest
end

--- Force the next tick to scan rather than reuse. Called when a session ends, because the
--- prop's busy flag just changed and the player has probably not moved.
function Detect.invalidate()
    haveScanned = false
end

-- ---------------------------------------------------------------------------------------
-- The loop
-- ---------------------------------------------------------------------------------------

CreateThread(function()
    buildSpots()
    buildBlips()

    if not Config.Detection.enabled then
        Sport.debug('detection disabled by config')
        return
    end

    local idleTick = math.max(100, tonumber(Config.Performance.idleTick) or 1000)
    local nearbyTick = math.max(50, tonumber(Config.Performance.nearbyTick) or 250)
    local interval = math.max(100, tonumber(Config.Detection.interval) or 750)
    local idleDistanceSquared = (tonumber(Config.Detection.idleDistance) or 1.5) ^ 2

    while true do
        local wait = idleTick
        local ped = PlayerPedId()

        local skip = false

        if Config.Performance.pauseWhenGamePaused and IsPauseMenuActive() then
            skip = true
        elseif Config.Performance.pauseWhenDead and IsEntityDead(ped) then
            skip = true
        elseif Config.Detection.skipInVehicle and IsPedInAnyVehicle(ped, false) then
            skip = true
        elseif Config.Detection.skipWhenBusy and Session.active() then
            skip = true
        end

        if skip then
            -- Everything found last time is stale the moment the player is in a car, and
            -- leaving it populated would let a prompt draw through a windscreen.
            nearbyCount = 0
            haveScanned = false
        else
            local coords = GetEntityCoords(ped)
            local now = GetGameTimer()

            local moved = true
            if haveScanned then
                local dx, dy, dz = coords.x - lastScanCoords.x, coords.y - lastScanCoords.y,
                    coords.z - lastScanCoords.z
                moved = (dx * dx + dy * dy + dz * dz) > idleDistanceSquared
            end

            -- Rescan when the player moved, or when the last scan is older than the
            -- configured interval. The second condition is what notices somebody else
            -- finishing on the bench you are standing at.
            if moved or (now - lastScanAt) >= interval then
                scan(coords)
                lastScanCoords = coords
                lastScanAt = now
                haveScanned = true
            end

            wait = nearbyCount > 0 and nearbyTick or idleTick
        end

        Wait(wait)
    end
end)

-- ---------------------------------------------------------------------------------------
-- Debug drawing
-- ---------------------------------------------------------------------------------------
--
-- Off unless Config.Debug.drawDetected. The thread exits immediately when it is off rather
-- than looping on a flag, so leaving the option in the file costs nothing.

CreateThread(function()
    if not Config.Debug.drawDetected and not Config.Debug.drawSpots then return end

    while true do
        if Config.Debug.drawDetected then
            for candidate in Detect.each() do
                local distance = math.sqrt(candidate.distanceSquared)
                local label = table.concat(candidate.keys, ', ')

                UI.text3d(
                    vector3(candidate.coords.x, candidate.coords.y, candidate.coords.z + 0.6),
                    ('%s  %.1fm%s'):format(label, distance, candidate.busy and '  [BUSY]' or ''),
                    { scale = 0.28 }
                )
            end
        end

        if Config.Debug.drawSpots then
            for _, spot in ipairs(spots) do
                DrawMarker(28, spot.coords.x, spot.coords.y, spot.coords.z,
                    0.0, 0.0, 0.0, 0.0, 0.0, 0.0,
                    spot.radius, spot.radius, spot.radius,
                    255, 120, 0, 70, false, false, 2, false, nil, nil, false)
            end
        end

        Wait(0)
    end
end)
