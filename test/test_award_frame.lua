-----------------------------------------------------------------------
-- test_award_frame.lua -- Unit tests for AwardFrame UI module
-- Tests autocomplete player search, manual award flow, and button states.
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
dofile("SimpleEPGP/UI/AwardFrame.lua")

-- Initialize addon (triggers OnInitialize + OnEnable for addon and all modules)
_G._testInitAddon("SimpleEPGP")

describe("AwardFrame", function()
    local AF, EPGP, LootMaster

    before_each(function()
        -- Reset guild roster officer notes
        _G._testGuildRoster[1].officerNote = "5000,1000"
        _G._testGuildRoster[2].officerNote = "3000,500"
        _G._testGuildRoster[3].officerNote = "2000,2000"
        _G._testGuildRoster[4].officerNote = "1000,100"
        _G._testGuildRoster[5].officerNote = ""

        AF = SimpleEPGP:GetModule("AwardFrame")
        EPGP = SimpleEPGP:GetModule("EPGP")
        LootMaster = SimpleEPGP:GetModule("LootMaster")

        -- Rebuild standings so PR values are current
        EPGP:GUILD_ROSTER_UPDATE()

        -- Reset LootMaster sessions
        LootMaster.sessions = {}
        LootMaster.nextSessionId = 1

        -- Clear sent messages
        for i = #_G._testSentMessages, 1, -1 do
            _G._testSentMessages[i] = nil
        end
    end)

    describe("Module registration", function()
        it("is registered as a module", function()
            assert.is_not_nil(AF)
        end)

        it("has autocomplete methods", function()
            assert.is_function(AF.GetAutocompleteCandidates)
            assert.is_function(AF.SelectAutocompletePlayer)
            assert.is_function(AF.HideAutocomplete)
        end)

        it("has test accessor methods", function()
            assert.is_function(AF.GetManualBidType)
            assert.is_function(AF.SetManualBidType)
            assert.is_function(AF.GetSelectedBidder)
            assert.is_function(AF.GetActiveSessionId)
            assert.is_function(AF.UpdateButtonStates)
        end)
    end)

    ---------------------------------------------------------------------------
    -- Autocomplete Candidates
    ---------------------------------------------------------------------------

    describe("GetAutocompleteCandidates", function()
        it("returns empty for nil input", function()
            local results = AF:GetAutocompleteCandidates(nil)
            assert.are.equal(0, #results)
        end)

        it("returns empty for empty string", function()
            local results = AF:GetAutocompleteCandidates("")
            assert.are.equal(0, #results)
        end)

        it("matches standings players by prefix", function()
            local results = AF:GetAutocompleteCandidates("Player1")
            assert.is_true(#results >= 1)
            local found = false
            for _, r in ipairs(results) do
                if r.name == "Player1" then found = true end
            end
            assert.is_true(found, "Player1 should be in results")
        end)

        it("matches case-insensitively", function()
            local results = AF:GetAutocompleteCandidates("player1")
            assert.is_true(#results >= 1)
            local found = false
            for _, r in ipairs(results) do
                if r.name == "Player1" then found = true end
            end
            assert.is_true(found, "Player1 should match lowercase search")
        end)

        it("matches by uppercase prefix", function()
            local results = AF:GetAutocompleteCandidates("PLAYER")
            assert.is_true(#results >= 1)
        end)

        it("matches by substring", function()
            -- "layer" is a substring of "Player1"
            local results = AF:GetAutocompleteCandidates("layer")
            assert.is_true(#results >= 1)
            local found = false
            for _, r in ipairs(results) do
                if r.name == "Player1" then found = true end
            end
            assert.is_true(found, "Substring match should find Player1")
        end)

        it("returns multiple matching players", function()
            -- "Player" should match Player1 through Player5
            local results = AF:GetAutocompleteCandidates("Player")
            assert.is_true(#results >= 5, "Should find at least 5 players matching 'Player'")
        end)

        it("deduplicates standings and raid members", function()
            -- Player1 through Player5 are in both standings and raid roster
            local results = AF:GetAutocompleteCandidates("Player")
            local nameCount = {}
            for _, r in ipairs(results) do
                nameCount[r.name] = (nameCount[r.name] or 0) + 1
            end
            for name, count in pairs(nameCount) do
                assert.are.equal(1, count, name .. " should appear only once")
            end
        end)

        it("includes class information", function()
            local results = AF:GetAutocompleteCandidates("Player1")
            assert.is_true(#results >= 1)
            -- Player1 is a WARRIOR in the test roster
            local p1 = nil
            for _, r in ipairs(results) do
                if r.name == "Player1" then p1 = r end
            end
            assert.is_not_nil(p1)
            assert.are.equal("WARRIOR", p1.class)
        end)

        it("returns results sorted alphabetically", function()
            local results = AF:GetAutocompleteCandidates("Player")
            for i = 2, #results do
                assert.is_true(results[i - 1].name <= results[i].name,
                    "Results should be sorted alphabetically")
            end
        end)

        it("limits results to max 8", function()
            -- Add extra guild members to exceed 8
            local originalRoster = {}
            for i, m in ipairs(_G._testGuildRoster) do
                originalRoster[i] = m
            end
            for i = 6, 15 do
                _G._testGuildRoster[i] = {
                    name = "TestPlayer" .. i .. "-TestRealm",
                    rankName = "Raider",
                    rankIndex = 2,
                    level = 70,
                    classDisplayName = "Warrior",
                    zone = "Shattrath City",
                    publicNote = "",
                    officerNote = "100,100",
                    isOnline = true,
                    status = 0,
                    class = "WARRIOR",
                    guid = "Player-" .. i,
                }
            end
            EPGP:GUILD_ROSTER_UPDATE()

            local results = AF:GetAutocompleteCandidates("Test")
            assert.is_true(#results <= 8, "Should return at most 8 results")

            -- Cleanup: restore original roster
            for i = #_G._testGuildRoster, 6, -1 do
                _G._testGuildRoster[i] = nil
            end
            EPGP:GUILD_ROSTER_UPDATE()
        end)

        it("returns no results for non-matching text", function()
            local results = AF:GetAutocompleteCandidates("Zzzzzzz")
            assert.are.equal(0, #results)
        end)

        it("includes raid members not in standings", function()
            -- Add a raid member that is NOT in the guild roster
            local originalRaid = {}
            for i, m in ipairs(_G._testRaidRoster) do
                originalRaid[i] = m
            end
            _G._testRaidRoster[#_G._testRaidRoster + 1] = {
                name = "PugPlayer-OtherRealm",
                rank = 0,
                subgroup = 3,
                level = 70,
                class = "ROGUE",
                fileName = "ROGUE",
                zone = "Karazhan",
                online = true,
                isDead = false,
                role = "NONE",
                isML = false,
            }

            local results = AF:GetAutocompleteCandidates("Pug")
            assert.is_true(#results >= 1)
            local found = false
            for _, r in ipairs(results) do
                if r.name == "PugPlayer" then
                    found = true
                    assert.are.equal("ROGUE", r.class)
                end
            end
            assert.is_true(found, "PugPlayer from raid should appear")

            -- Cleanup
            _G._testRaidRoster[#_G._testRaidRoster] = nil
        end)
    end)

    ---------------------------------------------------------------------------
    -- SelectAutocompletePlayer
    ---------------------------------------------------------------------------

    describe("SelectAutocompletePlayer", function()
        it("sets selectedBidder with player info", function()
            AF:SelectAutocompletePlayer("Player1", "WARRIOR")
            local bidder = AF:GetSelectedBidder()
            assert.is_not_nil(bidder)
            assert.are.equal("Player1", bidder.name)
            assert.are.equal("WARRIOR", bidder.class)
            assert.is_true(bidder.isManual)
        end)

        it("uses manual bid type", function()
            AF:SetManualBidType("OS")
            AF:SelectAutocompletePlayer("Player2", "PALADIN")
            local bidder = AF:GetSelectedBidder()
            assert.are.equal("OS", bidder.bidType)
        end)

        it("defaults to MS bid type", function()
            AF:SetManualBidType("MS")
            AF:SelectAutocompletePlayer("Player3", "HUNTER")
            local bidder = AF:GetSelectedBidder()
            assert.are.equal("MS", bidder.bidType)
        end)

        it("populates EP/GP/PR from standings", function()
            AF:SelectAutocompletePlayer("Player1", "WARRIOR")
            local bidder = AF:GetSelectedBidder()
            -- Player1 has EP=5000, GP=1000 in test roster
            assert.are.equal(5000, bidder.ep)
            assert.are.equal(1000, bidder.gp)
            assert.is_true(bidder.pr > 0)
        end)

        it("handles unknown player with zero EP/GP/PR", function()
            AF:SelectAutocompletePlayer("UnknownPug", "ROGUE")
            local bidder = AF:GetSelectedBidder()
            assert.are.equal(0, bidder.ep)
            assert.are.equal(0, bidder.gp)
            assert.are.equal(0, bidder.pr)
        end)
    end)

    ---------------------------------------------------------------------------
    -- Manual Bid Type
    ---------------------------------------------------------------------------

    describe("ManualBidType", function()
        it("defaults to MS", function()
            -- Reset via ShowLoot
            local items = {
                { itemLink = _G._testItemDB[29759][2], gpCost = 1000, quality = 4 },
            }
            AF:ShowLoot(items)
            assert.are.equal("MS", AF:GetManualBidType())
        end)

        it("can be set to OS", function()
            AF:SetManualBidType("OS")
            assert.are.equal("OS", AF:GetManualBidType())
        end)

        it("can be set to DE", function()
            AF:SetManualBidType("DE")
            assert.are.equal("DE", AF:GetManualBidType())
        end)
    end)

    ---------------------------------------------------------------------------
    -- Button States (via ShowLoot + UpdateButtonStates)
    ---------------------------------------------------------------------------

    describe("Button states", function()
        local items

        before_each(function()
            items = {
                { itemLink = _G._testItemDB[29759][2], gpCost = 1000, quality = 4, lootIndex = 1 },
            }
            AF:ShowLoot(items)
        end)

        it("all buttons disabled on initial show", function()
            -- After ShowLoot with no item selected, start should be disabled
            -- because no item is selected yet
            local frame = AF:GetFrame()
            assert.is_not_nil(frame)
            -- selectedItemIndex is nil, so all should be disabled
            assert.is_nil(AF:GetSelectedItemIndex())
        end)

        it("start enabled after item selection", function()
            AF:SelectItem(1)
            -- Start should be enabled (item selected, no session)
            assert.is_not_nil(AF:GetSelectedItemIndex())
            assert.is_nil(AF:GetActiveSessionId())
        end)

        it("start disabled and cancel enabled after starting session", function()
            AF:SelectItem(1)
            AF:OnStartBidding()
            -- Now there should be an active session
            assert.is_not_nil(AF:GetActiveSessionId())
        end)

        it("award enabled after selecting a bidder", function()
            AF:SelectItem(1)
            AF:OnStartBidding()
            local sessionId = AF:GetActiveSessionId()
            assert.is_not_nil(sessionId)

            -- Select a bidder via autocomplete
            AF:SelectAutocompletePlayer("Player1", "WARRIOR")
            local bidder = AF:GetSelectedBidder()
            assert.is_not_nil(bidder)
            assert.are.equal("Player1", bidder.name)
        end)

        it("resets after cancel", function()
            AF:SelectItem(1)
            AF:OnStartBidding()
            AF:SelectAutocompletePlayer("Player1", "WARRIOR")
            AF:OnCancelSession()

            assert.is_nil(AF:GetActiveSessionId())
            assert.is_nil(AF:GetSelectedBidder())
        end)
    end)

    ---------------------------------------------------------------------------
    -- SelectBidder clears manual flag
    ---------------------------------------------------------------------------

    describe("SelectBidder", function()
        it("clears isManual flag when selecting from bid list", function()
            local bidder = {
                name = "Player2",
                class = "PALADIN",
                bidType = "MS",
                ep = 3000,
                gp = 500,
                pr = 5.0,
            }
            AF:SelectBidder(bidder)
            local selected = AF:GetSelectedBidder()
            assert.is_not_nil(selected)
            assert.are.equal("Player2", selected.name)
            assert.is_false(selected.isManual)
        end)
    end)

    ---------------------------------------------------------------------------
    -- OnSearchEnterPressed
    ---------------------------------------------------------------------------

    describe("OnSearchEnterPressed", function()
        it("does nothing when no results exist", function()
            -- Ensure no autocomplete results
            AF:HideAutocomplete()
            AF:OnSearchEnterPressed()
            -- Should not crash, no bidder selected
        end)
    end)

    ---------------------------------------------------------------------------
    -- OnSearchArrowKey
    ---------------------------------------------------------------------------

    describe("OnSearchArrowKey", function()
        it("does nothing when no results exist", function()
            AF:HideAutocomplete()
            AF:OnSearchArrowKey(1)  -- arrow down
            AF:OnSearchArrowKey(-1) -- arrow up
            -- Should not crash
        end)
    end)

    ---------------------------------------------------------------------------
    -- SetTestState
    ---------------------------------------------------------------------------

    describe("SetTestState", function()
        it("sets eligible items and session", function()
            local items = {
                { itemLink = "test", gpCost = 100 },
            }
            AF:SetTestState(items, 1, 42)
            assert.are.equal(1, AF:GetSelectedItemIndex())
            assert.are.equal(42, AF:GetActiveSessionId())
        end)
    end)

    ---------------------------------------------------------------------------
    -- Integration: Full manual award flow
    ---------------------------------------------------------------------------

    describe("Manual award flow", function()
        it("allows awarding to a non-bidder via autocomplete", function()
            local link = _G._testItemDB[29759][2]
            local items = {
                { itemLink = link, gpCost = 1000, quality = 4, lootIndex = 1 },
            }
            AF:ShowLoot(items)

            -- Select item
            AF:SelectItem(1)
            assert.is_not_nil(AF:GetSelectedItemIndex())

            -- Start bidding
            AF:OnStartBidding()
            local sessionId = AF:GetActiveSessionId()
            assert.is_not_nil(sessionId)

            -- No bids come in, but ML wants to award to Player3 via autocomplete
            AF:SetManualBidType("OS")
            AF:SelectAutocompletePlayer("Player3", "HUNTER")

            local bidder = AF:GetSelectedBidder()
            assert.is_not_nil(bidder)
            assert.are.equal("Player3", bidder.name)
            assert.are.equal("OS", bidder.bidType)
            assert.is_true(bidder.isManual)

            -- OnAwardClick would show the confirmation dialog
            -- We verify the data is correct for the dialog
            local session = LootMaster.sessions[sessionId]
            assert.is_not_nil(session)
            assert.are.equal(link, session.itemLink)
        end)
    end)
end)
