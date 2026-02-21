-----------------------------------------------------------------------
-- test_log.lua — Unit tests for Log module
-----------------------------------------------------------------------

-- Load stubs first
require("test.wow_stubs")
require("test.ace_stubs")

-- Create the addon (simulates NewAddon call in Core.lua)
local SimpleEPGP = LibStub("AceAddon-3.0"):NewAddon("SimpleEPGP",
    "AceConsole-3.0", "AceEvent-3.0", "AceComm-3.0", "AceSerializer-3.0")

-- Set up default config (simulates AceDB defaults)
SimpleEPGP.db = LibStub("AceDB-3.0"):New("SimpleEPGPDB", {
    profile = {
        base_gp = 100,
        min_ep = 0,
        decay_percent = 15,
        quality_threshold = 4,
        standard_ilvl = 120,
        gp_base_multiplier = nil,
        slot_multipliers = {},
        os_multiplier = 0.5,
        de_multiplier = 0.0,
        ep_per_boss = 100,
        auto_ep_boss = true,
        standby_percent = 1.0,
        bid_timer = 30,
        auto_distribute = false,
        auto_distribute_delay = 3,
        show_gp_tooltip = true,
        announce_channel = "GUILD",
        announce_awards = true,
        announce_ep = true,
    },
}, true)

-- Load the module files (order matches .toc)
dofile("SimpleEPGP/EPGP.lua")
dofile("SimpleEPGP/GPCalc.lua")
dofile("SimpleEPGP/Log.lua")
dofile("SimpleEPGP/Comms.lua")
dofile("SimpleEPGP/LootMaster.lua")

-- Initialize addon (triggers OnInitialize + OnEnable for addon and all modules)
_G._testInitAddon("SimpleEPGP")

describe("Log", function()
    local Log

    before_each(function()
        Log = SimpleEPGP:GetModule("Log")
        -- Clear log entries between tests
        SimpleEPGP.db.log = {}
    end)

    describe("Add", function()
        it("creates entries with correct fields", function()
            Log:Add("EP", "Player1", 500, nil, "Boss kill")
            local log = SimpleEPGP.db.log
            assert.are.equal(1, #log)
            assert.are.equal("EP", log[1].action)
            assert.are.equal("Player1", log[1].player)
            assert.are.equal(500, log[1].amount)
            assert.is_nil(log[1].item)
            assert.are.equal("Boss kill", log[1].reason)
            assert.is_not_nil(log[1].timestamp)
        end)

        it("stores item link when provided", function()
            local link = _G._testItemDB[29759][2]
            Log:Add("AWARD", "Player2", 1000, link, "MS bid")
            local log = SimpleEPGP.db.log
            assert.are.equal(link, log[1].item)
        end)

        it("handles nil player for bulk actions", function()
            Log:Add("MASS_EP", nil, 100, nil, "Boss kill EP")
            local log = SimpleEPGP.db.log
            assert.is_nil(log[1].player)
            assert.are.equal("MASS_EP", log[1].action)
        end)

        it("appends multiple entries in order", function()
            Log:Add("EP", "Player1", 100, nil, "First")
            Log:Add("GP", "Player2", 200, nil, "Second")
            Log:Add("DECAY", nil, 15, nil, "Third")
            local log = SimpleEPGP.db.log
            assert.are.equal(3, #log)
            assert.are.equal("First", log[1].reason)
            assert.are.equal("Second", log[2].reason)
            assert.are.equal("Third", log[3].reason)
        end)
    end)

    describe("GetRecent", function()
        it("returns most recent N entries, newest first", function()
            Log:Add("EP", "Player1", 100, nil, "Entry1")
            Log:Add("EP", "Player2", 200, nil, "Entry2")
            Log:Add("EP", "Player3", 300, nil, "Entry3")
            Log:Add("EP", "Player4", 400, nil, "Entry4")
            Log:Add("EP", "Player5", 500, nil, "Entry5")

            local recent = Log:GetRecent(3)
            assert.are.equal(3, #recent)
            -- Newest first
            assert.are.equal("Entry5", recent[1].reason)
            assert.are.equal("Entry4", recent[2].reason)
            assert.are.equal("Entry3", recent[3].reason)
        end)

        it("returns all entries if fewer than N exist", function()
            Log:Add("EP", "Player1", 100, nil, "Only")
            local recent = Log:GetRecent(20)
            assert.are.equal(1, #recent)
            assert.are.equal("Only", recent[1].reason)
        end)

        it("defaults to 20 entries", function()
            -- Add 25 entries
            for i = 1, 25 do
                Log:Add("EP", "Player1", i, nil, "Entry" .. i)
            end
            local recent = Log:GetRecent()
            assert.are.equal(20, #recent)
            -- First entry should be the newest (Entry25)
            assert.are.equal("Entry25", recent[1].reason)
        end)

        it("returns empty table for empty log", function()
            local recent = Log:GetRecent(5)
            assert.are.equal(0, #recent)
        end)
    end)

    describe("GetAll", function()
        it("returns all entries oldest first", function()
            Log:Add("EP", "Player1", 100, nil, "First")
            Log:Add("EP", "Player2", 200, nil, "Second")
            Log:Add("EP", "Player3", 300, nil, "Third")

            local all = Log:GetAll()
            assert.are.equal(3, #all)
            -- Oldest first (as stored)
            assert.are.equal("First", all[1].reason)
            assert.are.equal("Second", all[2].reason)
            assert.are.equal("Third", all[3].reason)
        end)

        it("returns empty table for empty log", function()
            local all = Log:GetAll()
            assert.are.equal(0, #all)
        end)
    end)

    describe("Prune", function()
        it("keeps only last N entries", function()
            for i = 1, 10 do
                Log:Add("EP", "Player1", i, nil, "Entry" .. i)
            end
            Log:Prune(5)
            local log = SimpleEPGP.db.log
            assert.are.equal(5, #log)
            -- Should keep the 5 most recent (entries 6-10)
            assert.are.equal("Entry6", log[1].reason)
            assert.are.equal("Entry10", log[5].reason)
        end)

        it("does nothing when log is within limit", function()
            Log:Add("EP", "Player1", 100, nil, "Only")
            Log:Prune(500)
            assert.are.equal(1, #SimpleEPGP.db.log)
        end)

        it("defaults to 500 max entries", function()
            for i = 1, 510 do
                Log:Add("EP", "Player1", i, nil, "E" .. i)
            end
            Log:Prune()
            assert.are.equal(500, #SimpleEPGP.db.log)
        end)
    end)

    describe("Clear", function()
        it("empties the log", function()
            Log:Add("EP", "Player1", 100, nil, "Test")
            Log:Add("GP", "Player2", 200, nil, "Test2")
            assert.are.equal(2, #SimpleEPGP.db.log)
            Log:Clear()
            assert.are.equal(0, #SimpleEPGP.db.log)
        end)
    end)

    describe("FormatEntry", function()
        it("produces readable string for EP entry", function()
            Log:Add("EP", "Player1", 500, nil, "Boss kill")
            local entry = SimpleEPGP.db.log[1]
            local formatted = Log:FormatEntry(entry)
            assert.is_not_nil(formatted)
            -- Should contain date, action, player, amount with sign, and reason
            assert.is_truthy(formatted:find("EP"))
            assert.is_truthy(formatted:find("Player1"))
            assert.is_truthy(formatted:find("%+500"))
            assert.is_truthy(formatted:find("Boss kill"))
        end)

        it("produces readable string for DECAY entry", function()
            Log:Add("DECAY", nil, 15, nil, "15% decay applied")
            local entry = SimpleEPGP.db.log[1]
            local formatted = Log:FormatEntry(entry)
            assert.is_truthy(formatted:find("DECAY"))
            assert.is_truthy(formatted:find("15"))
        end)

        it("includes item link when present", function()
            local link = _G._testItemDB[29759][2]
            Log:Add("AWARD", "Player2", 1000, link, "MS bid")
            local entry = SimpleEPGP.db.log[1]
            local formatted = Log:FormatEntry(entry)
            assert.is_truthy(formatted:find("AWARD"))
            assert.is_truthy(formatted:find("Player2"))
            -- Item link should be in the output
            assert.is_truthy(formatted:find("Helm"))
        end)

        it("returns empty string for nil entry", function()
            assert.are.equal("", Log:FormatEntry(nil))
        end)

        it("adds + sign for positive EP amounts", function()
            Log:Add("EP", "Player1", 100, nil, nil)
            local entry = SimpleEPGP.db.log[1]
            local formatted = Log:FormatEntry(entry)
            assert.is_truthy(formatted:find("%+100"))
        end)

        it("no + sign for negative EP amounts", function()
            Log:Add("EP", "Player1", -50, nil, nil)
            local entry = SimpleEPGP.db.log[1]
            local formatted = Log:FormatEntry(entry)
            assert.is_truthy(formatted:find("%-50"))
        end)
    end)

    describe("ExportCSV", function()
        it("produces valid CSV with header", function()
            local csv = Log:ExportCSV()
            assert.is_not_nil(csv)
            -- Should start with header
            assert.is_truthy(csv:find("^timestamp,date,action,player,amount,item,reason"))
        end)

        it("includes data rows", function()
            Log:Add("EP", "Player1", 500, nil, "Boss kill")
            Log:Add("GP", "Player2", 300, nil, "Won item")
            local csv = Log:ExportCSV()

            -- Count lines (header + 2 data rows)
            local lineCount = 0
            for _ in csv:gmatch("[^\n]+") do
                lineCount = lineCount + 1
            end
            assert.are.equal(3, lineCount)
        end)

        it("handles entries with commas in reason", function()
            Log:Add("EP", "Player1", 100, nil, "Some, complex, reason")
            local csv = Log:ExportCSV()
            -- Reason should be quoted in CSV
            assert.is_truthy(csv:find('"Some, complex, reason"'))
        end)

        it("handles entries with quotes in item link", function()
            Log:Add("AWARD", "Player1", 1000, 'item with "quotes"', "test")
            local csv = Log:ExportCSV()
            -- Quotes should be escaped as double-quotes
            assert.is_truthy(csv:find('""quotes""'))
        end)

        it("returns only header for empty log", function()
            local csv = Log:ExportCSV()
            local lineCount = 0
            for _ in csv:gmatch("[^\n]+") do
                lineCount = lineCount + 1
            end
            assert.are.equal(1, lineCount)
        end)
    end)
end)
