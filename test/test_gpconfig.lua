-----------------------------------------------------------------------
-- test_gpconfig.lua — Unit tests for GPConfig formula parameter UI
-- Tests the GPCalc formula parameter API and GPConfig module interaction
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
dofile("SimpleEPGP/UI/GPConfig.lua")

-- Initialize addon (triggers OnInitialize + OnEnable for addon and all modules)
_G._testInitAddon("SimpleEPGP")

describe("GPCalc Formula Parameters", function()
    local GPCalc

    before_each(function()
        GPCalc = SimpleEPGP:GetModule("GPCalc")
        -- Reset formula parameters to defaults
        SimpleEPGP.db.profile.base_gp = 100
        SimpleEPGP.db.profile.standard_ilvl = 120
        SimpleEPGP.db.profile.gp_base_multiplier = nil
    end)

    describe("GetBaseGP / SetBaseGP", function()
        it("returns default base_gp of 100", function()
            assert.are.equal(100, GPCalc:GetBaseGP())
        end)

        it("sets base_gp to a new value", function()
            assert.is_true(GPCalc:SetBaseGP(200))
            assert.are.equal(200, GPCalc:GetBaseGP())
        end)

        it("allows base_gp of 0", function()
            assert.is_true(GPCalc:SetBaseGP(0))
            assert.are.equal(0, GPCalc:GetBaseGP())
        end)

        it("rejects negative base_gp", function()
            assert.is_false(GPCalc:SetBaseGP(-1))
            assert.are.equal(100, GPCalc:GetBaseGP())
        end)

        it("rejects non-number base_gp", function()
            assert.is_false(GPCalc:SetBaseGP("abc"))
            assert.are.equal(100, GPCalc:GetBaseGP())
        end)
    end)

    describe("GetStandardIlvl / SetStandardIlvl", function()
        it("returns default standard_ilvl of 120", function()
            assert.are.equal(120, GPCalc:GetStandardIlvl())
        end)

        it("sets standard_ilvl to a new value", function()
            assert.is_true(GPCalc:SetStandardIlvl(141))
            assert.are.equal(141, GPCalc:GetStandardIlvl())
        end)

        it("rejects zero standard_ilvl", function()
            assert.is_false(GPCalc:SetStandardIlvl(0))
            assert.are.equal(120, GPCalc:GetStandardIlvl())
        end)

        it("rejects negative standard_ilvl", function()
            assert.is_false(GPCalc:SetStandardIlvl(-10))
            assert.are.equal(120, GPCalc:GetStandardIlvl())
        end)

        it("rejects non-number standard_ilvl", function()
            assert.is_false(GPCalc:SetStandardIlvl("abc"))
            assert.are.equal(120, GPCalc:GetStandardIlvl())
        end)
    end)

    describe("GetGPBaseMultiplier / SetGPBaseMultiplier / ClearGPBaseMultiplier", function()
        it("returns nil when not explicitly set", function()
            assert.is_nil(GPCalc:GetGPBaseMultiplier())
        end)

        it("sets an explicit base multiplier", function()
            assert.is_true(GPCalc:SetGPBaseMultiplier(50))
            assert.are.equal(50, GPCalc:GetGPBaseMultiplier())
        end)

        it("clears explicit base multiplier back to nil", function()
            GPCalc:SetGPBaseMultiplier(50)
            GPCalc:ClearGPBaseMultiplier()
            assert.is_nil(GPCalc:GetGPBaseMultiplier())
        end)

        it("rejects zero base multiplier", function()
            assert.is_false(GPCalc:SetGPBaseMultiplier(0))
            assert.is_nil(GPCalc:GetGPBaseMultiplier())
        end)

        it("rejects negative base multiplier", function()
            assert.is_false(GPCalc:SetGPBaseMultiplier(-5))
            assert.is_nil(GPCalc:GetGPBaseMultiplier())
        end)

        it("rejects non-number base multiplier", function()
            assert.is_false(GPCalc:SetGPBaseMultiplier("abc"))
            assert.is_nil(GPCalc:GetGPBaseMultiplier())
        end)

        it("explicit multiplier overrides derived in GetBaseMultiplier", function()
            GPCalc:SetGPBaseMultiplier(50)
            assert.are.equal(50, GPCalc:GetBaseMultiplier())
        end)

        it("clearing reverts GetBaseMultiplier to derived value", function()
            local derived = GPCalc:GetBaseMultiplier()
            GPCalc:SetGPBaseMultiplier(50)
            assert.are.equal(50, GPCalc:GetBaseMultiplier())
            GPCalc:ClearGPBaseMultiplier()
            assert.are.equal(derived, GPCalc:GetBaseMultiplier())
        end)
    end)

    describe("GetDerivedBaseMultiplier", function()
        it("returns derived value independent of explicit override", function()
            local derived = GPCalc:GetDerivedBaseMultiplier()
            GPCalc:SetGPBaseMultiplier(50)
            -- Derived should remain the same even with override set
            assert.are.equal(derived, GPCalc:GetDerivedBaseMultiplier())
        end)

        it("changes when standard_ilvl changes", function()
            local derived120 = GPCalc:GetDerivedBaseMultiplier()
            GPCalc:SetStandardIlvl(141)
            local derived141 = GPCalc:GetDerivedBaseMultiplier()
            -- Higher standard ilvl = lower derived base multiplier
            assert.is_true(derived141 < derived120,
                "Expected lower derived mult for higher ilvl")
        end)

        it("at ilvl 120 is approximately 40.8", function()
            local derived = GPCalc:GetDerivedBaseMultiplier()
            assert.is_true(derived > 40 and derived < 42,
                "Expected ~40.8, got " .. tostring(derived))
        end)
    end)

    describe("GetFormulaInfo", function()
        it("returns all formula parameters", function()
            local info = GPCalc:GetFormulaInfo()
            assert.are.equal(100, info.base_gp)
            assert.are.equal(120, info.standard_ilvl)
            assert.is_nil(info.gp_base_multiplier)
            assert.is_true(info.effective_base_mult > 40 and info.effective_base_mult < 42)
            -- At standard ilvl 120 with slot 1.0, example GP should be ~1000
            assert.is_true(math.abs(info.example_gp - 1000) <= 1,
                "Expected ~1000 example GP, got " .. tostring(info.example_gp))
        end)

        it("reflects explicit multiplier override", function()
            GPCalc:SetGPBaseMultiplier(50)
            local info = GPCalc:GetFormulaInfo()
            assert.are.equal(50, info.gp_base_multiplier)
            assert.are.equal(50, info.effective_base_mult)
        end)

        it("reflects base_gp changes", function()
            GPCalc:SetBaseGP(200)
            local info = GPCalc:GetFormulaInfo()
            assert.are.equal(200, info.base_gp)
        end)

        it("reflects standard_ilvl changes", function()
            GPCalc:SetStandardIlvl(141)
            local info = GPCalc:GetFormulaInfo()
            assert.are.equal(141, info.standard_ilvl)
        end)
    end)

    describe("GetFormulaStrings", function()
        it("returns three non-empty strings", function()
            local gpF, prF, ex = GPCalc:GetFormulaStrings()
            assert.is_truthy(gpF)
            assert.is_truthy(prF)
            assert.is_truthy(ex)
            assert.is_true(#gpF > 0)
            assert.is_true(#prF > 0)
            assert.is_true(#ex > 0)
        end)

        it("GP formula contains the effective base multiplier", function()
            local gpF = GPCalc:GetFormulaStrings()
            -- Default base mult is ~40.8, should appear as "40.8" something
            assert.is_truthy(gpF:match("40%.8"))
        end)

        it("PR formula contains base_gp value", function()
            local _, prF = GPCalc:GetFormulaStrings()
            assert.is_truthy(prF:match("100"))
        end)

        it("example contains standard ilvl and GP value", function()
            local _, _, ex = GPCalc:GetFormulaStrings()
            assert.is_truthy(ex:match("120"))
            assert.is_truthy(ex:match("1000"))
        end)
    end)

    describe("standard_ilvl affects GP calculation", function()
        it("changing standard_ilvl changes CalculateGP when no explicit mult", function()
            local link = _G._testItemDB[29759][2]  -- ilvl 120 HEAD
            local gpDefault = GPCalc:CalculateGP(link)
            assert.is_true(math.abs(gpDefault - 1000) <= 1)

            -- Increase standard_ilvl -> lower base mult -> lower GP
            GPCalc:SetStandardIlvl(141)
            local gpHigher = GPCalc:CalculateGP(link)
            assert.is_true(gpHigher < gpDefault,
                "Expected lower GP with higher standard_ilvl, got " .. tostring(gpHigher))
        end)
    end)
end)

describe("GPConfig module", function()
    local GPConfig

    before_each(function()
        GPConfig = SimpleEPGP:GetModule("GPConfig")
    end)

    it("can show and hide", function()
        GPConfig:Show()
        GPConfig:Hide()
    end)

    it("can toggle", function()
        GPConfig:Toggle()
        GPConfig:Toggle()
    end)
end)
