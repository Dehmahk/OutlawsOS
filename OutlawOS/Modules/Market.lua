----------------------------------------------------------------------
-- Guild OS - Marketplace: the data, the sharing and the notices.
-- Ported from GuildOS_Unbroken 2.3.3 by Christian (used with his agreement). The tab is
-- UI/MarketPanel.lua, the item names and suggestions are Modules/MarketItems.lua.
--
-- "Offering": an item or a service a member puts up. "Looking for": what a member asks the guild
-- for. The guild sees both and answers with one click: "Want it" on an offer, "I have it" on a
-- request. Craft orders stay in the Crafts tab (CraftOrders); this tab only points there.
--
--   offer = { id = "<by>:<time>:<rand>" (an offer) or "...:s" (a request), by, it = item id or nil,
--             txt = item name or service, n = quantity, pr = price as typed, prc = price in copper,
--             note, st = "open" | "sold" | "gone", c, u, rev, ed,
--             mod = the officer who took it down (only with st "gone") }
--             only `by` changes it; an officer may take it down (mod, ed = mod)
--   want  = { id = "<offer id>#<who>", o = offer id, who, st = "in" | "out",
--             q = how many of a request I have (optional), c, u, rev, ed }   only `who` changes it
--             on an offer: wants it; on a request: has it
--
-- Shared over the hidden guild addon channel on its own prefix, so every member who runs Guild OS
-- keeps the same list. A copy reaches whoever was offline when it was made.
----------------------------------------------------------------------
local Market = {}
GuildOS.Market = Market
local L = GuildOS.L

Market.PREFIX = "GOSMarket"   -- max 16 characters
local PROTO = 1
local DAY = 86400
local KEEP_OFFER = 7 * DAY    -- an offer runs a week after its last change
local KEEP_GONE = DAY         -- a sold or removed one stays a day, so the change reaches everyone
local HEARD_FOR = 60          -- a copy someone sent a minute ago is not sent again
local CAP = 50                -- posts (offers and requests) one member may have up
local MAX_AGE = 600           -- a change older than ten minutes is not announced
local OLD_AFTER = 3 * DAY     -- an offer this old is offered for renewal
local QUIET = 30              -- after login, changes are counted and told once, not one by one
local QUESTION = "Interface\\Icons\\INV_Misc_Note_05"
Market.CAP, Market.OLD_AFTER, Market.KEEP_OFFER = CAP, OLD_AFTER, KEEP_OFFER

local AceComm = LibStub("AceComm-3.0")
local Ser = LibStub("GuildOS-LibSerialize")
local Deflate = LibStub("LibDeflate")
local comm = {}
AceComm:Embed(comm)

local function Now() return (GetServerTime and GetServerTime()) or time() end
local function Me() return UnitName("player") end
local function Short(name) return type(name) == "string" and (name:match("^([^-]+)") or name) or nil end
Market.Now, Market.Me, Market.Short = Now, Me, Short

-- on the screen and in the notices: no colour codes, no pipes, no control characters
local function Clean(s)
  s = tostring(s or "")
  s = s:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("|", "")
  s = s:gsub("%c", " ")
  return (s:gsub("^%s+", ""):gsub("%s+$", ""))
end

---------------------------------------------------------------- where things are kept
-- This guild's offers and requests (saved, per guild).
local function GuildKey()
  local name = GetGuildInfo and GetGuildInfo("player")
  if not name or name == "" then return nil end
  return (GetRealmName() or "") .. "|" .. name
end

function Market.G()
  if not GuildOS.db then return nil end
  local key = GuildKey()
  if not key then return nil end
  GuildOS.db.market = GuildOS.db.market or {}
  local g = GuildOS.db.market[key]
  if not g then
    g = {}
    GuildOS.db.market[key] = g
  end
  g.offers = g.offers or {}
  g.wants = g.wants or {}
  return g
end

-- the feature switch in Settings turns the whole tab, its sharing and its notices off
function Market.Enabled() return GuildOS:IsFeatureEnabled("market") end

-- my choices: the two notify switches and the popup (on by default), the members I muted, the
-- items whose popups I turned off, and where the popup sits
function Market.Prefs()
  if not GuildOS.db then return { notifyOffers = true, notifyRequests = true, popup = true, muted = {}, hideItems = {} } end
  GuildOS.db.marketPrefs = GuildOS.db.marketPrefs or {}
  local p = GuildOS.db.marketPrefs
  if p.notifyOffers == nil then p.notifyOffers = true end
  if p.notifyRequests == nil then p.notifyRequests = true end
  if p.popup == nil then p.popup = true end
  p.muted = p.muted or {}
  p.hideItems = p.hideItems or {}
  return p
end

-- a member I muted: their posts are hidden and make no noise
function Market.IsMuted(name)
  return name ~= nil and name ~= Me() and Market.Prefs().muted[Short(name)] == true
end

function Market.ToggleMute(name)
  local p, who = Market.Prefs(), Short(name)
  if not who or who == Me() then return end
  p.muted[who] = (not p.muted[who]) and true or nil
  GuildOS:Print(p.muted[who] and L["Muted %s: their posts are hidden and make no noise."]:format(who)
    or L["%s is no longer muted."]:format(who))
  Market.Changed()
end

-- the key of what a post is for: an item by its number, a service by its text
local function ItemKey(o)
  return o.it and ("i" .. o.it) or ("s" .. (o.txt or ""):lower())
end
Market.ItemKey = ItemKey

function Market.ItemHidden(o)
  return Market.Prefs().hideItems[ItemKey(o)] == true
end

function Market.HideItem(o)
  Market.Prefs().hideItems[ItemKey(o)] = true
  GuildOS:Print(L["No popups for %s any more. The Muted filter lists it, right-click there to show it again."]:format(Market.Label(o)))
  Market.Changed()
end

function Market.ShowItem(o)
  Market.Prefs().hideItems[ItemKey(o)] = nil
  Market.Changed()
end

---------------------------------------------------------------- the guild roster (who is a member, online, what class)
local roster = {} -- short name -> { class, online, rank }

function Market.ReadRoster()
  wipe(roster)
  local n = GetNumGuildMembers and GetNumGuildMembers() or 0
  for i = 1, n do
    local name, _, _, _, _, _, _, _, online, _, classFile = GetGuildRosterInfo(i)
    local short = Short(name)
    if short then roster[short] = { class = classFile, online = online and true or false } end
  end
end

function Market.InGuild(name)
  return Short(name) == Me() or roster[Short(name)] ~= nil
end

function Market.IsOnline(name)
  if Short(name) == Me() then return true end
  local e = roster[Short(name)]
  return e and e.online or false
end

function Market.ClassOf(name)
  if Short(name) == Me() then return select(2, UnitClass("player")) end
  local e = roster[Short(name)]
  return e and e.class
end

-- a name in its class colour; `class` when the roster does not know the member (a crafter's)
function Market.ColorName(name, class)
  return "|cff" .. GuildOS:GetClassColorHex(Market.ClassOf(name) or class or "") .. (Short(name) or "?") .. "|r"
end

---------------------------------------------------------------- known services
-- Services the tab knows: they get an icon, are found in the suggestions (in either language),
-- read in each player's own language, and whoever can do one hears of a request. A service is
-- either a class's (a rogue picks locks) or a profession's (who has Enchanting, and at what rank).
-- A service travels as its text, so an entry is recognized by any of its names.
Market.SERVICES = {
  { key = "lockpick", name = "Lockpicking", class = "ROGUE", icon = "Interface\\Icons\\Spell_Nature_MoonKey",
    names = { "Lockpicking", "Schlossknacken", "Pick Lock", "Schloss knacken", "Lockbox", "Lockboxes",
              "Schließkassette", "Schließkassetten", "Open lockboxes", "Schließkassetten öffnen" },
    skill = { "Lockpicking", "Schlossknacken" } },
  { key = "portal", name = "Portals", class = "MAGE", icon = "Interface\\Icons\\Spell_Arcane_PortalStormWind",
    names = { "Portal", "Portals", "Portale", "Portal Stormwind", "Portal Ironforge", "Portal Darnassus",
              "Portal Orgrimmar", "Portal Undercity", "Portal Thunder Bluff" },
    skill = {} },
  { key = "summon", name = "Summoning", class = "WARLOCK", icon = "Interface\\Icons\\Spell_Shadow_Twilight",
    names = { "Summon", "Summoning", "Beschwörung", "Summon Player", "Ritual of Summoning" },
    skill = {} },
  { key = "disenchant", name = "Disenchanting", prof = "Enchanting", icon = "Interface\\Icons\\INV_Enchant_Disenchant",
    names = { "Disenchant", "Disenchanting", "Entzaubern" }, skill = { "Enchanting", "Verzauberkunst" } },
}
for _, s in ipairs(Market.SERVICES) do
  s.lower = {}
  for i, n in ipairs(s.names) do s.lower[i] = n:lower() end
end

function Market.ServiceName(s) return L[s.name] end

-- the known service an entry's text means, or nil
function Market.ServiceOf(text)
  text = strtrim(text or ""):lower()
  if text == "" then return nil end
  for _, s in ipairs(Market.SERVICES) do
    if text == Market.ServiceName(s):lower() then return s end
    for _, n in ipairs(s.lower) do if text == n then return s end end
  end
end

-- services for the typed text (any of their names contains it), for the suggestion lists
function Market.SuggestServices(text)
  text = strtrim(text or ""):lower()
  local out = {}
  if #text < 3 then return out end
  for _, s in ipairs(Market.SERVICES) do
    local hit = Market.ServiceName(s):lower():find(text, 1, true)
    for _, n in ipairs(s.lower) do hit = hit or n:find(text, 1, true) end
    if hit then out[#out + 1] = { svc = s, name = Market.ServiceName(s), icon = s.icon } end
  end
  return out
end

-- my own skill in a service: its rank (true when the class has it and no skill line shows),
-- or nil when I can't do it
function Market.MyServiceSkill(s)
  local _, class = UnitClass("player")
  if s.class and class ~= s.class then return nil end
  if GetNumSkillLines and GetSkillLineInfo then
    for i = 1, GetNumSkillLines() do
      local name, header, _, rank = GetSkillLineInfo(i)
      if not header and name then
        for _, n in ipairs(s.skill or {}) do if name == n then return rank or true end end
      end
    end
  end
  if s.class then return true end
  return nil
end

-- the members who can do a service, online first: { name, online, rank, max }. A class service
-- reads the roster; a profession service reads the professions the guild has recorded.
function Market.ServicePeople(s)
  local out = {}
  if s.prof then
    local lines = {}
    for line, p in pairs(GuildOS.ProfCatalog and GuildOS.ProfCatalog.professions or {}) do
      if p.en == s.prof then lines[line] = true end
    end
    for key, rec in pairs(GuildOS.db and GuildOS.db.professions or {}) do
      for line in pairs(lines) do
        local e = rec.profs and rec.profs[line]
        if e then
          local who = Short(key)
          if who and Market.InGuild(who) then
            out[#out + 1] = { who, Market.IsOnline(who), rank = e.rank, max = e.max }
          end
          break
        end
      end
    end
  else
    for who, e in pairs(roster) do
      if s.class and e.class == s.class then out[#out + 1] = { who, e.online } end
    end
  end
  table.sort(out, function(a, b)
    if a[2] ~= b[2] then return a[2] end
    return a[1] < b[1]
  end)
  return out
end

-- the members who make an item, from the Crafts tab's data: { playerName, playerKey, class,
-- profName }, or nil when nobody in the guild can make it
function Market.Crafters(it)
  if not it or not GuildOS.ProfDirectory then return nil end
  local ok, list = pcall(GuildOS.ProfDirectory.CraftersForItem, it)
  return ok and list or nil
end

-- whether I can make an item myself (a recipe I know), from the Crafts tab
function Market.ICanCraft(it)
  local CO = GuildOS.CraftOrders
  if not it or not CO or not CO.CanCraft then return false end
  local ok, yes = pcall(CO.CanCraft, CO, it)
  return ok and yes or false
end

function Market.OpenCrafts()
  if GuildOS.UI and GuildOS.UI.OpenWindow then GuildOS.UI:OpenWindow("recipes") end
end

---------------------------------------------------------------- reading what is kept
function Market.Live(o) return o.st == "open" and Now() - (o.u or 0) <= KEEP_OFFER end

function Market.Expired(o)
  if o.st ~= "open" then return Now() - (o.u or 0) > KEEP_GONE end
  return Now() - (o.u or 0) > KEEP_OFFER + KEEP_GONE
end

-- how long since its last change, in seconds
function Market.Age(o) return Now() - (o.u or 0) end

-- a request ("Looking for") rather than an offer ("Offering")
function Market.IsRequest(o) return type(o.id) == "string" and o.id:sub(-2) == ":s" end

-- how many of an item I carry (bags and bank)
function Market.Have(o)
  if not o.it then return 0 end
  local count = (C_Item and C_Item.GetItemCount) or GetItemCount
  local ok, n = pcall(count, o.it, true)
  return ok and tonumber(n) or 0
end

-- a request for something I can do: a service, or an item I can craft
function Market.SeekForMe(o)
  if not Market.IsRequest(o) or o.by == Me() then return false end
  if o.it then return Market.ICanCraft(o.it) end
  local s = Market.ServiceOf(o.txt)
  return (s and Market.MyServiceSkill(s) ~= nil) or false
end

-- "3x [Mithril Bar]" or the service in brackets
function Market.Label(o)
  if o.it then
    local _, link = GuildOS.Compat.GetItemInfo(o.it)
    return (o.n > 1 and (o.n .. "x ") or "") .. (link or ("|cffffffff[" .. o.txt .. "]|r"))
  end
  local s = Market.ServiceOf(o.txt)
  return "|cff80c0ff[" .. (s and Market.ServiceName(s) or o.txt) .. "]|r"
end

function Market.Icon(o)
  if o.it then
    local instant = (C_Item and C_Item.GetItemInfoInstant) or GetItemInfoInstant
    local icon = instant and select(5, instant(o.it))
    return icon or QUESTION
  end
  local s = o.txt and Market.ServiceOf(o.txt)
  return s and s.icon or QUESTION
end

-- who wants an offer (sorted), how many they want (partial answers), and whether I do
function Market.WantsOf(o)
  local g = Market.G()
  local out, qty, mine = {}, {}, false
  for _, w in pairs(g and g.wants or {}) do
    if w.o == o.id and w.st == "in" then
      out[#out + 1] = w.who
      qty[w.who] = w.q
      if w.who == Me() then mine = true end
    end
  end
  table.sort(out)
  return out, mine, qty
end

-- the want record of one member on one post, or nil
function Market.WantRec(o, who)
  local g = Market.G()
  return g and g.wants[o.id .. "#" .. who] or nil
end

-- how many posts I have up (for the cap and the Mine count)
function Market.MineCount()
  local g = Market.G()
  local n = 0
  for _, o in pairs(g and g.offers or {}) do
    if o.by == Me() and Market.Live(o) then n = n + 1 end
  end
  return n
end

function Market.CountOffers()
  local g = Market.G()
  local n = 0
  for _, o in pairs(g and g.offers or {}) do
    if Market.Live(o) and o.by ~= Me() and not Market.IsMuted(o.by) then n = n + 1 end
  end
  return n
end

-- "5g 20s 3c", "5g", or a plain number (gold) to copper; nil when there is no price in it
function Market.ParsePrice(text)
  text = (text or ""):lower()
  if text:match("^%s*$") then return nil end
  local g = tonumber(text:match("(%d+)%s*g")) or 0
  local s = tonumber(text:match("(%d+)%s*s")) or 0
  local c = tonumber(text:match("(%d+)%s*c")) or 0
  if g == 0 and s == 0 and c == 0 then
    local plain = tonumber(text:match("^%s*(%d+)%s*$"))
    if not plain then return nil end
    g = plain
  end
  return g * 10000 + s * 100 + c
end

-- copper as gold, silver and copper, for the lines that show a price
function Market.FormatPrice(cu)
  if not cu then return nil end
  local g, s, c = math.floor(cu / 10000), math.floor(cu / 100) % 100, cu % 100
  local out = {}
  if g > 0 then out[#out + 1] = g .. "g" end
  if s > 0 then out[#out + 1] = s .. "s" end
  if c > 0 or #out == 0 then out[#out + 1] = c .. "c" end
  return table.concat(out, " ")
end

---------------------------------------------------------------- changing what I put up
local function Stamp(rec)
  rec.rev = (rec.rev or 0) + 1
  rec.u = math.max(Now(), rec.u or 0)
  rec.ed = Me()
end

-- text: an item link, an item name or a service; pickedIt: an item picked from the field;
-- seek: a request ("Looking for") instead of an offer. Returns the post, or nil and why it was refused.
function Market.Create(text, n, price, note, pickedIt, seek)
  local g, me = Market.G(), Me()
  if not g then return nil, L["Join a guild first."] end
  if Market.MineCount() >= CAP then
    return nil, L["You have %d posts up, the most one member can have. Remove one first."]:format(CAP)
  end
  text = strtrim(text or "")
  local it = pickedIt or tonumber(text:match("item:(%d+)"))
  local name = text:match("|h%[(.-)%]|h")
  if it and not name then name = GuildOS.Compat.GetItemInfo(it) end
  if not it and text ~= "" then
    -- a typed name of an item the client knows, else a service or plain text
    it = Market.ExactItem(text)
    if it then name = GuildOS.Compat.GetItemInfo(it) or text end
  end
  name = Clean(name or text):sub(1, 100)
  if name == "" then return nil, L["Write what you offer or want first."] end
  local cu = Market.ParsePrice(price)
  if strtrim(price or "") ~= "" and not cu then
    return nil, L["Not a price. Write it like 5g 20s 3c, or leave it empty."]
  end

  -- the same thing already up from me: say so, and post it anyway
  local lname = name:lower()
  for _, x in pairs(g.offers) do
    if x.by == me and Market.Live(x) and Market.IsRequest(x) == (seek and true or false)
      and ((it and x.it == it) or (not it and x.txt:lower() == lname)) then
      GuildOS:Print(L["You already have %s up. It is posted again."]:format(name))
      break
    end
  end

  local t = Now()
  local function field(s, max) s = Clean(s):sub(1, max); return s ~= "" and s or nil end
  local o = {
    id = ("%s:%d:%d"):format(me, t, math.random(1000, 9999)) .. (seek and ":s" or ""),
    by = me, it = it, txt = name,
    n = it and math.max(1, math.min(1000, math.floor(tonumber(n) or 1))) or 1,
    pr = field(price, 30), prc = cu, note = field(note, 150),
    st = "open", c = t, u = t, rev = 1, ed = me,
  }
  if seek and it and Market.Crafters(it) then
    GuildOS:Print(L["Someone in the guild can make %s. Craft orders are in the Crafts tab."]:format(name))
  end
  g.offers[o.id] = o
  Market.Send_M(o)
  Market.Changed()
  return o
end

local warned = {} -- offer id -> true once its "ends soon" line was printed

-- my own change to my post; the post goes out again with the new revision
local function EditMine(o, changes)
  if o.by ~= Me() then return end
  for k, v in pairs(changes) do if v == false then o[k] = nil else o[k] = v end end -- false clears a field
  o.mod = nil -- my own change, not an officer's take-down
  warned[o.id] = nil
  Stamp(o)
  Market.Send_M(o)
  Market.Changed()
end

function Market.Sold(o) EditMine(o, { st = "sold" }) end
function Market.Remove(o) EditMine(o, { st = "gone" }) end
-- still wanted: puts it up for another week
function Market.Renew(o) EditMine(o, {}) end

-- a new price for my post, in place: "" clears it; text that does not read as a price is refused
function Market.SetPrice(o, text)
  if not o or o.by ~= Me() then return nil, L["That is not your post."] end
  text = strtrim(text or "")
  local cu = Market.ParsePrice(text)
  if text ~= "" and not cu then return nil, L["Not a price. Write it like 5g 20s 3c, or leave it empty."] end
  local shown = Clean(text):sub(1, 30)
  EditMine(o, { pr = shown ~= "" and shown or false, prc = cu or false })
  return o
end

-- an officer takes a post down that breaks the guild's rules; the owner's copy says so
function Market.Moderate(o)
  if not GuildOS:IsOfficer() or o.by == Me() then return end
  local g = Market.G()
  if not g then return end
  local cur = g.offers[o.id] or o
  cur.mod = Me()
  cur.st = "gone"
  Stamp(cur)
  Market.Send_M(cur)
  Market.Changed()
end

-- "I want it" / "I have it": qty is how many I can give (partial answers), nil for all of it
local function SetWant(o, st, qty)
  local g, me = Market.G(), Me()
  if not g then return end
  local id = o.id .. "#" .. me
  local w = g.wants[id]
  if not w then
    w = { id = id, o = o.id, who = me, c = Now(), rev = 0 }
    g.wants[id] = w
  end
  w.st = st
  w.q = qty
  Stamp(w)
  Market.Send_W(w)
  Market.Changed()
end

-- my own offer is not mine to want: the tab offers no such button, and nothing else may do it either
function Market.Want(o)
  if o.by == Me() or not Market.Live(o) then return end
  local qty
  if Market.IsRequest(o) then
    local have = Market.Have(o)
    if have > 0 then qty = math.min(have, o.n) end
  end
  SetWant(o, "in", qty)
end

function Market.Unwant(o) SetWant(o, "out", nil) end

-- the line the whisper starts with: a question about the post, written in the player's words
function Market.WhisperText(o)
  if Market.IsRequest(o) then return L["Hi, I have %s, do you still need it?"]:format(o.txt) end
  return L["Hi, is your %s still available?"]:format(o.txt)
end

function Market.Whisper(o)
  if not ChatFrame_OpenChat then return end
  ChatFrame_OpenChat("/w " .. GuildOS:WhisperTarget(Short(o.by) or o.by) .. " " .. Market.WhisperText(o))
end

function Market.Purge()
  local g = Market.G()
  if not g then return end
  for id, o in pairs(g.offers) do if Market.Expired(o) then g.offers[id] = nil end end
  for id, w in pairs(g.wants) do
    if not g.offers[w.o] or Now() - (w.u or 0) > KEEP_OFFER + KEEP_GONE then g.wants[id] = nil end
  end
end

-- my posts that end within a day get one line each, once: renew them to keep them up
function Market.CheckMine()
  local g = Market.G()
  if not g then return end
  for id, o in pairs(g.offers) do
    if o.by == Me() and o.st == "open" and Now() - (o.u or 0) > KEEP_OFFER - DAY and not warned[id] then
      warned[id] = true
      GuildOS:Print(L["%s ends within a day. Renew it on the Marketplace tab to keep it up."]:format(Market.Label(o)))
    end
  end
end

---------------------------------------------------------------- callbacks for the tab
-- the tab repaints itself through this one hook (set by UI/MarketPanel.lua): a rebuilt window
-- replaces it rather than adding another
Market.uiRefresh = nil
function Market.Changed()
  if Market.uiRefresh then GuildOS:SafeCall(Market.uiRefresh) end
end

---------------------------------------------------------------- notices
local quietUntil, quietCount = 0, 0
function Market.IsQuiet() return GetTime() < quietUntil end

local function Ding()
  if PlaySound then pcall(PlaySound, SOUNDKIT and SOUNDKIT.READY_CHECK or 8960, "Master") end
end

local function Popup(o, kind) if Market.ShowPopup then Market.ShowPopup(o, kind) end end

-- a new offer or request from someone else: a line in chat, a sound and the popup (per the switches)
function Market.OnOfferChanged(o, old)
  if old or Now() - (o.u or 0) > MAX_AGE or o.by == Me() or o.st ~= "open" then return end
  if Market.IsMuted(o.by) then return end
  if Market.IsQuiet() then quietCount = quietCount + 1 return end
  local p = Market.Prefs()
  local seek = Market.IsRequest(o)
  local have = seek and Market.Have(o) or 0
  local can = Market.SeekForMe(o)
  local notify
  if seek then notify = p.notifyRequests else notify = p.notifyOffers end
  -- a request for something I carry or can do always comes, with a sound
  if notify or have > 0 or can then
    local why = ""
    if have > 0 then why = " |cff40ff40" .. L["You have %d of it"]:format(have) .. "|r"
    elseif can then why = " |cff40ff40" .. L["You can do this"] .. "|r" end
    local line = (seek and L["%s is looking for %s"] or L["%s is offering %s"]):format(Market.ColorName(o.by), Market.Label(o))
    GuildOS:Print(line .. (o.pr and (" |cffffd100" .. o.pr .. "|r") or "") .. why)
  end
  if have > 0 or can then Ding() end
  if not Market.ItemHidden(o) then Popup(o, seek and "seek" or "offer") end
end

-- someone wants my offer, or has my request: a line, a sound and a popup with "Sold" on it
function Market.OnWantChanged(w, old)
  if Now() - (w.u or 0) > MAX_AGE or w.who == Me() or Market.IsMuted(w.who) then return end
  local g = Market.G()
  local o = g and g.offers[w.o]
  if not o or o.by ~= Me() or not Market.Live(o) then return end
  local was = old and old.st == "in"
  local seek = Market.IsRequest(o)
  if w.st == "in" and not was then
    if Market.IsQuiet() then quietCount = quietCount + 1 return end
    local qty = w.q and (" (" .. w.q .. ")") or ""
    GuildOS:Print((seek and L["%s has it: %s"] or L["%s wants it: %s"]):format(Market.ColorName(w.who), Market.Label(o)) .. qty)
    Ding()
    if Market.ShowWantPopup and not Market.ItemHidden(o) then Market.ShowWantPopup(o, w) end
  elseif w.st == "out" and was and not Market.IsQuiet() then
    GuildOS:Print((seek and L["%s no longer has it: %s"] or L["%s no longer wants it: %s"]):format(Market.ColorName(w.who), Market.Label(o)))
  end
end

---------------------------------------------------------------- sharing
local function SafeName(s)
  return type(s) == "string" and #s > 0 and #s <= 64 and not s:find("[|:%c]") and not s:find("^%s")
end
local function SafeText(s, max)
  if type(s) ~= "string" or #s > (max or 200) then return false end
  return not s:gsub("||", ""):find("|", 1, true)
end
local function Num(v, lo, hi) return type(v) == "number" and v == v and v >= lo and v <= hi end
local function OptNum(v, lo, hi) return v == nil or Num(v, lo, hi) end

local function Encode(msg)
  return Deflate:EncodeForWoWAddonChannel(Deflate:CompressDeflate(Ser:Serialize(msg)))
end

local function Decode(text)
  local raw = Deflate:DecodeForWoWAddonChannel(text)
  raw = raw and Deflate:DecompressDeflate(raw)
  if not raw then return nil end
  local ok, msg = Ser:Deserialize(raw)
  if ok and type(msg) == "table" then return msg end
end

local function Send(msg, prio)
  if not IsInGuild() or not Market.G() or not Market.Enabled() then return end
  msg.v = PROTO
  msg.av = GuildOS.VERSION
  comm:SendCommMessage(Market.PREFIX, Encode(msg), "GUILD", nil, prio or "NORMAL")
end

-- an offer comes from its owner; an officer's take-down comes from the officer, and only that
local OFFER_STATES = { open = true, sold = true, gone = true }
local function ValidOffer(o, sender, relay)
  if type(o) ~= "table" or not SafeName(o.by) then return false end
  local editor = o.mod or o.by
  if o.ed ~= editor then return false end
  if o.mod ~= nil then
    if not SafeName(o.mod) or o.mod == o.by or o.st ~= "gone" then return false end
    if not GuildOS:IsOfficerByName(o.mod) then return false end
    if not relay and o.mod ~= sender then return false end
  elseif not relay and o.by ~= sender then
    return false
  end
  if type(o.id) ~= "string" or #o.id > 120 or o.id:sub(1, #o.by + 1) ~= o.by .. ":" then return false end
  if not SafeText(o.txt, 120) or #o.txt == 0 or (o.note ~= nil and not SafeText(o.note, 200))
    or (o.pr ~= nil and not SafeText(o.pr, 40)) then return false end
  if not OFFER_STATES[o.st] or not Num(o.n, 1, 1000) or not OptNum(o.it, 1, 1e7) then return false end
  if not OptNum(o.prc, 0, 1e12) then return false end
  local soon = Now() + DAY
  if not Num(o.c, 0, soon) or not Num(o.u, 0, soon) or not Num(o.rev, 0, 1e6) then return false end
  return true
end

local function ValidWant(w, sender, relay)
  if type(w) ~= "table" or not SafeName(w.who) or w.ed ~= w.who then return false end
  if type(w.o) ~= "string" or #w.o > 120 or w.id ~= w.o .. "#" .. w.who then return false end
  if w.st ~= "in" and w.st ~= "out" then return false end
  if not OptNum(w.q, 0, 1000) then return false end
  local soon = Now() + DAY
  if not Num(w.c, 0, soon) or not Num(w.u, 0, soon) or not Num(w.rev, 0, 1e6) then return false end
  if not relay and w.who ~= sender then return false end
  return true
end

local function TooMany(store, by)
  local n = 0
  for _, o in pairs(store) do
    if (o.by or o.who) == by then n = n + 1; if n >= CAP then return true end end
  end
  return false
end

---------------------------------------------------------------- de-duplicated sending
local queue, heard, flushing = {}, {}, false

local function HeardRecently(key, ver)
  local h = heard[key]
  return h and h.ver >= ver and GetTime() - h.at < HEARD_FOR
end

local function Flush()
  flushing = false
  for key, q in pairs(queue) do
    if not HeardRecently(key, q.ver) then
      Send(q.msg, "BULK")
      heard[key] = { ver = q.ver, at = GetTime() }
    end
  end
  wipe(queue)
end

local function Queue(key, ver, msg)
  if HeardRecently(key, ver) then return end
  queue[key] = { msg = msg, ver = ver }
  if not flushing then
    flushing = true
    C_Timer.After(1.5 + math.random() * 5, Flush)
  end
end

local function Heard(key, ver)
  local h = heard[key]
  if not h or h.ver <= ver then heard[key] = { ver = ver, at = GetTime() } end
  local q = queue[key]
  if q and q.ver <= ver then queue[key] = nil end
end

function Market.Send_M(o)
  Heard("M:" .. o.id, o.rev)
  Send({ k = "M", o = o })
end

function Market.Send_W(w)
  Heard("W:" .. w.id, w.rev)
  Send({ k = "W", o = w })
end

local lastHello = 0
function Market.SendHello(force)
  local g = Market.G()
  if not g then return end
  if not force and GetTime() - lastHello < 60 then return end
  lastHello = GetTime()
  local offers, wants = {}, {}
  for id, o in pairs(g.offers) do offers[id] = o.rev or 0 end
  for id, w in pairs(g.wants) do wants[id] = w.rev or 0 end
  Send({ k = "H", m = offers, w = wants })
end

---------------------------------------------------------------- incoming
-- A relayed copy can't prove who wrote it: ignore copies of my own offers (I have the real
-- ones), and changes by someone who is online right now (they send it themselves).
local function TrustRelay(author, old)
  if not old then return true end
  if author == Me() then return false end
  return not Market.IsOnline(author)
end

local FIELDS = {
  M = { "id", "by", "it", "txt", "n", "pr", "prc", "note", "st", "c", "u", "rev", "ed", "mod" },
  W = { "id", "o", "who", "st", "q", "c", "u", "rev", "ed" },
}

-- the newer of two copies: the higher revision, then the later change
local function Newer(a, b)
  if (a.rev or 0) ~= (b.rev or 0) then return (a.rev or 0) > (b.rev or 0) end
  return (a.u or 0) > (b.u or 0)
end

local function OnRecord(msg, sender, kind)
  local g = Market.G()
  if not g then return end
  local store = kind == "M" and g.offers or g.wants
  local r = msg.o
  local valid = kind == "M" and ValidOffer or ValidWant
  if not valid(r, sender, msg.relay) then return end
  local author = kind == "M" and r.by or r.who
  if (kind == "M" and Market.Expired(r)) or not Market.InGuild(author) then return end
  Heard(kind .. ":" .. r.id, r.rev)
  local old = store[r.id]
  if old and not Newer(r, old) then return end
  if msg.relay and not TrustRelay(author, old) then return end
  if not old and TooMany(store, author) then return end
  local copy = {}
  for _, f in ipairs(FIELDS[kind]) do copy[f] = r[f] end
  store[r.id] = copy
  if not msg.relay then
    if kind == "M" then
      Market.OnOfferChanged(copy, old)
      -- an officer took my post down
      if copy.mod and copy.by == Me() and not (old and old.mod) then
        GuildOS:Print(L["An officer took your %s off the Marketplace."]:format(Market.Label(copy)))
      end
    else
      Market.OnWantChanged(copy, old)
    end
  end
  Market.Changed()
end

-- what they have of one kind against mine: queue what I have newer, true when they have newer
local function Compare(mine, theirs, kind, live)
  local theyHaveNewer = false
  for id, r in pairs(mine) do
    local t = type(theirs[id]) == "number" and theirs[id] or nil
    if live(r) and (not t or (r.rev or 0) > t) then
      Queue(kind .. ":" .. id, r.rev or 0, { k = kind, o = r, relay = true })
    elseif t and t > (r.rev or 0) then
      theyHaveNewer = true
    end
  end
  for id in pairs(theirs) do if not mine[id] then return true end end
  return theyHaveNewer
end

local function OnHello(msg)
  local g = Market.G()
  if not g or type(msg.m) ~= "table" or type(msg.w) ~= "table" then return end
  local newer = Compare(g.offers, msg.m, "M", function(o) return not Market.Expired(o) end)
  newer = Compare(g.wants, msg.w, "W", function(w) return g.offers[w.o] ~= nil end) or newer
  if newer then C_Timer.After(2 + math.random() * 4, function() Market.SendHello() end) end
end

comm:RegisterComm(Market.PREFIX, function(_, text, dist, sender)
  if dist ~= "GUILD" or not Market.Enabled() then return end
  sender = Short(sender)
  if not sender or sender == Me() or not Market.G() or not Market.InGuild(sender) then return end
  local msg = Decode(text)
  if not msg or msg.v ~= PROTO then return end
  GuildOS:SafeCall(function()
    if msg.k == "M" or msg.k == "W" then OnRecord(msg, sender, msg.k)
    elseif msg.k == "H" then OnHello(msg) end
  end)
end)

---------------------------------------------------------------- startup
local started = false
function Market.Start(tries)
  if started or not Market.Enabled() or not IsInGuild() then return end
  if not Market.G() then
    if (tries or 0) < 30 then C_Timer.After(2, function() Market.Start((tries or 0) + 1) end) end
    return
  end
  started = true
  if C_GuildInfo and C_GuildInfo.GuildRoster then C_GuildInfo.GuildRoster() elseif GuildRoster then GuildRoster() end
  Market.ReadRoster()
  Market.Purge()
  -- the first minute after login: changes are counted, and told once
  quietUntil = GetTime() + QUIET
  C_Timer.After(5, function() Market.SendHello(true) end)
  C_Timer.After(QUIET + 1, function()
    if quietCount > 0 then
      GuildOS:Print(L["%d posts and answers came in from the guild while you were away. See the Marketplace tab."]:format(quietCount))
    end
    quietCount = 0
    Market.CheckMine()
  end)
  -- the item names: a slow walk over the game's items, out of combat (MarketItems.lua)
  if Market.StartItemWalk then C_Timer.After(20, Market.StartItemWalk) end
end

local ev = CreateFrame("Frame")
ev:RegisterEvent("PLAYER_LOGIN")
ev:RegisterEvent("PLAYER_GUILD_UPDATE")
ev:RegisterEvent("GUILD_ROSTER_UPDATE")
local rosterQueued, lastRoster = false, -1e9
ev:SetScript("OnEvent", function(_, event)
  if event == "PLAYER_LOGIN" then
    C_Timer.After(5, function() Market.Start() end)
  elseif event == "PLAYER_GUILD_UPDATE" then
    if not started then C_Timer.After(2, function() Market.Start() end) end
  elseif event == "GUILD_ROSTER_UPDATE" then
    -- fires often: read the roster at most every five seconds
    if not rosterQueued then
      rosterQueued = true
      C_Timer.After(math.max(0, lastRoster + 5 - GetTime()), function()
        rosterQueued, lastRoster = false, GetTime()
        Market.ReadRoster()
        Market.Changed()
      end)
    end
  end
end)

C_Timer.NewTicker(3600, function() Market.Purge(); Market.CheckMine(); Market.Changed() end)

-- the item a typed name means, when the client knows that exact name, or nil
function Market.ExactItem(text)
  if Market.FindExactItem then
    local it = Market.FindExactItem(text)
    if it then return it end
  end
  local _, link = GuildOS.Compat.GetItemInfo(text)
  return link and tonumber(link:match("item:(%d+)")) or nil
end
