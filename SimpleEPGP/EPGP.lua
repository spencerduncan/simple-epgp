local SimpleEPGP = LibStub("AceAddon-3.0"):GetAddon("SimpleEPGP")
local EPGP = SimpleEPGP:NewModule("EPGP", "AceEvent-3.0")

local floor = math.floor
local tonumber = tonumber
local tostring = tostring
local GetNumGuildMembers = GetNumGuildMembers
local GetGuildRosterInfo = GetGuildRosterInfo
-- GuildRoster() was removed in TBC Anniversary; use C_GuildInfo.GuildRoster() instead.
-- Fail early if neither exists — a silent no-op would let the addon "load" but silently
-- break all EP/GP commands (standings never populate, every lookup returns nil).
local GuildRoster = (C_GuildInfo and C_GuildInfo.GuildRoster) or GuildRoster
assert(GuildRoster, "SimpleEPGP: Neither C_GuildInfo.GuildRoster nor GuildRoster exists. The WoW API has changed — addon needs updating.")
local GuildRosterSetOfficerNote = GuildRosterSetOfficerNote
local IsInGuild = IsInGuild
local IsInRaid = IsInRaid
local GetNumGroupMembers = GetNumGroupMembers
local GetRaidRosterInfo = GetRaidRosterInfo
local time = time
local C_Timer = C_Timer

--- Normalize a player name to WoW canonical casing (first letter upper, rest lower).
-- Allows slash commands to be case-insensitive: "FLAUTAH", "flautah", "Flautah" all match.
local function NormalizeName(name)
    if not name then return name end
    return name:sub(1, 1):upper() .. name:sub(2):lower()
end

-- Cached standings table, rebuilt on GUILD_ROSTER_UPDATE
local standings = {}
-- Lookup table: name -> standings entry
local playerLookup = {}
-- Throttle GuildRoster() calls — server limits to 1 per 10 seconds
local lastRefresh = 0
local REFRESH_COOLDOWN = 10
-- Sync state: tracks whether we're using synced data from an officer
local syncedFromOfficer = false
local initialSyncDone = false  -- true after we've done the one-time auto-request

--------------------------------------------------------------------------------
-- External Players — SavedVariables-backed storage for pugs/allies/cross-realm
--------------------------------------------------------------------------------

--- Add an external player to the SavedVariables DB.
-- @param name Player name (will be normalized).
-- @param class WoW class token (e.g. "WARRIOR"). Must be a valid RAID_CLASS_COLORS key.
-- @return true on success, false with error message on failure.
function EPGP:AddExternalPlayer(name, class)
    if not name or name == "" then
        SimpleEPGP:Print("Cannot add external player: name is required.")
        return false
    end
    if not class or class == "" then
        SimpleEPGP:Print("Cannot add external player: class is required.")
        return false
    end

    local normalized = NormalizeName(name)
    local db = SimpleEPGP.db
    if not db then return false end

    if db.profile.external_players[normalized] then
        SimpleEPGP:Print(normalized .. " is already in the external player list.")
        return false
    end

    db.profile.external_players[normalized] = {
        class = class:upper(),
        ep = 0,
        gp = 0,
        modified_by = UnitName("player"),
        modified_at = time(),
    }

    -- Rebuild standings to include the new external player
    self:GUILD_ROSTER_UPDATE()
    return true
end

--- Remove an external player from the SavedVariables DB.
-- @param name Player name (will be normalized).
-- @return true on success, false if not found.
function EPGP:RemoveExternalPlayer(name)
    if not name or name == "" then
        SimpleEPGP:Print("Cannot remove external player: name is required.")
        return false
    end

    local normalized = NormalizeName(name)
    local db = SimpleEPGP.db
    if not db then return false end

    if not db.profile.external_players[normalized] then
        SimpleEPGP:Print(normalized .. " is not in the external player list.")
        return false
    end

    db.profile.external_players[normalized] = nil

    -- Rebuild standings to remove the external player
    self:GUILD_ROSTER_UPDATE()
    return true
end

--- Return the external_players table from SavedVariables.
-- @return table The external_players table (may be empty).
function EPGP:GetExternalPlayers()
    local db = SimpleEPGP.db
    if not db then return {} end
    return db.profile.external_players or {}
end

--- Check if a player name is in the external player DB.
-- @param name Player name (will be normalized).
-- @return true if the name exists in external_players, false otherwise.
function EPGP:IsExternalPlayer(name)
    if not name then return false end
    local normalized = NormalizeName(name)
    local db = SimpleEPGP.db
    if not db then return false end
    return db.profile.external_players[normalized] ~= nil
end

function EPGP:OnEnable()
    if not IsInGuild() then return end
    self:RegisterEvent("GUILD_ROSTER_UPDATE")

    -- Register comm callbacks for standings sync
    local Comms = SimpleEPGP:GetModule("Comms")

    -- Officers respond to sync requests from non-officers
    Comms:RegisterCallback("STANDINGS_REQUEST", function(sender)
        self:OnStandingsRequest(sender)
    end)

    -- Non-officers receive standings data from officers
    Comms:RegisterCallback("STANDINGS_SYNC", function(sender, data)
        self:OnStandingsSync(sender, data)
    end)

    -- Trigger initial roster load
    GuildRoster()
end

function EPGP:OnDisable()
    self:UnregisterAllEvents()
end

--- Request a guild roster refresh, throttled to once per 10 seconds.
function EPGP:RefreshRoster()
    local now = time()
    if now - lastRefresh >= REFRESH_COOLDOWN then
        lastRefresh = now
        GuildRoster()
    end
end

--- Event handler for GUILD_ROSTER_UPDATE.
-- Rebuilds the cached standings table from officer notes.
function EPGP:GUILD_ROSTER_UPDATE()
    local db = SimpleEPGP.db
    if not db then return end

    local Debug = SimpleEPGP:GetModule("Debug", true)

    local baseGP = db.profile.base_gp or 1
    local minEP = db.profile.min_ep or 0

    local newStandings = {}
    local newLookup = {}
    local numMembers = GetNumGuildMembers()

    for i = 1, numMembers do
        -- GetGuildRosterInfo returns: name(1), rankName(2), rankIndex(3), level(4),
        -- classDisplayName(5), zone(6), publicNote(7), officerNote(8), isOnline(9),
        -- status(10), class(11) — use position 11 for locale-independent class token
        local name, _, _, _, _, _, _, officerNote, _, _, class = GetGuildRosterInfo(i)
        if name then
            -- Strip realm suffix for consistency
            local shortName = name:match("^([^%-]+)") or name
            local ep, gp = self:ParseNote(officerNote or "")
            ep = ep or 0
            gp = gp or 0

            local effectiveGP = math.max(gp, 0) + baseGP
            local pr = 0
            if ep >= minEP and effectiveGP > 0 then
                pr = ep / effectiveGP
            end

            local entry = {
                name = shortName,
                fullName = name,
                class = class,
                ep = ep,
                gp = gp,
                pr = pr,
                rosterIndex = i,
            }
            newStandings[#newStandings + 1] = entry
            newLookup[shortName] = entry
        end
    end

    -- Merge external players into standings
    local externalPlayers = db.profile.external_players or {}
    for extName, extData in pairs(externalPlayers) do
        -- Skip if an external player name collides with a guild member
        if not newLookup[extName] then
            local ep = extData.ep or 0
            local gp = extData.gp or 0
            local effectiveGP = math.max(gp, 0) + baseGP
            local pr = 0
            if ep >= minEP and effectiveGP > 0 then
                pr = ep / effectiveGP
            end

            local entry = {
                name = extName,
                class = extData.class,
                ep = ep,
                gp = gp,
                pr = pr,
                isExternal = true,
                -- External players do NOT have rosterIndex
            }
            newStandings[#newStandings + 1] = entry
            newLookup[extName] = entry
        end
    end

    -- Sort by PR descending
    table.sort(newStandings, function(a, b)
        return a.pr > b.pr
    end)

    standings = newStandings
    playerLookup = newLookup

    if Debug then Debug:Log("EVENT", "GUILD_ROSTER_UPDATE", { members = #newStandings }) end

    -- Notify other modules that standings changed
    self:SendMessage("SEPGP_STANDINGS_UPDATED")

    -- One-time auto-sync: after the first roster update, check if we need
    -- to request standings from an officer. Only fires once per session,
    -- with a random delay (2-8s) to stagger requests when multiple
    -- non-officers log in simultaneously.
    if not initialSyncDone then
        initialSyncDone = true
        self:CheckNeedSync()
    end
end

--- Parse an officer note in "EP,GP" format.
-- @param note The officer note string.
-- @return ep, gp as numbers, or nil if the note doesn't match.
function EPGP:ParseNote(note)
    if not note then return nil end
    local epStr, gpStr = note:match("^(%d+),(%d+)$")
    if epStr then
        return tonumber(epStr), tonumber(gpStr)
    end
    return nil
end

--- Encode EP and GP values into an officer note string.
-- @param ep Effort points (number).
-- @param gp Gear points (number).
-- @return Encoded string "EP,GP".
function EPGP:EncodeNote(ep, gp)
    return tostring(floor(ep)) .. "," .. tostring(floor(gp))
end

--- Get the cached standings table (array of {name, class, ep, gp, pr}).
-- @return Array sorted by PR descending.
function EPGP:GetStandings()
    return standings
end

--- Look up a single player's info from the cache.
-- @param name Player name (without realm).
-- @return Standings entry table, or nil if not found.
function EPGP:GetPlayerInfo(name)
    return playerLookup[NormalizeName(name)]
end

--- Find a player's current roster index by name.
-- Roster indices shift when members join/leave, so always re-scan.
-- @param name Player name (without realm).
-- @return Roster index, or nil if not found.
local function FindRosterIndex(name)
    local normalized = NormalizeName(name)
    local numMembers = GetNumGuildMembers()
    for i = 1, numMembers do
        local rosterName = GetGuildRosterInfo(i)
        if rosterName then
            local shortName = rosterName:match("^([^%-]+)") or rosterName
            if shortName == normalized then
                return i
            end
        end
    end
    return nil
end

--- Modify a player's EP by a given amount.
-- Checks guild roster first, then falls back to external player DB.
-- @param name Player name.
-- @param amount EP to add (can be negative for penalties).
-- @param reason Optional reason string for the log.
function EPGP:ModifyEP(name, amount, reason)
    local Debug = SimpleEPGP:GetModule("Debug", true)
    if Debug then Debug:Log("EPGP", "ModifyEP", { player = name, amount = amount, reason = reason }) end

    if not self:CanEditNotes() then
        SimpleEPGP:Print("Cannot modify EP: you don't have officer note permissions.")
        return false
    end

    local index = FindRosterIndex(name)
    if not index then
        -- Not in guild roster — check external player DB
        local normalized = NormalizeName(name)
        local db = SimpleEPGP.db
        local extPlayer = db and db.profile.external_players[normalized]
        if extPlayer then
            local ep = (extPlayer.ep or 0) + amount
            if ep < 0 then ep = 0 end
            extPlayer.ep = ep
            extPlayer.modified_by = UnitName("player")
            extPlayer.modified_at = time()

            local Log = SimpleEPGP:GetModule("Log", true)
            if Log then
                Log:Add("EP", normalized, amount, nil, reason)
            end

            self:GUILD_ROSTER_UPDATE()
            self:BroadcastStandings()
            return true
        end

        SimpleEPGP:Print("Player " .. name .. " not found in guild roster or external player list.")
        return false
    end

    local _, _, _, _, _, _, _, officerNote = GetGuildRosterInfo(index)
    local ep, gp = self:ParseNote(officerNote or "")
    ep = (ep or 0) + amount
    gp = gp or 0

    -- EP cannot go below 0
    if ep < 0 then ep = 0 end

    local newNote = self:EncodeNote(ep, gp)
    GuildRosterSetOfficerNote(index, newNote)

    -- Log the change
    local Log = SimpleEPGP:GetModule("Log", true)
    if Log then
        Log:Add("EP", name, amount, nil, reason)
    end

    self:RefreshRoster()
    self:BroadcastStandings()
    return true
end

--- Modify a player's GP by a given amount.
-- Checks guild roster first, then falls back to external player DB.
-- @param name Player name.
-- @param amount GP to add (can be negative).
-- @param reason Optional reason string for the log.
function EPGP:ModifyGP(name, amount, reason)
    local Debug = SimpleEPGP:GetModule("Debug", true)
    if Debug then Debug:Log("EPGP", "ModifyGP", { player = name, amount = amount, reason = reason }) end

    if not self:CanEditNotes() then
        SimpleEPGP:Print("Cannot modify GP: you don't have officer note permissions.")
        return false
    end

    local index = FindRosterIndex(name)
    if not index then
        -- Not in guild roster — check external player DB
        local normalized = NormalizeName(name)
        local db = SimpleEPGP.db
        local extPlayer = db and db.profile.external_players[normalized]
        if extPlayer then
            local gp = (extPlayer.gp or 0) + amount
            if gp < 0 then gp = 0 end
            extPlayer.gp = gp
            extPlayer.modified_by = UnitName("player")
            extPlayer.modified_at = time()

            local Log = SimpleEPGP:GetModule("Log", true)
            if Log then
                Log:Add("GP", normalized, amount, nil, reason)
            end

            self:GUILD_ROSTER_UPDATE()
            self:BroadcastStandings()
            return true
        end

        SimpleEPGP:Print("Player " .. name .. " not found in guild roster or external player list.")
        return false
    end

    local _, _, _, _, _, _, _, officerNote = GetGuildRosterInfo(index)
    local ep, gp = self:ParseNote(officerNote or "")
    ep = ep or 0
    gp = (gp or 0) + amount

    -- GP cannot go below 0
    if gp < 0 then gp = 0 end

    local newNote = self:EncodeNote(ep, gp)
    GuildRosterSetOfficerNote(index, newNote)

    local Log = SimpleEPGP:GetModule("Log", true)
    if Log then
        Log:Add("GP", name, amount, nil, reason)
    end

    self:RefreshRoster()
    self:BroadcastStandings()
    return true
end

--- Award EP to all current raid members (and standby list if configured).
-- @param amount EP to award.
-- @param reason Optional reason string.
function EPGP:MassEP(amount, reason)
    local Debug = SimpleEPGP:GetModule("Debug", true)
    if Debug then Debug:Log("EPGP", "MassEP", { amount = amount, reason = reason }) end

    if not self:CanEditNotes() then
        SimpleEPGP:Print("Cannot award mass EP: you don't have officer note permissions.")
        return false
    end

    if not IsInRaid() then
        SimpleEPGP:Print("You must be in a raid to award mass EP.")
        return false
    end

    local db = SimpleEPGP.db
    local standbyPercent = db.profile.standby_percent or 0
    local awarded = 0

    -- Award to raid members
    local numRaid = GetNumGroupMembers()
    for i = 1, numRaid do
        local name = GetRaidRosterInfo(i)
        if name then
            local shortName = name:match("^([^%-]+)") or name
            local index = FindRosterIndex(shortName)
            if index then
                local _, _, _, _, _, _, _, officerNote = GetGuildRosterInfo(index)
                local ep, gp = self:ParseNote(officerNote or "")
                ep = (ep or 0) + amount
                gp = gp or 0
                GuildRosterSetOfficerNote(index, self:EncodeNote(ep, gp))
                awarded = awarded + 1
            end
        end
    end

    -- Award standby EP if configured and standby list exists
    -- standby_percent is 0.0-1.0 (not 0-100), standby list is in db.standby
    if standbyPercent > 0 and db.standby then
        local standbyAmount = floor(amount * standbyPercent)
        if standbyAmount > 0 then
            for _, standbyName in ipairs(db.standby) do
                local index = FindRosterIndex(standbyName)
                if index then
                    local _, _, _, _, _, _, _, officerNote = GetGuildRosterInfo(index)
                    local ep, gp = self:ParseNote(officerNote or "")
                    ep = (ep or 0) + standbyAmount
                    gp = gp or 0
                    GuildRosterSetOfficerNote(index, self:EncodeNote(ep, gp))
                end
            end
        end
    end

    local Log = SimpleEPGP:GetModule("Log", true)
    if Log then
        Log:Add("MASS_EP", nil, amount, nil, reason or ("Mass EP to " .. awarded .. " raiders"))
    end

    self:RefreshRoster()
    self:BroadcastStandings()
    SimpleEPGP:Print("Awarded " .. amount .. " EP to " .. awarded .. " raid members.")
    return true
end

--- Apply decay to all guild members with EP > 0 or GP > 0.
-- Writes are spaced with C_Timer.After to avoid hitting the server throttle.
function EPGP:Decay()
    local Debug = SimpleEPGP:GetModule("Debug", true)
    if Debug then Debug:Log("EPGP", "Decay", { percent = SimpleEPGP.db.profile.decay_percent }) end

    if not self:CanEditNotes() then
        SimpleEPGP:Print("Cannot decay: you don't have officer note permissions.")
        return false
    end

    local db = SimpleEPGP.db
    local decayPercent = db.profile.decay_percent or 0
    if decayPercent <= 0 then
        SimpleEPGP:Print("Decay percent is 0, nothing to do.")
        return false
    end

    local multiplier = 1 - (decayPercent / 100)
    local numMembers = GetNumGuildMembers()
    local writeDelay = 0

    for i = 1, numMembers do
        local name, _, _, _, _, _, _, officerNote = GetGuildRosterInfo(i)
        if name then
            local ep, gp = self:ParseNote(officerNote or "")
            if ep and gp and (ep > 0 or gp > 0) then
                local newEP = floor(ep * multiplier)
                local newGP = floor(gp * multiplier)
                local newNote = self:EncodeNote(newEP, newGP)
                -- Space writes to avoid server throttle on bulk officer note updates
                local rosterIndex = i
                C_Timer.After(writeDelay, function()
                    -- Re-verify the roster index is still the same player
                    local checkName = GetGuildRosterInfo(rosterIndex)
                    if checkName then
                        local checkShort = checkName:match("^([^%-]+)") or checkName
                        local nameShort = name:match("^([^%-]+)") or name
                        if checkShort == nameShort then
                            GuildRosterSetOfficerNote(rosterIndex, newNote)
                        end
                    end
                end)
                writeDelay = writeDelay + 0.05
            end
        end
    end

    local Log = SimpleEPGP:GetModule("Log", true)
    if Log then
        Log:Add("DECAY", nil, decayPercent, nil, decayPercent .. "% decay applied")
    end

    -- Refresh after all writes should be done, then broadcast updates
    C_Timer.After(writeDelay + 0.5, function()
        EPGP:RefreshRoster()
        EPGP:BroadcastStandings()
    end)

    SimpleEPGP:Print("Applied " .. decayPercent .. "% decay to all members.")
    return true
end

--- Reset all EP and GP to 0,0 for every guild member with an EPGP note.
function EPGP:ResetAll()
    local Debug = SimpleEPGP:GetModule("Debug", true)
    if Debug then Debug:Log("EPGP", "ResetAll") end

    if not self:CanEditNotes() then
        SimpleEPGP:Print("Cannot reset: you don't have officer note permissions.")
        return false
    end

    local numMembers = GetNumGuildMembers()
    local writeDelay = 0

    for i = 1, numMembers do
        local name, _, _, _, _, _, _, officerNote = GetGuildRosterInfo(i)
        if name then
            local ep, gp = self:ParseNote(officerNote or "")
            if ep and gp then
                local rosterIndex = i
                C_Timer.After(writeDelay, function()
                    local checkName = GetGuildRosterInfo(rosterIndex)
                    if checkName then
                        local checkShort = checkName:match("^([^%-]+)") or checkName
                        local nameShort = name:match("^([^%-]+)") or name
                        if checkShort == nameShort then
                            GuildRosterSetOfficerNote(rosterIndex, "0,0")
                        end
                    end
                end)
                writeDelay = writeDelay + 0.05
            end
        end
    end

    local Log = SimpleEPGP:GetModule("Log", true)
    if Log then
        Log:Add("RESET", nil, 0, nil, "All EP/GP reset to 0")
    end

    C_Timer.After(writeDelay + 0.5, function()
        EPGP:RefreshRoster()
        EPGP:BroadcastStandings()
    end)

    SimpleEPGP:Print("All EP/GP values have been reset.")
    return true
end

--------------------------------------------------------------------------------
-- Standings Sync — allows non-officers to see EP/GP data
--------------------------------------------------------------------------------

-- Debounce timer for broadcast: prevents spamming when multiple writes
-- happen in quick succession (e.g. Decay, MassEP).
local broadcastPending = false

--- Export current GP config for broadcasting to non-officers.
-- Returns a compact table of all config values that affect GP calculations.
-- @return table with keys: sm (slot_multipliers), io (item_overrides),
--   om (os_multiplier), dm (de_multiplier), bg (base_gp),
--   si (standard_ilvl), bm (gp_base_multiplier or nil).
function EPGP:ExportConfig()
    local db = SimpleEPGP.db
    local config = {
        sm = db.profile.slot_multipliers or {},
        io = db.profile.item_overrides or {},
        om = db.profile.os_multiplier or 0.5,
        dm = db.profile.de_multiplier or 0.0,
        bg = db.profile.base_gp or 100,
        si = db.profile.standard_ilvl or 120,
    }
    -- Only include gp_base_multiplier if explicitly set (nil means auto-derived)
    if db.profile.gp_base_multiplier then
        config.bm = db.profile.gp_base_multiplier
    end
    return config
end

--- Broadcast current standings to GUILD channel so non-officers get updates.
-- Debounced: multiple calls within 2 seconds collapse into a single broadcast.
-- Only fires if we can actually read officer notes (officer-side only).
function EPGP:BroadcastStandings()
    if not self:CanViewNotes() then return end
    if broadcastPending then return end

    broadcastPending = true
    C_Timer.After(2, function()
        broadcastPending = false

        local data = {}
        for _, entry in ipairs(standings) do
            if entry.ep > 0 or entry.gp > 0 then
                data[#data + 1] = {
                    n = entry.name,
                    c = entry.class,
                    e = entry.ep,
                    g = entry.gp,
                }
            end
        end

        if #data == 0 then return end

        local Debug = SimpleEPGP:GetModule("Debug", true)
        if Debug then Debug:Log("EPGP", "Broadcasting standings", { count = #data }) end

        -- Broadcast to GUILD so all non-officers receive it
        -- Include GP config so non-officers can compute correct tooltips
        local Comms = SimpleEPGP:GetModule("Comms")
        local payload = Comms:Serialize({
            type = "STANDINGS_SYNC",
            standings = data,
            config = EPGP:ExportConfig(),
        })
        Comms:SendCommMessage("SimpleEPGP", payload, "GUILD", nil, "BULK")
    end)
end

--- Check whether the current player can view officer notes.
-- @return true if the player has officer note view permission.
function EPGP:CanViewNotes()
    if C_GuildInfo and C_GuildInfo.CanViewOfficerNote then
        return C_GuildInfo.CanViewOfficerNote()
    end
    if CanViewOfficerNote then
        return CanViewOfficerNote()
    end
    return false
end

--- Return whether standings were synced from an officer (vs read directly).
-- @return true if using synced data.
function EPGP:IsSynced()
    return syncedFromOfficer
end

--- Request standings from an online officer.
-- Called manually via /sepgp sync.
function EPGP:RequestSync()
    local Debug = SimpleEPGP:GetModule("Debug", true)
    if Debug then Debug:Log("EPGP", "Requesting standings sync from officers") end

    SimpleEPGP:Print("Requesting EP/GP standings from officers...")
    local Comms = SimpleEPGP:GetModule("Comms")
    Comms:SendStandingsRequest()
end

--- One-time check after first GUILD_ROSTER_UPDATE.
-- If we can't read officer notes, schedule a single auto-request with
-- a random delay (2-8 seconds) to stagger when multiple non-officers
-- log in at the same time.
function EPGP:CheckNeedSync()
    -- If we can read notes directly, no sync needed
    if self:CanViewNotes() then return end

    -- If we already have synced data, don't re-request
    if syncedFromOfficer then return end

    -- Check if all standings are zero (meaning notes are unreadable)
    local allZero = true
    for _, entry in ipairs(standings) do
        if entry.ep > 0 or entry.gp > 0 then
            allZero = false
            break
        end
    end

    if allZero and #standings > 0 then
        -- Random delay 2-8 seconds to stagger requests from multiple clients
        local delay = 2 + math.random() * 6
        C_Timer.After(delay, function()
            -- Re-check: might have received sync during the delay
            if not syncedFromOfficer then
                self:RequestSync()
            end
        end)
    end
end

--- Handle incoming STANDINGS_REQUEST from a non-officer.
-- If we can read notes and have valid data, respond with standings + config.
-- Uses a short random delay (1-3s) so multiple officers don't all
-- respond simultaneously to the same request.
-- @param sender string The requesting player's name.
function EPGP:OnStandingsRequest(sender)
    -- Only respond if we can actually read officer notes
    if not self:CanViewNotes() then return end

    -- Don't respond to our own requests
    local myName = UnitName("player")
    if sender == myName then return end

    -- Random delay to prevent all officers responding at once
    local delay = 1 + math.random() * 2
    C_Timer.After(delay, function()
        local Debug = SimpleEPGP:GetModule("Debug", true)
        if Debug then Debug:Log("EPGP", "Responding to standings request", { from = sender }) end

        -- Build compact standings data (just name, class, ep, gp)
        local data = {}
        for _, entry in ipairs(standings) do
            data[#data + 1] = {
                n = entry.name,
                c = entry.class,
                e = entry.ep,
                g = entry.gp,
            }
        end

        local Comms = SimpleEPGP:GetModule("Comms")
        Comms:SendStandingsSync(sender, data, EPGP:ExportConfig())
    end)
end

--- Apply received GP config from an officer to local settings.
-- Only called on non-officer clients. Updates slot multipliers, item overrides,
-- bid multipliers, and formula parameters so tooltips/GP calculations match
-- the officer's configuration.
-- @param config table Compact config table from ExportConfig (keys: sm, io, om, dm, bg, si, bm).
function EPGP:ApplyReceivedConfig(config)
    if not config then return end

    local db = SimpleEPGP.db
    local GPCalc = SimpleEPGP:GetModule("GPCalc")
    local Debug = SimpleEPGP:GetModule("Debug", true)

    -- Slot multipliers (sm)
    if config.sm then
        db.profile.slot_multipliers = config.sm
    end

    -- Item overrides (io)
    if config.io then
        db.profile.item_overrides = config.io
    end

    -- OS multiplier (om)
    if config.om ~= nil then
        db.profile.os_multiplier = config.om
    end

    -- DE multiplier (dm)
    if config.dm ~= nil then
        db.profile.de_multiplier = config.dm
    end

    -- Base GP (bg) — uses GPCalc setter for validation
    if config.bg ~= nil then
        GPCalc:SetBaseGP(config.bg)
    end

    -- Standard ilvl (si) — uses GPCalc setter for validation
    if config.si ~= nil then
        GPCalc:SetStandardIlvl(config.si)
    end

    -- GP base multiplier (bm) — nil means auto-derived
    if config.bm ~= nil then
        GPCalc:SetGPBaseMultiplier(config.bm)
    else
        GPCalc:ClearGPBaseMultiplier()
    end

    if Debug then Debug:Log("EPGP", "Applied GP config from officer") end
end

--- Handle incoming STANDINGS_SYNC from an officer.
-- Applies GP config (if present) then populates the local standings cache.
-- @param sender string The officer who sent the data.
-- @param data table Contains data.standings array of {n, c, e, g} and optional data.config.
function EPGP:OnStandingsSync(sender, data)
    if not data or not data.standings then return end

    -- Officers who can read notes directly don't need synced data
    if self:CanViewNotes() then return end

    local Debug = SimpleEPGP:GetModule("Debug", true)
    if Debug then Debug:Log("EPGP", "Received standings sync", { from = sender, count = #data.standings }) end

    -- Apply GP config BEFORE processing standings so PR calculation uses
    -- the officer's base_gp value (not the local default).
    self:ApplyReceivedConfig(data.config)

    local db = SimpleEPGP.db
    local baseGP = db.profile.base_gp or 1
    local minEP = db.profile.min_ep or 0

    local newStandings = {}
    local newLookup = {}

    for _, entry in ipairs(data.standings) do
        local ep = entry.e or 0
        local gp = entry.g or 0
        local effectiveGP = math.max(gp, 0) + baseGP
        local pr = 0
        if ep >= minEP and effectiveGP > 0 then
            pr = ep / effectiveGP
        end

        local record = {
            name = entry.n,
            class = entry.c,
            ep = ep,
            gp = gp,
            pr = pr,
            rosterIndex = nil,  -- not available from sync
        }
        newStandings[#newStandings + 1] = record
        newLookup[entry.n] = record
    end

    -- Sort by PR descending
    table.sort(newStandings, function(a, b)
        return a.pr > b.pr
    end)

    standings = newStandings
    playerLookup = newLookup
    syncedFromOfficer = true

    SimpleEPGP:Print("Received standings from " .. sender .. " (" .. #newStandings .. " members).")
    self:SendMessage("SEPGP_STANDINGS_UPDATED")
end

--- Check whether the current player can edit officer notes.
-- @return true if the player has officer note edit permission.
function EPGP:CanEditNotes()
    -- C_GuildInfo.CanEditOfficerNote() is the TBC Anniversary API
    if C_GuildInfo and C_GuildInfo.CanEditOfficerNote then
        return C_GuildInfo.CanEditOfficerNote()
    end
    -- Fallback: CanEditOfficerNote() as a global (older client builds)
    if CanEditOfficerNote then
        return CanEditOfficerNote()
    end
    return false
end
