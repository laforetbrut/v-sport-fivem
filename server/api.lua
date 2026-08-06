--[[
    ===========================================================================================
    server/api.lua
    ===========================================================================================

    Everything another resource may call. This is the file a drug script, a supplement item, a
    gym membership, a coach NPC or an admin menu talks to.

    Full documentation with worked examples is in API.md. This file is the contract.

    -------------------------------------------------------------------------------------------
    THE RULES EVERY EXPORT HERE FOLLOWS
    -------------------------------------------------------------------------------------------

    1. A BAD ARGUMENT RETURNS nil OR false. It never raises. Somebody else's resource passing
       a string where a number belongs must not take a player's training down with it, and a
       nil return is something a caller can branch on.

    2. TABLES ARE COPIES. Mutating a returned stats table changes nothing here.

    3. AN UNKNOWN PLAYER IS NOT AN ERROR. A player can disconnect between another resource
       deciding to buff them and this call arriving. Every export answers nil or false for a
       source that is not loaded.

    4. CHANGES ARE CLAMPED AND LOGGED. Config.Buffs.maxSingleChange bounds how far one call
       can move a number, so a loop with a sign error costs a warning rather than a wipe.

    5. EVERY EXPORT HAS AN EVENT TWIN. Some resources prefer TriggerEvent; the event names
       are at the bottom of this file and route to the same functions.
]]

local function profileOf(src)
    return Profiles.get(tonumber(src))
end

-- ===========================================================================================
-- READING
-- ===========================================================================================

--- The trained values. { strength = 42.5, breath = 10.0, stamina = 31.25 }, or nil.
local function GetStats(src)
    local profile = profileOf(src)
    return profile and Sport.copy(profile.stats) or nil
end

--- One trained value, or nil.
local function GetStat(src, key)
    local profile = profileOf(src)
    if not profile or not Stats.def(key) then return nil end
    return profile.stats[key]
end

--- The values with active buffs folded in - what the player's body is actually doing.
local function GetEffectiveStats(src)
    local profile = profileOf(src)
    if not profile then return nil end
    return Stats.effective(profile.stats, profile.buffs, Sport.now())
end

local function GetEffectiveStat(src, key)
    local effective = GetEffectiveStats(src)
    if not effective or not Stats.def(key) then return nil end
    return effective[key]
end

--- Everything about a player in one call, for a menu or a status panel.
local function GetProfile(src)
    local profile = profileOf(src)
    if not profile then return nil end

    local spent = Profiles.allowanceSpent(profile)
    local globalLeft, perStatLeft = Stats.allowanceLeft(spent)

    return {
        identifier = profile.identifier,
        stats = Sport.copy(profile.stats),
        effective = Stats.effective(profile.stats, profile.buffs, Sport.now()),
        peak = Sport.copy(profile.peak),
        buffs = Sport.copy(profile.buffs),
        multipliers = Sport.copy(profile.multipliers),
        totalSessions = profile.totalSessions,
        lastSession = profile.lastSession,
        decayPaused = profile.decayPaused,
        decayImmuneUntil = profile.decayImmuneUntil,
        blocked = profile.blocked,
        blockReason = profile.blockReason,
        allowance = {
            spent = spent,
            left = globalLeft ~= math.huge and globalLeft or nil,
            perStatLeft = perStatLeft,
            resetsIn = Profiles.allowanceResetsIn(profile),
            exhausted = Stats.allowanceExhausted(spent),
        },
        training = Sessions.current(tonumber(src)),
    }
end

--- Whether the player's stats have finished loading. Anything that runs at spawn should
--- check this rather than assuming.
local function IsReady(src)
    return profileOf(src) ~= nil
end

local function GetBuffs(src)
    local profile = profileOf(src)
    return profile and Sport.copy(profile.buffs) or nil
end

local function GetMultipliers(src)
    local profile = profileOf(src)
    return profile and Sport.copy(profile.multipliers) or nil
end

--- The highest value this character has ever reached, for peak protection or for a title.
local function GetPeak(src, key)
    local profile = profileOf(src)
    if not profile then return nil end
    if key then return tonumber(profile.peak[key]) or 0 end
    return Sport.copy(profile.peak)
end

local function GetTotalSessions(src)
    local profile = profileOf(src)
    return profile and profile.totalSessions or nil
end

--- The top characters by one stat, read from the database. Not cheap: it reads up to two
--- thousand rows and sorts them. Call it for a leaderboard command, not on a timer.
local function GetLeaderboard(statKey, limit)
    return Database.leaderboard(statKey, limit)
end

-- ===========================================================================================
-- THE TRAINING ALLOWANCE
-- ===========================================================================================
--
-- The recovery mechanic from section 5b of the config, and the exports a drug script uses to
-- get around it. This is the group most likely to be what somebody came to this file for.

--- Everything about a player's current allowance.
local function GetAllowance(src)
    local profile = profileOf(src)
    if not profile then return nil end

    local spent = Profiles.allowanceSpent(profile)
    local globalLeft, perStatLeft = Stats.allowanceLeft(spent)
    local reduced = (tonumber(profile.recoveryUntil) or 0) > Sport.now()

    return {
        total = tonumber(Config.Allowance.total) or 0,
        perStat = tonumber(Config.Allowance.perStat) or 0,
        spent = spent,
        left = globalLeft ~= math.huge and globalLeft or nil,
        perStatLeft = perStatLeft,
        resetsIn = Profiles.allowanceResetsIn(profile),
        window = Stats.allowanceWindow(reduced),
        reduced = reduced,
        reducedUntil = profile.recoveryUntil,
        exhausted = Stats.allowanceExhausted(spent),
    }
end

--- Whether the player has trained as much as their body will take this cycle.
local function IsAllowanceExhausted(src)
    local profile = profileOf(src)
    if not profile then return false end
    return Stats.allowanceExhausted(Profiles.allowanceSpent(profile))
end

--- Give back `amount` points of spent allowance. A protein bar, a massage, a good night's
--- sleep - whatever the server calls it.
local function AddAllowance(src, amount)
    return Profiles.refundAllowance(tonumber(src), math.max(0, tonumber(amount) or 0))
end

--- Wipe the ledger. The full "ignore the recovery timer" bypass, for an admin command or a
--- drug that is meant to be genuinely powerful.
local function ResetAllowance(src)
    return Profiles.refundAllowance(tonumber(src), nil)
end

--[[
    Put the player on the shortened recovery window.

    This is what whey does, and what any other consumable that "speeds up recovery" should
    call. `seconds` is how long the shortened window applies for, NOT the window itself -
    the window comes from Config.Allowance.reducedWindow.

        exports['v-sport']:ReduceRecovery(source, 25 * 3600)
        -- for the next 25 hours, this character's allowance recovers in 8h instead of 25h
]]
local function ReduceRecovery(src, seconds)
    return Profiles.reduceRecovery(tonumber(src),
        tonumber(seconds) or Config.Allowance.window)
end

--- Take the shortened window away again.
local function ClearRecoveryBoost(src)
    local profile = profileOf(src)
    if not profile then return false end

    profile.recoveryUntil = 0
    Profiles.touch(tonumber(src))
    Profiles.sync(tonumber(src))
    return true
end

-- ===========================================================================================
-- CHANGING STATS
-- ===========================================================================================
--
-- These BYPASS the training allowance by default, because an admin fixing a number and a drug
-- granting a bonus are not workouts. Pass `respectAllowance = true` on the ones that take it
-- to make the change count against the player's cycle like real training would.

local function AddStat(src, key, amount, respectAllowance)
    return Profiles.changeStat(tonumber(src), key, amount, 'add', respectAllowance == true)
end

local function RemoveStat(src, key, amount)
    return Profiles.changeStat(tonumber(src), key, amount, 'remove', false)
end

local function SetStat(src, key, value)
    return Profiles.changeStat(tonumber(src), key, value, 'set', false)
end

--- Several at once. { strength = 50, stamina = 20 }. Returns how many actually moved.
local function SetStats(src, values)
    if type(values) ~= 'table' then return 0 end

    local changed = 0
    for key, value in pairs(values) do
        if Profiles.changeStat(tonumber(src), key, value, 'set', false) then
            changed = changed + 1
        end
    end
    return changed
end

--- Back to a brand new character. Clears the stats, the peak, the allowance and the history.
local function ResetStats(src)
    local source_ = tonumber(src)
    local profile = profileOf(source_)
    if not profile then return false end

    profile.stats = Stats.blank()
    profile.peak = {}
    profile.decayAnchor = {}
    profile.allowance = { entries = {}, cycleStart = 0 }
    profile.totalSessions = 0
    profile.lastSession = 0
    profile.recentSessions = {}
    profile.recoveryUntil = 0

    Profiles.touch(source_)
    Profiles.sync(source_)

    TriggerEvent('vsport:server:StatsReset', source_)
    return true
end

--[[
    Award a session as though the player had done one.

    Goes through the FULL pipeline - fatigue, multipliers, the allowance, milestones - which
    is what makes it different from AddStat. Use it for a coach NPC, a scripted training
    montage, or a piece of equipment another resource owns.

        exports['v-sport']:AddSession(source, 'bench_press', 1.0)
]]
local function AddSession(src, equipmentKey, quality)
    local source_ = tonumber(src)
    local entry = Equipment.get(equipmentKey)
    if not entry or not profileOf(source_) then return nil end

    local gains = Profiles.awardSession(source_, entry,
        Sport.clamp(quality, 0.0, 1.0, 1.0))

    TriggerClientEvent('vsport:client:SessionResult', source_, gains, nil)
    return gains
end

-- ===========================================================================================
-- BUFFS AND DEBUFFS
-- ===========================================================================================

--[[
    Add points to a stat's EFFECTIVE value for a while.

    The trained value is untouched, so this is genuinely temporary: the moment it expires the
    player is exactly where they were. A negative amount is a debuff.

        exports['v-sport']:ApplyBuff(source, 'strength', 15, 300)     -- +15 for 5 minutes
        exports['v-sport']:ApplyBuff(source, 'stamina', -20, 600)     -- -20 for 10 minutes

    `id` is optional and lets you remove this exact buff later. Returns the id.
]]
local function ApplyBuff(src, key, amount, seconds, id)
    return Profiles.addBuff(tonumber(src), key, amount, seconds, id)
end

--- The same thing, with the sign flipped for readability at the call site.
local function ApplyDebuff(src, key, amount, seconds, id)
    return Profiles.addBuff(tonumber(src), key, -math.abs(tonumber(amount) or 0), seconds, id)
end

--[[
    Multiply what TRAINING gains for a while. Does not change any stat by itself.

    `key` of nil applies to every stat, which is what a pre-workout wants.

        exports['v-sport']:ApplyMultiplier(source, nil, 2.0, 1800)      -- double gains, 30min
        exports['v-sport']:ApplyMultiplier(source, 'strength', 0.5, 600) -- steroid crash
]]
local function ApplyMultiplier(src, key, value, seconds, id)
    return Profiles.addMultiplier(tonumber(src), key, value, seconds, id)
end

local function RemoveBuff(src, id)
    return Profiles.removeBuff(tonumber(src), id)
end

--- Remove every buff, or every buff on one stat.
local function ClearBuffs(src, key)
    return Profiles.clearBuffs(tonumber(src), key)
end

-- ===========================================================================================
-- DECAY
-- ===========================================================================================

--[[
    Stop the clock indefinitely.

    The "a drug that stops you losing your 10% a day" hook. While paused, no decay is charged
    and the anchors do not move - so unpausing does NOT then charge for the paused period.
    That is deliberate: a pause that saves the bill up is not a pause.
]]
local function SetDecayPaused(src, paused)
    local source_ = tonumber(src)
    local profile = profileOf(source_)
    if not profile then return false end

    profile.decayPaused = paused == true

    -- Moving the anchors forward is what stops the paused time being charged later.
    if profile.decayPaused then
        local now = Sport.now()
        for _, key in ipairs(Stats.keys()) do
            profile.decayAnchor[key] = math.max(tonumber(profile.decayAnchor[key]) or 0, now)
        end
    else
        -- On resume, restart the clock from now rather than from whenever they last trained.
        local now = Sport.now()
        for _, key in ipairs(Stats.keys()) do
            profile.decayAnchor[key] = now + Stats.decayConfig(key).grace
        end
    end

    Profiles.touch(source_)
    Profiles.sync(source_)
    return true
end

local function IsDecayPaused(src)
    local profile = profileOf(src)
    if not profile then return false end
    return profile.decayPaused or (tonumber(profile.decayImmuneUntil) or 0) > Sport.now()
end

--[[
    The timed version. Immunity for `seconds`, then decay resumes on its own.

    This is the one a consumable should use - a pause with no expiry that somebody forgets to
    clear is a character who never decays again.

        exports['v-sport']:SetDecayImmunity(source, 48 * 3600)   -- two days protected
]]
local function SetDecayImmunity(src, seconds)
    local source_ = tonumber(src)
    local profile = profileOf(source_)
    if not profile then return false end

    local duration = math.max(0, tonumber(seconds) or 0)
    profile.decayImmuneUntil = duration > 0 and (Sport.now() + duration) or 0

    -- Same reasoning as the pause: the protected window must not be charged retroactively.
    local anchor = profile.decayImmuneUntil
    if anchor > 0 then
        for _, key in ipairs(Stats.keys()) do
            profile.decayAnchor[key] = math.max(tonumber(profile.decayAnchor[key]) or 0, anchor)
        end
    end

    Profiles.touch(source_)
    Profiles.sync(source_)
    return true
end

--- Charge whatever decay is owed right now, rather than waiting for the timer. Returns what
--- was lost.
local function ApplyDecayNow(src)
    return Profiles.applyDecay(tonumber(src), false)
end

-- ===========================================================================================
-- TRAINING CONTROL
-- ===========================================================================================

--[[
    Stop the player training at all, with a reason they will be shown.

    For a script that has taken the character somewhere they should not be doing push-ups:
    in custody, in hospital, badly injured, on a comedown.
]]
local function BlockTraining(src, blocked, reason)
    local source_ = tonumber(src)
    local profile = profileOf(source_)
    if not profile then return false end

    profile.blocked = blocked == true
    profile.blockReason = type(reason) == 'string' and reason or nil

    if profile.blocked then
        Sessions.forceStop(source_, 'blocked')
    end

    TriggerClientEvent('vsport:client:Blocked', source_, profile.blocked, profile.blockReason)
    Profiles.sync(source_)
    return true
end

local function IsTrainingBlocked(src)
    local profile = profileOf(src)
    if not profile then return false end
    return profile.blocked == true
end

local function IsTraining(src)
    return Sessions.current(tonumber(src)) ~= nil
end

local function GetSession(src)
    return Sessions.current(tonumber(src))
end

local function StopSession(src, reason)
    return Sessions.forceStop(tonumber(src), reason or 'export')
end

--- Seconds left before this player may use this equipment again.
local function GetCooldown(src, equipmentKey)
    return Sessions.cooldownLeft(tonumber(src), equipmentKey)
end

--- Clear one equipment cooldown, or all of them. The small bypass, next to ResetAllowance's
--- big one.
local function ClearCooldown(src, equipmentKey)
    return Sessions.clearCooldowns(tonumber(src), equipmentKey)
end

-- ===========================================================================================
-- EFFECTS ON THE BODY
-- ===========================================================================================
--
-- These reach through to client/effects.lua. They act on the ped directly and have nothing to
-- do with the stats, which is exactly what a drug script usually wants: "this character
-- cannot run for a minute" rather than "this character's stamina is temporarily 20 lower".

--[[
    Wind the player.

    `factor` is how much of their sprint bonus survives; 0 takes the sprint key away entirely.
    `seconds` is how long.

        exports['v-sport']:Exhaust(source, 0.0, 45)    -- cannot sprint for 45 seconds
        exports['v-sport']:Exhaust(source, 0.4, 120)   -- winded for two minutes
]]
local function Exhaust(src, factor, seconds)
    local source_ = tonumber(src)
    if not GetPlayerName(source_) then return false end

    TriggerClientEvent('vsport:client:Exhaust', source_,
        Sport.clamp(factor, 0.0, 1.0, 0.0), math.max(0, tonumber(seconds) or 30))
    return true
end

--- Refill the sprint bar. `fraction` is 0..1.
local function RestoreStamina(src, fraction)
    local source_ = tonumber(src)
    if not GetPlayerName(source_) then return false end

    TriggerClientEvent('vsport:client:RestoreStamina', source_,
        Sport.clamp(fraction, 0.0, 1.0, 1.0))
    return true
end

--[[
    Force one effect to a value, bypassing the stat that normally drives it.

    `name` is a key from Config.Effects: 'meleeDamage', 'meleeDefense', 'underwaterTime',
    'swimSpeed', 'sprintSpeed', 'healthRecharge', 'maxHealth'.
    `mode` is 'set' or 'multiply'. `seconds` of 0 means until it is cleared.

        exports['v-sport']:SetEffectOverride(source, 'sprintSpeed', 0.8, 60, 'multiply')
]]
local function SetEffectOverride(src, name, value, seconds, mode)
    local source_ = tonumber(src)
    if not GetPlayerName(source_) or type(name) ~= 'string' then return false end

    TriggerClientEvent('vsport:client:EffectOverride', source_, name, value, seconds, mode)
    return true
end

local function ClearEffectOverride(src, name)
    local source_ = tonumber(src)
    if not GetPlayerName(source_) then return false end

    TriggerClientEvent('vsport:client:ClearEffectOverride', source_, name)
    return true
end

--[[
    The carry weight this character's strength has earned, or nil when the bonus is disabled.

    Nothing applies this - inventories all handle weight differently and this resource does
    not reach into somebody else's. Read it from your inventory's own weight calculation.
]]
local function GetCarryWeight(src)
    local profile = profileOf(src)
    if not profile then return nil end

    local bonus = (Config.Effects.strength or {}).carryWeight
    return Stats.bonus('strength', bonus, profile.stats.strength or 0)
end

-- ===========================================================================================
-- REGISTRATION
-- ===========================================================================================

local API = {
    -- Reading
    GetStats = GetStats,
    GetStat = GetStat,
    GetEffectiveStats = GetEffectiveStats,
    GetEffectiveStat = GetEffectiveStat,
    GetProfile = GetProfile,
    IsReady = IsReady,
    GetBuffs = GetBuffs,
    GetMultipliers = GetMultipliers,
    GetPeak = GetPeak,
    GetTotalSessions = GetTotalSessions,
    GetLeaderboard = GetLeaderboard,

    -- Allowance and recovery
    GetAllowance = GetAllowance,
    IsAllowanceExhausted = IsAllowanceExhausted,
    AddAllowance = AddAllowance,
    ResetAllowance = ResetAllowance,
    ReduceRecovery = ReduceRecovery,
    ClearRecoveryBoost = ClearRecoveryBoost,

    -- Stats
    AddStat = AddStat,
    RemoveStat = RemoveStat,
    SetStat = SetStat,
    SetStats = SetStats,
    ResetStats = ResetStats,
    AddSession = AddSession,

    -- Buffs
    ApplyBuff = ApplyBuff,
    ApplyDebuff = ApplyDebuff,
    ApplyMultiplier = ApplyMultiplier,
    RemoveBuff = RemoveBuff,
    ClearBuffs = ClearBuffs,

    -- Decay
    SetDecayPaused = SetDecayPaused,
    IsDecayPaused = IsDecayPaused,
    SetDecayImmunity = SetDecayImmunity,
    ApplyDecayNow = ApplyDecayNow,

    -- Training control
    BlockTraining = BlockTraining,
    IsTrainingBlocked = IsTrainingBlocked,
    IsTraining = IsTraining,
    GetSession = GetSession,
    StopSession = StopSession,
    GetCooldown = GetCooldown,
    ClearCooldown = ClearCooldown,

    -- The body
    Exhaust = Exhaust,
    RestoreStamina = RestoreStamina,
    SetEffectOverride = SetEffectOverride,
    ClearEffectOverride = ClearEffectOverride,
    GetCarryWeight = GetCarryWeight,
}

for name, fn in pairs(API) do
    exports(name, fn)
end

--[[
    Event twins.

    Some resources would rather fire an event than call an export - it does not couple them to
    this resource being started, and it works from a resource that loads first. Every export
    above is reachable as `vsport:server:<Name>`.

    An event cannot return a value, so the read-only ones are only useful as exports. They are
    registered anyway, so that a caller does not have to remember which is which.
]]
for name, fn in pairs(API) do
    RegisterNetEvent('vsport:server:' .. name, function(...)
        -- A NET event can be fired by a client. Only accept these from the server itself:
        -- `source` is 0 for a server-side TriggerEvent and the player id for a client one.
        if source ~= 0 and source ~= nil and source ~= '' then
            Sport.warn(('a client tried to fire vsport:server:%s; ignored'):format(name))
            return
        end
        fn(...)
    end)
end

Sport.debug(('registered %d exports'):format(Sport.count(API)))
