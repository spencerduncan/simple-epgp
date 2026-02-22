-----------------------------------------------------------------------
-- UI/Utils.lua -- Shared UI utility functions
-- Extracted from duplicate boilerplate across 9 UI files.
-- Loaded before all other UI files via the .toc.
-----------------------------------------------------------------------
local SimpleEPGP = LibStub("AceAddon-3.0"):GetAddon("SimpleEPGP")

local Utils = {}
SimpleEPGP.UI = SimpleEPGP.UI or {}
SimpleEPGP.UI.Utils = Utils

-----------------------------------------------------------------------
-- Standard backdrop used by most dialog frames
-----------------------------------------------------------------------

Utils.DIALOG_BACKDROP = {
    bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
    edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
    tile = true, tileSize = 32, edgeSize = 32,
    insets = { left = 8, right = 8, top = 8, bottom = 8 },
}

-----------------------------------------------------------------------
-- CreateStandardFrame — dialog frame with backdrop, movable/draggable,
-- title bar, close button, and escape-to-close registration.
--
-- @param opts table Configuration:
--   name        (string)  Global frame name (also used for UISpecialFrames)
--   width       (number)  Frame width
--   height      (number)  Frame height
--   title       (string)  Title text (optional, nil = no title)
--   titleFont   (string)  Font object name (default "GameFontNormal")
--   strata      (string)  Frame strata (default "DIALOG")
--   backdrop    (table)   Backdrop table (default Utils.DIALOG_BACKDROP)
--   backdropColor (table) {r, g, b, a} for SetBackdropColor (optional)
--   point       (table)   Arguments for SetPoint (default {"CENTER"})
--   onClose     (function) Close button callback
-- @return frame Frame with .title and .closeBtn fields set
-----------------------------------------------------------------------
function Utils.CreateStandardFrame(opts)
    local frame = CreateFrame("Frame", opts.name, UIParent, "BackdropTemplate")
    frame:SetSize(opts.width, opts.height)
    frame:SetPoint(unpack(opts.point or { "CENTER" }))
    frame:SetFrameStrata(opts.strata or "DIALOG")
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
    frame:SetClampedToScreen(true)

    frame:SetBackdrop(opts.backdrop or Utils.DIALOG_BACKDROP)
    if opts.backdropColor then
        local c = opts.backdropColor
        frame:SetBackdropColor(c[1], c[2], c[3], c[4])
    end

    -- Title
    if opts.title then
        local title = frame:CreateFontString(nil, "OVERLAY", opts.titleFont or "GameFontNormal")
        title:SetPoint("TOP", 0, -12)
        title:SetText(opts.title)
        frame.title = title
    end

    -- Close button
    local closeBtn = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    closeBtn:SetPoint("TOPRIGHT", -2, -2)
    if opts.onClose then
        closeBtn:SetScript("OnClick", opts.onClose)
    end
    frame.closeBtn = closeBtn

    -- Escape to close
    if opts.name then
        table.insert(UISpecialFrames, opts.name)
    end

    frame:Hide()
    return frame
end

-----------------------------------------------------------------------
-- CreateSectionHeader — gold-colored section header label.
--
-- @param parent  Frame  Parent frame
-- @param text    string Header text
-- @param x       number X offset (default 15)
-- @param y       number Y offset
-- @return FontString
-----------------------------------------------------------------------
function Utils.CreateSectionHeader(parent, text, x, y)
    x = x or 15
    local fs = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    fs:SetPoint("TOPLEFT", x, y)
    fs:SetText(text)
    fs:SetTextColor(1.0, 0.82, 0)
    return fs
end

-----------------------------------------------------------------------
-- CreateLabel — standard setting/field label.
--
-- @param parent  Frame  Parent frame
-- @param text    string Label text
-- @param x       number X offset (default 25)
-- @param y       number Y offset
-- @return FontString
-----------------------------------------------------------------------
function Utils.CreateLabel(parent, text, x, y)
    x = x or 25
    local fs = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    fs:SetPoint("TOPLEFT", x, y)
    fs:SetText(text)
    return fs
end

-----------------------------------------------------------------------
-- CreateEditBox — standard InputBoxTemplate edit box with
-- escape-to-clear-focus and enter-to-clear-focus scripts.
--
-- @param parent    Frame  Parent frame
-- @param x         number X offset
-- @param y         number Y offset
-- @param width     number Width (default 160)
-- @param maxLetters number Max letters (default 100)
-- @return EditBox
-----------------------------------------------------------------------
function Utils.CreateEditBox(parent, x, y, width, maxLetters)
    width = width or 160
    maxLetters = maxLetters or 100
    local box = CreateFrame("EditBox", nil, parent, "InputBoxTemplate")
    box:SetSize(width, 20)
    box:SetPoint("TOPLEFT", x, y)
    box:SetAutoFocus(false)
    box:SetMaxLetters(maxLetters)
    box:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    box:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    return box
end

-----------------------------------------------------------------------
-- CreateScrollbar — vertical slider-based scrollbar with track and
-- thumb textures.  Matches the plain-slider pattern used throughout.
--
-- @param opts table Configuration:
--   parent       (Frame)    Parent frame
--   name         (string)   Optional global name for the slider
--   topOffset    (number)   Y offset from parent TOPRIGHT (negative)
--   bottomOffset (number)   Y offset from parent BOTTOMRIGHT (positive)
--   onChange      (function) OnValueChanged callback (receives self, value)
-- @return Slider  The scrollbar slider frame
-----------------------------------------------------------------------
function Utils.CreateScrollbar(opts)
    local scrollBar = CreateFrame("Slider", opts.name, opts.parent)
    scrollBar:SetPoint("TOPRIGHT", -10, opts.topOffset)
    scrollBar:SetPoint("BOTTOMRIGHT", -10, opts.bottomOffset)
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

    if opts.onChange then
        scrollBar:SetScript("OnValueChanged", opts.onChange)
    end

    return scrollBar
end

-----------------------------------------------------------------------
-- EnableMouseWheelScroll — wire a frame's mouse wheel to a scrollbar.
--
-- @param frame    Frame  The frame to receive mouse wheel events
-- @param scrollBar Slider The scrollbar to adjust
-- @param step     number Scroll amount per wheel tick (default 3)
-----------------------------------------------------------------------
function Utils.EnableMouseWheelScroll(frame, scrollBar, step)
    step = step or 3
    frame:EnableMouseWheel(true)
    frame:SetScript("OnMouseWheel", function(_, delta)
        local current = scrollBar:GetValue()
        scrollBar:SetValue(current - delta * step)
    end)
end
