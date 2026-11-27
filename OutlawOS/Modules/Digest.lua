----------------------------------------------------------------------
-- Guild OS - Login Digest
-- "Since your last login: N new members, X items looted, ..." — a quick
-- catch-up shown once on login (and on demand via /guildos digest).
-- Build() is pure data; the popup uses the UI factories at runtime.
----------------------------------------------------------------------
local Digest = {}
GuildOS.Digest = Digest
local L = GuildOS.L

local FEED_LINES = 5             -- lines from guildos.me in one digest
local FEED_SEEN_S = 14 * 86400   -- how long a line shown is remembered: the site sends a week of them

function Digest:Initialize()
    GuildOS.db.digest = GuildOS.db.digest or {}
    if GuildOS.db.digest.enabled == nil then GuildOS.db.digest.enabled = true end
    if GuildOS.db.digest.lastSeen == nil then GuildOS.db.digest.lastSeen = 0 end
    GuildOS.db.digest.feedSeen = GuildOS.db.digest.feedSeen or {}
end

-- What guildos.me said that this client has not shown yet (guildos-web #259), the newest first, and
-- what the block as a whole tells: an event the site says is not said again by this client's own lines.
local function fromSite()
    local seen = GuildOS.db.digest and GuildOS.db.digest.feedSeen or {}
    local unseen, told = {}, {}
    for _, item in ipairs(GuildOS.CompanionImport and GuildOS.CompanionImport:FeedLines() or {}) do
        told[item.type] = true
        told[item.type .. "|" .. item.at] = true
        if item.key then told[item.type .. "|" .. item.key] = true end
        if not seen[item.id] and #unseen < FEED_LINES then unseen[#unseen + 1] = item end
    end
    return unseen, told
end

local function myKey()
    return GuildOS:GetPlayerKey(GuildOS.Compat.PlayerName(), GetRealmName())
end

----------------------------------------------------------------------
-- Build the digest lines for everything that changed since `since`
-- (a server timestamp). Returns an array of strings.
----------------------------------------------------------------------
function Digest:Build(since)
    since = since or GuildOS.db.digest.lastSeen or 0
    local lines = {}
    local feed, told = fromSite()

    -- New members (first observed by Guild OS since last login, after its first look at the guild)
    local newCount, newNames = 0, {}
    local newSince = math.max(since, GuildOS.db.firstSeenSince or 0)
    for key, ts in pairs(GuildOS.db.firstSeen or {}) do
        if ts and ts > newSince then
            newCount = newCount + 1
            if #newNames < 3 then newNames[#newNames + 1] = key:match("^([^-]+)") or key end
        end
    end
    if newCount > 0 then
        local names = table.concat(newNames, ", ")
        if newCount > #newNames then names = names .. " +" .. (newCount - #newNames) end
        lines[#lines + 1] = string.format(L["%d new member(s): %s"], newCount, names)
    end

    -- Roster changes since last login (from the audit log)
    if GuildOS.RosterLog then
        local c = GuildOS.RosterLog:CountsSince(since)
        if c.kick > 0 then lines[#lines + 1] = string.format(L["%d member(s) removed"], c.kick) end
        if c.leave > 0 then lines[#lines + 1] = string.format(L["%d member(s) left"], c.leave) end
    end

    -- Raid sessions tracked since last login
    local raidCount = 0
    if GuildOS.db.raidTracker and GuildOS.db.raidTracker.sessions then
        for _, s in pairs(GuildOS.db.raidTracker.sessions) do
            if s.startTime and s.startTime > since then raidCount = raidCount + 1 end
        end
    end
    if raidCount > 0 then
        lines[#lines + 1] = string.format(L["%d raid session(s) tracked"], raidCount)
    end

    -- Loot recorded since last login
    local lootCount = 0
    for _, e in ipairs(GuildOS.db.lootHistory or {}) do
        if (e.timestamp or 0) > since then lootCount = lootCount + 1 end
    end
    if lootCount > 0 then
        lines[#lines + 1] = string.format(L["%d item(s) looted"], lootCount)
    end

    -- Your own points change since last login
    if GuildOS.Points and GuildOS.db.points and GuildOS.db.points.log then
        local mk = myKey()
        local delta = 0
        for _, e in ipairs(GuildOS.db.points.log) do
            if e.key == mk and (e.ts or 0) > since then delta = delta + (e.delta or 0) end
        end
        if delta ~= 0 then
            lines[#lines + 1] = string.format(L["Your points changed by %+d (now %d)"], delta, GuildOS.Points:Get(mk))
        end
    end

    -- Milestones & guild anniversaries
    if GuildOS.Milestones then
        for _, line in ipairs(GuildOS.Milestones:GetDigestLines(since, told)) do
            lines[#lines + 1] = line
        end
    end
    -- WoW: Forever's founding: who joined as a founder, the window, the guild's anniversaries (#209)
    if GuildOS.Founding then
        for _, line in ipairs(GuildOS.Founding:GetDigestLines(since, GetServerTime(), told)) do
            lines[#lines + 1] = line
        end
    end

    -- Upcoming raid reminder (event within the next 24h)
    if GuildOS.Calendar and GuildOS.Calendar.GetDigestLines then
        local calLines = GuildOS.Calendar:GetDigestLines()
        if calLines then
            for _, line in ipairs(calLines) do
                lines[#lines + 1] = "|cff4CB8FF" .. line .. "|r"
            end
        end
    end

    -- Alliance: how many allied raids are coming up in the next week. One line,
    -- and only when this guild is federated and something is actually scheduled.
    if GuildOS.Alliance and GuildOS.Alliance:Get() and GuildOS.Calendar
        and GuildOS.Calendar.AllianceEvents then
        local horizon = GetServerTime() + (7 * 86400)
        local count = 0
        for _, e in ipairs(GuildOS.Calendar:AllianceEvents()) do
            if (tonumber(e.when) or 0) <= horizon then
                count = count + 1
            end
        end
        if count > 0 then
            local gold = GuildOS.Colors.gold
            lines[#lines + 1] = string.format("|cff%02x%02x%02x", gold.r * 255, gold.g * 255, gold.b * 255) ..
                string.format(L["%d allied event(s) this week"], count) .. "|r"
        end
    end

    -- New bulletin notices (most recent few)
    if GuildOS.Bulletin then
        local shown = 0
        for _, m in ipairs(GuildOS.Bulletin:GetMessages()) do
            if (m.ts or 0) > since and shown < 3 then
                lines[#lines + 1] = "|cffEDCC7B" .. L["Notice:"] .. "|r " .. (m.text or "")
                shown = shown + 1
            end
        end
    end

    -- New polls opened since last login
    if GuildOS.Polls then
        local newPolls = 0
        for _, p in pairs(GuildOS.Polls:GetList()) do
            if not p.closed and (p.ts or 0) > since then newPolls = newPolls + 1 end
        end
        if newPolls > 0 then
            lines[#lines + 1] = string.format(L["%d new poll(s) — cast your vote"], newPolls)
        end
    end

    -- Officer-only catch-up
    if GuildOS:IsOfficer() then
        if GuildOS.TrialTracker then
            -- Ready to review: their end, from the guild's length, has passed with no decision (#249).
            local due = GuildOS.TrialTracker:CountReady()
            if due > 0 then
                lines[#lines + 1] = string.format(L["%d trial(s) ready for decision"], due)
            end
        end
        if GuildOS.GuildManager and GuildOS.GuildManager.GetInactiveMembers then
            local inactive = GuildOS.GuildManager:GetInactiveMembers(GuildOS.GuildManager.DEFAULT_INACTIVE_DAYS)
            if inactive and #inactive > 0 then
                lines[#lines + 1] = string.format(L["%d inactive member(s)"], #inactive)
            end
        end
    end

    -- WoW: Forever: what the guild earned (#216), and the officers' reminder of its setup (#217)
    if GuildOS.Achievements then
        for _, line in ipairs(GuildOS.Achievements:GetDigestLines(told)) do
            lines[#lines + 1] = line
        end
    end
    local setup = GuildOS.Activation and GuildOS.Activation:GetDigestLine(GetServerTime())
    if setup then lines[#lines + 1] = setup end
    -- Beside other news, never a reason to open the digest on its own at every login.
    local nearest = GuildOS.Achievements and GuildOS.Achievements:NextLine()
    if nearest and (#lines > 0 or #feed > 0) then lines[#lines + 1] = nearest end

    if #feed > 0 then
        lines[#lines + 1] = "|cffEDCC7B" .. L["From guildos.me"] .. "|r"
        for _, item in ipairs(feed) do lines[#lines + 1] = item.text end
    end

    return lines
end

----------------------------------------------------------------------
-- The Activity sub-tab's feed (the Gilded Feather). The same happenings as Build, kept as entries:
-- a time, a kind, the people behind them and the tab a click can go to. Build, which the login popup
-- uses, is unchanged. Every text here is plain (no colour codes), so the copy button can use it too.
----------------------------------------------------------------------
local DAY = 86400
local NEW_CAP = 30 * DAY     -- "New" reaches back this far at most
local NAMES_SHOWN = 3        -- a line names up to this many people; more are counted

local function plainText(s)
    s = tostring(s or "")
    s = s:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("|H.-|h", ""):gsub("|h", "")
    return s
end

local function shortName(full)
    full = tostring(full or "?")
    return full:match("^(.-)%-[^-]*$") or full
end

-- A label used inside a format string: its % signs are doubled, so it prints as it reads.
local function fmtSafe(s)
    return (tostring(s):gsub("%%", "%%%%"))
end

local function addPerson(list, name, ts, first)
    for _, p in ipairs(list) do
        if p.name == name then
            if (ts or 0) > p.ts then p.ts = ts end
            if first then p.first = true end
            return
        end
    end
    list[#list + 1] = { name = name, ts = ts or 0, first = first and true or false }
end

-- One line for a group of people: the names when there are few, the count when there are many.
-- `fmtNames` takes the names, `fmtCount` the count; `first` puts "First:" in front and gold on it.
local function groupLine(list, fmtNames, fmtCount)
    local names, ts, first = {}, 0, false
    for _, p in ipairs(list) do
        names[#names + 1] = p.name
        if p.ts > ts then ts = p.ts end
        if p.first then first = true end
    end
    local text
    if #names <= NAMES_SHOWN then
        text = string.format(fmtNames, table.concat(names, ", "))
    else
        text = string.format(fmtCount, #names)
    end
    if first then text = "First: " .. text end
    return text, ts, names, first
end

-- The Activity feed for everything since `since` (a server timestamp). Returns:
--   entries  - newest first, each { cat, text, ts, n, names, tone, tab, kind, first }
--   summary  - counts for the window's card, the welcome and the pinned lines
function Digest:Activity(since)
    local now = GetServerTime()
    since = since or (now - 7 * DAY)
    local out = {}
    local sum = { joins = 0, leaves = 0, raids = 0, loot = 0, clears = 0, levels = 0, notices = 0,
        welcome = {}, upcoming = nil, next = nil }

    local function emit(cat, text, ts, o)
        o = o or {}
        out[#out + 1] = { cat = cat, text = text, ts = ts or 0, n = o.n or 1, names = o.names,
            tone = o.tone, tab = o.tab, kind = o.kind, first = o.first }
    end

    -- Lines the website sent (guildos.me). `told` is what it says, so this client does not say it twice.
    local told = {}
    for _, item in ipairs(GuildOS.CompanionImport and GuildOS.CompanionImport:FeedLines() or {}) do
        told[item.type] = true
        told[item.type .. "|" .. item.at] = true
        if item.key then told[item.type .. "|" .. item.key] = true end
        if item.at > since then emit("site", plainText(item.text), item.at, { kind = "site" }) end
    end

    -- New members, as Build counts them: first seen by this client after its first look at the guild.
    local newSince = math.max(since, GuildOS.db.firstSeenSince or 0)
    local joins = {}
    for key, ts in pairs(GuildOS.db.firstSeen or {}) do
        if ts and ts > newSince then
            local nm = shortName(key)
            addPerson(joins, nm, ts)
            if ts > now - 2 * DAY then sum.welcome[#sum.welcome + 1] = nm end
        end
    end
    if #joins > 0 then
        sum.joins = #joins
        local text, ts, names = groupLine(joins, L["Joined: %s"], L["%d members joined"])
        emit("members", text, ts, { n = #joins, names = names, tone = "good", tab = { "roster" }, kind = "join" })
    end

    -- Leaves and removals, from the audit log.
    local left, kicked = {}, {}
    for _, e in ipairs((GuildOS.db.rosterLog and GuildOS.db.rosterLog.events) or {}) do
        if (e.timestamp or 0) > since and e.target then
            if e.action == "leave" then addPerson(left, shortName(e.target), e.timestamp)
            elseif e.action == "kick" then addPerson(kicked, shortName(e.target), e.timestamp) end
        end
    end
    if #left > 0 then
        sum.leaves = sum.leaves + #left
        local text, ts, names = groupLine(left, L["Left: %s"], L["%d members left"])
        emit("members", text, ts, { n = #left, names = names, tone = "bad", tab = { "roster" }, kind = "leave" })
    end
    if #kicked > 0 then
        sum.leaves = sum.leaves + #kicked
        local text, ts, names = groupLine(kicked, L["Removed: %s"], L["%d members removed"])
        emit("members", text, ts, { n = #kicked, names = names, tone = "bad", tab = { "roster" }, kind = "kick" })
    end

    -- Level milestones and dungeon clears, from the journal (it keeps a month of them).
    local levels, clears = {}, {}
    local journal = GuildOS.Journal
    for _, e in ipairs(journal and journal:GetSince(since) or {}) do
        local d = e.data or {}
        local nm = shortName(GuildOS:LocalMemberKey(e.subjectKey) or e.subjectKey)
        if e.type == "member.level" and d.level then
            levels[d.level] = levels[d.level] or {}
            addPerson(levels[d.level], nm, e.at)
        elseif e.type == "dungeon.clear" then
            local key = tostring(d.dungeonName or d.dungeonId or "?")
            clears[key] = clears[key] or {}
            addPerson(clears[key], nm, e.at, journal:IsFirstClear(e))
        end
    end
    for lvl, list in pairs(levels) do
        sum.levels = sum.levels + #list
        local text, ts, names, first = groupLine(list,
            "Reached level " .. lvl .. ": %s", "%d members reached level " .. lvl)
        emit("leveling", text, ts, { n = #list, names = names, tone = first and "gold" or nil, kind = "level", first = first })
    end
    for key, list in pairs(clears) do
        sum.clears = sum.clears + #list
        local text, ts, names, first = groupLine(list,
            "Dungeon cleared: " .. fmtSafe(key) .. " (%s)", "Dungeon cleared: " .. fmtSafe(key) .. " (%d members)")
        emit("clears", text, ts, { n = #list, names = names, tone = first and "gold" or nil, kind = "clear", first = first })
    end

    -- Single level dings, the first one ever for each level gold (the milestones' own events).
    local events = (GuildOS.db.milestones and GuildOS.db.milestones.events) or {}
    local firstDing = {}
    for _, ev in ipairs(events) do
        local lv = ev.type == "ding" and tonumber(ev.detail)
        if lv and (firstDing[lv] == nil or (ev.ts or 0) < firstDing[lv]) then firstDing[lv] = ev.ts or 0 end
    end
    for _, ev in ipairs(events) do
        if (ev.ts or 0) > since then
            if ev.type == "ding" and not told["member.level60|" .. tostring(ev.key)] then
                local lv = tonumber(ev.detail)
                local first = lv ~= nil and firstDing[lv] == ev.ts
                local text = string.format(L["%s reached level %s!"], ev.name or "?",
                    ev.detail or tostring(GuildOS.Client.maxLevel))
                if first then text = "First: " .. text end
                sum.levels = sum.levels + 1
                emit("leveling", text, ev.ts, { names = { ev.name or "?" }, tone = first and "gold" or nil,
                    kind = "ding", first = first })
            elseif ev.type == "attune" then
                emit("leveling", string.format(L["%s completed a new attunement"], ev.name or "?"), ev.ts, { kind = "attune" })
            end
        end
    end

    -- Raid sessions tracked since `since`: the raid, its date and how many were there.
    for _, s in pairs((GuildOS.db.raidTracker and GuildOS.db.raidTracker.sessions) or {}) do
        if s.startTime and s.startTime > since then
            local att = 0
            for _ in pairs(s.players or {}) do att = att + 1 end
            sum.raids = sum.raids + 1
            emit("raids", string.format(L["Raid: %s (%d attended)"], plainText(s.name or "?"), att), s.startTime,
                { tab = { "raids" }, kind = "raid" })
        end
    end

    -- Loot: the newest item and who got it, the rest counted; its list is the line's tooltip.
    local loot, units, newest = {}, 0, nil
    for _, e in ipairs(GuildOS.db.lootHistory or {}) do
        if (e.timestamp or 0) > since then
            loot[#loot + 1] = e
            units = units + (tonumber(e.count) or 1)
            if not newest or e.timestamp > newest.timestamp then newest = e end
        end
    end
    if newest then
        sum.loot = units
        local list = {}
        for _, e in ipairs(loot) do
            list[#list + 1] = plainText(e.itemName or "item") .. " to " .. shortName(e.player or "?")
        end
        local text = string.format(L["Looted: %s to %s"], plainText(newest.itemName or "item"), shortName(newest.player or "?"))
        if #loot > 1 then text = text .. string.format(L[" (+%d more)"], #loot - 1) end
        emit("loot", text, newest.timestamp, { n = #loot, names = list, tab = { "loot" }, kind = "loot" })
    end

    -- Your own points since `since`.
    if GuildOS.Points and GuildOS.db.points and GuildOS.db.points.log then
        local mk = myKey()
        local delta, last = 0, 0
        for _, e in ipairs(GuildOS.db.points.log) do
            if e.key == mk and (e.ts or 0) > since then
                delta = delta + (e.delta or 0)
                if e.ts > last then last = e.ts end
            end
        end
        if delta ~= 0 then
            emit("you", string.format(L["Your points changed by %+d (now %d)"], delta, GuildOS.Points:Get(mk)), last, { kind = "points" })
        end
    end

    -- Achievements earned in the window, and the one nearest to done (pinned, not in the timeline).
    if GuildOS.Achievements then
        for _, e in ipairs(GuildOS.Achievements:Earned()) do
            if e.at > since and not told["achievement.earned|" .. e.at] then
                emit("achievements", string.format(L["Achievement: %s"], plainText(e.title)), e.at,
                    { tab = { "guild", "achievements" }, kind = "achv" })
            end
        end
        sum.next = GuildOS.Achievements:Next()[1]
    end

    -- Polls opened in the window.
    if GuildOS.Polls then
        for _, p in pairs(GuildOS.Polls:GetList()) do
            if not p.closed and (p.ts or 0) > since then
                emit("polls", string.format(L["New poll: %s"], plainText(p.question or "?")), p.ts,
                    { tab = { "guild", "polls" }, kind = "poll" })
            end
        end
    end

    -- Notices stay in the Bulletin tab: the feed only counts them.
    if GuildOS.Bulletin then
        for _, m in ipairs(GuildOS.Bulletin:GetMessages()) do
            if (m.ts or 0) > since then sum.notices = sum.notices + 1 end
        end
    end

    -- The next event within a day, with a countdown (pinned).
    if GuildOS.Calendar then
        local ev = GuildOS.Calendar:NextEvent()
        local dt = ev and ev.when and (ev.when - now) or 0
        if dt > 0 and dt < DAY then
            sum.upcoming = string.format(L["%s soon: %s, in %dh %dm"], GuildOS.Calendar:KindLabel(ev.kind),
                plainText(ev.title), math.floor(dt / 3600), math.floor((dt % 3600) / 60))
        end
    end

    -- Lines with no time of their own: the founders, the officers' reminders, the allied events.
    if GuildOS.Founding then
        for _, line in ipairs(GuildOS.Founding:GetDigestLines(since, now, told)) do
            emit("system", plainText(line), 0, { kind = "founding" })
        end
    end
    if GuildOS:IsOfficer() then
        if GuildOS.TrialTracker then
            local due = GuildOS.TrialTracker:CountReady()
            if due > 0 then emit("system", string.format(L["%d trial(s) ready for decision"], due), 0, { kind = "officer", tab = { "management" } }) end
        end
        if GuildOS.GuildManager and GuildOS.GuildManager.GetInactiveMembers then
            local inactive = GuildOS.GuildManager:GetInactiveMembers(GuildOS.GuildManager.DEFAULT_INACTIVE_DAYS)
            if inactive and #inactive > 0 then
                emit("system", string.format(L["%d inactive member(s)"], #inactive), 0, { kind = "officer", tab = { "management" } })
            end
        end
    end
    local setup = GuildOS.Activation and GuildOS.Activation:GetDigestLine(now)
    if setup then emit("system", plainText(setup), 0, { kind = "setup" }) end

    table.sort(out, function(a, b)
        if a.ts ~= b.ts then return a.ts > b.ts end
        return a.text < b.text
    end)
    return { entries = out, summary = sum, since = since }
end

-- The window the Activity tab reads: "new" is since it was last looked at (7 days if never, or 30
-- days at most); "7" and "30" are fixed.
function Digest:ActivitySince(window)
    local now = GetServerTime()
    if window == "30" then return now - 30 * DAY end
    if window == "7" then return now - 7 * DAY end
    local seen = GuildOS.db.digest and GuildOS.db.digest.activitySeen or 0
    if seen <= 0 or seen < now - NEW_CAP then return now - 7 * DAY end
    return seen
end

-- How many lines are new since the Activity tab was last marked read (its badge).
function Digest:UnreadCount()
    local seen = GuildOS.db.digest and GuildOS.db.digest.activitySeen or 0
    local since = self:ActivitySince("new")
    local a = self:Activity(since)
    local n = a.summary.notices
    for _, e in ipairs(a.entries) do
        if e.ts > since then n = n + 1 end
    end
    return n
end

function Digest:MarkActivitySeen()
    GuildOS.db.digest = GuildOS.db.digest or {}
    GuildOS.db.digest.activitySeen = GetServerTime()
end

-- The login digest showed these: they are not shown again, and what is too old to come back is forgotten.
function Digest:MarkFeedSeen(now)
    local seen = GuildOS.db.digest.feedSeen
    for _, item in ipairs((fromSite())) do seen[item.id] = now end
    for id, at in pairs(seen) do
        if now - at > FEED_SEEN_S then seen[id] = nil end
    end
end

----------------------------------------------------------------------
-- The popup window.
----------------------------------------------------------------------
function Digest:Show(lines)
    local UI = GuildOS.UI
    local C = GuildOS.Colors
    lines = lines or self:Build()

    local f = self.frame
    if not f then
        f = CreateFrame("Frame", "GuildOSDigestFrame", UIParent, "BackdropTemplate")
        f:SetSize(420, 280)  -- EKO patch: room for the greeting
        f:SetPoint("TOP", UIParent, "TOP", 0, -140)
        f:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = GuildOS.UI:Edge(f) })
        f:SetBackdropColor(GuildOS.Colors.bg.r, GuildOS.Colors.bg.g, GuildOS.Colors.bg.b, 0.98)
        f:SetBackdropBorderColor(C.border.r, C.border.g, C.border.b, C.border.a)
        UI:StylePopup(f, { shadowSize = 16 })
        f:SetFrameStrata("HIGH")
        f:SetMovable(true)
        f:EnableMouse(true)
        f:RegisterForDrag("LeftButton")
        f:SetScript("OnDragStart", function(self2) self2:StartMoving() end)
        f:SetScript("OnDragStop", function(self2) self2:StopMovingOrSizing() end)

        f.title = UI:CreateTitle(f, L["Since your last login"], 15)
        f.title:SetPoint("TOPLEFT", 16, -14)
        -- EKO patch: the line under the greeting
        f.subtitle = UI:CreateText(f, "Here are your updates since you last logged in.", 11, C.silver.r, C.silver.g, C.silver.b)
        f.subtitle:SetPoint("TOPLEFT", 16, -36)

        f.close = UI:CreateCloseButton(f)
        f.close:SetPoint("TOPRIGHT", -8, -8)
        f.close:SetScript("OnClick", function() f:Hide() end)

        f.body = CreateFrame("Frame", nil, f)
        f.body:SetPoint("TOPLEFT", 16, -62)  -- EKO patch: under the subtitle
        f.body:SetPoint("BOTTOMRIGHT", -16, 48)

        f.openBtn = UI:CreateButton(f, "Open OutlawOS", 140, 26)  -- EKO patch
        f.openBtn:SetPoint("BOTTOM", 0, 14)
        f.openBtn:SetScript("OnClick", function()
            f:Hide()
            GuildOS:ToggleRoster()
        end)
        self.frame = f
    end

    -- EKO patch: greet by rank, "Welcome back, Officer Raistlin" (the Guild Master is the Matriarch)
    do
        local first = (UnitName("player") or ""):match("^(%S+)") or ""
        local _, rankName, rankIndex = GetGuildInfo("player")
        local title = (rankIndex == 0 and "Matriarch") or rankName
        if title and title ~= "" then
            f.title:SetText(string.format("Welcome back, %s %s!", title, first))
        else
            f.title:SetText(string.format("Welcome back, %s!", first))
        end
    end

    -- (Re)populate the body
    for _, c in pairs({ f.body:GetChildren() }) do c:Hide() end
    for _, r in pairs({ f.body:GetRegions() }) do r:Hide() end

    local y = 0
    -- Text width from the window itself: f.body can report 0 width on the first show of a session.
    local bodyW = f:GetWidth() - 32
    if #lines == 0 then
        local empty = UI:CreateText(f.body, L["Nothing new since your last login."], 11, C.silver.r, C.silver.g, C.silver.b)
        empty:SetPoint("TOPLEFT", 2, -y)
        empty:SetWidth(bodyW - 4)
    else
        for _, line in ipairs(lines) do
            local dot = UI:CreateText(f.body, "|cffEDCC7B*|r", 12, C.gold.r, C.gold.g, C.gold.b)
            dot:SetPoint("TOPLEFT", 2, -y)
            local fs = UI:CreateText(f.body, line, 11, C.text.r, C.text.g, C.text.b)
            fs:SetPoint("TOPLEFT", 18, -y)
            fs:SetWidth(bodyW - 22)
            fs:SetJustifyH("LEFT")
            y = y + math.max(20, (fs:GetStringHeight() or 14) + 8)
        end
    end
    -- The title above and the button below: a long digest grows, never runs under the button.
    f:SetHeight(math.max(280, 62 + y + 48))  -- EKO patch: the subtitle

    f:Show()
    return f
end

----------------------------------------------------------------------
-- Auto-show once on login (skipped on first run and when disabled).
----------------------------------------------------------------------
function Digest:ShowOnLogin()
    if not GuildOS.db.digest or not GuildOS.db.digest.enabled then return end
    if self.shownThisSession then return end

    local since = GuildOS.db.digest.lastSeen or 0
    -- First ever run: nothing to compare against — just start the clock.
    if since == 0 then
        GuildOS.db.digest.lastSeen = GetServerTime()
        return
    end

    local lines = self:Build(since)
    self:MarkFeedSeen(GetServerTime())
    if GuildOS.Achievements then GuildOS.Achievements:MarkSeen() end
    if GuildOS.Activation then
        if GuildOS.Activation:GetDigestLine(GetServerTime()) then GuildOS.Activation:Reminded(GetServerTime()) end
    end
    GuildOS.db.digest.lastSeen = GetServerTime()
    self.shownThisSession = true
    if #lines > 0 then
        self:Show(lines)
    end
end
