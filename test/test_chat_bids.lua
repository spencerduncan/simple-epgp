-----------------------------------------------------------------------
-- test_chat_bids.lua -- Unit tests for chat-based bidding (#53)
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
        enable_chat_bids = true,
        announce_channel = "GUILD",
        announce_awards = true,
        announce_ep = true,
        announce_loot_rw = true,
        announce_awards_raid = true,
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

describe("Chat-based bidding", function()
    local LootMaster, EPGP

    before_each(function()
        -- Reset guild roster officer notes
        _G._testGuildRoster[1].officerNote = "5000,1000"
        _G._testGuildRoster[2].officerNote = "3000,500"
        _G._testGuildRoster[3].officerNote = "2000,2000"
        _G._testGuildRoster[4].officerNote = "1000,100"
        _G._testGuildRoster[5].officerNote = ""

        LootMaster = SimpleEPGP:GetModule("LootMaster")
        EPGP = SimpleEPGP:GetModule("EPGP")

        -- Rebuild standings so PR values are current
        EPGP:GUILD_ROSTER_UPDATE()

        -- Reset sessions
        LootMaster.sessions = {}
        LootMaster.nextSessionId = 1

        -- Clear sent messages (addon comms)
        for i = #_G._testSentMessages, 1, -1 do
            _G._testSentMessages[i] = nil
        end

        -- Clear chat messages (SendChatMessage captures)
        for i = #_G._testChatMessages, 1, -1 do
            _G._testChatMessages[i] = nil
        end

        -- Ensure chat bids enabled by default
        SimpleEPGP.db.profile.enable_chat_bids = true

        -- Ensure IsInRaid returns true by default
        _G.IsInRaid = function() return true end
    end)

    --------------------------------------------------------------------------
    -- ParseChatBid
    --------------------------------------------------------------------------

    describe("ParseChatBid", function()
        it("parses 'ms' as MS", function()
            assert.are.equal("MS", LootMaster:ParseChatBid("ms"))
        end)

        it("parses 'MS' (uppercase) as MS", function()
            assert.are.equal("MS", LootMaster:ParseChatBid("MS"))
        end)

        it("parses 'mainspec' as MS", function()
            assert.are.equal("MS", LootMaster:ParseChatBid("mainspec"))
        end)

        it("parses 'MainSpec' (mixed case) as MS", function()
            assert.are.equal("MS", LootMaster:ParseChatBid("MainSpec"))
        end)

        it("parses 'os' as OS", function()
            assert.are.equal("OS", LootMaster:ParseChatBid("os"))
        end)

        it("parses 'offspec' as OS", function()
            assert.are.equal("OS", LootMaster:ParseChatBid("offspec"))
        end)

        it("parses 'OFFSPEC' (uppercase) as OS", function()
            assert.are.equal("OS", LootMaster:ParseChatBid("OFFSPEC"))
        end)

        it("parses 'de' as DE", function()
            assert.are.equal("DE", LootMaster:ParseChatBid("de"))
        end)

        it("parses 'disenchant' as DE", function()
            assert.are.equal("DE", LootMaster:ParseChatBid("disenchant"))
        end)

        it("parses 'DISENCHANT' (uppercase) as DE", function()
            assert.are.equal("DE", LootMaster:ParseChatBid("DISENCHANT"))
        end)

        it("parses 'pass' as PASS", function()
            assert.are.equal("PASS", LootMaster:ParseChatBid("pass"))
        end)

        it("parses 'Pass' (mixed case) as PASS", function()
            assert.are.equal("PASS", LootMaster:ParseChatBid("Pass"))
        end)

        it("strips leading/trailing whitespace", function()
            assert.are.equal("MS", LootMaster:ParseChatBid("  ms  "))
        end)

        it("returns nil for unrecognized text", function()
            assert.is_nil(LootMaster:ParseChatBid("hello"))
        end)

        it("returns nil for partial matches", function()
            assert.is_nil(LootMaster:ParseChatBid("ms bid"))
        end)

        it("returns nil for empty string", function()
            assert.is_nil(LootMaster:ParseChatBid(""))
        end)

        it("returns nil for nil input", function()
            assert.is_nil(LootMaster:ParseChatBid(nil))
        end)

        it("returns nil for whitespace-only input", function()
            assert.is_nil(LootMaster:ParseChatBid("   "))
        end)
    end)

    --------------------------------------------------------------------------
    -- IsRaidMember
    --------------------------------------------------------------------------

    describe("IsRaidMember", function()
        it("returns true for raid members", function()
            assert.is_true(LootMaster:IsRaidMember("Player1"))
            assert.is_true(LootMaster:IsRaidMember("Player2"))
            assert.is_true(LootMaster:IsRaidMember("Player5"))
        end)

        it("returns false for non-raid members", function()
            assert.is_false(LootMaster:IsRaidMember("RandomPerson"))
        end)

        it("returns false for nil", function()
            assert.is_false(LootMaster:IsRaidMember(nil))
        end)

        it("strips realm from raid roster names when comparing", function()
            -- Raid roster has "Player1-TestRealm"; should match "Player1"
            assert.is_true(LootMaster:IsRaidMember("Player1"))
        end)
    end)

    --------------------------------------------------------------------------
    -- GetMostRecentSession
    --------------------------------------------------------------------------

    describe("GetMostRecentSession", function()
        it("returns nil when no sessions exist", function()
            assert.is_nil(LootMaster:GetMostRecentSession())
        end)

        it("returns the only active session", function()
            local link = _G._testItemDB[29759][2]
            local sessionId = LootMaster:StartSession(link, 1000)
            assert.are.equal(sessionId, LootMaster:GetMostRecentSession())
        end)

        it("returns the highest session ID among active sessions", function()
            local link = _G._testItemDB[29759][2]
            local id1 = LootMaster:StartSession(link, 1000)
            local id2 = LootMaster:StartSession(link, 1000)
            assert.are.equal(id2, LootMaster:GetMostRecentSession())
            -- id1 should not be the result
            assert.are_not.equal(id1, LootMaster:GetMostRecentSession())
        end)

        it("skips awarded sessions", function()
            local link = _G._testItemDB[29759][2]
            local id1 = LootMaster:StartSession(link, 1000)
            local id2 = LootMaster:StartSession(link, 1000)
            -- Award session 2
            LootMaster.sessions[id2].awarded = true
            assert.are.equal(id1, LootMaster:GetMostRecentSession())
        end)

        it("returns nil when all sessions are awarded", function()
            local link = _G._testItemDB[29759][2]
            local id1 = LootMaster:StartSession(link, 1000)
            LootMaster.sessions[id1].awarded = true
            assert.is_nil(LootMaster:GetMostRecentSession())
        end)
    end)

    --------------------------------------------------------------------------
    -- HandleChatBid (core integration)
    --------------------------------------------------------------------------

    describe("HandleChatBid", function()
        it("processes a valid whisper bid and injects into session", function()
            local link = _G._testItemDB[29759][2]
            local sessionId = LootMaster:StartSession(link, 1000)

            -- Clear chat messages from StartSession
            for i = #_G._testChatMessages, 1, -1 do
                _G._testChatMessages[i] = nil
            end

            LootMaster:HandleChatBid("Player2-TestRealm", "ms")

            -- Bid should be recorded
            assert.are.equal("MS", LootMaster.sessions[sessionId].bids["Player2"])
        end)

        it("whispers confirmation back to bidder", function()
            local link = _G._testItemDB[29759][2]
            LootMaster:StartSession(link, 1000)

            -- Clear chat messages from StartSession
            for i = #_G._testChatMessages, 1, -1 do
                _G._testChatMessages[i] = nil
            end

            LootMaster:HandleChatBid("Player2-TestRealm", "ms")

            -- Find whisper confirmation
            local found = false
            for _, msg in ipairs(_G._testChatMessages) do
                if msg.channel == "WHISPER" and msg.target == "Player2-TestRealm" then
                    found = true
                    assert.is_truthy(msg.text:find("Bid received: MS"))
                    assert.is_truthy(msg.text:find("Helm of the Fallen Champion"))
                    break
                end
            end
            assert.is_true(found, "Expected whisper confirmation to bidder")
        end)

        it("processes OS bids correctly", function()
            local link = _G._testItemDB[29759][2]
            local sessionId = LootMaster:StartSession(link, 1000)

            LootMaster:HandleChatBid("Player3-TestRealm", "offspec")

            assert.are.equal("OS", LootMaster.sessions[sessionId].bids["Player3"])
        end)

        it("processes DE bids correctly", function()
            local link = _G._testItemDB[29759][2]
            local sessionId = LootMaster:StartSession(link, 1000)

            LootMaster:HandleChatBid("Player1-TestRealm", "disenchant")

            assert.are.equal("DE", LootMaster.sessions[sessionId].bids["Player1"])
        end)

        it("processes PASS bids correctly", function()
            local link = _G._testItemDB[29759][2]
            local sessionId = LootMaster:StartSession(link, 1000)

            LootMaster:HandleChatBid("Player4-TestRealm", "pass")

            assert.are.equal("PASS", LootMaster.sessions[sessionId].bids["Player4"])
        end)

        it("ignores bids when enable_chat_bids is false", function()
            SimpleEPGP.db.profile.enable_chat_bids = false
            local link = _G._testItemDB[29759][2]
            local sessionId = LootMaster:StartSession(link, 1000)

            LootMaster:HandleChatBid("Player2-TestRealm", "ms")

            assert.is_nil(LootMaster.sessions[sessionId].bids["Player2"])
        end)

        it("ignores bids from non-raid members", function()
            local link = _G._testItemDB[29759][2]
            local sessionId = LootMaster:StartSession(link, 1000)

            LootMaster:HandleChatBid("RandomPerson-SomeRealm", "ms")

            assert.is_nil(LootMaster.sessions[sessionId].bids["RandomPerson"])
        end)

        it("ignores non-bid chat messages", function()
            local link = _G._testItemDB[29759][2]
            local sessionId = LootMaster:StartSession(link, 1000)

            LootMaster:HandleChatBid("Player2-TestRealm", "hello everyone")

            assert.is_nil(LootMaster.sessions[sessionId].bids["Player2"])
        end)

        it("ignores bids when no active session exists", function()
            -- No session started — should not error
            LootMaster:HandleChatBid("Player2-TestRealm", "ms")
            -- No assertion needed; no error = pass
        end)

        it("matches bid to most recent session when multiple are active", function()
            local link1 = _G._testItemDB[29759][2]
            local link2 = _G._testItemDB[28789][2]
            local id1 = LootMaster:StartSession(link1, 1000)
            local id2 = LootMaster:StartSession(link2, 500)

            LootMaster:HandleChatBid("Player2-TestRealm", "ms")

            -- Bid should go to the more recent session (id2)
            assert.is_nil(LootMaster.sessions[id1].bids["Player2"])
            assert.are.equal("MS", LootMaster.sessions[id2].bids["Player2"])
        end)

        it("allows bid change via chat (overwrite existing bid)", function()
            local link = _G._testItemDB[29759][2]
            local sessionId = LootMaster:StartSession(link, 1000)

            LootMaster:HandleChatBid("Player2-TestRealm", "ms")
            assert.are.equal("MS", LootMaster.sessions[sessionId].bids["Player2"])

            LootMaster:HandleChatBid("Player2-TestRealm", "os")
            assert.are.equal("OS", LootMaster.sessions[sessionId].bids["Player2"])
        end)

        it("handles case-insensitive keywords", function()
            local link = _G._testItemDB[29759][2]
            local sessionId = LootMaster:StartSession(link, 1000)

            LootMaster:HandleChatBid("Player2-TestRealm", "MAINSPEC")

            assert.are.equal("MS", LootMaster.sessions[sessionId].bids["Player2"])
        end)

        it("sends whisper with correct bid type for Pass", function()
            local link = _G._testItemDB[29759][2]
            LootMaster:StartSession(link, 1000)

            -- Clear chat messages
            for i = #_G._testChatMessages, 1, -1 do
                _G._testChatMessages[i] = nil
            end

            LootMaster:HandleChatBid("Player3-TestRealm", "pass")

            local found = false
            for _, msg in ipairs(_G._testChatMessages) do
                if msg.channel == "WHISPER" and msg.target == "Player3-TestRealm" then
                    found = true
                    assert.is_truthy(msg.text:find("Bid received: Pass"))
                    break
                end
            end
            assert.is_true(found, "Expected whisper confirmation for Pass bid")
        end)

        it("does not whisper when bid is ignored (non-raid member)", function()
            local link = _G._testItemDB[29759][2]
            LootMaster:StartSession(link, 1000)

            -- Clear chat messages
            for i = #_G._testChatMessages, 1, -1 do
                _G._testChatMessages[i] = nil
            end

            LootMaster:HandleChatBid("RandomPerson-SomeRealm", "ms")

            -- Should not have any whisper messages
            for _, msg in ipairs(_G._testChatMessages) do
                if msg.channel == "WHISPER" then
                    assert.fail("Should not whisper to non-raid members")
                end
            end
        end)
    end)

    --------------------------------------------------------------------------
    -- Event handler integration
    --------------------------------------------------------------------------

    describe("CHAT_MSG_WHISPER handler", function()
        it("processes whispered bids", function()
            local link = _G._testItemDB[29759][2]
            local sessionId = LootMaster:StartSession(link, 1000)

            -- Simulate CHAT_MSG_WHISPER event
            LootMaster:CHAT_MSG_WHISPER("CHAT_MSG_WHISPER", "ms", "Player2-TestRealm")

            assert.are.equal("MS", LootMaster.sessions[sessionId].bids["Player2"])
        end)
    end)

    describe("CHAT_MSG_RAID handler", function()
        it("processes raid chat bids", function()
            local link = _G._testItemDB[29759][2]
            local sessionId = LootMaster:StartSession(link, 1000)

            -- Simulate CHAT_MSG_RAID event
            LootMaster:CHAT_MSG_RAID("CHAT_MSG_RAID", "os", "Player3-TestRealm")

            assert.are.equal("OS", LootMaster.sessions[sessionId].bids["Player3"])
        end)
    end)

    --------------------------------------------------------------------------
    -- Config toggle
    --------------------------------------------------------------------------

    describe("enable_chat_bids config", function()
        it("defaults to true", function()
            assert.is_true(SimpleEPGP.db.profile.enable_chat_bids)
        end)

        it("disables chat bid processing when false", function()
            SimpleEPGP.db.profile.enable_chat_bids = false
            local link = _G._testItemDB[29759][2]
            local sessionId = LootMaster:StartSession(link, 1000)

            LootMaster:CHAT_MSG_WHISPER("CHAT_MSG_WHISPER", "ms", "Player2-TestRealm")

            assert.is_nil(LootMaster.sessions[sessionId].bids["Player2"])
        end)

        it("re-enables when toggled back to true", function()
            SimpleEPGP.db.profile.enable_chat_bids = false
            local link = _G._testItemDB[29759][2]
            local sessionId = LootMaster:StartSession(link, 1000)

            LootMaster:CHAT_MSG_WHISPER("CHAT_MSG_WHISPER", "ms", "Player2-TestRealm")
            assert.is_nil(LootMaster.sessions[sessionId].bids["Player2"])

            -- Re-enable
            SimpleEPGP.db.profile.enable_chat_bids = true
            LootMaster:CHAT_MSG_WHISPER("CHAT_MSG_WHISPER", "ms", "Player2-TestRealm")
            assert.are.equal("MS", LootMaster.sessions[sessionId].bids["Player2"])
        end)
    end)

    --------------------------------------------------------------------------
    -- Whisper confirmation format
    --------------------------------------------------------------------------

    describe("whisper confirmation", function()
        it("uses the correct format: 'Bid received: <type> for <item>'", function()
            local link = _G._testItemDB[29759][2]
            LootMaster:StartSession(link, 1000)

            -- Clear chat messages
            for i = #_G._testChatMessages, 1, -1 do
                _G._testChatMessages[i] = nil
            end

            LootMaster:HandleChatBid("Player2-TestRealm", "de")

            local found = false
            for _, msg in ipairs(_G._testChatMessages) do
                if msg.channel == "WHISPER" then
                    found = true
                    assert.are.equal("Player2-TestRealm", msg.target)
                    assert.is_truthy(msg.text:find("^Bid received: DE for"))
                    break
                end
            end
            assert.is_true(found, "Expected whisper confirmation")
        end)

        it("whispers back to the original sender name (with realm)", function()
            local link = _G._testItemDB[29759][2]
            LootMaster:StartSession(link, 1000)

            -- Clear chat messages
            for i = #_G._testChatMessages, 1, -1 do
                _G._testChatMessages[i] = nil
            end

            LootMaster:HandleChatBid("Player4-TestRealm", "os")

            local whisperFound = false
            for _, msg in ipairs(_G._testChatMessages) do
                if msg.channel == "WHISPER" then
                    whisperFound = true
                    -- Target should be the full name with realm
                    assert.are.equal("Player4-TestRealm", msg.target)
                    break
                end
            end
            assert.is_true(whisperFound, "Expected whisper to Player4-TestRealm")
        end)
    end)
end)
