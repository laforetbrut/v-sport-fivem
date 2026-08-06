--[[
    client/ui.lua

    Every pixel this resource draws, drawn with the game's own natives.

    There is no NUI. No `ui_page`, no HTML, no CEF process, no SendNUIMessage traffic and no
    focus to get stuck. The cost of this file is a handful of draw calls per frame while
    something is actually on screen, and exactly zero when nothing is.

    ---------------------------------------------------------------------------------------
    THE TWO THINGS THAT TRIP EVERYBODY UP
    ---------------------------------------------------------------------------------------

    1. SCREEN SPACE IS NOT SQUARE. DrawRect takes fractions of the screen, so a rect with
       w == h is a wide rectangle on a 16:9 display and a very wide one on an ultrawide. Any
       box that has to look square is sized with `UI.square()`.

    2. TEXT COMMANDS ARE A STATE MACHINE. SetTextFont, SetTextScale and the rest configure
       the NEXT draw, and the game resets some of them and not others. So every text draw
       here sets every property it cares about, every time, rather than assuming what the
       last caller left behind.
]]

UI = {}

-- Cached once. GetAspectRatio is not free and the answer only changes on a resolution
-- change, which fires a resize event nothing here needs to listen for: the value is
-- re-read on a slow timer instead.
local aspect = 16.0 / 9.0

CreateThread(function()
    while true do
        aspect = GetAspectRatio(false)
        if not aspect or aspect <= 0 then aspect = 16.0 / 9.0 end
        Wait(10000)
    end
end)

--- The width that makes a box of height `h` square on screen.
function UI.square(h)
    return h / aspect
end

--- The configured scale, so a caller can size against it without reading Config every frame.
function UI.scale()
    return tonumber(Config.UI.scale) or 1.0
end

-- ---------------------------------------------------------------------------------------
-- Colours
-- ---------------------------------------------------------------------------------------

--- Unpack a { r, g, b } or { r, g, b, a } config entry. Missing alpha is opaque; a missing
--- or malformed entry is magenta, which is deliberately hideous - a colour typo should be
--- obvious on screen rather than invisible.
function UI.colour(name, alphaOverride)
    local entry = Config.UI.colours[name]
    if type(entry) ~= 'table' then return 255, 0, 255, 255 end

    return math.floor(entry[1] or 255),
           math.floor(entry[2] or 0),
           math.floor(entry[3] or 255),
           math.floor(alphaOverride or entry[4] or 255)
end

--- Blend two named colours. Used for the fill of a bar that changes colour as it fills.
function UI.mix(fromName, toName, t)
    local r1, g1, b1, a1 = UI.colour(fromName)
    local r2, g2, b2, a2 = UI.colour(toName)
    local factor = Sport.clamp(t, 0.0, 1.0, 0.0)

    return math.floor(Sport.lerp(r1, r2, factor)),
           math.floor(Sport.lerp(g1, g2, factor)),
           math.floor(Sport.lerp(b1, b2, factor)),
           math.floor(Sport.lerp(a1, a2, factor))
end

-- ---------------------------------------------------------------------------------------
-- Rectangles
-- ---------------------------------------------------------------------------------------

--- A filled rectangle. `x` and `y` are the CENTRE, which is what DrawRect wants and what
--- everything in this file is written against.
function UI.rect(x, y, w, h, r, g, b, a)
    DrawRect(x, y, w, h, r, g, b, a or 255)
end

--- The same, from a named colour.
function UI.fill(x, y, w, h, name, alpha)
    local r, g, b, a = UI.colour(name, alpha)
    DrawRect(x, y, w, h, r, g, b, a)
end

--[[
    A panel: a filled body with a one-pixel lit edge.

    There is no rounded corner and no blur, because the natives have neither. What reads as
    "a panel" rather than "a grey box" is the edge - a barely visible lighter line around the
    fill, which is what every GTA overlay actually does.
]]
function UI.panel(x, y, w, h, bodyName, edgeName)
    local edge = 0.0016

    if edgeName then
        UI.fill(x, y, w + edge * 2 / aspect, h + edge * 2, edgeName)
    end
    UI.fill(x, y, w, h, bodyName or 'panel')
end

--- A horizontal accent line, used under a panel header.
function UI.line(x, y, w, name, thickness)
    UI.fill(x, y, w, thickness or 0.0016, name or 'accent')
end

-- ---------------------------------------------------------------------------------------
-- Text
-- ---------------------------------------------------------------------------------------

--[[
    Draw text.

    `align` is 'left' | 'centre' | 'right', and it is done here rather than left to
    SetTextCentre because the native only knows about centring: right alignment means
    measuring the string and shifting the origin, which is what UI.textWidth is for.

    Fonts: 0 is the chunky GTA title font, 4 is the condensed one used by the HUD, 6 is the
    fixed-width one. 4 is the default because it is the one the game itself uses for
    everything that has to be read at a glance.
]]
function UI.text(content, x, y, opts)
    if type(content) ~= 'string' or content == '' then return end

    opts = opts or {}
    local scale = (opts.scale or 0.34) * UI.scale()
    local font = opts.font or 4
    local r, g, b, a = UI.colour(opts.colour or 'text', opts.alpha)

    SetTextFont(font)
    SetTextScale(0.0, scale)
    SetTextColour(r, g, b, a)

    -- A drop shadow costs nothing and is the difference between readable and not when the
    -- panel happens to sit over a white wall.
    if opts.shadow ~= false then
        SetTextDropShadow()
        SetTextDropshadow(1, 0, 0, 0, 200)
    end
    if opts.outline then SetTextOutline() end

    local drawX = x
    if opts.align == 'centre' then
        SetTextCentre(true)
    elseif opts.align == 'right' then
        drawX = x - UI.textWidth(content, font, scale)
    end

    BeginTextCommandDisplayText('STRING')
    AddTextComponentSubstringPlayerName(content)
    EndTextCommandDisplayText(drawX, y)
end

--[[
    The width of `content` as a fraction of the screen.

    This has to run the measurement text commands, which is why it is not free and why the
    stats panel measures its labels once when it opens rather than every frame.
]]
function UI.textWidth(content, font, scale)
    if type(content) ~= 'string' or content == '' then return 0.0 end

    SetTextFont(font or 4)
    SetTextScale(0.0, scale or 0.34)
    BeginTextCommandGetWidth('STRING')
    AddTextComponentSubstringPlayerName(content)
    return EndTextCommandGetWidth(true)
end

--[[
    Text in the world, above `coords`.

    SetDrawOrigin moves the 2D drawing origin to a world position, so everything drawn until
    ClearDrawOrigin is positioned relative to that point and scales with distance for free.
    It has to be cleared or every subsequent draw this frame lands in the wrong place, which
    is why there is no early return between the two calls.
]]
function UI.text3d(coords, content, opts)
    opts = opts or {}

    SetDrawOrigin(coords.x, coords.y, coords.z, 0)

    if opts.background ~= false then
        local width = UI.textWidth(content, opts.font or 4, (opts.scale or 0.32) * UI.scale())
        UI.fill(0.0, 0.0125, width + 0.014, 0.030, 'panel')
    end

    UI.text(content, 0.0, 0.0, {
        scale = opts.scale or 0.32,
        font = opts.font or 4,
        colour = opts.colour or 'text',
        align = 'centre',
    })

    ClearDrawOrigin()
end

--- The game's own help box, top left. Cheap, familiar, and it obeys the player's HUD scale.
function UI.help(content)
    if type(content) ~= 'string' or content == '' then return end
    BeginTextCommandDisplayHelp('STRING')
    AddTextComponentSubstringPlayerName(content)
    EndTextCommandDisplayHelp(0, false, true, -1)
end

-- ---------------------------------------------------------------------------------------
-- Bars
-- ---------------------------------------------------------------------------------------

--- A progress bar. `pct` is 0..1. The fill grows from the left edge, which means its centre
--- moves as it grows - the arithmetic below is that, and it is the single most commonly
--- got-wrong line in any native HUD.
function UI.bar(x, y, w, h, pct, trackName, fillName, fillColour)
    local fraction = Sport.clamp(pct, 0.0, 1.0, 0.0)

    UI.fill(x, y, w, h, trackName or 'barTrack')

    if fraction > 0.0 then
        local fillWidth = w * fraction
        if fillColour then
            UI.rect(x - w * 0.5 + fillWidth * 0.5, y, fillWidth, h,
                fillColour[1], fillColour[2], fillColour[3], fillColour[4] or 255)
        else
            UI.fill(x - w * 0.5 + fillWidth * 0.5, y, fillWidth, h, fillName or 'barFill')
        end
    end
end

--[[
    The minigame's timing bar: a track, a good band, a perfect band inside it, and a marker
    sweeping left to right.

    The bands are drawn UNDER the marker so the marker stays visible when it is inside them,
    and the marker is drawn as a thin bright rect rather than a sprite so there is nothing to
    stream and nothing to load.
]]
function UI.timingBar(x, y, w, h, progress, goodZone, perfectZone)
    UI.fill(x, y, w, h, 'barTrack')

    local left = x - w * 0.5

    local function band(zone, name)
        if type(zone) ~= 'table' then return end
        local from = Sport.clamp(zone[1], 0.0, 1.0, 0.0)
        local to = Sport.clamp(zone[2], from, 1.0, 1.0)
        local width = w * (to - from)
        if width <= 0 then return end
        UI.fill(left + w * from + width * 0.5, y, width, h, name)
    end

    band(goodZone, 'zoneGood')
    band(perfectZone, 'zonePerfect')

    local at = Sport.clamp(progress, 0.0, 1.0, 0.0)
    local markerWidth = 0.0022
    UI.fill(left + w * at, y, markerWidth, h * 1.9, 'text')
end

-- ---------------------------------------------------------------------------------------
-- Key boxes
-- ---------------------------------------------------------------------------------------

--[[
    One key of a QTE sequence.

    `state` is 'idle' | 'active' | 'hit' | 'miss'. The box is square, sized from its height,
    and the label is centred in it both ways - the vertical centring is the magic number
    below, because native text is drawn from its TOP LEFT and there is no way to ask the game
    how tall a line is.
]]
function UI.keyBox(x, y, h, label, state)
    local w = UI.square(h)

    local body = 'keyIdle'
    if state == 'active' then body = 'keyActive'
    elseif state == 'hit' then body = 'keyHit'
    elseif state == 'miss' then body = 'keyMiss' end

    -- The active box gets a lit edge so it reads as "this one, now" at a glance even for a
    -- player who cannot tell the two reds apart.
    if state == 'active' then
        UI.fill(x, y, w + 0.005 / aspect, h + 0.005, 'text')
    else
        UI.fill(x, y, w + 0.0022 / aspect, h + 0.0022, 'panelEdge')
    end

    UI.fill(x, y, w, h, body)

    -- Long labels like SPC need a smaller scale or they overflow a square box.
    local scale = #label > 1 and 0.30 or 0.42

    UI.text(label, x, y - h * 0.36, {
        scale = scale,
        font = 4,
        colour = state == 'idle' and 'text' or 'text',
        align = 'centre',
    })
end

-- ---------------------------------------------------------------------------------------
-- Key labels
-- ---------------------------------------------------------------------------------------
--
--  WHY THIS IS NOT JUST GetControlInstructionalButton.
--
--  That native answers with an internal token for a good number of controls - `b_1004` for
--  BACKSPACE, for instance - and a prompt reading "hold [b_1004] to stop" is what this
--  function exists to prevent. It is tried first, accepted only when it comes back looking
--  like something a person would recognise, and otherwise falls through to the table below.
--
--  The keyboard LAYOUT cannot be asked for at all. GTA maps a control to a physical key
--  position, so control 34 is `A` on QWERTY and `Q` on AZERTY - the same key, a different
--  letter printed on it. Config.Minigame.keyboardLayout decides which letter to draw.

-- Names for the controls this resource uses, per layout. Only the six QTE keys and the
-- handful of prompt keys need to be here.
local KEY_NAMES = {
    qwerty = {
        [32] = 'W', [33] = 'S', [34] = 'A', [35] = 'D',
        [38] = 'E', [44] = 'Q', [45] = 'R', [23] = 'F', [22] = 'SPACE',
        [47] = 'G', [177] = 'BACKSPACE', [200] = 'ESC',
    },
    azerty = {
        [32] = 'Z', [33] = 'S', [34] = 'Q', [35] = 'D',
        [38] = 'E', [44] = 'A', [45] = 'R', [23] = 'F', [22] = 'ESPACE',
        [47] = 'G', [177] = 'RETOUR', [200] = 'ECHAP',
    },
}

local resolvedLayout

--- 'azerty' or 'qwerty'. 'auto' derives it from the locale, which is the best signal
--- available: a French-locale server is overwhelmingly an AZERTY server.
function UI.layout()
    if resolvedLayout then return resolvedLayout end

    local configured = Config.Minigame.keyboardLayout or 'auto'

    if configured == 'azerty' or configured == 'qwerty' then
        resolvedLayout = configured
    else
        resolvedLayout = Locale.current() == 'fr' and 'azerty' or 'qwerty'
    end

    return resolvedLayout
end

--- The letter to draw for a key pool entry, honouring the layout.
function UI.poolLabel(entry)
    if type(entry) ~= 'table' then return '?' end

    local layout = UI.layout()
    local label = entry[layout] or entry.label
    if type(label) == 'string' and label ~= '' then return label end

    return UI.keyLabel(entry.control)
end

--[[
    A human-readable name for `control`.

    `fallback` is used when neither the game nor the table knows it, so a caller can supply
    something better than a question mark.
]]
function UI.keyLabel(control, fallback)
    local index = tonumber(control)
    if not index then return fallback or '?' end

    local raw = GetControlInstructionalButton(0, index, true)

    if type(raw) == 'string' and raw ~= '' then
        -- `t_NAME` is the game's own markup for a named key and is the good case.
        local named = raw:match('^t_(.+)$')
        if named and named ~= '' then return named end

        -- Anything that is a bare word of a sensible length is usable as-is. A `b_1234`
        -- token, or anything with punctuation in it, is not.
        if not raw:match('^b_') and raw:match('^[%w ]+$') and #raw <= 8 then
            return raw
        end
    end

    local table_ = KEY_NAMES[UI.layout()] or KEY_NAMES.qwerty
    return table_[index] or fallback or '?'
end

-- ---------------------------------------------------------------------------------------
-- Markers
-- ---------------------------------------------------------------------------------------

--- The ground marker under a usable piece of equipment.
function UI.marker(coords)
    local cfg = Config.Interaction.marker
    if not cfg.enabled then return end

    local colour = cfg.colour or { 255, 255, 255, 90 }
    local scale = cfg.scale or vector3(0.7, 0.7, 0.25)

    DrawMarker(
        cfg.type or 27,
        coords.x, coords.y, coords.z + (cfg.zOffset or 0.03),
        0.0, 0.0, 0.0,
        0.0, 0.0, 0.0,
        scale.x, scale.y, scale.z,
        math.floor(colour[1] or 255), math.floor(colour[2] or 255),
        math.floor(colour[3] or 255), math.floor(colour[4] or 90),
        cfg.bobUpAndDown == true,
        false,                      -- faceCamera
        2,
        cfg.rotate == true,
        nil, nil, false
    )
end

-- ---------------------------------------------------------------------------------------
-- Toasts
-- ---------------------------------------------------------------------------------------
--
-- The fallback notification, used when no provider was detected or when the operator asked
-- for this resource's own look. The render loop only exists while there is something to
-- render: an empty queue ends the thread rather than spinning at Wait(0) forever.

local toasts = {}
local toastLoopRunning = false

local TOAST_ACCENT = {
    primary = 'accent',
    success = 'judgePerfect',
    error = 'judgeMiss',
}

local function runToastLoop()
    if toastLoopRunning then return end
    toastLoopRunning = true

    CreateThread(function()
        while #toasts > 0 do
            local now = GetGameTimer()
            local cfg = Config.UI.toast

            -- Expire from the front. Removing while iterating forwards would skip an entry,
            -- so the walk is backwards.
            for index = #toasts, 1, -1 do
                if now >= toasts[index].expires then
                    table.remove(toasts, index)
                end
            end

            local y = cfg.y or 0.14
            for index = 1, math.min(#toasts, cfg.maxStacked or 3) do
                local toast = toasts[index]
                local width = UI.textWidth(toast.message, 4, 0.34 * UI.scale()) + 0.026
                local height = 0.036

                -- Fade the last 400ms rather than popping out.
                local left = toast.expires - now
                local alpha = left < 400 and math.floor(255 * (left / 400)) or 255

                UI.fill(cfg.x or 0.5, y, width, height, 'panel', math.floor(alpha * 0.82))
                UI.fill((cfg.x or 0.5) - width * 0.5, y, 0.0022, height,
                    TOAST_ACCENT[toast.kind] or 'accent', alpha)

                UI.text(toast.message, cfg.x or 0.5, y - 0.0125, {
                    scale = 0.34,
                    align = 'centre',
                    alpha = alpha,
                })

                y = y + height + 0.008
            end

            Wait(0)
        end

        toastLoopRunning = false
    end)
end

--- Queue a toast. Called by Compat.notify when no provider took the message, and directly by
--- the server through the `vsport:client:Toast` event.
function UI.toast(message, kind, durationMs)
    if type(message) ~= 'string' or message == '' then return end

    toasts[#toasts + 1] = {
        message = message,
        kind = kind or 'primary',
        expires = GetGameTimer() + (tonumber(durationMs) or Config.UI.toast.durationMs or 3500),
    }

    -- Drop the oldest rather than growing without bound if something spams notifications.
    local limit = (Config.UI.toast.maxStacked or 3) * 2
    while #toasts > limit do
        table.remove(toasts, 1)
    end

    runToastLoop()
end

RegisterNetEvent('vsport:client:Toast', function(message, kind, duration)
    UI.toast(message, kind, duration)
end)
