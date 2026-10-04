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

-- The bag windows, by the global names they have had: the combined one, then one per bag.
local WINDOWS = { "ContainerFrameCombinedBags" }
for i = 1, 13 do WINDOWS[#WINDOWS + 1] = "ContainerFrame" .. i end
Bags.WINDOWS = WINDOWS
-- The game lays a bag's items out again through these.
local RELAYS = { "UpdateItems", "UpdateItemLayout", "Update" }
local EVENTS = { "BAG_UPDATE_DELAYED", "BAG_NEW_ITEMS_UPDATED", "PLAYER_ENTERING_WORLD" }

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

local function mover(width, height)
    Bags.size = (width and height) and { width, height } or Bags.size or MOVER_SIZE
    return ns.Overhaul.Mover("bagwindow", "Bag window", Bags.size[1], Bags.size[2], MOVER_DEFAULT)
end

-- Puts the open bag window on its mover. Returns true when it did. Not in combat (the game
-- does not let a window holding its item buttons be moved then): it is done when combat ends.
function Bags.Place()
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
    local ok, _, anchor = pcall(f.GetPoint, f, 1)
    if ok and anchor == ns.Overhaul.movers.bagwindow then return false end
    return Bags.Place()
end

-- The sort button is one button the game moves between its bag windows.
local function dressSort()
    return ns.Menus.FlatMarked(frame("BagItemAutoSortButton"), "Sort")
end

-- Dresses every bag window that exists. Returns how many there are.
function Bags.DressAll()
    local n = 0
    for _, name in ipairs(WINDOWS) do
        if ns.Menus.DressNamed(name, RELAYS) then n = n + 1 end
    end
    dressSort()
    return n
end

-- Dresses the bag windows that are open, for what has changed in them.
function Bags.Refresh()
    local n = 0
    for _, name in ipairs(WINDOWS) do
        local f = frame(name)
        if f and type(f.IsShown) == "function" then
            local ok, shown = pcall(f.IsShown, f)
            if ok and shown == true and pcall(ns.Menus.Dress, f, name) then n = n + 1 end
        end
    end
    dressSort()
    return n
end

function Bags.Apply()
    if not ns.Menus then error("the window dressing code did not load") end
    Bags.count = Bags.DressAll()
    mover()
    if not Bags.events then
        Bags.events = CreateFrame("Frame")
        Bags.dirty, Bags.elapsed, Bags.sinceCheck = false, 0, 0
        for _, ev in ipairs(EVENTS) do pcall(Bags.events.RegisterEvent, Bags.events, ev) end
        Bags.events:SetScript("OnEvent", function() Bags.dirty = true end)
        Bags.events:SetScript("OnUpdate", function(_, dt)
            dt = type(dt) == "number" and dt or 0
            -- Once a second: is the open bag window still on its mover?
            Bags.sinceCheck = Bags.sinceCheck + dt
            if Bags.sinceCheck >= 1 then
                Bags.sinceCheck = 0
                Bags.Check()
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
                pcall(f.HookScript, f, "OnShow", function() Bags.Place() end)
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

-- Combat is over: a bag window opened during it goes to its mover now.
function Bags.OnCombatEnd()
    if Bags.pending then Bags.Place() end
end
