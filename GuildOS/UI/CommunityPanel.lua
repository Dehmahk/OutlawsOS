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
        f:SetBackdropColor(0.058, 0.058, 0.075, 0.98)
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
local function BuildBulletinSub(panel)
    local listTop = GAP
    local box
    if GuildOS:IsOfficer() then
        -- One field, so one label beside it, then its button (#371).
        local label = UI:CreateText(panel, L["Notice:"], 12)
        local postBtn = UI:CreateButton(panel, L["Post"], 84, FIELD_H)
        box = UI:CreateInput(panel, 0, FIELD_H, { max = 200 })
        box:SetPoint("TOPLEFT", math.ceil(label:GetStringWidth() or 0) + GAP, -GAP)
        box:SetPoint("TOPRIGHT", -(GAP + UI.ReserveFor(postBtn, GAP)), -GAP)
        label:SetPoint("RIGHT", box, "LEFT", -GAP, 0)
        postBtn:SetPoint("LEFT", box, "RIGHT", GAP, 0)
        local function doPost()
            if GuildOS.Bulletin then GuildOS.Bulletin:Post(box:GetText()) end
            box:SetText(""); box:ClearFocus()
        end
        box:SetScript("OnEnterPressed", doPost)
        postBtn:SetScript("OnClick", doPost)
        listTop = GAP + FIELD_H + GAP
    end
    local _, child = makeScroll(panel, "GuildOSHubBulletinScroll", listTop)

    local function refresh()
        clear(child)
        local msgs = (GuildOS.Bulletin and GuildOS.Bulletin:GetMessages()) or {}
        local isOfficer = GuildOS:IsOfficer()
        local y = 0
        for _, m in ipairs(msgs) do
            local textFS = UI:CreateText(child, m.text, 12, C.text.r, C.text.g, C.text.b)
            textFS:SetPoint("TOPLEFT", 0, -y)
            textFS:SetPoint("TOPRIGHT", isOfficer and -(22 + GAP) or 0, -y)
            textFS:SetJustifyH("LEFT")
            local th = textFS:GetStringHeight() or 14
            local meta = UI:CreateText(child, (m.author or "?") .. " · " .. GuildOS:DateText(m.ts or 0, " %H:%M"),
                11, C.textSoft.r, C.textSoft.g, C.textSoft.b)
            meta:SetPoint("TOPLEFT", 0, -(y + th + 2))
            if isOfficer then
                local del = UI:CreateButton(child, "\195\151", 22, 18)
                del:SetPoint("TOPRIGHT", 0, -y)
                local id = m.id
                del:SetScript("OnClick", function() if GuildOS.Bulletin then GuildOS.Bulletin:Remove(id) end end)
            end
            y = y + th + 22
        end
        if #msgs == 0 then
            local empty = UI:CreateText(child, L["No notices yet."], 12, C.textSoft.r, C.textSoft.g, C.textSoft.b)
            empty:SetPoint("TOPLEFT", 0, 0)
        end
        child:SetHeight(math.max(1, y))
    end
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
local function BuildPollsSub(panel)
    local listTop = GAP
    if GuildOS:IsOfficer() then
        -- The question says what it is while empty; the options box is three lines tall with its
        -- hint right under it (#371).
        local createBtn = UI:CreateButton(panel, L["Create Poll"], 110, FIELD_H)
        local qBox = UI:CreateInput(panel, 0, FIELD_H, { max = 150, placeholder = L["Question..."] })
        qBox:SetPoint("TOPLEFT", 0, -GAP)
        qBox:SetPoint("TOPRIGHT", -(GAP + UI.ReserveFor(createBtn, GAP)), -GAP)
        createBtn:SetPoint("LEFT", qBox, "RIGHT", GAP, 0)
        local oArea = UI:CreateTextArea(panel, 0, 56)   -- a multi-line EditBox alone shrinks to one line
        oArea:SetPoint("TOPLEFT", qBox, "BOTTOMLEFT", 0, -GAP)
        oArea:SetPoint("TOPRIGHT", createBtn, "BOTTOMRIGHT", 0, -GAP)
        local oBox = oArea.edit
        local hint = UI:CreateText(panel, L["One option per line (2-6)"], 11, C.textSoft.r, C.textSoft.g, C.textSoft.b)
        hint:SetPoint("TOPLEFT", oArea, "BOTTOMLEFT", 0, -4)
        listTop = hint
        createBtn:SetScript("OnClick", function()
            local opts = {}
            for line in (oBox:GetText() .. "\n"):gmatch("([^\n]*)\n") do
                local t = strtrim(line)
                if t ~= "" and #opts < 6 then opts[#opts + 1] = t end
            end
            if GuildOS.Polls then GuildOS.Polls:Create(qBox:GetText(), opts) end
            qBox:SetText(""); oBox:SetText(""); qBox:ClearFocus(); oBox:ClearFocus()
        end)
    end
    local _, child = makeScroll(panel, "GuildOSHubPollsScroll", listTop)

    local function keyOf(name)
        local short = (name or ""):match("^([^-]+)") or name
        return GuildOS:GetPlayerKey(short, GetRealmName())
    end

    local function refresh()
        clear(child)
        local polls = (GuildOS.Polls and GuildOS.Polls:GetSorted()) or {}
        local isOfficer = GuildOS:IsOfficer()
        local myKey = keyOf(GuildOS.Compat.PlayerName())
        local y = 0
        for _, p in ipairs(polls) do
            -- The question in the text colour, a closed one in the soft one (#371).
            local qc = p.closed and C.textSoft or C.text
            local q = UI:CreateText(child, (p.closed and "[" .. L["closed"] .. "] " or "") .. p.question, 12, qc.r, qc.g, qc.b)
            local closable = isOfficer and not p.closed
            q:SetPoint("TOPLEFT", 0, -y)
            q:SetPoint("TOPRIGHT", closable and -(56 + GAP) or 0, -y)
            q:SetJustifyH("LEFT")
            if closable then
                local closeBtn = UI:CreateButton(child, L["Close"], 56, 18)
                closeBtn:SetPoint("TOPRIGHT", 0, -y)
                local id = p.id
                closeBtn:SetScript("OnClick", function() if GuildOS.Polls then GuildOS.Polls:Close(id) end end)
            end
            y = y + math.max(18, (q:GetStringHeight() or 14) + 4)

            local total, counts = 0, {}
            for _, opt in pairs(p.votes or {}) do counts[opt] = (counts[opt] or 0) + 1; total = total + 1 end
            local myVote = p.votes and p.votes[myKey]
            for idx, optText in ipairs(p.options or {}) do
                local n = counts[idx] or 0
                local pct = total > 0 and math.floor(n / total * 100 + 0.5) or 0
                local btn = UI:CreateButton(child, string.format("%s  (%d · %d%%)", optText, n, pct), 1, 20)
                btn:SetPoint("TOPLEFT", 0, -y)
                btn:SetPoint("TOPRIGHT", 0, -y)
                -- My vote is the selected option, as every selection is marked (#371).
                UI:SetSelected(btn, myVote == idx)
                btn.label:ClearAllPoints()
                btn.label:SetPoint("LEFT", 8, 0)
                if not p.closed then
                    local id, oi = p.id, idx
                    btn:SetScript("OnClick", function() if GuildOS.Polls then GuildOS.Polls:Vote(id, oi) end end)
                end
                y = y + 22
            end
            local meta = UI:CreateText(child, string.format(L["%d vote(s) · by %s"], total, p.author or "?"),
                11, C.textSoft.r, C.textSoft.g, C.textSoft.b)
            meta:SetPoint("TOPLEFT", 0, -y)
            y = y + 22
        end
        if #polls == 0 then
            local empty = UI:CreateText(child, L["No polls yet."], 12, C.textSoft.r, C.textSoft.g, C.textSoft.b)
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
-- and the Now cards both build it.
----------------------------------------------------------------------
local CLASS_TEX = "Interface\\WorldStateFrame\\Icons-Classes"
local feeds = 0   -- each feed's scroll frame needs its own global name

-- A channel is { id, name, kind }; nil, and the Guild tab, mean /g.
local function idOf(stream)
    return (stream and stream.kind ~= "guild") and stream.id or nil
end

local function streamLabel(stream)
    if stream.kind == "guild" then return L["Guild"] end
    if stream.kind == "officer" then return L["Officers"] end
    return stream.name or "?"
end

-- `top`: room over the feed. The Guild tab leaves GAP under its sub-tab bar, as on every sub-tab
-- (#371); a Now card gives none.
function GuildOS:CreateGuildChatFeed(panel, top)
    local GC = GuildOS.GuildChat
    local current   -- the channel open; nil is /g
    top = top or 0
    feeds = feeds + 1

    -- The channel tabs, shown only when there is more than /g to choose from.
    local bar = CreateFrame("Frame", nil, panel)
    bar:SetPoint("TOPLEFT", 0, -top)
    bar:SetSize(400, TAB_H)
    UI:StyleSubTabBar(bar)
    bar:Hide()
    local tabs = {}

    local holder = CreateFrame("Frame", nil, panel)
    local function anchorHolder(belowTabs)
        holder:ClearAllPoints()
        if belowTabs then
            holder:SetPoint("TOPLEFT", bar, "BOTTOMLEFT", 0, -4)
        else
            holder:SetPoint("TOPLEFT", 0, -top)
        end
        holder:SetPoint("BOTTOMRIGHT", 0, 32)
    end
    anchorHolder(false)
    local scroll, content = UI:CreateScrollFrame(holder, "GuildOSGuildChatScroll" .. feeds)
    scroll:SetAllPoints()

    local input = UI:CreateInput(panel, 100, FIELD_H)
    input:SetPoint("BOTTOMLEFT", 0, 4)
    input:SetPoint("BOTTOMRIGHT", -70, 4)
    input:SetMaxBytes(241)   -- what Send keeps (240 bytes), plus the terminator
    local sendBtn = UI:CreateButton(panel, L["Send"], 62, FIELD_H)
    sendBtn:SetPoint("BOTTOMRIGHT", 0, 4)

    local empty = UI:CreateText(content, L["No guild chat yet."], 12, C.textSoft.r, C.textSoft.g, C.textSoft.b)
    empty:SetPoint("TOPLEFT", 0, -4)

    local refresh   -- declared for the tab clicks
    -- The newest line is shown on opening and on changing channel; after that the feed follows
    -- new lines only for a reader already at the bottom, never pulling one who scrolled up.
    local pinBottom = true
    local scrolling = false   -- a move to the bottom is queued for the next frame
    local waiting = false     -- a look after a chat lockdown is queued

    -- Another channel: the server stops being told about the old one, and is told about this one.
    local function open(stream)
        -- In a chat lockdown the feed cannot be redrawn: a channel changed then would send Enter
        -- somewhere other than what is on screen, an officer's line to the whole guild.
        if GC:Locked() or idOf(stream) == idOf(current) then return end
        GC:Watch(false, current)
        current = idOf(stream) and stream or nil
        GC:Watch(true, current)
        pinBottom = true
        refresh()
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
            t.label:SetText(streamLabel(s))
            t:SetWidth(math.max(TAB_MIN_W, math.ceil(t.label:GetStringWidth()) + TAB_PAD))
            t:SetActive(idOf(s) == idOf(current))
            t:Show()
            shown[#shown + 1] = t
        end
        for i = #list + 1, #tabs do tabs[i]:Hide() end
        bar:SetWidth(math.max(TAB_MIN_W, panel:GetWidth() or 0))
        UI:FlowBar(bar, shown, { gap = 4, rowGap = 4, rowH = TAB_H })
    end

    -- Pooled: refresh runs on every line of chat, and WoW never frees a frame.
    local blocks = {}
    local function getBlock(i)
        if blocks[i] then return blocks[i] end
        local card = CreateFrame("Frame", nil, content, "BackdropTemplate")
        card:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = GuildOS.UI:Edge(card) })
        -- A link in the line opens as it does in the chat frame.
        card:EnableMouse(true)
        card:SetHyperlinksEnabled(true)
        card:SetScript("OnHyperlinkClick", function(_, link, text, button) SetItemRef(link, text, button) end)
        local icon = card:CreateTexture(nil, "ARTWORK")
        icon:SetSize(20, 20)
        icon:SetPoint("TOPLEFT", 8, -6)
        icon:SetTexture(CLASS_TEX)
        local nameFS = UI:CreateText(card, "", 11, C.text.r, C.text.g, C.text.b)
        nameFS:SetPoint("TOPLEFT", 36, -7)
        local timeFS = UI:CreateText(card, "", 9, C.textDim.r, C.textDim.g, C.textDim.b)
        timeFS:SetPoint("TOPRIGHT", -8, -8)
        local bodyFS = UI:CreateText(card, "", 11, C.text.r, C.text.g, C.text.b)
        bodyFS:SetPoint("TOPLEFT", 36, -22)
        bodyFS:SetJustifyH("LEFT")
        bodyFS:SetWordWrap(true)
        blocks[i] = { card = card, icon = icon, nameFS = nameFS, timeFS = timeFS, bodyFS = bodyFS }
        return blocks[i]
    end

    refresh = function()
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
            return
        end
        local follow = pinBottom or scrolling or scroll:GetVerticalScroll() >= scroll:GetVerticalScrollRange() - 4
        pinBottom = false
        layoutTabs()
        -- Born 0 wide (CreateScrollFrame sizes it before layout), so re-set on every draw.
        content:SetWidth(math.max(holder:GetWidth() - 12, 1))
        local log = GC:Entries(current)
        local classOf = {}
        for _, e in ipairs(log) do classOf[e.n] = e.c or classOf[e.n] end
        local groups = GuildOS.AllianceChat.GroupLog(log, GuildOS.AllianceChat.GROUP_WINDOW)
        local today = date("%Y%m%d", GetServerTime())
        local width = math.max(content:GetWidth() - 12, 200)
        local y = 0
        for i, g in ipairs(groups) do
            local b = getBlock(i)
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
            b.nameFS:SetText(who)
            b.nameFS:SetTextColor(GuildOS:GetClassColor(class))
            -- The log outlives the session: a line from another day says which day.
            local t = tonumber(g.t)
            b.timeFS:SetText(t and GuildOS:LocalDate(date("%Y%m%d", t) == today and "%H:%M" or "%a %H:%M", t) or "")
            b.bodyFS:SetWidth(width - 44)
            b.bodyFS:SetText(table.concat(g.lines, "\n"))
            local h = math.max(34, (b.bodyFS:GetStringHeight() or 12) + 28)
            b.card:SetBackdropColor(C.bg2.r, C.bg2.g, C.bg2.b, 0.55)
            b.card:SetBackdropBorderColor(C.border.r, C.border.g, C.border.b, 0.35)
            b.card:SetPoint("TOPLEFT", 0, -y)
            b.card:SetSize(width, h)
            b.card:Show()
            y = y + h + 3
        end
        for i = #groups + 1, #blocks do blocks[i].card:Hide() end
        empty:SetShown(#groups == 0)
        if #groups == 0 then y = 20 end
        content:SetHeight(math.max(y, 1))
        -- A frame later: the scroll range follows the new height only after it lands.
        if not follow then return end
        local target = math.max(0, y - holder:GetHeight())
        scrolling = true
        GuildOS.Compat.After(0, function()
            scrolling = false
            if panel:IsVisible() then scroll:SetVerticalScroll(target) end
        end)
    end

    -- Enter and the click are the player's own key press, which chat needs on Forever.
    local function doSend()
        local ok, why = GC:Send(input:GetText(), current)
        if ok then
            input:SetText("")
        elseif why == "locked" then
            GuildOS:Print(L["Chat is locked right now: your message is still in the box."])
        end
    end
    sendBtn:SetScript("OnClick", doSend)
    input:SetScript("OnEnterPressed", doSend)

    GC:OnRefresh(function()
        if panel:IsVisible() then refresh() end
    end)
    -- The server is told a channel is being read only while the feed is on screen.
    panel:HookScript("OnShow", function() pinBottom = true; GC:Watch(true, current) end)
    panel:HookScript("OnHide", function() GC:Watch(false, current) end)
    -- The cards are as wide as the view: a resized window lays them out again, once a frame.
    UI:MakeResponsive(holder, function()
        if panel:IsVisible() then refresh() end
    end)
    return refresh
end

----------------------------------------------------------------------
-- EKO patch: ABOUT THE OUTLAWS sub-panel (static guild info, this client only)
----------------------------------------------------------------------
local EKO_GOLD = "|cffe6b84a"
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
    local refresh
    refresh = function()
        clear(child)
        editBtn:SetShown(EKO and EKO.CanEditAbout and EKO:CanEditAbout() or false)
        local sections = ABOUT_SECTIONS
        local stored = EKO and EKO.AboutStored and EKO:AboutStored()
        if stored and type(stored.text) == "string" then
            local parsed = EKO:ParseAbout(stored.text)
            if #parsed > 0 then sections = parsed end
        end
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
                fs:SetPoint("TOPRIGHT", -8, -y)
                fs:SetJustifyH("LEFT")
                fs:SetWordWrap(true)
                y = y + math.max(16, (fs:GetStringHeight() or 14) + 6)
            end
        end
        child:SetHeight(math.max(1, y))
    end
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
            GuildOS:Print(string.format(L["%s could not start on this client. Type /guildos errors for details."], def.label))
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
    parent.SelectSub = selectSub   -- deep links: /guildos calendar, /gos open journal, the Now tab

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

