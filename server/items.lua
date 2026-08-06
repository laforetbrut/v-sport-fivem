--[[
    server/items.lua

    The consumables from Config.Items - whey first among them.

    ---------------------------------------------------------------------------------------
    WHAT THIS FILE DOES AND DELIBERATELY DOES NOT DO
    ---------------------------------------------------------------------------------------

    It registers a USE handler for each configured item, on whichever framework is running.

    It does NOT create the items. Creating an item means writing into qb-core's `items.lua`,
    or ESX's `items` table, or ox_inventory's `data/items.lua` - all of which belong to
    somebody else's resource. A script that silently edited one of those would break on their
    next update and leave you wondering why.

    ITEMS.md walks through adding them, framework by framework, with the exact blocks to
    paste. It takes about two minutes.

    An item that is configured here but does not exist in your inventory costs nothing: the
    handler is registered, nobody can ever have one, and it is never called.
]]

Items = {}

local function started(resource)
    local state = GetResourceState(resource)
    return state == 'started' or state == 'starting'
end

-- ---------------------------------------------------------------------------------------
-- Effects
-- ---------------------------------------------------------------------------------------

--- The message shown after a successful use. Translated when the config named a locale key,
--- used verbatim when it did not.
local function notify(src, entry, ...)
    local text = entry.notify
    if type(text) ~= 'string' or text == '' then return end
    Bridge.notify(src, Locale.text(text, ...), 'success')
end

--[[
    Apply one item's effect. Returns whether it did anything.

    A `false` return means the item is NOT consumed - taking whey when your allowance is
    already full should not eat the item. That decision is made per effect below, and it is
    the difference between an item that feels fair and one that feels like a scam.
]]
local function applyEffect(src, key, entry)
    local profile = Profiles.get(src)
    if not profile then return false end

    local effect = entry.effect
    local amount = tonumber(entry.amount) or 0
    local duration = math.max(0, tonumber(entry.duration) or 0)

    -- --- Whey ---------------------------------------------------------------------------
    if effect == 'recovery' then
        -- Already on the shortened window with more time left than this would give? Refuse,
        -- rather than quietly wasting the item.
        local now = Sport.now()
        local remaining = (tonumber(profile.recoveryUntil) or 0) - now
        if remaining >= duration then
            Bridge.notify(src, L('item.no_effect'), 'error')
            return false
        end

        Profiles.reduceRecovery(src, duration > 0 and duration or Config.Allowance.window)
        notify(src, entry, Sport.duration(Stats.allowanceWindow(true)))

        TriggerEvent('vsport:server:ItemUsed', src, key, 'recovery')
        return true
    end

    -- --- Allowance refund ---------------------------------------------------------------
    if effect == 'allowance' then
        local spent = Profiles.allowanceSpent(profile)
        if (spent.total or 0) <= 0 then
            Bridge.notify(src, L('item.no_effect'), 'error')
            return false
        end

        Profiles.refundAllowance(src, amount)
        notify(src, entry, amount)

        TriggerEvent('vsport:server:ItemUsed', src, key, 'allowance')
        return true
    end

    -- --- Training multiplier --------------------------------------------------------------
    if effect == 'multiplier' then
        Profiles.addMultiplier(src, entry.stat, amount > 0 and amount or 1.5, duration,
            'item:' .. key)
        notify(src, entry, amount, Sport.duration(duration))

        TriggerEvent('vsport:server:ItemUsed', src, key, 'multiplier')
        return true
    end

    -- --- Temporary points -----------------------------------------------------------------
    if effect == 'buff' then
        if not Stats.def(entry.stat) then
            Sport.warn(("Config.Items.%s has effect 'buff' but no valid stat"):format(key))
            return false
        end

        Profiles.addBuff(src, entry.stat, amount, duration, 'item:' .. key)
        notify(src, entry, amount, Sport.duration(duration))

        TriggerEvent('vsport:server:ItemUsed', src, key, 'buff')
        return true
    end

    -- --- Decay protection -------------------------------------------------------------------
    if effect == 'decay_pause' then
        local profileImmune = tonumber(profile.decayImmuneUntil) or 0
        if profileImmune - Sport.now() >= duration then
            Bridge.notify(src, L('item.no_effect'), 'error')
            return false
        end

        exports[Sport.resource]:SetDecayImmunity(src, duration)
        notify(src, entry, Sport.duration(duration))

        TriggerEvent('vsport:server:ItemUsed', src, key, 'decay_pause')
        return true
    end

    -- --- Stamina ----------------------------------------------------------------------------
    if effect == 'stamina' then
        TriggerClientEvent('vsport:client:RestoreStamina', src,
            Sport.clamp(amount, 0.0, 1.0, 1.0))
        notify(src, entry)

        TriggerEvent('vsport:server:ItemUsed', src, key, 'stamina')
        return true
    end

    Sport.warn(("Config.Items.%s has an unknown effect '%s'"):format(key, tostring(effect)))
    return false
end

--[[
    The whole use path: cooldown, effect, consume.

    Called by every framework's handler below, so the behaviour is identical on all of them.
    Returns whether the item should be consumed.
]]
function Items.use(src, key)
    local entry = Config.Items[key]
    if type(entry) ~= 'table' or entry.item == '' then return false end

    local profile = Profiles.get(src)
    if not profile then return false end

    -- Cooldown.
    local cooldown = math.max(0, tonumber(entry.cooldown) or 0)
    if cooldown > 0 then
        local until_ = tonumber(profile.itemCooldowns[key]) or 0
        local left = until_ - Sport.now()

        if left > 0 then
            Bridge.notify(src, L('item.cooldown', Sport.duration(left)), 'error')
            return false
        end
    end

    if not applyEffect(src, key, entry) then return false end

    if cooldown > 0 then
        profile.itemCooldowns[key] = Sport.now() + cooldown
    end

    Sport.debug(('%s used %s'):format(GetPlayerName(src) or src, entry.item))
    return entry.consume ~= false
end

-- ---------------------------------------------------------------------------------------
-- Registration
-- ---------------------------------------------------------------------------------------
--
-- Each framework wants its usable items registered a different way, and ox_inventory wants
-- them registered against itself rather than against the framework. All four paths are
-- attempted; the ones whose resource is not running do nothing.

local function registerQb(key, entry)
    local core = Bridge.core()
    if not core then return false end

    local functions = core.Functions
    if not functions or not functions.CreateUseableItem then return false end

    local ok = pcall(functions.CreateUseableItem, entry.item, function(source_)
        if Items.use(source_, key) and entry.consume ~= false then
            local player = Bridge.player(source_)
            if player and player.Functions and player.Functions.RemoveItem then
                pcall(player.Functions.RemoveItem, entry.item, 1)
                TriggerClientEvent('inventory:client:ItemBox', source_, entry.item, 'remove')
            end
        end
    end)

    return ok
end

local function registerEsx(key, entry)
    local core = Bridge.core()
    if not core or type(core.RegisterUsableItem) ~= 'function' then return false end

    return pcall(core.RegisterUsableItem, entry.item, function(source_)
        if Items.use(source_, key) and entry.consume ~= false then
            local player = Bridge.player(source_)
            if player and player.removeInventoryItem then
                pcall(player.removeInventoryItem, entry.item, 1)
            end
        end
    end)
end

--[[
    ox_inventory.

    ONE handler for every item rather than one per item: ox_inventory fires the same event
    for everything used, so a handler per configured item would mean four handlers all
    checking the same string. The item name is looked up in a map instead.

    ox_inventory removes the item itself when it is declared with `consume = 1` in its own
    data file, so nothing is removed here.
]]
local oxItems = {}              -- item name -> config key

local function registerOxInventory()
    if not started('ox_inventory') then return false end

    AddEventHandler('ox_inventory:usedItem', function(src, name)
        local key = oxItems[name]
        if key then Items.use(src, key) end
    end)

    return true
end

CreateThread(function()
    -- Let the framework and the inventory finish starting. Registering a usable item against
    -- a resource that has not booted silently does nothing on every one of them.
    Wait(4000)

    local registered = 0

    for key, entry in pairs(Config.Items) do
        if type(entry) == 'table' and type(entry.item) == 'string' and entry.item ~= '' then
            oxItems[entry.item] = key

            local ok = registerQb(key, entry)
            if not ok then ok = registerEsx(key, entry) end
            if ok then registered = registered + 1 end
        end
    end

    if registerOxInventory() then
        Sport.debug('listening for ox_inventory:usedItem')
    end

    if registered > 0 then
        Sport.print(('registered %d usable items'):format(registered))
    end

    Sport.print('items must exist in your inventory before players can hold them - see ITEMS.md')
end)

--[[
    The universal fallback.

    A server whose inventory this resource does not know about can call this from its own use
    handler and get identical behaviour:

        exports['v-sport']:UseItem(source, 'whey')

    Returns whether the item should be consumed, so the caller knows whether to remove it.
]]
exports('UseItem', function(src, key)
    return Items.use(tonumber(src), key)
end)

--- Which items are configured, and what each does. For a shop or a documentation command.
exports('GetItems', function()
    local out = {}
    for key, entry in pairs(Config.Items) do
        if type(entry) == 'table' and entry.item ~= '' then
            out[key] = {
                item = entry.item,
                effect = entry.effect,
                amount = entry.amount,
                duration = entry.duration,
                cooldown = entry.cooldown,
            }
        end
    end
    return out
end)
