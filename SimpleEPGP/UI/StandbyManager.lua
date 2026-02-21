-----------------------------------------------------------------------
-- StandbyManager.lua -- UI panel for managing the standby list
-- Shows current standby members with add/remove functionality
-----------------------------------------------------------------------
local SimpleEPGP = LibStub("AceAddon-3.0"):GetAddon("SimpleEPGP")
local StandbyManager = SimpleEPGP:NewModule("StandbyManager", "AceEvent-3.0")

local ipairs = ipairs
local tinsert = table.insert
local tremove = table.remove

-- Constants
local FRAME_WIDTH = 300
local FRAME_HEIGHT = 400
local ROW_HEIGHT = 20
local HEADER_HEIGHT = 70
local MAX_VISIBLE_ROWS = 14

-- State
local frame
local rows = {}
local scrollOffset = 0

--------------------------------------------------------------------------------
-- Data helpers
--------------------------------------------------------------------------------

--- Get the standby list from the addon database.
-- @return table Array of player name strings.
local function GetStandbyList()
    if not SimpleEPGP.db then return {} end
    if not SimpleEPGP.db.standby then
        SimpleEPGP.db.standby = {}
    end
    return SimpleEPGP.db.standby
end

--- Add a name to the standby list (with duplicate check).
-- @param name string Player name to add.
-- @return boolean True if added, false if duplicate or empty.
local function AddToStandby(name)
    if not name or name == "" then return false end
    local list = GetStandbyList()
    for _, v in ipairs(list) do
        if v == name then
            SimpleEPGP:Print(name .. " is already on the standby list.")
            return false
        end
    end
    list[#list + 1] = name
    SimpleEPGP:Print(name .. " added to standby list.")
    return true
end

--- Remove a name from the standby list.
-- @param name string Player name to remove.
-- @return boolean True if removed, false if not found.
local function RemoveFromStandby(name)
    local list = GetStandbyList()
    for i, v in ipairs(list) do
        if v == name then
            tremove(list, i)
            SimpleEPGP:Print(name .. " removed from standby list.")
            return true
        end
    end
    return false
end

--- Clear the entire standby list.
-- @return number Count of removed names.
local function ClearStandby()
    local list = GetStandbyList()
    local count = #list
    -- Wipe by reassigning (same pattern as Core.lua CmdStandby)
    SimpleEPGP.db.standby = {}
    SimpleEPGP:Print("Standby list cleared (" .. count .. " names removed).")
    return count
end

--------------------------------------------------------------------------------
-- Row creation
--------------------------------------------------------------------------------

local function CreateRow(parent, index)
    local row = CreateFrame("Frame", nil, parent)
    row:SetSize(FRAME_WIDTH - 40, ROW_HEIGHT)
    row:SetPoint("TOPLEFT", parent, "TOPLEFT", 10, -((index - 1) * ROW_HEIGHT))

    -- Alternating row background
    if index % 2 == 0 then
        local bg = row:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints()
        bg:SetColorTexture(1, 1, 1, 0.03)
    end

    -- Player name
    row.nameText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.nameText:SetPoint("LEFT", row, "LEFT", 5, 0)
    row.nameText:SetWidth(180)
    row.nameText:SetJustifyH("LEFT")
    row.nameText:SetHeight(ROW_HEIGHT)

    -- Remove button
    row.removeBtn = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
    row.removeBtn:SetSize(60, 18)
    row.removeBtn:SetPoint("RIGHT", row, "RIGHT", -5, 0)
    row.removeBtn:SetText("Remove")

    return row
end

--------------------------------------------------------------------------------
-- Display update
--------------------------------------------------------------------------------

local function RefreshDisplay()
    if not frame or not frame:IsShown() then return end

    local list = GetStandbyList()
    local total = #list

    -- Update count label
    if frame.countLabel then
        frame.countLabel:SetText("Standby: " .. total .. " player" .. (total == 1 and "" or "s"))
    end

    -- Update scroll bar range
    local maxScroll = math.max(0, total - MAX_VISIBLE_ROWS)
    frame.scrollBar:SetMinMaxValues(0, maxScroll)
    if scrollOffset > maxScroll then
        scrollOffset = maxScroll
        frame.scrollBar:SetValue(scrollOffset)
    end

    -- Update rows
    for i = 1, MAX_VISIBLE_ROWS do
        local row = rows[i]
        local dataIndex = i + scrollOffset

        if dataIndex <= total then
            local name = list[dataIndex]
            row:Show()
            row.nameText:SetText(dataIndex .. ". " .. name)

            -- Wire up remove button for this entry
            row.removeBtn:SetScript("OnClick", function()
                RemoveFromStandby(name)
                RefreshDisplay()
            end)
        else
            row:Hide()
        end
    end
end

--------------------------------------------------------------------------------
-- Frame creation (lazy, one-time)
--------------------------------------------------------------------------------

local function CreateFrame_()
    frame = CreateFrame("Frame", "SimpleEPGPStandbyFrame", UIParent, "BackdropTemplate")
    frame:SetSize(FRAME_WIDTH, FRAME_HEIGHT)
    frame:SetPoint("CENTER")
    frame:SetFrameStrata("DIALOG")
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
    title:SetText("Standby List")

    -- Close button
    local closeBtn = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    closeBtn:SetPoint("TOPRIGHT", -2, -2)
    closeBtn:SetScript("OnClick", function() StandbyManager:Hide() end)

    -- Count label
    frame.countLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    frame.countLabel:SetPoint("TOPLEFT", 15, -30)
    frame.countLabel:SetTextColor(0.8, 0.8, 0.8)

    -- Add player input row
    local addLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    addLabel:SetPoint("TOPLEFT", 15, -48)
    addLabel:SetText("Add:")

    local addBox = CreateFrame("EditBox", nil, frame, "InputBoxTemplate")
    addBox:SetSize(140, 20)
    addBox:SetPoint("LEFT", addLabel, "RIGHT", 8, 0)
    addBox:SetAutoFocus(false)
    addBox:SetMaxLetters(40)
    frame.addBox = addBox

    local addBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    addBtn:SetSize(60, 22)
    addBtn:SetPoint("LEFT", addBox, "RIGHT", 4, 0)
    addBtn:SetText("Add")
    addBtn:SetScript("OnClick", function()
        local text = addBox:GetText()
        if text and text ~= "" then
            AddToStandby(text)
            addBox:SetText("")
            RefreshDisplay()
        end
    end)

    -- Enter key in the edit box also adds
    addBox:SetScript("OnEnterPressed", function(self)
        local text = self:GetText()
        if text and text ~= "" then
            AddToStandby(text)
            self:SetText("")
            RefreshDisplay()
        end
        self:ClearFocus()
    end)
    addBox:SetScript("OnEscapePressed", function(self)
        self:ClearFocus()
    end)

    -- Clear all button
    local clearBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    clearBtn:SetSize(80, 22)
    clearBtn:SetPoint("BOTTOMLEFT", 12, 12)
    clearBtn:SetText("Clear All")
    clearBtn:SetScript("OnClick", function()
        ClearStandby()
        RefreshDisplay()
    end)

    -- Row container (below header area)
    local rowContainer = CreateFrame("Frame", nil, frame)
    rowContainer:SetPoint("TOPLEFT", 8, -HEADER_HEIGHT)
    rowContainer:SetPoint("BOTTOMRIGHT", -28, 40)

    -- Create row frames
    for i = 1, MAX_VISIBLE_ROWS do
        rows[i] = CreateRow(rowContainer, i)
    end

    -- Scroll bar
    local scrollBar = CreateFrame("Slider", "SimpleEPGPStandbyScrollBar", frame)
    scrollBar:SetPoint("TOPRIGHT", -10, -HEADER_HEIGHT)
    scrollBar:SetPoint("BOTTOMRIGHT", -10, 40)
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

    scrollBar:SetScript("OnValueChanged", function(_, value)
        scrollOffset = math.floor(value)
        RefreshDisplay()
    end)
    frame.scrollBar = scrollBar

    -- Mouse wheel scrolling
    frame:EnableMouseWheel(true)
    frame:SetScript("OnMouseWheel", function(_, delta)
        local current = scrollBar:GetValue()
        scrollBar:SetValue(current - delta * 3)
    end)

    -- Escape to close
    tinsert(UISpecialFrames, "SimpleEPGPStandbyFrame")

    frame:Hide()
end

--------------------------------------------------------------------------------
-- Module API: Show / Hide / Toggle
--------------------------------------------------------------------------------

function StandbyManager:Show()
    if not frame then
        CreateFrame_()
    end
    scrollOffset = 0
    frame:Show()
    RefreshDisplay()
end

function StandbyManager:Hide()
    if frame then
        frame:Hide()
    end
end

function StandbyManager:Toggle()
    if frame and frame:IsShown() then
        self:Hide()
    else
        self:Show()
    end
end

--------------------------------------------------------------------------------
-- Test helpers
--------------------------------------------------------------------------------

--- Get the current standby list for testing.
-- @return table Array of player name strings.
function StandbyManager:GetStandbyList()
    return GetStandbyList()
end

--- Expose AddToStandby for testing.
-- @param name string Player name.
-- @return boolean True if added.
function StandbyManager:Add(name)
    local result = AddToStandby(name)
    RefreshDisplay()
    return result
end

--- Expose RemoveFromStandby for testing.
-- @param name string Player name.
-- @return boolean True if removed.
function StandbyManager:Remove(name)
    local result = RemoveFromStandby(name)
    RefreshDisplay()
    return result
end

--- Expose ClearStandby for testing.
-- @return number Count of removed names.
function StandbyManager:Clear()
    local result = ClearStandby()
    RefreshDisplay()
    return result
end

--------------------------------------------------------------------------------
-- Module Lifecycle
--------------------------------------------------------------------------------

function StandbyManager:OnEnable()
    -- Refresh display when standby list changes externally
    -- (e.g., via slash commands or other modules)
    self:RegisterMessage("SEPGP_STANDBY_UPDATED", function()
        RefreshDisplay()
    end)
end
