--[[
    client/menu.lua

    The stats panel, drawn with the same natives as everything else.

    It is a READOUT, not a menu: there is nothing to select and no cursor to release, which
    is the whole reason it can be a hundred lines of DrawRect instead of an HTML page. It
    opens, it shows the player where they are, and any key closes it.

    The draw loop exists only while the panel is open.
]]

Menu = {}

local open = false

--- Whether the panel is on screen.
function Menu.isOpen()
    return open
end

-- ---------------------------------------------------------------------------------------
-- The effects list
-- ---------------------------------------------------------------------------------------

--[[
    What the player's current stats are actually granting, as { label, value } rows.

    Built from the same Stats.bonus the natives are driven by, so this cannot drift from
    reality: if the panel says +18% melee damage, that is the number that was written.

    A bonus at its vanilla value is omitted. "Melee damage +0%" is noise.
]]
local function effectRows()
    local rows = {}

    if not Config.Effects.enabled then
        rows[#rows + 1] = { label = L('panel.effect_none'), value = '' }
        return rows
    end

    local cfg = Config.Effects

    --- A multiplier shown as a percentage above vanilla. Skipped when it rounds to nothing.
    local function multiplier(statKey, bonus, label)
        local value = Stats.bonus(statKey, bonus, State.get(statKey))
        if not value then return end

        local percent = (value - 1.0) * 100.0
        if math.abs(percent) < 0.5 then return end

        rows[#rows + 1] = { label = label, value = L('panel.percent', percent) }
    end

    multiplier('strength', (cfg.strength or {}).meleeDamage, L('panel.effect_melee'))
    multiplier('strength', (cfg.strength or {}).meleeDefense, L('panel.effect_defense'))

    -- Underwater time is an absolute, not a multiplier, so it is shown as seconds.
    local underwater = Stats.bonus('breath', (cfg.breath or {}).underwaterTime, State.get('breath'))
    if underwater then
        rows[#rows + 1] = {
            label = L('panel.effect_underwater'),
            value = L('panel.seconds', underwater),
        }
    end

    multiplier('breath', (cfg.breath or {}).swimSpeed, L('panel.effect_swim'))
    multiplier('stamina', (cfg.stamina or {}).sprintSpeed, L('panel.effect_sprint'))
    multiplier('stamina', (cfg.stamina or {}).healthRecharge, L('panel.effect_regen'))

    local maxHealth = Stats.bonus('strength', (cfg.strength or {}).maxHealth, State.get('strength'))
    if maxHealth then
        rows[#rows + 1] = {
            label = L('panel.effect_health'),
            value = ('%d'):format(math.floor(maxHealth)),
        }
    end

    local recovery = Stats.bonus('stamina', (cfg.stamina or {}).recovery, State.get('stamina'))
    if recovery and recovery > 0.001 then
        rows[#rows + 1] = {
            label = L('panel.effect_recovery'),
            value = ('+%.0f%%/s'):format(recovery * 100),
        }
    end

    return rows
end

-- ---------------------------------------------------------------------------------------
-- Drawing
-- ---------------------------------------------------------------------------------------

local ROW_HEIGHT = 0.052
local EFFECT_ROW = 0.021

local function draw(closeName)
    local cfg = Config.UI.panel
    local scale = UI.scale()

    local statKeys = Stats.keys()
    local effects = cfg.showEffects and effectRows() or {}
    local showAllowance = Config.Allowance.enabled and Config.Allowance.showInPanel

    local width = (tonumber(cfg.width) or 0.30) * scale
    local x = tonumber(cfg.x) or 0.5

    -- Height is measured rather than fixed, so adding a fourth stat in the config makes the
    -- panel taller instead of overflowing it.
    local height = 0.052                                        -- header
        + #statKeys * ROW_HEIGHT * scale
        + (showAllowance and 0.050 * scale or 0)
        + (#effects > 0 and (0.026 + #effects * EFFECT_ROW * scale) or 0)
        + 0.040                                                 -- footer

    local y = tonumber(cfg.y) or 0.5
    local top = y - height * 0.5

    UI.panel(x, y, width, height, 'panel', 'panelEdge')

    local left = x - width * 0.5 + 0.014
    local right = x + width * 0.5 - 0.014
    local cursor = top + 0.018

    -- --- Header -----------------------------------------------------------------------
    UI.text(L('panel.title'), left, cursor - 0.012, { scale = 0.40, colour = 'text' })

    if cfg.showSessionCount then
        UI.text(L('panel.total_sessions', State.totalSessions), right, cursor - 0.009, {
            scale = 0.28, colour = 'textDim', align = 'right',
        })
    end

    cursor = cursor + 0.016
    UI.line(x, cursor, width - 0.028, 'accent', 0.0018)
    cursor = cursor + 0.018

    -- --- Stats ------------------------------------------------------------------------
    local now = Sport.now()

    for _, key in ipairs(statKeys) do
        local def = Stats.def(key)
        local trained = State.raw(key)
        local buff = State.buffTotal(key)
        local max = def.max or 100.0

        -- Name and value.
        UI.text(L(def.label), left, cursor - 0.011, { scale = 0.33, colour = 'text' })

        UI.text(('%.1f%%'):format(trained), right, cursor - 0.011, {
            scale = 0.33, colour = 'text', align = 'right',
        })

        cursor = cursor + 0.017

        -- The bar, in the stat's own colour.
        local colour = def.colour or { 255, 255, 255 }
        UI.bar(x, cursor, width - 0.028, 0.009 * scale, trained / max, 'barTrack', nil,
            { colour[1], colour[2], colour[3], 255 })

        -- An active buff is drawn as a lighter overlay past the trained value, so a player
        -- can see at a glance which part of their strength they actually earned.
        if math.abs(buff) > 0.05 then
            local barWidth = width - 0.028
            local from = Sport.clamp(trained / max, 0.0, 1.0, 0.0)
            local to = Sport.clamp((trained + buff) / max, 0.0, 1.0, 0.0)
            local segmentFrom, segmentTo = math.min(from, to), math.max(from, to)
            local segmentWidth = barWidth * (segmentTo - segmentFrom)

            if segmentWidth > 0.0005 then
                UI.rect(x - barWidth * 0.5 + barWidth * segmentFrom + segmentWidth * 0.5,
                    cursor, segmentWidth, 0.009 * scale,
                    255, 255, 255, buff > 0 and 130 or 60)
            end
        end

        cursor = cursor + 0.014

        -- The line underneath: what is happening to this stat.
        local note
        if math.abs(buff) > 0.05 then
            note = L('panel.buffed', buff)
        elseif State.decayPaused then
            note = L('panel.decay_paused')
        elseif cfg.showNextDecay then
            local left_ = Stats.nextDecayIn(key, now, State.lastSession, State.decayAnchor[key])
            local decay = Stats.decayConfig(key)

            if left_ and decay.amount > 0 and trained > decay.floor then
                note = L('panel.next_decay', decay.amount, Sport.duration(left_))
            else
                note = L('panel.no_decay')
            end
        end

        if note then
            UI.text(note, left, cursor - 0.009, { scale = 0.26, colour = 'textDim' })
        end

        UI.text(L(def.description), right, cursor - 0.009, {
            scale = 0.24, colour = 'textDim', align = 'right',
        })

        cursor = cursor + 0.021 * scale
    end

    -- --- Allowance --------------------------------------------------------------------
    --
    -- The recovery mechanic, made visible. A player who cannot see how much of their cycle
    -- is left concludes the resource is broken the first time a session pays nothing.
    if showAllowance then
        cursor = cursor + 0.004
        UI.line(x, cursor, width - 0.028, 'panelEdge', 0.0012)
        cursor = cursor + 0.016

        local total = tonumber(Config.Allowance.total) or 0
        local spent = tonumber(State.allowanceSpent.total) or 0
        local remaining = math.max(0.0, total - spent)
        local exhausted = State.allowanceExhausted()

        UI.text(L('panel.allowance'), left, cursor - 0.009, {
            scale = 0.27,
            colour = exhausted and 'judgeMiss' or 'accent',
        })

        if total > 0 then
            UI.text(L('allowance.remaining', remaining, total), right, cursor - 0.009, {
                scale = 0.26,
                colour = exhausted and 'judgeMiss' or 'textDim',
                align = 'right',
            })
        end

        cursor = cursor + 0.015

        -- The bar drains rather than fills: it is what is LEFT, not what was spent, which is
        -- the number a player is actually asking about.
        if total > 0 then
            local fraction = Sport.clamp(remaining / total, 0.0, 1.0, 0.0)
            local r, g, b, a = UI.mix('judgeMiss', 'judgePerfect', fraction)
            UI.bar(x, cursor, width - 0.028, 0.007 * scale, fraction, 'barTrack', nil,
                { r, g, b, a })
            cursor = cursor + 0.013
        end

        if State.allowanceResetsIn and State.allowanceResetsIn > 0 then
            UI.text(L('allowance.resets_in', Sport.duration(State.allowanceResetsIn)),
                left, cursor - 0.008, { scale = 0.25, colour = 'textDim' })
        end

        -- Say so when whey is in effect: a player who paid for it should see it working.
        if State.allowanceWindow and Config.Allowance.window
            and State.allowanceWindow < Config.Allowance.window then
            UI.text(L('allowance.reduced', Sport.duration(State.allowanceWindow)),
                right, cursor - 0.008, {
                    scale = 0.25, colour = 'judgePerfect', align = 'right',
                })
        end

        cursor = cursor + 0.014
    end

    -- --- Effects ----------------------------------------------------------------------
    if #effects > 0 then
        cursor = cursor + 0.004
        UI.line(x, cursor, width - 0.028, 'panelEdge', 0.0012)
        cursor = cursor + 0.016

        UI.text(L('panel.effects'), left, cursor - 0.009, { scale = 0.27, colour = 'accent' })
        cursor = cursor + 0.018

        for _, row in ipairs(effects) do
            UI.text(row.label, left, cursor - 0.008, { scale = 0.26, colour = 'textDim' })
            UI.text(row.value, right, cursor - 0.008, {
                scale = 0.26, colour = 'text', align = 'right',
            })
            cursor = cursor + EFFECT_ROW * scale
        end
    end

    -- --- Footer -----------------------------------------------------------------------
    cursor = top + height - 0.020

    local fatigue = Stats.fatigue(State.recentSessions, 0)
    if fatigue < 0.995 then
        UI.text(L('panel.fatigue', math.floor(fatigue * 100 + 0.5)), left, cursor - 0.009, {
            scale = 0.26, colour = 'judgeGood',
        })
    else
        UI.text(L('panel.rested'), left, cursor - 0.009, { scale = 0.26, colour = 'textDim' })
    end

    UI.text(L('panel.close', closeName), right, cursor - 0.009, {
        scale = 0.26, colour = 'textDim', align = 'right',
    })

    -- The attribution the licence asks for. Translate it, recolour it, put your own credits
    -- beside it - but see LICENSE before removing it.
    UI.text('v-sport  ·  vyrriox', x, cursor - 0.009, {
        scale = 0.24, colour = 'textDim', align = 'centre',
    })
end

-- ---------------------------------------------------------------------------------------
-- Open and close
-- ---------------------------------------------------------------------------------------

function Menu.close()
    open = false
end

function Menu.open()
    if open then return end
    if Session.active() then return end

    if not State.ready then
        Compat.notify(L('panel.empty'), 'error')
        return
    end

    open = true

    CreateThread(function()
        local closeKeys = Config.UI.panel.closeKeys or { 177, 200 }

        --[[
            UI.keyLabel, NOT the raw glyph lookup.

            This panel kept its own copy of the old approach - ask
            GetControlInstructionalButton, strip a leading `t_` - and that native answers with an
            internal token for a good number of controls. BACKSPACE comes back as `b_1004`, so the
            footer read "[b_1004] Fermer".

            The same bug was fixed for the workout HUD and the prompts and missed here, which is
            the argument for having one helper rather than three copies of two lines.
        ]]
        local closeName = UI.keyLabel(closeKeys[1] or 177, 'ESC')

        -- A grace period so the key that opened the panel does not immediately close it.
        local ignoreUntil = GetGameTimer() + 250

        while open do
            draw(closeName)

            if GetGameTimer() >= ignoreUntil then
                for _, control in ipairs(closeKeys) do
                    if IsControlJustReleased(0, control) then
                        open = false
                        break
                    end
                end
            end

            -- Anything that makes a full-screen readout wrong.
            if IsPauseMenuActive() or Session.active() or IsEntityDead(PlayerPedId()) then
                open = false
            end

            Wait(0)
        end
    end)
end

function Menu.toggle()
    if open then
        Menu.close()
    else
        Menu.open()
    end
end

-- ---------------------------------------------------------------------------------------
-- Key binding
-- ---------------------------------------------------------------------------------------
--
-- Registered only when the operator named a key. RegisterKeyMapping with an empty default is
-- a permanent entry in the player's control settings for a binding that does nothing, which
-- is worse than not offering one.

CreateThread(function()
    local key = Config.UI.panel.openKey
    if type(key) ~= 'string' or key == '' then return end

    RegisterCommand('vsport:togglepanel', function()
        Menu.toggle()
    end, false)

    RegisterKeyMapping('vsport:togglepanel', L('cmd.stats'), 'keyboard', key)
end)
