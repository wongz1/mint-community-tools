--[[
    UnitFrames.lua - player, target and target-of-target frames of the addon's own.

    Player, target, target-of-target and pet. Flat frames in the skin: a health bar (class colour for players, reaction colour for
    everything else, with the name and the numbers on it), a thinner power bar under it
    (the level and the power on it), and a portrait on the left that can be turned off, or
    be the unit's animated 3D model rather than the flat picture. Names are whole: WoW Forever
    characters have a first and a last name, and both are shown.
    Click to target, right-click for the unit's menu, as on the game's own frames: they are
    secure unit buttons, so that works in combat too.

    Buffs and debuffs are rows of icons on whichever side of the frame the settings say
    (above, below, left, right, or off), debuffs nearest the frame; hover one for its
    tooltip; a debuff's border is its type's colour. The target's debuffs can be limited to
    your own. Buff icons and debuff icons each have their own size, and the countdown
    numbers on each can be turned off.

    The settings also choose the frames' sizes (one width and height for the player and
    target frames, one for the two small frames), and the font and font size of the text on
    them: the game's own fonts, plus any that LibSharedMedia knows of when another addon
    has brought it along. A size cannot be changed in combat (the game does not let a
    frame it can click through to a unit be resized then); it is applied when combat ends.

    The game's own player, target, target-of-target and pet frames are hidden. The combo
    points, class resources and the target's cast bar are the game's still, re-anchored.
    Every API is feature-detected and run under pcall: the WoW Forever client is a beta.

    SECRET VALUES. This client hands addons some unit numbers (health, power, aura stacks
    and durations) as secret values: they may be stored, passed to a status bar, a font
    string or a cooldown, and run through string.format, but not compared, added, indexed
    or used as a table key. So nothing here does arithmetic or a comparison on what a unit
    API returned without asking isSecret() first; a secret number goes straight to the
    widget, and to the text through string.format (no thousands separators: that would need
    the digits). A secret boolean cannot be tested at all and counts as "don't know".
]]

local ADDON, ns = ...
local Units = {}
ns.Units = Units

local ipairs, pairs, type, tostring, pcall = ipairs, pairs, type, tostring, pcall
local floor, ceil, max = math.floor, math.ceil, math.max
local sformat = string.format

local UNITS = {
    { key = "player", unit = "player", label = "Player frame", auras = true, default = { "BOTTOM", -200, 220 } },
    { key = "target", unit = "target", label = "Target frame", auras = true, watch = true, default = { "BOTTOM", 200, 220 } },
    { key = "tot", unit = "targettarget", label = "Target of target", watch = true, default = { "BOTTOM", 400, 231 } },
    { key = "pet", unit = "pet", label = "Pet frame", watch = true, default = { "BOTTOM", -250, 274 } },
}
Units.UNITS = UNITS

-- Events that are about one unit (the first argument says which).
local UNIT_EVENTS = {
    "UNIT_HEALTH", "UNIT_MAXHEALTH", "UNIT_HEALTH_FREQUENT", "UNIT_POWER_UPDATE", "UNIT_POWER_FREQUENT", "UNIT_MAXPOWER",
    "UNIT_DISPLAYPOWER", "UNIT_MANA", "UNIT_RAGE", "UNIT_ENERGY", "UNIT_FOCUS", "UNIT_MAXMANA", "UNIT_MAXRAGE",
    "UNIT_MAXENERGY", "UNIT_MAXFOCUS", "UNIT_NAME_UPDATE", "UNIT_LEVEL", "UNIT_FACTION", "UNIT_CONNECTION",
    "UNIT_PORTRAIT_UPDATE", "UNIT_MODEL_CHANGED", "UNIT_AURA", "UNIT_TARGET", "UNIT_PET",
}
local POWER_FALLBACK = { MANA = { 0.2, 0.4, 1 }, RAGE = { 0.9, 0.2, 0.2 }, FOCUS = { 1, 0.5, 0.25 }, ENERGY = { 1, 0.85, 0.1 } }
-- A debuff's border by its type, for clients without the game's own DebuffTypeColor table.
local DISPEL_COLORS = {
    Magic = { r = 0.2, g = 0.6, b = 1 }, Curse = { r = 0.6, g = 0, b = 1 },
    Disease = { r = 0.6, g = 0.4, b = 0 }, Poison = { r = 0, g = 0.6, b = 0 },
}
local SIDES = { off = true, above = true, below = true, left = true, right = true }
Units.SIDES = { "off", "above", "below", "left", "right" }

-- The fonts every client has. "default" is whatever the game uses for this language.
local FONTS = {
    { key = "default", label = "Game default" },
    { key = "friz", label = "Friz Quadrata", path = "Fonts\\FRIZQT__.TTF" },
    { key = "arial", label = "Arial Narrow", path = "Fonts\\ARIALN.TTF" },
    { key = "morpheus", label = "Morpheus", path = "Fonts\\MORPHEUS.TTF" },
    { key = "skurri", label = "Skurri", path = "Fonts\\SKURRI.TTF" },
}
-- What a setting may be: { least, most, step }. The Settings tab's steppers use these too.
Units.LIMITS = {
    fontSize = { 8, 20, 1 }, width = { 120, 400, 10 }, height = { 30, 90, 2 },
    smallWidth = { 80, 260, 10 }, smallHeight = { 16, 50, 2 },
    buffSize = { 12, 48, 2 }, debuffSize = { 12, 48, 2 }, perRow = { 4, 16, 1 },
}

local frames = {}
Units.frames = frames

local function settings()
    return ns.Overhaul.Settings().units
end

-- A numeric setting, kept inside what it may be.
local function limited(key)
    local limit = Units.LIMITS[key]
    local v = tonumber(settings()[key])
    if not v then v = ns.Overhaul.DEFAULTS.units[key] end
    if v < limit[1] then v = limit[1] elseif v > limit[2] then v = limit[2] end
    return v
end

-- The fonts to choose from: the game's own, then LibSharedMedia's (in name order) when some
-- other addon has loaded that library.
function Units.Fonts()
    local list, seen = {}, {}
    for i, font in ipairs(FONTS) do
        list[i] = font
        if font.path then seen[font.path:lower()] = true end
    end
    if LibStub then
        local ok, media = pcall(function() return LibStub("LibSharedMedia-3.0", true) end)
        if ok and type(media) == "table" and type(media.HashTable) == "function" then
            local ok2, fonts = pcall(media.HashTable, media, "font")
            if ok2 and type(fonts) == "table" then
                local extra = {}
                for name, path in pairs(fonts) do
                    if type(name) == "string" and type(path) == "string" and not seen[path:lower()] then
                        seen[path:lower()] = true
                        extra[#extra + 1] = { key = "media:" .. name, label = name, path = path }
                    end
                end
                table.sort(extra, function(a, b) return a.label < b.label end)
                for _, font in ipairs(extra) do list[#list + 1] = font end
            end
        end
    end
    return list
end

-- The font a setting names; the game's default for one that is not there (any more).
function Units.Font(key)
    for _, font in ipairs(Units.Fonts()) do
        if font.key == key then return font end
    end
    return FONTS[1]
end

-- The next font after `key`, for the Settings tab's button.
function Units.NextFont(key)
    local list = Units.Fonts()
    for i, font in ipairs(list) do
        if font.key == key then return list[i % #list + 1].key end
    end
    return list[1].key
end

-- A frame's width and height: the player and target frames share one size, the two small
-- frames another.
local function dims(def)
    if def.auras then return limited("width"), limited("height") end
    return limited("smallWidth"), limited("smallHeight")
end

local function frame(name)
    local f = _G[name]
    return type(f) == "table" and f or nil
end

local function call(fn, ...)
    if type(fn) ~= "function" then return nil end
    local ok, a, b, c, d, e, f, g = pcall(fn, ...)
    if ok then return a, b, c, d, e, f, g end
    return nil
end

local function isSecret(v)
    return issecretvalue ~= nil and issecretvalue(v) == true
end

-- A plain true or false out of what a unit API returned. A secret boolean cannot be tested,
-- so it counts as "don't know": false.
local function flag(v)
    if isSecret(v) then return false end
    return v and true or false
end

local function exists(unit)
    return flag(call(UnitExists, unit))
end

-- A number as text: "1,234" when the addon may read it; for a secret one, the game's own
-- short form when it has one, else the bare digits.
local function numberText(n)
    if not isSecret(n) then return ns.W.commas(n) end
    if AbbreviateNumbers then
        local ok, text = pcall(AbbreviateNumbers, n)
        if ok and type(text) == "string" then return text end
    end
    local ok, text = pcall(sformat, "%d", n)
    return ok and text or ""
end

---------------------------------------------------------------------------
-- Colours and text
---------------------------------------------------------------------------

local function healthColor(unit)
    local s = settings()
    if s.classColor and flag(call(UnitIsPlayer, unit)) then
        local _, class = call(UnitClass, unit)
        local c = type(class) == "string" and not isSecret(class) and RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
        if type(c) == "table" and type(c.r) == "number" then return c.r, c.g, c.b end
    end
    if flag(call(UnitIsTapDenied, unit)) then return 0.5, 0.5, 0.5 end
    local reaction = call(UnitReaction, unit, "player")
    if type(reaction) == "number" and not isSecret(reaction) then
        local c = FACTION_BAR_COLORS and FACTION_BAR_COLORS[reaction]
        if type(c) == "table" and type(c.r) == "number" then return c.r, c.g, c.b end
        if reaction <= 3 then return 0.85, 0.25, 0.25 end
        if reaction == 4 then return 0.9, 0.8, 0.2 end
        return 0.25, 0.8, 0.3
    end
    return 0.25, 0.8, 0.3
end

local function powerColor(unit)
    local _, token = call(UnitPowerType, unit)
    if type(token) ~= "string" or isSecret(token) then token = "MANA" end
    local c = PowerBarColor and PowerBarColor[token]
    if type(c) == "table" and type(c.r) == "number" then return c.r, c.g, c.b end
    local f = POWER_FALLBACK[token] or POWER_FALLBACK.MANA
    return f[1], f[2], f[3]
end

local function levelText(unit)
    local level = call(UnitLevel, unit)
    if isSecret(level) then
        local ok, text = pcall(sformat, "%d", level)
        return ok and text or ""
    end
    local text = (type(level) == "number" and level > 0) and tostring(level) or "??"
    local class = call(UnitClassification, unit)
    if isSecret(class) then class = nil end
    if class == "elite" then text = text .. "+"
    elseif class == "rareelite" then text = text .. "R+"
    elseif class == "rare" then text = text .. "R"
    elseif class == "worldboss" then text = "Boss" end
    local c
    if type(level) == "number" and level > 0 then
        c = call(GetQuestDifficultyColor, level) or call(GetDifficultyColor, level)
    end
    if type(c) == "table" and type(c.r) == "number" then
        return ("|cff%02x%02x%02x%s|r"):format(floor(c.r * 255 + 0.5), floor(c.g * 255 + 0.5), floor(c.b * 255 + 0.5), text)
    end
    return text
end

---------------------------------------------------------------------------
-- Updating a frame
---------------------------------------------------------------------------

-- "62%": worked out when the numbers may be read, asked of the game when they are secret.
local function percentText(unit, cur, maxv, secret)
    if not secret then return sformat("%d%%", floor(cur / maxv * 100 + 0.5)) end
    local curve = CurveConstants and CurveConstants.ScaleTo100
    if UnitHealthPercent and curve then
        local ok, pct = pcall(UnitHealthPercent, unit, true, curve)
        if ok then
            local ok2, text = pcall(sformat, "%d%%", pct)
            if ok2 then return text end
        end
    end
    return ""
end

local function updateHealth(f)
    local unit = f.unit
    local cur, maxv = call(UnitHealth, unit), call(UnitHealthMax, unit)
    local secret = isSecret(cur) or isSecret(maxv)
    if not secret then
        if type(cur) ~= "number" then cur = 0 end
        if type(maxv) ~= "number" or maxv <= 0 then maxv = 1 end
    end
    -- The bar takes the numbers as they are, secret or not.
    pcall(f.health.SetMinMaxValues, f.health, 0, maxv)
    pcall(f.health.SetValue, f.health, cur)
    f.health:SetStatusBarColor(healthColor(unit))
    local connected = call(UnitIsConnected, unit)
    local text
    if not isSecret(connected) and connected == false then text = "Offline"
    elseif flag(call(UnitIsGhost, unit)) then text = "Ghost"
    elseif flag(call(UnitIsDead, unit)) then text = "Dead"
    elseif not f.def.auras then text = percentText(unit, cur, maxv, secret)   -- the small frames: a percentage
    else
        local ok, joined = pcall(sformat, "%s / %s", numberText(cur), numberText(maxv))
        text = ok and joined or ""
    end
    pcall(f.healthText.SetText, f.healthText, text)
end

local function updatePower(f)
    local unit = f.unit
    local cur, maxv = call(UnitPower, unit), call(UnitPowerMax, unit)
    local secret = isSecret(cur) or isSecret(maxv)
    if not secret then
        if type(cur) ~= "number" then cur = 0 end
        if type(maxv) ~= "number" or maxv <= 0 then maxv = 1 end
    end
    pcall(f.power.SetMinMaxValues, f.power, 0, maxv)
    pcall(f.power.SetValue, f.power, cur)
    f.power:SetStatusBarColor(powerColor(unit))
    if f.powerText then
        local text = ""
        if secret then text = numberText(cur) elseif maxv > 1 then text = ns.W.commas(cur) end
        pcall(f.powerText.SetText, f.powerText, text)
    end
    if f.level then pcall(f.level.SetText, f.level, levelText(unit)) end
end

-- A unit's whole name. On WoW Forever UnitName gives the first name and, as its second
-- value, the last name; other clients put a realm there (or nothing), which is left off.
-- A name the addon may show but not read (a secret value) is joined without being looked at.
local function unitName(unit)
    local name, second = call(UnitName, unit)
    if type(name) ~= "string" then return "" end
    if type(second) ~= "string" then return name end
    if isSecret(name) or isSecret(second) then
        local ok, both = pcall(sformat, "%s %s", name, second)
        return ok and both or name
    end
    if second == "" or (ns.Collect and ns.Collect.IsRealm and ns.Collect.IsRealm(second)) then return name end
    return name .. " " .. second
end
Units.Name = unitName

local function updateName(f)
    pcall(f.name.SetText, f.name, unitName(f.unit))
end

-- The unit's own 3D model in the portrait square, animated as the game animates it. False
-- when there is no model to show: no model frame on this client, or a unit too far away to
-- be drawn. The flat picture stands in then.
local function showModel(f)
    local m = f.model
    if not m or type(m.SetUnit) ~= "function" then return false end
    local visible = call(UnitIsVisible, f.unit)
    if not isSecret(visible) and visible == false then return false end
    local connected = call(UnitIsConnected, f.unit)
    if not isSecret(connected) and connected == false then return false end
    pcall(m.ClearModel, m)
    if not pcall(m.SetUnit, m, f.unit) then return false end
    -- A head-and-shoulders view, as a portrait is.
    pcall(m.SetPortraitZoom, m, 1)
    pcall(m.SetCamDistanceScale, m, 1)
    pcall(m.SetPosition, m, 0, 0, 0)
    m:Show()
    return true
end

local function updatePortrait(f)
    if not f.portrait then return end
    local s = settings()
    if not s.portrait then
        f.portrait:Hide()
        if f.model then f.model:Hide() end
        return
    end
    if s.portrait3d and showModel(f) then
        f.portrait:Hide()
        return
    end
    if f.model then f.model:Hide() end
    call(SetPortraitTexture, f.portrait, f.unit)
    f.portrait:Show()
end

---------------------------------------------------------------------------
-- Auras
---------------------------------------------------------------------------

-- The aura at `index`, as { name, icon, count, dispel, duration, expires, id }, or nil when
-- there is none. Any field may be a secret value.
local function auraAt(unit, index, filter)
    if C_UnitAuras and C_UnitAuras.GetAuraDataByIndex then
        local ok, a = pcall(function()
            local d = C_UnitAuras.GetAuraDataByIndex(unit, index, filter)
            if type(d) ~= "table" then return nil end
            return { name = d.name, icon = d.icon, count = d.applications, dispel = d.dispelName,
                     duration = d.duration, expires = d.expirationTime, id = d.auraInstanceID }
        end)
        return ok and a or nil
    end
    local fn = UnitAura or (filter:find("HARMFUL", 1, true) and UnitDebuff or UnitBuff)
    if type(fn) ~= "function" then return nil end
    local ok, name, icon, count, dispel, duration, expires = pcall(fn, unit, index, filter)
    if not ok or type(name) ~= "string" then return nil end
    return { name = name, icon = icon, count = count, dispel = dispel, duration = duration, expires = expires }
end

local function auraEnter(b)
    if not GameTooltip then return end
    GameTooltip:SetOwner(b, "ANCHOR_BOTTOMLEFT")
    local ok = false
    if b.auraId then
        local setter = b.harmful and GameTooltip.SetUnitDebuffByAuraInstanceID or GameTooltip.SetUnitBuffByAuraInstanceID
        if type(setter) == "function" then ok = pcall(setter, GameTooltip, b.unit, b.auraId, b.filter) end
    end
    if not ok and type(GameTooltip.SetUnitAura) == "function" then
        ok = pcall(GameTooltip.SetUnitAura, GameTooltip, b.unit, b.index, b.filter)
    end
    if not ok then pcall(GameTooltip.SetText, GameTooltip, b.auraName or "", 1, 1, 1) end
    GameTooltip:Show()
end

local function auraLeave()
    if GameTooltip then GameTooltip:Hide() end
end

local function makeAuraButton(set, n)
    local W = ns.W
    local b = W.safeCreate("Frame", nil, set.frame, W.template())
    W.skin(b, W.COLOR.panel)
    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetPoint("TOPLEFT", 1, -1)
    b.icon:SetPoint("BOTTOMRIGHT", -1, 1)
    if b.icon.SetTexCoord then b.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92) end
    b.cd = W.safeCreate("Cooldown", nil, b, "CooldownFrameTemplate")
    b.cd:SetPoint("TOPLEFT", 1, -1)
    b.cd:SetPoint("BOTTOMRIGHT", -1, 1)
    if b.cd.SetDrawEdge then pcall(b.cd.SetDrawEdge, b.cd, false) end
    b.count = W.fontString(b, "GameFontHighlightSmall", nil)
    b.count:SetPoint("BOTTOMRIGHT", -1, 1)
    b.count:SetJustifyH("RIGHT")
    b.auraId, b.harmful = false, false
    b:EnableMouse(true)
    b:SetScript("OnEnter", auraEnter)
    b:SetScript("OnLeave", auraLeave)
    set.buttons[n] = b
    return b
end

local function updateAuraSet(f, kind)
    local s = settings()
    local cfg = s[f.def.key]
    local set = f.auras[kind]
    local side = cfg and cfg[kind] or "off"
    if not SIDES[side] or side == "off" or not exists(f.unit) then
        set.frame:Hide()
        set.shown = false
        return
    end
    local filter = kind == "buffs" and "HELPFUL" or "HARMFUL"
    if kind == "debuffs" and cfg.onlyMine then filter = filter .. "|PLAYER" end
    local size = limited(kind == "buffs" and "buffSize" or "debuffSize")
    local perRow, step = limited("perRow"), size + 2
    local timers = kind == "buffs" and s.buffTimers or s.debuffTimers
    local corner = side == "above" and "BOTTOMLEFT" or "TOPLEFT"
    local dir = side == "above" and 1 or -1
    local n = 0
    for i = 1, 40 do
        local a = auraAt(f.unit, i, filter)
        if not a then break end
        n = n + 1
        local b = set.buttons[n] or makeAuraButton(set, n)
        b.unit, b.index, b.filter, b.auraName = f.unit, i, filter, a.name
        b.auraId, b.harmful = a.id or false, kind == "debuffs"
        b:SetSize(size, size)
        pcall(b.icon.SetTexture, b.icon, a.icon)

        -- Stacks: shown from 2 up. A secret count cannot be compared, so the game is asked
        -- for the text to show when it can give one.
        local stacks = ""
        if isSecret(a.count) then
            if a.id and C_UnitAuras and C_UnitAuras.GetAuraApplicationDisplayCount then
                local ok, text = pcall(C_UnitAuras.GetAuraApplicationDisplayCount, f.unit, a.id, 2, 99)
                if ok and type(text) == "string" then stacks = text end
            end
        elseif type(a.count) == "number" and a.count > 1 then
            stacks = tostring(a.count)
        end
        pcall(b.count.SetText, b.count, stacks)

        -- The countdown numbers on the sweep are the game's own (they work from numbers the
        -- addon may not read); the settings can leave them off.
        if type(b.cd.SetHideCountdownNumbers) == "function" then pcall(b.cd.SetHideCountdownNumbers, b.cd, not timers) end

        -- The sweep: from the start time when it can be worked out, from the end time when
        -- the numbers are secret (the cooldown does the subtraction itself).
        local sweeping = false
        if isSecret(a.duration) or isSecret(a.expires) then
            if type(b.cd.SetCooldownFromExpirationTime) == "function" then
                sweeping = pcall(b.cd.SetCooldownFromExpirationTime, b.cd, a.expires, a.duration)
            end
        elseif type(a.duration) == "number" and a.duration > 0 and type(a.expires) == "number" then
            sweeping = pcall(b.cd.SetCooldown, b.cd, a.expires - a.duration, a.duration)
        end
        if sweeping then b.cd:Show() else b.cd:Hide() end

        local c = kind == "debuffs" and type(a.dispel) == "string" and not isSecret(a.dispel) and (DebuffTypeColor or DISPEL_COLORS)[a.dispel]
        if type(c) == "table" and type(c.r) == "number" then
            ns.W.setBorder(b, c.r, c.g, c.b, 1)
        else
            ns.W.setBorder(b, 0, 0, 0, 1)
        end
        local col, row = (n - 1) % perRow, floor((n - 1) / perRow)
        b:ClearAllPoints()
        b:SetPoint(corner, set.frame, corner, col * step, dir * row * step)
        b:Show()
    end
    for i = n + 1, #set.buttons do set.buttons[i]:Hide() end
    local cols, rows = max(1, (n < perRow) and n or perRow), max(1, ceil(n / perRow))
    set.width, set.height = cols * step - 2, rows * step - 2
    set.frame:SetSize(set.width, set.height)
    set.shown = n > 0
    if n > 0 then set.frame:Show() else set.frame:Hide() end
end

-- Puts the aura rows on their sides: debuffs nearest the frame, buffs beyond them when
-- both are on the same side.
local function placeAuras(f)
    local cfg = settings()[f.def.key]
    if not cfg then return end
    local used = {}
    for _, kind in ipairs({ "debuffs", "buffs" }) do
        local set = f.auras[kind]
        local side = cfg[kind]
        if set.shown and SIDES[side] and side ~= "off" then
            local gap = 4 + (used[side] or 0)
            set.frame:ClearAllPoints()
            if side == "above" then set.frame:SetPoint("BOTTOMLEFT", f, "TOPLEFT", 0, gap)
            elseif side == "below" then set.frame:SetPoint("TOPLEFT", f, "BOTTOMLEFT", 0, -gap)
            elseif side == "left" then set.frame:SetPoint("TOPRIGHT", f, "TOPLEFT", -gap, 0)
            else set.frame:SetPoint("TOPLEFT", f, "TOPRIGHT", gap, 0) end
            used[side] = (used[side] or 0) + ((side == "above" or side == "below") and set.height or set.width) + 4
        end
    end
end

local function updateAuras(f)
    if not f.auras then return end
    updateAuraSet(f, "debuffs")
    updateAuraSet(f, "buffs")
    placeAuras(f)
end

local function updateAll(f)
    if not exists(f.unit) then return end
    updateName(f)
    updateHealth(f)
    updatePower(f)
    updatePortrait(f)
    updateAuras(f)
end

-- Without RegisterUnitWatch, the frame follows the unit by hand.
local function updateVisibility(f)
    if f.watched then return end
    if exists(f.unit) then f:Show() else f:Hide() end
end

local function onEvent(self, event, arg1)
    if event == "PLAYER_TARGET_CHANGED" then
        updateVisibility(self)
        updateAll(self)
        return
    end
    if event == "PLAYER_ENTERING_WORLD" then
        updateVisibility(self)
        updateAll(self)
        return
    end
    if event == "UNIT_TARGET" then
        if self.unit == "targettarget" and arg1 == "target" then
            updateVisibility(self)
            updateAll(self)
        end
        return
    end
    if event == "UNIT_PET" then
        if self.unit == "pet" and arg1 == "player" then
            updateVisibility(self)
            updateAll(self)
        end
        return
    end
    if arg1 ~= nil and arg1 ~= self.unit then return end
    if event == "UNIT_AURA" then updateAuras(self)
    elseif event == "UNIT_PORTRAIT_UPDATE" or event == "UNIT_MODEL_CHANGED" then updatePortrait(self)
    elseif event == "UNIT_NAME_UPDATE" then updateName(self)
    elseif event == "UNIT_HEALTH" or event == "UNIT_MAXHEALTH" or event == "UNIT_HEALTH_FREQUENT" or event == "UNIT_FACTION" or event == "UNIT_CONNECTION" then
        updateHealth(self)
    else
        updatePower(self)
    end
end

---------------------------------------------------------------------------
-- Building a frame
---------------------------------------------------------------------------

local function capitalize(s)
    return s:sub(1, 1):upper() .. s:sub(2)
end

-- The text on a frame, in the font and size the settings name. A font the game cannot load
-- (a file that is not there) leaves the game's default in its place.
local function applyFonts(f)
    local font = Units.Font(settings().font)
    local standard = type(STANDARD_TEXT_FONT) == "string" and STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF"
    local path, size = font.path or standard, limited("fontSize")
    for _, fs in ipairs({ f.name, f.healthText, f.level, f.powerText }) do
        if fs and type(fs.SetFont) == "function" then
            local ok, set = pcall(fs.SetFont, fs, path, size, "")
            if (not ok or set == false) and path ~= standard then pcall(fs.SetFont, fs, standard, size, "") end
        end
    end
    f.fontPath, f.fontSize = path, size
end

-- The frame and its mover at the size the settings give. Not in combat: the game does not
-- let a secure frame be resized then; Units.OnCombatEnd does it afterwards.
local function resize(f)
    if InCombatLockdown and InCombatLockdown() then
        Units.pendingResize = true
        return false
    end
    local w, h = dims(f.def)
    f:SetSize(w, h)
    ns.Overhaul.Mover(f.def.key, f.def.label, w, h, f.def.default)
    return true
end

-- Lays the bars and portrait out; run again when the portrait or a size setting changes.
local function layout(f)
    local def = f.def
    local _, height = dims(def)
    local inner = height - 2
    local left = 1
    if f.portrait and settings().portrait then
        f.portrait:SetSize(inner, inner)
        if f.model then f.model:SetSize(inner, inner) end
        left = inner + 2
    end
    local healthH = floor((inner - 1) * 0.68)
    f.health:ClearAllPoints()
    f.health:SetPoint("TOPLEFT", f, "TOPLEFT", left, -1)
    f.health:SetPoint("TOPRIGHT", f, "TOPRIGHT", -1, -1)
    f.health:SetHeight(healthH)
    f.power:ClearAllPoints()
    f.power:SetPoint("TOPLEFT", f.health, "BOTTOMLEFT", 0, -1)
    f.power:SetPoint("TOPRIGHT", f.health, "BOTTOMRIGHT", 0, -1)
    f.power:SetPoint("BOTTOM", f, "BOTTOM", 0, 1)
end

local function bar(parent)
    local W = ns.W
    local b = CreateFrame("StatusBar", nil, parent)
    b:SetStatusBarTexture(W.WHITE)
    local bg = b:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    W.colorTexture(bg, 0.12, 0.12, 0.12, 0.9)
    return b
end

local function build(def)
    local W = ns.W
    local f = W.safeCreate("Button", "MintCommunityTools" .. capitalize(def.key) .. "Frame", UIParent, "SecureUnitButtonTemplate")
    f.def, f.unit = def, def.unit
    pcall(f.SetAttribute, f, "unit", def.unit)
    pcall(f.SetAttribute, f, "*type1", "target")
    pcall(f.SetAttribute, f, "*type2", "togglemenu")
    pcall(f.RegisterForClicks, f, "AnyUp")
    f:SetSize(dims(def))
    f:SetFrameStrata("LOW")
    W.skin(f, W.COLOR.panel)
    -- false, not nil, for what this frame does not have: a frame answers a missing key with
    -- nil, the test harness's stub does not.
    f.portrait, f.model, f.auras, f.level, f.powerText, f.watched = false, false, false, false, false, false

    if def.auras then
        f.portrait = f:CreateTexture(nil, "ARTWORK")
        f.portrait:SetPoint("TOPLEFT", 1, -1)
        -- The 3D portrait: a model frame over the same square, made now (frames cannot be
        -- made on a secure frame in combat) and shown only when the setting asks for it.
        local ok, model = pcall(CreateFrame, "PlayerModel", nil, f)
        if ok and type(model) == "table" then
            f.model = model
            model:SetPoint("TOPLEFT", 1, -1)
            pcall(model.EnableMouse, model, false)   -- clicks go to the unit frame under it
            model:Hide()
        end
    end
    f.health = bar(f)
    f.power = bar(f)
    -- The numbers take the room they need on the right; the name has the rest of the bar, both
    -- of its parts when they fit and cut short with dots when they do not.
    f.healthText = W.fontString(f.health, "GameFontHighlightSmall")
    f.healthText:SetPoint("RIGHT", f.health, "RIGHT", -4, 0)
    f.healthText:SetJustifyH("RIGHT")
    f.name = W.fontString(f.health, "GameFontHighlightSmall")
    f.name:SetPoint("LEFT", f.health, "LEFT", 4, 0)
    f.name:SetPoint("RIGHT", f.healthText, "LEFT", -4, 0)
    if f.name.SetWordWrap then f.name:SetWordWrap(false) end
    if def.auras then
        f.level = W.fontString(f.power, "GameFontHighlightSmall", 60)
        f.level:SetPoint("LEFT", f.power, "LEFT", 4, 0)
        f.powerText = W.fontString(f.power, "GameFontHighlightSmall", 80)
        f.powerText:SetPoint("RIGHT", f.power, "RIGHT", -4, 0)
        f.powerText:SetJustifyH("RIGHT")
        f.auras = {}
        for _, kind in ipairs({ "buffs", "debuffs" }) do
            local holder = CreateFrame("Frame", nil, f)
            holder:SetSize(1, 1)
            holder:Hide()
            f.auras[kind] = { frame = holder, buttons = {}, shown = false, width = 0, height = 0 }
        end
    end
    applyFonts(f)
    layout(f)

    f:SetScript("OnEnter", function(self)
        W.setBorder(self, W.accent())
        if GameTooltip and UnitExists then
            GameTooltip:SetOwner(self, "ANCHOR_BOTTOMRIGHT")
            pcall(GameTooltip.SetUnit, GameTooltip, self.unit)
            GameTooltip:Show()
        end
    end)
    f:SetScript("OnLeave", function(self)
        local b = W.COLOR.border
        W.setBorder(self, b[1], b[2], b[3], b[4])
        if GameTooltip then GameTooltip:Hide() end
    end)

    for _, ev in ipairs(UNIT_EVENTS) do pcall(f.RegisterEvent, f, ev) end
    pcall(f.RegisterEvent, f, "PLAYER_ENTERING_WORLD")
    if def.watch then pcall(f.RegisterEvent, f, "PLAYER_TARGET_CHANGED") end
    f:SetScript("OnEvent", onEvent)

    if def.watch then
        if RegisterUnitWatch and pcall(RegisterUnitWatch, f) then
            f.watched = true
        else
            updateVisibility(f)
        end
    end

    local width, height = dims(def)
    local mover = ns.Overhaul.Mover(def.key, def.label, width, height, def.default)
    f:ClearAllPoints()
    f:SetPoint("TOPLEFT", mover, "TOPLEFT", 0, 0)
    frames[def.key] = f
    updateAll(f)
    return f
end

---------------------------------------------------------------------------
-- The game's own frames
---------------------------------------------------------------------------

local function hideBlizzard()
    local O = ns.Overhaul
    local combo = frame("ComboFrame")
    if combo and frames.target then
        pcall(combo.SetParent, combo, UIParent)
        pcall(combo.ClearAllPoints, combo)
        pcall(combo.SetPoint, combo, "BOTTOMRIGHT", frames.target, "TOPRIGHT", 0, 2)
    end
    local cast = frame("TargetFrameSpellBar")
    if cast and frames.target then
        pcall(cast.SetParent, cast, UIParent)
        pcall(cast.ClearAllPoints, cast)
        pcall(cast.SetPoint, cast, "TOP", frames.target, "BOTTOM", 0, -60)
        cast.ignoreFramePositionManager = true
    end
    -- Class resources (combo points, totems) hang off the player frame on a newer client:
    -- kept, under the addon's player frame.
    if frames.player then
        local holders = {
            { "PlayerBottomManagedFrameContainer", "TOP", "BOTTOM", 0, -4 },
            { "PlayerFrameBottomManagedFramesContainer", "TOP", "BOTTOM", 0, -4 },
            { "TotemFrame", "TOPLEFT", "BOTTOMLEFT", 0, -24 },
        }
        for _, h in ipairs(holders) do
            local f = frame(h[1])
            if f then
                pcall(f.SetParent, f, UIParent)
                pcall(f.ClearAllPoints, f)
                pcall(f.SetPoint, f, h[2], frames.player, h[3], h[4], h[5])
                f.ignoreFramePositionManager = true
            end
        end
    end
    for _, name in ipairs({ "PlayerFrame", "TargetFrame", "TargetFrameToT", "TargetofTargetFrame", "PetFrame" }) do
        O.HideBlizzard(frame(name))
    end
end

function Units.Apply()
    for _, def in ipairs(UNITS) do
        if not frames[def.key] then build(def) end
    end
    hideBlizzard()
end

-- Settings changed: sizes, fonts, the portrait and the aura rows follow at once (sizes after
-- combat, when in it).
function Units.OnSettingsChanged()
    for _, f in pairs(frames) do
        resize(f)
        applyFonts(f)
        layout(f)
        updatePortrait(f)
        updateAuras(f)
    end
end

-- Combat is over: a size change that had to wait is made now.
function Units.OnCombatEnd()
    if not Units.pendingResize then return end
    Units.pendingResize = nil
    Units.OnSettingsChanged()
end

-- The next side after `side`, for the Settings tab's cycle buttons.
function Units.NextSide(side)
    for i, s in ipairs(Units.SIDES) do
        if s == side then return Units.SIDES[i % #Units.SIDES + 1] end
    end
    return Units.SIDES[1]
end
