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
    local lines = { "Name,Class,EP,GP,PR,Source" }
    for _, s in ipairs(standings) do
        local source = s.isExternal and "external" or "guild"
        lines[#lines + 1] = format("%s,%s,%d,%d,%.2f,%s", s.name, s.class, s.ep, s.gp, s.pr, source)
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

local Utils = SimpleEPGP.UI.Utils

local function CreateFrame_()
    frame = Utils.CreateStandardFrame({
        name = "SimpleEPGPExportFrame",
        width = FRAME_WIDTH,
        height = FRAME_HEIGHT,
        title = "Export Standings",
        onClose = function() ExportFrame:Hide() end,
    })

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
    local scrollBar = Utils.CreateScrollbar({
        parent = frame,
        topOffset = -56,
        bottomOffset = 44,
        onChange = function(_, value)
            scrollFrame:SetVerticalScroll(value)
        end,
    })
    -- Override default anchor to use -12 instead of -10
    scrollBar:ClearAllPoints()
    scrollBar:SetPoint("TOPRIGHT", -12, -56)
    scrollBar:SetPoint("BOTTOMRIGHT", -12, 44)

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
    Utils.EnableMouseWheelScroll(scrollFrame, scrollBar, 20)

    -- Select All button
    local selectBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    selectBtn:SetSize(90, 22)
    selectBtn:SetPoint("BOTTOMRIGHT", -12, 12)
    selectBtn:SetText("Select All")
    selectBtn:SetScript("OnClick", function()
        editBox:SetFocus()
        editBox:HighlightText()
    end)

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

--- Get the standings CSV text (for testing).
-- @return string CSV content with header and data rows
function ExportFrame:GetStandingsCSV()
    return BuildStandingsCSV()
end
