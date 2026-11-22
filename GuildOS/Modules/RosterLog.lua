----------------------------------------------------------------------
-- Guild OS - Roster Log (guild audit trail)
-- Captures join/leave/kick/promote/demote (with actor) from system
-- messages; synced officer-authoritative (domain "audit"); absorbs the
-- old GuildManager action log. Cold-login backfill is a tracked follow-up.
----------------------------------------------------------------------
local RosterLog = {}
GuildOS.RosterLog = RosterLog

local CAP = 1000
local MAX_AGE = 90 * 86400
local BACKFILL_N = 25   -- cold-sync re-broadcast is capped to the last N events

function RosterLog:Initialize()
    GuildOS.db.rosterLog = GuildOS.db.rosterLog or { events = {} }
    GuildOS.db.rosterLog.events = GuildOS.db.rosterLog.events or {}
    if GuildOS.SyncService then
        GuildOS.SyncService:On("audit", function(env) RosterLog:OnSync(env) end)
    end
    self:_MigrateManagementLog()
    self:_SetupDetection()
    self:Prune()
    self:_DedupeJoins()   -- EKO patch
    self:_RegisterTests()
end

----------------------------------------------------------------------
-- Pure helpers (deterministic; unit-tested via /gos selftest)
----------------------------------------------------------------------
-- Who an event is about: the short name, except on retail, where a guild spans connected realms
-- and two members can share a name: there it is the whole key, a name without a realm on this
-- client's. Officers on different realms then file the same event under the same id (issue #184).
function RosterLog:_NormShort(name)
    if not name or name == "" then return name end
    if GuildOS.Client and GuildOS.Client.isRetail then return GuildOS:KeyOfRosterName(name) end
    return name:match("^([^-]+)") or name
end

function RosterLog:_EventId(action, target, author, ts)
    local bucket = math.floor((ts or 0) / 5)
    return string.format("%s|%s|%s|%d", tostring(action), tostring(target or ""),
        tostring(author or ""), bucket)
end

-- Each message read through GuildOS:MatchFormat, which takes "%s" and German's numbered
-- "%1$s" alike and hands the arguments back by number, whatever order the language says
-- them in (#160).
function RosterLog:_ParseSystem(msg)
    if not msg then return nil end
    msg = strtrim(msg)
    -- join: ERR_GUILD_JOIN_S = "%s has joined the guild."
    local a = GuildOS:MatchFormat(msg, ERR_GUILD_JOIN_S)
    if a and a[1] then return { action = "join", target = self:_NormShort(a[1]) } end
    -- leave: ERR_GUILD_LEAVE_S = "%s has left the guild."
    a = GuildOS:MatchFormat(msg, ERR_GUILD_LEAVE_S)
    if a and a[1] then return { action = "leave", target = self:_NormShort(a[1]) } end
    -- kick: ERR_GUILD_REMOVE_SS = "%s has been kicked out of the guild by %s."  (target, actor)
    a = GuildOS:MatchFormat(msg, ERR_GUILD_REMOVE_SS)
    if a and a[1] and a[2] then
        return { action = "kick", target = self:_NormShort(a[1]), author = self:_NormShort(a[2]) }
    end
    -- promote: ERR_GUILD_PROMOTE_SSS = "%s has promoted %s to %s."  (actor, target, rank)
    a = GuildOS:MatchFormat(msg, ERR_GUILD_PROMOTE_SSS)
    if a and a[1] and a[2] then
        return { action = "promote", target = self:_NormShort(a[2]), author = self:_NormShort(a[1]), detail = a[3] }
    end
    -- demote: ERR_GUILD_DEMOTE_SSS = "%s has demoted %s to %s."  (actor, target, rank)
    a = GuildOS:MatchFormat(msg, ERR_GUILD_DEMOTE_SSS)
    if a and a[1] and a[2] then
        return { action = "demote", target = self:_NormShort(a[2]), author = self:_NormShort(a[1]), detail = a[3] }
    end
    return nil
end

function RosterLog:_Insert(evt, store)
    store = store or (GuildOS.db.rosterLog and GuildOS.db.rosterLog.events)
    if not store or not evt then return false end
    evt.timestamp = evt.timestamp or GetServerTime()
    evt.id = evt.id or self:_EventId(evt.action, evt.target, evt.author, evt.timestamp)
    -- EKO patch: a join or leave has no author in the game's line, so two clients (or one client a
    -- second apart) filed it twice. The same join/leave of the same person within 10 minutes is one
    -- event; a copy that knows who invited them fills that in.
    if evt.action == "join" or evt.action == "leave" then
        for i = 1, #store do
            local e = store[i]
            if e.action == evt.action and e.target == evt.target and math.abs((e.timestamp or 0) - evt.timestamp) < 600 then
                if evt.author and not e.author then e.author = evt.author; return true end
                return false
            end
        end
    end
    for i = 1, #store do
        if store[i].id == evt.id then return false end   -- dedup
    end
    store[#store + 1] = evt
    while #store > CAP do table.remove(store, 1) end
    return true
end

function RosterLog:Prune(now, store)
    store = store or (GuildOS.db.rosterLog and GuildOS.db.rosterLog.events)
    if not store then return 0 end
    now = now or GetServerTime()
    local removed = 0
    for i = #store, 1, -1 do
        if (store[i].timestamp or 0) < now - MAX_AGE then
            table.remove(store, i); removed = removed + 1
        end
    end
    return removed
end

-- EKO patch: fold the doubled joins/leaves (the same person within 10 minutes), keeping an author if
-- either copy had one. One pass, oldest first. Run at start-up and whenever the log is read, so a copy
-- that arrives later (another officer's sync) or a store switched after start-up is folded too.
function RosterLog:_DedupeJoins(store)
    store = store or (GuildOS.db and GuildOS.db.rosterLog and GuildOS.db.rosterLog.events)
    if not store then return 0 end
    local order = {}
    for i = 1, #store do order[i] = i end
    table.sort(order, function(a, b) return (store[a].timestamp or 0) < (store[b].timestamp or 0) end)
    local kept, drop, n = {}, {}, 0
    for _, i in ipairs(order) do
        local e = store[i]
        if e.action == "join" or e.action == "leave" then
            local k = tostring(e.action) .. "|" .. tostring(e.target)
            local o = kept[k]
            if o and (e.timestamp or 0) - (o.timestamp or 0) < 600 then
                o.author = o.author or e.author
                drop[i] = true
                n = n + 1
            else
                kept[k] = e
            end
        end
    end
    if n > 0 then
        for i = #store, 1, -1 do if drop[i] then table.remove(store, i) end end
    end
    return n
end

function RosterLog:GetLog(store)
    store = store or (GuildOS.db.rosterLog and GuildOS.db.rosterLog.events) or {}
    self:_DedupeJoins(store)   -- EKO patch
    local out = {}
    for i = #store, 1, -1 do out[#out + 1] = store[i] end
    -- EKO patch: newest first by time, so an older event that synced in late sits where it happened.
    table.sort(out, function(a, b) return (a.timestamp or 0) > (b.timestamp or 0) end)
    return out
end

-- Tally join/leave/kick events strictly after `since` (a server timestamp).
-- Used to feed the login digest with audit counts.
function RosterLog:CountsSince(since, store)
    store = store or (GuildOS.db.rosterLog and GuildOS.db.rosterLog.events) or {}
    local c = { join = 0, leave = 0, kick = 0 }
    for _, e in ipairs(store) do
        if (e.timestamp or 0) > (since or 0) and c[e.action] ~= nil then
            c[e.action] = c[e.action] + 1
        end
    end
    return c
end

-- Pure: the most recent up-to-N events (chronological order). Bounds the
-- cold-sync backfill so a late officer converges on the tail of the log
-- instead of us re-broadcasting the whole history every login.
function RosterLog:_Recent(store, n)
    store = store or (GuildOS.db.rosterLog and GuildOS.db.rosterLog.events) or {}
    n = n or BACKFILL_N
    local out = {}
    local first = math.max(1, #store - n + 1)
    for i = first, #store do
        out[#out + 1] = store[i]
    end
    return out
end

function RosterLog:_MigrateManagementLog()
    if GuildOS.db.rosterLog.migrated then return end
    GuildOS.db.rosterLog.migrated = true
    local old = GuildOS.db.managementLog
    if type(old) == "table" then
        for _, e in ipairs(old) do
            self:_Insert({
                action = e.action, target = e.target, author = e.author,
                detail = e.detail, timestamp = e.timestamp,
            })
        end
    end
end

function RosterLog:Clear()
    if not GuildOS:IsOfficer() then return end
    GuildOS.db.rosterLog.events = {}
    self:Refresh()
end

function RosterLog:OnSync(env)
    if env.act == "add" and env.data and env.data.evt then
        if self:_Insert(env.data.evt) then self:Refresh() end
    end
end

----------------------------------------------------------------------
-- Recording + detection
----------------------------------------------------------------------
function RosterLog:Add(evt)
    local inserted = self:_Insert(evt)
    if inserted then
        self:_Publish(evt)     -- broadcasts to officers if we are one; no-op for members
        self:Refresh()
    end
    return inserted
end

function RosterLog:Record(action, target, author, detail)
    return self:Add({
        action = action, target = target and self:_NormShort(target) or nil,
        author = author and self:_NormShort(author) or nil, detail = detail,
        timestamp = GetServerTime(),
    })
end

function RosterLog:Refresh()
    if self.uiRefresh then GuildOS:SafeCall(self.uiRefresh) end
end

function RosterLog:_SetupDetection()
    self._ready = false
    GuildOS.Compat.After(8, function() RosterLog._ready = true end)
    local f = CreateFrame("Frame")
    GuildOS.Compat.RegisterEvent(f, "CHAT_MSG_SYSTEM")
    f:SetScript("OnEvent", function(_, _, msg)
        if GuildOS.Compat.IsSecret(msg) then return end  -- chat in lockdown: nothing readable
        if not RosterLog._ready then return end
        -- EKO patch: the game's "You have invited X..." line, as a second way to see an invite (the
        -- GuildInvite hook below is the first). Remembered 30 minutes, so their join is logged "by" this player.
        local text = strtrim(msg or "")
        local inv = ERR_GUILD_INVITE_S and GuildOS:MatchFormat(text, ERR_GUILD_INVITE_S)
        local invName = (inv and inv[1]) or text:match("^You have invited (.-) to join")
        if invName then
            RosterLog:_RememberInvite(invName)
            return
        end
        local evt = RosterLog:_ParseSystem(msg)
        if evt and evt.action == "join" and RosterLog._invited then
            local at = RosterLog._invited[evt.target]
            if at and GetServerTime() - at < 1800 then
                evt.author = RosterLog:_NormShort(GuildOS.Compat.PlayerName() or UnitName("player"))
                RosterLog._invited[evt.target] = nil
            end
        end
        if evt then RosterLog:Add(evt) end
        -- With the guild's switch for new members on, an officer's client asks for a fresh roster: the
        -- trial starts from the roster line, never from this one's name (#249).
        if evt and evt.action == "join" and GuildOS.TrialTracker then
            GuildOS:SafeCall(GuildOS.TrialTracker.OnJoin, GuildOS.TrialTracker, evt.target)
        end
        -- And whoever leaves or is removed leaves the roster it compares against: back, they are new.
        if evt and (evt.action == "leave" or evt.action == "kick") and GuildOS.TrialTracker then
            GuildOS:SafeCall(GuildOS.TrialTracker.OnLeave, GuildOS.TrialTracker, evt.target)
        end
    end)
end

-- EKO patch: who this player invited, by name, for 30 minutes. Fed by a hook on the game's own invite
-- (GuildInvite: /ginvite, the guild window, right-click Invite, any addon) and by the system line.
function RosterLog:_RememberInvite(name)
    if type(name) ~= "string" or name == "" then return end
    self._invited = self._invited or {}
    self._invited[self:_NormShort(name)] = GetServerTime()
end

if hooksecurefunc then
    if GuildInvite then
        hooksecurefunc("GuildInvite", function(name) RosterLog:_RememberInvite(name) end)
    end
    if C_GuildInfo and C_GuildInfo.Invite then
        hooksecurefunc(C_GuildInfo, "Invite", function(name) RosterLog:_RememberInvite(name) end)
    end
end

function RosterLog:_Publish(evt)
    if not GuildOS.SyncService or not GuildOS:IsOfficer() then return end
    -- broadcast; convergence is by id-dedup on receipt (no rev, no ACK).
    GuildOS.SyncService:Publish("audit", "add", { evt = evt })
end

-- Cold-sync backfill: re-broadcast the last BACKFILL_N audit events so an
-- officer offline when they were recorded fills the tail of the log on login.
-- The audit domain is append-only and id-deduped (no revision), so this is
-- idempotent: _Insert drops an event a peer already holds and inserts one it
-- missed. No revision is involved and none is bumped. Bounded by _Recent to
-- avoid dumping unbounded history. Officers only. Called from HandleRequest.
function RosterLog:Backfill()
    if not GuildOS.SyncService or not GuildOS:IsOfficer() then return end
    local recent = self:_Recent()
    for i = 1, #recent do
        self:_Publish(recent[i])
    end
end

----------------------------------------------------------------------
-- Self-tests
----------------------------------------------------------------------
function RosterLog:_RegisterTests()
    if not GuildOS.SelfTest then return end
    local S = GuildOS.SelfTest
    -- The names as this client files them: with the realm on retail (#184).
    local grefer, daniel = RosterLog:_NormShort("Grefer"), RosterLog:_NormShort("Daniel")
    S:Register("rosterlog.parse_join", function()
        local e = RosterLog:_ParseSystem("Grefer has joined the guild.")
        if not e or e.action ~= "join" or e.target ~= grefer then return false, "join" end
        return true
    end)
    S:Register("rosterlog.parse_kick", function()
        local e = RosterLog:_ParseSystem("Grefer has been kicked out of the guild by Daniel.")
        if not e or e.action ~= "kick" or e.target ~= grefer or e.author ~= daniel then return false, "kick" end
        return true
    end)
    S:Register("rosterlog.parse_promote", function()
        local e = RosterLog:_ParseSystem("Daniel has promoted Grefer to Officer.")
        if not e or e.action ~= "promote" or e.target ~= grefer or e.author ~= daniel then return false, "promote" end
        return true
    end)
    S:Register("rosterlog.dedup", function()
        local store = {}
        local a = RosterLog:_Insert({ action = "join", target = "X", timestamp = 100 }, store)
        local b = RosterLog:_Insert({ action = "join", target = "X", timestamp = 101 }, store)  -- same 5s bucket
        if not a or b or #store ~= 1 then return false, "dedup" end
        return true
    end)
    S:Register("rosterlog.prune", function()
        local store = { { action = "join", target = "Y", timestamp = 1, id = "y" } }
        local n = RosterLog:Prune(1 + MAX_AGE + 1, store)
        if n ~= 1 or #store ~= 0 then return false, "prune" end
        return true
    end)
    S:Register("rosterlog.counts", function()
        local store = { { action="join", timestamp=10 }, { action="kick", timestamp=20 }, { action="join", timestamp=5 } }
        local c = RosterLog:CountsSince(8, store)
        if c.join ~= 1 or c.kick ~= 1 then return false, "counts" end
        return true
    end)
    S:Register("rosterlog.recent_window", function()
        local store = {}
        for i = 1, 5 do store[i] = { action = "join", target = "P" .. i, timestamp = i, id = "e" .. i } end
        local out = RosterLog:_Recent(store, 3)
        if #out ~= 3 or out[1].id ~= "e3" or out[3].id ~= "e5" then
            return false, "should return the last 3 in order"
        end
        local few = RosterLog:_Recent({ { id = "z" } }, 3)
        if #few ~= 1 or few[1].id ~= "z" then return false, "fewer than N returns all" end
        if #RosterLog:_Recent({}, 3) ~= 0 then return false, "empty store" end
        return true
    end)
end
