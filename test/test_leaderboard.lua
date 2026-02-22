-----------------------------------------------------------------------
-- test_leaderboard.lua -- Unit tests for Leaderboard UI module (groupings)
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

-- Load module files (order matches .toc)
dofile("SimpleEPGP/EPGP.lua")
dofile("SimpleEPGP/GPCalc.lua")
dofile("SimpleEPGP/Log.lua")
dofile("SimpleEPGP/Comms.lua")
dofile("SimpleEPGP/LootMaster.lua")
dofile("SimpleEPGP/UI/Utils.lua")
dofile("SimpleEPGP/UI/Leaderboard.lua")

-- Initialize addon
_G._testInitAddon("SimpleEPGP")

describe("Leaderboard", function()
    local Leaderboard
    local EPGP

    before_each(function()
        -- Reset officer notes to known values
        -- Player1: WARRIOR, EP=5000, GP=1000 -> PR=5000/(1000+100)=4.545
        -- Player2: PALADIN, EP=3000, GP=500  -> PR=3000/(500+100)=5.0
        -- Player3: HUNTER,  EP=2000, GP=2000 -> PR=2000/(2000+100)=0.952
        -- Player4: MAGE,    EP=1000, GP=100  -> PR=1000/(100+100)=5.0
        -- Player5: PRIEST,  EP=0,    GP=0    -> PR=0/(0+100)=0.0
        _G._testGuildRoster[1].officerNote = "5000,1000"
        _G._testGuildRoster[2].officerNote = "3000,500"
        _G._testGuildRoster[3].officerNote = "2000,2000"
        _G._testGuildRoster[4].officerNote = "1000,100"
        _G._testGuildRoster[5].officerNote = ""

        Leaderboard = SimpleEPGP:GetModule("Leaderboard")
        EPGP = SimpleEPGP:GetModule("EPGP")

        -- Build standings from guild roster
        EPGP:GUILD_ROSTER_UPDATE()

        -- Reset to defaults
        Leaderboard:SetGrouping("none")
        Leaderboard:SetFilter("all")

        -- Clear print log
        SimpleEPGP._printLog = {}

        -- Open the leaderboard so Refresh runs
        Leaderboard:Show()
    end)

    after_each(function()
        Leaderboard:Hide()
    end)

    describe("Module registration", function()
        it("is registered as a module", function()
            assert.is_not_nil(Leaderboard)
        end)

        it("has Show/Hide/Toggle methods", function()
            assert.is_function(Leaderboard.Show)
            assert.is_function(Leaderboard.Hide)
            assert.is_function(Leaderboard.Toggle)
        end)

        it("has grouping accessor methods", function()
            assert.is_function(Leaderboard.GetGrouping)
            assert.is_function(Leaderboard.SetGrouping)
            assert.is_function(Leaderboard.IsGroupCollapsed)
            assert.is_function(Leaderboard.SetGroupCollapsed)
            assert.is_function(Leaderboard.GetDisplayItems)
        end)
    end)

    describe("Flat mode (no grouping)", function()
        it("returns all players as row items", function()
            local items = Leaderboard:GetDisplayItems()
            assert.are.equal(5, #items)
            for _, item in ipairs(items) do
                assert.are.equal("row", item.type)
            end
        end)

        it("items have sequential ranks", function()
            local items = Leaderboard:GetDisplayItems()
            for i, item in ipairs(items) do
                assert.are.equal(i, item.rank)
            end
        end)

        it("is the default grouping mode", function()
            assert.are.equal("none", Leaderboard:GetGrouping())
        end)
    end)

    describe("Group by class", function()
        before_each(function()
            Leaderboard:SetGrouping("class")
        end)

        it("sets grouping mode to class", function()
            assert.are.equal("class", Leaderboard:GetGrouping())
        end)

        it("produces headers and rows", function()
            local items = Leaderboard:GetDisplayItems()
            local headerCount = 0
            local rowCount = 0
            for _, item in ipairs(items) do
                if item.type == "header" then
                    headerCount = headerCount + 1
                elseif item.type == "row" then
                    rowCount = rowCount + 1
                end
            end
            -- 5 players across 5 different classes = 5 headers
            assert.are.equal(5, headerCount)
            assert.are.equal(5, rowCount)
        end)

        it("groups players by class", function()
            local items = Leaderboard:GetDisplayItems()
            -- Each header should have count = 1 since each class has 1 player
            for _, item in ipairs(items) do
                if item.type == "header" then
                    assert.are.equal(1, item.count)
                end
            end
        end)

        it("headers have correct display names", function()
            local items = Leaderboard:GetDisplayItems()
            local displayNames = {}
            for _, item in ipairs(items) do
                if item.type == "header" then
                    displayNames[item.displayName] = true
                end
            end
            assert.is_true(displayNames["Hunter"])
            assert.is_true(displayNames["Mage"])
            assert.is_true(displayNames["Paladin"])
            assert.is_true(displayNames["Priest"])
            assert.is_true(displayNames["Warrior"])
        end)

        it("sorts groups alphabetically by class", function()
            local items = Leaderboard:GetDisplayItems()
            local order = {}
            for _, item in ipairs(items) do
                if item.type == "header" then
                    order[#order + 1] = item.displayName
                end
            end
            -- CLASS_ORDER is: DRUID, HUNTER, MAGE, PALADIN, PRIEST, ROGUE, SHAMAN, WARLOCK, WARRIOR
            -- We have: Hunter, Mage, Paladin, Priest, Warrior
            assert.are.equal("Hunter", order[1])
            assert.are.equal("Mage", order[2])
            assert.are.equal("Paladin", order[3])
            assert.are.equal("Priest", order[4])
            assert.are.equal("Warrior", order[5])
        end)

        it("ranks players within each group", function()
            local items = Leaderboard:GetDisplayItems()
            for _, item in ipairs(items) do
                if item.type == "row" then
                    -- Each group has 1 player so rank should be 1
                    assert.are.equal(1, item.rank)
                end
            end
        end)
    end)

    describe("Group by role", function()
        before_each(function()
            Leaderboard:SetGrouping("role")
        end)

        it("sets grouping mode to role", function()
            assert.are.equal("role", Leaderboard:GetGrouping())
        end)

        it("produces role group headers", function()
            local items = Leaderboard:GetDisplayItems()
            local headers = {}
            for _, item in ipairs(items) do
                if item.type == "header" then
                    headers[item.displayName] = item.count
                end
            end
            -- Tank: WARRIOR (Player1) = 1
            -- Healer: PALADIN (Player2), PRIEST (Player5) = 2
            -- DPS: HUNTER (Player3), MAGE (Player4) = 2
            assert.are.equal(1, headers["Tank"])
            assert.are.equal(2, headers["Healer"])
            assert.are.equal(2, headers["DPS"])
        end)

        it("sorts groups in Tank/Healer/DPS order", function()
            local items = Leaderboard:GetDisplayItems()
            local order = {}
            for _, item in ipairs(items) do
                if item.type == "header" then
                    order[#order + 1] = item.displayName
                end
            end
            assert.are.equal("Tank", order[1])
            assert.are.equal("Healer", order[2])
            assert.are.equal("DPS", order[3])
        end)

        it("sorts players by PR within each role group", function()
            local items = Leaderboard:GetDisplayItems()
            local currentGroup = nil
            local lastPR = nil
            for _, item in ipairs(items) do
                if item.type == "header" then
                    currentGroup = item.displayName
                    lastPR = nil
                elseif item.type == "row" then
                    if lastPR then
                        assert.is_true(lastPR >= item.entry.pr,
                            "Expected PR descending in group " .. (currentGroup or "?"))
                    end
                    lastPR = item.entry.pr
                end
            end
        end)
    end)

    describe("Role mapping", function()
        it("maps all WoW classes to roles", function()
            local roleMap = Leaderboard:GetClassRoleMap()
            local classes = {
                "WARRIOR", "PALADIN", "HUNTER", "ROGUE",
                "PRIEST", "SHAMAN", "MAGE", "WARLOCK", "DRUID",
            }
            for _, class in ipairs(classes) do
                assert.is_not_nil(roleMap[class],
                    "Expected role mapping for " .. class)
            end
        end)

        it("maps tank classes correctly", function()
            local roleMap = Leaderboard:GetClassRoleMap()
            assert.are.equal("Tank", roleMap["WARRIOR"])
        end)

        it("maps healer classes correctly", function()
            local roleMap = Leaderboard:GetClassRoleMap()
            assert.are.equal("Healer", roleMap["PALADIN"])
            assert.are.equal("Healer", roleMap["PRIEST"])
            assert.are.equal("Healer", roleMap["SHAMAN"])
            assert.are.equal("Healer", roleMap["DRUID"])
        end)

        it("maps DPS classes correctly", function()
            local roleMap = Leaderboard:GetClassRoleMap()
            assert.are.equal("DPS", roleMap["HUNTER"])
            assert.are.equal("DPS", roleMap["ROGUE"])
            assert.are.equal("DPS", roleMap["MAGE"])
            assert.are.equal("DPS", roleMap["WARLOCK"])
        end)
    end)

    describe("Class display names", function()
        it("has display names for all classes", function()
            local names = Leaderboard:GetClassDisplayNames()
            local classes = {
                "WARRIOR", "PALADIN", "HUNTER", "ROGUE",
                "PRIEST", "SHAMAN", "MAGE", "WARLOCK", "DRUID",
            }
            for _, class in ipairs(classes) do
                assert.is_not_nil(names[class],
                    "Expected display name for " .. class)
            end
        end)

        it("returns proper-cased names", function()
            local names = Leaderboard:GetClassDisplayNames()
            assert.are.equal("Warrior", names["WARRIOR"])
            assert.are.equal("Druid", names["DRUID"])
        end)
    end)

    describe("Collapsing groups", function()
        before_each(function()
            Leaderboard:SetGrouping("role")
        end)

        it("groups start expanded", function()
            assert.is_false(Leaderboard:IsGroupCollapsed("Tank"))
            assert.is_false(Leaderboard:IsGroupCollapsed("Healer"))
            assert.is_false(Leaderboard:IsGroupCollapsed("DPS"))
        end)

        it("collapsing a group removes its rows from display", function()
            local itemsBefore = Leaderboard:GetDisplayItems()
            local countBefore = #itemsBefore

            Leaderboard:SetGroupCollapsed("Healer", true)
            assert.is_true(Leaderboard:IsGroupCollapsed("Healer"))

            local itemsAfter = Leaderboard:GetDisplayItems()
            -- Should have 2 fewer items (Healer group has 2 players)
            assert.are.equal(countBefore - 2, #itemsAfter)
        end)

        it("collapsed header still shows with collapsed flag", function()
            Leaderboard:SetGroupCollapsed("Tank", true)
            local items = Leaderboard:GetDisplayItems()
            local found = false
            for _, item in ipairs(items) do
                if item.type == "header" and item.key == "Tank" then
                    assert.is_true(item.collapsed)
                    found = true
                end
            end
            assert.is_true(found, "Expected to find Tank header")
        end)

        it("expanding a collapsed group restores its rows", function()
            Leaderboard:SetGroupCollapsed("DPS", true)
            local collapsed = Leaderboard:GetDisplayItems()

            Leaderboard:SetGroupCollapsed("DPS", false)
            local expanded = Leaderboard:GetDisplayItems()

            assert.is_true(#expanded > #collapsed)
        end)

        it("collapsing all groups shows only headers", function()
            Leaderboard:SetGroupCollapsed("Tank", true)
            Leaderboard:SetGroupCollapsed("Healer", true)
            Leaderboard:SetGroupCollapsed("DPS", true)

            local items = Leaderboard:GetDisplayItems()
            for _, item in ipairs(items) do
                assert.are.equal("header", item.type)
            end
            assert.are.equal(3, #items)
        end)

        it("changing grouping mode resets collapsed state", function()
            Leaderboard:SetGroupCollapsed("Tank", true)
            assert.is_true(Leaderboard:IsGroupCollapsed("Tank"))

            Leaderboard:SetGrouping("class")
            assert.is_false(Leaderboard:IsGroupCollapsed("Tank"))
            assert.is_false(Leaderboard:IsGroupCollapsed("WARRIOR"))
        end)
    end)

    describe("Filter interaction with grouping", function()
        it("grouping works with raiders filter", function()
            -- Set min_ep to 1000 so Player5 (EP=0) is excluded
            SimpleEPGP.db.profile.min_ep = 1000

            Leaderboard:SetFilter("raiders")
            Leaderboard:SetGrouping("class")

            local items = Leaderboard:GetDisplayItems()
            local rowCount = 0
            for _, item in ipairs(items) do
                if item.type == "row" then
                    rowCount = rowCount + 1
                end
            end
            -- Player5 (Priest, EP=0) should be excluded
            assert.are.equal(4, rowCount)

            -- Reset
            SimpleEPGP.db.profile.min_ep = 0
        end)
    end)

    describe("Grouping mode transitions", function()
        it("switches from none to class", function()
            Leaderboard:SetGrouping("none")
            assert.are.equal("none", Leaderboard:GetGrouping())

            Leaderboard:SetGrouping("class")
            assert.are.equal("class", Leaderboard:GetGrouping())
        end)

        it("switches from class to role", function()
            Leaderboard:SetGrouping("class")
            Leaderboard:SetGrouping("role")
            assert.are.equal("role", Leaderboard:GetGrouping())
        end)

        it("switches from role back to none", function()
            Leaderboard:SetGrouping("role")
            Leaderboard:SetGrouping("none")
            assert.are.equal("none", Leaderboard:GetGrouping())
        end)

        it("rejects invalid grouping mode", function()
            Leaderboard:SetGrouping("class")
            Leaderboard:SetGrouping("invalid")
            -- Should remain unchanged
            assert.are.equal("class", Leaderboard:GetGrouping())
        end)
    end)

    describe("Toggle", function()
        it("hides when shown", function()
            Leaderboard:Show()
            Leaderboard:Toggle()
            Leaderboard:Toggle()
            assert.is_true(true)
        end)

        it("shows when hidden", function()
            Leaderboard:Hide()
            Leaderboard:Toggle()
            assert.is_true(true)
        end)
    end)

    describe("AnnounceTop", function()
        it("sends chat messages for top players", function()
            _G._testChatMessages = {}
            Leaderboard:AnnounceTop(3, "GUILD")
            -- Should have 1 header + 3 player messages = 4 total
            assert.are.equal(4, #_G._testChatMessages)
        end)

        it("prints error when no standings", function()
            -- Temporarily clear standings by setting all notes to empty
            for i = 1, 5 do
                _G._testGuildRoster[i].officerNote = ""
            end
            EPGP:GUILD_ROSTER_UPDATE()

            -- With min_ep > 0, no one is eligible
            SimpleEPGP.db.profile.min_ep = 100
            SimpleEPGP._printLog = {}
            Leaderboard:AnnounceTop(5, "GUILD")

            local found = false
            for _, msg in ipairs(SimpleEPGP._printLog) do
                if msg:find("No eligible") then
                    found = true
                end
            end
            assert.is_true(found)

            SimpleEPGP.db.profile.min_ep = 0
        end)
    end)

    describe("Display items with multiple players per class", function()
        it("handles multiple players in same class", function()
            -- Make Player4 and Player5 both MAGE
            local origClass5 = _G._testGuildRoster[5].class
            _G._testGuildRoster[5].class = "MAGE"
            _G._testGuildRoster[5].officerNote = "500,100"
            EPGP:GUILD_ROSTER_UPDATE()

            Leaderboard:SetGrouping("class")
            local items = Leaderboard:GetDisplayItems()

            -- Find the Mage header
            local mageHeader = nil
            for _, item in ipairs(items) do
                if item.type == "header" and item.key == "MAGE" then
                    mageHeader = item
                end
            end
            assert.is_not_nil(mageHeader)
            assert.are.equal(2, mageHeader.count)

            -- Restore
            _G._testGuildRoster[5].class = origClass5
            _G._testGuildRoster[5].officerNote = ""
            EPGP:GUILD_ROSTER_UPDATE()
        end)
    end)
end)
