--[[
    ===========================================================================================
    v-sport / shared/equipment.lua
    ===========================================================================================

    THE EQUIPMENT CATALOGUE. This is a configuration file; it lives in `shared/` only because
    both sides read it. Edit it freely.

    Each entry maps a set of prop models onto one exercise, and says what that exercise trains.

    -------------------------------------------------------------------------------------------
    FIELDS
    -------------------------------------------------------------------------------------------

      order         Sort position in menus and in /sportinfo. Low first.
      label         Locale key, or plain text if you would rather not translate it.
      description   Locale key for the line under the name.

      models        Prop model names. Hashed once at load into a lookup table.

                    A NAME THAT DOES NOT EXIST IN YOUR GAME COSTS NOTHING. It hashes to a
                    number no entity will ever carry, so it simply never matches. That is why
                    the lists below are generous and include several spellings of the same
                    idea: over-listing is free, under-listing means a prop nobody can use.

                    A raw hash works too, for a model whose name you do not know:
                        models = { 1234567890 }

      gains         What one PERFECT session is worth, expressed in SESSIONS of that stat.
                    { strength = 1.0 } is one full session, so with the default
                    sessionsToMax = 100 it is one point. { strength = 0.5, stamina = 0.5 }
                    trains both at half rate. The totals do not have to add up to 1.0 - a
                    piece of equipment that is simply better can be worth more, and a lazy
                    one less.

      reps          How many repetitions a session asks for. More reps is a longer session
                    and more chances to miss, not a bigger reward: the reward is `gains`.

      difficulty    A key from Config.Minigame.difficulties.
      minigame      Optional per-equipment overrides of that preset, same shape.

      cooldown      Seconds before the same player may use this equipment again. Defaults to
                    Config.Security.defaultCooldown.

      scenario      A GTA scenario name.
      anim          { dict, clip, flag }.

      preferScenario  Which of the two is tried FIRST, and it matters more than it sounds.

                    AN ANIMATION NEVER CARRIES A PROP. TaskPlayAnim moves the skeleton and
                    nothing else, so an exercise driven by an animation has EMPTY HANDS however
                    good the animation is. Only a scenario spawns and holds a prop.

                    So every exercise where the player should be holding something - the
                    weights, the racks, the bar, the bench - sets `preferScenario = true`, and
                    the ones that need nothing in their hands (push-ups, yoga, jogging) prefer
                    the animation, because the animations are more varied.

                    The PREFIX of the scenario name then decides how it is started:
                      PROP_*   placed on the prop with TaskStartScenarioAtPosition, so the
                               body and the bench line up
                      WORLD_*  played where the ped is standing, which is where the offset put
                               them

                    Whichever is tried first, the other is the fallback, and if both fail the
                    session still runs - the minigame is the workout, the animation is dressing.

      scenarioHeading  Degrees added to the prop's heading for a PROP_ scenario. If a bench
                    faces backwards on your map, 180.0 here is the whole fix.

      props         Props to create and attach OURSELVES, for an exercise where neither a
                    scenario nor an animation provides one:

                        props = {
                            { model = 'prop_barbell_01', bone = 57005,
                              pos = vector3(0.0, 0.0, 0.0), rot = vector3(0.0, 0.0, 0.0) },
                        }

                    Bone 57005 is the right prop hand, 36029 the left. Skipped entirely when a
                    scenario already brought a prop, so there is never a second dumbbell.
                    Deleted on cleanup along with everything else.

                    `centre = true` puts the model's MIDDLE on the bone instead of its origin.
                    For a long object whose origin is at one end, which is most of them.

                    `twoHanded = true` FOR ANYTHING THAT NEEDS BOTH HANDS, and it takes no other
                    field - no pos, no rot, no bone:

                        props = { { model = 'prop_barbell_01', twoHanded = true } }

                    The bar is not attached. It is placed every frame across both hand bones:
                    the midpoint between them, the heading from one to the other, the pitch from
                    the height between them, and the model's longest axis turned onto that line,
                    read from its own bounding box.

                    All of it is derived, because none of it CAN be configured: a bar attached to
                    one hand inherits that hand's tilt, and no single offset is right for two
                    hands that move independently. `rotOffset` is an escape hatch for odd
                    geometry and should stay at zero.

      offset        vector3, in the PROP's local space, where the player is placed.
                    Positive Y is in front of the prop, positive Z is above it - which is how
                    a player ends up ON a machine rather than beside it.
                    nil leaves the player where they are.
      heading       Degrees added to the prop's own heading for the player to face.
                    nil keeps the player's heading.
      snap          Whether to actually move the player to `offset`. false uses the offset
                    only to decide which side of the prop the prompt appears on.

      modelOverrides  Per-model positioning, for when one exercise covers props of different
                    shapes. A squat rack is approached from the front and a flat bench from
                    the side, and no single offset is right for both.

                        modelOverrides = {
                            ['prop_weight_squat'] = {
                                offset = vector3(0.0, 0.55, 0.0), heading = 180.0,
                            },
                        }

                    Any of `offset`, `heading`, `snap`, `anim`, `scenario` and `hideProp` can
                    be overridden. Everything else comes from the entry.

                    GETTING THESE RIGHT IS A TWO-MINUTE JOB IN GAME, not a guess: stand where
                    the player should be, face the prop, and run /vsportoffset. It prints the
                    exact block to paste.

      hideProp      Hide the world prop while it is in use. For hand-held equipment - a
                    barbell lying on the floor should not still be lying there while the
                    player is lifting one.

      trains        Optional. Restrict which stats this equipment may raise past a value,
                    e.g. `trains = { strength = 60 }` makes a home dumbbell useless above 60
                    strength and pushes players towards a real gym. nil is no ceiling.

      require       Optional gate. { stats = { strength = 40 }, job = 'police',
                    item = 'gymmembership' }. An unmet requirement shows the reason.

      inPlace       Do not move or attach the player: play the animation where they stand, turned
                    to face the equipment. For anything you pick UP rather than get ON - a dumbbell,
                    a barbell on the floor. Skips `offset`, `heading`, `snap`, `placeAnim` and
                    `animOffset` entirely, which is the point: there is no position to measure and
                    therefore none to get wrong. Never use it for a bench or a rack, where being in
                    the right place IS the exercise.

      enabled       false keeps the entry as documentation without registering it.
]]

--[[
    ===============================================================================================
    THE ONE NUMBER TO KNOW BEFORE MEASURING ANY animOffset
    ===============================================================================================

    A body attached to a prop lying on the floor wants animOffset.z = 0.88, ROUGHLY, and it wants it
    for every such prop rather than per model.

    Why: AttachEntityToEntity positions a ped by an origin near its middle, not by its feet, so
    standing a body level with a prop whose own origin is at floor level takes about the distance
    from pelvis to sole. Nine independent measurements across the free_weights entry - two
    dumbbells, a bare bar and six loaded bars - agree on it to within 3 cm wherever nothing hangs
    below the prop's origin.

    What moves it:

      DOWN    anything below the prop's origin. Loaded barbells drop to 0.58 with the largest discs,
              because the plates put the bottom of the bounding box below the bar's axis and the real
              floor with it. The bigger the discs, the lower the figure.

      UP      a prop whose origin is at floor level but whose usable surface is not. A bench seat is
              45 cm up, so a body lying ON it needs that much more.

      OTHER   lying and seated clips are their own case. All four yoga-mat exercises measured 1.03
              from four different clips, so a posture has a constant of its own - measure it once per
              clip family rather than reasoning from the standing figure.

    USE THIS AS A SANITY CHECK, NOT AS A SUBSTITUTE FOR MEASURING. Its real value is catching a
    figure that cannot be right: a bare bar that measures 0.73 is claiming to have plates. That is
    how the one bad number in this file was found, after it had already been written down.

    Any entry whose reference model is an ordinary floor prop should sit near 0.88, and any entry's
    DEFAULT should be the ordinary case rather than an extreme - an unmeasured model inherits it, and
    so does whatever a custom MLO adds tomorrow.
]]

Equipment = {}

--[[
    ===========================================================================================
    WHICH MODELS ARE CONFIRMED, AND WHICH ARE HOPEFUL
    ===========================================================================================

    Names marked CONFIRMED below were read off a real map with /vsportscan. The rest come from
    community model lists and from names common to gym MLOs, and some of them will not exist in
    any given game build - which costs nothing, because a name that does not exist hashes to a
    number no entity will ever carry.

    CONFIRMED - read either off a real map with /vsportscan, or out of a published GTA V model
    dump. These are the ones worth trusting:

        prop_muscle_bench_01 .. _06   the weight benches. SIX of them, not three.
        prop_weight_squat             the squat racks
        prop_barbell_01, _02          bare barbells
        prop_barbell_10kg .. _100kg   barbells with plates on, eight weights
        prop_freeweight_01, _02       dumbbells
        prop_curl_bar_01              a curl bar
        prop_beach_punchbag           a real heavy bag
        prop_beach_bars_01, _02       the bars you hang off
        prop_beach_dip_bars_01, _02   parallel dip bars
        prop_beach_rings_01           gymnastic rings
        prop_exer_bike_01             an exercise bike
        prop_skip_rope_01             a skipping rope
        prop_rolled_yoga_mat          a yoga mat
        prop_bskball_01,              basketball and hoop
          prop_basketball_net
        prop_beach_volball01, 02      volleyballs
        prop_bench_08                 ordinary park benches, all over the map

    Everything NOT in that list is hopeful: names from community lists and from gym MLOs, some of
    which do not exist in any given build. That costs nothing - a name that does not exist hashes
    to a number no entity will ever carry - which is why they are left in.

    RUN /vsportscan ON YOUR OWN MAP. It is the only way to know what your gym has, and it takes
    ten seconds. Anything it marks `-` goes into Config.ExtraEquipment.
]]

--[[
    ===========================================================================================
    ANIMATIONS
    ===========================================================================================

    One animation per exercise, so a treadmill does not look like a bench press.

    EVERY DICTIONARY AND CLIP BELOW IS A REAL ONE, read off published GTA V animation dumps
    rather than guessed. The names are case-sensitive and the clip is often NOT `base` - yoga's
    is `base_a`, and getting that wrong is a silent no-op rather than an error.

    THE ONE WORTH KNOWING ABOUT: `amb@prop_human_seat_muscle_bench_press@base` is a real lying
    bench press. The ped gets ON the bench and presses, which is what the base game does at
    Muscle Beach. Its scenario twin is PROP_HUMAN_SEAT_MUSCLE_BENCH_PRESS. Earlier versions of
    this resource used the standing dumbbell scenario for the bench because nothing better was
    known; this is much better.

    GENDER. Dictionaries containing `@male@` usually have a `@female@` twin. client/session.lua
    swaps it for a female ped and falls back to the male dictionary when there is no twin, so
    there is nothing to configure here.

    THESE ARE THE FALLBACK, NOT ALWAYS THE FIRST CHOICE. An entry with `preferScenario = true`
    tries its scenario first and only lands here if the scenario refuses to start - because a
    scenario is the only thing that puts a prop in the player's hands. Every entry that should
    be holding a weight sets that flag; the ones below that never do are the exercises where
    empty hands are correct.

    An entry in the catalogue may override `anim` itself; this table only fills in the ones that
    do not, which keeps the research in one place instead of spread over twenty entries.
]]

local ANIMS = {
    --[[
        Free weights and racks.

        NOTE THE CLIP ON THE BENCH PRESS: `idle_a`, not `base`.

        The published dump lists clip lengths, and they give the game away:

            amb@prop_human_seat_muscle_bench_press@base     base     1966 ms
            amb@prop_human_seat_muscle_bench_press@idle_a   idle_a   9433 ms

        Every other exercise's `@base` runs for several seconds and is the real movement -
        push-ups 4833, chin-ups 13333, free weights 9500. This one's is under two seconds,
        because it is the SETTLED POSE: lying on the bench holding the bar still. Looping it
        produces a character frozen mid-press, arms locked out, which is exactly what it looked
        like. `idle_a` is the pressing motion.

        A clip length is worth checking whenever an animation looks static rather than assuming
        the clip is wrong.
    ]]
    bench_press    = { dict = 'amb@prop_human_seat_muscle_bench_press@idle_a',      clip = 'idle_a' },
    free_weights   = { dict = 'amb@world_human_muscle_free_weights@male@barbell@base', clip = 'base' },
    weight_rack    = { dict = 'amb@world_human_muscle_free_weights@male@barbell@base', clip = 'base' },
    kettlebell     = { dict = 'amb@world_human_muscle_free_weights@male@barbell@idle_a', clip = 'idle_a' },
    cable_machine  = { dict = 'amb@world_human_muscle_free_weights@male@barbell@base', clip = 'base' },
    battle_ropes   = { dict = 'amb@world_human_muscle_free_weights@male@barbell@idle_a', clip = 'idle_a' },

    -- Bodyweight
    -- These two are the animation halves of PROP_ scenarios and are only ever reached as a
    -- fallback: both entries set `preferScenario`, so the scenario places the ped and brings
    -- the bar. A `prop_` dictionary played in place lies or hangs the ped at whatever heading
    -- they happened to have, holding nothing.
    pull_ups       = { dict = 'amb@prop_human_muscle_chin_ups@male@base',   clip = 'base' },
    dip_bars       = { dict = 'amb@prop_human_muscle_chin_ups@male@idle_a', clip = 'idle_a' },

    -- Bench sit-ups, not dips: a WORLD_ animation that plays correctly anywhere, with no prop
    -- and no dependence on how the bench is turned. A park bench is not a chin-up bar and
    -- borrowing that scenario for one looked exactly as wrong as it sounds.
    park_bench     = { dict = 'amb@world_human_sit_ups@male@base',          clip = 'base' },

    push_ups       = { dict = 'amb@world_human_push_ups@male@base',         clip = 'base' },
    sit_ups        = { dict = 'amb@world_human_sit_ups@male@base',          clip = 'base' },
    muscle_flex    = { dict = 'amb@world_human_muscle_flex@arms_at_side@base', clip = 'base' },

    -- Cardio. Three visibly different jogs, so the treadmill, the bike and the rope are not
    -- the same clip three times.
    treadmill      = { dict = 'amb@world_human_jog_standing@male@fitbase', clip = 'base' },
    exercise_bike  = { dict = 'amb@world_human_jog_standing@male@base',    clip = 'base' },
    skipping_rope  = { dict = 'amb@world_human_jog@male@base',             clip = 'base' },

    -- Ball sports. Standing jog rather than a jump shot: nothing shipped throws a ball, and a
    -- jog reads as "playing" without pretending to be an animation that does not exist.
    basketball     = { dict = 'amb@world_human_jog_standing@female@base', clip = 'base' },
    volleyball     = { dict = 'amb@world_human_jog@female@base',          clip = 'base' },

    -- Machines that are sat at
    -- Both sit at a machine, and both use the sit-up dictionary rather than the bench-press
    -- one: the bench-press clips are PROP_ clips that need a bench placed under them, and a
    -- leg press is not a bench. `idle_a` on the rower so it is not identical to sit-ups.
    -- A duplicated animation that always looks right beats a distinctive one that floats.
    rowing_machine = { dict = 'amb@world_human_sit_ups@male@idle_a', clip = 'idle_a' },
    leg_press      = { dict = 'amb@world_human_sit_ups@male@base',   clip = 'base' },

    -- Breathing. NOTE the clip: yoga's is `base_a`, not `base`.
    yoga           = { dict = 'amb@world_human_yoga@male@base',                 clip = 'base_a' },
    stretching     = { dict = 'amb@world_human_muscle_flex@arms_in_front@base', clip = 'base' },

    --[[
        Combat. AN ACTUAL PUNCH, NOT A STANCE, and the reason this works needs writing down.

        `idle` was here first and it is a fighting STANCE: a player squared up to a bag, bouncing
        slightly, never hitting it. For a bag that is the whole exercise missing.

        `heavy_punch_c` is a real base-game clip in the same dictionary (verified on Pleb Masters
        Forge, not guessed) and it is a single strike of about a second, not a loop. It is used
        anyway, because the placed-animation path LOOPS it - AF_LOOPING is in the flags - and
        because THE PED IS ATTACHED TO THE BAG. The step forward that a one-shot attack clip
        carries, the thing that would normally walk the player across the gym over fourteen reps,
        cannot move an attached ped at all. So the clip replays on the spot and reads as repeated
        punching.

        The speed bag keeps the stance. A heavy hook is the wrong shape for it entirely, and being
        MLO-only there is nothing shipped to test a better choice against.
    ]]
    punching_bag   = { dict = 'melee@unarmed@streamed_core', clip = 'heavy_punch_c' },
    speed_bag      = { dict = 'melee@unarmed@streamed_core', clip = 'idle' },
}

-- ===========================================================================================
-- The catalogue
-- ===========================================================================================

Equipment.catalogue = {

    -- --- Free weights ----------------------------------------------------------------

    bench_press = {
        order = 10,
        label = 'equip.bench_press',
        description = 'equip.bench_press_desc',
        models = {
            -- CONFIRMED: all six weight benches.
            --[[
                TWO OF THESE, NOT SIX, AND THE FAMILY NAME IS A LIE.

                prop_muscle_bench_01 .. _06 reads like six weight benches. Looked at one by one it is
                a mixed bag, and only two of them belong here:

                    _01, _03    flat benches. The _03 is the reference, and the one Muscle Beach
                                actually places - measured against the real thing and correct.
                    _02, _04    INCLINE benches, tipped back 44 degrees. REMOVED, see below.
                    _05         a PULL-UP FRAME. Removed too; it was never a bench.
                    _06         a SEATED machine. It is the leg press, and it is there now.

                WHY _02, _04 AND _05 ARE GONE RATHER THAN FIXED. All three placed a body visibly
                wrong in game, and every attempt to align them failed: four separate lookups - the
                object pool, a raycast, the known-locations search, and the handle from the last
                session - could not reach one, while a target resource trained on them the whole
                time. The only measurements available came from a studio copy, and a studio copy
                cannot know how high the map puts a prop's origin, so those numbers were wrong by
                tens of centimetres and there was no way to take better ones.

                A prop that cannot be measured cannot be placed correctly, and equipment that places
                a body in mid-air is worse than equipment that offers nothing. Same call as the dip
                bars, the street bench and the rolled-up mat.

                They are one line away from returning, for a server that can align them:

                    Config.ExtraEquipment = {
                        bench_press = { models = { 'prop_muscle_bench_01', 'prop_muscle_bench_03',
                                                   'prop_muscle_bench_02', 'prop_muscle_bench_04' } },
                    }
            ]]
            'prop_muscle_bench_01', 'prop_muscle_bench_03',
            --[[
                THE PRISON YARD. Bolingbroke has its own weight bench and its own pull-up bars,
                and neither was in this file - which is why a player could train at Muscle Beach
                and not in the yard, reported as a bug and correct as a report.

                Worth having beyond the prison itself: a jail script's inmates have nothing else to
                do, and this is the one place in the game where a workout is the obvious activity.
            ]]
            'prop_pris_bench_01',
            -- Found by /vsportmissing: real in the base files and in no list until then. Note that
            -- there is no _01 - the game ships the 02 alone, which is the sort of thing you only
            -- learn by asking IsModelValid rather than assuming a family is numbered from one.
            'prop_weight_bench_02',
            -- Hopeful: names common to gym MLOs.
            },
        gains = { strength = 1.0, stamina = 0.15 },
        reps = 8,
        difficulty = 'normal',
        cooldown = 90,

        --[[
            THE SCENARIO, NOT THE ANIMATION, AND IT HAS TO BE PLACED ON THE PROP.

            PROP_HUMAN_SEAT_MUSCLE_BENCH_PRESS lies the ped on the bench, facing the right way,
            with a barbell in their hands. Its animation twin
            (`amb@prop_human_seat_muscle_bench_press@base`) is the same motion but carries
            neither the placement nor the prop, so playing that directly gives a character
            lying across the bench at an angle, pressing nothing. See the long comment in
            client/session.lua.

            `preferScenario` is what routes this through TaskStartScenarioAtPosition with the
            bench's own coordinates and heading.

            `snap = false` because the scenario does the placing. Snapping first would move the
            player, then the scenario would move them again, and the walk would be visible.
            The `offset` is still used, but only to decide which side of the bench the prompt
            floats on.
        ]]
        --[[
            A PLACED ANIMATION PLUS A PROP WE OWN. This is the combination that actually holds
            together, and it took three attempts to get here, so the reasoning is written down.

            `placeAnim` runs the lying clip through TaskPlayAnimAdvanced at the BENCH's position
            and heading, so the body lands along the bench instead of wherever the player was
            facing. `props` then puts the barbell in their hands, because a placed animation -
            like every animation - carries nothing.

            The scenario stays as the fallback: it brings its own bar and does its own placing,
            which beats nothing when a dictionary will not stream.

            TUNE animOffset AND animHeading IN GAME. These are a starting point measured from the
            prop origin, and prop origins are not consistent between models. /vsportoffset prints
            the block to paste.
        ]]
        --[[
            MEASURED IN GAME against prop_muscle_bench_03 with /vsportprop, not guessed. The six
            bench models share their geometry closely enough that these serve all of them; a
            bench that sits differently gets a modelOverrides entry below.

            RE-CHECKED against the studio grid once that existed, and correct. A negative Z looks
            alarming next to the 0.88 rule in this file's header, and the reason it is fine is that
            a gym bench's origin is high - around the seat rather than on the floor - so a body
            lying on it belongs slightly BELOW that origin. The rule is about props whose origin is
            on the ground.
        ]]
        placeAnim = true,
        animOffset = vector3(0.00, -0.10, -0.25),
        animHeading = 180.0,

        -- Which model the numbers above were measured against. Read by tools/alignment.py to
        -- report which of this entry's other models are still unverified, so "aligned" never
        -- silently means "aligned against one of six".
        tunedAgainst = 'prop_muscle_bench_03',

        --[[
            Models checked in game and found correct WITH the reference numbers above - so they
            need no modelOverrides entry, and adding an empty one would be worse than nothing.

            Recorded because "verified good" and "not looked at yet" are indistinguishable in the
            file otherwise, and the difference is the whole work list. Read by
            tools/alignment.py.
        ]]
        --[[
            prop_muscle_bench_05 AND _06 USED TO BE LISTED HERE AND THE CLAIM WAS FALSE.

            They were "checked" early on, before the studio existed, with a tool that teleported to
            the nearest bench OF THE ENTRY rather than to the named model. The operator even said so
            at the time - "ca me re tp au meme", it takes me back to the same one - and both were
            recorded as verified anyway. What was actually judged twice was the _03.

            /vsporttour, which spawns the exact model asked for, marked all three of _04, _05 and _06
            wrong on the first pass. So they are back on the work list where they belong.

            The lesson is not about benches: a verification is only worth what the thing being shown
            is, and "it teleported me to the same one" was the tool telling us it was showing the
            wrong prop.
        ]]
        verifiedModels = {
            -- The prison yard's bench, checked in game against the studio and correct with nothing
            -- changed. A weight bench is a weight bench.
            'prop_pris_bench_01',
        },

        --[[
            Looked for and not found. The model stays in `models` regardless - a server whose MLO
            places it gets it for free - this only stops the work list from asking again.

            ONLY A TARGETED SEARCH BELONGS HERE, never a sweep result. A sweep that misses proves
            nothing: at a 400 metre step one reported five of these six benches as absent,
            including two that had just been used. `prop_muscle_bench_04` is listed because the
            targeted /vsportgoto for it failed at Muscle Beach, where its five siblings live -
            which is a much stronger negative than "the grid did not happen to stop near one".
        ]]
        absentModels = {
            'prop_muscle_bench_04',
        },

        --[[
            TWO-HANDED, AND THERE IS NOTHING TO POSITION.

            `twoHanded` needs no `pos`, no `rot` and no `bone`. The bar is placed every frame
            across BOTH hands: midpoint between the hand bones, heading from one to the other,
            pitch from the height between them, and the model's longest axis turned onto that
            line automatically from its bounding box.

            Every one of those is derived, so it is right for any bar on any animation with no
            tuning at all - which is the only way this could work. A bar attached to one hand
            inherits that hand's tilt, and there is no single offset that is correct for two
            hands moving independently. It is not hard to tune; it is impossible, and that is why
            it is not tuned.

            `rotOffset` exists only as an escape hatch for a model whose geometry is odd in some
            way the bounding box does not reveal. It should stay at zero.
        ]]
        -- `pos` and `rotOffset` are the measured fine adjustment: a few centimetres out of the
        -- palms and three degrees of level. Both were found in game, not reasoned about.
        props = {
            { model = 'prop_barbell_02', twoHanded = true,
              -- No rotation correction. The 357 that used to be here was a stray three degrees
              -- that the straighten key took to zero on a later pass, and zero is the expected
              -- answer for a two-handed prop: the bar's orientation is DERIVED every frame from
              -- the hand bones and the model's long axis, so there is nothing for a hand-tuned
              -- angle to fix. Three degrees on a barbell is invisible either way.
              pos = vector3(-0.034, 0.000, 0.048) },
        },

        --[[
            THE SCENARIO IS THE FALLBACK, NOT THE FIRST CHOICE. `preferScenario` is deliberately
            absent, and this is the second time the ordering has been wrong in this entry.

            PROP_HUMAN_SEAT_MUSCLE_BENCH_PRESS is a genuinely better animation than anything
            assembled by hand - Rockstar authored the bar and the body together. But a PROP_
            scenario expects a real scenario POINT baked into the map, not a position handed to
            it, and started at an arbitrary prop it does something worse than fail: it reports
            itself as running, teleports the ped to the coordinates, and animates nothing. The
            player ends up STANDING ON the bench, and because the verification sees a live
            scenario nothing falls back.

            The measured placeAnim values above do work, so they go first. The scenario is still
            tried if the animation dictionary will not stream, which is the case it is good for.
        ]]
        scenario = 'PROP_HUMAN_SEAT_MUSCLE_BENCH_PRESS',
        scenarioHeading = 0.0,
        offset = vector3(0.0, -0.9, 0.0),
        heading = 0.0,
        snap = false,

        --[[
            Per-bench tuning, for a model whose geometry differs from prop_muscle_bench_03.

            The six prop_muscle_bench models share the entry's own numbers - measured against _03,
            checked on _05 and _06 - so none of them appears here. An override that repeated them
            would be noise, and one full of zeroes would silently UNDO them.
        ]]
        modelOverrides = {
            --[[
                A DIFFERENT FAMILY ENTIRELY, and 84 centimetres of difference is why it needs this.

                prop_weight_bench_02 puts its origin on the FLOOR; every prop_muscle_bench puts its
                origin up at seat height. So the body belongs at +0.59 here and at -0.25 there - the
                same bench, the same posture, opposite signs. Nothing about the numbers hints at it
                and nothing but measuring would have found it.

                Found by /vsportmissing: the model is real, was in no list, and there is no
                prop_weight_bench_01 at all.
            ]]
            ['prop_weight_bench_02'] = {
                animOffset = vector3(0.00, -0.33, 0.59),
                animHeading = 180.0,
            },

            --[[
                AND THE FAMILY ASSUMPTION BREAKS INSIDE THE FAMILY.

                The entry's numbers were measured against prop_muscle_bench_03 and checked as
                correct on _05 and _06, which made "the six benches share their geometry" look like
                a safe statement. It is true for three of them. The _01 sits 48 cm higher than the
                _03 - the same distance apart as two different families - and the _02 is not even
                the same shape.
            ]]
            ['prop_muscle_bench_01'] = {
                animOffset = vector3(0.00, -0.10, 0.23),
                animHeading = 180.0,
            },
        },
    },

    free_weights = {
        order = 11,
        label = 'equip.free_weights',
        description = 'equip.free_weights_desc',
        models = {
            -- CONFIRMED. The dumbbells, the bare bars, the curl bar, and every loaded barbell
            -- from 10kg to 100kg - eight separate models, all of them real.
            'prop_freeweight_01', 'prop_freeweight_02',
            'prop_barbell_01', 'prop_barbell_02', 'prop_curl_bar_01',
            'prop_barbell_10kg', 'prop_barbell_20kg', 'prop_barbell_30kg',
            'prop_barbell_40kg', 'prop_barbell_50kg', 'prop_barbell_60kg',
            'prop_barbell_80kg', 'prop_barbell_100kg',
            -- Hopeful. Both spellings of dumbbell on purpose: the community list has carried
            -- the single-L misspelling for years and some MLOs ship it that way.
            },
        gains = { strength = 0.85, stamina = 0.1 },
        reps = 10,
        difficulty = 'normal',
        cooldown = 60,
        --[[
            THE SCENARIO IS NO LONGER PREFERRED, and that is a deliberate reversal worth recording.

            WORLD_HUMAN_MUSCLE_FREE_WEIGHTS brings its own dumbbell, which is why it used to run
            first. The cost was that the player's placement was the scenario's business: it stood
            them wherever it liked relative to the weight on the floor, and nothing could be
            measured or corrected.

            Measured in game with a bar we own. The scenario stays as the fallback for a build where
            the dictionary will not stream - it still brings its own weight, which beats an empty
            pair of hands.
        ]]
        scenario = 'WORLD_HUMAN_MUSCLE_FREE_WEIGHTS',

        --[[
            IN PLACE: THE PLAYER DOES NOT MOVE, AND THERE IS NO OFFSET TO MEASURE.

            You pick a dumbbell up. There is no correct place to stand to do that, so the body stays
            where it is, turns to face the weight, and lifts. Everything this entry used to carry to
            position the body - placeAnim, animOffset, animHeading, tunedAgainst, verifiedModels and
            two per-model overrides - is gone, for all thirteen models at once.

            THAT DATA WAS THE MOST EXPENSIVE IN THE RESOURCE. `animOffset` is measured from the prop's
            origin; how high that origin sits above the ground is decided by whoever placed the prop
            on the map; and the alignment studio, which spawns its own copy, cannot know it. That one
            fact produced a table of nine internally consistent and entirely wrong measurements, a
            player's feet through the floor, and half a metre of error on a squat rack that was
            "confirmed" twice against the same broken instrument.

            None of it is needed here. Deleting the data deletes the bug class rather than the bug.

            The scenario stays as the fallback for a build where the dictionary will not stream; it
            brings its own dumbbell, which beats empty hands.
        ]]
        inPlace = true,

        --[[
            The bar across both hands, the only placement this entry still has - and it is relative
            to the HANDS, not to the world, so nothing about where the player stands can move it.

            No rotation correction: a two-handed prop's orientation is derived every frame from the
            two hand bones and the model's own long axis, so there is nothing for a hand-tuned angle
            to fix. Seven centimetres forward and four up is the grip.
        ]]
        props = {
            { model = 'prop_barbell_02', twoHanded = true,
              pos = vector3(0.000, 0.072, 0.042) },
        },

        --[[
            The curl bar HOLDS A CURL BAR. The one per-model difference left, and it is not a
            position: a short bent EZ bar on the floor and a 2.2 metre Olympic bar in the hands is a
            substitution nobody would miss.
        ]]
        modelOverrides = {
            ['prop_curl_bar_01'] = {
                props = {
                    { model = 'prop_curl_bar_01', twoHanded = true,
                      pos = vector3(-0.033, 0.059, 0.040) },
                },
            },
        },

        -- `inPlace` ignores all three. They are kept only because `offset` still decides which side
        -- of the weight the interaction prompt floats on.
        offset = vector3(0.0, 0.7, 0.0),
        heading = 180.0,
        snap = false,

        -- The one that has to be hidden: a barbell still lying on the sand underneath the player
        -- while they lift an identical one is the giveaway. It reappears when the session ends.
        hideProp = true,
    },

    weight_rack = {
        order = 12,
        label = 'equip.weight_rack',
        description = 'equip.weight_rack_desc',
        models = {
            -- CONFIRMED: the squat racks at Muscle Beach.
            'prop_weight_squat',
            -- Both confirmed present in the base files by /vsportmissing. The _01 was in here as a
            -- guess and turned out to be right; the _02 was missing entirely.
            'prop_weight_rack_01',
            'prop_weight_rack_02',
            },
        gains = { strength = 1.1 },
        reps = 6,
        difficulty = 'hard',
        cooldown = 120,

        --[[
            THE SCENARIO IS NOT PREFERRED HERE, AND THAT IS THE DIFFERENCE FROM free_weights.

            WORLD_HUMAN_MUSCLE_FREE_WEIGHTS brings a DUMBBELL. That is right for the dumbbell rack
            and wrong for a squat rack, where the whole point is a loaded bar. So the animation
            runs and the bar is ours - two-handed, because a 2.27 metre barbell in one hand goes
            through the player's arm at a diagonal.

            Kept as the fallback for when the dictionary will not stream.
        ]]
        scenario = 'WORLD_HUMAN_MUSCLE_FREE_WEIGHTS',

        --[[
            MEASURED IN GAME against prop_weight_squat with /vsportprop. The body is set 80 cm in
            front of the rack's origin, which puts the player inside the frame under the bar.

            0.10, MEASURED AGAINST THE REAL RACK AT MUSCLE BEACH. Read the history before changing it.

            This value has been 0.09, then 0.59, then 0.10, and only the first and last were right.

            0.09 was the original, taken against the real prop in the real gym. When the studio was
            built, the rack was re-measured there and came out at 0.59 - and the studio's number was
            believed, on the reasoning that the studio had just been given real ground and was
            therefore trustworthy. A comment went in this spot declaring the 0.09 to have been a bug,
            with an explanation of why.

            It was the 0.59 that was wrong, by half a metre, and it put the player's pelvis a metre
            and a half above the gym floor.

            WHY THE STUDIO CANNOT GET THIS RIGHT, for any prop: animOffset is measured from the
            prop's ORIGIN, and how high that origin sits above the ground is decided by whoever
            placed the prop on the map. This rack's origin is 90 cm up at Muscle Beach.
            PlaceObjectOnGroundProperly seats a studio copy at its own height instead, and the
            difference between the two lands directly in the measurement. The studio is only sound
            for a model that the map places nowhere - where there is no ground truth to disagree with.

            The lesson is not about squat racks. It is that a confident written explanation of a
            wrong number makes it much harder to question later, and one had been written here.
        ]]
        placeAnim = true,
        animOffset = vector3(0.00, -0.80, 0.10),
        animHeading = 0.0,
        tunedAgainst = 'prop_weight_squat',

        props = {
            -- No rotation correction: the 5.2 that used to be here was stray drift that the
            -- straighten key took to zero on a later pass. Zero is the expected answer for a
            -- two-handed prop, whose orientation is derived every frame from the hand bones and
            -- the model's own long axis - see the same note on bench_press.
            { model = 'prop_barbell_02', twoHanded = true,
              pos = vector3(0.000, 0.042, 0.009) },
        },

        -- `snap` is off because the attachment does the placing: snapping first would walk the
        -- player there and the attach would then move them again, which is visible.
        offset = vector3(0.0, 0.6, 0.0),
        heading = 180.0,
        snap = false,

        modelOverrides = {
            -- A squat rack is stepped INTO, from the front, under the bar. The player ends up
            -- inside the frame rather than beside it, which is the whole difference between
            -- using a rack and standing next to one.
            ['prop_weight_squat'] = {
                offset = vector3(0.0, 0.35, 0.0),
                heading = 180.0,
                snap = true,
            },

            --[[
                The other rack in the files, found by /vsportmissing and in no list before that.

                Same step into the frame, same heading, 40 cm lower. Worth recording that this was
                PREDICTED at 0.9 on the reasoning that its origin would be on the floor, and the
                prediction was wrong: it sits 40 cm below the squat rack's bar-height origin, not
                90. Prop origins are not a family trait and cannot be reasoned about from a
                sibling - the only way to this number was to measure it.
            ]]
            ['prop_weight_rack_02'] = {
                animOffset = vector3(0.00, -0.80, 0.49),
                animHeading = 0.0,
            },

            --[[
                THESE TWO ARE PROVISIONAL, and the entry above says why.

                Both were measured in the studio, and the studio was then shown to be half a metre
                out on the squat rack because it cannot know how high the map puts a prop's origin.
                So treat 0.51 and 0.49 as best guesses rather than measurements.

                They are kept because there is no better answer available: the whole-map sweep found
                neither model placed anywhere, so there is no real specimen to measure against. If
                your MLO places one, align it there - `/vsportprop weight_rack prop_weight_rack_01`
                will use the real one now that the studio is no longer the default - and the numbers
                that come out will beat these.
            ]]
            ['prop_weight_rack_01'] = {
                animOffset = vector3(0.00, -0.80, 0.51),
                animHeading = 0.0,
            },
        },
    },

    kettlebell = {
        order = 13,
        label = 'equip.kettlebell',
        description = 'equip.kettlebell_desc',
        -- MLO ONLY. Every model this entry used to list was reported invalid by the game: those
        -- names are not in the base files at all, so they were guesses that never could have
        -- matched. The exercise is kept because gym MLOs do ship this equipment - add the model
        -- names your map uses to Config.ExtraEquipment and it starts working.
        mloOnly = true,
        models = {},
        gains = { strength = 0.6, stamina = 0.4 },
        reps = 12,
        difficulty = 'normal',
        cooldown = 60,
        scenario = 'WORLD_HUMAN_MUSCLE_FREE_WEIGHTS',
        preferScenario = true,   -- the scenario is what puts a weight in the hands
        offset = vector3(0.0, 0.6, 0.0),
        heading = 180.0,
        snap = true,
    },

    -- --- Bodyweight ------------------------------------------------------------------

    pull_ups = {
        order = 20,
        label = 'equip.pull_ups',
        description = 'equip.pull_ups_desc',
        models = {
            -- CONFIRMED: the bars you hang off, and the gymnastic rings.
            'prop_beach_bars_01', 'prop_beach_bars_02', 'prop_beach_rings_01',
            -- The prison yard's own bars. See the note on bench_press: the yard had none of this
            -- and the beach had all of it, which is not a distinction anybody designed.
            'prop_pris_bars_01',
            -- Hopeful.
            },
        gains = { strength = 0.9, stamina = 0.25 },
        reps = 8,
        difficulty = 'hard',
        cooldown = 75,
        --[[
            A PROP_ scenario, and therefore a FALLBACK rather than the first choice - same reason
            as the bench press. Started at a position instead of at a real scenario point, a PROP_
            scenario reports itself as running, teleports the ped and animates nothing, which is
            worse than failing because nothing falls back.

            The chin-up animation is played instead. It has no prop to hold and needs none: the
            bar is already in the world.
        ]]
        scenario = 'PROP_HUMAN_MUSCLE_CHIN_UPS',

        --[[
            HANGING FROM THE BAR. Measured in game with /vsportprop against prop_beach_bars_01.

            The -1.39 on X is the interesting number and it is why this had to be measured. The
            model's origin is not under the bar: prop_beach_bars_01 is a frame carrying SEVERAL
            bars, and its origin sits at one end of the frame. A body placed at the origin hangs
            off the side of the structure entirely.

            +0.98 on Z is the grip height above the frame's base.
        ]]
        placeAnim = true,
        animOffset = vector3(-1.39, -0.13, 0.98),
        animHeading = 0.0,
        tunedAgainst = 'prop_beach_bars_01',

        -- The prison bars fit the beach frame's numbers with nothing changed, checked in game.
        verifiedModels = { 'prop_pris_bars_01' },

        --[[
            AND THE SECOND FRAME NEEDS ITS OWN NUMBERS, which is the case that justifies this
            whole mechanism existing.

            prop_beach_bars_02 puts its origin UNDER the bar rather than at the end of the frame,
            so the lateral offset that the 01 needs is exactly wrong here: reusing -1.39 hangs the
            body a metre and a half off the side. The grip height is the same on both.
        ]]
        modelOverrides = {
            ['prop_beach_bars_02'] = {
                animOffset = vector3(0.00, -0.15, 0.98),
                animHeading = 0.0,
            },

            -- The rings hang half a metre higher than either bar, and their origin is centred
            -- like the 02's. Same exercise, three genuinely different placements.
            ['prop_beach_rings_01'] = {
                animOffset = vector3(0.02, -0.15, 1.47),
                animHeading = 0.0,
            },
        },

        offset = vector3(0.0, 0.35, 0.0),
        heading = 180.0,
        snap = false,
    },

    dip_bars = {
        order = 21,

        --[[
            OFF BY DEFAULT, AND NOT BECAUSE OF A MISSING PROP.

            prop_beach_dip_bars_01 and _02 are real and placed on the beaches. The problem is that
            nothing shipped with the game resembles a dip: the only usable clip is the chin-up,
            which puts the hands ABOVE the head, and on parallel bars the hands belong at the
            hips. Aligned as well as it can be, it reads as a player hanging in mid-air next to
            the bars rather than using them.

            Judged in game and rejected, rather than shipped as the one exercise that looks wrong.
            The entry stays because the numbers are not the issue and the day a server adds a
            proper dip animation this needs a `models` list, not a rewrite. Turn it on with:

                Config.ExtraEquipment = { dip_bars = { enabled = true } }
        ]]
        enabled = false,

        label = 'equip.dip_bars',
        description = 'equip.dip_bars_desc',
        models = {
            -- CONFIRMED: the parallel dip bars.
            'prop_beach_dip_bars_01', 'prop_beach_dip_bars_02',
            -- Hopeful.
            },
        gains = { strength = 0.75, stamina = 0.2 },
        reps = 10,
        difficulty = 'normal',
        cooldown = 60,
        -- Fallback only, like pull_ups above: a PROP_ scenario placed by hand does not animate.
        scenario = 'PROP_HUMAN_MUSCLE_CHIN_UPS',
        offset = vector3(0.0, 0.0, 0.0),
        snap = false,
    },

    push_ups = {
        order = 22,
        label = 'equip.push_ups',
        description = 'equip.push_ups_desc',
        models = {
            --[[
                prop_rolled_yoga_mat IS NOT LISTED, and it is real and it does exist.

                It is a mat ROLLED UP. Lying on it, or sitting on it cross-legged, is absurd - the
                thing is a 60 cm cylinder. It was in all four mat exercises because the name matches
                the pattern, which is exactly the kind of listing that looks like coverage and plays
                as a bug.

                Judged in game and dropped, the same call as the dip bars and the street bench.
                Add it back with Config.ExtraEquipment if your map lays them out flat.
            ]]
            'prop_yoga_mat_01', 'prop_yoga_mat_02', 'prop_yoga_mat_03',
            },
        gains = { strength = 0.55, stamina = 0.45 },
        reps = 12,
        difficulty = 'normal',
        cooldown = 45,

        --[[
            PRONE, ALONG THE MAT. Measured in game with /vsportprop against prop_yoga_mat_01.

            animHeading = 90 because the mat's long axis runs across its own Y, so a body placed at
            the mat's own heading lies ACROSS it.

            +1.03 on Z looks wrong for something 2 cm thick. See the note on the yoga entry: the
            same 1.03 came out of three separate measurements with three different clips - prone,
            supine and seated - so it belongs to the MAT and to how an attached ped is positioned,
            not to any one animation. It carries to every exercise on these mats.
        ]]
        placeAnim = true,
        animOffset = vector3(-0.23, -0.04, 1.03),
        animHeading = 90.0,
        tunedAgainst = 'prop_yoga_mat_01',

        --[[
            The other two mats fit the numbers above with nothing changed, checked in game.

            One check covered all four mat exercises: the three mats are the same object with
            different textures, so any geometric difference would have shifted push_ups, sit_ups,
            yoga and stretching by the same amount. Nothing shifted, so nothing needs overriding.
        ]]
        verifiedModels = { 'prop_yoga_mat_02', 'prop_yoga_mat_03' },

        -- The fallback. It places itself and does not care about the mat, which is fine for an
        -- exercise that needs no equipment at all.
        scenario = 'WORLD_HUMAN_PUSH_UPS',
        offset = vector3(0.0, 0.0, 0.0),
        heading = 0.0,
        snap = false,
    },

    sit_ups = {
        order = 23,
        label = 'equip.sit_ups',
        description = 'equip.sit_ups_desc',
        models = {
            -- prop_rolled_yoga_mat is deliberately absent: see the note on push_ups. It is a mat
            -- rolled up, and lying on a cylinder is absurd.
            'prop_yoga_mat_01', 'prop_yoga_mat_02', 'prop_yoga_mat_03',
            },
        gains = { strength = 0.4, stamina = 0.6 },
        reps = 14,
        difficulty = 'normal',
        cooldown = 45,

        --[[
            ON THE BACK, ALONG THE MAT. Measured against prop_yoga_mat_01, same as push_ups.

            The Z came out at 1.03 here too, from a different clip and a separate measurement,
            which confirms what push_ups only suspected: the metre belongs to the ANIMATION's root
            node, not to the mat. Expect it on any prone or supine clip placed this way, and do not
            try to talk it down towards the mat's real 2 cm.

            X differs in sign from push_ups (+0.33 against -0.23) because the two clips lie with
            their heads at opposite ends.
        ]]
        placeAnim = true,
        animOffset = vector3(0.33, 0.07, 1.03),
        animHeading = 90.0,
        tunedAgainst = 'prop_yoga_mat_01',

        -- Checked on the other two mats through push_ups; see the note there.
        verifiedModels = { 'prop_yoga_mat_02', 'prop_yoga_mat_03' },

        scenario = 'WORLD_HUMAN_SIT_UPS',
        offset = vector3(0.0, 0.0, 0.0),
        heading = 0.0,
        snap = false,
    },

    muscle_flex = {
        order = 24,
        label = 'equip.muscle_flex',
        description = 'equip.muscle_flex_desc',
        -- MLO ONLY. Every model this entry used to list was reported invalid by the game: those
        -- names are not in the base files at all, so they were guesses that never could have
        -- matched. The exercise is kept because gym MLOs do ship this equipment - add the model
        -- names your map uses to Config.ExtraEquipment and it starts working.
        mloOnly = true,
        models = {},
        -- Posing in the mirror is not training. It is here because a gym should let you do
        -- it, and it pays almost nothing on purpose.
        gains = { strength = 0.1 },
        reps = 4,
        difficulty = 'easy',
        cooldown = 300,
        scenario = 'WORLD_HUMAN_MUSCLE_FLEX',
        preferScenario = true,   -- the scenario is what puts a weight in the hands
        offset = vector3(0.0, 0.8, 0.0),
        heading = 180.0,
        snap = true,
    },

    -- --- Combat ----------------------------------------------------------------------

    punching_bag = {
        order = 30,
        label = 'equip.punching_bag',
        description = 'equip.punching_bag_desc',
        models = {
            -- CONFIRMED: a real heavy bag.
            'prop_beach_punchbag',
            -- The other heavy bag in the files, found by cross-checking a published prop dump
            -- against this catalogue. `_l` is the large one; there is no small sibling.
            'prop_punch_bag_l',
            -- Hopeful.
            },
        gains = { strength = 0.5, stamina = 0.5, breath = 0.2 },
        reps = 14,
        difficulty = 'hard',
        cooldown = 60,

        --[[
            SQUARED UP TO THE BAG. Measured in game against prop_beach_punchbag.

            The 1.25 on X is the whole reason this needed measuring: the model's origin is on its
            frame, not on the bag, so a body placed at the origin stands inside the post. The
            heading of 90 turns the player to face the bag rather than stand alongside it.
        ]]
        placeAnim = true,
        animOffset = vector3(1.25, 0.03, 0.91),
        animHeading = 90.0,
        tunedAgainst = 'prop_beach_punchbag',

        --[[
            THE HANGING BAG, AND ITS ORIGIN IS AT THE TOP.

            -1.63 against the beach bag's +0.91 - two and a half metres apart for the same exercise
            - because prop_punch_bag_l hangs from a mount and carries its origin up there, while the
            beach bag stands on a frame and carries its origin at the base.

            This is the widest gap between two models of one exercise anywhere in this file, and it
            is the clearest illustration of why none of these numbers can be reasoned about: they
            describe where a modeller put the origin, and modellers put it wherever the object hangs
            from or stands on.
        ]]
        modelOverrides = {
            -- Re-measured on real ground. The sky studio had it at -1.63; the 23 cm difference is
            -- the bounding-box floor error, same as everywhere else measured up there.
            ['prop_punch_bag_l'] = {
                animOffset = vector3(0.89, -0.04, -1.40),
                animHeading = 85.8,
            },
        },

        -- No shipped scenario punches a bag, so there is no fallback worth naming: a
        -- WORLD_HUMAN_ scenario here would stand the player somewhere else doing something else.
        offset = vector3(0.0, 0.9, 0.0),
        heading = 180.0,
        snap = false,
    },

    speed_bag = {
        order = 31,
        label = 'equip.speed_bag',
        description = 'equip.speed_bag_desc',
        -- MLO ONLY. Every model this entry used to list was reported invalid by the game: those
        -- names are not in the base files at all, so they were guesses that never could have
        -- matched. The exercise is kept because gym MLOs do ship this equipment - add the model
        -- names your map uses to Config.ExtraEquipment and it starts working.
        mloOnly = true,
        models = {},
        gains = { stamina = 0.4, strength = 0.2 },
        reps = 16,
        difficulty = 'brutal',
        cooldown = 60,
        offset = vector3(0.0, 0.7, 0.0),
        heading = 180.0,
        snap = true,
    },

    -- --- Cardio ----------------------------------------------------------------------

    treadmill = {
        order = 40,
        label = 'equip.treadmill',
        description = 'equip.treadmill_desc',
        -- MLO ONLY. Every model this entry used to list was reported invalid by the game: those
        -- names are not in the base files at all, so they were guesses that never could have
        -- matched. The exercise is kept because gym MLOs do ship this equipment - add the model
        -- names your map uses to Config.ExtraEquipment and it starts working.
        mloOnly = true,
        models = {},
        gains = { stamina = 1.0, breath = 0.35 },
        reps = 12,
        difficulty = 'normal',
        cooldown = 90,
        scenario = 'WORLD_HUMAN_JOG_STANDING',
        offset = vector3(0.0, -0.4, 0.0),
        heading = 0.0,
        snap = true,
    },

    exercise_bike = {
        order = 41,
        label = 'equip.exercise_bike',
        description = 'equip.exercise_bike_desc',
        models = {
            -- CONFIRMED: a real exercise bike.
            'prop_exer_bike_01',
            -- Hopeful.
            },
        gains = { stamina = 0.9, breath = 0.3 },
        reps = 12,
        difficulty = 'easy',
        cooldown = 75,

        --[[
            SEATED ON THE SADDLE. Measured in game with /vsportprop, not guessed.

            +1.11 on Z is the saddle height above the model's origin, which sits at the floor -
            the sort of number that is obvious once measured and impossible to guess, and the
            reason reaching for a negative Z to "sit down" drives the body into the ground.

            AND IT IS STILL A JOG. `amb@world_human_jog_standing@male@base` is a jog on the spot;
            nothing in the base game pedals outside a real bicycle. Seated on the saddle the legs
            move and the body is in the right place, which is as close as this gets. Kept because
            a rider sitting correctly and jogging beats a rider standing beside the bike.
        ]]
        placeAnim = true,
        animOffset = vector3(0.00, -0.27, 1.11),
        animHeading = 0.0,
        tunedAgainst = 'prop_exer_bike_01',

        -- The fallback, for a build where the dictionary will not stream. A standing jog next to
        -- the bike: wrong, but present.
        scenario = 'WORLD_HUMAN_JOG_STANDING',

        -- `snap = false`: the body is attached to the bike, so moving the player first would be
        -- a visible walk to a spot that then stops mattering. The offset still decides which
        -- side the prompt floats on.
        offset = vector3(0.0, -0.3, 0.0),
        heading = 0.0,
        snap = false,
    },

    rowing_machine = {
        order = 42,
        label = 'equip.rowing_machine',
        description = 'equip.rowing_machine_desc',
        -- MLO ONLY. Every model this entry used to list was reported invalid by the game: those
        -- names are not in the base files at all, so they were guesses that never could have
        -- matched. The exercise is kept because gym MLOs do ship this equipment - add the model
        -- names your map uses to Config.ExtraEquipment and it starts working.
        mloOnly = true,
        models = {},
        gains = { stamina = 0.7, strength = 0.35, breath = 0.25 },
        reps = 12,
        difficulty = 'normal',
        cooldown = 75,
        scenario = 'WORLD_HUMAN_SIT_UPS',
        offset = vector3(0.0, -0.5, 0.0),
        heading = 0.0,
        snap = true,
    },

    --[[
        OFF BY DEFAULT: NO CLIP SKIPS A ROPE.

        prop_skip_rope_01 is real and placed, and the alignment worked. What could not be fixed is
        that the only cardio clip available is a jog on the spot, so the player stands next to a
        coiled rope and runs. Judged in game: "c'est une corde a sauter pourquoi il court".

        The rule that follows from it, and it is the right rule: with no animation that matches the
        equipment, better nothing than something that reads as broken. Applied here, to volleyball
        and to basketball.

        Turn it on with:
            Config.ExtraEquipment = { skipping_rope = { enabled = true } }
    ]]
    skipping_rope = {
        order = 43,
        enabled = false,
        label = 'equip.skipping_rope',
        description = 'equip.skipping_rope_desc',
        models = {
            -- CONFIRMED: a real skipping rope.
            'prop_skip_rope_01',
            -- Hopeful.
            },
        gains = { stamina = 0.65, breath = 0.45 },
        reps = 16,
        difficulty = 'hard',
        cooldown = 60,
        scenario = 'WORLD_HUMAN_JOG_STANDING',
        offset = vector3(0.0, 0.5, 0.0),
        heading = 180.0,
        snap = true,
    },

    battle_ropes = {
        order = 44,
        label = 'equip.battle_ropes',
        description = 'equip.battle_ropes_desc',
        -- MLO ONLY. Every model this entry used to list was reported invalid by the game: those
        -- names are not in the base files at all, so they were guesses that never could have
        -- matched. The exercise is kept because gym MLOs do ship this equipment - add the model
        -- names your map uses to Config.ExtraEquipment and it starts working.
        mloOnly = true,
        models = {},
        gains = { stamina = 0.6, strength = 0.45, breath = 0.2 },
        reps = 14,
        difficulty = 'hard',
        cooldown = 75,
        scenario = 'WORLD_HUMAN_MUSCLE_FREE_WEIGHTS',
        preferScenario = true,   -- the scenario is what puts a weight in the hands
        offset = vector3(0.0, 0.9, 0.0),
        heading = 180.0,
        snap = true,
    },

    -- --- Breathing and recovery ------------------------------------------------------

    yoga = {
        order = 50,
        label = 'equip.yoga',
        description = 'equip.yoga_desc',
        models = {
            -- prop_rolled_yoga_mat is deliberately absent: see the note on push_ups. It is a mat
            -- rolled up, and lying on a cylinder is absurd.
            'prop_yoga_mat_01', 'prop_yoga_mat_02', 'prop_yoga_mat_03',
            },
        -- The best breath training in the catalogue, and almost the only thing that trains it
        -- indoors. Slow, easy, and long.
        gains = { breath = 1.0, stamina = 0.15 },
        reps = 8,
        difficulty = 'easy',
        cooldown = 120,
        minigame = {
            -- Yoga is held poses, not reps. A long window and a wide perfect band make it
            -- feel like breathing rather than button mashing.
            window = 2600,
            perfectZone = { 0.55, 0.90 },
            goodZone    = { 0.30, 0.99 },
            restBetween = 1600,
            keys = { 1, 1 },
        },
        --[[
            SEATED ON THE MAT, ALONG ITS LENGTH. Measured against prop_yoga_mat_01.

            THE 1.03 IS THE MAT'S, NOT THE ANIMATION'S, and this entry is what proved it. Three
            separate measurements - push_ups face down, sit_ups on its back, yoga sitting upright -
            all landed on the same Z from three different clips. A number that survives a change of
            posture is not a property of the posture.

            What it is a property of: an ATTACHED ped is positioned by an origin around its middle
            rather than by its feet, so lining a body up with a prop whose own origin sits on the
            floor takes roughly a metre of +Z. Expect that on any flat prop, and do not spend
            twenty presses arguing it back down towards the mat's real 2 cm.

            Only X changes between the three, because the clips sit and lie at different points
            along the mat: -0.23 face down, +0.33 on its back, -0.52 seated.
        ]]
        placeAnim = true,
        animOffset = vector3(-0.52, 0.00, 1.03),
        animHeading = 90.0,
        tunedAgainst = 'prop_yoga_mat_01',

        -- Checked on the other two mats through push_ups; see the note there.
        verifiedModels = { 'prop_yoga_mat_02', 'prop_yoga_mat_03' },

        scenario = 'WORLD_HUMAN_YOGA',
        offset = vector3(0.0, 0.0, 0.0),
        heading = 0.0,
        snap = false,
    },

    stretching = {
        order = 51,
        label = 'equip.stretching',
        description = 'equip.stretching_desc',
        models = {
            -- prop_rolled_yoga_mat is deliberately absent: see the note on push_ups. It is a mat
            -- rolled up, and lying on a cylinder is absurd.
            'prop_yoga_mat_01', 'prop_yoga_mat_02', 'prop_yoga_mat_03',
            },
        gains = { breath = 0.35, stamina = 0.2 },
        reps = 6,
        difficulty = 'easy',
        cooldown = 90,

        -- On the mat, along its length. Measured against prop_yoga_mat_01, and the fourth
        -- measurement in a row to land on Z = 1.03 - see the note on the yoga entry for why that
        -- number belongs to the mat rather than to any of the four clips.
        placeAnim = true,
        animOffset = vector3(-0.40, -0.05, 1.03),
        animHeading = 90.0,
        tunedAgainst = 'prop_yoga_mat_01',

        -- Checked on the other two mats through push_ups; see the note there.
        verifiedModels = { 'prop_yoga_mat_02', 'prop_yoga_mat_03' },

        scenario = 'WORLD_HUMAN_YOGA',
        offset = vector3(0.0, 0.0, 0.0),
        heading = 0.0,
        snap = false,
    },

    --[[
        The park bench.

        Not gym equipment, and that was the point: `prop_bench_*` is everywhere in Los Santos, so
        this single entry would have made a workout possible in any park, on any promenade and in
        every prison yard, on a server with no gym MLO at all. Fifteen models, `prop_bench_08`
        confirmed at Muscle Beach and the rest of the family covering the whole map.

        OFF BY DEFAULT ANYWAY, on the judgement that a street bench is a thing you sit on and
        training on one reads as absurd - which is a call about the fiction, not about the
        alignment, and the alignment would have worked.

        It costs less than the model count suggests: push_ups, sit_ups, yoga and stretching are
        already available ANYWHERE through Config.Anywhere and the radial menu, so a server with no
        gym is not left with nothing to do. That is what makes this removal cheap.

        Turn it on with:
            Config.ExtraEquipment = { park_bench = { enabled = true } }
        and then measure it - the numbers were never taken.
    ]]
    park_bench = {
        order = 25,
        enabled = false,
        label = 'equip.park_bench',
        description = 'equip.park_bench_desc',
        models = {
            'prop_bench_08',
            'prop_bench_01a', 'prop_bench_01b', 'prop_bench_01c',
            'prop_bench_02', 'prop_bench_03', 'prop_bench_04', 'prop_bench_05',
            'prop_bench_06', 'prop_bench_07', 'prop_bench_09', 'prop_bench_10',
            'prop_bench_11', 'prop_fib_3b_bench', 'prop_wait_bench_01',
        },
        gains = { strength = 0.45, stamina = 0.35 },
        reps = 12,
        difficulty = 'normal',
        cooldown = 60,
        -- A WORLD_ scenario, deliberately: it plays anywhere, needs no prop and does not care
        -- which way the bench is turned. The player sits at the bench and works their core.
        scenario = 'WORLD_HUMAN_SIT_UPS',
        offset = vector3(0.0, -0.75, 0.0),
        heading = 0.0,
        snap = true,
    },

    --[[
        --- Ball sports -----------------------------------------------------------------

        Two exercises off confirmed props that were sitting unused. Basketball hoops and
        volleyball nets are all over the beaches and the parks, which means a workout is
        available in places with no gym equipment at all.

        Both train stamina and lungs rather than strength, and both are worth less than a real
        session: running about with a ball is exercise, it is not a training programme.
    ]]
    --[[
        BOTH BALL SPORTS ARE OFF BY DEFAULT, for the same reason as the skipping rope: nothing
        shipped with the game throws or spikes a ball, so both fall back to a jog on the spot and
        the player runs in place next to a ball.

        Volleyball was judged in game. Basketball was not, and is turned off on the evidence rather
        than on a test: it is the twin entry, with the same WORLD_HUMAN_JOG_STANDING, the same
        standing jog clip and the same comment admitting it. Checking it would have produced the
        same answer. Reverse it in one line if that call was wrong:

            Config.ExtraEquipment = { basketball = { enabled = true } }
    ]]
    basketball = {
        order = 45,
        enabled = false,
        label = 'equip.basketball',
        description = 'equip.basketball_desc',
        models = {
            -- CONFIRMED.
            'prop_bskball_01', 'prop_basketball_net',
            -- Hopeful.
            },
        gains = { stamina = 0.55, breath = 0.25 },
        reps = 12,
        difficulty = 'normal',
        cooldown = 60,
        scenario = 'WORLD_HUMAN_JOG_STANDING',
        offset = vector3(0.0, 1.2, 0.0),
        heading = 180.0,
        snap = true,
    },

    -- Off by default. Both balls checked in game, both produced a jog on the spot. See the note on
    -- basketball above.
    volleyball = {
        order = 46,
        enabled = false,
        label = 'equip.volleyball',
        description = 'equip.volleyball_desc',
        models = {
            -- CONFIRMED.
            'prop_beach_volball01', 'prop_beach_volball02',
            -- Hopeful.
            },
        gains = { stamina = 0.5, breath = 0.2 },
        reps = 12,
        difficulty = 'normal',
        cooldown = 60,
        scenario = 'WORLD_HUMAN_JOG_STANDING',
        offset = vector3(0.0, 1.0, 0.0),
        heading = 180.0,
        snap = true,
    },

    -- --- Machines --------------------------------------------------------------------

    leg_press = {
        order = 60,
        --[[
            OFF BY DEFAULT, AND THE ONLY ONE HERE SWITCHED OFF FOR PLACEMENT RATHER THAN ANIMATION.

            The body lands wrong on prop_muscle_bench_06 in the world. Reported in play, and it is
            the fourth time this exact symptom has been reported about a prop_muscle_bench model:
            _02, _04 and _05 were taken out of the bench press for it, and this is _06.

            THE NUMBERS BELOW ARE NOT WRONG BY CARELESSNESS, AND THAT IS THE POINT. `animOffset` is
            measured from the PROP'S ORIGIN, and how high that origin sits above the ground is
            decided by whoever placed the prop in the map, not by the model. The alignment studio
            spawns its own copy on flat ground to measure against, so its answer is only ever right
            for a copy placed the way the studio places it. For a model the map puts somewhere else,
            the vertical is a guess wearing three decimal places.

            Which is why this entry once carried two contradictory comments a dozen lines apart: one
            saying the placement was not measured yet, one saying it was measured on real ground.
            Both were written honestly. The measurement happened; it just could not transfer.

            EVERYTHING IS KEPT rather than deleted, because nothing here is a guess: the model really
            is a leg press, the seated animation really is the right one, and the 37.5 degrees of
            recline really is what the machine looks like. Only the vertical could not be pinned
            down. An operator whose map places this machine somewhere the numbers do fit needs one
            line:

                Config.ExtraEquipment = { leg_press = { enabled = true } }

            and then /vsportprop leg_press prop_muscle_bench_06 to take their own measurement.

            A gym MLO with a real leg press is the better route back: turn it on and give it your own
            model, whose origin you can measure once and trust.
        ]]
        enabled = false,
        label = 'equip.leg_press',
        description = 'equip.leg_press_desc',
        models = {
            'prop_muscle_bench_06',
        },
        gains = { strength = 0.8, stamina = 0.3 },
        reps = 8,
        difficulty = 'normal',
        cooldown = 90,

        --[[
            SEATED IN THE MACHINE, taken in the alignment studio against a spawned copy.

            KEPT AS A STARTING POINT, NOT AS A VERIFIED VALUE. The two rotations are properties of
            the MODEL and transfer to any server: 37.5 degrees of pitch is the point of the whole
            entry, because a leg press seat reclines and the body has to be tipped back rather than
            sat upright, which `animHeading` cannot express - it is one number around Z. This is the
            second exercise in the file to need the full three-axis rotation, after the incline
            benches, and both were found the same way, by looking at the model.

            The 0.65 on the offset's Z is the part that did not survive contact with the map, and it
            is the reason the entry is switched off above. Anybody re-enabling this should expect to
            change that one number and nothing else.

            On the entry rather than in modelOverrides because it is the only model here. An override
            that covers nothing but the reference repeats the entry's own numbers, which is noise
            until it drifts and then it is a bug.
        ]]
        placeAnim = true,
        animOffset = vector3(0.00, -0.64, 0.65),
        animRot = vector3(37.5, 0.0, 2.9),
        tunedAgainst = 'prop_muscle_bench_06',

        -- The fallback if the dictionary will not stream, and `snap = false` because the body is
        -- attached to the machine: snapping first would walk the player, then the attach would move
        -- them again.
        scenario = 'WORLD_HUMAN_SIT_UPS',
        offset = vector3(0.0, -0.6, 0.0),
        heading = 0.0,
        snap = false,
    },

    cable_machine = {
        order = 61,
        label = 'equip.cable_machine',
        description = 'equip.cable_machine_desc',
        -- MLO ONLY. Every model this entry used to list was reported invalid by the game: those
        -- names are not in the base files at all, so they were guesses that never could have
        -- matched. The exercise is kept because gym MLOs do ship this equipment - add the model
        -- names your map uses to Config.ExtraEquipment and it starts working.
        mloOnly = true,
        models = {},
        gains = { strength = 0.7, stamina = 0.2 },
        reps = 10,
        difficulty = 'normal',
        cooldown = 75,
        scenario = 'WORLD_HUMAN_MUSCLE_FREE_WEIGHTS',
        preferScenario = true,   -- the scenario is what puts a weight in the hands
        offset = vector3(0.0, 0.7, 0.0),
        heading = 180.0,
        snap = true,
    },
}

-- ===========================================================================================
-- Indexing
-- ===========================================================================================
--
-- Built once at load. Every scan is a hash lookup after this, not a walk of the catalogue.

Equipment.byModel = {}          -- model hash -> { equipment key, ... }, in catalogue order
Equipment.keys = {}             -- every enabled key, sorted by `order`

--[[
    THE SHIPPED CATALOGUE, KEPT PRISTINE.

    `Equipment.build` merges on top of the catalogue IN PLACE, which is fine once and wrong twice:
    after the first build the shipped values are gone, so a later rebuild cannot un-apply anything.
    That did not matter while additions only ever came from config.lua and only ever at boot. It
    matters now that /vsportadd and /vsportremove change them while the server runs - removing a
    model has to give the shipped value back, not leave the merged one behind.

    So the shipped table is snapshotted once, and every build starts from a fresh copy of it. One
    deep copy of roughly a thousand lines, at boot, once.
]]
Equipment.shipped = nil

--[[
    Live additions from the staff commands, in exactly the shape of Config.ExtraEquipment.

    Owned by the server, persisted to data/custom.json, and pushed to every client. Applied AFTER
    Config.ExtraEquipment, so a hand-written config always loses to a deliberate in-game change -
    which is the right way round: the operator who just typed /vsportadd is looking at the result.
]]
Equipment.overlay = {}

--- Merge Config.ExtraEquipment and the live overlay, then build the indexes. Safe to call
--- repeatedly: /vsportadd, /vsportremove and /vsportreload all end here.
function Equipment.build()
    Equipment.byModel = {}
    Equipment.keys = {}

    -- Snapshot on the first call, restore from it on every later one.
    if Equipment.shipped == nil then
        Equipment.shipped = Sport.copy(Equipment.catalogue)
    else
        Equipment.catalogue = Sport.copy(Equipment.shipped)
    end

    --[[
        Two layers of operator additions, applied in order of how recently a human meant them.

        Config.ExtraEquipment first: declared in config.lua so that adding equipment never means
        editing a file under shared/, which is the one an update overwrites.

        Then the live overlay, so an in-game /vsportadd wins over a stale config line rather than
        being silently undone by it.
    ]]
    for _, layer in ipairs({ Config.ExtraEquipment, Equipment.overlay }) do
        if type(layer) == 'table' then
            for key, entry in pairs(layer) do
                if type(entry) == 'table' then
                    if type(Equipment.catalogue[key]) == 'table' then
                        -- An entry with the same key PATCHES the shipped one, so an operator can
                        -- add three models to the bench press without restating all of it.
                        Sport.merge(Equipment.catalogue[key], entry)
                    else
                        Equipment.catalogue[key] = Sport.copy(entry)
                    end
                end
            end
        end
    end

    for key, entry in pairs(Equipment.catalogue) do
        if entry.enabled ~= false then
            entry.key = key
            Equipment.keys[#Equipment.keys + 1] = key

            -- Fill in the researched animation unless the entry named its own. An operator's
            -- Config.ExtraEquipment `anim` always wins, and so does one written into the
            -- catalogue by hand.
            if entry.anim == nil and ANIMS[key] then
                entry.anim = { dict = ANIMS[key].dict, clip = ANIMS[key].clip, flag = 1 }
            end

            -- Re-key `modelOverrides` from names to hashes, once. Operators write names
            -- because that is what /vsportscan prints; the runtime only ever has a hash.
            if type(entry.modelOverrides) == 'table' then
                entry.overridesByHash = {}
                for model, override in pairs(entry.modelOverrides) do
                    local hash = type(model) == 'number' and model or GetHashKey(model)
                    if hash and hash ~= 0 then
                        entry.overridesByHash[hash] = override
                    end
                end
            end

            for _, model in ipairs(entry.models or {}) do
                -- A number is already a hash; a string has to be joaat'd. GetHashKey is
                -- available on both sides and is the same function as joaat().
                local hash = type(model) == 'number' and model or GetHashKey(model)
                if hash and hash ~= 0 then
                    local holders = Equipment.byModel[hash]
                    if not holders then
                        holders = {}
                        Equipment.byModel[hash] = holders
                    end
                    holders[#holders + 1] = key
                end
            end
        end
    end

    -- Sort the key list, and every model's holder list, by `order`. A yoga mat offers push
    -- ups, sit ups, yoga and stretching; without this the option order would change between
    -- restarts, because `pairs` makes no promises.
    local function byOrder(a, b)
        local left = tonumber(Equipment.catalogue[a].order) or 999
        local right = tonumber(Equipment.catalogue[b].order) or 999
        if left ~= right then return left < right end
        return a < b
    end

    table.sort(Equipment.keys, byOrder)
    for _, holders in pairs(Equipment.byModel) do
        table.sort(holders, byOrder)
    end
end

--- The catalogue entry for `key`, or nil. Every caller treats nil as "refuse the session":
--- an equipment key arriving from the client is untrusted input like any other.
function Equipment.get(key)
    if type(key) ~= 'string' then return nil end
    local entry = Equipment.catalogue[key]
    if type(entry) ~= 'table' or entry.enabled == false then return nil end
    return entry
end

--- Every exercise a given model offers, in display order. Empty when the model is not sport
--- equipment, which is the answer for almost every object in the pool.
function Equipment.forModel(hash)
    return Equipment.byModel[hash] or {}
end

--[[
    How to stage `entry` against one specific prop.

    Returns a fresh table of `offset`, `heading`, `snap`, `anim`, `scenario` and `hideProp`,
    with the entry's `modelOverrides` for `modelHash` applied on top of the entry's own values.

    This is what makes a squat rack and a flat bench, which are the same exercise, position the
    player completely differently. Called once when a session starts, never in a loop.
]]
function Equipment.staging(entry, modelHash)
    if type(entry) ~= 'table' then return {} end

    local out = {
        offset = entry.offset,
        heading = entry.heading,
        snap = entry.snap,
        anim = entry.anim,
        scenario = entry.scenario,
        hideProp = entry.hideProp == true,
        preferScenario = entry.preferScenario == true,
        scenarioHeading = entry.scenarioHeading,
        props = entry.props,
        placeAnim = entry.placeAnim == true,
        inPlace = entry.inPlace == true,
        animOffset = entry.animOffset,
        animHeading = entry.animHeading,
        animRot = entry.animRot,
    }

    local overrides = entry.modelOverrides
    if type(overrides) ~= 'table' or not modelHash then return out end

    -- The override table is keyed by NAME in the config, because that is what an operator can
    -- read and write. The index is built once at load; this is a hash lookup, not a walk.
    local override = entry.overridesByHash and entry.overridesByHash[modelHash] or nil
    if type(override) ~= 'table' then return out end

    if override.offset ~= nil then out.offset = override.offset end
    if override.heading ~= nil then out.heading = override.heading end
    if override.snap ~= nil then out.snap = override.snap end
    if override.anim ~= nil then out.anim = override.anim end
    if override.scenario ~= nil then out.scenario = override.scenario end
    if override.hideProp ~= nil then out.hideProp = override.hideProp == true end
    if override.preferScenario ~= nil then out.preferScenario = override.preferScenario == true end
    if override.scenarioHeading ~= nil then out.scenarioHeading = override.scenarioHeading end
    if override.props ~= nil then out.props = override.props end
    if override.placeAnim ~= nil then out.placeAnim = override.placeAnim == true end
    if override.inPlace ~= nil then out.inPlace = override.inPlace == true end
    if override.animOffset ~= nil then out.animOffset = override.animOffset end
    if override.animHeading ~= nil then out.animHeading = override.animHeading end
    if override.animRot ~= nil then out.animRot = override.animRot end

    return out
end

--[[
    The body's rotation for a placed exercise, as a full vector3.

    `animRot` when the entry gives one, and otherwise `animHeading` promoted into the Z slot.

    Both exist because a bench press only ever needed a heading - the body lies flat and turns
    to match the bench - so that is what shipped first. It turned out not to be enough: an
    incline bench, a rack and any machine the body leans into need PITCH as well, and there was
    no way to express it. `animHeading` stays because it is simpler for the common case and
    because config already written against it must keep working.
]]
function Equipment.bodyRotation(staging)
    if type(staging) ~= 'table' then return vector3(0.0, 0.0, 0.0) end

    if staging.animRot then
        return vector3(
            tonumber(staging.animRot.x) or 0.0,
            tonumber(staging.animRot.y) or 0.0,
            tonumber(staging.animRot.z) or 0.0)
    end

    return vector3(0.0, 0.0, tonumber(staging.animHeading) or 0.0)
end

--- The difficulty preset for `entry`, with its own `minigame` overrides merged in. Returns a
--- fresh table every call, so a caller may safely scale a field for one session.
function Equipment.difficulty(entry)
    local presets = Config.Minigame.difficulties
    local preset = presets[entry and entry.difficulty or ''] or presets.normal or {}
    local out = Sport.copy(preset)

    if type(entry) == 'table' and type(entry.minigame) == 'table' then
        Sport.merge(out, entry.minigame)
    end

    -- Defend the fields the minigame divides by or indexes with, so a hand-edited preset
    -- cannot produce a divide by zero or an endless rep.
    out.window = Sport.clamp(out.window, 200, 10000, 1250)
    out.restBetween = Sport.clamp(out.restBetween, 0, 10000, 750)
    out.keys = type(out.keys) == 'table' and out.keys or { 2, 3 }
    out.keys[1] = math.floor(Sport.clamp(out.keys[1], 1, 8, 2))
    out.keys[2] = math.floor(Sport.clamp(out.keys[2], out.keys[1], 8, out.keys[1]))
    out.perfectZone = type(out.perfectZone) == 'table' and out.perfectZone or { 0.60, 0.80 }
    out.goodZone = type(out.goodZone) == 'table' and out.goodZone or { 0.42, 0.95 }

    return out
end

--- The number of reps for `entry`, clamped. A catalogue entry with reps = 0 would finish
--- instantly and pay out in full, so the floor is 1.
function Equipment.reps(entry)
    return math.floor(Sport.clamp(entry and entry.reps, 1, 60, 8))
end

--[[
    The shortest time in milliseconds a session of `entry` can physically take.

    Shared because BOTH sides need it and they must agree: the client uses it for nothing at
    all, and the server multiplies it by Config.Security.minDurationFactor to reject a result
    that arrived faster than the reps could have been performed. Computing it twice, once per
    side, is how the two drift apart and start rejecting honest players.

    The fastest possible run presses every key the instant its good band opens, takes the
    minimum number of keys per rep, and never pauses.
]]
--[[
    The shortest time `reps` repetitions of this exercise could honestly take.

    `reps` IS AN ARGUMENT, and it was not, and that was a bug that rejected honest sessions.

    A workout can end early - four consecutive misses end it, and holding the cancel key stops it -
    and the server pays for the part that was done. That is deliberate and the README promises it.
    But this function only ever answered for the FULL rep count, so the duration check rejected any
    session that stopped early as "impossibly fast" and paid nothing, twenty lines above the code
    that handles partial completion. Two rules in one file disagreeing about the same feature.

    Passing the claimed reps costs nothing in cheat resistance: a client claiming twelve reps must
    still take twelve reps' worth of time, and claiming fewer pays proportionally less. There is no
    number a cheat can send that is both fast and worth anything.
]]
function Equipment.minimumDurationMs(entry, reps)
    local difficulty = Equipment.difficulty(entry)
    local total = Equipment.reps(entry)

    reps = math.floor(Sport.clamp(reps or total, 1, total, total))

    -- 110ms is the settle beat client/minigame.lua holds after each resolved key.
    local perKey = difficulty.window * (difficulty.goodZone[1] or 0.42) + 110
    return reps * difficulty.keys[1] * perKey + (reps - 1) * difficulty.restBetween
end

--- Seconds before the same player may use this equipment again.
function Equipment.cooldown(entry)
    local own = entry and tonumber(entry.cooldown)
    if own then return math.max(0, own) end
    return math.max(0, tonumber(Config.Security.defaultCooldown) or 0)
end

Equipment.build()
