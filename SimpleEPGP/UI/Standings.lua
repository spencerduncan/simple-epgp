local SimpleEPGP = LibStub("AceAddon-3.0"):GetAddon("SimpleEPGP")
local Standings = SimpleEPGP:NewModule("Standings", "AceEvent-3.0")

local ipairs = ipairs
local floor = math.floor
local format = string.format
local sort = table.sort
local RAID_CLASS_COLORS = RAID_CLASS_COLORS

-- Constants
local FRAME_WIDTH = 500
local FRAME_HEIGHT = 400
local ROW_HEIGHT = 16
local HEADER_HEIGHT = 24
local VISIBLE_ROWS = 20

-- Column definitions: {key, label, width, align}
local COLUMNS = {
    { key = "name",  label = "Name",  width = 150, align = "LEFT"   },
    { key = "class", label = "Class", width = 80,  align = "LEFT"   },
    { key = "ep",    label = "EP",    width = 70,  align = "RIGHT"  },
    { key = "gp",    label = "GP",    width = 70,  align = "RIGHT"  },
    { key = "pr",    label = "PR",    width = 80,  align = "RIGHT"  },
}

-- State
local frame
local rows = {}
local sortedData = {}
local sortColumn = "pr"
local sortAscending = false
local scrollOffset = 0
local filterRaidOnly = false

--- Build a set of short names for players currently in the raid.
-- @return table Set of short names (keys) with true values, or empty table if not in a raid.
local function GetRaidMemberNames()
    local names = {}
    if not IsInRaid() then return names end
    local numRaid = GetNumGroupMembers()
    for i = 1, numRaid do
        local name = GetRaidRosterInfo(i)
        if name then
            local shortName = name:match("^([^%-]+)") or name
            names[shortName] = true
        end
    end
    return names
end

local function SortData()
    local EPGP = SimpleEPGP:GetModule("EPGP")
    local raw = EPGP:GetStandings()

    -- Copy into sortedData, applying raid filter if active
    sortedData = {}
    if filterRaidOnly then
        local raidNames = GetRaidMemberNames()
        for i = 1, #raw do
            if raidNames[raw[i].name] then
                sortedData[#sortedData + 1] = raw[i]
            end
        end
    else
        for i = 1, #raw do
            sortedData[i] = raw[i]
        end
    end

    sort(sortedData, function(a, b)
        local va, vb = a[sortColumn], b[sortColumn]
        if va == vb then
            -- Secondary sort: name ascending for stability
            return a.name < b.name
        end
        if sortAscending then
            return va < vb
        else
            return va > vb
        end
    end)
end

local function UpdateRows()
    local db = SimpleEPGP.db
    local minEP = db and db.profile.min_ep or 0
    local totalRows = #sortedData

    for i = 1, VISIBLE_ROWS do
        local row = rows[i]
        local dataIndex = i + scrollOffset

        if dataIndex <= totalRows then
            local entry = sortedData[dataIndex]
            row:Show()

            -- Name colored by class
            local classColor = RAID_CLASS_COLORS[entry.class]
            if classColor then
                row.name:SetText("|c" .. classColor.colorStr .. entry.name .. "|r")
            else
                row.name:SetText(entry.name)
            end

            row.class:SetText(entry.class)
            row.ep:SetText(tostring(entry.ep))
            row.gp:SetText(tostring(entry.gp))
            row.pr:SetText(format("%.2f", entry.pr))

            -- Grey out players below min EP threshold
            if entry.ep < minEP then
                row.name:SetAlpha(0.5)
                row.class:SetAlpha(0.5)
                row.ep:SetAlpha(0.5)
                row.gp:SetAlpha(0.5)
                row.pr:SetAlpha(0.5)
            else
                row.name:SetAlpha(1.0)
                row.class:SetAlpha(1.0)
                row.ep:SetAlpha(1.0)
                row.gp:SetAlpha(1.0)
                row.pr:SetAlpha(1.0)
            end
        else
            row:Hide()
        end
    end
end

local function OnScrollChanged(_, value)
    scrollOffset = floor(value)
    UpdateRows()
end

local function OnHeaderClick(columnKey)
    if sortColumn == columnKey then
        sortAscending = not sortAscending
    else
        sortColumn = columnKey
        -- Default sort direction: descending for numbers, ascending for text
        if columnKey == "name" or columnKey == "class" then
            sortAscending = true
        else
            sortAscending = false
        end
    end
    SortData()
    UpdateRows()
end

local function CreateRow(parent, index)
    local row = CreateFrame("Frame", nil, parent)
    row:SetSize(FRAME_WIDTH - 40, ROW_HEIGHT)
    row:SetPoint("TOPLEFT", parent, "TOPLEFT", 10, -(HEADER_HEIGHT + (index - 1) * ROW_HEIGHT))

    -- Alternating row background
    if index % 2 == 0 then
        local bg = row:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints()
        bg:SetColorTexture(1, 1, 1, 0.03)
    end

    local x = 0
    for _, col in ipairs(COLUMNS) do
        local fs = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        fs:SetPoint(col.align == "RIGHT" and "TOPRIGHT" or "TOPLEFT",
            row, "TOPLEFT",
            col.align == "RIGHT" and (x + col.width - 5) or (x + 5),
            0)
        fs:SetWidth(col.width - 10)
        fs:SetJustifyH(col.align)
        fs:SetHeight(ROW_HEIGHT)
        row[col.key] = fs
        x = x + col.width
    end

    return row
end

local function RefreshDisplay()
    if not frame or not frame:IsShown() then return end

    SortData()

    -- Update scroll bar range
    local maxScroll = math.max(0, #sortedData - VISIBLE_ROWS)
    frame.scrollBar:SetMinMaxValues(0, maxScroll)
    if scrollOffset > maxScroll then
        scrollOffset = maxScroll
        frame.scrollBar:SetValue(scrollOffset)
    end

    UpdateRows()
end

local function CreateFrame_()
    frame = CreateFrame("Frame", "SimpleEPGPStandingsFrame", UIParent, "BackdropTemplate")
    frame:SetSize(FRAME_WIDTH, FRAME_HEIGHT)
    frame:SetPoint("CENTER")
    frame:SetFrameStrata("HIGH")
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
    frame:SetClampedToScreen(true)

    frame:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile = true, tileSize = 32, edgeSize = 32,
        insets = { left = 8, right = 8, top = 8, bottom = 8 },
    })

    -- Title
    local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOP", 0, -12)
    title:SetText("SimpleEPGP Standings")

    -- Close button
    local closeBtn = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    closeBtn:SetPoint("TOPRIGHT", -2, -2)
    closeBtn:SetScript("OnClick", function() Standings:Hide() end)

    -- "Current Raid" filter checkbox
    local raidFilter = CreateFrame("CheckButton", nil, frame, "UICheckButtonTemplate")
    raidFilter:SetPoint("TOPLEFT", 10, -8)
    raidFilter:SetSize(20, 20)
    raidFilter:SetChecked(filterRaidOnly)
    raidFilter:SetScript("OnClick", function(cb)
        filterRaidOnly = cb:IsChecked() or false
        scrollOffset = 0
        RefreshDisplay()
    end)

    local raidFilterLabel = raidFilter:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    raidFilterLabel:SetPoint("LEFT", raidFilter, "RIGHT", 2, 0)
    raidFilterLabel:SetText("Current Raid")
    frame.raidFilter = raidFilter

    -- Content area (below title, above bottom edge)
    local content = CreateFrame("Frame", nil, frame)
    content:SetPoint("TOPLEFT", 8, -30)
    content:SetPoint("BOTTOMRIGHT", -28, 8)

    -- Column headers
    local headerFrame = CreateFrame("Frame", nil, content)
    headerFrame:SetPoint("TOPLEFT")
    headerFrame:SetSize(FRAME_WIDTH - 40, HEADER_HEIGHT)

    local x = 0
    for _, col in ipairs(COLUMNS) do
        local btn = CreateFrame("Button", nil, headerFrame)
        btn:SetSize(col.width, HEADER_HEIGHT)
        btn:SetPoint("TOPLEFT", x, 0)

        local label = btn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        label:SetPoint("LEFT", 5, 0)
        label:SetText(col.label)
        label:SetJustifyH(col.align)

        btn:SetScript("OnClick", function()
            OnHeaderClick(col.key)
        end)

        -- Highlight on hover
        local highlight = btn:CreateTexture(nil, "HIGHLIGHT")
        highlight:SetAllPoints()
        highlight:SetColorTexture(1, 1, 1, 0.1)

        x = x + col.width
    end

    -- Header separator line
    local sep = content:CreateTexture(nil, "ARTWORK")
    sep:SetPoint("TOPLEFT", 0, -HEADER_HEIGHT)
    sep:SetPoint("TOPRIGHT", 0, -HEADER_HEIGHT)
    sep:SetHeight(1)
    sep:SetColorTexture(0.5, 0.5, 0.5, 0.5)

    -- Row container
    local rowContainer = CreateFrame("Frame", nil, content)
    rowContainer:SetPoint("TOPLEFT", 0, -(HEADER_HEIGHT + 1))
    rowContainer:SetPoint("BOTTOMRIGHT")

    -- Create row frames
    for i = 1, VISIBLE_ROWS do
        rows[i] = CreateRow(rowContainer, i)
    end

    -- Scroll bar (plain Slider — no template, avoids UIPanelScrollBarTemplate
    -- which requires a parent ScrollFrame with SetVerticalScroll on modern client)
    local scrollBar = CreateFrame("Slider", "SimpleEPGPStandingsScrollBar", frame)
    scrollBar:SetPoint("TOPRIGHT", -10, -(30 + HEADER_HEIGHT + 4))
    scrollBar:SetPoint("BOTTOMRIGHT", -10, 12)
    scrollBar:SetWidth(12)
    scrollBar:SetOrientation("VERTICAL")
    scrollBar:SetMinMaxValues(0, 1)
    scrollBar:SetValueStep(1)
    scrollBar:SetObeyStepOnDrag(true)
    scrollBar:SetValue(0)

    -- Track background
    local track = scrollBar:CreateTexture(nil, "BACKGROUND")
    track:SetAllPoints()
    track:SetColorTexture(0.1, 0.1, 0.1, 0.3)

    -- Thumb texture
    local thumb = scrollBar:CreateTexture(nil, "OVERLAY")
    thumb:SetSize(12, 40)
    thumb:SetColorTexture(0.5, 0.5, 0.5, 0.6)
    scrollBar:SetThumbTexture(thumb)

    scrollBar:SetScript("OnValueChanged", OnScrollChanged)
    frame.scrollBar = scrollBar

    -- Mouse wheel scrolling on the content area
    frame:EnableMouseWheel(true)
    frame:SetScript("OnMouseWheel", function(_, delta)
        local current = scrollBar:GetValue()
        scrollBar:SetValue(current - delta * 3)
    end)

    -- Escape to close
    table.insert(UISpecialFrames, "SimpleEPGPStandingsFrame")

    frame:Hide()
end

function Standings:OnEnable()
    self:RegisterMessage("SEPGP_STANDINGS_UPDATED", RefreshDisplay)
end

function Standings:Show()
    if not frame then
        CreateFrame_()
    end
    scrollOffset = 0
    frame:Show()
    RefreshDisplay()
end

function Standings:Hide()
    if frame then
        frame:Hide()
    end
end

function Standings:Toggle()
    if frame and frame:IsShown() then
        self:Hide()
    else
        self:Show()
    end
end

--- Set the raid-only filter state.
-- @param enabled boolean Whether to filter to current raid members only.
function Standings:SetRaidFilter(enabled)
    filterRaidOnly = enabled
    if frame and frame.raidFilter then
        frame.raidFilter:SetChecked(enabled)
    end
    scrollOffset = 0
    RefreshDisplay()
end

--- Get the current raid-only filter state.
-- @return boolean Whether the raid filter is active.
function Standings:GetRaidFilter()
    return filterRaidOnly
end

--- Get the current filtered and sorted display data (for testing).
-- @return array of standings entries currently displayed.
function Standings:GetDisplayData()
    return sortedData
end
