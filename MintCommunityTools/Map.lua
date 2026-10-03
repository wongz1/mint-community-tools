--[[
    Map.lua - the minimap, squared, with the zone above it and the coordinates and the
    time below it.

    The game's own minimap is kept (tracking, mail, the battleground icon and the zoom all
    stay the game's); what changes is its shape and dress:
      - square, in a 1px border, on a mover; the mouse wheel zooms;
      - the round border, the zoom buttons, the world map button, the calendar and the
        game's own clock are gone;
      - a strip above it with the zone's name in the colour of its PvP standing, and your
        coordinates at its right end. The name has the strip up to the coordinates and is
        cut short with dots when it is longer than that, so the two never overlap; hover
        the strip for the whole name;
      - below it, your computer's time and the game world's (the server's) time, whichever
        the settings turn on: one row, shared when both are on. With the zone strip turned
        off the coordinates go below the map too; two things share a row, and with all
        three the coordinates take a row and the times the row under it.
    Each part can be turned off in the settings.

    Other addons' minimap buttons need to know the map is square to sit on its edge, so once
    the map is set up this file answers the two global functions such buttons ask:
    GetMinimapShape() ("SQUARE" or "ROUND", the long-standing convention) and
    GetMinimapEdgeInsets() (the room the strips take above and below the map, then left and
    right, which is 0). Neither is replaced if another addon already answers it.
]]

local ADDON, ns = ...
local Map = {}
ns.Map = Map

local ipairs, type, pcall = ipairs, type, pcall
local floor = math.floor

local STRIP = 16
local widgets = {}
Map.widgets = widgets

local PVP_COLOR = {
    sanctuary = { 0.41, 0.80, 0.94 }, arena = { 1, 0.3, 0.3 }, friendly = { 0.3, 0.9, 0.3 },
    hostile = { 1, 0.3, 0.3 }, contested = { 1, 0.85, 0.2 }, combat = { 1, 0.3, 0.3 },
}

-- What goes: the round border, the zoom buttons, the map button, the calendar, the clock.
local HIDE = {
    "MinimapBorder", "MinimapBorderTop", "MinimapCompassTexture", "MinimapZoomIn", "MinimapZoomOut", "MiniMapWorldMapButton",
    "MinimapZoneTextButton", "MinimapToggleButton", "GameTimeFrame", "TimeManagerClockButton",
    "MinimapNorthTag", "MiniMapTrackingButtonBorder", "MiniMapTrackingBorder", "MiniMapMailBorder",
}

local function settings()
    return ns.Overhaul.Settings().map
end

local function frame(name)
    local f = _G[name]
    return type(f) == "table" and f or nil
end

function Map.Active()
    return Map.applied and settings().square or false
end

-- How far the strips reach above and below the map, for anything placed around its edge.
-- What is shown under the map, in order: { key, text function }.
local INFO = {
    { "coords", function() return Map.CoordinateText() end },
    { "localTime", function() return Map.LocalTimeText() end },
    { "gameTime", function() return Map.GameTimeText() end },
}

-- Where each item under the map goes, as { key = { row, "LEFT" | "RIGHT" | "CENTER" } }, and
-- how many rows that takes. One item is centred; two share a row, left and right; three put
-- the coordinates on a row of their own and the two times on the row under it.
-- The coordinates sit in the zone strip when there is one; under the map only when not.
function Map.CoordsOnTop()
    local s = settings()
    return s.zone and s.coords and true or false
end

local function below(key)
    local s = settings()
    if not s[key] then return false end
    return not (key == "coords" and s.zone)
end

function Map.InfoLayout()
    local on = {}
    for _, item in ipairs(INFO) do
        if below(item[1]) then on[#on + 1] = item[1] end
    end
    local places = {}
    if #on == 1 then
        places[on[1]] = { 1, "CENTER" }
    elseif #on == 2 then
        places[on[1]], places[on[2]] = { 1, "LEFT" }, { 1, "RIGHT" }
    elseif #on == 3 then
        places[on[1]], places[on[2]], places[on[3]] = { 1, "CENTER" }, { 2, "LEFT" }, { 2, "RIGHT" }
    end
    return places, (#on == 0 and 0) or (#on == 3 and 2) or 1
end

function Map.Insets()
    local s = settings()
    local _, rows = Map.InfoLayout()
    return s.zone and STRIP + 1 or 0, rows > 0 and rows * STRIP + 1 or 0
end

---------------------------------------------------------------------------
-- Text
---------------------------------------------------------------------------

-- Your position on the current map, as percentages, or nil (no map, or an instance).
function Map.Coordinates()
    if not (C_Map and C_Map.GetBestMapForUnit and C_Map.GetPlayerMapPosition) then return nil end
    local ok, mapID = pcall(C_Map.GetBestMapForUnit, "player")
    if not ok or type(mapID) ~= "number" then return nil end
    local ok2, pos = pcall(C_Map.GetPlayerMapPosition, mapID, "player")
    if not ok2 or type(pos) ~= "table" then return nil end
    local x, y = pos.x, pos.y
    if type(x) ~= "number" and pos.GetXY then
        local ok3, px, py = pcall(pos.GetXY, pos)
        if ok3 then x, y = px, py end
    end
    if type(x) ~= "number" or type(y) ~= "number" then return nil end
    if issecretvalue and (issecretvalue(x) or issecretvalue(y)) then return nil end   -- not to be done arithmetic on
    if x == 0 and y == 0 then return nil end
    return x * 100, y * 100
end

function Map.CoordinateText()
    local x, y = Map.Coordinates()
    if not x then return "|cff" .. ns.W.DIM_HEX .. "no map|r" end
    return ("%.1f, %.1f"):format(x, y)
end

-- "20:26 local": your computer's clock.
function Map.LocalTimeText()
    local now = date and date("%H:%M")
    if type(now) ~= "string" then return "" end
    return now .. " |cff" .. ns.W.DIM_HEX .. "local|r"
end

-- "20:30 game": the game world's (the server's) clock.
function Map.GameTimeText()
    if not GetGameTime then return "" end
    local ok, h, m = pcall(GetGameTime)
    if not (ok and type(h) == "number" and type(m) == "number") then return "" end
    return ("%02d:%02d |cff%sgame|r"):format(h, m, ns.W.DIM_HEX)
end

function Map.ZoneText()
    local zone = GetMinimapZoneText and GetMinimapZoneText()
    if type(zone) ~= "string" then zone = "" end
    local kind
    if GetZonePVPInfo then
        kind = GetZonePVPInfo()
    elseif C_PvP and C_PvP.GetZonePVPInfo then
        local ok, k = pcall(C_PvP.GetZonePVPInfo)
        if ok then kind = k end
    end
    if type(kind) ~= "string" then kind = "" end
    local c = PVP_COLOR[kind] or ns.W.COLOR.text
    return zone, c
end

local function refreshZone()
    if not widgets.zone then return end
    local zone, c = Map.ZoneText()
    widgets.zone:SetText(zone)
    widgets.zone:SetTextColor(c[1], c[2], c[3], 1)
end

local function refreshInfo()
    if widgets.coordsTop then widgets.coordsTop:SetText(Map.CoordsOnTop() and Map.CoordinateText() or "") end
    if not widgets.info then return end
    for _, item in ipairs(INFO) do
        local fs = widgets[item[1]]
        if fs then fs:SetText(below(item[1]) and item[2]() or "") end
    end
end

---------------------------------------------------------------------------
-- Building
---------------------------------------------------------------------------

local function layoutStrips(mover)
    local W = ns.W
    local s = settings()
    local size = s.size
    local zoneH = s.zone and STRIP or 0
    local places, rows = Map.InfoLayout()
    local infoH = rows * STRIP
    mover:SetSize(size, size + (zoneH > 0 and zoneH + 1 or 0) + (infoH > 0 and infoH + 1 or 0))

    if s.zone then
        if not widgets.zoneStrip then
            widgets.zoneStrip = W.panel(UIParent)
            widgets.zoneStrip:SetFrameStrata("BACKGROUND")
            widgets.zone = W.text(widgets.zoneStrip, "")
            if widgets.zone.SetWordWrap then widgets.zone:SetWordWrap(false) end
            widgets.coordsTop = W.text(widgets.zoneStrip, "")
            widgets.coordsTop:SetPoint("RIGHT", widgets.zoneStrip, "RIGHT", -4, 0)
            widgets.coordsTop:SetJustifyH("RIGHT")
            -- A name too long for the strip is cut short: the whole of it on hover.
            widgets.zoneStrip:EnableMouse(true)
            widgets.zoneStrip:SetScript("OnEnter", function(self)
                if not GameTooltip then return end
                local zone, c = Map.ZoneText()
                GameTooltip:SetOwner(self, "ANCHOR_BOTTOMLEFT")
                GameTooltip:SetText(zone, c[1], c[2], c[3])
                if Map.CoordsOnTop() then GameTooltip:AddLine(Map.CoordinateText(), 1, 1, 1) end
                GameTooltip:Show()
            end)
            widgets.zoneStrip:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
        end
        widgets.zoneStrip:ClearAllPoints()
        widgets.zoneStrip:SetPoint("TOPLEFT", mover, "TOPLEFT", 0, 0)
        widgets.zoneStrip:SetPoint("TOPRIGHT", mover, "TOPRIGHT", 0, 0)
        widgets.zoneStrip:SetHeight(STRIP)
        -- The name's width is whatever its two ends leave it: up to the coordinates when they
        -- are in the strip (left-aligned, so a short name does not float), the whole strip
        -- when they are not (centred, as before).
        widgets.zone:ClearAllPoints()
        widgets.zone:SetPoint("LEFT", widgets.zoneStrip, "LEFT", 4, 0)
        if s.coords then
            widgets.zone:SetPoint("RIGHT", widgets.coordsTop, "LEFT", -6, 0)
            widgets.zone:SetJustifyH("LEFT")
            widgets.coordsTop:Show()
        else
            widgets.zone:SetPoint("RIGHT", widgets.zoneStrip, "RIGHT", -4, 0)
            widgets.zone:SetJustifyH("CENTER")
            widgets.coordsTop:Hide()
        end
        widgets.zoneStrip:Show()
    elseif widgets.zoneStrip then
        widgets.zoneStrip:Hide()
    end

    if infoH > 0 then
        if not widgets.info then
            widgets.info = W.panel(UIParent)
            widgets.info:SetFrameStrata("BACKGROUND")
            for _, item in ipairs(INFO) do widgets[item[1]] = W.text(widgets.info, "") end
        end
        widgets.info:ClearAllPoints()
        widgets.info:SetPoint("BOTTOMLEFT", mover, "BOTTOMLEFT", 0, 0)
        widgets.info:SetPoint("BOTTOMRIGHT", mover, "BOTTOMRIGHT", 0, 0)
        widgets.info:SetHeight(infoH)
        -- Each item on its row and side; what is switched off is hidden.
        for _, item in ipairs(INFO) do
            local fs, place = widgets[item[1]], places[item[1]]
            fs:ClearAllPoints()
            if place then
                local y = -((place[1] - 1) * STRIP + STRIP / 2)
                if place[2] == "LEFT" then fs:SetPoint("LEFT", widgets.info, "TOPLEFT", 4, y)
                elseif place[2] == "RIGHT" then fs:SetPoint("RIGHT", widgets.info, "TOPRIGHT", -4, y)
                else fs:SetPoint("CENTER", widgets.info, "TOP", 0, y) end
                fs:SetJustifyH(place[2])
                fs:Show()
            else
                fs:Hide()
            end
        end
        widgets.info:Show()
    elseif widgets.info then
        widgets.info:Hide()
    end
    return zoneH
end

local function placeMinimap(mover, zoneH)
    local W = ns.W
    local s = settings()
    local mm = Minimap
    pcall(mm.ClearAllPoints, mm)
    pcall(mm.SetPoint, mm, "TOPLEFT", mover, "TOPLEFT", 0, zoneH > 0 and -(zoneH + 1) or 0)
    pcall(mm.SetSize, mm, s.size, s.size)
    if mm.SetMaskTexture then
        pcall(mm.SetMaskTexture, mm, s.square and W.WHITE or "Textures\\MinimapMask")
    end
    if not widgets.border then
        widgets.border = W.panel(UIParent, { 0, 0, 0, 0 })
        widgets.border:SetFrameStrata("BACKGROUND")
    end
    widgets.border:ClearAllPoints()
    widgets.border:SetPoint("TOPLEFT", mm, "TOPLEFT", -1, 1)
    widgets.border:SetPoint("BOTTOMRIGHT", mm, "BOTTOMRIGHT", 1, -1)
    if s.square then widgets.border:Show() else widgets.border:Hide() end
end

local function dressMinimap()
    local mm = Minimap
    local cluster = frame("MinimapCluster")
    if cluster then
        cluster.ignoreFramePositionManager = true
        pcall(cluster.EnableMouse, cluster, false)
    end
    pcall(mm.SetParent, mm, UIParent)
    for _, name in ipairs(HIDE) do ns.Overhaul.Blank(frame(name)) end
    for _, name in ipairs({ "MinimapZoomIn", "MinimapZoomOut", "MiniMapWorldMapButton", "MinimapZoneTextButton", "MinimapToggleButton", "GameTimeFrame", "TimeManagerClockButton" }) do
        ns.Overhaul.HideBlizzard(frame(name))
    end
    -- The round border is not called the same thing on every client, so every texture drawn
    -- on the minimap's backdrop and its cluster goes (the icons there are child frames, and
    -- stay), and so do the parts a newer client keeps in fields rather than under names.
    local sweep = ns.Overhaul.BlankRegions
    Map.swept = 0
    local holders = {}   -- built one by one: a holder this client lacks must not end the list
    holders[#holders + 1] = frame("MinimapBackdrop")
    holders[#holders + 1] = cluster
    if cluster and type(cluster.MinimapContainer) == "table" then holders[#holders + 1] = cluster.MinimapContainer end
    for _, holder in ipairs(holders) do
        if sweep then Map.swept = Map.swept + sweep(holder) end
    end
    if cluster then
        for _, field in ipairs({ "BorderTop", "ZoneTextButton" }) do
            if type(cluster[field]) == "table" then
                if sweep then sweep(cluster[field]) end
                ns.Overhaul.HideBlizzard(cluster[field])
            end
        end
    end
    for _, field in ipairs({ "ZoomIn", "ZoomOut" }) do
        if type(mm[field]) == "table" then ns.Overhaul.HideBlizzard(mm[field]) end
    end
    -- A newer client hangs these off the cluster rather than the map: the day and night dial
    -- and its own coordinates go (the strips show the time and the coordinates); tracking,
    -- mail and the instance difficulty move onto the map's corners.
    if cluster then
        for _, field in ipairs({ "DielFrame", "GamepadHudBackground" }) do
            if type(cluster[field]) == "table" then ns.Overhaul.HideBlizzard(cluster[field]) end
        end
        local container = cluster.MinimapContainer
        if type(container) == "table" and type(container.PlayerCoords) == "table" then ns.Overhaul.HideBlizzard(container.PlayerCoords) end
        local corners = {
            { "Tracking", "TOPLEFT", 2, -2 }, { "IndicatorFrame", "TOPRIGHT", -2, -2 }, { "InstanceDifficulty", "TOPRIGHT", -2, -20 },
        }
        for _, c in ipairs(corners) do
            local part = cluster[c[1]]
            if type(part) == "table" then
                if type(part.Background) == "table" then ns.Overhaul.Blank(part.Background) end
                pcall(part.SetParent, part, mm)
                pcall(part.ClearAllPoints, part)
                pcall(part.SetPoint, part, c[2], mm, c[2], c[3], c[4])
            end
        end
    end
    -- Rings the game draws for quest and dig areas assume a round map.
    for _, method in ipairs({ "SetArchBlobRingScalar", "SetQuestBlobRingScalar" }) do
        if type(mm[method]) == "function" then pcall(mm[method], mm, 0) end
    end
    -- The icons that stay: tracking top left, mail top right, the battleground icon bottom left.
    local tracking = frame("MiniMapTracking") or frame("MiniMapTrackingFrame")
    if tracking then
        pcall(tracking.ClearAllPoints, tracking)
        pcall(tracking.SetPoint, tracking, "TOPLEFT", mm, "TOPLEFT", 2, -2)
    end
    local mail = frame("MiniMapMailFrame")
    if mail then
        pcall(mail.ClearAllPoints, mail)
        pcall(mail.SetPoint, mail, "TOPRIGHT", mm, "TOPRIGHT", -2, -2)
    end
    local bg = frame("MiniMapBattlefieldFrame")
    if bg then
        pcall(bg.ClearAllPoints, bg)
        pcall(bg.SetPoint, bg, "BOTTOMLEFT", mm, "BOTTOMLEFT", 2, 2)
    end
    -- The mouse wheel zooms, now that the buttons are gone.
    pcall(mm.EnableMouseWheel, mm, true)
    mm:SetScript("OnMouseWheel", function(_, delta)
        if type(delta) ~= "number" then return end
        if delta > 0 then
            if Minimap_ZoomIn then Minimap_ZoomIn() end
        else
            if Minimap_ZoomOut then Minimap_ZoomOut() end
        end
    end)
end

-- What other addons' minimap buttons ask; see the top of this file.
local function publish()
    if type(_G.GetMinimapShape) ~= "function" then
        _G.GetMinimapShape = function() return Map.Active() and "SQUARE" or "ROUND" end
    end
    if type(_G.GetMinimapEdgeInsets) ~= "function" then
        _G.GetMinimapEdgeInsets = function()
            if not Map.applied then return 0, 0, 0, 0 end
            local above, below = Map.Insets()
            return above, below, 0, 0
        end
    end
end

function Map.Apply()
    if type(Minimap) ~= "table" then error("there is no minimap on this client") end
    local s = settings()
    local mover = ns.Overhaul.Mover("minimap", "Minimap", s.size, s.size, { "TOPRIGHT", -20, -20 })
    local zoneH = layoutStrips(mover)
    placeMinimap(mover, zoneH)
    dressMinimap()
    Map.applied = true
    publish()

    if not widgets.events then
        widgets.events = CreateFrame("Frame")
        for _, ev in ipairs({ "ZONE_CHANGED", "ZONE_CHANGED_INDOORS", "ZONE_CHANGED_NEW_AREA", "PLAYER_ENTERING_WORLD" }) do
            pcall(widgets.events.RegisterEvent, widgets.events, ev)
        end
        widgets.events:SetScript("OnEvent", refreshZone)
        -- The coordinates and the clocks, twice a second, whichever strip they are in.
        local elapsed = 0
        widgets.events:SetScript("OnUpdate", function(_, dt)
            elapsed = elapsed + (type(dt) == "number" and dt or 0)
            if elapsed < 0.5 then return end
            elapsed = 0
            refreshInfo()
        end)
    end
    refreshZone()
    refreshInfo()
    -- The addon's minimap button sits on the map's edge; a square edge is a different place.
    if ns.InitMinimap then pcall(ns.InitMinimap) end
end

function Map.OnSettingsChanged(path)
    if not Map.applied then return end
    local s = settings()
    local mover = ns.Overhaul.Mover("minimap", "Minimap", s.size, s.size)
    local zoneH = layoutStrips(mover)
    placeMinimap(mover, zoneH)
    refreshZone()
    refreshInfo()
    if ns.InitMinimap then pcall(ns.InitMinimap) end
end

-- The game dresses its minimap again when the world loads; so does this, after.
function Map.OnEnteringWorld()
    if not Map.applied then return end
    pcall(dressMinimap)
    Map.Refresh()
end

function Map.Refresh()
    refreshZone()
    refreshInfo()
end
