local SimpleEPGP = LibStub("AceAddon-3.0"):GetAddon("SimpleEPGP")
local Log = SimpleEPGP:NewModule("Log")

local time = time
local date = date
local tinsert = table.insert
local tremove = table.remove
local tconcat = table.concat

function Log:OnEnable()
    -- Ensure the log table exists in SavedVariables
    if not SimpleEPGP.db then return end
    if not SimpleEPGP.db.log then
        SimpleEPGP.db.log = {}
    end
end

--- Append an entry to the audit log.
-- @param action The action type (e.g. "EP", "GP", "MASS_EP", "DECAY", "RESET", "AWARD").
-- @param player Player name involved, or nil for bulk actions.
-- @param amount Numeric amount (EP/GP change, decay %, etc).
-- @param item Item link string, or nil.
-- @param reason Free-text reason string, or nil.
function Log:Add(action, player, amount, item, reason)
    if not SimpleEPGP.db then return end
    if not SimpleEPGP.db.log then
        SimpleEPGP.db.log = {}
    end

    local entry = {
        timestamp = time(),
        action = action,
        player = player,
        amount = amount,
        item = item,
        reason = reason,
    }

    tinsert(SimpleEPGP.db.log, entry)
end

--- Get the most recent N log entries, newest first.
-- @param count Number of entries to return (default 20).
-- @return Array of log entries, most recent first.
function Log:GetRecent(count)
    count = count or 20
    local log = SimpleEPGP.db and SimpleEPGP.db.log or {}
    local result = {}
    local total = #log

    local start = total
    local stop = total - count + 1
    if stop < 1 then stop = 1 end

    for i = start, stop, -1 do
        result[#result + 1] = log[i]
    end

    return result
end

--- Get all log entries (oldest first, as stored).
-- @return The full log array.
function Log:GetAll()
    return SimpleEPGP.db and SimpleEPGP.db.log or {}
end

--- Prune the log to keep only the most recent entries.
-- @param maxEntries Maximum entries to keep (default 500).
function Log:Prune(maxEntries)
    maxEntries = maxEntries or 500
    local log = SimpleEPGP.db and SimpleEPGP.db.log
    if not log then return end

    while #log > maxEntries do
        tremove(log, 1)
    end
end

--- Clear all log entries.
function Log:Clear()
    if SimpleEPGP.db then
        SimpleEPGP.db.log = {}
    end
end

--- Format a log entry as a human-readable string.
-- @param entry A log entry table.
-- @return Formatted string.
function Log:FormatEntry(entry)
    if not entry then return "" end

    local ts = date("%Y-%m-%d %H:%M:%S", entry.timestamp)
    local parts = { ts }

    parts[#parts + 1] = entry.action or "?"

    if entry.player then
        parts[#parts + 1] = entry.player
    end

    if entry.amount then
        local sign = ""
        if entry.action == "EP" or entry.action == "GP" or entry.action == "MASS_EP" then
            if entry.amount > 0 then sign = "+" end
        end
        parts[#parts + 1] = sign .. tostring(entry.amount)
    end

    if entry.item then
        parts[#parts + 1] = entry.item
    end

    if entry.reason then
        parts[#parts + 1] = "(" .. entry.reason .. ")"
    end

    return tconcat(parts, " ")
end

--- Export all log entries as a CSV string.
-- @return CSV-formatted string with header row.
function Log:ExportCSV()
    local log = SimpleEPGP.db and SimpleEPGP.db.log or {}
    local lines = {}

    lines[#lines + 1] = "timestamp,date,action,player,amount,item,reason"

    for i = 1, #log do
        local e = log[i]
        local ts = tostring(e.timestamp or 0)
        local dt = date("%Y-%m-%d %H:%M:%S", e.timestamp)
        local action = e.action or ""
        local player = e.player or ""
        local amount = tostring(e.amount or "")
        -- Escape item links and reason for CSV (replace commas and quotes)
        local item = (e.item or ""):gsub('"', '""')
        local reason = (e.reason or ""):gsub('"', '""')

        lines[#lines + 1] = ts .. "," .. dt .. "," .. action .. "," .. player .. "," .. amount .. ',"' .. item .. '","' .. reason .. '"'
    end

    return tconcat(lines, "\n")
end
