--[[
    client/tune.lua

    THE LIVE ALIGNMENT TOOL. `/vsportprop <equipment>`

    ---------------------------------------------------------------------------------------
    WHY THIS EXISTS
    ---------------------------------------------------------------------------------------

    Placing a body on a bench and a barbell in its hands comes down to six numbers - three for
    the animation offset, one for its heading, and a position and rotation for the prop - and
    NONE OF THEM CAN BE DERIVED. Prop origins are not consistent between models, animation clips
    are authored against scenario points nobody publishes, and the only way to know a number is
    right is to look at it.

    Guessing them from outside the game costs one restart per attempt and gets it wrong. So this
    plays the real animation with the real prop, live, and lets the numbers be nudged with the
    arrow keys until it looks right. Then it prints the exact block to paste.

    It is a developer tool: restricted to admins by Config.Commands.restrictDevCommands, and it
    starts no session, awards nothing and touches no stat.
]]

Tune = {}

local active = false

-- Controls. Deliberately not from Config.Minigame.keyPool: this runs outside a session and
-- should not change when somebody re-binds the QTE.
local KEY = {
    up      = 172,      -- arrow up
    down    = 173,      -- arrow down
    left    = 174,      -- arrow left
    right   = 175,      -- arrow right
    raise   = 38,       -- E
    lower   = 44,       -- Q on QWERTY, A on AZERTY
    turnCcw = 45,       -- R
    turnCw  = 23,       -- F
    quarter = 47,       -- G: a quarter turn, instantly
    axis    = 20,       -- Z on QWERTY, W on AZERTY: which axis R/F turns
    straight= 74,       -- H: snap every angle to the nearest 90
    --[[
        HOW THE PROP IS HELD. Cycles one hand / centred / two-handed.

        TAB, not X. Control 73 is INPUT_VEH_DUCK, and the physical X key it sits on ALSO drives
        the engine's own "cancel this ambient animation" behaviour - below the control layer,
        where DisableControlAction cannot reach it. Pressing it ended the animation and dropped
        out of the tool, which is not something a tuning key should be able to do.
    ]]
    hold    = 37,       -- TAB
    reset   = 26,       -- C: zero whatever is being edited
    mode    = 22,       -- SPACE
    faster  = 21,       -- SHIFT, held
    print   = 191,      -- ENTER
    --[[
        SAVE IT LIVE, to data/custom.json, for every player, without a restart.

        K rather than something next to ENTER, on purpose: this key changes what the whole server
        sees, so it should not be a neighbour of the one that only prints to a console. Nothing
        else in the tool uses it, and it is 311 on both layouts.
    ]]
    save    = 311,      -- K
    quit    = 177,      -- BACKSPACE

    --[[
        THE REVIEW KEYS, used by /vsporttour and inert outside it.

        ALL FOUR ARE NUMBER KEYS, and the first version was not. `next` was 249 - which is
        INPUT_PUSH_TO_TALK, the voice key - and `prev` was 29, the secondary special ability. The
        result was a tour that stepped through all 43 pairs on its own and reported "43 not judged"
        before the operator could look at any of them: something was firing the voice control, and
        every firing advanced the review.

        1, 2, 3, 4 sit in one row under one hand, are bound to weapon selection which is meaningless
        here and blocked anyway, and nothing else in the game holds them down.
    ]]
    good    = 157,      -- 1: this one looks right
    bad     = 158,      -- 2: this one does not
    next    = 159,      -- 3: next, no verdict
    prev    = 160,      -- 4: back
}

-- Which axis R/F turns, in 'prop' mode. Rotating only about Z is not enough to straighten a
-- barbell: getting a long object to sit level in a hand needs pitch and roll too.
local AXES = { 'x', 'y', 'z' }

local CONTROLS_TO_BLOCK = {
    KEY.up, KEY.down, KEY.left, KEY.right, KEY.raise, KEY.lower,
    KEY.turnCcw, KEY.turnCw, KEY.quarter, KEY.axis, KEY.straight, KEY.hold, KEY.reset,
    KEY.mode, KEY.print, KEY.save, KEY.quit,
    KEY.good, KEY.bad, KEY.next, KEY.prev,
    24, 25, 30, 31, 32, 33, 34, 35, 36,
    -- The look axes and the wheel. Disabled so they drive the tool's camera instead of the
    -- character's aim, and read back with GetDisabledControlNormal.
    1, 2, 241, 242,
    -- 73 is INPUT_VEH_DUCK. Blocked but never USED: the engine cancels ambient animations on
    -- the key behind it regardless, so it is unusable as a binding and only worth suppressing.
    73,
}

-- How the prop is held. Cycled with TAB.
local HOLDS = { 'hand', 'centred', 'twoHanded' }

--[[
    HOLD TO REPEAT.

    `IsDisabledControlJustPressed` fires once per physical press, so moving something twenty
    centimetres meant twenty presses and turning a body ninety degrees meant thirty-six. That is
    not a tool, it is a punishment.

    So: fire immediately on press, pause briefly so a single tap stays a single step, then repeat
    quickly while the key is held.
]]
--[[
    The bones a prop can hang off.

    Only a handful are useful and these are the well-known ones. PH_ bones are the "prop hand"
    bones the game itself attaches held objects to, and they are almost always the right answer;
    the other two are here for a mat under the body or something worn on the head.
]]
local BONES = {
    { id = 57005, label = 'right hand' },
    { id = 36029, label = 'left hand' },
    { id = 24818, label = 'spine' },
    { id = 31086, label = 'head' },
}

--[[
    HOLD TO REPEAT, AND ACCELERATE WHILE HELD.

    Two attempts got this wrong in opposite directions, which is what one fixed step size does.

    The first fired once per physical press: twenty centimetres meant twenty presses and a
    quarter turn meant thirty-six. The step was then raised to cover that, and holding a key
    swung the body a hundred degrees a second - far too coarse to land on anything.

    ONE STEP SIZE CANNOT DO BOTH JOBS. So the step ACCELERATES: a tap is always the smallest
    possible increment, and it ramps to six times that over the first second and a half of
    holding. Tap for precision, hold to sweep, and no mode to switch between.

    Returns whether to act, and the factor to scale the step by.
]]
local repeats = {}

local RAMP_MS = 1500        -- how long holding takes to reach full speed
local RAMP_MAX = 6.0        -- the multiplier once it is there

local function held(control, id)
    if not IsDisabledControlPressed(0, control) then
        repeats[id] = nil
        return false, 1.0
    end

    local now = GetGameTimer()
    local state = repeats[id]

    if not state then
        -- First frame of the press. Act now at the base step, and not again until the delay is
        -- up, so a tap is exactly one smallest increment.
        repeats[id] = { next = now + 280, since = now }
        return true, 1.0
    end

    if now >= state.next then
        state.next = now + 45

        local ramp = math.min((now - state.since) / RAMP_MS, 1.0)
        return true, 1.0 + ramp * (RAMP_MAX - 1.0)
    end

    return false, 1.0
end

-- ---------------------------------------------------------------------------------------
-- Finding the prop
-- ---------------------------------------------------------------------------------------

--[[
    The nearest prop that `key` knows how to use, with its model hash. Nil when there is none.

    `onlyModel` narrows it to one model name. That is what makes going through an exercise's props
    ONE BY ONE possible: an entry like bench_press covers six bench models, and without a filter
    the tool always picks whichever happens to be closest - so five of them can never be reached
    while standing in a gym that has all six.
]]
--[[
    The entity the player is looking at, whatever pool it lives in.

    THIS IS HOW A MAP-EMBEDDED PROP IS REACHED, and it is the difference between the tuner working on
    a gym and refusing to. GetGamePool('CObject') lists spawned objects; a prop that is part of the
    map or of an MLO is not in it. So:

      * Detect never sees it, so /vsportscan says "not in the list"
      * nearestPropFor never sees it, so the tuner falls through to a studio copy
      * but a TARGET resource hits it with its own raycast, so the exercise is offered on it anyway

    Every one of those was reported as a separate mystery. A raycast sees what the target sees.
]]
local function aimedEntity()
    local ped = PlayerPedId()
    local from = GetGameplayCamCoord()
    local rotation = GetGameplayCamRot(2)
    local pitch, yaw = math.rad(rotation.x), math.rad(rotation.z)
    local flat = math.abs(math.cos(pitch))

    local reach = 14.0
    local to = vector3(
        from.x - math.sin(yaw) * flat * reach,
        from.y + math.cos(yaw) * flat * reach,
        from.z + math.sin(pitch) * reach)

    --[[
        OBJECTS ONLY - FLAG 16, NOT 17.

        The first version used 17, adding flag 1 for map geometry, on the reasoning that a
        map-embedded bench needs it. It crashed the game: a map hit returns a handle that is not a
        usable entity, and GetEntityModel on it throws inside gta-streaming-five.dll rather than
        returning nil. There is nothing to be gained anyway - map geometry has no entity to attach a
        ped to, so even a successful hit would be useless here.

        What flag 16 does buy is real: it finds an object the player is LOOKING at, which beats the
        nearest one when several are in reach, and it does not care whether the object is where the
        pool walk expects.
    ]]
    local ray = StartShapeTestLosProbe(from.x, from.y, from.z, to.x, to.y, to.z, 16, ped, 4)

    local status, hit, _, _, entity = GetShapeTestResult(ray)
    local tries = 0
    while status == 1 and tries < 20 do
        Wait(0)
        tries = tries + 1
        status, hit, _, _, entity = GetShapeTestResult(ray)
    end

    if hit ~= 1 or not entity or entity == 0 or not DoesEntityExist(entity) then
        return nil
    end

    -- And read the model behind a pcall regardless. A shape test can hand back a handle that
    -- satisfies DoesEntityExist and still is not something the model natives accept; the crash was
    -- the proof, and one guarded read costs nothing next to taking the client down.
    local ok, model = pcall(GetEntityModel, entity)
    if not ok or type(model) ~= 'number' or model == 0 then return nil end

    return entity, model
end

--[[
    THE NEAREST OBJECT, OF ANY MODEL AT ALL. `/vsportprop <exercise> here`.

    Every other way of finding a prop filters by model first, and every one of them failed on one
    real bench at Muscle Beach: the pool walk did not list it, a shape test did not return it, the
    known-locations search did not find it, and remembering what the last session used did not help
    either. Meanwhile a target resource trained on it happily. Four mechanisms, four failures, and no
    explanation - so this one asks a question that cannot fail instead.

    No model filter, no search, no teleport, no studio copy. Whatever object is in front of you gets
    used, and the tool tells you which model it turned out to be so the printed block is keyed on the
    right name. If the answer is a model you did not expect, that is the bug found.
]]
local function nearestAnything()
    local aimed, aimedModel = aimedEntity()
    if aimed and aimedModel then return aimed, aimedModel, 0.0 end

    local coords = GetEntityCoords(PlayerPedId())
    local best, bestDistance, bestModel = nil, 100.0, nil       -- 10m, squared

    for _, entity in ipairs(GetGamePool('CObject')) do
        local at = GetEntityCoords(entity)
        local dx, dy, dz = at.x - coords.x, at.y - coords.y, at.z - coords.z
        local distanceSquared = dx * dx + dy * dy + dz * dz

        if distanceSquared < bestDistance then
            local ok, model = pcall(GetEntityModel, entity)
            if ok and type(model) == 'number' and model ~= 0 then
                best, bestDistance, bestModel = entity, distanceSquared, model
            end
        end
    end

    if not best then return nil end
    return best, bestModel, math.sqrt(bestDistance)
end

local function nearestPropFor(key, onlyModel)
    local entry = Equipment.get(key)
    if not entry then return nil end

    local wanted = {}

    if onlyModel then
        local hash = GetHashKey(onlyModel)
        if hash and hash ~= 0 then wanted[hash] = true end
    else
        for _, model in ipairs(entry.models or {}) do
            local hash = type(model) == 'number' and model or GetHashKey(model)
            if hash and hash ~= 0 then wanted[hash] = true end
        end
    end

    local coords = GetEntityCoords(PlayerPedId())

    --[[
        WHAT YOU ARE LOOKING AT WINS, and it is checked before the pool because the pool may not
        contain it at all. A bench that is part of the map is invisible to GetGamePool but perfectly
        solid to a raycast - and it is exactly the case where the tuner used to give up and hand back
        a studio copy whose numbers do not transfer.
    ]]
    local aimed, aimedModel = aimedEntity()
    if aimed and aimedModel and wanted[aimedModel] then
        local at = GetEntityCoords(aimed)
        local dx, dy, dz = at.x - coords.x, at.y - coords.y, at.z - coords.z
        return aimed, aimedModel, math.sqrt(dx * dx + dy * dy + dz * dz)
    end

    --[[
        THEN WHATEVER THE LAST WORKOUT USED, and this is the one that unblocks a real gym.

        Some equipment can be trained on and not found: a target resource reaches it with its own
        raycast, while GetGamePool('CObject') does not list it and a shape test does not return it.
        A bench in that state is the worst possible case - the placement is wrong and there is no way
        to measure a better one, because the tool hands back a studio copy whose numbers do not
        transfer.

        The session that just ran on it proves a working handle exists, so the resource keeps it. Do
        one workout on the awkward prop, then run /vsportprop: it aligns against that exact entity.
    ]]
    local last, lastModel = Session.lastProp()
    if last and lastModel and wanted[lastModel] then
        local at = GetEntityCoords(last)
        local dx, dy, dz = at.x - coords.x, at.y - coords.y, at.z - coords.z

        print('^5[v-sport]^7 using the prop your last workout ran on')
        return last, lastModel, math.sqrt(dx * dx + dy * dy + dz * dz)
    end

    local best, bestDistance, bestHash = nil, math.huge, nil

    for _, entity in ipairs(GetGamePool('CObject')) do
        local hash = GetEntityModel(entity)

        if wanted[hash] then
            local at = GetEntityCoords(entity)
            local dx, dy, dz = at.x - coords.x, at.y - coords.y, at.z - coords.z
            local distanceSquared = dx * dx + dy * dy + dz * dz

            if distanceSquared < bestDistance then
                best, bestDistance, bestHash = entity, distanceSquared, hash
            end
        end
    end

    if not best then return nil end
    return best, bestHash, math.sqrt(bestDistance)
end

--[[
    Put the player next to `entity`, facing it.

    Tuning means going back and forth between a bench and the console, and walking there every
    time is the sort of friction that stops a job getting finished. `/vsportprop` calls this
    itself when the prop it found is not already within arm's reach.

    The landing spot is the entry's own offset when it has one - which is where the player is
    meant to stand anyway - and a metre and a half in front otherwise.
]]
local function goTo(entity, entry, hash)
    if not entity or not DoesEntityExist(entity) then return false end

    local staging = Equipment.staging(entry, hash)
    local offset = staging.offset

    local target
    if offset and (offset.x ~= 0.0 or offset.y ~= 0.0 or offset.z ~= 0.0) then
        target = GetOffsetFromEntityInWorldCoords(entity, offset.x, offset.y, offset.z)
    else
        target = GetOffsetFromEntityInWorldCoords(entity, 0.0, -1.5, 0.0)
    end

    local ped = PlayerPedId()
    local propCoords = GetEntityCoords(entity)

    -- Drop onto the ground rather than into it: the offset is measured from the prop's origin,
    -- which on some models is not at its base.
    local found, groundZ = GetGroundZFor_3dCoord(target.x, target.y, target.z + 2.0, false)
    local z = found and (groundZ + 1.0) or target.z

    SetEntityCoords(ped, target.x, target.y, z, false, false, false, false)

    -- Face the prop, so the first thing seen is the thing being aligned.
    --
    -- GetHeadingFromVector_2d rather than hand-rolled trig: GTA's heading is zero at north and
    -- increases anticlockwise, which is not what atan2 gives you, and getting that convention
    -- subtly wrong lands the player facing away from the bench they came to align.
    local dx, dy = propCoords.x - target.x, propCoords.y - target.y
    if dx ~= 0.0 or dy ~= 0.0 then
        SetEntityHeading(ped, GetHeadingFromVector_2d(dx, dy))
    end

    return true
end

--[[
    Move to `coords` and wait for the world to actually exist there.

    A teleport is instant; the map is not. Scanning the object pool on the frame after arriving
    finds nothing, because nothing has streamed yet - which would make every search report "not
    on the map" from a location that has plenty.

    So the collision is requested and waited for, and then a little longer for props specifically:
    collision loads before object detail does.
]]
local function jumpAndStream(coords)
    local ped = PlayerPedId()

    SetEntityCoords(ped, coords.x, coords.y, coords.z, false, false, false, false)
    RequestCollisionAtCoord(coords.x, coords.y, coords.z)
    FreezeEntityPosition(ped, true)

    local deadline = GetGameTimer() + 6000
    while not HasCollisionLoadedAroundEntity(ped) and GetGameTimer() < deadline do
        RequestCollisionAtCoord(coords.x, coords.y, coords.z)
        Wait(100)
    end

    -- Props stream in after collision does. Without this the scan runs against an empty pool.
    Wait(900)

    FreezeEntityPosition(ped, false)
end

--[[
    Find `onlyModel` anywhere Config.Debug.searchSpots knows about.

    Returns the entity, its hash and the distance when found, and puts the player back where they
    started when it is not - being dumped at the last place searched would be worse than a
    failure message.
]]
local function searchTheMap(key, onlyModel)
    local spots = Config.Debug.searchSpots or {}
    if #spots == 0 then return nil end

    local origin = GetEntityCoords(PlayerPedId())

    Sport.print(('searching %d location(s) for %s'):format(#spots, onlyModel or key))

    for _, spot in ipairs(spots) do
        Sport.print(('  trying %s'):format(spot.name or 'unnamed'))
        jumpAndStream(spot.coords)

        local entity, hash, distance = nearestPropFor(key, onlyModel)
        if entity then
            Sport.print(('  found it at %s'):format(spot.name or 'unnamed'))
            return entity, hash, distance
        end
    end

    Sport.print('  not found anywhere in the list; putting you back')
    jumpAndStream(origin)

    return nil
end

--[[
    Spawn a piece of equipment in the sky and stand the player next to it.

    THE POINT: the alignment tool attaches the ped to the prop, so there is no physics involved -
    which means no ground is needed, no collision, and the model does not have to exist anywhere
    on the map. Hunting for a real specimen was solving a problem that did not need to exist.

    ON REAL GROUND, and that is not a detail. The studio used to be a hundred metres over open
    water, and with no ground the floor had to be guessed from GetModelDimensions - which is the
    model's BOUNDING BOX, not the visible bottom of the prop. Bounding boxes sit lower, because they
    wrap collision and stray geometry, so every body aligned in the sky was measured too low and in
    the world the player's feet went through the ground.

    Now the prop is placed on tarmac with PlaceObjectOnGroundProperly - the native the map itself
    uses - and the player stands on the same surface. The measurement then describes what a player
    will actually see, which is the only thing that makes it worth taking.

    Returns the entity, its hash and the ground height, or nil when the model will not load.
]]
local function spawnStudioProp(model)
    local hash = GetHashKey(model)
    if not hash or hash == 0 or not IsModelValid(hash) then
        Sport.warn(("'%s' is not a model this build has"):format(tostring(model)))
        return nil
    end

    local at = (Config.Debug.tuneStudio or {}).coords or vector3(-1336.0, -3044.0, 13.95)

    RequestModel(hash)
    local deadline = GetGameTimer() + 5000
    while not HasModelLoaded(hash) and GetGameTimer() < deadline do
        Wait(50)
    end

    if not HasModelLoaded(hash) then
        Sport.warn(("the model '%s' would not load"):format(model))
        return nil
    end

    --[[
        MOVE THE PLAYER FIRST, THEN TRACE THE GROUND. The order is the whole thing.

        The first version traced the ground here and teleported the player at the END of this
        function - so the trace ran while they were still hundreds of metres away and the tarmac was
        not streamed. It failed every single time, silently fell back to the configured height, and
        the studio was left guessing its floor again: exactly the bug real ground was meant to end.
        The log said "the studio ground would not stream in" on every spawn and nobody read it.

        Streaming follows the player. So the player goes first, at a safe height, and only then is
        there any geometry to trace against.
    ]]
    local ped = PlayerPedId()
    SetEntityCoords(ped, at.x, at.y + 2.0, at.z + 2.0, false, false, false, false)
    SetEntityInvincible(ped, true)
    FreezeEntityPosition(ped, true)      -- briefly, so they do not fall while the ground loads

    RequestCollisionAtCoord(at.x, at.y, at.z)

    local deadline2 = GetGameTimer() + 10000
    local found, groundZ = GetGroundZFor_3dCoord(at.x, at.y, at.z + 5.0, false)
    while not found and GetGameTimer() < deadline2 do
        Wait(100)
        RequestCollisionAtCoord(at.x, at.y, at.z)
        found, groundZ = GetGroundZFor_3dCoord(at.x, at.y, at.z + 5.0, false)
    end

    if not found then
        Sport.warn('the studio ground would not stream in after 10s; falling back to the '
            .. 'configured height. Z offsets measured here will not transfer to the world - '
            .. 'check Config.Debug.tuneStudio.coords is somewhere with solid ground.')
        groundZ = at.z
    end

    local object = CreateObject(hash, at.x, at.y, groundZ + 1.0, false, true, false)

    --[[
        THE NATIVE THE MAP ITSELF USES.

        PlaceObjectOnGroundProperly settles the prop exactly as a placed map object sits, which is
        the whole reason for having real ground: the alternative is computing where the bottom of the
        prop is, and the bounding box - the only thing available for that - is not the bottom.

        Frozen AFTER placing, so it stays put, and collision left ON: a prop with no collision is
        not what the player will walk up to.
    ]]
    PlaceObjectOnGroundProperly(object)
    FreezeEntityPosition(object, true)
    SetEntityInvincible(object, true)

    -- The ground, read back from the trace rather than from the model. This is what the grid is
    -- drawn at and what the body-height row measures against.
    local floorZ = groundZ

    SetModelAsNoLongerNeeded(hash)

    --[[
        And put the player down on the ground that has now loaded.

        UNFROZEN. Freezing was only ever needed when there was no floor to stand on; on real ground
        it hides the fault it was masking, because a frozen ped holds whatever height it was given
        and feet sunk into tarmac look identical to feet on it. Unfrozen, the ped settles onto the
        surface and the height row reads what the world will read.
    ]]
    SetEntityCoords(ped, at.x, at.y + 2.0, floorZ, false, false, false, false)
    FreezeEntityPosition(ped, false)

    local settled = GetEntityCoords(object)
    Sport.print(('spawned %s in the studio at %.1f %.1f, ground %.2f, prop settled at %.2f')
        :format(model, at.x, at.y, floorZ, settled.z))

    return object, hash, floorZ
end

-- ---------------------------------------------------------------------------------------
-- The camera
-- ---------------------------------------------------------------------------------------
--
--  A SCRIPTED CAMERA, ORBITED WITH THE MOUSE.
--
--  The follow camera is useless for this. It sits behind the ped's shoulder, which is the one
--  angle from which you cannot see whether the body is on the bench - and with the ped frozen in
--  the sky it has no ground to orient against at all, so it ends up inside the character. The
--  first studio session showed a close-up of a forearm and nothing else.
--
--  So the tool takes the camera: mouse orbits, wheel zooms, and it always looks at what is being
--  aligned. That is worth having in a real gym too, not just in the studio.

local cam
local camYaw, camPitch, camDist = 45.0, -20.0, 3.5

local function openCam()
    if cam then return end

    cam = CreateCamWithParams('DEFAULT_SCRIPTED_CAMERA',
        0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 50.0, false, 0)
    SetCamActive(cam, true)
    RenderScriptCams(true, false, 0, true, true)
end

local function closeCam()
    if not cam then return end

    RenderScriptCams(false, false, 0, true, true)
    DestroyCam(cam, true)
    cam = nil
end

--- Orbit from the mouse and point at `target`. Called every frame.
local function updateCam(target)
    if not cam or not target or not DoesEntityExist(target) then return end

    --[[
        The look axes, read as DISABLED so they move the camera and not the character's aim.

        The yaw ADDS. Camera position is (sin yaw, cos yaw) around the target, so the direction it
        looks in is -(sin yaw, cos yaw) - a view heading of 180 - yaw. Turning the view to the
        right means dropping that heading, which means raising the yaw. Subtracting mirrored the
        horizontal axis, and a mirrored mouse is worse than no camera at all.
    ]]
    camYaw = (camYaw + GetDisabledControlNormal(0, 1) * 12.0) % 360.0
    camPitch = Sport.clamp(camPitch - GetDisabledControlNormal(0, 2) * 12.0, -85.0, 85.0, camPitch)

    -- Wheel. 241 is up, 242 is down.
    if IsDisabledControlJustPressed(0, 241) then camDist = math.max(0.8, camDist - 0.35) end
    if IsDisabledControlJustPressed(0, 242) then camDist = math.min(20.0, camDist + 0.35) end

    local at = GetEntityCoords(target)

    -- Spherical to cartesian. Negative pitch puts the camera above, looking down, which is the
    -- angle that shows a body lying on a bench.
    local horizontal = math.cos(math.rad(camPitch)) * camDist

    SetCamCoord(cam,
        at.x + math.sin(math.rad(camYaw)) * horizontal,
        at.y + math.cos(math.rad(camYaw)) * horizontal,
        at.z - math.sin(math.rad(camPitch)) * camDist)

    PointCamAtCoord(cam, at.x, at.y, at.z)
end

-- ---------------------------------------------------------------------------------------
-- The whole-map sweep
-- ---------------------------------------------------------------------------------------
--
--  A curated list of locations can only cover places somebody already knew about, and every gym
--  MLO on every server is somewhere different. So this walks a GRID across the map: teleport,
--  wait for the world to stream, scan, move on.
--
--  It reports EVERY location it finds, as lines ready to paste into Config.Debug.searchSpots -
--  so the slow search happens once per model and the answer becomes permanent.

local sweeping = false

--- Cancel a sweep in progress. Bound to the same key that leaves the tuner.
function Tune.cancelSweep()
    sweeping = false
end

--[[
    Look for `model` across the whole map.

    Returns a list of { coords, count }. Cancellable, and the player is always put back where
    they started - a search that leaves you in the desert is worse than one that fails.
]]
local function sweepForModels(models)
    local cfg = Config.Debug.sweep or {}
    local step = math.max(100.0, tonumber(cfg.step) or 400.0)
    local dwell = math.max(200, math.floor(tonumber(cfg.dwellMs) or 450))

    -- A step above the small-prop streaming radius makes every miss meaningless, so say so rather
    -- than letting the result look authoritative.
    if step > 200.0 then
        Sport.warn(('sweep step is %.0fm, above the ~150m small props stream at.'):format(step))
        Sport.warn('Hits will be real; misses will NOT mean the model is absent.')
    end

    --[[
        MANY MODELS IN ONE PASS.

        The cost of a sweep is the travelling and the streaming, not the looking: once the world
        around a stop has loaded, checking one model against the object pool or checking thirty
        costs the same walk of the same table. Searching for them one at a time meant seven
        minutes per model and the same six hundred teleports over and over.

        So the whole list is answered by a single pass.
    ]]
    local wanted = {}       -- hash -> model name
    local names = {}

    for _, model in ipairs(models) do
        local hash = GetHashKey(model)
        if hash and hash ~= 0 and IsModelValid(hash) then
            wanted[hash] = model
            names[#names + 1] = model
        else
            Sport.warn(("'%s' is not a valid model on this build; skipping"):format(model))
        end
    end

    if #names == 0 then return {} end

    local ped = PlayerPedId()
    local origin = GetEntityCoords(ped)

    -- model name -> list of { coords, count }
    local found = {}
    for _, model in ipairs(names) do found[model] = {} end

    -- Count the stops up front so the progress readout means something.
    local columns = math.floor(((cfg.toX or 4400.0) - (cfg.fromX or -3600.0)) / step) + 1
    local rows = math.floor(((cfg.toY or 7600.0) - (cfg.fromY or -4400.0)) / step) + 1
    local total = columns * rows
    local visited = 0

    --[[
        Survive an unattended hour.

        A sweep teleports the player several thousand times and nobody is watching, so anything
        that can kill or interrupt them will eventually happen: a fall between the ground query and
        the drop, a police response to appearing inside a compound, drowning after a stop over
        water. All of it is switched off for the duration and restored at the end.
    ]]
    sweeping = true
    local skippedWater = 0

    SetEntityInvincible(ped, true)
    SetEntityProofs(ped, true, true, true, true, true, true, true, true)
    ClearPlayerWantedLevel(PlayerId())
    SetPlayerWantedLevel(PlayerId(), 0, false)
    SetPlayerWantedLevelNow(PlayerId(), false)
    SetPedCanRagdoll(ped, false)

    Sport.print(('sweeping %d stops for %d model(s) - this takes a while, [%s] cancels')
        :format(total, #names, UI.keyLabel(KEY.quit, 'BACKSPACE')))

    for x = (cfg.fromX or -3600.0), (cfg.toX or 4400.0), step do
        for y = (cfg.fromY or -4400.0), (cfg.toY or 7600.0), step do
            if not sweeping then break end
            visited = visited + 1

            --[[
                Skip open water before paying for a teleport.

                About half the bounding box is sea and nothing in this catalogue is ever placed on
                it. GetWaterHeight answers without the area being loaded, so this costs one native
                and removes thousands of stops - the difference between a sweep somebody runs and
                one they abandon halfway.
            ]]
            local overWater = false
            if cfg.skipWater ~= false then
                local wet, waterZ = GetWaterHeight(x, y, 0.0)
                -- Sea level is about zero; a water surface meaningfully above the seabed here
                -- means open water rather than a puddle on land.
                if wet and waterZ and waterZ > -1.0 then overWater = true end
            end

            --[[
                An `if` rather than a jump past the progress block.

                Skipping straight to the next stop would also skip the readout and the cancel
                check, so a long stretch of ocean would look like a frozen game and could not be
                interrupted. Water stops are cheap but they still have to tick.
            ]]
            if not overWater then
                --[[
                    Drop in from above, then settle onto the ground.

                    GetGroundZFor_3dCoord needs the area loaded before it can answer, and the area
                    will not load until the player is near it - so the first teleport is what
                    triggers streaming and the second puts the ped where props actually render. At
                    altitude the game serves LOD models and the scan finds nothing.
                ]]
                SetEntityCoords(ped, x, y, 400.0, false, false, false, false)
                FreezeEntityPosition(ped, true)
                RequestCollisionAtCoord(x, y, 400.0)
                Wait(150)

                local hit, groundZ = GetGroundZFor_3dCoord(x, y, 400.0, false)
                if hit then
                    SetEntityCoords(ped, x, y, groundZ + 2.0, false, false, false, false)
                    RequestCollisionAtCoord(x, y, groundZ)
                    Wait(dwell)

                    --[[
                        One walk of the pool, counting every wanted model at once.

                        Counting rather than stopping at the first: a gym has several of a bench,
                        and knowing there are six here and one there is what decides which
                        location goes in searchSpots.
                    ]]
                    local counts = {}
                    for _, entity in ipairs(GetGamePool('CObject')) do
                        local name = wanted[GetEntityModel(entity)]
                        if name then counts[name] = (counts[name] or 0) + 1 end
                    end

                    if next(counts) then
                        local at = GetEntityCoords(ped)

                        for name, count in pairs(counts) do
                            --[[
                                Merge hits that are close together.

                                At a 120 metre step a single gym is seen from four or five
                                neighbouring stops, so without this one location produces five
                                nearly identical lines and the final report is unreadable. The
                                stop that can see the most of them wins.
                            ]]
                            local merged = false
                            for _, place in ipairs(found[name]) do
                                local dx = place.coords.x - at.x
                                local dy = place.coords.y - at.y

                                if (dx * dx + dy * dy) < (200.0 * 200.0) then
                                    merged = true
                                    if count > place.count then
                                        place.count = count
                                        place.coords = at
                                    end
                                    break
                                end
                            end

                            if not merged then
                                found[name][#found[name] + 1] = { coords = at, count = count }
                                Sport.print(('  %d x %s near %.0f %.0f %.0f')
                                    :format(count, name, at.x, at.y, at.z))
                            end
                        end
                    end
                end
            end

            -- Progress, drawn rather than printed: a console line per stop would be thousands of
            -- lines of noise. Only the hits are printed.
            local hits = 0
            for _, places in pairs(found) do
                if #places > 0 then hits = hits + 1 end
            end

            UI.fill(0.5, 0.94, 0.52, 0.05, 'panel')
            UI.text(('Sweeping %d / %d   %d of %d models found   %d water skipped   [%s] cancel')
                :format(visited, total, hits, #names, skippedWater,
                    UI.keyLabel(KEY.quit, 'BACKSPACE')),
                0.5, 0.925, { scale = 0.32, align = 'centre' })

            if IsControlJustPressed(0, KEY.quit) then
                Sport.print('  cancelled')
                sweeping = false
            end
        end

        if not sweeping then break end
    end

    -- Always go home, and always undo everything that was switched off. A sweep that leaves the
    -- player invincible in the desert is worse than one that finds nothing.
    SetEntityCoords(ped, origin.x, origin.y, origin.z, false, false, false, false)
    RequestCollisionAtCoord(origin.x, origin.y, origin.z)
    Wait(400)

    FreezeEntityPosition(ped, false)
    SetEntityInvincible(ped, false)
    SetEntityProofs(ped, false, false, false, false, false, false, false, false)
    SetPedCanRagdoll(ped, true)
    sweeping = false

    Sport.print(('sweep finished: %d stops, %d skipped as water'):format(visited, skippedWater))

    -- The stop count goes back with the results. It used to be read from this function's own local
    -- in the command handler, where it does not exist - which crashed the report AFTER a
    -- half-hour sweep, at the exact moment the findings were about to be printed.
    return found, visited
end

-- ---------------------------------------------------------------------------------------
-- Drawing
-- ---------------------------------------------------------------------------------------

local function draw(state)
    -- Higher up than the workout HUD: the thing being aligned is usually in the middle of the
    -- screen, and a panel at 0.76 sat on top of it.
    local x, y = 0.5, 0.70

    -- Wider and taller than it looks like it needs to be, because the help text does not fit
    -- otherwise: the first version cut off mid-word at the panel edge, which is worse than no
    -- help at all. It is on two lines now.
    -- Two extra rows while a tour is running: where you are in it, and the verdict keys.
    local width, height = 0.42, 0.294
        + (Tune.tourLabel and 0.036 or 0.0)
        + (state.studioProp and 0.016 or 0.0)

    UI.panel(x, y, width, height, 'panel', 'panelEdge')

    local left = x - width * 0.5 + 0.014
    local right = x + width * 0.5 - 0.014
    local cursor = y - height * 0.5 + 0.017

    UI.text(L('tune.title', state.key), left, cursor - 0.011, { scale = 0.36 })
    UI.text(state.modelName, right, cursor - 0.009, {
        scale = 0.26, colour = 'textDim', align = 'right',
    })

    cursor = cursor + 0.019
    UI.line(x, cursor, width - 0.028, 'accent', 0.0018)
    cursor = cursor + 0.017

    -- Which set of numbers the keys are moving right now.
    local editing = L('tune.mode_prop')
    if state.mode == 'anim' then
        editing = L('tune.mode_anim')
    elseif state.mode == 'model' then
        editing = L('tune.mode_model')
    end
    UI.text(editing, left, cursor - 0.009, { scale = 0.28, colour = 'accent' })
    -- The base step, with a note that holding accelerates it. Showing only a number invited the
    -- assumption that the number is all there is.
    UI.text(L('tune.step', state.step), right, cursor - 0.009, {
        scale = 0.26, colour = 'textDim', align = 'right',
    })

    cursor = cursor + 0.020

    local function row(label, value, highlight)
        UI.text(label, left, cursor - 0.008, { scale = 0.26, colour = 'textDim' })
        UI.text(value, right, cursor - 0.008, {
            scale = 0.26,
            colour = highlight and 'text' or 'textDim',
            align = 'right',
        })
        cursor = cursor + 0.018
    end

    row('animOffset', ('%.2f  %.2f  %.2f'):format(
        state.animOffset.x, state.animOffset.y, state.animOffset.z), state.mode == 'anim')

    -- All three angles, with the one R/F is turning marked. Showing only the heading was what
    -- made it look as though the body could not be tipped at all.
    row(('animRot  (%s)'):format(AXES[state.axisIndex]:upper()),
        ('%.1f  %.1f  %.1f'):format(
            state.animRot.x, state.animRot.y, state.animRot.z), state.mode == 'anim')

    --[[
        The height above the ground, and it is the most useful number on this panel.

        A prop's origin is normally at its BASE, so a bench seat is roughly half a metre UP and
        the offset you want is POSITIVE. Reaching for negative Z to "lower the body onto the
        bench" drives it into the floor instead, which is exactly the wrong-way-round mistake
        this row makes visible.
    ]]
    if state.height then
        -- Green within a hand's width of the floor, which is where a body on a bench or a mat
        -- belongs. Amber when it is floating. Red when it is underground.
        local colour = 'judgePerfect'
        if state.height < -0.15 then
            colour = 'judgeMiss'
        elseif state.height > 0.20 then
            colour = 'judgeGood'
        end

        UI.text(L('tune.body_height'), left, cursor - 0.008, {
            scale = 0.26, colour = 'textDim',
        })
        UI.text(('%+.2f m'):format(state.height), right, cursor - 0.008, {
            scale = 0.26, colour = colour, align = 'right',
        })

        cursor = cursor + 0.018
    end
    -- In two-handed mode this is a fine offset in the bar's own frame, not an attachment point,
    -- so the label says which it is rather than leaving it to be guessed.
    row(HOLDS[state.holdIndex] == 'twoHanded' and 'fine offset  (along / across / up)'
            or 'prop pos',
        ('%.3f  %.3f  %.3f'):format(
            state.propPos.x, state.propPos.y, state.propPos.z), state.mode == 'prop')
    -- The axis R/F is turning is marked, because "R does nothing" is otherwise the natural
    -- conclusion when the selected axis is not the one that needs changing.
    row(('prop rot  (%s)'):format(AXES[state.axisIndex]:upper()),
        ('%.1f  %.1f  %.1f'):format(
            state.propRot.x, state.propRot.y, state.propRot.z), state.mode == 'prop')

    -- Which object is in the hand, and which hand. Cycled in 'model' mode.
    local choice = state.models[state.modelIndex] or {}
    row('prop model', ('%s   (%d/%d)'):format(
        choice.label or 'none', state.modelIndex, #state.models), state.mode == 'model')
    local hold = HOLDS[state.holdIndex]
    row('held', ('%s%s'):format(
        hold == 'twoHanded' and 'BOTH HANDS (auto)' or BONES[state.boneIndex].label,
        hold == 'centred' and '   [centred]' or ''), state.mode == 'model')

    -- The prop's real size. Knowing the bar is 2.1m long is what tells you it has to be centred
    -- rather than nudged.
    if state.propSize then
        row('prop size', ('%.2f x %.2f x %.2f m'):format(
            state.propSize.x, state.propSize.y, state.propSize.z), false)
    end

    UI.text(L('tune.help_move', UI.keyLabel(KEY.raise, 'E'), UI.keyLabel(KEY.lower, 'Q'),
        UI.keyLabel(KEY.turnCcw, 'R'), UI.keyLabel(KEY.turnCw, 'F'),
        UI.keyLabel(KEY.quarter, 'G')), left, cursor - 0.008, {
            scale = 0.235, colour = 'textDim',
        })

    cursor = cursor + 0.015

    UI.text(L('tune.help_snap', UI.keyLabel(KEY.axis, 'Z'), UI.keyLabel(KEY.straight, 'H'),
        UI.keyLabel(KEY.hold, 'TAB'), UI.keyLabel(KEY.reset, 'C')), left, cursor - 0.008, {
            scale = 0.225, colour = 'textDim',
        })

    cursor = cursor + 0.015

    UI.text(L('tune.help_keys', UI.keyLabel(KEY.mode, 'SPACE'), UI.keyLabel(KEY.print, 'ENTER'),
        UI.keyLabel(KEY.quit, 'BACKSPACE')), left, cursor - 0.008, {
            scale = 0.235, colour = 'textDim',
        })

    cursor = cursor + 0.015

    -- Its own line, in the accent colour, because the tool taking the mouse away from the
    -- character is the one behaviour nobody expects until they read it.
    UI.text(L('tune.help_cam'), left, cursor - 0.008, {
        scale = 0.235, colour = 'accent',
    })

    cursor = cursor + 0.015

    -- The save key gets its own line and a warmer colour than the rest: it is the only key here
    -- that changes something for every player on the server, and burying it in a list of six
    -- would be the wrong emphasis entirely.
    UI.text(L('tune.help_save', UI.keyLabel(KEY.save, 'K')), left, cursor - 0.008, {
        scale = 0.235, colour = 'judgePerfect',
    })

    --[[
        THE STUDIO WARNING, and it is on the panel because the console is not read while aligning.

        An offset is measured from the prop's origin, and how high that origin sits above the ground
        is decided by whoever placed the prop on the map. A studio copy is placed by
        PlaceObjectOnGroundProperly instead, which gives a different height - so a number measured
        here can be half a metre out in a real gym, and was.

        For a model the map places nowhere this is the best available answer and the warning is just
        noise. For one that exists in a gym it means: go and use the real one.
    ]]
    if state.studioProp then
        cursor = cursor + 0.016
        UI.text(L('tune.studio_warning'), left, cursor - 0.008, {
            scale = 0.235, colour = 'judgeMiss',
        })
    end

    --[[
        THE TOUR ROWS. Position first, then the verdict keys.

        On the panel rather than in the console on purpose: a review is a judgement made while
        looking at a body on a bench, and anything that requires looking away from the body is a
        thing that will not be read.
    ]]
    if Tune.tourLabel then
        cursor = cursor + 0.017
        UI.line(x, cursor, width - 0.028, 'accent', 0.0015)
        cursor = cursor + 0.015

        UI.text(Tune.tourLabel, left, cursor - 0.009, { scale = 0.28, colour = 'accent' })

        cursor = cursor + 0.016
        UI.text(L('tune.help_tour',
            UI.keyLabel(KEY.good, '1'), UI.keyLabel(KEY.bad, '2'),
            UI.keyLabel(KEY.next, 'N'), UI.keyLabel(KEY.prev, 'B')),
            left, cursor - 0.008, { scale = 0.235, colour = 'textDim' })
    end
end

-- ---------------------------------------------------------------------------------------
-- The prop being held
-- ---------------------------------------------------------------------------------------

--[[
    The list of models the tool can cycle through.

    The exercise's own prop first, so tuning always starts from what is configured; then
    'none', because some exercises should not be holding anything and that has to be reachable;
    then whatever Config.Debug.tuneProps offers, skipping duplicates and anything this game
    build does not have.
]]
local function buildModelList(configured)
    local list = {}
    local seen = {}

    local function add(model)
        if model == nil then
            if not seen['@none'] then
                seen['@none'] = true
                list[#list + 1] = { model = nil, label = 'none' }
            end
            return
        end

        if type(model) ~= 'string' or model == '' or seen[model] then return end

        local hash = GetHashKey(model)
        if not IsModelValid(hash) then
            Sport.debug('tuneProps: skipping', model, '(not in this build)')
            return
        end

        seen[model] = true
        list[#list + 1] = { model = model, hash = hash, label = model }
    end

    add(configured)
    add(nil)

    for _, model in ipairs(Config.Debug.tuneProps or {}) do
        add(model)
    end

    -- Everything was invalid, which would leave nothing to cycle. 'none' is always reachable.
    if #list == 0 then list[1] = { model = nil, label = 'none' } end

    return list
end

--[[
    A model's bounding box in its own space, as centre and size.

    Used for two things: the size is shown on the panel so you know how long the bar you are
    trying to place actually is, and the centre is what the centring key subtracts.
]]
local function modelBox(hash)
    local ok, minimum, maximum = pcall(function()
        return GetModelDimensions(hash)
    end)

    if not ok or type(minimum) ~= 'vector3' or type(maximum) ~= 'vector3' then
        return nil, nil
    end

    return vector3(
        (minimum.x + maximum.x) * 0.5,
        (minimum.y + maximum.y) * 0.5,
        (minimum.z + maximum.z) * 0.5),
    vector3(
        maximum.x - minimum.x,
        maximum.y - minimum.y,
        maximum.z - minimum.z)
end

--- Destroy whatever is in hand and create the currently selected model instead. Called only
--- when the selection changes, not on every nudge - creating an object per frame would be
--- absurd.
local function respawnProp(state)
    if state.propHandle and DoesEntityExist(state.propHandle) then
        SetEntityAsMissionEntity(state.propHandle, true, true)
        DeleteEntity(state.propHandle)
    end
    state.propHandle = nil

    local choice = state.models[state.modelIndex]
    if not choice or not choice.model then return end

    RequestModel(choice.hash)

    local deadline = GetGameTimer() + 3000
    while not HasModelLoaded(choice.hash) and GetGameTimer() < deadline do
        Wait(50)
    end

    if HasModelLoaded(choice.hash) then
        local at = GetEntityCoords(PlayerPedId())
        state.propHandle = CreateObject(choice.hash, at.x, at.y, at.z, false, true, false)

        -- Measured while the model is still loaded. The size goes on the panel, the centre is
        -- what 'centred' subtracts, and the longest side decides the default hold.
        state.propCentre, state.propSize = modelBox(choice.hash)

        --[[
            PICK THE HOLD FROM THE MODEL'S SIZE.

            A 2.27 metre barbell cannot be held in one hand, and defaulting to a hand bone put it
            through the player's arm at a diagonal - which reads as a broken script rather than as
            a default that needs changing.

            Anything longer than a metre goes to two-handed. Below that a single hand is right,
            and anything whose origin is off-centre gets 'centred' so it does not hang off the
            grip. Both are derived; TAB still overrides, and the choice is re-derived whenever the
            model changes because a decision made for a barbell is wrong for a dumbbell.
        ]]
        -- Not when the entry already states how the prop is held: a configured choice was made
        -- deliberately and outranks a guess from a bounding box.
        if state.propSize and state.deriveHold ~= false then
            local longest = math.max(state.propSize.x, state.propSize.y, state.propSize.z)

            if longest > 1.0 then
                state.holdIndex = 3                     -- two-handed
            elseif state.propCentre and (math.abs(state.propCentre.x) > 0.05
                or math.abs(state.propCentre.y) > 0.05) then
                state.holdIndex = 2                     -- centred on the bone
            else
                state.holdIndex = 1                     -- straight onto the bone
            end

            Sport.debug(('%s is %.2fm long -> hold %s')
                :format(choice.label, longest, HOLDS[state.holdIndex]))
        end
    else
        Sport.warn(("the model '%s' would not load"):format(choice.model))
    end

    SetModelAsNoLongerNeeded(choice.hash)
end

-- ---------------------------------------------------------------------------------------
-- Applying
-- ---------------------------------------------------------------------------------------

-- Same two flags as the session uses: loop, plus kinematic physics so the body follows the
-- placement exactly instead of being fought by its own collision capsule.
local PLACED_ANIM_FLAG = 1 + 262144

--[[
    How far the PED is above the ground, in metres.

    THE PED, NOT THE ANIMATION ROOT, and the difference is the whole point.

    An earlier version measured the root and refused to let it go below ground level, on the
    reasoning that below ground is where you fall out of the world. That reasoning was wrong: a
    clip translates the body away from its own root, and the bench-press clip lifts it roughly a
    metre. So the root has to sit BELOW the floor for the body to land ON the bench, and guarding
    the root meant the body stopped descending after a few nudges and no amount of pressing did
    anything - the exact symptom the guard was supposed to prevent.

    The body's height is the number that means something, so it is the number that is measured
    and shown. Returns nil when the ground cannot be probed.
]]
--[[
    How far the body's lowest point is above the floor. Zero means standing on it.

    FROM THE FOOT BONES, NOT FROM GetEntityCoords. An ATTACHED ped's coordinates are its attach
    point, somewhere around the pelvis, so this row read +1.03 on the yoga mats while the body was
    lying flat on them - it was reporting the offset it had just been given rather than where the
    body ended up, which made it worse than blank. The foot bones are where the body actually is,
    in every mode, attached or not.
]]
local FOOT_BONES = { 14201, 52301 }        -- SKEL_L_Foot, SKEL_R_Foot

local function pedHeightAboveGround(floorZ)
    local ped = PlayerPedId()

    local foot
    for index = 1, #FOOT_BONES do
        local bone = GetPedBoneCoords(ped, FOOT_BONES[index], 0.0, 0.0, 0.0)
        if bone and (not foot or bone.z < foot.z) then foot = bone end
    end

    if not foot then return nil end

    --[[
        THE STUDIO'S FLOOR IS A NUMBER, NOT GEOMETRY.

        GetGroundZFor_3dCoord traces against the map, and there is no map a hundred metres over the
        sea, so in the studio it reports nothing at all - which is what made this row go blank on
        the standing exercises, exactly where it was needed most. The drawn grid's height is used
        instead, and it is a better reference anyway: it is the plane the equipment rests on.
    ]]
    if floorZ then
        return foot.z - floorZ
    end

    local found, groundZ = GetGroundZFor_3dCoord(foot.x, foot.y, foot.z + 3.0, false)
    if not found then return nil end

    return foot.z - groundZ
end

--[[
    DRAW THE STUDIO'S FLOOR.

    A body hanging in an empty sky cannot be judged: for anything performed standing there is
    nothing to say whether the feet are on the floor, sunk into it or a metre above it. Which is
    the one thing a standing exercise needs.

    So the plane the equipment rests on is drawn as a grid, taken from the prop's own bounding box
    rather than assumed. The two centre lines are coloured because they answer the other question
    the sky cannot: which way is +X and which way is +Y, and therefore what animHeading = 0 means.

        red   = the prop's +X
        green = the prop's +Y
]]
local function drawStudioFloor(state)
    local z = state.studioFloor
    if not z or not state.entity or not DoesEntityExist(state.entity) then return end

    local at = GetEntityCoords(state.entity)
    local half, step = 3.0, 0.5
    local x0, y0 = at.x - half, at.y - half
    local span = half * 2.0

    for i = 0, math.floor(span / step) do
        local o = i * step
        DrawLine(x0 + o, y0, z, x0 + o, y0 + span, z, 110, 190, 240, 70)
        DrawLine(x0, y0 + o, z, x0 + span, y0 + o, z, 110, 190, 240, 70)
    end

    DrawLine(at.x - half, at.y, z, at.x + half, at.y, z, 240, 90, 90, 220)
    DrawLine(at.x, at.y - half, z, at.x, at.y + half, z, 90, 240, 120, 220)
end

--- Re-play the animation at the current numbers, and re-attach the prop. Called after every
--- nudge, because the only way to judge a placement is to see it.
--[[
    Place a two-handed prop across both hands. Same maths as the session's own updater: midpoint
    of the two hand bones, heading from one to the other, pitch from the height between them.

    Called every frame while this hold mode is selected, because the hands move every frame.
]]
local function updateTwoHanded(state)
    local object = state.propHandle
    if not object or not DoesEntityExist(object) then return end

    local ped = PlayerPedId()
    local right = GetPedBoneCoords(ped, BONES[1].id, 0.0, 0.0, 0.0)
    local left = GetPedBoneCoords(ped, BONES[2].id, 0.0, 0.0, 0.0)

    local dx, dy, dz = right.x - left.x, right.y - left.y, right.z - left.z
    local flat = math.sqrt(dx * dx + dy * dy)
    if flat < 0.01 then return end

    SetEntityCoords(object,
        (right.x + left.x) * 0.5, (right.y + left.y) * 0.5, (right.z + left.z) * 0.5,
        false, false, false, false)

    -- The same derived correction the session uses: turn the model's longest axis onto the
    -- hand-to-hand line. Without it a bar that is long in X comes out perpendicular to the
    -- hands, which looks like a positioning problem and cannot be positioned away.
    local correction = Session.longAxisYaw(GetEntityModel(object))

    SetEntityRotation(object,
        -math.deg(math.atan(dz, flat)) + state.propRot.x,
        state.propRot.y,
        GetHeadingFromVector_2d(dx, dy) + correction + state.propRot.z,
        2, true)

    --[[
        The fine offset, in the bar's own frame now that it is oriented.

        Without this the arrow keys did nothing in two-handed mode - the position is recomputed
        every frame, so anything they changed was overwritten immediately. Which is exactly the
        "it will not let me adjust it" complaint: the mode worked and could not be touched.

        Y slides the bar along its length, X moves it across the body, Z lifts it out of the
        palms. Local space, so a number tuned once stays right whichever way the player faces.
    ]]
    local off = state.propPos
    if off.x ~= 0.0 or off.y ~= 0.0 or off.z ~= 0.0 then
        local world = GetOffsetFromEntityInWorldCoords(object, off.x, off.y, off.z)
        SetEntityCoords(object, world.x, world.y, world.z, false, false, false, false)
    end
end

local function apply(state)
    local ped = PlayerPedId()

    -- The prop first, so it is in hand for the frame the animation restarts on.
    if state.propHandle and DoesEntityExist(state.propHandle) then
        local hold = HOLDS[state.holdIndex]

        if hold == 'twoHanded' then
            -- Not attached at all: driven from both hand bones by the loop below.
            DetachEntity(state.propHandle, true, false)
            SetEntityCollision(state.propHandle, false, false)
            updateTwoHanded(state)
        else
            local pos = state.propPos

            -- 'centred' puts the model's middle on the bone rather than its origin, which is
            -- what a long object needs before either hand can reach it.
            if hold == 'centred' and state.propCentre then
                pos = vector3(
                    pos.x - state.propCentre.x,
                    pos.y - state.propCentre.y,
                    pos.z - state.propCentre.z)
            end

            AttachEntityToEntity(state.propHandle, ped,
                GetPedBoneIndex(ped, state.bone),
                pos.x, pos.y, pos.z,
                state.propRot.x, state.propRot.y, state.propRot.z,
                true, true, false, true, 1, true)
        end
    end

    if not state.dict then return end

    --[[
        THE PED IS ATTACHED TO THE PROP, not placed in the world.

        This is the fix for the bug that made this tool feel broken: with the body merely placed
        at world coordinates, the BENCH'S OWN COLLISION pushed the capsule back. Lowering it did
        nothing for several nudges while the capsule rode up the bench, then the accumulated
        offset won all at once and the character dropped through the map.

        Attached, the offset is in the bench's local space and there is no physics to argue with.
        +Z is genuinely "up onto the seat", every nudge moves exactly that far, and nothing can
        block or tunnel. Which is what makes the numbers on this panel mean something.

        Re-attaching each time is cheap and is what makes the nudge visible immediately.
    ]]
    AttachEntityToEntity(ped, state.entity, 0,
        state.animOffset.x, state.animOffset.y, state.animOffset.z,
        state.animRot.x, state.animRot.y, state.animRot.z,
        false,      -- p9
        false,      -- useSoftPinning: false, or physics drags the ped off the mount
        false,      -- collision: off, which is the entire point
        true,       -- isPed
        2,          -- rotationOrder
        true)       -- fixedRot

    -- Only start the animation once. Restarting it on every nudge re-blends from scratch, which
    -- makes the body twitch and hides the very change being judged.
    if not state.animStarted then
        TaskPlayAnim(ped, state.dict, state.clip,
            8.0, -8.0, -1, PLACED_ANIM_FLAG, 0.0, false, false, false)
        state.animStarted = true
    end
end

--[[
    The current placement, as the server's storage shape.

    Shared by the save key and by nothing else yet, but written as its own function because the
    alternative is scraping it back out of printBlock's formatted strings - and a placement that
    reaches the file through a %.2f has already lost a digit.
]]
local function placementOf(state)
    local choice = state.models[state.modelIndex] or {}
    local hold = HOLDS[state.holdIndex]

    local function nonZero(v)
        return v and (v.x ~= 0.0 or v.y ~= 0.0 or v.z ~= 0.0)
    end

    local payload = {
        animOffset = { x = state.animOffset.x, y = state.animOffset.y, z = state.animOffset.z },
    }

    -- The simpler field when only the heading moved, exactly as printBlock chooses.
    if state.animRot.x == 0.0 and state.animRot.y == 0.0 then
        payload.animHeading = state.animRot.z
    else
        payload.animRot = { x = state.animRot.x, y = state.animRot.y, z = state.animRot.z }
    end

    if choice.model then
        local spec = { model = choice.model }

        if hold == 'twoHanded' then
            spec.twoHanded = true
        elseif hold == 'centred' then
            -- `centre`, not `centred`. The runtime reads `centre` and nothing has ever read
            -- `centred`, so every alignment saved in the centred hold silently lost its centring and
            -- came back attached by the model's origin instead of its middle - a long bar through the
            -- wrist. One letter, invisible in every review, and a saved file cannot depend on the old
            -- name because nothing consumed it.
            spec.centre = true
            spec.bone = BONES[state.boneIndex].id
        else
            spec.bone = BONES[state.boneIndex].id
        end

        if nonZero(state.propPos) then
            spec.pos = { x = state.propPos.x, y = state.propPos.y, z = state.propPos.z }
        end
        if nonZero(state.propRot) then
            local field = hold == 'twoHanded' and 'rotOffset' or 'rot'
            spec[field] = { x = state.propRot.x, y = state.propRot.y, z = state.propRot.z }
        end

        payload.props = { spec }
    end

    return payload
end

--[[
    Save the current placement for every player, now, with no restart and nothing to paste.

    It goes to the server as a `modelOverrides` entry for THIS model rather than onto the exercise
    itself, which is what makes it safe to press: aligning one bench cannot move the body on the
    other five.

    The console block still gets printed. data/custom.json is convenient and it is not version
    control, so the paste-ready text stays available for the moment an addition has proven itself
    and belongs in config.lua - see /vsportexport.
]]
local function saveBlock(state)
    if not state.modelName or state.modelName:sub(1, 1) == '[' then
        Compat.notify(L('custom.no_name'), 'error')
        print('^3[v-sport] this prop has no resolvable model name, so there is nothing to key '
            .. 'an override on. The printed block still works by hand.^7')
        return
    end

    TriggerServerEvent('vsport:server:CustomAlign', state.key, state.modelName,
        placementOf(state))
end

local function printBlock(state)
    local choice = state.models[state.modelIndex] or {}

    print('^5==== v-sport: paste into the ' .. state.key .. ' entry ====^7')
    print(('        placeAnim = true,'))
    print(('        animOffset = vector3(%.2f, %.2f, %.2f),')
        :format(state.animOffset.x, state.animOffset.y, state.animOffset.z))
    -- The simpler field when only the heading is used, which is the common case and reads
    -- better in the catalogue; the full vector as soon as the body is tipped or rolled.
    if state.animRot.x == 0.0 and state.animRot.y == 0.0 then
        print(('        animHeading = %.1f,'):format(state.animRot.z))
    else
        print(('        animRot = vector3(%.1f, %.1f, %.1f),')
            :format(state.animRot.x, state.animRot.y, state.animRot.z))
    end

    if choice.model then
        --[[
            The hold mode decides which fields the block even has, so each one writes its own
            rather than sharing a half-correct prefix.

            twoHanded has no `bone` and no attachment point at all: the position comes from the
            hands. `pos` there is a fine offset in the bar's own frame, and `rotOffset` corrects
            odd geometry. Both are omitted when they are zero, because a block full of zeroes
            invites somebody to start changing them.

            centred prints the FLAG rather than the corrected numbers: `centre` is computed from
            the model at runtime, so writing the offset in as well would apply it twice.
        ]]
        local hold = HOLDS[state.holdIndex]

        local function nonZero(v)
            return v.x ~= 0.0 or v.y ~= 0.0 or v.z ~= 0.0
        end

        print('        props = {')

        if hold == 'twoHanded' then
            local lines = { ("model = '%s'"):format(choice.model), 'twoHanded = true' }

            if nonZero(state.propPos) then
                lines[#lines + 1] = ('pos = vector3(%.3f, %.3f, %.3f)')
                    :format(state.propPos.x, state.propPos.y, state.propPos.z)
            end
            if nonZero(state.propRot) then
                lines[#lines + 1] = ('rotOffset = vector3(%.1f, %.1f, %.1f)')
                    :format(state.propRot.x, state.propRot.y, state.propRot.z)
            end

            print(('            { %s },'):format(table.concat(lines, ', ')))
            print('        },')
            print('')
            print('^3  No bone and no attachment: the bar is placed across both hands every^7')
            print('^3  frame, so it tracks them for the whole movement. `pos` is a fine offset^7')
            print('^3  in the bar\'s own frame - along, across, up.^7')
            print('^5=========================================================^7')
            Compat.notify(L('tune.printed'), 'success')
            return
        end

        print(("            { model = '%s', bone = %d,"):format(choice.model, state.bone))

        if hold == 'centred' then print('              centre = true,') end

        print(('              pos = vector3(%.3f, %.3f, %.3f),')
            :format(state.propPos.x, state.propPos.y, state.propPos.z))
        print(('              rot = vector3(%.1f, %.1f, %.1f) },')
            :format(state.propRot.x, state.propRot.y, state.propRot.z))
        print('        },')
    else
        print('        -- nothing held: no `props` line, or delete the one that is there')
    end

    print('')
    print('^3  Per-model, if this bench differs from the others:^7')
    print('        modelOverrides = {')
    print(("            ['%s'] = {"):format(state.modelName))
    print(('                animOffset = vector3(%.2f, %.2f, %.2f),')
        :format(state.animOffset.x, state.animOffset.y, state.animOffset.z))
    if state.animRot.x == 0.0 and state.animRot.y == 0.0 then
        print(('                animHeading = %.1f,'):format(state.animRot.z))
    else
        print(('                animRot = vector3(%.1f, %.1f, %.1f),')
            :format(state.animRot.x, state.animRot.y, state.animRot.z))
    end
    print('            },')
    print('        },')
    print('^5=========================================================^7')

    Compat.notify(L('tune.printed'), 'success')
end

-- ---------------------------------------------------------------------------------------
-- The loop
-- ---------------------------------------------------------------------------------------

function Tune.stop()
    active = false
end

--[[
    THE TOUR'S THREE HOOKS.

    `busy` is not the same thing as `active`, and the difference matters: `active` goes false the
    moment a key asks the loop to end, while the teardown - deleting the prop, clearing tasks,
    detaching the ped, putting them back where they were - runs for a few hundred milliseconds after
    that. A tour that started the next prop on `active == false` would race its own cleanup and have
    the previous session delete the new prop.

    `stepRequest` is how N and B talk to the tour: the tuner cannot know what comes next, and the
    tour cannot reach inside the tuner's control loop, so the loop sets a number and exits.
]]
local busy = false

function Tune.busy()
    return busy
end

function Tune.active()
    return active
end

--- +1 for the next pair, -1 for the previous, nil when the operator quit outright.
Tune.stepRequest = nil

--- The review verdict for the pair just looked at: true, false, or nil for "stepped past".
Tune.verdict = nil

--- A line the tour writes onto the panel, so "which of these am I looking at" is on screen rather
--- than in a console the operator is not reading while judging an animation.
Tune.tourLabel = nil

function Tune.start(key, onlyModel)
    if active or busy then return false end
    busy = true

    -- Remembered before anything teleports, so the exit can put the player back. Without it a
    -- studio session ends by dropping them out of the sky.
    local origin = GetEntityCoords(PlayerPedId())
    if Session.active() then
        Compat.notify(L('tune.busy'), 'error')
        busy = false
        return false
    end

    local entry = Equipment.get(key)
    if not entry then
        print(L('cmd.no_equipment', tostring(key)))
        print('  Known equipment: ' .. table.concat(Equipment.keys, ', '))
        busy = false
        return false
    end

    --[[
        `here` MEANS THE PROP IN FRONT OF ME, WHATEVER IT IS. The escape hatch that always works.

        Four model-filtered lookups failed on one real bench: the pool walk, a shape test, the
        known-locations search, and the handle the last session used. A target resource trained on it
        the whole time. Rather than keep adding mechanisms that might find it, this one asks a question
        with no filter to get wrong - and prints which model it turned out to be, which is the answer
        to why the others could not.
    ]]
    local here = onlyModel == 'here'
    if here then onlyModel = nil end

    -- A named model narrows the search, so each of an exercise's props can be reached in turn.
    if onlyModel and not Sport.contains(entry.models or {}, onlyModel) then
        print(("^3[v-sport] %s does not list the model '%s'.^7"):format(key, onlyModel))
        print('^3  Its models: ' .. table.concat(entry.models or {}, ', ') .. '^7')
        busy = false
        return false
    end

    --[[
        THE STUDIO IS THE DEFAULT. Spawn the equipment in the sky and align against that.

        This is the answer to an entire evening of "no prop nearby". Aligning does not need a real
        specimen in a real place: the ped is ATTACHED to the prop, so with no physics in play there
        is no need for ground, for collision, or for the model to be placed anywhere on the map.

        Everything becomes uniform - one command, the same clean backdrop, the same camera - and
        models that exist in the files but sit nowhere on the map become alignable for the first
        time. Set Config.Debug.tuneStudio.always = false to work against the real thing instead.
    ]]
    local studioCfg = Config.Debug.tuneStudio or {}
    local entity, hash, distance
    local studio = false
    local floorZ

    -- With no model named, take the entry's first: the studio needs something specific to build,
    -- and the first listed model is the one the entry is written around.
    local wantedModel = onlyModel or (entry.models or {})[1]

    --[[
        `here` RESOLVES FIRST AND EVERYTHING BELOW THEN SKIPS ITSELF, because each of the lookups is
        guarded on `entity` already. No search, no studio, no model filter.
    ]]
    if here then
        entity, hash, distance = nearestAnything()

        if not entity then
            print('^3[v-sport] no object at all within 10 metres of you.^7')
            Compat.notify(L('custom.nothing_there'), 'error')
            busy = false
            return false
        end

        wantedModel = nil

        local listedName = nil
        for _, listed in ipairs(entry.models or {}) do
            if type(listed) == 'string' and GetHashKey(listed) == hash then
                listedName = listed
                break
            end
        end

        print(('^5[v-sport]^7 using the object in front of you: %s, %.1fm away'):format(
            listedName or ('an UNLISTED model, hash ' .. tostring(hash)), distance or 0.0))

        if not listedName then
            print(('^3[v-sport] %s does not list that model, so this is the answer to why the other '
                .. 'lookups could not find it. Add it with /%s %s and the save key will work.^7')
                :format(key, Config.Commands.add or 'vsportadd', key))
        end
    end

    if not entity and studioCfg.always ~= false and type(wantedModel) == 'string' then
        entity, hash, floorZ = spawnStudioProp(wantedModel)
        distance = 2.0
        studio = entity ~= nil

        if studio then
            onlyModel = wantedModel
            Compat.notify(L('tune.studio', wantedModel), 'success')
        end
    end

    -- The real world, either because the studio is switched off or because the model would not
    -- load. Nearby first, then the known locations.
    if not entity then
        entity, hash, distance = nearestPropFor(key, onlyModel)

        if not entity then
            Compat.notify(L('tune.searching'), 'primary')
            entity, hash, distance = searchTheMap(key, onlyModel)
        end
    end

    --[[
        AND NOW THE STUDIO, AS THE ACTUAL FALLBACK.

        `always = false` was documented as "the real prop first, the studio only when no specimen can
        be found" and the code did no such thing: it skipped the studio entirely, so a model the map
        places nowhere could not be opened at all. /vsporttour died on its first pair.

        A studio copy is a poor measurement for a prop the map places somewhere - see the note on the
        squat rack - but for one it places NOWHERE it is the only thing there is, and refusing to open
        it helps no-one. The panel says which case you are in.
    ]]
    if not entity and type(wantedModel) == 'string' then
        entity, hash, floorZ = spawnStudioProp(wantedModel)
        distance = 2.0
        studio = entity ~= nil

        if studio then
            onlyModel = wantedModel
            print(('^3[v-sport] no %s is placed on the map; using a studio copy. The offset may '
                .. 'not transfer to a map-placed one.^7'):format(wantedModel))
            Compat.notify(L('tune.studio', wantedModel), 'primary')
        end
    end

    if not entity then
        Compat.notify(L('tune.no_prop', onlyModel or key), 'error')
        print(('^3[v-sport] %s could not be found and could not be spawned.^7')
            :format(onlyModel or key))
        busy = false
        return false
    end

    -- Walk over there for them. Tuning is a back-and-forth job and doing that on foot every
    -- time is what stops it getting finished.
    if distance > 3.0 then
        goTo(entity, entry, hash)
        Wait(250)
        Compat.notify(L('tune.teleported', distance), 'primary')
    end

    -- Start from whatever the config already says, so tuning is always an improvement on the
    -- current values rather than a restart from zero.
    local staging = Equipment.staging(entry, hash)
    local spec = (staging.props or {})[1] or {}

    local state = {
        key = key,
        entity = entity,

        -- A prop this tool conjured, and where the player was standing when it did. Both are
        -- needed at exit: the prop has to be destroyed and the player has to come back down.
        studioProp = studio and entity or nil,
        origin = origin,

        -- The height of the drawn grid. Doubles as the reference for the body-height row, which
        -- has no map to trace against up here.
        studioFloor = studio and floorZ or nil,

        modelName = ('[%d]'):format(hash),
        mode = 'anim',
        step = 0.05,

        animOffset = vector3(
            staging.animOffset and staging.animOffset.x or 0.0,
            staging.animOffset and staging.animOffset.y or 0.0,
            staging.animOffset and staging.animOffset.z or 0.0),

        -- Whatever the entry says, as a full vector: `animRot` when it has one, and its
        -- `animHeading` promoted into Z when it does not.
        animRot = Equipment.bodyRotation(staging),

        propPos = vector3(
            spec.pos and spec.pos.x or 0.0,
            spec.pos and spec.pos.y or 0.0,
            spec.pos and spec.pos.z or 0.0),
        propRot = vector3(
            spec.rot and spec.rot.x or 0.0,
            spec.rot and spec.rot.y or 0.0,
            spec.rot and spec.rot.z or 0.0),
    }

    -- Name the model where it can be named, so the printed block is paste-ready.
    for _, model in ipairs(entry.models or {}) do
        if type(model) == 'string' and GetHashKey(model) == hash then
            state.modelName = model
            break
        end
    end

    -- What can be held, and where. The exercise's own choice is first in both lists, so
    -- tuning always begins from what is configured rather than from an arbitrary default.
    state.models = buildModelList(spec.model)
    state.modelIndex = 1

    state.axisIndex = 3         -- start on Z, the one that is usually wanted first

    -- Start in whichever hold the entry already asks for, and only fall back to deriving one
    -- from the model's size when the entry says nothing.
    state.holdIndex = 1
    state.deriveHold = true

    if spec.twoHanded then
        state.holdIndex = 3
        state.deriveHold = false
    elseif spec.centre then
        state.holdIndex = 2
        state.deriveHold = false
    end

    state.boneIndex = 1
    for index, bone in ipairs(BONES) do
        if bone.id == (spec.bone or 57005) then
            state.boneIndex = index
            break
        end
    end
    state.bone = BONES[state.boneIndex].id

    -- The animation, loaded once.
    if type(staging.anim) == 'table' then
        local dict = staging.anim.dict
        RequestAnimDict(dict)

        local deadline = GetGameTimer() + 3000
        while not HasAnimDictLoaded(dict) and GetGameTimer() < deadline do Wait(50) end

        if HasAnimDictLoaded(dict) then
            state.dict, state.clip = dict, staging.anim.clip
        else
            Sport.warn(('the dictionary %s would not load; tuning the prop only'):format(dict))
        end
    end

    -- The prop. Created here, and again whenever the selection changes.
    respawnProp(state)

    --[[
        HIDE THE EQUIPMENT DURING A REVIEW, IF A SESSION WOULD HIDE IT.

        free_weights sets `hideProp`: in a real session the barbell lying on the sand is hidden
        while the player lifts an identical one, because seeing both is the giveaway. The alignment
        tool never applied it - correctly, since you cannot align a body against a prop you cannot
        see - and the tour inherited that.

        The consequence was seven false verdicts in a row. Every dumbbell and plated bar came up in
        the review with a barbell on the ground AND a barbell in the hands, which is not a state the
        game ever shows, and they were all marked wrong for it.

        So: hidden while touring, visible while aligning. The judgement and the measurement need
        opposite things and only one of them was ever considered.
    ]]
    if Tune.tourLabel and staging.hideProp and DoesEntityExist(entity) then
        state.hidden = entity
        SetEntityVisible(entity, false, false)
    end

    active = true
    Sport.print(('tuning %s against %s'):format(key, state.modelName))

    -- The tool takes the camera. The follow camera looks over the ped's shoulder, which is the one
    -- angle that cannot show whether a body is on a bench, and in the studio it has no ground to
    -- orient against at all - the first session rendered the inside of a forearm.
    camYaw, camPitch, camDist = 45.0, -20.0, 3.5
    openCam()
    updateCam(PlayerPedId())      -- placed before the first frame renders, or it flashes at 0,0,0

    apply(state)

    CreateThread(function()
        while active do
            for _, control in ipairs(CONTROLS_TO_BLOCK) do
                DisableControlAction(0, control, true)
            end

            -- Reported for the operator's benefit only. Nothing is clamped and nothing needs
            -- rescuing any more: an attached ped goes exactly where the offset says and cannot
            -- be blocked or pushed through anything.
            state.height = pedHeightAboveGround(state.studioFloor)
            drawStudioFloor(state)

            -- A two-handed prop has to follow the hands every frame, not only when a key moves.
            if HOLDS[state.holdIndex] == 'twoHanded' then
                updateTwoHanded(state)
            end

            draw(state)

            --[[
                BASE steps, which is what a single tap gives. Deliberately tiny: holding the key
                accelerates it up to six times, so these do not have to compromise between a
                nudge and a sweep, and G already covers the quarter turn.

                SHIFT is on top of that, for when the thing starts somewhere completely wrong.
            ]]
            local fast = IsDisabledControlPressed(0, KEY.faster)
            state.step = fast and 0.10 or 0.01
            local turn = fast and 10.0 or 1.0
            local moved = false

            --[[
                In 'model' mode the arrow keys change WHAT is held rather than where it is:
                left/right cycles the model, up/down cycles the bone. That is why nudge() and
                rotate() below return early there - there is no position being edited.
            ]]
            if state.mode == 'model' then
                local changed = false

                -- One press, one model. No repeat and no acceleration: a list of nine entries
                -- flies past at forty-five milliseconds a step, and each change spawns an
                -- object - so holding the key would be both useless and wasteful.
                if IsDisabledControlJustPressed(0, KEY.right) then
                    state.modelIndex = (state.modelIndex % #state.models) + 1
                    changed = true
                elseif IsDisabledControlJustPressed(0, KEY.left) then
                    state.modelIndex = state.modelIndex - 1
                    if state.modelIndex < 1 then state.modelIndex = #state.models end
                    changed = true
                end

                --[[
                    A NEW PROP STARTS STRAIGHT.

                    Inheriting the previous prop's angles is what makes placing one feel
                    impossible: cycle from a barbell you spent two minutes levelling to a
                    dumbbell and it arrives at the barbell's angles, which are wrong for it and
                    are not obviously wrong - so you tune from a worse starting point than zero.

                    So each model gets its own known-good starting values from
                    Config.Debug.tunePropDefaults, and zero when there is no entry. Zero is a
                    genuinely useful baseline: it is the bone's own orientation, which is what
                    the game itself uses for held objects.
                ]]
                if changed then
                    local choice = state.models[state.modelIndex]
                    local defaults = choice.model
                        and (Config.Debug.tunePropDefaults or {})[choice.model] or nil

                    state.propPos = defaults and defaults.pos or vector3(0.0, 0.0, 0.0)
                    state.propRot = defaults and defaults.rot or vector3(0.0, 0.0, 0.0)

                    -- Re-derive the hold for the new model: a decision that was right for a
                    -- barbell is wrong for a dumbbell, and carrying it over is how a small prop
                    -- ends up floating between the hands.
                    state.deriveHold = true

                    respawnProp(state)
                    moved = true
                end

                if IsDisabledControlJustPressed(0, KEY.up) then
                    state.boneIndex = (state.boneIndex % #BONES) + 1
                    state.bone = BONES[state.boneIndex].id
                    moved = true
                elseif IsDisabledControlJustPressed(0, KEY.down) then
                    state.boneIndex = state.boneIndex - 1
                    if state.boneIndex < 1 then state.boneIndex = #BONES end
                    state.bone = BONES[state.boneIndex].id
                    moved = true
                end
            end

            local function nudge(axis, amount)
                if state.mode == 'model' then return end

                local target = state.mode == 'anim' and 'animOffset' or 'propPos'
                local v = state[target]

                -- The prop sits in a hand: centimetres matter there and five-centimetre steps
                -- are useless, so its steps are a tenth of the animation's.
                local scaled = target == 'propPos' and amount * 0.1 or amount

                state[target] = vector3(
                    v.x + (axis == 'x' and scaled or 0.0),
                    v.y + (axis == 'y' and scaled or 0.0),
                    v.z + (axis == 'z' and scaled or 0.0))
                moved = true
            end

            -- The second return value is the acceleration factor: 1 on a tap, up to 6 while held.
            local pressed, factor

            pressed, factor = held(KEY.up, 'up')
            if pressed then nudge('y', state.step * factor) end

            pressed, factor = held(KEY.down, 'down')
            if pressed then nudge('y', -state.step * factor) end

            pressed, factor = held(KEY.right, 'right')
            if pressed then nudge('x', state.step * factor) end

            pressed, factor = held(KEY.left, 'left')
            if pressed then nudge('x', -state.step * factor) end

            pressed, factor = held(KEY.raise, 'raise')
            if pressed then nudge('z', state.step * factor) end

            pressed, factor = held(KEY.lower, 'lower')
            if pressed then nudge('z', -state.step * factor) end

            --[[
                Turn whichever thing is being edited.

                For the BODY there is only one meaningful angle, its heading. For a PROP all
                three matter: a barbell that is level but pointing the wrong way needs yaw, and
                one that is pointing right but tilted needs pitch or roll. So in prop mode R/F
                turn the SELECTED axis, and the axis key cycles which one.
            ]]
            local function rotate(amount)
                if state.mode == 'model' then return end

                -- BOTH the body and the prop turn on all three axes. The body used to have a
                -- heading and nothing else, which meant it could be swivelled but never tipped
                -- or rolled - so "I can only turn it one way" was exactly right.
                local axis = AXES[state.axisIndex]
                local target = state.mode == 'anim' and 'animRot' or 'propRot'
                local v = state[target]

                state[target] = vector3(
                    (v.x + (axis == 'x' and amount or 0.0)) % 360.0,
                    (v.y + (axis == 'y' and amount or 0.0)) % 360.0,
                    (v.z + (axis == 'z' and amount or 0.0)) % 360.0)

                moved = true
            end

            pressed, factor = held(KEY.turnCw, 'cw')
            if pressed then rotate(turn * factor) end

            pressed, factor = held(KEY.turnCcw, 'ccw')
            if pressed then rotate(-turn * factor) end

            -- A quarter turn per tap, and a half turn with SHIFT. This is the one that fixes
            -- "lying across the bench instead of along it" in a single press.
            if IsDisabledControlJustPressed(0, KEY.quarter) then
                rotate(fast and 180.0 or 90.0)
            end

            if IsDisabledControlJustPressed(0, KEY.axis) then
                state.axisIndex = (state.axisIndex % #AXES) + 1
            end

            --[[
                CENTRE THE PROP ON THE HAND. The two-handed fix.

                A barbell's origin is at one END of the bar, so it hangs off the hand and no
                amount of nudging brings both hands onto it. Subtracting the model's bounding-box
                centre puts the MIDDLE of the bar at the hand, which is where a two-handed grip
                belongs, and turns an impossible placement into an obvious one.

                Pressing it again toggles back, so the effect can be judged both ways.
            ]]
            --[[
                HOW THE PROP IS HELD. Three answers, and for a long object only the third works.

                  hand       attached at the bone. Right for a dumbbell.
                  centred    attached, with the model's MIDDLE on the bone instead of its origin.
                             Right for anything whose origin is at one end.
                  twoHanded  not attached: repositioned every frame to span BOTH hands. The only
                             thing that works for a barbell, because a bar attached to one hand
                             inherits that hand's tilt and no offset is right for both at once.
            ]]
            if IsDisabledControlJustPressed(0, KEY.hold) then
                state.holdIndex = (state.holdIndex % #HOLDS) + 1
                moved = true
            end

            --[[
                STRAIGHTEN. Snap every angle to the nearest 90 degrees.

                This is the one that makes a prop easy to place. Nudging a barbell to 87.5 by
                hand and calling it level is how you end up with a bar that looks subtly wrong
                from every angle; snapping turns "nearly right" into "exactly right" in one
                press, and the number that gets pasted into the config is a round one.
            ]]
            if IsDisabledControlJustPressed(0, KEY.straight) then
                local function snap(value)
                    return (math.floor(value / 90.0 + 0.5) * 90.0) % 360.0
                end

                local target = state.mode == 'anim' and 'animRot' or 'propRot'
                local v = state[target]
                state[target] = vector3(snap(v.x), snap(v.y), snap(v.z))

                moved = true
            end

            -- Back to zero, for whichever set of numbers is being edited. Faster than nudging
            -- back when a placement has gone somewhere silly.
            if IsDisabledControlJustPressed(0, KEY.reset) then
                if state.mode == 'anim' then
                    state.animOffset = vector3(0.0, 0.0, 0.0)
                    state.animRot = vector3(0.0, 0.0, 0.0)
                elseif state.mode == 'prop' then
                    state.propPos = vector3(0.0, 0.0, 0.0)
                    state.propRot = vector3(0.0, 0.0, 0.0)
                end
                moved = true
            end

            -- body -> prop position -> which prop -> back to body
            if IsDisabledControlJustPressed(0, KEY.mode) then
                if state.mode == 'anim' then
                    state.mode = 'prop'
                elseif state.mode == 'prop' then
                    state.mode = 'model'
                else
                    state.mode = 'anim'
                end
            end

            if IsDisabledControlJustPressed(0, KEY.print) then
                printBlock(state)
            end

            if IsDisabledControlJustPressed(0, KEY.save) then
                saveBlock(state)
            end

            if IsDisabledControlJustPressed(0, KEY.quit) then
                -- No step request: the tour reads that as "stop touring" rather than "advance".
                Tune.stepRequest = nil
                active = false
            end

            --[[
                The review keys. They only do anything while a tour is running - `tourLabel` is
                what says one is - because outside a tour there is nothing to advance to and a
                stray 1 should not end an alignment somebody is halfway through.
            ]]
            if Tune.tourLabel then
                if IsDisabledControlJustPressed(0, KEY.good) then
                    Tune.verdict = true
                    Tune.stepRequest = 1
                    active = false
                elseif IsDisabledControlJustPressed(0, KEY.bad) then
                    Tune.verdict = false
                    Tune.stepRequest = 1
                    active = false
                elseif IsDisabledControlJustPressed(0, KEY.next) then
                    Tune.verdict = nil
                    Tune.stepRequest = 1
                    active = false
                elseif IsDisabledControlJustPressed(0, KEY.prev) then
                    Tune.verdict = nil
                    Tune.stepRequest = -1
                    active = false
                end
            end

            if moved then apply(state) end

            -- Aimed at the ped rather than at the prop: the ped is what has to look right, and
            -- when it is attached the prop comes along in frame anyway.
            updateCam(PlayerPedId())

            Wait(0)
        end

        closeCam()

        -- Put back anything the review hid. Before the prop is deleted, because a studio prop is
        -- about to stop existing and an invisible leftover in a real gym would be a real bug.
        if state.hidden and DoesEntityExist(state.hidden) then
            SetEntityVisible(state.hidden, true, false)
        end

        -- Leave nothing behind: the prop, the animation and the ped's tasks.
        if state.propHandle and DoesEntityExist(state.propHandle) then
            SetEntityAsMissionEntity(state.propHandle, true, true)
            DeleteEntity(state.propHandle)
        end

        -- Tasks first, then detach: detaching while the lying animation still drives the
        -- skeleton reads as a fall rather than as getting up.
        local ped = PlayerPedId()
        ClearPedTasks(ped)

        if IsEntityAttached(ped) then
            DetachEntity(ped, true, true)
            SetEntityCollision(ped, true, true)
        end

        --[[
            A studio session ends by going home, not by standing up.

            Putting the ped on the ground under its current position would drop them from three
            hundred metres over the sea. The prop is destroyed first, because a frozen invisible
            bench left floating in the sky is the sort of litter nobody ever finds again.
        ]]
        if state.studioProp then
            if DoesEntityExist(state.studioProp) then
                SetEntityAsMissionEntity(state.studioProp, true, true)
                DeleteEntity(state.studioProp)
            end

            local home = state.origin
            SetEntityCoords(ped, home.x, home.y, home.z, false, false, false, false)
            RequestCollisionAtCoord(home.x, home.y, home.z)
            Wait(300)

            FreezeEntityPosition(ped, false)
            SetEntityInvincible(ped, false)
            Sport.print('studio closed, put you back where you were')
        else
            FreezeEntityPosition(ped, false)

            local coords = GetEntityCoords(ped)
            local found, groundZ = GetGroundZFor_3dCoord(coords.x, coords.y, coords.z + 2.0, false)
            if found then
                SetEntityCoords(ped, coords.x, coords.y, groundZ + 1.0, false, false, false, false)
            end
        end

        if state.dict then RemoveAnimDict(state.dict) end

        Sport.print('tuning stopped')

        -- LAST, after every piece of teardown above. The tour waits on this before starting the
        -- next prop; releasing it any earlier would let the next session's prop be deleted by the
        -- cleanup of this one.
        busy = false
    end)

    return true
end

-- ---------------------------------------------------------------------------------------
-- The command
-- ---------------------------------------------------------------------------------------

CreateThread(function()
    local name = Config.Commands.tune
    if type(name) ~= 'string' or name == '' then return end

    RegisterCommand(name, function(_, args)
        if not State.devGate() then return end

        local key = args and args[1]

        if not key or key == '' then
            print(L('cmd.tune_usage', name))
            print('  Known equipment: ' .. table.concat(Equipment.keys, ', '))
            print(('^5  /%s <exercise> here^7  aligns against the object in front of you, whatever')
                :format(name))
            print('^5  it is - no search, no studio copy, no model name to get right.^7')
            return
        end

        -- The second argument targets one model, for working through an exercise's props in turn.
        Tune.start(key, args[2])
    end, false)

    TriggerEvent('chat:addSuggestion', '/' .. name, L('cmd.tune'), {
        { name = 'equipment', help = table.concat(Equipment.keys, ' | ') },
        { name = 'model', help = "optional: a model name, or 'here' for the prop in front of you" },
    })
end)

-- ---------------------------------------------------------------------------------------
-- /vsportgoto
-- ---------------------------------------------------------------------------------------
--
-- Hop between machines without walking. With no argument it lists what is streamed in around
-- you, grouped by exercise, so you can see what there is to align before choosing.

CreateThread(function()
    local name = Config.Commands.goto_
    if type(name) ~= 'string' or name == '' then return end

    RegisterCommand(name, function(_, args)
        if not State.devGate() then return end

        local key = args and args[1]

        -- No argument: what is there to go to?
        if not key or key == '' then
            local coords = GetEntityCoords(PlayerPedId())
            local found = {}

            for _, entity in ipairs(GetGamePool('CObject')) do
                local hash = GetEntityModel(entity)
                local holders = Equipment.byModel[hash]

                if holders then
                    local at = GetEntityCoords(entity)
                    local dx, dy, dz = at.x - coords.x, at.y - coords.y, at.z - coords.z
                    local distance = math.sqrt(dx * dx + dy * dy + dz * dz)

                    for _, holder in ipairs(holders) do
                        if not found[holder] or distance < found[holder] then
                            found[holder] = distance
                        end
                    end
                end
            end

            print('^5==== v-sport: equipment streamed in around you ====^7')

            local any = false
            for _, holder in ipairs(Equipment.keys) do
                if found[holder] then
                    any = true
                    print(('  %-16s nearest %5.1fm    /%s %s')
                        :format(holder, found[holder], name, holder))
                end
            end

            if not any then
                print('  nothing. Get closer to a gym - only streamed props can be found.')
            end

            print('^5==================================================^7')
            return
        end

        local entry = Equipment.get(key)
        if not entry then
            print(L('cmd.no_equipment', key))
            print('  Known equipment: ' .. table.concat(Equipment.keys, ', '))
            return
        end

        -- A named model, so a specific one of an exercise's props can be walked to and then
        -- tuned. Without this the pair of commands can only ever reach the closest.
        local onlyModel = args[2]

        -- In its own thread: the map search below teleports and waits for streaming, which can
        -- take several seconds per location.
        CreateThread(function()
        local entity, hash, distance = nearestPropFor(key, onlyModel)

        -- Nothing loaded nearby does not mean nothing on the map. Go and look.
        if not entity then
            Compat.notify(L('tune.searching'), 'primary')
            entity, hash, distance = searchTheMap(key, onlyModel)
        end

        if not entity then
            Compat.notify(L('tune.no_prop', onlyModel or key), 'error')
            print(("^3[v-sport] %s is not streamed in near you and none of the"):format(
                onlyModel or key))
            print('^3  Config.Debug.searchSpots locations have one either. Add a location there^7')
            print('^3  if you know where to find it - /' ..
                (Config.Commands.spot or 'vsportspot') .. ' prints coordinates.^7')
            return
        end

        if goTo(entity, entry, hash) then
            --[[
                The MODEL NAME and the distance, not just the distance.

                Benches of different models stand two metres apart at Muscle Beach, so being
                moved "3m" tells you nothing about whether the right one was targeted - and
                landing in the same spot twice looks like the filter being ignored when it is
                simply the nearest one of that model being next to the last.

                Naming what was found makes that answerable instead of a guess.
            ]]
            local found = onlyModel
            if not found then
                for _, model in ipairs(entry.models or {}) do
                    if type(model) == 'string' and GetHashKey(model) == hash then
                        found = model
                        break
                    end
                end
            end

            Compat.notify(L('tune.teleported_to', found or '?', distance), 'success')
            Sport.print(('moved %.1fm to %s'):format(distance, found or tostring(hash)))
        end
        end)
    end, false)

    TriggerEvent('chat:addSuggestion', '/' .. name, L('cmd.goto'), {
        { name = 'equipment', help = 'blank lists what is nearby' },
        { name = 'model', help = 'optional: one specific prop model' },
    })
end)

-- ---------------------------------------------------------------------------------------
-- /vsportfind
-- ---------------------------------------------------------------------------------------
--
-- The answer to "it says there is none and I do not believe it". Sweeps the whole map for one
-- model and prints every place it exists, as searchSpots lines to paste - so this runs once and
-- /vsportgoto knows about it forever after.

CreateThread(function()
    local name = Config.Commands.find
    if type(name) ~= 'string' or name == '' then return end

    RegisterCommand(name, function(_, args)
        if not State.devGate() then return end

        if sweeping then
            print('^3[v-sport] a sweep is already running.^7')
            return
        end

        args = args or {}
        local models = {}

        --[[
            No argument, or `all`, sweeps for EVERY model the catalogue mentions.

            That is the useful default, because the seven minutes is the travelling: answering one
            model or forty costs the same walk. Running it once tells you what your map actually
            has and what is simply not placed anywhere, which is the question behind every "it
            says there is none and I do not believe it".
        ]]
        if args[1] == 'help' then
            print(L('cmd.find_usage', name))
            print('^3  Blank or "all" sweeps every catalogue model in one pass.^7')
            return
        end

        if #args == 0 or args[1] == 'all' then
            local seen = {}
            for _, key in ipairs(Equipment.keys) do
                for _, model in ipairs(Equipment.get(key).models or {}) do
                    if type(model) == 'string' and not seen[model] then
                        seen[model] = true
                        models[#models + 1] = model
                    end
                end
            end
            print(('^5[v-sport] sweeping for all %d catalogue models.^7'):format(#models))
        else
            for _, model in ipairs(args) do models[#models + 1] = model end
        end

        CreateThread(function()
            local found, stops = sweepForModels(models)
            stops = stops or 0

            local located, absent = {}, {}
            for _, model in ipairs(models) do
                local places = found[model]
                if places and #places > 0 then
                    located[#located + 1] = { model = model, places = places }
                elseif places then
                    absent[#absent + 1] = model
                end
            end

            print('^5================ v-sport: sweep result ================^7')

            if #located > 0 then
                print(('  %d model(s) located. Paste into Config.Debug.searchSpots:'):format(#located))
                print('')
                for _, hit in ipairs(located) do
                    -- The location with the most of them is the one worth going to.
                    local best = hit.places[1]
                    for _, place in ipairs(hit.places) do
                        if place.count > best.count then best = place end
                    end

                    print(("        { name = '%s x%d', coords = vector3(%.2f, %.2f, %.2f) },")
                        :format(hit.model, best.count,
                            best.coords.x, best.coords.y, best.coords.z))

                    if #hit.places > 1 then
                        print(("          -- also in %d other place(s)"):format(#hit.places - 1))
                    end
                end
                print('')
            end

            --[[
                NOT SEEN, not "does not exist". The distinction matters and getting it wrong
                already cost a wrong answer: at a 400 metre step this list once contained two
                benches the operator had used minutes earlier, because the step was wider than the
                distance at which small props stream in.

                A hit is a fact. A miss is only ever "not seen at the stops that were made".
            ]]
            if #absent > 0 then
                print(('^3  %d model(s) were NOT SEEN at any of the %d stops:^7')
                    :format(#absent, stops))
                for _, model in ipairs(absent) do
                    print('^3    ' .. model .. '^7')
                end
                print('')
                print('^1  THIS IS NOT PROOF THEY DO NOT EXIST.^7')
                print('^3  Small props stream in at roughly 150m. Anything sitting between two^7')
                print('^3  stops is invisible to the sweep. To settle one of these, go to the^7')
                print('^3  district it should be in and run /' ..
                    (Config.Commands.goto_ or 'vsportgoto') .. ' <exercise> <model>.^7')
            end

            print('^5======================================================^7')

            Compat.notify(L('tune.swept', #located, #models),
                #located > 0 and 'success' or 'error')
        end)
    end, false)

    TriggerEvent('chat:addSuggestion', '/' .. name, L('cmd.find'), {
        { name = 'models', help = 'blank or "all" sweeps for every catalogue model' },
    })
end)

AddEventHandler('onResourceStop', function(resource)
    if resource ~= Sport.resource then return end
    Tune.stop()
    Tune.cancelSweep()
end)
