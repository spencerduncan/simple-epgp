-----------------------------------------------------------------------
-- Core.lua — Main addon initialization, slash commands, event wiring
-- LOADED FIRST in .toc — creates the addon object that all modules reference
-----------------------------------------------------------------------
local ADDON_VERSION = "0.1.0"

local SimpleEPGP = LibStub("AceAddon-3.0"):NewAddon("SimpleEPGP",
    "AceConsole-3.0", "AceEvent-3.0", "AceComm-3.0", "AceSerializer-3.0")

-- Localize globals
local ipairs = ipairs
local tonumber = tonumber
local table = table
local SendChatMessage = SendChatMessage
local IsInRaid = IsInRaid

-- Pending confirmation state for dangerous commands (decay, reset)
local pendingAction = nil

-- AceDB defaults — the single source of truth for all addon settings
local defaults = {
    profile = {
        -- Core EPGP tuning
        base_gp = 100,
        min_ep = 0,
        decay_percent = 15,

        -- GP calculation
        quality_threshold = 4,
        standard_ilvl = 120,
        gp_base_multiplier = nil,
        slot_multipliers = {},
        item_overrides = {},

        -- Bid type GP multipliers
        os_multiplier = 0.5,
        de_multiplier = 0.0,

        -- EP awards
        ep_per_boss = 100,
        auto_ep = true,
        standby_percent = 1.0,

        -- Loot distribution
        bid_timer = 30,
        auto_distribute = false,
        auto_distribute_delay = 3,

        -- Tooltip
        show_gp_tooltip = true,

        -- Announcements
        announce_channel = "GUILD",
        announce_awards = true,
        announce_ep = true,
    },
}

--------------------------------------------------------------------------------
-- Lifecycle
--------------------------------------------------------------------------------

function SimpleEPGP:OnInitialize()
    self.db = LibStub("AceDB-3.0"):New("SimpleEPGPDB", defaults, true)

    -- Ensure standby table exists (stored at db level, not in profile)
    if not self.db.standby then
        self.db.standby = {}
    end

    -- Ensure log table exists
    if not self.db.log then
        self.db.log = {}
    end

    self:RegisterChatCommand("sepgp", "HandleSlashCommand")

    local Debug = self:GetModule("Debug", true)
    if Debug then Debug:Log("INFO", "OnInitialize complete", { version = ADDON_VERSION }) end
end

function SimpleEPGP:OnEnable()
    -- Register boss kill event for auto-EP
    self:RegisterEvent("ENCOUNTER_END")

    local Debug = self:GetModule("Debug", true)
    if Debug then Debug:Log("INFO", "OnEnable — addon loaded", { version = ADDON_VERSION }) end

    self:Print("SimpleEPGP v" .. ADDON_VERSION .. " loaded.")
end

--------------------------------------------------------------------------------
-- Boss Kill — Auto-EP
--------------------------------------------------------------------------------

--- ENCOUNTER_END fires when a boss encounter ends.
-- encounterID, encounterName, difficultyID, groupSize, success (1=kill, 0=wipe)
function SimpleEPGP:ENCOUNTER_END(_, encounterID, encounterName, difficultyID, groupSize, success)
    local Debug = self:GetModule("Debug", true)
    if Debug then Debug:Log("EVENT", "ENCOUNTER_END", {
        encounterID = encounterID, name = encounterName,
        difficulty = difficultyID, size = groupSize, success = success
    }) end

    if success ~= 1 then return end
    if not self.db.profile.auto_ep then return end
    if not IsInRaid() then return end

    local EPGP = self:GetModule("EPGP")
    local amount = self.db.profile.ep_per_boss or 100
    local reason = "Boss kill: " .. (encounterName or "Unknown")

    EPGP:MassEP(amount, reason)

    -- Announce the EP award if configured
    if self.db.profile.announce_ep then
        local channel = self.db.profile.announce_channel or "GUILD"
        SendChatMessage(
            "SimpleEPGP: Awarded " .. amount .. " EP for " .. (encounterName or "boss kill"),
            channel
        )
    end
end

--------------------------------------------------------------------------------
-- Slash Command Router
--------------------------------------------------------------------------------

function SimpleEPGP:HandleSlashCommand(input)
    input = input or ""
    local args = {}
    for word in input:gmatch("%S+") do
        args[#args + 1] = word
    end

    local cmd = args[1] and args[1]:lower() or ""

    if cmd == "" then
        self:GetModule("Standings"):Toggle()
    elseif cmd == "config" or cmd == "settings" then
        self:GetModule("Config"):Toggle()
    elseif cmd == "ep" then
        self:CmdEP(args)
    elseif cmd == "massep" then
        self:CmdMassEP(args)
    elseif cmd == "gp" then
        self:CmdGP(args)
    elseif cmd == "decay" then
        self:CmdDecay()
    elseif cmd == "confirm" then
        self:CmdConfirm()
    elseif cmd == "standby" then
        self:CmdStandby(args)
    elseif cmd == "slot" then
        self:CmdSlot(args)
    elseif cmd == "gpoverride" then
        self:CmdGPOverride(args)
    elseif cmd == "gpconfig" then
        self:GetModule("GPConfig"):Toggle()
    elseif cmd == "sync" then
        self:GetModule("EPGP"):RequestSync()
    elseif cmd == "export" then
        self:GetModule("ExportFrame"):Toggle()
    elseif cmd == "log" then
        self:CmdLog(args)
    elseif cmd == "reset" then
        self:CmdReset()
    elseif cmd == "board" or cmd == "leaderboard" then
        self:GetModule("Leaderboard"):Toggle()
    elseif cmd == "top" then
        self:CmdTop(args)
    elseif cmd == "debug" then
        self:GetModule("Debug"):HandleCommand(args)
    elseif cmd == "help" then
        self:PrintUsage()
    else
        self:Print("Unknown command: " .. cmd)
        self:PrintUsage()
    end
end

--------------------------------------------------------------------------------
-- /sepgp ep <name> <amount> [reason...]
--------------------------------------------------------------------------------

function SimpleEPGP:CmdEP(args)
    local name = args[2]
    local amount = tonumber(args[3])
    if not name or not amount then
        self:Print("Usage: /sepgp ep <name> <amount> [reason]")
        return
    end

    -- Remaining args are the reason
    local reason = nil
    if args[4] then
        local parts = {}
        for i = 4, #args do
            parts[#parts + 1] = args[i]
        end
        reason = table.concat(parts, " ")
    end

    local EPGP = self:GetModule("EPGP")
    local ok = EPGP:ModifyEP(name, amount, reason or "Manual EP adjustment")
    if ok then
        local sign = amount >= 0 and "+" or ""
        self:Print(sign .. amount .. " EP to " .. name .. (reason and (" (" .. reason .. ")") or ""))

        -- Announce if configured
        if self.db.profile.announce_ep and self.db.profile.announce_channel ~= "NONE" then
            SendChatMessage(
                "SimpleEPGP: " .. sign .. amount .. " EP to " .. name .. (reason and (" - " .. reason) or ""),
                self.db.profile.announce_channel
            )
        end
    end
end

--------------------------------------------------------------------------------
-- /sepgp massep <amount> [reason...]
--------------------------------------------------------------------------------

function SimpleEPGP:CmdMassEP(args)
    local amount = tonumber(args[2])
    if not amount then
        self:Print("Usage: /sepgp massep <amount> [reason]")
        return
    end

    local reason = nil
    if args[3] then
        local parts = {}
        for i = 3, #args do
            parts[#parts + 1] = args[i]
        end
        reason = table.concat(parts, " ")
    end

    local EPGP = self:GetModule("EPGP")
    EPGP:MassEP(amount, reason or "Manual mass EP")

    -- Announce if configured
    if self.db.profile.announce_ep and self.db.profile.announce_channel ~= "NONE" then
        SendChatMessage(
            "SimpleEPGP: Awarded " .. amount .. " EP to raid" .. (reason and (" - " .. reason) or ""),
            self.db.profile.announce_channel
        )
    end
end

--------------------------------------------------------------------------------
-- /sepgp gp <name> <amount> [reason...]
--------------------------------------------------------------------------------

function SimpleEPGP:CmdGP(args)
    local name = args[2]
    local amount = tonumber(args[3])
    if not name or not amount then
        self:Print("Usage: /sepgp gp <name> <amount> [reason]")
        return
    end

    local reason = nil
    if args[4] then
        local parts = {}
        for i = 4, #args do
            parts[#parts + 1] = args[i]
        end
        reason = table.concat(parts, " ")
    end

    local EPGP = self:GetModule("EPGP")
    local ok = EPGP:ModifyGP(name, amount, reason or "Manual GP adjustment")
    if ok then
        local sign = amount >= 0 and "+" or ""
        self:Print(sign .. amount .. " GP to " .. name .. (reason and (" (" .. reason .. ")") or ""))
    end
end

--------------------------------------------------------------------------------
-- /sepgp decay  (requires /sepgp confirm)
--------------------------------------------------------------------------------

function SimpleEPGP:CmdDecay()
    local pct = self.db.profile.decay_percent or 0
    if pct <= 0 then
        self:Print("Decay percent is 0, nothing to do.")
        return
    end

    pendingAction = "decay"
    self:Print("|cffff4444WARNING:|r This will apply " .. pct .. "% decay to ALL guild members' EP and GP.")
    self:Print("Type |cff00ff00/sepgp confirm|r to proceed.")
end

--------------------------------------------------------------------------------
-- /sepgp reset  (requires /sepgp confirm)
--------------------------------------------------------------------------------

function SimpleEPGP:CmdReset()
    pendingAction = "reset"
    self:Print("|cffff0000DANGER:|r This will reset ALL EP and GP to 0 for every guild member!")
    self:Print("This action CANNOT be undone.")
    self:Print("Type |cff00ff00/sepgp confirm|r to proceed.")
end

--------------------------------------------------------------------------------
-- /sepgp confirm  (executes pending decay or reset)
--------------------------------------------------------------------------------

function SimpleEPGP:CmdConfirm()
    if not pendingAction then
        self:Print("Nothing to confirm.")
        return
    end

    local EPGP = self:GetModule("EPGP")

    if pendingAction == "decay" then
        pendingAction = nil
        EPGP:Decay()
    elseif pendingAction == "reset" then
        pendingAction = nil
        EPGP:ResetAll()
    else
        pendingAction = nil
        self:Print("Unknown pending action.")
    end
end

--------------------------------------------------------------------------------
-- /sepgp standby add|remove|list [name]
--------------------------------------------------------------------------------

function SimpleEPGP:CmdStandby(args)
    local sub = args[2] and args[2]:lower() or ""
    local name = args[3]

    if sub == "add" then
        if not name then
            self:Print("Usage: /sepgp standby add <name>")
            return
        end
        -- Check for duplicates
        for _, v in ipairs(self.db.standby) do
            if v == name then
                self:Print(name .. " is already on the standby list.")
                return
            end
        end
        self.db.standby[#self.db.standby + 1] = name
        self:Print(name .. " added to standby list.")

    elseif sub == "remove" then
        if not name then
            self:Print("Usage: /sepgp standby remove <name>")
            return
        end
        for i, v in ipairs(self.db.standby) do
            if v == name then
                table.remove(self.db.standby, i)
                self:Print(name .. " removed from standby list.")
                return
            end
        end
        self:Print(name .. " is not on the standby list.")

    elseif sub == "clear" then
        local count = #self.db.standby
        self.db.standby = {}
        self:Print("Standby list cleared (" .. count .. " names removed).")

    elseif sub == "list" then
        local list = self.db.standby
        if #list == 0 then
            self:Print("Standby list is empty.")
        else
            self:Print("Standby list (" .. #list .. "):")
            for i, v in ipairs(list) do
                self:Print("  " .. i .. ". " .. v)
            end
        end

    else
        self:Print("Usage: /sepgp standby add|remove|clear|list [name]")
    end
end

--------------------------------------------------------------------------------
-- /sepgp log [N]
--------------------------------------------------------------------------------

function SimpleEPGP:CmdLog(args)
    local count = tonumber(args[2]) or 20
    local Log = self:GetModule("Log")
    local entries = Log:GetRecent(count)

    if #entries == 0 then
        self:Print("No log entries.")
        return
    end

    self:Print("Last " .. #entries .. " log entries:")
    for _, entry in ipairs(entries) do
        self:Print("  " .. Log:FormatEntry(entry))
    end
end

--------------------------------------------------------------------------------
-- /sepgp top [N]
--------------------------------------------------------------------------------

function SimpleEPGP:CmdTop(args)
    local count = tonumber(args[2]) or 5
    local channel = self.db.profile.announce_channel or "GUILD"
    local Leaderboard = self:GetModule("Leaderboard")
    Leaderboard:AnnounceTop(count, channel)
end

--------------------------------------------------------------------------------
-- /sepgp slot list | <INVTYPE_X> <number|reset>
--------------------------------------------------------------------------------

function SimpleEPGP:CmdSlot(args)
    local sub = args[2] and args[2]:upper() or ""
    local GPCalc = self:GetModule("GPCalc")

    if sub == "" or sub == "LIST" then
        local slots = GPCalc:GetAllSlotInfo()
        self:Print("Slot multipliers:")
        for _, info in ipairs(slots) do
            local tag = info.isOverride and " |cff00ff00(override)|r" or ""
            self:Print(string.format("  %-26s  %.3f%s", info.key, info.current, tag))
        end
        return
    end

    -- sub is a slot name like INVTYPE_HEAD
    if not GPCalc:IsKnownSlot(sub) then
        self:Print("Unknown slot: " .. sub)
        self:Print("Use /sepgp slot list to see all slots.")
        return
    end

    local valueStr = args[3] and args[3]:lower() or ""
    if valueStr == "" then
        local current = GPCalc:GetSlotMultiplier(sub)
        self:Print(sub .. " = " .. tostring(current or 0))
        return
    end

    if valueStr == "reset" then
        GPCalc:ResetSlotMultiplier(sub)
        local default = GPCalc:GetSlotMultiplier(sub)
        self:Print(sub .. " reset to default (" .. tostring(default or 0) .. ").")
        return
    end

    local value = tonumber(valueStr)
    if not value then
        self:Print("Invalid number: " .. valueStr)
        return
    end

    GPCalc:SetSlotMultiplier(sub, value)
    self:Print(sub .. " set to " .. value .. ".")
end

--------------------------------------------------------------------------------
-- /sepgp gpoverride <itemID|link> <gpCost|clear> | list
--------------------------------------------------------------------------------

function SimpleEPGP:CmdGPOverride(args)
    local sub = args[2] and args[2]:lower() or ""
    local GPCalc = self:GetModule("GPCalc")

    if sub == "" then
        self:Print("Usage: /sepgp gpoverride <itemID|link> <gpCost|clear>")
        self:Print("       /sepgp gpoverride list")
        return
    end

    if sub == "list" then
        local overrides = GPCalc:GetAllItemOverrides()
        local sortedIDs = {}
        for id in pairs(overrides) do
            sortedIDs[#sortedIDs + 1] = id
        end
        if #sortedIDs == 0 then
            self:Print("No item GP overrides set.")
        else
            table.sort(sortedIDs)
            self:Print("Item GP overrides (" .. #sortedIDs .. "):")
            for _, itemID in ipairs(sortedIDs) do
                local gpCost = overrides[itemID]
                local name = GetItemInfo(itemID)
                local display = name or ("item:" .. itemID)
                self:Print("  " .. display .. " = " .. gpCost .. " GP")
            end
        end
        return
    end

    -- Parse item ID from link or number
    local itemID = GPCalc:ParseItemID(args[2])
    if not itemID then
        self:Print("Could not parse item ID from: " .. tostring(args[2]))
        return
    end

    local action = args[3] and args[3]:lower() or ""
    if action == "" then
        -- Show current override
        local overrides = GPCalc:GetAllItemOverrides()
        if overrides[itemID] then
            self:Print("Item " .. itemID .. " override: " .. overrides[itemID] .. " GP")
        else
            self:Print("No override set for item " .. itemID .. ".")
        end
        return
    end

    if action == "clear" then
        GPCalc:ClearItemOverride(itemID)
        self:Print("GP override cleared for item " .. itemID .. ".")
        return
    end

    local gpCost = tonumber(action)
    if not gpCost or gpCost < 0 then
        self:Print("Invalid GP cost: " .. action)
        return
    end

    GPCalc:SetItemOverride(itemID, gpCost)
    local name = GetItemInfo(itemID)
    local display = name or ("item:" .. itemID)
    self:Print(display .. " GP override set to " .. gpCost .. ".")
end

--------------------------------------------------------------------------------
-- Usage / Help
--------------------------------------------------------------------------------

function SimpleEPGP:PrintUsage()
    self:Print("SimpleEPGP v" .. ADDON_VERSION .. " commands:")
    self:Print("  /sepgp — Open standings window")
    self:Print("  /sepgp config — Open settings")
    self:Print("  /sepgp gpconfig — Open GP slot/item config")
    self:Print("  /sepgp ep <name> <amount> [reason] — Award/deduct EP")
    self:Print("  /sepgp massep <amount> [reason] — Award EP to raid + standby")
    self:Print("  /sepgp gp <name> <amount> [reason] — Adjust GP")
    self:Print("  /sepgp decay — Apply decay (requires /sepgp confirm)")
    self:Print("  /sepgp standby add|remove|clear|list [name]")
    self:Print("  /sepgp slot list — Show slot multipliers")
    self:Print("  /sepgp slot <INVTYPE_X> <value|reset> — Override slot multiplier")
    self:Print("  /sepgp gpoverride <itemID|link> <gp|clear> — Item GP override")
    self:Print("  /sepgp gpoverride list — List all item overrides")
    self:Print("  /sepgp sync — Request standings from an online officer")
    self:Print("  /sepgp export — Open CSV export window")
    self:Print("  /sepgp log [N] — Show last N log entries")
    self:Print("  /sepgp reset — Reset all EP/GP (requires /sepgp confirm)")
    self:Print("  /sepgp board — Open leaderboard")
    self:Print("  /sepgp top [N] — Announce top N to guild chat")
    self:Print("  /sepgp debug — Debug/testing commands (see /sepgp debug help)")
end
