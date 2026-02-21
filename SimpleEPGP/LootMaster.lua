local SimpleEPGP = LibStub("AceAddon-3.0"):GetAddon("SimpleEPGP")
local LootMaster = SimpleEPGP:NewModule("LootMaster", "AceEvent-3.0")

-- GetLootMethod() moved to C_PartyInfo.GetLootMethod() in TBC Anniversary.
-- The new API returns Enum.LootMethod integers instead of strings.
local GetLootMethod = GetLootMethod
if not GetLootMethod and C_PartyInfo and C_PartyInfo.GetLootMethod then
    local METHOD_NAMES = {
        [0] = "freeforall", [1] = "roundrobin", [2] = "master",
        [3] = "group", [4] = "needbeforegreed", [5] = "personalloot",
    }
    GetLootMethod = function()
        local method, partyId = C_PartyInfo.GetLootMethod()
        return METHOD_NAMES[method] or "unknown", partyId or 0
    end
end
assert(GetLootMethod, "SimpleEPGP: Neither GetLootMethod nor C_PartyInfo.GetLootMethod exists.")

-- Guard master loot APIs — may not exist if master loot is unavailable
local GetMasterLootCandidate = GetMasterLootCandidate
local GiveMasterLoot = GiveMasterLoot

-- Callback registry for UI notifications
local uiCallbacks = {}

--- Register a callback for UI events.
-- @param eventName string Event name (e.g. "OFFER_RECEIVED", "AWARD_RECEIVED", "CANCEL_RECEIVED", "ELIGIBLE_LOOT", "TIMER_EXPIRED")
-- @param handler function
function LootMaster:RegisterUICallback(eventName, handler)
    if not uiCallbacks[eventName] then
        uiCallbacks[eventName] = {}
    end
    uiCallbacks[eventName][#uiCallbacks[eventName] + 1] = handler
end

local function FireUICallback(eventName, ...)
    local handlers = uiCallbacks[eventName]
    if not handlers then return end
    for i = 1, #handlers do
        handlers[i](...)
    end
end

function LootMaster:OnEnable()
    self.sessions = {}
    self.nextSessionId = 1
    self.lootWindowOpen = false

    -- Register WoW events for loot detection
    self:RegisterEvent("LOOT_OPENED")
    self:RegisterEvent("LOOT_CLOSED")

    -- Register comm callbacks for incoming messages
    local Comms = SimpleEPGP:GetModule("Comms")
    Comms:RegisterCallback("OFFER", function(sender, data)
        self:OnOfferReceived(sender, data.itemLink, data.gpCost, data.sessionId)
    end)
    Comms:RegisterCallback("BID", function(sender, data)
        self:OnBidReceived(sender, data.sessionId, data.bidType)
    end)
    Comms:RegisterCallback("RETRACT", function(sender, data)
        self:OnRetractReceived(sender, data.sessionId)
    end)
    Comms:RegisterCallback("AWARD", function(sender, data)
        self:OnAwardReceived(sender, data.itemLink, data.winner, data.bidType, data.gpCharged)
    end)
    Comms:RegisterCallback("CANCEL", function(sender, data)
        self:OnCancelReceived(sender, data.sessionId)
    end)
end

function LootMaster:OnDisable()
    self:UnregisterAllEvents()
end

--------------------------------------------------------------------------------
-- Loot Detection (Master Looter side)
--------------------------------------------------------------------------------

--- Called when a loot window opens. Check if we are the master looter
--- and scan for eligible items.
function LootMaster:LOOT_OPENED()
    local Debug = SimpleEPGP:GetModule("Debug", true)
    if Debug then Debug:Log("LOOT", "LOOT_OPENED") end

    self.lootWindowOpen = true

    -- Check if loot method is master loot and we are the ML
    local method, partyId = GetLootMethod()
    if method ~= "master" or partyId ~= 0 then
        return  -- Not master looter, nothing to do
    end

    local db = SimpleEPGP.db
    local threshold = db.profile.quality_threshold or 4  -- Default: Epic quality
    local GPCalc = SimpleEPGP:GetModule("GPCalc")

    local eligibleItems = {}
    local numItems = GetNumLootItems()

    for i = 1, numItems do
        -- GetLootSlotInfo returns: lootIcon, lootName, lootQuantity, currencyID, lootQuality, locked, isQuestItem, questID, isActive
        local _, _, _, _, quality = GetLootSlotInfo(i)
        if quality and quality >= threshold then
            -- Items in the open loot window are always cached (per CLAUDE.md)
            local itemLink = GetLootSlotLink(i)
            if itemLink then
                local gpCost = GPCalc:CalculateGP(itemLink)
                eligibleItems[#eligibleItems + 1] = {
                    lootIndex = i,
                    itemLink = itemLink,
                    gpCost = gpCost,
                    quality = quality,
                }
            end
        end
    end

    if #eligibleItems > 0 then
        -- Fire callback for UI to show the AwardFrame
        FireUICallback("ELIGIBLE_LOOT", eligibleItems)
    end
end

function LootMaster:LOOT_CLOSED()
    self.lootWindowOpen = false
end

--------------------------------------------------------------------------------
-- Session Management (Master Looter side)
--------------------------------------------------------------------------------

--- Start a new loot session for an item. Broadcasts OFFER to the raid.
-- @param itemLink string The item link
-- @param gpCost number GP cost for mainspec
-- @return number sessionId The new session ID
function LootMaster:StartSession(itemLink, gpCost)
    local db = SimpleEPGP.db
    local sessionId = self.nextSessionId
    self.nextSessionId = self.nextSessionId + 1

    local session = {
        id = sessionId,
        itemLink = itemLink,
        gpCost = gpCost,
        bids = {},
        startTime = time(),
        awarded = false,
    }

    self.sessions[sessionId] = session

    -- Broadcast the offer to the raid
    local Comms = SimpleEPGP:GetModule("Comms")
    Comms:SendOffer(itemLink, gpCost, sessionId)

    -- Start the bid timer (use NewTicker with 1 iteration for a cancellable one-shot)
    local bidTimer = db.profile.bid_timer or 30
    session.timer = C_Timer.NewTicker(bidTimer, function()
        self:OnTimerExpired(sessionId)
    end, 1)

    return sessionId
end

--- Cancel an active loot session. Broadcasts CANCEL to the raid.
-- @param sessionId number
function LootMaster:CancelSession(sessionId)
    local session = self.sessions[sessionId]
    if not session then return end

    -- Cancel the timer if it's still running
    if session.timer then
        session.timer:Cancel()
        session.timer = nil
    end

    local Comms = SimpleEPGP:GetModule("Comms")
    Comms:SendCancel(sessionId)

    self.sessions[sessionId] = nil
end

--- Handle an incoming bid from a raider (ML side).
-- @param sender string Character name
-- @param sessionId number
-- @param bidType string "MS", "OS", "DE", or "PASS"
function LootMaster:OnBidReceived(sender, sessionId, bidType)
    local Debug = SimpleEPGP:GetModule("Debug", true)
    if Debug then Debug:Log("LOOT", "BidReceived", { sender = sender, sessionId = sessionId, bidType = bidType }) end

    local session = self.sessions[sessionId]
    if not session or session.awarded then return end

    session.bids[sender] = bidType
end

--- Handle a bid retraction from a raider (ML side).
-- @param sender string Character name
-- @param sessionId number
function LootMaster:OnRetractReceived(sender, sessionId)
    local session = self.sessions[sessionId]
    if not session or session.awarded then return end

    session.bids[sender] = nil
end

--- Get bids for a session, grouped by type and sorted by PR descending.
-- @param sessionId number
-- @return table {ms={}, os={}, de={}, pass={}} Each entry: {name, class, pr, ep, gp, bidType}
function LootMaster:GetSessionBids(sessionId)
    local session = self.sessions[sessionId]
    if not session then return nil end

    local EPGP = SimpleEPGP:GetModule("EPGP")
    local result = {
        ms = {},
        os = {},
        de = {},
        pass = {},
    }

    for name, bidType in pairs(session.bids) do
        -- Use EPGP standings for player data (UnitClass only works with unit tokens)
        local playerInfo = EPGP:GetPlayerInfo(name)
        local ep = playerInfo and playerInfo.ep or 0
        local gp = playerInfo and playerInfo.gp or 0
        local pr = playerInfo and playerInfo.pr or 0
        local class = playerInfo and playerInfo.class or "UNKNOWN"

        local entry = {
            name = name,
            class = class,
            pr = pr,
            ep = ep,
            gp = gp,
            bidType = bidType,
        }

        local key = bidType:lower()
        if result[key] then
            result[key][#result[key] + 1] = entry
        end
    end

    -- Assign random tiebreak values before sorting so the comparator is consistent.
    -- table.sort in Lua 5.1 can infinite-loop with non-deterministic comparators.
    for _, group in pairs(result) do
        for _, entry in ipairs(group) do
            entry._tiebreak = math.random()
        end
    end

    -- Sort each group by PR descending, random tiebreak
    local function sortByPR(a, b)
        if a.pr ~= b.pr then
            return a.pr > b.pr
        end
        return a._tiebreak > b._tiebreak
    end

    table.sort(result.ms, sortByPR)
    table.sort(result.os, sortByPR)
    table.sort(result.de, sortByPR)
    table.sort(result.pass, sortByPR)

    return result
end

--------------------------------------------------------------------------------
-- Award Flow (Master Looter side)
--------------------------------------------------------------------------------

--- Award an item from a session to a player.
-- Charges GP, gives loot, broadcasts AWARD, logs action, announces.
-- @param sessionId number
-- @param winnerName string Character name of the winner
-- @param bidType string The bid type (MS/OS/DE)
function LootMaster:AwardItem(sessionId, winnerName, bidType)
    local Debug = SimpleEPGP:GetModule("Debug", true)
    if Debug then Debug:Log("LOOT", "AwardItem", { sessionId = sessionId, winner = winnerName, bidType = bidType }) end

    local session = self.sessions[sessionId]
    if not session or session.awarded then return end

    local EPGP = SimpleEPGP:GetModule("EPGP")
    local GPCalc = SimpleEPGP:GetModule("GPCalc")
    local Comms = SimpleEPGP:GetModule("Comms")
    local db = SimpleEPGP.db

    -- Calculate GP to charge based on bid type
    local gpCharged = GPCalc:GetBidGP(session.itemLink, bidType)

    -- Charge GP to the winner
    EPGP:ModifyGP(winnerName, gpCharged, "Won " .. session.itemLink)

    -- Give the actual loot via master loot API
    if self.lootWindowOpen then
        self:GiveLootToPlayer(session.itemLink, winnerName)
    end

    -- Broadcast the award to the raid
    Comms:SendAward(session.itemLink, winnerName, bidType, gpCharged)

    -- Log the action
    local Log = SimpleEPGP:GetModule("Log")
    Log:Add("AWARD", winnerName, gpCharged, session.itemLink,
        bidType .. " bid")

    -- Announce to configured chat channel
    local announceChannel = db.profile.announce_channel
    if announceChannel and announceChannel ~= "NONE" then
        local msg = string.format("%s awarded to %s (%s) for %d GP",
            session.itemLink, winnerName, bidType, gpCharged)
        SendChatMessage(msg, announceChannel)
    end

    -- Mark session as awarded and clean up timer
    session.awarded = true
    if session.timer then
        session.timer:Cancel()
        session.timer = nil
    end
end

--- Find the master loot candidate index for a player and give them the loot.
-- GiveMasterLoot requires iterating candidates to find the right index.
-- @param itemLink string The item to give
-- @param playerName string The recipient
function LootMaster:GiveLootToPlayer(itemLink, playerName)
    if not GetMasterLootCandidate or not GiveMasterLoot then
        SimpleEPGP:Print("Master loot API unavailable — item must be traded manually.")
        return
    end

    local numItems = GetNumLootItems()
    for lootSlot = 1, numItems do
        local link = GetLootSlotLink(lootSlot)
        if link == itemLink then
            -- Found the loot slot, now find the candidate
            for candidateIdx = 1, GetNumGroupMembers() do
                local candidateName = GetMasterLootCandidate(lootSlot, candidateIdx)
                if candidateName then
                    -- Strip realm from candidate name for comparison
                    local cleanName = candidateName:match("^([^%-]+)") or candidateName
                    if cleanName == playerName then
                        GiveMasterLoot(lootSlot, candidateIdx)
                        return
                    end
                end
            end
        end
    end
end

--------------------------------------------------------------------------------
-- Timer Handling
--------------------------------------------------------------------------------

--- Called when the bid timer expires for a session.
-- @param sessionId number
function LootMaster:OnTimerExpired(sessionId)
    local session = self.sessions[sessionId]
    if not session or session.awarded then return end

    local db = SimpleEPGP.db

    if db.profile.auto_distribute then
        -- Auto-distribute: pick highest PR bidder from MS > OS > DE
        local bids = self:GetSessionBids(sessionId)
        local winner = nil

        if #bids.ms > 0 then
            winner = bids.ms[1]
        elseif #bids.os > 0 then
            winner = bids.os[1]
        elseif #bids.de > 0 then
            winner = bids.de[1]
        end

        if winner then
            -- Brief delay before auto-awarding so ML can see what's happening
            local delay = db.profile.auto_distribute_delay or 5
            C_Timer.After(delay, function()
                -- Re-check session hasn't been manually awarded/cancelled during delay
                local s = self.sessions[sessionId]
                if s and not s.awarded then
                    self:AwardItem(sessionId, winner.name, winner.bidType)
                end
            end)
        end

        -- Notify ML about auto-distribution
        FireUICallback("TIMER_EXPIRED", sessionId, winner)
    else
        -- Manual mode: just notify ML that timer expired
        FireUICallback("TIMER_EXPIRED", sessionId, nil)
    end
end

--------------------------------------------------------------------------------
-- Raider Side (non-ML players)
--------------------------------------------------------------------------------

--- Handle an incoming OFFER from the master looter.
-- Fires a UI callback so LootPopup can be shown.
-- @param sender string ML character name
-- @param itemLink string
-- @param gpCost number
-- @param sessionId number
function LootMaster:OnOfferReceived(sender, itemLink, gpCost, sessionId)
    -- Don't show popup if we are the ML (we already have the AwardFrame)
    local method, partyId = GetLootMethod()
    if method == "master" and partyId == 0 then
        return
    end

    FireUICallback("OFFER_RECEIVED", {
        sender = sender,
        itemLink = itemLink,
        gpCost = gpCost,
        sessionId = sessionId,
    })
end

--- Submit a bid for a loot session (raider side).
-- @param sessionId number
-- @param bidType string "MS", "OS", "DE", or "PASS"
function LootMaster:SubmitBid(sessionId, bidType)
    local Comms = SimpleEPGP:GetModule("Comms")
    Comms:SendBid(sessionId, bidType)
end

--- Retract a bid for a loot session (raider side).
-- @param sessionId number
function LootMaster:RetractBid(sessionId)
    local Comms = SimpleEPGP:GetModule("Comms")
    Comms:SendRetract(sessionId)
end

--- Handle an incoming AWARD notification (raider side).
-- @param sender string ML character name
-- @param itemLink string
-- @param winner string
-- @param bidType string
-- @param gpCharged number
function LootMaster:OnAwardReceived(sender, itemLink, winner, bidType, gpCharged)
    FireUICallback("AWARD_RECEIVED", {
        sender = sender,
        itemLink = itemLink,
        winner = winner,
        bidType = bidType,
        gpCharged = gpCharged,
    })
end

--- Handle an incoming CANCEL notification (raider side).
-- @param sender string ML character name
-- @param sessionId number
function LootMaster:OnCancelReceived(sender, sessionId)
    FireUICallback("CANCEL_RECEIVED", {
        sender = sender,
        sessionId = sessionId,
    })
end
