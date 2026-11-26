----------------------------------------------------------------------
-- Guild OS - Online recruiters and officers, for characters with no guild
--
-- A recruiter or officer of Eastern Kingdoms Outlaws who runs Guild OS says they are online every
-- few minutes, on the realm bus (ChehulOnline): "ONL|name|guild|rank|at". Every client that hears
-- one keeps the newest ping per name and passes it on (the prefix is Relayable), so a character
-- with no guild, which never hears the guild channel, still learns who is online. A name counts as
-- online while its ping is fresher than ONLINE_SECONDS. The guildless screen reads the two lists.
--
-- A recruiter is the Herald rank in game (EKO.ROLE_RANK). An officer is a Leadership rank, except
-- Herald, so nobody is listed twice. The guild master has a line of their own, above the rest.
----------------------------------------------------------------------
local OL = {}
GuildOS.OnlineLeaders = OL

OL.PREFIX         = "ChehulOnline"
OL.GUILD          = "Eastern Kingdoms Outlaws"
OL.PING_INTERVAL  = 150     -- a ping every this many seconds, so two land inside ONLINE_SECONDS
OL.ONLINE_SECONDS = 360     -- a ping older than this is not online any more
OL.CLOCK_SKEW     = 60      -- a ping stamped this far ahead of our clock is refused

-- Officers by in-game rank, lowercase, as the Roster's Leadership group reads them.
OL.OFFICER_RANKS = {
    ["guild master"] = true, ["gm alt"] = true, ["co-guild master"] = true,
    ["officer"] = true, ["raid marshal"] = true,
}

local cache = {}      -- name -> { name, rank, at }
local listeners = {}

local function now() return GetServerTime and GetServerTime() or time() end
local function me() return GuildOS.Compat.PlayerName() or "" end

local function recruiterRank()
    local roles = GuildOS.EKO and GuildOS.EKO.ROLE_RANK
    return string.lower((roles and roles["Recruiter"]) or "Herald")
end

-- "guildmaster", "recruiter", "officer", or nil for any other rank.
function OL.KindOf(rank)
    if type(rank) ~= "string" then return nil end
    local r = string.lower(rank)
    if r == "guild master" then return "guildmaster" end
    if r == recruiterRank() then return "recruiter" end
    if OL.OFFICER_RANKS[r] then return "officer" end
    return nil
end

function OL:Listen(fn)
    if type(fn) == "function" then table.insert(listeners, fn) end
end

local function changed()
    for _, fn in ipairs(listeners) do GuildOS:SafeCall(fn) end
end

-- Our own ping, when we are a recruiter or an officer of the guild. Nothing is sent inside an instance.
function OL:Ping()
    local mesh = _G.ChehulMesh
    if not mesh or not IsInGuild() then return false end
    if IsInInstance and IsInInstance() then return false end
    local guild, rank = GetGuildInfo("player")
    if guild ~= self.GUILD or not self.KindOf(rank) then return false end
    local name = me()
    if name == "" then return false end
    local payload = table.concat({ "ONL", name, guild, string.lower(rank), tostring(now()) }, "|")
    mesh:Realm(self.PREFIX, payload, "ONL:" .. name, true)
    return true
end

-- Splits "a|b|c" into its fields.
local function fieldsOf(payload)
    local out = {}
    for field in string.gmatch(payload .. "|", "([^|]*)|") do out[#out + 1] = field end
    return out
end

local function onWire(payload)
    if type(payload) ~= "string" then return end
    local f = fieldsOf(payload)
    if f[1] ~= "ONL" or not f[2] or f[2] == "" then return end
    local name, guild, rank, at = f[2], f[3], f[4], tonumber(f[5])
    if guild ~= OL.GUILD or not at or not OL.KindOf(rank) then return end
    if at > now() + OL.CLOCK_SKEW then return end
    local old = cache[name]
    if old and old.at >= at then return end
    cache[name] = { name = name, rank = rank, at = at }
    changed()
end

-- Our own line, when we are a guild master, recruiter or officer of the guild. We know we are online,
-- so it needs no ping of our own to be heard.
local function selfEntry()
    if not IsInGuild() then return nil end
    local guild, rank = GetGuildInfo("player")
    if guild ~= OL.GUILD or not OL.KindOf(rank) then return nil end
    local name = me()
    if name == "" then return nil end
    return { name = name, rank = string.lower(rank), at = now() }
end

-- The online guild masters, recruiters and officers, each sorted by name. A ping that has gone stale
-- is dropped here. Your own line is listed when you qualify, so a preview shows your online status.
function OL:List()
    local t, mine = now(), me()
    local gms, recruiters, officers = {}, {}, {}
    local function add(row)
        local kind = self.KindOf(row.rank)
        if kind == "guildmaster" then gms[#gms + 1] = row
        elseif kind == "recruiter" then recruiters[#recruiters + 1] = row
        elseif kind == "officer" then officers[#officers + 1] = row end
    end
    for name, e in pairs(cache) do
        if t - e.at > self.ONLINE_SECONDS then
            cache[name] = nil
        elseif name ~= mine then
            add({ name = name, rank = e.rank, at = e.at })
        end
    end
    local own = selfEntry()
    if own then add(own) end
    local byName = function(a, b) return a.name < b.name end
    table.sort(gms, byName)
    table.sort(recruiters, byName)
    table.sort(officers, byName)
    return gms, recruiters, officers
end

function OL:Initialize()
    local mesh = _G.ChehulMesh
    if mesh and mesh.Register then
        mesh:Register(self.PREFIX, function(payload) GuildOS:SafeCall(onWire, payload) end)
    end
    if mesh and mesh.Relayable then mesh:Relayable(self.PREFIX) end
    if C_Timer and C_Timer.NewTicker then
        self._ticker = C_Timer.NewTicker(self.PING_INTERVAL, function() GuildOS:SafeCall(OL.Ping, OL) end)
        if C_Timer.After then
            C_Timer.After(10, function() GuildOS:SafeCall(OL.Ping, OL) end)
        end
    end
end
