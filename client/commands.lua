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
-- /sportinfo
-- ---------------------------------------------------------------------------------------

if Config.Commands.info and Config.Commands.info ~= '' then
    RegisterCommand(Config.Commands.info, function()
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
