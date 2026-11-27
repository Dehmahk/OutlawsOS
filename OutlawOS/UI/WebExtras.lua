----------------------------------------------------------------------
-- OutlawOS - Web tab extras
--
-- A second column on the Web tab (under the first on a narrow window):
--   PUBLISH TOOLS   what the site has against what the game has, a preview of what the next
--                   publish changes, the companion's status and a stale warning, a schedule,
--                   a history of publishes, what goes on the site, and names kept off it.
--   RAID TOOLS      load a raid from the guild calendar, who is online and in the group,
--                   what the raid lacks (roles, buffs), invite in two waves, post the roster
--                   to guild chat, saved plans and a raid-day checklist.
--
-- It wraps GuildOS:CreateWebPanel, so UI/WebPanel.lua keeps its own layout. Everything it
-- keeps lives in GuildOS.db.web.
----------------------------------------------------------------------
local UI = GuildOS.UI
local C  = GuildOS.Colors
local L  = GuildOS.L

local WE = {}
GuildOS.WebExtras = WE

local SITE_URL   = "https://guildos.me"
local SECTION    = 18
local TITLE_H    = 24
local BTN_H      = 22
local ROW_H      = 16
local LEFT_W     = 520      -- the first column's width when the window is wide enough for two
local TWO_COL_AT = 1060     -- the window width that gets two columns
local PREVIEW_ROWS = 14
local HISTORY_ROWS = 6
local HIDDEN_ROWS  = 8
local CAL_ROWS     = 5
local PLAN_ROWS    = 5
local MAX_PLANS    = 5

local function setOn(btn, on)
    if on then btn:Enable() else btn:Disable() end
end

local function now() return (GetServerTime and GetServerTime()) or time() end

----------------------------------------------------------------------
-- What is kept (GuildOS.db.web)
----------------------------------------------------------------------
local function W()
    local db = GuildOS.db
    if not db then return nil end
    db.web = db.web or {}
    local w = db.web
    w.share   = w.share   or {}
    w.hidden  = w.hidden  or {}
    w.history = w.history or {}
    w.sched   = w.sched   or { hours = 0, mode = "ask" }
    w.plans   = w.plans   or {}
    w.checks  = w.checks  or {}
    if w.staleHours == nil then w.staleHours = 12 end
    return w
end
WE.Data = W

----------------------------------------------------------------------
-- What goes on the site, shared among officers (domain "webcfg"): the share switches and the hidden names
-- are the guild's, so whichever officer publishes sends the same roster. The newest change wins.
----------------------------------------------------------------------
function WE.PublishCfg()
    local w = W()
    if not w or not GuildOS.SyncService or not GuildOS:IsOfficer() then return end
    local hidden = {}
    for n in pairs(w.hidden) do hidden[#hidden + 1] = n end
    table.sort(hidden)
    local share = {}
    for k, v in pairs(w.share) do if v == false then share[#share + 1] = k end end   -- the ones left out
    table.sort(share)
    GuildOS.SyncService:Publish("webcfg", "set", { rev = w.cfgRev or 0, hidden = hidden, off = share }, { priority = "BULK" })
end

-- A change made here: stamp it and send it.
local function cfgChanged()
    local w = W()
    if not w then return end
    w.cfgRev = math.max(now(), (w.cfgRev or 0) + 1)
    WE.PublishCfg()
end

if GuildOS.SyncService then
    GuildOS.SyncService.GUILD_ONLY_DOMAINS.webcfg = true
    GuildOS.SyncService:On("webcfg", function(env, sender)
        local d = env and env.data
        if type(d) ~= "table" or type(d.rev) ~= "number" or type(d.hidden) ~= "table" or type(d.off) ~= "table" then return end
        if not GuildOS:IsOfficerByName(sender) then return end
        local w = W()
        if not w or d.rev <= (w.cfgRev or 0) then return end
        w.cfgRev = d.rev
        w.hidden = {}
        for _, n in ipairs(d.hidden) do if type(n) == "string" and #n < 40 then w.hidden[n] = true end end
        for k in pairs(w.share) do w.share[k] = nil end
        for _, k in ipairs(d.off) do if type(k) == "string" and #k < 40 then w.share[k] = false end end
        if GuildOS.WebPanelRefresh then GuildOS:SafeCall(GuildOS.WebPanelRefresh) end
    end)
end

local function companionOn()
    local co = GuildOS.Companion
    return (co and co:IsEnabled()) and true or false
end

local function ago(t)
    if not t or t <= 0 then return L["never"] end
    local dt = now() - t
    if dt < 120 then return L["just now"] end
    if dt < 3600 then return string.format(L["%d min ago"], math.floor(dt / 60)) end
    if dt < 86400 then return string.format(L["%d h ago"], math.floor(dt / 3600)) end
    return string.format(L["%d d ago"], math.floor(dt / 86400))
end

local function clock(t)
    if not t or t <= 0 then return "-" end
    return GuildOS:LocalDate("%a %H:%M", t)
end

local function shortName(full)
    return (full and (full:match("^([^-]+)") or full)) or ""
end

----------------------------------------------------------------------
-- The guild as the game has it
----------------------------------------------------------------------
local function liveRoster()
    local t, n = {}, GetNumGuildMembers() or 0
    for i = 1, n do
        local full, rank, _, level, _, _, _, _, online = GetGuildRosterInfo(i)
        if full then
            t[shortName(full)] = { rank = rank or "", level = tonumber(level) or 0, online = online and true or false }
        end
    end
    return t, n
end

--- The roster the way the last publish saw it, so the next one can be compared with it.
function WE.Snapshot()
    local w = W()
    if not w then return end
    local live, n = liveRoster()
    if n == 0 then return end
    local members, count = {}, 0
    for name, v in pairs(live) do
        if not w.hidden[name] then
            members[name] = v.level .. "|" .. v.rank
            count = count + 1
        end
    end
    w.snap = { at = now(), count = count, members = members }
    w.lastPublishAt = now()
    table.insert(w.history, 1, { at = now(), count = count })
    while #w.history > 10 do table.remove(w.history) end
end

--- What would change if the roster were written now. Nil when there is nothing to compare with.
function WE.Diff()
    local w = W()
    local snap = w and w.snap
    if not snap or not snap.members then return nil end
    local live, n = liveRoster()
    if n == 0 then return nil end
    local d = { joined = {}, left = {}, ranks = {}, levelUps = 0, now = 0 }
    for name, v in pairs(live) do
        if not w.hidden[name] then
            d.now = d.now + 1
            local old = snap.members[name]
            if not old then
                d.joined[#d.joined + 1] = name
            else
                local lv, rk = old:match("^(%d+)|(.*)$")
                if rk and rk ~= v.rank then d.ranks[#d.ranks + 1] = { name, rk, v.rank } end
                if lv and (tonumber(lv) or 0) < v.level then d.levelUps = d.levelUps + 1 end
            end
        end
    end
    for name in pairs(snap.members) do
        if not live[name] or w.hidden[name] then d.left[#d.left + 1] = name end
    end
    table.sort(d.joined); table.sort(d.left)
    table.sort(d.ranks, function(a, b) return a[1] < b[1] end)
    return d
end

----------------------------------------------------------------------
-- Publishing: the click, the schedule, the confirmation after the reload
----------------------------------------------------------------------
function WE.MarkPublishing()
    local w = W()
    if not w then return end
    WE.Snapshot()
    w.pending = now()
end

-- The reload's other side: say that it worked.
local function confirmPublish()
    local w = W()
    if not w or not w.pending then return end
    local at, snap = w.pending, w.snap
    w.pending = nil
    if now() - at > 600 then return end
    GuildOS:Print(string.format(L["Published: %d members written at %s. The companion sends it on from your PC."],
        (snap and snap.count) or 0, clock(at)))
end

local function quietEnough()
    if InCombatLockdown and InCombatLockdown() then return false end
    if (GetNumGroupMembers() or 0) > 0 then return false end
    if IsInInstance and select(1, IsInInstance()) then return false end
    return true
end

StaticPopupDialogs["OUTLAWOS_WEB_PUBLISH"] = {
    text = "OutlawOS: it has been a while since the guild's data was written for the site. Publish now? This reloads the interface.",
    button1 = "Publish now",
    button2 = "Later",
    OnAccept = function()
        if InCombatLockdown and InCombatLockdown() then return end
        WE.MarkPublishing()
        ReloadUI()
    end,
    OnCancel = function()
        local w = W()
        if w then w.snoozeUntil = now() + 1800 end
    end,
    timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
}

local function scheduleTick()
    local w = W()
    if not w or not companionOn() then return end
    local hours = tonumber(w.sched.hours) or 0
    if hours <= 0 then return end
    local last = w.lastPublishAt or (w.snap and w.snap.at) or 0
    if now() - last < hours * 3600 then return end
    if (w.snoozeUntil or 0) > now() then return end
    if not quietEnough() then return end
    if w.sched.mode == "auto" then
        WE.MarkPublishing()
        ReloadUI()
    else
        if not StaticPopup_Visible("OUTLAWOS_WEB_PUBLISH") then
            StaticPopup_Show("OUTLAWOS_WEB_PUBLISH")
        end
        w.snoozeUntil = now() + 1800
    end
end

local function staleCheck()
    local w = W()
    if not w or not companionOn() or (w.staleHours or 0) <= 0 then return end
    if not (GuildOS.IsOfficer and GuildOS:IsOfficer()) then return end
    local I = GuildOS.CompanionImport
    local at = I and I:Ack()
    if at and now() - at <= w.staleHours * 3600 then return end
    GuildOS:Print(at
        and string.format(L["The site was last updated %s. Open the Web tab and publish."], ago(at))
        or L["The site has not confirmed an update yet. Open the Web tab to check the companion."])
end

local ev = CreateFrame("Frame")
ev:RegisterEvent("PLAYER_LOGOUT")
ev:RegisterEvent("PLAYER_ENTERING_WORLD")
ev:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_LOGOUT" then
        if companionOn() then WE.Snapshot() end
    else
        C_Timer.After(12, confirmPublish)
        C_Timer.After(30, staleCheck)
        if not WE.ticker then WE.ticker = C_Timer.NewTicker(60, scheduleTick) end
    end
end)

----------------------------------------------------------------------
-- A raid from the guild calendar
----------------------------------------------------------------------
local ROLE_SLOT = { TANK = "TANK", HEALER = "HEALER" }

local function rosterFromEvent(e)
    local Cal = GuildOS.Calendar
    local I = GuildOS.CompanionImport
    if not (Cal and I and e) then return nil end
    local answers = {}
    if Cal:IsWebEvent(e) then
        for _, s in ipairs(Cal:WebSignups(e)) do answers[#answers + 1] = s end
        for k, r in pairs(e.rsvps or {}) do
            if r.ally then answers[#answers + 1] = { name = r.name or k, class = r.class, role = r.role, status = r.status } end
        end
    else
        for k, r in pairs(e.rsvps or {}) do
            answers[#answers + 1] = { name = r.name or k, class = r.class, role = r.role, status = r.status }
        end
    end
    table.sort(answers, function(a, b) return tostring(a.name) < tostring(b.name) end)

    local members, signups, wait = {}, {}, 0
    for _, a in ipairs(answers) do
        local name = I.PlainName(tostring(a.name))
        local slot = ROLE_SLOT[a.role] or "RANGED"
        local why
        if a.status == "tentative" then why = "tentative"
        elseif a.status == "wait" then why = "wait"
        elseif a.status == "pending" then why = "pending"
        elseif a.status == "no" then why = "no" end
        local entry = {
            key = name, name = name, class = a.class or "", spec = "", slot = slot,
            status = a.status or "yes", group = 0, invite = (a.status == "yes"), why = why,
        }
        if a.status == "wait" then wait = wait + 1; entry.wait = wait end
        signups[#signups + 1] = entry
        if a.status == "yes" then
            members[#members + 1] = { key = name, name = name, class = a.class or "", spec = "", slot = slot, group = 0 }
        end
    end
    return {
        title = e.title or "", instance = e.title or "", size = tonumber(e.size) or #members,
        startsAt = tonumber(e.when) or 0, members = members, signups = signups, fromCalendar = e.id,
    }
end

WE.RosterFromEvent = rosterFromEvent

local function upcomingRaids()
    local Cal = GuildOS.Calendar
    local out = {}
    if not Cal then return out end
    for _, e in ipairs(Cal:GetUpcoming(false)) do
        if tostring(e.kind or ""):upper() == "RAID" then
            out[#out + 1] = e
            if #out >= CAL_ROWS then break end
        end
    end
    return out
end

----------------------------------------------------------------------
-- What the loaded roster says about the raid
----------------------------------------------------------------------
local function currentRoster()
    local I = GuildOS.CompanionImport
    return I and I:Current() or nil
end

local function groupNames()
    local set = {}
    set[shortName(UnitName("player") or "")] = true
    local n = GetNumGroupMembers() or 0
    for i = 1, n do
        local u = (IsInRaid and IsInRaid()) and ("raid" .. i) or ("party" .. i)
        local name = UnitName(u)
        if name then set[shortName(name)] = true end
    end
    return set
end

-- Classes the raid wants somebody of, by the buff or job they bring. Only classes an Alliance
-- guild can have in WoW: Forever are listed; it is a nudge, not a rule.
local BUFF_CLASSES = {
    { "PALADIN", "Paladin (blessings)" },
    { "PRIEST",  "Priest (Fortitude)" },
    { "MAGE",    "Mage (Intellect)" },
    { "DRUID",   "Druid (Mark of the Wild)" },
    { "WARLOCK", "Warlock (summons, healthstones)" },
}

local function rosterFacts(roster)
    local f = { coming = {}, tentative = {}, standby = {}, classes = {}, tanks = 0, healers = 0, dps = 0 }
    if not roster then return f end
    local signups = roster.signups
    if type(signups) == "table" then
        for _, p in ipairs(signups) do
            if p.invite then
                f.coming[#f.coming + 1] = p
            elseif p.why == "tentative" then
                f.tentative[#f.tentative + 1] = p
            elseif p.why == "wait" then
                f.standby[#f.standby + 1] = p
            end
        end
    else
        for _, p in ipairs(roster.members or {}) do f.coming[#f.coming + 1] = p end
    end
    for _, p in ipairs(f.coming) do
        if p.slot == "TANK" then f.tanks = f.tanks + 1
        elseif p.slot == "HEALER" then f.healers = f.healers + 1
        else f.dps = f.dps + 1 end
        if p.class and p.class ~= "" then f.classes[p.class] = (f.classes[p.class] or 0) + 1 end
    end
    return f
end

local function className(token)
    local names = _G.LOCALIZED_CLASS_NAMES_MALE
    return (names and names[token]) or token
end

-- A message the game will take: at most 250 characters, cut between names.
local function chunkLines(prefix, names)
    local out, cur = {}, prefix
    for i, n in ipairs(names) do
        local piece = (i == 1 and "" or ", ") .. n
        if #cur + #piece > 245 then
            out[#out + 1] = cur
            cur = "  " .. n
        else
            cur = cur .. piece
        end
    end
    if cur ~= "" then out[#out + 1] = cur end
    return out
end

local function rosterMessages(roster)
    local f = rosterFacts(roster)
    local title = (roster.title and roster.title ~= "") and roster.title or (roster.instance or "Raid")
    local when = (tonumber(roster.startsAt) or 0) > 0 and (" " .. clock(roster.startsAt)) or ""
    local by = { TANK = {}, HEALER = {}, DPS = {} }
    for _, p in ipairs(f.coming) do
        local key = (p.slot == "TANK" and "TANK") or (p.slot == "HEALER" and "HEALER") or "DPS"
        by[key][#by[key] + 1] = p.name
    end
    local msgs = { string.format("%s%s: %d coming (%d tanks, %d healers, %d dps)",
        title, when, #f.coming, f.tanks, f.healers, f.dps) }
    for _, key in ipairs({ "TANK", "HEALER", "DPS" }) do
        if #by[key] > 0 then
            table.sort(by[key])
            local label = (key == "TANK" and "Tanks: ") or (key == "HEALER" and "Healers: ") or "DPS: "
            for _, line in ipairs(chunkLines(label, by[key])) do msgs[#msgs + 1] = line end
        end
    end
    return msgs
end

WE.RosterMessages = rosterMessages
WE.RosterFacts = rosterFacts

----------------------------------------------------------------------
-- Build: the second column
----------------------------------------------------------------------
local CHECKLIST = {
    { "invites",  "Roster loaded and invites sent" },
    { "assist",   "Raid assistants set" },
    { "loot",     "Loot method and loot system set" },
    { "voice",    "Discord voice open" },
    { "ready",    "Ready check done" },
    { "consumes", "Consumables and repairs reminder posted" },
}

local SCHED_STEPS = { 0, 1, 2, 4, 12, 24 }
local STALE_STEPS = { 6, 12, 24, 72, 0 }

local SHARE_ITEMS = {
    { "loot",         "Loot history" },
    { "sessions",     "Raid nights and attendance" },
    { "journal",      "Journal" },
    { "joinRequests", "Join requests" },
    { "lootBook",     "Points and loot lists" },
}

function WE.Build(panel, parent)
    local ex = CreateFrame("Frame", nil, panel)
    ex:SetSize(400, 10)

    local items = {}
    local function add(it) items[#items + 1] = it; return it end

    ----------------------------------------------------------------
    -- Element makers. Each item has put(x, y, w) -> the height it took.
    ----------------------------------------------------------------
    local function titleItem(text, first)
        local fs = UI:CreateSectionTitle(ex, text, first)
        if fs.rule then fs.rule:SetPoint("RIGHT", ex, "RIGHT", 0, 0) end
        return add({
            put = function(_, x, y, w)
                local gap = first and 0 or SECTION
                fs:ClearAllPoints()
                fs:SetPoint("TOPLEFT", ex, "TOPLEFT", x, -(y + gap))
                return gap + TITLE_H
            end,
        })
    end

    local function textItem(size, r, g, b)
        local fs = UI:CreateText(ex, "", size or 10, r or C.textDim.r, g or C.textDim.g, b or C.textDim.b)
        fs:SetJustifyH("LEFT")
        fs:SetWordWrap(true)
        local it = { fs = fs }
        function it.put(_, x, y, w)
            local t = fs:GetText()
            if not t or t == "" then fs:Hide(); return 0 end
            fs:Show()
            fs:ClearAllPoints()
            fs:SetPoint("TOPLEFT", ex, "TOPLEFT", x, -y)
            fs:SetWidth(w)
            return math.max(ROW_H, math.ceil(fs:GetStringHeight() or 0) + 2)
        end
        return add(it), fs
    end

    local function buttonRow(buttons)
        local it = { buttons = buttons }
        function it.put(_, x, y, w)
            local cx, cy, rows = 0, 0, 1
            for _, b in ipairs(buttons) do
                if b:IsShown() then
                    local bw = b:GetWidth()
                    if cx > 0 and cx + bw > w then cx = 0; cy = cy + BTN_H + 4; rows = rows + 1 end
                    b:ClearAllPoints()
                    b:SetPoint("TOPLEFT", ex, "TOPLEFT", x + cx, -(y + cy))
                    cx = cx + bw + 6
                end
            end
            return rows * (BTN_H + 4)
        end
        return add(it)
    end

    local function hint(btn, text)
        btn.hintText = text
        btn:HookScript("OnEnter", function(self)
            if not self.hintText or self.hintText == "" then return end
            GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
            GameTooltip:SetText(self.hintText, 1, 1, 1, 1, true)
            GameTooltip:Show()
        end)
        btn:HookScript("OnLeave", function() GameTooltip:Hide() end)
    end

    local function mkButton(text, width, tip, onClick)
        local b = UI:CreateButton(ex, text, width, BTN_H)
        if tip then hint(b, tip) end
        b:SetScript("OnClick", onClick)
        return b
    end

    -- A pool of rows: a text and up to two small buttons, shown up to `count`.
    local function poolItem(n, withButtons)
        local pool = { rows = {}, count = 0 }
        for i = 1, n do
            local fs = UI:CreateText(ex, "", 10, C.text.r, C.text.g, C.text.b)
            fs:SetJustifyH("LEFT")
            fs:SetWordWrap(false)
            local row = { fs = fs }
            if withButtons then
                row.b1 = UI:CreateButton(ex, "", 60, 18)
                row.b2 = UI:CreateButton(ex, "", 24, 18)
                row.b1:Hide(); row.b2:Hide()
            end
            fs:Hide()
            pool.rows[i] = row
        end
        function pool.put(_, x, y, w)
            local used = 0
            for i, row in ipairs(pool.rows) do
                local on = i <= pool.count
                row.fs:SetShown(on)
                if row.b1 then row.b1:SetShown(on and row.b1.wanted ~= false) end
                if row.b2 then row.b2:SetShown(on and row.b2.wanted == true) end
                if on then
                    used = used + 1
                    local btnW = 0
                    if row.b2 and row.b2:IsShown() then
                        row.b2:ClearAllPoints()
                        row.b2:SetPoint("TOPRIGHT", ex, "TOPLEFT", x + w, -(y + (used - 1) * 20))
                        btnW = btnW + row.b2:GetWidth() + 4
                    end
                    if row.b1 and row.b1:IsShown() then
                        row.b1:ClearAllPoints()
                        row.b1:SetPoint("TOPRIGHT", ex, "TOPLEFT", x + w - btnW, -(y + (used - 1) * 20))
                        btnW = btnW + row.b1:GetWidth() + 4
                    end
                    row.fs:ClearAllPoints()
                    row.fs:SetPoint("TOPLEFT", ex, "TOPLEFT", x, -(y + (used - 1) * 20 + 3))
                    row.fs:SetWidth(math.max(60, w - btnW - 4))
                end
            end
            return used * 20
        end
        return add(pool), pool
    end

    ----------------------------------------------------------------
    -- PUBLISH TOOLS
    ----------------------------------------------------------------
    titleItem(L["PUBLISH TOOLS"], true)

    local _, syncFs = textItem(10, C.textDim.r, C.textDim.g, C.textDim.b)
    local _, diffFs = textItem(10, C.textDim.r, C.textDim.g, C.textDim.b)

    local previewBtn, siteBtn, staleBtn
    local previewOpen = false
    previewBtn = mkButton(L["Preview changes"], 130,
        L["Lists who joined, left or changed rank since the roster was last written."],
        function() previewOpen = not previewOpen; panel:Refresh() end)
    siteBtn = mkButton(L["Copy site link"], 120, L["Shows the website's address, ready to copy."],
        function() WE.showLink = not WE.showLink; panel:Refresh() end)
    staleBtn = mkButton("", 170, L["How long the site can go without an update before OutlawOS warns an officer."],
        function()
            local w = W(); if not w then return end
            local at = 1
            for i, v in ipairs(STALE_STEPS) do if v == w.staleHours then at = i end end
            w.staleHours = STALE_STEPS[(at % #STALE_STEPS) + 1]
            panel:Refresh()
        end)
    buttonRow({ previewBtn, siteBtn, staleBtn })

    local linkBox = UI:CreateInput(ex, 260, 20)
    linkBox:SetText(SITE_URL)
    linkBox:SetScript("OnEnterPressed", function(s) s:ClearFocus() end)
    linkBox:HookScript("OnTextChanged", function(s)
        if s:GetText() ~= SITE_URL then s:SetText(SITE_URL); s:HighlightText() end
    end)
    linkBox:Hide()
    add({
        put = function(_, x, y, w)
            if not WE.showLink then linkBox:Hide(); return 0 end
            linkBox:Show()
            linkBox:ClearAllPoints()
            linkBox:SetPoint("TOPLEFT", ex, "TOPLEFT", x, -y)
            linkBox:SetWidth(math.min(w, 300))
            if not linkBox.__sel then linkBox.__sel = true; linkBox:HighlightText(); linkBox:SetFocus() end
            return 26
        end,
    })

    local _, previewPool = poolItem(PREVIEW_ROWS, false)

    -- Schedule
    titleItem(L["SCHEDULE"])
    local schedBtn, modeBtn
    schedBtn = mkButton("", 160, L["How often OutlawOS offers to write the data for the site."],
        function()
            local w = W(); if not w then return end
            local at = 1
            for i, v in ipairs(SCHED_STEPS) do if v == w.sched.hours then at = i end end
            w.sched.hours = SCHED_STEPS[(at % #SCHED_STEPS) + 1]
            panel:Refresh()
        end)
    modeBtn = mkButton("", 150, L["Ask: a prompt appears. Auto: it reloads by itself, only when you are solo and out of combat."],
        function()
            local w = W(); if not w then return end
            w.sched.mode = (w.sched.mode == "auto") and "ask" or "auto"
            panel:Refresh()
        end)
    buttonRow({ schedBtn, modeBtn })
    local _, schedFs = textItem(10)

    -- History
    titleItem(L["PUBLISH HISTORY"])
    local _, histPool = poolItem(HISTORY_ROWS, false)
    local _, histEmpty = textItem(10)

    -- What goes on the site
    titleItem(L["WHAT GOES ON THE SITE"])
    local shareBtns, shareToggles = {}, {}
    local rosterBtn = UI:CreateButton(ex, L["Roster: always"], 110, BTN_H)
    rosterBtn:Disable()
    shareBtns[#shareBtns + 1] = rosterBtn
    for _, spec in ipairs(SHARE_ITEMS) do
        local key, label = spec[1], spec[2]
        local b = mkButton("", 190, L["Click to include or leave out of what officers publish. The choice is shared between officers."], function()
            local w = W(); if not w then return end
            w.share[key] = (w.share[key] == false) and true or false
            cfgChanged()
            panel:Refresh()
        end)
        b.shareKey, b.shareLabel = key, label
        shareBtns[#shareBtns + 1] = b
        shareToggles[#shareToggles + 1] = b
    end
    buttonRow(shareBtns)

    -- Kept off the site
    titleItem(L["KEPT OFF THE SITE"])
    local hideBox = UI:CreateInput(ex, 160, 20)
    local hideBtn = mkButton(L["Hide name"], 90, L["Leaves this name out of the roster every officer publishes."], function()
        local w = W(); if not w then return end
        local name = strtrim(hideBox:GetText() or "")
        name = shortName(name)
        if name == "" then return end
        w.hidden[name] = true
        cfgChanged()
        hideBox:SetText("")
        panel:Refresh()
    end)
    add({
        put = function(_, x, y, w)
            hideBox:ClearAllPoints()
            hideBox:SetPoint("TOPLEFT", ex, "TOPLEFT", x, -y)
            hideBtn:ClearAllPoints()
            hideBtn:SetPoint("LEFT", hideBox, "RIGHT", 6, 0)
            return 26
        end,
    })
    local _, hiddenPool = poolItem(HIDDEN_ROWS, true)
    local _, hiddenNote = textItem(9)
    hiddenNote:SetText(L["Hides a name from the roster every officer sends. The list is shared between officers."])

    ----------------------------------------------------------------
    -- RAID TOOLS
    ----------------------------------------------------------------
    titleItem(L["UPCOMING RAIDS"])
    local _, calPool = poolItem(CAL_ROWS, true)
    local _, calEmpty = textItem(10)

    titleItem(L["THIS RAID"])
    local _, loadedFs = textItem(11, C.text.r, C.text.g, C.text.b)
    local _, mixFs    = textItem(10)
    local _, needFs   = textItem(10, C.warn.r, C.warn.g, C.warn.b)
    local _, hereFs   = textItem(10)
    local _, offFs    = textItem(10)

    local restBtn, postBtn, saveBtn
    restBtn = mkButton(L["Invite the rest"], 130,
        L["Invites the maybes and the standby list, after the confirmed raiders have been invited."],
        function()
            local I = GuildOS.CompanionImport
            local roster = currentRoster()
            if not (I and roster) then return end
            local ok, why = I:CanInvite()
            if not ok then GuildOS:Print(why or ""); return end
            local f = rosterFacts(roster)
            local here, n = groupNames(), 0
            for _, list in ipairs({ f.tentative, f.standby }) do
                for _, p in ipairs(list) do
                    if p.name and not here[shortName(p.name)] then
                        pcall(GuildOS.Compat.InviteUnit, p.name)
                        here[shortName(p.name)] = true
                        n = n + 1
                    end
                end
            end
            GuildOS:Print(string.format(L["Invited %d more."], n))
            panel:Refresh()
        end)
    postBtn = mkButton(L["Post roster to guild"], 160,
        L["Sends the raid's roles and names to guild chat."],
        function()
            local roster = currentRoster()
            if not roster then return end
            if not IsInGuild() then return end
            for _, line in ipairs(rosterMessages(roster)) do SendChatMessage(line, "GUILD") end
            GuildOS:Print(L["Roster posted to guild chat."])
        end)
    saveBtn = mkButton(L["Save as plan"], 110,
        L["Keeps this roster so it can be loaded again later."],
        function()
            local w, roster = W(), currentRoster()
            if not (w and roster) then return end
            local title = (roster.title and roster.title ~= "") and roster.title or (roster.instance or "Raid")
            local label = title .. " " .. GuildOS:LocalDate("%b %d", now())
            table.insert(w.plans, 1, { name = label, roster = GuildOS:DeepCopy(roster) })
            while #w.plans > MAX_PLANS do table.remove(w.plans) end
            GuildOS:Print(string.format(L["Saved plan: %s"], label))
            panel:Refresh()
        end)
    buttonRow({ restBtn, postBtn, saveBtn })

    titleItem(L["SAVED PLANS"])
    local _, planPool = poolItem(PLAN_ROWS, true)
    local _, planEmpty = textItem(10)

    titleItem(L["RAID-DAY CHECKLIST"])
    local checkBtns = {}
    for _, spec in ipairs(CHECKLIST) do
        local key, label = spec[1], spec[2]
        local b = mkButton("", 300, nil, function()
            local w = W(); if not w then return end
            w.checks[key] = not w.checks[key]
            panel:Refresh()
        end)
        b.checkKey, b.checkLabel = key, label
        checkBtns[#checkBtns + 1] = b
    end
    local resetBtn = mkButton(L["Reset checklist"], 130, L["Clears every tick, ready for the next raid."], function()
        local w = W(); if not w then return end
        wipe(w.checks)
        panel:Refresh()
    end)
    -- one per line: each is its own row
    for _, b in ipairs(checkBtns) do buttonRow({ b }) end
    buttonRow({ resetBtn })

    ----------------------------------------------------------------
    -- Fill from the current state
    ----------------------------------------------------------------
    local function tick(on) return on and "[x] " or "[  ] " end

    function ex:Update()
        local w = W()
        if not w then return end
        local I = GuildOS.CompanionImport
        local co = GuildOS.Companion
        local on = companionOn()

        -- Companion status and the counts that disagree
        local ackAt, ackCount
        if I then ackAt, ackCount = I:Ack() end
        local live, liveN = liveRoster()
        local d = WE.Diff()
        if on then
            if ackAt then
                local lateAfter = (w.staleHours or 0) > 0 and (now() - ackAt) > w.staleHours * 3600
                syncFs:SetText(string.format(L["Companion last sent %s (%s, %d members)."], clock(ackAt), ago(ackAt), ackCount or 0))
                if lateAfter then syncFs:SetTextColor(C.warn.r, C.warn.g, C.warn.b)
                else syncFs:SetTextColor(C.textDim.r, C.textDim.g, C.textDim.b) end
            else
                syncFs:SetText(L["The companion has not confirmed an update yet."])
                syncFs:SetTextColor(C.warn.r, C.warn.g, C.warn.b)
            end
        else
            syncFs:SetText(L["Publishing is off, so nothing is being sent to the site."])
            syncFs:SetTextColor(C.textDim.r, C.textDim.g, C.textDim.b)
        end

        if on and liveN > 0 then
            local line = string.format(L["In the game: %d members."], liveN)
            if ackAt then
                local gap = liveN - (ackCount or 0)
                if gap == 0 then
                    line = line .. " " .. L["The site has the same number."]
                else
                    line = line .. " " .. string.format(L["The site has %d, so it is %d %s."], ackCount or 0, math.abs(gap),
                        gap > 0 and L["behind"] or L["ahead"])
                end
            end
            if d then
                line = line .. " " .. string.format(L["Since the last write: %d joined, %d left, %d rank changes, %d level-ups."],
                    #d.joined, #d.left, #d.ranks, d.levelUps)
            end
            diffFs:SetText(line)
        else
            diffFs:SetText("")
        end

        staleBtn.label:SetText((w.staleHours or 0) > 0
            and string.format(L["Warn after: %dh"], w.staleHours) or L["Warn after: never"])
        siteBtn:SetShown(true)

        -- Preview
        previewBtn.label:SetText(previewOpen and L["Hide changes"] or L["Preview changes"])
        local lines = {}
        if previewOpen and d then
            for _, n in ipairs(d.joined) do lines[#lines + 1] = "|cff66dd66+|r " .. n .. " " .. L["joined"] end
            for _, n in ipairs(d.left)   do lines[#lines + 1] = "|cffdd6666-|r " .. n .. " " .. L["left"] end
            for _, r in ipairs(d.ranks)  do lines[#lines + 1] = "|cffddcc66*|r " .. r[1] .. ": " .. r[2] .. " > " .. r[3] end
            if #lines == 0 then lines[1] = L["Nothing has changed since the last write."] end
        elseif previewOpen then
            lines[1] = L["No earlier write to compare with yet. One is kept each time the data is written."]
        end
        local shown = math.min(#lines, PREVIEW_ROWS)
        for i = 1, PREVIEW_ROWS do previewPool.rows[i].fs:SetText(lines[i] or "") end
        if #lines > PREVIEW_ROWS then
            previewPool.rows[PREVIEW_ROWS].fs:SetText(string.format(L["+%d more"], #lines - PREVIEW_ROWS + 1))
        end
        previewPool.count = shown

        -- Schedule
        schedBtn.label:SetText((w.sched.hours or 0) > 0
            and string.format(L["Publish every: %dh"], w.sched.hours) or L["Publish every: off"])
        modeBtn.label:SetText(w.sched.mode == "auto" and L["Mode: auto"] or L["Mode: ask"])
        local nextAt = (w.sched.hours or 0) > 0 and ((w.lastPublishAt or 0) + w.sched.hours * 3600) or nil
        schedFs:SetText(nextAt and (string.format(L["Next one is due %s."], nextAt <= now() and L["now"] or clock(nextAt))
            .. " " .. L["It waits until you are solo, out of combat and not in an instance."]) or "")

        -- History
        local hist = w.history
        for i = 1, HISTORY_ROWS do
            local h = hist[i]
            local row = histPool.rows[i]
            if h then
                local confirmed = ackAt and ackAt >= h.at
                row.fs:SetText(string.format("%s  ·  %d  ·  %s", clock(h.at), h.count or 0,
                    confirmed and L["site has it"] or L["waiting for the companion"]))
            else
                row.fs:SetText("")
            end
        end
        histPool.count = math.min(#hist, HISTORY_ROWS)
        histEmpty:SetText(#hist == 0 and L["Nothing written yet. One entry is added each time the data is written."] or "")

        -- Sharing toggles
        for _, b in ipairs(shareToggles) do
            b.label:SetText(tick(w.share[b.shareKey] ~= false) .. b.shareLabel)
        end

        -- Hidden names
        local names = {}
        for n in pairs(w.hidden) do names[#names + 1] = n end
        table.sort(names)
        for i = 1, HIDDEN_ROWS do
            local row, n = hiddenPool.rows[i], names[i]
            if n then
                row.fs:SetText(n)
                row.b1.wanted = false
                row.b2.wanted = true
                row.b2.label:SetText("x")
                row.b2:SetScript("OnClick", function() w.hidden[n] = nil; cfgChanged(); panel:Refresh() end)
            else
                row.fs:SetText("")
            end
        end
        hiddenPool.count = math.min(#names, HIDDEN_ROWS)
        hiddenNote:SetShown(true)

        -- Calendar raids
        local raids = upcomingRaids()
        local Cal = GuildOS.Calendar
        for i = 1, CAL_ROWS do
            local row, e = calPool.rows[i], raids[i]
            if e then
                local comp = Cal:GetComposition(e)
                row.fs:SetText(string.format("%s  %s  (%d yes, %d maybe)", clock(e.when), e.title or "?", comp.yes or 0, comp.tentative or 0))
                row.b1.wanted = true
                row.b1.label:SetText(L["Load"])
                row.b2.wanted = false
                row.b1:SetScript("OnClick", function()
                    local roster = rosterFromEvent(e)
                    if not roster then return end
                    GuildOS.db.companionRoster = roster
                    GuildOS:Print(string.format(L["Loaded %s from the calendar: %d coming."], roster.title, #roster.members))
                    panel:Refresh()
                end)
            else
                row.fs:SetText("")
            end
        end
        calPool.count = math.min(#raids, CAL_ROWS)
        calEmpty:SetText(#raids == 0 and L["No raids on the guild calendar."] or "")

        -- The loaded raid
        local roster = currentRoster()
        local f = rosterFacts(roster)
        if roster then
            local title = (roster.title and roster.title ~= "") and roster.title or (roster.instance or "?")
            loadedFs:SetText(string.format("%s%s  -  %d %s", title,
                (tonumber(roster.startsAt) or 0) > 0 and ("  " .. clock(roster.startsAt)) or "", #f.coming,
                roster.fromCalendar and L["coming (from the calendar)"] or L["coming"]))

            local mix = {}
            for token, n in pairs(f.classes) do mix[#mix + 1] = { className(token), n } end
            table.sort(mix, function(a, b) if a[2] ~= b[2] then return a[2] > b[2] end return a[1] < b[1] end)
            local parts = {}
            for _, m in ipairs(mix) do parts[#parts + 1] = m[2] .. " " .. m[1] end
            mixFs:SetText(#parts > 0 and (L["Classes: "] .. table.concat(parts, ", ")) or "")

            -- What the raid lacks: roles, and a class for each buff or job worth having.
            local lacks = {}
            if f.tanks == 0 then lacks[#lacks + 1] = L["no tank"] end
            if f.healers == 0 then lacks[#lacks + 1] = L["no healer"] end
            if next(f.classes) then
                for _, bc in ipairs(BUFF_CLASSES) do
                    if not f.classes[bc[1]] then lacks[#lacks + 1] = L["no "] .. bc[2] end
                end
            end
            needFs:SetText(#lacks > 0 and (L["Missing: "] .. table.concat(lacks, "; ")) or "")

            -- Who is online and in the group
            local here = groupNames()
            local online, offline, inGroup, offNames = 0, 0, 0, {}
            for _, p in ipairs(f.coming) do
                local n = shortName(p.name)
                if here[n] then inGroup = inGroup + 1 end
                local g = live[n]
                if g then
                    if g.online then online = online + 1 else offline = offline + 1; offNames[#offNames + 1] = n end
                end
            end
            hereFs:SetText(string.format(L["%d online · %d offline · %d already in your group"], online, offline, inGroup))
            table.sort(offNames)
            offFs:SetText(#offNames > 0 and (L["Offline: "] .. table.concat(offNames, ", ")) or "")
        else
            loadedFs:SetText(L["Nothing loaded. Load a raid above, or bring a roster from the website."])
            mixFs:SetText(""); needFs:SetText(""); hereFs:SetText(""); offFs:SetText("")
        end

        local ok = (roster ~= nil)
        setOn(postBtn, ok and IsInGuild())
        setOn(saveBtn, ok)
        local canInv = I and I:CanInvite()
        setOn(restBtn, ok and canInv and (#f.tentative + #f.standby) > 0)
        if not ok then
            restBtn.hintText = L["Load a raid first."]
            postBtn.hintText = L["Load a raid first."]
            saveBtn.hintText = L["Load a raid first."]
        elseif not canInv then
            restBtn.hintText = select(2, I:CanInvite()) or ""
        elseif (#f.tentative + #f.standby) == 0 then
            restBtn.hintText = L["Nobody is waiting on maybe or standby."]
        else
            restBtn.hintText = L["Invites the maybes and the standby list, after the confirmed raiders have been invited."]
            postBtn.hintText = L["Sends the raid's roles and names to guild chat."]
            saveBtn.hintText = L["Keeps this roster so it can be loaded again later."]
        end

        -- Saved plans
        for i = 1, PLAN_ROWS do
            local row, p = planPool.rows[i], w.plans[i]
            if p then
                row.fs:SetText(p.name)
                row.b1.wanted = true
                row.b1.label:SetText(L["Load"])
                row.b2.wanted = true
                row.b2.label:SetText("x")
                row.b1:SetScript("OnClick", function()
                    GuildOS.db.companionRoster = GuildOS:DeepCopy(p.roster)
                    GuildOS:Print(string.format(L["Loaded plan: %s"], p.name))
                    panel:Refresh()
                end)
                row.b2:SetScript("OnClick", function()
                    table.remove(w.plans, i)
                    panel:Refresh()
                end)
            else
                row.fs:SetText("")
            end
        end
        planPool.count = math.min(#w.plans, PLAN_ROWS)
        planEmpty:SetText(#w.plans == 0 and L["No saved plans yet."] or "")

        -- Checklist
        for _, b in ipairs(checkBtns) do
            b.label:SetText(tick(w.checks[b.checkKey]) .. b.checkLabel)
        end
    end

    ----------------------------------------------------------------
    -- Layout
    ----------------------------------------------------------------
    local function place(x, y, w)
        ex:ClearAllPoints()
        ex:SetPoint("TOPLEFT", panel, "TOPLEFT", x, -y)
        ex:SetWidth(w)
        local cy = 0
        for _, it in ipairs(items) do
            cy = cy + (it:put(0, cy, w) or 0)
        end
        ex:SetHeight(math.max(10, cy))
        return cy
    end

    local origRelayout = panel.Relayout
    function panel:Relayout(w, h)
        w = w or parent:GetWidth()
        if not w or w < 1 then return origRelayout(self, w, h) end
        local pad = 10
        local wide = w >= TWO_COL_AT
        origRelayout(self, wide and (LEFT_W + pad + 22) or w, h)
        if wide then
            local width = math.max(320, w - LEFT_W - pad - 22 - pad - 12)
            local used = place(pad + LEFT_W + 22, 8, width)
            self.contentHeight = math.max(self.contentHeight or 0, used + 16)
        else
            local y = (self.contentHeight or 0) + 6
            local used = place(pad, y, math.max(280, w - pad * 2 - 12))
            self.contentHeight = y + used + 16
        end
    end

    local origRefresh = panel.Refresh
    function panel:Refresh()
        origRefresh(self)
        local ok, err = pcall(ex.Update, ex)
        if not ok and not WE.warned then
            WE.warned = true
            GuildOS:Print("Web tab: " .. tostring(err))
        end
        self:Relayout()
    end

    panel.webExtras = ex
    return ex
end

----------------------------------------------------------------------
-- Wrap the panel's builder
----------------------------------------------------------------------
do
    local original = GuildOS.CreateWebPanel
    function GuildOS:CreateWebPanel(parent, win)
        local panel = original(self, parent, win)
        local ok, err = pcall(WE.Build, panel, parent)
        if not ok then GuildOS:Print("Web tab extras could not start: " .. tostring(err)) end
        return panel
    end
end
