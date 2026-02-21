local SimpleEPGP = LibStub("AceAddon-3.0"):GetAddon("SimpleEPGP")
local AwardFrame = SimpleEPGP:NewModule("AwardFrame", "AceEvent-3.0")

local GetItemInfo = GetItemInfo
local GetItemQualityColor = GetItemQualityColor
local RAID_CLASS_COLORS = RAID_CLASS_COLORS
local time = time
local floor = math.floor
local format = string.format
local pairs = pairs
local ipairs = ipairs

-- Main frame (created lazily)
local awardFrame
-- Current state
local eligibleItems = {}
local activeSessionId
local selectedBidder  -- {name, bidType}
-- Bid refresh ticker
local bidRefreshTicker

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
    tileEdge = true,
    tileSize = 32,
    edgeSize = 16,
    insets = { left = 4, right = 4, top = 4, bottom = 4 },
}

local SECTION_BACKDROP = {
    bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    tile = true,
    tileEdge = true,
    tileSize = 16,
    edgeSize = 12,
    insets = { left = 3, right = 3, top = 3, bottom = 3 },
}

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
-- Frame Creation (lazy)
--------------------------------------------------------------------------------

local function CreateAwardFrame()
    local f = CreateFrame("Frame", "SimpleEPGPAwardFrame", UIParent, "BackdropTemplate")
    f:SetSize(500, 450)
    f:SetPoint("CENTER", UIParent, "CENTER")
    f:SetFrameStrata("DIALOG")
    f:SetBackdrop(BACKDROP_INFO)
    f:SetBackdropColor(0, 0, 0, 0.9)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    f:SetClampedToScreen(true)
    f:Hide()

    -- Add to UISpecialFrames so Escape closes it
    tinsert(UISpecialFrames, "SimpleEPGPAwardFrame")

    -- Title
    local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOP", f, "TOP", 0, -12)
    title:SetText("SimpleEPGP - Loot Distribution")
    f.title = title

    -- Close button
    local closeBtn = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    closeBtn:SetPoint("TOPRIGHT", f, "TOPRIGHT", -2, -2)

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

    -- Bottom controls area
    -- Start Bidding button
    local startBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    startBtn:SetSize(120, 24)
    startBtn:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 12, 38)
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
    awardBtn:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -12, 38)
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

            -- Show selection state
            if selectedBidder and selectedBidder.name == bid.name and selectedBidder.bidType == bid.bidType then
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

local function RefreshBidDisplay()
    if not awardFrame or not activeSessionId then return end

    local LootMaster = SimpleEPGP:GetModule("LootMaster")
    local bids = LootMaster:GetSessionBids(activeSessionId)
    if not bids then return end

    PopulateBidSection(awardFrame.msSection, bids.ms)
    PopulateBidSection(awardFrame.osSection, bids.os)
    PopulateBidSection(awardFrame.deSection, bids.de)

    -- Update award button text
    if selectedBidder then
        awardFrame.awardBtn:SetText(format("Award to %s", selectedBidder.name))
        awardFrame.awardBtn:SetEnabled(true)
    else
        awardFrame.awardBtn:SetText("Award")
        awardFrame.awardBtn:SetEnabled(false)
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
                awardFrame.startBtn:SetEnabled(false)
                awardFrame.cancelBtn:SetEnabled(true)
                return
            end
        end
    end

    -- No active session for this item
    activeSessionId = nil
    self:StopBidRefresh()
    self:ClearBidDisplay()
    awardFrame.startBtn:SetEnabled(true)
    awardFrame.cancelBtn:SetEnabled(false)
    awardFrame.awardBtn:SetEnabled(false)
    awardFrame.awardBtn:SetText("Award")
    awardFrame.timerBar:SetValue(0)
    awardFrame.timerText:SetText("")
end

function AwardFrame:SelectBidder(bidder)
    selectedBidder = bidder
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
    awardFrame.startBtn:SetEnabled(false)
    awardFrame.cancelBtn:SetEnabled(true)
end

function AwardFrame:OnCancelSession()
    if not activeSessionId then return end
    local LootMaster = SimpleEPGP:GetModule("LootMaster")
    LootMaster:CancelSession(activeSessionId)
    activeSessionId = nil
    selectedBidder = nil
    self:StopBidRefresh()
    self:ClearBidDisplay()
    awardFrame.startBtn:SetEnabled(true)
    awardFrame.cancelBtn:SetEnabled(false)
    awardFrame.awardBtn:SetEnabled(false)
    awardFrame.awardBtn:SetText("Award")
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

    -- Show confirmation dialog — pass data table as 4th arg so OnShow/OnAccept can access it
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

    RefreshItemButtons()
    self:ClearBidDisplay()

    awardFrame.startBtn:SetEnabled(false)
    awardFrame.cancelBtn:SetEnabled(false)
    awardFrame.awardBtn:SetEnabled(false)
    awardFrame.awardBtn:SetText("Award")
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
