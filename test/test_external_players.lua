-----------------------------------------------------------------------
-- test_external_players.lua — Unit tests for external player data layer
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

describe("External Players", function()
    local EPGP

    before_each(function()
        -- Reset state between tests
        _G._testGuildRoster[1].officerNote = "5000,1000"
        _G._testGuildRoster[2].officerNote = "3000,500"
        _G._testGuildRoster[3].officerNote = "2000,2000"
        _G._testGuildRoster[4].officerNote = "1000,100"
        _G._testGuildRoster[5].officerNote = ""

        -- Clear external players
        SimpleEPGP.db.profile.external_players = {}

        EPGP = SimpleEPGP:GetModule("EPGP")
    end)

    describe("AddExternalPlayer", function()
        it("adds a new external player", function()
            local result = EPGP:AddExternalPlayer("Pugman", "WARRIOR")
            assert.is_true(result)
            local ext = SimpleEPGP.db.profile.external_players["Pugman"]
            assert.is_not_nil(ext)
            assert.are.equal("WARRIOR", ext.class)
            assert.are.equal(0, ext.ep)
            assert.are.equal(0, ext.gp)
            assert.is_not_nil(ext.modified_by)
            assert.is_not_nil(ext.modified_at)
        end)

        it("normalizes the player name", function()
            EPGP:AddExternalPlayer("pugman", "MAGE")
            assert.is_not_nil(SimpleEPGP.db.profile.external_players["Pugman"])
            assert.is_nil(SimpleEPGP.db.profile.external_players["pugman"])
        end)

        it("uppercases the class", function()
            EPGP:AddExternalPlayer("Pugman", "warrior")
            local ext = SimpleEPGP.db.profile.external_players["Pugman"]
            assert.are.equal("WARRIOR", ext.class)
        end)

        it("returns false for duplicate name", function()
            EPGP:AddExternalPlayer("Pugman", "WARRIOR")
            local result = EPGP:AddExternalPlayer("Pugman", "MAGE")
            assert.is_false(result)
        end)

        it("returns false for nil name", function()
            local result = EPGP:AddExternalPlayer(nil, "WARRIOR")
            assert.is_false(result)
        end)

        it("returns false for empty name", function()
            local result = EPGP:AddExternalPlayer("", "WARRIOR")
            assert.is_false(result)
        end)

        it("returns false for nil class", function()
            local result = EPGP:AddExternalPlayer("Pugman", nil)
            assert.is_false(result)
        end)

        it("returns false for empty class", function()
            local result = EPGP:AddExternalPlayer("Pugman", "")
            assert.is_false(result)
        end)

        it("sets modified_by to current player", function()
            EPGP:AddExternalPlayer("Pugman", "WARRIOR")
            local ext = SimpleEPGP.db.profile.external_players["Pugman"]
            assert.are.equal("Player1", ext.modified_by)
        end)

        it("sets modified_at to current time", function()
            local before = os.time()
            EPGP:AddExternalPlayer("Pugman", "WARRIOR")
            local after = os.time()
            local ext = SimpleEPGP.db.profile.external_players["Pugman"]
            assert.is_true(ext.modified_at >= before)
            assert.is_true(ext.modified_at <= after)
        end)
    end)

    describe("RemoveExternalPlayer", function()
        it("removes an existing external player", function()
            EPGP:AddExternalPlayer("Pugman", "WARRIOR")
            local result = EPGP:RemoveExternalPlayer("Pugman")
            assert.is_true(result)
            assert.is_nil(SimpleEPGP.db.profile.external_players["Pugman"])
        end)

        it("normalizes the name for removal", function()
            EPGP:AddExternalPlayer("Pugman", "WARRIOR")
            local result = EPGP:RemoveExternalPlayer("pugman")
            assert.is_true(result)
            assert.is_nil(SimpleEPGP.db.profile.external_players["Pugman"])
        end)

        it("returns false for non-existent player", function()
            local result = EPGP:RemoveExternalPlayer("Nobody")
            assert.is_false(result)
        end)

        it("returns false for nil name", function()
            local result = EPGP:RemoveExternalPlayer(nil)
            assert.is_false(result)
        end)

        it("returns false for empty name", function()
            local result = EPGP:RemoveExternalPlayer("")
            assert.is_false(result)
        end)
    end)

    describe("GetExternalPlayers", function()
        it("returns empty table when no external players", function()
            local ext = EPGP:GetExternalPlayers()
            assert.are.same({}, ext)
        end)

        it("returns the external players table", function()
            EPGP:AddExternalPlayer("Pugman", "WARRIOR")
            EPGP:AddExternalPlayer("Allyheals", "PRIEST")
            local ext = EPGP:GetExternalPlayers()
            assert.is_not_nil(ext["Pugman"])
            assert.is_not_nil(ext["Allyheals"])
        end)
    end)

    describe("IsExternalPlayer", function()
        it("returns true for an external player", function()
            EPGP:AddExternalPlayer("Pugman", "WARRIOR")
            assert.is_true(EPGP:IsExternalPlayer("Pugman"))
        end)

        it("normalizes name for lookup", function()
            EPGP:AddExternalPlayer("Pugman", "WARRIOR")
            assert.is_true(EPGP:IsExternalPlayer("pugman"))
            assert.is_true(EPGP:IsExternalPlayer("PUGMAN"))
        end)

        it("returns false for non-existent player", function()
            assert.is_false(EPGP:IsExternalPlayer("Nobody"))
        end)

        it("returns false for guild member", function()
            assert.is_false(EPGP:IsExternalPlayer("Player1"))
        end)

        it("returns false for nil", function()
            assert.is_false(EPGP:IsExternalPlayer(nil))
        end)
    end)

    describe("Standings merge", function()
        it("includes external players in standings", function()
            EPGP:AddExternalPlayer("Pugman", "WARRIOR")
            EPGP:GUILD_ROSTER_UPDATE()
            local standings = EPGP:GetStandings()
            local found = false
            for _, entry in ipairs(standings) do
                if entry.name == "Pugman" then
                    found = true
                    break
                end
            end
            assert.is_true(found)
        end)

        it("external players have isExternal flag", function()
            EPGP:AddExternalPlayer("Pugman", "WARRIOR")
            EPGP:GUILD_ROSTER_UPDATE()
            local info = EPGP:GetPlayerInfo("Pugman")
            assert.is_not_nil(info)
            assert.is_true(info.isExternal)
        end)

        it("external players do NOT have rosterIndex", function()
            EPGP:AddExternalPlayer("Pugman", "WARRIOR")
            EPGP:GUILD_ROSTER_UPDATE()
            local info = EPGP:GetPlayerInfo("Pugman")
            assert.is_not_nil(info)
            assert.is_nil(info.rosterIndex)
        end)

        it("guild members do NOT have isExternal flag", function()
            EPGP:GUILD_ROSTER_UPDATE()
            local info = EPGP:GetPlayerInfo("Player1")
            assert.is_not_nil(info)
            assert.is_nil(info.isExternal)
        end)

        it("guild members have rosterIndex", function()
            EPGP:GUILD_ROSTER_UPDATE()
            local info = EPGP:GetPlayerInfo("Player1")
            assert.is_not_nil(info)
            assert.is_not_nil(info.rosterIndex)
        end)

        it("calculates PR for external players with base_gp", function()
            EPGP:AddExternalPlayer("Pugman", "WARRIOR")
            -- Set some EP/GP on the external player
            SimpleEPGP.db.profile.external_players["Pugman"].ep = 500
            SimpleEPGP.db.profile.external_players["Pugman"].gp = 200
            EPGP:GUILD_ROSTER_UPDATE()

            local info = EPGP:GetPlayerInfo("Pugman")
            assert.is_not_nil(info)
            -- PR = 500 / (200 + 100) = 500/300 ~ 1.6667
            local expectedPR = 500 / (200 + 100)
            assert.is_true(math.abs(info.pr - expectedPR) < 0.01)
        end)

        it("applies min_ep to external players", function()
            SimpleEPGP.db.profile.min_ep = 600
            EPGP:AddExternalPlayer("Pugman", "WARRIOR")
            SimpleEPGP.db.profile.external_players["Pugman"].ep = 500
            EPGP:GUILD_ROSTER_UPDATE()

            local info = EPGP:GetPlayerInfo("Pugman")
            assert.are.equal(0, info.pr)  -- below min_ep
            SimpleEPGP.db.profile.min_ep = 0  -- reset
        end)

        it("external players are sorted by PR with guild members", function()
            EPGP:AddExternalPlayer("Pugman", "WARRIOR")
            -- Give Pugman high EP so they sort near the top
            SimpleEPGP.db.profile.external_players["Pugman"].ep = 10000
            EPGP:GUILD_ROSTER_UPDATE()

            local standings = EPGP:GetStandings()
            -- Pugman should be first: PR = 10000 / 100 = 100
            assert.are.equal("Pugman", standings[1].name)
        end)

        it("skips external player if name collides with guild member", function()
            -- Player1 is already a guild member
            EPGP:AddExternalPlayer("Player1", "MAGE")
            EPGP:GUILD_ROSTER_UPDATE()

            local info = EPGP:GetPlayerInfo("Player1")
            assert.is_not_nil(info)
            -- Should be the guild member (has rosterIndex), not the external player
            assert.is_not_nil(info.rosterIndex)
            assert.is_nil(info.isExternal)
        end)

        it("external player accessible via GetPlayerInfo", function()
            EPGP:AddExternalPlayer("Pugman", "HUNTER")
            EPGP:GUILD_ROSTER_UPDATE()
            local info = EPGP:GetPlayerInfo("Pugman")
            assert.is_not_nil(info)
            assert.are.equal("Pugman", info.name)
            assert.are.equal("HUNTER", info.class)
        end)
    end)

    describe("ModifyEP for external players", function()
        it("adds EP to an external player", function()
            EPGP:AddExternalPlayer("Pugman", "WARRIOR")
            EPGP:GUILD_ROSTER_UPDATE()
            local ok = EPGP:ModifyEP("Pugman", 500, "Boss kill")
            assert.is_true(ok)
            assert.are.equal(500, SimpleEPGP.db.profile.external_players["Pugman"].ep)
        end)

        it("handles case-insensitive name for EP", function()
            EPGP:AddExternalPlayer("Pugman", "WARRIOR")
            EPGP:GUILD_ROSTER_UPDATE()
            local ok = EPGP:ModifyEP("pugman", 300, "Test")
            assert.is_true(ok)
            assert.are.equal(300, SimpleEPGP.db.profile.external_players["Pugman"].ep)
        end)

        it("prevents EP from going below 0 for external players", function()
            EPGP:AddExternalPlayer("Pugman", "WARRIOR")
            SimpleEPGP.db.profile.external_players["Pugman"].ep = 100
            EPGP:GUILD_ROSTER_UPDATE()
            EPGP:ModifyEP("Pugman", -500, "Penalty")
            assert.are.equal(0, SimpleEPGP.db.profile.external_players["Pugman"].ep)
        end)

        it("updates modified_by and modified_at on EP change", function()
            EPGP:AddExternalPlayer("Pugman", "WARRIOR")
            EPGP:GUILD_ROSTER_UPDATE()
            local before = os.time()
            EPGP:ModifyEP("Pugman", 100, "Test")
            local ext = SimpleEPGP.db.profile.external_players["Pugman"]
            assert.are.equal("Player1", ext.modified_by)
            assert.is_true(ext.modified_at >= before)
        end)

        it("updates standings after modifying external player EP", function()
            EPGP:AddExternalPlayer("Pugman", "WARRIOR")
            EPGP:GUILD_ROSTER_UPDATE()
            EPGP:ModifyEP("Pugman", 1000, "Test")
            local info = EPGP:GetPlayerInfo("Pugman")
            assert.are.equal(1000, info.ep)
        end)

        it("still modifies guild members via officer notes", function()
            EPGP:GUILD_ROSTER_UPDATE()
            EPGP:ModifyEP("Player1", 500, "Boss kill")
            -- Player1 should be modified via officer note, not external DB
            assert.are.equal("5500,1000", _G._testGuildRoster[1].officerNote)
        end)

        it("returns false for player not in guild or external list", function()
            local result = EPGP:ModifyEP("NonExistent", 100, "Test")
            assert.is_false(result)
        end)
    end)

    describe("ModifyGP for external players", function()
        it("adds GP to an external player", function()
            EPGP:AddExternalPlayer("Pugman", "WARRIOR")
            EPGP:GUILD_ROSTER_UPDATE()
            local ok = EPGP:ModifyGP("Pugman", 300, "Won item")
            assert.is_true(ok)
            assert.are.equal(300, SimpleEPGP.db.profile.external_players["Pugman"].gp)
        end)

        it("handles case-insensitive name for GP", function()
            EPGP:AddExternalPlayer("Pugman", "WARRIOR")
            EPGP:GUILD_ROSTER_UPDATE()
            local ok = EPGP:ModifyGP("PUGMAN", 200, "Test")
            assert.is_true(ok)
            assert.are.equal(200, SimpleEPGP.db.profile.external_players["Pugman"].gp)
        end)

        it("prevents GP from going below 0 for external players", function()
            EPGP:AddExternalPlayer("Pugman", "WARRIOR")
            SimpleEPGP.db.profile.external_players["Pugman"].gp = 50
            EPGP:GUILD_ROSTER_UPDATE()
            EPGP:ModifyGP("Pugman", -200, "Correction")
            assert.are.equal(0, SimpleEPGP.db.profile.external_players["Pugman"].gp)
        end)

        it("updates modified_by and modified_at on GP change", function()
            EPGP:AddExternalPlayer("Pugman", "WARRIOR")
            EPGP:GUILD_ROSTER_UPDATE()
            local before = os.time()
            EPGP:ModifyGP("Pugman", 100, "Test")
            local ext = SimpleEPGP.db.profile.external_players["Pugman"]
            assert.are.equal("Player1", ext.modified_by)
            assert.is_true(ext.modified_at >= before)
        end)

        it("updates standings after modifying external player GP", function()
            EPGP:AddExternalPlayer("Pugman", "WARRIOR")
            SimpleEPGP.db.profile.external_players["Pugman"].ep = 1000
            EPGP:GUILD_ROSTER_UPDATE()
            EPGP:ModifyGP("Pugman", 200, "Test")
            local info = EPGP:GetPlayerInfo("Pugman")
            assert.are.equal(200, info.gp)
            -- PR = 1000 / (200 + 100) = 3.333
            local expectedPR = 1000 / 300
            assert.is_true(math.abs(info.pr - expectedPR) < 0.01)
        end)

        it("still modifies guild members via officer notes", function()
            EPGP:GUILD_ROSTER_UPDATE()
            EPGP:ModifyGP("Player2", 300, "Won item")
            assert.are.equal("3000,800", _G._testGuildRoster[2].officerNote)
        end)

        it("returns false for player not in guild or external list", function()
            local result = EPGP:ModifyGP("NonExistent", 100, "Test")
            assert.is_false(result)
        end)
    end)

    describe("Conflict resolution schema", function()
        it("external player entries have modified_by and modified_at", function()
            EPGP:AddExternalPlayer("Pugman", "WARRIOR")
            local ext = SimpleEPGP.db.profile.external_players["Pugman"]
            assert.is_string(ext.modified_by)
            assert.is_number(ext.modified_at)
        end)

        it("modified_at updates on EP modification", function()
            EPGP:AddExternalPlayer("Pugman", "WARRIOR")
            local initialTime = SimpleEPGP.db.profile.external_players["Pugman"].modified_at
            EPGP:GUILD_ROSTER_UPDATE()
            -- Modify EP (in test stubs, time() may return same second)
            EPGP:ModifyEP("Pugman", 100, "Test")
            local ext = SimpleEPGP.db.profile.external_players["Pugman"]
            assert.is_true(ext.modified_at >= initialTime)
        end)

        it("modified_at updates on GP modification", function()
            EPGP:AddExternalPlayer("Pugman", "WARRIOR")
            local initialTime = SimpleEPGP.db.profile.external_players["Pugman"].modified_at
            EPGP:GUILD_ROSTER_UPDATE()
            EPGP:ModifyGP("Pugman", 100, "Test")
            local ext = SimpleEPGP.db.profile.external_players["Pugman"]
            assert.is_true(ext.modified_at >= initialTime)
        end)
    end)

    describe("Multiple external players", function()
        it("can add and track multiple external players", function()
            EPGP:AddExternalPlayer("Pugman", "WARRIOR")
            EPGP:AddExternalPlayer("Allyheals", "PRIEST")
            EPGP:AddExternalPlayer("Crossrogue", "ROGUE")
            EPGP:GUILD_ROSTER_UPDATE()

            assert.is_not_nil(EPGP:GetPlayerInfo("Pugman"))
            assert.is_not_nil(EPGP:GetPlayerInfo("Allyheals"))
            assert.is_not_nil(EPGP:GetPlayerInfo("Crossrogue"))
        end)

        it("modifying one external player does not affect others", function()
            EPGP:AddExternalPlayer("Pugman", "WARRIOR")
            EPGP:AddExternalPlayer("Allyheals", "PRIEST")
            EPGP:GUILD_ROSTER_UPDATE()

            EPGP:ModifyEP("Pugman", 500, "Test")
            assert.are.equal(500, SimpleEPGP.db.profile.external_players["Pugman"].ep)
            assert.are.equal(0, SimpleEPGP.db.profile.external_players["Allyheals"].ep)
        end)

        it("removing one external player does not affect others", function()
            EPGP:AddExternalPlayer("Pugman", "WARRIOR")
            EPGP:AddExternalPlayer("Allyheals", "PRIEST")
            EPGP:RemoveExternalPlayer("Pugman")
            assert.is_true(EPGP:IsExternalPlayer("Allyheals"))
            assert.is_false(EPGP:IsExternalPlayer("Pugman"))
        end)

        it("all external players appear in standings", function()
            EPGP:AddExternalPlayer("Pugman", "WARRIOR")
            EPGP:AddExternalPlayer("Allyheals", "PRIEST")
            EPGP:GUILD_ROSTER_UPDATE()

            local standings = EPGP:GetStandings()
            local extCount = 0
            for _, entry in ipairs(standings) do
                if entry.isExternal then
                    extCount = extCount + 1
                end
            end
            assert.are.equal(2, extCount)
        end)
    end)
end)
