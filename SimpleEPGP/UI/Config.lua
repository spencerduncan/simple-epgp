local SimpleEPGP = LibStub("AceAddon-3.0"):GetAddon("SimpleEPGP")
local Config = SimpleEPGP:NewModule("Config")

local pairs = pairs
local tonumber = tonumber
local tostring = tostring

-- Constants
local FRAME_WIDTH = 450
local FRAME_HEIGHT = 550
local CONTENT_HEIGHT = 620
local LABEL_X = 15
local INPUT_X = 240
local INPUT_WIDTH = 160

-- State
local frame
local widgets = {}

-- Default values for all settings, keyed by db.profile field name
local DEFAULTS = {
    base_gp            = 100,
    min_ep             = 0,
    decay_percent      = 15,
    standard_ilvl      = 120,
    quality_threshold  = 4,
    os_multiplier      = 0.5,
    de_multiplier      = 0.0,
    ep_per_boss        = 100,
    auto_ep            = true,
    standby_percent    = 1.0,
    bid_timer          = 30,
    auto_distribute    = false,
    auto_distribute_delay = 3,
    announce_channel   = "GUILD",
    announce_awards    = true,
    announce_ep        = true,
    show_gp_tooltip    = true,
}

local Utils = SimpleEPGP.UI.Utils

--- Create a section header label (delegates to Utils).
local function CreateSectionHeader(parent, text, y)
    return Utils.CreateSectionHeader(parent, text, LABEL_X, y)
end

--- Create a setting label (delegates to Utils).
local function CreateLabel(parent, text, y)
    return Utils.CreateLabel(parent, text, LABEL_X + 10, y)
end

--- Create a number/text EditBox.
local function CreateEditBox(parent, dbKey, y, width)
    width = width or INPUT_WIDTH
    local box = Utils.CreateEditBox(parent, INPUT_X, y, width, 20)
    box.dbKey = dbKey
    widgets[dbKey] = box
    return box
end

--- Create a Slider (plain — avoids deprecated OptionsSliderTemplate).
local function CreateSlider(parent, dbKey, y, minVal, maxVal, step)
    step = step or 1
    local slider = CreateFrame("Slider", nil, parent)
    slider:SetSize(INPUT_WIDTH, 17)
    slider:SetPoint("TOPLEFT", INPUT_X, y)
    slider:SetMinMaxValues(minVal, maxVal)
    slider:SetValueStep(step)
    slider:SetObeyStepOnDrag(true)

    -- Track background
    local track = slider:CreateTexture(nil, "BACKGROUND")
    track:SetPoint("TOPLEFT", 0, -6)
    track:SetPoint("BOTTOMRIGHT", 0, 6)
    track:SetColorTexture(0.3, 0.3, 0.3, 0.8)

    -- Thumb
    local thumb = slider:CreateTexture(nil, "OVERLAY")
    thumb:SetSize(14, 20)
    thumb:SetColorTexture(0.6, 0.6, 0.6, 1.0)
    slider:SetThumbTexture(thumb)

    -- Value label to the right of the slider
    local valText = slider:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    valText:SetPoint("LEFT", slider, "RIGHT", 8, 0)
    slider.valText = valText

    slider:SetScript("OnValueChanged", function(self, value)
        self.valText:SetText(tostring(math.floor(value)))
    end)

    slider.dbKey = dbKey
    widgets[dbKey] = slider
    return slider
end

--- Create a CheckButton.
local function CreateCheckButton(parent, text, dbKey, y)
    local cb = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
    cb:SetSize(24, 24)
    cb:SetPoint("TOPLEFT", INPUT_X, y + 3)
    cb.text:SetText(text)
    cb.text:SetFontObject("GameFontHighlight")
    cb.dbKey = dbKey
    widgets[dbKey] = cb
    return cb
end

--- Populate all widgets from the current db.profile values.
local function PopulateFromDB()
    local db = SimpleEPGP.db
    if not db then return end

    for dbKey, widget in pairs(widgets) do
        local value = db.profile[dbKey]
        if value == nil then
            value = DEFAULTS[dbKey]
        end

        if widget:IsObjectType("EditBox") then
            widget:SetText(tostring(value or ""))
        elseif widget:IsObjectType("Slider") then
            widget:SetValue(tonumber(value) or 0)
        elseif widget:IsObjectType("CheckButton") then
            widget:SetChecked(value and true or false)
        end
    end
end

--- Write all widget values back to db.profile.
local function SaveToDB()
    local db = SimpleEPGP.db
    if not db then return end

    for dbKey, widget in pairs(widgets) do
        if widget:IsObjectType("EditBox") then
            local text = widget:GetText()
            local num = tonumber(text)
            -- Store as number if it parses, otherwise string
            if num then
                db.profile[dbKey] = num
            else
                db.profile[dbKey] = text
            end
        elseif widget:IsObjectType("Slider") then
            db.profile[dbKey] = widget:GetValue()
        elseif widget:IsObjectType("CheckButton") then
            db.profile[dbKey] = widget:GetChecked() and true or false
        end
    end

    SimpleEPGP:Print("Settings saved.")
end

--- Reset all settings to their default values.
local function ResetToDefaults()
    local db = SimpleEPGP.db
    if not db then return end

    for dbKey, default in pairs(DEFAULTS) do
        db.profile[dbKey] = default
    end

    PopulateFromDB()
    SimpleEPGP:Print("Settings reset to defaults.")
end

local function CreateFrame_()
    frame = Utils.CreateStandardFrame({
        name = "SimpleEPGPConfigFrame",
        width = FRAME_WIDTH,
        height = FRAME_HEIGHT,
        title = "SimpleEPGP Settings",
        onClose = function() Config:Hide() end,
    })

    -- ScrollFrame for the settings content (plain — avoids deprecated UIPanelScrollFrameTemplate)
    local scrollFrame = CreateFrame("ScrollFrame", nil, frame)
    scrollFrame:SetPoint("TOPLEFT", 8, -32)
    scrollFrame:SetPoint("BOTTOMRIGHT", -28, 44)

    local content = CreateFrame("Frame", nil, scrollFrame)
    content:SetSize(FRAME_WIDTH - 50, CONTENT_HEIGHT)
    scrollFrame:SetScrollChild(content)

    -- Scroll bar
    local scrollBar = Utils.CreateScrollbar({
        parent = frame,
        topOffset = -32,
        bottomOffset = 44,
        onChange = function(_, value)
            scrollFrame:SetVerticalScroll(value)
        end,
    })
    local maxScroll = math.max(0, CONTENT_HEIGHT - (FRAME_HEIGHT - 76))
    scrollBar:SetMinMaxValues(0, maxScroll)

    -- Mouse wheel scrolling on the config frame
    Utils.EnableMouseWheelScroll(frame, scrollBar, 20)

    -- Build all settings sections
    local y = -10

    -- === Core EPGP ===
    CreateSectionHeader(content, "Core EPGP", y)
    y = y - 22
    CreateLabel(content, "Base GP", y)
    CreateEditBox(content, "base_gp", y)
    y = y - 28
    CreateLabel(content, "Min EP", y)
    CreateEditBox(content, "min_ep", y)
    y = y - 28
    CreateLabel(content, "Decay %", y)
    CreateSlider(content, "decay_percent", y, 0, 100, 1)

    -- === GP Calculation ===
    y = y - 40
    CreateSectionHeader(content, "GP Calculation", y)
    y = y - 22
    CreateLabel(content, "Standard ilvl", y)
    CreateEditBox(content, "standard_ilvl", y)
    y = y - 28
    CreateLabel(content, "Quality Threshold (3=Rare, 4=Epic)", y)
    CreateEditBox(content, "quality_threshold", y, 60)

    -- === Bid Multipliers ===
    y = y - 40
    CreateSectionHeader(content, "Bid Multipliers", y)
    y = y - 22
    CreateLabel(content, "OS Multiplier", y)
    CreateEditBox(content, "os_multiplier", y, 60)
    y = y - 28
    CreateLabel(content, "DE Multiplier", y)
    CreateEditBox(content, "de_multiplier", y, 60)

    -- === EP Awards ===
    y = y - 40
    CreateSectionHeader(content, "EP Awards", y)
    y = y - 22
    CreateLabel(content, "EP per Boss", y)
    CreateEditBox(content, "ep_per_boss", y)
    y = y - 28
    CreateLabel(content, "Auto EP on Boss Kill", y)
    CreateCheckButton(content, "", "auto_ep", y)
    y = y - 28
    CreateLabel(content, "Standby % (0.0-1.0)", y)
    CreateEditBox(content, "standby_percent", y, 60)

    -- === Loot Distribution ===
    y = y - 40
    CreateSectionHeader(content, "Loot Distribution", y)
    y = y - 22
    CreateLabel(content, "Bid Timer (seconds)", y)
    CreateEditBox(content, "bid_timer", y, 60)
    y = y - 28
    CreateLabel(content, "Auto-Distribute", y)
    CreateCheckButton(content, "", "auto_distribute", y)
    y = y - 28
    CreateLabel(content, "Auto-Distribute Delay (sec)", y)
    CreateEditBox(content, "auto_distribute_delay", y, 60)

    -- === Announcements ===
    y = y - 40
    CreateSectionHeader(content, "Announcements", y)
    y = y - 22
    CreateLabel(content, "Announce Channel", y)
    CreateEditBox(content, "announce_channel", y, 100)
    y = y - 28
    CreateLabel(content, "Announce Awards", y)
    CreateCheckButton(content, "", "announce_awards", y)
    y = y - 28
    CreateLabel(content, "Announce EP", y)
    CreateCheckButton(content, "", "announce_ep", y)

    -- === Tooltip ===
    y = y - 40
    CreateSectionHeader(content, "Tooltip", y)
    y = y - 22
    CreateLabel(content, "Show GP in Tooltips", y)
    CreateCheckButton(content, "", "show_gp_tooltip", y)

    -- Bottom buttons (on the main frame, not scrolled)
    local saveBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    saveBtn:SetSize(100, 24)
    saveBtn:SetPoint("BOTTOMRIGHT", -40, 12)
    saveBtn:SetText("Save")
    saveBtn:SetScript("OnClick", SaveToDB)

    local resetBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    resetBtn:SetSize(120, 24)
    resetBtn:SetPoint("BOTTOMLEFT", 12, 12)
    resetBtn:SetText("Reset Defaults")
    resetBtn:SetScript("OnClick", ResetToDefaults)

end

function Config:Show()
    if not frame then
        CreateFrame_()
    end
    PopulateFromDB()
    frame:Show()
end

function Config:Hide()
    if frame then
        frame:Hide()
    end
end

function Config:Toggle()
    if frame and frame:IsShown() then
        self:Hide()
    else
        self:Show()
    end
end
