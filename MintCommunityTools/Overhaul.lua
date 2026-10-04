--[[
    Overhaul.lua - the minimalist UI: settings, movers, edit mode, and applying it at login.

    The overhaul replaces or restyles the game's own frames in the addon's flat skin:
      ActionBars.lua   the action bars, pet and stance bars, bags and micro menu
      Chat.lua         the chat window
      UnitFrames.lua   player, target and target-of-target frames of the addon's own
      Map.lua          a square minimap with coordinates and the time under it
      Quests.lua       the tracked quests and their objectives, as a plain list
      Menus.lua        the game menu (Escape) and the windows it opens
      Bags.lua         the bag windows
      CastBars.lua     the cast bars
    Each piece can be turned off on its own, and the whole overhaul can (Settings tab,
    /mint ui on|off). Off is the default until it has been tried on the real client.

    Every element sits on a MOVER: an invisible frame at a saved position that the element
    is anchored to. Edit mode (/mint edit, or the Settings tab) shows the movers as labelled
    boxes to drag; right-click one to put it back. Positions are kept in the saved variables
    (ui.positions) by mover name.

    The game menu's own Edit Mode button opens this edit mode while the overhaul is on (the
    game's edit mode moves frames the overhaul has replaced); hold Shift while clicking it
    for the game's own. That is done with a transparent button of the addon's laid over the
    game's, which steps aside while Shift is held: the game's button and what it runs are
    not touched.

    The game menu also gets a button of the addon's own, "Mint Edit Mode", at its bottom. It
    is not one of the menu's buttons: the menu makes those itself, and a button an addon
    adds to that list is known to break the ones that run the game's protected code (Log
    Out, Edit Mode). It is a strip of the addon's hung under the menu, drawn to look like
    the menu carrying on, shown and hidden with it.

    Every switch takes effect when it is flipped, where it can. Turning the overhaul or any
    piece ON sets it up there and then (after combat, when in it). Turning a piece OFF is
    done at once for the pieces that only restyle the game's frames or add a frame of the
    addon's (the quest tracker, the game menu, the bag windows, the cast bars): each has an
    Unapply that puts back exactly what its Apply changed. The pieces that take the game's
    frames apart and rebuild them (action bars, chat, unit frames, minimap) have none: the
    game's own layout of those cannot be put back piece by piece, so turning one of those
    off, alone or with the whole overhaul, is finished by a /reload. The Settings tab says
    which and offers the reload. Everything here is feature-detected and run under pcall: the WoW Forever
    client is a beta, and a frame that is not there must cost a piece, never the addon.
]]

local ADDON, ns = ...
local O = {}
ns.Overhaul = O

local pairs, ipairs, type, tostring, pcall = pairs, ipairs, type, tostring, pcall

O.DEFAULTS = {
    enabled = false,
    menuEdit = true,     -- the game menu's Edit Mode button opens this UI's edit mode
    menuButton = true,   -- a Mint Edit Mode button at the bottom of the game menu
    bars = { enabled = true, size = 32, spacing = 2, hideMicro = false, extraBags = true, xpClassColor = true, xpWidth = 0, xpHeight = 0 },
    -- fontSize 0 and font "default" mean: as the game has them
    chat = { enabled = true, background = true, width = 400, height = 180, fontSize = 0, font = "default" },
    units = {
        enabled = true, portrait = true, portrait3d = false, classColor = true,
        font = "default", fontSize = 10, width = 240, height = 46, smallWidth = 120, smallHeight = 24,
        buffSize = 20, debuffSize = 20, perRow = 8, buffTimers = true, debuffTimers = true,
        player = { buffs = "off", debuffs = "above", onlyMine = false },
        target = { buffs = "above", debuffs = "above", onlyMine = false },
    },
    map = { enabled = true, square = true, size = 180, zone = true, coords = true, localTime = true, gameTime = true },
    quests = { enabled = true, levels = true, background = false, collapsed = false, width = 250, maxHeight = 420 },
    menus = { enabled = true },
    bags = { enabled = true },
    -- width, height and fontSize 0 mean: as the game has them
    cast = { enabled = true, width = 0, height = 0, fontSize = 0, textX = 0, textY = 0 },
    positions = {},
}

-- Fills in anything missing from the saved settings without touching what is there.
local function fill(t, defaults)
    for k, v in pairs(defaults) do
        if type(v) == "table" then
            if type(t[k]) ~= "table" then t[k] = {} end
            fill(t[k], v)
        elseif t[k] == nil then
            t[k] = v
        end
    end
end

function O.Settings()
    local db = ns.DB()
    if type(db.ui) ~= "table" then db.ui = {} end
    -- "clock" used to switch both times at once; they have a switch each now.
    local map = db.ui.map
    if type(map) == "table" and map.clock ~= nil then
        if map.clock == false then
            if map.localTime == nil then map.localTime = false end
            if map.gameTime == nil then map.gameTime = false end
        end
        map.clock = nil
    end
    -- One size for every aura icon became a size each for buffs and debuffs.
    local units = db.ui.units
    if type(units) == "table" and units.auraSize ~= nil then
        if units.buffSize == nil then units.buffSize = units.auraSize end
        if units.debuffSize == nil then units.debuffSize = units.auraSize end
        units.auraSize = nil
    end
    fill(db.ui, O.DEFAULTS)
    return db.ui
end

-- The whole overhaul, or one piece of it ("bars", "chat", "units", "map", "quests", "menus"), is on.
function O.Active(piece)
    local s = O.Settings()
    if not s.enabled then return false end
    if piece then return s[piece] and s[piece].enabled and true or false end
    return true
end

local function inCombat()
    return InCombatLockdown and InCombatLockdown() or false
end

-- Is the game's own edit mode open? It is moving its frames about then, and the pieces that
-- keep a frame of the game's on a mover leave it alone until it closes.
--- Is `f` fastened exactly as `wanted` says: those points ({ point, to, toPoint, x, y } each)
--- and no others? The game adds a point of its own to a frame at times without taking the
--- others off. The first point then still looks right, while the frame is stretched between
--- the addon's points and the game's and no longer follows its mover.
function O.Fastened(f, wanted)
    if type(f) ~= "table" or type(f.GetPoint) ~= "function" then return false end
    local n
    if type(f.GetNumPoints) == "function" then
        local ok, count = pcall(f.GetNumPoints, f)
        if ok and type(count) == "number" then n = count end
    end
    if n and n ~= #wanted then return false end
    local have = {}
    for i = 1, n or #wanted do
        local ok, point, to, toPoint, x, y = pcall(f.GetPoint, f, i)
        if not ok or type(point) ~= "string" then return false end
        have[point] = { to, toPoint, x, y }
    end
    for _, want in ipairs(wanted) do
        local h = have[want[1]]
        if not h or h[1] ~= want[2] or h[2] ~= want[3] then return false end
        local x, y = h[3], h[4]
        if not (issecretvalue and (issecretvalue(x) or issecretvalue(y))) then
            if type(x) ~= "number" or type(y) ~= "number" then return false end
            if math.abs(x - want[4]) > 0.5 or math.abs(y - want[5]) > 0.5 then return false end
        end
    end
    return true
end

--- The parts of the addon that this session has not loaded. A file added by an update is
--- only read when the game starts: a /reload does not pick it up.
function O.MissingParts()
    local out = {}
    for _, piece in ipairs(O.PIECES or {}) do
        if not ns[piece.module] then out[#out + 1] = piece.label end
    end
    return out
end

function O.GameEditing()
    local manager = _G.EditModeManagerFrame
    if type(manager) ~= "table" then return false end
    if type(manager.IsEditModeActive) == "function" then
        local ok, active = pcall(manager.IsEditModeActive, manager)
        if ok and active == true then return true end
    end
    if type(manager.IsShown) == "function" then
        local ok, shown = pcall(manager.IsShown, manager)
        if ok and shown == true then return true end
    end
    return false
end

---------------------------------------------------------------------------
-- Hiding the game's own frames
---------------------------------------------------------------------------

-- A hidden parent: a frame put under it stays hidden whatever the game does with it.
local hider = CreateFrame("Frame", "MintCommunityToolsHider", UIParent)
hider:Hide()
O.hider = hider

-- Some of the game's frames ask their parent to do things ("parent:UpdateBarsShown()"), and
-- a frame moved under the hider would be asking the hider, which has no such method: a Lua
-- error in the game's own code. So the hider answers any method it does not have by doing
-- nothing. Only names that start with a capital, as methods do: a field the game looks for
-- ("isManagedFrame") is still not there.
pcall(function()
    local mt = getmetatable(hider)
    local methods = mt and mt.__index
    if type(methods) ~= "table" then return end
    local function nothing() end
    setmetatable(hider, {
        __index = function(_, key)
            local v = methods[key]
            if v ~= nil then return v end
            if type(key) == "string" and key:find("^%u") then return nothing end
            return nil
        end,
    })
end)

-- frame -> the parent it had before it was hidden, for giving it back
local taken = setmetatable({}, { __mode = "k" })

-- Hides a frame of the game's under the hidden parent. Its events are cut off unless
-- `keepEvents`: a frame that may be given back later (O.ShowBlizzard) has to stay alive.
function O.HideBlizzard(frame, keepEvents)
    if type(frame) ~= "table" then return false end
    if not keepEvents then pcall(frame.UnregisterAllEvents, frame) end
    if taken[frame] == nil and type(frame.GetParent) == "function" then
        local ok, parent = pcall(frame.GetParent, frame)
        if ok and type(parent) == "table" and parent ~= hider then taken[frame] = parent end
    end
    pcall(frame.Hide, frame)
    pcall(frame.SetParent, frame, hider)
    return true
end

-- Gives a frame hidden with its events kept back to the game: under the parent it had, shown.
function O.ShowBlizzard(frame)
    if type(frame) ~= "table" then return false end
    local parent = taken[frame]
    pcall(frame.SetParent, frame, type(parent) == "table" and parent or UIParent)
    pcall(frame.Show, frame)
    return true
end

-- A texture or frame that should not be seen but may still be used (by the game's code).
function O.Blank(obj)
    if type(obj) ~= "table" then return false end
    if obj.SetTexture then pcall(obj.SetTexture, obj, nil) end
    pcall(obj.SetAlpha, obj, 0)
    if obj.Hide and not obj.SetTexture then pcall(obj.Hide, obj) end
    return true
end

-- Blanks every texture drawn directly on a frame (not its child frames, not its text). The
-- client's art is not called the same thing from one version to the next, so art is removed
-- by sweeping the frame it is drawn on rather than by name. Returns how many were blanked.
function O.BlankRegions(f)
    if type(f) ~= "table" or type(f.GetRegions) ~= "function" then return 0 end
    local ok, regions = pcall(function() return { f:GetRegions() } end)
    if not ok then return 0 end
    local n = 0
    for _, r in ipairs(regions) do
        if type(r) == "table" and type(r.IsObjectType) == "function" then
            local okType, isTexture = pcall(r.IsObjectType, r, "Texture")
            if okType and isTexture and O.Blank(r) then n = n + 1 end
        end
    end
    return n
end

---------------------------------------------------------------------------
-- Movers
---------------------------------------------------------------------------

local movers = {}        -- key -> mover frame
local order = {}         -- keys in the order they were made
local editing = false
O.movers = movers

local function positions()
    return O.Settings().positions
end

local function place(mover)
    local saved = positions()[mover.key]
    local p = (type(saved) == "table" and type(saved[1]) == "string" and type(saved[2]) == "number" and type(saved[3]) == "number")
        and saved or mover.default
    mover:ClearAllPoints()
    mover:SetPoint(p[1], UIParent, p[1], p[2], p[3])
end

local function remember(mover)
    local point, _, _, x, y = mover:GetPoint(1)
    if type(point) == "string" and type(x) == "number" and type(y) == "number" then
        positions()[mover.key] = { point, math.floor(x + 0.5), math.floor(y + 0.5) }
    end
end

local function paint(mover)
    local W = ns.W
    if mover.off == true then return end   -- its piece is turned off: no box in edit mode
    if editing then
        mover:SetAlpha(1)
        mover:EnableMouse(true)
        W.setBg(mover, { 0.1, 0.1, 0.1, 0.7 })
        W.setBorder(mover, W.accent())
    else
        mover:SetAlpha(0)
        mover:EnableMouse(false)
    end
end

-- The mover for `key`, made on first use: `width` x `height`, labelled `label` in edit mode,
-- at `default` ({ point, x, y } from the same point of the screen) until it is moved.
function O.Mover(key, label, width, height, default)
    local W = ns.W
    local mover = movers[key]
    if not mover then
        mover = W.safeCreate("Frame", "MintCommunityToolsMover_" .. key, UIParent, W.template())
        mover.key, mover.label, mover.default = key, label, default
        mover:SetFrameStrata("DIALOG")
        mover:SetFrameLevel(20)
        mover:SetClampedToScreen(true)
        mover:SetMovable(true)
        mover:RegisterForDrag("LeftButton")
        W.skin(mover, { 0.1, 0.1, 0.1, 0.7 })
        mover.text = W.text(mover, label)
        mover.text:SetPoint("CENTER")
        mover:SetScript("OnDragStart", function(self) if editing and not inCombat() then self:StartMoving() end end)
        mover:SetScript("OnDragStop", function(self)
            self:StopMovingOrSizing()
            remember(self)
        end)
        mover:SetScript("OnMouseUp", function(self, button)
            if button == "RightButton" and editing then O.ResetPosition(self.key) end
        end)
        mover:SetScript("OnEnter", function(self)
            if not (editing and GameTooltip) then return end
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:SetText(self.label, 1, 1, 1)
            GameTooltip:AddLine("Drag to move. Right-click to put it back.", 0.6, 0.6, 0.6)
            GameTooltip:Show()
        end)
        mover:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
        movers[key] = mover
        order[#order + 1] = key
    end
    mover.default = default or mover.default
    mover.label = label
    mover.off = false
    mover.text:SetText(label)
    mover:SetSize(width, height)
    place(mover)
    paint(mover)
    mover:Show()
    return mover
end

-- Puts a mover away: its piece has been turned off, and there is nothing on it to move. The
-- next O.Mover call for it brings it back.
function O.HideMover(key)
    local mover = movers[key]
    if not mover then return false end
    mover.off = true
    mover:Hide()
    return true
end

function O.ResetPosition(key)
    local mover = movers[key]
    positions()[key] = nil
    if mover then place(mover) end
end

function O.ResetPositions()
    for _, key in ipairs(order) do O.ResetPosition(key) end
    ns.Say("every frame is back at its default place.")
end

---------------------------------------------------------------------------
-- Edit mode
---------------------------------------------------------------------------

local editBar

local function buildEditBar()
    local W = ns.W
    local f = W.window("MintCommunityToolsEditBar", 380, 52, "FULLSCREEN_DIALOG", "Edit mode", "drag the boxes; right-click one to put it back")
    f:ClearAllPoints()
    f:SetPoint("TOP", UIParent, "TOP", 0, -40)
    f.close:SetScript("OnClick", function() O.SetEdit(false) end)
    local reset = W.button(f, "MintCommunityToolsEditResetButton", "Reset all", 90, function() O.ResetPositions() end)
    reset:SetPoint("TOPLEFT", W.PAD, -(W.TITLE_H + W.GAP))
    local done = W.button(f, "MintCommunityToolsEditDoneButton", "Done", 90, function() O.SetEdit(false) end)
    done:SetPoint("LEFT", reset, "RIGHT", W.GAP, 0)
    f:Hide()
    return f
end

function O.Editing()
    return editing
end

function O.SetEdit(on)
    on = on and true or false
    if on and inCombat() then
        ns.Say("edit mode cannot be used in combat.")
        return false
    end
    if on and not O.Active() then
        ns.Say("the UI overhaul is off (Settings tab, or /mint ui on), so there is nothing to move.")
        return false
    end
    editing = on
    for _, key in ipairs(order) do paint(movers[key]) end
    if on then
        editBar = editBar or buildEditBar()
        editBar:Show()
    elseif editBar then
        editBar:Hide()
    end
    if ns.SettingsUI then ns.SettingsUI.Refresh() end
    return true
end

function O.ToggleEdit()
    return O.SetEdit(not editing)
end

---------------------------------------------------------------------------
-- The game menu's Edit Mode button
---------------------------------------------------------------------------

local catch          -- the addon's transparent button over the game's
local menuHooked = false

-- The game menu's Edit Mode button: the one that says so. The menu makes its buttons anew
-- each time it opens, so it is looked for each time.
local function gameEditButton()
    local menu = _G.GameMenuFrame
    if type(menu) ~= "table" or type(menu.GetChildren) ~= "function" then return nil end
    local label = type(HUD_EDIT_MODE_MENU) == "string" and HUD_EDIT_MODE_MENU or "Edit Mode"
    local ok, children = pcall(function() return { menu:GetChildren() } end)
    if not ok then return nil end
    for _, child in ipairs(children) do
        if type(child) == "table" and type(child.GetText) == "function" and type(child.IsObjectType) == "function" then
            local okType, isButton = pcall(child.IsObjectType, child, "Button")
            local okText, text = pcall(child.GetText, child)
            if okType and isButton == true and okText and text == label then return child end
        end
    end
    return nil
end

local function buildCatch()
    local W = ns.W
    catch = W.safeCreate("Button", "MintCommunityToolsMenuEditCatch", UIParent)
    catch:RegisterForClicks("LeftButtonUp")
    catch.over, catch.stepped = false, false
    catch:SetScript("OnClick", function()
        local menu = _G.GameMenuFrame
        if type(HideUIPanel) == "function" then pcall(HideUIPanel, menu) else pcall(menu.Hide, menu) end
        O.SetEdit(true)
    end)
    catch:SetScript("OnEnter", function(self)
        if type(self.over) == "table" and type(self.over.LockHighlight) == "function" then pcall(self.over.LockHighlight, self.over) end
        if not GameTooltip then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText("Edit Mode", 1, 0.82, 0)
        GameTooltip:AddLine("Opens the minimalist UI's edit mode: drag its frames where you want them.", 1, 1, 1, true)
        GameTooltip:AddLine("Hold Shift and click for the game's own edit mode.", 0.6, 0.6, 0.6, true)
        GameTooltip:Show()
    end)
    catch:SetScript("OnLeave", function(self)
        if type(self.over) == "table" and type(self.over.UnlockHighlight) == "function" then pcall(self.over.UnlockHighlight, self.over) end
        if GameTooltip then GameTooltip:Hide() end
    end)
    -- While Shift is held the catch lets the mouse through, so the click reaches the game's
    -- own button and runs the game's own, untouched, code.
    catch:SetScript("OnUpdate", function(self)
        local shift = IsShiftKeyDown and IsShiftKeyDown() and true or false
        if shift ~= self.stepped then
            self.stepped = shift
            self:EnableMouse(not shift)
        end
    end)
end

-- Lays the catch over the game menu's Edit Mode button, or puts it away: when the overhaul
-- or this setting is off, when the menu is closed, or when the menu has no such button.
function O.PlaceMenuCatch()
    local menu = _G.GameMenuFrame
    local wanted = O.Active() and O.Settings().menuEdit and type(menu) == "table"
    local shown = false
    if wanted and type(menu.IsShown) == "function" then
        local ok, s = pcall(menu.IsShown, menu)
        shown = ok and s == true
    end
    local button = wanted and shown and gameEditButton() or nil
    if not button then
        if catch then catch:Hide() end
        return false
    end
    if not catch then buildCatch() end
    catch.over = button
    catch:ClearAllPoints()
    catch:SetPoint("TOPLEFT", button, "TOPLEFT", 0, 0)
    catch:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", 0, 0)
    local okStrata, strata = pcall(menu.GetFrameStrata, menu)
    if okStrata and type(strata) == "string" then catch:SetFrameStrata(strata) end
    local okLevel, level = pcall(button.GetFrameLevel, button)
    catch:SetFrameLevel((okLevel and type(level) == "number" and level or 10) + 10)
    catch.stepped = false
    catch:EnableMouse(true)
    catch:Show()
    return true
end

-- The addon's own button under the game menu: "Mint Edit Mode".
local menuStrip

local function buildMenuStrip()
    local W = ns.W
    menuStrip = W.panel(UIParent, { 0.06, 0.06, 0.06, 0.95 })   -- as the flat game menu is
    menuStrip.button = W.button(menuStrip, "MintCommunityToolsMenuEditButton", "Mint Edit Mode", 200, function()
        local menu = _G.GameMenuFrame
        if type(HideUIPanel) == "function" then pcall(HideUIPanel, menu) else pcall(menu.Hide, menu) end
        O.SetEdit(true)
    end)
    menuStrip.button:SetHeight(36)   -- the height of the menu's own buttons
    pcall(menuStrip.button.SetNormalFontObject, menuStrip.button, "GameFontHighlight")
    menuStrip.button:SetPoint("TOP", menuStrip, "TOP", 0, -10)
end

-- Hangs the strip under the game menu, or puts it away: when the overhaul or this setting is
-- off, or the menu is closed.
function O.PlaceMenuButton()
    local menu = _G.GameMenuFrame
    local wanted = O.Active() and O.Settings().menuButton and type(menu) == "table"
    local shown = false
    if wanted and type(menu.IsShown) == "function" then
        local ok, s = pcall(menu.IsShown, menu)
        shown = ok and s == true
    end
    if not (wanted and shown) then
        if menuStrip then menuStrip:Hide() end
        return false
    end
    if not menuStrip then buildMenuStrip() end
    -- From the menu's bottom edge down, over its bottom border, so the two read as one panel.
    menuStrip:ClearAllPoints()
    menuStrip:SetPoint("TOPLEFT", menu, "BOTTOMLEFT", 0, 1)
    menuStrip:SetPoint("TOPRIGHT", menu, "BOTTOMRIGHT", 0, 1)
    menuStrip:SetHeight(10 + 36 + 10)
    local okStrata, strata = pcall(menu.GetFrameStrata, menu)
    if okStrata and type(strata) == "string" then menuStrip:SetFrameStrata(strata) end
    menuStrip:Show()
    return true
end

local function placeMenuThings()
    O.PlaceMenuCatch()
    O.PlaceMenuButton()
end

-- The menu is watched, not changed: its buttons are made when it opens.
local function hookGameMenu()
    local menu = _G.GameMenuFrame
    if menuHooked or type(menu) ~= "table" or type(menu.HookScript) ~= "function" then return end
    menuHooked = true
    pcall(menu.HookScript, menu, "OnShow", placeMenuThings)
    pcall(menu.HookScript, menu, "OnHide", placeMenuThings)
    if hooksecurefunc and type(menu.InitButtons) == "function" then
        pcall(hooksecurefunc, menu, "InitButtons", placeMenuThings)
    end
end

---------------------------------------------------------------------------
-- Applying the overhaul
---------------------------------------------------------------------------

O.applied = {}      -- piece -> true once it has been applied this session
O.needsReload = false

local PIECES = {
    { key = "bars", module = "Bars", label = "action bars" },
    { key = "chat", module = "Chat", label = "chat" },
    { key = "units", module = "Units", label = "unit frames" },
    { key = "map", module = "Map", label = "minimap" },
    { key = "quests", module = "Quests", label = "quest tracker" },
    { key = "menus", module = "Menus", label = "game menu" },
    { key = "bags", module = "Bags", label = "bag windows" },
    { key = "cast", module = "CastBars", label = "cast bars" },
}
O.PIECES = PIECES

local function applyPiece(piece)
    local m = ns[piece.module]
    if not (m and m.Apply) then return end
    local ok, err = pcall(m.Apply)
    if ok then
        O.applied[piece.key] = true
    else
        ns.Say(("the %s could not be set up: %s"):format(piece.label, tostring(err)))
    end
end

-- Called at login. A piece is applied once per session; a piece turned on later needs a
-- reload, and so does turning one off.
-- A piece that can be taken off again without a reload has an Unapply.
local function unapplyPiece(piece)
    local m = ns[piece.module]
    if not (m and m.Unapply) then return false end
    local ok, err = pcall(m.Unapply)
    if ok then
        O.applied[piece.key] = nil
        return true
    end
    ns.Say(("the %s could not be turned off: %s"):format(piece.label, tostring(err)))
    return false
end

-- Does switching this setting OFF need a reload to finish? True for a piece that has no
-- Unapply, and for the overhaul's own switch (which turns those pieces off with the rest).
-- The Settings tab marks these switches.
function O.OffNeedsReload(path)
    if path == "enabled" then return true end
    local key = type(path) == "string" and path:match("^(%w+)%.enabled$")
    if not key then return false end
    for _, piece in ipairs(PIECES) do
        if piece.key == key then
            local m = ns[piece.module]
            return not (m and m.Unapply)
        end
    end
    return false
end

-- The pieces that are set up but switched off and cannot be taken off without a reload.
function O.ReloadPieces()
    local out = {}
    for _, piece in ipairs(PIECES) do
        local m = ns[piece.module]
        if O.applied[piece.key] and not O.Active(piece.key) and not (m and m.Unapply) then out[#out + 1] = piece.label end
    end
    return out
end

-- Brings what is set up into line with the settings: a piece that is wanted and not set up
-- is set up; one that is set up and not wanted is taken off when it can be. Not in combat
-- (frames the game protects cannot be made or moved then): it is done when combat ends.
function O.Sync()
    if inCombat() then
        O.pendingApply = true
        O.needsReload = #O.ReloadPieces() > 0
        return false
    end
    for _, piece in ipairs(PIECES) do
        local want = O.Active(piece.key)
        if want and not O.applied[piece.key] then
            applyPiece(piece)
        elseif not want and O.applied[piece.key] then
            unapplyPiece(piece)
        end
    end
    if O.Active() then hookGameMenu() end
    O.needsReload = #O.ReloadPieces() > 0
    return true
end

-- Called at login.
function O.Apply()
    if not O.Active() then return end
    if inCombat() then ns.Say("logged in during combat: the UI overhaul will be set up when it ends.") end
    O.Sync()
end

-- Called when combat ends: a login that happened in combat is set up now, and each piece is
-- told, for what it could not do during it.
function O.OnCombatEnd()
    if O.pendingApply then
        O.pendingApply = nil
        O.Sync()
        if ns.SettingsUI then ns.SettingsUI.Refresh() end
    end
    for _, piece in ipairs(O.PIECES) do
        local m = ns[piece.module]
        if O.applied[piece.key] and m and m.OnCombatEnd then pcall(m.OnCombatEnd) end
    end
end

-- Called on PLAYER_ENTERING_WORLD: pieces that the game re-lays out at that point.
function O.OnEnteringWorld()
    if not O.Active() then return end
    for _, piece in ipairs(PIECES) do
        local m = ns[piece.module]
        if O.applied[piece.key] and m and m.OnEnteringWorld then pcall(m.OnEnteringWorld) end
    end
end

-- A setting changed. Pieces that can follow live do; the rest are noted for a reload.
function O.Changed(path)
    local s = O.Settings()
    -- The overhaul or a piece switched on or off: done now, where it can be.
    if path == "enabled" or path:match("%.enabled$") then O.Sync() end
    for _, piece in ipairs(PIECES) do
        local m = ns[piece.module]
        if O.applied[piece.key] and m and m.OnSettingsChanged then pcall(m.OnSettingsChanged, path) end
    end
    if not s.enabled and editing then O.SetEdit(false) end
    if path == "menuEdit" or path == "enabled" then O.PlaceMenuCatch() end
    if path == "menuButton" or path == "enabled" then O.PlaceMenuButton() end
end

-- /mint ui [on|off]
function O.Command(arg)
    local s = O.Settings()
    if arg == "on" or arg == "off" then
        s.enabled = arg == "on"
        O.Changed("enabled")
        if O.pendingApply then
            ns.Say(("the UI overhaul is %s; that will be done when combat ends."):format(arg))
        elseif arg == "on" then
            ns.Say("the UI overhaul is on. /mint edit to arrange it.")
        elseif O.needsReload then
            ns.Say(("the UI overhaul is off. Type /reload to finish: the game's own %s come back at a reload."):format(table.concat(O.ReloadPieces(), ", ")))
        else
            ns.Say("the UI overhaul is off.")
        end
    elseif arg == "reset" then
        O.ResetPositions()
    else
        local on = {}
        for _, piece in ipairs(PIECES) do on[#on + 1] = piece.label .. ": " .. (s[piece.key].enabled and "on" or "off") end
        ns.Say(("the UI overhaul is %s (%s). /mint ui on|off, /mint edit to move things, /mint ui reset to put them back."):format(
            s.enabled and "on" or "off", table.concat(on, ", ")))
    end
end
