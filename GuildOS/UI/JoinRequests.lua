----------------------------------------------------------------------
-- Guild OS - Join requests, the guild's side (specs/071-o-recrutamento in guildos-web, the mock's tab 3)
-- A discreet notice when somebody asks the guild to take them, and the "Join requests" list an officer
-- opens from it: Invite, Whisper, Decline. Every rule lives in Modules/JoinRequests.lua; this file draws
-- the rows and calls it (Rule 10). Nothing here opens by itself: the notice is a button, not the list.
----------------------------------------------------------------------
local UI = GuildOS.UI
local C  = GuildOS.Colors
local L  = GuildOS.L

local function JR() return GuildOS.JoinRequests end

local WIDTH, HEIGHT = 640, 400
local ROW_H, MAX_ROWS = 64, 50
local TOAST_SECONDS = 10

local ROLE_NAME = { TANK = L["Tank"], HEALER = L["Healer"], DPS = L["DPS"] }

local function className(class)
    return (LOCALIZED_CLASS_NAMES_MALE and LOCALIZED_CLASS_NAMES_MALE[class]) or class
end

-- "3 open", and "1 open" where the language has a singular.
function GuildOS:JoinRequestsOpenText(n)
    if n == 1 then return L["1 open"] end
    return string.format(L["%d open"], n)
end

-- "Paladin 12 · Healer" (the mock's list) or "Paladin 12, Healer" (its notice), whatever of it the request carried.
local function Detail(r, sep)
    local parts = {}
    if r.class or r.level then
        parts[#parts + 1] = ((r.class and className(r.class) or "") .. " " .. (r.level or "")):gsub("^%s+", ""):gsub("%s+$", "")
    end
    if r.role then parts[#parts + 1] = ROLE_NAME[r.role] end
    return table.concat(parts, sep or " \194\183 ")
end

-- "4m ago · online now", "1h ago · came from the site", "yesterday · delivered by Bruno Reis"...
local function Meta(r)
    local parts = { GuildOS:TimeAgo(r.at) }
    if r.status == "invited" then
        parts[#parts + 1] = string.format(L["Invited by %s"], r.decidedBy or "?")
    elseif r.status == "declined" then
        parts[#parts + 1] = string.format(L["Declined by %s"], r.decidedBy or "?")
    elseif r.status == "expired" then
        parts[#parts + 1] = L["expired"]
    elseif r.source == "site" then
        parts[#parts + 1] = L["came from the site"]
    else
        parts[#parts + 1] = (GetServerTime() - (r.seen or 0) < JR().ONLINE_SECONDS) and L["online now"] or L["offline"]
        if r.relayedBy then parts[#parts + 1] = string.format(L["delivered by %s"], r.relayedBy) end
    end
    return table.concat(parts, " \194\183 ")
end

local function Build()
    local f = CreateFrame("Frame", "GuildOSJoinRequests", UIParent, "BackdropTemplate")
    f:SetSize(WIDTH, HEIGHT)
    f:SetPoint("CENTER")
    f:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = GuildOS.UI:Edge(f) })
    f:SetBackdropColor(0.058, 0.058, 0.075, 0.98)
    f:SetBackdropBorderColor(C.border.r, C.border.g, C.border.b, C.border.a)
    UI:StylePopup(f)
    f:SetFrameStrata("DIALOG")
    f:SetMovable(true); f:EnableMouse(true); f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", function(self) self:StartMoving() end)
    f:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)
    table.insert(UISpecialFrames, "GuildOSJoinRequests")

    local title = UI:CreateTitle(f, L["Join requests"], 14)
    title:SetPoint("TOPLEFT", 14, -12)
    local count = UI:CreateText(f, "", 11, C.textSoft.r, C.textSoft.g, C.textSoft.b)
    count:SetPoint("TOPRIGHT", -40, -15)
    local close = UI:CreateCloseButton(f)
    close:SetPoint("TOPRIGHT", -6, -6)
    close:SetScript("OnClick", function() f:Hide() end)

    f.Refresh = GuildOS:BuildJoinRequestsList(f, count, "GuildOSJoinRequestsScroll", 40, 8, 28, 10)
    return f
end

-- EKO patch: the list itself, into any frame: the popup above and the Recruitment tab's own
-- "Join requests" sub-tab. `count` is the "2 open" text to keep; the insets place the scroll area.
function GuildOS:BuildJoinRequestsList(host, count, scrollName, top, left, right, bottom)
    local scroll, content = UI:CreateScrollFrame(host, scrollName)
    scroll:SetPoint("TOPLEFT", left or 0, -(top or 0))
    scroll:SetPoint("BOTTOMRIGHT", -(right or 0), bottom or 0)
    content:SetSize(WIDTH - 40, 1)
    if UI.BindScrollChildWidth then UI:BindScrollChildWidth(scroll, content) end

    local empty = UI:CreateText(host, L["Nobody has asked to join yet."], 11, C.label.r, C.label.g, C.label.b)
    empty:SetPoint("TOP", 0, -((top or 0) + 80))

    local rows = {}
    local function Row(i)
        if rows[i] then return rows[i] end
        local row = CreateFrame("Frame", nil, content)
        row:SetHeight(ROW_H)
        row:SetPoint("TOPLEFT", 0, -(i - 1) * ROW_H)
        row:SetPoint("TOPRIGHT", 0, -(i - 1) * ROW_H)
        row.name = UI:CreateText(row, "", 12)
        row.name:SetPoint("TOPLEFT", 6, -8)
        row.detail = UI:CreateText(row, "", 11, C.textSoft.r, C.textSoft.g, C.textSoft.b)
        row.detail:SetPoint("LEFT", row.name, "RIGHT", 8, 0)
        row.note = UI:CreateText(row, "", 11, C.textSoft.r, C.textSoft.g, C.textSoft.b)
        row.note:SetPoint("TOPLEFT", 6, -26)
        row.note:SetWidth(330); row.note:SetJustifyH("LEFT"); row.note:SetWordWrap(false)
        row.meta = UI:CreateText(row, "", 10, C.label.r, C.label.g, C.label.b)
        row.meta:SetPoint("TOPLEFT", 6, -44)
        row.meta:SetWidth(330); row.meta:SetJustifyH("LEFT"); row.meta:SetWordWrap(false)
        row.remove = UI:CreateButton(row, L["Remove"], 76, 24)
        row.remove:SetPoint("RIGHT", -6, 0)
        UI:SetButtonVariant(row.remove, "ghost")
        row.decline = UI:CreateButton(row, L["Decline"], 70, 24)
        row.decline:SetPoint("RIGHT", -6, 0)
        UI:SetButtonVariant(row.decline, "danger")
        row.whisper = UI:CreateButton(row, L["Whisper"], 76, 24)
        row.whisper:SetPoint("RIGHT", row.decline, "LEFT", -6, 0)
        row.invite = UI:CreateButton(row, "Approve", 76, 24)
        row.invite:SetPoint("RIGHT", row.whisper, "LEFT", -6, 0)
        UI:SetButtonVariant(row.invite, "primary")
        rows[i] = row
        return row
    end

    local function Refresh()
        local list = JR():List()
        local open = JR():OpenCount()
        count:SetText(GuildOS:JoinRequestsOpenText(open))
        empty:SetShown(#list == 0)
        for i, r in ipairs(list) do
            if i > MAX_ROWS then break end
            local row = Row(i)
            row.name:SetText(r.character)
            if r.class and GuildOS.ClassColors and GuildOS.ClassColors[r.class] then
                local cr, cg, cb = GuildOS:GetClassColor(r.class)
                row.name:SetTextColor(cr, cg, cb)
            else
                row.name:SetTextColor(C.text.r, C.text.g, C.text.b)
            end
            row.detail:SetText(Detail(r))
            row.note:SetText(r.note and ("\226\128\156" .. r.note .. "\226\128\157") or "")
            row.meta:SetText(Meta(r))
            local isOpen = r.status == "open"
            -- Invite is whoever the game lets invite; deciding is an officer's, and Decline would do nothing for anybody else.
            -- The game lets no addon invite off Anniversary (#256), and these requests are Forever's and retail's.
            -- EKO: Approve (was Invite, hidden on Forever): an officer's, on any open request. It puts
            -- /ginvite <name> in the chat box; the row closes when the game says the invite went.
            local officer = JR():CanDecide()
            row.invite:SetShown(isOpen and officer); row.whisper:SetShown(true)
            row.decline:SetShown(isOpen and officer); row.remove:SetShown(not isOpen and officer)
            -- Whisper sits left of the button on the right: Remove on a closed row, Decline on an open one.
            row.whisper:ClearAllPoints()
            row.whisper:SetPoint("RIGHT", (not isOpen and officer) and row.remove or row.decline, "LEFT", -6, 0)
            row.invite:SetEnabled(isOpen)
            row.invite:SetScript("OnClick", function() JR():Approve(r.id) end)
            row.decline:SetScript("OnClick", function() JR():Decide(r.id, "declined") end)
            row.remove:SetScript("OnClick", function() JR():Remove(r.id) end)
            row.whisper:SetScript("OnClick", function() ChatFrame_OpenChat("/w " .. GuildOS:WhisperTarget(r.character) .. " ") end)
            row:Show()
        end
        for i = #list + 1, #rows do rows[i]:Hide() end
        content:SetHeight(math.max(1, math.min(#list, MAX_ROWS) * ROW_H))
    end

    JR():Listen(function()
        if host:IsVisible() then Refresh() end
    end)
    return Refresh
end

-- EKO patch: the Recruitment tab's "Join requests" sub-tab: the count, the list, and how it works.
function GuildOS:CreateJoinRequestsPanel(parent)
    local count = UI:CreateText(parent, "", 11, C.textSoft.r, C.textSoft.g, C.textSoft.b)
    count:SetPoint("TOPLEFT", 0, -UI.GAP)
    local note = UI:CreateText(parent, L["Players who asked your guild to take them, from the game or from guildos.me."]
        .. " Approve puts /ginvite in your chat box: press Enter.", 10, C.label.r, C.label.g, C.label.b)
    note:SetPoint("LEFT", count, "RIGHT", 16, 0)
    local refresh = self:BuildJoinRequestsList(parent, count, "GuildOSJoinRequestsTabScroll", UI.GAP + 22, 0, 0, 0)
    return function()
        if JR() then GuildOS:SafeCall(JR().Refresh, JR()) end
        refresh()
    end
end

function GuildOS:ShowJoinRequests()
    if not JR() then return end
    local f = self.joinRequestsFrame or Build()
    self.joinRequestsFrame = f
    -- The site's requests come with the last export the companion left; read them now.
    GuildOS:SafeCall(JR().Refresh, JR())
    if self.SetMinimapAlert then self:SetMinimapAlert(false) end
    f.Refresh()
    f:Show(); f:Raise()
end

----------------------------------------------------------------------
-- The notice (the mock's "Novo pedido de guilda"): one small box, ten seconds, a click to see the list.
-- The minimap button lights too, which is what is on screen while the officer plays.
----------------------------------------------------------------------
local toast
local function BuildToast()
    local t = CreateFrame("Button", "GuildOSJoinRequestToast", UIParent, "BackdropTemplate")
    t:SetSize(280, 62)
    t:SetPoint("TOP", 0, -150)
    t:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = GuildOS.UI:Edge(t) })
    t:SetBackdropColor(0.058, 0.058, 0.075, 0.98)
    t:SetBackdropBorderColor(C.gold.r, C.gold.g, C.gold.b, 0.9)
    t:SetFrameStrata("DIALOG")
    t.title = UI:CreateTitle(t, L["New guild request"], 12)
    t.title:SetPoint("TOPLEFT", 10, -8)
    t.who = UI:CreateText(t, "", 11)
    t.who:SetPoint("TOPLEFT", 10, -26)
    t.who:SetWidth(260); t.who:SetJustifyH("LEFT"); t.who:SetWordWrap(false)
    t.hint = UI:CreateText(t, L["Click to see"], 10, C.label.r, C.label.g, C.label.b)
    t.hint:SetPoint("TOPLEFT", 10, -44)
    t:SetScript("OnClick", function(self)
        self:Hide()
        GuildOS:ShowJoinRequests()
    end)
    t:Hide()
    return t
end

-- Somebody asked this guild (an officer's client only; Modules/JoinRequests.lua says when).
function GuildOS:JoinRequestsHeard(r)
    if self.SetMinimapAlert then self:SetMinimapAlert(true) end
    if not (UI and r) then return end
    toast = toast or BuildToast()
    local detail = Detail(r, ", ")
    toast.who:SetText(r.character .. (detail ~= "" and (", " .. detail) or ""))
    toast.shownAt = GetTime()
    toast:Show()
    local shownAt = toast.shownAt
    GuildOS.Compat.After(TOAST_SECONDS, function()
        if toast and toast.shownAt == shownAt then toast:Hide() end
    end)
end
