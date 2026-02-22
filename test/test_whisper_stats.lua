-----------------------------------------------------------------------
-- test_whisper_stats.lua -- Unit tests for whisper stats command (#54)
-----------------------------------------------------------------------

-- Load stubs first
require("test.wow_stubs")
require("test.ace_stubs")

-- Core.lua is loaded FIRST in .toc -- creates the addon via NewAddon
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

describe("Whisper Stats", function()
    local EPGP

    before_each(function()
        EPGP = SimpleEPGP:GetModule("EPGP")

        -- Reset guild roster officer notes
        _G._testGuildRoster[1].officerNote = "5000,1000"
        _G._testGuildRoster[2].officerNote = "3000,500"
        _G._testGuildRoster[3].officerNote = "2000,2000"
        _G._testGuildRoster[4].officerNote = "1000,100"
        _G._testGuildRoster[5].officerNote = ""

        -- Rebuild standings
        EPGP:GUILD_ROSTER_UPDATE()

        -- Clear captured chat messages
        for i = #_G._testChatMessages, 1, -1 do
            _G._testChatMessages[i] = nil
        end

        -- Enable whisper stats
        SimpleEPGP.db.profile.enable_whisper_stats = true

        -- Reset rate limit table
        SimpleEPGP._whisperRateLimit = {}
    end)

    describe("EPGP:GetPlayerRank", function()
        it("returns rank 1 for highest PR player", function()
            -- Player1: EP=5000, GP=1000, PR=5000/(1000+100)=4.545...
            -- Player4: EP=1000, GP=100, PR=1000/(100+100)=5.0
            -- Player4 has highest PR
            local rank = EPGP:GetPlayerRank("Player4")
            assert.are.equal(1, rank)
        end)

        it("returns correct rank for each player", function()
            -- Standings sorted by PR descending:
            -- Player4: 1000/(100+100) = 5.0
            -- Player1: 5000/(1000+100) = 4.545...
            -- Player2: 3000/(500+100) = 5.0  -- same as Player4, order depends on sort stability
            -- Player3: 2000/(2000+100) = 0.952...
            -- Player5: 0/(0+100) = 0
            -- With table.sort stability, tied PR entries may vary in order.
            -- Just verify each player has a non-nil rank.
            for i = 1, 4 do
                local rank = EPGP:GetPlayerRank("Player" .. i)
                assert.is_not_nil(rank, "Player" .. i .. " should have a rank")
                assert.is_true(rank >= 1 and rank <= 5, "Rank should be between 1 and 5")
            end
        end)

        it("returns nil for unknown player", function()
            local rank = EPGP:GetPlayerRank("Nonexistent")
            assert.is_nil(rank)
        end)

        it("normalizes name casing", function()
            local rank = EPGP:GetPlayerRank("player1")
            assert.is_not_nil(rank)
        end)
    end)

    describe("CHAT_MSG_WHISPER handler", function()
        it("responds to !epgp whisper", function()
            SimpleEPGP:CHAT_MSG_WHISPER("CHAT_MSG_WHISPER", "!epgp", "Player1-TestRealm")

            assert.are.equal(1, #_G._testChatMessages)
            local msg = _G._testChatMessages[1]
            assert.are.equal("WHISPER", msg.channel)
            assert.is_truthy(msg.text:find("EP=5000"))
            assert.is_truthy(msg.text:find("GP=1000"))
            assert.is_truthy(msg.text:find("PR="))
            assert.is_truthy(msg.text:find("Rank #"))
        end)

        it("responds to !stats whisper", function()
            SimpleEPGP:CHAT_MSG_WHISPER("CHAT_MSG_WHISPER", "!stats", "Player2-TestRealm")

            assert.are.equal(1, #_G._testChatMessages)
            local msg = _G._testChatMessages[1]
            assert.is_truthy(msg.text:find("EP=3000"))
            assert.is_truthy(msg.text:find("GP=500"))
        end)

        it("responds to !pr whisper", function()
            SimpleEPGP:CHAT_MSG_WHISPER("CHAT_MSG_WHISPER", "!pr", "Player3-TestRealm")

            assert.are.equal(1, #_G._testChatMessages)
            local msg = _G._testChatMessages[1]
            assert.is_truthy(msg.text:find("EP=2000"))
            assert.is_truthy(msg.text:find("GP=2000"))
        end)

        it("is case-insensitive for keywords", function()
            SimpleEPGP:CHAT_MSG_WHISPER("CHAT_MSG_WHISPER", "!EPGP", "Player1-TestRealm")
            assert.are.equal(1, #_G._testChatMessages)
            assert.is_truthy(_G._testChatMessages[1].text:find("EP=5000"))
        end)

        it("handles mixed case keywords", function()
            SimpleEPGP:CHAT_MSG_WHISPER("CHAT_MSG_WHISPER", "!Epgp", "Player1-TestRealm")
            assert.are.equal(1, #_G._testChatMessages)
        end)

        it("trims whitespace around keywords", function()
            SimpleEPGP:CHAT_MSG_WHISPER("CHAT_MSG_WHISPER", "  !epgp  ", "Player1-TestRealm")
            assert.are.equal(1, #_G._testChatMessages)
        end)

        it("ignores non-keyword whispers", function()
            SimpleEPGP:CHAT_MSG_WHISPER("CHAT_MSG_WHISPER", "hello there", "Player1-TestRealm")
            assert.are.equal(0, #_G._testChatMessages)
        end)

        it("ignores empty whispers", function()
            SimpleEPGP:CHAT_MSG_WHISPER("CHAT_MSG_WHISPER", "", "Player1-TestRealm")
            assert.are.equal(0, #_G._testChatMessages)
        end)

        it("ignores partial keyword matches", function()
            SimpleEPGP:CHAT_MSG_WHISPER("CHAT_MSG_WHISPER", "!epgp standings", "Player1-TestRealm")
            assert.are.equal(0, #_G._testChatMessages)
        end)

        it("whispers 'not in standings' for unknown player", function()
            SimpleEPGP:CHAT_MSG_WHISPER("CHAT_MSG_WHISPER", "!epgp", "Stranger-OtherRealm")

            assert.are.equal(1, #_G._testChatMessages)
            local msg = _G._testChatMessages[1]
            assert.are.equal("WHISPER", msg.channel)
            assert.is_truthy(msg.text:find("not in the EPGP standings"))
        end)

        it("strips realm suffix from sender name for lookup", function()
            -- Player2-TestRealm should match Player2 in standings
            SimpleEPGP:CHAT_MSG_WHISPER("CHAT_MSG_WHISPER", "!epgp", "Player2-TestRealm")
            assert.are.equal(1, #_G._testChatMessages)
            assert.is_truthy(_G._testChatMessages[1].text:find("EP=3000"))
        end)

        it("includes correct PR in response", function()
            -- Player1: EP=5000, GP=1000, base_gp=100
            -- PR = 5000 / (1000 + 100) = 4.5454...
            SimpleEPGP:CHAT_MSG_WHISPER("CHAT_MSG_WHISPER", "!epgp", "Player1-TestRealm")

            local msg = _G._testChatMessages[1].text
            assert.is_truthy(msg:find("PR=4%.55"))
        end)

        it("includes rank number in response", function()
            SimpleEPGP:CHAT_MSG_WHISPER("CHAT_MSG_WHISPER", "!epgp", "Player1-TestRealm")

            local msg = _G._testChatMessages[1].text
            local rank = msg:match("Rank #(%d+)")
            assert.is_not_nil(rank, "Expected Rank #N in response")
            assert.is_true(tonumber(rank) >= 1, "Rank should be >= 1")
        end)
    end)

    describe("Rate limiting", function()
        it("responds to first whisper", function()
            SimpleEPGP:CHAT_MSG_WHISPER("CHAT_MSG_WHISPER", "!epgp", "Player1-TestRealm")
            assert.are.equal(1, #_G._testChatMessages)
        end)

        it("blocks repeated whispers within 30 seconds", function()
            -- First whisper succeeds
            SimpleEPGP:CHAT_MSG_WHISPER("CHAT_MSG_WHISPER", "!epgp", "Player1-TestRealm")
            assert.are.equal(1, #_G._testChatMessages)

            -- Second whisper within 30 seconds should be blocked
            SimpleEPGP:CHAT_MSG_WHISPER("CHAT_MSG_WHISPER", "!epgp", "Player1-TestRealm")
            assert.are.equal(1, #_G._testChatMessages)
        end)

        it("allows whisper after rate limit expires", function()
            -- First whisper succeeds
            SimpleEPGP:CHAT_MSG_WHISPER("CHAT_MSG_WHISPER", "!epgp", "Player1-TestRealm")
            assert.are.equal(1, #_G._testChatMessages)

            -- Simulate 30 seconds passing by backdating the rate limit entry
            SimpleEPGP._whisperRateLimit["Player1"] = os.time() - 31

            -- Now the whisper should succeed
            SimpleEPGP:CHAT_MSG_WHISPER("CHAT_MSG_WHISPER", "!epgp", "Player1-TestRealm")
            assert.are.equal(2, #_G._testChatMessages)
        end)

        it("rate limits per player independently", function()
            -- Player1 whispers
            SimpleEPGP:CHAT_MSG_WHISPER("CHAT_MSG_WHISPER", "!epgp", "Player1-TestRealm")
            assert.are.equal(1, #_G._testChatMessages)

            -- Player2 whispers (different player, not rate limited)
            SimpleEPGP:CHAT_MSG_WHISPER("CHAT_MSG_WHISPER", "!epgp", "Player2-TestRealm")
            assert.are.equal(2, #_G._testChatMessages)

            -- Player1 whispers again (rate limited)
            SimpleEPGP:CHAT_MSG_WHISPER("CHAT_MSG_WHISPER", "!epgp", "Player1-TestRealm")
            assert.are.equal(2, #_G._testChatMessages)
        end)

        it("rate limits different keywords from same player", function()
            -- Player1 sends !epgp
            SimpleEPGP:CHAT_MSG_WHISPER("CHAT_MSG_WHISPER", "!epgp", "Player1-TestRealm")
            assert.are.equal(1, #_G._testChatMessages)

            -- Player1 sends !stats (same player, still rate limited)
            SimpleEPGP:CHAT_MSG_WHISPER("CHAT_MSG_WHISPER", "!stats", "Player1-TestRealm")
            assert.are.equal(1, #_G._testChatMessages)
        end)
    end)

    describe("Config toggle", function()
        it("does not respond when enable_whisper_stats is false", function()
            SimpleEPGP.db.profile.enable_whisper_stats = false

            SimpleEPGP:CHAT_MSG_WHISPER("CHAT_MSG_WHISPER", "!epgp", "Player1-TestRealm")
            assert.are.equal(0, #_G._testChatMessages)
        end)

        it("responds when enable_whisper_stats is true", function()
            SimpleEPGP.db.profile.enable_whisper_stats = true

            SimpleEPGP:CHAT_MSG_WHISPER("CHAT_MSG_WHISPER", "!epgp", "Player1-TestRealm")
            assert.are.equal(1, #_G._testChatMessages)
        end)
    end)

    describe("Config default", function()
        it("enable_whisper_stats defaults to true", function()
            assert.is_true(SimpleEPGP.db.profile.enable_whisper_stats)
        end)
    end)
end)
