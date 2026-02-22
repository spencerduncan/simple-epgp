-----------------------------------------------------------------------
-- test_external_loot.lua — Tests for external players in loot
-- distribution and mass EP (issue #14)
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
        item_overrides = {},
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

-- Save original raid roster for restoration
local _origRaidRoster = {}
for i, m in ipairs(_G._testRaidRoster) do
    _origRaidRoster[i] = {}
    for k, v in pairs(m) do
        _origRaidRoster[i][k] = v
    end
end

describe("External players in loot and mass EP", function()
    local EPGP, LootMaster

    before_each(function()
        -- Reset guild roster officer notes
        _G._testGuildRoster[1].officerNote = "5000,1000"
        _G._testGuildRoster[2].officerNote = "3000,500"
        _G._testGuildRoster[3].officerNote = "2000,2000"
        _G._testGuildRoster[4].officerNote = "1000,100"
        _G._testGuildRoster[5].officerNote = ""

        -- Clear external players
        SimpleEPGP.db.profile.external_players = {}

        -- Reset standby
        SimpleEPGP.db.standby = {}
        SimpleEPGP.db.profile.standby_percent = 1.0

        -- Restore original raid roster
        for i = #_G._testRaidRoster, 1, -1 do
            _G._testRaidRoster[i] = nil
        end
        for i, m in ipairs(_origRaidRoster) do
            _G._testRaidRoster[i] = {}
            for k, v in pairs(m) do
                _G._testRaidRoster[i][k] = v
            end
        end

        -- Override GetNumGroupMembers to track raid roster size dynamically
        _G.GetNumGroupMembers = function()
            return #_G._testRaidRoster
        end

        EPGP = SimpleEPGP:GetModule("EPGP")
        LootMaster = SimpleEPGP:GetModule("LootMaster")

        -- Rebuild standings
        EPGP:GUILD_ROSTER_UPDATE()

        -- Reset sessions
        LootMaster.sessions = {}
        LootMaster.nextSessionId = 1

        -- Clear sent messages
        for i = #_G._testSentMessages, 1, -1 do
            _G._testSentMessages[i] = nil
        end
    end)

    -----------------------------------------------------------------------
    -- MassEP with external raid members
    -----------------------------------------------------------------------

    describe("MassEP with external raid members", function()
        it("awards EP to an external player in the raid", function()
            -- Add external player to DB and to raid roster
            EPGP:AddExternalPlayer("Pugman", "WARRIOR")
            EPGP:GUILD_ROSTER_UPDATE()

            -- Add Pugman to the raid roster (not in guild)
            _G._testRaidRoster[#_G._testRaidRoster + 1] = {
                name = "Pugman-OtherRealm", rank = 0, subgroup = 3,
                level = 70, class = "WARRIOR", fileName = "WARRIOR",
                zone = "Karazhan", online = true, isDead = false,
                role = "NONE", isML = false,
            }

            EPGP:MassEP(200, "Boss kill")

            -- External player should have received EP
            local ext = SimpleEPGP.db.profile.external_players["Pugman"]
            assert.are.equal(200, ext.ep)
        end)

        it("does not double-award to guild members via external path", function()
            -- Player1 is a guild member — should get EP via officer note, not external
            EPGP:MassEP(200, "Boss kill")

            -- Player1: 5000+200=5200 via officer note
            assert.are.equal("5200,1000", _G._testGuildRoster[1].officerNote)
            -- No external player record should exist for Player1
            assert.is_nil(SimpleEPGP.db.profile.external_players["Player1"])
        end)

        it("awards EP to multiple external players in the raid", function()
            EPGP:AddExternalPlayer("Pugman", "WARRIOR")
            EPGP:AddExternalPlayer("Allyheals", "PRIEST")
            EPGP:GUILD_ROSTER_UPDATE()

            -- Add both to raid
            _G._testRaidRoster[#_G._testRaidRoster + 1] = {
                name = "Pugman-OtherRealm", rank = 0, subgroup = 3,
                level = 70, class = "WARRIOR", fileName = "WARRIOR",
                zone = "Karazhan", online = true, isDead = false,
                role = "NONE", isML = false,
            }
            _G._testRaidRoster[#_G._testRaidRoster + 1] = {
                name = "Allyheals-OtherRealm", rank = 0, subgroup = 3,
                level = 70, class = "PRIEST", fileName = "PRIEST",
                zone = "Karazhan", online = true, isDead = false,
                role = "NONE", isML = false,
            }

            EPGP:MassEP(300, "Boss kill")

            assert.are.equal(300, SimpleEPGP.db.profile.external_players["Pugman"].ep)
            assert.are.equal(300, SimpleEPGP.db.profile.external_players["Allyheals"].ep)
        end)

        it("accumulates EP across multiple MassEP calls", function()
            EPGP:AddExternalPlayer("Pugman", "WARRIOR")
            EPGP:GUILD_ROSTER_UPDATE()

            _G._testRaidRoster[#_G._testRaidRoster + 1] = {
                name = "Pugman-OtherRealm", rank = 0, subgroup = 3,
                level = 70, class = "WARRIOR", fileName = "WARRIOR",
                zone = "Karazhan", online = true, isDead = false,
                role = "NONE", isML = false,
            }

            EPGP:MassEP(100, "Boss 1")
            EPGP:MassEP(100, "Boss 2")

            assert.are.equal(200, SimpleEPGP.db.profile.external_players["Pugman"].ep)
        end)

        it("skips raid members not in guild or external player DB", function()
            -- Add a random person to raid who is NOT an external player
            _G._testRaidRoster[#_G._testRaidRoster + 1] = {
                name = "Randompug-SomeRealm", rank = 0, subgroup = 3,
                level = 70, class = "ROGUE", fileName = "ROGUE",
                zone = "Karazhan", online = true, isDead = false,
                role = "NONE", isML = false,
            }

            -- Should not error
            EPGP:MassEP(200, "Boss kill")

            -- Guild members should still get EP
            assert.are.equal("5200,1000", _G._testGuildRoster[1].officerNote)
        end)

        it("updates modified_by and modified_at for external players", function()
            EPGP:AddExternalPlayer("Pugman", "WARRIOR")
            EPGP:GUILD_ROSTER_UPDATE()

            _G._testRaidRoster[#_G._testRaidRoster + 1] = {
                name = "Pugman-OtherRealm", rank = 0, subgroup = 3,
                level = 70, class = "WARRIOR", fileName = "WARRIOR",
                zone = "Karazhan", online = true, isDead = false,
                role = "NONE", isML = false,
            }

            local before = os.time()
            EPGP:MassEP(200, "Boss kill")
            local ext = SimpleEPGP.db.profile.external_players["Pugman"]

            assert.are.equal("Player1", ext.modified_by)
            assert.is_true(ext.modified_at >= before)
        end)
    end)

    -----------------------------------------------------------------------
    -- Standby EP for external players
    -----------------------------------------------------------------------

    describe("Standby EP for external players", function()
        it("awards standby EP to an external player on standby list", function()
            EPGP:AddExternalPlayer("Pugman", "WARRIOR")
            EPGP:GUILD_ROSTER_UPDATE()

            -- Pugman is on standby but NOT in raid
            SimpleEPGP.db.standby = { "Pugman" }
            SimpleEPGP.db.profile.standby_percent = 0.5

            EPGP:MassEP(200, "Boss kill")

            -- Standby EP = 200 * 0.5 = 100
            local ext = SimpleEPGP.db.profile.external_players["Pugman"]
            assert.are.equal(100, ext.ep)
        end)

        it("does not award standby EP when standby_percent is 0", function()
            EPGP:AddExternalPlayer("Pugman", "WARRIOR")
            EPGP:GUILD_ROSTER_UPDATE()

            SimpleEPGP.db.standby = { "Pugman" }
            SimpleEPGP.db.profile.standby_percent = 0

            EPGP:MassEP(200, "Boss kill")

            local ext = SimpleEPGP.db.profile.external_players["Pugman"]
            assert.are.equal(0, ext.ep)
        end)
    end)

    -----------------------------------------------------------------------
    -- Loot distribution: External player bids
    -----------------------------------------------------------------------

    describe("External player bids", function()
        it("accepts bids from external players", function()
            EPGP:AddExternalPlayer("Pugman", "WARRIOR")
            EPGP:GUILD_ROSTER_UPDATE()

            local link = _G._testItemDB[29759][2]
            local sessionId = LootMaster:StartSession(link, 1000)

            -- External player bids MS
            LootMaster:OnBidReceived("Pugman", sessionId, "MS")

            -- Bid should be recorded
            assert.are.equal("MS", LootMaster.sessions[sessionId].bids["Pugman"])
        end)

        it("shows external player with correct PR in GetSessionBids", function()
            EPGP:AddExternalPlayer("Pugman", "WARRIOR")
            SimpleEPGP.db.profile.external_players["Pugman"].ep = 5000
            SimpleEPGP.db.profile.external_players["Pugman"].gp = 200
            EPGP:GUILD_ROSTER_UPDATE()

            local link = _G._testItemDB[29759][2]
            local sessionId = LootMaster:StartSession(link, 1000)

            LootMaster:OnBidReceived("Pugman", sessionId, "MS")
            LootMaster:OnBidReceived("Player1", sessionId, "MS")

            local bids = LootMaster:GetSessionBids(sessionId)
            assert.are.equal(2, #bids.ms)

            -- Find Pugman in the bid list
            local pugmanBid
            for _, bid in ipairs(bids.ms) do
                if bid.name == "Pugman" then
                    pugmanBid = bid
                    break
                end
            end

            assert.is_not_nil(pugmanBid)
            assert.are.equal("WARRIOR", pugmanBid.class)
            -- PR = 5000 / (200 + 100) = 16.667
            local expectedPR = 5000 / (200 + 100)
            assert.is_true(math.abs(pugmanBid.pr - expectedPR) < 0.01)
        end)

        it("sorts external player correctly by PR among guild members", function()
            -- Give Pugman very high PR so they sort first
            EPGP:AddExternalPlayer("Pugman", "WARRIOR")
            SimpleEPGP.db.profile.external_players["Pugman"].ep = 50000
            EPGP:GUILD_ROSTER_UPDATE()

            local link = _G._testItemDB[29759][2]
            local sessionId = LootMaster:StartSession(link, 1000)

            LootMaster:OnBidReceived("Pugman", sessionId, "MS")
            LootMaster:OnBidReceived("Player1", sessionId, "MS")

            local bids = LootMaster:GetSessionBids(sessionId)
            -- Pugman: PR = 50000/100 = 500, Player1: PR = 5000/1100 ~ 4.5
            assert.are.equal("Pugman", bids.ms[1].name)
            assert.are.equal("Player1", bids.ms[2].name)
        end)
    end)

    -----------------------------------------------------------------------
    -- Loot distribution: GP charging for external players
    -----------------------------------------------------------------------

    describe("GP charging for external players", function()
        it("charges GP to external player on MS award", function()
            EPGP:AddExternalPlayer("Pugman", "WARRIOR")
            EPGP:GUILD_ROSTER_UPDATE()

            local link = _G._testItemDB[29759][2]
            local sessionId = LootMaster:StartSession(link, 1000)

            LootMaster:OnBidReceived("Pugman", sessionId, "MS")
            LootMaster:AwardItem(sessionId, "Pugman", "MS")

            -- GP should be charged to SavedVariables, not officer notes
            local ext = SimpleEPGP.db.profile.external_players["Pugman"]
            assert.is_true(ext.gp > 0)
        end)

        it("charges correct GP amount for MS bid", function()
            EPGP:AddExternalPlayer("Pugman", "WARRIOR")
            EPGP:GUILD_ROSTER_UPDATE()

            local link = _G._testItemDB[29759][2]
            local sessionId = LootMaster:StartSession(link, 1000)

            LootMaster:OnBidReceived("Pugman", sessionId, "MS")
            LootMaster:AwardItem(sessionId, "Pugman", "MS")

            -- Full GP cost for MS bid (calculated by GPCalc)
            local GPCalc = SimpleEPGP:GetModule("GPCalc")
            local expectedGP = GPCalc:GetBidGP(link, "MS")
            assert.are.equal(expectedGP, SimpleEPGP.db.profile.external_players["Pugman"].gp)
        end)

        it("charges reduced GP for OS bid", function()
            EPGP:AddExternalPlayer("Pugman", "WARRIOR")
            EPGP:GUILD_ROSTER_UPDATE()

            local link = _G._testItemDB[29759][2]
            local sessionId = LootMaster:StartSession(link, 1000)

            LootMaster:OnBidReceived("Pugman", sessionId, "OS")
            LootMaster:AwardItem(sessionId, "Pugman", "OS")

            -- OS = 50% GP
            local GPCalc = SimpleEPGP:GetModule("GPCalc")
            local expectedGP = GPCalc:GetBidGP(link, "OS")
            assert.are.equal(expectedGP, SimpleEPGP.db.profile.external_players["Pugman"].gp)
        end)

        it("charges 0 GP for DE bid", function()
            EPGP:AddExternalPlayer("Pugman", "WARRIOR")
            EPGP:GUILD_ROSTER_UPDATE()

            local link = _G._testItemDB[29759][2]
            local sessionId = LootMaster:StartSession(link, 1000)

            LootMaster:OnBidReceived("Pugman", sessionId, "DE")
            LootMaster:AwardItem(sessionId, "Pugman", "DE")

            -- DE = 0% GP
            assert.are.equal(0, SimpleEPGP.db.profile.external_players["Pugman"].gp)
        end)

        it("does not modify guild member officer notes when external player wins", function()
            EPGP:AddExternalPlayer("Pugman", "WARRIOR")
            EPGP:GUILD_ROSTER_UPDATE()

            local link = _G._testItemDB[29759][2]
            local sessionId = LootMaster:StartSession(link, 1000)

            LootMaster:OnBidReceived("Pugman", sessionId, "MS")
            LootMaster:AwardItem(sessionId, "Pugman", "MS")

            -- Guild member officer notes should be unchanged
            assert.are.equal("5000,1000", _G._testGuildRoster[1].officerNote)
            assert.are.equal("3000,500", _G._testGuildRoster[2].officerNote)
        end)

        it("marks session as awarded after external player wins", function()
            EPGP:AddExternalPlayer("Pugman", "WARRIOR")
            EPGP:GUILD_ROSTER_UPDATE()

            local link = _G._testItemDB[29759][2]
            local sessionId = LootMaster:StartSession(link, 1000)

            LootMaster:OnBidReceived("Pugman", sessionId, "MS")
            LootMaster:AwardItem(sessionId, "Pugman", "MS")

            assert.is_true(LootMaster.sessions[sessionId].awarded)
        end)
    end)

    -----------------------------------------------------------------------
    -- Auto-distribute with external players
    -----------------------------------------------------------------------

    describe("Auto-distribute with external player", function()
        it("auto-awards to highest PR external player", function()
            SimpleEPGP.db.profile.auto_distribute = true

            -- Give Pugman very high PR
            EPGP:AddExternalPlayer("Pugman", "WARRIOR")
            SimpleEPGP.db.profile.external_players["Pugman"].ep = 50000
            EPGP:GUILD_ROSTER_UPDATE()

            local link = _G._testItemDB[29759][2]
            local sessionId = LootMaster:StartSession(link, 1000)

            LootMaster:OnBidReceived("Pugman", sessionId, "MS")
            LootMaster:OnBidReceived("Player1", sessionId, "MS")

            LootMaster:OnTimerExpired(sessionId)

            -- Pugman should win (PR=500 vs Player1 PR~4.5)
            assert.is_true(LootMaster.sessions[sessionId].awarded)
            assert.is_true(SimpleEPGP.db.profile.external_players["Pugman"].gp > 0)

            SimpleEPGP.db.profile.auto_distribute = false
        end)
    end)
end)
