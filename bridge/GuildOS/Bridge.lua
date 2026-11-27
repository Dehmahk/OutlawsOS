-- OutlawOS companion bridge. Only marks itself so OutlawOS does not mistake this folder for the old
-- GuildOS addon. The companion app replaces Inbox.lua next to this file; OutlawOS imports it.
GuildOSBridge = true
-- The toc also lists GuildOSDB as saved data, so the game keeps writing SavedVariables\GuildOS.lua, the file the
-- companion reads. OutlawOS loads after this and its own save wins, so there is one set of data, written twice.
