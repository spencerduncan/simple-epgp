local SimpleEPGP = LibStub("AceAddon-3.0"):GetAddon("SimpleEPGP")
local Comms = SimpleEPGP:NewModule("Comms", "AceComm-3.0", "AceSerializer-3.0")

local COMM_PREFIX = "SimpleEPGP"

-- Callback registry: messageType -> {handler1, handler2, ...}
local callbacks = {}

function Comms:OnEnable()
    self:RegisterComm(COMM_PREFIX, "OnCommReceived")
end

function Comms:OnDisable()
    self:UnregisterAllComm()
end

--- Register a handler for a specific message type.
-- @param messageType string One of: OFFER, BID, AWARD, RETRACT, CANCEL
-- @param handler function Called with (sender, ...) where ... is message-type-specific fields
function Comms:RegisterCallback(messageType, handler)
    if not callbacks[messageType] then
        callbacks[messageType] = {}
    end
    callbacks[messageType][#callbacks[messageType] + 1] = handler
end

--- Fire all registered callbacks for a message type.
local function FireCallbacks(messageType, sender, data)
    local handlers = callbacks[messageType]
    if not handlers then return end
    for i = 1, #handlers do
        handlers[i](sender, data)
    end
end

--- Strip realm name from sender. WoW sends "Name-Realm" for cross-realm,
--- but in same-realm context we just want "Name".
local function StripRealm(sender)
    local name = sender:match("^([^%-]+)")
    return name or sender
end

--- Handle incoming comm messages. Deserializes and dispatches to callbacks.
-- Called by AceComm when a message with our prefix arrives.
function Comms:OnCommReceived(prefix, message, distribution, sender)
    if prefix ~= COMM_PREFIX then return end

    local success, data = self:Deserialize(message)
    if not success then
        -- data contains error message on failure
        return
    end

    if type(data) ~= "table" or not data.type then
        return
    end

    local cleanSender = StripRealm(sender)

    local Debug = SimpleEPGP:GetModule("Debug", true)
    if Debug then Debug:Log("COMMS", "Received " .. data.type, { sender = cleanSender }) end

    FireCallbacks(data.type, cleanSender, data)
end

--- Send an OFFER message to the raid (ML -> Raiders).
-- @param itemLink string The item link being offered
-- @param gpCost number The GP cost for this item
-- @param sessionId number The loot session ID
function Comms:SendOffer(itemLink, gpCost, sessionId)
    local Debug = SimpleEPGP:GetModule("Debug", true)
    if Debug then Debug:Log("COMMS", "SendOffer", { itemLink = itemLink, gpCost = gpCost, sessionId = sessionId }) end

    local payload = self:Serialize({
        type = "OFFER",
        itemLink = itemLink,
        gpCost = gpCost,
        sessionId = sessionId,
    })
    self:SendCommMessage(COMM_PREFIX, payload, "RAID", nil, "NORMAL")
end

--- Send a BID message to the raid (Raider -> ML).
-- @param sessionId number The loot session ID
-- @param bidType string One of "MS", "OS", "DE", "PASS"
function Comms:SendBid(sessionId, bidType)
    local payload = self:Serialize({
        type = "BID",
        sessionId = sessionId,
        bidType = bidType,
    })
    self:SendCommMessage(COMM_PREFIX, payload, "RAID", nil, "NORMAL")
end

--- Send an AWARD message to the raid (ML -> Raiders).
-- @param itemLink string The awarded item link
-- @param winner string Character name of the winner
-- @param bidType string The bid type that won (MS/OS/DE)
-- @param gpCharged number The GP amount charged to the winner
function Comms:SendAward(itemLink, winner, bidType, gpCharged)
    local payload = self:Serialize({
        type = "AWARD",
        itemLink = itemLink,
        winner = winner,
        bidType = bidType,
        gpCharged = gpCharged,
    })
    self:SendCommMessage(COMM_PREFIX, payload, "RAID", nil, "NORMAL")
end

--- Send a RETRACT message to the raid (Raider -> ML).
-- @param sessionId number The loot session ID
function Comms:SendRetract(sessionId)
    local payload = self:Serialize({
        type = "RETRACT",
        sessionId = sessionId,
    })
    self:SendCommMessage(COMM_PREFIX, payload, "RAID", nil, "NORMAL")
end

--- Send a CANCEL message to the raid (ML -> Raiders).
-- @param sessionId number The loot session ID
function Comms:SendCancel(sessionId)
    local payload = self:Serialize({
        type = "CANCEL",
        sessionId = sessionId,
    })
    self:SendCommMessage(COMM_PREFIX, payload, "RAID", nil, "NORMAL")
end

--------------------------------------------------------------------------------
-- Standings Sync — allows non-officers to receive EP/GP data
--------------------------------------------------------------------------------

--- Send a STANDINGS_REQUEST on GUILD channel.
-- Any officer running the addon who can read notes will respond.
function Comms:SendStandingsRequest()
    local Debug = SimpleEPGP:GetModule("Debug", true)
    if Debug then Debug:Log("COMMS", "SendStandingsRequest") end

    local payload = self:Serialize({ type = "STANDINGS_REQUEST" })
    self:SendCommMessage(COMM_PREFIX, payload, "GUILD", nil, "NORMAL")
end

--- Send a STANDINGS_SYNC to a specific player via whisper.
-- @param targetPlayer string The player name to send standings to.
-- @param standingsData table Array of {name, class, ep, gp} entries.
function Comms:SendStandingsSync(targetPlayer, standingsData)
    local Debug = SimpleEPGP:GetModule("Debug", true)
    if Debug then Debug:Log("COMMS", "SendStandingsSync", { target = targetPlayer, count = #standingsData }) end

    local payload = self:Serialize({
        type = "STANDINGS_SYNC",
        standings = standingsData,
    })
    self:SendCommMessage(COMM_PREFIX, payload, "WHISPER", targetPlayer, "BULK")
end
