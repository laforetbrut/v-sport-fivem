--[[
    shared/custom.lua

    The shape of a live equipment addition, and the two conversions it needs.

    ---------------------------------------------------------------------------------------
    WHY THIS FILE EXISTS
    ---------------------------------------------------------------------------------------

    Adding a prop used to mean: read a model name off /vsportscan, open config.lua, write an
    ExtraEquipment block, restart the resource, walk back to the gym, find out the body lands
    wrong, run /vsportprop, copy a block out of F8, open config.lua again, restart again.

    It now means standing in front of the thing and typing /vsportadd treadmill. That works because
    the addition is DATA rather than source: the server keeps it in data/custom.json, pushes it to
    every client, and both sides rebuild the catalogue in place.

    ---------------------------------------------------------------------------------------
    THE ONE AWKWARD PART: vector3 DOES NOT SURVIVE JSON
    ---------------------------------------------------------------------------------------

    `animOffset` and friends are vector3 values, and json.encode turns a vector3 into something
    json.decode gives back as a plain table - which then reaches AttachEntityToEntity as a table
    and fails, quietly, at the one moment nobody is watching the console.

    So every value crosses the boundary through `Custom.pack` and `Custom.unpack`. Storage is
    always plain `{ x = , y = , z = }`; the runtime is always vector3. Nothing else in the resource
    has to know.

    JSON rather than a generated Lua file, deliberately. A Lua file would keep vector3 exactly and
    would be nicer to hand-edit, but loading it means executing it, and a half-finished hand edit
    then takes the resource down instead of printing a warning. /vsportexport covers the case a
    Lua file would have served: it prints a paste-ready block for config.lua.
]]

Custom = {}

--- Fields that hold a vector3 and therefore need converting in both directions. Adding a new
--- vector field to an equipment entry means adding it here, or it silently becomes a table.
Custom.VECTOR_FIELDS = {
    'offset', 'animOffset', 'animRot', 'coords',
}

--- Fields inside a `props` entry that hold a vector3.
Custom.PROP_VECTOR_FIELDS = {
    'pos', 'rot', 'rotOffset',
}

--- Is this a vector3, or a table that used to be one? Both answer yes: a decoded vector3 is a
--- plain table with the same three keys, and that is exactly the case this has to catch.
local function isVectorish(value)
    return type(value) == 'table'
        and tonumber(value.x) ~= nil
        and tonumber(value.y) ~= nil
        and tonumber(value.z) ~= nil
end

--- A vector3 as a plain table, ready for json.encode. Rounded, because three decimals is finer
--- than anything the tuner can resolve and a file full of 0.08999999999 is unreadable.
local function packVector(value)
    if not isVectorish(value) then return nil end
    return {
        x = Sport.round(value.x, 3),
        y = Sport.round(value.y, 3),
        z = Sport.round(value.z, 3),
    }
end

local function unpackVector(value)
    if not isVectorish(value) then return nil end
    return vector3(tonumber(value.x) or 0.0, tonumber(value.y) or 0.0, tonumber(value.z) or 0.0)
end

--- Walk one equipment entry, converting every known vector field with `convert`.
local function walk(entry, convert)
    if type(entry) ~= 'table' then return entry end

    local out = Sport.copy(entry)

    for _, field in ipairs(Custom.VECTOR_FIELDS) do
        if out[field] ~= nil then
            out[field] = convert(out[field]) or out[field]
        end
    end

    if type(out.props) == 'table' then
        for _, spec in ipairs(out.props) do
            if type(spec) == 'table' then
                for _, field in ipairs(Custom.PROP_VECTOR_FIELDS) do
                    if spec[field] ~= nil then
                        spec[field] = convert(spec[field]) or spec[field]
                    end
                end
            end
        end
    end

    -- modelOverrides are entries in their own right, one level down.
    if type(out.modelOverrides) == 'table' then
        local converted = {}
        for model, override in pairs(out.modelOverrides) do
            converted[model] = walk(override, convert)
        end
        out.modelOverrides = converted
    end

    return out
end

--- Runtime shape -> storage shape. Every vector3 becomes { x, y, z }.
function Custom.pack(entry)
    return walk(entry, packVector)
end

--- Storage shape -> runtime shape. Every { x, y, z } becomes a vector3.
function Custom.unpack(entry)
    return walk(entry, unpackVector)
end

--- A whole overlay table, in one direction or the other.
function Custom.packAll(overlay)
    local out = {}
    for key, entry in pairs(overlay or {}) do
        out[key] = Custom.pack(entry)
    end
    return out
end

function Custom.unpackAll(overlay)
    local out = {}
    for key, entry in pairs(overlay or {}) do
        out[key] = Custom.unpack(entry)
    end
    return out
end

--[[
    Is `name` a plausible model name?

    Not "does it exist" - only the client can answer that, with IsModelValid, and it does before
    offering to add anything. This is the cheaper question the server can answer for itself before
    writing a name into a file that will be read at every boot from now on.
]]
function Custom.validModelName(name)
    if type(name) ~= 'string' then return false end
    if #name < 3 or #name > 64 then return false end
    return name:match('^[%w_%-]+$') ~= nil
end

--[[
    Format one overlay entry as Lua source, for /vsportexport.

    The point of the export is graduation: an addition proven in game moves into config.lua, where
    it is under version control and survives someone deleting data/custom.json. So the output has
    to be genuinely paste-ready, vector3 calls and all - which is the other half of why storage
    keeps plain tables and the runtime keeps vectors.
]]
function Custom.toLua(key, entry, indent)
    indent = indent or '        '
    local lines = {}

    local function add(text) lines[#lines + 1] = indent .. text end

    local function vectorText(value)
        if not isVectorish(value) then return 'nil' end
        return ('vector3(%.3f, %.3f, %.3f)'):format(value.x, value.y, value.z)
    end

    add(('%s = {'):format(key))

    if type(entry.models) == 'table' and #entry.models > 0 then
        add('    models = {')
        for _, model in ipairs(entry.models) do
            add(("        '%s',"):format(tostring(model)))
        end
        add('    },')
    end

    if entry.enabled ~= nil then
        add(('    enabled = %s,'):format(tostring(entry.enabled)))
    end
    if entry.placeAnim ~= nil then
        add(('    placeAnim = %s,'):format(tostring(entry.placeAnim)))
    end
    if isVectorish(entry.animOffset) then
        add(('    animOffset = %s,'):format(vectorText(entry.animOffset)))
    end
    if tonumber(entry.animHeading) then
        add(('    animHeading = %.1f,'):format(entry.animHeading))
    end
    if isVectorish(entry.animRot) then
        add(('    animRot = %s,'):format(vectorText(entry.animRot)))
    end

    if type(entry.props) == 'table' and #entry.props > 0 then
        add('    props = {')
        for _, spec in ipairs(entry.props) do
            local parts = { ("model = '%s'"):format(tostring(spec.model)) }
            if spec.twoHanded then parts[#parts + 1] = 'twoHanded = true' end
            if spec.bone then parts[#parts + 1] = ('bone = %d'):format(spec.bone) end
            if isVectorish(spec.pos) then
                parts[#parts + 1] = 'pos = ' .. vectorText(spec.pos)
            end
            if isVectorish(spec.rotOffset) then
                parts[#parts + 1] = 'rotOffset = ' .. vectorText(spec.rotOffset)
            end
            add(('        { %s },'):format(table.concat(parts, ', ')))
        end
        add('    },')
    end

    if type(entry.modelOverrides) == 'table' and next(entry.modelOverrides) then
        add('    modelOverrides = {')
        for model, override in pairs(entry.modelOverrides) do
            add(("        ['%s'] = {"):format(tostring(model)))
            if isVectorish(override.animOffset) then
                add(('            animOffset = %s,'):format(vectorText(override.animOffset)))
            end
            if tonumber(override.animHeading) then
                add(('            animHeading = %.1f,'):format(override.animHeading))
            end
            if isVectorish(override.animRot) then
                add(('            animRot = %s,'):format(vectorText(override.animRot)))
            end
            if type(override.props) == 'table' and #override.props > 0 then
                add('            props = {')
                for _, spec in ipairs(override.props) do
                    local parts = { ("model = '%s'"):format(tostring(spec.model)) }
                    if spec.twoHanded then parts[#parts + 1] = 'twoHanded = true' end
                    if isVectorish(spec.pos) then
                        parts[#parts + 1] = 'pos = ' .. vectorText(spec.pos)
                    end
                    if isVectorish(spec.rotOffset) then
                        parts[#parts + 1] = 'rotOffset = ' .. vectorText(spec.rotOffset)
                    end
                    add(('                { %s },'):format(table.concat(parts, ', ')))
                end
                add('            },')
            end
            add('        },')
        end
        add('    },')
    end

    add('},')
    return lines
end
