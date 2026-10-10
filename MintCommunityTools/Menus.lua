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
        border; the options window's category headings lose their banners;
      - item slots (in the bag windows, which Bags.lua dresses with the same code) are
        flat dark squares, the item's picture trimmed to them, with the border in the colour
        of the item's quality where the game drew a coloured frame; a coin box loses its
        frame.

    How: a window's art is made invisible (alpha 0; the game sets the pictures again when a
    button is pressed, but not their alpha), and a background and four 1px edges are drawn
    as textures on the frame itself. The game's frames are not given the addon's backdrop
    and nothing is written into them: what was done to a frame is remembered in tables of
    the addon's own. Parts are found by the fields the game keeps them in (NineSlice, Border,
    Bg, Header, Inset, Left/Middle/Right, Track, Thumb, Arrow) and by what kind of widget a
    frame is, not by texture names, which differ between clients. What kind each control is
    was read from this client with /mint uidump menus.

    Everything done to a frame can be undone, so that a piece can be switched off without a
    reload. Each change is made under the name of the piece making it (the game menu's
    windows, the bag windows and the cast bars all use this file), and the first time
    something of the game's is changed, how to put it back is written down: the alpha a
    texture had, the picture and place a tick had, the font a button had. Switching a piece
    off runs what was written down for it and hides the addon's own textures; the hooks the
    addon put on the game's frames stay (a hook cannot be taken off) and do nothing while
    their piece is off. Switching it on again dresses the same frames again.

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
    -- the game's edit mode: the box of settings for whatever is clicked there (the damage
    -- meter's bar height and the like), and its dialogs
    "EditModeSystemSettingsDialog", "EditModeNewLayoutDialog", "EditModeImportLayoutDialog", "EditModeImportLayoutLinkDialog",
    "EditModeUnsavedChangesDialog",
    -- the game's own windows, from the micro menu: seen in /mint uidump on build 70334
    "CharacterFrame", "WorldMapFrame", "CommunitiesFrame", "SocialUIFrame", "ProfessionsFrame", "LegacySystemFrame",
    "PlayerSpellsFrame",
}
Menus.WINDOWS = WINDOWS
-- Parts of a window that hold nothing but background art (a stone wall behind the character,
-- the map's frame and its row of place names, the friends window's fades): every texture on
-- them is made invisible. A name with a dot is a field of the window, else a global name.
local ART_HOLDERS = {
    CharacterFrame = { "CharacterFrameLeftPaneHost", "CharacterFrameRightPaneHost" },
    WorldMapFrame = { ".BorderFrame", ".OverscrollBG", ".navBar", ".navBar.overlay", ".TitleCanvasSpacerFrame",
                      "QuestScrollFrame", "QuestScrollFrame.BorderFrame", "QuestLogCount" },
    SocialUIFrame = { ".BattleNetBar", ".BattleNetBar.ControlsContainer", ".FriendsList" },
    CommunitiesFrame = { "CommunitiesFrameCommunitiesList", "CommunitiesFrameCommunitiesList.FilligreeOverlay",
                         "ClubFinderGuildFinderFrame.DisabledFrame" },
    LegacySystemFrame = { ".RewardTrackPage", ".TreePage", ".TreePage.LegacyTreePointSummary", ".TreePage.VerticalDivider",
                          ".ChallengesPage.VerticalDivider" },
    -- the Talents page is unseen (it opens at level 10): its own art is swept like the Legacy
    -- window's tree page, which is built from the same parts; its talent nodes are left alone
    PlayerSpellsFrame = { ".SpellBookFrame", ".TalentsFrame" },
}
-- Parts of a window that are left entirely alone: the map itself and the pins on it.
local LEAVE = {
    WorldMapFrame = { ".ScrollContainer", ".BlackoutFrame" },
    CharacterFrame = { "CharacterModelScene" },
}
-- Parts whose buttons are flat whatever their art is kept in: the map's row of place names.
local PLAIN_BUTTONS = {
    WorldMapFrame = { ".navBar" },
}
-- Buttons with a picture for a face that mean one thing: a flat square with a mark on it.
local EXTRA_MARKS = {
    WorldMapFrame = { { ".SidePanelToggle.CloseButton", ">", 6 }, { ".SidePanelToggle.OpenButton", "<", 6 } },
    CharacterFrame = { { "CharacterFrameRightPaneToggleButton", "=", 4 } },
    PlayerSpellsFrame = { { ".SpellBookFrame.PagedSpellsFrame.PagingControls.PrevPageButton", "<", 8 },
                          { ".SpellBookFrame.PagedSpellsFrame.PagingControls.NextPageButton", ">", 8 } },
}
-- Windows that fill themselves again while they are open: dressed again after these.
local REFILLS = {
    EditModeSystemSettingsDialog = { "UpdateSettings", "UpdateButtons", "UpdateExtraButtons", "AttachToSystemFrame" },
}
-- Windows that fill themselves again while they stay open, through functions the addon has
-- no name for (a page of the spellbook sorted or turned, a list of friends refreshed): while
-- one of these is shown it is dressed again every so often. Dressing is cheap and does
-- nothing twice.
local REDRESS_SHOWN = { "PlayerSpellsFrame", "CharacterFrame", "CommunitiesFrame", "SocialUIFrame", "ProfessionsFrame",
                        "LegacySystemFrame", "WorldMapFrame" }
Menus.REDRESS_EVERY = 2
-- The parts of a window its art is kept in. A part may be a frame or a single texture.
local PARTS = { "NineSlice", "Border", "BorderBox", "Bg", "BG", "Background", "Inset", "Header", "TopTileStreaks", "PortraitContainer", "TitleBg" }
local CLOSE = { "CloseButton", "ClosePanelButton" }
local MAX_DEPTH, MAX_FRAMES = 6, 1500
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

---------------------------------------------------------------------------
-- Whose change it is, and how to undo it
---------------------------------------------------------------------------

local rememberPicture      -- defined further down, with the controls it is for
local OWNER = "menus"      -- the piece whose frames are being dressed right now
local off = {}             -- piece -> true while it is switched off
local undo = {}            -- piece -> the functions that put back what it changed, in order
local noted = setmetatable({}, { __mode = "k" })   -- object -> { kind = true }: already written down

-- Writes down how to put one thing back, once for each object and kind of change.
local function remember(obj, kind, fn)
    local kinds = noted[obj]
    if not kinds then
        kinds = {}
        noted[obj] = kinds
    end
    if kinds[kind] then return false end
    kinds[kind] = true
    undo[OWNER] = undo[OWNER] or {}
    undo[OWNER][#undo[OWNER] + 1] = fn
    return true
end

-- Runs `fn` as the piece `owner`: what it changes is that piece's to undo.
function Menus.As(owner, fn, ...)
    local before = OWNER
    OWNER = owner
    local results = { pcall(fn, ...) }
    OWNER = before
    if not results[1] then error(results[2], 0) end
    return unpack(results, 2)
end

function Menus.IsOff(owner)
    return off[owner] == true
end

-- Switches a piece off (everything it changed is put back, its hooks go quiet) or on again
-- (its frames are dressed again by whoever calls this).
function Menus.SetOff(owner, isOff)
    if not isOff then
        off[owner] = nil
        return
    end
    off[owner] = true
    for _, fn in ipairs(undo[owner] or {}) do pcall(fn) end
end

-- For another file to write down an undo of its own, under the piece being dressed.
function Menus.Remember(obj, kind, fn)
    return remember(obj, kind, fn)
end

-- Makes a texture of the game's invisible, writing down the alpha it had.
local function hide(tex)
    if type(tex) ~= "table" or type(tex.SetAlpha) ~= "function" then return end
    local alpha = 1
    if type(tex.GetAlpha) == "function" then
        local ok, a = pcall(tex.GetAlpha, tex)
        if ok and type(a) == "number" then alpha = a end
    end
    remember(tex, "alpha", function() pcall(tex.SetAlpha, tex, alpha) end)
    pcall(tex.SetAlpha, tex, 0)
end
Menus.Hide = hide

-- Every texture drawn on a frame, other than the addon's own, made invisible. Returns how many.
local function sweep(f)
    if type(f) ~= "table" then return 0 end
    local n = 0
    for _, r in ipairs(list(f.GetRegions, f)) do
        if isType(r, "Texture") and not own[r] then
            hide(r)
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
-- The addon's own textures on a frame, shown or hidden together.
local function showDress(d, shown)
    local parts = { d.bg, d.mark }
    for _, e in ipairs(d.edges) do parts[#parts + 1] = e end
    for _, p in pairs(parts) do
        if type(p) == "table" then
            if shown then pcall(p.Show, p) else pcall(p.Hide, p) end
        end
    end
    d.hidden = not shown
end

local function flat(f, bg, inset)
    local d = dressed[f]
    if d then
        if d.hidden then showDress(d, true) end   -- its piece was off and is on again
        return d
    end
    if type(f.CreateTexture) ~= "function" then return nil end
    local W = ns.W
    local px = W.pixel()
    -- the panel sits `inset` in from the frame's sides: one number for all four, or
    -- { left, right, top, bottom } (a tab whose art fills only the bottom of its button)
    local i = inset or 0
    local left, right, top, bottom = i, i, i, i
    if type(i) == "table" then left, right, top, bottom = i[1] or 0, i[2] or 0, i[3] or 0, i[4] or 0 end
    d = { edges = {}, inset = i }
    d.bg = f:CreateTexture(nil, "BACKGROUND", nil, -8)
    d.bg:SetPoint("TOPLEFT", f, "TOPLEFT", left, -top)
    d.bg:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -right, bottom)
    W.colorTexture(d.bg, bg[1], bg[2], bg[3], bg[4])
    own[d.bg] = true
    local spans = {
        { "TOPLEFT", "TOPRIGHT", "SetHeight" }, { "BOTTOMLEFT", "BOTTOMRIGHT", "SetHeight" },
        { "TOPLEFT", "BOTTOMLEFT", "SetWidth" }, { "TOPRIGHT", "BOTTOMRIGHT", "SetWidth" },
    }
    local at = { TOPLEFT = { left, -top }, TOPRIGHT = { -right, -top }, BOTTOMLEFT = { left, bottom }, BOTTOMRIGHT = { -right, bottom } }
    for n, span in ipairs(spans) do
        local e = f:CreateTexture(nil, "BORDER", nil, 7)
        e:SetPoint(span[1], f, span[1], at[span[1]][1], at[span[1]][2])
        e:SetPoint(span[2], f, span[2], at[span[2]][1], at[span[2]][2])
        e[span[3]](e, px)
        own[e] = true
        d.edges[n] = e
    end
    local b = W.COLOR.border
    setEdges(d, b[1], b[2], b[3], b[4])
    d.hidden = false
    dressed[f] = d
    remember(f, "dress", function() showDress(d, false) end)
    return d
end

-- For the other files that dress a frame of the game's (the cast bars).
Menus.Flat = flat

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
    local owner = OWNER
    pcall(b.HookScript, b, "OnEnter", function(self)
        if off[owner] then return end
        local d = dressed[self]
        if d then setEdges(d, ns.W.accent()) end
    end)
    pcall(b.HookScript, b, "OnLeave", function(self)
        if off[owner] then return end
        restEdges(self)
    end)
end

-- A push button of the game's: its art gone, a flat square in its place, the border in the
-- accent colour under the mouse. A tab is the same, with the open one's border lit.
-- A tab's art sometimes fills only the bottom of its button (the Options window's Base and
-- Raid tabs: 23px of art on a 37px button), and the tabs sit edge to edge. A flat panel the
-- size of the button would run over the tab beside it: the panel is drawn where the art was.
local function tabInsets(b)
    local art = isType(b.Middle, "Texture") and b.Middle or (isType(b.Center, "Texture") and b.Center)
    if not art or type(art.GetHeight) ~= "function" or type(b.GetHeight) ~= "function" then return nil end
    local okA, artH = pcall(art.GetHeight, art)
    local okB, h = pcall(b.GetHeight, b)
    if not (okA and okB and type(artH) == "number" and type(h) == "number") or artH <= 0 or h - artH < 4 then return nil end
    return { 1, 1, h - artH, 0 }
end

local function flatButton(b)
    local W = ns.W
    sweep(b)
    local first = not dressed[b]
    local d = flat(b, W.COLOR.panel, isTab(b) and tabInsets(b) or nil)
    if not d then return false end
    if first then
        d.tab = isTab(b)
        hoverHooks(b)
        local owner = OWNER
        if type(b.HookScript) == "function" then
            -- The game shows a button's art again when it is shown, enabled or pressed.
            pcall(b.HookScript, b, "OnShow", function(self)
                if off[owner] then return end
                Menus.As(owner, sweep, self)
                restEdges(self)
            end)
            if d.tab then
                -- Which tab is open has changed by the time this runs.
                pcall(b.HookScript, b, "OnClick", function(self)
                    if off[owner] then return end
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

-- A small button of the game's whose art is a picture rather than a frame (a bag's sort
-- button, the menu behind a window's portrait): its art gone, a flat square with a word or a
-- letter on it, `inset` in from the button's sides when the button is larger than it looks.
function Menus.FlatMarked(b, text, inset)
    if not isType(b, "Button") then return false end
    sweep(b)
    if not flat(b, ns.W.COLOR.panel, inset) then return false end
    mark(b, text, "CENTER", 0)
    hoverHooks(b)
    return true
end

-- A close button: a flat square with an x. One that says "Close" keeps its word.
local function flatClose(b)
    if not isType(b, "Button") then return false end
    if not flatButton(b) then return false end
    if not hasText(b) then mark(b, "x", "CENTER", 0) end
    return true
end

-- Writes down a texture's picture, colour and place before the addon gives it its own, so
-- that it can have them back: a tick, a slider's thumb, a list entry's bar.
rememberPicture = function(t, holder)
    if noted[t] and noted[t].picture then return end
    local atlas = atlasOf(t)
    local texture
    if not atlas and type(t.GetTexture) == "function" then
        local ok, v = pcall(t.GetTexture, t)
        if ok and (type(v) == "string" or type(v) == "number") then texture = v end
    end
    local points = {}
    if type(t.GetNumPoints) == "function" then
        local ok, n = pcall(t.GetNumPoints, t)
        if ok and type(n) == "number" then
            for i = 1, n do
                local okPoint, point, rel, relPoint, x, y = pcall(t.GetPoint, t, i)
                if okPoint and type(point) == "string" then points[#points + 1] = { point, rel, relPoint, x, y } end
            end
        end
    end
    local width, height
    if type(t.GetSize) == "function" then
        local ok, w, h = pcall(t.GetSize, t)
        if ok and type(w) == "number" and type(h) == "number" then width, height = w, h end
    end
    remember(t, "picture", function()
        if atlas and type(t.SetAtlas) == "function" then pcall(t.SetAtlas, t, atlas)
        elseif texture then pcall(t.SetTexture, t, texture) end
        pcall(t.SetVertexColor, t, 1, 1, 1, 1)
        if #points > 0 then
            pcall(t.ClearAllPoints, t)
            for _, p in ipairs(points) do pcall(t.SetPoint, t, p[1], p[2], p[3], p[4], p[5]) end
        elseif holder then
            pcall(t.ClearAllPoints, t)
            pcall(t.SetAllPoints, t, holder)
        end
        if width then pcall(t.SetSize, t, width, height) end
    end)
end

-- A check box: the game's box art gone, a flat square the size the box was drawn at, and
-- the tick a block of the accent colour. A check button with an icon is something else (a
-- macro's picture, an action) and is left alone.
local function flatCheck(cb)
    if type(cb.Icon) == "table" or type(cb.icon) == "table" then return false end
    local checked = part(cb, "GetCheckedTexture")
    if not checked then return false end
    -- a check box is small; a large one is a card or a tab that happens to be a CheckButton
    local okW, w = pcall(cb.GetWidth, cb)
    local okH, h = pcall(cb.GetHeight, cb)
    if (okW and type(w) == "number" and w > 40) or (okH and type(h) == "number" and h > 40) then return false end
    local W = ns.W
    for _, getter in ipairs({ "GetNormalTexture", "GetPushedTexture", "GetHighlightTexture" }) do hide(part(cb, getter)) end
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
            rememberPicture(t, cb)
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
    if not (isType(b, "Button") and type(b.Background) == "table" and type(b.Text) == "table") then return false end
    if type(b.Arrow) == "table" then return true end
    local atlas = atlasOf(b.Background)
    return atlas ~= nil and atlas:lower():find("dropdown", 1, true) ~= nil
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
    if not isType(e, "EditBox") then return false end
    if isType(e.Background, "Texture") then return true end
    return type(e.Left) == "table" and type(e.Right) == "table" and type(e.Middle) == "table"
end

local function flatEdit(e)
    hide(e.Left); hide(e.Right); hide(e.Middle)
    if isType(e.Background, "Texture") then hide(e.Background) end
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
        d.hidden = false
        dressed[s] = d
        remember(s, "dress", function() showDress(d, false) end)
    elseif d.hidden then
        showDress(d, true)
    end
    local thumb = type(s.Thumb) == "table" and s.Thumb or part(s, "GetThumbTexture")
    if thumb then
        rememberPicture(thumb)
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

-- For the other files that dress a scroll bar of the game's (the chat windows').
function Menus.FlatScrollBar(f)
    if type(f) ~= "table" or not isScrollBar(f) then return false end
    return flatScrollBar(f)
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

-- An item slot: a button with a picture (icon) and the frame the game colours by the item's
-- quality (IconBorder). The slot's art goes for a flat dark square; the picture is trimmed of
-- its own rounded edge; and the quality's colour, which the game puts on IconBorder, goes on
-- the square's border instead: IconBorder is kept invisible, and watched.
--
-- An empty slot has a picture too: the game shows its empty-slot art through the icon (an
-- atlas with "slot" in its name) and puts the item's own picture there when one arrives. So
-- the icon is watched as well: invisible while it shows slot art, shown and trimmed while it
-- shows an item. It is not trimmed while it shows an atlas: that would cut a piece out of the
-- sheet the atlas is on.
local SLOT = { 0.03, 0.03, 0.03, 0.9 }

local function isItemButton(b)
    return isType(b, "Button") and type(b.IconBorder) == "table" and (type(b.icon) == "table" or type(b.Icon) == "table")
end

local function flatItemButton(b)
    hide(part(b, "GetNormalTexture"))
    for _, key in ipairs({ "NormalTexture", "ItemSlotBackground" }) do
        if type(b[key]) == "table" then hide(b[key]) end
    end
    local icon = type(b.icon) == "table" and b.icon or b.Icon
    local owner = OWNER
    local function picture()
        if off[owner] then return end
        local atlas = atlasOf(icon)
        if atlas and atlas:lower():find("slot", 1, true) then
            hide(icon)
        else
            if type(icon.SetAlpha) == "function" then pcall(icon.SetAlpha, icon, 1) end
            if type(icon.SetTexCoord) == "function" then pcall(icon.SetTexCoord, icon, 0.08, 0.92, 0.08, 0.92) end
        end
    end
    local first = not dressed[b]
    local d = flat(b, SLOT)
    if not d then return false end
    if first and hooksecurefunc then
        for _, method in ipairs({ "SetAtlas", "SetTexture" }) do
            if type(icon[method]) == "function" then pcall(hooksecurefunc, icon, method, picture) end
        end
    end
    -- off again: the picture untrimmed and showing, whatever it is of
    remember(icon, "trim", function()
        if type(icon.SetTexCoord) == "function" then pcall(icon.SetTexCoord, icon, 0, 1, 0, 1) end
        if type(icon.SetAlpha) == "function" then pcall(icon.SetAlpha, icon, 1) end
    end)
    picture()
    local border = b.IconBorder
    local function plain()
        if off[owner] then return end
        local c = ns.W.COLOR.border
        setEdges(d, c[1], c[2], c[3], c[4])
    end
    -- The border as the game has it now: its colour when it is showing, plain when it is not.
    local function follow()
        if off[owner] then return end
        local okShown, shown = pcall(border.IsShown, border)
        if okShown and shown == true and type(border.GetVertexColor) == "function" then
            local ok, r, g, bl = pcall(border.GetVertexColor, border)
            if ok and type(r) == "number" and type(g) == "number" and type(bl) == "number" then
                setEdges(d, r, g, bl, 1)
                return
            end
        end
        plain()
    end
    if first and hooksecurefunc then
        if type(border.SetVertexColor) == "function" then
            pcall(hooksecurefunc, border, "SetVertexColor", function(_, r, g, bl)
                if off[owner] then return end
                if type(r) == "number" and type(g) == "number" and type(bl) == "number" then setEdges(d, r, g, bl, 1) end
            end)
        end
        if type(border.Hide) == "function" then pcall(hooksecurefunc, border, "Hide", plain) end
        if type(border.Show) == "function" then pcall(hooksecurefunc, border, "Show", follow) end
        if type(border.SetShown) == "function" then pcall(hooksecurefunc, border, "SetShown", follow) end
    end
    hide(border)
    follow()
    return true
end

-- A coin box, or any small frame whose frame art is kept in a Border part of three pieces.
local function isBoxed(f)
    local border = f.Border
    if type(border) ~= "table" then return false end
    return isType(border.Left, "Texture") or isType(border.Middle, "Texture") or isType(border.Right, "Texture")
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
    local owner = OWNER
    rememberPicture(tex)
    local function paint(self)
        if off[owner] then return end
        local r, g, b = W.accent()
        pcall(self.SetTexture, self, W.WHITE)
        pcall(self.SetVertexColor, self, r, g, b, 0.25)
    end
    paint(tex)
    if painted[tex] then return end
    painted[tex] = true
    if hooksecurefunc and type(tex.SetAtlas) == "function" then pcall(hooksecurefunc, tex, "SetAtlas", paint) end
end

-- A side tab (the character window's, the professions window's): a frame with a Background
-- (the tab's shape), an Icon, and a SelectedTexture shown on the open one. The shape goes
-- for a flat square, the icon stays, and the open one's SelectedTexture is a faint wash of
-- the accent colour.
local function isSideTab(f)
    if not (isType(f.Background, "Texture") and isType(f.Icon, "Texture")) then return false end
    local atlas = atlasOf(f.Background)
    if atlas and atlas:lower():find("sidetab", 1, true) then return true end
    return not isType(f, "Button") and isType(f.SelectedTexture, "Texture")
end

local function flatSideTab(f)
    hide(f.Background)
    for _, key in ipairs({ "HighlightTexture", "TabGlow" }) do
        if isType(f[key], "Texture") then hide(f[key]) end
    end
    if isType(f.SelectedTexture, "Texture") then paintBar(f.SelectedTexture) end
    local d = flat(f, ns.W.COLOR.panel, 2)
    if d and isType(f, "Button") then hoverHooks(f) end
    return d ~= nil
end

-- Does any texture of the frame's wear an atlas with this word in its name?
local function wears(f, word)
    for _, r in ipairs(list(f.GetRegions, f)) do
        if isType(r, "Texture") and not own[r] then
            local atlas = atlasOf(r)
            if atlas and atlas:lower():find(word, 1, true) then return true end
        end
    end
    return false
end

-- Every texture of the frame's wearing an atlas with this word in its name is made invisible.
local function hideWearing(f, word)
    local n = 0
    for _, r in ipairs(list(f.GetRegions, f)) do
        if isType(r, "Texture") and not own[r] then
            local atlas = atlasOf(r)
            if atlas and atlas:lower():find(word, 1, true) then
                hide(r)
                n = n + 1
            end
        end
    end
    return n
end

-- A heading in a list that folds (the character's statistics, the quest log, the friends
-- list): a button drawn with the "collapseExpand" strip. The strip goes; its name and its
-- plus or minus stay.
local function isListHeader(b)
    return isType(b, "Button") and wears(b, "collapseexpand")
end

local function flatListHeader(b)
    hideWearing(b, "collapseexpand")
    local d = flat(b, ns.W.COLOR.panel)
    if d then hoverHooks(b) end
    return d ~= nil
end

-- A card (a friend in the friends list, a profession on the professions page): a frame or
-- button with a "card" picture behind it. The picture goes for a faint flat panel.
local function isCard(f)
    if not isType(f.Background, "Texture") then return false end
    local atlas = atlasOf(f.Background)
    return atlas ~= nil and atlas:lower():find("card", 1, true) ~= nil
end

local function flatCard(f)
    hideWearing(f, "card")
    hide(f.Background)
    local d = flat(f, NESTED)
    if d and isType(f, "Button") then hoverHooks(f) end
    return d ~= nil
end

-- A row in a scrolling list with a picture behind it (the guild window's list of communities):
-- a button, straight under a list's ScrollTarget, with a Background. The picture and whatever
-- lights up on the row go; its icon stays; a faint flat panel takes their place.
local function isListRow(b)
    if not (isType(b, "Button") and isType(b.Background, "Texture")) then return false end
    local parent = part(b, "GetParent")
    local list_ = parent and part(parent, "GetParent")
    return list_ ~= nil and list_.ScrollTarget == parent
end

local function flatListRow(b)
    local keep = {}
    for _, key in ipairs({ "Icon", "icon", "ActionIcon" }) do
        if isType(b[key], "Texture") then keep[b[key]] = true end
    end
    for _, r in ipairs(list(b.GetRegions, b)) do
        if isType(r, "Texture") and not own[r] and not keep[r] then hide(r) end
    end
    local d = flat(b, NESTED)
    if d then hoverHooks(b) end
    return d ~= nil
end

-- A row of the loot window (seen in /mint uidump on build 70334): a frame with a card picture
-- (NameFrame), a stroke around it (BorderFrame), the strokes lit when it is pointed at or
-- pressed, a rarity tag (QualityStripe) and the item's slot (Item) in it. The pictures go;
-- the item's name and rarity, and the slot with its quality border, stay.
local LOOT_CARD_ART = { "NameFrame", "BorderFrame", "HighlightNameFrame", "PushedNameFrame", "QualityStripe" }
local function isLootCard(f)
    return isType(f.NameFrame, "Texture") and isType(f.Item, "Button")
end

local function flatLootCard(f)
    for _, key in ipairs(LOOT_CARD_ART) do
        if isType(f[key], "Texture") then hide(f[key]) end
    end
    return flat(f, NESTED) ~= nil
end

-- A tab with a picture on it (the spellbook's): a button with an Icon on a SquareBackground,
-- and a SquareBackgroundActive lit on the open one. The square goes for a flat one, the icon
-- stays, the open one is washed in the accent colour.
local function isIconTab(b)
    return isType(b, "Button") and isType(b.Icon, "Texture") and isType(b.SquareBackground, "Texture")
end

local function flatIconTab(b)
    hide(b.SquareBackground)
    if isType(b.SquareBackgroundActiveGlow, "Texture") then hide(b.SquareBackgroundActiveGlow) end
    if isType(b.SquareBackgroundActive, "Texture") then paintBar(b.SquareBackgroundActive) end
    local d = flat(b, ns.W.COLOR.panel, 2)
    if d then hoverHooks(b) end
    return d ~= nil
end

-- An entry on a page of the spellbook, and a heading there: a frame with a Backplate behind
-- it (and a Border that is a divider). The plate and the divider go; the spell's button,
-- whose frame says whether it is a spell or a passive, is left as it is.
local function isPlated(f)
    return isType(f.Backplate, "Texture")
end

local function flatPlated(f)
    hide(f.Backplate)
    local atlas = isType(f.Border, "Texture") and atlasOf(f.Border)
    if atlas and atlas:lower():find("divider", 1, true) then hide(f.Border) end
    return true
end

-- A small square button with a picture on it (the friends window's menu and party buttons,
-- the map's pin button): its frame art goes, the picture stays, a flat square takes its place.
local ICONS = { "Icon", "icon", "ActionIcon" }
local function isIconButton(b)
    if not isType(b, "Button") then return false end
    local icon = false
    for _, key in ipairs(ICONS) do
        if isType(b[key], "Texture") then icon = true end
    end
    if not icon then return false end
    if wears(b, "common-button") then return true end
    return isType(b.Border, "Texture") and isType(b.Background, "Texture")
end

local function flatIconButton(b)
    local keep = {}
    for _, key in ipairs(ICONS) do
        if isType(b[key], "Texture") then keep[b[key]] = true end
    end
    for _, r in ipairs(list(b.GetRegions, b)) do
        if isType(r, "Texture") and not own[r] and not keep[r] then hide(r) end
    end
    local d = flat(b, ns.W.COLOR.panel, 2)
    if d then hoverHooks(b) end
    return d ~= nil
end
Menus.FlatIconButton = flatIconButton

---------------------------------------------------------------------------
-- Everything inside a window
---------------------------------------------------------------------------

local dressInside

-- A scrolling list makes and reuses its rows as it scrolls: its rows are looked over each
-- time it lays itself out.
local function watchScrollBox(box)
    if hooked[box] then return end
    hooked[box] = true
    local owner = OWNER
    if hooksecurefunc and type(box.Update) == "function" then
        pcall(hooksecurefunc, box, "Update", function(self)
            if off[owner] then return end
            if type(self.ScrollTarget) == "table" then pcall(Menus.As, owner, dressInside, self.ScrollTarget, 1, { left = MAX_FRAMES, skip = {} }) end
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
            if isType(child, "CheckButton") and flatCheck(child) then
                n = n + 1
            elseif isSlider(child) then
                if flatSlider(child) then n = n + 1 end
            elseif isFramedEdit(child) then
                if flatEdit(child) then n = n + 1 end
                deeper = true
            elseif isItemButton(child) then
                if flatItemButton(child) then n = n + 1 end
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
            elseif isSideTab(child) then
                if flatSideTab(child) then n = n + 1 end
            elseif isListHeader(child) then
                if flatListHeader(child) then n = n + 1 end
                deeper = true
            elseif isCard(child) then
                if flatCard(child) then n = n + 1 end
                deeper = true
            elseif isListRow(child) then
                if flatListRow(child) then n = n + 1 end
                deeper = true
            elseif isLootCard(child) then
                if flatLootCard(child) then n = n + 1 end
                deeper = true
            elseif isIconTab(child) then
                if flatIconTab(child) then n = n + 1 end
            elseif isPlated(child) then
                if flatPlated(child) then n = n + 1 end
                deeper = true
            elseif isIconButton(child) then
                if flatIconButton(child) then n = n + 1 end
            else
                if isNineSlice(child) then
                    if flatPanel(child) then n = n + 1 end
                elseif isBoxed(child) then
                    clearPart(child.Border)
                    if flat(child, NESTED) then n = n + 1 end
                end
                if type(child.ScrollTarget) == "table" then
                    watchScrollBox(child)
                    -- the lines a list draws between its rows live in nameless frames of its own
                    for _, kid in ipairs(list(child.GetChildren, child)) do
                        if kid ~= child.ScrollTarget and isType(kid, "Frame") and not isType(kid, "Button") and part(kid, "GetName") == nil then
                            n = n + sweep(kid)
                        end
                    end
                end
                -- the strip lit under the mouse on a row
                if type(child.BackgroundHighlight) == "table" then n = n + sweep(child.BackgroundHighlight) end
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
    local seen = {}
    for _, child in ipairs(list(f.GetChildren, f)) do
        if isType(child, "Button") and child ~= f.CloseButton then
            if flatButton(child) then n = n + 1 end
            local text = type(child.GetText) == "function" and select(2, pcall(child.GetText, child))
            seen[#seen + 1] = (type(text) == "string" and text or "?") .. (dressed[child] and "" or " (not dressed)")
            if type(child.SetNormalFontObject) == "function" then
                local normal, highlight = part(child, "GetNormalFontObject"), part(child, "GetHighlightFontObject")
                remember(child, "font", function()
                    pcall(child.SetNormalFontObject, child, normal or "GameFontNormal")
                    pcall(child.SetHighlightFontObject, child, highlight or "GameFontHighlight")
                end)
                pcall(child.SetNormalFontObject, child, "GameFontHighlight")
                pcall(child.SetHighlightFontObject, child, "GameFontHighlight")
            end
        end
    end
    -- for /mint uidump: the menu's buttons come and go with it
    Menus.gameMenu = { buttons = seen, dressed = n }
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

-- Dresses one window, as the piece `owner` (the game menu's when not said). Returns
-- { art = textures made invisible, buttons = controls dressed }; nothing while that piece is off.
local dressWindow

function Menus.Dress(f, name, owner)
    owner = owner or "menus"
    if off[owner] then return { art = 0, buttons = 0 } end
    return Menus.As(owner, dressWindow, f, name)
end

dressWindow = function(f, name)
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
    -- a window whose frame is kept in a BorderFrame (the map): its parts are there
    local border = type(f.BorderFrame) == "table" and f.BorderFrame or nil
    if border then
        for _, key in ipairs(PARTS) do
            local p = border[key]
            if type(p) == "table" then
                skip[p] = true
                result.art = result.art + clearPart(p)
            end
        end
    end
    -- parts that hold nothing but art, parts left alone, parts whose buttons are all flat
    local function resolve(path)
        local cur = f
        local first = true
        for key in path:gmatch("[^%.]+") do
            if first and path:sub(1, 1) ~= "." then cur = frame(key) else cur = type(cur) == "table" and cur[key] or nil end
            first = false
            if type(cur) ~= "table" then return nil end
        end
        return cur
    end
    for _, path in ipairs(name and ART_HOLDERS[name] or {}) do
        local holder = resolve(path)
        if holder then
            result.art = result.art + sweep(holder)
            -- and the nameless frames in it that hold a line or two more
            for _, kid in ipairs(list(holder.GetChildren, holder)) do
                if isType(kid, "Frame") and not isType(kid, "Button") and part(kid, "GetName") == nil then result.art = result.art + sweep(kid) end
            end
        end
    end
    -- a window that can be made large or small: the two buttons for it, flat, with + and -
    local sizer = type(f.MaximizeMinimizeFrame) == "table" and f.MaximizeMinimizeFrame or type(f.MaximizeMinimizeButton) == "table" and f.MaximizeMinimizeButton
        or (border and border.MaximizeMinimizeFrame)
    if type(sizer) == "table" then
        for key, mark in pairs({ MaximizeButton = "+", MinimizeButton = "-" }) do
            local b = sizer[key]
            if type(b) == "table" then
                skip[b] = true
                if Menus.FlatMarked(b, mark) then result.buttons = result.buttons + 1 end
            end
        end
    end
    -- the few buttons a window keeps that look like nothing else
    for _, extra in ipairs(name and EXTRA_MARKS[name] or {}) do
        local b = resolve(extra[1])
        if b then
            skip[b] = true
            if Menus.FlatMarked(b, extra[2], extra[3]) then result.buttons = result.buttons + 1 end
        end
    end
    for _, path in ipairs(name and LEAVE[name] or {}) do
        local p = resolve(path)
        if p then skip[p] = true end
    end
    for _, path in ipairs(name and PLAIN_BUTTONS[name] or {}) do
        local holder = resolve(path)
        for _, child in ipairs(holder and list(holder.GetChildren, holder) or {}) do
            if isType(child, "Button") then
                skip[child] = true
                if flatButton(child) then result.buttons = result.buttons + 1 end
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
    if border then
        local b = name and frame(name .. "CloseButton")
        if b and not skip[b] then
            skip[b] = true
            if flatClose(b) then result.buttons = result.buttons + 1 end
        end
    end
    local named = name and frame(name .. "CloseButton")
    if named and not skip[named] then
        skip[named] = true
        if flatClose(named) then result.buttons = result.buttons + 1 end
    end
    -- The portrait is gone, and with it what showed there was a menu behind it: the button
    -- that opens that menu is drawn as a small flat square with a v.
    local portrait = type(f.PortraitButton) == "table" and f.PortraitButton or (name and frame(name .. "PortraitButton"))
    if portrait and not skip[portrait] then
        skip[portrait] = true
        if Menus.FlatMarked(portrait, "v", 10) then result.buttons = result.buttons + 1 end
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

-- Dresses the window of that name, and again each time it is shown; `methods` names
-- methods of the window after which it is dressed again too (a bag lays its items out anew).
local function dressNamed(name, methods, owner)
    local f = frame(name)
    if not f then return false end
    owner = owner or "menus"
    local ok, result = pcall(Menus.Dress, f, name, owner)
    if not ok then
        Menus.windows[name] = { error = tostring(result) }
        return false
    end
    Menus.windows[name] = result
    if not hooked[f] then
        hooked[f] = true
        if type(f.HookScript) == "function" then
            pcall(f.HookScript, f, "OnShow", function(self) pcall(Menus.Dress, self, name, owner) end)
        end
        -- The game menu fills itself with buttons through this, on a newer client.
        if name == "GameMenuFrame" and hooksecurefunc and type(f.InitButtons) == "function" then
            pcall(hooksecurefunc, f, "InitButtons", function(self) pcall(Menus.Dress, self, name, owner) end)
        end
        for _, method in ipairs(methods or {}) do
            if hooksecurefunc and type(f[method]) == "function" then
                pcall(hooksecurefunc, f, method, function(self) pcall(Menus.Dress, self, name, owner) end)
            end
        end
    end
    return true
end
Menus.DressNamed = dressNamed

-- Dresses every window that exists by now. Returns how many there are.
function Menus.DressAll()
    local n = 0
    for _, name in ipairs(WINDOWS) do
        if dressNamed(name, REFILLS[name]) then n = n + 1 end
    end
    return n
end

function Menus.Apply()
    Menus.SetOff("menus", false)
    Menus.applied = true
    Menus.count = Menus.DressAll()
    -- Some of these windows only exist once their part of the game's interface has loaded.
    if not Menus.events then
        Menus.events = CreateFrame("Frame")
        pcall(Menus.events.RegisterEvent, Menus.events, "ADDON_LOADED")
        Menus.events:SetScript("OnEvent", function()
            if Menus.applied then Menus.count = Menus.DressAll() end
        end)
        local elapsed = 0
        Menus.events:SetScript("OnUpdate", function(_, dt)
            elapsed = elapsed + (type(dt) == "number" and dt or 0)
            if elapsed < Menus.REDRESS_EVERY then return end
            elapsed = 0
            Menus.RedressShown()
        end)
    end
end

-- Dresses again every window of the REDRESS_SHOWN kind that is on screen. Returns how many.
function Menus.RedressShown()
    if not Menus.applied or off.menus then return 0 end
    local n = 0
    for _, name in ipairs(REDRESS_SHOWN) do
        local f = frame(name)
        if f and type(f.IsShown) == "function" then
            local ok, shown = pcall(f.IsShown, f)
            if ok and shown == true and pcall(Menus.Dress, f, name, "menus") then n = n + 1 end
        end
    end
    return n
end

function Menus.OnEnteringWorld()
    Menus.count = Menus.DressAll()
end

-- Switched off: every window gets back what was changed on it.
function Menus.Unapply()
    Menus.applied = false
    Menus.SetOff("menus", true)
end
