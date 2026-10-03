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
    Fonts are left as they are.
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
    local mover = ns.Overhaul.Mover("chat", "Chat", s.width, s.height, { "BOTTOMLEFT", 20, 36 })
    pcall(cf.SetUserPlaced, cf, true)
    pcall(cf.ClearAllPoints, cf)
    pcall(cf.SetPoint, cf, "TOPLEFT", mover, "TOPLEFT", 4, -4)
    pcall(cf.SetPoint, cf, "BOTTOMRIGHT", mover, "BOTTOMRIGHT", -4, 4)
    placeBackdrop(cf)
end

function Chat.Apply()
    local n = NUM_CHAT_WINDOWS
    if type(n) ~= "number" then n = 10 end
    Chat.skinned = 0
    for i = 1, n do
        if skinFrame(i) then Chat.skinned = Chat.skinned + 1 end
    end
    for _, name in ipairs(BUTTONS) do ns.Overhaul.HideBlizzard(frame(name)) end
    placeMain()
    -- The game puts the main window back where it saved it at login; so does this, after.
    if hooksecurefunc and FCF_RestorePositionAndDimensions then
        pcall(hooksecurefunc, "FCF_RestorePositionAndDimensions", function(cf)
            if cf == frame("ChatFrame1") then placeMain() end
        end)
    end
    -- And again when the game's own edit mode layout arrives, some time after login.
    if not Chat.events then
        Chat.events = CreateFrame("Frame")
        pcall(Chat.events.RegisterEvent, Chat.events, "EDIT_MODE_LAYOUTS_UPDATED")
        Chat.events:SetScript("OnEvent", function() placeMain() end)
    end
end

function Chat.OnEnteringWorld()
    placeMain()
end

function Chat.OnSettingsChanged(path)
    if path == "chat.background" or path == "chat.width" or path == "chat.height" then placeMain() end
end
