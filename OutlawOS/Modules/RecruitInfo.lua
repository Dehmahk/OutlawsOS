----------------------------------------------------------------------
-- Guild OS - Recruit info
-- The guild's own words for recruits, at the bottom of the Recruiting tab: the raid schedule, the
-- expectations, the ranks, and the content progress are text that an officer of the right rank edits
-- live. Every edit is sent to the other OutlawOS users (SyncService, domain "recruitinfo"), and a
-- client takes an edit only from a sender whose rank may make it. The roles needed, the upcoming
-- events and the links are read from the addon's own data; nothing here is typed in for them.
-- Every rule is here; UI/RosterFrame.lua draws the section and calls these.
----------------------------------------------------------------------
local RI = {}
GuildOS.RecruitInfo = RI
local L = GuildOS.L

-- Rank names as the game gives them, highest first. Who may edit each section.
local OFFICER_PLUS = { "Guild Master", "Co-Guild Master", "Officer" }
local RAID_PLUS    = { "Guild Master", "Co-Guild Master", "Officer", "Raid Marshal" }
local GM_ONLY      = { "Guild Master" }

RI.SECTIONS = {
    schedule     = { editors = RAID_PLUS, limit = 600 },
    expectations = { editors = OFFICER_PLUS, limit = 1000 },
    ranks        = { editors = GM_ONLY, limit = 1000 },
    progress     = { editors = RAID_PLUS, limit = 600 },
}

local editorSets = {}
for key, sec in pairs(RI.SECTIONS) do
    local set = {}
    for _, name in ipairs(sec.editors) do set[name] = true end
    editorSets[key] = set
end

local listeners = {}
function RI:Listen(fn) listeners[#listeners + 1] = fn end
local function changed()
    for _, fn in ipairs(listeners) do GuildOS:SafeCall(fn) end
end

local function now() return GetServerTime() end
local function me() return GuildOS.Compat.PlayerName() or "" end
local function store()
    GuildOS.db.recruitInfo = GuildOS.db.recruitInfo or {}
    return GuildOS.db.recruitInfo
end

-- A player's rank by the roster, for an edit that came from them. Nil when they are not in the guild.
local function rankOfMember(fullName)
    if not IsInGuild() or not fullName or fullName == "" then return nil end
    local want = GuildOS:KeyOfRosterName(fullName)
    for i = 1, GetNumGuildMembers() or 0 do
        local name, rank = GetGuildRosterInfo(i)
        if name and GuildOS:KeyOfRosterName(name) == want then return rank end
    end
    return nil
end

-- Whether a rank may edit a section.
function RI:RankMayEdit(key, rank)
    local set = editorSets[key]
    return set ~= nil and rank ~= nil and set[rank] == true
end

-- Whether this character may edit a section, by its own rank.
function RI:CanEdit(key)
    local _, rank = GetGuildInfo("player")
    return self:RankMayEdit(key, rank)
end

function RI:Text(key)
    local rec = store()[key]
    return (rec and rec.text) or ""
end

-- Who edited it last and when, for the line under the section.
function RI:Edited(key)
    local rec = store()[key]
    if not rec or not rec.at then return nil end
    return rec.by, rec.at
end

----------------------------------------------------------------------
-- Sending
----------------------------------------------------------------------
function RI:Save(key, text)
    if not self.SECTIONS[key] or not self:CanEdit(key) then return false end
    text = tostring(text or ""):gsub("\r", ""):gsub("^%s+", ""):gsub("%s+$", "")
    text = text:sub(1, self.SECTIONS[key].limit)
    local SS = GuildOS.SyncService
    local rec = { text = text, by = me(), at = now() }
    store()[key] = rec
    if SS then
        local rev = math.max(SS:GetRevision("recruitinfo", key) + 1, now())
        SS:SetRevision("recruitinfo", key, rev)
        SS:Publish("recruitinfo", "set", { key = key, text = text, by = rec.by, at = rec.at }, { rev = rev })
    end
    changed()
    return true
end

----------------------------------------------------------------------
-- Receiving: an edit is kept only if its sender may make it, by the roster, and it is newer.
----------------------------------------------------------------------
function RI:OnSync(env, sender)
    local d = env.data
    if env.act ~= "set" or type(d) ~= "table" or type(d.key) ~= "string" or type(d.text) ~= "string" then return end
    local sec = self.SECTIONS[d.key]
    if not sec then return end
    if not self:RankMayEdit(d.key, rankOfMember(sender)) then return end
    local SS = GuildOS.SyncService
    if SS and not SS:ShouldApply("recruitinfo", d.key, env.rev) then return end
    store()[d.key] = {
        text = d.text:sub(1, sec.limit),
        by = tostring(d.by or sender or ""):sub(1, 48),
        at = tonumber(d.at) or 0,
    }
    if SS and env.rev then SS:SetRevision("recruitinfo", d.key, env.rev) end
    changed()
end

----------------------------------------------------------------------
-- Read from the addon's own data
----------------------------------------------------------------------
-- The roles and classes the Recruit Beacon ad is looking for, while the ad is on.
function RI:NeedsText()
    local RB = GuildOS.RecruitBeacon
    local ad = RB and RB.GetAd and RB:GetAd()
    if not (ad and ad.enabled) then return nil end
    local names = {}
    local roleName = { TANK = L["Tank"], HEALER = L["Healer"], DPS = L["DPS"] }
    for _, token in ipairs({ "TANK", "HEALER", "DPS" }) do
        if ad.needs[token] then names[#names + 1] = roleName[token] end
    end
    local classes = {}
    for token, on in pairs(ad.needs) do
        if on and not roleName[token] then
            classes[#classes + 1] = (LOCALIZED_CLASS_NAMES_MALE and LOCALIZED_CLASS_NAMES_MALE[token]) or token
        end
    end
    table.sort(classes)
    for _, c in ipairs(classes) do names[#names + 1] = c end
    return #names > 0 and table.concat(names, ", ") or nil
end

-- The next few events on the calendar, a line each.
function RI:EventsText(count)
    local cal = GuildOS.Calendar
    local list = cal and cal.GetUpcoming and cal:GetUpcoming(false) or {}
    local lines = {}
    for i = 1, math.min(count or 5, #list) do
        local e = list[i]
        lines[#lines + 1] = string.format("%s, %s", e.title or "", GuildOS:LocalDate("%a %d %b %H:%M", e.when or 0))
    end
    return lines
end

-- The Discord invite the recruiting settings hold, and the site.
function RI:Links()
    local r = GuildOS.db and GuildOS.db.recruitment or {}
    return r.discord or "", "https://guildos.me"
end

-- Start-up: the other officers' edits arrive over the guild's sync.
function RI:Initialize()
    if self._started then return end
    self._started = true
    if GuildOS.SyncService then
        GuildOS.SyncService:On("recruitinfo", function(env, sender) RI:OnSync(env, sender) end)
    end
end
