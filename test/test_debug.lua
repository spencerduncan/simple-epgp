-----------------------------------------------------------------------
-- test_debug.lua — Unit tests for Debug.lua (logging + debug commands)
-----------------------------------------------------------------------

-- Load stubs first
require("test.wow_stubs")
require("test.ace_stubs")

-- Load addon files in .toc order
dofile("SimpleEPGP/Core.lua")
dofile("SimpleEPGP/Debug.lua")
dofile("SimpleEPGP/EPGP.lua")
dofile("SimpleEPGP/GPCalc.lua")
dofile("SimpleEPGP/Log.lua")
dofile("SimpleEPGP/Comms.lua")
dofile("SimpleEPGP/LootMaster.lua")

local SimpleEPGP = LibStub("AceAddon-3.0"):GetAddon("SimpleEPGP")
_G._testInitAddon("SimpleEPGP")

local Debug = SimpleEPGP:GetModule("Debug")
local EPGP = SimpleEPGP:GetModule("EPGP")

describe("Debug", function()
    before_each(function()
        -- Reset guild roster
        _G._testGuildRoster[1].officerNote = "5000,1000"
        _G._testGuildRoster[2].officerNote = "3000,500"
        _G._testGuildRoster[3].officerNote = "2000,2000"
        _G._testGuildRoster[4].officerNote = "1000,100"
        _G._testGuildRoster[5].officerNote = ""

        -- Rebuild standings (this logs to debug log)
        EPGP:GUILD_ROSTER_UPDATE()

        -- Clear the debug log AFTER roster update so tests start clean
        _G.SimpleEPGPDebugLog = {}

        -- Clear chat messages
        for i = #_G._testChatMessages, 1, -1 do
            _G._testChatMessages[i] = nil
        end

        -- Ensure standby list exists
        SimpleEPGP.db.standby = {}

        -- Reset LootMaster sessions to avoid cross-test contamination
        local LootMaster = SimpleEPGP:GetModule("LootMaster")
        LootMaster.sessions = {}
        LootMaster.nextSessionId = 1

        -- Clear any pending item request from a previous test
        Debug._pendingItemID = nil
    end)

    describe("Logging", function()
        it("appends entries to _G.SimpleEPGPDebugLog", function()
            Debug:Log("INFO", "test message")
            assert.equals(1, #_G.SimpleEPGPDebugLog)
            assert.equals("INFO", _G.SimpleEPGPDebugLog[1][2])
            assert.equals("test message", _G.SimpleEPGPDebugLog[1][3])
        end)

        it("includes timestamp as first element", function()
            Debug:Log("INFO", "test")
            local ts = _G.SimpleEPGPDebugLog[1][1]
            assert.is_number(ts)
            assert.is_true(ts > 0)
        end)

        it("stores optional data table", function()
            Debug:Log("EPGP", "ModifyEP", { player = "Foo", amount = 100 })
            assert.equals(1, #_G.SimpleEPGPDebugLog)
            local data = _G.SimpleEPGPDebugLog[1][4]
            assert.is_table(data)
            assert.equals("Foo", data.player)
            assert.equals(100, data.amount)
        end)

        it("omits data when nil", function()
            Debug:Log("INFO", "no data")
            assert.is_nil(_G.SimpleEPGPDebugLog[1][4])
        end)

        it("prunes entries beyond MAX_ENTRIES (500)", function()
            for i = 1, 510 do
                Debug:Log("INFO", "entry " .. i)
            end
            assert.equals(500, #_G.SimpleEPGPDebugLog)
            -- First entry should be entry 11 (entries 1-10 pruned)
            assert.equals("entry 11", _G.SimpleEPGPDebugLog[1][3])
            assert.equals("entry 510", _G.SimpleEPGPDebugLog[500][3])
        end)

        it("initializes log table if nil", function()
            _G.SimpleEPGPDebugLog = nil
            Debug:Log("INFO", "after reset")
            assert.is_table(_G.SimpleEPGPDebugLog)
            assert.equals(1, #_G.SimpleEPGPDebugLog)
        end)
    end)

    describe("FormatEntry", function()
        it("formats a basic entry", function()
            local entry = { os.time(), "INFO", "test message" }
            local formatted = Debug:FormatEntry(entry)
            assert.is_string(formatted)
            assert.truthy(formatted:match("%[%d+:%d+:%d+%]"))
            assert.truthy(formatted:match("%[INFO%]"))
            assert.truthy(formatted:match("test message"))
        end)

        it("formats entry with data table", function()
            local entry = { os.time(), "EPGP", "ModifyEP", { player = "Foo" } }
            local formatted = Debug:FormatEntry(entry)
            assert.truthy(formatted:match("player=Foo"))
        end)
    end)

    describe("debug log command", function()
        it("prints last N entries", function()
            for i = 1, 5 do
                Debug:Log("INFO", "entry " .. i)
            end
            Debug:CmdLog({ "debug", "log", "3" })
            -- Should have printed to chat (via SimpleEPGP:Print)
            -- We can't easily capture Print output, but at least verify no errors
        end)

        it("handles empty log", function()
            _G.SimpleEPGPDebugLog = {}
            Debug:CmdLog({ "debug", "log" })
            -- Should print "Debug log is empty."
        end)
    end)

    describe("debug clear command", function()
        it("clears the log", function()
            Debug:Log("INFO", "entry 1")
            Debug:Log("INFO", "entry 2")
            assert.equals(2, #_G.SimpleEPGPDebugLog)

            Debug:CmdClear()
            -- CmdClear sets {} then logs one entry ("Debug log cleared by user")
            assert.equals(1, #_G.SimpleEPGPDebugLog)
            assert.equals("Debug log cleared by user", _G.SimpleEPGPDebugLog[1][3])
        end)
    end)

    describe("debug roster command", function()
        it("runs without error", function()
            Debug:CmdRoster()
            -- Should print roster members with EP/GP
        end)
    end)

    describe("debug note command", function()
        it("prints officer note for a known player", function()
            Debug:CmdNote({ "debug", "note", "Player1" })
        end)

        it("handles missing name arg", function()
            Debug:CmdNote({ "debug", "note" })
        end)

        it("handles unknown player", function()
            Debug:CmdNote({ "debug", "note", "NonExistent" })
        end)
    end)

    describe("debug status command", function()
        it("runs without error", function()
            Debug:CmdStatus()
        end)
    end)

    describe("debug fakeraid", function()
        -- Save originals before test manipulation
        local origIsInRaid = _G.IsInRaid
        local origGetNumGroupMembers = _G.GetNumGroupMembers

        after_each(function()
            -- Always restore to prevent leaking between tests
            _G.IsInRaid = origIsInRaid
            _G.GetNumGroupMembers = origGetNumGroupMembers
        end)

        it("overrides IsInRaid and GetNumGroupMembers", function()
            -- Before: these return test stub values
            assert.is_true(IsInRaid())

            -- Activate fakeraid (it saves current globals and overrides)
            Debug:CmdFakeRaid()

            -- After: should still return true (fakeraid sets it to true)
            assert.is_true(IsInRaid())
            assert.equals(5, GetNumGroupMembers())

            -- Check log entry
            local found = false
            for _, entry in ipairs(_G.SimpleEPGPDebugLog) do
                if entry[3] == "Fake raid activated" then
                    found = true
                    break
                end
            end
            assert.is_true(found)

            -- Deactivate
            Debug:CmdEndFakeRaid()
        end)

        it("endfakeraid restores originals", function()
            -- Save what IsInRaid is before fakeraid
            local before = IsInRaid

            Debug:CmdFakeRaid()
            -- Now IsInRaid is the override
            assert.is_not_equal(before, IsInRaid)

            Debug:CmdEndFakeRaid()
            -- Should be restored
            assert.equals(before, IsInRaid)
        end)

        it("prevents double activation", function()
            Debug:CmdFakeRaid()
            Debug:CmdFakeRaid()  -- Should print "already active"
            Debug:CmdEndFakeRaid()
        end)

        it("handles endfakeraid when not active", function()
            Debug:CmdEndFakeRaid()  -- Should print "No fake raid is active."
        end)
    end)

    describe("debug bosskill", function()
        it("fires ENCOUNTER_END handler", function()
            -- Clear the log first
            _G.SimpleEPGPDebugLog = {}

            Debug:CmdBossKill({ "debug", "bosskill", "Test", "Boss" })

            -- Should have logged the simulated boss kill
            local found = false
            for _, entry in ipairs(_G.SimpleEPGPDebugLog) do
                if entry[3] == "Simulating boss kill" then
                    found = true
                    assert.equals("Test Boss", entry[4].boss)
                    break
                end
            end
            assert.is_true(found)
        end)

        it("uses default boss name when none given", function()
            _G.SimpleEPGPDebugLog = {}
            Debug:CmdBossKill({ "debug", "bosskill" })

            local found = false
            for _, entry in ipairs(_G.SimpleEPGPDebugLog) do
                if entry[3] == "Simulating boss kill" then
                    found = true
                    assert.equals("Test Boss", entry[4].boss)
                    break
                end
            end
            assert.is_true(found)
        end)
    end)

    describe("debug loot", function()
        it("starts a loot session with cached item using real link", function()
            _G.SimpleEPGPDebugLog = {}
            Debug:CmdLoot({ "debug", "loot", "29759" })

            -- Check the loot session was created with the real link
            local LootMaster = SimpleEPGP:GetModule("LootMaster")
            local hasSession = false
            for _, session in pairs(LootMaster.sessions) do
                if not session.awarded then
                    hasSession = true
                    -- Verify it used the real link, not a fake one
                    assert.truthy(session.itemLink:find("Helm of the Fallen Champion"))
                    assert.falsy(session.itemLink:find("Test Item"))
                    break
                end
            end
            assert.is_true(hasSession)
        end)

        it("uses real GP calculation for cached items", function()
            _G.SimpleEPGPDebugLog = {}
            Debug:CmdLoot({ "debug", "loot", "29759" })

            -- Verify GP was calculated from real item data, not fallback 100
            local LootMaster = SimpleEPGP:GetModule("LootMaster")
            for _, session in pairs(LootMaster.sessions) do
                if not session.awarded then
                    -- ilvl 120 HEAD with default config should produce a real GP value
                    local GPCalc = SimpleEPGP:GetModule("GPCalc")
                    local expectedGP = GPCalc:CalculateGP(session.itemLink)
                    assert.equals(expectedGP, session.gpCost)
                    break
                end
            end
        end)

        it("requests uncached item from server", function()
            -- Temporarily make GetItemInfo return nil for a known ID
            local origGetItemInfo = _G.GetItemInfo
            local uncachedID = 99990
            _G.GetItemInfo = function(idOrLink)
                local id = idOrLink
                if type(id) == "string" then
                    id = tonumber(id:match("item:(%d+)")) or tonumber(id)
                end
                if id == uncachedID then return nil end
                return origGetItemInfo(idOrLink)
            end

            -- Capture C_Timer.After calls instead of executing immediately
            local capturedTimerFunc = nil
            local origTimerAfter = _G.C_Timer.After
            _G.C_Timer.After = function(seconds, func)
                capturedTimerFunc = func
            end

            -- Track C_Item.RequestLoadItemDataByID calls
            local requestedID = nil
            local origRequest = _G.C_Item.RequestLoadItemDataByID
            _G.C_Item.RequestLoadItemDataByID = function(id)
                requestedID = id
            end

            _G.SimpleEPGPDebugLog = {}
            Debug:CmdLoot({ "debug", "loot", tostring(uncachedID) })

            -- Should have set pending state
            assert.equals(uncachedID, Debug._pendingItemID)

            -- Should have requested the item
            assert.equals(uncachedID, requestedID)

            -- No session should exist yet
            local LootMaster = SimpleEPGP:GetModule("LootMaster")
            local sessionCount = 0
            for _ in pairs(LootMaster.sessions) do
                sessionCount = sessionCount + 1
            end
            assert.equals(0, sessionCount)

            -- Cleanup
            Debug._pendingItemID = nil
            Debug:UnregisterEvent("GET_ITEM_INFO_RECEIVED")
            _G.GetItemInfo = origGetItemInfo
            _G.C_Timer.After = origTimerAfter
            _G.C_Item.RequestLoadItemDataByID = origRequest
        end)

        it("starts session when GET_ITEM_INFO_RECEIVED fires", function()
            -- Use item 28789 (Eye of Gruul) but make it "uncached" initially
            local targetID = 28789
            local uncached = true
            local origGetItemInfo = _G.GetItemInfo
            _G.GetItemInfo = function(idOrLink)
                local id = idOrLink
                if type(id) == "string" then
                    id = tonumber(id:match("item:(%d+)")) or tonumber(id)
                end
                if id == targetID and uncached then return nil end
                return origGetItemInfo(idOrLink)
            end

            -- Defer C_Timer.After
            local capturedTimerFunc = nil
            local origTimerAfter = _G.C_Timer.After
            _G.C_Timer.After = function(seconds, func)
                capturedTimerFunc = func
            end

            _G.SimpleEPGPDebugLog = {}
            Debug:CmdLoot({ "debug", "loot", tostring(targetID) })

            -- Now "cache" the item and fire the event
            uncached = false
            _G._testFireEvent("GET_ITEM_INFO_RECEIVED", targetID, true)

            -- Session should now exist with real link
            local LootMaster = SimpleEPGP:GetModule("LootMaster")
            local hasSession = false
            for _, session in pairs(LootMaster.sessions) do
                if not session.awarded then
                    hasSession = true
                    assert.truthy(session.itemLink:find("Eye of Gruul"))
                    break
                end
            end
            assert.is_true(hasSession)

            -- Pending state should be cleared
            assert.is_nil(Debug._pendingItemID)

            -- Cleanup
            _G.GetItemInfo = origGetItemInfo
            _G.C_Timer.After = origTimerAfter
        end)

        it("times out after 5s if item does not exist", function()
            local fakeID = 99991
            local origGetItemInfo = _G.GetItemInfo
            _G.GetItemInfo = function(idOrLink)
                local id = idOrLink
                if type(id) == "string" then
                    id = tonumber(id:match("item:(%d+)")) or tonumber(id)
                end
                if id == fakeID then return nil end
                return origGetItemInfo(idOrLink)
            end

            -- Capture the timer callback
            local capturedTimerFunc = nil
            local origTimerAfter = _G.C_Timer.After
            _G.C_Timer.After = function(seconds, func)
                assert.equals(5, seconds)
                capturedTimerFunc = func
            end

            _G.SimpleEPGPDebugLog = {}
            Debug:CmdLoot({ "debug", "loot", tostring(fakeID) })

            assert.equals(fakeID, Debug._pendingItemID)
            assert.is_not_nil(capturedTimerFunc)

            -- Fire the timeout
            capturedTimerFunc()

            -- Pending state should be cleared
            assert.is_nil(Debug._pendingItemID)

            -- Check timeout was logged
            local found = false
            for _, entry in ipairs(_G.SimpleEPGPDebugLog) do
                if entry[2] == "WARN" and entry[3] == "Item request timed out" then
                    found = true
                    assert.equals(fakeID, entry[4].itemID)
                    break
                end
            end
            assert.is_true(found)

            -- Cleanup
            _G.GetItemInfo = origGetItemInfo
            _G.C_Timer.After = origTimerAfter
        end)

        it("ignores GET_ITEM_INFO_RECEIVED for different itemID", function()
            local targetID = 28789
            local origGetItemInfo = _G.GetItemInfo
            _G.GetItemInfo = function(idOrLink)
                local id = idOrLink
                if type(id) == "string" then
                    id = tonumber(id:match("item:(%d+)")) or tonumber(id)
                end
                if id == targetID then return nil end
                return origGetItemInfo(idOrLink)
            end

            -- Defer timeout
            local origTimerAfter = _G.C_Timer.After
            _G.C_Timer.After = function() end

            Debug:CmdLoot({ "debug", "loot", tostring(targetID) })
            assert.equals(targetID, Debug._pendingItemID)

            -- Fire event with DIFFERENT item ID
            _G._testFireEvent("GET_ITEM_INFO_RECEIVED", 99999, true)

            -- Should still be pending (event was for a different item)
            assert.equals(targetID, Debug._pendingItemID)

            -- Cleanup
            Debug._pendingItemID = nil
            Debug:UnregisterEvent("GET_ITEM_INFO_RECEIVED")
            _G.GetItemInfo = origGetItemInfo
            _G.C_Timer.After = origTimerAfter
        end)

        it("handles failed item load (success=false)", function()
            local targetID = 28789
            local origGetItemInfo = _G.GetItemInfo
            _G.GetItemInfo = function(idOrLink)
                local id = idOrLink
                if type(id) == "string" then
                    id = tonumber(id:match("item:(%d+)")) or tonumber(id)
                end
                if id == targetID then return nil end
                return origGetItemInfo(idOrLink)
            end

            -- Defer timeout
            local origTimerAfter = _G.C_Timer.After
            _G.C_Timer.After = function() end

            _G.SimpleEPGPDebugLog = {}
            Debug:CmdLoot({ "debug", "loot", tostring(targetID) })

            -- Fire event with success=false
            _G._testFireEvent("GET_ITEM_INFO_RECEIVED", targetID, false)

            -- Pending state should be cleared
            assert.is_nil(Debug._pendingItemID)

            -- No session should be created
            local LootMaster = SimpleEPGP:GetModule("LootMaster")
            local sessionCount = 0
            for _ in pairs(LootMaster.sessions) do
                sessionCount = sessionCount + 1
            end
            assert.equals(0, sessionCount)

            -- Check failure was logged
            local found = false
            for _, entry in ipairs(_G.SimpleEPGPDebugLog) do
                if entry[2] == "WARN" and entry[3] == "Item request failed" then
                    found = true
                    break
                end
            end
            assert.is_true(found)

            -- Cleanup
            _G.GetItemInfo = origGetItemInfo
            _G.C_Timer.After = origTimerAfter
        end)

        it("timeout is no-op after successful item load", function()
            local targetID = 28789
            local uncached = true
            local origGetItemInfo = _G.GetItemInfo
            _G.GetItemInfo = function(idOrLink)
                local id = idOrLink
                if type(id) == "string" then
                    id = tonumber(id:match("item:(%d+)")) or tonumber(id)
                end
                if id == targetID and uncached then return nil end
                return origGetItemInfo(idOrLink)
            end

            -- Capture the timer callback
            local capturedTimerFunc = nil
            local origTimerAfter = _G.C_Timer.After
            _G.C_Timer.After = function(seconds, func)
                capturedTimerFunc = func
            end

            Debug:CmdLoot({ "debug", "loot", tostring(targetID) })

            -- Simulate item loading successfully
            uncached = false
            _G._testFireEvent("GET_ITEM_INFO_RECEIVED", targetID, true)

            -- Now fire the timeout — should be a no-op since _pendingItemID was cleared
            assert.is_nil(Debug._pendingItemID)
            capturedTimerFunc()  -- Should not error or change state
            assert.is_nil(Debug._pendingItemID)

            -- Cleanup
            _G.GetItemInfo = origGetItemInfo
            _G.C_Timer.After = origTimerAfter
        end)
    end)

    describe("debug bid", function()
        it("injects a bid into an active session", function()
            -- Start a loot session first
            Debug:CmdLoot({ "debug", "loot", "29759" })

            -- Find the session
            local LootMaster = SimpleEPGP:GetModule("LootMaster")
            local sessionId = nil
            for id, session in pairs(LootMaster.sessions) do
                if not session.awarded then
                    sessionId = id
                    break
                end
            end
            assert.is_not_nil(sessionId)

            -- Inject a bid
            Debug:CmdBid({ "debug", "bid", "MS", "TestBidder" })

            -- Verify the bid was added
            local session = LootMaster.sessions[sessionId]
            assert.equals("MS", session.bids["TestBidder"])
        end)

        it("rejects invalid bid types", function()
            Debug:CmdBid({ "debug", "bid", "INVALID" })
            -- Should print usage
        end)

        it("handles no active session", function()
            -- Clear all sessions
            local LootMaster = SimpleEPGP:GetModule("LootMaster")
            LootMaster.sessions = {}
            Debug:CmdBid({ "debug", "bid", "MS" })
            -- Should print "No active loot session"
        end)
    end)

    describe("HandleCommand routing", function()
        it("routes log subcommand", function()
            Debug:HandleCommand({ "debug", "log" })
        end)

        it("routes clear subcommand", function()
            Debug:HandleCommand({ "debug", "clear" })
        end)

        it("routes help for unknown subcommand", function()
            Debug:HandleCommand({ "debug", "unknown" })
        end)

        it("routes help with no subcommand", function()
            Debug:HandleCommand({ "debug" })
        end)

        it("routes status subcommand", function()
            Debug:HandleCommand({ "debug", "status" })
        end)
    end)

    describe("instrumentation", function()
        it("logs GUILD_ROSTER_UPDATE events", function()
            _G.SimpleEPGPDebugLog = {}
            EPGP:GUILD_ROSTER_UPDATE()

            local found = false
            for _, entry in ipairs(_G.SimpleEPGPDebugLog) do
                if entry[2] == "EVENT" and entry[3] == "GUILD_ROSTER_UPDATE" then
                    found = true
                    assert.is_number(entry[4].members)
                    break
                end
            end
            assert.is_true(found)
        end)

        it("logs ModifyEP calls", function()
            _G.SimpleEPGPDebugLog = {}
            EPGP:ModifyEP("Player1", 100, "test")

            local found = false
            for _, entry in ipairs(_G.SimpleEPGPDebugLog) do
                if entry[2] == "EPGP" and entry[3] == "ModifyEP" then
                    found = true
                    assert.equals("Player1", entry[4].player)
                    assert.equals(100, entry[4].amount)
                    break
                end
            end
            assert.is_true(found)
        end)

        it("logs ModifyGP calls", function()
            _G.SimpleEPGPDebugLog = {}
            EPGP:ModifyGP("Player2", 50, "test gp")

            local found = false
            for _, entry in ipairs(_G.SimpleEPGPDebugLog) do
                if entry[2] == "EPGP" and entry[3] == "ModifyGP" then
                    found = true
                    assert.equals("Player2", entry[4].player)
                    break
                end
            end
            assert.is_true(found)
        end)
    end)
end)
