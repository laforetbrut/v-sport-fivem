--[[
    client/custom.lua

    The staff commands for adding equipment, and the receiving end of the live overlay.

    ---------------------------------------------------------------------------------------
    WHY THE MODEL NAME IS NOT AN ARGUMENT
    ---------------------------------------------------------------------------------------

    `/vsportadd treadmill` with no model name is the whole point. Typing a model name means first
    finding it, which means /vsportscan, reading a hash off a console, and getting the spelling
    right - and a misspelling silently does nothing at all, because a name that does not exist
    hashes to a number no object will ever carry.

    So the default is "the prop I am looking at". The client resolves it from the object pool,
    confirms it with IsModelValid, and sends the NAME rather than the hash so the stored file stays
    readable. A name can still be given explicitly, for a prop that is not loaded or not in front
    of you.

    ---------------------------------------------------------------------------------------
    NAMING A MODEL THAT THE CATALOGUE HAS NEVER HEARD OF
    ---------------------------------------------------------------------------------------

    This is the case /vsportscan cannot help with, and it is the common one in a custom MLO:
    GetEntityArchetypeName is not exposed on every server build, so a prop the catalogue does not
    already know may have no name available at all - only a hash.

    When that happens the command says so and prints the hash. A hash works everywhere a name does
    (`models = { 1234567890 }`), so nothing is lost except readability, and the message says how.
]]

-- ---------------------------------------------------------------------------------------
-- The live overlay
-- ---------------------------------------------------------------------------------------

RegisterNetEvent('vsport:client:CustomEquipment', function(store)
    if type(store) ~= 'table' then return end

    Equipment.overlay = Custom.unpackAll(store)
    Equipment.build()

    -- The detector caches by model hash, so it has to be told the index changed underneath it.
    if Detect and Detect.invalidate then Detect.invalidate() end

    local count = 0
    for _ in pairs(Equipment.overlay) do count = count + 1 end
    Sport.debug(('custom equipment applied: %d entr%s')
        :format(count, count == 1 and 'y' or 'ies'))
end)

RegisterNetEvent('vsport:client:CustomExport', function(lines)
    if type(lines) ~= 'table' then return end

    print('^5==== v-sport: your custom equipment as config.lua ====^7')
    for _, line in ipairs(lines) do print(line) end
    print('^5======================================================^7')
    Compat.notify(L('custom.exported'), 'success')
end)

--- The item blocks, mirrored into the admin's own F8 so they do not need server console access.
RegisterNetEvent('vsport:client:ItemBlocks', function(lines)
    if type(lines) ~= 'table' then return end

    print('^5==== v-sport: add these items to your inventory ====^7')
    for _, line in ipairs(lines) do print(line) end
    print('^5===================================================^7')
    Compat.notify(L('custom.exported'), 'success')
end)

-- ---------------------------------------------------------------------------------------
-- Which prop is the admin looking at
-- ---------------------------------------------------------------------------------------

--[[
    The prop in front of the player, or the nearest one.

    A ray from the camera first, because "the one I am looking at" is what a human means and it is
    the only way to pick one treadmill out of a row of four. The nearest object is the fallback,
    for a prop too small or too close to aim at.

    Deliberately NOT limited to props the catalogue knows: the entire purpose is adding ones it
    does not. That is the difference between this and the resolution in /vsportoffset.
]]
--[[
    The camera's forward vector.

    There is no native for this - RotationToDirection is a helper every resource writes for itself,
    and writing it wrong gives a ray that misses everything in a way that looks like the shape test
    is broken. The order matters: pitch (x) then yaw (z), and GTA's yaw is measured anticlockwise
    from north, which is where the negated sine comes from.
]]
local function camForward()
    local rotation = GetGameplayCamRot(2)
    local pitch = math.rad(rotation.x)
    local yaw = math.rad(rotation.z)
    local flat = math.abs(math.cos(pitch))

    return vector3(-math.sin(yaw) * flat, math.cos(yaw) * flat, math.sin(pitch))
end

local function propInFront()
    local ped = PlayerPedId()
    local from = GetGameplayCamCoord()
    local direction = camForward()
    local reach = 12.0

    local to = vector3(
        from.x + direction.x * reach,
        from.y + direction.y * reach,
        from.z + direction.z * reach)

    -- Flag 16 is objects only. Excluding the ped itself matters: aiming down at a mat otherwise
    -- hits the player's own capsule.
    local ray = StartShapeTestLosProbe(from.x, from.y, from.z, to.x, to.y, to.z, 16, ped, 4)

    local retries = 0
    local status, hit, _, _, entity = GetShapeTestResult(ray)

    -- A shape test is not ready on the frame it is fired. Reading it immediately is the mistake
    -- that made the ground-angle check useless before it was replaced.
    while status == 1 and retries < 20 do
        Wait(0)
        retries = retries + 1
        status, hit, _, _, entity = GetShapeTestResult(ray)
    end

    --[[
        Guarded, like the other two raycasts in this resource. A shape test can hand back a handle
        that satisfies DoesEntityExist and still is not something the model natives accept - reading
        it directly crashed the client once, from tune.lua, with an exception inside
        gta-streaming-five.dll rather than a nil.

        This one already checked GetEntityType == 3, which would probably have caught it, but
        "probably" against a crash is not a good trade for one pcall.
    ]]
    if hit == 1 and entity and entity ~= 0 and DoesEntityExist(entity) then
        local okType, kind = pcall(GetEntityType, entity)
        if okType and kind == 3 then
            local okModel, model = pcall(GetEntityModel, entity)
            if okModel and type(model) == 'number' and model ~= 0 then
                return entity, model, 'looking at'
            end
        end
    end

    -- Nearest object instead.
    local coords = GetEntityCoords(ped)
    local best, bestDistance, bestHash = nil, 25.0, nil

    for _, candidate in ipairs(GetGamePool('CObject')) do
        local at = GetEntityCoords(candidate)
        local dx, dy, dz = at.x - coords.x, at.y - coords.y, at.z - coords.z
        local distanceSquared = dx * dx + dy * dy + dz * dz

        if distanceSquared < bestDistance then
            best, bestDistance, bestHash = candidate, distanceSquared, GetEntityModel(candidate)
        end
    end

    if best then return best, bestHash, ('%.1fm away'):format(math.sqrt(bestDistance)) end
    return nil
end

--- The readable name for a hash, or nil. Tries the catalogue, then the native some builds expose.
local function nameFor(hash, entity)
    for _, key in ipairs(Equipment.keys) do
        local entry = Equipment.get(key)
        for _, model in ipairs(entry and entry.models or {}) do
            if type(model) == 'string' and GetHashKey(model) == hash then return model end
        end
    end

    local ok, name = pcall(function() return GetEntityArchetypeName(entity) end)
    if ok and type(name) == 'string' and name ~= '' then return name end

    return nil
end

--[[
    Work out what to add, from an optional argument.

    Returns the model name, or nil after having explained itself. Three ways this ends:

      an explicit name       taken as given, once IsModelValid confirms the game has it
      a prop in view         named if it can be, and refused with its hash if it cannot
      nothing in view        refused
]]
local function resolveModel(explicit)
    if type(explicit) == 'string' and explicit ~= '' then
        if not IsModelValid(GetHashKey(explicit)) then
            print(("^3[v-sport] '%s' is not a model this game build has. Check the spelling: "
                .. "a name that does not exist can never match anything.^7"):format(explicit))
            Compat.notify(L('custom.bad_model', explicit), 'error')
            return nil
        end
        return explicit
    end

    local entity, hash, how = propInFront()
    if not entity then
        print('^3[v-sport] nothing in front of you and nothing within 5 metres.^7')
        Compat.notify(L('custom.nothing_there'), 'error')
        return nil
    end

    local name = nameFor(hash, entity)
    if not name then
        print(('^3[v-sport] found an object (%s) but this server build will not tell me its '
            .. 'name.^7'):format(how))
        print(('^3  Its hash is %d. A hash works as well as a name:^7'):format(hash))
        print(('^3      Config.ExtraEquipment = { <exercise> = { models = { %d } } }^7'):format(hash))
        Compat.notify(L('custom.no_name'), 'error')
        return nil
    end

    print(('^5[v-sport] %s: %s (%s)^7'):format(L('custom.resolved'), name, how))
    return name
end

-- ---------------------------------------------------------------------------------------
-- /vsportadd
-- ---------------------------------------------------------------------------------------

if Config.Commands.add and Config.Commands.add ~= '' then
    RegisterCommand(Config.Commands.add, function(_, args)
        if not State.devGate() then return end

        local key = args and args[1]
        if not key or key == '' then
            print(L('custom.add_usage', Config.Commands.add))
            print('  ' .. table.concat(Equipment.keys, ', '))
            return
        end

        if not Equipment.get(key) and not (Equipment.catalogue[key]) then
            print(L('cmd.no_equipment', key))
            print('  ' .. table.concat(Equipment.keys, ', '))
            return
        end

        local model = resolveModel(args[2])
        if not model then return end

        TriggerServerEvent('vsport:server:CustomAdd', key, model)
    end, false)

    TriggerEvent('chat:addSuggestion', '/' .. Config.Commands.add, L('custom.add'), {
        { name = 'exercise', help = table.concat(Equipment.keys, ' | ') },
        { name = 'model', help = 'optional: defaults to the prop you are looking at' },
    })
end

-- ---------------------------------------------------------------------------------------
-- /vsportremove
-- ---------------------------------------------------------------------------------------

if Config.Commands.remove and Config.Commands.remove ~= '' then
    RegisterCommand(Config.Commands.remove, function(_, args)
        if not State.devGate() then return end

        local key = args and args[1]
        if not key or key == '' then
            print(L('custom.remove_usage', Config.Commands.remove))
            return
        end

        local model = resolveModel(args[2])
        if not model then return end

        TriggerServerEvent('vsport:server:CustomRemove', key, model)
    end, false)

    TriggerEvent('chat:addSuggestion', '/' .. Config.Commands.remove, L('custom.remove'), {
        { name = 'exercise', help = table.concat(Equipment.keys, ' | ') },
        { name = 'model', help = 'optional: defaults to the prop you are looking at' },
    })
end

-- ---------------------------------------------------------------------------------------
-- /vsportcustom, /vsportexport, /vsportreload, /vsportreset
-- ---------------------------------------------------------------------------------------

if Config.Commands.custom and Config.Commands.custom ~= '' then
    RegisterCommand(Config.Commands.custom, function()
        if not State.devGate() then return end

        print('^5==== v-sport: equipment added in game ====^7')

        local any = false
        for key, entry in pairs(Equipment.overlay or {}) do
            any = true
            print(('  ^5%s^7'):format(key))

            for _, model in ipairs(entry.models or {}) do
                local known = IsModelValid(GetHashKey(model))
                print(('      %-34s %s'):format(model, known and 'in this build' or '^3not in this build^7'))
            end

            for model in pairs(entry.modelOverrides or {}) do
                print(('      %-34s aligned'):format(model))
            end
        end

        if not any then
            print('  nothing yet. Stand in front of a prop and run /'
                .. (Config.Commands.add or 'vsportadd') .. ' <exercise>')
        end

        print('^5==========================================^7')
    end, false)

    TriggerEvent('chat:addSuggestion', '/' .. Config.Commands.custom, L('custom.list'))
end

-- ---------------------------------------------------------------------------------------
-- /vsportmissing - have we missed a prop?
-- ---------------------------------------------------------------------------------------
--
-- THE GAME ANSWERS, NOT A LIST. Every published GTA prop dump is incomplete: the one used to build
-- Config.Debug.candidateModels has no prop_weight_squat and no prop_pris_bench_01, and both are
-- real and in use here. IsModelValid is the only authority for what THIS build has.
--
-- So it reports in both directions, and the second is the one that gets forgotten:
--
--   exists here, not in the catalogue    a real gap
--   in the catalogue, does not exist     a dead entry, harmless but worth knowing
--
-- Nothing is streamed and nothing is spawned. IsModelValid is an archetype lookup, so a hundred
-- names cost one frame.

if Config.Commands.missing and Config.Commands.missing ~= '' then
    RegisterCommand(Config.Commands.missing, function()
        if not State.devGate() then return end

        -- Every model the catalogue claims, by name, so both directions can be answered.
        local claimed, claimedNames = {}, {}
        for _, key in ipairs(Equipment.keys) do
            local entry = Equipment.get(key)
            for _, model in ipairs(entry and entry.models or {}) do
                if type(model) == 'string' then
                    claimed[model] = key
                    claimedNames[#claimedNames + 1] = model
                end
            end
        end

        -- The disabled entries count as claimed too: prop_beach_volball01 is not a gap just
        -- because volleyball ships switched off.
        for key, entry in pairs(Equipment.catalogue) do
            for _, model in ipairs(type(entry) == 'table' and entry.models or {}) do
                if type(model) == 'string' and not claimed[model] then
                    claimed[model] = key .. ' (off)'
                    claimedNames[#claimedNames + 1] = model
                end
            end
        end

        table.sort(claimedNames)

        local gaps, dead = {}, {}

        for _, name in ipairs(Config.Debug.candidateModels or {}) do
            if type(name) == 'string' and not claimed[name] then
                if IsModelValid(GetHashKey(name)) then
                    gaps[#gaps + 1] = name
                end
            end
        end

        for _, name in ipairs(claimedNames) do
            if not IsModelValid(GetHashKey(name)) then
                dead[#dead + 1] = ('%-30s %s'):format(name, claimed[name])
            end
        end

        print('^5==== v-sport: did we miss a prop? ====^7')
        print(('  %d models claimed by the catalogue, %d candidates tested against this build')
            :format(#claimedNames, #(Config.Debug.candidateModels or {})))
        print('')

        if #gaps > 0 then
            print(('^3  %d MODEL%s EXIST HERE AND ARE NOT IN THE CATALOGUE:^7')
                :format(#gaps, #gaps == 1 and '' or 'S'))
            for _, name in ipairs(gaps) do
                print(('^3      %-30s  /%s <exercise> %s^7')
                    :format(name, Config.Commands.add or 'vsportadd', name))
            end
            print('')
        else
            print('^2  no candidate exists here that the catalogue does not already have^7')
            print('')
        end

        if #dead > 0 then
            print(('  %d claimed model%s not in this build (harmless - they hash to nothing):')
                :format(#dead, #dead == 1 and ' is' or 's are'))
            for _, line in ipairs(dead) do print('      ' .. line) end
        else
            print('  every model the catalogue claims exists in this build')
        end

        print('')
        print('  This tests Config.Debug.candidateModels. Add your MLO\'s names to it and run')
        print('  again - the game will tell you which of them it actually has.')
        print('^5======================================^7')

        Compat.notify(L('custom.missing_done', #gaps), #gaps > 0 and 'primary' or 'success')
    end, false)

    TriggerEvent('chat:addSuggestion', '/' .. Config.Commands.missing, L('custom.missing'))
end

-- ---------------------------------------------------------------------------------------
-- /vsporttour - look at every animation on every prop, once, and record a verdict
-- ---------------------------------------------------------------------------------------
--
-- The catalogue has 34 models across 18 exercises, and the only way to know an animation looks
-- right on a given prop is to LOOK at it. Doing that by hand meant typing 43 commands and
-- remembering which of them looked wrong, which is how the incline bench went unnoticed: a body
-- lying flat on a bench tipped 44 degrees, in a model named exactly like its five flat siblings.
--
-- So the tour drives the alignment studio: it spawns each prop in turn, plays the exercise's real
-- animation with its real configured placement, and waits.
--
--   1   this looks right
--   2   this does not
--   N   next without judging
--   B   back
--   BACKSPACE   stop, and print the report
--
-- The report is the point. A review that only tells you the answer while you are looking at it is
-- a review you have to do twice.

local tour = nil            -- { pairs, index, verdicts, running }

--[[
    Every (exercise, model) pair worth looking at.

    IsModelValid filters, because a model the build does not have cannot be spawned and would stall
    the tour on a prop that never appears. Disabled exercises are skipped: they are off precisely
    because their animation is wrong, so reviewing them would collect verdicts nobody wants.
]]
local function buildTour(only)
    local out = {}

    for _, key in ipairs(Equipment.keys) do
        if not only or only == key then
            local entry = Equipment.get(key)
            for _, model in ipairs(entry and entry.models or {}) do
                if type(model) == 'string' and IsModelValid(GetHashKey(model)) then
                    out[#out + 1] = { key = key, model = model }
                end
            end
        end
    end

    return out
end

local function tourReport()
    local bad, good, skipped = {}, 0, 0

    for _, pair in ipairs(tour.pairs) do
        local verdict = tour.verdicts[pair.key .. '/' .. pair.model]
        if verdict == true then
            good = good + 1
        elseif verdict == false then
            bad[#bad + 1] = pair
        else
            skipped = skipped + 1
        end
    end

    print('^5==== v-sport: animation review ====^7')
    print(('  %d looked right, %d did not, %d not judged, out of %d')
        :format(good, #bad, skipped, #tour.pairs))
    print('')

    if #bad > 0 then
        print(('^3  %d TO FIX:^7'):format(#bad))
        for _, pair in ipairs(bad) do
            print(('^3      %-18s %-30s  /%s %s %s^7'):format(
                pair.key, pair.model, Config.Commands.tune or 'vsportprop',
                pair.key, pair.model))
        end
    else
        print('^2  nothing was marked wrong^7')
    end

    if skipped > 0 then
        print('')
        print(('  %d were stepped past without a verdict. Run the tour again to finish them.')
            :format(skipped))
    end

    print('^5===================================^7')

    Compat.notify(L('custom.tour_done', #bad), #bad > 0 and 'error' or 'success')
end

if Config.Commands.tour and Config.Commands.tour ~= '' then
    RegisterCommand(Config.Commands.tour, function(_, args)
        if not State.devGate() then return end

        if tour and tour.running then
            print('^3[v-sport] a tour is already running. BACKSPACE ends it.^7')
            return
        end

        local only = args and args[1]
        if only and not Equipment.get(only) then
            print(L('cmd.no_equipment', only))
            print('  ' .. table.concat(Equipment.keys, ', '))
            return
        end

        local pairsToWalk = buildTour(only)
        if #pairsToWalk == 0 then
            print('^3[v-sport] nothing to review - no listed model exists in this build.^7')
            return
        end

        tour = { pairs = pairsToWalk, index = 1, verdicts = {}, running = true }

        print(('^5[v-sport] reviewing %d prop/exercise pairs. 1 = right, 2 = WRONG, 3 = skip, '
            .. '4 = back, BACKSPACE = stop and report.^7'):format(#pairsToWalk))

        CreateThread(function()
            while tour and tour.running do
                local pair = tour.pairs[tour.index]

                -- Walked off either end. Forwards is "finished"; backwards just stops at the top.
                if not pair then
                    tour.running = false
                    break
                end

                Tune.stepRequest = nil
                Tune.verdict = nil
                Tune.tourLabel = ('REVIEW %d / %d   %s')
                    :format(tour.index, #tour.pairs, pair.model)

                --[[
                    SKIP WHAT WILL NOT OPEN, DO NOT ABANDON THE REVIEW.

                    This used to stop the whole tour on the first failure, and the first failure came
                    immediately: a model the map places nowhere, with the studio fallback broken. One
                    unreachable prop out of 43 ended the review before a single verdict was recorded.

                    A skipped pair is reported as "not judged" at the end, which is exactly what it
                    is, and the other 42 still get looked at.
                ]]
                if not Tune.start(pair.key, pair.model) then
                    print(('^3[v-sport] skipping %s on %s - could not open it.^7')
                        :format(pair.key, pair.model))
                    tour.index = tour.index + 1
                    Wait(250)
                else
                    -- Wait for the tuner to finish, teardown included. `busy` rather than `active`:
                    -- see the note in tune.lua on why those are not the same moment.
                    while Tune.busy() do Wait(100) end

                    if Tune.verdict ~= nil then
                        tour.verdicts[pair.key .. '/' .. pair.model] = Tune.verdict
                    end

                    if Tune.stepRequest == nil then
                        tour.running = false
                    else
                        tour.index = math.max(1, tour.index + Tune.stepRequest)
                    end
                end
            end

            Tune.tourLabel = nil
            if tour then tourReport() end
        end)
    end, false)

    TriggerEvent('chat:addSuggestion', '/' .. Config.Commands.tour, L('custom.tour'), {
        { name = 'exercise', help = 'optional: review one exercise instead of all of them' },
    })
end


--[[
    These three are thin: they only ask the server, which does the work and the authorising. They
    exist as client commands purely so that an admin in game can reach them without console access -
    the server re-checks Bridge.isAdmin on the event regardless of the gate here.
]]
local function relay(commandKey, event, help, takesKey)
    local name = Config.Commands[commandKey]
    if not name or name == '' then return end

    RegisterCommand(name, function(_, args)
        if not State.devGate() then return end
        TriggerServerEvent(event, takesKey and args and args[1] or nil)
    end, false)

    TriggerEvent('chat:addSuggestion', '/' .. name, help)
end

CreateThread(function()
    relay('export', 'vsport:server:CustomExport', L('custom.export'), false)
    relay('reload', 'vsport:server:CustomReload', L('custom.reload'), false)
    relay('reset', 'vsport:server:CustomReset', L('custom.reset'), true)
end)
