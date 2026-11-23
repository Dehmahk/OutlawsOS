----------------------------------------------------------------------
-- OutlawOS - My Char: the main spec and the offspec of every character.
--
-- The spec list, role colours, role icons and the tab itself come from GuildOS_Unbroken by
-- Christian (the "My Char" tab), used with his permission. The sync, the roster marks, the
-- officer views and the rest of this tab are OutlawOS's own.
--
-- Each character says which of its class's talent trees it plays (main) and which it would
-- play when needed (offspec). The guild sees it on the roster tooltip. A record is written
-- only by the character it belongs to; it syncs on the "myspec" domain (guild only) and is
-- kept in GuildOS.db.specs, one per character. Copies to alts are drafts in
-- GuildOS.db.specDrafts: they are offered when that alt is next logged in, because a
-- character can only write its own record.
----------------------------------------------------------------------
local L = GuildOS.L
local C = GuildOS.Colors
local UI = GuildOS.UI

local DAY = 86400
local NUDGE_AFTER = 30 * DAY    -- a confirmed spec is asked about again after this long
local HISTORY_MAX = 5           -- changes kept per character
local MAX_ALTS = 4              -- alts per member, the main not counted
local FERAL_BEAR_FORM = 5       -- shapeshift form id of Bear Form

local MySpecs = {}
GuildOS.MySpecs = MySpecs

-- per class: key, English, German, role (T tank, H healer, D damage)
local LIST = {
  WARRIOR = { { "arms", "Arms", "Waffen", "D" }, { "fury", "Fury", "Furor", "D" },
              { "protw", "Protection", "Schutz", "T" } },
  PALADIN = { { "holypa", "Holy", "Heilig", "H" }, { "protpa", "Protection", "Schutz", "T" },
              { "ret", "Retribution", "Vergeltung", "D" } },
  HUNTER  = { { "bm", "Beast Mastery", "Tierherrschaft", "D" }, { "mm", "Marksmanship", "Treffsicherheit", "D" },
              { "surv", "Survival", "Überleben", "D" } },
  ROGUE   = { { "assa", "Assassination", "Meucheln", "D" }, { "combat", "Combat", "Kampf", "D" },
              { "sub", "Subtlety", "Täuschung", "D" } },
  PRIEST  = { { "disc", "Discipline", "Disziplin", "H" }, { "holypr", "Holy", "Heilig", "H" },
              { "shadow", "Shadow", "Schatten", "D" } },
  SHAMAN  = { { "ele", "Elemental", "Elementar", "D" }, { "enh", "Enhancement", "Verstärkung", "D" },
              { "restosh", "Restoration", "Wiederherstellung", "H" } },
  MAGE    = { { "arcane", "Arcane", "Arkan", "D" }, { "fire", "Fire", "Feuer", "D" },
              { "frost", "Frost", "Frost", "D" } },
  WARLOCK = { { "affli", "Affliction", "Gebrechen", "D" }, { "demo", "Demonology", "Dämonologie", "D" },
              { "destro", "Destruction", "Zerstörung", "D" } },
  DRUID   = { { "balance", "Balance", "Gleichgewicht", "D" }, { "bear", "Feral (Tank)", "Wilder Kampf (Tank)", "T" },
              { "cat", "Feral (Damage)", "Wilder Kampf (Schaden)", "D" }, { "restodr", "Restoration", "Wiederherstellung", "H" } },
}

local de = GetLocale() == "deDE"
local SPECS, CLASS_SPECS = {}, {}     -- key -> spec; class -> { spec, ... } in list order
for class, list in pairs(LIST) do
  CLASS_SPECS[class] = {}
  for _, s in ipairs(list) do
    local e = { key = s[1], en = s[2], de = s[3], name = de and s[3] or s[2], role = s[4], class = class }
    SPECS[e.key] = e
    table.insert(CLASS_SPECS[class], e)
  end
end
MySpecs.SPECS = SPECS
MySpecs.CLASS_SPECS = CLASS_SPECS

-- Druid Feral is one talent tree played in two forms: the button says which form it is.
local FORM_LABEL = {
  bear = { en = "Feral bear form", de = "Wilde Bärenform" },
  cat  = { en = "Feral cat form", de = "Wilde Katzenform" },
}
local function labelOf(e)
  local f = FORM_LABEL[e.key]
  if f then return de and f.de or f.en end
  return e.name
end

-- tank blue, healer green, damage red
local ROLE_RGB = { T = { 0.25, 0.55, 1.00 }, H = { 0.25, 0.90, 0.25 }, D = { 1.00, 0.27, 0.27 } }
local ROLE_WORD = { T = "Tank", H = "Healer", D = "Damage" }
local ROLE_TIP = {
  T = "Holds the enemies' attention and takes the hits.",
  H = "Keeps the group alive with healing.",
  D = "Deals the damage.",
}
-- ability icons every client has: shield, holy light, two blades
local ROLE_ICON = {
  T = "Interface\\Icons\\Ability_Defend",
  H = "Interface\\Icons\\Spell_Holy_FlashHeal",
  D = "Interface\\Icons\\Ability_DualWield",
}
local QUESTION_ICON = "Interface\\Icons\\INV_Misc_QuestionMark"

local function roleName(role) return L[ROLE_WORD[role] or "Damage"] end

local function roleIcon(role, size)
  local path = ROLE_ICON[role]
  if not path then return "" end
  size = size or 14
  return ("|T%s:%d:%d:0:0:64:64:5:59:5:59|t"):format(path, size, size)
end

local function roleHex(role)
  local c = ROLE_RGB[role] or ROLE_RGB.D
  return ("ff%02x%02x%02x"):format(math.floor(c[1] * 255 + 0.5), math.floor(c[2] * 255 + 0.5), math.floor(c[3] * 255 + 0.5))
end

-- "[icon] Protection (Tank)" in the role's colour
local function specText(key, size)
  local s = key and SPECS[key]
  if not s then return nil end
  return roleIcon(s.role, size) .. " |c" .. roleHex(s.role) .. labelOf(s) .. " (" .. roleName(s.role) .. ")|r"
end
MySpecs.SpecText = specText

-- plain text for chat lines
local function plain(key)
  local s = key and SPECS[key]
  if not s then return "?" end
  return labelOf(s) .. " (" .. roleName(s.role) .. ")"
end

local function classWord(class)
  return (LOCALIZED_CLASS_NAMES_MALE and LOCALIZED_CLASS_NAMES_MALE[class]) or class
end

----------------------------------------------------------------------
-- Records and the character
----------------------------------------------------------------------
local function short(name)
  if type(name) ~= "string" then return nil end
  return name:match("^([^-]+)") or name
end

local function Me() return UnitName("player") end
local function Now() return GetServerTime and GetServerTime() or time() end
local function isOfficer() return GuildOS.IsOfficer and GuildOS:IsOfficer() and true or false end

local function Store()
  if not GuildOS.db then return nil end
  GuildOS.db.specs = GuildOS.db.specs or {}
  return GuildOS.db.specs
end

local function Drafts()
  if not GuildOS.db then return nil end
  GuildOS.db.specDrafts = GuildOS.db.specDrafts or {}
  return GuildOS.db.specDrafts
end

local function RecordOf(name)
  local st = Store()
  return st and st[short(name)] or nil
end

local function MyClass()
  local _, class = UnitClass("player")
  return class
end

-- The guild roster, read once: { [short] = { class, online } } and its size.
local function Roster()
  local out, n = {}, GetNumGuildMembers and GetNumGuildMembers() or 0
  for i = 1, n do
    local name, _, _, _, _, _, _, _, online, _, classFile = GetGuildRosterInfo(i)
    local s = short(name)
    if s then out[s] = { class = classFile, online = online and true or false } end
  end
  -- your own character always counts, even when the roster lists it under another name
  local me = Me()
  if me and not out[me] then
    local _, class = UnitClass("player")
    out[me] = { class = class, online = true }
  end
  return out, n
end

-- Records of members still in the guild (every record while the roster is not loaded yet).
local function ActiveRecords(roster, n)
  local out = {}
  for who, r in pairs(Store() or {}) do
    if SPECS[r.ms] and (n == 0 or roster[who]) then out[who] = r end
  end
  return out
end

local refreshers = {}
local redrawPending = false
local function redrawRoster()
  if redrawPending then return end
  redrawPending = true
  C_Timer.After(0.5, function()
    redrawPending = false
    if GuildOS.RefreshRosterUI then GuildOS:SafeCall(GuildOS.RefreshRosterUI, GuildOS) end
  end)
end

function MySpecs.Refresh()
  for _, fn in ipairs(refreshers) do GuildOS:SafeCall(fn) end
  redrawRoster()
end

local function Publish(r)
  if GuildOS.SyncService and IsInGuild() then
    GuildOS.SyncService:Publish("myspec", "set", r, { priority = "BULK" })
  end
end

-- Save a main and offspec for this character. Returns true when something changed.
function MySpecs.Save(ms, os)
  local st, me = Store(), Me()
  if not st or not me or not SPECS[ms] then return false end
  if os == ms or (os and not SPECS[os]) then os = nil end
  local r = st[me]
  if r and r.ms == ms and (r.os or nil) == (os or nil) then return false end
  local t = Now()
  r = r or { id = me, who = me, c = t, rev = 0, h = {} }
  r.h = r.h or {}
  table.insert(r.h, 1, {
    ms = ms, os = os, from_ms = r.ms, from_os = r.os, t = t,
    raid = IsInRaid() and true or nil,
  })
  while #r.h > HISTORY_MAX do table.remove(r.h) end
  r.ms, r.os = ms, os
  r.rev = (r.rev or 0) + 1
  r.u = t
  r.ed = me
  st[me] = r
  Publish(r)
  MySpecs.Refresh()
  return true
end

-- The spec this character is playing right now, as a key, or nil.
function MySpecs.Detect()
  local class = MyClass()
  local specName
  -- the current API lives in C_SpecializationInfo; the older globals are the fallback
  local specApi = C_SpecializationInfo or {}
  local getIdx = specApi.GetSpecialization or GetSpecialization
  local getInfo = specApi.GetSpecializationInfo or GetSpecializationInfo
  if getIdx and getInfo then
    local idx = getIdx()
    if idx then
      local first, second = getInfo(idx)
      if type(first) == "table" then specName = first.name else specName = second end
    end
  end
  -- Clients without the spec API: the talent tab with the most points is the spec
  if type(specName) ~= "string" and GetTalentTabInfo then
    local best, bestPts = nil, -1
    for i = 1, 3 do
      local name, _, pts = GetTalentTabInfo(i)
      if name and (pts or 0) > bestPts then best, bestPts = name, pts or 0 end
    end
    specName = best
  end
  if type(specName) ~= "string" then return nil end
  for _, e in ipairs(CLASS_SPECS[class] or {}) do
    if e.key ~= "bear" and e.key ~= "cat" and (specName == e.en or specName == e.de) then return e.key end
  end
  -- Druid: one Feral tree, the form decides which spec is played
  if specName:find("Feral") and class == "DRUID" then
    -- without the form id the form is unknown: say nothing rather than guess
    if not GetShapeshiftFormID then return nil end
    return GetShapeshiftFormID() == FERAL_BEAR_FORM and "bear" or "cat"
  end
  return nil
end

----------------------------------------------------------------------
-- Sync: one record per character, newer revisions win; only the character itself may write it
----------------------------------------------------------------------
local function ValidRecord(s, who)
  if type(s) ~= "table" or s.who ~= who or s.id ~= who or s.ed ~= who then return false end
  if type(s.ms) ~= "string" or not SPECS[s.ms] then return false end
  if s.os ~= nil and (type(s.os) ~= "string" or not SPECS[s.os]) then return false end
  if type(s.rev) ~= "number" or s.rev < 0 or s.rev > 1e6 then return false end
  if type(s.u) ~= "number" or s.u < 0 or s.u > Now() + DAY then return false end
  if s.h ~= nil and type(s.h) ~= "table" then return false end
  return true
end

if GuildOS.SyncService then
  GuildOS.SyncService.GUILD_ONLY_DOMAINS.myspec = true
  GuildOS.SyncService:On("myspec", function(env, sender)
    local s = env and env.data
    local who = short(sender)
    if not who or not ValidRecord(s, who) then return end
    local st = Store()
    if not st then return end
    local cur = st[who]
    if cur and (cur.rev or 0) >= s.rev then return end
    st[who] = s
    MySpecs.Refresh()
  end)
end

----------------------------------------------------------------------
-- Roster marks: a role icon after the name, a grey ? for officers when no spec is set,
-- and the main and offspec in the tooltip
----------------------------------------------------------------------
local function specTexture(row)
  if row.mySpecTex then return row.mySpecTex end
  local t = row:CreateTexture(nil, "OVERLAY")
  t:SetSize(11, 11)
  if row.addonDot then
    t:SetPoint("LEFT", row.addonDot, "RIGHT", 3, 0)
  else
    t:SetPoint("RIGHT", row.nameText, "RIGHT", 0, 0)
  end
  t:Hide()
  row.mySpecTex = t
  return t
end

local ICON_PATH = {}
for role, path in pairs(ROLE_ICON) do ICON_PATH[role] = path end

local function paintRow(row, data)
  if not row or not data or not row.nameText then return end
  local t = specTexture(row)
  if not row.nameText:IsShown() then t:Hide() return end
  local r = RecordOf(data.name)
  local s = r and SPECS[r.ms]
  if s then
    t:SetTexture(ICON_PATH[s.role])
    t:SetDesaturated(not data.isOnline)
    t:Show()
  elseif isOfficer() then
    t:SetTexture(QUESTION_ICON)
    t:SetDesaturated(true)
    t:Show()
  else
    t:Hide()
  end
end

local function addRowTooltip(row)
  local data = row and row.memberData
  if not data or not GameTooltip:IsShown() then return end
  local r = RecordOf(data.name)
  if not r or not SPECS[r.ms] then return end
  GameTooltip:AddLine(" ")
  GameTooltip:AddDoubleLine(L["Main spec"], specText(r.ms) or "?", 0.85, 0.66, 0.31, 1, 1, 1)
  if r.os and SPECS[r.os] then
    GameTooltip:AddDoubleLine(L["Offspec"], specText(r.os) or "?", 0.85, 0.66, 0.31, 1, 1, 1)
  end
  if r.u then
    GameTooltip:AddLine(L["Confirmed %s"]:format(date("%Y-%m-%d", r.u)), 0.6, 0.6, 0.6)
  end
  GameTooltip:Show()
end

----------------------------------------------------------------------
-- Popups
----------------------------------------------------------------------
local raidPending                     -- { ms, os } waiting for the raid confirmation

StaticPopupDialogs["OUTLAWOS_MYSPEC_RAID"] = {
  text = L["You are in a raid. Changing your main spec now is noted for officers. Change it?"],
  button1 = YES, button2 = NO,
  OnAccept = function()
    if raidPending then MySpecs.Save(raidPending[1], raidPending[2]) end
    raidPending = nil
  end,
  OnCancel = function() raidPending = nil end,
  timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
}

StaticPopupDialogs["OUTLAWOS_MYSPEC_DRAFT"] = {
  text = "",
  button1 = YES, button2 = NO,
  OnAccept = function() MySpecs.ApplyDraft() end,
  OnCancel = function()
    local d = Drafts()
    if d then d[Me()] = nil end
  end,
  timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
}

function MySpecs.ApplyDraft()
  local d = Drafts()
  local me = Me()
  local draft = d and d[me]
  if d then d[me] = nil end
  if not draft or not SPECS[draft.ms] or SPECS[draft.ms].class ~= MyClass() then return end
  MySpecs.Save(draft.ms, draft.os)
end

----------------------------------------------------------------------
-- Login and spec changes: checks that the tab cannot do on its own
----------------------------------------------------------------------
local warnedMismatch = false
local nudgedLogin = false

local function checkOnLogin()
  local me = Me()
  local d = Drafts()
  local draft = d and d[me]
  if draft and SPECS[draft.ms] and SPECS[draft.ms].class == MyClass() then
    StaticPopupDialogs["OUTLAWOS_MYSPEC_DRAFT"].text =
      L["Copy your main spec from your other character? Main: %s."]:format(plain(draft.ms))
    StaticPopup_Show("OUTLAWOS_MYSPEC_DRAFT")
    return
  end
  local r = RecordOf(me)
  if not r then return end
  local now = MySpecs.Detect()
  if now and now ~= r.ms and now ~= r.os and not warnedMismatch then
    warnedMismatch = true
    GuildOS:Print(L["You are playing %s, but your main is set to %s. Use /mychar to change it."]
      :format(plain(now), plain(r.ms)))
  end
  if r.u and Now() - r.u > NUDGE_AFTER and not nudgedLogin then
    nudgedLogin = true
    GuildOS:Print(L["Your main spec was last confirmed over a month ago. Open /mychar and confirm it."])
  end
end

local function onSpecChanged()
  local now = MySpecs.Detect()
  if IsInRaid() and now then
    local swaps = GuildOS.db and GuildOS.db.specSwaps or {}
    if GuildOS.db then GuildOS.db.specSwaps = swaps end
    table.insert(swaps, 1, { who = Me(), ms = now, t = Now() })
    while #swaps > 30 do table.remove(swaps) end
    GuildOS:Print(L["Spec switched to %s during a raid. Noted for officers on this client."]:format(plain(now)))
  end
  local r = RecordOf(Me())
  if now and r and now ~= r.ms and now ~= r.os then
    GuildOS:Print(L["You are playing %s, but your main is set to %s. Use /mychar to change it."]
      :format(plain(now), plain(r.ms)))
  end
  MySpecs.Refresh()
end

local ev = CreateFrame("Frame")
ev:RegisterEvent("PLAYER_LOGIN")
pcall(ev.RegisterEvent, ev, "PLAYER_SPECIALIZATION_CHANGED")
ev:SetScript("OnEvent", function(_, event)
  if event == "PLAYER_LOGIN" then
    if type(UpdateRosterRow) == "function" then
      hooksecurefunc("UpdateRosterRow", function(row, data) GuildOS:SafeCall(paintRow, row, data) end)
    end
    if type(ShowRowTooltip) == "function" then
      hooksecurefunc("ShowRowTooltip", function(row) GuildOS:SafeCall(addRowTooltip, row) end)
    end
    C_Timer.After(6, function() GuildOS:SafeCall(checkOnLogin) end)
  elseif event == "PLAYER_SPECIALIZATION_CHANGED" then
    GuildOS:SafeCall(onSpecChanged)
  end
end)

----------------------------------------------------------------------
-- The "My Char" tab
----------------------------------------------------------------------
local function openMenu(anchor, items)
  if not (UIDropDownMenu_Initialize and UIDropDownMenu_CreateInfo and UIDropDownMenu_AddButton and ToggleDropDownMenu) then
    return
  end
  local menu = CreateFrame("Frame", "OutlawOSMySpecsMenu", UIParent, "UIDropDownMenuTemplate")
  UIDropDownMenu_Initialize(menu, function(_, level)
    for _, it in ipairs(items) do
      local info = UIDropDownMenu_CreateInfo()
      info.text = it.text
      info.checked = it.checked
      info.isNotRadio = true
      info.func = it.func
      UIDropDownMenu_AddButton(info, level)
    end
  end, "MENU")
  ToggleDropDownMenu(1, nil, menu, anchor, 0, 0)
end

-- The alt links are keyed by the full name ("First Surname") on some clients and by the roster
-- name on others. A character is matched by its first name, which is what the roster and the
-- spec records use.
local function firstName(k)
  if type(k) ~= "string" then return nil end
  return k:match("^(%S+)") or k
end

-- the name without the realm and server ("Name Surname-Realm" -> "Name Surname")
local function displayName(k)
  if type(k) ~= "string" then return "" end
  return (k:gsub("%-.*$", ""))
end

-- the characters on this account: the main and its alts, as the alt links name them
local function MyAltList()
  local links = GuildOS.db and GuildOS.db.altLinks or {}
  local me = Me()
  local main
  for k, m in pairs(links) do
    if firstName(k) == me then main = m break end
  end
  local out, seen = {}, {}
  local function add(k)
    if k and firstName(k) ~= me and not seen[k] then seen[k] = true; out[#out + 1] = k end
  end
  if main then
    -- an alt: the main and the main's other alts
    add(main)
    for k, m in pairs(links) do
      if m == main then add(k) end
    end
  else
    -- the main: every character linked to this one
    for k, m in pairs(links) do
      if firstName(m) == me then add(k) end
    end
  end
  table.sort(out)
  -- a member has at most four alts (the main is counted apart); the card and the menus rely on it
  while #out > MAX_ALTS do table.remove(out) end
  return out
end

local function BuildPanel(panel)
  local class = MyClass()
  local specs = CLASS_SPECS[class] or {}
  local cr, cg, cb = GuildOS:GetClassColor(class)
  local st = { ms = nil, os = nil }          -- what the buttons show; saved only by Save
  local buttons = {}

  local function loadStaged()
    local r = RecordOf(Me())
    st.ms = r and r.ms or nil
    st.os = r and r.os or nil
  end

  local function dirty()
    if not st.ms then return false end
    local r = RecordOf(Me())
    if not r then return true end
    return r.ms ~= st.ms or (r.os or nil) ~= (st.os or nil)
  end

  local title = UI:CreateText(panel, L["Main and offspec"], 12, C.gold.r, C.gold.g, C.gold.b)
  title:SetPoint("TOPLEFT", 10, -10)
  local intro = UI:CreateText(panel, L["Pick the talent tree you play. The guild sees it on your roster tooltip. Save to publish."],
    11, C.textSoft.r, C.textSoft.g, C.textSoft.b)
  intro:SetPoint("TOPLEFT", 10, -30)
  intro:SetPoint("RIGHT", panel, "RIGHT", -20, 0)
  intro:SetJustifyH("LEFT")
  intro:SetWordWrap(true)

  local header = UI:CreateText(panel, "", 11, C.text.r, C.text.g, C.text.b)
  header:SetPoint("TOPLEFT", 10, -54)

  -- Role columns: tank, healer, damage, each with the class's specs of that role
  local columns = {}
  for _, role in ipairs({ "T", "H", "D" }) do
    local list = {}
    for _, s in ipairs(specs) do
      if s.role == role then list[#list + 1] = s end
    end
    if #list > 0 then columns[#columns + 1] = { role = role, list = list } end
  end

  local ROW_Y, ROW_H = -104, 28
  local tallest = 0
  for i, col in ipairs(columns) do
    local x = 10 + (i - 1) * 196
    local head = UI:CreateText(panel, roleName(col.role):upper(), 11, cr, cg, cb)
    head:SetPoint("TOPLEFT", x, -80)
    tallest = math.max(tallest, #col.list)
    for j, s in ipairs(col.list) do
      local b = UI:CreateButton(panel, roleIcon(s.role, 18) .. " " .. labelOf(s), 186, 24)
      b:SetPoint("TOPLEFT", x, ROW_Y - (j - 1) * ROW_H)
      b.key, b.spec = s.key, s
      b.sel = b:CreateTexture(nil, "OVERLAY")
      b.sel:SetColorTexture(C.gold.r, C.gold.g, C.gold.b, 1)
      b.sel:SetPoint("BOTTOMLEFT", 2, 0)
      b.sel:SetPoint("BOTTOMRIGHT", -2, 0)
      b.sel:SetHeight(2)
      b.sel:Hide()
      b:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine(labelOf(s), 1, 1, 1)
        GameTooltip:AddLine(roleName(s.role), ROLE_RGB[s.role][1], ROLE_RGB[s.role][2], ROLE_RGB[s.role][3])
        GameTooltip:AddLine(ROLE_TIP[s.role], 0.85, 0.85, 0.85, true)
        if s.key == "bear" or s.key == "cat" then
          GameTooltip:AddLine(L["Druid Feral is played in two forms: bear for tank, cat for damage."], 0.85, 0.85, 0.85, true)
        end
        GameTooltip:Show()
      end)
      b:SetScript("OnLeave", function() GameTooltip:Hide() end)
      b:SetScript("OnClick", function()
        st.ms = s.key
        if st.os == s.key then st.os = nil end
        MySpecs.Paint()
      end)
      buttons[#buttons + 1] = b
    end
  end
  if #columns == 0 then
    local t = UI:CreateText(panel, L["Main and offspec are not set up for your class yet. It is planned for a later update."],
      11, C.textSoft.r, C.textSoft.g, C.textSoft.b)
    t:SetPoint("TOPLEFT", 10, ROW_Y)
  end

  -- Offspec: a dropdown, "None" first
  local y0 = ROW_Y - math.max(tallest, 1) * ROW_H - 8
  local offLabel = UI:CreateText(panel, L["Offspec"], 11, C.text.r, C.text.g, C.text.b)
  offLabel:SetPoint("TOPLEFT", 10, y0 - 6)
  local offBtn = UI:CreateButton(panel, "", 260, 24)
  offBtn:SetPoint("TOPLEFT", 90, y0)
  -- the button's own text does not show on this button type, so the label is drawn on top of it
  local offText = UI:CreateText(offBtn, "", 11, C.text.r, C.text.g, C.text.b)
  offText:SetPoint("LEFT", offBtn, "LEFT", 8, 0)
  offBtn:SetScript("OnClick", function(self)
    local items = { {
      text = L["None"], checked = st.os == nil,
      func = function() st.os = nil; MySpecs.Paint() end,
    } }
    for _, s in ipairs(specs) do
      if s.key ~= st.ms then
        items[#items + 1] = {
          text = roleIcon(s.role, 14) .. " " .. labelOf(s), checked = st.os == s.key,
          func = function() st.os = s.key; MySpecs.Paint() end,
        }
      end
    end
    openMenu(self, items)
  end)

  -- Actions: Save, Undo, use the current spec, confirm
  local y1 = y0 - 36
  local saveBtn = UI:SetButtonVariant(UI:CreateButton(panel, L["Save"], 130, 24), "primary")
  saveBtn:SetPoint("TOPLEFT", 10, y1)
  local undoBtn = UI:CreateButton(panel, L["Undo last change"], 150, 24)
  undoBtn:SetPoint("TOPLEFT", 146, y1)
  local currentBtn = UI:CreateButton(panel, L["Use my current spec"], 170, 24)
  currentBtn:SetPoint("TOPLEFT", 302, y1)
  local confirmBtn = UI:CreateButton(panel, L["Confirm still right"], 150, 24)
  confirmBtn:SetPoint("TOPLEFT", 478, y1)

  -- Copy to an alt: a draft for that character, offered when it is next logged in
  local y2 = y1 - 32
  local copyBtn = UI:CreateButton(panel, L["Copy to my alts..."], 200, 24)
  copyBtn:SetPoint("TOPLEFT", 10, y2)

  saveBtn:SetScript("OnClick", function()
    if not st.ms then return end
    local r = RecordOf(Me())
    if IsInRaid() and r and r.ms ~= st.ms then
      raidPending = { st.ms, st.os }
      StaticPopup_Show("OUTLAWOS_MYSPEC_RAID")
      return
    end
    MySpecs.Save(st.ms, st.os)
    loadStaged()
    MySpecs.Paint()
  end)

  undoBtn:SetScript("OnClick", function()
    local r = RecordOf(Me())
    local last = r and r.h and r.h[1]
    if not last or not last.from_ms then return end
    MySpecs.Save(last.from_ms, last.from_os)
    loadStaged()
    MySpecs.Paint()
  end)

  currentBtn:SetScript("OnClick", function()
    local now = MySpecs.Detect()
    if not now then
      GuildOS:Print(L["Could not read your current spec."])
      return
    end
    st.ms = now
    if st.os == now then st.os = nil end
    MySpecs.Paint()
  end)

  confirmBtn:SetScript("OnClick", function()
    local r = RecordOf(Me())
    if not r then return end
    r.u = Now()
    r.rev = (r.rev or 0) + 1
    r.ed = Me()
    Publish(r)
    MySpecs.Refresh()
  end)

  copyBtn:SetScript("OnClick", function(self)
    if not st.ms then
      GuildOS:Print(L["Pick a main spec first."])
      return
    end
    local roster = Roster()
    local items = {}
    local sameClass = {}
    local alts = MyAltList()
    for _, alt in ipairs(alts) do
      local rc = roster[firstName(alt)] and roster[firstName(alt)].class
      if rc == class then sameClass[#sameClass + 1] = alt end
    end
    if #sameClass > 0 then
      items[#items + 1] = {
        text = L["All my %s alts"]:format(classWord(class)), checked = false,
        func = function()
          local d = Drafts()
          if not d then return end
          for _, alt in ipairs(sameClass) do d[firstName(alt)] = { ms = st.ms, os = st.os, by = Me(), t = Now() } end
          GuildOS:Print(L["Copied your spec to %d of your %s. Log in as them and accept the offer."]:format(#sameClass, classWord(class)))
        end,
      }
    end
    for _, alt in ipairs(alts) do
      items[#items + 1] = {
        text = alt, checked = false,
        func = function()
          local rc = roster[firstName(alt)] and roster[firstName(alt)].class
          if rc and rc ~= class then
            GuildOS:Print(L["%s is a %s, so your %s spec does not fit. Pick an alt of your class."]:format(alt, classWord(rc), classWord(class)))
            return
          end
          local d = Drafts()
          if not d then return end
          d[firstName(alt)] = { ms = st.ms, os = st.os, by = Me(), t = Now() }
          GuildOS:Print(L["Copied your spec to %s. Log in as them and accept the offer."]:format(alt))
        end,
      }
    end
    if #items == 0 then
      GuildOS:Print(L["No alts linked to this character yet. Link them in the alt tools first."])
      return
    end
    openMenu(self, items)
  end)

  -- Status: what the guild sees, the confirmation, and the checks
  local y3 = y2 - 40
  local status = UI:CreateText(panel, "", 11, C.text.r, C.text.g, C.text.b)
  status:SetPoint("TOPLEFT", 10, y3)
  status:SetJustifyH("LEFT")
  local notes = UI:CreateText(panel, "", 11, C.textSoft.r, C.textSoft.g, C.textSoft.b)
  notes:SetPoint("TOPLEFT", 10, y3 - 36)
  notes:SetJustifyH("LEFT")
  notes:SetWordWrap(true)
  notes:SetPoint("RIGHT", panel, "RIGHT", -20, 0)

  -- Guild lines (everyone) and the officer block
  local guild = UI:CreateText(panel, "", 11, C.textSoft.r, C.textSoft.g, C.textSoft.b)
  guild:SetPoint("TOPLEFT", 10, y3 - 98)
  guild:SetJustifyH("LEFT")
  guild:SetWordWrap(true)
  guild:SetPoint("RIGHT", panel, "RIGHT", -20, 0)

  -- Officer block: one row per item, a gold label on the left and the values wrapping on the right.
  -- A row with onClick (the long name lists) opens its full names in a small window.
  local OFFICER_LABEL_W = 150
  local OFFICER_GAP = 8
  local officerRule = panel:CreateTexture(nil, "ARTWORK")
  officerRule:SetColorTexture(C.lineHi.r, C.lineHi.g, C.lineHi.b, 0.6)
  officerRule:SetPoint("TOPLEFT", 10, y3 - 190)
  officerRule:SetPoint("RIGHT", panel, "RIGHT", -20, 0)
  officerRule:SetHeight(1)
  officerRule:Hide()

  local officerBox = CreateFrame("Frame", nil, panel)
  officerBox:SetPoint("TOPLEFT", 10, y3 - 200)
  officerBox:SetPoint("RIGHT", panel, "RIGHT", -20, 0)
  officerBox:SetHeight(1)

  local namesFrame
  local function showNames(title, text)
    if not namesFrame then
      namesFrame = CreateFrame("Frame", "OutlawOSMySpecNames", UIParent, "BackdropTemplate")
      namesFrame:SetSize(460, 320)
      namesFrame:SetPoint("CENTER")
      namesFrame:SetFrameStrata("DIALOG")
      namesFrame:SetMovable(true)
      namesFrame:EnableMouse(true)
      namesFrame:RegisterForDrag("LeftButton")
      namesFrame:SetScript("OnDragStart", function(self) self:StartMoving() end)
      namesFrame:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)
      namesFrame:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
      namesFrame:SetBackdropColor(C.well.r, C.well.g, C.well.b, 0.97)
      namesFrame:SetBackdropBorderColor(C.gold.r, C.gold.g, C.gold.b, 0.9)
      namesFrame.title = UI:CreateText(namesFrame, "", 13, C.gold.r, C.gold.g, C.gold.b)
      namesFrame.title:SetPoint("TOPLEFT", 14, -12)
      local close = UI:CreateButton(namesFrame, L["Close"], 80, 22)
      close:SetPoint("BOTTOMRIGHT", -12, 10)
      close:SetScript("OnClick", function() namesFrame:Hide() end)
      local scroll = CreateFrame("ScrollFrame", nil, namesFrame, "UIPanelScrollFrameTemplate")
      scroll:SetPoint("TOPLEFT", 12, -38)
      scroll:SetPoint("BOTTOMRIGHT", -32, 44)
      local edit = CreateFrame("EditBox", nil, scroll)
      edit:SetMultiLine(true)
      edit:SetAutoFocus(false)
      edit:SetFontObject(ChatFontNormal)
      edit:SetWidth(400)
      edit:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
      scroll:SetScrollChild(edit)
      namesFrame.edit = edit
      namesFrame.scroll = scroll
    end
    namesFrame.title:SetText(title)
    namesFrame.edit:SetText(text)
    namesFrame.edit:SetHeight(math.max(260, namesFrame.edit:GetStringHeight() + 20))
    namesFrame.scroll:SetVerticalScroll(0)
    namesFrame:Show()
  end

  local officerRows = {}
  local function officerRow(i)
    if officerRows[i] then return officerRows[i] end
    local row = CreateFrame("Button", nil, officerBox)
    row.label = UI:CreateText(row, "", 11, C.gold.r, C.gold.g, C.gold.b)
    row.label:SetPoint("TOPLEFT", 0, 0)
    row.label:SetWidth(OFFICER_LABEL_W)
    row.label:SetJustifyH("LEFT")
    row.label:SetWordWrap(true)
    row.value = UI:CreateText(row, "", 11, C.textSoft.r, C.textSoft.g, C.textSoft.b)
    row.value:SetPoint("TOPLEFT", OFFICER_LABEL_W + OFFICER_GAP, 0)
    row.value:SetJustifyH("LEFT")
    row.value:SetWordWrap(true)
    row:SetScript("OnClick", function(self) if self.onClick then self.onClick() end end)
    officerRows[i] = row
    return row
  end

  -- items: { label, value, onClick? }. Rows stack under each other; each one is as tall as its text.
  local function layoutOfficer(items)
    local width = officerBox:GetWidth()
    if not width or width < 100 then width = 600 end
    local valueW = width - OFFICER_LABEL_W - OFFICER_GAP
    local prev
    for i, it in ipairs(items) do
      local row = officerRow(i)
      row.onClick = it.onClick
      row.label:SetText(it[1])
      row.value:SetWidth(valueW)
      row.value:SetText(it[2] or "")
      row:ClearAllPoints()
      if prev then
        row:SetPoint("TOPLEFT", prev, "BOTTOMLEFT", 0, -6)
      else
        row:SetPoint("TOPLEFT", officerBox, "TOPLEFT", 0, 0)
      end
      row:SetWidth(width)
      row:SetHeight(math.max(row.label:GetStringHeight(), row.value:GetStringHeight(), 14))
      row:Show()
      prev = row
    end
    for i = #items + 1, #officerRows do officerRows[i]:Hide() end
  end

  -- The "you" card, top right: a class-coloured band, your rank and join date, your bounty points
  -- and dungeon clears this week and all time, and your alts. Read from the journal, the Founding
  -- dates and the alt links.
  local card = CreateFrame("Frame", nil, panel, "BackdropTemplate")
  card:SetPoint("TOPLEFT", 760, -40)
  card:SetSize(560, 168)
  card:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
  card:SetBackdropColor(C.well.r, C.well.g, C.well.b, 0.95)
  card:SetBackdropBorderColor(C.gold.r, C.gold.g, C.gold.b, 0.9)

  local band = card:CreateTexture(nil, "ARTWORK")
  band:SetColorTexture(cr, cg, cb, 0.9)
  band:SetPoint("TOPLEFT", 1, -1)
  band:SetPoint("TOPRIGHT", -1, -1)
  band:SetHeight(4)

  local classIcon = card:CreateTexture(nil, "OVERLAY")
  classIcon:SetSize(28, 28)
  classIcon:SetPoint("TOPLEFT", 14, -16)
  classIcon:SetTexture("Interface\\GLUES\\CHARACTERCREATE\\UI-CharacterCreate-Classes")
  local coords = CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[class]
  if coords then classIcon:SetTexCoord(unpack(coords)) end

  local cardTitle = UI:CreateText(card, "", 15, cr, cg, cb)
  cardTitle:SetPoint("TOPLEFT", 50, -14)
  local cardRank = UI:CreateText(card, "", 10, C.gold.r, C.gold.g, C.gold.b)
  cardRank:SetPoint("TOPLEFT", 50, -34)
  local cardTag = UI:CreateText(card, "", 10, C.gold.r, C.gold.g, C.gold.b)
  cardTag:SetPoint("TOPRIGHT", -14, -18)
  cardTag:SetJustifyH("RIGHT")

  -- four stat blocks: bounty points and clears, this week and all time
  local STAT_X = { 16, 152, 288, 424 }
  local stats = {}
  local statLabels = { L["bounty points this week"], L["clears this week"], L["bounty points all time"], L["clears all time"] }
  for i = 1, 4 do
    local v = UI:CreateText(card, "0", 22, C.gold.r, C.gold.g, C.gold.b)
    v:SetPoint("TOPLEFT", STAT_X[i], -58)
    local l = UI:CreateText(card, statLabels[i], 10, C.textSoft.r, C.textSoft.g, C.textSoft.b)
    l:SetPoint("TOPLEFT", STAT_X[i], -90)
    stats[i] = v
  end

  local rule = card:CreateTexture(nil, "ARTWORK")
  rule:SetColorTexture(C.lineHi.r, C.lineHi.g, C.lineHi.b, 0.8)
  rule:SetPoint("TOPLEFT", 14, -116)
  rule:SetPoint("TOPRIGHT", -14, -116)
  rule:SetHeight(1)

  local cardBody = UI:CreateText(card, "", 10, C.textSoft.r, C.textSoft.g, C.textSoft.b)
  cardBody:SetPoint("TOPLEFT", 14, -126)
  cardBody:SetPoint("RIGHT", card, "RIGHT", -14, 0)
  cardBody:SetJustifyH("LEFT")
  cardBody:SetWordWrap(true)

  local function paintCard()
    local me = Me()
    local rankName = IsInGuild() and select(2, GetGuildInfo("player")) or nil
    local joined = GuildOS.Founding and GuildOS.Compat
      and GuildOS.Founding:JoinedAtOf(GuildOS:GetPlayerKey(GuildOS.Compat.PlayerName()))
    -- The game does not say when someone joined: this is the day GuildOS first saw them.
    local seenText = L["not recorded yet"]
    if joined then
      seenText = date("%Y-%m-%d", joined)
    end

    local weekStart = (GuildOS.EKO and GuildOS.EKO.WeekStart) and GuildOS.EKO:WeekStart() or 0
    local ptsWeek, ptsAll, clearsWeek, clearsAll = 0, 0, 0, 0
    for _, e in ipairs(GuildOS.db and GuildOS.db.journal and GuildOS.db.journal.entries or {}) do
      local d = e.data
      if e.type == "dungeon.clear" and type(d) == "table" and (e.subjectKey or ""):match("^([^-]+)") == me then
        local week = (e.at or 0) >= weekStart
        clearsAll = clearsAll + 1
        if week then clearsWeek = clearsWeek + 1 end
        -- the same rule as the Dashboard: a clear on this week's Bounty Board, three or more Outlaws
        if d.onBoard and (d.outlaws or 0) >= 3 then
          local p = (d.outlaws >= 5) and 2 or 1
          ptsAll = ptsAll + p
          if week then ptsWeek = ptsWeek + p end
        end
      end
    end

    local altText = {}
    for _, alt in ipairs(MyAltList()) do
      local rec = RecordOf(firstName(alt))
      altText[#altText + 1] = displayName(alt) .. (rec and SPECS[rec.ms] and (" (" .. labelOf(SPECS[rec.ms]) .. ")") or "")
    end

    cardTitle:SetText(me)
    cardRank:SetText(rankName or L["Not in a guild"])
    local tag
    if ptsWeek >= 5 then tag = L["Bounty hunter this week"]
    elseif ptsWeek > 0 then tag = L["Getting there this week"]
    else tag = L["No bounty points yet this week"] end
    cardTag:SetText(tag)
    stats[1]:SetText(tostring(ptsWeek))
    stats[2]:SetText(tostring(clearsWeek))
    stats[3]:SetText(tostring(ptsAll))
    stats[4]:SetText(tostring(clearsAll))
    cardBody:SetText(table.concat({
      L["First seen in the guild: %s"]:format(seenText),
      L["Alts: %s"]:format(#altText > 0 and table.concat(altText, ", ") or L["none linked"]),
    }, "\n"))
  end

  -- Paint the buttons and the text from the current state
  local function paint()
    if not panel:IsVisible() then return end
    paintCard()
    local r = RecordOf(Me())
    for _, b in ipairs(buttons) do
      b.sel:SetShown(st.ms == b.key)
    end
    offText:SetText(L["Offspec"] .. ": " .. (st.os and plain(st.os) or L["None"]))
    saveBtn:SetEnabled(dirty())
    undoBtn:SetEnabled(r and r.h and r.h[1] and r.h[1].from_ms and true or false)
    confirmBtn:SetEnabled(r and true or false)
    -- hidden where the client cannot tell which spec is played; the manual pick still works
    local detected = MySpecs.Detect() ~= nil
    currentBtn:SetShown(detected)
    -- Confirm takes the gap when the current-spec button is hidden
    confirmBtn:ClearAllPoints()
    confirmBtn:SetPoint("TOPLEFT", detected and 478 or 302, y1)
    copyBtn:SetEnabled(st.ms ~= nil)

    header:SetText(L["Main"] .. ": " .. (st.ms and specText(st.ms) or "|cff888888" .. L["not set"] .. "|r")
      .. "    " .. L["Offspec"] .. ": " .. (st.os and specText(st.os) or "|cff888888" .. L["none"] .. "|r"))

    if r then
      local seen = L["The guild sees: %s, offspec %s."]:format(specText(r.ms) or "?", r.os and specText(r.os) or L["none"])
      local line = seen .. "\n" .. L["Last confirmed: %s."]:format(date("%Y-%m-%d", r.u or r.c or Now()))
      status:SetText(line)
    else
      status:SetText("|cff888888" .. L["Not set yet. Pick a main spec and save."] .. "|r")
    end

    local lines = {}
    local now = MySpecs.Detect()
    if r and now and now ~= r.ms and now ~= r.os then
      lines[#lines + 1] = L["You are playing %s right now, but your main is %s."]:format(plain(now), plain(r.ms))
    end
    if r and r.u and Now() - r.u > NUDGE_AFTER then
      lines[#lines + 1] = L["It has been over a month since you confirmed this. Still right? Press Confirm."]
    end
    notes:SetText(table.concat(lines, "\n"))

    -- Guild lines
    local roster, n = Roster()
    local active = ActiveRecords(roster, n)
    local setCount, tanks, heals, dps = 0, 0, 0, 0
    for _, rec in pairs(active) do
      setCount = setCount + 1
      local role = SPECS[rec.ms].role
      if role == "T" then tanks = tanks + 1 elseif role == "H" then heals = heals + 1 else dps = dps + 1 end
    end
    local out = {}
    out[#out + 1] = L["%d of %d members have set a spec."]:format(setCount, n > 0 and n or setCount)
    out[#out + 1] = L["Guild mains: %d tanks, %d healers, %d damage."]:format(tanks, heals, dps)

    local target = st.os or st.ms
    if target then
      local mates = {}
      for who, rec in pairs(active) do
        if who ~= Me() and (rec.ms == target or rec.os == target) then mates[#mates + 1] = who end
      end
      table.sort(mates)
      if #mates > 0 then
        out[#out + 1] = L["Guildmates on %s: %s"]:format(plain(target), table.concat(mates, ", "))
      end
    end
    guild:SetText(table.concat(out, "\n"))

    -- Officer block: the raid leader's view, one labelled row per item
    local items = {}
    if isOfficer() then
      local classSeen, onlineMain = {}, {}
      for _, m in pairs(roster) do classSeen[m.class] = true end
      for who, rec in pairs(active) do
        if roster[who] and roster[who].online then
          onlineMain[rec.ms] = (onlineMain[rec.ms] or 0) + 1
        end
      end
      local onlineTanks, onlineHeals = {}, {}
      for who, rec in pairs(active) do
        if roster[who] and roster[who].online then
          if SPECS[rec.ms].role == "T" then onlineTanks[#onlineTanks + 1] = who
          elseif SPECS[rec.ms].role == "H" then onlineHeals[#onlineHeals + 1] = who end
        end
      end
      table.sort(onlineTanks); table.sort(onlineHeals)
      items[#items + 1] = { L["Tanks online"], #onlineTanks > 0 and table.concat(onlineTanks, ", ") or L["none"] }
      items[#items + 1] = { L["Healers online"], #onlineHeals > 0 and table.concat(onlineHeals, ", ") or L["none"] }

      -- gaps: specs of the classes in the guild with no online main
      for _, role in ipairs({ "T", "H", "D" }) do
        local gaps = {}
        for _, s in pairs(SPECS) do
          if s.role == role and classSeen[s.class] and not onlineMain[s.key] then
            gaps[#gaps + 1] = labelOf(s) .. " (" .. classWord(s.class) .. ")"
          end
        end
        table.sort(gaps)
        if #gaps > 0 then
          items[#items + 1] = { L["No online %s main"]:format(roleName(role):lower()), table.concat(gaps, ", ") }
        end
      end

      -- members with no spec set: a count here, the names in a window on click
      local missing = {}
      for who in pairs(roster) do
        if not active[who] then missing[#missing + 1] = who end
      end
      table.sort(missing)
      if #missing > 0 then
        items[#items + 1] = {
          L["No spec set"],
          L["%d members. Click to see the names."]:format(#missing),
          onClick = function()
            showNames(L["No spec set (%d)"]:format(#missing), table.concat(missing, ", "))
          end,
        }
      end

      -- recent changes, newest first
      local changes = {}
      for who, rec in pairs(active) do
        for _, h in ipairs(rec.h or {}) do
          if type(h) == "table" and SPECS[h.ms] then
            changes[#changes + 1] = { who = who, h = h }
          end
        end
      end
      table.sort(changes, function(a, b) return (a.h.t or 0) > (b.h.t or 0) end)
      if #changes > 0 then
        local lines = {}
        for i = 1, math.min(8, #changes) do
          local c = changes[i]
          local was = c.h.from_ms and (" (" .. L["was"] .. " " .. (SPECS[c.h.from_ms] and labelOf(SPECS[c.h.from_ms]) or "?") .. ")") or ""
          local raid = c.h.raid and (" [" .. L["in raid"] .. "]") or ""
          lines[#lines + 1] = ("%s  %s: %s%s%s"):format(date("%m-%d %H:%M", c.h.t or 0), c.who,
            labelOf(SPECS[c.h.ms]), was, raid)
        end
        items[#items + 1] = { L["Recent changes"], table.concat(lines, "\n") }
      end

      local swaps = GuildOS.db and GuildOS.db.specSwaps or {}
      local swapLines = {}
      for i = 1, math.min(5, #swaps) do
        local s = swaps[i]
        if SPECS[s.ms] then
          swapLines[#swapLines + 1] = ("%s  %s: %s"):format(date("%m-%d %H:%M", s.t or 0), s.who or "?", labelOf(SPECS[s.ms]))
        end
      end
      if #swapLines > 0 then
        items[#items + 1] = { L["Spec swaps in raids on this client"], table.concat(swapLines, "\n") }
      end
    end
    layoutOfficer(items)
    officerRule:SetShown(isOfficer())
  end
  MySpecs.Paint = paint
  table.insert(refreshers, paint)

  panel:HookScript("OnShow", function()
    loadStaged()
    GuildOS:SafeCall(paint)
  end)
  loadStaged()
  GuildOS:SafeCall(paint)
  return paint
end

UI:RegisterFeature({
  id = "mychar", label = L["My Char"], order = 50,
  build = function(c) return BuildPanel(c) end,
})

function MySpecs.Show()
  UI:OpenWindow("mychar")
end

SLASH_OUTLAWSPEC1 = "/gspec"
SLASH_OUTLAWSPEC2 = "/mychar"
SlashCmdList.OUTLAWSPEC = function() MySpecs.Show() end
