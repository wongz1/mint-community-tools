--[[
    Chat.lua - the chat window in the flat skin.

    The game's chat frames are kept (channels, tabs, history and everything else stay the
    game's); what changes is how they look and where the main window is:
      - the frame art, the tab art and the edit box art are gone; the tabs are plain text;
      - the edit box is a flat strip under the window, where the text appears;
      - the row of buttons beside the window (scroll arrows, the menu, the channel and
        social buttons) is gone: the mouse wheel scrolls, and /commands open the menus;
      - the main window sits on a mover, with an optional flat backdrop behind it. The
        backdrop is fastened to the chat window itself, not to the mover, so it is behind
        the window wherever the window is (the game moves its chat window on its own at
        times, and it can be dragged by its tab), and it takes in the whole of it: the
        tabs above the text and the edit box below.

    Keeping the window on its mover takes more than putting it there once. The chat window
    is one of the frames the game's own edit mode places, and the game fastens it back to
    where that last had it at several moments (when its layout arrives after login, when
    its edit mode closes, when a window is docked). A window fastened elsewhere does not
    follow the mover, so dragging the mover's box moved the box alone. Chat.Check looks once
    a second and puts the window back on the mover whenever it has been taken off it. It
    holds off while the game's own edit mode is open or a mouse button is down, so nothing
    is pulled out from under the mouse; a window dragged by its tab goes back when let go.
    The Chat page of the Settings tab sets the window's width and height, and the size and
    font of the text in it. Until a size or a font is chosen there, the text is left as the
    game has it. A size is set the game's own way where it offers one, so the game remembers
    it too and does not put the old size back; the edit box takes the same size and grows
    with it.
]]

local ADDON, ns = ...
local Chat = {}
ns.Chat = Chat

local ipairs, type, pcall = ipairs, type, pcall

-- The pieces of a chat frame's art, by the names the game gives them.
local FRAME_TEXTURES = {
    "Background", "TopLeftTexture", "BottomLeftTexture", "TopRightTexture", "BottomRightTexture",
    "LeftTexture", "RightTexture", "BottomTexture", "TopTexture",
}
local TAB_TEXTURES = {
    "Left", "Middle", "Right", "SelectedLeft", "SelectedMiddle", "SelectedRight",
    "HighlightLeft", "HighlightMiddle", "HighlightRight",
}
local TAB_FIELDS = {
    "leftTexture", "middleTexture", "rightTexture", "leftSelectedTexture", "middleSelectedTexture", "rightSelectedTexture",
    "leftHighlightTexture", "middleHighlightTexture", "rightHighlightTexture",
}
local EDIT_TEXTURES = { "Left", "Mid", "Right", "FocusLeft", "FocusMid", "FocusRight" }
local BUTTONS = {
    "ChatFrameMenuButton", "ChatFrameChannelButton", "QuickJoinToastButton",
    "ChatFrameToggleVoiceDeafenButton", "ChatFrameToggleVoiceMuteButton", "FriendsMicroButton",
}

local function settings()
    return ns.Overhaul.Settings().chat
end

local function frame(name)
    local f = _G[name]
    return type(f) == "table" and f or nil
end

-- What a setting may be: { least, most, step }. The Settings tab's steppers use these too.
Chat.LIMITS = { width = { 250, 900, 10 }, height = { 100, 700, 10 }, fontSize = { 8, 24, 1 } }
Chat.EDIT_H = 20

local function limited(key)
    local limit = Chat.LIMITS[key]
    local v = tonumber(settings()[key])
    if not v then v = ns.Overhaul.DEFAULTS.chat[key] end
    if v < limit[1] then v = limit[1] elseif v > limit[2] then v = limit[2] end
    return v
end

-- The text size chosen in the settings, or nil while none has been (0, or anything too small
-- to be a size, means: as the game has it).
local function chosenSize()
    local v = tonumber(settings().fontSize)
    if not v or v < Chat.LIMITS.fontSize[1] then return nil end
    return limited("fontSize")
end

-- A frame's font as the game gives it: file, size, flags, with something usable for whatever
-- it does not say.
local function fontOf(f)
    local file, size, flags
    if type(f.GetFont) == "function" then
        local ok, a, b, c = pcall(f.GetFont, f)
        if ok then file, size, flags = a, b, c end
    end
    if type(file) ~= "string" then file = type(STANDARD_TEXT_FONT) == "string" and STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF" end
    if type(size) ~= "number" or size <= 0 then size = 14 end
    if type(flags) ~= "string" then flags = "" end
    return file, size, flags
end

-- The size of the chat text right now: what was chosen, or what the game has.
function Chat.FontSize()
    local chosen = chosenSize()
    if chosen then return chosen end
    local cf = frame("ChatFrame1")
    if not cf then return 14 end
    local _, size = fontOf(cf)
    return math.floor(size + 0.5)
end

local originals = setmetatable({}, { __mode = "k" })   -- frame -> the font file the game gave it

-- The chosen size and font on every chat window and its edit box. Nothing is touched until
-- one of the two has been chosen; a font put back to "as the game has it" gets its own file
-- back.
local function applyFonts()
    local s = settings()
    local size = chosenSize()
    local font = ns.Units and ns.Units.Font(s.font) or {}
    Chat.fontsApplied = Chat.fontsApplied or size ~= nil or font.path ~= nil
    if not Chat.fontsApplied then return false end
    local n = NUM_CHAT_WINDOWS
    if type(n) ~= "number" then n = 10 end
    local editH = math.max(20, (size or 0) + 8)
    for i = 1, n do
        local cf = frame("ChatFrame" .. i)
        if cf then
            for _, f in ipairs({ cf, frame("ChatFrame" .. i .. "EditBox") }) do
                local file, current, flags = fontOf(f)
                originals[f] = originals[f] or file
                local wantFile, wantSize = font.path or originals[f], size or current
                -- The game's own way of setting a chat window's size, so that it remembers it.
                if f == cf and size and type(FCF_SetChatWindowFontSize) == "function" then
                    pcall(FCF_SetChatWindowFontSize, nil, cf, size)
                end
                if type(f.SetFont) == "function" then
                    local ok, set = pcall(f.SetFont, f, wantFile, wantSize, flags)
                    if (not ok or set == false) and wantFile ~= originals[f] then pcall(f.SetFont, f, originals[f], wantSize, flags) end
                end
                if f ~= cf and size then pcall(f.SetHeight, f, editH) end
            end
        end
    end
    if size then Chat.EDIT_H = editH end
    Chat.EDIT_ROOM = 8 + Chat.EDIT_H
    return true
end

local function skinFrame(i)
    local W = ns.W
    local name = "ChatFrame" .. i
    local cf = frame(name)
    if not cf then return false end
    for _, suffix in ipairs(FRAME_TEXTURES) do ns.Overhaul.Blank(frame(name .. suffix)) end
    ns.Overhaul.HideBlizzard(frame(name .. "ButtonFrame"))

    local tab = frame(name .. "Tab")
    if tab then
        for _, suffix in ipairs(TAB_TEXTURES) do ns.Overhaul.Blank(frame(name .. "Tab" .. suffix)) end
        for _, field in ipairs(TAB_FIELDS) do ns.Overhaul.Blank(tab[field]) end
        -- Whatever this client calls the tab's art, every texture on the tab goes; its text stays.
        ns.Overhaul.BlankRegions(tab)
        local text = frame(name .. "TabText") or (tab.GetFontString and tab:GetFontString())
        if text then pcall(text.SetTextColor, text, W.COLOR.text[1], W.COLOR.text[2], W.COLOR.text[3], 1) end
        pcall(tab.SetAlpha, tab, 1)
    end

    local edit = frame(name .. "EditBox")
    if edit then
        for _, suffix in ipairs(EDIT_TEXTURES) do ns.Overhaul.Blank(frame(name .. "EditBox" .. suffix)) end
        W.skin(edit, W.COLOR.panel)
        pcall(edit.SetTextInsets, edit, 6, 6, 0, 0)
        pcall(edit.SetHeight, edit, 20)
        -- Under its window, the full width of it.
        pcall(edit.ClearAllPoints, edit)
        pcall(edit.SetPoint, edit, "TOPLEFT", cf, "BOTTOMLEFT", -2, -4)
        pcall(edit.SetPoint, edit, "TOPRIGHT", cf, "BOTTOMRIGHT", 2, -4)
    end
    pcall(cf.SetClampRectInsets, cf, 0, 0, 0, 0)
    -- The scroll bar that shows under the mouse: a thin dark track and a flat thumb, as the
    -- game menu's windows have. (That code loads after this file; it is there by now.)
    if type(cf.ScrollBar) == "table" and ns.Menus and ns.Menus.FlatScrollBar then
        local ok, done = pcall(ns.Menus.As, "chat", ns.Menus.FlatScrollBar, cf.ScrollBar)
        if ok and done then Chat.scrollBars = (Chat.scrollBars or 0) + 1 end
    end
    return true
end

local backdrop
Chat.TAB_ROOM = 26     -- the tabs' text sits this far above the window's text
Chat.EDIT_ROOM = 28    -- the edit box and the gaps around it, below

-- The backdrop, behind the chat window itself: 4px out from the text on each side, up past
-- the tabs and down past the edit box.
local function placeBackdrop(cf)
    local W = ns.W
    if settings().background then
        if not backdrop then
            backdrop = W.panel(UIParent, W.COLOR.window)
            backdrop:SetFrameStrata("BACKGROUND")
            Chat.backdrop = backdrop
        end
        backdrop:ClearAllPoints()
        backdrop:SetPoint("TOPLEFT", cf, "TOPLEFT", -4, 4 + Chat.TAB_ROOM)
        backdrop:SetPoint("BOTTOMRIGHT", cf, "BOTTOMRIGHT", 4, -Chat.EDIT_ROOM)
        backdrop:Show()
    elseif backdrop then
        backdrop:Hide()
    end
end

-- The main window on its mover, with the backdrop behind it when wanted.
-- How the main window is fastened to its mover: these two points and no others.
local function wantedPoints(mover)
    return { { "TOPLEFT", mover, "TOPLEFT", 4, -4 }, { "BOTTOMRIGHT", mover, "BOTTOMRIGHT", -4, 4 } }
end

-- A frame the game's edit mode looks after has its SetPoint and ClearAllPoints replaced by
-- the game's own, which tell its edit mode about every move; the plain ones are kept beside
-- them. The addon uses the plain ones where there are any: the edit mode has no part in this.
local function plain(f, method)
    local base = rawget(f, method .. "Base")
    if type(base) == "function" then return base end
    return f[method]
end

local placing = false

local function placeMain()
    local s = settings()
    local cf = frame("ChatFrame1")
    if not cf then return end
    local mover = ns.Overhaul.Mover("chat", "Chat", limited("width"), limited("height"), { "BOTTOMLEFT", 20, 36 })
    -- The box stops where the tabs above it and the edit box under it are still on screen;
    -- the window itself is held by its mover and by nothing else.
    pcall(mover.SetClampRectInsets, mover, 0, 0, Chat.TAB_ROOM - 4, -(Chat.EDIT_ROOM - 4))
    pcall(cf.SetClampRectInsets, cf, 0, 0, 0, 0)
    pcall(cf.SetClampedToScreen, cf, false)
    placing = true
    pcall(cf.SetUserPlaced, cf, true)
    pcall(plain(cf, "ClearAllPoints"), cf)
    for _, p in ipairs(wantedPoints(mover)) do pcall(plain(cf, "SetPoint"), cf, p[1], p[2], p[3], p[4], p[5]) end
    placing = false
    placeBackdrop(cf)
end

-- A frame's points, written out: "TOPLEFT > UIParent TOPLEFT 4,-4; ...".
local function describePoints(f)
    local out = {}
    local ok, n = pcall(f.GetNumPoints, f)
    if not ok or type(n) ~= "number" then n = 1 end
    for i = 1, n do
        local okPoint, point, to, toPoint, x, y = pcall(f.GetPoint, f, i)
        if okPoint and type(point) == "string" then
            local name = "?"
            if type(to) == "table" and type(to.GetName) == "function" then
                local okName, got = pcall(to.GetName, to)
                if okName and type(got) == "string" then name = got end
            end
            local okText, text = pcall(string.format, "%s > %s %s %.0f,%.0f", point, name, tostring(toPoint), x, y)
            out[#out + 1] = okText and text or point
        end
    end
    return table.concat(out, "; ")
end

local function number(f, method)
    if type(f[method]) ~= "function" then return nil end
    local ok, v = pcall(f[method], f)
    if ok and type(v) == "number" then return math.floor(v * 10 + 0.5) / 10 end
    return nil
end

-- What the game had done to the window each time it had to be put back: kept in the saved
-- data (the last twelve), for /mint uidump chat and a bug report.
Chat.LOG_MOST = 12
local function logIncident(cf)
    local db = ns.DB and ns.DB()
    if type(db) ~= "table" then return end
    local log = type(db.chatLog) == "table" and db.chatLog or {}
    db.chatLog = log
    local now = time and time() or 0
    local last = Chat.lastEvent
    log[#log + 1] = {
        at = now,
        points = describePoints(cf),
        width = number(cf, "GetWidth") or false,
        height = number(cf, "GetHeight") or false,
        after = last and last.name or false,
        ago = last and (now - last.at) or false,
        combat = (InCombatLockdown and InCombatLockdown()) and true or false,
    }
    while #log > Chat.LOG_MOST do table.remove(log, 1) end
end

-- Everything about the main window's place that a bug report needs (/mint uidump chat).
function Chat.Facts()
    local cf, mover = frame("ChatFrame1"), ns.Overhaul.movers.chat
    local s = settings()
    local out = { applied = Chat.applied and true or false, width = s.width, height = s.height, fontSize = s.fontSize, font = s.font,
                  apis = {} }
    for _, name in ipairs({ "FCF_UpdateDockPosition", "FCF_DockUpdate", "FCF_RestorePositionAndDimensions", "FCF_SavePositionAndDimensions",
                            "FCF_SetChatWindowFontSize", "UIParent_ManageFramePositions" }) do
        out.apis[name] = type(_G[name])
    end
    local function facts(f)
        local t = { points = describePoints(f), left = number(f, "GetLeft") or false, bottom = number(f, "GetBottom") or false,
                    width = number(f, "GetWidth") or false, height = number(f, "GetHeight") or false, scale = number(f, "GetScale") or false }
        for key, method in pairs({ clamped = "IsClampedToScreen", userPlaced = "IsUserPlaced", movable = "IsMovable", resizable = "IsResizable" }) do
            if type(f[method]) == "function" then
                local ok, v = pcall(f[method], f)
                if ok and type(v) == "boolean" then t[key] = v end
            end
        end
        if type(f.GetClampRectInsets) == "function" then
            local ok, l, r, top, b = pcall(f.GetClampRectInsets, f)
            if ok and type(l) == "number" then t.insets = table.concat({ l, r, top, b }, ",") end
        end
        return t
    end
    if cf then
        out.window = facts(cf)
        out.window.plainSetPoint = type(rawget(cf, "SetPointBase")) == "function"
        local _, size = fontOf(cf)
        out.window.textSize = size
        if mover then out.fastened = ns.Overhaul.Fastened(cf, wantedPoints(mover)) end
    end
    if mover then out.mover = facts(mover) end
    local db = ns.DB and ns.DB()
    out.log = type(db) == "table" and db.chatLog or false
    return out
end

-- Is the chat window still fastened to its mover? If the game has fastened it elsewhere, it
-- is put back. Returns true when it had to be.
function Chat.Check()
    if not Chat.applied then return false end
    local cf, mover = frame("ChatFrame1"), ns.Overhaul.movers.chat
    if not (cf and mover) then return false end
    if ns.Overhaul.GameEditing() then return false end
    if IsMouseButtonDown and IsMouseButtonDown() then return false end
    -- The game puts a window's own remembered text size back at times.
    local size = chosenSize()
    if size then
        local _, current = fontOf(cf)
        if math.abs(current - size) > 0.5 then applyFonts() end
    end
    -- Every point, not the first alone: the game also ADDS a point of its own to the window
    -- without taking the addon's off, which leaves the first one as it was and the window
    -- stretched between the two, deaf to its mover.
    if ns.Overhaul.Fastened(cf, wantedPoints(mover)) then return false end
    pcall(logIncident, cf)
    placeMain()
    return true
end

function Chat.Apply()
    local n = NUM_CHAT_WINDOWS
    if type(n) ~= "number" then n = 10 end
    Chat.skinned = 0
    for i = 1, n do
        if skinFrame(i) then Chat.skinned = Chat.skinned + 1 end
    end
    for _, name in ipairs(BUTTONS) do ns.Overhaul.HideBlizzard(frame(name)) end
    applyFonts()
    placeMain()
    -- The game puts the main window back where it saved it at login; so does this, after.
    if hooksecurefunc and FCF_RestorePositionAndDimensions then
        pcall(hooksecurefunc, "FCF_RestorePositionAndDimensions", function(cf)
            if cf == frame("ChatFrame1") then placeMain() end
        end)
    end
    -- And again when the game's own edit mode layout arrives, some time after login, when
    -- its edit mode closes, and once a second for whatever else moves the window. The game
    -- may act on the same event after the addon has: the next look comes at once, not a
    -- second later.
    if not Chat.events then
        Chat.events = CreateFrame("Frame")
        Chat.sinceCheck = 0
        -- The events after which the game has been seen to move the window, or may: the
        -- last one is kept, to say in the log what came before a move.
        for _, ev in ipairs({ "EDIT_MODE_LAYOUTS_UPDATED", "PLAYER_LEVEL_UP", "UPDATE_CHAT_WINDOWS", "UPDATE_FLOATING_CHAT_WINDOWS",
                              "DISPLAY_SIZE_CHANGED", "UI_SCALE_CHANGED", "PLAYER_REGEN_ENABLED" }) do
            pcall(Chat.events.RegisterEvent, Chat.events, ev)
        end
        Chat.events:SetScript("OnEvent", function(_, event)
            Chat.lastEvent = { name = event, at = time and time() or 0 }
            if event == "EDIT_MODE_LAYOUTS_UPDATED" then placeMain() end
            Chat.sinceCheck = 1
        end)
        -- Anything that fastens the window anywhere is looked at on the next frame.
        local main = frame("ChatFrame1")
        if hooksecurefunc and main then
            pcall(hooksecurefunc, main, "SetPoint", function()
                if not placing then Chat.sinceCheck = 1 end
            end)
        end
        Chat.events:SetScript("OnUpdate", function(_, dt)
            Chat.sinceCheck = Chat.sinceCheck + (type(dt) == "number" and dt or 0)
            if Chat.sinceCheck < 1 then return end
            Chat.sinceCheck = 0
            Chat.Check()
        end)
        local manager = frame("EditModeManagerFrame")
        if hooksecurefunc and manager and type(manager.ExitEditMode) == "function" then
            pcall(hooksecurefunc, manager, "ExitEditMode", function() Chat.sinceCheck = 1 end)
        end
    end
    Chat.applied = true
end

function Chat.OnEnteringWorld()
    applyFonts()
    placeMain()
end

function Chat.OnSettingsChanged(path)
    if path == "chat.fontSize" or path == "chat.font" then
        applyFonts()
        placeMain()   -- the backdrop takes in the edit box, which grows with the text
    elseif path == "chat.background" or path == "chat.width" or path == "chat.height" then
        placeMain()
    end
end
