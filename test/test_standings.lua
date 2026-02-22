-----------------------------------------------------------------------
-- test_standings.lua — Unit tests for Standings UI module (raid filter)
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
dofile("SimpleEPGP/UI/Utils.lua")
dofile("SimpleEPGP/UI/Standings.lua")

-- Initialize addon
_G._testInitAddon("SimpleEPGP")

describe("Standings", function()
    local Standings
    local EPGP

    before_each(function()
        -- Reset officer notes to defaults
        _G._testGuildRoster[1].officerNote = "5000,1000"
        _G._testGuildRoster[2].officerNote = "3000,500"
        _G._testGuildRoster[3].officerNote = "2000,2000"
        _G._testGuildRoster[4].officerNote = "1000,100"
        _G._testGuildRoster[5].officerNote = ""

        Standings = SimpleEPGP:GetModule("Standings")
        EPGP = SimpleEPGP:GetModule("EPGP")

        -- Build standings from guild roster
        EPGP:GUILD_ROSTER_UPDATE()

        -- Reset filter state
        Standings:SetRaidFilter(false)

        -- Open the standings window so RefreshDisplay runs
        Standings:Show()
    end)

    after_each(function()
        Standings:Hide()
    end)

    describe("GetDisplayData without filter", function()
        it("shows all guild members", function()
            local data = Standings:GetDisplayData()
            -- Guild has 5 members total (4 with EPGP notes + 1 with empty note)
            assert.are.equal(5, #data)
        end)

        it("sorts by PR descending by default", function()
            local data = Standings:GetDisplayData()
            for i = 2, #data do
                assert.is_true(data[i - 1].pr >= data[i].pr,
                    "Expected PR descending order at index " .. i)
            end
        end)
    end)

    describe("Raid filter", function()
        it("filters to only raid members when enabled", function()
            -- Raid roster (from wow_stubs) has 5 members:
            -- Player1-Player5 (all in raid)
            -- Guild roster also has 5 members (same names).
            -- So with filter on, should still show all 5 since all are in raid.
            Standings:SetRaidFilter(true)
            assert.is_true(Standings:GetRaidFilter())

            local data = Standings:GetDisplayData()
            assert.are.equal(5, #data)
        end)

        it("excludes non-raid members", function()
            -- Temporarily modify the raid roster to only have 3 members
            local savedRoster = {}
            for i, v in ipairs(_G._testRaidRoster) do
                savedRoster[i] = v
            end
            -- Keep only Player1, Player2, Player3 in raid
            _G._testRaidRoster[4] = nil
            _G._testRaidRoster[5] = nil

            -- Override GetNumGroupMembers to match
            local origGetNum = _G.GetNumGroupMembers
            _G.GetNumGroupMembers = function() return 3 end

            Standings:SetRaidFilter(true)
            local data = Standings:GetDisplayData()
            assert.are.equal(3, #data)

            -- Verify the correct players are shown
            local names = {}
            for _, entry in ipairs(data) do
                names[entry.name] = true
            end
            assert.is_true(names["Player1"])
            assert.is_true(names["Player2"])
            assert.is_true(names["Player3"])
            assert.is_nil(names["Player4"])
            assert.is_nil(names["Player5"])

            -- Restore
            for i, v in ipairs(savedRoster) do
                _G._testRaidRoster[i] = v
            end
            _G.GetNumGroupMembers = origGetNum
        end)

        it("shows all members when filter is disabled", function()
            Standings:SetRaidFilter(true)
            Standings:SetRaidFilter(false)
            assert.is_false(Standings:GetRaidFilter())

            local data = Standings:GetDisplayData()
            assert.are.equal(5, #data)
        end)

        it("shows empty list when not in a raid", function()
            -- Override IsInRaid to return false
            local origIsInRaid = _G.IsInRaid
            _G.IsInRaid = function() return false end

            Standings:SetRaidFilter(true)
            local data = Standings:GetDisplayData()
            assert.are.equal(0, #data)

            -- Restore
            _G.IsInRaid = origIsInRaid
        end)

        it("maintains sort order when filtered", function()
            Standings:SetRaidFilter(true)
            local data = Standings:GetDisplayData()
            for i = 2, #data do
                assert.is_true(data[i - 1].pr >= data[i].pr,
                    "Expected PR descending order at index " .. i)
            end
        end)

        it("toggles correctly via GetRaidFilter/SetRaidFilter", function()
            assert.is_false(Standings:GetRaidFilter())
            Standings:SetRaidFilter(true)
            assert.is_true(Standings:GetRaidFilter())
            Standings:SetRaidFilter(false)
            assert.is_false(Standings:GetRaidFilter())
        end)
    end)
end)
