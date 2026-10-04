--[[
    SettingsUI.lua - the Settings tab: the minimalist UI's switches.

    The tab is split into pages, picked with the row of buttons across its top, so that it
    stays short however many pieces the overhaul grows: General (the switch for the whole
    overhaul, the game menu's switch, and the addon's own minimap button), then a page per
    piece: action bars, chat, unit frames, cast bar, minimap, quests. Each page has the piece's own switch and the choices inside
    it: portraits, class colours, where a frame's buffs and debuffs go, what sits above and
    below the minimap. Under the pages, always there: Edit mode, Reset positions, Reload UI,
    and a line saying what state things are in. Switches that change the game's own frames
    take a reload to apply; that line says so.

    A switch whose OFF is only finished by a reload says so in its own label, dimmed:
    "(turning off needs a reload)". Which switches those are is asked of Overhaul.lua, the
    same place that decides whether a reload is needed, so the label cannot say one thing
    and the addon do another.

    Nothing may run past the window's sides. A check box's label is given the width that is
    left of its row and wraps onto as many lines as it needs, the row growing with it; a
    note wraps the same way; a label that shares its row with something else (two check
    boxes side by side, the text beside a stepper) and the text on a button are kept to one
    line and cut short with dots.

    The addon's own minimap button is on the General page (it is not part of the overhaul
    and works with it off): whether it is shown, and the shape of the minimap it sits around.
]]

local ADDON, ns = ...
local SettingsUI = {}
ns.SettingsUI = SettingsUI

local ipairs, type, tostring = ipairs, type, tostring

local sui = { checks = {}, cycles = {}, steppers = {} }   -- the widgets, also reached by the tests as ns.settingsui
ns.settingsui = sui

local SIDE_LABEL = { off = "Off", above = "Above", below = "Below", left = "Left", right = "Right" }
SettingsUI.RELOAD_TAG = "(turning off needs a reload)"
-- Shown in place of a page whose part of the addon this session has not loaded.
SettingsUI.RESTART_NOTE = "This part came with an update while the game was running. Close the game completely and start it again to load it: a /reload is not enough."

local function settings()
    return ns.Overhaul.Settings()
end

-- "units.player.buffs" -> the table holding it and the last key.
local function walk(path)
    local t = settings()
    local last
    for part in path:gmatch("[^%.]+") do
        if last then t = t[last] end
        last = part
    end
    return t, last
end

function SettingsUI.Get(path)
    local t, k = walk(path)
    return t[k]
end

function SettingsUI.Set(path, value)
    local t, k = walk(path)
    t[k] = value
    ns.Overhaul.Changed(path)
    SettingsUI.Refresh()
end

-- One step up (+1) or down (-1) for a number with a stepper, kept inside what it may be.
function SettingsUI.Step(path, direction)
    local st = sui.steppers[path]
    if not st then return false end
    local v = tonumber(SettingsUI.Get(path)) or st.least
    -- A number not yet chosen (the chat's text size, left as the game has it) starts from
    -- what is in use now.
    if st.current and v < st.least then v = st.current() end
    v = v + direction * st.step
    if v < st.least then v = st.least elseif v > st.most then v = st.most end
    SettingsUI.Set(path, v)
    return v
end

local function setStatus(text)
    sui.status:SetText(text or "")
end

---------------------------------------------------------------------------
-- Building the tab
---------------------------------------------------------------------------

local PAGES = {
    { key = "general", label = "General" },
    { key = "bars", label = "Bars" },
    { key = "chat", label = "Chat" },
    { key = "units", label = "Units" },
    { key = "cast", label = "Cast bar" },
    { key = "meter", label = "Meter" },
    { key = "map", label = "Minimap" },
    { key = "quests", label = "Quests" },
}
SettingsUI.PAGES = PAGES

-- Shows one page and marks its button.
function SettingsUI.ShowPage(key)
    if not sui.pages or not sui.pages[key] then return false end
    sui.page = key
    for _, def in ipairs(PAGES) do
        local page, b = sui.pages[def.key], sui.pageButtons[def.key]
        if def.key == key then page:Show() else page:Hide() end
        ns.W.setSelected(b, def.key == key)
    end
    return true
end

function SettingsUI.Build(panel, frame)
    local W = ns.W
    local PAD, GAP = W.PAD, W.GAP
    local CW = W.WIDTH - 2 * PAD
    sui.panel = panel
    sui.pages, sui.pageButtons = {}, {}
    sui.checks, sui.cycles, sui.steppers = {}, {}, {}
    sui.meterFont = nil

    -- The page buttons, across the top.
    local bw = math.floor((CW - (#PAGES - 1) * 2) / #PAGES)
    for i, def in ipairs(PAGES) do
        local b = W.button(panel, "MintCommunityToolsSettingsPage_" .. def.key, def.label, bw, function()
            SettingsUI.ShowPage(def.key)
        end)
        b:SetPoint("TOPLEFT", PAD + (i - 1) * (bw + 2), -2)
        sui.pageButtons[def.key] = b
    end
    local PAGE_TOP = -(2 + W.BUTTON_H + GAP)

    -- The widgets below go on whichever page was started last, top to bottom.
    local page, y
    local tallest = 0
    local function finish()
        if page and -y > tallest then tallest = -y end
    end
    local function start(key)
        finish()
        page = CreateFrame("Frame", nil, panel)
        page:SetPoint("TOPLEFT", panel, "TOPLEFT", 0, PAGE_TOP)
        page:SetPoint("TOPRIGHT", panel, "TOPRIGHT", 0, PAGE_TOP)
        page:SetHeight(1)
        page:Hide()
        sui.pages[key] = page
        y = 0
    end
    local function header(text)
        y = y - 2
        local strip = W.strip(page, y)
        local h = W.header(strip, text)
        h:SetPoint("LEFT", strip, "LEFT", 4, 0)
        y = y - W.STRIP_H - GAP
    end
    -- A check box's label, kept to `room`: wrapped onto as many lines as it takes, or on one
    -- line cut short with dots. Returns how tall it came out.
    local function fitLabel(cb, label, room, wrap)
        local fs = cb.label
        fs:ClearAllPoints()
        fs:SetPoint("TOPLEFT", cb, "TOPRIGHT", 4, -1)
        fs:SetWidth(room)
        fs:SetJustifyH("LEFT")
        if fs.SetJustifyV then fs:SetJustifyV("TOP") end
        if fs.SetWordWrap then fs:SetWordWrap(wrap) end
        cb.room = room
        return wrap and W.textHeight(fs, label, room) or 12
    end
    -- A check box on a row of its own. Its label has the rest of the row.
    local function boxed(cb, label, indent)
        cb:SetPoint("TOPLEFT", PAD + 2 + indent, y - 2)
        local height = fitLabel(cb, label, CW - 4 - indent - 18, true)
        y = y - math.max(18, math.ceil(height) + 6)
    end
    local function check(path, label, indent)
        -- a switch whose OFF is finished by a reload says so, dimmed, after its label
        local tagged = ns.Overhaul.OffNeedsReload(path)
        if tagged then label = label .. " |cff" .. W.DIM_HEX .. SettingsUI.RELOAD_TAG .. "|r" end
        local cb = W.checkbox(page, "MintCommunityToolsSetting_" .. path:gsub("%.", "_"), label, function(on)
            SettingsUI.Set(path, on)
        end)
        cb.path, cb.reloadTag = path, tagged
        sui.checks[path] = cb
        boxed(cb, label, indent or 0)
    end
    local function note(text)
        local width = CW - 4
        local d = W.dim(page, text, width)
        d:SetPoint("TOPLEFT", PAD + 2, y)
        d:SetJustifyH("LEFT")
        d:SetJustifyV("TOP")
        if d.SetWordWrap then d:SetWordWrap(true) end
        local height = math.ceil(W.textHeight(d, text, width))
        d:SetHeight(height + 2)
        y = y - height - 4
    end
    -- A check box at `x` that does not start a new row (for two on one row): its label has
    -- `room` and no more.
    local function checkAt(path, label, x, room)
        local cb = W.checkbox(page, "MintCommunityToolsSetting_" .. path:gsub("%.", "_"), label, function(on)
            SettingsUI.Set(path, on)
        end)
        cb:SetPoint("TOPLEFT", PAD + 2 + x, y - 2)
        cb.path, cb.reloadTag = path, false
        sui.checks[path] = cb
        fitLabel(cb, label, room - 18, false)
    end
    -- A number: [-] [+] and "Label: 240". What it may be comes from the limits of the piece it
    -- belongs to. `current`, when given, says what is in use while nothing has been chosen.
    local function stepper(path, label, x, current)
        local id = path:gsub("%.", "_")
        local owner
        if path:match("^chat%.") then owner = ns.Chat
        elseif path:match("^cast%.") then owner = ns.CastBars
        elseif path:match("^bars%.") then owner = ns.Bars
        elseif path:match("^meter%.") then owner = ns.Meters
        else owner = ns.Units end
        local limit = type(owner) == "table" and type(owner.LIMITS) == "table" and owner.LIMITS[path:match("[^%.]+$")]
        if type(limit) ~= "table" then return false end   -- that part of the addon is not loaded
        local less = W.button(page, "MintCommunityToolsSettingLess_" .. id, "-", 18, function() SettingsUI.Step(path, -1) end)
        less:SetPoint("TOPLEFT", PAD + 2 + x, y)
        local more = W.button(page, "MintCommunityToolsSettingMore_" .. id, "+", 18, function() SettingsUI.Step(path, 1) end)
        more:SetPoint("LEFT", less, "RIGHT", 2, 0)
        local text = W.text(page, "")
        text:SetPoint("LEFT", more, "RIGHT", 6, 0)
        -- the text has what is left of its column: the second column runs to the window's side
        local room = (x >= 200 and CW - x or 216) - 18 - 2 - 18 - 6 - 4
        text:SetWidth(room)
        text:SetJustifyH("LEFT")
        if text.SetWordWrap then text:SetWordWrap(false) end
        sui.steppers[path] = { room = room, less = less, more = more, text = text, label = label, least = limit[1], most = limit[2], step = limit[3],
                               current = current or false }
    end
    local function cycle(path, label, x)
        local b = W.button(page, "MintCommunityToolsSettingCycle_" .. path:gsub("%.", "_"), label, 150, function()
            SettingsUI.Set(path, ns.Units.NextSide(SettingsUI.Get(path)))
        end)
        b:SetPoint("TOPLEFT", PAD + 2 + x, y)
        b.path, b.label = path, label
        sui.cycles[path] = b
        W.fitText(b, 150)
        return b
    end

    start("general")
    header("The minimalist UI")
    check("enabled", "Use the minimalist UI: flat bars, chat, unit frames, minimap and quest list")
    note("Off by default. Every switch works at once, except turning off the ones marked \"turning off needs a reload\".")
    check("menus.enabled", "Flat game menu (Escape) and the windows it opens: Options, AddOns, Edit Mode, Macros", 18)
    check("menuButton", "A Mint Edit Mode button at the bottom of the game menu", 18)
    check("menuEdit", "The game menu's Edit Mode button opens this UI's edit mode (Shift-click for the game's own)", 18)
    header("Minimap button")
    sui.buttonShown = W.checkbox(page, "MintCommunityToolsSettingMinimapButton", "Show this addon's minimap button", function(on)
        ns.SetMinimapShown(on)
    end)
    sui.buttonShown:SetPoint("TOPLEFT", PAD + 2, y - 3)
    fitLabel(sui.buttonShown, "Show this addon's minimap button", CW - 4 - 18 - 190 - GAP, false)
    sui.buttonShape = W.button(page, "MintCommunityToolsSettingMinimapShape", "", 190, function()
        ns.SetMinimapShape(ns.NextMinimapShape())
    end)
    sui.buttonShape:SetPoint("TOPRIGHT", -(PAD + 2), y)
    y = y - W.BUTTON_H - GAP
    note("Auto follows the minimap: square with this addon's square minimap or another addon's, round otherwise.")

    start("bars")
    header("Action bars")
    check("bars.enabled", "Flat action bars, each on its own mover; the pet and stance bars, bags and micro menu too")
    check("bars.hideMicro", "Hide the micro menu (Escape and the keybinds still open everything)", 18)
    check("bars.hideBags", "Hide the bag row: the backpack, the bags and the keyring (your bag key still opens them)", 18)
    check("bars.extraBags", "The keyring and the reagent bag slot in the bag row, when it is shown", 18)
    header("Experience bar")
    check("bars.xpClassColor", "In your class colour (turn off for the game's own purple)")
    y = y - 2
    do
        local COL2, ROW = 18 + 216, W.BUTTON_H + GAP
        stepper("bars.xpWidth", "Width", 0, function() return (ns.Bars.ExperienceSize()) end)
        stepper("bars.xpHeight", "Height", COL2, function() return select(2, ns.Bars.ExperienceSize()) end)
        y = y - ROW
        note("Until you choose, the bar is as wide as a row of twelve buttons. Move it with Edit mode.")
    end
    header("Bag windows")
    check("bags.enabled", "Flat bag windows: plain slots, with the border in the colour of the item's quality")

    start("chat")
    header("Chat")
    check("chat.enabled", "Flat chat: no frame art, the edit box under the window, no side buttons")
    check("chat.background", "A backdrop behind the chat window", 18)
    y = y - 2
    do
        local COL2, ROW = 18 + 216, W.BUTTON_H + GAP
        stepper("chat.width", "Width", 18)
        stepper("chat.height", "Height", COL2)
        y = y - ROW
        sui.chatFont = W.button(page, "MintCommunityToolsSettingChatFont", "", 190, function()
            SettingsUI.Set("chat.font", ns.Units.NextFont(SettingsUI.Get("chat.font")))
        end)
        sui.chatFont:SetPoint("TOPLEFT", PAD + 2 + 18, y)
        stepper("chat.fontSize", "Text size", COL2, function() return ns.Chat.FontSize() end)
        y = y - ROW
        note("The size is the chat window's own; move it with Edit mode. The text is as the game has it until you choose a size or a font here.")
    end

    start("units")
    header("Unit frames")
    check("units.enabled", "The addon's own player, target, target-of-target and pet frames")
    check("units.portrait", "Portraits", 18)
    check("units.portrait3d", "Animated 3D portraits (the unit's own model, in place of the flat picture)", 36)
    check("units.classColor", "Class colours on players' health bars", 18)
    check("units.target.onlyMine", "Only my debuffs on the target", 18)
    y = y - 2
    cycle("units.player.buffs", "Player buffs", 18)
    cycle("units.player.debuffs", "Player debuffs", 18 + 150 + GAP)
    y = y - W.BUTTON_H - GAP
    cycle("units.target.buffs", "Target buffs", 18)
    cycle("units.target.debuffs", "Target debuffs", 18 + 150 + GAP)
    y = y - W.BUTTON_H - GAP
    -- text, sizes and the aura icons: two to a row
    local COL2, ROW = 18 + 216, W.BUTTON_H + GAP
    sui.font = W.button(page, "MintCommunityToolsSettingFont", "", 190, function()
        SettingsUI.Set("units.font", ns.Units.NextFont(SettingsUI.Get("units.font")))
    end)
    sui.font:SetPoint("TOPLEFT", PAD + 2 + 18, y)
    stepper("units.fontSize", "Font size", COL2)
    y = y - ROW
    stepper("units.width", "Width", 18)
    stepper("units.height", "Height", COL2)
    y = y - ROW
    stepper("units.smallWidth", "Small frames' width", 18)
    stepper("units.smallHeight", "Small frames' height", COL2)
    y = y - ROW
    stepper("units.buffSize", "Buff icon size", 18)
    stepper("units.debuffSize", "Debuff icon size", COL2)
    y = y - ROW
    stepper("units.perRow", "Icons in a row", 18)
    y = y - ROW
    checkAt("units.buffTimers", "Countdown numbers on buffs", 18, COL2 - 18 - GAP)
    checkAt("units.debuffTimers", "Countdown numbers on debuffs", COL2, CW - 2 - COL2)
    y = y - 18
    note("Width and height are the player and target frames'; the small frames are the target's target and the pet. A size changed in combat applies when it ends.")

    start("cast")
    header("Cast bars")
    if not ns.CastBars then
        -- a file that came with an update is only read when the game starts
        note(SettingsUI.RESTART_NOTE)
    else
        check("cast.enabled", "Flat cast bars: no frame art, the spell's name on the bar, your own on a mover")
    end
    y = y - 2
    if ns.CastBars then
        local COL2, ROW = 18 + 216, W.BUTTON_H + GAP
        stepper("cast.width", "Width", 18, function() return (ns.CastBars.Size()) end)
        stepper("cast.height", "Height", COL2, function() return select(2, ns.CastBars.Size()) end)
        y = y - ROW
        stepper("cast.fontSize", "Text size", 18, function() return ns.CastBars.FontSize() end)
        y = y - ROW
        stepper("cast.textX", "Text left / right", 18)
        stepper("cast.textY", "Text down / up", COL2)
        y = y - ROW
        note("Width and height are your own cast bar's. The text size and place are every cast bar's; the place is how far the spell's name sits from the middle of the bar. Each is as the game has it until you choose.")
    end

    start("meter")
    header("Damage meter")
    if not ns.Meters then
        note(SettingsUI.RESTART_NOTE)
    else
        check("meter.enabled", "Flat damage meter: the game's own meter without its art, with plain bars")
        check("meter.background", "A backdrop behind the bars", 18)
        check("meter.oneColor", "Every bar in your class colour (off: the colours the game gives them)", 18)
        y = y - 2
        local COL2, ROW = 18 + 216, W.BUTTON_H + GAP
        stepper("meter.backgroundAlpha", "Backdrop darkness", 18)
        y = y - ROW
        sui.meterFont = W.button(page, "MintCommunityToolsSettingMeterFont", "", 190, function()
            SettingsUI.Set("meter.font", ns.Units.NextFont(SettingsUI.Get("meter.font")))
        end)
        sui.meterFont:SetPoint("TOPLEFT", PAD + 2 + 18, y)
        stepper("meter.fontSize", "Text size", COL2, function() return ns.Meters.FontSize() end)
        y = y - ROW
        note("This is the game's own damage meter (Options, or /console damageMeterEnabled 1), in the flat skin. "
            .. "Move it with Edit mode. The bars' height and spacing, the window's size, and the icons are the game's own settings: "
            .. "open the game's Edit Mode (Shift-click Edit Mode in the Escape menu) and click the meter.")
    end

    start("map")
    header("Minimap")
    check("map.enabled", "The minimap on a mover, with the zoom buttons and the round border gone")
    check("map.square", "Square", 18)
    check("map.zone", "The zone's name above it", 18)
    check("map.coords", "Your coordinates, at the right of the zone's name (below the map without it)", 18)
    check("map.localTime", "Your computer's time below it", 18)
    check("map.gameTime", "The game world's time below it", 18)

    start("quests")
    header("Quest tracker")
    check("quests.enabled", "The addon's own list of your quests, in place of the game's tracker")
    check("quests.levels", "Each quest's level in front of its title", 18)
    check("quests.background", "A backdrop behind the list", 18)
    note("The list has two tabs: All shows every quest in your quest log, Tracked the ones you are tracking. "
        .. "Click the list's header to fold it away, a quest to open it in the quest log, and shift-click a quest to track it or stop tracking it. "
        .. "The mouse wheel scrolls a list that does not fit. The game's tracker is hidden while this is on, along with anything else it shows.")
    finish()

    -- Under the pages, whichever is showing: positions, the reload, and the state of things.
    y = PAGE_TOP - tallest - GAP
    local strip = W.strip(panel, y)
    local h = W.header(strip, "Positions")
    h:SetPoint("LEFT", strip, "LEFT", 4, 0)
    y = y - W.STRIP_H - GAP
    do
        local text = "Edit mode shows every frame as a box to drag; right-click a box to put it back."
        local hint = W.dim(panel, text, CW - 4)
        hint:SetPoint("TOPLEFT", PAD + 2, y)
        hint:SetJustifyH("LEFT")
        hint:SetJustifyV("TOP")
        local height = math.ceil(W.textHeight(hint, text, CW - 4))
        hint:SetHeight(height + 2)
        y = y - height - 4
    end
    sui.edit = W.button(panel, "MintCommunityToolsSettingEditButton", "Edit mode", 110, function()
        ns.Overhaul.ToggleEdit()
    end)
    sui.edit:SetPoint("TOPLEFT", PAD + 2, y)
    sui.reset = W.button(panel, "MintCommunityToolsSettingResetButton", "Reset positions", 110, function()
        ns.Overhaul.ResetPositions()
    end)
    sui.reset:SetPoint("LEFT", sui.edit, "RIGHT", GAP, 0)
    sui.reload = W.button(panel, "MintCommunityToolsSettingReloadButton", "Reload UI", 90, function()
        if ReloadUI then ReloadUI() end
    end)
    sui.reload:SetPoint("LEFT", sui.reset, "RIGHT", GAP, 0)
    y = y - W.BUTTON_H - GAP

    -- the longest thing the status line says takes three lines at this width
    sui.status = W.dim(panel, "", CW - 4)
    sui.status:SetPoint("TOPLEFT", PAD + 2, y)
    sui.status:SetJustifyH("LEFT")
    sui.status:SetJustifyV("TOP")
    sui.status:SetHeight(40)
    y = y - 40 - PAD

    SettingsUI.ShowPage(sui.page or "general")
    return -y
end

---------------------------------------------------------------------------
-- Refresh
---------------------------------------------------------------------------

function SettingsUI.Refresh()
    if not sui.panel then return end
    local O = ns.Overhaul
    local s = settings()
    for path, cb in pairs(sui.checks) do
        cb:SetChecked(SettingsUI.Get(path) and true or false)
    end
    for path, b in pairs(sui.cycles) do
        b:SetText(b.label .. ": " .. (SIDE_LABEL[SettingsUI.Get(path)] or "Off"))
    end
    for path, st in pairs(sui.steppers) do
        local v = tonumber(SettingsUI.Get(path))
        if st.current and (not v or v < st.least) then v = st.current() end
        st.text:SetText(st.label .. ": " .. tostring(v))
    end
    sui.font:SetText("Font: " .. ns.Units.Font(SettingsUI.Get("units.font")).label)
    do
        local key = SettingsUI.Get("chat.font")
        sui.chatFont:SetText("Font: " .. (key == "default" and "as the game has it" or ns.Units.Font(key).label))
    end
    -- a font's name can be any length: the text stays inside its button
    ns.W.fitText(sui.font, 190)
    ns.W.fitText(sui.chatFont, 190)
    if sui.meterFont then
        local key = SettingsUI.Get("meter.font")
        sui.meterFont:SetText("Font: " .. (key == "default" and "as the game has it" or ns.Units.Font(key).label))
        ns.W.fitText(sui.meterFont, 190)
    end
    ns.W.fitText(sui.buttonShape, 190)
    sui.buttonShown:SetChecked(ns.DB().minimap.shown and true or false)
    sui.buttonShape:SetText(ns.MinimapShapeLabel())
    sui.edit:SetText(O.Editing() and "Exit edit mode" or "Edit mode")
    if O.needsReload then
        setStatus("|cffffd100Reload to apply|r: turning off the " .. table.concat(O.ReloadPieces(), ", ")
            .. " puts the game's own frames back, which only a reload can do. Click Reload UI when you are ready.")
    elseif O.pendingApply then
        setStatus("In combat: this will be done when combat ends.")
    elseif not s.enabled then
        setStatus("The minimalist UI is off. Turn it on, then use Edit mode to arrange it.")
    else
        local pieces = {}
        for _, piece in ipairs(O.PIECES) do
            if not O.applied[piece.key] and s[piece.key].enabled then pieces[#pieces + 1] = piece.label end
        end
        if #pieces > 0 then
            setStatus("Could not be set up: " .. table.concat(pieces, ", ") .. ". The reason is in chat.")
        else
            setStatus("The minimalist UI is on. Edit mode moves things; portraits, aura rows, the minimap strips and the quest list change at once.")
        end
    end
end
