local SimpleEPGP = LibStub("AceAddon-3.0"):GetAddon("SimpleEPGP")
local GPCalc = SimpleEPGP:NewModule("GPCalc")

local floor = math.floor
local tonumber = tonumber
local GetItemInfo = GetItemInfo

-- Default slot multipliers keyed by equipLoc from GetItemInfo.
-- These match the classic EPGP formula weights.
local DEFAULT_SLOT_MULTIPLIERS = {
    INVTYPE_HEAD         = 1.0,
    INVTYPE_CHEST        = 1.0,
    INVTYPE_ROBE         = 1.0,
    INVTYPE_LEGS         = 1.0,
    INVTYPE_SHOULDER     = 0.75,
    INVTYPE_HAND         = 0.75,
    INVTYPE_FEET         = 0.75,
    INVTYPE_WAIST        = 0.75,
    INVTYPE_WRIST        = 0.56,
    INVTYPE_NECK         = 0.56,
    INVTYPE_FINGER       = 0.56,
    INVTYPE_CLOAK        = 0.56,
    INVTYPE_TRINKET      = 1.25,
    INVTYPE_WEAPON       = 1.5,
    INVTYPE_WEAPONMAINHAND = 1.5,
    INVTYPE_2HWEAPON     = 2.0,
    INVTYPE_WEAPONOFFHAND = 0.5,
    INVTYPE_HOLDABLE     = 0.5,
    INVTYPE_SHIELD       = 0.5,
    INVTYPE_RANGED       = 0.5,
    INVTYPE_RANGEDRIGHT  = 0.5,
    INVTYPE_THROWN       = 0.5,
    INVTYPE_RELIC        = 0.667,
    INVTYPE_BODY         = 0,   -- Shirts, not relevant
    INVTYPE_TABARD       = 0,   -- Tabards, not relevant
}

-- Sorted list of slot keys for display order
local SLOT_ORDER = {
    "INVTYPE_HEAD", "INVTYPE_CHEST", "INVTYPE_ROBE", "INVTYPE_LEGS",
    "INVTYPE_SHOULDER", "INVTYPE_HAND", "INVTYPE_FEET", "INVTYPE_WAIST",
    "INVTYPE_WRIST", "INVTYPE_NECK", "INVTYPE_FINGER", "INVTYPE_CLOAK",
    "INVTYPE_TRINKET",
    "INVTYPE_WEAPON", "INVTYPE_WEAPONMAINHAND", "INVTYPE_2HWEAPON",
    "INVTYPE_WEAPONOFFHAND", "INVTYPE_HOLDABLE", "INVTYPE_SHIELD",
    "INVTYPE_RANGED", "INVTYPE_RANGEDRIGHT", "INVTYPE_THROWN",
    "INVTYPE_RELIC",
    "INVTYPE_BODY", "INVTYPE_TABARD",
}

--- Get the base multiplier for the GP formula.
-- If gp_base_multiplier is explicitly set in config, use it.
-- Otherwise derive from standard_ilvl: 1000 * 2^(-standard_ilvl/26).
-- This normalizes GP so that an item at standard_ilvl with slot mult 1.0 = ~1000 GP.
-- @return Base multiplier number.
function GPCalc:GetBaseMultiplier()
    local db = SimpleEPGP.db
    if db.profile.gp_base_multiplier then
        return db.profile.gp_base_multiplier
    end
    local standardIlvl = db.profile.standard_ilvl or 120
    return 1000 * 2 ^ (-standardIlvl / 26)
end

--- Check whether a slot key is a known equipment location.
-- @param equipLoc The INVTYPE_* string.
-- @return true if the slot exists in DEFAULT_SLOT_MULTIPLIERS.
function GPCalc:IsKnownSlot(equipLoc)
    return DEFAULT_SLOT_MULTIPLIERS[equipLoc] ~= nil
end

--- Get the slot multiplier for an equipment location.
-- @param equipLoc The INVTYPE_* string from GetItemInfo.
-- @return Slot multiplier number, or nil if not equippable.
function GPCalc:GetSlotMultiplier(equipLoc)
    if not equipLoc or equipLoc == "" then return nil end
    local db = SimpleEPGP.db
    -- Allow config overrides of individual slot multipliers
    if db.profile.slot_multipliers and db.profile.slot_multipliers[equipLoc] then
        return db.profile.slot_multipliers[equipLoc]
    end
    return DEFAULT_SLOT_MULTIPLIERS[equipLoc]
end

--- Get information about all slots: key, default value, current value, and override status.
-- @return Array of {key, default, current, isOverride} sorted by display order.
function GPCalc:GetAllSlotInfo()
    local db = SimpleEPGP.db
    local overrides = db.profile.slot_multipliers or {}
    local result = {}

    for _, key in ipairs(SLOT_ORDER) do
        local default = DEFAULT_SLOT_MULTIPLIERS[key]
        local override = overrides[key]
        result[#result + 1] = {
            key = key,
            default = default,
            current = override or default,
            isOverride = override ~= nil,
        }
    end

    return result
end

--- Set an override multiplier for a slot.
-- @param equipLoc The INVTYPE_* string.
-- @param value The new multiplier (number).
function GPCalc:SetSlotMultiplier(equipLoc, value)
    if not self:IsKnownSlot(equipLoc) then return false end
    local db = SimpleEPGP.db
    if not db.profile.slot_multipliers then
        db.profile.slot_multipliers = {}
    end
    db.profile.slot_multipliers[equipLoc] = value
    return true
end

--- Remove the override for a slot, reverting to default.
-- @param equipLoc The INVTYPE_* string.
function GPCalc:ResetSlotMultiplier(equipLoc)
    local db = SimpleEPGP.db
    if db.profile.slot_multipliers then
        db.profile.slot_multipliers[equipLoc] = nil
    end
end

--------------------------------------------------------------------------------
-- Item GP Overrides
--------------------------------------------------------------------------------

--- Set a fixed GP cost for a specific item ID.
-- @param itemID number The item ID.
-- @param gpCost number The fixed GP cost.
function GPCalc:SetItemOverride(itemID, gpCost)
    local db = SimpleEPGP.db
    if not db.profile.item_overrides then
        db.profile.item_overrides = {}
    end
    db.profile.item_overrides[itemID] = gpCost
end

--- Remove a fixed GP override for a specific item ID.
-- @param itemID number The item ID.
function GPCalc:ClearItemOverride(itemID)
    local db = SimpleEPGP.db
    if db.profile.item_overrides then
        db.profile.item_overrides[itemID] = nil
    end
end

--- Get all current item overrides.
-- @return Table mapping itemID -> gpCost, or empty table.
function GPCalc:GetAllItemOverrides()
    local db = SimpleEPGP.db
    return db.profile.item_overrides or {}
end

--- Extract the numeric item ID from an item link string.
-- @param itemLink string An item link or plain item ID string.
-- @return number The item ID, or nil if not parseable.
function GPCalc:ParseItemID(itemLink)
    if not itemLink then return nil end
    -- If already a number, return it directly
    if type(itemLink) == "number" then return itemLink end
    -- Try extracting from item link format
    local id = itemLink:match("item:(%d+)")
    if id then return tonumber(id) end
    -- Try as plain number string
    return tonumber(itemLink)
end

--- Calculate the GP cost of an item.
-- Checks item overrides first. If an override exists for the item ID, returns it
-- directly (skips formula, quality check, and slot check).
-- Otherwise uses the formula: floor(0.5 + baseMult * 2^(ilvl/26) * slotMult)
-- @param itemLink A WoW item link string.
-- @return GP cost (integer), or nil if item is not equippable or below quality threshold.
function GPCalc:CalculateGP(itemLink)
    if not itemLink then return nil end

    -- Check for per-item GP override first
    local db = SimpleEPGP.db
    if db.profile.item_overrides then
        local itemID = self:ParseItemID(itemLink)
        if itemID and db.profile.item_overrides[itemID] then
            return db.profile.item_overrides[itemID]
        end
    end

    -- GetItemInfo returns nil for uncached items.
    -- Items in the loot window are always cached; for manual lookups
    -- the caller should request the item and wait for GET_ITEM_INFO_RECEIVED.
    local itemName, _, quality, ilvl, _, _, _, _, equipLoc = GetItemInfo(itemLink)
    if not itemName then return nil end

    local qualityThreshold = db.profile.quality_threshold or 4  -- Epic by default

    if quality < qualityThreshold then return nil end
    if not equipLoc or equipLoc == "" then return nil end

    local slotMult = self:GetSlotMultiplier(equipLoc)
    if not slotMult or slotMult == 0 then return nil end

    local baseMult = self:GetBaseMultiplier()
    local gpCost = floor(0.5 + baseMult * 2 ^ (ilvl / 26) * slotMult)

    local Debug = SimpleEPGP:GetModule("Debug", true)
    if Debug then Debug:Log("EPGP", "CalculateGP", { item = itemName, ilvl = ilvl, slot = equipLoc, gp = gpCost }) end

    return gpCost
end

--- Get the GP cost for a specific bid type.
-- MS/OS/DE multipliers apply on top of item overrides (the override is the MS cost).
-- @param itemLink A WoW item link string.
-- @param bidType One of "MS", "OS", "DE", "PASS".
-- @return GP cost for the bid type, or nil if item is not valid.
function GPCalc:GetBidGP(itemLink, bidType)
    local gpCost = self:CalculateGP(itemLink)
    if not gpCost then return nil end

    if bidType == "PASS" then
        return 0
    end

    local db = SimpleEPGP.db

    if bidType == "OS" then
        local osMult = db.profile.os_multiplier or 0.5
        return floor(gpCost * osMult)
    end

    if bidType == "DE" then
        local deMult = db.profile.de_multiplier or 0
        return floor(gpCost * deMult)
    end

    -- MS (main spec) or any unrecognized type: full GP
    return gpCost
end
