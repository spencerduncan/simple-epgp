local SimpleEPGP = LibStub("AceAddon-3.0"):GetAddon("SimpleEPGP")
local AwardFrame = SimpleEPGP:NewModule("AwardFrame", "AceEvent-3.0")

local function StripRealm(name)
    if SimpleEPGP.StripRealm then return SimpleEPGP.StripRealm(name) end
    if not name then return nil end
    return name:match("^([^%-]+)") or name
end

local GetItemInfo = GetItemInfo
local GetItemQualityColor = GetItemQualityColor
local RAID_CLASS_COLORS = RAID_CLASS_COLORS
local GetRaidRosterInfo = GetRaidRosterInfo
local GetNumGroupMembers = GetNumGroupMembers
local IsInRaid = IsInRaid
local time = time
local floor = math.floor
local format = string.format
local pairs = pairs
local ipairs = ipairs
local strlower = string.lower
local strsub = string.sub

-- Main frame (created lazily)
local awardFrame
-- Current state
local eligibleItems = {}
local activeSessionId
local selectedBidder  -- {name, bidType}
-- Bid refresh ticker
local bidRefreshTicker
-- Autocomplete state
local MAX_AUTOCOMPLETE_RESULTS = 8
local AUTOCOMPLETE_ROW_HEIGHT = 18
local manualBidType = "MS"
local autocompleteHighlightIndex = 0
local autocompleteResults = {}

-- Forward declaration (defined after PopulateBidSection)
local RefreshBidDisplay

--------------------------------------------------------------------------------
-- Confirmation Dialog
--------------------------------------------------------------------------------

StaticPopupDialogs["SEPGP_AWARD_CONFIRM"] = { -- luacheck: ignore 122
    -- StaticPopup_Show only substitutes text_arg1 and text_arg2 into format specifiers.
    -- Use OnShow to set the full message including GP cost and bid type from data.
    text = "Award %s to %s?",
    button1 = "Award",
    button2 = "Cancel",
    OnShow = function(self, data)
        if data and data.gpCharged then
            self.text:SetFormattedText("Award %s to %s for %d GP (%s)?",
                data.itemLink, data.name, data.gpCharged, data.bidType)
        end
    end,
    OnAccept = function(self, data)
        local LootMaster = SimpleEPGP:GetModule("LootMaster")
        LootMaster:AwardItem(data.sessionId, data.name, data.bidType)
    end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
}

--------------------------------------------------------------------------------
-- Backdrop
--------------------------------------------------------------------------------

local BACKDROP_INFO = {
    bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
    edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
    tile = true,
    tileSize = 32,
    edgeSize = 16,
    insets = { left = 4, right = 4, top = 4, bottom = 4 },
}

local SECTION_BACKDROP = {
    bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    tile = true,
    tileSize = 16,
    edgeSize = 12,
    insets = { left = 3, right = 3, top = 3, bottom = 3 },
}

--------------------------------------------------------------------------------
-- Button State Colors
--------------------------------------------------------------------------------

local COLOR_ENABLED = { r = 1.0, g = 0.82, b = 0.0 }    -- Gold (normal WoW)
local COLOR_DISABLED = { r = 0.5, g = 0.5, b = 0.5 }     -- Gray
local COLOR_AWARD = { r = 0.2, g = 1.0, b = 0.2 }        -- Green for award
local COLOR_CANCEL = { r = 1.0, g = 0.3, b = 0.3 }       -- Red for cancel

--- Apply colored text to a button based on enabled state and optional color override.
local function StyleButton(btn, enabled, color)
    btn:SetEnabled(enabled)
    local fontString = btn:GetFontString()
    if fontString and fontString.SetTextColor then
        if enabled and color then
            fontString:SetTextColor(color.r, color.g, color.b)
        elseif enabled then
            fontString:SetTextColor(COLOR_ENABLED.r, COLOR_ENABLED.g, COLOR_ENABLED.b)
        else
            fontString:SetTextColor(COLOR_DISABLED.r, COLOR_DISABLED.g, COLOR_DISABLED.b)
        end
    end
end

--------------------------------------------------------------------------------
-- Item Button Creation
--------------------------------------------------------------------------------

local function CreateItemButton(parent, index)
    local btn = CreateFrame("Button", nil, parent)
    btn:SetSize(36, 36)

    local icon = btn:CreateTexture(nil, "ARTWORK")
    icon:SetAllPoints()
    btn.icon = icon

    local border = btn:CreateTexture(nil, "OVERLAY")
    border:SetSize(40, 40)
    border:SetPoint("CENTER")
    border:SetTexture("Interface\\Buttons\\UI-ActionButton-Border")
    border:SetBlendMode("ADD")
    border:SetAlpha(0.6)
    btn.border = border

    btn:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
    return btn
end

--------------------------------------------------------------------------------
-- Bid Row Creation
--------------------------------------------------------------------------------

local BID_ROW_HEIGHT = 20
local MAX_VISIBLE_ROWS = 6

local function CreateBidRow(parent, index)
    local row = CreateFrame("Button", nil, parent)
    row:SetSize(460, BID_ROW_HEIGHT)

    -- Class color bar
    local classBar = row:CreateTexture(nil, "ARTWORK")
    classBar:SetSize(4, BID_ROW_HEIGHT - 2)
    classBar:SetPoint("LEFT", row, "LEFT", 2, 0)
    row.classBar = classBar

    -- Player name
    local nameText = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    nameText:SetPoint("LEFT", classBar, "RIGHT", 6, 0)
    nameText:SetWidth(120)
    nameText:SetJustifyH("LEFT")
    row.nameText = nameText

    -- PR
    local prText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    prText:SetPoint("LEFT", row, "LEFT", 150, 0)
    prText:SetWidth(80)
    prText:SetJustifyH("LEFT")
    row.prText = prText

    -- EP
    local epText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    epText:SetPoint("LEFT", row, "LEFT", 240, 0)
    epText:SetWidth(70)
    epText:SetJustifyH("LEFT")
    row.epText = epText

    -- GP
    local gpText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    gpText:SetPoint("LEFT", row, "LEFT", 320, 0)
    gpText:SetWidth(70)
    gpText:SetJustifyH("LEFT")
    row.gpText = gpText

    -- Highlight texture
    local highlight = row:CreateTexture(nil, "HIGHLIGHT")
    highlight:SetAllPoints()
    highlight:SetColorTexture(1, 1, 1, 0.1)

    -- Selection texture
    local selected = row:CreateTexture(nil, "BACKGROUND")
    selected:SetAllPoints()
    selected:SetColorTexture(0.3, 0.5, 1.0, 0.3)
    selected:Hide()
    row.selected = selected

    return row
end

--------------------------------------------------------------------------------
-- Bid Section (MS / OS / DE header + rows)
--------------------------------------------------------------------------------

local function CreateBidSection(parent, title, yOffset)
    local section = CreateFrame("Frame", nil, parent)
    section:SetSize(470, 24)
    section:SetPoint("TOPLEFT", parent, "TOPLEFT", 10, yOffset)

    local header = section:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    header:SetPoint("TOPLEFT", section, "TOPLEFT", 0, 0)
    header:SetText(title)
    section.header = header

    section.rows = {}
    for i = 1, MAX_VISIBLE_ROWS do
        local row = CreateBidRow(section, i)
        row:SetPoint("TOPLEFT", section, "TOPLEFT", 0, -20 - (i - 1) * BID_ROW_HEIGHT)
        row:Hide()
        section.rows[i] = row
    end

    return section
end

--------------------------------------------------------------------------------
-- Autocomplete Dropdown Creation
--------------------------------------------------------------------------------

local function CreateAutocompleteRow(parent, index)
    local row = CreateFrame("Button", nil, parent)
    row:SetSize(200, AUTOCOMPLETE_ROW_HEIGHT)
    row:SetPoint("TOPLEFT", parent, "TOPLEFT", 2, -2 - (index - 1) * AUTOCOMPLETE_ROW_HEIGHT)

    -- Class color bar
    local classBar = row:CreateTexture(nil, "ARTWORK")
    classBar:SetSize(3, AUTOCOMPLETE_ROW_HEIGHT - 2)
    classBar:SetPoint("LEFT", row, "LEFT", 1, 0)
    row.classBar = classBar

    -- Name text
    local nameText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    nameText:SetPoint("LEFT", classBar, "RIGHT", 4, 0)
    nameText:SetWidth(190)
    nameText:SetJustifyH("LEFT")
    row.nameText = nameText

    -- Highlight texture (for keyboard navigation)
    local highlight = row:CreateTexture(nil, "BACKGROUND")
    highlight:SetAllPoints()
    highlight:SetColorTexture(0.3, 0.5, 1.0, 0.3)
    highlight:Hide()
    row.highlight = highlight

    -- Mouse hover highlight
    local hoverHL = row:CreateTexture(nil, "HIGHLIGHT")
    hoverHL:SetAllPoints()
    hoverHL:SetColorTexture(1, 1, 1, 0.1)

    return row
end

local function CreateAutocompleteDropdown(parent)
    local dropdown = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    dropdown:SetSize(206, 10)  -- Width matches editbox; height set dynamically
    dropdown:SetPoint("TOPLEFT", parent, "BOTTOMLEFT", 0, -2)
    dropdown:SetFrameStrata("TOOLTIP")
    dropdown:SetBackdrop(SECTION_BACKDROP)
    dropdown:SetBackdropColor(0.1, 0.1, 0.1, 0.95)
    dropdown:SetBackdropBorderColor(0.4, 0.4, 0.4, 1.0)
    dropdown:Hide()

    dropdown.rows = {}
    for i = 1, MAX_AUTOCOMPLETE_RESULTS do
        local row = CreateAutocompleteRow(dropdown, i)
        row:Hide()
        dropdown.rows[i] = row
    end

    return dropdown
end

--------------------------------------------------------------------------------
-- Bid Type Toggle Buttons
--------------------------------------------------------------------------------

local function CreateBidTypeButton(parent, label, xOffset)
    local btn = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    btn:SetSize(32, 20)
    btn:SetPoint("LEFT", parent, "RIGHT", xOffset, 0)
    btn:SetText(label)

    -- Selection indicator
    local selTex = btn:CreateTexture(nil, "BACKGROUND")
    selTex:SetAllPoints()
    selTex:SetColorTexture(0.2, 0.6, 1.0, 0.3)
    selTex:Hide()
    btn.selTex = selTex

    return btn
end

--------------------------------------------------------------------------------
-- Frame Creation (lazy)
--------------------------------------------------------------------------------

local Utils = SimpleEPGP.UI.Utils

local function CreateAwardFrame()
    local f = Utils.CreateStandardFrame({
        name = "SimpleEPGPAwardFrame",
        width = 500,
        height = 490,
        title = "SimpleEPGP - Loot Distribution",
        titleFont = "GameFontNormalLarge",
        backdrop = BACKDROP_INFO,
        backdropColor = { 0, 0, 0, 0.9 },
    })

    -- Item list area (top section)
    local itemArea = CreateFrame("Frame", nil, f, "BackdropTemplate")
    itemArea:SetSize(476, 50)
    itemArea:SetPoint("TOPLEFT", f, "TOPLEFT", 12, -36)
    itemArea:SetBackdrop(SECTION_BACKDROP)
    itemArea:SetBackdropColor(0, 0, 0, 0.4)
    f.itemArea = itemArea

    -- Item buttons (created on demand, max 8)
    f.itemButtons = {}

    -- Bid display area (main section)
    local bidArea = CreateFrame("Frame", nil, f, "BackdropTemplate")
    bidArea:SetSize(476, 290)
    bidArea:SetPoint("TOPLEFT", itemArea, "BOTTOMLEFT", 0, -4)
    bidArea:SetBackdrop(SECTION_BACKDROP)
    bidArea:SetBackdropColor(0, 0, 0, 0.3)
    f.bidArea = bidArea

    -- Bid sections
    f.msSection = CreateBidSection(bidArea, "Main Spec", -8)
    f.osSection = CreateBidSection(bidArea, "Off Spec", -110)
    f.deSection = CreateBidSection(bidArea, "Disenchant", -210)

    -- Manual award area (between bid area and bottom controls)
    local manualLabel = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    manualLabel:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 14, 70)
    manualLabel:SetText("Manual:")
    manualLabel:SetTextColor(0.8, 0.8, 0.8)
    f.manualLabel = manualLabel

    -- Player search editbox
    local searchBox = CreateFrame("EditBox", "SimpleEPGPSearchBox", f, "InputBoxTemplate")
    searchBox:SetSize(200, 20)
    searchBox:SetPoint("LEFT", manualLabel, "RIGHT", 6, 0)
    searchBox:SetAutoFocus(false)
    searchBox:SetMaxLetters(50)
    f.searchBox = searchBox

    -- Autocomplete dropdown
    local dropdown = CreateAutocompleteDropdown(searchBox)
    f.autocompleteDropdown = dropdown

    -- Bid type toggle buttons (MS / OS / DE) for manual awards
    local msBtn = CreateBidTypeButton(searchBox, "MS", 8)
    local osBtn = CreateBidTypeButton(searchBox, "OS", 44)
    local deBtn = CreateBidTypeButton(searchBox, "DE", 80)
    f.bidTypeMS = msBtn
    f.bidTypeOS = osBtn
    f.bidTypeDE = deBtn

    -- Wire up bid type button clicks
    local function UpdateBidTypeButtons()
        f.bidTypeMS.selTex:SetShown(manualBidType == "MS")
        f.bidTypeOS.selTex:SetShown(manualBidType == "OS")
        f.bidTypeDE.selTex:SetShown(manualBidType == "DE")
        -- Update selectedBidder's bidType if it was set via autocomplete
        if selectedBidder and selectedBidder.isManual then
            selectedBidder.bidType = manualBidType
            AwardFrame:UpdateButtonStates()
        end
    end

    msBtn:SetScript("OnClick", function()
        manualBidType = "MS"
        UpdateBidTypeButtons()
    end)
    osBtn:SetScript("OnClick", function()
        manualBidType = "OS"
        UpdateBidTypeButtons()
    end)
    deBtn:SetScript("OnClick", function()
        manualBidType = "DE"
        UpdateBidTypeButtons()
    end)

    -- Default selection indicator
    msBtn.selTex:Show()

    -- Wire up editbox scripts
    searchBox:SetScript("OnTextChanged", function(self)
        AwardFrame:OnSearchTextChanged(self:GetText())
    end)
    searchBox:SetScript("OnEnterPressed", function()
        AwardFrame:OnSearchEnterPressed()
    end)
    searchBox:SetScript("OnEscapePressed", function(self)
        self:SetText("")
        self:ClearFocus()
        AwardFrame:HideAutocomplete()
    end)
    searchBox:SetScript("OnKeyDown", function(self, key)
        if key == "DOWN" then
            AwardFrame:OnSearchArrowKey(1)
        elseif key == "UP" then
            AwardFrame:OnSearchArrowKey(-1)
        end
    end)

    -- Status text (above buttons)
    local statusText = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    statusText:SetPoint("BOTTOM", f, "BOTTOM", 0, 55)
    statusText:SetTextColor(0.7, 0.7, 0.7)
    statusText:SetText("Select an item to begin")
    f.statusText = statusText

    -- Bottom controls area
    -- Start Bidding button
    local startBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    startBtn:SetSize(120, 24)
    startBtn:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 12, 28)
    startBtn:SetText("Start Bidding")
    startBtn:SetScript("OnClick", function()
        AwardFrame:OnStartBidding()
    end)
    f.startBtn = startBtn

    -- Cancel button
    local cancelBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    cancelBtn:SetSize(80, 24)
    cancelBtn:SetPoint("LEFT", startBtn, "RIGHT", 8, 0)
    cancelBtn:SetText("Cancel")
    cancelBtn:SetScript("OnClick", function()
        AwardFrame:OnCancelSession()
    end)
    cancelBtn:SetEnabled(false)
    f.cancelBtn = cancelBtn

    -- Award button
    local awardBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    awardBtn:SetSize(160, 24)
    awardBtn:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -12, 28)
    awardBtn:SetText("Award")
    awardBtn:SetEnabled(false)
    awardBtn:SetScript("OnClick", function()
        AwardFrame:OnAwardClick()
    end)
    f.awardBtn = awardBtn

    -- Timer bar
    local timerBar = CreateFrame("StatusBar", nil, f)
    timerBar:SetSize(476, 14)
    timerBar:SetPoint("BOTTOM", f, "BOTTOM", 0, 10)
    timerBar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
    timerBar:SetStatusBarColor(0.2, 0.6, 1.0)
    timerBar:SetMinMaxValues(0, 1)
    timerBar:SetValue(1)

    local timerBG = timerBar:CreateTexture(nil, "BACKGROUND")
    timerBG:SetAllPoints()
    timerBG:SetColorTexture(0, 0, 0, 0.5)

    local timerText = timerBar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    timerText:SetPoint("CENTER", timerBar, "CENTER")
    f.timerBar = timerBar
    f.timerText = timerText

    return f
end

--------------------------------------------------------------------------------
-- Autocomplete Logic
--------------------------------------------------------------------------------

--- Get autocomplete candidates matching the given text.
-- Sources: EPGP standings + current raid members.
-- @param text string The search text (case-insensitive matching).
-- @return array of {name, class} entries, max MAX_AUTOCOMPLETE_RESULTS.
function AwardFrame:GetAutocompleteCandidates(text)
    if not text or text == "" then
        return {}
    end

    local searchText = strlower(text)
    local seen = {}
    local candidates = {}

    -- Source 1: EPGP standings
    local EPGP = SimpleEPGP:GetModule("EPGP")
    local standings = EPGP:GetStandings()
    for i = 1, #standings do
        local entry = standings[i]
        if entry.name and not seen[entry.name] then
            local lowerName = strlower(entry.name)
            if strsub(lowerName, 1, #searchText) == searchText
                or lowerName:find(searchText, 1, true) then
                seen[entry.name] = true
                candidates[#candidates + 1] = {
                    name = entry.name,
                    class = entry.class or "UNKNOWN",
                }
            end
        end
    end

    -- Source 2: Current raid members (may include players not in standings)
    if IsInRaid() then
        local numRaid = GetNumGroupMembers()
        for i = 1, numRaid do
            local name, _, _, _, class = GetRaidRosterInfo(i)
            if name then
                local shortName = StripRealm(name)
                if not seen[shortName] then
                    local lowerName = strlower(shortName)
                    if strsub(lowerName, 1, #searchText) == searchText
                        or lowerName:find(searchText, 1, true) then
                        seen[shortName] = true
                        candidates[#candidates + 1] = {
                            name = shortName,
                            class = class or "UNKNOWN",
                        }
                    end
                end
            end
        end
    end

    -- Sort alphabetically
    table.sort(candidates, function(a, b) return a.name < b.name end)

    -- Limit to max results
    if #candidates > MAX_AUTOCOMPLETE_RESULTS then
        local trimmed = {}
        for i = 1, MAX_AUTOCOMPLETE_RESULTS do
            trimmed[i] = candidates[i]
        end
        return trimmed
    end

    return candidates
end

--- Refresh the autocomplete dropdown with current results.
local function RefreshAutocompleteDropdown()
    if not awardFrame then return end

    local dropdown = awardFrame.autocompleteDropdown
    local count = #autocompleteResults

    if count == 0 then
        dropdown:Hide()
        return
    end

    -- Size the dropdown to fit results
    dropdown:SetHeight(count * AUTOCOMPLETE_ROW_HEIGHT + 4)

    for i, row in ipairs(dropdown.rows) do
        local candidate = autocompleteResults[i]
        if candidate then
            local cc = RAID_CLASS_COLORS[candidate.class]
            if cc then
                row.classBar:SetColorTexture(cc.r, cc.g, cc.b)
                row.nameText:SetTextColor(cc.r, cc.g, cc.b)
            else
                row.classBar:SetColorTexture(0.5, 0.5, 0.5)
                row.nameText:SetTextColor(1, 1, 1)
            end
            row.nameText:SetText(candidate.name)

            -- Keyboard highlight
            if i == autocompleteHighlightIndex then
                row.highlight:Show()
            else
                row.highlight:Hide()
            end

            row.candidateData = candidate
            row:SetScript("OnClick", function(self)
                AwardFrame:SelectAutocompletePlayer(self.candidateData.name, self.candidateData.class)
            end)
            row:Show()
        else
            row:Hide()
            row.candidateData = nil
        end
    end

    dropdown:Show()
end

function AwardFrame:HideAutocomplete()
    autocompleteResults = {}
    autocompleteHighlightIndex = 0
    if awardFrame and awardFrame.autocompleteDropdown then
        awardFrame.autocompleteDropdown:Hide()
    end
end

function AwardFrame:OnSearchTextChanged(text)
    if not text or text == "" then
        self:HideAutocomplete()
        return
    end

    autocompleteResults = self:GetAutocompleteCandidates(text)
    autocompleteHighlightIndex = 0
    RefreshAutocompleteDropdown()
end

function AwardFrame:OnSearchEnterPressed()
    if autocompleteHighlightIndex > 0 and autocompleteResults[autocompleteHighlightIndex] then
        local candidate = autocompleteResults[autocompleteHighlightIndex]
        self:SelectAutocompletePlayer(candidate.name, candidate.class)
    elseif #autocompleteResults == 1 then
        -- Auto-select if exactly one match
        local candidate = autocompleteResults[1]
        self:SelectAutocompletePlayer(candidate.name, candidate.class)
    end
end

function AwardFrame:OnSearchArrowKey(direction)
    if #autocompleteResults == 0 then return end

    autocompleteHighlightIndex = autocompleteHighlightIndex + direction
    if autocompleteHighlightIndex < 1 then
        autocompleteHighlightIndex = #autocompleteResults
    elseif autocompleteHighlightIndex > #autocompleteResults then
        autocompleteHighlightIndex = 1
    end

    RefreshAutocompleteDropdown()
end

--- Select a player from autocomplete for manual award.
-- @param name string Player name
-- @param class string WoW class token
function AwardFrame:SelectAutocompletePlayer(name, class)
    -- Look up real EP/GP/PR if available
    local EPGP = SimpleEPGP:GetModule("EPGP")
    local playerInfo = EPGP:GetPlayerInfo(name)

    selectedBidder = {
        name = name,
        class = class,
        bidType = manualBidType,
        ep = playerInfo and playerInfo.ep or 0,
        gp = playerInfo and playerInfo.gp or 0,
        pr = playerInfo and playerInfo.pr or 0,
        isManual = true,  -- Flag indicating this was a manual selection
    }

    -- Update UI
    if awardFrame then
        awardFrame.searchBox:SetText(name)
        awardFrame.searchBox:ClearFocus()
    end
    self:HideAutocomplete()
    self:UpdateButtonStates()
    -- Also refresh bid display to clear any bid-row selection highlighting
    if activeSessionId then
        RefreshBidDisplay()
    end
end

--------------------------------------------------------------------------------
-- Item List Management
--------------------------------------------------------------------------------

local selectedItemIndex

local function RefreshItemButtons()
    if not awardFrame then return end

    -- Ensure enough buttons exist
    for i = #awardFrame.itemButtons + 1, #eligibleItems do
        local btn = CreateItemButton(awardFrame.itemArea, i)
        btn:SetPoint("TOPLEFT", awardFrame.itemArea, "TOPLEFT", 8 + (i - 1) * 42, -8)
        awardFrame.itemButtons[i] = btn
    end

    -- Update all buttons
    for i, btn in ipairs(awardFrame.itemButtons) do
        local itemData = eligibleItems[i]
        if itemData then
            local _, _, quality, _, _, _, _, _, _, texture = GetItemInfo(itemData.itemLink)
            if texture then
                btn.icon:SetTexture(texture)
            else
                btn.icon:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
            end

            if quality then
                local r, g, b = GetItemQualityColor(quality)
                btn.border:SetVertexColor(r, g, b)
            end

            btn.itemData = itemData
            btn.index = i
            btn:SetScript("OnClick", function(self)
                selectedItemIndex = self.index
                AwardFrame:SelectItem(self.index)
            end)
            btn:SetScript("OnEnter", function(self)
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                GameTooltip:SetHyperlink(itemData.itemLink)
                GameTooltip:Show()
            end)
            btn:SetScript("OnLeave", function()
                GameTooltip:Hide()
            end)
            btn:Show()
        else
            btn:Hide()
        end
    end
end

--------------------------------------------------------------------------------
-- Bid Display
--------------------------------------------------------------------------------

local function PopulateBidSection(section, bids)
    for i, row in ipairs(section.rows) do
        local bid = bids[i]
        if bid then
            -- Class color
            local cc = RAID_CLASS_COLORS[bid.class]
            if cc then
                row.classBar:SetColorTexture(cc.r, cc.g, cc.b)
                row.nameText:SetTextColor(cc.r, cc.g, cc.b)
            else
                row.classBar:SetColorTexture(0.5, 0.5, 0.5)
                row.nameText:SetTextColor(1, 1, 1)
            end

            row.nameText:SetText(bid.name)
            row.prText:SetText(format("PR: %.2f", bid.pr))
            row.epText:SetText(format("EP: %d", bid.ep))
            row.gpText:SetText(format("GP: %d", bid.gp))

            row.bidder = bid
            row:SetScript("OnClick", function(self)
                AwardFrame:SelectBidder(self.bidder)
            end)
            row:Show()

            -- Show selection state (only if not a manual/autocomplete selection)
            if selectedBidder and not selectedBidder.isManual
                and selectedBidder.name == bid.name
                and selectedBidder.bidType == bid.bidType then
                row.selected:Show()
            else
                row.selected:Hide()
            end
        else
            row:Hide()
            row.bidder = nil
        end
    end
end

RefreshBidDisplay = function()
    if not awardFrame or not activeSessionId then return end

    local LootMaster = SimpleEPGP:GetModule("LootMaster")
    local bids = LootMaster:GetSessionBids(activeSessionId)
    if not bids then return end

    PopulateBidSection(awardFrame.msSection, bids.ms)
    PopulateBidSection(awardFrame.osSection, bids.os)
    PopulateBidSection(awardFrame.deSection, bids.de)

    AwardFrame:UpdateButtonStates()
end

--------------------------------------------------------------------------------
-- Button State Management
--------------------------------------------------------------------------------

--- Centralized button state update. Called whenever state changes.
function AwardFrame:UpdateButtonStates()
    if not awardFrame then return end

    local hasItem = selectedItemIndex ~= nil
    local hasSession = activeSessionId ~= nil
    local hasBidder = selectedBidder ~= nil

    if not hasItem then
        -- No item selected
        StyleButton(awardFrame.startBtn, false)
        StyleButton(awardFrame.cancelBtn, false)
        StyleButton(awardFrame.awardBtn, false)
        awardFrame.awardBtn:SetText("Award")
        awardFrame.statusText:SetText("Select an item to begin")
    elseif not hasSession then
        -- Item selected but no session
        StyleButton(awardFrame.startBtn, true)
        StyleButton(awardFrame.cancelBtn, false)
        StyleButton(awardFrame.awardBtn, false)
        awardFrame.awardBtn:SetText("Award")
        awardFrame.statusText:SetText("Click Start Bidding to open bids")
    elseif not hasBidder then
        -- Session active, no bidder selected
        StyleButton(awardFrame.startBtn, false)
        StyleButton(awardFrame.cancelBtn, true, COLOR_CANCEL)
        StyleButton(awardFrame.awardBtn, false)
        awardFrame.awardBtn:SetText("Award")
        awardFrame.statusText:SetText("Waiting for bids... Select a bidder or use manual award")
    else
        -- Session active, bidder selected
        StyleButton(awardFrame.startBtn, false)
        StyleButton(awardFrame.cancelBtn, true, COLOR_CANCEL)
        StyleButton(awardFrame.awardBtn, true, COLOR_AWARD)
        awardFrame.awardBtn:SetText(format("Award to %s", selectedBidder.name))
        local bidLabel = selectedBidder.bidType or "?"
        if selectedBidder.isManual then
            awardFrame.statusText:SetText(format("Manual award: %s (%s)", selectedBidder.name, bidLabel))
        else
            awardFrame.statusText:SetText(format("Selected: %s (%s bid)", selectedBidder.name, bidLabel))
        end
    end
end

--------------------------------------------------------------------------------
-- Session / Selection Handlers
--------------------------------------------------------------------------------

function AwardFrame:SelectItem(index)
    local itemData = eligibleItems[index]
    if not itemData then return end

    -- If this item already has an active session, just view it
    -- Otherwise the ML needs to click Start Bidding
    selectedBidder = nil
    selectedItemIndex = index

    -- Clear autocomplete search
    if awardFrame and awardFrame.searchBox then
        awardFrame.searchBox:SetText("")
    end
    self:HideAutocomplete()

    -- Check if a session exists for this item
    local LootMaster = SimpleEPGP:GetModule("LootMaster")
    -- Sessions are tracked by ID; find if one matches this itemLink
    if LootMaster.sessions then
        for sid, session in pairs(LootMaster.sessions) do
            if session.itemLink == itemData.itemLink and not session.awarded then
                activeSessionId = sid
                self:StartBidRefresh()
                self:StartTimerBar(session)
                RefreshBidDisplay()
                self:UpdateButtonStates()
                return
            end
        end
    end

    -- No active session for this item
    activeSessionId = nil
    self:StopBidRefresh()
    self:ClearBidDisplay()
    self:UpdateButtonStates()
    awardFrame.timerBar:SetValue(0)
    awardFrame.timerText:SetText("")
end

function AwardFrame:SelectBidder(bidder)
    selectedBidder = bidder
    -- Clear manual selection flag since this is from bid list
    if selectedBidder then
        selectedBidder.isManual = false
    end
    -- Clear autocomplete search box
    if awardFrame and awardFrame.searchBox then
        awardFrame.searchBox:SetText("")
    end
    self:HideAutocomplete()
    RefreshBidDisplay()
end

function AwardFrame:OnStartBidding()
    if not selectedItemIndex then return end
    local itemData = eligibleItems[selectedItemIndex]
    if not itemData then return end

    local LootMaster = SimpleEPGP:GetModule("LootMaster")
    local sessionId = LootMaster:StartSession(itemData.itemLink, itemData.gpCost)
    activeSessionId = sessionId

    local session = LootMaster.sessions[sessionId]
    if session then
        self:StartTimerBar(session)
    end

    self:StartBidRefresh()
    self:UpdateButtonStates()
end

function AwardFrame:OnCancelSession()
    if not activeSessionId then return end
    local LootMaster = SimpleEPGP:GetModule("LootMaster")
    LootMaster:CancelSession(activeSessionId)
    activeSessionId = nil
    selectedBidder = nil
    self:StopBidRefresh()
    self:ClearBidDisplay()
    self:UpdateButtonStates()
    awardFrame.timerBar:SetValue(0)
    awardFrame.timerText:SetText("")
end

function AwardFrame:OnAwardClick()
    if not selectedBidder or not activeSessionId then return end

    local LootMaster = SimpleEPGP:GetModule("LootMaster")
    local session = LootMaster.sessions[activeSessionId]
    if not session then return end

    local GPCalc = SimpleEPGP:GetModule("GPCalc")
    local gpCharged = GPCalc:GetBidGP(session.itemLink, selectedBidder.bidType) or 0

    -- Show confirmation dialog -- pass data table as 4th arg so OnShow/OnAccept can access it
    local data = {
        sessionId = activeSessionId,
        name = selectedBidder.name,
        bidType = selectedBidder.bidType,
        itemLink = session.itemLink,
        gpCharged = gpCharged,
    }
    StaticPopup_Show("SEPGP_AWARD_CONFIRM", session.itemLink, selectedBidder.name, data)
end

--------------------------------------------------------------------------------
-- Timer Bar
--------------------------------------------------------------------------------

function AwardFrame:StartTimerBar(session)
    if not awardFrame then return end

    local db = SimpleEPGP.db
    local bidTimer = db.profile.bid_timer or 30
    local endTime = session.startTime + bidTimer

    awardFrame.timerBar:SetMinMaxValues(0, bidTimer)
    awardFrame.timerBar:SetValue(bidTimer)

    awardFrame:SetScript("OnUpdate", function()
        local remaining = endTime - time()
        if remaining < 0 then remaining = 0 end
        awardFrame.timerBar:SetValue(remaining)
        awardFrame.timerText:SetText(floor(remaining) .. "s")
        if remaining <= 5 then
            awardFrame.timerBar:SetStatusBarColor(1.0, 0.2, 0.2)
        else
            awardFrame.timerBar:SetStatusBarColor(0.2, 0.6, 1.0)
        end
    end)
end

--------------------------------------------------------------------------------
-- Bid Refresh Ticker
--------------------------------------------------------------------------------

function AwardFrame:StartBidRefresh()
    self:StopBidRefresh()
    bidRefreshTicker = C_Timer.NewTicker(1, function()
        RefreshBidDisplay()
    end)
end

function AwardFrame:StopBidRefresh()
    if bidRefreshTicker then
        bidRefreshTicker:Cancel()
        bidRefreshTicker = nil
    end
end

function AwardFrame:ClearBidDisplay()
    if not awardFrame then return end
    for _, section in ipairs({awardFrame.msSection, awardFrame.osSection, awardFrame.deSection}) do
        for _, row in ipairs(section.rows) do
            row:Hide()
            row.bidder = nil
        end
    end
end

--------------------------------------------------------------------------------
-- Show / Hide
--------------------------------------------------------------------------------

function AwardFrame:ShowLoot(items)
    if not awardFrame then
        awardFrame = CreateAwardFrame()
    end

    eligibleItems = items
    activeSessionId = nil
    selectedBidder = nil
    selectedItemIndex = nil
    manualBidType = "MS"

    RefreshItemButtons()
    self:ClearBidDisplay()

    -- Reset autocomplete
    if awardFrame.searchBox then
        awardFrame.searchBox:SetText("")
    end
    self:HideAutocomplete()

    -- Reset bid type buttons
    if awardFrame.bidTypeMS then
        awardFrame.bidTypeMS.selTex:Show()
        awardFrame.bidTypeOS.selTex:Hide()
        awardFrame.bidTypeDE.selTex:Hide()
    end

    self:UpdateButtonStates()
    awardFrame.timerBar:SetValue(0)
    awardFrame.timerText:SetText("")
    awardFrame:SetScript("OnUpdate", nil)

    awardFrame:Show()
end

function AwardFrame:OnTimerExpired(sessionId, winner)
    if activeSessionId ~= sessionId then return end

    self:StopBidRefresh()
    -- Do one final refresh to show final bid state
    RefreshBidDisplay()

    -- If auto-distribute found a winner, select them
    if winner then
        self:SelectBidder(winner)
    end
end

--------------------------------------------------------------------------------
-- Test Accessors
--------------------------------------------------------------------------------

--- Get the current frame reference (for tests).
function AwardFrame:GetFrame()
    return awardFrame
end

--- Get the current manual bid type (for tests).
function AwardFrame:GetManualBidType()
    return manualBidType
end

--- Set the manual bid type (for tests).
function AwardFrame:SetManualBidType(bidType)
    manualBidType = bidType
end

--- Get the current selected bidder (for tests).
function AwardFrame:GetSelectedBidder()
    return selectedBidder
end

--- Get the active session ID (for tests).
function AwardFrame:GetActiveSessionId()
    return activeSessionId
end

--- Set the active session ID (for tests).
function AwardFrame:SetActiveSessionId(id)
    activeSessionId = id
end

--- Get the selected item index (for tests).
function AwardFrame:GetSelectedItemIndex()
    return selectedItemIndex
end

--- Set eligible items and selected index (for tests).
function AwardFrame:SetTestState(items, itemIndex, sessionId)
    eligibleItems = items or {}
    selectedItemIndex = itemIndex
    activeSessionId = sessionId
end

--------------------------------------------------------------------------------
-- Module Lifecycle
--------------------------------------------------------------------------------

function AwardFrame:OnEnable()
    local LootMaster = SimpleEPGP:GetModule("LootMaster")
    LootMaster:RegisterUICallback("ELIGIBLE_LOOT", function(items)
        self:ShowLoot(items)
    end)
    LootMaster:RegisterUICallback("TIMER_EXPIRED", function(sessionId, winner)
        self:OnTimerExpired(sessionId, winner)
    end)
end

function AwardFrame:OnDisable()
    self:StopBidRefresh()
    if awardFrame then
        awardFrame:Hide()
    end
    eligibleItems = {}
    activeSessionId = nil
    selectedBidder = nil
end
