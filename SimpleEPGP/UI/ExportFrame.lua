local SimpleEPGP = LibStub("AceAddon-3.0"):GetAddon("SimpleEPGP")
local ExportFrame = SimpleEPGP:NewModule("ExportFrame")

local format = string.format
local tconcat = table.concat

-- Constants
local FRAME_WIDTH = 400
local FRAME_HEIGHT = 300

-- State
local frame
local editBox
local activeTab = "standings"

local function BuildStandingsCSV()
    local EPGP = SimpleEPGP:GetModule("EPGP")
    local standings = EPGP:GetStandings()
    local lines = { "Name,Class,EP,GP,PR" }
    for _, s in ipairs(standings) do
        lines[#lines + 1] = format("%s,%s,%d,%d,%.2f", s.name, s.class, s.ep, s.gp, s.pr)
    end
    return tconcat(lines, "\n")
end

local function BuildLogCSV()
    local Log = SimpleEPGP:GetModule("Log", true)
    if Log then
        return Log:ExportCSV()
    end
    return "No log data available."
end

local function RefreshContent()
    if not editBox then return end
    local text
    if activeTab == "standings" then
        text = BuildStandingsCSV()
    else
        text = BuildLogCSV()
    end
    editBox:SetText(text)
    editBox:HighlightText(0, 0) -- Clear highlight
    editBox:SetCursorPosition(0)
end

local function CreateFrame_()
    frame = CreateFrame("Frame", "SimpleEPGPExportFrame", UIParent, "BackdropTemplate")
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
    title:SetText("Export Standings")
    frame.title = title

    -- Close button
    local closeBtn = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    closeBtn:SetPoint("TOPRIGHT", -2, -2)
    closeBtn:SetScript("OnClick", function() ExportFrame:Hide() end)

    -- Tab buttons
    local standingsTab = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    standingsTab:SetSize(100, 22)
    standingsTab:SetPoint("TOPLEFT", 12, -30)
    standingsTab:SetText("Standings")
    standingsTab:SetScript("OnClick", function()
        activeTab = "standings"
        frame.title:SetText("Export Standings")
        RefreshContent()
    end)

    local logTab = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    logTab:SetSize(100, 22)
    logTab:SetPoint("LEFT", standingsTab, "RIGHT", 4, 0)
    logTab:SetText("Log Export")
    logTab:SetScript("OnClick", function()
        activeTab = "log"
        frame.title:SetText("Export Log")
        RefreshContent()
    end)

    -- ScrollFrame for the EditBox (plain — avoids deprecated UIPanelScrollFrameTemplate)
    local scrollFrame = CreateFrame("ScrollFrame", "SimpleEPGPExportScrollFrame", frame)
    scrollFrame:SetPoint("TOPLEFT", 12, -56)
    scrollFrame:SetPoint("BOTTOMRIGHT", -32, 44)

    editBox = CreateFrame("EditBox", nil, scrollFrame)
    editBox:SetMultiLine(true)
    editBox:SetFontObject("ChatFontNormal")
    editBox:SetWidth(FRAME_WIDTH - 60)
    editBox:SetAutoFocus(false)
    editBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    scrollFrame:SetScrollChild(editBox)

    -- Scroll bar
    local scrollBar = CreateFrame("Slider", nil, frame)
    scrollBar:SetPoint("TOPRIGHT", -12, -56)
    scrollBar:SetPoint("BOTTOMRIGHT", -12, 44)
    scrollBar:SetWidth(12)
    scrollBar:SetOrientation("VERTICAL")
    scrollBar:SetMinMaxValues(0, 1)
    scrollBar:SetValueStep(1)
    scrollBar:SetObeyStepOnDrag(true)
    scrollBar:SetValue(0)

    local eTrack = scrollBar:CreateTexture(nil, "BACKGROUND")
    eTrack:SetAllPoints()
    eTrack:SetColorTexture(0.1, 0.1, 0.1, 0.3)

    local eThumb = scrollBar:CreateTexture(nil, "OVERLAY")
    eThumb:SetSize(12, 40)
    eThumb:SetColorTexture(0.5, 0.5, 0.5, 0.6)
    scrollBar:SetThumbTexture(eThumb)

    scrollBar:SetScript("OnValueChanged", function(_, value)
        scrollFrame:SetVerticalScroll(value)
    end)

    -- Update scroll range when editbox content changes
    editBox:SetScript("OnTextChanged", function(self)
        local _, numLines = self:GetText():gsub("\n", "\n")
        numLines = (numLines or 0) + 1
        local lineHeight = 14  -- approximate ChatFontNormal line height
        local textHeight = numLines * lineHeight
        self:SetHeight(math.max(textHeight, scrollFrame:GetHeight()))
        local maxScroll = math.max(0, self:GetHeight() - scrollFrame:GetHeight())
        scrollBar:SetMinMaxValues(0, maxScroll)
    end)

    -- Mouse wheel scrolling
    scrollFrame:EnableMouseWheel(true)
    scrollFrame:SetScript("OnMouseWheel", function(_, delta)
        local current = scrollBar:GetValue()
        scrollBar:SetValue(current - delta * 20)
    end)

    -- Select All button
    local selectBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    selectBtn:SetSize(90, 22)
    selectBtn:SetPoint("BOTTOMRIGHT", -12, 12)
    selectBtn:SetText("Select All")
    selectBtn:SetScript("OnClick", function()
        editBox:SetFocus()
        editBox:HighlightText()
    end)

    -- Escape to close
    table.insert(UISpecialFrames, "SimpleEPGPExportFrame")

    frame:Hide()
end

function ExportFrame:Show()
    if not frame then
        CreateFrame_()
    end
    activeTab = "standings"
    if frame.title then
        frame.title:SetText("Export Standings")
    end
    RefreshContent()
    frame:Show()
end

function ExportFrame:Hide()
    if frame then
        frame:Hide()
    end
end

function ExportFrame:Toggle()
    if frame and frame:IsShown() then
        self:Hide()
    else
        self:Show()
    end
end
