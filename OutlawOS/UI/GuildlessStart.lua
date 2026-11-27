----------------------------------------------------------------------
-- Guild OS - Guildless start: apply to the Outlaws, or apply to their alliance
--
-- A character with no guild sees this at each login until it picks one. There is no
-- guild search here: both choices are for the Eastern Kingdoms Outlaws. "Apply to the
-- Outlaws" opens the join form, which sends a join request to the guild's officers.
-- "Apply to Alliance" opens the window below, with one row for the Outlaws: Apply sends
-- an alliance application to their ambassadors, from a guild master or Co-Guild Master of a guild
-- other than the Outlaws. Anyone else sees why they cannot apply, greyed out. An accepted application makes the
-- character a read-only observer (AllianceObserver).
-- Reminder: answers to these belong to the GM, Co-GM or another trusted official of the
-- guild. Alliance applications also need an ambassador (JR:CanDecideRow).
-- The choice window lists the Outlaws' guild master, recruiters and officers who are online
-- (OnlineLeaders), each with Whisper. Your own line shows your online status when you qualify.
-- Preview: the owner's character sees a preview button in Settings. It shows the same windows with
-- a banner, and nothing is saved or sent.
----------------------------------------------------------------------
local L = GuildOS.L
local UI = GuildOS.UI
local C = GuildOS.Colors

local GS = {}
GuildOS.GuildlessStart = GS

GS.MAX_ROWS = 8
GS.ROW_H = 34
GS.MAX_ONLINE = 5          -- names per column on the choice window; more show as "+N more"
GS.ONLINE_ROW_H = 24
GS.ONLINE_REFRESH = 15     -- seconds between repaints of the online list while the window is open

-- The guild both choices apply to, matched by name as EKO.lua matches it. No listing is
-- needed, so there is no search.
local OUTLAWS = "Eastern Kingdoms Outlaws"
local function outlawsAd() return { n = OUTLAWS } end

-- The one character that sees the preview button in Settings. Matched by name, as the addon matches
-- its own characters.
local PREVIEWER = "Vyctoria Windwhisper"

-- Each character's choice, kept account-wide so the same character is not asked twice.
local function choices()
    if type(GuildOSDB) ~= "table" then return {} end
    if type(GuildOSDB.guildlessChoice) ~= "table" then GuildOSDB.guildlessChoice = {} end
    return GuildOSDB.guildlessChoice
end

local function me() return GuildOS.Compat.PlayerName() end

function GS:Chosen() return choices()[me()] ~= nil end
function GS:Choose(kind)
    if self.previewing then return end
    choices()[me()] = kind
end

-- Only the owner's character sees the preview button.
function GS:IsPreviewer()
    local name = me() or ""
    return (name:match("^(.-)%-") or name) == PREVIEWER
end

local WHITE = "Interface\\Buttons\\WHITE8x8"

-- A panel in the house style: popup surface, lineHi border, draggable.
local function panel(name, w, h)
    local f = CreateFrame("Frame", name, UIParent, "BackdropTemplate")
    f:SetSize(w, h)
    f:SetFrameStrata("DIALOG")
    f:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = UI:Edge(f) })
    f:SetBackdropColor(C.popup.r, C.popup.g, C.popup.b, 1)
    f:SetBackdropBorderColor(C.lineHi.r, C.lineHi.g, C.lineHi.b, 1)
    f:EnableMouse(true)
    f:SetMovable(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    f:Hide()
    return f
end

----------------------------------------------------------------------
-- The choice: join, or alliance
----------------------------------------------------------------------
local choiceFrame

local function whisperTo(name)
    local target = GuildOS:WhisperTarget(name)
    if ChatFrame_SendTell then
        ChatFrame_SendTell(target)
    elseif ChatFrame_OpenChat then
        ChatFrame_OpenChat("/w " .. target .. " ")
    end
end

-- One column of the online list: its heading, the line for nobody online, and the line for more
-- names than fit. The name rows are made the first time they are needed. Names start a line below
-- the heading. The guild master column is one row wide and carries an Online label.
local function buildColumn(f, x, heading, top, max, opts)
    local col = { x = x, top = top, max = max, rows = {}, width = opts.width, status = opts.status }
    col.heading = UI:CreateHeaderText(f, heading, 10)
    col.heading:SetPoint("TOPLEFT", x, top)
    col.empty = UI:CreateText(f, L["Nobody online right now."], 11, C.textSoft.r, C.textSoft.g, C.textSoft.b)
    col.empty:SetPoint("TOPLEFT", x, top - 22)
    col.more = UI:CreateText(f, "", 10, C.label.r, C.label.g, C.label.b)
    col.more:SetPoint("TOPLEFT", x, top - 22 - max * GS.ONLINE_ROW_H)
    return col
end

-- Whether a listed name is our own character. Names may carry a realm after a dash.
local function isMe(name)
    local mine = me() or ""
    return (name:match("^(.-)%-") or name) == (mine:match("^(.-)%-") or mine)
end

local function makeOnlineRow(f, col, i)
    local row = CreateFrame("Frame", nil, f)
    row:SetSize(col.width or 200, GS.ONLINE_ROW_H)
    row:SetPoint("TOPLEFT", col.x, col.top - 22 - (i - 1) * GS.ONLINE_ROW_H)
    row.whisper = UI:CreateButton(row, L["Whisper"], 64, 20)
    if col.status then
        row.status = UI:CreateText(row, L["Online"], 10, C.ok.r, C.ok.g, C.ok.b)
    end
    row.name = UI:CreateText(row, "", 11, C.text.r, C.text.g, C.text.b)
    row.name:SetJustifyH("LEFT")
    return row
end

-- Lays out a row from its right edge: Whisper (hidden on your own line, so the rest runs to the edge),
-- then the Online label where the column has one, then the name in what is left.
local function anchorRow(row, col, own)
    row.whisper:SetShown(not own)
    row.whisper:ClearAllPoints()
    row.whisper:SetPoint("RIGHT", 0, 0)
    local edge, point, gap = row, "RIGHT", 0
    if not own then edge, point, gap = row.whisper, "LEFT", -8 end
    if row.status then
        row.status:ClearAllPoints()
        row.status:SetPoint("RIGHT", edge, point, gap, 0)
        edge, point, gap = row.status, "LEFT", -8
    end
    row.name:ClearAllPoints()
    row.name:SetPoint("LEFT", 0, 0)
    row.name:SetPoint("RIGHT", edge, point, gap, 0)
end

local function paintColumn(f, col, list)
    col.empty:SetShown(#list == 0)
    for i = 1, col.max do
        local e = list[i]
        local row = col.rows[i]
        if e then
            row = row or makeOnlineRow(f, col, i)
            col.rows[i] = row
            row.name:SetText(e.name)
            anchorRow(row, col, isMe(e.name))
            row.whisper:SetScript("OnClick", function() whisperTo(e.name) end)
            row:Show()
        elseif row then
            row:Hide()
        end
    end
    local extra = #list - col.max
    col.more:SetText(extra > 0 and string.format(L["+%d more"], extra) or "")
end

-- Repaints the three lists from the online list. Nothing is done while the window is closed.
function GS:RefreshOnline()
    if not choiceFrame or not choiceFrame:IsShown() then return end
    local OL = GuildOS.OnlineLeaders
    if not OL then return end
    local guildMasters, recruiters, officers = OL:List()
    paintColumn(choiceFrame, choiceFrame.guildMaster, guildMasters)
    paintColumn(choiceFrame, choiceFrame.recruiters, recruiters)
    paintColumn(choiceFrame, choiceFrame.officers, officers)
end

local function buildChoice()
    local f = panel("GuildOSGuildlessChoice", 460, 450)
    f:SetPoint("CENTER", 0, 120)

    f.title = UI:CreateTitle(f, L["Looking to join?"], 18)
    f.title:SetPoint("TOP", 0, -16)

    local body = UI:CreateText(f, L["Are you looking to join the Outlaws, or apply for an alliance with us?"],
        12, C.text.r, C.text.g, C.text.b)
    body:SetPoint("TOPLEFT", 20, -48)
    body:SetPoint("TOPRIGHT", -20, -48)
    body:SetJustifyH("LEFT")
    body:SetWordWrap(true)

    f.onlineTitle = UI:CreateHeaderText(f, L["Online now"], 10)
    f.onlineTitle:SetPoint("TOPLEFT", 20, -96)
    f.guildMaster = buildColumn(f, 20, L["Guild Master"], -118, 1, { width = 420, status = true })
    f.recruiters = buildColumn(f, 20, L["Recruiters"], -186, GS.MAX_ONLINE, {})
    f.officers = buildColumn(f, 240, L["Officers"], -186, GS.MAX_ONLINE, {})

    local join = UI:CreateButton(f, L["Apply to the Outlaws"], 190, 28)
    join:SetPoint("BOTTOMLEFT", 20, 50)
    join:SetScript("OnClick", function()
        GS:Choose("join")
        f:Hide()
        if GuildOS.ShowJoinForm then GuildOS:ShowJoinForm(outlawsAd()) end
    end)

    local ally = UI:CreateButton(f, L["Apply to Alliance"], 190, 28)
    ally:SetPoint("BOTTOMRIGHT", -20, 50)
    ally:SetScript("OnClick", function()
        GS:Choose("alliance")
        f:Hide()
        GS:ShowAlliance()
    end)

    -- Shown only in the owner's preview: nothing is saved or sent from this window.
    f.banner = UI:CreateText(f, L["Preview: nothing is saved or sent."], 10, C.gold.r, C.gold.g, C.gold.b)
    f.banner:SetPoint("BOTTOM", 0, 86)
    f.banner:SetShown(false)

    -- No close that counts as a choice: it comes back at the next login until one is made.
    local later = UI:CreateButton(f, L["Not now"], 90, 22)
    later:SetPoint("BOTTOM", 0, 14)
    UI:SetButtonVariant(later, "ghost")
    later:SetScript("OnClick", function()
        if not GS.previewing then GS.hiddenThisSession = true end
        f:Hide()
    end)

    -- The online list repaints while the window is open.
    f:SetScript("OnShow", function()
        GS:RefreshOnline()
        if not f.ticker and C_Timer and C_Timer.NewTicker then
            f.ticker = C_Timer.NewTicker(GS.ONLINE_REFRESH, function() GS:RefreshOnline() end)
        end
    end)
    f:SetScript("OnHide", function()
        if f.ticker then f.ticker:Cancel(); f.ticker = nil end
    end)
    return f
end

-- At login, preview is nil. The owner's preview passes true: the same window with a banner, and nothing
-- saved or sent.
function GS:ShowChoice(preview)
    self.previewing = preview and true or false
    choiceFrame = choiceFrame or buildChoice()
    choiceFrame.banner:SetShown(self.previewing)
    choiceFrame:Show()
    choiceFrame:Raise()
end

-- The owner's preview of this screen, opened from Settings.
function GS:Preview()
    self:ShowChoice(true)
end

-- At login, for a guildless character that has not chosen yet and is not already observing.
function GuildOS:MaybeShowGuildlessChoice()
    if IsInGuild() or GS:Chosen() or GS.hiddenThisSession then return end
    local obs = GuildOS.AllianceObserver
    if obs and obs:IsObserving() then return end
    GS:ShowChoice()
end

----------------------------------------------------------------------
-- Apply to Alliance: the Outlaws' alliance, with Apply
----------------------------------------------------------------------
local allyFrame
local rows = {}

local function statusOf(ad)
    local JR = GuildOS.JoinRequests
    local e = JR and JR:Latest(ad)
    if not e or e.kind ~= "alliance" then return nil end
    if e.status == "open" then return L["Waiting for an answer"] end
    if e.status == "invited" then return L["Accepted"] end
    if e.status == "declined" then return L["Declined"] end
    return nil
end

local REASONS = {
    ["already"] = "You already applied to this guild.",
    ["too-many"] = "You have too many open applications. Wait for an answer first.",
    ["in-guild"] = "You are in a guild, so you cannot apply.",
    ["no-guild"] = "You are not in a guild. Only a guild master or Co-Guild Master can apply for their guild.",
    ["outlaws"] = "Eastern Kingdoms Outlaws is the guild applied to, so its members cannot apply from here.",
    ["rank"] = "Only a guild master or Co-Guild Master can apply for their guild.",
    ["no-ad"] = "That guild has no listing to apply through.",
}

function GS:Apply(ad)
    if self.previewing then
        GuildOS:Print(L["Preview: nothing was sent."])
        return
    end
    local JR = GuildOS.JoinRequests
    if not JR then return end
    local e, err = JR:Send(ad, "", "alliance")
    if e then
        GuildOS:Print(string.format(L["Alliance application sent to %s."], ad.n))
    else
        GuildOS:Print(L[REASONS[err or ""] or "Could not send the application."])
    end
    self:Refresh()
end

-- The alliance window lists the Outlaws only. There is no search, so there is one row.
local function listedGuilds()
    return { outlawsAd() }
end

local function makeRow(parent, i)
    local row = CreateFrame("Frame", nil, parent)
    row:SetSize(440, GS.ROW_H - 4)
    row:SetPoint("TOPLEFT", 0, -(i - 1) * GS.ROW_H)
    row.apply = UI:CreateButton(row, L["Apply"], 90, 24)
    row.apply:SetPoint("RIGHT", -4, 0)
    row.status = UI:CreateText(row, "", 11, C.textSoft.r, C.textSoft.g, C.textSoft.b)
    row.status:SetPoint("RIGHT", row.apply, "LEFT", -10, 0)
    row.name = UI:CreateText(row, "", 12, C.text.r, C.text.g, C.text.b)
    row.name:SetPoint("LEFT", 4, 0)
    row.name:SetPoint("RIGHT", row.status, "LEFT", -8, 0)
    row.name:SetJustifyH("LEFT")
    return row
end

local function build()
    local f = panel("GuildOSAllianceApply", 480, 340)
    f:SetPoint("CENTER", 0, 40)

    f.title = UI:CreateTitle(f, L["Apply to an alliance"], 18)
    f.title:SetPoint("TOP", 0, -16)

    f.body = UI:CreateText(f, L["Apply to join the Outlaws' alliance. Its ambassadors see your application and can accept or decline it. Once accepted, you can watch the alliance read-only: leaders online, events and who has signed up."],
        11, C.text.r, C.text.g, C.text.b)
    f.body:SetPoint("TOPLEFT", 20, -46)
    f.body:SetPoint("TOPRIGHT", -20, -46)
    f.body:SetJustifyH("LEFT")
    f.body:SetWordWrap(true)

    -- Who may apply, then your own guild and rank, then why Apply is greyed out when it is.
    f.who = UI:CreateText(f, L["Only a guild master or a Co-Guild Master can apply, for the guild they lead. The application names that guild."],
        11, C.textSoft.r, C.textSoft.g, C.textSoft.b)
    f.who:SetPoint("TOPLEFT", 20, -104)
    f.who:SetPoint("TOPRIGHT", -20, -104)
    f.who:SetJustifyH("LEFT")
    f.who:SetWordWrap(true)

    f.guild = UI:CreateText(f, "", 11, C.text.r, C.text.g, C.text.b)
    f.guild:SetPoint("TOPLEFT", 20, -140)
    f.guild:SetPoint("TOPRIGHT", -20, -140)
    f.guild:SetJustifyH("LEFT")

    f.why = UI:CreateText(f, "", 10, C.textSoft.r, C.textSoft.g, C.textSoft.b)
    f.why:SetPoint("TOPLEFT", 20, -158)
    f.why:SetPoint("TOPRIGHT", -20, -158)
    f.why:SetJustifyH("LEFT")
    f.why:SetWordWrap(true)

    f.list = CreateFrame("Frame", nil, f)
    f.list:SetPoint("TOPLEFT", 20, -190)
    f.list:SetPoint("TOPRIGHT", -20, -190)
    f.list:SetHeight(GS.MAX_ROWS * GS.ROW_H)

    f.steps = UI:CreateText(f, L["What happens next: apply, and your guild is named on the application. An Outlaws ambassador accepts or declines it. Once accepted, you watch the alliance read-only."],
        10, C.label.r, C.label.g, C.label.b)
    f.steps:SetPoint("TOPLEFT", 20, -248)
    f.steps:SetPoint("TOPRIGHT", -20, -248)
    f.steps:SetJustifyH("LEFT")
    f.steps:SetWordWrap(true)

    local close = UI:CreateButton(f, L["Close"], 90, 24)
    close:SetPoint("BOTTOM", 0, 14)
    close:SetScript("OnClick", function() f:Hide() end)
    return f
end

function GS:Refresh()
    if not allyFrame or not allyFrame:IsShown() then return end
    local JR = GuildOS.JoinRequests
    local ok, detail = false, "no-guild"
    if JR then ok, detail = JR:CanApplyAlliance() end
    local guild, rank = GetGuildInfo("player")
    if IsInGuild() and guild and guild ~= "" then
        allyFrame.guild:SetText(string.format(L["Your guild: %s, rank: %s"], guild, rank or ""))
    else
        allyFrame.guild:SetText(L["You are not in a guild."])
    end
    if ok then
        allyFrame.why:SetText(string.format(L["You can apply for %s."], detail))
        allyFrame.why:SetTextColor(C.textSoft.r, C.textSoft.g, C.textSoft.b)
    else
        allyFrame.why:SetText(L[REASONS[detail] or "Could not send the application."])
        local bad = C.danger or C.textSoft
        allyFrame.why:SetTextColor(bad.r, bad.g, bad.b)
    end
    local ads = listedGuilds()
    for i = 1, GS.MAX_ROWS do
        local ad = ads[i]
        local row = rows[i]
        if ad then
            row = row or makeRow(allyFrame.list, i)
            rows[i] = row
            local state = statusOf(ad)
            row.name:SetText(ad.n)
            row.status:SetText(state or "")
            row.apply:SetEnabled(state == nil and ok)
            row.apply:SetScript("OnClick", function() GS:Apply(ad) end)
            row:Show()
        elseif row then
            row:Hide()
        end
    end
end

function GS:ShowAlliance()
    allyFrame = allyFrame or build()
    allyFrame:Show()
    allyFrame:Raise()
    self:Refresh()
end

-- Answers to an application arrive from the join-request queue: repaint while the window is open.
if GuildOS.JoinRequests and GuildOS.JoinRequests.Listen then
    GuildOS.JoinRequests:Listen(function() GS:Refresh() end)
end
if GuildOS.OnlineLeaders and GuildOS.OnlineLeaders.Listen then
    GuildOS.OnlineLeaders:Listen(function() GS:RefreshOnline() end)
end
