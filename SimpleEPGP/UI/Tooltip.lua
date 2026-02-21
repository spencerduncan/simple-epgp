local SimpleEPGP = LibStub("AceAddon-3.0"):GetAddon("SimpleEPGP")
local Tooltip = SimpleEPGP:NewModule("Tooltip")

-- Flag to prevent duplicate GP lines on the same tooltip
local gpLineAdded = false

--- Add GP cost information to a tooltip for an item.
-- @param tooltip GameTooltip frame
-- @param itemLink Item link string (or item:ID format from SetHyperlink)
local function AddGPLine(tooltip, itemLink)
    if not itemLink then return end
    if gpLineAdded then return end

    local db = SimpleEPGP.db
    if not db or not db.profile.show_gp_tooltip then return end

    local GPCalc = SimpleEPGP:GetModule("GPCalc")
    local gpCost = GPCalc:CalculateGP(itemLink)
    if not gpCost then return end

    local osGP = GPCalc:GetBidGP(itemLink, "OS")

    gpLineAdded = true

    tooltip:AddLine(" ")  -- blank separator
    tooltip:AddDoubleLine(
        "GP Cost (MS):", tostring(gpCost),
        0.5, 0.8, 1.0,   -- left color: light blue
        1.0, 1.0, 1.0    -- right color: white
    )
    if osGP then
        tooltip:AddDoubleLine(
            "GP Cost (OS):", tostring(osGP),
            0.5, 0.8, 1.0,
            0.8, 0.8, 0.8
        )
    end
    tooltip:Show()  -- resize tooltip to fit new lines
end

function Tooltip:OnEnable()
    local db = SimpleEPGP.db
    if not db or not db.profile.show_gp_tooltip then return end

    -- Reset duplicate flag whenever a tooltip is cleared
    GameTooltip:HookScript("OnTooltipCleared", function()
        gpLineAdded = false
    end)

    -- Hook SetHyperlink: link arg may be "item:12345:..." format
    hooksecurefunc(GameTooltip, "SetHyperlink", function(tooltip, link)
        AddGPLine(tooltip, link)
    end)

    -- Hook SetBagItem: use GetItem() to retrieve the link after the tooltip is set
    hooksecurefunc(GameTooltip, "SetBagItem", function(tooltip, bag, slot)
        local _, link = tooltip:GetItem()
        AddGPLine(tooltip, link)
    end)

    -- Hook SetLootItem: use GetLootSlotLink for the item link
    hooksecurefunc(GameTooltip, "SetLootItem", function(tooltip, slot)
        local link = GetLootSlotLink(slot)
        AddGPLine(tooltip, link)
    end)

    -- Hook SetInventoryItem: use GetInventoryItemLink for equipped items
    hooksecurefunc(GameTooltip, "SetInventoryItem", function(tooltip, unit, slot)
        local link = GetInventoryItemLink(unit, slot)
        AddGPLine(tooltip, link)
    end)
end

function Tooltip:OnDisable()
    -- hooksecurefunc hooks are permanent; OnDisable just prevents future
    -- lines from being added by relying on the db.profile check in AddGPLine.
end
