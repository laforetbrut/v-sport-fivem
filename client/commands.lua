--[[
    client/commands.lua

    The player commands, the two developer tools, and every client export.

    /sportscan and /sportspot are the answer to the question no shipped resource can answer
    for you: WHICH sport props does YOUR map actually have. The catalogue in
    shared/equipment.lua covers the base game and a spread of common MLO names, and it cannot
    possibly cover the gym you downloaded last week. These two print exactly what to paste
    into the config.
]]

-- A hash -> name map built from the catalogue, so the scan can name what it already knows.
-- There is no way back from a hash to a string in general; this only names models the
-- resource was told about.
local knownNames = {}

CreateThread(function()
    for _, key in ipairs(Equipment.keys) do
        local entry = Equipment.get(key)
        for _, model in ipairs(entry and entry.models or {}) do
            if type(model) == 'string' then
                knownNames[GetHashKey(model)] = model
            end
        end
    end
end)

--[[
    The model name for a hash, or nil.

    Tries the catalogue first, then GetEntityArchetypeName - which some server builds expose
    and some do not. It is called through pcall for exactly that reason: a missing native
    raises rather than returning nil, and a developer command must not be the thing that
    errors on somebody's server.
]]
local function modelName(hash, entity)
    local known = knownNames[hash]
    if known then return known end

    local ok, name = pcall(function()
        return GetEntityArchetypeName(entity)
    end)

    if ok and type(name) == 'string' and name ~= '' then return name end
    return nil
end

-- ---------------------------------------------------------------------------------------
-- /sport
-- ---------------------------------------------------------------------------------------

if Config.Commands.stats and Config.Commands.stats ~= '' then
    RegisterCommand(Config.Commands.stats, function()
        Menu.toggle()
    end, false)

    TriggerEvent('chat:addSuggestion', '/' .. Config.Commands.stats, L('cmd.stats'))
end

-- ---------------------------------------------------------------------------------------
-- /vsportdev
-- ---------------------------------------------------------------------------------------
--
-- Re-ask the server whether this player may use the developer tools. Not restricted itself, and
-- it does not need to be: the ANSWER comes from the server, which computes it fresh every time,
-- so a non-admin asking repeatedly is told no repeatedly.
--
-- It exists for the case that would otherwise need a reconnect: an admin promoted mid-session, or
-- one whose ace comes from a permissions resource that finished loading after this one.

if Config.Commands.dev and Config.Commands.dev ~= '' then
    RegisterCommand(Config.Commands.dev, function()
        TriggerServerEvent('vsport:server:RequestDevAccess')
        Wait(500)

        if State.devAllowed then
            Compat.notify(L('cmd.dev_granted'), 'success')
        else
            Compat.notify(L('notify.no_permission'), 'error')
        end
    end, false)

    TriggerEvent('chat:addSuggestion', '/' .. Config.Commands.dev, L('cmd.dev'))
end

-- ---------------------------------------------------------------------------------------
-- /sportinfo
-- ---------------------------------------------------------------------------------------

if Config.Commands.info and Config.Commands.info ~= '' then
    RegisterCommand(Config.Commands.info, function()
        if not State.devGate() then return end

        print('^5================ v-sport ================^7')

        for _, row in ipairs(Compat.report()) do
            print(('  %-16s %s'):format(row[1], tostring(row[2])))
        end

        print('  ---------------------------------------')
        print(('  %-16s %s'):format('Stats ready', tostring(State.ready)))

        for _, key in ipairs(Stats.keys()) do
            local def = Stats.def(key)
            print(('  %-16s %.2f  (effective %.2f)'):format(
                L(def.label), State.raw(key), State.get(key)))
        end

        print(('  %-16s %d'):format('Sessions', State.totalSessions))
        print(('  %-16s %d in range'):format('Detection', Detect.count()))

        local closest = Detect.closestVisible()
        if closest then
            print(('  %-16s %s at %.1fm'):format('Nearest',
                table.concat(closest.keys, ', '), math.sqrt(closest.distanceSquared)))
        end

        print('^5=========================================^7')
        Compat.notify('Printed to the console (F8)', 'primary')
    end, false)

    TriggerEvent('chat:addSuggestion', '/' .. Config.Commands.info, L('cmd.info'))
end

-- ---------------------------------------------------------------------------------------
-- /sportscan
-- ---------------------------------------------------------------------------------------

if Config.Commands.scan and Config.Commands.scan ~= '' then
    RegisterCommand(Config.Commands.scan, function(_, args)
        if not State.devGate() then return end

        local radius = tonumber(args and args[1]) or 20.0
        local coords = GetEntityCoords(PlayerPedId())
        local found = {}

        for _, entity in ipairs(GetGamePool('CObject')) do
            local entityCoords = GetEntityCoords(entity)
            local dx, dy, dz = entityCoords.x - coords.x, entityCoords.y - coords.y,
                entityCoords.z - coords.z
            local distance = math.sqrt(dx * dx + dy * dy + dz * dz)

            if distance <= radius then
                local hash = GetEntityModel(entity)
                found[#found + 1] = {
                    hash = hash,
                    name = modelName(hash, entity),
                    distance = distance,
                    keys = Equipment.byModel[hash],
                    coords = entityCoords,
                }
            end
        end

        table.sort(found, function(a, b) return a.distance < b.distance end)

        print(('^5==== v-sport scan: %d objects within %.0fm ====^7'):format(#found, radius))
        print('  dist    known   model')

        local shown = 0
        for _, item in ipairs(found) do
            shown = shown + 1
            if shown > 60 then
                print(('  ... and %d more. Pass a smaller radius: /%s 8')
                    :format(#found - 60, Config.Commands.scan))
                break
            end

            print(('  %5.1fm  %-6s  %s'):format(
                item.distance,
                item.keys and 'YES' or '-',
                item.name or ('hash ' .. tostring(item.hash))
            ))

            if item.keys then
                print(('           -> %s'):format(table.concat(item.keys, ', ')))
            end
        end

        print('^3  A model marked "-" is not in the catalogue. Add it to^7')
        print('^3  Config.ExtraEquipment in config.lua to make it usable.^7')
        print('^3  An unnamed hash can be added as a number instead of a string.^7')

        --[[
            WHAT THE SCAN CANNOT SEE, said out loud.

            This list comes from GetGamePool('CObject'), which holds spawned objects. A prop that is
            part of the map or baked into an MLO is not in it - so it is absent from everything above,
            absent from Detect, and yet a TARGET resource will happily offer an exercise on it,
            because a target uses its own raycast.

            That combination produced three separate reports that each looked like a different bug:
            "the dev tool does not see these props", "it offers the bench press on something not in
            the list", and "the tuner cannot find it". One line here would have answered all three.
        ]]
        local aimedHit, aimedModel = nil, nil
        do
            local ped = PlayerPedId()
            local from = GetGameplayCamCoord()
            local rotation = GetGameplayCamRot(2)
            local pitch, yaw = math.rad(rotation.x), math.rad(rotation.z)
            local flat = math.abs(math.cos(pitch))
            local reach = 14.0

            -- Flag 16, objects only. Flag 1 adds map geometry and returns a handle that passes
            -- DoesEntityExist and then crashes GetEntityModel inside the streaming DLL; that is
            -- not a theory, it took the client down once.
            local ray = StartShapeTestLosProbe(from.x, from.y, from.z,
                from.x - math.sin(yaw) * flat * reach,
                from.y + math.cos(yaw) * flat * reach,
                from.z + math.sin(pitch) * reach,
                16, ped, 4)

            local status, hit, _, _, entity = GetShapeTestResult(ray)
            local tries = 0
            while status == 1 and tries < 20 do
                Wait(0)
                tries = tries + 1
                status, hit, _, _, entity = GetShapeTestResult(ray)
            end

            if hit == 1 and entity and entity ~= 0 and DoesEntityExist(entity) then
                local ok, model = pcall(GetEntityModel, entity)
                if ok and type(model) == 'number' and model ~= 0 then
                    aimedHit, aimedModel = entity, model
                end
            end
        end

        print('')
        print('^5  WHAT YOU ARE LOOKING AT^7')

        if not aimedHit then
            print('  no OBJECT within 14m of your crosshair')
            print('  (map and MLO geometry is not an object and never appears here)')
        else
            local hash = aimedModel
            local inPool = false
            for _, entity in ipairs(GetGamePool('CObject')) do
                if entity == aimedHit then inPool = true break end
            end

            print(('  model      %s'):format(modelName(hash, aimedHit)
                or ('hash ' .. tostring(hash))))
            print(('  catalogue  %s'):format(Equipment.byModel[hash]
                and table.concat(Equipment.byModel[hash], ', ') or 'not in it'))
            print(('  in the object pool  %s'):format(inPool and 'yes' or
                '^3NO - it is map or MLO geometry^7'))

            if not inPool then
                print('^3  That is why it is missing from the list above and from /vsportscan in')
                print('^3  general: this resource scans spawned objects. A target resource uses its')
                print('^3  own raycast and WILL offer an exercise on it. /vsportprop now finds it')
                print('^3  too, by looking where you look.^7')
            end
        end

        --[[
            WHY IS THE PROMPT OFFERING THAT?

            The question a scan could never answer, and the one that actually gets asked. Listing
            what is nearby does not say which of it the prompt has chosen, and when the answer is
            "something four metres behind you" the report reads as though the prompt is about the
            machine in front of you.

            So it says outright: this exact entity, this far away, this far off your aim, and where
            the body will be put. If the model named here is not the thing you are looking at, that
            is the whole bug in one line.
        ]]
        print('')
        print('^5  WHAT THE PROMPT IS CURRENTLY TARGETING^7')

        local target = Detect.closestVisible()
        if not target then
            print('  nothing - no prompt should be showing')
        else
            local hash = target.entity and GetEntityModel(target.entity) or nil
            local name = hash and modelName(hash, target.entity) or nil

            print(('  model      %s'):format(name or ('hash ' .. tostring(hash))))
            print(('  offers     %s'):format(table.concat(target.keys or {}, ', ')))
            print(('  distance   %.2fm'):format(math.sqrt(target.distanceSquared)))
            print(('  kind       %s'):format(
                target.spot and 'a Config.Spots coordinate, not an object' or 'a world object'))

            if target.entity and DoesEntityExist(target.entity) then
                local at = GetEntityCoords(target.entity)
                print(('  prop at    %.2f %.2f %.2f'):format(at.x, at.y, at.z))

                -- Where the body will actually end up, per the entry the prompt would start.
                local first = (target.keys or {})[1]
                local entry = first and Equipment.get(first)
                if entry then
                    local staging = Equipment.staging(entry, hash)
                    if staging.placeAnim and staging.animOffset then
                        local body = GetOffsetFromEntityInWorldCoords(target.entity,
                            staging.animOffset.x, staging.animOffset.y, staging.animOffset.z)
                        local ok, ground = GetGroundZFor_3dCoord(body.x, body.y, body.z + 2.0, false)

                        --[[
                            THE ATTACH POINT, NOT THE FEET, AND THIS LINE USED TO CLAIM OTHERWISE.

                            animOffset positions the ped's attach origin, which sits around the
                            pelvis - roughly a metre above the soles on a standing body. The first
                            version of this readout compared that height against the ground and
                            printed "BELOW IT, the offset is too low" under 15 cm, which fires on
                            perfectly correct values: a standing body's pelvis belongs about a metre
                            up.

                            There is no honest verdict available here. The relationship between the
                            attach point and the feet depends on the posture the clip puts the body
                            in - a metre standing, near zero lying down - and this command runs with
                            no session and no attached ped to read foot bones from.

                            So it reports the number and says what the number is. The tuner's own
                            height row measures the actual foot bones and is the thing to trust.
                        ]]
                        print(('  body attach point -> %.2f %.2f %.2f  (animOffset %.2f %.2f %.2f)')
                            :format(body.x, body.y, body.z,
                                staging.animOffset.x, staging.animOffset.y, staging.animOffset.z))

                        if ok then
                            print(('  that point is %+.2fm above the ground there')
                                :format(body.z - ground))
                            print('  it is the PELVIS, not the feet: about 1m up for a standing')
                            print('  clip, near zero for one lying down. Judge it in /'
                                .. (Config.Commands.tune or 'vsportprop') .. ', which reads the')
                            print('  actual foot bones.')
                        end
                    else
                        print('  this exercise places no animation - the scenario decides')
                    end
                end
            else
                print('  the entity no longer exists - the scan is stale')
            end
        end

        print('^5=================================================^7')

        Compat.notify(('%d objects listed in the console (F8)'):format(#found), 'primary')
    end, false)

    TriggerEvent('chat:addSuggestion', '/' .. Config.Commands.scan, L('cmd.scan'), {
        { name = 'radius', help = 'metres, default 20' },
    })
end

-- ---------------------------------------------------------------------------------------
-- /sportspot
-- ---------------------------------------------------------------------------------------

if Config.Commands.spot and Config.Commands.spot ~= '' then
    RegisterCommand(Config.Commands.spot, function(_, args)
        if not State.devGate() then return end

        local key = args and args[1]

        if not key or key == '' then
            print(L('cmd.spot_usage', Config.Commands.spot))
            print('  Known equipment: ' .. table.concat(Equipment.keys, ', '))
            return
        end

        if not Equipment.get(key) then
            print(L('cmd.no_equipment', key))
            print('  Known equipment: ' .. table.concat(Equipment.keys, ', '))
            return
        end

        local ped = PlayerPedId()
        local coords = GetEntityCoords(ped)
        local heading = GetEntityHeading(ped)

        print('^5==== v-sport: paste this into Config.Spots ====^7')
        print(('    { equipment = \'%s\', coords = vector3(%.2f, %.2f, %.2f), heading = %.1f },')
            :format(key, coords.x, coords.y, coords.z - 1.0, heading))
        print('^3  The z is the player position minus 1.0, which puts it on the floor.^7')
        print('^5===============================================^7')

        Compat.notify('Spot printed to the console (F8)', 'success')
    end, false)

    TriggerEvent('chat:addSuggestion', '/' .. Config.Commands.spot, L('cmd.spot'), {
        { name = 'equipment', help = table.concat(Equipment.keys, ' | ') },
    })
end

-- ---------------------------------------------------------------------------------------
-- /vsportoffset
-- ---------------------------------------------------------------------------------------
--
-- Tuning a `modelOverrides` entry by guesswork means restarting the resource for every
-- attempt. This prints the exact block: stand where the player should be, face the prop, run
-- it, paste the result.

if Config.Commands.offset and Config.Commands.offset ~= '' then
    RegisterCommand(Config.Commands.offset, function()
        if not State.devGate() then return end

        local ped = PlayerPedId()
        local coords = GetEntityCoords(ped)

        -- The nearest prop the catalogue knows about, whatever exercise it belongs to.
        local best, bestDistance, bestHash = nil, math.huge, nil

        for _, entity in ipairs(GetGamePool('CObject')) do
            local hash = GetEntityModel(entity)
            if Equipment.byModel[hash] then
                local at = GetEntityCoords(entity)
                local dx, dy, dz = at.x - coords.x, at.y - coords.y, at.z - coords.z
                local distanceSquared = dx * dx + dy * dy + dz * dz

                if distanceSquared < bestDistance then
                    best, bestDistance, bestHash = entity, distanceSquared, hash
                end
            end
        end

        if not best then
            print('^3[v-sport] no known sport prop nearby. Run /' ..
                (Config.Commands.scan or 'vsportscan') .. ' to see what is around you.^7')
            Compat.notify('No known sport prop nearby', 'error')
            return
        end

        -- GetOffsetFromEntityGivenWorldCoords is the exact inverse of the
        -- GetOffsetFromEntityInWorldCoords the session uses to place the player, so what this
        -- prints is what will be applied - no sign or axis guesswork.
        local offset = GetOffsetFromEntityGivenWorldCoords(best, coords.x, coords.y, coords.z)
        local heading = GetEntityHeading(ped) - GetEntityHeading(best)

        -- Normalise into 0-360 so the printed number reads the way an operator expects.
        heading = heading % 360.0

        local name = modelName(bestHash, best) or ('[' .. tostring(bestHash) .. ']')
        local exercises = table.concat(Equipment.byModel[bestHash] or {}, ', ')

        print('^5==== v-sport: paste into the entry\'s modelOverrides ====^7')
        print(('  model    %s   (%.2fm away)'):format(name, math.sqrt(bestDistance)))
        print(('  offers   %s'):format(exercises))
        print('')
        print('        modelOverrides = {')
        print(("            ['%s'] = {"):format(name))
        print(('                offset = vector3(%.2f, %.2f, %.2f),'):format(
            offset.x, offset.y, offset.z))
        print(('                heading = %.1f,'):format(heading))
        print('                snap = true,')
        print('            },')
        print('        },')
        print('^3  Stand exactly where the player should end up, facing the way they should^7')
        print('^3  face, and run this again if it is not right yet.^7')
        print('^5========================================================^7')

        Compat.notify(('Offset for %s printed to F8'):format(name), 'success')
    end, false)

    TriggerEvent('chat:addSuggestion', '/' .. Config.Commands.offset, L('cmd.offset'))
end

-- ---------------------------------------------------------------------------------------
-- Events, for a radial menu or any other resource
-- ---------------------------------------------------------------------------------------
--
-- qb-radialmenu, ox_lib's radial, a keybind resource or an NPC dialogue can all fire these.
-- They are net events rather than exports so that a resource which loads BEFORE this one can
-- still reference them - an export has to exist at the moment it is called, an event does not.
--
-- See API.md for the qb-radialmenu block to paste.

RegisterNetEvent('vsport:client:OpenPanel', function()
    Menu.open()
end)

RegisterNetEvent('vsport:client:ClosePanel', function()
    Menu.close()
end)

RegisterNetEvent('vsport:client:TogglePanel', function()
    Menu.toggle()
end)

--- Start a workout on the nearest usable equipment. `key` optionally names which exercise when
--- the prop offers several.
RegisterNetEvent('vsport:client:StartNearest', function(key)
    local candidate = Detect.closest()

    if not candidate then
        Compat.notify(L('refuse.distance'), 'error')
        return
    end

    Session.start(candidate, key)
end)

RegisterNetEvent('vsport:client:StopSession', function()
    Session.stop('event')
end)

--[[
    Train with no equipment at all, wherever the player is standing.

    This is the one a radial menu wants for push-ups and yoga: there is no prop in the world to
    walk up to and press E on, so the menu IS the interaction. `key` is an exercise from
    Config.Anywhere.allowed, and the server re-checks it against its own copy of that list.
]]
RegisterNetEvent('vsport:client:StartAnywhere', function(key)
    Session.startAnywhere(key)
end)

-- Shorthands, so a radial menu entry needs no argument plumbing at all.
RegisterNetEvent('vsport:client:PushUps', function()
    Session.startAnywhere('push_ups')
end)

RegisterNetEvent('vsport:client:SitUps', function()
    Session.startAnywhere('sit_ups')
end)

RegisterNetEvent('vsport:client:Yoga', function()
    Session.startAnywhere('yoga')
end)

RegisterNetEvent('vsport:client:Stretch', function()
    Session.startAnywhere('stretching')
end)

-- ---------------------------------------------------------------------------------------
-- CLIENT EXPORTS
-- ---------------------------------------------------------------------------------------
--
-- Everything another resource can ask the client. See API.md.
--
-- Every table handed out is a COPY. A caller that mutates the result cannot reach into this
-- resource's own state, which is the difference between an API and a shared global.

--- The stored values, without buffs. { strength = 42.5, breath = 10.0, stamina = 31.25 }
exports('GetStats', function()
    return Sport.copy(State.trained)
end)

--- The values with active buffs folded in. These are the ones driving the natives.
exports('GetEffectiveStats', function()
    return Sport.copy(State.effective)
end)

--- One stored value, or 0.
exports('GetStat', function(key)
    return State.raw(key)
end)

--- One effective value, or 0.
exports('GetEffectiveStat', function(key)
    return State.get(key)
end)

--- Every active buff, as a copy.
exports('GetBuffs', function()
    return Sport.copy(State.buffs)
end)

--- Whether the player has finished loading their stats.
exports('IsReady', function()
    return State.ready
end)

--- Whether a workout is running.
exports('IsTraining', function()
    return Session.active()
end)

--- What is running, or nil. { equipment, label, startedAt, reps }
exports('GetSession', function()
    return Session.info()
end)

--- Stop the running workout. Returns whether there was one.
exports('StopSession', function(reason)
    return Session.stop(reason or 'export')
end)

--- Start a workout on the nearest usable equipment. `key` optionally names which exercise
--- when the prop offers several. Returns whether one started.
exports('StartNearest', function(key)
    local candidate = Detect.closest()
    if not candidate then return false end
    return Session.start(candidate, key)
end)

--- Start an exercise that needs no equipment, where the player is standing. Returns whether one
--- started; it shows the player the reason when it refuses.
exports('StartAnywhere', function(key)
    return Session.startAnywhere(key)
end)

--- The exercises that can be started in the open, for building a menu:
--- { { key, label, description, cooldownLeft }, ... }
exports('GetAnywhereExercises', function()
    return Session.anywhereList()
end)

--- Whether one specific exercise can be done without equipment.
exports('IsAnywhereExercise', function(key)
    return Session.isAnywhere(key)
end)

--- Everything in detection range, as a plain list. Allocates, so do not call it per frame.
exports('GetNearbyEquipment', function()
    local out = {}
    for candidate in Detect.each() do
        out[#out + 1] = {
            equipment = Sport.copy(candidate.keys),
            coords = vector3(candidate.coords.x, candidate.coords.y, candidate.coords.z),
            distance = math.sqrt(candidate.distanceSquared),
            busy = candidate.busy,
            isSpot = candidate.spot ~= nil,
        }
    end
    return out
end)

--- The stats panel.
exports('OpenPanel', function() Menu.open() end)
exports('ClosePanel', function() Menu.close() end)
exports('IsPanelOpen', function() return Menu.isOpen() end)

--- The computed value of one effect at the player's current stats, or nil when that effect
--- is disabled. Named as in Config.Effects: 'meleeDamage', 'underwaterTime', 'sprintSpeed'...
exports('GetEffectValue', function(statKey, effectName)
    local block = Config.Effects[statKey]
    if type(block) ~= 'table' then return nil end
    return Stats.bonus(statKey, block[effectName], State.get(statKey))
end)

--- Wind the player. `factor` is how much of their sprint bonus survives (0 removes the
--- sprint key entirely); `seconds` is how long. The hook a drug or an injury script wants.
exports('Exhaust', function(factor, seconds)
    Effects.exhaust(factor, seconds)
    return true
end)

--- Refill the sprint bar. `fraction` is 0..1.
exports('RestoreStamina', function(fraction)
    Effects.restoreStamina(fraction)
    return true
end)

--- Whether the player is winded, and for how many more seconds.
exports('GetExhaustion', function()
    return Effects.exhaustion()
end)

--- Force an effect to a value for a while, bypassing the stat entirely.
--- `mode` is 'set' or 'multiply'; `seconds` of 0 means until cleared.
exports('SetEffectOverride', function(name, value, seconds, mode)
    return Effects.setOverride(name, value, seconds, mode)
end)

exports('ClearEffectOverride', function(name)
    return Effects.clearOverride(name)
end)

exports('ClearEffectOverrides', function()
    Effects.clearOverrides()
    return true
end)

--- The catalogue, for a resource building its own menu of what a gym offers.
exports('GetEquipment', function()
    local out = {}
    for _, key in ipairs(Equipment.keys) do
        local entry = Equipment.get(key)
        out[key] = {
            label = Locale.text(entry.label or key),
            description = Locale.text(entry.description or ''),
            gains = Sport.copy(entry.gains),
            reps = Equipment.reps(entry),
            difficulty = entry.difficulty,
            cooldown = Equipment.cooldown(entry),
            cooldownLeft = State.cooldownLeft(key),
        }
    end
    return out
end)
