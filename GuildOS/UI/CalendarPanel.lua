----------------------------------------------------------------------
-- Guild OS - Calendar sub-panel (month grid)
-- Embedded as the first sub-tab of the Guild hub. Month view with event
-- markers; click a day to RSVP to its events. Officers get a "New Event"
-- button plus per-event Edit / Delete, all driven through a shared editor
-- popup (title, date, time, size, description).
-- Backed by GuildOS.Calendar (synced "event" domain).
-- Time basis: the client's date()/time() used consistently (assumes the guild
-- shares one timezone, which is the normal case).
----------------------------------------------------------------------
local UI = GuildOS.UI
local C  = GuildOS.Colors
local L  = GuildOS.L

local function CAL() return GuildOS.Calendar end

local WEEKDAYS = { L["Sun"], L["Mon"], L["Tue"], L["Wed"], L["Thu"], L["Fri"], L["Sat"] }
local ROLES    = { "TANK", "HEALER", "DPS" }
local SIZES    = GuildOS.Client.raidSizes   -- the game's: 10/25/40 on TBC, 10/20/40 on Forever (#92)
local DEFAULT_SIZE = GuildOS.Client.defaultRaidSize

local COLS, ROWS = 7, 6
local CELL_H  = 44
-- The Guild tab's grid (#371): flush with the sub-tab bar's left edge, the first line GAP under the
-- sub-panel's top, the grid ending GAP short of its right edge.
local GAP     = UI.GAP
local NAV_Y   = -GAP
local WD_Y    = NAV_Y - 22 - GAP   -- under the 22px month buttons
local GRID_Y  = WD_Y - 16
local GRID_X  = 0

-- Secondary bits of a line drawn in one string (a size, "(repeats)", a guild): the token's colour,
-- so a palette the style re-points carries them too (#371).
local function tint(text, c) return string.format("|cff%02x%02x%02x%s|r", c.r * 255, c.g * 255, c.b * 255, text) end

-- Date helpers (noon avoids DST edge issues).
local function noon(y, m, d) return time({ year = y, month = m, day = d, hour = 12 }) end
local function daysInMonth(y, m) return date("*t", noon(y, m + 1, 0)).day end
local function firstWeekday(y, m) return date("*t", noon(y, m, 1)).wday end   -- 1=Sun..7=Sat
local function dayKey(y, m, d) return y * 10000 + m * 100 + d end
local function keyOfTs(ts) local t = date("*t", ts); return dayKey(t.year, t.month, t.day) end
local function roleLabel(r)
    if r == "TANK" then return L["Tank"] end
    if r == "HEALER" then return L["Healer"] end
    return L["DPS"]
end

-- Per-category accent colour for grid markers, header tags, and picker pills.
-- Tokens mirror Calendar.KINDS; unknown/legacy kinds fall back to RAID.
local KIND_COLOR = {
    RAID    = { r = 0.86, g = 0.34, b = 0.34 },
    DUNGEON = { r = 0.92, g = 0.66, b = 0.30 },
    PVP     = { r = 0.74, g = 0.48, b = 0.92 },
    FARM    = { r = 0.46, g = 0.78, b = 0.48 },
    SOCIAL  = { r = 0.40, g = 0.68, b = 0.92 },
    OTHER   = { r = 0.70, g = 0.72, b = 0.78 },
}
local function kindColor(k) return KIND_COLOR[k] or KIND_COLOR.RAID end
local function kindLabel(k) return (CAL() and CAL().KindLabel and CAL():KindLabel(k)) or k end

----------------------------------------------------------------------
-- Event editor popup (shared by create + edit).
-- A single lazily-built dialog. :Open(dayKey, event) fills it: pass an
-- event to edit it, or just a dayKey to create a new one on that day.
----------------------------------------------------------------------
local function parseDate(s)
    local y, m, d = tostring(s or ""):match("^(%d%d%d%d)%-(%d%d?)%-(%d%d?)$")
    y, m, d = tonumber(y), tonumber(m), tonumber(d)
    if not y or not m or not d or m < 1 or m > 12 or d < 1 or d > 31 then return nil end
    return y, m, d
end

local function parseTime(s)
    local hh, mm = tostring(s or ""):match("^(%d%d?):(%d%d)$")
    hh, mm = tonumber(hh), tonumber(mm)
    if not hh or not mm or hh > 23 or mm > 59 then return nil end
    return hh, mm
end

-- The colours an event may take (its Color), in the order the editor's swatches show them.
local PALETTE = {
    { key = "RED",    r = 0.86, g = 0.34, b = 0.34 },
    { key = "ORANGE", r = 0.92, g = 0.56, b = 0.22 },
    { key = "GOLD",   r = 0.95, g = 0.85, b = 0.40 },
    { key = "GREEN",  r = 0.46, g = 0.78, b = 0.48 },
    { key = "BLUE",   r = 0.40, g = 0.68, b = 0.92 },
    { key = "PURPLE", r = 0.74, g = 0.48, b = 0.92 },
}
local PALETTE_BY_KEY = {}
for _, p in ipairs(PALETTE) do PALETTE_BY_KEY[p.key] = p end

-- The colour an event is drawn in: its own pick, else its kind's.
local function eventColor(e)
    return (e.color and PALETTE_BY_KEY[e.color]) or kindColor(e.kind)
end

local editor   -- lazily-built singleton

-- The cycle buttons' rows. An event's value that is not one of them (one set from another client)
-- joins the row as "Custom", so it reads true and survives a save.
local CLOSE_OPTIONS = {   -- sign-ups close this many seconds before the start; nil stays open
    { lead = nil,   label = L["Stay open"] },
    { lead = 3600,  label = L["Close 1 hr before"] },
    { lead = 86400, label = L["Close 1 day before"] },
    { lead = 0,     label = L["Close at start"] },
}
local REMIND_OPTIONS = {  -- the reminder a member gets when signed up, seconds before the start
    { lead = nil,   label = L["No reminder"] },
    { lead = 900,   label = L["15 min before"] },
    { lead = 3600,  label = L["1 hour before"] },
    { lead = 86400, label = L["1 day before"] },
}
local function optionsWith(opts, value)
    local list, idx = {}, nil
    for i, o in ipairs(opts) do
        list[i] = o
        if o.lead == value then idx = i end
    end
    if not idx then
        list[#list + 1] = { lead = value, label = L["Custom"] }
        idx = #list
    end
    return list, idx
end

local function buildEditor()
    local f = CreateFrame("Frame", "GuildOSEventEditor", UIParent, "BackdropTemplate")
    f:SetSize(652, 470)
    f:SetPoint("CENTER")
    f:SetFrameStrata("DIALOG")
    f:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = GuildOS.UI:Edge(f) })
    f:SetBackdropColor(0.058, 0.058, 0.075, 0.98)
    f:SetBackdropBorderColor(C.border.r, C.border.g, C.border.b, C.border.a)
    UI:StylePopup(f)
    f:SetMovable(true); f:EnableMouse(true); f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", function(self) self:StartMoving() end)
    f:SetScript("OnDragStop",  function(self) self:StopMovingOrSizing() end)
    tinsert(UISpecialFrames, "GuildOSEventEditor")

    local titleFS = UI:CreateTitle(f, "", 14)
    titleFS:SetPoint("TOPLEFT", 14, -12)
    local close = UI:CreateCloseButton(f)
    close:SetPoint("TOPRIGHT", -6, -6)
    close:SetScript("OnClick", function() f:Hide() end)

    -- A labelled field (single- or multi-line): the shared field under a form label (#371).
    local function fieldBox(x, y, w, labelText, multiline, maxLetters, h)
        local lbl = UI:CreateText(f, labelText, 11)
        lbl:SetPoint("TOPLEFT", x, y)
        local box = UI:CreateInput(f, w, h or (multiline and 84 or 22), { multiline = multiline, max = maxLetters })
        box:SetPoint("TOPLEFT", x, y - 14)
        return box
    end

    -- The preview card's refresh: the fields call it as they change; it is defined below.
    local refreshPreview

    ------------------------------------------------------------------
    -- Left column: when, what, where, who, and its colour.
    ------------------------------------------------------------------
    local dateBox = fieldBox(14,  -42, 118, L["Date (YYYY-MM-DD)"], false, 10)
    local timeBox = fieldBox(140, -42, 66,  L["Time (HH:MM)"],      false, 5)
    local sizeLbl = UI:CreateText(f, L["Size"], 11)
    sizeLbl:SetPoint("TOPLEFT", 216, -42)
    local sizeBtn = UI:CreateButton(f, tostring(DEFAULT_SIZE), 44, 22)
    sizeBtn:SetPoint("TOPLEFT", 216, -56)
    sizeBtn.sizeVal = DEFAULT_SIZE
    sizeBtn:SetScript("OnClick", function()
        local idx = 1
        local sizes = CAL().SizesFor(f.kind, SIZES)   -- a dungeon is five (issue #283)
        for i, v in ipairs(sizes) do if v == sizeBtn.sizeVal then idx = i break end end
        sizeBtn.sizeVal = sizes[(idx % #sizes) + 1]
        sizeBtn.label:SetText(tostring(sizeBtn.sizeVal))
        refreshPreview()
    end)

    -- Category picker: one button per kind, the chosen one marked as every selection is (#371).
    -- f.kind holds the current selection.
    local kindLbl = UI:CreateText(f, L["Type"], 11)
    kindLbl:SetPoint("TOPLEFT", 14, -84)
    local kindPills = {}
    local refreshDungeon   -- the dungeon picker beside the title (#308), built with the title below
    local function refreshKinds()
        for _, p in ipairs(kindPills) do
            -- A kind this rank may not create (#308) stays in its place, dimmed and not clickable.
            if CAL():MayCreateKind(p.kind) then p:Enable() else p:Disable() end
            UI:SetSelected(p, p.kind == f.kind)
        end
        if refreshDungeon then refreshDungeon() end
    end
    do
        local kinds = (CAL() and CAL().KINDS) or { "RAID", "DUNGEON", "PVP", "FARM", "SOCIAL", "OTHER" }
        for i, k in ipairs(kinds) do
            -- Six fixed 52px places: a long translation is shortened to fit rather than pushing the row past the edge.
            local p = UI:CreateButton(f, "", 52, 20)
            GuildOS:ApplyFont(p.label, 11, "button")
            p:SetPoint("TOPLEFT", 14 + (i - 1) * 55, -98)
            -- Shortened by hand: UI:SetChipText would add a removable chip's "x" to a kind.
            local text = kindLabel(k)
            local chars = select(2, text:gsub("[^\128-\191]", ""))   -- UTF-8 characters, not bytes
            p.label:SetText(text)
            while p.label:GetStringWidth() > 44 and chars > 2 do
                chars = chars - 1
                p.label:SetText(GuildOS:Utf8Head(text, chars) .. "..")
            end
            p:SetWidth(52)   -- back from the growth the label asked for
            p.fs = p.label   -- the pill's label, under the name it always had
            p.kind = k
            p:SetScript("OnClick", function()
                f.kind = k; refreshKinds()
                -- A size the new kind does not offer moves to one it does: a dungeon's five, or back to the raid default.
                local sizes = CAL().SizesFor(k, SIZES)
                local fits = false
                for _, v in ipairs(sizes) do if v == sizeBtn.sizeVal then fits = true end end
                if not fits then
                    sizeBtn.sizeVal = (k == "DUNGEON") and sizes[1] or DEFAULT_SIZE
                    sizeBtn.label:SetText(tostring(sizeBtn.sizeVal))
                end
                refreshPreview()
            end)
            kindPills[#kindPills + 1] = p
        end
    end
    refreshKinds()

    local titleBox = fieldBox(14, -128, 332, L["Title"], false, 60)

    -- A Dungeon event picks its dungeon from the game's list (#308), the one guildos.me offers, or
    -- "Other" and types it: the pick is the title. The list opens beside the editor.
    local dungeonBtn = UI:CreateButton(f, L["Pick a dungeon"], 104, 22)
    dungeonBtn:SetPoint("TOPLEFT", 242, -142)
    local dungeonList
    local function hideDungeonList() if dungeonList then dungeonList:Hide() end end
    local function pickDungeon(name)
        if name then
            titleBox:SetText(name)
        else
            -- Other: a name the list put there gives way to the one typed.
            for _, n in ipairs(CAL():DungeonChoices()) do
                if strtrim(titleBox:GetText() or "") == n then titleBox:SetText("") end
            end
            titleBox:SetFocus()
        end
        hideDungeonList()
    end
    local function buildDungeonList()
        local list = CreateFrame("Frame", nil, f, "BackdropTemplate")
        list:SetFrameStrata("DIALOG")
        list:SetFrameLevel(f:GetFrameLevel() + 10)
        list:SetPoint("TOPLEFT", f, "TOPRIGHT", 4, 0)
        list:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = GuildOS.UI:Edge(list) })
        list:SetBackdropColor(0.058, 0.058, 0.075, 0.98)
        list:SetBackdropBorderColor(C.border.r, C.border.g, C.border.b, C.border.a)
        local choices = CAL():DungeonChoices()
        for i, name in ipairs(choices) do
            local b = UI:CreateButton(list, name, 196, 20)
            b:SetPoint("TOPLEFT", 6, -6 - (i - 1) * 22)
            b:SetScript("OnClick", function() pickDungeon(name) end)
        end
        local other = UI:CreateButton(list, L["Other (type a name)"], 196, 20)
        other:SetPoint("TOPLEFT", 6, -6 - #choices * 22)
        other:SetScript("OnClick", function() pickDungeon(nil) end)
        list:SetSize(208, 12 + (#choices + 1) * 22)
        list:Hide()
        return list
    end
    dungeonBtn:SetScript("OnClick", function()
        dungeonList = dungeonList or buildDungeonList()
        dungeonList:SetShown(not dungeonList:IsShown())
    end)
    -- Only for a dungeon, and only where the game has a list (WoW: Forever); the title makes room.
    refreshDungeon = function()
        local show = f.kind == "DUNGEON" and #CAL():DungeonChoices() > 0
        dungeonBtn:SetShown(show)
        titleBox:SetWidth(show and 222 or 332)
        if not show then hideDungeonList() end
    end

    local locBox  = fieldBox(14, -172, 332, L["Location"], false, 48)
    local descBox = fieldBox(14, -216, 332, L["Description (optional)"], true, 500, 56)
    local leadBox = fieldBox(14,  -296, 162, L["Lead"],    false, 32)
    local coBox   = fieldBox(184, -296, 162, L["Co-host"], false, 32)

    -- Colour: a default that follows the kind, or one of six. The chosen swatch is outlined in gold.
    local colorLbl = UI:CreateText(f, L["Color"], 11)
    colorLbl:SetPoint("TOPLEFT", 14, -344)
    local SWATCHES = {
        { key = nil, r = 0.45, g = 0.46, b = 0.50 },   -- follows the kind
        { key = "RED",    r = 0.86, g = 0.34, b = 0.34 },
        { key = "ORANGE", r = 0.92, g = 0.56, b = 0.22 },
        { key = "GOLD",   r = 0.95, g = 0.85, b = 0.40 },
        { key = "GREEN",  r = 0.46, g = 0.78, b = 0.48 },
        { key = "BLUE",   r = 0.40, g = 0.68, b = 0.92 },
        { key = "PURPLE", r = 0.74, g = 0.48, b = 0.92 },
    }
    local swatches = {}
    local function refreshSwatches()
        for _, s in ipairs(swatches) do
            local on = (s.key or false) == (f.colorKey or false)
            local edge = on and C.gold or C.line
            s:SetBackdropBorderColor(edge.r, edge.g, edge.b, 1)
        end
    end
    for i, sw in ipairs(SWATCHES) do
        local s = CreateFrame("Button", nil, f, "BackdropTemplate")
        s:SetSize(18, 18)
        s:SetPoint("TOPLEFT", 14 + (i - 1) * 24, -358)
        s:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = GuildOS.UI:Edge(s) })
        s:SetBackdropColor(sw.r, sw.g, sw.b, 1)
        s.key = sw.key
        s:SetScript("OnClick", function()
            f.colorKey = s.key
            refreshSwatches(); refreshPreview()
        end)
        swatches[i] = s
    end

    ------------------------------------------------------------------
    -- Right column: when it repeats, who may come, and what it asks of them.
    ------------------------------------------------------------------
    -- Quick times (UI only): the usual start hours, one click each; the one the time box holds is lit.
    local QUICK = { "18:00", "19:00", "20:00", "21:00", "22:00" }
    local quickLbl = UI:CreateText(f, L["Quick times"], 11)
    quickLbl:SetPoint("TOPLEFT", 368, -42)
    local quickBtns = {}
    for i, t in ipairs(QUICK) do
        local b = UI:CreateButton(f, t, 50, 22)
        b:SetPoint("TOPLEFT", 368 + (i - 1) * 54, -56)
        b.time = t
        b:SetScript("OnClick", function() timeBox:SetText(t) end)
        quickBtns[i] = b
    end
    local function refreshQuick()
        local now = strtrim(timeBox:GetText() or "")
        for _, b in ipairs(quickBtns) do UI:SetSelected(b, b.time == now) end
    end

    -- Repeating (#267). A new event cycles through the repeats its date allows; an event of a series
    -- offers to change every later date instead.
    local repLbl = UI:CreateText(f, L["Repeat"], 11)
    repLbl:SetPoint("TOPLEFT", 368, -88)
    local repBtn = UI:CreateButton(f, "", 270, 22)
    repBtn:SetPoint("TOPLEFT", 368, -102)
    local laterCb = UI:CreateCheckbox(f, L["Change every later date in this series"], 18)
    laterCb:SetPoint("TOPLEFT", 368, -102)
    local REPEATS = (CAL() and CAL().REPEATS) or { "none" }
    f.rep = "none"
    local function repDate()
        local y, m, d = parseDate(dateBox:GetText())
        return y and noon(y, m, d) or nil
    end
    local function repLabel(rep)
        local ts = repDate()
        local r = (ts and CAL() and CAL().RepeatOf) and CAL().RepeatOf(rep, ts) or { wday = 1, nth = 1, day = 1 }
        if rep == "weekly" then return string.format(L["Every week on %s"], WEEKDAYS[r.wday]) end
        if rep == "biweekly" then return string.format(L["Every 2 weeks on %s"], WEEKDAYS[r.wday]) end
        if rep == "daily" then return L["Every day"] end
        if rep == "everyother" then return L["Every other day"] end
        if rep == "monthnth" then return string.format(L["Every month, %s"], WEEKDAYS[r.wday] .. " #" .. r.nth) end
        if rep == "monthday" then return string.format(L["Every month on day %d"], r.day) end
        if rep == "yearly" then return string.format(L["Every year on %s"], ts and (GuildOS:LocalDate("%d %b", ts):gsub("^0", "")) or "") end
        return L["Does not repeat"]
    end
    local function refreshRep() repBtn.label:SetText(repLabel(f.rep)) end
    repBtn:SetScript("OnClick", function()
        local idx = 1
        for i, v in ipairs(REPEATS) do if v == f.rep then idx = i break end end
        f.rep = REPEATS[(idx % #REPEATS) + 1]
        refreshRep()
        refreshPreview()
    end)
    dateBox:HookScript("OnTextChanged", refreshRep)

    -- Alliance sharing. The whole block only exists while this guild is in a pact: with no alliance
    -- there is nothing to share with, and an unexplained checkbox is worse than no checkbox.
    local shareCb = UI:CreateCheckbox(f, L["Share with the alliance"], 18)
    shareCb:SetPoint("TOPLEFT", 368, -132)
    local shareHint = UI:CreateText(f,
        L["Allied guilds see this event and can request a slot. Unchecked, it stays in the guild."],
        9, C.textDim.r, C.textDim.g, C.textDim.b)
    shareHint:SetPoint("TOPLEFT", 388, -150)
    shareHint:SetWidth(250)
    shareHint:SetJustifyH("LEFT")
    shareHint:SetWordWrap(true)

    -- Minimum level, and the spots each role has (blank: open).
    local levelBox = fieldBox(368, -172, 64, L["Min level"], false, 2)
    local tankBox  = fieldBox(446, -172, 52, L["Tank"],     false, 2)
    local healBox  = fieldBox(506, -172, 56, L["Healer"],   false, 2)
    local dpsBox   = fieldBox(576, -172, 50, L["DPS"],      false, 2)

    -- Sign-ups close and the reminder: each a cycle button over its options.
    local closeLbl = UI:CreateText(f, L["Sign-ups"], 11)
    closeLbl:SetPoint("TOPLEFT", 368, -218)
    local closeBtn = UI:CreateButton(f, "", 130, 22)
    closeBtn:SetPoint("TOPLEFT", 368, -232)
    local remindLbl = UI:CreateText(f, L["Reminder"], 11)
    remindLbl:SetPoint("TOPLEFT", 508, -218)
    local remindBtn = UI:CreateButton(f, "", 130, 22)
    remindBtn:SetPoint("TOPLEFT", 508, -232)
    f.closeOpts, f.closeIdx = CLOSE_OPTIONS, 1
    f.remindOpts, f.remindIdx = REMIND_OPTIONS, 1
    local function refreshCycles()
        closeBtn.label:SetText(f.closeOpts[f.closeIdx].label)
        remindBtn.label:SetText(f.remindOpts[f.remindIdx].label)
    end
    closeBtn:SetScript("OnClick", function()
        f.closeIdx = (f.closeIdx % #f.closeOpts) + 1
        refreshCycles(); refreshPreview()
    end)
    remindBtn:SetScript("OnClick", function()
        f.remindIdx = (f.remindIdx % #f.remindOpts) + 1
        refreshCycles(); refreshPreview()
    end)

    -- The preview card (UI only): what the event will read as, kept up as the form changes.
    local card = CreateFrame("Frame", nil, f, "BackdropTemplate")
    card:SetPoint("TOPLEFT", 368, -266)
    card:SetSize(270, 82)
    card:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = GuildOS.UI:Edge(card) })
    card:SetBackdropColor(0.09, 0.09, 0.11, 1)
    card:SetBackdropBorderColor(C.border.r, C.border.g, C.border.b, C.border.a)
    local cardBar = card:CreateTexture(nil, "ARTWORK")
    cardBar:SetTexture("Interface\\Buttons\\WHITE8x8")
    cardBar:SetPoint("TOPLEFT", 0, 0)
    cardBar:SetPoint("BOTTOMLEFT", 0, 0)
    cardBar:SetWidth(3)
    local function cardLine(y, size, dim)
        local fs = dim and UI:CreateText(card, "", size, C.textDim.r, C.textDim.g, C.textDim.b)
            or UI:CreateText(card, "", size)
        fs:SetPoint("TOPLEFT", 12, y)
        fs:SetWidth(246)
        fs:SetJustifyH("LEFT")
        fs:SetWordWrap(false)
        return fs
    end
    local cardHead  = cardLine(-8, 9, true)
    cardHead:SetText(L["Preview"])
    local cardTitle = cardLine(-22, 12)
    local cardMeta  = cardLine(-40, 10, true)
    local cardExtra = cardLine(-54, 10, true)
    local cardZone  = cardLine(-68, 9, true)

    -- Overlaps with the guild's own events, named before the event is made (it is still made).
    local conflictFS = UI:CreateText(f, "", 10, C.danger.r, C.danger.g, C.danger.b)
    conflictFS:SetPoint("TOPLEFT", 368, -356)
    conflictFS:SetWidth(270)
    conflictFS:SetJustifyH("LEFT")
    conflictFS:SetWordWrap(true)

    -- The clock the times are read on: the member's own offset from UTC.
    local function zoneText()
        local now = time()
        local off = now - time(date("!*t", now))
        local sign = off < 0 and "-" or "+"
        off = math.abs(off)
        return string.format(L["Your clock: UTC%s%02d:%02d"], sign, math.floor(off / 3600), math.floor((off % 3600) / 60))
    end

    ------------------------------------------------------------------
    -- Reading and writing the extra fields.
    ------------------------------------------------------------------
    local function extraForm()
        return {
            level = tonumber(levelBox:GetText()),
            location = locBox:GetText(),
            lead = leadBox:GetText(),
            coHost = coBox:GetText(),
            slots = { TANK = tonumber(tankBox:GetText()), HEALER = tonumber(healBox:GetText()), DPS = tonumber(dpsBox:GetText()) },
            color = f.colorKey,
            closeLead = f.closeOpts[f.closeIdx].lead,
            remind = f.remindOpts[f.remindIdx].lead,
        }
    end

    local function setExtraForm(x)
        levelBox:SetText(x.level and tostring(x.level) or "")
        locBox:SetText(x.location or "")
        leadBox:SetText(x.lead or "")
        coBox:SetText(x.coHost or "")
        local s = x.slots or {}
        tankBox:SetText(s.TANK and tostring(s.TANK) or "")
        healBox:SetText(s.HEALER and tostring(s.HEALER) or "")
        dpsBox:SetText(s.DPS and tostring(s.DPS) or "")
        f.colorKey = x.color
        f.closeOpts, f.closeIdx = optionsWith(CLOSE_OPTIONS, x.closeLead)
        f.remindOpts, f.remindIdx = optionsWith(REMIND_OPTIONS, x.remind)
        refreshSwatches(); refreshCycles()
    end

    function refreshPreview()
        local title = strtrim(titleBox:GetText() or "")
        cardTitle:SetText(title ~= "" and title or tint(L["Untitled event"], C.textDim))
        local p = (f.colorKey and PALETTE_BY_KEY[f.colorKey]) or KIND_COLOR[f.kind] or KIND_COLOR.RAID
        cardBar:SetVertexColor(p.r, p.g, p.b, 1)

        local y, m, d = parseDate(dateBox:GetText())
        local hh, mm = parseTime(timeBox:GetText())
        local ts = (y and hh) and time({ year = y, month = m, day = d, hour = hh, min = mm }) or nil
        local meta = {}
        meta[#meta + 1] = ts and (GuildOS:LocalDate("%a %d %b", ts) .. string.format(" %02d:%02d", hh, mm)) or L["Enter a date and time"]
        meta[#meta + 1] = kindLabel(f.kind)
        meta[#meta + 1] = tostring(sizeBtn.sizeVal)
        if f.rep and f.rep ~= "none" and not f.editId then meta[#meta + 1] = repLabel(f.rep) end
        cardMeta:SetText(table.concat(meta, " - "))

        local bits = {}
        local loc = strtrim(locBox:GetText() or "")
        if loc ~= "" then bits[#bits + 1] = loc end
        local lead = strtrim(leadBox:GetText() or "")
        if lead ~= "" then bits[#bits + 1] = L["Lead: "] .. lead end
        local co = strtrim(coBox:GetText() or "")
        if co ~= "" then bits[#bits + 1] = L["Co-host: "] .. co end
        local lvl = tonumber(levelBox:GetText())
        if lvl then bits[#bits + 1] = string.format(L["Level %d+"], lvl) end
        cardExtra:SetText(table.concat(bits, "  -  "))
        cardZone:SetText(zoneText())

        local clash = ts and CAL():ConflictsFor(ts, f.editId) or {}
        if #clash > 0 then
            local parts = {}
            for i, o in ipairs(clash) do
                if i <= 3 then parts[#parts + 1] = (o.title or "?") .. " " .. date("%H:%M", o.when) end
            end
            conflictFS:SetText(L["Overlaps: "] .. table.concat(parts, ", "))
        else
            conflictFS:SetText("")
        end
    end

    titleBox:HookScript("OnTextChanged", function() refreshPreview() end)
    dateBox:HookScript("OnTextChanged", function() refreshPreview() end)
    timeBox:HookScript("OnTextChanged", function() refreshPreview(); refreshQuick() end)
    for _, b in ipairs({ locBox, descBox, leadBox, coBox, levelBox, tankBox, healBox, dpsBox }) do
        b:HookScript("OnTextChanged", function() refreshPreview() end)
    end

    ------------------------------------------------------------------
    -- Footer: the save and close buttons, the templates, and the note on where the event lives.
    ------------------------------------------------------------------
    local saveBtn = UI:CreateButton(f, L["Create"], 110, 24)
    saveBtn:SetPoint("BOTTOMLEFT", 14, 14)
    local cancelBtn = UI:CreateButton(f, L["Cancel"], 80, 24)
    cancelBtn:SetPoint("LEFT", saveBtn, "RIGHT", 8, 0)
    local loadBtn = UI:CreateButton(f, L["Load template"], 130, 24)
    loadBtn:SetPoint("LEFT", cancelBtn, "RIGHT", 8, 0)
    local tplBtn = UI:CreateButton(f, L["Save as template"], 150, 24)
    tplBtn:SetPoint("LEFT", loadBtn, "RIGHT", 8, 0)
    cancelBtn:SetScript("OnClick", function() f:Hide() end)

    -- An event made here never becomes a raid on the site or a Discord post (spec 075 in guildos-web):
    -- said where it is made, since "the bot didn't post my dungeon" is the question it answers.
    local gameOnly = UI:CreateText(f, L["Events made here stay in the game. For signups on Discord, create the raid on guildos.me or with /raid create."], 9, C.textDim.r, C.textDim.g, C.textDim.b)
    gameOnly:SetPoint("BOTTOMLEFT", saveBtn, "TOPLEFT", 0, 6)
    gameOnly:SetWidth(624)
    gameOnly:SetJustifyH("LEFT")
    gameOnly:SetWordWrap(true)

    -- Templates: the list opens above its button. Picking a name fills the form (not the date);
    -- the x removes it.
    local tplList
    local function hideTplList() if tplList then tplList:Hide() end end
    local function loadTemplate(name)
        local t = CAL():Templates()[name]
        if not t then return end
        titleBox:SetText(name)
        descBox:SetText(t.note or "")
        f.kind = t.kind or f.kind
        refreshKinds()
        if t.size then
            sizeBtn.sizeVal = t.size
            sizeBtn.label:SetText(tostring(t.size))
        end
        setExtraForm(t.extra or {})
        refreshPreview()
    end
    loadBtn:SetScript("OnClick", function()
        if tplList and tplList:IsShown() then tplList:Hide(); return end
        local names = {}
        for n in pairs(CAL():Templates()) do names[#names + 1] = n end
        table.sort(names)
        if #names == 0 then
            GuildOS:Print(L["No templates yet. Fill in an event and use Save as template."])
            return
        end
        hideTplList()
        tplList = CreateFrame("Frame", nil, f, "BackdropTemplate")
        tplList:SetFrameStrata("DIALOG")
        tplList:SetFrameLevel(f:GetFrameLevel() + 10)
        tplList:SetPoint("BOTTOMLEFT", loadBtn, "TOPLEFT", 0, 4)
        tplList:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = GuildOS.UI:Edge(tplList) })
        tplList:SetBackdropColor(0.058, 0.058, 0.075, 0.98)
        tplList:SetBackdropBorderColor(C.border.r, C.border.g, C.border.b, C.border.a)
        for i, name in ipairs(names) do
            local b = UI:CreateButton(tplList, name, 180, 20)
            b:SetPoint("TOPLEFT", 6, -6 - (i - 1) * 22)
            b:SetScript("OnClick", function() loadTemplate(name); tplList:Hide() end)
            local x = UI:CreateButton(tplList, "x", 22, 20)
            x:SetPoint("LEFT", b, "RIGHT", 4, 0)
            x:SetScript("OnClick", function()
                CAL():DeleteTemplate(name)
                tplList:Hide()
                GuildOS:Print(string.format(L["Deleted template \"%s\"."], name))
            end)
        end
        tplList:SetSize(214, 12 + #names * 22)
        tplList:Show()
    end)
    tplBtn:SetScript("OnClick", function()
        local name = strtrim(titleBox:GetText() or "")
        if name == "" then
            GuildOS:Print(L["Give the event a title to save it as a template."])
            return
        end
        if CAL():SaveTemplate(name, { kind = f.kind, size = sizeBtn.sizeVal, note = descBox:GetText() or "", extra = extraForm() }) then
            GuildOS:Print(string.format(L["Saved template \"%s\"."], name))
        end
    end)

    ------------------------------------------------------------------
    -- Save: create, edit, or make a series from the form.
    ------------------------------------------------------------------
    local function commit()
        local y, m, d = parseDate(dateBox:GetText())
        if not y then GuildOS:Print(L["Enter a date as YYYY-MM-DD."]); return end
        local hh, mm = parseTime(timeBox:GetText())
        if not hh then GuildOS:Print(L["Enter a time as HH:MM."]); return end
        local title = strtrim(titleBox:GetText() or "")
        if title == "" then GuildOS:Print(L["An event needs a title and a date/time."]); return end
        local when = time({ year = y, month = m, day = d, hour = hh, min = mm })
        local inAlliance = GuildOS.Alliance and GuildOS.Alliance:Get() ~= nil
        local share = inAlliance and shareCb.checkbox:GetChecked() or nil
        local x = extraForm()
        if f.editId and f.inSeries and laterCb.checkbox:GetChecked() then
            CAL():UpdateSeries(f.editId, title, when, sizeBtn.sizeVal, descBox:GetText() or "", f.kind, share, x)
        elseif f.editId then
            CAL():Update(f.editId, title, when, sizeBtn.sizeVal, descBox:GetText() or "", f.kind, share, x)
        elseif f.rep ~= "none" then
            CAL():CreateSeries(title, when, sizeBtn.sizeVal, descBox:GetText() or "", f.kind, share and true or false, f.rep, x)
        else
            CAL():Create(title, when, sizeBtn.sizeVal, descBox:GetText() or "", f.kind, share and true or false, x)
        end
        f:Hide()
    end
    saveBtn:SetScript("OnClick", commit)
    dateBox:SetScript("OnEnterPressed", commit)
    timeBox:SetScript("OnEnterPressed", commit)
    titleBox:SetScript("OnEnterPressed", commit)

    -- Opens the editor. An event edits it; `asCopy` makes a new event from it (a duplicate, whose date
    -- the form still shows, to be changed before it is made).
    function f:Open(dk, event, asCopy)
        local editing = event and not asCopy or false
        f.editId = editing and event.id or nil
        titleFS:SetText(editing and L["Edit Event"] or L["New Event"])
        saveBtn.label:SetText(editing and L["Save"] or L["Create"])
        -- A new event starts on a kind this rank creates (#308): a raid, else the first one open.
        local first = CAL():MayCreateKind("RAID") and "RAID" or CAL():CreatableKinds()[1] or "RAID"
        f.kind = (event and event.kind and KIND_COLOR[event.kind]) and event.kind or first
        hideDungeonList(); hideTplList()
        refreshKinds()
        local y, m, d, hh, mm, size, title, note
        if event then
            local t = date("*t", event.when)
            y, m, d, hh, mm = t.year, t.month, t.day, t.hour, t.min
            size, title, note = event.size or DEFAULT_SIZE, event.title or "", event.note or ""
        else
            y = math.floor(dk / 10000); m = math.floor((dk % 10000) / 100); d = dk % 100
            hh, mm, size, title, note = 20, 0, CAL().SizesFor(f.kind, { DEFAULT_SIZE })[1], "", ""
        end
        local inAlliance = GuildOS.Alliance and GuildOS.Alliance:Get() ~= nil
        shareCb:SetShown(inAlliance)
        shareHint:SetShown(inAlliance)
        -- New: pick a repeat. An event of a series: change only it, or every later date too.
        f.inSeries = editing and type(event.series) == "table" or false
        f.rep = "none"
        repLbl:SetShown(not editing)
        repBtn:SetShown(not editing)
        laterCb:SetShown(f.inSeries)
        laterCb.checkbox:SetChecked(false)
        shareCb.checkbox:SetChecked((event and event.shareAlliance) and true or false)

        dateBox:SetText(string.format("%04d-%02d-%02d", y, m, d))
        refreshRep()
        timeBox:SetText(string.format("%02d:%02d", hh, mm))
        sizeBtn.sizeVal = size; sizeBtn.label:SetText(tostring(size))
        titleBox:SetText(title)
        descBox:SetText(note)
        setExtraForm(event and CAL().ExtraOf(event) or {})
        refreshQuick()
        refreshPreview()
        f:Show(); f:Raise()
        titleBox:SetFocus()
    end

    return f
end

-- The label of a reminder setting, as the editor names it.
local function remindText(sec)
    for _, o in ipairs(REMIND_OPTIONS) do if o.lead == sec then return o.label end end
    return L["Custom"]
end

local function openEditor(dk, event, asCopy)
    if not editor then editor = buildEditor() end
    editor:Open(dk, event, asCopy)
end


-- Delete confirmation (standard Blizzard popup; avoids accidental loss).
GuildOS.Dialogs["GUILDOS_CALENDAR_DELETE"] = {
    text = L["Remove \"%s\" from the calendar? This cannot be undone."],
    button1 = YES, button2 = NO,
    OnAccept = function(self, data)
        local id = data
        if id == nil and self then id = self.data end   -- older clients pass via dialog.data
        if id then CAL():Delete(id) end
    end,
    timeout = 0, whileDead = true, hideOnEscape = true, showAlert = true,
    preferredIndex = 3,
}
local function confirmDelete(e)
    local dlg = GuildOS:ShowDialog("GUILDOS_CALENDAR_DELETE", e.title or "?", nil, e.id)
    if dlg then dlg.data = e.id end   -- some clients pass data via dialog.data
end

-- Ending a series from one date on (#267): the earlier dates stay.
GuildOS.Dialogs["GUILDOS_CALENDAR_END_SERIES"] = {
    text = L["End \"%s\" from this date on? Earlier dates stay."],
    button1 = YES, button2 = NO,
    OnAccept = function(self, data)
        local id = data
        if id == nil and self then id = self.data end
        if id then CAL():EndSeries(id) end
    end,
    timeout = 0, whileDead = true, hideOnEscape = true, showAlert = true,
    preferredIndex = 3,
}
local function confirmEndSeries(e)
    local dlg = GuildOS:ShowDialog("GUILDOS_CALENDAR_END_SERIES", e.title or "?", nil, e.id)
    if dlg then dlg.data = e.id end
end

----------------------------------------------------------------------
-- Build the calendar into a Guild-hub sub-panel; return its refresh fn.
----------------------------------------------------------------------
function GuildOS:CreateCalendarSub(panel)
    local f = CreateFrame("Frame", nil, panel)
    f:SetAllPoints(panel)

    -- Month navigation. The month is the screen's first section title; it is as wide as its name, so
    -- the ">" sits right after it rather than a fixed 170px away (#371).
    local prevBtn = UI:CreateButton(f, "<", 26, 22)
    prevBtn:SetPoint("TOPLEFT", GRID_X, NAV_Y)
    local monthLabel = UI:CreateSectionTitle(f, "", true)
    monthLabel:SetPoint("LEFT", prevBtn, "RIGHT", GAP, 0)
    local nextBtn = UI:CreateButton(f, ">", 26, 22)
    nextBtn:SetPoint("LEFT", monthLabel, "RIGHT", GAP, 0)
    local todayBtn = UI:CreateButton(f, L["Today"], 60, 22)
    todayBtn:SetPoint("LEFT", nextBtn, "RIGHT", 12, 0)

    -- Weekday headers: the grid's column labels (repositioned in Render to match the grid width)
    f.wdFS = {}
    for i = 1, COLS do
        f.wdFS[i] = UI:CreateHeaderText(f, WEEKDAYS[i])
    end

    -- Day cells
    f.cells = {}
    for idx = 1, COLS * ROWS do
        local cell = CreateFrame("Button", nil, f, "BackdropTemplate")
        cell:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = GuildOS.UI:Edge(cell) })
        cell.dayFS = cell:CreateFontString(nil, "OVERLAY")
        GuildOS:ApplyFont(cell.dayFS, 11)
        cell.dayFS:SetPoint("TOPLEFT", 4, -3)
        cell.evtFS = cell:CreateFontString(nil, "OVERLAY")
        GuildOS:ApplyFont(cell.evtFS, 9)
        cell.evtFS:SetPoint("BOTTOMLEFT", 3, 3)
        cell.evtFS:SetPoint("BOTTOMRIGHT", -3, 3)
        cell.evtFS:SetJustifyH("LEFT"); cell.evtFS:SetWordWrap(false)
        cell:SetScript("OnClick", function(self2)
            if self2.dkey then f.selectedKey = self2.dkey; f.Render() end
        end)
        f.cells[idx] = cell
    end

    -- Detail area (below the grid): the selected day is a section of its own, its rule 12px over it,
    -- with room for that rule under the grid (#371).
    local DET_Y = GRID_Y - ROWS * CELL_H - 20
    local detailLabel = UI:CreateSectionTitle(f, "")
    detailLabel:SetPoint("TOPLEFT", GRID_X, DET_Y)

    -- Officer "New Event" button, beside the day it adds to: opens the editor popup for the selected day.
    local newBtn = UI:CreateButton(f, L["New Event"], 100, 20)
    newBtn:SetPoint("LEFT", detailLabel, "RIGHT", 12, 0)
    newBtn:SetScript("OnClick", function()
        if f.selectedKey then openEditor(f.selectedKey, nil) end
    end)
    f.newBtn = newBtn

    -- Event list holder (scrollable), fills the rest of the panel
    local holder = CreateFrame("Frame", nil, f)
    holder:SetPoint("TOPLEFT", detailLabel, "BOTTOMLEFT", 0, -12)
    holder:SetPoint("BOTTOMRIGHT", 0, 0)
    f.holder = holder
    local scrollFrame, scrollChild = UI:CreateScrollFrame(holder, "GuildOSCalendarScroll")
    scrollFrame:SetAllPoints()   -- fill the holder; without this the scroll viewport is 0x0 and clips all content
    -- The child keeps the list's width, less the bar's gutter; the rows hang from both its top corners.
    UI:BindScrollChildWidth(scrollFrame, scrollChild)
    f.child = scrollChild

    ------------------------------------------------------------------
    -- Render (grid sizes to the current panel width)
    ------------------------------------------------------------------
    function f.Render()
        local W = f:GetWidth()
        if not W or W < 120 then W = 1000 end
        local cellW = math.floor((W - GRID_X - GAP) / COLS)

        monthLabel:SetText(GuildOS:LocalDate(L["%b %Y"], noon(f.viewYear, f.viewMonth, 1)))

        for i = 1, COLS do
            f.wdFS[i]:ClearAllPoints()
            f.wdFS[i]:SetPoint("TOPLEFT", GRID_X + (i - 1) * cellW + 4, WD_Y)
        end

        -- Bucket events by day.
        local byDay = {}
        for _, e in pairs(CAL():GetEvents()) do
            if not e.canceled then
                local k = keyOfTs(e.when)
                byDay[k] = byDay[k] or {}
                byDay[k][#byDay[k] + 1] = e
            end
        end

        local dim = daysInMonth(f.viewYear, f.viewMonth)
        local lead = firstWeekday(f.viewYear, f.viewMonth) - 1
        local todayKey = keyOfTs(GetServerTime())

        for idx = 1, COLS * ROWS do
            local col = (idx - 1) % COLS
            local row = math.floor((idx - 1) / COLS)
            local cell = f.cells[idx]
            cell:ClearAllPoints()
            cell:SetPoint("TOPLEFT", GRID_X + col * cellW, GRID_Y - row * CELL_H)
            cell:SetSize(cellW - 2, CELL_H - 2)

            local dayNum = idx - lead
            -- Flat cells with a 1px line; the selected day and today take a 1px gold border and no
            -- gold fill, the selected one on the selected-row surface (#371).
            if dayNum < 1 or dayNum > dim then
                cell.dayFS:SetText(""); cell.evtFS:SetText(""); cell.dkey = nil
                cell:SetBackdropColor(C.well.r, C.well.g, C.well.b, 0)
                cell:SetBackdropBorderColor(C.line.r, C.line.g, C.line.b, 0.4)
            else
                local k = dayKey(f.viewYear, f.viewMonth, dayNum)
                cell.dkey = k
                cell.dayFS:SetText(dayNum); cell.dayFS:SetTextColor(C.text.r, C.text.g, C.text.b)
                local evs = byDay[k]
                if evs then
                    table.sort(evs, function(a, b) return a.when < b.when end)
                    local line = date("%H:%M ", evs[1].when) .. (evs[1].title or "")
                    if #evs > 1 then line = "+" .. #evs .. " " .. line end
                    cell.evtFS:SetText(line)
                    local kc = eventColor(evs[1])
                    cell.evtFS:SetTextColor(kc.r, kc.g, kc.b)
                else
                    cell.evtFS:SetText("")
                end
                local fill = (k == f.selectedKey) and C.popup or C.well
                local edge = (k == f.selectedKey or k == todayKey) and C.gold or C.line
                cell:SetBackdropColor(fill.r, fill.g, fill.b, 1)
                cell:SetBackdropBorderColor(edge.r, edge.g, edge.b, 1)
            end
        end

        f.RenderDetail(byDay)
    end

    ------------------------------------------------------------------
    -- Detail for the selected day
    ------------------------------------------------------------------
    function f.RenderDetail(byDay)
        local isOfficer = GuildOS:IsOfficer()
        -- The guild's ranks (issue #283), and a kind left open to this one (#308).
        local canCreate = GuildOS:MayCreateEvents() and #CAL():CreatableKinds() > 0
        local sel = f.selectedKey
        if sel then
            local y = math.floor(sel / 10000); local m = math.floor((sel % 10000) / 100); local d = sel % 100
            detailLabel:SetText(GuildOS:LocalDate(L["%A, %d %b %Y"], noon(y, m, d)))
        else
            detailLabel:SetText(L["Select a day"])
        end
        f.newBtn:SetShown(canCreate and sel ~= nil)

        local child = f.child
        for _, c in pairs({ child:GetChildren() }) do c:Hide() end
        for _, r in pairs({ child:GetRegions() }) do r:Hide() end

        -- A line that wraps hangs from both of the list's top corners, never from a width read while
        -- the tab may be hidden (#371).
        local function across(fs, y)
            fs:SetPoint("TOPLEFT", 0, -y)
            fs:SetPoint("TOPRIGHT", 0, -y)
            fs:SetJustifyH("LEFT")
        end
        local soft = C.textSoft

        local evs = (sel and byDay and byDay[sel]) or {}
        local yy = 0
        -- The game's own calendar (guildos-web specs/075, #263), read once for the day's raids from the
        -- site: its guild events over the inbox's window, and the inbox. WoW: Forever only.
        local GC = GuildOS.GameCalendar
        local gameOn = GC ~= nil and GuildOS.Compat.CalendarAvailable()
        local gameEvents, inbox   -- gameEvents stays nil until the game has read its calendar
        if gameOn then
            GuildOS.Compat.CalendarRequest()
            local now = GetServerTime()
            gameEvents = GuildOS.Compat.CalendarGuildEvents(now - GC.GRACE - 86400, now + (GC.WINDOW_DAYS + 1) * 86400)
            inbox = GuildOS.CompanionImport and GuildOS.CompanionImport:InboxInfo()
        end
        -- Per-day render is wrapped so a single malformed event can't blank the
        -- whole list; any failure is surfaced inline instead.
        local okAll, errAll = pcall(function()
        for _, e in ipairs(evs) do
            local comp = CAL():GetComposition(e)
            local mine = CAL():MyRsvp(e)

            -- The kind keeps its colour: it is the same one the grid marks the day with.
            local tag = tint("[" .. kindLabel(e.kind) .. "]", eventColor(e)) .. " "
            -- Shared events carry a mark so an officer can see what is exposed
            -- without opening each one. Marking the SHARED ones (not the
            -- private ones) because exposure is the state that wants attention.
            -- An [A] rather than a globe glyph: the skin fonts have no symbol
            -- coverage and unicode marks render as a box in these fonts. In the
            -- text colour, not gold: gold is the selection's (#371).
            local shareMark = e.shareAlliance and "  [A]" or ""
            local inSeries = type(e.series) == "table"
            local repMark = inSeries and ("  " .. tint(L["(repeats)"], soft)) or ""
            local head = UI:CreateText(child, date("%H:%M ", e.when) .. tag .. (e.title or "") .. "  "
                .. tint("(" .. (e.size or DEFAULT_SIZE) .. ")", soft) .. shareMark .. repMark,
                12, C.text.r, C.text.g, C.text.b)
            head:SetPoint("TOPLEFT", 0, -yy)
            if CAL():MayManage(e) then
                local ev = e
                local delBtn = UI:CreateButton(child, L["Delete"], 58, 18)
                delBtn:SetPoint("TOPRIGHT", 0, -yy)
                delBtn:SetScript("OnClick", function() confirmDelete(ev) end)
                local editBtn = UI:CreateButton(child, L["Edit"], 48, 18)
                editBtn:SetPoint("RIGHT", delBtn, "LEFT", -6, 0)
                editBtn:SetScript("OnClick", function() openEditor(nil, ev) end)
                local copyBtn = UI:CreateButton(child, L["Copy"], 48, 18)
                copyBtn:SetPoint("RIGHT", editBtn, "LEFT", -6, 0)
                copyBtn:SetScript("OnClick", function() openEditor(nil, ev, true) end)
                if inSeries then
                    -- This date and every later one of the series go (#267).
                    local endBtn = UI:CreateButton(child, L["End series"], 80, 18)
                    endBtn:SetPoint("RIGHT", copyBtn, "LEFT", -6, 0)
                    endBtn:SetScript("OnClick", function() confirmEndSeries(ev) end)
                end
            end
            yy = yy + 20

            local compFS = UI:CreateText(child, string.format(L["Tanks %d, Heals %d, DPS %d  (%d going, %d tentative)"],
                comp.roles.TANK, comp.roles.HEALER, comp.roles.DPS, comp.yes, comp.tentative),
                11, soft.r, soft.g, soft.b)
            compFS:SetPoint("TOPLEFT", 0, -yy)
            yy = yy + 18

            -- What the event asks of its people: where, who leads, the level, the spots, the sign-ups and
            -- the reminder. Each line is shown only when the event sets it.
            local facts = {}
            if e.location and e.location ~= "" then facts[#facts + 1] = L["Where: "] .. e.location end
            local who = {}
            if e.lead and e.lead ~= "" then who[#who + 1] = L["Lead: "] .. e.lead end
            if e.coHost and e.coHost ~= "" then who[#who + 1] = L["Co-host: "] .. e.coHost end
            if #who > 0 then facts[#facts + 1] = table.concat(who, "  -  ") end
            if e.level then facts[#facts + 1] = string.format(L["Level %d+"], e.level) end
            if e.slots then
                local spots = {}
                for _, r in ipairs({ "TANK", "HEALER", "DPS" }) do
                    if e.slots[r] then spots[#spots + 1] = roleLabel(r) .. " " .. (comp.roles[r] or 0) .. "/" .. e.slots[r] end
                end
                if #spots > 0 then facts[#facts + 1] = L["Spots: "] .. table.concat(spots, ", ") end
            end
            if e.closeLead then
                local closeAt = (e.when or 0) - e.closeLead
                if GetServerTime() >= closeAt then
                    facts[#facts + 1] = L["Sign-ups are closed."]
                else
                    facts[#facts + 1] = string.format(L["Sign-ups close %s."], GuildOS:LocalDate("%a %d %b %H:%M", closeAt))
                end
            end
            if e.remind then facts[#facts + 1] = L["Reminder: "] .. remindText(e.remind) end
            for _, line in ipairs(facts) do
                local factFS = UI:CreateText(child, line, 11, soft.r, soft.g, soft.b)
                across(factFS, yy)
                yy = yy + math.max(14, (factFS:GetStringHeight() or 12) + 4)
            end

            if e.note and e.note ~= "" then
                local noteFS = UI:CreateText(child, e.note, 11, soft.r, soft.g, soft.b)
                across(noteFS, yy)
                yy = yy + math.max(14, (noteFS:GetStringHeight() or 12) + 6)
            end

            if CAL():IsWebEvent(e) then
                -- Planned on the site, so signing up happens there: the game shows the site's
                -- answers and no buttons of its own. A second list here was a second answer to
                -- the same question, empty, and it never reached the site (#146).
                -- With when the list is from: a member who was offline when it was sent keeps the
                -- last one they got.
                local where = L["Sign up in Discord or on the website."]
                if (tonumber(e.signupsAt) or 0) > 0 then
                    where = where .. " " .. string.format(L["(as of %s)"], GuildOS:LocalDate("%a %H:%M", e.signupsAt))
                end
                local whereFS = UI:CreateText(child, where, 11, soft.r, soft.g, soft.b)
                whereFS:SetPoint("TOPLEFT", 0, -yy)
                yy = yy + 16
                -- Whether it is in the game's own calendar, and for an officer the click that changes it.
                if gameOn then
                    local view = GC:ViewFor(e, gameEvents, inbox)
                    if view.text then
                        local stateFS = UI:CreateText(child, view.text, 11, soft.r, soft.g, soft.b)
                        stateFS:SetPoint("TOPLEFT", 0, -yy)
                        if view.action then
                            local evId, action = e.id, view.action
                            local gameBtn = UI:CreateButton(child, view.label, 200, 18)
                            gameBtn:SetPoint("TOPRIGHT", 0, -yy)
                            gameBtn:SetScript("OnClick", function() GC:Act(evId, action) end)
                        end
                        yy = yy + 20
                    end
                end
                -- An allied seat is approved in the game, and goes with the ones coming.
                local answers = CAL():WebSignups(e)
                for _, r in pairs(e.rsvps or {}) do
                    if r.ally and r.status == "yes" then
                        answers[#answers + 1] = { name = GuildOS:SanitizeUserText(r.name or "?", 48), class = r.class, status = "yes" }
                    end
                end
                for _, line in ipairs({
                    { "yes", L["Going: "] }, { "pending", L["Awaiting approval: "] },
                    { "tentative", L["Tentative: "] }, { "wait", L["Standby: "] }, { "no", L["Absent: "] },
                }) do
                    local names = {}
                    for _, s in ipairs(answers) do
                        if s.status == line[1] then
                            local cr, cg, cb = GuildOS:GetClassColor(s.class)
                            names[#names + 1] = string.format("|cff%02x%02x%02x%s|r", cr * 255, cg * 255, cb * 255, s.name)
                        end
                    end
                    if #names > 0 then
                        local fs = UI:CreateText(child, line[2] .. table.concat(names, ", "), 11, soft.r, soft.g, soft.b)
                        across(fs, yy)
                        yy = yy + math.max(14, (fs:GetStringHeight() or 12) + 4)
                    end
                end
            else
                local id = e.id
                local roleBtn = UI:CreateButton(child, roleLabel((mine and mine.role) or "DPS"), 66, 18)
                roleBtn:SetPoint("TOPLEFT", 0, -yy)
                roleBtn.role = (mine and mine.role) or "DPS"
                roleBtn:SetScript("OnClick", function()
                    local i = 1
                    for j, v in ipairs(ROLES) do if v == roleBtn.role then i = j break end end
                    roleBtn.role = ROLES[(i % #ROLES) + 1]
                    roleBtn.label:SetText(roleLabel(roleBtn.role))
                end)
                -- Chained, so a label that grew its button pushes the next one (issue #28). My answer
                -- is the selected one of the three, marked as every selection is (#371).
                local function rsvpBtn(text, status, anchor, xoff)
                    local b = UI:CreateButton(child, text, 64, 18)
                    b:SetPoint("LEFT", anchor, "RIGHT", xoff, 0)
                    UI:SetSelected(b, mine and mine.status == status)
                    b:SetScript("OnClick", function() CAL():Rsvp(id, status, roleBtn.role) end)
                    return b
                end
                local goingBtn = rsvpBtn(L["Going"],     "yes",       roleBtn,  8)
                local tentBtn  = rsvpBtn(L["Tentative"], "tentative", goingBtn, 4)
                rsvpBtn(L["Absent"],    "no",        tentBtn,  4)
                yy = yy + 24

                local going = {}
                for _, r in pairs(e.rsvps or {}) do
                    if r.status == "yes" then
                        local cr, cg, cb = GuildOS:GetClassColor(r.class)
                        going[#going + 1] = string.format("|cff%02x%02x%02x%s|r", cr * 255, cg * 255, cb * 255, r.name or "?")
                    end
                end
                if #going > 0 then
                    local goFS = UI:CreateText(child, L["Going: "] .. table.concat(going, ", "), 11, soft.r, soft.g, soft.b)
                    across(goFS, yy)
                    yy = yy + math.max(14, (goFS:GetStringHeight() or 12) + 4)
                end
                local standby = {}
                for _, r in pairs(e.rsvps or {}) do
                    if r.status == "wait" then standby[#standby + 1] = r.name or "?" end
                end
                if #standby > 0 then
                    local sbFS = UI:CreateText(child, L["Standby: "] .. table.concat(standby, ", "), 11, soft.r, soft.g, soft.b)
                    across(sbFS, yy)
                    yy = yy + math.max(14, (sbFS:GetStringHeight() or 12) + 4)
                end
            end

            -- Cross-guild signup queue. Officers only: the request already
            -- reached only ambassadors, and seating is an officer action.
            local pending = isOfficer and CAL().AlliancePending and CAL():AlliancePending(e) or {}
            if #pending > 0 then
                -- The queue's own column label, not gold (#371).
                local hdr = UI:CreateHeaderText(child, string.format(L["ALLIANCE PENDING (%d)"], #pending))
                hdr:SetPoint("TOPLEFT", 0, -yy)
                yy = yy + 16
                for _, p in ipairs(pending) do
                    local cr, cg, cb = GuildOS:GetClassColor(p.class)
                    local line = string.format("|cff%02x%02x%02x%s|r  %s  %s  %s",
                        cr * 255, cg * 255, cb * 255, p.name or "?",
                        p.level and tostring(p.level) or "", roleLabel(p.role), tint(p.guild or "?", soft))
                    if p.note and p.note ~= "" then
                        line = line .. "  " .. tint("\"" .. p.note .. "\"", C.label)
                    end
                    local evId, pKey = e.id, p.key
                    local noBtn = UI:CreateButton(child, L["Decline"], 62, 18)
                    noBtn:SetPoint("TOPRIGHT", 0, -yy + 2)
                    noBtn:SetScript("OnClick", function() CAL():DeclineAlliance(evId, pKey) end)
                    local yesBtn = UI:CreateButton(child, L["Approve"], 62, 18)
                    yesBtn:SetPoint("RIGHT", noBtn, "LEFT", -6, 0)
                    yesBtn:SetScript("OnClick", function() CAL():ApproveAlliance(evId, pKey) end)

                    -- One line, stopping short of its two buttons.
                    local fs = UI:CreateText(child, line, 11, C.text.r, C.text.g, C.text.b)
                    fs:SetPoint("TOPLEFT", 0, -yy)
                    fs:SetPoint("TOPRIGHT", yesBtn, "TOPLEFT", -GAP, -2)
                    fs:SetJustifyH("LEFT")
                    fs:SetWordWrap(false)

                    yy = yy + 20
                end
            end

            yy = yy + 12
        end
        end)
        if not okAll then
            local errFS = UI:CreateText(child, tostring(errAll), 11, C.danger.r, C.danger.g, C.danger.b)
            across(errFS, yy)
            yy = yy + math.max(40, (errFS:GetStringHeight() or 20) + 10)
        end

        if sel and #evs == 0 then
            local none = UI:CreateText(child, canCreate and L["No events. Use New Event to add one."] or L["No events this day."],
                12, soft.r, soft.g, soft.b)
            none:SetPoint("TOPLEFT", 0, 0)
        end
        child:SetHeight(math.max(1, yy))
    end

    prevBtn:SetScript("OnClick", function()
        f.viewMonth = f.viewMonth - 1
        if f.viewMonth < 1 then f.viewMonth = 12; f.viewYear = f.viewYear - 1 end
        f.Render()
    end)
    nextBtn:SetScript("OnClick", function()
        f.viewMonth = f.viewMonth + 1
        if f.viewMonth > 12 then f.viewMonth = 1; f.viewYear = f.viewYear + 1 end
        f.Render()
    end)
    todayBtn:SetScript("OnClick", function()
        local t = date("*t", GetServerTime())
        f.viewYear, f.viewMonth, f.selectedKey = t.year, t.month, dayKey(t.year, t.month, t.day)
        f.Render()
    end)

    -- Initial view = current month, today selected.
    local t = date("*t", GetServerTime())
    f.viewYear, f.viewMonth, f.selectedKey = t.year, t.month, dayKey(t.year, t.month, t.day)

    -- A deep link (the Now tab's raid) opens on that day, its events listed.
    panel.ApplyFilter = function(when)
        local d = date("*t", when)
        f.viewYear, f.viewMonth, f.selectedKey = d.year, d.month, dayKey(d.year, d.month, d.day)
        f.Render()
    end

    -- Live-refresh while visible as synced events/RSVPs arrive.
    if GuildOS.Calendar then
        GuildOS.Calendar.uiRefresh = function() if panel:IsShown() then f.Render() end end
    end

    return f.Render
end

----------------------------------------------------------------------
-- Entry point (command): open the roster on the Guild hub's Calendar sub-tab.
----------------------------------------------------------------------
function GuildOS:ShowCalendar()
    GuildOS.UI:OpenWindow("guild", "calendar")
end
