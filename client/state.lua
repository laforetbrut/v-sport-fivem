--[[
    client/state.lua

    What the client knows about the player's own training.

    THE CLIENT IS A MIRROR, NOT A SOURCE. Every number in here arrived from the server and is
    used for two things only: drawing the panel, and deciding what to grey out before asking.
    Nothing the player can reach changes a stat; the server re-derives every payout from the
    session it authorised, and a client that lies about its stats gains exactly nothing by it.
]]

State = {}

State.ready = false             -- the first payload has arrived
State.trained = {}              -- the stored values
State.effective = {}            -- trained + active buffs, the numbers the natives use
State.buffs = {}                -- { { id, stat, amount, expires }, ... }
State.multipliers = {}          -- { { id, stat, value, expires }, ... }
State.decayPaused = false
State.blocked = false           -- another resource asked us not to let this player train
State.blockReason = nil
State.totalSessions = 0
State.lastSession = 0
State.decayAnchor = {}          -- stat -> the boundary decay was last charged to
State.recentSessions = 0
State.peak = {}                 -- highest value ever reached, for peak protection
State.cooldowns = {}            -- equipment key -> game timer at which it is usable again

-- The training allowance, as the server last reported it. Display only: the server refuses
-- an over-budget session itself and never trusts these numbers coming back.
State.allowanceSpent = { total = 0.0, stats = {} }
State.allowanceResetsIn = nil
State.allowanceWindow = nil

--[[
    ---------------------------------------------------------------------------------------
    THE DEVELOPER TOOLS GATE
    ---------------------------------------------------------------------------------------

    Whether this player may run the developer commands. FALSE until the server says otherwise,
    which is the important half: a player who joins and immediately types /vsportgoto is refused
    because the answer has not arrived, rather than allowed because it has not arrived.

    THE SERVER IS THE ONLY AUTHORITY. The client never decides this for itself - it asks, and the
    answer comes from Bridge.isAdmin, which checks the configured ace first and the framework's
    own idea of staff second. Config.Commands.restrictDevCommands = false opens them to everyone,
    for a development server.

    An honest limit: this is a gate on the COMMANDS, not a security boundary. Everything the dev
    tools do - teleport yourself, spawn a local prop, print to your own console - a modified
    client could do without them. What this stops is an ordinary player on an ordinary client
    finding a free map-wide teleport in the chat suggestions, which is what shipped before.
]]
State.devAllowed = false

--- Refuse, with a reason, unless the server has said this player may use the developer tools.
--- Every dev command goes through this one function; the third occurrence of a duplicated
--- two-line guard is how the key-label bug in ERROR_LOG.md happened three times.
function State.devGate()
    if State.devAllowed then return true end

    --[[
        The on-screen refusal is for the player; the console line is for whoever is meant to be able
        to run this. Through Sport.warn rather than print, so an ordinary player who mistypes a
        command does not get a config field name and a resource internal in their F8 - they get the
        notification, which is the part that concerns them.

        An admin whose answer has not arrived yet sees neither, because the gate that silences the
        console is the same one that refused them. The notification names /vsportdev for exactly that
        case.
    ]]
    Compat.notify(L('notify.no_permission'), 'error')
    Sport.warn('the developer commands are restricted to admins '
        .. '(Config.Commands.restrictDevCommands). /'
        .. (Config.Commands.dev or 'vsportdev') .. ' re-asks the server.')
    return false
end

RegisterNetEvent('vsport:client:DevAccess', function(allowed)
    State.devAllowed = allowed == true
end)

--[[
    THE PLAYER'S F8 IS NOT A LOG FILE.

    Sport.warn printed for everybody, so an ordinary player saw diagnostics written for whoever runs
    the server: "the prop model would not load", "the scenario would not start; falling back to the
    animation", "no stats received from the server after 10 attempts". None of it is actionable by
    them, and it reads as a broken resource.

    So client console output is for admins, or for anybody when Config.Debug.enabled is on. Server
    output is untouched: that console belongs to the operator.

    Assigned here rather than checked inside sport.lua because that file is shared and loads first -
    it must not depend on State. Until the server answers, State.devAllowed is false, which means the
    first seconds of a session are quiet for everyone including admins. That is the right way round:
    a missed warning costs a re-run of /vsportdev, and the alternative leaks to every player.
]]
Sport.consoleAllowed = function()
    if Config and Config.Debug and Config.Debug.enabled then return true end
    return State.devAllowed == true
end

--- What the allowance still permits, globally and per stat. Both are `math.huge` when that
--- part of the allowance is switched off in the config.
function State.allowanceLeft()
    return Stats.allowanceLeft(State.allowanceSpent)
end

--- Whether the player has trained as much as their body will take this cycle. The panel
--- shows it, and the prompt uses it to warn before a workout rather than after.
function State.allowanceExhausted()
    return Stats.allowanceExhausted(State.allowanceSpent)
end

--- Whether a session may start right now, as far as the client knows. The server checks the
--- same things again; this exists so the prompt can say why instead of silently failing.
function State.canTrain()
    if not State.ready then return false, nil end
    if State.blocked then return false, State.blockReason or L('notify.blocked') end
    return true, nil
end

--- The effective value of one stat, or 0. Every drawing path goes through here rather than
--- indexing State.effective, so a stat that has not arrived yet reads as zero instead of nil.
function State.get(key)
    return tonumber(State.effective[key]) or 0.0
end

--- The stored value, without buffs. What the panel shows as the real number.
function State.raw(key)
    return tonumber(State.trained[key]) or 0.0
end

--- The total of every active buff on `key`, positive or negative. Drawn next to the bar so a
--- player can tell a supplement from actual training.
function State.buffTotal(key)
    if not Config.Buffs.enabled then return 0.0 end

    local now = Sport.now()
    local total = 0.0

    for _, buff in ipairs(State.buffs) do
        if buff.stat == key then
            local expires = tonumber(buff.expires) or 0
            if expires == 0 or expires > now then
                total = total + (tonumber(buff.amount) or 0)
            end
        end
    end

    return total
end

--- Seconds left on `key`'s cooldown, or 0.
function State.cooldownLeft(key)
    local until_ = State.cooldowns[key]
    if not until_ then return 0 end

    local left = until_ - GetGameTimer()
    if left <= 0 then
        State.cooldowns[key] = nil
        return 0
    end

    return math.ceil(left / 1000)
end

--- Start a local cooldown. The server holds the authoritative one and will refuse an early
--- session anyway; this is so the prompt can grey out immediately rather than after a round
--- trip that ends in a refusal.
function State.startCooldown(key, seconds)
    if type(key) ~= 'string' or (tonumber(seconds) or 0) <= 0 then return end
    State.cooldowns[key] = GetGameTimer() + seconds * 1000
end

--- Recompute the effective values from the trained ones plus whatever buffs are live, then
--- hand them to client/effects.lua. Called on every payload and whenever a buff expires.
function State.recompute()
    State.effective = Stats.effective(State.trained, State.buffs, Sport.now())
    Effects.apply(State.effective)
end

-- ---------------------------------------------------------------------------------------
-- Server payloads
-- ---------------------------------------------------------------------------------------

--[[
    The full picture. Sent once when the character loads and again after anything the client
    could not have predicted - an admin command, an export from another resource, decay.

    Partial updates use `vsport:client:StatsPatch` instead, which is the common case: a
    finished session moves two numbers and there is no reason to resend the rest.
]]
RegisterNetEvent('vsport:client:Sync', function(payload)
    if type(payload) ~= 'table' then return end

    State.trained = Stats.sanitise(payload.stats)
    State.buffs = type(payload.buffs) == 'table' and payload.buffs or {}
    State.multipliers = type(payload.multipliers) == 'table' and payload.multipliers or {}
    State.decayPaused = payload.decayPaused == true
    State.blocked = payload.blocked == true
    State.blockReason = payload.blockReason
    State.totalSessions = tonumber(payload.totalSessions) or 0
    State.lastSession = tonumber(payload.lastSession) or 0
    State.decayAnchor = type(payload.decayAnchor) == 'table' and payload.decayAnchor or {}
    State.recentSessions = tonumber(payload.recentSessions) or 0
    State.peak = type(payload.peak) == 'table' and payload.peak or {}

    State.allowanceSpent = type(payload.allowanceSpent) == 'table'
        and payload.allowanceSpent or { total = 0.0, stats = {} }
    State.allowanceResetsIn = tonumber(payload.allowanceResetsIn)
    State.allowanceWindow = tonumber(payload.allowanceWindow)

    local first = not State.ready
    State.ready = true
    State.recompute()

    if first then
        Sport.debug('stats synced:', json.encode(State.trained))
        TriggerEvent('vsport:client:Ready', Sport.copy(State.trained))
    end

    TriggerEvent('vsport:client:StatsChanged', Sport.copy(State.trained),
        Sport.copy(State.effective))
end)

--- A few keys moved. Everything not named keeps its current value.
RegisterNetEvent('vsport:client:StatsPatch', function(patch, extra)
    if type(patch) ~= 'table' then return end

    for key, value in pairs(patch) do
        if Stats.def(key) then
            State.trained[key] = tonumber(value) or State.trained[key]
        end
    end

    if type(extra) == 'table' then
        if extra.totalSessions then State.totalSessions = tonumber(extra.totalSessions) or State.totalSessions end
        if extra.lastSession then State.lastSession = tonumber(extra.lastSession) or State.lastSession end
        if extra.recentSessions then State.recentSessions = tonumber(extra.recentSessions) or 0 end
        if type(extra.allowanceSpent) == 'table' then State.allowanceSpent = extra.allowanceSpent end
        if extra.allowanceResetsIn then State.allowanceResetsIn = tonumber(extra.allowanceResetsIn) end
        if type(extra.decayAnchor) == 'table' then State.decayAnchor = extra.decayAnchor end
        if type(extra.peak) == 'table' then State.peak = extra.peak end
    end

    State.recompute()
    TriggerEvent('vsport:client:StatsChanged', Sport.copy(State.trained),
        Sport.copy(State.effective))
end)

--- The buff list changed. Sent whole rather than patched: it is short, it changes rarely,
--- and reconciling two lists client-side would be more code than resending five entries.
RegisterNetEvent('vsport:client:Buffs', function(buffs, multipliers, decayPaused)
    State.buffs = type(buffs) == 'table' and buffs or {}
    State.multipliers = type(multipliers) == 'table' and multipliers or {}
    if decayPaused ~= nil then State.decayPaused = decayPaused == true end

    State.recompute()
    TriggerEvent('vsport:client:BuffsChanged', Sport.copy(State.buffs),
        Sport.copy(State.multipliers))
end)

--- Another resource blocked or unblocked training through the server export.
RegisterNetEvent('vsport:client:Blocked', function(blocked, reason)
    State.blocked = blocked == true
    State.blockReason = reason

    if State.blocked and Session and Session.active() then
        Session.stop('blocked')
    end
end)

--- A cooldown the server is enforcing, mirrored locally so the prompt can show it.
RegisterNetEvent('vsport:client:Cooldown', function(key, seconds)
    State.startCooldown(key, seconds)
end)

-- ---------------------------------------------------------------------------------------
-- Buff expiry
-- ---------------------------------------------------------------------------------------
--
-- The server owns expiry and will resend the list. This loop exists so the EFFECTS drop at
-- the right second rather than at the next sweep - a player whose strength buff ran out
-- three seconds ago should not still be hitting harder.
--
-- It only runs while there is something to expire.

local expiryLoopRunning = false

local function runExpiryLoop()
    if expiryLoopRunning then return end
    expiryLoopRunning = true

    CreateThread(function()
        while #State.buffs > 0 or #State.multipliers > 0 do
            local now = Sport.now()
            local changed = false

            for index = #State.buffs, 1, -1 do
                local expires = tonumber(State.buffs[index].expires) or 0
                if expires > 0 and expires <= now then
                    table.remove(State.buffs, index)
                    changed = true
                end
            end

            for index = #State.multipliers, 1, -1 do
                local expires = tonumber(State.multipliers[index].expires) or 0
                if expires > 0 and expires <= now then
                    table.remove(State.multipliers, index)
                    changed = true
                end
            end

            if changed then State.recompute() end
            Wait(1000)
        end

        expiryLoopRunning = false
    end)
end

AddEventHandler('vsport:client:BuffsChanged', runExpiryLoop)

-- ---------------------------------------------------------------------------------------
-- Handshake
-- ---------------------------------------------------------------------------------------
--
-- The client says hello once it has a ped. Every framework announces a loaded character
-- differently and a standalone server announces nothing at all, so this is the one path that
-- always works. The server deduplicates.

CreateThread(function()
    while not NetworkIsSessionStarted() do Wait(250) end

    -- The ped exists before the character data does on most frameworks. Waiting for a real
    -- ped rather than for a framework event is what keeps this working on all of them.
    while not DoesEntityExist(PlayerPedId()) do Wait(250) end

    TriggerServerEvent('vsport:server:PlayerReady')

    --[[
        And ask whether this player may use the developer tools.

        A separate question from the stats, deliberately: an admin whose ace is granted by a
        permissions resource that loads after this one, or who is promoted mid-session, would
        otherwise stay locked out until they reconnected. The server also pushes the answer
        unasked when the profile loads, so this is belt and braces rather than the only path.

        The gate stays CLOSED until an answer arrives. A dropped event costs an admin one
        /vsportdev to ask again; the alternative failure - open until told otherwise - would
        cost every player a free teleport for the first few seconds of every session.
    ]]
    TriggerServerEvent('vsport:server:RequestDevAccess')

    -- Ask again if nothing came back. A framework that loads the character late, a server
    -- that was still booting, a one-off dropped event: all of them look the same from here
    -- and all of them are fixed by asking twice.
    local attempts = 0
    while not State.ready and attempts < 10 do
        Wait(3000)
        attempts = attempts + 1
        if not State.ready then
            TriggerServerEvent('vsport:server:PlayerReady')
            TriggerServerEvent('vsport:server:RequestDevAccess')
        end
    end

    if not State.ready then
        Sport.warn('no stats received from the server after 10 attempts')
    end
end)
