-----------------------------------------------------------------------
-- test_external_decay.lua — Tests for decay and reset of external players
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

-- Initialize addon (triggers OnInitialize + OnEnable for addon and all modules)
_G._testInitAddon("SimpleEPGP")

describe("External player decay and reset", function()
    local EPGP

    before_each(function()
        -- Reset guild roster to defaults
        _G._testGuildRoster[1].officerNote = "5000,1000"
        _G._testGuildRoster[2].officerNote = "3000,500"
        _G._testGuildRoster[3].officerNote = "2000,2000"
        _G._testGuildRoster[4].officerNote = "1000,100"
        _G._testGuildRoster[5].officerNote = ""

        -- Clear external players
        SimpleEPGP.db.profile.external_players = {}

        -- Reset decay percent to default
        SimpleEPGP.db.profile.decay_percent = 15

        EPGP = SimpleEPGP:GetModule("EPGP")
    end)

    describe("Decay with external players", function()
        it("applies decay multiplier to external player EP and GP", function()
            EPGP:AddExternalPlayer("Pugman", "WARRIOR")
            SimpleEPGP.db.profile.external_players["Pugman"].ep = 1000
            SimpleEPGP.db.profile.external_players["Pugman"].gp = 500
            EPGP:GUILD_ROSTER_UPDATE()

            EPGP:Decay()

            local ext = SimpleEPGP.db.profile.external_players["Pugman"]
            -- 15% decay: multiplier = 0.85
            -- EP: floor(1000 * 0.85) = 850
            -- GP: floor(500 * 0.85) = 425
            assert.are.equal(850, ext.ep)
            assert.are.equal(425, ext.gp)
        end)

        it("floors fractional decay values for external players", function()
            EPGP:AddExternalPlayer("Pugman", "WARRIOR")
            SimpleEPGP.db.profile.external_players["Pugman"].ep = 1001
            SimpleEPGP.db.profile.external_players["Pugman"].gp = 101
            EPGP:GUILD_ROSTER_UPDATE()

            EPGP:Decay()

            local ext = SimpleEPGP.db.profile.external_players["Pugman"]
            -- EP: floor(1001 * 0.85) = floor(850.85) = 850
            -- GP: floor(101 * 0.85) = floor(85.85) = 85
            assert.are.equal(850, ext.ep)
            assert.are.equal(85, ext.gp)
        end)

        it("skips external players with 0 EP and 0 GP", function()
            EPGP:AddExternalPlayer("Pugman", "WARRIOR")
            -- EP=0, GP=0 by default after AddExternalPlayer
            local initialModifiedAt = SimpleEPGP.db.profile.external_players["Pugman"].modified_at
            EPGP:GUILD_ROSTER_UPDATE()

            EPGP:Decay()

            local ext = SimpleEPGP.db.profile.external_players["Pugman"]
            assert.are.equal(0, ext.ep)
            assert.are.equal(0, ext.gp)
            -- modified_at should not have been updated (player was skipped)
            assert.are.equal(initialModifiedAt, ext.modified_at)
        end)

        it("decays external player with EP > 0 but GP = 0", function()
            EPGP:AddExternalPlayer("Pugman", "WARRIOR")
            SimpleEPGP.db.profile.external_players["Pugman"].ep = 500
            SimpleEPGP.db.profile.external_players["Pugman"].gp = 0
            EPGP:GUILD_ROSTER_UPDATE()

            EPGP:Decay()

            local ext = SimpleEPGP.db.profile.external_players["Pugman"]
            -- EP: floor(500 * 0.85) = 425
            -- GP: floor(0 * 0.85) = 0
            assert.are.equal(425, ext.ep)
            assert.are.equal(0, ext.gp)
        end)

        it("decays external player with EP = 0 but GP > 0", function()
            EPGP:AddExternalPlayer("Pugman", "WARRIOR")
            SimpleEPGP.db.profile.external_players["Pugman"].ep = 0
            SimpleEPGP.db.profile.external_players["Pugman"].gp = 200
            EPGP:GUILD_ROSTER_UPDATE()

            EPGP:Decay()

            local ext = SimpleEPGP.db.profile.external_players["Pugman"]
            -- EP: floor(0 * 0.85) = 0
            -- GP: floor(200 * 0.85) = 170
            assert.are.equal(0, ext.ep)
            assert.are.equal(170, ext.gp)
        end)

        it("uses the correct decay multiplier", function()
            SimpleEPGP.db.profile.decay_percent = 20
            EPGP:AddExternalPlayer("Pugman", "WARRIOR")
            SimpleEPGP.db.profile.external_players["Pugman"].ep = 1000
            SimpleEPGP.db.profile.external_players["Pugman"].gp = 1000
            EPGP:GUILD_ROSTER_UPDATE()

            EPGP:Decay()

            local ext = SimpleEPGP.db.profile.external_players["Pugman"]
            -- 20% decay: multiplier = 0.80
            -- EP: floor(1000 * 0.80) = 800
            -- GP: floor(1000 * 0.80) = 800
            assert.are.equal(800, ext.ep)
            assert.are.equal(800, ext.gp)
        end)

        it("updates modified_by on decay", function()
            EPGP:AddExternalPlayer("Pugman", "WARRIOR")
            SimpleEPGP.db.profile.external_players["Pugman"].ep = 1000
            SimpleEPGP.db.profile.external_players["Pugman"].gp = 500
            EPGP:GUILD_ROSTER_UPDATE()

            EPGP:Decay()

            local ext = SimpleEPGP.db.profile.external_players["Pugman"]
            assert.are.equal("Player1", ext.modified_by)
        end)

        it("updates modified_at on decay", function()
            EPGP:AddExternalPlayer("Pugman", "WARRIOR")
            SimpleEPGP.db.profile.external_players["Pugman"].ep = 1000
            SimpleEPGP.db.profile.external_players["Pugman"].gp = 500
            EPGP:GUILD_ROSTER_UPDATE()

            local before = os.time()
            EPGP:Decay()
            local after = os.time()

            local ext = SimpleEPGP.db.profile.external_players["Pugman"]
            assert.is_true(ext.modified_at >= before)
            assert.is_true(ext.modified_at <= after)
        end)

        it("decays multiple external players", function()
            EPGP:AddExternalPlayer("Pugman", "WARRIOR")
            EPGP:AddExternalPlayer("Allyheals", "PRIEST")
            SimpleEPGP.db.profile.external_players["Pugman"].ep = 1000
            SimpleEPGP.db.profile.external_players["Pugman"].gp = 500
            SimpleEPGP.db.profile.external_players["Allyheals"].ep = 2000
            SimpleEPGP.db.profile.external_players["Allyheals"].gp = 300
            EPGP:GUILD_ROSTER_UPDATE()

            EPGP:Decay()

            local pugman = SimpleEPGP.db.profile.external_players["Pugman"]
            local allyheals = SimpleEPGP.db.profile.external_players["Allyheals"]
            assert.are.equal(850, pugman.ep)
            assert.are.equal(425, pugman.gp)
            assert.are.equal(1700, allyheals.ep)
            assert.are.equal(255, allyheals.gp)
        end)

        it("also decays guild members alongside external players", function()
            EPGP:AddExternalPlayer("Pugman", "WARRIOR")
            SimpleEPGP.db.profile.external_players["Pugman"].ep = 1000
            SimpleEPGP.db.profile.external_players["Pugman"].gp = 500
            EPGP:GUILD_ROSTER_UPDATE()

            EPGP:Decay()

            -- Guild member Player1: EP=5000*0.85=4250, GP=1000*0.85=850
            assert.are.equal("4250,850", _G._testGuildRoster[1].officerNote)
            -- External player
            local ext = SimpleEPGP.db.profile.external_players["Pugman"]
            assert.are.equal(850, ext.ep)
            assert.are.equal(425, ext.gp)
        end)

        it("handles empty external_players table gracefully", function()
            SimpleEPGP.db.profile.external_players = {}
            EPGP:GUILD_ROSTER_UPDATE()

            -- Should not error
            local result = EPGP:Decay()
            assert.is_true(result)
            -- Guild members should still be decayed
            assert.are.equal("4250,850", _G._testGuildRoster[1].officerNote)
        end)

        it("handles nil external_players gracefully", function()
            SimpleEPGP.db.profile.external_players = nil
            EPGP:GUILD_ROSTER_UPDATE()

            -- Should not error
            local result = EPGP:Decay()
            assert.is_true(result)
            -- Guild members should still be decayed
            assert.are.equal("4250,850", _G._testGuildRoster[1].officerNote)
        end)

        it("does not decay external players when decay_percent is 0", function()
            SimpleEPGP.db.profile.decay_percent = 0
            EPGP:AddExternalPlayer("Pugman", "WARRIOR")
            SimpleEPGP.db.profile.external_players["Pugman"].ep = 1000
            SimpleEPGP.db.profile.external_players["Pugman"].gp = 500
            EPGP:GUILD_ROSTER_UPDATE()

            local result = EPGP:Decay()
            assert.is_false(result)

            -- External player should be unchanged
            local ext = SimpleEPGP.db.profile.external_players["Pugman"]
            assert.are.equal(1000, ext.ep)
            assert.are.equal(500, ext.gp)
        end)
    end)

    describe("ResetAll with external players", function()
        it("zeroes EP and GP for external players", function()
            EPGP:AddExternalPlayer("Pugman", "WARRIOR")
            SimpleEPGP.db.profile.external_players["Pugman"].ep = 5000
            SimpleEPGP.db.profile.external_players["Pugman"].gp = 3000
            EPGP:GUILD_ROSTER_UPDATE()

            EPGP:ResetAll()

            local ext = SimpleEPGP.db.profile.external_players["Pugman"]
            assert.are.equal(0, ext.ep)
            assert.are.equal(0, ext.gp)
        end)

        it("does not remove external players from the database", function()
            EPGP:AddExternalPlayer("Pugman", "WARRIOR")
            EPGP:AddExternalPlayer("Allyheals", "PRIEST")
            SimpleEPGP.db.profile.external_players["Pugman"].ep = 1000
            SimpleEPGP.db.profile.external_players["Allyheals"].ep = 2000
            EPGP:GUILD_ROSTER_UPDATE()

            EPGP:ResetAll()

            -- Players still exist in DB (only zeroed, not removed)
            assert.is_not_nil(SimpleEPGP.db.profile.external_players["Pugman"])
            assert.is_not_nil(SimpleEPGP.db.profile.external_players["Allyheals"])
            assert.are.equal("WARRIOR", SimpleEPGP.db.profile.external_players["Pugman"].class)
            assert.are.equal("PRIEST", SimpleEPGP.db.profile.external_players["Allyheals"].class)
        end)

        it("updates modified_by on reset", function()
            EPGP:AddExternalPlayer("Pugman", "WARRIOR")
            SimpleEPGP.db.profile.external_players["Pugman"].ep = 1000
            EPGP:GUILD_ROSTER_UPDATE()

            EPGP:ResetAll()

            local ext = SimpleEPGP.db.profile.external_players["Pugman"]
            assert.are.equal("Player1", ext.modified_by)
        end)

        it("updates modified_at on reset", function()
            EPGP:AddExternalPlayer("Pugman", "WARRIOR")
            SimpleEPGP.db.profile.external_players["Pugman"].ep = 1000
            EPGP:GUILD_ROSTER_UPDATE()

            local before = os.time()
            EPGP:ResetAll()
            local after = os.time()

            local ext = SimpleEPGP.db.profile.external_players["Pugman"]
            assert.is_true(ext.modified_at >= before)
            assert.is_true(ext.modified_at <= after)
        end)

        it("resets multiple external players", function()
            EPGP:AddExternalPlayer("Pugman", "WARRIOR")
            EPGP:AddExternalPlayer("Allyheals", "PRIEST")
            EPGP:AddExternalPlayer("Crossrogue", "ROGUE")
            SimpleEPGP.db.profile.external_players["Pugman"].ep = 5000
            SimpleEPGP.db.profile.external_players["Pugman"].gp = 3000
            SimpleEPGP.db.profile.external_players["Allyheals"].ep = 2000
            SimpleEPGP.db.profile.external_players["Allyheals"].gp = 1000
            SimpleEPGP.db.profile.external_players["Crossrogue"].ep = 800
            SimpleEPGP.db.profile.external_players["Crossrogue"].gp = 400
            EPGP:GUILD_ROSTER_UPDATE()

            EPGP:ResetAll()

            for _, name in ipairs({"Pugman", "Allyheals", "Crossrogue"}) do
                local ext = SimpleEPGP.db.profile.external_players[name]
                assert.are.equal(0, ext.ep, name .. " EP should be 0")
                assert.are.equal(0, ext.gp, name .. " GP should be 0")
            end
        end)

        it("also resets guild members alongside external players", function()
            EPGP:AddExternalPlayer("Pugman", "WARRIOR")
            SimpleEPGP.db.profile.external_players["Pugman"].ep = 5000
            SimpleEPGP.db.profile.external_players["Pugman"].gp = 3000
            EPGP:GUILD_ROSTER_UPDATE()

            EPGP:ResetAll()

            -- Guild member Player1 should be reset
            assert.are.equal("0,0", _G._testGuildRoster[1].officerNote)
            -- External player should be reset
            local ext = SimpleEPGP.db.profile.external_players["Pugman"]
            assert.are.equal(0, ext.ep)
            assert.are.equal(0, ext.gp)
        end)

        it("resets external players already at 0,0", function()
            EPGP:AddExternalPlayer("Pugman", "WARRIOR")
            -- EP=0, GP=0 by default
            EPGP:GUILD_ROSTER_UPDATE()

            -- Should not error, should still update modified_by/at
            EPGP:ResetAll()

            local ext = SimpleEPGP.db.profile.external_players["Pugman"]
            assert.are.equal(0, ext.ep)
            assert.are.equal(0, ext.gp)
            assert.are.equal("Player1", ext.modified_by)
        end)

        it("handles empty external_players table gracefully", function()
            SimpleEPGP.db.profile.external_players = {}
            EPGP:GUILD_ROSTER_UPDATE()

            local result = EPGP:ResetAll()
            assert.is_true(result)
            -- Guild members should still be reset
            assert.are.equal("0,0", _G._testGuildRoster[1].officerNote)
        end)

        it("handles nil external_players gracefully", function()
            SimpleEPGP.db.profile.external_players = nil
            EPGP:GUILD_ROSTER_UPDATE()

            local result = EPGP:ResetAll()
            assert.is_true(result)
            -- Guild members should still be reset
            assert.are.equal("0,0", _G._testGuildRoster[1].officerNote)
        end)
    end)
end)
