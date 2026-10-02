#!/usr/bin/env python3
"""
Runs the Mint Community Tools addon in a real Lua 5.1 interpreter against a mocked WoW API,
drives it the way a player would (opens the window, clicks its buttons, loots, links an item
in chat, exports the items seen), then checks the results independently in Python: the
export strings are decoded with base64, zlib and json and checked against
docs/export-string-format-v1.md and docs/item-export-format-v1.md.

Three mocked clients:
  forever   WoW Forever: UnitName returns the first name with the LAST NAME as its second value,
            Classic talent API, GetItemStats, no region source but a "beta" portal.
  classic   Classic Era: UnitName returns the name alone. Starts with SAVED DATA already in
            place, as Saved.lua leaves it (a loot log, the watcher on, the minimap button moved).
  mainline  Mainline-style: UnitName's second value is the REALM (must not become a last name),
            C_Item namespace, no Classic talent API, German loot lines. The client hands the
            saved data over LATE, after the addon has started fresh.

WoW uses Lua 5.1, so the addon must run under 5.1 semantics (setfenv, loadstring, ...).
The interpreter is picked in this order:
  1. $LUA, if set (must report _VERSION "Lua 5.1")
  2. luajit, lua5.1, lua-5.1, lua51, lua on PATH -- the first one that reports "Lua 5.1"
     (on macOS: `brew install luajit`; on Debian/Ubuntu: `apt install lua5.1` or `luajit`)

usage: python3 tests/run.py [-v] [--write-fixtures]
"""
import base64
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
import zlib
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
ADDON_DIR = ROOT / "MintCommunityTools"
# The .toc's load order, without Saved.lua (a link to the game's save file; absent here).
FILES = ["Encode.lua", "Collect.lua", "Loot.lua", "UI.lua", "LootUI.lua", "Minimap.lua", "Core.lua"]
VARIANTS = ["forever", "classic", "mainline"]
VERBOSE = "-v" in sys.argv
# --write-fixtures saves the export strings the addon actually produced, for the website's
# importer tests to consume. Commit the result.
WRITE_FIXTURES = "--write-fixtures" in sys.argv
FIXTURE_DIR = Path(__file__).resolve().parent / "fixtures"

# What the website's item database reads from an item (docs/item-export-format-v1.md).
ITEM_KEYS = ["id", "name", "quality", "itemLevel", "itemClass", "itemSubclass", "equipLoc", "icon", "stats"]

# ---------------------------------------------------------------------------
# Lua side: mocked WoW environment. Chunks are loaded with loadstring + setfenv so the
# addon sees only the mock API, exactly as it would inside the game.
# ---------------------------------------------------------------------------
LUA_PRELUDE = r'''
local out = { prints = {}, texts = {}, frames = {}, chatLinks = {}, chatOpened = {} }

-- Generic no-op frame stub. It records SetText calls, remembers scripts, registered events,
-- where it was anchored, the template it was created with and the backdrop it was given (so
-- the harness can fire events, click buttons, check placement and check that no Blizzard
-- frame art is used), and answers anything else with another stub. Any capitalised method
-- name is accepted: the flat skin calls SetBackdrop, SetBackdropColor, SetBackdropBorderColor,
-- SetNormalFontObject, SetTextInsets, SetCheckedTexture, SetVertexColor, SetTextColor and so on.
local function stub(name, template)
  local o = { _name = name, _template = template, _scripts = {}, _events = {}, _shown = false }
  table.insert(out.frames, o)
  return setmetatable(o, { __index = function(t, k)
    return function(self, ...)
      if k == "SetText" then rawset(self, "_text", (...)); table.insert(out.texts, (...)) end
      if k == "GetText" then return rawget(self, "_text") or "" end
      if k == "SetScript" then local kind, fn = ...; rawget(self, "_scripts")[kind] = fn; return end
      if k == "RegisterEvent" then rawget(self, "_events")[(...)] = true; return end
      if k == "UnregisterEvent" then rawget(self, "_events")[(...)] = nil; return end
      if k == "SetPoint" then rawset(self, "_point", { ... }); return end
      if k == "SetTexture" then rawset(self, "_texture", (...)); return end
      if k == "SetBackdrop" then rawset(self, "_backdrop", (...)); return end
      if k == "Show" then rawset(self, "_shown", true); local s = rawget(self, "_scripts"); if s.OnShow then s.OnShow(self) end; return end
      if k == "Hide" then rawset(self, "_shown", false); local s = rawget(self, "_scripts"); if s.OnHide then s.OnHide(self) end; return end
      if k == "IsShown" then return rawget(self, "_shown") end
      return stub()
    end
  end })
end

local function fire(event, ...)
  for _, f in ipairs(out.frames) do
    if f._events[event] and f._scripts.OnEvent then f._scripts.OnEvent(f, event, ...) end
  end
end

local function frameNamed(name)
  for _, f in ipairs(out.frames) do if f._name == name then return f end end
  error("no frame named " .. name)
end

local function click(name, ...)
  local f = frameNamed(name)
  assert(f._scripts.OnClick, name .. " has no OnClick")
  f._scripts.OnClick(f, ...)
end

-- The minimap answers with numbers, as the real one does.
local MINIMAP = stub("Minimap")
rawset(MINIMAP, "GetWidth", function() return 140 end)
rawset(MINIMAP, "GetCenter", function() return 900, 700 end)
rawset(MINIMAP, "GetEffectiveScale", function() return 1 end)

local function ilink(color, id, name, suffix)
  return "|cff" .. color .. "|Hitem:" .. id .. ":0:0:0:0:0:" .. (suffix or 0) .. ":0:60|h[" .. name .. "]|h|r"
end

-- Equipped gear
local links = {
  [1]  = "|cffa335ee|Hitem:12640:0:0:0:0:0:0:0:60|h[Lionheart Helm]|h|r",
  [2]  = "|cffa335ee|Hitem:18404:2564:2345:0:0:0:-25:1234:60:0:0:0:0|h[Onyxia Tooth Pendant]|h|r",
  [4]  = "|cffffffff|Hitem:2576:0:0:0:0:0:0:0:60|h[White Swashbuckler's Shirt]|h|r",
  [5]  = "|cff0070dd|Hitem:11726:1892:3:4::::::60|h[Savage Gladiator Chain]|h|r",
  [16] = "|cffff8000|Hitem:19019::::::::60|h[Thunderfury, Blessed Blade of the Windseeker]|h|r",
  [17] = '|cff1eff00|Hitem:999:0:0:0:0:0:0:0:60|h[Test "Quoted" \\ Item]|h|r',
}
local qualities = { [1] = 4, [2] = 4, [4] = 1, [5] = 3, [16] = 5, [17] = 2 }
local levels = { [1] = 66, [2] = 74, [4] = 1, [5] = 55, [16] = 80, [17] = 10 }
local stats = {
  [12640] = { ITEM_MOD_STRENGTH_SHORT = 18, ITEM_MOD_AGILITY_SHORT = 18, ITEM_MOD_STAMINA_SHORT = 0, ITEM_MOD_CRIT_RATING_SHORT = 2 },
  [19019] = { ITEM_MOD_DAMAGE_PER_SECOND_SHORT = 53.9, ITEM_MOD_STAMINA_SHORT = 8 },
  [2576]  = {},
  [16800] = { ITEM_MOD_STAMINA_SHORT = 13, ITEM_MOD_INTELLECT_SHORT = 14 },
  [18832] = { ITEM_MOD_STRENGTH_SHORT = 9, ITEM_MOD_DAMAGE_PER_SECOND_SHORT = 56.5 },
}
local function itemIdOf(link) return tonumber(link:match("|Hitem:(%d+)")) end

-- Loot: id -> link and what GetItemInfo says (quality, item level, type, subtype, slot, icon)
local LOOT = {
  [16800] = { link = ilink("a335ee", 16800, "Arcanist Boots"),   info = { 4, 66, "Armor", "Cloth", "INVTYPE_FEET", 132541 } },
  [18832] = { link = ilink("a335ee", 18832, "Brutality Blade"),  info = { 4, 70, "Weapon", "One-Handed Swords", "INVTYPE_WEAPON", 135313 } },
  [765]   = { link = ilink("ffffff", 765, "Silverleaf"),         info = { 1, 5, "Trade Goods", "Herb", "", "Interface\\Icons\\INV_Misc_Herb_10" } },
  [9799]  = { link = ilink("1eff00", 9799, "Durable Belt of the Bear", 1179), info = { 2, 30, "Armor", "Cloth", "INVTYPE_WAIST", 132493 } },
  [20725] = { link = ilink("0070dd", 20725, "Uncached Crystal") },   -- the client has not loaded this one yet
}
local CLOCK = 1790000100
local LOOT_WINDOW = {}      -- { { id = , quantity = , guid = } }
local MODIFIER = nil        -- "CHATLINK" / "DRESSUP" while a modified click is simulated
local CHAT_OPEN = true      -- is a chat edit box open for ChatEdit_InsertLink to write into?

local env = {
  string = string, table = table, math = math, type = type, pairs = pairs, ipairs = ipairs,
  tostring = tostring, tonumber = tonumber, pcall = pcall, error = error, select = select,
  unpack = unpack, next = next, setmetatable = setmetatable, rawget = rawget, rawset = rawset,
  print = function(...)
    local t = {}
    for i = 1, select("#", ...) do t[#t + 1] = tostring((select(i, ...))) end
    table.insert(out.prints, table.concat(t, " "))
  end,
  time = function() return 1790000000 end,
  date = function(fmt, t) return "20:26" end,
  UIParent = stub("UIParent"), Minimap = MINIMAP, GameTooltip = stub("GameTooltip"),
  ChatFontNormal = {}, GameFontHighlight = {}, GameFontHighlightSmall = {},
  SlashCmdList = {}, UISpecialFrames = {},
  CreateFrame = function(_, name, _, template) return stub(name, template) end,
  GetCursorPosition = function() return 900, 800 end,
  UnitExists = function() return true end,
  UnitName = function() return "Th\195\169oden", "Stormwind" end,
  GetRealmName = function() return "Mock Realm" end,
  GetNormalizedRealmName = function() return "MockRealm" end,
  UnitClass = function() return "Warrior", "WARRIOR" end,
  UnitRace = function() return "Human", "Human" end,
  UnitSex = function() return 2 end,
  UnitLevel = function() return 60 end,
  UnitFactionGroup = function() return "Alliance", "Alliance" end,
  GetGuildInfo = function() return "My Guild", "Officer", 1 end,
  GetCurrentRegion = function() return 1 end,
  GetBuildInfo = function() return "1.60.1", "60101", "Sep 1 2026", 16001 end,
  GetInventoryItemLink = function(unit, slot) return links[slot] end,
  GetInventoryItemQuality = function(unit, slot) return qualities[slot] end,
  GetInventoryItemTexture = function(unit, slot)
    if not links[slot] then return nil end
    if slot == 2 then return "Interface\\Icons\\INV_Jewelry_Necklace_07" end
    return 135000 + slot
  end,
  GetItemInfo = function(link)
    local loot = LOOT[itemIdOf(link) or 0]
    if loot then
      if not loot.info then return nil end
      local q, ilvl, itemType, subType, equipLoc, icon = unpack(loot.info)
      return (link:match("|h%[(.-)%]|h")), link, q, ilvl, 60, itemType, subType, 1, equipLoc, icon, 0
    end
    for slot, l in pairs(links) do
      if l == link then return "name", link, qualities[slot], levels[slot] end
    end
    return nil
  end,
  GetItemStats = function(link) return stats[itemIdOf(link)] end,
  GetNumTalentTabs = function() return 3 end,
  GetTalentTabInfo = function(t) return ({"Arms","Fury","Protection"})[t], "icon", ({31,20,0})[t], "bg" end,
  GetNumTalents = function(t) return 4 end,
  GetTalentInfo = function(t, i) return "T" .. i, "icon", 1, i, (t == 1 and i) or 0, 5 end,
  -- loot
  GetServerTime = function() return CLOCK end,
  GetRealZoneText = function() return "Molten Core" end,
  GetNumLootItems = function() return #LOOT_WINDOW end,
  GetLootSlotLink = function(i) return LOOT_WINDOW[i] and LOOT[LOOT_WINDOW[i].id].link end,
  GetLootSlotInfo = function(i) local s = LOOT_WINDOW[i]; if s then return "icon", "name", s.quantity or 1 end end,
  GetLootSourceInfo = function(i) return LOOT_WINDOW[i] and LOOT_WINDOW[i].guid end,
  IsModifiedClick = function(action) return MODIFIER == action end,
  ChatEdit_InsertLink = function(link) if not CHAT_OPEN then return false end; table.insert(out.chatLinks, link); return true end,
  ChatFrame_OpenChat = function(text) table.insert(out.chatOpened, text) end,
}

local SAVED_ENTRY = { t = 1789990000, link = ilink("0070dd", 11726, "Savage Gladiator Chain"), id = 11726,
                      name = "Savage Gladiator Chain", q = 3, to = "Old Friend", icon = 132624 }
local SAVED_ITEM = { id = 11726, name = "Savage Gladiator Chain", quality = 3, itemLevel = 55, seen = 1, first = 1789990000, last = 1789990000 }

if VARIANT == "forever" then
  -- The beta client: no GetCurrentRegion, and the portal cvar names the beta rather than a
  -- region. A beta client is a US client, and the portal is exported for the website to see.
  env.GetCurrentRegion = nil
  env.GetCVar = function(name) return name == "portal" and "beta" or nil end
  env.GetLootSourceInfo = nil   -- corpses can only be told apart by time
elseif VARIANT == "classic" then
  -- Classic Era: no last names, UnitName's second value is nil for your own character.
  env.UnitName = function() return "Th\195\169oden", nil end
  -- The last session's data is already in place when the addon's files load (Saved.lua).
  env.MintCommunityToolsDB = {
    minimapAngle = 90,   -- where version 0.1 kept it
    loot = { minQuality = 0, watch = true, log = { SAVED_ENTRY } },
    items = { [11726] = SAVED_ITEM },
  }
elseif VARIANT == "mainline" then
  -- Mainline-style client: UnitName's second value is the realm, no Classic talent API,
  -- C_Item namespace, detailed item level available, a German locale.
  env.UnitName = function() return "Th\195\169oden", "MockRealm" end
  env.GetCurrentRegion = nil
  env.GetCurrentRegionName = function() return "us" end
  env.GetNumTalentTabs = nil; env.GetTalentTabInfo = nil; env.GetNumTalents = nil; env.GetTalentInfo = nil
  local classicGetItemInfo = env.GetItemInfo
  env.GetItemInfo = nil
  env.C_Item = { GetItemInfo = classicGetItemInfo,
                 GetItemStats = env.GetItemStats,
                 GetDetailedItemLevelInfo = function(link) return 72.0, false, 66 end }
  env.GetItemStats = nil
  env.C_Timer = { After = function(t, fn) fn() end }
  env.BackdropTemplateMixin = {}
  -- Loot lines must be matched from the client's own format strings (positional arguments
  -- included), not from English.
  env.LOOT_ITEM = "%1$s erh\195\164lt Beute: %2$s."
  env.LOOT_ITEM_SELF = "Ihr erhaltet Beute: %s."
  env.LOOT_ITEM_MULTIPLE = "%1$s erh\195\164lt Beute: %2$sx%3$d."
  env.LOOT_ITEM_SELF_MULTIPLE = "Ihr erhaltet Beute: %sx%d."
end
env._G = env
setmetatable(env, { __index = function(t, k) return nil end })

local ns = {}
local before = {}
for k in pairs(env) do before[k] = true end
local function load(name, src)
  local fn, err = loadstring(src, "@" .. name)
  if not fn then error("SYNTAX " .. name .. ": " .. err) end
  setfenv(fn, env)
  fn("MintCommunityTools", ns)
end
'''

LUA_EPILOGUE = r'''
-- Minimal JSON encoder (strings, numbers, arrays, objects) for the harness result. Non-ASCII
-- bytes pass through untouched; Python decodes them as UTF-8.
local function jsonEncode(v)
  local t = type(v)
  if t == "string" then
    return '"' .. v:gsub('[%c"\\]', function(c)
      if c == '"' then return '\\"' elseif c == "\\" then return "\\\\" end
      return string.format("\\u%04x", c:byte())
    end) .. '"'
  elseif t == "number" or t == "boolean" then
    return tostring(v)
  elseif t == "nil" then
    return "null"
  elseif t == "table" then
    local parts = {}
    if next(v) == nil or v[1] ~= nil then
      for i = 1, #v do parts[i] = jsonEncode(v[i]) end
      return "[" .. table.concat(parts, ",") .. "]"
    end
    for k, x in pairs(v) do parts[#parts + 1] = jsonEncode(tostring(k)) .. ":" .. jsonEncode(x) end
    return "{" .. table.concat(parts, ",") .. "}"
  end
  error("jsonEncode: unsupported type " .. t)
end

local slash = env.SlashCmdList["MINTCOMMUNITYTOOLS"]
assert(slash, "slash command not registered")
assert(env.SLASH_MINTCOMMUNITYTOOLS1 == "/mint", "primary slash command")

fire("ADDON_LOADED", "SomeOtherAddon")
fire("ADDON_LOADED", "MintCommunityTools")
assert(env.MintCommunityToolsDB, "saved variables table created at ADDON_LOADED")
fire("PLAYER_LOGIN")
fire("PLAYER_ENTERING_WORLD")

---------------------------------------------------------------------------
-- The minimap button: on the minimap's edge, where it was left
---------------------------------------------------------------------------
local mm = frameNamed("MintCommunityToolsMinimapButton")
assert(mm._shown, "the minimap button is shown at login")
local function minimapAt()
  local p = mm._point
  assert(p[1] == "CENTER" and p[2] == env.Minimap and p[3] == "CENTER", "anchored to the minimap's centre")
  return p[4], p[5]
end
local mx, my = minimapAt()
local minimapRadius = math.sqrt(mx * mx + my * my)
local minimapStart = { mx, my }
-- Dragging: the cursor is straight above the minimap's centre, so the button goes to the top.
mm._scripts.OnDragStart(mm)
mm._scripts.OnUpdate(mm)
mm._scripts.OnDragStop(mm)
assert(mm._scripts.OnUpdate == nil, "dragging stops following the cursor")
local dx, dy = minimapAt()
assert(math.abs(dx) < 0.001 and math.abs(dy - 75) < 0.001, "dragged to the top of the minimap: " .. dx .. ", " .. dy)
assert(math.abs(env.MintCommunityToolsDB.minimap.angle - 90) < 0.001, "the new place is saved")
slash("minimap hide")
assert(not mm._shown and env.MintCommunityToolsDB.minimap.shown == false, "/mint minimap hide")
slash("minimap")
assert(mm._shown, "/mint minimap shows it again")
slash("minimap reset")
local rx, ry = minimapAt()
assert(math.abs(rx - math.cos(math.rad(200)) * 75) < 0.001 and math.abs(ry - math.sin(math.rad(200)) * 75) < 0.001, "reset to the default place")

-- The loot watcher comes back at login when it was left on.
local watchAtLogin = ns.lootui.watchFrame and ns.lootui.watchFrame._shown or false

slash("selftest")
slash("debug")
slash("scan")
slash("help")

---------------------------------------------------------------------------
-- The window and the Gear tab
---------------------------------------------------------------------------
slash("")
local frame = frameNamed("MintCommunityToolsFrame")
assert(frame._shown, "/mint opens the window")
assert(ns.UI.CurrentTab() == "gear" and ns.ui.panels.gear._shown and not ns.ui.panels.loot._shown, "on the Gear tab")
assert(ns.ui.rows and #ns.ui.rows == 19, "one row per equipment slot")
assert(ns.ui.rows[1].item and ns.ui.rows[1].item.id == 12640, "row 1 shows the helm")
assert(not ns.ui.rows[3].item, "row 3 (shoulder) is empty")
local whoText = ns.ui.who:GetText()
local summaryText = ns.ui.summary:GetText()

-- Gear changes while the window is open refresh the list.
fire("PLAYER_EQUIPMENT_CHANGED", 1, false)
fire("UNIT_INVENTORY_CHANGED", "player")

click("MintCommunityToolsRescanButton")
click("MintCommunityToolsExportButton")
assert(ns.lastExport and ns.lastExport.str, "Export button produced a string")
local exportText = ns.ui.editBox:GetText()
assert(exportText == ns.lastExport.str, "the copy box holds the export string")
local statusAfterExport = ns.ui.status:GetText()

-- Typing into the copy box restores the export.
ns.ui.editBox._text = "garbage"
ns.ui.editBox._scripts.OnTextChanged(ns.ui.editBox, true)
assert(ns.ui.editBox:GetText() == exportText, "the copy box is read-only")

-- /mint json shows the JSON the string wraps.
slash("json")
local jsonText = ns.ui.editBox:GetText()

-- /mint export from a closed window opens it again.
slash("")
assert(not frame._shown, "/mint toggles the window closed")
slash("export")
assert(frame._shown, "/mint export opens the window")
assert(ns.ui.editBox:GetText() == exportText, "/mint export puts the string back in the box")

-- /mint region overrides whatever the client said (or failed to say), and survives a reload
-- on clients that load saved variables.
slash("region")
slash("region eu")
assert(env.MintCommunityToolsDB.region == "EU", "region kept in saved variables")
slash("export")
local regionExport = ns.ui.editBox:GetText()
slash("region xx")

---------------------------------------------------------------------------
-- Loot
---------------------------------------------------------------------------
local german = VARIANT == "mainline"
local function receives(who, link, count)
  local n = count and ("x" .. count) or ""
  if german then
    if who then return who .. " erh\195\164lt Beute: " .. link .. n .. "." end
    return "Ihr erhaltet Beute: " .. link .. n .. "."
  end
  if who then return who .. " receives loot: " .. link .. n .. "." end
  return "You receive loot: " .. link .. n .. "."
end
local L = function(id) return LOOT[id].link end
local function logSize() return #ns.Loot.Entries(0) end
local savedBefore = logSize()   -- what the last session left (classic only)

-- 1. You loot a pair of boots.
fire("CHAT_MSG_LOOT", receives(nil, L(16800)))
assert(logSize() == savedBefore + 1, "a loot line is logged")

-- The client hands the saved data over after the addon has started fresh (mainline only):
-- the saved log comes first, and what this session has seen follows it.
if VARIANT == "mainline" then
  env.MintCommunityToolsDB = { minimap = { angle = 45 }, loot = { log = { SAVED_ENTRY }, watch = false }, items = { [11726] = SAVED_ITEM } }
  fire("PLAYER_ENTERING_WORLD")
  assert(ns.db == env.MintCommunityToolsDB, "the saved table is the one in use")
  assert(logSize() == 2 and ns.Loot.Entries(0)[1].id == 16800 and ns.Loot.Entries(0)[2].id == 11726, "this session's loot follows the saved log")
  assert(ns.db.region == "EU", "what was set this session is carried over")
  savedBefore = 1
  fire("PLAYER_ENTERING_WORLD")
  assert(logSize() == 2, "adopting twice changes nothing")
end

-- 2. A corpse with two blades, three herbs in one stack, and an item the client has not loaded.
CLOCK = CLOCK + 60
LOOT_WINDOW = { { id = 18832, guid = "Creature-0-1" }, { id = 18832, guid = "Creature-0-1" },
                { id = 765, quantity = 3, guid = "Creature-0-1" }, { id = 20725, guid = "Creature-0-1" } }
fire("LOOT_READY")
fire("LOOT_OPENED")
assert(logSize() == savedBefore + 5, "two blades, a stack of herbs and the crystal: " .. logSize())
-- Opened again after one blade was taken: nothing new.
LOOT_WINDOW = { { id = 18832, guid = "Creature-0-1" }, { id = 765, quantity = 3, guid = "Creature-0-1" } }
fire("LOOT_OPENED")
assert(logSize() == savedBefore + 5, "re-opening a corpse adds nothing")

-- 3. One blade goes to a group member: that fills in the drop, it does not add one.
CLOCK = CLOCK + 5
fire("CHAT_MSG_LOOT", receives("Bravo Testa", L(18832)))
assert(logSize() == savedBefore + 5, "a drop that is handed out is one entry")

-- 4. A random-suffix item, seen only as a loot line; lines that are not loot.
fire("CHAT_MSG_LOOT", receives("Charlie", L(9799)))
fire("CHAT_MSG_LOOT", "Bravo creates: something.")
fire("CHAT_MSG_LOOT", receives("Charlie", "3 Silver"))
assert(logSize() == savedBefore + 6, "only item loot lines count")

-- 5. Fast looting: the chat line arrives before the window event. Still one entry.
CLOCK = CLOCK + 60
fire("CHAT_MSG_LOOT", receives(nil, L(16800), 2))
LOOT_WINDOW = { { id = 16800, quantity = 2, guid = "Creature-0-2" } }
fire("LOOT_OPENED")
assert(logSize() == savedBefore + 7, "a line and then its window are one entry")

-- 6. The client loads the crystal's details late.
LOOT[20725].info = { 3, 60, "Gem", "Simple", "", 134104 }
fire("GET_ITEM_INFO_RECEIVED", 20725, true)

local entries = {}
for i, e in ipairs(ns.Loot.Entries(0)) do
  entries[i] = { id = e.id, name = e.name, q = e.q, to = e.to or false, mine = e.mine or false, n = e.n or 1,
                 window = e.window or false, icon = tostring(e.icon), zone = e.zone or false }
end
local drops, itemsSeen = ns.Loot.Counts()
local minimapLines = ns.MinimapLines()

---------------------------------------------------------------------------
-- The Loot tab
---------------------------------------------------------------------------
slash("loot")
assert(frame._shown and ns.UI.CurrentTab() == "loot" and ns.ui.panels.loot._shown and not ns.ui.panels.gear._shown, "/mint loot opens the Loot tab")
assert(#ns.lootui.rows == 18, "rows on the Loot tab")
local function shownRows()
  local t = {}
  for _, row in ipairs(ns.lootui.rows) do
    if row._shown and row.entry then t[#t + 1] = { id = row.entry.id, name = row.name:GetText(), who = row.who:GetText(), icon = tostring(row.icon._texture) } end
  end
  return t
end
env.MintCommunityToolsDB.loot.minQuality = 2
ns.LootUI.Refresh()
local rowsUncommon = shownRows()
local countUncommon = ns.lootui.count:GetText()
local filterLabels = { ns.lootui.filter:GetText() }
for _ = 1, 4 do
  click("MintCommunityToolsLootFilterButton")
  filterLabels[#filterLabels + 1] = ns.lootui.filter:GetText()
end
assert(env.MintCommunityToolsDB.loot.minQuality == 2, "the filter goes all the way round")
click("MintCommunityToolsLootFilterButton"); click("MintCommunityToolsLootFilterButton"); click("MintCommunityToolsLootFilterButton")
assert(env.MintCommunityToolsDB.loot.minQuality == 0, "showing everything")
local rowsAll = shownRows()
local countAll = ns.lootui.count:GetText()

-- Hovering a row shows the item's tooltip; a plain click does nothing.
local first = ns.lootui.rows[1]
first._scripts.OnEnter(first)
first._scripts.OnLeave(first)
first._scripts.OnClick(first, "LeftButton")
assert(#out.chatLinks == 0 and #out.chatOpened == 0, "a plain click links nothing")
-- Shift-click links the item into the open chat box, whole.
MODIFIER = "CHATLINK"
first._scripts.OnClick(first, "LeftButton")
assert(#out.chatLinks == 1 and out.chatLinks[1] == first.entry.link, "shift-click links the item in chat")
-- With no chat box open, one is opened with the link in it.
CHAT_OPEN = false
first._scripts.OnClick(first, "LeftButton")
assert(#out.chatOpened == 1 and out.chatOpened[1] == first.entry.link, "shift-click opens chat with the link")
CHAT_OPEN = true
MODIFIER = nil
local linked = out.chatLinks[1]

-- Export new items: a string to paste on the website. Nothing counts as exported until Done.
local hintBefore = ns.lootui.hint:GetText()
local pendingBefore = ns.Loot.PendingCount()
assert(pendingBefore == itemsSeen, "nothing has been exported yet, so every item seen is new")
assert(not ns.lootui.confirm._shown, "no Done button until there is something to paste")
click("MintCommunityToolsLootExportButton")
local itemsString = ns.lootui.box.editBox:GetText()
local itemsStatus = ns.lootui.status:GetText()
assert(ns.lootui.confirm._shown and ns.lootui.confirm:GetText() == "Done", "a single string ends with Done")
assert(ns.Loot.PendingCount() == pendingBefore, "copying is not pasting: nothing is marked yet")
-- Walking away and exporting again gives the same items.
slash("")
slash("loot")
click("MintCommunityToolsLootExportButton")
assert(ns.lootui.box.editBox:GetText() == itemsString, "an export that was never confirmed is offered again")
click("MintCommunityToolsLootConfirmButton")
assert(ns.Loot.PendingCount() == 0, "Done marks the items as exported")
assert(not ns.lootui.confirm._shown and ns.lootui.box.editBox:GetText() == "", "and clears the box")
local doneStatus = ns.lootui.status:GetText()
local hintAfter = ns.lootui.hint:GetText()
click("MintCommunityToolsLootExportButton")
local nothingStatus = ns.lootui.status:GetText()
assert(ns.lootui.box.editBox:GetText() == "" and not ns.lootui.confirm._shown, "nothing new: nothing to copy")
-- Seeing an item again, unchanged, does not make it new; a change does (WoW Forever retuned it).
fire("CHAT_MSG_LOOT", receives("Charlie", L(16800)))
assert(ns.Loot.PendingCount() == 0, "the same item again is not news")
LOOT[16800].info[2] = 68
fire("CHAT_MSG_LOOT", receives("Charlie", L(16800)))
assert(ns.Loot.PendingCount() == 1, "an item that changed is exported again")
click("MintCommunityToolsLootExportButton")
local changedString = ns.lootui.box.editBox:GetText()
click("MintCommunityToolsLootConfirmButton")
assert(ns.Loot.PendingCount() == 0)

-- Switching tabs by their buttons.
click("MintCommunityToolsTab1")
assert(ns.UI.CurrentTab() == "gear" and ns.ui.panels.gear._shown and not ns.ui.panels.loot._shown, "back on the Gear tab")
click("MintCommunityToolsTab2")
assert(ns.UI.CurrentTab() == "loot", "and on the Loot tab again")
slash("items")
assert(ns.lootui.box.editBox:GetText() == "", "/mint items: nothing new")
slash("items all")
local allString = ns.lootui.box.editBox:GetText()
assert(allString ~= "" and ns.lootui.confirm._shown, "/mint items all exports everything again")
click("MintCommunityToolsTab1"); click("MintCommunityToolsTab2")

---------------------------------------------------------------------------
-- The loot watcher
---------------------------------------------------------------------------
local function watchShown() return ns.lootui.watchFrame and ns.lootui.watchFrame._shown or false end
if watchShown() then slash("watch") end
assert(not watchShown() and env.MintCommunityToolsDB.loot.watch == false, "the watcher is off")
slash("watch")
assert(watchShown() and env.MintCommunityToolsDB.loot.watch == true, "/mint watch shows the loot watcher")
assert(frameNamed("MintCommunityToolsLootWatch") == ns.lootui.watchFrame)
assert(#ns.lootui.watchRows == 8 and ns.lootui.watchRows[1].entry == ns.Loot.Entries(0)[1], "the watcher shows the newest drops")
local watchButton = ns.lootui.watch:GetText()
-- New loot appears in it as it happens.
CLOCK = CLOCK + 30
fire("CHAT_MSG_LOOT", receives("Delta", L(16800)))
assert(ns.lootui.watchRows[1].entry.to == "Delta", "the watcher follows new loot")
assert(ns.lootui.rows[1].entry.to == "Delta", "and so does the open Loot tab")
-- Right-click on the minimap button toggles it; its own X turns it off.
mm._scripts.OnClick(mm, "RightButton")
assert(not watchShown(), "right-click on the minimap button hides the watcher")
mm._scripts.OnClick(mm, "RightButton")
assert(watchShown())
ns.lootui.watchFrame.close._scripts.OnClick(ns.lootui.watchFrame.close)
assert(not watchShown() and env.MintCommunityToolsDB.loot.watch == false, "closing the watcher turns it off")
-- Left-click toggles the main window.
mm._scripts.OnClick(mm, "LeftButton")
assert(not frame._shown, "left-click on the minimap button closes the open window")
mm._scripts.OnClick(mm, "LeftButton")
assert(frame._shown and ns.UI.CurrentTab() == "loot", "and opens it on the tab it was on")
mm._scripts.OnEnter(mm)
mm._scripts.OnLeave(mm)

-- What would be written to the saved variables at logout.
local sdb = env.MintCommunityToolsDB
local state = { log = #sdb.loot.log, lastTo = sdb.loot.log[#sdb.loot.log].to, watch = sdb.loot.watch, region = sdb.region,
  bladeSeen = sdb.items[18832].seen, bootsSeen = sdb.items[16800].seen, bootsSent = sdb.items[16800].sent,
  oldAngle = sdb.minimapAngle ~= nil, angle = type(sdb.minimap.angle) }

-- The log is capped; clearing it keeps the items seen.
for i = 1, 520 do ns.Loot.OnLootMessage(receives("Filler", L(765))) end
assert(logSize() == 500, "the log keeps the last 500 drops: " .. logSize())

-- The watcher scrolls back through the last 100 drops with the mouse wheel.
slash("watch")
local wf, wrows = ns.lootui.watchFrame, ns.lootui.watchRows
local function position() return ns.lootui.watchPosition:GetText() end
local function latestShown() return ns.lootui.watchLatest._shown end
local all = ns.Loot.Entries(0)
assert(wrows[1].entry == all[1] and position() == "1-8 of 100" and not latestShown(), "it opens on the newest drops: " .. position())
wf._scripts.OnMouseWheel(wf, 1)
assert(wrows[1].entry == all[1] and position() == "1-8 of 100", "wheel up at the top stays at the top")
wf._scripts.OnMouseWheel(wf, -1)
assert(wrows[1].entry == all[3] and wrows[8].entry == all[10] and position() == "3-10 of 100", "a notch down is two rows: " .. position())
assert(latestShown(), "Latest appears once scrolled back")
-- New loot while scrolled back: the same drops stay in view, one place further down.
fire("CHAT_MSG_LOOT", receives("Echo", L(16800)))
assert(ns.Loot.Entries(0)[1].to == "Echo" and wrows[1].entry == all[3] and position() == "4-11 of 100", "new loot does not move the view: " .. position())
wf._scripts.OnMouseWheel(wf, 1)
assert(wrows[1].entry == all[1] and position() == "2-9 of 100", "a notch up: " .. position())
-- The far end is the hundredth drop, however far the wheel turns.
for _ = 1, 80 do wf._scripts.OnMouseWheel(wf, -1) end
assert(position() == "93-100 of 100" and wrows[8].entry == ns.Loot.Entries(0)[100], "capped at the last 100: " .. position())
click("MintCommunityToolsLootWatchLatestButton")
assert(wrows[1].entry.to == "Echo" and position() == "1-8 of 100" and not latestShown(), "Latest returns to the newest")
-- A filter that leaves fewer drops than rows: nothing to scroll, no position shown.
wf._scripts.OnMouseWheel(wf, -1)
env.MintCommunityToolsDB.loot.minQuality = 4
ns.LootUI.Refresh()
assert(position() == "" and not latestShown() and wrows[1].entry and wrows[1].entry.q == 4, "few drops: no scrolling")
env.MintCommunityToolsDB.loot.minQuality = 0
-- Reopening starts at the newest again.
wf._scripts.OnMouseWheel(wf, -3)
slash("watch"); slash("watch")
assert(position() == "1-8 of 100", "reopened on the newest")
slash("watch")
-- A long export is split: a hundred items to a string, one part at a time.
for i = 1, 250 do ns.Loot.OnLootMessage(receives("Filler", ilink("ffffff", 50000 + i, "Filler Item " .. i))) end
assert(ns.Loot.PendingCount() == 250)
slash("loot")
local chunks, chunkStatus, chunkButtons = {}, {}, {}
click("MintCommunityToolsLootExportButton")
for part = 1, 3 do
  chunks[part] = ns.lootui.box.editBox:GetText()
  chunkStatus[part] = ns.lootui.status:GetText()
  chunkButtons[part] = ns.lootui.confirm:GetText()
  assert(ns.Loot.PendingCount() == 250 - (part - 1) * 100, "each part is marked when it is confirmed")
  click("MintCommunityToolsLootConfirmButton")
end
assert(ns.Loot.PendingCount() == 0 and not ns.lootui.confirm._shown, "all three parts exported")
local chunkDone = ns.lootui.status:GetText()

local beforeClear = { ns.Loot.Counts() }
click("MintCommunityToolsLootClearButton")
local afterClear = { ns.Loot.Counts() }
assert(afterClear[1] == 0 and afterClear[2] == beforeClear[2], "clearing the log keeps the items seen")

---------------------------------------------------------------------------
-- The flat skin: none of Blizzard's frame art anywhere
---------------------------------------------------------------------------
local BLIZZARD_TEMPLATES = { UIPanelButtonTemplate = true, UIPanelCloseButton = true, UICheckButtonTemplate = true,
                             InputBoxTemplate = true, BasicFrameTemplate = true, UIPanelScrollFrameTemplate = true }
local windows, skinned = 0, 0
for _, f in ipairs(out.frames) do
  local name, template, bd = rawget(f, "_name"), rawget(f, "_template"), rawget(f, "_backdrop")
  assert(not BLIZZARD_TEMPLATES[template or ""], (name or "a frame") .. " was created with " .. tostring(template))
  if type(bd) == "table" then
    skinned = skinned + 1
    for _, file in ipairs({ bd.bgFile, bd.edgeFile }) do
      assert(not (type(file) == "string" and (file:find("DialogBox") or file:find("Tooltip%-Border"))),
        (name or "a frame") .. " has a Blizzard border: " .. tostring(file))
    end
    assert(bd.edgeFile == "Interface\\Buttons\\WHITE8X8" and bd.bgFile == "Interface\\Buttons\\WHITE8X8", "flat backdrop on " .. tostring(name))
  end
  if name == "MintCommunityToolsFrame" or name == "MintCommunityToolsLootWatch" or name == "MintCommunityToolsMinimapButton" then
    windows = windows + 1
    assert(type(bd) == "table", name .. " is skinned")
    local close = rawget(f, "close")
    assert(close == nil or rawget(close, "_template") ~= "UIPanelCloseButton", name .. " has a flat close button")
  end
end
assert(windows == 3, "both windows and the minimap button were seen: " .. windows)
assert(skinned >= 29, "panels, buttons and boxes are skinned: " .. skinned)
assert(rawget(frame, "titleBar") and rawget(frame, "title") and rawget(frame, "close") and frame.close._scripts.OnClick, "the window has a title strip with a close button")
assert(rawget(ns.lootui.watchFrame, "titleBar") and ns.lootui.watchLatest._scripts.OnClick, "the watcher has a title strip with Latest on it")

local newg = {}
for k in pairs(env) do if not before[k] then newg[#newg + 1] = k end end
table.sort(newg)
local RESULT = jsonEncode({ prints = out.prints, export = exportText, json = jsonText, newglobals = newg,
  who = whoText, summary = summaryText, status = statusAfterExport, regionExport = regionExport,
  minimapRadius = minimapRadius, minimapStart = minimapStart, watchAtLogin = watchAtLogin,
  entries = entries, drops = drops, itemsSeen = itemsSeen, minimapLines = minimapLines,
  rowsUncommon = rowsUncommon, countUncommon = countUncommon, rowsAll = rowsAll, countAll = countAll,
  filterLabels = filterLabels, linked = linked, itemsString = itemsString, itemsStatus = itemsStatus,
  doneStatus = doneStatus, nothingStatus = nothingStatus, changedString = changedString, allString = allString,
  hintBefore = hintBefore, hintAfter = hintAfter, chunks = chunks, chunkStatus = chunkStatus,
  chunkButtons = chunkButtons, chunkDone = chunkDone, watchButton = watchButton, state = state })
io.write(RESULT)
'''


def build_script(variant):
    parts = [f'local VARIANT = "{variant}"', LUA_PRELUDE]
    for name in FILES:
        src = (ADDON_DIR / name).read_text(encoding="utf-8")
        if "]==]" in src:
            raise SystemExit(f"{name} contains ']==]', which breaks the test loader")
        parts.append(f'load("{name}", [==[{src}]==])')
    parts.append(LUA_EPILOGUE)
    return "\n".join(parts)


# ---------------------------------------------------------------------------
# Interpreter selection
# ---------------------------------------------------------------------------
LUA_CANDIDATES = ["luajit", "lua5.1", "lua-5.1", "lua51", "lua"]


def lua_version(exe):
    try:
        r = subprocess.run([exe, "-e", "io.write(_VERSION)"], capture_output=True, text=True, timeout=10)
    except OSError:
        return None
    return r.stdout.strip() if r.returncode == 0 else None


def find_lua():
    override = os.environ.get("LUA")
    if override:
        exe = shutil.which(override) or override
        version = lua_version(exe)
        if version != "Lua 5.1":
            raise SystemExit(f"$LUA={override} reports {version!r}, need 'Lua 5.1' (WoW's Lua version)")
        return exe
    for name in LUA_CANDIDATES:
        exe = shutil.which(name)
        if exe and lua_version(exe) == "Lua 5.1":
            return exe
    raise SystemExit(
        "No Lua 5.1 interpreter found. Install LuaJIT (macOS: `brew install luajit`; "
        "Debian/Ubuntu: `apt install luajit` or `apt install lua5.1`), or set $LUA to one."
    )


# ---------------------------------------------------------------------------
# Checks
# ---------------------------------------------------------------------------
def strip_colors(s):
    return re.sub(r"\|c[0-9a-fA-F]{8}|\|r", "", s)


def decode(string):
    """The decoding procedure from the spec, independent of the addon's own code."""
    prefix, body, checksum = string.strip().split(":")
    assert prefix == "GAE1", prefix
    raw = base64.b64decode(body, validate=True)
    assert format(zlib.adler32(raw) & 0xFFFFFFFF, "08x") == checksum, "adler32 differs from zlib's"
    return json.loads(raw.decode("utf-8")), raw


def check_version():
    """The .toc and Core.lua must agree on the version; the release workflow tags by it."""
    toc = re.search(r"^## Version:\s*(\S+)", (ADDON_DIR / "MintCommunityTools.toc").read_text(encoding="utf-8"), re.M)
    core = re.search(r'^ns\.VERSION = "([^"]+)"', (ADDON_DIR / "Core.lua").read_text(encoding="utf-8"), re.M)
    if not toc or not core or toc.group(1) != core.group(1):
        raise SystemExit(f"version mismatch: .toc says {toc and toc.group(1)}, Core.lua says {core and core.group(1)}")
    return toc.group(1)


def check_toc():
    """Every file the harness loads is in the .toc, in the same order, and exists."""
    listed = [l.strip() for l in (ADDON_DIR / "MintCommunityTools.toc").read_text(encoding="utf-8").splitlines()
              if l.strip() and not l.startswith("#")]
    assert listed == ["Saved.lua"] + FILES, f".toc lists {listed}, the harness loads {FILES}"
    for name in FILES:
        assert (ADDON_DIR / name).is_file(), f"{name} is in the .toc but not in the folder"


VERSION = check_version()


def check_gear(result, variant):
    data, raw = decode(result["export"])
    assert result["json"] == raw.decode("utf-8"), "/mint json differs from the string's payload"
    assert len(result["export"]) < 64 * 1024, "the website rejects strings over 64 KB"
    if VERBOSE:
        print(f"--- decoded export ({variant}) ---")
        print(json.dumps(data, indent=2, ensure_ascii=False))

    assert data["v"] == 1 and data["src"] == "self" and data["ts"] == 1790000000
    assert "kind" not in data, "a character export has no kind key"
    assert data["addon"] == {"name": "MintCommunityTools", "version": VERSION}
    assert {k: v for k, v in data["game"].items() if k != "portal"} == {"version": "1.60.1", "build": "60101", "toc": 16001}

    c = data["char"]
    assert c["name"] == "Théoden"  # UTF-8 survives the round trip
    assert c["realm"] == "Mock Realm" and c["realmSlug"] == "MockRealm" and c["region"] == "US"
    assert c["class"] == "Warrior" and c["classFile"] == "WARRIOR" and c["level"] == 60
    assert c["guild"] == "My Guild" and c["guildRank"] == "Officer" and c["faction"] == "Alliance"
    if variant == "forever":
        assert c["lastName"] == "Stormwind", "UnitName's second value is the last name on WoW Forever"
        assert "Théoden Stormwind" in strip_colors(result["who"])
    else:
        assert "lastName" not in c, f"no last name expected on {variant}: {c.get('lastName')!r}"

    items = {i["slot"]: i for i in data["items"]}
    assert sorted(items) == [1, 2, 4, 5, 16, 17], sorted(items)
    for item in data["items"]:
        assert set(item) <= {"slot", "id", "name", "quality", "ilvl", "enchant", "gems", "suffix", "icon", "stats"}, item
    assert items[1]["id"] == 12640 and "enchant" not in items[1] and "gems" not in items[1]
    assert items[1]["quality"] == 4 and items[5]["quality"] == 3 and items[16]["quality"] == 5
    assert items[2]["enchant"] == 2564 and items[2]["gems"] == [2345] and items[2]["suffix"] == -25
    assert items[2]["icon"] == "Interface\\Icons\\INV_Jewelry_Necklace_07"  # string icon kept as-is
    assert isinstance(items[1]["icon"], int)                                 # numeric icon kept as-is
    assert items[5]["enchant"] == 1892 and items[5]["gems"] == [3, 4]
    assert items[16]["id"] == 19019 and "enchant" not in items[16]            # empty enchant field
    assert items[16]["name"] == "Thunderfury, Blessed Blade of the Windseeker"
    assert items[17]["name"] == 'Test "Quoted" \\ Item'                        # JSON escaping

    # Item stats: exactly what the client reported, zero values and empty blocks left out.
    assert items[1]["stats"] == {"ITEM_MOD_STRENGTH_SHORT": 18, "ITEM_MOD_AGILITY_SHORT": 18, "ITEM_MOD_CRIT_RATING_SHORT": 2}
    assert items[16]["stats"]["ITEM_MOD_DAMAGE_PER_SECOND_SHORT"] == 53.9
    assert "stats" not in items[4] and "stats" not in items[2]

    summary = strip_colors(result["summary"])
    if variant == "mainline":
        assert all(i["ilvl"] == 72 for i in data["items"])   # detailed item level path, float floored
        assert "talents" not in data                        # no talent API: omitted, not an error
        assert "talentsError" not in data
        assert "6 items equipped  -  average item level 72  -  2 enchanted" in summary, summary
        assert "Talents" not in summary
    else:
        assert items[1]["ilvl"] == 66 and items[4]["ilvl"] == 1
        trees = data["talents"]
        assert [t["name"] for t in trees] == ["Arms", "Fury", "Protection"]
        assert trees[0]["ranks"] == "1234" and trees[0]["points"] == 31 and trees[2]["ranks"] == "0000"
        # average over 66, 74, 55, 80, 10 (shirt left out) = 57
        assert "6 items equipped  -  average item level 57  -  2 enchanted" in summary, summary
        assert "Talents: Arms 31  /  Fury 20  /  Protection 0" in summary, summary

    status = strip_colors(result["status"])
    assert status.startswith("Exported at 20:26: ") and "6 items. Press Ctrl+C now." in status, status

    # Region: US by every route, and "assumed" is said out loud only when nothing answered.
    who = strip_colors(result["who"])
    if variant == "forever":
        assert "Mock Realm (US, beta)" in who, who                # portal "beta" -> a US test client
        assert data["game"]["portal"] == "beta"
        assert "assumed" not in strip_colors(result["status"])
    else:
        assert "Mock Realm (US)" in who, who
        assert "portal" not in data["game"]
    overridden, _ = decode(result["regionExport"])
    assert overridden["char"]["region"] == "EU", "/mint region eu changes the export"
    return data


def check_loot(result, variant):
    saved = 0 if variant == "forever" else 1      # classic and mainline start with one saved drop
    me = "Théoden Stormwind" if variant == "forever" else "Théoden"

    entries = result["entries"]
    if VERBOSE:
        print(f"--- loot log, newest first ({variant}) ---")
        for e in entries:
            print(f"  {e['name']} x{e['n']}  to={e['to']}  mine={e['mine']}  window={e['window']}  q={e['q']}  icon={e['icon']}")
    assert result["drops"] == len(entries) == 7 + saved, len(entries)
    got = [(e["name"], e["n"], e["to"], e["mine"], e["window"]) for e in entries]
    expected = [
        ("Arcanist Boots", 2, me, True, True),                 # the line came first, then its window
        ("Durable Belt of the Bear", 1, "Charlie", False, False),
        ("Uncached Crystal", 1, False, False, True),
        ("Silverleaf", 3, False, False, True),
        ("Brutality Blade", 1, "Bravo Testa", False, True),    # the NEWEST pending blade is the one handed out
        ("Brutality Blade", 1, False, False, True),
        ("Arcanist Boots", 1, me, True, False),
    ]
    if saved:
        expected.append(("Savage Gladiator Chain", 1, "Old Friend", False, False))
    assert got == expected, got
    by_name = {e["name"]: e for e in entries}
    assert by_name["Brutality Blade"]["q"] == 4 and by_name["Brutality Blade"]["icon"] == "135313"
    assert by_name["Silverleaf"]["icon"] == "Interface\\Icons\\INV_Misc_Herb_10", "a texture path is kept as the icon"
    assert by_name["Uncached Crystal"]["q"] == 3 and by_name["Uncached Crystal"]["icon"] == "134104", "details that arrive late are filled in"
    assert by_name["Durable Belt of the Bear"]["q"] == 2 and by_name["Arcanist Boots"]["zone"] == "Molten Core"

    # The Loot tab: names in the colour of their quality, who looted, the item's own icon.
    rows = result["rowsUncommon"]
    assert [r["id"] for r in rows] == [e["id"] for e in entries if e["q"] >= 2], rows
    assert rows[0]["name"] == "|cffa335eeArcanist Boots|r |cffffffffx2|r", rows[0]
    assert rows[0]["who"] == "|cff7fe5a8You|r" and rows[0]["icon"] == "132541"
    assert rows[1]["name"] == "|cff1eff00Durable Belt of the Bear|r" and rows[1]["who"] == "Charlie"
    assert rows[2]["name"] == "|cff0070ddUncached Crystal|r" and rows[2]["who"] == "|cff888888not looted|r"
    assert result["countUncommon"] == f"{6 + saved} of {7 + saved} drops", result["countUncommon"]
    assert [r["id"] for r in result["rowsAll"]] == [e["id"] for e in entries]
    assert result["rowsAll"][3]["name"] == "|cffffffffSilverleaf|r |cffffffffx3|r"
    assert result["countAll"] == f"{7 + saved} drops", result["countAll"]
    assert result["filterLabels"] == ["Showing: Uncommon and better", "Showing: Rare and better", "Showing: Epic and better",
                                      "Showing: Everything", "Showing: Uncommon and better"], result["filterLabels"]
    assert result["watchButton"] == "Hide loot watcher"
    assert result["watchAtLogin"] is (variant == "classic"), "the watcher comes back at login only when it was left on"

    # A chat link is the item's whole link, as a bag item's would be.
    assert result["linked"] == "|cffa335ee|Hitem:16800:0:0:0:0:0:0:0:60|h[Arcanist Boots]|h|r", result["linked"]

    check_item_export(result, variant, saved)


def decode_items(string, index=1, of=1):
    """An item export, checked against docs/item-export-format-v1.md."""
    doc, _ = decode(string)
    assert len(string) < 256 * 1024, "the website takes at most 256 KB per string"
    assert doc["v"] == 1 and doc["kind"] == "items" and doc["ts"] == 1790000000
    assert doc["addon"] == {"name": "MintCommunityTools", "version": VERSION}
    assert doc["game"]["toc"] == 16001 and doc["game"]["version"] == "1.60.1"
    assert doc["part"] == {"index": index, "of": of}, doc["part"]
    assert set(doc) == {"v", "kind", "ts", "addon", "game", "by", "part", "items"}, sorted(doc)
    assert 1 <= len(doc["items"]) <= 100
    ids = [i["id"] for i in doc["items"]]
    assert len(set(ids)) == len(ids), "an item appears once per string"
    for item in doc["items"]:
        assert set(item) <= set(ITEM_KEYS) and isinstance(item["id"], int) and item["name"], item
    return doc


def check_item_export(result, variant, saved):
    doc = decode_items(result["itemsString"])
    by = {"name": "Théoden", "realm": "Mock Realm", "region": "EU"}   # set with /mint region earlier in the run
    if variant == "forever":
        by["lastName"] = "Stormwind"
        assert doc["game"]["portal"] == "beta"
    assert doc["by"] == by, doc["by"]

    # The suffix item is not exported (its ID is shared by every "of the ..." variant).
    items = {i["id"]: i for i in doc["items"]}
    assert sorted(items) == sorted([765, 16800, 18832, 20725] + ([11726] if saved else [])), sorted(items)
    assert result["itemsSeen"] == len(items)
    assert items[16800] == {"id": 16800, "name": "Arcanist Boots", "quality": 4, "itemLevel": 66, "itemClass": "Armor",
                            "itemSubclass": "Cloth", "equipLoc": "INVTYPE_FEET", "icon": 132541,
                            "stats": {"ITEM_MOD_STAMINA_SHORT": 13, "ITEM_MOD_INTELLECT_SHORT": 14}}, items[16800]
    assert items[18832]["stats"]["ITEM_MOD_DAMAGE_PER_SECOND_SHORT"] == 56.5 and items[18832]["itemSubclass"] == "One-Handed Swords"
    assert items[765] == {"id": 765, "name": "Silverleaf", "quality": 1, "itemLevel": 5, "itemClass": "Trade Goods",
                          "itemSubclass": "Herb", "icon": "Interface\\Icons\\INV_Misc_Herb_10"}, items[765]
    assert items[20725] == {"id": 20725, "name": "Uncached Crystal", "quality": 3, "itemLevel": 60, "itemClass": "Gem",
                            "itemSubclass": "Simple", "icon": 134104}, items[20725]
    assert doc["items"][0]["id"] == 16800, "most recently seen first"
    if saved:
        assert items[11726] == {"id": 11726, "name": "Savage Gladiator Chain", "quality": 3, "itemLevel": 55}, "from the last session"

    n = len(items)
    assert strip_colors(result["itemsStatus"]) == f"{n} items. Press Ctrl+C, paste it on the website's Items page, then click Done."
    assert strip_colors(result["doneStatus"]) == f"Exported {n} items. They wait for an officer's approval on the website."
    assert strip_colors(result["nothingStatus"]) == "Nothing new to export. Export all sends every item again."
    assert f"{n} new items to export for the website's item database." in strip_colors(result["hintBefore"])
    assert "No new items to export" in strip_colors(result["hintAfter"])
    assert result["minimapLines"] == [["Drops in the loot log", str(7 + saved)], ["Items seen", str(n)], ["New items to export", str(n)]]

    # An item that changed is exported again, alone; Export all sends everything.
    changed = decode_items(result["changedString"])
    assert [i["id"] for i in changed["items"]] == [16800] and changed["items"][0]["itemLevel"] == 68
    everything = decode_items(result["allString"])
    assert sorted(i["id"] for i in everything["items"]) == sorted(items)

    # 250 items: three strings, each a document of its own.
    assert len(result["chunks"]) == 3
    seen_ids = []
    for index, string in enumerate(result["chunks"], 1):
        part = decode_items(string, index, 3)
        assert len(part["items"]) == (100 if index < 3 else 50)
        assert len(string) < 64 * 1024, f"part {index} is {len(string)} characters"
        seen_ids += [i["id"] for i in part["items"]]
    assert sorted(seen_ids) == list(range(50001, 50251)), "every item is in exactly one part"
    assert [strip_colors(t) for t in result["chunkStatus"]] == [
        "Part 1 of 3, 100 items. Press Ctrl+C, paste it on the website's Items page, then click Next part.",
        "Part 2 of 3, 100 items. Press Ctrl+C, paste it on the website's Items page, then click Next part.",
        "Part 3 of 3, 50 items. Press Ctrl+C, paste it on the website's Items page, then click Done.",
    ], result["chunkStatus"]
    assert result["chunkButtons"] == ["Next part", "Next part", "Done"]
    assert strip_colors(result["chunkDone"]) == "Exported 250 items. They wait for an officer's approval on the website."

    # What is kept between sessions.
    st = result["state"]
    assert st["log"] == 10 + saved and st["lastTo"] == "Delta", st
    assert st["watch"] is False and st["region"] == "EU"
    assert st["bladeSeen"] == 2, "seen in a window, handed out once"
    assert st["bootsSeen"] == 6 and re.fullmatch(r"[0-9a-f]{8}", st["bootsSent"]), st
    assert st["oldAngle"] is False and st["angle"] == "number"


def check_minimap(result, variant):
    assert abs(result["minimapRadius"] - 75) < 0.001, f"half the minimap's width plus 5: {result['minimapRadius']}"
    x, y = result["minimapStart"]
    if variant == "classic":
        assert abs(x) < 0.001 and abs(y - 75) < 0.001, "where the saved data says it was left (angle 90, from version 0.1's place)"
    else:
        import math
        assert abs(x - math.cos(math.radians(200)) * 75) < 0.001 and abs(y - math.sin(math.radians(200)) * 75) < 0.001, (x, y)


def check_chat(result, variant):
    prints = [strip_colors(p) for p in result["prints"]]
    if VERBOSE:
        print(f"--- addon chat output ({variant}) ---")
        for p in prints:
            print(p)
    assert any("0 failed" in p for p in prints), "in-addon selftest reported failures"
    loaded = next(p for p in prints if p.startswith(f"Mint Community Tools: v{VERSION} loaded"))
    hint = any("The beta client does not load addon data by itself" in p for p in prints)
    if variant == "classic":
        assert "saved data restored from the linked save file (1 drops in the loot log, 1 items seen)" in loaded, loaded
        assert not hint
    elif variant == "forever":
        assert loaded == f"Mint Community Tools: v{VERSION} loaded. Type /mint or click the minimap button.", loaded
        assert hint, "on a beta client that loaded nothing, the one-time fix is mentioned"
    else:
        assert not hint, "no hint on a live client"
        assert any("handed over the saved data late; adopted it" in p for p in prints)
    scan_line = next(p for p in prints if "items equipped" in p and "Type /mint" in p)
    expected_name = "Théoden Stormwind" if variant == "forever" else "Théoden"
    assert scan_line.startswith(f"Mint Community Tools: {expected_name}: 6 items equipped"), scan_line
    assert not any("talents could not be read" in p for p in prints)
    expected_source = {"forever": "beta client", "classic": "GetCurrentRegion", "mainline": "GetCurrentRegionName"}[variant]
    assert any(p.startswith(f"Mint Community Tools: region: US ({expected_source}") for p in prints), [p for p in prints if "region" in p]
    assert any("region set to EU" in p for p in prints) and any("unknown region XX" in p for p in prints)
    assert any("minimap button hidden" in p for p in prints) and any("back at its default place" in p for p in prints)

    expected_globals = ["MintCommunityToolsDB", "SLASH_MINTCOMMUNITYTOOLS1", "SLASH_MINTCOMMUNITYTOOLS2", "SLASH_MINTCOMMUNITYTOOLS3"]
    if variant == "classic":
        expected_globals.remove("MintCommunityToolsDB")   # it was there before the addon loaded
    assert result["newglobals"] == expected_globals, f"unexpected globals: {result['newglobals']}"


def run_variant(lua, variant, workdir):
    script = workdir / f"harness_{variant}.lua"
    script.write_text(build_script(variant), encoding="utf-8")
    res = subprocess.run([lua, str(script)], capture_output=True, text=True)
    text = res.stdout.strip()
    try:
        result = json.loads(text)
    except ValueError:
        raise AssertionError(f"Lua run failed:\n{text}\n{res.stderr}")

    if VERBOSE:
        print(f"--- window ({variant}) ---")
        print(strip_colors(result["who"]))
        print(strip_colors(result["summary"]))
        print(strip_colors(result["status"]))

    check_chat(result, variant)
    check_gear(result, variant)
    check_minimap(result, variant)
    check_loot(result, variant)

    if WRITE_FIXTURES:
        FIXTURE_DIR.mkdir(exist_ok=True)
        (FIXTURE_DIR / f"character-{variant}.txt").write_text(result["export"] + "\n", encoding="utf-8")
        if variant == "forever":
            (FIXTURE_DIR / "items-forever.txt").write_text(result["itemsString"] + "\n", encoding="utf-8")
            (FIXTURE_DIR / "items-forever-part-2-of-3.txt").write_text(result["chunks"][1] + "\n", encoding="utf-8")
    return len(result["export"])


def main():
    lua = find_lua()
    print(f"version {VERSION}")
    print(f"using {os.path.basename(lua)}")
    check_toc()
    failed = False
    with tempfile.TemporaryDirectory() as tmp:
        for variant in VARIANTS:
            try:
                length = run_variant(lua, variant, Path(tmp))
                print(f"PASS  {variant:9s} (export string {length} chars)")
            except AssertionError as e:
                failed = True
                print(f"FAIL  {variant:9s} {e}")
    sys.exit(1 if failed else 0)


if __name__ == "__main__":
    main()
