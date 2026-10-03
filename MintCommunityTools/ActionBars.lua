--[[
    ActionBars.lua - the game's action bars in the flat skin, on movers, with the addon's own
    experience bar and the micro menu.

    The game's own buttons are kept (keybinds, paging, cooldowns and everything else stay
    the game's); what changes is how they look and where they are:
      - the bar art (the gryphons, the bar textures, the page arrows) is gone;
      - every button is a flat square: the icon inset 1px in a 1px black border, no round
        Blizzard button texture, a flat highlight and pressed state, the keybind text top
        right;
      - each bar is laid out on its own mover: bars 1 to 3 stacked at the bottom, bars 4
        and 5 as columns on the right, the pet and stance bars above, the bags bottom
        right, the micro menu beside them on a flat strip (or hidden).
    The experience bar is the addon's own: a thin flat bar under bar 1 with rested experience
    behind it, and the watched reputation when there is no experience left to gain. The
    game's own experience and reputation bars are hidden.

    The client's frames are not the same from one version of the game to the next, so
    nothing here relies on one name: art is removed by sweeping every texture off the bar's
    art frames as well as by name, the micro buttons come from the game's own list when it
    has one, and what does not exist is skipped. A client with different bars loses a bar,
    not the addon. /mint uidump records what this client really has.
]]

local ADDON, ns = ...
local Bars = {}
ns.Bars = Bars

local ipairs, type, pcall, tostring = ipairs, type, pcall, tostring
local floor = math.floor
local sformat = string.format

local BARS = {
    { key = "bar1", label = "Action bar 1", prefix = "ActionButton", count = 12, default = { "BOTTOM", 0, 36 } },
    { key = "bar2", label = "Action bar 2", prefix = "MultiBarBottomLeftButton", count = 12, default = { "BOTTOM", 0, 72 } },
    { key = "bar3", label = "Action bar 3", prefix = "MultiBarBottomRightButton", count = 12, default = { "BOTTOM", 0, 108 } },
    { key = "bar4", label = "Action bar 4", prefix = "MultiBarRightButton", count = 12, vertical = true, default = { "RIGHT", -36, 0 } },
    { key = "bar5", label = "Action bar 5", prefix = "MultiBarLeftButton", count = 12, vertical = true, default = { "RIGHT", -72, 0 } },
    -- Newer clients have three more bars; laid out only where they exist.
    { key = "bar6", label = "Action bar 6", prefix = "MultiBar5Button", count = 12, default = { "BOTTOM", 0, 180 } },
    { key = "bar7", label = "Action bar 7", prefix = "MultiBar6Button", count = 12, default = { "BOTTOM", 0, 216 } },
    { key = "bar8", label = "Action bar 8", prefix = "MultiBar7Button", count = 12, default = { "BOTTOM", 0, 252 } },
    { key = "petbar", label = "Pet bar", prefix = "PetActionButton", count = 10, small = true, default = { "BOTTOM", 0, 146 } },
    { key = "stancebar", label = "Stance bar", prefix = "StanceButton", alt = "ShapeshiftButton", count = 10, small = true, default = { "BOTTOMLEFT", 20, 146 } },
}
Bars.BARS = BARS

local BAG_BUTTONS = {
    "MainMenuBarBackpackButton", "CharacterBag0Slot", "CharacterBag1Slot", "CharacterBag2Slot", "CharacterBag3Slot",
    "CharacterReagentBag0Slot", "KeyRingButton",
}
-- The game's frame for each bar: a bar switched off in the game's settings, or one with
-- nothing to show (no pet, no stances), is hidden, and its mover says so in edit mode.
local BAR_FRAMES = {
    bar1 = { "MainActionBar", "MainMenuBar" }, bar2 = { "MultiBarBottomLeft" }, bar3 = { "MultiBarBottomRight" },
    bar4 = { "MultiBarRight" }, bar5 = { "MultiBarLeft" }, bar6 = { "MultiBar5" }, bar7 = { "MultiBar6" }, bar8 = { "MultiBar7" },
    petbar = { "PetActionBar", "PetActionBarFrame" }, stancebar = { "StanceBar", "StanceBarFrame", "ShapeshiftBarFrame" },
}
-- The micro buttons of every version; the game's own MICRO_BUTTONS list is used when it exists.
local MICRO_BUTTONS_KNOWN = {
    "LegacyMicroButton", "CharacterMicroButton", "SpellbookMicroButton", "ProfessionMicroButton", "PlayerSpellsMicroButton", "TalentMicroButton",
    "AchievementMicroButton", "QuestLogMicroButton", "SocialsMicroButton", "GuildMicroButton", "LFGMicroButton", "LFDMicroButton",
    "CollectionsMicroButton", "EJMicroButton", "WorldMapMicroButton", "StoreMicroButton", "MainMenuMicroButton", "HelpMicroButton",
}
-- Art that goes, by the names it has had: the gryphons, the bar textures, the page arrows.
local ART = {
    "MainMenuBarTexture0", "MainMenuBarTexture1", "MainMenuBarTexture2", "MainMenuBarTexture3",
    "MainMenuBarLeftEndCap", "MainMenuBarRightEndCap", "MainMenuBarPageNumber", "ActionBarUpButton", "ActionBarDownButton",
    "MainMenuBarPerformanceBarFrame", "MainMenuBarMaxLevelBar", "MainMenuBarArtFrameBackground",
    "MainMenuXPBarTexture0", "MainMenuXPBarTexture1", "MainMenuXPBarTexture2", "MainMenuXPBarTexture3",
}
-- Frames whose own textures are all art (the buttons on them are child frames, untouched).
local ART_FRAMES = { "MainMenuBarArtFrame", "MainMenuBar", "MainActionBar", "MicroButtonAndBagsBar", "BagsBar", "MicroMenu", "MicroMenuContainer" }
-- Parts of the main bar that newer clients keep as fields rather than under global names.
local ART_FIELDS = { "EndCaps", "BorderArt", "Background", "ArtFrame", "ActionBarPageNumber" }
-- The game's own experience and reputation bars, by every name they have had.
local STATUS_BARS = {
    "MainMenuExpBar", "ReputationWatchBar", "MainMenuBarMaxLevelBar", "StatusTrackingBarManager",
    "MainStatusTrackingBarContainer", "SecondaryStatusTrackingBarContainer",
}

local function settings()
    return ns.Overhaul.Settings().bars
end

local function frame(name)
    local f = _G[name]
    return type(f) == "table" and f or nil
end

local function isSecret(v)
    return issecretvalue ~= nil and issecretvalue(v) == true
end

local function blankRegions(f)
    return ns.Overhaul.BlankRegions(f)
end
Bars.BlankRegions = blankRegions

---------------------------------------------------------------------------
-- One button
---------------------------------------------------------------------------

local skinned = setmetatable({}, { __mode = "k" })   -- buttons already dressed (the layout is redone now and then)

local function skinButton(b, size)
    local W = ns.W
    local name = b.GetName and b:GetName()
    if type(name) ~= "string" then name = "" end
    pcall(b.SetSize, b, size, size)
    if skinned[b] then return end
    skinned[b] = true
    W.skin(b, W.COLOR.panel)

    -- The round Blizzard button texture, and the green "equipped" border: gone. The game
    -- sets the normal texture again whenever the button gets an action, so it is kept blank
    -- after every such call.
    local normal = b.GetNormalTexture and b:GetNormalTexture()
    if normal then pcall(normal.SetAlpha, normal, 0) end
    if hooksecurefunc and b.SetNormalTexture then
        pcall(hooksecurefunc, b, "SetNormalTexture", function(self)
            local t = self:GetNormalTexture()
            if t then t:SetAlpha(0) end
        end)
    end
    ns.Overhaul.Blank(frame(name .. "Border"))
    ns.Overhaul.Blank(frame(name .. "FloatingBG"))
    -- Newer clients keep the slot art in fields.
    for _, field in ipairs({ "SlotArt", "SlotBackground", "RightDivider", "BottomDivider" }) do
        if type(b[field]) == "table" then ns.Overhaul.Blank(b[field]) end
    end

    local icon = frame(name .. "Icon") or (type(b.icon) == "table" and b.icon or nil)
    if icon then
        -- The game rounds the icon's corners with a mask. The mask is taken OFF the icon, not
        -- blanked: an empty mask hides everything under it, the icon included.
        if type(b.IconMask) == "table" and type(icon.RemoveMaskTexture) == "function" then
            pcall(icon.RemoveMaskTexture, icon, b.IconMask)
        end
        -- Above the button's backdrop, which is drawn on the icon's own layer.
        if type(icon.SetDrawLayer) == "function" then pcall(icon.SetDrawLayer, icon, "ARTWORK", -1) end
        pcall(icon.SetTexCoord, icon, 0.08, 0.92, 0.08, 0.92)
        pcall(icon.ClearAllPoints, icon)
        pcall(icon.SetPoint, icon, "TOPLEFT", b, "TOPLEFT", 1, -1)
        pcall(icon.SetPoint, icon, "BOTTOMRIGHT", b, "BOTTOMRIGHT", -1, 1)
    end
    for _, suffix in ipairs({ "Cooldown", "Flash" }) do
        local t = frame(name .. suffix)
        if t then
            pcall(t.ClearAllPoints, t)
            pcall(t.SetPoint, t, "TOPLEFT", b, "TOPLEFT", 1, -1)
            pcall(t.SetPoint, t, "BOTTOMRIGHT", b, "BOTTOMRIGHT", -1, 1)
        end
    end

    -- Flat hover, pressed and "this is on" states.
    if b.SetHighlightTexture then
        pcall(b.SetHighlightTexture, b, W.WHITE)
        local t = b:GetHighlightTexture()
        if t then pcall(t.SetVertexColor, t, 1, 1, 1, 0.15); pcall(t.SetAllPoints, t, b) end
    end
    if b.SetPushedTexture then
        pcall(b.SetPushedTexture, b, W.WHITE)
        local t = b:GetPushedTexture()
        if t then pcall(t.SetVertexColor, t, 0, 0, 0, 0.4); pcall(t.SetAllPoints, t, b) end
    end
    if b.SetCheckedTexture then
        pcall(b.SetCheckedTexture, b, W.WHITE)
        local t = b:GetCheckedTexture()
        if t then
            local r, g, bl = W.accent()
            pcall(t.SetVertexColor, t, r, g, bl, 0.3)
            pcall(t.SetAllPoints, t, b)
        end
    end

    local hotkey = frame(name .. "HotKey") or (type(b.HotKey) == "table" and b.HotKey or nil)
    if hotkey then
        pcall(hotkey.ClearAllPoints, hotkey)
        pcall(hotkey.SetPoint, hotkey, "TOPRIGHT", b, "TOPRIGHT", -2, -2)
        pcall(hotkey.SetJustifyH, hotkey, "RIGHT")
        pcall(hotkey.SetFontObject, hotkey, "GameFontHighlightSmall")
    end
    local count = frame(name .. "Count") or (type(b.Count) == "table" and b.Count or nil)
    if count then
        pcall(count.ClearAllPoints, count)
        pcall(count.SetPoint, count, "BOTTOMRIGHT", b, "BOTTOMRIGHT", -2, 2)
    end
    local macro = frame(name .. "Name") or (type(b.Name) == "table" and b.Name or nil)
    if macro then
        pcall(macro.ClearAllPoints, macro)
        pcall(macro.SetPoint, macro, "BOTTOM", b, "BOTTOM", 0, 2)
        pcall(macro.SetWidth, macro, size - 4)
    end
end

---------------------------------------------------------------------------
-- Bars
---------------------------------------------------------------------------

-- The buttons of a bar that exist on this client.
local function buttonsOf(def)
    local out = {}
    for i = 1, def.count do
        local b = frame(def.prefix .. i) or (def.alt and frame(def.alt .. i))
        if b then out[#out + 1] = b end
    end
    return out
end

-- Is the game showing this bar at all? (Unknown counts as yes.)
local function barShown(def)
    for _, name in ipairs(BAR_FRAMES[def.key] or {}) do
        local f = frame(name)
        if f and type(f.IsShown) == "function" then
            local ok, shown = pcall(f.IsShown, f)
            if ok and shown == false then return false end
            if ok then return true end
        end
    end
    return true
end

local function layoutBar(def)
    local s = settings()
    local buttons = buttonsOf(def)
    if #buttons == 0 then return false end
    local size = def.small and floor(s.size * 0.8 + 0.5) or s.size
    local step = size + s.spacing
    local long = #buttons * step - s.spacing
    local label = def.label .. (barShown(def) and "" or " (hidden right now)")
    local mover = ns.Overhaul.Mover(def.key, label, def.vertical and size or long, def.vertical and long or size, def.default)
    for i, b in ipairs(buttons) do
        skinButton(b, size)
        pcall(b.ClearAllPoints, b)
        if def.vertical then
            pcall(b.SetPoint, b, "TOPLEFT", mover, "TOPLEFT", 0, -(i - 1) * step)
        else
            pcall(b.SetPoint, b, "TOPLEFT", mover, "TOPLEFT", (i - 1) * step, 0)
        end
    end
    return true
end

-- The keyring has no picture of its own on a newer client, only a slot outline, and an empty
-- reagent bag slot looks like any other empty bag slot. The game also sets its own picture on
-- them again whenever it likes, so each gets a picture of the addon's own drawn over the
-- game's: a key on the keyring, and a dimmed herb on the reagent slot while it is empty.
local KEYRING_ICON = "Interface\\Icons\\INV_Misc_Key_03"
local REAGENT_ICON = "Interface\\Icons\\Trade_Herbalism"
local EXTRA_BAGS = { CharacterReagentBag0Slot = true, KeyRingButton = true }
local extraIcons = setmetatable({}, { __mode = "k" })   -- button -> the addon's own picture on it
Bars.extraIcons = extraIcons

local function extraIcon(b)
    local t = extraIcons[b]
    if not t then
        t = b:CreateTexture(nil, "ARTWORK", nil, 2)
        t:SetPoint("TOPLEFT", b, "TOPLEFT", 1, -1)
        t:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", -1, 1)
        if t.SetTexCoord then t:SetTexCoord(0.08, 0.92, 0.08, 0.92) end
        extraIcons[b] = t
    end
    return t
end

-- Is there a bag in this bag slot? nil when the client will not say.
local function slotFilled(b)
    if type(GetInventoryItemTexture) ~= "function" or type(b.GetID) ~= "function" then return nil end
    local okID, id = pcall(b.GetID, b)
    if not okID or type(id) ~= "number" or id <= 0 then return nil end
    local ok, texture = pcall(GetInventoryItemTexture, "player", id)
    if not ok then return nil end
    return texture ~= nil
end

-- What a click on the keyring or the reagent slot did, for /mint uidump: the addon does not
-- handle these clicks (they are the game's buttons), so when one seems to do nothing, this
-- says whether the click arrived at all and whether the game opened anything.
Bars.clicks = {}
local clickWatched = setmetatable({}, { __mode = "k" })

local function watchClicks(b, name)
    if clickWatched[b] or type(b.HookScript) ~= "function" then return end
    clickWatched[b] = true
    pcall(b.HookScript, b, "OnClick", function(self, mouseButton)
        local c = Bars.clicks[name] or { count = 0 }
        c.count = c.count + 1
        c.button = type(mouseButton) == "string" and mouseButton or nil
        local okID, id = pcall(self.GetID, self)
        c.id = okID and type(id) == "number" and id or nil
        if type(self.GetBagID) == "function" then
            local ok, bag = pcall(self.GetBagID, self)
            c.bag = ok and type(bag) == "number" and bag or nil
        end
        if type(IsBagOpen) == "function" and c.bag then
            local ok, open = pcall(IsBagOpen, c.bag)
            c.open = ok and (open and true or false) or nil
        end
        Bars.clicks[name] = c
    end)
end

-- The keyring's key and the reagent slot's herb. Run with every layout and once a second:
-- putting a bag in the reagent slot, or taking it out, changes what is shown.
local function dressExtraBags()
    local key = frame("KeyRingButton")
    if key then watchClicks(key, "KeyRingButton") end
    local reagentSlot = frame("CharacterReagentBag0Slot")
    if reagentSlot then watchClicks(reagentSlot, "CharacterReagentBag0Slot") end
    if key then
        local own = extraIcon(key)
        own:SetTexture(KEYRING_ICON)
        own:Show()
        local theirs = frame("KeyRingButtonIconTexture")
        if theirs then pcall(theirs.SetAlpha, theirs, 0) end
    end
    local reagent = frame("CharacterReagentBag0Slot")
    if reagent then
        local own = extraIcon(reagent)
        local theirs = frame("CharacterReagentBag0SlotIconTexture")
        if slotFilled(reagent) then
            own:Hide()
            if theirs then pcall(theirs.SetAlpha, theirs, 1) end
        else
            own:SetTexture(REAGENT_ICON)
            if own.SetDesaturated then pcall(own.SetDesaturated, own, true) end
            own:SetAlpha(0.45)
            own:Show()
            if theirs then pcall(theirs.SetAlpha, theirs, 0) end
        end
    end
end

-- The bag buttons in the row: the backpack and the four bags, and the reagent bag slot and
-- the keyring unless the settings leave those out.
local function bagButtons()
    local s = settings()
    local shown, left = {}, {}
    for _, name in ipairs(BAG_BUTTONS) do
        local b = frame(name)
        if b then
            if EXTRA_BAGS[name] and not s.extraBags then left[#left + 1] = b else shown[#shown + 1] = b end
        end
    end
    return shown, left
end

local function layoutBags()
    local s = settings()
    local buttons, left = bagButtons()
    for _, b in ipairs(left) do pcall(b.Hide, b) end
    if #buttons == 0 then return end
    local size, step = s.size, s.size + s.spacing
    local mover = ns.Overhaul.Mover("bags", "Bags", #buttons * step - s.spacing, size, { "BOTTOMRIGHT", -20, 36 })
    for i, b in ipairs(buttons) do
        skinButton(b, size)
        local name = b.GetName and b:GetName()
        local icon = type(name) == "string" and frame(name .. "IconTexture") or nil
        if icon and name ~= "KeyRingButton" then   -- the keyring's own picture is an outline: left alone, and covered
            if type(icon.SetDrawLayer) == "function" then pcall(icon.SetDrawLayer, icon, "ARTWORK", -1) end
            pcall(icon.SetTexCoord, icon, 0.08, 0.92, 0.08, 0.92)
            pcall(icon.ClearAllPoints, icon)
            pcall(icon.SetPoint, icon, "TOPLEFT", b, "TOPLEFT", 1, -1)
            pcall(icon.SetPoint, icon, "BOTTOMRIGHT", b, "BOTTOMRIGHT", -1, 1)
        end
        pcall(b.ClearAllPoints, b)
        pcall(b.SetPoint, b, "TOPLEFT", mover, "TOPLEFT", (i - 1) * step, 0)
        pcall(b.Show, b)
    end
    if s.extraBags then pcall(dressExtraBags) end
end

---------------------------------------------------------------------------
-- The micro menu
---------------------------------------------------------------------------

-- The micro buttons this client has, in the game's own order when it gives one.
-- Found once and kept: after they are moved onto the addon's strip, the game's container no
-- longer lists them. In order: the game's own list when it has one, then the named buttons
-- in its micro menu as it laid them out, then any known name not yet seen.
local microList

local function microButtons()
    if microList then return microList end
    local out, seen = {}, {}
    local function add(b)
        if type(b) == "table" and not seen[b] then
            seen[b] = true
            out[#out + 1] = b
        end
    end
    if type(MICRO_BUTTONS) == "table" then
        for _, name in ipairs(MICRO_BUTTONS) do
            if type(name) == "string" then add(frame(name)) end
        end
    end
    local menu = frame("MicroMenu")
    if menu and type(menu.GetChildren) == "function" then
        local ok, children = pcall(function() return { menu:GetChildren() } end)
        for _, c in ipairs(ok and children or {}) do
            local okType, kind = pcall(function() return c:GetObjectType() end)
            local okName, name = pcall(function() return c:GetName() end)
            if okType and kind == "Button" and okName and type(name) == "string" and name:find("MicroButton", 1, true) then add(c) end
        end
    end
    for _, name in ipairs(MICRO_BUTTONS_KNOWN) do add(frame(name)) end
    if #out > 0 then microList = out end
    return out
end

-- The stone slab behind each micro button's icon goes; the icon stays.
local function skinMicro(b)
    if skinned[b] then return end
    skinned[b] = true
    for _, field in ipairs({ "Background", "PushedBackground", "Shadow", "PushedShadow" }) do
        if type(b[field]) == "table" then ns.Overhaul.Blank(b[field]) end
    end
end

local microBar

-- The micro buttons in a row on a flat strip of their own, on the "micro" mover. The buttons
-- stay the game's (what they open, their art); the strip and the place are the addon's.
local function placeMicro()
    local W = ns.W
    local buttons = microButtons()
    if #buttons == 0 then return end
    local s = settings()
    if s.hideMicro then
        for _, b in ipairs(buttons) do ns.Overhaul.HideBlizzard(b) end
        if microBar then microBar:Hide() end
        return
    end
    local w, h, pad = 24, 30, 2
    local mover = ns.Overhaul.Mover("micro", "Micro menu", #buttons * (w + 1) - 1 + 2 * pad, h + 2 * pad, { "BOTTOMRIGHT", -20, 72 })
    if not microBar then
        microBar = W.safeCreate("Frame", "MintCommunityToolsMicroBar", UIParent, W.template())
        microBar:SetFrameStrata("LOW")
        W.skin(microBar, W.COLOR.panel)
    end
    microBar:ClearAllPoints()
    microBar:SetPoint("TOPLEFT", mover, "TOPLEFT", 0, 0)
    microBar:SetPoint("BOTTOMRIGHT", mover, "BOTTOMRIGHT", 0, 0)
    microBar:Show()
    for i, b in ipairs(buttons) do
        skinMicro(b)
        pcall(b.SetParent, b, microBar)
        pcall(b.SetSize, b, w, h)
        pcall(b.ClearAllPoints, b)
        pcall(b.SetPoint, b, "BOTTOMLEFT", microBar, "BOTTOMLEFT", pad + (i - 1) * (w + 1), pad)
        pcall(b.Show, b)
    end
    Bars.microCount = #buttons
end

local function layoutMicro()
    placeMicro()
    -- The game puts its micro buttons back in their own bar now and then; so does this, after.
    if hooksecurefunc and not Bars.microHooked then
        Bars.microHooked = true
        for _, fn in ipairs({ "UpdateMicroButtonsParent", "MoveMicroButtons", "UpdateMicroButtons" }) do
            if type(_G[fn]) == "function" then
                pcall(hooksecurefunc, fn, function()
                    if InCombatLockdown and InCombatLockdown() then return end
                    pcall(placeMicro)
                end)
            end
        end
    end
    -- Newer clients hold the micro menu and the bags in containers of their own.
    for _, name in ipairs({ "MicroMenuContainer", "MicroMenu", "MicroButtonAndBagsBar" }) do
        local f = frame(name)
        if f then
            blankRegions(f)
            pcall(f.EnableMouse, f, false)
        end
    end
end

---------------------------------------------------------------------------
-- The experience bar: the addon's own
---------------------------------------------------------------------------

local xp = {}
Bars.xp = xp

-- What the bar shows: experience when there is some to gain, else the watched reputation,
-- else nothing. Returns kind, current, maximum, rested, label, colour.
local function atLevelCap()
    if IsPlayerAtEffectiveMaxLevel then
        local ok, capped = pcall(IsPlayerAtEffectiveMaxLevel)
        if ok then return capped == true end
    end
    local level = UnitLevel and UnitLevel("player")
    if type(level) ~= "number" or isSecret(level) then return false end
    for _, fn in ipairs({ "GetMaxLevelForPlayerExpansion", "GetMaxPlayerLevel" }) do
        if type(_G[fn]) == "function" then
            local ok, cap = pcall(_G[fn])
            if ok and type(cap) == "number" then return level >= cap end
        end
    end
    return false
end

-- The watched reputation as name, standing, low, high, value; by the old call or the new.
local function watchedFaction()
    if GetWatchedFactionInfo then
        local ok, name, standing, low, high, value = pcall(GetWatchedFactionInfo)
        if ok then return name, standing, low, high, value end
    end
    if C_Reputation and C_Reputation.GetWatchedFactionData then
        local ok, d = pcall(C_Reputation.GetWatchedFactionData)
        if ok and type(d) == "table" then
            return d.name, d.reaction, d.currentReactionThreshold, d.nextReactionThreshold, d.currentStanding
        end
    end
    return nil
end

function Bars.ExperienceState()
    local W = ns.W
    local cur = UnitXP and UnitXP("player")
    local maxv = UnitXPMax and UnitXPMax("player")
    if isSecret(cur) or isSecret(maxv) then return "xp", cur, maxv, nil, "Experience", { W.accent() } end
    if type(cur) == "number" and type(maxv) == "number" and maxv > 0 then
        if not atLevelCap() then
            local rested = GetXPExhaustion and GetXPExhaustion()
            if type(rested) ~= "number" or isSecret(rested) then rested = nil end
            return "xp", cur, maxv, rested, "Experience", { W.accent() }
        end
    end
    local name, standing, low, high, value = watchedFaction()
    if type(name) == "string" and type(low) == "number" and type(high) == "number" and type(value) == "number"
        and not (isSecret(low) or isSecret(high) or isSecret(value)) and high > low then
        local c = type(standing) == "number" and FACTION_BAR_COLORS and FACTION_BAR_COLORS[standing]
        local color = (type(c) == "table" and type(c.r) == "number") and { c.r, c.g, c.b, 1 } or { 0.3, 0.8, 0.3, 1 }
        return "rep", value - low, high - low, nil, name, color
    end
    return nil
end

local function refreshExperience()
    if not xp.bar then return end
    local kind, cur, maxv, rested, label, color = Bars.ExperienceState()
    xp.kind, xp.cur, xp.max, xp.restedValue, xp.label = kind, cur, maxv, rested, label
    if not kind then
        xp.frame:Hide()
        return
    end
    pcall(xp.bar.SetMinMaxValues, xp.bar, 0, maxv)
    pcall(xp.bar.SetValue, xp.bar, cur)
    xp.bar:SetStatusBarColor(color[1], color[2], color[3], 1)
    if rested and rested > 0 then
        local to = cur + rested
        if to > maxv then to = maxv end
        xp.rested:SetMinMaxValues(0, maxv)
        xp.rested:SetValue(to)
        xp.rested:Show()
    else
        xp.rested:Hide()
    end
    xp.frame:Show()
end

local function experienceTooltip(self)
    local W = ns.W
    if not (GameTooltip and xp.kind) then return end
    GameTooltip:SetOwner(self, "ANCHOR_TOP")
    GameTooltip:SetText(xp.label or "Experience", 1, 1, 1)
    if isSecret(xp.cur) or isSecret(xp.max) then
        local ok, text = pcall(sformat, "%d / %d", xp.cur, xp.max)
        if ok then GameTooltip:AddLine(text, 0.8, 0.8, 0.8) end
    else
        GameTooltip:AddLine(sformat("%s / %s  (%d%%)", W.commas(xp.cur), W.commas(xp.max), floor(xp.cur / xp.max * 100 + 0.5)), 0.8, 0.8, 0.8)
        if xp.kind == "xp" then
            GameTooltip:AddLine(sformat("%s to go", W.commas(xp.max - xp.cur)), 0.6, 0.6, 0.6)
            if xp.restedValue and xp.restedValue > 0 then
                GameTooltip:AddLine(sformat("Rested: %s", W.commas(xp.restedValue)), 0.4, 0.6, 1)
            end
        end
    end
    GameTooltip:Show()
end

local function buildExperience()
    local W = ns.W
    -- The game's own bars go, whatever this client calls them.
    for _, name in ipairs(STATUS_BARS) do ns.Overhaul.HideBlizzard(frame(name)) end

    local s = settings()
    local width = 12 * (s.size + s.spacing) - s.spacing
    local mover = ns.Overhaul.Mover("xp", "Experience bar", width, 8, { "BOTTOM", 0, 24 })
    if not xp.frame then
        xp.frame = W.safeCreate("Frame", "MintCommunityToolsExperienceBar", UIParent, W.template())
        xp.frame:SetFrameStrata("LOW")
        W.skin(xp.frame, W.COLOR.panel)
        -- Rested experience: a dimmer bar behind the real one, reaching further.
        xp.rested = CreateFrame("StatusBar", nil, xp.frame)
        xp.rested:SetStatusBarTexture(W.WHITE)
        xp.rested:SetStatusBarColor(0.25, 0.45, 0.9, 0.5)
        xp.rested:SetPoint("TOPLEFT", 1, -1)
        xp.rested:SetPoint("BOTTOMRIGHT", -1, 1)
        xp.bar = CreateFrame("StatusBar", nil, xp.frame)
        xp.bar:SetStatusBarTexture(W.WHITE)
        xp.bar:SetPoint("TOPLEFT", 1, -1)
        xp.bar:SetPoint("BOTTOMRIGHT", -1, 1)
        xp.frame:EnableMouse(true)
        xp.frame:SetScript("OnEnter", experienceTooltip)
        xp.frame:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
        for _, ev in ipairs({ "PLAYER_XP_UPDATE", "PLAYER_LEVEL_UP", "UPDATE_EXHAUSTION", "PLAYER_UPDATE_RESTING", "UPDATE_FACTION", "PLAYER_ENTERING_WORLD" }) do
            pcall(xp.frame.RegisterEvent, xp.frame, ev)
        end
        xp.frame:SetScript("OnEvent", refreshExperience)
    end
    xp.frame:ClearAllPoints()
    xp.frame:SetPoint("TOPLEFT", mover, "TOPLEFT", 0, 0)
    xp.frame:SetPoint("BOTTOMRIGHT", mover, "BOTTOMRIGHT", 0, 0)
    refreshExperience()
end

---------------------------------------------------------------------------
-- Art
---------------------------------------------------------------------------

local function hideArt()
    local n = 0
    for _, name in ipairs(ART) do
        if ns.Overhaul.Blank(frame(name)) then n = n + 1 end
    end
    for _, name in ipairs(ART_FRAMES) do
        local f = frame(name)
        if f then
            n = n + blankRegions(f)
            -- Fields a newer client keeps its end caps and borders in.
            for _, field in ipairs(ART_FIELDS) do
                local part = f[field]
                if type(part) == "table" then
                    n = n + blankRegions(part)
                    pcall(part.SetAlpha, part, 0)
                    pcall(part.EnableMouse, part, false)
                    n = n + 1
                end
            end
        end
    end
    Bars.artHidden = n
end

function Bars.Apply()
    for _, name in ipairs({ "MainMenuBar", "MainActionBar" }) do
        local main = frame(name)
        if main then
            main.ignoreFramePositionManager = true
            pcall(main.SetMovable, main, true)
            pcall(main.SetUserPlaced, main, true)
            pcall(main.EnableMouse, main, false)
        end
    end
    hideArt()
    local art = frame("MainMenuBarArtFrame")
    if art then pcall(art.EnableMouse, art, false) end
    -- The game lays the other bars out from the main bar; they are not to be moved back.
    for _, name in ipairs({ "MultiBarBottomLeft", "MultiBarBottomRight", "MultiBarRight", "MultiBarLeft", "PetActionBarFrame", "PetActionBar", "StanceBarFrame", "StanceBar", "ShapeshiftBarFrame" }) do
        local f = frame(name)
        if f then
            f.ignoreFramePositionManager = true
            pcall(f.EnableMouse, f, false)
        end
    end
    Bars.laid = {}
    for _, def in ipairs(BARS) do
        if layoutBar(def) then Bars.laid[#Bars.laid + 1] = def.key end
    end
    layoutBags()
    layoutMicro()
    buildExperience()
    -- The game's own edit mode lays its bars out again when it closes; so does this, after.
    if hooksecurefunc and type(EditModeManagerFrame) == "table" and type(EditModeManagerFrame.ExitEditMode) == "function" then
        pcall(hooksecurefunc, EditModeManagerFrame, "ExitEditMode", function() Bars.Relayout() end)
    end
    -- The bag bar chains its buttons to itself every time it lays out: put them back at once.
    local bagsBar = frame("BagsBar")
    if hooksecurefunc and bagsBar and type(bagsBar.Layout) == "function" then
        pcall(hooksecurefunc, bagsBar, "Layout", function()
            if not (InCombatLockdown and InCombatLockdown()) then pcall(layoutBags) end
        end)
    end
    -- And a look once a second, for whatever else moves a button.
    if not Bars.watch then
        Bars.watch = CreateFrame("Frame")
        local elapsed = 0
        Bars.watch:SetScript("OnUpdate", function(_, dt)
            elapsed = elapsed + (type(dt) == "number" and dt or 0)
            if elapsed < 1 then return end
            elapsed = 0
            Bars.Check()
        end)
    end
    Bars.applied = true
end

-- Has the game pulled this button off the frame the addon anchored it to?
local function strayed(b, anchor)
    local ok, _, relativeTo = pcall(b.GetPoint, b, 1)
    return ok and relativeTo ~= anchor
end

-- The game lays its own bars out again whenever it sees fit (a bag changes, its edit mode
-- closes, the world loads), and that pulls buttons back to where it wants them. This looks
-- at every bar and puts back any that moved. Returns how many it had to fix. Not in combat:
-- the game does not let its action buttons be moved then.
function Bars.Check()
    if InCombatLockdown and InCombatLockdown() then return 0 end
    local movers = ns.Overhaul.movers
    local fixed = 0
    for _, def in ipairs(BARS) do
        local mover = movers[def.key]
        if mover then
            for _, b in ipairs(buttonsOf(def)) do
                if strayed(b, mover) then
                    pcall(layoutBar, def)
                    fixed = fixed + 1
                    break
                end
            end
        end
    end
    if movers.bags then
        for _, b in ipairs((bagButtons())) do
            if strayed(b, movers.bags) then
                pcall(layoutBags)
                fixed = fixed + 1
                break
            end
        end
        if settings().extraBags then pcall(dressExtraBags) end
    end
    if microBar and not settings().hideMicro then
        for _, b in ipairs(microButtons()) do
            if strayed(b, microBar) then
                pcall(placeMicro)
                fixed = fixed + 1
                break
            end
        end
    end
    return fixed
end

-- Puts every button back on its mover and sweeps the art again. Not in combat: the game does
-- not let its action buttons be moved then.
function Bars.Relayout()
    if InCombatLockdown and InCombatLockdown() then return false end
    hideArt()
    for _, def in ipairs(BARS) do pcall(layoutBar, def) end
    pcall(layoutBags)
    pcall(placeMicro)
    refreshExperience()
    return true
end

-- The game re-lays its bars out when the world loads; so does this, after.
function Bars.OnEnteringWorld()
    Bars.Relayout()
end

function Bars.OnSettingsChanged(path)
    if path == "bars.hideMicro" and not settings().hideMicro then pcall(placeMicro) end
    if path == "bars.extraBags" then pcall(layoutBags) end
end
