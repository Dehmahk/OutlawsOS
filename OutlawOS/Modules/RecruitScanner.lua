----------------------------------------------------------------------
-- Guild OS - Recruit Scanner
-- Active recruiting: /who-scan unguilded candidates, mass-whisper a
-- template, capture replies. Officer-gated, OFF by default, fail-safe.
----------------------------------------------------------------------
local RecruitScanner = {}
GuildOS.RecruitScanner = RecruitScanner
local L = GuildOS.L

RecruitScanner.DEFAULTS = {
    template    = "Hi [player], we're recruiting — whisper me if interested!",
    minLevel    = 0,
    maxLevel    = GuildOS.Client.maxLevel,
    classes     = {},     -- set { WARRIOR=true }; empty = any
    batchMax    = 10,
    cooldownSec = 1800,
}

function RecruitScanner:Initialize()
    GuildOS.db.recruitScanner = GuildOS.db.recruitScanner or {}
    for k, v in pairs(self.DEFAULTS) do
        if GuildOS.db.recruitScanner[k] == nil then
            GuildOS.db.recruitScanner[k] = (type(v) == "table") and GuildOS:DeepCopy(v) or v
        end
    end
    GuildOS.db.recruitScanner.inbox = GuildOS.db.recruitScanner.inbox or {}
    self:_ExpireInbox()     -- replies from weeks ago are not applicants waiting (issue #311)
    self._results = {}
    -- EKO patch: remember who was whispered across reloads/logins, and skip them for 7 days.
    GuildOS.db.recruitScanner.cooldownSec = 7 * 24 * 3600
    GuildOS.db.recruitScanner.contacted = GuildOS.db.recruitScanner.contacted or {}
    local nowTs = GetServerTime()
    for k, untilTs in pairs(GuildOS.db.recruitScanner.contacted) do
        if type(untilTs) ~= "number" or untilTs <= nowTs then GuildOS.db.recruitScanner.contacted[k] = nil end
    end
    self._contactCd = GuildOS.db.recruitScanner.contacted
    self._RegisterEvents = self._RegisterEvents or function() end
    self:_RegisterEvents()      -- real body in Task 2 (until then, a stub below)
    self:_RegisterTests()
end

----------------------------------------------------------------------
-- Pure logic (unit-tested)
----------------------------------------------------------------------
function RecruitScanner:_ExpandTemplate(tmpl, cand)
    tmpl = tmpl or ""
    cand = cand or {}
    local out = tmpl
    out = out:gsub("%[player%]", cand.name or "")
    out = out:gsub("%[class%]", cand.class or "")
    out = out:gsub("%[level%]", tostring(cand.level or ""))
    return out
end

-- Who a candidate is to the scanner: the name it is selected, shown and whispered by. On retail
-- /who names a connected realm's player with their realm, and two namesakes differ only by it, so
-- it is the whole name /who gave; elsewhere the name alone, as before (issue #184).
function RecruitScanner:Addr(cand)
    return GuildOS.Client.isRetail and cand.full or cand.name
end

-- The key a contacted player's cooldown and reply are remembered under: the whole key on retail
-- (a name without a realm is this realm's), the name alone elsewhere (issue #184).
local function contactKey(name)
    if GuildOS.Client.isRetail then return GuildOS:KeyOfRosterName(name) end
    return name:match("^([^-]+)") or name
end

function RecruitScanner:_CandidateOK(cand, filters, isBannedFn)
    if not cand or not cand.name then return false end
    if cand.guilded then return false end                       -- unguilded only
    filters = filters or {}
    if (filters.minLevel or 0) > 0 and (cand.level or 0) < filters.minLevel then return false end
    if filters.maxLevel and (cand.level or 0) > filters.maxLevel then return false end
    if filters.classes and next(filters.classes) ~= nil and not filters.classes[cand.class] then return false end
    if isBannedFn and isBannedFn(cand.full or cand.name) then return false end   -- /who's realm too (#184)
    if RecruitScanner:_EkoRecentlyLeft(cand.name) then return false end   -- EKO patch
    -- EKO patch: hide anyone whispered in the last 7 days from the results.
    local ekoCd = RecruitScanner._contactCd and RecruitScanner._contactCd[contactKey(cand.name)]
    if ekoCd and ekoCd > GetServerTime() then return false end
    return true
end

-- EKO patch: true when the audit log shows this player leaving or being kicked in the last 30 days.
function RecruitScanner:_EkoRecentlyLeft(name)
    if not name then return false end
    local rl = GuildOS.db and GuildOS.db.rosterLog
    local store = rl and rl.events
    if not store then return false end
    local short = (name:match("^([^-]+)") or name):lower()
    local cutoff = GetServerTime() - 30 * 86400
    for i = #store, 1, -1 do
        local e = store[i]
        if (e.timestamp or 0) >= cutoff and (e.action == "leave" or e.action == "kick")
            and e.target and ((e.target:match("^([^-]+)") or e.target):lower() == short) then
            return true
        end
    end
    return false
end

----------------------------------------------------------------------
-- /who scan (fail-safe)
----------------------------------------------------------------------
function RecruitScanner:Scan(onDone)
    if not GuildOS:CanRecruit() then return end
    if self._scanBusy then return end
    self._scanBusy = true
    self._results = {}
    self._hiddenCount = 0
    self._whisperQueue = nil    -- a new scan drops a Forever batch left half sent (issue #61)
    local cfg = GuildOS.db.recruitScanner
    if not self._whoFrame then
        self._whoFrame = CreateFrame("Frame")
        self._whoFrame:SetScript("OnEvent", function() RecruitScanner:_OnWhoResult() end)
    end
    GuildOS.Compat.RegisterEvent(self._whoFrame, "WHO_LIST_UPDATE")
    self._onScanDone = onDone
    GuildOS.Compat.SetWhoToUI(true)
    -- level-range query; Blizzard caps results (~50). classes filtered post-hoc.
    -- Capped at the game's top: a Forever client saved 70 here before it knew its cap (issue #53).
    local cap = GuildOS.Client.maxLevel
    local q = string.format("%d-%d", (cfg.minLevel or 1) > 0 and cfg.minLevel or 1, math.min(cfg.maxLevel or cap, cap))
    GuildOS.Compat.SendWho(q)
    GuildOS.Compat.After(6, function()
        if RecruitScanner._scanBusy then RecruitScanner:_FinishScan() end
    end)
end

function RecruitScanner:_OnWhoResult()
    local cfg = GuildOS.db.recruitScanner
    local isBanned = function(n) return GuildOS.BanList and GuildOS.BanList:IsBanned(n) end
    local out, total = {}, 0
    if C_FriendList and C_FriendList.GetNumWhoResults then
        local n = C_FriendList.GetNumWhoResults() or 0
        for i = 1, n do
            local w = C_FriendList.GetWhoInfo(i)
            if w and w.fullName then
                total = total + 1
                local short = w.fullName:match("^([^-]+)") or w.fullName
                local cand = {
                    name = short, full = w.fullName, level = w.level, class = w.filename,
                    zone = w.area, guilded = (w.fullGuildName ~= nil and w.fullGuildName ~= ""),
                }
                if self:_CandidateOK(cand, cfg, isBanned) then out[#out + 1] = cand end
            end
        end
    end
    self._results = out
    self._hiddenCount = total - #out   -- EKO patch: shown next to "found" so the filters are visible
    self:_FinishScan()
end

function RecruitScanner:_FinishScan()
    if self._whoFrame then self._whoFrame:UnregisterEvent("WHO_LIST_UPDATE") end
    GuildOS.Compat.SetWhoToUI(false)
    self._scanBusy = nil
    if self._onScanDone then GuildOS:SafeCall(self._onScanDone) end
end

function RecruitScanner:GetResults() return self._results or {} end

----------------------------------------------------------------------
-- Mass-whisper (throttled, cooldown, batch-capped)
----------------------------------------------------------------------
function RecruitScanner:WhisperSelected(names)
    if not GuildOS:CanRecruit() then return end
    local cfg = GuildOS.db.recruitScanner
    local now = GetServerTime()
    local plan = {}
    for _, name in ipairs(names or {}) do
        if #plan >= (cfg.batchMax or 10) then break end
        local cd = self._contactCd[contactKey(name)]
        -- Banned again at the click: a ban may have arrived since the scan, and on retail a name
        -- without a realm is this realm's player, whoever the scan listed (issue #184).
        local banned = GuildOS.BanList and GuildOS.BanList:IsBanned(name)
        if not (cd and cd > now) and not banned then
            local cand
            for _, r in ipairs(self._results) do if self:Addr(r) == name then cand = r; break end end
            plan[#plan + 1] = { name = name, msg = self:_ExpandTemplate(cfg.template, cand or { name = name }) }
        end
    end
    -- EKO patch: say how many were skipped because they were already whispered.
    local ekoSkipped = math.min(#(names or {}), cfg.batchMax or 10) - #plan
    if ekoSkipped > 0 then
        GuildOS:Print(string.format("|cffFFD700EKO:|r skipped %d already whispered in the last 7 days.", ekoSkipped))
    end
    if #plan == 0 then return end
    if GuildOS.Compat.NeedsClick() then
        -- WoW: Forever drops a whisper sent from a timer (issue #61): the first goes out in
        -- this click, the rest one per click on "Whisper next".
        self._whisperQueue = plan
        self:WhisperNext()
        if #plan > 0 then
            GuildOS:Print(string.format(GuildOS.L["%d more: click Whisper next to send each one."], #plan))
        end
        return
    end
    for i, w in ipairs(plan) do
        self._contactCd[contactKey(w.name)] = now + (cfg.cooldownSec or 1800)
        GuildOS.Compat.After(i * 1.5, function()    -- throttle: 1.5s between whispers
            SendChatMessage(w.msg, "WHISPER", nil, w.name)
            if GuildOS.Office then GuildOS.Office:CountPitch() end   -- The Office: pitches this client sent
        end)
    end
    GuildOS:Print(string.format(GuildOS.L["Whispering %d candidate(s)…"], #plan))
end

-- Whispers waiting for a click (WoW: Forever).
function RecruitScanner:PendingWhispers()
    return self._whisperQueue and #self._whisperQueue or 0
end

-- The click: send the next whisper waiting. Returns how many are left.
function RecruitScanner:WhisperNext()
    local q = self._whisperQueue
    local w = q and table.remove(q, 1)
    if w then
        SendChatMessage(w.msg, "WHISPER", nil, w.name)
        if GuildOS.Office then GuildOS.Office:CountPitch() end   -- The Office
        self._contactCd[contactKey(w.name)] = GetServerTime() + ((GuildOS.db.recruitScanner or {}).cooldownSec or 1800)
    end
    return self:PendingWhispers()
end

----------------------------------------------------------------------
-- Reply inbox
----------------------------------------------------------------------
function RecruitScanner:_RegisterEvents()
    local f = CreateFrame("Frame")
    GuildOS.Compat.RegisterEvent(f, "CHAT_MSG_WHISPER")
    f:SetScript("OnEvent", function(_, _, msg, author)
        if GuildOS.Compat.IsSecret(msg, author) then return end  -- chat in lockdown: nothing readable
        local short = author and (author:match("^([^-]+)") or author)
        if short and RecruitScanner._contactCd[contactKey(author)] then
            local inbox = GuildOS.db.recruitScanner.inbox
            table.insert(inbox, 1, { name = short, msg = msg, ts = GetServerTime() })
            while #inbox > 200 do table.remove(inbox) end
        end
    end)
end

-- A reply stays in the inbox two weeks: kept forever, the Now tab's "applicants waiting" counted
-- every whisper ever received and never went away (issue #311).
RecruitScanner.INBOX_KEEP_SEC = 14 * 86400

function RecruitScanner:_ExpireInbox()
    local cfg = GuildOS.db and GuildOS.db.recruitScanner
    local inbox = cfg and cfg.inbox
    if type(inbox) ~= "table" then return end
    local cutoff = GetServerTime() - self.INBOX_KEEP_SEC
    for i = #inbox, 1, -1 do
        local e = inbox[i]
        if type(e) ~= "table" or (tonumber(e.ts) or 0) < cutoff then table.remove(inbox, i) end
    end
end

function RecruitScanner:GetInbox()
    self:_ExpireInbox()
    return (GuildOS.db.recruitScanner and GuildOS.db.recruitScanner.inbox) or {}
end

-- Opening the inbox view reads it: only replies newer than this count as waiting (issue #311).
function RecruitScanner:MarkInboxRead()
    local cfg = GuildOS.db and GuildOS.db.recruitScanner
    if cfg then cfg.inboxReadAt = GetServerTime() end
end

-- The inbox view's Clear button (issue #311).
function RecruitScanner:ClearInbox()
    local cfg = GuildOS.db and GuildOS.db.recruitScanner
    if not cfg then return end
    cfg.inbox = {}
    cfg.inboxReadAt = GetServerTime()
end

----------------------------------------------------------------------
-- Whisper-selected confirmation (standard Blizzard popup; avoids an
-- accidental mass-whisper). Registered once at file load — same pattern
-- as UI/CalendarPanel.lua's GUILDOS_CALENDAR_DELETE.
----------------------------------------------------------------------
if not GuildOS.Dialogs["GUILDOS_SCOUT_WHISPER_CONFIRM"] then
    GuildOS.Dialogs["GUILDOS_SCOUT_WHISPER_CONFIRM"] = {
        text = L["Whisper %d players?"],
        button1 = YES, button2 = NO,
        OnAccept = function(dlg, data, data2)
            local names = data or (dlg and dlg.data)
            if names then RecruitScanner:WhisperSelected(names) end
            -- Repaint the panel that asked, so a Forever batch shows "Whisper next" (issue #61).
            local refresh = data2 or (dlg and dlg.data2)
            if type(refresh) == "function" then GuildOS:SafeCall(refresh) end
        end,
        timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
    }
end

----------------------------------------------------------------------
-- UI (embeddable content + a self-contained popup wrapper — mirrors
-- Modules/Bulletin.lua:Show()). BuildInto() builds every scanner widget
-- as a child of whatever container it's given (the popup body, or a
-- Recruitment-tab sub-panel); Show() just supplies the popup chrome.
--
-- Layout (full-width; see docs/superpowers approved mock):
--   row 1  filters bar: min/max level, class cycle, Scan · "N found" (right)
--   ------ separator
--   row 2  view toggle: Results/Inbox tabs · Select all + "N selected" (right)
--   row 3  column header (Results view only) + separator
--   row 4  THE HERO: full-width, full-height scrolling list
--   ------ footer (pinned to the container bottom)
--          template label/hint, full-width template box, Whisper button
----------------------------------------------------------------------
local ROW_HEIGHT = 20

----------------------------------------------------------------------
-- Build all scanner controls (filters, Scan button, Results/Inbox tabs,
-- results list, template box, Whisper button) as children of `container`.
-- Safe to call more than once overall (e.g. popup body + an embedded
-- sub-tab), but a second call on the SAME container is a no-op, guarded
-- by container._scannerBuilt.
----------------------------------------------------------------------
function RecruitScanner:BuildInto(container)
    if not container then return end
    if container._scannerBuilt then return container._scannerRefresh end
    container._scannerBuilt = true

    local UI = GuildOS.UI
    local C = GuildOS.Colors
    -- UI.GAP (#371), read the way Layout.lua reads UI.SCROLL_GUTTER: a stubbed UI in the tools
    -- answers something else for it.
    local GAP = type(UI.GAP) == "number" and UI.GAP or 8
    local f = container
    -- Forward-declared: the button handlers below close over this LOCAL
    -- (not a shared self.uiRefresh) so each container's controls always
    -- repaint that same container — never a different popup/embed built
    -- later, which would otherwise steal a single shared refresh slot.
    local refresh

    -- Officer gate is checked once at build time (mirrors Bulletin.lua's
    -- officer-only post box): non-officers get a static notice and no
    -- controls are ever created for them.
    f.isOfficer = GuildOS:CanRecruit()   -- EKO patch: Recruiters (Herald) scan and whisper too
    if not f.isOfficer then
        local notice = UI:CreateText(f, L["Officers only."], 12, C.textSoft.r, C.textSoft.g, C.textSoft.b)
        notice:SetPoint("TOPLEFT", 0, -GAP)
    else
        self._selected = self._selected or {}
        self._view = self._view or "results"
        local cfg = GuildOS.db.recruitScanner
        cfg.classes = cfg.classes or {}

        ------------------------------------------------------------
        -- Every row starts flush with the container's left edge (the Recruitment sub-tab bar's), the
        -- first UI.GAP under its top, and stops UI.GAP short of its right (#371): they sat 12px in.
        ------------------------------------------------------------
        local ROW1_Y = -GAP
        local BTN_H = 24

        ------------------------------------------------------------
        -- Row 1: filters bar. Min level / Max level / Class / Scan, and the count the scan found right
        -- after it. The level fields are the shared field (#371): they had the gold Blizzard border.
        ------------------------------------------------------------
        local minLbl = UI:CreateText(f, L["Min level"], 11, C.text.r, C.text.g, C.text.b)
        minLbl:SetPoint("LEFT", f, "TOPLEFT", 0, ROW1_Y - BTN_H / 2)
        local minBox = UI:CreateInput(f, 36, 22, { numeric = true, max = 2 })
        minBox:SetPoint("LEFT", minLbl, "RIGHT", 6, 0)
        minBox:SetText(tostring(cfg.minLevel or 0))
        local function commitMin(s)
            cfg.minLevel = math.max(0, math.min(GuildOS.Client.maxLevel, tonumber(s:GetText()) or 0))
            s:SetText(tostring(cfg.minLevel))
            s:ClearFocus()
        end
        minBox:SetScript("OnEnterPressed", commitMin)
        minBox:HookScript("OnEditFocusLost", commitMin)

        local maxLbl = UI:CreateText(f, L["Max level"], 11, C.text.r, C.text.g, C.text.b)
        maxLbl:SetPoint("LEFT", minBox, "RIGHT", 14, 0)
        local maxBox = UI:CreateInput(f, 36, 22, { numeric = true, max = 2 })
        maxBox:SetPoint("LEFT", maxLbl, "RIGHT", 6, 0)
        local cap = GuildOS.Client.maxLevel
        maxBox:SetText(tostring(math.min(cfg.maxLevel or cap, cap)))
        local function commitMax(s)
            cfg.maxLevel = math.max(0, math.min(cap, tonumber(s:GetText()) or cap))
            s:SetText(tostring(cfg.maxLevel))
            s:ClearFocus()
        end
        maxBox:SetScript("OnEnterPressed", commitMax)
        maxBox:HookScript("OnEditFocusLost", commitMax)

        -- Class cycle button: Any -> the 9 TBC classes -> Any. Reuses the
        -- class order already defined for the recruitment beacon instead
        -- of duplicating the list here.
        local classBtn = UI:CreateButton(f, "", 132, BTN_H)
        classBtn:SetPoint("LEFT", maxBox, "RIGHT", 14, 0)
        local function currentClass()
            return next(cfg.classes)
        end
        local function classNameFor(cls)
            return cls and (LOCALIZED_CLASS_NAMES_MALE[cls] or cls) or L["Any"]
        end
        local function paintClassBtn()
            classBtn.label:SetText(string.format(L["Class: %s"], classNameFor(currentClass())))
        end
        classBtn:SetScript("OnClick", function()
            local order = (GuildOS.Recruitment and GuildOS.Recruitment.CLASSES) or {}
            local cur = currentClass()
            local nextCls
            if cur then
                for i, cls in ipairs(order) do
                    if cls == cur then nextCls = order[i + 1]; break end
                end
            else
                nextCls = order[1]
            end
            cfg.classes = nextCls and { [nextCls] = true } or {}
            paintClassBtn()
        end)
        paintClassBtn()
        f.classBtn = classBtn

        local scanBtn = UI:CreateButton(f, L["Scan"], 90, BTN_H)
        scanBtn:SetPoint("LEFT", classBtn, "RIGHT", 14, 0)
        scanBtn:SetScript("OnClick", function()
            RecruitScanner:Scan(function()
                self._selected = {}
                GuildOS:SafeCall(refresh)
            end)
            GuildOS:SafeCall(refresh) -- immediate busy-state repaint
        end)
        f.scanBtn = scanBtn

        local foundText = UI:CreateText(f, string.format(L["%d found"], 0), 11, C.textSoft.r, C.textSoft.g, C.textSoft.b)
        foundText:SetPoint("LEFT", scanBtn, "RIGHT", 12, 0)
        f.foundText = foundText

        ------------------------------------------------------------
        -- Separator under the filters bar.
        ------------------------------------------------------------
        local SEP1_Y = ROW1_Y - BTN_H - GAP
        local sep1 = UI:CreateSeparator(f)
        sep1:SetPoint("TOPLEFT", 0, SEP1_Y)
        sep1:SetPoint("TOPRIGHT", -GAP, SEP1_Y)

        ------------------------------------------------------------
        -- Row 2: view toggle. Results / Inbox tabs (left) and a
        -- Select-all checkbox + "N selected" count (right).
        ------------------------------------------------------------
        local TAB_Y, TAB_H = SEP1_Y - GAP, 28
        local resultsTab = UI:CreateTab(f, L["Results"], 90)
        resultsTab:SetPoint("TOPLEFT", 0, TAB_Y)
        resultsTab:SetScript("OnClick", function()
            self._view = "results"
            GuildOS:SafeCall(refresh)
        end)
        local inboxTab = UI:CreateTab(f, L["Inbox"], 90)
        inboxTab:SetPoint("LEFT", resultsTab, "RIGHT", 4, 0)
        inboxTab:SetScript("OnClick", function()
            self._view = "inbox"
            GuildOS:SafeCall(refresh)
        end)
        f.tabs = { results = resultsTab, inbox = inboxTab }

        -- Inbox view only: empties it, so old replies stop reading as applicants (issue #311).
        local clearBtn = UI:CreateButton(f, L["Clear"], 70, 20)
        clearBtn:SetPoint("LEFT", inboxTab, "RIGHT", 12, 0)
        clearBtn:SetScript("OnClick", function()
            RecruitScanner:ClearInbox()
            GuildOS:SafeCall(refresh)
        end)
        f.clearBtn = clearBtn

        local selectedText = UI:CreateText(f, string.format(L["%d selected"], 0), 11,
            C.textSoft.r, C.textSoft.g, C.textSoft.b)
        selectedText:SetPoint("RIGHT", f, "TOPRIGHT", -GAP, TAB_Y - TAB_H / 2)
        f.selectedText = selectedText

        local selectAllCb = UI:CreateCheckbox(f, L["Select all"], 16)
        -- CreateCheckbox pads its frame out to size+200 (room for long
        -- labels elsewhere in the app); shrink it to its visible content
        -- so it can be anchored snugly against selectedText instead of
        -- floating 200px past the label, per the ScrollFrame-gotcha-style
        -- lesson of not trusting a helper's default frame bounds.
        selectAllCb:SetWidth(16 + 6 + (selectAllCb.label:GetStringWidth() or 50) + 4)
        selectAllCb:SetPoint("RIGHT", selectedText, "LEFT", -14, 0)
        selectAllCb.checkbox.onChanged = function(_, checked)
            local results = RecruitScanner:GetResults()
            for _, cand in ipairs(results) do
                local who = RecruitScanner:Addr(cand)
                if checked then self._selected[who] = true else self._selected[who] = nil end
            end
            GuildOS:SafeCall(refresh)
        end
        f.selectAllCb = selectAllCb

        ------------------------------------------------------------
        -- Row 3: column header (Results view only). The shared header (#371): no band, its 1px rule
        -- under it, the column labels the table's. Its x offsets are the rows' below, the scroll
        -- child being flush with the holder, so headers line up with the data.
        ------------------------------------------------------------
        local HEADER_Y = TAB_Y - TAB_H - 4
        local colHeader = UI:CreateTableHeader(f)
        colHeader:SetPoint("TOPLEFT", 0, HEADER_Y)
        colHeader:SetPoint("TOPRIGHT", -GAP, HEADER_Y)
        -- EKO patch: click a column to sort by it; click again to reverse. The arrow says which way.
        self._sort = self._sort or { col = nil, dir = 1 }
        f.headerFS = {}
        local SORT_COLS = {
            { key = "name",  label = L["PLAYER"], x = 30,  w = 200 },
            { key = "level", label = L["LVL"],    x = 240, w = 40 },
            { key = "class", label = L["CLASS"],  x = 290, w = 110 },
            { key = "zone",  label = L["ZONE"],   x = 410, w = 300 },
        }
        for _, col in ipairs(SORT_COLS) do
            local fs = UI:CreateHeaderText(colHeader, col.label)
            fs:SetPoint("LEFT", col.x, 0)
            f.headerFS[col.key] = fs
            local hit = CreateFrame("Button", nil, colHeader)
            hit:SetPoint("LEFT", col.x - 4, 0)
            hit:SetSize(col.w, 20)
            hit:SetScript("OnClick", function()
                if self._sort.col == col.key then self._sort.dir = -self._sort.dir
                else self._sort.col, self._sort.dir = col.key, 1 end
                GuildOS:SafeCall(refresh)
            end)
        end
        f.colHeader = { colHeader }

        ------------------------------------------------------------
        -- Row 4 (THE HERO): scroll list. Hung just below the column header and just above the
        -- footer, so it fills the middle and grows with the window.
        -- ScrollFrame gotcha: CreateScrollFrame does NOT anchor the
        -- scroll frame itself: SetAllPoints() here, or content is
        -- clipped to 0x0. The child keeps the frame's width less the bar's gutter (#371).
        ------------------------------------------------------------
        local FOOTER_H = 118   -- EKO patch: room for the preview line above the template label
        local holder = CreateFrame("Frame", nil, f)
        holder:SetPoint("TOPLEFT", colHeader, "BOTTOMLEFT", 0, -2)
        holder:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -GAP, FOOTER_H)
        local scroll, child = UI:CreateScrollFrame(holder, "GuildOSRecruitScannerScroll")
        scroll:SetAllPoints()
        UI:BindScrollChildWidth(scroll, child)
        f.child = child
        f.holder = holder

        ------------------------------------------------------------
        -- Footer: fixed at the container bottom. The template's label, the
        -- full-width template box (the shared field, in its font, #371), and under it the tokens
        -- it takes and the Whisper-selected button.
        ------------------------------------------------------------
        local whisperBtn = UI:CreateButton(f, string.format(L["Whisper selected (%d)"], 0), 190, 28)
        whisperBtn:SetPoint("BOTTOMRIGHT", -GAP, GAP)
        whisperBtn:SetScript("OnClick", function()
            -- WoW: Forever: the last batch's whispers go out one per click (issue #61).
            if RecruitScanner:PendingWhispers() > 0 then
                RecruitScanner:WhisperNext()
                GuildOS:SafeCall(refresh)
                return
            end
            local names = {}
            for name in pairs(self._selected) do names[#names + 1] = name end
            if #names == 0 then return end
            local dlg = GuildOS:ShowDialog("GUILDOS_SCOUT_WHISPER_CONFIRM", #names, nil, names)
            if dlg then dlg.data, dlg.data2 = names, refresh end
            -- EKO patch: hang the question just outside the GuildOS window's right edge, level with
            -- the Scan button, so it never covers the scanner.
            if dlg and f.scanBtn then
                local win = f
                while win:GetParent() and win:GetParent() ~= UIParent do win = win:GetParent() end
                local sb = f.scanBtn
                local right, left = win:GetRight(), sb:GetLeft()
                if right and left then
                    local x = (right * win:GetEffectiveScale() - left * sb:GetEffectiveScale()) / dlg:GetEffectiveScale() + 12
                    dlg:ClearAllPoints()
                    dlg:SetPoint("TOPLEFT", sb, "TOPLEFT", x, 0)
                end
            end
        end)
        f.whisperBtn = whisperBtn

        local tmplBox = UI:CreateInput(f, 200, 22, { max = 255 })
        tmplBox:SetPoint("BOTTOMLEFT", 0, 44)
        tmplBox:SetPoint("BOTTOMRIGHT", -GAP, 44)
        tmplBox:SetText(cfg.template or "")
        local function commitTemplate(s)
            cfg.template = s:GetText()
            s:ClearFocus()
        end
        tmplBox:SetScript("OnEnterPressed", commitTemplate)
        tmplBox:HookScript("OnEditFocusLost", commitTemplate)

        local tmplLbl = UI:CreateText(f, L["Message template"], 11, C.text.r, C.text.g, C.text.b)
        tmplLbl:SetPoint("BOTTOMLEFT", tmplBox, "TOPLEFT", 0, 6)
        -- The tokens under the box they fill, left-aligned (#371): they trailed its label after a dot.
        local hint = UI:CreateText(f, L["Tokens: [player] [class] [level]"], 10, C.textSoft.r, C.textSoft.g, C.textSoft.b)
        hint:SetPoint("TOPLEFT", tmplBox, "BOTTOMLEFT", 0, -6)

        -- EKO patch: token buttons insert at the cursor, so nobody has to type the brackets.
        local prevTok = hint
        for _, tok in ipairs({ "[player]", "[class]", "[level]" }) do
            local b = UI:CreateButton(f, tok, 72, 20)
            b:SetPoint("LEFT", prevTok, "RIGHT", prevTok == hint and 14 or 6, 0)
            b:SetScript("OnClick", function()
                tmplBox:SetFocus()
                tmplBox:Insert(tok)
            end)
            prevTok = b
        end

        -- EKO patch: the message as it would go out, filled in for one player, with its length against
        -- the whisper limit (255). Painted again as the text changes and on each refresh.
        local preview = UI:CreateText(f, "", 10, C.text.r, C.text.g, C.text.b)
        preview:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", GAP, FOOTER_H - 16)
        preview:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -GAP, FOOTER_H - 16)
        preview:SetJustifyH("LEFT")
        preview:SetWordWrap(false)
        f.preview = preview
        f.paintPreview = function()
            local sample = self._sampleCand or { name = L["Player"], class = "WARRIOR", level = 12 }
            local text = self:_ExpandTemplate(tmplBox:GetText() or "", sample)
            local n = #text
            if n > 255 then
                preview:SetTextColor(C.danger.r, C.danger.g, C.danger.b, 1)
                preview:SetText(string.format(L["Too long for a whisper: %d/255"], n) .. "  " .. text)
            else
                preview:SetTextColor(C.silver.r, C.silver.g, C.silver.b, 1)
                preview:SetText(string.format("%d/255  ", n) .. text)
            end
        end
        tmplBox:HookScript("OnTextChanged", function() f.paintPreview() end)
    end

    -- EKO patch: a sorted copy of the results, by the column clicked (never the scan's own order).
    local function sortedResults(list)
        local copy = {}
        for i, c in ipairs(list) do copy[i] = c end
        local key, dir = self._sort and self._sort.col, self._sort and self._sort.dir or 1
        if not key then return copy end
        local function val(c)
            if key == "level" then return c.level or 0 end
            if key == "class" then return (LOCALIZED_CLASS_NAMES_MALE[c.class] or c.class or ""):lower() end
            if key == "zone" then return (c.zone or ""):lower() end
            return (c.name or ""):lower()
        end
        table.sort(copy, function(a, b)
            local va, vb = val(a), val(b)
            if va ~= vb then
                if dir > 0 then return va < vb else return va > vb end
            end
            return (a.name or "") < (b.name or "")
        end)
        return copy
    end

    -- Row widgets are pooled: built the first time a row is needed, then reused by every
    -- refresh. A WoW frame can't be freed, so building new ones on each refresh piled up
    -- regions under the scroll child until child:GetRegions() overflowed the Lua stack.
    local resultRows, inboxRows = {}, {}
    local statics = {}
    local function staticText(key, text, size, color)
        if not statics[key] then
            statics[key] = UI:CreateText(f.child, text, size, color.r, color.g, color.b)
        end
        return statics[key]
    end
    local function setRowShown(row, shown)
        for _, w in ipairs(row.widgets) do
            if shown then w:Show() else w:Hide() end
        end
    end
    local function resultRow(i)
        local row = resultRows[i]
        if row then return row end
        local child = f.child
        row = {}
        row.sel = UI:CreateCheckbox(child, "", 16)
        row.nameFS = UI:CreateText(child, "", 11, C.text.r, C.text.g, C.text.b)
        row.nameFS:SetWidth(200)
        row.nameFS:SetJustifyH("LEFT")
        row.lvlFS = UI:CreateText(child, "", 11, C.textDim.r, C.textDim.g, C.textDim.b)
        row.lvlFS:SetWidth(40)
        row.classFS = UI:CreateText(child, "", 11, C.textDim.r, C.textDim.g, C.textDim.b)
        row.classFS:SetWidth(110)
        row.classFS:SetJustifyH("LEFT")
        row.zoneFS = UI:CreateText(child, "", 10, C.silver.r, C.silver.g, C.silver.b)
        row.zoneFS:SetWidth(300)
        row.zoneFS:SetJustifyH("LEFT")
        row.widgets = { row.sel, row.nameFS, row.lvlFS, row.classFS, row.zoneFS }
        resultRows[i] = row
        return row
    end
    local function inboxRow(i)
        local row = inboxRows[i]
        if row then return row end
        local child = f.child
        row = {}
        row.nameFS = UI:CreateText(child, "", 11, C.text.r, C.text.g, C.text.b)
        row.nameFS:SetWidth(88)
        row.nameFS:SetJustifyH("LEFT")
        row.msgFS = UI:CreateText(child, "", 10, C.text.r, C.text.g, C.text.b)
        row.msgFS:SetJustifyH("LEFT")
        row.msgFS:SetWordWrap(false)
        row.tsFS = UI:CreateText(child, "", 9, C.silver.r, C.silver.g, C.silver.b)
        row.widgets = { row.nameFS, row.msgFS, row.tsFS }
        inboxRows[i] = row
        return row
    end

    refresh = function()
        if not f:IsShown() or not f.isOfficer then return end

        if RecruitScanner._scanBusy then
            f.scanBtn:Disable()
            f.scanBtn.label:SetText(L["Scanning…"])
        else
            f.scanBtn:Enable()
            f.scanBtn.label:SetText(L["Scan"])
        end
        for view, tab in pairs(f.tabs) do tab:SetActive(view == self._view) end

        local results = sortedResults(RecruitScanner:GetResults())
        self._sampleCand = results[1]
        local hidden = RecruitScanner._hiddenCount or 0
        if hidden > 0 then
            f.foundText:SetText(string.format(L["%d found"], #results) .. "  ·  "
                .. string.format(L["%d hidden by filters"], hidden))
        else
            f.foundText:SetText(string.format(L["%d found"], #results))
        end
        if #results == 0 then
            f.foundText:SetTextColor(C.danger.r, C.danger.g, C.danger.b)
        else
            f.foundText:SetTextColor(C.textSoft.r, C.textSoft.g, C.textSoft.b)
        end
        -- EKO patch: the sort arrow sits on the column it sorts by.
        local ARROW = { [1] = " " .. L["asc"], [-1] = " " .. L["desc"] }
        local names = { name = L["PLAYER"], level = L["LVL"], class = L["CLASS"], zone = L["ZONE"] }
        for key, fs in pairs(f.headerFS or {}) do
            local arrow = (self._sort.col == key) and ARROW[self._sort.dir] or ""
            fs:SetText(names[key] .. arrow)
        end
        f.paintPreview()

        local selCount = 0
        for _ in pairs(self._selected) do selCount = selCount + 1 end
        f.selectedText:SetText(string.format(L["%d selected"], selCount))
        local pendingW = RecruitScanner:PendingWhispers()
        f.whisperBtn.label:SetText(pendingW > 0 and string.format(L["Whisper next (%d)"], pendingW)
                                   or string.format(L["Whisper selected (%d)"], selCount))

        local isResults = (self._view == "results")
        for _, hdr in ipairs(f.colHeader) do hdr:SetShown(isResults) end
        f.clearBtn:SetShown(not isResults)
        -- Seeing the inbox is reading it: the Now tab stops counting these replies (issue #311).
        -- Only on screen: the view is shared by both containers, and building the hidden one
        -- would otherwise mark replies read that nobody saw.
        if not isResults and f:IsVisible() then RecruitScanner:MarkInboxRead() end

        if isResults then
            local allSelected = #results > 0
            for _, cand in ipairs(results) do
                if not self._selected[RecruitScanner:Addr(cand)] then allSelected = false; break end
            end
            f.selectAllCb.checkbox:SetChecked(allSelected)
            f.selectAllCb.checkbox:Enable()
        else
            f.selectAllCb.checkbox:SetChecked(false)
            f.selectAllCb.checkbox:Disable()
        end

        -- Paint from the pooled widgets: hide what the last paint showed, then reuse them.
        -- Nothing is built here, so refreshes never pile up regions under the scroll child.
        local child = f.child
        for _, row in ipairs(resultRows) do setRowShown(row, false) end
        for _, row in ipairs(inboxRows) do setRowShown(row, false) end
        for _, fs in pairs(statics) do fs:Hide() end

        local y = 0
        if isResults then
            for i, cand in ipairs(results) do
                local row = resultRow(i)
                local who = RecruitScanner:Addr(cand)   -- realm and all on retail (#184)
                row.sel:ClearAllPoints()
                row.sel:SetPoint("TOPLEFT", 4, -y)
                row.sel.checkbox:SetChecked(self._selected[who] and true or false)
                row.sel.checkbox.onChanged = function(_, checked)
                    if checked then self._selected[who] = true
                    else self._selected[who] = nil end
                    GuildOS:SafeCall(refresh) -- live-updates "N selected" + Whisper count
                end

                -- Every column below anchors TOPLEFT with the SAME explicit
                -- -y offset against the SAME parent (child). Chaining
                -- "LEFT"/"RIGHT" anchors across sibling frames of different
                -- heights would make WoW resolve conflicting vertical centers
                -- (e.g. a row element vs. the whole scroll child) — explicit
                -- -y on every column sidesteps that entirely. Offsets mirror
                -- the column header row above (HDR + this offset).
                row.nameFS:ClearAllPoints()
                row.nameFS:SetPoint("TOPLEFT", 30, -y)
                row.nameFS:SetText(who or "?")
                row.lvlFS:ClearAllPoints()
                row.lvlFS:SetPoint("TOPLEFT", 240, -y)
                row.lvlFS:SetText(tostring(cand.level or "?"))

                local classLabel = LOCALIZED_CLASS_NAMES_MALE[cand.class] or cand.class or "?"
                local cc = RAID_CLASS_COLORS[cand.class]
                row.classFS:ClearAllPoints()
                row.classFS:SetPoint("TOPLEFT", 290, -y)
                row.classFS:SetText(classLabel)
                row.classFS:SetTextColor(cc and cc.r or C.textDim.r, cc and cc.g or C.textDim.g, cc and cc.b or C.textDim.b)

                row.zoneFS:ClearAllPoints()
                row.zoneFS:SetPoint("TOPLEFT", 410, -y)
                row.zoneFS:SetText(cand.zone or "")

                setRowShown(row, true)
                y = y + ROW_HEIGHT
            end
            if #results == 0 then
                local empty = staticText("emptyResults", L["No candidates."], 11, C.silver)
                empty:ClearAllPoints()
                empty:SetPoint("TOPLEFT", 4, -4)
                empty:Show()
                y = 20
            end
        else -- inbox
            local inbox = RecruitScanner:GetInbox()
            -- EKO patch: say what this list is, how long it keeps replies, and what Clear does.
            local days = math.floor((RecruitScanner.INBOX_KEEP_SEC or 14 * 86400) / 86400)
            local intro = staticText("intro", "", 10, C.textSoft)
            intro:SetText(string.format(L["Replies to your whispers, kept for %d days. Clear empties this list."], days))
            intro:ClearAllPoints()
            intro:SetPoint("TOPLEFT", 4, -y)
            intro:SetPoint("TOPRIGHT", child, "TOPRIGHT", -4, -y)
            intro:SetJustifyH("LEFT")
            intro:Show()
            y = y + math.max(14, intro:GetStringHeight() or 14) + 10
            for i, entry in ipairs(inbox) do
                local row = inboxRow(i)
                -- A name in the text colour: gold is the selection's (#371).
                row.nameFS:ClearAllPoints()
                row.nameFS:SetPoint("TOPLEFT", 4, -y)
                row.nameFS:SetText(entry.name or "?")
                row.msgFS:ClearAllPoints()
                row.msgFS:SetPoint("TOPLEFT", 98, -y)
                row.msgFS:SetPoint("TOPRIGHT", child, "TOPRIGHT", -54, -y)
                row.msgFS:SetText(entry.msg or "")
                row.tsFS:ClearAllPoints()
                row.tsFS:SetPoint("TOPRIGHT", child, "TOPRIGHT", -4, -y)
                row.tsFS:SetText(date("%a %H:%M", entry.ts or 0))

                setRowShown(row, true)
                local rowH = math.max(row.nameFS:GetStringHeight() or 14, row.msgFS:GetStringHeight() or 14)
                y = y + rowH + 6
            end
            if #inbox == 0 then
                local empty = staticText("emptyInbox", L["No replies yet."], 11, C.silver)
                empty:ClearAllPoints()
                empty:SetPoint("TOPLEFT", 4, -y)
                empty:Show()
                y = y + 20
            end
        end
        child:SetHeight(math.max(1, y))
    end

    container._scannerRefresh = refresh
    f:SetScript("OnShow", refresh)
    refresh()
    return refresh
end

----------------------------------------------------------------------
-- Popup wrapper: chrome only (backdrop/title/close/drag). Content is
-- built by BuildInto() so the same widgets can be embedded elsewhere
-- (see UI/RosterFrame.lua's Recruitment > Scanner sub-tab).
----------------------------------------------------------------------
function RecruitScanner:Show()
    local UI = GuildOS.UI
    local C = GuildOS.Colors

    local f = self.frame
    if not f then
        f = CreateFrame("Frame", "GuildOSRecruitScannerFrame", UIParent, "BackdropTemplate")
        -- Wider/taller than the old popup: the new layout's filters bar
        -- (min/max level + class cycle + Scan + right-aligned "N found")
        -- needs the room, and the fixed-height header+footer chrome
        -- (~218px combined) needs a taller body to leave the scroll list
        -- a usable height.
        f:SetSize(760, 520)
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

        local title = UI:CreateTitle(f, L["Recruit Scanner"], 15)
        title:SetPoint("TOPLEFT", 16, -14)
        local close = UI:CreateCloseButton(f)
        close:SetPoint("TOPRIGHT", -8, -8)
        close:SetScript("OnClick", function() f:Hide() end)

        -- BuildInto() lays its rows flush with the container's left edge, UI.GAP under its top
        -- and UI.GAP short of its right and bottom (#371), which is right for the RosterFrame
        -- sub-tab it was designed for but would run straight into this popup's edges and under
        -- its title if handed `f` directly. Give it its own body frame below the title/close row,
        -- inset like the title, the same idiom as RosterFrame's bar+sub-panel split.
        local body = CreateFrame("Frame", nil, f)
        body:SetPoint("TOPLEFT", 16, -36)
        body:SetPoint("BOTTOMRIGHT", -8, 8)
        self.frame = f
        self.body = body
    end

    local refresh = self:BuildInto(self.body)
    f:Show()
    GuildOS:SafeCall(refresh)
end

----------------------------------------------------------------------
-- Self-tests
----------------------------------------------------------------------
function RecruitScanner:_RegisterTests()
    if not GuildOS.SelfTest then return end
    local S = GuildOS.SelfTest
    S:Register("scanner.template", function()
        local s = RecruitScanner:_ExpandTemplate("Hi [player] ([level] [class])",
            { name = "Bob", level = 68, class = "MAGE" })
        if s ~= "Hi Bob (68 MAGE)" then return false, s end
        return true
    end)
    S:Register("scanner.candidate_ok", function()
        local f = { minLevel = 60, maxLevel = 70, classes = { MAGE = true } }
        local ok = RecruitScanner:_CandidateOK({ name = "Bob", level = 68, class = "MAGE", guilded = false }, f)
        if not ok then return false, "should pass" end
        return true
    end)
    S:Register("scanner.reject_guilded", function()
        if RecruitScanner:_CandidateOK({ name = "Bob", level = 68, class = "MAGE", guilded = true }, {}) then
            return false, "guilded must be rejected"
        end
        return true
    end)
    S:Register("scanner.reject_banned", function()
        local banned = function(n) return n == "Bob" end
        if RecruitScanner:_CandidateOK({ name = "Bob", level = 68, guilded = false }, {}, banned) then
            return false, "banned must be rejected"
        end
        return true
    end)
end
