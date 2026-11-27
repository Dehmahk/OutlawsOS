----------------------------------------------------------------------
-- Guild OS - Announcements
-- A member posts a short guild announcement with the Post button on a movable box at the top of
-- the Ledger (the members screen). Everyone with the Ledger open sees each new post for about ten
-- seconds, then it fades. The box keeps the last five posts, and hovering over it steps back
-- through them. Anyone except the EKO recruiters can post. The writing window is its own popup,
-- on screen, not part of the OutlawOS window.
--
-- A post travels on the "announce" domain over GUILD. A receiver keeps it only when the sender
-- signed it with their own name, the sender is not a recruiter, the text is not empty, and the same
-- sender did not post in the last POST_GAP seconds.
----------------------------------------------------------------------
local Announcements = {}
GuildOS.Announcements = Announcements
local L = GuildOS.L

Announcements.MAX_KEPT  = 5       -- posts kept, newest first, and posts waiting to show
Announcements.SHOW_FOR  = 10      -- seconds a post stays up before it fades
Announcements.FADE_FOR  = 0.8     -- seconds the fade takes
Announcements.POST_GAP  = 60      -- seconds between two posts from one member
Announcements.MAX_CHARS = 200     -- longest message, in bytes
Announcements.MAX_AGE   = 86400   -- a post stamped further than this from our clock is refused

local BOX_W, FULL_H = 380, 150

local box, body
local state = "idle"      -- "idle": no box up; "full": a post is up
local viewIndex = 1      -- which kept post the box shows, 1 = newest
local token = 0          -- bumped to cancel a pending fade
local hovered = false
local queue = {}         -- kept posts not yet shown, oldest first
local lastBy = {}        -- short name -> when a post of theirs was last kept (this session)
local popup

-- The domain is a member's, not an officer's. SyncService holds the GUILD-only rule for it.
if GuildOS.SyncService then
    GuildOS.SyncService.GUILD_ONLY_DOMAINS.announce = true
end

----------------------------------------------------------------------
-- Names, recruiters and storage
----------------------------------------------------------------------
local function shortName(name)
    if type(name) ~= "string" then return nil end
    return name:match("^([^-]+)") or name
end

local function me()
    return shortName(GuildOS.Compat.PlayerName()) or ""
end

local function serverNow()
    return GetServerTime and GetServerTime() or time()
end

-- An EKO recruiter, by name, from the EKO leader list.
local function isRecruiter(short)
    for _, l in ipairs((GuildOS.EKO and GuildOS.EKO.LEADERS) or {}) do
        if l.role == "Recruiter" and l.name == short then return true end
    end
    return false
end
Announcements.IsRecruiter = isRecruiter

-- The kept posts live in the guild's database, so they survive a reload.
local function store()
    if not GuildOS.db then return nil end
    GuildOS.db.announce = GuildOS.db.announce or {}
    GuildOS.db.announce.list = GuildOS.db.announce.list or {}
    return GuildOS.db.announce
end

-- A class colour as the six hex digits an |c code takes.
local function classHex(class)
    local cc = class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
    if not cc then return "d9a94f" end
    return string.format("%02x%02x%02x", cc.r * 255, cc.g * 255, cc.b * 255)
end

local function reasonText(why)
    if why == "guild" then return L["You need to be in the guild to post."] end
    if why == "recruiter" then return L["Recruiters can't post announcements."] end
    if why == "empty" then return L["Type a message first."] end
    if why == "gap" then return L["You can post again in a minute."] end
    return L["That announcement did not go out."]
end

----------------------------------------------------------------------
-- Checking and keeping posts
----------------------------------------------------------------------
-- Is this post one we keep? Returns the clean post, or nil and the reason. `sender` is who it came from
-- over the wire, or us for our own post. `lastBy` holds when each sender last got a post kept.
function Announcements.Check(data, sender, now, lastBy)
    if type(data) ~= "table" then return nil, "shape" end
    local by = shortName(sender)
    if not by or data.by ~= by then return nil, "name" end
    if isRecruiter(by) then return nil, "recruiter" end
    if type(data.id) ~= "string" or data.id == "" then return nil, "id" end
    if type(data.t) ~= "number" or data.t > now + 60 or data.t < now - Announcements.MAX_AGE then
        return nil, "time"
    end
    local msg = GuildOS:SanitizeUserText(type(data.msg) == "string" and data.msg or "", Announcements.MAX_CHARS)
    if msg == "" then return nil, "empty" end
    local last = lastBy and lastBy[by]
    if last and now - last < Announcements.POST_GAP then return nil, "gap" end
    return { id = data.id, by = by, c = type(data.c) == "string" and data.c or "", msg = msg, t = data.t }, nil
end

-- Keeps a post at the top of the list, newest first. A post already kept is not kept twice.
-- Returns true when it was added.
function Announcements.Add(post)
    local s = store()
    if not s then return false end
    for _, p in ipairs(s.list) do
        if p.id == post.id then return false end
    end
    table.insert(s.list, 1, post)
    while #s.list > Announcements.MAX_KEPT do table.remove(s.list) end
    return true
end

local function indexOf(id)
    local s = store()
    for i, p in ipairs((s and s.list) or {}) do
        if p.id == id then return i end
    end
    return 1
end

----------------------------------------------------------------------
-- Receiving and posting
----------------------------------------------------------------------
local function receive(env, sender)
    local now = serverNow()
    local post = Announcements.Check(env and env.data, sender, now, lastBy)
    if not post then return end
    if not Announcements.Add(post) then return end
    lastBy[post.by] = now
    Announcements.Enqueue(post)
end

if GuildOS.SyncService then
    GuildOS.SyncService:On("announce", receive)
end

local function newId(now)
    return me() .. ":" .. now .. ":" .. string.format("%04X", math.random(0, 0xFFFF))
end

-- Posts the text as this character. Returns true, or false and the reason it did not go out.
function Announcements.Post(text)
    if not IsInGuild() then return false, "guild" end
    local name = me()
    if name == "" then return false, "guild" end
    if isRecruiter(name) then return false, "recruiter" end
    local now = serverNow()
    local _, class = UnitClass("player")
    local raw = { id = newId(now), by = name, c = class or "", msg = text or "", t = now }
    local post, why = Announcements.Check(raw, name, now, lastBy)
    if not post then return false, why end
    if not GuildOS.SyncService then return false, "sync" end
    GuildOS.SyncService:Publish("announce", "post",
        { id = post.id, by = post.by, c = post.c, msg = post.msg, t = post.t }, { priority = "NORMAL" })
    lastBy[name] = now
    Announcements.Add(post)
    Announcements.Enqueue(post)
    return true
end

----------------------------------------------------------------------
-- The box: what shows, when it fades, and how it is moved
----------------------------------------------------------------------
-- The fade is our own alpha ramp: the Blizzard fade helpers are not reliably
-- The fade is our own alpha ramp: the Blizzard fade helpers are not reliably
-- available on this client. Only one ramp runs at a time.
local fadeTicker

-- Stops a running fade and leaves the body at its current alpha.
local function stopFade()
    if fadeTicker then fadeTicker:Cancel(); fadeTicker = nil end
end

-- Eases the body's alpha from `from` to `to` over `duration` seconds, then calls `done`.
local function fadeBody(from, to, duration, done)
    stopFade()
    local steps = math.max(1, math.floor(duration / 0.05 + 0.5))
    local i = 0
    body:SetAlpha(from)
    fadeTicker = C_Timer.NewTicker(duration / steps, function()
        i = i + 1
        body:SetAlpha(from + (to - from) * (i / steps))
        if i >= steps then
            stopFade()
            if done then done() end
        end
    end)
end

local function render(index)
    local s = store()
    local list = (s and s.list) or {}
    local p = list[index]
    if not p or not box then return end
    viewIndex = index
    box.author:SetText(string.format(L["Posted by %s"], "|cff" .. classHex(p.c) .. p.by .. "|r"))
    box.msg:SetText(p.msg)
    box.counter:SetText(index .. " / " .. #list)
end

-- Runs a few times a second while the box is up. Declared here because the box starts it.
local tick

-- Puts the box where the member last dragged it, or at the top of the screen.
local function placeBox()
    box:ClearAllPoints()
    local s = store()
    local p = s and s.pos
    if p then
        box:SetPoint(p[1], UIParent, p[2], p[3], p[4])
    else
        box:SetPoint("TOP", UIParent, "TOP", 0, -120)
    end
end

local function postAllowed()
    return not isRecruiter(me())
end

-- Whether this character may post. The Outlaw Desk uses it to show its Post button.
function Announcements.CanPost()
    return postAllowed()
end

local function ensureBox()
    if box then return box end
    local C, UI = GuildOS.Colors, GuildOS.UI
    local f = CreateFrame("Frame", "GuildOSAnnounceBox", UIParent, "BackdropTemplate")
    f:SetSize(BOX_W, FULL_H)
    -- DIALOG, not HIGH: the Ledger window is HIGH, and this box is not its child,
    -- so at HIGH the window's background was drawn over it.
    f:SetFrameStrata("DIALOG")
    f:SetClampedToScreen(true)
    f:SetBackdrop({
        bgFile   = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = GuildOS.UI:Edge(f),
    })
    f:SetBackdropColor(0.063, 0.059, 0.086, 0.95)
    f:SetBackdropBorderColor(C.gold.r, C.gold.g, C.gold.b, 0.9)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", function(self) self:StartMoving() end)
    f:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local s = store()
        if s then
            local point, _, relPoint, x, y = self:GetPoint()
            s.pos = { point, relPoint, x, y }
        end
    end)

    local title = UI:CreateTitle(f, L["Outlaw Announcement"], 11)
    title:SetPoint("TOPLEFT", 10, -9)

    local close = UI:CreateButton(f, L["Close"], 64, 20)
    close:SetPoint("TOPRIGHT", -10, -7)
    close:SetScript("OnClick", function() Announcements.Dismiss() end)
    f.close = close

    body = CreateFrame("Frame", nil, f)
    body:SetPoint("TOPLEFT", 10, -30)
    body:SetPoint("BOTTOMRIGHT", -10, 8)

    local author = body:CreateFontString(nil, "OVERLAY")
    GuildOS:ApplyFont(author, 10)
    author:SetPoint("TOPLEFT", 0, 0)
    f.author = author

    local msg = body:CreateFontString(nil, "OVERLAY")
    GuildOS:ApplyFont(msg, 12)
    msg:SetPoint("TOPLEFT", 0, -16)
    msg:SetPoint("TOPRIGHT", 0, -16)
    msg:SetJustifyH("LEFT")
    msg:SetWordWrap(true)
    msg:SetTextColor(C.text.r, C.text.g, C.text.b)
    f.msg = msg

    local prev = UI:CreateButton(body, "<", 26, 20)
    prev:SetPoint("BOTTOMLEFT", 0, 0)
    prev:SetScript("OnClick", function() if viewIndex > 1 then render(viewIndex - 1) end end)

    local nxt = UI:CreateButton(body, ">", 26, 20)
    nxt:SetPoint("BOTTOMRIGHT", 0, 0)
    nxt:SetScript("OnClick", function()
        local s = store()
        if s and viewIndex < #s.list then render(viewIndex + 1) end
    end)

    local counter = body:CreateFontString(nil, "OVERLAY")
    GuildOS:ApplyFont(counter, 10)
    counter:SetPoint("BOTTOM", 0, 4)
    f.counter = counter

    box = f
    box:Hide()
    C_Timer.NewTicker(0.2, function() tick() end)
    return box
end

-- The box is up only while a post shows. Once that post has faded, the box goes away.
local function hideBox()
    stopFade()
    hovered = false
    state = "idle"
    if box then box:Hide() end
end

-- Shows a kept post in the box, and brings the box up.
local function setFull(index)
    ensureBox()
    state = "full"
    render(index)
    stopFade()
    body:SetAlpha(1)
    body:Show()
    box:SetHeight(FULL_H)
    if not box:IsShown() then placeBox() end
    box:Show()
end

-- Fades the post after `delay` seconds, unless the mouse comes over the box first.
local function armFade(delay)
    token = token + 1
    local mine = token
    C_Timer.After(delay, function()
        if mine ~= token or hovered or state ~= "full" then return end
        fadeBody(1, 0, Announcements.FADE_FOR, function()
            if mine ~= token or hovered then return end
            hideBox()
            Announcements.ShowNext()
        end)
    end)
end

-- A new kept post joins the queue, so posts that arrive together show one after another.
function Announcements.Enqueue(post)
    table.insert(queue, post)
    while #queue > Announcements.MAX_KEPT do table.remove(queue, 1) end
    Announcements.ShowNext()
end

-- Shows the next waiting post, unless one is up or the mouse is on the box.
function Announcements.ShowNext()
    if state == "full" or hovered then return end
    local p = table.remove(queue, 1)
    if not p then return end
    setFull(indexOf(p.id))
    armFade(Announcements.SHOW_FOR)
end

-- Close: the box goes away now, and the next waiting post, if any, shows.
function Announcements.Dismiss()
    token = token + 1
    hideBox()
    Announcements.ShowNext()
end

local function onHoverChange(over)
    hovered = over
    if over then
        token = token + 1
        stopFade()
        if state == "full" then body:SetAlpha(1) end
    else
        armFade(1.5)
    end
end

function tick()
    if not box or not box:IsShown() then return end
    local over = box:IsMouseOver() and true or false
    if over ~= hovered then onHoverChange(over) end
end

----------------------------------------------------------------------
-- The writing popup: on screen, with the message box and one Post button, plus the close X
----------------------------------------------------------------------
local function buildPopup()
    local C, UI = GuildOS.Colors, GuildOS.UI
    local f = UI:CreateDialogFrame("GuildOSAnnouncePopup", 420, 130)

    local title = UI:CreateTitle(f, L["Post an announcement"], 13)
    title:SetPoint("TOP", 0, -8)

    local who = f:CreateFontString(nil, "OVERLAY")
    GuildOS:ApplyFont(who, 11)
    who:SetPoint("TOP", 0, -28)
    local _, class = UnitClass("player")
    who:SetText(string.format(L["Posting as %s"], "|cff" .. classHex(class) .. me() .. "|r"))

    local edit = CreateFrame("EditBox", nil, f, "InputBoxTemplate")
    edit:SetSize(380, 22)
    edit:SetPoint("TOP", 0, -50)
    edit:SetAutoFocus(false)
    edit:SetMaxLetters(Announcements.MAX_CHARS)
    edit:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    f.edit = edit

    -- Why a post did not go out, shown just above the button and cleared when the popup opens.
    local status = f:CreateFontString(nil, "OVERLAY")
    GuildOS:ApplyFont(status, 11)
    status:SetPoint("BOTTOM", 0, 41)
    status:SetTextColor(C.textSoft.r, C.textSoft.g, C.textSoft.b)
    f.status = status

    local function send()
        local ok, why = Announcements.Post(edit:GetText())
        if ok then
            f:Hide()
        else
            status:SetText(reasonText(why))
        end
    end

    local postBtn = UI:SetButtonVariant(UI:CreateButton(f, L["Post announcement"], 170, 26), "primary")
    postBtn:SetPoint("BOTTOM", 0, 12)
    postBtn:SetScript("OnClick", send)
    edit:SetScript("OnEnterPressed", send)

    local closeBtn = UI:CreateCloseButton(f)
    closeBtn:SetPoint("TOPRIGHT", -4, -4)
    closeBtn:SetScript("OnClick", function() f:Hide() end)

    f:Hide()
    return f
end

function Announcements.OpenPopup()
    if not IsInGuild() or not postAllowed() then return end
    if not popup then popup = buildPopup() end
    popup.edit:SetText("")
    popup.status:SetText("")
    popup:Show()
    popup.edit:SetFocus()
end
