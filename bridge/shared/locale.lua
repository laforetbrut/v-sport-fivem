--[[
    bridge/shared/locale.lua

    `L(key, ...)` and the table it reads.

    Locale files register themselves into `Locales` by calling `Locale.register`. English is
    the fallback for every key missing from another language, so `locales/en.lua` loads first
    in the manifest and is the base every other file is read against.

    A missing key returns the key itself rather than nil or an empty string. A UI that draws
    `stat.strength` is instantly diagnosable; one that draws nothing is not.
]]

Locales = {}
Locale = {}

local active                -- resolved lazily: the convars are not readable at load time
local FALLBACK = 'en'

--- Register a language. Called at the bottom of each locale file.
function Locale.register(code, entries)
    if type(code) ~= 'string' or type(entries) ~= 'table' then return end
    Locales[code] = entries
end

--[[
    Which language to use.

    Config first, then the resource's own convar, then qb-core's, then English. Resolved on
    first use and cached: `GetConvar` is cheap but this is called for every string drawn in
    every frame of the stats panel.
]]
function Locale.current()
    if active then return active end

    local configured = Config and Config.General and Config.General.locale or 'auto'

    if type(configured) == 'string' and configured ~= '' and configured ~= 'auto' then
        active = configured
    else
        local convar = GetConvar('sport_locale', '')
        if convar == '' then convar = GetConvar('qb_locale', '') end
        if convar == '' then convar = GetConvar('esx_locale', '') end
        active = convar ~= '' and convar or FALLBACK
    end

    if not Locales[active] then
        if active ~= FALLBACK then
            Sport.warn(("locale '%s' is not installed, falling back to '%s'"):format(active, FALLBACK))
        end
        active = FALLBACK
    end

    return active
end

--- Force a language at runtime. Used by /sportlocale on a debug server and by nothing else.
function Locale.set(code)
    if type(code) == 'string' and Locales[code] then
        active = code
        return true
    end
    return false
end

--[[
    Translate.

    `L('notify.gained', 1.5, 'Strength')` formats the entry with string.format. A format
    string whose placeholders do not match its arguments raises inside string.format, so the
    call is guarded: a bad translation shows the unformatted string rather than taking down
    whatever was drawing it.
]]
function L(key, ...)
    if type(key) ~= 'string' then return '' end

    local language = Locales[Locale.current()] or {}
    local text = language[key]

    if text == nil then
        local fallback = Locales[FALLBACK] or {}
        text = fallback[key]
    end

    if type(text) ~= 'string' then return key end
    if select('#', ...) == 0 then return text end

    local ok, formatted = pcall(string.format, text, ...)
    return ok and formatted or text
end

--- Whether `key` exists in the active language or in English. Used by the equipment
--- catalogue: a `label` that is not a known key is treated as literal text, so an operator
--- adding equipment in Config.ExtraEquipment can write "Squat rack" instead of inventing a
--- translation key and adding it to two files.
function Locale.has(key)
    if type(key) ~= 'string' then return false end
    local language = Locales[Locale.current()] or {}
    if language[key] ~= nil then return true end
    local fallback = Locales[FALLBACK] or {}
    return fallback[key] ~= nil
end

--- Translate when the value is a known key, and return it unchanged when it is not.
function Locale.text(value, ...)
    if type(value) ~= 'string' then return '' end
    if Locale.has(value) then return L(value, ...) end
    return value
end
