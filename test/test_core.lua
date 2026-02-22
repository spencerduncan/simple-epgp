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

        -- Clear print log for assertion checking
        SimpleEPGP._printLog = {}
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

    describe("StripRealm", function()
        it("strips realm suffix from a name", function()
            assert.are.equal("Player", SimpleEPGP.StripRealm("Player-Dreamscythe"))
        end)

        it("returns name unchanged when no realm suffix", function()
            assert.are.equal("Player", SimpleEPGP.StripRealm("Player"))
        end)

        it("returns nil for nil input", function()
            assert.is_nil(SimpleEPGP.StripRealm(nil))
        end)

        it("returns empty string for empty string input", function()
            assert.are.equal("", SimpleEPGP.StripRealm(""))
        end)

        it("handles names with special characters before dash", function()
            assert.are.equal("Ärch", SimpleEPGP.StripRealm("Ärch-SomeRealm"))
        end)

        it("strips only the first dash (realm names can have hyphens)", function()
            assert.are.equal("Player", SimpleEPGP.StripRealm("Player-Some-Realm"))
        end)

        it("handles single character names", function()
            assert.are.equal("X", SimpleEPGP.StripRealm("X-Realm"))
        end)

        it("handles name that is just a dash", function()
            -- Edge case: match returns "" or nil, fallback to original
            local result = SimpleEPGP.StripRealm("-Realm")
            assert.is_not_nil(result)
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
                SimpleEPGP:HandleSlashCommand("ep")
                SimpleEPGP:HandleSlashCommand("ep Player1")
                local found = false
                for _, msg in ipairs(SimpleEPGP._printLog) do
                    if msg:find("Usage") then found = true; break end
                end
                assert.is_true(found, "Expected usage message in print log")
            end)
        end)

        describe("/sepgp gp", function()
            it("adjusts GP for a player", function()
                SimpleEPGP:HandleSlashCommand("gp Player2 300 Manual correction")
                assert.are.equal("3000,800", _G._testGuildRoster[2].officerNote)
            end)

            it("prints usage with missing args", function()
                SimpleEPGP:HandleSlashCommand("gp")
                SimpleEPGP:HandleSlashCommand("gp SomeName")
                local found = false
                for _, msg in ipairs(SimpleEPGP._printLog) do
                    if msg:find("Usage") then found = true; break end
                end
                assert.is_true(found, "Expected usage message in print log")
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
                SimpleEPGP:HandleSlashCommand("confirm")
                local found = false
                for _, msg in ipairs(SimpleEPGP._printLog) do
                    if msg:find("Nothing to confirm") then found = true; break end
                end
                assert.is_true(found, "Expected 'Nothing to confirm' message")
                -- Values unchanged
                assert.are.equal("5000,1000", _G._testGuildRoster[1].officerNote)
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
                SimpleEPGP:HandleSlashCommand("standby list")
                local found = false
                for _, msg in ipairs(SimpleEPGP._printLog) do
                    if msg:find("empty") then found = true; break end
                end
                assert.is_true(found, "Expected 'empty' in standby list output")
            end)

            it("lists standby with entries", function()
                SimpleEPGP:HandleSlashCommand("standby add Player3")
                SimpleEPGP:HandleSlashCommand("standby add Player4")
                SimpleEPGP._printLog = {}
                SimpleEPGP:HandleSlashCommand("standby list")
                local foundCount = false
                local foundPlayer3 = false
                local foundPlayer4 = false
                for _, msg in ipairs(SimpleEPGP._printLog) do
                    if msg:find("2") then foundCount = true end
                    if msg:find("Player3") then foundPlayer3 = true end
                    if msg:find("Player4") then foundPlayer4 = true end
                end
                assert.is_true(foundCount, "Expected standby count in output")
                assert.is_true(foundPlayer3, "Expected Player3 in standby list")
                assert.is_true(foundPlayer4, "Expected Player4 in standby list")
            end)
        end)

        describe("/sepgp log", function()
            it("shows log entries", function()
                -- Generate some log entries via EP commands
                SimpleEPGP:HandleSlashCommand("ep Player1 100 Test")
                SimpleEPGP:HandleSlashCommand("ep Player2 50 Test2")
                SimpleEPGP._printLog = {}
                SimpleEPGP:HandleSlashCommand("log")
                local foundHeader = false
                for _, msg in ipairs(SimpleEPGP._printLog) do
                    if msg:find("Last") and msg:find("log entries") then
                        foundHeader = true; break
                    end
                end
                assert.is_true(foundHeader, "Expected 'Last N log entries' header")
                -- Should have printed more than just the header (entries too)
                assert.is_true(#SimpleEPGP._printLog >= 2, "Expected log entries in output")
            end)

            it("shows empty log message", function()
                SimpleEPGP:HandleSlashCommand("log")
                local found = false
                for _, msg in ipairs(SimpleEPGP._printLog) do
                    if msg:find("No log entries") then found = true; break end
                end
                assert.is_true(found, "Expected 'No log entries' message")
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

            it("lists all slots", function()
                SimpleEPGP:HandleSlashCommand("slot list")
                local foundHeader = false
                local foundSlot = false
                for _, msg in ipairs(SimpleEPGP._printLog) do
                    if msg:find("Slot multipliers") then foundHeader = true end
                    if msg:find("INVTYPE_HEAD") then foundSlot = true end
                end
                assert.is_true(foundHeader, "Expected 'Slot multipliers' header")
                assert.is_true(foundSlot, "Expected slot names in output")
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
                SimpleEPGP:HandleSlashCommand("slot INVTYPE_FAKE 1.0")
                local found = false
                for _, msg in ipairs(SimpleEPGP._printLog) do
                    if msg:find("Unknown slot") then found = true; break end
                end
                assert.is_true(found, "Expected 'Unknown slot' message")
            end)

            it("shows current value for single slot", function()
                SimpleEPGP:HandleSlashCommand("slot INVTYPE_HEAD")
                local found = false
                for _, msg in ipairs(SimpleEPGP._printLog) do
                    if msg:find("INVTYPE_HEAD") then found = true; break end
                end
                assert.is_true(found, "Expected slot name in output")
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
                SimpleEPGP._printLog = {}
                SimpleEPGP:HandleSlashCommand("gpoverride list")
                local foundHeader = false
                local foundItem = false
                for _, msg in ipairs(SimpleEPGP._printLog) do
                    if msg:find("Item GP overrides") then foundHeader = true end
                    if msg:find("500") and msg:find("GP") then foundItem = true end
                end
                assert.is_true(foundHeader, "Expected 'Item GP overrides' header")
                assert.is_true(foundItem, "Expected override entry with 500 GP")
            end)

            it("lists empty overrides", function()
                SimpleEPGP:HandleSlashCommand("gpoverride list")
                local found = false
                for _, msg in ipairs(SimpleEPGP._printLog) do
                    if msg:find("No item GP overrides") then found = true; break end
                end
                assert.is_true(found, "Expected 'No item GP overrides' message")
            end)

            it("prints usage with no args", function()
                SimpleEPGP:HandleSlashCommand("gpoverride")
                local found = false
                for _, msg in ipairs(SimpleEPGP._printLog) do
                    if msg:find("Usage") then found = true; break end
                end
                assert.is_true(found, "Expected usage message in print log")
            end)

            it("shows current override for specific item", function()
                SimpleEPGP:HandleSlashCommand("gpoverride 29759 500")
                SimpleEPGP._printLog = {}
                SimpleEPGP:HandleSlashCommand("gpoverride 29759")
                local found = false
                for _, msg in ipairs(SimpleEPGP._printLog) do
                    if msg:find("500") and msg:find("override") then found = true; break end
                end
                assert.is_true(found, "Expected override value in output")
            end)
        end)

        describe("/sepgp loot", function()
            local LootMaster

            before_each(function()
                LootMaster = SimpleEPGP:GetModule("LootMaster")
                -- Reset loot sessions
                LootMaster.sessions = {}
                LootMaster.nextSessionId = 1
                -- Clear any pending loot state
                SimpleEPGP._pendingLootItemID = nil
                SimpleEPGP._pendingLootItemLink = nil
            end)

            it("starts a loot session from an item link", function()
                local link = _G._testItemDB[29759][2]
                SimpleEPGP:HandleSlashCommand("loot " .. link)
                -- Session should have been created
                assert.is_not_nil(LootMaster.sessions[1])
                assert.are.equal(link, LootMaster.sessions[1].itemLink)
            end)

            it("starts a loot session from an item ID", function()
                SimpleEPGP:HandleSlashCommand("loot 29759")
                -- Session should have been created
                assert.is_not_nil(LootMaster.sessions[1])
                -- The item link should be resolved from the ID
                local expectedLink = _G._testItemDB[29759][2]
                assert.are.equal(expectedLink, LootMaster.sessions[1].itemLink)
            end)

            it("calculates GP cost correctly for the session", function()
                local GPCalc = SimpleEPGP:GetModule("GPCalc")
                local link = _G._testItemDB[29759][2]
                local expectedGP = GPCalc:CalculateGP(link)
                SimpleEPGP:HandleSlashCommand("loot " .. link)
                assert.are.equal(expectedGP, LootMaster.sessions[1].gpCost)
            end)

            it("prints usage with no args", function()
                SimpleEPGP:HandleSlashCommand("loot")
                -- Should not create a session
                assert.is_nil(LootMaster.sessions[1])
            end)

            it("prints usage with invalid arg", function()
                SimpleEPGP:HandleSlashCommand("loot notanumber")
                assert.is_nil(LootMaster.sessions[1])
            end)

            it("handles uncached items by setting pending state", function()
                -- Item ID 99999 is not in _testItemDB, so GetItemInfo returns nil
                SimpleEPGP:HandleSlashCommand("loot 99999")
                -- Session should NOT have been created
                assert.is_nil(LootMaster.sessions[1])
                -- C_Timer.After fires immediately in test stubs, so the timeout
                -- callback runs synchronously and cleans up the pending state.
                -- Verify that the timeout message was printed.
                local foundTimeout = false
                for _, msg in ipairs(SimpleEPGP._printLog) do
                    if msg:find("Timed out") or msg:find("not cached") then
                        foundTimeout = true; break
                    end
                end
                assert.is_true(foundTimeout, "Expected timeout or uncached message")
                -- Pending state should be cleaned up by the timeout
                assert.is_nil(SimpleEPGP._pendingLootItemID)
            end)

            it("resolves pending session on GET_ITEM_INFO_RECEIVED", function()
                -- Manually set up pending state (simulating the uncached flow
                -- without relying on C_Timer.After timing)
                SimpleEPGP._pendingLootItemID = 29759
                SimpleEPGP._pendingLootItemLink = nil

                -- Fire the event
                SimpleEPGP:GET_ITEM_INFO_RECEIVED("GET_ITEM_INFO_RECEIVED", 29759)

                -- Pending state should be cleared
                assert.is_nil(SimpleEPGP._pendingLootItemID)
                assert.is_nil(SimpleEPGP._pendingLootItemLink)

                -- Session should have been created
                assert.is_not_nil(LootMaster.sessions[1])
                local expectedLink = _G._testItemDB[29759][2]
                assert.are.equal(expectedLink, LootMaster.sessions[1].itemLink)
            end)

            it("ignores GET_ITEM_INFO_RECEIVED for wrong item ID", function()
                SimpleEPGP._pendingLootItemID = 29759
                SimpleEPGP._pendingLootItemLink = nil

                -- Fire event for a different item
                SimpleEPGP:GET_ITEM_INFO_RECEIVED("GET_ITEM_INFO_RECEIVED", 12345)

                -- Pending state should still be set
                assert.are.equal(29759, SimpleEPGP._pendingLootItemID)
                -- No session created
                assert.is_nil(LootMaster.sessions[1])

                -- Clean up
                SimpleEPGP._pendingLootItemID = nil
            end)

            it("ignores GET_ITEM_INFO_RECEIVED when no pending item", function()
                -- Should not error
                SimpleEPGP:GET_ITEM_INFO_RECEIVED("GET_ITEM_INFO_RECEIVED", 29759)
                assert.is_nil(LootMaster.sessions[1])
            end)

            it("starts session with 0 GP for non-equippable items", function()
                -- Add a non-equippable item to the test DB temporarily
                _G._testItemDB[99990] = {
                    "Pattern: Something", nil, 4, 120, 70,
                    "Recipe", "Tailoring", 1, "", 123470, 0
                }
                -- Generate a fake link for it
                _G._testItemDB[99990][2] = "|cffa335ee|Hitem:99990::::::::70:::::::|h[Pattern: Something]|h|r"

                SimpleEPGP:HandleSlashCommand("loot 99990")
                assert.is_not_nil(LootMaster.sessions[1])
                assert.are.equal(0, LootMaster.sessions[1].gpCost)

                -- Clean up
                _G._testItemDB[99990] = nil
            end)

            it("increments session IDs across multiple loot commands", function()
                local link = _G._testItemDB[29759][2]
                SimpleEPGP:HandleSlashCommand("loot " .. link)
                SimpleEPGP:HandleSlashCommand("loot " .. link)
                assert.is_not_nil(LootMaster.sessions[1])
                assert.is_not_nil(LootMaster.sessions[2])
            end)
        end)

        -- Note: /sepgp top, /sepgp board, /sepgp config, /sepgp gpconfig, /sepgp export,
        -- and /sepgp (no args) require UI modules which aren't loaded in
        -- this test. Those commands are tested via in-game manual testing.

        describe("/sepgp help and unknown", function()
            it("prints help", function()
                SimpleEPGP:HandleSlashCommand("help")
                local foundHeader = false
                local foundCommand = false
                for _, msg in ipairs(SimpleEPGP._printLog) do
                    if msg:find("SimpleEPGP") and msg:find("commands") then
                        foundHeader = true
                    end
                    if msg:find("/sepgp ep") then foundCommand = true end
                end
                assert.is_true(foundHeader, "Expected help header with version")
                assert.is_true(foundCommand, "Expected command listing in help")
            end)

            it("handles unknown commands", function()
                SimpleEPGP:HandleSlashCommand("nonexistent")
                local found = false
                for _, msg in ipairs(SimpleEPGP._printLog) do
                    if msg:find("Unknown command") then found = true; break end
                end
                assert.is_true(found, "Expected 'Unknown command' message")
            end)

            it("handles empty input", function()
                -- Empty input tries to toggle Standings, which is not loaded
                -- in this test file — verify the expected module error
                local ok, err = pcall(function()
                    SimpleEPGP:HandleSlashCommand("")
                end)
                -- Standings module is not loaded, so this should error
                assert.is_false(ok, "Expected error when Standings module is not loaded")
                assert.is_truthy(err:find("Standings"), "Expected error to mention Standings")
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
