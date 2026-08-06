--[[
    server/commands.lua

    /sportadmin, and the boot banner.

    The command is registered through the framework's own registry when there is one, so it
    shows up in the chat suggestions, and through plain RegisterCommand when there is not.
    Either way `Bridge.isAdmin` decides who may run it: the configured ace first, the
    framework's own idea of staff as a fallback, and the console always.
]]

local function reply(src, message)
    if src == 0 then
        print('[v-sport] ' .. message)
    else
        Bridge.notify(src, message, 'primary')
    end
end

--- The stat keys, for the "no stat called x" message.
local function statList()
    return table.concat(Stats.keys(), ', ')
end

--- Resolve a target from a command argument. Returns the source, or nil after replying.
local function targetOf(src, raw)
    local target = tonumber(raw)
    if not target or not GetPlayerName(target) then
        reply(src, L('cmd.no_player'))
        return nil
    end

    if not Profiles.get(target) then
        reply(src, ('%s has not finished loading'):format(GetPlayerName(target)))
        return nil
    end

    return target
end

local HANDLERS = {}

--- /sportadmin get <id>
HANDLERS.get = function(src, args)
    local target = targetOf(src, args[2])
    if not target then return end

    local profile = exports[Sport.resource]:GetProfile(target)
    if not profile then return end

    print(('^5==== v-sport: %s (%s) ===='):format(GetPlayerName(target), profile.identifier))

    for _, key in ipairs(Stats.keys()) do
        print(('  %-14s %6.2f   (effective %6.2f, peak %6.2f)'):format(
            key, profile.stats[key] or 0, profile.effective[key] or 0, profile.peak[key] or 0))
    end

    print(('  %-14s %d'):format('sessions', profile.totalSessions))
    print(('  %-14s %s'):format('last session',
        profile.lastSession > 0 and
        (Sport.duration(Sport.now() - profile.lastSession) .. ' ago') or 'never'))

    local allowance = profile.allowance
    print(('  %-14s %.1f spent, %s left, resets in %s'):format('allowance',
        allowance.spent.total or 0,
        allowance.left and ('%.1f'):format(allowance.left) or 'unlimited',
        allowance.resetsIn and Sport.duration(allowance.resetsIn) or '-'))

    print(('  %-14s %s'):format('decay',
        profile.decayPaused and 'PAUSED' or 'running'))
    print(('  %-14s %d buffs, %d multipliers'):format('active',
        #profile.buffs, #profile.multipliers))
    print('^5=========================================^7')

    reply(src, L('cmd.done') .. ' - printed to the server console')
end

--- /sportadmin set <id> <stat> <value>
HANDLERS.set = function(src, args)
    local target = targetOf(src, args[2])
    if not target then return end

    local key = args[3]
    if not Stats.def(key) then
        reply(src, L('cmd.no_stat', tostring(key), statList()))
        return
    end

    local value = tonumber(args[4])
    if not value then
        reply(src, L('cmd.admin_usage', Config.Commands.admin))
        return
    end

    local after = exports[Sport.resource]:SetStat(target, key, value)
    reply(src, L('cmd.admin_set', GetPlayerName(target), key, after or 0))
end

--- /sportadmin add <id> <stat> <value>
HANDLERS.add = function(src, args)
    local target = targetOf(src, args[2])
    if not target then return end

    local key = args[3]
    if not Stats.def(key) then
        reply(src, L('cmd.no_stat', tostring(key), statList()))
        return
    end

    local value = tonumber(args[4])
    if not value then
        reply(src, L('cmd.admin_usage', Config.Commands.admin))
        return
    end

    local after = exports[Sport.resource]:AddStat(target, key, value)
    reply(src, L('cmd.admin_set', GetPlayerName(target), key, after or 0))
end

--- /sportadmin reset <id>
HANDLERS.reset = function(src, args)
    local target = targetOf(src, args[2])
    if not target then return end

    exports[Sport.resource]:ResetStats(target)
    reply(src, L('cmd.admin_reset', GetPlayerName(target)))
end

--- /sportadmin buff <id> <stat> <amount> [seconds]
HANDLERS.buff = function(src, args)
    local target = targetOf(src, args[2])
    if not target then return end

    local key = args[3]
    if not Stats.def(key) then
        reply(src, L('cmd.no_stat', tostring(key), statList()))
        return
    end

    local amount = tonumber(args[4])
    if not amount then
        reply(src, L('cmd.admin_usage', Config.Commands.admin))
        return
    end

    local seconds = tonumber(args[5]) or 300
    local id = exports[Sport.resource]:ApplyBuff(target, key, amount, seconds)

    reply(src, id and ('buff %s applied'):format(id) or 'nothing applied')
end

--- /sportadmin allowance <id> [amount]   - no amount clears the whole ledger
HANDLERS.allowance = function(src, args)
    local target = targetOf(src, args[2])
    if not target then return end

    local amount = tonumber(args[3])

    if amount then
        exports[Sport.resource]:AddAllowance(target, amount)
        reply(src, ('gave %s %.1f allowance back'):format(GetPlayerName(target), amount))
    else
        exports[Sport.resource]:ResetAllowance(target)
        reply(src, ('cleared %s\'s allowance ledger'):format(GetPlayerName(target)))
    end
end

--- /sportadmin whey <id> [seconds]   - the shortened recovery window, without the item
HANDLERS.whey = function(src, args)
    local target = targetOf(src, args[2])
    if not target then return end

    local seconds = tonumber(args[3]) or Config.Allowance.window
    exports[Sport.resource]:ReduceRecovery(target, seconds)

    reply(src, ('%s recovers in %s for the next %s'):format(
        GetPlayerName(target),
        Sport.duration(Stats.allowanceWindow(true)),
        Sport.duration(seconds)))
end

--- /sportadmin block <id> <0|1> [reason]
HANDLERS.block = function(src, args)
    local target = targetOf(src, args[2])
    if not target then return end

    local blocked = args[3] == '1' or args[3] == 'true'
    local reason = args[4] and table.concat(args, ' ', 4) or nil

    exports[Sport.resource]:BlockTraining(target, blocked, reason)
    reply(src, ('%s is %s'):format(GetPlayerName(target),
        blocked and 'blocked from training' or 'allowed to train'))
end

--- /sportadmin top <stat> [limit]
HANDLERS.top = function(src, args)
    local key = args[2]
    if not Stats.def(key) then
        reply(src, L('cmd.no_stat', tostring(key), statList()))
        return
    end

    local rows = exports[Sport.resource]:GetLeaderboard(key, tonumber(args[3]) or 10)

    print(('^5==== v-sport: top %s ===='):format(key))
    for index, row in ipairs(rows) do
        print(('  %2d. %-40s %6.2f'):format(index, row.identifier, row.value))
    end
    if #rows == 0 then print('  (nothing to show - no database, or nobody has trained)') end
    print('^5=================================^7')

    reply(src, L('cmd.done') .. ' - printed to the server console')
end

CreateThread(function()
    local name = Config.Commands.admin
    if type(name) ~= 'string' or name == '' then return end

    -- Wait for the framework so the command lands in its registry rather than in the plain
    -- fallback, which is what puts it in the chat suggestions.
    Wait(3000)

    Bridge.addCommand(name, L('cmd.admin'), {
        { name = 'action', help = 'get | set | add | reset | buff | allowance | whey | block | top' },
        { name = 'id', help = 'server id' },
        { name = 'stat', help = statList() },
        { name = 'value', help = 'a number' },
    }, true, function(src, rawArgs)
        -- The plain RegisterCommand fallback hands a table; the framework registries hand
        -- either a table or a string depending on which one and which version.
        local args = rawArgs
        if type(args) == 'string' then
            args = {}
            for word in rawArgs:gmatch('%S+') do args[#args + 1] = word end
        end
        args = type(args) == 'table' and args or {}

        local action = tostring(args[1] or ''):lower()
        local handler = HANDLERS[action]

        if not handler then
            reply(src, L('cmd.admin_usage', name))
            return
        end

        handler(src, args)
    end)
end)

-- ---------------------------------------------------------------------------------------
-- Who may use the developer tools
-- ---------------------------------------------------------------------------------------
--
-- /vsportprop, /vsportgoto, /vsportfind, /vsportscan, /vsportspot and /vsportoffset run entirely
-- on the client - they teleport the player, spawn a local prop and print to their own console -
-- so the client is where they have to be gated. The client never decides for itself: it asks
-- here, and until an answer arrives the gate is CLOSED.
--
-- Config.Commands.restrictDevCommands = false opens them to everyone, which is reasonable on a
-- development server and nowhere else. Before this existed the flag was declared, documented and
-- read by nothing, so every player had a map-wide teleport in their chat suggestions.

--- Tell one client whether they may use the developer commands.
local function pushDevAccess(src)
    if not src or src == 0 then return end

    local allowed = Config.Commands.restrictDevCommands == false or Bridge.isAdmin(src)
    TriggerClientEvent('vsport:client:DevAccess', src, allowed == true)
end

--[[
    The client asks on load, and may ask again.

    Asking again matters: an admin promoted mid-session, or one whose ace arrives from a
    permissions resource that loads after this one, would otherwise stay locked out until they
    reconnected. There is nothing to abuse in re-asking - the answer is computed here every time
    and a non-admin gets `false` however often they ask.
]]
RegisterNetEvent('vsport:server:RequestDevAccess', function()
    pushDevAccess(source)
end)

-- And pushed unasked when a profile loads, so the usual case needs no round trip from the client.
AddEventHandler('vsport:server:PlayerLoaded', function(src)
    pushDevAccess(src)
end)

-- ---------------------------------------------------------------------------------------
-- Boot banner
-- ---------------------------------------------------------------------------------------

CreateThread(function()
    Wait(5000)

    local models = Sport.count(Equipment.byModel)

    Sport.print(('ready - %s, %d exercises across %d models, %d static spots')
        :format(Bridge.framework(), #Equipment.keys, models, #(Config.Spots or {})))

    if Config.Allowance.enabled then
        Sport.print(('allowance: %.0f points per %s, %.0f max per stat')
            :format(Config.Allowance.total, Sport.duration(Config.Allowance.window),
                Config.Allowance.perStat))
    end

    if not Config.Effects.enabled then
        Sport.print('effects are OFF - stats are a roleplay number on this server')
    end

    --[[
        POINT THE OPERATOR AT THE NEXT STEP.

        Eight of the shipped exercises have no base-game model at all - kettlebells, treadmills,
        rowing machines and the rest - because every name they used to list was rejected by
        IsModelValid. They are waiting for a gym MLO's model names, and on a fresh install nobody
        knows that: the resource simply appears to be missing half its equipment.

        So it says so, once, with the command that fixes it. Two lines at boot against an evening
        of wondering why the treadmill does nothing.
    ]]
    local waiting = {}
    for _, key in ipairs(Equipment.keys) do
        local entry = Equipment.get(key)
        if entry and #(entry.models or {}) == 0 then
            waiting[#waiting + 1] = key
        end
    end

    if #waiting > 0 then
        Sport.print(('%d exercise%s waiting for a model from your map: %s')
            :format(#waiting, #waiting == 1 and ' is' or 's are', table.concat(waiting, ', ')))
        Sport.print(('stand in front of one and run /%s <exercise> - no restart needed. '
            .. 'See PROPS.md'):format(Config.Commands.add or 'vsportadd'))
    end

    local added = 0
    for _ in pairs(Equipment.overlay or {}) do added = added + 1 end
    if added > 0 then
        Sport.print(('%d exercise%s extended in game (data/custom.json). /%s prints them as config')
            :format(added, added == 1 and '' or 's', Config.Commands.export or 'vsportexport'))
    end
end)
