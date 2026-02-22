-----------------------------------------------------------------------
-- test_comms.lua — Unit tests for Comms module
-----------------------------------------------------------------------

-- Load stubs first
require("test.wow_stubs")
require("test.ace_stubs")

-- Create the addon (simulates NewAddon call in Core.lua)
local SimpleEPGP = LibStub("AceAddon-3.0"):NewAddon("SimpleEPGP",
    "AceConsole-3.0", "AceEvent-3.0", "AceComm-3.0", "AceSerializer-3.0")

-- Set up default config (simulates AceDB defaults)
SimpleEPGP.db = LibStub("AceDB-3.0"):New("SimpleEPGPDB", {
    profile = {
        base_gp = 100,
        min_ep = 0,
        decay_percent = 15,
        quality_threshold = 4,
        standard_ilvl = 120,
        gp_base_multiplier = nil,
        slot_multipliers = {},
        os_multiplier = 0.5,
        de_multiplier = 0.0,
        ep_per_boss = 100,
        auto_ep_boss = true,
        standby_percent = 1.0,
        bid_timer = 30,
        auto_distribute = false,
        auto_distribute_delay = 3,
        show_gp_tooltip = true,
        announce_channel = "GUILD",
        announce_awards = true,
        announce_ep = true,
    },
}, true)

-- Load the module files (order matches .toc)
dofile("SimpleEPGP/EPGP.lua")
dofile("SimpleEPGP/GPCalc.lua")
dofile("SimpleEPGP/Log.lua")
dofile("SimpleEPGP/Comms.lua")
dofile("SimpleEPGP/LootMaster.lua")

-- Initialize addon (triggers OnInitialize + OnEnable for addon and all modules)
_G._testInitAddon("SimpleEPGP")

describe("Comms", function()
    local Comms

    before_each(function()
        Comms = SimpleEPGP:GetModule("Comms")
        -- Clear sent messages
        for i = #_G._testSentMessages, 1, -1 do
            _G._testSentMessages[i] = nil
        end
    end)

    describe("message sending", function()
        -- Helper: deserialize the payload from a sent message
        local function deserializeSent(index)
            local msg = _G._testSentMessages[index or 1].message
            local ok, data = Comms:Deserialize(msg)
            assert.is_true(ok, "Deserialize should succeed")
            return data
        end

        it("sends OFFER messages with correct payload", function()
            Comms:SendOffer("itemlink", 1000, 1)
            assert.are.equal(1, #_G._testSentMessages)
            assert.are.equal("SimpleEPGP", _G._testSentMessages[1].prefix)
            assert.are.equal("RAID", _G._testSentMessages[1].distribution)

            local data = deserializeSent(1)
            assert.are.equal("OFFER", data.type)
            assert.are.equal("itemlink", data.itemLink)
            assert.are.equal(1000, data.gpCost)
            assert.are.equal(1, data.sessionId)
        end)

        it("sends BID messages with correct payload", function()
            Comms:SendBid(1, "MS")
            assert.are.equal(1, #_G._testSentMessages)
            assert.are.equal("SimpleEPGP", _G._testSentMessages[1].prefix)
            assert.are.equal("RAID", _G._testSentMessages[1].distribution)

            local data = deserializeSent(1)
            assert.are.equal("BID", data.type)
            assert.are.equal(1, data.sessionId)
            assert.are.equal("MS", data.bidType)
        end)

        it("sends AWARD messages with correct payload", function()
            Comms:SendAward("itemlink", "Player1", "MS", 1000)
            assert.are.equal(1, #_G._testSentMessages)
            assert.are.equal("SimpleEPGP", _G._testSentMessages[1].prefix)
            assert.are.equal("RAID", _G._testSentMessages[1].distribution)

            local data = deserializeSent(1)
            assert.are.equal("AWARD", data.type)
            assert.are.equal("itemlink", data.itemLink)
            assert.are.equal("Player1", data.winner)
            assert.are.equal("MS", data.bidType)
            assert.are.equal(1000, data.gpCharged)
        end)

        it("sends RETRACT messages with correct payload", function()
            Comms:SendRetract(1)
            assert.are.equal(1, #_G._testSentMessages)
            assert.are.equal("SimpleEPGP", _G._testSentMessages[1].prefix)
            assert.are.equal("RAID", _G._testSentMessages[1].distribution)

            local data = deserializeSent(1)
            assert.are.equal("RETRACT", data.type)
            assert.are.equal(1, data.sessionId)
        end)

        it("sends CANCEL messages with correct payload", function()
            Comms:SendCancel(1)
            assert.are.equal(1, #_G._testSentMessages)
            assert.are.equal("SimpleEPGP", _G._testSentMessages[1].prefix)
            assert.are.equal("RAID", _G._testSentMessages[1].distribution)

            local data = deserializeSent(1)
            assert.are.equal("CANCEL", data.type)
            assert.are.equal(1, data.sessionId)
        end)

        it("sends STANDINGS_REQUEST with correct payload", function()
            Comms:SendStandingsRequest()
            assert.are.equal(1, #_G._testSentMessages)
            assert.are.equal("SimpleEPGP", _G._testSentMessages[1].prefix)
            assert.are.equal("GUILD", _G._testSentMessages[1].distribution)

            local data = deserializeSent(1)
            assert.are.equal("STANDINGS_REQUEST", data.type)
        end)

        it("sends STANDINGS_SYNC with correct payload", function()
            local standingsData = {
                { n = "Alice", c = "PALADIN", e = 5000, g = 1000 },
                { n = "Bob", c = "ROGUE", e = 3000, g = 500 },
            }
            Comms:SendStandingsSync("TargetPlayer", standingsData)
            assert.are.equal(1, #_G._testSentMessages)
            assert.are.equal("SimpleEPGP", _G._testSentMessages[1].prefix)
            assert.are.equal("WHISPER", _G._testSentMessages[1].distribution)
            assert.are.equal("TargetPlayer", _G._testSentMessages[1].target)
            assert.are.equal("BULK", _G._testSentMessages[1].priority)

            local data = deserializeSent(1)
            assert.are.equal("STANDINGS_SYNC", data.type)
            assert.are.equal(2, #data.standings)
            assert.are.equal("Alice", data.standings[1].n)
            assert.are.equal(5000, data.standings[1].e)
            assert.are.equal("Bob", data.standings[2].n)
        end)
    end)

    describe("message roundtrip", function()
        it("roundtrips OFFER message", function()
            local received = nil
            Comms:RegisterCallback("OFFER", function(sender, data)
                received = data
            end)
            -- Send an offer
            Comms:SendOffer("testLink", 500, 42)
            -- Simulate receiving it
            local msg = _G._testSentMessages[1].message
            _G._testReceiveComm(Comms, "SimpleEPGP", msg, "RAID", "TestSender-Realm")

            assert.is_not_nil(received)
            assert.are.equal("OFFER", received.type)
            assert.are.equal("testLink", received.itemLink)
            assert.are.equal(500, received.gpCost)
            assert.are.equal(42, received.sessionId)
        end)

        it("roundtrips BID message", function()
            local received = nil
            Comms:RegisterCallback("BID", function(sender, data)
                received = {sender = sender, data = data}
            end)
            Comms:SendBid(1, "OS")
            local msg = _G._testSentMessages[1].message
            _G._testReceiveComm(Comms, "SimpleEPGP", msg, "RAID", "Bidder-Realm")

            assert.is_not_nil(received)
            assert.are.equal("Bidder", received.sender)  -- realm stripped
            assert.are.equal("OS", received.data.bidType)
        end)

        it("strips realm from sender", function()
            local receivedSender = nil
            Comms:RegisterCallback("BID", function(sender, data)
                receivedSender = sender
            end)
            Comms:SendBid(1, "MS")
            local msg = _G._testSentMessages[1].message
            _G._testReceiveComm(Comms, "SimpleEPGP", msg, "RAID", "PlayerName-SomeRealm")
            assert.are.equal("PlayerName", receivedSender)
        end)

        it("roundtrips AWARD message", function()
            local received = nil
            Comms:RegisterCallback("AWARD", function(sender, data)
                received = data
            end)
            Comms:SendAward("testLink", "Winner", "MS", 1000)
            local msg = _G._testSentMessages[1].message
            _G._testReceiveComm(Comms, "SimpleEPGP", msg, "RAID", "ML-Realm")

            assert.is_not_nil(received)
            assert.are.equal("AWARD", received.type)
            assert.are.equal("testLink", received.itemLink)
            assert.are.equal("Winner", received.winner)
            assert.are.equal("MS", received.bidType)
            assert.are.equal(1000, received.gpCharged)
        end)

        it("roundtrips RETRACT message", function()
            local received = nil
            Comms:RegisterCallback("RETRACT", function(sender, data)
                received = data
            end)
            Comms:SendRetract(7)
            local msg = _G._testSentMessages[1].message
            _G._testReceiveComm(Comms, "SimpleEPGP", msg, "RAID", "Player-Realm")

            assert.is_not_nil(received)
            assert.are.equal("RETRACT", received.type)
            assert.are.equal(7, received.sessionId)
        end)

        it("roundtrips CANCEL message", function()
            local received = nil
            Comms:RegisterCallback("CANCEL", function(sender, data)
                received = data
            end)
            Comms:SendCancel(3)
            local msg = _G._testSentMessages[1].message
            _G._testReceiveComm(Comms, "SimpleEPGP", msg, "RAID", "ML-Realm")

            assert.is_not_nil(received)
            assert.are.equal("CANCEL", received.type)
            assert.are.equal(3, received.sessionId)
        end)

        it("strips realm from sender without realm suffix", function()
            local receivedSender = nil
            Comms:RegisterCallback("BID", function(sender, data)
                receivedSender = sender
            end)
            Comms:SendBid(1, "MS")
            local msg = _G._testSentMessages[1].message
            -- Sender without realm suffix (same realm)
            _G._testReceiveComm(Comms, "SimpleEPGP", msg, "RAID", "JustAName")
            assert.are.equal("JustAName", receivedSender)
        end)
    end)

    describe("OnCommReceived error handling", function()
        it("ignores messages with wrong prefix", function()
            local received = nil
            Comms:RegisterCallback("BID", function(sender, data)
                received = data
            end)
            -- Send a valid BID message
            Comms:SendBid(1, "MS")
            local msg = _G._testSentMessages[1].message
            -- Deliver it with a wrong prefix
            _G._testReceiveComm(Comms, "WrongAddon", msg, "RAID", "Sender-Realm")
            assert.is_nil(received)
        end)

        it("ignores malformed serialized data", function()
            local received = nil
            Comms:RegisterCallback("BID", function(sender, data)
                received = data
            end)
            -- Send garbage that won't deserialize to a valid table
            _G._testReceiveComm(Comms, "SimpleEPGP", "this is not valid serialized data!!!", "RAID", "Sender-Realm")
            assert.is_nil(received)
        end)

        it("ignores data with missing type field", function()
            local callbackFired = false
            -- Register callbacks for several types to catch any accidental dispatch
            for _, msgType in ipairs({"OFFER", "BID", "AWARD", "RETRACT", "CANCEL"}) do
                Comms:RegisterCallback(msgType, function()
                    callbackFired = true
                end)
            end
            -- Serialize a table with no "type" field
            local payload = Comms:Serialize({ sessionId = 1, bidType = "MS" })
            _G._testReceiveComm(Comms, "SimpleEPGP", payload, "RAID", "Sender-Realm")
            assert.is_false(callbackFired)
        end)

        it("ignores non-table deserialized data", function()
            local callbackFired = false
            Comms:RegisterCallback("BID", function()
                callbackFired = true
            end)
            -- Serialize a plain string instead of a table
            local payload = Comms:Serialize("just a string")
            _G._testReceiveComm(Comms, "SimpleEPGP", payload, "RAID", "Sender-Realm")
            assert.is_false(callbackFired)
        end)

        it("ignores non-table deserialized data (number)", function()
            local callbackFired = false
            Comms:RegisterCallback("BID", function()
                callbackFired = true
            end)
            -- Serialize a plain number
            local payload = Comms:Serialize(42)
            _G._testReceiveComm(Comms, "SimpleEPGP", payload, "RAID", "Sender-Realm")
            assert.is_false(callbackFired)
        end)

        it("ignores non-table deserialized data (boolean)", function()
            local callbackFired = false
            Comms:RegisterCallback("BID", function()
                callbackFired = true
            end)
            local payload = Comms:Serialize(true)
            _G._testReceiveComm(Comms, "SimpleEPGP", payload, "RAID", "Sender-Realm")
            assert.is_false(callbackFired)
        end)
    end)

    describe("OnStandingsRequest self-filtering", function()
        local EPGP

        before_each(function()
            EPGP = SimpleEPGP:GetModule("EPGP")
            -- Build standings so officer has data to send
            _G._testGuildRoster[1].officerNote = "5000,1000"
            _G._testGuildRoster[2].officerNote = "3000,500"
            EPGP:GUILD_ROSTER_UPDATE()
            -- Clear messages
            for i = #_G._testSentMessages, 1, -1 do
                _G._testSentMessages[i] = nil
            end
        end)

        it("does not respond to own standings request", function()
            -- UnitName("player") returns "Player1" in wow_stubs
            -- Simulate receiving a STANDINGS_REQUEST from ourselves
            local payload = Comms:Serialize({ type = "STANDINGS_REQUEST" })
            _G._testReceiveComm(Comms, "SimpleEPGP", payload, "GUILD", "Player1")

            -- Officer should NOT have sent a response (self-request filter)
            assert.are.equal(0, #_G._testSentMessages)
        end)

        it("responds to standings request from another player", function()
            -- Simulate receiving a STANDINGS_REQUEST from someone else
            local payload = Comms:Serialize({ type = "STANDINGS_REQUEST" })
            _G._testReceiveComm(Comms, "SimpleEPGP", payload, "GUILD", "OtherPlayer-Realm")

            -- Officer should respond with STANDINGS_SYNC via whisper
            assert.are.equal(1, #_G._testSentMessages)
            assert.are.equal("WHISPER", _G._testSentMessages[1].distribution)
            assert.are.equal("OtherPlayer", _G._testSentMessages[1].target)
        end)

        it("does not respond to request if not an officer", function()
            -- Temporarily stub CanViewOfficerNote to return false
            local origCanView = C_GuildInfo.CanViewOfficerNote
            C_GuildInfo.CanViewOfficerNote = function() return false end

            local payload = Comms:Serialize({ type = "STANDINGS_REQUEST" })
            _G._testReceiveComm(Comms, "SimpleEPGP", payload, "GUILD", "SomePlayer-Realm")

            -- Non-officer should NOT respond
            assert.are.equal(0, #_G._testSentMessages)

            C_GuildInfo.CanViewOfficerNote = origCanView
        end)
    end)

    describe("CheckNeedSync", function()
        local EPGP

        before_each(function()
            EPGP = SimpleEPGP:GetModule("EPGP")
            -- Clear messages
            for i = #_G._testSentMessages, 1, -1 do
                _G._testSentMessages[i] = nil
            end
        end)

        it("does not request sync when officer can view notes", function()
            -- Default stubs: CanViewOfficerNote returns true
            -- Set up standings with nonzero EP/GP
            _G._testGuildRoster[1].officerNote = "5000,1000"
            EPGP:GUILD_ROSTER_UPDATE()

            for i = #_G._testSentMessages, 1, -1 do
                _G._testSentMessages[i] = nil
            end

            EPGP:CheckNeedSync()

            -- Should not have sent a STANDINGS_REQUEST
            assert.are.equal(0, #_G._testSentMessages)
        end)

        it("requests sync when non-officer sees all-zero standings", function()
            -- Stub: cannot view officer notes
            local origCanView = C_GuildInfo.CanViewOfficerNote
            C_GuildInfo.CanViewOfficerNote = function() return false end

            -- Set up roster with zero EP/GP (non-officer can't read notes)
            _G._testGuildRoster[1].officerNote = ""
            _G._testGuildRoster[2].officerNote = ""
            _G._testGuildRoster[3].officerNote = ""
            _G._testGuildRoster[4].officerNote = ""
            _G._testGuildRoster[5].officerNote = ""
            EPGP:GUILD_ROSTER_UPDATE()

            for i = #_G._testSentMessages, 1, -1 do
                _G._testSentMessages[i] = nil
            end

            EPGP:CheckNeedSync()

            -- Should have sent a STANDINGS_REQUEST (C_Timer.After fires immediately in tests)
            assert.is_true(#_G._testSentMessages > 0)
            local data = Comms:Deserialize(_G._testSentMessages[1].message)
            -- Deserialize returns (true, data) — need second return value
            local ok, payload = Comms:Deserialize(_G._testSentMessages[1].message)
            assert.is_true(ok)
            assert.are.equal("STANDINGS_REQUEST", payload.type)
            assert.are.equal("GUILD", _G._testSentMessages[1].distribution)

            C_GuildInfo.CanViewOfficerNote = origCanView
        end)

        it("does not request sync if already synced from officer", function()
            -- Stub: cannot view officer notes
            local origCanView = C_GuildInfo.CanViewOfficerNote
            C_GuildInfo.CanViewOfficerNote = function() return false end

            -- Set up all-zero standings
            _G._testGuildRoster[1].officerNote = ""
            _G._testGuildRoster[2].officerNote = ""
            _G._testGuildRoster[3].officerNote = ""
            _G._testGuildRoster[4].officerNote = ""
            _G._testGuildRoster[5].officerNote = ""
            EPGP:GUILD_ROSTER_UPDATE()

            -- Simulate having already received a sync
            -- Use OnStandingsSync to set the synced flag properly
            EPGP:OnStandingsSync("Officer", {
                standings = {
                    { n = "Player1", c = "WARRIOR", e = 100, g = 50 },
                },
            })

            for i = #_G._testSentMessages, 1, -1 do
                _G._testSentMessages[i] = nil
            end

            EPGP:CheckNeedSync()

            -- Should NOT request sync — already synced
            assert.are.equal(0, #_G._testSentMessages)

            C_GuildInfo.CanViewOfficerNote = origCanView
        end)

        it("does not request sync if standings have nonzero values", function()
            -- Stub: cannot view officer notes
            local origCanView = C_GuildInfo.CanViewOfficerNote
            C_GuildInfo.CanViewOfficerNote = function() return false end

            -- Simulate a non-officer that somehow has nonzero standings
            -- (e.g., received a broadcast earlier)
            -- First, receive a sync with real data
            EPGP:OnStandingsSync("Officer", {
                standings = {
                    { n = "Player1", c = "WARRIOR", e = 5000, g = 1000 },
                },
            })

            for i = #_G._testSentMessages, 1, -1 do
                _G._testSentMessages[i] = nil
            end

            -- Now CheckNeedSync: already synced, should skip
            EPGP:CheckNeedSync()

            assert.are.equal(0, #_G._testSentMessages)

            C_GuildInfo.CanViewOfficerNote = origCanView
        end)
    end)

    describe("standings sync", function()
        it("sends STANDINGS_REQUEST on GUILD channel", function()
            Comms:SendStandingsRequest()
            assert.are.equal(1, #_G._testSentMessages)
            assert.are.equal("GUILD", _G._testSentMessages[1].distribution)
        end)

        it("sends STANDINGS_SYNC via WHISPER to target", function()
            local data = {
                { n = "Player1", c = "WARRIOR", e = 1000, g = 500 },
                { n = "Player2", c = "MAGE", e = 2000, g = 300 },
            }
            Comms:SendStandingsSync("Player3", data)
            assert.are.equal(1, #_G._testSentMessages)
            assert.are.equal("WHISPER", _G._testSentMessages[1].distribution)
            assert.are.equal("Player3", _G._testSentMessages[1].target)
        end)

        it("roundtrips STANDINGS_REQUEST", function()
            local received = nil
            Comms:RegisterCallback("STANDINGS_REQUEST", function(sender, data)
                received = { sender = sender }
            end)
            Comms:SendStandingsRequest()
            local msg = _G._testSentMessages[1].message
            _G._testReceiveComm(Comms, "SimpleEPGP", msg, "GUILD", "NonOfficer-Realm")
            assert.is_not_nil(received)
            assert.are.equal("NonOfficer", received.sender)
        end)

        it("roundtrips STANDINGS_SYNC with data", function()
            local received = nil
            Comms:RegisterCallback("STANDINGS_SYNC", function(sender, data)
                received = { sender = sender, data = data }
            end)
            local standings = {
                { n = "Alice", c = "PALADIN", e = 5000, g = 1000 },
                { n = "Bob", c = "ROGUE", e = 3000, g = 500 },
            }
            Comms:SendStandingsSync("Requester", standings)
            local msg = _G._testSentMessages[1].message
            _G._testReceiveComm(Comms, "SimpleEPGP", msg, "WHISPER", "Officer-Realm")

            assert.is_not_nil(received)
            assert.are.equal("Officer", received.sender)
            assert.are.equal(2, #received.data.standings)
            assert.are.equal("Alice", received.data.standings[1].n)
            assert.are.equal(5000, received.data.standings[1].e)
        end)
    end)

    describe("EPGP standings sync integration", function()
        local EPGP

        before_each(function()
            EPGP = SimpleEPGP:GetModule("EPGP")
            -- Reset guild roster
            _G._testGuildRoster[1].officerNote = "5000,1000"
            _G._testGuildRoster[2].officerNote = "3000,500"
            _G._testGuildRoster[3].officerNote = "2000,2000"
            EPGP:GUILD_ROSTER_UPDATE()
        end)

        it("officer responds to sync request with standings data", function()
            -- Officer can view notes (default in test stubs)
            for i = #_G._testSentMessages, 1, -1 do
                _G._testSentMessages[i] = nil
            end

            -- Simulate receiving a request
            Comms:SendStandingsRequest()
            local msg = _G._testSentMessages[1].message
            for i = #_G._testSentMessages, 1, -1 do
                _G._testSentMessages[i] = nil
            end

            _G._testReceiveComm(Comms, "SimpleEPGP", msg, "GUILD", "NonOfficer-Realm")

            -- Officer should have sent a STANDINGS_SYNC response
            assert.are.equal(1, #_G._testSentMessages)
            assert.are.equal("WHISPER", _G._testSentMessages[1].distribution)
            assert.are.equal("NonOfficer", _G._testSentMessages[1].target)
        end)

        it("non-officer populates standings from sync data", function()
            -- Simulate non-officer: cannot view officer notes
            local origCanView = C_GuildInfo.CanViewOfficerNote
            C_GuildInfo.CanViewOfficerNote = function() return false end

            -- Simulate receiving a STANDINGS_SYNC
            local syncData = {
                { n = "Alice", c = "PALADIN", e = 5000, g = 1000 },
                { n = "Bob", c = "ROGUE", e = 3000, g = 500 },
            }
            -- Build the sync message
            Comms:SendStandingsSync("TestTarget", syncData)
            local msg = _G._testSentMessages[1].message
            _G._testReceiveComm(Comms, "SimpleEPGP", msg, "WHISPER", "OfficerSender-Realm")

            -- Check standings were populated
            local standings = EPGP:GetStandings()
            assert.is_true(#standings >= 2)

            -- Verify data
            local alice = EPGP:GetPlayerInfo("Alice")
            assert.is_not_nil(alice)
            assert.are.equal(5000, alice.ep)
            assert.are.equal(1000, alice.gp)

            local bob = EPGP:GetPlayerInfo("Bob")
            assert.is_not_nil(bob)
            assert.are.equal(3000, bob.ep)
            assert.are.equal(500, bob.gp)

            -- Check synced flag
            assert.is_true(EPGP:IsSynced())

            -- Restore
            C_GuildInfo.CanViewOfficerNote = origCanView
        end)

        it("officer ignores STANDINGS_SYNC (already has direct access)", function()
            -- Officer can view notes (default in stubs)
            -- Set known EP/GP via officer notes
            _G._testGuildRoster[1].officerNote = "5000,1000"
            EPGP:GUILD_ROSTER_UPDATE()
            local before = EPGP:GetPlayerInfo("Player1")
            assert.are.equal(5000, before.ep)

            -- Simulate receiving a sync with different data
            local syncData = {
                { n = "Player1", c = "WARRIOR", e = 9999, g = 9999 },
            }
            Comms:SendStandingsSync("SomeTarget", syncData)
            local msg = _G._testSentMessages[#_G._testSentMessages].message
            _G._testReceiveComm(Comms, "SimpleEPGP", msg, "GUILD", "OtherOfficer-Realm")

            -- Standings should NOT have been overwritten
            local after = EPGP:GetPlayerInfo("Player1")
            assert.are.equal(5000, after.ep)
            assert.are.equal(1000, after.gp)
        end)
    end)
end)
