--[[
    UI.lua - the Mint Community Tools window, and the Gear tab.

    Opened with /mint or the minimap button. The window has one tab per feature, so each
    stays a page of its own as more are added:

      Gear   your character and every equipment slot as the addon sees it (hover a row for
             the item's tooltip), a summary line, and the export string to paste on the
             website's Roster page. Refreshes by itself when you change gear.
      Loot   what has dropped and who got it (LootUI.lua).
      Settings   the minimalist UI's switches (SettingsUI.lua).

    Style: flat and ElvUI-like, with none of Blizzard's frame art. Every window, panel,
    button and box is a WHITE8X8 backdrop with a 1px solid black border (one physical
    pixel at any UI scale), dark neutral panels, light grey text, dim grey labels, and one
    accent colour: the player's class colour when the client gives it, else a muted cyan.
    Windows are laid out top to bottom with a running y and size themselves to it, so
    nothing is drawn outside the backdrop.

    ns.W holds the skin and the widget helpers both tabs, the loot watcher and the minimap
    button use. Frames are created defensively: a template that does not exist on this
    client falls back to a bare frame, SetBackdrop is called under pcall, and nothing here
    does arithmetic on values read back from frames, so the window also builds under the
    test harness's stub frames. Only APIs a Classic client has are used (SetBackdrop via
    BackdropTemplate where BackdropTemplateMixin exists, SetBackdropColor,
    SetBackdropBorderColor, SetNormalFontObject, SetCheckedTexture, SetTextInsets,
    SetTextColor, SetVertexColor).
]]

local ADDON, ns = ...
local UI = {}
ns.UI = UI
local W = {}
ns.W = W

local ipairs, type, tostring, pcall = ipairs, type, tostring, pcall
local sformat = string.format

local WIDTH = 470
local PAD = 8                  -- window padding
local GAP = 4                  -- between controls
local TITLE_H = 20             -- the title strip
local BUTTON_H = 20
local STRIP_H = 18             -- column header strips
local ROW_HEIGHT = 18
local MIN_BOX_H = 110          -- the copy box is at least this tall; the taller tab decides the rest
local PANEL_TOP = -(TITLE_H + GAP + BUTTON_H + GAP)   -- below the title strip and the tab buttons
local NUM_ROWS = #ns.Collect.SLOTS

W.WIDTH, W.PAD, W.GAP, W.TITLE_H, W.BUTTON_H, W.STRIP_H, W.MIN_BOX_H = WIDTH, PAD, GAP, TITLE_H, BUTTON_H, STRIP_H, MIN_BOX_H
W.QUALITY_COLOR = { [0] = "9d9d9d", [1] = "ffffff", [2] = "1eff00", [3] = "0070dd", [4] = "a335ee", [5] = "ff8000" }
local QUALITY_COLOR = W.QUALITY_COLOR

local TABS = {
    { key = "gear", label = "Gear" },
    { key = "loot", label = "Loot" },
    { key = "settings", label = "Settings" },
}

local ui = {}   -- the widgets, also reached by the tests as ns.ui
ns.ui = ui
local current = "gear"

---------------------------------------------------------------------------
-- Skin (ns.W)
---------------------------------------------------------------------------

local WHITE = "Interface\\Buttons\\WHITE8X8"
W.WHITE = WHITE
local COLOR = {
    window = { 0.06, 0.06, 0.06, 0.85 },
    panel = { 0.10, 0.10, 0.10, 0.90 },
    panelHover = { 0.16, 0.16, 0.16, 0.95 },
    panelPushed = { 0.04, 0.04, 0.04, 0.95 },
    border = { 0, 0, 0, 1 },
    text = { 0.90, 0.90, 0.90, 1 },
    dim = { 0.55, 0.55, 0.55, 1 },
    error = { 1, 0.4, 0.4, 1 },
}
W.COLOR = COLOR
W.DIM_HEX = "8c8c8c"    -- the dim token, for inline |cff colour codes
W.TEXT_HEX = "e6e6e6"   -- the text token, the same way

-- The accent colour: the player's class colour, else a muted cyan.
function W.accent()
    if RAID_CLASS_COLORS and UnitClass then
        local ok, _, class = pcall(UnitClass, "player")
        local c = ok and type(class) == "string" and RAID_CLASS_COLORS[class]
        if type(c) == "table" and type(c.r) == "number" then return c.r, c.g, c.b, 1 end
    end
    return 0.35, 0.75, 0.85, 1
end
local accent = W.accent

-- One screen pixel in UI units, so the 1px borders stay 1px at any UI scale.
function W.pixel()
    if GetPhysicalScreenSize and UIParent and UIParent.GetEffectiveScale then
        local ok, _, h = pcall(GetPhysicalScreenSize)
        local ok2, scale = pcall(UIParent.GetEffectiveScale, UIParent)
        if ok and ok2 and type(h) == "number" and h > 0 and type(scale) == "number" and scale > 0 then
            return 768 / h / scale
        end
    end
    return 1
end

-- Newer clients need BackdropTemplate for SetBackdrop; older ones have it built in.
function W.template()
    return BackdropTemplateMixin and "BackdropTemplate" or nil
end

-- CreateFrame, but falls back to a template-less frame if the template does not exist here.
function W.safeCreate(frameType, name, parent, template)
    if template then
        local ok, f = pcall(CreateFrame, frameType, name, parent, template)
        if ok and f then return f end
    end
    return CreateFrame(frameType, name, parent)
end
local safeCreate = W.safeCreate

function W.setBg(frame, c)
    if frame.SetBackdropColor then pcall(frame.SetBackdropColor, frame, c[1], c[2], c[3], c[4]) end
end
local setBg = W.setBg

function W.setBorder(frame, r, g, b, a)
    if frame.SetBackdropBorderColor then pcall(frame.SetBackdropBorderColor, frame, r, g, b, a) end
end
local setBorder = W.setBorder

local function resetBorder(frame)
    setBorder(frame, COLOR.border[1], COLOR.border[2], COLOR.border[3], COLOR.border[4])
end

-- Turns any frame flat: a solid backdrop in `bg` (the window token by default) with a 1px
-- black border. Returns false when the client cannot draw backdrops on this frame.
function W.skin(frame, bg)
    if not frame.SetBackdrop and Mixin and BackdropTemplateMixin then pcall(Mixin, frame, BackdropTemplateMixin) end
    if not frame.SetBackdrop then return false end
    local ok = pcall(frame.SetBackdrop, frame, {
        bgFile = WHITE, edgeFile = WHITE, tile = false, tileSize = 0, edgeSize = W.pixel(),
        insets = { left = 0, right = 0, top = 0, bottom = 0 },
    })
    if not ok then return false end
    setBg(frame, bg or COLOR.window)
    resetBorder(frame)
    return true
end
local skin = W.skin

---------------------------------------------------------------------------
-- Widget helpers (ns.W)
---------------------------------------------------------------------------

-- A left-aligned font string in the text token colour (or `color`).
function W.fontString(parent, template, width, color)
    local fs = parent:CreateFontString(nil, "OVERLAY", template or "GameFontHighlightSmall")
    if width then fs:SetWidth(width) end
    fs:SetJustifyH("LEFT")
    local c = color or COLOR.text
    fs:SetTextColor(c[1], c[2], c[3], c[4])
    return fs
end
local fontString = W.fontString

function W.text(parent, str, color, font)
    local fs = fontString(parent, font, nil, color)
    fs:SetText(str or "")
    return fs
end

-- A header: the game's small gold font, recoloured to the text token.
function W.header(parent, str)
    return W.text(parent, str, COLOR.text, "GameFontNormalSmall")
end

-- A label, hint or piece of metadata, in the dim token.
function W.dim(parent, str, width)
    local fs = fontString(parent, "GameFontHighlightSmall", width, COLOR.dim)
    fs:SetText(str or "")
    return fs
end

function W.colorTexture(texture, r, g, b, a)
    if texture.SetColorTexture then texture:SetColorTexture(r, g, b, a) else texture:SetTexture(r, g, b, a) end
end

-- Every other row a touch lighter than the list panel it sits on.
function W.stripe(row, index)
    if index % 2 ~= 1 then return end
    local bg = row:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    W.colorTexture(bg, 1, 1, 1, 0.03)
end

-- A flat panel inside a window: a title strip, a column header strip, a list background.
function W.panel(parent, bg)
    local p = safeCreate("Frame", nil, parent, W.template())
    skin(p, bg or COLOR.panel)
    return p
end

-- A column header strip across the window at `y`: an 18px panel; put W.header texts on it.
function W.strip(parent, y)
    local p = W.panel(parent)
    p:SetPoint("TOPLEFT", PAD, y)
    p:SetPoint("TOPRIGHT", -PAD, y)
    p:SetHeight(STRIP_H)
    return p
end

-- A list background for `rows` rows of `rowHeight`, across the window at `y`, its top
-- border on the strip above it. W.listRow puts a row on it.
function W.list(parent, y, rows, rowHeight)
    local p = W.panel(parent)
    p:SetPoint("TOPLEFT", PAD, y + 1)
    p:SetPoint("TOPRIGHT", -PAD, y + 1)
    p:SetHeight(rows * rowHeight + 4)
    p.rowHeight = rowHeight
    return p
end

-- Row `index` of `list`, `width` wide: anchored just inside its border, striped.
function W.listRow(list, row, index, width, rowHeight)
    row:SetSize(width - 4, rowHeight)
    row:SetPoint("TOPLEFT", list, "TOPLEFT", 2, -2 - (index - 1) * rowHeight)
    W.stripe(row, index)
end

-- A flat button. `name` is the frame's global name (the tests find buttons by it).
function W.button(parent, name, text, width, onClick)
    local b = safeCreate("Button", name, parent, W.template())
    b:SetSize(width or 90, BUTTON_H)
    skin(b, COLOR.panel)
    b:SetNormalFontObject("GameFontHighlightSmall")
    b:SetDisabledFontObject("GameFontDisableSmall")
    b:SetText(text)
    b:SetScript("OnClick", onClick)
    b:SetScript("OnEnter", function(self) if not self.selected then setBorder(self, accent()) end end)
    b:SetScript("OnLeave", function(self) if not self.selected then resetBorder(self); setBg(self, COLOR.panel) end end)
    b:SetScript("OnMouseDown", function(self) if not self.selected then setBg(self, COLOR.panelPushed) end end)
    b:SetScript("OnMouseUp", function(self) if not self.selected then setBg(self, COLOR.panelHover) end end)
    return b
end
local button = W.button

-- Keeps a button's text inside the button: one line, cut short with dots when it is longer
-- than the button is wide (a font's name can be any length).
function W.fitText(b, width)
    local fs = type(b.GetFontString) == "function" and b:GetFontString()
    if type(fs) ~= "table" then return false end
    if type(width) ~= "number" then width = type(b.GetWidth) == "function" and b:GetWidth() end
    if type(width) ~= "number" or width <= 12 then return false end
    fs:SetWidth(width - 8)
    if fs.SetWordWrap then fs:SetWordWrap(false) end
    return true
end

-- How tall a font string is once its text is wrapped to `width`. The game says, once the
-- string has its width; where it does not (it gives nothing, or less than a line), the
-- height is worked out from the length of the text.
function W.textHeight(fs, text, width)
    local h = type(fs.GetStringHeight) == "function" and fs:GetStringHeight()
    if type(h) == "number" and h >= 9 then return h end
    local lines = math.max(1, math.ceil(#tostring(text or "") * 5.6 / width))
    return lines * 12
end

-- Marks a button as the selected one of a set (a tab): accent border, hover background,
-- and no hover or press effects until it is unselected.
function W.setSelected(b, selected)
    b.selected = selected and true or false
    if selected then
        setBorder(b, accent())
        setBg(b, COLOR.panelHover)
    else
        resetBorder(b)
        setBg(b, COLOR.panel)
    end
end

-- A flat check box: a 14px square that fills with the accent colour when checked, with its
-- label to the right. onClick gets true or false. Native GetChecked/SetChecked still work.
function W.checkbox(parent, name, text, onClick)
    local cb = safeCreate("CheckButton", name, parent, W.template())
    cb:SetSize(14, 14)
    skin(cb, COLOR.panel)
    local fill = cb:CreateTexture(nil, "ARTWORK")
    fill:SetTexture(WHITE)
    fill:SetVertexColor(accent())
    fill:SetPoint("TOPLEFT", cb, "TOPLEFT", 3, -3)
    fill:SetPoint("BOTTOMRIGHT", cb, "BOTTOMRIGHT", -3, 3)
    cb:SetCheckedTexture(fill)
    local hover = cb:CreateTexture(nil, "HIGHLIGHT")
    hover:SetTexture(WHITE)
    hover:SetVertexColor(1, 1, 1, 0.08)
    hover:SetAllPoints(cb)
    cb:SetHighlightTexture(hover)
    cb.label = W.text(parent, text)
    cb.label:SetPoint("LEFT", cb, "RIGHT", 4, 0)
    cb:SetScript("OnClick", function(self) if onClick then onClick(self:GetChecked() and true or false) end end)
    return cb
end

-- A flat single-line edit box. onCommit(text) on Enter and when focus is lost.
function W.editbox(parent, name, width, onCommit, onEscape)
    local e = safeCreate("EditBox", name, parent, W.template())
    e:SetSize(width, 18)
    skin(e, COLOR.panel)
    e:SetFontObject("GameFontHighlightSmall")
    e:SetTextColor(COLOR.text[1], COLOR.text[2], COLOR.text[3], COLOR.text[4])
    e:SetTextInsets(4, 4, 0, 0)
    e:SetAutoFocus(false)
    e:SetScript("OnEditFocusGained", function(self) setBorder(self, accent()) end)
    e:SetScript("OnEnterPressed", function(self) if onCommit then onCommit(self:GetText()) end; self:ClearFocus() end)
    e:SetScript("OnEscapePressed", function(self) self:ClearFocus(); if onEscape then onEscape() end end)
    e:SetScript("OnEditFocusLost", function(self)
        resetBorder(self)
        if onCommit then onCommit(self:GetText()) end
    end)
    return e
end

function W.clock(ts)
    if not ts then return "?" end
    return date and date("%H:%M", ts) or tostring(ts)
end

-- 12345 -> "12,345". A secret number (see UnitFrames.lua) can be shown but not read, so it
-- comes back as it is, without separators.
function W.commas(n)
    if issecretvalue and issecretvalue(n) then return tostring(n) end
    local s = tostring(n or 0)
    local out = s:reverse():gsub("(%d%d%d)", "%1,"):reverse()
    return (out:gsub("^,", ""))
end

-- A movable flat window with a title strip across the top: the title left-aligned, a dim
-- subtitle after it (f.subtitle, say the version), and a flat x on the right as f.close.
-- Content starts at -(W.TITLE_H + W.GAP); size the window to what you put in it.
function W.window(name, width, height, strata, title, subtitle)
    local f = safeCreate("Frame", name, UIParent, W.template())
    f:SetSize(width, height)
    f:SetPoint("CENTER")
    f:SetFrameStrata(strata or "DIALOG")
    f:SetClampedToScreen(true)
    f:EnableMouse(true)
    f:SetMovable(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    skin(f, COLOR.window)

    f.titleBar = W.panel(f)
    f.titleBar:SetPoint("TOPLEFT", 0, 0)
    f.titleBar:SetPoint("TOPRIGHT", 0, 0)
    f.titleBar:SetHeight(TITLE_H)
    f.title = W.header(f.titleBar, title or "")
    f.title:SetPoint("LEFT", f.titleBar, "LEFT", PAD, 0)
    f.subtitle = W.dim(f.titleBar, subtitle or "")
    f.subtitle:SetPoint("LEFT", f.title, "RIGHT", 6, 0)

    local close = button(f.titleBar, nil, "x", TITLE_H - 4, function() f:Hide() end)
    close:SetHeight(TITLE_H - 4)
    close:SetPoint("RIGHT", f.titleBar, "RIGHT", -2, 0)
    f.close = close
    return f
end

-- A read-only text box for copying: typing or pasting restores the text, selecting and
-- copying still work. box.Set(text) fills and selects it. A flat panel (box.frame) holds a
-- plain scroll frame; the mouse wheel scrolls it. Anchored at (left, top) to (right,
-- bottom) inside `parent`.
function W.copyBox(parent, name, left, top, right, bottom, onEscape)
    local frame = W.panel(parent)
    frame:SetPoint("TOPLEFT", left, top)
    frame:SetPoint("BOTTOMRIGHT", right, bottom)

    local scroll = CreateFrame("ScrollFrame", name .. "Scroll", frame)
    scroll:SetPoint("TOPLEFT", 4, -4)
    scroll:SetPoint("BOTTOMRIGHT", -4, 4)
    local edit = CreateFrame("EditBox", name .. "EditBox", scroll)
    edit:SetMultiLine(true)
    edit:SetAutoFocus(false)
    edit:SetFontObject(ChatFontNormal or GameFontHighlightSmall)
    edit:SetTextColor(COLOR.text[1], COLOR.text[2], COLOR.text[3], COLOR.text[4])
    edit:SetTextInsets(2, 2, 0, 0)
    edit:SetWidth(WIDTH - 2 * PAD - 12)
    edit:SetMaxLetters(0)
    scroll:SetScrollChild(edit)

    scroll:EnableMouseWheel(true)
    scroll:SetScript("OnMouseWheel", function(self, delta)
        local at, range = self:GetVerticalScroll(), self:GetVerticalScrollRange()
        if type(delta) ~= "number" or type(at) ~= "number" or type(range) ~= "number" then return end
        local to = at - delta * 30
        if to < 0 then to = 0 elseif to > range then to = range end
        self:SetVerticalScroll(to)
    end)

    local box = { frame = frame, scroll = scroll, editBox = edit, text = nil }
    function box.SelectAll()
        edit:SetFocus()
        edit:HighlightText()
    end
    function box.Set(text)
        box.text = text
        edit:SetText(text or "")
        if not text then return end
        box.SelectAll()
        -- Highlighting straight after SetText can be lost on some clients, so retry next frame.
        if C_Timer and C_Timer.After then
            C_Timer.After(0, function() if box.text == text then box.SelectAll() end end)
        end
    end
    edit:SetScript("OnEscapePressed", function() if onEscape then onEscape() end end)
    edit:SetScript("OnTextChanged", function(self, userInput)
        if userInput and box.text and self:GetText() ~= box.text then
            self:SetText(box.text)
            self:HighlightText()
        end
    end)
    edit:SetScript("OnEditFocusGained", function(self)
        setBorder(frame, accent())
        self:HighlightText()
    end)
    edit:SetScript("OnEditFocusLost", function() resetBorder(frame) end)
    return box
end

---------------------------------------------------------------------------
-- Gear tab: text
---------------------------------------------------------------------------

local DIM = "|cff" .. W.DIM_HEX
local SEP = "  " .. DIM .. "-|r  "

local function characterLine(c)
    local name = c.name or "?"
    if c.lastName then name = name .. " " .. c.lastName end
    local parts = { name }
    local desc = {}
    if c.level then desc[#desc + 1] = "Level " .. tostring(c.level) end
    if c.race then desc[#desc + 1] = c.race end
    if c.class then desc[#desc + 1] = c.class end
    if #desc > 0 then parts[#parts + 1] = table.concat(desc, " ") end
    if c.realm then
        local region = c.region or "?"
        if ns.Collect.regionSource == "assumed" then region = region .. ", assumed"
        elseif ns.Collect.regionSource == "beta client" then region = region .. ", beta" end
        parts[#parts + 1] = c.realm .. " (" .. region .. ")"
    end
    return table.concat(parts, SEP)
end

local function guildLine(c)
    if not c.guild then return DIM .. "Not in a guild|r" end
    return "<" .. c.guild .. ">" .. (c.guildRank and ("  " .. DIM .. c.guildRank .. "|r") or "")
end

local function itemText(item)
    if not item then return "|cff555555(empty)|r" end
    local color = QUALITY_COLOR[item.quality or 1] or "ffffff"
    local extras = {}
    if item.enchant then extras[#extras + 1] = "enchanted" end
    if item.gems then extras[#extras + 1] = #item.gems .. (#item.gems == 1 and " gem" or " gems") end
    local text = "|cff" .. color .. (item.name or ("item " .. tostring(item.id))) .. "|r"
    if #extras > 0 then text = text .. "  " .. DIM .. table.concat(extras, ", ") .. "|r" end
    return text
end

local function summaryText(data)
    local s = ns.Collect.Summarize(data)
    local line = sformat("%d item%s equipped", s.items, s.items == 1 and "" or "s")
    if s.averageLevel then line = line .. sformat("%saverage item level |cffffffff%d|r", SEP, s.averageLevel) end
    line = line .. sformat("%s%d enchanted", SEP, s.enchanted)
    if data.talents and #data.talents > 0 then
        local trees = {}
        for _, t in ipairs(data.talents) do trees[#trees + 1] = sformat("%s %d", t.name or "?", t.points or 0) end
        line = line .. "\nTalents: " .. table.concat(trees, "  " .. DIM .. "/|r  ")
    elseif data.talentsError then
        line = line .. "\n|cffff6666Talents could not be read.|r"
    end
    return line
end

local function setStatus(text, isError)
    ui.status:SetText(text or "")
    local c = isError and COLOR.error or COLOR.dim
    ui.status:SetTextColor(c[1], c[2], c[3], c[4])
end

---------------------------------------------------------------------------
-- Gear tab: rows
---------------------------------------------------------------------------

local function rowEnter(row)
    if not (GameTooltip and row.item) then return end
    GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
    local ok = pcall(GameTooltip.SetInventoryItem, GameTooltip, "player", row.slot)
    if not ok then
        GameTooltip:SetText(row.item.name or "", 1, 1, 1)
    end
    GameTooltip:Show()
end

local function rowLeave()
    if GameTooltip then GameTooltip:Hide() end
end

---------------------------------------------------------------------------
-- Gear tab: refresh and export
---------------------------------------------------------------------------

-- Draws a scan. `data` is nil when the character could not be read.
local function render(data, reason)
    ui.data = data
    if not data then
        ui.who:SetText("|cffff6666Could not read your character.|r")
        ui.guild:SetText(tostring(reason or ""))
        for _, row in ipairs(ui.rows) do row:Hide() end
        ui.summary:SetText("")
        return
    end

    ui.who:SetText(characterLine(data.char))
    ui.guild:SetText(guildLine(data.char))

    local bySlot = {}
    for _, item in ipairs(data.items) do bySlot[item.slot] = item end
    for i, row in ipairs(ui.rows) do
        local slot = ns.Collect.SLOTS[i]
        row.slot = slot
        row.item = bySlot[slot] or false   -- false, not nil: a frame answers a missing key with nil, a stub does not
        row.name:SetText(itemText(row.item or nil))
        row.level:SetText(row.item and row.item.ilvl and tostring(row.item.ilvl) or "")
        row:Show()
    end
    ui.summary:SetText(summaryText(data))

    if ns.Collect.regionSource == "assumed" then
        setStatus(("The client did not say which region you are on, so %s was assumed. If that is wrong, type /mint region EU (or US, KR, TW, CN)."):format(
            data.char.region or ns.Collect.DEFAULT_REGION), true)
    end
    if ui.exportedAt and ns.lastExport and ns.lastExport.signature ~= ns.Signature(data) then
        setStatus("Your gear changed since the last export. Export again before pasting.", true)
    end
end

-- Rescans and redraws the Gear tab.
function UI.Refresh()
    if not ui.frame then return end
    render(ns.Scan())
end

-- Called from Core when the client says equipment changed.
function UI.OnGearChanged()
    if ui.frame and ui.frame:IsShown() and current == "gear" then UI.Refresh() end
end

-- Lays the Gear tab out top to bottom; returns the height the panel needs.
local function buildGear(panel)
    local CW = WIDTH - 2 * PAD   -- content width
    local y = -2

    ui.who = fontString(panel, "GameFontHighlight", CW)
    ui.who:SetPoint("TOPLEFT", PAD, y)
    y = y - 16
    ui.guild = fontString(panel, "GameFontHighlightSmall", CW)
    ui.guild:SetPoint("TOPLEFT", PAD, y)
    y = y - 14 - GAP

    local strip = W.strip(panel, y)
    local hSlot = W.header(strip, "Slot")
    hSlot:SetPoint("LEFT", strip, "LEFT", 4, 0)
    hSlot:SetWidth(76)
    hSlot:SetJustifyH("LEFT")
    local hItem = W.header(strip, "Item")
    hItem:SetPoint("LEFT", strip, "LEFT", 84, 0)
    hItem:SetWidth(300)
    hItem:SetJustifyH("LEFT")
    local hLevel = W.header(strip, "Level")
    hLevel:SetPoint("RIGHT", strip, "RIGHT", -4, 0)
    hLevel:SetWidth(40)
    hLevel:SetJustifyH("RIGHT")
    y = y - STRIP_H

    local list = W.list(panel, y, NUM_ROWS, ROW_HEIGHT)
    ui.list = list
    ui.rows = {}
    for i = 1, NUM_ROWS do
        local row = CreateFrame("Frame", nil, list)
        W.listRow(list, row, i, CW, ROW_HEIGHT)
        row.slot = ns.Collect.SLOTS[i]
        row.item = false
        row.slotName = W.dim(row, ns.Collect.SLOT_NAMES[ns.Collect.SLOTS[i]] or "", 76)
        row.slotName:SetPoint("LEFT", 2, 0)
        row.name = fontString(row, "GameFontHighlightSmall", 300)
        row.name:SetPoint("LEFT", 82, 0)
        row.name:SetHeight(ROW_HEIGHT)
        if row.name.SetWordWrap then row.name:SetWordWrap(false) end
        row.level = fontString(row, "GameFontHighlightSmall", 40)
        row.level:SetPoint("RIGHT", -2, 0)
        row.level:SetJustifyH("RIGHT")
        row:EnableMouse(true)
        row:SetScript("OnEnter", rowEnter)
        row:SetScript("OnLeave", rowLeave)
        ui.rows[i] = row
    end
    y = y + 1 - (NUM_ROWS * ROW_HEIGHT + 4) - GAP

    ui.summary = W.dim(panel, "", CW)
    ui.summary:SetPoint("TOPLEFT", PAD, y)
    ui.summary:SetJustifyV("TOP")
    ui.summary:SetHeight(30)
    y = y - 30 - GAP

    ui.rescan = button(panel, "MintCommunityToolsRescanButton", "Rescan", 90, function()
        UI.Refresh()
        setStatus("Rescanned your gear.")
    end)
    ui.rescan:SetPoint("TOPLEFT", PAD, y)
    ui.export = button(panel, "MintCommunityToolsExportButton", "Export for website", 150, function() UI.Export(false) end)
    ui.export:SetPoint("LEFT", ui.rescan, "RIGHT", GAP, 0)
    -- The group finder's instances with their level bands, for the website's dungeon pages.
    ui.exportDungeons = button(panel, "MintCommunityToolsExportDungeonsButton", "Export dungeons", 130, function() UI.ExportDungeons() end)
    ui.exportDungeons:SetPoint("LEFT", ui.export, "RIGHT", GAP, 0)
    y = y - BUTTON_H - GAP

    ui.hint = W.dim(panel, "", CW)
    ui.hint:SetPoint("TOPLEFT", PAD, y)
    ui.hint:SetJustifyV("TOP")
    ui.hint:SetHeight(26)
    ui.hint:SetText("Press |cffffffffCtrl+C|r (|cffffffffCmd+C|r on a Mac) to copy the string below, then paste it on the website's "
        .. "|cffffffffRoster|r page under |cffffffffAdd or update a character|r. Do this again whenever your gear changes.")
    y = y - 26 - GAP

    -- The copy box takes what is left above the bottom row of controls.
    local bottomRow = PAD + BUTTON_H + GAP
    ui.box = W.copyBox(panel, "MintCommunityTools", PAD, y, -PAD, bottomRow, function() ui.frame:Hide() end)
    ui.editBox = ui.box.editBox

    ui.selectAll = button(panel, "MintCommunityToolsSelectAllButton", "Select all", 90, function()
        if ui.box.text then ui.box.SelectAll() else setStatus("Nothing to select yet. Click Export for website first.", true) end
    end)
    ui.selectAll:SetPoint("BOTTOMLEFT", PAD, PAD)
    ui.status = fontString(panel, "GameFontHighlightSmall", CW - 90 - 6)
    ui.status:SetPoint("LEFT", ui.selectAll, "RIGHT", 6, 0)
    setStatus("")

    return -y + MIN_BOX_H + bottomRow
end

---------------------------------------------------------------------------
-- The window and its tabs
---------------------------------------------------------------------------

local function refreshCurrent()
    if current == "gear" then
        UI.Refresh()
    elseif current == "loot" and ns.LootUI then
        ns.LootUI.Refresh()
    elseif current == "settings" and ns.SettingsUI then
        ns.SettingsUI.Refresh()
    end
end

local function selectTab(key)
    current = key
    for i, tab in ipairs(TABS) do
        local b, panel = ui.tabs[i], ui.panels[tab.key]
        if tab.key == key then
            W.setSelected(b, true)
            panel:Show()
        else
            W.setSelected(b, false)
            panel:Hide()
        end
    end
    if GameTooltip then GameTooltip:Hide() end
    refreshCurrent()
end

local function build()
    local f = W.window("MintCommunityToolsFrame", WIDTH, 100, "DIALOG", "Mint Community Tools", "v" .. ns.VERSION)
    ui.frame = f
    if UISpecialFrames then table.insert(UISpecialFrames, "MintCommunityToolsFrame") end   -- Escape closes it

    ui.tabs, ui.panels = {}, {}
    for i, tab in ipairs(TABS) do
        local b = button(f, "MintCommunityToolsTab" .. i, tab.label, 90, function() selectTab(tab.key) end)
        b:SetPoint("TOPLEFT", PAD + (i - 1) * (90 + 2), -(TITLE_H + GAP))
        ui.tabs[i] = b
        local panel = CreateFrame("Frame", nil, f)
        panel:SetPoint("TOPLEFT", 0, PANEL_TOP)
        panel:SetPoint("BOTTOMRIGHT", 0, 0)
        panel:Hide()
        ui.panels[tab.key] = panel
    end
    -- Each tab says how tall it needs to be; the window takes the taller one, and the other
    -- tab's copy box grows into the difference.
    local gearHeight = buildGear(ui.panels.gear)
    local lootHeight = ns.LootUI.Build(ui.panels.loot, f) or 0
    local settingsHeight = ns.SettingsUI and ns.SettingsUI.Build(ui.panels.settings, f) or 0
    f:SetHeight(-PANEL_TOP + math.max(gearHeight, lootHeight, settingsHeight))

    f:SetScript("OnShow", function() selectTab(current) end)
    f:SetScript("OnHide", function()
        ui.editBox:ClearFocus()
        if GameTooltip then GameTooltip:Hide() end
    end)
    f:Hide()
end

-- Opens the window, on `tab` ("gear" or "loot") when given.
function UI.Show(tab)
    if not ui.frame then build() end
    if tab then current = tab end
    if ui.frame:IsShown() then
        selectTab(current)
    else
        ui.frame:Show()   -- OnShow draws the current tab
    end
end

-- The dungeons export into the copy box: every instance the group finder lists, with its
-- level band (docs/class-data-format-v1.md, kind "dungeons"). It does not depend on the
-- character; an officer pastes it in the class-data box on the website's Talents dashboard.
function UI.ExportDungeons()
    if not ui.frame then build() end
    local str, count = ns.Collect.DungeonsExport()
    if not str then
        ui.box.Set(nil)
        setStatus(count, true)
        return false
    end
    ui.box.Set(str)
    setStatus(("%d instances with their level bands. Paste this in the class-data box on the website's Talents dashboard."):format(count))
    return true
end

function UI.Toggle()
    if not ui.frame then build() end
    if ui.frame:IsShown() then ui.frame:Hide() else UI.Show() end
end

function UI.CurrentTab()
    return current
end

-- Puts the current export string (or the raw JSON, for debugging) in the Gear tab's copy box.
function UI.Export(rawJson)
    UI.Show("gear")
    local text, data, reason = ns.Export(rawJson)
    if not text then
        setStatus(tostring(reason or "nothing to export"), true)
        return
    end
    render(data)   -- the list shows exactly what was exported
    ui.exportedAt = data.ts
    ui.box.Set(text)
    setStatus(sformat("Exported at %s: %s characters, %d items. Press Ctrl+C now.",
        W.clock(data.ts), W.commas(#text), #data.items))
    if #data.items == 0 then
        setStatus("No equipped items were found. Type /mint debug and report the output.", true)
    end
end
