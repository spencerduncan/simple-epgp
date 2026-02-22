-----------------------------------------------------------------------
-- test_epgp_helpers.lua — Unit tests for CalculatePR and ModifyNote helpers
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

describe("EPGP Helpers", function()
    local EPGP

    before_each(function()
        -- Reset state between tests
        _G._testGuildRoster[1].officerNote = "5000,1000"
        _G._testGuildRoster[2].officerNote = "3000,500"
        _G._testGuildRoster[3].officerNote = "2000,2000"
        _G._testGuildRoster[4].officerNote = "1000,100"
        _G._testGuildRoster[5].officerNote = ""
        SimpleEPGP.db.profile.base_gp = 100
        SimpleEPGP.db.profile.min_ep = 0
        EPGP = SimpleEPGP:GetModule("EPGP")
    end)

    describe("CalculatePR", function()
        it("computes PR as EP / (GP + baseGP)", function()
            -- EP=5000, GP=1000, base_gp=100 -> PR = 5000/1100
            local pr = EPGP:CalculatePR(5000, 1000)
            local expected = 5000 / (1000 + 100)
            assert.is_true(math.abs(pr - expected) < 0.0001)
        end)

        it("returns 0 when EP is below min_ep", function()
            SimpleEPGP.db.profile.min_ep = 2000
            local pr = EPGP:CalculatePR(1000, 500)
            assert.are.equal(0, pr)
        end)

        it("returns PR when EP equals min_ep", function()
            SimpleEPGP.db.profile.min_ep = 1000
            local pr = EPGP:CalculatePR(1000, 500)
            local expected = 1000 / (500 + 100)
            assert.is_true(math.abs(pr - expected) < 0.0001)
        end)

        it("returns 0 when EP is 0 and min_ep is 0", function()
            local pr = EPGP:CalculatePR(0, 0)
            assert.are.equal(0, pr)
        end)

        it("uses base_gp from config", function()
            SimpleEPGP.db.profile.base_gp = 200
            local pr = EPGP:CalculatePR(1000, 0)
            -- EP=1000, GP=0, base_gp=200 -> PR = 1000/200 = 5.0
            assert.are.equal(1000 / 200, pr)
        end)

        it("handles negative GP by flooring to 0 before adding baseGP", function()
            -- GP of -50 should be treated as max(-50, 0) = 0
            local pr = EPGP:CalculatePR(1000, -50)
            local expected = 1000 / (0 + 100)  -- effectiveGP = max(-50, 0) + 100 = 100
            assert.are.equal(expected, pr)
        end)

        it("defaults base_gp to 1 when nil", function()
            SimpleEPGP.db.profile.base_gp = nil
            local pr = EPGP:CalculatePR(100, 0)
            -- base_gp defaults to 1, so PR = 100 / (0 + 1) = 100
            assert.are.equal(100, pr)
        end)

        it("defaults min_ep to 0 when nil", function()
            SimpleEPGP.db.profile.min_ep = nil
            local pr = EPGP:CalculatePR(100, 0)
            -- min_ep defaults to 0, EP=100 >= 0, so PR is computed
            assert.is_true(pr > 0)
        end)

        it("produces same result as inline code for standings data", function()
            -- Verify the helper matches what GUILD_ROSTER_UPDATE now computes
            EPGP:GUILD_ROSTER_UPDATE()
            local info = EPGP:GetPlayerInfo("Player1")
            local helperPR = EPGP:CalculatePR(5000, 1000)
            assert.are.equal(helperPR, info.pr)
        end)

        it("handles large EP and GP values", function()
            local pr = EPGP:CalculatePR(99999, 99999)
            local expected = 99999 / (99999 + 100)
            assert.is_true(math.abs(pr - expected) < 0.0001)
        end)
    end)

    describe("ModifyNote", function()
        it("adds EP delta to officer note", function()
            -- Player1 starts at "5000,1000"
            local newEP, newGP = EPGP:ModifyNote(1, 500, 0)
            assert.are.equal(5500, newEP)
            assert.are.equal(1000, newGP)
            assert.are.equal("5500,1000", _G._testGuildRoster[1].officerNote)
        end)

        it("adds GP delta to officer note", function()
            -- Player2 starts at "3000,500"
            local newEP, newGP = EPGP:ModifyNote(2, 0, 300)
            assert.are.equal(3000, newEP)
            assert.are.equal(800, newGP)
            assert.are.equal("3000,800", _G._testGuildRoster[2].officerNote)
        end)

        it("adds both EP and GP deltas simultaneously", function()
            -- Player3 starts at "2000,2000"
            local newEP, newGP = EPGP:ModifyNote(3, 100, 200)
            assert.are.equal(2100, newEP)
            assert.are.equal(2200, newGP)
            assert.are.equal("2100,2200", _G._testGuildRoster[3].officerNote)
        end)

        it("floors EP to 0 when delta is negative and exceeds current", function()
            -- Player4 starts at "1000,100"
            local newEP, newGP = EPGP:ModifyNote(4, -2000, 0)
            assert.are.equal(0, newEP)
            assert.are.equal(100, newGP)
            assert.are.equal("0,100", _G._testGuildRoster[4].officerNote)
        end)

        it("floors GP to 0 when delta is negative and exceeds current", function()
            -- Player4 starts at "1000,100"
            local newEP, newGP = EPGP:ModifyNote(4, 0, -500)
            assert.are.equal(1000, newEP)
            assert.are.equal(0, newGP)
            assert.are.equal("1000,0", _G._testGuildRoster[4].officerNote)
        end)

        it("handles empty officer note as 0,0", function()
            -- Player5 has empty officer note
            local newEP, newGP = EPGP:ModifyNote(5, 200, 50)
            assert.are.equal(200, newEP)
            assert.are.equal(50, newGP)
            assert.are.equal("200,50", _G._testGuildRoster[5].officerNote)
        end)

        it("returns the new EP and GP values", function()
            local newEP, newGP = EPGP:ModifyNote(1, 100, 200)
            assert.are.equal(5100, newEP)
            assert.are.equal(1200, newGP)
        end)

        it("handles negative EP delta that reduces to exactly 0", function()
            -- Player4 starts at "1000,100", subtract exactly 1000 EP
            local newEP, newGP = EPGP:ModifyNote(4, -1000, 0)
            assert.are.equal(0, newEP)
            assert.are.equal(100, newGP)
            assert.are.equal("0,100", _G._testGuildRoster[4].officerNote)
        end)

        it("handles zero deltas (no change)", function()
            local newEP, newGP = EPGP:ModifyNote(1, 0, 0)
            assert.are.equal(5000, newEP)
            assert.are.equal(1000, newGP)
            assert.are.equal("5000,1000", _G._testGuildRoster[1].officerNote)
        end)

        it("preserves existing values when only EP changes", function()
            EPGP:ModifyNote(2, 500, 0)
            -- GP should remain unchanged at 500
            assert.are.equal("3500,500", _G._testGuildRoster[2].officerNote)
        end)

        it("preserves existing values when only GP changes", function()
            EPGP:ModifyNote(2, 0, 100)
            -- EP should remain unchanged at 3000
            assert.are.equal("3000,600", _G._testGuildRoster[2].officerNote)
        end)

        it("roundtrips correctly through ParseNote and EncodeNote", function()
            -- Modify, then parse the result — should match returned values
            local newEP, newGP = EPGP:ModifyNote(1, 123, 456)
            local parsedEP, parsedGP = EPGP:ParseNote(_G._testGuildRoster[1].officerNote)
            assert.are.equal(newEP, parsedEP)
            assert.are.equal(newGP, parsedGP)
        end)
    end)
end)
