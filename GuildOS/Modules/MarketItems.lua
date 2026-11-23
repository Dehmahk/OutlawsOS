----------------------------------------------------------------------
-- Guild OS - Marketplace: item names for the item field and its suggestions.
-- Ported from GuildOS_Unbroken's Items.lua and Search.lua by Christian (used with his agreement).
--
-- The game has no search by name, so the addon asks the client about every item number once and
-- keeps the names (per account, in the client's language). After the first walk only numbers
-- without a name are looked at again, after a game patch.
--
-- Kept light on purpose:
--  * the walk asks the server slowly (REQ_PER_SEC, never more than OPEN_MAX at once), because every
--    answer is an event every other addon listening to it handles too; not in combat, not in an
--    instance, and it runs only until all numbers are done (the first login: some minutes)
--  * only one string per item is kept: no poor (grey) items and no quest items, which nobody orders
--  * the search reads that table directly with a case-insensitive pattern: no copy of the list
----------------------------------------------------------------------
local Market = GuildOS.Market

local GetItemInfo = (C_Item and C_Item.GetItemInfo) or GetItemInfo
local GetItemInfoInstant = (C_Item and C_Item.GetItemInfoInstant) or GetItemInfoInstant
local Exists = C_Item and C_Item.DoesItemExistByID
local Request = C_Item and C_Item.RequestLoadItemDataByID

local MAX_ID = Exists and 80000 or 30000 -- Forever adds items above Classic's numbers
local REQ_PER_SEC = 25     -- server requests per second
local OPEN_MAX = 15        -- requests waiting for an answer at most
local CHECK_PER_STEP = 400 -- numbers looked at per step (no request needed for most)
local STEP = 0.1           -- seconds between steps
local QUEST_CLASS = 12

local db
local open, nOpen = {}, 0
local ticker
local budget = 0

-- the saved table for the walk: names by item number, and where the walk is
local function DB()
  if db then return db end
  if not GuildOS.db then return nil end
  GuildOS.db.marketItems = GuildOS.db.marketItems or {}
  db = GuildOS.db.marketItems
  local locale, build = GetLocale(), select(2, GetBuildInfo())
  if db.locale ~= locale then
    db.locale, db.names, db.next, db.build = locale, {}, 1, nil
  end
  db.names = db.names or {}
  db.next = db.next or 1
  if db.build ~= build then
    db.build, db.next = build, 1 -- a patch may bring new items: walk again (known ones are skipped)
  end
  return db
end

-- keep the item's name if it is one somebody could order; true when the client had the item
local function Keep(id)
  local name, _, quality = GetItemInfo(id)
  if type(name) ~= "string" or name == "" then return false end
  if db.names[id] then return true end
  if quality == 0 then return true end
  local classID = GetItemInfoInstant and select(6, GetItemInfoInstant(id))
  if classID == QUEST_CLASS then return true end
  db.names[id] = name
  return true
end

local function Busy()
  return InCombatLockdown() or IsInInstance()
end

local function Step()
  if Busy() or not db then return end
  -- requests that never got an answer: give up on them
  local now = GetTime()
  for id, at in pairs(open) do
    if now - at > 10 then open[id] = nil; nOpen = nOpen - 1 end
  end
  budget = math.min(REQ_PER_SEC, budget + REQ_PER_SEC * STEP)
  local checked = 0
  while db.next <= MAX_ID and checked < CHECK_PER_STEP and budget >= 1 and nOpen < OPEN_MAX do
    local id = db.next
    db.next = id + 1
    checked = checked + 1
    if not db.names[id] and (not Exists or Exists(id)) then
      if not Keep(id) then
        if Request then Request(id) end -- GetItemInfo above already asked on clients without it
        open[id] = now
        nOpen = nOpen + 1
        budget = budget - 1
      end
    end
  end
  if db.next > MAX_ID and nOpen == 0 and ticker then
    ticker:Cancel()
    ticker = nil
  end
end

-- started by Market.Start, after the login rush: asks for the numbers that have no name yet
function Market.StartItemWalk()
  if ticker or not DB() then return end
  if db.next > MAX_ID then return end
  ticker = C_Timer.NewTicker(STEP, Step)
end

-- answers to the walk, and any item another addon or the game loaded: one table lookup
local ev = CreateFrame("Frame")
ev:RegisterEvent("GET_ITEM_INFO_RECEIVED")
ev:SetScript("OnEvent", function(_, _, id, ok)
  if not db or type(id) ~= "number" then return end
  if open[id] then open[id] = nil; nOpen = nOpen - 1 end
  if ok ~= false and not db.names[id] then Keep(id) end
end)

---------------------------------------------------------------- search
-- "mith" -> "[mM][iI][tT][hH]": matches without lower-casing every name
local function Pattern(text)
  return (text:gsub("[%^%$%(%)%%%.%[%]%*%+%-%?]", "%%%0"):gsub("%a", function(c)
    return "[" .. c:lower() .. c:upper() .. "]"
  end))
end

-- up to `max` items whose name contains `text` (starting with it first): { { id, name }, ... }
function Market.FindItems(text, max)
  local out = {}
  if not db or #text < 3 then return out end
  local pat = Pattern(text)
  local starts, contains = {}, {}
  local limit = max * 4 -- enough to sort from, without collecting thousands for "ma"
  for id, name in pairs(db.names) do
    local at = name:find(pat)
    if at == 1 then
      if #starts < limit then starts[#starts + 1] = id end
    elseif at and #contains < limit then
      contains[#contains + 1] = id
    end
  end
  local names = db.names
  local function byName(a, b) return names[a] < names[b] end
  table.sort(starts, byName)
  table.sort(contains, byName)
  local seen = {}
  for _, list in ipairs({ starts, contains }) do
    for _, id in ipairs(list) do
      if #out >= max then return out end
      local lower = names[id]:lower()
      if not seen[lower] then
        seen[lower] = true
        out[#out + 1] = { id = id, name = names[id] }
      end
    end
  end
  return out
end

-- the item of an exactly typed name, any case, or nil
function Market.FindExactItem(text)
  if not db or not text or text == "" then return nil end
  local pat = "^" .. Pattern(text) .. "$"
  for id, name in pairs(db.names) do
    if name:find(pat) then return id end
  end
end

-- how many guild members can make an item (from the Crafts tab), for the suggestion lines
local function CrafterCount(it)
  local list = Market.Crafters(it)
  return list and #list or 0
end

-- the suggestion lines under the item field for a typed text: services first, then items with
-- the number of guild crafters. Each line: { name, icon, it = item id or nil, svc = service or nil,
-- crafters = n }. Up to `max` lines.
function Market.Suggest(text, max)
  max = max or 6
  local out = {}
  for _, s in ipairs(Market.SuggestServices(text)) do
    if #out >= max then return out end
    out[#out + 1] = { name = s.name, icon = s.icon, svc = s.svc, crafters = 0 }
  end
  for _, hit in ipairs(Market.FindItems(text, max)) do
    if #out >= max then break end
    local icon = GetItemInfoInstant and select(5, GetItemInfoInstant(hit.id))
    out[#out + 1] = { name = hit.name, icon = icon or "Interface\\Icons\\INV_Misc_Note_05", it = hit.id,
      crafters = CrafterCount(hit.id) }
  end
  return out
end
