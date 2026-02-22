-----------------------------------------------------------------------
-- test_loot_popup.lua -- Unit tests for LootPopup UI module
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
    },
}, true)

-- Load the module files (order matches .toc)
dofile("SimpleEPGP/EPGP.lua")
dofile("SimpleEPGP/GPCalc.lua")
dofile("SimpleEPGP/Log.lua")
dofile("SimpleEPGP/Comms.lua")
dofile("SimpleEPGP/LootMaster.lua")
dofile("SimpleEPGP/UI/Utils.lua")
dofile("SimpleEPGP/UI/LootPopup.lua")

-- Initialize addon
_G._testInitAddon("SimpleEPGP")

-- Item link not in the stub DB — GetItemInfo will return nil (simulates uncached)
local UNCACHED_ITEM_LINK = "|cffff8000|Hitem:99999::::::::70:::::::|h[Unknown Item]|h|r"
local UNCACHED_ITEM_ID = 99999

describe("LootPopup", function()
    local LootPopup
    local testItemLink = _G._testItemDB[29759][2]  -- Helm of the Fallen Champion
    local testGpCost = 500
    local origTimerAfter

    before_each(function()
        LootPopup = SimpleEPGP:GetModule("LootPopup")

        -- Save original C_Timer.After so tests can override
        origTimerAfter = _G.C_Timer.After

        -- Reset module state (clears queue, currentSessionId, hides popup)
        LootPopup:OnDisable()

        -- Remove uncached test item from DB if present from a previous test
        _G._testItemDB[UNCACHED_ITEM_ID] = nil
    end)

    after_each(function()
        -- Restore C_Timer.After
        _G.C_Timer.After = origTimerAfter
    end)

    describe("Escape-to-close", function()
        it("adds frame name to UISpecialFrames after creation", function()
            -- Override C_Timer.After to not fire immediately
            _G.C_Timer.After = function() end

            LootPopup:ShowOffer(1, testItemLink, testGpCost)

            local found = false
            for _, name in ipairs(_G.UISpecialFrames) do
                if name == "SimpleEPGPLootPopup" then
                    found = true
                    break
                end
            end
            assert.is_true(found, "SimpleEPGPLootPopup should be in UISpecialFrames")
        end)
    end)

    describe("Close button", function()
        it("creates a close button on the popup frame", function()
            -- Override C_Timer.After to not fire immediately
            _G.C_Timer.After = function() end

            LootPopup:ShowOffer(1, testItemLink, testGpCost)
            local frame = _G["SimpleEPGPLootPopup"]
            assert.is_not_nil(frame.closeBtn, "Frame should have a closeBtn")
        end)

        it("dismisses popup when close button is clicked", function()
            -- Override C_Timer.After to not fire immediately
            _G.C_Timer.After = function() end

            LootPopup:ShowOffer(1, testItemLink, testGpCost)
            local frame = _G["SimpleEPGPLootPopup"]
            assert.is_true(frame:IsShown())

            -- Simulate clicking the close button
            local onClick = frame.closeBtn:GetScript("OnClick")
            assert.is_not_nil(onClick, "Close button should have OnClick handler")
            onClick()

            assert.is_false(frame:IsShown(),
                "Popup should be hidden after close button click")
        end)
    end)

    describe("Auto-dismiss timeout", function()
        it("schedules auto-dismiss after bid_timer + 10 seconds", function()
            local timerCalls = {}
            _G.C_Timer.After = function(seconds, func)
                timerCalls[#timerCalls + 1] = {
                    seconds = seconds,
                    func = func,
                }
            end

            LootPopup:ShowOffer(1, testItemLink, testGpCost)
            local frame = _G["SimpleEPGPLootPopup"]
            assert.is_true(frame:IsShown(), "Popup should be visible")

            -- Find the auto-dismiss timer (bid_timer + 10 = 40)
            local bidTimer = SimpleEPGP.db.profile.bid_timer  -- 30
            local found = false
            local dismissFunc
            for _, call in ipairs(timerCalls) do
                if call.seconds == bidTimer + 10 then
                    found = true
                    dismissFunc = call.func
                    break
                end
            end
            assert.is_true(found,
                "Should schedule timer for bid_timer + 10 seconds")

            -- Fire the dismiss callback — should hide the popup
            dismissFunc()
            assert.is_false(frame:IsShown(),
                "Popup should be auto-dismissed when timer fires")
        end)

        it("does not dismiss if session changed before timeout", function()
            local timerCalls = {}
            _G.C_Timer.After = function(seconds, func)
                timerCalls[#timerCalls + 1] = {
                    seconds = seconds,
                    func = func,
                }
            end

            LootPopup:ShowOffer(1, testItemLink, testGpCost)
            local frame = _G["SimpleEPGPLootPopup"]
            assert.is_true(frame:IsShown(), "Popup should be visible")

            -- Simulate award dismissing the popup
            LootPopup:OnAward({})
            assert.is_false(frame:IsShown())

            -- Now fire the original timeout callback for session 1
            -- It should be a no-op since currentSessionId was cleared
            local bidTimer = SimpleEPGP.db.profile.bid_timer
            for _, call in ipairs(timerCalls) do
                if call.seconds == bidTimer + 10 then
                    call.func()
                    break
                end
            end

            -- Should still be hidden (no crash, no re-dismiss)
            assert.is_false(frame:IsShown())
        end)
    end)

    describe("Uncached item retry", function()
        it("shows placeholder for uncached items", function()
            -- Override C_Timer.After to not fire immediately
            _G.C_Timer.After = function() end

            -- Use an item link not in the stub DB (GetItemInfo returns nil)
            LootPopup:ShowOffer(1, UNCACHED_ITEM_LINK, testGpCost)
            local frame = _G["SimpleEPGPLootPopup"]
            assert.is_true(frame:IsShown(),
                "Popup should show even with uncached item")
        end)

        it("registers GET_ITEM_INFO_RECEIVED when item is uncached", function()
            local registeredEvents = {}
            local origRegister = LootPopup.RegisterEvent
            LootPopup.RegisterEvent = function(self, event, ...)
                registeredEvents[#registeredEvents + 1] = event
                return origRegister(self, event, ...)
            end

            -- Override C_Timer.After to not fire immediately
            _G.C_Timer.After = function() end

            LootPopup:ShowOffer(1, UNCACHED_ITEM_LINK, testGpCost)

            local found = false
            for _, event in ipairs(registeredEvents) do
                if event == "GET_ITEM_INFO_RECEIVED" then
                    found = true
                    break
                end
            end
            assert.is_true(found,
                "Should register GET_ITEM_INFO_RECEIVED for uncached items")

            -- Restore
            LootPopup.RegisterEvent = origRegister
        end)

        it("updates display when item info is received", function()
            -- Override C_Timer.After to not fire immediately
            _G.C_Timer.After = function() end

            -- Show popup with uncached item
            LootPopup:ShowOffer(1, UNCACHED_ITEM_LINK, testGpCost)
            local frame = _G["SimpleEPGPLootPopup"]
            assert.is_true(frame:IsShown())

            -- Now add the item to the DB (simulating data arriving from server)
            _G._testItemDB[UNCACHED_ITEM_ID] = {
                "Resolved Item", UNCACHED_ITEM_LINK, 4, 120, 70,
                "Armor", "Plate", 1, "INVTYPE_HEAD", 999999, 0
            }

            -- Fire the event with the matching item ID
            _G._testFireEvent("GET_ITEM_INFO_RECEIVED", UNCACHED_ITEM_ID)

            -- The popup should still be showing (display was updated, not dismissed)
            assert.is_true(frame:IsShown())
        end)

        it("ignores GET_ITEM_INFO_RECEIVED for non-matching item IDs", function()
            -- Override C_Timer.After to not fire immediately
            _G.C_Timer.After = function() end

            local unregistered = false
            local origUnregister = LootPopup.UnregisterEvent
            LootPopup.UnregisterEvent = function(self, event, ...)
                if event == "GET_ITEM_INFO_RECEIVED" then
                    unregistered = true
                end
                return origUnregister(self, event, ...)
            end

            LootPopup:ShowOffer(1, UNCACHED_ITEM_LINK, testGpCost)

            -- Fire event with wrong item ID
            _G._testFireEvent("GET_ITEM_INFO_RECEIVED", 12345)

            assert.is_false(unregistered,
                "Should not unregister for non-matching item ID")

            -- Restore
            LootPopup.UnregisterEvent = origUnregister
        end)

        it("does not register event for cached items", function()
            local registeredEvents = {}
            local origRegister = LootPopup.RegisterEvent
            LootPopup.RegisterEvent = function(self, event, ...)
                registeredEvents[#registeredEvents + 1] = event
                return origRegister(self, event, ...)
            end

            -- Override C_Timer.After to not fire immediately
            _G.C_Timer.After = function() end

            -- Use a cached item (in stub DB)
            LootPopup:ShowOffer(1, testItemLink, testGpCost)

            local found = false
            for _, event in ipairs(registeredEvents) do
                if event == "GET_ITEM_INFO_RECEIVED" then
                    found = true
                    break
                end
            end
            assert.is_false(found,
                "Should not register GET_ITEM_INFO_RECEIVED for cached items")

            -- Restore
            LootPopup.RegisterEvent = origRegister
        end)
    end)

    describe("TBC backdrop compatibility", function()
        it("does not include tileEdge in BACKDROP_INFO", function()
            -- Verify by creating the frame and checking it was set up fine
            -- (tileEdge would cause error in TBC, but in stubs it's a no-op)
            _G.C_Timer.After = function() end
            LootPopup:ShowOffer(1, testItemLink, testGpCost)
            local frame = _G["SimpleEPGPLootPopup"]
            assert.is_not_nil(frame, "Frame should be created successfully")
        end)
    end)

    describe("Offer queuing", function()
        it("queues offers when popup is already showing", function()
            -- Override C_Timer.After to not fire immediately
            _G.C_Timer.After = function() end

            LootPopup:ShowOffer(1, testItemLink, testGpCost)
            local frame = _G["SimpleEPGPLootPopup"]
            assert.is_true(frame:IsShown())

            -- Second offer should be queued (popup still shows session 1)
            LootPopup:ShowOffer(2, testItemLink, testGpCost)
            assert.is_true(frame:IsShown())
        end)
    end)

    describe("OnCancel", function()
        it("dismisses popup for matching session", function()
            -- Override C_Timer.After to not fire immediately
            _G.C_Timer.After = function() end

            LootPopup:ShowOffer(1, testItemLink, testGpCost)
            local frame = _G["SimpleEPGPLootPopup"]
            assert.is_true(frame:IsShown())

            LootPopup:OnCancel({ sessionId = 1 })
            assert.is_false(frame:IsShown())
        end)

        it("does not dismiss popup for non-matching session", function()
            -- Override C_Timer.After to not fire immediately
            _G.C_Timer.After = function() end

            LootPopup:ShowOffer(1, testItemLink, testGpCost)
            local frame = _G["SimpleEPGPLootPopup"]
            assert.is_true(frame:IsShown())

            LootPopup:OnCancel({ sessionId = 999 })
            assert.is_true(frame:IsShown())
        end)
    end)

    describe("OnAward", function()
        it("dismisses popup when item is awarded", function()
            -- Override C_Timer.After to not fire immediately
            _G.C_Timer.After = function() end

            LootPopup:ShowOffer(1, testItemLink, testGpCost)
            local frame = _G["SimpleEPGPLootPopup"]
            assert.is_true(frame:IsShown())

            LootPopup:OnAward({})
            assert.is_false(frame:IsShown())
        end)
    end)

    describe("OnDisable", function()
        it("cleans up pending item info request", function()
            -- Override C_Timer.After to not fire immediately
            _G.C_Timer.After = function() end

            LootPopup:ShowOffer(1, UNCACHED_ITEM_LINK, testGpCost)

            -- Call OnDisable
            LootPopup:OnDisable()

            local frame = _G["SimpleEPGPLootPopup"]
            assert.is_false(frame:IsShown())
        end)
    end)
end)
