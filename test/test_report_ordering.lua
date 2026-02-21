-----------------------------------------------------------------------
-- test_report_ordering.lua — Tests for deterministic report output order
-- Verifies that all report/list commands produce ordered output.
-- Fixes GitHub issue #10.
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

-- The expected SLOT_ORDER from GPCalc.lua
local EXPECTED_SLOT_ORDER = {
    "INVTYPE_HEAD", "INVTYPE_CHEST", "INVTYPE_ROBE", "INVTYPE_LEGS",
    "INVTYPE_SHOULDER", "INVTYPE_HAND", "INVTYPE_FEET", "INVTYPE_WAIST",
    "INVTYPE_WRIST", "INVTYPE_NECK", "INVTYPE_FINGER", "INVTYPE_CLOAK",
    "INVTYPE_TRINKET",
    "INVTYPE_WEAPON", "INVTYPE_WEAPONMAINHAND", "INVTYPE_2HWEAPON",
    "INVTYPE_WEAPONOFFHAND", "INVTYPE_HOLDABLE", "INVTYPE_SHIELD",
    "INVTYPE_RANGED", "INVTYPE_RANGEDRIGHT", "INVTYPE_THROWN",
    "INVTYPE_RELIC",
    "INVTYPE_BODY", "INVTYPE_TABARD",
}

describe("Report ordering (#10)", function()
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

        -- Clear print log
        SimpleEPGP._printLog = {}

        -- Clear chat messages
        for i = #_G._testChatMessages, 1, -1 do
            _G._testChatMessages[i] = nil
        end

        -- Reset GP config overrides
        SimpleEPGP.db.profile.slot_multipliers = {}
        SimpleEPGP.db.profile.item_overrides = {}

        -- Reset standby list
        SimpleEPGP.db.standby = {}

        -- Clear log
        SimpleEPGP.db.log = {}
    end)

    describe("GetAllSlotInfo", function()
        it("returns slots in defined SLOT_ORDER", function()
            local GPCalc = SimpleEPGP:GetModule("GPCalc")
            local slots = GPCalc:GetAllSlotInfo()

            assert.are.equal(#EXPECTED_SLOT_ORDER, #slots)
            for i, info in ipairs(slots) do
                assert.are.equal(EXPECTED_SLOT_ORDER[i], info.key,
                    "Slot #" .. i .. " expected " .. EXPECTED_SLOT_ORDER[i] ..
                    " but got " .. tostring(info.key))
            end
        end)

        it("preserves order even with slot overrides", function()
            local GPCalc = SimpleEPGP:GetModule("GPCalc")
            -- Set overrides on several slots in arbitrary order
            GPCalc:SetSlotMultiplier("INVTYPE_TRINKET", 2.0)
            GPCalc:SetSlotMultiplier("INVTYPE_HEAD", 1.5)
            GPCalc:SetSlotMultiplier("INVTYPE_FEET", 0.9)

            local slots = GPCalc:GetAllSlotInfo()
            for i, info in ipairs(slots) do
                assert.are.equal(EXPECTED_SLOT_ORDER[i], info.key,
                    "Slot #" .. i .. " expected " .. EXPECTED_SLOT_ORDER[i] ..
                    " but got " .. tostring(info.key))
            end
        end)
    end)

    describe("/sepgp slot list", function()
        it("prints slots in defined order", function()
            SimpleEPGP:HandleSlashCommand("slot list")

            -- First line is the header "Slot multipliers:"
            -- Subsequent lines are the slot entries
            local log = SimpleEPGP._printLog
            assert.is_true(#log > 1, "Expected slot list output")

            -- Verify slot entries appear in SLOT_ORDER
            local slotIndex = 1
            for i = 2, #log do
                local line = log[i]
                local expectedSlot = EXPECTED_SLOT_ORDER[slotIndex]
                if expectedSlot then
                    assert.is_truthy(line:find(expectedSlot, 1, true),
                        "Line " .. i .. " expected to contain " .. expectedSlot ..
                        " but got: " .. line)
                    slotIndex = slotIndex + 1
                end
            end
        end)
    end)

    describe("/sepgp gpoverride list", function()
        it("prints overrides sorted by item ID", function()
            -- Set overrides with item IDs in non-sorted order
            local GPCalc = SimpleEPGP:GetModule("GPCalc")
            GPCalc:SetItemOverride(30627, 800)   -- Tsunami Talisman
            GPCalc:SetItemOverride(29759, 500)   -- Helm of the Fallen Champion
            GPCalc:SetItemOverride(29764, 300)   -- Pauldrons of the Fallen Hero

            SimpleEPGP._printLog = {}
            SimpleEPGP:HandleSlashCommand("gpoverride list")

            local log = SimpleEPGP._printLog
            -- First line: "Item GP overrides (3):"
            assert.is_truthy(log[1]:find("3"), "Expected count of 3 in header")

            -- Lines 2-4 should be sorted by item ID: 29759, 29764, 30627
            assert.is_truthy(log[2]:find("Helm"), "Line 2 should be item 29759 (Helm)")
            assert.is_truthy(log[3]:find("Pauldrons"), "Line 3 should be item 29764 (Pauldrons)")
            assert.is_truthy(log[4]:find("Tsunami"), "Line 4 should be item 30627 (Tsunami)")
        end)

        it("handles single override", function()
            local GPCalc = SimpleEPGP:GetModule("GPCalc")
            GPCalc:SetItemOverride(29759, 500)

            SimpleEPGP._printLog = {}
            SimpleEPGP:HandleSlashCommand("gpoverride list")

            local log = SimpleEPGP._printLog
            assert.is_truthy(log[1]:find("1"), "Expected count of 1 in header")
            assert.is_truthy(log[2]:find("500"), "Should show GP cost")
        end)

        it("handles empty overrides", function()
            SimpleEPGP._printLog = {}
            SimpleEPGP:HandleSlashCommand("gpoverride list")

            local log = SimpleEPGP._printLog
            assert.is_truthy(log[1]:find("No item GP overrides"),
                "Expected empty overrides message")
        end)
    end)

    describe("/sepgp log", function()
        it("prints log entries in chronological order (newest first)", function()
            -- Generate log entries
            SimpleEPGP:HandleSlashCommand("ep Player1 100 First")
            SimpleEPGP:HandleSlashCommand("ep Player2 200 Second")
            SimpleEPGP:HandleSlashCommand("ep Player3 300 Third")

            SimpleEPGP._printLog = {}
            SimpleEPGP:HandleSlashCommand("log")

            local log = SimpleEPGP._printLog
            -- First line is header "Last N log entries:"
            -- The log uses ipairs which iterates the GetRecent result (newest first)
            assert.is_true(#log >= 4, "Expected header + 3 log entries")

            -- Verify Third appears before Second, which appears before First
            -- (newest first)
            local thirdIdx, secondIdx, firstIdx
            for i = 2, #log do
                if log[i]:find("Third") then thirdIdx = i end
                if log[i]:find("Second") then secondIdx = i end
                if log[i]:find("First") then firstIdx = i end
            end

            assert.is_not_nil(thirdIdx, "Expected 'Third' in log output")
            assert.is_not_nil(secondIdx, "Expected 'Second' in log output")
            assert.is_not_nil(firstIdx, "Expected 'First' in log output")
            assert.is_true(thirdIdx < secondIdx, "Third should appear before Second (newest first)")
            assert.is_true(secondIdx < firstIdx, "Second should appear before First (newest first)")
        end)
    end)

    describe("/sepgp top", function()
        it("announces players in PR-sorted order", function()
            SimpleEPGP:HandleSlashCommand("top 3")

            -- Check chat messages are in PR order
            local msgs = _G._testChatMessages
            assert.is_true(#msgs >= 2, "Expected header + at least 1 player line")

            -- First message is the header
            assert.is_truthy(msgs[1].text:find("Top"), "First message should be header")

            -- Player lines should be in PR-descending order
            -- With default data: Player1 PR=5000/1100~4.55, Player4 PR=1000/200=5.0,
            -- Player2 PR=3000/600=5.0, Player3 PR=2000/2100~0.95
            -- Actually: base_gp=100, so effective GP = gp + base_gp
            -- Player1: 5000/(1000+100) = 4.545
            -- Player2: 3000/(500+100)  = 5.000
            -- Player3: 2000/(2000+100) = 0.952
            -- Player4: 1000/(100+100)  = 5.000
            -- Player5: 0/100 = 0 (no EP/GP note)
            -- Sorted: Player2=5.0, Player4=5.0, Player1=4.545, Player3=0.952
            -- With min_ep=0, all are eligible

            -- Verify #1 has higher or equal PR than #2
            local pr1 = msgs[2].text:match("PR: ([%d%.]+)")
            local pr2 = msgs[3].text:match("PR: ([%d%.]+)")
            if pr1 and pr2 then
                assert.is_true(tonumber(pr1) >= tonumber(pr2),
                    "Player #1 PR (" .. pr1 .. ") should be >= Player #2 PR (" .. pr2 .. ")")
            end
        end)
    end)
end)
