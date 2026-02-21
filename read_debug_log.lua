#!/usr/bin/env lua5.1
-----------------------------------------------------------------------
-- read_debug_log.lua — Parse SimpleEPGP debug log from SavedVariables
--
-- Usage:
--   lua5.1 read_debug_log.lua [options]
--
-- Options:
--   -n COUNT        Show last COUNT entries (default: all)
--   -c CATEGORY     Filter by category (e.g. EPGP, LOOT, EVENT)
--   -f PATH         Override SavedVariables file path
--   -h              Show help
-----------------------------------------------------------------------

-- Default SavedVariables path
local DEFAULT_PATH = "/home/sd/.steam/debian-installation/steamapps/compatdata/2243145978/pfx/drive_c/Program Files (x86)/World of Warcraft/_anniversary_/WTF/Account/ANGRYB4CON/SavedVariables/SimpleEPGP.lua"

-- Parse arguments
local count = nil
local category = nil
local filepath = DEFAULT_PATH

local i = 1
while i <= #arg do
    if arg[i] == "-n" then
        i = i + 1
        count = tonumber(arg[i])
    elseif arg[i] == "-c" then
        i = i + 1
        category = arg[i] and arg[i]:upper()
    elseif arg[i] == "-f" then
        i = i + 1
        filepath = arg[i]
    elseif arg[i] == "-h" or arg[i] == "--help" then
        print("Usage: lua5.1 read_debug_log.lua [-n COUNT] [-c CATEGORY] [-f PATH]")
        print("")
        print("Options:")
        print("  -n COUNT     Show last COUNT entries (default: all)")
        print("  -c CATEGORY  Filter by category (EPGP, LOOT, EVENT, INFO, WARN, ERROR, COMMS, UI)")
        print("  -f PATH      Override SavedVariables file path")
        print("  -h           Show this help")
        os.exit(0)
    end
    i = i + 1
end

-- Load the SavedVariables file (it assigns to global tables)
local ok, err = pcall(dofile, filepath)
if not ok then
    io.stderr:write("Error loading " .. filepath .. ": " .. tostring(err) .. "\n")
    io.stderr:write("Make sure WoW has written SavedVariables (do /reloadui in game first).\n")
    os.exit(1)
end

-- SimpleEPGPDebugLog is now a global set by the SavedVariables file
local log = SimpleEPGPDebugLog  -- luacheck: ignore
if not log then
    print("No debug log found in SavedVariables. Has the addon run yet?")
    os.exit(0)
end

-- Format a data table as key=value pairs
local function formatData(data)
    if not data or type(data) ~= "table" then return "" end
    local parts = {}
    for k, v in pairs(data) do
        parts[#parts + 1] = tostring(k) .. "=" .. tostring(v)
    end
    if #parts == 0 then return "" end
    table.sort(parts)
    return " {" .. table.concat(parts, ", ") .. "}"
end

-- Filter by category if specified
local filtered = {}
for _, entry in ipairs(log) do
    if not category or (entry[2] and entry[2]:upper() == category) then
        filtered[#filtered + 1] = entry
    end
end

-- Apply count limit
local start = 1
if count and count < #filtered then
    start = #filtered - count + 1
end

-- Print header
print(string.format("SimpleEPGP Debug Log — %d entries%s",
    #filtered,
    category and (" [" .. category .. "]") or ""))
print(string.rep("-", 72))

-- Print entries
for idx = start, #filtered do
    local entry = filtered[idx]
    local ts = entry[1] or 0
    local cat = entry[2] or "?"
    local msg = entry[3] or ""
    local data = formatData(entry[4])
    print(string.format("[%s] [%-5s] %s%s", os.date("%Y-%m-%d %H:%M:%S", ts), cat, msg, data))
end

if #filtered == 0 then
    print("(no entries)")
end
