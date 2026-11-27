----------------------------------------------------------------------
-- Guild OS - The Groups tab (issue #341)
-- The guild's own group finder: what is being formed and who is looking (Active), and the game's
-- activities as tiles (Dungeons, Raids, Quests and more), each with how many groups and players it
-- has. Modules/Groups.lua and Modules/LFGBoard.lua answer; this draws and calls their methods.
--
-- Activity cards (#373): the roles are the game's own icons, a group being formed is a card with its
-- activity's art and one seat per place it has or offers, a player looking is a row with class, level
-- and roles, and Dungeons opens on the tiles of my level. Nothing here is new data: every figure is
-- one the modules already keep.
--
-- One scroll area, repainted from pools: a repaint that created its rows would leak them, because
-- the client never frees a frame.
----------------------------------------------------------------------
local UI = GuildOS.UI
local C = GuildOS.Colors
local L = GuildOS.L
local WHITE = "Interface\\Buttons\\WHITE8x8"

local TAB_H, TAB_MIN_W, TAB_PAD = 28, 70, 20   -- as the Guild hub's sub-tabs
local TILE_MIN_W, TILE_H, GAP = 150, 60, UI.GAP
local ROW_H, HEAD_H = 24, 26
local HEAD_ABOVE = 20           -- room over a later section title for its rule (UI:CreateSectionTitle)
local CHIP = 22
local ART_ALPHA = 0.55          -- the game's art under a tile's text
local OFF_LEVEL_ALPHA = 0.5     -- a tile outside my level
local LEVEL_SLACK = 5           -- levels past an activity's range it still reads as mine
local REPAINT_EVERY = 30        -- seconds: the time left on a listing
local NAME_W, ROLES_W, TIME_W = 130, 96, 44

-- A forming group's card (#373). Its rows sit at fixed heights so the cards of one row line up
-- whatever each says: the art band, who leads, the seats, the note, the actions.
-- Never narrower than its widest action row: Whisper and three Join buttons at 60px, 4px apart, 8px in
-- from each side (264 + 16). Three a row on the default window, two or one on a narrower one.
local GROUP_MIN_W = 280
local BAND_H = 48
local SLOT, SLOT_GAP = 16, 3
local ROW_LEAD = BAND_H + 8
local ROW_SEATS = ROW_LEAD + 18
local ROW_NOTE = ROW_SEATS + SLOT + 6
local ROW_STATUS = ROW_NOTE + 18   -- what the buttons below do ("ask for a spot as"), on a line of its own
local ROW_ACT = ROW_STATUS + 16
local GROUP_H = ROW_ACT + 20 + 8
-- My group as the leader's panel, and the summary over Active (#378), in one table: the tab's builder
-- is one function, and Lua 5.1 lets a function reach at most 60 of the file's locals.
local K = {}
K.SEATS = BAND_H + 10
K.FILL = K.SEATS + SLOT + 10
K.META = K.FILL + 14
K.ACT = K.META + 22
K.H = K.ACT + 22 + 10
K.TIME_BAR_H = 2           -- the time a listing has left, under a card's band
K.SUMMARY_H, K.FILTER_H = 46, 22
K.FILTERS = {
    { key = "all",     label = L["All"] },
    { key = "dungeon", label = L["Dungeons"] },
    { key = "raid",    label = L["Raids"] },
    { key = "other",   label = L["Quests and more"] },
}
-- A player looking (#373): class icon, name, level, roles, what they want.
local ICON, CLASS_W, LEVEL_W = 16, 20, 44
local ROLE_ICONS_W = 3 * (ICON + 2) + 6
local CLASS_ICONS = "Interface\\GLUES\\CHARACTERCREATE\\UI-CharacterCreate-Classes"   -- as the Roster's
-- A scroll child past ~15000px stops drawing: a guild of hundreds all looking must not get there.
local GROUPS_MAX, SEEKERS_MAX = 50, 200   -- one column, both full: under 14,000px with the status row
local DOT = "  \194\183  "

local LETTERS = { "T", "H", "D" }
local ROLE_OF = { T = "TANK", H = "HEALER", D = "DPS" }
local SUBS = {
    { key = "active",  label = L["Active now"] },
    { key = "dungeon", label = L["Dungeons"] },
    { key = "raid",    label = L["Raids"] },
    { key = "other",   label = L["Quests and more"] },
}

local function roleColor(letter)
    return (letter == "T" and C.info) or (letter == "H" and C.ok) or C.danger
end

local function roleNames(roles)
    local B, out = GuildOS.LFGBoard, {}
    for _, k in ipairs(LETTERS) do
        if roles:find(k, 1, true) then out[#out + 1] = B:RoleName(ROLE_OF[k]) end
    end
    return #out > 0 and table.concat(out, ", ") or B:RoleName("ANY")
end

local function coloured(name, classFile)
    if not classFile then return name end
    return "|cff" .. GuildOS:GetClassColorHex(classFile) .. name .. "|r"
end

local function whisper(name)
    local target = GuildOS:WhisperTarget(name)
    if ChatFrame_SendTell then ChatFrame_SendTell(target) else ChatFrame_OpenChat("/w " .. target .. " ") end
end

local function oneLine(fs, width)
    fs:SetWidth(math.max(10, width))
    fs:SetJustifyH("LEFT")
    fs:SetWordWrap(false)
end

-- "68-70", or the one level, or nothing for an activity with no range.
local function rangeOf(it)
    if not it or not it.min then return "" end
    return it.min == it.max and tostring(it.min) or (it.min .. "\226\128\147" .. it.max)
end

-- Whether the client has an activity's art, asked once: a path it lacks draws a green square.
local function hasArt(it)
    if it.artOk == nil then it.artOk = it.art ~= nil and GuildOS.Compat.TextureExists(it.art) end
    return it.artOk
end

----------------------------------------------------------------------
-- The game's role icons (#373)
----------------------------------------------------------------------
-- The group finder's own atlases, where the client lists all three: retail, TBC Anniversary and
-- WoW: Forever name both sets (tools/data/forever-atlas-elements.txt, neither marked Forever-only),
-- and on Forever an element resolves to its own -c60 art. Then the LFG frame's file, cut where
-- Blizzard's GetTexCoordsForRole cuts it (67px cells of a 256px sheet). Then nothing: a role keeps
-- its letter, because a path the client does not have draws a green square.
local ROLE_ATLASES = {
    { T = "groupfinder-icon-role-large-tank", H = "groupfinder-icon-role-large-heal", D = "groupfinder-icon-role-large-dps" },
    { T = "UI-LFG-RoleIcon-Tank", H = "UI-LFG-RoleIcon-Healer", D = "UI-LFG-RoleIcon-DPS" },
}
local ROLE_FILE = "Interface\\LFGFrame\\UI-LFG-ICON-ROLES"
local CELL = 67 / 256
local ROLE_CELL = { T = { 0, CELL, CELL, 2 * CELL }, H = { CELL, 2 * CELL, 0, CELL }, D = { CELL, 2 * CELL, CELL, 2 * CELL } }
local roleArt   -- the atlas set, "file", or false; asked once a session: the client's files do not change

local function roleArtKind()
    if roleArt ~= nil then return roleArt end
    roleArt = false
    local get = C_Texture and C_Texture.GetAtlasInfo
    for _, set in ipairs(get and ROLE_ATLASES or {}) do
        local all = true
        for _, letter in ipairs(LETTERS) do
            local ok, info = pcall(get, set[letter])
            all = all and ok and info ~= nil
        end
        if all then
            roleArt = set
            return roleArt
        end
    end
    if GuildOS.Compat.TextureExists(ROLE_FILE) then roleArt = "file" end
    return roleArt
end

-- Paint a role's icon on `tex` and show it. False, with `tex` hidden, where the client has none: the
-- caller then shows the role's letter or name.
local function setRoleIcon(tex, letter)
    local kind = roleArtKind()
    if type(kind) == "table" then
        tex:SetAtlas(kind[letter])
    elseif kind == "file" then
        tex:SetTexture(ROLE_FILE)
        tex:SetTexCoord(unpack(ROLE_CELL[letter]))
    else
        tex:Hide()
        return false
    end
    tex:Show()
    return true
end

-- A role's square: a shared button with the role's icon, or its letter where the client has no icon
-- (#373). A chosen role takes the shared selection mark (UI:SetSelected), not a border tinted in the
-- role's colour (#371); an icon not chosen is greyed, as the game's own role picker greys it.
local function createRoleChip(parent, letter)
    local chip = UI:CreateButton(parent, letter, CHIP, CHIP)
    chip.letter = letter
    chip.baseLabelColor = { C.label.r, C.label.g, C.label.b }
    chip.icon = chip:CreateTexture(nil, "ARTWORK")
    chip.icon:SetSize(CHIP - 6, CHIP - 6)
    chip.icon:SetPoint("CENTER")
    if setRoleIcon(chip.icon, letter) then chip.label:SetText("") end
    function chip:SetOn(on)
        self.on = on and true or false
        UI:SetSelected(self, self.on)
        self.icon:SetDesaturated(not self.on)
    end
    chip:SetOn(false)
    -- Hooked, not set: the button's own hover and press states live on OnEnter and OnLeave.
    local B = GuildOS.LFGBoard
    chip:HookScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine(B:RoleName(ROLE_OF[letter]), GuildOS.Tip.text.r, GuildOS.Tip.text.g, GuildOS.Tip.text.b)
        GameTooltip:Show()
    end)
    chip:HookScript("OnLeave", function() GameTooltip:Hide() end)
    return chip
end

-- A role's square that only names the role (a stepper's), never chosen: its icon in full colour, or
-- its letter in the role's colour.
local function createRoleMark(parent, letter)
    local mark = createRoleChip(parent, letter)
    local ink = roleColor(letter)
    mark.baseLabelColor = { ink.r, ink.g, ink.b }
    UI:_ButtonState(mark, "rest")
    mark.icon:SetDesaturated(false)
    mark:EnableMouse(false)
    return mark
end

----------------------------------------------------------------------
-- The composer: one popup, two modes (I am looking; I am forming a group)
----------------------------------------------------------------------
local composer

local function defaultNeed(act)
    local need = { T = 1, H = 1, D = 3 }
    local mine = GuildOS.LFGBoard:Pref("roles") or ""
    if #mine == 1 and need[mine] > 0 then need[mine] = need[mine] - 1 end
    local room = GuildOS.Groups:SizeOf(act) - 1
    return GuildOS.Groups:_SanitizeNeed(need, room)
end

-- The composer's figures (#6, #11, #12, #15, #16).
local NOTE_LEN = 60
local TIME_W, TIME_GAP, TIME_SEP = 38, 4, 10   -- the timing row: the starts, a gap, then the listing lengths

-- The level range of some activities: the lowest any starts at, the highest any ends at. nil when none has one.
local function levelsOf(acts)
    local cat = GuildOS.GroupActivities
    local lo, hi
    for _, id in ipairs(acts or {}) do
        local it = cat and cat.byId[id]
        if it and it.min then
            lo = math.min(lo or it.min, it.min)
            hi = math.max(hi or (it.max or it.min), it.max or it.min)
        end
    end
    return lo, hi
end

-- "Levels 24-32", or "Level 30" for one level. `lower` for use mid-sentence.
local function levelText(lo, hi, lower)
    if not lo then return nil end
    if lo == hi then return string.format(lower and L["level %d"] or L["Level %d"], lo) end
    return string.format(lower and L["levels %d-%d"] or L["Levels %d-%d"], lo, hi)
end

-- Groups forming for these activities, from the same counts the tiles use. `skipMine` leaves out my own
-- group, for a leader who reads the line as "other groups".
local function groupsForming(acts, skipMine)
    local G = GuildOS.Groups
    local counts = G:Counts(GetServerTime())
    local mine = skipMine and G:Mine() or nil
    local n = 0
    for _, id in ipairs(acts) do
        local c = counts[id]
        if c then n = n + c.groups end
    end
    if mine and mine.act then
        for _, id in ipairs(acts) do
            if id == mine.act then n = n - 1; break end
        end
    end
    return math.max(0, n)
end

-- The spots and timing I used for an activity I formed a group for, so the next one starts from them (#11).
local function rememberTiming(act, ttl, start, need)
    local prefs = GuildOS.db.lfgPrefs
    prefs.perAct = prefs.perAct or {}
    local spots = {}
    for _, k in ipairs(LETTERS) do spots[k] = need[k] or 0 end
    prefs.perAct[act] = { ttl = ttl, start = start, need = spots }
end

local function buildComposer()
    local B, G = GuildOS.LFGBoard, GuildOS.Groups
    local f = CreateFrame("Frame", "GuildOSGroupComposer", UIParent, "BackdropTemplate")
    f:SetSize(380, 476)
    f:SetPoint("CENTER")
    f:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = GuildOS.UI:Edge(f) })
    f:SetBackdropColor(C.popup.r, C.popup.g, C.popup.b, 1)
    f:SetBackdropBorderColor(C.line.r, C.line.g, C.line.b, 1)
    UI:StylePopup(f)
    f:SetFrameStrata("DIALOG")
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", function(s) s:StartMoving() end)
    f:SetScript("OnDragStop", function(s) s:StopMovingOrSizing() end)
    f:Hide()

    local close = UI:CreateCloseButton(f)
    close:SetPoint("TOPRIGHT", -8, -8)
    close:SetScript("OnClick", function() f:Hide() end)

    local PAD, y = 16, -30          -- the first row sits clear of the close button
    -- A form label (#371): body text in `text`, not a column header.
    local function label(text)
        local fs = UI:CreateText(f, text, 11)
        fs:SetPoint("TOPLEFT", PAD, y)
        y = y - 16
        return fs
    end

    -- Mode (#19): a full-width segmented control, two equal halves, the chosen one filled.
    local tabs = {}
    local SEG_W = math.floor((f:GetWidth() - PAD * 2 - 4) / 2)
    local function segment(mode, text, x)
        local b = UI:CreateButton(f, text, SEG_W, 26)
        b:SetPoint("TOPLEFT", x, y)
        b:SetScript("OnClick", function() f:SetMode(mode) end)
        tabs[mode] = b
    end
    segment("seek", L["I am looking"], PAD)
    segment("group", L["Form a group"], PAD + SEG_W + 4)
    y = y - 26 - 12

    -- Activity, with its level range (#6), and under it my level against the range (#12), and the
    -- groups forming for it (#16).
    label(L["ACTIVITY"])
    local actText = UI:CreateText(f, "", 12)
    actText:SetPoint("TOPLEFT", PAD, y)
    actText:SetWidth(f:GetWidth() - PAD * 2)
    actText:SetJustifyH("LEFT")
    actText:SetWordWrap(true)
    actText:SetHeight(28)
    actText:SetJustifyV("TOP")
    local onlyBtn = UI:CreateButton(f, L["Only this one"], 110, 18)
    onlyBtn:SetPoint("TOPRIGHT", -PAD, y + 20)
    y = y - 34
    local infoText = UI:CreateText(f, "", 11)
    infoText:SetPoint("TOPLEFT", PAD, y)
    infoText:SetWidth(f:GetWidth() - PAD * 2)
    infoText:SetJustifyH("LEFT")
    y = y - 16
    local formingText = UI:CreateText(f, "", 11, C.textSoft.r, C.textSoft.g, C.textSoft.b)
    formingText:SetPoint("TOPLEFT", PAD, y)
    formingText:SetWidth(f:GetWidth() - PAD * 2)
    formingText:SetJustifyH("LEFT")
    y = y - 18

    -- Roles (looking) or open spots (group): the same line, one of the two shown. In a group the size
    -- sits on that line too (#1).
    local rowY = y
    local rolesLabel = label("")
    local sizeText = UI:CreateText(f, "", 11, C.textSoft.r, C.textSoft.g, C.textSoft.b)
    sizeText:SetPoint("TOPRIGHT", -PAD, rowY)
    local chips, steppers, captions = {}, {}, {}
    local paint                      -- defined below; a chip's click repaints the composer
    local ROLE_STEP = 76             -- a chip with its role's name beside it
    for i, letter in ipairs(LETTERS) do
        local chip = createRoleChip(f, letter)
        chip:SetPoint("TOPLEFT", PAD + (i - 1) * ROLE_STEP, y)
        chip:SetScript("OnClick", function(self)
            self:SetOn(not self.on)
            paint()
        end)
        chips[letter] = chip
        local cap = UI:CreateText(f, GuildOS.LFGBoard:RoleName(ROLE_OF[letter]), 11)
        cap:SetPoint("LEFT", chip, "RIGHT", 4, 0)
        captions[letter] = cap

        local st = CreateFrame("Frame", nil, f)
        st:SetSize(104, CHIP)
        st:SetPoint("TOPLEFT", PAD + (i - 1) * 112, y)
        local mark = createRoleMark(st, letter)
        mark:SetPoint("LEFT")
        local minus = UI:CreateButton(st, "-", 20, CHIP)
        minus:SetPoint("LEFT", mark, "RIGHT", 4, 0)
        local value = UI:CreateText(st, "0", 12)
        value:SetPoint("LEFT", minus, "RIGHT", 0, 0)
        value:SetWidth(24)
        value:SetJustifyH("CENTER")
        local plus = UI:CreateButton(st, "+", 20, CHIP)
        plus:SetPoint("LEFT", value, "RIGHT", 0, 0)
        st.value = value
        st.minus, st.plus = minus, plus
        minus:SetScript("OnClick", function() f:Step(letter, -1) end)
        plus:SetScript("OnClick", function() f:Step(letter, 1) end)
        steppers[letter] = st
    end
    -- "Any": no role chosen, which the listing already means (roles are "" for any)
    local anyBtn = UI:CreateButton(f, L["Any"], 44, CHIP)
    anyBtn:SetPoint("TOPLEFT", PAD + #LETTERS * ROLE_STEP, y)
    anyBtn:SetScript("OnClick", function()
        for _, letter in ipairs(LETTERS) do chips[letter]:SetOn(false) end
        paint()
    end)
    y = y - CHIP - 12

    -- Note (#9): an example in the empty field, and the count against the limit.
    local noteY = y
    label(L["NOTE"])
    local note = UI:CreateInput(f, f:GetWidth() - PAD * 2, 22, { max = NOTE_LEN, placeholder = L["Chill run, voice optional"] })
    note:SetPoint("TOPLEFT", PAD, y)
    note:SetScript("OnEnterPressed", function(s) s:ClearFocus() end)
    local noteCount = UI:CreateText(f, "", 10, C.textSoft.r, C.textSoft.g, C.textSoft.b)
    noteCount:SetPoint("TOPRIGHT", -PAD, noteY)
    local function countNote()
        noteCount:SetText(string.format(L["%d/%d"], #(note:GetText() or ""), NOTE_LEN))
    end
    note:HookScript("OnTextChanged", countNote)
    countNote()
    y = y - 22 - 12

    -- Timing (#4, #5): when it starts and how long it lists, on one row. Seeking shows the listing
    -- length alone.
    local timingLabel = label("")
    local timingY = y
    local startBtns, durBtns = {}, {}
    for _, seconds in ipairs(G.STARTS) do
        local b = UI:CreateButton(f, seconds == 0 and L["Now"] or B:DurationName(seconds), TIME_W, 22)
        b:SetScript("OnClick", function()
            f.start = seconds
            paint()
        end)
        startBtns[#startBtns + 1] = { seconds = seconds, b = b }
    end
    for _, seconds in ipairs(B.DURATIONS) do
        local b = UI:CreateButton(f, B:DurationName(seconds), TIME_W, 22)
        b:SetScript("OnClick", function() f:SetDuration(seconds) end)
        durBtns[#durBtns + 1] = { seconds = seconds, b = b }
    end
    y = y - 22 - 12

    -- Sharing (#10): the two checkboxes under one heading, the auto-invite with its hint.
    local sharingLabel = UI:CreateText(f, L["SHARING"], 11)
    local chat = UI:CreateCheckbox(f, L["Also post in guild chat"], 18)
    chat.checkbox.onChanged = function(_, checked) B:SetPref("postToGuild", checked and true or false) end
    -- A group's own (#378): whoever asks, with the addon or by whispering "inv", is invited at once.
    local auto = UI:CreateCheckbox(f, L["Invite whoever asks"], 18)
    auto.checkbox.onChanged = function(_, checked) B:SetPref("autoInvite", checked and true or false) end
    local autoHint = UI:CreateText(f, L["Auto-invites anyone who whispers you"], 10, C.textSoft.r, C.textSoft.g, C.textSoft.b)

    -- Why Publish is off (#8), or the error of a failed post. Sits above the preview.
    local hint = UI:CreateText(f, "", 11, C.danger.r, C.danger.g, C.danger.b)
    hint:SetWidth(f:GetWidth() - PAD * 2)
    hint:SetJustifyH("LEFT")

    local preview = UI:CreateText(f, "", 11, C.textSoft.r, C.textSoft.g, C.textSoft.b)
    preview:SetPoint("BOTTOMLEFT", PAD, 48)
    preview:SetWidth(f:GetWidth() - PAD * 2)
    preview:SetJustifyH("LEFT")

    local publish = UI:SetButtonVariant(UI:CreateButton(f, L["Publish"], 110, 26), "primary")
    publish:SetPoint("BOTTOMRIGHT", -PAD, 14)
    local down = UI:SetButtonVariant(UI:CreateButton(f, L["Take down"], 100, 26), "danger")
    down:SetPoint("BOTTOMLEFT", PAD, 14)

    -- My chosen roles, as names, for the seek line and the preview.
    local function pickedNames()
        local picked = {}
        for _, letter in ipairs(LETTERS) do
            if chips[letter].on then picked[#picked + 1] = B:RoleName(ROLE_OF[letter]) end
        end
        return picked
    end

    function paint()
        local seek = f.mode == "seek"
        for mode, b in pairs(tabs) do UI:SetSelected(b, mode == f.mode) end
        rolesLabel:SetText(seek and L["I CAN PLAY"] or L["OPEN SPOTS"])
        local room = f.act and (G:SizeOf(f.act) - 1) or 0
        local total, any = 0, true
        for _, letter in ipairs(LETTERS) do
            total = total + (f.need[letter] or 0)
            any = any and not chips[letter].on
        end
        local picked = seek and pickedNames() or {}

        -- The activity line, the level line and the forming line.
        local namesText
        if seek then
            local names = {}
            for _, id in ipairs(f.acts) do names[#names + 1] = B:ActivityName(id) end
            namesText = #names > 0 and table.concat(names, ", ") or L["Anything"]
            actText:SetText(namesText)
            local lo, hi = levelsOf(f.acts)
            infoText:SetText(string.format(L["Showing groups for %s and %s"],
                levelText(lo, hi, true) or L["any level"], #picked > 0 and table.concat(picked, " or ") or L["any role"]))
            infoText:SetTextColor(C.textSoft.r, C.textSoft.g, C.textSoft.b)
            local n = groupsForming(f.acts)
            if #f.acts == 1 then
                formingText:SetText(string.format(L["%d groups forming for %s"], n, B:ActivityName(f.acts[1])))
            elseif #f.acts > 1 then
                formingText:SetText(string.format(L["%d groups forming for these activities"], n))
            else
                formingText:SetText("")
            end
        elseif f.act then
            namesText = B:ActivityName(f.act)
            local lo, hi = levelsOf({ f.act })
            local lvl = levelText(lo, hi)
            actText:SetText(lvl and (namesText .. DOT .. lvl) or namesText)
            local me = UnitLevel("player")
            if me and G:FitsLevel(f.act, me) then
                infoText:SetText(string.format(L["You're %d, fits"], me))
                infoText:SetTextColor(C.textSoft.r, C.textSoft.g, C.textSoft.b)
            elseif me then
                infoText:SetText(string.format(L["You're %d, outside the range"], me))
                infoText:SetTextColor(C.danger.r, C.danger.g, C.danger.b)
            else
                infoText:SetText("")
            end
            formingText:SetText(string.format(L["%d other groups forming for %s"], groupsForming({ f.act }, true), namesText))
        else
            actText:SetText(L["Pick what the group is for."])
            infoText:SetText("")
            formingText:SetText("")
        end
        onlyBtn:SetShown(seek and #f.acts > 1 and f.picked ~= nil)

        -- Roles or spots (#1, #2): the counters stop at the room a group has.
        local size = f.act and G:SizeOf(f.act) or nil
        sizeText:SetShown(not seek and size ~= nil)
        if size then sizeText:SetText(string.format(L["%d of %d spots open"], total, size)) end
        for _, letter in ipairs(LETTERS) do
            chips[letter]:SetShown(seek)
            captions[letter]:SetShown(seek)
            local ink = chips[letter].on and C.text or C.textSoft
            captions[letter]:SetTextColor(ink.r, ink.g, ink.b)
            local st = steppers[letter]
            st:SetShown(not seek)
            st.value:SetText(tostring(f.need[letter] or 0))
            -- + greys out at the room a group has, and - at none, rather than doing nothing when pressed
            if total < room then st.plus:Enable() else st.plus:Disable() end
            if (f.need[letter] or 0) > 0 then st.minus:Enable() else st.minus:Disable() end
        end
        anyBtn:SetShown(seek)
        UI:SetSelected(anyBtn, any)

        -- Timing (#4, #5): one row. The starts are a group's alone; the lengths come after them.
        timingLabel:SetText(seek and L["LISTING LASTS"] or L["STARTS  |  LISTING LASTS"])
        for i, s in ipairs(startBtns) do
            s.b:ClearAllPoints()
            s.b:SetPoint("TOPLEFT", PAD + (i - 1) * (TIME_W + TIME_GAP), timingY)
            s.b:SetShown(not seek)
            UI:SetSelected(s.b, s.seconds == f.start)
        end
        local base = seek and PAD or (PAD + #startBtns * (TIME_W + TIME_GAP) + TIME_SEP)
        for i, d in ipairs(durBtns) do
            d.b:ClearAllPoints()
            d.b:SetPoint("TOPLEFT", base + (i - 1) * (TIME_W + TIME_GAP), timingY)
            UI:SetSelected(d.b, d.seconds == f.ttl)
        end

        -- Sharing (#10): a group has the auto-invite and its hint; seeking has the chat box alone, moved up.
        local sy = timingY - 22 - 12
        sharingLabel:ClearAllPoints()
        sharingLabel:SetPoint("TOPLEFT", PAD, sy)
        sy = sy - 16
        chat:ClearAllPoints()
        chat:SetPoint("TOPLEFT", PAD - 2, sy)
        sy = sy - 26
        auto:SetShown(not seek)
        autoHint:SetShown(not seek)
        if not seek then
            auto:ClearAllPoints()
            auto:SetPoint("TOPLEFT", PAD - 2, sy)
            autoHint:ClearAllPoints()
            autoHint:SetPoint("TOPLEFT", PAD + 20, sy - 18)
            sy = sy - 40
        end
        hint:ClearAllPoints()
        hint:SetPoint("TOPLEFT", PAD, sy)

        -- What the post says, above Publish (#7).
        local line = {}
        if namesText then line[#line + 1] = namesText end
        if seek then
            line[#line + 1] = #picked > 0 and table.concat(picked, ", ") or L["Any"]
        elseif f.act then
            local needs = {}
            for _, letter in ipairs(LETTERS) do
                local n = f.need[letter] or 0
                if n > 0 then needs[#needs + 1] = string.format("%d %s", n, B:RoleName(ROLE_OF[letter])) end
            end
            line[#line + 1] = #needs > 0 and string.format(L["Need %s"], table.concat(needs, ", ")) or L["No open spots"]
            line[#line + 1] = (f.start or 0) > 0 and string.format(L["Starts in %d min"], math.floor(f.start / 60)) or L["Now"]
        end
        if namesText then line[#line + 1] = B:DurationName(f.ttl) end
        preview:SetText(table.concat(line, DOT))

        -- Publish is off until the form can post, and says why (#8).
        local reason
        if not seek then
            if not f.act then reason = L["Pick an activity first"]
            elseif total == 0 then reason = L["Add at least one open spot"] end
        end
        hint:SetText(reason or "")
        local listed = (seek and B:Mine() ~= nil) or (not seek and G:Mine() ~= nil)
        publish.label:SetText(listed and L["Update"] or L["Publish"])
        down:SetShown(listed)
        if reason then publish:Disable() else publish:Enable() end
    end

    function f:SetMode(mode)
        self.mode = mode
        B:SetPref("lastMode", mode)
        hint:SetText("")
        paint()
    end
    function f:SetDuration(seconds)
        self.ttl = seconds
        paint()
    end
    -- One spot more or less, never past the room a group of this size has besides its leader.
    function f:Step(letter, by)
        local want = {}
        for _, k in ipairs(LETTERS) do want[k] = self.need[k] or 0 end
        want[letter] = math.max(0, want[letter] + by)
        if G:OpenSpots(want) > G:SizeOf(self.act) - 1 then return end
        self.need = want
        paint()
    end

    onlyBtn:SetScript("OnClick", function()
        f.acts = { f.picked }
        paint()
    end)
    down:SetScript("OnClick", function()
        if f.mode == "seek" then B:ClearAvailable() else G:Disband() end
        f:Hide()
    end)

    -- After a post: the line says what went out, and the composer closes a moment later (#20). A
    -- change made in that moment cancels the close.
    local function confirm(message)
        publish:Disable()
        preview:SetText(message)
        local stamp = {}
        f.posted = stamp
        C_Timer.After(1.5, function()
            if f.posted == stamp then
                f.posted = nil
                f:Hide()
            end
        end)
    end

    publish:SetScript("OnClick", function()
        local toGuild = B:Pref("postToGuild") and true or false
        if f.mode == "seek" then
            local roles = ""
            for _, letter in ipairs(LETTERS) do
                if chips[letter].on then roles = roles .. letter end
            end
            B:SetPref("roles", roles)
            B:SetAvailable(nil, note:GetText(), f.ttl, toGuild, roles, f.acts)
            local names = {}
            for _, id in ipairs(f.acts) do names[#names + 1] = B:ActivityName(id) end
            confirm(string.format(L["Posted. You're on the board for %s."],
                #names > 0 and table.concat(names, ", ") or L["Anything"]))
        else
            local ok, why = G:Create(f.act, f.need, note:GetText(), f.ttl, toGuild, f.start)
            if not ok then
                hint:SetText(why or "")
                return
            end
            rememberTiming(f.act, f.ttl, f.start, f.need)
            confirm(string.format(L["Posted. %s now has %d groups forming."],
                B:ActivityName(f.act), groupsForming({ f.act })))
        end
    end)

    -- Open on `act` (a tile), or on what I already have listed. `mode` nil is the one used last,
    -- unless I am leading a group, which is then what there is to change.
    function f:Open(act, mode)
        local mine, group = B:Mine(), G:Mine()
        mode = mode or (group and "group") or (mine and "seek") or B:Pref("lastMode") or "seek"
        self.picked = act
        self.acts = {}
        for _, id in ipairs(mine and mine.acts or {}) do self.acts[#self.acts + 1] = id end
        if act then
            local have = false
            for _, id in ipairs(self.acts) do have = have or id == act end
            if not have then self.acts[#self.acts + 1] = act end
            self.acts = B:_SanitizeActs(self.acts)
        end
        self.act = act or (group and group.act) or nil
        -- The group I lead, when the tile is its activity; else, for an activity I formed a group for
        -- before, the spots and timing I used then (#11); else the defaults.
        local useGroup = group and (not act or act == group.act)
        local saved = mode == "group" and not useGroup and self.act
            and GuildOS.db.lfgPrefs.perAct and GuildOS.db.lfgPrefs.perAct[self.act] or nil
        if useGroup then
            self.need = G:_SanitizeNeed(group.need)
        elseif saved then
            self.need = G:_SanitizeNeed(saved.need, G:SizeOf(self.act) - 1)
        else
            self.need = defaultNeed(self.act)
        end
        self.ttl = (saved and B:_ClampTtl(saved.ttl)) or B:_ClampTtl(GuildOS.db.lfgPrefs.lastTtl)
        -- A group I change keeps the start it has, to the second; a new one starts now, or as it did.
        self.start = (useGroup and G:StartsIn(group)) or (saved and saved.start) or 0
        local roles = (mine and mine.roles) or B:Pref("roles") or ""
        for _, letter in ipairs(LETTERS) do chips[letter]:SetOn(roles:find(letter, 1, true) ~= nil) end
        local current = (mode == "group" and group) or (mode == "seek" and mine) or nil
        note:SetText(current and current.note or "")
        chat.checkbox:SetChecked(B:Pref("postToGuild") and true or false)
        auto.checkbox:SetChecked(B:Pref("autoInvite") and true or false)
        hint:SetText("")
        self.posted = nil
        self.mode = mode
        paint()
        self:Show()
        self:Raise()
    end

    f.Repaint = paint
    return f
end

local function openComposer(act, mode)
    composer = composer or buildComposer()
    composer:Open(act, mode)
end

-- Opens the composer from outside the panel (the Tavern's Ride Out buttons).
function GuildOS.OpenGroupComposer(act, mode)
    openComposer(act, mode)
end

----------------------------------------------------------------------
-- The notice (#378): a small card at the top of the screen that goes away by itself. Two kinds,
-- which Modules/Groups.lua decides: a guildmate formed a group I fit ("group"), or somebody asks for
-- a spot in mine and I do not invite whoever asks ("request"). One at a time: the newer replaces it.
----------------------------------------------------------------------
local TOAST_W, TOAST_H = 330, 66
local TOAST_SECONDS = { group = 12, request = 30, expiring = 60 }
local toast
-- Groups that came while a notice was up wait here instead of stacking (oldest first); the card says how many.
local toastQueue, TOAST_QUEUE_MAX = {}, 8
local advanceToast   -- set below: shows the next waiting notice, if any

-- What the notice keeps between sessions: the sound, where I put it, and what I silenced.
local function tstate()
    local db = GuildOS.db
    if not db then return { mute = {}, quietUntil = 0 } end
    db.groupToast = db.groupToast or {}
    local st = db.groupToast
    if st.sound == nil then st.sound = true end
    st.mute = st.mute or {}
    st.quietUntil = st.quietUntil or 0
    return st
end
GuildOS.GroupToastState = tstate
local function nowSec() return (GetServerTime and GetServerTime()) or time() end

-- Where the card sits: where I last dropped it, else the top middle. `slide` lifts it for the slide-in.
local function toastPlace(t, slide)
    local pos = tstate().pos
    t:ClearAllPoints()
    if pos then
        t:SetPoint(pos[1], UIParent, pos[2], pos[3], pos[4] + 18 * (slide or 0))
    else
        t:SetPoint("TOP", UIParent, "TOP", 0, -110 + 18 * (slide or 0))
    end
end

-- The roles I could ask as in this group: its open ones, among mine (any, with none set).
local function askCandidates(n)
    local mine = GuildOS.LFGBoard:Pref("roles") or ""
    local out = {}
    for _, k in ipairs(LETTERS) do
        if ((n.need and n.need[k]) or 0) > 0 and (mine == "" or mine:find(k, 1, true)) then out[#out + 1] = k end
    end
    return out
end

-- Why I cannot ask for a spot in this group just now, or nil when I can.
local function askReason(n)
    local G, B = GuildOS.Groups, GuildOS.LFGBoard
    local g = GuildOS.db and GuildOS.db.lfgGroups and GuildOS.db.lfgGroups[n.key]
    if not (g and B:_IsActive(g, nowSec())) then return L["This group is gone"] end
    if GetNumGroupMembers and (GetNumGroupMembers() or 0) > 1 then return L["You're in a group"] end
    if G:Mine() then return L["You lead a group"] end
    local lvl = UnitLevel and UnitLevel("player")
    if not G:FitsLevel(n.act, lvl) then
        local it = GuildOS.GroupActivities and GuildOS.GroupActivities.byId[n.act]
        return (it and it.min and lvl and lvl < it.min) and L["Too low for this one"] or L["Too high for this one"]
    end
    local asked = G:Asked(n.key)
    if asked then return asked.state == "declined" and L["Declined"] or L["Already asked"] end
    if #askCandidates(n) == 0 then return L["No spot for your role"] end
    return nil
end

-- How well a waiting group suits me, so the best ones come up first: in my level range (not just near),
-- a role of mine, and room for more than one of me.
local function toastScore(n)
    local B, G = GuildOS.LFGBoard, GuildOS.Groups
    local score = 0
    local it = GuildOS.GroupActivities and GuildOS.GroupActivities.byId[n.act]
    local lvl = UnitLevel and UnitLevel("player")
    if it and it.min and lvl and lvl >= it.min and lvl <= (it.max or it.min) then score = score + 2 end
    local mine = B:Pref("roles") or ""
    local role = G:BestRole(n.need, mine)
    if mine ~= "" and role then score = score + 2 end
    if role and ((n.need and n.need[role]) or 0) >= 2 then score = score + 1 end
    return score
end

local function buildToast()
    local t = CreateFrame("Button", "GuildOSGroupsToast", UIParent, "BackdropTemplate")
    t:SetSize(TOAST_W, TOAST_H)
    toastPlace(t, 0)
    t:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = UI:Edge(t) })
    t:SetBackdropColor(C.popup.r, C.popup.g, C.popup.b, 0.96)
    t:SetBackdropBorderColor(C.line.r, C.line.g, C.line.b, 1)
    t:SetFrameStrata("DIALOG")
    t:SetMovable(true)
    t:RegisterForDrag("LeftButton")
    t:SetScript("OnDragStart", function(self) self.moving = true; self:StartMoving() end)
    t:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        self.moving = false
        local point, rel, relPoint, x, y = self:GetPoint()
        if point and (rel == nil or rel == UIParent) then tstate().pos = { point, relPoint, x, y } end
    end)
    t.title = UI:CreateTitle(t, "", 12)
    t.title:SetPoint("TOPLEFT", 12, -8)
    t.title:SetWidth(TOAST_W - 40)
    t.title:SetJustifyH("LEFT")
    t.title:SetWordWrap(false)
    t.body = UI:CreateText(t, "", 11)
    t.body:SetPoint("TOPLEFT", 12, -26)
    t.body:SetWidth(TOAST_W - 24)
    t.body:SetJustifyH("LEFT")
    t.body:SetWordWrap(false)
    local close = UI:CreateCloseButton(t)
    close:SetPoint("TOPRIGHT", -4, -4)
    close:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    close:SetScript("OnClick", function(_, button)
        if button == "RightButton" and t.current and t.current.kind == "group" then
            t.menu:SetShown(not t.menu:IsShown())
            return
        end
        t.dismissed = true
        t:Hide()
    end)
    close:HookScript("OnEnter", function(self)
        if not (t.current and t.current.kind == "group") then return end
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOMRIGHT")
        GameTooltip:AddLine(L["Close"], 1, 1, 1)
        GameTooltip:AddLine(L["Right-click: mute or move"], 0.6, 0.6, 0.6)
        GameTooltip:Show()
    end)
    close:HookScript("OnLeave", function() GameTooltip:Hide() end)
    -- A group's card: a gold edge, the open roles as icons with counts, a pip for each place, and a thin
    -- bar that runs down as the card's time does. Only the "group" kind uses the roles and the pips.
    t.edge = t:CreateTexture(nil, "ARTWORK")
    t.edge:SetColorTexture(C.gold.r, C.gold.g, C.gold.b, 1)
    t.edge:SetPoint("TOPLEFT", 0, 0)
    t.edge:SetPoint("BOTTOMLEFT", 0, 0)
    t.edge:SetWidth(3)
    t.timer = t:CreateTexture(nil, "ARTWORK")
    t.timer:SetColorTexture(C.gold.r, C.gold.g, C.gold.b, 0.55)
    t.timer:SetHeight(2)
    t.timer:SetPoint("BOTTOMLEFT", 3, 0)
    t.roleRow = {}
    for i, letter in ipairs(LETTERS) do
        local r = { letter = letter }
        r.icon = t:CreateTexture(nil, "ARTWORK")
        r.icon:SetSize(16, 16)
        r.count = UI:CreateText(t, "", 11, C.text.r, C.text.g, C.text.b)
        r.count:SetPoint("LEFT", r.icon, "RIGHT", 3, 0)
        t.roleRow[i] = r
    end
    t.roleText = UI:CreateText(t, "", 11, C.textSoft.r, C.textSoft.g, C.textSoft.b)
    t.roleText:SetPoint("TOPLEFT", 12, -46)
    t.pips = {}
    t.pipText = UI:CreateText(t, "", 10, C.label.r, C.label.g, C.label.b)
    t.primary = UI:SetButtonVariant(UI:CreateButton(t, "", 110, 20), "primary")
    t.primary:SetPoint("BOTTOMRIGHT", -8, 8)
    t.secondary = UI:CreateButton(t, "", 90, 20)
    t.secondary:SetPoint("RIGHT", t.primary, "LEFT", -6, 0)
    -- The card itself opens the tab, where the rest is.
    t:SetScript("OnClick", function(self)
        self.dismissed = true
        self:Hide()
        GuildOS.LFGBoard:Show()
    end)
    -- "+2 more groups >" : the next waiting group, the one on show going to the back of the line.
    t.more = CreateFrame("Button", nil, t)
    t.more:SetSize(120, 16)
    t.more:SetPoint("BOTTOMLEFT", 12, 10)
    t.more.text = UI:CreateText(t.more, "", 10, C.textSoft.r, C.textSoft.g, C.textSoft.b)
    t.more.text:SetPoint("LEFT", 0, 0)
    t.more:SetScript("OnEnter", function(self) self.text:SetTextColor(C.gold.r, C.gold.g, C.gold.b) end)
    t.more:SetScript("OnLeave", function(self) self.text:SetTextColor(C.textSoft.r, C.textSoft.g, C.textSoft.b) end)
    t.more:SetScript("OnClick", function()
        if t.current and #toastQueue > 0 then
            toastQueue[#toastQueue + 1] = t.current
            local nxt = table.remove(toastQueue, 1)
            t.showNext(nxt)
        end
    end)
    t.more:Hide()
    -- Right-click on the X: silence this activity for a day, go quiet for half an hour, or put the card back.
    t.menu = CreateFrame("Frame", nil, t, "BackdropTemplate")
    t.menu:SetSize(176, 3 * 24 + 8)
    t.menu:SetPoint("TOPRIGHT", t, "BOTTOMRIGHT", 0, -2)
    t.menu:SetFrameStrata("DIALOG")
    t.menu:SetFrameLevel(t:GetFrameLevel() + 10)
    t.menu:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = UI:Edge(t.menu) })
    t.menu:SetBackdropColor(C.popup.r, C.popup.g, C.popup.b, 0.98)
    t.menu:SetBackdropBorderColor(C.line.r, C.line.g, C.line.b, 1)
    local function menuButton(i, onClick)
        local b = UI:CreateButton(t.menu, "", 168, 20)
        b:SetPoint("TOP", 0, -4 - (i - 1) * 24)
        b:SetScript("OnClick", function() t.menu:Hide(); onClick() end)
        return b
    end
    t.menuMute = menuButton(1, function()
        local n = t.current
        if not n then return end
        tstate().mute[n.act] = nowSec() + 86400
        for i = #toastQueue, 1, -1 do
            if toastQueue[i].act == n.act then table.remove(toastQueue, i) end
        end
        t:Hide()   -- the next waiting group comes in
    end)
    t.menuQuiet = menuButton(2, function()
        tstate().quietUntil = nowSec() + 1800
        t.dismissed = true
        t:Hide()
    end)
    t.menuReset = menuButton(3, function()
        tstate().pos = nil
        toastPlace(t, 0)
    end)
    t.menuQuiet.label:SetText(L["Quiet for 30 minutes"])
    t.menuReset.label:SetText(L["Put the card back"])
    t.menu:Hide()
    -- Click the icon on the Ask button to ask as another of the open roles.
    t.roleBtn = CreateFrame("Button", nil, t.primary)
    t.roleBtn:SetSize(22, 20)
    t.roleBtn:SetPoint("LEFT", 4, 0)
    t.roleBtn:SetFrameLevel(t.primary:GetFrameLevel() + 3)
    t.roleBtn:SetScript("OnClick", function()
        local n = t.current
        if not (n and n.kind == "group") then return end
        local list = askCandidates(n)
        if #list < 2 then return end
        local at = 1
        for i, k in ipairs(list) do if k == t.askRole then at = i end end
        t.askRole = list[at % #list + 1]
        t.paintAsk()
    end)
    t.roleBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine(L["Click to ask as another role"], 1, 1, 1)
        GameTooltip:Show()
    end)
    t.roleBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
    t.roleBtn:Hide()
    -- What the card does not have room for: the note, levels, how long ago it was listed.
    t:SetScript("OnEnter", function(self)
        local n = self.current
        if not (n and n.kind == "group") then return end
        local B, G = GuildOS.LFGBoard, GuildOS.Groups
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
        GameTooltip:AddLine(n.name .. " - " .. B:ActivityName(n.act), 1, 0.82, 0)
        local it = GuildOS.GroupActivities and GuildOS.GroupActivities.byId[n.act]
        if it and it.min then
            GameTooltip:AddLine(string.format(L["Levels %d-%d"], it.min, it.max or it.min), 0.8, 0.8, 0.8)
        end
        local rec = GuildOS.GetMemberRecord and GuildOS:GetMemberRecord(n.name)
        if rec and (rec.level or 0) > 0 then
            GameTooltip:AddLine(string.format(L["Leader is level %d"], rec.level), 0.8, 0.8, 0.8)
        end
        GameTooltip:AddLine(string.format(L["open: %s"], G:NeedText(n.need)), 0.8, 0.8, 0.8)
        local g = GuildOS.db and GuildOS.db.lfgGroups and GuildOS.db.lfgGroups[n.key]
        if g and g.ts then
            local mins = math.max(0, math.floor((nowSec() - g.ts) / 60))
            GameTooltip:AddLine(mins == 0 and L["Listed just now"] or string.format(L["Listed %d min ago"], mins), 0.6, 0.6, 0.6)
        end
        local note = n.note or (g and g.note)
        if note and note ~= "" then GameTooltip:AddLine(note, 1, 1, 1, true) end
        GameTooltip:AddLine(L["Click to open the Groups tab"], 0.6, 0.6, 0.6)
        GameTooltip:Show()
    end)
    t:SetScript("OnLeave", function() GameTooltip:Hide() end)
    -- A notice that goes (time, a button) lets the next one in; the X, or opening the tab, drops the rest.
    t:SetScript("OnHide", function(self)
        self.menu:Hide()
        GameTooltip:Hide()
        if self.dismissed then
            self.dismissed = nil
            wipe(toastQueue)
        else
            GuildOS.Compat.After(0.4, function() advanceToast() end)
        end
    end)
    -- the button that asks, with my role's icon on it
    t.primary.roleIcon = t.primary:CreateTexture(nil, "OVERLAY")
    t.primary.roleIcon:SetSize(14, 14)
    t.primary.roleIcon:SetPoint("LEFT", 8, 0)
    t.primary.roleIcon:Hide()
    t:Hide()
    return t
end

local function fitButton(b, text, letter)
    b.label:SetText(text)
    local extra = 0
    local shown = false
    if b.roleIcon then
        shown = letter and setRoleIcon(b.roleIcon, letter) or false
        if not shown then b.roleIcon:Hide() end
        extra = shown and 18 or 0
    end
    b.label:ClearAllPoints()
    b.label:SetPoint("CENTER", extra / 2, 0)
    b:SetWidth(math.max(70, math.ceil(b.label:GetStringWidth()) + 20 + extra))
end

-- Slide in and fade, a bar that runs down with the card's time, and a fade before it goes.
local TOAST_IN, TOAST_OUT = 0.25, 0.5
local function toastAnimate(t, seconds)
    t.born, t.life, t.placed, t.nextCheck = GetTime(), seconds, false, 0
    t:SetScript("OnUpdate", function(self)
        local age = GetTime() - self.born
        local alpha = math.min(1, age / TOAST_IN)
        local left = self.life - age
        if left < TOAST_OUT then alpha = math.min(alpha, math.max(0, left / TOAST_OUT)) end
        self:SetAlpha(alpha)
        local slide = math.max(0, 1 - age / TOAST_IN)
        if not self.moving then
            if slide > 0 then
                toastPlace(self, slide)
                self.placed = false
            elseif not self.placed then
                toastPlace(self, 0)
                self.placed = true
            end
        end
        -- The Ask button follows what is true now: a group joined, a level gained, a listing ended.
        if self.paintAsk and self.current and self.current.kind == "group" and GetTime() >= (self.nextCheck or 0) then
            self.nextCheck = GetTime() + 1
            self.paintAsk()
        end
        self.timer:SetWidth(math.max(1, (self:GetWidth() - 3) * math.max(0, left) / self.life))
        if left <= 0 then self:SetScript("OnUpdate", nil) end
    end)
end

-- The group card's second line: each open role as its icon and a count (or its words where the client has
-- no icons), and a pip for every place in the group, gold for the ones taken.
local function paintGroupCard(t, n, B, G)
    local roleCount, openTotal = 0, 0
    for _, k in ipairs(LETTERS) do openTotal = openTotal + ((n.need and n.need[k]) or 0) end
    local x = 12
    local art = roleArtKind()
    t.roleText:SetShown(not art)
    if art then
        for _, r in ipairs(t.roleRow) do
            local c = (n.need and n.need[r.letter]) or 0
            if c > 0 and setRoleIcon(r.icon, r.letter) then
                r.icon:ClearAllPoints()
                r.icon:SetPoint("TOPLEFT", x, -45)
                r.icon:Show()
                r.count:SetText("x" .. c)
                r.count:Show()
                x = x + 16 + 3 + math.ceil(r.count:GetStringWidth() or 12) + 10
            else
                r.icon:Hide()
                r.count:Hide()
            end
        end
    else
        for _, r in ipairs(t.roleRow) do r.icon:Hide(); r.count:Hide() end
        t.roleText:SetText(string.format(L["open: %s"], G:NeedText(n.need)))
    end
    -- The places: the group's size, the leader and whoever joined are taken, the open roles are not.
    local size = G:SizeOf(n.act)
    local open = math.min(openTotal, size)
    for _, pip in ipairs(t.pips) do pip:Hide() end
    t.pipText:ClearAllPoints()
    if size <= 10 then
        for i = 1, size do
            local pip = t.pips[i]
            if not pip then
                pip = t:CreateTexture(nil, "ARTWORK")
                pip:SetSize(8, 8)
                t.pips[i] = pip
            end
            local taken = i <= size - open
            pip:SetColorTexture(taken and C.gold.r or C.line.r, taken and C.gold.g or C.line.g, taken and C.gold.b or C.line.b, taken and 1 or 0.9)
            pip:ClearAllPoints()
            pip:SetPoint("TOPRIGHT", -12 - (size - i) * 11, -49)
            pip:Show()
        end
        t.pipText:SetText("")
    else
        t.pipText:SetText((size - open) .. "/" .. size)
        t.pipText:SetPoint("TOPRIGHT", -12, -47)
    end
end

local function showToast(n)
    local B, G = GuildOS.LFGBoard, GuildOS.Groups
    toast = toast or buildToast()
    toast.showNext = showToast
    toast.current = n
    toast.dismissed = nil
    toast.primary.roleIcon:Hide()
    toast.roleBtn:Hide()
    toast.menu:Hide()
    toast.primary:Enable()
    toast.paintAsk = nil
    toast.primary.label:ClearAllPoints()
    toast.primary.label:SetPoint("CENTER", 0, 0)
    local key = n.key
    local isGroup = n.kind == "group"
    toast:SetHeight(isGroup and 96 or TOAST_H)
    toast.edge:SetColorTexture(C.gold.r, C.gold.g, C.gold.b, 1)
    for _, r in ipairs(toast.roleRow) do r.icon:Hide(); r.count:Hide() end
    for _, pip in ipairs(toast.pips) do pip:Hide() end
    toast.roleText:Hide()
    toast.pipText:SetText("")
    if n.kind == "group" then
        toast.title:SetText(L["Groups being formed"])
        toast.askRole = nil
        -- The leader in their class colour, the activity in gold.
        local who = n.name
        local rec = GuildOS.GetMemberRecord and GuildOS:GetMemberRecord(n.name)
        local classFile = rec and (rec.classFile or rec.class)
        if classFile and GuildOS.ClassColors and GuildOS.ClassColors[classFile] then
            who = "|cff" .. GuildOS:GetClassColorHex(classFile) .. n.name .. "|r"
        end
        toast.body:SetText(who .. "  " .. GuildOS.GoldEsc() .. B:ActivityName(n.act) .. "|r")
        paintGroupCard(toast, n, B, G)
        -- The Ask button: my role's icon on it (click the icon for another open role of mine), greyed
        -- with the reason when I cannot ask. Repainted every second while it is up.
        toast.paintAsk = function()
            local cur = toast.current
            if not (cur and cur.kind == "group") then return end
            local reason = askReason(cur)
            toast.primary:Show()
            if reason then
                fitButton(toast.primary, reason)
                toast.primary:Disable()
                toast.roleBtn:Hide()
                return
            end
            local list = askCandidates(cur)
            local ok = false
            for _, k in ipairs(list) do if k == toast.askRole then ok = true end end
            if not ok then toast.askRole = G:BestRole(cur.need, B:Pref("roles") or "") end
            fitButton(toast.primary, string.format(L["Ask as %s"], B:RoleName(ROLE_OF[toast.askRole] or "ANY")), toast.askRole)
            toast.primary:Enable()
            toast.roleBtn:SetShown(#list > 1)
        end
        toast.paintAsk()
        toast.primary:SetScript("OnClick", function()
            local role = toast.askRole
            toast:Hide()
            if role then G:RequestSpot(key, role) end
        end)
        fitButton(toast.secondary, L["Whisper"])
        toast.secondary:SetScript("OnClick", function()
            toast:Hide()
            whisper(n.name)
        end)
    elseif n.kind == "expiring" then
        -- My listing is about to end (#378): 30 minutes more, or down now.
        local group = n.what == "group"
        toast.title:SetText(L["Your listing ends soon"])
        toast.body:SetText(L["Your listing ends in 5 minutes."])
        fitButton(toast.primary, L["+30 min"])
        toast.primary:Show()
        toast.primary:SetScript("OnClick", function()
            toast:Hide()
            if group then G:Extend() else B:Extend() end
        end)
        fitButton(toast.secondary, L["Take down"])
        toast.secondary:SetScript("OnClick", function()
            toast:Hide()
            if group then G:Disband() else B:ClearAvailable() end
        end)
    else
        toast.title:SetText(L["Asking for a spot"])
        toast.body:SetText(string.format(L["%s asks for a spot in your group as %s."], n.name,
            B:RoleName(ROLE_OF[n.role])))
        fitButton(toast.primary, L["Invite"])
        toast.primary:Show()
        toast.primary:SetScript("OnClick", function()
            toast:Hide()
            G:Invite(key)
        end)
        fitButton(toast.secondary, L["Decline"])
        toast.secondary:SetScript("OnClick", function()
            toast:Hide()
            G:Decline(key)
        end)
    end
    local waiting = (n.kind == "group") and #toastQueue or 0
    toast.more:SetShown(waiting > 0)
    if waiting > 0 then
        toast.more.text:SetText(string.format(waiting == 1 and L["+%d more group >"] or L["+%d more groups >"], waiting))
    end
    local shownAt = GetTime()
    toast.shownAt = shownAt
    toast:Show()
    toastAnimate(toast, TOAST_SECONDS[n.kind])
    GuildOS.Compat.After(TOAST_SECONDS[n.kind], function()
        if toast and toast.shownAt == shownAt then toast:Hide() end
    end)
end

advanceToast = function()
    if toast and toast:IsShown() then return end
    -- In a group of my own now, or leading one: what waits is no use to me.
    if (GetNumGroupMembers and (GetNumGroupMembers() or 0) > 1) or GuildOS.Groups:Mine() then
        wipe(toastQueue)
        return
    end
    local B = GuildOS.LFGBoard
    while #toastQueue > 0 do
        local nxt = table.remove(toastQueue, 1)
        local g = GuildOS.db and GuildOS.db.lfgGroups and GuildOS.db.lfgGroups[nxt.key]
        if g and B:_IsActive(g, nowSec()) then return showToast(nxt) end   -- one that ended is skipped
    end
end

-- n = { kind, key, name, act?, need?, note?, role? }, from Modules/Groups.lua.
-- Groups that come while a notice is up wait their turn; a request or a warning goes first.
function GuildOS:GroupsToast(n)
    if not (n and n.kind and TOAST_SECONDS[n.kind]) then return end
    local st = tstate()
    if n.kind == "group" and (nowSec() < st.quietUntil or (st.mute[n.act] or 0) > nowSec()) then return end
    local up = toast and toast:IsShown() and toast.current
    -- A soft chime for a new group or a request, with the notice (Settings turns it off).
    local function chime()
        if st.sound ~= false and (n.kind == "group" or n.kind == "request") and PlaySound then
            pcall(PlaySound, (SOUNDKIT and (SOUNDKIT.UI_BNET_TOAST or SOUNDKIT.TELL_MESSAGE)) or 3081)
        end
    end
    if not up then chime(); return showToast(n) end
    if n.kind == "group" then
        if up.kind == "group" and up.key == n.key then return showToast(n) end
        local replaced = false
        for i, q in ipairs(toastQueue) do
            if q.key == n.key and q.kind == "group" then toastQueue[i] = n; replaced = true; break end
        end
        if not replaced and #toastQueue < TOAST_QUEUE_MAX then
            -- Best fit first, the older one ahead among equals.
            local score, at = toastScore(n), #toastQueue + 1
            for i, q in ipairs(toastQueue) do
                if toastScore(q) < score then at = i; break end
            end
            table.insert(toastQueue, at, n)
        end
        if up.kind == "group" then
            toast.more:Show()
            local w = #toastQueue
            toast.more.text:SetText(string.format(w == 1 and L["+%d more group >"] or L["+%d more groups >"], w))
        end
        return
    end
    chime()
    if up.kind == "group" then table.insert(toastQueue, 1, up) end
    showToast(n)
end

----------------------------------------------------------------------
-- The tab
----------------------------------------------------------------------
-- Guild members in my party, me included: the count a bounty clear is logged with.
local function partyOutlaws()
    local members = GuildOS.Compat.GroupRoster()
    local outlaws = IsInGuild() and 1 or 0
    for key in pairs(members) do
        if GuildOS.db.members and GuildOS.db.members[key] then outlaws = outlaws + 1 end
    end
    return outlaws
end

-- The activities on this week's Bounty Board, as a set of ids (EKO builds it; empty without EKO).
local function bountyActs()
    local EKO = GuildOS.EKO
    return (EKO and EKO.BountyActSet and EKO:BountyActSet()) or {}
end

function GuildOS:CreateGroupsPanel(parent)
    local B, G, Cat = GuildOS.LFGBoard, GuildOS.Groups, GuildOS.GroupActivities
    parent.activeSub = "active"
    -- With the game's icons a player's roles take three squares; spelled out they need the room.
    local rolesW = roleArtKind() and ROLE_ICONS_W or ROLES_W

    -- Sub-tabs. Anchored on the left only: UI:FlowBar reads GetWidth to wrap (as the Guild hub).
    local bar = CreateFrame("Frame", nil, parent)
    bar:SetPoint("TOPLEFT", 10, -8)
    bar:SetSize(400, TAB_H)
    UI:StyleSubTabBar(bar)
    local subTabs, subList = {}, {}

    -- Actions: what I play, listing myself, forming a group. Flush with the bar's left edge, UI.GAP
    -- under it, and ending UI.GAP short of its right edge, as every screen's content does (#371).
    local actions = CreateFrame("Frame", nil, parent)
    actions:SetPoint("TOPLEFT", bar, "BOTTOMLEFT", 0, -UI.GAP)
    actions:SetPoint("TOPRIGHT", bar, "BOTTOMRIGHT", -UI.GAP, -UI.GAP)
    actions:SetHeight(26)

    local rolesLabel = UI:CreateText(actions, L["I PLAY"], 11)   -- a form label (#371)
    rolesLabel:SetPoint("LEFT", 0, 0)
    local myChips = {}
    for i, letter in ipairs(LETTERS) do
        local chip = createRoleChip(actions, letter)
        if i == 1 then
            chip:SetPoint("LEFT", rolesLabel, "RIGHT", 8, 0)
        else
            chip:SetPoint("LEFT", myChips[LETTERS[i - 1]], "RIGHT", 4, 0)
        end
        myChips[letter] = chip
    end

    local groupBtn = UI:SetButtonVariant(UI:CreateButton(actions, L["+ Form a group"], 130, 26), "primary")
    groupBtn:SetPoint("RIGHT", 0, 0)
    local seekBtn = UI:CreateButton(actions, L["I am looking..."], 120, 26)
    seekBtn:SetPoint("RIGHT", groupBtn, "LEFT", -6, 0)

    -- The scroll child stops UI.SCROLL_GUTTER short of the frame (BindScrollChildWidth), so the frame
    -- reaches that far past the actions' right edge: the content then ends where the actions do, and
    -- nothing on its right (the scope button) runs under the bar (#371).
    local scroll, content = UI:CreateScrollFrame(parent, "GuildOSGroupsScroll")
    scroll:SetPoint("TOPLEFT", actions, "BOTTOMLEFT", 0, -UI.GAP)
    scroll:SetPoint("BOTTOMRIGHT", -(10 + UI.GAP - UI.SCROLL_GUTTER), 8)
    UI:BindScrollChildWidth(scroll, content)

    ------------------------------------------------------------------
    -- Pools
    ------------------------------------------------------------------
    local pools = {}
    local function acquire(kind, make)
        local pool = pools[kind]
        if not pool then
            pool = { used = 0, items = {} }
            pools[kind] = pool
        end
        pool.used = pool.used + 1
        local item = pool.items[pool.used]
        if not item then
            item = make()
            pool.items[pool.used] = item
        end
        item:Show()
        return item
    end
    local function releaseAll()
        for _, pool in pairs(pools) do
            for _, item in ipairs(pool.items) do item:Hide() end
            pool.used = 0
        end
    end

    local y, width = 0, 400
    local paint   -- forward: the handlers below repaint

    -- (#2) Search: filters the tiles and the lists by activity name. (#10) actFilter: the activity a
    -- tile opened, shown alone over Active until the Active tab is picked again.
    local search, actFilter = "", nil
    -- detailKey: the activity whose page is open in place of the cards. openWing: the dungeon whose
    -- wings a card has opened (one at a time).
    local detailKey, openWing = nil, nil
    local dropSort = "boss"   -- how a dungeon page lists its drops: "boss" (the default) or "type"
    local searchBox = CreateFrame("EditBox", nil, actions, "InputBoxTemplate")
    searchBox:SetAutoFocus(false)
    searchBox:SetHeight(22)
    searchBox:SetFontObject(GameFontHighlightSmall)
    searchBox:SetPoint("LEFT", myChips[LETTERS[#LETTERS]], "RIGHT", 14, 0)
    searchBox:SetPoint("RIGHT", seekBtn, "LEFT", -10, 0)
    searchBox:SetScript("OnTextChanged", function(self)
        search = (self:GetText() or ""):lower()
        GuildOS:SafeCall(function() paint() end)
    end)
    searchBox:SetScript("OnEscapePressed", function(self) self:SetText(""); self:ClearFocus() end)
    searchBox:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)

    -- A section title (#371): the shared one, held by a strip across the content so its rule reaches
    -- the right edge and goes with it when the pool hides it. The view's first title has no rule.
    -- Returns the strip, for what sits on the title's line (the scope button).
    local function head(text, extra)
        local strip = acquire("head", function()
            local s = CreateFrame("Frame", nil, content)
            s:SetHeight(18)
            s.title = UI:CreateSectionTitle(s, "", false)
            s.title:SetPoint("TOPLEFT", 0, 0)
            return s
        end)
        local first = y == 0
        if not first then y = y + HEAD_ABOVE end
        strip:ClearAllPoints()
        strip:SetPoint("TOPLEFT", 0, -y)
        strip:SetPoint("TOPRIGHT", 0, -y)
        strip.title.rule:SetShown(not first)
        strip.title:SetText(extra and (text .. "  |cff" .. string.format("%02x%02x%02x", C.label.r * 255, C.label.g * 255,
            C.label.b * 255) .. extra .. "|r") or text)
        y = y + HEAD_H
        return strip
    end

    -- What a view says when it has nothing to list: secondary text, not a heading (#371).
    local function line(text)
        local fs = acquire("line", function()
            local t = UI:CreateText(content, "", 11, C.textSoft.r, C.textSoft.g, C.textSoft.b)
            t:SetJustifyH("LEFT")
            return t
        end)
        fs:ClearAllPoints()
        fs:SetPoint("TOPLEFT", 0, -y)
        fs:SetWidth(math.max(10, width))
        fs:SetText(text)
        y = y + math.max(16, fs:GetStringHeight() or 16) + 6
    end

    local function smallButton(parentFrame, variant)
        local b = UI:CreateButton(parentFrame, "", 60, 20)
        if variant then UI:SetButtonVariant(b, variant) end
        return b
    end

    -- A button as wide as its label, never under the 60px of the others.
    local function fit(b, text)
        b.label:SetText(text)
        b:SetWidth(math.max(60, math.ceil(b.label:GetStringWidth() or 0) + 18))
        return b
    end

    -- Lay buttons out from a frame's right edge inwards; returns the width they took. `inset`: 6 inside
    -- a card's border, none on a bare row, which ends flush with the content's right edge (#371).
    local function rightAlign(frame, buttons, top, inset)
        local x = -(inset or 6)
        for _, b in ipairs(buttons) do
            b:ClearAllPoints()
            b:SetPoint("TOPRIGHT", frame, "TOPRIGHT", x, top)
            x = x - b:GetWidth() - 4
        end
        return -x
    end

    local function panelFrame()
        local f = CreateFrame("Frame", nil, content, "BackdropTemplate")
        f:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = GuildOS.UI:Edge(f) })
        f:SetBackdropColor(C.panel.r, C.panel.g, C.panel.b, 1)
        f:SetBackdropBorderColor(C.line.r, C.line.g, C.line.b, 1)
        return f
    end

    ------------------------------------------------------------------
    -- Active: my group and its queue, the groups being formed, who is looking
    ------------------------------------------------------------------
    local function requestRow(r, classByKey)
        local row = acquire("request", function()
            local f = CreateFrame("Frame", nil, content)
            f.name = UI:CreateText(f, "", 11)
            f.name:SetPoint("LEFT", 0, 0)
            f.state = UI:CreateText(f, "", 10, C.label.r, C.label.g, C.label.b)
            f.invite = smallButton(f)
            f.invite.label:SetText(L["Invite"])
            f.decline = smallButton(f)
            f.decline.label:SetText(L["Decline"])
            return f
        end)
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", 0, -y)
        row:SetPoint("TOPRIGHT", 0, -y)
        row:SetHeight(ROW_H)
        local ink = roleColor(r.role)
        row.name:SetText(coloured(r.name, classByKey[r.key]) .. "  " ..
            GuildOS:ColorText(B:RoleName(ROLE_OF[r.role]), ink.r, ink.g, ink.b))
        local taken = rightAlign(row, { row.decline, row.invite }, -2, 0)
        row.state:ClearAllPoints()
        row.state:SetPoint("RIGHT", row, "RIGHT", -(taken + 6), 0)
        row.state:SetText(r.state == "invited" and L["invited"] or "")
        oneLine(row.name, width - taken - 70)
        local key = r.key
        row.invite:SetScript("OnClick", function() G:Invite(key) end)
        row.decline:SetScript("OnClick", function() G:Decline(key) end)
        y = y + ROW_H
    end

    -- The activity's art as a band across a card's top, cut as the tiles cut it, over `well` where the
    -- client has no art for it; with the time the listing has left as a hairline under it (#378).
    local function addBand(f)
        f.band = f:CreateTexture(nil, "BACKGROUND", nil, 1)
        f.band:SetTexture(WHITE)
        f.band:SetVertexColor(C.well.r, C.well.g, C.well.b, 1)
        f.band:SetPoint("TOPLEFT", 1, -1)
        f.band:SetPoint("TOPRIGHT", -1, -1)
        f.band:SetHeight(BAND_H)
        f.art = f:CreateTexture(nil, "ARTWORK")
        f.art:SetAllPoints(f.band)
        f.art:SetTexCoord(0, 1, 0.08, 0.72)
        f.art:SetAlpha(ART_ALPHA)
        f.bandRule = UI:CreateSeparator(f)
        f.bandRule:SetPoint("TOPLEFT", f.band, "BOTTOMLEFT", 0, 0)
        f.bandRule:SetPoint("TOPRIGHT", f.band, "BOTTOMRIGHT", 0, 0)
        f.timeBar = f:CreateTexture(nil, "OVERLAY")
        f.timeBar:SetTexture(WHITE)
        f.timeBar:SetPoint("TOPLEFT", f.band, "BOTTOMLEFT", 0, 0)
        f.timeBar:SetHeight(K.TIME_BAR_H)
        f.title = UI:CreateText(f, "", 13)
        f.title:SetPoint("BOTTOMLEFT", f.band, "BOTTOMLEFT", 8, 6)
        f.range = UI:CreateText(f, "", 10, C.textSoft.r, C.textSoft.g, C.textSoft.b)
        f.range:SetPoint("TOPRIGHT", f.band, "TOPRIGHT", -6, -5)
        f.badge = UI:CreateBadge(f, "", C.ok)
        f.badge:SetPoint("TOPLEFT", f.band, "TOPLEFT", 6, -5)
        f.badge:Hide()
    end

    -- Paint a band: the art, the title, the range, an optional badge, and the time left as a share of
    -- the listing's whole duration (`label` ink, `warn` in its last ten minutes).
    local function paintBand(card, g, now, w, title, badgeText, badgeColor)
        local it = Cat.byId[g.act]
        if it and hasArt(it) then
            card.art:SetTexture(it.art)
            card.art:Show()
        else
            card.art:Hide()
        end
        card.title:SetText(title)
        oneLine(card.title, w - 16)
        card.range:SetText(rangeOf(it))
        if badgeText then
            card.badge:SetText(badgeText, badgeColor)
            card.badge:Show()
        else
            card.badge:Hide()
        end
        local total = math.max(1, g.ttl or 1)
        local left = math.max(0, (g.ts or now) + total - now)
        card.timeBar:SetWidth(math.max(1, (w - 2) * math.min(1, left / total)))
        local ink = left <= 600 and C.warn or C.label
        card.timeBar:SetVertexColor(ink.r, ink.g, ink.b, 0.9)
    end

    -- What a card says about time: how full, when it starts (if later), how long it stays up.
    local function whenText(g, now)
        local parts = { string.format("%d/%d", g.n or 1, g.max or 5) }
        if bountyActs()[g.act] and (g.n or 1) >= (g.max or 5) then parts[#parts + 1] = L["double points when full"] end
        local startIn = G:StartsIn(g, now)
        if startIn then parts[#parts + 1] = string.format(L["starts in %dm"], math.ceil(startIn / 60)) end
        parts[#parts + 1] = string.format(L["%dm"], B:_Remaining(g, now))
        return table.concat(parts, DOT)
    end

    -- One seat of a card, made the first time a card needs that many and kept with the card.
    local function slotOf(card, i)
        local s = card.slots[i]
        if not s then
            s = CreateFrame("Frame", nil, card, "BackdropTemplate")
            s:SetSize(SLOT, SLOT)
            s:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = GuildOS.UI:Edge(s) })
            s.icon = s:CreateTexture(nil, "ARTWORK")
            s.icon:SetPoint("TOPLEFT", 1, -1)
            s.icon:SetPoint("BOTTOMRIGHT", -1, 1)
            s.mark = UI:CreateText(s, "", 9)
            s.mark:SetPoint("CENTER", 0, 0)
            card.slots[i] = s
        end
        s:Show()
        return s
    end

    -- A seat somebody has (`letter` nil) is a solid block: the listing counts its members, never their
    -- roles, so it names none. An open one is an empty seat with the role it is for.
    local function paintSlot(s, letter)
        s.role, s.filled = letter, letter == nil
        if letter then
            s:SetBackdropColor(C.well.r, C.well.g, C.well.b, 1)
            s:SetBackdropBorderColor(C.line.r, C.line.g, C.line.b, 1)
            local drawn = setRoleIcon(s.icon, letter)
            local ink = roleColor(letter)
            s.mark:SetTextColor(ink.r, ink.g, ink.b)
            s.mark:SetText(drawn and "" or letter)
        else
            s:SetBackdropColor(C.label.r, C.label.g, C.label.b, 1)
            s:SetBackdropBorderColor(C.label.r, C.label.g, C.label.b, 1)
            s.icon:Hide()
            s.mark:SetText("")
        end
    end

    -- The seats: one a member, then one an open spot, by role, from `top`. `share` of the card at most,
    -- so what is missing stays legible beside them; a raid's surplus reads as "+N", open spots kept
    -- first. Returns the open roles and the x where the seats end.
    local function paintSeats(card, g, w, top, share)
        local open = {}
        for _, letter in ipairs(LETTERS) do
            for _ = 1, (g.need[letter] or 0) do open[#open + 1] = letter end
        end
        local members = g.n or 1
        local cap = math.max(1, math.floor((w - 20) * share / (SLOT + SLOT_GAP)))
        local showOpen = math.min(#open, cap)
        local showFilled = math.min(members, cap - showOpen)
        local hidden = (members - showFilled) + (#open - showOpen)
        local n = 0
        local function seat(letter)
            n = n + 1
            local s = slotOf(card, n)
            s:ClearAllPoints()
            s:SetPoint("TOPLEFT", 10 + (n - 1) * (SLOT + SLOT_GAP), -top)
            paintSlot(s, letter)
        end
        for _ = 1, showFilled do seat(nil) end
        for i = 1, showOpen do seat(open[i]) end
        for i = n + 1, #card.slots do card.slots[i]:Hide() end
        local after = 10 + n * (SLOT + SLOT_GAP) + 4
        card.more:ClearAllPoints()
        card.more:SetPoint("LEFT", card, "TOPLEFT", after, -(top + SLOT / 2))
        card.more:SetText(hidden > 0 and ("+" .. hidden) or "")
        if hidden > 0 then after = after + math.ceil(card.more:GetStringWidth() or 0) + 6 end
        return open, after
    end

    -- My group, as the leader sees it (#378): the band with when it starts, the seats, a bar of how
    -- full it is, and everything a leader does from here: change it, give it 30 minutes more, say it
    -- in guild chat now, run a ready check, take it down.
    local function leaderPanel(g, now)
        local card = acquire("mine", function()
            local f = panelFrame()
            addBand(f)
            f.slots = {}
            f.more = UI:CreateText(f, "", 10, C.labelDim.r, C.labelDim.g, C.labelDim.b)
            f.missing = UI:CreateText(f, "", 11, C.textSoft.r, C.textSoft.g, C.textSoft.b)
            f.fill = UI:CreateProgressBar(f, 100, 8)
            f.fill:SetPoint("TOPLEFT", 10, -K.FILL)
            f.fillText = UI:CreateText(f, "", 10, C.label.r, C.label.g, C.label.b)
            f.fillText:SetPoint("LEFT", f.fill, "RIGHT", 8, 0)
            f.meta = UI:CreateText(f, "", 11, C.textSoft.r, C.textSoft.g, C.textSoft.b)
            f.meta:SetPoint("TOPLEFT", 10, -K.META)
            f.down = fit(smallButton(f, "danger"), L["Take down"])
            f.down:SetScript("OnClick", function() G:Disband() end)
            f.edit = fit(smallButton(f), L["Change"])
            f.edit:SetScript("OnClick", function() openComposer(nil, "group") end)
            f.extend = fit(smallButton(f), L["+30 min"])
            f.extend:SetScript("OnClick", function() G:Extend() end)
            f.post = smallButton(f)
            f.post:SetScript("OnClick", function()
                G:PostNow()
                paint()
            end)
            f.ready = fit(smallButton(f), L["Ready check"])
            f.ready:SetScript("OnClick", function() G:ReadyCheck() end)
            return f
        end)
        -- Hung by both top corners (#371). My own group is told apart by the brighter `lineHi` border:
        -- gold is only for what is selected or focused.
        card:ClearAllPoints()
        card:SetPoint("TOPLEFT", 0, -y)
        card:SetPoint("TOPRIGHT", 0, -y)
        card:SetHeight(K.H)
        card:SetBackdropBorderColor(C.lineHi.r, C.lineHi.g, C.lineHi.b, 1)
        local startIn = G:StartsIn(g, now)
        local underThree = bountyActs()[g.act] and partyOutlaws() < 3
        local badge = startIn and string.format(L["starts in %dm"], math.ceil(startIn / 60)) or nil
        if underThree then badge = (badge and (badge .. DOT) or "") .. L["under 3 Outlaws: no bounty points"] end
        paintBand(card, g, now, width, string.format(L["Your group: %s"], B:ActivityName(g.act)),
            badge, underThree and C.danger or C.info)

        local open, after = paintSeats(card, g, width, K.SEATS, 0.6)
        card.missing:ClearAllPoints()
        card.missing:SetPoint("LEFT", card, "TOPLEFT", after, -(K.SEATS + SLOT / 2))
        card.missing:SetText(#open > 0 and string.format(L["missing %s"], G:NeedText(g.need)) or "")
        oneLine(card.missing, width - after - 10)

        local max = g.max or 5
        card.fill:SetWidth(math.max(60, math.floor(width * 0.4)))
        card.fill:SetProgress((g.n or 1) / max)
        card.fillText:SetText(string.format("%d/%d", g.n or 1, max))

        local parts = { string.format(L["%dm"], B:_Remaining(g, now)) }
        if (g.note or "") ~= "" then parts[#parts + 1] = g.note end
        card.meta:SetText(table.concat(parts, DOT))
        oneLine(card.meta, width - 20)

        local wait = B:GuildLineWait(now, "lastGroupLine")
        fit(card.post, wait > 0 and (L["Post in chat"] .. " (" .. string.format(L["in %dm"], math.ceil(wait / 60)) .. ")")
            or L["Post in chat"])
        if wait > 0 then card.post:Disable() else card.post:Enable() end
        local buttons = { card.down, card.edit, card.extend, card.post }
        if G:CanReadyCheck() then
            card.ready:Show()
            buttons[#buttons + 1] = card.ready
        else
            card.ready:Hide()
        end
        rightAlign(card, buttons, -K.ACT, 8)
        y = y + K.H + GAP
    end

    local function groupCard(g, now, classByKey, x, w, forMe)
        local card = acquire("group", function()
            local f = panelFrame()
            addBand(f)
            f.lead = UI:CreateText(f, "", 11)
            f.lead:SetPoint("TOPLEFT", 10, -ROW_LEAD)
            f.when = UI:CreateText(f, "", 10, C.labelDim.r, C.labelDim.g, C.labelDim.b)
            f.when:SetPoint("TOPRIGHT", -8, -(ROW_LEAD + 1))
            f.slots = {}
            f.more = UI:CreateText(f, "", 10, C.labelDim.r, C.labelDim.g, C.labelDim.b)
            f.missing = UI:CreateText(f, "", 11, C.textSoft.r, C.textSoft.g, C.textSoft.b)
            f.note = UI:CreateText(f, "", 11, C.textSoft.r, C.textSoft.g, C.textSoft.b)
            f.note:SetPoint("TOPLEFT", 10, -ROW_NOTE)
            f.status = UI:CreateText(f, "", 10, C.label.r, C.label.g, C.label.b)
            f.whisper = smallButton(f)
            f.whisper.label:SetText(L["Whisper"])
            f.cancel = smallButton(f)
            f.cancel.label:SetText(L["Take it back"])
            f.join = {}
            for _, letter in ipairs(LETTERS) do
                local b = smallButton(f)
                b.label:SetText(B:RoleName(ROLE_OF[letter]))
                local ink = roleColor(letter)
                b.baseLabelColor = { ink.r, ink.g, ink.b }
                UI:_ButtonState(b, "rest")
                f.join[letter] = b
            end
            return f
        end)
        card:ClearAllPoints()
        card:SetPoint("TOPLEFT", x, -y)
        card:SetSize(w, GROUP_H)

        -- The band: art, name and level range, as the activity's tile shows them, and "for you" on a
        -- group of my level with a spot in a role I play (#378).
        local bounty = bountyActs()[g.act]
        paintBand(card, g, now, w, B:ActivityName(g.act), forMe and L["for you"] or (bounty and L["Bounty"]) or nil, forMe and C.ok or C.label)

        -- Who leads, in their class colour; how full and for how long.
        local key, name = g.key, g.name
        card.when:SetText(whenText(g, now))
        card.lead:SetText(string.format(L["led by %s"], coloured(name, classByKey[key])))
        oneLine(card.lead, w - 20 - math.ceil(card.when:GetStringWidth() or 0) - 8)

        local open, after = paintSeats(card, g, w, ROW_SEATS, 0.5)
        card.missing:ClearAllPoints()
        card.missing:SetPoint("LEFT", card, "TOPLEFT", after, -(ROW_SEATS + SLOT / 2))
        card.missing:SetText(#open > 0 and string.format(L["missing %s"], G:NeedText(g.need)) or "")
        oneLine(card.missing, w - after - 8)

        card.note:SetText(g.note or "")
        oneLine(card.note, w - 20)

        -- The actions, as before #373: ask for a spot in a role it has open, or take the ask back.
        local asked = G:Asked(key)
        local buttons = { card.whisper }
        card.whisper:SetScript("OnClick", function() whisper(name) end)
        card.cancel:Hide()
        card.status:SetText("")
        for _, letter in ipairs(LETTERS) do card.join[letter]:Hide() end
        if asked and asked.state == "pending" then
            card.cancel:Show()
            card.cancel:SetScript("OnClick", function() G:CancelRequest(key) end)
            buttons[#buttons + 1] = card.cancel
            card.status:SetText(string.format(L["asked as %s"], B:RoleName(ROLE_OF[asked.role])))
        elseif asked then
            card.status:SetText(L["no spot for you"])
        else
            for i = #LETTERS, 1, -1 do
                local letter = LETTERS[i]
                if (g.need[letter] or 0) > 0 then
                    local b = card.join[letter]
                    b:Show()
                    b:SetScript("OnClick", function() G:RequestSpot(key, letter) end)
                    buttons[#buttons + 1] = b
                end
            end
            card.status:SetText(L["ask for a spot as"])
        end
        rightAlign(card, buttons, -ROW_ACT, 8)
        -- Over the buttons, the card's width to itself: beside three Join buttons it had 20px and was
        -- hidden, on the composer's most common group (#373).
        card.status:ClearAllPoints()
        card.status:SetPoint("TOPLEFT", 10, -ROW_STATUS)
        oneLine(card.status, w - 20)
        card.status:Show()
    end

    -- The cards wrap, two or three a row, each as wide as the row allows.
    local function groupGrid(groups, now, classByKey, forMe)
        local cols = math.max(1, math.min(3, math.floor((width + GAP) / (GROUP_MIN_W + GAP))))
        local w = math.floor((width - GAP * (cols - 1)) / cols)
        local shown = math.min(#groups, GROUPS_MAX)
        for i = 1, shown do
            local col = (i - 1) % cols
            if col == 0 and i > 1 then y = y + GROUP_H + GAP end
            groupCard(groups[i], now, classByKey, col * (w + GAP), w, forMe[groups[i].key])
        end
        if shown > 0 then y = y + GROUP_H + GAP end
        if #groups > shown then line(string.format(L["... and %d more."], #groups - shown)) end
    end

    -- The levels of the guildmates online, keyed as the board keys them (LFGBoard:_BuildOnlineRoster):
    -- the roster already has them, so a row can say a player's level without asking anybody.
    local function rosterLevels()
        local out = {}
        for i = 1, GetNumGuildMembers() or 0 do
            local full, _, _, level, _, _, _, _, isOnline = GetGuildRosterInfo(i)
            if full and isOnline and type(level) == "number" and level > 0 then
                local short = full:match("^([^-]+)") or full
                out[GuildOS:GetPlayerKey(short, full:match("-(.+)$") or GetRealmName())] = level
            end
        end
        return out
    end

    -- A player looking, as a card (#379): class colour down the left edge, name and level, roles and what
    -- they want, a bar for how much of the listing is left, and Invite. Someone who fits my group is outlined
    -- in gold and says so; my own card gives the listing 30 minutes more.
    local function seekerRow(e, now, classByKey, levelByKey, mine, fitKeys)
        local CARD_H, BAR_W = 52, 60
        local row = acquire("seeker", function()
            local f = CreateFrame("Frame", nil, content, "BackdropTemplate")
            f:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = GuildOS.UI:Edge(f) })
            f:SetBackdropColor(C.well.r, C.well.g, C.well.b, 1)
            f.accent = f:CreateTexture(nil, "ARTWORK")
            f.accent:SetTexture(WHITE)
            f.accent:SetPoint("TOPLEFT", 0, 0)
            f.accent:SetPoint("BOTTOMLEFT", 0, 0)
            f.accent:SetWidth(3)
            f.class = f:CreateTexture(nil, "ARTWORK")
            f.class:SetSize(ICON, ICON)
            f.class:SetPoint("TOPLEFT", 12, -8)
            f.nameBtn = CreateFrame("Button", nil, f)
            f.nameBtn:SetPoint("TOPLEFT", 12 + ICON + 6, -7)
            f.nameBtn:SetSize(NAME_W, 18)
            f.name = UI:CreateText(f.nameBtn, "", 12)
            f.name:SetPoint("LEFT")
            oneLine(f.name, NAME_W - 6)
            f.level = UI:CreateText(f, "", 10, C.label.r, C.label.g, C.label.b)
            f.level:SetPoint("TOPLEFT", f.nameBtn, "TOPLEFT", NAME_W + 4, -5)
            f.roleIcons = {}
            for i = 1, #LETTERS do
                local t = f:CreateTexture(nil, "ARTWORK")
                t:SetSize(ICON, ICON)
                t:SetPoint("TOPLEFT", f.nameBtn, "TOPLEFT", NAME_W + LEVEL_W + (i - 1) * (ICON + 2), -6)
                t:Hide()
                f.roleIcons[i] = t
            end
            f.roles = UI:CreateText(f, "", 11, C.textSoft.r, C.textSoft.g, C.textSoft.b)
            f.roles:SetPoint("TOPLEFT", f.nameBtn, "TOPLEFT", NAME_W + LEVEL_W, -6)
            f.what = UI:CreateText(f, "", 11, C.label.r, C.label.g, C.label.b)
            f.what:SetPoint("TOPLEFT", 12 + ICON + 6, -28)
            f.time = UI:CreateText(f, "", 10, C.labelDim.r, C.labelDim.g, C.labelDim.b)
            f.time:SetPoint("TOPRIGHT", -8, -6)
            f.fit = UI:CreateText(f, L["Fits your group"], 10, C.gold.r, C.gold.g, C.gold.b)
            f.fit:SetPoint("TOPRIGHT", f.time, "TOPLEFT", -8, 0)
            f.barBg = f:CreateTexture(nil, "ARTWORK")
            f.barBg:SetTexture(WHITE)
            f.barBg:SetSize(BAR_W, 4)
            f.barBg:SetPoint("TOPRIGHT", -8, -22)
            f.barBg:SetVertexColor(C.label.r, C.label.g, C.label.b, 0.2)
            f.barFill = f:CreateTexture(nil, "ARTWORK")
            f.barFill:SetTexture(WHITE)
            f.barFill:SetHeight(4)
            f.barFill:SetPoint("RIGHT", f.barBg, "RIGHT", 0, 0)
            f.barFill:SetVertexColor(C.ok.r, C.ok.g, C.ok.b, 1)
            f.invite = smallButton(f)
            f.invite.label:SetText(L["Invite"])
            f.invite:SetPoint("BOTTOMRIGHT", -8, 6)
            f.you = UI:CreateText(f, L["(you)"], 10, C.label.r, C.label.g, C.label.b)
            f.extend = fit(smallButton(f), L["+30 min"])
            f.extend:SetPoint("BOTTOMRIGHT", -8, 6)
            f.extend:SetScript("OnClick", function() B:Extend() end)
            return f
        end)
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", 0, -y)
        row:SetPoint("TOPRIGHT", 0, -y)
        row:SetHeight(CARD_H)
        local isMe = e.key ~= nil and e.key == mine
        -- An allied listing carries no key, so no class or level: those stay blank, never guessed.
        local allied = e.key == nil
        local classFile = e.key and classByKey[e.key]
        if classFile then
            local r, g, b = GuildOS:GetClassColor(classFile)
            row.accent:SetVertexColor(r, g, b, 1)
        else
            row.accent:SetVertexColor(C.label.r, C.label.g, C.label.b, 0.6)
        end
        local coords = classFile and CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[classFile]
        if coords then
            row.class:SetTexture(CLASS_ICONS)
            row.class:SetTexCoord(coords[1], coords[2], coords[3], coords[4])
            row.class:Show()
        else
            row.class:Hide()
        end
        local fits = not isMe and not allied and fitKeys and fitKeys[e.key]
        row:SetBackdropBorderColor(C.label.r, C.label.g, C.label.b, fits and 1 or 0.2)
        if fits then row:SetBackdropBorderColor(C.gold.r, C.gold.g, C.gold.b, 1) end
        row.name:SetText(coloured(e.name, classFile))
        local level = e.key and levelByKey[e.key]
        row.level:SetText(level and (L["Lv "] .. level) or "")
        -- The roles as the game's icons; spelled out where the client has none, and "Any" for none.
        local roles, shown = e.roles or "", 0
        if roleArtKind() then
            for _, letter in ipairs(LETTERS) do
                if roles:find(letter, 1, true) then
                    shown = shown + 1
                    setRoleIcon(row.roleIcons[shown], letter)
                end
            end
        end
        for i = shown + 1, #LETTERS do row.roleIcons[i]:Hide() end
        row.roles:SetText(shown > 0 and "" or roleNames(roles))
        row.nameBtn:EnableMouse(not isMe and not allied)
        local name = e.name
        row.nameBtn:SetScript("OnClick", function() whisper(name) end)
        row.invite:SetShown(not isMe and not allied)
        row.you:SetShown(isMe)
        row.extend:SetShown(isMe)
        if not isMe and not allied then
            row.invite:SetScript("OnClick", function() GuildOS.Compat.InviteUnit(name) end)
        end
        if isMe then
            row.you:ClearAllPoints()
            row.you:SetPoint("RIGHT", row.extend, "LEFT", -6, 0)
        end
        -- How much of the listing is left: its time against its length.
        local ttl = e.ttl or 600
        local left = e.ts and math.max(0, math.min(1, ((e.ts + ttl) - now) / ttl)) or 0
        row.barFill:SetWidth(math.max(1, 60 * left))
        row.time:SetText(string.format(L["%dm"], B:_Remaining(e, now)))
        row.fit:SetShown(fits and true or false)
        local what = e.guild and e.note or B:Describe(e)
        row.what:SetText(what ~= "" and what or L["Anything"])
        oneLine(row.what, width - 12 - ICON - 6 - 150)
        y = y + CARD_H + 6
    end

    -- Which activities a filter keeps (#378): its category, and with "my level only" those of my level.
    local function keeps(act, cat, levelOnly, myLevel)
        local it = Cat.byId[act]
        if cat ~= "all" and (not it or it.cat ~= cat) then return false end
        return not levelOnly or G:FitsLevel(act, myLevel)
    end
    -- A player looking with no activity named wants anything: every filter keeps them.
    local function keepsSeeker(e, cat, levelOnly, myLevel)
        if #(e.acts or {}) == 0 then return true end
        for _, act in ipairs(e.acts) do
            if keeps(act, cat, levelOnly, myLevel) then return true end
        end
        return false
    end

    -- Over Active (#378): how many groups, how many looking, how many for me, and the filters. On a
    -- narrow window the filters take a line of their own under the figures.
    local function summary(nGroups, nSeekers, nForMe)
        local strip = acquire("summary", function()
            local f = CreateFrame("Frame", nil, content)
            f.chips = {
                UI:CreateMetricChip(f, "0", L["groups forming"]),
                UI:CreateMetricChip(f, "0", L["looking"]),
                UI:CreateMetricChip(f, "0", L["for you"]),
            }
            for i, chip in ipairs(f.chips) do chip:SetPoint("TOPLEFT", (i - 1) * 110, 0) end
            f.filters = {}
            for _, def in ipairs(K.FILTERS) do
                local b = fit(smallButton(f), def.label)
                local key = def.key
                b:SetScript("OnClick", function()
                    B:SetPref("filterCat", key)
                    paint()
                end)
                f.filters[#f.filters + 1] = { key = key, button = b }
            end
            f.level = fit(smallButton(f), L["My level only"])
            f.level:SetScript("OnClick", function()
                B:SetPref("filterLevel", not B:Pref("filterLevel"))
                paint()
            end)
            return f
        end)
        strip.chips[1]:SetValue(tostring(nGroups))
        strip.chips[2]:SetValue(tostring(nSeekers))
        strip.chips[3]:SetValue(tostring(nForMe))
        local idle = nGroups == 0 and nSeekers == 0 and nForMe == 0
        for _, chip in ipairs(strip.chips) do chip:SetShown(not idle) end
        local cat = B:Pref("filterCat") or "all"
        local row = { strip.level }
        for i = #strip.filters, 1, -1 do row[#row + 1] = strip.filters[i].button end
        local need = 0
        for _, b in ipairs(row) do need = need + b:GetWidth() + 4 end
        local wide = width - 3 * 110 >= need
        local top = wide and 0 or -K.SUMMARY_H
        local x = 0
        for _, b in ipairs(row) do
            b:ClearAllPoints()
            b:SetPoint("TOPRIGHT", strip, "TOPRIGHT", x, top)
            x = x - b:GetWidth() - 4
        end
        for _, def in ipairs(strip.filters) do UI:SetSelected(def.button, def.key == cat) end
        UI:SetSelected(strip.level, B:Pref("filterLevel") and true or false)
        local h = wide and K.SUMMARY_H or (K.SUMMARY_H + K.FILTER_H + 4)
        strip:ClearAllPoints()
        strip:SetPoint("TOPLEFT", 0, -y)
        strip:SetPoint("TOPRIGHT", 0, -y)
        strip:SetHeight(h)
        y = y + h + GAP
    end

    -- A player looking who fits my group (#378): who, their level, the role they would take, what they
    -- wrote, and one click to invite them in that role.
    local function matchRow(m, classByKey, levelByKey)
        local row = acquire("match", function()
            local f = CreateFrame("Frame", nil, content)
            f.name = UI:CreateText(f, "", 11)
            f.name:SetPoint("LEFT", 0, 0)
            f.what = UI:CreateText(f, "", 11, C.label.r, C.label.g, C.label.b)
            f.invite = smallButton(f, "primary")
            f.rule = UI:CreateSeparator(f)
            f.rule:SetPoint("BOTTOMLEFT", 0, 0)
            f.rule:SetPoint("BOTTOMRIGHT", 0, 0)
            f.rule:SetAlpha(0.4)
            return f
        end)
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", 0, -y)
        row:SetPoint("TOPRIGHT", 0, -y)
        row:SetHeight(ROW_H)
        local level = levelByKey[m.key]
        local ink = roleColor(m.role)
        row.name:SetText(coloured(m.name, classByKey[m.key]) .. (level and ("  |cff999999" .. L["Lv "] .. level .. "|r") or ""))
        oneLine(row.name, NAME_W + LEVEL_W)
        fit(row.invite, string.format(L["Invite as %s"], GuildOS:ColorText(B:RoleName(ROLE_OF[m.role]), ink.r, ink.g, ink.b)))
        local taken = rightAlign(row, { row.invite }, -2, 0)
        local what = B:Describe(m.entry)
        row.what:ClearAllPoints()
        row.what:SetPoint("LEFT", NAME_W + LEVEL_W + 8, 0)
        row.what:SetText(what ~= "" and what or L["Anything"])
        oneLine(row.what, width - NAME_W - LEVEL_W - taken - 16)
        local key, name, role = m.key, m.name, m.role
        row.invite:SetScript("OnClick", function() G:InviteSeeker(key, name, role) end)
        y = y + ROW_H
    end

    -- On its section title's line, flush with the content's right edge, which already stops clear of
    -- the scroll bar (#371).
    local function scopeButton(strip)
        local b = acquire("scope", function()
            local s = smallButton(content)
            s:SetScript("OnClick", function()
                B:SetPref("allianceScope", not B:Pref("allianceScope"))
                paint()
            end)
            return s
        end)
        b.label:SetText(B:Pref("allianceScope") and L["Scope: Alliance"] or L["Scope: Guild"])
        b:ClearAllPoints()
        b:SetPoint("RIGHT", strip, "RIGHT", 0, 0)
    end

    -- (#2) Whether an activity's name matches the search box.
    local function matchesSearch(act)
        if search == "" then return true end
        local name = B:ActivityName(act) or act
        return tostring(name):lower():find(search, 1, true) ~= nil
    end

    -- (#2, #10) Whether a player looking is wanted here: by the tile's activity, or by the search.
    local function seekerKeeps(e)
        local acts = e.acts or {}
        if #acts == 0 then return true end
        if actFilter then
            for _, a in ipairs(acts) do if a == actFilter then return true end end
            return false
        end
        if search == "" then return true end
        for _, a in ipairs(acts) do if matchesSearch(a) then return true end end
        return false
    end

    -- (#18) An empty Active tab offers the dungeons this level can run, one click each. Pooled, as all rows.
    local function startRow(myLevel)
        local picks = {}
        for _, s in ipairs(Cat:Sections("dungeon")) do
            for _, it in ipairs(s.items) do
                if #picks < 3 and it.min and it.max and myLevel >= it.min and myLevel <= it.max then
                    picks[#picks + 1] = it
                end
            end
        end
        if #picks == 0 then return end
        local x = 0
        for _, it in ipairs(picks) do
            local b = acquire("start", function() return UI:CreateButton(content, "", 120, 22) end)
            b:ClearAllPoints()
            b:SetPoint("TOPLEFT", x, -y)
            fit(b, B:ActivityName(it.id))
            b:SetScript("OnClick", function() openComposer(it.id) end)
            x = x + b:GetWidth() + 6
        end
        y = y + 22 + GAP
    end

    local function paintActive()
        local now = GetServerTime()
        local onlineSet, classByKey = B:_BuildOnlineRoster()
        local mine = B:MyKey()
        local myLevel = UnitLevel("player") or 1
        local myRoles = B:Pref("roles") or ""
        local cat, levelOnly = B:Pref("filterCat") or "all", B:Pref("filterLevel") and true or false
        local known = false
        for _, def in ipairs(K.FILTERS) do known = known or def.key == cat end
        if not known then cat = "all" end
        local levelByKey = rosterLevels()
        -- (#20) What this view is.
        if actFilter then
            line(string.format(L["Showing %s only. Pick Active now for every group."], B:ActivityName(actFilter)))
        else
            line(L["Groups being formed right now, and players looking for one."])
        end

        -- The groups of others that pass the filter, those for me first (#378), then newest.
        local groups, forMe, nForMe = {}, {}, 0
        for _, g in ipairs(G:ActiveList(GuildOS.db.lfgGroups, now, onlineSet)) do
            if g.key ~= mine and keeps(g.act, cat, levelOnly, myLevel) and matchesSearch(g.act)
                and (not actFilter or g.act == actFilter) then
                groups[#groups + 1] = g
                if G:FitsMe(g, myLevel, myRoles) then
                    forMe[g.key] = true
                    nForMe = nForMe + 1
                end
            end
        end
        table.sort(groups, function(a, b)
            if (forMe[a.key] or false) ~= (forMe[b.key] or false) then return forMe[a.key] == true end
            if (a.ts or 0) ~= (b.ts or 0) then return (a.ts or 0) > (b.ts or 0) end
            return a.key < b.key
        end)

        local seekers = {}
        for _, e in ipairs(B:ActiveList(GuildOS.db.lfgBoard, now, onlineSet)) do
            if keepsSeeker(e, cat, levelOnly, myLevel) and seekerKeeps(e) then seekers[#seekers + 1] = e end
        end
        local ally = GuildOS.Alliance
        local inAlliance = ally and ally:Get() ~= nil
        if inAlliance and B:Pref("allianceScope") then
            for _, row in ipairs(B:AllianceList(now)) do seekers[#seekers + 1] = row end
        end

        summary(#groups, #seekers, nForMe)

        local fitKeys = {}
        local myGroup = G:Mine()
        if myGroup then
            leaderPanel(myGroup, now)
            local requests = G:Requests()
            if #requests == 0 then
                line(L["Nobody asked for a spot yet. Guildmates see your group here and in the tiles."])
            else
                head(L["Asking for a spot"], tostring(#requests))
                for _, r in ipairs(requests) do requestRow(r, classByKey) end
                y = y + GAP
            end
            -- Who is looking and would fit (#378): the leader invites them without waiting to be asked.
            local matches = G:Matches(now, onlineSet)
            for _, m in ipairs(matches) do fitKeys[m.key] = true end
            if #matches > 0 then
                head(L["Fits your group"], tostring(#matches))
                for i = 1, math.min(#matches, SEEKERS_MAX) do matchRow(matches[i], classByKey, levelByKey) end
                y = y + GAP
            end
        end

        head(L["Groups being formed"], tostring(#groups))
        if #groups == 0 then
            local bountyLine = GuildOS.EKO and GuildOS.EKO.BountyNames and GuildOS.EKO:BountyNames()
            if bountyLine then line(string.format(L["Bounty Board this week: %s. Form a group for one."], bountyLine)) end
            line(L["No group is being formed right now. Pick an activity to start one."])
        else
            groupGrid(groups, now, classByKey, forMe)
        end

        local strip = head(L["Looking for a group"], tostring(#seekers))
        if inAlliance then scopeButton(strip) end
        if #seekers == 0 then
            line(L["Nobody is available right now. Be the first!"])
            if #groups == 0 and not actFilter and search == "" then startRow(myLevel) end
            return
        end
        -- Grouped under the first activity each player named (#379); no activity named is "Anything".
        local buckets, order = {}, {}
        for _, e in ipairs(seekers) do
            local key = (e.acts and e.acts[1]) or ""
            if not buckets[key] then buckets[key] = {}; order[#order + 1] = key end
            table.insert(buckets[key], e)
        end
        local shown = 0
        for _, key in ipairs(order) do
            if shown >= SEEKERS_MAX then break end
            local list = buckets[key]
            head(key ~= "" and B:ActivityName(key) or L["Anything"], tostring(#list))
            for _, e in ipairs(list) do
                if shown >= SEEKERS_MAX then break end
                shown = shown + 1
                seekerRow(e, now, classByKey, levelByKey, mine, fitKeys)
            end
        end
        if #seekers > shown then line(string.format(L["... and %d more."], #seekers - shown)) end
    end

    ------------------------------------------------------------------
    -- Tiles
    ------------------------------------------------------------------
    -- A card's name: a wing is its own short name ("Library"), a dungeon card is the dungeon.
    local function labelOf(it)
        if it.isGroup then return it.name end
        if it.wing then return Cat:WingLabel(it) end
        return B:ActivityName(it.id)
    end

    -- A dungeon with wings, as one card: its name, the range of all its wings, and the wings as members.
    local BREAK = { brk = true }   -- in a list of cards: the next card starts a row
    local function wingCard(key)
        local g = Cat.wings[key]
        local members = {}
        for _, id in ipairs(g.ids) do members[#members + 1] = Cat.byId[id] end
        local first = members[1]
        local card = { isGroup = true, wing = key, id = "wings:" .. key, name = g.name, art = first.art,
            size = first.size, cat = first.cat, members = members, min = first.min, max = first.max }
        for _, m in ipairs(members) do
            card.min = math.min(card.min, m.min)
            card.max = math.max(card.max, m.max)
        end
        return card
    end

    local function makeTile()
        local t = CreateFrame("Button", nil, content, "BackdropTemplate")
        t:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = GuildOS.UI:Edge(t) })
        t:SetBackdropColor(C.well.r, C.well.g, C.well.b, 1)
        t.art = t:CreateTexture(nil, "ARTWORK")
        t.art:SetPoint("TOPLEFT", 1, -1)
        t.art:SetPoint("BOTTOMRIGHT", -1, 1)
        t.art:SetTexCoord(0, 1, 0.08, 0.72)
        t.art:SetAlpha(ART_ALPHA)
        t.name = UI:CreateText(t, "", 12)   -- in `text`, set per tile below (#371)
        t.name:SetPoint("BOTTOMLEFT", 8, 6)
        t.name:SetJustifyH("LEFT")
        t.name:SetJustifyV("BOTTOM")
        t.name:SetWordWrap(true)
        t.level = UI:CreateText(t, "", 10, C.textSoft.r, C.textSoft.g, C.textSoft.b)
        t.level:SetPoint("TOPRIGHT", -6, -5)
        t.groups = UI:CreateText(t, "", 10, C.ok.r, C.ok.g, C.ok.b)
        t.groups:SetPoint("TOPLEFT", 8, -5)
        t.seekers = UI:CreateText(t, "", 10, C.info.r, C.info.g, C.info.b)
        -- (#10) Its own Form button: the tile shows its groups, Form starts one.
        t.form = UI:SetButtonVariant(UI:CreateButton(t, L["Form"], 56, 20), "primary")
        t.form:SetPoint("BOTTOMRIGHT", -5, 5)
        t.form:SetScript("OnClick", function() if t.id then openComposer(t.id) end end)
        t:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        -- Left-click opens the activity's page (its description, bosses and loot). A card of several
        -- wings opens or shuts them instead. Right-click whispers the leader of the first group forming (#11).
        t:SetScript("OnClick", function(self, button)
            if button == "RightButton" then
                if self.first then whisper(self.first.key) end
            elseif self.isGroup then
                openWing = (openWing ~= self.wing) and self.wing or nil
                GuildOS:SafeCall(paint)
            else
                detailKey = self.id
                scroll:SetVerticalScroll(0)
                GuildOS:SafeCall(paint)
            end
        end)
        -- Hovered, a tile lights its border as a secondary button does (`label`): gold is for selection.
        t:SetScript("OnEnter", function(self)
            self:SetBackdropBorderColor(C.label.r, C.label.g, C.label.b, 1)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:AddLine(self.title, GuildOS.Tip.text.r, GuildOS.Tip.text.g, GuildOS.Tip.text.b)
            if self.detail then GameTooltip:AddLine(self.detail, 1, 1, 1) end
            for _, txt in ipairs(self.lines or {}) do GameTooltip:AddLine(txt, 0.8, 0.8, 0.8) end
            if self.isGroup then
                GameTooltip:AddLine(L["Click to see its wings."], GuildOS.Tip.label.r, GuildOS.Tip.label.g, GuildOS.Tip.label.b, true)
            else
                GameTooltip:AddLine(L["Click for its description, bosses and loot. Form starts yours."], GuildOS.Tip.label.r, GuildOS.Tip.label.g, GuildOS.Tip.label.b, true)
            end
            if self.first then
                GameTooltip:AddLine(L["Right-click to whisper the first leader."], GuildOS.Tip.label.r, GuildOS.Tip.label.g, GuildOS.Tip.label.b, true)
            end
            GameTooltip:Show()
        end)
        t:SetScript("OnLeave", function(self)
            local e = self.edge or C.line
            self:SetBackdropBorderColor(e.r, e.g, e.b, 1)
            GameTooltip:Hide()
        end)
        return t
    end

    -- info: { c = the activity's counts, list = the groups forming for it, online = guildmates online in
    -- its range, bounty = on this week's Bounty Board }.
    local function tile(it, x, w, info, myLevel, now)
        local t = acquire("tile", makeTile)
        t:ClearAllPoints()
        t:SetPoint("TOPLEFT", x, -y)
        t:SetSize(w, TILE_H)
        -- (#6) Green border at my level, gold a few levels off, plain past that. Dimmed out of range.
        local exact = it.min and it.max and myLevel >= it.min and myLevel <= it.max
        local near = it.min and it.max and not exact and myLevel >= it.min and myLevel <= it.max + LEVEL_SLACK
        local edge = exact and C.ok or (near and C.label or C.line)
        t.edge = edge
        t:SetBackdropBorderColor(edge.r, edge.g, edge.b, 1)
        -- A tile with no art of its own (WoW: Forever's new dungeons) is a flat `panel` card (#371).
        local artOk = hasArt(it)
        local fill = artOk and C.well or C.panel
        t:SetBackdropColor(fill.r, fill.g, fill.b, 1)
        if artOk then
            t.art:SetTexture(it.art)
            t.art:Show()
        else
            t.art:Hide()
        end
        local name = labelOf(it)
        t.title, t.id = name, it.id
        t.isGroup, t.wing = it.isGroup, it.wing
        t.form:SetShown(not it.isGroup)
        t.name:SetWidth(w - 84)
        t.name:SetText(name)
        local range = rangeOf(it)
        t.level:SetText(range)
        local list = info.list or {}
        local details = {}
        if it.min then details[#details + 1] = string.format(L["Level %s"], range) end
        details[#details + 1] = string.format(L["%d players"], it.size)
        -- (#7) How far off my level it is.
        if it.min and it.max and myLevel < it.min then
            details[#details + 1] = string.format(L["%d levels to go"], it.min - myLevel)
        elseif it.min and it.max and myLevel > it.max then
            details[#details + 1] = string.format(L["%d levels over"], myLevel - it.max)
        end
        if info.online > 0 then details[#details + 1] = string.format(L["%d guildmates in range"], info.online) end
        if info.bounty then details[#details + 1] = L["Bounty this week"] end
        t.detail = table.concat(details, DOT)
        -- (#8, #12) The tooltip: the open spots, then the first groups forming for it.
        local open, soonest = {}, nil
        for _, g in ipairs(list) do
            for _, k in ipairs(LETTERS) do open[k] = (open[k] or 0) + ((g.need and g.need[k]) or 0) end
            local left = (g.ts or now) + (g.ttl or 0) - now
            if not soonest or left < soonest then soonest = left end
        end
        t.lines = {}
        local spots = G:NeedText(open)
        if #list > 0 and spots ~= "" then t.lines[#t.lines + 1] = string.format(L["Open: %s"], spots) end
        for i = 1, math.min(3, #list) do
            local g = list[i]
            t.lines[#t.lines + 1] = string.format("%s  %d/%d", g.name, g.n, g.max)
        end
        t.first = list[1]
        -- (#9) How long the soonest listing has left, beside the groups count.
        local c = info.c
        local gtext = (c and c.groups > 0) and string.format(L["%d forming"], c.groups) or ""
        if soonest and soonest > 0 then
            local left = string.format(L["%d min left"], math.max(1, math.floor(soonest / 60)))
            gtext = gtext ~= "" and (gtext .. DOT .. left) or left
        end
        t.groups:ClearAllPoints()
        t.groups:SetPoint("TOPLEFT", 8, -5)
        t.groups:SetText(gtext)
        t.seekers:ClearAllPoints()
        if gtext ~= "" then
            t.seekers:SetPoint("LEFT", t.groups, "RIGHT", 8, 0)
        else
            t.seekers:SetPoint("TOPLEFT", 8, -5)
        end
        t.seekers:SetText((c and c.seekers > 0) and string.format(L["%d looking"], c.seekers) or "")
        local mine = not it.min or (myLevel >= it.min and myLevel <= it.max + LEVEL_SLACK)
        t:SetAlpha(mine and 1 or OFF_LEVEL_ALPHA)
        local ink = mine and C.text or C.label   -- a dimmed tile's title steps down too (#371)
        t.name:SetTextColor(ink.r, ink.g, ink.b)
    end

    local function tileSection(title, items, cols, w, myLevel, now, infoOf)
        if #items == 0 then return end
        head(title)
        local n = 0   -- cards in the row being laid out
        for _, it in ipairs(items) do
            if it.brk then
                if n > 0 then y = y + TILE_H + GAP; n = 0 end
            else
                if n == cols then y = y + TILE_H + GAP; n = 0 end
                tile(it, n * (w + GAP), w, infoOf(it), myLevel, now)
                n = n + 1
            end
        end
        if n > 0 then y = y + TILE_H end
    end

    local function paintTiles(cat)
        local now = GetServerTime()
        local onlineSet = B:_BuildOnlineRoster()
        local counts = G:Counts(now, onlineSet)
        local listsBy = {}
        for _, g in ipairs(G:ActiveList(GuildOS.db.lfgGroups, now, onlineSet)) do
            listsBy[g.act] = listsBy[g.act] or {}
            listsBy[g.act][#listsBy[g.act] + 1] = g
        end
        local levels = rosterLevels()
        local bountyText = GuildOS.EKO and GuildOS.EKO.BountyNames and GuildOS.EKO:BountyNames()
        local bounties = bountyText and (", " .. bountyText:lower() .. ", ") or nil
        local myLevel = UnitLevel("player") or 1
        local cols = math.max(1, math.floor((width + GAP) / (TILE_MIN_W + GAP)))
        local w = math.floor((width - GAP * (cols - 1)) / cols)
        local function infoOf(it)
            local online = 0
            if it.min and it.max then
                for _, lvl in pairs(levels) do
                    if lvl >= it.min and lvl <= it.max then online = online + 1 end
                end
            end
            local dungeon = it.isGroup and it.name or (it.wing and Cat.wings[it.wing].name) or B:ActivityName(it.id)
            local bounty = bounties ~= nil and bounties:find(", " .. dungeon:lower() .. ", ", 1, true) ~= nil
            if not it.isGroup then
                return { c = counts[it.id], list = listsBy[it.id] or {}, online = online, bounty = bounty }
            end
            local c, list = { groups = 0, seekers = 0 }, {}
            for _, m in ipairs(it.members) do
                local cc = counts[m.id]
                if cc then
                    c.groups = c.groups + (cc.groups or 0)
                    c.seekers = c.seekers + (cc.seekers or 0)
                end
                for _, g in ipairs(listsBy[m.id] or {}) do list[#list + 1] = g end
            end
            return { c = c, list = list, online = online, bounty = bounty }
        end
        -- (#4) The busiest first; ties keep the catalogue's order.
        local function score(it)
            local c = counts[it.id]
            return c and (c.groups + c.seekers) or 0
        end
        local function ranked(items)
            local rows, seen = {}, {}
            for i, it in ipairs(items) do
                if it.wing then
                    if not seen[it.wing] then
                        seen[it.wing] = true
                        local card = wingCard(it.wing)
                        local s, match = 0, false
                        for _, m in ipairs(card.members) do
                            s = s + score(m)
                            match = match or matchesSearch(m.id)
                        end
                        if match then rows[#rows + 1] = { it = card, i = i, s = s } end
                    end
                elseif matchesSearch(it.id) then
                    rows[#rows + 1] = { it = it, i = i, s = score(it) }
                end
            end
            table.sort(rows, function(a, b)
                if a.s ~= b.s then return a.s > b.s end
                return a.i < b.i
            end)
            local out = {}
            for _, r in ipairs(rows) do
                out[#out + 1] = r.it
                if r.it.isGroup and openWing == r.it.wing then
                    out[#out + 1] = BREAK
                    for _, m in ipairs(r.it.members) do out[#out + 1] = m end
                    out[#out + 1] = BREAK
                end
            end
            return out
        end
        -- (#20, #6) What the numbers and the borders on a tile mean.
        line(L["Each card: groups forming, then players looking. Green border: your level. Click a card for its details, or Form to start a group."])
        local sections = Cat:Sections(cat)
        -- Dungeons open on what I can run now (#373): every tile whose range holds my level, once.
        if cat == "dungeon" then
            local mine, seen = {}, {}
            for _, s in ipairs(sections) do
                for _, it in ipairs(s.items) do
                    if it.min and it.max and myLevel >= it.min and myLevel <= it.max and not seen[it.id] then
                        seen[it.id] = true
                        mine[#mine + 1] = it
                    end
                end
            end
            tileSection(L["For your level"], ranked(mine), cols, w, myLevel, now, infoOf)
        end
        for _, s in ipairs(sections) do tileSection(s.title, ranked(s.items), cols, w, myLevel, now, infoOf) end
    end

    ------------------------------------------------------------------
    -- Painting
    ------------------------------------------------------------------
    ------------------------------------------------------------------
    -- A dungeon's page: its art, what it is, its bosses and what drops, with its groups a button away
    ------------------------------------------------------------------
    local DETAIL_BAND_H = 120
    local function paragraph(text, size, col)
        local fs = acquire("para" .. size, function()
            local t = UI:CreateText(content, "", size, C.text.r, C.text.g, C.text.b)
            t:SetJustifyH("LEFT")
            t:SetJustifyV("TOP")
            t:SetWordWrap(true)
            return t
        end)
        fs:ClearAllPoints()
        fs:SetPoint("TOPLEFT", 0, -y)
        fs:SetWidth(math.max(10, width))
        fs:SetTextColor(col.r, col.g, col.b)
        fs:SetText(text)
        y = y + math.max(14, fs:GetStringHeight() or 14) + 6
    end
    local function artBand(art)
        local f = acquire("band", function()
            local b = CreateFrame("Frame", nil, content)
            b.tex = b:CreateTexture(nil, "ARTWORK")
            b.tex:SetAllPoints()
            return b
        end)
        f:ClearAllPoints()
        f:SetPoint("TOPLEFT", 0, -y)
        f:SetSize(math.max(10, width), DETAIL_BAND_H)
        f.tex:SetTexture(art)
        f.tex:SetTexCoord(0, 1, 0.08, 0.72)
        f.tex:SetAlpha(ART_ALPHA)
        y = y + DETAIL_BAND_H + 10
    end
    -- The item of each drop name, for its icon and the game's own tooltip (as the character screen shows gear).
    -- The guild's gear scans first, with the links they saw; then the item IDs in Data/DropItemIds.lua. A name
    -- in neither stays text.
    local function knownItems()
        local index = {}
        for _, data in pairs(GuildOS.db and GuildOS.db.members or {}) do
            for _, item in pairs(data.gear or {}) do
                if item.name and item.name ~= "" and item.link and not index[item.name] then
                    index[item.name] = item
                end
            end
        end
        for name, id in pairs(GuildOS.DropItemIds or {}) do
            if not index[name] then index[name] = { link = "item:" .. id } end
        end
        return index
    end

    -- "Golemguard Chest (Mail, Chest)": the name, and the slot in brackets.
    local function dropParts(drop)
        local name = drop:match("^(.-) %(") or drop
        return name, drop:match("%(([^()]*)%)$")
    end

    -- By type: the armour material a drop is made of; weapons and off-hand pieces by their weapon word;
    -- the rest (rings, trinkets, capes, quest items) as Other.
    local ARMOUR = { cloth = "Cloth", leather = "Leather", mail = "Mail", plate = "Plate" }
    local WEAPON_WORDS = { "hand", "axe", "sword", "mace", "dagger", "staff", "bow", "wand", "gun", "polearm",
        "fist", "crossbow", "thrown", "shield", "relic" }
    local TYPE_ORDER = { "Cloth", "Leather", "Mail", "Plate", "Weapons and off-hand", "Other" }
    local ARMOUR_SUB = { [1] = "Cloth", [2] = "Leather", [3] = "Mail", [4] = "Plate" }
    -- The client's own item class, read without the item being cached: armour by its material, weapons
    -- and shields as off-hand. A drop without an item id falls back to its name's bracket.
    local function typeOf(drop, item)
        if item and item.link then
            local _, _, classID, subID = GuildOS.Compat.ItemInstant(item.link)
            if classID == 4 then
                if ARMOUR_SUB[subID] then return ARMOUR_SUB[subID] end
                if subID == 6 then return "Weapons and off-hand" end
                return "Other"
            elseif classID == 2 then
                return "Weapons and off-hand"
            end
        end
        local _, slot = dropParts(drop)
        if not slot then return "Other" end
        local first = (slot:match("^%s*([^,]-)%s*,") or slot:match("^%s*(.-)%s*$")):lower()
        if ARMOUR[first] then return ARMOUR[first] end
        local low = slot:lower()
        for _, word in ipairs(WEAPON_WORDS) do
            if low:find(word, 1, true) then return "Weapons and off-hand" end
        end
        return "Other"
    end

    -- A drop with a known item: its icon, its name in the quality colour, its slot, and the tooltip on hover.
    local function dropRow(drop, item, boss)
        local name, slot = dropParts(drop)
        local row = acquire("dloot", function()
            local r = CreateFrame("Button", nil, content)
            r:SetHeight(22)
            r:EnableMouse(true)
            r.icon = r:CreateTexture(nil, "ARTWORK")
            r.icon:SetSize(18, 18)
            r.icon:SetPoint("LEFT", 0, 0)
            r.text = UI:CreateText(r, "", 11, C.text.r, C.text.g, C.text.b)
            r.text:SetPoint("LEFT", r.icon, "RIGHT", 6, 0)
            r:SetScript("OnEnter", function(self)
                if not self.link then return end
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                GameTooltip:SetHyperlink(self.link)
                GameTooltip:Show()
            end)
            r:SetScript("OnLeave", function() GameTooltip:Hide() end)
            return r
        end)
        row.link = item.link
        local _, _, quality, _, _, _, _, _, _, texture = GuildOS.Compat.GetItemInfo(item.link)
        local _, instant = GuildOS.Compat.ItemInstant(item.link)
        row.icon:SetTexture(texture or instant or "Interface\\Icons\\INV_Misc_QuestionMark")
        local colour = ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[quality or item.quality or 1]
        if colour then row.text:SetTextColor(colour.r, colour.g, colour.b) end
        local parts = { name }
        if slot and slot ~= "" then parts[#parts + 1] = slot end
        if boss then parts[#parts + 1] = boss end
        row.text:SetText(table.concat(parts, DOT))
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", 12, -y)
        row:SetWidth(math.max(10, width - 12))
        y = y + 24
    end

    -- The two ways a dungeon page lists its drops, as two small switches on the Bosses heading.
    local function sortButtons(hd)
        local modes = { { "boss", L["By boss"] }, { "type", L["By type"] } }
        local right = -6
        for i = #modes, 1, -1 do
            local mode, text = modes[i][1], modes[i][2]
            local b = acquire("dsort-" .. mode, function() return UI:CreateButton(content, "", 90, 20) end)
            b.label:SetText(text)
            b:SetWidth(math.max(72, math.ceil(b.label:GetStringWidth() or 0) + 18))
            b:ClearAllPoints()
            b:SetPoint("TOPRIGHT", hd, "TOPRIGHT", right, -2)
            UI:SetSelected(b, dropSort == mode)
            b:SetScript("OnClick", function()
                dropSort = mode
                GuildOS:SafeCall(paint)
            end)
            right = right - b:GetWidth() - 6
        end
    end

    -- Every drop on the page, grouped by its armour type, each row naming the boss that drops it.
    local function paintByType(bosses, known)
        local groups = {}
        for _, key in ipairs(TYPE_ORDER) do groups[key] = {} end
        for _, boss in ipairs(bosses) do
            for _, drop in ipairs(boss.loot or {}) do
                local item = known[(dropParts(drop))]
                local g = groups[typeOf(drop, item)]
                g[#g + 1] = { drop = drop, boss = boss.name, item = item }
            end
        end
        for _, key in ipairs(TYPE_ORDER) do
            local g = groups[key]
            if #g > 0 then
                head(L[key], tostring(#g))
                for _, e in ipairs(g) do
                    if e.item then
                        dropRow(e.drop, e.item, e.boss)
                    else
                        paragraph(e.drop .. DOT .. e.boss, 11, C.label)
                    end
                end
                y = y + 6
            end
        end
    end

    local function paintDetail(id)
        local it = Cat.byId[id]
        local guide = (GuildOS.DungeonGuide and GuildOS.DungeonGuide[id]) or {}
        local back = acquire("dback", function() return UI:CreateButton(content, "", 100, 22) end)
        back.label:SetText(L["< Back"])
        back:SetWidth(math.max(80, math.ceil(back.label:GetStringWidth() or 0) + 18))
        back:ClearAllPoints()
        back:SetPoint("TOPLEFT", 0, -y)
        back:SetScript("OnClick", function()
            detailKey = nil
            scroll:SetVerticalScroll(0)
            GuildOS:SafeCall(paint)
        end)
        y = y + 30
        if hasArt(it) then artBand(it.art) end
        local title = acquire("ptitle", function() return UI:CreateText(content, "", 16, C.text.r, C.text.g, C.text.b) end)
        title:ClearAllPoints()
        title:SetPoint("TOPLEFT", 0, -y)
        title:SetWidth(math.max(10, width))
        title:SetText(B:ActivityName(id))
        y = y + 24
        local facts = {}
        if it.min then facts[#facts + 1] = string.format(L["Level %s"], rangeOf(it)) end
        facts[#facts + 1] = string.format(L["%d players"], it.size)
        paragraph(table.concat(facts, DOT), 11, C.textSoft)
        paragraph(guide.desc or L["No details for this one yet."], 12, C.text)
        local see = acquire("dsee", function() return UI:CreateButton(content, "", 120, 22) end)
        see.label:SetText(L["See its groups"])
        see:SetWidth(120)
        see:ClearAllPoints()
        see:SetPoint("TOPLEFT", 0, -y)
        see:SetScript("OnClick", function()
            actFilter = id
            parent.SelectSub("active")
        end)
        local form = acquire("dform", function() return UI:SetButtonVariant(UI:CreateButton(content, "", 120, 22), "primary") end)
        form.label:SetText(L["Form"])
        form:SetWidth(120)
        form:ClearAllPoints()
        form:SetPoint("LEFT", see, "RIGHT", 6, 0)
        form:SetScript("OnClick", function() openComposer(id) end)
        y = y + 30
        if guide.bosses and #guide.bosses > 0 then
            local hd = head(L["Bosses"])
            sortButtons(hd)
            local known = knownItems()
            if dropSort == "type" then
                paintByType(guide.bosses, known)
            else
                for _, boss in ipairs(guide.bosses) do
                    paragraph(boss.name .. (boss.note and ("  " .. DOT .. "  " .. boss.note) or ""), 12, C.text)
                    local unknown = {}
                    for _, drop in ipairs(boss.loot or {}) do
                        local item = known[(dropParts(drop))]
                        if item then dropRow(drop, item, nil) else unknown[#unknown + 1] = drop end
                    end
                    if #unknown > 0 then
                        paragraph(string.format(L["Drops: %s"], table.concat(unknown, ", ")), 11, C.label)
                    end
                    y = y + 6
                end
            end
        else
            head(L["Bosses"])
            line(L["No boss list yet."])
        end
        paragraph(L["Bosses and loot are from the standard game. WoW: Forever may differ."], 10, C.textSoft)
    end

    paint = function()
        if not parent:IsVisible() then return end
        B:Prune()
        G:Prune()
        releaseAll()
        -- Read only while shown (the early return above), and minus the gutter BindScrollChildWidth
        -- keeps, so the tiles and the text that is cut to fit stop clear of the scroll bar (#371).
        local w = scroll:GetWidth() or 0
        width = (w > 1 and w or 400) - UI.SCROLL_GUTTER
        content:SetWidth(width)
        -- (#3, #19) The sub-tabs say how much is on each, and how many are asking my group.
        local tnow = GetServerTime()
        local tonline = B:_BuildOnlineRoster()
        local tcounts = G:Counts(tnow, tonline)
        local perCat, total = {}, 0
        for act, c in pairs(tcounts) do
            local it = Cat.byId[act]
            local n = c.groups + c.seekers
            total = total + n
            if it then perCat[it.cat] = (perCat[it.cat] or 0) + n end
        end
        local asking = G:Mine() and #G:Requests() or 0
        for _, t in ipairs(SUBS) do
            local btn = subTabs[t.key]
            local n = t.key == "active" and total or (perCat[t.key] or 0)
            local text = t.label
            if t.key == "active" and asking > 0 then text = text .. string.format(" [%d asking]", asking) end
            if n > 0 then text = text .. " (" .. n .. ")" end
            btn.label:SetText(text)
            btn:SetWidth(math.max(TAB_MIN_W, math.ceil(btn.label:GetStringWidth()) + TAB_PAD))
        end
        UI:FlowBar(bar, subList, { gap = 4, rowGap = 4, rowH = TAB_H })

        y = 0
        if detailKey and Cat.byId[detailKey] then
            paintDetail(detailKey)
        elseif parent.activeSub == "active" then
            paintActive()
        else
            paintTiles(parent.activeSub)
        end
        content:SetHeight(math.max(1, y + 8))

        local roles = B:Pref("roles") or ""
        for _, letter in ipairs(LETTERS) do myChips[letter]:SetOn(roles:find(letter, 1, true) ~= nil) end
        seekBtn.label:SetText(B:Mine() and L["Stop looking"] or L["I am looking..."])
        groupBtn.label:SetText(G:Mine() and L["My group"] or L["+ Form a group"])
        if composer and composer:IsShown() then composer.Repaint() end
    end

    local function selectSub(key)
        detailKey = nil
        local known = false
        for _, t in ipairs(SUBS) do known = known or t.key == key end
        parent.activeSub = known and key or "active"
        for k, btn in pairs(subTabs) do btn:SetActive(k == parent.activeSub) end
        scroll:SetVerticalScroll(0)
        GuildOS:SafeCall(paint)
    end
    parent.SelectSub = selectSub   -- deep links: /gos avail, Guild > Call to Arms

    for _, t in ipairs(SUBS) do
        local btn = UI:CreateTab(bar, t.label, TAB_MIN_W, true)
        btn:SetWidth(math.max(TAB_MIN_W, math.ceil(btn.label:GetStringWidth()) + TAB_PAD))
        btn:SetScript("OnClick", function() actFilter = nil; selectSub(t.key) end)
        subTabs[t.key] = btn
        subList[#subList + 1] = btn
    end
    UI:FlowBar(bar, subList, { gap = 4, rowGap = 4, rowH = TAB_H })

    for _, letter in ipairs(LETTERS) do
        myChips[letter]:SetScript("OnClick", function()
            local roles, out = B:Pref("roles") or "", ""
            for _, k in ipairs(LETTERS) do
                local on = roles:find(k, 1, true) ~= nil
                if k == letter then on = not on end
                if on then out = out .. k end
            end
            B:SetPref("roles", out)
            GuildOS:SafeCall(paint)
        end)
    end
    seekBtn:SetScript("OnClick", function()
        if B:Mine() then B:ClearAvailable() else openComposer(nil, "seek") end
    end)
    groupBtn:SetScript("OnClick", function()
        if G:Mine() then
            openComposer(nil, "group")
        elseif parent.activeSub == "active" then
            -- A group is for something: the tiles are where that is picked.
            selectSub("dungeon")
        else
            openComposer(nil, "group")
        end
    end)

    -- The board's refresh hook: every change the modules make lands here.
    B.uiRefresh = paint

    parent:SetScript("OnShow", function() selectSub(parent.activeSub or "active") end)
    local since = 0
    parent:SetScript("OnUpdate", function(_, elapsed)
        since = since + elapsed
        if since < REPAINT_EVERY then return end
        since = 0
        GuildOS:SafeCall(paint)
    end)
    UI:MakeResponsive(parent, function(_, w)
        bar:SetWidth(math.max(TAB_MIN_W, w - 20))
        UI:FlowBar(bar, subList, { gap = 4, rowGap = 4, rowH = TAB_H })
        GuildOS:SafeCall(paint)
    end)
end
