--[[
    Dump.lua - /mint uidump: a record of what this client's own interface is made of.

    The game's frames are not the same from one version to the next (what the gryphons are
    called, where the experience bar lives, what the minimap's border is), and the WoW
    Forever client has no public documentation. This writes down what is really there:
    for each frame the overhaul cares about, its name, type, size, anchor and whether it is
    shown; every texture drawn on it (with the file or atlas it shows, which is how a
    gryphon or a round border is told from everything else); and its child frames, a few
    levels down. It also notes which functions the overhaul would like to use exist.

    The record goes into the saved variables (uiDump, and uiDumps[group] for each group so
    that several can be taken before one /reload), which the game writes to disk at the next
    /reload or logout. Nothing is sent anywhere. /mint uidump all takes every group at once:
    open the windows first (the game menu and each of its windows, your bags, a vendor, the
    loot window, the damage meter) so that they exist. tools/uidump.lua reads the save file,
    prints a group's frames and says what changed since a copy kept from an earlier client.
    A word after the group names the record (/mint uidump menus gameplay): each named record
    is kept on its own, which is how several pages of one window are recorded, one at a time,
    before a single /reload. The game's Options window only builds the page that is open.
    /mint uidump frame <Name> records any one frame by its name, six levels down, and
    /mint uidump mouse records whatever the mouse is over (point at it, press Enter, type
    the command, press Enter: the mouse stays where it was): the topmost named frame it is
    part of, and the way down to the part under the mouse.

    /mint uidump records the frames on screen during play (bars, unit frames, chat, minimap,
    quest tracker). /mint uidump menus records the game menu and the windows it opens
    instead: open the game menu and each of those windows once first, so that they exist.
    /mint uidump bags records the bag windows: have your bags open when you type it.
    /mint uidump cast records the cast bars and the game's buff frame.
    /mint uidump chat records the chat windows, and with them every point the main window
    is fastened by, its size and place, and what the game had done to it each time the addon
    had to put it back on its mover. Type it while the window is misbehaving, before a reload.
    /mint uidump loot records the loot window: type it while one is open.
    /mint uidump vendor records a vendor's window: type it while one is open.
    /mint uidump meter records the game's own damage meter: have its window on screen, with
    a few bars in it (hit something first), when you type it. It also lists everything the
    game has with "DamageMeter" in its name, since nothing says what this client calls it.
]]

local ADDON, ns = ...
local Dump = {}
ns.Dump = Dump

local pairs, ipairs, type, tostring, pcall = pairs, ipairs, type, tostring, pcall
local floor = math.floor

local MAX_NODES = 4000

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
    { "GameMenuFrame", 4 }, { "SettingsPanel", 8 }, { "AddonList", 4 }, { "EditModeManagerFrame", 3 }, { "EditModeSystemSettingsDialog", 5 },
    { "MacroFrame", 3 }, { "HelpFrame", 2 }, { "KeyBindingFrame", 2 }, { "InterfaceOptionsFrame", 2 },
    { "VideoOptionsFrame", 2 }, { "StaticPopup1", 2 }, { "GameTooltip", 1 }, { "DropDownList1", 1 },
}
-- /mint uidump bags: the bag windows (open your bags first) and what sits in them.
local BAG_ROOTS = {
    { "ContainerFrameCombinedBags", 3 }, { "ContainerFrame1", 3 }, { "ContainerFrame2", 2 }, { "ContainerFrame6", 2 },
    { "BagItemSearchBox", 1 }, { "BagItemAutoSortButton", 1 }, { "BackpackTokenFrame", 2 }, { "ContainerFrame1MoneyFrame", 1 },
    { "BankFrame", 2 }, { "MerchantFrame", 1 },
}
-- /mint uidump cast: the cast bars.
local CAST_ROOTS = {
    { "PlayerCastingBarFrame", 3 }, { "CastingBarFrame", 3 }, { "TargetFrameSpellBar", 3 }, { "FocusFrameSpellBar", 2 },
    { "PetCastingBarFrame", 2 }, { "UIParentBottomManagedFrameContainer", 1 }, { "BuffFrame", 2 }, { "DebuffFrame", 2 },
}
-- /mint uidump chat: the chat windows, their tabs and what holds them.
local CHAT_ROOTS = {
    { "ChatFrame1", 2 }, { "ChatFrame2", 1 }, { "ChatFrame3", 0 }, { "ChatFrame1Tab", 0 }, { "ChatFrame2Tab", 0 },
    { "ChatFrame1EditBox", 0 }, { "ChatFrame1ButtonFrame", 1 }, { "GeneralDockManager", 2 }, { "MintCommunityToolsMover_chat", 0 },
    { "EditModeManagerFrame", 0 }, { "CombatLogQuickButtonFrame_Custom", 0 },
}
-- /mint uidump meter: the game's own damage meter, a long way down (a bar is five frames in).
local METER_ROOTS = {
    { "DamageMeter", 6 }, { "DamageMeterSessionWindow1", 6 }, { "DamageMeterSessionWindow2", 3 }, { "DamageMeterSessionWindow3", 3 },
}
-- /mint uidump loot: the loot window (type it while one is open) and the roll windows.
local LOOT_ROOTS = {
    { "LootFrame", 6 }, { "GroupLootContainer", 2 }, { "GroupLootFrame1", 3 }, { "LootHistoryFrame", 2 }, { "GroupLootHistoryFrame", 2 },
}
-- /mint uidump vendor: the vendor's window (type it while one is open).
local VENDOR_ROOTS = {
    { "MerchantFrame", 4 }, { "MerchantItem1", 3 }, { "MerchantBuyBackItem", 3 }, { "MerchantFrameTab1", 1 }, { "MerchantRepairAllButton", 1 },
    { "MerchantSellAllJunkButton", 1 }, { "MerchantMoneyFrame", 2 }, { "MerchantNextPageButton", 1 },
}
local GROUPS = { menus = MENU_ROOTS, bags = BAG_ROOTS, cast = CAST_ROOTS, chat = CHAT_ROOTS, meter = METER_ROOTS, loot = LOOT_ROOTS,
                 vendor = VENDOR_ROOTS }

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

-- Everything the game has with "DamageMeter" in its name: frames (recorded like the rest, if
-- they were not already), the functions of each mixin (what there is to hook), the meter's
-- own API and its settings. Nothing documents this client's meter; this finds it by name.
local METER_EXTRA_MOST, METER_NAMES_MOST = 12, 80
local function meterInfo(out)
    local info = { globals = {}, mixins = {}, api = {}, cvars = {} }
    local names = {}
    for k in pairs(_G) do
        if type(k) == "string" and k:find("DamageMeter") then names[#names + 1] = k end
    end
    table.sort(names)
    local extra = 0
    for _, k in ipairs(names) do
        local v = _G[k]
        local kind = type(v)
        if kind == "table" and type(v.GetObjectType) == "function" then
            local ok, t = pcall(v.GetObjectType, v)
            kind = ok and type(t) == "string" and t or "frame"
            if not out.frames[k] and extra < METER_EXTRA_MOST then
                local okWalk, tree = pcall(walk, v, nil, 3)
                if okWalk then
                    out.frames[k] = tree
                    extra = extra + 1
                end
            end
        elseif kind == "table" then
            local fns = {}
            for name, fn in pairs(v) do
                if type(name) == "string" and type(fn) == "function" and #fns < METER_NAMES_MOST then fns[#fns + 1] = name end
            end
            table.sort(fns)
            if #fns > 0 then info.mixins[k] = fns end
        end
        info.globals[k] = kind
    end
    if type(C_DamageMeter) == "table" then
        for name, fn in pairs(C_DamageMeter) do
            if type(name) == "string" and type(fn) == "function" then info.api[#info.api + 1] = name end
        end
        table.sort(info.api)
    end
    -- How the game's edit mode keeps the meter's own settings (bar height and the like): the
    -- numbers it calls the meter and each setting by, and what each layout has for them.
    info.editMode = { enums = {}, layouts = {} }
    if type(Enum) == "table" then
        for name, t in pairs(Enum) do
            if type(name) == "string" and name:find("DamageMeter") and type(t) == "table" then
                local copy = {}
                for k, v in pairs(t) do
                    if type(k) == "string" and (type(v) == "number" or type(v) == "string") then copy[k] = v end
                end
                info.editMode.enums[name] = copy
            end
        end
        if type(Enum.EditModeSystem) == "table" then info.editMode.system = Enum.EditModeSystem.DamageMeter or false end
    end
    if type(C_EditMode) == "table" and type(C_EditMode.GetLayouts) == "function" then
        local ok, all = pcall(C_EditMode.GetLayouts)
        if ok and type(all) == "table" then
            info.editMode.activeLayout = type(all.activeLayout) == "number" and all.activeLayout or false
            for i, layout in ipairs(type(all.layouts) == "table" and all.layouts or {}) do
                local entry = { name = type(layout.layoutName) == "string" and layout.layoutName or false,
                                type = type(layout.layoutType) == "number" and layout.layoutType or false, meter = false }
                for _, sys in ipairs(type(layout.systems) == "table" and layout.systems or {}) do
                    if type(sys) == "table" and sys.system == info.editMode.system and info.editMode.system then
                        local settings = {}
                        for _, st in ipairs(type(sys.settings) == "table" and sys.settings or {}) do
                            if type(st) == "table" and type(st.setting) == "number" then settings[#settings + 1] = st.setting .. "=" .. tostring(st.value) end
                        end
                        entry.meter = table.concat(settings, " ")
                    end
                end
                info.editMode.layouts[i] = entry
            end
        end
    end
    if type(GetCVar) == "function" then
        for _, name in ipairs({ "damageMeterEnabled", "damageMeterResetOnNewInstance" }) do
            local ok, v = pcall(GetCVar, name)
            info.cvars[name] = ok and v ~= nil and tostring(v) or false
        end
    end
    return info
end

-- The groups, in the order /mint uidump all takes them.
local ORDER = { "screen", "menus", "bags", "cast", "chat", "meter", "loot", "vendor" }
Dump.GROUPS = ORDER

-- The frame under the mouse: the topmost named frame it is part of (what is recorded), and
-- the way down from there to the part the mouse is over.
local function underMouse()
    local f
    if type(GetMouseFoci) == "function" then
        local ok, list = pcall(GetMouseFoci)
        if ok and type(list) == "table" then f = list[1] end
    elseif type(GetMouseFocus) == "function" then
        local ok, v = pcall(GetMouseFocus)
        if ok then f = v end
    end
    if type(f) ~= "table" or f == WorldFrame or f == UIParent then return nil end
    local chain, top, cur = {}, nil, f
    for _ = 1, 24 do
        if type(cur) ~= "table" or cur == UIParent or cur == WorldFrame then break end
        local name
        if type(cur.GetName) == "function" then
            local ok, n = pcall(cur.GetName, cur)
            if ok and type(n) == "string" and n ~= "" then name = n end
        end
        chain[#chain + 1] = name or "(unnamed)"
        if name then top = cur end
        cur = type(cur.GetParent) == "function" and select(2, pcall(cur.GetParent, cur)) or nil
    end
    return top, table.concat(chain, " < ")
end

local function record(group, label, roots)
    roots = roots or GROUPS[group or ""] or ROOTS
    nodes = 0
    local version, build, _, toc
    if GetBuildInfo then version, build, _, toc = GetBuildInfo() end
    local out = { at = time(), addon = ns.VERSION, version = version, build = build, toc = toc, apis = {}, frames = {}, missing = {},
                  group = (GROUPS[group or ""] or group == "frame") and group or "screen" }
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
    -- The chat window's place, in full: every dump has it.
    if ns.Chat and ns.Chat.Facts then
        local ok, chat = pcall(ns.Chat.Facts)
        out.chat = ok and chat or { error = tostring(chat) }
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
    if group == "meter" then
        local ok, meter = pcall(meterInfo, out)
        out.meter = ok and meter or { error = tostring(meter) }
    end
    out.count = nodes
    out.found = found
    if type(label) == "string" and label ~= "" then out.label = label end
    local db = ns.DB()
    db.uiDump = out
    db.uiDumps = type(db.uiDumps) == "table" and db.uiDumps or {}
    db.uiDumps[out.label and (out.group .. ":" .. out.label) or out.group] = out
    -- what the game menu last showed: its buttons come and go with it, so a dump taken while
    -- it is closed has none
    if ns.Menus and ns.Menus.gameMenu then out.gameMenu = ns.Menus.gameMenu end
    return out
end

-- /mint uidump finder: what the group finder answers, raw, for every instance it lists (the
-- values of GetLFGDungeonInfo in the order this client returns them), and the constants the
-- client names its instance types by. For the dungeons export, whose contract assumed the
-- order the retail client uses.
local FINDER_VALUES_MOST, FINDER_IDS_MOST = 24, 5000
local function finderInfo()
    local out = { at = time(), group = "finder", addon = ns.VERSION, entries = {}, constants = {}, count = 0 }
    if GetBuildInfo then out.version, out.build = GetBuildInfo() end
    out.has = type(GetLFGDungeonInfo)
    if out.has == "function" then
        for id = 1, FINDER_IDS_MOST do
            local values = { pcall(GetLFGDungeonInfo, id) }
            if values[1] and type(values[2]) == "string" and values[2] ~= "" then
                local row = {}
                for i = 2, math.min(#values, FINDER_VALUES_MOST + 1) do
                    local v = values[i]
                    row[i - 1] = (issecretvalue and issecretvalue(v)) and "<secret>" or (v == nil and "nil" or tostring(v))
                end
                out.entries[tostring(id)] = row
                out.count = out.count + 1
            end
        end
    end
    for k, v in pairs(_G) do
        if type(k) == "string" and (k:find("^TYPEID_") or k:find("^LFG_SUBTYPEID_") or k:find("^LFG_TYPE") or k == "NUM_LFG_DUNGEON_TYPES")
            and (type(v) == "number" or type(v) == "string") then
            out.constants[k] = v
        end
    end
    return out
end

function Dump.Run(group, label)
    if group == "finder" then
        local out = finderInfo()
        local db = ns.DB()
        db.uiDumps = type(db.uiDumps) == "table" and db.uiDumps or {}
        db.uiDumps.finder = out
        ns.Say(("recorded what the group finder answers for %d instances. Type /reload to write it to the save file."):format(out.count))
        return out
    end
    -- one frame, by its name or by pointing at it
    if group == "frame" or group == "mouse" then
        local target, path
        if group == "mouse" then
            target, path = underMouse()
            if not target then
                ns.Say("the mouse is not over a frame of the game's with a name. Point at it, press Enter, type /mint uidump mouse, press Enter.")
                return nil
            end
        else
            target = type(label) == "string" and _G[label] or nil
            if type(target) ~= "table" or type(target.GetObjectType) ~= "function" then
                ns.Say(("there is no frame named %s. /mint uidump mouse records what the mouse is over."):format(tostring(label)))
                return nil
            end
        end
        local name = select(2, pcall(target.GetName, target))
        if type(name) ~= "string" then name = tostring(label) end
        local out = record("frame", name, { { name, 6 } })
        out.mouse = path
        ns.Say(("recorded %s (%d frames and textures)%s. Type /reload to write it to the save file."):format(name, out.count,
            path and (", the mouse over " .. path) or ""))
        return out
    end
    if group == "all" then
        local taken, total, missing = {}, 0, {}
        for _, name in ipairs(ORDER) do
            local out = record(name == "screen" and nil or name)
            taken[#taken + 1] = ("%s %d"):format(name, out.found)
            total = total + out.count
            for _, root in ipairs(out.missing) do missing[#missing + 1] = root end
        end
        ns.DB().uiDump = ns.DB().uiDumps.screen
        ns.Say(("recorded every group on build %s (%s; %d frames and textures in all; %d names this client does not have or had not opened). "
            .. "Type /reload to write it to the save file."):format(tostring(ns.DB().uiDump.build), table.concat(taken, ", "), total, #missing))
        return ns.DB().uiDumps
    end
    local out = record(group, label)
    ns.Say(("recorded %d of the game's frames on build %s%s (%d frames and textures in all; %d names this client does not have). "
        .. "Type /reload to write it to the save file."):format(out.found, tostring(out.build), out.label and (' as "' .. out.label .. '"') or "", out.count, #out.missing))
    return out
end
