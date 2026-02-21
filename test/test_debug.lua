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
        it("starts a loot session", function()
            _G.SimpleEPGPDebugLog = {}
            Debug:CmdLoot({ "debug", "loot", "29759" })

            -- Check the loot session was created
            local LootMaster = SimpleEPGP:GetModule("LootMaster")
            local hasSession = false
            for _, session in pairs(LootMaster.sessions) do
                if not session.awarded then
                    hasSession = true
                    break
                end
            end
            assert.is_true(hasSession)
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
