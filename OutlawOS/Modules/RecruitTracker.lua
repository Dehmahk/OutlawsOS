----------------------------------------------------------------------
-- Guild OS - Applicant tracker
-- What the officers do with a join request once it is in the list: its stage, a claim so two officers do
-- not whisper the same person, officer notes, and a new-recruit checklist. Shared with every officer over
-- SyncService (domain "recruit"). The record is one revision per applicant: the newest wins for the stage,
-- the claim and the checklist. Notes only ever add, so they are merged by id and none is lost to a race.
-- Every rule is here; UI/JoinRequests.lua draws the controls and calls these.
----------------------------------------------------------------------
local RT = {}
GuildOS.RecruitTracker = RT

-- Stages an officer sets. "New" is no stage at all; "Invited" and "Declined" come from the request itself.
RT.STAGES = { contacted = true, trial = true, joined = true }
RT.STAGE_ORDER = { "contacted", "trial", "joined" }
-- The new-recruit checklist, in the order it is done.
RT.CHECKS = { "invite", "welcome", "raid", "checkin", "download" }
RT.MAX_NOTES = 20
RT.MAX_NOTE = 120

local listeners = {}

local function now() return GetServerTime() end
local function me() return GuildOS.Compat.PlayerName() or "" end
local function store()
    GuildOS.db.recruitTracker = GuildOS.db.recruitTracker or {}
    return GuildOS.db.recruitTracker
end
local function changed()
    for _, fn in ipairs(listeners) do GuildOS:SafeCall(fn) end
end

function RT:Listen(fn) listeners[#listeners + 1] = fn end
function RT:Get(id) return store()[id] end

-- An officer may change the tracker: the same rule as deciding a request.
function RT:CanEdit()
    return GuildOS.JoinRequests ~= nil and GuildOS.JoinRequests:CanDecide()
end

local function ensure(id)
    local rec = store()[id]
    if not rec then
        rec = { notes = {}, checklist = {} }
        store()[id] = rec
    end
    return rec
end

----------------------------------------------------------------------
-- Clean what arrives: a player's word from another officer is still text of any shape.
----------------------------------------------------------------------
local function cleanStage(v)
    return (type(v) == "string" and RT.STAGES[v]) and v or nil
end

local function cleanClaim(v)
    if type(v) ~= "table" or type(v.by) ~= "string" or v.by == "" then return nil end
    return { by = v.by:sub(1, 48), at = tonumber(v.at) or 0 }
end

local function cleanChecklist(v)
    local out = {}
    if type(v) == "table" then
        for _, key in ipairs(RT.CHECKS) do
            if v[key] then out[key] = true end
        end
    end
    return out
end

local function cleanNote(n)
    if type(n) ~= "table" or type(n.id) ~= "string" or n.id == "" or #n.id > 40 then return nil end
    return {
        id = n.id,
        by = tostring(n.by or ""):sub(1, 48),
        at = tonumber(n.at) or 0,
        text = tostring(n.text or ""):sub(1, RT.MAX_NOTE),
    }
end

-- Adds the notes the record does not have yet, keeps them in time order, and keeps the newest MAX_NOTES.
local function mergeNotes(rec, incoming)
    local seen = {}
    for _, n in ipairs(rec.notes) do seen[n.id] = true end
    for _, raw in ipairs(incoming or {}) do
        local n = cleanNote(raw)
        if n and not seen[n.id] then
            rec.notes[#rec.notes + 1] = n
            seen[n.id] = true
        end
    end
    table.sort(rec.notes, function(a, b)
        if a.at ~= b.at then return a.at < b.at end
        return a.id < b.id
    end)
    while #rec.notes > RT.MAX_NOTES do table.remove(rec.notes, 1) end
end

----------------------------------------------------------------------
-- Sending: one envelope per change, carrying the whole record, at a revision newer than any this client
-- has seen for the applicant (the clock keeps it ahead of officers whose counters are behind).
----------------------------------------------------------------------
function RT:_Publish(id, rec)
    local SS = GuildOS.SyncService
    if not SS then return end
    local rev = math.max(SS:GetRevision("recruit", id) + 1, now())
    SS:SetRevision("recruit", id, rev)
    SS:Publish("recruit", "set", {
        id = id,
        rec = { stage = rec.stage, claim = rec.claim, checklist = rec.checklist, notes = rec.notes },
    }, { rev = rev })
end

-- Applies a change made here, then tells the other officers and the open list.
local function commit(id, rec)
    rec.by, rec.at = me(), now()
    RT:_Publish(id, rec)
    changed()
end

----------------------------------------------------------------------
-- Changes an officer makes
----------------------------------------------------------------------
-- stage: "contacted", "trial", "joined", or nil for New.
function RT:SetStage(id, stage)
    if not self:CanEdit() or not id then return false end
    if stage ~= nil and not self.STAGES[stage] then return false end
    local rec = ensure(id)
    rec.stage = stage
    commit(id, rec)
    return true
end

-- Claims the applicant for this officer. Someone else's claim stands until they release it.
function RT:Claim(id)
    if not self:CanEdit() or not id then return false, nil end
    local rec = ensure(id)
    if rec.claim and rec.claim.by ~= me() then return false, rec.claim.by end
    rec.claim = { by = me(), at = now() }
    commit(id, rec)
    return true
end

-- Gives the claim up. Only the officer who holds it can.
function RT:Release(id)
    if not self:CanEdit() or not id then return false end
    local rec = ensure(id)
    if not rec.claim or rec.claim.by ~= me() then return false end
    rec.claim = nil
    commit(id, rec)
    return true
end

-- Adds an officer's note. Empty text is refused; a note is cut to MAX_NOTE.
function RT:AddNote(id, text)
    if not self:CanEdit() or not id then return false end
    text = tostring(text or ""):gsub("^%s+", ""):gsub("%s+$", "")
    if text == "" then return false end
    local rec = ensure(id)
    rec.notes[#rec.notes + 1] = {
        id = now() .. "-" .. math.random(100000, 999999),
        by = me(), at = now(), text = text:sub(1, self.MAX_NOTE),
    }
    while #rec.notes > self.MAX_NOTES do table.remove(rec.notes, 1) end
    commit(id, rec)
    return true
end

function RT:ToggleCheck(id, key)
    if not self:CanEdit() or not id then return false end
    local valid = false
    for _, k in ipairs(self.CHECKS) do if k == key then valid = true end end
    if not valid then return false end
    local rec = ensure(id)
    rec.checklist[key] = (not rec.checklist[key]) or nil
    commit(id, rec)
    return true
end

-- How many of the checklist are done, out of how many there are.
function RT:CheckProgress(id)
    local rec = store()[id]
    local done = 0
    for _, key in ipairs(self.CHECKS) do
        if rec and rec.checklist and rec.checklist[key] then done = done + 1 end
    end
    return done, #self.CHECKS
end

----------------------------------------------------------------------
-- Receiving: another officer's record. Only officers can send this domain (SyncService checks it).
----------------------------------------------------------------------
function RT:OnSync(env, sender)
    local d = env.data
    if env.act ~= "set" or type(d) ~= "table" or type(d.id) ~= "string" or d.id == "" or #d.id > 40 then return end
    if type(d.rec) ~= "table" then return end
    local rec = ensure(d.id)
    -- Notes only ever add, whatever the revision: a note from an older record still counts.
    mergeNotes(rec, d.rec.notes)
    local SS = GuildOS.SyncService
    if SS:ShouldApply("recruit", d.id, env.rev) then
        rec.stage = cleanStage(d.rec.stage)
        rec.claim = cleanClaim(d.rec.claim)
        rec.checklist = cleanChecklist(d.rec.checklist)
        if env.rev then SS:SetRevision("recruit", d.id, env.rev) end
    end
    changed()
end

function RT:Initialize()
    if self._started then return end
    self._started = true
    if GuildOS.SyncService then
        GuildOS.SyncService:On("recruit", function(env, sender) RT:OnSync(env, sender) end)
    end
end
