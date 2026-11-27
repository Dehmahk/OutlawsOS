----------------------------------------------------------------------
-- Guild OS - JoinRequests (specs/071-o-recrutamento in guildos-web, "O pedido")
-- A character with no guild asks a guild to take it, and an officer of that guild invites or declines.
-- Both sides live here, over the prefix the gossip already owns:
--
--   CRQ|id|character|class|level|role|guild|note   the request, repeated every REPEAT_SECONDS while the
--                                                  player is online. The id makes a repeat harmless, and it
--                                                  is what delivery, presence and the answer all hang on
--   CRA|id|state|who[|reason|again]                the answer. officer and member say where it got to and
--                                                  do NOT stop the repetition; invited and declined end it.
--                                                  A decline may carry a preset reason and a reapply time
--                                                  (epoch seconds). An older client reads the first four
--   CRR|id|who                                     an officer took the request off the list. Over GUILD only:
--                                                  every officer's copy goes, and the player hears nothing
--   CRX|id|character                               the player takes the request back. Whispered by the player
--                                                  to the officer heard (else the contacts); an officer's client
--                                                  passes it on over GUILD. Nothing is answered. CRW is the
--                                                  gossip's whisper test, so the withdraw is not CRW
--
-- The guildless side keeps its queue in GuildOSDB.recruitOutbox[character] (account-wide: a guildless
-- character has no guild db worth the name) and writes the open ones to GuildOSDB.recruitOutboxWire on
-- logout, a GOSOUTB1 for the companion to take to the site. The guild's side keeps db.joinRequests[id],
-- fifty at most, and tells the site through the export's optional `joinRequests`.
--
-- Nothing here is ever said in a public channel, and nothing off the network is believed: names and
-- notes are inert, one line and cut by character; class, level and role are closed sets.
----------------------------------------------------------------------
local JR = {}
GuildOS.JoinRequests = JR

local Compat = GuildOS.Compat
local L = GuildOS.L

local PREFIX = "ChehulRecruit"

JR.REPEAT_SECONDS = 300        -- a request goes out again this often while the player is online
JR.MAX_OPEN       = 3          -- open requests one character may have
JR.EXPIRE_SECONDS = 14 * 86400 -- as on the site
JR.MAX_STORED     = 50         -- rows a guild's client keeps
JR.ONLINE_SECONDS = 360        -- a request heard this lately belongs to somebody online: the repeat is 300
JR.EXPIRE_WARN    = 3 * 86400  -- an officer's list flags a request this close to its expiry
JR.REAPPLY_MAX    = 90 * 86400 -- a reapply time further off than this is not believed

-- The preset reasons a decline may carry: the token goes on the wire, the text is the locale's.
JR.REASON_ORDER = { "notrecruiting", "level", "schedule", "full" }
JR.REASONS = {
    notrecruiting = "Not recruiting right now",
    level         = "Your level is below what we need right now",
    schedule      = "Your play times do not match ours",
    full          = "The guild is full right now",
}

-- The short questions on the request form. Their answers are packed into the note, the one free field the wire
-- has: a second one would make an older officer's client drop the request. max is the room each answer has.
JR.PROMPTS = {
    { key = "when", tag = "When", question = "When do you usually play?",      max = 36, example = "Weeknights after 8 pm" },
    { key = "main", tag = "Main", question = "Main or alt?",                   max = 12, example = "Main" },
    { key = "want", tag = "Want", question = "What do you want from a guild?", max = 48, example = "Raids, friendly people" },
}

local NOTE_MAX, NAME_MAX, WHO_MAX = 120, 48, 40
local KEEP_SECONDS = 30 * 86400    -- a closed entry of the player's own queue is forgotten after this
local ID_ALPHABET = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789"
local ANSWER = { officer = 2, member = 1 }        -- where a request got to; a better one is not taken back
local ROLES = { TANK = true, HEALER = true, DPS = true }
local SPEC_ROLE = { TANK = "TANK", HEALER = "HEALER", DAMAGER = "DPS" }

local function now() return GetServerTime() end

local function text(v, max)
    local GF = GuildOS.GuildFinder
    return GF and GF.Text(v, max) or nil
end

-- The id of a request made in the game: ten letters and digits.
local function validId(id) return type(id) == "string" and id:match("^%w+$") ~= nil and #id == 10 end

-- The id of a row, which may be the site's (a UUID): the rule Import:SiteJoinRequests applies.
local function validRowId(id) return type(id) == "string" and #id <= 40 and id:match("^[%w_%-]+$") ~= nil end

-- Messages dropped for a reason that would otherwise be silent, for the Audit panel to show; and how many
-- invites went and how many times the game's "You have invited X" line came back for one, because no real
-- client has been seen to say it yet.
local dropped = { name = 0, guild = 0, invites = 0, confirmed = 0 }
function JR:Stats()
    return { name = dropped.name, guild = dropped.guild, invites = dropped.invites, confirmed = dropped.confirmed }
end

-- Everything the Audit panel counts about requests: the rows open here, this character's own asking (the ones
-- still in its queue, and of those the ones somebody answered), and the numbers above.
function JR:Audit()
    local asked, delivered = 0, 0
    local box = GuildOSDB and GuildOSDB.recruitOutbox and GuildOSDB.recruitOutbox[Compat.PlayerName()] or {}
    for _, e in pairs(box) do
        asked = asked + 1
        if e.delivered or e.status == "invited" or e.status == "declined" then delivered = delivered + 1 end
    end
    return { open = self:OpenCount() + self:OpenCount("alliance"), asked = asked, delivered = delivered, invites = dropped.invites,
             confirmed = dropped.confirmed, dropped = { name = dropped.name, guild = dropped.guild } }
end

-- A request is relayed (and a closed one announced again) at most this often per row: the player repeats
-- every REPEAT_SECONDS, and a little less keeps one late timer from skipping a repetition.
JR.RELAY_GAP = 240
JR.INVITE_WAIT = 10   -- seconds the game has to say an invite went before the click is forgotten

local function classSet()
    if not JR._classes then
        JR._classes = {}
        for _, c in ipairs(GuildOS.Client.classes or {}) do JR._classes[c] = true end
    end
    return JR._classes
end

-- The three facts about a person that are a closed set or a number; anything else is absent.
local function facts(class, level, role)
    class = classSet()[class] and class or nil
    level = GuildOS.Finite(level)
    if not (level and level == math.floor(level) and level >= 1 and level <= 100) then level = nil end
    role = ROLES[role] and role or nil
    return class, level, role
end

-- Two spellings of one character: the game writes "Chehul Costa", people type the hyphen, and on
-- retail a sender may come with its realm.
local function sameName(a, b)
    a, b = a:lower():gsub("[%s%-]+", " "), b:lower():gsub("[%s%-]+", " ")
    return a == b or a:sub(1, #b + 1) == b .. " " or b:sub(1, #a + 1) == a .. " "
end

-- The same name, whole: space and hyphen are one thing and case is none, and nothing else is.
local function sameWhole(a, b)
    return a:lower():gsub("[%s%-]+", " ") == b:lower():gsub("[%s%-]+", " ")
end

-- The confirmation of an invite names the person whole: "Ana" is not "Ana Lima" and "Ana" on this realm is
-- not "Ana-Gallywix". Space and hyphen are one thing, case is none. On retail the realm is compared when
-- both sides have one: the game leaves out this character's own.
local function sameInvited(a, b)
    a, b = a:lower():gsub("[%s%-]+", " "), b:lower():gsub("[%s%-]+", " ")
    if a == b then return true end
    if not GuildOS.Client.isRetail then return false end
    local nameA, realmA = a:match("^(%S+) (.+)$")
    local nameB, realmB = b:match("^(%S+) (.+)$")
    if realmA and realmB then return false end   -- both with a realm, and they are not the same
    return (nameA or a) == (nameB or b)
end

-- A guild name as the digest spells it, and with no case: the site and the game do not agree on it.
local function guildKey(name) return (tostring(name or ""):gsub("[,:]", " "):lower()) end

-- In a guild, and on that guild's db: a character that joined or changed guild this session has not
-- resolved to the new one yet (#150), and what it wrote would land in the wrong place.
local function inGuild() return IsInGuild() and GuildOS:IsOnGuildDB() end

local function tell(fn, ...)
    if fn then pcall(fn, ...) end
end

-- The screens that show requests ask to hear when one changes. A screen that errors costs the others nothing.
local listeners = {}
function JR:Listen(fn) listeners[#listeners + 1] = fn end
local function changed()
    for _, fn in ipairs(listeners) do pcall(fn) end
end

----------------------------------------------------------------------
-- The queue of a character with no guild
----------------------------------------------------------------------
local function outbox()
    GuildOSDB.recruitOutbox = GuildOSDB.recruitOutbox or {}
    local me = Compat.PlayerName()
    GuildOSDB.recruitOutbox[me] = GuildOSDB.recruitOutbox[me] or {}
    return GuildOSDB.recruitOutbox[me]
end

-- Expires what is past fourteen days, forgets what closed long ago.
local function pruneOutbox()
    local box, n = outbox(), now()
    for id, e in pairs(box) do
        if e.status == "open" and e.at + JR.EXPIRE_SECONDS <= n then e.status = "expired" end
        if e.status ~= "open" and e.at + KEEP_SECONDS <= n then box[id] = nil end
    end
end

-- This character's requests, the latest first.
function JR:Outbox()
    pruneOutbox()
    local list = {}
    for _, e in pairs(outbox()) do list[#list + 1] = e end
    table.sort(list, function(a, b) if a.at ~= b.at then return a.at > b.at end return a.id < b.id end)
    return list
end

-- The latest request this character made of the guild whose ad is `ad`, or nil.
function JR:Latest(ad)
    for _, e in ipairs(self:Outbox()) do
        if e.key == (ad.u or ad.n) then return e end
    end
end

-- Where a request stands: "stored" (nobody has answered: kept here), "officer" or "member" (delivered,
-- and to whom), "invited", "declined", "expired" or "withdrawn"; then when it was answered, and for a decline its
-- reason and reapply time. Nil for a request that
-- is not this character's.
function JR:Status(id)
    pruneOutbox()
    local e = outbox()[id]
    if not e then return nil end
    if e.status ~= "open" then return e.status, e.by, e.answeredAt, e.reason, e.again end
    return e.delivered or "stored", e.by
end

-- How many of this character's requests are open, to any guild.
function JR:OpenMine()
    pruneOutbox()
    local n = 0
    for _, e in pairs(outbox()) do if e.status == "open" then n = n + 1 end end
    return n
end

-- The seconds before "Ask again" may send this request once more: a REPEAT_SECONDS gap from the last time it went
-- out, which is the gap the repeat keeps too. Nil for a request that is not open.
function JR:AskWait(e)
    if not e or e.status ~= "open" then return nil end
    return math.max(0, (e.askedAt or e.at) + self.REPEAT_SECONDS - now())
end

-- Asks the guild again now, if the gap allows. Returns how many whispers went, or nil and why.
function JR:AskAgain(id)
    local e = outbox()[id]
    if not e or e.status ~= "open" then return nil, "closed" end
    if (self:AskWait(e) or 0) > 0 then return nil, "wait" end
    return self:Deliver(e)
end

-- Whether this session can reach the guild from the game at all: a whisper of ours has been seen to arrive.
function JR:CanReach()
    local gossip = GuildOS.ChehulGossip
    return gossip ~= nil and gossip:CanWhisper() == true
end

local function payloadOf(e)
    local parts = { "CRQ", e.id, e.character, e.class or "", e.level or "", e.role or "", e.guild, e.note or "" }
    -- An alliance application is the same request with its kind on the end: nine fields, not eight.
    if e.kind == "alliance" then parts[#parts + 1] = "alliance" end
    return table.concat(parts, "|")
end

-- One round for one request: to the officer heard from that guild, else a member, and the contact names
-- the ad carries when nobody was heard or the one heard has not answered the round before (an addon that
-- predates this message never will). Nothing is tried where this client's whisper has not been seen to arrive.
function JR:Deliver(e)
    e.askedAt = now()
    local gossip = GuildOS.ChehulGossip
    if not (gossip and gossip:CanWhisper()) then return 0 end
    local payload, sent = payloadOf(e), 0
    local peer = gossip:PeerFor(e.guild)
    local silent = (e.rounds or 0) >= 1 and not e.delivered
    if peer then
        e.rounds = (e.rounds or 0) + 1
        if gossip:Whisper(peer, payload) then sent = 1 end
    end
    if not peer or silent then
        for _, name in ipairs(e.ct or {}) do
            if gossip:Whisper(name, payload) then sent = sent + 1 end
        end
    end
    return sent
end

-- A character in a guild asks nobody: whatever is left of the queue goes.
local function clearOutbox()
    GuildOSDB.recruitOutbox = GuildOSDB.recruitOutbox or {}
    GuildOSDB.recruitOutbox[Compat.PlayerName()] = nil
end

function JR:Tick()
    if IsInGuild() then clearOutbox(); changed(); return end
    pruneOutbox()
    for _, e in pairs(outbox()) do
        if e.status == "open" then self:Deliver(e)
        elseif e.status == "withdrawn" and not e.withdrawSent then self:SendWithdraw(e) end
    end
end

-- The player takes a request back. It closes here at once, and the guild is told as soon as one of its officers
-- can be reached: Tick keeps trying until one has it.
function JR:Withdraw(id)
    local e = outbox()[id]
    if not e or e.status ~= "open" then return false end
    e.status, e.answeredAt = "withdrawn", now()
    self:SendWithdraw(e)
    changed()
    return true
end

-- One round of a withdrawal: to the officer heard from that guild, and to the contacts the ad names, so that one of
-- the officers who reads it is among them. Returns how many whispers went.
function JR:SendWithdraw(e)
    local gossip = GuildOS.ChehulGossip
    if not (gossip and gossip:CanWhisper()) then return 0 end
    local payload = table.concat({ "CRX", e.id, e.character or "" }, "|")
    local names = {}
    local peer = gossip:PeerFor(e.guild)
    if peer then names[#names + 1] = peer end
    for _, name in ipairs(e.ct or {}) do names[#names + 1] = name end
    local sent, seen = 0, {}
    for _, name in ipairs(names) do
        if not seen[name] then
            seen[name] = true
            if gossip:Whisper(name, payload) then sent = sent + 1 end
        end
    end
    if sent > 0 then e.withdrawSent = true end
    return sent
end

-- How a request was answered, in one line: as it arrives, and at login if it came while the player was away.
-- Nil for an answer that is not a decision.
function JR:AnswerText(e)
    if e.kind == "alliance" then
        if e.status == "invited" then return string.format(L["Your alliance application to %s was accepted."], e.guild) end
        return string.format(L["%s declined your alliance application."], e.guild)
    end
    if e.status == "invited" then return string.format(L["Invite from %s"], e.guild) end
    if e.status ~= "declined" then return nil end
    local line
    if e.reason and self.REASONS[e.reason] then
        line = string.format(L["%s declined your request: %s."], e.guild, L[self.REASONS[e.reason]])
    else
        line = string.format(L["%s thanked you, but is not opening spots right now"], e.guild)
    end
    if e.again then
        local sep = line:sub(-1) == "." and " " or ". "
        line = line .. sep .. string.format(L["You can ask again from %s."], date("%d %b %Y", e.again))
    end
    return line
end

-- An answer that came while this character was not in the game is said once, at login. Told is kept on the request,
-- so the same answer is not said twice.
function JR:Greet()
    if IsInGuild() then return end
    pruneOutbox()
    for _, e in pairs(outbox()) do
        if not e.told and e.answeredAt and (e.status == "invited" or e.status == "declined") then
            e.told = true
            local line = self:AnswerText(e)
            if line then GuildOS:Print(line) end
        end
    end
end

-- The form's answers as the note: "When: weeknights · Main: Main · Want: raids". Each answer is cut to its room and a
-- blank one is left out; nil when all are blank. The separator is a middle dot, since the wire has no room for a bar.
function JR:PackNote(answers)
    local parts = {}
    for _, p in ipairs(self.PROMPTS) do
        local v = text(answers and answers[p.key], p.max)
        if v then parts[#parts + 1] = p.tag .. ": " .. v end
    end
    if #parts == 0 then return nil end
    return table.concat(parts, " \194\183 ")
end

-- Who is asking: this character's name, class token, level and the role it prefers; what the game
-- will not say is absent.
function JR:Me()
    local _, classFile = UnitClass("player")
    local role
    local prefers = GuildOS:GetMyRoles()
    for _, r in ipairs({ "TANK", "HEALER", "DPS" }) do
        if prefers[r] then role = r; break end
    end
    -- Nobody sets a preferred role before joining a guild: the spec the character is playing says it.
    if not role then
        local _, _, specRole = Compat.SpecOf("player")
        role = SPEC_ROLE[specRole]
    end
    local class, level
    class, level, role = facts(classFile, UnitLevel("player"), role)
    -- On retail the realm travels with the name: a namesake on a connected realm is somebody else.
    local name = Compat.PlayerName()
    if GuildOS.Client.isRetail and name and name ~= "" then name = GuildOS:KeyOfRosterName(name) or name end
    return { character = name, class = class, level = level, role = role }
end

-- Who may apply to the Outlaws' alliance: a guild master, or a Co-Guild Master, of a guild other than the Outlaws.
-- Returns true and the applicant's guild name, or false and why: "no-guild", "outlaws" or "rank".
local OUTLAWS_NAME = "Eastern Kingdoms Outlaws"
function JR:CanApplyAlliance()
    if not IsInGuild() then return false, "no-guild" end
    local guild, rankName, rankIndex = GetGuildInfo("player")
    if not guild or guild == "" then return false, "no-guild" end
    if guildKey(guild) == guildKey(OUTLAWS_NAME) then return false, "outlaws" end
    if rankIndex ~= 0 and rankName ~= "Co-Guild Master" then return false, "rank" end
    return true, guild
end

-- Asks `ad`'s guild to take this character. Returns the request, or nil and why: "in-guild", "no-ad",
-- "too-many" (three are open), "already" (this guild has one open).
function JR:Send(ad, note, kind)
    kind = kind == "alliance" and "alliance" or nil
    if kind == "alliance" then
        -- The applicant's guild rides in the note: an extra field would make older officers' clients drop it.
        local ok, detail = self:CanApplyAlliance()
        if not ok then return nil, detail end
        note = "Guild: " .. detail
    elseif IsInGuild() then return nil, "in-guild" end
    -- The slug is the site's name for the guild and a card heard by CR2 has none: the name stands in.
    if type(ad) ~= "table" or not ad.n then return nil, "no-ad" end
    local key = ad.u or ad.n
    pruneOutbox()
    local box, open = outbox(), 0
    for _, e in pairs(box) do
        if e.status == "open" then
            open = open + 1
            if e.key == key and e.kind == kind then return nil, "already" end
        end
    end
    if open >= self.MAX_OPEN then return nil, "too-many" end

    local id
    repeat
        id = ""
        for _ = 1, 10 do
            local at = math.random(1, #ID_ALPHABET)
            id = id .. ID_ALPHABET:sub(at, at)
        end
    until not box[id]

    local who = self:Me()
    local contacts = {}
    for _, name in ipairs(ad.ct or {}) do
        if #contacts < 3 and text(name, NAME_MAX) then contacts[#contacts + 1] = text(name, NAME_MAX) end
    end
    local e = {
        id = id, character = who.character, class = who.class, level = who.level, role = who.role,
        note = text(note, NOTE_MAX), at = now(), guild = ad.n, slug = ad.u, key = key, ct = contacts, status = "open", kind = kind,
    }
    box[id] = e
    self:Deliver(e)
    changed()
    return e
end

-- The queue as the companion takes it, on logout: only what is still open. Nothing when there is none.
function JR:WriteWire()
    local requests, n = {}, now()
    for _, entries in pairs(GuildOSDB.recruitOutbox or {}) do
        for _, e in pairs(entries) do
            if e.status == "open" and e.slug and e.at + self.EXPIRE_SECONDS > n then
                requests[#requests + 1] = { id = e.id, slug = e.slug, character = e.character, class = e.class,
                    level = e.level, role = e.role, note = e.note, at = e.at }
            end
        end
    end
    if #requests == 0 then GuildOSDB.recruitOutboxWire = nil; return end
    table.sort(requests, function(a, b) if a.at ~= b.at then return a.at < b.at end return a.id < b.id end)
    local wire = GuildOS.Companion:Pack("GOSOUTB1:", { fmt = "GOSOUTB1", v = 1, requests = requests })
    if wire then GuildOSDB.recruitOutboxWire = wire end
end

----------------------------------------------------------------------
-- The guild's rows
----------------------------------------------------------------------
local function store()
    -- Off the guild's own db a write would land in the db of another guild, or of none: it lands nowhere.
    if not GuildOS:IsOnGuildDB() then return {} end
    GuildOS.db.joinRequests = GuildOS.db.joinRequests or {}
    return GuildOS.db.joinRequests
end

-- Drops what is not a row (a damaged save must not break a screen) and expires what is past its days.
local function expireRows()
    local n, rows = now(), store()
    for id, r in pairs(rows) do
        if type(r) ~= "table" or type(r.id) ~= "string" or type(r.character) ~= "string" or type(r.at) ~= "number" then
            rows[id] = nil
        elseif r.status == "open" and r.at + JR.EXPIRE_SECONDS <= n then
            r.status = "expired"
        end
    end
end

-- Room for one more row: drops the oldest closed one past the cap. False when all fifty are open.
local function makeRoom()
    local rows, count, oldest = store(), 0, nil
    for _, r in pairs(rows) do
        count = count + 1
        if r.status ~= "open" and (not oldest or r.at < oldest.at) then oldest = r end
    end
    if count < JR.MAX_STORED then return true end
    if not oldest then return false end
    rows[oldest.id] = nil
    return true
end

-- The row whose request was made in the game under `id`: the site's row keeps it as `gameId`.
local function byGameId(id, character)
    for _, r in pairs(store()) do
        -- An id says nothing about whose it is: the name must still be the row's.
        if r.gameId == id and sameWhole(r.character, character) then return r end
    end
end

local function openFor(character)
    for _, r in pairs(store()) do
        if r.status == "open" and sameName(r.character, character) then return r end
    end
end

-- Which list a row belongs to: an alliance application (the Alliance tab) or a join request (Recruitment).
local function kindOf(r) return r.kind == "alliance" and "alliance" or "guild" end

-- The rows of one list, open ones first, each group the latest first. `which` is "alliance" for the
-- alliance applications; anything else is the join requests.
function JR:List(which)
    expireRows()
    local want = which == "alliance" and "alliance" or "guild"
    local list = {}
    for _, r in pairs(store()) do
        if r.status ~= "removed" and kindOf(r) == want then list[#list + 1] = r end
    end
    table.sort(list, function(a, b)
        if (a.status == "open") ~= (b.status == "open") then return a.status == "open" end
        if a.at ~= b.at then return a.at > b.at end
        return a.id < b.id
    end)
    return list
end

function JR:OpenCount(which)
    expireRows()
    local want = which == "alliance" and "alliance" or "guild"
    local n = 0
    for _, r in pairs(store()) do if r.status == "open" and kindOf(r) == want then n = n + 1 end end
    return n
end

function JR:Prune()
    expireRows()
    pruneOutbox()
end

local function me() return Compat.PlayerName() end

local function toGuild(payload)
    local mesh = _G.ChehulMesh
    if mesh then mesh:Guild(PREFIX, payload) end
end

-- The answer as it goes over the wire. A decline's reason and reapply time ride after the four fields an older
-- client reads, so an older client still reads the answer.
local function answerPayload(id, state, who, reason, again)
    local parts = { "CRA", id, state, who }
    if reason or again then parts[5], parts[6] = reason or "", again and tostring(again) or "" end
    return table.concat(parts, "|")
end

-- A reapply time, off the wire or from an officer's menu: a whole moment ahead, within REAPPLY_MAX. Else nothing.
local function reapplyAt(v)
    local t = GuildOS.Finite(tonumber(v))
    if not t or t ~= math.floor(t) then return nil end
    if t <= now() or t > now() + JR.REAPPLY_MAX then return nil end
    return t
end

-- What a row tells a person who asks about it: officer or member for an open one, the decision (with its reason
-- and reapply time) for a closed one, nothing for one that expired or was withdrawn. And who says so.
local function answerOf(r)
    local state = r.status
    if state == "open" then return GuildOS:IsOfficer() and "officer" or "member", me() end
    if state == "invited" or state == "declined" then return state, r.decidedBy or me(), r.reason, r.again end
    return nil
end

-- `id` is the one the person knows the request by: its own, when it was made in the game.
local function answerTo(r, name, id)
    local gossip = GuildOS.ChehulGossip
    local state, by, reason, again = answerOf(r)
    if state and gossip then gossip:Whisper(name, answerPayload(id or r.id, state, by, reason, again)) end
end

-- A closed row whose request is heard again: a client that was offline at the decision, or the person
-- who never heard it, would otherwise make a new open row of it. An officer, or whoever decided, says it
-- again over GUILD and to the person, at most once per repetition.
local function announceAgain(r)
    if r.status ~= "invited" and r.status ~= "declined" then return end
    if not (GuildOS:IsOfficer() or r.decidedBy == me()) then return end
    if now() - (r.toldAt or 0) < JR.REPEAT_SECONDS then return end
    r.toldAt = now()
    local by = r.decidedBy or me()
    toGuild(answerPayload(r.id, r.status, by, r.reason, r.again))
    local gossip = GuildOS.ChehulGossip
    if gossip then gossip:Whisper(r.character, answerPayload(r.gameId or r.id, r.status, by, r.reason, r.again)) end
end

-- A CRQ off the network. Whispered by the player it is the player's own, and answered; over GUILD it is
-- a guild-mate passing one on, and is kept and nothing more. Either way it says the player is online.
function JR:OnCRQ(payload, sender, dist)
    if type(sender) ~= "string" or not inGuild() then return end
    local mine = GetGuildInfo("player")
    if not mine or mine == "" then return end
    local f = { strsplit("|", payload) }
    if (#f ~= 8 and #f ~= 9) or f[1] ~= "CRQ" or not validId(f[2]) then return end
    local kind = f[9] == "alliance" and "alliance" or nil
    if guildKey(f[7]) ~= guildKey(mine) then dropped.guild = dropped.guild + 1; return end
    local character = text(f[3], NAME_MAX)
    if not character then return end
    local direct = dist ~= "GUILD"
    if direct and not sameName(character, sender) then dropped.name = dropped.name + 1; return end
    local bans = GuildOS.BanList
    if bans and (bans:IsBanned(character) or (direct and bans:IsBanned(sender))) then return end

    local rows = store()
    -- A request the person made on the site and then in the game lives under the site's id, with the game's
    -- as `gameId`: when it was decided with the person offline, the id that comes back finds the closed row
    -- here, not an open one made new.
    local r = rows[f[2]] or byGameId(f[2], character)
    if r then
        if r.status == "open" then r.seen = now() end
    else
        -- One open request per person, however many ids. When one is open already (the person asked on
        -- the site, then in the game) the game's id is kept on it, so the answer finds its way back.
        local twin = openFor(character)
        if twin then
            twin.seen, twin.gameId = now(), f[2]
            r = twin
        else
            if not makeRoom() then return end
            local class, level, role = facts(f[4], f[5], f[6])
            r = { id = f[2], character = character, class = class, level = level, role = role, note = text(f[8], NOTE_MAX),
                  at = now(), seen = now(), status = "open", source = "addon", relayedBy = (not direct) and sender or nil, kind = kind }
            rows[r.id] = r
            if GuildOS:IsOfficer() then tell(GuildOS.JoinRequestsHeard, GuildOS, r) end
        end
    end
    if direct then
        answerTo(r, sender, f[2])
        if r.status == "open" and now() - (r.relayedAt or 0) >= JR.RELAY_GAP then
            r.relayedAt = now()
            toGuild(payload)
        end
    else
        announceAgain(r)
    end
    changed()
end

-- A CRA off the network. For a request this character made it is the answer; for a row in the guild's
-- db it is a decision, and only an officer's word over GUILD is one.
function JR:OnCRA(payload, sender, dist)
    local _, id, state, who, reason, again = strsplit("|", payload)
    if not validRowId(id) or not (ANSWER[state] or state == "invited" or state == "declined") then return end
    who = text(who, WHO_MAX) or ""
    reason = self.REASONS[reason] and reason or nil
    again = reapplyAt(again)

    local e = (not IsInGuild()) and outbox()[id] or nil
    if e then
        if e.status ~= "open" then return end
        if ANSWER[state] then
            if (ANSWER[state] or 0) >= (ANSWER[e.delivered] or 0) then e.delivered, e.by = state, who end
        else
            e.status, e.by, e.answeredAt = state, who, now()
            e.reason, e.again, e.told = reason, again, true
            local line = self:AnswerText(e)
            if line then GuildOS:Print(line) end
        end
        changed()
        return
    end

    if dist ~= "GUILD" or ANSWER[state] or not inGuild() then return end
    -- The channel and the rank both: the check reads the roster, and a row the roster could not vouch for
    -- stays open until the site's own block closes it.
    local gossip = GuildOS.ChehulGossip
    if not (gossip and gossip:IsOfficerSender(sender)) then return end
    local r = store()[id]
    if r and r.status == "open" then
        r.status, r.decidedBy, r.decidedAt = state, who, now()
        r.reason, r.again = reason, again
        changed()
    end
end

-- A CRR off GUILD: an officer took a request off the list. Only an officer's word counts, as for a decision.
-- A request this client never heard of becomes the mark, so a repeat of it does not come back as a new row.
function JR:OnCRR(payload, sender, dist)
    local _, id, who = strsplit("|", payload)
    if dist ~= "GUILD" or not validRowId(id) or not inGuild() then return end
    local gossip = GuildOS.ChehulGossip
    if not (gossip and gossip:IsOfficerSender(sender)) then return end
    local rows = store()
    local r = rows[id]
    if r and r.status == "removed" then return end
    if not r then
        if not makeRoom() then return end
        r = { id = id, character = "", at = now() }
        rows[id] = r
    end
    r.status, r.removedBy, r.removedAt = "removed", text(who, WHO_MAX) or "", now()
    changed()
end

-- A CRX: the player takes a request back. Whispered by the player it is theirs, and the name must be the sender's.
-- Over GUILD it is an officer's client passing it on, and only an officer's word counts, as for CRR. A request this
-- client never heard of becomes a mark, so a late copy of it cannot open a new row. Only the client that heard it
-- straight from the player passes it on, so the copies do not go round.
function JR:OnCRX(payload, sender, dist)
    local _, id, character = strsplit("|", payload)
    if not validRowId(id) or not inGuild() then return end
    character = text(character, NAME_MAX)
    if not character then return end
    local direct = dist ~= "GUILD"
    if direct then
        if not sameName(character, sender) then dropped.name = dropped.name + 1; return end
    else
        local gossip = GuildOS.ChehulGossip
        if not (gossip and gossip:IsOfficerSender(sender)) then return end
    end

    local rows = store()
    local r = rows[id] or byGameId(id, character)
    if r then
        if r.status ~= "open" or not sameName(r.character, character) then return end
        r.status, r.withdrawnAt = "withdrawn", now()
    else
        if not makeRoom() then return end
        r = { id = id, character = character, at = now(), status = "withdrawn", withdrawnAt = now() }
        rows[id] = r
    end
    if direct and GuildOS:IsOfficer() then toGuild(payload) end
    changed()
end

-- Whether this character may close a request. The game's right to invite can reach below the guild's
-- officers: that person invites, and closes nothing.
function JR:CanDecide()
    return inGuild() and GuildOS:IsOfficer()
end

-- Whether this character may close this request. An alliance application is an ambassador's to accept
-- or decline; every other request stays with the officers.
function JR:CanDecideRow(r)
    if r and r.kind == "alliance" then
        return inGuild() and GuildOS.Alliance ~= nil and GuildOS.Alliance:IsMyAmbassador()
    end
    return self:CanDecide()
end

-- An officer's decision, once: the first one stands. It is told to the guild, and to the player if heard
-- just now, who would otherwise wait for the next repetition. A refusal says why, from the click on Decline or
-- from the game's line after an invite. A decline may carry a preset reason (JR.REASONS) and a reapply time;
-- anything else is dropped rather than sent.
function JR:Decide(id, status, reason, again)
    if status ~= "invited" and status ~= "declined" then return false end
    local heard = store()[id]
    if not self:CanDecideRow(heard) then
        GuildOS:Print(heard and heard.kind == "alliance"
            and L["Only an ambassador can answer an alliance application."]
            or L["Only an officer can close a request: this one stays open."])
        return false
    end
    expireRows()
    local r = store()[id]
    if not r or r.status ~= "open" then
        GuildOS:Print(L["This request is already closed."])
        return false
    end
    -- Accepting an alliance application grants the applicant read-only observer access. If the grant
    -- fails (not an ambassador, the list is full) the row stays open.
    if r.kind == "alliance" and status == "invited" then
        local ok, err = GuildOS.AllianceObserver:Grant(r.character)
        if not ok then
            GuildOS:Print(err or L["Could not grant access."])
            return false
        end
    end
    local declined = status == "declined"
    reason = declined and self.REASONS[reason] and reason or nil
    again = declined and reapplyAt(again) or nil
    r.status, r.decidedBy, r.decidedAt = status, me(), now()
    r.reason, r.again = reason, again
    toGuild(answerPayload(id, status, me(), reason, again))
    local gossip = GuildOS.ChehulGossip
    if gossip and (r.source == "addon" or r.gameId) and now() - (r.seen or 0) < self.ONLINE_SECONDS then
        gossip:Whisper(r.character, answerPayload(r.gameId or id, status, me(), reason, again))
    end
    changed()
    return true
end

-- Takes a request off every officer's list, open or closed. Remove is not an answer: the player is not told,
-- and Decline is the one that tells them. It is for a request that should not be on the list at all (a
-- duplicate, a test, a spam line). The row stays as a mark, so a repeat of the request from the game does not
-- make it new again; the other officers' clients take it off too, over GUILD (OnCRR).
function JR:Remove(id)
    local r = store()[id]
    if not r or r.status == "removed" or not self:CanDecideRow(r) then return false end
    r.status, r.removedBy, r.removedAt = "removed", me(), now()
    toGuild(table.concat({ "CRR", id, me() }, "|"))
    changed()
    return true
end

-- Whether Invite would act: the request is open, this player may invite, and the person is there to be
-- invited. A request from the game is repeated by whoever is online, so one not heard for six minutes is
-- offline; the site cannot know, so a request from there is always live.
function JR:CanInvite(id)
    local r = inGuild() and store()[id] or nil
    -- An alliance application is accepted as an observer, never invited into the guild.
    if r and r.kind == "alliance" then return false end
    if not r or r.status ~= "open" or not CanGuildInvite() then return false end
    if r.source == "site" then return true end
    return now() - (r.seen or 0) < self.ONLINE_SECONDS
end

local pending = {}   -- [id] = when the invite was sent: waiting for the game to say it went

-- The game's guild invite, with the name as the game gave it (retail: cut to the plain one on this
-- character's realm). Only ever called from a button's OnClick, and there is no path here that invites by
-- itself. On WoW: Forever the game lets no addon invite: the /ginvite line waits in the chat box for the
-- player's Enter (Compat.GuildInvite, #256). The row
-- is not closed here: the game's own line does that (see onSystem), so a person who is offline, or a
-- name the game refused, leaves it open for another try.
function JR:Invite(id)
    if not self:CanInvite(id) then return false end
    local Import = GuildOS.CompanionImport
    local name = store()[id].character
    pending[id] = now()
    dropped.invites = dropped.invites + 1
    GuildOS.Compat.GuildInvite(Import and Import.PlainName(name) or name)
    return true
end

-- EKO: Approve, an officer's. The game lets no addon invite on WoW: Forever, so it puts /ginvite <name>
-- in the chat box for the officer's own Enter. The row closes as invited when the game says the invite
-- went (onSystem), so an offline player or a refused name leaves it open. The officer gets a minute to
-- press Enter instead of INVITE_WAIT's ten seconds (the stamp is set 50 seconds ahead).
function JR:Approve(id)
    local asked = store()[id]
    if asked and asked.kind == "alliance" then return self:Decide(id, "invited") end
    if not self:CanDecide() then
        GuildOS:Print(L["Only an officer can close a request: this one stays open."])
        return false
    end
    local r = store()[id]
    if not r or r.status ~= "open" then return false end
    local Import = GuildOS.CompanionImport
    local name = Import and Import.PlainName(r.character) or r.character
    if GuildOS.Compat.AddonMayInvite() and self:CanInvite(id) then return self:Invite(id) end
    pending[id] = now() + 50
    if ChatFrame_OpenChat then ChatFrame_OpenChat("/ginvite " .. name) end
    if now() - (r.seen or 0) >= self.ONLINE_SECONDS and r.source ~= "site" then
        GuildOS:Print(name .. " looks offline. Press Enter to try; if they're not on, the request stays open.")
    end
    return true
end

-- "You have invited X to join your guild.": the only word the game gives that an invite went. A line the
-- client keeps secret, one for another name or one that comes late closes nothing: the error is always
-- toward not claiming what did not happen (the ingest closes the row as joined when the roster has them).
local function onSystem(_, _, msg)
    if next(pending) == nil or type(msg) ~= "string" or Compat.IsSecret(msg) or not ERR_GUILD_INVITE_S then return end
    local args = GuildOS:MatchFormat(msg, ERR_GUILD_INVITE_S)
    local name = args and args[1]
    if not name then return end
    dropped.confirmed = dropped.confirmed + 1
    local n = now()
    for id, at in pairs(pending) do
        local r = store()[id]
        if n - at > JR.INVITE_WAIT or not r or r.status ~= "open" then
            pending[id] = nil
        elseif sameInvited(r.character, name) then
            pending[id] = nil
            JR:Decide(id, "invited")
        end
    end
end

----------------------------------------------------------------------
-- What the site knows (GOSGILD1.joinRequests) and what it is told (the export's joinRequests)
----------------------------------------------------------------------
local FROM_SITE = { invited = "invited", joined = "invited", declined = "declined", expired = "expired" }

-- Reads the block's requests into the rows: a new open one becomes a row, a decision made on Discord
-- closes the row it names, a closed one this client never had is not worth keeping. It runs at the start,
-- when the rank is not known yet, and again from the officers' start, when it is: so a new row waits as
-- `unheard` until an officer's client reads it, and the officer hears of it once, as of one from the game.
function JR:Refresh()
    local Import = GuildOS.CompanionImport
    local list = inGuild() and Import and Import.SiteJoinRequests and Import:SiteJoinRequests() or nil
    if not list then return end
    local rows = store()
    for _, s in ipairs(list) do
        local r = rows[s.id]
        if r then
            if r.status == "open" and FROM_SITE[s.status] then
                r.status = FROM_SITE[s.status]
                if r.status ~= "expired" then r.decidedBy = L["Discord"] end
            end
        elseif s.status == "open" and not openFor(s.character) and makeRoom() then
            local class, level, role = facts(s.class, s.level, s.role)
            rows[s.id] = { id = s.id, character = s.character, class = class, level = level, role = role, note = s.note,
                           at = s.at, status = "open", source = s.source, unheard = true }
        end
    end
    expireRows()
    if GuildOS:IsOfficer() then
        for _, r in pairs(rows) do
            if r.unheard then
                r.unheard = nil
                if r.status == "open" then tell(GuildOS.JoinRequestsHeard, GuildOS, r) end
            end
        end
    end
    changed()
end

-- The rows as the site's GoscompJoinRequest, nil with none. Expired ones are not told: the site has its
-- own clock for them.
function JR:ForExport()
    if GuildOS.Client.isAnniversary or not inGuild() then return nil end
    expireRows()
    local out = {}
    for _, r in pairs(store()) do
        if r.status == "open" or r.status == "invited" or r.status == "declined" then
            out[#out + 1] = { id = r.id, character = r.character, class = r.class, level = r.level, role = r.role,
                note = r.note, at = r.at, status = r.status, decidedBy = r.status ~= "open" and r.decidedBy or nil }
        end
    end
    if #out == 0 then return nil end
    table.sort(out, function(a, b) if a.at ~= b.at then return a.at < b.at end return a.id < b.id end)
    return out
end

----------------------------------------------------------------------
-- Start
----------------------------------------------------------------------
function JR:Initialize()
    if GuildOS.Client.isAnniversary or self._started then return end
    self._started = true
    local gossip = GuildOS.ChehulGossip
    if gossip and gossip.On then
        gossip:On("CRQ", function(payload, sender, dist) JR:OnCRQ(payload, sender, dist) end)
        gossip:On("CRA", function(payload, sender, dist) JR:OnCRA(payload, sender, dist) end)
        gossip:On("CRR", function(payload, sender, dist) JR:OnCRR(payload, sender, dist) end)
        gossip:On("CRX", function(payload, sender, dist) JR:OnCRX(payload, sender, dist) end)
    end
    Compat.NewTicker(self.REPEAT_SECONDS, function() GuildOS:SafeCall(JR.Tick, JR) end)
    Compat.After(3, function() GuildOS:SafeCall(JR.Greet, JR) end)

    -- Entering a guild ends the asking: the queue is cleared.
    local frame = CreateFrame("Frame")
    Compat.RegisterEvent(frame, "PLAYER_GUILD_UPDATE")
    frame:SetScript("OnEvent", function()
        GuildOS:SafeCall(function()
            if IsInGuild() then clearOutbox(); changed() end
        end)
    end)
    local chat = CreateFrame("Frame")
    Compat.RegisterEvent(chat, "CHAT_MSG_SYSTEM")
    chat:SetScript("OnEvent", function(...) GuildOS:SafeCall(onSystem, ...) end)

    if IsInGuild() then clearOutbox() end
    GuildOS:SafeCall(JR.Refresh, JR)
    pruneOutbox()
end
