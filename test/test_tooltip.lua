-----------------------------------------------------------------------
-- test_tooltip.lua — Unit tests for Tooltip module (GP cost in tooltips)
-----------------------------------------------------------------------

-- Load stubs first
require("test.wow_stubs")
require("test.ace_stubs")

-- Core.lua is loaded FIRST in .toc — creates the addon via NewAddon
dofile("SimpleEPGP/Core.lua")

-- Get the addon object (Core.lua created it)
local SimpleEPGP = LibStub("AceAddon-3.0"):GetAddon("SimpleEPGP")

-----------------------------------------------------------------------
-- GameTooltip spy setup — track calls made by AddGPLine
-----------------------------------------------------------------------

local addLineLog = {}
local addDoubleLineLog = {}
local showCount = 0

-- Store hooked script handlers so tests can fire OnTooltipCleared
local hookScriptHandlers = {}

_G.GameTooltip.HookScript = function(self, event, handler)
    hookScriptHandlers[event] = hookScriptHandlers[event] or {}
    table.insert(hookScriptHandlers[event], handler)
end

-- Replace AddLine/AddDoubleLine/Show with spies
_G.GameTooltip.AddLine = function(self, text, r, g, b)
    table.insert(addLineLog, { text = text, r = r, g = g, b = b })
end

_G.GameTooltip.AddDoubleLine = function(self, left, right, lr, lg, lb, rr, rg, rb)
    table.insert(addDoubleLineLog, {
        left = left, right = right,
        lr = lr, lg = lg, lb = lb,
        rr = rr, rg = rg, rb = rb,
    })
end

_G.GameTooltip.Show = function(self)
    showCount = showCount + 1
end

-- Add GetItem stub for SetBagItem hook path
_G.GameTooltip.GetItem = function(self)
    return nil, nil
end

-- Fire all hooked OnTooltipCleared handlers (resets gpLineAdded flag)
local function fireOnTooltipCleared()
    local handlers = hookScriptHandlers["OnTooltipCleared"]
    if handlers then
        for _, handler in ipairs(handlers) do
            handler()
        end
    end
end

-- Reset spy counters
local function resetSpies()
    for i = #addLineLog, 1, -1 do addLineLog[i] = nil end
    for i = #addDoubleLineLog, 1, -1 do addDoubleLineLog[i] = nil end
    showCount = 0
end

-----------------------------------------------------------------------
-- Load module files (order matches .toc)
-----------------------------------------------------------------------

dofile("SimpleEPGP/EPGP.lua")
dofile("SimpleEPGP/GPCalc.lua")
dofile("SimpleEPGP/Log.lua")
dofile("SimpleEPGP/Comms.lua")
dofile("SimpleEPGP/LootMaster.lua")
dofile("SimpleEPGP/UI/Tooltip.lua")

-- Initialize addon and all modules (triggers OnEnable, which installs hooks)
_G._testInitAddon("SimpleEPGP")

-----------------------------------------------------------------------
-- Tests
-----------------------------------------------------------------------

describe("Tooltip", function()
    -- Item links from the test item database
    local epicHelmLink = _G._testItemDB[29759][2]    -- ilvl 120, HEAD, quality 4 (Epic)
    local epicShoulderLink = _G._testItemDB[29764][2] -- ilvl 120, SHOULDER, quality 4

    before_each(function()
        -- Reset spy state
        resetSpies()
        -- Reset gpLineAdded flag via OnTooltipCleared
        fireOnTooltipCleared()
        -- Ensure config is in default state
        SimpleEPGP.db.profile.show_gp_tooltip = true
        SimpleEPGP.db.profile.quality_threshold = 4
        SimpleEPGP.db.profile.slot_multipliers = {}
        SimpleEPGP.db.profile.item_overrides = {}
    end)

    describe("AddGPLine", function()
        it("adds GP text to tooltip for valid items", function()
            -- Trigger AddGPLine through the SetHyperlink hook
            _G.GameTooltip:SetHyperlink(epicHelmLink)

            -- Should have added a blank separator line
            assert.is_true(#addLineLog >= 1,
                "Expected at least 1 AddLine call (blank separator)")
            assert.are.equal(" ", addLineLog[1].text)

            -- Should have added GP Cost (MS) double line
            assert.is_true(#addDoubleLineLog >= 1,
                "Expected at least 1 AddDoubleLine call for MS GP cost")
            assert.are.equal("GP Cost (MS):", addDoubleLineLog[1].left)

            -- GP value should be the string form of the calculated GP (~1000)
            local gpStr = addDoubleLineLog[1].right
            local gpVal = tonumber(gpStr)
            assert.is_not_nil(gpVal, "GP cost should be a number string")
            assert.is_true(math.abs(gpVal - 1000) <= 1,
                "Expected ~1000 GP for T4 Helm, got " .. tostring(gpVal))

            -- Should have added GP Cost (OS) double line
            assert.is_true(#addDoubleLineLog >= 2,
                "Expected 2 AddDoubleLine calls (MS + OS)")
            assert.are.equal("GP Cost (OS):", addDoubleLineLog[2].left)

            local osGpStr = addDoubleLineLog[2].right
            local osGpVal = tonumber(osGpStr)
            assert.is_not_nil(osGpVal)
            assert.are.equal(500, osGpVal)  -- OS = 50% of MS

            -- Show should have been called to resize the tooltip
            assert.are.equal(1, showCount)
        end)

        it("uses correct colors for GP lines", function()
            _G.GameTooltip:SetHyperlink(epicHelmLink)

            -- MS line: left=light blue (0.5, 0.8, 1.0), right=white (1.0, 1.0, 1.0)
            local msLine = addDoubleLineLog[1]
            assert.are.equal(0.5, msLine.lr)
            assert.are.equal(0.8, msLine.lg)
            assert.are.equal(1.0, msLine.lb)
            assert.are.equal(1.0, msLine.rr)
            assert.are.equal(1.0, msLine.rg)
            assert.are.equal(1.0, msLine.rb)

            -- OS line: left=light blue, right=grey (0.8, 0.8, 0.8)
            local osLine = addDoubleLineLog[2]
            assert.are.equal(0.5, osLine.lr)
            assert.are.equal(0.8, osLine.lg)
            assert.are.equal(1.0, osLine.lb)
            assert.are.equal(0.8, osLine.rr)
            assert.are.equal(0.8, osLine.rg)
            assert.are.equal(0.8, osLine.rb)
        end)

        it("skips items below quality threshold", function()
            -- Add a Rare item (quality 3) to the test item DB
            _G._testItemDB[99010] = {
                "Rare Test Helm",
                "|cff0070dd|Hitem:99010::::::::70:::::::|h[Rare Test Helm]|h|r",
                3, 115, 70, "Armor", "Plate", 1, "INVTYPE_HEAD", 123499, 0,
            }

            _G.GameTooltip:SetHyperlink(_G._testItemDB[99010][2])

            -- No lines should have been added (quality 3 < threshold 4)
            assert.are.equal(0, #addLineLog)
            assert.are.equal(0, #addDoubleLineLog)
            assert.are.equal(0, showCount)

            -- Clean up
            _G._testItemDB[99010] = nil
        end)

        it("respects show_gp_tooltip config toggle", function()
            -- Disable tooltip GP display
            SimpleEPGP.db.profile.show_gp_tooltip = false

            _G.GameTooltip:SetHyperlink(epicHelmLink)

            -- No lines should have been added
            assert.are.equal(0, #addLineLog)
            assert.are.equal(0, #addDoubleLineLog)
            assert.are.equal(0, showCount)
        end)

        it("prevents duplicate GP lines via gpLineAdded flag", function()
            -- First call: should add GP lines
            _G.GameTooltip:SetHyperlink(epicHelmLink)
            assert.is_true(#addDoubleLineLog >= 1,
                "First call should add GP lines")
            local firstCallLines = #addDoubleLineLog

            -- Second call without clearing: should NOT add more lines
            _G.GameTooltip:SetHyperlink(epicShoulderLink)
            assert.are.equal(firstCallLines, #addDoubleLineLog,
                "Second call should not add duplicate GP lines")
        end)

        it("returns early for nil itemLink", function()
            _G.GameTooltip:SetHyperlink(nil)
            assert.are.equal(0, #addLineLog)
            assert.are.equal(0, #addDoubleLineLog)
            assert.are.equal(0, showCount)
        end)

        it("returns early when db is not available", function()
            local savedDb = SimpleEPGP.db
            SimpleEPGP.db = nil

            _G.GameTooltip:SetHyperlink(epicHelmLink)
            assert.are.equal(0, #addLineLog)
            assert.are.equal(0, #addDoubleLineLog)

            SimpleEPGP.db = savedDb
        end)
    end)

    describe("OnTooltipCleared", function()
        it("resets the gpLineAdded flag", function()
            -- First call: adds GP lines and sets gpLineAdded = true
            _G.GameTooltip:SetHyperlink(epicHelmLink)
            assert.is_true(#addDoubleLineLog >= 1,
                "First call should add GP lines")

            -- Second call without clearing: blocked by gpLineAdded
            resetSpies()
            _G.GameTooltip:SetHyperlink(epicShoulderLink)
            assert.are.equal(0, #addDoubleLineLog,
                "Should be blocked by gpLineAdded flag")

            -- Fire OnTooltipCleared to reset the flag
            fireOnTooltipCleared()

            -- Third call after clearing: should add GP lines again
            _G.GameTooltip:SetHyperlink(epicShoulderLink)
            assert.is_true(#addDoubleLineLog >= 1,
                "After OnTooltipCleared, GP lines should be added again")
            assert.are.equal("GP Cost (MS):", addDoubleLineLog[1].left)
        end)

        it("allows new GP lines after tooltip is cleared and re-shown", function()
            -- Show GP for helm
            _G.GameTooltip:SetHyperlink(epicHelmLink)
            local helmGP = addDoubleLineLog[1].right

            -- Clear and reset
            fireOnTooltipCleared()
            resetSpies()

            -- Show GP for shoulder (different GP value due to slot multiplier)
            _G.GameTooltip:SetHyperlink(epicShoulderLink)
            assert.is_true(#addDoubleLineLog >= 1)
            local shoulderGP = addDoubleLineLog[1].right

            -- Shoulder (0.75 mult) should have different GP than helm (1.0 mult)
            assert.are_not.equal(helmGP, shoulderGP,
                "Different items should show different GP values")
        end)
    end)
end)
