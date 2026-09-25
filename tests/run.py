#!/usr/bin/env python3
"""
Runs the Mint Community Tools addon in a real Lua 5.1 interpreter against a mocked WoW API, drives the
window (builds it, clicks Rescan and Export), then independently decodes the export string with
Python (base64, zlib, json) and checks it against docs/export-string-format-v1.md.

Three mocked clients:
  forever   WoW Forever: UnitName returns the first name with the LAST NAME as its second value,
            Classic talent API, GetItemStats.
  classic   Classic Era: UnitName returns the name alone, Classic talent API.
  mainline  Mainline-style: UnitName's second value is the REALM (must not become a last name),
            C_Item namespace, detailed item level, no Classic talent API, a German locale.

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
FILES = ["Encode.lua", "Collect.lua", "UI.lua", "Core.lua"]
VARIANTS = ["forever", "classic", "mainline"]
VERBOSE = "-v" in sys.argv
# --write-fixtures saves the export strings the addon actually produced, for the website's
# importer tests to consume. Commit the result.
WRITE_FIXTURES = "--write-fixtures" in sys.argv
FIXTURE_DIR = Path(__file__).resolve().parent / "fixtures"

# ---------------------------------------------------------------------------
# Lua side: mocked WoW environment. Chunks are loaded with loadstring + setfenv so the
# addon sees only the mock API, exactly as it would inside the game.
# ---------------------------------------------------------------------------
LUA_PRELUDE = r'''
local out = { prints = {}, texts = {}, frames = {} }

-- Generic no-op frame stub. It records SetText calls, remembers scripts and registered
-- events (so the harness can fire events and click buttons), and answers anything else
-- with another stub.
local function stub(name)
  local o = { _name = name, _scripts = {}, _events = {}, _shown = false }
  table.insert(out.frames, o)
  return setmetatable(o, { __index = function(t, k)
    return function(self, ...)
      if k == "SetText" then rawset(self, "_text", (...)); table.insert(out.texts, (...)) end
      if k == "GetText" then return rawget(self, "_text") or "" end
      if k == "SetScript" then local kind, fn = ...; rawget(self, "_scripts")[kind] = fn; return end
      if k == "RegisterEvent" then rawget(self, "_events")[(...)] = true; return end
      if k == "UnregisterEvent" then rawget(self, "_events")[(...)] = nil; return end
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

local function click(name)
  for _, f in ipairs(out.frames) do
    if f._name == name then
      assert(f._scripts.OnClick, name .. " has no OnClick")
      f._scripts.OnClick(f)
      return
    end
  end
  error("no frame named " .. name)
end

local function frameNamed(name)
  for _, f in ipairs(out.frames) do if f._name == name then return f end end
  error("no frame named " .. name)
end

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
}
local function itemIdOf(link) return tonumber(link:match("|Hitem:(%d+)")) end

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
  UIParent = stub("UIParent"), Minimap = stub("Minimap"), GameTooltip = stub("GameTooltip"),
  ChatFontNormal = {}, GameFontHighlight = {}, GameFontHighlightSmall = {},
  SlashCmdList = {}, UISpecialFrames = {},
  CreateFrame = function(_, name) return stub(name) end,
  GetCursorPosition = function() return 0, 0 end,
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
}
if VARIANT == "classic" then
  -- Classic Era: no last names, UnitName's second value is nil for your own character.
  env.UnitName = function() return "Th\195\169oden", nil end
elseif VARIANT == "mainline" then
  -- Mainline-style client: UnitName's second value is the realm, no Classic talent API,
  -- C_Item namespace, detailed item level available, a German locale.
  env.UnitName = function() return "Th\195\169oden", "MockRealm" end
  env.GetNumTalentTabs = nil; env.GetTalentTabInfo = nil; env.GetNumTalents = nil; env.GetTalentInfo = nil
  local classicGetItemInfo = env.GetItemInfo
  env.GetItemInfo = nil
  env.C_Item = { GetItemInfo = classicGetItemInfo,
                 GetItemStats = env.GetItemStats,
                 GetDetailedItemLevelInfo = function(link) return 72.0, false, 66 end }
  env.GetItemStats = nil
  env.C_Timer = { After = function(t, fn) fn() end }
  env.BackdropTemplateMixin = {}
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

slash("selftest")
slash("debug")
slash("scan")
slash("help")

-- The window: /mint builds and opens it; the gear list is filled on show.
slash("")
local frame = frameNamed("MintCommunityToolsFrame")
assert(frame._shown, "/mint opens the window")
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

local newg = {}
for k in pairs(env) do if not before[k] then newg[#newg + 1] = k end end
table.sort(newg)
local RESULT = jsonEncode({ prints = out.prints, export = exportText, json = jsonText, newglobals = newg,
  who = whoText, summary = summaryText, status = statusAfterExport })
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
        print(f"--- addon chat output ({variant}) ---")
        for p in result["prints"]:
            print(strip_colors(p))
        print(f"--- window ({variant}) ---")
        print(strip_colors(result["who"]))
        print(strip_colors(result["summary"]))
        print(strip_colors(result["status"]))

    data, raw = decode(result["export"])
    assert result["json"] == raw.decode("utf-8"), "/mint json differs from the string's payload"
    assert len(result["export"]) < 64 * 1024, "the website rejects strings over 64 KB"
    if VERBOSE:
        print(f"--- decoded export ({variant}) ---")
        print(json.dumps(data, indent=2, ensure_ascii=False))

    assert data["v"] == 1 and data["src"] == "self" and data["ts"] == 1790000000
    assert "kind" not in data, "a character export has no kind key"
    assert data["addon"] == {"name": "MintCommunityTools", "version": "0.1.0"}
    assert data["game"] == {"version": "1.60.1", "build": "60101", "toc": 16001}

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

    prints = [strip_colors(p) for p in result["prints"]]
    assert any("0 failed" in p for p in prints), "in-addon selftest reported failures"
    assert any(p.startswith("Mint Community Tools: v0.1.0 loaded.") for p in prints), prints[:3]
    scan_line = next(p for p in prints if "items equipped" in p and "Type /mint" in p)
    expected_name = "Théoden Stormwind" if variant == "forever" else "Théoden"
    assert scan_line.startswith(f"Mint Community Tools: {expected_name}: 6 items equipped"), scan_line
    assert not any("talents could not be read" in p for p in prints)

    expected_globals = ["MintCommunityToolsDB", "SLASH_MINTCOMMUNITYTOOLS1", "SLASH_MINTCOMMUNITYTOOLS2", "SLASH_MINTCOMMUNITYTOOLS3"]
    assert result["newglobals"] == expected_globals, f"unexpected globals: {result['newglobals']}"

    if WRITE_FIXTURES:
        FIXTURE_DIR.mkdir(exist_ok=True)
        (FIXTURE_DIR / f"character-{variant}.txt").write_text(result["export"] + "\n", encoding="utf-8")
    return len(result["export"])


def main():
    lua = find_lua()
    print(f"using {os.path.basename(lua)}")
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
