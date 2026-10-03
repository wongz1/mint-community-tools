--[[
    SettingsUI.lua - the Settings tab: the minimalist UI's switches.

    The tab is split into pages, picked with the row of buttons across its top, so that it
    stays short however many pieces the overhaul grows: General (the switch for the whole
    overhaul, the game menu's switch, and the addon's own minimap button), then a page per
    piece: action bars, chat, unit frames, minimap, quests. Each page has the piece's own switch and the choices inside
    it: portraits, class colours, where a frame's buffs and debuffs go, what sits above and
    below the minimap. Under the pages, always there: Edit mode, Reset positions, Reload UI,
    and a line saying what state things are in. Switches that change the game's own frames
    take a reload to apply; that line says so.

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
    { key = "bars", label = "Action bars" },
    { key = "chat", label = "Chat" },
    { key = "units", label = "Unit frames" },
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
    local function check(path, label, indent)
        local cb = W.checkbox(page, "MintCommunityToolsSetting_" .. path:gsub("%.", "_"), label, function(on)
            SettingsUI.Set(path, on)
        end)
        cb:SetPoint("TOPLEFT", PAD + 2 + (indent or 0), y - 2)
        cb.path = path
        sui.checks[path] = cb
        y = y - 18
    end
    local function note(text, lines)
        local d = W.dim(page, text, CW - 4)
        d:SetPoint("TOPLEFT", PAD + 2, y)
        d:SetJustifyV("TOP")
        d:SetHeight(14 * (lines or 1))
        y = y - 14 * (lines or 1) - 2
    end
    -- A check box at `x` that does not start a new row (for two on one row).
    local function checkAt(path, label, x)
        local cb = W.checkbox(page, "MintCommunityToolsSetting_" .. path:gsub("%.", "_"), label, function(on)
            SettingsUI.Set(path, on)
        end)
        cb:SetPoint("TOPLEFT", PAD + 2 + x, y - 2)
        cb.path = path
        sui.checks[path] = cb
    end
    -- A number: [-] [+] and "Label: 240". What it may be comes from the unit frames' limits.
    local function stepper(path, label, x)
        local id = path:gsub("%.", "_")
        local limit = ns.Units.LIMITS[path:match("[^%.]+$")]
        local less = W.button(page, "MintCommunityToolsSettingLess_" .. id, "-", 18, function() SettingsUI.Step(path, -1) end)
        less:SetPoint("TOPLEFT", PAD + 2 + x, y)
        local more = W.button(page, "MintCommunityToolsSettingMore_" .. id, "+", 18, function() SettingsUI.Step(path, 1) end)
        more:SetPoint("LEFT", less, "RIGHT", 2, 0)
        local text = W.text(page, "")
        text:SetPoint("LEFT", more, "RIGHT", 6, 0)
        sui.steppers[path] = { less = less, more = more, text = text, label = label, least = limit[1], most = limit[2], step = limit[3] }
    end
    local function cycle(path, label, x)
        local b = W.button(page, "MintCommunityToolsSettingCycle_" .. path:gsub("%.", "_"), label, 150, function()
            SettingsUI.Set(path, ns.Units.NextSide(SettingsUI.Get(path)))
        end)
        b:SetPoint("TOPLEFT", PAD + 2 + x, y)
        b.path, b.label = path, label
        sui.cycles[path] = b
        return b
    end

    start("general")
    header("The minimalist UI")
    check("enabled", "Use the minimalist UI: flat bars, chat, unit frames, minimap and quest list")
    note("Off by default. Turning the whole thing, or a piece of it, on or off applies after a reload.")
    check("menus.enabled", "Flat game menu (Escape) and the windows it opens: Options, AddOns, Edit Mode, Macros", 18)
    header("Minimap button")
    sui.buttonShown = W.checkbox(page, "MintCommunityToolsSettingMinimapButton", "Show this addon's minimap button", function(on)
        ns.SetMinimapShown(on)
    end)
    sui.buttonShown:SetPoint("TOPLEFT", PAD + 2, y - 3)
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
    check("bars.extraBags", "The keyring and the reagent bag slot in the bag row", 18)

    start("chat")
    header("Chat")
    check("chat.enabled", "Flat chat: no frame art, the edit box under the window, no side buttons")
    check("chat.background", "A backdrop behind the chat window", 18)

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
    checkAt("units.buffTimers", "Countdown numbers on buffs", 18)
    checkAt("units.debuffTimers", "Countdown numbers on debuffs", COL2)
    y = y - 18
    note("Width and height are the player and target frames'; the small frames are the target's target and the pet. A size changed in combat applies when it ends.", 2)

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
    check("quests.enabled", "The addon's own list of tracked quests, in place of the game's tracker")
    check("quests.levels", "Each quest's level in front of its title", 18)
    check("quests.background", "A backdrop behind the list", 18)
    note("Click the list's header to fold it away, a quest to open it in the quest log, and shift-click a quest to stop tracking it. "
        .. "The game's tracker is hidden while this is on, along with anything else it shows.", 3)
    finish()

    -- Under the pages, whichever is showing: positions, the reload, and the state of things.
    y = PAGE_TOP - tallest - GAP
    local strip = W.strip(panel, y)
    local h = W.header(strip, "Positions")
    h:SetPoint("LEFT", strip, "LEFT", 4, 0)
    y = y - W.STRIP_H - GAP
    local hint = W.dim(panel, "Edit mode shows every frame as a box to drag; right-click a box to put it back.", CW - 4)
    hint:SetPoint("TOPLEFT", PAD + 2, y)
    hint:SetJustifyV("TOP")
    hint:SetHeight(14)
    y = y - 14 - 2
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

    sui.status = W.dim(panel, "", CW - 4)
    sui.status:SetPoint("TOPLEFT", PAD + 2, y)
    sui.status:SetJustifyV("TOP")
    sui.status:SetHeight(28)
    y = y - 28 - PAD

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
        st.text:SetText(st.label .. ": " .. tostring(SettingsUI.Get(path)))
    end
    sui.font:SetText("Font: " .. ns.Units.Font(SettingsUI.Get("units.font")).label)
    sui.buttonShown:SetChecked(ns.DB().minimap.shown and true or false)
    sui.buttonShape:SetText(ns.MinimapShapeLabel())
    sui.edit:SetText(O.Editing() and "Exit edit mode" or "Edit mode")
    if O.needsReload then
        setStatus("|cffffd100Reload to apply|r: what the game's own frames look like only changes at a reload. Click Reload UI when you are ready.")
    elseif not s.enabled then
        setStatus("The minimalist UI is off. Turn it on, reload, then use Edit mode to arrange it.")
    else
        local pieces = {}
        for _, piece in ipairs(O.PIECES) do
            if not O.applied[piece.key] and s[piece.key].enabled then pieces[#pieces + 1] = piece.label end
        end
        if #pieces > 0 then
            setStatus("Not set up this session: " .. table.concat(pieces, ", ") .. ". Reload to apply.")
        else
            setStatus("The minimalist UI is on. Edit mode moves things; portraits, aura rows, the minimap strips and the quest list change at once.")
        end
    end
end
