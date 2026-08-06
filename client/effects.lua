--[[
    client/effects.lua

    Where a number becomes something the player can feel.

    ---------------------------------------------------------------------------------------
    THE RULES THIS FILE FOLLOWS
    ---------------------------------------------------------------------------------------

    1. NOTHING IS WRITTEN THAT HAS NOT CHANGED. Every native below is guarded by a cache of
       what was last written. A player standing still with static stats costs zero native
       calls per refresh, not eleven.

    2. THE GAME RESETS SOME OF THESE. A respawn, a model change and a few cutscenes clear the
       player modifiers. So there is a slow re-assert loop, and a forced re-assert on
       spawn - not because they need writing often, but because they need writing again.

    3. VANILLA IS THE FLOOR. Every bonus interpolates from the game's own default at 0, so an
       untrained character plays exactly like base GTA. `Config.Effects.globalScale` pulls
       everything back towards that floor, and 0.0 means "the numbers are roleplay".

    4. ONE PLACE DECIDES. `Stats.bonus` computes every multiplier, including the global
       scale. This file only writes what it is handed.
]]

Effects = {}

-- What was last written, so nothing is written twice. Reset to empty forces a full re-assert
-- on the next apply, which is what the spawn handler does.
local applied = {}

-- Direct overrides from another resource, by effect name.
-- { value = n, expires = unix, previous = n }
local overrides = {}

-- Exhaustion, for a drug or an injury script that wants the player winded.
local exhaustedUntil = 0
local exhaustionFactor = 1.0

-- The last effective stats handed to apply(), so the refresh loop and the override system
-- can re-derive without asking State again.
local lastValues = {}

-- ---------------------------------------------------------------------------------------
-- Writing
-- ---------------------------------------------------------------------------------------

--- Write `value` for `name` only if it differs from what was written last. Floats are
--- compared with a tolerance: recomputing the same multiplier can land a millionth away and
--- that is not a change worth a native call.
local function write(name, value, apply)
    if value == nil then return end

    local previous = applied[name]
    if previous ~= nil and type(value) == 'number' and type(previous) == 'number' then
        if math.abs(previous - value) < 0.0005 then return end
    elseif previous == value then
        return
    end

    applied[name] = value
    apply(value)
end

--- The value for `name` after any override from another resource. An override that has
--- expired is dropped here rather than swept on a timer, so the effect returns to normal on
--- the exact second even if nothing else is running.
local function overridden(name, value)
    local entry = overrides[name]
    if not entry then return value end

    local expires = tonumber(entry.expires) or 0
    if expires > 0 and expires <= Sport.now() then
        overrides[name] = nil
        return value
    end

    if entry.mode == 'multiply' then
        return (tonumber(value) or 1.0) * (tonumber(entry.value) or 1.0)
    end

    return tonumber(entry.value) or value
end

-- ---------------------------------------------------------------------------------------
-- Apply
-- ---------------------------------------------------------------------------------------

--[[
    Push `values` - the EFFECTIVE stats, trained plus buffs - onto the ped and the player.

    Called from State.recompute, so it runs when something actually changed rather than on a
    tick. The refresh loop calls it again with the same values, and the `write` guard makes
    that call free.
]]
function Effects.apply(values)
    if type(values) ~= 'table' then return end
    lastValues = values

    local player = PlayerId()
    local ped = PlayerPedId()
    if not DoesEntityExist(ped) then return end

    local cfg = Config.Effects

    -- --- The real GTA character stats ------------------------------------------------
    --
    -- Strength, stamina and lung capacity already exist in the game as first-class character
    -- stats, and the engine reads them for a dozen small behaviours nobody has to write. This
    -- is the honest way to make a trained character feel trained, and it is bounded by the
    -- game rather than by this config.
    if cfg.enabled and cfg.writeGameStats then
        for key, def in pairs(Config.Stats) do
            local statValue = Stats.gameStatValue(key, values[key])
            if statValue and def.gameStat and def.gameStat ~= '' then
                write('gamestat:' .. def.gameStat, statValue, function(v)
                    -- Which slot is live depends on whether the server put the player in a
                    -- multiplayer character. Writing both costs one extra call and removes
                    -- the guesswork.
                    StatSetInt('MP0_' .. def.gameStat, v, true)
                    StatSetInt('SP0_' .. def.gameStat, v, true)
                end)
            end
        end
    end

    if not cfg.enabled then
        Effects.clear()
        return
    end

    -- --- Strength ---------------------------------------------------------------------
    local strength = cfg.strength or {}

    write('meleeDamage', overridden('meleeDamage', Stats.bonus('strength', strength.meleeDamage, values.strength)),
        function(v) SetPlayerMeleeWeaponDamageModifier(player, v, false) end)

    write('meleeDefense', overridden('meleeDefense', Stats.bonus('strength', strength.meleeDefense, values.strength)),
        function(v) SetPlayerMeleeWeaponDefenseModifier(player, v) end)

    -- Max health is off by default and should usually stay off: every ambulance job and
    -- every armour script on the market assumes 200 and will fight this.
    local maxHealth = Stats.bonus('strength', strength.maxHealth, values.strength)
    if maxHealth then
        write('maxHealth', math.floor(overridden('maxHealth', maxHealth)), function(v)
            SetEntityMaxHealth(ped, v)
            -- Raising the ceiling does not raise current health, and a player at 200/225 who
            -- never notices is worse than one who is simply healthier.
            if GetEntityHealth(ped) > v then SetEntityHealth(ped, v) end
        end)
    end

    -- --- Lung capacity ---------------------------------------------------------------
    local breath = cfg.breath or {}

    write('underwaterTime', overridden('underwaterTime', Stats.bonus('breath', breath.underwaterTime, values.breath)),
        function(v) SetPedMaxTimeUnderwater(ped, v) end)

    write('swimSpeed', overridden('swimSpeed', Stats.bonus('breath', breath.swimSpeed, values.breath)),
        function(v)
            -- The engine ignores anything above 1.49 and silently clamps, so clamping here
            -- keeps the cache honest about what actually took effect.
            SetSwimMultiplierForPlayer(player, Sport.clamp(v, 1.0, 1.49, 1.0))
        end)

    -- --- Stamina ---------------------------------------------------------------------
    local stamina = cfg.stamina or {}

    local sprint = Stats.bonus('stamina', stamina.sprintSpeed, values.stamina)
    if sprint then
        -- Exhaustion multiplies the sprint bonus down. This is the hook a drug script uses
        -- when it wants the player winded without touching their trained stamina.
        if GetGameTimer() < exhaustedUntil then
            sprint = 1.0 + (sprint - 1.0) * exhaustionFactor
        end

        write('sprintSpeed', overridden('sprintSpeed', sprint), function(v)
            SetRunSprintMultiplierForPlayer(player, Sport.clamp(v, 1.0, 1.49, 1.0))
        end)
    end

    write('healthRecharge', overridden('healthRecharge', Stats.bonus('stamina', stamina.healthRecharge, values.stamina)),
        function(v) SetPlayerHealthRechargeMultiplier(player, v) end)
end

--- Put every modifier back to vanilla. Called when effects are switched off, and on resource
--- stop so a restart does not leave a player permanently buffed.
function Effects.clear()
    local player = PlayerId()
    local ped = PlayerPedId()

    SetPlayerMeleeWeaponDamageModifier(player, 1.0, false)
    SetPlayerMeleeWeaponDefenseModifier(player, 1.0)
    SetSwimMultiplierForPlayer(player, 1.0)
    SetRunSprintMultiplierForPlayer(player, 1.0)
    SetPlayerHealthRechargeMultiplier(player, 1.0)

    if DoesEntityExist(ped) then
        SetPedMaxTimeUnderwater(ped, 45.0)
    end

    applied = {}
end

-- ---------------------------------------------------------------------------------------
-- Overrides, for other resources
-- ---------------------------------------------------------------------------------------

--[[
    Force an effect to a value, or scale it, for a while.

    This is the blunt instrument a drug script reaches for when it wants something the buff
    system cannot express - "sprint speed is 0.7 for the next minute" rather than "stamina is
    twenty points lower". It bypasses the stat entirely.

    `mode` is 'set' or 'multiply'. `seconds` of 0 means until it is cleared.
]]
function Effects.setOverride(name, value, seconds, mode)
    if type(name) ~= 'string' or name == '' then return false end

    overrides[name] = {
        value = tonumber(value) or 1.0,
        mode = mode == 'multiply' and 'multiply' or 'set',
        expires = (tonumber(seconds) or 0) > 0 and (Sport.now() + seconds) or 0,
    }

    -- Force the next apply to write, since the cached value is still the old one.
    applied[name] = nil
    Effects.apply(lastValues)
    return true
end

function Effects.clearOverride(name)
    if overrides[name] == nil then return false end
    overrides[name] = nil
    applied[name] = nil
    Effects.apply(lastValues)
    return true
end

function Effects.clearOverrides()
    overrides = {}
    applied = {}
    Effects.apply(lastValues)
end

-- ---------------------------------------------------------------------------------------
-- Stamina, directly
-- ---------------------------------------------------------------------------------------

--[[
    Wind the player: no sprint bonus, and the sprint they do have runs out fast.

    WHAT THIS CAN AND CANNOT DO, because the difference matters to whoever calls it.

    GTA exposes RestorePlayerStamina, which FILLS the sprint bar, and nothing at all that
    empties it or sets it to a value. There is no SetPlayerStamina. So "drain the player"
    cannot be implemented as "write 0 to the bar".

    What it is implemented as instead is the thing a drained player actually experiences: for
    `seconds`, their sprint speed bonus is scaled by `factor`, and the sprint control is
    disabled outright when `factor` is 0. A drug script asking for exhaustion gets a character
    who cannot run away, which is what it wanted; it does not get a specific bar value, which
    the engine will not give anybody.

    `factor` is how much of the sprint bonus survives, 0.0 to 1.0.
]]
function Effects.exhaust(factor, seconds)
    exhaustionFactor = Sport.clamp(factor, 0.0, 1.0, 0.0)
    exhaustedUntil = GetGameTimer() + math.floor((tonumber(seconds) or 30) * 1000)

    applied.sprintSpeed = nil
    Effects.apply(lastValues)

    -- Total exhaustion also takes the sprint key away, which is the only way to make a
    -- player genuinely unable to run. Anything above zero leaves them the key and just makes
    -- it worth less.
    CreateThread(function()
        while GetGameTimer() < exhaustedUntil do
            if exhaustionFactor <= 0.001 then
                DisableControlAction(0, 21, true)      -- INPUT_SPRINT
                Wait(0)
            else
                Wait(500)
            end
        end

        exhaustionFactor = 1.0
        applied.sprintSpeed = nil
        Effects.apply(lastValues)
    end)
end

--- Refill the sprint bar. `fraction` is 0..1; 1.0 is a full restore.
function Effects.restoreStamina(fraction)
    RestorePlayerStamina(PlayerId(), Sport.clamp(fraction, 0.0, 1.0, 1.0))
end

--- Whether the player is currently winded, and for how much longer in seconds.
function Effects.exhaustion()
    local left = exhaustedUntil - GetGameTimer()
    if left <= 0 then return false, 0 end
    return true, math.ceil(left / 1000)
end

-- ---------------------------------------------------------------------------------------
-- The loops
-- ---------------------------------------------------------------------------------------

--[[
    Re-assert, slowly.

    This exists because the game clears player modifiers on respawn and on a model change,
    not because they drift. Every call is guarded by the `write` cache, so a refresh where
    nothing changed is a handful of table lookups.
]]
CreateThread(function()
    local interval = math.max(1000, tonumber(Config.Effects.refreshInterval) or 5000)

    while true do
        Wait(interval)

        if State.ready and Config.Effects.enabled then
            if Config.Performance.pauseWhenDead and IsEntityDead(PlayerPedId()) then
                -- Nothing to assert on a corpse, and the spawn handler below forces a full
                -- rewrite the moment one gets up.
            else
                Effects.apply(lastValues)
            end
        end
    end
end)

--[[
    Stamina recovery.

    The one effect that has to run on its own clock rather than being a multiplier: it tops
    the sprint bar up a little at a time while the player is on foot and not sprinting.

    Cheap on purpose. The loop sleeps for `tickInterval` and does nothing at all unless the
    bonus is configured, non-zero and the player is actually in a state to recover.
]]
CreateThread(function()
    local cfg = Config.Effects.stamina or {}
    local recovery = cfg.recovery

    if not recovery or recovery.enabled == false then return end
    local interval = math.max(250, tonumber(cfg.tickInterval) or 1000)

    while true do
        Wait(interval)

        if State.ready and Config.Effects.enabled then
            local amount = Stats.bonus('stamina', recovery, State.get('stamina'))

            if amount and amount > 0.001 then
                local ped = PlayerPedId()
                if not IsEntityDead(ped) and not IsPedInAnyVehicle(ped, false)
                    and not IsPedSprinting(ped) and GetGameTimer() >= exhaustedUntil then
                    RestorePlayerStamina(PlayerId(), amount)
                end
            end
        end
    end
end)

--- A respawn clears the modifiers, so the cache has to be dropped or nothing is rewritten.
AddEventHandler('playerSpawned', function()
    applied = {}
    exhaustedUntil = 0
    exhaustionFactor = 1.0

    -- The ped is not always fully there on the same frame the event fires.
    CreateThread(function()
        Wait(1500)
        Effects.apply(lastValues)
    end)
end)

AddEventHandler('onResourceStop', function(resource)
    if resource ~= Sport.resource then return end
    Effects.clear()
end)

-- ---------------------------------------------------------------------------------------
-- What the server asks for
-- ---------------------------------------------------------------------------------------
--
-- The client half of the exports in server/api.lua. Everything here acts on the ped
-- directly and has nothing to do with the stats, which is what a drug or an injury script
-- usually wants: "this character cannot run for a minute" rather than "this character's
-- stamina is temporarily lower".

RegisterNetEvent('vsport:client:Exhaust', function(factor, seconds)
    Effects.exhaust(factor, seconds)
end)

RegisterNetEvent('vsport:client:RestoreStamina', function(fraction)
    Effects.restoreStamina(fraction)
end)

RegisterNetEvent('vsport:client:EffectOverride', function(name, value, seconds, mode)
    Effects.setOverride(name, value, seconds, mode)
end)

RegisterNetEvent('vsport:client:ClearEffectOverride', function(name)
    if name == nil then
        Effects.clearOverrides()
    else
        Effects.clearOverride(name)
    end
end)

RegisterNetEvent('vsport:client:ForceStop', function(reason)
    if Session and Session.active() then
        Session.stop(reason or 'server')
    end
end)
