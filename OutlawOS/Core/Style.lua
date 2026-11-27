----------------------------------------------------------------------
-- Guild OS - Interface styles (issue #122; spec docs/superpowers/specs/2026-10-07-ui-styles-design.md §4)
-- A style is how the addon is painted: its palette, its font, and the art behind each role
-- (window, title bar, panel, well, popup, input) and control (button, tab, checkbox, close
-- button, scroll bar). "guildos" is the flat look the addon was made with; it paints exactly as
-- the Helpers always did. "forever" paints with the WoW: Forever client's own -c60 atlases, and
-- is offered only where the client has them. The choice belongs to the account (GuildOSDB.style)
-- and takes effect at load: frames are built once, so a switch asks for a reload.
----------------------------------------------------------------------
local Style = {}
GuildOS.Style = Style
local L = GuildOS.L

Style.DEFAULT = "guildos"
Style.ORDER = { "guildos", "classic", "alliance", "forever" }
-- Styles taken out of the picker. An account that had one saved quietly goes back to the default.
Style.RETIRED = { parchment = true }
Style.current = Style.DEFAULT

local INFO = {
    guildos = { name = "OutlawOS", desc = L["Flat and dark: the classic look."] },
    classic = { name = "GuildOS", desc = L["The original GuildOS look: flat and dark, with no leather or brass."] },
    alliance = { name = "Alliance", desc = L["Deep royal blue with silver and gold trim."] },
    parchment = { name = "Parchment", desc = L["Light cream and tan with dark brown text, like an old ledger page. Class colours are darkened so they read on cream."] },
    forever = { name = "WoW: Forever",
                desc = L["The game's own bronze frames, tabs and buttons. A beta: tell us what looks off."] },
}

-- Names are the client's atlas ELEMENTS. On WoW: Forever an element resolves to its -c60 member (the
-- active atlas set); the member names themselves ("…-c60") are not addressable: GetAtlasInfo answers
-- nil for them in game (checked on 1.60.1.70245).
-- A frame's border in nine pieces: four corners, and edges whose names start with "_" (tiled across)
-- or "!" (tiled down).
local function nine(prefix, scale, center)
    return { kind = "nine", scale = scale, center = center,
        TopLeftCorner = prefix .. "CornerTopLeft", TopRightCorner = prefix .. "CornerTopRight",
        BottomLeftCorner = prefix .. "CornerBottomLeft", BottomRightCorner = prefix .. "CornerBottomRight",
        TopEdge = "_" .. prefix .. "EdgeTop", BottomEdge = "_" .. prefix .. "EdgeBottom",
        LeftEdge = "!" .. prefix .. "EdgeLeft", RightEdge = "!" .. prefix .. "EdgeRight" }
end
local function three(left, center, right)
    return { kind = "three", Left = left, Center = center, Right = right }
end
local function redButton(state)
    local s = (state == "rest") and "" or ("-" .. state)
    return three("128-RedButton-Left" .. s, "_128-RedButton-Center" .. s, "128-RedButton-Right" .. s)
end
local function iconButton(name)
    return { rest = "128-RedButton-" .. name, pressed = "128-RedButton-" .. name .. "-Pressed",
             disabled = "128-RedButton-" .. name .. "-Disabled" }
end

-- The Forever client's art (build 1.60.1.70245), by role. A nine-slice's pieces are the atlas size
-- times `scale`; a three-slice is as tall as its frame. Candidates until beta screenshots of
-- /gos style preview confirm them (spec §4.6).
-- A panel and a well paint flat, a thin bronze line on the palette's colour: the Settings frame's art
-- around every card was heavier than the window it sat in, and a player asked for the line the small
-- cards already had. The title bar has no band of its own: the metal frame's top edge is the bar, and a
-- band over it met the frame's corner a few pixels off (#148).
Style.FOREVER = {
    window   = nine("UI-Frame-Metal-", 0.25),
    -- Its -c60 centre is not in Forever's atlas set (the client would draw the plain one): no centre.
    popup    = nine("Tooltip-NineSlice-", 1),
    input    = three("common-search-border-left", "common-search-border-middle", "common-search-border-right"),
    -- Only a screen's one primary button: the rest are the flat dark button with its bronze line, so a
    -- screen does not mix red buttons with the dark tabs beside them (#148).
    button   = { rest = redButton("rest"), pressed = redButton("Pressed"), disabled = redButton("Disabled") },
    -- The Settings panel's top tabs, in three pieces that stretch to any label; the open one is
    -- the taller active art. (One 96px tab atlas stretched across a label smeared its corners.)
    tab      = { rest = three("Options_Tab_Left", "Options_Tab_Middle", "Options_Tab_Right"),
                 active = three("Options_Tab_Active_Left", "Options_Tab_Active_Middle", "Options_Tab_Active_Right") },
    checkbox = { box = "checkbox-minimal", mark = "Talents-Checkmark-c60" },
    close    = iconButton("Exit"),
    minimise = iconButton("Minus"),
    scroll   = { track = "!minimal-scrollbar-track-middle", thumb = "minimal-scrollbar-thumb-middle" },
}
-- The pieces that say the client has the art at all: elements only Forever has (Anniversary draws the
-- red button and the tooltip too, with its own art), on the in-game canvas.
Style.KEY_ATLASES = { "common-internaltab", "OptionsFrame-NineSlice-CornerTopLeft" }
local KEY_ATLASES = Style.KEY_ATLASES

-- Stone, bronze and parchment, with the game's yellow as the accent. Status colours keep theirs.
local function rgb(r, g, b, a) return { r = r, g = g, b = b, a = a or 1 } end
Style.FOREVER_PALETTE = {
    bg = rgb(0.078, 0.067, 0.055), panel = rgb(0.125, 0.106, 0.086), popup = rgb(0.157, 0.133, 0.106),
    well = rgb(0.051, 0.043, 0.035), line = rgb(0.361, 0.290, 0.180), lineHi = rgb(0.549, 0.443, 0.263),
    text = rgb(1.000, 0.957, 0.859), textSoft = rgb(0.824, 0.761, 0.624), label = rgb(0.722, 0.643, 0.482),
    labelDim = rgb(0.522, 0.459, 0.349), disabled = rgb(0.400, 0.361, 0.298),
    gold = rgb(1.000, 0.820, 0.000), onGold = rgb(0.149, 0.098, 0.020),
    -- A primary button without the red art falls back to the flat one: its hover and press follow this gold.
    goldHover = rgb(1.000, 0.878, 0.302), goldActive = rgb(0.851, 0.698, 0.000),
}

-- The flat themes. Each paints exactly as the "guildos" style does, in its own palette; none of them wears
-- the Outlaw leather, brass emblem or western fonts (the EKO theme is switched off for them in Resolve).
-- `palette` nil: the palette GuildOS shipped with.
Style.THEMES = {
    classic = {},
    alliance = { palette = {
        bg = rgb(0.043, 0.071, 0.133), panel = rgb(0.067, 0.110, 0.200), popup = rgb(0.090, 0.145, 0.251),
        well = rgb(0.031, 0.051, 0.098), line = rgb(0.416, 0.337, 0.141), lineHi = rgb(0.749, 0.612, 0.239),
        text = rgb(0.933, 0.949, 0.984), textSoft = rgb(0.682, 0.741, 0.839), label = rgb(0.553, 0.620, 0.753),
        labelDim = rgb(0.384, 0.451, 0.604), disabled = rgb(0.239, 0.286, 0.400),
        gold = rgb(0.878, 0.722, 0.298), goldHover = rgb(0.929, 0.784, 0.384), goldActive = rgb(0.769, 0.616, 0.220),
        onGold = rgb(0.043, 0.071, 0.133),
    } },
    parchment = { light = true, classScale = 0.55, palette = {
        bg = rgb(0.894, 0.847, 0.737), panel = rgb(0.827, 0.765, 0.627), popup = rgb(0.937, 0.898, 0.796),
        well = rgb(0.953, 0.918, 0.835), line = rgb(0.722, 0.643, 0.490), lineHi = rgb(0.545, 0.439, 0.282),
        text = rgb(0.169, 0.122, 0.078), textSoft = rgb(0.353, 0.275, 0.188), label = rgb(0.431, 0.345, 0.239),
        labelDim = rgb(0.545, 0.463, 0.345), disabled = rgb(0.620, 0.561, 0.451),
        gold = rgb(0.604, 0.337, 0.071), goldHover = rgb(0.690, 0.404, 0.110), goldActive = rgb(0.502, 0.271, 0.047),
        onGold = rgb(0.984, 0.953, 0.878),
        ok = rgb(0.184, 0.490, 0.227), danger = rgb(0.690, 0.227, 0.180),
    } },
}

----------------------------------------------------------------------
-- Atlases
----------------------------------------------------------------------
local function atlasInfo(name)
    local get = C_Texture and C_Texture.GetAtlasInfo
    if not get then return nil end
    local ok, info = pcall(get, name)
    return ok and info or nil
end

-- Every atlas a piece of art names, depth first.
function Style.AtlasNames(art, out)
    out = out or {}
    if type(art) == "string" then out[#out + 1] = art; return out end
    for k, v in pairs(art or {}) do
        if k ~= "kind" and (type(v) == "string" or type(v) == "table") then Style.AtlasNames(v, out) end
    end
    return out
end

-- True when the client has every atlas of `art`. Each missing one is recorded once per session.
local reported = {}
function Style:_HasArt(art)
    local all = true
    for _, n in ipairs(Style.AtlasNames(art)) do
        if not atlasInfo(n) then
            all = false
            if not reported[n] then
                reported[n] = true
                GuildOS:RecordError("style forever: the client has no atlas " .. n)
            end
        end
    end
    return all
end

----------------------------------------------------------------------
-- The registry
----------------------------------------------------------------------
function Style:Has(id)
    if Style.RETIRED[id] then return false end
    if id == "guildos" or Style.THEMES[id] then return true end
    if id ~= "forever" then return false end
    for _, n in ipairs(KEY_ATLASES) do
        if not atlasInfo(n) then return false end
    end
    return true
end

function Style:Available()
    local out = {}
    for _, id in ipairs(self.ORDER) do
        if self:Has(id) then out[#out + 1] = id end
    end
    return out
end

function Style:Name(id) return INFO[id] and INFO[id].name or tostring(id) end
function Style:Description(id) return INFO[id] and INFO[id].desc or "" end
function Style:Current() return self.current end

-- A light theme: dark text on cream. Safe to ask from any file at load, before Resolve has run.
function Style:IsLight()
    local id = self.current or (type(GuildOSDB) == "table" and GuildOSDB.style) or nil
    local theme = id and not Style.RETIRED[id] and Style.THEMES[id]
    return theme and theme.light and true or false
end

-- A colour code for text. On a light theme the bright colours made for dark windows (lime, pale yellow,
-- white) are brought down to a lightness that reads on cream; dark ones and the dark themes are untouched.
local function lightFix(r, g, b)
    local lum = 0.299 * r + 0.587 * g + 0.114 * b
    if lum <= 0.38 then return r, g, b end
    local f = 0.38 / lum
    return r * f, g * f, b * f
end
function GuildOS.Esc(hex)
    if not GuildOS.Style:IsLight() then return "|cff" .. hex end
    local r, g, b = tonumber(hex:sub(1, 2), 16), tonumber(hex:sub(3, 4), 16), tonumber(hex:sub(5, 6), 16)
    if not (r and g and b) then return "|cff" .. hex end
    r, g, b = lightFix(r / 255, g / 255, b / 255)
    return string.format("|cff%02x%02x%02x", math.floor(r * 255 + 0.5), math.floor(g * 255 + 0.5), math.floor(b * 255 + 0.5))
end
function GuildOS.LightFix(r, g, b)
    if GuildOS.Style:IsLight() then return lightFix(r, g, b) end
    return r, g, b
end

-- Colours for tooltip lines. The game's tooltip stays dark on every theme, so on a light theme the palette's
-- dark brown text would not show on it: these are the light equivalents. GuildOS.Tip.text.r etc., read live.
local TIP_LIGHT = {
    text = { 0.93, 0.90, 0.84 }, textSoft = { 0.78, 0.72, 0.60 }, label = { 0.72, 0.64, 0.50 },
    labelDim = { 0.60, 0.54, 0.42 }, silver = { 0.78, 0.72, 0.60 }, textDim = { 0.72, 0.64, 0.50 },
    disabled = { 0.50, 0.46, 0.40 }, gold = { 0.90, 0.72, 0.30 }, accent = { 0.90, 0.72, 0.30 },
    ok = { 0.49, 0.85, 0.56 }, green = { 0.49, 0.85, 0.56 }, danger = { 0.94, 0.48, 0.45 }, red = { 0.94, 0.48, 0.45 },
    warn = { 0.91, 0.60, 0.35 }, info = { 0.36, 0.58, 0.81 },
}
GuildOS.Tip = setmetatable({}, { __index = function(_, k)
    local l = TIP_LIGHT[k]
    if l and GuildOS.Style:IsLight() then return { r = l[1], g = l[2], b = l[3], a = 1 } end
    return GuildOS.Colors[k]
end })

-- The gold of text colour codes: the light yellow on dark themes, the deep amber of the Parchment accent on cream.
function GuildOS.GoldEsc()
    return GuildOS.Style:IsLight() and "|cff9a5612" or "|cffe6b84a"
end

-- Saves the account's choice; it is used from the next load on.
function Style:Choose(id)
    if not INFO[id] then return false, "unknown" end
    if not self:Has(id) then return false, "unavailable" end
    if type(GuildOSDB) ~= "table" then GuildOSDB = {} end
    GuildOSDB.style = id
    return true
end

-- At load, before any window is built: the saved style if this client draws it, else the default,
-- said once. The Forever style re-points the palette in place and takes the game's font.
function Style:Resolve()
    local want = type(GuildOSDB) == "table" and GuildOSDB.style or nil
    local id = (want and self:Has(want)) and want or self.DEFAULT
    self.current, self.gameFont = id, nil
    if want and want ~= id and not Style.RETIRED[want] then
        GuildOS:Print(string.format(L["The %s style is not available on this client; using %s."],
            self:Name(want), self:Name(id)))
    end
    if id == "forever" then
        GuildOS:RepointColors(self.FOREVER_PALETTE)
        self.gameFont = true
    end
    local theme = Style.THEMES[id]
    if theme then
        -- Off with the Outlaw leather and fonts first (it puts GuildOS's own palette back), then the theme's.
        if GuildOS.EKO and GuildOS.EKO.ApplyTheme then
            GuildOS.EKO:ApplyTheme(false)
            if GuildOS.EKO.ApplyFonts then GuildOS.EKO:ApplyFonts(false) end
        end
        if theme.palette then GuildOS:RepointColors(theme.palette) end
        -- On cream the pale class colours (priest white, rogue yellow, hunter green) vanish: darken them.
        if theme.classScale then
            Style.classOriginal = Style.classOriginal or {}
            for class, c in pairs(GuildOS.ClassColors) do
                local o = Style.classOriginal[class]
                if not o then o = { r = c.r, g = c.g, b = c.b }; Style.classOriginal[class] = o end
                c.r, c.g, c.b = o.r * theme.classScale, o.g * theme.classScale, o.b * theme.classScale
            end
        end
    end
    return id
end

GuildOS.Dialogs["GUILDOS_STYLE_RELOAD"] = {
    text = "%s", button1 = L["Reload"], button2 = L["Later"],
    OnAccept = function() ReloadUI() end,
    timeout = 0, whileDead = true, hideOnEscape = true,
}

-- The picker's and /gos style's verb: save, then offer the reload.
function Style:Apply(id)
    local ok, why = self:Choose(id)
    if not ok then
        if why == "unknown" then
            GuildOS:Print(string.format(L["Unknown style: %s. Styles: %s"], tostring(id), table.concat(self.ORDER, ", ")))
        else
            GuildOS:Print(string.format(L["The %s style is not available on this client."], self:Name(id)))
        end
        return false
    end
    GuildOS:ShowDialog("GUILDOS_STYLE_RELOAD", string.format(L["Reload the interface now to use the %s style?"], self:Name(id)))
    return true
end

function Style:PrintList()
    for _, id in ipairs(self.ORDER) do
        local tag = (id == self.current and L["in use"]) or ((not self:Has(id)) and L["not available here"]) or nil
        GuildOS:Print("  " .. id .. " - " .. self:Name(id) .. (tag and (" (" .. tag .. ")") or ""))
    end
end

----------------------------------------------------------------------
-- Painting by role
----------------------------------------------------------------------
local WHITE = "Interface\\Buttons\\WHITE8x8"

local function roleColor(role)
    local C = GuildOS.Colors
    if role == "well" or role == "input" then return C.well end
    if role == "titlebar" then return C.panel end
    return C.bg
end

-- Today's paint, unchanged: a WHITE8x8 backdrop with a 1px `line` border, or the title bar's band.
-- A popup's background is its caller's (Helpers:StylePopup sets only the lineHi border), so flat leaves it alone.
function Style:_PaintFlat(frame, role)
    local C = GuildOS.Colors
    if role == "popup" then return "flat" end
    if role == "titlebar" then
        local bg = frame.__styleBg or frame:CreateTexture(nil, "BACKGROUND")
        bg:SetTexture(WHITE)
        bg:SetAllPoints()
        bg:SetVertexColor(C.panel.r, C.panel.g, C.panel.b, 1)
        frame.__styleBg = bg
        return "flat"
    end
    local c = roleColor(role)
    frame:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = GuildOS.UI:Edge(frame) })
    frame:SetBackdropColor(c.r, c.g, c.b, 1)
    frame:SetBackdropBorderColor(C.line.r, C.line.g, C.line.b, 1)
    return "flat"
end

-- As the client's NineSliceUtil does: the atlas says whether it repeats, and that is set before it.
local function setAtlas(tex, name)
    local info = atlasInfo(name)
    tex:SetHorizTile(info and info.tilesHorizontally or false)
    tex:SetVertTile(info and info.tilesVertically or false)
    tex:SetAtlas(name)
    return info
end

local function setAtlasSized(tex, name, scale)
    local info = setAtlas(tex, name)
    tex:SetSize((info and info.width or 0) * scale, (info and info.height or 0) * scale)
end

local NINE = { "TopLeftCorner", "TopRightCorner", "BottomLeftCorner", "BottomRightCorner",
               "TopEdge", "BottomEdge", "LeftEdge", "RightEdge" }

-- The border in nine pieces around the role's colour.
function Style:_PaintNine(frame, art, role)
    local c = roleColor(role)
    frame:SetBackdrop({ bgFile = WHITE })
    frame:SetBackdropColor(c.r, c.g, c.b, 1)
    local p = frame.__nine or {}
    frame.__nine = p
    for _, key in ipairs(NINE) do
        p[key] = p[key] or frame:CreateTexture(nil, "BORDER")
        setAtlasSized(p[key], art[key], art.scale)
        p[key]:ClearAllPoints()
    end
    p.TopLeftCorner:SetPoint("TOPLEFT")
    p.TopRightCorner:SetPoint("TOPRIGHT")
    p.BottomLeftCorner:SetPoint("BOTTOMLEFT")
    p.BottomRightCorner:SetPoint("BOTTOMRIGHT")
    p.TopEdge:SetPoint("TOPLEFT", p.TopLeftCorner, "TOPRIGHT")
    p.TopEdge:SetPoint("TOPRIGHT", p.TopRightCorner, "TOPLEFT")
    p.BottomEdge:SetPoint("BOTTOMLEFT", p.BottomLeftCorner, "BOTTOMRIGHT")
    p.BottomEdge:SetPoint("BOTTOMRIGHT", p.BottomRightCorner, "BOTTOMLEFT")
    p.LeftEdge:SetPoint("TOPLEFT", p.TopLeftCorner, "BOTTOMLEFT")
    p.LeftEdge:SetPoint("BOTTOMLEFT", p.BottomLeftCorner, "TOPLEFT")
    p.RightEdge:SetPoint("TOPRIGHT", p.TopRightCorner, "BOTTOMRIGHT")
    p.RightEdge:SetPoint("BOTTOMRIGHT", p.BottomRightCorner, "TOPRIGHT")
    if art.center then
        p.Center = p.Center or frame:CreateTexture(nil, "BACKGROUND", nil, 1)
        setAtlas(p.Center, art.center)
        p.Center:ClearAllPoints()
        p.Center:SetPoint("TOPLEFT", p.TopLeftCorner, "BOTTOMRIGHT")
        p.Center:SetPoint("BOTTOMRIGHT", p.BottomRightCorner, "TOPLEFT")
    end
    -- Corners that would overlap (a small card, a collapsed window) make no border: such a frame
    -- paints flat until it is big enough, and is looked at again whenever its size changes.
    local function fit()
        local w, h = frame:GetWidth() or 0, frame:GetHeight() or 0
        local minW = math.max(p.TopLeftCorner:GetWidth() + p.TopRightCorner:GetWidth(),
                              p.BottomLeftCorner:GetWidth() + p.BottomRightCorner:GetWidth())
        local minH = math.max(p.TopLeftCorner:GetHeight() + p.BottomLeftCorner:GetHeight(),
                              p.TopRightCorner:GetHeight() + p.BottomRightCorner:GetHeight())
        local small = w > 0 and h > 0 and (w < minW or h < minH)
        if small == frame.__nineSmall then return end
        frame.__nineSmall = small
        for _, t in pairs(p) do t:SetShown(not small) end
        local C, fill = GuildOS.Colors, roleColor(role)
        if small then
            frame:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = GuildOS.UI:Edge(frame) })
            frame:SetBackdropBorderColor(C.line.r, C.line.g, C.line.b, 1)
        else
            frame:SetBackdrop({ bgFile = WHITE })
        end
        frame:SetBackdropColor(fill.r, fill.g, fill.b, 1)
    end
    frame.__nineSmall = nil
    fit()
    if not frame.__nineHooked then
        frame.__nineHooked = true
        frame:HookScript("OnSizeChanged", fit)
    end
    return "art"
end

-- Three pieces side by side, as tall as the frame. The caps keep their atlas proportions at that
-- height and are squeezed together when the frame is narrower than both.
function Style:_PaintThree(frame, art, layer)
    local p = frame.__three or {}
    frame.__three = p
    for _, k in ipairs({ "Left", "Center", "Right" }) do
        p[k] = p[k] or frame:CreateTexture(nil, layer or "BACKGROUND")
        setAtlas(p[k], art[k])
    end
    local function layout()
        local h, w = frame:GetHeight() or 0, frame:GetWidth() or 0
        local li, ri = atlasInfo(art.Left), atlasInfo(art.Right)
        local k = (li and li.height and li.height > 0) and (h / li.height) or 1
        local lw, rw = (li and li.width or 0) * k, (ri and ri.width or 0) * k
        if w > 0 and lw + rw > w then
            local f = w / (lw + rw)
            lw, rw = lw * f, rw * f
        end
        p.Left:ClearAllPoints(); p.Left:SetPoint("TOPLEFT"); p.Left:SetPoint("BOTTOMLEFT"); p.Left:SetWidth(lw)
        p.Right:ClearAllPoints(); p.Right:SetPoint("TOPRIGHT"); p.Right:SetPoint("BOTTOMRIGHT"); p.Right:SetWidth(rw)
        p.Center:ClearAllPoints()
        p.Center:SetPoint("TOPLEFT", p.Left, "TOPRIGHT")
        p.Center:SetPoint("BOTTOMRIGHT", p.Right, "BOTTOMLEFT")
    end
    layout()
    if not frame.__threeHooked then
        frame.__threeHooked = true
        frame:HookScript("OnSizeChanged", layout)
    end
    return p
end

-- Paint `frame` as `role`. In the Forever style with the client's art, the role's art; otherwise,
-- and for any piece the client lacks, today's flat paint.
function Style:Paint(frame, role)
    -- On the game's metal frame the window's own top edge is the title bar: nothing to paint (#148).
    if role == "titlebar" and self.current == "forever" and self:_HasArt(self.FOREVER.window) then return "none" end
    local art = (self.current == "forever") and self.FOREVER[role] or nil
    if art and self:_HasArt(art) then
        if art.kind == "nine" then return self:_PaintNine(frame, art, role) end
        if role == "titlebar" then self:_PaintFlat(frame, role) end   -- the band behind the art
        if role == "input" then
            local c = roleColor(role)
            frame:SetBackdrop({ bgFile = WHITE })
            frame:SetBackdropColor(c.r, c.g, c.b, 1)
        end
        self:_PaintThree(frame, art, role == "titlebar" and "ARTWORK" or "BORDER")
        return "art"
    end
    return self:_PaintFlat(frame, role)
end

----------------------------------------------------------------------
-- Controls. Each is a no-op returning false in the guildos style (or without the art), so the
-- Helpers keep painting as they always did.
----------------------------------------------------------------------
local function forever(self, art) return self.current == "forever" and self:_HasArt(art) end

-- A primary button's art (Helpers:SetButtonVariant asks; #148). Above the backdrop, below the label.
function Style:SkinButton(btn)
    if not forever(self, self.FOREVER.button) then return false end
    btn.__forever = true
    self:_PaintThree(btn, self.FOREVER.button.rest, "BORDER")
    for _, t in pairs(btn.__three) do t:Show() end
    return true
end

-- A primary button switched to another variant goes back to the flat button.
function Style:UnskinButton(btn)
    if not btn.__forever then return end
    btn.__forever = nil
    for _, t in pairs(btn.__three or {}) do t:Hide() end
end

-- A toggle's colour (SetBaseColor) on the game's art: a tint of the art itself. A grey, the "off"
-- the screens use, dims it; any other colour tints it toward that colour; none leaves it as it is.
function Style:ButtonTint(btn, r, g, b, a)
    local hi, lo = math.max(r, g, b), math.min(r, g, b)
    local tr, tg, tb = 1, 1, 1
    if (a or 1) > 0 and hi > 0 then
        if hi - lo < 0.06 then
            tr, tg, tb = 0.55, 0.55, 0.55
        else
            tr, tg, tb = 0.6 + 0.4 * r / hi, 0.6 + 0.4 * g / hi, 0.6 + 0.4 * b / hi
        end
    end
    for _, t in pairs(btn.__three) do t:SetVertexColor(tr, tg, tb, 1) end
end

-- Only a primary button wears the art since #148; a ghost link, the one with an underline, is flat
-- and coloured by the Helpers. The other variants stay handled for a button switched back and forth.
function Style:ButtonState(btn, state)
    local C = GuildOS.Colors
    local key = (state == "pressed" or state == "disabled") and state or "rest"
    local art, p = self.FOREVER.button[key], btn.__three
    setAtlas(p.Left, art.Left); setAtlas(p.Center, art.Center); setAtlas(p.Right, art.Right)
    local ghost = btn.variant == "ghost"
    for _, t in pairs(p) do t:SetShown(not ghost) end
    btn:SetBackdropColor(0, 0, 0, 0)
    btn:SetBackdropBorderColor(0, 0, 0, 0)
    local rest = (btn.variant == "danger" and C.danger) or (ghost and C.label) or C.gold
    local ink = (state == "disabled" and C.disabled) or (state == "hover" and C.text) or rest
    btn.label:SetTextColor(ink.r, ink.g, ink.b)
    btn.__hovered = (state == "hover")
    if btn.underline then btn.underline:SetShown(ghost) end
end

function Style:SkinTab(tab)
    if not forever(self, self.FOREVER.tab) then return false end
    self:_PaintThree(tab, self.FOREVER.tab.rest, "BACKGROUND")
    tab.__styleTab = true
    return true
end

-- The open tab takes the active art; hover only lights the label (the Helpers paint it).
function Style:TabState(tab)
    local art, p = tab.isActive and self.FOREVER.tab.active or self.FOREVER.tab.rest, tab.__three
    setAtlas(p.Left, art.Left); setAtlas(p.Center, art.Center); setAtlas(p.Right, art.Right)
end

function Style:SkinCheckbox(_, border, fill, mark)
    if not forever(self, self.FOREVER.checkbox) then return false end
    border:Hide()
    fill:SetAtlas(self.FOREVER.checkbox.box)
    fill:SetVertexColor(1, 1, 1, 1)
    mark:SetAtlas(self.FOREVER.checkbox.mark)
    mark:SetVertexColor(1, 1, 1, 1)
    return true
end

-- The close button, or (kind "minimise") the minimise button the window makes from it.
function Style:SkinClose(btn, kind)
    local art = self.FOREVER[kind == "minimise" and "minimise" or "close"]
    if not forever(self, art) then return false end
    btn.__art = btn.__art or btn:CreateTexture(nil, "ARTWORK")
    btn.__art:SetAllPoints()
    btn.__art:SetAtlas(art.rest)
    if btn.x then btn.x:Hide() end
    btn:SetScript("OnEnter", nil)
    btn:SetScript("OnLeave", nil)
    btn:SetScript("OnMouseDown", function(b) b.__art:SetAtlas(art.pressed) end)
    btn:SetScript("OnMouseUp", function(b) b.__art:SetAtlas(art.rest) end)
    return true
end

function Style:SkinScrollBar(track, thumb)
    if not forever(self, self.FOREVER.scroll) then return false end
    track:SetAtlas(self.FOREVER.scroll.track)
    track:SetVertexColor(1, 1, 1, 1)
    thumb:SetAtlas(self.FOREVER.scroll.thumb)
    thumb:SetVertexColor(1, 1, 1, 1)
    return true
end
