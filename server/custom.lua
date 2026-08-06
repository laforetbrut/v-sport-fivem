--[[
    server/custom.lua

    Adding and aligning equipment from inside the game, with no file to edit and no restart.

    ---------------------------------------------------------------------------------------
    THE WHOLE FLOW, FOR A GYM MLO NOBODY HAS EVER SEEN
    ---------------------------------------------------------------------------------------

        walk up to the treadmill
        /vsportadd treadmill                 <- no model name to type; it uses what you face
        /vsportprop treadmill                <- align the body in the studio
        press ENTER                          <- saved, live, for everyone

    That is it. No config.lua, no restart, no copying blocks out of F8. When it is proven,
    /vsportexport prints the same thing as a config.lua block so it can graduate into version
    control.

    ---------------------------------------------------------------------------------------
    WHO IS TRUSTED WITH WHAT
    ---------------------------------------------------------------------------------------

    The CLIENT decides which prop the admin is looking at, because only the client can see the
    object pool, and validates the model with IsModelValid so a typo cannot be written into a file
    that is read at every boot from now on.

    The SERVER decides whether that player may change anything, and it re-checks Bridge.isAdmin on
    every event rather than trusting the gate the client was given. It also re-validates the model
    NAME, because a client can send whatever it likes and this one ends up on disk.

    ---------------------------------------------------------------------------------------
    WHAT IT COSTS
    ---------------------------------------------------------------------------------------

    Nothing at steady state. The file is read once at boot and written only when something changes,
    debounced so that holding a tuner key does not write a file per frame. The overlay is pushed to
    a client once when it joins and once per change - a handful of small events over a session.
]]

Custom.store = {}               -- key -> entry, in STORAGE shape (plain tables, not vector3)

local FILE = 'data/custom.json'
local dirty = false
local writeAt = nil             -- game time to flush at, for the debounce

-- ---------------------------------------------------------------------------------------
-- Disk
-- ---------------------------------------------------------------------------------------

--[[
    Read the overlay off disk.

    Every failure here is survivable and none of them may take the resource down: a missing file is
    the normal first boot, and a corrupt one is somebody's half-finished hand edit. Both end with an
    empty overlay and a warning, because the alternative - a resource that refuses to start because
    of a stray comma in an optional file - is worse than losing the additions.
]]
local function readFile()
    local raw = LoadResourceFile(Sport.resource, FILE)

    if not raw or raw == '' then
        Sport.debug('no ' .. FILE .. ' yet, starting with no custom equipment')
        return {}
    end

    local ok, decoded = pcall(json.decode, raw)
    if not ok or type(decoded) ~= 'table' then
        Sport.warn(FILE .. ' could not be parsed and was ignored. Fix or delete it; '
            .. 'nothing has been overwritten.')
        return {}
    end

    -- A version field so a future format change can migrate rather than guess.
    local entries = type(decoded.equipment) == 'table' and decoded.equipment or {}

    local count = 0
    for _ in pairs(entries) do count = count + 1 end
    Sport.print(('loaded %d custom equipment entr%s from %s')
        :format(count, count == 1 and 'y' or 'ies', FILE))

    return entries
end

--- Write the overlay to disk. Called from the debounce, never directly from a command.
local function writeFile()
    local payload = json.encode({
        version = 1,
        note = 'Managed by v-sport. Written by /vsportadd, /vsportremove and the tuner. '
            .. 'Safe to delete: you lose the additions, nothing else. '
            .. 'Use /vsportexport to move them into config.lua permanently.',
        equipment = Custom.store,
    })

    if SaveResourceFile(Sport.resource, FILE, payload, -1) then
        Sport.debug('wrote ' .. FILE)
        return true
    end

    Sport.warn('could not write ' .. FILE .. ' - is the resource folder read-only? '
        .. 'The change is live but will be lost on restart. Use /vsportexport to keep it.')
    return false
end

--[[
    Mark the overlay changed, and flush shortly.

    Debounced because the tuner can save on a key repeat: without this, holding an arrow key while
    aligned to a prop would write the same file dozens of times a second. Two seconds is long enough
    to coalesce a burst and short enough that nobody who types /vsportadd and immediately restarts
    loses the change.
]]
local function touch()
    dirty = true
    writeAt = GetGameTimer() + 2000
end

CreateThread(function()
    while true do
        Wait(500)
        if dirty and writeAt and GetGameTimer() >= writeAt then
            dirty = false
            writeAt = nil
            writeFile()
        end
    end
end)

-- Never lose a pending write because somebody restarted the resource two seconds too early.
AddEventHandler('onResourceStop', function(resource)
    if resource ~= Sport.resource then return end
    if dirty then writeFile() end
end)

-- ---------------------------------------------------------------------------------------
-- Applying and broadcasting
-- ---------------------------------------------------------------------------------------

--- Rebuild the server's own catalogue from the overlay, and push it to clients.
--- `target` pushes to one player - for a join - and nil broadcasts to everyone.
function Custom.apply(target)
    Equipment.overlay = Custom.unpackAll(Custom.store)
    Equipment.build()

    -- The clients get the STORAGE shape and unpack it themselves, so the vector3 conversion
    -- happens on exactly one side of the wire and cannot disagree with itself.
    TriggerClientEvent('vsport:client:CustomEquipment', target or -1, Custom.store)
end

CreateThread(function()
    -- After the catalogue's own build at the bottom of shared/equipment.lua.
    Wait(0)
    Custom.store = readFile()
    Equipment.overlay = Custom.unpackAll(Custom.store)
    Equipment.build()
end)

AddEventHandler('vsport:server:PlayerLoaded', function(src)
    if next(Custom.store) == nil then return end
    TriggerClientEvent('vsport:client:CustomEquipment', src, Custom.store)
end)

-- ---------------------------------------------------------------------------------------
-- Changes, all of them from a client and all of them re-authorised here
-- ---------------------------------------------------------------------------------------

--- Refuse anything from a player the server does not consider staff. Returns true when allowed.
local function authorised(src, what)
    if Config.Commands.restrictDevCommands == false then return true end
    if Bridge.isAdmin(src) then return true end

    Sport.warn(('%s (%s) tried to %s without permission'):format(
        GetPlayerName(src) or '?', tostring(src), what))
    Bridge.notify(src, L('notify.no_permission'), 'error')
    return false
end

--- The stored entry for `key`, created empty if it does not exist yet.
local function entryFor(key)
    local entry = Custom.store[key]
    if not entry then
        entry = {}
        Custom.store[key] = entry
    end
    return entry
end

--[[
    Add a model to an exercise.

    The model joins the SHIPPED list rather than replacing it, which is the behaviour an operator
    expects from "add" and is not what Sport.merge does on its own - it replaces a list wholesale.
    So the stored list is the shipped models plus the additions, rebuilt each time.
]]
RegisterNetEvent('vsport:server:CustomAdd', function(key, model)
    local src = source
    if not authorised(src, 'add equipment') then return end

    if type(key) ~= 'string' or not Custom.validModelName(model) then
        Bridge.notify(src, L('custom.bad_input'), 'error')
        return
    end

    -- The exercise has to exist. Creating one from a chat command would need gains, reps, a
    -- difficulty and an animation, none of which a command line is a good place for - config.lua
    -- is, and PROPS.md documents it.
    local shipped = Equipment.shipped and Equipment.shipped[key]
    if type(shipped) ~= 'table' then
        Bridge.notify(src, L('custom.no_exercise', key), 'error')
        return
    end

    local entry = entryFor(key)

    --[[
        SEED FROM WHAT IS STORED, NOT FROM WHAT SHIPS, once anything has been stored.

        Merging the shipped list in on every add UNDID every removal: /vsportremove wrote a shorter
        list, and the next /vsportadd on the same exercise rebuilt it from the shipped models and
        brought the removed one back. Two commands, opposite intents, and the second silently won.

        A stored list is the operator's current answer for this exercise. Shipped models are only the
        starting point for an entry nobody has touched yet.
    ]]
    local base = (type(entry.models) == 'table' and #entry.models > 0)
        and entry.models
        or (shipped.models or {})

    local models, seen = {}, {}
    for _, name in ipairs(base) do
        if type(name) == 'string' and not seen[name] then
            seen[name] = true
            models[#models + 1] = name
        end
    end

    if seen[model] then
        Bridge.notify(src, L('custom.already', model, key), 'error')
        return
    end

    models[#models + 1] = model
    entry.models = models

    -- An MLO-only exercise stops being MLO-only the moment it has a model.
    if shipped.mloOnly then entry.mloOnly = false end

    -- And a disabled one is presumably being added to because somebody wants it back.
    if shipped.enabled == false then entry.enabled = true end

    touch()
    Custom.apply()

    Sport.print(('%s added %s to %s'):format(GetPlayerName(src) or src, model, key))
    Bridge.notify(src, L('custom.added', model, key), 'success')
end)

--- Remove a model that was added. Shipped models can be removed too - a bench that your MLO
--- replaced with its own geometry is a real case - and the removal is remembered.
RegisterNetEvent('vsport:server:CustomRemove', function(key, model)
    local src = source
    if not authorised(src, 'remove equipment') then return end

    if type(key) ~= 'string' or not Custom.validModelName(model) then
        Bridge.notify(src, L('custom.bad_input'), 'error')
        return
    end

    local shipped = Equipment.shipped and Equipment.shipped[key]
    if type(shipped) ~= 'table' then
        Bridge.notify(src, L('custom.no_exercise', key), 'error')
        return
    end

    local entry = entryFor(key)
    local current = entry.models or shipped.models or {}

    local kept, removed = {}, false
    for _, name in ipairs(current) do
        if name == model then
            removed = true
        else
            kept[#kept + 1] = name
        end
    end

    if not removed then
        Bridge.notify(src, L('custom.not_listed', model, key), 'error')
        return
    end

    entry.models = kept

    touch()
    Custom.apply()

    Sport.print(('%s removed %s from %s'):format(GetPlayerName(src) or src, model, key))
    Bridge.notify(src, L('custom.removed', model, key), 'success')
end)

--[[
    Save an alignment from the tuner.

    `payload` is one model's placement: animOffset, animHeading, animRot and the held props, in
    STORAGE shape. It is written as a modelOverrides entry rather than onto the exercise itself,
    which is what makes it safe - aligning one bench cannot move the body on the other five.
]]
RegisterNetEvent('vsport:server:CustomAlign', function(key, model, payload)
    local src = source
    if not authorised(src, 'save an alignment') then return end

    if type(key) ~= 'string' or not Custom.validModelName(model)
        or type(payload) ~= 'table' then
        Bridge.notify(src, L('custom.bad_input'), 'error')
        return
    end

    local shipped = Equipment.shipped and Equipment.shipped[key]
    if type(shipped) ~= 'table' then
        Bridge.notify(src, L('custom.no_exercise', key), 'error')
        return
    end

    local entry = entryFor(key)
    entry.modelOverrides = type(entry.modelOverrides) == 'table' and entry.modelOverrides or {}

    -- Only the fields a placement consists of. Anything else the client sent is discarded rather
    -- than merged, so a modified client cannot write arbitrary keys into an equipment entry.
    local clean = {
        placeAnim = true,
        animOffset = payload.animOffset,
        animHeading = tonumber(payload.animHeading),
        animRot = payload.animRot,
        props = payload.props,
    }

    entry.modelOverrides[model] = Custom.pack(clean)

    -- A placement is meaningless unless the exercise places its animation at all.
    entry.placeAnim = true

    touch()
    Custom.apply()

    Sport.print(('%s saved an alignment for %s on %s')
        :format(GetPlayerName(src) or src, model, key))
    Bridge.notify(src, L('custom.aligned', model, key), 'success')
end)

--- Forget everything stored for one exercise, or all of it.
RegisterNetEvent('vsport:server:CustomReset', function(key)
    local src = source
    if not authorised(src, 'reset custom equipment') then return end

    if key == nil or key == '' or key == 'all' then
        Custom.store = {}
        Bridge.notify(src, L('custom.reset_all'), 'success')
    elseif type(key) == 'string' and Custom.store[key] then
        Custom.store[key] = nil
        Bridge.notify(src, L('custom.reset_one', key), 'success')
    else
        Bridge.notify(src, L('custom.nothing_stored'), 'error')
        return
    end

    touch()
    Custom.apply()
end)

--- Re-read the file, for someone who edited it by hand or restored a backup.
RegisterNetEvent('vsport:server:CustomReload', function()
    local src = source
    if not authorised(src, 'reload custom equipment') then return end

    Custom.store = readFile()
    Custom.apply()

    Bridge.notify(src, L('custom.reloaded'), 'success')
end)

--[[
    Print the overlay as a config.lua block, to whoever asked and to the server console.

    THE POINT OF THIS COMMAND IS GRADUATION. data/custom.json is convenient and it is not version
    control: it is one deleted folder away from gone, and it does not travel with an update. An
    addition proven in game belongs in config.lua, and this is what makes moving it a paste.
]]
RegisterNetEvent('vsport:server:CustomExport', function()
    local src = source
    if not authorised(src, 'export custom equipment') then return end

    local lines = {}
    local function say(text) lines[#lines + 1] = text end

    if next(Custom.store) == nil then
        say('nothing has been added in game yet - data/custom.json is empty')
    else
        say('-- Paste into config.lua, then /vsportreset to clear data/custom.json.')
        say('Config.ExtraEquipment = {')
        for key in pairs(Custom.store) do
            for _, line in ipairs(Custom.toLua(key, Custom.unpack(Custom.store[key]))) do
                say(line)
            end
        end
        say('}')
    end

    print('^5==== v-sport: your custom equipment as config.lua ====^7')
    for _, line in ipairs(lines) do print(line) end
    print('^5======================================================^7')

    -- To the caller's own console too, so an admin in game does not need server console access.
    if src and src ~= 0 then
        TriggerClientEvent('vsport:client:CustomExport', src, lines)
    end
end)

-- ---------------------------------------------------------------------------------------
-- A read-only view, for a menu or another resource
-- ---------------------------------------------------------------------------------------

exports('GetCustomEquipment', function()
    return Custom.unpackAll(Custom.store)
end)
