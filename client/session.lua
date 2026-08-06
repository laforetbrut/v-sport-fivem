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

--[[
    THE LAST PIECE OF EQUIPMENT A WORKOUT ACTUALLY USED.

    Kept because the alignment tool could not otherwise reach some of it. A target resource finds
    equipment through its own raycast and will happily start a session on a prop that
    GetGamePool('CObject') does not list and that a shape test does not return - whatever the reason,
    the fact is a bench that can be trained on and cannot be tuned, which is the worst combination:
    the placement is wrong and there is no way to measure a better one.

    So the resource remembers what it just used. `/vsportprop` checks here before giving up and
    conjuring a studio copy, which means anything a player can train on is something an admin can
    align - by definition, because the session proved the handle works.
]]
local lastProp = nil            -- { entity, model, key }

--- The equipment the last workout used, or nil. The entity may have unstreamed since.
function Session.lastProp()
    if not lastProp then return nil end
    if not lastProp.entity or not DoesEntityExist(lastProp.entity) then return nil end
    return lastProp.entity, lastProp.model, lastProp.key
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
---
--- `anywhere` says this is an exercise being done with no equipment. The server checks the key
--- against its own Config.Anywhere.allowed rather than believing the flag.
local function requestPermission(key, coords, anywhere)
    nextRequest = nextRequest + 1
    local id = nextRequest

    local entry = { promise = promise.new(), done = false }
    pending[id] = entry

    TriggerServerEvent('vsport:server:RequestSession', id, key,
        { x = coords.x, y = coords.y, z = coords.z }, anywhere == true)

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

    -- Config.Notifications.cooldownActive decides whether this one speaks. It was declared as a
    -- switch and read by nothing, so turning it off did nothing; the message was gated by
    -- requirementFailed along with every other refusal.
    local left = State.cooldownLeft(entry.key)
    if left > 0 then
        if Config.Notifications.cooldownActive == false then return '' end
        return L('notify.cooldown', Sport.duration(left))
    end

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
            -- `jobType` too, matching the server's own check. Without it a require written
            -- against a job TYPE passed on the server and was refused here, so the player was
            -- told "this is not for you" about equipment they were entitled to use.
            if roles.job ~= require_.job
                and roles.jobType ~= require_.job
                and ('gang:' .. roles.gang) ~= require_.job then
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
    The dictionary to actually use for this ped.

    Most of the workout dictionaries are `...@male@...` and most have a `@female@` twin, so a
    female character gets the animation that was built for her rather than a man's. Not all of
    them do - the bench press and the muscle flex have no gendered variant at all - which is why
    this returns a CANDIDATE and the caller falls back to the configured name when it will not
    load.
]]
local function genderedDict(dict)
    if type(dict) ~= 'string' then return nil end
    if not dict:find('@male@', 1, true) then return nil end
    if IsPedMale(PlayerPedId()) then return nil end

    return (dict:gsub('@male@', '@female@'))
end

--- The dictionary that is actually loaded and ready, or nil. Her variant if there is one, his
--- otherwise. Factored out because two animation paths need the identical resolution.
local function resolveDict(dict)
    local wanted = genderedDict(dict)
    if wanted and loadAnimDict(wanted) then return wanted end
    if loadAnimDict(dict) then return dict end
    return nil
end

--[[
    ---------------------------------------------------------------------------------------
    SCENARIO PROPS, AND WHY THEY HAVE TO BE HUNTED DOWN
    ---------------------------------------------------------------------------------------

    A scenario like WORLD_HUMAN_MUSCLE_FREE_WEIGHTS spawns its own dumbbell and puts it in the
    ped's hands. That prop belongs to the scenario, not to this resource, and
    `ClearPedTasksImmediately` ends the task by DETACHING it - which drops a live dumbbell on
    the floor, permanently, once per workout. On a busy gym that is a pile of them by the end of
    the evening.

    There is no native that says "end this scenario and take its prop with it". So the props are
    identified by comparing what is attached to the ped BEFORE the scenario starts against what
    is attached while it is running, and the difference is deleted by handle after the task is
    cleared.

    The order matters and is the whole trick: the snapshot has to be taken while the prop is
    still attached, because once it has been dropped there is nothing linking it to the ped.
]]

--- Every object currently attached to `ped`, as a set of handles.
local function attachedSet(ped)
    local set = {}

    for _, object in ipairs(GetGamePool('CObject')) do
        if IsEntityAttachedToEntity(object, ped) then
            set[object] = true
        end
    end

    return set
end

--[[
    Delete an object this resource caused to exist.

    NO Wait IN HERE, DELIBERATELY. This is reached from every path that ends a session, and two
    of those - `onResourceStop` and a game-event handler - cannot yield. A `Wait` on one of them
    fails with "Execution of function reference in script host failed", which says nothing about
    where it came from and is a miserable thing to debug.

    So control is requested and not waited for. Requesting it is enough in practice for an
    object this client created a moment ago, and if the request has not landed yet the local
    delete still removes it for the player who was holding it - which is the one who would
    otherwise be looking at a dumbbell on the floor.
]]
local function deleteObject(object)
    if not object or object == 0 then return end
    if not DoesEntityExist(object) then return end

    if not NetworkHasControlOfEntity(object) then
        NetworkRequestControlOfEntity(object)
    end

    SetEntityAsMissionEntity(object, true, true)
    DeleteEntity(object)
end

-- ---------------------------------------------------------------------------------------
-- Props we create ourselves
-- ---------------------------------------------------------------------------------------
--
--  AN ANIMATION NEVER CARRIES A PROP. Only a scenario does.
--
--  That is the single fact behind "the player has nothing in his hands": TaskPlayAnim moves the
--  skeleton and nothing else, so an exercise driven by an animation has empty hands no matter
--  how good the animation is. A scenario spawns and holds its own prop, which is why the
--  weight-bearing exercises prefer one.
--
--  Where neither works - a custom exercise, an animation with no scenario twin - the prop can
--  be created and attached here instead. `props` on a catalogue entry:
--
--      props = {
--          { model = 'prop_barbell_01', bone = 57005,
--            pos = vector3(0.0, 0.0, 0.0), rot = vector3(0.0, 0.0, 0.0) },
--      }
--
--  Bones: 57005 is the right prop hand, 36029 the left. Offsets are found by eye, and a prop
--  attachment tool is far quicker than guessing.

local BONE_RIGHT_HAND = 57005       -- PH_R_Hand
local BONE_LEFT_HAND  = 36029       -- PH_L_Hand

--[[
    The flag for a PLACED animation, and it is two flags added together.

        1        AF_LOOPING                  keep playing until the tasks are cleared
        262144   AF_USE_KINEMATIC_PHYSICS    the ped FOLLOWS the animation instead of being
                                             resolved against collision

    The second one is not optional, and leaving it out produces a very specific and very
    confusing bug: without it the ped's physics capsule fights the placement. Lowering the body
    towards a bench appears to do nothing for several nudges - the ground is holding the capsule
    up - and then the accumulated offset wins all at once and the character drops through the
    map.

    With kinematic physics the body goes exactly where it is told, every nudge moves it by
    exactly that much, and it can be tuned by eye. It also means nothing stops a placement that
    IS below the ground, which is why the alignment tool guards against that separately.
]]
local PLACED_ANIM_FLAG = 1 + 262144

--[[
    Where a model's geometric centre sits relative to its own origin.

    THIS IS THE FIX FOR TWO-HANDED PROPS. A barbell's origin is at one END of the bar, not in
    the middle, so attaching it to a hand at (0,0,0) hangs the whole two-metre bar off that hand
    and no amount of nudging makes both hands grip it - the bar simply is not where the hands
    are.

    GetModelDimensions gives the model's bounding box in its own space. Subtracting the box's
    centre from the attachment offset puts the MIDDLE of the bar at the hand, which is where the
    grip of a two-handed object belongs.

    Returns nil when the model is not loaded, in which case the offset is used unchanged.
]]
local function modelCentre(hash)
    local ok, minimum, maximum = pcall(function()
        return GetModelDimensions(hash)
    end)

    if not ok or type(minimum) ~= 'vector3' or type(maximum) ~= 'vector3' then
        return nil
    end

    return vector3(
        (minimum.x + maximum.x) * 0.5,
        (minimum.y + maximum.y) * 0.5,
        (minimum.z + maximum.z) * 0.5)
end

--[[
    ---------------------------------------------------------------------------------------
    TWO-HANDED PROPS: SPAN THE HANDS, DO NOT HANG OFF ONE
    ---------------------------------------------------------------------------------------

    A barbell attached to a hand bone inherits that hand's position AND its rotation. During a
    bench press the hands are not level with each other for most of the movement, so the bar
    tilts, sinks through one wrist and sticks out past the other - and no offset fixes it,
    because there is no single offset that is right for both hands at once. Tuning it by hand is
    not hard, it is impossible.

    So a two-handed prop is not attached at all. It is placed every frame:

        position  the midpoint between the two hand bones
        heading   the direction from one hand to the other
        pitch     the height difference between them

    The bar then spans the hands exactly, for the whole movement, with nothing to tune. What is
    left to configure is `rotOffset`, which only exists because a model's long axis is not always
    its Y - one or two round numbers instead of six fiddly ones.
]]
--[[
    The yaw that turns a model's LONGEST axis onto its Y, cached per model.

    THIS IS WHY TWO-HANDED PROPS WOULD NOT LINE UP. The maths below points the bar's local Y at
    the far hand, which is correct only if the bar is actually long in Y. `prop_barbell_01` is
    long in X, so it came out perpendicular to the hands - a diagonal bar through the chest,
    which looks exactly like a positioning problem and cannot be fixed by positioning.

    The bounding box already says which axis is longest, so the correction is derived rather
    than configured. Nothing to tune, and it is right for any model, including ones nobody has
    tried yet.
]]
local longAxisYaw = {}

function Session.longAxisYaw(hash)
    if longAxisYaw[hash] ~= nil then return longAxisYaw[hash] end

    local ok, minimum, maximum = pcall(function()
        return GetModelDimensions(hash)
    end)

    local yaw = 0.0

    if ok and type(minimum) == 'vector3' and type(maximum) == 'vector3' then
        local sizeX = maximum.x - minimum.x
        local sizeY = maximum.y - minimum.y

        -- Long in X: turn it a quarter so its length runs along Y, which is the axis the
        -- hand-to-hand direction is applied to.
        if sizeX > sizeY then yaw = 90.0 end
    end

    longAxisYaw[hash] = yaw
    return yaw
end

local function updateTwoHanded(object, rotOffset, posOffset)
    if not object or not DoesEntityExist(object) then return end

    local ped = PlayerPedId()

    -- GetPedBoneCoords takes the bone ID directly, so there is no index lookup to get wrong.
    local right = GetPedBoneCoords(ped, BONE_RIGHT_HAND, 0.0, 0.0, 0.0)
    local left = GetPedBoneCoords(ped, BONE_LEFT_HAND, 0.0, 0.0, 0.0)

    local dx, dy, dz = right.x - left.x, right.y - left.y, right.z - left.z
    local flat = math.sqrt(dx * dx + dy * dy)

    -- Hands on top of each other: no direction to derive, so leave the last orientation alone
    -- rather than snapping the bar to something arbitrary.
    if flat < 0.01 then return end

    local offset = rotOffset or vector3(0.0, 0.0, 0.0)
    local heading = GetHeadingFromVector_2d(dx, dy)
    local pitch = -math.deg(math.atan(dz, flat))

    -- Turn the model's long axis onto the hand-to-hand line, whichever axis that happens to be.
    local correction = Session.longAxisYaw(GetEntityModel(object))

    SetEntityCoords(object,
        (right.x + left.x) * 0.5,
        (right.y + left.y) * 0.5,
        (right.z + left.z) * 0.5,
        false, false, false, false)

    SetEntityRotation(object,
        pitch + offset.x,
        offset.y,
        heading + correction + offset.z,
        2, true)

    --[[
        A FINE OFFSET, IN THE BAR'S OWN FRAME.

        Everything above is derived, which is what makes two-handed props work at all - but it
        also left nothing to adjust, and a grip is never exactly at the bone. So `pos` is applied
        afterwards, in the object's LOCAL space now that it is oriented:

            Y   slides the bar along its own length
            X   moves it across, towards or away from the body
            Z   lifts it off the hands, which is the one that is usually wanted

        Local space rather than world is the whole point: +Z is "up out of the palms" whatever
        direction the player happens to be facing, so a number tuned once stays right.

        Skipped entirely when it is zero, which is the common case.
    ]]
    if posOffset and (posOffset.x ~= 0.0 or posOffset.y ~= 0.0 or posOffset.z ~= 0.0) then
        local world = GetOffsetFromEntityInWorldCoords(object,
            posOffset.x, posOffset.y, posOffset.z)
        SetEntityCoords(object, world.x, world.y, world.z, false, false, false, false)
    end
end

--[[
    Create whatever `staging.props` asks for.

    Returns two lists: every handle created, for cleanup, and the subset that has to be driven
    from both hands every frame.
]]
local function attachProps(staging)
    local created = {}
    local twoHanded = {}
    if type(staging.props) ~= 'table' then return created, twoHanded end

    local ped = PlayerPedId()
    local coords = GetEntityCoords(ped)

    for _, spec in ipairs(staging.props) do
        local hash = type(spec.model) == 'number' and spec.model or GetHashKey(spec.model or '')

        if hash and hash ~= 0 and IsModelValid(hash) then
            RequestModel(hash)

            local deadline = GetGameTimer() + 3000
            while not HasModelLoaded(hash) and GetGameTimer() < deadline do
                Wait(50)
            end

            if HasModelLoaded(hash) then
                local object = CreateObject(hash, coords.x, coords.y, coords.z,
                    true,       -- networked, so other players see it
                    true,       -- a mission entity, so the streamer will not take it away
                    false)

                created[#created + 1] = object

                if spec.twoHanded then
                    --[[
                        NOT ATTACHED. Repositioned every frame from both hand bones by
                        updateTwoHanded above, which is the only way one object can span two
                        hands that move independently of each other.

                        Collision and damage off: it is a visual, and a two-metre bar with
                        physics lying across a prone player is a catapult.
                    ]]
                    SetEntityCollision(object, false, false)
                    SetEntityCanBeDamaged(object, false)

                    twoHanded[#twoHanded + 1] = {
                        handle = object,
                        rotOffset = spec.rotOffset,
                        -- `pos` is the fine offset in the bar's own frame, not an attachment
                        -- point: there is no attachment to offset from.
                        posOffset = spec.pos,
                    }

                    updateTwoHanded(object, spec.rotOffset, spec.pos)
                    Sport.debug('two-handed prop:', tostring(spec.model))
                else
                    local pos = spec.pos or vector3(0.0, 0.0, 0.0)
                    local rot = spec.rot or vector3(0.0, 0.0, 0.0)

                    -- `centre = true` moves the model's middle onto the bone. See modelCentre.
                    if spec.centre then
                        local middle = modelCentre(hash)
                        if middle then
                            pos = vector3(pos.x - middle.x, pos.y - middle.y, pos.z - middle.z)
                        end
                    end

                    AttachEntityToEntity(object, ped,
                        GetPedBoneIndex(ped, spec.bone or BONE_RIGHT_HAND),
                        pos.x, pos.y, pos.z,
                        rot.x, rot.y, rot.z,
                        true,       -- p9
                        true,       -- useSoftPinning
                        false,      -- collision: off, or it fights the ped
                        true,       -- isPedAttachment
                        1,          -- rotationOrder
                        true)       -- syncRotation

                    Sport.debug('attached prop:', tostring(spec.model))
                end
            else
                Sport.warn(("the prop model '%s' would not load"):format(tostring(spec.model)))
            end

            -- Either way, stop holding the model resident.
            SetModelAsNoLongerNeeded(hash)
        elseif spec.model then
            Sport.warn(("'%s' is not a valid model"):format(tostring(spec.model)))
        end
    end

    return created, twoHanded
end

--[[
    Drive the two-handed props for as long as this session is the running one.

    Per frame, and it has to be: the hands move every frame, so anything slower shows the bar
    lagging behind them. It is two bone reads and two setters per prop, which is nothing next to
    the minigame loop already running alongside it.

    The loop ends by itself when `current` stops being this session, so no path that ends a
    workout has to remember to stop it.
]]
local function startTwoHandedLoop(session)
    if #session.twoHanded == 0 then return end

    CreateThread(function()
        while current == session do
            for _, item in ipairs(session.twoHanded) do
                updateTwoHanded(item.handle, item.rotOffset, item.posOffset)
            end
            Wait(0)
        end
    end)
end

--[[
    Keep the animation alive.

    The game cancels an ambient animation on its own for reasons a script does not get told
    about - a stray input the engine handles below the control layer, a nearby event, a task
    the AI decided to insert. When that happens mid-workout the player is left standing in the
    middle of a session, which reads as a broken resource.

    So it is checked a few times a second and restarted if it stopped. Cheap: one native, and
    only while a placed animation is running.
]]
local function startAnimWatchdog(session, dict, clip)
    if type(dict) ~= 'string' or type(clip) ~= 'string' then return end

    CreateThread(function()
        -- Let the first blend finish before judging whether it is playing.
        Wait(500)

        while current == session do
            local ped = PlayerPedId()

            if not IsEntityPlayingAnim(ped, dict, clip, 3) then
                Sport.debug('animation stopped by itself; restarting')
                TaskPlayAnim(ped, dict, clip,
                    8.0, -8.0, -1, PLACED_ANIM_FLAG, 0.0, false, false, false)
            end

            Wait(400)
        end
    end)
end

--[[
    Start a scenario, and prove it took.

    Returns `before, 'scenario'` when it is running, and `before, nil` when it refused - a
    scenario declines silently for reasons a script cannot see from here: the geometry does not
    fit, the point is taken, the prop is the wrong shape. The caller then falls through to the
    animation, which always plays something.

    WHICH SCENARIOS ARE PLACED ON THE PROP, AND WHICH PLAY WHERE THE PED STANDS. The prefix says
    it, and the game means it:

        PROP_*   owns a prop and expects to be given its position. A bench press or a chin-up
                 needs the bar and the body to line up, so TaskStartScenarioAtPosition.
        WORLD_*  needs nothing but a patch of ground. Free weights, jogging, yoga. Plays where
                 the ped already is, which is where the offset put them.

    So the mode is derived from the name rather than configured: one fewer field to get wrong.
]]
local function startScenario(staging, entity, before)
    local ped = PlayerPedId()
    local atProp = staging.scenario:sub(1, 5) == 'PROP_'

    if atProp and entity and DoesEntityExist(entity) then
        local at = GetEntityCoords(entity)
        local heading = GetEntityHeading(entity) + (tonumber(staging.scenarioHeading) or 0.0)

        --[[
            THE DURATION HAS TO BE -1, AND THIS COST AN ENTIRE BROKEN VERSION.

            The seventh argument is `timeToLeave`, in MILLISECONDS. Below zero sets the engine's
            IdleForever flag; a positive number is a timeout; and **0 means zero milliseconds**,
            so the scenario starts and ends on the same frame and the player simply stands there.

            It is NOT the same convention as TaskStartScenarioInPlace below, where 0 is the usual
            "no timeout". Two natives, two meanings, one number.
        ]]
        TaskStartScenarioAtPosition(ped, staging.scenario,
            at.x, at.y, at.z, heading % 360.0,
            -1,         -- timeToLeave: below zero is IdleForever
            true,       -- sittingScenario: the ped is placed ON the prop
            true)       -- teleport rather than walk

        Sport.debug('scenario at prop:', staging.scenario)
    else
        -- A WORLD_ scenario, a static Config.Spots entry, or an exercise done in the open.
        -- Here 0 is the "no timeout" value - the opposite of the native above.
        TaskStartScenarioInPlace(ped, staging.scenario, 0, true)
        Sport.debug('scenario in place:', staging.scenario)
    end

    --[[
        `IsPedUsingAnyScenario` is not present in every server build, and calling a native that is
        not there is a nil call - which surfaces as the same unhelpful "function reference failed"
        error rather than as a missing-native message.

        Resolved defensively, and when neither check exists the scenario is assumed to have
        worked. Assuming success is the right direction: the alternative is falling back to an
        animation that was already the worse option.
    ]]
    local usingScenario = IsPedUsingAnyScenario or IsPedActiveInScenario

    if type(usingScenario) ~= 'function' then
        Wait(300)
        Sport.debug('cannot verify the scenario on this build; assuming it started')
        return before, 'scenario'
    end

    local deadline = GetGameTimer() + 600
    while GetGameTimer() < deadline do
        if usingScenario(ped) then return before, 'scenario' end
        Wait(50)
    end

    Sport.warn(('the scenario %s would not start; falling back to the animation')
        :format(staging.scenario))
    ClearPedTasks(ped)

    return before, nil
end

--[[
    Start the exercise animation.

    Three routes, tried in this order: the game's own scenario when the entry prefers one, a
    placed animation with our own props, then a plain animation. Any of them can fail on a given
    map or build, and none failing stops the session - the minigame is the workout, the animation
    is the dressing.

    Returns the set of objects that were attached to the ped BEFORE anything started, for
    stopAnimation to diff against.
]]
local function startAnimation(staging, entity)
    local ped = PlayerPedId()
    local before = attachedSet(ped)

    --[[
        PROP SCENARIOS COME FIRST WHEN THE ENTRY ASKS FOR IT, AND THEY HAVE TO BE PLACED.

        This is the difference between a bench press that works and one that does not.

        `amb@prop_human_seat_muscle_bench_press@base` is a real lying bench press, but it is
        the animation half of a PROP_ scenario, and playing it with TaskPlayAnim gives two
        problems at once, both visible immediately:

          * The clip's root is the SCENARIO POINT, not the ped. Played in place it lies the ped
            down wherever they happen to be standing, at whatever heading they happen to have -
            which is how you get somebody lying across the bench at ninety degrees, half a
            metre off it.

          * The barbell belongs to the scenario, not to the clip. TaskPlayAnim spawns nothing,
            so the ped presses thin air.

        TaskStartScenarioAtPosition solves both. Given the prop's own position and heading it
        places the ped on the bench, in the right direction, and spawns the barbell. `sitting`
        and `teleport` are both true: this is a seated scenario and the ped has to be moved onto
        it rather than walking there.
    ]]
    --[[
        WHICH SCENARIOS ARE PLACED ON THE PROP, AND WHICH PLAY WHERE THE PED STANDS.

        The prefix says it, and the game means it:

            PROP_*   the scenario owns a prop and expects to be given its position. A bench
                     press or a chin-up needs the bench and the bar to line up with the body,
                     so it goes through TaskStartScenarioAtPosition.

            WORLD_*  the scenario needs nothing but a patch of ground. Free weights, jogging,
                     yoga. It plays where the ped already is, which is where the offset put
                     them, so TaskStartScenarioInPlace is right and using the prop's position
                     would drag them into the middle of the rack.

        So the mode is derived from the name rather than configured. One fewer field to get
        wrong, and it is self-documenting at the call site.
    ]]
    --[[
        ---------------------------------------------------------------------------------------
        A PLACED ANIMATION. THE ONE THAT ACTUALLY WORKS FOR A BENCH.
        ---------------------------------------------------------------------------------------

        `TaskPlayAnimAdvanced` puts the animation's ROOT at a world position and rotation we
        choose, instead of wherever the ped happens to be standing and facing. That is the whole
        difference between a character lying neatly along the bench and one lying across it in
        mid-air, and no amount of positioning the ped beforehand fixes the second, because
        TaskPlayAnim ignores where the clip was authored to sit.

            TaskPlayAnimAdvanced(ped, dict, clip,
                posX, posY, posZ, rotX, rotY, rotZ,
                blendIn, blendOut, duration, flag, animTime, p14, p15)

        duration -1 and flag 1 keeps it looping until the tasks are cleared. The rotation is
        applied about Z only: a bench press wants the body turned to match the bench, not
        tipped.

        A placed animation carries NO PROP - nothing but a scenario does - so `props` on the
        entry supplies the barbell, and attachProps runs straight afterwards because this mode
        is not 'scenario'.
    ]]
    --[[
        ---------------------------------------------------------------------------------------
        THE ORDER, AND WHY THE GAME'S OWN SCENARIO GOES FIRST
        ---------------------------------------------------------------------------------------

        For an exercise with `preferScenario`, the scenario is tried before anything else. That is
        not a fallback ordering, it is a preference, and it is the right default for one reason:
        ROCKSTAR ALREADY SOLVED IT. PROP_HUMAN_SEAT_MUSCLE_BENCH_PRESS lies the ped on the bench,
        in the right direction, with a barbell held correctly in BOTH hands, tracking both hands
        through the whole movement - because the animation and the prop were authored together.

        Nothing this resource assembles out of an animation plus an attached object will beat
        that. The placed-animation path below exists for the exercises with no scenario twin, and
        as a fallback for when a scenario refuses to start.

        The reason it looked broken for so long was `timeToLeave = 0`, which ended the scenario on
        the frame it began. That is fixed; the scenario is worth preferring again.
    ]]
    --[[
        IN PLACE: DO NOT MOVE THE PLAYER, DO NOT ATTACH THEM. Just play the animation where they are.

        For equipment you pick UP rather than get ON - a dumbbell, a barbell lying on the sand - there
        is no correct place to stand. You lift it where you are. Attaching the body to the prop at a
        measured offset was solving a problem that does not exist, and it was the most expensive
        pretend problem in this resource: `animOffset` is measured from the prop's origin, how high
        that origin sits above the ground is decided by whoever placed the prop, and a studio copy
        cannot know it. That produced feet through the floor, a table of nine plausible and entirely
        wrong measurements, and half a metre of error on a squat rack.

        `inPlace` deletes the whole class. No offset means no offset to get wrong, for every model the
        exercise lists at once.

        What still happens: the world prop is hidden by `hideProp`, our own barbell goes into the
        hands from `props`, and the prop comes back at the end. The player is turned to FACE the
        equipment without being moved, so it does not vanish behind them - the one case where standing
        still would read badly.

        Not for a bench or a rack. Lying on a bench and stepping into a squat rack are exactly the
        cases where position is the whole point, and those keep attaching.
    ]]
    if staging.inPlace and type(staging.anim) == 'table' then
        local dict = resolveDict(staging.anim.dict)

        if dict then
            if entity and DoesEntityExist(entity) then
                local at = GetEntityCoords(entity)
                TaskTurnPedToFaceCoord(ped, at.x, at.y, at.z, 800)
                Wait(300)
            end

            staging.loadedDict = dict
            TaskPlayAnim(ped, dict, staging.anim.clip,
                8.0, -8.0, -1, tonumber(staging.anim.flag) or 1, 0.0,
                false, false, false)

            -- 'placed' rather than 'anim', because the caller uses that to decide two things this
            -- path needs: attach the held props (a scenario would bring its own), and watch the
            -- animation, since TaskPlayAnim can be cancelled by the engine and a scenario cannot.
            return before, 'placed'
        end
    end

    if staging.preferScenario and type(staging.scenario) == 'string' and staging.scenario ~= '' then
        local before2, mode = startScenario(staging, entity, before)
        if mode then return before2, mode end
    end

    if staging.placeAnim and type(staging.anim) == 'table'
        and entity and DoesEntityExist(entity) then

        local dict = resolveDict(staging.anim.dict)

        if dict then
            local offset = staging.animOffset or vector3(0.0, 0.0, 0.0)

            -- All three axes, not just the heading. An incline bench, a rack and anything the
            -- body leans into need pitch as well, and a single heading cannot express that.
            local rot = Equipment.bodyRotation(staging)

            staging.loadedDict = dict

            --[[
                ATTACH THE PED TO THE PROP. This is what finally works, and the two things it
                replaces are both worth knowing about because they fail in the same confusing way.

                TaskPlayAnim places the clip at the ped's own position and heading, so the body
                lands wherever they were standing - across the bench, not along it.

                TaskPlayAnimAdvanced places the clip at a world position, which fixes the
                orientation but not the physics: THE BENCH'S OWN COLLISION PUSHES BACK. Lowering
                the body appears to do nothing for several nudges while the capsule rides up the
                bench geometry, and then the accumulated offset wins all at once and the character
                drops through the map. Adding AF_USE_KINEMATIC_PHYSICS helps and does not cure it.

                Attaching removes physics from the question entirely. The ped becomes rigidly
                positioned relative to the bench, the offset is directly in the bench's local
                space - so +Z is genuinely "up onto the seat", every nudge moves exactly that far,
                and nothing can be blocked or tunnel. The animation then plays on top of a body
                that is already in the right place.

                The three false flags matter:
                  useSoftPinning  false, or physics is allowed to drag the ped off the mount
                  collision       false, which is the entire point
                  fixedRot        true, so the body keeps the heading it was given
            ]]
            AttachEntityToEntity(ped, entity, 0,
                offset.x, offset.y, offset.z,
                rot.x, rot.y, rot.z,
                false,      -- p9
                false,      -- useSoftPinning
                false,      -- collision
                true,       -- isPed: the thing being attached IS a ped
                2,          -- rotationOrder
                true)       -- fixedRot

            TaskPlayAnim(ped, dict, staging.anim.clip,
                8.0, -8.0, -1, PLACED_ANIM_FLAG, 0.0, false, false, false)

            Sport.debug(('attached to prop: %s offset %.2f %.2f %.2f rot %.1f %.1f %.1f')
                :format(dict, offset.x, offset.y, offset.z, rot.x, rot.y, rot.z))

            return before, 'placed'
        end

        Sport.debug('placed anim dictionary would not load:', tostring(staging.anim.dict))
    end

    --[[
        The scenario as a MID-CASCADE fallback.

        Reached when the entry did not prefer a scenario but the placed animation could not run -
        a dictionary that will not stream, a prop that vanished. A scenario needs neither, so it
        is a better answer than the plain animation below, which would play the clip at whatever
        heading the player happens to have.
    ]]
    if not staging.preferScenario and type(staging.scenario) == 'string'
        and staging.scenario ~= '' then
        local before2, mode = startScenario(staging, entity, before)
        if mode then return before2, mode end
    end

    if type(staging.anim) == 'table' then
        local dict = resolveDict(staging.anim.dict)

        if dict then
            -- Remembered so stopAnimation releases the dictionary that was actually loaded
            -- rather than the one that was configured.
            staging.loadedDict = dict

            TaskPlayAnim(ped, dict, staging.anim.clip,
                8.0, -8.0, -1, staging.anim.flag or 1, 0.0, false, false, false)

            Sport.debug('anim:', dict, staging.anim.clip)
            return before, 'anim'
        end

        Sport.debug('anim dictionary would not load, falling back to scenario:',
            tostring(staging.anim.dict))
    end

    if type(staging.scenario) == 'string' and staging.scenario ~= '' then
        TaskStartScenarioInPlace(ped, staging.scenario, 0, true)
        return before, 'scenario'
    end

    return before, 'none'
end

--[[
    Put the ped back under its own physics.

    Every attachment has to be undone or the player is welded to a bench for the rest of their
    session, and the order matters: detach, restore collision, then put them on the ground.
    Skipping the ground step leaves them standing inside the bench they were lying on.
]]
local function detachPed(restoreTo)
    local ped = PlayerPedId()
    if not IsEntityAttached(ped) then return end

    DetachEntity(ped, true, true)
    SetEntityCollision(ped, true, true)
    FreezeEntityPosition(ped, false)

    --[[
        BACK WHERE THEY STOOD, ON THE GROUND. Two bugs lived in the line this replaces:

            SetEntityCoords(ped, coords.x, coords.y, groundZ + 1.0, ...)

        `groundZ + 1.0` put the player a METRE IN THE AIR and let them fall. A ped's coordinates are
        its feet, so groundZ is the ground; the +1 is a reflex borrowed from spawn code, where the
        clearance exists because the trace may be stale. Reported as "when I stop, it teleports me up
        a bit". The same mistake was fixed in the alignment tool hours earlier and not looked for
        here.

        And `coords` was the ped's CURRENT position - which, still attached to a bench, is the
        bench's. So the player was put down inside the equipment rather than beside it.

        `restoreTo` is where they were standing before the attach. The ground is re-traced there,
        because a bench on a slope is not at the height of the ground beside it.
    ]]
    local at = restoreTo or GetEntityCoords(ped)
    local found, groundZ = GetGroundZFor_3dCoord(at.x, at.y, at.z + 2.0, false)

    SetEntityCoords(ped, at.x, at.y, found and groundZ or at.z, false, false, false, false)
end

local function stopAnimation(staging, before, keep, sweep, restoreTo)
    local ped = PlayerPedId()

    --[[
        Snapshot FIRST, while the scenario prop is still in the ped's hands.

        TWO GUARDS, AND THE FIRST ONE MATTERS A LOT.

        `keep` is the equipment itself, and it is excluded. Attaching the PED TO THE BENCH makes
        the engine report the relationship in BOTH directions, so the bench came back from
        attachedSet as "something attached to the ped that was not there before" - and got
        deleted. Off the client's map, permanently, one piece of gym equipment per workout.

        `sweep` is only true when a SCENARIO ran, because that is the only case where an object
        exists that we did not create. Everything the placed path spawns is tracked by handle in
        `ownProps` and deleted from there, so diffing at all is unnecessary risk.
    ]]
    local spawned = {}

    if sweep and type(before) == 'table' then
        for object in pairs(attachedSet(ped)) do
            if not before[object] and object ~= keep then
                spawned[#spawned + 1] = object
            end
        end
    end

    -- Stops the game re-issuing the scenario, which it will do for an idle ped standing on a
    -- scenario point - and which would spawn a second dumbbell straight after the first is
    -- cleaned up.
    SetPedKeepTask(ped, false)
    ClearPedTasksImmediately(ped)

    -- After clearing the tasks: detaching first would drop the ped while the lying animation is
    -- still driving the skeleton, which reads as a fall rather than as standing up.
    detachPed(restoreTo)

    for _, object in ipairs(spawned) do
        deleteObject(object)
    end

    -- Let the streamer reclaim it. Keeping every workout dictionary resident for the whole
    -- session is a few megabytes for no reason. The dictionary that was actually loaded is
    -- released, which is not always the one that was configured.
    if type(staging.loadedDict) == 'string' then
        RemoveAnimDict(staging.loadedDict)
    end
end

--[[
    Undo everything a session did to the world.

    ONE function, called by every path that ends a session - a clean finish, a cancel, a death,
    a block, a resource stop. That is deliberate: a workout that leaves a dumbbell on the floor
    or an invisible barbell behind does it because some fifth exit path forgot to tidy up, and
    the way to not have a fifth path is to not have four.
]]
local function cleanUp(session)
    if type(session) ~= 'table' then return end

    -- Ours first, by handle, while they are still attached and definitely findable.
    for _, object in ipairs(session.ownProps or {}) do
        deleteObject(object)
    end

    -- Then the scenario's, by diffing what is attached against what was - and only when a
    -- scenario actually ran. The equipment itself is passed in so it can never be swept up.
    stopAnimation(session.staging or {}, session.attachedBefore,
        session.entity, session.mode == 'scenario', session.standingAt)

    -- Put the world prop back.
    if session.propHidden and session.entity and DoesEntityExist(session.entity) then
        SetEntityVisible(session.entity, true, false)
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

    --[[
        DERIVE THE MODEL FROM THE ENTITY WHEN THE CALLER DID NOT SUPPLY IT.

        `model` is what selects the modelOverrides for this prop, and a caller that forgets it gets
        the entry's generic numbers with no warning whatsoever - a body placed for a flat bench on an
        incline one. The target integration forgot it, and because the two other callers pass real
        detection candidates the fault only showed on servers running a target, as "the placement is
        wrong" rather than as anything pointing here.

        There is no reason a caller should have to know: the entity is right there. Deriving it means
        the next integration written against this function cannot make the same mistake.
    ]]
    local model = candidate.model
    if not model and entity and DoesEntityExist(entity) then
        model = GetEntityModel(entity)
    end

    -- Remembered for the alignment tool. See the note on Session.lastProp: this is the only handle
    -- the resource is guaranteed to be able to get for equipment a target found and a pool walk
    -- cannot see.
    if entity and DoesEntityExist(entity) and model then
        lastProp = { entity = entity, model = model, key = equipmentKey }
    end

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

        -- How to stage this exercise against THIS prop. A squat rack and a flat bench are the
        -- same exercise and want the player in completely different places.
        staging = Equipment.staging(entry, model),
        entity = entity,
        propHidden = false,
        attachedBefore = nil,
        anywhere = candidate.anywhere == true,
    }

    --[[
        SAY WHAT WAS CHOSEN AND WHERE THE BODY IS GOING. Behind Config.Debug.enabled.

        Worth keeping rather than deleting, because it is the line that found the worst bug in this
        resource's history: "hash nil" in it revealed that no per-model placement had ever been applied
        on a server with a target, after three rounds of reasoning had blamed the measurements instead.

        "It offers the bench press on a prop that is not in the list and puts me anywhere" is the
        hardest class of report to act on - the state is gone by the time anybody can type a command,
        because moving to open the chat changes what you are aiming at. This turns that report into a
        fact. Switch Config.Debug.enabled on, reproduce, read one line.

        Off in normal play: a console line per workout is noise on a busy server.
    ]]
    if Config.Debug.enabled then
        local name = ('hash %s'):format(tostring(model))
        for _, listed in ipairs(entry.models or {}) do
            if type(listed) == 'string' and GetHashKey(listed) == model then
                name = listed
                break
            end
        end

        local staging = current.staging
        local offset = staging.animOffset
        local where = ''

        if staging.placeAnim and offset and entity and DoesEntityExist(entity) then
            local body = GetOffsetFromEntityInWorldCoords(entity, offset.x, offset.y, offset.z)
            local ok, ground = GetGroundZFor_3dCoord(body.x, body.y, body.z + 2.0, false)
            where = (', attach point %+.2fm above the ground'):format(ok and (body.z - ground) or 0)
        end

        Sport.debug(('%s on %s%s%s'):format(
            equipmentKey, name,
            staging.placeAnim and (', animOffset %.2f %.2f %.2f'):format(
                offset and offset.x or 0, offset and offset.y or 0, offset and offset.z or 0)
                or ' (scenario, no placed animation)',
            where))
    end

    CreateThread(function()
        local ped = PlayerPedId()

        -- --- Permission ---------------------------------------------------------------
        local token, refused = requestPermission(equipmentKey, coords, current.anywhere)

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

        local staging = current.staging
        local heading
        local target

        if spot then
            target = spot.coords
            heading = spot.heading
        elseif entity and staging.snap ~= false and staging.offset then
            -- The offset is in the PROP's own space, so positive Y is in front of it and
            -- positive Z is above it - which is how a player ends up standing on a treadmill
            -- deck or inside a squat rack rather than beside either.
            target = GetOffsetFromEntityInWorldCoords(entity,
                staging.offset.x, staging.offset.y, staging.offset.z)
            if staging.heading then
                heading = GetEntityHeading(entity) + staging.heading
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
        --
        -- Hide the world prop for hand-held equipment. The scenario puts its own dumbbell in
        -- the player's hands, and a barbell still lying on the sand underneath them while they
        -- lift an identical one is the giveaway.
        if staging.hideProp and entity and DoesEntityExist(entity) then
            SetEntityVisible(entity, false, false)
            current.propHidden = true
        end

        --[[
            WHERE THEY ARE STANDING, CAPTURED BEFORE ANYTHING MOVES THEM.

            Read here rather than at the start of the session, because the walk to the mark has
            already happened: this is the spot the player will expect to be returned to, not
            wherever they were when they pressed the key. cleanUp hands it to detachPed.
        ]]
        current.standingAt = GetEntityCoords(ped)

        local before, mode = startAnimation(staging, entity)
        current.attachedBefore = before
        current.mode = mode
        current.twoHanded = {}

        -- Only when the scenario did not already bring one: a scenario holding a dumbbell plus
        -- one of ours would be two dumbbells.
        if mode ~= 'scenario' then
            local props, twoHanded = attachProps(staging)
            current.ownProps = props
            current.twoHanded = twoHanded

            startTwoHandedLoop(current)
        end

        -- Only a placed animation needs watching. A scenario is the game's own task and it does
        -- not quietly stop.
        if mode == 'placed' and type(staging.anim) == 'table' then
            startAnimWatchdog(current, staging.loadedDict, staging.anim.clip)
        end
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
-- Training with no equipment
-- ---------------------------------------------------------------------------------------

--- Whether `key` is an exercise that needs no equipment. The server holds the authoritative
--- copy of this list and re-checks it; this is so the menu can grey out what is not offered.
function Session.isAnywhere(key)
    if not Config.Anywhere.enabled then return false end
    return Sport.contains(Config.Anywhere.allowed, key)
end

--- Every exercise that can be started in the open, in catalogue order.
function Session.anywhereList()
    local out = {}
    if not Config.Anywhere.enabled then return out end

    for _, key in ipairs(Equipment.keys) do
        if Sport.contains(Config.Anywhere.allowed, key) then
            local entry = Equipment.get(key)
            out[#out + 1] = {
                key = key,
                label = Locale.text(entry.label or key),
                description = Locale.text(entry.description or ''),
                cooldownLeft = State.cooldownLeft(key),
            }
        end
    end

    return out
end

--[[
    How level the ground under the player is, in degrees from horizontal.

    Push-ups on a 40-degree hillside look worse than no push-ups at all.

    THREE GROUND HEIGHTS RATHER THAN A SHAPE TEST. `StartShapeTestRay` does not resolve in the
    frame it is fired - `GetShapeTestResult` returns "pending" and a garbage normal - so reading
    it immediately gives an answer that is wrong in a way that looks right. Sampling
    GetGroundZFor_3dCoord at the ped and 80cm along each axis is synchronous, cannot fail, and
    measures exactly what matters: whether a body laid down here would be level.
]]
local function groundAngle()
    local coords = GetEntityCoords(PlayerPedId())
    local reach = 0.8

    local function groundAt(dx, dy)
        local found, z = GetGroundZFor_3dCoord(
            coords.x + dx, coords.y + dy, coords.z + 1.0, false)
        if not found then return nil end
        return z
    end

    local here = groundAt(0.0, 0.0)
    local alongX = groundAt(reach, 0.0)
    local alongY = groundAt(0.0, reach)

    -- No ground found means indoors on a surface the probe cannot see, or mid-air. Treating
    -- that as level is the permissive direction, and it is the right one: refusing to let
    -- somebody do push-ups because a probe failed would be worse than the odd sloped push-up.
    if not here or not alongX or not alongY then return 0.0 end

    local slope = math.max(
        math.abs(alongX - here) / reach,
        math.abs(alongY - here) / reach)

    return math.deg(math.atan(slope))
end

--[[
    Start an exercise with no equipment, wherever the player is standing.

    Builds the same candidate shape the detection loop produces, with no entity and no spot, so
    everything downstream - the refusal checks, the staging, the minigame, the cleanup - is the
    single path it always was. There is no second session implementation.
]]
function Session.startAnywhere(key)
    if current then return false end

    if not Config.Anywhere.enabled then
        Compat.notify(L('refuse.no_equipment'), 'error')
        return false
    end

    if not Session.isAnywhere(key) then
        -- Not an error the player caused: a menu offered something it should not have.
        Sport.warn(("'%s' is not in Config.Anywhere.allowed"):format(tostring(key)))
        Compat.notify(L('refuse.no_equipment'), 'error')
        return false
    end

    if Config.Anywhere.requireFlatGround then
        local angle = groundAngle()
        local limit = tonumber(Config.Anywhere.maxGroundAngle) or 20.0

        if angle > limit then
            Compat.notify(L('refuse.uneven_ground'), 'error')
            return false
        end
    end

    local coords = GetEntityCoords(PlayerPedId())

    return Session.start({
        entity = nil,
        model = nil,
        coords = coords,
        keys = { key },
        spot = nil,
        busy = false,
        distanceSquared = 0.0,
        anywhere = true,
    }, key)
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

    cleanUp(session)

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

    if result.status == 'failed' then
        if Config.Notifications.sessionFailed then
            Compat.notify(L('session.aborted'), 'error')
        end

        --[[
            Drop them on the floor.

            AFTER cleanUp, and that ordering is load-bearing: cleanUp calls
            ClearPedTasksImmediately, and clearing tasks cancels a ragdoll. Setting it first
            would look like nothing happened at all.

            Only on a genuine failure. Holding the cancel key is giving up, and giving up does
            not throw you on the ground.
        ]]
        local ragdoll = Config.Minigame.ragdollOnFail
        if ragdoll and ragdoll.enabled then
            local ms = math.floor(Sport.clamp(ragdoll.durationMs, 250, 10000, 2200))
            local ped = PlayerPedId()

            if not IsPedRagdoll(ped) then
                SetPedToRagdoll(ped, ms, ms, 0, true, true, false)
            end
        end
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

    cleanUp(session)

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
