-----------------------------------------------------------------------
-- UI/GPConfig.lua — GP slot multiplier + item override configuration
-- Opened via /sepgp gpconfig
-----------------------------------------------------------------------
local SimpleEPGP = LibStub("AceAddon-3.0"):GetAddon("SimpleEPGP")
local GPConfig = SimpleEPGP:NewModule("GPConfig")

local pairs = pairs
local ipairs = ipairs
local tonumber = tonumber
local tostring = tostring
local floor = math.floor
local format = string.format

-- Constants
local FRAME_WIDTH = 520
local FRAME_HEIGHT = 600
local ROW_HEIGHT = 22
local SLOT_SECTION_HEIGHT = 26 * ROW_HEIGHT + 40  -- 26 slots + header + padding
local OVERRIDE_SECTION_HEIGHT = 300

-- State
local frame
local slotRows = {}
local overrideRows = {}
local addItemIDBox, addGPBox

--------------------------------------------------------------------------------
-- Slot Multiplier Section
--------------------------------------------------------------------------------

local function CreateSlotRow(parent, y, slotInfo)
    local GPCalc = SimpleEPGP:GetModule("GPCalc")
    local row = {}

    -- Slot name label
    local label = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    label:SetPoint("TOPLEFT", 10, y)
    label:SetWidth(180)
    label:SetJustifyH("LEFT")
    label:SetText(slotInfo.key)
    row.label = label

    -- Default value (dimmed)
    local defaultLabel = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    defaultLabel:SetPoint("TOPLEFT", 195, y)
    defaultLabel:SetWidth(50)
    defaultLabel:SetJustifyH("RIGHT")
    defaultLabel:SetText(format("%.3f", slotInfo.default))
    defaultLabel:SetTextColor(0.5, 0.5, 0.5)
    row.defaultLabel = defaultLabel

    -- Current value EditBox
    local editBox = CreateFrame("EditBox", nil, parent, "InputBoxTemplate")
    editBox:SetSize(60, 18)
    editBox:SetPoint("TOPLEFT", 260, y + 2)
    editBox:SetAutoFocus(false)
    editBox:SetMaxLetters(8)
    editBox:SetText(format("%.3f", slotInfo.current))
    editBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    editBox:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    row.editBox = editBox
    row.slotKey = slotInfo.key

    -- Override indicator
    if slotInfo.isOverride then
        editBox:SetTextColor(0.0, 1.0, 0.0)
    end

    -- Reset button
    local resetBtn = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    resetBtn:SetSize(50, 18)
    resetBtn:SetPoint("TOPLEFT", 330, y + 2)
    resetBtn:SetText("Reset")
    resetBtn:SetScript("OnClick", function()
        GPCalc:ResetSlotMultiplier(slotInfo.key)
        local newVal = GPCalc:GetSlotMultiplier(slotInfo.key)
        editBox:SetText(format("%.3f", newVal or 0))
        editBox:SetTextColor(1.0, 1.0, 1.0)
    end)
    row.resetBtn = resetBtn

    return row
end

--------------------------------------------------------------------------------
-- Item Override Section
--------------------------------------------------------------------------------

local function RefreshOverrideList(content, startY)
    -- Clear existing override rows
    for _, row in ipairs(overrideRows) do
        if row.label then row.label:Hide() end
        if row.editBox then row.editBox:Hide() end
        if row.removeBtn then row.removeBtn:Hide() end
    end
    overrideRows = {}

    local GPCalc = SimpleEPGP:GetModule("GPCalc")
    local overrides = GPCalc:GetAllItemOverrides()

    local y = startY
    for itemID, gpCost in pairs(overrides) do
        local row = {}

        -- Item name/ID label
        local label = content:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        label:SetPoint("TOPLEFT", 10, y)
        label:SetWidth(200)
        label:SetJustifyH("LEFT")
        local name = GetItemInfo(itemID)
        label:SetText(name or ("Item:" .. itemID))
        row.label = label

        -- GP cost EditBox
        local editBox = CreateFrame("EditBox", nil, content, "InputBoxTemplate")
        editBox:SetSize(60, 18)
        editBox:SetPoint("TOPLEFT", 220, y + 2)
        editBox:SetAutoFocus(false)
        editBox:SetMaxLetters(8)
        editBox:SetText(tostring(gpCost))
        editBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
        editBox:SetScript("OnEnterPressed", function(self)
            self:ClearFocus()
            local val = tonumber(self:GetText())
            if val and val >= 0 then
                GPCalc:SetItemOverride(itemID, floor(val))
            end
        end)
        row.editBox = editBox
        row.itemID = itemID

        -- Remove button
        local removeBtn = CreateFrame("Button", nil, content, "UIPanelButtonTemplate")
        removeBtn:SetSize(60, 18)
        removeBtn:SetPoint("TOPLEFT", 290, y + 2)
        removeBtn:SetText("Remove")
        removeBtn:SetScript("OnClick", function()
            GPCalc:ClearItemOverride(itemID)
            RefreshOverrideList(content, startY)
        end)
        row.removeBtn = removeBtn

        overrideRows[#overrideRows + 1] = row
        y = y - ROW_HEIGHT
    end

    return y
end

--------------------------------------------------------------------------------
-- Save / Populate
--------------------------------------------------------------------------------

local function SaveSlots()
    local GPCalc = SimpleEPGP:GetModule("GPCalc")
    for _, row in ipairs(slotRows) do
        local text = row.editBox:GetText()
        local value = tonumber(text)
        if value then
            local slots = GPCalc:GetAllSlotInfo()
            -- Find the default for this slot to decide whether to set or reset
            for _, info in ipairs(slots) do
                if info.key == row.slotKey then
                    if math.abs(value - info.default) < 0.0001 then
                        GPCalc:ResetSlotMultiplier(row.slotKey)
                        row.editBox:SetTextColor(1.0, 1.0, 1.0)
                    else
                        GPCalc:SetSlotMultiplier(row.slotKey, value)
                        row.editBox:SetTextColor(0.0, 1.0, 0.0)
                    end
                    break
                end
            end
        end
    end
end

local function SaveOverrides()
    local GPCalc = SimpleEPGP:GetModule("GPCalc")
    for _, row in ipairs(overrideRows) do
        local text = row.editBox:GetText()
        local value = tonumber(text)
        if value and value >= 0 then
            GPCalc:SetItemOverride(row.itemID, floor(value))
        end
    end
end

local function PopulateSlots()
    local GPCalc = SimpleEPGP:GetModule("GPCalc")
    local slots = GPCalc:GetAllSlotInfo()
    for i, info in ipairs(slots) do
        if slotRows[i] then
            slotRows[i].editBox:SetText(format("%.3f", info.current))
            if info.isOverride then
                slotRows[i].editBox:SetTextColor(0.0, 1.0, 0.0)
            else
                slotRows[i].editBox:SetTextColor(1.0, 1.0, 1.0)
            end
        end
    end
end

--------------------------------------------------------------------------------
-- Frame Construction
--------------------------------------------------------------------------------

local function CreateFrame_()
    local GPCalc = SimpleEPGP:GetModule("GPCalc")

    frame = CreateFrame("Frame", "SimpleEPGPGPConfigFrame", UIParent, "BackdropTemplate")
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
    title:SetText("GP Configuration")

    -- Close button
    local closeBtn = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    closeBtn:SetPoint("TOPRIGHT", -2, -2)
    closeBtn:SetScript("OnClick", function() GPConfig:Hide() end)

    -- ScrollFrame
    local scrollFrame = CreateFrame("ScrollFrame", nil, frame)
    scrollFrame:SetPoint("TOPLEFT", 8, -32)
    scrollFrame:SetPoint("BOTTOMRIGHT", -28, 44)

    local totalContentHeight = SLOT_SECTION_HEIGHT + OVERRIDE_SECTION_HEIGHT + 200
    local content = CreateFrame("Frame", nil, scrollFrame)
    content:SetSize(FRAME_WIDTH - 50, totalContentHeight)
    scrollFrame:SetScrollChild(content)

    -- Scroll bar
    local scrollBar = CreateFrame("Slider", nil, frame)
    scrollBar:SetPoint("TOPRIGHT", -10, -32)
    scrollBar:SetPoint("BOTTOMRIGHT", -10, 44)
    scrollBar:SetWidth(12)
    scrollBar:SetOrientation("VERTICAL")
    local maxScroll = math.max(0, totalContentHeight - (FRAME_HEIGHT - 76))
    scrollBar:SetMinMaxValues(0, maxScroll)
    scrollBar:SetValueStep(1)
    scrollBar:SetObeyStepOnDrag(true)
    scrollBar:SetValue(0)

    local sTrack = scrollBar:CreateTexture(nil, "BACKGROUND")
    sTrack:SetAllPoints()
    sTrack:SetColorTexture(0.1, 0.1, 0.1, 0.3)

    local sThumb = scrollBar:CreateTexture(nil, "OVERLAY")
    sThumb:SetSize(12, 40)
    sThumb:SetColorTexture(0.5, 0.5, 0.5, 0.6)
    scrollBar:SetThumbTexture(sThumb)

    scrollBar:SetScript("OnValueChanged", function(_, value)
        scrollFrame:SetVerticalScroll(value)
    end)

    frame:EnableMouseWheel(true)
    frame:SetScript("OnMouseWheel", function(_, delta)
        local current = scrollBar:GetValue()
        scrollBar:SetValue(current - delta * 20)
    end)

    -- Build content
    local y = -10

    -- === Slot Multipliers Section ===
    local slotHeader = content:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    slotHeader:SetPoint("TOPLEFT", 10, y)
    slotHeader:SetText("Slot Multipliers")
    slotHeader:SetTextColor(1.0, 0.82, 0)
    y = y - 18

    -- Column headers
    local colSlot = content:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    colSlot:SetPoint("TOPLEFT", 10, y)
    colSlot:SetText("Slot")
    colSlot:SetTextColor(0.7, 0.7, 0.7)

    local colDefault = content:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    colDefault:SetPoint("TOPLEFT", 195, y)
    colDefault:SetText("Default")
    colDefault:SetTextColor(0.7, 0.7, 0.7)

    local colCurrent = content:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    colCurrent:SetPoint("TOPLEFT", 260, y)
    colCurrent:SetText("Current")
    colCurrent:SetTextColor(0.7, 0.7, 0.7)
    y = y - ROW_HEIGHT

    local slots = GPCalc:GetAllSlotInfo()
    slotRows = {}
    for _, info in ipairs(slots) do
        slotRows[#slotRows + 1] = CreateSlotRow(content, y, info)
        y = y - ROW_HEIGHT
    end

    -- Reset All Slots button
    y = y - 8
    local resetAllBtn = CreateFrame("Button", nil, content, "UIPanelButtonTemplate")
    resetAllBtn:SetSize(120, 22)
    resetAllBtn:SetPoint("TOPLEFT", 10, y)
    resetAllBtn:SetText("Reset All Slots")
    resetAllBtn:SetScript("OnClick", function()
        for _, row in ipairs(slotRows) do
            GPCalc:ResetSlotMultiplier(row.slotKey)
        end
        PopulateSlots()
        SimpleEPGP:Print("All slot multipliers reset to defaults.")
    end)

    -- === Item Overrides Section ===
    y = y - 40
    local overrideHeader = content:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    overrideHeader:SetPoint("TOPLEFT", 10, y)
    overrideHeader:SetText("Item GP Overrides")
    overrideHeader:SetTextColor(1.0, 0.82, 0)
    y = y - 22

    -- Store the override list start position for refresh
    local overrideStartY = y
    y = RefreshOverrideList(content, overrideStartY)

    -- Add new override row
    y = y - 10
    local addLabel = content:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    addLabel:SetPoint("TOPLEFT", 10, y)
    addLabel:SetText("Add override:")
    addLabel:SetTextColor(0.7, 0.7, 0.7)
    y = y - ROW_HEIGHT

    local addItemLabel = content:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    addItemLabel:SetPoint("TOPLEFT", 10, y)
    addItemLabel:SetText("Item ID:")

    addItemIDBox = CreateFrame("EditBox", nil, content, "InputBoxTemplate")
    addItemIDBox:SetSize(80, 18)
    addItemIDBox:SetPoint("TOPLEFT", 70, y + 2)
    addItemIDBox:SetAutoFocus(false)
    addItemIDBox:SetMaxLetters(10)
    addItemIDBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    addItemIDBox:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)

    local addGPLabel = content:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    addGPLabel:SetPoint("TOPLEFT", 165, y)
    addGPLabel:SetText("GP:")

    addGPBox = CreateFrame("EditBox", nil, content, "InputBoxTemplate")
    addGPBox:SetSize(60, 18)
    addGPBox:SetPoint("TOPLEFT", 190, y + 2)
    addGPBox:SetAutoFocus(false)
    addGPBox:SetMaxLetters(8)
    addGPBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    addGPBox:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)

    local addBtn = CreateFrame("Button", nil, content, "UIPanelButtonTemplate")
    addBtn:SetSize(50, 18)
    addBtn:SetPoint("TOPLEFT", 260, y + 2)
    addBtn:SetText("Add")
    addBtn:SetScript("OnClick", function()
        local itemID = tonumber(addItemIDBox:GetText())
        local gpCost = tonumber(addGPBox:GetText())
        if not itemID or itemID <= 0 then
            SimpleEPGP:Print("Enter a valid item ID.")
            return
        end
        if not gpCost or gpCost < 0 then
            SimpleEPGP:Print("Enter a valid GP cost (>= 0).")
            return
        end
        GPCalc:SetItemOverride(itemID, floor(gpCost))
        addItemIDBox:SetText("")
        addGPBox:SetText("")
        RefreshOverrideList(content, overrideStartY)
        local name = GetItemInfo(itemID)
        SimpleEPGP:Print((name or ("Item:" .. itemID)) .. " override set to " .. floor(gpCost) .. " GP.")
    end)

    -- Bottom buttons (on the main frame, not scrolled)
    local saveBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    saveBtn:SetSize(100, 24)
    saveBtn:SetPoint("BOTTOMRIGHT", -40, 12)
    saveBtn:SetText("Save & Close")
    saveBtn:SetScript("OnClick", function()
        SaveSlots()
        SaveOverrides()
        SimpleEPGP:Print("GP configuration saved.")
        GPConfig:Hide()
    end)

    local cancelBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    cancelBtn:SetSize(80, 24)
    cancelBtn:SetPoint("BOTTOMLEFT", 12, 12)
    cancelBtn:SetText("Close")
    cancelBtn:SetScript("OnClick", function()
        GPConfig:Hide()
    end)

    -- Escape to close
    table.insert(UISpecialFrames, "SimpleEPGPGPConfigFrame")

    frame:Hide()
end

function GPConfig:Show()
    if not frame then
        CreateFrame_()
    end
    PopulateSlots()
    frame:Show()
end

function GPConfig:Hide()
    if frame then
        frame:Hide()
    end
end

function GPConfig:Toggle()
    if frame and frame:IsShown() then
        self:Hide()
    else
        self:Show()
    end
end
