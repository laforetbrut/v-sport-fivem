--[[
    client/minigame.lua

    The rhythm QTE, and the HUD it draws.

    ---------------------------------------------------------------------------------------
    HOW ONE SESSION PLAYS
    ---------------------------------------------------------------------------------------

    A session is a number of REPS. Each rep is a short sequence of randomly chosen keys, asked
    for one at a time. Each key gets a bar that fills left to right and two bands drawn on it:

        pressed inside the PERFECT band      scores 1.0
        pressed inside the GOOD band         scores Config.Minigame.goodScore
        pressed outside either, or wrong key scores 0 and counts as a miss
        never pressed before the bar fills   scores 0 and counts as a miss

    A rep with no misses adds to a streak multiplier. `maxMisses` consecutive misses ends the
    session early, and the player keeps what the completed reps were worth.

    ---------------------------------------------------------------------------------------
    THE ONE PER-FRAME LOOP IN THE RESOURCE
    ---------------------------------------------------------------------------------------

    This is it. A QTE that has to judge a press against a 200ms band cannot run at 250ms, so
    this file - and only this file - runs at Wait(0), for the couple of minutes a workout
    lasts, for the one player doing it. Everything else in the resource is on a timer
    precisely so that this can afford not to be.
]]

Minigame = {}

-- Controls held down for the duration of a session, so pressing W to hit a prompt does not
-- also walk the player off the bench. Read back with IsDisabledControlJustPressed.
local DISABLED = {
    30, 31,                     -- move left/right, up/down (the analogue pair)
    21,                         -- sprint
    24, 25,                     -- attack, aim
    47, 58,                     -- weapon, holster
    140, 141, 142,              -- melee light, heavy, alternate
    257, 263, 264,              -- attack2 and the melee combo inputs
    75,                         -- exit vehicle
    23,                         -- enter vehicle
    36,                         -- duck
    44,                         -- cover
    73,                         -- clear ped tasks, which would cancel the animation
}

-- Judgement, kept between frames so the flash outlives the frame it happened on.
local judgement = { text = nil, colour = 'text', until_ = 0 }

local function judge(text, colour)
    if not Config.UI.workout.showJudgement then return end
    judgement.text = text
    judgement.colour = colour
    judgement.until_ = GetGameTimer() + (tonumber(Config.UI.workout.judgementMs) or 550)
end

-- ---------------------------------------------------------------------------------------
-- Sequences
-- ---------------------------------------------------------------------------------------

--- Pick `count` keys from the pool. `noRepeats` stops the same key appearing twice in a row,
--- because two identical boxes side by side read as one long press.
local function buildSequence(count)
    local pool = Config.Minigame.keyPool
    if type(pool) ~= 'table' or #pool == 0 then
        -- A pool emptied by a config edit would loop forever below. One safe key beats a
        -- hang, and the warning says why the workout feels odd.
        Sport.warn('Config.Minigame.keyPool is empty; falling back to [E]')
        pool = { { label = 'E', control = 38 } }
    end

    local sequence = {}
    local previous

    for index = 1, count do
        local pick

        if Config.Minigame.noRepeats and #pool > 1 then
            -- Bounded: at most a handful of rerolls, and only when the pool is small.
            local attempts = 0
            repeat
                pick = pool[math.random(#pool)]
                attempts = attempts + 1
            until pick.control ~= previous or attempts >= 8
        else
            pick = pool[math.random(#pool)]
        end

        previous = pick.control
        -- The letter comes from the layout, not from the control: the same physical key is
        -- `A` on QWERTY and `Q` on AZERTY.
        sequence[index] = {
            label = UI.poolLabel(pick),
            control = pick.control,
            state = 'idle',
        }
    end

    return sequence
end

-- ---------------------------------------------------------------------------------------
-- The HUD
-- ---------------------------------------------------------------------------------------

--[[
    Draw the workout panel.

    ---------------------------------------------------------------------------------------
    THE HEIGHT IS MEASURED, NOT GUESSED
    ---------------------------------------------------------------------------------------

    The first version of this function drew its rows with a running cursor and took the panel
    height from a hand-written constant, and the two did not agree: the content came to about
    0.168 of the screen against a panel of 0.115, so the form bar and the "hold to stop" hint
    were painted BELOW the black box, floating on the game.

    So the row heights are named constants now, the panel height is their sum, and adding or
    hiding a row changes both at once. A row that is switched off in the config costs no space.
]]

-- Vertical budget, in fractions of screen height, before Config.UI.scale is applied.
local PAD_TOP      = 0.015
local PAD_BOTTOM   = 0.013
local ROW_HEADER   = 0.021      -- exercise name and rep counter
local ROW_RULE     = 0.014      -- the separator under the header
local BOX_HEIGHT   = 0.042      -- a key box
local GAP_AFTER_KEYS = 0.013
local ROW_TIMING   = 0.008      -- the timing bar itself
local GAP_AFTER_TIMING = 0.015
local ROW_FORM     = 0.016      -- the form bar and its percentage
local ROW_FOOTER   = 0.015      -- the cancel hint and the streak

local function draw(view)
    local cfg = Config.UI.workout
    local scale = UI.scale()

    local x = tonumber(cfg.x) or 0.5
    local y = tonumber(cfg.y) or 0.82
    local compact = cfg.compact == true

    -- Which rows are actually drawn. Compact keeps only what the QTE cannot work without.
    local showHeader = not compact and (cfg.showExerciseName or cfg.showRepCounter)
    local showForm = not compact and cfg.showQualityBar
    local showFooter = not compact

    local width = (compact and 0.20 or 0.26) * scale

    local height = PAD_TOP + PAD_BOTTOM
        + (showHeader and (ROW_HEADER + ROW_RULE) or 0)
        + BOX_HEIGHT + GAP_AFTER_KEYS
        + ROW_TIMING + GAP_AFTER_TIMING
        + (showForm and ROW_FORM or 0)
        + (showFooter and ROW_FOOTER or 0)
    height = height * scale

    UI.panel(x, y, width, height, 'panel', 'panelEdge')

    local top = y - height * 0.5
    local cursor = top + PAD_TOP * scale

    -- --- Header -----------------------------------------------------------------------
    if showHeader then
        if cfg.showExerciseName then
            UI.text(view.label, x - width * 0.5 + 0.012, cursor - 0.010 * scale, {
                scale = 0.34,
                colour = 'text',
            })
        end

        if cfg.showRepCounter then
            UI.text(L('session.rep', view.rep, view.reps),
                x + width * 0.5 - 0.012, cursor - 0.010 * scale, {
                    scale = 0.32,
                    colour = 'textDim',
                    align = 'right',
                })
        end

        cursor = cursor + ROW_HEADER * scale
        UI.line(x, cursor, width - 0.024, 'panelEdge', 0.0012)
        cursor = cursor + ROW_RULE * scale
    end

    -- --- Key row ----------------------------------------------------------------------
    local boxHeight = BOX_HEIGHT * scale
    local gap = 0.008 * scale
    local boxWidth = UI.square(boxHeight)

    local total = #view.sequence * boxWidth + (#view.sequence - 1) * gap
    local keyY = cursor + boxHeight * 0.5
    local keyX = x - total * 0.5 + boxWidth * 0.5

    for index = 1, #view.sequence do
        local key = view.sequence[index]
        UI.keyBox(keyX, keyY, boxHeight, key.label, key.state)
        keyX = keyX + boxWidth + gap
    end

    cursor = cursor + boxHeight + GAP_AFTER_KEYS * scale

    -- --- Timing bar -------------------------------------------------------------------
    if view.showTiming then
        UI.timingBar(x, cursor, width - 0.030, ROW_TIMING * scale,
            view.progress, view.goodZone, view.perfectZone)
    else
        -- The rest between reps. Same footprint so the panel does not jump.
        UI.bar(x, cursor, width - 0.030, ROW_TIMING * scale, view.restProgress or 0.0,
            'barTrack', 'panelEdge')
    end

    cursor = cursor + GAP_AFTER_TIMING * scale

    -- --- Form bar ---------------------------------------------------------------------
    if showForm then
        local quality = Sport.clamp(view.quality, 0.0, 1.0, 0.0)

        UI.text(L('session.quality'), x - width * 0.5 + 0.012, cursor - 0.009 * scale, {
            scale = 0.27,
            colour = 'textDim',
        })

        -- The bar shifts from the miss colour to the perfect colour as form improves, so a
        -- player reads their run without having to read a number.
        local r, g, b, a = UI.mix('judgeMiss', 'judgePerfect', quality)

        UI.bar(x + 0.026, cursor, width - 0.078, 0.007 * scale, quality,
            'barTrack', nil, { r, g, b, a })

        UI.text(('%d%%'):format(math.floor(quality * 100 + 0.5)),
            x + width * 0.5 - 0.012, cursor - 0.009 * scale, {
                scale = 0.27,
                colour = 'textDim',
                align = 'right',
            })

        cursor = cursor + ROW_FORM * scale
    end

    -- --- Footer -----------------------------------------------------------------------
    if showFooter then
        UI.text(L('session.cancel', view.cancelLabel), x - width * 0.5 + 0.012,
            cursor - 0.009 * scale, {
                scale = 0.26,
                colour = 'textDim',
            })

        if view.streak > 1.001 then
            UI.text(L('session.streak', view.streak), x + width * 0.5 - 0.012,
                cursor - 0.009 * scale, {
                    scale = 0.26,
                    colour = 'judgePerfect',
                    align = 'right',
                })
        end
    end

    -- --- Judgement flash --------------------------------------------------------------
    if judgement.text and GetGameTimer() < judgement.until_ then
        UI.text(judgement.text, x, top - 0.040 * scale, {
            scale = 0.62,
            font = 4,
            colour = judgement.colour,
            align = 'centre',
            outline = true,
        })
    end

    -- --- Live gains -------------------------------------------------------------------
    if not compact and cfg.showStatGains and view.gainText then
        UI.text(view.gainText, x, y + height * 0.5 + 0.008, {
            scale = 0.30,
            colour = 'judgePerfect',
            align = 'centre',
        })
    end
end

-- ---------------------------------------------------------------------------------------
-- Input
-- ---------------------------------------------------------------------------------------

local function holdDisabled()
    for index = 1, #DISABLED do
        DisableControlAction(0, DISABLED[index], true)
    end

    for _, key in ipairs(Config.Minigame.keyPool) do
        DisableControlAction(0, key.control, true)
    end

    DisableControlAction(0, Config.Minigame.cancelKey or 177, true)
end

--- Which pool key was pressed this frame, or nil. Returns the control so the caller can
--- compare it against the one it wanted rather than against a label.
local function pressedControl()
    for _, key in ipairs(Config.Minigame.keyPool) do
        if IsDisabledControlJustPressed(0, key.control) then
            return key.control
        end
    end
    return nil
end

--- The label for the cancel key. The configured name wins, because the game answers `b_1004`
--- for BACKSPACE and "hold [b_1004] to stop" is not a hint.
local function cancelLabel()
    local configured = Config.Minigame.cancelLabel
    if type(configured) == 'string' and configured ~= '' then return configured end

    return UI.keyLabel(Config.Minigame.cancelKey or 177, 'BACKSPACE')
end

-- ---------------------------------------------------------------------------------------
-- Run
-- ---------------------------------------------------------------------------------------

--[[
    Run a full session and return what happened.

    Blocking: the caller runs it inside its own thread and gets the result when the workout
    is over. Returns a table:

        status      'complete' | 'cancelled' | 'failed'
        quality     0.0 .. 1.0, what the gains are multiplied by
        reps        reps actually finished
        misses      total misses, for the console log
        perfects    perfect presses, for the console log

    `shouldStop` is called every frame; returning true aborts the session as 'cancelled'.
    That is how an external block, a death or a vehicle entry stops a workout mid-rep.
]]
function Minigame.run(options)
    local entry = options.entry
    local difficulty = Equipment.difficulty(entry)
    local reps = Equipment.reps(entry)

    local goodScore = Sport.clamp(Config.Minigame.goodScore, 0.0, 1.0, 0.55)
    local maxMisses = math.floor(tonumber(Config.Minigame.maxMisses) or 0)
    local cancelKey = Config.Minigame.cancelKey or 177
    local cancelHold = math.max(0, tonumber(Config.Minigame.cancelHold) or 400)
    local sounds = Config.Minigame.sounds

    local view = {
        label = options.label or '',
        reps = reps,
        rep = 1,
        sequence = {},
        progress = 0.0,
        restProgress = 0.0,
        showTiming = true,
        quality = 0.0,
        streak = 1.0,
        goodZone = difficulty.goodZone,
        perfectZone = difficulty.perfectZone,
        cancelLabel = cancelLabel(),
        gainText = options.gainText,
    }

    local scored, scoreTotal = 0, 0.0
    local misses, perfects = 0, 0
    local consecutiveMisses = 0
    local repsDone = 0
    local streak = 1.0
    local cancelHeldSince = nil
    local status = 'complete'

    judgement.text = nil

    local function currentQuality()
        if scored == 0 then return 0.0 end
        return Sport.clamp((scoreTotal / scored) * streak, 0.0, 1.0, 0.0)
    end

    --- One frame of upkeep shared by both loops below. Returns false when the session should
    --- stop, which the caller turns into the right status.
    local function frame()
        holdDisabled()
        view.quality = currentQuality()
        draw(view)

        if options.shouldStop and options.shouldStop() then
            status = 'cancelled'
            return false
        end

        if IsDisabledControlPressed(0, cancelKey) then
            cancelHeldSince = cancelHeldSince or GetGameTimer()
            if GetGameTimer() - cancelHeldSince >= cancelHold then
                status = 'cancelled'
                return false
            end
        else
            cancelHeldSince = nil
        end

        return true
    end

    for rep = 1, reps do
        view.rep = rep
        view.sequence = buildSequence(math.random(difficulty.keys[1], difficulty.keys[2]))
        view.showTiming = true

        local repMissed = false

        for index = 1, #view.sequence do
            local key = view.sequence[index]
            key.state = 'active'

            local started = GetGameTimer()
            local window = difficulty.window
            local resolved = false

            while not resolved do
                local elapsed = GetGameTimer() - started
                view.progress = elapsed / window

                if not frame() then return {
                    status = status, quality = currentQuality(), reps = repsDone,
                    misses = misses, perfects = perfects,
                } end

                local pressed = pressedControl()

                if pressed then
                    local at = elapsed / window
                    local score, text, colour, cue

                    if Config.Debug.autoPerfect then
                        score, text, colour = 1.0, L('session.perfect'), 'judgePerfect'
                        cue = sounds.perfect
                    elseif pressed ~= key.control then
                        score, text, colour = 0.0, L('session.miss'), 'judgeMiss'
                        cue = sounds.miss
                    elseif at >= difficulty.perfectZone[1] and at <= difficulty.perfectZone[2] then
                        score, text, colour = 1.0, L('session.perfect'), 'judgePerfect'
                        cue = sounds.perfect
                    elseif at >= difficulty.goodZone[1] and at <= difficulty.goodZone[2] then
                        score, text, colour = goodScore, L('session.good'), 'judgeGood'
                        cue = sounds.good
                    else
                        score, text, colour = 0.0, L('session.miss'), 'judgeMiss'
                        cue = sounds.miss
                    end

                    key.state = score > 0 and 'hit' or 'miss'
                    scored = scored + 1
                    scoreTotal = scoreTotal + score

                    if score >= 1.0 then perfects = perfects + 1 end

                    if score <= 0.0 then
                        misses = misses + 1
                        consecutiveMisses = consecutiveMisses + 1
                        repMissed = true
                        streak = 1.0
                    else
                        consecutiveMisses = 0
                    end

                    judge(text, colour)
                    if cue then Compat.playSound(cue.name, cue.set) end

                    resolved = true

                elseif elapsed >= window then
                    -- Never pressed. Same as a miss, and the commonest one.
                    key.state = 'miss'
                    scored = scored + 1
                    misses = misses + 1
                    consecutiveMisses = consecutiveMisses + 1
                    repMissed = true
                    streak = 1.0

                    judge(L('session.miss'), 'judgeMiss')
                    if sounds.miss then Compat.playSound(sounds.miss.name, sounds.miss.set) end

                    resolved = true
                end

                if not resolved then Wait(0) end
            end

            if maxMisses > 0 and consecutiveMisses >= maxMisses then
                if sounds.fail then Compat.playSound(sounds.fail.name, sounds.fail.set) end
                return {
                    status = 'failed', quality = currentQuality(), reps = repsDone,
                    misses = misses, perfects = perfects,
                }
            end

            -- A short beat with the resolved box still coloured, so the player sees whether
            -- they hit it before the next one lights up.
            local settle = GetGameTimer() + 110
            while GetGameTimer() < settle do
                if not frame() then return {
                    status = status, quality = currentQuality(), reps = repsDone,
                    misses = misses, perfects = perfects,
                } end
                Wait(0)
            end
        end

        repsDone = repsDone + 1

        if not repMissed then
            streak = math.min(
                streak + (tonumber(Config.Minigame.streakPerRep) or 0.04),
                tonumber(Config.Minigame.streakMax) or 1.20)
        end
        view.streak = streak

        -- --- Rest ---------------------------------------------------------------------
        if rep < reps and difficulty.restBetween > 0 then
            view.showTiming = false
            for _, key in ipairs(view.sequence) do key.state = 'idle' end

            local restStarted = GetGameTimer()
            while GetGameTimer() - restStarted < difficulty.restBetween do
                view.restProgress = (GetGameTimer() - restStarted) / difficulty.restBetween

                if not frame() then return {
                    status = status, quality = currentQuality(), reps = repsDone,
                    misses = misses, perfects = perfects,
                } end

                Wait(0)
            end

            view.restProgress = 0.0
        end
    end

    if sounds.finish then Compat.playSound(sounds.finish.name, sounds.finish.set) end

    return {
        status = 'complete',
        quality = currentQuality(),
        reps = repsDone,
        misses = misses,
        perfects = perfects,
    }
end

--- The shortest a session can physically take, in milliseconds. Lives in
--- shared/equipment.lua so the server's "that arrived too fast" check reads the identical
--- implementation; re-exported here because this is where a reader looks for it.
Minigame.minimumDuration = Equipment.minimumDurationMs
