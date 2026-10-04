--[[
    Core.lua - saved settings, slash commands and addon lifecycle.

    /mint                    open the Mint Community Tools window
    /mint export             scan your gear and put the export string in the window, ready to copy
    /mint scan               print a one-line summary of your gear to chat
    /mint loot               open the window on the Loot tab
    /mint watch              show or hide the loot watcher
    /mint items [all]        export the items seen for the website: what is new, or all of them
    /mint minimap [show | hide | reset]   the minimap button
    /mint minimap round | square | auto   the shape of the minimap the button sits around
    /mint ui [on | off | reset]   the minimalist UI overhaul (Settings tab); reset puts every frame back
    /mint edit               edit mode: drag the overhaul's frames where you want them
    /mint uidump [menus | bags]   record what this client's own interface is made of (for bug
                             reports); "menus" records the game menu and the windows it opens
                             instead, "bags" the bag windows (have them open)
    /mint region XX          set your region (US, EU, KR, TW, CN) if the client cannot tell the addon
    /mint json               the gear export as raw JSON in the window (for debugging)
    /mint debug              print client build info and which APIs exist (paste this in bug reports)
    /mint selftest           run the built-in encoder tests
    /mint help

    /mct and /gb do the same as /mint.

    MintCommunityToolsDB (account wide):
        minimap      { shown, angle, shape } for the minimap button; shape is auto, round or square
        loot         { log = the last 500 drops, minQuality = the filter, watch = is the loot
                       watcher shown, watchAt = where it was left }
        items        [item ID] = the item as the website's item database takes it, plus
                     seen/first/last and sent (what was last exported of it)
        region       set with /mint region
        lastExport   { ts, str } of the last gear export

    The WoW Forever beta client writes saved variables but does not read them back (a known
    client bug). Saved.lua (see the .toc) works around it: when it is a link to the saved file
    (link-saved-settings.sh, LinkSavedSettings.cmd), the last save is loaded as code. Nothing
    depends on it: without it every session starts empty and works.
]]

local ADDON, ns = ...
ns.NAME = "MintCommunityTools"
ns.VERSION = "0.5.2"

-- True when Saved.lua has already put the last save in place. The client's own loading,
-- when it works, happens later, at ADDON_LOADED.
ns.restoredFromLink = MintCommunityToolsDB ~= nil

local PREFIX = "|cff7fe5a8Mint Community Tools|r: "

local function say(msg)
    print(PREFIX .. tostring(msg))
end
ns.Say = say

---------------------------------------------------------------------------
-- Saved settings
---------------------------------------------------------------------------

function ns.LoadDB()
    MintCommunityToolsDB = type(MintCommunityToolsDB) == "table" and MintCommunityToolsDB or {}
    local db = MintCommunityToolsDB
    if type(db.minimap) ~= "table" then db.minimap = {} end
    if db.minimap.shown == nil then db.minimap.shown = true end
    if db.minimap.shape ~= "round" and db.minimap.shape ~= "square" then db.minimap.shape = "auto" end
    -- an older version kept the angle at the top level
    if db.minimapAngle and not db.minimap.angle then db.minimap.angle = db.minimapAngle end
    db.minimapAngle = nil
    if type(db.loot) ~= "table" then db.loot = {} end
    if type(db.loot.log) ~= "table" then db.loot.log = {} end
    if type(db.loot.minQuality) ~= "number" then db.loot.minQuality = 2 end
    if db.loot.watch == nil then db.loot.watch = false end
    if type(db.items) ~= "table" then db.items = {} end
    ns.db = db
    if ns.Overhaul then ns.Overhaul.Settings() end
    return db
end

-- The settings, loading them on first use.
function ns.DB()
    return ns.db or ns.LoadDB()
end

-- If the game hands the saved table over after the addon has already started fresh, the global
-- stops being the table the addon works on. This adopts the saved one and carries what the
-- fresh session has gathered into it, so nothing seen since login is lost.
function ns.AdoptLateDB()
    local fresh, saved = ns.db, MintCommunityToolsDB
    if not fresh or type(saved) ~= "table" or saved == fresh then return false end
    ns.db = nil
    local db = ns.LoadDB()
    for _, e in ipairs(fresh.loot.log) do db.loot.log[#db.loot.log + 1] = e end
    for id, o in pairs(fresh.items) do
        if type(db.items[id]) ~= "table" then db.items[id] = o end
    end
    if fresh.region then db.region = fresh.region end
    if fresh.lastExport then db.lastExport = fresh.lastExport end
    ns.Loot.Trim()
    ns.LootUI.Refresh()
    return true
end

---------------------------------------------------------------------------
-- Region override
---------------------------------------------------------------------------

function ns.RegionOverride()
    local region = ns.DB().region
    return ns.Collect.REGION_SET[region or ""] and region or nil
end

local function doRegion(arg)
    arg = (arg or ""):upper()
    if arg == "" then
        local region, source = ns.Collect.DetectRegion(ns.RegionOverride())
        say(("region: %s (%s). To set it: /mint region US, EU, KR, TW or CN."):format(
            region or ns.Collect.DEFAULT_REGION, source or "assumed, nothing answered"))
    elseif ns.Collect.REGION_SET[arg] then
        ns.DB().region = arg
        say("region set to " .. arg .. ". Export again.")
        ns.UI.OnGearChanged()
    else
        say("unknown region " .. arg .. ". Use US, EU, KR, TW or CN.")
    end
end

---------------------------------------------------------------------------
-- Scanning and exporting gear (shared by the window and the slash commands)
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
    -- Kept in the saved variables so a companion tool can pick it up from disk.
    ns.DB().lastExport = { ts = data.ts, str = str }

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
-- Minimap command
---------------------------------------------------------------------------

local function doMinimap(action)
    if action == "reset" then
        ns.ResetMinimap()
        say("minimap button back at its default place.")
        return
    end
    if action == "auto" or action == "round" or action == "square" then
        ns.SetMinimapShape(action)
        if action == "auto" then
            say(("minimap button follows the minimap's shape (%s right now)."):format(ns.MinimapShape()))
        else
            say(("minimap button sits around a %s minimap. /mint minimap auto follows the minimap's shape."):format(action))
        end
        return
    end
    local show = (action == "show") or (action ~= "hide" and not ns.DB().minimap.shown)
    ns.SetMinimapShown(show)
    say("minimap button " .. (show and "shown. Drag it around the minimap to move it." or "hidden. /mint minimap shows it again."))
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
    local lootApis = { "GetNumLootItems", "GetLootSlotLink", "GetLootSlotInfo", "GetLootSourceInfo", "ChatEdit_InsertLink", "GetServerTime" }
    local have = {}
    for _, n in ipairs(lootApis) do have[#have + 1] = n .. ": " .. (_G[n] ~= nil and "yes" or "NO") end
    say("  loot: " .. table.concat(have, ", "))
    local drops, items = ns.Loot.Counts()
    say(("loot log: %d drops, %d items seen; saved data %s"):format(drops, items,
        ns.restoredFromLink and "restored from the linked save file" or (ns.loadedFromDisk and "loaded by the client" or "not loaded (started empty)")))
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

    -- Loot lines
    local who, link, count = ns.Loot.ParseLootMessage("Bravo Testa receives loot: |cffa335ee|Hitem:16800:0:0:0:0:0:0:0:60|h[Arcanist Boots]|h|rx3.")
    if not LOOT_ITEM_MULTIPLE then   -- only meaningful against the English fallback
        check("loot line: who", who, "Bravo Testa")
        check("loot line: count", count, 3)
        check("loot line: link", link and link:match("|h%[(.-)%]|h"), "Arcanist Boots")
    end

    say(("self test: %d passed, %d failed"):format(passed, failed))
end

---------------------------------------------------------------------------
-- Slash command
---------------------------------------------------------------------------

SLASH_MINTCOMMUNITYTOOLS1 = "/mint"
SLASH_MINTCOMMUNITYTOOLS2 = "/mct"
SLASH_MINTCOMMUNITYTOOLS3 = "/gb"
SlashCmdList["MINTCOMMUNITYTOOLS"] = function(msg)
    local cmd, arg = (msg or ""):lower():match("^%s*(%S*)%s*(%S*)")
    cmd = cmd or ""
    if cmd == "" then
        ns.UI.Toggle()
    elseif cmd == "export" then
        ns.UI.Export(false)
    elseif cmd == "json" then
        ns.UI.Export(true)
    elseif cmd == "scan" then
        doScan()
    elseif cmd == "loot" then
        ns.UI.Show("loot")
    elseif cmd == "gear" then
        ns.UI.Show("gear")
    elseif cmd == "watch" then
        ns.LootUI.ToggleWatch()
    elseif cmd == "items" then
        ns.LootUI.ExportItems(arg == "all")
    elseif cmd == "minimap" then
        doMinimap(arg)
    elseif cmd == "ui" then
        ns.Overhaul.Command(arg)
    elseif cmd == "edit" then
        ns.Overhaul.ToggleEdit()
    elseif cmd == "uidump" then
        ns.Dump.Run(arg)
    elseif cmd == "region" then
        doRegion(arg)
    elseif cmd == "debug" then
        doDebug()
    elseif cmd == "selftest" then
        doSelfTest()
    else
        say("commands: /mint (open the window), /mint export, /mint scan, /mint loot, /mint watch, /mint items, "
            .. "/mint ui on|off, /mint edit, /mint minimap, /mint region, /mint json, /mint debug, /mint selftest")
    end
end

---------------------------------------------------------------------------
-- Lifecycle
---------------------------------------------------------------------------

-- Events differ between client generations; register whichever this one has. Registering an
-- event the client does not know raises an error, hence the pcall.
local GEAR_EVENTS = { "PLAYER_EQUIPMENT_CHANGED", "UNIT_INVENTORY_CHANGED", "CHARACTER_POINTS_CHANGED" }
local LOOT_EVENT = {}
for _, name in ipairs(ns.Loot.EVENTS) do LOOT_EVENT[name] = true end

local function isTestClient()
    local portal = ns.Collect.Portal()
    portal = portal and portal:lower()
    return portal == "beta" or portal == "test" or portal == "ptr"
end

local function announce()
    local drops, items = ns.Loot.Counts()
    if ns.loadedFromDisk then
        say(("v%s loaded, saved data %s (%d drops in the loot log, %d items seen). Type /mint or click the minimap button."):format(
            ns.VERSION, ns.restoredFromLink and "restored from the linked save file" or "loaded", drops, items))
    else
        say("v" .. ns.VERSION .. " loaded. Type /mint or click the minimap button.")
        if isTestClient() then
            say("The beta client does not load addon data by itself, so the loot log starts empty each session. "
                .. "One-time fix: run link-saved-settings.sh (Mac) or LinkSavedSettings.cmd (Windows) from the addon's folder; see the README.")
        end
    end
end

local events = CreateFrame("Frame")
events:RegisterEvent("ADDON_LOADED")
events:SetScript("OnEvent", function(self, event, ...)
    if event == "ADDON_LOADED" then
        if (...) ~= ADDON then return end
        self:UnregisterEvent("ADDON_LOADED")
        ns.loadedFromDisk = type(MintCommunityToolsDB) == "table"
        ns.LoadDB()
        ns.Loot.onChange = ns.LootUI.Refresh
        pcall(self.RegisterEvent, self, "PLAYER_LOGIN")
        pcall(self.RegisterEvent, self, "PLAYER_ENTERING_WORLD")
        pcall(self.RegisterEvent, self, "PLAYER_REGEN_ENABLED")
        for _, name in ipairs(GEAR_EVENTS) do pcall(self.RegisterEvent, self, name) end
        for _, name in ipairs(ns.Loot.EVENTS) do pcall(self.RegisterEvent, self, name) end
    elseif event == "PLAYER_LOGIN" then
        pcall(ns.Overhaul.Apply)
        pcall(ns.InitMinimap)
        pcall(ns.LootUI.InitWatch)
        announce()
    elseif event == "PLAYER_ENTERING_WORLD" then
        if ns.AdoptLateDB() then
            ns.loadedFromDisk = true
            pcall(ns.Overhaul.Apply)
            pcall(ns.InitMinimap)
            pcall(ns.LootUI.InitWatch)
            say("the game handed over the saved data late; adopted it.")
        end
        pcall(ns.Overhaul.OnEnteringWorld)
    elseif event == "PLAYER_REGEN_ENABLED" then
        pcall(ns.Overhaul.OnCombatEnd)
    elseif LOOT_EVENT[event] then
        ns.Loot.OnEvent(event, ...)
    elseif event == "UNIT_INVENTORY_CHANGED" then
        if (...) == "player" then ns.UI.OnGearChanged() end
    else
        ns.UI.OnGearChanged()
    end
end)
