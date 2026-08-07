--[[
    bridge/server/framework.lua

    The server's half of the compatibility layer. Everything the server needs to know about a
    player - who they are, what job they hold, whether they have an item - is asked for here,
    so no file above this one names a framework.

    ---------------------------------------------------------------------------------------
    HOW A FRAMEWORK IS ADDED
    ---------------------------------------------------------------------------------------

    Each one is an ADAPTER: a table of small functions with the same names. `Bridge.core()`
    picks the first whose resource is started and whose handshake answers, and every
    `Bridge.*` function below calls through the chosen adapter. Nothing branches on a
    framework name outside this file.

    Four are shipped, under three adapters:

        qb-core / qbx_core    the same PlayerData shape and the same GetCoreObject export,
                              so one adapter serves both
        es_extended (ESX)     a different object, a different notification path, and no
                              citizenid - the identifier is the stable key instead
        ox_core               a different object again, with groups instead of jobs

    Anything else degrades to standalone: the resource keys stats on the Rockstar licence and
    everything keeps working. That is a supported configuration, not a failure mode.

    Set Config.Compat.forceFramework to skip detection on a server that has two installed.
]]

Bridge = {}

local core
local adapter
local frameworkName

local function started(resource)
    if not resource or resource == '' then return false end
    local state = GetResourceState(resource)
    return state == 'started' or state == 'starting'
end

--[[
    Read a field from the framework object without raising.

    ox_core's "core object" IS its exports table, and in FiveM indexing an export that does
    not exist RAISES rather than returning nil. So any `core.Functions` written for qb-core's
    shape is a crash on an ox_core server.
]]
local function field(object, name)
    if type(object) ~= 'table' then return nil end
    local ok, value = pcall(function() return object[name] end)
    if not ok then return nil end
    return value
end

--[[
    Call `fn` and return its result, or nil if it threw. Every call into somebody else's code
    goes through here: a framework that changed a signature between versions must degrade,
    never take this resource down with it.

    THE GATE IS Sport.callable, NEVER type(fn) == 'function'. A framework method that has
    crossed a resource boundary is a table with a __call metamethod, and on stock qb-core -
    which does not export GetPlayer, so the fallback is the only path - a type test here meant
    no player was ever resolved and no stats were ever loaded. Sport.callable carries the
    measurement.
]]
local function try(fn, ...)
    if not Sport.callable(fn) then return nil end
    local ok, result = pcall(fn, ...)
    if not ok then return nil end
    return result
end

-- ---------------------------------------------------------------------------------------
-- The adapters
-- ---------------------------------------------------------------------------------------

local ADAPTERS = {}

--[[
    qb-core and qbx_core.

    qbx_core publishes the same GetCoreObject export and the same PlayerData shape, so it
    needs no separate adapter.
]]
ADAPTERS.qb = {
    resources = { 'qb-core', 'qbx_core' },

    handshake = function(resource)
        local object = try(function() return exports[resource]:GetCoreObject() end)
        return type(object) == 'table' and object or nil
    end,

    player = function(object, src)
        -- qb-core moved GetPlayer to a resource export and kept the Functions one as an
        -- alias. Try the export first so a build that dropped the alias still works.
        local player = try(function() return exports[frameworkName]:GetPlayer(src) end)
        if type(player) == 'table' then return player end

        local functions = field(object, 'Functions')
        if functions and functions.GetPlayer then
            player = try(functions.GetPlayer, src)
            if type(player) == 'table' then return player end
        end

        return nil
    end,

    characterId = function(_, player)
        return player and player.PlayerData and player.PlayerData.citizenid or nil
    end,

    license = function(_, player)
        return player and player.PlayerData and player.PlayerData.license or nil
    end,

    name = function(_, player)
        local data = player and player.PlayerData
        local charinfo = data and data.charinfo
        if not charinfo then return nil end
        return ((charinfo.firstname or '') .. ' ' .. (charinfo.lastname or '')):gsub('^%s+', '')
    end,

    roles = function(_, player)
        local data = player and player.PlayerData
        if not data then return nil end
        return {
            job = (data.job and data.job.name) or '',
            jobType = (data.job and data.job.type) or '',
            grade = tostring((data.job and data.job.grade and data.job.grade.level) or ''),
            gang = (data.gang and data.gang.name) or '',
        }
    end,

    hasItem = function(_, player, item)
        if not player then return false end

        -- ox_inventory answers for qb servers that swapped their inventory out, and its
        -- export is the cheapest check when it is there.
        if started('ox_inventory') then
            local count = try(function() return exports.ox_inventory:GetItemCount(player.PlayerData.source, item) end)
            if type(count) == 'number' then return count > 0 end
        end

        local functions = field(player, 'Functions')
        if functions and functions.GetItemByName then
            local found = try(functions.GetItemByName, item)
            return type(found) == 'table' and (tonumber(found.amount) or 0) > 0
        end

        return false
    end,

    isCuffed = function(_, player)
        local data = player and player.PlayerData
        local meta = data and data.metadata
        if type(meta) ~= 'table' then return false end
        return meta.ishandcuffed == true or meta.handcuffed == true
    end,

    notify = function(object, src, message, kind)
        local functions = field(object, 'Functions')
        if functions and functions.Notify then
            return pcall(functions.Notify, src, message, kind or 'primary')
        end
        return false
    end,

    isAdmin = function(object, src)
        local functions = field(object, 'Functions')
        if functions and functions.HasPermission then
            return try(functions.HasPermission, src, 'admin') == true
        end
        return false
    end,

    addCommand = function(object, name, help, args, restricted, handler)
        local commands = field(object, 'Commands')
        if not (commands and commands.Add) then return false end
        -- The sixth argument is a PERMISSION STRING ('admin'), not a boolean. Passing `true`
        -- makes qb-core print a warning trace on every boot, because it tries to build an
        -- ace name out of it.
        return pcall(commands.Add, name, help, args or {}, false, handler,
            restricted and 'admin' or nil)
    end,
}

--[[
    ESX (es_extended).

    No citizenid: the character key IS the identifier, which is stable per character on a
    multicharacter ESX and per account without one. No gang either, so Config.Decay.exemptJobs
    keys of the form 'gang:name' simply never match on an ESX server; the job grade is exposed
    as `grade` and is the closest thing an operator will want to key on.
]]
ADAPTERS.esx = {
    resources = { 'es_extended' },

    handshake = function(resource)
        -- Modern ESX publishes an export; older builds only answer the event.
        local object = try(function() return exports[resource]:getSharedObject() end)
        if type(object) == 'table' then return object end

        local fetched
        try(function() TriggerEvent('esx:getSharedObject', function(o) fetched = o end) end)
        return type(fetched) == 'table' and fetched or nil
    end,

    player = function(object, src)
        local player = try(object.GetPlayerFromId, src)
        return type(player) == 'table' and player or nil
    end,

    characterId = function(_, player)
        return player and player.identifier or nil
    end,

    license = function(_, player)
        return player and player.identifier or nil
    end,

    name = function(_, player)
        return player and (player.getName and try(player.getName) or player.name) or nil
    end,

    roles = function(_, player)
        if not player then return nil end
        local job = player.job or {}
        return {
            job = job.name or '',
            -- No job "type" in ESX. The grade name is the closest equivalent and is what an
            -- operator will reach for.
            jobType = job.grade_name or '',
            grade = tostring(job.grade or ''),
            gang = '',
        }
    end,

    hasItem = function(_, player, item)
        if not player then return false end

        if started('ox_inventory') then
            local count = try(function() return exports.ox_inventory:GetItemCount(player.source, item) end)
            if type(count) == 'number' then return count > 0 end
        end

        if player.getInventoryItem then
            local found = try(player.getInventoryItem, item)
            return type(found) == 'table' and (tonumber(found.count) or 0) > 0
        end

        return false
    end,

    isCuffed = function(_, player)
        -- ESX has no core cuffed flag. esx_policejob keeps it on the client, so the honest
        -- answer here is "unknown", and the client-side check in client/session.lua is what
        -- actually catches it.
        local meta = player and player.getMeta and try(player.getMeta, 'handcuffed')
        return meta == true
    end,

    notify = function(_, src, message, kind)
        local types = { primary = 'info', success = 'success', error = 'error' }
        TriggerClientEvent('esx:showNotification', src, message, types[kind] or 'info')
        return true
    end,

    isAdmin = function(object, src)
        local player = try(object.GetPlayerFromId, src)
        local group = player and player.getGroup and try(player.getGroup)
        return group == 'admin' or group == 'superadmin' or group == 'owner'
    end,

    addCommand = function(object, name, help, args, restricted, handler)
        -- field(), not object.RegisterCommand: the raw index raises on an exports-table core.
        -- Sport.callable, not a type test: a method read off a shared object is a callable table.
        local register = field(object, 'RegisterCommand')
        if not Sport.callable(register) then return false end

        --[[
            ESX's signature is (name, group, cb, allowConsole, suggestion), and its callback gets
            (xPlayer, args, showError) rather than (source, rawArgs). Adapted here rather than
            leaking the difference to the caller.

            TWO CORRECTIONS. `object.RegisterCommand` is a METHOD, so it needs `object` as its first
            argument - called without it, ESX read the command name as its own self and registered
            nothing, which is why /vsportadmin did not exist on ESX.

            And `validate = false` with `arguments` set is contradictory: ESX validates when it is
            given an argument list, and this resource does its own argument handling. The suggestion
            carries the help text only.
        ]]
        return pcall(register, object, name,
            restricted and 'admin' or 'user',
            function(xPlayer, commandArgs)
                handler(xPlayer and xPlayer.source or 0, commandArgs)
            end, true, { help = help, validate = false, arguments = args or {} })
    end,
}

--[[
    ox_core.

    Groups rather than jobs, and metadata through get/set on the player object. ox_core ships
    no notification system, so notifications fall through to this resource's own toast, which
    is the correct answer rather than a compromise.
]]
ADAPTERS.ox = {
    resources = { 'ox_core' },

    handshake = function(resource)
        local ok = try(function() return exports[resource]:GetPlayers() end)
        if ok == nil then return nil end
        return exports[resource]
    end,

    player = function(object, src)
        local player = try(function() return object:GetPlayer(src) end)
        return type(player) == 'table' and player or nil
    end,

    characterId = function(_, player)
        return player and (player.stateId or player.charId) and
            tostring(player.stateId or player.charId) or nil
    end,

    license = function(_, player)
        return player and player.userId and tostring(player.userId) or nil
    end,

    name = function(_, player)
        if not player then return nil end
        return ((player.firstName or '') .. ' ' .. (player.lastName or '')):gsub('^%s+', '')
    end,

    roles = function(_, player)
        if not player then return nil end

        local groups = player.getGroups and try(player.getGroups) or nil
        local name, grade = '', ''
        if type(groups) == 'table' then
            for group, rank in pairs(groups) do
                name, grade = group, tostring(rank)
                break
            end
        end

        return { job = name, jobType = grade, grade = grade, gang = '' }
    end,

    hasItem = function(_, player, item)
        if not player then return false end
        if not started('ox_inventory') then return false end
        local count = try(function() return exports.ox_inventory:GetItemCount(player.source, item) end)
        return type(count) == 'number' and count > 0
    end,

    isCuffed = function(_, player)
        return player and player.get and try(player.get, 'handcuffed') == true
    end,

    notify = function()
        -- Nothing of its own. Bridge.notify falls through to this resource's toast.
        return false
    end,

    isAdmin = function()
        -- ox_core leans on aces, which Bridge.isAdmin already checked before asking.
        return false
    end,

    addCommand = function()
        -- No command registry to hook; the plain RegisterCommand fallback is used.
        return false
    end,
}

-- Detection order. qb first because it is the most common and the cheapest handshake.
local ORDER = { 'qb', 'esx', 'ox' }

-- ---------------------------------------------------------------------------------------
-- Resolution
-- ---------------------------------------------------------------------------------------

--- The core object, or nil. Resolved on first use rather than at load, because a framework
--- further down server.cfg has not started yet when this file runs.
function Bridge.core()
    if core then return core end

    local forced = Config.Compat and Config.Compat.forceFramework or ''

    for _, key in ipairs(ORDER) do
        local candidate = ADAPTERS[key]
        for _, resource in ipairs(candidate.resources) do
            local wanted = forced == '' or forced == resource
            if wanted and started(resource) then
                local object = candidate.handshake(resource)
                if object then
                    core, adapter, frameworkName = object, candidate, resource
                    Sport.debug('server framework:', resource)
                    return core
                end
            end
        end
    end

    return nil
end

--- The framework's name, or 'standalone'. Printed by /sportinfo.
function Bridge.framework()
    Bridge.core()
    return frameworkName or 'standalone'
end

--- The player object for `src`, or nil. Every caller has to cope with nil: a player can drop
--- between a client event being sent and the server handling it.
function Bridge.player(src)
    local object = Bridge.core()
    if not object then return nil end
    return adapter.player(object, src)
end

--[[
    The identifier stats are stored against, honouring Config.Persistence.scope.

    Returns nil when the player is not loaded yet, and EVERY caller treats that as "do not
    load or save yet" rather than as an error. A character that has not finished spawning
    has no citizenid, and writing a row keyed on nil would merge two players' progress.
]]
function Bridge.identifier(src)
    local object = Bridge.core()
    local player = object and adapter.player(object, src) or nil

    --[[
        "NOT LOADED YET" HAS TO ANSWER NIL, and it did not, which silently turned the default
        scope = 'character' into scope = 'license' on the one framework that has been tested.

        The old condition was `scope == 'license' or not player`, and the branch below always
        succeeds: GetPlayerIdentifiers works from the moment somebody connects. So a call made
        before the character loaded returned a licence rather than nil - and the caller in
        server/stats.lua retries for twenty seconds ON NIL ONLY, so it never retried. The profile
        was created keyed on the licence, and the framework's own PlayerLoaded event, arriving
        later with the real citizenid, was dropped by `if profiles[src] then return end`.

        The trigger is routine rather than exotic: client/state.lua announces the player as soon as
        the session has started and a ped exists, which on qb-core is true while the
        multicharacter selector is still open - seconds before GetPlayer(src) returns anything. So
        every join took the licence, and every character on an account shared one body.

        Now the licence is only used when it is genuinely the answer: standalone (no core object),
        or an operator who asked for licence scope. With a framework present and the character not
        loaded, this returns nil, the retry loop does the waiting it was written for, and if it
        gives up the framework's own load event triggers a fresh, correctly keyed load.
    ]]
    if Config.Persistence.scope == 'license' or not object then
        if player then
            local license = adapter.license(object, player)
            if license and license ~= '' then return license end
        end

        -- Standalone, or an operator who asked for account-wide progress. The Rockstar licence is
        -- the only identifier that is always available and always stable.
        for _, identifier in ipairs(GetPlayerIdentifiers(src) or {}) do
            if identifier:sub(1, 8) == 'license:' then return identifier end
        end
        return nil
    end

    -- A framework is present and has not finished loading this character. Answer nil so the caller
    -- waits, rather than keying a row on something that is not the character.
    if not player then return nil end

    local characterId = adapter.characterId(object, player)
    if characterId and characterId ~= '' then return characterId end

    return nil
end

--- The character's name, for console logs and the admin command. Falls back to the Rockstar
--- username, which always exists.
function Bridge.name(src)
    local object = Bridge.core()
    local player = object and adapter.player(object, src) or nil
    local name = player and adapter.name(object, player) or nil

    if type(name) == 'string' and name ~= '' then return name end
    return GetPlayerName(src) or ('player ' .. tostring(src))
end

--- Job name, job type, grade and gang. Empty strings rather than nil, so a caller can index
--- a config table with them without a guard.
function Bridge.roles(src)
    local object = Bridge.core()
    local player = object and adapter.player(object, src) or nil
    local roles = player and adapter.roles(object, player) or nil

    return roles or { job = '', jobType = '', grade = '', gang = '' }
end

--- Whether the player is exempt from decay, by job name, job type or gang.
function Bridge.decayExempt(src)
    local exempt = Config.Decay.exemptJobs
    if type(exempt) ~= 'table' or next(exempt) == nil then return false end

    local roles = Bridge.roles(src)
    return exempt[roles.job] == true
        or exempt[roles.jobType] == true
        or exempt['gang:' .. roles.gang] == true
end

--- Whether the player holds `item`. Fails CLOSED: a server with no readable inventory
--- answers "no", so an equipment `require.item` gate is never accidentally open.
function Bridge.hasItem(src, item)
    if type(item) ~= 'string' or item == '' then return true end

    local object = Bridge.core()
    local player = object and adapter.player(object, src) or nil
    if not player then return false end

    return adapter.hasItem(object, player, item) == true
end

--- Whether the player is handcuffed, as far as the framework knows. Unknown reads as false;
--- the client-side check is the one that actually catches it on ESX.
function Bridge.isCuffed(src)
    local object = Bridge.core()
    local player = object and adapter.player(object, src) or nil
    if not player then return false end
    return adapter.isCuffed(object, player) == true
end

--- Notify a player, through the framework when it has one and through this resource's own
--- native toast when it does not.
function Bridge.notify(src, message, kind)
    if type(message) ~= 'string' or message == '' then return end

    if not Config.Notifications.preferOwnToast then
        local object = Bridge.core()
        if object and adapter.notify(object, src, message, kind) then return end
    end

    TriggerClientEvent('vsport:client:Toast', src, message, kind or 'primary')
end

--- Whether `src` may run the admin commands. The console (source 0) always may.
function Bridge.isAdmin(src)
    if src == 0 then return true end

    local ace = Config.Commands.adminAce
    if ace and ace ~= '' and IsPlayerAceAllowed(src, ace) then return true end

    -- Fall back to the framework's own idea of staff, so a server that never set the ace up
    -- is not locked out of its own admin command.
    local object = Bridge.core()
    if object and adapter.isAdmin(object, src) then return true end

    return false
end

--- Register a command through the framework's own registry when there is one, so it appears
--- in the chat suggestions, and through plain RegisterCommand when there is not.
function Bridge.addCommand(name, help, args, restricted, handler)
    if type(name) ~= 'string' or name == '' then return end

    local object = Bridge.core()
    if object and adapter.addCommand(object, name, help, args, restricted, handler) then
        return
    end

    RegisterCommand(name, function(source, rawArgs)
        if restricted and not Bridge.isAdmin(source) then
            Bridge.notify(source, L('notify.no_permission'), 'error')
            return
        end
        handler(source, rawArgs)
    end, false)

    if restricted then
        -- Only meaningful for the plain fallback; the framework registries police themselves.
        TriggerEvent('chat:addSuggestion', '/' .. name, help, args or {})
    end
end

-- ---------------------------------------------------------------------------------------
-- Load and unload
-- ---------------------------------------------------------------------------------------
--
-- Every framework announces a loaded character differently, and several announce it more than
-- once. `Bridge.onPlayerLoaded` is called with a source; server/stats.lua deduplicates, so a
-- framework that fires twice costs one extra table lookup rather than two database reads.

local loadedHandler

--- Register the callback fired when a character finishes loading. One handler, set by
--- server/stats.lua; this is not a general event bus.
function Bridge.onPlayerLoaded(handler)
    loadedHandler = handler
end

local function announceLoaded(src)
    if not loadedHandler or not src or src == 0 then return end
    loadedHandler(tonumber(src))
end

-- qb-core / qbx_core
RegisterNetEvent('QBCore:Server:PlayerLoaded', function(player)
    announceLoaded(type(player) == 'table' and player.PlayerData and player.PlayerData.source or source)
end)
RegisterNetEvent('QBCore:Server:OnPlayerLoaded', function()
    announceLoaded(source)
end)

--[[
    ESX. `source` ONLY - the argument is ignored.

    This is a NET event, so a client can fire it, and it used to prefer the id in the payload: any
    player could trigger a profile load for any other server id. Nothing catastrophic followed - the
    load is idempotent and keyed on the target's own identifier - but it let one player make the
    server do work on another's behalf, which is not a decision a client gets to make.

    ESX fires this server-side with the source set correctly, so ignoring the argument costs nothing.
]]
RegisterNetEvent('esx:playerLoaded', function()
    announceLoaded(source)
end)

-- ox_core. AddEventHandler, not RegisterNetEvent: this one cannot be fired by a client, so its
-- argument is the server's own and safe to prefer.
AddEventHandler('ox:playerLoaded', function(src)
    announceLoaded(src or source)
end)

--[[
    The catch-all.

    Some frameworks fire nothing the server can hear, some fire before the identifier is
    readable, and a standalone server fires nothing at all. So the client also says hello once
    it has spawned, and this handler is what makes the resource work with no framework and
    with a framework nobody has written an adapter for.

    Deduplication is server/stats.lua's job, which is why this can be unconditional.
]]
RegisterNetEvent('vsport:server:PlayerReady', function()
    announceLoaded(source)
end)
