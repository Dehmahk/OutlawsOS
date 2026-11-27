----------------------------------------------------------------------
-- Guild OS - Call to Arms (issue #108)
-- An officer rallies the guild: a world boss is up, a fight in the open world, a zone to
-- defend, an event farm. Everyone running the addon gets a popup at the top of the screen
-- with a sound, sees how many are coming and can answer "On my way", "Maybe" or "Can't". A plain
-- guild chat line goes out with it, for members without the addon.
--
-- A call can be set for a time: everyone gets a reminder popup a few minutes before it. Officers
-- share the recent calls and the saved meeting points: each one who logs in asks the others, and
-- an officer can close a call for everyone.
--
-- Officer-authoritative: SyncService only takes a "cta" call, close or meeting point from an
-- officer over GUILD (OFFICER_DOMAINS); answering is a member action.
----------------------------------------------------------------------
local CTA = {}
GuildOS.CallToArms = CTA
local L = GuildOS.L

CTA.COOLDOWN  = 60    -- seconds between two calls from one officer
CTA.FROM_GAP  = 30    -- a second call from the same sender inside this is dropped on arrival
CTA.POPUP_GAP = 10    -- a popup inside this of the last one, from anybody, is a chat line instead
CTA.MAX_AGE   = 600   -- a call older than this cannot be answered and is not shown as a popup
CTA.SKEW      = 300   -- a call stamped further ahead than this is not believed
CTA.SHOW_FOR  = 30    -- seconds the popup stays up
CTA.TEXT_MAX  = 140
CTA.NAME_MAX  = 24
CTA.MEET_MAX  = 30
CTA.KEEP      = 10    -- recent calls kept and listed
CTA.TEMPLATES_MAX = 12
CTA.MEETS_MAX = 12
CTA.REMIND_LEAD = 300 -- seconds before a timed call that its reminder pops up
CTA.LOGIN_DELAY = 15  -- seconds after login before an officer asks the others for the history
CTA.HIST_DELAY  = 6   -- seconds an officer waits before answering a history request
CTA.ANSWERS = { going = true, maybe = true, cant = true }

local RAID_WARNING = (SOUNDKIT and SOUNDKIT.RAID_WARNING) or 8959
local READY_CHECK  = (SOUNDKIT and SOUNDKIT.READY_CHECK) or 8960

-- The ready-made kinds. `text` is the default message; {zone} becomes where the caller is.
CTA.KINDS = {
    { id = "worldboss", title = L["World Boss"], text = L["World boss up in {zone}, come now!"],
      icon = "Interface\\Icons\\INV_Misc_Head_Dragon_01", sound = RAID_WARNING },
    { id = "pvp", title = L["World PvP"], text = L["Fight in {zone}, everyone we can get!"],
      icon = "Interface\\Icons\\Ability_DualWield", sound = RAID_WARNING },
    { id = "defend", title = L["Defend"], text = L["{zone} is under attack, defend it!"],
      icon = "Interface\\Icons\\INV_Shield_06", sound = RAID_WARNING },
    { id = "event", title = L["Event / Farm"], text = L["Event farm in {zone}, join us!"],
      icon = "Interface\\Icons\\INV_Misc_Bag_08", sound = READY_CHECK },
    { id = "rally", title = L["Rally"], text = L["Gather in {zone}!"],
      icon = "Interface\\Icons\\Ability_Warrior_BattleShout", sound = READY_CHECK },
}
local BY_ID = {}
for _, k in ipairs(CTA.KINDS) do BY_ID[k.id] = k end

function CTA:Kind(id)
    return BY_ID[id] or BY_ID.rally
end

CTA.recent = {}     -- newest first; becomes the saved history in Initialize
CTA.lastFrom = {}   -- sender -> server time of their last call shown

local function clean(s, max)
    return type(s) == "string" and GuildOS:SanitizeUserText(s, max) or ""
end
-- A cleaned string, or nil when it is empty.
local function opt(s, max)
    local v = clean(s, max)
    if v ~= "" then return v end
end
local function me() return GuildOS.Compat.PlayerName() end
local function publish(act, data)
    if GuildOS.SyncService then GuildOS.SyncService:Publish("cta", act, data) end
end
local function short(name)
    return (Ambiguate and Ambiguate(name or "", "short")) or (name or "")
end
local function sameName(a, b)
    return a:lower() == b:lower()
end

function CTA:Initialize()
    GuildOS.db.cta = GuildOS.db.cta or {}
    local c = GuildOS.db.cta
    c.templates = c.templates or {}
    c.history = c.history or {}
    c.meets = c.meets or {}
    self.recent = c.history
    self.reminders = {}
    if GuildOS.SyncService then
        GuildOS.SyncService:On("cta", function(env, sender) CTA:OnSync(env, sender) end)
    end
    for _, e in ipairs(self.recent) do self:ArmReminder(e) end
    if C_Timer and C_Timer.After then
        C_Timer.After(self.LOGIN_DELAY, function() CTA:RequestHistory() end)
    end
end

----------------------------------------------------------------------
-- Settings: each player's own, true unless switched off
----------------------------------------------------------------------
local function on(key)
    return GuildOS:GetSetting(key) ~= false
end
function CTA:PopupsOn() return on("ctaPopups") end
function CTA:SoundOn() return on("ctaSound") end
function CTA:QuietOn() return on("ctaQuiet") end
function CTA:ChatOn() return on("ctaChat") end
function CTA:MuteAll() return GuildOS:GetSetting("ctaMuteAll") == true end
function CTA:Muted(kind)
    return self:MuteAll() or GuildOS:GetSetting("ctaMute_" .. tostring(kind)) == true
end

----------------------------------------------------------------------
-- Templates: the ready-made kinds, then an officer's own. A template can carry a meeting
-- point (its name) and a time (as typed: "+10" or "20:30").
----------------------------------------------------------------------
function CTA:Templates()
    local out = {}
    for _, k in ipairs(self.KINDS) do
        out[#out + 1] = { id = k.id, name = k.title, text = k.text, kind = k.id, builtin = true }
    end
    for _, t in ipairs((GuildOS.db.cta and GuildOS.db.cta.templates) or {}) do
        out[#out + 1] = { id = t.id, name = t.name, text = t.text, kind = t.kind, meet = t.meet, when = t.when }
    end
    return out
end

function CTA:Template(id)
    for _, t in ipairs(self:Templates()) do
        if t.id == id then return t end
    end
end

-- The template the panel opens on: the officer's default, else the world boss.
function CTA:Default()
    local d = GuildOS.db.cta and GuildOS.db.cta.default
    if d and self:Template(d) then return d end
    return "worldboss"
end

function CTA:SetDefault(id)
    if not self:Template(id) then return false end
    GuildOS.db.cta.default = id
    return true
end

function CTA:SaveTemplate(name, text, kind, meet, when)
    name = clean(name, self.NAME_MAX)
    text = clean(text, self.TEXT_MAX)
    if name == "" or text == "" then return false, L["A template needs a name and a message."] end
    local list = GuildOS.db.cta.templates
    if #list >= self.TEMPLATES_MAX then return false, L["Too many templates: delete one first."] end
    local t = { id = string.format("c%X%04X", GetServerTime(), math.random(0, 0xFFFF)),
                name = name, text = text, kind = BY_ID[kind] and kind or "rally" }
    t.meet = opt(meet, self.MEET_MAX)
    t.when = opt(when, 12)
    list[#list + 1] = t
    return true, t.id
end

function CTA:DeleteTemplate(id)
    local list = GuildOS.db.cta.templates
    for i = #list, 1, -1 do
        if list[i].id == id then table.remove(list, i) end
    end
    if GuildOS.db.cta.default == id then GuildOS.db.cta.default = nil end
end

function CTA:RenameTemplate(id, name)
    name = clean(name, self.NAME_MAX)
    if name == "" then return false, L["A template needs a name and a message."] end
    for _, t in ipairs(GuildOS.db.cta.templates) do
        if t.id == id then t.name = name; return true end
    end
    return false, L["Only your own templates can be renamed."]
end

function CTA:DuplicateTemplate(id)
    local t = self:Template(id)
    if not t then return false end
    return self:SaveTemplate((t.name or "") .. " 2", t.text, t.kind, t.meet, t.when)
end

----------------------------------------------------------------------
-- Meeting points: one shared list for the officers
----------------------------------------------------------------------
function CTA:Meets()
    return GuildOS.db.cta.meets
end

function CTA:MergeMeet(m)
    if type(m) ~= "table" or type(m.id) ~= "string" then return end
    local name = opt(m.name, self.MEET_MAX)
    if not name then return end
    local list = GuildOS.db.cta.meets
    for _, x in ipairs(list) do
        if x.id == m.id or sameName(x.name, name) then return end
    end
    if #list < self.MEETS_MAX then list[#list + 1] = { id = m.id, name = name } end
end

function CTA:DropMeet(id)
    local list, found = GuildOS.db.cta.meets, false
    for i = #list, 1, -1 do
        if list[i].id == id then table.remove(list, i); found = true end
    end
    return found
end

function CTA:AddMeet(name)
    if not GuildOS:IsOfficer() then return false, L["Officers only."] end
    name = opt(name, self.MEET_MAX)
    if not name then return false, L["A meeting point needs a name."] end
    for _, m in ipairs(GuildOS.db.cta.meets) do
        if sameName(m.name, name) then return false, L["That meeting point is already saved."] end
    end
    if #GuildOS.db.cta.meets >= self.MEETS_MAX then return false, L["Too many meeting points: remove one first."] end
    local m = { id = string.format("m%X%04X", GetServerTime(), math.random(0, 0xFFFF)), name = name }
    self:MergeMeet(m)
    publish("meetadd", { id = m.id, name = m.name })
    return true
end

function CTA:RemoveMeet(id)
    if not GuildOS:IsOfficer() then return false, L["Officers only."] end
    if not self:DropMeet(id) then return false end
    publish("meetdel", { id = id })
    return true
end

----------------------------------------------------------------------
-- Where the caller is: the zone (and subzone) and the map position, if the client gives it
----------------------------------------------------------------------
function CTA:Where()
    local zone = GetZoneText and GetZoneText() or ""
    local sub = GetSubZoneText and GetSubZoneText() or ""
    local label = (sub ~= "" and sub ~= zone) and (sub .. ", " .. zone) or zone
    local x, y
    local ok = pcall(function()
        local mapID = GuildOS.Compat.GetBestMapForUnit("player")
        local px, py = GuildOS.Compat.GetPlayerMapPosition(mapID, "player")
        if px and py and not GuildOS.Compat.IsSecret(px, py) and px > 0 and py > 0 then
            x, y = math.floor(px * 1000 + 0.5) / 10, math.floor(py * 1000 + 0.5) / 10
        end
    end)
    if not ok then x, y = nil, nil end
    return label, x, y
end

local function fill(text, zone)
    return (text:gsub("{zone}", function() return zone ~= "" and zone or L["here"] end))
end

----------------------------------------------------------------------
-- Time: "now", "+10" (minutes from now) or "20:30" (the next time that clock reads it).
-- Returns the server time of the call, nil for now, or nil and a reason when it is not understood.
----------------------------------------------------------------------
function CTA:ParseWhen(str, now)
    local s = strtrim(str or ""):lower()
    now = now or GetServerTime()
    if s == "" or s == "now" then return nil end
    local bad = L["A time within the next 24 hours, like +10 or 20:30."]
    local n = s:match("^%+?(%d+)$")
    if n then
        n = tonumber(n)
        if n < 1 or n > 1440 then return nil, bad end
        return now + n * 60
    end
    local h, m = s:match("^(%d%d?):(%d%d)$")
    h, m = tonumber(h), tonumber(m)
    if h and m and h < 24 and m < 60 then
        local t = date("*t", now)
        t.hour, t.min, t.sec = h, m, 0
        local ts = time(t)
        if ts <= now then ts = ts + 86400 end
        return ts
    end
    return nil, bad
end

-- " (starts 20:30, meet at X)" for a chat line or a printed line; "" when neither is set.
function CTA:Detail(e)
    local parts = {}
    if e.when then parts[#parts + 1] = string.format(L["starts %s"], date("%H:%M", e.when)) end
    if e.meet then parts[#parts + 1] = string.format(L["meet at %s"], e.meet) end
    if #parts == 0 then return "" end
    return " (" .. table.concat(parts, ", ") .. ")"
end

-- "Starts in 4 min", "Started at 20:30", or nil for a call with no time.
function CTA:WhenLine(e)
    if not e.when then return nil end
    local now = GetServerTime()
    if now >= e.when then return string.format(L["Started at %s"], date("%H:%M", e.when)) end
    return string.format(L["Starts in %d min"], math.max(1, math.ceil((e.when - now) / 60)))
end

----------------------------------------------------------------------
-- Sending (officers, from a click or a command: the guild chat line needs that on Forever)
-- opts: zone (typed; blank = where I am), when (typed; blank = now), meet (a meeting point's name)
----------------------------------------------------------------------
function CTA:Send(templateId, text, opts)
    opts = opts or {}
    if not GuildOS:IsOfficer() then
        GuildOS:Print(L["|cffFF4444Officers only.|r"])
        return false
    end
    local now = GetServerTime()
    local last = GuildOS.db.cta.lastSent   -- saved, so a /reload does not skip the cooldown
    if last and now - last < self.COOLDOWN and now >= last then
        GuildOS:Print(string.format(L["Wait %ds before the next call."], self.COOLDOWN - (now - last)))
        return false
    end
    local t = self:Template(templateId) or self:Template("rally")
    local autoZone, ax, ay = self:Where()
    local zone, x, y = autoZone, ax, ay
    local typed = clean(opts.zone, 60)
    if typed ~= "" and typed ~= autoZone then zone, x, y = typed, nil, nil end
    local whenIn = opts.when
    if whenIn == nil then whenIn = t.when end
    local when, werr = self:ParseWhen(whenIn, now)
    if werr then GuildOS:Print(werr) return false end
    local meetIn = opts.meet
    if meetIn == nil then meetIn = t.meet end
    local body = GuildOS:SanitizeUserText((text and strtrim(text) ~= "") and text or t.text, self.TEXT_MAX)
    local call = {
        id = string.format("%X%04X", now, math.random(0, 0xFFFF)),
        kind = t.kind,
        title = GuildOS:SanitizeUserText(t.name, self.NAME_MAX),
        text = GuildOS:SanitizeUserText(fill(body, zone), self.TEXT_MAX),
        zone = GuildOS:SanitizeUserText(zone, 60),
        x = x, y = y, ts = now, when = when, meet = opt(meetIn, self.MEET_MAX),
    }
    -- The guild line first, so the call can say it went: a player who takes calls as chat lines
    -- already has it there, and is not told twice. Forever drops a refused line without an
    -- error, so an encounter's chat lockdown is asked first rather than inferred.
    if self:ChatOn() and IsInGuild() then
        local locked = C_ChatInfo and C_ChatInfo.InChatMessagingLockdown and C_ChatInfo.InChatMessagingLockdown()
        call.chat = not locked
            and pcall(SendChatMessage, string.format(L["[Call to Arms] %s: %s"], call.title, call.text) .. self:Detail(call), "GUILD")
            or nil
    end
    publish("call", call)
    GuildOS.db.cta.lastSent = now
    -- The caller sees the popup the guild sees, and the count grow on it, on the same terms:
    -- not with popups off, nor mid-fight with quiet on.
    local e = self:Remember(call, me(), true)
    self:ArmReminder(e)
    if self:PopupsOn() and not self:Quiet() then
        self.lastPopup = now
        self:ShowPopup(e)
    end
    GuildOS:Print(string.format(L["Call to Arms sent: %s"], call.title))
    if self.uiRefresh then GuildOS:SafeCall(self.uiRefresh) end
    return true
end

----------------------------------------------------------------------
-- Calls kept (shared history)
----------------------------------------------------------------------
function CTA:Remember(call, sender, mine)
    local entry = {}
    for k, v in pairs(call) do entry[k] = v end
    entry.sender, entry.at, entry.answers = sender, GetServerTime(), {}
    entry.mine = mine and true or nil
    table.insert(self.recent, 1, entry)
    while #self.recent > self.KEEP do table.remove(self.recent) end
    return entry
end

function CTA:Find(id)
    for _, e in ipairs(self.recent) do
        if e.id == id then return e end
    end
end

function CTA:Counts(e)
    local c = { going = 0, maybe = 0, cant = 0 }
    for _, a in pairs(e.answers or {}) do
        if c[a] ~= nil then c[a] = c[a] + 1 end
    end
    return c
end

function CTA:CountText(e)
    local c = self:Counts(e)
    local parts = {}
    if c.going > 0 then parts[#parts + 1] = string.format(L["%d on the way"], c.going) end
    if c.maybe > 0 then parts[#parts + 1] = string.format(L["%d maybe"], c.maybe) end
    if c.cant > 0 then parts[#parts + 1] = string.format(L["%d can't"], c.cant) end
    return table.concat(parts, " · ")
end

----------------------------------------------------------------------
-- Receiving
----------------------------------------------------------------------
function CTA:OnSync(env, sender)
    local d = env and env.data
    if type(d) ~= "table" or type(sender) ~= "string" then return end
    local act = env.act
    if act == "call" then
        self:OnCall(d, sender)
    elseif self.ANSWERS[act] then
        self:OnAnswer(d, sender, act)
    elseif act == "close" then
        local e = type(d.id) == "string" and self:Find(d.id)
        if e then e.closed = true; self:OnClosed(e) end
    elseif act == "meetadd" then
        self:MergeMeet(d)
        if self.uiRefresh then GuildOS:SafeCall(self.uiRefresh) end
    elseif act == "meetdel" then
        if type(d.id) == "string" then self:DropMeet(d.id) end
        if self.uiRefresh then GuildOS:SafeCall(self.uiRefresh) end
    elseif act == "hreq" then
        self:OnHistRequest(sender)
    elseif act == "hist" then
        self:OnHistory(d)
    end
end

function CTA:OnAnswer(d, sender, act)
    local e = type(d.id) == "string" and self:Find(d.id)
    if not e or e.closed then return end
    e.answers[sender] = act
    if self.popup and self.popup.callId == e.id then self:PaintCount(e) end
    if self.uiRefresh then GuildOS:SafeCall(self.uiRefresh) end
end

function CTA:OnCall(d, sender)
    if type(d.id) ~= "string" or d.id == "" or self:Find(d.id) then return end
    local now = GetServerTime()
    local ts = tonumber(d.ts) or 0
    if now - ts > self.MAX_AGE or ts - now > self.SKEW then return end
    if self.lastFrom[sender] and now - self.lastFrom[sender] < self.FROM_GAP then return end
    self.lastFrom[sender] = now
    local x, y = tonumber(d.x), tonumber(d.y)
    if not (x and y and x >= 0 and x <= 100 and y >= 0 and y <= 100) then x, y = nil, nil end
    local when = tonumber(d.when)
    if when and (when < 0 or when - now > 86400 + self.SKEW) then when = nil end
    local call = {
        id = d.id, kind = BY_ID[d.kind] and d.kind or "rally", ts = ts,
        title = clean(d.title, self.NAME_MAX), text = clean(d.text, self.TEXT_MAX), zone = clean(d.zone, 60),
        x = x, y = y, when = when, meet = opt(d.meet, self.MEET_MAX), chat = d.chat == true or nil,
    }
    if call.title == "" then call.title = self:Kind(call.kind).title end
    local e = self:Remember(call, sender, false)
    self:ArmReminder(e)
    if self.uiRefresh then GuildOS:SafeCall(self.uiRefresh) end
    self:Alert(e)
end

-- Answering: a member's own choice, sent to everyone. A caller does not answer their own call.
function CTA:Answer(id, ans)
    ans = ans or "going"
    local e = self:Find(id)
    if not e or e.closed or e.mine or not self.ANSWERS[ans] then return false end
    e.answers[me()] = ans
    publish(ans, { id = id })
    if self.popup and self.popup.callId == id then self:PaintCount(e) end
    if self.uiRefresh then GuildOS:SafeCall(self.uiRefresh) end
    return true
end

-- Closing: an officer ends a call for everyone. It cannot be answered after this.
function CTA:Close(id)
    if not GuildOS:IsOfficer() then return false, L["Officers only."] end
    local e = self:Find(id)
    if not e or e.closed then return false end
    e.closed = true
    publish("close", { id = id })
    self:OnClosed(e)
    return true
end

function CTA:OnClosed(e)
    if self.popup and self.popup.callId == e.id then self.popup:Hide() end
    if self.uiRefresh then GuildOS:SafeCall(self.uiRefresh) end
end

----------------------------------------------------------------------
-- Shared history: an officer who logs in asks the others; each officer who is online answers
-- once, after a short random wait, so the requester gets it from one or a few of them.
----------------------------------------------------------------------
function CTA:RequestHistory()
    if not GuildOS:IsOfficer() then return end
    publish("hreq", {})
end

function CTA:OnHistRequest(sender)
    if not GuildOS:IsOfficer() or sender == me() or self.histTimer then return end
    if not (C_Timer and C_Timer.NewTimer) then return end
    self.histTimer = C_Timer.NewTimer(math.random(1, self.HIST_DELAY), function()
        CTA.histTimer = nil
        CTA:SendHistory()
    end)
end

function CTA:SendHistory()
    local calls = {}
    for i, e in ipairs(self.recent) do
        if i > self.KEEP then break end
        local ans = {}
        for n, a in pairs(e.answers or {}) do ans[#ans + 1] = { n = n, a = a } end
        calls[#calls + 1] = { id = e.id, kind = e.kind, ts = e.ts, title = e.title, text = e.text,
            zone = e.zone, x = e.x, y = e.y, when = e.when, meet = e.meet, chat = e.chat,
            sender = e.sender, at = e.at, closed = e.closed, ans = ans }
    end
    local meets = {}
    for _, m in ipairs(GuildOS.db.cta.meets) do meets[#meets + 1] = { id = m.id, name = m.name } end
    publish("hist", { calls = calls, meets = meets })
end

function CTA:OnHistory(d)
    local mine = me()
    for _, c in ipairs(type(d.calls) == "table" and d.calls or {}) do
        if type(c.id) == "string" and c.id ~= "" then
            local e = self:Find(c.id)
            if not e then
                e = {
                    id = c.id, kind = BY_ID[c.kind] and c.kind or "rally", ts = tonumber(c.ts) or 0,
                    title = clean(c.title, self.NAME_MAX), text = clean(c.text, self.TEXT_MAX),
                    zone = clean(c.zone, 60), x = tonumber(c.x), y = tonumber(c.y),
                    when = tonumber(c.when), meet = opt(c.meet, self.MEET_MAX), chat = c.chat == true or nil,
                    sender = clean(c.sender, 40), at = tonumber(c.at) or 0, answers = {},
                }
                if e.title == "" then e.title = self:Kind(e.kind).title end
                e.mine = (e.sender == mine) or nil
                table.insert(self.recent, e)
            end
            e.answers = e.answers or {}
            for _, a in ipairs(type(c.ans) == "table" and c.ans or {}) do
                if type(a) == "table" and type(a.n) == "string" and self.ANSWERS[a.a] and not e.answers[a.n] then
                    e.answers[a.n] = a.a
                end
            end
            if c.closed then e.closed = true end
        end
    end
    table.sort(self.recent, function(a, b) return (a.ts or 0) > (b.ts or 0) end)
    while #self.recent > self.KEEP do table.remove(self.recent) end
    for _, m in ipairs(type(d.meets) == "table" and d.meets or {}) do self:MergeMeet(m) end
    for _, e in ipairs(self.recent) do self:ArmReminder(e) end
    if self.uiRefresh then GuildOS:SafeCall(self.uiRefresh) end
end

----------------------------------------------------------------------
-- Reminders: a timed call pops up again a few minutes before it starts, once
----------------------------------------------------------------------
function CTA:ArmReminder(e)
    if not e.when or e.reminded or e.closed or not (C_Timer and C_Timer.NewTimer) then return end
    local now = GetServerTime()
    if e.when <= now then return end
    self.reminders = self.reminders or {}
    if self.reminders[e.id] then self.reminders[e.id]:Cancel() end
    local delay = math.max(1, e.when - self.REMIND_LEAD - now)
    self.reminders[e.id] = C_Timer.NewTimer(delay, function()
        CTA.reminders[e.id] = nil
        CTA:Remind(e.id)
    end)
end

function CTA:Remind(id)
    local e = self:Find(id)
    if not e or e.reminded or e.closed then return end
    e.reminded = true
    if self:Muted(e.kind) then return end
    if not self:PopupsOn() or self:Quiet() then
        GuildOS:Print(L["Starting soon"] .. ": " .. self:Line(e))
    else
        self:ShowPopup(e, true)
    end
end

----------------------------------------------------------------------
-- How a call reaches this player: a popup, a chat line only, or nothing. A line the caller
-- already put in guild chat is not printed again. Popups from several officers at once are
-- one popup and lines for the rest.
-- In an instance or in combat, with quiet on: chat lines, not popups.
----------------------------------------------------------------------
function CTA:Quiet()
    return self:QuietOn() and ((IsInInstance and select(2, IsInInstance()) ~= "none")
        or (InCombatLockdown and InCombatLockdown())) and true or false
end

function CTA:Alert(e)
    if self:Muted(e.kind) then return "muted" end
    local now = GetServerTime()
    local crowded = self.lastPopup and now - self.lastPopup < self.POPUP_GAP
    if not self:PopupsOn() or self:Quiet() or crowded then
        if not e.chat then GuildOS:Print(self:Line(e)) end
        return "line"
    end
    self.lastPopup = now
    self:ShowPopup(e)
    return "popup"
end

function CTA:Line(e)
    return string.format(L["|cffFF8800[Call to Arms]|r %s: %s |cff888888(%s, %s)|r"], e.title, e.text .. self:Detail(e),
        short(e.sender), e.zone or "")
end

----------------------------------------------------------------------
-- The popup: one at a time, the newest call wins
----------------------------------------------------------------------
local function ago(ts)
    local d = math.max(0, GetServerTime() - (tonumber(ts) or 0))
    if d < 60 then return L["just now"] end
    return string.format(L["%d min ago"], math.floor(d / 60))
end

function CTA:BuildPopup()
    local C = GuildOS.Colors
    local f = CreateFrame("Frame", "GuildOSCallToArms", UIParent, "BackdropTemplate")
    f:SetSize(440, 160)
    f:SetPoint("TOP", 0, -140)
    f:SetFrameStrata("DIALOG")
    -- A flat popup surface with a 1px border (#371). Only the border keeps the alert's warm colour,
    -- as the warn token; the title and the count are text, not an accent.
    f:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = GuildOS.UI:Edge(f) })
    f:SetBackdropColor(C.popup.r, C.popup.g, C.popup.b, 0.97)
    f:SetBackdropBorderColor(C.warn.r, C.warn.g, C.warn.b, 1)
    f:EnableMouse(true)
    f:Hide()
    f:SetScript("OnHide", function()
        if CTA.tickTimer then CTA.tickTimer:Cancel(); CTA.tickTimer = nil end
    end)

    f.icon = f:CreateTexture(nil, "ARTWORK")
    f.icon:SetSize(52, 52)
    f.icon:SetPoint("TOPLEFT", 12, -12)

    f.title = f:CreateFontString(nil, "OVERLAY")
    GuildOS:ApplyFont(f.title, 16, "windowTitle")
    f.title:SetPoint("TOPLEFT", f.icon, "TOPRIGHT", 10, 0)
    f.title:SetTextColor(C.text.r, C.text.g, C.text.b)

    f.text = f:CreateFontString(nil, "OVERLAY")
    GuildOS:ApplyFont(f.text, 12)
    f.text:SetPoint("TOPLEFT", f.title, "BOTTOMLEFT", 0, -4)
    f.text:SetWidth(350)
    f.text:SetJustifyH("LEFT")
    if f.text.SetMaxLines then f.text:SetMaxLines(3) end   -- 140 wide letters would be four
    f.text:SetTextColor(C.text.r, C.text.g, C.text.b)

    -- Buttons along the bottom, right to left: Dismiss, Can't, Maybe, On my way.
    f.close = GuildOS.UI:CreateButton(f, L["Dismiss"], 90, 22)
    f.close:SetPoint("BOTTOMRIGHT", -12, 10)
    f.close:SetScript("OnClick", function() f:Hide() end)

    f.cant = GuildOS.UI:CreateButton(f, L["Can't"], 70, 22)
    f.cant:SetPoint("RIGHT", f.close, "LEFT", -8, 0)
    f.cant:SetScript("OnClick", function() CTA:Answer(f.callId, "cant") end)

    f.maybe = GuildOS.UI:CreateButton(f, L["Maybe"], 70, 22)
    f.maybe:SetPoint("RIGHT", f.cant, "LEFT", -6, 0)
    f.maybe:SetScript("OnClick", function() CTA:Answer(f.callId, "maybe") end)

    f.go = GuildOS.UI:CreateButton(f, L["On my way"], 100, 22)
    f.go:SetPoint("RIGHT", f.maybe, "LEFT", -6, 0)
    f.go:SetScript("OnClick", function() CTA:Answer(f.callId, "going") end)

    -- Where, who, when and meeting point: the popup's full width, on one line.
    f.meta = f:CreateFontString(nil, "OVERLAY")
    GuildOS:ApplyFont(f.meta, 10)
    f.meta:SetPoint("BOTTOMLEFT", 12, 62)
    f.meta:SetPoint("BOTTOMRIGHT", -12, 62)
    f.meta:SetJustifyH("LEFT")
    f.meta:SetWordWrap(false)
    f.meta:SetTextColor(C.textSoft.r, C.textSoft.g, C.textSoft.b)

    -- Who is coming, on a line of its own above the buttons.
    f.count = f:CreateFontString(nil, "OVERLAY")
    GuildOS:ApplyFont(f.count, 10)
    f.count:SetPoint("BOTTOMLEFT", 12, 42)
    f.count:SetPoint("BOTTOMRIGHT", -12, 42)
    f.count:SetJustifyH("LEFT")
    f.count:SetWordWrap(false)
    f.count:SetTextColor(C.text.r, C.text.g, C.text.b)

    self.popup = f
    return f
end

-- Where, by whom, how long ago, and the meeting point and time when there are any.
function CTA:PaintMeta(e)
    local f = self.popup
    if not f then return end
    local where = e.zone or ""
    if e.x and e.y then where = string.format("%s (%.1f, %.1f)", where, e.x, e.y) end
    local meta = string.format(L["%s · by %s · %s"], where, short(e.sender), ago(e.ts))
    local status = self:WhenLine(e)
    if status then meta = meta .. "  ·  " .. status end
    if e.meet then meta = meta .. "  ·  " .. string.format(L["Meet at %s"], e.meet) end
    f.meta:SetText(meta)
end

function CTA:PaintCount(e)
    local f = self.popup
    if not f then return end
    local out = e.mine or e.closed
    f.count:SetText(e.closed and L["Closed"] or self:CountText(e))
    f.go:SetShown(not out)
    f.maybe:SetShown(not out)
    f.cant:SetShown(not out)
end

function CTA:ShowPopup(e, reminder)
    local f = self.popup or self:BuildPopup()
    local k = self:Kind(e.kind)
    f.callId = e.id
    f.icon:SetTexture(k.icon)
    f.title:SetText(reminder and (L["Starting soon"] .. ": " .. e.title) or e.title)
    f.text:SetText(e.text)
    self:PaintMeta(e)
    self:PaintCount(e)
    f:Show()
    if self:SoundOn() and PlaySound then pcall(PlaySound, k.sound, "Master") end
    if self.hideTimer then self.hideTimer:Cancel() end
    self.hideTimer = C_Timer.NewTimer(self.SHOW_FOR, function()
        if f.callId == e.id then f:Hide() end
    end)
    -- A timed call's "starts in" counts down while the popup is up.
    if self.tickTimer then self.tickTimer:Cancel(); self.tickTimer = nil end
    if e.when and C_Timer.NewTicker then
        self.tickTimer = C_Timer.NewTicker(15, function()
            if f.callId == e.id and f:IsShown() then CTA:PaintMeta(e) end
        end)
    end
end

----------------------------------------------------------------------
-- Self-tests: the pure parts
----------------------------------------------------------------------
if GuildOS.SelfTest then
    local S = GuildOS.SelfTest
    S:Register("cta.when", function()
        local now = 1795400000
        if CTA:ParseWhen("", now) ~= nil or CTA:ParseWhen("now", now) ~= nil then return false, "now" end
        if CTA:ParseWhen("+10", now) ~= now + 600 then return false, "+10" end
        local ts, err = CTA:ParseWhen("25:00", now)
        if ts ~= nil or not err then return false, "bad hour accepted" end
        return true
    end)
end
