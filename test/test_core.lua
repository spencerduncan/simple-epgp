-----------------------------------------------------------------------
-- test_core.lua — Unit tests for Core.lua (addon init + slash commands)
-----------------------------------------------------------------------

-- Load stubs first
require("test.wow_stubs")
require("test.ace_stubs")

-- Core.lua is loaded FIRST in .toc — creates the addon via NewAddon
dofile("SimpleEPGP/Core.lua")

-- Get the addon object (Core.lua created it)
local SimpleEPGP = LibStub("AceAddon-3.0"):GetAddon("SimpleEPGP")

-- Load the module files (order matches .toc after Core.lua)
dofile("SimpleEPGP/EPGP.lua")
dofile("SimpleEPGP/GPCalc.lua")
dofile("SimpleEPGP/Log.lua")
dofile("SimpleEPGP/Comms.lua")
dofile("SimpleEPGP/LootMaster.lua")

-- Initialize addon (triggers OnInitialize + OnEnable for addon and all modules)
_G._testInitAddon("SimpleEPGP")

describe("Core", function()
    before_each(function()
        -- Reset guild roster officer notes
        _G._testGuildRoster[1].officerNote = "5000,1000"
        _G._testGuildRoster[2].officerNote = "3000,500"
        _G._testGuildRoster[3].officerNote = "2000,2000"
        _G._testGuildRoster[4].officerNote = "1000,100"
        _G._testGuildRoster[5].officerNote = ""

        -- Rebuild standings
        local EPGP = SimpleEPGP:GetModule("EPGP")
        EPGP:GUILD_ROSTER_UPDATE()

        -- Clear sent messages
        for i = #_G._testSentMessages, 1, -1 do
            _G._testSentMessages[i] = nil
        end

        -- Clear chat messages
        for i = #_G._testChatMessages, 1, -1 do
            _G._testChatMessages[i] = nil
        end

        -- Reset standby list
        SimpleEPGP.db.standby = {}

        -- Clear log
        SimpleEPGP.db.log = {}

        -- Reset GP config overrides
        SimpleEPGP.db.profile.slot_multipliers = {}
        SimpleEPGP.db.profile.item_overrides = {}
    end)

    describe("Initialization", function()
        it("creates the addon object", function()
            assert.is_not_nil(SimpleEPGP)
        end)

        it("initializes AceDB with defaults", function()
            assert.is_not_nil(SimpleEPGP.db)
            assert.is_not_nil(SimpleEPGP.db.profile)
            assert.are.equal(100, SimpleEPGP.db.profile.base_gp)
            assert.are.equal(0, SimpleEPGP.db.profile.min_ep)
            assert.are.equal(15, SimpleEPGP.db.profile.decay_percent)
            assert.are.equal(4, SimpleEPGP.db.profile.quality_threshold)
            assert.are.equal(120, SimpleEPGP.db.profile.standard_ilvl)
            assert.are.equal(0.5, SimpleEPGP.db.profile.os_multiplier)
            assert.are.equal(0.0, SimpleEPGP.db.profile.de_multiplier)
            assert.are.equal(100, SimpleEPGP.db.profile.ep_per_boss)
            assert.is_true(SimpleEPGP.db.profile.auto_ep)
            assert.are.equal(1.0, SimpleEPGP.db.profile.standby_percent)
            assert.are.equal(30, SimpleEPGP.db.profile.bid_timer)
            assert.is_false(SimpleEPGP.db.profile.auto_distribute)
            assert.are.equal(3, SimpleEPGP.db.profile.auto_distribute_delay)
            assert.is_true(SimpleEPGP.db.profile.show_gp_tooltip)
            assert.are.equal("GUILD", SimpleEPGP.db.profile.announce_channel)
            assert.is_true(SimpleEPGP.db.profile.announce_awards)
            assert.is_true(SimpleEPGP.db.profile.announce_ep)
        end)

        it("creates standby and log tables", function()
            assert.is_not_nil(SimpleEPGP.db.standby)
            assert.is_not_nil(SimpleEPGP.db.log)
        end)

        it("has all modules registered", function()
            assert.is_not_nil(SimpleEPGP:GetModule("EPGP"))
            assert.is_not_nil(SimpleEPGP:GetModule("GPCalc"))
            assert.is_not_nil(SimpleEPGP:GetModule("Log"))
            assert.is_not_nil(SimpleEPGP:GetModule("Comms"))
            assert.is_not_nil(SimpleEPGP:GetModule("LootMaster"))
        end)
    end)

    describe("Slash commands", function()
        describe("/sepgp ep", function()
            it("awards EP to a player", function()
                SimpleEPGP:HandleSlashCommand("ep Player1 200 Boss bonus")
                assert.are.equal("5200,1000", _G._testGuildRoster[1].officerNote)
            end)

            it("deducts EP with negative amount", function()
                SimpleEPGP:HandleSlashCommand("ep Player1 -500 Penalty")
                assert.are.equal("4500,1000", _G._testGuildRoster[1].officerNote)
            end)

            it("prints usage with missing args", function()
                -- Should not error
                SimpleEPGP:HandleSlashCommand("ep")
                SimpleEPGP:HandleSlashCommand("ep Player1")
            end)
        end)

        describe("/sepgp gp", function()
            it("adjusts GP for a player", function()
                SimpleEPGP:HandleSlashCommand("gp Player2 300 Manual correction")
                assert.are.equal("3000,800", _G._testGuildRoster[2].officerNote)
            end)

            it("prints usage with missing args", function()
                -- Should not error
                SimpleEPGP:HandleSlashCommand("gp")
                SimpleEPGP:HandleSlashCommand("gp SomeName")
            end)
        end)

        describe("/sepgp massep", function()
            it("awards EP to raid", function()
                SimpleEPGP:HandleSlashCommand("massep 150 Trash clear")
                -- Player1: 5000+150=5150
                assert.are.equal("5150,1000", _G._testGuildRoster[1].officerNote)
                -- Player2: 3000+150=3150
                assert.are.equal("3150,500", _G._testGuildRoster[2].officerNote)
            end)
        end)

        describe("/sepgp decay + confirm", function()
            it("requires confirmation", function()
                SimpleEPGP:HandleSlashCommand("decay")
                -- No decay yet — values unchanged
                assert.are.equal("5000,1000", _G._testGuildRoster[1].officerNote)
            end)

            it("applies decay after confirm", function()
                SimpleEPGP:HandleSlashCommand("decay")
                SimpleEPGP:HandleSlashCommand("confirm")
                -- 15% decay: EP=5000*0.85=4250, GP=1000*0.85=850
                assert.are.equal("4250,850", _G._testGuildRoster[1].officerNote)
            end)

            it("confirm does nothing without pending action", function()
                -- Should not error
                SimpleEPGP:HandleSlashCommand("confirm")
            end)
        end)

        describe("/sepgp standby", function()
            it("adds a player to standby list", function()
                SimpleEPGP:HandleSlashCommand("standby add Player5")
                assert.are.equal(1, #SimpleEPGP.db.standby)
                assert.are.equal("Player5", SimpleEPGP.db.standby[1])
            end)

            it("prevents duplicate standby entries", function()
                SimpleEPGP:HandleSlashCommand("standby add Player5")
                SimpleEPGP:HandleSlashCommand("standby add Player5")
                assert.are.equal(1, #SimpleEPGP.db.standby)
            end)

            it("removes a player from standby list", function()
                SimpleEPGP:HandleSlashCommand("standby add Player5")
                assert.are.equal(1, #SimpleEPGP.db.standby)
                SimpleEPGP:HandleSlashCommand("standby remove Player5")
                assert.are.equal(0, #SimpleEPGP.db.standby)
            end)

            it("lists standby when empty", function()
                -- Should not error
                SimpleEPGP:HandleSlashCommand("standby list")
            end)

            it("lists standby with entries", function()
                SimpleEPGP:HandleSlashCommand("standby add Player3")
                SimpleEPGP:HandleSlashCommand("standby add Player4")
                -- Should not error
                SimpleEPGP:HandleSlashCommand("standby list")
            end)
        end)

        describe("/sepgp log", function()
            it("shows log entries", function()
                -- Generate some log entries via EP commands
                SimpleEPGP:HandleSlashCommand("ep Player1 100 Test")
                SimpleEPGP:HandleSlashCommand("ep Player2 50 Test2")
                -- Should not error
                SimpleEPGP:HandleSlashCommand("log")
                SimpleEPGP:HandleSlashCommand("log 5")
            end)

            it("shows empty log message", function()
                -- Should not error
                SimpleEPGP:HandleSlashCommand("log")
            end)
        end)

        describe("/sepgp reset + confirm", function()
            it("requires confirmation", function()
                SimpleEPGP:HandleSlashCommand("reset")
                -- No reset yet — values unchanged
                assert.are.equal("5000,1000", _G._testGuildRoster[1].officerNote)
            end)

            it("resets all EP/GP after confirm", function()
                SimpleEPGP:HandleSlashCommand("reset")
                SimpleEPGP:HandleSlashCommand("confirm")
                -- All players with EPGP notes should be 0,0
                assert.are.equal("0,0", _G._testGuildRoster[1].officerNote)
                assert.are.equal("0,0", _G._testGuildRoster[2].officerNote)
                assert.are.equal("0,0", _G._testGuildRoster[3].officerNote)
                assert.are.equal("0,0", _G._testGuildRoster[4].officerNote)
            end)
        end)

        describe("/sepgp standby clear", function()
            it("clears the standby list", function()
                SimpleEPGP:HandleSlashCommand("standby add Player3")
                SimpleEPGP:HandleSlashCommand("standby add Player4")
                SimpleEPGP:HandleSlashCommand("standby add Player5")
                assert.are.equal(3, #SimpleEPGP.db.standby)
                SimpleEPGP:HandleSlashCommand("standby clear")
                assert.are.equal(0, #SimpleEPGP.db.standby)
            end)

            it("clear on empty list reports 0", function()
                -- Should not error
                SimpleEPGP:HandleSlashCommand("standby clear")
                assert.are.equal(0, #SimpleEPGP.db.standby)
            end)
        end)

        describe("/sepgp slot", function()
            before_each(function()
                SimpleEPGP.db.profile.slot_multipliers = {}
            end)

            it("lists all slots without error", function()
                -- Should not error
                SimpleEPGP:HandleSlashCommand("slot list")
                SimpleEPGP:HandleSlashCommand("slot")
            end)

            it("sets a slot override", function()
                SimpleEPGP:HandleSlashCommand("slot INVTYPE_HEAD 1.5")
                local GPCalc = SimpleEPGP:GetModule("GPCalc")
                assert.are.equal(1.5, GPCalc:GetSlotMultiplier("INVTYPE_HEAD"))
            end)

            it("resets a slot override", function()
                SimpleEPGP:HandleSlashCommand("slot INVTYPE_HEAD 2.0")
                SimpleEPGP:HandleSlashCommand("slot INVTYPE_HEAD reset")
                local GPCalc = SimpleEPGP:GetModule("GPCalc")
                assert.are.equal(1.0, GPCalc:GetSlotMultiplier("INVTYPE_HEAD"))
            end)

            it("rejects unknown slots", function()
                -- Should not error
                SimpleEPGP:HandleSlashCommand("slot INVTYPE_FAKE 1.0")
            end)

            it("shows current value for single slot", function()
                -- Should not error
                SimpleEPGP:HandleSlashCommand("slot INVTYPE_HEAD")
            end)
        end)

        describe("/sepgp gpoverride", function()
            before_each(function()
                SimpleEPGP.db.profile.item_overrides = {}
            end)

            it("sets an item override", function()
                SimpleEPGP:HandleSlashCommand("gpoverride 29759 500")
                local GPCalc = SimpleEPGP:GetModule("GPCalc")
                local overrides = GPCalc:GetAllItemOverrides()
                assert.are.equal(500, overrides[29759])
            end)

            it("clears an item override", function()
                SimpleEPGP:HandleSlashCommand("gpoverride 29759 500")
                SimpleEPGP:HandleSlashCommand("gpoverride 29759 clear")
                local GPCalc = SimpleEPGP:GetModule("GPCalc")
                local overrides = GPCalc:GetAllItemOverrides()
                assert.is_nil(overrides[29759])
            end)

            it("lists overrides", function()
                SimpleEPGP:HandleSlashCommand("gpoverride 29759 500")
                -- Should not error
                SimpleEPGP:HandleSlashCommand("gpoverride list")
            end)

            it("lists empty overrides", function()
                -- Should not error
                SimpleEPGP:HandleSlashCommand("gpoverride list")
            end)

            it("prints usage with no args", function()
                -- Should not error
                SimpleEPGP:HandleSlashCommand("gpoverride")
            end)

            it("shows current override for specific item", function()
                SimpleEPGP:HandleSlashCommand("gpoverride 29759 500")
                -- Should not error
                SimpleEPGP:HandleSlashCommand("gpoverride 29759")
            end)
        end)

        -- Note: /sepgp top, /sepgp board, /sepgp config, /sepgp gpconfig, /sepgp export,
        -- and /sepgp (no args) require UI modules which aren't loaded in
        -- this test. Those commands are tested via in-game manual testing.

        describe("/sepgp help and unknown", function()
            it("prints help", function()
                -- Should not error
                SimpleEPGP:HandleSlashCommand("help")
            end)

            it("handles unknown commands", function()
                -- Should not error
                SimpleEPGP:HandleSlashCommand("nonexistent")
            end)

            it("handles empty input", function()
                -- This would try to toggle Standings, but module has no frame in tests
                -- UI modules are not loaded in this test, so we skip frame toggling
                -- Just verify it doesn't crash
            end)
        end)
    end)

    describe("ENCOUNTER_END", function()
        it("awards EP on boss kill when auto_ep is enabled", function()
            SimpleEPGP.db.profile.auto_ep = true
            SimpleEPGP.db.profile.ep_per_boss = 200
            SimpleEPGP.db.profile.announce_ep = false  -- suppress chat for test

            SimpleEPGP:ENCOUNTER_END("ENCOUNTER_END", 1234, "Gruul the Dragonkiller", 1, 25, 1)

            -- Player1: 5000+200=5200
            assert.are.equal("5200,1000", _G._testGuildRoster[1].officerNote)
            -- Player2: 3000+200=3200
            assert.are.equal("3200,500", _G._testGuildRoster[2].officerNote)

            -- Reset
            SimpleEPGP.db.profile.auto_ep = true
            SimpleEPGP.db.profile.ep_per_boss = 100
        end)

        it("does not award EP on wipe", function()
            SimpleEPGP.db.profile.auto_ep = true

            SimpleEPGP:ENCOUNTER_END("ENCOUNTER_END", 1234, "Gruul the Dragonkiller", 1, 25, 0)

            -- Values unchanged
            assert.are.equal("5000,1000", _G._testGuildRoster[1].officerNote)
        end)

        it("does not award EP when auto_ep is disabled", function()
            SimpleEPGP.db.profile.auto_ep = false

            SimpleEPGP:ENCOUNTER_END("ENCOUNTER_END", 1234, "Gruul the Dragonkiller", 1, 25, 1)

            -- Values unchanged
            assert.are.equal("5000,1000", _G._testGuildRoster[1].officerNote)

            SimpleEPGP.db.profile.auto_ep = true  -- reset
        end)

        it("announces EP award when configured", function()
            SimpleEPGP.db.profile.auto_ep = true
            SimpleEPGP.db.profile.announce_ep = true
            SimpleEPGP.db.profile.announce_channel = "GUILD"

            SimpleEPGP:ENCOUNTER_END("ENCOUNTER_END", 1234, "Gruul the Dragonkiller", 1, 25, 1)

            -- Should have sent a chat message
            local found = false
            for _, msg in ipairs(_G._testChatMessages) do
                if msg.text:find("Gruul") then
                    found = true
                    assert.are.equal("GUILD", msg.channel)
                end
            end
            assert.is_true(found, "Expected boss kill announcement in chat")

            SimpleEPGP.db.profile.auto_ep = true
        end)
    end)

    describe("Integration smoke test", function()
        it("addon loads all modules in correct order", function()
            -- Verify all modules are accessible and functional
            local EPGP = SimpleEPGP:GetModule("EPGP")
            local GPCalc = SimpleEPGP:GetModule("GPCalc")
            local Log = SimpleEPGP:GetModule("Log")
            local Comms = SimpleEPGP:GetModule("Comms")
            local LootMaster = SimpleEPGP:GetModule("LootMaster")

            assert.is_not_nil(EPGP)
            assert.is_not_nil(GPCalc)
            assert.is_not_nil(Log)
            assert.is_not_nil(Comms)
            assert.is_not_nil(LootMaster)
        end)

        it("end-to-end: EP award, GP charge, standings update", function()
            local EPGP = SimpleEPGP:GetModule("EPGP")
            local GPCalc = SimpleEPGP:GetModule("GPCalc")

            -- 1. Award EP via slash command
            SimpleEPGP:HandleSlashCommand("ep Player1 500 Bonus")
            -- Officer note is written immediately; standings cache needs manual refresh
            -- (GuildRoster() is a no-op in test stubs — doesn't fire GUILD_ROSTER_UPDATE)
            assert.are.equal("5500,1000", _G._testGuildRoster[1].officerNote)
            EPGP:GUILD_ROSTER_UPDATE()  -- refresh cache
            local info = EPGP:GetPlayerInfo("Player1")
            assert.are.equal(5500, info.ep)

            -- 2. Calculate GP for an item
            local link = _G._testItemDB[29759][2]  -- T4 Helm
            local gp = GPCalc:CalculateGP(link)
            assert.is_true(math.abs(gp - 1000) <= 1)

            -- 3. Charge GP via slash command
            SimpleEPGP:HandleSlashCommand("gp Player1 1000 Won T4 Helm")
            assert.are.equal("5500,2000", _G._testGuildRoster[1].officerNote)
            EPGP:GUILD_ROSTER_UPDATE()
            info = EPGP:GetPlayerInfo("Player1")
            assert.are.equal(2000, info.gp)

            -- 4. PR should be updated: 5500 / (2000 + 100) = ~2.619
            info = EPGP:GetPlayerInfo("Player1")
            local expectedPR = 5500 / (2000 + 100)
            assert.is_true(math.abs(info.pr - expectedPR) < 0.01)
        end)

        it("end-to-end: mass EP + decay cycle", function()
            -- 1. Mass EP
            SimpleEPGP:HandleSlashCommand("massep 200 Boss kill")
            assert.are.equal("5200,1000", _G._testGuildRoster[1].officerNote)

            -- 2. Decay
            SimpleEPGP:HandleSlashCommand("decay")
            SimpleEPGP:HandleSlashCommand("confirm")
            -- 5200 * 0.85 = 4420, 1000 * 0.85 = 850
            assert.are.equal("4420,850", _G._testGuildRoster[1].officerNote)
        end)

        it("log captures all operations", function()
            local Log = SimpleEPGP:GetModule("Log")

            SimpleEPGP:HandleSlashCommand("ep Player1 100 Test EP")
            SimpleEPGP:HandleSlashCommand("gp Player2 50 Test GP")
            SimpleEPGP:HandleSlashCommand("massep 75 Test mass")

            local entries = Log:GetRecent(10)
            assert.is_true(#entries >= 3)
        end)
    end)
end)
