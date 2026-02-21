local SimpleEPGP = LibStub("AceAddon-3.0"):GetAddon("SimpleEPGP")
local LootPopup = SimpleEPGP:NewModule("LootPopup", "AceEvent-3.0")

local GetItemInfo = GetItemInfo
local GetItemQualityColor = GetItemQualityColor
local time = time
local floor = math.floor
local format = string.format

-- Popup frame (created lazily)
local popupFrame
-- Queue of pending offers when popup is already showing
local offerQueue = {}
-- Currently displayed session
local currentSessionId

--------------------------------------------------------------------------------
-- Frame Creation (lazy)
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

local function CreateBidButton(parent, label, r, g, b, xOffset)
    local btn = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    btn:SetSize(60, 22)
    btn:SetPoint("BOTTOMLEFT", parent, "BOTTOMLEFT", xOffset, 32)
    btn:SetText(label)
    btn:GetFontString():SetTextColor(r, g, b)
    return btn
end

local function CreatePopupFrame()
    local f = CreateFrame("Frame", "SimpleEPGPLootPopup", UIParent, "BackdropTemplate")
    f:SetSize(280, 120)
    f:SetPoint("TOP", UIParent, "TOP", 0, -120)
    f:SetFrameStrata("DIALOG")
    f:SetBackdrop(BACKDROP_INFO)
    f:SetBackdropColor(0, 0, 0, 0.85)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    f:SetClampedToScreen(true)
    f:Hide()

    -- Item icon
    local icon = f:CreateTexture(nil, "ARTWORK")
    icon:SetSize(32, 32)
    icon:SetPoint("TOPLEFT", f, "TOPLEFT", 12, -12)
    f.icon = icon

    -- Item name
    local nameText = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    nameText:SetPoint("LEFT", icon, "RIGHT", 8, 0)
    nameText:SetPoint("RIGHT", f, "RIGHT", -12, 0)
    nameText:SetJustifyH("LEFT")
    nameText:SetWordWrap(false)
    f.nameText = nameText

    -- GP costs line
    local gpText = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    gpText:SetPoint("TOPLEFT", icon, "BOTTOMLEFT", 0, -6)
    gpText:SetPoint("RIGHT", f, "RIGHT", -12, 0)
    gpText:SetJustifyH("LEFT")
    f.gpText = gpText

    -- Bid buttons: MS, OS, DE, Pass
    local btnMS = CreateBidButton(f, "MS", 0.1, 1.0, 0.1, 12)
    local btnOS = CreateBidButton(f, "OS", 1.0, 1.0, 0.1, 78)
    local btnDE = CreateBidButton(f, "DE", 0.7, 0.7, 0.7, 144)
    local btnPass = CreateBidButton(f, "Pass", 1.0, 0.2, 0.2, 210)
    f.btnMS = btnMS
    f.btnOS = btnOS
    f.btnDE = btnDE
    f.btnPass = btnPass

    -- Bid status text (shown after bidding, replaces buttons visually)
    local bidStatus = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    bidStatus:SetPoint("BOTTOM", f, "BOTTOM", 0, 36)
    bidStatus:Hide()
    f.bidStatus = bidStatus

    -- Timer bar
    local timerBar = CreateFrame("StatusBar", nil, f)
    timerBar:SetSize(256, 12)
    timerBar:SetPoint("BOTTOM", f, "BOTTOM", 0, 8)
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
-- Bid Button Handlers
--------------------------------------------------------------------------------

local function SetButtonsEnabled(enabled)
    if not popupFrame then return end
    local state = enabled and true or false
    popupFrame.btnMS:SetEnabled(state)
    popupFrame.btnOS:SetEnabled(state)
    popupFrame.btnDE:SetEnabled(state)
    popupFrame.btnPass:SetEnabled(state)
end

local function ShowBidStatus(bidType)
    if not popupFrame then return end
    popupFrame.btnMS:Hide()
    popupFrame.btnOS:Hide()
    popupFrame.btnDE:Hide()
    popupFrame.btnPass:Hide()
    popupFrame.bidStatus:SetText("Bid: " .. bidType)
    popupFrame.bidStatus:Show()
end

local function OnBidClick(bidType)
    if not currentSessionId then return end
    local LootMaster = SimpleEPGP:GetModule("LootMaster")
    LootMaster:SubmitBid(currentSessionId, bidType)
    SetButtonsEnabled(false)
    ShowBidStatus(bidType)
end

--------------------------------------------------------------------------------
-- Display Logic
--------------------------------------------------------------------------------

local function ResetPopup()
    if not popupFrame then return end
    popupFrame.btnMS:Show()
    popupFrame.btnOS:Show()
    popupFrame.btnDE:Show()
    popupFrame.btnPass:Show()
    SetButtonsEnabled(true)
    popupFrame.bidStatus:Hide()
    popupFrame.timerBar:SetValue(1)
    popupFrame.timerText:SetText("")
    popupFrame:SetScript("OnUpdate", nil)
end

--- Show the popup for an offer.
-- @param sessionId number
-- @param itemLink string
-- @param gpCost number Base GP cost from the offer message
function LootPopup:ShowOffer(sessionId, itemLink, gpCost)
    -- If popup is already showing, queue this offer
    if popupFrame and popupFrame:IsShown() then
        offerQueue[#offerQueue + 1] = {
            sessionId = sessionId,
            itemLink = itemLink,
            gpCost = gpCost,
        }
        return
    end

    if not popupFrame then
        popupFrame = CreatePopupFrame()
    end

    ResetPopup()
    currentSessionId = sessionId

    -- Get item display info
    local itemName, _, quality, _, _, _, _, _, _, texture = GetItemInfo(itemLink)
    if itemName then
        local r, g, b = GetItemQualityColor(quality)
        popupFrame.icon:SetTexture(texture)
        popupFrame.nameText:SetText(itemName)
        popupFrame.nameText:SetTextColor(r, g, b)
    else
        popupFrame.icon:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
        popupFrame.nameText:SetText(itemLink)
        popupFrame.nameText:SetTextColor(1, 1, 1)
    end

    -- Calculate GP costs for each bid type
    local GPCalc = SimpleEPGP:GetModule("GPCalc")
    local msGP = GPCalc:GetBidGP(itemLink, "MS") or gpCost
    local osGP = GPCalc:GetBidGP(itemLink, "OS") or floor(gpCost * 0.5)
    local deGP = GPCalc:GetBidGP(itemLink, "DE") or 0

    popupFrame.gpText:SetText(format("MS: %d GP  |  OS: %d GP  |  DE: %d GP", msGP, osGP, deGP))

    -- Update button labels with GP costs
    popupFrame.btnMS:SetText(format("MS (%d)", msGP))
    popupFrame.btnOS:SetText(format("OS (%d)", osGP))
    popupFrame.btnDE:SetText(format("DE (%d)", deGP))

    -- Wire button click handlers
    popupFrame.btnMS:SetScript("OnClick", function() OnBidClick("MS") end)
    popupFrame.btnOS:SetScript("OnClick", function() OnBidClick("OS") end)
    popupFrame.btnDE:SetScript("OnClick", function() OnBidClick("DE") end)
    popupFrame.btnPass:SetScript("OnClick", function() OnBidClick("PASS") end)

    -- Timer bar countdown
    local db = SimpleEPGP.db
    local bidTimer = db.profile.bid_timer or 30
    local startTime = time()
    local endTime = startTime + bidTimer

    popupFrame.timerBar:SetMinMaxValues(0, bidTimer)
    popupFrame.timerBar:SetValue(bidTimer)

    popupFrame:SetScript("OnUpdate", function()
        local remaining = endTime - time()
        if remaining < 0 then remaining = 0 end
        popupFrame.timerBar:SetValue(remaining)
        popupFrame.timerText:SetText(floor(remaining) .. "s")
        if remaining <= 5 then
            popupFrame.timerBar:SetStatusBarColor(1.0, 0.2, 0.2)
        else
            popupFrame.timerBar:SetStatusBarColor(0.2, 0.6, 1.0)
        end
    end)

    popupFrame:Show()
end

--- Dismiss the popup and show next queued offer if any.
local function DismissPopup()
    if popupFrame then
        popupFrame:Hide()
        popupFrame:SetScript("OnUpdate", nil)
    end
    currentSessionId = nil

    -- Show next queued offer
    if #offerQueue > 0 then
        local next = table.remove(offerQueue, 1)
        LootPopup:ShowOffer(next.sessionId, next.itemLink, next.gpCost)
    end
end

--- Handle an AWARD notification. Dismiss popup if it matches our session.
-- @param data table {itemLink, winner, bidType, gpCharged}
function LootPopup:OnAward(data)
    -- Dismiss regardless of session match since the item has been awarded
    if popupFrame and popupFrame:IsShown() then
        DismissPopup()
    end

    -- Also remove any queued offers for awarded items
    -- (We don't have sessionId in AWARD data, so we can't filter precisely)
end

--- Handle a CANCEL notification. Dismiss popup if it matches our session.
-- @param data table {sender, sessionId}
function LootPopup:OnCancel(data)
    if currentSessionId and data.sessionId == currentSessionId then
        DismissPopup()
        return
    end

    -- Remove from queue if queued
    for i = #offerQueue, 1, -1 do
        if offerQueue[i].sessionId == data.sessionId then
            table.remove(offerQueue, i)
            break
        end
    end
end

--------------------------------------------------------------------------------
-- Module Lifecycle
--------------------------------------------------------------------------------

function LootPopup:OnEnable()
    local LootMaster = SimpleEPGP:GetModule("LootMaster")
    LootMaster:RegisterUICallback("OFFER_RECEIVED", function(data)
        self:ShowOffer(data.sessionId, data.itemLink, data.gpCost)
    end)
    LootMaster:RegisterUICallback("AWARD_RECEIVED", function(data)
        self:OnAward(data)
    end)
    LootMaster:RegisterUICallback("CANCEL_RECEIVED", function(data)
        self:OnCancel(data)
    end)
end

function LootPopup:OnDisable()
    if popupFrame then
        popupFrame:Hide()
    end
    offerQueue = {}
    currentSessionId = nil
end
