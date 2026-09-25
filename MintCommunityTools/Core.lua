--[[
    Core.lua - slash commands and addon lifecycle.

    /mint               open the Mint Community Tools window (scan, gear list, export)
    /mint export        scan your gear and put the export string in the window, ready to copy
    /mint scan          print a one-line summary of your gear to chat
    /mint json          the export as raw JSON in the window (for debugging)
    /mint debug         print client build info and which APIs exist (paste this in bug reports)
    /mint selftest      run the built-in encoder tests
    /mint help

    /mct and /gb do the same as /mint.

    Saved settings (MintCommunityToolsDB) hold only conveniences: the minimap button's position and the
    last export. The WoW Forever beta client writes saved variables but does not read them back
    (a known client bug), so nothing here depends on them surviving a logout.
]]

local ADDON, ns = ...
ns.NAME = "MintCommunityTools"
ns.VERSION = "0.1.0"

local PREFIX = "|cff7fe5a8Mint Community Tools|r: "

local function say(msg)
    print(PREFIX .. tostring(msg))
end
ns.Say = say

---------------------------------------------------------------------------
-- Scanning and exporting (shared by the window and the slash commands)
---------------------------------------------------------------------------

-- Reads the character. Returns the export table, or nil plus a reason.
function ns.Scan()
    local ok, data, reason = pcall(ns.Collect.FromUnit, "player", "self")
    if not ok then
        return nil, "could not read your character: " .. tostring(data)
    end
    if not data then
        return nil, reason or "nothing to export"
    end
    ns.lastScan = data
    return data
end

-- What an export is "of": the gear and talents, without the clock. Used to tell whether the
-- character changed since the last export.
function ns.Signature(data)
    return ns.Encode.JSON({ items = data.items, talents = data.talents or {} })
end

-- Scans and packs. Returns the text to copy (the export string, or the JSON when rawJson is
-- set), the export table, or nil plus a reason.
function ns.Export(rawJson)
    local data, reason = ns.Scan()
    if not data then return nil, nil, reason end

    local packOk, str, json = pcall(ns.Encode.Pack, data)
    if not packOk then
        return nil, nil, "could not encode the export: " .. tostring(str)
    end

    ns.lastExport = { ts = data.ts, str = str, json = json, signature = ns.Signature(data) }
    -- Kept in SavedVariables so a future companion tool could pick it up from disk.
    MintCommunityToolsDB = MintCommunityToolsDB or {}
    MintCommunityToolsDB.lastExport = { ts = data.ts, str = str }

    if data.talentsError then
        say("talents could not be read: " .. data.talentsError)
    end
    return rawJson and json or str, data
end

local function doScan()
    local data, reason = ns.Scan()
    if not data then
        say(reason)
        return
    end
    local s = ns.Collect.Summarize(data)
    local c = data.char
    say(("%s%s: %d items equipped%s, %d enchanted. Type /mint to see them and export."):format(
        tostring(c.name), c.lastName and (" " .. c.lastName) or "", s.items,
        s.averageLevel and (", average item level " .. s.averageLevel) or "", s.enchanted))
end

---------------------------------------------------------------------------
-- Debug and self test
---------------------------------------------------------------------------

local function doDebug()
    local version, build, _, toc = GetBuildInfo()
    say(("%s v%s on client %s, build %s, interface number %s"):format(
        ns.NAME, ns.VERSION, tostring(version), tostring(build), tostring(toc)))
    for _, line in ipairs(ns.Collect.Diagnostics()) do
        say("  " .. line)
    end
    local found = 0
    for _, slot in ipairs(ns.Collect.SLOTS) do
        if GetInventoryItemLink and GetInventoryItemLink("player", slot) then found = found + 1 end
    end
    say(("equipped item links found: %d"):format(found))
end

local function doSelfTest()
    local E = ns.Encode
    local passed, failed = 0, 0
    local function check(label, got, expected)
        if got == expected then
            passed = passed + 1
        else
            failed = failed + 1
            say(("FAIL %s: got [%s], expected [%s]"):format(label, tostring(got), tostring(expected)))
        end
    end

    -- RFC 4648 base64 test vectors
    local b64 = { [""] = "", f = "Zg==", fo = "Zm8=", foo = "Zm9v", foob = "Zm9vYg==", fooba = "Zm9vYmE=", foobar = "Zm9vYmFy" }
    for plain, encoded in pairs(b64) do
        check("base64 encode '" .. plain .. "'", E.Base64Encode(plain), encoded)
        check("base64 decode '" .. encoded .. "'", E.Base64Decode(encoded), plain)
    end

    -- Adler-32 reference value from the zlib RFC / Wikipedia
    check("adler32 Wikipedia", E.Adler32("Wikipedia"), "11e60398")

    -- JSON: sorted keys, arrays, escaping, UTF-8 pass-through
    check("json object", E.JSON({ a = 1, b = { 1, 2, 3 }, c = 'x"y', d = true }), '{"a":1,"b":[1,2,3],"c":"x\\"y","d":true}')
    check("json empty list", E.JSON({}), "[]")
    check("json utf8 + newline", E.JSON("\195\169\n"), '"\195\169\\n"')
    check("json control char", E.JSON("\1"), '"\\u0001"')
    check("json float", E.JSON({ dps = 56.5 }), '{"dps":56.5}')

    -- Full round trip through Pack / Unpack
    local packed, json = E.Pack({ v = 1, name = "T\195\169st", list = { 1, 2 } })
    check("unpack roundtrip", E.Unpack(packed), json)
    local tampered = packed:sub(1, 12) .. (packed:sub(13, 13) == "A" and "B" or "A") .. packed:sub(14)
    check("tamper detected", E.Unpack(tampered) == nil, true)

    say(("self test: %d passed, %d failed"):format(passed, failed))
end

---------------------------------------------------------------------------
-- Slash command and lifecycle
---------------------------------------------------------------------------

SLASH_MINTCOMMUNITYTOOLS1 = "/mint"
SLASH_MINTCOMMUNITYTOOLS2 = "/mct"
SLASH_MINTCOMMUNITYTOOLS3 = "/gb"
SlashCmdList["MINTCOMMUNITYTOOLS"] = function(msg)
    local cmd = (msg or ""):lower():match("^%s*(%S*)") or ""
    if cmd == "" then
        ns.UI.Toggle()
    elseif cmd == "export" then
        ns.UI.Export(false)
    elseif cmd == "json" then
        ns.UI.Export(true)
    elseif cmd == "scan" then
        doScan()
    elseif cmd == "debug" then
        doDebug()
    elseif cmd == "selftest" then
        doSelfTest()
    else
        say("commands: /mint (open the window), /mint export, /mint scan, /mint json, /mint debug, /mint selftest")
    end
end

-- Equipment events differ between client generations; register whichever this one has.
-- Registering an event the client does not know raises an error, hence the pcall.
local GEAR_EVENTS = { "PLAYER_EQUIPMENT_CHANGED", "UNIT_INVENTORY_CHANGED", "CHARACTER_POINTS_CHANGED" }

local events = CreateFrame("Frame")
events:RegisterEvent("ADDON_LOADED")
events:SetScript("OnEvent", function(self, event, ...)
    if event == "ADDON_LOADED" then
        if (...) ~= ADDON then return end
        MintCommunityToolsDB = MintCommunityToolsDB or {}
        self:UnregisterEvent("ADDON_LOADED")
        for _, name in ipairs(GEAR_EVENTS) do
            pcall(self.RegisterEvent, self, name)
        end
        pcall(ns.UI.CreateMinimapButton)
        say("v" .. ns.VERSION .. " loaded. Type /mint or click the minimap button to export your gear for the website.")
    elseif event == "UNIT_INVENTORY_CHANGED" then
        if (...) == "player" then ns.UI.OnGearChanged() end
    else
        ns.UI.OnGearChanged()
    end
end)
