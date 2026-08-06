-- ===========================================================================================
-- v-sport
-- ===========================================================================================
--
-- IMPORTING THIS IS OPTIONAL. The table is created on first start when it does not exist.
-- Import it by hand when your database user is not allowed to run CREATE TABLE, and set
-- Config.Persistence.autoCreateTable = false so the resource does not try.
--
-- Rename the table here AND in Config.Persistence.table if you want it called something else.
--
-- -------------------------------------------------------------------------------------------
-- WHY JSON COLUMNS INSTEAD OF ONE COLUMN PER STAT
-- -------------------------------------------------------------------------------------------
--
-- Adding a fourth stat to Config.Stats has to be a config change, not a database migration.
-- A schema with `strength`, `breath` and `stamina` columns would make every new stat a
-- migration and every removed stat a dead column.
--
-- The cost is that you cannot `ORDER BY strength` in SQL. The leaderboard export reads rows
-- and sorts them in Lua instead, which is why it is capped at two thousand rows.
-- ===========================================================================================

CREATE TABLE IF NOT EXISTS `v_sport_stats` (
    -- The character key. qb citizenid, ESX identifier, ox stateId, or the Rockstar licence
    -- when Config.Persistence.scope is 'license' or no framework is running.
    `identifier`      VARCHAR(64)  NOT NULL,

    -- { "strength": 42.5, "breath": 10.0, "stamina": 31.25 }
    `stats`           LONGTEXT     NOT NULL,

    -- The highest value ever reached per stat, for Config.Decay.peakProtection.
    `peak`            LONGTEXT     NOT NULL,

    -- Per stat, the timestamp decay has already been charged up to. This is what makes
    -- offline decay idempotent: it cannot bill the same day twice.
    `decay_anchor`    LONGTEXT     NOT NULL,

    -- The training allowance ledger:
    -- { "cycleStart": 1700000000, "entries": [ { "at": ..., "stat": "...", "amount": 1.2 } ] }
    `allowance`       LONGTEXT     NOT NULL,

    -- Unix seconds. When the character last finished a session; the decay clock starts here.
    `last_session`    BIGINT       NOT NULL DEFAULT 0,

    `total_sessions`  INT          NOT NULL DEFAULT 0,

    -- Unix seconds. Whey and anything else calling ReduceRecovery puts the shortened
    -- allowance window in effect until this time.
    `recovery_until`  BIGINT       NOT NULL DEFAULT 0,

    `created_at`      TIMESTAMP    NOT NULL DEFAULT CURRENT_TIMESTAMP,
    `updated_at`      TIMESTAMP    NOT NULL DEFAULT CURRENT_TIMESTAMP
                                   ON UPDATE CURRENT_TIMESTAMP,

    PRIMARY KEY (`identifier`),

    -- Only used by the boot-time prune (Config.Persistence.pruneAfterDays).
    KEY `idx_last_session` (`last_session`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
