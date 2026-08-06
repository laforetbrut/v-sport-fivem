--[[
    bridge/client/compat.lua

    Runtime detection of everything optional on the client: the framework, the target
    resource, the notification provider and the sound player.

    Loads FIRST among the client scripts, because every file below asks it what is installed.

    Nothing here is required. A server with none of it runs the built-in key prompt and the
    built-in native toast, which is a supported configuration and the one the resource is
    tested against most.
]]

Compat = {}

local function started(resource)
    if not resource or resource == '' then return false end
    local state = GetResourceState(resource)
    return state == 'started' or state == 'starting'
end

local function try(fn, ...)
    if type(fn) ~= 'function' then return nil end
    local ok, result = pcall(fn, ...)
    if not ok then return nil end
    return result
end

-- ---------------------------------------------------------------------------------------
-- Framework
-- ---------------------------------------------------------------------------------------

local frameworkName
local frameworkObject

--- The client-side core object, or nil. Only three things are asked of it - the job, the
--- cuffed flag and whether the character is loaded - so the surface is deliberately tiny.
function Compat.framework()
    if frameworkName then return frameworkName, frameworkObject end

    local forced = Config.Compat.forceFramework or ''

    local candidates = {
        { resource = 'qb-core', kind = 'qb' },
        { resource = 'qbx_core', kind = 'qb' },
        { resource = 'es_extended', kind = 'esx' },
        { resource = 'ox_core', kind = 'ox' },
    }

    for _, candidate in ipairs(candidates) do
        if (forced == '' or forced == candidate.resource) and started(candidate.resource) then
            local object

            if candidate.kind == 'qb' then
                object = try(function() return exports[candidate.resource]:GetCoreObject() end)
            elseif candidate.kind == 'esx' then
                object = try(function() return exports[candidate.resource]:getSharedObject() end)
                if type(object) ~= 'table' then
                    try(function()
                        TriggerEvent('esx:getSharedObject', function(o) object = o end)
                    end)
                end
            else
                object = try(function() return exports[candidate.resource] end)
            end

            if type(object) == 'table' then
                frameworkName, frameworkObject = candidate.resource, object
                Sport.debug('client framework:', frameworkName)
                return frameworkName, frameworkObject
            end
        end
    end

    frameworkName = 'standalone'
    return frameworkName, nil
end

--[[
    Whether the local player is handcuffed.

    This is the check that actually works on ESX, where the cuffed state lives on the client
    and the server never sees it. Three sources, cheapest first:

      1. The player's own state bag, which is where every modern resource puts it.
      2. qb-core's PlayerData metadata.
      3. The animation itself - a cuffed ped is playing mp_arresting/idle, and a resource
         that tracks cuffs no other way still cannot hide that.
]]
function Compat.isCuffed()
    local state = LocalPlayer.state
    if state then
        if state.handcuffed == true or state.cuffed == true or state.isHandcuffed == true then
            return true
        end
    end

    local name, object = Compat.framework()
    if name == 'qb-core' or name == 'qbx_core' then
        local data = object and try(function() return object.Functions.GetPlayerData() end)
        local meta = type(data) == 'table' and data.metadata or nil
        if type(meta) == 'table' and (meta.ishandcuffed or meta.handcuffed) then return true end
    end

    return IsEntityPlayingAnim(PlayerPedId(), 'mp_arresting', 'idle', 3)
end

--- The local player's job name and gang, or empty strings. Used only by the requirement gate
--- on a piece of equipment; the server re-checks before it pays anything out.
function Compat.roles()
    local name, object = Compat.framework()

    --[[
        `jobType` IS PART OF THE ANSWER, and it was missing from every branch.

        The server's own requirement check reads `roles.jobType`, so `require = { job = 'leo' }` -
        a job TYPE rather than a job name - matched on the server and never on the client. The
        client then refused the session with "this is not for you" before the server was ever asked,
        which reads as the requirement being broken rather than as the client disagreeing.

        And ox_core had no branch at all: it returned the empty fallback, so every job-gated piece of
        equipment was closed to everybody on ox. ox uses GROUPS rather than jobs, so the highest
        group stands in for the job, which is the same substitution the server-side adapter makes.
    ]]
    if name == 'qb-core' or name == 'qbx_core' then
        local data = object and try(function() return object.Functions.GetPlayerData() end)
        if type(data) == 'table' then
            return {
                job = (data.job and data.job.name) or '',
                jobType = (data.job and data.job.type) or '',
                gang = (data.gang and data.gang.name) or '',
            }
        end
    elseif name == 'es_extended' then
        local data = object and try(function() return object.GetPlayerData() end)
        if type(data) == 'table' then
            -- ESX has no job type. Its grade name is the nearest thing, and it is what the
            -- server-side adapter uses, so the two sides agree.
            return {
                job = (data.job and data.job.name) or '',
                jobType = (data.job and data.job.grade_name) or '',
                gang = '',
            }
        end
    elseif name == 'ox_core' then
        local groups = object and try(function() return object.GetPlayerData().groups end)
        if type(groups) == 'table' then
            local best, bestGrade = '', -1
            for group, grade in pairs(groups) do
                if (tonumber(grade) or 0) > bestGrade then
                    best, bestGrade = group, tonumber(grade) or 0
                end
            end
            return { job = best, jobType = best, gang = '' }
        end
    end

    return { job = '', jobType = '', gang = '' }
end

-- ---------------------------------------------------------------------------------------
-- Target
-- ---------------------------------------------------------------------------------------

local targetName

--- 'ox_target' | 'qb-target' | 'qtarget' | 'none'. Resolved once.
function Compat.target()
    if targetName then return targetName end

    local forced = Config.Compat.forceTarget or ''
    if forced ~= '' then
        targetName = forced
        return targetName
    end

    if Config.Interaction.mode == 'key' then
        targetName = 'none'
        return targetName
    end

    for _, resource in ipairs({ 'ox_target', 'qb-target', 'qtarget' }) do
        if started(resource) then
            targetName = resource
            Sport.debug('target:', resource)
            return targetName
        end
    end

    targetName = 'none'
    return targetName
end

--- Whether the resource should use a target rather than its own key prompt.
function Compat.usesTarget()
    if Config.Interaction.mode == 'key' then return false end
    local resolved = Compat.target()
    if resolved == 'none' then return false end
    return started(resolved)
end

--[[
    Register one exercise against a list of models.

    Called once per catalogue entry at boot by client/interact.lua. `onSelect` is handed the
    entity that was targeted.

    Each target resource has its own option shape, and the differences are absorbed here so
    that client/interact.lua contains no resource names.
]]
function Compat.addTargetModels(models, option)
    local resource = Compat.target()
    if resource == 'none' or #models == 0 then return false end

    local distance = tonumber(Config.Interaction.target.distance) or 2.0
    local icon = Config.Interaction.target.icon or 'fa-solid fa-dumbbell'

    if resource == 'ox_target' then
        return try(function()
            exports.ox_target:addModel(models, { {
                name = 'vsport:' .. option.key,
                label = option.label,
                icon = icon,
                distance = distance,
                onSelect = function(data)
                    option.onSelect(data and data.entity or nil)
                end,
                canInteract = function(entity, dist)
                    return option.canInteract(entity, dist)
                end,
            } })
            return true
        end) == true
    end

    -- qb-target and qtarget share a signature. `action` gets the entity; `canInteract` gets
    -- (entity, distance, data) on qb-target and (entity) on some qtarget builds, so only the
    -- first argument is relied on.
    local exportName = resource == 'qb-target' and 'qb-target' or 'qtarget'
    return try(function()
        exports[exportName]:AddTargetModel(models, {
            options = { {
                icon = icon,
                label = option.label,
                action = function(entity)
                    option.onSelect(entity)
                end,
                canInteract = function(entity, dist)
                    return option.canInteract(entity, dist)
                end,
            } },
            distance = distance,
        })
        return true
    end) == true
end

--- Remove everything this resource registered. Called on resource stop so a restart does not
--- leave two copies of every option on the same bench.
function Compat.removeTargetModels(models, names)
    local resource = Compat.target()
    if resource == 'none' or #models == 0 then return end

    if resource == 'ox_target' then
        try(function() exports.ox_target:removeModel(models, names) end)
        return
    end

    local exportName = resource == 'qb-target' and 'qb-target' or 'qtarget'
    try(function() exports[exportName]:RemoveTargetModel(models, names) end)
end

-- ---------------------------------------------------------------------------------------
-- Notifications
-- ---------------------------------------------------------------------------------------

local notifyName

--- 'ox_lib' | 'qb-core' | 'esx' | 'okokNotify' | 'native'. 'native' is this resource's own
--- toast, drawn with DrawRect and DrawText.
function Compat.notifyProvider()
    if notifyName then return notifyName end

    local forced = Config.Compat.forceNotify or ''
    if forced ~= '' then
        notifyName = forced
        return notifyName
    end

    if Config.Notifications.preferOwnToast then
        notifyName = 'native'
        return notifyName
    end

    if started('ox_lib') then
        notifyName = 'ox_lib'
    elseif started('okokNotify') then
        notifyName = 'okokNotify'
    elseif started('qb-core') or started('qbx_core') then
        notifyName = 'qb-core'
    elseif started('es_extended') then
        notifyName = 'esx'
    else
        notifyName = 'native'
    end

    Sport.debug('notifications:', notifyName)
    return notifyName
end

--- Show a message. `kind` is 'primary' | 'success' | 'error'.
--- Falls through to the native toast whenever the chosen provider refuses or throws, so a
--- message is never silently lost.
function Compat.notify(message, kind, durationMs)
    if type(message) ~= 'string' or message == '' then return end

    kind = kind or 'primary'
    local duration = tonumber(durationMs) or Config.UI.toast.durationMs or 3500
    local provider = Compat.notifyProvider()
    local delivered = false

    if provider == 'ox_lib' then
        delivered = try(function()
            exports.ox_lib:notify({
                description = message,
                type = kind == 'primary' and 'inform' or kind,
                duration = duration,
            })
            return true
        end) == true

    elseif provider == 'okokNotify' then
        --[[
            okokNotify's fourth argument is its OWN type vocabulary - 'info', 'success', 'error' -
            and this resource's is 'primary', 'success', 'error'. Passing 'primary' straight through
            gave it a type it does not know, so every informational notification fell back to
            whatever its default styling is instead of reading as information.
        ]]
        local titles = { primary = 'Info', success = 'Success', error = 'Error' }
        local types = { primary = 'info', success = 'success', error = 'error' }

        delivered = try(function()
            exports['okokNotify']:Alert(titles[kind] or 'Info', message, duration,
                types[kind] or 'info')
            return true
        end) == true

    elseif provider == 'qb-core' then
        local _, object = Compat.framework()
        delivered = try(function()
            object.Functions.Notify(message, kind, duration)
            return true
        end) == true

    elseif provider == 'esx' then
        delivered = try(function()
            local _, object = Compat.framework()
            object.ShowNotification(message)
            return true
        end) == true
    end

    if not delivered then
        UI.toast(message, kind, duration)
    end
end

-- ---------------------------------------------------------------------------------------
-- Sound
-- ---------------------------------------------------------------------------------------

--[[
    Play one of the game's own frontend sounds.

    These come from audio banks the game already has loaded, so there is nothing to stream and
    nothing to ship. `PlaySoundFrontend(-1, name, set, true)` is the whole thing.

    interact-sound is used instead when the operator configured it AND the resource is
    running, for servers that route every cue through one place.
]]
--[[
    THE FRONTEND NATIVE, ALWAYS. The interact-sound route is gone, and it was silencing the resource.

    Every cue in Config.Minigame.sounds is a GTA FRONTEND sound with a soundset -
    `CHECKPOINT_PERFECT` in `HUD_MINI_GAME_SOUNDSET`. interact-sound plays FILES shipped inside its
    own resource, and its event does not even take a soundset. So passing a frontend name to it
    played nothing at all - and because the routing returned as soon as the event fired without
    error, PlaySoundFrontend was never reached.

    The result was total silence for the whole minigame on any server with interact-sound installed,
    which is most of them, presented as a feature: "for servers that route every cue through one
    place". Routing is a reasonable idea and these are not the sounds to route.
]]
function Compat.playSound(name, set)
    if not Config.Minigame.sounds.enabled then return end
    if type(name) ~= 'string' or name == '' then return end

    PlaySoundFrontend(-1, name, set or '', true)
end

-- ---------------------------------------------------------------------------------------
-- Progress
-- ---------------------------------------------------------------------------------------

--- Whether ox_lib's progress bar should be used for the rest between reps. The resource
--- draws its own otherwise, which matches the workout HUD and is one fewer dependency in the
--- hot path.
function Compat.useOxProgress()
    return Config.Compat.useOxProgress == true and started('ox_lib')
end

-- ---------------------------------------------------------------------------------------
-- Report
-- ---------------------------------------------------------------------------------------

--- What /sportinfo prints. A flat table so the command can render it without knowing what is
--- in it.
function Compat.report()
    return {
        { 'Framework', Compat.framework() },
        { 'Target', Compat.target() },
        { 'Notifications', Compat.notifyProvider() },
        { 'Progress bar', Compat.useOxProgress() and 'ox_lib' or 'native' },
        { 'Locale', Locale.current() },
        { 'Equipment', tostring(#Equipment.keys) .. ' types, ' ..
            tostring(Sport.count(Equipment.byModel)) .. ' models' },
        { 'Static spots', tostring(#(Config.Spots or {})) },
    }
end
