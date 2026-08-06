fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'v-sport'
author 'vyrriox'
description 'Physical training for FiveM on qb-core, qbx_core, ESX and ox_core: every sport prop in the map becomes usable, a rhythm QTE drives the workout, and strength, lung capacity and stamina are trained, decay when unused, and can be pushed around by any other resource.'
version '1.0.0'

-- No hard dependency, on purpose. oxmysql, ox_target, qb-target, qtarget, ox_lib,
-- interact-sound and every framework are detected at runtime and all optional.
-- See config.lua -> Config.Compat, bridge/client/compat.lua and bridge/server/framework.lua.
--
-- Without oxmysql the resource still runs: stats live in memory for the session and are
-- announced as unsaved in the console once, at boot. That is a supported configuration.

shared_scripts {
    -- The shared core first: it defines `Sport` (maths, clamping, time) and the locale
    -- helper that every file below is written against.
    'bridge/shared/sport.lua',
    'bridge/shared/locale.lua',

    -- English first: it is the fallback for any key missing from another locale, so it is
    -- the base table the others are read against.
    'locales/en.lua',
    'locales/fr.lua',

    'config.lua',

    -- The equipment catalogue is a config file in everything but name. It reads Config for
    -- its difficulty presets, so it loads after it.
    'shared/equipment.lua',

    -- The shape of a live equipment addition, and the vector3-to-JSON conversion both sides
    -- share. After equipment.lua, which owns the overlay it feeds.
    'shared/custom.lua',

    -- The progression, decay and level maths. Shared because the server computes them and
    -- the client displays them: one implementation, no drift between the two.
    'shared/stats.lua',
}

client_scripts {
    -- Runtime detection of everything optional. FIRST, because every client file below
    -- asks it what is installed.
    'bridge/client/compat.lua',

    -- The native drawing primitives. Before anything that draws.
    'client/ui.lua',

    'client/state.lua',
    'client/effects.lua',
    'client/detect.lua',
    'client/minigame.lua',
    'client/session.lua',
    -- After session.lua: the interaction layer starts sessions, so the function has to
    -- exist by the time a target option or a key press can fire.
    'client/interact.lua',
    'client/passive.lua',
    'client/menu.lua',
    -- The live alignment tool. After session.lua, because it reuses the same staging data, and
    -- before commands.lua only for readability - it registers its own command.
    'client/tune.lua',
    -- The staff commands for adding equipment. After tune.lua, whose save key calls into the
    -- same server events, and after detect.lua, whose index it invalidates on a change.
    'client/custom.lua',
    'client/commands.lua',
}

server_scripts {
    'bridge/server/framework.lua',
    'server/database.lua',
    'server/stats.lua',
    'server/session.lua',
    'server/api.lua',
    -- After api.lua: the item handlers call the exports it registers.
    'server/items.lua',
    'server/commands.lua',
    -- Owns data/custom.json and authorises every change to it. After commands.lua, which
    -- registers the admin gate this one re-checks.
    'server/custom.lua',
}

-- The SQL is shipped for operators who prefer to import a schema by hand. The table is
-- created on first start when it is missing, so importing it is optional.
--
-- data/custom.json holds the equipment added in game. It is listed so that SaveResourceFile can
-- write it and LoadResourceFile can read it back; it does not exist until something is added.
files {
    'sql/v_sport.sql',
    'data/custom.json',
}
