--[[
    Collect.lua - reads a unit's character info, equipped gear, and talents into a plain table.

    The table is what docs/export-string-format-v1.md describes; Encode.lua turns it into the
    string. Everything here is feature-detected, because the WoW Forever client is a beta and
    its exact API surface (Classic Era style vs. Mainline style) is not confirmed. Anything that
    is missing is left out of the result rather than raising an error, and Collect.Diagnostics()
    reports what was available for bug reports.

    FromUnit takes a unit token so a later version can reuse it for inspecting other players
    (unit = "target" / "raid5" after INSPECT_READY). v1 only calls it with "player".
]]

local ADDON, ns = ...
local Collect = {}
ns.Collect = Collect

local floor, sfind, ssub, sgsub, smatch = math.floor, string.find, string.sub, string.gsub, string.match
local tonumber, tostring, pcall, type, ipairs, pairs = tonumber, tostring, pcall, type, ipairs, pairs

-- Inventory slot ids. Empty slots are simply absent from the export.
local SLOTS = { 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19 }
Collect.SLOTS = SLOTS

Collect.SLOT_NAMES = {
    [1] = "Head", [2] = "Neck", [3] = "Shoulder", [4] = "Shirt", [5] = "Chest", [6] = "Waist",
    [7] = "Legs", [8] = "Feet", [9] = "Wrist", [10] = "Hands", [11] = "Ring 1", [12] = "Ring 2",
    [13] = "Trinket 1", [14] = "Trinket 2", [15] = "Back", [16] = "Main Hand", [17] = "Off Hand",
    [18] = "Ranged", [19] = "Tabard",
}
-- Slots that say nothing about how well geared a character is.
Collect.COSMETIC_SLOTS = { [4] = true, [19] = true }

local REGIONS = { "US", "KR", "EU", "TW", "CN" }
local REGION_SET = { US = true, KR = true, EU = true, TW = true, CN = true }
Collect.REGION_SET = REGION_SET
-- Used only when no source below answers at all.
Collect.DEFAULT_REGION = "US"
-- Portal values that name a test client rather than a region. Blizzard's beta and PTR
-- realms are hosted in the US, so a beta client is a US client.
local TEST_PORTALS = { beta = true, test = true, ptr = true }

---------------------------------------------------------------------------
-- Region
---------------------------------------------------------------------------

-- Which region this character is on. The website needs it (it is part of a character's
-- identity), and the beta client does not answer GetCurrentRegion like other clients do, so
-- several sources are tried in turn. Returns region, source; nil when nothing answered.
local function detectRegion(override)
    if type(override) == "string" and REGION_SET[override:upper()] then
        return override:upper(), "set with /mint region"
    end
    if GetCurrentRegion then
        local ok, r = pcall(GetCurrentRegion)
        if ok and REGIONS[r] then return REGIONS[r], "GetCurrentRegion" end
    end
    if GetCurrentRegionName then
        local ok, r = pcall(GetCurrentRegionName)
        if ok and type(r) == "string" and REGION_SET[r:upper()] then return r:upper(), "GetCurrentRegionName" end
    end
    local portal = Collect.Portal()
    if portal then
        if REGION_SET[portal:upper()] then return portal:upper(), "portal cvar" end
        if TEST_PORTALS[portal:lower()] then return "US", "beta client" end
    end
    return nil
end
Collect.DetectRegion = detectRegion

-- The client's portal cvar ("us", "eu", "beta", ...), or nil. Exported as game.portal so the
-- website can tell a beta export from a live one.
function Collect.Portal()
    if not GetCVar then return nil end
    local ok, portal = pcall(GetCVar, "portal")
    if ok and type(portal) == "string" and portal ~= "" then return portal end
    return nil
end

---------------------------------------------------------------------------
-- Names
---------------------------------------------------------------------------

-- "Mock Realm", "Mock-Realm" and "MockRealm" compare equal.
local function squash(s)
    return (sgsub(tostring(s or ""):lower(), "[%s%-']", ""))
end

local function trim(s)
    return (sgsub(sgsub(tostring(s or ""), "^%s+", ""), "%s+$", ""))
end

-- WoW Forever characters have a first and a last name. The client returns the first name from
-- UnitName with the last name as its second value (where other clients put the realm), and
-- has also been seen returning "First Last" as one string. A second value that is this realm's
-- name is the realm, not a last name.
-- Is this string the name of the realm the player is on? (What other clients put where WoW
-- Forever puts a last name.)
local function isRealm(s)
    if type(s) ~= "string" then return false end
    local key = squash(s)
    if key == "" then return false end
    local realm = GetRealmName and GetRealmName() or nil
    if type(realm) == "string" and squash(realm) == key then return true end
    if GetNormalizedRealmName then
        local ok, r = pcall(GetNormalizedRealmName)
        if ok and type(r) == "string" and squash(r) == key then return true end
    end
    return false
end
Collect.IsRealm = isRealm

-- Returns firstName, lastName (or nil), realm (or nil).
local function splitName(unit)
    local name, second = UnitName(unit)
    if type(name) ~= "string" or name == "" then return nil end
    name = trim(name)
    local realm = GetRealmName and GetRealmName() or nil
    local realmKeys = {}
    if type(realm) == "string" and realm ~= "" then realmKeys[squash(realm)] = true end
    if GetNormalizedRealmName then
        local ok, r = pcall(GetNormalizedRealmName)
        if ok and type(r) == "string" and r ~= "" then realmKeys[squash(r)] = true end
    end

    local lastName
    if type(second) == "string" and trim(second) ~= "" then
        second = trim(second)
        if realmKeys[squash(second)] then
            realm = realm or second
        else
            lastName = second
        end
    end
    if not lastName then
        local first, last = smatch(name, "^(.-)%s+(%S+)$")
        if first and first ~= "" then
            name, lastName = first, last
        end
    end
    return name, lastName, realm
end
Collect.SplitName = splitName

---------------------------------------------------------------------------
-- Item link parsing
---------------------------------------------------------------------------

-- Splits on ":" keeping empty fields ("a::b" -> {"a", "", "b"}).
local function splitColon(s)
    local t, pos = {}, 1
    while true do
        local i = sfind(s, ":", pos, true)
        if not i then
            t[#t + 1] = ssub(s, pos)
            break
        end
        t[#t + 1] = ssub(s, pos, i - 1)
        pos = i + 1
    end
    return t
end

-- |Hitem:itemID:enchantID:gem1:gem2:gem3:gem4:suffixID:...|h[Name]|h
-- Returns itemID, enchantID, gems (list of non-zero gem ids), suffixID, name
local function parseItemLink(link)
    local payload = smatch(link, "|Hitem:([^|]+)|h")
    if not payload then return nil end
    local f = splitColon(payload)
    local id = tonumber(f[1])
    if not id then return nil end
    local gems = {}
    for i = 3, 6 do
        local g = tonumber(f[i])
        if g and g ~= 0 then gems[#gems + 1] = g end
    end
    return id, tonumber(f[2]), gems, tonumber(f[7]), smatch(link, "|h%[(.-)%]|h")
end
Collect.ParseItemLink = parseItemLink

-- Effective item level when the client can tell us; nil otherwise.
local function itemLevel(link)
    local detailed = (C_Item and C_Item.GetDetailedItemLevelInfo) or GetDetailedItemLevelInfo
    if detailed then
        local ok, effective = pcall(detailed, link)
        if ok and type(effective) == "number" and effective > 0 then
            return floor(effective)
        end
    end
    local getInfo = (C_Item and C_Item.GetItemInfo) or GetItemInfo
    if getInfo then
        local ok, _, _, _, ilvl = pcall(getInfo, link)
        if ok and type(ilvl) == "number" and ilvl > 0 then
            return floor(ilvl)
        end
    end
    return nil
end

-- The item's stat block as the client reports it ({ ITEM_MOD_STAMINA_SHORT = 13, ... }), so
-- the website never needs an item database to know what an item does. nil when the client has
-- no such API or reports nothing for this item.
local function itemStats(link)
    local getStats = (C_Item and C_Item.GetItemStats) or GetItemStats
    if not getStats then return nil end
    local ok, stats = pcall(getStats, link)
    if not ok or type(stats) ~= "table" then return nil end
    local out, any = {}, false
    for k, v in pairs(stats) do
        if type(k) == "string" and type(v) == "number" and v ~= 0 then
            out[k] = v
            any = true
        end
    end
    return any and out or nil
end

---------------------------------------------------------------------------
-- Sections
---------------------------------------------------------------------------

local function collectCharacter(unit)
    local name, lastName, realm = splitName(unit)
    local className, classFile = UnitClass(unit)
    local raceName, raceFile = UnitRace(unit)
    local guildName, guildRank = nil, nil
    if GetGuildInfo then
        local ok, g, r = pcall(GetGuildInfo, unit)
        if ok then guildName, guildRank = g, r end
    end
    local region, regionSource = detectRegion(ns.RegionOverride and ns.RegionOverride())
    if not region then
        region, regionSource = Collect.DEFAULT_REGION, "assumed"
    end
    Collect.regionSource = regionSource   -- shown in the window; not part of the export
    local realmSlug
    if GetNormalizedRealmName then
        local ok, r = pcall(GetNormalizedRealmName)
        if ok and type(r) == "string" and r ~= "" then realmSlug = r end
    end

    return {
        name      = name,
        lastName  = lastName,
        realm     = realm,
        realmSlug = realmSlug,
        region    = region,
        class     = className,
        classFile = classFile,
        race      = raceName,
        raceFile  = raceFile,
        sex       = UnitSex and UnitSex(unit) or nil, -- 2 = male, 3 = female
        level     = UnitLevel(unit),
        faction   = UnitFactionGroup and (UnitFactionGroup(unit)) or nil,
        guild     = guildName,
        guildRank = guildRank,
    }
end

local function collectItems(unit)
    local items = {}
    if not GetInventoryItemLink then return items end

    for _, slot in ipairs(SLOTS) do
        local link = GetInventoryItemLink(unit, slot)
        if link then
            local id, enchant, gems, suffix, name = parseItemLink(link)
            if id then
                local item = { slot = slot, id = id, name = name }
                local quality = GetInventoryItemQuality and GetInventoryItemQuality(unit, slot)
                if quality then item.quality = quality end
                -- Icon exactly as the client reports it: a FileDataID number on modern
                -- clients, or a texture path string on older ones.
                local icon = GetInventoryItemTexture and GetInventoryItemTexture(unit, slot)
                if icon then item.icon = icon end
                local ilvl = itemLevel(link)
                if ilvl then item.ilvl = ilvl end
                if enchant and enchant ~= 0 then item.enchant = enchant end
                if gems and #gems > 0 then item.gems = gems end
                if suffix and suffix ~= 0 then item.suffix = suffix end
                local stats = itemStats(link)
                if stats then item.stats = stats end
                items[#items + 1] = item
            end
        end
    end
    return items
end

-- Classic-style talent trees: one entry per tree with name, points spent, and a digit string
-- of ranks in the client's own talent order (one character per talent, capped at 9).
-- Returns nil when this client has no Classic-style talent API.
local function collectTalents()
    if not (GetNumTalentTabs and GetTalentTabInfo and GetNumTalents and GetTalentInfo) then
        return nil
    end
    local tabs = {}
    for t = 1, GetNumTalentTabs() do
        local a, b, c, d, e = GetTalentTabInfo(t)
        local name, points
        if type(a) == "number" then
            name, points = b, e   -- newer clients return the tab id first
        else
            name, points = a, c   -- Classic Era: name, icon, pointsSpent, background
        end
        local ranks = {}
        for i = 1, GetNumTalents(t) do
            local _, _, _, _, rank = GetTalentInfo(t, i)
            rank = tonumber(rank) or 0
            if rank > 9 then rank = 9 end
            ranks[#ranks + 1] = tostring(rank)
        end
        tabs[#tabs + 1] = { name = name, points = tonumber(points) or 0, ranks = table.concat(ranks) }
    end
    if #tabs == 0 then return nil end
    return tabs
end

---------------------------------------------------------------------------
-- Public API
---------------------------------------------------------------------------

-- Returns the export table, or nil plus a reason.
function Collect.FromUnit(unit, source)
    unit = unit or "player"
    if not UnitExists(unit) then
        return nil, "unit '" .. tostring(unit) .. "' does not exist"
    end

    local gameVersion, gameBuild, _, toc
    if GetBuildInfo then
        gameVersion, gameBuild, _, toc = GetBuildInfo()
    end

    local data = {
        v     = 1,
        src   = source or "self",
        ts    = time(),
        addon = { name = ns.NAME, version = ns.VERSION },
        game  = { version = gameVersion, build = gameBuild, toc = toc, portal = Collect.Portal() },
        char  = collectCharacter(unit),
        items = collectItems(unit),
    }

    -- Talent info is only read for yourself in v1; inspected units need isInspect variants.
    if unit == "player" then
        local ok, talents = pcall(collectTalents)
        if ok then
            data.talents = talents
        else
            data.talentsError = tostring(talents)
        end
    end

    return data
end

-- Numbers the window shows about a scan: how many items, the average item level (cosmetic
-- slots left out), and how many are enchanted.
---------------------------------------------------------------------------
-- The dungeons export (docs/class-data-format-v1.md, kind "dungeons")
---------------------------------------------------------------------------

-- The group finder's list of instances with their level bands. The website lists every
-- dungeon and raid from the client's own files, but the table with the level bands is not
-- in them; the finder has them. GetLFGDungeonInfo(id) answers for a sparse set of ids, so
-- every id up to DUNGEON_IDS_MOST is asked (the WoW Forever instances sit near 3270 today).
Collect.DUNGEON_IDS_MOST = 5000
-- The finder's typeID: 1 dungeon and 2 raid on the retail client. The WoW Forever client
-- (seen with /mint uidump finder on build 70338) answers 0 for every dungeon AND raid, 4 for
-- a zone and 5 for a battleground, gives no player count, and one level per instance (its
-- minimum, maximum and recommended levels are the same number, the level to enter at).
-- A 0 goes out as "dungeon": the website tells raids from dungeons by its own places.
local DUNGEON_TYPES = { [0] = "dungeon", [1] = "dungeon", [2] = "raid" }

local function plainNumber(v)
    if type(v) ~= "number" then return nil end
    if issecretvalue and issecretvalue(v) then return nil end
    return v
end

-- Every instance the finder knows: { id, name, type, minLevel, maxLevel, recLevel?, players? }.
-- Empty when this client has no finder list.
function Collect.Dungeons()
    local out = {}
    if type(GetLFGDungeonInfo) ~= "function" then return out end
    for id = 1, Collect.DUNGEON_IDS_MOST do
        -- name, typeID, subtypeID, minLevel, maxLevel, recLevel, minRecLevel, maxRecLevel,
        -- expansionLevel, groupID, textureFilename, difficulty, maxPlayers, ...
        local ok, name, typeID, _, minLevel, maxLevel, recLevel, _, _, _, _, _, _, maxPlayers = pcall(GetLFGDungeonInfo, id)
        if ok and type(name) == "string" and name ~= "" then
            local low, high = plainNumber(minLevel), plainNumber(maxLevel)
            if low and high and low >= 1 and high <= 100 and low <= high then
                local entry = { id = id, name = name, type = DUNGEON_TYPES[plainNumber(typeID) or 0] or "other", minLevel = low, maxLevel = high }
                local rec, players = plainNumber(recLevel), plainNumber(maxPlayers)
                if rec and rec > 0 then entry.recLevel = rec end
                if players and players > 0 then entry.players = players end
                out[#out + 1] = entry
            end
        end
    end
    return out
end

-- The export string, and how many instances it holds; or nil and the reason there is none.
function Collect.DungeonsExport()
    local list = Collect.Dungeons()
    if #list == 0 then
        if type(GetLFGDungeonInfo) ~= "function" then return nil, "this client has no group finder list to read the level bands from." end
        return nil, "the group finder lists no instances on this client: nothing to export."
    end
    local gameVersion, gameBuild
    if GetBuildInfo then gameVersion, gameBuild = GetBuildInfo() end
    local c = collectCharacter("player")
    local data = {
        v = 1, kind = "dungeons", ts = time(),
        locale = GetLocale and GetLocale() or nil,
        addon = { name = ns.NAME, version = ns.VERSION },
        game = { version = gameVersion, build = gameBuild },
        character = { classFile = c.classFile, class = c.class, raceFile = c.raceFile, race = c.race, faction = c.faction, level = c.level },
        dungeons = list,
    }
    return ns.Encode.Pack(data), #list
end

function Collect.Summarize(data)
    local count, enchanted, levelSum, levelCount = 0, 0, 0, 0
    for _, item in ipairs(data.items) do
        count = count + 1
        if item.enchant then enchanted = enchanted + 1 end
        if item.ilvl and not Collect.COSMETIC_SLOTS[item.slot] then
            levelSum = levelSum + item.ilvl
            levelCount = levelCount + 1
        end
    end
    return {
        items = count,
        enchanted = enchanted,
        averageLevel = levelCount > 0 and floor(levelSum / levelCount + 0.5) or nil,
    }
end

-- Human-readable list of which APIs this client has, for /mint debug bug reports.
function Collect.Diagnostics()
    local names = {
        "GetInventoryItemLink", "GetInventoryItemQuality", "GetInventoryItemTexture",
        "GetItemInfo", "GetItemStats", "GetDetailedItemLevelInfo", "NotifyInspect",
        "GetNumTalentTabs", "GetTalentTabInfo", "GetTalentInfo", "GetCurrentRegion", "GetCurrentRegionName", "GetCVar",
        "GetNormalizedRealmName", "GetRealmName", "GetGuildInfo", "UnitSex",
    }
    local lines = {}
    for _, n in ipairs(names) do
        lines[#lines + 1] = n .. ": " .. (_G[n] ~= nil and "yes" or "NO")
    end
    lines[#lines + 1] = "C_Item: " .. (C_Item ~= nil and "yes" or "NO")
    lines[#lines + 1] = "C_Timer: " .. (C_Timer ~= nil and "yes" or "NO")
    lines[#lines + 1] = "C_ClassTalents: " .. (C_ClassTalents ~= nil and "yes" or "NO")
    local first, last, realm = splitName("player")
    local a, b = UnitName("player")
    lines[#lines + 1] = ("UnitName: [%s] [%s] -> first [%s] last [%s] realm [%s]"):format(
        tostring(a), tostring(b), tostring(first), tostring(last), tostring(realm))
    local function try(fn, ...)
        if not fn then return "absent" end
        local ok, v = pcall(fn, ...)
        return ok and tostring(v) or ("error: " .. tostring(v))
    end
    lines[#lines + 1] = ("region sources: GetCurrentRegion [%s], GetCurrentRegionName [%s], portal cvar [%s], realmList cvar [%s]"):format(
        try(GetCurrentRegion), try(GetCurrentRegionName), try(GetCVar, "portal"), try(GetCVar, "realmList"))
    local region, source = detectRegion(ns.RegionOverride and ns.RegionOverride())
    lines[#lines + 1] = ("region used: %s (%s)"):format(region or Collect.DEFAULT_REGION, source or "assumed")
    return lines
end
