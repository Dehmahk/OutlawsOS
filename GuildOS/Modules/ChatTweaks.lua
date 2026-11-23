----------------------------------------------------------------------
-- Guild OS - Chat Tweaks
-- Optional guild/officer chat annotations (class icon + level + alt tag),
-- added as a safe MESSAGE PREFIX (never modifies the author/name link).
-- Off by default. Cache refreshed on GUILD_ROSTER_UPDATE, never per line.
----------------------------------------------------------------------
local ChatTweaks = {}
GuildOS.ChatTweaks = ChatTweaks

ChatTweaks.DEFAULTS = {
    enabled   = true,
    guild     = true,
    officer   = true,
    classIcon = true,
    level     = true,
    altTag    = true,
    altShort  = false,   -- "[Floyd]" / "[M]" instead of "(alt of Floyd)" (#269)
    rank      = true,    -- a symbol for the guild ranks listed in RANK_ICON, and for the EKO roles in ROLE_ICON
}

-- The symbol of each guild rank, by the rank's name in the guild (English names). Guild Master has
-- its own medallion (Media/rank_gm.tga); GM Alt and Co-Guild Master get the crown; Officer has its own medallion (Media/rank_officer.tga); Raid Marshal has its own medallion (Media/rank_raidmarshal.tga);
-- Veteran Outlaw has its own medallion (Media/rank_vo.tga). Other ranks (Herald, Alter Ego, Outlaw, Recruit, and any rank not listed) get none.
ChatTweaks.RANK_ICON = {
    ["Guild Master"]      = "Interface\\AddOns\\GuildOS\\Media\\rank_gm.tga",
    ["GM Alt"]            = "Interface\\GroupFrame\\UI-Group-LeaderIcon",
    ["Co-Guild Master"]   = "Interface\\GroupFrame\\UI-Group-LeaderIcon",
    ["Officer"]           = "Interface\\AddOns\\GuildOS\\Media\\rank_officer.tga",
    ["Raid Marshal"]      = "Interface\\AddOns\\GuildOS\\Media\\rank_raidmarshal.tga",
    ["Veteran Outlaw"]    = "Interface\\AddOns\\GuildOS\\Media\\rank_vo.tga",
}

-- The symbol of each EKO role, by the role's name in EKO.LEADERS. Recruiter has its own medallion
-- (Media/rank_recruiter.tga); Event Organizer has its own (Media/rank_eventorganizer.tga). Other roles get none.
ChatTweaks.ROLE_ICON = {
    ["Recruiter"]         = "Interface\\AddOns\\GuildOS\\Media\\rank_recruiter.tga",
    ["Event Organizer"]   = "Interface\\AddOns\\GuildOS\\Media\\rank_eventorganizer.tga",
}

local CLASS_TEX = "Interface\\WorldStateFrame\\Icons-Classes"

function ChatTweaks:Initialize()
    GuildOS.db.chatTweaks = GuildOS.db.chatTweaks or {}
    for k, v in pairs(self.DEFAULTS) do
        if GuildOS.db.chatTweaks[k] == nil then GuildOS.db.chatTweaks[k] = v end
    end
    self._cache = {}

    local f = CreateFrame("Frame")
    GuildOS.Compat.RegisterEvent(f, "GUILD_ROSTER_UPDATE")
    -- A pass over the whole roster: at most one every ROSTER_GAP seconds (issue #324).
    f:SetScript("OnEvent", function()
        GuildOS:Coalesce("chatTweaks", GuildOS.ROSTER_GAP, ChatTweaks.TimedRefresh)
    end)

    self:_RegisterFilters()
    self:_RegisterTests()
end

function ChatTweaks.TimedRefresh()
    local t = GuildOS.Perf:Start()
    ChatTweaks:_RefreshCache()
    GuildOS.Perf:Stop("roster chat cache", t)
end

function ChatTweaks:_RefreshCache()
    local cache = {}
    local roles = {}
    for _, l in ipairs((GuildOS.EKO and GuildOS.EKO.LEADERS) or {}) do roles[l.name] = l.role end
    local n = GetNumGuildMembers() or 0
    for i = 1, n do
        local name, rankName, _, level, _, _, _, _, _, _, classFile = GetGuildRosterInfo(i)
        if name then
            local short = name:match("^([^-]+)") or name
            local realm = name:match("-(.+)$") or GetRealmName()
            cache[short] = { classFile = classFile, level = level, rankName = rankName, role = roles[short], fullKey = GuildOS:GetPlayerKey(short, realm) }
        end
    end
    self._cache = cache
end

----------------------------------------------------------------------
-- Pure prefix building (unit-tested)
----------------------------------------------------------------------
function ChatTweaks:_ClassIcon(classFile)
    local c = CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[classFile]
    if not c then return "" end
    return string.format("|T%s:14:14:0:0:256:256:%d:%d:%d:%d|t",
        CLASS_TEX, c[1] * 256, c[2] * 256, c[3] * 256, c[4] * 256)
end

function ChatTweaks:_RankIcon(rankName)
    local tex = rankName and self.RANK_ICON[rankName]
    if not tex then return "" end
    return string.format("|T%s:18:18:0:0|t", tex)
end

function ChatTweaks:_RoleIcon(role)
    local tex = role and self.ROLE_ICON[role]
    if not tex then return "" end
    return string.format("|T%s:18:18:0:0|t", tex)
end

function ChatTweaks:_BuildPrefix(info, cfg)
    if not info then return "" end
    local parts = {}
    if cfg.rank and info.rankName then
        local sym = self:_RankIcon(info.rankName)
        if sym ~= "" then parts[#parts + 1] = sym end
    end
    if cfg.rank and info.role then
        local sym = self:_RoleIcon(info.role)
        if sym ~= "" then parts[#parts + 1] = sym end
    end
    if cfg.classIcon and info.classFile then
        local ic = self:_ClassIcon(info.classFile)
        if ic ~= "" then parts[#parts + 1] = ic end
    end
    if cfg.level and info.level and info.level > 0 then
        parts[#parts + 1] = "[" .. info.level .. "]"
    end
    if cfg.altTag and cfg.altShort then
        if info.shortTag then parts[#parts + 1] = "|cff888888" .. info.shortTag .. "|r" end
    elseif cfg.altTag and info.altTag then
        parts[#parts + 1] = "|cff888888(" .. info.altTag .. ")|r"
    end
    return table.concat(parts, " ")
end

----------------------------------------------------------------------
-- Chat filters (message-prefix only; returns false = keep line, modified)
----------------------------------------------------------------------
function ChatTweaks:_MakeFilter()
    return function(_, _, msg, author, ...)
        local cfg = GuildOS.db.chatTweaks
        if not cfg or not cfg.enabled then return false end
        local short = author and (author:match("^([^-]+)") or author)
        local cached = short and ChatTweaks._cache[short]
        if not cached then return false end
        local info = {
            classFile = cached.classFile,
            level     = cached.level,
            rankName  = cached.rankName,
            role      = cached.role,
            altTag    = (GuildOS.GetAltTag and cached.fullKey) and GuildOS:GetAltTag(cached.fullKey) or nil,
            shortTag  = (cfg.altShort and GuildOS.AltRoster and cached.fullKey) and GuildOS.AltRoster:ShortTag(cached.fullKey) or nil,
        }
        local prefix = ChatTweaks:_BuildPrefix(info, cfg)
        if prefix == "" then return false end
        return false, prefix .. " " .. msg, author, ...
    end
end

function ChatTweaks:_RegisterFilters()
    if not ChatFrame_AddMessageEventFilter then return end
    if GuildOS.db.chatTweaks.guild ~= false then
        ChatFrame_AddMessageEventFilter("CHAT_MSG_GUILD", self:_MakeFilter())
    end
    if GuildOS.db.chatTweaks.officer ~= false then
        ChatFrame_AddMessageEventFilter("CHAT_MSG_OFFICER", self:_MakeFilter())
    end
end

----------------------------------------------------------------------
-- Self-tests
----------------------------------------------------------------------
function ChatTweaks:_RegisterTests()
    if not GuildOS.SelfTest then return end
    local S = GuildOS.SelfTest
    local cfg = { classIcon = true, level = true, altTag = true }
    S:Register("chattweaks.level", function()
        local p = ChatTweaks:_BuildPrefix({ level = 70 }, cfg)
        if not p:find("[70]", 1, true) then return false, p end
        return true
    end)
    S:Register("chattweaks.alttag", function()
        local p = ChatTweaks:_BuildPrefix({ altTag = "alt of Main" }, cfg)
        if not p:find("alt of Main", 1, true) then return false, p end
        return true
    end)
    S:Register("chattweaks.rank", function()
        local rcfg = { rank = true }
        local p = ChatTweaks:_BuildPrefix({ rankName = "Guild Master" }, rcfg)
        if p == "" or not p:find("rank_gm.tga", 1, true) then return false, p end
        if ChatTweaks:_BuildPrefix({ rankName = "Recruit" }, rcfg) ~= "" then return false, "Recruit has a symbol" end
        return true
    end)
    S:Register("chattweaks.role", function()
        local p = ChatTweaks:_BuildPrefix({ rankName = "Herald", role = "Recruiter" }, { rank = true })
        if not p:find("rank_recruiter.tga", 1, true) or p:find("MainTankIcon", 1, true) then return false, p end
        if ChatTweaks:_BuildPrefix({ rankName = "Herald" }, { rank = true }) ~= "" then return false, "Herald has a symbol" end
        if ChatTweaks:_BuildPrefix({ role = "Officer" }, { rank = true }) ~= "" then return false, "Officer role has a symbol" end
        if not ChatTweaks:_BuildPrefix({ role = "Event Organizer" }, { rank = true }):find("rank_eventorganizer.tga", 1, true) then return false, "Event Organizer has no symbol" end
        return true
    end)
    S:Register("chattweaks.off", function()
        local p = ChatTweaks:_BuildPrefix({ level = 70 }, { level = false })
        if p ~= "" then return false, "toggles off => empty" end
        return true
    end)
    S:Register("chattweaks.nil_info", function()
        if ChatTweaks:_BuildPrefix(nil, cfg) ~= "" then return false end
        return true
    end)
end
