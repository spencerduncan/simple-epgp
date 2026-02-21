-----------------------------------------------------------------------
-- test_epgp.lua — Unit tests for EPGP module
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

describe("EPGP", function()
    local EPGP

    before_each(function()
        -- Reset state between tests
        -- Restore test guild roster to defaults
        _G._testGuildRoster[1].officerNote = "5000,1000"
        _G._testGuildRoster[2].officerNote = "3000,500"
        _G._testGuildRoster[3].officerNote = "2000,2000"
        _G._testGuildRoster[4].officerNote = "1000,100"
        _G._testGuildRoster[5].officerNote = ""
        EPGP = SimpleEPGP:GetModule("EPGP")
    end)

    describe("ParseNote", function()
        it("parses valid EP,GP note", function()
            local ep, gp = EPGP:ParseNote("5000,1000")
            assert.are.equal(5000, ep)
            assert.are.equal(1000, gp)
        end)
        it("returns nil for empty note", function()
            assert.is_nil(EPGP:ParseNote(""))
        end)
        it("returns nil for non-numeric note", function()
            assert.is_nil(EPGP:ParseNote("hello"))
        end)
        it("returns nil for nil input", function()
            assert.is_nil(EPGP:ParseNote(nil))
        end)
        it("parses zero values", function()
            local ep, gp = EPGP:ParseNote("0,0")
            assert.are.equal(0, ep)
            assert.are.equal(0, gp)
        end)
        it("parses large values", function()
            local ep, gp = EPGP:ParseNote("99999,99999")
            assert.are.equal(99999, ep)
            assert.are.equal(99999, gp)
        end)
    end)

    describe("EncodeNote", function()
        it("encodes EP,GP as string", function()
            assert.are.equal("1500,300", EPGP:EncodeNote(1500, 300))
        end)
        it("floors fractional values", function()
            assert.are.equal("1500,299", EPGP:EncodeNote(1500.7, 299.9))
        end)
        it("handles zero", function()
            assert.are.equal("0,0", EPGP:EncodeNote(0, 0))
        end)
        it("roundtrips with ParseNote", function()
            -- THE fundamental correctness invariant
            local testCases = {
                {0, 0}, {100, 50}, {1500, 300}, {99999, 99999},
                {5000, 1000}, {1, 1},
            }
            for _, tc in ipairs(testCases) do
                local ep, gp = tc[1], tc[2]
                local encoded = EPGP:EncodeNote(ep, gp)
                local parsedEP, parsedGP = EPGP:ParseNote(encoded)
                assert.are.equal(ep, parsedEP,
                    "EP roundtrip failed for " .. ep)
                assert.are.equal(gp, parsedGP,
                    "GP roundtrip failed for " .. gp)
            end
        end)
    end)

    describe("Standings", function()
        it("builds standings from guild roster", function()
            -- Fire GUILD_ROSTER_UPDATE to build standings
            EPGP:GUILD_ROSTER_UPDATE()
            local standings = EPGP:GetStandings()
            assert.is_not_nil(standings)
            assert.is_true(#standings >= 4)  -- 4 members have EPGP notes
        end)

        it("sorts by PR descending", function()
            EPGP:GUILD_ROSTER_UPDATE()
            local standings = EPGP:GetStandings()
            for i = 2, #standings do
                assert.is_true(standings[i-1].pr >= standings[i].pr)
            end
        end)

        it("calculates PR correctly", function()
            -- Player1: EP=5000, GP=1000, base_gp=100 -> PR = 5000/1100 ~ 4.545
            EPGP:GUILD_ROSTER_UPDATE()
            local info = EPGP:GetPlayerInfo("Player1")
            assert.is_not_nil(info)
            local expectedPR = 5000 / (1000 + 100)
            assert.is_true(math.abs(info.pr - expectedPR) < 0.01)
        end)

        it("applies min_ep threshold", function()
            SimpleEPGP.db.profile.min_ep = 2500
            EPGP:GUILD_ROSTER_UPDATE()
            -- Player4 has EP=1000, below min_ep -> PR should be 0
            local info = EPGP:GetPlayerInfo("Player4")
            assert.are.equal(0, info.pr)
            SimpleEPGP.db.profile.min_ep = 0  -- reset
        end)

        it("handles empty officer note as 0,0", function()
            EPGP:GUILD_ROSTER_UPDATE()
            local info = EPGP:GetPlayerInfo("Player5")
            assert.are.equal(0, info.ep)
            assert.are.equal(0, info.gp)
        end)
    end)

    describe("ModifyEP", function()
        it("adds EP to a player", function()
            EPGP:GUILD_ROSTER_UPDATE()
            EPGP:ModifyEP("Player1", 500, "Boss kill")
            -- Check officer note was updated
            assert.are.equal("5500,1000", _G._testGuildRoster[1].officerNote)
        end)

        it("prevents EP from going below 0", function()
            EPGP:GUILD_ROSTER_UPDATE()
            EPGP:ModifyEP("Player4", -2000, "Penalty")
            assert.are.equal("0,100", _G._testGuildRoster[4].officerNote)
        end)

        it("returns false for unknown player", function()
            local result = EPGP:ModifyEP("NonExistent", 100, "Test")
            assert.is_false(result)
        end)
    end)

    describe("ModifyGP", function()
        it("adds GP to a player", function()
            EPGP:GUILD_ROSTER_UPDATE()
            EPGP:ModifyGP("Player2", 300, "Won item")
            assert.are.equal("3000,800", _G._testGuildRoster[2].officerNote)
        end)

        it("prevents GP from going below 0", function()
            EPGP:GUILD_ROSTER_UPDATE()
            EPGP:ModifyGP("Player4", -500, "Correction")
            assert.are.equal("1000,0", _G._testGuildRoster[4].officerNote)
        end)

        it("returns false for unknown player", function()
            local result = EPGP:ModifyGP("NonExistent", 100, "Test")
            assert.is_false(result)
        end)
    end)

    describe("GetPlayerInfo", function()
        it("returns nil for unknown player", function()
            EPGP:GUILD_ROSTER_UPDATE()
            assert.is_nil(EPGP:GetPlayerInfo("NonExistent"))
        end)
    end)

    describe("MassEP", function()
        it("awards EP to all raid members", function()
            EPGP:GUILD_ROSTER_UPDATE()
            -- Raid has 5 members (Player1-Player5 per wow_stubs)
            EPGP:MassEP(200, "Boss kill")
            -- Player1: 5000+200=5200, GP unchanged
            assert.are.equal("5200,1000", _G._testGuildRoster[1].officerNote)
            -- Player2: 3000+200=3200
            assert.are.equal("3200,500", _G._testGuildRoster[2].officerNote)
            -- Player3: 2000+200=2200
            assert.are.equal("2200,2000", _G._testGuildRoster[3].officerNote)
        end)

        it("awards standby EP when configured", function()
            EPGP:GUILD_ROSTER_UPDATE()
            -- Set up standby list
            SimpleEPGP.db.standby = { "Player5" }
            SimpleEPGP.db.profile.standby_percent = 0.5 -- 50%
            -- Player5 has "" officer note (0,0)
            _G._testGuildRoster[5].officerNote = "0,0"
            EPGP:GUILD_ROSTER_UPDATE()

            EPGP:MassEP(200, "Boss kill")
            -- Player5 is in raid AND standby, so gets raid EP (200) from raid loop
            -- and then standby EP (100) from standby loop = 300 total
            -- Wait, no - the standby list iteration uses FindRosterIndex
            -- Player5 is in raid roster too, so gets 200 from raid + 100 from standby
            -- Actually, let me re-check. MassEP iterates GetRaidRosterInfo (raid members)
            -- then separately iterates db.standby. Player5 IS in raid (wow_stubs has 5 raid members)
            -- So Player5 gets 200 from raid loop, THEN 100 from standby loop.
            -- This means Player5 gets 300 total. That's the correct behavior per plan
            -- (standby can overlap with raid — the guild manages the list).
            -- Actually, in a real scenario, standby players would NOT be in the raid.
            -- But our stubs have them in both. Let's just test the math works.
            -- Player5 starts at 0,0 -> +200 (raid) -> +100 (standby) -> 300,0
            assert.are.equal("300,0", _G._testGuildRoster[5].officerNote)

            -- Reset
            SimpleEPGP.db.standby = {}
            SimpleEPGP.db.profile.standby_percent = 1.0
        end)

        it("skips standby when standby_percent is 0", function()
            EPGP:GUILD_ROSTER_UPDATE()
            SimpleEPGP.db.standby = { "Player5" }
            SimpleEPGP.db.profile.standby_percent = 0
            _G._testGuildRoster[5].officerNote = "0,0"
            EPGP:GUILD_ROSTER_UPDATE()

            EPGP:MassEP(200, "Boss kill")
            -- Player5 gets raid EP (200) but no standby EP (percent=0)
            assert.are.equal("200,0", _G._testGuildRoster[5].officerNote)

            -- Reset
            SimpleEPGP.db.standby = {}
            SimpleEPGP.db.profile.standby_percent = 1.0
        end)
    end)

    describe("Decay", function()
        it("applies decay percentage to all members", function()
            EPGP:GUILD_ROSTER_UPDATE()
            EPGP:Decay()
            -- Player1: EP=5000*0.85=4250, GP=1000*0.85=850
            assert.are.equal("4250,850", _G._testGuildRoster[1].officerNote)
            -- Player2: EP=3000*0.85=2550, GP=500*0.85=425
            assert.are.equal("2550,425", _G._testGuildRoster[2].officerNote)
        end)

        it("floors decayed values", function()
            _G._testGuildRoster[4].officerNote = "1001,101"
            EPGP:GUILD_ROSTER_UPDATE()
            EPGP:Decay()
            -- 1001*0.85 = 850.85 -> 850, 101*0.85 = 85.85 -> 85
            assert.are.equal("850,85", _G._testGuildRoster[4].officerNote)
        end)

        it("skips members with 0,0", function()
            _G._testGuildRoster[5].officerNote = "0,0"
            EPGP:GUILD_ROSTER_UPDATE()
            EPGP:Decay()
            -- Should still be 0,0 (not processed)
            assert.are.equal("0,0", _G._testGuildRoster[5].officerNote)
        end)

        it("returns false when decay_percent is 0", function()
            SimpleEPGP.db.profile.decay_percent = 0
            EPGP:GUILD_ROSTER_UPDATE()
            local result = EPGP:Decay()
            assert.is_false(result)
            -- Values should be unchanged
            assert.are.equal("5000,1000", _G._testGuildRoster[1].officerNote)
            SimpleEPGP.db.profile.decay_percent = 15  -- reset
        end)
    end)
end)
