----------------------------------------------------------------------
-- Guild OS - Alliance observers
--
-- A guildless player an alliance lets WATCH it, read-only: each guild's leaders
-- online, and the upcoming alliance events with who has signed up. An observer
-- is never given the alliance code, so nothing they send is believed by the
-- alliance. Their client only ever changes its own copy.
--
--   sponsor  : an ambassador who granted access (/outlawos ally observe <name>) or
--              accepted an alliance application. It keeps the list of who it
--              granted and whispers each one a snapshot on a timer.
--   observer : a guildless character with a read-only copy of the alliance's
--              name and tag. It takes snapshots only from the one character
--              that granted it, and only when that character is an ambassador.
--
-- A grant is a dialog the player accepts, like an alliance invite. The feed is
-- one named character: when that character is offline the snapshot goes stale,
-- and the frame shows its age. That is a known limit of v1.
--
-- Wire ops (whisper on the ChehulAlly channel, read before any pact gate):
--   OBS   sponsor -> observer   a grant: the alliance's tag, name and sponsor guild
--   OBSX  sponsor -> observer   access removed
--   OBSD  sponsor -> observer   a snapshot: leaders per guild, upcoming events
--   OBSA  observer -> sponsor   accepted; the sponsor sends a snapshot straight away
----------------------------------------------------------------------
local AO = {}
GuildOS.AllianceObserver = AO

local L = GuildOS.L

AO.TICK            = 300   -- seconds between snapshots to each observer
AO.MAX_OBSERVERS   = 10
AO.PROMPT_COOLDOWN = 60    -- seconds before the same sender may prompt again
AO.GUILD_CAP       = 10    -- guilds kept in one snapshot
AO.LEADER_CAP      = 30    -- leaders kept per guild
AO.EVENT_CAP       = 40    -- events kept in one snapshot
AO.NAME_CAP        = 20    -- signups kept per event

local function now() return (GetServerTime and GetServerTime()) or time() end
local function display(name) return (name or ""):match("^([^-]+)") or name or "" end
local function short(name) return string.lower(display(name)) end
local function clean(s, max)
    if s == nil then return "" end
    return GuildOS:SanitizeUserText(tostring(s), max or 60)
end
local function count(t)
    local n = 0
    for _ in pairs(t) do n = n + 1 end
    return n
end

----------------------------------------------------------------------
-- Pure helpers (tested below)
----------------------------------------------------------------------

-- The copy of an alliance an observer may hold: its name, tag and each guild's
-- ambassadors. Never the code, the key, or a guild the owner has blocked.
function AO.StripView(pact)
    if type(pact) ~= "table" or type(pact.guilds) ~= "table" then return nil end
    local view = {
        tag = pact.tag, name = pact.name, owner = pact.owner,
        revision = pact.revision, guilds = {},
    }
    for guild, entry in pairs(pact.guilds) do
        if type(entry) == "table" and not (pact.blocked and pact.blocked[guild]) then
            local ambs = {}
            for _, a in ipairs(entry.ambassadors or {}) do ambs[#ambs + 1] = a end
            view.guilds[guild] = { ambassadors = ambs, joinedAt = entry.joinedAt }
        end
    end
    return view
end

-- A snapshot replaces the one held only when it is newer.
function AO.Newer(rev, held)
    return (tonumber(rev) or 0) > (tonumber(held) or 0)
end

-- A snapshot off the wire, cut down to the caps and made safe to print. Nil when
-- it names no guild.
function AO.Clamp(data)
    if type(data) ~= "table" then return nil end
    local guildMax = GuildOS.Alliance.GUILD_NAME_MAX
    local guild = clean(data.guild, guildMax)
    if guild == "" then return nil end
    local out = { guild = guild, rev = tonumber(data.rev) or 0, leaders = {}, events = {} }

    if type(data.leaders) == "table" then
        for i = 1, math.min(#data.leaders, AO.GUILD_CAP) do
            local g = data.leaders[i]
            if type(g) == "table" and type(g.leaders) == "table" then
                local row = { guild = clean(g.guild, guildMax), leaders = {} }
                for j = 1, math.min(#g.leaders, AO.LEADER_CAP) do
                    local l = g.leaders[j]
                    if type(l) == "table" then
                        row.leaders[#row.leaders + 1] = {
                            name = clean(l.name, 40), role = clean(l.role, 30), online = l.online == true,
                        }
                    end
                end
                if row.guild ~= "" then out.leaders[#out.leaders + 1] = row end
            end
        end
    end

    if type(data.events) == "table" then
        for i = 1, math.min(#data.events, AO.EVENT_CAP) do
            local e = data.events[i]
            if type(e) == "table" then
                local names = {}
                if type(e.names) == "table" then
                    for j = 1, math.min(#e.names, AO.NAME_CAP) do
                        names[#names + 1] = clean(e.names[j], 40)
                    end
                end
                out.events[#out.events + 1] = {
                    title = clean(e.title, 80), when = tonumber(e.when) or 0,
                    size = tonumber(e.size) or 0, yes = tonumber(e.yes) or 0,
                    guild = clean(e.guild, guildMax), names = names,
                }
            end
        end
    end
    return out
end

----------------------------------------------------------------------
-- Sponsor side
----------------------------------------------------------------------
local function observers()
    GuildOS.db.allianceObservers = GuildOS.db.allianceObservers or {}
    return GuildOS.db.allianceObservers
end

-- One op whispered with the bare encoder: no code, no key stamp. The far side
-- reads it before any pact gate, so it needs none of them.
local function whisper(op, tbl, target)
    local Alliance = GuildOS.Alliance
    local mesh = _G.ChehulMesh
    if not (Alliance and mesh and target and target ~= "") then return false end
    local blob = Alliance.Encode(tbl)
    if not blob then return false end
    GuildOS:NoteWhisper(target)
    return mesh:Whisper(Alliance.PREFIX, Alliance.PROTO .. "|" .. op .. "|" .. blob, target) and true or false
end

local function sponsorState()
    local ally = GuildOS.Alliance
    local pact = ally and ally:Get()
    local guild = ally and ally:MyGuildName()
    return pact, guild, ally
end

-- Each guild's leaders, and whether each is online now. Our own guild's roster is
-- built locally; an allied guild's comes from its synced roster.
local function leadersOf(pact, ally)
    local out = {}
    local sync, net = GuildOS.AllianceSync, _G.ChehulNet
    if not (sync and sync._BuildRoster and net and net.Peers) then return out end
    local mine = ally:MyGuildName()
    local t, peers, ttl = now(), net:Peers(), net.PEER_TTL or 600
    for guildName in pairs(pact.guilds) do
        if not ally:IsBlocked(guildName) then
            local rows
            if guildName == mine then
                rows = sync._BuildRoster(GuildOS.db.members, sync.ROSTER_CAP, GuildOS.db.altLinks)
            else
                local entry = sync:Remote(guildName, "roster")
                rows = entry and type(entry.data) == "table" and entry.data or {}
            end
            local leaders = {}
            for _, r in ipairs(rows) do
                if r.ld and r.n then
                    local name = r.n:match("^([^-]+)") or r.n
                    local p = peers[name]
                    leaders[#leaders + 1] = {
                        name = name, role = r.ld,
                        online = p ~= nil and (t - (p.ts or 0)) <= ttl,
                    }
                end
            end
            if #leaders > 0 then out[#out + 1] = { guild = guildName, leaders = leaders } end
        end
    end
    table.sort(out, function(a, b) return a.guild < b.guild end)
    return out
end

-- Upcoming events of our guild and of its allies, soonest first.
local function eventsOf(ally)
    local out = {}
    local cal = GuildOS.Calendar
    if cal and cal._BuildAllianceEvents and cal.GetEvents then
        local mine = ally:MyGuildName()
        for _, e in ipairs(cal._BuildAllianceEvents(cal:GetEvents(), now(), AO.EVENT_CAP)) do
            e.guild = mine
            out[#out + 1] = e
        end
    end
    if cal and cal.AllianceEvents then
        for _, e in ipairs(cal:AllianceEvents()) do out[#out + 1] = e end
    end
    table.sort(out, function(a, b) return (a.when or 0) < (b.when or 0) end)
    while #out > AO.EVENT_CAP do table.remove(out) end
    return out
end

function AO:Snapshot(pact, ally)
    return {
        guild = ally:MyGuildName(), rev = now(),
        leaders = leadersOf(pact, ally), events = eventsOf(ally),
    }
end

-- Grant access to a character. Only an ambassador of this guild may grant it. The
-- character still has to accept the dialog on its side before anything is shown.
function AO:Grant(who)
    local pact, guild = sponsorState()
    if not (pact and guild) then return false, L["You need to be in an alliance to share it."] end
    local me = GuildOS.Compat.PlayerName()
    if not GuildOS.Alliance.IsAmbassador(pact, guild, me) then
        return false, L["Only an ambassador of your guild can grant observer access."]
    end
    local target = short(who)
    if target == "" then return false, L["Usage: /outlawos ally observe <name>"] end
    if target == short(me) then return false, L["You cannot observe your own alliance."] end
    local list = observers()
    if not list[target] and count(list) >= AO.MAX_OBSERVERS then
        return false, string.format(L["At most %d observers at a time."], AO.MAX_OBSERVERS)
    end
    -- Whispered by the name as the game shows it; the lowercase key is only for lookups.
    local name = clean(display(who), 40)
    local sent = whisper("OBS", { view = AO.StripView(pact), sponsor = guild }, name)
    if not sent then
        return false, L["Could not reach that character. Check the name and try again."]
    end
    list[target] = { name = name, since = now() }
    return true
end

function AO:Revoke(who)
    local list = observers()
    local target = short(who)
    if target == "" or not list[target] then
        return false, L["That character is not observing your alliance."]
    end
    local name = list[target].name or target
    list[target] = nil
    whisper("OBSX", {}, name)
    return true
end

-- Snapshot to every observer on the list. Called on a timer.
function AO:PushAll()
    local pact, guild, ally = sponsorState()
    if not (pact and guild) then return 0 end
    local targets = {}
    for _, rec in pairs(observers()) do targets[#targets + 1] = rec.name or "" end
    if #targets == 0 then return 0 end
    local snap = self:Snapshot(pact, ally)
    local sent = 0
    for _, name in ipairs(targets) do
        if whisper("OBSD", snap, name) then sent = sent + 1 end
    end
    return sent
end

function AO:PushTo(target)
    local pact, guild, ally = sponsorState()
    local rec = pact and guild and observers()[target]
    if not rec then return false end
    return whisper("OBSD", self:Snapshot(pact, ally), rec.name or target)
end

function AO:PrintList()
    local list = observers()
    local names = {}
    for key in pairs(list) do names[#names + 1] = key end
    if #names == 0 then
        GuildOS:Print(L["No observers yet."])
        return
    end
    table.sort(names)
    GuildOS:Print(L["Observers of your alliance:"])
    for _, key in ipairs(names) do
        GuildOS:Print(string.format(L["  %s (since %s)"], list[key].name or key,
            date("%d %b %H:%M", list[key].since or 0)))
    end
end

----------------------------------------------------------------------
-- Observer side
----------------------------------------------------------------------
function AO.Record()
    return GuildOS.db and GuildOS.db.allianceObserver or nil
end

function AO:IsObserving()
    if not AO.Record() then return false end
    if IsInGuild() or GuildOS.Alliance:Get() then return false end
    return true
end

-- Called from Alliance:OnMessage before any pact gate. True when the op was an
-- observer op, so the caller stops there.
function AO:OnWire(op, data, sender)
    if op == "OBS" then self:_OnGrant(data, sender); return true end
    if op == "OBSX" then self:_OnRevoked(sender); return true end
    if op == "OBSD" then self:_OnSnapshot(data, sender); return true end
    if op == "OBSA" then self:_OnAccepted(sender); return true end
    return false
end

function AO:_OnGrant(data, sender)
    if type(data) ~= "table" then return end
    local Alliance = GuildOS.Alliance
    if IsInGuild() or Alliance:Get() or AO.Record() then
        GuildOS.Logger.Debug("Alliance observer: grant from " .. display(sender) .. " not taken here")
        return
    end
    local view = Alliance.SanitizePact(data.view)
    if not view then return end
    local sponsor = clean(data.sponsor, Alliance.GUILD_NAME_MAX)
    local guild = Alliance:GuildOfSender(sender, view)
    if sponsor == "" or guild ~= sponsor then return end

    local key, t = short(sender), now()
    self._prompts = self._prompts or {}
    if self._prompts[key] and (t - self._prompts[key]) < AO.PROMPT_COOLDOWN then return end
    self._prompts[key] = t

    GuildOS:ShowDialog("GUILDOS_ALLY_OBSERVE",
        string.format(L["%s of %s would like to share the alliance %s with you. You can watch it, but not change it."],
            display(sender), guild, view.name or view.tag),
        nil, { tag = view.tag, name = view.name, sponsor = guild, sender = sender })
end

function AO:_OnRevoked(sender)
    local rec = AO.Record()
    if not rec or rec.grantor ~= short(sender) then return end
    GuildOS.db.allianceObserver = nil
    GuildOS:Print(string.format(L["%s ended your observer access to the alliance %s."],
        rec.grantorName or display(sender), rec.name or rec.tag or ""))
    self:Hide()
end

function AO:_OnSnapshot(data, sender)
    local rec = AO.Record()
    if not rec or rec.grantor ~= short(sender) then return end
    local snap = AO.Clamp(data)
    if not snap or snap.guild ~= rec.sponsor then return end
    if not AO.Newer(snap.rev, rec.rev) then return end
    rec.rev, rec.leaders, rec.events, rec.syncedAt = snap.rev, snap.leaders, snap.events, now()
    self:Refresh()
end

function AO:_OnAccepted(sender)
    local key = short(sender)
    if observers()[key] then self:PushTo(key) end
end

-- The player accepted the dialog: keep the grant, and tell the sponsor to send now.
function AO:Accept(d)
    if IsInGuild() or GuildOS.Alliance:Get() or AO.Record() then return end
    GuildOS.db.allianceObserver = {
        tag = d.tag, name = d.name, sponsor = d.sponsor,
        grantor = short(d.sender), grantorName = display(d.sender),
        grantedAt = now(), rev = 0, leaders = {}, events = {},
    }
    whisper("OBSA", {}, d.sender)
    GuildOS:Print(string.format(L["You are now observing the alliance %s. Read-only."], d.name or d.tag or ""))
    self:Show()
end

----------------------------------------------------------------------
-- The observer's frame
----------------------------------------------------------------------
local frame

local function hexOf(c)
    return string.format("%02x%02x%02x", c.r * 255, c.g * 255, c.b * 255)
end

local function ago(sec)
    sec = math.max(0, math.floor(sec))
    if sec < 3600 then return string.format(L["%d min"], math.max(1, math.floor(sec / 60))) end
    return string.format(L["%d h"], math.floor(sec / 3600))
end

local function ensureFrame()
    if frame then return frame end
    local UI, C = GuildOS.UI, GuildOS.Colors
    frame = CreateFrame("Frame", "GuildOSObserverFrame", UIParent, "BackdropTemplate")
    frame:SetSize(520, 460)
    frame:SetPoint("CENTER")
    frame:SetFrameStrata("DIALOG")
    frame:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = UI:Edge(frame),
    })
    frame:SetBackdropColor(C.popup.r, C.popup.g, C.popup.b, 1)
    frame:SetBackdropBorderColor(C.lineHi.r, C.lineHi.g, C.lineHi.b, 1)
    frame:EnableMouse(true)
    frame:SetMovable(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
    frame:Hide()

    frame.title = UI:CreateTitle(frame, "", 18)
    frame.title:SetPoint("TOP", 0, -16)

    frame.body = UI:CreateText(frame, "", 11, C.text.r, C.text.g, C.text.b)
    frame.body:SetPoint("TOPLEFT", 16, -48)
    frame.body:SetPoint("TOPRIGHT", -16, -48)
    frame.body:SetPoint("BOTTOM", 0, 44)
    frame.body:SetJustifyH("LEFT")
    frame.body:SetJustifyV("TOP")
    frame.body:SetWordWrap(true)

    local close = UI:CreateButton(frame, L["Close"], 90, 24)
    close:SetPoint("BOTTOM", 0, 14)
    close:SetScript("OnClick", function() frame:Hide() end)
    return frame
end

function AO:Refresh()
    if not frame or not frame:IsShown() then return end
    local rec = AO.Record()
    if not rec then
        self:Hide()
        return
    end
    local C = GuildOS.Colors
    local heading = "|cff" .. hexOf(C.label) .. "%s|r"
    frame.title:SetText(string.format(L["Observing %s"], rec.name or rec.tag or ""))

    local lines = {}
    lines[#lines + 1] = string.format(L["Shared by %s of %s. Read-only."], rec.grantorName or "", rec.sponsor or "")
    if rec.syncedAt then
        lines[#lines + 1] = string.format(L["Last synced %s ago."], ago(now() - rec.syncedAt))
    else
        lines[#lines + 1] = string.format(L["Waiting for the first sync from %s."], rec.grantorName or "")
    end
    lines[#lines + 1] = ""
    lines[#lines + 1] = string.format(heading, L["LEADERS ONLINE"])
    if #rec.leaders == 0 then lines[#lines + 1] = "  " .. L["Nothing synced yet."] end
    for _, g in ipairs(rec.leaders) do
        local parts = {}
        for _, l in ipairs(g.leaders) do
            parts[#parts + 1] = l.name .. " " .. l.role .. " " .. (l.online and L["online"] or L["not seen"])
        end
        lines[#lines + 1] = "  " .. g.guild .. ":  " .. table.concat(parts, ";  ")
    end

    lines[#lines + 1] = ""
    lines[#lines + 1] = string.format(heading, L["UPCOMING ALLIANCE EVENTS"])
    if #rec.events == 0 then lines[#lines + 1] = "  " .. L["No events shared yet."] end
    for i, e in ipairs(rec.events) do
        if i > 8 then break end
        lines[#lines + 1] = string.format("  %s  %s  (%s)  %s",
            date("%a %d %b %H:%M", e.when or 0), e.title or "", e.guild or "",
            string.format(L["%d signed up"], e.yes or 0))
        if e.names and #e.names > 0 then
            lines[#lines + 1] = "      " .. table.concat(e.names, ", ")
        end
    end
    frame.body:SetText(table.concat(lines, "\n"))
end

function AO:Show()
    if not self:IsObserving() then
        GuildOS:Print(L["You are not observing an alliance."])
        return
    end
    local f = ensureFrame()
    f:Show()
    f:Raise()
    self:Refresh()
end

function AO:Hide()
    if frame then frame:Hide() end
end

----------------------------------------------------------------------
-- Tests and start-up
----------------------------------------------------------------------
function AO:_RegisterTests()
    if not GuildOS.SelfTest then return end
    GuildOS.SelfTest:Register("allianceobserver.strip_view", function()
        local v = AO.StripView({
            tag = "ABC", name = "Test", owner = "A", revision = 3, code = "secret", key = "k",
            guilds = { A = { ambassadors = { "a1" }, joinedAt = 1 }, B = { ambassadors = { "b1" } } },
            blocked = { B = true },
        })
        if v.code or v.key then return false, "code or key leaked" end
        if v.guilds.B then return false, "blocked guild leaked" end
        if not v.guilds.A or v.guilds.A.ambassadors[1] ~= "a1" then return false, "member lost" end
        return true
    end)
    GuildOS.SelfTest:Register("allianceobserver.newer", function()
        if AO.Newer(5, 5) then return false, "equal revision accepted" end
        if not AO.Newer(6, 5) then return false, "newer revision rejected" end
        if not AO.Newer(6, nil) then return false, "first snapshot rejected" end
        return true
    end)
    GuildOS.SelfTest:Register("allianceobserver.clamp", function()
        local big = {}
        for i = 1, 200 do big[i] = { name = "n" .. i } end
        local s = AO.Clamp({ guild = "G", rev = 1, leaders = { { guild = "H", leaders = big } }, events = {} })
        if not s or #s.leaders[1].leaders > AO.LEADER_CAP then return false, "leaders not capped" end
        if AO.Clamp({ rev = 1 }) ~= nil then return false, "a snapshot with no guild must be nil" end
        return true
    end)
end

function AO:Initialize()
    self:_RegisterTests()
    if GuildOS.Dialogs and not GuildOS.Dialogs["GUILDOS_ALLY_OBSERVE"] then
        GuildOS.Dialogs["GUILDOS_ALLY_OBSERVE"] = {
            text = "%s",
            button1 = L["Accept"],
            button2 = L["Decline"],
            OnAccept = function(self)
                local d = self and self.data
                if d then AO:Accept(d) end
            end,
            timeout = 60,
            whileDead = true,
            hideOnEscape = true,
            preferredIndex = 3,
        }
    end
    GuildOS.Compat.NewTicker(self.TICK, function()
        GuildOS:SafeCall(function() AO:PushAll() end)
    end)
end
