--[[
    Meters.lua - the game's own damage meter, in the flat skin.

    This client has a damage meter of the game's own (Options, or /console damageMeterEnabled
    1). It stays the game's: the game counts the damage, sorts the bars and fills them. On
    this client the numbers behind a bar can be values an addon may show but not read, and
    the game's meter is the only thing that may read them. So nothing here calls the meter's
    own functions or writes anything into its frames: doing that would make the game treat
    its meter as addon code, and it would stop being able to read its own numbers in combat.

    What changes is the dress, with calls every frame and texture answers to:
      - the header's art and the textured background are made invisible; a flat header strip
        and a flat backdrop (as dark as the settings say, or none) are drawn in their place;
      - each bar loses its shadowed frame and gets a plain fill, in the colour the game gave
        it (class colours) or, if the settings say so, every bar in your own class colour;
      - the names and numbers on the bars take the font and the size chosen in the settings;
      - the minimize button and the breakdown window's close button become flat squares.

    The meter also sits on a mover ("Damage meter" in edit mode): the frame the game keeps
    its first window on is fastened to the mover's box, where the game had it until the box
    is dragged. The game places that frame itself when its layout arrives; it is put back on
    its box at once, and left alone while the game's own edit mode is open.

    What is left to the game, because only its own settings can change it safely: the bars'
    height and spacing, the window's size, the icons and the number format. They are in the
    game's Edit Mode (click the meter there).

    How: the meter's windows are found by name (DamageMeterSessionWindow1, 2, ...). Their bars
    are made as they scroll into view and the game dresses each again whenever it fills it,
    so the bars are gone over after every update of the list, and everything once a second.

    Built from /mint uidump meter on build 70205.
]]

local ADDON, ns = ...
local Meter = {}
ns.Meters = Meter

local ipairs, pairs, type, pcall, select = ipairs, pairs, type, pcall, select

Meter.WINDOWS_MOST = 6
-- What a setting may be: { least, most, step }. A text size under its least means: as the
-- game has it. The backdrop's darkness is in percent.
Meter.LIMITS = { fontSize = { 6, 24, 1 }, backgroundAlpha = { 0, 100, 10 } }

local function weak() return setmetatable({}, { __mode = "k" }) end
local own = weak()         -- frame -> { key = the addon's own texture on it }
local hooked = weak()      -- object -> true once its hooks are on
local gameAlpha = weak()   -- texture -> the alpha the game last gave it
local gameColor = weak()   -- status bar -> { r, g, b, a }: the colour the game last gave it
local gameFill = weak()    -- status bar -> the atlas its fill had, or false
local gameFont = weak()    -- font string -> { file, size, flags }: what it had before
local flattened = weak()   -- status bar -> true once its fill is the plain one
Meter.windows = {}         -- the session windows found so far

local busy = false         -- true while the addon itself is the one setting something

local function settings()
    return ns.Overhaul.Settings().meter
end

local function on()
    return Meter.applied == true and not ns.Menus.IsOff("meter")
end

-- A named part of a frame, when it is there.
local function part(f, key)
    if type(f) ~= "table" then return nil end
    local p = f[key]
    return type(p) == "table" and p or nil
end

local function limited(key)
    local limit = Meter.LIMITS[key]
    local v = tonumber(settings()[key])
    if not v then v = ns.Overhaul.DEFAULTS.meter[key] end
    if v < limit[1] then v = limit[1] elseif v > limit[2] then v = limit[2] end
    return v
end

-- The text size chosen in the settings; nil while none has been.
local function chosenSize()
    local v = tonumber(settings().fontSize)
    if not v or v < Meter.LIMITS.fontSize[1] then return nil end
    return limited("fontSize")
end

-- How dark the backdrop is, 0 to 1: nothing when it is switched off.
function Meter.BackdropAlpha()
    if not settings().background then return 0 end
    return limited("backgroundAlpha") / 100
end

---------------------------------------------------------------------------
-- The pieces of dress
---------------------------------------------------------------------------

-- Keeps a texture of the game's invisible. The game sets the alpha of some of these again
-- whenever it fills a bar (its own "background transparency"): that is watched, the alpha it
-- wanted written down for when the skin is switched off, and the texture made invisible again.
local function quiet(tex)
    if not tex or type(tex.SetAlpha) ~= "function" then return end
    if not hooked[tex] then
        hooked[tex] = true
        local alpha = 1
        if type(tex.GetAlpha) == "function" then
            local ok, a = pcall(tex.GetAlpha, tex)
            if ok and type(a) == "number" then alpha = a end
        end
        gameAlpha[tex] = alpha
        if hooksecurefunc then
            pcall(hooksecurefunc, tex, "SetAlpha", function(self, a)
                if busy then return end
                if type(a) == "number" then gameAlpha[self] = a end
                if on() then
                    busy = true
                    pcall(self.SetAlpha, self, 0)
                    busy = false
                end
            end)
        end
        ns.Menus.Remember(tex, "alpha", function()
            busy = true
            pcall(tex.SetAlpha, tex, gameAlpha[tex] or 1)
            busy = false
        end)
    end
    busy = true
    pcall(tex.SetAlpha, tex, 0)
    busy = false
end

-- A texture of the addon's own on one of the meter's frames, made once and shown again when
-- the skin comes back on.
local function mine(holder, key, layer, sublevel)
    local set = own[holder]
    if not set then
        set = {}
        own[holder] = set
    end
    local t = set[key]
    if not t then
        if type(holder.CreateTexture) ~= "function" then return nil end
        t = holder:CreateTexture(nil, layer, nil, sublevel)
        set[key] = t
        ns.Menus.Remember(t, "own", function() pcall(t.Hide, t) end)
    end
    pcall(t.Show, t)
    return t
end

-- A flat backdrop on `holder`, covering `over` (the holder itself when not said), with a 1px
-- border: colour { r, g, b }, as dark as `alpha` says. Nothing is drawn at alpha 0.
local function backdrop(holder, color, alpha, over)
    local W = ns.W
    over = over or holder
    local bg = mine(holder, "bg", "BACKGROUND", -8)
    if not bg then return end
    bg:ClearAllPoints()
    bg:SetAllPoints(over)
    W.colorTexture(bg, color[1], color[2], color[3], alpha)
    local px = W.pixel()
    local b = W.COLOR.border
    local spans = {
        { "TOPLEFT", "TOPRIGHT", "SetHeight" }, { "BOTTOMLEFT", "BOTTOMRIGHT", "SetHeight" },
        { "TOPLEFT", "BOTTOMLEFT", "SetWidth" }, { "TOPRIGHT", "BOTTOMRIGHT", "SetWidth" },
    }
    for n, span in ipairs(spans) do
        local e = mine(holder, "edge" .. n, "BORDER", 7)
        if e then
            e:ClearAllPoints()
            e:SetPoint(span[1], over, span[1], 0, 0)
            e:SetPoint(span[2], over, span[2], 0, 0)
            e[span[3]](e, px)
            W.colorTexture(e, b[1], b[2], b[3], alpha > 0 and (b[4] or 1) or 0)
        end
    end
end

local function atlasOf(tex)
    if type(tex) ~= "table" or type(tex.GetAtlas) ~= "function" then return nil end
    local ok, atlas = pcall(tex.GetAtlas, tex)
    if ok and type(atlas) == "string" and atlas ~= "" then return atlas end
    return nil
end

local function fillOf(sb)
    if type(sb.GetStatusBarTexture) ~= "function" then return nil end
    local ok, tex = pcall(sb.GetStatusBarTexture, sb)
    return ok and type(tex) == "table" and tex or nil
end

-- The colour a bar should have: your class colour when the settings want one colour for
-- every bar, else whatever the game last gave it.
local function paint(sb)
    local r, g, b, a
    if settings().oneColor then
        r, g, b = ns.W.accent()
        a = 1
    else
        local c = gameColor[sb]
        if not c then return end
        r, g, b, a = c[1], c[2], c[3], c[4]
    end
    busy = true
    pcall(sb.SetStatusBarColor, sb, r, g, b, a or 1)
    busy = false
end

local function flatten(sb)
    busy = true
    pcall(sb.SetStatusBarTexture, sb, ns.W.WHITE)
    busy = false
    flattened[sb] = true
end

-- A bar's fill: the plain one, in the right colour. The game gives a bar its own fill and
-- colour again when it fills it; both are watched.
local function fill(sb)
    if type(sb.SetStatusBarTexture) ~= "function" then return end
    local atlas = atlasOf(fillOf(sb))
    if not hooked[sb] then
        hooked[sb] = true
        gameFill[sb] = atlas or false
        if type(sb.GetStatusBarColor) == "function" then
            local ok, r, g, b, a = pcall(sb.GetStatusBarColor, sb)
            if ok and type(r) == "number" and type(g) == "number" and type(b) == "number" then
                gameColor[sb] = { r, g, b, type(a) == "number" and a or 1 }
            end
        end
        if hooksecurefunc then
            pcall(hooksecurefunc, sb, "SetStatusBarTexture", function(self)
                if busy or not on() then return end
                flatten(self)
                paint(self)
            end)
            pcall(hooksecurefunc, sb, "SetStatusBarColor", function(self, r, g, b, a)
                if busy then return end
                if type(r) == "number" and type(g) == "number" and type(b) == "number" then
                    gameColor[self] = { r, g, b, type(a) == "number" and a or 1 }
                end
                if on() then paint(self) end
            end)
        end
        ns.Menus.Remember(sb, "fill", function()
            flattened[sb] = nil
            local tex = fillOf(sb)
            if gameFill[sb] and tex and type(tex.SetAtlas) == "function" then pcall(tex.SetAtlas, tex, gameFill[sb]) end
            local c = gameColor[sb]
            if c then
                busy = true
                pcall(sb.SetStatusBarColor, sb, c[1], c[2], c[3], c[4])
                busy = false
            end
        end)
    end
    -- the game put its own picture back on the fill without being seen to
    if atlas or not flattened[sb] then flatten(sb) end
    paint(sb)
end

-- A name or a number on a bar: the font and the size chosen in the settings, or its own.
local function text(fs)
    if not fs or type(fs.GetFont) ~= "function" or type(fs.SetFont) ~= "function" then return end
    local ok, file, size, flags = pcall(fs.GetFont, fs)
    if not ok or type(file) ~= "string" or type(size) ~= "number" then return end
    if not gameFont[fs] then
        gameFont[fs] = { file, size, type(flags) == "string" and flags or "" }
        ns.Menus.Remember(fs, "font", function()
            local g = gameFont[fs]
            pcall(fs.SetFont, fs, g[1], g[2], g[3])
        end)
    end
    local g = gameFont[fs]
    Meter.gameTextSize = g[2]
    local font = ns.Units and ns.Units.Font(settings().font) or {}
    local wantFile, wantSize = font.path or g[1], chosenSize() or g[2]
    if file ~= wantFile or math.abs(size - wantSize) > 0.05 then
        local okSet, set = pcall(fs.SetFont, fs, wantFile, wantSize, g[3])
        if (not okSet or set == false) and wantFile ~= g[1] then pcall(fs.SetFont, fs, g[1], wantSize, g[3]) end
    end
end

-- One bar of the meter.
local function dressEntry(entry)
    local sb = part(entry, "StatusBar")
    if not sb then return false end
    quiet(part(sb, "Background"))
    quiet(part(sb, "BackgroundEdge"))
    local bg = mine(sb, "bg", "BACKGROUND", -8)
    if bg then
        bg:ClearAllPoints()
        bg:SetAllPoints(sb)
        ns.W.colorTexture(bg, 0, 0, 0, 0.45)
    end
    fill(sb)
    text(part(sb, "Name"))
    text(part(sb, "Value"))
    return true
end

-- The bars a scrolling list is showing right now.
local function entriesOf(box)
    local out = {}
    local target = part(box, "ScrollTarget")
    if target and type(target.GetChildren) == "function" then
        local kids = { pcall(target.GetChildren, target) }
        if kids[1] then
            for i = 2, #kids do
                if part(kids[i], "StatusBar") then out[#out + 1] = kids[i] end
            end
        end
    end
    return out
end

-- Every bar of a window: its list, the pinned bar for yourself, the breakdown window's list.
local function dressEntries(win)
    local n = 0
    local body = part(win, "MinimizeContainer") or win
    local source = part(body, "SourceWindow")
    for _, box in ipairs({ part(body, "ScrollBox") or false, source and part(source, "ScrollBox") or false }) do
        if box then
            for _, entry in ipairs(entriesOf(box)) do
                if dressEntry(entry) then n = n + 1 end
            end
        end
    end
    local me = part(body, "LocalPlayerEntry")
    if me and dressEntry(me) then n = n + 1 end
    return n
end

-- Goes over a window's bars again, as the meter's piece. Called after every update of its list.
function Meter.Pass(win)
    if not on() or Meter.passing then return 0 end
    Meter.passing = true
    local ok, n = pcall(ns.Menus.As, "meter", dressEntries, win)
    Meter.passing = false
    return ok and n or 0
end

-- One window of the meter: header, backdrop, buttons, bars.
local function dressWindow(win)
    local W, M = ns.W, ns.Menus
    local header = part(win, "Header")
    if header then
        quiet(header)
        local strip = mine(win, "header", "BACKGROUND", -7)
        if strip then
            strip:ClearAllPoints()
            strip:SetAllPoints(header)
            local c = W.COLOR.panel
            W.colorTexture(strip, c[1], c[2], c[3], 1)
        end
    end
    local body = part(win, "MinimizeContainer") or win
    quiet(part(body, "Background"))
    backdrop(body, W.COLOR.window, Meter.BackdropAlpha())

    local minimize = part(win, "MinimizeButton")
    if minimize then pcall(M.FlatMarked, minimize, "-") end
    local session = part(win, "SessionDropdown")
    if session then
        quiet(part(session, "Background"))
        pcall(M.Flat, session, W.COLOR.panel, 0)
    end

    local source = part(body, "SourceWindow")
    if source then
        quiet(part(source, "Background"))
        backdrop(source, W.COLOR.window, 0.95)
        local close = part(source, "CloseButton")
        if close then pcall(M.FlatMarked, close, "x") end
    end

    if not hooked[win] then
        hooked[win] = true
        local function pass() Meter.Pass(win) end
        for _, box in ipairs({ part(body, "ScrollBox") or false, source and part(source, "ScrollBox") or false }) do
            if box and hooksecurefunc and type(box.Update) == "function" then pcall(hooksecurefunc, box, "Update", pass) end
        end
        if type(win.HookScript) == "function" then pcall(win.HookScript, win, "OnShow", pass) end
    end
    return dressEntries(win)
end

---------------------------------------------------------------------------
-- The meter on its mover
---------------------------------------------------------------------------

local placing = false

-- The frame the game keeps the meter's first window on.
local function system()
    local f = _G.DamageMeter
    return type(f) == "table" and type(f.GetObjectType) == "function" and f or nil
end

-- A frame the game's edit mode looks after may have its ClearAllPoints (and SetPoint)
-- replaced by the game's own, with the plain ones kept beside them: the addon uses the plain
-- ones where there are any, so that the edit mode has no part in this.
local function plain(f, method)
    local base = rawget(f, method .. "Base")
    if type(base) == "function" then return base end
    return f[method]
end

local function measure(f, method)
    if type(f[method]) ~= "function" then return nil end
    local ok, v = pcall(f[method], f)
    return ok and type(v) == "number" and v or nil
end

-- How the meter is fastened to its mover: by its top left corner, its size left to the game.
local function wantedPoints(box)
    return { { "TOPLEFT", box, "TOPLEFT", 0, 0 } }
end

-- The meter's mover: the size the meter has now, and until it is dragged, where the game
-- had the meter when the addon first looked.
local function mover(f)
    local width, height = measure(f, "GetWidth"), measure(f, "GetHeight")
    if not (width and width > 0) then width = 400 end
    if not (height and height > 0) then height = 140 end
    if not Meter.home then
        local left, bottom = measure(f, "GetLeft"), measure(f, "GetBottom")
        Meter.home = (left and bottom) and { "BOTTOMLEFT", math.floor(left + 0.5), math.floor(bottom + 0.5) } or { "CENTER", -250, 19 }
    end
    return ns.Overhaul.Mover("meter", "Damage meter", width, height, Meter.home)
end

-- Puts the meter on its mover. Left alone while the game's own edit mode is open.
function Meter.Place()
    local f = system()
    if not (f and on()) or placing then return false end
    if ns.Overhaul.GameEditing() then return false end
    placing = true
    -- how the game had it fastened, for when the skin is switched off
    if not Meter.wasAt then
        local points = {}
        local n = measure(f, "GetNumPoints") or 0
        for i = 1, n do
            local ok, point, to, toPoint, x, y = pcall(f.GetPoint, f, i)
            if ok and type(point) == "string" then points[#points + 1] = { point, to, toPoint, x, y } end
        end
        Meter.wasAt = points
    end
    local box = mover(f)   -- measured before the meter is taken off its points
    pcall(plain(f, "ClearAllPoints"), f)
    for _, p in ipairs(wantedPoints(box)) do pcall(plain(f, "SetPoint"), f, p[1], p[2], p[3], p[4], p[5]) end
    placing = false
    if not hooked[f] then
        hooked[f] = true
        if hooksecurefunc and type(f.SetPoint) == "function" then
            pcall(hooksecurefunc, f, "SetPoint", function()
                if not placing and on() then Meter.Place() end
            end)
        end
    end
    return true
end

-- Is the meter still on its mover, by that one point and no other? Returns true when it had
-- to be put back. Not while the game's own edit mode is open, nor with a mouse button down.
function Meter.CheckPlace()
    local f = system()
    if not (f and on()) then return false end
    if ns.Overhaul.GameEditing() then return false end
    if IsMouseButtonDown and IsMouseButtonDown() then return false end
    local box = ns.Overhaul.movers.meter
    if box and box.off ~= true and ns.Overhaul.Fastened(f, wantedPoints(box)) then
        mover(f)   -- the box follows the meter's size
        return false
    end
    return Meter.Place()
end

-- The meter back where the game had it fastened, its mover put away.
local function release()
    ns.Overhaul.HideMover("meter")
    local f = system()
    if not (f and Meter.wasAt and #Meter.wasAt > 0) then return end
    placing = true
    pcall(plain(f, "ClearAllPoints"), f)
    for _, p in ipairs(Meter.wasAt) do pcall(plain(f, "SetPoint"), f, p[1], p[2] or UIParent, p[3], p[4], p[5]) end
    placing = false
end

---------------------------------------------------------------------------
-- The overhaul's hooks
---------------------------------------------------------------------------

-- The meter's windows this client has right now.
function Meter.Find()
    local found = {}
    for i = 1, Meter.WINDOWS_MOST do
        local win = _G["DamageMeterSessionWindow" .. i]
        if type(win) == "table" and type(win.GetObjectType) == "function" then found[#found + 1] = win end
    end
    Meter.windows = found
    return found
end

-- Dresses every window there is (the game makes them when the meter is switched on, and a
-- second and third when you ask for them). Returns how many windows there are.
function Meter.Check()
    if not on() then return 0 end
    local found = Meter.Find()
    for _, win in ipairs(found) do pcall(ns.Menus.As, "meter", dressWindow, win) end
    Meter.CheckPlace()
    return #found
end

-- The size of the bars' text right now: what was chosen, or what the game has.
function Meter.FontSize()
    local size = chosenSize()
    if size then return size end
    return math.floor((Meter.gameTextSize or 12) + 0.5)
end

function Meter.Apply()
    if not (ns.Menus and ns.Menus.Flat) then error("the window dressing code did not load") end
    ns.Menus.SetOff("meter", false)
    Meter.applied = true
    Meter.Check()
    if not Meter.events then
        -- The meter may not be there yet (it is switched on in the game's options), and its
        -- other windows come and go: a look once a second.
        Meter.events = CreateFrame("Frame")
        local elapsed = 0
        Meter.events:SetScript("OnUpdate", function(_, dt)
            elapsed = elapsed + (type(dt) == "number" and dt or 0)
            if elapsed < 1 then return end
            elapsed = 0
            Meter.Check()
        end)
    end
end

function Meter.OnEnteringWorld()
    Meter.Check()
end

-- A setting on the Meter page changed: the windows are dressed again, at once.
function Meter.OnSettingsChanged(path)
    if type(path) == "string" and path:match("^meter%.") then Meter.Check() end
end

-- Switched off: the meter gets back what was changed on it.
function Meter.Unapply()
    Meter.applied = false
    ns.Menus.SetOff("meter", true)
    release()
end
