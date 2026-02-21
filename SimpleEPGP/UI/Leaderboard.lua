local SimpleEPGP = LibStub("AceAddon-3.0"):GetAddon("SimpleEPGP")
local Leaderboard = SimpleEPGP:NewModule("Leaderboard", "AceEvent-3.0")

local format = string.format
local tinsert = table.insert
local RAID_CLASS_COLORS = RAID_CLASS_COLORS
local UnitName = UnitName
local SendChatMessage = SendChatMessage

-- UI state
local frame = nil
local rows = {}
local activeFilter = "all"  -- "all", "raiders", "online"

-- Constants
local FRAME_WIDTH = 400
local FRAME_HEIGHT = 450
local ROW_HEIGHT = 18
local HEADER_HEIGHT = 60
local MAX_VISIBLE_ROWS = 20

--------------------------------------------------------------------------------
-- Data
--------------------------------------------------------------------------------

--- Get filtered and sorted standings data.
-- @param filter string "all", "raiders", or "online"
-- @return array of standings entries
local function GetFilteredStandings(filter)
    local EPGP = SimpleEPGP:GetModule("EPGP")
    local standings = EPGP:GetStandings()
    if not standings then return {} end

    local db = SimpleEPGP.db
    local minEP = db.profile.min_ep or 0

    if filter == "all" then
        return standings
    end

    local filtered = {}
    for i = 1, #standings do
        local entry = standings[i]
        if filter == "raiders" then
            if entry.ep >= minEP then
                filtered[#filtered + 1] = entry
            end
        end
        -- "online" filter would require re-querying the guild roster
        -- for isOnline status; for now treat as "all"
    end

    return filtered
end

--------------------------------------------------------------------------------
-- Frame Creation (lazy)
--------------------------------------------------------------------------------

local function CreateRow(parent, index)
    local row = CreateFrame("Frame", nil, parent)
    row:SetHeight(ROW_HEIGHT)
    row:SetPoint("TOPLEFT", parent, "TOPLEFT", 8, -(HEADER_HEIGHT + (index - 1) * ROW_HEIGHT))
    row:SetPoint("RIGHT", parent, "RIGHT", -8, 0)

    row.rank = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    row.rank:SetPoint("LEFT", row, "LEFT", 0, 0)
    row.rank:SetWidth(30)
    row.rank:SetJustifyH("CENTER")

    row.name = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    row.name:SetPoint("LEFT", row, "LEFT", 35, 0)
    row.name:SetWidth(120)
    row.name:SetJustifyH("LEFT")

    row.ep = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    row.ep:SetPoint("LEFT", row, "LEFT", 160, 0)
    row.ep:SetWidth(65)
    row.ep:SetJustifyH("RIGHT")

    row.gp = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    row.gp:SetPoint("LEFT", row, "LEFT", 230, 0)
    row.gp:SetWidth(65)
    row.gp:SetJustifyH("RIGHT")

    row.pr = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    row.pr:SetPoint("LEFT", row, "LEFT", 300, 0)
    row.pr:SetWidth(70)
    row.pr:SetJustifyH("RIGHT")

    row.highlight = row:CreateTexture(nil, "BACKGROUND")
    row.highlight:SetAllPoints()
    row.highlight:SetColorTexture(1, 1, 1, 0.05)
    row.highlight:Hide()

    return row
end

local function CreateFilterButton(parent, label, filterKey, xOffset)
    local btn = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    btn:SetSize(90, 22)
    btn:SetPoint("TOPLEFT", parent, "TOPLEFT", xOffset, -30)
    btn:SetText(label)
    btn:SetScript("OnClick", function()
        activeFilter = filterKey
        Leaderboard:Refresh()
    end)
    return btn
end

local function CreateLeaderboardFrame()
    local f = CreateFrame("Frame", "SimpleEPGPLeaderboard", UIParent, "BackdropTemplate")
    f:SetSize(FRAME_WIDTH, FRAME_HEIGHT)
    f:SetPoint("CENTER")
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    f:SetFrameStrata("DIALOG")

    f:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile = true, tileSize = 32, edgeSize = 32,
        insets = { left = 8, right = 8, top = 8, bottom = 8 },
    })

    -- Title
    f.title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    f.title:SetPoint("TOP", f, "TOP", 0, -12)
    f.title:SetText("SimpleEPGP Leaderboard")

    -- Close button
    local closeBtn = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    closeBtn:SetPoint("TOPRIGHT", f, "TOPRIGHT", -4, -4)

    -- Filter buttons
    f.btnAll = CreateFilterButton(f, "All Members", "all", 12)
    f.btnRaiders = CreateFilterButton(f, "Raiders Only", "raiders", 108)
    f.btnOnline = CreateFilterButton(f, "Online Only", "online", 204)

    -- Column headers
    local headerY = -(HEADER_HEIGHT - 4)
    local headerFont = "GameFontNormalSmall"

    local hRank = f:CreateFontString(nil, "OVERLAY", headerFont)
    hRank:SetPoint("TOPLEFT", f, "TOPLEFT", 8, headerY)
    hRank:SetWidth(30)
    hRank:SetJustifyH("CENTER")
    hRank:SetText("#")
    hRank:SetTextColor(0.8, 0.8, 0.0)

    local hName = f:CreateFontString(nil, "OVERLAY", headerFont)
    hName:SetPoint("TOPLEFT", f, "TOPLEFT", 43, headerY)
    hName:SetText("Name")
    hName:SetTextColor(0.8, 0.8, 0.0)

    local hEP = f:CreateFontString(nil, "OVERLAY", headerFont)
    hEP:SetPoint("TOPLEFT", f, "TOPLEFT", 168, headerY)
    hEP:SetWidth(65)
    hEP:SetJustifyH("RIGHT")
    hEP:SetText("EP")
    hEP:SetTextColor(0.8, 0.8, 0.0)

    local hGP = f:CreateFontString(nil, "OVERLAY", headerFont)
    hGP:SetPoint("TOPLEFT", f, "TOPLEFT", 238, headerY)
    hGP:SetWidth(65)
    hGP:SetJustifyH("RIGHT")
    hGP:SetText("GP")
    hGP:SetTextColor(0.8, 0.8, 0.0)

    local hPR = f:CreateFontString(nil, "OVERLAY", headerFont)
    hPR:SetPoint("TOPLEFT", f, "TOPLEFT", 308, headerY)
    hPR:SetWidth(70)
    hPR:SetJustifyH("RIGHT")
    hPR:SetText("PR")
    hPR:SetTextColor(0.8, 0.8, 0.0)

    -- Create row frames
    for i = 1, MAX_VISIBLE_ROWS do
        rows[i] = CreateRow(f, i)
    end

    -- Escape-to-close
    tinsert(UISpecialFrames, "SimpleEPGPLeaderboard")

    f:Hide()
    return f
end

--------------------------------------------------------------------------------
-- Refresh Display
--------------------------------------------------------------------------------

function Leaderboard:Refresh()
    if not frame or not frame:IsShown() then return end

    local standings = GetFilteredStandings(activeFilter)
    local playerName = UnitName("player")

    for i = 1, MAX_VISIBLE_ROWS do
        local row = rows[i]
        local entry = standings[i]

        if entry then
            row:Show()

            -- Rank display: medals for top 3
            if i == 1 then
                row.rank:SetText("#1")
                row.rank:SetTextColor(1.0, 0.84, 0.0) -- gold
            elseif i == 2 then
                row.rank:SetText("#2")
                row.rank:SetTextColor(0.75, 0.75, 0.75) -- silver
            elseif i == 3 then
                row.rank:SetText("#3")
                row.rank:SetTextColor(0.80, 0.50, 0.20) -- bronze
            else
                row.rank:SetText(tostring(i))
                row.rank:SetTextColor(0.8, 0.8, 0.8)
            end

            -- Class-colored name
            local classColor = RAID_CLASS_COLORS[entry.class]
            if classColor then
                row.name:SetTextColor(classColor.r, classColor.g, classColor.b)
            else
                row.name:SetTextColor(1, 1, 1)
            end
            row.name:SetText(entry.name)

            -- EP, GP, PR
            row.ep:SetText(tostring(entry.ep))
            row.ep:SetTextColor(1, 1, 1)

            row.gp:SetText(tostring(entry.gp))
            row.gp:SetTextColor(1, 1, 1)

            row.pr:SetText(format("%.2f", entry.pr))
            row.pr:SetTextColor(0.5, 1.0, 0.5) -- green

            -- Highlight current player
            if entry.name == playerName then
                row.highlight:SetColorTexture(0.3, 0.5, 1.0, 0.15)
                row.highlight:Show()
            else
                row.highlight:Hide()
            end
        else
            row:Hide()
        end
    end
end

--------------------------------------------------------------------------------
-- Show / Hide / Toggle
--------------------------------------------------------------------------------

function Leaderboard:Show()
    if not frame then
        frame = CreateLeaderboardFrame()
    end
    frame:Show()
    self:Refresh()
end

function Leaderboard:Hide()
    if frame then
        frame:Hide()
    end
end

function Leaderboard:Toggle()
    if frame and frame:IsShown() then
        self:Hide()
    else
        self:Show()
    end
end

--------------------------------------------------------------------------------
-- Chat Announce
--------------------------------------------------------------------------------

--- Announce top N players to a chat channel.
-- @param count Number of players to announce (default 5)
-- @param channel Chat channel type (default "GUILD")
function Leaderboard:AnnounceTop(count, channel)
    count = count or 5
    channel = channel or "GUILD"

    local EPGP = SimpleEPGP:GetModule("EPGP")
    local standings = EPGP:GetStandings()
    if not standings or #standings == 0 then
        SimpleEPGP:Print("No standings data available.")
        return
    end

    local db = SimpleEPGP.db
    local minEP = db.profile.min_ep or 0

    -- Filter to raiders (above min_ep) for announce
    local eligible = {}
    for i = 1, #standings do
        local entry = standings[i]
        if entry.ep >= minEP then
            eligible[#eligible + 1] = entry
        end
        if #eligible >= count then break end
    end

    if #eligible == 0 then
        SimpleEPGP:Print("No eligible players to announce.")
        return
    end

    SendChatMessage(format("=== SimpleEPGP Top %d ===", #eligible), channel)
    for i = 1, #eligible do
        local e = eligible[i]
        local line = format("#%d. %s - PR: %.2f (EP: %d / GP: %d)",
            i, e.name, e.pr, e.ep, e.gp)
        SendChatMessage(line, channel)
    end
end

--------------------------------------------------------------------------------
-- Module Lifecycle
--------------------------------------------------------------------------------

function Leaderboard:OnEnable()
    -- Auto-refresh when standings change
    self:RegisterMessage("SEPGP_STANDINGS_UPDATED", "Refresh")
end

function Leaderboard:OnDisable()
    self:UnregisterAllMessages()
    self:Hide()
end
