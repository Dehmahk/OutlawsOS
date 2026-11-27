----------------------------------------------------------------------
-- Guild OS - Mentions / Watch-words
-- Alerts you when your name (or a watch-word) appears in guild/officer
-- chat. Personal, no sync. Keeps a small capped recent-mentions log.
----------------------------------------------------------------------
local Mentions = {}
GuildOS.Mentions = Mentions
local L = GuildOS.L

local LOG_MAX = 100
local MIN_WORD = 3      -- shorter watch-words fire on nearly every message

Mentions.DEFAULTS = {
    enabled   = true,
    ownName   = true,
    watchWords= {},
    sound     = true,
    guild     = true,
    officer   = true,
    officerCall = true,   -- someone writes "officer" in guild chat: whoever has an officer rank hears it (#266)
    cooldown  = 5,        -- seconds before the same word from the same sender alerts again
}

local WORDS_TAG = "GOSWORDS1"   -- the first field of a watch-word string (copy and paste on the settings page)

-- Heard in every client, next to the client's own words: a guild speaks English as often as not.
local OFFICER_WORDS_EN = { "officer", "officers" }

function Mentions:Initialize()
    GuildOS.db.mentions = GuildOS.db.mentions or {}
    for k, v in pairs(self.DEFAULTS) do
        if GuildOS.db.mentions[k] == nil then
            GuildOS.db.mentions[k] = (type(v) == "table") and GuildOS:DeepCopy(v) or v
        end
    end
    GuildOS.db.mentions.log = GuildOS.db.mentions.log or {}
    self._cd = {}
    self._hinted = false
    self:_SetupHook()
    self:_RegisterTests()
end

-- Split on SEPARATORS (whitespace, punctuation, control chars) rather than on
-- "not alphanumeric": %w rejects every UTF-8 byte >= 0x80 in the C locale, so
-- the old "[^%w]" pass turned the accents in Jurgen/Bjorn/Jose into spaces on
-- the haystack while the needle kept them, and the match could never land.
-- Runs of separators collapse to one space so "mc-run" still matches "mc - run".
local function normWords(s)
    local t = s:lower():gsub("[%s%p%c]+", " ")
    t = t:gsub("^ ", ""):gsub(" $", "")
    return " " .. t .. " "
end

-- whole-word, case-insensitive: normalize BOTH sides the same way, then look
-- for " needle " inside " haystack ". Chinese has no spaces and Korean glues a particle to a
-- name ("철수님"), so there a word in their script is any stretch of the message (issue #106).
local NO_WORD_EDGES = { zhCN = true, zhTW = true, koKR = true }
local function hasWord(hay, needle)
    if not hay or not needle then return false end
    if NO_WORD_EDGES[GetLocale()] and needle:find("[\128-\255]") then
        return hay:lower():find(needle:lower(), 1, true) ~= nil
    end
    local n = normWords(needle)
    -- A needle made only of separators would normalize to "  " and match any
    -- haystack; treat it as matching nothing instead.
    if not n:find("[^ ]") then return false end
    return normWords(hay):find(n, 1, true) ~= nil
end

-- Pure: append `phrase` to `list`. Returns status ("ok"|"short"|"dupe") and the
-- normalized phrase. Dedupe is case-insensitive against what is already stored.
function Mentions:_AddWatchWord(list, phrase)
    local p = strtrim(tostring(phrase or "")):lower()
    if #p < MIN_WORD then return "short", p end
    for _, w in ipairs(list) do
        if tostring(w):lower() == p then return "dupe", p end
    end
    list[#list + 1] = p
    return "ok", p
end

-- Pure: remove `phrase` from `list`, matched the way _AddWatchWord stores it. Returns how
-- many came off (issue #59: the Settings screen removes through this, as the command does).
function Mentions:_RemoveWatchWord(list, phrase)
    local p = strtrim(tostring(phrase or "")):lower()
    local n = 0
    for i = #list, 1, -1 do
        if tostring(list[i]):lower() == p then
            table.remove(list, i)
            n = n + 1
        end
    end
    return n
end

function Mentions:_Match(msg, ownName, watchWords, watchOwn)
    if not msg then return nil end
    if watchOwn and ownName and ownName ~= "" and hasWord(msg, ownName) then return ownName end
    for _, w in ipairs(watchWords or {}) do
        if w and w ~= "" and hasWord(msg, w) then return w end
    end
    return nil
end

-- The words that call the officers (#266): English, then the client's own, comma-separated in one
-- locale line, without repeats.
function Mentions:_OfficerWords()
    local out, seen = {}, {}
    local function add(w)
        w = strtrim(tostring(w or "")):lower()
        if w ~= "" and not seen[w] then seen[w] = true; out[#out + 1] = w end
    end
    for _, w in ipairs(OFFICER_WORDS_EN) do add(w) end
    for w in tostring(L["officer, officers"]):gmatch("[^,]+") do add(w) end
    return out
end

-- Pure: the first of `words` that `msg` says as a whole word, or nil.
function Mentions:_OfficerCall(msg, words)
    if not msg then return nil end
    for _, w in ipairs(words or {}) do
        if hasWord(msg, w) then return w end
    end
    return nil
end

function Mentions:_Record(term, sender, msg)
    local cfg = GuildOS.db.mentions
    local log = cfg.log
    local ts = GetServerTime()
    table.insert(log, 1, { term = term, sender = sender, msg = msg, ts = ts })
    while #log > LOG_MAX do table.remove(log) end
    -- How often each word has fired, and when last: the settings page shows both on its chips.
    cfg.hits = cfg.hits or {}
    cfg.hits[term] = (cfg.hits[term] or 0) + 1
    cfg.lastHit = cfg.lastHit or {}
    cfg.lastHit[term] = ts
end

-- A temporary mute: alerts stop until the time passes (or Unmute). Nothing is logged while muted.
function Mentions:Mute(seconds)
    local cfg = GuildOS.db.mentions
    if cfg then cfg.muteUntil = GetServerTime() + seconds end
end

function Mentions:Unmute()
    local cfg = GuildOS.db.mentions
    if cfg then cfg.muteUntil = nil end
end

-- The time a mute ends, while one is running; nil otherwise.
function Mentions:MutedUntil()
    local cfg = GuildOS.db.mentions
    local t = cfg and cfg.muteUntil
    if t and GetServerTime() < t then return t end
    return nil
end

-- Pure: the short names of the characters linked to `me` (its short name) in `links`, as the guild's
-- alt links are kept (alt -> main). A main gives its alts; an alt gives its main and the main's other
-- alts. `me` itself is left out, and the list is sorted.
function Mentions:_LinkedNames(me, links)
    local function short(k)
        k = tostring(k or "")
        return k:match("^([^-]+)") or k
    end
    me = short(me)
    links = links or {}
    local main = me
    for key, m in pairs(links) do
        if short(key) == me then main = short(m); break end
    end
    local out, seen = {}, { [me] = true }
    local function add(n)
        if n ~= "" and not seen[n] then seen[n] = true; out[#out + 1] = n end
    end
    add(main)
    for key, m in pairs(links) do
        if short(m) == main then add(short(key)) end
    end
    table.sort(out)
    return out
end

-- Pure: the watch-words of `list` as one string: the tag, then each word after a semicolon.
function Mentions:_ExportWords(list)
    local parts = { WORDS_TAG }
    for _, w in ipairs(list or {}) do
        parts[#parts + 1] = (tostring(w):gsub(";", ""))
    end
    return table.concat(parts, ";")
end

-- Pure: adds the words of a string from _ExportWords to `list`, one at a time through _AddWatchWord.
-- Returns the counts { added, dupe, short }, or nil when the text is not a watch-word string.
function Mentions:_ImportWords(list, text)
    local counts = { added = 0, dupe = 0, short = 0 }
    local tagged = false
    for part in tostring(text or ""):gmatch("[^;]+") do
        if not tagged then
            if strtrim(part) ~= WORDS_TAG then return nil end
            tagged = true
        else
            local st = self:_AddWatchWord(list, part)
            if st == "ok" then counts.added = counts.added + 1
            elseif st == "dupe" then counts.dupe = counts.dupe + 1
            else counts.short = counts.short + 1 end
        end
    end
    if not tagged then return nil end
    return counts
end

-- A sample alert, to hear the sound and see the line without waiting for a mention.
function Mentions:TestAlert()
    local cfg = GuildOS.db.mentions
    if not cfg then return end
    GuildOS:Print(string.format(L["|cffFFD700Mention|r (%s): %s: %s"], "test", "Test", L["This is a test alert."]))
    if cfg.sound and PlaySound then PlaySound(SOUNDKIT and SOUNDKIT.TELL_MESSAGE or 3081) end
end

function Mentions:_SetupHook()
    local f = CreateFrame("Frame")
    GuildOS.Compat.RegisterEvent(f, "CHAT_MSG_GUILD")
    GuildOS.Compat.RegisterEvent(f, "CHAT_MSG_OFFICER")
    f:SetScript("OnEvent", function(_, event, msg, author)
        if GuildOS.Compat.IsSecret(msg, author) then return end  -- chat in lockdown: nothing readable
        local cfg = GuildOS.db.mentions
        if not cfg or not cfg.enabled then return end
        if Mentions:MutedUntil() then return end   -- a temporary mute: nothing alerts until it ends
        if event == "CHAT_MSG_GUILD" and not cfg.guild then return end
        if event == "CHAT_MSG_OFFICER" and not cfg.officer then return end
        local me = GuildOS.Compat.PlayerName()
        local sender = author and (author:match("^([^-]+)") or author)
        if sender == me then return end     -- don't alert on your own messages
        -- Chat calls me by my first name; on WoW: Forever `me` also carries the surname (issue #26).
        local term = Mentions:_Match(msg, me:match("^%S+") or me, cfg.watchWords, cfg.ownName)
        -- A call for the officers (#266), in guild chat only: officer chat is read by officers already.
        if not term and event == "CHAT_MSG_GUILD" and cfg.officerCall and GuildOS:IsOfficer() then
            term = Mentions:_OfficerCall(msg, Mentions:_OfficerWords())
        end
        if not term then return end
        -- per (sender+term) cooldown so one burst doesn't spam
        local key = (sender or "?") .. "|" .. term
        if Mentions._cd[key] then return end
        Mentions._cd[key] = true
        GuildOS.Compat.After(cfg.cooldown or 5, function() Mentions._cd[key] = nil end)
        Mentions:_Record(term, sender, msg)
        GuildOS:Print(string.format(L["|cffFFD700Mention|r (%s): %s: %s"], term, sender or "?", msg))
        if cfg.sound and PlaySound then PlaySound(SOUNDKIT and SOUNDKIT.TELL_MESSAGE or 3081) end
        -- Own-name matching is on by default, so a player called Tank/Ally/Lol would get
        -- alerted on normal guild chatter with no idea where it came from. Point at the
        -- off switch once per session (flag set first, so later alerts stay quiet).
        if not Mentions._hinted then
            Mentions._hinted = true
            GuildOS:Print(string.format(L["Tip: turn these off in %s > %s > %s, or with /outlawos mentions off."],
                L["Settings"], L["Chat and alerts"], L["Mentions"]))
        end
    end)
end

function Mentions:_RegisterTests()
    if not GuildOS.SelfTest then return end
    local S = GuildOS.SelfTest
    S:Register("mentions.ownname", function()
        if Mentions:_Match("hey Bob can you inv?", "Bob", {}, true) ~= "Bob" then return false, "own name" end
        if Mentions:_Match("Bobby says hi", "Bob", {}, true) ~= nil then return false, "whole-word only" end
        return true
    end)
    S:Register("mentions.watchword", function()
        if Mentions:_Match("who wants to run SP?", "X", { "sp" }, false) ~= "sp" then return false, "watch-word" end
        return true
    end)
    S:Register("mentions.no_own_when_off", function()
        if Mentions:_Match("hey Bob", "Bob", {}, false) ~= nil then return false, "ownName off => nil" end
        return true
    end)
    S:Register("mentions.case_insensitive", function()
        if Mentions:_Match("HEY BOB", "bob", {}, true) ~= "bob" then return false, "case" end
        return true
    end)
    S:Register("mentions.punctuation_needle", function()
        -- Both sides normalize the same way, so an apostrophe/hyphen in the
        -- watch-word still lands (it used to be a guaranteed silent no-op).
        if Mentions:_Match("anyone for Kel'Thuzad?", "X", { "kel'thuzad" }, false) ~= "kel'thuzad" then
            return false, "apostrophe"
        end
        if Mentions:_Match("lf1m mc-run", "X", { "mc-run" }, false) ~= "mc-run" then
            return false, "hyphen"
        end
        -- Whole-word matching must not regress.
        if Mentions:_Match("Bobby says hi", "Bob", {}, true) ~= nil then return false, "Bobby is not Bob" end
        -- A needle of pure punctuation must match nothing, not everything.
        if Mentions:_Match("hello there", "X", { "!!!" }, false) ~= nil then return false, "punct-only needle" end
        return true
    end)
    S:Register("mentions.high_bytes", function()
        -- "Jose" with an accented e: \195\169 must survive on BOTH sides.
        local jose = "Jos\195\169"
        if Mentions:_Match("hey " .. jose .. " inv?", jose, {}, true) ~= jose then return false, "accented own name" end
        return true
    end)
    S:Register("mentions.linked_names", function()
        local links = { Alt1 = "Main", Alt2 = "Main-Realm" }
        local got = Mentions:_LinkedNames("Alt1", links)
        if #got ~= 2 or got[1] ~= "Alt2" or got[2] ~= "Main" then return false, "alt sees main and sibling" end
        got = Mentions:_LinkedNames("Main", links)
        if #got ~= 2 or got[1] ~= "Alt1" or got[2] ~= "Alt2" then return false, "main sees its alts" end
        return true
    end)
    S:Register("mentions.words_round_trip", function()
        local list = { "need heals", "vic" }
        local text = Mentions:_ExportWords(list)
        if text ~= "GOSWORDS1;need heals;vic" then return false, "export" end
        local into = {}
        local counts = Mentions:_ImportWords(into, text .. ";vic;ab")
        if not counts or counts.added ~= 2 or counts.dupe ~= 1 or counts.short ~= 1 then return false, "import counts" end
        if Mentions:_ImportWords({}, "not a list") ~= nil then return false, "untagged text refused" end
        return true
    end)
    S:Register("mentions.add_watchword", function()
        local list = {}
        local st, norm = Mentions:_AddWatchWord(list, "need heals")
        if st ~= "ok" or norm ~= "need heals" then return false, "phrase not kept whole" end
        if #list ~= 1 then return false, "not stored" end
        st = Mentions:_AddWatchWord(list, "NEED HEALS")
        if st ~= "dupe" or #list ~= 1 then return false, "case-insensitive dedupe" end
        st = Mentions:_AddWatchWord(list, "a")
        if st ~= "short" or #list ~= 1 then return false, "min length" end
        return true
    end)
end

-- The last mentions, to chat: `/outlawos mentions` and the Mentions settings' button (#142).
function Mentions:PrintLog()
    local cfg = GuildOS.db.mentions
    if not cfg then return end
    local log = cfg.log or {}
    GuildOS:Print(L["--- Recent mentions ---"])
    if #log == 0 then GuildOS:Print(L["(none)"]) end
    for i = 1, math.min(#log, 15) do
        local e = log[i]
        GuildOS:Print(string.format("|cff888888%s|r %s: %s", GuildOS:DateText(e.ts or 0, " %H:%M"), e.sender or "?", e.msg or ""))
    end
end

function Mentions:HandleCommand(args)
    local cfg = GuildOS.db.mentions
    if not cfg then return end
    local sub = args[1]
    if sub == "on" then cfg.enabled = true; GuildOS:Print(L["Mentions |cff4CFF4Con|r."])
    elseif sub == "off" then cfg.enabled = false; GuildOS:Print(L["Mentions |cffFF4444off|r."])
    elseif sub == "ownname" and (args[2] == "on" or args[2] == "off") then
        cfg.ownName = (args[2] == "on")
        GuildOS:Print(L["Own-name alerts: "] .. (cfg.ownName and L["|cff4CFF4CON|r"] or L["|cffFF4444OFF|r"]))
    elseif sub == "sound" and (args[2] == "on" or args[2] == "off") then
        cfg.sound = (args[2] == "on")
        GuildOS:Print(L["Mention sound: "] .. (cfg.sound and L["|cff4CFF4CON|r"] or L["|cffFF4444OFF|r"]))
    elseif sub == "list" then
        GuildOS:Print(L["--- Watch-words ---"])
        if #cfg.watchWords == 0 then GuildOS:Print(L["(none)"]) end
        for i = 1, #cfg.watchWords do
            GuildOS:Print("  |cffFFFFFF" .. tostring(cfg.watchWords[i]) .. "|r")
        end
    elseif sub == "add" and args[2] then
        -- Keep the whole phrase: "add need heals" is two words, not "need".
        local phrase = table.concat(args, " ", 2, #args)
        local status, norm = Mentions:_AddWatchWord(cfg.watchWords, phrase)
        if status == "ok" then
            GuildOS:Print(L["Watch-word added: |cffFFFFFF"] .. norm .. "|r")
        elseif status == "short" then
            GuildOS:Print(L["Watch-words must be at least 3 characters."])
        else
            GuildOS:Print(L["Already watching: |cffFFFFFF"] .. norm .. "|r")
        end
    elseif sub == "remove" and args[2] then
        local t = strtrim(table.concat(args, " ", 2, #args)):lower()
        Mentions:_RemoveWatchWord(cfg.watchWords, t)
        GuildOS:Print(L["Watch-word removed: |cffFFFFFF"] .. t .. "|r")
    elseif sub == "clearwords" then
        cfg.watchWords = {}; GuildOS:Print(L["Watch-words cleared."])
    else
        -- default: print the recent log
        self:PrintLog()
        GuildOS:Print(L["Usage: /outlawos mentions <on|off|add|remove|list|clearwords|ownname|sound> [word|on|off]"])
    end
end
