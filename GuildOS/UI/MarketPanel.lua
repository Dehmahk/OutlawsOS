----------------------------------------------------------------------
-- Guild OS - The Marketplace tab (ported from GuildOS_Unbroken 2.3.3 by Christian, used with his
-- agreement). Two halves: "Offering" (items and services members put up) and "Looking for"
-- (what members ask the guild for). The form on top is one line with suggestions under the item
-- field, then the filters and the search, then the switches; each entry is a two-line row. The data
-- and the sharing are in Modules/Market.lua, the item names in Modules/MarketItems.lua.
-- Popups for new posts and for answers to my posts are at the bottom of this file.
----------------------------------------------------------------------
local Market = GuildOS.Market
local L = GuildOS.L
local UI = GuildOS.UI
local C = GuildOS.Colors

local TAB_H, TAB_MIN_W, TAB_PAD = 28, 90, 22
local ROW_H = 34
local BTN_W, BTN_H, FIELD_H = 72, 20, 22
local ACT_MAX = 4
local REPAINT_EVERY = 15
local SUGGEST_ROWS, SUGGEST_H = 6, 19
local GOLD = { 0.85, 0.66, 0.31 }
local PRICE_W, NEAR_CAP, STALE_ALPHA = 96, 5, 0.6 -- price column; amber this close to the cap; dimmed stale posts
local startPriceEdit -- set by the panel: "Change price" on my own post opens the form on its price

local function Me() return UnitName("player") end

-- the filter buttons; "For me" only reads for requests; "Muted" lists the members I muted and the
-- items whose popups I turned off
local FILTERS = {
    { key = "all", label = "All" },
    { key = "forme", label = "For me", requests = true },
    { key = "items", label = "Items" },
    { key = "services", label = "Services" },
    { key = "mine", label = "Mine" },
    { key = "muted", label = "Muted" },
}

-- the sort cycle: newest first, cheapest first (no price last), members online first
local SORTS = { "new", "price", "online" }
local SORT_LABEL = { new = "Sort: newest", price = "Sort: price", online = "Sort: online" }

local function isFilter(key)
    for _, f in ipairs(FILTERS) do if f.key == key then return true end end
    return false
end
local function isSort(key)
    for _, v in ipairs(SORTS) do if v == key then return true end end
    return false
end

local function Matches(o, filter, me, mine)
    local hidden = Market.IsMuted(o.by) or Market.ItemHidden(o)
    if filter == "muted" then return hidden end
    if Market.IsMuted(o.by) then return false end
    if filter == "all" then return true end
    if filter == "forme" then return Market.IsRequest(o) and not mine and o.by ~= me
        and (Market.Have(o) > 0 or Market.SeekForMe(o)) end
    if filter == "items" then return o.it ~= nil end
    if filter == "services" then return o.it == nil end
    if filter == "mine" then return o.by == me or mine end
    return true
end

-- the free text search: the name, the note and who posted it
local function Searched(o, q)
    if q == "" then return true end
    local s = (o.txt or "") .. " " .. (o.note or "") .. " " .. (o.by or "")
    return s:lower():find(q, 1, true) ~= nil
end

-- the buttons a row offers, at most ACT_MAX: { { label, fn }, ... }; fn takes the entry
local function Actions(o, me, mine)
    local out = {}
    local function add(label, fn) out[#out + 1] = { label, fn } end
    local seek = Market.IsRequest(o)
    if o.by == me then
        if Market.Age(o) > Market.OLD_AFTER then add(L["Renew"], Market.Renew) end
        add(L["Change price"], function(x) if startPriceEdit then startPriceEdit(x) end end)
        add(seek and L["Got it"] or L["Sold"], Market.Sold)
        add(L["Remove"], Market.Remove)
    else
        if seek and o.it and not mine and (Market.ICanCraft(o.it) or Market.Crafters(o.it)) then
            add(L["Craft it"], Market.OpenCrafts)
        end
        -- the same answer either way: "Want it" on an offer, "I have it" on a request
        if mine then add(seek and L["Not any more"] or L["Not wanted"], Market.Unwant)
        else add(seek and L["I have it"] or L["Want it"], Market.Want) end
        add(L["Whisper"], Market.Whisper)
        if GuildOS:IsOfficer() then add(L["Take down"], Market.Moderate) end
    end
    return out
end

-- the names of the members who can make an item, for the tooltip and the row
local function CrafterNames(it)
    local list = Market.Crafters(it) or {}
    local out, seen = {}, {}
    for _, c in ipairs(list) do
        local who = Market.Short(c.playerName or c.playerKey)
        if who and not seen[who] then
            seen[who] = true
            out[#out + 1] = { who, c.class }
        end
    end
    table.sort(out, function(a, b) return a[1] < b[1] end)
    return out
end

local function Tooltip(tt, o)
    local svc = not o.it and Market.ServiceOf(o.txt)
    if o.it then
        tt:SetHyperlink("item:" .. o.it)
    else
        tt:AddLine(svc and Market.ServiceName(svc) or o.txt, 0.5, 0.75, 1)
        tt:AddLine(svc and L["Done by guild members who have the skill."] or L["A service."], 0.7, 0.7, 0.7, true)
    end
    tt:AddLine(" ")
    local tag = Market.IsRequest(o) and L["Looking for"] or L["Offering"]
    tt:AddLine(tag .. "  " .. L["by %s"]:format(Market.ColorName(o.by)) .. "  ·  " .. GuildOS:TimeAgo(o.c), 1, 1, 1)
    if o.it and o.n > 1 then tt:AddLine(L["Quantity: %d"]:format(o.n), 1, 1, 1) end
    if o.pr then tt:AddLine(L["Price: %s"]:format(o.pr), GOLD[1], GOLD[2], GOLD[3]) end
    if o.note then tt:AddLine(o.note, 1, 1, 1, true) end
    local seek = Market.IsRequest(o)
    local have = seek and Market.Have(o) or 0
    if have > 0 then tt:AddLine(L["You have %d of it"]:format(have), 0.25, 1, 0.25) end
    -- who makes an item (from the Crafts tab)
    if o.it then
        local crafters = CrafterNames(o.it)
        if #crafters > 0 then
            tt:AddLine(" ")
            tt:AddLine(L["Made by guild members"], GOLD[1], GOLD[2], GOLD[3])
            for i, c in ipairs(crafters) do
                if i > 10 then break end
                tt:AddLine(Market.ColorName(c[1], c[2]), 1, 1, 1)
            end
        end
    end
    local wants, _, qty = Market.WantsOf(o)
    if #wants > 0 then
        tt:AddLine(" ")
        tt:AddLine(seek and L["Has it"] or L["Wanted by"], GOLD[1], GOLD[2], GOLD[3])
        for _, who in ipairs(wants) do
            local on = Market.IsOnline(who)
            local left = Market.ColorName(who) .. (qty[who] and ("  (" .. qty[who] .. ")") or "")
            tt:AddDoubleLine(left, on and L["Online"] or L["Offline"],
                1, 1, 1, on and 0.25 or 0.5, on and 1 or 0.5, on and 0.25 or 0.5)
        end
    end
    -- a request for a known service: who in the guild can do it, and at what rank
    if seek and svc then
        local people = Market.ServicePeople(svc)
        if #people > 0 then
            tt:AddLine(" ")
            tt:AddLine(L["Can do it"], GOLD[1], GOLD[2], GOLD[3])
            for i, p in ipairs(people) do
                if i > 10 then break end
                local left = Market.ColorName(p[1])
                if p.rank then left = left .. "  " .. p.rank .. "/" .. (p.max or "?") end
                tt:AddDoubleLine(left, p[2] and L["Online"] or L["Offline"],
                    1, 1, 1, p[2] and 0.25 or 0.5, p[2] and 1 or 0.5, p[2] and 0.25 or 0.5)
            end
        end
    end
    tt:AddLine(" ")
    tt:AddLine(L["Right-click: mute or unmute the member"], 0.6, 0.6, 0.6)
end

-- a row's two lines: the tag, the item or service, the quantity; then who, when, who wants it, and
-- "old" once the post is past its week. The price is a column of its own: the third value.
local function RowText(o, me, wants, mine, qty)
    local seek = Market.IsRequest(o)
    local tag = seek and ("|cffff9933" .. L["Looking for"] .. "|r") or ("|cff40c040" .. L["Offering"] .. "|r")
    local stale = Market.Age(o) > Market.OLD_AFTER
    local title = tag .. "  " .. Market.Label(o)
        .. ((o.it and o.n and o.n > 1) and ("  |cffaaaaaa×" .. o.n .. "|r") or "")
        .. (o.it and "" or ("  |cff888888" .. L["Service"] .. "|r"))
        .. (stale and ("  |cff888888" .. L["old"] .. "|r") or "")
    local meta = { L["by %s"]:format(Market.ColorName(o.by)), GuildOS:TimeAgo(o.c) }
    if #wants > 0 then
        local names = {}
        for j = 1, math.min(3, #wants) do
            names[j] = Market.ColorName(wants[j]) .. (qty[wants[j]] and (" " .. qty[wants[j]]) or "")
        end
        meta[#meta + 1] = (seek and L["%d have it: %s"] or L["%d want it: %s"]):format(#wants,
            table.concat(names, ", ") .. (#wants > 3 and " …" or ""))
    end
    if mine then meta[#meta + 1] = "|cff40ff40" .. (seek and L["You have it"] or L["You want it"]) .. "|r" end
    local have = (seek and o.by ~= me and not mine) and Market.Have(o) or 0
    if have > 0 then meta[#meta + 1] = "|cff40ff40" .. L["You have %d of it"]:format(have) .. "|r"
    elseif not mine and Market.SeekForMe(o) then meta[#meta + 1] = "|cff40ff40" .. L["You can do this"] .. "|r" end
    if o.note then meta[#meta + 1] = "|cffffffff\"" .. o.note .. "\"|r" end
    local price = o.pr and ("|cffffd100" .. o.pr .. "|r") or ""
    return title, table.concat(meta, "  ·  "), price
end

-- the one row a group of the same item gets: its name, how many posts, and who posted them
local function GroupText(grp)
    local first = grp.items[1].o
    local posters, seen = {}, {}
    for _, e in ipairs(grp.items) do
        if not seen[e.o.by] then seen[e.o.by] = true; posters[#posters + 1] = e.o.by end
    end
    local names = {}
    for j = 1, math.min(3, #posters) do names[j] = Market.ColorName(posters[j]) end
    local tag = Market.IsRequest(first) and ("|cffff9933" .. L["Looking for"] .. "|r")
        or ("|cff40c040" .. L["Offering"] .. "|r")
    local title = tag .. "  " .. Market.Label(first) .. "  |cffaaaaaa" .. L["%d posts"]:format(#grp.items) .. "|r"
    local meta = L["by %s"]:format(table.concat(names, ", ") .. (#posters > 3 and " …" or ""))
    return title, meta
end

function GuildOS:CreateMarketPanel(parent)
    -- the view the tab was left in (sub-tab, filter, sort) is the view it comes back in
    local saved = (GuildOS.db and GuildOS.db.marketView) or {}
    local filter = isFilter(saved.filter) and saved.filter or "all"
    local sortMode = isSort(saved.sort) and saved.sort or "new"
    local search = ""
    local expanded = {} -- item key -> true, for the groups opened by a click
    local editing      -- my post whose price the form is changing, else nil
    local refresh
    parent.activeSub = saved.sub == "seek" and "seek" or "offer"

    local function saveView()
        if GuildOS.db then GuildOS.db.marketView = { sub = parent.activeSub, filter = filter, sort = sortMode } end
    end

    ------------------------------------------------------------------
    -- Sub-tabs (their labels carry the live count, see refresh)
    ------------------------------------------------------------------
    local bar = CreateFrame("Frame", nil, parent)
    bar:SetPoint("TOPLEFT", 10, -8)
    bar:SetSize(400, TAB_H)
    UI:StyleSubTabBar(bar)
    local subTabs, subList = {}, {}
    local tabNames = { offer = L["Offering"], seek = L["Looking for"] }
    local tabShown = {}

    ------------------------------------------------------------------
    -- Line 1: the form. An item (dragged in, shift-clicked, typed, or picked from the suggestions) or
    -- a service, how many, a price, a note. Posted under the sub-tab it is on. The item takes about a
    -- third of the line, the note what is left. Under the price: what it reads as. Under the form: why
    -- a post was refused.
    ------------------------------------------------------------------
    local form = CreateFrame("Frame", nil, parent)
    form:SetPoint("TOPLEFT", bar, "BOTTOMLEFT", 0, -UI.GAP)
    form:SetPoint("TOPRIGHT", bar, "BOTTOMRIGHT", -UI.GAP, -UI.GAP)
    form:SetHeight(FIELD_H)

    local itemBox = UI:CreateInput(form, 240, FIELD_H, { max = 100, placeholder = L["Item, link or service (drop an item here)"] })
    itemBox:SetPoint("LEFT", 0, 0)
    local qtyBox = UI:CreateInput(form, 40, FIELD_H, { numeric = true, max = 4 })
    qtyBox:SetPoint("LEFT", itemBox, "RIGHT", 4, 0)
    qtyBox:SetText("1")
    UI:AddTooltip(qtyBox, L["Quantity"], { L["How many of the item you put up."] })
    local priceBox = UI:CreateInput(form, 110, FIELD_H, { max = 30, placeholder = L["Price (optional)"] })
    priceBox:SetPoint("LEFT", qtyBox, "RIGHT", 4, 0)
    UI:AddTooltip(priceBox, L["Price"], { L["Gold, silver, copper: 5g 20s 3c. A plain number is gold."] })
    local noteBox = UI:CreateInput(form, 160, FIELD_H, { max = 150, placeholder = L["Note (optional)"] })
    noteBox:SetPoint("LEFT", priceBox, "RIGHT", 4, 0)
    local postBtn = UI:CreateButton(form, L["Post"], 90, FIELD_H)
    UI:SetButtonVariant(postBtn, "primary")
    postBtn:SetPoint("RIGHT", 0, 0)
    noteBox:SetPoint("RIGHT", postBtn, "LEFT", -6, 0)
    form:SetScript("OnSizeChanged", function()
        local w = form:GetWidth() or 0
        if w > 0 then itemBox:SetWidth(math.max(200, math.floor(w * 0.36))) end
    end)

    local priceHint = UI:CreateText(form, "", 10, C.textDim.r, C.textDim.g, C.textDim.b)
    priceHint:SetPoint("TOPLEFT", priceBox, "BOTTOMLEFT", 6, -3)
    local formMsg = UI:CreateText(form, "", 11, C.warn.r, C.warn.g, C.warn.b)
    formMsg:SetPoint("TOPLEFT", form, "BOTTOMLEFT", 0, -3)
    formMsg:SetPoint("RIGHT", priceBox, "LEFT", -10, 0)
    formMsg:SetHeight(26)
    formMsg:SetJustifyH("LEFT")
    formMsg:SetJustifyV("TOP")
    formMsg:SetWordWrap(true)

    local function say(msg) formMsg:SetText(msg or "") end

    local function readPrice()
        local t = strtrim(priceBox:GetText() or "")
        if t == "" then priceHint:SetText("") return end
        local cu = Market.ParsePrice(t)
        if cu then
            priceHint:SetText(L["Reads as %s"]:format(Market.FormatPrice(cu)))
            priceHint:SetTextColor(GOLD[1], GOLD[2], GOLD[3])
        else
            priceHint:SetText(L["Not a price"])
            priceHint:SetTextColor(C.warn.r, C.warn.g, C.warn.b)
        end
    end
    priceBox:HookScript("OnTextChanged", function(_, userInput)
        readPrice()
        if userInput then say("") end
    end)
    qtyBox:HookScript("OnTextChanged", function(_, userInput) if userInput then say("") end end)
    noteBox:HookScript("OnTextChanged", function(_, userInput) if userInput then say("") end end)

    local picked -- { id, text }: the item taken (dropped, shift-clicked, picked), while the field shows it

    local function SetItem(id, link)
        local name, l = GuildOS.Compat.GetItemInfo(id)
        link = link or l
        picked = { id = id, text = link or name or ("item:" .. id) }
        itemBox.quiet = true
        itemBox:SetText(picked.text)
        itemBox.quiet = nil
        itemBox:ClearFocus()
        priceBox:SetFocus()
    end

    -- an item on the cursor (dragged from the bags) goes into the form
    local function TakeCursor()
        local kind, id, link = GetCursorInfo()
        if kind ~= "item" or not id then return false end
        ClearCursor()
        SetItem(id, link)
        return true
    end
    itemBox:SetScript("OnReceiveDrag", TakeCursor)
    itemBox:HookScript("OnMouseUp", function() TakeCursor() end)

    -- the suggestion list under the item field: services and items (with crafters), as I type
    local dd = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    dd:SetFrameStrata("DIALOG")
    dd:SetWidth(240)
    dd:SetPoint("TOPLEFT", itemBox, "BOTTOMLEFT", 0, -2)
    UI:StylePopup(dd, { noFade = true })
    dd:Hide()
    local ddRows = {}
    for i = 1, SUGGEST_ROWS do
        local b = UI:CreateButton(dd, "", 228, BTN_H)
        b:SetPoint("TOPLEFT", 6, -5 - (i - 1) * SUGGEST_H)
        b:Hide()
        ddRows[i] = b
    end

    local function pick(s)
        dd:Hide()
        if s.it then
            SetItem(s.it, nil)
        else
            picked = nil
            itemBox.quiet = true
            itemBox:SetText(s.name)
            itemBox.quiet = nil
            itemBox:ClearFocus()
            priceBox:SetFocus()
        end
    end

    local function suggest()
        local text = strtrim(itemBox:GetText() or "")
        if (picked and itemBox:GetText() == picked.text) or #text < 3 or not itemBox:HasFocus() then
            dd:Hide()
            return
        end
        local list = Market.Suggest(text, SUGGEST_ROWS)
        if #list == 0 then dd:Hide() return end
        local dw = itemBox:GetWidth() or 240
        dd:SetWidth(dw)
        for i, b in ipairs(ddRows) do
            local s = list[i]
            if s then
                local tail = (s.crafters and s.crafters > 0) and ("  |cff40ff40" .. L["%d can make it"]:format(s.crafters) .. "|r") or ""
                b.label:SetText(s.name .. tail)
                b:SetWidth(dw - 12)
                b:SetScript("OnClick", function() pick(s) end)
                b:Show()
            else
                b:Hide()
            end
        end
        dd:SetHeight(#list * SUGGEST_H + 10)
        dd:Show()
    end

    itemBox:HookScript("OnTextChanged", function(self, userInput)
        if self.quiet then return end
        if userInput then picked = nil; say("") end
        suggest()
    end)
    itemBox:HookScript("OnEditFocusGained", suggest)
    itemBox:HookScript("OnEditFocusLost", function()
        C_Timer.After(0.2, function() if not dd:IsMouseOver() then dd:Hide() end end)
    end)

    -- shift-click an item while the tab is open: it goes into the form, unless a chat line is typed.
    -- One hook for the session; it calls the form of the window built last.
    Market.takeLink = function(link)
        if type(link) ~= "string" or not parent:IsVisible() or not IsShiftKeyDown() then return end
        local id = tonumber(link:match("item:(%d+)"))
        if not id then return end
        local chat = ChatEdit_GetActiveWindow and ChatEdit_GetActiveWindow()
        if chat and not itemBox:HasFocus() then return end
        SetItem(id, link)
    end
    if HandleModifiedItemClick and not Market.clickHooked then
        Market.clickHooked = true
        hooksecurefunc("HandleModifiedItemClick", function(link)
            if Market.takeLink then Market.takeLink(link) end
        end)
    end

    -- changing the price of one of my posts: the form takes that price, Save puts it on the post
    local function endEdit()
        editing = nil
        postBtn.label:SetText(L["Post"])
        priceBox:SetText("")
        say("")
    end
    startPriceEdit = function(o)
        if not o or o.by ~= Me() then return end
        editing = o
        postBtn.label:SetText(L["Save price"])
        priceBox:SetText(o.pr or "")
        priceBox:SetFocus()
        say(L["Changing the price of %s. Enter saves, Escape cancels."]:format(Market.Label(o)))
    end
    priceBox:HookScript("OnEscapePressed", function() if editing then endEdit() end end)

    local function Post()
        dd:Hide()
        if editing then
            local o, why = Market.SetPrice(editing, priceBox:GetText())
            if not o then say(why) return end
            endEdit()
            priceBox:ClearFocus()
            return
        end
        local still = picked and itemBox:GetText() == picked.text
        local o, why = Market.Create(itemBox:GetText(), qtyBox:GetText(), priceBox:GetText(), noteBox:GetText(),
            still and picked.id or nil, parent.activeSub == "seek")
        if not o then say(why) return end
        -- the item stays in the form for the next post; the quantity goes back to one, price and note clear
        qtyBox:SetText("1")
        priceBox:SetText("")
        noteBox:SetText("")
        itemBox:ClearFocus(); priceBox:ClearFocus(); noteBox:ClearFocus(); qtyBox:ClearFocus()
        say("")
    end
    postBtn:SetScript("OnClick", Post)
    qtyBox:SetScript("OnEnterPressed", Post)
    priceBox:SetScript("OnEnterPressed", Post)
    noteBox:SetScript("OnEnterPressed", Post)
    itemBox:SetScript("OnEnterPressed", function() priceBox:SetFocus() end)
    itemBox:SetScript("OnTabPressed", function() qtyBox:SetFocus() end)
    qtyBox:SetScript("OnTabPressed", function() priceBox:SetFocus() end)
    priceBox:SetScript("OnTabPressed", function() noteBox:SetFocus() end)
    noteBox:SetScript("OnTabPressed", function() itemBox:SetFocus() end)

    ------------------------------------------------------------------
    -- Line 2: filters (a hidden one leaves no gap), the sort cycle
    ------------------------------------------------------------------
    local filterRow = CreateFrame("Frame", nil, parent)
    filterRow:SetPoint("TOPLEFT", formMsg, "BOTTOMLEFT", 0, -UI.GAP)
    filterRow:SetPoint("RIGHT", form, "RIGHT", 0, 0)
    filterRow:SetHeight(BTN_H)

    local filterBtns = {}
    local function mineLabel()
        return L["Mine"] .. "  " .. Market.MineCount() .. "/" .. Market.CAP
    end
    local function mutedCount()
        local p, n = Market.Prefs(), 0
        for _ in pairs(p.muted or {}) do n = n + 1 end
        for _ in pairs(p.hideItems or {}) do n = n + 1 end
        return n
    end
    -- the buttons that show take their places in turn, so a hidden one leaves no gap
    local function layoutFilters()
        local x = 0
        for _, f in ipairs(FILTERS) do
            local row = filterBtns[f.key]
            if row and (not row.requests or parent.activeSub == "seek") then
                row.btn:ClearAllPoints()
                row.btn:SetPoint("LEFT", x, 0)
                x = x + row.btn:GetWidth() + 4
            end
        end
    end
    local function paintFilters()
        -- my count goes amber five posts before the cap and red at it
        local over = Market.MineCount()
        local capCol = (over >= Market.CAP and C.danger) or (over >= Market.CAP - NEAR_CAP and C.warn) or nil
        for key, f in pairs(filterBtns) do
            local on = key == filter
            local col = (key == "mine" and capCol) or (on and C.gold) or C.text
            f.btn.baseLabelColor = { col.r, col.g, col.b }
            f.btn.label:SetTextColor(col.r, col.g, col.b)
            f.btn:SetShown(not f.requests or parent.activeSub == "seek")
        end
        if filterBtns.mine then filterBtns.mine.btn.label:SetText(mineLabel()) end
        if filterBtns.muted then
            local n = mutedCount()
            filterBtns.muted.btn.label:SetText(L["Muted"] .. (n > 0 and ("  " .. n) or ""))
        end
        layoutFilters()
    end

    for _, f in ipairs(FILTERS) do
        local b = UI:CreateButton(filterRow, L[f.label], 74, BTN_H)
        b:SetScript("OnClick", function()
            filter = f.key
            paintFilters()
            saveView()
            GuildOS:SafeCall(refresh)
        end)
        filterBtns[f.key] = { btn = b, requests = f.requests }
    end

    local sortBtn = UI:CreateButton(filterRow, L[SORT_LABEL[sortMode]], 120, BTN_H)
    sortBtn:SetPoint("RIGHT", 0, 0)
    sortBtn:SetScript("OnClick", function()
        local i = 1
        for k, v in ipairs(SORTS) do if v == sortMode then i = k end end
        sortMode = SORTS[i % #SORTS + 1]
        sortBtn.label:SetText(L[SORT_LABEL[sortMode]])
        saveView()
        GuildOS:SafeCall(refresh)
    end)

    ------------------------------------------------------------------
    -- Line 3: search (with a clear button), and the two switches (notify, popup)
    ------------------------------------------------------------------
    local searchRow = CreateFrame("Frame", nil, parent)
    searchRow:SetPoint("TOPLEFT", filterRow, "BOTTOMLEFT", 0, -UI.GAP)
    searchRow:SetPoint("TOPRIGHT", filterRow, "BOTTOMRIGHT", 0, -UI.GAP)
    searchRow:SetHeight(FIELD_H)

    local searchBox = UI:CreateInput(searchRow, 240, FIELD_H, { max = 60, placeholder = L["Search: name, note or who"] })
    searchBox:SetPoint("LEFT", 0, 0)
    local clearX = UI:CreateButton(searchRow, "x", 18, 18)
    clearX:SetPoint("RIGHT", searchBox, "RIGHT", -3, 0)
    clearX:Hide()
    -- every change to the search goes through the box, the variable, the × and the list together
    local function setSearch(text)
        searchBox:SetText(text or "")
        search = strtrim(text or ""):lower()
        clearX:SetShown(search ~= "")
        GuildOS:SafeCall(refresh)
    end
    searchBox:HookScript("OnTextChanged", function(self, userInput)
        search = strtrim(self:GetText() or ""):lower()
        clearX:SetShown(search ~= "")
        if userInput then GuildOS:SafeCall(refresh) end
    end)
    searchBox:HookScript("OnEscapePressed", function() setSearch("") end)
    clearX:SetScript("OnClick", function() setSearch(""); searchBox:ClearFocus() end)

    local function Check(label, tip, anchor)
        local c = UI:CreateCheckbox(searchRow, label, 18)
        if anchor then c:SetPoint("LEFT", anchor, "RIGHT", 10, 0)
        else c:SetPoint("LEFT", searchBox, "RIGHT", 14, 0) end
        UI:AddTooltip(c, label, { tip })
        return c
    end
    local notifyCheck = Check(L["Notify me"], L["Say it in chat when someone posts here, and play a sound."])
    local popupCheck = Check(L["Popup"], L["Show a small popup for a new post. Closes by itself."], notifyCheck)
    -- under the switches: which sub-tab they apply to
    local scopeCap = UI:CreateText(searchRow, "", 10, C.textDim.r, C.textDim.g, C.textDim.b)
    scopeCap:SetPoint("TOPLEFT", notifyCheck, "BOTTOMLEFT", 0, -2)

    -- the notify switch is for the sub-tab on screen: offers and requests have one each
    local function notifyKey() return parent.activeSub == "seek" and "notifyRequests" or "notifyOffers" end
    notifyCheck.checkbox.onChanged = function(_, checked) Market.Prefs()[notifyKey()] = checked and true or false end
    popupCheck.checkbox.onChanged = function(_, checked) Market.Prefs().popup = checked and true or false end

    local function paintChecks()
        local p = Market.Prefs()
        notifyCheck.checkbox:SetChecked(p[notifyKey()] ~= false)
        popupCheck.checkbox:SetChecked(p.popup ~= false)
        scopeCap:SetText(parent.activeSub == "seek" and L["Applies to Looking for"] or L["Applies to Offering"])
    end

    -- one line above the list: what the right-click does
    local hint = UI:CreateText(parent, L["Right-click a post to mute its poster. Click a group to open it."], 10,
        C.textDim.r, C.textDim.g, C.textDim.b)
    hint:SetPoint("TOPLEFT", searchRow, "BOTTOMLEFT", 0, -(UI.GAP + 14))

    ------------------------------------------------------------------
    -- The list
    ------------------------------------------------------------------
    local scroll, content = UI:CreateScrollFrame(parent, "GuildOSMarketScroll")
    scroll:SetPoint("TOPLEFT", hint, "BOTTOMLEFT", 0, -UI.GAP)
    scroll:SetPoint("BOTTOMRIGHT", -(10 + UI.GAP - UI.SCROLL_GUTTER), 8)
    UI:BindScrollChildWidth(scroll, content)

    local empty = UI:CreateText(content, "", 11, C.textDim.r, C.textDim.g, C.textDim.b)
    empty:SetPoint("TOPLEFT", 8, -8)
    local emptyBtn = UI:CreateButton(content, "", 120, BTN_H)
    emptyBtn:SetPoint("TOPLEFT", empty, "BOTTOMLEFT", 0, -6)
    emptyBtn:Hide()
    emptyBtn:SetScript("OnClick", function()
        if search ~= "" then setSearch("")
        else
            filter = "all"
            paintFilters()
            saveView()
            GuildOS:SafeCall(refresh)
        end
    end)

    local rows = {}
    local function RightClick(o)
        local me = Me()
        if filter == "muted" and Market.IsMuted(o.by) then return Market.ToggleMute(o.by) end
        if filter == "muted" and Market.ItemHidden(o) then return Market.ShowItem(o) end
        if o.by ~= me then Market.ToggleMute(o.by) end
    end

    local function GetRow(i)
        if rows[i] then return rows[i] end
        local row = CreateFrame("Frame", nil, content, "BackdropTemplate")
        row:SetHeight(ROW_H - 1)
        row:SetPoint("TOPLEFT", 0, -(i - 1) * ROW_H)
        row:SetPoint("RIGHT", content, "RIGHT", 0, 0)
        row:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8" })
        local bg = (i % 2 == 0) and C.row2 or C.row1
        row:SetBackdropColor(bg.r, bg.g, bg.b, bg.a or 1)
        row:EnableMouse(true)
        row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        row:SetScript("OnClick", function(self, button)
            if self.group and button == "LeftButton" then
                local k = self.group.key
                expanded[k] = (not expanded[k]) or nil
                GuildOS:SafeCall(refresh)
            elseif self.offer and button == "RightButton" then
                RightClick(self.offer)
            end
        end)
        row:SetScript("OnEnter", function(self)
            if not (self.group or self.offer) then return end
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            if self.group then
                GameTooltip:AddLine(Market.Label(self.group.items[1].o), 1, 1, 1)
                GameTooltip:AddLine(L["Several posts of this. Click to show them one by one."], 0.7, 0.7, 0.7, true)
            else
                Tooltip(GameTooltip, self.offer)
            end
            GameTooltip:Show()
        end)
        row:SetScript("OnLeave", function() GameTooltip:Hide() end)

        row.icon = UI:CreateIcon(row, 22)
        row.icon:SetPoint("LEFT", 4, 0)
        row.btns = {}
        local prev
        for k = 1, ACT_MAX do
            local b = UI:CreateButton(row, "", BTN_W, BTN_H)
            if prev then b:SetPoint("RIGHT", prev, "LEFT", -4, 0) else b:SetPoint("RIGHT", -4, 0) end
            row.btns[k] = b
            prev = b
        end
        -- the price column sits just left of the action buttons, right-aligned
        row.price = UI:CreateText(row, "", 11, GOLD[1], GOLD[2], GOLD[3])
        row.price:SetJustifyH("RIGHT")
        row.price:SetWordWrap(false)
        row.price:SetWidth(PRICE_W)
        row.price:SetPoint("RIGHT", row.btns[ACT_MAX], "LEFT", -8, 0)

        local function text(size, y, col)
            local fs = UI:CreateText(row, "", size, col.r, col.g, col.b)
            fs:SetJustifyH("LEFT")
            fs:SetWordWrap(false)
            fs:SetPoint("TOPLEFT", row.icon, "TOPRIGHT", 6, y)
            fs:SetPoint("RIGHT", row, "RIGHT", -(ACT_MAX * (BTN_W + 4) + 12 + PRICE_W), 0)
            return fs
        end
        row.title = text(11, 0, C.text)
        row.meta = text(10, -14, C.textDim)
        rows[i] = row
        return row
    end

    local function FillButton(btn, action, o)
        if not action then btn:Hide() return end
        btn.label:SetText(action[1])
        btn:SetWidth(BTN_W)
        btn:SetScript("OnClick", function() action[2](o) end)
        btn:Show()
    end

    -- the tab labels: "Offering  4", "Looking for  2" (live posts, not counting muted members or hidden items)
    local function paintTabCounts(live)
        local changed = false
        for key, name in pairs(tabNames) do
            local text = name .. "  " .. live[key]
            if tabShown[key] ~= text then
                tabShown[key] = text
                subTabs[key].label:SetText(text)
                subTabs[key]:SetWidth(math.max(TAB_MIN_W, math.ceil(subTabs[key].label:GetStringWidth()) + TAB_PAD))
                changed = true
            end
        end
        if changed then UI:FlowBar(bar, subList, { gap = 4, rowGap = 4, rowH = TAB_H }) end
    end

    refresh = function()
        if not parent:IsVisible() then return end
        paintChecks()
        paintFilters()
        local seekMode = parent.activeSub == "seek"
        local g, me = Market.G(), Me()
        local list, live = {}, { offer = 0, seek = 0 }
        for _, o in pairs(g and g.offers or {}) do
            if Market.Live(o) then
                local req = Market.IsRequest(o)
                if not Market.IsMuted(o.by) and not Market.ItemHidden(o) then
                    local k = req and "seek" or "offer"
                    live[k] = live[k] + 1
                end
                if req == seekMode then
                    local wants, mine, qty = Market.WantsOf(o)
                    if Matches(o, filter, me, mine) and Searched(o, search) then
                        list[#list + 1] = { o = o, w = wants, mine = mine, qty = qty }
                    end
                end
            end
        end
        paintTabCounts(live)
        table.sort(list, function(a, b)
            if sortMode == "price" then
                local pa, pb = a.o.prc, b.o.prc
                if (pa == nil) ~= (pb == nil) then return pa ~= nil end
                if pa and pb and pa ~= pb then return pa < pb end
            elseif sortMode == "online" then
                local oa, ob = Market.IsOnline(a.o.by), Market.IsOnline(b.o.by)
                if oa ~= ob then return oa end
            end
            return (a.o.c or 0) > (b.o.c or 0)
        end)

        -- the same item posted by several members is one row with a count; a click opens it
        local groups, order, rowsOut = {}, {}, {}
        for _, e in ipairs(list) do
            local k = Market.ItemKey(e.o)
            if not groups[k] then
                groups[k] = { key = k, items = {} }
                order[#order + 1] = groups[k]
            end
            table.insert(groups[k].items, e)
        end
        for _, grp in ipairs(order) do
            if #grp.items == 1 then
                rowsOut[#rowsOut + 1] = { e = grp.items[1] }
            else
                rowsOut[#rowsOut + 1] = { group = grp }
                if expanded[grp.key] then
                    for _, e in ipairs(grp.items) do rowsOut[#rowsOut + 1] = { e = e, child = true } end
                end
            end
        end

        for i, r in ipairs(rowsOut) do
            local row = GetRow(i)
            row.offer, row.group = nil, nil
            row.icon:ClearAllPoints()
            row.icon:SetPoint("LEFT", r.child and 22 or 4, 0)
            if r.group then
                local title, meta = GroupText(r.group)
                row.group = r.group
                row.icon.icon:SetTexture(Market.Icon(r.group.items[1].o))
                row.title:SetText((expanded[r.group.key] and "-  " or "+  ") .. title)
                row.meta:SetText(meta)
                row.price:SetText("")
                for _, b in ipairs(row.btns) do FillButton(b, nil) end
                row:SetAlpha(1)
            else
                local e = r.e
                row.offer = e.o
                row.icon.icon:SetTexture(Market.Icon(e.o))
                local title, meta, price = RowText(e.o, me, e.w, e.mine, e.qty)
                row.title:SetText(title)
                row.meta:SetText(meta)
                row.price:SetText(price)
                local acts = Actions(e.o, me, e.mine)
                for k, b in ipairs(row.btns) do FillButton(b, acts[k], e.o) end
                row:SetAlpha(Market.Age(e.o) > Market.OLD_AFTER and STALE_ALPHA or 1)
            end
            row:Show()
        end
        for i = #rowsOut + 1, #rows do rows[i]:Hide(); rows[i].offer = nil; rows[i].group = nil end

        local n = #rowsOut
        empty:SetShown(n == 0)
        emptyBtn:SetShown(n == 0 and (search ~= "" or filter ~= "all"))
        if n == 0 then
            local msg
            if filter == "muted" then
                msg = L["Nothing is muted. Right-click a post to mute its poster, or use Mute this item on a popup."]
            elseif search ~= "" or filter ~= "all" then
                msg = L["Nothing matches this filter or search."]
            elseif seekMode then
                msg = L["No requests right now. Ask the guild for something you need."]
            else
                msg = L["No offers yet. Put up something you can sell, or a service you do."]
            end
            empty:SetText(msg)
            emptyBtn.label:SetText(search ~= "" and L["Clear search"] or L["Show all"])
        end
        content:SetHeight(math.max(1, n * ROW_H))
    end
    Market.uiRefresh = refresh

    ------------------------------------------------------------------
    -- Sub-tabs: select, deep links, the rest
    ------------------------------------------------------------------
    local function selectSub(key)
        parent.activeSub = key == "seek" and "seek" or "offer"
        for k, btn in pairs(subTabs) do btn:SetActive(k == parent.activeSub) end
        if parent.activeSub == "offer" and filter == "forme" then filter = "all" end
        paintFilters()
        dd:Hide()
        scroll:SetVerticalScroll(0)
        saveView()
        GuildOS:SafeCall(refresh)
    end
    parent.SelectSub = selectSub

    for _, t in ipairs({ { key = "offer", label = tabNames.offer }, { key = "seek", label = tabNames.seek } }) do
        local btn = UI:CreateTab(bar, t.label, TAB_MIN_W, true)
        btn:SetWidth(math.max(TAB_MIN_W, math.ceil(btn.label:GetStringWidth()) + TAB_PAD))
        btn:SetScript("OnClick", function() selectSub(t.key) end)
        subTabs[t.key] = btn
        subList[#subList + 1] = btn
    end
    UI:FlowBar(bar, subList, { gap = 4, rowGap = 4, rowH = TAB_H })

    parent:SetScript("OnShow", function() selectSub(parent.activeSub or "offer") end)
    local since = 0
    parent:SetScript("OnUpdate", function(_, elapsed)
        since = since + elapsed
        if since < REPAINT_EVERY then return end
        since = 0
        GuildOS:SafeCall(refresh)
    end)

    -- item names arrive after the client has them: repaint once they do (debounced)
    local itemEv = CreateFrame("Frame")
    itemEv:RegisterEvent("GET_ITEM_INFO_RECEIVED")
    local queued = false
    itemEv:SetScript("OnEvent", function()
        if queued or not parent:IsVisible() then return end
        queued = true
        C_Timer.After(0.5, function() queued = false; GuildOS:SafeCall(refresh) end)
    end)

    UI:MakeResponsive(parent, function(_, w)
        bar:SetWidth(math.max(TAB_MIN_W, w - 20))
        UI:FlowBar(bar, subList, { gap = 4, rowGap = 4, rowH = TAB_H })
        GuildOS:SafeCall(refresh)
    end)

    selectSub(parent.activeSub)
end

----------------------------------------------------------------------
-- Popups. For a new post: "Show" opens the tab, the middle button takes it ("Want it" / "I have it"),
-- "Mute this item" stops the popups for this item, "Popup off" switches them all off. For an answer to my
-- post ("someone wants it"): the middle button is "Sold" or "Got it". Draggable; closes by itself
-- unless the mouse is on it. Nothing pops up in combat: the newest one waits until the fight is over.
----------------------------------------------------------------------
local SHOW_FOR, POP_W, POP_H = 25, 440, 82
local popup, current, currentKind, currentWant, hideAt, pending

local function savePos(f)
    local point, _, _, x, y = f:GetPoint()
    Market.Prefs().popupPos = { point, x, y }
end

local function buildPopup()
    local f = CreateFrame("Frame", "GuildOSMarketPopup", UIParent, "BackdropTemplate")
    f:SetSize(POP_W, POP_H)
    f:SetFrameStrata("DIALOG")
    f:SetClampedToScreen(true)
    UI:StylePopup(f, { noFade = true })
    local pos = Market.Prefs().popupPos
    if pos then f:SetPoint(pos[1], UIParent, pos[1], pos[2], pos[3])
    else f:SetPoint("TOP", UIParent, "TOP", 0, -140) end

    f:EnableMouse(true)
    f:SetMovable(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", function(self) self:StopMovingOrSizing(); savePos(self) end)

    f.icon = UI:CreateIcon(f, 32)
    f.icon:SetPoint("TOPLEFT", 8, -8)
    f.icon:EnableMouse(true)
    f.icon:SetScript("OnEnter", function(self)
        if not current then return end
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        Tooltip(GameTooltip, current)
        GameTooltip:Show()
    end)
    f.icon:SetScript("OnLeave", function() GameTooltip:Hide() end)

    f.head = UI:CreateText(f, "", 11, GOLD[1], GOLD[2], GOLD[3])
    f.head:SetPoint("TOPLEFT", f.icon, "TOPRIGHT", 8, -1)
    f.head:SetPoint("RIGHT", f, "RIGHT", -28, 0)
    f.head:SetJustifyH("LEFT")
    f.head:SetWordWrap(false)

    f.text = UI:CreateText(f, "", 11, C.text.r, C.text.g, C.text.b)
    f.text:SetPoint("TOPLEFT", f.head, "BOTTOMLEFT", 0, -3)
    f.text:SetPoint("RIGHT", f, "RIGHT", -10, 0)
    f.text:SetJustifyH("LEFT")
    f.text:SetJustifyV("TOP")
    f.text:SetHeight(26)
    f.text:SetWordWrap(true)

    local close = UI:CreateButton(f, "x", 18, 18)
    close:SetPoint("TOPRIGHT", -5, -5)
    close:SetScript("OnClick", function() f:Hide() end)

    f.open = UI:CreateButton(f, L["Show"], 80, 20)
    f.open:SetPoint("BOTTOMRIGHT", -8, 8)
    f.open:SetScript("OnClick", function()
        local seek = current and Market.IsRequest(current)
        f:Hide()
        UI:OpenWindow("market", seek and "seek" or "offer")
    end)

    f.act = UI:CreateButton(f, "", 100, 20)
    UI:SetButtonVariant(f.act, "primary")
    f.act:SetScript("OnClick", function()
        local o = current
        local kind = currentKind
        f:Hide()
        local cur = o and Market.G() and Market.G().offers[o.id]
        if not cur then return end
        if kind == "want" then Market.Sold(cur) else Market.Want(cur) end
    end)

    f.hide = UI:CreateButton(f, L["Mute this item"], 110, 20)
    f.hide:SetScript("OnClick", function()
        local o = current
        f:Hide()
        if o then Market.HideItem(o) end
    end)

    f.off = UI:CreateButton(f, L["Popup off"], 100, 20)
    f.off:SetScript("OnClick", function()
        f:Hide()
        Market.Prefs().popup = false
        GuildOS:Print(L["Marketplace popups are off. Switch them on in the Marketplace tab."])
        Market.Changed()
    end)

    f:EnableMouse(true)
    -- closes by itself, but not while the mouse is on it
    f:SetScript("OnUpdate", function(self)
        if GetTime() >= hideAt and not self:IsMouseOver() then self:Hide() end
    end)
    f:SetScript("OnHide", function() current = nil; currentWant = nil end)
    f:Hide()
    return f
end

local function show(o, kind, w)
    popup = popup or buildPopup()
    current, currentKind, currentWant = o, kind, w
    local seek = Market.IsRequest(o)
    local mine = o.by == Me()
    popup.icon.icon:SetTexture(Market.Icon(o))

    if kind == "want" then
        local qty = w and w.q and (" (" .. w.q .. ")") or ""
        popup.head:SetText(seek and L["Someone has it"] or L["Someone wants it"])
        popup.text:SetText(Market.ColorName(w and w.who or "") .. ": " .. Market.Label(o) .. qty)
    else
        local have = seek and Market.Have(o) or 0
        local can = Market.SeekForMe(o)
        local why = ""
        if have > 0 then why = "  |cff40ff40" .. L["You have %d of it"]:format(have) .. "|r"
        elseif can then why = "  |cff40ff40" .. L["You can do this"] .. "|r" end
        popup.head:SetText((seek and L["New request"] or L["New offer"]) .. why)
        popup.text:SetText(Market.ColorName(o.by) .. ": " .. Market.Label(o)
            .. (o.pr and ("  |cffffd100" .. o.pr .. "|r") or "")
            .. (o.note and ("\n|cffaaaaaa\"" .. o.note .. "\"|r") or ""))
    end

    -- the buttons, right to left: Show, the middle one, Hide item, Popup off
    local showAct, showHide = kind == "want" or not mine, kind ~= "want" and not mine
    if kind == "want" then
        popup.act.label:SetText(seek and L["Got it"] or L["Sold"])
    else
        popup.act.label:SetText(seek and L["I have it"] or L["Want it"])
    end
    popup.act:SetShown(showAct)
    popup.hide:SetShown(showHide)
    local anchor = popup.open
    for _, b in ipairs({ popup.act, popup.hide, popup.off }) do
        b:ClearAllPoints()
        if b:IsShown() or b == popup.off then
            b:SetPoint("RIGHT", anchor, "LEFT", -6, 0)
            anchor = b
        end
    end
    popup.off:ClearAllPoints()
    popup.off:SetPoint("RIGHT", anchor, "LEFT", -6, 0)

    hideAt = GetTime() + SHOW_FOR
    popup:Show()
end

function Market.ShowPopup(o, kind)
    if Market.Prefs().popup == false then return end
    if InCombatLockdown() then pending = { o = o, kind = kind } return end
    GuildOS:SafeCall(show, o, kind)
end

-- someone said they want my offer, or has my request: the popup with "Sold" on it
function Market.ShowWantPopup(o, w)
    if Market.Prefs().popup == false then return end
    if InCombatLockdown() then pending = { o = o, kind = "want", w = w } return end
    GuildOS:SafeCall(show, o, "want", w)
end

local combatEv = CreateFrame("Frame")
combatEv:RegisterEvent("PLAYER_REGEN_ENABLED")
combatEv:SetScript("OnEvent", function()
    if not pending then return end
    local p = pending
    pending = nil
    if Market.Prefs().popup ~= false then GuildOS:SafeCall(show, p.o, p.kind, p.w) end
end)
