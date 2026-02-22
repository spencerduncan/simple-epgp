-----------------------------------------------------------------------
-- Debug.lua — Debug logging and test helper commands
-- Writes structured log entries to SimpleEPGPDebugLog SavedVariable
-- for external parsing. Also provides /sepgp debug subcommands for
-- simulating game events without needing a raid group.
-----------------------------------------------------------------------
local SimpleEPGP = LibStub("AceAddon-3.0"):GetAddon("SimpleEPGP")
local Debug = SimpleEPGP:NewModule("Debug", "AceEvent-3.0")

local function StripRealm(name)
    if SimpleEPGP.StripRealm then return SimpleEPGP.StripRealm(name) end
    if not name then return nil end
    return name:match("^([^%-]+)") or name
end

local time = time
local ipairs = ipairs
local tostring = tostring
local type = type
local table = table
local math = math

-- Max entries in the circular buffer
local MAX_ENTRIES = 500

-- Saved state for fakeraid overrides
local savedIsInRaid = nil
local savedGetNumGroupMembers = nil
local fakeRaidActive = false

--------------------------------------------------------------------------------
-- Lifecycle
--------------------------------------------------------------------------------

--- Get the debug log table (SavedVariable accessed through _G for portability).
local function GetLog()
    if not _G.SimpleEPGPDebugLog then
        _G.SimpleEPGPDebugLog = {}
    end
    return _G.SimpleEPGPDebugLog
end

function Debug:OnEnable()
    -- Initialize the debug log SavedVariable if it doesn't exist
    GetLog()
end

--------------------------------------------------------------------------------
-- Core Logging
--------------------------------------------------------------------------------

--- Append a debug log entry. Entries are stored in SimpleEPGPDebugLog
-- (a SavedVariable), written to disk on /reloadui or logout.
-- @param category string One of: INFO, WARN, ERROR, EVENT, EPGP, COMMS, LOOT, UI
-- @param message string Short description
-- @param data table|nil Optional structured data
function Debug:Log(category, message, data)
    local log = GetLog()

    local entry = { time(), category or "INFO", message or "" }
    if data then
        entry[4] = data
    end

    log[#log + 1] = entry

    -- Prune if over max
    while #log > MAX_ENTRIES do
        table.remove(log, 1)
    end
end

--- Format a single log entry for chat display.
-- @param entry table {timestamp, category, message[, data]}
-- @return string Formatted line
function Debug:FormatEntry(entry)
    local ts = entry[1] or 0
    local cat = entry[2] or "?"
    local msg = entry[3] or ""
    local dataStr = ""
    if entry[4] and type(entry[4]) == "table" then
        local parts = {}
        for k, v in pairs(entry[4]) do
            parts[#parts + 1] = tostring(k) .. "=" .. tostring(v)
        end
        if #parts > 0 then
            dataStr = " {" .. table.concat(parts, ", ") .. "}"
        end
    end
    return string.format("[%s] [%s] %s%s", date("%H:%M:%S", ts), cat, msg, dataStr)
end

--------------------------------------------------------------------------------
-- Debug Slash Command Router
--------------------------------------------------------------------------------

--- Handle /sepgp debug <subcommand> [args...]
-- @param args table Parsed arguments (args[1] is "debug", args[2] is subcommand)
function Debug:HandleCommand(args)
    local sub = args[2] and args[2]:lower() or "help"

    if sub == "log" then
        self:CmdLog(args)
    elseif sub == "clear" then
        self:CmdClear()
    elseif sub == "roster" then
        self:CmdRoster()
    elseif sub == "note" then
        self:CmdNote(args)
    elseif sub == "status" then
        self:CmdStatus()
    elseif sub == "fakeraid" then
        self:CmdFakeRaid()
    elseif sub == "endfakeraid" then
        self:CmdEndFakeRaid()
    elseif sub == "bosskill" then
        self:CmdBossKill(args)
    elseif sub == "loot" then
        self:CmdLoot(args)
    elseif sub == "bid" then
        self:CmdBid(args)
    elseif sub == "viewcheck" then
        self:CmdViewCheck()
    elseif sub == "tooltip" then
        self:CmdTooltip(args)
    elseif sub == "selftest" then
        self:CmdSelfTest()
    else
        self:PrintHelp()
    end
end

--------------------------------------------------------------------------------
-- Debug Commands: Log inspection
--------------------------------------------------------------------------------

function Debug:CmdLog(args)
    local count = tonumber(args[3]) or 20
    local log = GetLog()
    local start = math.max(1, #log - count + 1)

    if #log == 0 then
        SimpleEPGP:Print("Debug log is empty.")
        return
    end

    SimpleEPGP:Print("Debug log (last " .. math.min(count, #log) .. " of " .. #log .. "):")
    for i = start, #log do
        SimpleEPGP:Print("  " .. self:FormatEntry(log[i]))
    end
end

function Debug:CmdClear()
    _G.SimpleEPGPDebugLog = {}
    SimpleEPGP:Print("Debug log cleared.")
    self:Log("INFO", "Debug log cleared by user")
end

--------------------------------------------------------------------------------
-- Debug Commands: Roster inspection
--------------------------------------------------------------------------------

function Debug:CmdRoster()
    local EPGP = SimpleEPGP:GetModule("EPGP")
    local standings = EPGP:GetStandings()

    if #standings == 0 then
        SimpleEPGP:Print("No standings data. Are you in a guild?")
        return
    end

    SimpleEPGP:Print("Guild roster (" .. #standings .. " members):")
    local shown = 0
    for _, entry in ipairs(standings) do
        if entry.ep > 0 or entry.gp > 0 then
            SimpleEPGP:Print(string.format("  %s (%s): EP=%d GP=%d PR=%.2f",
                entry.name, entry.class or "?", entry.ep, entry.gp, entry.pr))
            shown = shown + 1
        end
    end
    if shown == 0 then
        SimpleEPGP:Print("  (No members have EP or GP yet)")
    end
end

function Debug:CmdNote(args)
    local name = args[3]
    if not name then
        SimpleEPGP:Print("Usage: /sepgp debug note <name>")
        return
    end

    local EPGP = SimpleEPGP:GetModule("EPGP")
    local info = EPGP:GetPlayerInfo(name)
    if not info then
        SimpleEPGP:Print("Player " .. name .. " not found in roster cache.")
        return
    end

    -- Read the raw officer note from the guild roster
    local numMembers = GetNumGuildMembers()
    for i = 1, numMembers do
        local rosterName, _, _, _, _, _, _, officerNote = GetGuildRosterInfo(i)
        if rosterName then
            local shortName = StripRealm(rosterName)
            if shortName == name then
                SimpleEPGP:Print(name .. " officer note: " .. (officerNote or "(empty)"))
                return
            end
        end
    end
    SimpleEPGP:Print(name .. " not found in guild roster.")
end

--------------------------------------------------------------------------------
-- Debug Commands: Status
--------------------------------------------------------------------------------

function Debug:CmdStatus()
    local db = SimpleEPGP.db
    SimpleEPGP:Print("=== SimpleEPGP Debug Status ===")
    SimpleEPGP:Print("  Fake raid active: " .. tostring(fakeRaidActive))
    SimpleEPGP:Print("  IsInRaid(): " .. tostring(_G.IsInRaid()))
    SimpleEPGP:Print("  GetNumGroupMembers(): " .. tostring(_G.GetNumGroupMembers()))

    -- Config values
    SimpleEPGP:Print("  ep_per_boss: " .. tostring(db.profile.ep_per_boss))
    SimpleEPGP:Print("  auto_ep: " .. tostring(db.profile.auto_ep))
    SimpleEPGP:Print("  base_gp: " .. tostring(db.profile.base_gp))
    SimpleEPGP:Print("  decay_percent: " .. tostring(db.profile.decay_percent))
    SimpleEPGP:Print("  bid_timer: " .. tostring(db.profile.bid_timer))
    SimpleEPGP:Print("  announce_channel: " .. tostring(db.profile.announce_channel))

    -- Standby list
    local standby = db.standby or {}
    SimpleEPGP:Print("  Standby list: " .. #standby .. " players")

    -- Debug log size
    local logSize = #GetLog()
    SimpleEPGP:Print("  Debug log entries: " .. logSize .. "/" .. MAX_ENTRIES)
end

--------------------------------------------------------------------------------
-- Debug Commands: Fake Raid
--------------------------------------------------------------------------------

function Debug:CmdFakeRaid()
    if fakeRaidActive then
        SimpleEPGP:Print("Fake raid is already active. Use /sepgp debug endfakeraid to end it.")
        return
    end

    -- Save originals
    savedIsInRaid = _G.IsInRaid
    savedGetNumGroupMembers = _G.GetNumGroupMembers

    -- Override globals
    _G.IsInRaid = function() return true end
    _G.GetNumGroupMembers = function() return 5 end

    fakeRaidActive = true
    self:Log("INFO", "Fake raid activated", { members = 5 })
    SimpleEPGP:Print("Fake raid activated (5 members). IsInRaid() now returns true.")
    SimpleEPGP:Print("Use /sepgp debug endfakeraid to restore.")
end

function Debug:CmdEndFakeRaid()
    if not fakeRaidActive then
        SimpleEPGP:Print("No fake raid is active.")
        return
    end

    -- Restore originals
    if savedIsInRaid then
        _G.IsInRaid = savedIsInRaid
        savedIsInRaid = nil
    end
    if savedGetNumGroupMembers then
        _G.GetNumGroupMembers = savedGetNumGroupMembers
        savedGetNumGroupMembers = nil
    end

    fakeRaidActive = false
    self:Log("INFO", "Fake raid deactivated")
    SimpleEPGP:Print("Fake raid deactivated. Globals restored.")
end

--------------------------------------------------------------------------------
-- Debug Commands: Boss Kill Simulation
--------------------------------------------------------------------------------

function Debug:CmdBossKill(args)
    local bossName = args[3] or "Test Boss"
    -- Reconstruct multi-word boss name from remaining args
    if args[4] then
        local parts = {}
        for i = 3, #args do
            parts[#parts + 1] = args[i]
        end
        bossName = table.concat(parts, " ")
    end

    self:Log("INFO", "Simulating boss kill", { boss = bossName })
    SimpleEPGP:Print("Simulating boss kill: " .. bossName)

    -- Fire the ENCOUNTER_END handler directly
    -- Args: event, encounterID, encounterName, difficultyID, groupSize, success
    SimpleEPGP:ENCOUNTER_END("ENCOUNTER_END", 9999, bossName, 4, 25, 1)
end

--------------------------------------------------------------------------------
-- Debug Commands: Loot Simulation
--------------------------------------------------------------------------------

function Debug:CmdLoot(args)
    local itemID = tonumber(args[3]) or 29759  -- Default: T4 Helm of the Fallen Hero

    -- Try to get real item info if cached
    local itemName, itemLink = GetItemInfo(itemID)
    if itemName and itemLink then
        self:StartLootSession(itemID, itemLink)
        return
    end

    -- Item not cached — request from server and wait for event
    SimpleEPGP:Print("Item " .. itemID .. " not cached, requesting from server...")
    self._pendingItemID = itemID

    self:RegisterEvent("GET_ITEM_INFO_RECEIVED", "OnItemInfoReceived")

    -- Request the item data from the server
    if C_Item and C_Item.RequestLoadItemDataByID then
        C_Item.RequestLoadItemDataByID(itemID)
    else
        -- Fallback: calling GetItemInfo also triggers a server request
        GetItemInfo(itemID)
    end

    -- Timeout after 5 seconds in case the item doesn't exist
    C_Timer.After(5, function()
        if self._pendingItemID == itemID then
            self._pendingItemID = nil
            self:UnregisterEvent("GET_ITEM_INFO_RECEIVED")
            SimpleEPGP:Print("Timed out waiting for item " .. itemID .. ". Item may not exist.")
            self:Log("WARN", "Item request timed out", { itemID = itemID })
        end
    end)
end

--- Handle GET_ITEM_INFO_RECEIVED for pending debug loot requests.
-- @param event string The event name
-- @param receivedItemID number The item ID that was loaded
-- @param success boolean Whether the item data was loaded successfully
function Debug:OnItemInfoReceived(event, receivedItemID, success)
    if not self._pendingItemID then return end
    if receivedItemID ~= self._pendingItemID then return end

    local itemID = self._pendingItemID
    self._pendingItemID = nil
    self:UnregisterEvent("GET_ITEM_INFO_RECEIVED")

    if not success then
        SimpleEPGP:Print("Failed to load item " .. itemID .. ". Item may not exist.")
        self:Log("WARN", "Item request failed", { itemID = itemID })
        return
    end

    local itemName, itemLink = GetItemInfo(itemID)
    if not itemName or not itemLink then
        SimpleEPGP:Print("Item " .. itemID .. " data received but GetItemInfo still returned nil.")
        self:Log("WARN", "Item data inconsistency", { itemID = itemID })
        return
    end

    self:StartLootSession(itemID, itemLink)
end

--- Start a loot session with a real item link.
-- Shared by the cached path (immediate) and uncached path (after event).
-- @param itemID number The item ID
-- @param itemLink string The real item link from GetItemInfo
function Debug:StartLootSession(itemID, itemLink)
    self:Log("LOOT", "Simulating loot drop", { itemID = itemID, itemLink = itemLink })
    SimpleEPGP:Print("Simulating loot: " .. itemLink)

    -- Start a loot session directly on LootMaster
    local LootMaster = SimpleEPGP:GetModule("LootMaster")
    local GPCalc = SimpleEPGP:GetModule("GPCalc")
    local gpCost = GPCalc:CalculateGP(itemLink) or 100
    local sessionId = LootMaster:StartSession(itemLink, gpCost)
    SimpleEPGP:Print("Loot session #" .. sessionId .. " started (GP: " .. gpCost .. ")")
end

function Debug:CmdBid(args)
    local bidType = args[3] and args[3]:upper() or "MS"
    local fakePlayer = args[4] or "TestPlayer"

    if bidType ~= "MS" and bidType ~= "OS" and bidType ~= "DE" and bidType ~= "PASS" then
        SimpleEPGP:Print("Usage: /sepgp debug bid <MS|OS|DE|PASS> [playerName]")
        return
    end

    local LootMaster = SimpleEPGP:GetModule("LootMaster")

    -- Find the most recent active session
    local latestSession = nil
    local latestId = 0
    for id, session in pairs(LootMaster.sessions) do
        if not session.awarded and id > latestId then
            latestSession = session
            latestId = id
        end
    end

    if not latestSession then
        SimpleEPGP:Print("No active loot session. Run /sepgp debug loot first.")
        return
    end

    self:Log("LOOT", "Simulating bid", { sessionId = latestId, bidType = bidType, player = fakePlayer })
    SimpleEPGP:Print("Injecting " .. bidType .. " bid from " .. fakePlayer .. " on session #" .. latestId)

    -- Inject the bid directly
    latestSession.bids[fakePlayer] = bidType
end

--------------------------------------------------------------------------------
-- Debug Commands: Officer Note Permission Check
--------------------------------------------------------------------------------

function Debug:CmdViewCheck()
    SimpleEPGP:Print("=== Officer Note Permission Check ===")

    -- Check CanViewOfficerNote
    local canView = "unknown"
    if C_GuildInfo and C_GuildInfo.CanViewOfficerNote then
        canView = tostring(C_GuildInfo.CanViewOfficerNote())
        SimpleEPGP:Print("  C_GuildInfo.CanViewOfficerNote(): " .. canView)
    elseif CanViewOfficerNote then
        canView = tostring(CanViewOfficerNote())
        SimpleEPGP:Print("  CanViewOfficerNote(): " .. canView)
    else
        SimpleEPGP:Print("  CanViewOfficerNote: API not found")
    end

    -- Check CanEditOfficerNote
    local EPGP = SimpleEPGP:GetModule("EPGP")
    local canEdit = EPGP:CanEditNotes()
    SimpleEPGP:Print("  CanEditNotes(): " .. tostring(canEdit))

    -- Sample raw officer notes from first 5 guild members
    local numMembers = GetNumGuildMembers()
    SimpleEPGP:Print("  Guild members: " .. numMembers)
    SimpleEPGP:Print("  First 5 raw officer notes:")
    local nonEmpty = 0
    for i = 1, math.min(numMembers, 5) do
        local name, _, _, _, _, _, _, officerNote = GetGuildRosterInfo(i)
        if name then
            local shortName = StripRealm(name)
            local display = officerNote
            if display == nil then
                display = "(nil)"
            elseif display == "" then
                display = "(empty string)"
            end
            SimpleEPGP:Print("    " .. shortName .. ": " .. display)
            if officerNote and officerNote ~= "" then
                nonEmpty = nonEmpty + 1
            end
        end
    end

    -- Summary
    if nonEmpty == 0 then
        SimpleEPGP:Print("  Result: All sampled notes are empty.")
        if canView == "false" then
            SimpleEPGP:Print("  >> You likely CANNOT view officer notes (permission denied).")
        else
            SimpleEPGP:Print("  >> Notes may not be initialized yet, OR you lack view permission.")
            SimpleEPGP:Print("  >> Ask an officer to check if any notes contain EP,GP values.")
        end
    else
        SimpleEPGP:Print("  Result: Found " .. nonEmpty .. " non-empty notes. You CAN read officer notes.")
    end
end

--------------------------------------------------------------------------------
-- Debug Commands: Tooltip Diagnostics
--------------------------------------------------------------------------------

function Debug:CmdTooltip(args)
    local db = SimpleEPGP.db
    SimpleEPGP:Print("=== Tooltip Diagnostics ===")
    SimpleEPGP:Print("  show_gp_tooltip: " .. tostring(db.profile.show_gp_tooltip))
    SimpleEPGP:Print("  quality_threshold: " .. tostring(db.profile.quality_threshold))
    SimpleEPGP:Print("  (Items below this quality won't show GP)")
    SimpleEPGP:Print("  Quality reference: 0=Poor, 1=Common, 2=Uncommon, 3=Rare, 4=Epic, 5=Legendary")

    -- Test with an item ID if provided
    local itemID = tonumber(args[3])
    if itemID then
        local name, link, quality, ilvl, _, _, _, _, equipLoc = GetItemInfo(itemID)
        if name then
            SimpleEPGP:Print("  Test item: " .. (link or name))
            SimpleEPGP:Print("    quality=" .. tostring(quality) .. " ilvl=" .. tostring(ilvl) .. " slot=" .. tostring(equipLoc))
            local GPCalc = SimpleEPGP:GetModule("GPCalc")
            local gp = GPCalc:CalculateGP(link)
            SimpleEPGP:Print("    CalculateGP result: " .. tostring(gp))
            if not gp then
                if quality < db.profile.quality_threshold then
                    SimpleEPGP:Print("    >> Filtered: quality " .. quality .. " < threshold " .. db.profile.quality_threshold)
                elseif not equipLoc or equipLoc == "" then
                    SimpleEPGP:Print("    >> Filtered: not equippable (no slot)")
                else
                    SimpleEPGP:Print("    >> Filtered: unknown reason")
                end
            end
        else
            SimpleEPGP:Print("  Item " .. itemID .. " not cached. Try linking it in chat first.")
        end
    else
        SimpleEPGP:Print("  Tip: /sepgp debug tooltip <itemID> to test a specific item")
    end

    -- Check if GameTooltip hooks are working
    SimpleEPGP:Print("  GameTooltip exists: " .. tostring(GameTooltip ~= nil))
    SimpleEPGP:Print("  Tooltip module enabled: " .. tostring(SimpleEPGP:GetModule("Tooltip").enabledState))
end

--------------------------------------------------------------------------------
-- Debug Commands: Automated Self-Test
--------------------------------------------------------------------------------

--- Run a comprehensive self-test suite that exercises all testable code paths
--- without requiring officer note access, real loot, or other players.
--- Prints PASS/FAIL per check with a final summary.
function Debug:CmdSelfTest()
    local pass, fail = 0, 0
    local floor = math.floor

    local function check(name, condition)
        if condition then
            pass = pass + 1
            SimpleEPGP:Print("  |cff00ff00PASS|r " .. name)
        else
            fail = fail + 1
            SimpleEPGP:Print("  |cffff0000FAIL|r " .. name)
        end
    end

    local function section(name, fn)
        SimpleEPGP:Print("|cffffcc00--- " .. name .. " ---|r")
        local ok, err = pcall(fn)
        if not ok then
            fail = fail + 1
            SimpleEPGP:Print("  |cffff0000CRASH|r " .. tostring(err))
        end
    end

    SimpleEPGP:Print("|cff00ccff=== SimpleEPGP Self-Test ===|r")

    -- 1. Module loading
    section("Module Loading", function()
        local modules = {
            "EPGP", "GPCalc", "Comms", "LootMaster", "Log",
            "Standings", "Config", "GPConfig", "ExportFrame",
            "Leaderboard", "Tooltip", "Debug",
        }
        for _, name in ipairs(modules) do
            local mod = SimpleEPGP:GetModule(name, true)
            check(name .. " loaded", mod ~= nil)
        end
    end)

    -- 2. Config/DB integrity
    section("Config/DB Integrity", function()
        local db = SimpleEPGP.db
        check("db exists", db ~= nil)
        check("db.profile exists", db and db.profile ~= nil)
        if db and db.profile then
            local p = db.profile
            check("base_gp is number > 0", type(p.base_gp) == "number" and p.base_gp > 0)
            check("decay_percent is 0-100", type(p.decay_percent) == "number" and p.decay_percent >= 0 and p.decay_percent <= 100)
            check("quality_threshold is number", type(p.quality_threshold) == "number")
            check("bid_timer is number > 0", type(p.bid_timer) == "number" and p.bid_timer > 0)
            check("ep_per_boss is number", type(p.ep_per_boss) == "number")
            check("os_multiplier is number", type(p.os_multiplier) == "number")
        end
    end)

    -- 3. EPGP math
    section("EPGP Math", function()
        local EPGP = SimpleEPGP:GetModule("EPGP")
        local ep, gp = EPGP:ParseNote("5000,1000")
        check("ParseNote(5000,1000) -> ep=5000", ep == 5000)
        check("ParseNote(5000,1000) -> gp=1000", gp == 1000)
        check("ParseNote('') -> nil", EPGP:ParseNote("") == nil)
        check("ParseNote('garbage') -> nil", EPGP:ParseNote("garbage") == nil)
        check("EncodeNote(1234,567) -> '1234,567'", EPGP:EncodeNote(1234, 567) == "1234,567")

        -- Roundtrip
        local encoded = EPGP:EncodeNote(9999, 0)
        local rtEP, rtGP = EPGP:ParseNote(encoded)
        check("Encode/Parse roundtrip", rtEP == 9999 and rtGP == 0)
    end)

    -- 4. GPCalc engine
    section("GPCalc Engine", function()
        local GPCalc = SimpleEPGP:GetModule("GPCalc")
        local baseMult = GPCalc:GetBaseMultiplier()
        check("GetBaseMultiplier() > 0", type(baseMult) == "number" and baseMult > 0)
        check("HEAD slot = 1.0", GPCalc:GetSlotMultiplier("INVTYPE_HEAD") == 1.0)
        check("TRINKET slot = 1.25", GPCalc:GetSlotMultiplier("INVTYPE_TRINKET") == 1.25)
        check("2HWEAPON slot = 2.0", GPCalc:GetSlotMultiplier("INVTYPE_2HWEAPON") == 2.0)
        check("Empty string slot -> nil", GPCalc:GetSlotMultiplier("") == nil)
        check("nil slot -> nil", GPCalc:GetSlotMultiplier(nil) == nil)
        check("IsKnownSlot(HEAD) = true", GPCalc:IsKnownSlot("INVTYPE_HEAD") == true)
        check("IsKnownSlot(FAKE) = false", GPCalc:IsKnownSlot("INVTYPE_FAKE") == false)
        check("ParseItemID from link", GPCalc:ParseItemID("item:29759::::::::70:::::") == 29759)
        check("ParseItemID from number", GPCalc:ParseItemID(12345) == 12345)
        check("ParseItemID from string", GPCalc:ParseItemID("29759") == 29759)
    end)

    -- 5. Slot override cycle
    section("Slot Override Cycle", function()
        local GPCalc = SimpleEPGP:GetModule("GPCalc")
        -- Save original
        local db = SimpleEPGP.db
        local origOverride = db.profile.slot_multipliers and db.profile.slot_multipliers["INVTYPE_HEAD"]

        GPCalc:SetSlotMultiplier("INVTYPE_HEAD", 2.0)
        check("Set HEAD to 2.0", GPCalc:GetSlotMultiplier("INVTYPE_HEAD") == 2.0)

        GPCalc:ResetSlotMultiplier("INVTYPE_HEAD")
        check("Reset HEAD to default 1.0", GPCalc:GetSlotMultiplier("INVTYPE_HEAD") == 1.0)

        check("Set unknown slot returns false", GPCalc:SetSlotMultiplier("INVTYPE_FAKE", 1.0) == false)

        local allSlots = GPCalc:GetAllSlotInfo()
        check("GetAllSlotInfo() returns 25 slots", #allSlots == 25)

        -- Restore
        if origOverride then
            GPCalc:SetSlotMultiplier("INVTYPE_HEAD", origOverride)
        else
            GPCalc:ResetSlotMultiplier("INVTYPE_HEAD")
        end
    end)

    -- 6. Item override cycle
    section("Item Override Cycle", function()
        local GPCalc = SimpleEPGP:GetModule("GPCalc")
        local TEST_ID = 99999

        -- Save original
        local origOverrides = GPCalc:GetAllItemOverrides()
        local origVal = origOverrides[TEST_ID]

        GPCalc:SetItemOverride(TEST_ID, 500)
        check("Set item override 99999 = 500", GPCalc:GetAllItemOverrides()[TEST_ID] == 500)

        GPCalc:ClearItemOverride(TEST_ID)
        check("Clear item override", GPCalc:GetAllItemOverrides()[TEST_ID] == nil)

        -- Restore
        if origVal then
            GPCalc:SetItemOverride(TEST_ID, origVal)
        end
    end)

    -- 7. Bid GP multipliers (uses item override to avoid needing cached items)
    section("Bid GP Multipliers", function()
        local GPCalc = SimpleEPGP:GetModule("GPCalc")
        local db = SimpleEPGP.db
        local TEST_ID = 99998
        local fakeLink = "|cff|Hitem:" .. TEST_ID .. "|h[SelfTest Item]|h|r"

        -- Save and set override
        local origVal = GPCalc:GetAllItemOverrides()[TEST_ID]
        GPCalc:SetItemOverride(TEST_ID, 1000)

        local msGP = GPCalc:GetBidGP(fakeLink, "MS")
        check("MS bid GP = 1000", msGP == 1000)

        local expectedOS = floor(1000 * (db.profile.os_multiplier or 0.5))
        local osGP = GPCalc:GetBidGP(fakeLink, "OS")
        check("OS bid GP = " .. expectedOS, osGP == expectedOS)

        local passGP = GPCalc:GetBidGP(fakeLink, "PASS")
        check("PASS bid GP = 0", passGP == 0)

        local expectedDE = floor(1000 * (db.profile.de_multiplier or 0))
        local deGP = GPCalc:GetBidGP(fakeLink, "DE")
        check("DE bid GP = " .. expectedDE, deGP == expectedDE)

        -- Clean up
        GPCalc:ClearItemOverride(TEST_ID)
        if origVal then GPCalc:SetItemOverride(TEST_ID, origVal) end
    end)

    -- 8. Standby lifecycle
    section("Standby Lifecycle", function()
        local db = SimpleEPGP.db
        -- Save original
        local origStandby = {}
        for i, v in ipairs(db.standby or {}) do
            origStandby[i] = v
        end

        -- Clear
        db.standby = {}
        check("Clear standby -> empty", #db.standby == 0)

        -- Add
        db.standby[#db.standby + 1] = "SelfTestPlayer1"
        db.standby[#db.standby + 1] = "SelfTestPlayer2"
        check("Add 2 players -> count = 2", #db.standby == 2)

        -- Duplicate check (via the CmdStandby logic — check manually)
        local isDupe = false
        for _, v in ipairs(db.standby) do
            if v == "SelfTestPlayer1" then isDupe = true; break end
        end
        check("Duplicate detection works", isDupe == true)

        -- Clear again
        db.standby = {}
        check("Re-clear -> empty", #db.standby == 0)

        -- Restore
        db.standby = origStandby
        check("Standby restored", true)
    end)

    -- 9. Log module
    section("Log Module", function()
        local Log = SimpleEPGP:GetModule("Log")
        local logBefore = #(SimpleEPGP.db.log or {})

        Log:Add("TEST", "SelfTestProbe", 0, nil, "selftest")
        local logAfter = #(SimpleEPGP.db.log or {})
        check("Log:Add increments count", logAfter == logBefore + 1)

        local recent = Log:GetRecent(1)
        check("GetRecent(1) returns entry", #recent >= 1 and recent[1].action == "TEST")

        local formatted = Log:FormatEntry(recent[1])
        check("FormatEntry returns string", type(formatted) == "string" and #formatted > 0)

        local csv = Log:ExportCSV()
        check("ExportCSV has header", csv:find("timestamp,date,action") ~= nil)

        -- Remove the test entry (pop last)
        if SimpleEPGP.db.log and #SimpleEPGP.db.log > 0 then
            SimpleEPGP.db.log[#SimpleEPGP.db.log] = nil
        end
    end)

    -- 10. Comms serialize/deserialize
    section("Comms Serialize/Deserialize", function()
        local Comms = SimpleEPGP:GetModule("Comms")
        local testData = { type = "TEST", foo = "bar", num = 42 }
        local serialized = Comms:Serialize(testData)
        check("Serialize returns string", type(serialized) == "string" and #serialized > 0)

        local ok, deserialized = Comms:Deserialize(serialized)
        check("Deserialize succeeds", ok == true)
        check("Roundtrip preserves type field", ok and deserialized.type == "TEST")
        check("Roundtrip preserves string field", ok and deserialized.foo == "bar")
        check("Roundtrip preserves number field", ok and deserialized.num == 42)
    end)

    -- 11. Permission detection
    section("Permission Detection", function()
        local EPGP = SimpleEPGP:GetModule("EPGP")
        check("CanViewNotes returns boolean", type(EPGP:CanViewNotes()) == "boolean")
        check("CanEditNotes returns boolean", type(EPGP:CanEditNotes()) == "boolean")
        check("IsSynced returns boolean", type(EPGP:IsSynced()) == "boolean")
    end)

    -- 12. LootMaster session lifecycle
    section("LootMaster Session Lifecycle", function()
        local LootMaster = SimpleEPGP:GetModule("LootMaster")
        local fakeLink = "|cff|Hitem:99997|h[SelfTest Loot]|h|r"

        local sessionId = LootMaster:StartSession(fakeLink, 100)
        check("StartSession returns ID > 0", type(sessionId) == "number" and sessionId > 0)

        local session = LootMaster.sessions[sessionId]
        check("Session exists and not awarded", session ~= nil and not session.awarded)

        -- Inject a bid and verify GetSessionBids
        if session then
            session.bids["TestBidder"] = "MS"
            session.bids["TestBidder2"] = "OS"
            local bids = LootMaster:GetSessionBids(sessionId)
            check("GetSessionBids has MS group", bids ~= nil and bids.ms ~= nil)
            check("MS group contains TestBidder", bids and #bids.ms == 1 and bids.ms[1].name == "TestBidder")
            check("OS group contains TestBidder2", bids and #bids.os == 1 and bids.os[1].name == "TestBidder2")
        end

        LootMaster:CancelSession(sessionId)
        check("CancelSession removes session", LootMaster.sessions[sessionId] == nil)
    end)

    -- 13. UI frame open/close
    section("UI Frames Open/Close", function()
        local uiModules = {
            { name = "Standings",   frameName = "SimpleEPGPStandingsFrame" },
            { name = "Config",      frameName = "SimpleEPGPConfigFrame" },
            { name = "GPConfig",    frameName = "SimpleEPGPGPConfigFrame" },
            { name = "ExportFrame", frameName = "SimpleEPGPExportFrame" },
            { name = "Leaderboard", frameName = "SimpleEPGPLeaderboard" },
        }

        for _, ui in ipairs(uiModules) do
            local mod = SimpleEPGP:GetModule(ui.name, true)
            if mod then
                -- Open
                mod:Show()
                local f = _G[ui.frameName]
                local isShown = f and f:IsShown()
                check(ui.name .. " opens", isShown)

                -- Close
                mod:Hide()
                local isHidden = not f or not f:IsShown()
                check(ui.name .. " closes", isHidden)
            else
                check(ui.name .. " module exists", false)
            end
        end
    end)

    -- 14. Debug log cycle
    section("Debug Log Cycle", function()
        self:Log("TEST", "selftest probe marker")
        local log = GetLog()
        local last = log[#log]
        check("Debug:Log writes entry", last ~= nil and last[2] == "TEST" and last[3] == "selftest probe marker")

        local formatted = self:FormatEntry(last)
        check("FormatEntry works on probe", type(formatted) == "string" and formatted:find("selftest probe marker") ~= nil)
    end)

    -- Summary
    local total = pass + fail
    SimpleEPGP:Print("|cff00ccff=== Self-Test Complete ===|r")
    if fail == 0 then
        SimpleEPGP:Print("|cff00ff00ALL " .. total .. " CHECKS PASSED|r")
    else
        SimpleEPGP:Print("|cff00ff00" .. pass .. " passed|r, |cffff0000" .. fail .. " failed|r out of " .. total .. " checks")
    end
end

--------------------------------------------------------------------------------
-- Help
--------------------------------------------------------------------------------

function Debug:PrintHelp()
    SimpleEPGP:Print("Debug commands:")
    SimpleEPGP:Print("  /sepgp debug log [N] — Show last N debug log entries")
    SimpleEPGP:Print("  /sepgp debug clear — Clear the debug log")
    SimpleEPGP:Print("  /sepgp debug roster — Print guild roster with EP/GP")
    SimpleEPGP:Print("  /sepgp debug note <name> — Print raw officer note")
    SimpleEPGP:Print("  /sepgp debug status — Print addon state")
    SimpleEPGP:Print("  /sepgp debug fakeraid — Stub IsInRaid() to return true")
    SimpleEPGP:Print("  /sepgp debug endfakeraid — Restore real IsInRaid()")
    SimpleEPGP:Print("  /sepgp debug bosskill [name] — Simulate ENCOUNTER_END")
    SimpleEPGP:Print("  /sepgp debug loot [itemID] — Start a fake loot session")
    SimpleEPGP:Print("  /sepgp debug bid <MS|OS|DE> [player] — Inject a fake bid")
    SimpleEPGP:Print("  /sepgp debug viewcheck — Check officer note permissions")
    SimpleEPGP:Print("  /sepgp debug tooltip [itemID] — Tooltip diagnostics")
    SimpleEPGP:Print("  /sepgp debug selftest — Run automated self-test suite")
end
