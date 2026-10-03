--[[
    Menus.lua - the game menu (Escape) and the windows it opens, in the flat skin.

    The game menu, and from it Options, AddOns, Edit Mode, Macros and Help, and the
    confirmation boxes the game pops up (logging out, quitting), are the game's own windows
    and stay so: nothing about what they do is touched. What changes is their dress:
      - the ornate border, the header art and the textured background are gone; the window
        is a flat dark panel with a 1px border, its title left as plain text;
      - push buttons are flat squares whose border lights up under the mouse; a close
        button is a flat square with an x;
      - tabs are flat, the one that is open marked by a border in the accent colour;
      - check boxes are flat squares that fill with the accent colour when ticked;
      - drop-downs and search boxes are flat panels; sliders are a thin bar with a flat
        thumb; scroll bars a thin dark track with a flat thumb;
      - framed areas inside a window (insets, text boxes) lose their frame art for a 1px
        border; the options window's category headings lose their banners.

    How: a window's art is made invisible (alpha 0; the game sets the pictures again when a
    button is pressed, but not their alpha), and a background and four 1px edges are drawn
    as textures on the frame itself. The game's frames are not given the addon's backdrop
    and nothing is written into them: what was done to a frame is remembered in tables of
    the addon's own. Parts are found by the fields the game keeps them in (NineSlice, Border,
    Bg, Header, Inset, Left/Middle/Right, Track, Thumb, Arrow) and by what kind of widget a
    frame is, not by texture names, which differ between clients. What kind each control is
    was read from this client with /mint uidump menus.

    A window that only exists once it has been opened (Macros) is dressed when its code
    loads; every window is looked over again each time it is shown, since the game makes
    some buttons anew then; and a scrolling list is looked over each time it lays itself
    out, since it makes and reuses its rows as it scrolls.
]]

local ADDON, ns = ...
local Menus = {}
ns.Menus = Menus

local ipairs, pairs, type, pcall = ipairs, pairs, type, pcall
local floor = math.floor

-- The windows, by the global names they have had.
local WINDOWS = {
    "GameMenuFrame", "SettingsPanel", "AddonList", "EditModeManagerFrame", "MacroFrame", "MacroPopupFrame", "HelpFrame",
    "InterfaceOptionsFrame", "VideoOptionsFrame", "KeyBindingFrame",
    "StaticPopup1", "StaticPopup2", "StaticPopup3", "StaticPopup4",
}
Menus.WINDOWS = WINDOWS
-- The parts of a window its art is kept in. A part may be a frame or a single texture.
local PARTS = { "NineSlice", "Border", "BorderBox", "Bg", "BG", "Background", "Inset", "Header", "TopTileStreaks", "PortraitContainer", "TitleBg" }
local CLOSE = { "CloseButton", "ClosePanelButton" }
local MAX_DEPTH, MAX_FRAMES = 5, 800
local NESTED = { 0, 0, 0, 0.2 }      -- behind a framed area inside a window
local WINDOW = { 0.06, 0.06, 0.06, 0.95 }   -- behind a whole window: these are read, so nearly solid
local THUMB = { 0.45, 0.45, 0.45, 1 }

local own = setmetatable({}, { __mode = "k" })       -- texture or font string -> true: the addon's own
local dressed = setmetatable({}, { __mode = "k" })   -- frame -> { bg, edges = { ... } }
local hooked = setmetatable({}, { __mode = "k" })    -- frame -> true once its scripts are hooked
local painted = setmetatable({}, { __mode = "k" })   -- texture -> true once its picture is the addon's
Menus.dressed = dressed
Menus.windows = {}                                   -- name -> what was done to it

local function frame(name)
    local f = _G[name]
    return type(f) == "table" and f or nil
end

local function isType(obj, kind)
    if type(obj) ~= "table" or type(obj.IsObjectType) ~= "function" then return false end
    local ok, is = pcall(obj.IsObjectType, obj, kind)
    return ok and is == true
end

local function list(fn, obj)
    if type(fn) ~= "function" then return {} end
    local ok, items = pcall(function() return { fn(obj) } end)
    return ok and items or {}
end

-- What a getter of the game's gives, when it gives a table (a texture, a font string).
local function part(obj, getter)
    if type(obj[getter]) ~= "function" then return nil end
    local ok, v = pcall(obj[getter], obj)
    return ok and type(v) == "table" and v or nil
end

local function hide(tex)
    if type(tex) == "table" and type(tex.SetAlpha) == "function" then pcall(tex.SetAlpha, tex, 0) end
end

-- Every texture drawn on a frame, other than the addon's own, made invisible. Returns how many.
local function sweep(f)
    if type(f) ~= "table" then return 0 end
    local n = 0
    for _, r in ipairs(list(f.GetRegions, f)) do
        if isType(r, "Texture") and not own[r] then
            pcall(r.SetAlpha, r, 0)
            n = n + 1
        end
    end
    return n
end

-- A part of a window: a single texture is made invisible, a frame is swept (and its own
-- NineSlice and Bg with it).
local function clearPart(p)
    if type(p) ~= "table" then return 0 end
    if isType(p, "Texture") then
        hide(p)
        return 1
    end
    local n = sweep(p)
    for _, key in ipairs({ "NineSlice", "Bg" }) do
        local inner = p[key]
        if type(inner) == "table" then
            if isType(inner, "Texture") then hide(inner); n = n + 1 else n = n + sweep(inner) end
        end
    end
    return n
end

local function setEdges(d, r, g, b, a)
    for _, e in ipairs(d.edges) do ns.W.colorTexture(e, r, g, b, a) end
end

-- The flat dress: a background and four 1px edges, as textures on the frame itself, `inset`
-- in from its sides (a check box's square is smaller than the frame it is clicked on).
local function flat(f, bg, inset)
    local d = dressed[f]
    if d then return d end
    if type(f.CreateTexture) ~= "function" then return nil end
    local W = ns.W
    local px = W.pixel()
    local i = inset or 0
    d = { edges = {}, inset = i }
    d.bg = f:CreateTexture(nil, "BACKGROUND", nil, -8)
    d.bg:SetPoint("TOPLEFT", f, "TOPLEFT", i, -i)
    d.bg:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -i, i)
    W.colorTexture(d.bg, bg[1], bg[2], bg[3], bg[4])
    own[d.bg] = true
    local spans = {
        { "TOPLEFT", "TOPRIGHT", "SetHeight" }, { "BOTTOMLEFT", "BOTTOMRIGHT", "SetHeight" },
        { "TOPLEFT", "BOTTOMLEFT", "SetWidth" }, { "TOPRIGHT", "BOTTOMRIGHT", "SetWidth" },
    }
    local sign = { TOPLEFT = { 1, -1 }, TOPRIGHT = { -1, -1 }, BOTTOMLEFT = { 1, 1 }, BOTTOMRIGHT = { -1, 1 } }
    for n, span in ipairs(spans) do
        local e = f:CreateTexture(nil, "BORDER", nil, 7)
        e:SetPoint(span[1], f, span[1], sign[span[1]][1] * i, sign[span[1]][2] * i)
        e:SetPoint(span[2], f, span[2], sign[span[2]][1] * i, sign[span[2]][2] * i)
        e[span[3]](e, px)
        own[e] = true
        d.edges[n] = e
    end
    local b = W.COLOR.border
    setEdges(d, b[1], b[2], b[3], b[4])
    dressed[f] = d
    return d
end

---------------------------------------------------------------------------
-- Tabs
---------------------------------------------------------------------------

local function atlasOf(tex)
    if type(tex) ~= "table" or type(tex.GetAtlas) ~= "function" then return nil end
    local ok, name = pcall(tex.GetAtlas, tex)
    return ok and type(name) == "string" and name or nil
end

-- A tab is a push button with a second set of art for when it is the open one (LeftActive),
-- or whose art is called a tab.
local function isTab(b)
    if type(b.LeftActive) == "table" then return true end
    local atlas = atlasOf(b.Left)
    return atlas ~= nil and atlas:lower():find("tab", 1, true) ~= nil
end

local function tabIsOpen(b)
    if type(b.LeftActive) == "table" and type(b.LeftActive.IsShown) == "function" then
        local ok, shown = pcall(b.LeftActive.IsShown, b.LeftActive)
        if ok and shown == true then return true end
    end
    local atlas = atlasOf(b.Left)
    return atlas ~= nil and atlas:lower():find("active", 1, true) ~= nil
end

-- A button's border when the mouse is not on it: the accent colour on the open tab, black
-- on everything else.
local function restEdges(b)
    local d = dressed[b]
    if not d then return end
    if d.tab and tabIsOpen(b) then
        setEdges(d, ns.W.accent())
    else
        local c = ns.W.COLOR.border
        setEdges(d, c[1], c[2], c[3], c[4])
    end
end

local function restTabs(parent)
    for _, sibling in ipairs(list(parent.GetChildren, parent)) do
        if type(sibling) == "table" and dressed[sibling] and dressed[sibling].tab then restEdges(sibling) end
    end
end

---------------------------------------------------------------------------
-- One control
---------------------------------------------------------------------------

local function hoverHooks(b)
    if hooked[b] or type(b.HookScript) ~= "function" then return end
    hooked[b] = true
    pcall(b.HookScript, b, "OnEnter", function(self)
        local d = dressed[self]
        if d then setEdges(d, ns.W.accent()) end
    end)
    pcall(b.HookScript, b, "OnLeave", function(self) restEdges(self) end)
end

-- A push button of the game's: its art gone, a flat square in its place, the border in the
-- accent colour under the mouse. A tab is the same, with the open one's border lit.
local function flatButton(b)
    local W = ns.W
    sweep(b)
    local first = not dressed[b]
    local d = flat(b, W.COLOR.panel)
    if not d then return false end
    if first then
        d.tab = isTab(b)
        hoverHooks(b)
        if type(b.HookScript) == "function" then
            -- The game shows a button's art again when it is shown, enabled or pressed.
            pcall(b.HookScript, b, "OnShow", function(self) sweep(self); restEdges(self) end)
            if d.tab then
                -- Which tab is open has changed by the time this runs.
                pcall(b.HookScript, b, "OnClick", function(self)
                    local parent = part(self, "GetParent")
                    if parent then restTabs(parent) else restEdges(self) end
                end)
            end
        end
    end
    restEdges(b)
    return true
end
Menus.FlatButton = flatButton

-- Is this one of the game's push buttons? They are buttons whose art is three pieces kept
-- in fields: Left, Middle (or Center) and Right.
local function isPushButton(b)
    if not isType(b, "Button") then return false end
    if type(b.Left) ~= "table" or type(b.Right) ~= "table" then return false end
    if type(b.Middle) ~= "table" and type(b.Center) ~= "table" then return false end
    return true
end

local function hasText(b)
    if type(b.GetText) ~= "function" then return false end
    local ok, text = pcall(b.GetText, b)
    return ok and type(text) == "string" and text ~= ""
end

-- A mark of the addon's own on a control: the x on a close button, the v on a drop-down.
local function mark(b, text, point, x)
    local d = dressed[b]
    if not d or d.mark or type(b.CreateFontString) ~= "function" then return end
    local fs = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    fs:SetPoint(point, b, point, x, 0)
    fs:SetText(text)
    local c = ns.W.COLOR.text
    fs:SetTextColor(c[1], c[2], c[3], c[4])
    own[fs] = true
    d.mark = fs
end

-- A close button: a flat square with an x. One that says "Close" keeps its word.
local function flatClose(b)
    if not isType(b, "Button") then return false end
    if not flatButton(b) then return false end
    if not hasText(b) then mark(b, "x", "CENTER", 0) end
    return true
end

-- A check box: the game's box art gone, a flat square the size the box was drawn at, and
-- the tick a block of the accent colour. A check button with an icon is something else (a
-- macro's picture, an action) and is left alone.
local function flatCheck(cb)
    if type(cb.Icon) == "table" or type(cb.icon) == "table" then return false end
    local checked = part(cb, "GetCheckedTexture")
    if not checked then return false end
    local W = ns.W
    for _, getter in ipairs({ "GetNormalTexture", "GetPushedTexture", "GetHighlightTexture" }) do hide(part(cb, getter)) end
    if dressed[cb] then return true end
    local width = type(cb.GetWidth) == "function" and cb:GetWidth()
    if type(width) ~= "number" or width <= 0 then width = 24 end
    local inset = floor(width * 0.2 + 0.5)
    local d = flat(cb, W.COLOR.panel, inset)
    if not d then return false end
    local r, g, b = W.accent()
    local ticks = { { checked, r, g, b }, { part(cb, "GetDisabledCheckedTexture"), 0.5, 0.5, 0.5 } }
    for _, tick in ipairs(ticks) do
        local t = tick[1]
        if t then
            pcall(t.SetTexture, t, W.WHITE)
            pcall(t.SetVertexColor, t, tick[2], tick[3], tick[4], 1)
            pcall(t.ClearAllPoints, t)
            pcall(t.SetPoint, t, "TOPLEFT", cb, "TOPLEFT", inset + 3, -(inset + 3))
            pcall(t.SetPoint, t, "BOTTOMRIGHT", cb, "BOTTOMRIGHT", -(inset + 3), inset + 3)
            own[t] = true
        end
    end
    d.check = checked
    hoverHooks(cb)
    return true
end

-- A drop-down: a button with a Background, an Arrow and its Text.
local function isDropdown(b)
    return isType(b, "Button") and type(b.Arrow) == "table" and type(b.Background) == "table" and type(b.Text) == "table"
end

local function flatDropdown(b)
    hide(b.Background)
    hide(b.Arrow)
    if not flat(b, ns.W.COLOR.panel) then return false end
    mark(b, "v", "RIGHT", -6)
    hoverHooks(b)
    return true
end

-- A search box (or any edit box framed by three pieces).
local function isFramedEdit(e)
    return isType(e, "EditBox") and type(e.Left) == "table" and type(e.Right) == "table" and type(e.Middle) == "table"
end

local function flatEdit(e)
    hide(e.Left); hide(e.Right); hide(e.Middle)
    return flat(e, ns.W.COLOR.panel) ~= nil
end

-- A slider: the bar's art gone for a thin dark line, the thumb a small flat block.
local function isSlider(s)
    return isType(s, "Slider") and type(s.Left) == "table" and type(s.Right) == "table" and type(s.Middle) == "table"
end

local function flatSlider(s)
    local W = ns.W
    hide(s.Left); hide(s.Right); hide(s.Middle)
    local d = dressed[s]
    if not d then
        if type(s.CreateTexture) ~= "function" then return false end
        d = { edges = {} }
        d.bg = s:CreateTexture(nil, "BACKGROUND", nil, -8)
        d.bg:SetPoint("LEFT", s, "LEFT", 4, 0)
        d.bg:SetPoint("RIGHT", s, "RIGHT", -4, 0)
        d.bg:SetHeight(4)
        W.colorTexture(d.bg, 0, 0, 0, 0.6)
        own[d.bg] = true
        dressed[s] = d
    end
    local thumb = type(s.Thumb) == "table" and s.Thumb or part(s, "GetThumbTexture")
    if thumb then
        pcall(thumb.SetTexture, thumb, W.WHITE)
        pcall(thumb.SetVertexColor, thumb, THUMB[1] + 0.3, THUMB[2] + 0.3, THUMB[3] + 0.3, 1)
        pcall(thumb.SetSize, thumb, 8, 16)
        d.thumb = thumb
    end
    return true
end

-- A scroll bar: a Track with a Thumb on it. The track's art gone for a thin dark strip,
-- the thumb a flat block. The arrows at its ends are left.
local function isScrollBar(f)
    return type(f.Track) == "table" and (type(f.Back) == "table" or type(f.Forward) == "table" or type(f.Track.Thumb) == "table")
end

local function flatScrollBar(f)
    local W = ns.W
    local track = f.Track
    for _, key in ipairs({ "Begin", "End", "Middle" }) do hide(track[key]) end
    flat(track, W.COLOR.panelPushed)
    local thumb = track.Thumb
    if type(thumb) == "table" then
        for _, key in ipairs({ "Begin", "End", "Middle" }) do hide(thumb[key]) end
        flat(thumb, THUMB)
        hoverHooks(thumb)
    end
    return true
end

-- A framed area inside a window: a frame whose border is nine pieces drawn on it. The
-- pieces go; a 1px border and a faint darkening take their place.
local function isNineSlice(f)
    return type(f.TopLeftCorner) == "table" or type(f.TopEdge) == "table"
end

local function flatPanel(f)
    sweep(f)
    return flat(f, NESTED) ~= nil
end

-- The options window's category list: a heading is a frame with a banner (Background) behind
-- its Label; an entry is a button whose bar (Texture) shows when it is open or under the mouse.
local function isListHeading(f)
    return not isType(f, "Button") and isType(f.Background, "Texture") and type(f.Label) == "table"
end

local function isListEntry(b)
    return isType(b, "Button") and isType(b.Texture, "Texture") and type(b.Label) == "table"
end

-- The entry's bar in the accent colour, faint, whatever picture the game gives it next.
local function paintBar(tex)
    local W = ns.W
    local function paint(self)
        local r, g, b = W.accent()
        pcall(self.SetTexture, self, W.WHITE)
        pcall(self.SetVertexColor, self, r, g, b, 0.25)
    end
    paint(tex)
    if painted[tex] then return end
    painted[tex] = true
    if hooksecurefunc and type(tex.SetAtlas) == "function" then pcall(hooksecurefunc, tex, "SetAtlas", paint) end
end

---------------------------------------------------------------------------
-- Everything inside a window
---------------------------------------------------------------------------

local dressInside

-- A scrolling list makes and reuses its rows as it scrolls: its rows are looked over each
-- time it lays itself out.
local function watchScrollBox(box)
    if hooked[box] then return end
    hooked[box] = true
    if hooksecurefunc and type(box.Update) == "function" then
        pcall(hooksecurefunc, box, "Update", function(self)
            if type(self.ScrollTarget) == "table" then pcall(dressInside, self.ScrollTarget, 1, { left = MAX_FRAMES, skip = {} }) end
        end)
    end
end

-- Dresses what is under a frame, a few levels down. Returns how many controls were dressed.
dressInside = function(f, depth, budget)
    local n = 0
    for _, child in ipairs(list(f.GetChildren, f)) do
        if budget.left <= 0 then break end
        budget.left = budget.left - 1
        if type(child) == "table" and not budget.skip[child] then
            local deeper = false
            if isType(child, "CheckButton") then
                if flatCheck(child) then n = n + 1 end
            elseif isSlider(child) then
                if flatSlider(child) then n = n + 1 end
            elseif isFramedEdit(child) then
                if flatEdit(child) then n = n + 1 end
                deeper = true
            elseif isPushButton(child) then
                if flatButton(child) then n = n + 1 end
            elseif isDropdown(child) then
                if flatDropdown(child) then n = n + 1 end
            elseif isScrollBar(child) then
                if flatScrollBar(child) then n = n + 1 end
            elseif isListEntry(child) then
                paintBar(child.Texture)
                n = n + 1
            elseif isListHeading(child) then
                hide(child.Background)
                flat(child, ns.W.COLOR.panel)
                n = n + 1
            else
                if isNineSlice(child) then
                    if flatPanel(child) then n = n + 1 end
                end
                if type(child.ScrollTarget) == "table" then watchScrollBox(child) end
                deeper = true
            end
            if deeper and depth < MAX_DEPTH then n = n + dressInside(child, depth + 1, budget) end
        end
    end
    return n
end
Menus.DressInside = function(f) return dressInside(f, 1, { left = MAX_FRAMES, skip = {} }) end

-- The game menu's own buttons are made anew each time it opens, and are all push buttons
-- whatever their art is kept in.
local function dressGameMenu(f)
    local n = 0
    for _, child in ipairs(list(f.GetChildren, f)) do
        if isType(child, "Button") and child ~= f.CloseButton then
            if flatButton(child) then n = n + 1 end
            if type(child.SetNormalFontObject) == "function" then
                pcall(child.SetNormalFontObject, child, "GameFontHighlight")
                pcall(child.SetHighlightFontObject, child, "GameFontHighlight")
            end
        end
    end
    return n
end

-- A confirmation box: its border and background are in BG; its buttons' art is not in
-- three pieces. Its own pictures (the alert icon, a progress bar) are left alone.
local function dressPopup(f, name)
    local n = 0
    local holder = type(f.ButtonContainer) == "table" and f.ButtonContainer or f
    for _, child in ipairs(list(holder.GetChildren, holder)) do
        if isType(child, "Button") then
            if flatButton(child) then n = n + 1 end
        end
    end
    local extra = frame(name .. "ExtraButton")
    if extra and flatButton(extra) then n = n + 1 end
    return n
end

-- Dresses one window. Returns { art = textures made invisible, buttons = controls dressed }.
function Menus.Dress(f, name)
    local W = ns.W
    local popup = type(name) == "string" and name:find("^StaticPopup%d") ~= nil
    local result = { art = popup and 0 or sweep(f), buttons = 0 }
    local skip = {}
    for _, key in ipairs(PARTS) do
        local p = f[key]
        if type(p) == "table" then
            skip[p] = true
            result.art = result.art + clearPart(p)
        end
    end
    if name then
        for _, suffix in ipairs({ "Inset", "Bg", "TitleBg" }) do
            local p = frame(name .. suffix)
            if p then
                skip[p] = true
                result.art = result.art + clearPart(p)
            end
        end
    end
    flat(f, WINDOW)
    for _, key in ipairs(CLOSE) do
        local b = f[key]
        if type(b) == "table" then
            skip[b] = true
            if flatClose(b) then result.buttons = result.buttons + 1 end
        end
    end
    local named = name and frame(name .. "CloseButton")
    if named and not skip[named] then
        skip[named] = true
        if flatClose(named) then result.buttons = result.buttons + 1 end
    end
    if name == "GameMenuFrame" then
        result.buttons = result.buttons + dressGameMenu(f)
    elseif popup then
        result.buttons = result.buttons + dressPopup(f, name)
    else
        result.buttons = result.buttons + dressInside(f, 1, { left = MAX_FRAMES, skip = skip })
    end
    return result
end

local function dressNamed(name)
    local f = frame(name)
    if not f then return false end
    local ok, result = pcall(Menus.Dress, f, name)
    if not ok then
        Menus.windows[name] = { error = tostring(result) }
        return false
    end
    Menus.windows[name] = result
    if not hooked[f] then
        hooked[f] = true
        if type(f.HookScript) == "function" then
            pcall(f.HookScript, f, "OnShow", function(self) pcall(Menus.Dress, self, name) end)
        end
        -- The game menu fills itself with buttons through this, on a newer client.
        if name == "GameMenuFrame" and hooksecurefunc and type(f.InitButtons) == "function" then
            pcall(hooksecurefunc, f, "InitButtons", function(self) pcall(Menus.Dress, self, name) end)
        end
    end
    return true
end

-- Dresses every window that exists by now. Returns how many there are.
function Menus.DressAll()
    local n = 0
    for _, name in ipairs(WINDOWS) do
        if dressNamed(name) then n = n + 1 end
    end
    return n
end

function Menus.Apply()
    Menus.count = Menus.DressAll()
    -- Some of these windows only exist once their part of the game's interface has loaded.
    if not Menus.events then
        Menus.events = CreateFrame("Frame")
        pcall(Menus.events.RegisterEvent, Menus.events, "ADDON_LOADED")
        Menus.events:SetScript("OnEvent", function() Menus.count = Menus.DressAll() end)
    end
end

function Menus.OnEnteringWorld()
    Menus.count = Menus.DressAll()
end
