--[[
    bridge/shared/sport.lua

    The shared core. Small, dependency-free helpers that both sides need, plus the debug
    printer. Loads before Config, so nothing in here may read Config at load time.
]]

Sport = {}

Sport.resource = GetCurrentResourceName()

-- ---------------------------------------------------------------------------------------
-- Numbers
-- ---------------------------------------------------------------------------------------

--- Clamp `value` into [min, max]. A non-number returns `fallback` rather than raising, so a
--- corrupt database row or a hostile net event degrades to a default instead of a stack trace.
function Sport.clamp(value, min, max, fallback)
    local number = tonumber(value)
    if not number then return fallback end
    if number ~= number then return fallback end          -- NaN is the one number that fails ==
    if number < min then return min end
    if number > max then return max end
    return number
end

--- Round to `places` decimals. Stats are stored with one decimal: a session that gives 0.35
--- of a point has to accumulate rather than vanish into an integer.
function Sport.round(value, places)
    local number = tonumber(value) or 0
    local factor = 10 ^ (places or 0)
    return math.floor(number * factor + 0.5) / factor
end

--- Linear interpolation, clamped at both ends. Used everywhere a stat between 0 and 100 has
--- to become a multiplier between two configured bounds.
function Sport.lerp(from, to, t)
    local factor = Sport.clamp(t, 0.0, 1.0, 0.0)
    return from + (to - from) * factor
end

-- ---------------------------------------------------------------------------------------
-- Time
-- ---------------------------------------------------------------------------------------

--[[
    Wall clock in seconds.

    `os.time()` is SERVER ONLY in FiveM - `os`, `io` and `package` are stripped from the
    client Lua state. The client answer is `GetCloudTimeAsInt()`, which is the same unix
    epoch fetched from Rockstar's time service.

    Everything that decays is timestamped with this, so the two sides have to agree on what
    "now" means or a client-side countdown drifts away from the server's decay.
]]
if IsDuplicityVersion() then
    function Sport.now()
        return os.time()
    end
else
    function Sport.now()
        local cloud = GetCloudTimeAsInt()
        -- The cloud time is 0 for the first few frames after joining, before the service
        -- has answered. Returning 0 there would make every timestamp look ancient and
        -- trigger a full decay, so it is treated as "unknown" instead.
        if not cloud or cloud <= 0 then return 0 end
        return cloud
    end
end

--- Seconds as a short human string: `2d 4h`, `4h 12m`, `12m`, `45s`. Used by the stats panel
--- and by /sportinfo; never by anything that has to parse it back.
function Sport.duration(seconds)
    local total = math.floor(tonumber(seconds) or 0)
    if total < 0 then total = 0 end

    local days = math.floor(total / 86400)
    local hours = math.floor((total % 86400) / 3600)
    local minutes = math.floor((total % 3600) / 60)

    if days > 0 then return ('%dd %dh'):format(days, hours) end
    if hours > 0 then return ('%dh %dm'):format(hours, minutes) end
    if minutes > 0 then return ('%dm'):format(minutes) end
    return ('%ds'):format(total % 60)
end

-- ---------------------------------------------------------------------------------------
-- Tables
-- ---------------------------------------------------------------------------------------

--- A deep copy. Every export that hands a stats table out returns one of these, so a caller
--- that mutates the result cannot reach into this resource's own state.
function Sport.copy(value)
    if type(value) ~= 'table' then return value end

    local out = {}
    for key, entry in pairs(value) do
        out[key] = Sport.copy(entry)
    end
    return out
end

--- Merge `patch` into `base`, in place, recursing into tables. Lists are replaced wholesale
--- rather than merged element by element: merging two lists of different lengths produces a
--- result that was in neither, which is never what an operator writing a config meant.
function Sport.merge(base, patch)
    if type(base) ~= 'table' or type(patch) ~= 'table' then return base end

    for key, value in pairs(patch) do
        if type(value) == 'table' and type(base[key]) == 'table' and not value[1] then
            Sport.merge(base[key], value)
        else
            base[key] = Sport.copy(value)
        end
    end
    return base
end

--- The keys of `map`, sorted by an `order` field when the values carry one and
--- alphabetically when they do not. Config tables are hash maps, and `pairs` order is
--- undefined - anything the player SEES has to be built from this or the stats panel
--- reshuffles itself between restarts.
function Sport.sortedKeys(map)
    local keys = {}
    if type(map) ~= 'table' then return keys end

    for key in pairs(map) do keys[#keys + 1] = key end

    table.sort(keys, function(a, b)
        local left = type(map[a]) == 'table' and tonumber(map[a].order) or nil
        local right = type(map[b]) == 'table' and tonumber(map[b].order) or nil
        if left and right and left ~= right then return left < right end
        if left and not right then return true end
        if right and not left then return false end
        return tostring(a) < tostring(b)
    end)

    return keys
end

--- How many pairs are in a hash map. `#` only answers for sequences, and every index in
--- this resource is keyed on a model hash or a stat name.
function Sport.count(map)
    if type(map) ~= 'table' then return 0 end
    local total = 0
    for _ in pairs(map) do total = total + 1 end
    return total
end

--- Whether `list` contains `wanted`. Config lists are small enough that a linear scan beats
--- building a set for a handful of lookups per session.
function Sport.contains(list, wanted)
    if type(list) ~= 'table' then return false end
    for _, entry in ipairs(list) do
        if entry == wanted then return true end
    end
    return false
end

--[[
    Whether `value` is worth attempting to call.

    NOT `type(value) == 'function'`, and the difference is why a server ran for a day without
    saving a single stat.

    FiveM hands an object across a resource boundary as a PROXY. qb-core's
    QBCore.Functions.GetPlayer arrives as a table carrying a __call metamethod, not as a
    function. Measured on a live stock qb-core:

        type(gp) = table    getmetatable(gp).__call = function    gp(src) -> the player

    So `type(fn) ~= 'function' then return nil` rejected an object that was perfectly callable,
    every one of the forty retries answered nil the same way, no identifier was ever resolved,
    and every player joined without stats. The console said the framework was found, because it
    was.

    The corroboration was already in the same resource: server/items.lua reaches
    CreateUseableItem through a truthiness test and a pcall, and item registration WORKED on the
    same server, in the same boot, where the player lookup did not. Two paths to the same object,
    one gated on type and one not, and only the gated one failed.

    This answers the weaker question on purpose - function, or anything that could be a proxy -
    because a metatable can be hidden behind __metatable and a stricter check would go back to
    guessing. The pcall around the call is the real guard and always was; this only keeps a nil
    or a stray string from being called at all.
]]
function Sport.callable(value)
    local kind = type(value)
    return kind == 'function' or kind == 'table' or kind == 'userdata'
end

-- ---------------------------------------------------------------------------------------
-- Console
-- ---------------------------------------------------------------------------------------

local PREFIX = '^5[v-sport]^7 '

--[[
    WHO IS ALLOWED TO SEE THE CONSOLE, and why this is a hook rather than a check.

    A player's F8 is not a log file. Diagnostics like "the prop model would not load", "the scenario
    would not start" or "no stats received after 10 attempts" are written for whoever runs the server,
    and printing them to every player is noise they cannot act on and did not ask for.

    On the SERVER this never applies: the server console belongs to the operator, so everything prints.

    On the CLIENT, client/state.lua assigns this once the server has told it whether the player is an
    admin. It is a hook rather than a direct check because this file is shared and loads first - it
    cannot know about State, and hard-coding a dependency on it would make the shared core depend on
    the client. Left nil, everything prints, which is the safe default for a file that may be running
    before anything has had a chance to set it.
]]
Sport.consoleAllowed = nil

local function mayPrint()
    if Sport.consoleAllowed == nil then return true end
    return Sport.consoleAllowed() == true
end

function Sport.print(...)
    if not mayPrint() then return end
    local parts = {}
    for index = 1, select('#', ...) do
        parts[#parts + 1] = tostring((select(index, ...)))
    end
    print(PREFIX .. table.concat(parts, ' '))
end

function Sport.warn(...)
    if not mayPrint() then return end
    local parts = {}
    for index = 1, select('#', ...) do
        parts[#parts + 1] = tostring((select(index, ...)))
    end
    print('^3[v-sport]^7 ' .. table.concat(parts, ' '))
end

--- Debug output. Silent unless Config.Debug.enabled, and guarded against Config not existing
--- yet: this file loads before config.lua, and something in between may want to log.
function Sport.debug(...)
    if not Config or not Config.Debug or not Config.Debug.enabled then return end
    local parts = {}
    for index = 1, select('#', ...) do
        parts[#parts + 1] = tostring((select(index, ...)))
    end
    print('^6[v-sport]^7 ' .. table.concat(parts, ' '))
end

-- ---------------------------------------------------------------------------------------
-- JSON
-- ---------------------------------------------------------------------------------------

--- Decode, never raise. A database column written by an older version, or hand-edited, must
--- degrade to `fallback` rather than take the player's load path down with it.
function Sport.decode(text, fallback)
    if type(text) ~= 'string' or text == '' then return fallback end
    local ok, value = pcall(json.decode, text)
    if not ok or type(value) ~= 'table' then return fallback end
    return value
end

--- Encode, never raise. Returns `'{}'` on failure so a write always has something valid to
--- put in the column.
function Sport.encode(value)
    local ok, text = pcall(json.encode, value)
    if not ok or type(text) ~= 'string' then return '{}' end
    return text
end
