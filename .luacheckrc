std = "lua51"
max_line_length = false

-- Ace3 uses colon syntax (self:Method) so 'self' is often unused in method bodies
-- Also ignore unused args in general (common in event handlers, callbacks)
ignore = {
    "212",  -- unused argument (self, event args, etc.)
}

-- Don't lint vendored libraries
exclude_files = {
    "SimpleEPGP/Libs/**",
}

globals = {
    "SimpleEPGP",
    "SimpleEPGPDB",
    "SimpleEPGPDebugLog",
    "SLASH_SEPGP1",
    "SLASH_SEPGP2",
    -- Debug.lua fakeraid overrides these globals temporarily
    "IsInRaid",
    "GetNumGroupMembers",
}

read_globals = {
    -- WoW Frame API
    "CreateFrame", "UIParent", "GameTooltip", "GameFontNormal", "GameFontHighlight",
    "GameFontNormalSmall", "GameFontHighlightSmall", "GameFontNormalLarge",
    "BackdropTemplateMixin", "BACKDROP_DIALOG_32_32",
    "StaticPopupDialogs", "StaticPopup_Show",
    "InterfaceOptions_AddCategory",

    -- WoW API Functions
    "GetGuildRosterInfo", "GetNumGuildMembers", "GuildRoster", "GuildRosterSetOfficerNote",
    "CanEditOfficerNote", "CanViewOfficerNote",
    "GetRaidRosterInfo", "IsInGroup",
    "GetLootMethod", "GetNumLootItems", "GetLootSlotInfo", "GetLootSlotLink",
    "GetMasterLootCandidate", "GiveMasterLoot", "GetLootThreshold",
    "GetItemInfo", "GetItemInfoInstant", "GetItemQualityColor",
    "GetInstanceInfo", "GetRealZoneText",
    "UnitName", "UnitClass", "UnitGUID", "UnitIsUnit",
    "SendChatMessage",
    "IsInGuild", "CanEditOfficerNote", "IsGuildLeader",
    "GetAddOnMetadata",

    -- WoW Namespaced APIs
    "C_ChatInfo", "C_GuildInfo", "C_Item", "C_PartyInfo", "C_Timer", "C_AddOns",

    -- WoW Constants and Tables
    "RAID_CLASS_COLORS", "ITEM_QUALITY_COLORS", "LE_ITEM_CLASS_WEAPON",
    "Enum",

    -- WoW Utility
    "time", "date", "format", "strsplit", "strjoin", "tinsert", "tremove", "wipe",
    "hooksecurefunc", "securecall",
    "tContains", "CopyTable",
    "GetTime", "GetInventoryItemLink",

    -- WoW UI Tables
    "UISpecialFrames",

    -- WoW String Utilities (global in WoW Lua)
    "strtrim", "strsub", "strlen", "strupper", "strlower",

    -- Math (global in WoW Lua)
    "floor", "ceil", "abs", "max", "min", "random",
    "math",

    -- Ace3 / Libraries
    "LibStub",
}
