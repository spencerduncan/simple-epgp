# SimpleEPGP — WoW TBC Anniversary Addon

## WoW Addon Lua Conventions
- **No `require`/`module`** — WoW uses global namespace, files loaded by .toc order
- **Namespace pollution** — wrap everything in the addon table (`local addon = LibStub("AceAddon-3.0"):GetAddon("SimpleEPGP")`)
- **Event-driven** — never poll. Register events, respond in handlers
- **No coroutines in event handlers** — WoW's Lua doesn't support yielding from event callbacks
- **Strings are bytes** — WoW Lua is 5.1, no UTF-8 string lib. Character names can contain special chars
- **`self` convention** — Ace3 mixins use `self:Method()` calling convention, colon syntax
- **Frame recycling** — create frames once, show/hide. Don't create/destroy frames repeatedly

## TBC Anniversary Client Specifics (Interface 20505)
- **TOC suffix**: `_TBC.toc` (NOT `-BCC`, removed Jan 2026)
- **API namespaces**: Many globals moved to `C_*` namespaces (C_ChatInfo, C_GuildInfo, C_AddOns). Use new names.
- **SendAddonMessage**: Returns `Enum.SendAddonMessageResult`, not boolean. Per-prefix throttle: 10 burst, 1/sec regen.
- **GuildRoster()**: Throttled server-side to 1 call per 10 seconds. Cache results.
- **Officer notes**: 31-char hard limit. Any guild member can READ via API. Only officers can WRITE (silent fail if no permission).
- **GetItemInfo**: Returns nil for uncached items. Items in open loot windows are always cached. For manual lookups, request and wait for `GET_ITEM_INFO_RECEIVED`.
- **SavedVariables**: NOT written on crash/kill. Only on logout, /reload, disconnect, or quit.
- **January 2026 throttle hotfix**: Blizzard accidentally over-throttled addons at TBC Anniversary launch; fixed Jan 14-15.

## Addon Messaging Best Practices
- Always use ChatThrottleLib (embedded via AceComm) — raw SendAddonMessage will silently drop messages
- Prefix max 16 chars, message max 255 bytes per packet
- AceComm handles chunking for messages >255 bytes automatically
- Use RAID channel during raids, GUILD for out-of-raid sync
- Null bytes (`\0`) cannot appear in addon messages — AceSerializer handles encoding
- After login/zone change, first 5 seconds have 1/10th normal throughput

## Officer Note Encoding
- Format: `"<EP>,<GP>"` — both integers, comma-separated
- Max realistic size: `"99999,99999"` = 11 chars (well under 31)
- Parse with: `string.match(note, "^(%d+),(%d+)$")`
- On parse failure, treat as EP=0, GP=0 (don't overwrite — could be another addon's data)
- Always find roster index by name match before writing (indices shift when members join/leave)

## Testing Without a Raid
- Use `/script` to simulate events
- Standings window can be tested with just guild membership
- Loot flow requires a dungeon with ML — test in a 5-man with a guildie
- Use `/dump GetGuildRosterInfo(1)` to inspect API returns
- BugSack + BugGrabber addons for error capture (essential during development)
- `/console scriptErrors 1` to enable Lua error display

## Patch Resilience
- **Check Interface number every patch** — Blizzard increments it, causing "out of date" warnings
- **Never rely on deprecated API aliases** — they can be removed any patch
- **Don't hardcode encounter IDs** — use ENCOUNTER_END generically, log the encounterName
- **Test after every WoW patch** — addon API changes are not always documented in advance
- **Keep Ace3 libs updated** — they get patched for API changes faster than individual addons

## Code Style
- 4-space indentation
- `local` everything — minimize globals
- Comment non-obvious WoW API quirks inline
- Group related functions in files by responsibility
- Error messages to user via `self:Print()` (AceConsole), not `print()`

## Architecture
```
SimpleEPGP/
├── SimpleEPGP_TBC.toc
├── Core.lua          -- AceAddon init, slash commands, event wiring
├── EPGP.lua          -- EP/GP math, officer note encode/decode, decay
├── GPCalc.lua        -- GP cost formula (ilvl + slot multipliers)
├── Comms.lua         -- AceComm messaging for loot bids
├── LootMaster.lua    -- Loot detection, bid collection, award flow
├── UI/
│   ├── Standings.lua
│   ├── LootPopup.lua
│   ├── AwardFrame.lua
│   ├── Config.lua
│   ├── ExportFrame.lua
│   ├── Tooltip.lua
│   └── Leaderboard.lua
├── Debug.lua         -- Debug logging + test helper slash commands
├── Log.lua           -- Audit log (SavedVariables-backed)
└── Libs/             -- Embedded Ace3 libraries
```

## Running Tests
```bash
luacheck SimpleEPGP/ --config .luacheckrc   # Static analysis
busted test/                                  # Unit tests
```

## Debug Loop (In-Game Testing)

### Workflow
1. Claude edits code in `~/claude/simple-epgp/SimpleEPGP/`
2. Run: `bash deploy.sh` (rsyncs to WoW AddOns folder)
3. Penny does `/reloadui` in game (loads updated addon)
4. Penny runs test commands (see below)
5. Penny does `/reloadui` again (flushes SavedVariables to disk)
6. Claude reads results: `lua5.1 read_debug_log.lua`
7. Iterate

### Paths
- **WoW AddOns**: `~/.steam/.../World of Warcraft/_anniversary_/Interface/AddOns/SimpleEPGP/`
- **SavedVariables**: `.../_anniversary_/WTF/Account/ANGRYB4CON/SavedVariables/`
- **Account**: ANGRYB4CON, Realm: Dreamscythe

### Debug Commands
- `/sepgp debug log [N]` — Show last N debug log entries in chat
- `/sepgp debug clear` — Clear the debug log
- `/sepgp debug roster` — Print guild roster with EP/GP/PR
- `/sepgp debug note <name>` — Print raw officer note for a player
- `/sepgp debug status` — Print addon state (config, standby, module status)
- `/sepgp debug fakeraid` — Stub IsInRaid() to return true (for solo testing)
- `/sepgp debug endfakeraid` — Restore real IsInRaid()
- `/sepgp debug bosskill [name]` — Simulate ENCOUNTER_END with success
- `/sepgp debug loot [itemID]` — Start a fake loot session (default: 29759 T4 Helm)
- `/sepgp debug bid <MS|OS|DE> [player]` — Inject a fake bid into active session

### Reading Logs Externally
```bash
lua5.1 read_debug_log.lua              # All entries
lua5.1 read_debug_log.lua -n 20        # Last 20 entries
lua5.1 read_debug_log.lua -c EPGP      # Filter by category
```

### Debug Log Categories
`INFO`, `WARN`, `ERROR`, `EVENT`, `EPGP`, `COMMS`, `LOOT`, `UI`

Logged automatically at: addon init, ENCOUNTER_END, GUILD_ROSTER_UPDATE, ModifyEP/GP, MassEP, Decay, ResetAll, LOOT_OPENED, AwardItem, BidReceived, CalculateGP, SendOffer, comm received.
