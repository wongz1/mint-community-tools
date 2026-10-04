--[[
    CastBars.lua - the cast bars, in the flat skin.

    The player's cast bar (and the target's, the focus's and the pet's where the client has
    them) are the game's own bars and stay so: the game fills them, times them and says what
    is being cast. That matters on this client, where the timing of a cast can be a value an
    addon may show but not read. What changes is their dress:
      - the ornate frame, the text box under the bar and the textured background are gone;
        the bar is a flat dark strip with a 1px border;
      - the fill is a plain colour instead of the game's art: your class colour for a cast,
        green for a channel, red when it was interrupted, grey when it cannot be interrupted;
      - the spell's name sits on the bar instead of in a box under it.
    The player's cast bar also sits on a mover ("Cast bar" in edit mode).

    The Cast bar page of the Settings tab sets your own cast bar's width and height, and for
    every cast bar the size of the spell's name and where it sits: so far right or left of
    the bar's middle, so far above or below it. Until a width, a height or a text size is
    chosen there, each is as the game has it.

    How: the art is made invisible (alpha 0), and a background and four 1px edges are drawn
    just outside the bar with the same code that dresses the game menu's windows. The game
    sets the bar's fill picture again every time a cast starts, stops or is interrupted, so
    that call is watched and the plain fill put back after it, in the colour for what the
    game says the bar is doing (its barType). The game also places the player's cast bar
    itself, each time it lays out the frames at the bottom of the screen; that is watched
    the same way and the bar put back on its mover at once, so it is never seen anywhere
    else. While the game's own edit mode is open the bar is left to it.

    Built without a look at this client's cast bars; /mint uidump cast records them.
]]

local ADDON, ns = ...
local Cast = {}
ns.CastBars = Cast

local ipairs, type, pcall = ipairs, type, pcall

-- The cast bars, by the global names they have had. The first that exists of each is used.
local BARS = {
    { key = "player", names = { "PlayerCastingBarFrame", "CastingBarFrame" }, mover = true },
    { key = "target", names = { "TargetFrameSpellBar" } },
    { key = "focus", names = { "FocusFrameSpellBar" } },
    { key = "pet", names = { "PetCastingBarFrame" } },
}
Cast.BARS = BARS
-- The parts a bar's art is kept in.
local ART = { "Border", "TextBorder", "Background", "BorderShield" }
local MOVER_DEFAULT = { "BOTTOM", 0, 186 }
local COLORS = {
    channel = { 0.3, 0.8, 0.35 },
    interrupted = { 0.85, 0.25, 0.25 },
    uninterruptable = { 0.6, 0.6, 0.6 },
    uninterruptible = { 0.6, 0.6, 0.6 },
}

-- What a setting may be: { least, most, step }. The Settings tab's steppers use these too.
-- A width, height or text size under its least means: as the game has it.
Cast.LIMITS = {
    width = { 80, 500, 4 }, height = { 6, 40, 1 }, fontSize = { 6, 24, 1 },
    textX = { -150, 150, 2 }, textY = { -40, 40, 1 },
}

local skinned = setmetatable({}, { __mode = "k" })   -- bar -> true once it has been dressed
Cast.bars = {}                                       -- key -> the bar found for it

local function frame(name)
    local f = _G[name]
    return type(f) == "table" and f or nil
end

local function settings()
    return ns.Overhaul.Settings().cast
end

-- A size chosen in the settings, kept inside what it may be; nil while none has been.
local function chosen(key)
    local limit = Cast.LIMITS[key]
    local v = tonumber(settings()[key])
    if not v or v < limit[1] then return nil end
    return v > limit[2] and limit[2] or v
end

-- How far the text sits from the bar's middle: 0 unless set, kept inside what it may be.
local function nudge(key)
    local limit = Cast.LIMITS[key]
    local v = tonumber(settings()[key]) or 0
    if v < limit[1] then v = limit[1] elseif v > limit[2] then v = limit[2] end
    return v
end

local function number(fn, obj, fallback)
    if type(fn) == "function" then
        local ok, v = pcall(fn, obj)
        if ok and type(v) == "number" and v > 0 then return v end
    end
    return fallback
end

-- The fill's colour for what the game says the bar is doing.
function Cast.Color(bar)
    local kind = type(bar.barType) == "string" and bar.barType or "standard"
    local c = COLORS[kind]
    if c then return c[1], c[2], c[3] end
    local r, g, b = ns.W.accent()
    return r, g, b
end

-- The spell's name on the bar itself, in the skin's small font. Where the game had it, and
-- in what font, is written down first, for when the cast bars are switched off.
local function placeText(bar)
    local text = bar.Text
    if type(text) ~= "table" or type(text.SetPoint) ~= "function" then return end
    local points, font = {}, nil
    if type(text.GetNumPoints) == "function" then
        local ok, n = pcall(text.GetNumPoints, text)
        if ok and type(n) == "number" then
            for i = 1, n do
                local okPoint, point, rel, relPoint, x, y = pcall(text.GetPoint, text, i)
                if okPoint and type(point) == "string" then points[#points + 1] = { point, rel, relPoint, x, y } end
            end
        end
    end
    if type(text.GetFontObject) == "function" then
        local ok, f = pcall(text.GetFontObject, text)
        if ok and type(f) == "table" then font = f end
    end
    ns.Menus.Remember(text, "place", function()
        if #points > 0 then
            pcall(text.ClearAllPoints, text)
            for _, p in ipairs(points) do pcall(text.SetPoint, text, p[1], p[2], p[3], p[4], p[5]) end
        end
        if font then pcall(text.SetFontObject, text, font) end
    end)
    pcall(text.ClearAllPoints, text)
    pcall(text.SetPoint, text, "CENTER", bar, "CENTER", nudge("textX"), nudge("textY"))
    if type(text.SetFontObject) == "function" then pcall(text.SetFontObject, text, "GameFontHighlightSmall") end
    -- a size chosen in the settings: the same font, at that size
    local size = chosen("fontSize")
    if size and type(text.GetFont) == "function" and type(text.SetFont) == "function" then
        local ok, file, _, flags = pcall(text.GetFont, text)
        if not ok or type(file) ~= "string" then file = type(STANDARD_TEXT_FONT) == "string" and STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF" end
        pcall(text.SetFont, text, file, size, type(flags) == "string" and flags or "")
    end
end

-- The size of the spell's name right now: what was chosen, or what the bar's text has.
function Cast.FontSize()
    local size = chosen("fontSize")
    if size then return size end
    local bar = Cast.bars.player
    local text = bar and bar.Text
    if type(text) == "table" and type(text.GetFont) == "function" then
        local ok, _, current = pcall(text.GetFont, text)
        if ok and type(current) == "number" and current > 0 then return math.floor(current + 0.5) end
    end
    return 10
end

-- Your own cast bar's width and height right now.
function Cast.Size()
    local bar = Cast.bars.player
    if not bar then return 208, 11 end
    return math.floor(number(bar.GetWidth, bar, 208) + 0.5), math.floor(number(bar.GetHeight, bar, 11) + 0.5)
end

-- The player's cast bar at the width and height chosen in the settings. The size the game
-- gave it is written down first, for when the cast bars are switched off.
local function resize(bar)
    local width, height = chosen("width"), chosen("height")
    if not (width or height) then return false end
    local was = { number(bar.GetWidth, bar, nil), number(bar.GetHeight, bar, nil) }
    ns.Menus.Remember(bar, "size", function()
        if was[1] then pcall(bar.SetWidth, bar, was[1]) end
        if was[2] then pcall(bar.SetHeight, bar, was[2]) end
    end)
    if width then pcall(bar.SetWidth, bar, width) end
    if height then pcall(bar.SetHeight, bar, height) end
    return true
end

-- Dresses one bar, as the cast bars' piece. Safe to run again: the hooks are put on once.
local function skin(bar)
    local W = ns.W
    local hide = ns.Menus.Hide
    for _, key in ipairs(ART) do hide(bar[key]) end
    -- the border goes just outside the bar: the fill covers everything inside it
    ns.Menus.Flat(bar, W.COLOR.panel, -1)
    if bar == Cast.bars.player then resize(bar) end
    placeText(bar)

    local busy = false
    local function fill()
        if busy or ns.Menus.IsOff("cast") then return end
        busy = true
        pcall(bar.SetStatusBarTexture, bar, W.WHITE)
        local r, g, b = Cast.Color(bar)
        pcall(bar.SetStatusBarColor, bar, r, g, b, 1)
        busy = false
    end
    if not skinned[bar] then
        skinned[bar] = true
        if hooksecurefunc and type(bar.SetStatusBarTexture) == "function" then
            pcall(hooksecurefunc, bar, "SetStatusBarTexture", fill)
        end
        if type(bar.HookScript) == "function" then
            -- a cast starting shows the bar: the game may have put its text back under it
            pcall(bar.HookScript, bar, "OnShow", function(self)
                if ns.Menus.IsOff("cast") then return end
                ns.Menus.As("cast", function()
                    for _, key in ipairs(ART) do ns.Menus.Hide(self[key]) end
                    placeText(self)
                end)
            end)
        end
    end
    fill()
    return true
end

---------------------------------------------------------------------------
-- The player's cast bar on its mover
---------------------------------------------------------------------------

local placing = false

local function mover(bar)
    local width, height = 208, 11
    if type(bar.GetWidth) == "function" then
        local ok, w = pcall(bar.GetWidth, bar)
        if ok and type(w) == "number" and w > 0 then width = w end
    end
    if type(bar.GetHeight) == "function" then
        local ok, h = pcall(bar.GetHeight, bar)
        if ok and type(h) == "number" and h > 0 then height = h end
    end
    return ns.Overhaul.Mover("castbar", "Cast bar", width, height + 6, MOVER_DEFAULT)
end

-- Puts the player's cast bar on its mover. Left alone while the game's own edit mode is open.
function Cast.Place()
    local bar = Cast.bars.player
    if not (bar and Cast.applied) or placing then return false end
    if ns.Overhaul.GameEditing() then return false end
    placing = true
    local m = mover(bar)
    pcall(bar.ClearAllPoints, bar)
    pcall(bar.SetPoint, bar, "CENTER", m, "CENTER", 0, 0)
    placing = false
    return true
end

-- Is the player's cast bar still on its mover? Returns true when it had to be put back.
function Cast.Check()
    local bar = Cast.bars.player
    if not (Cast.applied and bar) then return false end
    -- the game gives the bar its own size back at times
    local width, height = chosen("width"), chosen("height")
    local w, h = Cast.Size()
    if (width and math.abs(w - width) > 0.5) or (height and math.abs(h - height) > 0.5) then
        pcall(ns.Menus.As, "cast", resize, bar)
    end
    -- every point, not the first alone: the game adds one of its own to those the bar has
    local box = ns.Overhaul.movers.castbar
    if box and ns.Overhaul.Fastened(bar, { { "CENTER", box, "CENTER", 0, 0 } }) then return false end
    return Cast.Place()
end

---------------------------------------------------------------------------
-- The overhaul's hooks
---------------------------------------------------------------------------

function Cast.Apply()
    if not (ns.Menus and ns.Menus.Flat) then error("the window dressing code did not load") end
    ns.Menus.SetOff("cast", false)
    Cast.count = 0
    for _, def in ipairs(BARS) do
        local bar
        for _, name in ipairs(def.names) do
            bar = bar or frame(name)
        end
        if bar then
            Cast.bars[def.key] = bar
            if pcall(ns.Menus.As, "cast", skin, bar) then Cast.count = Cast.count + 1 end
        end
    end
    if Cast.count == 0 then error("this client has no cast bar the addon knows of") end

    local player = Cast.bars.player
    if player then
        Cast.applied = true
        Cast.Place()
        if not Cast.events then
            -- The game places the bar itself, whenever it lays out the bottom of the screen:
            -- it goes back on its mover in the same breath.
            if hooksecurefunc and type(player.SetPoint) == "function" then
                pcall(hooksecurefunc, player, "SetPoint", function(_, _, anchor)
                    if not placing and anchor ~= ns.Overhaul.movers.castbar then Cast.Place() end
                end)
            end
            -- And a look once a second, for after the game's own edit mode closes.
            Cast.events = CreateFrame("Frame")
            local elapsed = 0
            Cast.events:SetScript("OnUpdate", function(_, dt)
                elapsed = elapsed + (type(dt) == "number" and dt or 0)
                if elapsed < 1 then return end
                elapsed = 0
                Cast.Check()
            end)
        end
    end
    Cast.applied = true
end

function Cast.OnEnteringWorld()
    for _, bar in pairs(Cast.bars) do pcall(ns.Menus.As, "cast", skin, bar) end
    Cast.Place()
end

-- A setting on the Cast bar page changed: the bars are dressed again, at once.
function Cast.OnSettingsChanged(path)
    if not (Cast.applied and type(path) == "string" and path:match("^cast%.")) then return end
    for _, bar in pairs(Cast.bars) do pcall(ns.Menus.As, "cast", skin, bar) end
    Cast.Place()
end

-- Switched off: the bars get back what was changed on them. The plain fill stays until the
-- game next sets the bar's picture, which it does when the next cast starts; the player's
-- bar is the game's to place again, which it does when it next lays out its frames.
function Cast.Unapply()
    Cast.applied = false
    ns.Menus.SetOff("cast", true)
    ns.Overhaul.HideMover("castbar")
end
