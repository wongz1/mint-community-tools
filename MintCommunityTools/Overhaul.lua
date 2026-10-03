--[[
    Overhaul.lua - the minimalist UI: settings, movers, edit mode, and applying it at login.

    The overhaul replaces or restyles the game's own frames in the addon's flat skin:
      ActionBars.lua   the action bars, pet and stance bars, bags and micro menu
      Chat.lua         the chat window
      UnitFrames.lua   player, target and target-of-target frames of the addon's own
      Map.lua          a square minimap with coordinates and the time under it
      Quests.lua       the tracked quests and their objectives, as a plain list
      Menus.lua        the game menu (Escape) and the windows it opens
    Each piece can be turned off on its own, and the whole overhaul can (Settings tab,
    /mint ui on|off). Off is the default until it has been tried on the real client.

    Every element sits on a MOVER: an invisible frame at a saved position that the element
    is anchored to. Edit mode (/mint edit, or the Settings tab) shows the movers as labelled
    boxes to drag; right-click one to put it back. Positions are kept in the saved variables
    (ui.positions) by mover name.

    What the game's own frames look like can only be changed once per session: turning a
    piece off (or the overhaul) takes a /reload to undo. The Settings tab says so and offers
    the reload. Everything here is feature-detected and run under pcall: the WoW Forever
    client is a beta, and a frame that is not there must cost a piece, never the addon.
]]

local ADDON, ns = ...
local O = {}
ns.Overhaul = O

local pairs, ipairs, type, tostring, pcall = pairs, ipairs, type, tostring, pcall

O.DEFAULTS = {
    enabled = false,
    bars = { enabled = true, size = 32, spacing = 2, hideMicro = false, extraBags = true },
    chat = { enabled = true, background = true, width = 400, height = 180 },
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

---------------------------------------------------------------------------
-- Hiding the game's own frames
---------------------------------------------------------------------------

-- A hidden parent: a frame put under it stays hidden whatever the game does with it.
local hider = CreateFrame("Frame", "MintCommunityToolsHider", UIParent)
hider:Hide()
O.hider = hider

function O.HideBlizzard(frame)
    if type(frame) ~= "table" then return false end
    pcall(frame.UnregisterAllEvents, frame)
    pcall(frame.Hide, frame)
    pcall(frame.SetParent, frame, hider)
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
    mover.text:SetText(label)
    mover:SetSize(width, height)
    place(mover)
    paint(mover)
    mover:Show()
    return mover
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
function O.Apply()
    if not O.Active() then return end
    if inCombat() then
        ns.Say("logged in during combat: the UI overhaul will be set up when it ends.")
        O.pendingApply = true
        return
    end
    for _, piece in ipairs(PIECES) do
        if O.Active(piece.key) and not O.applied[piece.key] then applyPiece(piece) end
    end
end

-- Called when combat ends: a login that happened in combat is set up now, and each piece is
-- told, for what it could not do during it.
function O.OnCombatEnd()
    if O.pendingApply then
        O.pendingApply = nil
        O.Apply()
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
    if path == "enabled" or path:match("%.enabled$") then
        -- Turning the overhaul or a piece on when it was not applied this session, or off
        -- when it was: a reload either way.
        O.needsReload = true
    end
    for _, piece in ipairs(PIECES) do
        local m = ns[piece.module]
        if O.applied[piece.key] and m and m.OnSettingsChanged then pcall(m.OnSettingsChanged, path) end
    end
    if not s.enabled and editing then O.SetEdit(false) end
end

-- /mint ui [on|off]
function O.Command(arg)
    local s = O.Settings()
    if arg == "on" or arg == "off" then
        s.enabled = arg == "on"
        O.Changed("enabled")
        ns.Say(("the UI overhaul is %s. Type /reload to apply it%s."):format(arg, arg == "on" and ", then /mint edit to arrange it" or ""))
    elseif arg == "reset" then
        O.ResetPositions()
    else
        local on = {}
        for _, piece in ipairs(PIECES) do on[#on + 1] = piece.label .. ": " .. (s[piece.key].enabled and "on" or "off") end
        ns.Say(("the UI overhaul is %s (%s). /mint ui on|off, /mint edit to move things, /mint ui reset to put them back."):format(
            s.enabled and "on" or "off", table.concat(on, ", ")))
    end
end
