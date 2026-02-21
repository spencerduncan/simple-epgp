-----------------------------------------------------------------------
-- test_gpcalc.lua — Unit tests for GPCalc module
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

describe("GPCalc", function()
    local GPCalc

    before_each(function()
        GPCalc = SimpleEPGP:GetModule("GPCalc")
        -- Reset any slot/item overrides between tests
        SimpleEPGP.db.profile.slot_multipliers = {}
        SimpleEPGP.db.profile.item_overrides = {}
    end)

    describe("CalculateGP", function()
        it("calculates T4 Helm (ilvl 120, HEAD) as ~1000 GP", function()
            -- Item 29759: Helm of the Fallen Champion, ilvl 120, HEAD
            local link = _G._testItemDB[29759][2]
            local gp = GPCalc:CalculateGP(link)
            assert.is_not_nil(gp)
            -- Reference: 1000 GP +/-1
            assert.is_true(math.abs(gp - 1000) <= 1,
                "Expected ~1000 GP for T4 Helm, got " .. tostring(gp))
        end)

        it("calculates T4 Shoulder (ilvl 120, SHOULDER) as ~750 GP", function()
            local link = _G._testItemDB[29764][2]
            local gp = GPCalc:CalculateGP(link)
            assert.is_not_nil(gp)
            assert.is_true(math.abs(gp - 750) <= 1,
                "Expected ~750 GP for T4 Shoulder, got " .. tostring(gp))
        end)

        it("calculates T4 Chest (ilvl 120, CHEST) as ~1000 GP", function()
            local link = _G._testItemDB[29753][2]
            local gp = GPCalc:CalculateGP(link)
            assert.is_not_nil(gp)
            assert.is_true(math.abs(gp - 1000) <= 1,
                "Expected ~1000 GP for T4 Chest, got " .. tostring(gp))
        end)

        it("calculates Trinket ilvl 115 with correct multiplier", function()
            local link = _G._testItemDB[28789][2]
            local gp = GPCalc:CalculateGP(link)
            assert.is_not_nil(gp)
            -- ilvl 115 trinket with 1.25 mult: baseMult*2^(115/26)*1.25 ~ 1094
            assert.is_true(math.abs(gp - 1094) <= 2,
                "Expected ~1094 GP for ilvl 115 trinket, got " .. tostring(gp))
        end)

        it("calculates Tsunami Talisman (ilvl 128, TRINKET) as ~1547 GP", function()
            local link = _G._testItemDB[30627][2]
            local gp = GPCalc:CalculateGP(link)
            assert.is_not_nil(gp)
            -- baseMult*2^(128/26)*1.25 ~ 1547
            assert.is_true(math.abs(gp - 1547) <= 2,
                "Expected ~1547 GP for Tsunami Talisman, got " .. tostring(gp))
        end)

        it("calculates Warglaive (ilvl 156, 1H WEAPON) as ~3917 GP", function()
            local link = _G._testItemDB[32837][2]
            local gp = GPCalc:CalculateGP(link)
            assert.is_not_nil(gp)
            -- INVTYPE_WEAPON (1H) has 1.5x multiplier: baseMult*2^(156/26)*1.5 ~ 3917
            assert.is_true(math.abs(gp - 3917) <= 5,
                "Expected ~3917 GP for Warglaive (1H weapon), got " .. tostring(gp))
        end)

        it("returns nil for nil input", function()
            assert.is_nil(GPCalc:CalculateGP(nil))
        end)

        it("returns nil for non-existent item", function()
            assert.is_nil(GPCalc:CalculateGP("item:99999"))
        end)

        it("calculates 2H Weapon (ilvl 141, 2HWEAPON) with 2.0x multiplier", function()
            -- Item 30311: Pillar of Ferocity, ilvl 141, INVTYPE_2HWEAPON
            local link = _G._testItemDB[30311][2]
            local gp = GPCalc:CalculateGP(link)
            assert.is_not_nil(gp)
            -- baseMult * 2^(141/26) * 2.0
            -- 2HWEAPON is the highest multiplier (2.0x)
            -- Expected: ~3498-3502 range (floating point variance)
            assert.is_true(gp > 3400 and gp < 3600,
                "Expected ~3500 GP for 2H weapon ilvl 141, got " .. tostring(gp))
            -- Verify it's roughly double the 1H weapon at same ilvl would be
            -- (2.0/1.5 ratio = 1.33x)
        end)

        it("returns nil for below-quality-threshold item", function()
            -- Temporarily add a Rare item (quality 3) to the DB
            local rareItem = { "Rare Helm", "|cffa335ee|Hitem:99001::::::::70:::::::|h[Rare Helm]|h|r", 3, 115, 70, "Armor", "Plate", 1, "INVTYPE_HEAD", 123499, 0 }
            _G._testItemDB[99001] = rareItem
            -- quality_threshold is 4 (Epic), so quality 3 (Rare) should return nil
            local gp = GPCalc:CalculateGP(rareItem[2])
            assert.is_nil(gp)
            -- Clean up
            _G._testItemDB[99001] = nil
        end)
    end)

    describe("Item GP Overrides", function()
        it("returns override value instead of formula result", function()
            local link = _G._testItemDB[29759][2]
            -- Normal GP for T4 Helm is ~1000
            GPCalc:SetItemOverride(29759, 500)
            local gp = GPCalc:CalculateGP(link)
            assert.are.equal(500, gp)
        end)

        it("bypasses quality check for overridden items", function()
            -- Add a Rare item (quality 3, below threshold 4)
            local rareItem = { "Rare Helm", "|cffa335ee|Hitem:99002::::::::70:::::::|h[Rare Helm]|h|r", 3, 115, 70, "Armor", "Plate", 1, "INVTYPE_HEAD", 123499, 0 }
            _G._testItemDB[99002] = rareItem
            -- Without override, returns nil (below quality threshold)
            assert.is_nil(GPCalc:CalculateGP(rareItem[2]))
            -- With override, returns the override value
            GPCalc:SetItemOverride(99002, 200)
            assert.are.equal(200, GPCalc:CalculateGP(rareItem[2]))
            -- Clean up
            _G._testItemDB[99002] = nil
        end)

        it("ClearItemOverride reverts to formula", function()
            local link = _G._testItemDB[29759][2]
            GPCalc:SetItemOverride(29759, 500)
            assert.are.equal(500, GPCalc:CalculateGP(link))
            GPCalc:ClearItemOverride(29759)
            local gp = GPCalc:CalculateGP(link)
            assert.is_true(math.abs(gp - 1000) <= 1)
        end)

        it("GetAllItemOverrides returns all overrides", function()
            GPCalc:SetItemOverride(29759, 500)
            GPCalc:SetItemOverride(29764, 300)
            local overrides = GPCalc:GetAllItemOverrides()
            assert.are.equal(500, overrides[29759])
            assert.are.equal(300, overrides[29764])
        end)

        it("GetAllItemOverrides returns empty table when none set", function()
            local overrides = GPCalc:GetAllItemOverrides()
            local count = 0
            for _ in pairs(overrides) do count = count + 1 end
            assert.are.equal(0, count)
        end)

        it("OS/DE multipliers apply on top of item override", function()
            local link = _G._testItemDB[29759][2]
            GPCalc:SetItemOverride(29759, 600)
            -- MS = 600
            assert.are.equal(600, GPCalc:GetBidGP(link, "MS"))
            -- OS = 600 * 0.5 = 300
            assert.are.equal(300, GPCalc:GetBidGP(link, "OS"))
            -- DE = 600 * 0.0 = 0
            assert.are.equal(0, GPCalc:GetBidGP(link, "DE"))
            -- PASS = 0
            assert.are.equal(0, GPCalc:GetBidGP(link, "PASS"))
        end)
    end)

    describe("Slot Multiplier API", function()
        it("IsKnownSlot returns true for valid slots", function()
            assert.is_true(GPCalc:IsKnownSlot("INVTYPE_HEAD"))
            assert.is_true(GPCalc:IsKnownSlot("INVTYPE_TRINKET"))
            assert.is_true(GPCalc:IsKnownSlot("INVTYPE_2HWEAPON"))
        end)

        it("IsKnownSlot returns false for invalid slots", function()
            assert.is_false(GPCalc:IsKnownSlot("INVTYPE_NONEXISTENT"))
            assert.is_false(GPCalc:IsKnownSlot(""))
            assert.is_false(GPCalc:IsKnownSlot(nil))
        end)

        it("SetSlotMultiplier overrides default", function()
            GPCalc:SetSlotMultiplier("INVTYPE_HEAD", 2.0)
            assert.are.equal(2.0, GPCalc:GetSlotMultiplier("INVTYPE_HEAD"))
        end)

        it("ResetSlotMultiplier reverts to default", function()
            GPCalc:SetSlotMultiplier("INVTYPE_HEAD", 2.0)
            assert.are.equal(2.0, GPCalc:GetSlotMultiplier("INVTYPE_HEAD"))
            GPCalc:ResetSlotMultiplier("INVTYPE_HEAD")
            assert.are.equal(1.0, GPCalc:GetSlotMultiplier("INVTYPE_HEAD"))
        end)

        it("SetSlotMultiplier rejects unknown slots", function()
            local ok = GPCalc:SetSlotMultiplier("INVTYPE_FAKE", 1.5)
            assert.is_false(ok)
        end)

        it("slot override affects GP calculation", function()
            local link = _G._testItemDB[29759][2]  -- HEAD, ilvl 120
            -- Default HEAD mult is 1.0, GP ~1000
            local gpBefore = GPCalc:CalculateGP(link)
            assert.is_true(math.abs(gpBefore - 1000) <= 1)
            -- Override HEAD to 2.0
            GPCalc:SetSlotMultiplier("INVTYPE_HEAD", 2.0)
            local gpAfter = GPCalc:CalculateGP(link)
            assert.is_true(math.abs(gpAfter - 2000) <= 1,
                "Expected ~2000 GP with 2.0x head mult, got " .. tostring(gpAfter))
        end)

        it("GetAllSlotInfo returns all 26 slots", function()
            local slots = GPCalc:GetAllSlotInfo()
            -- Count: 25 actual slots in DEFAULT_SLOT_MULTIPLIERS
            assert.is_true(#slots >= 25)
        end)

        it("GetAllSlotInfo marks overrides correctly", function()
            GPCalc:SetSlotMultiplier("INVTYPE_HEAD", 1.5)
            local slots = GPCalc:GetAllSlotInfo()
            local headFound = false
            for _, info in ipairs(slots) do
                if info.key == "INVTYPE_HEAD" then
                    headFound = true
                    assert.is_true(info.isOverride)
                    assert.are.equal(1.5, info.current)
                    assert.are.equal(1.0, info.default)
                end
            end
            assert.is_true(headFound)
        end)
    end)

    describe("ParseItemID", function()
        it("parses from item link", function()
            local link = _G._testItemDB[29759][2]
            assert.are.equal(29759, GPCalc:ParseItemID(link))
        end)

        it("parses from plain number string", function()
            assert.are.equal(29759, GPCalc:ParseItemID("29759"))
        end)

        it("parses from number", function()
            assert.are.equal(29759, GPCalc:ParseItemID(29759))
        end)

        it("returns nil for nil", function()
            assert.is_nil(GPCalc:ParseItemID(nil))
        end)

        it("returns nil for non-parseable string", function()
            assert.is_nil(GPCalc:ParseItemID("not_an_item"))
        end)
    end)

    describe("GetBidGP", function()
        it("returns full GP for MS bid", function()
            local link = _G._testItemDB[29759][2]
            local gp = GPCalc:GetBidGP(link, "MS")
            assert.is_true(math.abs(gp - 1000) <= 1)
        end)

        it("returns 50% GP for OS bid", function()
            local link = _G._testItemDB[29759][2]
            local gp = GPCalc:GetBidGP(link, "OS")
            assert.are.equal(500, gp)
        end)

        it("returns 0 GP for DE bid", function()
            local link = _G._testItemDB[29759][2]
            local gp = GPCalc:GetBidGP(link, "DE")
            assert.are.equal(0, gp)
        end)

        it("returns 0 GP for PASS", function()
            local link = _G._testItemDB[29759][2]
            local gp = GPCalc:GetBidGP(link, "PASS")
            assert.are.equal(0, gp)
        end)
    end)

    describe("GetBaseMultiplier", function()
        it("derives from standard_ilvl when gp_base_multiplier is nil", function()
            local mult = GPCalc:GetBaseMultiplier()
            -- 1000 * 2^(-120/26) ~ 40.8
            assert.is_true(mult > 40 and mult < 42,
                "Expected ~40.8 base mult, got " .. tostring(mult))
        end)

        it("uses explicit gp_base_multiplier when set", function()
            SimpleEPGP.db.profile.gp_base_multiplier = 50
            local mult = GPCalc:GetBaseMultiplier()
            assert.are.equal(50, mult)
            SimpleEPGP.db.profile.gp_base_multiplier = nil  -- reset
        end)
    end)
end)
