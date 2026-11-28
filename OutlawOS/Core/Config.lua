----------------------------------------------------------------------
-- Guild OS - Configuration
-- Single source of truth for all addon-wide constants.
-- This file is loaded first (before Core.lua) so every module can
-- safely reference GuildOS.* constants from the start.
----------------------------------------------------------------------

-- Create the primary namespace. Using "or {}" is idempotent — safe to
-- call even if a future loader has already created the table.
--
_G.GuildOS = _G.GuildOS or {}
-- The addon is OutlawOS now. GuildOS stays as the internal name, so saved data, the guild's sync and
-- every addon that reads GuildOS keep working; this is the same table under its new name.
_G.OutlawOS = _G.GuildOS

-- ── Product identity ─────────────────────────────────────────────
GuildOS.ADDON_NAME        = "OutlawOS"
GuildOS.NAMESPACE         = "GuildOS"

-- ── Version ───────────────────────────────────────────────────────
GuildOS.VERSION           = "1.41.43"  -- kept in sync with GuildOS.toc by the release workflow
GuildOS.COMM_VERSION      = 1

-- ── SavedVariables ────────────────────────────────────────────────
GuildOS.DB_GLOBAL         = "GuildOSDB"

-- ── Communication prefixes ────────────────────────────────────────
GuildOS.PREFIX            = "GUILDOS"

-- ── Slash commands ────────────────────────────────────────────────
GuildOS.SLASH_PRIMARY     = "/outlawos"
