--[[
    Dump.lua - /mint uidump: a record of what this client's own interface is made of.

    The game's frames are not the same from one version to the next (what the gryphons are
    called, where the experience bar lives, what the minimap's border is), and the WoW
    Forever client has no public documentation. This writes down what is really there:
    for each frame the overhaul cares about, its name, type, size, anchor and whether it is
    shown; every texture drawn on it (with the file or atlas it shows, which is how a
    gryphon or a round border is told from everything else); and its child frames, a few
    levels down. It also notes which functions the overhaul would like to use exist.

    The record goes into the saved variables (uiDump), which the game writes to disk at the
    next /reload or logout. Nothing is sent anywhere.

    /mint uidump records the frames on screen during play (bars, unit frames, chat, minimap,
    quest tracker). /mint uidump menus records the game menu and the windows it opens
    instead: open the game menu and each of those windows once first, so that they exist.
    /mint uidump bags records the bag windows: have your bags open when you type it.
]]

local ADDON, ns = ...
local Dump = {}
ns.Dump = Dump

local pairs, ipairs, type, tostring, pcall = pairs, ipairs, type, tostring, pcall
local floor = math.floor

local MAX_NODES = 2500

-- name -> how many levels of child frames to follow
local ROOTS = {
    { "MainMenuBar", 3 }, { "MainActionBar", 3 }, { "MainMenuBarArtFrame", 2 }, { "ActionBarController", 0 },
    { "MicroMenuContainer", 3 }, { "MicroMenu", 2 }, { "MicroButtonAndBagsBar", 2 }, { "BagsBar", 2 },
    { "CharacterMicroButton", 1 }, { "MainMenuMicroButton", 1 }, { "MainMenuBarBackpackButton", 1 }, { "CharacterBag0Slot", 1 },
    { "StatusTrackingBarManager", 3 }, { "MainStatusTrackingBarContainer", 2 }, { "SecondaryStatusTrackingBarContainer", 2 },
    { "MainMenuExpBar", 1 }, { "ReputationWatchBar", 1 }, { "MainMenuBarMaxLevelBar", 0 },
    { "MinimapCluster", 3 }, { "Minimap", 2 }, { "MinimapBackdrop", 2 },
    { "ActionButton1", 1 }, { "MultiBarBottomLeft", 1 }, { "MultiBarBottomRight", 0 }, { "MultiBarRight", 0 }, { "MultiBarLeft", 0 },
    { "MultiBarBottomLeftButton1", 0 }, { "PetActionBar", 1 }, { "PetActionBarFrame", 1 }, { "PetActionButton1", 0 },
    { "StanceBar", 1 }, { "StanceBarFrame", 1 }, { "StanceButton1", 0 },
    { "PlayerFrame", 1 }, { "TargetFrame", 1 }, { "TargetFrameToT", 0 }, { "PetFrame", 0 }, { "ComboFrame", 0 },
    { "ChatFrame1", 1 }, { "ChatFrame1Tab", 0 }, { "ChatFrame1EditBox", 0 }, { "ChatFrame1ButtonFrame", 1 },
    { "ChatFrameMenuButton", 0 }, { "ChatFrameChannelButton", 0 }, { "QuickJoinToastButton", 0 },
    { "BuffFrame", 0 }, { "CastingBarFrame", 0 }, { "PlayerCastingBarFrame", 0 }, { "EditModeManagerFrame", 0 },
    { "GameTimeFrame", 0 }, { "TimeManagerClockButton", 0 }, { "MiniMapTracking", 1 }, { "MiniMapMailFrame", 0 },
    -- quests: the on-screen tracker and the quest log window, by every name they have had
    { "ObjectiveTrackerFrame", 3 }, { "QuestObjectiveTracker", 2 }, { "QuestWatchFrame", 2 }, { "WatchFrame", 2 },
    { "QuestLogFrame", 2 }, { "QuestMapFrame", 2 }, { "QuestScrollFrame", 1 }, { "WorldMapFrame", 1 }, { "QuestFrame", 1 },
    { "QuestLogDetailFrame", 1 }, { "UIParentRightManagedFrameContainer", 1 },
}

-- /mint uidump menus: the game menu and the windows it opens, a good way down.
local MENU_ROOTS = {
    { "GameMenuFrame", 4 }, { "SettingsPanel", 4 }, { "AddonList", 4 }, { "EditModeManagerFrame", 3 },
    { "MacroFrame", 3 }, { "HelpFrame", 2 }, { "KeyBindingFrame", 2 }, { "InterfaceOptionsFrame", 2 },
    { "VideoOptionsFrame", 2 }, { "StaticPopup1", 2 }, { "GameTooltip", 1 }, { "DropDownList1", 1 },
}
-- /mint uidump bags: the bag windows (open your bags first) and what sits in them.
local BAG_ROOTS = {
    { "ContainerFrameCombinedBags", 3 }, { "ContainerFrame1", 3 }, { "ContainerFrame2", 2 }, { "ContainerFrame6", 2 },
    { "BagItemSearchBox", 1 }, { "BagItemAutoSortButton", 1 }, { "BackpackTokenFrame", 2 }, { "ContainerFrame1MoneyFrame", 1 },
    { "BankFrame", 2 }, { "MerchantFrame", 1 },
}
local GROUPS = { menus = MENU_ROOTS, bags = BAG_ROOTS }

-- Functions and tables the overhaul would like to use.
local APIS = {
    "issecretvalue", "hooksecurefunc", "RegisterUnitWatch", "RegisterStateDriver", "InCombatLockdown",
    "EditModeManagerFrame", "C_EditMode", "UnitAura", "UnitBuff", "UnitDebuff", "C_UnitAuras", "AbbreviateNumbers",
    "UnitHealthPercent", "CurveConstants", "UnitXP", "UnitXPMax", "GetXPExhaustion", "IsPlayerAtEffectiveMaxLevel",
    "GetWatchedFactionInfo", "C_Reputation", "MICRO_BUTTONS", "UpdateMicroButtonsParent", "MoveMicroButtons",
    "UpdateMicroButtons", "Minimap_ZoomIn", "GetMinimapZoneText", "GetZonePVPInfo", "C_Map", "GetGameTime",
    "FCF_RestorePositionAndDimensions", "CHAT_FRAME_TEXTURES", "NUM_CHAT_WINDOWS", "C_ChatInfo", "SetPortraitTexture",
    "GetQuestDifficultyColor", "RAID_CLASS_COLORS", "PowerBarColor", "FACTION_BAR_COLORS", "DebuffTypeColor",
    "UIParent_ManageFramePositions", "ActionBarController", "C_AddOns", "ReloadUI",
    "C_QuestLog", "GetNumQuestWatches", "GetQuestIndexForWatch", "GetQuestLogTitle", "GetQuestLogLeaderBoard",
    "GetNumQuestLogEntries", "QuestMapFrame_OpenToQuestDetails", "QuestLog_SetSelection", "ToggleQuestLog",
    "RemoveQuestWatch", "AddQuestWatch", "GetQuestLogSpecialItemInfo", "UnitIsVisible", "GetInventoryItemTexture",
}

local function safe(fn, ...)
    if type(fn) ~= "function" then return nil end
    local ok, a, b, c, d, e = pcall(fn, ...)
    if ok then return a, b, c, d, e end
    return nil
end

local function plain(v)
    return not (issecretvalue and issecretvalue(v))
end

local function str(v)
    if type(v) == "string" and plain(v) then return v end
    return nil
end

local function num(v)
    if type(v) == "number" and plain(v) then return floor(v * 10 + 0.5) / 10 end
    return nil
end

local function nameOf(obj)
    if type(obj) ~= "table" then return nil end
    return str(safe(obj.GetName, obj))
end

-- The field of `parent` that holds `child` ("EndCaps", "BorderTop"), for parts without a name.
local function keyIn(parent, child)
    if type(parent) ~= "table" then return nil end
    local ok, key = pcall(function()
        for k, v in pairs(parent) do
            if v == child and type(k) == "string" then return k end
        end
    end)
    return ok and key or nil
end

local nodes

local function describe(obj, parent)
    nodes = nodes + 1
    local d = {}
    d.name = nameOf(obj)
    d.key = keyIn(parent, obj)
    d.type = str(safe(obj.GetObjectType, obj))
    d.shown = safe(obj.IsShown, obj) == true
    d.alpha = num(safe(obj.GetAlpha, obj))
    d.w, d.h = num(safe(obj.GetWidth, obj)), num(safe(obj.GetHeight, obj))
    local point, rel, relPoint, x, y = safe(obj.GetPoint, obj, 1)
    if str(point) then
        d.point = ("%s -> %s %s %s,%s"):format(point, nameOf(rel) or "?", tostring(str(relPoint)), tostring(num(x)), tostring(num(y)))
    end
    if d.type == "Texture" then
        local texture = safe(obj.GetTexture, obj)
        if plain(texture) and (type(texture) == "string" or type(texture) == "number") then d.texture = tostring(texture) end
        d.atlas = str(safe(obj.GetAtlas, obj))
        d.layer = str(safe(obj.GetDrawLayer, obj))
    elseif d.type == "FontString" then
        local text = str(safe(obj.GetText, obj))
        if text then d.text = text:sub(1, 40) end
    else
        d.strata = str(safe(obj.GetFrameStrata, obj))
        d.parent = nameOf(safe(obj.GetParent, obj))
        d.level = num(safe(obj.GetFrameLevel, obj))
        if safe(obj.IsMouseEnabled, obj) == true then d.mouse = true end
    end
    return d
end

-- The bag row's buttons, and what this client has for a keyring and a reagent bag: whether
-- the buttons can be clicked at all, what the game thinks is in those slots, and what a
-- click on them did (ActionBars.lua keeps count).
local BAG_NAMES = { "MainMenuBarBackpackButton", "CharacterBag0Slot", "CharacterReagentBag0Slot", "KeyRingButton" }
local BAG_APIS = { "ToggleBag", "ToggleKeyRing", "ToggleAllBags", "OpenBag", "IsBagOpen", "PutKeyInKeyRing", "HasKey", "GetKeyRingSize",
                   "KEYRING_CONTAINER", "C_Container", "ContainerFrame_GetOpenFrame" }

local function plainValue(v)
    if not plain(v) then return "secret" end
    if type(v) == "number" or type(v) == "boolean" or type(v) == "string" then return v end
    return type(v)
end

local function bagInfo()
    local info = { buttons = {}, apis = {}, clicks = ns.Bars and ns.Bars.clicks or {} }
    for _, name in ipairs(BAG_APIS) do info.apis[name] = type(_G[name]) end
    for _, name in ipairs(BAG_NAMES) do
        local b = _G[name]
        if type(b) == "table" then
            local e = {}
            e.id = num(safe(b.GetID, b))
            e.shown, e.visible = safe(b.IsShown, b) == true, safe(b.IsVisible, b) == true
            e.enabled = plainValue(safe(b.IsEnabled, b))
            e.mouse = plainValue(safe(b.IsMouseEnabled, b))
            e.mouseClick = plainValue(safe(b.IsMouseClickEnabled, b))
            e.protected = plainValue(safe(b.IsProtected, b))
            e.strata, e.level = str(safe(b.GetFrameStrata, b)), num(safe(b.GetFrameLevel, b))
            for _, script in ipairs({ "OnClick", "PreClick", "PostClick", "OnMouseDown", "OnMouseUp", "OnEnter" }) do
                e[script] = type(safe(b.GetScript, b, script))
            end
            for _, method in ipairs({ "GetBagID", "BagSlotOnClick", "OnClick", "UpdateTextures", "IsBagOpen" }) do
                if type(b[method]) == "function" then e["has" .. method] = true end
            end
            if type(b.GetBagID) == "function" then e.bag = plainValue(safe(b.GetBagID, b)) end
            if e.id and GetInventoryItemTexture then e.item = type(safe(GetInventoryItemTexture, "player", e.id)) end
            info.buttons[name] = e
        end
    end
    local index = type(Enum) == "table" and type(Enum.BagIndex) == "table" and Enum.BagIndex or {}
    info.keyringIndex = plainValue(index.Keyring or KEYRING_CONTAINER)
    info.reagentIndex = plainValue(index.ReagentBag)
    info.hasKey = plainValue(safe(HasKey))
    info.keyRingSize = plainValue(safe(GetKeyRingSize))
    if type(C_Container) == "table" and type(C_Container.GetContainerNumSlots) == "function" then
        for key, bag in pairs({ keyringSlots = index.Keyring or KEYRING_CONTAINER, reagentSlots = index.ReagentBag }) do
            if type(bag) == "number" then info[key] = plainValue(safe(C_Container.GetContainerNumSlots, bag)) end
        end
    end
    return info
end

local function list(fn, obj)
    if type(fn) ~= "function" then return {} end
    local ok, items = pcall(function() return { fn(obj) } end)
    return ok and items or {}
end

local function walk(frame, parent, depth)
    local d = describe(frame, parent)
    local regions = {}
    for _, r in ipairs(list(frame.GetRegions, frame)) do
        if type(r) == "table" and nodes < MAX_NODES then regions[#regions + 1] = describe(r, frame) end
    end
    if #regions > 0 then d.regions = regions end
    if depth > 0 then
        local children = {}
        for _, c in ipairs(list(frame.GetChildren, frame)) do
            if type(c) == "table" and nodes < MAX_NODES then children[#children + 1] = walk(c, frame, depth - 1) end
        end
        if #children > 0 then d.children = children end
    end
    return d
end

function Dump.Run(group)
    local roots = GROUPS[group or ""] or ROOTS
    nodes = 0
    local version, build, _, toc
    if GetBuildInfo then version, build, _, toc = GetBuildInfo() end
    local out = { at = time(), addon = ns.VERSION, version = version, build = build, toc = toc, apis = {}, frames = {}, missing = {},
                  group = GROUPS[group or ""] and group or "screen" }
    if ns.Menus then
        out.menus = {}
        for name, result in pairs(ns.Menus.windows) do out.menus[name] = result end
    end
    for _, name in ipairs(APIS) do out.apis[name] = type(_G[name]) end
    -- Which of the quest log's own functions this client has, and what it says is tracked.
    if type(C_QuestLog) == "table" then
        out.questApi = {}
        pcall(function()
            for k, v in pairs(C_QuestLog) do
                if type(k) == "string" and type(v) == "function" then out.questApi[#out.questApi + 1] = k end
            end
            table.sort(out.questApi)
        end)
    end
    do
        local ok, bags = pcall(bagInfo)
        out.bags = ok and bags or { error = tostring(bags) }
    end
    if ns.Quests then
        out.quests = { source = ns.Quests.Source() or "none", hidden = ns.Quests.hidden }
        local ok, list = pcall(ns.Quests.List)
        out.quests.tracked = ok and type(list) == "table" and #list or tostring(list)
    end
    if type(MICRO_BUTTONS) == "table" then
        out.micro = {}
        for i, name in ipairs(MICRO_BUTTONS) do
            if type(name) == "string" then out.micro[i] = name end
        end
    end
    local found = 0
    for _, root in ipairs(roots) do
        local f = _G[root[1]]
        if type(f) == "table" and type(f.GetObjectType) == "function" then
            local ok, tree = pcall(walk, f, nil, root[2])
            if ok then
                out.frames[root[1]] = tree
                found = found + 1
            else
                out.frames[root[1]] = { error = tostring(tree) }
            end
        else
            out.missing[#out.missing + 1] = root[1]
        end
    end
    out.count = nodes
    ns.DB().uiDump = out
    ns.Say(("recorded %d of the game's frames (%d frames and textures in all; %d names this client does not have). "
        .. "Type /reload to write it to the save file."):format(found, nodes, #out.missing))
    return out
end
