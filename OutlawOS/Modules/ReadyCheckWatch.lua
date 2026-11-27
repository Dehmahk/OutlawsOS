----------------------------------------------------------------------
-- Guild OS - Ready check watch
-- Who did not answer a ready check in the raid. The game reports each answer as it comes; when the
-- check ends, the raiders who did not answer are listed in a small popup. Nothing is sent to anyone.
----------------------------------------------------------------------
local GuildOS = GuildOS
local UI = GuildOS.UI
local C  = GuildOS.Colors
local L  = GuildOS.L

local RC = {}
GuildOS.ReadyCheckWatch = RC

local current   -- the check running now: { answered = { [name] = true } }
local frame     -- the popup, built the first time it is needed

local function short(name)
    if not name then return nil end
    return name:match("^([^-]+)") or name
end

local function raidNames()
    local names = {}
    for i = 1, GetNumGroupMembers() or 0 do
        local name = GetRaidRosterInfo(i)
        if name then names[#names + 1] = short(name) end
    end
    return names
end

local function build()
    local f = CreateFrame("Frame", "GuildOSReadyCheckMissing", UIParent, "BackdropTemplate")
    f:SetSize(300, 160)
    f:SetPoint("CENTER")
    f:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = UI:Edge(f) })
    f:SetBackdropColor(GuildOS.Colors.bg.r, GuildOS.Colors.bg.g, GuildOS.Colors.bg.b, 0.98)
    f:SetBackdropBorderColor(C.border.r, C.border.g, C.border.b, C.border.a)
    UI:StylePopup(f)
    f:SetFrameStrata("DIALOG")
    f:SetMovable(true); f:EnableMouse(true); f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", function(self) self:StartMoving() end)
    f:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)
    table.insert(UISpecialFrames, "GuildOSReadyCheckMissing")

    local title = UI:CreateTitle(f, L["Ready check: not answered"], 14)
    title:SetPoint("TOPLEFT", 14, -12)
    local close = UI:CreateCloseButton(f)
    close:SetPoint("TOPRIGHT", -6, -6)
    close:SetScript("OnClick", function() f:Hide() end)

    f.body = UI:CreateText(f, "", 11, C.text.r, C.text.g, C.text.b)
    f.body:SetPoint("TOPLEFT", 14, -40)
    f.body:SetWidth(272)
    f.body:SetJustifyH("LEFT")
    f.body:SetWordWrap(true)
    f:Hide()
    frame = f
end

local function show(missing)
    if not frame then build() end
    frame.body:SetText(table.concat(missing, "\n"))
    frame:SetHeight(math.max(120, 56 + #missing * 15))
    frame:Show()
    frame:Raise()
end

function RC:Initialize()
    if self._started then return end
    self._started = true
    local ev = CreateFrame("Frame")
    GuildOS.Compat.RegisterEvent(ev, "READY_CHECK")
    GuildOS.Compat.RegisterEvent(ev, "READY_CHECK_CONFIRM")
    GuildOS.Compat.RegisterEvent(ev, "READY_CHECK_FINISHED")
    ev:SetScript("OnEvent", function(_, event, a1)
        if event == "READY_CHECK" then
            -- The one who started the check has answered it.
            current = { answered = {} }
            local starter = short(a1)
            if starter then current.answered[starter] = true end
        elseif event == "READY_CHECK_CONFIRM" then
            if current and a1 then
                local who = short(UnitName(a1))
                if who then current.answered[who] = true end
            end
        elseif event == "READY_CHECK_FINISHED" then
            local run = current
            current = nil
            if not run or not IsInRaid() then return end
            local missing = {}
            for _, name in ipairs(raidNames()) do
                if not run.answered[name] then missing[#missing + 1] = name end
            end
            if #missing > 0 then
                show(missing)
            else
                GuildOS:Print(L["Ready check: everyone answered."])
            end
        end
    end)
end
