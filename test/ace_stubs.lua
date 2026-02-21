-----------------------------------------------------------------------
-- ace_stubs.lua — Mock Ace3 framework for busted unit tests
-- Load AFTER wow_stubs.lua: require("test.ace_stubs")
-----------------------------------------------------------------------

-----------------------------------------------------------------------
-- Serialization helpers (internal)
-----------------------------------------------------------------------

local function serialize_value(v)
    local t = type(v)
    if t == "nil" then
        return "^Z"
    elseif t == "number" then
        return "^N" .. tostring(v)
    elseif t == "string" then
        -- Escape ^ characters in strings
        return "^S" .. v:gsub("%^", "^^")
    elseif t == "boolean" then
        return v and "^B1" or "^B0"
    elseif t == "table" then
        local parts = { "^T" }
        for k, val in pairs(v) do
            parts[#parts + 1] = serialize_value(k)
            parts[#parts + 1] = serialize_value(val)
        end
        parts[#parts + 1] = "^t"
        return table.concat(parts, "\31")
    end
    return "^Z"
end

local function deserialize_value(str)
    if type(str) ~= "string" then return str end
    -- Split by unit separator
    local tokens = {}
    for token in (str .. "\31"):gmatch("(.-)\31") do
        if token ~= "" then
            tokens[#tokens + 1] = token
        end
    end

    local pos = 1
    local function parse()
        if pos > #tokens then return nil end
        local token = tokens[pos]
        pos = pos + 1

        if token == "^Z" then
            return nil
        elseif token:sub(1, 2) == "^N" then
            return tonumber(token:sub(3))
        elseif token:sub(1, 2) == "^S" then
            return token:sub(3):gsub("^^", "^")
        elseif token == "^B1" then
            return true
        elseif token == "^B0" then
            return false
        elseif token == "^T" then
            local tbl = {}
            while pos <= #tokens and tokens[pos] ~= "^t" do
                local key = parse()
                local val = parse()
                if key ~= nil then
                    tbl[key] = val
                end
            end
            if pos <= #tokens and tokens[pos] == "^t" then
                pos = pos + 1  -- consume ^t
            end
            return tbl
        end
        -- Fallback: return as string
        return token
    end

    return parse()
end

-----------------------------------------------------------------------
-- Deep copy helper
-----------------------------------------------------------------------

local function deepcopy(orig)
    if type(orig) ~= "table" then return orig end
    local copy = {}
    for k, v in pairs(orig) do
        copy[deepcopy(k)] = deepcopy(v)
    end
    return setmetatable(copy, getmetatable(orig))
end

-----------------------------------------------------------------------
-- LibStub mock
-----------------------------------------------------------------------

local libs = {}
_G.LibStub = setmetatable({}, {
    __call = function(self, name, silent)
        if not libs[name] then
            if silent then return nil end
            libs[name] = {}
        end
        return libs[name]
    end,
})
_G.LibStub.libs = libs

function _G.LibStub:NewLibrary(name, version)
    libs[name] = libs[name] or {}
    return libs[name]
end

function _G.LibStub:GetLibrary(name, silent)
    if libs[name] then
        return libs[name]
    end
    if not silent then
        error("Library not found: " .. tostring(name))
    end
    return nil
end

-----------------------------------------------------------------------
-- Mixin definitions
-----------------------------------------------------------------------

local mixins = {}

-----------------------------------------------------------------------
-- AceEvent-3.0 mock
-----------------------------------------------------------------------

local registeredEvents = {}

mixins["AceEvent-3.0"] = {
    RegisterEvent = function(self, event, handler)
        registeredEvents[event] = registeredEvents[event] or {}
        table.insert(registeredEvents[event], { obj = self, handler = handler or event })
    end,
    UnregisterEvent = function(self, event)
        if registeredEvents[event] then
            for i = #registeredEvents[event], 1, -1 do
                if registeredEvents[event][i].obj == self then
                    table.remove(registeredEvents[event], i)
                end
            end
        end
    end,
    UnregisterAllEvents = function(self)
        for event, regs in pairs(registeredEvents) do
            for i = #regs, 1, -1 do
                if regs[i].obj == self then
                    table.remove(regs, i)
                end
            end
        end
    end,
    SendMessage = function(self, msg, ...)
        -- Fire as if it were an event so RegisterMessage handlers fire
        if registeredEvents[msg] then
            for _, reg in ipairs(registeredEvents[msg]) do
                local handler = reg.handler
                if type(handler) == "string" then
                    if reg.obj[handler] then
                        reg.obj[handler](reg.obj, msg, ...)
                    end
                elseif type(handler) == "function" then
                    handler(msg, ...)
                end
            end
        end
    end,
    RegisterMessage = function(self, msg, handler)
        registeredEvents[msg] = registeredEvents[msg] or {}
        table.insert(registeredEvents[msg], { obj = self, handler = handler or msg })
    end,
    UnregisterMessage = function(self, msg)
        if registeredEvents[msg] then
            for i = #registeredEvents[msg], 1, -1 do
                if registeredEvents[msg][i].obj == self then
                    table.remove(registeredEvents[msg], i)
                end
            end
        end
    end,
}

-- Expose for tests
_G._testFireEvent = function(event, ...)
    if registeredEvents[event] then
        for _, reg in ipairs(registeredEvents[event]) do
            local handler = reg.handler
            if type(handler) == "string" then
                if reg.obj[handler] then
                    reg.obj[handler](reg.obj, event, ...)
                end
            elseif type(handler) == "function" then
                handler(event, ...)
            end
        end
    end
end

-- Expose for test cleanup
_G._testClearEvents = function()
    for k in pairs(registeredEvents) do
        registeredEvents[k] = nil
    end
end

-----------------------------------------------------------------------
-- AceComm-3.0 mock
-----------------------------------------------------------------------

local sentMessages = {}
_G._testSentMessages = sentMessages

mixins["AceComm-3.0"] = {
    RegisterComm = function(self, prefix, handler)
        self._commHandler = handler
        self._commPrefix = prefix
    end,
    UnregisterComm = function(self, prefix)
        if self._commPrefix == prefix then
            self._commHandler = nil
            self._commPrefix = nil
        end
    end,
    UnregisterAllComm = function(self)
        self._commHandler = nil
        self._commPrefix = nil
    end,
    SendCommMessage = function(self, prefix, message, distribution, target, priority)
        table.insert(sentMessages, {
            prefix = prefix,
            message = message,
            distribution = distribution,
            target = target,
            priority = priority,
        })
    end,
}

-- Simulate receiving a comm message
_G._testReceiveComm = function(addon, prefix, message, distribution, sender)
    if addon._commHandler then
        if type(addon._commHandler) == "string" then
            if addon[addon._commHandler] then
                addon[addon._commHandler](addon, prefix, message, distribution, sender)
            end
        elseif type(addon._commHandler) == "function" then
            addon._commHandler(prefix, message, distribution, sender)
        end
    end
end

-----------------------------------------------------------------------
-- AceSerializer-3.0 mock
-----------------------------------------------------------------------

mixins["AceSerializer-3.0"] = {
    Serialize = function(self, ...)
        local parts = {}
        for i = 1, select("#", ...) do
            local v = select(i, ...)
            parts[#parts + 1] = serialize_value(v)
        end
        return table.concat(parts, "\30")  -- record separator between top-level args
    end,
    Deserialize = function(self, str)
        if type(str) ~= "string" then
            return false, "Invalid input to Deserialize"
        end
        -- Split by record separator for multiple top-level values
        local results = {}
        for segment in (str .. "\30"):gmatch("(.-)\30") do
            if segment ~= "" then
                results[#results + 1] = deserialize_value(segment)
            end
        end
        if #results == 0 then
            return true, nil
        elseif #results == 1 then
            return true, results[1]
        else
            return true, unpack(results)
        end
    end,
}

-----------------------------------------------------------------------
-- AceConsole-3.0 mock
-----------------------------------------------------------------------

mixins["AceConsole-3.0"] = {
    RegisterChatCommand = function(self, cmd, handler)
        self._chatCommands = self._chatCommands or {}
        self._chatCommands[cmd] = handler
    end,
    Print = function(self, ...)
        -- Collect printed messages for test inspection
        self._printLog = self._printLog or {}
        local parts = {}
        for i = 1, select("#", ...) do
            parts[i] = tostring(select(i, ...))
        end
        table.insert(self._printLog, table.concat(parts, " "))
    end,
}

-----------------------------------------------------------------------
-- AceAddon-3.0 mock
-----------------------------------------------------------------------

local AceAddon = _G.LibStub:NewLibrary("AceAddon-3.0", 1)
local addons = {}

local function applyMixins(target, ...)
    for i = 1, select("#", ...) do
        local mixinName = select(i, ...)
        if mixins[mixinName] then
            for k, v in pairs(mixins[mixinName]) do
                target[k] = v
            end
        end
    end
end

function AceAddon:NewAddon(name, ...)
    local addon = {
        name = name,
        modules = {},
        orderedModules = {},
        _enabled = false,
    }

    -- Apply mixins
    applyMixins(addon, ...)

    -- Default lifecycle methods
    addon.OnInitialize = addon.OnInitialize or function() end
    addon.OnEnable = addon.OnEnable or function() end

    -- Print (always available, AceConsole overrides if mixed in)
    if not addon.Print then
        addon.Print = function(self, ...) end
    end

    addon.GetModule = function(self, modName, silent)
        local mod = self.modules[modName]
        if not mod and not silent then
            error("Module '" .. tostring(modName) .. "' not found")
        end
        return mod
    end

    addon.NewModule = function(self, modName, ...)
        local mod = {
            name = modName,
            _enabled = false,
        }

        -- Apply mixins
        applyMixins(mod, ...)

        -- Default lifecycle methods
        mod.OnInitialize = mod.OnInitialize or function() end
        mod.OnEnable = mod.OnEnable or function() end
        mod.OnDisable = mod.OnDisable or function() end

        -- Print (always available)
        if not mod.Print then
            mod.Print = function(self2, ...)
                local parts = {}
                for i2 = 1, select("#", ...) do
                    parts[i2] = tostring(select(i2, ...))
                end
                self2._printLog = self2._printLog or {}
                table.insert(self2._printLog, table.concat(parts, " "))
            end
        end

        self.modules[modName] = mod
        self.orderedModules[#self.orderedModules + 1] = mod
        return mod
    end

    addons[name] = addon
    return addon
end

function AceAddon:GetAddon(name, silent)
    local addon = addons[name]
    if not addon and not silent then
        error("Addon '" .. tostring(name) .. "' not found")
    end
    return addon
end

--- Initialize and enable an addon and all its modules.
-- Useful in tests to simulate the WoW addon loading lifecycle.
function AceAddon:InitializeAddon(name)
    local addon = addons[name]
    if not addon then return end
    if addon.OnInitialize then addon:OnInitialize() end
    if addon.OnEnable then addon:OnEnable() end
    addon._enabled = true
    for _, mod in ipairs(addon.orderedModules) do
        if mod.OnInitialize then mod:OnInitialize() end
        if mod.OnEnable then mod:OnEnable() end
        mod._enabled = true
    end
end

-- Expose for test use
_G._testInitAddon = function(name)
    AceAddon:InitializeAddon(name)
end

-----------------------------------------------------------------------
-- AceDB-3.0 mock
-----------------------------------------------------------------------

local AceDB = _G.LibStub:NewLibrary("AceDB-3.0", 1)

function AceDB:New(svName, defaults, defaultProfile)
    local db = {
        profile = {},
        log = {},
        standby = {},
        sv = {},
        keys = { profile = defaultProfile or "Default" },
    }

    -- Deep-copy defaults into profile
    if defaults and defaults.profile then
        db.profile = deepcopy(defaults.profile)
    end
    if defaults and defaults.global then
        db.global = deepcopy(defaults.global)
    end

    -- RegisterCallback stub
    db.RegisterCallback = function() end

    return db
end

-----------------------------------------------------------------------
-- Register remaining library names that real Ace3 would provide
-----------------------------------------------------------------------

_G.LibStub:NewLibrary("CallbackHandler-1.0", 1)
_G.LibStub:NewLibrary("ChatThrottleLib", 1)

-----------------------------------------------------------------------
-- Reset helpers for tests
-----------------------------------------------------------------------

--- Reset all addon state. Call in before_each to get a clean slate.
_G._testResetAddons = function()
    for k in pairs(addons) do
        addons[k] = nil
    end
    -- Clear sent messages
    for i = #sentMessages, 1, -1 do
        sentMessages[i] = nil
    end
    -- Clear events
    _G._testClearEvents()
end
