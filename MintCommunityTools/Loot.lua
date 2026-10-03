--[[
    Loot.lua - the loot tracker: what dropped, who got it, and what each item is.

    Two things are kept, both in the saved variables (MintCommunityToolsDB):

      loot.log   the last 500 drops, oldest first: when, the item's link, how many, who
                 received it. This is what the Loot tab and the loot watcher show.
      items      one record per item ID ever seen, in the shape the website's item database
                 takes ({ id, name, quality, itemLevel, itemClass, itemSubclass, equipLoc,
                 icon, stats }), plus what was last exported of it. "Export new items" on
                 the Loot tab turns what is new or changed into strings to paste on the
                 website (docs/item-export-format-v1.md), a hundred items to a string.

    Items are seen two ways: in the loot window (what dropped, whether or not anyone takes
    it) and in the loot lines of chat (who received what, for you and everyone in your group).
    A drop seen in the window and then handed out is one entry, not two.

    Everything is feature-detected: the WoW Forever client is a beta, and a missing function
    must cost a detail, never the tracker. This file has no UI; Loot.onChange is called when
    something changes.
]]

local ADDON, ns = ...
local Loot = {}
ns.Loot = Loot

local floor = math.floor
local pairs, ipairs, type, tostring, tonumber, pcall = pairs, ipairs, type, tostring, tonumber, pcall
local sgsub, smatch, sfind = string.gsub, string.match, string.find

Loot.MAX_LOG = 500
-- A drop seen in the loot window waits this long for a loot line saying who received it.
Loot.PENDING_SECONDS = 900
Loot.EVENTS = { "CHAT_MSG_LOOT", "LOOT_OPENED", "LOOT_READY", "GET_ITEM_INFO_RECEIVED" }
-- What the website's item database reads from an item; anything else is left out of an export.
Loot.OBSERVATION_KEYS = { "id", "name", "quality", "itemLevel", "itemClass", "itemSubclass", "equipLoc", "icon", "stats" }
-- Items per export string. The game's text box is slow to select and copy long before the
-- website would mind the size: a hundred items is about 40 KB.
Loot.EXPORT_CHUNK = 100

local QUALITY_BY_COLOR = {
    ["9d9d9d"] = 0, ["ffffff"] = 1, ["1eff00"] = 2, ["0070dd"] = 3, ["a335ee"] = 4, ["ff8000"] = 5,
}

---------------------------------------------------------------------------
-- Small helpers
---------------------------------------------------------------------------

local function now()
    if GetServerTime then
        local ok, t = pcall(GetServerTime)
        if ok and type(t) == "number" then return t end
    end
    return time()
end

local function notify()
    if Loot.onChange then pcall(Loot.onChange) end
end

local function playerName()
    local first, last = ns.Collect.SplitName("player")
    if not first then return nil end
    return last and (first .. " " .. last) or first
end

local function zone()
    if not GetRealZoneText then return nil end
    local ok, z = pcall(GetRealZoneText)
    return ok and type(z) == "string" and z ~= "" and z or nil
end

---------------------------------------------------------------------------
-- Items
---------------------------------------------------------------------------

-- Everything the client will tell us about an item link.
function Loot.Describe(link)
    if type(link) ~= "string" then return nil end
    local id, enchant, _, suffix, name = ns.Collect.ParseItemLink(link)
    if not id then return nil end
    local item = { id = id, name = name, link = link }
    if enchant and enchant ~= 0 then item.enchant = enchant end
    if suffix and suffix ~= 0 then item.suffix = suffix end

    local getInfo = (C_Item and C_Item.GetItemInfo) or GetItemInfo
    local infoQuality
    if getInfo then
        local ok, infoName, _, quality, ilvl, _, itemType, itemSubType, _, equipLoc, texture = pcall(getInfo, link)
        if ok and infoName then
            infoQuality = quality
            if not item.name or item.name == "" then item.name = infoName end
            if type(ilvl) == "number" and ilvl > 0 then item.ilvl = floor(ilvl) end
            if type(itemType) == "string" and itemType ~= "" then item.itemType = itemType end
            if type(itemSubType) == "string" and itemSubType ~= "" then item.itemSubType = itemSubType end
            if type(equipLoc) == "string" and equipLoc ~= "" then item.equipLoc = equipLoc end
            if texture then item.icon = texture end
        end
    end
    if type(infoQuality) == "number" then
        item.quality = infoQuality
    else
        local color = smatch(link, "|c%x%x(%x%x%x%x%x%x)")
        item.quality = color and QUALITY_BY_COLOR[color:lower()] or nil
    end

    local getStats = (C_Item and C_Item.GetItemStats) or GetItemStats
    if getStats then
        local ok, stats = pcall(getStats, link)
        if ok and type(stats) == "table" then
            local out, any = {}, false
            for k, v in pairs(stats) do
                if type(k) == "string" and type(v) == "number" and v ~= 0 then out[k] = v; any = true end
            end
            if any then item.stats = out end   -- an empty table would encode as a JSON list
        end
    end
    if not item.name or item.name == "" then return nil end
    return item
end

-- The item as the website's item API takes it.
function Loot.Observation(item)
    return {
        id = item.id, name = item.name, quality = item.quality, itemLevel = item.ilvl,
        itemClass = item.itemType, itemSubclass = item.itemSubType, equipLoc = item.equipLoc,
        icon = item.icon, stats = item.stats,
    }
end

-- Files the item under its ID. A later sighting fills in what an earlier one could not see
-- (the client describes an item it has not loaded yet by its link alone).
local function remember(item, t)
    -- "of the Bear" items share an ID and differ in name and stats: nothing to file them under.
    if item.suffix then return end
    local items = ns.DB().items
    local cur = items[item.id]
    local o = Loot.Observation(item)
    if type(cur) ~= "table" then
        o.seen, o.first, o.last = 1, t, t
        items[item.id] = o
        return
    end
    for _, k in ipairs(Loot.OBSERVATION_KEYS) do
        if o[k] ~= nil then cur[k] = o[k] end
    end
    cur.seen = (tonumber(cur.seen) or 0) + 1
    cur.first = cur.first or t
    cur.last = t
end

---------------------------------------------------------------------------
-- The log
---------------------------------------------------------------------------

local function log()
    return ns.DB().loot.log
end

function Loot.Trim()
    local l = log()
    local extra = #l - Loot.MAX_LOG
    if extra <= 0 then return end
    for i = 1, #l - extra do l[i] = l[i + extra] end
    for i = #l, #l - extra + 1, -1 do l[i] = nil end
end

local function entryFor(item, t, count)
    return {
        t = t, link = item.link, id = item.id, name = item.name, q = item.quality, icon = item.icon,
        suffix = item.suffix, n = (count and count > 1) and count or nil, zone = zone(),
    }
end

local function add(entry)
    local l = log()
    l[#l + 1] = entry
    Loot.Trim()
end

local function sameItem(entry, item)
    return entry.id == item.id and (entry.suffix or 0) == (item.suffix or 0)
end

-- The newest entry for this item that `test` accepts, no older than `seconds`.
local function findRecent(item, t, seconds, test)
    local l = log()
    for i = #l, 1, -1 do
        local e = l[i]
        if t - (e.t or 0) > seconds then return nil end
        if sameItem(e, item) and test(e) then return e end
    end
    return nil
end

-- Newest first, at or above a quality.
function Loot.Entries(minQuality)
    minQuality = minQuality or 0
    local out = {}
    local l = log()
    for i = #l, 1, -1 do
        if (l[i].q or 1) >= minQuality then out[#out + 1] = l[i] end
    end
    return out
end

function Loot.Counts()
    local items = 0
    for _ in pairs(ns.DB().items) do items = items + 1 end
    return #log(), items
end

function Loot.Clear()
    local l = log()
    for i = #l, 1, -1 do l[i] = nil end
    notify()
end

---------------------------------------------------------------------------
-- Loot lines in chat: who received what
---------------------------------------------------------------------------

-- "%s receives loot: %s." -> a Lua pattern, plus which capture is which. Built from the
-- client's own format strings so it works in every locale; falls back to English.
local function formatToPattern(fmt)
    local order, n = {}, 0
    local pattern = sgsub(fmt, "[%^%$%(%)%.%[%]%*%+%-%?]", "%%%0")
    -- Positional forms first ("%1$s", which localized clients use to reorder arguments). The
    -- "$" was escaped to "%$" by the line above, so that is what has to be matched here.
    pattern = sgsub(pattern, "%%(%d)%%%$s", function(i) n = n + 1; order[n] = tonumber(i); return "(.+)" end)
    -- (a function's return value is used as it is: "%d", not the "%%d" a replacement string would need)
    pattern = sgsub(pattern, "%%(%d)%%%$d", function(i) n = n + 1; order[n] = tonumber(i); return "(%d+)" end)
    pattern = sgsub(pattern, "%%s", function() n = n + 1; order[n] = n; return "(.+)" end)
    pattern = sgsub(pattern, "%%d", function() n = n + 1; order[n] = n; return "(%d+)" end)
    return "^" .. pattern .. "$", order
end

local lootPatterns
local function buildLootPatterns()
    local defs = {
        -- global name,            English fallback,               has a player?  (the "x3" forms first:
        -- the plain pattern would swallow the count into the link)
        { "LOOT_ITEM_MULTIPLE",             "%s receives loot: %sx%d.",  true },
        { "LOOT_ITEM",                      "%s receives loot: %s.",     true },
        { "LOOT_ITEM_SELF_MULTIPLE",        "You receive loot: %sx%d.",  false },
        { "LOOT_ITEM_SELF",                 "You receive loot: %s.",     false },
        { "LOOT_ITEM_PUSHED_SELF_MULTIPLE", "You receive item: %sx%d.",  false },
        { "LOOT_ITEM_PUSHED_SELF",          "You receive item: %s.",     false },
    }
    local out = {}
    for _, d in ipairs(defs) do
        local fmt = _G[d[1]] or d[2]
        if type(fmt) == "string" then
            local pattern, order = formatToPattern(fmt)
            out[#out + 1] = { pattern = pattern, order = order, hasPlayer = d[3] }
        end
    end
    return out
end

-- Returns who (nil for yourself), link, count for a loot chat line; nothing for any other line.
function Loot.ParseLootMessage(msg)
    if type(msg) ~= "string" then return nil end
    -- Where the game restricts addons (an encounter in progress), chat text arrives as a
    -- secret value that cannot be matched against. Those lines are not logged.
    if issecretvalue and issecretvalue(msg) then return nil end
    lootPatterns = lootPatterns or buildLootPatterns()
    for _, p in ipairs(lootPatterns) do
        local caps = { smatch(msg, p.pattern) }
        if #caps > 0 then
            local args = {}
            for i, v in ipairs(caps) do args[p.order[i] or i] = v end
            if p.hasPlayer then
                return args[1], args[2], tonumber(args[3]) or 1
            end
            return nil, args[1], tonumber(args[2]) or 1
        end
    end
    return nil
end

function Loot.OnLootMessage(msg)
    local who, link, count = Loot.ParseLootMessage(msg)
    if not link or not sfind(link, "|Hitem:", 1, true) then return end
    local item = Loot.Describe(link)
    if not item then return end
    local t = now()
    remember(item, t)

    local mine = who == nil
    local name = who or playerName()
    -- A drop already seen in the loot window and not yet handed out is this one.
    local pending = findRecent(item, t, Loot.PENDING_SECONDS, function(e) return e.window and not e.to end)
    if pending then
        pending.to, pending.mine, pending.at = name, mine or nil, t
        if count > 1 then pending.n = count end
    else
        local e = entryFor(item, t, count)
        e.to, e.mine = name, mine or nil
        add(e)
    end
    notify()
end

---------------------------------------------------------------------------
-- The loot window: what dropped
---------------------------------------------------------------------------

-- How many of an item each corpse has shown in any one opening. A corpse can be opened many
-- times with fewer items each time, so the largest count seen is how many dropped.
local shown = {}

function Loot.OnLootWindow()
    if not (GetNumLootItems and GetLootSlotLink) then return end
    local okCount, slots = pcall(GetNumLootItems)
    if not okCount or type(slots) ~= "number" then return end
    local t = now()
    local counts, samples, order = {}, {}, {}   -- order: the keys as the window lists them
    for slot = 1, slots do
        local okLink, link = pcall(GetLootSlotLink, slot)
        if okLink and type(link) == "string" and sfind(link, "|Hitem:", 1, true) then
            local item = Loot.Describe(link)
            if item then
                local quantity
                if GetLootSlotInfo then
                    local ok, _, _, q = pcall(GetLootSlotInfo, slot)
                    if ok and type(q) == "number" then quantity = q end
                end
                local source
                if GetLootSourceInfo then
                    local ok, guid = pcall(GetLootSourceInfo, slot)
                    if ok and type(guid) == "string" then source = guid end
                end
                -- No source to tell corpses apart: the same item within two minutes is the same corpse.
                source = source or ("t" .. floor(t / 120))
                local key = source .. ":" .. item.id .. ":" .. (item.suffix or 0)
                if not counts[key] then order[#order + 1] = key end
                counts[key] = (counts[key] or 0) + 1
                samples[key] = { item = item, quantity = quantity }
            end
        end
    end

    local changed = false
    for _, key in ipairs(order) do
        local n, s = counts[key], samples[key]
        -- A sighting is a new drop; the same corpse opened again is not one.
        if n > (shown[key] or 0) then remember(s.item, t) end
        for _ = (shown[key] or 0) + 1, n do
            -- With fast looting the chat line can arrive before the window event.
            local early = findRecent(s.item, t, 5, function(e) return e.to and not e.window end)
            if early then
                early.window = true
            else
                local e = entryFor(s.item, t, s.quantity)
                e.window = true
                add(e)
            end
            changed = true
        end
        if n > (shown[key] or 0) then shown[key] = n end
    end
    if changed then notify() end
end

---------------------------------------------------------------------------
-- Late item details
---------------------------------------------------------------------------

-- The client describes an item it has not loaded yet by its link alone; when the details
-- arrive, entries that were missing them are filled in.
function Loot.OnItemInfo(itemId)
    itemId = tonumber(itemId)
    if not itemId then return end
    local changed = false
    local l = log()
    for i = #l, 1, -1 do
        local e = l[i]
        if e.id == itemId and (e.icon == nil or e.q == nil) then
            local item = Loot.Describe(e.link)
            if item then
                e.icon, e.q, e.name = item.icon or e.icon, item.quality or e.q, item.name or e.name
                remember(item, e.t or now())
                local cur = ns.DB().items[itemId]
                if cur then cur.seen = math.max(1, (tonumber(cur.seen) or 1) - 1) end   -- a refresh, not a sighting
                changed = true
            end
        end
    end
    if changed then notify() end
end

function Loot.OnEvent(event, ...)
    if event == "CHAT_MSG_LOOT" then
        Loot.OnLootMessage((...))
    elseif event == "LOOT_OPENED" or event == "LOOT_READY" then
        Loot.OnLootWindow()
    elseif event == "GET_ITEM_INFO_RECEIVED" then
        Loot.OnItemInfo((...))
    end
end

---------------------------------------------------------------------------
-- Export for the website's item database
---------------------------------------------------------------------------

-- The item as the website will see it, and a fingerprint of that: what tells an item that
-- changed since it was exported from one that did not.
local function exportForm(o)
    local item = {}
    for _, k in ipairs(Loot.OBSERVATION_KEYS) do item[k] = o[k] end
    return item, ns.Encode.Adler32(ns.Encode.JSON(item))
end

-- The items to export, most recently seen first: everything when `all` is set, otherwise
-- what has not been exported yet or has changed since it was.
function Loot.Pending(all)
    local rows = {}
    for _, o in pairs(ns.DB().items) do
        if type(o) == "table" and type(o.id) == "number" and type(o.name) == "string" and o.name ~= "" then
            local item, mark = exportForm(o)
            if all or o.sent ~= mark then
                rows[#rows + 1] = { id = o.id, last = o.last or 0, item = item, mark = mark }
            end
        end
    end
    table.sort(rows, function(a, b)
        if a.last ~= b.last then return a.last > b.last end
        return a.id < b.id
    end)
    return rows
end

function Loot.PendingCount()
    return #Loot.Pending(false)
end

-- The export strings, one per hundred items. Each part is a complete document of its own
-- (docs/item-export-format-v1.md): { str, count, marks = { [item id] = fingerprint } }.
function Loot.BuildExport(all)
    local rows = Loot.Pending(all)
    if #rows == 0 then return {}, 0 end

    local by, game
    local data = ns.Scan()
    if data then
        game = data.game
        by = { name = data.char.name, lastName = data.char.lastName, realm = data.char.realm, region = data.char.region }
    end
    local stamp = time()
    local parts = {}
    local of = math.ceil(#rows / Loot.EXPORT_CHUNK)
    for index = 1, of do
        local items, marks = {}, {}
        for i = (index - 1) * Loot.EXPORT_CHUNK + 1, math.min(index * Loot.EXPORT_CHUNK, #rows) do
            items[#items + 1] = rows[i].item
            marks[rows[i].id] = rows[i].mark
        end
        local str = ns.Encode.Pack({
            v = 1, kind = "items", ts = stamp,
            addon = { name = ns.NAME, version = ns.VERSION },
            game = game, by = by,
            part = { index = index, of = of },
            items = items,
        })
        parts[index] = { str = str, count = #items, marks = marks }
    end
    return parts, #rows
end

-- Remembers that a part was exported: its items are not "new" again until they change.
function Loot.MarkExported(part)
    local items = ns.DB().items
    for id, mark in pairs(part.marks) do
        if type(items[id]) == "table" then items[id].sent = mark end
    end
    notify()
end
