----------------------------------------------------------------------
-- Guild OS - EKO patch: Eastern Kingdoms Outlaws extras
--
-- Only on clients that carry the EKO patch kit (WTF\EKO_Patches).
--   * Lore touches: Activity lines and a Matriarch greeting.
--   * Guild bank goal bar (the top of the Guild tab).
--   * Inner Circle: the new leaders' 2-week trials (Leadership tab).
--   * Ready for Outlaw: the promotion helper (Leadership tab).
--   * /eko goal <gold> <name>, /eko ready, /eko circle
----------------------------------------------------------------------
local EKO = {}
GuildOS.EKO = EKO

local L = GuildOS.L
local DAY = 86400

----------------------------------------------------------------------
-- The Outlaw theme: Leather & Parchment. Dark saddle-brown surfaces, parchment text, brass gold.
-- Re-points GuildOS's palette in place (GuildOS:RepointColors), so every screen picks it up.
-- /eko theme off goes back to GuildOS's own colours (after a /reload); /eko theme on brings it back.
----------------------------------------------------------------------
local function rgb(r, g, b) return { r = r, g = g, b = b, a = 1 } end
EKO.THEME = {
    bg       = rgb(0.114, 0.082, 0.059),  -- #1d150f window
    panel    = rgb(0.165, 0.114, 0.075),  -- #2a1d13 cards, title bar, headers
    popup    = rgb(0.200, 0.141, 0.102),  -- #33241a popups, tooltips, selected row
    well     = rgb(0.082, 0.059, 0.039),  -- #150f0a tables, inputs
    line     = rgb(0.290, 0.208, 0.141),  -- #4a3524 borders
    lineHi   = rgb(0.541, 0.416, 0.282),  -- #8a6a48 control borders
    text     = rgb(0.945, 0.894, 0.784),  -- #f1e4c8 parchment
    textSoft = rgb(0.788, 0.710, 0.576),  -- #c9b593
    label    = rgb(0.690, 0.604, 0.471),  -- #b09a78
    labelDim = rgb(0.541, 0.455, 0.345),  -- #8a7458
    disabled = rgb(0.369, 0.298, 0.227),  -- #5e4c3a
    gold     = rgb(0.831, 0.635, 0.298),  -- #d4a24c brass
    goldHover  = rgb(0.878, 0.706, 0.392),
    goldActive = rgb(0.722, 0.541, 0.227),
    onGold   = rgb(0.114, 0.075, 0.039),
    ok       = rgb(0.561, 0.812, 0.478),  -- #8fcf7a
    danger   = rgb(0.878, 0.439, 0.353),  -- #e0705a
}

local themeOriginal, themeApplying = nil, false
function EKO:ApplyTheme(on)
    local C = GuildOS.Colors
    if not (C and GuildOS.RepointColors) then return end
    if not themeOriginal then
        themeOriginal = {}
        for k in pairs(self.THEME) do
            local c = C[k]
            if c then themeOriginal[k] = { r = c.r, g = c.g, b = c.b, a = c.a } end
        end
    end
    themeApplying = true
    GuildOS:RepointColors(on and self.THEME or themeOriginal)
    themeApplying = false
    self.themeOn = on
end

-- On from the start, so every frame is built in it; a style that re-points the palette later gets it back.
EKO:ApplyTheme(true)
if hooksecurefunc and GuildOS.RepointColors then
    hooksecurefunc(GuildOS, "RepointColors", function()
        if not themeApplying and EKO.themeOn then EKO:ApplyTheme(true) end
    end)
end
local themeEv = CreateFrame("Frame")
themeEv:RegisterEvent("PLAYER_LOGIN")
themeEv:SetScript("OnEvent", function()
    if type(GuildOSDB) == "table" and GuildOSDB.ekoThemeOff then
        EKO:ApplyTheme(false)
        if EKO.ApplyFonts then EKO:ApplyFonts(false) end
    end
end)

----------------------------------------------------------------------
-- The Outlaw look (with the theme on): a western title font, the Wind & Blade emblem by the wordmark,
-- a brass-studded frame, leather grain, a candlelight glow under the title bar, open and close
-- sounds, brass section titles, and a banner at login. /eko theme off turns all of it off.
----------------------------------------------------------------------
EKO.FONT_TITLE = "Fonts\\MORPHEUS.TTF"

local function texOK(path)
    return GuildOS.Compat and GuildOS.Compat.TextureExists and GuildOS.Compat.TextureExists(path) or false
end
local function firstTex(list)
    for _, p in ipairs(list) do if texOK(p) then return p end end
    return nil
end
-- Outlaw artwork shipped in GuildOS/Media (TGA, power-of-two sizes). Falls back to stock art if missing.
local MEDIA = "Interface\\AddOns\\OutlawOS\\Media\\"
-- GetFileIDFromPath only knows the game archives, not addon folders, so our own files are used as shipped.
local function media(name) return MEDIA .. name end
local function playSound(kitName, fallback)
    if not PlaySound then return end
    local id = (SOUNDKIT and SOUNDKIT[kitName]) or fallback
    if id then pcall(PlaySound, id) end
end

-- Title fonts: the wordmark, window titles and section titles in Morpheus.
local fontOriginal
function EKO:ApplyFonts(on)
    local F = GuildOS.Fonts
    if not F then return end
    if not fontOriginal then
        fontOriginal = { wordmark = F.wordmark, windowTitle = F.windowTitle, sectionTitle = F.sectionTitle }
    end
    if on then
        F.wordmark = { file = self.FONT_TITLE, size = 22 }
        F.windowTitle = { file = self.FONT_TITLE, size = 18 }
        F.sectionTitle = { file = self.FONT_TITLE, size = 16 }
    else
        for k, v in pairs(fontOriginal) do F[k] = v end
    end
end
EKO:ApplyFonts(true)

-- Section titles in brass, their rule in worn leather.
do
    local UI = GuildOS.UI
    local orig = UI and UI.CreateSectionTitle
    if orig then
        UI.CreateSectionTitle = function(self, parent, text, first)
            local fs = orig(self, parent, text, first)
            if EKO.themeOn and fs then
                local C = GuildOS.Colors
                pcall(fs.SetTextColor, fs, C.gold.r, C.gold.g, C.gold.b)
                pcall(fs.SetShadowOffset, fs, 1, -1)
                pcall(fs.SetShadowColor, fs, 0, 0, 0, 0.8)
                if fs.rule then pcall(fs.rule.SetVertexColor, fs.rule, C.lineHi.r, C.lineHi.g, C.lineHi.b, 0.6) end
            end
            return fs
        end
    end
end

-- Where the wordmark starts in the title bar (UI/Window.lua reads this): room for the emblem.
function EKO:WordmarkX() return self.themeOn and 44 or 10 end

function EKO:SkinWindow(f)
    if not f or f.ekoSkinned or not self.themeOn then return end
    f.ekoSkinned = true
    local C = GuildOS.Colors

    -- Leather grain over the window's own background.
    local leatherPath = media("leather.tga")
    local grainPath = leatherPath or firstTex({ "Interface\\FrameGeneral\\UI-Background-Rock", "Interface\\DialogFrame\\UI-DialogBox-Background-Dark", "Interface\\FrameGeneral\\UI-Background-Marble" })
    if grainPath then
        local grain = f:CreateTexture(nil, "BACKGROUND", nil, 2)
        grain:SetPoint("TOPLEFT", 1, -1)
        grain:SetPoint("BOTTOMRIGHT", -1, 1)
        grain:SetTexture(grainPath, "REPEAT", "REPEAT")
        if grain.SetHorizTile then grain:SetHorizTile(true); grain:SetVertTile(true) end
        if leatherPath then
            grain:SetVertexColor(1, 1, 1)      -- the artwork already carries its colour
            grain:SetAlpha(0.55)
        else
            grain:SetVertexColor(0.62, 0.42, 0.26)
            grain:SetAlpha(0.18)
        end
        f.ekoGrain = grain
    end

    -- A brass frame around the window.
    local edge = firstTex({ "Interface\\DialogFrame\\UI-DialogBox-Gold-Border", "Interface\\Tooltips\\UI-Tooltip-Border" })
    if edge then
        local border = CreateFrame("Frame", nil, f, "BackdropTemplate")
        local gold = edge:find("Gold") ~= nil
        local out = gold and 10 or 4
        border:SetPoint("TOPLEFT", -out, out)
        border:SetPoint("BOTTOMRIGHT", out, -out)
        border:SetFrameLevel((f:GetFrameLevel() or 1) + 40)
        border:SetBackdrop({ edgeFile = edge, edgeSize = 16 })
        if gold then border:SetBackdropBorderColor(0.95, 0.78, 0.50, 1) else border:SetBackdropBorderColor(C.gold.r, C.gold.g, C.gold.b, 1) end
        border:EnableMouse(false)
        f.ekoBorder = border
    end

    local bar = f.titleBar
    if bar then
        -- The wood plank title bar, studded.
        local plank = media("titlebar2.tga")
        if plank then
            local pt = bar:CreateTexture(nil, "BACKGROUND", nil, 1)
            pt:SetAllPoints(bar)
            pt:SetTexture(plank)
            f.ekoPlank = pt
        end

        -- The Wind & Blade emblem: a dagger in a brass ring, left of the wordmark.
        local em = CreateFrame("Frame", nil, bar)
        em:SetSize(32, 32)
        em:SetPoint("LEFT", 6, 0)
        local emblemPath = media("emblem.tga")
        local icon = em:CreateTexture(nil, "ARTWORK")
        icon:SetAllPoints(em)
        if emblemPath then
            icon:SetTexture(emblemPath)           -- the artwork includes its own brass ring
        else
            icon:SetSize(20, 20); icon:SetPoint("CENTER")
            icon:SetTexture(firstTex({ "Interface\\Icons\\INV_Weapon_ShortBlade_05", "Interface\\Icons\\INV_Weapon_ShortBlade_01", "Interface\\Icons\\Ability_Rogue_Ambush" }) or "Interface\\Icons\\INV_Misc_QuestionMark")
            local mask = "Interface\\CharacterFrame\\TempPortraitAlphaMask"
            if icon.SetMask and texOK(mask) then icon:SetMask(mask) else icon:SetTexCoord(0.08, 0.92, 0.08, 0.92) end
        end
        f.ekoEmblem = em

        -- Candlelight: a warm glow under the title bar that breathes slowly.
        local glow = f:CreateTexture(nil, "BACKGROUND", nil, 3)
        glow:SetColorTexture(0.85, 0.60, 0.25, 0.10)   -- flat colour: gradients render as solid white on this client
        glow:SetPoint("TOPLEFT", bar, "BOTTOMLEFT", 0, 0)
        glow:SetPoint("TOPRIGHT", bar, "BOTTOMRIGHT", 0, 0)
        glow:SetHeight(60)
        if glow.CreateAnimationGroup then
            local ag = glow:CreateAnimationGroup()
            local a = ag:CreateAnimation("Alpha")
            a:SetFromAlpha(1); a:SetToAlpha(0.45); a:SetDuration(2.6); a:SetSmoothing("IN_OUT")
            ag:SetLooping("BOUNCE")
            ag:Play()
        end
        f.ekoGlow = glow
    end

    -- A quick fade in, and the sound of a ledger opening and closing.
    f:HookScript("OnShow", function(self)
        if not EKO.themeOn then return end
        if UIFrameFadeIn then UIFrameFadeIn(self, 0.18, 0, 1) end
        local db = EKO:DB()
        if not (db and db.noSound) then playSound("IG_QUEST_LOG_OPEN", 844) end
    end)
    f:HookScript("OnHide", function()
        if not EKO.themeOn then return end
        local db = EKO:DB()
        if not (db and db.noSound) then playSound("IG_QUEST_LOG_CLOSE", 845) end
    end)
end

-- The login banner: the guild's name and the motto across the screen, the first login of a session.
function EKO:ShowBanner(greeting)
    local C = GuildOS.Colors
    local b = self.banner
    if not b then
        b = CreateFrame("Frame", nil, UIParent)
        b:SetSize(800, 120)
        b:SetPoint("TOP", 0, -170)
        b:SetFrameStrata("HIGH")
        b:EnableMouse(false)
        local bg = b:CreateTexture(nil, "BACKGROUND")
        bg:SetColorTexture(0.08, 0.05, 0.03, 0.6)   -- flat colour: gradients render as solid white on this client
        bg:SetAllPoints()
        local top = b:CreateTexture(nil, "ARTWORK"); top:SetTexture("Interface\\Buttons\\WHITE8x8")
        top:SetHeight(1); top:SetPoint("TOPLEFT", 120, 0); top:SetPoint("TOPRIGHT", -120, 0); top:SetVertexColor(C.gold.r, C.gold.g, C.gold.b, 0.8)
        local bot = b:CreateTexture(nil, "ARTWORK"); bot:SetTexture("Interface\\Buttons\\WHITE8x8")
        bot:SetHeight(1); bot:SetPoint("BOTTOMLEFT", 120, 0); bot:SetPoint("BOTTOMRIGHT", -120, 0); bot:SetVertexColor(C.gold.r, C.gold.g, C.gold.b, 0.8)
        b.title = b:CreateFontString(nil, "OVERLAY")
        b.title:SetFont(self.FONT_TITLE, 34, "")
        b.title:SetShadowOffset(2, -2); b.title:SetShadowColor(0, 0, 0, 1)
        b.title:SetTextColor(C.gold.r, C.gold.g, C.gold.b)
        b.title:SetPoint("TOP", 0, -18)
        b.sub = b:CreateFontString(nil, "OVERLAY")
        b.sub:SetFont(self.FONT_TITLE, 18, "")
        b.sub:SetShadowOffset(1, -1); b.sub:SetShadowColor(0, 0, 0, 1)
        b.sub:SetTextColor(C.text.r, C.text.g, C.text.b)
        b.sub:SetPoint("TOP", b.title, "BOTTOM", 0, -10)
        b:Hide()
        self.banner = b
    end
    local _, rank = GetGuildInfo("player")
    local first = (UnitName("player") or ""):match("^(%S+)") or ""
    b.title:SetText("Eastern Kingdoms Outlaws")
    local line = greeting or (rank == "Guild Master" and "Welcome back, Matriarch." or ("Welcome back, " .. first .. "."))
    b.sub:SetText(line .. "   Free by choice, bound by bond.")
    b:SetAlpha(0)
    b:Show()
    if UIFrameFadeIn then UIFrameFadeIn(b, 1.2, 0, 1) else b:SetAlpha(1) end
    C_Timer.After(5, function()
        if UIFrameFadeOut then UIFrameFadeOut(b, 1.5, 1, 0) end
        C_Timer.After(1.6, function() b:Hide() end)
    end)
end

-- The line the banner shows when the Guild Master logs in, on every OutlawOS client in the guild.
local MATRIARCH_LINE = "The Matriarch has arrived."

local bannerEv = CreateFrame("Frame")
bannerEv:RegisterEvent("PLAYER_ENTERING_WORLD")
bannerEv:SetScript("OnEvent", function(_, _, isLogin)
    if not isLogin then return end
    C_Timer.After(6, function()
        GuildOS:SafeCall(function()
            local db = EKO:DB()
            local gname, _, rankIndex = GetGuildInfo("player")
            if gname ~= "Eastern Kingdoms Outlaws" then return end
            local isMatriarch = rankIndex == 0
            -- The Guild Master's login goes out to the guild, whatever this client's banner setting is.
            if isMatriarch and GuildOS.SyncService then
                GuildOS.SyncService:Publish("matriarch", "arrived", { by = UnitName("player") }, { priority = "NORMAL" })
            end
            if not EKO.themeOn or (db and db.noBanner) then return end
            EKO:ShowBanner(isMatriarch and MATRIARCH_LINE or nil)
        end)
    end)
end)

-- Another member's Guild Master login: the same banner here. Only the guild master on the roster counts,
-- so a message from anyone else claiming it is dropped.
local function isMatriarchOnRoster(sender)
    local want = (sender or ""):match("^([^-]+)")
    if not want or want == "" then return false end
    for i = 1, (GetNumGuildMembers() or 0) do
        local name, _, rankIndex = GetGuildRosterInfo(i)
        if name and rankIndex == 0 and (name:match("^([^-]+)") or name) == want then return true end
    end
    return false
end

if GuildOS.SyncService then
    GuildOS.SyncService:On("matriarch", function(_, sender)
        GuildOS:SafeCall(function()
            if not IsInGuild or not IsInGuild() then return end
            local db = EKO:DB()
            if not EKO.themeOn or (db and db.noBanner) then return end
            local gname = GetGuildInfo("player")
            if gname ~= "Eastern Kingdoms Outlaws" then return end
            if not isMatriarchOnRoster(sender) then return end
            EKO:ShowBanner(MATRIARCH_LINE)
        end)
    end)
end

-- Lore lines in the Activity feed (Modules/Digest.lua reads these keys).
L["%d new member(s): %s"] = "%d signed the Ledger: %s"
L["%d member(s) left"] = "%d rode off into the sunset"

----------------------------------------------------------------------
-- Defaults
----------------------------------------------------------------------
-- The 2-week leadership trials: Mon Nov 23 2026 00:00 EST through Mon Dec 7 2026 23:59 EST.
EKO.TRIAL_START = 1795410000
EKO.TRIAL_END = 1796705999

-- role -> the in-game rank that role should hold
EKO.ROLE_RANK = {
    ["Officer"] = "Officer",
    ["Raid Leader"] = "Raid Marshal",
    ["Event Organizer"] = "Herald",
    ["Recruiter"] = "Herald",
}

EKO.LEADERS = {
    { name = "Raistlin Danuz", role = "Officer" },
    { name = "Gigglebyte Fizzlebang", role = "Officer" },
    { name = "Korgran Ironborne", role = "Officer" },
    { name = "Donut Glitterblast", role = "Officer" },
    { name = "Essanance Serilia", role = "Raid Leader" },
    { name = "Genevieve Hunt", role = "Event Organizer" },
    { name = "Wizzly Crusher", role = "Recruiter" },
    { name = "Skadi Miniheals", role = "Recruiter" },
    { name = "Exadus Arrowstorm", role = "Recruiter" },
}

local NUDGE = "Hey! You've been leveling great and you're close to Outlaw rank. Last step is joining our Discord: discord.gg/AdD9kFnQWu. Once you're in, /register your character and you're set!"

----------------------------------------------------------------------
-- Saved state (per guild, in GuildOS.db)
----------------------------------------------------------------------
function EKO:DB()
    local db = GuildOS.db
    if not db then return nil end
    db.eko = db.eko or {}
    local e = db.eko
    e.goal = e.goal or { gold = 100, name = "Unlock the Guild Bank", told = {} }
    e.goal.told = e.goal.told or {}
    e.circle = e.circle or {}
    e.ready = e.ready or {}
    local r = e.ready
    r.minDays = r.minDays or 7
    r.minLevels = r.minLevels or 3
    r.onlineDays = r.onlineDays or 2
    r.skip = r.skip or {}
    r.wave = r.wave or {}
    r.levelAt = r.levelAt or {}
    return e
end

local function now() return GetServerTime and GetServerTime() or time() end
local function short(name)
    if type(name) ~= "string" then return nil end
    return name:match("^([^-]+)") or name
end

----------------------------------------------------------------------
-- The guild roster, read once per call
----------------------------------------------------------------------
-- A member's addon record. Records are keyed "Name-Realm" while the roster's names are short, so try
-- the short name, the roster's full name, then this realm's key.
function EKO:MemberRecord(name, full)
    local gdb = (GuildOS.db and GuildOS.db.members) or {}
    return gdb[name] or (full and gdb[full]) or gdb[GuildOS:GetPlayerKey(name) or name] or nil
end

-- { [short] = { name, rank, rankIndex, level, class, online, hoursOff, index } }
function EKO:Roster()
    local out = {}
    local n = GetNumGuildMembers and GetNumGuildMembers() or 0
    for i = 1, n do
        local name, rank, rankIndex, level, _, _, _, _, online, _, classFile = GetGuildRosterInfo(i)
        local s = short(name)
        if s then
            local hours = 0
            if not online and GetGuildRosterLastOnline then
                local y, m, d, h = GetGuildRosterLastOnline(i)
                hours = ((y or 0) * 365 + (m or 0) * 30 + (d or 0)) * 24 + (h or 0)
            end
            out[s] = { name = s, full = name, rank = rank, rankIndex = rankIndex, level = level or 0,
                class = classFile, online = online and true or false, hoursOff = hours, index = i }
        end
    end
    return out
end

local function hoursText(m)
    if m.online then return "|cff66dd66online|r" end
    local h = m.hoursOff or 0
    if h < 1 then return "<1h ago" end
    if h < 48 then return h .. "h ago" end
    return math.floor(h / 24) .. "d ago"
end

local function classColored(m)
    local hex = (GuildOS.GetClassColorHex and m.class) and GuildOS:GetClassColorHex(m.class) or "ffffff"
    if type(hex) ~= "string" or #hex ~= 6 then hex = "ffffff" end
    return "|cff" .. hex .. m.name .. "|r"
end

----------------------------------------------------------------------
-- Guild bank goal bar
----------------------------------------------------------------------
GuildOS.Dialogs = GuildOS.Dialogs or {}
GuildOS.Dialogs["EKO_GOAL_MILESTONE"] = {
    text = "%s",
    button1 = "Put it in guild chat",
    button2 = "Not now",
    OnAccept = function(_, data)
        if type(data) == "string" and ChatFrame_OpenChat then ChatFrame_OpenChat("/g " .. data) end
    end,
    timeout = 0, whileDead = true, hideOnEscape = true,
}

function EKO:BankMoney()
    local b = GuildOS.db and GuildOS.db.guildBank
    if not b or not b.moneyNow then return nil end
    return b.moneyNow, b.moneyTs
end

function EKO:BuildBankGoal(parent)
    local UI, C = GuildOS.UI, GuildOS.Colors
    local f = CreateFrame("Frame", nil, parent)
    f:SetHeight(30)
    local label = UI:CreateText(f, "", 12, C.text.r, C.text.g, C.text.b)
    label:SetPoint("TOPLEFT", 0, -1)
    local info = UI:CreateText(f, "", 10, C.textSoft.r, C.textSoft.g, C.textSoft.b)
    info:SetPoint("TOPRIGHT", 0, -2)
    local bg = f:CreateTexture(nil, "BACKGROUND")
    bg:SetTexture("Interface\\Buttons\\WHITE8x8")
    bg:SetPoint("BOTTOMLEFT", 0, 2)
    bg:SetPoint("BOTTOMRIGHT", 0, 2)
    bg:SetHeight(8)
    bg:SetVertexColor(C.bg0.r, C.bg0.g, C.bg0.b, 0.8)
    local fill = f:CreateTexture(nil, "ARTWORK")
    fill:SetTexture("Interface\\Buttons\\WHITE8x8")
    fill:SetPoint("BOTTOMLEFT", bg, "BOTTOMLEFT", 0, 0)
    fill:SetHeight(8)
    fill:SetVertexColor(C.gold.r, C.gold.g, C.gold.b, 1)

    local function refresh()
        local db = EKO:DB()
        if not db then return end
        local g = db.goal
        local money, ts = EKO:BankMoney()
        local goalCopper = (tonumber(g.gold) or 100) * 10000
        if not money then
            label:SetText("|cffE8C266" .. (g.name or "Guild bank goal") .. "|r  ·  open the guild bank once to read its gold")
            info:SetText("")
            fill:SetWidth(1)
            return
        end
        local pct = goalCopper > 0 and math.min(1, money / goalCopper) or 0
        local gold = math.floor(money / 10000)
        local left = math.max(0, (tonumber(g.gold) or 100) - gold)
        label:SetText(string.format("|cffE8C266%s|r  ·  %dg / %dg (%d%%)%s", g.name or "Guild bank goal", gold,
            tonumber(g.gold) or 100, math.floor(pct * 100), left > 0 and ("  ·  " .. left .. "g to go") or "  ·  goal reached!"))
        local age = ts and (now() - ts) or nil
        info:SetText(age and ("updated " .. (age < 3600 and (math.floor(age / 60) .. "m") or age < 2 * DAY and (math.floor(age / 3600) .. "h") or (math.floor(age / DAY) .. "d")) .. " ago") or "")
        local w = bg:GetWidth() or 0
        fill:SetWidth(math.max(1, w * pct))
        -- milestones: offered once each, never posted on its own
        for _, m in ipairs({ 25, 50, 75, 100 }) do
            local key = (g.name or "") .. ":" .. (g.gold or 0) .. ":" .. m
            if pct * 100 >= m and not g.told[key] then
                g.told[key] = true
                local msg = m >= 100
                    and string.format("We did it Outlaws! We hit our %dg goal: %s. Thank you all for every donation!", g.gold, g.name or "")
                    or string.format("We're %d%% of the way to our %dg goal (%s)! %dg to go, every bit helps. Deposit at any guild bank!", m, g.gold, g.name or "", left)
                GuildOS:ShowDialog("EKO_GOAL_MILESTONE", string.format("Guild bank goal: %d%%!\n\n%s", m, msg), nil, msg)
                break
            end
        end
    end
    f:SetScript("OnShow", function() GuildOS:SafeCall(refresh) end)
    f:SetScript("OnSizeChanged", function() GuildOS:SafeCall(refresh) end)
    f.Refresh = refresh
    return f
end

----------------------------------------------------------------------
-- Shared list helpers for the two Leadership sub-tabs
----------------------------------------------------------------------
local function makeList(panel, name, topOffset)
    local UI = GuildOS.UI
    local holder = CreateFrame("Frame", nil, panel)
    holder:SetPoint("TOPLEFT", 0, -(topOffset or 0))
    holder:SetPoint("BOTTOMRIGHT", 0, 0)
    local scroll, child = UI:CreateScrollFrame(holder, name)
    scroll:SetAllPoints()
    if UI.BindScrollChildWidth then UI:BindScrollChildWidth(scroll, child) end
    return holder, child
end

local function clear(child)
    for _, c in pairs({ child:GetChildren() }) do c:Hide() end
    for _, r in pairs({ child:GetRegions() }) do r:Hide() end
end

local function newRow(child, y, i, h)
    local C = GuildOS.Colors
    local row = CreateFrame("Frame", nil, child, "BackdropTemplate")
    row:SetHeight(h or 26)
    row:SetPoint("TOPLEFT", 0, -y)
    row:SetPoint("TOPRIGHT", 0, -y)
    row:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8" })
    local alt = (i % 2 == 0) and C.row1 or C.row2
    if alt then row:SetBackdropColor(alt.r, alt.g, alt.b, alt.a or 1) end
    return row
end

local function cell(row, text, x, w, r, g, b)
    local UI, C = GuildOS.UI, GuildOS.Colors
    local fs = UI:CreateText(row, text or "", 11, r or C.text.r, g or C.text.g, b or C.text.b)
    fs:SetPoint("LEFT", x, 0)
    if w then fs:SetWidth(w); fs:SetJustifyH("LEFT"); fs:SetWordWrap(false) end
    return fs
end

local function header(child, cols, y)
    local UI, C = GuildOS.UI, GuildOS.Colors
    local h = CreateFrame("Frame", nil, child)
    h:SetHeight(20)
    h:SetPoint("TOPLEFT", 0, -y)
    h:SetPoint("TOPRIGHT", 0, -y)
    for _, c in ipairs(cols) do
        local fs = UI:CreateText(h, c[1], 10, C.textSoft.r, C.textSoft.g, C.textSoft.b)
        fs:SetPoint("LEFT", c[2], 0)
    end
    return h
end

----------------------------------------------------------------------
-- Inner Circle: the leadership trials
----------------------------------------------------------------------
function EKO:TrialDay()
    local t = now()
    if t < self.TRIAL_START then return 0 end
    return math.min(14, math.floor((t - self.TRIAL_START) / DAY) + 1)
end

function EKO:BuildCircleSub(panel)
    local UI, C = GuildOS.UI, GuildOS.Colors
    local intro = UI:CreateText(panel, "", 12, C.textSoft.r, C.textSoft.g, C.textSoft.b)
    intro:SetPoint("TOPLEFT", 0, -4)
    local _, child = makeList(panel, "GuildOSEKOCircleScroll", 30)

    local refresh
    refresh = function()
        local db = EKO:DB()
        if not db then return end
        clear(child)
        local day, t = EKO:TrialDay(), now()
        if day == 0 then
            intro:SetText("Leadership trials start Monday, Nov 23 and run through Dec 7.")
        elseif t <= EKO.TRIAL_END then
            intro:SetText(string.format("Leadership trials: day %d of 14, ending Dec 7 (%d days left).", day, math.max(0, math.ceil((EKO.TRIAL_END - t) / DAY))))
        else
            intro:SetText("Leadership trials are over: confirm each leader or send them back to Outlaw.")
        end
        local roster = EKO:Roster()
        header(child, { { "LEADER", 4 }, { "ROLE", 180 }, { "RANK", 310 }, { "LAST ONLINE", 450 }, { "OATH", 560 }, { "NOTES", 610 } }, 0)
        local y = 22
        for i, ldr in ipairs(EKO.LEADERS) do
            local st = db.circle[ldr.name] or {}
            db.circle[ldr.name] = st
            local m = roster[ldr.name]
            local row = newRow(child, y, i, 30)
            cell(row, m and classColored(m) or ldr.name, 4, 170)
            cell(row, ldr.role, 180, 125, C.textDim.r, C.textDim.g, C.textDim.b)
            local want = EKO.ROLE_RANK[ldr.role]
            local rankText
            if not m then rankText = "|cffff6666not in guild|r"
            elseif m.rank == want then rankText = "|cff66dd66" .. m.rank .. "|r"
            else rankText = "|cffffcc33! " .. (m.rank or "?") .. "|r (" .. want .. ")" end
            cell(row, rankText, 310, 135)
            cell(row, m and hoursText(m) or "-", 450, 105, C.textDim.r, C.textDim.g, C.textDim.b)
            local cbw = UI:CreateCheckbox(row, "", 18)
            cbw:SetPoint("LEFT", 560, 0)
            cbw:SetWidth(24)
            cbw.checkbox:SetChecked(st.oath and true or false)
            cbw.checkbox.onChanged = function(_, v) st.oath = v and true or nil end
            local note = UI:CreateInput(row, 260, 22, { max = 120, placeholder = "note" })
            note:SetPoint("LEFT", 610, 0)
            note:SetText(st.note or "")
            note:SetScript("OnEnterPressed", function(self) st.note = self:GetText(); self:ClearFocus() end)
            note:SetScript("OnEditFocusLost", function(self) st.note = self:GetText() end)
            if t > EKO.TRIAL_END - DAY then
                if st.result then
                    cell(row, st.result == "confirmed" and "|cff66dd66Confirmed|r" or "|cffff9966Back to Outlaw|r", 880, 140)
                else
                    local ok = UI:CreateButton(row, "Confirm", 70, 22)
                    ok:SetPoint("LEFT", 880, 0)
                    ok:SetScript("OnClick", function() st.result = "confirmed"; refresh() end)
                    local back = UI:CreateButton(row, "Back to Outlaw", 110, 22)
                    back:SetPoint("LEFT", ok, "RIGHT", 6, 0)
                    back:SetScript("OnClick", function()
                        st.result = "outlaw"
                        if GuildOS.GuildManager and m then GuildOS.GuildManager:Demote(m.full) end
                        refresh()
                    end)
                end
            end
            y = y + 32
        end
        local foot = UI:CreateText(child, "Oath: tick it once they've reacted in #the-oath. Rank checks use the live roster. A yellow ! means their rank doesn't match their role yet.", 10, C.textSoft.r, C.textSoft.g, C.textSoft.b)
        foot:SetPoint("TOPLEFT", 4, -(y + 8))
        foot:SetPoint("TOPRIGHT", -4, -(y + 8))
        foot:SetJustifyH("LEFT")
        child:SetHeight(y + 40)
    end
    return refresh
end

----------------------------------------------------------------------
-- Ready for Outlaw: the promotion helper
----------------------------------------------------------------------
local function trialOf(name)
    local tr = GuildOS.db and GuildOS.db.trials
    if not tr then return nil end
    return tr[name] or tr[name .. "-" .. (GetRealmName and (GetRealmName() or "") or "")]
end

-- When this member joined (server time), from the trial record or the join log.
function EKO:JoinedAt(name)
    local best
    local t = trialOf(name)
    if t and t.startDate then best = t.startDate end
    local ev = GuildOS.db and GuildOS.db.rosterLog and GuildOS.db.rosterLog.events
    if ev then
        for _, e in ipairs(ev) do
            if e.action == "join" and short(e.target) == name and e.timestamp and (not best or e.timestamp < best) then
                best = e.timestamp
            end
        end
    end
    return best
end

-- The first level we know for this member: their trial's first snapshot, else the first level this
-- helper saw (it starts remembering from now on).
function EKO:FirstLevel(name, currentLevel)
    local t = trialOf(name)
    local first, at
    if t and t.snapshots then
        for _, s in pairs(t.snapshots) do
            if type(s) == "table" and s.level and (not at or (s.timestamp or 0) < at) then
                first, at = s.level, s.timestamp or 0
            end
        end
    end
    local db = self:DB()
    if not first then
        db.ready.levelAt[name] = db.ready.levelAt[name] or currentLevel
        first = db.ready.levelAt[name]
    end
    return first
end

function EKO:DungeonClears(name)
    local n = 0
    local j = GuildOS.db and GuildOS.db.journal and GuildOS.db.journal.entries
    if not j then return 0 end
    for _, e in pairs(j) do
        if type(e) == "table" and e.type == "dungeon.clear" and short(e.subjectKey) == name then n = n + 1 end
    end
    return n
end

function EKO:IsLeader(name)
    for _, l in ipairs(self.LEADERS) do if l.name == name then return true end end
    return false
end

-- Quick Tools (the Inner Circle's leadership-only tab): an officer, or the Raid Marshal rank that the
-- Raid Leader role holds. Event Organizers and recruiters are Heralds, so they are left out.
function EKO:CanQuickTools()
    if not (IsInGuild and IsInGuild()) then return false end
    local _, rank = GetGuildInfo("player")
    if not rank then return false end
    if rank == self.ROLE_RANK["Event Organizer"] or rank == self.ROLE_RANK["Recruiter"] then return false end
    return rank == self.ROLE_RANK["Raid Leader"] or GuildOS:IsOfficer() == true
end

-- Recruiting permissions (GuildOS:CanRecruit, CanRecruitByName) are in Modules/RecruitmentSystem.lua.

-- Verified Bounty Board clears this week that name the member (the clear's `who` list).
function EKO:BountyDoneBy(name)
    local n, key = 0, tostring(name):lower()
    for _, c in ipairs(self:VerifiedClears()) do
        for _, who in ipairs(c.who or {}) do
            if tostring(who):lower() == key then n = n + 1 break end
        end
    end
    return n
end

-- Whether a name is one of the finders in a LotW text ("Easy finders: Name, Name2").
function EKO:LotwListed(text, name)
    local key = tostring(name):lower()
    for token in tostring(text or ""):gmatch("[^,:\n]+") do
        if strtrim(token):lower() == key then return true end
    end
    return false
end

function EKO:Candidates()
    local db = self:DB()
    local r = db.ready
    local t = now()
    local alts = (GuildOS.db and GuildOS.db.altLinks) or {}
    local out = {}
    local lotwText = (self:Lotw() or {}).text or ""
    for name, m in pairs(self:Roster()) do
        local mem = self:MemberRecord(name, m.full)
        local gos = (mem and mem.addonVersion) and true or false
        if m.rank == "Recruit" and gos and not alts[name] and not self:IsLeader(name)
            and not (r.skip[name] and r.skip[name] > t) then
            local joined = self:JoinedAt(name)
            local days = joined and math.floor((t - joined) / DAY) or nil
            local first = self:FirstLevel(name, m.level)
            local gained = (m.level or 0) - (first or m.level or 0)
            local online = m.online or (m.hoursOff or 0) <= r.onlineDays * 24
            if days and days >= r.minDays and gained >= r.minLevels and online then
                local bounty = self:BountyDoneBy(name)
                local lotw = self:LotwListed(lotwText, name)
                if (not r.onlyBounty or bounty > 0) and (not r.onlyLotw or lotw) then
                    out[#out + 1] = { m = m, days = days, first = first, gained = gained, gos = gos,
                        clears = self:DungeonClears(name), bounty = bounty, lotw = lotw }
                end
            end
        end
    end
    -- Active first: online right now ahead of seen within the window, then the ones who gained most.
    table.sort(out, function(a, b)
        if r.sort == "name" then return a.m.name < b.m.name end
        if a.m.online ~= b.m.online then return a.m.online and true or false end
        if a.gained ~= b.gained then return a.gained > b.gained end
        return a.m.name < b.m.name
    end)
    return out
end

function EKO:WaveText()
    local db = self:DB()
    local names = {}
    for _, n in ipairs(db.ready.wave) do names[#names + 1] = n end
    if #names == 0 then return nil end
    local game = "Promotion wave! These Outlaws earned their Outlaw colors: " .. table.concat(names, ", ") .. "! Want to be next? Stay active and join our Discord: discord.gg/AdD9kFnQWu"
    local lines = {}
    for _, n in ipairs(names) do lines[#lines + 1] = "• " .. n end
    local discord = ":ekobadge: **Promotion Wave!** :ekobadge:\n\nThese Outlaws just earned their Outlaw colors! Congrats y'all! :ekoswords:\n\n"
        .. table.concat(lines, "\n")
        .. "\n\n**Want to be next?** 7+ days in the guild, stay active and leveling, and join the Discord and /register your character. Bounty Board clears and Location of the Week entries help too!\n\nSee you on the road, Outlaws! :ekoswords:"
    return "IN-GAME (" .. #game .. " characters; trim to 255 if needed):\n" .. game .. "\n\nDISCORD:\n" .. discord
end

function EKO:BuildReadySub(panel)
    local UI, C = GuildOS.UI, GuildOS.Colors
    local intro = UI:CreateText(panel, "", 12, C.textSoft.r, C.textSoft.g, C.textSoft.b)
    intro:SetPoint("TOPLEFT", 0, -4)
    local copyBtn = UI:CreateButton(panel, "Copy announcement", 150, 22)
    copyBtn:SetPoint("TOPRIGHT", 0, 0)
    local clearBtn = UI:CreateButton(panel, "Clear wave", 90, 22)
    clearBtn:SetPoint("RIGHT", copyBtn, "LEFT", -6, 0)
    local refresh
    -- Filters and sort: toggles that narrow the list, and the order it is shown in.
    local bountyBtn = UI:CreateButton(panel, "", 190, 22)
    bountyBtn:SetPoint("TOPLEFT", 0, -30)
    local lotwBtn = UI:CreateButton(panel, "", 170, 22)
    lotwBtn:SetPoint("LEFT", bountyBtn, "RIGHT", 6, 0)
    local sortBtn = UI:CreateButton(panel, "", 130, 22)
    sortBtn:SetPoint("LEFT", lotwBtn, "RIGHT", 6, 0)
    bountyBtn:SetScript("OnClick", function()
        local r = EKO:DB().ready
        r.onlyBounty = not r.onlyBounty
        refresh()
    end)
    lotwBtn:SetScript("OnClick", function()
        local r = EKO:DB().ready
        r.onlyLotw = not r.onlyLotw
        refresh()
    end)
    sortBtn:SetScript("OnClick", function()
        local r = EKO:DB().ready
        r.sort = (r.sort == "name") and "gained" or "name"
        refresh()
    end)
    local _, child = makeList(panel, "GuildOSEKOReadyScroll", 58)

    copyBtn:SetScript("OnClick", function()
        local txt = EKO:WaveText()
        if not txt then GuildOS:Print("Nobody in this promotion wave yet: use Promote on a row first.") return end
        GuildOS:ShowExportPopup("Promotion wave", txt)
    end)
    clearBtn:SetScript("OnClick", function()
        EKO:DB().ready.wave = {}
        refresh()
    end)

    refresh = function()
        local db = EKO:DB()
        if not db then return end
        clear(child)
        local r = db.ready
        local list = EKO:Candidates()
        intro:SetText(string.format("%d Recruits ready: %d+ days in the guild, %d+ levels gained, online in the last %d days, OutlawOS installed. Alts, Alter Egos and leadership left out. In this wave: %d.",
            #list, r.minDays, r.minLevels, r.onlineDays, #r.wave))
        bountyBtn.label:SetText(r.onlyBounty and "Cleared Bounty Board: on" or "Cleared Bounty Board: off")
        lotwBtn.label:SetText(r.onlyLotw and "Submitted LOTW: on" or "Submitted LOTW: off")
        sortBtn.label:SetText(r.sort == "name" and "Sort: A to Z" or "Sort: active first")
        header(child, { { "MEMBER", 4 }, { "DAYS", 190 }, { "LEVELS", 240 }, { "LAST ONLINE", 330 }, { "GUILDOS", 430 }, { "CLEARS", 500 } }, 0)
        local y = 22
        local inWave = {}
        for _, n in ipairs(r.wave) do inWave[n] = true end
        for i, c in ipairs(list) do
            local m = c.m
            local row = newRow(child, y, i, 28)
            cell(row, classColored(m), 4, 180)
            cell(row, tostring(c.days), 190, 45)
            cell(row, string.format("%d > %d (+%d)", c.first or m.level, m.level, c.gained), 240, 85)
            cell(row, hoursText(m), 330, 95, C.textDim.r, C.textDim.g, C.textDim.b)
            cell(row, c.gos and "|cff66dd66yes|r" or "|cff888888no|r", 430, 60)
            cell(row, tostring(c.clears), 500, 50)
            local promo = UI:CreateButton(row, inWave[m.name] and "In wave" or "Promote", 80, 22)
            promo:SetPoint("LEFT", 560, 0)
            promo:SetScript("OnClick", function()
                if not inWave[m.name] then table.insert(r.wave, m.name) end
                if GuildOS.GuildManager then GuildOS.GuildManager:Promote(m.full) end
                refresh()
            end)
            local nudge = UI:CreateButton(row, "Nudge", 64, 22)
            nudge:SetPoint("LEFT", promo, "RIGHT", 6, 0)
            nudge:SetScript("OnClick", function()
                if SendChatMessage then SendChatMessage(NUDGE, "WHISPER", nil, m.full or m.name) end
                GuildOS:Print("Sent the Discord nudge to " .. m.name .. ".")
            end)
            local skip = UI:CreateButton(row, "Skip", 54, 22)
            skip:SetPoint("LEFT", nudge, "RIGHT", 6, 0)
            skip:SetScript("OnClick", function()
                r.skip[m.name] = now() + 7 * DAY
                refresh()
            end)
            y = y + 30
        end
        if #list == 0 then
            local e = UI:CreateText(child, "Nobody matches right now.", 12, C.textSoft.r, C.textSoft.g, C.textSoft.b)
            e:SetPoint("TOPLEFT", 4, -(y + 6))
            y = y + 24
        end
        local foot = UI:CreateText(child, "Promote opens the game's guild window (rank changes are Blizzard-protected) and adds them to the wave. Skip hides someone for 7 days. Clears = dungeon clears OutlawOS logged. Cleared Bounty Board = named in this week's verified clears. Submitted LOTW = named in this week's LotW finders. Rules: /eko ready <days> <levels> <online days>", 10, C.textSoft.r, C.textSoft.g, C.textSoft.b)
        foot:SetPoint("TOPLEFT", 4, -(y + 8))
        foot:SetPoint("TOPRIGHT", -4, -(y + 8))
        foot:SetJustifyH("LEFT")
        child:SetHeight(y + 60)
    end
    return refresh
end

----------------------------------------------------------------------
-- Suggestions (Leadership tab), EKO's version: what needs a leader today.
--   Needs attention / Trials ending soon / Promotion candidates / Cleanup
-- Trial OK / X here change this client only, with no whole-list broadcast (that disconnected the
-- client on Nov 21); the other officers get them with the next normal trial sync.
----------------------------------------------------------------------
EKO.SOON_DAYS = 3        -- "ending soon": trials ending within this many days
EKO.CLEANUP_DAYS = 14    -- Recruits offline this long are cleanup candidates
EKO.LEADER_AWAY_DAYS = 3 -- leaders not seen this long get flagged
local SECTION_MAX = 25   -- rows shown per section before "+N more"

local function setTrial(key, status)
    local TT = GuildOS.TrialTracker
    local t = GuildOS.db and GuildOS.db.trials and GuildOS.db.trials[key]
    if not (TT and t and GuildOS:IsOfficer()) then return false end
    t.status = status
    t.resolvedDate = now()
    t.resolvedBy = (GuildOS.Compat and GuildOS.Compat.PlayerName()) or UnitName("player")
    if TT.RefreshUI then GuildOS:SafeCall(function() TT:RefreshUI() end) end
    return true
end

-- Whether a Recruit meets the Ready for Outlaw rules (days, levels gained, online lately).
function EKO:MeetsRules(m)
    local r = self:DB().ready
    local joined = self:JoinedAt(m.name)
    local days = joined and math.floor((now() - joined) / DAY) or 0
    local first = self:FirstLevel(m.name, m.level)
    local gained = (m.level or 0) - (first or m.level or 0)
    local online = m.online or (m.hoursOff or 0) <= r.onlineDays * 24
    return days >= r.minDays and gained >= r.minLevels and online, gained, days
end

-- Everything the page shows, worked out from the live roster.
function EKO:SuggestData()
    local TT = GuildOS.TrialTracker
    local roster = self:Roster()
    local alts = (GuildOS.db and GuildOS.db.altLinks) or {}
    local t = now()
    local d = { soon = {}, cleanup = {}, leadersAway = {}, noGuildOSOnline = {}, noGuildOS = 0, total = 0, ready = 0 }
    for name, m in pairs(roster) do
        d.total = d.total + 1
        local rec = self:MemberRecord(name, m.full)
        if not (rec and rec.addonVersion) then
            d.noGuildOS = d.noGuildOS + 1
            if m.online then d.noGuildOSOnline[#d.noGuildOSOnline + 1] = name end
        end
        if m.rank == "Recruit" then
            local key = GuildOS.db.trials and (GuildOS.db.trials[name] and name or (m.full and GuildOS.db.trials[m.full] and m.full)) or nil
            local tr = key and GuildOS.db.trials[key]
            if tr and TT and TT:IsUnresolved(tr) then
                local left = TT:EndOf(tr) - t
                local meets, gained = false, 0
                if left <= self.SOON_DAYS * DAY then meets, gained = self:MeetsRules(m) end
                if left <= 0 and gained <= 0 then
                    d.cleanup[#d.cleanup + 1] = { m = m, why = "trial over, 0 levels gained" }
                    m.ekoCleanup = true
                end
            end
            if not m.ekoCleanup and not m.online and (m.hoursOff or 0) >= self.CLEANUP_DAYS * 24 and not alts[name] then
                d.cleanup[#d.cleanup + 1] = { m = m, why = math.floor((m.hoursOff or 0) / 24) .. " days offline" }
            end
        end
    end
    -- Ending soon: every unresolved trial the Trials list shows (not only members ranked Recruit),
    -- matched to the roster by name. A trial with no roster line can't be ruled on, so it is skipped.
    for _, act in ipairs(TT and TT:GetActiveTrials() or {}) do
        local m = roster[short(act.key)]
        local left = TT:EndOf(act.data) - t
        if m and left <= self.SOON_DAYS * DAY then
            local meets, gained = self:MeetsRules(m)
            if left <= 0 then d.ready = d.ready + 1 end
            d.soon[#d.soon + 1] = { m = m, key = act.key, left = left, meets = meets, gained = gained }
        end
    end
    for _, l in ipairs(self.LEADERS) do
        local m = roster[l.name]
        if m and not m.online and (m.hoursOff or 0) >= self.LEADER_AWAY_DAYS * 24 then
            d.leadersAway[#d.leadersAway + 1] = { m = m, role = l.role }
        elseif not m then
            d.leadersAway[#d.leadersAway + 1] = { name = l.name, role = l.role, missing = true }
        end
    end
    table.sort(d.soon, function(a, b) return a.left < b.left end)
    table.sort(d.cleanup, function(a, b) return (a.m.hoursOff or 0) > (b.m.hoursOff or 0) end)
    table.sort(d.noGuildOSOnline)
    d.joinOpen = GuildOS.JoinRequests and GuildOS.JoinRequests:OpenCount() or 0
    d.candidates = self:Candidates()
    return d
end

-- SuggestData, kept 30 seconds: the Now tab asks every 10 seconds and it walks the whole roster.
function EKO:SuggestCached()
    local t = GetTime and GetTime() or 0
    if not self._sugg or t - (self._suggAt or 0) > 30 then
        self._sugg = self:SuggestData()
        self._suggAt = t
    end
    return self._sugg
end

-- Joins today and in the last 7 days, each person once, from the roster log.
function EKO:JoinCounts()
    local ev = GuildOS.db and GuildOS.db.rosterLog and GuildOS.db.rosterLog.events or {}
    local t = now()
    local d = date("*t", t)
    local midnight = t - ((d.hour or 0) * 3600 + (d.min or 0) * 60 + (d.sec or 0))
    local today, week = {}, {}
    for _, e in ipairs(ev) do
        if e.action == "join" and e.target and e.timestamp then
            if e.timestamp >= t - 7 * DAY then week[e.target] = true end
            if e.timestamp >= midnight then today[e.target] = true end
        end
    end
    local a, b = 0, 0
    for _ in pairs(today) do a = a + 1 end
    for _ in pairs(week) do b = b + 1 end
    return a, b
end

local function leftText(s)
    if s <= 0 then return "|cffff6060ready to review|r" end
    if s < DAY then return "|cffffd060today|r" end
    return math.ceil(s / DAY) .. "d left"
end

function EKO:BuildSuggestSub(panel)
    local UI, C = GuildOS.UI, GuildOS.Colors
    local _, child = makeList(panel, "GuildOSEKOSuggestScroll", 0)
    local refresh

    local function section(text, y, first)
        local f = CreateFrame("Frame", nil, child)
        f:SetHeight(18)
        f:SetPoint("TOPLEFT", 0, -y)
        f:SetPoint("TOPRIGHT", 0, -y)
        local lbl = UI:CreateSectionTitle(f, text, first)
        lbl:SetPoint("TOPLEFT", 0, 0)
        return f
    end
    local function line(text, y, i)
        local row = newRow(child, y, i or 1, 24)
        cell(row, text, 8, nil, C.textSoft.r, C.textSoft.g, C.textSoft.b)
        return row
    end
    local function more(n, y)
        if n > SECTION_MAX then line(string.format("+%d more", n - SECTION_MAX), y); return y + 26 end
        return y
    end

    refresh = function()
        if not EKO:DB() then return end
        clear(child)
        local d = EKO:SuggestData()
        local y = 0

        -- 1. Needs attention
        section("NEEDS ATTENTION", y, true); y = y + 24
        local i = 0
        local function attn(text, btnText, fn)
            i = i + 1
            local row = line(text, y, i)
            if btnText then
                local b = UI:CreateButton(row, btnText, 110, 20)
                b:SetPoint("RIGHT", -8, 0)
                b:SetScript("OnClick", fn)
            end
            y = y + 26
        end
        if d.joinOpen > 0 then
            attn(string.format("%d open join request(s)", d.joinOpen), "Open requests", function() GuildOS:ShowJoinRequests() end)
        end
        if d.ready > 0 then
            attn(string.format("%d Recruit trial(s) ready for review (below)", d.ready))
        end
        for _, a in ipairs(d.leadersAway) do
            if a.missing then
                attn(string.format("%s (%s) isn't in the guild roster", a.name, a.role))
            else
                attn(string.format("%s (%s) not seen in %d days", classColored(a.m), a.role, math.floor((a.m.hoursOff or 0) / 24)), "Whisper", function()
                    ChatFrame_OpenChat("/w " .. (a.m.full or a.m.name) .. " ")
                end)
            end
        end
        local noGos = string.format("%d of %d members don't have OutlawOS", d.noGuildOS, d.total)
        if #d.noGuildOSOnline > 0 then
            local names = {}
            for k = 1, math.min(8, #d.noGuildOSOnline) do names[#names + 1] = d.noGuildOSOnline[k] end
            noGos = noGos .. string.format("  ·  online now: %s%s", table.concat(names, ", "), #d.noGuildOSOnline > 8 and string.format(" +%d", #d.noGuildOSOnline - 8) or "")
        end
        if d.noGuildOS > 0 then attn(noGos) end
        if i == 0 then line("All clear.", y); y = y + 26 end

        -- 2. Trials ending soon
        y = y + 20
        local meetCount = 0
        for _, s in ipairs(d.soon) do if s.meets then meetCount = meetCount + 1 end end
        local hdr = section(string.format("TRIALS ENDING SOON  (%d, next %d days)", #d.soon, EKO.SOON_DAYS), y)
        if meetCount > 0 and GuildOS:IsOfficer() then
            local all = UI:CreateButton(hdr, string.format("Approve the %d who meet the rules", meetCount), 230, 20)
            all:SetPoint("TOPRIGHT", 0, 2)
            all:SetScript("OnClick", function()
                local n = 0
                for _, s in ipairs(d.soon) do if s.meets and setTrial(s.key, "approved") then n = n + 1 end end
                GuildOS:Print(string.format("EKO: approved %d trial(s). Promote them in Ready for Outlaw.", n))
                refresh()
            end)
        end
        y = y + 24
        if #d.soon == 0 then
            line("No Recruit trials end in the next " .. EKO.SOON_DAYS .. " days.", y); y = y + 26
        else
            header(child, { { "MEMBER", 8 }, { "LEVEL", 200 }, { "GAINED", 260 }, { "LAST ONLINE", 330 }, { "ENDS", 430 }, { "RULES", 540 } }, y)
            y = y + 22
            for k, s in ipairs(d.soon) do
                if k > SECTION_MAX then break end
                local row = newRow(child, y, k, 26)
                cell(row, classColored(s.m), 8, 185)
                cell(row, tostring(s.m.level or "?"), 200, 50)
                cell(row, (s.gained >= 0 and "+" or "") .. s.gained, 260, 60)
                cell(row, hoursText(s.m), 330, 95, C.textDim.r, C.textDim.g, C.textDim.b)
                cell(row, leftText(s.left), 430, 105)
                cell(row, s.meets and "|cff66dd66meets|r" or "|cff888888not yet|r", 540, 60)
                local x = UI:CreateButton(row, "X", 24, 20)
                x:SetPoint("RIGHT", -8, 0)
                x:SetScript("OnClick", function() setTrial(s.key, "denied"); refresh() end)
                local ok = UI:CreateButton(row, "OK", 32, 20)
                ok:SetPoint("RIGHT", x, "LEFT", -4, 0)
                ok:SetScript("OnClick", function() setTrial(s.key, "approved"); refresh() end)
                y = y + 28
            end
            y = more(#d.soon, y)
        end

        -- 3. Promotion candidates (the Ready for Outlaw rules)
        y = y + 20
        local r = EKO:DB().ready
        section(string.format("PROMOTION CANDIDATES  (%d)", #d.candidates), y); y = y + 24
        line(string.format("Recruits with %d+ days, %d+ levels gained, online in the last %d days. Full list and the wave in Ready for Outlaw.", r.minDays, r.minLevels, r.onlineDays), y); y = y + 26
        local inWave = {}
        for _, n in ipairs(r.wave) do inWave[n] = true end
        for k, c in ipairs(d.candidates) do
            if k > SECTION_MAX then break end
            local m = c.m
            local row = newRow(child, y, k, 26)
            cell(row, classColored(m), 8, 185)
            cell(row, string.format("%d > %d (+%d)", c.first or m.level, m.level, c.gained), 200, 120)
            cell(row, c.days .. " days", 330, 95)
            cell(row, hoursText(m), 430, 100, C.textDim.r, C.textDim.g, C.textDim.b)
            local promo = UI:CreateButton(row, inWave[m.name] and "In wave" or "Promote", 80, 20)
            promo:SetPoint("RIGHT", -8, 0)
            promo:SetScript("OnClick", function()
                if not inWave[m.name] then table.insert(r.wave, m.name) end
                if GuildOS.GuildManager then GuildOS.GuildManager:Promote(m.full) end
                refresh()
            end)
            y = y + 28
        end
        if #d.candidates == 0 then line("Nobody matches right now.", y); y = y + 26 end
        y = more(#d.candidates, y)

        -- 4. Cleanup
        y = y + 20
        section(string.format("CLEANUP  (%d)", #d.cleanup), y); y = y + 24
        line(string.format("Recruits offline %d+ days, or whose trial ended with no levels gained. Alts left out.", EKO.CLEANUP_DAYS), y); y = y + 26
        local canKick = GuildOS.GuildManager and GuildOS.GuildManager:CanKick()
        for k, c in ipairs(d.cleanup) do
            if k > SECTION_MAX then break end
            local m = c.m
            local row = newRow(child, y, k, 26)
            cell(row, classColored(m), 8, 185)
            cell(row, "Lv " .. (m.level or "?"), 200, 60)
            cell(row, c.why, 260, 260, C.warn and C.warn.r, C.warn and C.warn.g, C.warn and C.warn.b)
            if canKick then
                local rm = UI:CreateButton(row, "Remove", 70, 20)
                rm:SetPoint("RIGHT", -8, 0)
                rm:SetScript("OnClick", function() GuildOS.GuildManager:ConfirmKick(m.full or m.name) end)
            end
            y = y + 28
        end
        if #d.cleanup == 0 then line("Nobody to clean up.", y); y = y + 26 end
        y = more(#d.cleanup, y)

        local foot = UI:CreateText(child, "OK / X here change your copy only (no sync blast); other officers get it with the next trial sync. Discord status isn't visible in-game.", 10, C.textSoft.r, C.textSoft.g, C.textSoft.b)
        foot:SetPoint("TOPLEFT", 4, -(y + 10))
        foot:SetPoint("TOPRIGHT", -4, -(y + 10))
        foot:SetJustifyH("LEFT")
        child:SetHeight(y + 50)
    end
    return refresh
end

----------------------------------------------------------------------
-- About the Outlaws: editable by the Guild Master and Co-Guild Masters.
-- The text is plain lines: "# Title" starts a section, *words* show in gold. A save is stored here and
-- sent to the guild (domain "ekoabout", GUILD only); a client keeps it only from a GM or Co-GM, and only
-- if it is newer than its own. A GM or Co-GM's client sends its copy again at login, so anyone offline
-- catches up then.
----------------------------------------------------------------------
EKO.ABOUT_EDITORS = { ["Guild Master"] = true, ["Co-Guild Master"] = true }
local ABOUT_GOLD = "|cffe6b84a"

local function rankOf(name)
    local s = short(name)
    for i = 1, (GetNumGuildMembers and GetNumGuildMembers() or 0) do
        local n, rank = GetGuildRosterInfo(i)
        if short(n) == s then return rank end
    end
    return nil
end

function EKO:CanEditAbout()
    if not (IsInGuild and IsInGuild()) then return false end
    local _, rank = GetGuildInfo("player")
    return rank and self.ABOUT_EDITORS[rank] and true or false
end

function EKO:AboutStored()
    local db = self:DB()
    return db and db.about
end

-- "# Title" lines and body lines -> { { title, lines = {...} }, ... }, *x* in gold. Pipes are dropped:
-- no escape codes or links from the text.
function EKO:ParseAbout(text)
    local out, cur = {}, nil
    text = tostring(text or ""):gsub("|", "")
    for raw in (text .. "\n"):gmatch("([^\n]*)\n") do
        local line = raw:gsub("\r", ""):match("^%s*(.-)%s*$")
        local title = line:match("^#%s*(.+)$")
        if title then
            cur = { title = title, lines = {} }
            out[#out + 1] = cur
        elseif line ~= "" then
            if not cur then cur = { title = "", lines = {} }; out[#out + 1] = cur end
            cur.lines[#cur.lines + 1] = line:gsub("%*(.-)%*", ABOUT_GOLD .. "%1|r")
        end
    end
    return out
end

-- The built-in sections back to editable text (gold -> *words*).
function EKO:AboutToText(sections)
    local parts = {}
    for _, s in ipairs(sections or {}) do
        parts[#parts + 1] = "# " .. (s.title or "")
        for _, l in ipairs(s.lines or {}) do
            parts[#parts + 1] = (l:gsub("|c%x%x%x%x%x%x%x%x(.-)|r", "*%1*"))
        end
        parts[#parts + 1] = ""
    end
    return table.concat(parts, "\n")
end

local function sendAbout(a)
    if GuildOS.SyncService and a and a.text then
        GuildOS.SyncService:Publish("ekoabout", "set", { text = a.text, rev = a.rev, by = a.by }, { priority = "BULK" })
    end
end

-- text nil: back to the built-in page.
function EKO:SaveAbout(text)
    if not self:CanEditAbout() then GuildOS:Print("Only the Guild Master and Co-Guild Masters can edit About the Outlaws.") return end
    local db = self:DB()
    db.about = { text = text or false, rev = now(), by = (GuildOS.Compat and GuildOS.Compat.PlayerName()) or UnitName("player") }
    sendAbout(db.about)
    if self.aboutRefresh then GuildOS:SafeCall(self.aboutRefresh) end
    GuildOS:Print("EKO: About the Outlaws saved and sent to everyone with OutlawOS.")
end

if GuildOS.SyncService then
    GuildOS.SyncService.GUILD_ONLY_DOMAINS.ekoabout = true
    GuildOS.SyncService:On("ekoabout", function(env, sender)
        local d = env and env.data
        if type(d) ~= "table" or type(d.rev) ~= "number" then return end
        if not EKO.ABOUT_EDITORS[rankOf(sender) or ""] then return end
        local db = EKO:DB()
        if not db then return end
        if db.about and (db.about.rev or 0) >= d.rev then return end
        db.about = { text = (type(d.text) == "string") and d.text or false, rev = d.rev, by = d.by or sender }
        if EKO.aboutRefresh then GuildOS:SafeCall(EKO.aboutRefresh) end
    end)
end

local aboutEv = CreateFrame("Frame")
aboutEv:RegisterEvent("PLAYER_LOGIN")
aboutEv:SetScript("OnEvent", function()
    C_Timer.After(25, function()
        GuildOS:SafeCall(function()
            local a = EKO:AboutStored()
            if a and EKO:CanEditAbout() then sendAbout(a) end
        end)
    end)
end)

-- The editor: one big text box, Save / Reset to default / Cancel.
function EKO:OpenAboutEditor(defaultText)
    local UI, C = GuildOS.UI, GuildOS.Colors
    local f = self.aboutEditor
    if not f then
        f = CreateFrame("Frame", "GuildOSEKOAboutEditor", UIParent, "BackdropTemplate")
        f:SetSize(760, 540)
        f:SetPoint("CENTER")
        f:SetFrameStrata("DIALOG")
        f:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
        f:SetBackdropColor(GuildOS.Colors.bg.r, GuildOS.Colors.bg.g, GuildOS.Colors.bg.b, 0.98)
        f:SetBackdropBorderColor(C.border.r, C.border.g, C.border.b, C.border.a or 1)
        f:SetMovable(true); f:EnableMouse(true); f:RegisterForDrag("LeftButton")
        f:SetScript("OnDragStart", f.StartMoving)
        f:SetScript("OnDragStop", f.StopMovingOrSizing)
        f:SetClampedToScreen(true)
        table.insert(UISpecialFrames, "GuildOSEKOAboutEditor")
        local title = UI:CreateTitle(f, "Edit About the Outlaws", 14)
        title:SetPoint("TOPLEFT", 14, -12)
        local hint = UI:CreateText(f, "Start a section with  # Title  ·  wrap words in  *stars*  to make them gold  ·  blank lines are ignored", 10, C.textSoft.r, C.textSoft.g, C.textSoft.b)
        hint:SetPoint("TOPLEFT", 14, -34)
        local well = CreateFrame("Frame", nil, f, "BackdropTemplate")
        well:SetPoint("TOPLEFT", 12, -54)
        well:SetPoint("BOTTOMRIGHT", -12, 48)
        well:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
        well:SetBackdropColor(C.well.r, C.well.g, C.well.b, 1)
        well:SetBackdropBorderColor(C.lineHi.r, C.lineHi.g, C.lineHi.b, 1)
        local scroll = CreateFrame("ScrollFrame", "GuildOSEKOAboutEditorScroll", well, "UIPanelScrollFrameTemplate")
        scroll:SetPoint("TOPLEFT", 6, -6)
        scroll:SetPoint("BOTTOMRIGHT", -26, 6)
        local edit = CreateFrame("EditBox", nil, scroll)
        edit:SetMultiLine(true)
        edit:SetAutoFocus(false)
        edit:SetWidth(690)
        GuildOS:ApplyFont(edit, 12)
        edit:SetTextColor(C.text.r, C.text.g, C.text.b)
        edit:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
        edit:SetScript("OnCursorChanged", function(_, _, y, _, h)
            local top = scroll:GetVerticalScroll()
            local bottom = top + scroll:GetHeight()
            y = -y
            if y < top then scroll:SetVerticalScroll(y) elseif y + h > bottom then scroll:SetVerticalScroll(math.max(0, y + h - scroll:GetHeight())) end
        end)
        scroll:SetScrollChild(edit)
        well:EnableMouse(true)
        well:SetScript("OnMouseDown", function() edit:SetFocus() end)
        f.edit = edit
        local cancel = UI:CreateButton(f, "Cancel", 80, 24)
        cancel:SetPoint("BOTTOMRIGHT", -12, 12)
        cancel:SetScript("OnClick", function() f:Hide() end)
        local save = UI:CreateButton(f, "Save", 80, 24)
        save:SetPoint("RIGHT", cancel, "LEFT", -8, 0)
        if UI.SetButtonVariant then UI:SetButtonVariant(save, "primary") end
        save:SetScript("OnClick", function()
            EKO:SaveAbout(f.edit:GetText())
            f:Hide()
        end)
        local reset = UI:CreateButton(f, "Reset to default", 130, 24)
        reset:SetPoint("BOTTOMLEFT", 12, 12)
        reset:SetScript("OnClick", function() f.edit:SetText(f.defaultText or "") end)
        f.by = UI:CreateText(f, "", 10, C.textSoft.r, C.textSoft.g, C.textSoft.b)
        f.by:SetPoint("LEFT", reset, "RIGHT", 12, 0)
        self.aboutEditor = f
    end
    f.defaultText = defaultText
    local a = self:AboutStored()
    f.edit:SetText((a and type(a.text) == "string") and a.text or defaultText or "")
    f.edit:SetCursorPosition(0)
    f.by:SetText(a and a.by and ("Last edited by " .. short(a.by) .. " " .. date("%b %d, %I:%M %p", a.rev)) or "Showing the built-in page")
    f:Show(); f:Raise()
end

----------------------------------------------------------------------
-- Journal extras (Guild > Journal): Bounty Board, weekly leaderboards, level firsts, recent clears.
-- The week runs Monday 00:00 to Sunday, like the Bounty Board. Clears come from GuildOS's journal,
-- which only members with GuildOS log, grouped into runs by their runId.
----------------------------------------------------------------------
EKO.CLASSES = { "WARRIOR", "PALADIN", "HUNTER", "ROGUE", "PRIEST", "SHAMAN", "MAGE", "WARLOCK", "DRUID" }
EKO.LEVEL_FIRSTS = { 20, 30, 40, 50, 60 }
local RECENT_RUNS = 12
local BOARD_N = 5

function EKO:WeekStart(t)
    t = t or now()
    local d = date("*t", t)
    local sinceMon = ((d.wday or 2) + 5) % 7
    return t - sinceMon * DAY - (d.hour or 0) * 3600 - (d.min or 0) * 60 - (d.sec or 0)
end

-- Each member's level at the week's start (first seen this week otherwise; a member whose trial
-- started this week counts from their first trial snapshot). Kept per week in db.eko.week.
function EKO:WeekLevels()
    local db = self:DB()
    if not db then return {} end
    local ws = self:WeekStart()
    if not db.week or db.week.start ~= ws then db.week = { start = ws, levels = {} } end
    local lv = db.week.levels
    for name, m in pairs(self:Roster()) do
        if not lv[name] then
            local start = m.level or 0
            local t = trialOf(name)
            if t and (t.startDate or 0) >= ws then start = math.min(start, self:FirstLevel(name, m.level) or start) end
            lv[name] = start
        end
    end
    return lv, ws
end

local function entries()
    local j = GuildOS.db and GuildOS.db.journal and GuildOS.db.journal.entries
    return type(j) == "table" and j or {}
end

-- Dungeon runs since `since`: { at, name, bosses, who = { short names } }, newest first. Each member
-- logs their own clear (runId = instance id : their own entry time), so one group is the clears of
-- the same instance (or dungeon) finished within 10 minutes of each other.
function EKO:Runs(since, keep)
    local out = {}
    local list = {}
    for _, e in pairs(entries()) do
        if type(e) == "table" and e.type == "dungeon.clear" and (e.at or 0) >= (since or 0) and e.data and (not keep or keep(e)) then list[#list + 1] = e end
    end
    table.sort(list, function(a, b) return (a.at or 0) < (b.at or 0) end)
    for _, e in ipairs(list) do
        local inst = e.data.runId and tostring(e.data.runId):match("^(%d+):")
        local name = e.data.dungeonName or e.data.dungeonId or "?"
        local r
        for k = #out, 1, -1 do
            local o = out[k]
            if (e.at or 0) - o.at > 600 then break end
            if o.name == name and (not inst or not o.inst or o.inst == inst) then r = o; break end
        end
        if not r then
            r = { inst = inst, at = e.at or 0, name = name, bosses = e.data.bosses or 0, who = {}, seen = {} }
            out[#out + 1] = r
        end
        do
            local s = short(e.subjectKey)
            if s and not r.seen[s] then r.seen[s] = true; r.who[#r.who + 1] = s end
            if (e.at or 0) > r.at then r.at = e.at end
            if (e.data.bosses or 0) > r.bosses then r.bosses = e.data.bosses end
        end
    end
    table.sort(out, function(a, b) return a.at > b.at end)
    for _, r in ipairs(out) do table.sort(r.who) end
    return out
end

function EKO:Leaderboards()
    local lv, ws = self:WeekLevels()
    local roster = self:Roster()
    local levelers = {}
    for name, m in pairs(roster) do
        local g = (m.level or 0) - (lv[name] or m.level or 0)
        if g > 0 then levelers[#levelers + 1] = { name = name, n = g, m = m } end
    end
    table.sort(levelers, function(a, b) if a.n ~= b.n then return a.n > b.n end return a.name < b.name end)
    local count = {}
    for _, r in ipairs(self:Runs(ws)) do
        for _, s in ipairs(r.who) do count[s] = (count[s] or 0) + 1 end
    end
    local runners = {}
    for s, n in pairs(count) do runners[#runners + 1] = { name = s, n = n, m = roster[s] } end
    table.sort(runners, function(a, b) if a.n ~= b.n then return a.n > b.n end return a.name < b.name end)
    return levelers, runners
end

-- First to each level (from the journal's level milestones) and the first of each class to max level.
function EKO:LevelFirsts()
    local firstAt, classMax = {}, {}
    local max = GuildOS.Client and GuildOS.Client.maxLevel or 60
    for _, e in pairs(entries()) do
        if type(e) == "table" and (e.type == "member.level" or e.type == "member.level60") then
            local level = e.type == "member.level60" and max or (e.data and e.data.level)
            local s = short(e.subjectKey)
            if level and s then
                local f = firstAt[level]
                if not f or (e.at or 0) < f.at then firstAt[level] = { name = s, at = e.at or 0 } end
                if level >= max then
                    local mem = self:MemberRecord(s, e.subjectKey)
                    local cls = mem and mem.class
                    if cls and (not classMax[cls] or (e.at or 0) < classMax[cls].at) then classMax[cls] = { name = s, at = e.at or 0 } end
                end
            end
        end
    end
    return firstAt, classMax
end

----------------------------------------------------------------------
-- The Bounty Board: this week's dungeons, set by an officer, synced (domain "ekobounty").
----------------------------------------------------------------------
-- "Low: The Hall of Thanes" lines -> { { tier, name } }.
-- A dungeon name as a key: "The Hall of Thanes" and "Hall of Thanes" both become "hallofthanes".
local function nameKey(s)
    local k = tostring(s or ""):lower():gsub("^the%s+", "")
    return (k:gsub("[^%w]", ""))
end

-- The group finder's activity id for a bounty dungeon, or nil.
function EKO:BountyActId(name)
    local cat = GuildOS.GroupActivities
    if not cat or not cat.byId then return nil end
    local want = nameKey(name)
    if want == "" then return nil end
    for id, it in pairs(cat.byId) do
        if nameKey(it.name) == want then return id end
    end
    return nil
end

-- This week's Bounty Board dungeons as a set of group finder activity ids: { [id] = true }.
function EKO:BountyActSet()
    local set = {}
    local bt = self:Bounties()
    if not bt then return set end
    for _, bnt in ipairs(self:ParseBounties(bt.text)) do
        local id = self:BountyActId(bnt.name)
        if id then set[id] = true end
    end
    return set
end

-- This week's Bounty Board dungeon names, comma-separated, or nil when none are posted.
-- How many active listings in the group finder want this activity.
function EKO:BountyLooking(actId)
    local B, store = GuildOS.LFGBoard, GuildOS.db and GuildOS.db.lfgBoard
    if not (actId and B and store) then return 0 end
    local n = 0
    for _, e in ipairs(B:ActiveList(store, GetServerTime())) do
        for _, id in ipairs(e.acts or {}) do
            if id == actId then n = n + 1 break end
        end
    end
    return n
end

function EKO:BountyNames()
    local bt = self:Bounties()
    local list = bt and self:ParseBounties(bt.text) or {}
    if #list == 0 then return nil end
    local names = {}
    for _, bnt in ipairs(list) do names[#names + 1] = bnt.name end
    return table.concat(names, ", ")
end

function EKO:ParseBounties(text)
    local out = {}
    for raw in (tostring(text or ""):gsub("|", "") .. "\n"):gmatch("([^\n]*)\n") do
        local line = raw:gsub("\r", ""):match("^%s*(.-)%s*$")
        if line ~= "" then
            local tier, name = line:match("^(%a+)%s*:%s*(.+)$")
            if not (tier and ({ low = 1, mid = 1, high = 1 })[tier:lower()]) then tier, name = nil, line end
            out[#out + 1] = { tier = tier and (tier:sub(1, 1):upper() .. tier:sub(2):lower()) or nil, name = name }
        end
    end
    return out
end

function EKO:Bounties()
    local db = self:DB()
    local b = db and db.bounty
    if not b or b.week ~= self:WeekStart() then return nil end
    return b
end

-- Whether a dungeon is on this week's Bounty Board. The board's lines read "Low: The Hall of Thanes", matched
-- by name either way round, as the sheet's clears are (BountyClaims).
function EKO:BoardHas(dungeonName)
    local b = self:Bounties()
    if not b or type(b.text) ~= "string" then return false end
    local key = tostring(dungeonName or ""):lower():gsub("^the ", "")
    if key == "" then return false end
    for line in b.text:gmatch("[^\n]+") do
        local name = line:gsub("^%s*%a+:%s*", ""):lower():gsub("^%s*the ", ""):gsub("%s+$", "")
        if name ~= "" and (name == key or name:find(key, 1, true) or key:find(name, 1, true)) then return true end
    end
    return false
end

local function sendBounty(b)
    if GuildOS.SyncService and b then
        GuildOS.SyncService:Publish("ekobounty", "set", { text = b.text, rev = b.rev, by = b.by, week = b.week }, { priority = "BULK" })
    end
end

function EKO:SaveBounties(text)
    if not GuildOS:IsOfficer() then GuildOS:Print("Only officers can set the Bounty Board.") return end
    local db = self:DB()
    db.bounty = { text = text, rev = now(), by = (GuildOS.Compat and GuildOS.Compat.PlayerName()) or UnitName("player"), week = self:WeekStart() }
    sendBounty(db.bounty)
    if self.journalRefresh then GuildOS:SafeCall(self.journalRefresh) end
    GuildOS:Print("EKO: this week's Bounty Board is set and sent to everyone with OutlawOS.")
end

if GuildOS.SyncService then
    GuildOS.SyncService.GUILD_ONLY_DOMAINS.ekobounty = true
    GuildOS.SyncService:On("ekobounty", function(env, sender)
        local d = env and env.data
        if type(d) ~= "table" or type(d.rev) ~= "number" or type(d.text) ~= "string" then return end
        if not GuildOS:IsOfficerByName(sender) then return end
        local db = EKO:DB()
        if not db then return end
        if db.bounty and (db.bounty.rev or 0) >= d.rev then return end
        db.bounty = { text = d.text, rev = d.rev, by = d.by or sender, week = d.week }
        if EKO.journalRefresh then GuildOS:SafeCall(EKO.journalRefresh) end
    end)
end

local bountyEv = CreateFrame("Frame")
bountyEv:RegisterEvent("PLAYER_LOGIN")
bountyEv:SetScript("OnEvent", function()
    C_Timer.After(30, function()
        GuildOS:SafeCall(function()
            local b = EKO:Bounties()
            if b and GuildOS:IsOfficer() then sendBounty(b) end
        end)
    end)
end)

-- A small text editor popup: title, hint, text, onSave(text).
function EKO:TextPopup(title, hint, text, onSave)
    local UI, C = GuildOS.UI, GuildOS.Colors
    local f = self.textPopup
    if not f then
        f = CreateFrame("Frame", "GuildOSEKOTextPopup", UIParent, "BackdropTemplate")
        f:SetSize(520, 300)
        f:SetPoint("CENTER")
        f:SetFrameStrata("DIALOG")
        f:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
        f:SetBackdropColor(GuildOS.Colors.bg.r, GuildOS.Colors.bg.g, GuildOS.Colors.bg.b, 0.98)
        f:SetBackdropBorderColor(C.border.r, C.border.g, C.border.b, C.border.a or 1)
        f:SetMovable(true); f:EnableMouse(true); f:RegisterForDrag("LeftButton")
        f:SetScript("OnDragStart", f.StartMoving)
        f:SetScript("OnDragStop", f.StopMovingOrSizing)
        f:SetClampedToScreen(true)
        table.insert(UISpecialFrames, "GuildOSEKOTextPopup")
        f.title = UI:CreateTitle(f, "", 14)
        f.title:SetPoint("TOPLEFT", 14, -12)
        f.hint = UI:CreateText(f, "", 10, C.textSoft.r, C.textSoft.g, C.textSoft.b)
        f.hint:SetPoint("TOPLEFT", 14, -34)
        f.hint:SetPoint("TOPRIGHT", -14, -34)
        f.hint:SetJustifyH("LEFT")
        local well = CreateFrame("Frame", nil, f, "BackdropTemplate")
        well:SetPoint("TOPLEFT", 12, -64)
        well:SetPoint("BOTTOMRIGHT", -12, 48)
        well:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
        well:SetBackdropColor(C.well.r, C.well.g, C.well.b, 1)
        well:SetBackdropBorderColor(C.lineHi.r, C.lineHi.g, C.lineHi.b, 1)
        local edit = CreateFrame("EditBox", nil, well)
        edit:SetPoint("TOPLEFT", 6, -6)
        edit:SetPoint("BOTTOMRIGHT", -6, 6)
        edit:SetMultiLine(true)
        edit:SetAutoFocus(false)
        GuildOS:ApplyFont(edit, 12)
        edit:SetTextColor(C.text.r, C.text.g, C.text.b)
        edit:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
        well:EnableMouse(true)
        well:SetScript("OnMouseDown", function() edit:SetFocus() end)
        f.edit = edit
        local cancel = UI:CreateButton(f, "Cancel", 80, 24)
        cancel:SetPoint("BOTTOMRIGHT", -12, 12)
        cancel:SetScript("OnClick", function() f:Hide() end)
        local save = UI:CreateButton(f, "Save", 80, 24)
        save:SetPoint("RIGHT", cancel, "LEFT", -8, 0)
        if UI.SetButtonVariant then UI:SetButtonVariant(save, "primary") end
        save:SetScript("OnClick", function()
            if f.onSave then f.onSave(f.edit:GetText()) end
            f:Hide()
        end)
        self.textPopup = f
    end
    f.title:SetText(title or "")
    f.hint:SetText(hint or "")
    f.onSave = onSave
    f.edit:SetText(text or "")
    f:Show(); f:Raise()
end

----------------------------------------------------------------------
-- Drawing: one block per call, into a frame of its own across the Journal's content.
----------------------------------------------------------------------
local jBlocks = {}
local function block(content, key, y)
    local b = jBlocks[key]
    if not b or b:GetParent() ~= content then
        b = CreateFrame("Frame", nil, content)
        jBlocks[key] = b
    end
    clear(b)
    b:ClearAllPoints()
    b:SetPoint("TOPLEFT", 0, -y)
    b:SetPoint("TOPRIGHT", 0, -y)
    b:Show()
    return b
end

local function txt(parent, s, x, y, w, size, col)
    local UI, C = GuildOS.UI, GuildOS.Colors
    col = col or C.text
    local fs = UI:CreateText(parent, s or "", size or 12, col.r, col.g, col.b)
    fs:SetPoint("TOPLEFT", x, -y)
    if w then fs:SetWidth(w) end
    fs:SetJustifyH("LEFT")
    fs:SetWordWrap(w and true or false)
    return fs
end

local function nameColored(s, m, classes)
    local cls = (m and m.class) or (classes and classes[s])
    local hex = cls and GuildOS.GetClassColorHex and GuildOS:GetClassColorHex(cls)
    if type(hex) ~= "string" or #hex ~= 6 then hex = "ffffff" end
    return "|cff" .. hex .. s .. "|r"
end

local function classMap()
    local out = {}
    for name, m in pairs(EKO:Roster()) do out[name] = m.class end
    return out
end

-- Returns the y under the block. `first` is false for every block (THIS WEEK comes first).
function EKO:JournalBlock(key, content, y, width)
    local UI, C = GuildOS.UI, GuildOS.Colors
    y = y + 20
    local b = block(content, key, y)
    local title = UI:CreateSectionTitle(b, "", false)
    title:SetPoint("TOPLEFT", 0, 0)
    local by = 24
    local classes = classMap()

    if key == "bounty" then
        local bt = self:Bounties()
        local list = bt and self:ParseBounties(bt.text) or {}
        title:SetText("BOUNTY BOARD  ·  this week")
        if GuildOS:IsOfficer() then
            local set = UI:CreateButton(b, "Set bounties", 100, 20)
            set:SetPoint("TOPRIGHT", 0, 2)
            set:SetScript("OnClick", function()
                EKO:TextPopup("This week's Bounty Board", "One dungeon per line. Start with Low:, Mid: or High: for its tier, e.g.  Low: The Hall of Thanes",
                    bt and bt.text or "Low: \nLow: \nMid: \nMid: \nHigh: \nHigh: ", function(t) EKO:SaveBounties(t) end)
            end)
            local sc = UI:CreateButton(b, "Set verified clears", 130, 20)
            sc:SetPoint("TOPRIGHT", -106, 2)
            sc:SetScript("OnClick", function()
                local cs = shared("bountyclears")
                local cur = (type(cs) == "table" and cs.week == EKO:WeekStart()) and (cs.text or "") or ""
                EKO:TextPopup("Verified clears",
                    "Paste this week's rows from the Bounty Board sheet's Clears tab, columns A to J, all at once. Only the newest week in the paste counts. Each Clear # with three or more Outlaws marks its dungeon's poster. Clear the box to remove them.",
                    cur, function(t)
                        EKO:SetShared("bountyclears", { text = t, week = (t ~= "" and EKO:WeekStart()) or nil })
                    end)
            end)
        end
        if #list == 0 then
            txt(b, GuildOS:IsOfficer() and "No bounties set for this week. Use Set bounties." or "This week's bounties aren't set yet.", 0, by, width, 12, C.textSoft)
            by = by + 20
        else
            for i, bnt in ipairs(list) do
                local row = newRow(b, by, i, 26)
                local done = self:BountyClaims(bnt.name)
                cell(row, bnt.tier and ("|cffe6b84a" .. bnt.tier .. "|r") or "", 8, 50)
                cell(row, bnt.name, 60, 220)
                if #done > 0 then
                    local names = {}
                    for _, s in ipairs(done[#done].who) do names[#names + 1] = nameColored(s, nil, classes) end
                    cell(row, string.format("|cff66dd66cleared %dx|r", #done), 290, 90)
                    cell(row, table.concat(names, ", ") .. (#done > 1 and string.format("  (+%d more group%s)", #done - 1, #done > 2 and "s" or "") or ""), 385, math.max(100, width - 390))
                else
                    cell(row, "|cff888888not cleared yet|r", 290, 120)
                end
                by = by + 28
            end
            txt(b, "Verified clears from the Bounty Board tracker (screenshots in #bb-submissions). Names shown are the latest group; credit goes to mains.", 0, by + 2, width, 10, C.textSoft)
            by = by + 30
        end

    elseif key == "leaders" then
        local levelers, runners = self:Leaderboards()
        title:SetText("TOP OUTLAWS  ·  this week")
        local colW = math.floor((width - 24) / 2)
        local function board(x, head, list, unit)
            txt(b, head, x, by, colW, 11, C.label)
            local yy = by + 18
            if #list == 0 then txt(b, "Nobody yet this week.", x, yy, colW, 12, C.textSoft); return yy + 18 end
            for i = 1, math.min(BOARD_N, #list) do
                local e = list[i]
                txt(b, string.format("%d.  %s", i, nameColored(e.name, e.m, classes)), x, yy, colW - 80, 12)
                local n = txt(b, string.format(unit, e.n), x + colW - 80, yy, 80, 12, C.textSoft)
                n:SetJustifyH("RIGHT")
                yy = yy + 18
            end
            return yy
        end
        local y1 = board(0, "MOST LEVELS GAINED", levelers, "+%d")
        local y2 = board(colW + 24, "MOST DUNGEON RUNS", runners, "%d runs")
        by = math.max(y1, y2) + 6
        local function shout(list, label, unit)
            local parts = {}
            for i = 1, math.min(BOARD_N, #list) do parts[#parts + 1] = list[i].name .. " " .. string.format(unit, list[i].n) end
            local s = label .. table.concat(parts, ", ") .. "! Great work Outlaws!"
            if #s > 250 then s = s:sub(1, 247) .. "..." end
            ChatFrame_OpenChat("/g " .. s)
        end
        local b1 = UI:CreateButton(b, "Shout out levelers", 140, 20)
        b1:SetPoint("TOPLEFT", 0, -by)
        b1:SetScript("OnClick", function() shout(levelers, "Top levelers this week: ", "+%d") end)
        local b2 = UI:CreateButton(b, "Shout out dungeon runners", 180, 20)
        b2:SetPoint("TOPLEFT", colW + 24, -by)
        b2:SetScript("OnClick", function() shout(runners, "Top dungeon runners this week: ", "(%d)") end)
        by = by + 26
        txt(b, "Week runs Monday to Sunday. Levels are counted from each member's level when OutlawOS first saw them this week; runs are dungeon clears OutlawOS logged.", 0, by, width, 10, C.textSoft)
        by = by + 30

    elseif key == "levelfirsts" then
        local firstAt, classMax = self:LevelFirsts()
        title:SetText("LEVEL FIRSTS")
        local x = 0
        for _, lvl in ipairs(self.LEVEL_FIRSTS) do
            local f = firstAt[lvl]
            txt(b, "FIRST TO " .. lvl, x, by, 150, 10, C.label)
            txt(b, f and nameColored(f.name, nil, classes) or "|cff888888no one yet|r", x, by + 14, 150, 12)
            if f then txt(b, date("%Y-%m-%d", f.at), x, by + 30, 150, 10, C.textSoft) end
            x = x + 160
            if x + 150 > width then x = 0; by = by + 52 end
        end
        if x > 0 then by = by + 52 end
        txt(b, "FIRST OF EACH CLASS TO " .. (GuildOS.Client and GuildOS.Client.maxLevel or 60), 0, by + 4, width, 10, C.label)
        by = by + 22
        local parts = {}
        for _, cls in ipairs(self.CLASSES) do
            local f = classMax[cls]
            local label = (LOCALIZED_CLASS_NAMES_MALE and LOCALIZED_CLASS_NAMES_MALE[cls]) or cls
            local hex = GuildOS.GetClassColorHex and GuildOS:GetClassColorHex(cls) or "ffffff"
            parts[#parts + 1] = "|cff" .. hex .. label .. "|r: " .. (f and f.name or "|cff888888open|r")
        end
        txt(b, table.concat(parts, "   ·   "), 0, by, width, 12)
        by = by + 40

    elseif key == "recent" then
        local runs = self:Runs(now() - 7 * DAY)
        title:SetText(string.format("RECENT GUILD CLEARS  (%d this week)", #self:Runs(self:WeekStart())))
        if #runs == 0 then
            txt(b, "No dungeon clears logged in the last 7 days.", 0, by, width, 12, C.textSoft)
            by = by + 20
        end
        for i = 1, math.min(RECENT_RUNS, #runs) do
            local r = runs[i]
            local row = newRow(b, by, i, 26)
            cell(row, date("%m/%d %I:%M %p", r.at), 8, 110, C.textSoft.r, C.textSoft.g, C.textSoft.b)
            cell(row, string.format("%s  ·  %d bosses", r.name, r.bosses), 125, 240)
            local names = {}
            for _, s in ipairs(r.who) do names[#names + 1] = nameColored(s, nil, classes) end
            cell(row, table.concat(names, ", "), 375, math.max(100, width - 380))
            by = by + 28
        end
        if #runs > RECENT_RUNS then txt(b, string.format("... and %d more this week.", #runs - RECENT_RUNS), 0, by, width, 11, C.textSoft); by = by + 18 end
    end

    b:SetHeight(by)
    return y + by
end

----------------------------------------------------------------------
-- OUTLAW EXTRAS (Nov 21): Wanted posters, Bounty Hunter of the Month, Raffle, Location of the Week,
-- Notoriety, Ledger seals, rank lore, anniversaries, the Ledger signing, farewell lines, strikes,
-- Quote the Code, the Outlaw Gazette, the recruit ad rotator, Ride Out, Safehouses, the Tavern and
-- Campfire nights. Shared state goes out on one sync domain, "ekomisc", accepted only from officers.
----------------------------------------------------------------------
local GOLDC = "|cffe6b84a"
local GREY = "|cff888888"
local GREEN = "|cff66dd66"

-- Rank lore (roster tooltips).
EKO.RANK_LORE = {
    ["Guild Master"] = "The Matriarch. Keeper of the Ledger and the Gilded Feather.",
    ["GM Alt"] = "The Matriarch in disguise.",
    ["Co-Guild Master"] = "Holds the Ledger when the Matriarch rides out.",
    ["Officer"] = "Inner Circle. Keeps the gang together and the Code kept.",
    ["Raid Marshal"] = "Leads the big jobs: raids and the Raid of the Month.",
    ["Herald"] = "Spreads the word. Recruiters and event organizers.",
    ["Veteran Outlaw"] = "Rode with the gang through thick and thin.",
    ["Outlaw"] = "Signed the Ledger and earned their colors.",
    ["Alter Ego"] = "Another face of a known Outlaw.",
    ["Recruit"] = "New to the road. Earning their colors.",
}

EKO.CODE_RULES = {
    { key = "respect", text = "Outlaw Code: respect everyone. No harassment, keep it friendly." },
    { key = "pg13", text = "Outlaw Code: keep guild chat PG-13 please." },
    { key = "drama", text = "Outlaw Code: no drama or politics in guild chat. Take it to whispers or let it go." },
    { key = "ninja", text = "Outlaw Code: no ninja looting. Roll need only on gear you'll use." },
    { key = "strikes", text = "Heads up: we use 3 strikes. A verbal warning, then a written warning, then removal." },
    { key = "slurs", text = "Outlaw Code: slurs and harassment mean removal on the spot. No exceptions." },
}

EKO.RECRUIT_ADS = {
    "<Eastern Kingdoms Outlaws> is recruiting! Casual 21+ guild with weekly Bounty Board dungeons, a Sunday gold raffle, Location of the Week hunts and raids starting Dec 9. Whisper me for an invite!",
    "Looking for a crew? The Outlaws ride every week: Bounty Board dungeons, Sunday raffle, Location of the Week and raids soon. 530+ members, active Discord. Whisper for an invite!",
    "Sign the Ledger with <Eastern Kingdoms Outlaws>! Weekly bounties pay out in raffle entries, LotW finders win gold, raids launch Dec 9. All levels and alts welcome. Whisper me!",
    "<Eastern Kingdoms Outlaws>: free by choice, bound by bond. Casual leveling crew with weekly events, raffles, dungeon bounties and a chill Discord voice chat. Whisper for an invite!",
    "Tired of quiet guilds? EKO runs Bounty Board dungeons, a Sunday raffle, Location of the Week and Raid of the Month. Over 500 Outlaws and growing. Whisper me to join!",
}

EKO.FAREWELLS = {
    "%s rode off into the sunset",
    "%s took the back road out of Goldshire",
    "%s left the Ledger behind",
    "%s slipped out the tavern's back door",
    "%s rode off without a word",
}

EKO.CAMPFIRES = {
    { name = "Goldshire Hangout", game = "Campfire night! Come hang out at the Lion's Pride Inn in Goldshire, and hop in the Goldshire voice channel. No agenda, just Outlaws being Outlaws.",
      discord = ":ekoswords: **Campfire Night: Goldshire Hangout** :ekoswords:\nCome hang out at the Lion's Pride Inn in Goldshire and hop in the Goldshire voice channel. No agenda, just Outlaws being Outlaws!" },
    { name = "Fishing Derby", game = "Fishing derby tonight! Biggest catch wins gold. Grab a pole and meet at the Goldshire pond, all levels welcome.",
      discord = ":ekoswords: **Campfire Night: Fishing Derby** :ekoswords:\nBiggest catch wins gold! Grab a pole and meet at the Goldshire pond. All levels welcome." },
    { name = "Duel Night", game = "Duel night outside Goldshire! Friendly duels, bragging rights on the line. Come watch or fight, all levels welcome.",
      discord = ":ekoswords: **Campfire Night: Duel Night** :ekoswords:\nFriendly duels outside Goldshire, bragging rights on the line. Come watch or fight!" },
    { name = "Transmog Contest", game = "Transmog contest tonight! Show off your best Outlaw look in Goldshire. Winner gets gold and eternal glory.",
      discord = ":ekoswords: **Campfire Night: Transmog Contest** :ekoswords:\nShow off your best Outlaw look in Goldshire. Winner gets gold and eternal glory!" },
    { name = "Bounty Rush", game = "Bounty rush tonight! Let's clear as many Bounty Board dungeons as we can. Every clear is a raffle entry. Ask in guild for a group!",
      discord = ":ekoswords: **Campfire Night: Bounty Rush** :ekoswords:\nLet's clear as many Bounty Board dungeons as we can tonight. Every clear is a raffle entry! Ask in guild chat for a group." },
}

EKO.SAFEHOUSE_DEFAULTS = {
    { name = "The Gilded Feather (Lion's Pride Inn, Goldshire)", map = 1429, x = 43.8, y = 65.8 },
}

local function meName() return (GuildOS.Compat and GuildOS.Compat.PlayerName()) or UnitName("player") end

local function monthKey(t) return date("%Y-%m", t or now()) end

-- Shared state: officers write, everyone with OutlawOS reads. db.eko.shared[kind] = { rev, by, data }.
local function shared(kind)
    local db = EKO:DB()
    if not db then return nil end
    db.shared = db.shared or {}
    local s = db.shared[kind]
    return s and s.data
end

local refreshers = {}
local function refreshAll()
    for _, fn in pairs(refreshers) do GuildOS:SafeCall(fn) end
end

function EKO:SetShared(kind, data)
    if not GuildOS:IsOfficer() then GuildOS:Print("Only officers can change that.") return false end
    local db = self:DB()
    db.shared = db.shared or {}
    local rec = { rev = now(), by = meName(), data = data }
    db.shared[kind] = rec
    if GuildOS.SyncService then
        GuildOS.SyncService:Publish("ekomisc", "set", { kind = kind, rev = rec.rev, by = rec.by, data = data }, { priority = "BULK" })
    end
    refreshAll()
    return true
end

-- Strikes stay with officers: other members' clients drop them.
local OFFICER_ONLY = { strikes = true }

if GuildOS.SyncService then
    GuildOS.SyncService.GUILD_ONLY_DOMAINS.ekomisc = true
    GuildOS.SyncService:On("ekomisc", function(env, sender)
        local d = env and env.data
        if type(d) ~= "table" or type(d.kind) ~= "string" or type(d.rev) ~= "number" then return end
        if not GuildOS:IsOfficerByName(sender) then return end
        if OFFICER_ONLY[d.kind] and not GuildOS:IsOfficer() then return end
        local db = EKO:DB()
        if not db then return end
        db.shared = db.shared or {}
        local cur = db.shared[d.kind]
        if cur and (cur.rev or 0) >= d.rev then return end
        db.shared[d.kind] = { rev = d.rev, by = d.by or sender, data = d.data }
        refreshAll()
    end)
end

-- An officer's client sends what it holds again 35 seconds after login, so anyone offline catches up.
local miscEv = CreateFrame("Frame")
miscEv:RegisterEvent("PLAYER_LOGIN")
miscEv:SetScript("OnEvent", function()
    C_Timer.After(35, function()
        GuildOS:SafeCall(function()
            if not GuildOS:IsOfficer() or not GuildOS.SyncService then return end
            local db = EKO:DB()
            for kind, rec in pairs(db and db.shared or {}) do
                GuildOS.SyncService:Publish("ekomisc", "set", { kind = kind, rev = rec.rev, by = rec.by, data = rec.data }, { priority = "BULK" })
            end
        end)
    end)
end)

----------------------------------------------------------------------
-- Bounty Hunter of the Month
----------------------------------------------------------------------
function EKO:Hunter()
    local h = shared("hunter")
    if type(h) ~= "table" then return nil end
    return h
end

function EKO:IsHunterNow(name)
    local h = self:Hunter()
    return h and h.name == name and h.month == monthKey() or false
end

function EKO:WasHunter(name)
    local h = self:Hunter()
    if not h then return 0 end
    local n = 0
    for _, rec in ipairs(h.history or {}) do if rec.name == name then n = n + 1 end end
    return n
end

function EKO:SetHunter(name)
    name = strtrim(name or "")
    if name == "" then return end
    local h = self:Hunter() or {}
    local history = {}
    for _, rec in ipairs(h.history or {}) do if rec.month ~= monthKey() then history[#history + 1] = rec end end
    history[#history + 1] = { name = name, month = monthKey() }
    if self:SetShared("hunter", { name = name, month = monthKey(), history = history }) then
        GuildOS:Print("EKO: " .. name .. " is Bounty Hunter of the Month.")
    end
end

----------------------------------------------------------------------
-- Location of the Week
----------------------------------------------------------------------
-- "Easy: hint" / "Easy finders: A, B" lines.
function EKO:ParseLotw(text)
    local spots = {}
    for raw in (tostring(text or ""):gsub("|", "") .. "\n"):gmatch("([^\n]*)\n") do
        local line = raw:gsub("\r", ""):match("^%s*(.-)%s*$")
        local theme = line:match("^[Tt]heme%s*:%s*(.+)$")
        local ptier, prizes = line:match("^(%a+)%s+[Pp]rizes?%s*:%s*(.*)$")
        local tier, rest = line:match("^(%a+)%s+[Ff]inders?%s*:%s*(.*)$")
        if theme then
            spots.theme = theme
        elseif ptier and ({ easy = 1, medium = 1, hard = 1 })[ptier:lower()] then
            local t = ptier:lower()
            spots[t] = spots[t] or { hint = "", finders = {} }
            spots[t].prizes = prizes
        elseif tier then
            local t = tier:lower()
            spots[t] = spots[t] or { hint = "", finders = {} }
            for part in rest:gmatch("[^,]+") do
                local n = part:match("^%s*(.-)%s*$")
                if n ~= "" then table.insert(spots[t].finders, n) end
            end
        else
            tier, rest = line:match("^(%a+)%s*:%s*(.*)$")
            if tier and ({ easy = 1, medium = 1, hard = 1 })[tier:lower()] then
                local t = tier:lower()
                spots[t] = spots[t] or { hint = "", finders = {} }
                spots[t].hint = rest
            end
        end
    end
    return spots
end

-- Location of the Week runs Friday 8 PM to Friday 8 PM.
function EKO:LotwWeekStart(t)
    t = t or now()
    local d = date("*t", t)
    local back = ((d.wday or 6) - 6) % 7   -- days since Friday
    local s = t - back * DAY - (d.hour or 0) * 3600 - (d.min or 0) * 60 - (d.sec or 0) + 20 * 3600
    if s > t then s = s - 7 * DAY end
    return s
end

-- The Nov 20 post (theme: Statues), used until an officer posts a newer week in the Outlaw Desk.
EKO.LOTW_SEED = { week = 1795222800, text = table.concat({
    "Theme: Statues",
    "Easy: In the woods where it never stops raining, someone's been waiting with open arms. Find them between the two torches.",
    "Easy prizes: 40s, 30s, 20s",
    "Easy finders: ",
    "Medium: In a forest of night where the elves keep their guard, two faces were frozen in screams, carved hard. They don't make a sound, but they watch where you tread. Find the pair that cried out, then lost their heads.",
    "Medium prizes: 60s, 40s, 30s",
    "Medium finders: ",
    "Hard: She left her homeland for a war that wasn't hers, vanished beyond a dark gate, and now greets every traveler with a bird on her arm. Find where the ranger stands guard.",
    "Hard prizes: 1g, 70s, 50s",
    "Hard finders: Oin Stormweaver, Object Oriented, Bodybagz Gravy",
}, "\n") }

-- Every past winner from the LotW tracker (Nov 13 and Nov 20), so seals and Notoriety count them.
EKO.LOTW_TALLY_SEED = {
    ["Oin Stormweaver"] = 1, ["Object Oriented"] = 1, ["Bodybagz Gravy"] = 1,
    ["Freya Jordahl"] = 1, ["Brannoc Grimvolt"] = 1, ["Nordra Valorheart"] = 1,
    ["Pairs II"] = 1, ["Fallen Toius"] = 1, ["Nameloading Nameloading"] = 1, ["Ryzen Moros"] = 1,
}

function EKO:Lotw()
    local l = shared("lotw")
    local ws = self:LotwWeekStart()
    if type(l) == "table" and l.week == ws then return l end
    if self.LOTW_SEED.week == ws then return self.LOTW_SEED end
    return nil
end

function EKO:LotwFinds(name)
    -- Every week's finders: the shared record's tally, else the tracker's winners so far.
    local l = shared("lotw")
    local tally = (type(l) == "table" and l.tally) or self.LOTW_TALLY_SEED
    return tally[name] or 0
end

-- Add a winner to one tier ("easy" / "medium" / "hard") of this week's spots, and sync it.
function EKO:LotwAddFinder(tier, name)
    name = strtrim((name or ""):gsub("[,|]", ""))
    if name == "" then return end
    local l = self:Lotw()
    local text = l and l.text or ""
    local label = tier:sub(1, 1):upper() .. tier:sub(2)
    local lines, done = {}, false
    for raw in (text .. "\n"):gmatch("([^\n]*)\n") do
        local line = raw
        local t, rest = raw:match("^%s*(%a+)%s+[Ff]inders?%s*:%s*(.*)$")
        if t and t:lower() == tier and not done then
            rest = rest:match("^%s*(.-)%s*$")
            line = label .. " finders: " .. (rest ~= "" and (rest .. ", ") or "") .. name
            done = true
        end
        lines[#lines + 1] = line
    end
    while #lines > 0 and lines[#lines] == "" do lines[#lines] = nil end
    if not done then lines[#lines + 1] = label .. " finders: " .. name end
    self:SaveLotw(table.concat(lines, "\n"))
    GuildOS:Print(string.format("EKO: %s added to the %s Location of the Week winners.", name, label))
end

function EKO:EditLotw()
    local l = self:Lotw()
    self:TextPopup("Location of the Week", "Theme: ...  |  Easy: <riddle>  |  Easy prizes: 40s, 30s, 20s  |  Easy finders: Name, Name  (same for Medium and Hard). Saving sends it to everyone with OutlawOS.",
        l and l.text or "Theme: \nEasy: \nEasy prizes: \nEasy finders: \nMedium: \nMedium prizes: \nMedium finders: \nHard: \nHard prizes: \nHard finders: ",
        function(t) EKO:SaveLotw(t) end)
end

function EKO:SaveLotw(text)
    local old = shared("lotw")
    local ws = self:LotwWeekStart()
    local tally = {}
    for k, v in pairs(type(old) == "table" and old.tally or self.LOTW_TALLY_SEED) do tally[k] = v end
    -- Take back this week's finders before counting the new list, so a re-save doesn't double-count.
    local prev = (type(old) == "table" and old.week == ws) and old or (self.LOTW_SEED.week == ws and self.LOTW_SEED) or nil
    if prev then
        for t, s in pairs(self:ParseLotw(prev.text)) do
            if t ~= "theme" then for _, n in ipairs(s.finders) do tally[n] = math.max(0, (tally[n] or 1) - 1) end end
        end
    end
    for t, s in pairs(self:ParseLotw(text)) do
        if t ~= "theme" then for _, n in ipairs(s.finders) do tally[n] = (tally[n] or 0) + 1 end end
    end
    self:SetShared("lotw", { week = ws, text = text, tally = tally })
end

----------------------------------------------------------------------
-- Notoriety and Ledger seals (from GuildOS's journal, the roster and the shared records)
----------------------------------------------------------------------
local statsCache, statsAt = nil, 0
function EKO:MemberStats()
    local t = GetTime and GetTime() or 0
    if statsCache and t - statsAt < 60 then return statsCache end
    local out = {}
    local function S(n) out[n] = out[n] or { clears = 0, dungeons = {}, nDungeons = 0, firsts = 0 }; return out[n] end
    for _, r in ipairs(self:Runs(0)) do
        for _, n in ipairs(r.who) do
            local s = S(n)
            s.clears = s.clears + 1
            if not s.dungeons[r.name] then s.dungeons[r.name] = true; s.nDungeons = s.nDungeons + 1 end
        end
    end
    local f = GuildOS.db and GuildOS.db.journal and GuildOS.db.journal.firsts
    for _, first in pairs(type(f) == "table" and f or {}) do
        for _, key in ipairs(type(first) == "table" and first.who or {}) do
            local n = short(key)
            if n then S(n).firsts = S(n).firsts + 1 end
        end
    end
    statsCache, statsAt = out, t
    return out
end

function EKO:Notoriety(name, level)
    local s = self:MemberStats()[name] or { clears = 0, nDungeons = 0, firsts = 0 }
    local score = s.clears * 3 + s.nDungeons * 2 + math.floor((level or 0) / 2)
        + self:LotwFinds(name) * 5 + s.firsts * 10 + self:WasHunter(name) * 15
    return score, s
end

function EKO:WantedLevel(score)
    if score >= 120 then return "Most Wanted" end
    if score >= 70 then return "Notorious" end
    if score >= 35 then return "Wanted" end
    if score >= 12 then return "Known Outlaw" end
    return "Fresh Face"
end

function EKO:Seals(name, level)
    local _, s = self:Notoriety(name, level)
    local out = {}
    local joined = self:JoinedAt(name)
    if s.clears >= 1 then out[#out + 1] = "First Blood" end
    if s.clears >= 10 then out[#out + 1] = "Dungeon Delver" end
    if s.nDungeons >= 5 then out[#out + 1] = "Wanderer" end
    if s.firsts >= 1 then out[#out + 1] = "Trailblazer" end
    if self:LotwFinds(name) >= 1 then out[#out + 1] = "Pathfinder" end
    if self:WasHunter(name) >= 1 then out[#out + 1] = "Bounty Hunter" end
    for _, l in ipairs({ 20, 40, 60 }) do if (level or 0) >= l then out[#out + 1] = "Level " .. l end end
    if joined and now() - joined >= 90 * DAY then out[#out + 1] = "Veteran of the Ledger" end
    return out
end

-- Lines for the roster tooltip (UI/RosterFrame.lua calls this under the alts).
function EKO:TooltipLines(data)
    local lines = {}
    local name = data and data.name and short(data.name)
    if not name then return lines end
    if self:IsHunterNow(name) then lines[#lines + 1] = { GOLDC .. "Bounty Hunter of the Month|r" } end
    local lore = data.rank and self.RANK_LORE[data.rank]
    if lore then lines[#lines + 1] = { GREY .. lore .. "|r", wrap = true } end
    local score = self:Notoriety(name, data.level)
    lines[#lines + 1] = { string.format("Notoriety: %s%d|r  (%s)", GOLDC, score, self:WantedLevel(score)) }
    lines[#lines + 1] = { GREY .. "Clears, dungeons, firsts, bounties and level add up to it." .. "|r", wrap = true }
    local joined = self:JoinedAt(name)
    if joined then
        local days = math.floor((now() - joined) / DAY)
        lines[#lines + 1] = { string.format("On the Ledger since %s (%d day%s)", date("%b %d", joined), days, days == 1 and "" or "s") }
    end
    local seals = self:Seals(name, data.level)
    if #seals > 0 then lines[#lines + 1] = { "Seals (badges): " .. GOLDC .. table.concat(seals, ", ") .. "|r", wrap = true } end
    return lines
end

----------------------------------------------------------------------
-- Anniversaries
----------------------------------------------------------------------
EKO.ANNIVERSARIES = { 7, 14, 21, 28, 30, 90, 180, 365 }

-- Members who reached a milestone in the last 7 days: { name, days, at }.
function EKO:Anniversaries()
    local out = {}
    local t = now()
    for name in pairs(self:Roster()) do
        local joined = self:JoinedAt(name)
        if joined then
            for _, d in ipairs(self.ANNIVERSARIES) do
                local at = joined + d * DAY
                if at <= t and t - at < 7 * DAY then out[#out + 1] = { name = name, days = d, at = at } end
            end
        end
    end
    table.sort(out, function(a, b) return a.at > b.at end)
    return out
end

-- Members who reach a milestone in the next `within` days (default 14), soonest first.
function EKO:UpcomingAnniversaries(within)
    local out = {}
    local t = now()
    local span = (within or 14) * DAY
    for name in pairs(self:Roster()) do
        local joined = self:JoinedAt(name)
        if joined then
            for _, d in ipairs(self.ANNIVERSARIES) do
                local at = joined + d * DAY
                if at > t and at - t <= span then out[#out + 1] = { name = name, days = d, at = at } end
            end
        end
    end
    table.sort(out, function(a, b)
        if a.at ~= b.at then return a.at < b.at end
        return a.name < b.name
    end)
    return out
end

local function annText(d)
    if d == 7 then return "1 week" end
    if d == 14 then return "2 weeks" end
    if d == 21 then return "3 weeks" end
    if d == 28 then return "4 weeks" end
    if d == 30 then return "1 month" end
    if d == 90 then return "3 months" end
    if d == 180 then return "6 months" end
    if d == 365 then return "1 year" end
    return d .. " days"
end

----------------------------------------------------------------------
-- Farewell lines and lore wording (UI/Agora.lua asks for these)
----------------------------------------------------------------------
function EKO:FarewellFormat(name)
    local h = 0
    for i = 1, #(name or "") do h = (h * 31 + name:byte(i)) % 100003 end
    return self.FAREWELLS[(h % #self.FAREWELLS) + 1]
end

EKO.ROSTER_LORE = {
    join = "%s signed the Ledger",
    kick = "%s was exiled from the guild",
    promote = "%s earned their colors: %s",
    demote = "%s was knocked down to %s",
}

----------------------------------------------------------------------
-- Signing the Ledger: a welcome for a new Recruit, once per character
----------------------------------------------------------------------
GuildOS.Dialogs["EKO_LEDGER"] = {
    text = "%s",
    button1 = "I sign the Ledger",
    OnAccept = function()
        local db = EKO:DB()
        if db then db.signed = db.signed or {}; db.signed[meName()] = now() end
        GuildOS:Print(GOLDC .. "Welcome to the Outlaws. Free by choice, bound by bond.|r Discord: discord.gg/AdD9kFnQWu")
    end,
    timeout = 0, whileDead = true, hideOnEscape = false,
}

local ledgerEv = CreateFrame("Frame")
ledgerEv:RegisterEvent("PLAYER_LOGIN")
ledgerEv:SetScript("OnEvent", function()
    C_Timer.After(15, function()
        GuildOS:SafeCall(function()
            if not (IsInGuild and IsInGuild()) then return end
            local gname, rank = GetGuildInfo("player")
            if gname ~= "Eastern Kingdoms Outlaws" or rank ~= "Recruit" then return end
            local db = EKO:DB()
            if not db or (db.signed and db.signed[meName()]) then return end
            GuildOS:ShowDialog("EKO_LEDGER", "Welcome to the Eastern Kingdoms Outlaws!\n\nYou've found the Gilded Feather, the hidden tavern where Outlaws who chose freedom over serving crowns gather.\n\nThe Outlaw Code: respect everyone, keep chat PG-13, no drama or politics, no ninja looting. We use 3 strikes.\n\nJoin us on Discord: discord.gg/AdD9kFnQWu\nAfter 7 days and some adventures, you'll earn your Outlaw colors.\n\nFree by choice, bound by bond.")
        end)
    end)
end)

-- Login stinger: a short sound and the motto, once per login (/eko sound toggles it).
local stingEv = CreateFrame("Frame")
stingEv:RegisterEvent("PLAYER_ENTERING_WORLD")
stingEv:SetScript("OnEvent", function(_, _, isLogin)
    if not isLogin then return end
    C_Timer.After(9, function()
        local db = EKO:DB()
        if db and db.noSound then return end
        if PlaySound then pcall(PlaySound, (SOUNDKIT and SOUNDKIT.IG_QUEST_LIST_COMPLETE) or 618) end
    end)
end)

----------------------------------------------------------------------
-- Strikes (officers only)
----------------------------------------------------------------------
EKO.STRIKE_LEVELS = { "Verbal warning", "Written warning", "Removal" }

function EKO:Strikes()
    local s = shared("strikes")
    return type(s) == "table" and s or {}
end

function EKO:AddStrike(name, level, reason)
    name = strtrim(name or "")
    if name == "" then GuildOS:Print("Type the member's name first.") return end
    local all = {}
    for k, v in pairs(self:Strikes()) do all[k] = v end
    all[name] = all[name] or {}
    local list = {}
    for _, s in ipairs(all[name]) do list[#list + 1] = s end
    list[#list + 1] = { level = level, reason = reason or "", by = short(meName()), at = now() }
    all[name] = list
    self:SetShared("strikes", all)
end

function EKO:RemoveStrike(name, i)
    local all = {}
    for k, v in pairs(self:Strikes()) do all[k] = v end
    local list = {}
    for j, s in ipairs(all[name] or {}) do if j ~= i then list[#list + 1] = s end end
    all[name] = #list > 0 and list or nil
    self:SetShared("strikes", all)
end

----------------------------------------------------------------------
-- Raffle: entries pasted from the Bounty Board sheet, drawn with the game's own /roll
----------------------------------------------------------------------
function EKO:ParseRaffle(text)
    local out, total = {}, 0
    for raw in (tostring(text or ""):gsub("|", "") .. "\n"):gmatch("([^\n]*)\n") do
        local line = raw:gsub("\r", ""):match("^%s*(.-)%s*$")
        local name, n
        if raw:find("\t") then
            -- A row copied from the sheet's Leaderboard: Outlaw, Bounty Points, Raffle Entries, ...
            local f = {}
            for part in (raw .. "\t"):gmatch("([^\t]*)\t") do f[#f + 1] = part:match("^%s*(.-)%s*$") end
            name, n = f[1], (#f >= 3 and f[3]) or f[2]
            if not tonumber(n) then name, n = nil, nil end
        end
        if not name then name, n = line:match("^(.-)%s+[xX]%s*(%d+)$") end
        if not name then name, n = line:match("^(.-)%s*[%-:=]%s*(%d+)$") end
        if not name then name, n = line:match("^(.-)%s+(%d+)$") end
        if name and name ~= "" and tonumber(n) and tonumber(n) > 0 then
            name = name:match("^(.-)%s*$")
            out[#out + 1] = { name = name, n = tonumber(n) }
            total = total + tonumber(n)
        end
    end
    return out, total
end

-- The places, what each pays in gold (0.7 is 70s), and how many Outlaws must have entered before a
-- place is drawn: 1st to 3rd from the start, 4th and 5th at 20, 6th and 7th at 30, 8th to 10th at 40.
EKO.RAFFLE_PRIZES = { 5, 3, 1, 0.7, 0.7, 0.5, 0.5, 0.3, 0.3, 0.3 }
EKO.RAFFLE_MIN_ENTRANTS = { 0, 0, 0, 20, 20, 30, 30, 40, 40, 40 }
local PLACE_WORD = { "1st", "2nd", "3rd", "4th", "5th", "6th", "7th", "8th", "9th", "10th" }

-- A prize as the game shows it: 5g, or 70s for 0.7.
local function prizeText(p)
    if p >= 1 then return string.format("%dg", p) end
    return string.format("%ds", math.floor(p * 100 + 0.5))
end

function EKO:Raffle()
    local r = shared("raffle")
    if type(r) ~= "table" then r = { winners = {} } end
    -- Entries are counted from this week's clears. A list an officer pasted counts only for the week it was set.
    local text = (r.week == self:WeekStart() and r.text) or self:CountedRaffleText()
    -- A raffle saved with only the older three places (or none) takes the current places.
    local prizes = r.prizes
    if type(prizes) ~= "table" or #prizes < 4 then
        prizes = {}
        for i, v in ipairs(self.RAFFLE_PRIZES) do prizes[i] = v end
    end
    return { text = text, prizes = prizes, winners = r.winners or {}, drawnAt = r.drawnAt, week = r.week }
end

local pendingRoll
function EKO:DrawRaffle()
    local r = self:Raffle()
    local winners = r.winners or {}
    local prizes = r.prizes
    local place = #winners + 1
    if place > #prizes then GuildOS:Print("All places are drawn. Reset to start a new raffle.") return end
    local entries = self:ParseRaffle(r.text)
    local need = self.RAFFLE_MIN_ENTRANTS[place] or 0
    if #entries < need then
        GuildOS:Print(string.format("The %s place opens at %d Outlaws entered. So far there are %d.", PLACE_WORD[place], need, #entries))
        return
    end
    local pool, total = {}, 0
    local won = {}
    for _, w in ipairs(winners) do won[w.name] = true end
    for _, e in ipairs(entries) do
        if not won[e.name] then pool[#pool + 1] = e; total = total + e.n end
    end
    if total == 0 then GuildOS:Print("No raffle entries left to draw from.") return end
    pendingRoll = { total = total, pool = pool, at = GetTime and GetTime() or 0 }
    if not (GuildOS.Compat and GuildOS.Compat.RandomRoll and GuildOS.Compat.RandomRoll(1, total)) then
        pendingRoll = nil
        GuildOS:Print("Couldn't roll. Try /roll 1-" .. total .. " yourself.")
    else
        GuildOS:Print(string.format("Rolling 1-%d for the %s place...", total, PLACE_WORD[place]))
    end
end

local rollEv = CreateFrame("Frame")
rollEv:RegisterEvent("CHAT_MSG_SYSTEM")
rollEv:SetScript("OnEvent", function(_, _, msg)
    if not pendingRoll or type(msg) ~= "string" or not RANDOM_ROLL_RESULT then return end
    local a = GuildOS:MatchFormat(msg, RANDOM_ROLL_RESULT)
    if not a then return end
    local who, roll, low, high = a[1], tonumber(a[2]), tonumber(a[3]), tonumber(a[4])
    if short(who) ~= short(meName()) or low ~= 1 or high ~= pendingRoll.total then return end
    local acc, pick = 0, nil
    for _, e in ipairs(pendingRoll.pool) do
        acc = acc + e.n
        if roll <= acc then pick = e; break end
    end
    pendingRoll = nil
    if not pick then return end
    local r = EKO:Raffle()
    local winners = {}
    for _, w in ipairs(r.winners or {}) do winners[#winners + 1] = w end
    local place = #winners + 1
    local prize = (r.prizes or EKO.RAFFLE_PRIZES)[place] or 0
    winners[place] = { name = pick.name, roll = roll, prize = prize }
    EKO:SetShared("raffle", { text = r.text, prizes = r.prizes, winners = winners, drawnAt = now(), week = r.week })
    GuildOS:Print(string.format("%s%s place: %s|r (rolled %d, %d entr%s) wins %s!", GOLDC, PLACE_WORD[place] or (place .. "th"), pick.name, roll, pick.n, pick.n == 1 and "y" or "ies", prizeText(prize)))
    playSound("LEVELUPSOUND", 888)
end)

function EKO:RaffleAnnouncement()
    local r = self:Raffle()
    local parts = {}
    for i, w in ipairs(r.winners or {}) do
        parts[#parts + 1] = string.format("%s %s %s", PLACE_WORD[i] or (i .. "th"), w.name, prizeText(w.prize or 0))
    end
    if #parts == 0 then return nil end
    return "Sunday Raffle winners: " .. table.concat(parts, ", ") .. ". New bounties go up Monday!"
end

----------------------------------------------------------------------
-- Safehouses (TomTom waypoints when TomTom is loaded, else a /way line)
----------------------------------------------------------------------
function EKO:Safehouses()
    local s = shared("safehouses")
    local out = {}
    for _, d in ipairs(self.SAFEHOUSE_DEFAULTS) do out[#out + 1] = d end
    for _, d in ipairs(type(s) == "table" and s or {}) do out[#out + 1] = d end
    return out
end

function EKO:AddSafehouse(name)
    name = strtrim(name or "")
    if name == "" then GuildOS:Print("Give the safehouse a name.") return end
    local map = C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")
    local pos = map and C_Map.GetPlayerMapPosition and C_Map.GetPlayerMapPosition(map, "player")
    if not pos then GuildOS:Print("Can't read your position here (inside a dungeon?).") return end
    local x, y = pos:GetXY()
    local list = {}
    for _, d in ipairs(shared("safehouses") or {}) do list[#list + 1] = d end
    list[#list + 1] = { name = name, map = map, x = math.floor(x * 1000 + 0.5) / 10, y = math.floor(y * 1000 + 0.5) / 10 }
    self:SetShared("safehouses", list)
end

function EKO:RemoveSafehouse(name)
    local list = {}
    for _, d in ipairs(shared("safehouses") or {}) do if d.name ~= name then list[#list + 1] = d end end
    self:SetShared("safehouses", list)
end

function EKO:Waypoint(d)
    if TomTom and TomTom.AddWaypoint then
        local ok = pcall(TomTom.AddWaypoint, TomTom, d.map, d.x / 100, d.y / 100, { title = d.name, persistent = false, minimap = true, world = true })
        if ok then GuildOS:Print("Waypoint set: " .. d.name) return end
    end
    ChatFrame_OpenChat(string.format("/way #%d %.1f %.1f %s", d.map, d.x, d.y, d.name))
end

----------------------------------------------------------------------
-- The Outlaw Gazette: the week, ready for Discord
----------------------------------------------------------------------
-- The Gazette as the stored post for this week if an editor saved one, otherwise the generated post.
function EKO:Gazette()
    local ws = self:WeekStart()
    local saved = self:GazetteStored()
    if saved and saved.week == ws then return saved.text end
    return self:GazetteGenerated()
end

-- Gazette edits (GM and Co-GMs): a saved version replaces this week's generated post for everyone with OutlawOS.
function EKO:GazetteStored()
    local db = self:DB()
    local g = db and db.gazette
    if type(g) == "table" and type(g.text) == "string" and g.text ~= "" then return g end
    return nil
end

function EKO:SaveGazette(text)
    if not self:CanEditAbout() then GuildOS:Print("Only the Guild Master and Co-Guild Masters can edit the Gazette.") return end
    local db = self:DB()
    if not db then return end
    local by = (GuildOS.Compat and GuildOS.Compat.PlayerName()) or UnitName("player")
    local rec = { week = self:WeekStart(), text = (text and text:match("%S")) and text or "", rev = now(), by = by }
    if rec.text ~= "" then db.gazette = { week = rec.week, text = rec.text, rev = rec.rev, by = rec.by } else db.gazette = nil end
    if GuildOS.SyncService then
        GuildOS.SyncService:Publish("ekogazette", "set", rec, { priority = "BULK" })
    end
    GuildOS:Print(rec.text ~= "" and "EKO: Gazette saved and sent to everyone with OutlawOS." or "EKO: Gazette edit cleared. The auto post is back.")
    if self.gazetteRefresh then GuildOS:SafeCall(self.gazetteRefresh) end
end

-- Editor: starts from what everyone sees now. Clear the text and save to go back to the auto post.
function EKO:OpenGazetteEditor()
    local text = self:Gazette()
    self:TextPopup("The Outlaw Gazette", "Edit this week's Gazette. Saving sends it to everyone with OutlawOS. Clear the text and save to go back to the auto post.", text, function(t) self:SaveGazette(t) end)
end

if GuildOS.SyncService then
    GuildOS.SyncService.GUILD_ONLY_DOMAINS.ekogazette = true
    GuildOS.SyncService:On("ekogazette", function(env, sender)
        local d = env and env.data
        if type(d) ~= "table" or type(d.rev) ~= "number" then return end
        if not EKO.ABOUT_EDITORS[rankOf(sender) or ""] then return end
        local db = EKO:DB()
        if not db then return end
        if db.gazette and (db.gazette.rev or 0) >= d.rev then return end
        if type(d.text) == "string" and d.text ~= "" then
            db.gazette = { week = d.week, text = d.text, rev = d.rev, by = d.by or sender }
        else
            db.gazette = nil
        end
        if EKO.gazetteRefresh then GuildOS:SafeCall(EKO.gazetteRefresh) end
    end)
end

-- The Gazette as a styled page: gold headings, no emoji codes or ** markers. Copy for Discord gives the raw text.
local function gazetteLine(raw)
    local s = raw:gsub(":%w+:", ""):gsub("^%s+", ""):gsub("%s+$", "")
    s = s:gsub("%*%*(.-)%*%*", "|cffffd100%1|r")
    s = s:gsub("%*(.-)%*", "%1")
    return s
end
EKO.GazetteLine = gazetteLine   -- the Now tab's preview styles its lines the same way

function EKO:ShowGazettePopup(gz, title)
    local UI, C = GuildOS.UI, GuildOS.Colors
    local gold = { r = 1, g = 0.82, b = 0 }
    local f = self.gazettePopup
    if not f then
        f = CreateFrame("Frame", "GuildOSGazettePopup", UIParent, "BackdropTemplate")
        f:SetSize(560, 540)
        f:SetPoint("CENTER")
        f:SetFrameStrata("DIALOG")
        f:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
        f:SetBackdropColor(C.bg.r, C.bg.g, C.bg.b, 0.98)
        f:SetBackdropBorderColor(C.border.r, C.border.g, C.border.b, C.border.a or 1)
        f:SetMovable(true); f:EnableMouse(true); f:RegisterForDrag("LeftButton")
        f:SetScript("OnDragStart", f.StartMoving)
        f:SetScript("OnDragStop", f.StopMovingOrSizing)
        f:SetClampedToScreen(true)
        table.insert(UISpecialFrames, "GuildOSGazettePopup")
        f.title = UI:CreateTitle(f, "The Outlaw Gazette", 16)
        f.title:SetPoint("TOP", 0, -14)
        local sf = CreateFrame("ScrollFrame", "GuildOSGazetteScroll", f, "UIPanelScrollFrameTemplate")
        sf:SetPoint("TOPLEFT", 16, -50)
        sf:SetPoint("BOTTOMRIGHT", -34, 52)
        UI:SkinScrollBar(sf, "GuildOSGazetteScroll")
        f.sf = sf
        local copy = UI:CreateButton(f, "Copy for Discord", 150, 24)
        copy:SetPoint("BOTTOMLEFT", 16, 14)
        f.copy = copy
        local close = UI:CreateButton(f, "Close", 90, 24)
        close:SetPoint("BOTTOMRIGHT", -16, 14)
        close:SetScript("OnClick", function() f:Hide() end)
        self.gazettePopup = f
    end

    -- A fresh page each open, so an edited Gazette never shows old lines
    if f.child then f.child:Hide() end
    local child = CreateFrame("Frame", nil, f.sf)
    child:SetWidth(500)
    f.sf:SetScrollChild(child)
    f.child = child

    local y = 4
    local function add(text, size, col, after)
        local fs = UI:CreateText(child, text, size, col.r, col.g, col.b)
        fs:SetPoint("TOPLEFT", 6, -y)
        fs:SetWidth(488)
        fs:SetJustifyH("LEFT")
        fs:SetWordWrap(true)
        y = y + (fs:GetStringHeight() or size) + (after or 6)
    end

    for raw in ((gz or "") .. "\n"):gmatch("([^\n]*)\n") do
        local s = gazetteLine(raw)
        if s == "" then
            y = y + 6
        elseif raw:find(":scroll:") then
            -- the title is already on the popup
        elseif s:find("^Week of") then
            add(s, 12, C.textSoft, 14)
        elseif raw:find("^%s*:ek") then
            add(s, 12, C.text, 8)
        else
            add(s, 12, C.text, 6)
        end
    end
    child:SetHeight(y + 10)
    f.sf:SetVerticalScroll(0)

    if y <= 4 then add("No notes for this release.", 12, C.textSoft, 6) end
    child:SetHeight(y + 10)
    local heading = title or "The Outlaw Gazette"
    f.title:SetText(heading)
    f.copy:SetScript("OnClick", function() GuildOS:ShowExportPopup(heading, gz) end)
    f:Show(); f:Raise()
end

function EKO:GazetteGenerated()
    local ws = self:WeekStart()
    local ev = GuildOS.db and GuildOS.db.rosterLog and GuildOS.db.rosterLog.events or {}
    local joins, leaves, promos = {}, 0, {}
    for _, e in ipairs(ev) do
        if (e.timestamp or 0) >= ws then
            if e.action == "join" then joins[e.target or "?"] = true
            elseif e.action == "leave" or e.action == "kick" then leaves = leaves + 1
            elseif e.action == "promote" and e.target then promos[#promos + 1] = string.format("%s (%s)", e.target, e.detail or "?") end
        end
    end
    local nj = 0
    for _ in pairs(joins) do nj = nj + 1 end
    local levelers, runners = self:Leaderboards()
    local runs = self:Runs(ws)
    local L = {}
    L[#L + 1] = ":scroll: **The Outlaw Gazette** :scroll:"
    L[#L + 1] = "*Week of " .. date("%B %d", ws) .. "*"
    L[#L + 1] = ""
    L[#L + 1] = string.format(":ekobadge: **%d** new Outlaws signed the Ledger, **%d** rode off into the sunset.", nj, leaves)
    if #promos > 0 then
        L[#L + 1] = string.format(":ekoswords: **Earned their colors (%d):** %s", #promos, table.concat(promos, ", "))
    end
    L[#L + 1] = string.format(":ekoswords: **%d dungeon runs** logged by OutlawOS this week.", #runs)
    local function top(list, unit)
        local p = {}
        for i = 1, math.min(3, #list) do p[#p + 1] = string.format("%s (%s)", list[i].name, string.format(unit, list[i].n)) end
        return table.concat(p, ", ")
    end
    if #levelers > 0 then L[#L + 1] = "**Top levelers:** " .. top(levelers, "+%d") end
    if #runners > 0 then L[#L + 1] = "**Top dungeon runners:** " .. top(runners, "%d runs") end
    local h = self:Hunter()
    if h and h.month == monthKey() then L[#L + 1] = "**Bounty Hunter of the Month:** " .. h.name end
    local lotw = self:Lotw()
    if lotw then
        local f = {}
        for _, t in ipairs({ "easy", "medium", "hard" }) do
            local s = self:ParseLotw(lotw.text)[t]
            if s and #s.finders > 0 then f[#f + 1] = (t:sub(1, 1):upper() .. t:sub(2)) .. ": " .. table.concat(s.finders, ", ") end
        end
        if #f > 0 then L[#L + 1] = "**Location of the Week finders:** " .. table.concat(f, " · ") end
    end
    local r = self:Raffle()
    if r.winners and #r.winners > 0 then
        local w = {}
        for i, x in ipairs(r.winners) do w[#w + 1] = string.format("%d. %s (%s)", i, x.name, prizeText(x.prize or 0)) end
        L[#L + 1] = "**Raffle winners:** " .. table.concat(w, ", ")
    end
    local ann = self:Anniversaries()
    if #ann > 0 then
        local a = {}
        for i = 1, math.min(8, #ann) do a[#a + 1] = ann[i].name .. " (" .. annText(ann[i].days) .. ")" end
        L[#L + 1] = "**Ledger anniversaries:** " .. table.concat(a, ", ")
    end
    L[#L + 1] = ""
    L[#L + 1] = "New bounties go up Monday. See you on the road, Outlaws! :ekoswords:"
    return table.concat(L, "\n")
end

----------------------------------------------------------------------
-- Drawing helpers for the new pages
----------------------------------------------------------------------
local function sectionAt(child, text, y, first)
    local f = CreateFrame("Frame", nil, child)
    f:SetHeight(18)
    f:SetPoint("TOPLEFT", 0, -y)
    f:SetPoint("TOPRIGHT", 0, -y)
    local lbl = GuildOS.UI:CreateSectionTitle(f, text, first)
    lbl:SetPoint("TOPLEFT", 0, 0)
    return f
end

local function btn(parent, label, w, onClick)
    local b = GuildOS.UI:CreateButton(parent, label, w or 100, 20)
    b:SetScript("OnClick", onClick)
    return b
end

local function input(parent, w, placeholder)
    local box = GuildOS.UI:CreateInput(parent, w or 160, 22, { placeholder = placeholder })
    return box
end

----------------------------------------------------------------------
-- The Gilded Feather > Wanted: posters, the Hunter, Most Wanted, Location of the Week
----------------------------------------------------------------------
-- Clears typed in on the Wanted page: { week, clears = { [dungeon] = { { names = {...}, full = bool }, ... } } }.
EKO.CLEARS_MAX = 3   -- clears per dungeon on one board
local function formClears()
    local s = shared("bountyclearsform")
    if type(s) ~= "table" or s.week ~= EKO:WeekStart() then return {} end
    return s.clears or {}
end

function EKO:BuildWantedSub(panel)
    local UI, C = GuildOS.UI, GuildOS.Colors
    local _, child = makeList(panel, "GuildOSEKOWantedScroll", 0)
    local refresh
    local formState, live = nil, {}
    -- Copies what is typed into the open boxes back into the state, before a rebuild or a save.
    local function captureForm()
        if not formState then return end
        for dungeon, rows in pairs(formState.rows) do
            for i, r in ipairs(rows) do
                local l = live[dungeon] and live[dungeon][i]
                if l then
                    for k = 1, 5 do r.names[k] = l.boxes[k]:GetText() or "" end
                    r.full = l.cb:GetChecked() and true or false
                end
            end
        end
    end
    local function formSync(week)
        if formState and formState.week == week then return end
        formState = { week = week, rows = {} }
        for dungeon, list in pairs(formClears()) do
            formState.rows[dungeon] = {}
            for _, c in ipairs(list) do
                local names = {}
                for k = 1, 5 do names[k] = c.names[k] or "" end
                table.insert(formState.rows[dungeon], { names = names, full = c.full and true or false })
            end
        end
    end
    refresh = function()
        if not EKO:DB() then return end
        captureForm()
        clear(child)
        local width = math.max(400, (child:GetWidth() or 0) > 1 and child:GetWidth() or 760)
        local y = 0
        local classes = classMap()

        -- Bounty Hunter of the Month
        local h = EKO:Hunter()
        sectionAt(child, "BOUNTY HUNTER OF THE MONTH", y, true); y = y + 24
        txt(child, (h and h.month == monthKey()) and (GOLDC .. h.name .. "|r  ·  " .. date("%B %Y")) or (GREY .. "Not crowned yet this month. Most Bounty Points by month's end wins.|r"), 0, y, width, 14)
        y = y + 28

        -- Wanted posters
        local bt = EKO:Bounties()
        local list = bt and EKO:ParseBounties(bt.text) or {}
        local wh = sectionAt(child, "WANTED  ·  this week's bounties", y)
        if GuildOS:IsOfficer() then
            local cb = btn(wh, "Verified clears", 120, function()
                local cs = shared("bountyclears")
                local cur = (type(cs) == "table" and cs.week == EKO:WeekStart()) and (cs.text or "") or ""
                EKO:TextPopup("Verified clears",
                    "Paste this week's rows from the Bounty Board sheet's Clears tab, columns A to J, all at once. Only the newest week in the paste counts. Each Clear # with three or more Outlaws marks its dungeon's poster. Clear the box to remove them.",
                    cur, function(t)
                        EKO:SetShared("bountyclears", { text = t, week = (t ~= "" and EKO:WeekStart()) or nil })
                    end)
            end)
            cb:SetPoint("TOPRIGHT", 0, 2)
        end
        y = y + 26
        if #list == 0 then
            txt(child, "No bounties posted this week yet. Officers post them in Journal > Set bounties.", 0, y, width, 12, C.textSoft)
            y = y + 22
        else
            local cols = math.max(1, math.min(3, math.floor((width + 12) / 240)))
            local cw = math.floor((width - 12 * (cols - 1)) / cols)
            local ch = 132
            for i, bnt in ipairs(list) do
                local col = (i - 1) % cols
                local row = math.floor((i - 1) / cols)
                local card = CreateFrame("Frame", nil, child, "BackdropTemplate")
                card:SetSize(cw, ch)
                card:SetPoint("TOPLEFT", col * (cw + 12), -(y + row * (ch + 12)))
                card:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 2 })
                card:SetBackdropColor(0.80, 0.70, 0.50, 0.95)   -- parchment
                card:SetBackdropBorderColor(0.40, 0.27, 0.12, 1)
                local ourPaper = media("parchment.tga")
                local paper = ourPaper or firstTex({ "Interface\\QuestFrame\\QuestBG", "Interface\\Stationery\\StationeryTest1" })
                if paper then
                    local pt = card:CreateTexture(nil, "BORDER")
                    pt:SetPoint("TOPLEFT", 2, -2); pt:SetPoint("BOTTOMRIGHT", -2, 2)
                    pt:SetTexture(paper)
                    if ourPaper then pt:SetTexCoord(0, 1, 0, 1) else pt:SetTexCoord(0, 0.58, 0, 0.42) end
                end
                local function ink(s, yy, size, r, g, b)
                    local fs = UI:CreateText(card, s, size, r or 0.22, g or 0.13, b or 0.05)
                    fs:SetPoint("TOP", 0, -yy)
                    fs:SetWidth(cw - 16)
                    fs:SetJustifyH("CENTER")
                    fs:SetWordWrap(true)
                    return fs
                end
                local w = ink("WANTED", 6, 18, 0.45, 0.08, 0.05)
                if EKO.themeOn then pcall(w.SetFont, w, EKO.FONT_TITLE, 24, "") end
                ink(bnt.name, 34, 13)
                ink((bnt.tier and (bnt.tier .. " tier") or "Bounty") .. "  ·  Reward: 1 Bounty Point + 1 raffle entry", 54, 10)
                ink("Full party of 5 Outlaws: double points", 70, 10)
                local claimed = EKO:BountyClaims(bnt.name)
                if #claimed > 0 then
                    ink(string.format("CLAIMED %dx", #claimed), 90, 12, 0.10, 0.40, 0.10)
                    ink(table.concat(claimed[#claimed].who, ", "), 108, 9)
                else
                    ink("Still at large", 92, 12, 0.45, 0.08, 0.05)
                end
            end
            y = y + (math.floor((#list - 1) / cols) + 1) * (ch + 12)
        end

        -- Verified clears, typed in: one block per dungeon on the board, up to CLEARS_MAX clears each.
        if GuildOS:IsOfficer() and #list > 0 then
            formSync(EKO:WeekStart())
            y = y + 12
            sectionAt(child, "VERIFIED CLEARS  ·  type them in, or paste above", y); y = y + 24
            live = {}
            local nameW = math.max(50, math.floor((width - 200) / 5) - 6)
            for _, bnt in ipairs(list) do
                local rows = formState.rows[bnt.name] or {}
                formState.rows[bnt.name] = rows
                txt(child, GOLDC .. bnt.name .. "|r" .. (bnt.tier and ("  ·  " .. bnt.tier .. " tier") or ""), 0, y, width, 12)
                y = y + 18
                live[bnt.name] = {}
                for i, r in ipairs(rows) do
                    local rowF = CreateFrame("Frame", nil, child)
                    rowF:SetSize(width, 26)
                    rowF:SetPoint("TOPLEFT", 0, -y)
                    local entry = { boxes = {} }
                    live[bnt.name][i] = entry
                    for k = 1, 5 do
                        local box = input(rowF, nameW, "Name")
                        box:SetPoint("LEFT", (k - 1) * (nameW + 6), 0)
                        box:SetText(r.names[k] or "")
                        entry.boxes[k] = box
                    end
                    local cb = CreateFrame("CheckButton", nil, rowF, "UICheckButtonTemplate")
                    cb:SetSize(22, 22)
                    cb:SetPoint("LEFT", 5 * (nameW + 6), 0)
                    cb:SetChecked(r.full)
                    entry.cb = cb
                    local cbl = UI:CreateText(rowF, "Full party", 10, C.textSoft.r, C.textSoft.g, C.textSoft.b)
                    cbl:SetPoint("LEFT", cb, "RIGHT", 2, 0)
                    local rm = btn(rowF, "Remove", 66, function()
                        captureForm()
                        table.remove(formState.rows[bnt.name], i)
                        refresh()
                    end)
                    rm:SetPoint("LEFT", cbl, "RIGHT", 6, 0)
                    y = y + 28
                end
                if #rows < EKO.CLEARS_MAX then
                    local add = btn(child, "+ Add clear", 100, function()
                        captureForm()
                        table.insert(formState.rows[bnt.name], { names = { "", "", "", "", "" }, full = false })
                        refresh()
                    end)
                    add:SetPoint("TOPLEFT", 0, -y)
                    y = y + 26
                end
                y = y + 8
            end
            local sv = btn(child, "Save verified clears", 160, function()
                captureForm()
                local clears = {}
                for dungeon, rows in pairs(formState.rows) do
                    for _, r in ipairs(rows) do
                        local names, seen = {}, {}
                        for _, n in ipairs(r.names) do
                            local t = (n or ""):match("^%s*(.-)%s*$")
                            if t ~= "" and not seen[t] then seen[t] = true; names[#names + 1] = t end
                        end
                        if #names > 0 then
                            clears[dungeon] = clears[dungeon] or {}
                            table.insert(clears[dungeon], { names = names, full = r.full and true or false })
                        end
                    end
                end
                EKO:SetShared("bountyclearsform", { week = EKO:WeekStart(), clears = clears })
            end)
            sv:SetPoint("TOPLEFT", 0, -y)
            if UI.SetButtonVariant then UI:SetButtonVariant(sv, "primary") end
            y = y + 30
        end

        -- Most Wanted (Notoriety)
        y = y + 12
        sectionAt(child, "MOST WANTED  ·  Notoriety", y); y = y + 24
        local ranked = {}
        for name, m in pairs(EKO:Roster()) do
            local score = EKO:Notoriety(name, m.level)
            ranked[#ranked + 1] = { name = name, m = m, score = score }
        end
        table.sort(ranked, function(a, b) if a.score ~= b.score then return a.score > b.score end return a.name < b.name end)
        for i = 1, math.min(10, #ranked) do
            local e = ranked[i]
            local row = newRow(child, y, i, 24)
            cell(row, string.format("%d.", i), 8, 30)
            cell(row, nameColored(e.name, e.m, classes), 40, 200)
            cell(row, GOLDC .. e.score .. "|r", 250, 60)
            cell(row, EKO:WantedLevel(e.score), 310, 140, C.textSoft.r, C.textSoft.g, C.textSoft.b)
            local seals = EKO:Seals(e.name, e.m.level)
            cell(row, table.concat(seals, ", "), 455, math.max(100, width - 460), C.textSoft.r, C.textSoft.g, C.textSoft.b)
            y = y + 26
        end
        txt(child, "Notoriety: 3 per dungeon run, 2 per different dungeon, 1 per 2 levels, 5 per Location of the Week find, 10 per guild first, 15 per Bounty Hunter of the Month. Runs are what OutlawOS logged.", 0, y + 4, width, 10, C.textSoft)
        y = y + 34

        -- Location of the Week
        local lotw = EKO:Lotw()
        local lspots = lotw and EKO:ParseLotw(lotw.text) or {}
        local lhdr = sectionAt(child, "LOCATION OF THE WEEK" .. (lspots.theme and ("  ·  Theme: " .. lspots.theme) or ""), y)
        local canEdit = GuildOS:IsOfficer()
        if canEdit then
            local eb = btn(lhdr, lotw and "Edit spots & prizes" or "Post this week's spots", 150, function() EKO:EditLotw() end)
            eb:SetPoint("TOPRIGHT", 0, 2)
        end
        y = y + 24
        if not lotw then
            txt(child, "This week's spots aren't posted yet. New spots every Friday!", 0, y, width, 12, C.textSoft)
            y = y + 22
        else
            local spots = lspots
            for i, t in ipairs({ "easy", "medium", "hard" }) do
                local s = spots[t]
                if s then
                    local row = newRow(child, y, i, 1)
                    cell(row, GOLDC .. t:sub(1, 1):upper() .. t:sub(2) .. "|r", 8, 70)
                    -- The finders/prizes column sits at rightX; the hint stops 14px short of it so the two never overlap
                    local rightX = math.max(250, width - (canEdit and 430 or 330))
                    local hint = txt(row, (s.hint ~= "" and ("|cffdddddd" .. s.hint .. "|r") or GREY .. "(no hint)|r"), 80, 6, math.max(160, rightX - 80 - 14), 11)
                    local f = {}
                    for _, n in ipairs(s.finders) do f[#f + 1] = nameColored(n, nil, classes) end
                    local found = #f > 0 and ("Found: " .. table.concat(f, ", ")) or (GREY .. "not found yet|r")
                    if #f > 0 and #f < 3 then found = found .. GREY .. "  (" .. (3 - #f) .. " left)|r" end
                    local right = txt(row, found .. (s.prizes and ("\n" .. GOLDC .. "Prizes: " .. s.prizes .. "|r") or ""), rightX, 6, 320, 11)
                    if canEdit then
                        local tier = t
                        local ab = btn(row, "Add winner", 90, function()
                            EKO:TextPopup("Add a " .. tier:sub(1, 1):upper() .. tier:sub(2) .. " winner", "Type the winner's main character name, then Save. It goes to everyone with OutlawOS.", "",
                                function(name) EKO:LotwAddFinder(tier, (name or ""):match("^[^\n]*")) end)
                        end)
                        ab:SetPoint("TOPRIGHT", -8, -4)
                    end
                    local h = math.max(28, (hint:GetStringHeight() or 14) + 12, (right:GetStringHeight() or 14) + 12)
                    row:SetHeight(h)
                    y = y + h + 2
                end
            end
            txt(child, "First 3 to find each spot and post a screenshot with their character in #lotw-submissions win gold.", 0, y + 2, width, 10, C.textSoft)
            y = y + 24
        end
        child:SetHeight(y + 20)
    end
    refreshers.wanted = function() if panel:IsVisible() then refresh() end end
    return refresh
end

----------------------------------------------------------------------
-- The Gilded Feather > Raffle
----------------------------------------------------------------------
-- The raffle's gold per place, one per line. Read fresh each time, so it edits what is saved now.
-- Shared by the Raffle tab and Quick Tools.
function EKO:EditRafflePrizes()
    local r = self:Raffle()
    self:TextPopup("Raffle prizes", "Gold per place, one per line (1st on the first line). Use 0.7 for 70s, 0.5 for 50s, 0.3 for 30s.",
        table.concat(r.prizes, "\n"), function(t)
            local p = {}
            for n in t:gmatch("%d+%.?%d*") do p[#p + 1] = tonumber(n) end
            if #p > 0 then self:SetShared("raffle", { text = r.text, prizes = p, winners = r.winners or {}, week = r.week }) end
        end)
end

function EKO:BuildRaffleSub(panel)
    local UI, C = GuildOS.UI, GuildOS.Colors
    local _, child = makeList(panel, "GuildOSEKORaffleScroll", 0)
    local refresh
    refresh = function()
        if not EKO:DB() then return end
        clear(child)
        local width = math.max(400, (child:GetWidth() or 0) > 1 and child:GetWidth() or 760)
        local r = EKO:Raffle()
        local entries, total = EKO:ParseRaffle(r.text)
        local y = 0
        local hdr = sectionAt(child, string.format("SUNDAY RAFFLE  ·  %d entries from %d Outlaws", total, #entries), y, true)
        if GuildOS:IsOfficer() then
            local x = 0
            local function hb(label, w, fn)
                local b = btn(hdr, label, w, fn)
                b:SetPoint("TOPRIGHT", -x, 2)
                x = x + w + 6
                return b
            end
            hb("Reset", 60, function() EKO:SetShared("raffle", { text = r.text, prizes = r.prizes, winners = {}, week = r.week }) end)
            hb("Announce", 80, function()
                local a = EKO:RaffleAnnouncement()
                if a then ChatFrame_OpenChat("/g " .. a) else GuildOS:Print("Draw a winner first.") end
            end)
            hb("Draw next place", 120, function() EKO:DrawRaffle() end)
            hb("Prizes", 70, function() EKO:EditRafflePrizes() end)
            hb("Set entries", 90, function()
                EKO:TextPopup("Raffle entries", "Entries are counted from this week's clears. Set a list here only to override them for this week, one Outlaw per line, e.g.  Ryzen Moros 4. Clear the box to go back to the counted entries.",
                    r.text or "", function(t) EKO:SetShared("raffle", { text = t, prizes = r.prizes, winners = {}, week = (t ~= "" and EKO:WeekStart()) or nil }) end)
            end)
        end
        y = y + 26
        local prizes = r.prizes
        local places = PLACE_WORD
        local pp = {}
        for i, g in ipairs(prizes) do pp[#pp + 1] = (places[i] or i .. "th") .. " " .. prizeText(g) end
        txt(child, "Prizes: " .. GOLDC .. table.concat(pp, ",  ") .. "|r", 0, y, width, 13)
        y = y + 24
        if r.winners and #r.winners > 0 then
            sectionAt(child, "WINNERS", y); y = y + 24
            for i, w in ipairs(r.winners) do
                local row = newRow(child, y, i, 26)
                cell(row, GOLDC .. (places[i] or i .. "th") .. "|r", 8, 50)
                cell(row, w.name, 60, 220)
                cell(row, prizeText(w.prize or 0), 290, 60)
                cell(row, "rolled " .. (w.roll or "?"), 360, 120, C.textSoft.r, C.textSoft.g, C.textSoft.b)
                y = y + 28
            end
        end
        sectionAt(child, "ENTRIES", y + 6); y = y + 30
        if #entries == 0 then
            txt(child, GuildOS:IsOfficer() and "No entries yet: use Set entries." or "Entries aren't posted yet.", 0, y, width, 12, C.textSoft)
            y = y + 22
        end
        table.sort(entries, function(a, b) if a.n ~= b.n then return a.n > b.n end return a.name < b.name end)
        for i, e in ipairs(entries) do
            local row = newRow(child, y, i, 22)
            cell(row, e.name, 8, 240)
            cell(row, e.n .. (e.n == 1 and " entry" or " entries"), 260, 90)
            cell(row, string.format("%.1f%% chance", total > 0 and e.n / total * 100 or 0), 360, 120, C.textSoft.r, C.textSoft.g, C.textSoft.b)
            y = y + 24
        end
        txt(child, "Draws use the game's own /roll 1-N, so everyone nearby sees it. Each entry is one number; a winner is taken out before the next place.", 0, y + 6, width, 10, C.textSoft)
        child:SetHeight(y + 40)
    end
    refreshers.raffle = function() if panel:IsVisible() then refresh() end end
    return refresh
end

----------------------------------------------------------------------
-- The Gilded Feather > Tavern: who's where, Ride Out, Safehouses, Campfire nights
----------------------------------------------------------------------
function EKO:BuildTavernSub(panel)
    local UI, C = GuildOS.UI, GuildOS.Colors
    local _, child = makeList(panel, "GuildOSEKOTavernScroll", 0)
    local refresh
    refresh = function()
        if not EKO:DB() then return end
        clear(child)
        local width = math.max(400, (child:GetWidth() or 0) > 1 and child:GetWidth() or 760)
        local y = 0
        -- Online by zone
        local zones, online = {}, 0
        for i = 1, (GetNumGuildMembers and GetNumGuildMembers() or 0) do
            local name, _, _, level, _, zone, _, _, isOnline, _, classFile = GetGuildRosterInfo(i)
            if isOnline and name then
                online = online + 1
                zone = (zone and zone ~= "") and zone or "Unknown"
                zones[zone] = zones[zone] or {}
                table.insert(zones[zone], { name = short(name), class = classFile, level = level })
            end
        end
        local zl = {}
        for z, list in pairs(zones) do zl[#zl + 1] = { zone = z, list = list } end
        table.sort(zl, function(a, b) if #a.list ~= #b.list then return #a.list > #b.list end return a.zone < b.zone end)
        sectionAt(child, string.format("THE TAVERN  ·  %d Outlaws online in %d zones", online, #zl), y, true); y = y + 26
        for i, z in ipairs(zl) do
            table.sort(z.list, function(a, b) return a.name < b.name end)
            local names = {}
            for _, p in ipairs(z.list) do names[#names + 1] = nameColored(p.name, { class = p.class }) .. GREY .. " " .. (p.level or "") .. "|r" end
            local row = newRow(child, y, i, 1)
            local zt = txt(row, GOLDC .. z.zone .. "|r  " .. GREY .. "(" .. #z.list .. ")|r", 8, 4, 180, 12)
            local nt = txt(row, table.concat(names, ",  "), 195, 4, math.max(150, width - 205), 11)
            local h = math.max(20, (nt:GetStringHeight() or 14) + 8)
            row:SetHeight(h)
            y = y + h + 2
        end
        if online == 0 then txt(child, "Nobody online right now (or the roster hasn't loaded yet).", 0, y, width, 12, C.textSoft); y = y + 22 end

        -- Ride Out
        y = y + 14
        sectionAt(child, "RIDE OUT  ·  find a crew for a bounty", y); y = y + 26
        local bt = EKO:Bounties()
        local list = bt and EKO:ParseBounties(bt.text) or {}
        if #list == 0 then
            txt(child, "No bounties posted this week yet.", 0, y, width, 12, C.textSoft); y = y + 22
        else
            local x = 0
            for _, bnt in ipairs(list) do
                local act = EKO:BountyActId(bnt.name)
                local looking = EKO:BountyLooking(act)
                local label = "Ride out: " .. bnt.name .. (looking > 0 and string.format(L["  (%d looking)"], looking) or "")
                local b = btn(child, label, 0, function()
                    if act and GuildOS.OpenGroupComposer then
                        GuildOS.OpenGroupComposer(act, "seek")
                    else
                        ChatFrame_OpenChat(string.format("/g Riding out for %s (%sbounty)! Need a crew of Outlaws, whisper me for an invite.", bnt.name, bnt.tier and (bnt.tier .. " ") or ""))
                    end
                end)
                b:SetWidth(math.ceil(b.label:GetStringWidth() or 100) + 20)
                if x + b:GetWidth() > width then x = 0; y = y + 26 end
                b:SetPoint("TOPLEFT", x, -y)
                x = x + b:GetWidth() + 6
            end
            y = y + 30
        end

        -- Safehouses
        y = y + 10
        local sh = sectionAt(child, "SAFEHOUSES  ·  meetup spots", y)
        if GuildOS:IsOfficer() then
            local box = input(sh, 200, "Name this spot")
            box:SetPoint("TOPRIGHT", -150, 4)
            local add = btn(sh, "Add where I stand", 140, function() EKO:AddSafehouse(box:GetText()) end)
            add:SetPoint("TOPRIGHT", 0, 2)
        end
        y = y + 28
        for i, d in ipairs(EKO:Safehouses()) do
            local row = newRow(child, y, i, 26)
            cell(row, d.name, 8, math.max(150, width - 330))
            cell(row, string.format("%.1f, %.1f", d.x, d.y), math.max(160, width - 310), 90, C.textSoft.r, C.textSoft.g, C.textSoft.b)
            local go = btn(row, "Waypoint", 80, function() EKO:Waypoint(d) end)
            go:SetPoint("RIGHT", GuildOS:IsOfficer() and -40 or -8, 0)
            if GuildOS:IsOfficer() and i > #EKO.SAFEHOUSE_DEFAULTS then
                local x = btn(row, "X", 26, function() EKO:RemoveSafehouse(d.name) end)
                x:SetPoint("RIGHT", -8, 0)
            end
            y = y + 28
        end

        -- Campfire nights
        y = y + 12
        sectionAt(child, "CAMPFIRE NIGHTS  ·  social events", y); y = y + 26
        for i, c in ipairs(EKO.CAMPFIRES) do
            local row = newRow(child, y, i, 26)
            cell(row, GOLDC .. c.name .. "|r", 8, 180)
            cell(row, c.game, 195, math.max(150, width - 420), C.textSoft.r, C.textSoft.g, C.textSoft.b)
            if GuildOS:IsOfficer() then
                local d = btn(row, "Copy for Discord", 120, function() GuildOS:ShowExportPopup(c.name, c.discord) end)
                d:SetPoint("RIGHT", -8, 0)
                local g = btn(row, "Announce", 80, function() ChatFrame_OpenChat("/g " .. c.game) end)
                g:SetPoint("RIGHT", d, "LEFT", -6, 0)
            end
            y = y + 28
        end
        child:SetHeight(y + 20)
    end
    refreshers.tavern = function() if panel:IsVisible() then refresh() end end
    return refresh
end

----------------------------------------------------------------------
-- Inner Circle > Outlaw Desk: Hunter, LotW, strikes, Quote the Code, Gazette, ads, anniversaries
----------------------------------------------------------------------
----------------------------------------------------------------------
-- Quick Tools (leadership only): the editors and actions an officer or Raid Leader uses most, grouped
-- by what they change. Each button opens the same editor as its home screen and keeps that screen's check.
----------------------------------------------------------------------
function EKO:BuildQuickSub(panel)
    local _, child = makeList(panel, "GuildOSEKOQuickScroll", 0)
    local refresh
    refresh = function()
        if not EKO:DB() then return end
        clear(child)
        local width = math.max(400, (child:GetWidth() or 0) > 1 and child:GetWidth() or 760)
        local officer = GuildOS:IsOfficer()
        local y = 0

        -- A category: its title, then its buttons in rows that wrap at the panel's width. An item with
        -- `when` shows only while that returns true.
        local function category(title, items)
            local shown = {}
            for _, it in ipairs(items) do
                if not it.when or it.when() then shown[#shown + 1] = it end
            end
            if #shown == 0 then return end
            sectionAt(child, title, y, y == 0); y = y + 26
            local x, rowY = 0, y
            for _, it in ipairs(shown) do
                local w = it.w or 150
                if x > 0 and x + w > width then x = 0; rowY = rowY + 26 end
                btn(child, it.label, w, it.fn):SetPoint("TOPLEFT", x, -rowY)
                x = x + w + 6
            end
            y = rowY + 36
        end

        category("LOCATION OF THE WEEK", {
            { label = "Edit spots & prizes", w = 170, when = function() return officer end,
              fn = function() EKO:EditLotw() end },
        })

        -- Bounty Hunter of the Month: a name, Crown, and who holds it this month.
        sectionAt(child, "BOUNTY HUNTER OF THE MONTH", y, y == 0); y = y + 26
        local hbox = input(child, 180, "Bounty Hunter of the Month")
        hbox:SetPoint("TOPLEFT", 0, -y)
        local crown = btn(child, "Crown", 70, function() EKO:SetHunter(hbox:GetText()); refresh() end)
        crown:SetPoint("LEFT", hbox, "RIGHT", 6, 0)
        local h = EKO:Hunter()
        local ht = txt(child, (h and h.month == monthKey()) and ("Current: " .. GOLDC .. h.name .. "|r") or "", 0, 0, 220, 11)
        ht:ClearAllPoints(); ht:SetPoint("LEFT", crown, "RIGHT", 10, 0)
        y = y + 36

        category("BOUNTY BOARD", {
            { label = "Set bounties", w = 120, when = function() return officer end, fn = function()
                local bt = EKO:Bounties()
                EKO:TextPopup("This week's Bounty Board", "One dungeon per line. Start with Low:, Mid: or High: for its tier, e.g.  Low: The Hall of Thanes",
                    bt and bt.text or "Low: \nLow: \nMid: \nMid: \nHigh: \nHigh: ", function(t) EKO:SaveBounties(t) end)
            end },
            { label = "Set verified clears", w = 150, when = function() return officer end, fn = function()
                local cs = shared("bountyclears")
                local cur = (type(cs) == "table" and cs.week == EKO:WeekStart()) and (cs.text or "") or ""
                EKO:TextPopup("Verified clears",
                    "Paste this week's rows from the Bounty Board sheet's Clears tab, columns A to J, all at once. Only the newest week in the paste counts. Each Clear # with three or more Outlaws marks its dungeon's poster. Clear the box to remove them.",
                    cur, function(t)
                        EKO:SetShared("bountyclears", { text = t, week = (t ~= "" and EKO:WeekStart()) or nil })
                    end)
            end },
        })

        -- Reset raffle is left to the Raffle tab: it clears the winners with no way back, so it isn't one click here.
        category("RAFFLE", {
            { label = "Raffle prizes", w = 120, when = function() return officer end, fn = function() EKO:EditRafflePrizes() end },
            { label = "Draw next place", w = 130, when = function() return officer end, fn = function() EKO:DrawRaffle() end },
            { label = "Announce raffle", w = 130, when = function() return officer end, fn = function()
                local a = EKO:RaffleAnnouncement()
                if a then ChatFrame_OpenChat("/g " .. a) else GuildOS:Print("Draw a winner first.") end
            end },
        })

        category("GAZETTE AND ANNOUNCEMENTS", {
            { label = "The Outlaw Gazette", w = 150, fn = function() EKO:ShowGazettePopup(EKO:Gazette()) end },
            { label = "Edit Gazette", w = 110, when = function() return EKO:CanEditAbout() end,
              fn = function() EKO:OpenGazetteEditor() end },
            { label = "Post Announcement", w = 150,
              when = function() return GuildOS.Announcements ~= nil and GuildOS.Announcements.CanPost() end,
              fn = function() GuildOS.Announcements.OpenPopup() end },
        })

        category("CHECKS", {
            { label = "Check who's online", w = 150, fn = function() EKO:CheckPatch() end },
        })
    end
    return refresh
end

function EKO:BuildDeskSub(panel)
    local UI, C = GuildOS.UI, GuildOS.Colors
    local _, child = makeList(panel, "GuildOSEKODeskScroll", 0)
    local stillOpen = false -- the install check's "still on GuildOS" list starts closed
    local onOpen, noOpen = false, false -- and so do the "on OutlawOS" and "no addon data" lists
    local refresh
    refresh = function()
        if not EKO:DB() then return end
        clear(child)
        local width = math.max(400, (child:GetWidth() or 0) > 1 and child:GetWidth() or 760)
        local y = 0
        local officer = GuildOS:IsOfficer()

        -- Weekly posts
        sectionAt(child, "THIS WEEK'S POSTS", y, true); y = y + 26
        local row = CreateFrame("Frame", nil, child)
        row:SetHeight(24); row:SetPoint("TOPLEFT", 0, -y); row:SetPoint("TOPRIGHT", 0, -y)
        local b1 = btn(row, "The Outlaw Gazette", 150, function() EKO:ShowGazettePopup(EKO:Gazette()) end)
        b1:SetPoint("LEFT", 0, 0)
        local canEdit = EKO:CanEditAbout()
        local bEdit = btn(row, "Edit Gazette", 110, function() EKO:OpenGazetteEditor() end)
        bEdit:SetPoint("LEFT", b1, "RIGHT", 6, 0)
        if not canEdit then bEdit:Hide() end
        local b2 = btn(row, "Location of the Week", 160, function()
            local l = EKO:Lotw()
            EKO:TextPopup("Location of the Week", "One line per spot and one per finders list:  Easy: <hint>  and  Easy finders: Name, Name  (Medium, Hard the same).",
                l and l.text or "Easy: \nEasy finders: \nMedium: \nMedium finders: \nHard: \nHard finders: ", function(t) EKO:SaveLotw(t) end)
        end)
        b2:SetPoint("LEFT", canEdit and bEdit or b1, "RIGHT", 6, 0)
        local hbox = input(row, 180, "Bounty Hunter of the Month")
        hbox:SetPoint("LEFT", b2, "RIGHT", 16, 0)
        local b3 = btn(row, "Crown", 70, function() EKO:SetHunter(hbox:GetText()) end)
        b3:SetPoint("LEFT", hbox, "RIGHT", 6, 0)
        local h = EKO:Hunter()
        local ht = txt(row, (h and h.month == monthKey()) and ("Current: " .. GOLDC .. h.name .. "|r") or "", 0, 4, 220, 11)
        ht:ClearAllPoints(); ht:SetPoint("LEFT", b3, "RIGHT", 10, 0)
        -- Opens the announcement popup (Modules/Announcements.lua); hidden for recruiters, who cannot post.
        local bPost = btn(row, "Post Announcement", 150, function() GuildOS.Announcements.OpenPopup() end)
        bPost:SetPoint("RIGHT", row, "RIGHT", 0, 0)
        if not (GuildOS.Announcements and GuildOS.Announcements.CanPost()) then bPost:Hide() end
        y = y + 32

        -- Who has OutlawOS: every leader (the Leadership tab's list and the roster's Leadership ranks), with
        -- the version they check in with. A leader who has never checked in shows NOT INSTALLED; any version
        -- other than this release is out of date.
        local LEAD_RANKS = { ["guild master"] = true, ["gm alt"] = true, ["co-guild master"] = true, ["officer"] = true,
            ["recruiter"] = true, ["herald"] = true, ["raid marshal"] = true }
        local seen = {}
        for _, u in ipairs(EKO:PatchUsers()) do seen[short(u.name)] = u end
        local users = {}
        for name, m in pairs(EKO:Roster()) do
            if EKO:IsLeader(name) or (m.rank and LEAD_RANKS[m.rank:lower()]) then
                local rec = seen[name] or {}
                users[#users + 1] = { name = name, m = m, online = m.online, rank = m.rank, v = rec.v, at = rec.at }
            end
        end
        table.sort(users, function(a, b)
            if (a.online and 1 or 0) ~= (b.online and 1 or 0) then return a.online end
            return a.name < b.name
        end)
        local CURRENT = EKO.PATCH_VERSION
        local onl, current = 0, 0
        for _, u in ipairs(users) do
            if u.online then onl = onl + 1 end
            if u.v == CURRENT then current = current + 1 end
        end
        local wh = sectionAt(child, string.format("OutlawOS INSTALLED  ·  %d of %d leaders current, %d online now", current, #users, onl), y)
        local chk = btn(wh, "Check who's online", 140, function() EKO:CheckPatch() end)
        chk:SetPoint("TOPRIGHT", 0, 2)
        y = y + 26
        if #users == 0 then txt(child, "No leaders found in the roster.", 0, y, width, 12, C.textSoft); y = y + 22 end
        for i, u in ipairs(users) do
            local r = newRow(child, y, i, 22)
            cell(r, u.m and classColored(u.m) or u.name, 8, 200)
            cell(r, u.rank or (GREY .. "not in roster|r"), 215, 140, C.textSoft.r, C.textSoft.g, C.textSoft.b)
            cell(r, u.online and (GREEN .. "online|r") or (GREY .. "offline|r"), 360, 70)
            if not u.v then
                cell(r, "|cffff6060NOT INSTALLED|r", 435, 150)
            elseif u.v == CURRENT then
                cell(r, GREEN .. "current|r", 435, 150)
            else
                cell(r, "|cffff6060UPDATE OutlawOS|r", 435, 150)
            end
            cell(r, u.v and ("v" .. tostring(u.v)) or "", 590, 200, C.textSoft.r, C.textSoft.g, C.textSoft.b)
            y = y + 24
        end
        txt(child, "Each leader's version is the one they check in with at login. NOT INSTALLED means no check-in yet; UPDATE OutlawOS means an older version.", 0, y + 2, width, 10, C.textSoft)
        y = y + 26

        -- Install check: every guild member. A check-in in the last EKO.PATCH_RECENT_DAYS days is OutlawOS; a
        -- member the guild's addon sync shows on GuildOS without one is still on GuildOS; the rest show no addon.
        local recent = now() - EKO.PATCH_RECENT_DAYS * DAY
        local checked = {}
        for _, u in ipairs(EKO:PatchUsers()) do
            if u.at and u.at >= recent then checked[short(u.name)] = u end
        end
        local still, onOutlaw, noAddon = {}, {}, {}
        for name, m in pairs(EKO:Roster()) do
            local mem = EKO:MemberRecord(name, m.full)
            if checked[name] then
                onOutlaw[#onOutlaw + 1] = { name = name, m = m, online = m.online }
            elseif mem and mem.addonVersion then
                still[#still + 1] = { name = name, m = m, online = m.online, v = mem.addonVersion }
            else
                noAddon[#noAddon + 1] = { name = name, m = m, online = m.online }
            end
        end
        local function byOnline(a, b)
            if (a.online and 1 or 0) ~= (b.online and 1 or 0) then return a.online end
            return a.name < b.name
        end
        table.sort(still, byOnline)
        table.sort(onOutlaw, byOnline)
        table.sort(noAddon, byOnline)
        -- A list of members behind a Show list button, the same as the Still on GuildOS list.
        local function memberList(title, list, open, onToggle, extra)
            sectionAt(child, title, y); y = y + 26
            if #list == 0 then
                txt(child, "None.", 0, y, width, 12, C.textSoft); y = y + 22
            else
                local toggle = CreateFrame("Frame", nil, child)
                toggle:SetHeight(24); toggle:SetPoint("TOPLEFT", 0, -y); toggle:SetPoint("TOPRIGHT", 0, -y)
                local tb = btn(toggle, (open and "Hide list" or "Show list") .. "  (" .. #list .. ")", 150, onToggle)
                tb:SetPoint("LEFT", 0, 0)
                y = y + 30
                if open then
                    for i, u in ipairs(list) do
                        local r = newRow(child, y, i, 22)
                        cell(r, u.m and classColored(u.m) or u.name, 8, 200)
                        if extra then cell(r, extra(u), 215, 200) end
                        cell(r, u.online and (GREEN .. "online|r") or (GREY .. "offline|r"), 430, 70)
                        y = y + 24
                    end
                end
            end
            y = y + 8
        end
        sectionAt(child, string.format("INSTALL CHECK  ·  %d on OutlawOS, %d still on GuildOS, %d no addon", #onOutlaw, #still, #noAddon), y)
        y = y + 26
        local inote = txt(child, "On OutlawOS: a check-in in the last " .. EKO.PATCH_RECENT_DAYS .. " days. Still on GuildOS: the guild's addon sync shows GuildOS and no recent check-in. Use Check who's online above to refresh.", 0, y, width, 10, C.textSoft)
        y = y + (inote:GetStringHeight() or 12) + 10
        if #still == 0 then
            txt(child, "Nobody is still on GuildOS.", 0, y, width, 12, C.textSoft); y = y + 22
        else
            local toggle = CreateFrame("Frame", nil, child)
            toggle:SetHeight(24); toggle:SetPoint("TOPLEFT", 0, -y); toggle:SetPoint("TOPRIGHT", 0, -y)
            local tb = btn(toggle, (stillOpen and "Hide list" or "Show list") .. "  (" .. #still .. ")", 150, function()
                stillOpen = not stillOpen
                refresh()
            end)
            tb:SetPoint("LEFT", 0, 0)
            y = y + 30
            if stillOpen then
                for i, u in ipairs(still) do
                    local r = newRow(child, y, i, 22)
                    cell(r, u.m and classColored(u.m) or u.name, 8, 200)
                    cell(r, "|cffff6060GuildOS|r  v" .. tostring(u.v), 215, 200)
                    cell(r, u.online and (GREEN .. "online|r") or (GREY .. "offline|r"), 430, 70)
                    y = y + 24
                end
            end
        end
        y = y + 8
        memberList("ON OUTLAWOS  ·  " .. #onOutlaw, onOutlaw, onOpen, function()
            onOpen = not onOpen
            refresh()
        end)
        memberList("NO ADDON DATA  ·  " .. #noAddon, noAddon, noOpen, function()
            noOpen = not noOpen
            refresh()
        end)

        -- Anniversaries
        -- Milestones grouped by tier: a heading with a count, then the first few names and "and N more".
        local function annSection(title, list, emptyText, showShout)
            sectionAt(child, title, y); y = y + 26
            if #list == 0 then txt(child, emptyText, 0, y, width, 12, C.textSoft); y = y + 22; return end
            local byDays, order = {}, {}
            for _, a in ipairs(list) do
                if not byDays[a.days] then byDays[a.days] = {}; order[#order + 1] = a.days end
                table.insert(byDays[a.days], a)
            end
            table.sort(order)
            for _, d in ipairs(order) do
                local g = byDays[d]
                txt(child, GOLDC .. annText(d) .. "|r  ·  " .. #g .. " member" .. (#g == 1 and "" or "s"), 0, y, width, 12, C.text)
                y = y + 18
                for i = 1, math.min(5, #g) do
                    local a = g[i]
                    local r = newRow(child, y, i, 24)
                    cell(r, a.name, 8, 220)
                    cell(r, date("%b %d", a.at), 240, 80, C.textSoft.r, C.textSoft.g, C.textSoft.b)
                    if showShout then
                        local s = btn(r, "Shout out", 80, function()
                            ChatFrame_OpenChat(string.format("/g Happy Ledger anniversary %s! %s with the Outlaws. Free by choice, bound by bond!", a.name, annText(a.days)))
                        end)
                        s:SetPoint("RIGHT", -8, 0)
                    end
                    y = y + 26
                end
                if #g > 5 then txt(child, string.format("... and %d more.", #g - 5), 0, y, width, 11, C.textSoft); y = y + 18 end
                y = y + 6
            end
        end
        annSection("LEDGER ANNIVERSARIES  ·  last 7 days", EKO:Anniversaries(), "No anniversaries this week.", true)
        annSection("COMING UP  ·  next 14 days", EKO:UpcomingAnniversaries(14), "Nobody reaches a milestone in the next 14 days.", false)

        -- Quote the Code
        y = y + 12
        local qh = sectionAt(child, "QUOTE THE CODE", y)
        local qbox = input(qh, 200, "Member to whisper")
        qbox:SetPoint("TOPRIGHT", 0, 4)
        y = y + 28
        for i, rule in ipairs(EKO.CODE_RULES) do
            local r = newRow(child, y, i, 24)
            cell(r, rule.text, 8, math.max(150, width - 110), C.textSoft.r, C.textSoft.g, C.textSoft.b)
            local w = btn(r, "Whisper", 80, function()
                local who = strtrim(qbox:GetText() or "")
                if who == "" then GuildOS:Print("Type who to whisper in the box above.") return end
                if SendChatMessage then SendChatMessage(rule.text, "WHISPER", nil, who) end
            end)
            w:SetPoint("RIGHT", -8, 0)
            y = y + 26
        end

        -- Strikes
        y = y + 12
        sectionAt(child, "STRIKES  ·  officers only", y); y = y + 26
        if not officer then
            txt(child, "Officers only.", 0, y, width, 12, C.textSoft); y = y + 22
        else
            local srow = CreateFrame("Frame", nil, child)
            srow:SetHeight(24); srow:SetPoint("TOPLEFT", 0, -y); srow:SetPoint("TOPRIGHT", 0, -y)
            local nbox = input(srow, 170, "Member")
            nbox:SetPoint("LEFT", 0, 0)
            local rbox = input(srow, math.max(150, width - 170 - 3 * 130 - 30), "Reason")
            rbox:SetPoint("LEFT", nbox, "RIGHT", 6, 0)
            local prev = rbox
            for li, lvl in ipairs(EKO.STRIKE_LEVELS) do
                local b = btn(srow, lvl, 124, function() EKO:AddStrike(nbox:GetText(), li, rbox:GetText()) end)
                b:SetPoint("LEFT", prev, "RIGHT", 6, 0)
                prev = b
            end
            y = y + 32
            local names = {}
            for n in pairs(EKO:Strikes()) do names[#names + 1] = n end
            table.sort(names)
            if #names == 0 then txt(child, "No strikes on record.", 0, y, width, 12, C.textSoft); y = y + 22 end
            local i = 0
            for _, n in ipairs(names) do
                for si, s in ipairs(EKO:Strikes()[n]) do
                    i = i + 1
                    local r = newRow(child, y, i, 24)
                    cell(r, si == 1 and n or "", 8, 170)
                    local col = s.level >= 3 and "|cffff6060" or s.level == 2 and "|cffffd060" or GREY
                    cell(r, col .. (EKO.STRIKE_LEVELS[s.level] or "?") .. "|r", 185, 130)
                    cell(r, s.reason ~= "" and s.reason or GREY .. "(no reason)|r", 320, math.max(100, width - 560))
                    cell(r, (s.by or "?") .. ", " .. date("%b %d", s.at or 0), math.max(330, width - 230), 150, C.textSoft.r, C.textSoft.g, C.textSoft.b)
                    local x = btn(r, "X", 26, function() EKO:RemoveStrike(n, si) end)
                    x:SetPoint("RIGHT", -8, 0)
                    y = y + 26
                end
            end
            txt(child, "Strikes sync to officers with OutlawOS only. Members never receive them.", 0, y + 4, width, 10, C.textSoft)
            y = y + 26
        end

        -- Recruit ads
        y = y + 12
        sectionAt(child, "RECRUIT ADS  ·  rotate them so they don't look copy-pasted", y); y = y + 26
        for i, ad in ipairs(EKO.RECRUIT_ADS) do
            local r = newRow(child, y, i, 1)
            local t = txt(r, ad, 8, 5, math.max(150, width - 230), 11, C.textSoft)
            local h2 = math.max(28, (t:GetStringHeight() or 14) + 10)
            r:SetHeight(h2)
            local use = btn(r, "Use in OutlawOS", 110, function()
                local info = GuildOS.db and GuildOS.db.guildRecruitment
                if type(info) == "table" then info.message = ad; GuildOS:Print("EKO: OutlawOS recruit message updated.") else GuildOS:Print("Set up Recruitment once first.") end
            end)
            use:SetPoint("RIGHT", -8, 0)
            local chat = btn(r, "To chat box", 96, function() ChatFrame_OpenChat(ad) end)
            chat:SetPoint("RIGHT", use, "LEFT", -6, 0)
            y = y + h2 + 2
        end
        child:SetHeight(y + 20)
    end
    refreshers.desk = function() if panel:IsVisible() then refresh() end end
    return refresh
end

-- /eko sound: the login sound on or off.
EKO.extraSlash = function(cmd, rest)
    if cmd == "theme" then
        local arg = strtrim(rest or ""):lower()
        local on = arg == "on" or (arg == "" and not EKO.themeOn)
        if arg == "off" then on = false end
        GuildOSDB.ekoThemeOff = not on
        EKO:ApplyTheme(on)
        EKO:ApplyFonts(on)
        GuildOS:Print("EKO: Leather & Parchment theme " .. (on and "on" or "off") .. ". Type /reload to repaint every window.")
        return true
    end
    if cmd == "banner" then
        local db = EKO:DB()
        if (rest or ""):lower():match("test") then EKO:ShowBanner() return true end
        db.noBanner = not db.noBanner
        GuildOS:Print("EKO: login banner " .. (db.noBanner and "off" or "on") .. ". /eko banner test shows it now.")
        return true
    end
    if cmd == "who" then
        EKO:CheckPatch()
        C_Timer.After(8, function()
            local names = {}
            for _, u in ipairs(EKO:PatchUsers()) do if u.online then names[#names + 1] = u.name end end
            GuildOS:Print(string.format("EKO: %d online with OutlawOS: %s", #names, table.concat(names, ", ")))
        end)
        return true
    end
    if cmd == "sound" then
        local db = EKO:DB()
        db.noSound = not db.noSound
        GuildOS:Print("EKO: login sound " .. (db.noSound and "off" or "on") .. ".")
        return true
    end
    return false
end

-- Bounty Board clears this week, from the journal. Each OutlawOS client logs its own clear, and the journal
-- syncs every member's clears to the guild, so every client counts the same list. A clear counts when the
-- dungeon was on this week's board and three or more Outlaws were in the party, as the sheet's rules say.
function EKO:WeekBountyRuns()
    return self:Runs(self:WeekStart(), function(e)
        return e.data.onBoard and (e.data.outlaws or 0) >= 3
    end)
end

-- This week's clears, in the shape BountyClaims reads: { d = dungeon, tier, who = { names } }.
function EKO:VerifiedClears()
    local tierOf = {}
    for _, bnt in ipairs(self:ParseBounties((self:Bounties() or {}).text or "")) do tierOf[nameKey(bnt.name)] = bnt.tier end
    local out = {}
    for _, r in ipairs(self:WeekBountyRuns()) do
        out[#out + 1] = { d = r.name, tier = tierOf[nameKey(r.name)], who = r.who }
    end
    for _, m in ipairs(self:ManualClears()) do
        out[#out + 1] = { d = m.d, tier = tierOf[nameKey(m.d)], who = m.who }
    end
    return out
end

-- Clears an officer pasted from the Bounty Board sheet's Clears tab this week, for clears the journal
-- missed (the posters read these with the journal's). Only a clear with three or more Outlaws counts.
function EKO:ManualClears()
    local out = {}
    local s = shared("bountyclears")
    if type(s) == "table" and s.week == self:WeekStart() then
        for _, g in ipairs(self:ParseClears(s.text or "")) do
            if #g.who >= 3 then out[#out + 1] = g end
        end
    end
    for dungeon, list in pairs(formClears()) do
        for _, c in ipairs(list) do
            if #c.names >= 3 then out[#out + 1] = { d = dungeon, who = c.names } end
        end
    end
    return out
end

-- Rows copied from the Clears tab (Date, Week, Clear #, Outlaw, Dungeon, ...): one group per Clear #
-- and dungeon, of the newest week in the paste. The header row and anything else is skipped.
-- Dungeons the Clears tab uses. A pasted row that lost its tabs is split on these names.
local CLEAR_DUNGEON_NAMES = {
    "Hall of Thanes", "Deadmines", "Excavation Site", "Shadowfang Keep", "Drowned City", "Scarlet Monastery",
    "Ragefire Chasm", "Ruins of Lordaeron", "Blackfathom Deeps", "Dalaran", "Uldaman", "Krol'dok Stronghold",
}

-- One row of the Clears tab as { week, clear, who, d }, or nil. A row with tabs (a copy from the sheet) is
-- read by column. A row whose tabs were lost is read from its start: date (optional), week, Clear #, the
-- Outlaw's name, then the dungeon, which is the first of CLEAR_DUNGEON_NAMES found after the name.
local function clearRow(line)
    if line:find("\t") then
        local f = {}
        for part in (line .. "\t"):gmatch("([^\t]*)\t") do f[#f + 1] = (part:match("^%s*(.-)%s*$")) end
        local week = tonumber(f[2]) or tonumber((f[2] or ""):match("(%d+)"))
        local clear, who, dungeon = f[3], f[4], f[5]
        if week and clear and clear ~= "" and who and who ~= "" and dungeon and dungeon ~= "" then
            return { week = week, clear = clear, who = who, d = dungeon }
        end
        return nil
    end
    local rest = line:gsub("^%s*%d%d%d%d%-%d%d%-%d%d%s+", "")
    local week, clear, tail = rest:match("^%s*(%d+)%s+(%d+)%s+(.-)%s*$")
    if not week or not tail then return nil end
    local at, found
    for _, name in ipairs(CLEAR_DUNGEON_NAMES) do
        local s = tail:find(name, 1, true)
        if s and (not at or s < at) then at, found = s, name end
    end
    if not at then return nil end
    local who = tail:sub(1, at - 1):match("^%s*(.-)%s*$")
    if who == "" then return nil end
    return { week = tonumber(week), clear = clear, who = who, d = found }
end

-- Clears pasted from the Bounty Board sheet's Clears tab: one group per Clear # and dungeon, of the newest
-- week in the paste. The header row and anything else is skipped.
function EKO:ParseClears(text)
    local rows, bestWeek = {}, nil
    for raw in (tostring(text or ""):gsub("|", "") .. "\n"):gmatch("([^\n]*)\n") do
        local r = clearRow((raw:gsub("\r", "")))
        if r then
            rows[#rows + 1] = r
            if not bestWeek or r.week > bestWeek then bestWeek = r.week end
        end
    end
    local groups, order = {}, {}
    for _, r in ipairs(rows) do
        if r.week == bestWeek then
            local key = r.clear .. "|" .. r.d
            if not groups[key] then
                groups[key] = { d = r.d, who = {} }
                order[#order + 1] = key
            end
            local g = groups[key]
            local seen = false
            for _, n in ipairs(g.who) do if n == r.who then seen = true end end
            if not seen then g.who[#g.who + 1] = r.who end
        end
    end
    local out = {}
    for _, k in ipairs(order) do out[#out + 1] = groups[k] end
    return out
end

-- The verified clears of one bounty (names match either way round: "The Deadmines" / "Deadmines").
function EKO:BountyClaims(bountyName)
    local key = tostring(bountyName or ""):lower():gsub("^the ", "")
    local out = {}
    for _, c in ipairs(self:VerifiedClears()) do
        local d = c.d:lower():gsub("^the ", "")
        if d == key or d:find(key, 1, true) or key:find(d, 1, true) then out[#out + 1] = c end
    end
    return out
end

-- Each Outlaw's clears this week: one raffle entry a clear, and bounty points (1 a clear, 2 with a full party of 5).
function EKO:WeekTickets()
    local byName, seen = {}, {}
    local weekStart = self:WeekStart()
    for _, e in ipairs(GuildOS.db and GuildOS.db.journal and GuildOS.db.journal.entries or {}) do
        local d = e.data
        if e.type == "dungeon.clear" and type(d) == "table" and d.onBoard and (d.outlaws or 0) >= 3
            and (e.at or 0) >= weekStart and e.id and not seen[e.id] then
            seen[e.id] = true
            local s = short(e.subjectKey)
            if s then
                local t = byName[s] or { n = 0, pts = 0 }
                byName[s] = t
                t.n = t.n + 1
                t.pts = t.pts + ((d.outlaws >= 5) and 2 or 1)
            end
        end
    end
    return byName
end

-- The raffle entries counted from this week's clears, one "Name n" line each, most entries first.
function EKO:CountedRaffleText()
    local list = {}
    for name, t in pairs(self:WeekTickets()) do list[#list + 1] = { name = name, n = t.n } end
    table.sort(list, function(x, y) if x.n ~= y.n then return x.n > y.n end return x.name < y.name end)
    local lines = {}
    for _, e in ipairs(list) do lines[#lines + 1] = e.name .. " " .. e.n end
    return table.concat(lines, "\n")
end

----------------------------------------------------------------------
-- Who has OutlawOS: every client with the patch says hello at login and answers a check (domain
-- "ekowho", guild only). Kept in db.eko.patchUsers[name] = { v, at }.
----------------------------------------------------------------------
EKO.PATCH_VERSION = GuildOS.VERSION or "?"   -- the CurseForge version each client checks in with
-- A check-in this many days old or less counts as OutlawOS in the install check.
EKO.PATCH_RECENT_DAYS = 14
-- This release's notes, sent with each check-in so a guildmate on an older version can read them (Data/Changelog.lua).
EKO.NOTES_MAX = 1500
EKO.RELEASE_NOTES_TEXT = ((GuildOS.RELEASE_NOTES and GuildOS.RELEASE_NOTES.text) or ""):sub(1, EKO.NOTES_MAX)

local function rememberPatch(name, v, notes)
    local db = EKO:DB()
    if not db or not name then return end
    db.patchUsers = db.patchUsers or {}
    local rec = { v = v or "?", at = now() }
    if type(notes) == "string" and notes ~= "" then rec.n = notes:sub(1, EKO.NOTES_MAX) end
    db.patchUsers[short(name)] = rec
end

function EKO:SayHello(act)
    rememberPatch(meName(), self.PATCH_VERSION, self.RELEASE_NOTES_TEXT)
    if GuildOS.SyncService then
        GuildOS.SyncService:Publish("ekowho", act or "hello", { v = self.PATCH_VERSION, n = self.RELEASE_NOTES_TEXT }, { priority = "BULK" })
    end
end

-- Hand on who this client has heard from in the last PATCH_RECENT_DAYS days, so every client's With OutlawOS
-- count converges instead of depending on who was online for which check-in. Sent in chunks of 50 names
-- as "name=hours ago" (domain "ekolist", guild only). A receiver keeps the newer check-in per name and
-- never moves a check-in later than the time it was heard.
function EKO:ShareList()
    if not GuildOS.SyncService then return end
    if self._listSentAt and now() - self._listSentAt < 600 then return end   -- once per ten minutes
    self._listSentAt = now()
    local db = self:DB()
    local recent = now() - EKO.PATCH_RECENT_DAYS * DAY
    local items = {}
    for name, rec in pairs(db and db.patchUsers or {}) do
        if rec.at and rec.at >= recent and short(name) ~= short(meName()) then
            items[#items + 1] = string.format("%s=%d|%s", short(name), math.floor((now() - rec.at) / 3600), tostring(rec.v or "?"))
        end
    end
    table.sort(items)
    local i = 1
    while i <= #items and i <= 300 do
        local chunk = {}
        for j = i, math.min(i + 49, #items) do chunk[#chunk + 1] = items[j] end
        GuildOS.SyncService:Publish("ekolist", "list", { u = table.concat(chunk, ",") }, { priority = "BULK" })
        i = i + 50
    end
end

function EKO:CheckPatch()
    self._checkAt = GetTime and GetTime() or 0
    self:SayHello("ping")
    GuildOS:Print("EKO: asked everyone online with OutlawOS to check in. The list fills over the next few seconds.")
    C_Timer.After(8, function() if refreshers.desk then GuildOS:SafeCall(refreshers.desk) end end)
end

if GuildOS.SyncService then
    GuildOS.SyncService.GUILD_ONLY_DOMAINS.ekowho = true
    GuildOS.SyncService:On("ekowho", function(env, sender)
        local d = env and env.data
        if type(d) ~= "table" then return end
        rememberPatch(sender, d.v, d.n)
        -- A check: answer after a short random wait so twenty clients don't answer in the same second.
        if env.act == "ping" and short(sender) ~= short(meName()) then
            C_Timer.After(1 + math.random() * 4, function() GuildOS:SafeCall(function() EKO:SayHello("hello") end) end)
            C_Timer.After(10 + math.random() * 20, function() GuildOS:SafeCall(function() EKO:ShareList() end) end)
        end
        if refreshers.desk then GuildOS:SafeCall(refreshers.desk) end
    end)
end

if GuildOS.SyncService then
    GuildOS.SyncService.GUILD_ONLY_DOMAINS.ekolist = true
    GuildOS.SyncService:On("ekolist", function(env, sender)
        local d = env and env.data
        if type(d) ~= "table" or type(d.u) ~= "string" then return end
        local db = EKO:DB()
        if not db then return end
        db.patchUsers = db.patchUsers or {}
        local recent = now() - EKO.PATCH_RECENT_DAYS * DAY
        for entry in d.u:gmatch("[^,]+") do
            local name, hrs, ver = entry:match("^([^=|]+)=(%d+)|?(.*)$")
            hrs = tonumber(hrs)
            if name and hrs and hrs >= 0 then
                local at = now() - hrs * 3600
                local rec = db.patchUsers[short(name)]
                if at >= recent and (not rec or (rec.at or 0) < at) then
                    db.patchUsers[short(name)] = { v = (ver ~= "" and ver) or (rec and rec.v) or "?", at = at, n = rec and rec.n }
                end
            end
        end
        if refreshers.desk then GuildOS:SafeCall(refreshers.desk) end
    end)
end

local whoEv = CreateFrame("Frame")
whoEv:RegisterEvent("PLAYER_LOGIN")
whoEv:SetScript("OnEvent", function()
    C_Timer.After(20 + math.random() * 10, function() GuildOS:SafeCall(function() EKO:SayHello("hello") end) end)
    C_Timer.After(60 + math.random() * 20, function() GuildOS:SafeCall(function() EKO:ShareList() end) end)
end)

-- The list for the Outlaw Desk: { name, v, at, online, rank }, online first.
-- Members of the guild who checked in with OutlawOS in the last EKO.PATCH_RECENT_DAYS days: the Install
-- check's "On OutlawOS" count, which the Roster's With OutlawOS card shows.
function EKO:OnOutlawCount()
    local recent = now() - EKO.PATCH_RECENT_DAYS * DAY
    local n = 0
    for _, u in ipairs(self:PatchUsers()) do
        if u.at and u.at >= recent and u.m then n = n + 1 end
    end
    return n
end

function EKO:PatchUsers()
    local db = self:DB()
    local roster = self:Roster()
    local out = {}
    for name, rec in pairs(db and db.patchUsers or {}) do
        local m = roster[name]
        out[#out + 1] = { name = name, v = rec.v, at = rec.at, n = rec.n, online = m and m.online, rank = m and m.rank, m = m }
    end
    table.sort(out, function(a, b)
        if (a.online and 1 or 0) ~= (b.online and 1 or 0) then return a.online end
        return (a.at or 0) > (b.at or 0)
    end)
    return out
end

-- The OutlawOS version a member last checked in with, when that check-in is recent. nil when there is none,
-- so the roster tooltip can say OutlawOS is not installed.
function EKO:OutlawVersionFor(name)
    local db = self:DB()
    local rec = db and db.patchUsers and db.patchUsers[short(name)]
    if not rec or not rec.at or rec.at < now() - EKO.PATCH_RECENT_DAYS * DAY then return nil end
    return rec.v
end

-- OutlawOS versions compare as major.minor.patch with a short major (1.38.0). A date-style string an
-- old build sent (2026.11.21) has a four-digit first part: it is not compared, so it never counts as newer.
local function parseVersion(v)
    local a, b, c = tostring(v or ""):match("^(%d%d?%d?)%.(%d+)%.(%d+)$")
    if not a then return nil end
    return tonumber(a) * 1000000 + tonumber(b) * 1000 + tonumber(c)
end

-- The newest OutlawOS version a guildmate has checked in with, when it is newer than this one: that
-- version and its notes. nil when this one is current or no newer check-in is on record.
function EKO:NewerRelease()
    local mine = parseVersion(self.PATCH_VERSION)
    if not mine then return nil end
    local best
    for _, rec in ipairs(self:PatchUsers()) do
        local theirs = parseVersion(rec.v)
        if theirs and theirs > mine and (not best or theirs > best.num) then
            best = { num = theirs, v = rec.v, n = rec.n }
        end
    end
    if not best then return nil end
    return best.v, best.n or ""
end

----------------------------------------------------------------------
-- One-time: the joins logged before inviters were recorded (Nov 21) were all Victoria's invites,
-- except Khar Grimmfang (Skadi Miniheals). Only on Victoria's client, once, nothing broadcast: the
-- next login's audit backfill carries the most recent ones to the other officers.
----------------------------------------------------------------------
EKO.INVITER_FILL = { default = "Vyctoria Windwhisper", only = { ["Khar Grimmfang"] = "Skadi Miniheals" } }

function EKO:FillInviters()
    local db = self:DB()
    if not db or db.invitersFilled then return end
    if short(GuildOS.Compat and GuildOS.Compat.PlayerName() or UnitName("player")) ~= self.INVITER_FILL.default then return end
    local ev = GuildOS.db.rosterLog and GuildOS.db.rosterLog.events
    if not ev then return end
    local n = 0
    for _, e in ipairs(ev) do
        if e.action == "join" and not e.author then
            e.author = self.INVITER_FILL.only[e.target] or self.INVITER_FILL.default
            n = n + 1
        end
    end
    db.invitersFilled = now()
    if GuildOS.RosterLog and GuildOS.RosterLog.Refresh then GuildOS.RosterLog:Refresh() end
    GuildOS:Print(string.format("EKO: filled in the inviter on %d logged join(s).", n))
end

-- One-time, Nov 21 evening: four joins Victoria invited before invite tracking caught /ginvite.
EKO.INVITER_FILL2 = { ["Sir Zynbabwe"] = true, ["Invictus Dawnwalker"] = true, ["Vanha Nainen"] = true, ["My Log"] = true }
function EKO:FillInviters2()
    local db = self:DB()
    if not db or db.invitersFilled2 then return end
    if short(GuildOS.Compat and GuildOS.Compat.PlayerName() or UnitName("player")) ~= self.INVITER_FILL.default then return end
    local ev = GuildOS.db.rosterLog and GuildOS.db.rosterLog.events
    if not ev then return end
    local n = 0
    for _, e in ipairs(ev) do
        if e.action == "join" and not e.author and self.INVITER_FILL2[e.target] then
            e.author = self.INVITER_FILL.default
            n = n + 1
        end
    end
    db.invitersFilled2 = now()
    if n > 0 and GuildOS.RosterLog and GuildOS.RosterLog.Refresh then GuildOS.RosterLog:Refresh() end
end

local fillEv = CreateFrame("Frame")
fillEv:RegisterEvent("PLAYER_LOGIN")
fillEv:SetScript("OnEvent", function()
    C_Timer.After(12, function()
        GuildOS:SafeCall(function() EKO:FillInviters() end)
        GuildOS:SafeCall(function() EKO:FillInviters2() end)
    end)
end)

----------------------------------------------------------------------
-- Login: the Matriarch greeting and the trial reminder
----------------------------------------------------------------------
local ev = CreateFrame("Frame")
ev:RegisterEvent("PLAYER_LOGIN")
ev:SetScript("OnEvent", function()
    C_Timer.After(8, function()
        local ok = pcall(function()
            if not IsInGuild or not IsInGuild() then return end
            local _, _, rankIndex = GetGuildInfo("player")
            if rankIndex == 0 then
                GuildOS:Print("|cffE8C266Welcome back, Matriarch.|r")
            end
            local t = now()
            if t >= EKO.TRIAL_END - 3 * DAY and t <= EKO.TRIAL_END + 7 * DAY then
                local db = EKO:DB()
                local open = 0
                for _, l in ipairs(EKO.LEADERS) do
                    local st = db and db.circle[l.name]
                    if not (st and st.result) then open = open + 1 end
                end
                if open > 0 then
                    if t <= EKO.TRIAL_END then
                        GuildOS:Print(string.format("|cffE8C266Leadership trials end Dec 7: %d days left.|r %d leader(s) to confirm in Leadership > Inner Circle.",
                            math.max(0, math.ceil((EKO.TRIAL_END - t) / DAY)), open))
                    else
                        GuildOS:Print(string.format("|cffE8C266Leadership trials are over.|r %d leader(s) still to confirm in Leadership > Inner Circle.", open))
                    end
                end
            end
        end)
    end)
end)

----------------------------------------------------------------------
-- Alter Egos never need a trial: once someone is on the Alter Ego rank, their open trial is closed
-- (marked approved) on this client. Checked on roster updates, at most every 30 seconds. Nothing is
-- broadcast (a whole-list sync disconnected the client): other officers get it with the next sync.
----------------------------------------------------------------------
function EKO:CloseAlterEgoTrials()
    if not (GuildOS.db and GuildOS.db.trials and GuildOS:IsOfficer()) then return 0 end
    local roster = self:Roster()
    local n = 0
    local by = (GuildOS.Compat and GuildOS.Compat.PlayerName()) or UnitName("player")
    for key, t in pairs(GuildOS.db.trials) do
        if type(t) == "table" and t.status == "trial" then
            local m = roster[short(key)]
            if m and m.rank == "Alter Ego" then
                t.status = "approved"
                t.resolvedDate = now()
                t.resolvedBy = by
                n = n + 1
            end
        end
    end
    if n > 0 then
        local TT = GuildOS.TrialTracker
        if TT and TT.RefreshUI then GuildOS:SafeCall(function() TT:RefreshUI() end) end
        GuildOS:Print(string.format("EKO: closed %d trial(s) for Alter Egos.", n))
    end
    return n
end

local aeLast = 0
local aeFrame = CreateFrame("Frame")
aeFrame:RegisterEvent("GUILD_ROSTER_UPDATE")
aeFrame:SetScript("OnEvent", function()
    local t = GetTime and GetTime() or 0
    if t - aeLast < 30 then return end
    aeLast = t
    GuildOS:SafeCall(function() EKO:CloseAlterEgoTrials() end)
    GuildOS:SafeCall(function() if EKO.WeekLevels then EKO:WeekLevels() end end)
end)

----------------------------------------------------------------------
-- /eko
----------------------------------------------------------------------
SLASH_GUILDOSEKO1 = "/eko"
SlashCmdList["GUILDOSEKO"] = function(msg)
    msg = strtrim(msg or "")
    local cmd, rest = msg:match("^(%S*)%s*(.*)$")
    cmd = (cmd or ""):lower()
    local db = EKO:DB()
    if not db then GuildOS:Print("EKO: not loaded yet.") return end
    if cmd == "goal" then
        local gold, name = rest:match("^(%d+)%s*(.*)$")
        if not gold then
            GuildOS:Print(string.format("EKO goal: %dg, %s. Change it with /eko goal <gold> <name>, e.g. /eko goal 250 Raid consumables", db.goal.gold, db.goal.name))
            return
        end
        db.goal.gold = tonumber(gold)
        if name and name ~= "" then db.goal.name = name end
        GuildOS:Print(string.format("EKO goal set: %dg, %s.", db.goal.gold, db.goal.name))
    elseif cmd == "ready" then
        local d, l, o = rest:match("^(%d+)%s+(%d+)%s+(%d+)")
        if d then
            db.ready.minDays, db.ready.minLevels, db.ready.onlineDays = tonumber(d), tonumber(l), tonumber(o)
        end
        GuildOS:Print(string.format("Ready for Outlaw rules: %d+ days, %d+ levels, online in %d days. Change with /eko ready <days> <levels> <online days>.",
            db.ready.minDays, db.ready.minLevels, db.ready.onlineDays))
    elseif cmd == "trials" then
        -- Approve the open trials of everyone already promoted past Recruit (Alter Egos too with "all").
        local TT = GuildOS.TrialTracker
        if not (TT and GuildOS:IsOfficer()) then GuildOS:Print("EKO: only officers can resolve trials.") return end
        local withAlts = rest:lower():match("^all") ~= nil
        local roster = EKO:Roster()
        local approved, names = 0, {}
        for key, t in pairs(GuildOS.db.trials or {}) do
            if type(t) == "table" and t.status == "trial" then
                local m = roster[short(key)]
                if m and m.rank and m.rank ~= "Recruit" and (withAlts or m.rank ~= "Alter Ego") then
                    t.status = (TT.STATUS and TT.STATUS.APPROVED) or "approved"
                    t.resolvedDate = now()
                    t.resolvedBy = GuildOS.Compat and GuildOS.Compat.PlayerName() or UnitName("player")
                    approved = approved + 1
                    if #names < 40 then names[#names + 1] = m.name end
                end
            end
        end
        if approved > 0 then
            -- No sync broadcast here: sending the whole trial list at once disconnected the client
            -- (Nov 21). The approvals reach other officers with the next normal trial sync.
            if TT.RefreshUI then GuildOS:SafeCall(function() TT:RefreshUI() end) end
        end
        GuildOS:Print(string.format("EKO: approved %d trial(s) for members already past Recruit%s.", approved, withAlts and " (Alter Egos included)" or ""))
        if approved > 0 then GuildOS:Print(table.concat(names, ", ") .. (approved > #names and " ..." or "")) end
        if not withAlts then GuildOS:Print("Type /eko trials all to also clear the Alter Egos' trials.") end
    elseif cmd == "circle" then
        GuildOS:Print(string.format("Leadership trials: day %d of 14, ending Dec 7.", EKO:TrialDay()))
    elseif EKO.extraSlash and EKO.extraSlash(cmd, rest) then
        -- handled (/eko sound)
    else
        GuildOS:Print("EKO: /eko goal <gold> <name> · /eko ready <days> <levels> <online days> · /eko trials [all] · /eko circle")
    end
end
