----------------------------------------------------------------------
-- Guild OS - Alliance panel
-- The Alliance tab: who is federated with us, how fresh their data is, and the
-- officer controls for the pact. Two sub-tabs: Overview and Manage.
--
-- Rule 10: no business logic here. Everything is rendered from
-- Alliance:Summary() / Alliance:CanAdminister(); actions call module methods.
----------------------------------------------------------------------
local UI = GuildOS.UI
local C  = GuildOS.Colors
local L  = GuildOS.L

local ROW_H = 22
local TAB_H = 28        -- UI:CreateTab's fixed height
local TAB_MIN_W = 80    -- narrowest a sub-tab may be drawn
local TAB_PAD = 20      -- label padding inside a sub-tab

-- Wrapped hint texts whose width has to follow the panel rather than the
-- fixed 460px they used to assume. Collected per CreateAlliancePanel call
-- (the builder runs once per container), so the expanded-mode tab and the
-- floating window never fight over one shared list.
local flexHints = nil
local function addFlexHint(fs)
    if flexHints then flexHints[#flexHints + 1] = fs end
end

local function ALLY() return GuildOS.Alliance end

-- Explicit Show/Hide instead of SetShown: everywhere else in this codebase
-- SetShown is only ever called on Frames, and these groups mix in FontStrings
-- and Textures. Show/Hide is defined on every region, so this cannot surprise.
local function setShown(widget, cond)
    if cond then widget:Show() else widget:Hide() end
end

local function clear(child)
    for _, c in pairs({ child:GetChildren() }) do c:Hide() end
    for _, r in pairs({ child:GetRegions() }) do r:Hide() end
end

-- The shared field (#371). Its own Escape, focus and hint handlers are hooks, so callers may set
-- OnEnterPressed but hook anything else.
local function makeInput(parent, width, opts)
    return UI:CreateInput(parent, width, 24, opts)
end

-- A colour token as the hex an inline |c code takes: secondary text inside a line keeps the palette
-- instead of a hard-coded grey (#371).
local function hex(c)
    return string.format("%02x%02x%02x", c.r * 255, c.g * 255, c.b * 255)
end

-- Room over a later section title for the rule UI:CreateSectionTitle draws 12px above it, and the
-- height a title takes with the gap under it (#371).
local SECTION_ABOVE, TITLE_H = 20, 24

-- A scroll frame filling `holder` and reaching UI.SCROLL_GUTTER past its right edge: the child stops
-- that gutter short (BindScrollChildWidth), so the content ends where the screen's other lines do and
-- the bar sits in the margin, not over the content (#371).
local function fillScroll(scroll, content)
    scroll:SetPoint("TOPLEFT", 0, 0)
    scroll:SetPoint("BOTTOMRIGHT", UI.SCROLL_GUTTER, 0)
    UI:BindScrollChildWidth(scroll, content)
end

-- Sizes for the redesigned Overview: one allied guild's card, one upcoming event row.
local CARD_H = 78
local EVENT_H = 26

-- A flat coloured square, used for status dots.
local function square(parent, size, r, g, b)
    local t = parent:CreateTexture(nil, "ARTWORK")
    t:SetSize(size, size)
    t:SetColorTexture(r, g, b, 1)
    return t
end

-- A 3px strip down the left edge of a card or row, in that guild's own colour.
local function guildStrip(parent, guildName)
    local t = parent:CreateTexture(nil, "ARTWORK")
    t:SetPoint("TOPLEFT", 0, 0)
    t:SetPoint("BOTTOMLEFT", 0, 0)
    t:SetWidth(3)
    t:SetColorTexture(GuildOS.Alliance.GuildColor(guildName))
    return t
end

-- "1 guild, 4 members" rather than "1 guilds, 4 members".
local function guildCountText(n, members)
    if n == 1 then return string.format(L["%d guild, %d members"], n, members) end
    return string.format(L["%d guilds, %d members"], n, members)
end

-- Leaders of each allied guild, from the roster held for it, and whether one of them is on the mesh.
local function collectLeaderGuilds(ally)
    local out = {}
    local pact = ally and ally:Get()
    local sync, net = GuildOS.AllianceSync, _G.ChehulNet
    if not (pact and sync and sync._BuildRoster) then return out end
    local mine, now = ally:MyGuildName(), time()
    local peers = (net and net.Peers and net:Peers()) or {}
    local ttl = (net and net.PEER_TTL) or 600
    local own = ally:OwnRoster()
    for guildName in pairs(pact.guilds) do
        if not ally:IsBlocked(guildName) then
            local rows
            if guildName == mine then
                rows = sync._BuildRoster(GuildOS.db.members, sync.ROSTER_CAP, GuildOS.db.altLinks)
            else
                local entry = sync:Remote(guildName, "roster")
                rows = entry and type(entry.data) == "table" and entry.data or {}
            end
            local leaders = {}
            for _, r in ipairs(rows) do
                if r.ld and r.n then
                    local short = r.n:match("^([^-]+)") or r.n
                    local online
                    if guildName == mine then
                        -- Our own guild: the game says who is online, mesh or no mesh.
                        online = own.onlineNames[short] == true
                    else
                        local pe = peers[short]
                        online = pe ~= nil and (now - (pe.ts or 0)) <= ttl
                    end
                    leaders[#leaders + 1] = { name = short, role = r.ld, online = online }
                end
            end
            if #leaders > 0 then
                table.sort(leaders, function(a, b)
                    if a.online ~= b.online then return a.online end
                    return a.name < b.name
                end)
                out[#out + 1] = { guild = guildName, leaders = leaders, mine = guildName == mine }
            end
        end
    end
    table.sort(out, function(a, b) return a.guild < b.guild end)
    return out
end

----------------------------------------------------------------------
-- Overview: the header band, the allied guild table, the blocked list.
----------------------------------------------------------------------
local function BuildOverview(panel)
    local empty = UI:CreateText(panel, "", 12, C.textSoft.r, C.textSoft.g, C.textSoft.b)
    empty:SetPoint("TOPLEFT", 0, 0)
    empty:SetPoint("RIGHT", 0, 0)
    empty:SetJustifyH("LEFT")
    empty:SetWordWrap(true)

    -- The alliance is the screen's first section (#371): the shared title, no gold and no gold rule.
    local title = UI:CreateSectionTitle(panel, "", true)
    title:SetPoint("TOPLEFT", 0, 0)

    local status = UI:CreateText(panel, "", 11, C.label.r, C.label.g, C.label.b)
    status:SetPoint("TOPLEFT", 0, -22)

    local holder = CreateFrame("Frame", nil, panel)
    holder:SetPoint("TOPLEFT", 0, -36 - UI.GAP)
    holder:SetPoint("BOTTOMRIGHT", 0, 0)
    -- CreateScrollFrame does NOT anchor the scroll frame; without this the
    -- content is clipped to 0x0 and renders as nothing, with no error.
    local scroll, content = UI:CreateScrollFrame(holder, "GuildOSAllianceOverviewScroll")
    fillScroll(scroll, content)

    -- A later section's title inside the list, with the room its rule needs above it.
    local function sectionTitle(text, y)
        y = y + SECTION_ABOVE
        local fs = UI:CreateSectionTitle(content, text)
        fs:SetPoint("TOPLEFT", 0, -y)
        return y + TITLE_H
    end

    local function refresh()
        local ally = ALLY()
        local summary = ally and ally:Summary()

        clear(content)

        if not summary then
            title:Hide()
            status:Hide()
            empty:Show()
            empty:SetText(GuildOS:IsOfficer()
                and L["This guild is not in an alliance yet. Use the Manage tab to join or found one."]
                or L["This guild is not in an alliance yet."])
            return
        end

        empty:Hide()
        title:Show()
        status:Show()

        -- The name takes the width it needs; the tag and the size follow it as secondary text (#371).
        title:SetText(string.format("%s  |cff%s[%s]  %s|r",
            summary.name, hex(C.label), summary.tag,
            guildCountText(#summary.guilds, summary.members)))

        local bridgeText = summary.bridge or L["nobody online"]
        if summary.amBridge then
            bridgeText = bridgeText .. " " .. L["(you)"]
        end
        local chanText = summary.connected and L["connected"] or L["not connected"]
        status:SetText(string.format("%s  \194\183  %s %s",
            string.format(L["Bridge: %s"], bridgeText),
            summary.channel or "?", chanText))

        local y = 0
        local cal = GuildOS.Calendar
        local events = (cal and cal.AllianceEvents and cal:AllianceEvents()) or {}
        -- Our own shared events join the alliance's: one list, soonest first.
        for _, ev in ipairs((cal and cal.OwnAllianceEvents and cal:OwnAllianceEvents()) or {}) do
            events[#events + 1] = ev
        end
        table.sort(events, function(a, b) return (a.when or 0) < (b.when or 0) end)
        local leaderGuilds = collectLeaderGuilds(ally)

        -- The next event each allied guild has published, and how many of its leaders are on the mesh.
        local nextByGuild, leadersOn = {}, {}
        for _, ev in ipairs(events) do
            if ev.guild and not nextByGuild[ev.guild] then nextByGuild[ev.guild] = ev end
        end
        for _, lg in ipairs(leaderGuilds) do
            local on = 0
            for _, l in ipairs(lg.leaders) do
                if l.online then on = on + 1 end
            end
            leadersOn[lg.guild] = { on = on, total = #lg.leaders }
        end

        ------------------------------------------------------------------
        -- Schedule conflicts. Only rendered when there is something to say,
        -- so a healthy week costs no vertical space at all.
        ------------------------------------------------------------------
        local conflicts = (cal and cal.AllianceConflicts and cal:AllianceConflicts()) or {}
        if #conflicts > 0 then
            y = sectionTitle(string.format(L["SCHEDULE CONFLICTS (%d)"], #conflicts), y)

            for i = 1, math.min(#conflicts, 6) do
                local c = conflicts[i]
                local mins = math.floor((c.gap or 0) / 60)
                local gapText = mins >= 60
                    and string.format(L["%dh%02d apart"], math.floor(mins / 60), mins % 60)
                    or string.format(L["%dmin apart"], mins)
                local head = UI:CreateText(content, string.format(
                    "%s  %s  |cff%sx|r  %s  |cff%s%s  %s|r",
                    GuildOS:LocalDate("%a %H:%M", c.mine.when), c.mine.title or "?",
                    hex(C.label), c.theirs.title or "?", hex(C.label), c.theirs.guild or "?", gapText),
                    11, C.text.r, C.text.g, C.text.b)
                -- Held by both sides of the list, not sized from its width (#371).
                head:SetPoint("TOPLEFT", 0, -y)
                head:SetPoint("RIGHT", content, "RIGHT", 0, 0)
                head:SetJustifyH("LEFT")
                head:SetWordWrap(false)
                y = y + 15

                local detail
                if c.sharedCount > 0 then
                    detail = string.format(L["%d signed up for both: %s"],
                        c.sharedCount, table.concat(c.shared, ", "))
                else
                    detail = L["nobody in common"]
                end
                local sub = UI:CreateText(content, detail, 10,
                    c.sharedCount > 0 and C.red.r or C.textDim.r,
                    c.sharedCount > 0 and C.red.g or C.textDim.g,
                    c.sharedCount > 0 and C.red.b or C.textDim.b)
                sub:SetPoint("TOPLEFT", 8, -y)
                sub:SetPoint("RIGHT", content, "RIGHT", 0, 0)
                sub:SetJustifyH("LEFT")
                sub:SetWordWrap(false)
                y = y + 17
            end
            y = y + UI.GAP
        end

        ------------------------------------------------------------------
        -- One card per allied guild: identity, freshness, who vouches for it, and what it has
        -- coming up. The table below keeps the exact numbers.
        ------------------------------------------------------------------
        y = sectionTitle(L["ALLIED GUILDS"], y)
        for _, g in ipairs(summary.guilds) do
            local gr, gg, gb = ally.GuildColor(g.name)
            local card = CreateFrame("Frame", nil, content, "BackdropTemplate")
            card:SetHeight(CARD_H)
            card:SetPoint("TOPLEFT", 0, -y)
            card:SetPoint("TOPRIGHT", 0, -y)
            card:SetBackdrop({
                bgFile = "Interface\\Buttons\\WHITE8x8",
                edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = GuildOS.UI:Edge(card),
            })
            card:SetBackdropColor(C.panel.r, C.panel.g, C.panel.b, 1)
            card:SetBackdropBorderColor(C.line.r, C.line.g, C.line.b, 1)
            guildStrip(card, g.name)

            -- Line 1: the name in the guild's colour, and how many of its members the mesh can see.
            local label = g.name
            if g.isOwner then label = label .. "  " .. L["(owner)"] end
            if g.isMine then label = label .. "  " .. L["(you)"] end
            local nameFs = UI:CreateText(card, label, 13, gr, gg, gb)
            nameFs:SetPoint("TOPLEFT", 14, -10)

            local seenFs = UI:CreateText(card, string.format(g.live and L["%d/%d online"] or L["%d/%d seen"], g.seen, g.members), 11,
                C.textDim.r, C.textDim.g, C.textDim.b)
            seenFs:SetPoint("TOPRIGHT", -10, -12)
            local live = g.seen > 0
            local dot = square(card, 7,
                live and C.online.r or C.offline.r,
                live and C.online.g or C.offline.g,
                live and C.online.b or C.offline.b)
            dot:SetPoint("RIGHT", seenFs, "LEFT", -6, 0)

            -- Line 2: the ambassadors who vouch for it, and when its data last arrived.
            local amb = table.concat(g.ambassadors, ", ")
            local ambFs = UI:CreateText(card, string.format(L["Ambassadors: %s"], amb ~= "" and amb or "-"),
                11, C.textDim.r, C.textDim.g, C.textDim.b)
            ambFs:SetPoint("TOPLEFT", 14, -32)
            ambFs:SetPoint("RIGHT", card, "RIGHT", -150, 0)
            ambFs:SetJustifyH("LEFT")
            ambFs:SetWordWrap(false)

            local ageFs = UI:CreateText(card, g.live and L["live"] or (g.ts and GuildOS:TimeAgo(g.ts) or L["never"]), 11,
                C.textDim.r, C.textDim.g, C.textDim.b)
            ageFs:SetPoint("TOPRIGHT", -10, -32)

            -- Line 3: the next event this guild has published, and how many of its leaders are online.
            local nx = nextByGuild[g.name]
            local nextText = L["No events scheduled"]
            if nx then
                nextText = string.format(L["Next: %s"],
                    string.format("%s  %s", GuildOS:LocalDate("%a %H:%M", nx.when), nx.title or "?"))
            end
            local nextFs = UI:CreateText(card, nextText, 11, C.text.r, C.text.g, C.text.b)
            nextFs:SetPoint("TOPLEFT", 14, -54)
            nextFs:SetPoint("RIGHT", card, "RIGHT", -150, 0)
            nextFs:SetJustifyH("LEFT")
            nextFs:SetWordWrap(false)

            local lo = leadersOn[g.name]
            if lo then
                local leadFs = UI:CreateText(card, string.format(L["%d of %d leaders online"], lo.on, lo.total),
                    11, C.label.r, C.label.g, C.label.b)
                leadFs:SetPoint("TOPRIGHT", -10, -54)
            end

            y = y + CARD_H + 6
        end
        y = y + UI.GAP

        ------------------------------------------------------------------
        -- Allied guilds: the table keeps the exact numbers under the cards (#371).
        ------------------------------------------------------------------
        local COLS = {
            { label = L["GUILD"],       x = 0 },
            { label = L["SEEN"],        x = 200 },
            { label = L["AMBASSADORS"], x = 274 },
            { label = L["LAST SYNC"],   x = 478 },
        }
        local header = UI:CreateTableHeader(content)
        header:SetPoint("TOPLEFT", 0, -y)
        header:SetPoint("TOPRIGHT", 0, -y)
        for _, col in ipairs(COLS) do
            local fs = UI:CreateHeaderText(header, col.label, 10)
            fs:SetPoint("LEFT", col.x, 0)
            fs:SetJustifyH("LEFT")
        end
        y = y + 22

        for i, g in ipairs(summary.guilds) do
            local row = CreateFrame("Frame", nil, content)
            row:SetHeight(ROW_H)
            row:SetPoint("TOPLEFT", 0, -y)
            row:SetPoint("TOPRIGHT", 0, -y)

            local bg = row:CreateTexture(nil, "BACKGROUND")
            bg:SetAllPoints()
            local rc = (i % 2 == 0) and C.row2 or C.row1
            bg:SetColorTexture(rc.r, rc.g, rc.b, rc.a or 1)

            -- Filled marker when the mesh can see somebody from that guild,
            -- hollow when it cannot. Data never vanishes; it just ages.
            local live = g.seen > 0
            local mark = UI:CreateText(row, live and "*" or "o", 12,
                live and C.online.r or C.offline.r,
                live and C.online.g or C.offline.g,
                live and C.online.b or C.offline.b)
            mark:SetPoint("LEFT", 0, 0)

            -- The owner and you badges live on the card above; here the name stays on one line.
            local nameFs = UI:CreateText(row, g.name, 11, C.text.r, C.text.g, C.text.b)
            nameFs:SetPoint("LEFT", 12, 0)
            nameFs:SetWidth(184)
            nameFs:SetJustifyH("LEFT")
            nameFs:SetWordWrap(false)

            local seenFs = UI:CreateText(row, string.format("%d/%d", g.seen, g.members), 11,
                C.textDim.r, C.textDim.g, C.textDim.b)
            seenFs:SetPoint("LEFT", 200, 0)

            local amb = table.concat(g.ambassadors, ", ")
            local ambFs = UI:CreateText(row, amb, 11, C.textDim.r, C.textDim.g, C.textDim.b)
            ambFs:SetPoint("LEFT", 274, 0)
            ambFs:SetWidth(200)
            ambFs:SetJustifyH("LEFT")
            ambFs:SetWordWrap(false)

            local age = g.live and L["live"] or (g.ts and GuildOS:TimeAgo(g.ts) or L["never"])
            local ageFs = UI:CreateText(row, age, 11, C.textDim.r, C.textDim.g, C.textDim.b)
            ageFs:SetPoint("LEFT", 478, 0)

            row:EnableMouse(true)
            row:SetScript("OnEnter", function()
                bg:SetColorTexture(C.rowHover.r, C.rowHover.g, C.rowHover.b, 1)
                GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
                GameTooltip:AddLine(g.name)
                GameTooltip:AddLine(string.format(
                    L["Seen: %d of %d known members are visible on the presence mesh."],
                    g.seen, g.members), 0.8, 0.8, 0.8, true)
                GameTooltip:AddLine(L["Only players running OutlawOS are counted, so this is a floor, not the real online count."],
                    0.6, 0.6, 0.6, true)
                GameTooltip:Show()
            end)
            row:SetScript("OnLeave", function()
                bg:SetColorTexture(rc.r, rc.g, rc.b, rc.a or 1)
                GameTooltip:Hide()
            end)

            y = y + ROW_H
        end

        ------------------------------------------------------------------
        -- Leaders: each guild's leaders, with a dot for whether one is on OutlawOS right now.
        -- The presence mesh sees Guild OS clients only, so a leader without the addon reads not seen.
        ------------------------------------------------------------------
        if #leaderGuilds > 0 then
            y = y + UI.GAP
            y = sectionTitle(L["LEADERS ONLINE"], y)
            for _, g in ipairs(leaderGuilds) do
                local gr, gg, gb = ally.GuildColor(g.guild)
                local head = UI:CreateText(content,
                    g.guild .. (g.mine and ("  " .. L["(you)"]) or ""), 11, gr, gg, gb)
                head:SetPoint("TOPLEFT", 0, -y)
                y = y + 18
                for _, l in ipairs(g.leaders) do
                    local row = CreateFrame("Frame", nil, content)
                    row:SetHeight(16)
                    row:SetPoint("TOPLEFT", 12, -y)
                    row:SetPoint("TOPRIGHT", 0, -y)

                    local dot = square(row, 7,
                        l.online and C.online.r or C.offline.r,
                        l.online and C.online.g or C.offline.g,
                        l.online and C.online.b or C.offline.b)
                    dot:SetPoint("LEFT", 0, 0)

                    local nameFs = UI:CreateText(row, l.name, 11, C.text.r, C.text.g, C.text.b)
                    nameFs:SetPoint("LEFT", 14, 0)
                    nameFs:SetWidth(150)
                    nameFs:SetJustifyH("LEFT")

                    local roleFs = UI:CreateText(row, l.role, 11, C.textDim.r, C.textDim.g, C.textDim.b)
                    roleFs:SetPoint("LEFT", 170, 0)

                    local stateText = l.online and L["online"] or L["not seen"]
                    local stateFs
                    if l.online then
                        stateFs = UI:CreateText(row, stateText, 11, C.text.r, C.text.g, C.text.b)
                    else
                        stateFs = UI:CreateText(row, stateText, 11, C.textDim.r, C.textDim.g, C.textDim.b)
                    end
                    stateFs:SetPoint("LEFT", 300, 0)

                    y = y + 16
                end
                y = y + 8
            end
        end

        ------------------------------------------------------------------
        -- Upcoming events published by allied guilds, each in its guild's colour, with a slot request.
        ------------------------------------------------------------------
        if #events > 0 then
            y = y + UI.GAP
            y = sectionTitle(L["UPCOMING ALLIANCE EVENTS"], y)

            for i = 1, math.min(#events, 8) do
                local ev = events[i]
                local size = tonumber(ev.size) or GuildOS.Client.defaultRaidSize   -- from another guild
                local full = (ev.yes or 0) >= size
                local when = GuildOS:LocalDate("%a %H:%M", ev.when)

                local row = CreateFrame("Frame", nil, content)
                row:SetHeight(EVENT_H)
                row:SetPoint("TOPLEFT", 0, -y)
                row:SetPoint("TOPRIGHT", 0, -y)

                local bg = row:CreateTexture(nil, "BACKGROUND")
                bg:SetAllPoints()
                bg:SetColorTexture(C.well.r, C.well.g, C.well.b, 1)
                guildStrip(row, ev.guild)

                local fs = UI:CreateText(row, string.format("%s  %s  |cff%s%s|r  %d/%d",
                    when, ev.title or "?", ally.GuildColorHex(ev.guild), ev.guild or "?", ev.yes or 0, size),
                    11, C.text.r, C.text.g, C.text.b)
                fs:SetPoint("LEFT", 12, 0)
                fs:SetPoint("RIGHT", row, "RIGHT", -190, 0)
                fs:SetJustifyH("LEFT")
                fs:SetWordWrap(false)

                if ev.own then
                    local yoursFs = UI:CreateText(row, L["Yours"], 10, C.textDim.r, C.textDim.g, C.textDim.b)
                    yoursFs:SetPoint("RIGHT", row, "RIGHT", -8, 0)
                elseif full then
                    local fullFs = UI:CreateText(row, L["full"], 10, C.textDim.r, C.textDim.g, C.textDim.b)
                    fullFs:SetPoint("RIGHT", row, "RIGHT", -8, 0)
                else
                    local askBtn = UI:CreateButton(row, L["Request slot"], 100, 18)
                    askBtn:SetPoint("RIGHT", row, "RIGHT", -6, 0)
                    local roleBtn = UI:CreateButton(row, L["DPS"], 56, 18)
                    roleBtn.role = "DPS"
                    roleBtn:SetPoint("RIGHT", askBtn, "LEFT", -6, 0)
                    roleBtn:SetScript("OnClick", function()
                        local order = { TANK = "HEALER", HEALER = "DPS", DPS = "TANK" }
                        roleBtn.role = order[roleBtn.role] or "DPS"
                        roleBtn.label:SetText(({ TANK = L["Tank"], HEALER = L["Healer"], DPS = L["DPS"] })[roleBtn.role])
                    end)
                    askBtn:SetScript("OnClick", function()
                        local ok, err = GuildOS.Calendar:RequestAllianceSlot(
                            ev.id, ev.guild, roleBtn.role, "")
                        if ok then
                            GuildOS:Print(string.format(L["Slot requested from %s."], ev.guild))
                        elseif err then
                            GuildOS:Print(err)
                        end
                    end)
                end
                y = y + EVENT_H + 4
            end
        end

        if #summary.blocked > 0 then
            y = y + UI.GAP
            local fs = UI:CreateText(content,
                string.format(L["Blocked: %s"], table.concat(summary.blocked, ", ")),
                11, C.red.r, C.red.g, C.red.b)
            fs:SetPoint("TOPLEFT", 0, -y)
            y = y + ROW_H
        end

        content:SetHeight(math.max(y, 1))
    end

    return refresh
end

----------------------------------------------------------------------
-- Ally card: everything the alliance already knows about one character.
-- One reusable frame, re-anchored per click. Reads Alliance:SpeakerInfo, which
-- normalises allied and own-guild data into a single shape.
----------------------------------------------------------------------
local allyCard

local function ensureAllyCard()
    if allyCard then return allyCard end

    local f = CreateFrame("Frame", "GuildOSAllyCard", UIParent, "BackdropTemplate")
    f:SetSize(260, 200)
    f:SetFrameStrata("DIALOG")
    f:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = GuildOS.UI:Edge(f),
    })
    -- A floating card is elevation 4: popup surface, lineHi border.
    f:SetBackdropColor(C.popup.r, C.popup.g, C.popup.b, 1)
    f:SetBackdropBorderColor(C.lineHi.r, C.lineHi.g, C.lineHi.b, 1)
    f:EnableMouse(true)
    f:SetMovable(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    f:Hide()

    f.accent = f:CreateTexture(nil, "ARTWORK")
    f.accent:SetPoint("TOPLEFT")
    f.accent:SetPoint("TOPRIGHT")
    f.accent:SetHeight(2)

    f.icon = f:CreateTexture(nil, "ARTWORK")
    f.icon:SetSize(30, 30)
    f.icon:SetPoint("TOPLEFT", 12, -12)

    f.name = UI:CreateText(f, "", 14, C.text.r, C.text.g, C.text.b)
    f.name:SetPoint("TOPLEFT", 50, -12)
    f.guild = UI:CreateText(f, "", 10, C.textDim.r, C.textDim.g, C.textDim.b)
    f.guild:SetPoint("TOPLEFT", 50, -28)
    f.sub = UI:CreateText(f, "", 11, C.silver.r, C.silver.g, C.silver.b)
    f.sub:SetPoint("TOPLEFT", 12, -50)

    f.close = UI:CreateCloseButton(f)
    f.close:SetPoint("TOPRIGHT", -4, -4)
    f.close:SetScript("OnClick", function() f:Hide() end)

    f.body = UI:CreateText(f, "", 11, C.text.r, C.text.g, C.text.b)
    f.body:SetPoint("TOPLEFT", 12, -70)
    f.body:SetPoint("RIGHT", f, "RIGHT", -12, 0)
    f.body:SetJustifyH("LEFT")
    f.body:SetWordWrap(true)

    f.whisper = UI:CreateButton(f, L["Whisper"], 76, 22)
    f.whisper:SetPoint("BOTTOMLEFT", 12, 10)
    f.invite = UI:CreateButton(f, L["Invite"], 76, 22)
    f.invite:SetPoint("LEFT", f.whisper, "RIGHT", 6, 0)
    f.sheet = UI:CreateButton(f, L["Full sheet"], 82, 22)
    f.sheet:SetPoint("LEFT", f.invite, "RIGHT", 6, 0)

    -- Ban only. Kick was pointless here: the join watchdog puts the player
    -- back inside 20 seconds, so it promised something it could not deliver.
    -- A ban is refused by the server on rejoin, which is what actually holds.
    f.ban = UI:CreateButton(f, L["Ban from channel"], 118, 22)
    f.ban:SetPoint("BOTTOMLEFT", 12, 38)

    tinsert(UISpecialFrames, "GuildOSAllyCard")   -- ESC closes it
    allyCard = f
    return f
end

function GuildOS:ShowAllyCard(name, guild, anchor)
    local f = ensureAllyCard()
    local ally = GuildOS.Alliance
    local info = (ally and ally:SpeakerInfo(name)) or {}
    local cr, cg, cb = GuildOS:GetClassColor(info.class)

    f.accent:SetColorTexture(cr, cg, cb, 0.9)
    f.name:SetText(name or "?")
    f.name:SetTextColor(cr, cg, cb)
    f.guild:SetText(info.guild or guild or "")

    local coords = CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[info.class]
    if coords then
        f.icon:SetTexture("Interface\\WorldStateFrame\\Icons-Classes")
        f.icon:SetTexCoord(coords[1], coords[2], coords[3], coords[4])
        f.icon:Show()
    else
        f.icon:Hide()
    end

    local bits = {}
    if info.level then bits[#bits + 1] = tostring(info.level) end
    if info.class then bits[#bits + 1] = info.class end
    if info.spec then bits[#bits + 1] = info.spec end
    f.sub:SetText(table.concat(bits, "  \194\183  "))

    local lines = {}
    if info.main then
        lines[#lines + 1] = string.format(L["Alt of %s"], info.main)
    end
    if info.professions and #info.professions > 0 then
        local profs = {}
        for _, p in ipairs(info.professions) do
            profs[#profs + 1] = string.format("%s %d", L[p.n or "?"], p.r or 0)
        end
        -- A block's name in `label`, not a gold of its own (#371).
        lines[#lines + 1] = "|cff" .. hex(C.label) .. L["Professions"] .. "|r\n  " .. table.concat(profs, "\n  ")
    end
    if info.attunements and #info.attunements > 0 then
        lines[#lines + 1] = "|cff" .. hex(C.label) .. L["Attunements"] .. "|r\n  " ..
            table.concat(info.attunements, ", ")
    end
    if #lines == 0 then
        -- Be explicit rather than showing an empty card: for an ally we only
        -- ever know what their guild published.
        lines[#lines + 1] = "|cff" .. hex(C.textSoft) .. L["Nothing synced for this character yet."] .. "|r"
    end
    f.body:SetText(table.concat(lines, "\n\n"))

    f.whisper:SetScript("OnClick", function() ChatFrame_SendTell(name) end)
    f.invite:SetScript("OnClick", function() GuildOS.Compat.InviteUnit(name) end)

    -- The full member sheet only exists for our OWN guild: an ally's gear and
    -- history are simply not data we hold.
    setShown(f.sheet, info.own == true)
    if info.own then
        f.sheet:SetScript("OnClick", function()
            -- MemberDetail needs the merged roster view, not the raw synced
            -- entry: rank and classDisplay only exist on the live roster.
            local record = GuildOS:GetMemberRecord(name)
            if record and GuildOS.ShowMemberDetail then
                f:Hide()
                GuildOS:ShowMemberDetail(record)
            else
                GuildOS:Print(L["Could not load that character's sheet."])
            end
        end)
    end

    -- Moderating your own guildmates through a channel kick is the wrong tool:
    -- that is a guild matter, not an alliance one.
    local chat = GuildOS.AllianceChat
    local canModerate = ally and ally:CanAdminister() and info.own ~= true
        and chat and chat:CanModerate()
    setShown(f.ban, canModerate)
    if canModerate then
        f.ban:SetScript("OnClick", function()
            GuildOS:ShowDialog("GUILDOS_ALLY_BAN",
                string.format(L["Ban %s from the alliance channel? They cannot rejoin until unbanned."], name),
                nil, { name = name })
        end)
    end

    local extra = canModerate and 30 or 0
    f:SetHeight(math.max(150, 96 + (f.body:GetStringHeight() or 0) + 44 + extra))
    f:ClearAllPoints()
    if anchor then
        f:SetPoint("TOPLEFT", anchor, "TOPRIGHT", 12, 8)
    else
        f:SetPoint("CENTER")
    end
    f:Show()
end

----------------------------------------------------------------------
-- Chat: the alliance feed. Conversation and alliance events on one timeline,
-- which is the one thing a default chat tab cannot do.
----------------------------------------------------------------------
-- Copy: WoW gives an addon no clipboard to write to, so a line goes into a box with its text selected,
-- and Ctrl+C takes it from there.
local COPY_BOX
local function showCopyBox(text)
    if not COPY_BOX then
        local f = CreateFrame("Frame", "GuildOSAllyCopyBox", UIParent, "BackdropTemplate")
        f:SetSize(440, 96)
        f:SetPoint("CENTER")
        f:SetFrameStrata("DIALOG")
        f:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8x8",
            edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = GuildOS.UI:Edge(f),
        })
        f:SetBackdropColor(C.popup.r, C.popup.g, C.popup.b, 1)
        f:SetBackdropBorderColor(C.lineHi.r, C.lineHi.g, C.lineHi.b, 1)
        f:EnableMouse(true)

        local hint = UI:CreateText(f, L["Press Ctrl+C to copy, then Esc."], 11,
            C.textSoft.r, C.textSoft.g, C.textSoft.b)
        hint:SetPoint("TOPLEFT", 12, -10)

        local edit = makeInput(f, 416)
        edit:SetPoint("TOPLEFT", 12, -32)
        edit:HookScript("OnEscapePressed", function() f:Hide() end)

        local close = UI:CreateButton(f, L["Close"], 80, 22)
        close:SetPoint("BOTTOMRIGHT", -12, 10)
        close:SetScript("OnClick", function() f:Hide() end)

        f.edit = edit
        COPY_BOX = f
    end
    COPY_BOX.edit:SetText(text or "")
    COPY_BOX:Show()
    COPY_BOX.edit:SetFocus()
    COPY_BOX.edit:HighlightText()
end

local function BuildChat(panel)
    local CHAT = function() return GuildOS.AllianceChat end
    local ROW2_Y = 20 + UI.GAP            -- the search row
    local PIN_Y = ROW2_Y + 24 + UI.GAP    -- the pinned notice, when there is one, sits here

    -- Session state, not saved: the guild the feed is narrowed to, and the lines this session sent
    -- (Up recalls them). A new line of ours, or a jump, brings the feed back to its newest line.
    local filterGuild
    local history, historyAt = {}, nil
    local forceBottom = true

    -- Declared before anything that calls it: the buttons below close over it, and a later
    -- declaration would leave those closures pointing at a nil global.
    local refresh

    -- The status and the toggles share the screen's first line, flush with its edges (#371).
    local status = UI:CreateText(panel, "", 10, C.textDim.r, C.textDim.g, C.textDim.b)
    status:SetPoint("LEFT", panel, "TOPLEFT", 0, -10)

    local sysBtn = UI:CreateButton(panel, L["Events"], 90, 20)
    sysBtn:SetPoint("TOPRIGHT", 0, 0)
    local hideBtn = UI:CreateButton(panel, L["Default chat"], 120, 20)
    hideBtn:SetPoint("RIGHT", sysBtn, "LEFT", -6, 0)
    local clearBtn = UI:CreateButton(panel, L["Clear"], 70, 20)
    clearBtn:SetPoint("RIGHT", hideBtn, "LEFT", -6, 0)
    -- The allied guilds' /g in our guild chat (issue #344).
    local gchatBtn = UI:CreateButton(panel, L["Allied /g"], 120, 20)
    gchatBtn:SetPoint("RIGHT", clearBtn, "LEFT", -6, 0)

    -- Second row: the search box, and the guild the feed is narrowed to.
    local filterBtn = UI:CreateButton(panel, L["All guilds"], 150, 24)
    filterBtn:SetPoint("TOPRIGHT", 0, -ROW2_Y)
    local search = makeInput(panel, 200, { placeholder = L["Search the chat"] })
    search:SetPoint("TOPLEFT", 0, -ROW2_Y)
    search:SetPoint("RIGHT", filterBtn, "LEFT", -UI.GAP, 0)
    search:SetHeight(24)

    -- The pinned notice: one line an ambassador keeps at the top of the feed.
    local pinCard = CreateFrame("Frame", nil, panel, "BackdropTemplate")
    pinCard:SetPoint("TOPLEFT", 0, -PIN_Y)
    pinCard:SetPoint("TOPRIGHT", 0, -PIN_Y)
    pinCard:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = GuildOS.UI:Edge(pinCard),
    })
    pinCard:SetBackdropColor(C.bg2.r, C.bg2.g, C.bg2.b, 0.7)
    pinCard:SetBackdropBorderColor(C.gold.r, C.gold.g, C.gold.b, 0.5)
    local pinRail = pinCard:CreateTexture(nil, "ARTWORK")
    pinRail:SetPoint("TOPLEFT", 0, 0)
    pinRail:SetPoint("BOTTOMLEFT", 0, 0)
    pinRail:SetWidth(3)
    pinRail:SetColorTexture(C.gold.r, C.gold.g, C.gold.b, 0.95)
    local pinWho = UI:CreateText(pinCard, "", 10, C.textDim.r, C.textDim.g, C.textDim.b)
    pinWho:SetPoint("TOPLEFT", 14, -8)
    pinWho:SetJustifyH("LEFT")
    local pinBody = UI:CreateText(pinCard, "", 12, C.text.r, C.text.g, C.text.b)
    pinBody:SetPoint("TOPLEFT", 14, -24)
    pinBody:SetJustifyH("LEFT")
    pinBody:SetWordWrap(true)
    local pinUnpin = UI:CreateButton(pinCard, L["Unpin"], 64, 18)
    pinUnpin:SetPoint("TOPRIGHT", -8, -6)
    pinUnpin:SetScript("OnClick", function()
        local ok, err = ALLY():UnpinMessage()
        if not ok and err then GuildOS:Print(err) end
        refresh()
    end)
    pinCard:Hide()

    local holder = CreateFrame("Frame", nil, panel)
    holder:SetPoint("TOPLEFT", 0, -PIN_Y)
    holder:SetPoint("BOTTOMRIGHT", 0, 24 + UI.GAP)
    local scroll, content = UI:CreateScrollFrame(holder, "GuildOSAllianceChatScroll")
    fillScroll(scroll, content)

    local input = makeInput(panel, 100)
    input:SetPoint("BOTTOMLEFT", 0, 0)
    input:SetPoint("BOTTOMRIGHT", -(62 + UI.GAP), 0)
    local sendBtn = UI:CreateButton(panel, L["Send"], 62, 24)
    sendBtn:SetPoint("BOTTOMRIGHT", 0, 0)

    -- Shown only when the feed is scrolled up, away from its newest line.
    local jump = UI:CreateButton(panel, L["Latest"], 84, 22)
    jump:SetPoint("BOTTOMRIGHT", holder, "BOTTOMRIGHT", -14, 8)
    jump:Hide()

    local function atBottom()
        return scroll:GetVerticalScroll() >= scroll:GetVerticalScrollRange() - 4
    end
    scroll:HookScript("OnVerticalScroll", function() setShown(jump, not atBottom()) end)
    jump:SetScript("OnClick", function()
        forceBottom = true
        refresh()
    end)

    local empty = UI:CreateText(content, L["Nothing here yet. Say hello."], 11,
        C.textSoft.r, C.textSoft.g, C.textSoft.b)
    empty:Hide()

    -- A small text button on a card's top row. The card's own state is read at click time.
    local function actionButton(card, text, onClick)
        local btn = CreateFrame("Button", nil, card)
        btn:SetSize(40, 14)
        btn.fs = btn:CreateFontString(nil, "OVERLAY")
        GuildOS:ApplyFont(btn.fs, 9)
        btn.fs:SetPoint("RIGHT", btn, "RIGHT", 0, 0)
        btn.fs:SetText(text)
        btn.fs:SetTextColor(C.textDim.r, C.textDim.g, C.textDim.b)
        btn:SetScript("OnEnter", function() btn.fs:SetTextColor(C.text.r, C.text.g, C.text.b) end)
        btn:SetScript("OnLeave", function() btn.fs:SetTextColor(C.textDim.r, C.textDim.g, C.textDim.b) end)
        btn:SetScript("OnClick", onClick)
        return btn
    end

    -- Blocks are POOLED. Refresh runs on every incoming message and WoW never
    -- frees a frame, so building widgets per refresh leaked for the whole
    -- session. Created on demand, parked when the log shrinks.
    local CLASS_TEX = "Interface\\WorldStateFrame\\Icons-Classes"
    local blocks = {}
    local function getBlock(i)
        if blocks[i] then return blocks[i] end

        local card = CreateFrame("Frame", nil, content, "BackdropTemplate")
        card:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8x8",
            edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = GuildOS.UI:Edge(card),
        })

        -- Left accent bar in the speaker's guild colour. This is the "bubble":
        -- WHITE8x8 cannot round a corner without shipping an art asset, so the
        -- card reads as a card through the bar and the hairline border instead.
        local accent = card:CreateTexture(nil, "ARTWORK")
        accent:SetPoint("TOPLEFT", 0, 0)
        accent:SetPoint("BOTTOMLEFT", 0, 0)
        accent:SetWidth(3)

        local icon = card:CreateTexture(nil, "ARTWORK")
        icon:SetSize(20, 20)
        icon:SetPoint("TOPLEFT", 10, -7)

        -- Online dot, just right of the icon: green when the speaker is on right now.
        local presence = card:CreateTexture(nil, "ARTWORK")
        presence:SetSize(6, 6)
        presence:SetPoint("TOPLEFT", 33, -14)

        local nameFS = UI:CreateText(card, "", 11, C.text.r, C.text.g, C.text.b)
        nameFS:SetPoint("TOPLEFT", 42, -7)
        nameFS:SetJustifyH("LEFT")

        local timeFS = UI:CreateText(card, "", 9, C.textDim.r, C.textDim.g, C.textDim.b)
        timeFS:SetPoint("TOPRIGHT", -26, -9)

        -- What this card holds right now, read by its action buttons at click time.
        local st = {}
        local reply = actionButton(card, L["Reply"], function()
            if st.name then
                input:SetText(st.name .. ": ")
                input:SetFocus()
            end
        end)
        reply:SetPoint("RIGHT", timeFS, "LEFT", -10, 0)
        local copy = actionButton(card, L["Copy"], function()
            if st.text then showCopyBox(st.text) end
        end)
        copy:SetPoint("RIGHT", reply, "LEFT", -8, 0)
        local pinBtn = actionButton(card, L["Pin"], function()
            if st.text then
                local ok, err = ALLY():PinMessage(st.name .. ": " .. st.text)
                if not ok and err then GuildOS:Print(err) end
                refresh()
            end
        end)
        pinBtn:SetPoint("RIGHT", copy, "LEFT", -8, 0)

        local bodyFS = UI:CreateText(card, "", 11, C.text.r, C.text.g, C.text.b)
        bodyFS:SetPoint("TOPLEFT", 42, -22)
        bodyFS:SetJustifyH("LEFT")
        bodyFS:SetWordWrap(true)

        -- Only the icon and the name open the card: clicking the message text
        -- itself would fire every time somebody tries to select text.
        local hit = CreateFrame("Button", nil, card)
        hit:SetPoint("TOPLEFT", 8, -5)
        hit:SetSize(200, 22)
        -- Hovered, the name lights to `text` (#371): gold marks selection, not a link.
        hit:SetScript("OnEnter", function(self)
            if self.name then
                nameFS:SetTextColor(C.text.r, C.text.g, C.text.b)
            end
        end)
        hit:SetScript("OnLeave", function()
            local col = blocks[i] and blocks[i].nameColor
            if col then nameFS:SetTextColor(col[1], col[2], col[3]) end
        end)
        hit:SetScript("OnClick", function(self)
            if self.name and GuildOS.ShowAllyCard then
                GuildOS:ShowAllyCard(self.name, self.guild, self)
            end
        end)

        local hide = CreateFrame("Button", nil, card)
        hide:SetSize(16, 16)
        hide:SetPoint("TOPRIGHT", -4, -4)
        hide.fs = hide:CreateFontString(nil, "OVERLAY")
        GuildOS:ApplyFont(hide.fs, 12)
        hide.fs:SetPoint("CENTER")
        hide.fs:SetText("\195\151")
        hide.fs:SetTextColor(C.textDim.r, C.textDim.g, C.textDim.b)
        hide:SetScript("OnEnter", function(self)
            self.fs:SetTextColor(C.red.r, C.red.g, C.red.b)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:AddLine(L["Hide from the alliance feed"])
            GameTooltip:AddLine(L["The message was already delivered; this only clears it from the OutlawOS feed."],
                0.6, 0.6, 0.6, true)
            GameTooltip:Show()
        end)
        hide:SetScript("OnLeave", function(self)
            self.fs:SetTextColor(C.textDim.r, C.textDim.g, C.textDim.b)
            GameTooltip:Hide()
        end)
        hide:SetScript("OnClick", function(self)
            local ok, err = GuildOS.AllianceChat:HideMessage(self.who, self.text)
            if not ok and err then GuildOS:Print(err) end
            refresh()
        end)

        blocks[i] = {
            card = card, accent = accent, icon = icon, presence = presence,
            nameFS = nameFS, timeFS = timeFS, bodyFS = bodyFS, hit = hit,
            hide = hide, reply = reply, copy = copy, pinBtn = pinBtn, st = st,
            classTex = CLASS_TEX,
        }
        return blocks[i]
    end

    local function doSend()
        local chat = CHAT()
        if not chat then return end
        -- Enter and click are hardware events, which is what makes a channel
        -- send legal here at all (see Modules/RecruitmentSystem.lua).
        local text = input:GetText() or ""
        if chat:Send(text) then
            if text ~= "" then
                table.insert(history, 1, text)
                while #history > 20 do table.remove(history) end
            end
            historyAt = nil
            input:SetText("")
            forceBottom = true
        else
            GuildOS:Print(L["Not connected to the alliance channel."])
        end
        refresh()
    end
    sendBtn:SetScript("OnClick", doSend)
    input:SetScript("OnEnterPressed", doSend)

    -- Up recalls the lines this session sent, newest first; Down walks back toward an empty box.
    input:HookScript("OnArrowPressed", function(self, key)
        if key == "UP" and #history > 0 then
            historyAt = math.min((historyAt or 0) + 1, #history)
            self:SetText(history[historyAt])
        elseif key == "DOWN" and historyAt then
            historyAt = historyAt - 1
            if historyAt < 1 then
                historyAt = nil
                self:SetText("")
            else
                self:SetText(history[historyAt])
            end
        end
    end)

    clearBtn:SetScript("OnClick", function()
        if CHAT() then CHAT():Clear() end
        refresh()
    end)
    sysBtn:SetScript("OnClick", function()
        local p = CHAT() and CHAT():Prefs()
        if p then p.system = not p.system end
        refresh()
    end)
    hideBtn:SetScript("OnClick", function()
        local p = CHAT() and CHAT():Prefs()
        if p then p.hideDefault = not p.hideDefault end
        refresh()
    end)
    gchatBtn:SetScript("OnClick", function()
        local p = CHAT() and CHAT():Prefs()
        if p then p.guildBridge = not p.guildBridge end
        refresh()
    end)

    -- The guild filter steps through the pact's guilds in name order, then back to all of them.
    filterBtn:SetScript("OnClick", function()
        local list = {}
        local pact = ALLY():Get()
        if pact then
            for name in pairs(pact.guilds) do list[#list + 1] = name end
            table.sort(list)
        end
        local nextGuild
        if filterGuild == nil then
            nextGuild = list[1]
        else
            for i, name in ipairs(list) do
                if name == filterGuild then
                    nextGuild = list[i + 1]
                    break
                end
            end
        end
        filterGuild = nextGuild
        forceBottom = true
        refresh()
    end)

    search:HookScript("OnTextChanged", function() refresh() end)

    refresh = function()
        local chat = CHAT()
        if not chat then return end
        chat:MarkRead()
        -- The child's width is kept by BindScrollChildWidth (fillScroll), gutter included (#371).
        -- No clear() here: the rows are pooled, so this refresh shows exactly
        -- the ones it needs and parks the rest at the end.

        local ally = ALLY()
        local pact = ally and ally:Get()
        local AC = GuildOS.AllianceChat
        -- Whether the feed was already at its newest line before this refresh changes its height.
        local wasBottom = atBottom()

        local prefs = chat:Prefs()
        sysBtn.label:SetText(prefs.system and L["Events: on"] or L["Events: off"])
        hideBtn.label:SetText(prefs.hideDefault and L["Default chat: hidden"] or L["Default chat: shown"])
        gchatBtn.label:SetText(prefs.guildBridge and L["Allied /g: shown"] or L["Allied /g: hidden"])
        status:SetText(chat:IsConnected()
            and string.format(L["%s connected"], chat:ChannelName() or "?")
            or (chat:Prefs().chat and L["connecting..."] or L["not connected"]))

        -- The filter button names the guild it narrows to. A guild that has left the pact drops out of it.
        if filterGuild and not (pact and pact.guilds[filterGuild]) then filterGuild = nil end
        filterBtn.label:SetText(filterGuild and string.format(L["Guild: %s"], filterGuild) or L["All guilds"])

        -- The pinned notice holds its place above the feed; with none, the feed takes the room.
        local pinned = ally and ally:Pin()
        local canAdmin = ally and ally:CanAdminister()
        local holderTop = PIN_Y
        if pact and pinned and pinned.text then
            local who = string.format(L["Pinned by %s"], pinned.by or "?")
            if pinned.guild and pinned.guild ~= "" then who = who .. "  \194\183  " .. pinned.guild end
            if (pinned.ts or 0) > 0 then
                who = who .. "  \194\183  " .. GuildOS:LocalDate("%a %H:%M", pinned.ts)
            end
            pinWho:SetText(who)
            pinBody:SetWidth(math.max(panel:GetWidth() - 28, 200))
            pinBody:SetText(pinned.text)
            setShown(pinUnpin, canAdmin)
            local ph = math.max(34, (pinBody:GetStringHeight() or 12) + 32)
            pinCard:SetHeight(ph)
            pinCard:Show()
            holderTop = PIN_Y + ph + UI.GAP
        else
            pinCard:Hide()
        end
        holder:ClearAllPoints()
        holder:SetPoint("TOPLEFT", 0, -holderTop)
        holder:SetPoint("BOTTOMRIGHT", 0, 24 + UI.GAP)

        -- The feed: each line is kept or dropped by the guild filter and the search box, then grouped
        -- by speaker. A line that opens a new day is preceded by the day's name.
        local query = (search:GetText() or ""):lower()
        local rawLog = chat:Log()
        local hidden = chat:HiddenSet()
        local log = {}
        for _, e in ipairs(rawLog) do
            if (e.sys or not hidden[AC.HiddenKey(e.n, e.m)]) and AC.PassesFilter(e, filterGuild, query) then
                log[#log + 1] = e
            end
        end
        local groups = AC.GroupLog(log, AC.GROUP_WINDOW)
        local rows, lastDay = {}, nil
        for _, g in ipairs(groups) do
            if g.t and g.t > 0 then
                local day = GuildOS:LocalDate("%Y-%m-%d", g.t)
                if day ~= lastDay then
                    rows[#rows + 1] = { divider = GuildOS:LocalDate("%A, %b %d", g.t) }
                    lastDay = day
                end
            end
            rows[#rows + 1] = { group = g }
        end

        local canHide = ally and ally:CanAdminister()
        local myGuild = ally and ally:MyGuildName()
        local me = (GuildOS.Compat.PlayerName() or ""):match("^([^-]+)") or ""
        -- The wrap width of a message; the cards hang by both sides of the list (#371).
        local width = math.max(content:GetWidth(), 200)
        local y = 0

        for i, row in ipairs(rows) do
            local b = getBlock(i)

            if row.divider then
                b.card:SetBackdropColor(0, 0, 0, 0)
                b.card:SetBackdropBorderColor(0, 0, 0, 0)
                b.accent:Hide()
                b.icon:Hide()
                b.presence:Hide()
                b.nameFS:Hide()
                b.timeFS:Hide()
                b.hit:Hide()
                b.hide:Hide()
                b.reply:Hide()
                b.copy:Hide()
                b.pinBtn:Hide()
                b.bodyFS:SetJustifyH("CENTER")
                b.bodyFS:SetPoint("TOPLEFT", 0, -4)
                b.bodyFS:SetWidth(width)
                b.bodyFS:SetText(string.format("|cff%s%s|r", hex(C.label), row.divider))
                local h = 22
                b.card:ClearAllPoints()
                b.card:SetPoint("TOPLEFT", 0, -y)
                b.card:SetPoint("TOPRIGHT", 0, -y)
                b.card:SetHeight(h)
                b.card:Show()
                y = y + h + 2
            else
                local g = row.group
                -- When the line was said: day and time to the minute, then how long ago that was.
                local stamp = ""
                if g.t and g.t > 0 then
                    stamp = GuildOS:LocalDate("%a %H:%M", g.t) .. "  \194\183  " .. GuildOS:TimeAgo(g.t)
                end

                if g.sys then
                    -- Events stand apart: no card, no speaker, a line in `label`, or `warn` for a warning.
                    -- No marker in front of it (#371).
                    local col = hex((g.sys == "warn") and C.warn or C.label)
                    b.card:SetBackdropColor(0, 0, 0, 0)
                    b.card:SetBackdropBorderColor(0, 0, 0, 0)
                    b.accent:Hide()
                    b.icon:Hide()
                    b.presence:Hide()
                    b.nameFS:Hide()
                    b.hit:Hide()
                    b.hide:Hide()
                    b.reply:Hide()
                    b.copy:Hide()
                    b.pinBtn:Hide()
                    b.st.name, b.st.text = nil, nil
                    b.timeFS:Show()
                    b.timeFS:SetText(stamp)
                    b.bodyFS:SetJustifyH("LEFT")
                    b.bodyFS:SetPoint("TOPLEFT", 0, -4)
                    b.bodyFS:SetWidth(width - 60)
                    b.bodyFS:SetText(string.format("|cff%s%s|r", col, g.lines[1] or ""))
                    local h = math.max(18, (b.bodyFS:GetStringHeight() or 12) + 8)
                    b.card:ClearAllPoints()
                    b.card:SetPoint("TOPLEFT", 0, -y)
                    b.card:SetPoint("TOPRIGHT", 0, -y)
                    b.card:SetHeight(h)
                    b.card:Show()
                    y = y + h + 2
                else
                    local text = table.concat(g.lines, "\n")
                    local info = ally and ally:SpeakerInfo(g.name)
                    local cr, cg, cb = GuildOS:GetClassColor(info and info.class)
                    local own = (g.guild == myGuild)
                    local mention = AC.MentionsMe(text, me)

                    b.card:SetBackdropColor(C.bg2.r, C.bg2.g, C.bg2.b, own and 0.35 or 0.55)
                    if mention then
                        -- A line that names you wears the warning tint, so it is found at a glance.
                        b.card:SetBackdropColor(C.warn.r, C.warn.g, C.warn.b, 0.16)
                    end
                    b.card:SetBackdropBorderColor(C.border.r, C.border.g, C.border.b, 0.35)

                    -- The rail is the GUILD's colour, matching the bulletin, so one
                    -- colour means one guild everywhere in this panel. Class still
                    -- reads off the icon and the name, which is where you look for
                    -- it anyway.
                    local gr, gg, gb = GuildOS.Alliance.GuildColor(g.guild)
                    b.accent:SetColorTexture(gr, gg, gb, 0.95)
                    b.accent:Show()

                    local coords = CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[info and info.class]
                    if coords then
                        b.icon:SetTexture(b.classTex)
                        b.icon:SetTexCoord(coords[1], coords[2], coords[3], coords[4])
                        b.icon:Show()
                    else
                        b.icon:Hide()
                    end

                    local online = ally and ally:IsOnlineNow(g.name, g.guild)
                    b.presence:SetColorTexture(
                        online and C.online.r or C.offline.r,
                        online and C.online.g or C.offline.g,
                        online and C.online.b or C.offline.b, 1)
                    b.presence:Show()

                    -- The speaker's rank in their guild follows the name, dimmer than it.
                    local role = ally and ally:RankOf(g.name, g.guild)
                    local roleText = role and string.format("  |cff%s%s|r", hex(C.label), role) or ""
                    b.nameFS:SetText(string.format("%s  |cff%s[%s]|r%s",
                        g.name or "?", hex(own and C.labelDim or C.info), g.guild or "?", roleText))
                    b.nameFS:SetTextColor(cr, cg, cb)
                    b.nameColor = { cr, cg, cb }
                    b.nameFS:Show()

                    b.timeFS:Show()
                    b.timeFS:SetText(stamp)
                    b.bodyFS:SetJustifyH("LEFT")
                    b.bodyFS:SetPoint("TOPLEFT", 42, -22)
                    b.bodyFS:SetWidth(width - 54)
                    b.bodyFS:SetText(AC.Highlight(text, query))

                    local h = math.max(34, (b.bodyFS:GetStringHeight() or 12) + 28)
                    b.card:ClearAllPoints()
                    b.card:SetPoint("TOPLEFT", 0, -y)
                    b.card:SetPoint("TOPRIGHT", 0, -y)
                    b.card:SetHeight(h)
                    b.card:Show()

                    b.hit.name = g.name
                    b.hit.guild = g.guild
                    b.hit:Show()

                    -- Hides the whole block's text, which is what the ambassador
                    -- clicked on: a run of lines from one speaker reads as one
                    -- message and pulling half of it would look like a glitch.
                    b.hide.who = g.name
                    b.hide.text = text
                    setShown(b.hide, canHide)

                    b.st.name, b.st.text = g.name, text
                    b.reply:Show()
                    b.copy:Show()
                    setShown(b.pinBtn, canHide)
                    y = y + h + 3
                end
            end
        end

        -- Park every pooled block the feed no longer needs.
        for i = #rows + 1, #blocks do
            blocks[i].card:Hide()
        end

        if #log == 0 then
            empty:SetText((query ~= "" or filterGuild) and L["No lines match."] or L["Nothing here yet. Say hello."])
            empty:SetPoint("TOPLEFT", 0, 0)
            empty:Show()
            y = 20
        else
            empty:Hide()
        end
        content:SetHeight(math.max(y, 1))

        -- Stick to the newest line only if the feed was already there, or this refresh is ours.
        local stick = forceBottom or wasBottom
        forceBottom = false
        -- Deferred one frame: the scroll range is recomputed after the content
        -- height lands, so scrolling to the bottom in this frame would clamp
        -- against the OLD range and leave the newest line off screen.
        local target = math.max(0, y - holder:GetHeight())
        GuildOS.Compat.After(0, function()
            if not panel:IsVisible() then return end
            if stick then scroll:SetVerticalScroll(target) end
            setShown(jump, not atBottom())
        end)
    end

    if GuildOS.AllianceChat then
        GuildOS.AllianceChat:OnRefresh(function()
            if panel:IsVisible() then refresh() end
        end)
    end

    return refresh
end

----------------------------------------------------------------------
-- Events: the alliance's upcoming events, the Calendar's, soonest first. An ambassador creates one with the
-- Calendar's own editor, shared to the alliance, and only ambassadors approve or cancel them. Anyone in the
-- alliance can ask for a slot in another guild's event.
----------------------------------------------------------------------
local PEND_H, PEND_MAX = 22, 6
local EVENT_ROLE_NEXT = { TANK = "HEALER", HEALER = "DPS", DPS = "TANK" }

local function eventRoleName(role)
    return ({ TANK = L["Tank"], HEALER = L["Healer"], DPS = L["DPS"] })[role] or L["DPS"]
end

local function BuildEvents(panel)
    local count = UI:CreateText(panel, "", 11, C.label.r, C.label.g, C.label.b)
    count:SetPoint("TOPRIGHT", 0, -3)
    local title = UI:CreateSectionTitle(panel, "", true)
    title:SetPoint("TOPLEFT", 0, 0)
    title:SetPoint("RIGHT", count, "LEFT", -UI.GAP, 0)
    title:SetWordWrap(false)

    local FORM_Y = 18 + UI.GAP
    local createBtn = UI:CreateButton(panel, L["Create event"], 130, 26)
    createBtn:SetPoint("TOPRIGHT", 0, -FORM_Y)
    createBtn:SetScript("OnClick", function() GuildOS.OpenAllianceEventEditor() end)

    local hint = UI:CreateText(panel, "", 10, C.textDim.r, C.textDim.g, C.textDim.b)
    hint:SetPoint("TOPLEFT", 0, -(FORM_Y + 6))

    -- What happened to the last action. Errors used to go to the chat frame only, where a refused action
    -- looked like nothing had happened.
    local status = UI:CreateText(panel, "", 10, C.textDim.r, C.textDim.g, C.textDim.b)
    status:SetPoint("TOPRIGHT", 0, -(FORM_Y + 26 + UI.GAP))
    status:SetJustifyH("RIGHT")
    local function feedback(ok, msg)
        if not msg or msg == "" then return end
        status:SetText(msg)
        local col = ok and C.online or C.red
        status:SetTextColor(col.r, col.g, col.b)
    end

    local holder = CreateFrame("Frame", nil, panel)
    holder:SetPoint("TOPLEFT", 0, -(FORM_Y + 26 + UI.GAP + 16 + UI.GAP))
    holder:SetPoint("BOTTOMRIGHT", 0, 0)
    local scroll, content = UI:CreateScrollFrame(holder, "GuildOSAllianceEventsScroll")
    fillScroll(scroll, content)

    local empty = UI:CreateText(content, L["No upcoming events."], 12, C.textSoft.r, C.textSoft.g, C.textSoft.b)
    empty:SetPoint("TOPLEFT", 0, 0)
    empty:Hide()

    -- The role each event's request button asks for, kept across refreshes.
    local roles = {}

    local refresh

    -- Cards are pooled, and so are the rows of pending requests inside them: WoW never frees a frame.
    local cards = {}
    local function pendRow(card, j)
        if card.pend[j] then return card.pend[j] end
        local row = {}
        row.frame = CreateFrame("Frame", nil, card.card)
        row.frame:SetHeight(PEND_H)
        row.name = UI:CreateText(row.frame, "", 11, C.text.r, C.text.g, C.text.b)
        row.name:SetPoint("LEFT", 14, 0)
        row.role = UI:CreateText(row.frame, "", 10, C.label.r, C.label.g, C.label.b)
        row.role:SetPoint("LEFT", 170, 0)
        row.no = UI:CreateButton(row.frame, L["Decline"], 84, 18)
        row.no:SetPoint("RIGHT", row.frame, "RIGHT", -6, 0)
        row.yes = UI:CreateButton(row.frame, L["Approve"], 84, 18)
        row.yes:SetPoint("RIGHT", row.no, "LEFT", -6, 0)
        row.yes:SetScript("OnClick", function(self)
            local ok, err = GuildOS.Calendar:ApproveAlliance(self.eventId, self.key)
            feedback(ok, ok and L["Request approved."] or err)
            refresh()
        end)
        row.no:SetScript("OnClick", function(self)
            local ok, err = GuildOS.Calendar:DeclineAlliance(self.eventId, self.key, "declined")
            feedback(ok, ok and L["Request declined."] or err)
            refresh()
        end)
        card.pend[j] = row
        return row
    end

    local function getCard(i)
        if cards[i] then return cards[i] end
        local card = CreateFrame("Frame", nil, content, "BackdropTemplate")
        card:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8x8",
            edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = GuildOS.UI:Edge(card),
        })
        card:SetBackdropBorderColor(C.border.r, C.border.g, C.border.b, 0.3)

        local rail = card:CreateTexture(nil, "ARTWORK")
        rail:SetPoint("TOPLEFT", 0, 0)
        rail:SetPoint("BOTTOMLEFT", 0, 0)
        rail:SetWidth(3)

        local who = UI:CreateText(card, "", 10, C.textDim.r, C.textDim.g, C.textDim.b)
        who:SetPoint("TOPLEFT", 14, -8)
        who:SetJustifyH("LEFT")

        local when = UI:CreateText(card, "", 9, C.textDim.r, C.textDim.g, C.textDim.b)
        when:SetPoint("TOPRIGHT", -10, -9)

        local ttl = UI:CreateText(card, "", 13, C.text.r, C.text.g, C.text.b)
        ttl:SetPoint("TOPLEFT", 14, -24)
        ttl:SetJustifyH("LEFT")
        ttl:SetWordWrap(false)

        local spots = UI:CreateText(card, "", 11, C.text.r, C.text.g, C.text.b)
        spots:SetPoint("TOPRIGHT", -10, -24)

        local note = UI:CreateText(card, "", 10, C.textSoft.r, C.textSoft.g, C.textSoft.b)
        note:SetPoint("TOPLEFT", 14, -44)
        note:SetJustifyH("LEFT")
        note:SetWordWrap(true)

        local role = UI:CreateButton(card, "", 70, 22)
        role:SetScript("OnClick", function(self)
            local nextRole = EVENT_ROLE_NEXT[roles[self.eventId] or "DPS"] or "DPS"
            roles[self.eventId] = nextRole
            self.label:SetText(eventRoleName(nextRole))
        end)

        local ask = UI:CreateButton(card, L["Request slot"], 110, 22)
        ask:SetScript("OnClick", function(self)
            local ok, err = GuildOS.Calendar:RequestAllianceSlot(self.eventId, self.guild, roles[self.eventId] or "DPS", "")
            feedback(ok, ok and string.format(L["Slot requested from %s."], self.guild) or err)
            refresh()
        end)

        local state = UI:CreateText(card, "", 10, C.textDim.r, C.textDim.g, C.textDim.b)

        local cancel = UI:CreateButton(card, L["Cancel event"], 100, 22)
        cancel:SetScript("OnClick", function(self)
            GuildOS.Calendar:Cancel(self.eventId)
            feedback(true, L["Event cancelled."])
            refresh()
        end)

        cards[i] = {
            card = card, rail = rail, who = who, when = when, ttl = ttl, spots = spots,
            note = note, role = role, ask = ask, state = state, cancel = cancel, pend = {},
        }
        return cards[i]
    end

    refresh = function()
        local ally = GuildOS.Alliance
        local cal = GuildOS.Calendar
        local canAnswer = (cal and cal:IsAllianceAmbassador()) and true or false
        local summary = ally and ally:Summary()

        local events = {}
        for _, ev in ipairs((cal and cal:AllianceEvents()) or {}) do events[#events + 1] = ev end
        for _, ev in ipairs((cal and cal:OwnAllianceEvents()) or {}) do events[#events + 1] = ev end
        table.sort(events, function(a, b) return (a.when or 0) < (b.when or 0) end)

        title:SetText((summary and summary.name) or "")
        count:SetText(string.format(L["%d upcoming"], #events))
        setShown(createBtn, canAnswer)
        hint:SetText(canAnswer and L["Ambassadors create events. Every guild in the alliance sees them."]
            or L["Only alliance ambassadors can create events. Request a slot on any event below."])

        local width = math.max(content:GetWidth(), 200)
        local y = 0
        for i, ev in ipairs(events) do
            local c = getCard(i)
            local r, g, b = ally.GuildColor(ev.guild)
            local own = ev.own and true or false
            local full = (ev.yes or 0) >= (ev.size or 0)
            local pending = ev.pending or {}
            local hosting = own and canAnswer

            c.card:SetBackdropColor(C.bg2.r, C.bg2.g, C.bg2.b, 0.5)
            c.rail:SetColorTexture(r, g, b, 0.95)

            local kindText = (cal and cal:KindLabel(ev.kind)) or ev.kind
            local eyebrow = string.format("|cff%s%s|r  \194\183  |cff%s%s|r",
                ally.GuildColorHex(ev.guild), (ev.guild or "?"):upper(), hex(C.label), kindText)
            if hosting and #pending > 0 then
                eyebrow = eyebrow .. string.format("  \194\183  |cff%s%s|r", hex(C.gold), string.format(L["Requests (%d)"], #pending))
            end
            c.who:SetText(eyebrow)
            c.when:SetText(GuildOS:LocalDate("%a %b %d %H:%M", ev.when))
            c.ttl:SetText(ev.title or "")
            c.spots:SetText(string.format(L["%d/%d spots"], ev.yes or 0, ev.size or 0))

            local y0 = 44
            if ev.note and ev.note ~= "" then
                c.note:Show()
                c.note:SetWidth(width - 40)
                c.note:SetText(ev.note)
                y0 = y0 + (c.note:GetStringHeight() or 12) + 6
            else
                c.note:Hide()
            end

            -- The action row: a request for another guild's event, a status, and for the host's ambassador a cancel.
            local showAsk = not own and not full
            c.role.eventId = ev.id
            c.role.label:SetText(eventRoleName(roles[ev.id] or "DPS"))
            c.role:ClearAllPoints()
            c.role:SetPoint("TOPLEFT", c.card, "TOPLEFT", 14, -y0)
            c.ask.eventId, c.ask.guild = ev.id, ev.guild
            c.ask:ClearAllPoints()
            c.ask:SetPoint("LEFT", c.role, "RIGHT", 6, 0)
            setShown(c.role, showAsk)
            setShown(c.ask, showAsk)

            local stateText = ""
            if own then
                stateText = L["Yours"]
            elseif full then
                stateText = L["Full"]
            end
            c.state:SetText(stateText)
            c.state:ClearAllPoints()
            c.state:SetPoint("TOPLEFT", c.card, "TOPLEFT", 14, -(y0 + 5))
            setShown(c.state, not showAsk and stateText ~= "")

            c.cancel.eventId = ev.id
            c.cancel:ClearAllPoints()
            c.cancel:SetPoint("TOPRIGHT", c.card, "TOPRIGHT", -10, -y0)
            setShown(c.cancel, hosting)

            -- The host's ambassador sees the requests waiting, one row each, with Approve and Decline.
            local py = y0 + 26
            local shownPend = 0
            if hosting then
                for j, s in ipairs(pending) do
                    if j > PEND_MAX then break end
                    local row = pendRow(c, j)
                    row.frame:ClearAllPoints()
                    row.frame:SetPoint("TOPLEFT", c.card, "TOPLEFT", 0, -py)
                    row.frame:SetPoint("TOPRIGHT", c.card, "TOPRIGHT", 0, -py)
                    row.frame:Show()
                    row.name:SetText(s.name or "?")
                    row.role:SetText(eventRoleName(s.role))
                    row.yes.eventId, row.yes.key = ev.id, s.key
                    row.no.eventId, row.no.key = ev.id, s.key
                    py = py + PEND_H
                    shownPend = j
                end
            end
            for j = shownPend + 1, #c.pend do c.pend[j].frame:Hide() end

            local h = py + 8
            c.card:ClearAllPoints()
            c.card:SetPoint("TOPLEFT", 0, -y)
            c.card:SetPoint("TOPRIGHT", 0, -y)
            c.card:SetHeight(h)
            c.card:Show()
            y = y + h + UI.GAP
        end

        for i = #events + 1, #cards do cards[i].card:Hide() end

        if #events == 0 then
            empty:Show()
            y = 24
        else
            empty:Hide()
        end
        content:SetHeight(math.max(y, 1))
    end

    return refresh
end

----------------------------------------------------------------------
-- Bulletin: notices posted by any ambassador in the alliance.
----------------------------------------------------------------------
local function BuildBulletin(panel)
    ------------------------------------------------------------------
    -- Identity band. This board is the face of the alliance, so it opens
    -- with who the alliance IS: its name, as the screen's first section
    -- title, and its size. The name is held across the line up to the
    -- size, so a long one is never cut short by a width of its own, and it
    -- is the shared title in `text`, not gold caps (#371). The colour chips
    -- that stood under it went: unlabelled, they named nobody; each
    -- notice still carries its guild's colour.
    ------------------------------------------------------------------
    local count = UI:CreateText(panel, "", 11, C.label.r, C.label.g, C.label.b)
    count:SetPoint("TOPRIGHT", 0, -3)
    local title = UI:CreateSectionTitle(panel, "", true)
    title:SetPoint("TOPLEFT", 0, 0)
    title:SetPoint("RIGHT", count, "LEFT", -UI.GAP, 0)
    title:SetWordWrap(false)

    local box = makeInput(panel, 100, { placeholder = L["Write a notice for the alliance"] })
    box:SetPoint("TOPLEFT", 0, -(18 + UI.GAP))
    box:SetPoint("RIGHT", panel, "RIGHT", -(88 + UI.GAP), 0)
    box:SetHeight(26)

    local postBtn = UI:CreateButton(panel, L["Post"], 88, 26)
    postBtn:SetPoint("TOPRIGHT", 0, -(18 + UI.GAP))

    local hint = UI:CreateText(panel, "", 10, C.textDim.r, C.textDim.g, C.textDim.b)
    hint:SetPoint("TOPLEFT", 0, -(18 + UI.GAP + 26 + 4))

    local holder = CreateFrame("Frame", nil, panel)
    holder:SetPoint("TOPLEFT", 0, -(18 + UI.GAP + 26 + 4 + 14 + UI.GAP))
    holder:SetPoint("BOTTOMRIGHT", 0, 0)
    local scroll, content = UI:CreateScrollFrame(holder, "GuildOSAllianceBoardScroll")
    fillScroll(scroll, content)

    local empty = UI:CreateText(content, "", 12, C.textSoft.r, C.textSoft.g, C.textSoft.b)
    empty:Hide()

    local refresh

    -- Notice cards, pooled: WoW never frees a frame.
    local cards = {}
    local function getCard(i)
        if cards[i] then return cards[i] end
        local card = CreateFrame("Frame", nil, content, "BackdropTemplate")
        card:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8x8",
            edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = GuildOS.UI:Edge(card),
        })
        card:SetBackdropBorderColor(C.border.r, C.border.g, C.border.b, 0.3)

        local rail = card:CreateTexture(nil, "ARTWORK")
        rail:SetPoint("TOPLEFT", 0, 0)
        rail:SetPoint("BOTTOMLEFT", 0, 0)
        rail:SetWidth(3)

        -- Eyebrow: who said it, institutionally. Small and uppercase in the
        -- guild colour, so it reads as a stamp rather than as body text.
        local who = UI:CreateText(card, "", 10, C.textDim.r, C.textDim.g, C.textDim.b)
        who:SetPoint("TOPLEFT", 14, -8)
        who:SetJustifyH("LEFT")

        local when = UI:CreateText(card, "", 9, C.textDim.r, C.textDim.g, C.textDim.b)
        when:SetPoint("TOPRIGHT", -26, -9)

        -- The notice is the biggest thing on the card. It is the only part
        -- anyone opened this tab to read.
        local body = UI:CreateText(card, "", 13, C.text.r, C.text.g, C.text.b)
        body:SetPoint("TOPLEFT", 14, -24)
        body:SetJustifyH("LEFT")
        body:SetWordWrap(true)

        local del = CreateFrame("Button", nil, card)
        del:SetSize(18, 18)
        del:SetPoint("TOPRIGHT", -5, -5)
        del.fs = del:CreateFontString(nil, "OVERLAY")
        GuildOS:ApplyFont(del.fs, 13)
        del.fs:SetPoint("CENTER")
        del.fs:SetText("\195\151")
        del.fs:SetTextColor(C.textDim.r, C.textDim.g, C.textDim.b)
        del:SetScript("OnEnter", function() del.fs:SetTextColor(C.red.r, C.red.g, C.red.b) end)
        del:SetScript("OnLeave", function() del.fs:SetTextColor(C.textDim.r, C.textDim.g, C.textDim.b) end)
        del:SetScript("OnClick", function(self)
            local ok, err = ALLY():RemoveBoardPost(self.postId)
            if not ok and err then GuildOS:Print(err) end
            refresh()
        end)

        cards[i] = { card = card, rail = rail, who = who, when = when, body = body, del = del }
        return cards[i]
    end

    postBtn:SetScript("OnClick", function()
        local ok, err = ALLY():PostBoard(box:GetText())
        if ok then
            box:SetText("")
        elseif err then
            GuildOS:Print(err)
        end
        refresh()
    end)
    box:SetScript("OnEnterPressed", function() postBtn:Click() end)

    refresh = function()
        local ally = ALLY()
        local Ally = GuildOS.Alliance

        local summary = ally and ally:Summary()
        title:SetText((summary and summary.name) or "")
        count:SetText(summary
            and guildCountText(#summary.guilds, summary.members) or "")

        local canPost = ally and ally:CanAdminister()
        setShown(box, canPost)
        setShown(postBtn, canPost)
        hint:SetText(canPost and L["Ambassadors can post. Everyone in the alliance sees it."]
            or L["Only alliance ambassadors can post here."])

        local posts = (ally and ally.BoardPosts and ally:BoardPosts()) or {}
        local mine = ally and ally:MyGuildName()
        -- The wrap width of a notice; the cards hang by both sides of the list (#371).
        local width = math.max(content:GetWidth(), 200)
        local y = 0

        for i, p in ipairs(posts) do
            local c = getCard(i)
            local r, g, b = Ally.GuildColor(p.guild)

            c.card:SetBackdropColor(C.bg2.r, C.bg2.g, C.bg2.b, 0.5)
            c.rail:SetColorTexture(r, g, b, 0.95)

            -- Who wrote it and in what role: the guild, then the poster, then their rank.
            local eyebrow = string.format("|cff%s%s|r  \194\183  |cff%s%s|r",
                Ally.GuildColorHex(p.guild), (p.guild or "?"):upper(), hex(C.text), p.by or "?")
            if p.role and p.role ~= "" then
                eyebrow = eyebrow .. string.format("  \194\183  |cff%s%s|r", hex(C.label), p.role)
            end
            c.who:SetText(eyebrow)
            -- When it was written, to the minute, and how long ago that was.
            if p.ts and p.ts > 0 then
                c.when:SetText(GuildOS:LocalDate("%a %H:%M", p.ts) .. "  \194\183  " .. GuildOS:TimeAgo(p.ts))
            else
                c.when:SetText("")
            end

            c.body:SetWidth(width - 40)
            c.body:SetText(p.text or "")

            -- Only your own guild's notices can be pulled, and only by an
            -- ambassador: the same independence rule as the rest of the pact.
            c.del.postId = p.id
            setShown(c.del, canPost and p.guild == mine)

            local h = math.max(46, (c.body:GetStringHeight() or 12) + 34)
            c.card:ClearAllPoints()
            c.card:SetPoint("TOPLEFT", 0, -y)
            c.card:SetPoint("TOPRIGHT", 0, -y)
            c.card:SetHeight(h)
            c.card:Show()
            y = y + h + UI.GAP
        end

        for i = #posts + 1, #cards do cards[i].card:Hide() end

        if #posts == 0 then
            -- An empty board is an invitation, not a status report.
            empty:SetText(canPost and L["Nothing here yet. Welcome the allied guilds."]
                or L["Nothing here yet."])
            empty:SetPoint("TOPLEFT", 0, 0)
            empty:Show()
            y = 24
        else
            empty:Hide()
        end
        content:SetHeight(math.max(y, 1))
    end

    return refresh
end

----------------------------------------------------------------------
-- Manage: found, invite, block, remove, leave, and the channel toggle.
----------------------------------------------------------------------
local function BuildManage(panel)
    local notOfficer = UI:CreateText(panel, L["Only officers can manage the alliance."],
        12, C.textSoft.r, C.textSoft.g, C.textSoft.b)
    notOfficer:SetPoint("TOPLEFT", 0, 0)

    -- A scrolling body: with the section titles' spacing (#371) an ambassador's view runs past a
    -- 620px window, and the window clips what does not fit. The layouts below set its height.
    local bodyScroll, body = UI:CreateScrollFrame(panel, nil)
    bodyScroll:SetPoint("TOPLEFT", 0, 0)
    bodyScroll:SetPoint("BOTTOMRIGHT", 0, 0)
    UI:BindScrollChildWidth(bodyScroll, body)

    -- Each block opens with the shared section title (#371): the first of a view has no rule, every
    -- later one a 1px rule above it, which is a region of `body`, shown and hidden with its title.
    local function sectionTitle(text, first)
        return UI:CreateSectionTitle(body, text, first)
    end

    ------------------------------------------------------------------
    -- No pact yet. JOINING comes first and is one field: almost every guild
    -- joins, exactly one founds.
    ------------------------------------------------------------------
    local joinHdr = sectionTitle(L["Join an alliance"], true)
    local joinBox = makeInput(body, 100)
    local joinBtn = UI:CreateButton(body, L["Join"], 90, 24)
    local joinHint = UI:CreateText(body, L["Paste the invite an ambassador gave you."],
        10, C.textDim.r, C.textDim.g, C.textDim.b)

    -- Fallback, shown ONLY after a join failed to find anybody. The mesh
    -- normally supplies the contact, so asking up front would be friction
    -- charged to everyone to cover a minority case. A warning, so `warn`.
    local joinWarn = UI:CreateText(body, "", 10, C.warn.r, C.warn.g, C.warn.b)
    addFlexHint(joinWarn)
    joinWarn:SetJustifyH("LEFT")
    joinWarn:SetWordWrap(true)
    local contactBox = makeInput(body, 200)
    local contactBtn = UI:CreateButton(body, L["Try with this name"], 140, 24)
    contactBtn:SetPoint("LEFT", contactBox, "RIGHT", 8, 0)

    -- /outlawos ally request: no invite in hand, ask an officer of a guild already in the alliance (#142).
    local reqHdr = sectionTitle(L["Ask to join an alliance"])
    local reqTagBox = makeInput(body, 110)
    local reqWhoBox = makeInput(body, 200)
    reqWhoBox:SetPoint("LEFT", reqTagBox, "RIGHT", 8, 0)
    local reqBtn = UI:CreateButton(body, L["Send request"], 120, 24)
    reqBtn:SetPoint("LEFT", reqWhoBox, "RIGHT", 8, 0)
    local reqHint = UI:CreateText(body, L["Alliance tag and an officer of a guild already in it. They approve the request."],
        10, C.textDim.r, C.textDim.g, C.textDim.b)

    -- The rule over this title is the line that used to stand alone between joining and founding.
    local foundHdr = sectionTitle(L["Found an alliance"])
    local tagBox = makeInput(body, 110)
    local nameBox = makeInput(body, 240)
    nameBox:SetPoint("LEFT", tagBox, "RIGHT", 8, 0)
    local foundBtn = UI:CreateButton(body, L["Create"], 90, 24)
    foundBtn:SetPoint("LEFT", nameBox, "RIGHT", 8, 0)
    local foundHint = UI:CreateText(body, L["Tag (letters and numbers) and a display name."],
        10, C.textDim.r, C.textDim.g, C.textDim.b)

    -- Invite / block, shown once a pact exists.
    local inviteHdr = sectionTitle(L["Invite a guild"], true)
    inviteHdr:SetPoint("TOPLEFT", 0, 0)
    local inviteBox = makeInput(body, 200)
    inviteBox:SetPoint("TOPLEFT", 0, -TITLE_H)
    local inviteBtn = UI:CreateButton(body, L["Invite"], 90, 24)
    inviteBtn:SetPoint("LEFT", inviteBox, "RIGHT", UI.GAP, 0)
    local inviteHint = UI:CreateText(body,
        L["Name any officer of that guild. They get a prompt and must accept."],
        10, C.textDim.r, C.textDim.g, C.textDim.b)
    inviteHint:SetPoint("TOPLEFT", 0, -(TITLE_H + 24 + 6))

    ------------------------------------------------------------------
    -- Ambassadors. Rows are POOLED (created once, shown/hidden), because
    -- WoW never frees a frame: rebuilding them per refresh would leak.
    ------------------------------------------------------------------
    local ambHdr = sectionTitle(L["Ambassadors of this guild"])
    local ambRows = {}
    for i = 1, 8 do
        local row = CreateFrame("Frame", nil, body)
        row:SetSize(360, 20)
        row.name = UI:CreateText(row, "", 11, C.text.r, C.text.g, C.text.b)
        row.name:SetPoint("LEFT", 0, 0)
        row.name:SetWidth(250)
        row.name:SetJustifyH("LEFT")
        row.del = UI:CreateButton(row, L["Remove"], 80, 18)
        row.del:SetPoint("LEFT", 264, 0)
        row:Hide()
        ambRows[i] = row
    end
    local ambBox = makeInput(body, 200)
    local ambAddBtn = UI:CreateButton(body, L["Add"], 90, 24)
    ambAddBtn:SetPoint("LEFT", ambBox, "RIGHT", 8, 0)
    local ambHint = UI:CreateText(body,
        L["Ambassadors speak for the guild: they invite, approve slots and post."],
        10, C.textDim.r, C.textDim.g, C.textDim.b)
    -- Vacancy state: shown instead of the list when the guild lost them all.
    local ambWarn = UI:CreateText(body, "", 11, C.red.r, C.red.g, C.red.b)
    addFlexHint(ambWarn)
    ambWarn:SetJustifyH("LEFT")
    ambWarn:SetWordWrap(true)
    local ambClaimBtn = UI:CreateButton(body, L["Claim ambassador"], 170, 24)

    -- Join code. Shown ONLY to ambassadors: it is stored on every member's
    -- client (they all have to validate it) so this is a deterrent against
    -- casual sharing rather than real secrecy, and the hint says as much.
    local codeHdr = sectionTitle(L["Join code"])
    local codeBox = makeInput(body, 140)
    codeBox:SetAutoFocus(false)
    codeBox:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    local codeNewBtn = UI:CreateButton(body, L["New code"], 100, 24)
    codeNewBtn:SetPoint("LEFT", codeBox, "RIGHT", 8, 0)
    local codeHint = UI:CreateText(body,
        L["A guild with this code joins without anyone having to approve. Anyone in the alliance can be the contact."],
        10, C.textDim.r, C.textDim.g, C.textDim.b)
    addFlexHint(codeHint)
    codeHint:SetJustifyH("LEFT")
    codeHint:SetWordWrap(true)

    local blockHdr = sectionTitle(L["Ignore a guild locally"])
    local blockBox = makeInput(body, 200)
    local blockBtn = UI:CreateButton(body, L["Block"], 90, 24)
    blockBtn:SetPoint("LEFT", blockBox, "RIGHT", 8, 0)
    local unblockBtn = UI:CreateButton(body, L["Unblock"], 90, 24)
    unblockBtn:SetPoint("LEFT", blockBtn, "RIGHT", 6, 0)
    local blockHint = UI:CreateText(body,
        L["Only affects you. The pact is untouched and nobody is told."],
        10, C.textDim.r, C.textDim.g, C.textDim.b)

    local removeHdr = sectionTitle(L["Remove a guild from the pact"])
    local removeBox = makeInput(body, 200)
    local removeBtn = UI:CreateButton(body, L["Remove"], 90, 24)
    removeBtn:SetPoint("LEFT", removeBox, "RIGHT", 8, 0)
    local removeHint = UI:CreateText(body, L["Only the founding guild can do this."],
        10, C.textDim.r, C.textDim.g, C.textDim.b)

    -- The channel and leaving have no title of their own: a rule closes the block above them.
    local chatRule = UI:CreateSeparator(body)
    local chatBtn = UI:CreateButton(body, L["Alliance chat"], 150, 24)
    local chatHint = UI:CreateText(body,
        L["A custom channel is public: anyone who guesses the name can join. Keep secrets out of it."],
        10, C.textDim.r, C.textDim.g, C.textDim.b)
    addFlexHint(chatHint)
    chatHint:SetJustifyH("LEFT")
    chatHint:SetWordWrap(true)

    -- Channel ownership goes to whoever joined first, which is usually not an
    -- ambassador, so the people who need to moderate cannot. This hands it over
    -- in one action. Only the owner can, so it hides for everyone else.
    local modBtn = UI:CreateButton(body, L["Give ambassadors channel moderation"], 250, 24)
    modBtn:SetScript("OnClick", function()
        local n = GuildOS.AllianceChat and GuildOS.AllianceChat:PromoteAmbassadors() or 0
        if n > 0 then
            GuildOS:Print(string.format(L["Asked the server to promote %d ambassador(s)."], n))
        else
            GuildOS:Print(L["Only the channel owner can do that."])
        end
    end)

    local leaveBtn = UI:CreateButton(body, L["Leave the alliance"], 170, 24)

    -- A later section title's rule is its own region: it goes in the group with its title.
    local foundGroup  = { joinHdr, joinBox, joinBtn, joinHint,
                          foundHdr, foundHdr.rule, tagBox, nameBox, foundBtn, foundHint,
                          reqHdr, reqHdr.rule, reqTagBox, reqWhoBox, reqBtn, reqHint }
    -- Set by a join that could not find anybody on the mesh.
    local needContact = false
    local memberGroup = { inviteHdr, inviteBox, inviteBtn, inviteHint, ambHdr, ambHdr.rule,
                          blockHdr, blockHdr.rule, blockBox, blockBtn, unblockBtn, blockHint,
                          removeHdr, removeHdr.rule, removeBox, removeBtn, removeHint,
                          chatRule, chatBtn, chatHint, modBtn, leaveBtn,
                          codeHdr, codeHdr.rule, codeBox, codeNewBtn, codeHint }

    local function say(ok, err)
        if not ok and err then GuildOS:Print(err) end
    end

    local refresh   -- forward declaration so handlers can re-render

    -- The no-pact side also runs on an offset, because the contact fallback
    -- appears and disappears between renders.
    -- Flush with the screen's left edge, a title's field TITLE_H under it, and SECTION_ABOVE over every
    -- later title for its rule (#371). HINT_H: a one-line hint and the gap under it.
    local HINT_H = 14
    local function layoutJoin()
        local y = 0
        joinHdr:SetPoint("TOPLEFT", 0, -y);   y = y + TITLE_H
        joinBox:SetPoint("TOPLEFT", 0, -y)
        joinBox:SetPoint("RIGHT", body, "RIGHT", -(90 + UI.GAP), 0)
        joinBtn:SetPoint("TOPRIGHT", 0, -y);  y = y + 30
        joinHint:SetPoint("TOPLEFT", 0, -y);  y = y + HINT_H
        if needContact then
            y = y + UI.GAP
            joinWarn:SetPoint("TOPLEFT", 0, -y);   y = y + 30
            contactBox:SetPoint("TOPLEFT", 0, -y); y = y + 24
        end
        y = y + SECTION_ABOVE
        reqHdr:SetPoint("TOPLEFT", 0, -y);     y = y + TITLE_H
        reqTagBox:SetPoint("TOPLEFT", 0, -y);  y = y + 30
        reqHint:SetPoint("TOPLEFT", 0, -y);    y = y + HINT_H + SECTION_ABOVE
        foundHdr:SetPoint("TOPLEFT", 0, -y);   y = y + TITLE_H
        tagBox:SetPoint("TOPLEFT", 0, -y);     y = y + 30
        foundHint:SetPoint("TOPLEFT", 0, -y);  y = y + HINT_H
        body:SetHeight(y + UI.GAP)
    end

    -- Everything under the invite block is laid out with a running offset,
    -- because the ambassador list grows and shrinks. Fixed offsets would either
    -- overlap or leave a hole.
    local function layout(ambCount, vacancy, showCode)
        local y = TITLE_H + 30 + HINT_H + SECTION_ABOVE
        ambHdr:SetPoint("TOPLEFT", 0, -y)
        y = y + TITLE_H
        for i, row in ipairs(ambRows) do
            if i <= ambCount then
                row:SetPoint("TOPLEFT", 0, -y)
                y = y + 20
            end
        end
        if vacancy then
            ambWarn:SetPoint("TOPLEFT", 0, -y)
            y = y + 32
            ambClaimBtn:SetPoint("TOPLEFT", 0, -y)
            y = y + 24
        else
            ambBox:SetPoint("TOPLEFT", 0, -(y + 4))
            y = y + 34
            ambHint:SetPoint("TOPLEFT", 0, -y)
            y = y + HINT_H
        end

        -- The join code is for ambassadors only: hidden, it leaves no hole.
        if showCode then
            y = y + SECTION_ABOVE
            codeHdr:SetPoint("TOPLEFT", 0, -y);     y = y + TITLE_H
            codeBox:SetPoint("TOPLEFT", 0, -y);     y = y + 28
            codeHint:SetPoint("TOPLEFT", 0, -y);    y = y + 26
        end
        y = y + SECTION_ABOVE
        blockHdr:SetPoint("TOPLEFT", 0, -y);    y = y + TITLE_H
        blockBox:SetPoint("TOPLEFT", 0, -y);    y = y + 28
        blockHint:SetPoint("TOPLEFT", 0, -y);   y = y + HINT_H + SECTION_ABOVE
        removeHdr:SetPoint("TOPLEFT", 0, -y);   y = y + TITLE_H
        removeBox:SetPoint("TOPLEFT", 0, -y);   y = y + 28
        removeHint:SetPoint("TOPLEFT", 0, -y);  y = y + HINT_H + SECTION_ABOVE
        chatRule:SetPoint("TOPLEFT", 0, -(y - 12))
        chatRule:SetPoint("TOPRIGHT", 0, -(y - 12))
        chatBtn:SetPoint("TOPLEFT", 0, -y);     y = y + 28
        chatHint:SetPoint("TOPLEFT", 0, -y);    y = y + 30
        modBtn:SetPoint("TOPLEFT", 0, -y);      y = y + 30
        leaveBtn:SetPoint("TOPLEFT", 0, -y);    y = y + 24
        body:SetHeight(y + UI.GAP)
    end

    ambAddBtn:SetScript("OnClick", function()
        local who = ambBox:GetText()
        local ok, err = ALLY():AddAmbassador(who)
        say(ok, err)
        if ok then
            GuildOS:Print(string.format(L["%s is now an ambassador."], who))
            ambBox:SetText("")
        end
        refresh()
    end)

    codeNewBtn:SetScript("OnClick", function()
        local ok, res = ALLY():RegenerateCode()
        if ok then
            GuildOS:Print(string.format(L["New join code: %s"], res))
        elseif res then
            GuildOS:Print(res)
        end
        refresh()
    end)

    ambClaimBtn:SetScript("OnClick", function()
        local ok, err = ALLY():ClaimAmbassador()
        say(ok, err)
        if ok then GuildOS:Print(L["You are now an ambassador of this guild."]) end
        refresh()
    end)

    local function tryJoin(contact)
        local ok, err, marker = ALLY():JoinWithToken(joinBox:GetText(), contact)
        if ok then
            GuildOS:Print(L["Join sent. If somebody from that alliance is online you are in."])
            joinBox:SetText("")
            contactBox:SetText("")
            needContact = false
        else
            needContact = (marker == "needContact")
            if needContact then
                joinWarn:SetText(L["Nobody from that alliance is visible right now. Name anyone in it and try again."])
            end
            if err then GuildOS:Print(err) end
        end
        refresh()
    end

    joinBtn:SetScript("OnClick", function() tryJoin(nil) end)
    joinBox:SetScript("OnEnterPressed", function() joinBtn:Click() end)
    contactBtn:SetScript("OnClick", function() tryJoin(contactBox:GetText()) end)
    reqBtn:SetScript("OnClick", function()
        local who = strtrim(reqWhoBox:GetText() or "")
        local ok, err = ALLY():RequestJoin(reqTagBox:GetText(), who)
        say(ok, err)
        if ok then GuildOS:Print(string.format(L["Join request sent to %s."], who)) end
    end)
    contactBox:SetScript("OnEnterPressed", function() contactBtn:Click() end)

    foundBtn:SetScript("OnClick", function()
        local ok, err = ALLY():Create(tagBox:GetText(), nameBox:GetText())
        say(ok, err)
        if ok then
            tagBox:SetText("")
            nameBox:SetText("")
            if GuildOS.AllianceChat then GuildOS.AllianceChat:Join() end
        end
        refresh()
    end)

    inviteBtn:SetScript("OnClick", function()
        local target = inviteBox:GetText()
        local ok, err = ALLY():Invite(target)
        say(ok, err)
        if ok then
            GuildOS:Print(string.format(L["Invite sent to %s."], target))
            inviteBox:SetText("")
        end
        refresh()
    end)

    blockBtn:SetScript("OnClick", function()
        say(ALLY():Block(blockBox:GetText()))
        blockBox:SetText("")
        refresh()
    end)

    unblockBtn:SetScript("OnClick", function()
        say(ALLY():Unblock(blockBox:GetText()))
        blockBox:SetText("")
        refresh()
    end)

    removeBtn:SetScript("OnClick", function()
        local guild = removeBox:GetText()
        GuildOS:ShowDialog("GUILDOS_ALLY_REMOVE",
            string.format(L["Remove %s from the alliance?"], guild), nil,
            { guild = guild, after = function() removeBox:SetText(""); refresh() end })
    end)

    chatBtn:SetScript("OnClick", function()
        local chat = GuildOS.AllianceChat
        if not chat then return end
        chat:SetEnabled(not chat:Prefs().chat)
        refresh()
    end)

    leaveBtn:SetScript("OnClick", function()
        GuildOS:ShowDialog("GUILDOS_ALLY_LEAVE",
            L["Leave the alliance? Your guild stops sharing and stops receiving."], nil,
            { after = function() refresh() end })
    end)

    refresh = function()
        local ally = ALLY()
        local isOfficer = GuildOS:IsOfficer()
        setShown(notOfficer, not isOfficer)
        setShown(body, isOfficer)
        if not isOfficer then return end

        local hasPact = ally and ally:Get() ~= nil
        for _, w in ipairs(foundGroup) do setShown(w, not hasPact) end
        for _, w in ipairs(memberGroup) do setShown(w, hasPact) end
        if not hasPact then
            for _, row in ipairs(ambRows) do row:Hide() end
            ambBox:Hide(); ambAddBtn:Hide(); ambHint:Hide()
            ambWarn:Hide(); ambClaimBtn:Hide()
            setShown(joinWarn, needContact)
            setShown(contactBox, needContact)
            setShown(contactBtn, needContact)
            layoutJoin()
            return
        end
        joinWarn:Hide(); contactBox:Hide(); contactBtn:Hide()

        ------------------------------------------------------------------
        -- Ambassadors
        ------------------------------------------------------------------
        local entry = ally:_MyEntry()
        local list = (entry and entry.ambassadors) or {}
        local me = (Ambiguate and Ambiguate(GuildOS.Compat.PlayerName() or "", "short")) or GuildOS.Compat.PlayerName()
        local vacancy = GuildOS.Alliance._CanClaimAmbassador(list, ally:_GuildRosterShortSet())
        local canEdit = ally:CanAdminister()

        for i, row in ipairs(ambRows) do
            local amb = list[i]
            if amb and not vacancy then
                local label = amb
                if amb:lower() == tostring(me):lower() then
                    label = label .. "  " .. L["(you)"]
                end
                row.name:SetText(label)
                -- Never offer to remove the last one: that would lock the guild
                -- out of its own pact, and the module refuses it anyway.
                setShown(row.del, canEdit and #list > 1)
                row.del:SetScript("OnClick", function()
                    local ok, err = ALLY():RemoveAmbassador(amb)
                    say(ok, err)
                    if ok then
                        GuildOS:Print(string.format(L["%s is no longer an ambassador."], amb))
                    end
                    refresh()
                end)
                row:Show()
            else
                row:Hide()
            end
        end

        setShown(ambWarn, vacancy)
        setShown(ambClaimBtn, vacancy)
        setShown(ambBox, not vacancy and canEdit)
        setShown(ambAddBtn, not vacancy and canEdit)
        setShown(ambHint, not vacancy)
        if vacancy then
            ambWarn:SetText(L["No ambassador of this guild is on the roster any more. Without one this guild cannot invite, approve slots or post."])
        end
        -- Ambassadors only. A plain officer manages the pact but does not
        -- get the code to hand around.
        local isAmb = ally:CanAdminister()
        layout(vacancy and 0 or #list, vacancy, isAmb)
        if not vacancy then
            ambAddBtn:SetPoint("LEFT", ambBox, "RIGHT", 8, 0)
        end

        -- Enable/Disable rather than SetEnabled: both exist on Button and
        -- EditBox in this client, these two are the ones guaranteed to.
        local isOwner = ally:Get().owner == ally:MyGuildName()
        if isOwner then
            removeBtn:Enable()
            removeBox:Enable()
        else
            removeBtn:Disable()
            removeBox:Disable()
        end

        for _, w in ipairs({ codeHdr, codeHdr.rule, codeBox, codeNewBtn, codeHint }) do
            setShown(w, isAmb)
        end
        if isAmb then
            codeBox:SetText(ally:JoinToken() or "")
            if ally:Get().owner == ally:MyGuildName() then
                codeNewBtn:Enable()
            else
                codeNewBtn:Disable()
            end
        end

        local chat = GuildOS.AllianceChat
        local on = chat and chat:Prefs().chat
        -- UI:CreateButton has no SetText; the label is a child FontString.
        chatBtn.label:SetText(on and L["Alliance chat: on"] or L["Alliance chat: off"])
    end

    return refresh
end

----------------------------------------------------------------------
-- Setup: the alliance code, the GreenWall way (issue #348). One code, the same
-- in every guild; an officer saves it and the guild hands it to every member.
----------------------------------------------------------------------
local function BuildSetup(panel)
    local LINK = function() return GuildOS.AllianceLink end

    -- The screen's first section title, then form labels in `text` over their fields (#371).
    local hdr = UI:CreateSectionTitle(panel, L["Alliance code"], true)
    hdr:SetPoint("TOPLEFT", 0, 0)
    local status = UI:CreateText(panel, "", 11, C.text.r, C.text.g, C.text.b)
    status:SetPoint("TOPLEFT", 0, -TITLE_H)
    status:SetJustifyH("LEFT")

    local tagLbl = UI:CreateText(panel, L["Tag (letters and numbers)"], 11)
    tagLbl:SetPoint("TOPLEFT", 0, -50)
    local tagBox = makeInput(panel, 110)
    tagBox:SetPoint("TOPLEFT", 0, -68)
    local guildsLbl = UI:CreateText(panel, L["Guilds, separated by ;"], 11)
    guildsLbl:SetPoint("TOPLEFT", 0, -100)
    local guildsBox = makeInput(panel, 420)
    guildsBox:SetPoint("TOPLEFT", 0, -118)
    local genBtn = UI:CreateButton(panel, L["Generate"], 110, 24)
    genBtn:SetPoint("LEFT", guildsBox, "RIGHT", UI.GAP, 0)

    local lineBox = makeInput(panel, 540)
    lineBox:SetPoint("TOPLEFT", 0, -(118 + 24 + UI.GAP + 4))
    lineBox:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    local writeBtn = UI:CreateButton(panel, L["Save for the guild"], 170, 24)
    writeBtn:SetPoint("TOPLEFT", lineBox, "BOTTOMLEFT", 0, -UI.GAP)
    local removeBtn = UI:CreateButton(panel, L["Turn off for the guild"], 170, 24)
    removeBtn:SetPoint("LEFT", writeBtn, "RIGHT", UI.GAP, 0)

    local hint = UI:CreateText(panel, L["Paste this same code in Alliance > Setup in every guild of the alliance and save. OutlawOS hands it to every member of the guild: no ambassadors, nobody in particular has to be online."],
        10, C.textDim.r, C.textDim.g, C.textDim.b)
    hint:SetPoint("TOPLEFT", writeBtn, "BOTTOMLEFT", 0, -UI.GAP)
    hint:SetWidth(540)
    hint:SetJustifyH("LEFT")
    hint:SetWordWrap(true)
    addFlexHint(hint)

    local refresh
    local function say(ok, err)
        if not ok and err then GuildOS:Print(err) end
    end

    genBtn:SetScript("OnClick", function()
        local link = LINK()
        if not link then return end
        local names = {}
        for name in (guildsBox:GetText() .. ";"):gmatch("([^;]*);") do
            name = strtrim(name)
            if name ~= "" then names[#names + 1] = name end
        end
        local mine = ALLY() and ALLY():MyGuildName()
        local has = false
        for _, n in ipairs(names) do if n == mine then has = true end end
        if mine and not has then table.insert(names, 1, mine) end
        local tag = GuildOS.Alliance.NormalizeTag(tagBox:GetText())
        if tag == "" or #names < 2 then
            GuildOS:Print(L["Name at least two guilds, this one included."])
            return
        end
        -- The same tag keeps its key, so the guilds already set need nothing new but the list.
        local cfg = link:Config()
        local key = (cfg and cfg.tag == tag) and cfg.key or link.NewKey()
        lineBox:SetText(link.Build(tag, key, names))
        lineBox:HighlightText()
    end)
    writeBtn:SetScript("OnClick", function()
        local link = LINK()
        if not link then return end
        local ok, err = link:SetCode(strtrim(lineBox:GetText() or ""))
        say(ok, err)
        if ok then GuildOS:Print(L["Saved. The guild gets it now."]) end
        refresh()
    end)
    removeBtn:SetScript("OnClick", function()
        local link = LINK()
        if not link then return end
        say(link:SetCode(nil))
        refresh()
    end)

    refresh = function()
        local link = LINK()
        if not link then return end
        local cfg = link:Config()
        local mine = ALLY() and ALLY():MyGuildName()
        if cfg and mine and cfg.guilds[mine] then
            status:SetText(string.format(L["Active: %s, %d guilds."], cfg.tag, #cfg.order))
        elseif cfg then
            status:SetText(L["The code does not name this guild."])
        else
            status:SetText(L["No alliance set up for this guild."])
        end
        local officer = GuildOS:IsOfficer()
        for _, w in ipairs({ tagLbl, tagBox, guildsLbl, guildsBox, genBtn, lineBox, writeBtn, removeBtn, hint }) do
            setShown(w, officer)
        end
        if not officer then return end
        if not lineBox:HasFocus() then
            local line = link:Suggest()
            local parsed = line and link.Parse(line)
            lineBox:SetText(line or "")
            if parsed and tagBox:GetText() == "" then
                tagBox:SetText(parsed.tag)
                guildsBox:SetText(table.concat(parsed.order, "; "))
            end
        end
        if link:Config() then removeBtn:Enable() else removeBtn:Disable() end
    end
    return refresh
end

----------------------------------------------------------------------
-- Confirmations
----------------------------------------------------------------------
local function registerPopups()
    if GuildOS.Dialogs["GUILDOS_ALLY_REMOVE"] then return end

    GuildOS.Dialogs["GUILDOS_ALLY_REMOVE"] = {
        text = "%s", button1 = L["Remove"], button2 = L["Cancel"],
        OnAccept = function(self)
            local d = self and self.data
            if not d then return end
            local ok, err = GuildOS.Alliance:RemoveGuild(d.guild)
            if not ok and err then GuildOS:Print(err) end
            if d.after then d.after() end
        end,
        timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
    }

    GuildOS.Dialogs["GUILDOS_ALLY_BAN"] = {
        text = "%s", button1 = L["Ban"], button2 = L["Cancel"],
        OnAccept = function(self)
            local d = self and self.data
            if d and d.name and GuildOS.AllianceChat:Ban(d.name) then
                GuildOS:Print(string.format(L["Asked the server to ban %s from the channel."], d.name))
            end
        end,
        timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
    }

    GuildOS.Dialogs["GUILDOS_ALLY_LEAVE"] = {
        text = "%s", button1 = L["Leave"], button2 = L["Cancel"],
        OnAccept = function(self)
            local ok, err = GuildOS.Alliance:Leave()
            if not ok and err then GuildOS:Print(err) end
            local d = self and self.data
            if d and d.after then d.after() end
        end,
        timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
    }
end

----------------------------------------------------------------------
-- Entry point, called from UI/RosterFrame.lua
----------------------------------------------------------------------
-- Bulletin first: it is the alliance's front page, the thing an allied leader
-- should land on. Bulletin and Chat need a pact to mean anything, so they hide
-- until there is one, and the panel opens on whichever tab is first VISIBLE.
local SUBTABS = {
    { key = "bulletin", label = L["Bulletin"], needsPact = true },
    { key = "chat",     label = L["Chat"],     needsPact = true },
    { key = "events",   label = L["Events"],   needsPact = true },
    -- The alliance applications: for ambassadors only, the ones who can accept or decline them.
    { key = "applications", label = L["Applications"], needsAmbassador = true },
    { key = "overview", label = L["Overview"] },
    { key = "setup",    label = L["Setup"] },
    { key = "manage",   label = L["Manage"] },
}

function GuildOS:CreateAlliancePanel(parent, _mainFrame)
    registerPopups()
    parent.subPanels = {}
    parent.activeSub = nil

    -- Left-anchored: UI:FlowBar reads GetWidth, and a frame pinned on both
    -- sides reports a stale width in the frame its container was resized.
    local bar = CreateFrame("Frame", nil, parent)
    bar:SetPoint("TOPLEFT", 10, -8)
    bar:SetSize(400, 28)
    UI:StyleSubTabBar(bar)

    local btns = {}
    local function selectSub(key)
        parent.activeSub = key
        for k, info in pairs(parent.subPanels) do info.panel:SetShown(k == key) end
        for k, btn in pairs(btns) do btn:SetActive(k == key) end
        local info = parent.subPanels[key]
        if info and info.refresh then GuildOS:SafeCall(info.refresh) end
    end
    parent.SelectSub = selectSub

    for _, t in ipairs(SUBTABS) do
        local btn = UI:CreateTab(bar, t.label, TAB_MIN_W, true)
        btn:SetWidth(math.max(TAB_MIN_W, math.ceil(btn.label:GetStringWidth()) + TAB_PAD))
        btn:SetScript("OnClick", function() selectSub(t.key) end)
        btns[t.key] = btn
    end

    -- Flow the VISIBLE tabs only, so hiding Chat and Bulletin without a
    -- pact leaves no gap in the bar. UI:FlowBar wraps to a second row when
    -- the window is too narrow, and its returned height is what pushes the
    -- sub-panels down.
    local function isAmbassador()
        local A = GuildOS.Alliance
        return (A and A.IsMyAmbassador and A:IsMyAmbassador()) and true or false
    end

    local hasPactNow = false
    local function layoutTabs(hasPact)
        hasPactNow = hasPact
        local visible, first = {}, nil
        for _, t in ipairs(SUBTABS) do
            local btn = btns[t.key]
            local show = (hasPact or not t.needsPact) and (not t.needsAmbassador or isAmbassador())
            setShown(btn, show)
            if show then
                visible[#visible + 1] = btn
                first = first or t.key
            end
        end
        UI:FlowBar(bar, visible, { gap = 4, rowGap = 4, rowH = TAB_H })
        return first
    end

    -- Anchored to the bar, not a fixed offset, so a wrapped two-row tab
    -- bar pushes the content down instead of hiding behind it. Flush with the
    -- bar's left edge, UI.GAP under it, ending UI.GAP short of its right edge
    -- (the bar spans the parent less 10px a side), as every screen does (#371).
    local function makeSubPanel()
        local p = CreateFrame("Frame", nil, parent)
        p:SetPoint("TOPLEFT", bar, "BOTTOMLEFT", 0, -UI.GAP)
        p:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", -(10 + UI.GAP), 10)
        p:Hide()
        return p
    end

    local builders = {
        chat = BuildChat, overview = BuildOverview, events = BuildEvents,
        bulletin = BuildBulletin, manage = BuildManage, setup = BuildSetup,
        applications = function(p) return GuildOS:CreateAllianceApplicationsPanel(p) end,
    }
    flexHints = {}
    for _, t in ipairs(SUBTABS) do
        local p = makeSubPanel()
        parent.subPanels[t.key] = { panel = p, refresh = builders[t.key](p) }
    end
    -- Take this instance's list and close the collector, so a second
    -- container starts a fresh one.
    local myHints = flexHints
    flexHints = nil

    -- Unread count on the Chat tab, so a message that lands while you are on
    -- another tab is not silently missed.
    local function paintUnread()
        local chat = GuildOS.AllianceChat
        local n = (chat and chat.unread) or 0
        local btn = btns["chat"]
        if not btn then return end
        btn.label:SetText(n > 0 and string.format("%s (%d)", L["Chat"], n) or L["Chat"])
    end
    -- The Applications tab says how many are open, "Applications (2)", and follows each change.
    local function paintApplications()
        local btn = btns["applications"]
        if not (btn and GuildOS.JoinRequests) then return end
        local ok, n = pcall(GuildOS.JoinRequests.OpenCount, GuildOS.JoinRequests, "alliance")
        n = ok and n or 0
        btn.label:SetText(n > 0 and string.format(L["Applications (%d)"], n) or L["Applications"])
    end
    if GuildOS.JoinRequests and GuildOS.JoinRequests.Listen then GuildOS.JoinRequests:Listen(paintApplications) end
    paintApplications()

    if GuildOS.AllianceChat then
        GuildOS.AllianceChat:OnRefresh(function()
            if parent:IsVisible() then paintUnread() end
        end)
    end

    parent:SetScript("OnShow", function()
        local hasPact = GuildOS.Alliance and GuildOS.Alliance:Get() ~= nil
        local first = layoutTabs(hasPact)
        local want = parent.activeSub
        -- Falling out of a pact must not strand the panel on a hidden tab, and
        -- the landing tab is simply the first visible one, so reordering
        -- SUBTABS is the only thing anyone has to change.
        if not want or not btns[want] or not btns[want]:IsShown() then
            want = first or "overview"
        end
        selectSub(want)
        paintUnread()
        paintApplications()
    end)

    ----------------------------------------------------------------
    -- Layout: the tab bar rewraps and the wrapped hint texts follow the
    -- panel instead of the fixed 460px they used to assume.
    ----------------------------------------------------------------
    UI:MakeResponsive(parent, function(_, w, _)
        bar:SetWidth(math.max(TAB_MIN_W, w - 20))
        layoutTabs(hasPactNow)
        local hintW = math.max(220, w - 90)
        for _, fs in ipairs(myHints) do fs:SetWidth(hintW) end
    end)
end
