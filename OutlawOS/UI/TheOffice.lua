----------------------------------------------------------------------
-- OutlawOS - The Office (Inner Circle tab, guild master / GM Alt / Co-GM only)
-- A guild-master desk: an overview of the guild, a recruiter tracker, an officer tracker, weekly goals,
-- guild-wide controls and the danger-zone buttons. It only reports what this client has seen or what the
-- other officers synced to it (the audit log, the strike list, the calendar, the guild roster), so a
-- number can be lower than the truth if nobody with the addon was online when it happened.
-- The sums are pure functions (Office.Tally and friends) so they can be tested without the game.
----------------------------------------------------------------------
local UI = GuildOS.UI
local C = GuildOS.Colors
local L = GuildOS.L

local Office = {}
GuildOS.Office = Office

local DAY = 86400
local STAY_DAYS = 7

-- The ranks that may open The Office (compared lower-case). The guild leader always may.
local GM_RANKS = {
    ["guild master"] = true, ["gm alt"] = true, ["co-guild master"] = true,
    ["co guild master"] = true, ["co-gm"] = true, ["co gm"] = true, ["guildmaster"] = true,
}

Office.PERIODS = {
    { key = "all",   label = "All time" },
    { key = "week",  label = "This week" },
    { key = "month", label = "This month" },
    { key = "d7",    label = "Last 7 days" },
    { key = "d30",   label = "Last 30 days" },
}

local function short(name)
    name = tostring(name or "")
    return name:match("^([^-]+)") or name
end

local function store()
    GuildOS.db.office = GuildOS.db.office or {}
    local s = GuildOS.db.office
    s.goals = s.goals or {}       -- [shortName] = { recruits = n, events = n } per week
    s.pitches = s.pitches or {}   -- [shortName] = { [dayStart] = n }, this client's own whispers
    return s
end

local function nowTs() return GetServerTime and GetServerTime() or time() end

----------------------------------------------------------------------
-- Access
----------------------------------------------------------------------
function Office:CanAccess()
    if not (IsInGuild and IsInGuild()) then return false end
    if GuildOS.Compat and GuildOS.Compat.IsGuildLeader and GuildOS.Compat.IsGuildLeader() then return true end
    local _, rank = GetGuildInfo("player")
    return rank ~= nil and GM_RANKS[tostring(rank):lower()] == true
end

----------------------------------------------------------------------
-- Time periods
----------------------------------------------------------------------
local function weekStart(t)
    if GuildOS.EKO and GuildOS.EKO.WeekStart then return GuildOS.EKO:WeekStart(t) end
    local d = date("*t", t)
    local sinceMon = ((d.wday or 2) + 5) % 7
    return t - sinceMon * DAY - (d.hour or 0) * 3600 - (d.min or 0) * 60 - (d.sec or 0)
end

-- The start of a period (a server timestamp); 0 for all time.
function Office.Since(key, now)
    now = now or nowTs()
    if key == "week" then return weekStart(now) end
    if key == "month" then
        local d = date("*t", now)
        return now - (d.day - 1) * DAY - (d.hour or 0) * 3600 - (d.min or 0) * 60 - (d.sec or 0)
    end
    if key == "d7" then return now - 7 * DAY end
    if key == "d30" then return now - 30 * DAY end
    return 0
end

----------------------------------------------------------------------
-- Pure sums
----------------------------------------------------------------------
local function blank()
    return { joined = 0, stayed = 0, promoted = 0, still = 0, strikes = 0, kicks = 0, events = 0, raids = 0, pitches = 0 }
end

-- Whether a promote event's rank text is the Outlaw rank or above it ("Outlaw", "Veteran Outlaw").
local function isOutlawRank(txt)
    txt = tostring(txt or ""):lower()
    return txt:find("outlaw", 1, true) ~= nil and not txt:find("recruit", 1, true)
end

-- input = { log = {events}, strikes = { [name] = { {by, at}, ... } }, events = { {author, when, kind, canceled} },
--           pitches = { [name] = { [dayStart] = n } }, current = { [shortName] = true } or nil }
-- Returns { people = { [shortName] = counts }, unattributed = n } for the period starting at `since`.
function Office.Tally(input, since, now)
    since = since or 0
    now = now or nowTs()
    local people, unattributed = {}, 0
    local function P(name)
        name = short(name)
        people[name] = people[name] or blank()
        return people[name]
    end

    -- Everything that happened to each person, so a join can be followed to what came after it.
    local byTarget = {}
    for _, e in ipairs(input.log or {}) do
        if e.target then
            local t = short(e.target)
            byTarget[t] = byTarget[t] or {}
            table.insert(byTarget[t], e)
        end
    end

    for _, e in ipairs(input.log or {}) do
        local ts = e.timestamp or 0
        if e.action == "join" and ts >= since then
            if not e.author or e.author == "" then
                unattributed = unattributed + 1
            else
                local p = P(e.author)
                p.joined = p.joined + 1
                local target = short(e.target)
                local leftAt, promoted
                for _, f in ipairs(byTarget[target] or {}) do
                    local fts = f.timestamp or 0
                    if fts > ts then
                        if (f.action == "leave" or f.action == "kick") and (not leftAt or fts < leftAt) then leftAt = fts end
                        if f.action == "promote" and isOutlawRank(f.detail) then promoted = true end
                    end
                end
                if promoted then p.promoted = p.promoted + 1 end
                if leftAt then
                    if leftAt - ts >= STAY_DAYS * DAY then p.stayed = p.stayed + 1 end
                else
                    if now - ts >= STAY_DAYS * DAY then p.stayed = p.stayed + 1 end
                    -- Still here: the roster says so when it is known, otherwise no leave was logged.
                    if not input.current or input.current[target] then p.still = p.still + 1 end
                end
            end
        elseif e.action == "kick" and ts >= since and e.author and e.author ~= "" then
            P(e.author).kicks = P(e.author).kicks + 1
        end
    end

    for _, list in pairs(input.strikes or {}) do
        for _, s in ipairs(list) do
            if s.by and (s.at or 0) >= since then P(s.by).strikes = P(s.by).strikes + 1 end
        end
    end

    for _, ev in ipairs(input.events or {}) do
        local w = tonumber(ev.when) or 0
        if ev.author and not ev.canceled and w >= since and w <= now then
            local p = P(ev.author)
            p.events = p.events + 1
            if ev.kind == "RAID" then p.raids = p.raids + 1 end
        end
    end

    for name, days in pairs(input.pitches or {}) do
        for dayStart, n in pairs(days) do
            if (tonumber(dayStart) or 0) + DAY > since then P(name).pitches = P(name).pitches + (tonumber(n) or 0) end
        end
    end

    return { people = people, unattributed = unattributed }
end

-- Join conversion: of the people a recruiter pitched, how many joined. Nil when there were no pitches.
function Office.Conversion(c)
    if not c or (c.pitches or 0) <= 0 then return nil end
    return math.min(100, math.floor((c.joined or 0) / c.pitches * 100 + 0.5))
end

-- Goal progress for the current week: { recruits = {have, want}, events = {have, want}, met = bool } or nil.
function Office.GoalState(goal, weekCounts)
    if not goal or ((goal.recruits or 0) <= 0 and (goal.events or 0) <= 0) then return nil end
    weekCounts = weekCounts or blank()
    local r = { weekCounts.joined or 0, goal.recruits or 0 }
    local e = { weekCounts.events or 0, goal.events or 0 }
    return { recruits = r, events = e, met = (r[1] >= r[2]) and (e[1] >= e[2]) }
end

----------------------------------------------------------------------
-- Live data
----------------------------------------------------------------------
-- The guild roster: { [shortName] = { rank, rankIndex, online, lastOnline (seconds ago, nil = unknown) } }
function Office:ReadRoster()
    local out, count = {}, 0
    if not (GetNumGuildMembers and GetGuildRosterInfo) then return out, 0 end
    local n = GetNumGuildMembers() or 0
    for i = 1, n do
        local full, rank, rankIndex, _, _, _, _, _, online = GetGuildRosterInfo(i)
        if full then
            local ago
            if online then ago = 0
            elseif GetGuildRosterLastOnline then
                local y, m, d, h = GetGuildRosterLastOnline(i)
                if y then ago = (((y * 12 + (m or 0)) * 30 + (d or 0)) * 24 + (h or 0)) * 3600 end
            end
            out[short(full)] = { rank = rank, rankIndex = rankIndex, online = online and true or false, lastOnline = ago }
            count = count + 1
        end
    end
    return out, count
end

local function agoText(sec)
    if sec == nil then return "?" end
    if sec < 600 then return L["online"] end
    local d = math.floor(sec / DAY)
    if d >= 1 then return d .. "d" end
    return math.floor(sec / 3600) .. "h"
end

function Office:CountPitch()
    local me = short(GuildOS.Compat and GuildOS.Compat.PlayerName and GuildOS.Compat.PlayerName() or UnitName("player"))
    local days = store().pitches
    days[me] = days[me] or {}
    local d = date("*t", nowTs())
    local dayStart = nowTs() - (d.hour or 0) * 3600 - (d.min or 0) * 60 - (d.sec or 0)
    days[me][dayStart] = (days[me][dayStart] or 0) + 1
    -- A year of days is plenty.
    for k in pairs(days[me]) do if k < nowTs() - 400 * DAY then days[me][k] = nil end end
end

local function collect(roster)
    local cal = {}
    if GuildOS.Calendar and GuildOS.Calendar.GetEvents then
        for _, e in pairs(GuildOS.Calendar:GetEvents() or {}) do
            if type(e) == "table" then cal[#cal + 1] = { author = e.author, when = e.when, kind = e.kind, canceled = e.canceled } end
        end
    end
    local current
    if roster and next(roster) then
        current = {}
        for name in pairs(roster) do current[name] = true end
    end
    return {
        log = GuildOS.GuildManager and GuildOS.GuildManager:GetLog() or {},
        strikes = GuildOS.EKO and GuildOS.EKO.Strikes and GuildOS.EKO:Strikes() or {},
        events = cal,
        pitches = store().pitches,
        current = current,
    }
end

-- Everything the screen and the Discord export draw, for one period.
function Office:Snapshot(periodKey)
    local now = nowTs()
    local since = Office.Since(periodKey, now)
    local roster, memberCount = self:ReadRoster()
    local input = collect(roster)
    local tally = Office.Tally(input, since, now)
    local weekTally = Office.Tally(input, Office.Since("week", now), now)

    -- The officers: rank at or above the guild's officer line, plus the named leaders.
    local maxRank = (GuildOS.db.settings and GuildOS.db.settings.officerMaxRank) or 1
    local officers, recruiters = {}, {}
    for name, r in pairs(roster) do
        if r.rankIndex and r.rankIndex <= maxRank then officers[name] = true end
    end
    if GuildOS.EKO and GuildOS.EKO.LEADERS then
        for _, l in ipairs(GuildOS.EKO.LEADERS) do
            local n = short(l.name)
            if l.role == "Recruiter" then recruiters[n] = true else officers[n] = true end
        end
    end
    for name, c in pairs(tally.people) do if c.joined > 0 then recruiters[name] = true end end

    local function row(name)
        local c = tally.people[name] or blank()
        local wk = weekTally.people[name] or blank()
        local r = roster[name]
        return {
            name = name, c = c, week = wk, rank = r and r.rank or "?", lastOnline = r and r.lastOnline,
            online = r and r.online, goal = Office.GoalState(store().goals[name], wk),
            conv = Office.Conversion(c),
        }
    end
    local recRows, offRows = {}, {}
    for name in pairs(recruiters) do recRows[#recRows + 1] = row(name) end
    for name in pairs(officers) do offRows[#offRows + 1] = row(name) end
    table.sort(recRows, function(a, b)
        if a.c.joined ~= b.c.joined then return a.c.joined > b.c.joined end
        return a.name < b.name
    end)
    table.sort(offRows, function(a, b)
        local ai, bi = (roster[a.name] or {}).rankIndex or 99, (roster[b.name] or {}).rankIndex or 99
        if ai ~= bi then return ai < bi end
        return a.name < b.name
    end)

    -- Overview
    local online = 0
    for _, r in pairs(roster) do if r.online then online = online + 1 end end
    local counts = GuildOS.RosterLog and GuildOS.RosterLog.CountsSince and GuildOS.RosterLog:CountsSince(since) or {}
    local ready, promo = 0, 0
    if GuildOS.GuildManager and GuildOS.GuildManager.GetSuggestions then
        local ok, sug = pcall(GuildOS.GuildManager.GetSuggestions, GuildOS.GuildManager)
        if ok and sug then ready, promo = #(sug.trialsReady or {}), #(sug.promoteCandidates or {}) end
    end
    local bank = GuildOS.Compat and GuildOS.Compat.GuildBankMoney and GuildOS.Compat.GuildBankMoney()
    if not bank and GuildOS.GuildBank and GuildOS.GuildBank.Store then bank = GuildOS.GuildBank:Store().moneyNow end
    local bounty
    if GuildOS.EKO and GuildOS.EKO.VerifiedClears then
        local ok, list = pcall(GuildOS.EKO.VerifiedClears, GuildOS.EKO)
        if ok and type(list) == "table" then bounty = #list end
    end

    return {
        period = periodKey, since = since, now = now,
        members = memberCount, online = online,
        joins = counts.join or 0, leaves = counts.leave or 0, kicks = counts.kick or 0,
        trialsReady = ready, promoteCandidates = promo, bank = bank, bountyClears = bounty,
        unattributed = tally.unattributed,
        recruiters = recRows, officers = offRows,
    }
end

----------------------------------------------------------------------
-- Text for Discord
----------------------------------------------------------------------
local function periodLabel(key)
    for _, p in ipairs(Office.PERIODS) do if p.key == key then return p.label end end
    return key
end

local function goldText(copper)
    if not copper then return "?" end
    return string.format("%dg", math.floor(copper / 10000))
end

function Office.ExportText(s)
    local out = {}
    local function add(t) out[#out + 1] = t end
    add("**The Office - " .. periodLabel(s.period) .. "**")
    add(string.format("Members %d (%d online) | Joined %d, left %d, kicked %d", s.members, s.online, s.joins, s.leaves, s.kicks))
    add(string.format("Trials ready %d | Ready to promote %d | Bank %s%s", s.trialsReady, s.promoteCandidates, goldText(s.bank),
        s.bountyClears and (" | Bounty clears " .. s.bountyClears) or ""))
    add("")
    add("**Recruiters** (joined / stayed " .. STAY_DAYS .. "d+ / promoted / still in guild)")
    if #s.recruiters == 0 then add("Nobody credited yet.") end
    for _, r in ipairs(s.recruiters) do
        add(string.format("%s: %d / %d / %d / %d", r.name, r.c.joined, r.c.stayed, r.c.promoted, r.c.still))
    end
    if s.unattributed > 0 then add(string.format("(%d joins with no inviter on record)", s.unattributed)) end
    add("")
    add("**Officers** (recruits / strikes / kicks / events / raids / last on)")
    for _, r in ipairs(s.officers) do
        add(string.format("%s: %d / %d / %d / %d / %d / %s", r.name, r.c.joined, r.c.strikes, r.c.kicks, r.c.events, r.c.raids,
            agoText(r.lastOnline)))
    end
    return table.concat(out, "\n")
end

-- A line of at most 255 characters for officer chat.
function Office.ChatLine(s)
    local top, topN = nil, 0
    for _, r in ipairs(s.recruiters) do if r.c.joined > topN then top, topN = r.name, r.c.joined end end
    local line = string.format("Office (%s): %d members, %d joined, %d left, %d trials ready%s.", periodLabel(s.period),
        s.members, s.joins, s.leaves, s.trialsReady, top and (", top recruiter " .. top .. " (" .. topN .. ")") or "")
    return line:sub(1, 255)
end

----------------------------------------------------------------------
-- Dialogs
----------------------------------------------------------------------
GuildOS.Dialogs["OUTLAWOS_OFFICE_CONFIRM"] = {
    text = "%s",
    button1 = L["Yes"] or "Yes",
    button2 = L["Cancel"],
    OnAccept = function(_, data) if data and data.run then GuildOS:SafeCall(data.run) end end,
    timeout = 0, whileDead = true, hideOnEscape = true, showAlert = true, preferredIndex = 3,
}

local function confirm(text, run)
    GuildOS:ShowDialog("OUTLAWOS_OFFICE_CONFIRM", text, nil, { run = run })
end

-- A small window with the text selected, to copy into Discord.
local exportFrame
local function showExport(text)
    if not exportFrame then
        local f = CreateFrame("Frame", "OutlawOSOfficeExport", UIParent, "BackdropTemplate")
        f:SetSize(520, 360)
        f:SetPoint("CENTER")
        f:SetFrameStrata("DIALOG")
        f:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
        f:SetBackdropColor(GuildOS.Colors.well.r, GuildOS.Colors.well.g, GuildOS.Colors.well.b, 0.97)
        f:SetBackdropBorderColor(0.4, 0.4, 0.45, 1)
        f:EnableMouse(true)
        f:SetMovable(true)
        f:RegisterForDrag("LeftButton")
        f:SetScript("OnDragStart", f.StartMoving)
        f:SetScript("OnDragStop", f.StopMovingOrSizing)
        local title = UI:CreateText(f, L["Copy for Discord: press Ctrl+C, then close"], 11, C.text.r, C.text.g, C.text.b)
        title:SetPoint("TOPLEFT", 10, -10)
        local scroll = CreateFrame("ScrollFrame", "OutlawOSOfficeExportScroll", f, "UIPanelScrollFrameTemplate")
        scroll:SetPoint("TOPLEFT", 10, -32)
        scroll:SetPoint("BOTTOMRIGHT", -30, 40)
        local box = CreateFrame("EditBox", nil, scroll)
        box:SetMultiLine(true)
        box:SetFontObject(ChatFontNormal or GameFontNormal)
        box:SetWidth(470)
        box:SetAutoFocus(false)
        box:SetScript("OnEscapePressed", function() f:Hide() end)
        scroll:SetScrollChild(box)
        local close = UI:CreateButton(f, L["Close"], 80, 22)
        close:SetPoint("BOTTOMRIGHT", -10, 10)
        close:SetScript("OnClick", function() f:Hide() end)
        f.box = box
        exportFrame = f
    end
    exportFrame.box:SetText(text)
    exportFrame:Show()
    exportFrame.box:SetFocus()
    exportFrame.box:HighlightText()
end

----------------------------------------------------------------------
-- The screen
----------------------------------------------------------------------
local OFFICER_RANK_STEPS = { 0, 1, 2, 3, 4 }

function Office:BuildSub(panel)
    local H = GuildOS.MgmtHelpers
    local GAP = tonumber(UI.GAP) or 8
    local periodIdx = 2
    local snapshot
    local refresh

    -- Top bar
    local periodBtn = UI:CreateButton(panel, "", 130, 22)
    periodBtn:SetPoint("TOPLEFT", 0, 0)
    local copyBtn = UI:CreateButton(panel, L["Copy for Discord"], 130, 22)
    copyBtn:SetPoint("LEFT", periodBtn, "RIGHT", 6, 0)
    local chatBtn = UI:CreateButton(panel, L["Post to officer chat"], 140, 22)
    chatBtn:SetPoint("LEFT", copyBtn, "RIGHT", 6, 0)
    local note = UI:CreateText(panel, L["Counts only what this client and the other officers' addons saw."], 9, C.textDim.r, C.textDim.g, C.textDim.b)
    note:SetPoint("TOPLEFT", 0, -26)

    local holder = CreateFrame("Frame", nil, panel)
    holder:SetPoint("TOPLEFT", 0, -(22 + 16 + GAP))
    holder:SetPoint("BOTTOMRIGHT", 0, 0)
    local _, content = H.MakeScrollList(holder, "OutlawOSOfficeScroll")

    local body
    local function T(parent, text, size, col, x, y, justify, w)
        col = col or C.silver
        local fs = UI:CreateText(parent, text, size or 10, col.r, col.g, col.b)
        fs:SetPoint("TOPLEFT", x, -y)
        if w then fs:SetWidth(w); fs:SetWordWrap(false); fs:SetJustifyH(justify or "LEFT") end
        return fs
    end
    local function B(parent, label, w, x, y, onClick, tip)
        local b = UI:CreateButton(parent, label, w, 22)
        b:SetPoint("TOPLEFT", x, -y)
        b:SetScript("OnClick", onClick)
        if tip then
            b:HookScript("OnEnter", function(self)
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT"); GameTooltip:SetText(tip, 1, 1, 1, 1, true); GameTooltip:Show()
            end)
            b:HookScript("OnLeave", function() GameTooltip:Hide() end)
        end
        return b
    end
    local function section(parent, text, y)
        local f = CreateFrame("Frame", nil, parent)
        f:SetHeight(18)
        f:SetPoint("TOPLEFT", 0, -y)
        f:SetPoint("TOPRIGHT", 0, -y)
        local lbl = UI:CreateSectionTitle(f, text, false)
        lbl:SetPoint("TOPLEFT", 0, 0)
        return y + 24
    end
    local function numText(n) return tostring(n or 0) end

    local function draw()
        if body then body:Hide() end
        body = CreateFrame("Frame", nil, content)
        body:SetPoint("TOPLEFT", 0, 0)
        body:SetPoint("TOPRIGHT", 0, 0)
        local per = Office.PERIODS[periodIdx]
        local s = snapshot
        local y = 0
        local ROW = 20

        -- Overview
        y = section(body, L["Overview"], y)
        local line1 = string.format("%s: %d (%d %s)   %s: %d   %s: %d   %s: %d",
            L["Members"], s.members, s.online, L["online"], L["Joined"], s.joins, L["Left"], s.leaves, L["Kicked"], s.kicks)
        T(body, line1, 11, C.text, 0, y); y = y + 18
        local line2 = string.format("%s: %d   %s: %d   %s: %s%s", L["Trials ready"], s.trialsReady, L["Ready to promote"],
            s.promoteCandidates, L["Guild bank"], goldText(s.bank),
            s.bountyClears and string.format("   %s: %d", L["Bounty clears this week"], s.bountyClears) or "")
        T(body, line2, 11, C.text, 0, y); y = y + 26

        -- Recruiter tracker
        y = section(body, L["Recruiter tracker"] .. " - " .. L[per.label], y)
        local rc = { { L["Name"], 8 }, { L["Joined"], 150 }, { L["Stayed 7d+"], 215 }, { L["Promoted"], 290 },
                     { L["Still in"], 360 }, { L["Pitches"], 425 }, { L["Join %"], 490 } }
        for _, col in ipairs(rc) do T(body, col[1], 9, C.textDim, col[2], y) end
        y = y + 16
        if #s.recruiters == 0 then
            T(body, L["Nobody is credited with a join yet."], 10, C.silver, 8, y); y = y + ROW
        end
        for i, r in ipairs(s.recruiters) do
            local row = H.MakeRow(body, y, i, ROW)
            local function cell(text, x, col)
                local fs = UI:CreateText(row, text, 10, (col or C.silver).r, (col or C.silver).g, (col or C.silver).b)
                fs:SetPoint("LEFT", x, 0)
            end
            cell(r.name, 8, C.text)
            cell(numText(r.c.joined), 150, C.text)
            cell(numText(r.c.stayed), 215)
            cell(numText(r.c.promoted), 290)
            cell(numText(r.c.still), 360)
            cell(r.c.pitches > 0 and numText(r.c.pitches) or "-", 425)
            cell(r.conv and (r.conv .. "%") or "-", 490)
            y = y + ROW + 2
        end
        if s.unattributed > 0 then
            T(body, string.format(L["%d joins have no inviter on record."], s.unattributed), 9, C.textDim, 8, y); y = y + 16
        end
        T(body, L["Pitches and Join % are only known for whispers sent from this PC."], 9, C.textDim, 8, y); y = y + 24

        -- Officer tracker
        y = section(body, L["Officer tracker"] .. " - " .. L[per.label], y)
        local oc = { { L["Name"], 8 }, { L["Rank"], 130 }, { L["Recruits"], 235 }, { L["Strikes"], 290 }, { L["Kicks"], 345 },
                     { L["Events"], 395 }, { L["Raids"], 445 }, { L["Last on"], 495 }, { L["Weekly goal"], 555 } }
        for _, col in ipairs(oc) do T(body, col[1], 9, C.textDim, col[2], y) end
        y = y + 16
        if #s.officers == 0 then
            T(body, L["No officers found in the guild roster."], 10, C.silver, 8, y); y = y + ROW
        end
        for i, r in ipairs(s.officers) do
            local row = H.MakeRow(body, y, i, ROW)
            local function cell(text, x, col, w)
                local fs = UI:CreateText(row, text, 10, (col or C.silver).r, (col or C.silver).g, (col or C.silver).b)
                fs:SetPoint("LEFT", x, 0)
                if w then fs:SetWidth(w); fs:SetWordWrap(false); fs:SetJustifyH("LEFT") end
            end
            cell(r.name, 8, C.text, 118)
            cell(tostring(r.rank), 130, C.silver, 100)
            cell(numText(r.c.joined), 235)
            cell(numText(r.c.strikes), 290)
            cell(numText(r.c.kicks), 345)
            cell(numText(r.c.events), 395)
            cell(numText(r.c.raids), 445)
            cell(agoText(r.lastOnline), 495, r.online and C.online or C.silver)
            if r.goal then
                local g = r.goal
                local txt = string.format("%d/%d  %d/%d", g.recruits[1], g.recruits[2], g.events[1], g.events[2])
                cell(txt, 555, g.met and C.green or C.warn)
            else
                cell("-", 555)
            end
            y = y + ROW + 2
        end
        T(body, L["Weekly goal shows recruits and events this week against the goal set below."], 9, C.textDim, 8, y); y = y + 24

        -- Goals form
        y = section(body, L["Weekly goals"], y)
        T(body, L["Name"], 10, C.text, 0, y + 4)
        local nameBox = UI:CreateInput(body, 130, 22, { max = 40 })
        nameBox:SetPoint("TOPLEFT", 44, -y)
        T(body, L["Recruits"], 10, C.text, 190, y + 4)
        local recBox = UI:CreateInput(body, 36, 22, { numeric = true, max = 3, justify = "CENTER" })
        recBox:SetPoint("TOPLEFT", 250, -y)
        T(body, L["Events"], 10, C.text, 296, y + 4)
        local evBox = UI:CreateInput(body, 36, 22, { numeric = true, max = 3, justify = "CENTER" })
        evBox:SetPoint("TOPLEFT", 346, -y)
        B(body, L["Set goal"], 80, 394, y, function()
            local n = short(strtrim(nameBox:GetText() or ""))
            if n == "" then GuildOS:Print(L["Type a name first."]) return end
            local r, e = tonumber(recBox:GetText()) or 0, tonumber(evBox:GetText()) or 0
            store().goals[n] = (r > 0 or e > 0) and { recruits = r, events = e } or nil
            refresh()
        end, L["Zero for both clears the goal."])
        y = y + 30
        local gi = 0
        local names = {}
        for n in pairs(store().goals) do names[#names + 1] = n end
        table.sort(names)
        for _, n in ipairs(names) do
            local g = store().goals[n]
            T(body, string.format("%s: %d %s, %d %s", n, g.recruits or 0, L["recruits"], g.events or 0, L["events"]), 10, C.silver, 8, y)
            y = y + 16; gi = gi + 1
        end
        if gi == 0 then T(body, L["No goals set."], 10, C.silver, 8, y); y = y + 16 end
        y = y + 10

        -- Guild-wide controls
        y = section(body, L["Guild settings"], y)
        local maxRank = (GuildOS.db.settings and GuildOS.db.settings.officerMaxRank) or 1
        B(body, string.format(L["Officer line: rank %d and above"], maxRank), 230, 0, y, function()
            local nextRank = ((maxRank + 1) % (#OFFICER_RANK_STEPS))
            if GuildOS.SetOfficerMaxRank and GuildOS:SetOfficerMaxRank(nextRank) then refresh()
            else GuildOS:Print(L["Only an officer can change this."]) end
        end, L["Which ranks count as officers for OutlawOS. Every officer's addon follows this."])
        local days = GuildOS.TrialTracker and GuildOS.TrialTracker:GetDays() or 14
        B(body, string.format(L["Trial length: %d days"], days), 160, 240, y, function()
            if not GuildOS.TrialTracker then return end
            local steps = { 7, 10, 14, 21, 28 }
            local at = 1
            for i, v in ipairs(steps) do if v == days then at = i end end
            GuildOS.TrialTracker:SetDays(steps[(at % #steps) + 1])
            refresh()
        end, L["How long a recruit's trial runs before it is ready to review."])
        local auto = GuildOS.TrialTracker and GuildOS.TrialTracker:IsAutoOn()
        B(body, auto and L["Auto trials: on"] or L["Auto trials: off"], 140, 408, y, function()
            if GuildOS.TrialTracker then GuildOS.TrialTracker:SetAuto(not auto); refresh() end
        end, L["Start a trial automatically for every new member."])
        y = y + 30

        -- Leadership rounds
        y = section(body, L["Leadership round"], y)
        B(body, L["Post summary to officer chat"], 220, 0, y, function()
            if GuildOS.Office then Office:PostChat() end
        end, L["Sends one short line with this period's numbers to officer chat."])
        B(body, L["Copy for Discord"], 140, 230, y, function() showExport(Office.ExportText(snapshot)) end)
        y = y + 34

        -- Danger zone
        y = section(body, L["Danger zone"], y)
        B(body, L["Clear audit log"], 150, 0, y, function()
            confirm(L["Clear the whole audit log on this PC? Recruiter counts that come from it start over."], function()
                GuildOS.GuildManager:ClearLog(); refresh()
            end)
        end)
        B(body, L["Clear weekly goals"], 150, 160, y, function()
            confirm(L["Remove every weekly goal?"], function() store().goals = {}; refresh() end)
        end)
        B(body, L["Clear pitch counts"], 150, 320, y, function()
            confirm(L["Reset the whisper counts kept on this PC?"], function() store().pitches = {}; refresh() end)
        end)
        y = y + 34

        body:SetHeight(y)
        content:SetHeight(math.max(1, y))
    end

    refresh = function()
        local per = Office.PERIODS[periodIdx]
        periodBtn.label:SetText(L[per.label])
        snapshot = Office:Snapshot(per.key)
        draw()
    end

    periodBtn:SetScript("OnClick", function() periodIdx = periodIdx % #Office.PERIODS + 1; refresh() end)
    copyBtn:SetScript("OnClick", function()
        snapshot = Office:Snapshot(Office.PERIODS[periodIdx].key)
        showExport(Office.ExportText(snapshot))
    end)
    chatBtn:SetScript("OnClick", function() Office:PostChat(Office.PERIODS[periodIdx].key) end)

    -- The roster arrives a moment after login: redraw when it does.
    local f = CreateFrame("Frame")
    f:RegisterEvent("GUILD_ROSTER_UPDATE")
    f:SetScript("OnEvent", function() if panel:IsShown() then refresh() end end)

    return refresh
end

function Office:PostChat(periodKey)
    if not self:CanAccess() then return end
    local s = self:Snapshot(periodKey or "week")
    SendChatMessage(Office.ChatLine(s), "OFFICER")
end
