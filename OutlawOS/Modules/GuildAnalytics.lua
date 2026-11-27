----------------------------------------------------------------------
-- Guild OS - Guild Analytics
-- Composition distributions (class / level / rank / zone) as pure
-- aggregation over the guild roster, shown as bars in a /outlawos analytics window.
----------------------------------------------------------------------
local GuildAnalytics = {}
GuildOS.GuildAnalytics = GuildAnalytics

GuildAnalytics.DIMENSIONS = { "class", "level", "rank", "zone", "prof", "rhour", "rday" }  -- EKO patch: + prof, recruiting

function GuildAnalytics:Initialize()
    self:_RegisterTests()
end

function GuildAnalytics:_LevelBracket(level)
    level = level or 0
    local cap = GuildOS.Client.maxLevel
    if level >= cap then return tostring(cap) end
    local lo = math.floor(level / 10) * 10
    if lo == 0 then return "1-9" end
    return lo .. "-" .. (lo + 9)
end

function GuildAnalytics:BuildRoster()
    local roster = {}
    local n = GetNumGuildMembers() or 0
    for i = 1, n do
        local name, rank, _, level, _, zone, _, _, online, _, classFile = GetGuildRosterInfo(i)
        if name then
            roster[#roster + 1] = { name = name, class = classFile, level = level, rank = rank, zone = zone, online = online }
        end
    end
    return roster
end

-- EKO patch: professions breakdown. One row per profession: how many of the counted members
-- have it (% of those members, so the rows add up past 100%: a member has two), and the average
-- skill of the ones whose GuildOS reported it. Primaries first, then Cooking, Fishing, First Aid.
-- The second value is how many counted members have no profession on record.
function GuildAnalytics:ProfDistribution(onlineOnly, roster, maxOnly)
    roster = roster or self:BuildRoster()
    local P, cat = GuildOS.Professions, GuildOS.ProfCatalog
    local db = GuildOS.db and GuildOS.db.professions
    if not (P and cat and cat.professions and db) then return {}, 0, 0 end
    local cap = maxOnly and GuildOS.Client.maxLevel
    local rows, total, none = {}, 0, 0
    for _, m in ipairs(roster) do
        if ((not onlineOnly) or m.online) and ((not maxOnly) or (m.level or 0) >= cap) then
            total = total + 1
            local key = m.name and P.KeyFor(m.name)
            local rec = key and db[key]
            local any = false
            for line, e in pairs((rec and rec.profs) or {}) do
                local meta = cat.professions[line]
                if meta then
                    any = true
                    local r = rows[line]
                    if not r then
                        r = { label = meta.en or tostring(line), primary = meta.primary, count = 0, skillSum = 0, skillN = 0 }
                        rows[line] = r
                    end
                    r.count = r.count + 1
                    local rank = type(e) == "table" and tonumber(e.rank) or 0
                    if rank and rank > 0 then
                        r.skillSum = r.skillSum + rank
                        r.skillN = r.skillN + 1
                    end
                end
            end
            if not any then none = none + 1 end
        end
    end
    local out = {}
    for _, r in pairs(rows) do
        r.pct = total > 0 and (r.count / total * 100) or 0
        r.avgSkill = r.skillN > 0 and math.floor(r.skillSum / r.skillN + 0.5) or nil
        out[#out + 1] = r
    end
    table.sort(out, function(a, b)
        if a.primary ~= b.primary then return a.primary and true or false end
        if a.count ~= b.count then return a.count > b.count end
        return a.label < b.label
    end)
    return out, total, none
end

-- EKO patch: recruiting by hour of the day / day of the week. Every join in the roster log
-- (GuildOS keeps 90 days), counted at the local hour or weekday it happened. `days`: only the
-- last N days (nil = everything logged). Rows stay in clock / calendar order, zeros included.
local EKO_DAYS = { "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday" }
local function ekoHourLabel(h)
    if h == 0 then return "12 AM" elseif h < 12 then return h .. " AM"
    elseif h == 12 then return "12 PM" else return (h - 12) .. " PM" end
end

function GuildAnalytics:RecruitDistribution(dim, days, events)
    events = events or (GuildOS.db and GuildOS.db.rosterLog and GuildOS.db.rosterLog.events) or {}
    local since = days and (GetServerTime() - days * 86400) or nil
    local n = dim == "rhour" and 24 or 7
    local counts, total = {}, 0
    for i = 1, n do counts[i] = 0 end
    for _, e in ipairs(events) do
        local ts = tonumber(e.timestamp)
        if e.action == "join" and ts and ((not since) or ts >= since) then
            local i
            if dim == "rhour" then
                i = (tonumber(date("%H", ts)) or 0) + 1
            else
                i = ((tonumber(date("%w", ts)) or 0) + 6) % 7 + 1   -- Monday first
            end
            counts[i] = counts[i] + 1
            total = total + 1
        end
    end
    local out, peak = {}, 0
    for i = 1, n do
        if counts[i] > peak then peak = counts[i] end
    end
    for i = 1, n do
        out[i] = {
            label = dim == "rhour" and ekoHourLabel(i - 1) or EKO_DAYS[i],
            count = counts[i],
            pct = total > 0 and (counts[i] / total * 100) or 0,
            fill = peak > 0 and (counts[i] / peak * 100) or 0,   -- bar length: the busiest row is full
            peak = peak > 0 and counts[i] == peak,
        }
    end
    return out, total
end

-- `maxOnly` counts only who is at the game's level cap (issue #137).
function GuildAnalytics:Distribution(dim, onlineOnly, roster, maxOnly)
    roster = roster or self:BuildRoster()
    local cap = maxOnly and GuildOS.Client.maxLevel
    local counts, order, total = {}, {}, 0
    for _, m in ipairs(roster) do
        if ((not onlineOnly) or m.online) and ((not maxOnly) or (m.level or 0) >= cap) then
            local key, colorKey
            if dim == "class" then key = m.class or "?"; colorKey = m.class
            elseif dim == "level" then key = self:_LevelBracket(m.level)
            elseif dim == "rank" then key = m.rank or "?"
            elseif dim == "zone" then key = (m.zone and m.zone ~= "" and m.zone) or "?"
            else key = "?" end
            if not counts[key] then counts[key] = { count = 0, colorKey = colorKey }; order[#order + 1] = key end
            counts[key].count = counts[key].count + 1
            total = total + 1
        end
    end
    local out = {}
    for _, k in ipairs(order) do
        out[#out + 1] = { label = k, count = counts[k].count, colorKey = counts[k].colorKey }
    end
    table.sort(out, function(a, b)
        if a.count ~= b.count then return a.count > b.count end
        return tostring(a.label) < tostring(b.label)
    end)
    for _, e in ipairs(out) do e.pct = total > 0 and (e.count / total * 100) or 0 end
    return out, total
end

-- (Note: for dim=="class", label is the class file token; the UI localizes via
-- LOCALIZED_CLASS_NAMES_MALE and colors via RAID_CLASS_COLORS. Keeping the raw
-- token here keeps Distribution pure and testable.)

----------------------------------------------------------------------
-- UI (self-contained popup — mirrors Modules/Bulletin.lua:Show())
----------------------------------------------------------------------
local BAR_MAX     = 200  -- max pixel width of a fully-filled (100%) bar
local LABEL_WIDTH = 110  -- left column width for the dimension label
local ROW_HEIGHT  = 22

function GuildAnalytics:Show()
    local UI = GuildOS.UI
    local C = GuildOS.Colors
    local L = GuildOS.L

    self._dim = self._dim or "class"
    if self._onlineOnly == nil then self._onlineOnly = false end
    if self._maxOnly == nil then self._maxOnly = false end

    local f = self.frame
    if not f then
        f = CreateFrame("Frame", "GuildOSAnalyticsFrame", UIParent, "BackdropTemplate")
        f:SetSize(840, 600)  -- EKO patch: wider for the extra tabs, taller for 24 hours
        f:SetPoint("CENTER")
        f:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = GuildOS.UI:Edge(f) })
        f:SetBackdropColor(GuildOS.Colors.bg.r, GuildOS.Colors.bg.g, GuildOS.Colors.bg.b, 0.98)
        f:SetBackdropBorderColor(C.border.r, C.border.g, C.border.b, C.border.a)
        UI:StylePopup(f)
        f:SetFrameStrata("HIGH")
        f:SetMovable(true)
        f:EnableMouse(true)
        f:RegisterForDrag("LeftButton")
        f:SetScript("OnDragStart", function(s) s:StartMoving() end)
        f:SetScript("OnDragStop", function(s) s:StopMovingOrSizing() end)

        local title = UI:CreateTitle(f, L["Guild Analytics"], 15)
        title:SetPoint("TOPLEFT", 16, -14)
        local close = UI:CreateCloseButton(f)
        close:SetPoint("TOPRIGHT", -8, -8)
        close:SetScript("OnClick", function() f:Hide() end)

        -- Dimension selector: Class / Levels / Ranks / Zones
        local tabDefs = {
            { dim = "class", label = L["Class"] },
            { dim = "level", label = L["Levels"] },
            { dim = "rank",  label = L["Ranks"] },
            { dim = "zone",  label = L["Zones"] },
            { dim = "prof",  label = L["Professions"] },  -- EKO patch
            { dim = "rhour", label = "Recruiting - Hourly" },  -- EKO patch
            { dim = "rday",  label = "Recruiting - Daily" },   -- EKO patch
        }
        local tabs = {}
        for _, def in ipairs(tabDefs) do
            local tab = UI:CreateTab(f, def.label, 96)
            if tab.label then tab:SetWidth(math.max(80, math.ceil(tab.label:GetStringWidth() or 0) + 24)) end
            tab:SetScript("OnClick", function()
                self._dim = def.dim
                if self.uiRefresh then GuildOS:SafeCall(self.uiRefresh) end
            end)
            tabs[def.dim] = tab
        end
        f.tabs = tabs
        f.tabOrder = tabDefs

        -- Online-only toggle
        local onlineCB = UI:CreateCheckbox(f, L["Online only"], 18)
        onlineCB:SetPoint("TOPLEFT", 16, -78)
        onlineCB.checkbox:SetChecked(self._onlineOnly)
        onlineCB.checkbox.onChanged = function(_, checked)
            self._onlineOnly = checked and true or false
            if self.uiRefresh then GuildOS:SafeCall(self.uiRefresh) end
        end

        -- Max-level-only toggle (issue #137)
        local maxCB = UI:CreateCheckbox(f, L["Max level only"], 18)
        maxCB:SetPoint("TOPLEFT", 236, -78)
        maxCB.checkbox:SetChecked(self._maxOnly)
        maxCB.checkbox.onChanged = function(_, checked)
            self._maxOnly = checked and true or false
            if self.uiRefresh then GuildOS:SafeCall(self.uiRefresh) end
        end
        f.onlineCB, f.maxCB = onlineCB, maxCB

        -- EKO patch: time range for the recruiting tabs (they replace the two checkboxes there)
        self._range = self._range or 0
        local rangeDefs = { { days = 7, label = "Last 7 days" }, { days = 30, label = "Last 30 days" }, { days = 0, label = "All logged" } }
        f.rangeBtns = {}
        local rx = 16
        for _, rd in ipairs(rangeDefs) do
            local b = UI:CreateTab(f, rd.label, 100, true)
            if b.label then b:SetWidth(math.max(80, math.ceil(b.label:GetStringWidth() or 0) + 24)) end
            b:SetPoint("TOPLEFT", rx, -76)
            rx = rx + b:GetWidth() + 6
            b:SetScript("OnClick", function()
                self._range = rd.days
                if self.uiRefresh then GuildOS:SafeCall(self.uiRefresh) end
            end)
            b.days = rd.days
            f.rangeBtns[#f.rangeBtns + 1] = b
        end

        -- Bar list (ScrollFrame gotcha: CreateScrollFrame does NOT anchor the
        -- scroll frame itself — SetAllPoints() here, or content is clipped to 0x0).
        local holder = CreateFrame("Frame", nil, f)
        holder:SetPoint("TOPLEFT", 12, -108)
        holder:SetPoint("BOTTOMRIGHT", -12, 14)
        local scroll, child = UI:CreateScrollFrame(holder, "GuildOSAnalyticsScroll")
        scroll:SetAllPoints()
        f.child = child
        f.holder = holder
        self.frame = f
    end

    local function refresh()
        if not f:IsShown() then return end

        -- At the cap only, the Levels tab would hold one bar: it steps aside and the others close up.
        if self._maxOnly and self._dim == "level" then self._dim = "class" end
        local tabX = 16
        for _, def in ipairs(f.tabOrder) do
            local tab = f.tabs[def.dim]
            local shown = not (self._maxOnly and def.dim == "level")
            tab:SetShown(shown)
            tab:SetActive(def.dim == self._dim)
            if shown then
                tab:ClearAllPoints()
                tab:SetPoint("TOPLEFT", tabX, -42)
                tabX = tabX + tab:GetWidth() + 6  -- a tab its label grew pushes the next one (issue #28)
            end
        end

        -- EKO patch: the recruiting tabs show the range buttons in place of the two checkboxes
        local recruit = self._dim == "rhour" or self._dim == "rday"
        if f.onlineCB then f.onlineCB:SetShown(not recruit) end
        if f.maxCB then f.maxCB:SetShown(not recruit) end
        for _, b in ipairs(f.rangeBtns or {}) do
            b:SetShown(recruit)
            b:SetActive(b.days == (self._range or 0))
        end

        -- Reset ALL row state before repaint (regions and any child frames).
        local child = f.child
        for _, c in pairs({ child:GetChildren() }) do c:Hide() end
        for _, r in pairs({ child:GetRegions() }) do r:Hide() end
        child:SetWidth(f.holder:GetWidth() - 12)

        local entries, profNone, recruitTotal
        if recruit then
            entries, recruitTotal = self:RecruitDistribution(self._dim, (self._range or 0) > 0 and self._range or nil)
        elseif self._dim == "prof" then
            local _
            entries, _, profNone = self:ProfDistribution(self._onlineOnly, nil, self._maxOnly)
        else
            entries = self:Distribution(self._dim, self._onlineOnly, nil, self._maxOnly)
        end
        local y = 0
        local wasPrimary = true
        for _, e in ipairs(entries) do
            local label = e.label
            -- EKO patch: a gap before the secondary professions
            if self._dim == "prof" and wasPrimary and not e.primary then
                if y > 0 then y = y + 8 end
                wasPrimary = false
            end
            if self._dim == "class" then
                label = LOCALIZED_CLASS_NAMES_MALE[e.label] or e.label
            end

            local labelFS = UI:CreateText(child, label, 11, C.text.r, C.text.g, C.text.b)
            labelFS:SetPoint("TOPLEFT", 4, -(y + 4))
            labelFS:SetWidth(LABEL_WIDTH - 8)
            labelFS:SetJustifyH("LEFT")

            local barBG = child:CreateTexture(nil, "BACKGROUND")
            barBG:SetTexture("Interface\\Buttons\\WHITE8x8")
            barBG:SetPoint("TOPLEFT", LABEL_WIDTH, -(y + 3))
            barBG:SetSize(BAR_MAX, ROW_HEIGHT - 6)
            barBG:SetVertexColor(C.bg0.r, C.bg0.g, C.bg0.b, 0.6)

            local bar = child:CreateTexture(nil, "ARTWORK")
            bar:SetTexture("Interface\\Buttons\\WHITE8x8")
            bar:SetPoint("TOPLEFT", LABEL_WIDTH, -(y + 3))
            bar:SetSize(math.max(1, ((e.fill or e.pct) / 100) * BAR_MAX), ROW_HEIGHT - 6)
            if e.peak and C.gold then
                bar:SetVertexColor(C.gold.r, C.gold.g, C.gold.b)   -- EKO patch: the busiest hour / day
            elseif self._dim == "class" and e.colorKey and RAID_CLASS_COLORS[e.colorKey] then
                local cc = RAID_CLASS_COLORS[e.colorKey]
                bar:SetVertexColor(cc.r, cc.g, cc.b)
            else
                bar:SetVertexColor(C.accent.r, C.accent.g, C.accent.b)
            end

            local valueText = e.count .. " (" .. string.format("%.0f%%", e.pct) .. ")"
            if self._dim == "prof" and e.avgSkill then
                valueText = valueText .. "  avg " .. e.avgSkill  -- EKO patch
            end
            local valueFS = UI:CreateText(child, valueText,
                11, C.textDim.r, C.textDim.g, C.textDim.b)
            valueFS:SetPoint("TOPLEFT", LABEL_WIDTH + BAR_MAX + 8, -(y + 4))

            y = y + ROW_HEIGHT
        end

        -- EKO patch: how many joins the recruiting tabs counted
        if recruit then
            local rangeText = (self._range or 0) > 0 and ("in the last " .. self._range .. " days") or "in the log (up to 90 days)"
            local note = UI:CreateText(child, (recruitTotal or 0) .. " joins " .. rangeText .. ". Busiest in gold. Times are your local time.",
                11, C.silver.r, C.silver.g, C.silver.b)
            note:SetPoint("TOPLEFT", 4, -(y + 10))
            y = y + 30
        end

        -- EKO patch: who the professions tab could not count
        if self._dim == "prof" and #entries > 0 and (profNone or 0) > 0 then
            local note = UI:CreateText(child, profNone .. " " .. L["members with no profession on record"],
                11, C.silver.r, C.silver.g, C.silver.b)
            note:SetPoint("TOPLEFT", 4, -(y + 10))
            y = y + 30
        end

        if #entries == 0 then
            local empty = UI:CreateText(child, L["No data."], 11, C.silver.r, C.silver.g, C.silver.b)
            empty:SetPoint("TOPLEFT", 4, -4)
            y = 20
        end

        child:SetHeight(math.max(1, y))
    end

    self.uiRefresh = refresh
    f:SetScript("OnShow", refresh)
    f:Show()
    refresh()
end

function GuildAnalytics:_RegisterTests()
    if not GuildOS.SelfTest then return end
    local S = GuildOS.SelfTest
    S:Register("analytics.class", function()
        local roster = { { class = "MAGE", online = true }, { class = "MAGE", online = false }, { class = "WARRIOR", online = true } }
        local out, total = GuildAnalytics:Distribution("class", false, roster)
        if total ~= 3 then return false, "total" end
        if out[1].label ~= "MAGE" or out[1].count ~= 2 then return false, "top bucket" end
        return true
    end)
    S:Register("analytics.online_filter", function()
        local roster = { { class = "MAGE", online = true }, { class = "MAGE", online = false } }
        local _, total = GuildAnalytics:Distribution("class", true, roster)
        if total ~= 1 then return false, "online-only" end
        return true
    end)
    S:Register("analytics.level_bracket", function()
        local cap = GuildOS.Client.maxLevel
        if GuildAnalytics:_LevelBracket(cap) ~= tostring(cap) then return false, "cap" end
        if GuildAnalytics:_LevelBracket(55) ~= "50-59" then return false, "50-59" end
        if GuildAnalytics:_LevelBracket(5) ~= "1-9" then return false, "1-9" end
        return true
    end)
    S:Register("analytics.prof", function()
        if not (GuildOS.Professions and GuildOS.ProfCatalog) then return true end
        local out = GuildAnalytics:ProfDistribution(false, {})
        if type(out) ~= "table" then return false, "prof" end
        return true
    end)
    S:Register("analytics.recruit", function()
        local now = GetServerTime()
        local ev = { { action = "join", timestamp = now }, { action = "leave", timestamp = now }, { action = "join", timestamp = now - 40 * 86400 } }
        local h, th = GuildAnalytics:RecruitDistribution("rhour", nil, ev)
        local d, td = GuildAnalytics:RecruitDistribution("rday", 30, ev)
        if #h ~= 24 or th ~= 2 then return false, "hourly" end
        if #d ~= 7 or td ~= 1 then return false, "daily" end
        return true
    end)
    S:Register("analytics.pct", function()
        local roster = { { class = "MAGE" }, { class = "MAGE" }, { class = "ROGUE" }, { class = "ROGUE" } }
        local out = GuildAnalytics:Distribution("class", false, roster)
        if math.abs(out[1].pct - 50) > 0.01 then return false, "pct" end
        return true
    end)
end
