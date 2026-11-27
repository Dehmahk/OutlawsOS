----------------------------------------------------------------------
-- Guild OS - Bulletin Board
-- Officers post short notices; everyone running the addon sees them.
-- Officer-authoritative: the board is broadcast as a revision-checked
-- snapshot via SyncService (domain "bulletin"). New posts also surface
-- in the login digest.
----------------------------------------------------------------------
local Bulletin = {}
GuildOS.Bulletin = Bulletin
local L = GuildOS.L

local MAX = 20
Bulletin.MAX = MAX   -- the notices the board holds; the oldest goes past it

function Bulletin:Initialize()
    GuildOS.db.bulletin = GuildOS.db.bulletin or { messages = {} }
    GuildOS.db.bulletin.messages = GuildOS.db.bulletin.messages or {}
    if GuildOS.SyncService then
        GuildOS.SyncService:On("bulletin", function(env) Bulletin:OnSync(env) end)
    end
end

function Bulletin:GetMessages()
    return (GuildOS.db.bulletin and GuildOS.db.bulletin.messages) or {}
end

-- What the board shows: the notices still up (an expiry past now drops one), the pinned ones first,
-- the rest in the order they were posted (#8, #10).
function Bulletin:Shown()
    local now = GetServerTime()
    local pinned, rest = {}, {}
    for _, m in ipairs(self:GetMessages()) do
        if not (m.expires and now >= m.expires) then
            if m.pinned then pinned[#pinned + 1] = m else rest[#rest + 1] = m end
        end
    end
    for _, m in ipairs(rest) do pinned[#pinned + 1] = m end
    return pinned
end

local function newId()
    return string.format("%X%04X", GetServerTime(), math.random(0, 0xFFFF))
end

----------------------------------------------------------------------
-- Officer mutations
----------------------------------------------------------------------
-- `days` is how long the notice stays up; nil or false keeps it for ever (#10).
function Bulletin:Post(text, days)
    if not GuildOS:IsOfficer() then
        GuildOS:Print(L["|cffFF4444Officers only.|r"])
        return
    end
    text = strtrim(text or "")
    if text == "" then return end
    local msgs = self:GetMessages()
    local now = GetServerTime()
    local msg = { id = newId(), text = text, author = GuildOS.Compat.PlayerName(), ts = now }
    if tonumber(days) and days > 0 then msg.expires = now + days * 86400 end
    table.insert(msgs, 1, msg)
    while #msgs > MAX do table.remove(msgs) end
    self:Broadcast()
    self:Refresh()
end

function Bulletin:Remove(id)
    if not GuildOS:IsOfficer() then return end
    local msgs = self:GetMessages()
    for i, m in ipairs(msgs) do
        if m.id == id then table.remove(msgs, i); break end
    end
    self:Broadcast()
    self:Refresh()
end

-- Edits a notice's text. Its time and author stay; it is marked edited (#9).
function Bulletin:Edit(id, text)
    if not GuildOS:IsOfficer() then return end
    text = strtrim(text or "")
    if text == "" then return end
    for _, m in ipairs(self:GetMessages()) do
        if m.id == id then
            m.text = text
            m.edited = GetServerTime()
            break
        end
    end
    self:Broadcast()
    self:Refresh()
end

-- Pins a notice to the top, or unpins it (#8).
function Bulletin:Pin(id)
    if not GuildOS:IsOfficer() then return end
    for _, m in ipairs(self:GetMessages()) do
        if m.id == id then
            m.pinned = (not m.pinned) or nil
            break
        end
    end
    self:Broadcast()
    self:Refresh()
end

function Bulletin:Clear()
    if not GuildOS:IsOfficer() then return end
    GuildOS.db.bulletin.messages = {}
    self:Broadcast()
    self:Refresh()
end

----------------------------------------------------------------------
-- Sync (domain "bulletin")
----------------------------------------------------------------------
function Bulletin:Broadcast()
    if not GuildOS:IsOfficer() or not GuildOS.SyncService then return end
    local rev = GuildOS.SyncService:NextRevision("bulletin", "board")
    GuildOS.db.bulletin.syncedAt = GetServerTime()   -- when the board last changed here (#15)
    GuildOS.SyncService:Publish("bulletin", "snapshot", { messages = self:GetMessages() }, { rev = rev })
end

-- Cold-sync backfill: re-broadcast the current board snapshot at its STORED
-- revision (never a bumped one, unlike Broadcast) so an officer offline for
-- the last post/removal converges on login. Answering the sync REQUEST with
-- the existing revision keeps it idempotent: ShouldApply drops it for a peer
-- already at that revision and applies it only for one that missed the edit,
-- so a stale re-broadcast can never overwrite a newer board. A revision of 0
-- means nothing authoritative has been posted yet, so there is nothing to
-- backfill. Officers only. Called from CommSystem:HandleRequest.
function Bulletin:Backfill()
    if not GuildOS:IsOfficer() or not GuildOS.SyncService then return end
    local rev = GuildOS.SyncService:GetRevision("bulletin", "board")
    if rev <= 0 then return end
    GuildOS.SyncService:Publish("bulletin", "snapshot", { messages = self:GetMessages() }, { rev = rev })
end

function Bulletin:OnSync(env)
    if env.act == "snapshot" and env.data
        and GuildOS.SyncService:ShouldApply("bulletin", "board", env.rev) then
        GuildOS.db.bulletin.messages = env.data.messages or {}
        GuildOS.db.bulletin.syncedAt = GetServerTime()
        GuildOS.SyncService:SetRevision("bulletin", "board", env.rev)
        self:Refresh()
    end
end

function Bulletin:Refresh()
    if self.uiRefresh then GuildOS:SafeCall(self.uiRefresh) end
end

----------------------------------------------------------------------
-- UI
----------------------------------------------------------------------
function Bulletin:Show()
    local UI = GuildOS.UI
    local C = GuildOS.Colors

    local f = self.frame
    if not f then
        f = CreateFrame("Frame", "GuildOSBulletinFrame", UIParent, "BackdropTemplate")
        f:SetSize(460, 380)
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

        local title = UI:CreateTitle(f, L["Guild Bulletin"], 15)
        title:SetPoint("TOPLEFT", 16, -14)
        local close = UI:CreateCloseButton(f)
        close:SetPoint("TOPRIGHT", -8, -8)
        close:SetScript("OnClick", function() f:Hide() end)

        local listTop = -44
        if GuildOS:IsOfficer() then
            -- The shared field, labelled, then its button: as the Guild tab's Bulletin draws it (#371).
            local label = UI:CreateText(f, L["Notice:"], 12)
            local postBtn = UI:CreateButton(f, L["Post"], 80, 24)
            local box = UI:CreateInput(f, 0, 24, { max = 200 })
            box:SetPoint("TOPLEFT", 16 + math.ceil(label:GetStringWidth() or 0) + 8, -42)
            box:SetPoint("TOPRIGHT", -(16 + UI.ReserveFor(postBtn, 8)), -42)
            label:SetPoint("RIGHT", box, "LEFT", -8, 0)
            postBtn:SetPoint("LEFT", box, "RIGHT", 8, 0)
            local function doPost()
                GuildOS.Bulletin:Post(box:GetText())
                box:SetText("")
                box:ClearFocus()
            end
            box:SetScript("OnEnterPressed", doPost)
            postBtn:SetScript("OnClick", doPost)
            listTop = -76
        end

        local holder = CreateFrame("Frame", nil, f)
        holder:SetPoint("TOPLEFT", 16, listTop)
        holder:SetPoint("BOTTOMRIGHT", -12, 14)
        local scroll, child = UI:CreateScrollFrame(holder, "GuildOSBulletinScroll")
        scroll:SetAllPoints()
        -- The rows hang from both of the child's top corners; it keeps the list's width (#371).
        UI:BindScrollChildWidth(scroll, child)
        f.child = child
        f.holder = holder
        self.frame = f
    end

    local function refresh()
        if not f:IsShown() then return end
        local child = f.child
        for _, c in pairs({ child:GetChildren() }) do c:Hide() end
        for _, r in pairs({ child:GetRegions() }) do r:Hide() end

        local msgs = GuildOS.Bulletin:GetMessages()
        local y, isOfficer = 0, GuildOS:IsOfficer()
        for _, m in ipairs(msgs) do
            local textFS = UI:CreateText(child, m.text, 12, C.text.r, C.text.g, C.text.b)
            textFS:SetPoint("TOPLEFT", 0, -y)
            textFS:SetPoint("TOPRIGHT", isOfficer and -30 or 0, -y)
            textFS:SetJustifyH("LEFT")
            local th = textFS:GetStringHeight() or 14
            local meta = UI:CreateText(child, (m.author or "?") .. " · " .. GuildOS:DateText(m.ts or 0, " %H:%M"),
                11, C.textSoft.r, C.textSoft.g, C.textSoft.b)
            meta:SetPoint("TOPLEFT", 0, -(y + th + 2))
            if isOfficer then
                local del = UI:CreateButton(child, "\195\151", 22, 18)  -- the multiplication sign
                del:SetPoint("TOPRIGHT", 0, -y)
                local id = m.id
                del:SetScript("OnClick", function() GuildOS.Bulletin:Remove(id) end)
            end
            y = y + th + 22
        end
        if #msgs == 0 then
            local empty = UI:CreateText(child, L["No notices yet."], 12, C.textSoft.r, C.textSoft.g, C.textSoft.b)
            empty:SetPoint("TOPLEFT", 0, 0)
        end
        child:SetHeight(math.max(1, y))
    end

    self.uiRefresh = refresh
    f:SetScript("OnShow", refresh)
    f:Show()
    refresh()
end
