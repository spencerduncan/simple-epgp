-----------------------------------------------------------------------
-- test_officer_panel.lua — Unit tests for OfficerPanel UI module
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

-- Load the module files (order matches .toc)
dofile("SimpleEPGP/EPGP.lua")
dofile("SimpleEPGP/GPCalc.lua")
dofile("SimpleEPGP/Log.lua")
dofile("SimpleEPGP/Comms.lua")
dofile("SimpleEPGP/LootMaster.lua")
dofile("SimpleEPGP/UI/Utils.lua")
dofile("SimpleEPGP/UI/Standings.lua")
dofile("SimpleEPGP/UI/OfficerPanel.lua")

-- Initialize addon
_G._testInitAddon("SimpleEPGP")

describe("OfficerPanel", function()
    local OfficerPanel
    local EPGP

    before_each(function()
        -- Reset officer notes to defaults
        _G._testGuildRoster[1].officerNote = "5000,1000"
        _G._testGuildRoster[2].officerNote = "3000,500"
        _G._testGuildRoster[3].officerNote = "2000,2000"
        _G._testGuildRoster[4].officerNote = "1000,100"
        _G._testGuildRoster[5].officerNote = ""

        -- Reset permissions
        _G.C_GuildInfo.CanEditOfficerNote = function() return true end
        _G.C_GuildInfo.CanViewOfficerNote = function() return true end

        OfficerPanel = SimpleEPGP:GetModule("OfficerPanel")
        EPGP = SimpleEPGP:GetModule("EPGP")

        -- Build standings from guild roster
        EPGP:GUILD_ROSTER_UPDATE()

        -- Clear print log
        SimpleEPGP._printLog = {}
    end)

    after_each(function()
        OfficerPanel:Hide()
        OfficerPanel:CancelPendingConfirm()
    end)

    describe("Show/Hide/Toggle", function()
        it("shows the panel", function()
            OfficerPanel:Show()
            assert.is_true(OfficerPanel:IsShown())
        end)

        it("hides the panel", function()
            OfficerPanel:Show()
            OfficerPanel:Hide()
            assert.is_false(OfficerPanel:IsShown())
        end)

        it("toggles the panel", function()
            assert.is_false(OfficerPanel:IsShown())
            OfficerPanel:Toggle()
            assert.is_true(OfficerPanel:IsShown())
            OfficerPanel:Toggle()
            assert.is_false(OfficerPanel:IsShown())
        end)
    end)

    describe("Player list", function()
        it("contains all guild members from standings", function()
            OfficerPanel:Show()
            local list = OfficerPanel:GetPlayerList()
            assert.are.equal(5, #list)
        end)

        it("is sorted alphabetically", function()
            OfficerPanel:Show()
            local list = OfficerPanel:GetPlayerList()
            for i = 2, #list do
                assert.is_true(list[i - 1] <= list[i],
                    "Expected alphabetical order at index " .. i)
            end
        end)

        it("updates when standings change", function()
            OfficerPanel:Show()
            -- Verify initial count
            local list = OfficerPanel:GetPlayerList()
            assert.are.equal(5, #list)
        end)
    end)

    describe("Player selection", function()
        it("allows selecting a player", function()
            OfficerPanel:Show()
            OfficerPanel:SetSelectedPlayer("Player1")
            assert.are.equal("Player1", OfficerPanel:GetSelectedPlayer())
        end)

        it("allows clearing selection", function()
            OfficerPanel:Show()
            OfficerPanel:SetSelectedPlayer("Player1")
            OfficerPanel:SetSelectedPlayer(nil)
            assert.is_nil(OfficerPanel:GetSelectedPlayer())
        end)
    end)

    describe("EP Adjustment", function()
        it("modifies EP via confirmation dialog", function()
            OfficerPanel:Show()
            OfficerPanel:SetSelectedPlayer("Player1")

            -- Initial EP for Player1 is 5000
            local info = EPGP:GetPlayerInfo("Player1")
            assert.are.equal(5000, info.ep)

            -- Simulate filling in amount and confirming
            OfficerPanel:ShowConfirmDialog("Award +100 EP to Player1?", function()
                EPGP:ModifyEP("Player1", 100, "Test EP award")
            end)

            -- Confirm the action
            OfficerPanel:ExecutePendingConfirm()

            -- Refresh standings
            EPGP:GUILD_ROSTER_UPDATE()

            -- Verify EP increased
            info = EPGP:GetPlayerInfo("Player1")
            assert.are.equal(5100, info.ep)
        end)

        it("cancelling confirmation does not modify EP", function()
            OfficerPanel:Show()
            OfficerPanel:SetSelectedPlayer("Player1")

            local info = EPGP:GetPlayerInfo("Player1")
            assert.are.equal(5000, info.ep)

            OfficerPanel:ShowConfirmDialog("Award +100 EP to Player1?", function()
                EPGP:ModifyEP("Player1", 100, "Test EP award")
            end)

            -- Cancel instead of confirming
            OfficerPanel:CancelPendingConfirm()

            -- Verify EP unchanged
            info = EPGP:GetPlayerInfo("Player1")
            assert.are.equal(5000, info.ep)
        end)

        it("supports negative EP amounts", function()
            OfficerPanel:Show()
            OfficerPanel:SetSelectedPlayer("Player2")

            local info = EPGP:GetPlayerInfo("Player2")
            assert.are.equal(3000, info.ep)

            OfficerPanel:ShowConfirmDialog("Award -500 EP to Player2?", function()
                EPGP:ModifyEP("Player2", -500, "EP penalty")
            end)
            OfficerPanel:ExecutePendingConfirm()

            EPGP:GUILD_ROSTER_UPDATE()
            info = EPGP:GetPlayerInfo("Player2")
            assert.are.equal(2500, info.ep)
        end)
    end)

    describe("GP Adjustment", function()
        it("modifies GP via confirmation dialog", function()
            OfficerPanel:Show()
            OfficerPanel:SetSelectedPlayer("Player2")

            local info = EPGP:GetPlayerInfo("Player2")
            assert.are.equal(500, info.gp)

            OfficerPanel:ShowConfirmDialog("Adjust +200 GP on Player2?", function()
                EPGP:ModifyGP("Player2", 200, "Test GP adjustment")
            end)
            OfficerPanel:ExecutePendingConfirm()

            EPGP:GUILD_ROSTER_UPDATE()
            info = EPGP:GetPlayerInfo("Player2")
            assert.are.equal(700, info.gp)
        end)

        it("supports negative GP amounts", function()
            OfficerPanel:Show()
            OfficerPanel:SetSelectedPlayer("Player3")

            local info = EPGP:GetPlayerInfo("Player3")
            assert.are.equal(2000, info.gp)

            OfficerPanel:ShowConfirmDialog("Adjust -300 GP on Player3?", function()
                EPGP:ModifyGP("Player3", -300, "GP correction")
            end)
            OfficerPanel:ExecutePendingConfirm()

            EPGP:GUILD_ROSTER_UPDATE()
            info = EPGP:GetPlayerInfo("Player3")
            assert.are.equal(1700, info.gp)
        end)
    end)

    describe("Mass EP", function()
        it("awards EP to all raid members via confirmation dialog", function()
            OfficerPanel:Show()

            -- Record initial EP values
            local p1Before = EPGP:GetPlayerInfo("Player1").ep
            local p2Before = EPGP:GetPlayerInfo("Player2").ep

            OfficerPanel:ShowConfirmDialog("Award 50 EP to ALL raid members?", function()
                EPGP:MassEP(50, "Test mass EP")
            end)
            OfficerPanel:ExecutePendingConfirm()

            EPGP:GUILD_ROSTER_UPDATE()

            local p1After = EPGP:GetPlayerInfo("Player1").ep
            local p2After = EPGP:GetPlayerInfo("Player2").ep

            assert.are.equal(p1Before + 50, p1After)
            assert.are.equal(p2Before + 50, p2After)
        end)
    end)

    describe("Decay", function()
        it("applies decay via confirmation dialog", function()
            OfficerPanel:Show()

            -- Player1 has EP=5000, GP=1000, decay is 15%
            local p1Before = EPGP:GetPlayerInfo("Player1")
            assert.are.equal(5000, p1Before.ep)
            assert.are.equal(1000, p1Before.gp)

            OfficerPanel:ShowConfirmDialog("Apply 15% decay?", function()
                EPGP:Decay()
            end)
            OfficerPanel:ExecutePendingConfirm()

            EPGP:GUILD_ROSTER_UPDATE()

            local p1After = EPGP:GetPlayerInfo("Player1")
            -- 5000 * 0.85 = 4250, 1000 * 0.85 = 850
            assert.are.equal(4250, p1After.ep)
            assert.are.equal(850, p1After.gp)
        end)

        it("cancelling decay does nothing", function()
            OfficerPanel:Show()

            OfficerPanel:ShowConfirmDialog("Apply 15% decay?", function()
                EPGP:Decay()
            end)
            OfficerPanel:CancelPendingConfirm()

            local p1 = EPGP:GetPlayerInfo("Player1")
            assert.are.equal(5000, p1.ep)
            assert.are.equal(1000, p1.gp)
        end)
    end)

    describe("Reset", function()
        it("resets all EP/GP via confirmation dialog", function()
            OfficerPanel:Show()

            -- Verify some players have non-zero values
            assert.are.equal(5000, EPGP:GetPlayerInfo("Player1").ep)
            assert.are.equal(3000, EPGP:GetPlayerInfo("Player2").ep)

            OfficerPanel:ShowConfirmDialog("Reset ALL EP/GP to 0?", function()
                EPGP:ResetAll()
            end)
            OfficerPanel:ExecutePendingConfirm()

            EPGP:GUILD_ROSTER_UPDATE()

            -- All players with EPGP notes should be reset to 0
            assert.are.equal(0, EPGP:GetPlayerInfo("Player1").ep)
            assert.are.equal(0, EPGP:GetPlayerInfo("Player1").gp)
            assert.are.equal(0, EPGP:GetPlayerInfo("Player2").ep)
            assert.are.equal(0, EPGP:GetPlayerInfo("Player2").gp)
            assert.are.equal(0, EPGP:GetPlayerInfo("Player3").ep)
            assert.are.equal(0, EPGP:GetPlayerInfo("Player3").gp)
            assert.are.equal(0, EPGP:GetPlayerInfo("Player4").ep)
            assert.are.equal(0, EPGP:GetPlayerInfo("Player4").gp)
        end)

        it("cancelling reset preserves values", function()
            OfficerPanel:Show()

            OfficerPanel:ShowConfirmDialog("Reset ALL EP/GP to 0?", function()
                EPGP:ResetAll()
            end)
            OfficerPanel:CancelPendingConfirm()

            assert.are.equal(5000, EPGP:GetPlayerInfo("Player1").ep)
            assert.are.equal(1000, EPGP:GetPlayerInfo("Player1").gp)
        end)
    end)

    describe("Confirmation dialog", function()
        it("stores pending action", function()
            OfficerPanel:Show()
            local called = false
            OfficerPanel:ShowConfirmDialog("Test?", function()
                called = true
            end)

            assert.is_not_nil(OfficerPanel:GetPendingConfirmAction())
            assert.is_false(called)
        end)

        it("clears pending action after execution", function()
            OfficerPanel:Show()
            OfficerPanel:ShowConfirmDialog("Test?", function() end)
            OfficerPanel:ExecutePendingConfirm()
            assert.is_nil(OfficerPanel:GetPendingConfirmAction())
        end)

        it("clears pending action on cancel", function()
            OfficerPanel:Show()
            OfficerPanel:ShowConfirmDialog("Test?", function() end)
            OfficerPanel:CancelPendingConfirm()
            assert.is_nil(OfficerPanel:GetPendingConfirmAction())
        end)
    end)

    describe("Permission checks", function()
        it("blocks EP modification without officer permissions", function()
            OfficerPanel:Show()
            _G.C_GuildInfo.CanEditOfficerNote = function() return false end

            OfficerPanel:SetSelectedPlayer("Player1")

            -- EP should not change when we lack permissions
            local info = EPGP:GetPlayerInfo("Player1")
            assert.are.equal(5000, info.ep)

            -- ModifyEP should return false
            local ok = EPGP:ModifyEP("Player1", 100, "Should fail")
            assert.is_false(ok)

            EPGP:GUILD_ROSTER_UPDATE()
            info = EPGP:GetPlayerInfo("Player1")
            assert.are.equal(5000, info.ep)
        end)

        it("blocks GP modification without officer permissions", function()
            OfficerPanel:Show()
            _G.C_GuildInfo.CanEditOfficerNote = function() return false end

            local ok = EPGP:ModifyGP("Player1", 100, "Should fail")
            assert.is_false(ok)
        end)

        it("blocks mass EP without officer permissions", function()
            OfficerPanel:Show()
            _G.C_GuildInfo.CanEditOfficerNote = function() return false end

            local ok = EPGP:MassEP(100, "Should fail")
            assert.is_false(ok)
        end)

        it("blocks decay without officer permissions", function()
            OfficerPanel:Show()
            _G.C_GuildInfo.CanEditOfficerNote = function() return false end

            local ok = EPGP:Decay()
            assert.is_false(ok)
        end)

        it("blocks reset without officer permissions", function()
            OfficerPanel:Show()
            _G.C_GuildInfo.CanEditOfficerNote = function() return false end

            local ok = EPGP:ResetAll()
            assert.is_false(ok)
        end)
    end)
end)
