local SimpleEPGP = LibStub("AceAddon-3.0"):GetAddon("SimpleEPGP")
local Leaderboard = SimpleEPGP:NewModule("Leaderboard", "AceEvent-3.0")

local format = string.format
local sort = table.sort
local tinsert = table.insert
local RAID_CLASS_COLORS = RAID_CLASS_COLORS
local UnitName = UnitName
local SendChatMessage = SendChatMessage
local floor = math.floor

-- UI state
local frame = nil
local displayRows = {}
local groupHeaders = {}
local activeFilter = "all"  -- "all", "raiders", "online"
local activeGrouping = "none"  -- "none", "class", "role"
local collapsedGroups = {}
local scrollOffset = 0

-- Constants
local FRAME_WIDTH = 400
local FRAME_HEIGHT = 500
local ROW_HEIGHT = 18
local GROUP_HEADER_HEIGHT = 22
local CONTROLS_HEIGHT = 88  -- title + filter buttons + group buttons + column headers
local MAX_VISIBLE_ROWS = 20

-- Role mapping: class token -> primary role group
local CLASS_ROLE = {
    WARRIOR = "Tank",
    PALADIN = "Healer",
    DRUID   = "Healer",
    PRIEST  = "Healer",
    SHAMAN  = "Healer",
    HUNTER  = "DPS",
    ROGUE   = "DPS",
    MAGE    = "DPS",
    WARLOCK = "DPS",
}

-- Display name for class tokens
local CLASS_DISPLAY = {
    WARRIOR = "Warrior",
    PALADIN = "Paladin",
    HUNTER  = "Hunter",
    ROGUE   = "Rogue",
    PRIEST  = "Priest",
    SHAMAN  = "Shaman",
    MAGE    = "Mage",
    WARLOCK = "Warlock",
    DRUID   = "Druid",
}

-- Canonical ordering for role groups
local ROLE_ORDER = { "Tank", "Healer", "DPS" }

-- Canonical ordering for class groups (alphabetical)
local CLASS_ORDER = {
    "DRUID", "HUNTER", "MAGE", "PALADIN", "PRIEST",
    "ROGUE", "SHAMAN", "WARLOCK", "WARRIOR",
}

--------------------------------------------------------------------------------
-- Data
--------------------------------------------------------------------------------

--- Get filtered and sorted standings data.
-- @param filter string "all", "raiders", or "online"
-- @return array of standings entries
local function GetFilteredStandings(filter)
    local EPGP = SimpleEPGP:GetModule("EPGP")
    local standings = EPGP:GetStandings()
    if not standings then return {} end

    local db = SimpleEPGP.db
    local minEP = db.profile.min_ep or 0

    if filter == "all" then
        return standings
    end

    local filtered = {}
    for i = 1, #standings do
        local entry = standings[i]
        if filter == "raiders" then
            if entry.ep >= minEP then
                filtered[#filtered + 1] = entry
            end
        end
        -- "online" filter would require re-querying the guild roster
        -- for isOnline status; for now treat as "all"
    end

    return filtered
end

--------------------------------------------------------------------------------
-- Grouping Logic
--------------------------------------------------------------------------------

--- Get the group key for a standings entry based on the active grouping mode.
-- @param entry table Standings entry with name, class, ep, gp, pr fields
-- @param grouping string "none", "class", or "role"
-- @return string Group key, or nil for no grouping
local function GetGroupKey(entry, grouping)
    if grouping == "class" then
        return entry.class or "UNKNOWN"
    elseif grouping == "role" then
        return CLASS_ROLE[entry.class] or "DPS"
    end
    return nil
end

--- Get the display name for a group key.
-- @param key string Group key (class token or role name)
-- @param grouping string "class" or "role"
-- @return string Human-readable group name
local function GetGroupDisplayName(key, grouping)
    if grouping == "class" then
        return CLASS_DISPLAY[key] or key
    end
    return key
end

--- Build the display items list: a flat array of group headers and player rows.
-- Each item is either {type="header", key=string, displayName=string, count=number}
-- or {type="row", entry=standingsEntry, rank=number}.
-- When a group is collapsed, its player rows are omitted.
-- @param standings array Filtered standings entries sorted by PR descending
-- @param grouping string "none", "class", or "role"
-- @param collapsed table Set of collapsed group keys
-- @return array of display items
local function BuildDisplayItems(standings, grouping, collapsed)
    if grouping == "none" then
        local items = {}
        for i = 1, #standings do
            items[#items + 1] = { type = "row", entry = standings[i], rank = i }
        end
        return items
    end

    -- Group entries
    local groups = {}
    local groupSet = {}
    for i = 1, #standings do
        local entry = standings[i]
        local key = GetGroupKey(entry, grouping)
        if not groupSet[key] then
            groupSet[key] = {}
            groups[#groups + 1] = key
        end
        tinsert(groupSet[key], entry)
    end

    -- Sort groups by canonical order
    local orderMap = {}
    if grouping == "class" then
        for i, v in ipairs(CLASS_ORDER) do
            orderMap[v] = i
        end
    elseif grouping == "role" then
        for i, v in ipairs(ROLE_ORDER) do
            orderMap[v] = i
        end
    end
    sort(groups, function(a, b)
        return (orderMap[a] or 999) < (orderMap[b] or 999)
    end)

    -- Build flat display list
    local items = {}
    for _, key in ipairs(groups) do
        local members = groupSet[key]
        local isCollapsed = collapsed[key] or false
        items[#items + 1] = {
            type = "header",
            key = key,
            displayName = GetGroupDisplayName(key, grouping),
            count = #members,
            collapsed = isCollapsed,
        }
        if not isCollapsed then
            for rank, entry in ipairs(members) do
                items[#items + 1] = { type = "row", entry = entry, rank = rank }
            end
        end
    end

    return items
end

--------------------------------------------------------------------------------
-- Frame Creation (lazy)
--------------------------------------------------------------------------------

local function CreateDataRow(parent)
    local row = CreateFrame("Frame", nil, parent)
    row:SetHeight(ROW_HEIGHT)

    row.rank = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    row.rank:SetPoint("LEFT", row, "LEFT", 0, 0)
    row.rank:SetWidth(30)
    row.rank:SetJustifyH("CENTER")

    row.name = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    row.name:SetPoint("LEFT", row, "LEFT", 35, 0)
    row.name:SetWidth(120)
    row.name:SetJustifyH("LEFT")

    row.ep = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    row.ep:SetPoint("LEFT", row, "LEFT", 160, 0)
    row.ep:SetWidth(65)
    row.ep:SetJustifyH("RIGHT")

    row.gp = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    row.gp:SetPoint("LEFT", row, "LEFT", 230, 0)
    row.gp:SetWidth(65)
    row.gp:SetJustifyH("RIGHT")

    row.pr = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    row.pr:SetPoint("LEFT", row, "LEFT", 300, 0)
    row.pr:SetWidth(70)
    row.pr:SetJustifyH("RIGHT")

    row.highlight = row:CreateTexture(nil, "BACKGROUND")
    row.highlight:SetAllPoints()
    row.highlight:SetColorTexture(1, 1, 1, 0.05)
    row.highlight:Hide()

    row._itemType = "row"
    return row
end

local function CreateGroupHeader(parent)
    local header = CreateFrame("Button", nil, parent)
    header:SetHeight(GROUP_HEADER_HEIGHT)

    header.arrow = header:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    header.arrow:SetPoint("LEFT", header, "LEFT", 4, 0)
    header.arrow:SetWidth(16)
    header.arrow:SetJustifyH("LEFT")

    header.label = header:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    header.label:SetPoint("LEFT", header, "LEFT", 20, 0)
    header.label:SetJustifyH("LEFT")

    header.countText = header:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    header.countText:SetPoint("RIGHT", header, "RIGHT", -8, 0)
    header.countText:SetJustifyH("RIGHT")

    -- Separator line below header
    header.sep = header:CreateTexture(nil, "ARTWORK")
    header.sep:SetPoint("BOTTOMLEFT", header, "BOTTOMLEFT", 0, 0)
    header.sep:SetPoint("BOTTOMRIGHT", header, "BOTTOMRIGHT", 0, 0)
    header.sep:SetHeight(1)
    header.sep:SetColorTexture(0.5, 0.5, 0.5, 0.3)

    -- Highlight on hover
    header.hoverBg = header:CreateTexture(nil, "HIGHLIGHT")
    header.hoverBg:SetAllPoints()
    header.hoverBg:SetColorTexture(1, 1, 1, 0.05)

    header._itemType = "header"
    return header
end

local function CreateFilterButton(parent, label, filterKey, xOffset, yOffset)
    local btn = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    btn:SetSize(90, 22)
    btn:SetPoint("TOPLEFT", parent, "TOPLEFT", xOffset, yOffset)
    btn:SetText(label)
    btn:SetScript("OnClick", function()
        activeFilter = filterKey
        scrollOffset = 0
        Leaderboard:Refresh()
    end)
    return btn
end

local function CreateGroupButton(parent, label, groupKey, xOffset, yOffset)
    local btn = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    btn:SetSize(90, 22)
    btn:SetPoint("TOPLEFT", parent, "TOPLEFT", xOffset, yOffset)
    btn:SetText(label)
    btn:SetScript("OnClick", function()
        activeGrouping = groupKey
        collapsedGroups = {}
        scrollOffset = 0
        Leaderboard:Refresh()
    end)
    return btn
end

local function OnScrollChanged(_, value)
    scrollOffset = floor(value)
    Leaderboard:Refresh()
end

local Utils = SimpleEPGP.UI.Utils

local LEADERBOARD_BACKDROP = {
    bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark",
    edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
    tile = true, tileSize = 32, edgeSize = 32,
    insets = { left = 8, right = 8, top = 8, bottom = 8 },
}

local function CreateLeaderboardFrame()
    local f = Utils.CreateStandardFrame({
        name = "SimpleEPGPLeaderboard",
        width = FRAME_WIDTH,
        height = FRAME_HEIGHT,
        title = "SimpleEPGP Leaderboard",
        titleFont = "GameFontNormalLarge",
        backdrop = LEADERBOARD_BACKDROP,
    })

    -- Filter buttons (row 1)
    f.btnAll = CreateFilterButton(f, "All Members", "all", 12, -30)
    f.btnRaiders = CreateFilterButton(f, "Raiders Only", "raiders", 108, -30)
    f.btnOnline = CreateFilterButton(f, "Online Only", "online", 204, -30)

    -- Group buttons (row 2)
    f.btnGroupNone = CreateGroupButton(f, "No Groups", "none", 12, -54)
    f.btnGroupClass = CreateGroupButton(f, "By Class", "class", 108, -54)
    f.btnGroupRole = CreateGroupButton(f, "By Role", "role", 204, -54)

    -- Column headers
    local headerY = -(CONTROLS_HEIGHT - 4)
    local headerFont = "GameFontNormalSmall"

    local hRank = f:CreateFontString(nil, "OVERLAY", headerFont)
    hRank:SetPoint("TOPLEFT", f, "TOPLEFT", 8, headerY)
    hRank:SetWidth(30)
    hRank:SetJustifyH("CENTER")
    hRank:SetText("#")
    hRank:SetTextColor(0.8, 0.8, 0.0)

    local hName = f:CreateFontString(nil, "OVERLAY", headerFont)
    hName:SetPoint("TOPLEFT", f, "TOPLEFT", 43, headerY)
    hName:SetText("Name")
    hName:SetTextColor(0.8, 0.8, 0.0)

    local hEP = f:CreateFontString(nil, "OVERLAY", headerFont)
    hEP:SetPoint("TOPLEFT", f, "TOPLEFT", 168, headerY)
    hEP:SetWidth(65)
    hEP:SetJustifyH("RIGHT")
    hEP:SetText("EP")
    hEP:SetTextColor(0.8, 0.8, 0.0)

    local hGP = f:CreateFontString(nil, "OVERLAY", headerFont)
    hGP:SetPoint("TOPLEFT", f, "TOPLEFT", 238, headerY)
    hGP:SetWidth(65)
    hGP:SetJustifyH("RIGHT")
    hGP:SetText("GP")
    hGP:SetTextColor(0.8, 0.8, 0.0)

    local hPR = f:CreateFontString(nil, "OVERLAY", headerFont)
    hPR:SetPoint("TOPLEFT", f, "TOPLEFT", 308, headerY)
    hPR:SetWidth(70)
    hPR:SetJustifyH("RIGHT")
    hPR:SetText("PR")
    hPR:SetTextColor(0.8, 0.8, 0.0)

    -- Create row and header frame pools
    for i = 1, MAX_VISIBLE_ROWS do
        local row = CreateDataRow(f)
        displayRows[i] = row
    end
    for i = 1, 10 do
        local header = CreateGroupHeader(f)
        groupHeaders[i] = header
    end

    -- Scroll bar (plain Slider, same pattern as Standings.lua)
    local scrollBar = Utils.CreateScrollbar({
        parent = f,
        name = "SimpleEPGPLeaderboardScrollBar",
        topOffset = -(CONTROLS_HEIGHT + 4),
        bottomOffset = 12,
        onChange = OnScrollChanged,
    })
    f.scrollBar = scrollBar

    -- Mouse wheel scrolling
    Utils.EnableMouseWheelScroll(f, scrollBar)

    return f
end

--------------------------------------------------------------------------------
-- Refresh Display
--------------------------------------------------------------------------------

function Leaderboard:Refresh()
    if not frame or not frame:IsShown() then return end

    local standings = GetFilteredStandings(activeFilter)
    local playerName = UnitName("player")
    local items = BuildDisplayItems(standings, activeGrouping, collapsedGroups)

    -- Update scroll bar range
    local maxScroll = math.max(0, #items - MAX_VISIBLE_ROWS)
    frame.scrollBar:SetMinMaxValues(0, maxScroll)
    if scrollOffset > maxScroll then
        scrollOffset = maxScroll
        frame.scrollBar:SetValue(scrollOffset)
    end

    -- Hide all display elements first
    for i = 1, MAX_VISIBLE_ROWS do
        displayRows[i]:Hide()
    end
    for i = 1, #groupHeaders do
        groupHeaders[i]:Hide()
    end

    -- Lay out visible items
    local rowIdx = 0
    local headerIdx = 0
    local yPos = 0

    for i = scrollOffset + 1, math.min(#items, scrollOffset + MAX_VISIBLE_ROWS) do
        local item = items[i]

        if item.type == "header" then
            headerIdx = headerIdx + 1
            local header = groupHeaders[headerIdx]
            if not header then
                -- Create more headers if needed
                header = CreateGroupHeader(frame)
                groupHeaders[headerIdx] = header
            end

            header:ClearAllPoints()
            header:SetPoint("TOPLEFT", frame, "TOPLEFT", 8, -(CONTROLS_HEIGHT + yPos))
            header:SetPoint("RIGHT", frame, "RIGHT", -24, 0)

            -- Arrow indicator for collapse state
            if item.collapsed then
                header.arrow:SetText("+")
            else
                header.arrow:SetText("-")
            end

            -- Group name with class color if applicable
            local displayName = item.displayName
            if activeGrouping == "class" then
                local classColor = RAID_CLASS_COLORS[item.key]
                if classColor then
                    header.label:SetTextColor(classColor.r, classColor.g, classColor.b)
                else
                    header.label:SetTextColor(1.0, 0.82, 0.0)
                end
            else
                header.label:SetTextColor(1.0, 0.82, 0.0)
            end
            header.label:SetText(displayName)

            -- Member count
            header.countText:SetText("(" .. item.count .. ")")
            header.countText:SetTextColor(0.7, 0.7, 0.7)

            -- Click handler for collapse/expand
            local groupKey = item.key
            header:SetScript("OnClick", function()
                collapsedGroups[groupKey] = not collapsedGroups[groupKey]
                scrollOffset = 0
                Leaderboard:Refresh()
            end)

            header:Show()
            yPos = yPos + GROUP_HEADER_HEIGHT

        elseif item.type == "row" then
            rowIdx = rowIdx + 1
            local row = displayRows[rowIdx]
            if not row then
                row = CreateDataRow(frame)
                displayRows[rowIdx] = row
            end

            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", frame, "TOPLEFT", 8, -(CONTROLS_HEIGHT + yPos))
            row:SetPoint("RIGHT", frame, "RIGHT", -24, 0)

            local entry = item.entry
            local rank = item.rank

            -- Rank display: medals for top 3 (only in flat mode)
            if activeGrouping == "none" then
                if rank == 1 then
                    row.rank:SetText("#1")
                    row.rank:SetTextColor(1.0, 0.84, 0.0)
                elseif rank == 2 then
                    row.rank:SetText("#2")
                    row.rank:SetTextColor(0.75, 0.75, 0.75)
                elseif rank == 3 then
                    row.rank:SetText("#3")
                    row.rank:SetTextColor(0.80, 0.50, 0.20)
                else
                    row.rank:SetText(tostring(rank))
                    row.rank:SetTextColor(0.8, 0.8, 0.8)
                end
            else
                row.rank:SetText(tostring(rank))
                row.rank:SetTextColor(0.8, 0.8, 0.8)
            end

            -- Class-colored name, with external player indicator
            local displayName = entry.name
            if entry.isExternal then
                displayName = displayName .. " *"
            end
            local classColor = RAID_CLASS_COLORS[entry.class]
            if classColor then
                row.name:SetTextColor(classColor.r, classColor.g, classColor.b)
            else
                row.name:SetTextColor(1, 1, 1)
            end
            row.name:SetText(displayName)

            -- EP, GP, PR
            row.ep:SetText(tostring(entry.ep))
            row.ep:SetTextColor(1, 1, 1)

            row.gp:SetText(tostring(entry.gp))
            row.gp:SetTextColor(1, 1, 1)

            row.pr:SetText(format("%.2f", entry.pr))
            row.pr:SetTextColor(0.5, 1.0, 0.5)

            -- Highlight current player
            if entry.name == playerName then
                row.highlight:SetColorTexture(0.3, 0.5, 1.0, 0.15)
                row.highlight:Show()
            else
                row.highlight:Hide()
            end

            -- Slightly reduce alpha for external players
            local rowAlpha = entry.isExternal and 0.8 or 1.0
            row:SetAlpha(rowAlpha)

            row:Show()
            yPos = yPos + ROW_HEIGHT
        end
    end
end

--------------------------------------------------------------------------------
-- Show / Hide / Toggle
--------------------------------------------------------------------------------

function Leaderboard:Show()
    if not frame then
        frame = CreateLeaderboardFrame()
    end
    frame:Show()
    self:Refresh()
end

function Leaderboard:Hide()
    if frame then
        frame:Hide()
    end
end

function Leaderboard:Toggle()
    if frame and frame:IsShown() then
        self:Hide()
    else
        self:Show()
    end
end

--------------------------------------------------------------------------------
-- Chat Announce
--------------------------------------------------------------------------------

--- Announce top N players to a chat channel.
-- @param count Number of players to announce (default 5)
-- @param channel Chat channel type (default "GUILD")
function Leaderboard:AnnounceTop(count, channel)
    count = count or 5
    channel = channel or "GUILD"

    local EPGP = SimpleEPGP:GetModule("EPGP")
    local standings = EPGP:GetStandings()
    if not standings or #standings == 0 then
        SimpleEPGP:Print("No standings data available.")
        return
    end

    local db = SimpleEPGP.db
    local minEP = db.profile.min_ep or 0

    -- Filter to raiders (above min_ep) for announce
    local eligible = {}
    for i = 1, #standings do
        local entry = standings[i]
        if entry.ep >= minEP then
            eligible[#eligible + 1] = entry
        end
        if #eligible >= count then break end
    end

    if #eligible == 0 then
        SimpleEPGP:Print("No eligible players to announce.")
        return
    end

    SendChatMessage(format("=== SimpleEPGP Top %d ===", #eligible), channel)
    for i = 1, #eligible do
        local e = eligible[i]
        local line = format("#%d. %s - PR: %.2f (EP: %d / GP: %d)",
            i, e.name, e.pr, e.ep, e.gp)
        SendChatMessage(line, channel)
    end
end

--------------------------------------------------------------------------------
-- Accessors (for testing and external use)
--------------------------------------------------------------------------------

--- Get the current active grouping mode.
-- @return string "none", "class", or "role"
function Leaderboard:GetGrouping()
    return activeGrouping
end

--- Set the grouping mode.
-- @param mode string "none", "class", or "role"
function Leaderboard:SetGrouping(mode)
    if mode == "none" or mode == "class" or mode == "role" then
        activeGrouping = mode
        collapsedGroups = {}
        scrollOffset = 0
        self:Refresh()
    end
end

--- Get the collapsed state of a group.
-- @param groupKey string The group key (class token or role name)
-- @return boolean True if the group is collapsed
function Leaderboard:IsGroupCollapsed(groupKey)
    return collapsedGroups[groupKey] or false
end

--- Set the collapsed state of a group.
-- @param groupKey string The group key
-- @param collapsed boolean True to collapse, false to expand
function Leaderboard:SetGroupCollapsed(groupKey, collapsed)
    collapsedGroups[groupKey] = collapsed or nil
    self:Refresh()
end

--- Get the current display items (for testing).
-- @return array of display items ({type, ...})
function Leaderboard:GetDisplayItems()
    local standings = GetFilteredStandings(activeFilter)
    return BuildDisplayItems(standings, activeGrouping, collapsedGroups)
end

--- Get the current active filter.
-- @return string "all", "raiders", or "online"
function Leaderboard:GetFilter()
    return activeFilter
end

--- Set the active filter.
-- @param filter string "all", "raiders", or "online"
function Leaderboard:SetFilter(filter)
    activeFilter = filter or "all"
    scrollOffset = 0
    self:Refresh()
end

--- Get the role mapping table (for testing).
-- @return table mapping class tokens to role names
function Leaderboard:GetClassRoleMap()
    return CLASS_ROLE
end

--- Get the class display name table (for testing).
-- @return table mapping class tokens to display names
function Leaderboard:GetClassDisplayNames()
    return CLASS_DISPLAY
end

--------------------------------------------------------------------------------
-- Module Lifecycle
--------------------------------------------------------------------------------

function Leaderboard:OnEnable()
    -- Auto-refresh when standings change
    self:RegisterMessage("SEPGP_STANDINGS_UPDATED", "Refresh")
end

function Leaderboard:OnDisable()
    self:UnregisterAllMessages()
    self:Hide()
end
