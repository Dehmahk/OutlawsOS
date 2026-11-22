----------------------------------------------------------------------
-- Guild OS - Home cards
-- The Now tab's grid (UI/Agora.lua places it): six equal cards (#377, the
-- approved sketch Agora.dc.html) that surface the most useful at-a-glance
-- info: the next event and your answer, your readiness (on WoW: Forever, the
-- countdown to the raids), the guild's pulse, recruitment, your loot and the
-- guild's chat, each clicking through to its full tab. A card is a `panel`
-- surface with a 1px line, its title in Mono, 12px inside. Everything is
-- read from existing modules; nothing here owns state. Refreshes on show.
----------------------------------------------------------------------
local UI = GuildOS.UI
local C  = GuildOS.Colors
local L  = GuildOS.L

local WHITE      = "Interface\\Buttons\\WHITE8x8"
local PAD        = 12    -- inside a card (the sketch's .card)
local HDR_H      = 12    -- a card's title line (Mono 10)
local STACK      = 8     -- between a card's blocks
local BODY_TOP   = PAD + HDR_H + STACK
local CARD_H     = 164   -- a card under the column: the height it has in the default 1000x620 window
local CARD_MIN_H = 150   -- beside the column, never shorter: the tab scrolls instead
local CARD_MIN_W = 240   -- two side by side only while each keeps this, or the RSVP buttons wrap
local SETUP_H    = 150
local GUTTER     = 12    -- when the grid is drawn alone (Agora passes its own)
local MARK       = 6     -- the status square (Indicator textures are game art, not the identity's)
local ROW_H      = 24
local LINE_H     = 16    -- a line of the raids countdown
local DASH       = "\226\128\148"   -- a number not known yet
local DOT        = " \194\183 "

local RSVP = { { L["Going"], "yes" }, { L["Tentative"], "tentative" }, { L["Absent"], "no" } }

local function CAL() return GuildOS.Calendar end
local function nowT() return (GetServerTime and GetServerTime()) or time() end
local function myKey() return GuildOS:GetPlayerKey(GuildOS.Compat.PlayerName(), GetRealmName()) end

-- Hide everything a previous fill created inside a card body.
local function clearBody(body)
    for _, c in pairs({ body:GetChildren() }) do c:Hide() end
    for _, r in pairs({ body:GetRegions() }) do r:Hide() end
end

-- "in 2d 4h" / "in 3h 10m" / "in 25m" / "now".
local function fmtCountdown(dt)
    if dt <= 0 then return L["now"] end
    local d = math.floor(dt / 86400)
    local h = math.floor((dt % 86400) / 3600)
    local m = math.floor((dt % 3600) / 60)
    if d > 0 then return string.format(L["in %dd %dh"], d, h) end
    if h > 0 then return string.format(L["in %dh %dm"], h, m) end
    return string.format(L["in %dm"], math.max(1, m))
end

local function truncate(s, n)
    s = tostring(s or "")
    if GuildOS:Utf8Len(s) <= n then return s end
    return GuildOS:Utf8Head(s, n - 1) .. "..."   -- by characters, never half of one (#104)
end

-- A text in a card body at (x, y): Sans 12 unless a role says otherwise, one line cut at `w`
-- unless it wraps.
local function text(body, s, x, y, w, col, role, wrap)
    local fs = UI:CreateText(body, s, 12, col.r, col.g, col.b)
    if role then GuildOS:ApplyFont(fs, nil, role) end
    fs:SetPoint("TOPLEFT", x, -y)
    if w then fs:SetWidth(math.max(1, w)) end
    fs:SetWordWrap(wrap == true)
    fs:SetJustifyH("LEFT")
    return fs
end

-- A status line: a 6px square in `col`, then the words in `ink`.
local function markLine(body, col, ink, s, y, w, x)
    x = x or 0
    local sq = body:CreateTexture(nil, "ARTWORK")
    sq:SetTexture(WHITE)
    sq:SetSize(MARK, MARK)
    sq:SetPoint("TOPLEFT", x, -(y + 4))
    sq:SetVertexColor(col.r, col.g, col.b, 1)
    return text(body, s, x + MARK + 8, y, w - MARK - 8, ink)
end

-- A button as wide as its label plus the sketch's padding on each side: CreateButton only grows one
-- whose label spills, so a short label sat against its edges.
local function fit(b, pad)
    b:SetWidth(math.ceil(b.label:GetStringWidth() or 0) + 2 * pad)
    return b
end

-- A link-style button (the sketch's "b g": 4px either side of its mono label).
local function ghost(parent, label)
    return fit(UI:SetButtonVariant(UI:CreateButton(parent, label, 40, 26), "ghost"), 4)
end

----------------------------------------------------------------------
-- Build the cards into `panel` (Agora's grid frame); return the refresh fn.
-- panel.Layout(w, h, fill, gutter) places them and returns the height used.
----------------------------------------------------------------------
function GuildOS:CreateDashboardPanel(panel)
    local f = CreateFrame("Frame", nil, panel)
    f:SetAllPoints(panel)

    -- A card opens its tab, and the sub-tab when it names one.
    local function goTab(tabKey, subKey) UI:OpenWindow(tabKey, subKey) end

    -- Card = a `panel` surface with a Mono title + a body frame + click-through. A card whose body
    -- takes clicks itself (the chat: a link, the box) opens its tab from the arrow alone.
    local function makeCard(title, tabKey, subKey, arrowOnly)
        local card = UI:CreatePanel(f, nil, (f:GetFrameLevel() or 1) + 1)
        card:SetBackdropColor(C.panel.r, C.panel.g, C.panel.b, 1)
        local hdr = UI:CreateHeaderText(card, title)
        hdr:SetPoint("TOPLEFT", PAD, -PAD)
        -- One line, short of the arrow: a long translation cuts, never runs into it (#148).
        hdr:SetPoint("RIGHT", card, "RIGHT", -(PAD + 16), 0)
        hdr:SetWordWrap(false)
        hdr:SetJustifyH("LEFT")
        card.hdr = hdr

        local arrow = UI:CreateText(card, ">", 12, C.label.r, C.label.g, C.label.b)
        arrow:SetPoint("TOPRIGHT", -PAD, -(PAD - 2))
        arrow:SetShown(tabKey ~= nil)
        card.arrow = arrow

        local body = CreateFrame("Frame", nil, card)
        body:SetPoint("TOPLEFT", PAD, -BODY_TOP)
        body:SetPoint("BOTTOMRIGHT", -PAD, PAD)
        card.body = body
        card.innerW, card.innerH = 1, 1

        if tabKey then
            local hit = card
            if arrowOnly then
                hit = CreateFrame("Button", nil, card)
                hit:SetPoint("TOPRIGHT", -4, -4)
                hit:SetSize(28, 22)
                hit:SetScript("OnClick", function() goTab(tabKey, subKey) end)
            else
                card:EnableMouse(true)
                card:SetScript("OnMouseUp", function() goTab(tabKey, subKey) end)
            end
            -- Hovered, a card lights its border as a secondary button does: gold is for selection.
            hit:SetScript("OnEnter", function()
                card:SetBackdropBorderColor(C.label.r, C.label.g, C.label.b, 1)
                arrow:SetTextColor(C.text.r, C.text.g, C.text.b)
            end)
            hit:SetScript("OnLeave", function()
                card:SetBackdropBorderColor(C.line.r, C.line.g, C.line.b, 1)
                arrow:SetTextColor(C.label.r, C.label.g, C.label.b)
            end)
        end
        return card
    end

    local cNext     = makeCard(L["NEXT EVENT"],      "guild",       "calendar")
    local cReady    = makeCard(L["YOUR READINESS"],  "raids")
    local cPulse    = makeCard(L["GUILD PULSE"],     "roster")
    local cRecruit  = makeCard(L["RECRUITMENT"],     "recruitment")
    -- EKO patch: this week's Location of the Week and your bounty board, in Recruitment's place.
    local cEvents   = makeCard("EVENTS",             "guild",       "raffle")
    local cLoot     = makeCard("THE OUTLAW GAZETTE")
    -- The guild's chat (#126), where "Guild activity" repeated the Activity column beside it.
    local cChat     = makeCard(L["GUILD CHAT"],      "guild",       "chat", true)
    local chatRefresh = GuildOS:CreateGuildChatFeed(cChat.body)
    -- The guild's setup, for its GM and officers (issue #217), over the grid while due. WoW: Forever only.
    local cSetup = GuildOS.Activation and makeCard(L["SET UP GUILD OS FOR YOUR GUILD"]) or nil
    if cSetup then cSetup:Hide() end   -- frames are born shown: only Layout decides it is due
    local grid = { cNext, cReady, cPulse, cEvents, cRecruit, cLoot, cChat }

    ------------------------------------------------------------------
    -- Card fills (each clears its body and rebuilds from live data)
    ------------------------------------------------------------------
    local function fillNext(card)
        local body, w = card.body, card.innerW
        clearBody(body)
        local cal = CAL()
        local e = cal and cal:NextEvent()
        if not e then
            text(body, L["No upcoming events scheduled."], 0, 0, w, C.textSoft, nil, true)
            return
        end
        local kindTxt = (cal.KindLabel and cal:KindLabel(e.kind)) or ""
        -- An officer typed it, and it may have come over the wire (#377).
        text(body, truncate(GuildOS:SanitizeUserText(e.title or "?"), 34), 0, 0, w, C.text, "sectionTitle")
        local when = GuildOS:LocalDate(L["%a %d %b, %H:%M"], e.when) .. DOT .. fmtCountdown((e.when or 0) - nowT())
        if kindTxt ~= "" then when = when .. DOT .. kindTxt end
        text(body, when, 0, 18, w, C.label, "caption")
        local comp = cal:GetComposition(e)
        text(body, string.format(L["%d going · %d tentative  |  %dT %dH %dD"],
            comp.yes, comp.tentative, comp.roles.TANK, comp.roles.HEALER, comp.roles.DPS), 0, 38, w, C.textSoft, "tableNum")

        -- A raid planned on the site is answered there: no buttons of the game's own (#146).
        if cal:IsWebEvent(e) then
            local where = text(body, L["Sign up in Discord or on the website."], 0, 0, w, C.textSoft, nil, true)
            where:ClearAllPoints()
            where:SetPoint("BOTTOMLEFT", 0, 0)
            return
        end

        -- The answer, along the card's foot (keeps the player's current role). Until it is given,
        -- "Going" is the screen's one primary (the sketch); once given, that answer is the selected one.
        local mine = cal:MyRsvp(e)
        local role = (mine and mine.role) or "DPS"
        local bar = CreateFrame("Frame", nil, body)
        bar:SetPoint("BOTTOMLEFT", 0, 0)
        bar:SetWidth(math.max(1, w))
        local buttons = {}
        for _, opt in ipairs(RSVP) do
            local b = UI:CreateButton(bar, opt[1], 40, 26)
            if not mine and opt[2] == "yes" then UI:SetButtonVariant(b, "primary") end
            fit(b, 12)
            UI:SetSelected(b, mine ~= nil and mine.status == opt[2])
            b:SetScript("OnClick", function() cal:Rsvp(e.id, opt[2], role); f.Refresh() end)
            b.status = opt[2]
            buttons[#buttons + 1] = b
        end
        -- A translation too long for one row wraps the buttons rather than running out of the card.
        UI:FlowBar(bar, buttons, { gap = STACK, rowGap = 4, rowH = 26 })
        card.rsvp = buttons
    end

    local function fillReady(card, myRow)
        local body, w = card.body, card.innerW
        clearBody(body)
        if not myRow then
            text(body, L["No readiness data yet — open the roster to sync."], 0, 0, w, C.textSoft, nil, true)
            return
        end
        local y = 0
        -- Attunements: a bar and its percentage, as in the sketch.
        if (myRow.attTotal or 0) > 0 then
            local frac = myRow.attDone / myRow.attTotal
            text(body, string.format(L["Attunements (%d/%d)"], myRow.attDone, myRow.attTotal), 0, 0, w - 44, C.text)
            local pct = text(body, string.format("%d%%", math.floor(frac * 100 + 0.5)), 0, 0, 40, C.label, "caption")
            pct:ClearAllPoints()
            pct:SetPoint("TOPRIGHT", 0, -2)
            pct:SetJustifyH("RIGHT")
            local bar = UI:CreateProgressBar(body, math.max(1, w), 8)
            bar:SetPoint("TOPLEFT", 0, -18)
            bar:SetProgress(frac)
            y = 18 + 8 + STACK
        end
        -- Each check a square: ok when it is done, warn (square and words) when it is not.
        local function tick(ok, okText, warnText)
            markLine(body, ok and C.ok or C.warn, ok and C.text or C.warn, ok and okText or warnText, y, w)
            y = y + 14 + STACK
        end
        if myRow.hasGear then
            tick((myRow.missEnch or 0) == 0, L["Enchants complete"], string.format(L["Enchants: %d missing"], myRow.missEnch or 0))
        end
        -- Consumables (nil = never checked this raid)
        if myRow.missCons ~= nil then
            tick(myRow.missCons == 0, L["Consumables stocked"], string.format(L["Consumables: %d missing"], myRow.missCons))
        end
        -- Overall verdict
        local verdict, vcol
        if myRow.status == "ready" then verdict, vcol = L["You're raid-ready!"], C.ok
        elseif myRow.status == "warn" or myRow.status == "notready" then verdict, vcol = L["Needs attention"], C.warn
        else verdict, vcol = L["Not enough data yet"], C.textSoft end
        text(body, verdict, 0, y, w, vcol, "memberName")
    end

    -- WoW: Forever, until a week after the raids open (issue #207): the countdown in the readiness
    -- card's place. Readiness:Countdown counts; this only draws.
    local function fillCountdown(card, cd)
        local body = card.body
        clearBody(body)
        local title = cd.open and L["RAIDS ARE OPEN"]
            or cd.days == 0 and L["RAIDS OPEN IN UNDER A DAY"]
            or cd.days == 1 and L["RAIDS OPEN IN 1 DAY"]
            or string.format(L["RAIDS OPEN IN %d DAYS"], cd.days)
        card.hdr:SetText(title)
        local w = card.innerW
        local y = 0
        local function line(label, value, frac)
            local valX = math.floor(w * 0.38)
            local barW = frac and math.max(20, math.floor(w * 0.22)) or 0
            text(body, label, 0, y, math.floor(w * 0.36), C.text)
            local val = text(body, value, valX, y + 1, w - valX - barW - (frac and 8 or 0), C.textSoft)
            GuildOS:ApplyFont(val, 11)
            if frac then
                local bar = UI:CreateProgressBar(body, barW, 8)
                bar:SetPoint("TOPRIGHT", 0, -(y + 3))
                bar:SetProgress(frac)
            end
            y = y + LINE_H
        end
        for _, c in ipairs(cd.cores) do
            line(c.name, string.format(L["%d / %d at %d"], c.ready, c.size, cd.cap), c.ready / c.size)
        end
        -- The slices, as on guildos.me: on a line of their own, or a long guild would cut them.
        local g, s = cd.guild, cd.guild.slices
        if s.short then
            line(L["Guild"], s.shortSize == GuildOS.Readiness.DUNGEON_GROUP and string.format(L["%d at %d · %d more for a group"], g.ready, cd.cap, s.short)
                or string.format(L["%d at %d · %d more for a %d"], g.ready, cd.cap, s.short, s.shortSize))
        else
            line(L["Guild"], string.format(L["%d at %d"], g.ready, cd.cap))
        end
        if s.dungeons > 0 then
            local parts = { s.dungeons == 1 and L["1 group"] or string.format(L["%d groups"], s.dungeons) }
            for _, r in ipairs(s.raids) do parts[#parts + 1] = r.count .. "×" .. r.size end
            line(L["Can form"], table.concat(parts, " · "))
        end
        local me = cd.me
        if me then
            local mine
            if (me.level or 0) < cd.cap then
                mine = string.format(L["Level %d · %d to go"], me.level or 0, cd.cap - (me.level or 0))
            elseif me.reason == "enchants" then
                mine = string.format(L["Ready · %d enchants missing"], me.missEnch or 0)
            elseif me.reason == "ilvl" then
                mine = L["Ready · under the guild's item level"]
            else
                mine = L["Ready"]
            end
            line(L["You"], mine)
        end
    end

    -- Three metric chips (members, online, average item level), and the raid-ready count under them.
    local function fillPulse(card, rows)
        local body, w = card.body, card.innerW
        clearBody(body)
        local total, online, iSum, iN = 0, 0, 0, 0
        for _, r in ipairs(rows or {}) do
            total = total + 1
            if r.online then online = online + 1 end
            if (r.ilvl or 0) > 0 then iSum = iSum + r.ilvl; iN = iN + 1 end
        end
        local avgIlvl = iN > 0 and math.floor(iSum / iN) or 0
        -- EKO patch: a leveling guild's pulse. GuildOS users instead of item level, the level spread under it.
        local gosUsers, band = 0, { 0, 0, 0, 0 }
        local saved = (GuildOS.db and GuildOS.db.members) or {}
        for i = 1, GetNumGuildMembers() or 0 do
            local n, _, _, lv = GetGuildRosterInfo(i)
            local s = n and (n:match("^([^-]+)") or n)
            if s and saved[s] and saved[s].addonVersion then gosUsers = gosUsers + 1 end
            lv = lv or 0
            local b = lv >= GuildOS.Client.maxLevel and 4 or lv >= 40 and 3 or lv >= 20 and 2 or 1
            band[b] = band[b] + 1
        end

        -- Raid-ready = max-level members (70, or 60 on Forever), counted straight from the guild
        -- roster so offline members count too: a stable, motivating number even with the guild
        -- offline. Level is a roster field known for everyone, so this needs no synced data.
        local ready = 0
        for i = 1, GetNumGuildMembers() or 0 do
            local _, _, _, level = GetGuildRosterInfo(i)
            if (level or 0) >= GuildOS.Client.maxLevel then ready = ready + 1 end
        end
        local stats = {
            { tostring(total), L["members"] },
            { tostring(online), L["online"] },
            { tostring(gosUsers), "GuildOS" },   -- EKO patch (was avg iLvl)
        }
        local chipW = math.max(34, math.floor((w - 2 * PAD) / 3))
        card.chips = {}
        for i, s in ipairs(stats) do
            local chip = UI:CreateMetricChip(body, s[1], s[2])
            chip:SetPoint("TOPLEFT", (i - 1) * (chipW + PAD), -4)
            chip:SetWidth(chipW)
            -- Its own column and one line: "prêts pour le raid" ran out of the card (#148).
            chip.label:SetWidth(chipW)
            chip.label:SetWordWrap(false)
            chip.label:SetJustifyH("LEFT")
            card.chips[i] = chip
        end
        local foot = text(body, string.format("Lv 1-19: %d  ·  20-39: %d  ·  40-59: %d  ·  %d: %d", band[1], band[2], band[3], GuildOS.Client.maxLevel, band[4]), 0, 0, w, C.label, "caption")   -- EKO patch (was raid-ready)
        foot:ClearAllPoints()
        foot:SetPoint("BOTTOMLEFT", 0, 0)
    end

    local function fillRecruit(card)
        local body, w = card.body, card.innerW
        clearBody(body)
        -- Switched off in Settings, no popup will come: say so instead of offering one (issue #84).
        if not GuildOS:IsFeatureEnabled("recruitment") then
            text(body, L["The Recruitment module is off. Turn it on in Settings > Modules."], 0, 0, w, C.textSoft, nil, true)
            return
        end
        local info = GuildOS.db and GuildOS.db.guildRecruitment
        local isOfficer = GuildOS:IsOfficer()
        -- EKO patch: officers see the guild's recruiting at a glance (UI/EKO.lua); the card still opens Recruitment.
        local EKO = GuildOS.EKO
        if isOfficer and EKO and EKO.SuggestCached then
            local d = EKO:SuggestCached()
            local today, week = EKO:JoinCounts()
            local y = 0
            local function stat(col, s) markLine(body, col, C.text, s, y, w); y = y + 20 end
            stat(C.ok or C.green, string.format("%d joined today  ·  %d this week", today, week))
            stat((d.joinOpen or 0) > 0 and (C.danger or C.red) or C.label, string.format("%d open join request(s)", d.joinOpen or 0))
            stat((d.ready or 0) > 0 and (C.warn or C.gold) or C.label, string.format("%d trial(s) ending in %d days  ·  %d ready to review", #(d.soon or {}), EKO.SOON_DAYS, d.ready or 0))
            stat(#(d.candidates or {}) > 0 and (C.ok or C.green) or C.label, string.format("%d Recruit(s) ready for Outlaw", #(d.candidates or {})))
            local b = ghost(body, "Open Suggestions")
            b:SetScript("OnClick", function() UI:OpenWindow("management", "suggest") end)
            b:SetPoint("BOTTOMLEFT", 0, 0)
            card.action = b
            return
        end
        if not info or not info.enabled or not info.message or info.message == "" then
            local txt = isOfficer and L["Recruitment is off. Set it up in the Recruitment tab."]
                                   or L["Your guild isn't recruiting right now."]
            text(body, txt, 0, 0, w, C.textSoft, nil, true)
            return
        end
        text(body, L["Guild is recruiting"], 0, 0, w, C.text, "memberName")
        -- An officer's text, relayed member to member (#377).
        text(body, "\"" .. truncate(GuildOS:SanitizeUserText(info.message), 90) .. "\"", 0, 22, w, C.textSoft, nil, true)

        local b
        if isOfficer then
            b = ghost(body, L["Broadcast now"])
            b:SetScript("OnClick", function() if GuildOS.Recruitment then GuildOS.Recruitment:BroadcastStatus() end end)
        elseif GuildOS.Recruitment and GuildOS.Recruitment:MemberMayPost() then
            -- Opt-in (#150): only an explicit choice helps; a member past the officers' rank is not offered it.
            local participating = GuildOS.db.recruitParticipate == true
            b = ghost(body, participating and L["Helping"] or L["Help spread it"])
            UI:SetSelected(b, participating)
            b:SetScript("OnClick", function()
                if GuildOS.Recruitment then GuildOS.Recruitment:SetParticipation(not participating) end
                f.Refresh()
            end)
        end
        if b then b:SetPoint("BOTTOMLEFT", 0, 0) end
        card.action = b
    end

    -- EKO patch: the Events card. This week's Location of the Week theme, your bounty points and raffle
    -- tickets, the clears you are in this week, and the next Sunday raffle draw.
    local function fillEvents(card)
        local body, w = card.body, card.innerW
        clearBody(body)
        local EKO = GuildOS.EKO
        if not EKO then return end
        local me = GuildOS.Compat.PlayerName()

        local lotw = EKO:Lotw()
        local theme = lotw and type(lotw.text) == "string" and lotw.text:match("Theme:%s*([^|\n]+)")
        text(body, L["Location of the Week"], 0, 0, w, C.label, "caption")
        local themeTxt = theme and theme:match("^%s*(.-)%s*$") or ""
        text(body, themeTxt ~= "" and truncate(GuildOS:SanitizeUserText(themeTxt), 30) or L["No location posted yet"],
            0, 16, w, C.text, "memberName")

        -- Your points: one per dungeon clear, two when the party was a full five. Tickets: the raffle list.
        local pts, clears = 0, 0
        for _, c in ipairs(EKO:VerifiedClears()) do
            local who, mine = c.who or {}, false
            for _, name in ipairs(who) do if name == me then mine = true break end end
            if mine then
                clears = clears + 1
                pts = pts + ((#who >= 5) and 2 or 1)
            end
        end
        local tickets = 0
        for _, e in ipairs((EKO:ParseRaffle(EKO:Raffle().text))) do
            if e.name == me then tickets = e.n end
        end
        text(body, string.format(L["Bounty points %d  ·  Raffle tickets %d"], pts, tickets), 0, 40, w, C.text, "tableNum")
        text(body, string.format(L["%d clear(s) this week"], clears), 0, 60, w, C.textSoft, "caption")

        -- Raffle draws run on Sundays: the next one, today included.
        local t = nowT()
        local daysToSun = (7 - tonumber(date("%w", t))) % 7
        local drawTxt = daysToSun == 0 and L["Raffle draw: today"]
            or string.format(L["Next raffle draw: %s"], GuildOS:LocalDate("%a %d %b", t + daysToSun * 86400))
        text(body, drawTxt, 0, 80, w, C.label, "caption")
    end

    -- The Outlaw Gazette (OutlawOS): the first lines of this week's post, with the full text one click away.
    local function fillGazette(card)
        local body, w = card.body, card.innerW
        clearBody(body)
        local gz = GuildOS.EKO and GuildOS.EKO:Gazette() or nil
        if type(gz) ~= "string" or gz == "" then
            text(body, "The Gazette is empty this week.", 0, 0, w, C.textSoft, nil, true)
            return
        end
        -- Preview: as many lines of the Gazette as the card has room for above the Open button.
        -- Height is measured, so wrapped lines count and nothing runs under the button.
        local lines = {}
        for raw in (gz .. "\n"):gmatch("([^\n]*)\n") do
            local s = raw:gsub("%*%*(.-)%*%*", "%1"):gsub("%*(.-)%*", "%1")
            s = s:gsub(":%w+:", ""):gsub("^%s+", ""):gsub("%s+$", "")
            if s ~= "" then lines[#lines + 1] = s end
        end
        local BUTTON_H, GAP = 22, STACK
        local avail = (card.innerH or (CARD_H - BUTTON_H - BODY_TOP)) - BUTTON_H - GAP
        local fs = text(body, "", 0, 0, w, C.text, nil, true)
        local n = #lines
        local function build(k)
            return table.concat(lines, "\n", 1, k) .. (k < #lines and "..." or "")
        end
        fs:SetText(build(n))
        while n > 1 and fs:GetStringHeight() > avail do
            n = n - 1
            fs:SetText(build(n))
        end
        local open = UI:CreateButton(body, "Open the Gazette", 150, 22)
        open:SetPoint("BOTTOMLEFT", 0, 0)
        open:SetScript("OnClick", function() GuildOS.EKO:ShowGazettePopup(gz) end)
    end

    -- Each step, and the tab that helps with it; the line under them says what the site asks for.
    local SETUP = {
        publish = { L["Publish through the companion"], "web" },
        bot = { L["Add the bot to your Discord"], "web" },
        account = { L["Confirm a leader's character"], "web" },
        members = { L["5 members with the addon"], "roster" },
        run = { L["First group run"] },
    }
    local function fillSetup(card, state)
        local body, w = card.body, card.innerW
        clearBody(body)
        local A = GuildOS.Activation
        local count = text(body, string.format("%d / %d", state.done, #A.STEPS), 0, 2, nil, C.text, "tableNum")
        local hide = ghost(body, L["Hide"])
        hide:SetPoint("TOPRIGHT", 0, 4)
        hide:SetScript("OnClick", function() A:Hide(GetServerTime()); f.Refresh() end)
        local half = math.floor(w / 2)
        for i, id in ipairs(A.STEPS) do
            local step = SETUP[id]
            local col, row = (i - 1) % 2, math.floor((i - 1) / 2)
            local done = state.steps[id]
            local fs = markLine(body, done and C.ok or C.lineHi, C.text, step[1], 26 + row * 18, half - 8, col * half)
            if step[2] and not done then
                local b = CreateFrame("Button", nil, body)
                b:SetAllPoints(fs)
                b:SetScript("OnClick", function() goTab(step[2]) end)
            end
        end
        text(body, L["The bot and the character are set up on guildos.me/start. A group run is a dungeon cleared by 3 members with the addon."],
            0, 84, w, C.textSoft)
        if state.staleDays then
            local old = text(body, string.format(L["Verified %d days ago · log out once to update"], state.staleDays),
                0, 0, nil, C.label, "caption")
            old:ClearAllPoints()
            old:SetPoint("LEFT", count, "RIGHT", 10, 0)
        end
    end

    ------------------------------------------------------------------
    -- Layout: equal cells, and the fill
    ------------------------------------------------------------------
    local function setupDue()
        if not cSetup then return false end
        local A = GuildOS.Activation
        local ok, show = GuildOS:SafeCall(A.ShouldShow, A, GetServerTime())
        return ok and show or false
    end

    -- What Agora last asked for, so a refresh lays the cards out the same way.
    local last = nil
    panel.dash = { cards = grid, setup = cSetup }

    -- Place the cards in `w`: two columns while each keeps CARD_MIN_W, else one; every cell the same
    -- size (#377). With `fill`, the rows share `h` out (beside the column), never under CARD_MIN_H;
    -- otherwise each is CARD_H (under the column). The setup card, while due, spans the grid's top.
    -- Returns the height used.
    function panel.Layout(w, h, fill, gutter)
        last = { w = w, h = h, fill = fill, gutter = gutter }
        local g = gutter or GUTTER
        local top = 0
        local due = setupDue()
        if cSetup then
            local was = cSetup:IsShown()
            cSetup:SetShown(due)
            if due then
                cSetup:ClearAllPoints()
                cSetup:SetPoint("TOPLEFT", 0, 0)
                cSetup:SetSize(w, SETUP_H)
                cSetup.innerW, cSetup.innerH = w - 2 * PAD, SETUP_H - BODY_TOP - PAD
                top = SETUP_H + g
                -- Due on the 10s repaint, not only on a tab open: filled as it comes, never empty (#377).
                if not was then GuildOS:SafeCall(fillSetup, cSetup, GuildOS.Activation:Read(GetServerTime())) end
            end
        end
        -- OutlawOS: the Gazette card replaces Your Loot, shown whenever EKO is loaded.
        cLoot:SetShown(GuildOS.EKO ~= nil)
        cEvents:SetShown(GuildOS.EKO ~= nil)
        cRecruit:SetShown(GuildOS.EKO == nil)
        local shown = {}
        for _, card in ipairs(grid) do
            if card:IsShown() then shown[#shown + 1] = card end
        end
        local cols = ((w - g) / 2 >= CARD_MIN_W) and 2 or 1
        local cw = math.floor((w - g * (cols - 1)) / cols)
        local rows = math.ceil(#shown / cols)
        local ch = CARD_H
        if fill and h then ch = math.max(CARD_MIN_H, math.floor((h - top - g * (rows - 1)) / rows)) end
        for i, card in ipairs(shown) do
            local col, row = (i - 1) % cols, math.floor((i - 1) / cols)
            card:ClearAllPoints()
            card:SetPoint("TOPLEFT", col * (cw + g), -(top + row * (ch + g)))
            card:SetSize(cw, ch)
            card.innerW, card.innerH = math.max(1, cw - 2 * PAD), math.max(1, ch - BODY_TOP - PAD)
        end
        panel.dash.cols, panel.dash.cardW, panel.dash.cardH = cols, cw, ch
        return top + rows * ch + math.max(0, rows - 1) * g
    end

    local lastHeight
    function f.Refresh()
        -- Drawn alone (no Agora yet), the panel's own size, one column of three.
        local l = last or {}
        local w = l.w or panel:GetWidth() or 0
        if w < 200 then w = 640 end
        local h = l.h
        if l.fill == nil and not h then h = panel:GetHeight() or 0; if h < 200 then h = 516 end end
        local fill = l.fill
        if fill == nil then fill = true end
        local used = panel.Layout(w, h, fill, l.gutter)
        -- The guild's setup came or went: the grid's height changed, so Agora places it again.
        if lastHeight and used ~= lastHeight and panel.relayout then panel.relayout() end
        lastHeight = used

        -- A failure leaves the rest of the cards as they were (issue #217).
        if cSetup and cSetup:IsShown() then
            GuildOS:SafeCall(fillSetup, cSetup, GuildOS.Activation:Read(GetServerTime()))
        end

        -- One readiness scan powers both the readiness + pulse cards.
        local rows = GuildOS.Readiness and GuildOS.Readiness:GetReport() or {}
        local myShort = GuildOS.Compat.PlayerName()
        local myRow
        for _, r in ipairs(rows) do if r.name == myShort then myRow = r break end end

        fillNext(cNext)
        -- If the countdown fails, the card it replaced: the rest of the cards still draw (issue #232).
        local R, ok, countdown = GuildOS.Readiness, false, nil
        if R and R.Countdown then ok, countdown = GuildOS:SafeCall(R.Countdown, R, rows, GetServerTime()) end
        if not (ok and countdown and GuildOS:SafeCall(fillCountdown, cReady, countdown)) then
            cReady.hdr:SetText(L["YOUR READINESS"])
            fillReady(cReady, myRow)
        end
        fillPulse(cPulse, rows)
        fillRecruit(cRecruit)
        fillEvents(cEvents)
        if cLoot:IsShown() then fillGazette(cLoot) end
        chatRefresh()
    end

    -- Refresh whenever the tab becomes visible.
    panel:HookScript("OnShow", function() GuildOS:SafeCall(f.Refresh) end)

    -- ...and when Agora resizes the grid, because the fills size their text to the cards. A fill
    -- runs a readiness scan, far too heavy for the once-per-frame rate a grip drag produces, so
    -- this debounces and ignores changes too small to move a card.
    local lastW, pending = nil, false
    UI:MakeResponsive(panel, function(_, w)
        if lastW and math.abs(w - lastW) < 8 then return end
        lastW = w
        if pending then return end
        pending = true
        C_Timer.After(0.2, function()
            pending = false
            GuildOS:SafeCall(f.Refresh)
        end)
    end)

    return f.Refresh
end
