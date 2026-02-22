-----------------------------------------------------------------------
-- OfficerPanel.lua — UI panel for officer EP/GP operations
-- Provides EP/GP adjustment, Mass EP, Decay, and Reset via GUI
-----------------------------------------------------------------------
local SimpleEPGP = LibStub("AceAddon-3.0"):GetAddon("SimpleEPGP")
local OfficerPanel = SimpleEPGP:NewModule("OfficerPanel")
local Utils = SimpleEPGP.UI.Utils

local tonumber = tonumber
local ipairs = ipairs
local format = string.format

-- Constants
local FRAME_WIDTH = 420
local FRAME_HEIGHT = 460
local LABEL_X = 15
local INPUT_X = 130
local INPUT_WIDTH = 240
local BUTTON_WIDTH = 160
local BUTTON_HEIGHT = 24
local SECTION_GAP = 16
local ROW_HEIGHT = 28

-- State
local frame
local playerDropdown
local playerDropdownText
local playerList = {}
local selectedPlayer = nil
local dropdownScrollOffset = 0

-- Confirmation dialog state
local pendingConfirmAction = nil
local confirmFrame

-----------------------------------------------------------------------
-- Player list helpers
-----------------------------------------------------------------------

--- Build a sorted list of guild member names from the EPGP standings.
local function RefreshPlayerList()
    local EPGP = SimpleEPGP:GetModule("EPGP")
    local standings = EPGP:GetStandings()
    playerList = {}
    for i = 1, #standings do
        playerList[#playerList + 1] = standings[i].name
    end
    table.sort(playerList)
end

-----------------------------------------------------------------------
-- Dropdown menu for player selection
-----------------------------------------------------------------------

local dropdownMenu

local function CreateDropdownMenu(parent)
    local menu = CreateFrame("Frame", "SimpleEPGPOfficerDropdownMenu", parent, "BackdropTemplate")
    menu:SetFrameStrata("TOOLTIP")
    menu:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile = true, tileSize = 32, edgeSize = 16,
        insets = { left = 4, right = 4, top = 4, bottom = 4 },
    })
    menu:SetClampedToScreen(true)
    menu:Hide()
    menu._buttons = {}
    return menu
end

--- Update dropdown button visibility/positions based on current scroll offset.
local function UpdateDropdownScroll()
    if not dropdownMenu then return end

    local rowH = 18
    local maxVisible = 15
    local count = #playerList

    -- Clamp scroll offset to valid range
    local maxOffset = count > maxVisible and (count - maxVisible) or 0
    if dropdownScrollOffset < 0 then dropdownScrollOffset = 0 end
    if dropdownScrollOffset > maxOffset then dropdownScrollOffset = maxOffset end

    for i = 1, #dropdownMenu._buttons do
        local btn = dropdownMenu._buttons[i]
        local visibleIndex = i - dropdownScrollOffset
        if visibleIndex >= 1 and visibleIndex <= maxVisible then
            btn:SetPoint("TOPLEFT", 4, -(4 + (visibleIndex - 1) * rowH))
            btn._label:SetText(playerList[i])
            btn:Show()

            local name = playerList[i]
            btn:SetScript("OnClick", function()
                selectedPlayer = name
                if playerDropdownText then
                    playerDropdownText:SetText(name)
                end
                dropdownMenu:Hide()
            end)
        else
            btn:Hide()
        end
    end
end

local function ShowDropdownMenu(anchorFrame)
    RefreshPlayerList()

    if not dropdownMenu then
        dropdownMenu = CreateDropdownMenu(frame)
    end

    -- Reset scroll offset when opening
    dropdownScrollOffset = 0

    -- Clear old buttons
    for _, btn in ipairs(dropdownMenu._buttons) do
        btn:Hide()
    end

    local menuWidth = INPUT_WIDTH
    local rowH = 18
    local maxVisible = 15
    local count = #playerList
    local visibleCount = count > maxVisible and maxVisible or count
    local menuHeight = visibleCount * rowH + 8

    dropdownMenu:SetSize(menuWidth, menuHeight)
    dropdownMenu:SetPoint("TOPLEFT", anchorFrame, "BOTTOMLEFT", 0, -2)

    -- Ensure buttons exist for all items
    for i = 1, count do
        local btn = dropdownMenu._buttons[i]
        if not btn then
            btn = CreateFrame("Button", nil, dropdownMenu)
            btn:SetSize(menuWidth - 8, rowH)
            btn:SetNormalFontObject("GameFontHighlightSmall")
            local highlight = btn:CreateTexture(nil, "HIGHLIGHT")
            highlight:SetAllPoints()
            highlight:SetColorTexture(1, 1, 1, 0.1)
            btn._label = btn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            btn._label:SetPoint("LEFT", 4, 0)
            btn._label:SetJustifyH("LEFT")
            dropdownMenu._buttons[i] = btn
        end
    end

    -- Enable mouse wheel scrolling on the dropdown menu
    dropdownMenu:EnableMouseWheel(true)
    dropdownMenu:SetScript("OnMouseWheel", function(_, delta)
        dropdownScrollOffset = dropdownScrollOffset - delta
        UpdateDropdownScroll()
    end)

    -- Show/position only the visible buttons
    UpdateDropdownScroll()

    dropdownMenu:Show()
end

-----------------------------------------------------------------------
-- Confirmation dialog
-----------------------------------------------------------------------

local function CreateConfirmFrame()
    confirmFrame = Utils.CreateStandardFrame({
        name = "SimpleEPGPOfficerConfirmFrame",
        width = 340,
        height = 140,
        strata = "FULLSCREEN_DIALOG",
        point = { "CENTER", 0, 100 },
    })

    confirmFrame._text = confirmFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    confirmFrame._text:SetPoint("TOP", 0, -20)
    confirmFrame._text:SetWidth(300)
    confirmFrame._text:SetJustifyH("CENTER")

    local yesBtn = CreateFrame("Button", nil, confirmFrame, "UIPanelButtonTemplate")
    yesBtn:SetSize(100, 24)
    yesBtn:SetPoint("BOTTOMRIGHT", confirmFrame, "BOTTOM", -10, 16)
    yesBtn:SetText("Confirm")
    yesBtn:SetScript("OnClick", function()
        if pendingConfirmAction then
            pendingConfirmAction()
            pendingConfirmAction = nil
        end
        confirmFrame:Hide()
    end)

    local noBtn = CreateFrame("Button", nil, confirmFrame, "UIPanelButtonTemplate")
    noBtn:SetSize(100, 24)
    noBtn:SetPoint("BOTTOMLEFT", confirmFrame, "BOTTOM", 10, 16)
    noBtn:SetText("Cancel")
    noBtn:SetScript("OnClick", function()
        pendingConfirmAction = nil
        confirmFrame:Hide()
    end)

end

local function ShowConfirmDialog(message, onConfirm)
    if not confirmFrame then
        CreateConfirmFrame()
    end
    confirmFrame._text:SetText(message)
    pendingConfirmAction = onConfirm
    confirmFrame:Show()
end

-----------------------------------------------------------------------
-- Section creation helpers (delegate to shared Utils)
-----------------------------------------------------------------------

local function CreateSectionHeader(parent, text, y)
    return Utils.CreateSectionHeader(parent, text, LABEL_X, y)
end

local function CreateLabel(parent, text, y)
    return Utils.CreateLabel(parent, text, LABEL_X + 10, y)
end

local function CreateEditBox(parent, y, width)
    return Utils.CreateEditBox(parent, INPUT_X, y, width or INPUT_WIDTH)
end

local function CreateActionButton(parent, text, y, onClick)
    local btn = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    btn:SetSize(BUTTON_WIDTH, BUTTON_HEIGHT)
    btn:SetPoint("TOPLEFT", INPUT_X, y)
    btn:SetText(text)
    btn:SetScript("OnClick", onClick)
    return btn
end

-----------------------------------------------------------------------
-- Permission check helper
-----------------------------------------------------------------------

local function CheckOfficerPermission()
    local EPGP = SimpleEPGP:GetModule("EPGP")
    if not EPGP:CanEditNotes() then
        SimpleEPGP:Print("You do not have officer note permissions. Officer panel is restricted to officers.")
        return false
    end
    return true
end

-----------------------------------------------------------------------
-- Main frame creation
-----------------------------------------------------------------------

local epAmountBox, epReasonBox
local gpAmountBox, gpReasonBox
local massEPAmountBox, massEPReasonBox

local function CreateFrame_()
    frame = Utils.CreateStandardFrame({
        name = "SimpleEPGPOfficerFrame",
        width = FRAME_WIDTH,
        height = FRAME_HEIGHT,
        title = "Officer EP/GP Panel",
        titleFont = "GameFontNormalLarge",
        onClose = function() OfficerPanel:Hide() end,
    })

    -- Content area
    local content = CreateFrame("Frame", nil, frame)
    content:SetPoint("TOPLEFT", 8, -36)
    content:SetPoint("BOTTOMRIGHT", -8, 8)

    local y = -4

    ---------------------------------------------------------------
    -- Player Selection (shared by EP and GP sections)
    ---------------------------------------------------------------
    CreateSectionHeader(content, "Player", y)
    y = y - 22

    -- Dropdown button for player selection
    playerDropdown = CreateFrame("Button", "SimpleEPGPOfficerPlayerDropdown", content, "BackdropTemplate")
    playerDropdown:SetSize(INPUT_WIDTH, 22)
    playerDropdown:SetPoint("TOPLEFT", INPUT_X, y)
    playerDropdown:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 12,
        insets = { left = 3, right = 3, top = 3, bottom = 3 },
    })

    playerDropdownText = playerDropdown:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    playerDropdownText:SetPoint("LEFT", 6, 0)
    playerDropdownText:SetPoint("RIGHT", -20, 0)
    playerDropdownText:SetJustifyH("LEFT")
    playerDropdownText:SetText("Select Player...")

    -- Arrow indicator
    local arrow = playerDropdown:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    arrow:SetPoint("RIGHT", -4, 0)
    arrow:SetText("v")

    playerDropdown:SetScript("OnClick", function(self)
        if dropdownMenu and dropdownMenu:IsShown() then
            dropdownMenu:Hide()
        else
            ShowDropdownMenu(self)
        end
    end)

    -- Click anywhere else to close dropdown
    frame:SetScript("OnMouseDown", function()
        if dropdownMenu and dropdownMenu:IsShown() then
            dropdownMenu:Hide()
        end
    end)

    ---------------------------------------------------------------
    -- EP Adjustment
    ---------------------------------------------------------------
    y = y - ROW_HEIGHT - SECTION_GAP
    CreateSectionHeader(content, "EP Adjustment", y)
    y = y - 22

    CreateLabel(content, "Amount", y)
    epAmountBox = CreateEditBox(content, y, 80)
    epAmountBox:SetNumeric(false)  -- allow negative via "-"
    y = y - ROW_HEIGHT

    CreateLabel(content, "Reason", y)
    epReasonBox = CreateEditBox(content, y)
    y = y - ROW_HEIGHT

    CreateActionButton(content, "Award EP", y, function()
        if not CheckOfficerPermission() then return end
        if not selectedPlayer then
            SimpleEPGP:Print("Select a player first.")
            return
        end
        local amount = tonumber(epAmountBox:GetText())
        if not amount then
            SimpleEPGP:Print("Enter a valid EP amount.")
            return
        end
        local reason = epReasonBox:GetText()
        if not reason or reason == "" then
            reason = "Manual EP adjustment"
        end
        local sign = amount >= 0 and "+" or ""
        ShowConfirmDialog(
            format("Award %s%d EP to %s?\n\nReason: %s", sign, amount, selectedPlayer, reason),
            function()
                local EPGP = SimpleEPGP:GetModule("EPGP")
                local ok = EPGP:ModifyEP(selectedPlayer, amount, reason)
                if ok then
                    SimpleEPGP:Print(format("%s%d EP to %s (%s)", sign, amount, selectedPlayer, reason))
                end
            end
        )
    end)

    ---------------------------------------------------------------
    -- GP Adjustment
    ---------------------------------------------------------------
    y = y - ROW_HEIGHT - SECTION_GAP
    CreateSectionHeader(content, "GP Adjustment", y)
    y = y - 22

    CreateLabel(content, "Amount", y)
    gpAmountBox = CreateEditBox(content, y, 80)
    gpAmountBox:SetNumeric(false)
    y = y - ROW_HEIGHT

    CreateLabel(content, "Reason", y)
    gpReasonBox = CreateEditBox(content, y)
    y = y - ROW_HEIGHT

    CreateActionButton(content, "Adjust GP", y, function()
        if not CheckOfficerPermission() then return end
        if not selectedPlayer then
            SimpleEPGP:Print("Select a player first.")
            return
        end
        local amount = tonumber(gpAmountBox:GetText())
        if not amount then
            SimpleEPGP:Print("Enter a valid GP amount.")
            return
        end
        local reason = gpReasonBox:GetText()
        if not reason or reason == "" then
            reason = "Manual GP adjustment"
        end
        local sign = amount >= 0 and "+" or ""
        ShowConfirmDialog(
            format("Adjust %s%d GP on %s?\n\nReason: %s", sign, amount, selectedPlayer, reason),
            function()
                local EPGP = SimpleEPGP:GetModule("EPGP")
                local ok = EPGP:ModifyGP(selectedPlayer, amount, reason)
                if ok then
                    SimpleEPGP:Print(format("%s%d GP to %s (%s)", sign, amount, selectedPlayer, reason))
                end
            end
        )
    end)

    ---------------------------------------------------------------
    -- Mass EP
    ---------------------------------------------------------------
    y = y - ROW_HEIGHT - SECTION_GAP
    CreateSectionHeader(content, "Mass EP (Raid-wide)", y)
    y = y - 22

    CreateLabel(content, "Amount", y)
    massEPAmountBox = CreateEditBox(content, y, 80)
    y = y - ROW_HEIGHT

    CreateLabel(content, "Reason", y)
    massEPReasonBox = CreateEditBox(content, y)
    y = y - ROW_HEIGHT

    CreateActionButton(content, "Award Mass EP", y, function()
        if not CheckOfficerPermission() then return end
        local amount = tonumber(massEPAmountBox:GetText())
        if not amount then
            SimpleEPGP:Print("Enter a valid EP amount for mass award.")
            return
        end
        local reason = massEPReasonBox:GetText()
        if not reason or reason == "" then
            reason = "Manual mass EP"
        end
        ShowConfirmDialog(
            format("Award %d EP to ALL raid members?\n\nReason: %s", amount, reason),
            function()
                local EPGP = SimpleEPGP:GetModule("EPGP")
                EPGP:MassEP(amount, reason)
            end
        )
    end)

    ---------------------------------------------------------------
    -- Decay & Reset (dangerous operations)
    ---------------------------------------------------------------
    y = y - ROW_HEIGHT - SECTION_GAP
    CreateSectionHeader(content, "Maintenance", y)
    y = y - 26

    -- Decay button
    local decayBtn = CreateFrame("Button", nil, content, "UIPanelButtonTemplate")
    decayBtn:SetSize(BUTTON_WIDTH, BUTTON_HEIGHT)
    decayBtn:SetPoint("TOPLEFT", LABEL_X + 10, y)
    decayBtn:SetText("Apply Decay")
    decayBtn:SetScript("OnClick", function()
        if not CheckOfficerPermission() then return end
        local db = SimpleEPGP.db
        local pct = db.profile.decay_percent or 0
        if pct <= 0 then
            SimpleEPGP:Print("Decay percent is 0. Configure it in Settings first.")
            return
        end
        ShowConfirmDialog(
            format("Apply %d%% decay to ALL guild members' EP and GP?\n\nThis affects every member with EP or GP > 0.", pct),
            function()
                local EPGP = SimpleEPGP:GetModule("EPGP")
                EPGP:Decay()
            end
        )
    end)

    -- Reset button (extra caution — red tinted text later)
    local resetBtn = CreateFrame("Button", nil, content, "UIPanelButtonTemplate")
    resetBtn:SetSize(BUTTON_WIDTH, BUTTON_HEIGHT)
    resetBtn:SetPoint("LEFT", decayBtn, "RIGHT", 20, 0)
    resetBtn:SetText("|cffff4444Reset All|r")
    resetBtn:SetScript("OnClick", function()
        if not CheckOfficerPermission() then return end
        ShowConfirmDialog(
            "DANGER: Reset ALL EP and GP to 0 for every guild member?\n\nThis action CANNOT be undone!",
            function()
                local EPGP = SimpleEPGP:GetModule("EPGP")
                EPGP:ResetAll()
            end
        )
    end)

end

-----------------------------------------------------------------------
-- Module API
-----------------------------------------------------------------------

function OfficerPanel:Show()
    if not frame then
        CreateFrame_()
    end
    -- Refresh player list each time we show
    RefreshPlayerList()
    frame:Show()
end

function OfficerPanel:Hide()
    if frame then
        frame:Hide()
    end
    if dropdownMenu then
        dropdownMenu:Hide()
    end
    if confirmFrame then
        confirmFrame:Hide()
    end
end

function OfficerPanel:Toggle()
    if frame and frame:IsShown() then
        self:Hide()
    else
        self:Show()
    end
end

-----------------------------------------------------------------------
-- Test helpers — expose internal state for unit tests
-----------------------------------------------------------------------

--- Get the currently selected player name (for testing).
function OfficerPanel:GetSelectedPlayer()
    return selectedPlayer
end

--- Set the selected player (for testing).
function OfficerPanel:SetSelectedPlayer(name)
    selectedPlayer = name
    if playerDropdownText then
        playerDropdownText:SetText(name or "Select Player...")
    end
end

--- Get the EP amount edit box (for testing).
function OfficerPanel:GetEPAmountBox()
    return epAmountBox
end

--- Get the EP reason edit box (for testing).
function OfficerPanel:GetEPReasonBox()
    return epReasonBox
end

--- Get the GP amount edit box (for testing).
function OfficerPanel:GetGPAmountBox()
    return gpAmountBox
end

--- Get the GP reason edit box (for testing).
function OfficerPanel:GetGPReasonBox()
    return gpReasonBox
end

--- Get the Mass EP amount edit box (for testing).
function OfficerPanel:GetMassEPAmountBox()
    return massEPAmountBox
end

--- Get the Mass EP reason edit box (for testing).
function OfficerPanel:GetMassEPReasonBox()
    return massEPReasonBox
end

--- Get the player list (for testing).
function OfficerPanel:GetPlayerList()
    RefreshPlayerList()
    return playerList
end

--- Show the confirmation dialog (for testing).
function OfficerPanel:ShowConfirmDialog(message, onConfirm)
    ShowConfirmDialog(message, onConfirm)
end

--- Get pending confirm action (for testing).
function OfficerPanel:GetPendingConfirmAction()
    return pendingConfirmAction
end

--- Execute the pending confirm action (for testing).
function OfficerPanel:ExecutePendingConfirm()
    if pendingConfirmAction then
        pendingConfirmAction()
        pendingConfirmAction = nil
    end
end

--- Cancel the pending confirm (for testing).
function OfficerPanel:CancelPendingConfirm()
    pendingConfirmAction = nil
    if confirmFrame then
        confirmFrame:Hide()
    end
end

--- Check if the panel frame is shown (for testing).
function OfficerPanel:IsShown()
    return frame and frame:IsShown() or false
end

--- Get the current dropdown scroll offset (for testing).
function OfficerPanel:GetDropdownScrollOffset()
    return dropdownScrollOffset
end

--- Set the dropdown scroll offset (for testing).
function OfficerPanel:SetDropdownScrollOffset(offset)
    dropdownScrollOffset = offset
    UpdateDropdownScroll()
end

--- Get the dropdown menu frame (for testing).
function OfficerPanel:GetDropdownMenu()
    return dropdownMenu
end
