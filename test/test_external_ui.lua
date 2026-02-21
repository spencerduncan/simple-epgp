-----------------------------------------------------------------------
-- test_external_ui.lua — Unit tests for external player UI indicators
-- Covers: Standings display, Leaderboard display, ExportFrame CSV
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
        external_players = {},
    },
}, true)

-- Load the module files (order matches .toc)
dofile("SimpleEPGP/EPGP.lua")
dofile("SimpleEPGP/GPCalc.lua")
dofile("SimpleEPGP/Log.lua")
dofile("SimpleEPGP/Comms.lua")
dofile("SimpleEPGP/LootMaster.lua")
dofile("SimpleEPGP/UI/Standings.lua")
dofile("SimpleEPGP/UI/Leaderboard.lua")
dofile("SimpleEPGP/UI/ExportFrame.lua")

-- Initialize addon
_G._testInitAddon("SimpleEPGP")

describe("External Player UI Indicators", function()
    local EPGP, Standings, Leaderboard, ExportFrame

    before_each(function()
        -- Reset officer notes
        _G._testGuildRoster[1].officerNote = "5000,1000"
        _G._testGuildRoster[2].officerNote = "3000,500"
        _G._testGuildRoster[3].officerNote = "2000,2000"
        _G._testGuildRoster[4].officerNote = "1000,100"
        _G._testGuildRoster[5].officerNote = ""

        -- Clear external players
        SimpleEPGP.db.profile.external_players = {}

        EPGP = SimpleEPGP:GetModule("EPGP")
        Standings = SimpleEPGP:GetModule("Standings")
        Leaderboard = SimpleEPGP:GetModule("Leaderboard")
        ExportFrame = SimpleEPGP:GetModule("ExportFrame")

        -- Build standings
        EPGP:GUILD_ROSTER_UPDATE()

        -- Reset UI state
        Standings:SetRaidFilter(false)
        Leaderboard:SetGrouping("none")
        Leaderboard:SetFilter("all")
    end)

    describe("Standings display", function()
        before_each(function()
            Standings:Show()
        end)

        after_each(function()
            Standings:Hide()
        end)

        it("includes external players in display data", function()
            EPGP:AddExternalPlayer("Pugman", "WARRIOR")
            EPGP:GUILD_ROSTER_UPDATE()
            Standings:Show()  -- refresh

            local data = Standings:GetDisplayData()
            local found = false
            for _, entry in ipairs(data) do
                if entry.name == "Pugman" then
                    found = true
                    break
                end
            end
            assert.is_true(found, "Expected Pugman in standings display")
        end)

        it("external players have isExternal flag in display data", function()
            EPGP:AddExternalPlayer("Pugman", "HUNTER")
            EPGP:GUILD_ROSTER_UPDATE()
            Standings:Show()

            local data = Standings:GetDisplayData()
            for _, entry in ipairs(data) do
                if entry.name == "Pugman" then
                    assert.is_true(entry.isExternal)
                end
            end
        end)

        it("guild members do NOT have isExternal flag in display data", function()
            EPGP:AddExternalPlayer("Pugman", "WARRIOR")
            EPGP:GUILD_ROSTER_UPDATE()
            Standings:Show()

            local data = Standings:GetDisplayData()
            for _, entry in ipairs(data) do
                if entry.name == "Player1" then
                    assert.is_nil(entry.isExternal)
                end
            end
        end)

        it("shows external and guild players together sorted by PR", function()
            EPGP:AddExternalPlayer("Pugman", "WARRIOR")
            SimpleEPGP.db.profile.external_players["Pugman"].ep = 10000
            EPGP:GUILD_ROSTER_UPDATE()
            Standings:Show()

            local data = Standings:GetDisplayData()
            -- Pugman has highest PR (10000/100 = 100), should be first
            assert.are.equal("Pugman", data[1].name)
            assert.is_true(data[1].isExternal)

            -- Verify overall PR ordering
            for i = 2, #data do
                assert.is_true(data[i - 1].pr >= data[i].pr,
                    "Expected PR descending order at index " .. i)
            end
        end)

        it("external players counted in total display rows", function()
            EPGP:AddExternalPlayer("Pugman", "WARRIOR")
            EPGP:AddExternalPlayer("Allyheals", "PRIEST")
            EPGP:GUILD_ROSTER_UPDATE()
            Standings:Show()

            local data = Standings:GetDisplayData()
            -- 5 guild members + 2 external = 7
            assert.are.equal(7, #data)
        end)
    end)

    describe("Leaderboard display", function()
        before_each(function()
            Leaderboard:Show()
        end)

        after_each(function()
            Leaderboard:Hide()
        end)

        it("includes external players in display items", function()
            EPGP:AddExternalPlayer("Pugman", "WARRIOR")
            EPGP:GUILD_ROSTER_UPDATE()
            Leaderboard:Show()

            local items = Leaderboard:GetDisplayItems()
            local found = false
            for _, item in ipairs(items) do
                if item.type == "row" and item.entry.name == "Pugman" then
                    found = true
                    break
                end
            end
            assert.is_true(found, "Expected Pugman in leaderboard display")
        end)

        it("external players have isExternal flag in leaderboard items", function()
            EPGP:AddExternalPlayer("Pugman", "HUNTER")
            EPGP:GUILD_ROSTER_UPDATE()
            Leaderboard:Show()

            local items = Leaderboard:GetDisplayItems()
            for _, item in ipairs(items) do
                if item.type == "row" and item.entry.name == "Pugman" then
                    assert.is_true(item.entry.isExternal)
                end
            end
        end)

        it("guild members do NOT have isExternal flag in leaderboard items", function()
            EPGP:AddExternalPlayer("Pugman", "WARRIOR")
            EPGP:GUILD_ROSTER_UPDATE()
            Leaderboard:Show()

            local items = Leaderboard:GetDisplayItems()
            for _, item in ipairs(items) do
                if item.type == "row" and item.entry.name == "Player1" then
                    assert.is_nil(item.entry.isExternal)
                end
            end
        end)

        it("external players appear in class grouping", function()
            EPGP:AddExternalPlayer("Pugman", "WARRIOR")
            EPGP:GUILD_ROSTER_UPDATE()
            Leaderboard:SetGrouping("class")
            Leaderboard:Show()

            local items = Leaderboard:GetDisplayItems()
            -- Find the Warrior header — should include Pugman + Player1
            local warriorHeader = nil
            for _, item in ipairs(items) do
                if item.type == "header" and item.key == "WARRIOR" then
                    warriorHeader = item
                end
            end
            assert.is_not_nil(warriorHeader)
            assert.are.equal(2, warriorHeader.count)
        end)

        it("external players appear in role grouping", function()
            EPGP:AddExternalPlayer("Pugman", "HUNTER")
            EPGP:GUILD_ROSTER_UPDATE()
            Leaderboard:SetGrouping("role")
            Leaderboard:Show()

            local items = Leaderboard:GetDisplayItems()
            -- Hunter maps to DPS. Player3 is HUNTER, Player4 is MAGE = 2 DPS + Pugman = 3
            local dpsHeader = nil
            for _, item in ipairs(items) do
                if item.type == "header" and item.key == "DPS" then
                    dpsHeader = item
                end
            end
            assert.is_not_nil(dpsHeader)
            assert.are.equal(3, dpsHeader.count)
        end)

        it("external player count in display items is correct", function()
            EPGP:AddExternalPlayer("Pugman", "WARRIOR")
            EPGP:AddExternalPlayer("Allyheals", "PRIEST")
            EPGP:GUILD_ROSTER_UPDATE()
            Leaderboard:Show()

            local items = Leaderboard:GetDisplayItems()
            -- 5 guild + 2 external = 7 rows
            assert.are.equal(7, #items)
            for _, item in ipairs(items) do
                assert.are.equal("row", item.type)
            end
        end)
    end)

    describe("ExportFrame CSV", function()
        it("includes Source column header", function()
            EPGP:GUILD_ROSTER_UPDATE()
            local csv = ExportFrame:GetStandingsCSV()
            local firstLine = csv:match("^([^\n]+)")
            assert.are.equal("Name,Class,EP,GP,PR,Source", firstLine)
        end)

        it("guild members have 'guild' source", function()
            EPGP:GUILD_ROSTER_UPDATE()
            local csv = ExportFrame:GetStandingsCSV()
            -- Player1 should appear with ,guild at the end
            assert.is_truthy(csv:find("Player1,WARRIOR,%d+,%d+,[%d%.]+,guild"))
        end)

        it("external players have 'external' source", function()
            EPGP:AddExternalPlayer("Pugman", "WARRIOR")
            EPGP:GUILD_ROSTER_UPDATE()
            local csv = ExportFrame:GetStandingsCSV()
            assert.is_truthy(csv:find("Pugman,WARRIOR,%d+,%d+,[%d%.]+,external"))
        end)

        it("mixed guild and external players have correct sources", function()
            EPGP:AddExternalPlayer("Pugman", "HUNTER")
            EPGP:AddExternalPlayer("Allyheals", "PRIEST")
            EPGP:GUILD_ROSTER_UPDATE()
            local csv = ExportFrame:GetStandingsCSV()

            -- Count guild and external sources
            local guildCount = 0
            local externalCount = 0
            for line in csv:gmatch("[^\n]+") do
                if line:match(",guild$") then
                    guildCount = guildCount + 1
                elseif line:match(",external$") then
                    externalCount = externalCount + 1
                end
            end
            assert.are.equal(5, guildCount, "Expected 5 guild entries")
            assert.are.equal(2, externalCount, "Expected 2 external entries")
        end)

        it("CSV has correct number of columns per row", function()
            EPGP:AddExternalPlayer("Pugman", "WARRIOR")
            EPGP:GUILD_ROSTER_UPDATE()
            local csv = ExportFrame:GetStandingsCSV()

            for line in csv:gmatch("[^\n]+") do
                -- Count commas: 5 commas = 6 columns
                local _, commaCount = line:gsub(",", ",")
                assert.are.equal(5, commaCount,
                    "Expected 6 columns (5 commas) in: " .. line)
            end
        end)

        it("CSV with no external players has all guild sources", function()
            EPGP:GUILD_ROSTER_UPDATE()
            local csv = ExportFrame:GetStandingsCSV()

            local externalCount = 0
            for line in csv:gmatch("[^\n]+") do
                if line:match(",external$") then
                    externalCount = externalCount + 1
                end
            end
            assert.are.equal(0, externalCount, "Expected no external entries")
        end)
    end)
end)
