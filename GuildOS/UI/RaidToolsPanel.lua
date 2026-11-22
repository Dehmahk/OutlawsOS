----------------------------------------------------------------------
-- Guild OS - Raid Tools Panel
-- "Raid Tools" tab with sub-tabs: Composition (class breakdown + buff
-- coverage) and Cooldowns (key raid CD coverage). Data comes from
-- GuildOS.RaidTools (Rule 3 / Rule 10).
----------------------------------------------------------------------
local UI = GuildOS.UI
local C = GuildOS.Colors
local L = GuildOS.L
local WHITE = "Interface\\Buttons\\WHITE8x8"

local SUBTABS = {
    { key = "comp", label = L["Composition"] },
    { key = "cds",  label = L["Cooldowns"] },
}

local ROW_H = 24
local ICON_DONE = "|TInterface\\RAIDFRAME\\ReadyCheck-Ready:14:14|t"
local ICON_NONE = "|TInterface\\RAIDFRAME\\ReadyCheck-NotReady:14:14|t"
-- The screen's margins (#371): flush with the sub-tab bar's left edge, GAP under it, the content ending
-- GAP short of the right edge. A scroll child stops UI.SCROLL_GUTTER short of its frame, so a scroll
-- frame's right edge sits SCROLL_R from the panel's.
local GAP = UI.GAP
local SCROLL_R = UI.SCROLL_GUTTER - UI.GAP
local HEAD_ABOVE = 20   -- room over a later section title for its rule (UI:CreateSectionTitle)
local HEAD_H = 26       -- a section title's line and the space under it

-- The shared scroll frame (#371), anchored here: its child keeps the frame's width less the gutter.
local function MakeScrollList(panel, name, topInset)
    local scroll, content = UI:CreateScrollFrame(panel, name)
    scroll:SetPoint("TOPLEFT", 0, -(topInset or 0))
    scroll:SetPoint("BOTTOMRIGHT", SCROLL_R, 0)
    UI:BindScrollChildWidth(scroll, content)
    return scroll, content
end

-- A row hung by both top corners: a width read at refresh time is 0 on a hidden tab (#371).
local function MakeRow(content, yOff, index)
    local row = CreateFrame("Frame", nil, content, "BackdropTemplate")
    row:SetHeight(ROW_H)
    row:SetPoint("TOPLEFT", 0, -yOff)
    row:SetPoint("TOPRIGHT", 0, -yOff)
    row:SetBackdrop({ bgFile = WHITE })
    local alt = (index % 2 == 0) and C.row1 or C.row2
    row:SetBackdropColor(alt.r, alt.g, alt.b, alt.a)
    return row
end

-- A section title (#371): the shared one, no band behind it. The list's first has no rule; a later one
-- leaves HEAD_ABOVE over itself for it. Returns the y under it.
local function SectionHeader(content, text, yOff)
    local first = yOff == 0
    if not first then yOff = yOff + HEAD_ABOVE end
    local t = UI:CreateSectionTitle(content, text, first)
    t:SetPoint("TOPLEFT", 0, -yOff)
    return yOff + HEAD_H
end

-- What a refresh drew goes before the next one: the rows, and the titles drawn straight on the content.
local function ClearContent(content)
    for _, child in pairs({ content:GetChildren() }) do child:Hide() end
    for _, region in pairs({ content:GetRegions() }) do region:Hide() end
end

-- Localized class name from the WoW global (LOCALIZED_CLASS_NAMES_MALE),
-- falling back to the class token if unavailable.
local function ClassName(classFile)
    local t = LOCALIZED_CLASS_NAMES_MALE
    return (t and t[classFile]) or classFile
end

local function ProvidersText(providers)
    local parts = {}
    for _, cf in ipairs(providers) do
        local cc = GuildOS.ClassColors[cf] or C.silver
        parts[#parts + 1] = GuildOS:ColorText(ClassName(cf), cc.r, cc.g, cc.b)
    end
    return table.concat(parts, ", ")
end

----------------------------------------------------------------------
-- COMPOSITION sub-panel
----------------------------------------------------------------------
local function BuildCompSub(panel)
    local summary = UI:CreateText(panel, "", 12, C.text.r, C.text.g, C.text.b)
    summary:SetPoint("TOPLEFT", 0, -4)

    local listHolder = CreateFrame("Frame", nil, panel)
    listHolder:SetPoint("TOPLEFT", 0, -(18 + GAP))
    listHolder:SetPoint("BOTTOMRIGHT", 0, 0)
    local _, content = MakeScrollList(listHolder, "GuildOSRaidCompScroll")

    return function()
        ClearContent(content)

        local RT = GuildOS.RaidTools
        local list, label = RT:GetSource()
        local counts = RT:GetClassCounts(list)
        summary:SetText(string.format(L["%s  \226\128\148  %d players"], label, #list))

        local yOff = 0
        yOff = SectionHeader(content, L["CLASS BREAKDOWN"], yOff)

        for _, classFile in ipairs(RT.CLASS_ORDER) do
            local c = counts[classFile] or 0
            if c > 0 then
                local row = MakeRow(content, yOff, yOff / (ROW_H + 2))
                local cc = GuildOS.ClassColors[classFile] or C.silver
                local nameFS = UI:CreateText(row, ClassName(classFile), 11, cc.r, cc.g, cc.b)
                nameFS:SetPoint("LEFT", 8, 0)
                local cntFS = UI:CreateText(row, tostring(c), 11, C.text.r, C.text.g, C.text.b)
                cntFS:SetPoint("LEFT", 150, 0)
                yOff = yOff + ROW_H + 2
            end
        end

        yOff = SectionHeader(content, L["BUFF COVERAGE"], yOff)

        local cov = RT:ResolveCoverage(RT.BUFFS, counts)
        for idx, b in ipairs(cov) do
            local row = MakeRow(content, yOff, idx)
            local icon = UI:CreateText(row, b.covered and ICON_DONE or ICON_NONE, 11, C.text.r, C.text.g, C.text.b)
            icon:SetPoint("LEFT", 8, 0)
            local nameFS = UI:CreateText(row, b.name, 11,
                b.covered and C.text.r or C.label.r, b.covered and C.text.g or C.label.g, b.covered and C.text.b or C.label.b)
            nameFS:SetPoint("LEFT", 34, 0)
            if b.covered then
                local prov = UI:CreateText(row, ProvidersText(b.providers), 11, C.textSoft.r, C.textSoft.g, C.textSoft.b)
                prov:SetPoint("LEFT", 220, 0)
            end
            yOff = yOff + ROW_H + 2
        end

        content:SetHeight(math.max(1, yOff))
    end
end

----------------------------------------------------------------------
-- COOLDOWNS sub-panel
----------------------------------------------------------------------
-- Dead members of the raid, the one dead longest first: who a battle res goes to. The order is when this
-- panel first saw them dead. Who has a res ready is not read on WoW: Forever (its combat log is not read
-- there), so the druids in the raid are counted instead.
local deadSince = {}
local function BattleResQueue(content, yOff)
    yOff = SectionHeader(content, L["BATTLE RES QUEUE"], yOff)
    local dead, druids = {}, 0
    local inRaid = IsInRaid()
    if inRaid then
        for i = 1, GetNumGroupMembers() or 0 do
            local name, _, _, _, _, classFile = GetRaidRosterInfo(i)
            if name then
                local short = name:match("^([^-]+)") or name
                if classFile == "DRUID" then druids = druids + 1 end
                if UnitIsDeadOrGhost("raid" .. i) then
                    deadSince[short] = deadSince[short] or GetTime()
                    dead[#dead + 1] = { name = short, class = classFile or "", at = deadSince[short] }
                end
            end
        end
    end
    -- Those who are up again leave the queue.
    local isDead = {}
    for _, d in ipairs(dead) do isDead[d.name] = true end
    for name in pairs(deadSince) do
        if not isDead[name] then deadSince[name] = nil end
    end
    table.sort(dead, function(a, b)
        if a.at ~= b.at then return a.at < b.at end
        return a.name < b.name
    end)

    local note = inRaid
        and string.format(L["Druids in the raid: %d. Who has a res ready cannot be read on this client."], druids)
        or L["Not in a raid."]
    local t = UI:CreateText(content, note, 11, C.textSoft.r, C.textSoft.g, C.textSoft.b)
    t:SetPoint("TOPLEFT", 0, -yOff)
    yOff = yOff + 20
    if #dead == 0 then
        local none = UI:CreateText(content, L["Nobody is dead right now."], 11, C.text.r, C.text.g, C.text.b)
        none:SetPoint("TOPLEFT", 8, -yOff)
        return yOff + ROW_H + 2
    end
    local now = GetTime()
    for idx, d in ipairs(dead) do
        local row = MakeRow(content, yOff, idx)
        local pos = UI:CreateText(row, tostring(idx), 11, C.text.r, C.text.g, C.text.b)
        pos:SetPoint("LEFT", 8, 0)
        local cc = GuildOS.ClassColors[d.class] or C.silver
        local nameFS = UI:CreateText(row, d.name, 11, cc.r, cc.g, cc.b)
        nameFS:SetPoint("LEFT", 34, 0)
        local since = UI:CreateText(row, string.format(L["dead for %ds"], math.floor(now - d.at)),
            11, C.textSoft.r, C.textSoft.g, C.textSoft.b)
        since:SetPoint("LEFT", 220, 0)
        yOff = yOff + ROW_H + 2
    end
    return yOff
end

-- The queue moves as people fall and get up, so the Cooldowns sub-tab redraws itself while it is shown.
local function KeepLive(panel)
    if panel.liveTicker then return end
    panel.liveTicker = C_Timer.NewTicker(2, function(ticker)
        if not panel:IsVisible() then
            ticker:Cancel()
            panel.liveTicker = nil
            return
        end
        panel:GetParent().RefreshActive()
    end)
end

local function BuildCdSub(panel)
    local summary = UI:CreateText(panel, "", 12, C.text.r, C.text.g, C.text.b)
    summary:SetPoint("TOPLEFT", 0, -4)

    local listHolder = CreateFrame("Frame", nil, panel)
    listHolder:SetPoint("TOPLEFT", 0, -(18 + GAP))
    listHolder:SetPoint("BOTTOMRIGHT", 0, 0)
    local _, content = MakeScrollList(listHolder, "GuildOSRaidCdScroll")

    return function()
        ClearContent(content)

        local RT = GuildOS.RaidTools
        local list, label = RT:GetSource()
        local counts = RT:GetClassCounts(list)
        summary:SetText(string.format(L["%s  \226\128\148  %d players"], label, #list))

        local yOff = 0
        local cov = RT:ResolveCoverage(RT.COOLDOWNS, counts)
        for idx, cd in ipairs(cov) do
            local row = MakeRow(content, yOff, idx)
            local icon = UI:CreateText(row, cd.covered and ICON_DONE or ICON_NONE, 11, C.text.r, C.text.g, C.text.b)
            icon:SetPoint("LEFT", 8, 0)
            local nameFS = UI:CreateText(row, cd.name, 11,
                cd.covered and C.text.r or C.label.r, cd.covered and C.text.g or C.label.g, cd.covered and C.text.b or C.label.b)
            nameFS:SetPoint("LEFT", 34, 0)
            if cd.covered then
                local prov = UI:CreateText(row, ProvidersText(cd.providers), 11, C.textSoft.r, C.textSoft.g, C.textSoft.b)
                prov:SetPoint("LEFT", 220, 0)
            else
                local miss = UI:CreateText(row, L["missing"], 11, C.danger.r, C.danger.g, C.danger.b)
                miss:SetPoint("LEFT", 220, 0)
            end
            yOff = yOff + ROW_H + 2
        end

        yOff = BattleResQueue(content, yOff)
        content:SetHeight(math.max(1, yOff))
        KeepLive(panel)
    end
end

----------------------------------------------------------------------
-- Panel assembly
----------------------------------------------------------------------
function GuildOS:CreateRaidToolsPanel(parent, _mainFrame)
    parent.subPanels = {}
    parent.activeSub = "comp"

    -- Flush with the Raids sub-tab bar's left edge and GAP under it, as every screen (#371).
    local bar = CreateFrame("Frame", nil, parent)
    bar:SetPoint("TOPLEFT", 0, -GAP)
    bar:SetPoint("TOPRIGHT", 0, -GAP)
    bar:SetHeight(28)
    UI:StyleSubTabBar(bar)

    local subTabBtns = {}
    local function selectSub(key)
        parent.activeSub = key
        for k, info in pairs(parent.subPanels) do info.panel:SetShown(k == key) end
        for k, btn in pairs(subTabBtns) do btn:SetActive(k == key) end
        local info = parent.subPanels[key]
        if info and info.refresh then GuildOS:SafeCall(info.refresh) end
    end
    parent.SelectSub = selectSub
    parent.RefreshActive = function()
        local info = parent.subPanels[parent.activeSub]
        if info and info.refresh then GuildOS:SafeCall(info.refresh) end
    end

    local x = 0
    for _, t in ipairs(SUBTABS) do
        local btn = UI:CreateTab(bar, t.label, 130, true)
        btn:SetPoint("LEFT", x, 0)
        btn:SetScript("OnClick", function() selectSub(t.key) end)
        subTabBtns[t.key] = btn
        x = x + btn:GetWidth() + 4  -- a tab its label grew pushes the next one (issue #28)
    end

    -- Manual refresh (group changes don't auto-refresh the panel)
    local refreshBtn = UI:CreateButton(bar, L["Refresh"], 90, 22)
    refreshBtn:SetPoint("RIGHT", 0, 0)
    refreshBtn:SetScript("OnClick", function() parent.RefreshActive() end)

    -- A sub-tab's content: flush with the bar's left edge, its first line GAP under it.
    local function makeSubPanel()
        local p = CreateFrame("Frame", nil, parent)
        p:SetPoint("TOPLEFT", 0, -(GAP + 28 + GAP))
        p:SetPoint("BOTTOMRIGHT", 0, GAP)
        p:Hide()
        return p
    end

    local builders = { comp = BuildCompSub, cds = BuildCdSub }
    for _, t in ipairs(SUBTABS) do
        local p = makeSubPanel()
        parent.subPanels[t.key] = { panel = p, refresh = builders[t.key](p) }
    end

    parent:SetScript("OnShow", function()
        selectSub(parent.activeSub or "comp")
    end)
end
