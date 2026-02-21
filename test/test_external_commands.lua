-----------------------------------------------------------------------
-- test_external_commands.lua — Unit tests for /sepgp external slash commands
-----------------------------------------------------------------------

-- Load stubs first
require("test.wow_stubs")
require("test.ace_stubs")

-- Core.lua is loaded FIRST in .toc — creates the addon via NewAddon
dofile("SimpleEPGP/Core.lua")

-- Get the addon object (Core.lua created it)
local SimpleEPGP = LibStub("AceAddon-3.0"):GetAddon("SimpleEPGP")

-- Load the module files (order matches .toc after Core.lua)
dofile("SimpleEPGP/EPGP.lua")
dofile("SimpleEPGP/GPCalc.lua")
dofile("SimpleEPGP/Log.lua")
dofile("SimpleEPGP/Comms.lua")
dofile("SimpleEPGP/LootMaster.lua")

-- Initialize addon (triggers OnInitialize + OnEnable for addon and all modules)
_G._testInitAddon("SimpleEPGP")

describe("External player slash commands", function()
    local EPGP

    before_each(function()
        -- Reset guild roster officer notes
        _G._testGuildRoster[1].officerNote = "5000,1000"
        _G._testGuildRoster[2].officerNote = "3000,500"
        _G._testGuildRoster[3].officerNote = "2000,2000"
        _G._testGuildRoster[4].officerNote = "1000,100"
        _G._testGuildRoster[5].officerNote = ""

        -- Clear external players
        SimpleEPGP.db.profile.external_players = {}

        -- Rebuild standings
        EPGP = SimpleEPGP:GetModule("EPGP")
        EPGP:GUILD_ROSTER_UPDATE()

        -- Clear print log
        SimpleEPGP._printLog = {}
    end)

    describe("/sepgp external add", function()
        it("adds an external player with a valid class", function()
            SimpleEPGP:HandleSlashCommand("external add Pugman WARRIOR")
            assert.is_true(EPGP:IsExternalPlayer("Pugman"))
            local ext = SimpleEPGP.db.profile.external_players["Pugman"]
            assert.are.equal("WARRIOR", ext.class)
        end)

        it("adds an external player with class defaulting to UNKNOWN", function()
            SimpleEPGP:HandleSlashCommand("external add Pugman")
            assert.is_true(EPGP:IsExternalPlayer("Pugman"))
            local ext = SimpleEPGP.db.profile.external_players["Pugman"]
            assert.are.equal("UNKNOWN", ext.class)
        end)

        it("accepts class case-insensitively", function()
            SimpleEPGP:HandleSlashCommand("external add Pugman warrior")
            assert.is_true(EPGP:IsExternalPlayer("Pugman"))
            local ext = SimpleEPGP.db.profile.external_players["Pugman"]
            assert.are.equal("WARRIOR", ext.class)
        end)

        it("rejects an invalid class token", function()
            SimpleEPGP:HandleSlashCommand("external add Pugman MONK")
            assert.is_false(EPGP:IsExternalPlayer("Pugman"))
        end)

        it("accepts all valid WoW class tokens", function()
            local classes = {
                "WARRIOR", "PALADIN", "HUNTER", "ROGUE", "PRIEST",
                "DEATHKNIGHT", "SHAMAN", "MAGE", "WARLOCK", "DRUID",
            }
            for i, class in ipairs(classes) do
                SimpleEPGP:HandleSlashCommand("external add Player" .. (i + 10) .. " " .. class)
                local name = "Player" .. (i + 10)
                -- Normalize name (first letter upper, rest lower)
                name = name:sub(1, 1):upper() .. name:sub(2):lower()
                assert.is_true(EPGP:IsExternalPlayer(name),
                    "Expected " .. name .. " with class " .. class .. " to be added")
            end
        end)

        it("prints usage when name is missing", function()
            SimpleEPGP:HandleSlashCommand("external add")
            assert.is_false(EPGP:IsExternalPlayer(""))
        end)

        it("prints confirmation on success", function()
            SimpleEPGP:HandleSlashCommand("external add Pugman WARRIOR")
            local found = false
            for _, msg in ipairs(SimpleEPGP._printLog) do
                if msg:find("Added external player") and msg:find("Pugman") then
                    found = true
                end
            end
            assert.is_true(found, "Expected confirmation message for add")
        end)

        it("does not print 'Added' for duplicate player", function()
            SimpleEPGP:HandleSlashCommand("external add Pugman WARRIOR")
            SimpleEPGP._printLog = {}
            SimpleEPGP:HandleSlashCommand("external add Pugman MAGE")
            local foundAdded = false
            for _, msg in ipairs(SimpleEPGP._printLog) do
                if msg:find("Added external player") then
                    foundAdded = true
                end
            end
            assert.is_false(foundAdded, "Should not print 'Added' for duplicate")
        end)

        it("normalizes player name", function()
            SimpleEPGP:HandleSlashCommand("external add pugman WARRIOR")
            assert.is_true(EPGP:IsExternalPlayer("Pugman"))
        end)
    end)

    describe("/sepgp external remove", function()
        it("removes an existing external player", function()
            SimpleEPGP:HandleSlashCommand("external add Pugman WARRIOR")
            assert.is_true(EPGP:IsExternalPlayer("Pugman"))
            SimpleEPGP:HandleSlashCommand("external remove Pugman")
            assert.is_false(EPGP:IsExternalPlayer("Pugman"))
        end)

        it("prints confirmation on successful removal", function()
            SimpleEPGP:HandleSlashCommand("external add Pugman WARRIOR")
            SimpleEPGP._printLog = {}
            SimpleEPGP:HandleSlashCommand("external remove Pugman")
            local found = false
            for _, msg in ipairs(SimpleEPGP._printLog) do
                if msg:find("Removed external player") and msg:find("Pugman") then
                    found = true
                end
            end
            assert.is_true(found, "Expected confirmation message for remove")
        end)

        it("handles removing non-existent player", function()
            -- Should not error; EPGP module prints its own error
            SimpleEPGP:HandleSlashCommand("external remove Nobody")
        end)

        it("prints usage when name is missing", function()
            SimpleEPGP:HandleSlashCommand("external remove")
            -- Should not error
        end)

        it("normalizes name for removal", function()
            SimpleEPGP:HandleSlashCommand("external add Pugman ROGUE")
            SimpleEPGP:HandleSlashCommand("external remove pugman")
            assert.is_false(EPGP:IsExternalPlayer("Pugman"))
        end)
    end)

    describe("/sepgp external list", function()
        it("prints empty message when no external players", function()
            SimpleEPGP._printLog = {}
            SimpleEPGP:HandleSlashCommand("external list")
            local found = false
            for _, msg in ipairs(SimpleEPGP._printLog) do
                if msg:find("No external players") then
                    found = true
                end
            end
            assert.is_true(found, "Expected 'No external players' message")
        end)

        it("lists external players with EP, GP, PR", function()
            SimpleEPGP:HandleSlashCommand("external add Pugman WARRIOR")
            SimpleEPGP.db.profile.external_players["Pugman"].ep = 500
            SimpleEPGP.db.profile.external_players["Pugman"].gp = 200
            SimpleEPGP._printLog = {}
            SimpleEPGP:HandleSlashCommand("external list")

            local foundHeader = false
            local foundPlayer = false
            for _, msg in ipairs(SimpleEPGP._printLog) do
                if msg:find("External players") then
                    foundHeader = true
                end
                if msg:find("Pugman") and msg:find("WARRIOR") then
                    foundPlayer = true
                end
            end
            assert.is_true(foundHeader, "Expected header line")
            assert.is_true(foundPlayer, "Expected Pugman in list output")
        end)

        it("lists multiple external players", function()
            SimpleEPGP:HandleSlashCommand("external add Pugman WARRIOR")
            SimpleEPGP:HandleSlashCommand("external add Allyheals PRIEST")
            SimpleEPGP._printLog = {}
            SimpleEPGP:HandleSlashCommand("external list")

            local foundPugman = false
            local foundAlly = false
            for _, msg in ipairs(SimpleEPGP._printLog) do
                if msg:find("Pugman") then foundPugman = true end
                if msg:find("Allyheals") then foundAlly = true end
            end
            assert.is_true(foundPugman, "Expected Pugman in list")
            assert.is_true(foundAlly, "Expected Allyheals in list")
        end)

        it("shows correct PR calculation", function()
            SimpleEPGP:HandleSlashCommand("external add Pugman WARRIOR")
            SimpleEPGP.db.profile.external_players["Pugman"].ep = 1000
            SimpleEPGP.db.profile.external_players["Pugman"].gp = 0
            SimpleEPGP._printLog = {}
            SimpleEPGP:HandleSlashCommand("external list")

            -- PR = 1000 / (0 + 100) = 10.00
            local foundPR = false
            for _, msg in ipairs(SimpleEPGP._printLog) do
                if msg:find("10%.00") then
                    foundPR = true
                end
            end
            assert.is_true(foundPR, "Expected PR of 10.00")
        end)
    end)

    describe("/sepgp external set", function()
        it("sets EP and GP values for an external player", function()
            SimpleEPGP:HandleSlashCommand("external add Pugman WARRIOR")
            SimpleEPGP:HandleSlashCommand("external set Pugman 500 200")
            local ext = SimpleEPGP.db.profile.external_players["Pugman"]
            assert.are.equal(500, ext.ep)
            assert.are.equal(200, ext.gp)
        end)

        it("prints confirmation on success", function()
            SimpleEPGP:HandleSlashCommand("external add Pugman WARRIOR")
            SimpleEPGP._printLog = {}
            SimpleEPGP:HandleSlashCommand("external set Pugman 500 200")
            local found = false
            for _, msg in ipairs(SimpleEPGP._printLog) do
                if msg:find("Set") and msg:find("Pugman") and msg:find("500") and msg:find("200") then
                    found = true
                end
            end
            assert.is_true(found, "Expected confirmation message for set")
        end)

        it("handles non-existent player", function()
            -- Should not error; EPGP module prints its own error
            SimpleEPGP:HandleSlashCommand("external set Nobody 100 50")
        end)

        it("prints usage when args are missing", function()
            SimpleEPGP:HandleSlashCommand("external set")
            SimpleEPGP:HandleSlashCommand("external set Pugman")
            SimpleEPGP:HandleSlashCommand("external set Pugman 100")
            -- Should not error
        end)

        it("rejects negative EP value", function()
            SimpleEPGP:HandleSlashCommand("external add Pugman WARRIOR")
            SimpleEPGP:HandleSlashCommand("external set Pugman -100 50")
            local ext = SimpleEPGP.db.profile.external_players["Pugman"]
            -- Values should remain at defaults (0, 0) since set was rejected
            assert.are.equal(0, ext.ep)
            assert.are.equal(0, ext.gp)
        end)

        it("rejects negative GP value", function()
            SimpleEPGP:HandleSlashCommand("external add Pugman WARRIOR")
            SimpleEPGP:HandleSlashCommand("external set Pugman 100 -50")
            local ext = SimpleEPGP.db.profile.external_players["Pugman"]
            assert.are.equal(0, ext.ep)
            assert.are.equal(0, ext.gp)
        end)

        it("allows setting values to zero", function()
            SimpleEPGP:HandleSlashCommand("external add Pugman WARRIOR")
            SimpleEPGP.db.profile.external_players["Pugman"].ep = 500
            SimpleEPGP.db.profile.external_players["Pugman"].gp = 200
            SimpleEPGP:HandleSlashCommand("external set Pugman 0 0")
            local ext = SimpleEPGP.db.profile.external_players["Pugman"]
            assert.are.equal(0, ext.ep)
            assert.are.equal(0, ext.gp)
        end)

        it("updates standings after setting values", function()
            SimpleEPGP:HandleSlashCommand("external add Pugman WARRIOR")
            SimpleEPGP:HandleSlashCommand("external set Pugman 1000 0")
            local info = EPGP:GetPlayerInfo("Pugman")
            assert.is_not_nil(info)
            assert.are.equal(1000, info.ep)
            assert.are.equal(0, info.gp)
            -- PR = 1000 / (0 + 100) = 10.0
            local expectedPR = 1000 / 100
            assert.is_true(math.abs(info.pr - expectedPR) < 0.01)
        end)

        it("normalizes name for set", function()
            SimpleEPGP:HandleSlashCommand("external add Pugman WARRIOR")
            SimpleEPGP:HandleSlashCommand("external set pugman 300 100")
            local ext = SimpleEPGP.db.profile.external_players["Pugman"]
            assert.are.equal(300, ext.ep)
            assert.are.equal(100, ext.gp)
        end)

        it("updates modified_by and modified_at", function()
            SimpleEPGP:HandleSlashCommand("external add Pugman WARRIOR")
            local before = os.time()
            SimpleEPGP:HandleSlashCommand("external set Pugman 500 200")
            local ext = SimpleEPGP.db.profile.external_players["Pugman"]
            assert.are.equal("Player1", ext.modified_by)
            assert.is_true(ext.modified_at >= before)
        end)
    end)

    describe("/sepgp external (no subcommand)", function()
        it("prints usage when no subcommand given", function()
            SimpleEPGP._printLog = {}
            SimpleEPGP:HandleSlashCommand("external")
            local found = false
            for _, msg in ipairs(SimpleEPGP._printLog) do
                if msg:find("Usage") then
                    found = true
                end
            end
            assert.is_true(found, "Expected usage message")
        end)

        it("prints usage for unknown subcommand", function()
            SimpleEPGP._printLog = {}
            SimpleEPGP:HandleSlashCommand("external bogus")
            local found = false
            for _, msg in ipairs(SimpleEPGP._printLog) do
                if msg:find("Usage") then
                    found = true
                end
            end
            assert.is_true(found, "Expected usage message for unknown subcommand")
        end)
    end)

    describe("/sepgp ext shorthand", function()
        it("works as alias for external", function()
            SimpleEPGP:HandleSlashCommand("ext add Pugman WARRIOR")
            assert.is_true(EPGP:IsExternalPlayer("Pugman"))
        end)
    end)

    describe("EPGP:SetExternalPlayerValues", function()
        it("sets EP and GP directly", function()
            EPGP:AddExternalPlayer("Pugman", "WARRIOR")
            local ok = EPGP:SetExternalPlayerValues("Pugman", 1000, 500)
            assert.is_true(ok)
            local ext = SimpleEPGP.db.profile.external_players["Pugman"]
            assert.are.equal(1000, ext.ep)
            assert.are.equal(500, ext.gp)
        end)

        it("returns false for non-existent external player", function()
            local ok = EPGP:SetExternalPlayerValues("Nobody", 100, 50)
            assert.is_false(ok)
        end)

        it("returns false for nil name", function()
            local ok = EPGP:SetExternalPlayerValues(nil, 100, 50)
            assert.is_false(ok)
        end)

        it("returns false for empty name", function()
            local ok = EPGP:SetExternalPlayerValues("", 100, 50)
            assert.is_false(ok)
        end)

        it("normalizes name", function()
            EPGP:AddExternalPlayer("Pugman", "WARRIOR")
            local ok = EPGP:SetExternalPlayerValues("pugman", 500, 200)
            assert.is_true(ok)
            local ext = SimpleEPGP.db.profile.external_players["Pugman"]
            assert.are.equal(500, ext.ep)
            assert.are.equal(200, ext.gp)
        end)

        it("updates modified_by and modified_at", function()
            EPGP:AddExternalPlayer("Pugman", "WARRIOR")
            local before = os.time()
            EPGP:SetExternalPlayerValues("Pugman", 500, 200)
            local ext = SimpleEPGP.db.profile.external_players["Pugman"]
            assert.are.equal("Player1", ext.modified_by)
            assert.is_true(ext.modified_at >= before)
        end)

        it("rebuilds standings after setting values", function()
            EPGP:AddExternalPlayer("Pugman", "WARRIOR")
            EPGP:SetExternalPlayerValues("Pugman", 1000, 0)
            local info = EPGP:GetPlayerInfo("Pugman")
            assert.is_not_nil(info)
            assert.are.equal(1000, info.ep)
            assert.are.equal(0, info.gp)
        end)
    end)
end)
