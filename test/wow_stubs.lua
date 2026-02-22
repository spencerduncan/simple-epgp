-----------------------------------------------------------------------
-- wow_stubs.lua — Mock WoW API for busted unit tests
-- Load with: require("test.wow_stubs")
-- Must be loaded BEFORE ace_stubs.lua
-----------------------------------------------------------------------

-----------------------------------------------------------------------
-- Frame API
-----------------------------------------------------------------------

function CreateFrame(frameType, name, parent, template)
    local frame = {
        _type = frameType,
        _name = name,
        _visible = false,
        _scripts = {},
        _children = {},
        -- Position/size
        SetPoint = function() end,
        ClearAllPoints = function() end,
        SetSize = function() end,
        SetWidth = function() end,
        SetHeight = function() end,
        GetWidth = function() return 400 end,
        GetHeight = function() return 300 end,
        -- Visibility
        Show = function(self) self._visible = true end,
        Hide = function(self) self._visible = false end,
        IsShown = function(self) return self._visible or false end,
        SetShown = function(self, v) self._visible = v end,
        -- Text (for FontStrings)
        SetText = function() end,
        GetText = function() return "" end,
        SetTextColor = function() end,
        SetJustifyH = function() end,
        SetJustifyV = function() end,
        SetFont = function() end,
        SetWordWrap = function() end,
        -- Scripts
        SetScript = function(self, event, handler)
            self._scripts[event] = handler
        end,
        GetScript = function(self, event)
            return self._scripts[event]
        end,
        -- Backdrop
        SetBackdrop = function() end,
        SetBackdropColor = function() end,
        SetBackdropBorderColor = function() end,
        -- Misc frame
        SetMovable = function() end,
        EnableMouse = function() end,
        RegisterForDrag = function() end,
        SetClampedToScreen = function() end,
        SetFrameStrata = function() end,
        SetFrameLevel = function() end,
        CreateFontString = function()
            return CreateFrame("FontString")
        end,
        CreateTexture = function()
            return {
                SetTexture = function() end,
                SetTexCoord = function() end,
                SetPoint = function() end,
                SetSize = function() end,
                SetHeight = function() end,
                SetWidth = function() end,
                SetAllPoints = function() end,
                SetColorTexture = function() end,
                SetBlendMode = function() end,
                SetVertexColor = function() end,
                Show = function(self) self._visible = true end,
                Hide = function(self) self._visible = false end,
                SetShown = function(self, v) self._visible = v end,
                IsShown = function(self) return self._visible or false end,
                SetAlpha = function() end,
            }
        end,
        -- Parent
        SetParent = function() end,
        GetParent = function() return _G.UIParent end,
        -- Alpha
        SetAlpha = function() end,
        GetAlpha = function() return 1 end,
        -- Scrolling (ScrollFrame)
        SetScrollChild = function() end,
        SetVerticalScroll = function() end,
        GetVerticalScroll = function() return 0 end,
        -- EditBox
        SetMultiLine = function() end,
        SetMaxLetters = function() end,
        SetAutoFocus = function() end,
        SetFocus = function() end,
        ClearFocus = function() end,
        HighlightText = function() end,
        SetNumeric = function() end,
        -- Button
        SetNormalTexture = function() end,
        SetHighlightTexture = function() end,
        SetPushedTexture = function() end,
        SetDisabledTexture = function() end,
        SetEnabled = function() end,
        Enable = function() end,
        Disable = function() end,
        GetFontString = function(self) return self end,
        SetNormalFontObject = function() end,
        SetFontObject = function() end,
        -- Slider / StatusBar
        SetMinMaxValues = function() end,
        SetValue = function() end,
        GetValue = function() return 0 end,
        SetValueStep = function() end,
        SetOrientation = function() end,
        SetObeyStepOnDrag = function() end,
        SetThumbTexture = function() end,
        SetStatusBarTexture = function() end,
        SetStatusBarColor = function() end,
        -- CheckButton
        SetChecked = function(self, val) self._checked = val end,
        GetChecked = function(self) return self._checked or false end,
        -- Mouse wheel
        EnableMouseWheel = function() end,
        -- Dragging
        StartMoving = function() end,
        StopMovingOrSizing = function() end,
    }
    if name then
        _G[name] = frame
    end
    return frame
end
_G.CreateFrame = CreateFrame

-----------------------------------------------------------------------
-- UIParent and common global frames
-----------------------------------------------------------------------

_G.UIParent = CreateFrame("Frame", nil, nil, nil)

_G.GameTooltip = CreateFrame("GameTooltip")
_G.GameTooltip.AddLine = function() end
_G.GameTooltip.AddDoubleLine = function() end
_G.GameTooltip.SetHyperlink = function() end
_G.GameTooltip.ClearLines = function() end

_G.GameFontNormal = {}
_G.GameFontHighlight = {}
_G.GameFontHighlightSmall = {}
_G.GameFontNormalSmall = {}
_G.GameFontNormalLarge = {}
_G.NumberFontNormal = {}
_G.ChatFontNormal = {}

_G.StaticPopupDialogs = {}
_G.StaticPopup_Show = function() end

-----------------------------------------------------------------------
-- Guild Roster
-----------------------------------------------------------------------

local _guildRoster = {
    { name = "Player1-TestRealm", rankName = "Guild Master", rankIndex = 0, level = 70, classDisplayName = "Warrior",  zone = "Shattrath City", publicNote = "", officerNote = "5000,1000",  isOnline = true,  status = 0, class = "WARRIOR", guid = "Player-1" },
    { name = "Player2-TestRealm", rankName = "Officer",      rankIndex = 1, level = 70, classDisplayName = "Paladin",  zone = "Karazhan",       publicNote = "", officerNote = "3000,500",   isOnline = true,  status = 0, class = "PALADIN", guid = "Player-2" },
    { name = "Player3-TestRealm", rankName = "Officer",      rankIndex = 1, level = 70, classDisplayName = "Hunter",   zone = "Gruul's Lair",   publicNote = "", officerNote = "2000,2000",  isOnline = true,  status = 0, class = "HUNTER",  guid = "Player-3" },
    { name = "Player4-TestRealm", rankName = "Raider",       rankIndex = 2, level = 70, classDisplayName = "Mage",     zone = "Orgrimmar",      publicNote = "", officerNote = "1000,100",   isOnline = false, status = 0, class = "MAGE",    guid = "Player-4" },
    { name = "Player5-TestRealm", rankName = "Raider",       rankIndex = 2, level = 70, classDisplayName = "Priest",   zone = "Shattrath City", publicNote = "", officerNote = "",           isOnline = true,  status = 0, class = "PRIEST",  guid = "Player-5" },
}
_G._testGuildRoster = _guildRoster

function GetNumGuildMembers()
    local online = 0
    for _, m in ipairs(_guildRoster) do
        if m.isOnline then online = online + 1 end
    end
    return #_guildRoster, online
end
_G.GetNumGuildMembers = GetNumGuildMembers

function GetGuildRosterInfo(index)
    local m = _guildRoster[index]
    if not m then return nil end
    return m.name, m.rankName, m.rankIndex, m.level, m.classDisplayName,
           m.zone, m.publicNote, m.officerNote, m.isOnline, m.status,
           m.class, nil, nil, nil, nil, nil, m.guid
end
_G.GetGuildRosterInfo = GetGuildRosterInfo

function GuildRoster()
    -- No-op; in real WoW this triggers GUILD_ROSTER_UPDATE
end
_G.GuildRoster = GuildRoster

function GuildRosterSetOfficerNote(index, text)
    if _guildRoster[index] then
        _guildRoster[index].officerNote = text
    end
end
_G.GuildRosterSetOfficerNote = GuildRosterSetOfficerNote

function IsInGuild()
    return true
end
_G.IsInGuild = IsInGuild

function CanEditOfficerNote()
    return true
end
_G.CanEditOfficerNote = CanEditOfficerNote

function CanViewOfficerNote()
    return true
end
_G.CanViewOfficerNote = CanViewOfficerNote

_G.C_GuildInfo = {
    CanEditOfficerNote = function() return true end,
    CanViewOfficerNote = function() return true end,
    GuildRoster = function()
        -- No-op; in real WoW this triggers GUILD_ROSTER_UPDATE
    end,
}

-----------------------------------------------------------------------
-- Item Database
-----------------------------------------------------------------------

-- Each entry: {name, link, quality, ilvl, minLevel, type, subType, stackCount, equipLoc, texture, sellPrice}
local _itemDB = {
    -- HEAD ilvl 120
    [29759]  = { "Helm of the Fallen Champion",  "|cffff8000|Hitem:29759::::::::70:::::::|h[Helm of the Fallen Champion]|h|r",  4, 120, 70, "Armor", "Plate",   1, "INVTYPE_HEAD",     123456, 0 },
    -- SHOULDER ilvl 120
    [29764]  = { "Pauldrons of the Fallen Hero",  "|cffa335ee|Hitem:29764::::::::70:::::::|h[Pauldrons of the Fallen Hero]|h|r", 4, 120, 70, "Armor", "Plate",   1, "INVTYPE_SHOULDER",  123457, 0 },
    -- CHEST ilvl 120
    [29753]  = { "Chestguard of the Fallen Hero","|cffa335ee|Hitem:29753::::::::70:::::::|h[Chestguard of the Fallen Hero]|h|r", 4, 120, 70, "Armor", "Leather", 1, "INVTYPE_CHEST",    123458, 0 },
    -- TRINKET ilvl 115
    [28789]  = { "Eye of Gruul",                  "|cffa335ee|Hitem:28789::::::::70:::::::|h[Eye of Gruul]|h|r",                 4, 115, 70, "Armor", "Misc",    1, "INVTYPE_TRINKET",  123459, 0 },
    -- TRINKET ilvl 128
    [30627]  = { "Tsunami Talisman",              "|cffa335ee|Hitem:30627::::::::70:::::::|h[Tsunami Talisman]|h|r",             4, 128, 70, "Armor", "Misc",    1, "INVTYPE_TRINKET",  123460, 0 },
    -- WEAPON (1H) ilvl 156
    [32837]  = { "Warglaive of Azzinoth",         "|cffff8000|Hitem:32837::::::::70:::::::|h[Warglaive of Azzinoth]|h|r",        5, 156, 70, "Weapon","Sword",   1, "INVTYPE_WEAPON",   123461, 0 },
    -- 2HWEAPON ilvl 141
    [30311]  = { "Pillar of Ferocity",            "|cffa335ee|Hitem:30311::::::::70:::::::|h[Pillar of Ferocity]|h|r",           4, 141, 70, "Weapon","Mace",    1, "INVTYPE_2HWEAPON", 123462, 0 },
}

-- Build link-based lookup as well
local _itemLinkDB = {}
for id, info in pairs(_itemDB) do
    _itemLinkDB[info[2]] = info
    -- Also support lookup by item:ID pattern inside links
    _itemLinkDB[tostring(id)] = info
end

local function LookupItem(itemIdOrLink)
    if type(itemIdOrLink) == "number" then
        return _itemDB[itemIdOrLink]
    end
    if type(itemIdOrLink) == "string" then
        -- Try direct link match
        if _itemLinkDB[itemIdOrLink] then
            return _itemLinkDB[itemIdOrLink]
        end
        -- Try extracting item ID from link
        local id = itemIdOrLink:match("item:(%d+)")
        if id then
            return _itemDB[tonumber(id)]
        end
        -- Try as plain number string
        local numId = tonumber(itemIdOrLink)
        if numId then
            return _itemDB[numId]
        end
    end
    return nil
end

function GetItemInfo(itemIdOrLink)
    local info = LookupItem(itemIdOrLink)
    if not info then return nil end
    return info[1], info[2], info[3], info[4], info[5],
           info[6], info[7], info[8], info[9], info[10], info[11]
end
_G.GetItemInfo = GetItemInfo

function GetItemInfoInstant(itemIdOrLink)
    local info = LookupItem(itemIdOrLink)
    if not info then return nil end
    -- Returns: itemID, itemType, itemSubType, itemEquipLoc, icon, classID, subClassID
    local id = itemIdOrLink
    if type(id) == "string" then
        id = tonumber(id:match("item:(%d+)")) or 0
    end
    return id, info[6], info[7], info[9], info[10], 0, 0
end
_G.GetItemInfoInstant = GetItemInfoInstant

function GetItemQualityColor(quality)
    local colors = {
        [0] = { r = 0.62, g = 0.62, b = 0.62, hex = "ff9d9d9d" },  -- Poor (grey)
        [1] = { r = 1.00, g = 1.00, b = 1.00, hex = "ffffffff" },  -- Common (white)
        [2] = { r = 0.12, g = 1.00, b = 0.00, hex = "ff1eff00" },  -- Uncommon (green)
        [3] = { r = 0.00, g = 0.44, b = 0.87, hex = "ff0070dd" },  -- Rare (blue)
        [4] = { r = 0.64, g = 0.21, b = 0.93, hex = "ffa335ee" },  -- Epic (purple)
        [5] = { r = 1.00, g = 0.50, b = 0.00, hex = "ffff8000" },  -- Legendary (orange)
    }
    local c = colors[quality] or colors[1]
    return c.r, c.g, c.b, c.hex
end
_G.GetItemQualityColor = GetItemQualityColor

-- Expose item DB for test manipulation
_G._testItemDB = _itemDB

-----------------------------------------------------------------------
-- Loot stubs
-----------------------------------------------------------------------

local _lootMethod = "master"
local _lootPartyID = 0
local _lootRaidID = 1

local _lootSlots = {
    { name = "Helm of the Fallen Champion", texture = 123456, quantity = 1, quality = 4, locked = false, isQuestItem = false },
}

function GetLootMethod()
    return _lootMethod, _lootPartyID, _lootRaidID
end
_G.GetLootMethod = GetLootMethod

function GetNumLootItems()
    return #_lootSlots
end
_G.GetNumLootItems = GetNumLootItems

function GetLootSlotInfo(slot)
    local s = _lootSlots[slot]
    if not s then return nil end
    return s.texture, s.name, s.quantity, nil, s.quality, s.locked, s.isQuestItem
end
_G.GetLootSlotInfo = GetLootSlotInfo

function GetLootSlotLink(slot)
    -- Return the link for test item 29759 (Helm) by default
    if slot == 1 then
        return _itemDB[29759][2]
    end
    return nil
end
_G.GetLootSlotLink = GetLootSlotLink

function GetMasterLootCandidate(slot, idx)
    local candidates = { "Player1-TestRealm", "Player2-TestRealm", "Player3-TestRealm" }
    return candidates[idx]
end
_G.GetMasterLootCandidate = GetMasterLootCandidate

function GiveMasterLoot(slot, idx)
    -- No-op in tests
end
_G.GiveMasterLoot = GiveMasterLoot

-- Expose for test manipulation
_G._testLootMethod = function(method, partyID, raidID)
    _lootMethod = method or "master"
    _lootPartyID = partyID or 0
    _lootRaidID = raidID or 1
end

-- C_PartyInfo.GetLootMethod() — TBC Anniversary API (returns Enum.LootMethod integers).
-- In tests the global GetLootMethod exists so the LootMaster.lua shim won't activate,
-- but we stub this for completeness and for testing the shim path if needed.
_G.C_PartyInfo = _G.C_PartyInfo or {}
_G.C_PartyInfo.GetLootMethod = function()
    -- Map string method names to Enum.LootMethod integers
    local METHOD_ENUM = {
        freeforall  = 0, roundrobin = 1, master = 2,
        group       = 3, needbeforegreed = 4, personalloot = 5,
    }
    return METHOD_ENUM[_lootMethod] or 2, _lootPartyID
end

-----------------------------------------------------------------------
-- Raid stubs
-----------------------------------------------------------------------

local _raidRoster = {
    { name = "Player1-TestRealm", rank = 2, subgroup = 1, level = 70, class = "WARRIOR",  fileName = "WARRIOR",  zone = "Karazhan", online = true,  isDead = false, role = "MAINTANK", isML = true  },
    { name = "Player2-TestRealm", rank = 0, subgroup = 1, level = 70, class = "PALADIN",  fileName = "PALADIN",  zone = "Karazhan", online = true,  isDead = false, role = "NONE",     isML = false },
    { name = "Player3-TestRealm", rank = 0, subgroup = 1, level = 70, class = "HUNTER",   fileName = "HUNTER",   zone = "Karazhan", online = true,  isDead = false, role = "NONE",     isML = false },
    { name = "Player4-TestRealm", rank = 0, subgroup = 2, level = 70, class = "MAGE",     fileName = "MAGE",     zone = "Karazhan", online = true,  isDead = false, role = "NONE",     isML = false },
    { name = "Player5-TestRealm", rank = 0, subgroup = 2, level = 70, class = "PRIEST",   fileName = "PRIEST",   zone = "Karazhan", online = true,  isDead = false, role = "NONE",     isML = false },
}
_G._testRaidRoster = _raidRoster

function GetNumGroupMembers()
    return #_raidRoster
end
_G.GetNumGroupMembers = GetNumGroupMembers

function IsInRaid()
    return true
end
_G.IsInRaid = IsInRaid

function IsInGroup()
    return true
end
_G.IsInGroup = IsInGroup

function GetRaidRosterInfo(idx)
    local m = _raidRoster[idx]
    if not m then return nil end
    return m.name, m.rank, m.subgroup, m.level, m.class, m.fileName,
           m.zone, m.online, m.isDead, m.role, m.isML
end
_G.GetRaidRosterInfo = GetRaidRosterInfo

function GetInstanceInfo()
    return "Karazhan", "raid", 3, "10 Player", 10, 0, false, 0, nil, nil
end
_G.GetInstanceInfo = GetInstanceInfo

-----------------------------------------------------------------------
-- Unit stubs
-----------------------------------------------------------------------

function UnitName(unit)
    if unit == "player" then return "Player1", "TestRealm" end
    return nil
end
_G.UnitName = UnitName

function UnitClass(unit)
    if unit == "player" then return "Warrior", "WARRIOR" end
    return nil
end
_G.UnitClass = UnitClass

function UnitLevel(unit)
    if unit == "player" then return 70 end
    return 0
end
_G.UnitLevel = UnitLevel

function UnitGUID(unit)
    if unit == "player" then return "Player-1" end
    return nil
end
_G.UnitGUID = UnitGUID

-----------------------------------------------------------------------
-- Timer stubs
-----------------------------------------------------------------------

-- GetTime returns game time in seconds (float). Tests use os.clock for relative timing.
function GetTime()
    return os.clock()
end
_G.GetTime = GetTime

_G.C_Timer = {
    After = function(seconds, func)
        -- For tests, execute immediately
        func()
    end,
    NewTicker = function(interval, func, iterations)
        -- For tests, execute immediately (once if iterations=1)
        if iterations then
            for i = 1, iterations do func() end
        else
            func()
        end
        return { Cancel = function() end }
    end,
}

function GetLootThreshold()
    return 4  -- Epic by default
end
_G.GetLootThreshold = GetLootThreshold

function GetAddOnMetadata(addon, field)
    if addon == "SimpleEPGP" and field == "Version" then
        return "0.1.0"
    end
    return nil
end
_G.GetAddOnMetadata = GetAddOnMetadata

-----------------------------------------------------------------------
-- Chat / Addon Message stubs
-----------------------------------------------------------------------

_G.C_ChatInfo = {
    RegisterAddonMessagePrefix = function() return true end,
    SendAddonMessage = function() return 0 end,
}

-- Captured chat messages for test verification
-- SendChatMessage(msg, chatType, language, target) — target used for WHISPER
_G._testChatMessages = {}
_G.SendChatMessage = function(text, channel, language, target)
    _G._testChatMessages[#_G._testChatMessages + 1] = {
        text = text,
        channel = channel,
        target = target,
    }
end

-----------------------------------------------------------------------
-- Enum stubs
-----------------------------------------------------------------------

_G.Enum = {
    SendAddonMessageResult = {
        Success = 0,
    },
}

-----------------------------------------------------------------------
-- Constants: Class Colors
-----------------------------------------------------------------------

_G.RAID_CLASS_COLORS = {
    WARRIOR     = { r = 0.78, g = 0.61, b = 0.43, colorStr = "ffc79c6e" },
    PALADIN     = { r = 0.96, g = 0.55, b = 0.73, colorStr = "fff58cba" },
    HUNTER      = { r = 0.67, g = 0.83, b = 0.45, colorStr = "ffabd473" },
    ROGUE       = { r = 1.00, g = 0.96, b = 0.41, colorStr = "fffff569" },
    PRIEST      = { r = 1.00, g = 1.00, b = 1.00, colorStr = "ffffffff" },
    SHAMAN      = { r = 0.00, g = 0.44, b = 0.87, colorStr = "ff0070de" },
    MAGE        = { r = 0.25, g = 0.78, b = 0.92, colorStr = "ff40c7eb" },
    WARLOCK     = { r = 0.53, g = 0.53, b = 0.93, colorStr = "ff8787ed" },
    DRUID       = { r = 1.00, g = 0.49, b = 0.04, colorStr = "ffff7d0a" },
}

-----------------------------------------------------------------------
-- Constants: Item Quality Colors
-----------------------------------------------------------------------

_G.ITEM_QUALITY_COLORS = {
    [0] = { r = 0.62, g = 0.62, b = 0.62, hex = "|cff9d9d9d" },  -- Poor
    [1] = { r = 1.00, g = 1.00, b = 1.00, hex = "|cffffffff" },  -- Common
    [2] = { r = 0.12, g = 1.00, b = 0.00, hex = "|cff1eff00" },  -- Uncommon
    [3] = { r = 0.00, g = 0.44, b = 0.87, hex = "|cff0070dd" },  -- Rare
    [4] = { r = 0.64, g = 0.21, b = 0.93, hex = "|cffa335ee" },  -- Epic
    [5] = { r = 1.00, g = 0.50, b = 0.00, hex = "|cffff8000" },  -- Legendary
}

-----------------------------------------------------------------------
-- Utility functions (WoW global aliases)
-----------------------------------------------------------------------

_G.time   = os.time
_G.date   = os.date
_G.format = string.format

--- WoW's strsplit returns multiple values (not a table).
function strsplit(delimiter, str, limit)
    if not str then return nil end
    local result = {}
    local pat = "(.-)" .. delimiter
    local lastEnd = 1
    local count = 0
    for part, pos in str:gmatch(pat .. "()") do
        count = count + 1
        if limit and count >= limit then
            break
        end
        result[#result + 1] = part
        lastEnd = pos
    end
    result[#result + 1] = str:sub(lastEnd)
    return unpack(result)
end
_G.strsplit = strsplit

--- WoW's strjoin concatenates with a delimiter.
function strjoin(delimiter, ...)
    local parts = {}
    for i = 1, select("#", ...) do
        parts[i] = tostring(select(i, ...))
    end
    return table.concat(parts, delimiter)
end
_G.strjoin = strjoin

_G.tinsert = table.insert
_G.tremove = table.remove

--- WoW's wipe: clear all keys from a table.
function wipe(t)
    for k in pairs(t) do
        t[k] = nil
    end
    return t
end
_G.wipe = wipe

--- hooksecurefunc: post-hook a function on a table or in _G.
function hooksecurefunc(tblOrName, nameOrFunc, funcOrNil)
    local tbl, name, func
    if type(tblOrName) == "table" then
        tbl = tblOrName
        name = nameOrFunc
        func = funcOrNil
    else
        tbl = _G
        name = tblOrName
        func = nameOrFunc
    end
    local orig = tbl[name]
    tbl[name] = function(...)
        local results = { orig(...) }
        func(...)
        return unpack(results)
    end
end
_G.hooksecurefunc = hooksecurefunc

-- Math aliases
_G.floor  = math.floor
_G.ceil   = math.ceil
_G.abs    = math.abs
_G.max    = math.max
_G.min    = math.min
_G.random = math.random

-- String aliases
_G.strtrim = function(str)
    if not str then return "" end
    return str:match("^%s*(.-)%s*$")
end
_G.strsub  = string.sub
_G.strlen  = string.len
_G.strupper = string.upper
_G.strlower = string.lower
_G.strmatch = string.match
_G.strfind  = string.find
_G.strrep   = string.rep
_G.gsub     = string.gsub

-- print is already available in standard Lua; no stub needed.

-----------------------------------------------------------------------
-- Misc WoW globals
-----------------------------------------------------------------------

_G.DEFAULT_CHAT_FRAME = CreateFrame("Frame")
_G.DEFAULT_CHAT_FRAME.AddMessage = function() end

_G.SlashCmdList = {}
_G.hash_SlashCmdList = {}
_G.UISpecialFrames = {}

_G.NORMAL_FONT_COLOR = { r = 1.0, g = 0.82, b = 0 }
_G.HIGHLIGHT_FONT_COLOR = { r = 1.0, g = 1.0, b = 1.0 }
_G.RED_FONT_COLOR = { r = 1.0, g = 0.1, b = 0.1 }
_G.GREEN_FONT_COLOR = { r = 0.1, g = 1.0, b = 0.1 }

_G.UNKNOWN = "Unknown"
_G.NONE = "None"

_G.select = select
_G.type = type
_G.pairs = pairs
_G.ipairs = ipairs
_G.tostring = tostring
_G.tonumber = tonumber
_G.unpack = unpack or table.unpack
_G.pcall = pcall
_G.error = error
_G.setmetatable = setmetatable
_G.getmetatable = getmetatable
_G.rawget = rawget
_G.rawset = rawset
_G.next = next
_G.assert = assert
_G.loadstring = loadstring or load

-----------------------------------------------------------------------
-- C_Item stub (TBC Anniversary)
-----------------------------------------------------------------------

_G.C_Item = {
    RequestLoadItemDataByID = function(itemID)
        -- No-op in tests; in real WoW this triggers GET_ITEM_INFO_RECEIVED
    end,
}

-----------------------------------------------------------------------
-- C_AddOns stub (TBC Anniversary)
-----------------------------------------------------------------------

_G.C_AddOns = {
    GetNumAddOns = function() return 1 end,
    GetAddOnInfo = function(idx)
        if idx == 1 then
            return "SimpleEPGP", "Simple EPGP", "", true, "INSECURE", false
        end
        return nil
    end,
    IsAddOnLoaded = function(nameOrIdx)
        return true
    end,
}
