-----------------------------------------------------------------------
-- test_config_sync.lua -- Unit tests for GP config sync (issue #1)
-- Tests that GP config values are broadcast alongside standings and
-- correctly applied on non-officer clients.
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
        auto_ep = true,
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

describe("GP Config Sync", function()
    local EPGP, Comms, GPCalc

    before_each(function()
        EPGP = SimpleEPGP:GetModule("EPGP")
        Comms = SimpleEPGP:GetModule("Comms")
        GPCalc = SimpleEPGP:GetModule("GPCalc")

        -- Reset config to defaults
        SimpleEPGP.db.profile.base_gp = 100
        SimpleEPGP.db.profile.standard_ilvl = 120
        SimpleEPGP.db.profile.gp_base_multiplier = nil
        SimpleEPGP.db.profile.os_multiplier = 0.5
        SimpleEPGP.db.profile.de_multiplier = 0.0
        SimpleEPGP.db.profile.slot_multipliers = {}
        SimpleEPGP.db.profile.item_overrides = {}

        -- Reset guild roster
        _G._testGuildRoster[1].officerNote = "5000,1000"
        _G._testGuildRoster[2].officerNote = "3000,500"
        _G._testGuildRoster[3].officerNote = "2000,2000"
        EPGP:GUILD_ROSTER_UPDATE()

        -- Clear sent messages
        for i = #_G._testSentMessages, 1, -1 do
            _G._testSentMessages[i] = nil
        end
    end)

    describe("ExportConfig", function()
        it("exports default config values", function()
            local config = EPGP:ExportConfig()
            assert.is_not_nil(config)
            assert.are.equal(100, config.bg)
            assert.are.equal(120, config.si)
            assert.are.equal(0.5, config.om)
            assert.are.equal(0.0, config.dm)
            assert.is_nil(config.bm)
            assert.is_table(config.sm)
            assert.is_table(config.io)
        end)

        it("exports custom slot multipliers", function()
            SimpleEPGP.db.profile.slot_multipliers = {
                INVTYPE_HEAD = 1.5,
                INVTYPE_TRINKET = 2.0,
            }
            local config = EPGP:ExportConfig()
            assert.are.equal(1.5, config.sm.INVTYPE_HEAD)
            assert.are.equal(2.0, config.sm.INVTYPE_TRINKET)
        end)

        it("exports item overrides", function()
            SimpleEPGP.db.profile.item_overrides = {
                [29759] = 500,
                [30627] = 1200,
            }
            local config = EPGP:ExportConfig()
            assert.are.equal(500, config.io[29759])
            assert.are.equal(1200, config.io[30627])
        end)

        it("exports explicit gp_base_multiplier when set", function()
            SimpleEPGP.db.profile.gp_base_multiplier = 50
            local config = EPGP:ExportConfig()
            assert.are.equal(50, config.bm)
        end)

        it("omits gp_base_multiplier when nil (auto-derived)", function()
            SimpleEPGP.db.profile.gp_base_multiplier = nil
            local config = EPGP:ExportConfig()
            assert.is_nil(config.bm)
        end)

        it("exports custom bid multipliers", function()
            SimpleEPGP.db.profile.os_multiplier = 0.75
            SimpleEPGP.db.profile.de_multiplier = 0.1
            local config = EPGP:ExportConfig()
            assert.are.equal(0.75, config.om)
            assert.are.equal(0.1, config.dm)
        end)

        it("exports custom base_gp and standard_ilvl", function()
            SimpleEPGP.db.profile.base_gp = 200
            SimpleEPGP.db.profile.standard_ilvl = 141
            local config = EPGP:ExportConfig()
            assert.are.equal(200, config.bg)
            assert.are.equal(141, config.si)
        end)
    end)

    describe("ApplyReceivedConfig", function()
        it("applies all config values from officer", function()
            local config = {
                sm = { INVTYPE_HEAD = 1.5 },
                io = { [29759] = 500 },
                om = 0.75,
                dm = 0.1,
                bg = 200,
                si = 141,
                bm = 50,
            }
            EPGP:ApplyReceivedConfig(config)

            assert.are.equal(1.5, SimpleEPGP.db.profile.slot_multipliers.INVTYPE_HEAD)
            assert.are.equal(500, SimpleEPGP.db.profile.item_overrides[29759])
            assert.are.equal(0.75, SimpleEPGP.db.profile.os_multiplier)
            assert.are.equal(0.1, SimpleEPGP.db.profile.de_multiplier)
            assert.are.equal(200, GPCalc:GetBaseGP())
            assert.are.equal(141, GPCalc:GetStandardIlvl())
            assert.are.equal(50, GPCalc:GetGPBaseMultiplier())
        end)

        it("clears gp_base_multiplier when not in config", function()
            -- First set an explicit multiplier
            GPCalc:SetGPBaseMultiplier(50)
            assert.are.equal(50, GPCalc:GetGPBaseMultiplier())

            -- Receive config without bm (officer uses auto-derived)
            local config = {
                sm = {},
                io = {},
                om = 0.5,
                dm = 0.0,
                bg = 100,
                si = 120,
                -- bm is nil
            }
            EPGP:ApplyReceivedConfig(config)
            assert.is_nil(GPCalc:GetGPBaseMultiplier())
        end)

        it("handles nil config gracefully", function()
            -- Should not error
            EPGP:ApplyReceivedConfig(nil)
            assert.are.equal(100, GPCalc:GetBaseGP())
        end)

        it("preserves values not overridden", function()
            SimpleEPGP.db.profile.min_ep = 500
            local config = {
                sm = {},
                io = {},
                om = 0.75,
                dm = 0.1,
                bg = 200,
                si = 141,
            }
            EPGP:ApplyReceivedConfig(config)
            -- min_ep should not be changed by config sync
            assert.are.equal(500, SimpleEPGP.db.profile.min_ep)
        end)
    end)

    describe("config in standings sync roundtrip", function()
        it("includes config in STANDINGS_SYNC broadcast", function()
            -- Set custom config on officer side
            SimpleEPGP.db.profile.base_gp = 200
            SimpleEPGP.db.profile.os_multiplier = 0.75
            SimpleEPGP.db.profile.slot_multipliers = { INVTYPE_HEAD = 1.5 }

            -- Trigger broadcast (officer side)
            EPGP:BroadcastStandings()

            -- Check that a message was sent
            assert.is_true(#_G._testSentMessages > 0)

            -- Deserialize and verify config is present
            local msg = _G._testSentMessages[#_G._testSentMessages].message
            local success, payload = Comms:Deserialize(msg)
            assert.is_true(success)
            assert.is_not_nil(payload.config)
            assert.are.equal(200, payload.config.bg)
            assert.are.equal(0.75, payload.config.om)
            assert.are.equal(1.5, payload.config.sm.INVTYPE_HEAD)
        end)

        it("includes config in whisper response to STANDINGS_REQUEST", function()
            -- Set custom config on officer side
            SimpleEPGP.db.profile.base_gp = 300
            SimpleEPGP.db.profile.de_multiplier = 0.15

            -- Simulate receiving a request from a non-officer
            Comms:SendStandingsRequest()
            local reqMsg = _G._testSentMessages[1].message
            for i = #_G._testSentMessages, 1, -1 do
                _G._testSentMessages[i] = nil
            end

            _G._testReceiveComm(Comms, "SimpleEPGP", reqMsg, "GUILD", "NonOfficer-Realm")

            -- Officer should have sent a response
            assert.are.equal(1, #_G._testSentMessages)
            assert.are.equal("WHISPER", _G._testSentMessages[1].distribution)

            -- Deserialize and verify config
            local success, payload = Comms:Deserialize(_G._testSentMessages[1].message)
            assert.is_true(success)
            assert.is_not_nil(payload.config)
            assert.are.equal(300, payload.config.bg)
            assert.are.equal(0.15, payload.config.dm)
        end)

        it("non-officer applies config from standings sync", function()
            -- Set custom config as if officer had it
            SimpleEPGP.db.profile.base_gp = 250
            SimpleEPGP.db.profile.standard_ilvl = 141
            SimpleEPGP.db.profile.os_multiplier = 0.6
            SimpleEPGP.db.profile.de_multiplier = 0.05
            SimpleEPGP.db.profile.slot_multipliers = { INVTYPE_HEAD = 1.75 }
            SimpleEPGP.db.profile.item_overrides = { [29759] = 777 }

            local config = EPGP:ExportConfig()

            -- Reset to defaults (simulating non-officer starting state)
            SimpleEPGP.db.profile.base_gp = 100
            SimpleEPGP.db.profile.standard_ilvl = 120
            SimpleEPGP.db.profile.os_multiplier = 0.5
            SimpleEPGP.db.profile.de_multiplier = 0.0
            SimpleEPGP.db.profile.slot_multipliers = {}
            SimpleEPGP.db.profile.item_overrides = {}

            -- Simulate non-officer
            local origCanView = C_GuildInfo.CanViewOfficerNote
            C_GuildInfo.CanViewOfficerNote = function() return false end

            -- Build and send sync message with config
            local syncData = {
                { n = "Alice", c = "PALADIN", e = 5000, g = 1000 },
            }
            local payload = Comms:Serialize({
                type = "STANDINGS_SYNC",
                standings = syncData,
                config = config,
            })
            _G._testReceiveComm(Comms, "SimpleEPGP", payload, "GUILD", "Officer-Realm")

            -- Verify config was applied
            assert.are.equal(250, GPCalc:GetBaseGP())
            assert.are.equal(141, GPCalc:GetStandardIlvl())
            assert.are.equal(0.6, SimpleEPGP.db.profile.os_multiplier)
            assert.are.equal(0.05, SimpleEPGP.db.profile.de_multiplier)
            assert.are.equal(1.75, SimpleEPGP.db.profile.slot_multipliers.INVTYPE_HEAD)
            assert.are.equal(777, SimpleEPGP.db.profile.item_overrides[29759])

            -- Verify standings also populated
            local alice = EPGP:GetPlayerInfo("Alice")
            assert.is_not_nil(alice)
            assert.are.equal(5000, alice.ep)
            assert.are.equal(1000, alice.gp)

            -- PR should use synced base_gp (250)
            local expectedPR = 5000 / (1000 + 250)
            assert.is_true(math.abs(alice.pr - expectedPR) < 0.01,
                "Expected PR " .. expectedPR .. " got " .. alice.pr)

            -- Restore
            C_GuildInfo.CanViewOfficerNote = origCanView
        end)

        it("non-officer uses synced base_gp for PR, not local default", function()
            -- Simulate non-officer
            local origCanView = C_GuildInfo.CanViewOfficerNote
            C_GuildInfo.CanViewOfficerNote = function() return false end

            -- Non-officer has default base_gp=100
            SimpleEPGP.db.profile.base_gp = 100

            -- Officer sends sync with base_gp=500
            local syncData = {
                { n = "Bob", c = "ROGUE", e = 2000, g = 500 },
            }
            local payload = Comms:Serialize({
                type = "STANDINGS_SYNC",
                standings = syncData,
                config = { sm = {}, io = {}, om = 0.5, dm = 0.0, bg = 500, si = 120 },
            })
            _G._testReceiveComm(Comms, "SimpleEPGP", payload, "GUILD", "Officer-Realm")

            local bob = EPGP:GetPlayerInfo("Bob")
            assert.is_not_nil(bob)
            -- PR = 2000 / (500 + 500) = 2.0
            local expectedPR = 2000 / (500 + 500)
            assert.is_true(math.abs(bob.pr - expectedPR) < 0.01,
                "Expected PR " .. expectedPR .. " with synced base_gp=500, got " .. bob.pr)

            -- Restore
            C_GuildInfo.CanViewOfficerNote = origCanView
        end)

        it("officer ignores config from other officers", function()
            -- Officer can view notes (default in stubs)
            SimpleEPGP.db.profile.base_gp = 100

            -- Receive sync with different base_gp from another officer
            local payload = Comms:Serialize({
                type = "STANDINGS_SYNC",
                standings = { { n = "Test", c = "MAGE", e = 100, g = 50 } },
                config = { sm = {}, io = {}, om = 0.9, dm = 0.5, bg = 999, si = 141 },
            })
            _G._testReceiveComm(Comms, "SimpleEPGP", payload, "GUILD", "OtherOfficer-Realm")

            -- Officer's config should NOT have changed
            assert.are.equal(100, SimpleEPGP.db.profile.base_gp)
            assert.are.equal(120, SimpleEPGP.db.profile.standard_ilvl)
            assert.are.equal(0.5, SimpleEPGP.db.profile.os_multiplier)
        end)

        it("handles sync without config (backward compat)", function()
            -- Simulate non-officer
            local origCanView = C_GuildInfo.CanViewOfficerNote
            C_GuildInfo.CanViewOfficerNote = function() return false end

            -- Sync message without config field (older officer version)
            local payload = Comms:Serialize({
                type = "STANDINGS_SYNC",
                standings = { { n = "Charlie", c = "HUNTER", e = 3000, g = 700 } },
                -- no config field
            })
            _G._testReceiveComm(Comms, "SimpleEPGP", payload, "GUILD", "OldOfficer-Realm")

            -- Should still work, config stays at defaults
            assert.are.equal(100, SimpleEPGP.db.profile.base_gp)
            local charlie = EPGP:GetPlayerInfo("Charlie")
            assert.is_not_nil(charlie)
            assert.are.equal(3000, charlie.ep)

            -- Restore
            C_GuildInfo.CanViewOfficerNote = origCanView
        end)
    end)

    describe("config affects GP calculations after sync", function()
        it("synced slot multiplier changes GP calc", function()
            -- Simulate non-officer
            local origCanView = C_GuildInfo.CanViewOfficerNote
            C_GuildInfo.CanViewOfficerNote = function() return false end

            -- Calculate GP with default HEAD multiplier (1.0)
            local link = _G._testItemDB[29759][2]  -- ilvl 120 HEAD
            local gpDefault = GPCalc:CalculateGP(link)

            -- Receive config with HEAD = 2.0
            EPGP:ApplyReceivedConfig({
                sm = { INVTYPE_HEAD = 2.0 },
                io = {},
                om = 0.5,
                dm = 0.0,
                bg = 100,
                si = 120,
            })

            local gpAfterSync = GPCalc:CalculateGP(link)
            assert.is_true(gpAfterSync > gpDefault,
                "Expected higher GP with 2.0 HEAD multiplier")
            -- Should be approximately 2x
            assert.is_true(math.abs(gpAfterSync - gpDefault * 2) <= 1,
                "Expected ~2x GP, got " .. gpAfterSync .. " vs " .. gpDefault)

            -- Restore
            C_GuildInfo.CanViewOfficerNote = origCanView
        end)

        it("synced item override takes precedence", function()
            -- Simulate non-officer
            local origCanView = C_GuildInfo.CanViewOfficerNote
            C_GuildInfo.CanViewOfficerNote = function() return false end

            local link = _G._testItemDB[29759][2]  -- ilvl 120 HEAD

            -- Receive config with item override
            EPGP:ApplyReceivedConfig({
                sm = {},
                io = { [29759] = 777 },
                om = 0.5,
                dm = 0.0,
                bg = 100,
                si = 120,
            })

            local gp = GPCalc:CalculateGP(link)
            assert.are.equal(777, gp)

            -- Restore
            C_GuildInfo.CanViewOfficerNote = origCanView
        end)

        it("synced OS multiplier changes bid GP", function()
            -- Simulate non-officer
            local origCanView = C_GuildInfo.CanViewOfficerNote
            C_GuildInfo.CanViewOfficerNote = function() return false end

            local link = _G._testItemDB[29759][2]

            -- Receive config with OS multiplier of 0.75
            EPGP:ApplyReceivedConfig({
                sm = {},
                io = {},
                om = 0.75,
                dm = 0.0,
                bg = 100,
                si = 120,
            })

            local msGP = GPCalc:GetBidGP(link, "MS")
            local osGP = GPCalc:GetBidGP(link, "OS")
            -- OS should be 75% of MS
            assert.are.equal(math.floor(msGP * 0.75), osGP)

            -- Restore
            C_GuildInfo.CanViewOfficerNote = origCanView
        end)

        it("synced standard_ilvl changes GP calculation", function()
            -- Simulate non-officer
            local origCanView = C_GuildInfo.CanViewOfficerNote
            C_GuildInfo.CanViewOfficerNote = function() return false end

            local link = _G._testItemDB[29759][2]  -- ilvl 120 HEAD
            local gpBefore = GPCalc:CalculateGP(link)

            -- Receive config with higher standard_ilvl (lowers base mult)
            EPGP:ApplyReceivedConfig({
                sm = {},
                io = {},
                om = 0.5,
                dm = 0.0,
                bg = 100,
                si = 141,
            })

            local gpAfter = GPCalc:CalculateGP(link)
            assert.is_true(gpAfter < gpBefore,
                "Expected lower GP with higher standard_ilvl")

            -- Restore
            C_GuildInfo.CanViewOfficerNote = origCanView
        end)
    end)

    describe("ExportConfig roundtrip through serialization", function()
        it("config survives serialize/deserialize roundtrip", function()
            -- Set up complex config
            SimpleEPGP.db.profile.base_gp = 250
            SimpleEPGP.db.profile.standard_ilvl = 141
            SimpleEPGP.db.profile.gp_base_multiplier = 50
            SimpleEPGP.db.profile.os_multiplier = 0.75
            SimpleEPGP.db.profile.de_multiplier = 0.1
            SimpleEPGP.db.profile.slot_multipliers = {
                INVTYPE_HEAD = 1.5,
                INVTYPE_TRINKET = 2.0,
            }
            SimpleEPGP.db.profile.item_overrides = {
                [29759] = 500,
            }

            local config = EPGP:ExportConfig()

            -- Serialize and deserialize (simulates network transit)
            local serialized = Comms:Serialize({
                type = "STANDINGS_SYNC",
                standings = {},
                config = config,
            })
            local success, payload = Comms:Deserialize(serialized)
            assert.is_true(success)

            local received = payload.config
            assert.is_not_nil(received)
            assert.are.equal(250, received.bg)
            assert.are.equal(141, received.si)
            assert.are.equal(50, received.bm)
            assert.are.equal(0.75, received.om)
            assert.are.equal(0.1, received.dm)
            assert.are.equal(1.5, received.sm.INVTYPE_HEAD)
            assert.are.equal(2.0, received.sm.INVTYPE_TRINKET)
            assert.are.equal(500, received.io[29759])
        end)
    end)
end)
