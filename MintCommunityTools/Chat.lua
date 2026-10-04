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
local function placeMain()
    local s = settings()
    local cf = frame("ChatFrame1")
    if not cf then return end
    local mover = ns.Overhaul.Mover("chat", "Chat", limited("width"), limited("height"), { "BOTTOMLEFT", 20, 36 })
    pcall(cf.SetUserPlaced, cf, true)
    pcall(cf.ClearAllPoints, cf)
    pcall(cf.SetPoint, cf, "TOPLEFT", mover, "TOPLEFT", 4, -4)
    pcall(cf.SetPoint, cf, "BOTTOMRIGHT", mover, "BOTTOMRIGHT", -4, 4)
    placeBackdrop(cf)
end

-- Is the chat window still fastened to its mover? If the game has fastened it elsewhere, it
-- is put back. Returns true when it had to be.
function Chat.Check()
    if not Chat.applied then return false end
    local cf, mover = frame("ChatFrame1"), ns.Overhaul.movers.chat
    if not (cf and mover) then return false end
    if ns.Overhaul.GameEditing() then return false end
    if IsMouseButtonDown and IsMouseButtonDown() then return false end
    local ok, _, anchor = pcall(cf.GetPoint, cf, 1)
    -- The game puts a window's own remembered text size back at times.
    local size = chosenSize()
    if size then
        local _, current = fontOf(cf)
        if math.abs(current - size) > 0.5 then applyFonts() end
    end
    if ok and anchor == mover then return false end
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
        pcall(Chat.events.RegisterEvent, Chat.events, "EDIT_MODE_LAYOUTS_UPDATED")
        Chat.events:SetScript("OnEvent", function()
            placeMain()
            Chat.sinceCheck = 1
        end)
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
