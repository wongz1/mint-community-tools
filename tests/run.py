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
FILES = ["Encode.lua", "Collect.lua", "Loot.lua", "UI.lua", "LootUI.lua", "Minimap.lua",
         "Overhaul.lua", "ActionBars.lua", "Chat.lua", "UnitFrames.lua", "Map.lua", "Quests.lua", "Menus.lua", "SettingsUI.lua", "Dump.lua", "Core.lua"]
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

-- Secret values, as the newest engine hands some unit numbers to addons: opaque. One can be
-- stored, passed to a widget, formatted and concatenated. Indexing one raises an error, and
-- so do arithmetic and ordered comparisons (Lua refuses those on a table by itself), which
-- is what the game does to addon code. reveal() is for the harness's own checks.
local SECRETS = setmetatable({}, { __mode = "k" })
local secretMeta
local function secret(v) local p = setmetatable({}, secretMeta); SECRETS[p] = { v }; return p end
local function isSecret(v) return type(v) == "table" and SECRETS[v] ~= nil end
local function reveal(v) if isSecret(v) then return SECRETS[v][1] end return v end
secretMeta = {
  __index = function() error("attempt to index a secret value", 2) end,
  __newindex = function() error("attempt to index a secret value", 2) end,
  __concat = function(a, b) return secret(tostring(reveal(a)) .. tostring(reveal(b))) end,
}

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
      if k == "GetText" then return reveal(rawget(self, "_text")) or "" end
      if k == "SetCooldown" then rawset(self, "_cd", { ... }); return end
      if k == "SetCooldownFromExpirationTime" then rawset(self, "_cdExpiration", { ... }); return end
      if k == "SetScript" then local kind, fn = ...; rawget(self, "_scripts")[kind] = fn; return end
      if k == "RegisterEvent" then rawget(self, "_events")[(...)] = true; return end
      if k == "UnregisterEvent" then rawget(self, "_events")[(...)] = nil; return end
      if k == "SetPoint" then
        local pt = { ... }
        rawset(self, "_point", pt)
        local by = rawget(self, "_pointsBy") or {}
        by[pt[1]] = pt
        rawset(self, "_pointsBy", by)
        return
      end
      if k == "SetTexture" then rawset(self, "_texture", (...)); return end
      if k == "SetTextColor" then rawset(self, "_textColor", { ... }); return end
      if k == "SetUnit" then rawset(self, "_unit", (...)); return end
      if k == "SetFont" then rawset(self, "_font", { ... }); return end
      if k == "SetColorTexture" then rawset(self, "_colorTexture", { ... }); return end
      if k == "HookScript" then
        local kind, fn = ...
        local hooks = rawget(self, "_hooks") or {}
        hooks[kind] = fn
        rawset(self, "_hooks", hooks)
        return
      end
      if k == "SetHideCountdownNumbers" then rawset(self, "_hideNumbers", (...)); return end
      if k == "SetValue" then rawset(self, "_value", (...)); return end
      if k == "SetMinMaxValues" then rawset(self, "_minmax", { ... }); return end
      if k == "SetStatusBarColor" then rawset(self, "_color", { ... }); return end
      if k == "SetBackdropBorderColor" then rawset(self, "_borderColor", { ... }); return end
      if k == "SetParent" then rawset(self, "_parent", (...)); return end
      if k == "SetAlpha" then rawset(self, "_alpha", (...)); return end
      if k == "SetMaskTexture" then rawset(self, "_mask", (...)); return end
      if k == "SetSize" then rawset(self, "_size", { ... }); return end
      if k == "SetChecked" then rawset(self, "_checked", (...) and true or false); return end
      if k == "GetChecked" then return rawget(self, "_checked") end
      if k == "GetName" then return rawget(self, "_name") end
      if k == "RemoveMaskTexture" then rawset(self, "_maskRemoved", (...)); return end
      if k == "SetDrawLayer" then rawset(self, "_layer", (...)); return end
      if k == "GetPoint" then local p = rawget(self, "_point"); if p then return unpack(p) end; return nil end
      if k == "GetParent" then return rawget(self, "_parent") end
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

-- The game's own UI, as named frames the overhaul looks up.
local function named(name) local f = stub(name); env[name] = f; return f end
for _, n in ipairs({
  "PlayerFrame", "TargetFrame", "TargetFrameToT", "PetFrame", "ComboFrame", "TargetFrameSpellBar",
  "MainMenuBar", "MainMenuBarArtFrame", "MainMenuExpBar", "ReputationWatchBar", "MultiBarBottomLeft", "MultiBarRight",
  "MainMenuBarTexture0", "MainMenuBarLeftEndCap", "MainMenuBarRightEndCap", "ActionBarUpButton",
  "MainMenuBarBackpackButton", "CharacterBag0Slot", "CharacterBag1Slot", "KeyRingButton", "KeyRingButtonIconTexture", "CharacterReagentBag0Slot", "CharacterReagentBag0SlotIconTexture", "CharacterMicroButton", "SpellbookMicroButton", "MainMenuMicroButton",
  "ChatFrame1", "ChatFrame1Tab", "ChatFrame1EditBox", "ChatFrame1ButtonFrame", "ChatFrame1Background", "ChatFrame1TabLeft",
  "ChatFrame1EditBoxLeft", "ChatFrame2", "ChatFrame2Tab", "ChatFrameMenuButton", "ChatFrameChannelButton",
  "MinimapCluster", "MinimapBorder", "MinimapZoomIn", "MinimapZoomOut", "MiniMapWorldMapButton", "MinimapZoneTextButton",
  "GameTimeFrame", "TimeManagerClockButton", "MiniMapTracking", "MiniMapMailFrame",
  "ObjectiveTrackerFrame", "QuestWatchFrame",
}) do named(n) end
for i = 1, 12 do named("ActionButton" .. i); named("ActionButton" .. i .. "Icon"); named("ActionButton" .. i .. "HotKey"); named("MultiBarBottomLeftButton" .. i) end
for i = 1, 10 do named("PetActionButton" .. i) end
-- A newer client rounds each action button's icon with a mask kept in a field.
rawset(env.ActionButton1, "IconMask", stub("IconMask"))
-- The reagent bag slot is inventory slot 35, and there is nothing in it.
rawset(env.CharacterReagentBag0Slot, "GetID", function() return 35 end)

-- The game menu and the options window, as the game builds them: art kept in parts (a
-- border frame, a header frame, a NineSlice, a single Bg texture), push buttons whose art is
-- three pieces in fields, and things that are not push buttons (a check box, a close button).
local MENU, SP = {}, {}
do
  local function typed(obj, kind) rawset(obj, "IsObjectType", function(self, k) return k == kind end); return obj end
  local function holding(obj, regions, children)
    regions, children = regions or {}, children or {}
    rawset(obj, "GetRegions", function() return unpack(regions) end)
    rawset(obj, "GetChildren", function() return unpack(children) end)
    return obj
  end
  local function art() return typed(stub(), "Texture") end
  local function words() return typed(stub(), "FontString") end
  local function pushButton(third)
    local b = typed(stub(), "Button")
    local l, m, r = art(), art(), art()
    rawset(b, "Left", l); rawset(b, third, m); rawset(b, "Right", r)
    return holding(b, { l, m, r, words() }), l
  end
  MENU.typed, MENU.holding, MENU.art, MENU.pushButton = typed, holding, art, pushButton

  MENU.frame = typed(named("GameMenuFrame"), "Frame")
  MENU.borderArt, MENU.headerArt, MENU.headerText, MENU.ownArt = art(), art(), words(), art()
  rawset(MENU.frame, "Border", holding(typed(stub(), "Frame"), { MENU.borderArt }))
  rawset(MENU.frame, "Header", holding(typed(stub(), "Frame"), { MENU.headerArt, MENU.headerText }))
  MENU.options, MENU.optionsArt = pushButton("Center")
  MENU.plainArt = art()
  MENU.plain = holding(typed(stub(), "Button"), { MENU.plainArt })   -- art not in three pieces: still a button of the menu
  MENU.children = { MENU.options, MENU.plain }
  holding(MENU.frame, { MENU.ownArt, words() }, MENU.children)

  SP.frame = typed(named("SettingsPanel"), "Frame")
  SP.nineArt, SP.bg = art(), art()
  rawset(SP.frame, "NineSlice", holding(typed(stub(), "Frame"), { SP.nineArt }))
  rawset(SP.frame, "Bg", SP.bg)
  SP.close, SP.closeArt = pushButton("Middle")
  SP.xArt = art()
  SP.x = holding(typed(stub(), "Button"), { SP.xArt })
  rawset(SP.frame, "ClosePanelButton", SP.x)
  SP.defaults = pushButton("Center")
  rawset(SP.close, "GetText", function() return "Close" end)   -- a close button that says so
  rawset(SP.frame, "CloseButton", SP.close)
  -- a check box answers to Button and CheckButton, and keeps its art behind getters
  local function checkButton()
    local cb = stub()
    rawset(cb, "IsObjectType", function(self, k) return k == "CheckButton" or k == "Button" end)
    local box, tick, greyTick = art(), art(), art()
    rawset(cb, "GetNormalTexture", function() return box end)
    rawset(cb, "GetPushedTexture", function() return nil end)
    rawset(cb, "GetHighlightTexture", function() return nil end)
    rawset(cb, "GetCheckedTexture", function() return tick end)
    rawset(cb, "GetDisabledCheckedTexture", function() return greyTick end)
    rawset(cb, "GetWidth", function() return 30 end)
    return holding(cb, { box, tick, greyTick }), box, tick
  end
  SP.check, SP.checkArt, SP.tick = checkButton()
  SP.iconCheck, SP.iconCheckArt = checkButton()   -- a macro's picture: a check button, not a check box
  rawset(SP.iconCheck, "Icon", art())
  SP.dropdown = typed(stub(), "Button")
  SP.dropArrow, SP.dropBg = art(), art()
  rawset(SP.dropdown, "Arrow", SP.dropArrow); rawset(SP.dropdown, "Background", SP.dropBg); rawset(SP.dropdown, "Text", words())
  holding(SP.dropdown, { SP.dropArrow, SP.dropBg })
  SP.slider = typed(stub(), "Slider")
  SP.sliderBar, SP.sliderThumb = art(), art()
  rawset(SP.slider, "Left", SP.sliderBar); rawset(SP.slider, "Right", art()); rawset(SP.slider, "Middle", art()); rawset(SP.slider, "Thumb", SP.sliderThumb)
  holding(SP.slider, {})
  SP.search = typed(stub(), "EditBox")
  SP.searchArt = art()
  rawset(SP.search, "Left", SP.searchArt); rawset(SP.search, "Right", art()); rawset(SP.search, "Middle", art())
  holding(SP.search, {})
  SP.scrollBar, SP.track, SP.thumb = typed(stub(), "Frame"), typed(stub(), "Frame"), typed(stub(), "Button")
  SP.trackArt, SP.thumbArt = art(), art()
  rawset(SP.track, "Middle", SP.trackArt); rawset(SP.track, "Thumb", SP.thumb); rawset(SP.thumb, "Middle", SP.thumbArt)
  rawset(SP.scrollBar, "Track", SP.track); rawset(SP.scrollBar, "Back", stub())
  holding(SP.scrollBar, {}, { SP.track }); holding(SP.track, {}, { SP.thumb }); holding(SP.thumb, {})
  -- two tabs: the open one shows its LeftActive art
  SP.OPEN = "A"
  local function tab(which)
    local b = pushButton("Middle")
    local active = art()
    rawset(active, "IsShown", function() return SP.OPEN == which end)
    rawset(b, "LeftActive", active)
    return b
  end
  SP.tabA, SP.tabB = tab("A"), tab("B")
  SP.tabs = holding(typed(stub(), "Frame"), {}, { SP.tabA, SP.tabB })
  rawset(SP.tabA, "GetParent", function() return SP.tabs end); rawset(SP.tabB, "GetParent", function() return SP.tabs end)
  -- a framed area: a frame whose border is nine pieces drawn on it
  SP.inset, SP.insetCorner = typed(stub(), "Frame"), art()
  rawset(SP.inset, "TopLeftCorner", SP.insetCorner)
  holding(SP.inset, { SP.insetCorner })
  -- a scrolling list of categories: a heading with a banner, an entry with a bar
  SP.heading, SP.banner = typed(stub(), "Frame"), art()
  rawset(SP.heading, "Background", SP.banner); rawset(SP.heading, "Label", words()); holding(SP.heading, { SP.banner })
  SP.entry, SP.bar = typed(stub(), "Button"), art()
  rawset(SP.entry, "Texture", SP.bar); rawset(SP.entry, "Label", words()); holding(SP.entry, { SP.bar })
  SP.scrollTarget = holding(typed(stub(), "Frame"), {}, { SP.heading, SP.entry })
  SP.scrollBox = holding(typed(stub(), "Frame"), {}, { SP.scrollTarget })
  rawset(SP.scrollBox, "ScrollTarget", SP.scrollTarget)
  local list = holding(typed(stub(), "Frame"), {}, { SP.defaults, SP.check, SP.iconCheck, SP.dropdown, SP.slider, SP.search, SP.scrollBar, SP.tabs, SP.inset, SP.scrollBox })
  holding(SP.frame, {}, { SP.close, SP.x, holding(typed(stub(), "Frame"), {}, { list }) })

  -- a confirmation box: border and background in BG, an alert icon of its own, plain buttons
  local POP = {}
  MENU.popup = POP
  POP.frame = typed(named("StaticPopup1"), "Frame")
  POP.bgArt, POP.alert, POP.buttonArt = art(), art(), art()
  rawset(POP.frame, "BG", holding(typed(stub(), "Frame"), { POP.bgArt }))
  POP.button = holding(typed(stub(), "Button"), { POP.buttonArt })
  rawset(POP.frame, "ButtonContainer", holding(typed(stub(), "Frame"), {}, { POP.button }))
  holding(POP.frame, { POP.alert }, {})
end

local TARGET_EXISTS = false
local HEALTH = 1234
local AT_LEVEL_CAP = false
env.UnitXP = function() return 12345 end
env.UnitXPMax = function() return 20000 end
env.GetXPExhaustion = function() return 9000 end
env.IsPlayerAtEffectiveMaxLevel = function() return AT_LEVEL_CAP end
env.GetWatchedFactionInfo = function() return "Argent Dawn", 5, 3000, 9000, 4500 end
local ZOOM = 0
env.RAID_CLASS_COLORS = { WARRIOR = { r = 0.78, g = 0.61, b = 0.43 } }
env.PowerBarColor = { MANA = { r = 0, g = 0, b = 1 }, RAGE = { r = 1, g = 0, b = 0 } }
env.FACTION_BAR_COLORS = { [2] = { r = 1, g = 0, b = 0 }, [4] = { r = 1, g = 1, b = 0 }, [5] = { r = 0, g = 1, b = 0 } }
env.DebuffTypeColor = { Magic = { r = 0.2, g = 0.6, b = 1 } }
env.NUM_CHAT_WINDOWS = 2
env.InCombatLockdown = function() return false end
env.SetPortraitTexture = function(tex, unit) rawset(tex, "_portrait", unit) end
env.GetGameTime = function() return 20, 30 end
env.GetMinimapZoneText = function() return "Elwynn Forest" end
env.GetZonePVPInfo = function() return "friendly" end
env.C_Map = { GetBestMapForUnit = function() return 1429 end, GetPlayerMapPosition = function() return { x = 0.523, y = 0.481 } end }
env.Minimap_ZoomIn = function() ZOOM = ZOOM + 1 end
env.Minimap_ZoomOut = function() ZOOM = ZOOM - 1 end
env.hooksecurefunc = function() end
env.UnitHealth = function(u) return u == "target" and 50 or HEALTH end
env.UnitHealthMax = function(u) return u == "target" and 100 or 2000 end
env.UnitPower = function() return 600 end
env.UnitPowerMax = function() return 1000 end
env.UnitPowerType = function(u) if u == "player" then return 0, "MANA" end return 1, "RAGE" end
env.UnitIsPlayer = function(u) return u == "player" end
env.UnitReaction = function() return 2 end
env.UnitClassification = function(u) return u == "target" and "elite" or "normal" end
env.UnitIsConnected = function() return true end
env.UnitIsDead = function() return false end
env.UnitIsGhost = function() return false end
env.UnitIsTapDenied = function() return false end
env.GetQuestDifficultyColor = function() return { r = 1, g = 0.82, b = 0 } end
env.UnitAura = function(unit, i, filter)
  local harmful = filter:find("HARMFUL", 1, true)
  if unit == "player" then
    if harmful then if i == 1 then return "Weakened Soul", 135936, 1, "Magic", 15, CLOCK + 10 end
    elseif i <= 2 then return "Power Word: Fortitude", 135987, 0, nil, 0, 0 end
  elseif unit == "target" then
    if harmful then
      if filter:find("PLAYER", 1, true) then if i == 1 then return "Rend", 132155, 3, nil, 9, CLOCK + 5 end
      elseif i <= 3 then return "Debuff " .. i, 1, 1, nil, 0, 0 end
    elseif i == 1 then return "Enrage", 2, 1 end
  end
  return nil
end

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
    ui = { enabled = true, units = { player = { buffs = "below" } } },   -- the minimalist UI, partly configured
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
env.type = function(v) return type(reveal(v)) end
env.tostring = function(v) if isSecret(v) then return secret(tostring(reveal(v))) end return tostring(v) end
env.string = setmetatable({ format = function(fmt, ...)
  local n, args, any = select("#", ...), { ... }, false
  for i = 1, n do if isSecret(args[i]) then any = true; args[i] = reveal(args[i]) end end
  local text = string.format(fmt, unpack(args, 1, n))
  return any and secret(text) or text
end }, { __index = string })
if VARIANT ~= "classic" then env.issecretvalue = isSecret end   -- Classic Era has no such thing
if VARIANT == "mainline" then
  -- A newer client lists its own micro buttons, and keeps the bar's end caps in a field.
  env.MICRO_BUTTONS = { "CharacterMicroButton", "MainMenuMicroButton", "NoSuchMicroButton" }
  rawset(env.MainMenuBar, "EndCaps", stub("EndCaps"))
  -- ...hangs the minimap's extras off its cluster, has no DebuffTypeColor table, and answers
  -- the level cap and the watched reputation through different calls.
  for _, part in ipairs({ "DielFrame", "Tracking", "IndicatorFrame" }) do rawset(env.MinimapCluster, part, stub(part)) end
  env.DebuffTypeColor = nil
  env.IsPlayerAtEffectiveMaxLevel = nil
  env.GetMaxPlayerLevel = function() return AT_LEVEL_CAP and 60 or 70 end
  env.GetWatchedFactionInfo = nil
  env.C_Reputation = { GetWatchedFactionData = function()
    return { name = "Argent Dawn", reaction = 5, currentReactionThreshold = 3000, nextReactionThreshold = 9000, currentStanding = 4500 }
  end }
  env.GetZonePVPInfo = nil
  env.C_PvP = { GetZonePVPInfo = function() return "friendly" end }
  -- The newest engine: current health and power, and an aura's stacks and timing, are secret.
  env.UnitHealth = function(u) return secret(u == "target" and 50 or HEALTH) end
  env.UnitPower = function() return secret(600) end
  env.CurveConstants = { ScaleTo100 = {} }
  env.UnitHealthPercent = function(u, predicted, curve)
    assert(curve == env.CurveConstants.ScaleTo100, "the percentage is asked for on the 0 to 100 scale")
    return secret(62)
  end
  local unitAura, counts = env.UnitAura, {}
  env.UnitAura = nil
  env.C_UnitAuras = {
    GetAuraDataByIndex = function(unit, i, filter)
      local name, icon, count, dispel, duration, expires = unitAura(unit, i, filter)
      if not name then return nil end
      local id = (unit == "player" and 100 or 200) + i + (filter:find("HARMFUL", 1, true) and 50 or 0)
      counts[id] = count or 0
      return { name = name, icon = icon, applications = secret(count or 0), dispelName = dispel,
               duration = secret(duration or 0), expirationTime = secret(expires or 0), auraInstanceID = id }
    end,
    GetAuraApplicationDisplayCount = function(unit, id, least, most)
      local c = counts[id] or 0
      return secret(c >= least and tostring(c) or "")
    end,
  }
end

-- The quest log: three quests, all tracked. The first has one objective done and one not,
-- the second is complete, the third has no objectives to count. Classic Era answers through
-- GetQuestLogTitle and its kin, a newer client through C_QuestLog; WoW Forever's own variant
-- here has neither, as a client the addon cannot read would.
local QUESTS = {
  [101] = { title = "Kobold Camp Cleanup", level = 2, objectives = { { "Kobold Vermin slain: 3/8", false }, { "Kobold Worker slain: 8/8", true } } },
  [102] = { title = "Brotherhood of Thieves", level = 4, complete = true, objectives = { { "Red Burlap Bandana: 12/12", true } } },
  [103] = { title = "Milly's Harvest", level = 5, objectives = {} },
  [104] = { title = "A Fishy Peril", level = 10, objectives = { { "Speak with Gryan Stoutmantle", false } } },
}
local WATCHED = { 101, 102, 103 }
local QUEST_OPENED, QUEST_SELECTED = {}, {}
local function unwatch(id)
  for i, w in ipairs(WATCHED) do if w == id then table.remove(WATCHED, i) return end end
end
if VARIANT == "classic" then
  -- The quest log's rows: a zone header first, then the quests, so a quest's row is its id - 99.
  env.GetNumQuestWatches = function() return #WATCHED end
  env.GetQuestIndexForWatch = function(i) return WATCHED[i] and WATCHED[i] - 99 end
  env.GetQuestLogTitle = function(index)
    if index == 1 then return "Elwynn Forest", 0, nil, true, false, nil, 0, 0 end
    local q = QUESTS[index + 99]
    if not q then return nil end
    return q.title, q.level, nil, false, false, q.complete and 1 or nil, 0, index + 99
  end
  env.GetNumQuestLeaderBoards = function(index) return #QUESTS[index + 99].objectives end
  env.GetQuestLogLeaderBoard = function(j, index)
    local o = QUESTS[index + 99].objectives[j]
    return o[1], "monster", o[2]
  end
  env.QuestLog_SetSelection = function(index) table.insert(QUEST_SELECTED, index) end
  env.RemoveQuestWatch = function(index) unwatch(index + 99) end
elseif VARIANT == "mainline" then
  env.C_QuestLog = {
    GetNumQuestWatches = function() return #WATCHED end,
    GetQuestIDForQuestWatchIndex = function(i) return WATCHED[i] end,
    GetTitleForQuestID = function(id) return QUESTS[id] and QUESTS[id].title end,
    GetLogIndexForQuestID = function(id) return id - 99 end,
    GetInfo = function(index) local q = QUESTS[index + 99]; return q and { title = q.title, level = q.level, questID = index + 99, isHeader = false } end,
    IsComplete = function(id) return QUESTS[id].complete or false end,
    IsFailed = function() return false end,
    GetQuestObjectives = function(id)
      local t = {}
      for i, o in ipairs(QUESTS[id].objectives) do t[i] = { text = o[1], type = "monster", finished = o[2] } end
      return t
    end,
    RemoveQuestWatch = function(id) unwatch(id) end,
  }
  env.QuestMapFrame_OpenToQuestDetails = function(id) table.insert(QUEST_OPENED, id) end
end
local SHIFT = false
env.IsShiftKeyDown = function() return SHIFT end

-- The target, when there is one, is Hogger; the target's target is the player.
local playerName = env.UnitName
env.UnitName = function(unit)
  if unit == "target" then return "Hogger", nil end
  if unit == "targettarget" then return playerName("player") end
  return playerName(unit)
end
env.UnitExists = function(unit)
  if unit == "target" or unit == "targettarget" then return TARGET_EXISTS end
  return true
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
  v = reveal(v)
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
-- On the round map the button sits 75 from the centre; on the overhaul's square map, 82 out along the square.
local function expectAngle(deg, what)
  local x, y = minimapAt()
  local cx, cy = math.cos(math.rad(deg)), math.sin(math.rad(deg))
  local ex, ey
  if ns.Map.Active() then
    local m = math.max(math.abs(cx), math.abs(cy))
    ex, ey = cx / m * 82, cy / m * 82
    -- ...and clear of the strips above and below the map (17 each).
    if ey >= 82 - 0.001 then ey = ey + 17 elseif ey <= -82 + 0.001 then ey = ey - 17 end
  else
    ex, ey = cx * 75, cy * 75
  end
  assert(math.abs(x - ex) < 0.001 and math.abs(y - ey) < 0.001, what .. ": " .. x .. ", " .. y)
end
expectAngle(90, "dragged to the top of the minimap")
assert(math.abs(env.MintCommunityToolsDB.minimap.angle - 90) < 0.001, "the new place is saved")
slash("minimap hide")
assert(not mm._shown and env.MintCommunityToolsDB.minimap.shown == false, "/mint minimap hide")
slash("minimap")
assert(mm._shown, "/mint minimap shows it again")
slash("minimap reset")
expectAngle(200, "reset to the default place")
local minimapSquare = ns.Map.Active()

-- Round or square: the shape of the minimap the button sits around. Auto, the default, follows
-- the map: this addon's own square map, or what another addon says through GetMinimapShape().
do
  local mdb = env.MintCommunityToolsDB.minimap
  local function at(x, y, what)
    local px, py = minimapAt()
    assert(math.abs(px - x) < 0.001 and math.abs(py - y) < 0.001, what .. ": " .. px .. ", " .. py)
  end
  local function dragTo(x, y)   -- the minimap's centre is at 900, 700
    local old = env.GetCursorPosition
    env.GetCursorPosition = function() return x, y end
    mm._scripts.OnDragStart(mm); mm._scripts.OnUpdate(mm); mm._scripts.OnDragStop(mm)
    env.GetCursorPosition = old
  end
  local watcher = frameNamed("MintCommunityToolsMinimapWatcher")
  local function tick(dt) watcher._scripts.OnUpdate(watcher, dt) end
  -- This addon's own strips above and below its map, when the map is on.
  local top, bottom = 0, 0
  if ns.Map.applied then top, bottom = ns.Map.Insets() end

  assert(mdb.shape == "auto", "the shape defaults to auto, also for settings saved before it existed")
  assert(ns.MinimapShape() == (minimapSquare and "square" or "round"), "auto follows this addon's own map")
  assert(ns.SetMinimapShape("sideways") == false and mdb.shape == "auto", "an unknown shape is refused")

  dragTo(900, 800)
  slash("minimap square")
  assert(mdb.shape == "square" and ns.MinimapShape() == "square", "/mint minimap square")
  at(0, 82 + top, "square: straight up, half the width plus 12, clear of the strip above")
  dragTo(1000, 800)
  at(82, 82 + top, "square: dragged to the corner")
  dragTo(800, 690)
  at(-82, -8.2, "square: on the left edge the button slides along it")
  dragTo(900, 600)
  at(0, -(82 + bottom), "square: straight down, clear of the strip below")
  slash("minimap round")
  assert(mdb.shape == "round" and ns.MinimapShape() == "round", "/mint minimap round, even on a square map")
  at(0, -75, "round: back on the circle")
  slash("minimap auto")
  assert(mdb.shape == "auto" and out.prints[#out.prints]:find((minimapSquare and "square" or "round") .. " right now", 1, true),
    "/mint minimap auto says what it found: " .. out.prints[#out.prints])

  if minimapSquare then
    -- The square map tells other addons' buttons what it is and how much room its strips take.
    assert(env.GetMinimapShape() == "SQUARE", "the square map answers GetMinimapShape")
    local a, b, l, r = env.GetMinimapEdgeInsets()
    assert(a == top and b == bottom and l == 0 and r == 0 and a > 0, "and GetMinimapEdgeInsets: the strips above and below")
    at(0, -(82 + bottom), "auto on the square map: on the square")
  else
    -- Another addon squares the map: auto follows within a second, and clears its insets.
    local oldShape, oldInsets = env.GetMinimapShape, env.GetMinimapEdgeInsets
    dragTo(900, 800)
    env.GetMinimapShape = function() return "SQUARE" end
    env.GetMinimapEdgeInsets = function() return 17, 33 end
    tick(0.4)
    at(0, 75, "not before a second has passed")
    tick(0.7)
    assert(ns.MinimapShape() == "square", "auto: square when another addon says so")
    at(0, 82 + 17, "auto: clear of what the other addon has above the map")
    dragTo(900, 600)
    at(0, -(82 + 33), "auto: and below it")
    env.GetMinimapShape = function() return "ROUND" end
    tick(1.1)
    at(0, -75, "auto: round again when the map is")
    env.GetMinimapShape = function() error("broken") end
    tick(1.1)
    assert(ns.MinimapShape() == "round", "a GetMinimapShape that errors means round")
    slash("minimap square")
    env.GetMinimapEdgeInsets = function() return "x", -5 end
    tick(1.1)
    at(0, -82, "insets that are not positive numbers are ignored")
    env.GetMinimapShape, env.GetMinimapEdgeInsets = oldShape, oldInsets
    slash("minimap auto")
  end
  slash("minimap reset")
  expectAngle(200, "back at the default place, on the map's own shape")
end

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
  env.MintCommunityToolsDB = { minimap = { angle = 45 }, loot = { log = { SAVED_ENTRY }, watch = false }, items = { [11726] = SAVED_ITEM }, ui = { enabled = true } }
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
if VARIANT == "mainline" then fire("CHAT_MSG_LOOT", secret(receives("Bravo", L(16800)))) end   -- chat text the addon may not read
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

---------------------------------------------------------------------------
-- The minimalist UI
---------------------------------------------------------------------------
local hider = frameNamed("MintCommunityToolsHider")
local function mover(key) return frameNamed("MintCommunityToolsMover_" .. key) end
local function shownAuras(f, kind)
  local n = 0
  for _, b in ipairs(f.auras[kind].buttons) do if b._shown then n = n + 1 end end
  local point = rawget(f.auras[kind].frame, "_point")
  return { n, f.auras[kind].frame._shown and true or false, point and point[1] or false }
end
local S = env.MintCommunityToolsDB.ui
local ov = { enabled = S.enabled and true or false, failed = false }
for _, p in ipairs(out.prints) do if p:find("could not be set up", 1, true) then ov.failed = p end end
assert(not ov.failed, "a piece of the overhaul failed: " .. tostring(ov.failed))
if S.enabled then
  -- The game's own frames: hidden, moved or stripped.
  ov.playerHidden = env.PlayerFrame._parent == hider and env.PlayerFrame._shown == false
  ov.targetHidden = env.TargetFrame._parent == hider
  local petf = frameNamed("MintCommunityToolsPetFrame")
  ov.petKept = env.PetFrame._parent == hider and petf._pointsBy.TOPLEFT[2] == mover("pet")
  ov.pet = { petf._shown, petf.healthText:GetText(), petf.auras }
  ov.chatTab = env.ChatFrame1Tab._alpha
  ov.bar1 = env.ActionButton1._point[2] == mover("bar1") and env.ActionButton12._point[4]
  ov.bar1Size = env.ActionButton1._size and env.ActionButton1._size[1]
  -- The icon keeps its picture: its corner mask is taken off it (not blanked), and it sits above the backdrop.
  local mask = rawget(env.ActionButton1, "IconMask")
  ov.icon = { env.ActionButton1Icon._maskRemoved == mask, rawget(mask, "_alpha") == nil, env.ActionButton1Icon._layer }
  -- The keyring and the empty reagent slot get a picture of the addon's own over the game's
  -- (which the game keeps setting back to an outline): a key, and a dimmed herb.
  local keyIcon, reagentIcon = ns.Bars.extraIcons[env.KeyRingButton], ns.Bars.extraIcons[env.CharacterReagentBag0Slot]
  ov.keyring = { env.KeyRingButton._point[2] == mover("bags"), keyIcon._texture, env.KeyRingButton._shown,
                 env.KeyRingButtonIconTexture._alpha, rawget(env.KeyRingButtonIconTexture, "_texture") == nil }
  ov.reagentEmpty = { reagentIcon._texture, reagentIcon._shown, reagentIcon._alpha, env.CharacterReagentBag0SlotIconTexture._alpha }
  -- A bag goes into the reagent slot: within a second the game's own picture of it shows instead.
  local oldTexture = env.GetInventoryItemTexture
  env.GetInventoryItemTexture = function(unit, slot) if slot == 35 then return 133633 end return oldTexture(unit, slot) end
  ns.Bars.Check()
  ov.reagentFilled = { reagentIcon._shown, env.CharacterReagentBag0SlotIconTexture._alpha }
  env.GetInventoryItemTexture = oldTexture
  ns.Bars.Check()
  ov.reagentEmptyAgain = reagentIcon._shown
  -- Clicks on these two are the game's to handle; the addon only counts them, for the dump.
  assert(next(ns.Bars.clicks) == nil, "no clicks yet")
  env.KeyRingButton._hooks.OnClick(env.KeyRingButton, "LeftButton")
  env.KeyRingButton._hooks.OnClick(env.KeyRingButton, "LeftButton")
  env.CharacterReagentBag0Slot._hooks.OnClick(env.CharacterReagentBag0Slot, "RightButton")
  assert(ns.Bars.clicks.KeyRingButton.count == 2 and ns.Bars.clicks.KeyRingButton.button == "LeftButton", "clicks on the keyring are counted")
  assert(ns.Bars.clicks.CharacterReagentBag0Slot.count == 1 and ns.Bars.clicks.CharacterReagentBag0Slot.id == 35, "and on the reagent slot, with its slot")
  ov.bar1Mover = mover("bar1")._size
  ov.bar2 = env.MultiBarBottomLeftButton1._point[2] == mover("bar2")
  ov.petbar = env.PetActionButton1._point[2] == mover("petbar") and env.PetActionButton1._size[1]
  ov.gryphon = env.MainMenuBarLeftEndCap._alpha
  ov.bags = env.CharacterBag0Slot._point[2] == mover("bags")
  local microBar = frameNamed("MintCommunityToolsMicroBar")
  ov.micro = env.CharacterMicroButton._parent == microBar and microBar._pointsBy.TOPLEFT[2] == mover("micro")
  ov.microCount = ns.Bars.microCount
  ov.endCaps = type(rawget(env.MainMenuBar, "EndCaps")) == "table" and rawget(env.MainMenuBar, "EndCaps")._alpha or false
  -- The experience bar is the addon's own; the game's is hidden.
  local xp = ns.Bars.xp
  ov.xp = { xp.frame._shown, xp.bar._minmax[2], xp.bar._value, xp.rested._shown, xp.rested._value, xp.kind }
  ov.xpBlizzard = env.MainMenuExpBar._parent == hider and env.ReputationWatchBar._parent == hider
  ov.xpMover = xp.frame._pointsBy.TOPLEFT[2] == mover("xp") and mover("xp")._size
  AT_LEVEL_CAP = true
  fire("UPDATE_FACTION")
  ov.rep = { xp.kind, xp.label, xp.bar._minmax[2], xp.bar._value, xp.rested._shown }
  AT_LEVEL_CAP = false
  fire("PLAYER_XP_UPDATE")
  ov.mapSwept = ns.Map.swept
  local dial, tracking = rawget(env.MinimapCluster, "DielFrame"), rawget(env.MinimapCluster, "Tracking")
  ov.cluster = type(dial) == "table" and { dial._parent == hider, tracking._parent == env.Minimap, tracking._point[2] == env.Minimap } or false
  ov.relayout = ns.Bars.Relayout()
  -- The game lays its bag bar out again and chains the bags back to the backpack; the addon's
  -- once-a-second look puts them on their mover again, and finds nothing to do after that.
  ov.bagsFirst = ns.Bars.Check()
  env.MainMenuBarBackpackButton:ClearAllPoints()
  env.MainMenuBarBackpackButton:SetPoint("RIGHT", env.BagsBar or env.UIParent, "RIGHT", 0, 0)
  env.CharacterBag0Slot:SetPoint("RIGHT", env.MainMenuBarBackpackButton, "LEFT", -2, 0)
  env.ActionButton3:SetPoint("LEFT", env.ActionButton2, "RIGHT", 6, 0)
  ov.bagsStrayed = env.CharacterBag0Slot._point[2] ~= mover("bags")
  ov.bagsFixed = ns.Bars.Check()
  ov.bagsBack = env.CharacterBag0Slot._point[2] == mover("bags") and env.MainMenuBarBackpackButton._point[2] == mover("bags")
    and env.ActionButton3._point[2] == mover("bar1") and env.ActionButton3._point[4] == 68
  ov.bagsAgain = ns.Bars.Check()
  ov.watch = type(ns.Bars.watch._scripts.OnUpdate)
  ov.chat = env.ChatFrame1._point[2] == mover("chat")
  ov.chatArt = env.ChatFrame1Background._alpha
  ov.chatButtons = env.ChatFrameMenuButton._parent == hider and env.ChatFrame1ButtonFrame._parent == hider
  ov.chatEdit = env.ChatFrame1EditBox._point[2] == env.ChatFrame1
  ov.minimap = rawget(env.Minimap, "_point") ~= nil and env.Minimap._point[2] == mover("minimap")
  ov.mask = env.Minimap._mask
  ov.zoomHidden = env.MinimapZoomIn._parent == hider and env.GameTimeFrame._parent == hider
  -- Above the map: the zone's name with the coordinates at the strip's right end, the name
  -- given what room that leaves. Below it: the two times on one row.
  do
    local mw = ns.Map.widgets
    local function under(key) local p = rawget(mw[key], "_point"); return { mw[key]._shown, p and p[1] or false, p and p[5] or false } end
    local function same(a, b) return a[1] == b[1] and a[2] == b[2] and a[3] == b[3] end
    local function size() local s = mover("minimap")._size; return s[1] .. "x" .. s[2] end
    local function change(key, on) S.map[key] = on; ns.Map.OnSettingsChanged("map." .. key) end
    local function strip(text) return (text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")) end
    assert(ns.Map.CoordsOnTop() and mw.coordsTop._shown and mw.coordsTop:GetText() == "52.3, 48.1", "the coordinates are in the zone strip: " .. tostring(mw.coordsTop:GetText()))
    assert(mw.coordsTop._pointsBy.RIGHT[2] == mw.zoneStrip and mw.coordsTop._pointsBy.RIGHT[4] == -4, "at its right end")
    assert(mw.zone._pointsBy.LEFT[2] == mw.zoneStrip and mw.zone._pointsBy.RIGHT[2] == mw.coordsTop and mw.zone._pointsBy.RIGHT[4] == -6,
      "the zone's name runs from the strip's left to the coordinates, so a long one cannot reach them")
    assert(mw.coords._shown == false and mw.coords:GetText() == "", "and are not under the map as well")
    assert(strip(mw.localTime:GetText()) == "20:26 local" and strip(mw.gameTime:GetText()) == "20:30 game", "the two times")
    assert(same(under("localTime"), { true, "LEFT", -8 }) and same(under("gameTime"), { true, "RIGHT", -8 }), "share one row under the map")
    assert(size() == "180x" .. (180 + 17 + 17) and ({ ns.Map.Insets() })[2] == 17, "one row above, one below: " .. size())
    -- the clocks and the coordinates are redrawn twice a second, by a frame that is always there
    env.C_Map.GetPlayerMapPosition = function() return { x = 0.101, y = 0.202 } end
    mw.events._scripts.OnUpdate(mw.events, 0.3)
    assert(mw.coordsTop:GetText() == "52.3, 48.1", "not before half a second")
    mw.events._scripts.OnUpdate(mw.events, 0.3)
    assert(mw.coordsTop:GetText() == "10.1, 20.2", "then they follow you")
    env.C_Map.GetPlayerMapPosition = function() return { x = 0.523, y = 0.481 } end
    -- hover the strip for the whole of a name that was cut short
    mw.zoneStrip._scripts.OnEnter(mw.zoneStrip)
    -- one time, or none: the row is centred, or goes
    change("gameTime", false)
    assert(same(under("localTime"), { true, "CENTER", -8 }) and mw.gameTime._shown == false and size() == "180x" .. (180 + 17 + 17), "one time is centred")
    change("localTime", false)
    assert(mw.info._shown == false and size() == "180x" .. (180 + 17) and ({ ns.Map.Insets() })[2] == 0, "no times: nothing under the map, though the coordinates are on")
    -- coordinates off: the zone's name has the whole strip again, centred
    change("coords", false)
    assert(mw.coordsTop._shown == false and mw.coordsTop:GetText() == "" and mw.zone._pointsBy.RIGHT[2] == mw.zoneStrip, "without coordinates the name has the whole strip")
    -- no zone strip: the coordinates go under the map, sharing with the times as before
    change("coords", true); change("localTime", true); change("gameTime", true); change("zone", false)
    assert(not ns.Map.CoordsOnTop() and mw.zoneStrip._shown == false and mw.coords:GetText() == "52.3, 48.1", "without the zone strip the coordinates are under the map")
    assert(same(under("coords"), { true, "CENTER", -8 }) and same(under("localTime"), { true, "LEFT", -24 }) and same(under("gameTime"), { true, "RIGHT", -24 }),
      "three things under the map: the coordinates a row, the times the next")
    assert(size() == "180x" .. (180 + 33) and ({ ns.Map.Insets() })[1] == 0 and ({ ns.Map.Insets() })[2] == 33, "two rows below, none above: " .. size())
    change("gameTime", false)
    assert(same(under("coords"), { true, "LEFT", -8 }) and same(under("localTime"), { true, "RIGHT", -8 }), "two share a row")
    change("zone", true); change("gameTime", true)
    assert(ns.Map.CoordsOnTop() and size() == "180x" .. (180 + 17 + 17), "back to the defaults")
  end
  ov.zone = ns.Map.widgets.zone:GetText()
  env.Minimap._scripts.OnMouseWheel(env.Minimap, 1); env.Minimap._scripts.OnMouseWheel(env.Minimap, -1); env.Minimap._scripts.OnMouseWheel(env.Minimap, -1)
  ov.zoom = ZOOM

  -- The addon's own unit frames.
  local pf = frameNamed("MintCommunityToolsPlayerFrame")
  local tf = frameNamed("MintCommunityToolsTargetFrame")
  local tot = frameNamed("MintCommunityToolsTotFrame")
  ov.playerName = pf.name:GetText()
  ov.playerHealth = { pf.health._minmax[2], pf.health._value, pf.healthText:GetText() }
  ov.playerPower = { pf.power._value, pf.powerText:GetText(), pf.level:GetText() }
  ov.playerColor = pf.health._color
  ov.powerColor = pf.power._color
  ov.portrait = pf.portrait._portrait
  ov.healthLeft = pf.health._pointsBy.TOPLEFT[4]
  ov.playerDebuffs = shownAuras(pf, "debuffs")
  ov.playerBuffs = shownAuras(pf, "buffs")
  ov.debuffBorder = pf.auras.debuffs.buttons[1] and rawget(pf.auras.debuffs.buttons[1], "_borderColor")
  local dcd = pf.auras.debuffs.buttons[1].cd
  ov.debuffSweep = { rawget(dcd, "_cd") ~= nil, rawget(dcd, "_cdExpiration") ~= nil, dcd._shown and true or false }
  ov.debuffStacks = pf.auras.debuffs.buttons[1].count:GetText()
  HEALTH = 999
  fire("UNIT_HEALTH", "pet")
  ov.healthAfterPet = pf.health._value
  fire("UNIT_HEALTH", "player")
  ov.healthAfterPlayer = pf.health._value
  HEALTH = 1234
  fire("UNIT_HEALTH", "player")
  -- The target frame follows the target.
  ov.targetHiddenAtFirst = tf._shown == false and tot._shown == false
  TARGET_EXISTS = true
  fire("PLAYER_TARGET_CHANGED")
  ov.target = { tf._shown, tf.name:GetText(), tf.healthText:GetText(), tf.level:GetText(), tf.health._color }
  ov.targetDebuffs = shownAuras(tf, "debuffs")
  ov.targetBuffs = shownAuras(tf, "buffs")
  ov.tot = { tot._shown, tot.name:GetText(), tot.healthText:GetText() }
  ov.combo = env.ComboFrame._point[2] == tf

  -- Names are whole: WoW Forever gives a last name where other clients put the realm.
  do
    assert(pf.name._pointsBy.LEFT[2] == pf.health and pf.name._pointsBy.RIGHT[2] == pf.healthText, "the name has the bar's width up to the numbers")
    local oldName = env.UnitName
    env.UnitName = function() return "Aldric", "Thornwood" end
    fire("UNIT_NAME_UPDATE", "player")
    assert(pf.name:GetText() == "Aldric Thornwood", "first and last name: " .. tostring(pf.name:GetText()))
    assert(tot.name:GetText() ~= "Aldric Thornwood", "another unit's name event leaves a frame alone")
    env.UnitName = function() return "Aldric", "Mock Realm" end
    fire("UNIT_NAME_UPDATE", "player")
    assert(pf.name:GetText() == "Aldric", "a realm is not a last name")
    env.UnitName = function() return "Aldric", "" end
    fire("UNIT_NAME_UPDATE", "player")
    assert(pf.name:GetText() == "Aldric", "an empty second value adds nothing")
    if VARIANT == "mainline" then
      env.UnitName = function() return secret("Aldric"), secret("Thornwood") end
      fire("UNIT_NAME_UPDATE", "player")
      assert(pf.name:GetText() == "Aldric Thornwood", "names that may be shown but not read are joined unread")
    end
    env.UnitName = oldName
    fire("UNIT_NAME_UPDATE", "player")
  end

  -- The 3D portrait: off by default; on, the unit's model stands where the flat picture did,
  -- and the flat picture comes back for a unit too far away to be drawn.
  do
    assert(S.units.portrait3d == false and pf.model and pf.model._shown == false and pf.portrait._shown, "flat portraits by default")
    S.units.portrait3d = true
    ns.Overhaul.Changed("units.portrait3d")
    assert(pf.model._shown and pf.model._unit == "player" and pf.portrait._shown == false, "the player's model is shown in place of the picture")
    assert(tf.model._shown and tf.model._unit == "target", "and the target's")
    assert(pf.model._size[1] == 44 and rawget(tot, "model") == false, "the model fills the portrait square; the small frames have none")
    assert(ns.Overhaul.needsReload == false, "the 3D portrait changes at once, without a reload")
    env.UnitIsVisible = function(unit) return unit ~= "target" end
    fire("PLAYER_TARGET_CHANGED")
    assert(tf.model._shown == false and tf.portrait._shown and tf.portrait._portrait == "target", "out of sight: the flat picture stands in")
    assert(pf.model._shown, "the player is always in sight")
    env.UnitIsVisible = nil
    fire("UNIT_MODEL_CHANGED", "target")
    assert(tf.model._shown, "a model change draws it again")
    S.units.portrait = false
    ns.Overhaul.Changed("units.portrait")
    assert(pf.model._shown == false and pf.portrait._shown == false, "portraits off hides both")
    S.units.portrait, S.units.portrait3d = true, false
    ns.Overhaul.Changed("units.portrait3d")
    assert(pf.model._shown == false and pf.portrait._shown, "back to the flat picture")
  end

  -- Sizes, fonts, the aura icons' sizes and their countdown numbers: the Unit frames page.
  do
    local sui = ns.settingsui
    local STANDARD = "Fonts\\FRIZQT__.TTF"
    local function step(path, dir)
      click("MintCommunityToolsSetting" .. (dir > 0 and "More_" or "Less_") .. path:gsub("%.", "_"))
    end
    local function changed(path) ns.Overhaul.Changed(path) end
    assert(pf._size[1] == 240 and pf._size[2] == 46 and tot._size[1] == 120 and tot._size[2] == 24, "the default sizes")
    assert(pf.name._font[1] == STANDARD and pf.name._font[2] == 10 and pf.name._font[3] == "", "the game's font at 10 by default")
    assert(sui.steppers["units.width"].text:GetText() == "Width: 240" and sui.font:GetText() == "Font: Game default", "the page shows what is set")

    -- width and height: the player and target frames together, their movers with them
    step("units.width", 1); step("units.height", 1)
    assert(S.units.width == 250 and S.units.height == 48, "a step each: " .. S.units.width .. "x" .. S.units.height)
    assert(pf._size[1] == 250 and pf._size[2] == 48 and tf._size[1] == 250 and tot._size[1] == 120, "the two main frames grow, the small ones do not")
    assert(mover("player")._size[1] == 250 and mover("player")._size[2] == 48, "the mover is the frame's size")
    assert(pf.portrait._size[1] == 46 and pf.health._pointsBy.TOPLEFT[4] == 48, "the portrait and the bars follow the height")
    assert(sui.steppers["units.width"].text:GetText() == "Width: 250", "and the page says so")
    assert(ns.Overhaul.needsReload == false, "sizes change at once, without a reload")
    step("units.smallWidth", -1); step("units.smallHeight", 1)
    assert(tot._size[1] == 110 and tot._size[2] == 26 and pf._size[1] == 250, "the small frames have a size of their own")
    -- kept inside what a size may be, from the buttons and from a hand-edited save file
    S.units.width = 400
    step("units.width", 1)
    assert(S.units.width == 400, "the + button stops at the most")
    S.units.width = 5
    changed("units.width")
    assert(pf._size[1] == 120, "a saved size outside the limits is brought inside them")
    -- not in combat: the game does not let a secure frame be resized then
    env.InCombatLockdown = function() return true end
    S.units.width = 240
    changed("units.width")
    assert(pf._size[1] == 120 and ns.Units.pendingResize == true, "in combat the size waits")
    env.InCombatLockdown = function() return false end
    fire("PLAYER_REGEN_ENABLED")
    assert(pf._size[1] == 240 and ns.Units.pendingResize == nil, "and is applied when combat ends")

    -- fonts: size, the game's own fonts, LibSharedMedia's when it is there
    step("units.fontSize", 1)
    assert(S.units.fontSize == 11 and pf.name._font[2] == 11 and pf.healthText._font[2] == 11 and pf.level._font[2] == 11
      and pf.powerText._font[2] == 11 and tot.name._font[2] == 11, "every text on every frame takes the size")
    click("MintCommunityToolsSettingFont")
    assert(S.units.font == "friz" and pf.name._font[1] == "Fonts\\FRIZQT__.TTF" and sui.font:GetText() == "Font: Friz Quadrata", "the font button steps to the next font")
    assert(#ns.Units.Fonts() == 5, "five fonts of the game's own")
    env.LibStub = function(name, silent)
      assert(name == "LibSharedMedia-3.0" and silent == true, "the library is asked for quietly")
      return { HashTable = function(self, kind)
        assert(kind == "font")
        return { ["Zed Font"] = "Interface\\AddOns\\X\\zed.ttf", ["Friz again"] = "Fonts\\frizqt__.ttf", ["Alpha Font"] = "Interface\\AddOns\\X\\alpha.ttf" }
      end }
    end
    local fonts = ns.Units.Fonts()
    assert(#fonts == 7 and fonts[6].label == "Alpha Font" and fonts[7].label == "Zed Font", "LibSharedMedia's fonts follow, in name order, without ones already listed")
    S.units.font = "media:Zed Font"
    changed("units.font")
    assert(pf.name._font[1] == "Interface\\AddOns\\X\\zed.ttf" and sui.font:GetText() == "Font: Zed Font", "a shared font is used")
    assert(ns.Units.NextFont("media:Zed Font") == "default", "after the last font comes the first")
    env.LibStub = nil
    changed("units.font")
    assert(pf.name._font[1] == STANDARD and sui.font:GetText() == "Font: Game default", "a font that is no longer there: the game's default")
    -- a font file the game cannot load answers false: the default stands in
    rawset(pf.name, "SetFont", function(self, path, size, flags)
      if path == "Fonts\\MORPHEUS.TTF" then return false end
      rawset(self, "_font", { path, size, flags })
      return true
    end)
    S.units.font = "morpheus"
    changed("units.font")
    assert(pf.name._font[1] == STANDARD and pf.healthText._font[1] == "Fonts\\MORPHEUS.TTF", "a font that will not load leaves the default on that text")
    rawset(pf.name, "SetFont", nil)

    -- buff and debuff icons: a size each, and countdown numbers each
    local debuff, buff = pf.auras.debuffs.buttons[1], tf.auras.buffs.buttons[1]
    assert(debuff._size[1] == 20 and buff._size[1] == 20 and debuff.cd._hideNumbers == false and buff.cd._hideNumbers == false, "icons at 20 with their numbers by default")
    step("units.debuffSize", 1); step("units.buffSize", -1)
    assert(debuff._size[1] == 22 and buff._size[1] == 18, "debuffs and buffs sized apart: " .. debuff._size[1] .. ", " .. buff._size[1])
    local box = sui.checks["units.debuffTimers"]
    rawset(box, "_checked", false)
    box._scripts.OnClick(box)
    assert(S.units.debuffTimers == false and debuff.cd._hideNumbers == true and buff.cd._hideNumbers == false, "countdown numbers off on debuffs only")
    step("units.perRow", -1)
    assert(S.units.perRow == 7, "icons in a row")
    -- the one size of an earlier version becomes both
    S.units.auraSize, S.units.buffSize = 30, nil
    ns.Overhaul.Settings()
    assert(S.units.buffSize == 30 and S.units.debuffSize == 22 and S.units.auraSize == nil, "an earlier version's single icon size is carried over")

    S.units.font, S.units.fontSize, S.units.width, S.units.height, S.units.smallWidth, S.units.smallHeight = "default", 10, 240, 46, 120, 24
    S.units.buffSize, S.units.debuffSize, S.units.perRow, S.units.buffTimers, S.units.debuffTimers = 20, 20, 8, true, true
    changed("units.width")
    assert(pf._size[1] == 240 and pf._size[2] == 46 and tot._size[2] == 24 and pf.name._font[2] == 10 and debuff.cd._hideNumbers == false, "back to the defaults")
  end

  -- The chat backdrop is fastened to the chat window itself, tabs and edit box included, and
  -- the window goes back on its mover when the game's own layout arrives and moves it.
  do
    local bd = ns.Chat.backdrop
    assert(bd and bd._shown, "the chat backdrop is on by default")
    local tl, br = bd._pointsBy.TOPLEFT, bd._pointsBy.BOTTOMRIGHT
    assert(tl[2] == env.ChatFrame1 and tl[4] == -4 and tl[5] == 4 + ns.Chat.TAB_ROOM, "from above the tabs")
    assert(br[2] == env.ChatFrame1 and br[4] == 4 and br[5] == -ns.Chat.EDIT_ROOM, "to under the edit box")
    env.ChatFrame1:SetPoint("BOTTOMLEFT", env.UIParent, "BOTTOMLEFT", 0, 0)
    fire("EDIT_MODE_LAYOUTS_UPDATED")
    assert(env.ChatFrame1._point[2] == mover("chat"), "the game's layout moved the window: it is put back on its mover")
  end

  -- The quest tracker: the addon's own list of what the game says is tracked.
  do
    local Q, qt = ns.Quests, ns.Quests.ui
    local YELLOW = "|cffffd100"
    local function titles()
      local t = {}
      for _, row in ipairs(qt.titles) do if row._shown then t[#t + 1] = row.text:GetText() end end
      return t
    end
    local function lines()
      local t = {}
      for _, fs in ipairs(qt.lines) do
        if fs._shown then
          local c = fs._textColor
          t[#t + 1] = fs:GetText() .. " @" .. math.floor(c[1] * 100 + 0.5) .. "," .. math.floor(c[2] * 100 + 0.5)
        end
      end
      return t
    end
    local function tick(dt) qt.frame._scripts.OnUpdate(qt.frame, dt) end
    assert(Q.Source() == (VARIANT == "classic" and "classic" or "modern"), "the quest list is read the way this client offers: " .. tostring(Q.Source()))
    assert(ns.Overhaul.applied.quests, "the quest tracker is a piece of the overhaul")
    assert(env.ObjectiveTrackerFrame._parent == hider and env.QuestWatchFrame._parent == hider and Q.hidden == 2, "the game's own tracker is hidden, by either name")
    assert(qt.frame._pointsBy.TOPLEFT[2] == mover("quests") and mover("quests")._size[1] == 250, "the list sits on its mover")
    assert(qt.count:GetText() == "3 tracked", qt.count:GetText())
    local t, l = titles(), lines()
    assert(#t == 3 and t[1] == YELLOW .. "[2] Kobold Camp Cleanup|r" and t[2] == YELLOW .. "[4] Brotherhood of Thieves|r" and t[3] == YELLOW .. "[5] Milly's Harvest|r",
      "titles with their level, in the difficulty's colour: " .. table.concat(t, " / "))
    -- what is left in the text colour (90), what is done dimmed (55), a finished quest in green
    assert(#l == 3 and l[1] == "Kobold Vermin slain: 3/8 @90,90" and l[2] == "Kobold Worker slain: 8/8 @55,55" and l[3] == "Ready to turn in @35,85",
      "objectives: " .. table.concat(l, " / "))
    assert(qt.backdrop._shown == false, "no backdrop by default")

    -- Settings: the level can be left out, and a backdrop put behind the list, at once.
    local checks = ns.settingsui.checks
    rawset(checks["quests.levels"], "_checked", false)
    checks["quests.levels"]._scripts.OnClick(checks["quests.levels"])
    assert(S.quests.levels == false and titles()[1] == YELLOW .. "Kobold Camp Cleanup|r", "without levels: " .. titles()[1])
    rawset(checks["quests.background"], "_checked", true)
    checks["quests.background"]._scripts.OnClick(checks["quests.background"])
    assert(qt.backdrop._shown and ns.Overhaul.needsReload == false, "the backdrop shows without a reload")
    S.quests.levels, S.quests.background = true, false
    ns.Overhaul.Changed("quests.levels")

    -- The header folds the list away and brings it back.
    click("MintCommunityToolsQuestHeader")
    assert(S.quests.collapsed == true and #titles() == 0 and #lines() == 0 and qt.body._shown == false, "folded")
    assert(qt.count:GetText() == "3 tracked, folded" and qt.frame._size[2] == 18, "folded: the header alone, saying so")
    click("MintCommunityToolsQuestHeader")
    assert(S.quests.collapsed == false and #titles() == 3, "unfolded")

    -- Click a quest: it opens in the quest log. Shift-click: it is no longer tracked.
    qt.titles[2]._scripts.OnClick(qt.titles[2])
    if VARIANT == "classic" then
      assert(#QUEST_SELECTED == 1 and QUEST_SELECTED[1] == 3, "the quest log is put on that quest's row")
    else
      assert(#QUEST_OPENED == 1 and QUEST_OPENED[1] == 102, "the quest log is opened to that quest")
    end
    SHIFT = true
    qt.titles[2]._scripts.OnClick(qt.titles[2])
    SHIFT = false
    assert(#WATCHED == 2 and qt.count:GetText() == "2 tracked" and titles()[2] == YELLOW .. "[5] Milly's Harvest|r", "shift-click stops tracking")
    assert(#lines() == 2, "the untracked quest's lines are gone")

    -- The game says the log changed, several times over: the list is drawn once, a moment later.
    WATCHED[#WATCHED + 1] = 104
    fire("QUEST_WATCH_LIST_CHANGED")
    fire("QUEST_LOG_UPDATE")
    assert(#titles() == 2, "not drawn again at once")
    tick(0.06)
    assert(#titles() == 2, "nor before a tenth of a second")
    tick(0.06)
    assert(#titles() == 3 and titles()[3] == YELLOW .. "[10] A Fishy Peril|r" and lines()[3] == "Speak with Gryan Stoutmantle @90,90", "then it is")

    -- The list stops at the height it may take and says what did not fit.
    S.quests.maxHeight = 40
    Q.Refresh()
    assert(#titles() == 1 and lines()[3] == "+2 more @55,55", "what does not fit is counted: " .. table.concat(lines(), " / "))
    S.quests.maxHeight = 420
    local saved = { unpack(WATCHED) }
    for i = #WATCHED, 1, -1 do WATCHED[i] = nil end
    Q.Refresh()
    assert(#titles() == 0 and qt.count:GetText() == "0 tracked" and lines()[1]:find("Nothing tracked", 1, true), "an empty list says so")
    for i, id in ipairs(saved) do WATCHED[i] = id end
    Q.Refresh()
    assert(#titles() == 3, "and the quests are back")

    -- The game takes its own tracker back some time after login (its edit mode layout
    -- arrives): within a second it is hidden again. Not in combat; then at the next look.
    env.ObjectiveTrackerFrame:SetParent(env.UIParent)
    qt.sinceCheck = 0
    tick(0.5)
    assert(env.ObjectiveTrackerFrame._parent == env.UIParent, "not before a second has passed")
    tick(0.6)
    assert(env.ObjectiveTrackerFrame._parent == hider and env.ObjectiveTrackerFrame._shown == false, "the game's tracker is hidden again")
    assert(Q.Check() == 0, "and there is nothing more to do")
    env.ObjectiveTrackerFrame:SetParent(env.UIParent)
    env.InCombatLockdown = function() return true end
    assert(Q.Check() == 0 and env.ObjectiveTrackerFrame._parent == env.UIParent, "left alone in combat")
    env.InCombatLockdown = function() return false end
    fire("EDIT_MODE_LAYOUTS_UPDATED")
    tick(0.2)
    assert(env.ObjectiveTrackerFrame._parent == hider, "hidden again when the game's layout arrives")
  end

  -- The game menu and the windows it opens: the art gone, flat panels and buttons in its place.
  do
    local M = ns.Menus
    local function black(tex) local c = tex._colorTexture; return c[1] == 0 and c[2] == 0 and c[3] == 0 end
    assert(ns.Overhaul.applied.menus and M.count == 3, "the game menu is a piece of the overhaul; three of its windows exist: " .. tostring(M.count))
    assert(M.windows.GameMenuFrame and M.windows.SettingsPanel and not M.windows.MacroFrame, "the windows that exist are dressed")
    -- the menu: border, header and background art invisible, the title's text left alone
    assert(MENU.borderArt._alpha == 0 and MENU.headerArt._alpha == 0 and MENU.ownArt._alpha == 0, "the menu's art is invisible")
    assert(rawget(MENU.headerText, "_alpha") == nil, "its title is not")
    local d = M.dressed[MENU.frame]
    assert(d and #d.edges == 4 and d.bg._colorTexture[4] > 0 and black(d.edges[1]), "a flat background and four black edges on the menu")
    assert(M.windows.GameMenuFrame.art == 3 and M.windows.GameMenuFrame.buttons == 2, "counted: " .. M.windows.GameMenuFrame.art .. " art, " .. M.windows.GameMenuFrame.buttons .. " buttons")
    -- its buttons, whatever their art is kept in: flat, the border lit under the mouse
    assert(M.dressed[MENU.options] and M.dressed[MENU.plain] and MENU.optionsArt._alpha == 0 and MENU.plainArt._alpha == 0, "the menu's buttons are flat")
    MENU.options._hooks.OnEnter(MENU.options)
    assert(not black(M.dressed[MENU.options].edges[1]), "the border lights up under the mouse")
    MENU.options._hooks.OnLeave(MENU.options)
    assert(black(M.dressed[MENU.options].edges[1]), "and goes back")
    -- the game makes the menu's buttons anew when it opens: they are dressed then
    local late, lateArt = MENU.pushButton("Center")
    MENU.children[#MENU.children + 1] = late
    rawset(MENU.optionsArt, "_alpha", 1)   -- and shows a button's art again
    MENU.frame._hooks.OnShow(MENU.frame)
    assert(M.dressed[late] and lateArt._alpha == 0 and MENU.optionsArt._alpha == 0, "buttons made later are dressed when the menu opens")
    assert(#M.dressed[MENU.frame].edges == 4 and M.dressed[MENU.frame] == d, "the menu itself is dressed once")
    -- the options window: its parts, its push buttons a few levels down, its close button
    assert(SP.nineArt._alpha == 0 and SP.bg._alpha == 0, "a NineSlice frame and a single Bg texture are both cleared")
    assert(M.dressed[SP.close] and SP.closeArt._alpha == 0 and M.dressed[SP.defaults], "push buttons are flat, three levels down too")
    assert(M.dressed[SP.x] and M.dressed[SP.x].mark:GetText() == "x" and SP.xArt._alpha == 0, "the close button is a flat square with an x")
    assert(M.dressed[SP.close].mark == nil, "a close button that says Close keeps its word and gets no x")
    -- the controls inside it, each told apart by what kind of widget it is
    local WHITE = "Interface\\Buttons\\WHITE8X8"
    assert(M.dressed[SP.check] and M.dressed[SP.check].inset == 6 and SP.checkArt._alpha == 0, "a check box: its box art gone, a flat square inside the frame")
    assert(SP.tick._texture == WHITE and rawget(SP.tick, "_alpha") == nil, "its tick is a block of colour, and still shows")
    assert(not M.dressed[SP.iconCheck] and rawget(SP.iconCheckArt, "_alpha") == nil, "a check button with an icon is left alone")
    assert(M.dressed[SP.dropdown] and SP.dropBg._alpha == 0 and SP.dropArrow._alpha == 0 and M.dressed[SP.dropdown].mark:GetText() == "v", "a drop-down: flat, with a v")
    assert(SP.sliderBar._alpha == 0 and SP.sliderThumb._texture == WHITE and SP.sliderThumb._size[1] == 8 and M.dressed[SP.slider].bg, "a slider: a thin bar and a flat thumb")
    assert(M.dressed[SP.search] and SP.searchArt._alpha == 0, "a search box: flat")
    assert(SP.trackArt._alpha == 0 and SP.thumbArt._alpha == 0 and M.dressed[SP.track] and M.dressed[SP.thumb], "a scroll bar: a flat track and thumb")
    assert(M.dressed[SP.inset] and SP.insetCorner._alpha == 0 and M.dressed[SP.inset].bg._colorTexture[4] == 0.2, "a framed area: a 1px border and a faint darkening")
    assert(M.dressed[SP.heading] and SP.banner._alpha == 0 and SP.bar._texture == WHITE and not M.dressed[SP.entry], "the category list: banners gone, the entry's bar flat")
    -- tabs: flat, the open one's border lit; a click moves the light
    assert(M.dressed[SP.tabA].tab and not black(M.dressed[SP.tabA].edges[1]) and black(M.dressed[SP.tabB].edges[1]), "the open tab's border is lit")
    SP.OPEN = "B"
    SP.tabB._hooks.OnClick(SP.tabB)
    assert(black(M.dressed[SP.tabA].edges[1]) and not black(M.dressed[SP.tabB].edges[1]), "a click on the other tab moves the light")
    SP.tabA._hooks.OnEnter(SP.tabA); SP.tabA._hooks.OnLeave(SP.tabA)
    assert(black(M.dressed[SP.tabA].edges[1]), "the mouse leaving a closed tab leaves it dark")
    SP.tabB._hooks.OnLeave(SP.tabB)
    assert(not black(M.dressed[SP.tabB].edges[1]), "and the open tab lit")
    assert(M.windows.SettingsPanel.buttons == 13, "controls dressed in the options window: " .. M.windows.SettingsPanel.buttons)
    -- a scrolling list's rows are made as it scrolls: a new row is dressed when looked over again
    local heading2, banner2 = MENU.typed(stub(), "Frame"), MENU.art()
    rawset(heading2, "Background", banner2); rawset(heading2, "Label", stub()); MENU.holding(heading2, { banner2 })
    MENU.holding(SP.scrollTarget, {}, { SP.heading, SP.entry, heading2 })
    assert(M.DressInside(SP.scrollTarget) == 3 and banner2._alpha == 0, "new rows are dressed")
    -- a confirmation box: the border goes, its own pictures stay, its plain buttons are flat
    local POP = MENU.popup
    assert(M.windows.StaticPopup1 and POP.bgArt._alpha == 0 and rawget(POP.alert, "_alpha") == nil, "a popup's border is cleared, its alert icon is not")
    assert(M.dressed[POP.frame] and M.dressed[POP.button] and POP.buttonArt._alpha == 0, "a popup and its buttons are flat")
    -- a window that only exists once its part of the interface loads
    local macro = MENU.typed(stub("MacroFrame"), "Frame")
    local macroArt = MENU.art()
    MENU.holding(macro, { macroArt }, {})
    env.MacroFrame = macro
    fire("ADDON_LOADED", "Blizzard_MacroUI")
    assert(M.windows.MacroFrame and macroArt._alpha == 0 and M.dressed[macro] and M.count == 4, "a window that loads later is dressed then")
    assert(ns.settingsui.checks["menus.enabled"], "the game menu has its switch on the General page")
    env.MacroFrame = nil   -- the harness's own, not a global the addon made
  end

  -- Edit mode: the movers show, drag, remember, and reset.
  slash("edit")
  ov.editing = ns.Overhaul.Editing()
  ov.moverAlpha = mover("player")._alpha
  ov.editBar = frameNamed("MintCommunityToolsEditBar")._shown
  local pm = mover("player")
  rawset(pm, "GetPoint", function() return "BOTTOMLEFT", nil, "BOTTOMLEFT", 100.4, 200.6 end)
  pm._scripts.OnDragStart(pm)
  pm._scripts.OnDragStop(pm)
  ov.saved = S.positions.player
  ns.Overhaul.Mover("player", "Player frame", 220, 46)   -- placed again from what was saved, as at the next login
  ov.placed = { pm._point[1], pm._point[4], pm._point[5] }
  pm._scripts.OnMouseUp(pm, "RightButton")
  ov.resetSaved = S.positions.player == nil
  ov.resetPlaced = { pm._point[1], pm._point[4], pm._point[5] }
  slash("edit")
  ov.editingAfter = ns.Overhaul.Editing()
  ov.moverAlphaAfter = mover("player")._alpha

  -- The Settings tab.
  slash("")
  click("MintCommunityToolsTab3")
  ov.settingsTab = ns.UI.CurrentTab()
  local checks = ns.settingsui.checks
  ov.enabledChecked = checks["enabled"]._checked
  ov.portraitChecked = checks["units.portrait"]._checked
  local cb = checks["units.portrait"]
  rawset(cb, "_checked", false)
  cb._scripts.OnClick(cb)
  ov.portraitOff = { S.units.portrait, pf.portrait._shown, pf.health._pointsBy.TOPLEFT[4] }
  ov.needsReloadBefore = ns.Overhaul.needsReload
  ov.cycleBefore = ns.settingsui.cycles["units.player.buffs"]:GetText()
  click("MintCommunityToolsSettingCycle_units_player_buffs")
  ov.cycleAfter = { ns.settingsui.cycles["units.player.buffs"]:GetText(), S.units.player.buffs }
  ov.playerBuffsAfter = shownAuras(pf, "buffs")
  local om = checks["units.target.onlyMine"]
  rawset(om, "_checked", true)
  om._scripts.OnClick(om)
  ov.targetDebuffsMine = shownAuras(tf, "debuffs")
  ov.rendStacks = tf.auras.debuffs.buttons[1].count:GetText()
  ov.statusLive = ns.settingsui.status:GetText()
  -- The keyring and reagent bag slot can be left out of the bag row, at once.
  local extra = checks["bars.extraBags"]
  rawset(extra, "_checked", false)
  extra._scripts.OnClick(extra)
  ov.keyringOff = { S.bars.extraBags, env.KeyRingButton._shown, ns.Overhaul.needsReload, ns.Bars.Check() }
  local bars = checks["bars.enabled"]
  rawset(bars, "_checked", false)
  bars._scripts.OnClick(bars)
  ov.needsReloadAfter = ns.Overhaul.needsReload
  ov.statusReload = ns.settingsui.status:GetText()
  slash("ui")
  TARGET_EXISTS = false
  fire("PLAYER_TARGET_CHANGED")
  ov.targetGone = tf._shown == false
else
  assert(rawget(MENU.borderArt, "_alpha") == nil and ns.Menus.dressed[MENU.frame] == nil and ns.Overhaul.applied.menus == nil,
    "with the overhaul off the game menu is not touched")
  ov.playerUntouched = rawget(env.PlayerFrame, "_parent") == nil and rawget(env.ActionButton1, "_point") == nil and rawget(env.Minimap, "_mask") == nil
  ov.noFrames = not pcall(frameNamed, "MintCommunityToolsPlayerFrame")
  slash("edit")
  ov.editRefused = not ns.Overhaul.Editing()
  slash("ui on")
  ov.turnedOn = { S.enabled, ns.Overhaul.needsReload }
  slash("")
  click("MintCommunityToolsTab3")
  ov.statusReload = ns.settingsui.status:GetText()
  slash("ui off")
  ov.turnedOff = S.enabled
end

-- The Settings tab is split into pages: one shows at a time, picked by the row of buttons.
do
  local sui = ns.settingsui
  local keys = {}
  for _, def in ipairs(ns.SettingsUI.PAGES) do keys[#keys + 1] = def.key end
  assert(table.concat(keys, ",") == "general,bars,chat,units,map,quests", "the pages: " .. table.concat(keys, ","))
  click("MintCommunityToolsSettingsPage_units")
  assert(sui.page == "units" and sui.pages.units._shown and sui.pages.general._shown == false and sui.pages.quests._shown == false, "one page shows at a time")
  click("MintCommunityToolsSettingsPage_quests")
  assert(sui.pages.quests._shown and sui.pages.units._shown == false, "the quests page")
  assert(sui.checks["units.portrait3d"] and sui.checks["quests.enabled"] and sui.checks["quests.levels"] and sui.checks["quests.background"], "the new switches exist")
  click("MintCommunityToolsSettingsPage_general")
  assert(sui.page == "general" and sui.pages.general._shown, "back to the general page")
end
if VARIANT == "forever" then
  assert(ns.Quests.Source() == nil and #ns.Quests.List() == 0, "a client with no quest list the addon can read: nothing, and no error")
end

-- The Settings tab's own switches for the minimap button: shown or not, and its shape.
do
  local mdb = ns.DB().minimap
  local sui = ns.settingsui
  ns.SettingsUI.Refresh()
  assert(sui.buttonShown._checked == true, "the Settings tab shows the minimap button as on")
  local now = ns.MinimapShape()
  assert(sui.buttonShape:GetText() == "Button shape: auto (" .. now .. " now)", "and its shape: " .. tostring(sui.buttonShape:GetText()))
  click("MintCommunityToolsSettingMinimapShape")
  assert(mdb.shape == "round" and sui.buttonShape:GetText() == "Button shape: round", "the shape button steps to round")
  click("MintCommunityToolsSettingMinimapShape")
  assert(mdb.shape == "square" and sui.buttonShape:GetText() == "Button shape: square" and ns.MinimapShape() == "square", "then square")
  click("MintCommunityToolsSettingMinimapShape")
  assert(mdb.shape == "auto", "then back to auto")
  slash("minimap square")
  assert(sui.buttonShape:GetText() == "Button shape: square", "the tab follows the slash command")
  slash("minimap auto")
  rawset(sui.buttonShown, "_checked", false)
  sui.buttonShown._scripts.OnClick(sui.buttonShown)
  assert(not mm._shown and mdb.shown == false, "the checkbox hides the button")
  slash("minimap show")
  assert(mm._shown and sui.buttonShown._checked == true, "/mint minimap show brings it back and ticks the box")
end

-- /mint uidump: what this client's interface is made of, into the saved variables.
slash("uidump")
do
  local bags = env.MintCommunityToolsDB.uiDump.bags
  assert(type(bags) == "table" and bags.error == nil and bags.buttons.KeyRingButton and bags.apis.ToggleBag == "nil", "the dump says what the bag buttons are: " .. tostring(bags and bags.error))
  assert(bags.buttons.CharacterReagentBag0Slot.id == 35 and bags.buttons.CharacterReagentBag0Slot.item == "nil", "the reagent slot's slot, and that it is empty")
  assert(S.enabled ~= true or bags.clicks.KeyRingButton.count == 2, "and what clicks on them did")
end
slash("uidump menus")
do
  local menus = env.MintCommunityToolsDB.uiDump
  assert(menus.group == "menus" and menus.frames.GameMenuFrame and menus.frames.SettingsPanel and menus.frames.Minimap == nil,
    "/mint uidump menus records the game menu and its windows, and only those")
  assert(S.enabled ~= true or (menus.menus and menus.menus.GameMenuFrame), "with what the addon did to each")
end
slash("uidump")
local dump = env.MintCommunityToolsDB.uiDump
ov.dump = { type(dump), dump and dump.count > 0, dump and type(dump.frames.Minimap), dump and dump.apis.UnitXP,
            dump and dump.apis.NoSuchThing == nil, dump and #dump.missing > 0 }

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
  chunkButtons = chunkButtons, chunkDone = chunkDone, watchButton = watchButton, state = state,
  minimapSquare = minimapSquare, overhaul = ov })
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
    x, y = result["minimapStart"]
    if variant == "classic":
        # The overhaul's square map: the button sits 82 out along the square, at the saved angle (90, from version 0.1's place).
        assert result["minimapSquare"] is True
        assert abs(x) < 0.001 and abs(y - 99) < 0.001, (x, y)   # 82, and 17 more to clear the zone strip
    else:
        assert result["minimapSquare"] is False
        assert abs(result["minimapRadius"] - 75) < 0.001, f"half the minimap's width plus 5: {result['minimapRadius']}"
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
    if variant in ("classic", "mainline"):
        # The overhaul's map is set up in these two, and tells other addons' minimap buttons
        # what shape it is and how much room its strips take. Nothing else may leak.
        expected_globals = sorted(expected_globals + ["GetMinimapShape", "GetMinimapEdgeInsets"])
    assert result["newglobals"] == expected_globals, f"unexpected globals: {result['newglobals']}"


def check_overhaul(result, variant):
    ov = result["overhaul"]
    assert ov["failed"] is False, f"a piece of the overhaul failed: {ov['failed']}"
    assert ov["dump"] == ["table", True, "table", "function", True, True], ov["dump"]
    if variant == "forever":
        assert ov["enabled"] is False, "off by default"
        assert ov["playerUntouched"] is True and ov["noFrames"] is True, "nothing of the game's UI is touched while it is off"
        assert ov["editRefused"] is True
        assert ov["turnedOn"] == [True, True] and ov["turnedOff"] is False
        assert "Reload to apply" in strip_colors(ov["statusReload"])
        return

    assert ov["enabled"] is True
    assert ov["playerHidden"] is True and ov["targetHidden"] is True and ov["petKept"] is True
    assert ov["pet"] == [True, "62%", False], ov["pet"]   # the addon's own small pet frame: a percentage, no aura rows
    assert ov["bar1"] == 11 * 34, "twelve 32px buttons, 2px apart, on bar 1's mover"
    assert ov["bar1Size"] == 32 and ov["bar1Mover"] == [12 * 34 - 2, 32]
    assert ov["icon"] == [True, True, "ARTWORK"], ov["icon"]
    assert ov["keyring"] == [True, "Interface\\Icons\\INV_Misc_Key_03", True, 0, True], ov["keyring"]
    assert ov["reagentEmpty"] == ["Interface\\Icons\\Trade_Herbalism", True, 0.45, 0], ov["reagentEmpty"]
    assert ov["reagentFilled"] == [False, 1] and ov["reagentEmptyAgain"] is True, (ov["reagentFilled"], ov["reagentEmptyAgain"])
    assert ov["keyringOff"] == [False, False, False, 0], ov["keyringOff"]
    assert ov["bar2"] is True and ov["petbar"] == 26, "the pet bar's buttons are smaller"
    assert ov["gryphon"] == 0 and ov["bags"] is True and ov["micro"] is True
    # The micro buttons come from the game's own list when it has one (two that exist, one that does not).
    # ...followed by any known button it left out.
    assert ov["microCount"] == 3, ov["microCount"]
    assert ov["cluster"] == ([True, True, True] if variant == "mainline" else False), "the dial goes, tracking moves onto the map"
    assert ov["relayout"] is True
    assert ov["bagsFirst"] == 0, "nothing has strayed after a fresh layout"
    assert ov["bagsStrayed"] is True and ov["bagsFixed"] == 2, "the bag bar and action bar 1 are both put back"
    assert ov["bagsBack"] is True and ov["bagsAgain"] == 0 and ov["watch"] == "function"
    assert ov["endCaps"] == (0 if variant == "mainline" else False), "end caps kept in a field are blanked too"
    assert ov["xp"] == [True, 20000, 12345, True, 20000, "xp"], ov["xp"]   # rested reaches past the end: capped at the bar's length
    assert ov["xpBlizzard"] is True and ov["xpMover"] == [406, 8]
    assert ov["rep"] == ["rep", "Argent Dawn", 6000, 1500, False], ov["rep"]
    assert ov["mapSwept"] >= 1, "textures on the minimap's backdrop are swept, whatever they are called"
    assert ov["chat"] is True and ov["chatArt"] == 0 and ov["chatButtons"] is True and ov["chatEdit"] is True
    assert ov["minimap"] is True and ov["mask"] == "Interface\\Buttons\\WHITE8X8" and ov["zoomHidden"] is True
    assert ov["zone"] == "Elwynn Forest" and ov["zoom"] == -1, "the wheel zooms"

    me = "Théoden Stormwind" if variant == "forever" else "Théoden"
    assert ov["playerName"] == me
    # On the newest engine current health is a secret value: it reaches the bar as it is, and the
    # text without thousands separators (those would need the digits).
    health_text = "1234 / 2,000" if variant == "mainline" else "1,234 / 2,000"
    assert ov["playerHealth"] == [2000, 1234, health_text], ov["playerHealth"]
    assert ov["playerPower"][0] == 600 and ov["playerPower"][1] == "600" and strip_colors(ov["playerPower"][2]) == "60"
    assert [round(c, 2) for c in ov["playerColor"]] == [0.78, 0.61, 0.43], "class colour"
    assert ov["powerColor"] == [0, 0, 1], "mana"
    assert ov["portrait"] == "player" and ov["healthLeft"] == 46, "the portrait takes the left of the frame"
    assert ov["playerDebuffs"] == [1, True, "BOTTOMLEFT"], "one debuff, above"
    assert ov["playerBuffs"] == ([2, True, "TOPLEFT"] if variant == "classic" else [0, False, False]), "buffs below (saved) or off (default)"
    assert [round(c, 1) for c in ov["debuffBorder"]] == [0.2, 0.6, 1, 1], "a magic debuff's border"
    # The sweep is set from the start time where the numbers may be read, from the end time where they are secret.
    assert ov["debuffSweep"] == ([False, True, True] if variant == "mainline" else [True, False, True]), ov["debuffSweep"]
    assert ov["debuffStacks"] == "", "one stack shows no number"
    assert ov["healthAfterPet"] == 1234 and ov["healthAfterPlayer"] == 999, "only the frame's own unit's events count"
    assert ov["targetHiddenAtFirst"] is True
    assert ov["target"][0] is True and ov["target"][1] == "Hogger" and ov["target"][2] == "50 / 100" and strip_colors(ov["target"][3]) == "60+"
    assert ov["target"][4] == [1, 0, 0], "a hostile's reaction colour"
    assert ov["targetDebuffs"] == [3, True, "BOTTOMLEFT"] and ov["targetBuffs"] == [1, True, "BOTTOMLEFT"]
    assert ov["tot"] == [True, me, "62%"], ov["tot"]
    assert ov["combo"] is True

    assert ov["editing"] is True and ov["moverAlpha"] == 1 and ov["editBar"] is True
    assert ov["saved"] == ["BOTTOMLEFT", 100, 201] and ov["placed"] == ["BOTTOMLEFT", 100, 201]
    assert ov["resetSaved"] is True and ov["resetPlaced"] == ["BOTTOM", -200, 220]
    assert ov["editingAfter"] is False and ov["moverAlphaAfter"] == 0

    assert ov["settingsTab"] == "settings" and ov["enabledChecked"] is True and ov["portraitChecked"] is True
    assert ov["portraitOff"] == [False, False, 1], "no portrait: the bars take the whole width at once"
    assert ov["needsReloadBefore"] is False, "a live setting needs no reload"
    before, after = ("Player buffs: Below", ["Player buffs: Left", "left"]) if variant == "classic" else ("Player buffs: Off", ["Player buffs: Above", "above"])
    assert ov["cycleBefore"] == before and ov["cycleAfter"] == after, (ov["cycleBefore"], ov["cycleAfter"])
    assert ov["playerBuffsAfter"] == [2, True, "TOPRIGHT" if variant == "classic" else "BOTTOMLEFT"]
    assert ov["targetDebuffsMine"] == [1, True, "BOTTOMLEFT"], "only my debuffs"
    assert ov["rendStacks"] == "3", "three stacks, read or asked for"
    assert "is on" in strip_colors(ov["statusLive"]), ov["statusLive"]
    assert ov["needsReloadAfter"] is True and "Reload to apply" in strip_colors(ov["statusReload"])
    assert ov["targetGone"] is True


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
    check_overhaul(result, variant)

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
