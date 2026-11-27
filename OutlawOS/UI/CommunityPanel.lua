----------------------------------------------------------------------
-- Guild OS - Guild Hub + DKP panels
-- Brings the community/loot features into the main window as real tabs
-- instead of slash-only popups:
--   * Guild hub: Activity feed, Bulletin board, Polls (sub-tabs)
--   * DKP: standings + officer controls
-- Renders from the module data APIs (Rule 3 / Rule 10).
----------------------------------------------------------------------
local UI = GuildOS.UI
local C = GuildOS.Colors
local L = GuildOS.L
local WHITE = "Interface\\Buttons\\WHITE8x8"
local TAB_H = 28        -- UI:CreateTab's fixed height
local TAB_MIN_W = 70    -- narrowest a sub-tab may be drawn
local TAB_PAD = 20      -- label padding inside a sub-tab
-- Every sub-tab lays out on the same grid (#371): content flush with the sub-tab bar's left edge,
-- its first line GAP under the sub-panel's top, blocks GAP apart, and a later section title with
-- room over it for its rule.
local GAP = UI.GAP
local SECTION_SPACE = 20   -- over a later UI:CreateSectionTitle: its rule sits 12px above it
local FIELD_H = 24         -- a one-line field, and the button beside it

----------------------------------------------------------------------
-- Shared builders
----------------------------------------------------------------------
-- A scroll list filling the panel under `top`: a region it hangs GAP below, or an offset from the
-- panel's top (GAP by default). Its child keeps the list's width, less the scroll bar's gutter, and
-- every row hangs from both top corners, so a tab built hidden (0 wide) still lays out (#371).
local function makeScroll(panel, name, top)
    local holder = CreateFrame("Frame", nil, panel)
    if type(top) == "table" then
        holder:SetPoint("TOPLEFT", top, "BOTTOMLEFT", 0, -GAP)
    else
        holder:SetPoint("TOPLEFT", 0, -(top or GAP))
    end
    holder:SetPoint("BOTTOMRIGHT", 0, 0)
    local scroll, child = UI:CreateScrollFrame(holder, name)
    scroll:SetAllPoints()
    UI:BindScrollChildWidth(scroll, child)
    return holder, child
end

local function clear(child)
    for _, c in pairs({ child:GetChildren() }) do c:Hide() end
    for _, r in pairs({ child:GetRegions() }) do r:Hide() end
end

----------------------------------------------------------------------
-- ACTIVITY sub-panel: what has happened in the guild, as a timeline (Digest:Activity). A window and a
-- filter; a summary card; what is open now; the people in it; and a click that goes where the line is.
----------------------------------------------------------------------
local ACT_ROW_H = 20
local ACT_WINDOWS = {
    { key = "new", label = L["New"] },
    { key = "7", label = L["7 days"] },
    { key = "30", label = L["30 days"] },
}
local ACT_FILTERS = {
    { key = "all", label = L["All"] },
    { key = "people", label = L["People"], cats = { members = true, leveling = true } },
    { key = "raids", label = L["Raids"], cats = { raids = true } },
    { key = "loot", label = L["Loot"], cats = { loot = true } },
    { key = "clears", label = L["Clears"], cats = { clears = true } },
}
local ACT_TRUNCATE = 110     -- a line longer than this is cut, and its full text is in the tooltip
local ACT_NAMES_TIP = 20     -- names listed in a tooltip before "and N more"
local NAMES_SHOWN_UI = 3     -- a line names this many people in full; more are counted (as Digest)

local function toneColor(tone)
    if tone == "good" then return C.ok end
    if tone == "bad" then return C.danger end
    if tone == "gold" then return C.gold end
    return C.silver
end

local function setColor(fs, c)
    fs:SetTextColor(c.r, c.g, c.b)
end

-- One pooled row: a time, a dot, the line, and a button where the line can go.
local function actRow(child)
    local r = CreateFrame("Frame", nil, child)
    r:SetHeight(ACT_ROW_H)
    r:EnableMouse(true)
    r.time = UI:CreateText(r, "", 11, C.textSoft.r, C.textSoft.g, C.textSoft.b)
    r.time:SetPoint("LEFT", r, "LEFT", 0, 0)
    r.time:SetWidth(84)
    r.time:SetJustifyH("LEFT")
    r.dot = UI:CreateText(r, "*", 12, C.silver.r, C.silver.g, C.silver.b)
    r.dot:SetPoint("LEFT", r, "LEFT", 88, 0)
    r.text = UI:CreateText(r, "", 12, C.text.r, C.text.g, C.text.b)
    r.text:SetPoint("LEFT", r, "LEFT", 102, 0)
    r.text:SetJustifyH("LEFT")
    r.text:SetWordWrap(false)
    r.btn = UI:CreateButton(r, "", 84, 18)
    UI:SetButtonVariant(r.btn, "ghost")
    r.btn:SetPoint("RIGHT", r, "RIGHT", 0, 0)
    r:SetScript("OnEnter", function(self)
        if not self.tip then return end
        GameTooltip:SetOwner(self, "ANCHOR_CURSOR")
        GameTooltip:ClearLines()
        if self.tip.title then GameTooltip:AddLine(self.tip.title, 1, 1, 1, true) end
        for _, line in ipairs(self.tip.lines) do GameTooltip:AddLine(line, 0.8, 0.8, 0.8, true) end
        GameTooltip:Show()
    end)
    r:SetScript("OnLeave", function() GameTooltip:Hide() end)
    return r
end

-- A small window to copy the summary from (Ctrl+C), for pasting into Discord.
local copyFrame
local function showCopy(text)
    if not copyFrame then
        local f = CreateFrame("Frame", "GuildOSActivityCopy", UIParent, "BackdropTemplate")
        f:SetSize(460, 300)
        f:SetPoint("CENTER")
        f:SetFrameStrata("DIALOG")
        f:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = UI:Edge(f) })
        f:SetBackdropColor(GuildOS.Colors.bg.r, GuildOS.Colors.bg.g, GuildOS.Colors.bg.b, 0.98)
        f:SetBackdropBorderColor(C.border.r, C.border.g, C.border.b, C.border.a)
        f:EnableMouse(true)
        f:SetMovable(true)
        f:RegisterForDrag("LeftButton")
        f:SetScript("OnDragStart", function(self) self:StartMoving() end)
        f:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)
        f.title = UI:CreateTitle(f, L["Copy the summary"], 14)
        f.title:SetPoint("TOPLEFT", 16, -14)
        f.hint = UI:CreateText(f, L["Press Ctrl+C to copy it, then paste it into Discord."], 11, C.silver.r, C.silver.g, C.silver.b)
        f.hint:SetPoint("TOPLEFT", 16, -36)
        local close = UI:CreateCloseButton(f)
        close:SetPoint("TOPRIGHT", -8, -8)
        close:SetScript("OnClick", function() f:Hide() end)
        local box = CreateFrame("EditBox", nil, f)
        box:SetMultiLine(true)
        box:SetAutoFocus(false)
        box:SetFontObject("GameFontHighlightSmall")
        box:SetPoint("TOPLEFT", 16, -60)
        box:SetPoint("BOTTOMRIGHT", -16, 16)
        box:SetScript("OnEscapePressed", function() f:Hide() end)
        f.box = box
        copyFrame = f
    end
    copyFrame.box:SetText(text or "")
    copyFrame:Show()
    copyFrame.box:SetFocus()
    copyFrame.box:HighlightText()
end

local function BuildActivitySub(panel)
    local hub = panel:GetParent()
    local Digest = GuildOS.Digest
    local state = { window = "7", filter = "all" }
    local lastCopy = ""
    local refresh   -- defined below; the controls call it

    local hint = UI:CreateText(panel, L["What's happened in the guild lately."], 12, C.textSoft.r, C.textSoft.g, C.textSoft.b)
    hint:SetPoint("TOPLEFT", 0, -GAP)

    -- The controls on one bar that wraps: the window, the filter, and two actions.
    local bar = CreateFrame("Frame", nil, panel)
    bar:SetPoint("TOPLEFT", hint, "BOTTOMLEFT", 0, -GAP)
    bar:SetHeight(FIELD_H)
    local controls, windowBtns, filterBtns = {}, {}, {}
    for _, w in ipairs(ACT_WINDOWS) do
        local b = UI:CreateButton(bar, w.label, 84, 24)
        b:SetScript("OnClick", function() state.window = w.key; refresh() end)
        windowBtns[w.key] = b
        controls[#controls + 1] = b
    end
    for _, f in ipairs(ACT_FILTERS) do
        local b = UI:CreateButton(bar, f.label, 84, 24)
        b:SetScript("OnClick", function() state.filter = f.key; refresh() end)
        filterBtns[f.key] = b
        controls[#controls + 1] = b
    end
    local markBtn = UI:CreateButton(bar, L["Mark all read"], 116, 24)
    markBtn:SetScript("OnClick", function()
        if Digest then Digest:MarkActivitySeen() end
        refresh()
    end)
    local copyBtn = UI:CreateButton(bar, L["Copy summary"], 116, 24)
    copyBtn:SetScript("OnClick", function() showCopy(lastCopy) end)
    controls[#controls + 1] = markBtn
    controls[#controls + 1] = copyBtn
    local function layoutBar()
        UI:FlowBar(bar, controls, { gap = 4, rowGap = 4, rowH = 24 })
    end

    local holder, child = makeScroll(panel, "GuildOSHubActivityScroll", bar)
    UI:MakeResponsive(panel, function(_, w)
        bar:SetWidth(math.max(200, w))
        layoutBar()
    end)

    -- The summary card: four numbers for the window.
    local cardTitles = { L["Joined"], L["Raids"], L["Looted"], L["Cleared"] }
    local cards = {}
    for i, t in ipairs(cardTitles) do
        cards[i] = {
            num = UI:CreateText(child, "0", 18, C.gold.r, C.gold.g, C.gold.b),
            label = UI:CreateText(child, t, 10, C.textSoft.r, C.textSoft.g, C.textSoft.b),
        }
    end

    -- Pinned lines, placed each refresh: what is open now, what is coming, the next achievement,
    -- a welcome, and the notices that live in Bulletin.
    local openText = UI:CreateText(child, "", 12, C.text.r, C.text.g, C.text.b)
    local openRide = UI:CreateButton(child, L["Ride Out"], 84, 20)
    UI:SetButtonVariant(openRide, "ghost")
    openRide:SetScript("OnClick", function() UI:OpenWindow("groups", "active") end)
    local openCta = UI:CreateButton(child, L["Call to Arms"], 110, 20)
    UI:SetButtonVariant(openCta, "ghost")
    openCta:SetScript("OnClick", function() UI:OpenWindow("guild", "cta") end)
    local upcomingText = UI:CreateText(child, "", 12, C.ok.r, C.ok.g, C.ok.b)
    local nextText = UI:CreateText(child, "", 12, C.text.r, C.text.g, C.text.b)
    local nextBar = CreateFrame("StatusBar", nil, child)
    nextBar:SetStatusBarTexture(WHITE)
    nextBar:SetStatusBarColor(C.gold.r, C.gold.g, C.gold.b, 1)
    nextBar.bg = nextBar:CreateTexture(nil, "BACKGROUND")
    nextBar.bg:SetAllPoints()
    nextBar.bg:SetTexture(WHITE)
    nextBar.bg:SetVertexColor(0.15, 0.15, 0.18, 1)
    local welcomeText = UI:CreateText(child, "", 12, C.gold.r, C.gold.g, C.gold.b)
    local welcomeBtn = UI:CreateButton(child, L["Roster"], 84, 20)
    UI:SetButtonVariant(welcomeBtn, "ghost")
    welcomeBtn:SetScript("OnClick", function() UI:OpenWindow("roster") end)
    local noticeText = UI:CreateText(child, "", 12, C.text.r, C.text.g, C.text.b)
    local noticeBtn = UI:CreateButton(child, L["Bulletin"], 84, 20)
    UI:SetButtonVariant(noticeBtn, "ghost")
    noticeBtn:SetScript("OnClick", function() UI:OpenWindow("guild", "bulletin") end)
    local emptyText = UI:CreateText(child, "", 12, C.textSoft.r, C.textSoft.g, C.textSoft.b)

    local pool, used = {}, 0
    local y = 0
    local todayStart = 0

    local function place(fs, x)
        fs:ClearAllPoints()
        fs:SetPoint("TOPLEFT", child, "TOPLEFT", x or 0, -y)
    end
    local function placeRight(btn, shown)
        btn:ClearAllPoints()
        if shown then btn:SetPoint("TOPRIGHT", child, "TOPRIGHT", 0, -y) end
        btn:SetShown(shown)
    end

    local function nextRow()
        used = used + 1
        local r = pool[used]
        if not r then
            r = actRow(child)
            pool[used] = r
        end
        r:ClearAllPoints()
        r:SetPoint("TOPLEFT", child, "TOPLEFT", 0, -y)
        r:SetPoint("TOPRIGHT", child, "TOPRIGHT", 0, -y)
        r:Show()
        r.tip = nil
        return r
    end

    local function headRow(title)
        local r = nextRow()
        r.time:Hide()
        r.dot:Hide()
        r.btn:Hide()
        r.text:ClearAllPoints()
        r.text:SetPoint("LEFT", r, "LEFT", 0, 0)
        r.text:SetPoint("RIGHT", r, "RIGHT", 0, 0)
        r.text:SetText(title)
        setColor(r.text, C.gold)
        y = y + ACT_ROW_H + 4
    end

    local function entryRow(e)
        local r = nextRow()
        r.time:Show()
        r.dot:Show()
        r.time:SetText(e.ts > 0 and date(e.ts >= todayStart and "%H:%M" or "%a %H:%M", e.ts) or "")
        r.dot:SetText("*")
        setColor(r.dot, toneColor(e.tone))
        local full = e.text
        local shortText = (#full > ACT_TRUNCATE) and (full:sub(1, ACT_TRUNCATE - 3) .. "...") or full
        r.text:SetText(shortText)
        setColor(r.text, e.tone == "gold" and C.gold or C.text)

        local tipLines = {}
        if e.names and #e.names > 0 then
            for i, nm in ipairs(e.names) do
                if i > ACT_NAMES_TIP then
                    tipLines[#tipLines + 1] = string.format(L["and %d more"], #e.names - ACT_NAMES_TIP)
                    break
                end
                tipLines[#tipLines + 1] = nm
            end
        end
        if #tipLines > 0 or #full > ACT_TRUNCATE then
            r.tip = { title = (#full > ACT_TRUNCATE) and full or nil, lines = tipLines }
        end

        local tab = e.tab
        local btnShown = tab ~= nil
        if btnShown then
            local big = e.names and #e.names > NAMES_SHOWN_UI
            r.btn.label:SetText(big and L["See all"] or L["Open"])
            r.btn:SetWidth(84)
            r.btn:SetScript("OnClick", function() UI:OpenWindow(tab[1], tab[2]) end)
        end
        r.btn:SetShown(btnShown)
        r.text:ClearAllPoints()
        r.text:SetPoint("LEFT", r, "LEFT", 102, 0)
        if btnShown then
            r.text:SetPoint("RIGHT", r.btn, "LEFT", -GAP, 0)
        else
            r.text:SetPoint("RIGHT", r, "RIGHT", 0, 0)
        end
        y = y + ACT_ROW_H
    end

    refresh = function()
        local now = GetServerTime()
        local t = date("*t", now)
        todayStart = now - (t.hour * 3600 + t.min * 60 + t.sec)
        layoutBar()
        for _, w in ipairs(ACT_WINDOWS) do
            UI:SetButtonVariant(windowBtns[w.key], state.window == w.key and "primary" or "secondary")
        end
        for _, f in ipairs(ACT_FILTERS) do
            UI:SetButtonVariant(filterBtns[f.key], state.filter == f.key and "primary" or "secondary")
        end

        if not Digest then
            emptyText:ClearAllPoints()
            emptyText:SetPoint("TOPLEFT", child, "TOPLEFT", 0, 0)
            emptyText:SetText(L["Nothing new in this window."])
            emptyText:Show()
            child:SetHeight(24)
            return
        end

        local since = Digest:ActivitySince(state.window)
        local feed = Digest:Activity(since)
        local sum = feed.summary

        -- The card
        local vals = { sum.joins, sum.raids, sum.loot, sum.clears }
        y = 0
        for i, c in ipairs(cards) do
            c.num:ClearAllPoints()
            c.num:SetPoint("TOPLEFT", child, "TOPLEFT", (i - 1) * 120, -y)
            c.num:SetText(tostring(vals[i] or 0))
            c.label:ClearAllPoints()
            c.label:SetPoint("TOPLEFT", child, "TOPLEFT", (i - 1) * 120, -(y + 22))
        end
        y = y + 44

        -- Open now: calls in the last six hours, and groups forming or looking
        local calls, forming, looking = 0, 0, 0
        for _, c in ipairs(GuildOS.CallToArms and GuildOS.CallToArms.recent or {}) do
            if (c.at or 0) > now - 6 * 3600 then calls = calls + 1 end
        end
        if GuildOS.Groups and GuildOS.LFGBoard then
            local onlineSet = GuildOS.LFGBoard:_BuildOnlineRoster()
            for _, c in pairs(GuildOS.Groups:Counts(now, onlineSet)) do
                forming = forming + (c.groups or 0)
                looking = looking + (c.seekers or 0)
            end
        end
        local openShown = calls > 0 or forming > 0 or looking > 0
        openText:SetShown(openShown)
        if openShown then
            openText:ClearAllPoints()
            openText:SetPoint("TOPLEFT", child, "TOPLEFT", 0, -y - 3)
            openText:SetText(string.format(L["Open now: %d call(s) in 6h, %d group(s) forming, %d looking"], calls, forming, looking))
        end
        placeRight(openRide, openShown)
        openCta:SetShown(openShown and calls > 0)
        if openShown and calls > 0 then
            openCta:ClearAllPoints()
            openCta:SetPoint("TOPRIGHT", openRide, "TOPLEFT", -GAP, 0)
        end
        if openShown then y = y + 26 end

        upcomingText:SetShown(sum.upcoming ~= nil)
        if sum.upcoming then
            place(upcomingText)
            upcomingText:SetText(sum.upcoming)
            y = y + 22
        end

        nextText:SetShown(sum.next ~= nil)
        nextBar:SetShown(sum.next ~= nil)
        if sum.next then
            place(nextText)
            nextText:SetText(string.format(L["Next: %s (%d/%d)"], sum.next.title, sum.next.current, sum.next.target))
            nextBar:ClearAllPoints()
            nextBar:SetPoint("TOPLEFT", child, "TOPLEFT", 0, -(y + 18))
            nextBar:SetPoint("TOPRIGHT", child, "TOPRIGHT", 0, -(y + 18))
            nextBar:SetHeight(8)
            nextBar:SetMinMaxValues(0, sum.next.target)
            nextBar:SetValue(math.min(sum.next.current, sum.next.target))
            y = y + 36
        end

        local welcome = sum.welcome or {}
        welcomeText:SetShown(#welcome > 0)
        placeRight(welcomeBtn, #welcome > 0)
        if #welcome > 0 then
            local names = {}
            for i, nm in ipairs(welcome) do
                if i > NAMES_SHOWN_UI then break end
                names[#names + 1] = nm
            end
            local more = #welcome - #names
            local who = table.concat(names, ", ") .. (more > 0 and string.format(L[" +%d"], more) or "")
            place(welcomeText)
            welcomeText:SetText(string.format(L["Welcome: %s"], who))
            welcomeBtn:SetPoint("TOPRIGHT", child, "TOPRIGHT", 0, -y)
            y = y + 24
        end

        noticeText:SetShown(sum.notices > 0)
        noticeBtn:SetShown(sum.notices > 0)
        if sum.notices > 0 then
            place(noticeText)
            noticeText:SetText(string.format(L["%d new notice(s) in Bulletin"], sum.notices))
            noticeBtn:ClearAllPoints()
            noticeBtn:SetPoint("TOPRIGHT", child, "TOPRIGHT", 0, -y)
            y = y + 24
        end
        if y > 0 then y = y + GAP end

        -- The timeline
        used = 0
        local filter
        for _, f in ipairs(ACT_FILTERS) do if f.key == state.filter then filter = f end end
        local function keep(e)
            return not filter or not filter.cats or filter.cats[e.cat] == true
        end
        local winLabel = ""
        for _, w in ipairs(ACT_WINDOWS) do
            if w.key == state.window then winLabel = w.label end
        end
        local lines = { string.format(L["OutlawOS, %s"], winLabel) }

        local youShown = false
        for _, e in ipairs(feed.entries) do
            if e.cat == "you" and (state.filter == "all" or state.filter == "people") then
                if not youShown then headRow(L["You"]); youShown = true end
                entryRow(e)
            end
        end

        local bucketNow
        for _, e in ipairs(feed.entries) do
            if e.cat ~= "you" and keep(e) then
                local bucket = e.ts == 0 and "none" or (e.ts >= todayStart and "today" or "earlier")
                if bucket ~= bucketNow then
                    bucketNow = bucket
                    headRow(bucket == "today" and L["Today"] or (bucket == "earlier" and L["Earlier"] or L["No time recorded"]))
                end
                entryRow(e)
                local stamp = e.ts > 0 and (date("%a %H:%M", e.ts) .. "  ") or ""
                lines[#lines + 1] = stamp .. e.text
            end
        end
        for i = 1, #pool do
            if i > used then pool[i]:Hide() end
        end

        emptyText:SetShown(used == 0)
        if used == 0 then
            emptyText:ClearAllPoints()
            emptyText:SetPoint("TOPLEFT", child, "TOPLEFT", 0, -y)
            emptyText:SetText(L["Nothing new in this window."])
        end

        lastCopy = table.concat(lines, "\n")
        child:SetHeight(math.max(1, y + (used == 0 and 24 or 0)))

        -- The unread count on the sub-tab's label
        if hub and hub.setBadge then hub.setBadge("activity", Digest:UnreadCount()) end
    end

    return refresh
end

----------------------------------------------------------------------
-- BULLETIN sub-panel
----------------------------------------------------------------------
-- The expiry a post gets, by index: for ever, a week, a month (#10).
local BULLETIN_DAYS = { false, 7, 30 }
local BULLETIN_MAX_CHARS = 200   -- the field's cap

GuildOS.Dialogs["GUILDOS_BULLETIN_DELETE"] = {
    text = "%s", button1 = L["Delete"], button2 = L["Cancel"],
    OnAccept = function(self)
        local d = self and self.data
        if d and d.run then d.run() end
    end,
    timeout = 0, whileDead = true, hideOnEscape = true,
}
GuildOS.Dialogs["GUILDOS_BULLETIN_CHAT"] = {
    text = "%s", button1 = L["Send"], button2 = L["Cancel"],
    OnAccept = function(self)
        local d = self and self.data
        if d and d.run then d.run() end
    end,
    timeout = 0, whileDead = true, hideOnEscape = true,
}

-- A hover tooltip. HookScript, so the button's own hover tint (SetScript in UI:CreateButton) keeps working.
local function tipOn(frame, text)
    frame:HookScript("OnEnter", function(self)
        if not GameTooltip then return end
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine(text, GuildOS.Tip.text.r, GuildOS.Tip.text.g, GuildOS.Tip.text.b, true)
        GameTooltip:Show()
    end)
    frame:HookScript("OnLeave", function()
        if GameTooltip then GameTooltip:Hide() end
    end)
end

local function rgbHex(c)
    return string.format("|cff%02x%02x%02x", math.floor(c.r * 255 + 0.5), math.floor(c.g * 255 + 0.5), math.floor(c.b * 255 + 0.5))
end

-- The author's name in their class colour, when the roster knows their class (#2).
local function authorText(author)
    if type(author) ~= "string" or author == "" then return author or "?" end
    local m = GuildOS.db and GuildOS.db.members and GuildOS.db.members[GuildOS:LocalMemberKey(author)]
    local cls = type(m) == "table" and m.class
    if not cls then return author end
    local r, g, b = GuildOS:GetClassColor(cls)
    return rgbHex({ r = r, g = g, b = b }) .. author .. "|r"
end

local function expiryText(i)
    local d = BULLETIN_DAYS[i]
    return d and string.format(L["Lasts: %d days"], d) or L["Lasts: forever"]
end

local function BuildBulletinSub(panel)
    local isOfficer = GuildOS:IsOfficer()
    local MAX = (GuildOS.Bulletin and GuildOS.Bulletin.MAX) or 20
    local editingId        -- the notice being edited, while the field holds its text (#9)
    local expiry = 1       -- an index into BULLETIN_DAYS: what the next post gets (#10)
    local search = ""      -- the search text, lower-cased (#11)
    local refresh, updateEditing

    -- Offsets from the panel's top: the field row, the search and controls row, the status line, the list.
    local R1 = GAP
    local R2 = isOfficer and (GAP + FIELD_H + GAP) or GAP
    local R3 = R2 + FIELD_H + GAP
    local listTop = R3 + 16 + GAP

    local box, postBtn, cancelBtn, counterFS, expiryBtn
    if isOfficer then
        -- One field, so one label beside it, then its button (#371). It shows a hint while empty (#3).
        local label = UI:CreateText(panel, L["Notice:"], 12)
        postBtn = UI:CreateButton(panel, L["Post"], 84, FIELD_H)
        box = UI:CreateInput(panel, 0, FIELD_H, { max = BULLETIN_MAX_CHARS, placeholder = L["Write a notice..."] })
        box:SetPoint("TOPLEFT", math.ceil(label:GetStringWidth() or 0) + GAP, -R1)
        box:SetPoint("TOPRIGHT", -(GAP + UI.ReserveFor(postBtn, GAP)), -R1)
        label:SetPoint("RIGHT", box, "LEFT", -GAP, 0)
        postBtn:SetPoint("LEFT", box, "RIGHT", GAP, 0)
    end

    -- The search box, on both rows of controls (#11).
    local searchBox = UI:CreateInput(panel, 200, FIELD_H, { placeholder = L["Search notices..."] })
    searchBox:SetPoint("TOPLEFT", 0, -R2)

    if isOfficer then
        expiryBtn = UI:CreateButton(panel, expiryText(expiry), 124, FIELD_H)
        expiryBtn:SetPoint("LEFT", searchBox, "RIGHT", GAP, 0)
        tipOn(expiryBtn, L["How long the next notice stays up."])
        expiryBtn:SetScript("OnClick", function()
            expiry = expiry % #BULLETIN_DAYS + 1
            expiryBtn.label:SetText(expiryText(expiry))
        end)

        cancelBtn = UI:CreateButton(panel, L["Cancel"], 84, FIELD_H)
        cancelBtn:SetPoint("TOPRIGHT", panel, "TOPRIGHT", 0, -R2)
        cancelBtn:Hide()
        counterFS = UI:CreateText(panel, "", 11, C.textSoft.r, C.textSoft.g, C.textSoft.b)
        counterFS:SetText(string.format(L["%d / %d"], 0, BULLETIN_MAX_CHARS))
        box:HookScript("OnTextChanged", function(self)
            local t = self:GetText() or ""
            local n = (strlenutf8 and strlenutf8(t)) or #t
            counterFS:SetText(string.format(L["%d / %d"], n, BULLETIN_MAX_CHARS))
        end)
    end

    -- The counter sits at the right, or beside Cancel while a notice is being edited (#4, #9).
    local function placeCounter()
        if not counterFS then return end
        counterFS:ClearAllPoints()
        if editingId then
            counterFS:SetPoint("RIGHT", cancelBtn, "LEFT", -GAP, 0)
        else
            counterFS:SetPoint("TOPRIGHT", panel, "TOPRIGHT", 0, -(R2 + math.floor((FIELD_H - 12) / 2)))
        end
    end

    -- While editing, the button says Save and Cancel shows; otherwise it says Post.
    updateEditing = function()
        if postBtn then postBtn.label:SetText(editingId and L["Save"] or L["Post"]) end
        if cancelBtn then cancelBtn:SetShown(editingId ~= nil) end
        placeCounter()
    end

    local statusFS = UI:CreateText(panel, "", 11, C.textSoft.r, C.textSoft.g, C.textSoft.b)
    statusFS:SetPoint("TOPLEFT", 0, -R3)
    local syncFS = UI:CreateText(panel, "", 11, C.textSoft.r, C.textSoft.g, C.textSoft.b)
    syncFS:SetPoint("TOPRIGHT", 0, -R3)

    local _, child = makeScroll(panel, "GuildOSHubBulletinScroll", listTop)

    if isOfficer then
        local function doPost()
            local text = strtrim(box:GetText() or "")
            if text == "" then
                GuildOS:Print(L["Type a notice first."])
                box:SetFocus()
                return
            end
            if GuildOS.Bulletin then
                if editingId then
                    GuildOS.Bulletin:Edit(editingId, text)
                else
                    GuildOS.Bulletin:Post(text, BULLETIN_DAYS[expiry])
                end
            end
            editingId = nil
            box:SetText("")
            box:SetFocus()   -- it stays in the field for the next notice (#18)
            updateEditing()
        end
        box:SetScript("OnEnterPressed", doPost)
        postBtn:SetScript("OnClick", doPost)
        tipOn(postBtn, L["Post this notice."])
        cancelBtn:SetScript("OnClick", function()
            editingId = nil
            box:SetText("")
            box:ClearFocus()
            updateEditing()
        end)
        tipOn(cancelBtn, L["Stop editing and clear the field."])
    end

    searchBox:HookScript("OnTextChanged", function(self, userInput)
        if not userInput then return end
        search = strtrim(self:GetText() or ""):lower()
        GuildOS:SafeCall(refresh)
    end)

    refresh = function()
        clear(child)
        local bulletin = GuildOS.Bulletin
        local stored = (bulletin and bulletin:GetMessages()) or {}
        local all = (bulletin and bulletin:Shown()) or {}

        -- The search keeps the notices whose text or author has its text (#11).
        local shown = {}
        for _, m in ipairs(all) do
            local text = (m.text or ""):lower()
            local who = (m.author or ""):lower()
            if search == "" or text:find(search, 1, true) or who:find(search, 1, true) then
                shown[#shown + 1] = m
            end
        end

        -- The status line: how many the board holds, against its cap (#12), or who may post (#14); and when it
        -- last changed here (#15).
        if isOfficer then
            local n = #stored
            statusFS:SetText(string.format(L["%d of %d notices"], n, MAX))
            local near = n >= MAX - 4
            local col = near and C.warn or C.textSoft
            statusFS:SetTextColor(col.r, col.g, col.b)
        else
            statusFS:SetText(L["Officers post notices here."])
        end
        local at = GuildOS.db and GuildOS.db.bulletin and GuildOS.db.bulletin.syncedAt
        syncFS:SetText(at and string.format(L["Updated %s"], GuildOS:DateText(at, " %H:%M")) or "")

        -- The newest notice that is not pinned: its "Latest" tag (#7).
        local newest
        for _, m in ipairs(all) do
            if not m.pinned and (not newest or (m.ts or 0) > (newest.ts or 0)) then newest = m end
        end

        local y = 0
        for _, m in ipairs(shown) do
            local id, text = m.id, m.text or ""
            local textFS = UI:CreateText(child, text, 12, C.text.r, C.text.g, C.text.b)
            textFS:SetPoint("TOPLEFT", 0, -y)
            textFS:SetPoint("TOPRIGHT", 0, -y)
            textFS:SetJustifyH("LEFT")
            local th = textFS:GetStringHeight() or 14

            -- A rule between one notice and the next (#1).
            if y > 0 then
                local rule = child:CreateTexture(nil, "ARTWORK")
                rule:SetColorTexture(C.line.r, C.line.g, C.line.b, 1)
                rule:SetHeight(1)
                rule:SetPoint("TOPLEFT", 0, -(y - 7))
                rule:SetPoint("TOPRIGHT", 0, -(y - 7))
            end

            -- The meta line: author (#2), how long ago (#6), edited, its expiry (#10), and the Pinned or Latest tag (#7, #8).
            local metaY = y + th + 2
            local bits = { authorText(m.author), GuildOS:TimeAgo(m.ts or 0) }
            if m.edited then bits[#bits + 1] = L["edited"] end
            if m.expires then bits[#bits + 1] = string.format(L["until %s"], GuildOS:DateText(m.expires, "")) end
            if m.pinned then
                bits[#bits + 1] = rgbHex(C.gold) .. L["Pinned"] .. "|r"
            elseif newest and newest.id == id then
                bits[#bits + 1] = rgbHex(C.gold) .. L["Latest"] .. "|r"
            end
            local meta = UI:CreateText(child, table.concat(bits, " · "), 11, C.textSoft.r, C.textSoft.g, C.textSoft.b)
            meta:SetPoint("TOPLEFT", 0, -metaY)

            -- The full time on hover over the meta line (#6).
            local hit = CreateFrame("Frame", nil, child)
            hit:SetPoint("TOPLEFT", meta, "TOPLEFT", 0, 0)
            hit:SetSize(math.max(20, meta:GetStringWidth() or 20), 14)
            hit:EnableMouse(true)
            tipOn(hit, string.format(L["Posted %s"], GuildOS:DateText(m.ts or 0, " %H:%M")))

            if isOfficer then
                local del = UI:CreateButton(child, "\195\151", 24, 18)   -- the multiplication sign
                del:SetPoint("TOPRIGHT", child, "TOPRIGHT", 0, -(metaY - 2))
                tipOn(del, L["Delete this notice."])
                del:SetScript("OnClick", function()
                    GuildOS:ShowDialog("GUILDOS_BULLETIN_DELETE", L["Delete this notice? Everyone in the guild loses it."], nil, {
                        run = function() if GuildOS.Bulletin then GuildOS.Bulletin:Remove(id) end end,
                    })
                end)

                local chat = UI:CreateButton(child, L["Chat"], 52, 18)
                chat:SetPoint("RIGHT", del, "LEFT", -4, 0)
                tipOn(chat, L["Send this notice to guild chat."])
                chat:SetScript("OnClick", function()
                    GuildOS:ShowDialog("GUILDOS_BULLETIN_CHAT", L["Send this notice to guild chat?"], nil, {
                        run = function() GuildOS.Compat.SendChatMessage(text, "GUILD") end,
                    })
                end)

                local edit = UI:CreateButton(child, L["Edit"], 48, 18)
                edit:SetPoint("RIGHT", chat, "LEFT", -4, 0)
                tipOn(edit, L["Edit this notice."])
                edit:SetScript("OnClick", function()
                    editingId = id
                    box:SetText(text)
                    box:SetFocus()
                    updateEditing()
                end)

                local pin = UI:CreateButton(child, m.pinned and L["Unpin"] or L["Pin"], 52, 18)
                pin:SetPoint("RIGHT", edit, "LEFT", -4, 0)
                tipOn(pin, m.pinned and L["Unpin this notice."] or L["Pin this notice to the top."])
                pin:SetScript("OnClick", function() if GuildOS.Bulletin then GuildOS.Bulletin:Pin(id) end end)
            end

            y = y + th + 2 + (isOfficer and 18 or 14) + 14
        end

        if #all == 0 then
            local empty = UI:CreateText(child,
                isOfficer and L["No notices yet. Write the first one above."] or L["Officers will post news here."],
                12, C.textSoft.r, C.textSoft.g, C.textSoft.b)
            empty:SetPoint("TOPLEFT", 0, 0)
        elseif #shown == 0 then
            local none = UI:CreateText(child, L["No notices match that search."], 12, C.textSoft.r, C.textSoft.g, C.textSoft.b)
            none:SetPoint("TOPLEFT", 0, 0)
        end
        child:SetHeight(math.max(1, y))
    end

    updateEditing()
    if GuildOS.Bulletin then GuildOS.Bulletin.uiRefresh = refresh end
    return refresh
end

----------------------------------------------------------------------
-- CALL TO ARMS sub-panel (issue #108): officers send, everyone sees the
-- recent calls, answers them and sets how they want to be told.
----------------------------------------------------------------------

local function shortName(n)
    return (Ambiguate and Ambiguate(n or "", "short")) or (n or "")
end

local function BuildCallToArmsSub(panel)
    local CTA = GuildOS.CallToArms
    local officer = GuildOS:IsOfficer()
    local selected = CTA:Default()     -- the template the chips and Send use
    local selectedMeet                 -- id of the meeting point picked, or nil
    local rows = {}                    -- { frame, kids, rowH, manual }: wrapped again on every resize
    local chips = {}                   -- template id -> its chip button
    local lines = {}                   -- the pooled recent-call lines
    local builtinRow, ownRow, meetRow, zoneRow, msgRow, meetInputRow, actionRow, alertRow, chatRow
    local msgBox, zoneBox, whenBox, nameBox, meetBox
    local renameBtn, dupBtn, deleteBtn, defaultBtn
    local paintSelected, paintMeets, applyTemplate, buildChips

    local function reflow()
        -- As wide as the content: flush left, GAP short of the right edge (#371).
        local w = (panel:GetWidth() or 0) - GAP
        if w < 200 then w = 600 end   -- not laid out yet: OnSizeChanged wraps it again
        for _, r in ipairs(rows) do
            r.frame:SetWidth(w)
            if not r.manual then UI:FlowBar(r.frame, r.kids, { gap = 4, rowGap = 4, rowH = r.rowH }) end
        end
    end
    panel:SetScript("OnSizeChanged", reflow)

    -- A row under `anchor` (or at the top): its children are flowed into it by reflow.
    local function newRow(anchor, gapY, rowH, manual)
        local f = CreateFrame("Frame", nil, panel)
        if anchor then f:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -(gapY or GAP))
        else f:SetPoint("TOPLEFT", 0, -GAP) end
        local r = { frame = f, kids = {}, rowH = rowH or 22, manual = manual }
        rows[#rows + 1] = r
        return r
    end
    local function label(anchor, text)
        local fs = UI:CreateText(panel, text, 11, C.textSoft.r, C.textSoft.g, C.textSoft.b)
        fs:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -GAP)
        return fs
    end
    local function clearRow(r)
        for _, k in ipairs(r.kids) do k:Hide() end
        r.kids = {}
    end
    local function chip(r, text, width, onClick)
        local b = UI:CreateButton(r.frame, text, width, 22)
        b:SetScript("OnClick", onClick)
        r.kids[#r.kids + 1] = b
        return b
    end
    local function setEnabled(b, on)
        if on then b:Enable() else b:Disable() end
    end
    local function checkbox(r, text, get, set)
        local cb = UI:CreateCheckbox(r.frame, text, 16)
        cb:SetWidth(30 + (cb.label:GetStringWidth() or 100))
        cb.checkbox:SetChecked(get())
        cb.checkbox.onChanged = function(_, checked) set(checked and true or false) end
        r.kids[#r.kids + 1] = cb
        return cb
    end
    local function setting(key) return function(v) GuildOS:SetSetting(key, v) end end

    -- Opens the Groups board: it lives here, not in the recent calls, so it is not taken for a filter.
    local boardRow = newRow(nil, nil, 22)
    if GuildOS.LFGBoard then
        chip(boardRow, L["Open Groups board"], 180, function() GuildOS.LFGBoard:Show() end)
    end
    local above = boardRow.frame

    if officer then
        local head = UI:CreateSectionTitle(panel, L["Send a call"], false)
        head:SetPoint("TOPLEFT", above, "BOTTOMLEFT", 0, -SECTION_SPACE)

        local bl = label(head, L["Ready-made"])
        builtinRow = newRow(bl, GAP, 22)
        local ol = label(builtinRow.frame, L["Your templates"])
        ownRow = newRow(ol, GAP, 22)

        -- The message: left empty, the call carries the template's own message (#371).
        local sendBtn = UI:CreateButton(panel, L["Send"], 88, FIELD_H)
        msgRow = newRow(ownRow.frame, GAP, FIELD_H, true)
        msgRow.frame:SetHeight(FIELD_H)
        msgBox = UI:CreateInput(msgRow.frame, 0, FIELD_H, { placeholder = L["Message (optional)"] })
        msgBox:SetPoint("TOPLEFT", msgRow.frame, "TOPLEFT", 0, 0)
        msgBox:SetPoint("TOPRIGHT", msgRow.frame, "TOPRIGHT", -UI.ReserveFor(sendBtn, GAP), 0)
        msgBox:SetMaxBytes(CTA.TEXT_MAX + 1)   -- the call is cut at bytes, not letters: Cyrillic is two each
        sendBtn:SetPoint("TOPRIGHT", msgRow.frame, "TOPRIGHT", 0, 0)

        -- Where and when: the zone defaults to where I am, the time to now.
        zoneRow = newRow(msgRow.frame, GAP, FIELD_H)
        zoneBox = UI:CreateInput(zoneRow.frame, 170, FIELD_H, { max = 60, placeholder = L["Zone (blank = here)"] })
        zoneRow.kids[#zoneRow.kids + 1] = zoneBox
        whenBox = UI:CreateInput(zoneRow.frame, 170, FIELD_H, { max = 12, placeholder = L["When: now, +10 or 20:30"] })
        zoneRow.kids[#zoneRow.kids + 1] = whenBox
        local hereBtn = chip(zoneRow, L["Use my zone"], 110, function()
            zoneBox:SetText((CTA:Where()))
        end)
        hereBtn:SetHeight(FIELD_H)

        -- Meeting point: pick one of the saved ones, or none.
        local ml = label(zoneRow.frame, L["Meet at"])
        meetRow = newRow(ml, GAP, 22)
        meetInputRow = newRow(meetRow.frame, GAP, FIELD_H)
        meetBox = UI:CreateInput(meetInputRow.frame, 170, FIELD_H, { max = CTA.MEET_MAX, placeholder = L["New meeting point"] })
        meetInputRow.kids[#meetInputRow.kids + 1] = meetBox
        local saveMeet = chip(meetInputRow, L["Save point"], 110, function()
            local ok, why = CTA:AddMeet(meetBox:GetText())
            if not ok then GuildOS:Print(why) return end
            meetBox:SetText("")
            paintMeets()
        end)
        saveMeet:SetHeight(FIELD_H)
        local removeMeet = chip(meetInputRow, L["Remove point"], 120, function()
            if not selectedMeet then return end
            CTA:RemoveMeet(selectedMeet)
            selectedMeet = nil
            paintMeets()
        end)
        removeMeet:SetHeight(FIELD_H)

        -- Templates: save this message as one, and act on the one picked.
        actionRow = newRow(meetInputRow.frame, GAP, FIELD_H)
        nameBox = UI:CreateInput(actionRow.frame, 160, FIELD_H, { placeholder = L["Title"] })
        nameBox:SetMaxBytes(CTA.NAME_MAX + 1)
        actionRow.kids[#actionRow.kids + 1] = nameBox
        chip(actionRow, L["Save as template"], 130, function()
            local meetName = ""
            if selectedMeet then
                for _, m in ipairs(CTA:Meets()) do if m.id == selectedMeet then meetName = m.name end end
            end
            local tpl = CTA:Template(selected)
            local ok, why = CTA:SaveTemplate(nameBox:GetText(), msgBox:GetText(), tpl and tpl.kind, meetName, whenBox:GetText())
            if not ok then GuildOS:Print(why) return end
            nameBox:SetText("")
            buildChips()
        end)
        renameBtn = chip(actionRow, L["Rename"], 80, function()
            local ok, why = CTA:RenameTemplate(selected, nameBox:GetText())
            if not ok then GuildOS:Print(why) return end
            nameBox:SetText("")
            buildChips()
        end)
        dupBtn = chip(actionRow, L["Duplicate"], 90, function()
            local ok, newId = CTA:DuplicateTemplate(selected)
            if not ok then return end
            selected = newId
            buildChips()
            applyTemplate(newId)
        end)
        defaultBtn = chip(actionRow, L["Make default"], 110, function()
            CTA:SetDefault(selected)
            buildChips()
        end)
        deleteBtn = chip(actionRow, L["Delete"], 80, function()
            CTA:DeleteTemplate(selected)
            selected = CTA:Default()
            buildChips()
            applyTemplate(selected)
        end)

        -- Send: the message box and the button share the row's width.
        local send = function()
            local meetName = ""
            if selectedMeet then
                for _, m in ipairs(CTA:Meets()) do if m.id == selectedMeet then meetName = m.name end end
            end
            local ok = CTA:Send(selected, msgBox:GetText(), { zone = zoneBox:GetText(), when = whenBox:GetText(), meet = meetName })
            if ok then msgBox:ClearFocus() end
        end
        sendBtn:SetScript("OnClick", send)
        msgBox:SetScript("OnEnterPressed", send)   -- a key press is a hardware event, as a click is

        -- Chips and the meeting points.
        buildChips = function()
            for k in pairs(chips) do chips[k] = nil end
            clearRow(builtinRow)
            clearRow(ownRow)
            for _, t in ipairs(CTA:Templates()) do
                local r = t.builtin and builtinRow or ownRow
                local text = t.name
                if t.id == CTA:Default() then text = string.format(L["%s (default)"], t.name) end
                local id = t.id
                chips[id] = chip(r, text, 150, function() applyTemplate(id) end)
            end
            paintSelected()
        end
        paintSelected = function()
            for id, b in pairs(chips) do UI:SetSelected(b, id == selected) end
            local t = CTA:Template(selected)
            local own = t and not t.builtin
            setEnabled(renameBtn, own)
            setEnabled(deleteBtn, own)
            reflow()
        end
        paintMeets = function()
            clearRow(meetRow)
            local none = chip(meetRow, L["No meeting point"], 140, function()
                selectedMeet = nil
                paintMeets()
            end)
            UI:SetSelected(none, selectedMeet == nil)
            for _, m in ipairs(CTA:Meets()) do
                local id = m.id
                local b = chip(meetRow, m.name, 140, function()
                    selectedMeet = id
                    paintMeets()
                end)
                UI:SetSelected(b, selectedMeet == id)
            end
            reflow()
        end
        applyTemplate = function(id)
            local t = CTA:Template(id)
            if not t then return end
            selected = id
            msgBox:SetText(t.text or "")
            whenBox:SetText(t.when or "")
            selectedMeet = nil
            if t.meet then
                for _, m in ipairs(CTA:Meets()) do if m.name == t.meet then selectedMeet = m.id end end
            end
            paintMeets()
            paintSelected()
        end
        zoneBox:SetText((CTA:Where()))
        buildChips()
        paintMeets()
        applyTemplate(selected)
        above = actionRow.frame
    end

    -- Everyone: how a call reaches me. Popups, then the types to hear, then the chat line.
    local mine = UI:CreateSectionTitle(panel, L["My alerts"], not officer)
    if officer then mine:SetPoint("TOPLEFT", above, "BOTTOMLEFT", 0, -SECTION_SPACE)
    else mine:SetPoint("TOPLEFT", above, "BOTTOMLEFT", 0, -GAP) end
    local pl = label(mine, L["Popups"])
    local popRow = newRow(pl, GAP, 18)
    checkbox(popRow, L["Show popups"], function() return CTA:PopupsOn() end, setting("ctaPopups"))
    checkbox(popRow, L["Play a sound"], function() return CTA:SoundOn() end, setting("ctaSound"))
    checkbox(popRow, L["Quiet in instances and combat"], function() return CTA:QuietOn() end, setting("ctaQuiet"))

    local tl = label(popRow.frame, L["Call types"])
    local typeRow = newRow(tl, GAP, 22)
    checkbox(typeRow, L["Mute all"], function() return CTA:MuteAll() end, setting("ctaMuteAll"))
    for _, k in ipairs(CTA.KINDS) do
        local id, sound = k.id, k.sound
        checkbox(typeRow, k.title, function() return not CTA:Muted(id) end,
            function(v) GuildOS:SetSetting("ctaMute_" .. id, not v) end)
        local hear = chip(typeRow, L["Hear"], 56, function()
            if PlaySound then pcall(PlaySound, sound, "Master") end
        end)
        hear:SetHeight(18)
    end
    above = typeRow.frame

    if officer then
        local cl = label(typeRow.frame, L["Chat"])
        chatRow = newRow(cl, GAP, 18)
        checkbox(chatRow, L["Also post in guild chat"], function() return CTA:ChatOn() end, setting("ctaChat"))
        above = chatRow.frame
    end

    -- The recent calls: the newest first, with the answers and, for an officer, Close.
    local recentHead = UI:CreateSectionTitle(panel, L["Recent calls"])
    recentHead:SetPoint("TOPLEFT", above, "BOTTOMLEFT", 0, -SECTION_SPACE)
    local _, child = makeScroll(panel, "GuildOSHubCTAScroll", recentHead)
    reflow()

    local empty = UI:CreateText(child, L["No calls yet."], 12, C.textSoft.r, C.textSoft.g, C.textSoft.b)
    empty:SetPoint("TOPLEFT", 0, 0)
    local function lineAt(i)
        local ln = lines[i]
        if ln then return ln end
        ln = {}
        ln.text = UI:CreateText(child, "", 12, C.text.r, C.text.g, C.text.b)
        ln.meta = UI:CreateText(child, "", 11, C.textSoft.r, C.textSoft.g, C.textSoft.b)
        ln.go = UI:CreateButton(child, L["On my way"], 92, 20)
        ln.go:SetScript("OnClick", function() CTA:Answer(ln.id, "going") end)
        ln.maybe = UI:CreateButton(child, L["Maybe"], 62, 20)
        ln.maybe:SetScript("OnClick", function() CTA:Answer(ln.id, "maybe") end)
        ln.cant = UI:CreateButton(child, L["Can't"], 62, 20)
        ln.cant:SetScript("OnClick", function() CTA:Answer(ln.id, "cant") end)
        ln.close = UI:CreateButton(child, L["Close"], 56, 20)
        ln.close:SetScript("OnClick", function() CTA:Close(ln.id) end)
        lines[i] = ln
        return ln
    end

    local function refresh()
        reflow()
        local now, y = GetServerTime(), 0
        local amOfficer = GuildOS:IsOfficer()
        for i, e in ipairs(CTA.recent) do
            local ln = lineAt(i)
            ln.id = e.id
            local open = not e.mine and not e.closed and now - (tonumber(e.ts) or 0) <= CTA.MAX_AGE
            local vis = {}
            if open then vis[#vis + 1] = ln.go; vis[#vis + 1] = ln.maybe; vis[#vis + 1] = ln.cant end
            if amOfficer and not e.closed then vis[#vis + 1] = ln.close end
            for _, b in ipairs({ ln.go, ln.maybe, ln.cant, ln.close }) do b:Hide() end
            -- Placed from the right; the leftmost one is vis[1], and the text stops short of it.
            local x = 0
            for j = #vis, 1, -1 do
                local b = vis[j]
                b:ClearAllPoints()
                b:SetPoint("TOPRIGHT", child, "TOPRIGHT", -x, -y)
                b:Show()
                x = x + b:GetWidth() + 4
            end
            ln.text:SetText(string.format("%s  %s", e.title or "", e.text or ""))
            ln.text:ClearAllPoints()
            ln.text:SetPoint("TOPLEFT", 0, -y)
            if vis[1] then ln.text:SetPoint("TOPRIGHT", vis[1], "TOPLEFT", -GAP, 0)
            else ln.text:SetPoint("TOPRIGHT", 0, -y) end
            ln.text:Show()
            local th = ln.text:GetStringHeight() or 14
            local tail = CTA:CountText(e)
            if tail == "" then tail = date("%H:%M", e.at or 0) end
            local meta = string.format("%s · %s · %s", e.zone or "", shortName(e.sender), tail)
            if e.meet then meta = meta .. " · " .. string.format(L["Meet at %s"], e.meet) end
            local status = CTA:WhenLine(e)
            if status then meta = meta .. " · " .. status end
            if e.closed then meta = meta .. " · " .. L["Closed"] end
            ln.meta:SetText(meta)
            ln.meta:ClearAllPoints()
            ln.meta:SetPoint("TOPLEFT", 0, -(y + math.max(th, 20) + 2))
            ln.meta:Show()
            y = y + math.max(th, 20) + 26
        end
        for i = #CTA.recent + 1, #lines do
            local ln = lines[i]
            ln.text:Hide(); ln.meta:Hide()
            for _, b in ipairs({ ln.go, ln.maybe, ln.cant, ln.close }) do b:Hide() end
        end
        empty:SetShown(#CTA.recent == 0)
        child:SetHeight(math.max(1, y))
    end
    -- Answers arrive by the dozen while the tab is closed; it catches up when it opens.
    CTA.uiRefresh = function() if panel:IsVisible() then refresh() end end
    return refresh
end

----------------------------------------------------------------------
-- POLLS sub-panel
----------------------------------------------------------------------
GuildOS.Dialogs["GUILDOS_POLL_CLOSE"] = {
    text = "%s", button1 = L["Close"], button2 = L["Cancel"],
    OnAccept = function(self)
        local d = self and self.data
        if d and d.run then d.run() end
    end,
    timeout = 0, whileDead = true, hideOnEscape = true,
}
GuildOS.Dialogs["GUILDOS_POLL_DELETE"] = {
    text = "%s", button1 = L["Delete"], button2 = L["Cancel"],
    OnAccept = function(self)
        local d = self and self.data
        if d and d.run then d.run() end
    end,
    timeout = 0, whileDead = true, hideOnEscape = true,
}
GuildOS.Dialogs["GUILDOS_POLL_CHAT"] = {
    text = "%s", button1 = L["Send"], button2 = L["Cancel"],
    OnAccept = function(self)
        local d = self and self.data
        if d and d.run then d.run() end
    end,
    timeout = 0, whileDead = true, hideOnEscape = true,
}
GuildOS.Dialogs["GUILDOS_POLL_NOTICE"] = {
    text = "%s", button1 = L["Post"], button2 = L["Cancel"],
    OnAccept = function(self)
        local d = self and self.data
        if d and d.run then d.run() end
    end,
    timeout = 0, whileDead = true, hideOnEscape = true,
}

local function BuildPollsSub(panel)
    local isOfficer = GuildOS:IsOfficer()
    local POLL_DAYS = { false, 3, 7, 14 }     -- the close-after choices on the form (#10)
    local POLL_MAX_OPTIONS = 6
    local POLL_MAX_QUESTION = 150
    local POLL_FILTERS = { { "open", "Open" }, { "closed", "Closed" }, { "all", "All" } }
    local filter = "open"                      -- which polls the list shows (#14)
    local dayIdx = 1                           -- into POLL_DAYS, the form's close-after choice
    local formMsg                              -- the form's own message line (#18)
    local formLast                             -- the form's last line; the filters hang under it
    local refresh                              -- set below; the filters and the buttons repaint through it

    local soft = C.textSoft
    local function setFormMsg(text, col)
        if not formMsg then return end
        formMsg:SetText(text or "")
        local c = col or soft
        formMsg:SetTextColor(c.r, c.g, c.b)
    end

    -- A tooltip with a title and plain lines under it: who picked an option, or a note (#8).
    local function listTip(frame, title, lines)
        frame:HookScript("OnEnter", function(self)
            if not GameTooltip then return end
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:AddLine(title, GuildOS.Tip.text.r, GuildOS.Tip.text.g, GuildOS.Tip.text.b, true)
            for _, line in ipairs(lines) do
                GameTooltip:AddLine(line, soft.r, soft.g, soft.b, true)
            end
            GameTooltip:Show()
        end)
        frame:HookScript("OnLeave", function()
            if GameTooltip then GameTooltip:Hide() end
        end)
    end

    -- The poll as one line for guild chat or the bulletin board (#13).
    local function pollLine(p)
        return string.format(L["Poll: %s (%s)"], p.question or "", table.concat(p.options or {}, " / "))
    end

    if isOfficer then
        -- The question says what it is while empty; the options box is three lines tall with its
        -- hint right under it (#371).
        local createBtn = UI:CreateButton(panel, L["Create Poll"], 110, FIELD_H)
        local qBox = UI:CreateInput(panel, 0, FIELD_H, { max = POLL_MAX_QUESTION, placeholder = L["Question..."] })
        qBox:SetPoint("TOPLEFT", 0, -GAP)
        qBox:SetPoint("TOPRIGHT", -(GAP + UI.ReserveFor(createBtn, GAP)), -GAP)
        createBtn:SetPoint("LEFT", qBox, "RIGHT", GAP, 0)
        local oArea = UI:CreateTextArea(panel, 0, 56)   -- a multi-line EditBox alone shrinks to one line
        oArea:SetPoint("TOPLEFT", qBox, "BOTTOMLEFT", 0, -GAP)
        oArea:SetPoint("TOPRIGHT", createBtn, "BOTTOMRIGHT", 0, -GAP)
        local oBox = oArea.edit
        local hint = UI:CreateText(panel, L["One option per line (2-6)"], 11, soft.r, soft.g, soft.b)
        hint:SetPoint("TOPLEFT", oArea, "BOTTOMLEFT", 0, -4)
        local countFS = UI:CreateText(panel, "", 11, soft.r, soft.g, soft.b)
        countFS:SetPoint("TOPRIGHT", oArea, "BOTTOMRIGHT", 0, -4)

        local function countQuestion()
            countFS:SetText(string.format(L["Question: %d of %d characters"], #(qBox:GetText() or ""), POLL_MAX_QUESTION))
        end
        qBox:HookScript("OnTextChanged", countQuestion)
        countQuestion()

        -- The hint turns to a warning past six options: only six are kept (#17).
        local function paintOptions()
            local n = 0
            for line in (oBox:GetText() .. "\n"):gmatch("([^\n]*)\n") do
                if strtrim(line) ~= "" then n = n + 1 end
            end
            if n > POLL_MAX_OPTIONS then
                hint:SetText(string.format(L["Only the first %d options count."], POLL_MAX_OPTIONS))
                hint:SetTextColor(C.warn.r, C.warn.g, C.warn.b)
            else
                hint:SetText(L["One option per line (2-6)"])
                hint:SetTextColor(soft.r, soft.g, soft.b)
            end
        end
        oBox:HookScript("OnTextChanged", paintOptions)

        -- Hidden results until it closes, and a close time for it on its own (#9, #10).
        local hideCb = UI:CreateCheckbox(panel, L["Hide results until closed"], 16)
        hideCb:SetPoint("TOPLEFT", hint, "BOTTOMLEFT", 0, -GAP)
        local dayBtn = UI:CreateButton(panel, "", 170, FIELD_H)
        dayBtn:SetPoint("TOPLEFT", hideCb, "BOTTOMLEFT", 0, -GAP)
        local function dayText()
            local d = POLL_DAYS[dayIdx]
            return d and string.format(L["Closes in %d days"], d) or L["Stays open"]
        end
        dayBtn.label:SetText(dayText())
        dayBtn:SetScript("OnClick", function()
            dayIdx = dayIdx % #POLL_DAYS + 1
            dayBtn.label:SetText(dayText())
        end)
        tipOn(dayBtn, L["How long the poll stays open. It closes on its own after that."])

        formMsg = UI:CreateText(panel, "", 11, soft.r, soft.g, soft.b)
        formMsg:SetPoint("TOPLEFT", dayBtn, "BOTTOMLEFT", 0, -GAP)
        formLast = formMsg

        createBtn:SetScript("OnClick", function()
            local question = strtrim(qBox:GetText() or "")
            local opts, extra = {}, 0
            for line in (oBox:GetText() .. "\n"):gmatch("([^\n]*)\n") do
                local t = strtrim(line)
                if t ~= "" then
                    if #opts < POLL_MAX_OPTIONS then opts[#opts + 1] = t else extra = extra + 1 end
                end
            end
            if question == "" then
                setFormMsg(L["Type a question first."], C.warn)
                qBox:SetFocus()
                return
            end
            if #opts < 2 then
                setFormMsg(L["Add at least 2 options."], C.warn)
                oBox:SetFocus()
                return
            end
            if GuildOS.Polls then
                GuildOS.Polls:Create(question, opts, {
                    hideResults = hideCb.checkbox:GetChecked() and true or nil,
                    days = POLL_DAYS[dayIdx],
                })
            end
            qBox:SetText(""); oBox:SetText("")
            qBox:ClearFocus(); oBox:ClearFocus()
            paintOptions(); countQuestion()
            if extra > 0 then
                setFormMsg(string.format(L["Only the first %d options count."], POLL_MAX_OPTIONS), C.warn)
            else
                setFormMsg(L["Poll created."], soft)
            end
        end)
    end

    -- The filters (#14), and the summary of how many are open and closed (#16). The list hangs under them.
    local filterBtns, firstFilter, prevFilter = {}, nil, nil
    for _, d in ipairs(POLL_FILTERS) do
        local key = d[1]
        local b = UI:CreateButton(panel, L[d[2]], 70, 20)
        if prevFilter then
            b:SetPoint("LEFT", prevFilter, "RIGHT", 4, 0)
        elseif formLast then
            b:SetPoint("TOPLEFT", formLast, "BOTTOMLEFT", 0, -GAP)
        else
            b:SetPoint("TOPLEFT", 0, -GAP)
        end
        b:SetScript("OnClick", function()
            filter = key
            refresh()
        end)
        filterBtns[key] = b
        firstFilter = firstFilter or b
        prevFilter = b
    end
    local summaryFS = UI:CreateText(panel, "", 11, soft.r, soft.g, soft.b)
    summaryFS:SetPoint("LEFT", prevFilter, "RIGHT", GAP, 0)

    local _, child = makeScroll(panel, "GuildOSHubPollsScroll", firstFilter)

    local function keyOf(name)
        local short = (name or ""):match("^([^-]+)") or name
        return GuildOS:GetPlayerKey(short, GetRealmName())
    end

    refresh = function()
        clear(child)
        local P = GuildOS.Polls
        for key, b in pairs(filterBtns) do UI:SetSelected(b, filter == key) end
        local list = (P and P:GetSorted()) or {}
        local myKey = keyOf(GuildOS.Compat.PlayerName())
        local openN, closedN = 0, 0
        for _, p in ipairs(list) do
            if P:IsClosed(p) then closedN = closedN + 1 else openN = openN + 1 end
        end
        summaryFS:SetText(string.format(L["%d open · %d closed"], openN, closedN))

        local y, shown = 0, 0
        for _, p in ipairs(list) do
            local isClosed = P:IsClosed(p)
            if filter == "all" or (filter == "closed") == isClosed then
                shown = shown + 1
                if shown > 1 then
                    -- A rule between one poll and the next (#6).
                    y = y + 12
                    local rule = child:CreateTexture(nil, "ARTWORK")
                    rule:SetColorTexture(C.line.r, C.line.g, C.line.b, 1)
                    rule:SetHeight(1)
                    rule:SetPoint("TOPLEFT", 0, -(y - 6))
                    rule:SetPoint("TOPRIGHT", 0, -(y - 6))
                end

                -- The question in the text colour, a closed one in the soft one (#371).
                local qc = isClosed and soft or C.text
                local prefix = isClosed and ("[" .. L["closed"] .. "] ") or ""
                local q = UI:CreateText(child, prefix .. (p.question or ""), 12, qc.r, qc.g, qc.b)
                q:SetPoint("TOPLEFT", 0, -y)
                q:SetPoint("TOPRIGHT", 0, -y)
                q:SetJustifyH("LEFT")
                y = y + math.max(18, (q:GetStringHeight() or 14) + 4)

                -- The tallies. Hidden results show no counts until the poll closes (#9).
                local total, counts, voters = 0, {}, {}
                for voterKey, opt in pairs(p.votes or {}) do
                    counts[opt] = (counts[opt] or 0) + 1
                    total = total + 1
                    voters[opt] = voters[opt] or {}
                    voters[opt][#voters[opt] + 1] = voterKey:match("^([^%-]+)") or voterKey
                end
                for _, names in pairs(voters) do table.sort(names) end
                local hidden = p.hideResults and not isClosed
                local topCount = 0
                if isClosed then
                    for i = 1, #(p.options or {}) do topCount = math.max(topCount, counts[i] or 0) end
                end
                local myVote = p.votes and p.votes[myKey]

                for idx, optText in ipairs(p.options or {}) do
                    local n = counts[idx] or 0
                    local pct = total > 0 and math.floor(n / total * 100 + 0.5) or 0
                    local label = optText
                    if not hidden then
                        label = string.format("%s  (%d · %d%%)", optText, n, pct)
                        -- The option or options with the most votes, once it has closed (#2).
                        if isClosed and topCount > 0 and n == topCount then
                            label = label .. "  " .. rgbHex(C.gold) .. L["Leading"] .. "|r"
                        end
                    end
                    local btn = UI:CreateButton(child, label, 1, 20)
                    btn:SetPoint("TOPLEFT", 0, -y)
                    btn:SetPoint("TOPRIGHT", 0, -y)
                    -- My vote is the selected option, as every selection is marked (#371).
                    UI:SetSelected(btn, myVote == idx)
                    btn.label:ClearAllPoints()
                    btn.label:SetPoint("LEFT", 8, 0)

                    -- The share of the vote, as a bar behind the option (#1).
                    if not hidden and total > 0 and n > 0 then
                        local fill = btn:CreateTexture(nil, "BORDER")
                        fill:SetColorTexture(C.lineHi.r, C.lineHi.g, C.lineHi.b, 0.45)
                        fill:SetPoint("TOPLEFT", 1, -1)
                        fill:SetPoint("BOTTOMLEFT", 1, 1)
                        local share = n / total
                        local function size() fill:SetWidth(math.max(1, (btn:GetWidth() - 2) * share)) end
                        btn:HookScript("OnSizeChanged", size)
                        size()
                    end

                    -- Hover: who picked it (#8), or why the tallies are hidden.
                    local names = voters[idx] or {}
                    local lines = {}
                    if not isClosed then lines[#lines + 1] = L["Click to vote."] end
                    if hidden then
                        lines[#lines + 1] = L["Results are hidden until the poll closes."]
                    elseif #names > 0 then
                        for _, nm in ipairs(names) do lines[#lines + 1] = nm end
                    else
                        lines[#lines + 1] = L["Nobody has voted for this yet."]
                    end
                    listTip(btn, optText, lines)

                    if not isClosed then
                        local id, oi = p.id, idx
                        btn:SetScript("OnClick", function() if GuildOS.Polls then GuildOS.Polls:Vote(id, oi) end end)
                    end
                    y = y + 22
                end

                -- The meta line: the votes and the author in their class colour (#4), and when it was posted (#5).
                local metaY = y + 2
                local votesKey = total == 1 and L["%d vote · by %s"] or L["%d votes · by %s"]
                local meta = UI:CreateText(child, table.concat({
                    string.format(votesKey, total, authorText(p.author)),
                    GuildOS:TimeAgo(p.ts or 0),
                }, " · "), 11, soft.r, soft.g, soft.b)
                meta:SetPoint("TOPLEFT", 0, -metaY)
                local hit = CreateFrame("Frame", nil, child)
                hit:SetPoint("TOPLEFT", meta, "TOPLEFT", 0, 0)
                hit:SetSize(math.max(20, meta:GetStringWidth() or 20), 14)
                hit:EnableMouse(true)
                tipOn(hit, string.format(L["Posted %s"], GuildOS:DateText(p.ts or 0, " %H:%M")))

                -- The status line: closed or when it closes (#3, #10), hidden results, and my vote (#15).
                local status = {}
                if p.closed then
                    status[#status + 1] = L["Closed"]
                elseif isClosed then
                    status[#status + 1] = string.format(L["Closed %s"], GuildOS:DateText(p.closesAt or 0, ""))
                elseif p.closesAt then
                    status[#status + 1] = string.format(L["Closes %s"], GuildOS:DateText(p.closesAt, ""))
                end
                if hidden then status[#status + 1] = L["Results hidden until closed"] end
                if myVote and p.options and p.options[myVote] then
                    status[#status + 1] = string.format(L["You voted: %s"], p.options[myVote])
                elseif isClosed then
                    status[#status + 1] = L["You did not vote."]
                else
                    status[#status + 1] = L["You have not voted yet."]
                end
                local statusFS = UI:CreateText(child, table.concat(status, " · "), 11, soft.r, soft.g, soft.b)
                statusFS:SetPoint("TOPLEFT", 0, -(metaY + 15))
                y = metaY + 32

                if isOfficer then
                    local id = p.id
                    local line = pollLine(p)
                    -- Delete (#11), Notice (#13), Chat (#13), then Close or Reopen (#12, #19).
                    local del = UI:CreateButton(child, L["Delete"], 56, 18)
                    del:SetPoint("TOPRIGHT", child, "TOPRIGHT", 0, -(metaY - 2))
                    tipOn(del, L["Delete this poll and its votes."])
                    del:SetScript("OnClick", function()
                        GuildOS:ShowDialog("GUILDOS_POLL_DELETE", L["Delete this poll? Its votes go with it."], nil, {
                            run = function() if GuildOS.Polls then GuildOS.Polls:Delete(id) end end,
                        })
                    end)

                    local notice = UI:CreateButton(child, L["Notice"], 56, 18)
                    notice:SetPoint("RIGHT", del, "LEFT", -4, 0)
                    tipOn(notice, L["Post this poll to the bulletin board."])
                    notice:SetScript("OnClick", function()
                        GuildOS:ShowDialog("GUILDOS_POLL_NOTICE", L["Post this poll to the bulletin board?"], nil, {
                            run = function() if GuildOS.Bulletin then GuildOS.Bulletin:Post(line) end end,
                        })
                    end)

                    local chat = UI:CreateButton(child, L["Chat"], 52, 18)
                    chat:SetPoint("RIGHT", notice, "LEFT", -4, 0)
                    tipOn(chat, L["Send this poll to guild chat."])
                    chat:SetScript("OnClick", function()
                        GuildOS:ShowDialog("GUILDOS_POLL_CHAT", L["Send this poll to guild chat?"], nil, {
                            run = function() GuildOS.Compat.SendChatMessage(line:sub(1, 255), "GUILD") end,
                        })
                    end)

                    local toggle = UI:CreateButton(child, isClosed and L["Reopen"] or L["Close"], 62, 18)
                    toggle:SetPoint("RIGHT", chat, "LEFT", -4, 0)
                    if isClosed then
                        tipOn(toggle, L["Open this poll for votes again."])
                        toggle:SetScript("OnClick", function() if GuildOS.Polls then GuildOS.Polls:Reopen(id) end end)
                    else
                        tipOn(toggle, L["Close this poll. Nobody can vote after."])
                        toggle:SetScript("OnClick", function()
                            GuildOS:ShowDialog("GUILDOS_POLL_CLOSE", L["Close this poll? Nobody can vote after."], nil, {
                                run = function() if GuildOS.Polls then GuildOS.Polls:Close(id) end end,
                            })
                        end)
                    end
                end
            end
        end

        if shown == 0 then
            local msg = L["No open polls."]
            if #list == 0 then
                msg = L["No polls yet."]
            elseif filter == "closed" then
                msg = L["No closed polls."]
            end
            local empty = UI:CreateText(child, msg, 12, soft.r, soft.g, soft.b)
            empty:SetPoint("TOPLEFT", 0, 0)
        end
        child:SetHeight(math.max(1, y))
    end
    if GuildOS.Polls then GuildOS.Polls.uiRefresh = refresh end
    return refresh
end

----------------------------------------------------------------------
-- Guild chat feed (issues #124, #126), kept by Modules/GuildChat.lua. Laid out
-- like the alliance feed: one card per run of lines from one speaker, newest at
-- the bottom, a box underneath, and a tab per channel of the guild. Guild > Chat
-- builds the full page; the Now card builds the compact one (no search row).
----------------------------------------------------------------------
local CLASS_TEX = "Interface\\WorldStateFrame\\Icons-Classes"
local feeds = 0               -- each feed's scroll frame needs its own global name
local SEND_MAX = 240          -- the bytes Send keeps (GuildChat:Send)
local CHAT_GROUP_WINDOW = 120 -- a speaker's run breaks into a new card after two quiet minutes (#3)
local CHAT_MAX_W = 760        -- the widest a line of text runs (#2)
local CHAT_SIZES = { small = 10, normal = 11, large = 13 }
local CHAT_SIZE_NEXT = { small = "normal", normal = "large", large = "small" }
local SENT_MAX = 20           -- the lines the Up arrow can bring back (#10)

-- A channel is { id, name, kind }; nil, and the Guild tab, mean /g.
local function idOf(stream)
    return (stream and stream.kind ~= "guild") and stream.id or nil
end

local function streamLabel(stream)
    if stream.kind == "guild" then return L["Guild"] end
    if stream.kind == "officer" then return L["Officers"] end
    return stream.name or "?"
end

-- The key a channel's read mark goes by (#15, #16).
local function keyFor(stream)
    if not stream or stream.kind == "guild" then return "guild" end
    if stream.kind == "officer" then return "officer" end
    return "club:" .. tostring(stream.id)
end

-- The Mentions switch a channel alerts by, or nil where Mentions does not alert (#20).
local function alertKeyFor(stream)
    if not stream or stream.kind == "guild" then return "guild" end
    if stream.kind == "officer" then return "officer" end
    return nil
end

-- The player's own first name in gold wherever it appears in a line (#19). A line with a link in it
-- is left as it is, so the link keeps its colour codes.
local function markName(line, first)
    if first == "" or line:find("|H", 1, true) then return line end
    local low, needle = line:lower(), first:lower()
    local out, pos = {}, 1
    while true do
        local s, e = low:find(needle, pos, true)
        if not s then break end
        out[#out + 1] = line:sub(pos, s - 1)
        out[#out + 1] = GuildOS.GoldEsc() .. line:sub(s, e) .. "|r"
        pos = e + 1
    end
    out[#out + 1] = line:sub(pos)
    return table.concat(out)
end

-- What a speaker's icon says on hover: level, rank and zone from the roster (#7).
local function memberTip(frame, name)
    if not GameTooltip or not name then return end
    local soft = C.textSoft
    GameTooltip:SetOwner(frame, "ANCHOR_TOP")
    GameTooltip:AddLine(name, GuildOS.Tip.text.r, GuildOS.Tip.text.g, GuildOS.Tip.text.b)
    local m = GuildOS.db and GuildOS.db.members and GuildOS.db.members[GuildOS:LocalMemberKey(name)]
    if type(m) == "table" then
        if m.level then GameTooltip:AddLine(string.format(L["Level %d"], m.level), soft.r, soft.g, soft.b) end
        local GM = GuildOS.GuildManager
        local rank = (GM and GM.GetRankName and m.rankIndex) and GM:GetRankName(m.rankIndex)
        if rank then GameTooltip:AddLine(string.format(L["Rank: %s"], rank), soft.r, soft.g, soft.b) end
        if m.zone and m.zone ~= "" then GameTooltip:AddLine(string.format(L["Zone: %s"], m.zone), soft.r, soft.g, soft.b) end
    else
        GameTooltip:AddLine(L["Not on the roster."], soft.r, soft.g, soft.b)
    end
    GameTooltip:Show()
end

-- `top`: room over the feed. The Guild tab leaves GAP under its sub-tab bar, as on every sub-tab
-- (#371); a Now card gives none, and has no search row.
function GuildOS:CreateGuildChatFeed(panel, top)
    local GC = GuildOS.GuildChat
    local full = top ~= nil
    local current   -- the channel open; nil is /g
    top = top or 0
    feeds = feeds + 1
    local soft, dim = C.textSoft, C.textDim
    local refresh   -- set below; the tabs, the search and the buttons repaint through it
    local search = ""
    local dividerAt = 0   -- the read mark the channel open had when it was last left: where new lines start (#16)
    local seen = {}       -- per channel: when its lines were last read on this page (#15, #16)
    local sent, histAt = {}, 0
    local pinBottom = true
    local scrolling = false   -- a move to the bottom is queued for the next frame
    local waiting = false     -- a look after a chat lockdown is queued
    local row = full and (TAB_H + 4) or 0

    -- The channel tabs, left; on the full page, the search box and the alert switch, right.
    local bar = CreateFrame("Frame", nil, panel)
    bar:SetPoint("TOPLEFT", 0, -top)
    bar:SetSize(400, TAB_H)
    UI:StyleSubTabBar(bar)
    bar:Hide()
    local tabs = {}

    local searchBox, muteBtn
    if full then
        searchBox = UI:CreateInput(panel, 170, FIELD_H, { placeholder = L["Search this chat"] })
        searchBox:SetPoint("TOPRIGHT", 0, -(top + math.floor((TAB_H - FIELD_H) / 2)))
        searchBox:SetMaxLetters(60)
        searchBox:HookScript("OnTextChanged", function(self, userInput)
            if not userInput then return end
            search = strtrim(self:GetText() or ""):lower()
            refresh()
        end)
        muteBtn = UI:CreateButton(panel, "", 66, FIELD_H)
        muteBtn:SetPoint("TOPRIGHT", searchBox, "TOPLEFT", -6, 0)
    end

    local function paintMute()
        if not muteBtn then return end
        local key, cfg = alertKeyFor(current), GuildOS.db.mentions
        muteBtn:SetShown(key ~= nil and cfg ~= nil)
        if key and cfg then
            muteBtn.label:SetText(cfg[key] ~= false and L["Alerts on"] or L["Alerts off"])
        end
    end
    if muteBtn then
        tipOn(muteBtn, L["Mention alerts for this channel. Click to switch them on or off."])
        muteBtn:SetScript("OnClick", function()
            local cfg, key = GuildOS.db.mentions, alertKeyFor(current)
            if not cfg or not key then return end
            cfg[key] = (cfg[key] == false)   -- on when it was off, off when it was on
            paintMute()
        end)
    end

    local holder = CreateFrame("Frame", nil, panel)
    local function anchorHolder(belowTabs)
        holder:ClearAllPoints()
        if full then
            holder:SetPoint("TOPLEFT", 0, -(top + row))
        elseif belowTabs then
            holder:SetPoint("TOPLEFT", bar, "BOTTOMLEFT", 0, -4)
        else
            holder:SetPoint("TOPLEFT", 0, -top)
        end
        holder:SetPoint("BOTTOMRIGHT", 0, 32)
    end
    anchorHolder(false)
    local scroll, content = UI:CreateScrollFrame(holder, "GuildOSGuildChatScroll" .. feeds)
    scroll:SetAllPoints()

    -- The line to say where a message goes, then the box, then the counter, the text size and Send.
    local targetFS = UI:CreateText(panel, "", 11, soft.r, soft.g, soft.b)
    targetFS:SetPoint("BOTTOMLEFT", 0, 4 + math.floor((FIELD_H - 12) / 2))
    local input = UI:CreateInput(panel, 100, FIELD_H)
    input:SetPoint("BOTTOMLEFT", 92, 4)
    input:SetPoint("BOTTOMRIGHT", -118, 4)
    input:SetMaxBytes(SEND_MAX + 1)   -- what Send keeps (240 bytes), plus the terminator
    input:SetTextInsets(6, 58, 0, 0)
    local counter = UI:CreateText(input, "", 10, soft.r, soft.g, soft.b)
    counter:SetPoint("RIGHT", input, "RIGHT", -6, 0)
    local function paintCounter()
        local n = #(input:GetText() or "")
        counter:SetText(string.format("%d/%d", n, SEND_MAX))
        local col = n > SEND_MAX - 40 and C.warn or soft
        counter:SetTextColor(col.r, col.g, col.b)
    end
    input:HookScript("OnTextChanged", function(self, userInput)
        if userInput then histAt = 0 end
        paintCounter()
    end)
    paintCounter()

    local sendBtn = UI:CreateButton(panel, L["Send"], 62, FIELD_H)
    sendBtn:SetPoint("BOTTOMRIGHT", 0, 4)
    local sizeKey = GuildOS:GetSetting("guildChatSize")
    if not CHAT_SIZES[sizeKey] then sizeKey = "normal" end
    local sizeBtn = UI:CreateButton(panel, "Aa", 40, FIELD_H)
    sizeBtn:SetPoint("BOTTOMRIGHT", -70, 4)
    tipOn(sizeBtn, L["Change the size of the chat text."])
    sizeBtn:SetScript("OnClick", function()
        sizeKey = CHAT_SIZE_NEXT[sizeKey] or "normal"
        GuildOS:SetSetting("guildChatSize", sizeKey)
        refresh()
    end)

    local empty = UI:CreateText(content, L["No guild chat yet."], 12, soft.r, soft.g, soft.b)
    empty:SetPoint("TOPLEFT", 0, -4)

    -- The "Latest" button: shown while the reader is up the feed, and it goes back to the bottom (#14).
    local jump = UI:CreateButton(panel, L["Latest"], 70, 20)
    jump:SetPoint("BOTTOMRIGHT", holder, "BOTTOMRIGHT", -18, 8)
    jump:SetFrameLevel((holder:GetFrameLevel() or 1) + 10)
    jump:Hide()
    local function updateJump()
        local atBottom = scroll:GetVerticalScroll() >= scroll:GetVerticalScrollRange() - 4
        jump:SetShown(not atBottom and not GC:Locked() and (content:GetHeight() or 0) > holder:GetHeight())
    end
    jump:SetScript("OnClick", function()
        scroll:SetVerticalScroll(scroll:GetVerticalScrollRange())
        updateJump()
    end)
    scroll:HookScript("OnVerticalScroll", updateJump)

    -- Another channel: the server stops being told about the old one, and is told about this one.
    local function open(stream)
        -- In a chat lockdown the feed cannot be redrawn: a channel changed then would send Enter
        -- somewhere other than what is on screen, an officer's line to the whole guild.
        if GC:Locked() or idOf(stream) == idOf(current) then return end
        GC:Watch(false, current)
        current = idOf(stream) and stream or nil
        GC:Watch(true, current)
        dividerAt = seen[keyFor(current)] or 0
        pinBottom = true
        refresh()
    end

    -- A channel's unread lines: those newer than the last time its lines were read here (#15).
    -- A channel first seen starts with none unread.
    local function unreadOf(stream)
        local k = keyFor(stream)
        if seen[k] == nil then
            seen[k] = GetServerTime()
            return 0
        end
        local entries = GC:Entries(stream)
        if not entries then return 0 end
        local n = 0
        for i = #entries, 1, -1 do
            if (tonumber(entries[i].t) or 0) <= seen[k] then break end
            n = n + 1
        end
        return n
    end

    local function layoutTabs()
        local streams = GC:Streams()
        local list = (streams and #streams > 1) and streams or nil
        -- The channel open is gone (removed, or no longer listed to this player): back to /g.
        if current then
            local still
            for _, s in ipairs(list or {}) do
                if s.id == current.id then still = s end
            end
            if not still then
                -- Hidden, the feed already stopped watching it.
                local watched = panel:IsVisible()
                if watched then GC:Watch(false, current) end
                current = nil
                if watched then GC:Watch(true, nil) end
            end
        end
        bar:SetShown(list ~= nil)
        anchorHolder(list ~= nil)
        if not list then return end
        local shown = {}
        for i, s in ipairs(list) do
            local t = tabs[i]
            if not t then
                t = UI:CreateTab(bar, "", TAB_MIN_W, true)
                t:SetScript("OnClick", function(self) open(self.stream) end)
                tabs[i] = t
            end
            t.stream = s
            local unread = (keyFor(s) == keyFor(current)) and 0 or unreadOf(s)
            local count = unread > 0 and string.format(" (%s)", unread > 99 and "99+" or tostring(unread)) or ""
            t.label:SetText(streamLabel(s) .. count)
            t:SetWidth(math.max(TAB_MIN_W, math.ceil(t.label:GetStringWidth()) + TAB_PAD))
            t:SetActive(idOf(s) == idOf(current))
            t:Show()
            shown[#shown + 1] = t
        end
        for i = #list + 1, #tabs do tabs[i]:Hide() end
        bar:SetWidth(math.max(TAB_MIN_W, (panel:GetWidth() or 0) - (full and 250 or 0)))
        UI:FlowBar(bar, shown, { gap = 4, rowGap = 4, rowH = TAB_H })
    end

    -- Where the box says the message goes (#11), or that chat is locked (#12).
    local function paintTarget()
        if GC:Locked() then
            targetFS:SetText(L["Locked"])
            targetFS:SetTextColor(C.warn.r, C.warn.g, C.warn.b)
            return
        end
        targetFS:SetText(string.format(L["To %s"], streamLabel(current or { kind = "guild" })))
        targetFS:SetTextColor(soft.r, soft.g, soft.b)
    end

    -- A send refused in a lockdown: the text stays in the box, and the line says so for a moment (#12).
    local function flashLocked()
        targetFS:SetText(L["Locked"])
        targetFS:SetTextColor(C.warn.r, C.warn.g, C.warn.b)
        GuildOS.Compat.After(3, paintTarget)
    end

    -- Pooled: refresh runs on every line of chat, and WoW never frees a frame.
    local blocks, dividers = {}, {}
    local function getDivider(i)
        if dividers[i] then return dividers[i] end
        local fs = UI:CreateText(content, "", 10, dim.r, dim.g, dim.b)
        local rule = content:CreateTexture(nil, "ARTWORK")
        rule:SetColorTexture(C.line.r, C.line.g, C.line.b, 1)
        rule:SetHeight(1)
        dividers[i] = { fs = fs, rule = rule }
        return dividers[i]
    end

    local function getBlock(i)
        if blocks[i] then return blocks[i] end
        local b = {}
        local card = CreateFrame("Frame", nil, content, "BackdropTemplate")
        card:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = GuildOS.UI:Edge(card) })
        -- A link in the line opens as it does in the chat frame.
        card:EnableMouse(true)
        card:SetHyperlinksEnabled(true)
        card:SetScript("OnHyperlinkClick", function(_, link, text, button) SetItemRef(link, text, button) end)
        -- Right-click a card to copy its lines (#13).
        card:SetScript("OnMouseUp", function(_, button)
            if button == "RightButton" and b.copy then showCopy(b.copy) end
        end)
        local icon = card:CreateTexture(nil, "ARTWORK")
        icon:SetSize(20, 20)
        icon:SetPoint("TOPLEFT", 8, -6)
        icon:SetTexture(CLASS_TEX)
        local iconHit = CreateFrame("Frame", nil, card)
        iconHit:SetSize(20, 20)
        iconHit:SetPoint("TOPLEFT", 8, -6)
        iconHit:EnableMouse(true)
        iconHit:SetScript("OnEnter", function(self) memberTip(self, b.name) end)
        iconHit:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
        local nameFS = UI:CreateText(card, "", 11, C.text.r, C.text.g, C.text.b)
        nameFS:SetPoint("TOPLEFT", 36, -7)
        -- A click on the name (#13, #18): left whispers, right shows only that player's lines, Ctrl invites.
        local nameHit = CreateFrame("Button", nil, card)
        nameHit:SetPoint("TOPLEFT", 36, -6)
        nameHit:SetHeight(14)
        nameHit:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        nameHit:SetScript("OnClick", function(_, button)
            if not b.name then return end
            if button == "RightButton" then
                if full and searchBox then
                    search = b.name:lower()
                    searchBox:SetText(b.name)
                    refresh()
                end
            elseif IsControlKeyDown() then
                local invite = (C_PartyInfo and C_PartyInfo.InviteUnit) or InviteUnit
                if invite then invite(b.name) end
            elseif ChatFrame_SendTell then
                ChatFrame_SendTell(b.name)
            end
        end)
        local bodyFS = UI:CreateText(card, "", 11, C.text.r, C.text.g, C.text.b)
        bodyFS:SetPoint("TOPLEFT", 36, -22)
        bodyFS:SetJustifyH("LEFT")
        bodyFS:SetWordWrap(true)
        b.card, b.icon, b.nameFS, b.nameHit, b.bodyFS = card, icon, nameFS, nameHit, bodyFS
        blocks[i] = b
        return b
    end

    refresh = function()
        paintTarget()
        paintMute()
        -- In a chat lockdown the server's lines and channels arrive secret: keep what is drawn,
        -- and look again every 2 seconds while on screen, since no event says the lockdown lifted.
        if GC:Locked() then
            if not waiting then
                waiting = true
                GuildOS.Compat.After(2, function()
                    waiting = false
                    if panel:IsVisible() then refresh() end
                end)
            end
            updateJump()
            return
        end
        local follow = pinBottom or scrolling or scroll:GetVerticalScroll() >= scroll:GetVerticalScrollRange() - 4
        pinBottom = false
        layoutTabs()
        -- Born 0 wide (CreateScrollFrame sizes it before layout), so re-set on every draw.
        content:SetWidth(math.max(holder:GetWidth() - 12, 1))
        if panel:IsVisible() then seen[keyFor(current)] = GetServerTime() end

        local raw = GC:Entries(current) or {}
        local classOf = {}
        for _, e in ipairs(raw) do classOf[e.n] = e.c or classOf[e.n] end
        local log = raw
        if search ~= "" then
            log = {}
            for _, e in ipairs(raw) do
                if (e.n or ""):lower():find(search, 1, true) or (e.m or ""):lower():find(search, 1, true) then
                    log[#log + 1] = e
                end
            end
        end
        local groups = GuildOS.AllianceChat.GroupLog(log, CHAT_GROUP_WINDOW)

        -- The list in draw order: a day's line where the day changes (#4), and the new-lines line
        -- before the first line newer than the last read (#16).
        local items, prevDay, olderSeen, newDone = {}, nil, false, false
        for _, g in ipairs(groups) do
            local t = tonumber(g.t) or 0
            local day = t > 0 and date("%Y%m%d", t) or nil
            if day and prevDay and day ~= prevDay then
                items[#items + 1] = { text = GuildOS:LocalDate("%a %d %b", t) }
            end
            if day then prevDay = day end
            if dividerAt > 0 and not newDone then
                if t <= dividerAt then
                    olderSeen = true
                elseif olderSeen then
                    items[#items + 1] = { text = L["New since you last looked"], gold = true }
                    newDone = true
                end
            end
            items[#items + 1] = { group = g }
        end

        local today = date("%Y%m%d", GetServerTime())
        local width = math.max(content:GetWidth() - 12, 200)
        local myFirst = (GuildOS.Compat.PlayerName() or ""):match("^([^%-]+)") or ""
        local sizeFont = CHAT_SIZES[sizeKey]
        local y, bi, di = 0, 0, 0
        for _, it in ipairs(items) do
            if it.text then
                di = di + 1
                local d = getDivider(di)
                local col = it.gold and C.gold or dim
                d.fs:SetText(it.text)
                d.fs:SetTextColor(col.r, col.g, col.b)
                d.fs:SetPoint("TOPLEFT", 8, -(y + 1))
                d.rule:SetPoint("TOPLEFT", 0, -(y + 16))
                d.rule:SetPoint("TOPRIGHT", 0, -(y + 16))
                d.fs:Show()
                d.rule:Show()
                y = y + 20
            else
                bi = bi + 1
                local g = it.group
                local b = getBlock(bi)
                if b.size ~= sizeKey then
                    GuildOS:ApplyFont(b.bodyFS, sizeFont)
                    b.size = sizeKey
                end
                b.name = g.name
                b.copy = table.concat(g.lines, "\n")
                local class = classOf[g.name]
                local coords = CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[class]
                if coords then
                    b.icon:SetTexCoord(coords[1], coords[2], coords[3], coords[4])
                    b.icon:Show()
                else
                    b.icon:Hide()
                end
                -- A line from an allied guild (issue #344) says which one, in its colour.
                local who = g.name or "?"
                if g.guild and GuildOS.Alliance then
                    who = "|cff" .. GuildOS.Alliance.GuildColorHex(g.guild) .. "[" .. g.guild .. "]|r " .. who
                end
                -- The time sits on the name line (#1): the clock today, the day and clock before it.
                -- A line from another day says which day, since the log outlives the session.
                local t = tonumber(g.t)
                local stamp = t and GuildOS:LocalDate(date("%Y%m%d", t) == today and "%H:%M" or "%a %H:%M", t) or ""
                b.nameFS:SetText(stamp ~= "" and (who .. "  " .. rgbHex(dim) .. stamp .. "|r") or who)
                b.nameFS:SetTextColor(GuildOS:GetClassColor(class))
                b.nameHit:SetWidth(math.max(24, math.min(b.nameFS:GetStringWidth() or 24, width - 60)))
                local lines = {}
                for k, ln in ipairs(g.lines) do lines[k] = markName(ln, myFirst) end
                local bodyW = math.min(width - 44, CHAT_MAX_W)
                b.bodyFS:SetWidth(bodyW)
                b.bodyFS:SetText(table.concat(lines, "\n"))
                local h = math.max(34, (b.bodyFS:GetStringHeight() or 12) + 28)
                -- My own lines carry a gold wash (#6).
                local mine = g.name ~= nil and g.name == myFirst
                if mine then
                    b.card:SetBackdropColor(C.gold.r, C.gold.g, C.gold.b, 0.10)
                else
                    b.card:SetBackdropColor(C.bg2.r, C.bg2.g, C.bg2.b, 0.55)
                end
                b.card:SetBackdropBorderColor(C.border.r, C.border.g, C.border.b, 0.35)
                b.card:SetPoint("TOPLEFT", 0, -y)
                b.card:SetSize(width, h)
                b.card:Show()
                y = y + h + 3
            end
        end
        for i = bi + 1, #blocks do blocks[i].card:Hide() end
        for i = di + 1, #dividers do dividers[i].fs:Hide(); dividers[i].rule:Hide() end
        empty:SetText(search ~= "" and L["Nothing matches your search."] or L["No guild chat yet."])
        empty:SetShown(#items == 0)
        if #items == 0 then y = 20 end
        content:SetHeight(math.max(y, 1))
        -- A frame later: the scroll range follows the new height only after it lands.
        if follow then
            local target = math.max(0, y - holder:GetHeight())
            scrolling = true
            GuildOS.Compat.After(0, function()
                scrolling = false
                if panel:IsVisible() then scroll:SetVerticalScroll(target) end
                updateJump()
            end)
        else
            GuildOS.Compat.After(0, updateJump)
        end
    end

    -- Enter and the click are the player's own key press, which chat needs on Forever.
    local function doSend()
        local text = input:GetText() or ""
        local ok, why = GC:Send(text, current)
        if ok then
            local clean = strtrim(text)
            if clean ~= "" then
                sent[#sent + 1] = clean
                if #sent > SENT_MAX then table.remove(sent, 1) end
            end
            histAt = 0
            input:SetText("")
            input:SetFocus()   -- the box keeps focus, so the next line can be typed straight away (#9)
        elseif why == "locked" then
            flashLocked()
        end
    end
    sendBtn:SetScript("OnClick", doSend)
    input:SetScript("OnEnterPressed", doSend)
    -- The Up and Down arrows walk back through what was sent (#10).
    input:HookScript("OnKeyDown", function(self, key)
        if #sent == 0 then return end
        if key == "UP" then
            histAt = math.min(histAt + 1, #sent)
        elseif key == "DOWN" then
            histAt = math.max(histAt - 1, 0)
        else
            return
        end
        local text = histAt > 0 and sent[#sent - histAt + 1] or ""
        self:SetText(text)
        self:SetCursorPosition(#text)
    end)

    GC:OnRefresh(function()
        if panel:IsVisible() then refresh() end
    end)
    -- The server is told a channel is being read only while the feed is on screen. Its new-lines line
    -- is where the channel was left, so it is taken before the page marks it read again.
    panel:HookScript("OnShow", function()
        pinBottom = true
        dividerAt = seen[keyFor(current)] or 0
        GC:Watch(true, current)
    end)
    panel:HookScript("OnHide", function() GC:Watch(false, current) end)
    -- The cards are as wide as the view: a resized window lays them out again, once a frame.
    UI:MakeResponsive(holder, function()
        if panel:IsVisible() then refresh() end
    end)
    paintTarget()
    paintMute()
    return refresh
end

----------------------------------------------------------------------
-- EKO patch: ABOUT THE OUTLAWS sub-panel (static guild info, this client only)
----------------------------------------------------------------------
local EKO_GOLD = GuildOS.GoldEsc()
local ABOUT_SECTIONS = {
    { title = "Who We Are", lines = {
        "Eastern Kingdoms Outlaws is a casual, 21+ Alliance guild on WoW: Forever. We're here for leveling, questing, dungeons, raids and just hanging out. Casual at heart, but hardcore players are welcome too.",
        "We're based in EST but every time zone is welcome. Peak hours are about 1 PM to 11 PM EST. Alts and friends are always welcome.",
    } },
    { title = "Our Story", lines = {
        "EKO rose from the ashes of The Final Crusaders, a guild that goes back to 2017, with players from as far back as 2013.",
        "The Outlaws were founded in a hidden tavern called the Gilded Feather by Outlaws who chose freedom over serving crowns. We stand against corrupt nobles, look out for each other, and help folk along the road. Joining the guild means signing the Ledger.",
        "Our symbol is the Wind & Blade, a feather crossed with a dagger. Our motto: " .. EKO_GOLD .. "Free by choice, bound by bond.|r",
    } },
    { title = "Weekly Events", lines = {
        EKO_GOLD .. "Bounty Board|r: Every Monday, 6 dungeons go up (Low, Mid and High). Clear one with 3+ Outlaws and post your group screenshot in #bb-submissions to earn Bounty Points and raffle entries. Run them as often as you want. A full party of 5 Outlaws earns double points.",
        EKO_GOLD .. "Sunday Raffle|r: 1st 5g, 2nd 3g, 3rd 1g. Then 4th and 5th get 70s at 20+ Outlaws entered, 6th and 7th get 50s at 30+, and 8th to 10th get 30s at 40+. Most Bounty Points each month wins Bounty Hunter of the Month.",
        EKO_GOLD .. "Location of the Week|r: New Easy, Medium and Hard spots every Friday. The first 3 to find each spot and post a screenshot with their character in #lotw-submissions win gold. 1 entry per week.",
        EKO_GOLD .. "Raids|r: Our first raids launch December 9, plus a Raid of the Month bounty on the 1st of every month.",
    } },
    { title = "Ranks & Promotions", lines = {
        "Guild Master > GM Alt > Co-Guild Master > Officer > Raid Marshal > Herald > Veteran Outlaw > Outlaw > Alter Ego > Recruit",
        "New members start as Recruits. After 7 days in the guild you can be promoted to Outlaw, based on activity: joining events, groups and dungeons.",
        "Alts go in as Alter Egos, up to 4 per member.",
        "Members who are inactive for 30 days without letting us know will be removed (starting January 1). Going away for a while? Just tell an officer.",
    } },
    { title = "The Outlaw Code", lines = {
        "Respect everyone. No harassment. Keep chat PG-13. No drama or politics. No ninja looting.",
        "We use 3 strikes: a verbal warning, then a written warning, then removal. Slurs and harassment get you removed on the spot.",
    } },
    { title = "Join Us on Discord", lines = {
        EKO_GOLD .. "discord.gg/AdD9kFnQWu|r",
        "Once you're in the guild, use /register in Discord to link your character. Check #server-guide for a map of every channel, and come hang out in the Goldshire voice channel.",
    } },
}

local function BuildAboutSub(panel)
    local _, child = makeScroll(panel, "GuildOSHubAboutScroll")
    local EKO = GuildOS.EKO
    -- Edit: the Guild Master and Co-Guild Masters only (UI/EKO.lua).
    local editBtn = UI:CreateButton(panel, "Edit", 60, 20)
    editBtn:SetPoint("TOPRIGHT", -10, 0)
    editBtn:SetFrameLevel((child:GetFrameLevel() or 1) + 5)
    editBtn:SetScript("OnClick", function()
        if EKO then EKO:OpenAboutEditor(EKO:AboutToText(ABOUT_SECTIONS)) end
    end)
    local refresh, lastWidth
    refresh = function()
        clear(child)
        editBtn:SetShown(EKO and EKO.CanEditAbout and EKO:CanEditAbout() or false)
        local sections = ABOUT_SECTIONS
        local stored = EKO and EKO.AboutStored and EKO:AboutStored()
        if stored and type(stored.text) == "string" then
            local parsed = EKO:ParseAbout(stored.text)
            if #parsed > 0 then sections = parsed end
        end
        local width = child:GetWidth() or 0
        lastWidth = width
        local y = 0
        for i, sec in ipairs(sections) do
            if i > 1 then y = y + SECTION_SPACE end
            local head = UI:CreateSectionTitle(child, sec.title, i == 1)
            head:SetPoint("TOPLEFT", 0, -y)
            head:SetPoint("TOPRIGHT", 0, -y)
            y = y + math.max(18, (head:GetStringHeight() or 14) + GAP)
            for _, line in ipairs(sec.lines) do
                local fs = UI:CreateText(child, line, 12, C.text.r, C.text.g, C.text.b)
                fs:SetPoint("TOPLEFT", 0, -y)
                -- Set the width before reading the height: a wrapped line is measured at this width,
                -- so a narrow window gets the extra rows it needs instead of overlapping the next line.
                if width > 8 then fs:SetWidth(width - 8) end
                fs:SetJustifyH("LEFT")
                fs:SetWordWrap(true)
                y = y + math.max(16, (fs:GetStringHeight() or 14) + 6)
            end
        end
        child:SetHeight(math.max(1, y))
    end
    -- Re-lay the page when the window's width changes. The width check stops the page's own height
    -- changes, made by refresh, from calling it again.
    child:HookScript("OnSizeChanged", function()
        C_Timer.After(0, function()
            if panel:IsVisible() and (child:GetWidth() or 0) ~= lastWidth then refresh() end
        end)
    end)
    if EKO then EKO.aboutRefresh = function() if panel:IsVisible() then refresh() end end end
    return refresh
end

----------------------------------------------------------------------
-- Guild Hub assembly (sub-tab bar mirrors the Audit panel)
----------------------------------------------------------------------
-- `feature`: offered only while that feature may open here (UI:IsFeatureAllowed: present on this
-- client, switched on, started), and built the first time it opens. The Journal and Achievements
-- tabs became the last two (issue #367); both are WoW: Forever's. Achievements leads the bar and is
-- where Guild opens wherever it is offered (#373); elsewhere Guild opens on Calendar.
local HUB_SUBTABS = {
    { key = "about",    label = "About the Outlaws" },  -- EKO patch
    { key = "wanted",   label = "Wanted" },             -- EKO patch (UI/EKO.lua)
    { key = "raffle",   label = "Raffle" },             -- EKO patch
    { key = "tavern",   label = "Tavern" },             -- EKO patch
    { key = "achievements", label = L["Achievements"], feature = "achievements" },
    { key = "calendar", label = L["Calendar"] },
    { key = "activity", label = L["Activity"] },
    { key = "bulletin", label = L["Bulletin"] },
    { key = "cta",      label = L["Call to Arms"] },
    { key = "polls",    label = L["Polls"] },
    { key = "chat",     label = L["Chat"] },
    { key = "journal",      label = L["Journal"],      feature = "journal" },
}

-- `failed`: this hub's lazy sub-tabs whose builder errored (issue #367), refused for the session.
local function hubOffers(key, failed)
    if failed and failed[key] then return false end
    for _, t in ipairs(HUB_SUBTABS) do
        if t.key == key then return not t.feature or UI:IsFeatureAllowed(UI:GetFeature(t.feature)) end
    end
    return false
end

-- Where Guild opens: Achievements where this client has it and it started, else Calendar (#373).
local function hubDefault(failed)
    if hubOffers("about", failed) then return "about" end  -- EKO patch: Guild opens on About the Outlaws
    return hubOffers("achievements", failed) and "achievements" or "calendar"
end

function GuildOS:CreateGuildHub(parent, _mainFrame)
    parent.subPanels = {}
    parent.activeSub = hubDefault()

    -- Anchored on the left only: UI:FlowBar reads GetWidth to wrap, and a frame pinned on both
    -- sides reports a stale width in the frame its container was resized (as ManagementPanel).
    -- EKO patch: the guild bank goal bar across the top of the Guild tab (UI/EKO.lua)
    local ekoTop = -8
    if GuildOS.EKO then
        local goal = GuildOS.EKO:BuildBankGoal(parent)
        goal:SetPoint("TOPLEFT", 10, -8)
        goal:SetPoint("TOPRIGHT", -10, -8)
        parent.ekoGoal = goal
        ekoTop = -44
    end
    local bar = CreateFrame("Frame", nil, parent)
    bar:SetPoint("TOPLEFT", 10, ekoTop)
    bar:SetSize(400, TAB_H)
    UI:StyleSubTabBar(bar)

    local builders = {
        calendar = function(p) return GuildOS:CreateCalendarSub(p) end,
        about = BuildAboutSub,  -- EKO patch
        wanted = function(p) return GuildOS.EKO:BuildWantedSub(p) end,   -- EKO patch
        raffle = function(p) return GuildOS.EKO:BuildRaffleSub(p) end,   -- EKO patch
        tavern = function(p) return GuildOS.EKO:BuildTavernSub(p) end,   -- EKO patch
        activity = BuildActivitySub, bulletin = BuildBulletinSub, polls = BuildPollsSub, cta = BuildCallToArmsSub,
        chat = function(p) return GuildOS:CreateGuildChatFeed(p, GAP) end,
        journal = function(p) return GuildOS:CreateJournalPanel(p) end,
        achievements = function(p) return GuildOS:CreateAchievementsPanel(p) end,
    }
    local failed = {}
    -- The six built with the tab raise as they did, into the tab's own start-up guard. Journal and
    -- Achievements are built the first time they open: one that errors is recorded, with its stack, and
    -- refused for the session rather than left half built (issue #367).
    local function build(key)
        local info = parent.subPanels[key]
        if not info or info.built then return end
        info.built = true
        local def
        for _, t in ipairs(HUB_SUBTABS) do if t.key == key then def = t end end
        if not (def and def.feature) then
            info.refresh = builders[key](info.panel)
            return
        end
        local ok, res = xpcall(function() return builders[key](info.panel) end, function(e)
            return tostring(e) .. (debugstack and ("\n" .. debugstack(2)) or "")
        end)
        if ok then
            info.refresh = res
        else
            failed[key] = true
            GuildOS:RecordError("Guild hub " .. key .. ": " .. tostring(res))
            GuildOS:Print(string.format(L["%s could not start on this client. Type /outlawos errors for details."], def.label))
        end
    end

    local subTabBtns = {}
    -- A sub-tab not offered (switched off, or not on this client) falls back to the calendar, deep
    -- links included.
    local function selectSub(key, filter)
        if not hubOffers(key, failed) then key = hubDefault(failed) end
        build(key)
        if failed[key] then key = hubDefault(failed); build(key) end   -- its builder just errored
        parent.activeSub = key
        for k, info in pairs(parent.subPanels) do info.panel:SetShown(k == key) end
        for k, btn in pairs(subTabBtns) do btn:SetActive(k == key) end
        local info = parent.subPanels[key]
        if info and info.refresh then GuildOS:SafeCall(info.refresh) end
        -- A deep link's filter goes to the sub-panel that takes one (the calendar: a day).
        if filter ~= nil and info and info.panel.ApplyFilter then GuildOS:SafeCall(info.panel.ApplyFilter, filter) end
    end
    parent.SelectSub = selectSub   -- deep links: /outlawos calendar, /outlawos open journal, the Now tab

    -- A tab is as wide as its label: five at a fixed 120px ran off a narrow window (issue #108).
    for _, t in ipairs(HUB_SUBTABS) do
        local btn = UI:CreateTab(bar, t.label, TAB_MIN_W, true)
        btn:SetWidth(math.max(TAB_MIN_W, math.ceil(btn.label:GetStringWidth()) + TAB_PAD))
        btn:SetScript("OnClick", function() selectSub(t.key) end)
        subTabBtns[t.key] = btn
    end

    -- Flow the offered tabs only, so a sub-tab switched off leaves no gap in the bar (as the
    -- Alliance panel).
    local function layoutTabs()
        local shown = {}
        for _, t in ipairs(HUB_SUBTABS) do
            local btn = subTabBtns[t.key]
            local offered = hubOffers(t.key, failed)
            btn:SetShown(offered)
            if offered then shown[#shown + 1] = btn end
        end
        UI:FlowBar(bar, shown, { gap = 4, rowGap = 4, rowH = TAB_H })
    end
    layoutTabs()

    -- An unread count on a sub-tab's label ("Activity  3"), set by the sub-panel that owns it.
    parent.setBadge = function(key, n)
        local btn = subTabBtns[key]
        if not btn then return end
        local base = ""
        for _, t in ipairs(HUB_SUBTABS) do if t.key == key then base = t.label end end
        btn.label:SetText((n and n > 0) and (base .. "  " .. n) or base)
        btn:SetWidth(math.max(TAB_MIN_W, math.ceil(btn.label:GetStringWidth()) + TAB_PAD))
        layoutTabs()
    end

    -- Hung from the bar, so a bar wrapped onto two rows pushes the content down. Flush with the bar on
    -- both sides and right under it: each sub-tab starts its content at x = 0, GAP down (#371), so
    -- every one of them starts at the same place.
    local function makeSubPanel()
        local p = CreateFrame("Frame", nil, parent)
        p:SetPoint("TOPLEFT", bar, "BOTTOMLEFT", 0, 0)
        p:SetPoint("BOTTOMRIGHT", -10, 10)
        p:Hide()
        return p
    end

    for _, t in ipairs(HUB_SUBTABS) do
        parent.subPanels[t.key] = { panel = makeSubPanel() }
        if not t.feature then build(t.key) end
    end

    -- The Activity badge is set before the tab is first opened.
    if GuildOS.Digest then
        local ok, n = pcall(GuildOS.Digest.UnreadCount, GuildOS.Digest)
        if ok then parent.setBadge("activity", n) end
    end

    parent:SetScript("OnShow", function()
        layoutTabs()
        selectSub(parent.activeSub or hubDefault(failed))
    end)
    UI:MakeResponsive(parent, function(_, w)
        bar:SetWidth(math.max(TAB_MIN_W, w - 20))
        layoutTabs()
    end)
end

