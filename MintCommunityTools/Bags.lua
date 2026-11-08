--[[
    Bags.lua - the bag windows, in the flat skin.

    The backpack as one window (the combined bags) and the bags as windows of their own are
    the game's and stay so; what changes is their dress, with the same code that dresses the
    game menu's windows (Menus.lua):
      - the ornate border, the bag's portrait and the textured background are gone; the
        window is a flat dark panel with a 1px border, its title left as plain text, its
        close button a flat square with an x;
      - each slot is a flat dark square with the item's picture trimmed to it, and its
        border is the colour of the item's quality where the game drew a coloured frame; an
        empty slot is the plain square, without the game's empty-slot art;
      - the search box and the coin box are flat;
      - the sort button is a flat square that says Sort, and the bag's menu, which was
        behind the portrait, is a small flat square with a v where the portrait was.

    The bag window sits on a mover of its own ("Bag window" in edit mode), by its bottom
    right corner, so that it grows up and to the left as the game has it grow. The game
    puts its bag windows where it wants them every time one opens or closes, so the window
    is put back on the mover after each time it does, and a look once a second catches
    anything else. A bag window holds the game's protected item buttons, and the game does
    not let such a window be moved in combat: a bag opened in combat stays where the game
    put it and goes to the mover when combat ends. With the bags as separate windows it is
    the backpack that sits on the mover; the game stacks the others from it.

    A bag makes and lays out its slots when it opens and when what is in it changes, so a
    window is dressed again each time it is shown, each time the game lays its items out,
    and a moment after the bags change. Nothing is written into the game's frames and the
    slots themselves are not moved or resized: using an item from a bag runs the game's own
    protected code, which the addon stays out of the way of.

    What a bag window is made of on this client was read with /mint uidump bags.
]]

local ADDON, ns = ...
local Bags = {}
ns.Bags = Bags

local ipairs, type, pcall = ipairs, type, pcall
local floor, tsort = math.floor, table.sort

-- The bag windows, by the global names they have had: the combined one, then one per bag.
local WINDOWS = { "ContainerFrameCombinedBags" }
for i = 1, 13 do WINDOWS[#WINDOWS + 1] = "ContainerFrame" .. i end
Bags.WINDOWS = WINDOWS
-- The game lays a bag's items out again through these.
local RELAYS = { "UpdateItems", "UpdateItemLayout", "Update" }
local EVENTS = { "BAG_UPDATE_DELAYED", "BAG_NEW_ITEMS_UPDATED", "PLAYER_ENTERING_WORLD", "LOOT_OPENED", "LOOT_READY", "LOOT_SLOT_CLEARED",
                 "MERCHANT_SHOW", "MERCHANT_UPDATE" }

local MOVER_DEFAULT = { "BOTTOMRIGHT", -20, 84 }
local MOVER_SIZE = { 430, 180 }   -- until a bag window has been open: about the backpack's own

local function frame(name)
    local f = _G[name]
    return type(f) == "table" and f or nil
end

local function isShown(f)
    if type(f) ~= "table" or type(f.IsShown) ~= "function" then return false end
    local ok, shown = pcall(f.IsShown, f)
    return ok and shown == true
end

-- The bag window that goes on the mover: the combined backpack when it is open, otherwise
-- the backpack's own window when that is.
local function movable()
    for _, name in ipairs({ "ContainerFrameCombinedBags", "ContainerFrame1" }) do
        local f = frame(name)
        if isShown(f) then return f end
    end
    return nil
end

---------------------------------------------------------------------------
-- The slots of the combined window, in the addon's order
---------------------------------------------------------------------------

-- The game lays the combined window's slots out from the bottom right, the highest-numbered
-- bag first and the backpack last, so a quiver (or an ammo pouch, a soul bag, a profession
-- bag) in the middle bag slots lands among the ordinary bags. The addon lays them out again,
-- the special bags first (so at the bottom), the rest as the game had them. Seen in
-- /mint uidump bags on build 70790: every slot hangs by its bottom right corner off the same
-- frame, 42 apart, ten to a row.

-- A bag's family: 0 for an ordinary bag, a number for a quiver, an ammo pouch, a soul bag or
-- a profession bag. A missing or secret answer counts as ordinary.
local function bagFamily(bagID)
    local fn = (type(C_Container) == "table" and C_Container.GetContainerNumFreeSlots) or GetContainerNumFreeSlots
    if type(fn) ~= "function" then return 0 end
    local ok, _, family = pcall(fn, bagID)
    if not ok or (issecretvalue and issecretvalue(family)) or type(family) ~= "number" then return 0 end
    return family
end

-- The slots in a bag window: the item buttons the game made, each with its bag and its
-- first point (the corner it hangs by, off what, and where).
local function slotsOf(f)
    local out = {}
    if type(f) ~= "table" or type(f.GetChildren) ~= "function" then return out end
    local ok, kids = pcall(function() return { f:GetChildren() } end)
    for _, c in ipairs(ok and kids or {}) do
        if type(c) == "table" and type(c.GetBagID) == "function" and type(c.GetID) == "function" and isShown(c) then
            local okB, bag = pcall(c.GetBagID, c)
            local okP, point, rel, relPoint, x, y = pcall(c.GetPoint, c, 1)
            local okN, n = pcall(c.GetNumPoints, c)
            if okB and okP and type(bag) == "number" and type(x) == "number" and type(y) == "number" and rel ~= nil then
                out[#out + 1] = { button = c, bag = bag, point = point, rel = rel, relPoint = relPoint, x = x, y = y,
                                  points = okN and n or 1, special = bagFamily(bag) ~= 0 }
            end
        end
    end
    return out
end

-- The grid the game laid the slots out in, read off the slots themselves: all hang by the
-- same corner off the same frame; the columns are the distinct x offsets, a step the gap
-- between neighbours, the first slot the rightmost and lowest. Nil when the slots are not
-- laid out that way (another client), and nothing is moved.
local function gridOf(list)
    if #list < 2 then return nil end
    local first = list[1]
    local xs, ys = {}, {}
    for _, s in ipairs(list) do
        if s.point ~= first.point or s.rel ~= first.rel or s.relPoint ~= first.relPoint then return nil end
        xs[s.x], ys[s.y] = true, true
    end
    local function sorted(set)
        local t = {}
        for v in pairs(set) do t[#t + 1] = v end
        tsort(t)
        return t
    end
    local xl, yl = sorted(xs), sorted(ys)
    if #xl < 2 then return nil end
    local stepX = xl[2] - xl[1]
    for i = 3, #xl do if xl[i] - xl[i - 1] < stepX then stepX = xl[i] - xl[i - 1] end end
    local stepY = yl[2] and (yl[2] - yl[1]) or stepX
    for i = 3, #yl do if yl[i] - yl[i - 1] < stepY then stepY = yl[i] - yl[i - 1] end end
    if stepX <= 0 or stepY <= 0 then return nil end
    return { point = first.point, rel = first.rel, relPoint = first.relPoint, x0 = xl[#xl], y0 = yl[1], stepX = stepX, stepY = stepY, columns = #xl }
end

-- Lays the combined window's slots out again: the special bags' slots first, then the rest
-- in the order they are in now. With `restore`, the game's own order (the special bags
-- back where they were) for when the setting is turned off. Only out of combat: the slots
-- are the game's protected buttons, and a window opened in combat is arranged when it
-- ends. Returns how many slots moved.
function Bags.Arrange(f, restore)
    f = f or frame("ContainerFrameCombinedBags")
    if not Bags.applied or not f or not isShown(f) then return 0 end
    local specialFirst = ns.Overhaul.Settings().bags.specialBottom ~= false
    if not specialFirst and not restore then return 0 end
    if InCombatLockdown and InCombatLockdown() then
        Bags.pendingArrange = true
        return 0
    end
    local list = slotsOf(f)
    local g = gridOf(list)
    if not g then return 0 end
    -- where each slot is now, counted from the bottom right; the game's own order within a bag
    for _, s in ipairs(list) do
        s.at = floor((g.y0 - s.y) / g.stepY + 0.5) * -g.columns + floor((g.x0 - s.x) / g.stepX + 0.5)
    end
    tsort(list, function(a, b)
        if specialFirst and a.special ~= b.special then return a.special end
        if restore and a.bag ~= b.bag then return a.bag > b.bag end
        return a.at < b.at
    end)
    local moved = 0
    for i, s in ipairs(list) do
        local c, r = (i - 1) % g.columns, floor((i - 1) / g.columns)
        local x, y = g.x0 - c * g.stepX, g.y0 + r * g.stepY
        if s.x ~= x or s.y ~= y or s.points ~= 1 then
            pcall(s.button.ClearAllPoints, s.button)
            pcall(s.button.SetPoint, s.button, g.point, g.rel, g.relPoint, x, y)
            moved = moved + 1
        end
    end
    Bags.arranged = (Bags.arranged or 0) + moved
    return moved
end

-- Once a second while a bag window is open, and a moment after the bags change: the slots'
-- pictures and borders as the game has them now, and the combined window's slots in the
-- addon's order. Returns how many slots were looked at or moved.
function Bags.Look()
    if not Bags.applied or ns.Menus.IsOff("bags") then return 0 end
    local n = 0
    for _, name in ipairs(WINDOWS) do
        local f = frame(name)
        if f and isShown(f) then n = n + ns.Menus.LookAtSlots(f) end
    end
    return n + Bags.Arrange()
end

local function mover(width, height)
    Bags.size = (width and height) and { width, height } or Bags.size or MOVER_SIZE
    return ns.Overhaul.Mover("bagwindow", "Bag window", Bags.size[1], Bags.size[2], MOVER_DEFAULT)
end

-- Puts the open bag window on its mover. Returns true when it did. Not in combat (the game
-- does not let a window holding its item buttons be moved then): it is done when combat ends.
function Bags.Place()
    if not Bags.applied then return false end
    local f = movable()
    if not f then return false end
    if InCombatLockdown and InCombatLockdown() then
        Bags.pending = true
        return false
    end
    local width, height
    if type(f.GetWidth) == "function" and type(f.GetHeight) == "function" then
        local ok, w, h
        ok, w = pcall(f.GetWidth, f)
        if ok and type(w) == "number" and w > 0 then width = w end
        ok, h = pcall(f.GetHeight, f)
        if ok and type(h) == "number" and h > 0 then height = h end
    end
    local m = mover(width, height)
    pcall(f.ClearAllPoints, f)
    pcall(f.SetPoint, f, "BOTTOMRIGHT", m, "BOTTOMRIGHT", 0, 0)
    Bags.pending = nil
    return true
end

-- Is the open bag window still on its mover? If the game has put it elsewhere, it goes
-- back. Returns true when it had to. Left alone while the game's own edit mode is open and
-- while a mouse button is down.
function Bags.Check()
    if not Bags.applied then return false end
    local f = movable()
    if not f then return false end
    if ns.Overhaul.GameEditing() then return false end
    if IsMouseButtonDown and IsMouseButtonDown() then return false end
    -- every point, not the first alone: the game adds one of its own to those the window has
    local box = ns.Overhaul.movers.bagwindow
    if box and ns.Overhaul.Fastened(f, { { "BOTTOMRIGHT", box, "BOTTOMRIGHT", 0, 0 } }) then return false end
    return Bags.Place()
end

-- The sort button is one button the game moves between its bag windows.
local function dressSort()
    if ns.Menus.IsOff("bags") then return false end
    return ns.Menus.As("bags", ns.Menus.FlatMarked, frame("BagItemAutoSortButton"), "Sort")
end

-- Dresses every bag window that exists. Returns how many there are.
-- The other windows that hold items are dressed with the bag windows: the loot window (what
-- a corpse or a chest holds) and the vendor's window. A flat panel, flat buttons and tabs,
-- items in plain slots with the border in the colour of their quality. Each fills itself
-- when it opens and as its pages are turned. Built without a look at this client's loot and
-- vendor windows at first; both were then checked against /mint uidump records on build 70334
-- (the loot window's rows are dressed by the window dressing, as loot cards).
local LOOT_WINDOWS = { "LootFrame", "MerchantFrame" }
local LOOT_RELAYS = { LootFrame = { "Open", "Update" }, MerchantFrame = {} }
-- The vendor's window is filled by functions of the game's that are not the window's own.
local LOOT_GLOBALS = { "MerchantFrame_Update", "MerchantFrame_UpdateMerchantInfo", "MerchantFrame_UpdateBuybackInfo" }
Bags.LOOT_WINDOWS = LOOT_WINDOWS
local lootHooked = {}

-- The vendor's window keeps art the window dressing does not know as a control: a slot
-- picture and a name plate behind each item (and the buyback slot), a slot picture behind
-- the repair and sell-junk buttons, and the page-turning arrows. Seen in /mint uidump vendor
-- on build 70334.
local VENDOR_ROW_ART = { "SlotTexture", "NameFrame" }
local VENDOR_ICON_BUTTONS = { "MerchantRepairAllButton", "MerchantRepairItemButton", "MerchantGuildBankRepairButton", "MerchantSellAllJunkButton" }
local VENDOR_PAGE_BUTTONS = { MerchantPrevPageButton = "<", MerchantNextPageButton = ">" }

local function dressVendor()
    if ns.Menus.IsOff("bags") or not frame("MerchantFrame") then return 0 end
    return ns.Menus.As("bags", function()
        local M = ns.Menus
        local n = 0
        local rows = { "MerchantBuyBackItem" }
        for i = 1, 12 do rows[#rows + 1] = "MerchantItem" .. i end
        for _, row in ipairs(rows) do
            for _, suffix in ipairs(VENDOR_ROW_ART) do
                local t = frame(row .. suffix)
                if t then
                    M.Hide(t)
                    n = n + 1
                end
            end
        end
        -- the slot picture is the one texture drawn behind the button's icon
        for _, name in ipairs(VENDOR_ICON_BUTTONS) do
            local b = frame(name)
            if b and type(b.GetRegions) == "function" then
                local ok, regions = pcall(function() return { b:GetRegions() } end)
                for _, r in ipairs(ok and regions or {}) do
                    if type(r) == "table" and r ~= b.Icon and type(r.GetDrawLayer) == "function" then
                        local okLayer, layer = pcall(r.GetDrawLayer, r)
                        if okLayer and layer == "BACKGROUND" then
                            M.Hide(r)
                            n = n + 1
                        end
                    end
                end
            end
        end
        for name, mark in pairs(VENDOR_PAGE_BUTTONS) do
            local b = frame(name)
            if b and M.FlatMarked(b, mark, 8) then n = n + 1 end
        end
        Bags.vendorArt = n
        return n
    end)
end

local function dressLoot()
    local n = 0
    for _, name in ipairs(LOOT_WINDOWS) do
        if ns.Menus.DressNamed(name, LOOT_RELAYS[name], "bags") then n = n + 1 end
    end
    pcall(dressVendor)
    for _, name in ipairs(LOOT_GLOBALS) do
        if not lootHooked[name] and hooksecurefunc and type(_G[name]) == "function" then
            lootHooked[name] = true
            -- dressed again a moment later, with whatever else has changed
            pcall(hooksecurefunc, name, function() if Bags.applied then Bags.dirty = true end end)
        end
    end
    Bags.lootCount = n
    return n
end

function Bags.DressAll()
    local n = 0
    for _, name in ipairs(WINDOWS) do
        if ns.Menus.DressNamed(name, RELAYS, "bags") then n = n + 1 end
    end
    dressSort()
    dressLoot()
    return n
end

-- Dresses the bag windows that are open, for what has changed in them.
function Bags.Refresh()
    local n = 0
    for _, name in ipairs(WINDOWS) do
        local f = frame(name)
        if f and type(f.IsShown) == "function" then
            local ok, shown = pcall(f.IsShown, f)
            if ok and shown == true and pcall(ns.Menus.Dress, f, name, "bags") then n = n + 1 end
        end
    end
    dressSort()
    Bags.Look()
    -- the loot and vendor windows, when one is open (and found now, if it did not exist at login)
    dressLoot()
    for _, name in ipairs(LOOT_WINDOWS) do
        local f = frame(name)
        if f and type(f.IsShown) == "function" then
            local ok, shown = pcall(f.IsShown, f)
            if ok and shown == true then pcall(ns.Menus.Dress, f, name, "bags") end
        end
    end
    pcall(dressVendor)
    return n
end

function Bags.Apply()
    if not ns.Menus then error("the window dressing code did not load") end
    ns.Menus.SetOff("bags", false)
    Bags.count = Bags.DressAll()
    mover()
    if not Bags.events then
        Bags.events = CreateFrame("Frame")
        Bags.dirty, Bags.elapsed, Bags.sinceCheck = false, 0, 0
        for _, ev in ipairs(EVENTS) do pcall(Bags.events.RegisterEvent, Bags.events, ev) end
        Bags.events:SetScript("OnEvent", function() if Bags.applied then Bags.dirty = true end end)
        Bags.events:SetScript("OnUpdate", function(_, dt)
            dt = type(dt) == "number" and dt or 0
            -- Once a second: is the open bag window still on its mover?
            Bags.sinceCheck = Bags.sinceCheck + dt
            if Bags.sinceCheck >= 1 then
                Bags.sinceCheck = 0
                Bags.Check()
                Bags.Look()
            end
            -- The game tells of a change to the bags several times over: once, a moment later.
            if not Bags.dirty then return end
            Bags.elapsed = Bags.elapsed + dt
            if Bags.elapsed < 0.1 then return end
            Bags.dirty, Bags.elapsed = false, 0
            Bags.Refresh()
        end)
        -- The game places its bag windows each time one opens or closes: so does this, after.
        if hooksecurefunc and type(UpdateContainerFrameAnchors) == "function" then
            pcall(hooksecurefunc, "UpdateContainerFrameAnchors", function() Bags.Place() end)
        end
        for _, name in ipairs({ "ContainerFrameCombinedBags", "ContainerFrame1" }) do
            local f = frame(name)
            if f and type(f.HookScript) == "function" then
                pcall(f.HookScript, f, "OnShow", function()
                    Bags.Place()
                    if Bags.applied then Bags.dirty = true end   -- its slots a moment after the game has filled them
                end)
            end
        end
    end
    Bags.applied = true
    Bags.Place()
end

function Bags.OnEnteringWorld()
    Bags.count = Bags.DressAll()
    Bags.Place()
end

-- Combat is over: a bag window opened during it goes to its mover now, its slots in order.
function Bags.OnCombatEnd()
    if Bags.pending then Bags.Place() end
    if Bags.pendingArrange then
        Bags.pendingArrange = nil
        Bags.Arrange()
    end
end

-- The special bags' place switched: the open window laid out again at once, the game's own
-- order back when it is off.
function Bags.OnSettingsChanged(path)
    if path == "bags.specialBottom" then Bags.Arrange(nil, true) end
end

-- Switched off: the bag windows get back what was changed on them, and are the game's to
-- place again (it places them every time one opens).
function Bags.Unapply()
    Bags.applied = false
    Bags.dirty, Bags.pending = false, nil
    ns.Menus.SetOff("bags", true)
    ns.Overhaul.HideMover("bagwindow")
end
