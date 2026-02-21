-----------------------------------------------------------------------
-- test_lootmaster.lua — Unit tests for LootMaster module
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

-- Initialize addon (triggers OnInitialize + OnEnable for addon and all modules)
_G._testInitAddon("SimpleEPGP")

describe("LootMaster", function()
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

        -- Clear sent messages
        for i = #_G._testSentMessages, 1, -1 do
            _G._testSentMessages[i] = nil
        end
    end)

    describe("StartSession", function()
        it("creates session and sends OFFER", function()
            local link = _G._testItemDB[29759][2]
            local sessionId = LootMaster:StartSession(link, 1000)
            assert.are.equal(1, sessionId)
            assert.is_not_nil(LootMaster.sessions[1])
            assert.are.equal(link, LootMaster.sessions[1].itemLink)
            assert.are.equal(1000, LootMaster.sessions[1].gpCost)
            assert.is_false(LootMaster.sessions[1].awarded)
            -- OFFER should have been sent
            assert.is_true(#_G._testSentMessages >= 1)
        end)

        it("increments session IDs", function()
            local link = _G._testItemDB[29759][2]
            local id1 = LootMaster:StartSession(link, 1000)
            local id2 = LootMaster:StartSession(link, 1000)
            assert.are.equal(1, id1)
            assert.are.equal(2, id2)
        end)
    end)

    describe("OnBidReceived", function()
        it("stores bids correctly", function()
            local link = _G._testItemDB[29759][2]
            local sessionId = LootMaster:StartSession(link, 1000)
            LootMaster:OnBidReceived("Player1", sessionId, "MS")
            LootMaster:OnBidReceived("Player2", sessionId, "OS")
            LootMaster:OnBidReceived("Player3", sessionId, "DE")
            assert.are.equal("MS", LootMaster.sessions[sessionId].bids["Player1"])
            assert.are.equal("OS", LootMaster.sessions[sessionId].bids["Player2"])
            assert.are.equal("DE", LootMaster.sessions[sessionId].bids["Player3"])
        end)

        it("ignores bids for non-existent sessions", function()
            -- Should not error
            LootMaster:OnBidReceived("Player1", 999, "MS")
        end)

        it("ignores bids for awarded sessions", function()
            local link = _G._testItemDB[29759][2]
            local sessionId = LootMaster:StartSession(link, 1000)
            LootMaster.sessions[sessionId].awarded = true
            LootMaster:OnBidReceived("Player1", sessionId, "MS")
            assert.is_nil(LootMaster.sessions[sessionId].bids["Player1"])
        end)

        it("allows bid change (re-bid overwrites)", function()
            local link = _G._testItemDB[29759][2]
            local sessionId = LootMaster:StartSession(link, 1000)
            LootMaster:OnBidReceived("Player1", sessionId, "MS")
            assert.are.equal("MS", LootMaster.sessions[sessionId].bids["Player1"])
            -- Player changes mind to OS
            LootMaster:OnBidReceived("Player1", sessionId, "OS")
            assert.are.equal("OS", LootMaster.sessions[sessionId].bids["Player1"])
            -- Verify it's in OS group now, not MS
            local bids = LootMaster:GetSessionBids(sessionId)
            assert.are.equal(0, #bids.ms)
            assert.are.equal(1, #bids.os)
            assert.are.equal("Player1", bids.os[1].name)
        end)
    end)

    describe("OnRetractReceived", function()
        it("removes bids", function()
            local link = _G._testItemDB[29759][2]
            local sessionId = LootMaster:StartSession(link, 1000)
            LootMaster:OnBidReceived("Player1", sessionId, "MS")
            assert.are.equal("MS", LootMaster.sessions[sessionId].bids["Player1"])
            LootMaster:OnRetractReceived("Player1", sessionId)
            assert.is_nil(LootMaster.sessions[sessionId].bids["Player1"])
        end)
    end)

    describe("GetSessionBids", function()
        it("groups by type and sorts by PR", function()
            local link = _G._testItemDB[29759][2]
            local sessionId = LootMaster:StartSession(link, 1000)

            -- Player1: PR=5000/1100~4.545, Player2: PR=3000/600=5.0
            LootMaster:OnBidReceived("Player1", sessionId, "MS")
            LootMaster:OnBidReceived("Player2", sessionId, "MS")
            LootMaster:OnBidReceived("Player3", sessionId, "OS")

            local bids = LootMaster:GetSessionBids(sessionId)
            assert.is_not_nil(bids)

            -- MS group should have 2 entries
            assert.are.equal(2, #bids.ms)
            -- Player2 has higher PR (5.0) than Player1 (4.545), so Player2 first
            assert.are.equal("Player2", bids.ms[1].name)
            assert.are.equal("Player1", bids.ms[2].name)

            -- OS group should have 1 entry
            assert.are.equal(1, #bids.os)
            assert.are.equal("Player3", bids.os[1].name)
        end)

        it("returns nil for non-existent session", function()
            assert.is_nil(LootMaster:GetSessionBids(999))
        end)

        it("handles empty bids", function()
            local link = _G._testItemDB[29759][2]
            local sessionId = LootMaster:StartSession(link, 1000)
            local bids = LootMaster:GetSessionBids(sessionId)
            assert.are.equal(0, #bids.ms)
            assert.are.equal(0, #bids.os)
            assert.are.equal(0, #bids.de)
            assert.are.equal(0, #bids.pass)
        end)

        it("deterministic sort within same PR via tiebreak", function()
            -- Give Player1 and Player4 identical PR
            -- Both at EP=1000, GP=100, base_gp=100 -> PR = 1000/200 = 5.0
            _G._testGuildRoster[1].officerNote = "1000,100"
            _G._testGuildRoster[4].officerNote = "1000,100"
            EPGP:GUILD_ROSTER_UPDATE()

            local link = _G._testItemDB[29759][2]
            local sessionId = LootMaster:StartSession(link, 1000)
            LootMaster:OnBidReceived("Player1", sessionId, "MS")
            LootMaster:OnBidReceived("Player4", sessionId, "MS")

            -- Should not error (tiebreak handles equal PR without infinite loop)
            local bids = LootMaster:GetSessionBids(sessionId)
            assert.are.equal(2, #bids.ms)
        end)
    end)

    describe("AwardItem", function()
        it("charges GP and sends AWARD", function()
            local link = _G._testItemDB[29759][2]
            local sessionId = LootMaster:StartSession(link, 1000)
            LootMaster:OnBidReceived("Player2", sessionId, "MS")

            -- Clear messages from StartSession
            for i = #_G._testSentMessages, 1, -1 do
                _G._testSentMessages[i] = nil
            end

            LootMaster:AwardItem(sessionId, "Player2", "MS")

            -- Session should be marked as awarded
            assert.is_true(LootMaster.sessions[sessionId].awarded)

            -- GP should have been charged to Player2
            -- Player2 was 3000,500 -> GP +1000 -> 3000,1500
            assert.are.equal("3000,1500", _G._testGuildRoster[2].officerNote)

            -- AWARD message should have been sent
            assert.is_true(#_G._testSentMessages >= 1)
        end)

        it("charges reduced GP for OS bid", function()
            local link = _G._testItemDB[29759][2]
            local sessionId = LootMaster:StartSession(link, 1000)
            LootMaster:OnBidReceived("Player2", sessionId, "OS")

            LootMaster:AwardItem(sessionId, "Player2", "OS")

            -- OS = 50% of 1000 = 500 GP charged
            -- Player2 was 3000,500 -> GP +500 -> 3000,1000
            assert.are.equal("3000,1000", _G._testGuildRoster[2].officerNote)
        end)

        it("charges 0 GP for DE bid", function()
            local link = _G._testItemDB[29759][2]
            local sessionId = LootMaster:StartSession(link, 1000)
            LootMaster:OnBidReceived("Player2", sessionId, "DE")

            LootMaster:AwardItem(sessionId, "Player2", "DE")

            -- DE = 0% -> 0 GP charged
            -- Player2 stays at 3000,500
            assert.are.equal("3000,500", _G._testGuildRoster[2].officerNote)
        end)

        it("does not double-award", function()
            local link = _G._testItemDB[29759][2]
            local sessionId = LootMaster:StartSession(link, 1000)
            LootMaster:OnBidReceived("Player2", sessionId, "MS")

            LootMaster:AwardItem(sessionId, "Player2", "MS")
            -- Try to award again (should be no-op because session.awarded = true)
            LootMaster:AwardItem(sessionId, "Player2", "MS")

            -- GP should only have been charged once
            assert.are.equal("3000,1500", _G._testGuildRoster[2].officerNote)
        end)
    end)

    describe("CancelSession", function()
        it("removes session", function()
            local link = _G._testItemDB[29759][2]
            local sessionId = LootMaster:StartSession(link, 1000)
            assert.is_not_nil(LootMaster.sessions[sessionId])
            LootMaster:CancelSession(sessionId)
            assert.is_nil(LootMaster.sessions[sessionId])
        end)
    end)

    describe("Auto-distribute", function()
        it("picks highest PR MS bidder on timer expiry", function()
            SimpleEPGP.db.profile.auto_distribute = true
            local link = _G._testItemDB[29759][2]
            local sessionId = LootMaster:StartSession(link, 1000)

            -- Player2 has higher PR (5.0) than Player1 (4.545)
            LootMaster:OnBidReceived("Player1", sessionId, "MS")
            LootMaster:OnBidReceived("Player2", sessionId, "MS")

            LootMaster:OnTimerExpired(sessionId)

            -- auto_distribute_delay uses C_Timer.After which fires immediately in tests
            -- Session should be awarded
            assert.is_true(LootMaster.sessions[sessionId].awarded)
            -- Player2 should have been awarded (highest PR MS)
            -- Player2: 3000,500 -> GP +1000 -> 3000,1500
            assert.are.equal("3000,1500", _G._testGuildRoster[2].officerNote)

            SimpleEPGP.db.profile.auto_distribute = false  -- reset
        end)

        it("falls back to OS when no MS bids", function()
            SimpleEPGP.db.profile.auto_distribute = true
            local link = _G._testItemDB[29759][2]
            local sessionId = LootMaster:StartSession(link, 1000)

            LootMaster:OnBidReceived("Player1", sessionId, "OS")

            LootMaster:OnTimerExpired(sessionId)

            assert.is_true(LootMaster.sessions[sessionId].awarded)
            -- OS = 50% of 1000 = 500 GP
            -- Player1: 5000,1000 -> GP +500 -> 5000,1500
            assert.are.equal("5000,1500", _G._testGuildRoster[1].officerNote)

            SimpleEPGP.db.profile.auto_distribute = false
        end)

        it("falls back to DE when no MS or OS bids", function()
            SimpleEPGP.db.profile.auto_distribute = true
            local link = _G._testItemDB[29759][2]
            local sessionId = LootMaster:StartSession(link, 1000)

            LootMaster:OnBidReceived("Player3", sessionId, "DE")

            LootMaster:OnTimerExpired(sessionId)

            assert.is_true(LootMaster.sessions[sessionId].awarded)
            -- DE = 0 GP
            -- Player3: 2000,2000 stays same
            assert.are.equal("2000,2000", _G._testGuildRoster[3].officerNote)

            SimpleEPGP.db.profile.auto_distribute = false
        end)

        it("does not auto-distribute when disabled", function()
            SimpleEPGP.db.profile.auto_distribute = false
            local link = _G._testItemDB[29759][2]
            local sessionId = LootMaster:StartSession(link, 1000)

            LootMaster:OnBidReceived("Player1", sessionId, "MS")

            LootMaster:OnTimerExpired(sessionId)

            -- Session should NOT be awarded in manual mode
            assert.is_false(LootMaster.sessions[sessionId].awarded)
        end)

        it("does nothing when auto-distribute enabled but no bids", function()
            SimpleEPGP.db.profile.auto_distribute = true
            local link = _G._testItemDB[29759][2]
            local sessionId = LootMaster:StartSession(link, 1000)
            -- No bids submitted

            LootMaster:OnTimerExpired(sessionId)

            -- Session should NOT be awarded (no winner found)
            assert.is_false(LootMaster.sessions[sessionId].awarded)
            -- All officer notes unchanged
            assert.are.equal("5000,1000", _G._testGuildRoster[1].officerNote)
            assert.are.equal("3000,500", _G._testGuildRoster[2].officerNote)

            SimpleEPGP.db.profile.auto_distribute = false
        end)
    end)

    describe("Timer expiry", function()
        it("fires on session start due to C_Timer immediate execution in tests", function()
            -- C_Timer.NewTicker fires immediately in test stubs
            -- which means OnTimerExpired is called during StartSession
            -- With auto_distribute=false, this just fires UI callback
            SimpleEPGP.db.profile.auto_distribute = false
            local link = _G._testItemDB[29759][2]
            local sessionId = LootMaster:StartSession(link, 1000)
            -- Session still valid (timer expired but no auto-distribute)
            assert.is_not_nil(LootMaster.sessions[sessionId])
            assert.is_false(LootMaster.sessions[sessionId].awarded)
        end)
    end)
end)
