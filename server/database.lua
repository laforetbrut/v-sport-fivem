--[[
    server/database.lua

    Persistence, through oxmysql when it is installed and through nothing at all when it is
    not.

    ---------------------------------------------------------------------------------------
    WHY THERE IS NO `@oxmysql/lib/MySQL.lua` IN THE MANIFEST
    ---------------------------------------------------------------------------------------

    A `server_script '@oxmysql/lib/MySQL.lua'` is a HARD dependency: the resource fails to
    start at all when oxmysql is missing, with an error that does not say why. Going through
    `exports.oxmysql` instead means a server without a database still boots, still trains,
    still shows the panel, and says so once in the console. Progress is lost on restart,
    which is a bad configuration - but it is a configuration somebody can diagnose.

    mysql-async and ghmattimysql are accepted as a fallback for older servers.

    Every query is wrapped in a promise so the callers read as straight-line code, and every
    one is guarded: a database that goes away mid-session must degrade to "not saved", never
    take a player's load path down.
]]

Database = {}

local driver                    -- 'oxmysql' | 'mysql-async' | nil
local ready = false
local warned = false

local TABLE = 'v_sport_stats'

local function started(resource)
    local state = GetResourceState(resource)
    return state == 'started' or state == 'starting'
end

-- ---------------------------------------------------------------------------------------
-- Driver
-- ---------------------------------------------------------------------------------------

local function detect()
    if started('oxmysql') then
        driver = 'oxmysql'
    elseif started('mysql-async') then
        driver = 'mysql-async'
    elseif started('ghmattimysql') then
        driver = 'ghmattimysql'
    else
        driver = nil
    end

    return driver
end

--- Whether anything is being persisted. Callers use this to decide whether to warn the
--- player, not to decide whether to keep working: everything works either way.
function Database.available()
    return ready and driver ~= nil
end

function Database.driverName()
    return driver or 'none'
end

-- ---------------------------------------------------------------------------------------
-- Queries
-- ---------------------------------------------------------------------------------------

--[[
    Run a query and wait for it.

    Returns the result, or nil on any failure. `nil` is deliberately indistinguishable from
    "no rows" here: every caller treats both as "this character has no saved row", which is
    the correct behaviour for a new character and the safe behaviour for a broken database.
]]
local function query(sql, params)
    if not driver then return nil end

    local p = promise.new()
    local settled = false

    local function settle(value)
        if settled then return end
        settled = true
        p:resolve(value)
    end

    local ok = pcall(function()
        if driver == 'oxmysql' then
            exports.oxmysql:query(sql, params or {}, function(result)
                settle(result)
            end)
        elseif driver == 'mysql-async' then
            exports['mysql-async']:mysql_fetch_all(sql, params or {}, function(result)
                settle(result)
            end)
        else
            exports.ghmattimysql:execute(sql, params or {}, function(result)
                settle(result)
            end)
        end
    end)

    if not ok then
        settle(nil)
        Sport.warn('a database query threw; persistence is degraded')
        return nil
    end

    -- A driver that never calls back would hang the calling thread forever. Ten seconds is
    -- far longer than any of these queries and far shorter than a player will wait.
    SetTimeout(10000, function()
        if not settled then
            settled = true
            Sport.warn('a database query timed out after 10s')
            p:resolve(nil)
        end
    end)

    return Citizen.Await(p)
end

--- Fire and forget. Used by the flush, which has nothing to do with the result and must not
--- block the timer thread behind two hundred round trips.
local function execute(sql, params)
    if not driver then return end

    pcall(function()
        if driver == 'oxmysql' then
            exports.oxmysql:execute(sql, params or {})
        elseif driver == 'mysql-async' then
            exports['mysql-async']:mysql_execute(sql, params or {})
        else
            exports.ghmattimysql:execute(sql, params or {})
        end
    end)
end

-- ---------------------------------------------------------------------------------------
-- Schema
-- ---------------------------------------------------------------------------------------

--[[
    The table.

    LONGTEXT columns holding JSON rather than one column per stat, and that is deliberate:
    adding a fourth stat in Config.Stats has to be a config change, and a schema with a
    `strength` column would make it a migration. The cost is that you cannot ORDER BY
    strength in SQL, which is why Database.leaderboard exists.
]]
local SCHEMA = ([[
CREATE TABLE IF NOT EXISTS `%s` (
    `identifier`      VARCHAR(64)  NOT NULL,
    `stats`           LONGTEXT     NOT NULL,
    `peak`            LONGTEXT     NOT NULL,
    `decay_anchor`    LONGTEXT     NOT NULL,
    `allowance`       LONGTEXT     NOT NULL,
    `last_session`    BIGINT       NOT NULL DEFAULT 0,
    `total_sessions`  INT          NOT NULL DEFAULT 0,
    `recovery_until`  BIGINT       NOT NULL DEFAULT 0,
    `created_at`      TIMESTAMP    NOT NULL DEFAULT CURRENT_TIMESTAMP,
    `updated_at`      TIMESTAMP    NOT NULL DEFAULT CURRENT_TIMESTAMP
                                   ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (`identifier`),
    KEY `idx_last_session` (`last_session`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
]]):format(TABLE)

-- ---------------------------------------------------------------------------------------
-- Boot
-- ---------------------------------------------------------------------------------------

CreateThread(function()
    TABLE = Config.Persistence.table or 'v_sport_stats'

    -- Guard the table name. It is interpolated into every statement below rather than bound
    -- as a parameter, because SQL will not let a table name be a placeholder. So it has to
    -- be proved safe HERE, once, rather than trusted.
    if not TABLE:match('^[%w_]+$') then
        Sport.warn(("Config.Persistence.table '%s' is not a plain identifier; refusing to use it")
            :format(TABLE))
        ready = true
        return
    end

    -- Give the database resource time to come up. A query fired at a starting oxmysql fails
    -- in a way that looks like a missing table.
    Wait(2000)

    if not detect() then
        Sport.warn('no database resource found (oxmysql, mysql-async, ghmattimysql).')
        Sport.warn('training works, but NOTHING IS SAVED. Install oxmysql to keep progress.')
        ready = true
        return
    end

    if Config.Persistence.autoCreateTable then
        query(SCHEMA:gsub('`' .. 'v_sport_stats' .. '`', '`' .. TABLE .. '`'))
    end

    -- Prove the table is actually usable rather than assuming the CREATE worked. A database
    -- user without DDL rights gets a clear message instead of a silent no-op on every save.
    local probe = query(('SELECT 1 FROM `%s` LIMIT 1'):format(TABLE))
    if probe == nil then
        Sport.warn(('table `%s` is not readable. Import sql/v_sport.sql by hand, or grant'):format(TABLE))
        Sport.warn('the database user CREATE rights and restart. Progress is NOT being saved.')
        driver = nil
        ready = true
        return
    end

    ready = true
    Sport.print(('persistence: %s, table `%s`'):format(driver, TABLE))

    -- Prune, once, at boot. Never on a timer: it is a full table scan and there is no reason
    -- to run it more than once per restart.
    local days = math.floor(tonumber(Config.Persistence.pruneAfterDays) or 0)
    if days > 0 then
        execute(('DELETE FROM `%s` WHERE `last_session` > 0 AND `last_session` < ?'):format(TABLE),
            { Sport.now() - days * 86400 })
        Sport.print(('pruning rows untouched for %d days'):format(days))
    end
end)

--- Wait until the driver has been resolved one way or the other. Callers use it so the first
--- player to join a freshly started server does not race the boot thread.
function Database.waitReady()
    local attempts = 0
    while not ready and attempts < 100 do
        Wait(100)
        attempts = attempts + 1
    end
    return ready
end

-- ---------------------------------------------------------------------------------------
-- Rows
-- ---------------------------------------------------------------------------------------

--- Load one character's row, or nil when there is none. Every JSON column is decoded
--- defensively: a hand-edited row degrades to a default rather than to an error.
function Database.load(identifier)
    -- No database at all, or a bad identifier: not a failure to retry, just nothing to load.
    if not Database.available() or type(identifier) ~= 'string' or identifier == '' then
        return nil, true
    end

    local rows = query(([[
        SELECT `stats`, `peak`, `decay_anchor`, `allowance`, `last_session`,
               `total_sessions`, `recovery_until`
        FROM `%s` WHERE `identifier` = ? LIMIT 1
    ]]):format(TABLE), { identifier })

    --[[
        THREE OUTCOMES, NOT TWO. Returns `row, ok`.

        A failed or timed-out query and a character with no row both used to answer plain nil, and
        the caller read that as "new character" - so one slow query during a join installed a blank
        profile, and the next autosave wrote those zeroes over a real saved row. A player could lose
        everything to a database hiccup and nothing would say so.

        Every supported driver returns an empty TABLE for zero rows, so nil genuinely does mean the
        query did not answer. `ok = false` tells the caller to leave the profile alone.
    ]]
    if rows == nil then return nil, false end
    if type(rows) ~= 'table' or not rows[1] then return nil, true end

    local row = rows[1]

    return {
        stats = Sport.decode(row.stats, nil),
        peak = Sport.decode(row.peak, {}),
        decayAnchor = Sport.decode(row.decay_anchor, {}),
        allowance = Sport.decode(row.allowance, {}),
        lastSession = tonumber(row.last_session) or 0,
        totalSessions = tonumber(row.total_sessions) or 0,
        recoveryUntil = tonumber(row.recovery_until) or 0,
    }, true
end

--[[
    Write one character's row.

    An upsert rather than a SELECT-then-INSERT-or-UPDATE, so there is no window in which two
    saves for the same character both decide the row does not exist.
]]
function Database.save(identifier, profile)
    if not Database.available() or type(identifier) ~= 'string' or identifier == '' then
        return false
    end
    if type(profile) ~= 'table' then return false end

    execute(([[
        INSERT INTO `%s`
            (`identifier`, `stats`, `peak`, `decay_anchor`, `allowance`,
             `last_session`, `total_sessions`, `recovery_until`)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?)
        ON DUPLICATE KEY UPDATE
            `stats`          = VALUES(`stats`),
            `peak`           = VALUES(`peak`),
            `decay_anchor`   = VALUES(`decay_anchor`),
            `allowance`      = VALUES(`allowance`),
            `last_session`   = VALUES(`last_session`),
            `total_sessions` = VALUES(`total_sessions`),
            `recovery_until` = VALUES(`recovery_until`)
    ]]):format(TABLE), {
        identifier,
        Sport.encode(profile.stats or {}),
        Sport.encode(profile.peak or {}),
        Sport.encode(profile.decayAnchor or {}),
        Sport.encode(profile.allowance or {}),
        math.floor(tonumber(profile.lastSession) or 0),
        math.floor(tonumber(profile.totalSessions) or 0),
        math.floor(tonumber(profile.recoveryUntil) or 0),
    })

    return true
end

--- Delete a character's row entirely. Only the admin command calls this.
function Database.delete(identifier)
    if not Database.available() or type(identifier) ~= 'string' or identifier == '' then
        return false
    end

    execute(('DELETE FROM `%s` WHERE `identifier` = ?'):format(TABLE), { identifier })
    return true
end

--[[
    The top `limit` characters by one stat.

    The stats are a JSON blob, so this cannot be an ORDER BY. It reads the rows and sorts in
    Lua, which is fine for a leaderboard on a server with thousands of characters and would
    not be for anything called per frame - hence the hard cap on how many rows come back.
]]
function Database.leaderboard(statKey, limit)
    if not Database.available() then return {} end
    if not Stats.def(statKey) then return {} end

    local rows = query(([[
        SELECT `identifier`, `stats` FROM `%s`
        WHERE `last_session` > 0
        ORDER BY `last_session` DESC
        LIMIT 2000
    ]]):format(TABLE))

    if type(rows) ~= 'table' then return {} end

    local out = {}
    for _, row in ipairs(rows) do
        local stats = Sport.decode(row.stats, nil)
        local value = stats and tonumber(stats[statKey])
        if value then
            out[#out + 1] = { identifier = row.identifier, value = value }
        end
    end

    table.sort(out, function(a, b) return a.value > b.value end)

    local capped = {}
    for index = 1, math.min(#out, math.max(1, math.floor(tonumber(limit) or 10))) do
        capped[index] = out[index]
    end

    return capped
end
