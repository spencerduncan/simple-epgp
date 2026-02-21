-----------------------------------------------------------------------
-- test_standby_manager.lua -- Unit tests for StandbyManager UI module
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

-- Load the StandbyManager module
dofile("SimpleEPGP/UI/StandbyManager.lua")

-- Initialize addon (triggers OnInitialize + OnEnable for addon and all modules)
_G._testInitAddon("SimpleEPGP")

describe("StandbyManager", function()
    local SM

    before_each(function()
        SM = SimpleEPGP:GetModule("StandbyManager")
        -- Reset standby list
        SimpleEPGP.db.standby = {}

        -- Clear print log
        SimpleEPGP._printLog = {}

        -- Open the UI so RefreshDisplay runs
        SM:Show()
    end)

    after_each(function()
        SM:Hide()
    end)

    describe("Module registration", function()
        it("is registered as a module", function()
            assert.is_not_nil(SM)
        end)

        it("has Show/Hide/Toggle methods", function()
            assert.is_function(SM.Show)
            assert.is_function(SM.Hide)
            assert.is_function(SM.Toggle)
        end)
    end)

    describe("Add player", function()
        it("adds a player to the standby list", function()
            local result = SM:Add("Player5")
            assert.is_true(result)
            local list = SM:GetStandbyList()
            assert.are.equal(1, #list)
            assert.are.equal("Player5", list[1])
        end)

        it("adds multiple players", function()
            SM:Add("Alpha")
            SM:Add("Beta")
            SM:Add("Gamma")
            local list = SM:GetStandbyList()
            assert.are.equal(3, #list)
            assert.are.equal("Alpha", list[1])
            assert.are.equal("Beta", list[2])
            assert.are.equal("Gamma", list[3])
        end)

        it("prevents duplicate entries", function()
            SM:Add("Player5")
            local result = SM:Add("Player5")
            assert.is_false(result)
            local list = SM:GetStandbyList()
            assert.are.equal(1, #list)
        end)

        it("rejects empty name", function()
            local result = SM:Add("")
            assert.is_false(result)
            local list = SM:GetStandbyList()
            assert.are.equal(0, #list)
        end)

        it("rejects nil name", function()
            local result = SM:Add(nil)
            assert.is_false(result)
            local list = SM:GetStandbyList()
            assert.are.equal(0, #list)
        end)
    end)

    describe("Remove player", function()
        it("removes a player from the standby list", function()
            SM:Add("Player3")
            SM:Add("Player4")
            local result = SM:Remove("Player3")
            assert.is_true(result)
            local list = SM:GetStandbyList()
            assert.are.equal(1, #list)
            assert.are.equal("Player4", list[1])
        end)

        it("returns false for non-existent player", function()
            SM:Add("Player3")
            local result = SM:Remove("NonExistent")
            assert.is_false(result)
            local list = SM:GetStandbyList()
            assert.are.equal(1, #list)
        end)

        it("handles removing from empty list", function()
            local result = SM:Remove("Nobody")
            assert.is_false(result)
        end)

        it("removes the correct player when multiple exist", function()
            SM:Add("Alpha")
            SM:Add("Beta")
            SM:Add("Gamma")
            SM:Remove("Beta")
            local list = SM:GetStandbyList()
            assert.are.equal(2, #list)
            assert.are.equal("Alpha", list[1])
            assert.are.equal("Gamma", list[2])
        end)
    end)

    describe("Clear all", function()
        it("clears the entire standby list", function()
            SM:Add("Player1")
            SM:Add("Player2")
            SM:Add("Player3")
            local count = SM:Clear()
            assert.are.equal(3, count)
            local list = SM:GetStandbyList()
            assert.are.equal(0, #list)
        end)

        it("returns 0 when clearing empty list", function()
            local count = SM:Clear()
            assert.are.equal(0, count)
        end)
    end)

    describe("GetStandbyList", function()
        it("returns the db standby table", function()
            SimpleEPGP.db.standby = { "A", "B", "C" }
            local list = SM:GetStandbyList()
            assert.are.equal(3, #list)
            assert.are.equal("A", list[1])
            assert.are.equal("B", list[2])
            assert.are.equal("C", list[3])
        end)

        it("returns empty table when standby is nil", function()
            SimpleEPGP.db.standby = nil
            local list = SM:GetStandbyList()
            assert.are.same({}, list)
        end)
    end)

    describe("Toggle", function()
        it("hides when shown", function()
            SM:Show()
            SM:Toggle()
            -- After toggle from shown, frame should be hidden
            -- (Toggle calls Hide which hides the frame)
        end)

        it("shows when hidden", function()
            SM:Hide()
            SM:Toggle()
            -- After toggle from hidden, frame should be shown
        end)
    end)

    describe("Integration with db.standby", function()
        it("reflects changes made directly to db.standby", function()
            -- Simulate standby changes from slash commands
            SimpleEPGP.db.standby = { "SlashAdded1", "SlashAdded2" }
            local list = SM:GetStandbyList()
            assert.are.equal(2, #list)
            assert.are.equal("SlashAdded1", list[1])
        end)

        it("Add writes to the same db.standby table", function()
            SM:Add("UIAdded")
            assert.are.equal(1, #SimpleEPGP.db.standby)
            assert.are.equal("UIAdded", SimpleEPGP.db.standby[1])
        end)

        it("Remove modifies the same db.standby table", function()
            SimpleEPGP.db.standby = { "ToRemove", "ToKeep" }
            SM:Remove("ToRemove")
            assert.are.equal(1, #SimpleEPGP.db.standby)
            assert.are.equal("ToKeep", SimpleEPGP.db.standby[1])
        end)

        it("Clear replaces db.standby with empty table", function()
            SimpleEPGP.db.standby = { "A", "B", "C" }
            SM:Clear()
            assert.are.equal(0, #SimpleEPGP.db.standby)
        end)
    end)

    describe("Print messages", function()
        it("prints add confirmation", function()
            SM:Add("TestPlayer")
            local found = false
            for _, msg in ipairs(SimpleEPGP._printLog) do
                if msg:find("TestPlayer") and msg:find("added") then
                    found = true
                end
            end
            assert.is_true(found, "Expected add confirmation message")
        end)

        it("prints duplicate warning", function()
            SM:Add("DupeTest")
            SimpleEPGP._printLog = {}
            SM:Add("DupeTest")
            local found = false
            for _, msg in ipairs(SimpleEPGP._printLog) do
                if msg:find("DupeTest") and msg:find("already") then
                    found = true
                end
            end
            assert.is_true(found, "Expected duplicate warning message")
        end)

        it("prints remove confirmation", function()
            SM:Add("RemoveMe")
            SimpleEPGP._printLog = {}
            SM:Remove("RemoveMe")
            local found = false
            for _, msg in ipairs(SimpleEPGP._printLog) do
                if msg:find("RemoveMe") and msg:find("removed") then
                    found = true
                end
            end
            assert.is_true(found, "Expected remove confirmation message")
        end)

        it("prints clear confirmation", function()
            SM:Add("A")
            SM:Add("B")
            SimpleEPGP._printLog = {}
            SM:Clear()
            local found = false
            for _, msg in ipairs(SimpleEPGP._printLog) do
                if msg:find("cleared") and msg:find("2") then
                    found = true
                end
            end
            assert.is_true(found, "Expected clear confirmation message")
        end)
    end)
end)
