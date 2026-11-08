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

    The party: four frames in a column, one for each party member, clickable like the rest,
    on one box in edit mode. Built like the player's frame (a portrait, flat or 3D as the
    portrait settings say; buff and debuff rows on the sides the party settings pick, one
    setting for all four), at a width and height of their own, the health as a percentage.
    They are a setting (on by default), and stay out of the way in a raid, where the game's
    raid frames show the same people. The game's party window is put away while they are
    on, and given back when they are turned off.

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
    -- the pet frame carries pills (`pills`) for a hunter's pet's mood, aura rows or no
    { key = "pet", unit = "pet", label = "Pet frame", watch = true, pills = true, default = { "BOTTOM", -250, 274 } },
    -- the party: four frames in a column, on one box in edit mode (the group's), with a
    -- portrait and aura rows like the player's and the target's, at a size of their own
    -- (`size`), their aura rows set under one key for all four (`cfg`), the health as a
    -- percentage (`percent`) for the room there is
    { key = "party1", unit = "party1", watch = true, auras = true, percent = true, group = "party", index = 1, size = "party", cfg = "party" },
    { key = "party2", unit = "party2", watch = true, auras = true, percent = true, group = "party", index = 2, size = "party", cfg = "party" },
    { key = "party3", unit = "party3", watch = true, auras = true, percent = true, group = "party", index = 3, size = "party", cfg = "party" },
    { key = "party4", unit = "party4", watch = true, auras = true, percent = true, group = "party", index = 4, size = "party", cfg = "party" },
}
Units.UNITS = UNITS
-- A group of frames that share one box: its label there, where the box starts out, how
-- many frames stand in its column, and the settings that size them.
local GROUPS = {
    party = { label = "Party frames", default = { "TOPLEFT", 20, -260 }, count = 4, width = "partyWidth", height = "partyHeight" },
}
local GROUP_GAP = 4
-- The game's party window, put away while the addon's party frames are on.
local PARTY_GAME = { "PartyFrame", "PartyMemberFrame1", "PartyMemberFrame2", "PartyMemberFrame3", "PartyMemberFrame4" }

-- Events that are about one unit (the first argument says which).
local UNIT_EVENTS = {
    "UNIT_HEALTH", "UNIT_MAXHEALTH", "UNIT_HEALTH_FREQUENT", "UNIT_POWER_UPDATE", "UNIT_POWER_FREQUENT", "UNIT_MAXPOWER",
    "UNIT_DISPLAYPOWER", "UNIT_MANA", "UNIT_RAGE", "UNIT_ENERGY", "UNIT_FOCUS", "UNIT_MAXMANA", "UNIT_MAXRAGE",
    "UNIT_MAXENERGY", "UNIT_MAXFOCUS", "UNIT_NAME_UPDATE", "UNIT_LEVEL", "UNIT_FACTION", "UNIT_CONNECTION",
    "UNIT_PORTRAIT_UPDATE", "UNIT_MODEL_CHANGED", "UNIT_AURA", "UNIT_TARGET", "UNIT_PET", "UNIT_CLASSIFICATION_CHANGED", "UNIT_FLAGS",
}
-- Events of no unit that change what a frame says: the player in or out of combat, resting.
local STATE_EVENTS = { "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED", "PLAYER_UPDATE_RESTING", "UNIT_HAPPINESS" }
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
    fontSize = { 8, 20, 1 }, levelSize = { 8, 24, 1 }, width = { 120, 400, 10 }, height = { 30, 90, 2 },
    smallWidth = { 80, 260, 10 }, smallHeight = { 16, 50, 2 },
    partyWidth = { 80, 400, 10 }, partyHeight = { 16, 90, 2 },
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
-- frames another, the party frames a third.
local function dims(def)
    if def.size == "party" then return limited("partyWidth"), limited("partyHeight") end
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

local function inRaid()
    return flag(call(IsInRaid))
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

-- The level alone, in the game's difficulty colour; "??" for a level the game does not give
-- (a boss, a unit too high to read). What else the unit is stands in tagsText.
local function levelText(unit)
    local level = call(UnitLevel, unit)
    if isSecret(level) then
        local ok, text = pcall(sformat, "%d", level)
        return ok and text or ""
    end
    local text = (type(level) == "number" and level > 0) and tostring(level) or "??"
    local c
    if type(level) == "number" and level > 0 then
        c = call(GetQuestDifficultyColor, level) or call(GetDifficultyColor, level)
    end
    if type(c) == "table" and type(c.r) == "number" then
        return ("|cff%02x%02x%02x%s|r"):format(floor(c.r * 255 + 0.5), floor(c.g * 255 + 0.5), floor(c.b * 255 + 0.5), text)
    end
    return text
end

-- What stands out about a unit, as small flat pills on the power bar: a coloured block with
-- dark text and a 1px border, one for each of these, in this order. ELITE, RARE, RARE ELITE
-- or BOSS from the game's classification (gold for elites and bosses, silver for rares),
-- PVP in red for a player flagged for PvP, COMBAT in orange for a unit fighting, RESTING in
-- blue for the player in an inn or a city. None for an ordinary unit at peace. A secret
-- answer counts as nothing to say.
-- A tag's word, its colour, and (for what the unit is) the colour of the star on each side
-- of its pill: gold for an elite or a boss, silver for a rare.
local GOLD, SILVER = { 1, 0.82, 0 }, { 0.82, 0.82, 0.9 }
local TAGS = {
    elite = { "ELITE", 1, 0.82, 0, GOLD }, rareelite = { "RARE ELITE", 1, 0.82, 0, GOLD }, worldboss = { "BOSS", 1, 0.82, 0, GOLD },
    rare = { "RARE", 0.78, 0.78, 1, SILVER }, pvp = { "PVP", 1, 0.25, 0.25 },
    combat = { "COMBAT", 1, 0.5, 0 }, resting = { "RESTING", 0.5, 0.78, 1 },
    -- a hunter's pet's mood, the game's 1 (unhappy) to 3 (happy)
    happy = { "HAPPY", 0.3, 0.85, 0.3 }, content = { "CONTENT", 1, 0.82, 0 }, unhappy = { "UNHAPPY", 1, 0.25, 0.25 },
}
Units.TAGS = TAGS
local HAPPINESS = { "unhappy", "content", "happy" }

-- The pet frame is on unless the Units page turned it off.
local function petOn()
    return settings().pet ~= false
end

-- A hunter's pet's mood, as the key of its pill: "happy", "content" or "unhappy" from the
-- game's 3, 2 or 1. Nil without a pet, for another class's pet (the game says nothing of
-- its mood) and on a client without the call. WoW Forever has the call as
-- C_PetInfo.GetPetHappiness (the old GetPetHappiness is gone); older clients the other way
-- round. What it gives back is taken as a number, a table with the number in it, or the
-- mood's word.
local function moodOf(v)
    if isSecret(v) then return nil end
    if type(v) == "number" then return HAPPINESS[v] end
    if type(v) == "string" then
        local w = v:lower()
        if w:find("unhappy", 1, true) then return "unhappy" end
        if w:find("content", 1, true) then return "content" end
        if w:find("happy", 1, true) then return "happy" end
        return nil
    end
    if type(v) == "table" then
        for _, k in ipairs({ "happiness", "happinessState", "state", "mood", "level", "value" }) do
            local mood = moodOf(v[k])
            if mood then return mood end
        end
    end
    return nil
end

local function happinessCall()
    if type(C_PetInfo) == "table" and type(C_PetInfo.GetPetHappiness) == "function" then return C_PetInfo.GetPetHappiness end
    if type(GetPetHappiness) == "function" then return GetPetHappiness end
    return nil
end

local function happinessOf()
    if not exists("pet") then return nil end
    return moodOf((call(happinessCall())))
end

-- The game's own pet frame is one the player frame's container manages, and Edit Mode gives
-- it back to that container, and so to the screen, whenever it applies a layout: a pet
-- summoned is one such time. Put under the hider again as soon as it shows (its OnShow is
-- hooked), after combat when it shows in combat (a secure frame), and looked at once a
-- second besides.
local function keepPetAway()
    local O = ns.Overhaul
    local pet = frame("PetFrame")
    if not pet then return false end
    local ok, parent = pcall(pet.GetParent, pet)
    if ok and parent == O.hider then return false end
    if InCombatLockdown and InCombatLockdown() then
        Units.pendingPet = true
        return false
    end
    O.HideBlizzard(pet)
    return true
end
Units.KeepPetAway = keepPetAway

local petHooked = false
local function watchPet()
    local pet = frame("PetFrame")
    if petHooked or not pet or type(pet.HookScript) ~= "function" then return false end
    petHooked = true
    pcall(pet.HookScript, pet, "OnShow", keepPetAway)
    return true
end

local watcher = CreateFrame("Frame", nil, UIParent)
watcher.since = 0
watcher:SetScript("OnUpdate", function(self, elapsed)
    self.since = self.since + (tonumber(elapsed) or 0)
    if self.since < 1 then return end
    self.since = 0
    if petHooked then keepPetAway() end
    if Units.RefreshMoods then Units.RefreshMoods() end
end)
Units.watcher = watcher
local PILL_TEXT = { 0.08, 0.08, 0.08, 1 }
local PILL_GAP, PILL_PAD, STAR_GAP = 3, 4, 2
local STAR_ATLAS = "auctionhouse-icon-favorite"   -- the game's own golden star; tinted

local function tagsOf(unit)
    local out = {}
    local class = call(UnitClassification, unit)
    if isSecret(class) then class = nil end
    if TAGS[class] then out[#out + 1] = class end
    local player, pvp, ffa = call(UnitIsPlayer, unit), call(UnitIsPVP, unit), call(UnitIsPVPFreeForAll, unit)
    if not (isSecret(player) or isSecret(pvp) or isSecret(ffa)) and player == true and (pvp == true or ffa == true) then
        out[#out + 1] = "pvp"
    end
    local combat = call(UnitAffectingCombat, unit)
    if not isSecret(combat) and combat == true then out[#out + 1] = "combat" end
    if unit == "player" then
        local resting = call(IsResting)
        if not isSecret(resting) and resting == true then out[#out + 1] = "resting" end
    end
    -- a hunter's pet's mood: on the pet frame, or on the player frame while the pet frame is off
    if unit == "pet" or (unit == "player" and not petOn()) then
        local mood = happinessOf()
        if mood then out[#out + 1] = mood end
    end
    return out
end

-- A pill's height and its text size: as tall as the power bar allows, the text a little
-- smaller than the frame's; on a short frame the pill overflows the bar a touch rather
-- than shrink past reading.
local function pillMetrics(f)
    local size = f.fontSize or limited("fontSize")
    local h = (f.powerHeight or 14) - 2
    if h > size + 6 then h = size + 6 end
    if h < 12 then h = 12 end
    local at = size
    if at > h - 3 then at = h - 3 end
    if at < 8 then at = 8 end
    return h, at
end

-- A star beside a pill: the game's star atlas, drawn grey and tinted, on the frame's dark
-- ground just outside the pill.
local function star(p, side)
    local t = p[side]
    if t then return t end
    t = p:CreateTexture(nil, "OVERLAY")
    if side == "starL" then
        t:SetPoint("RIGHT", p, "LEFT", -STAR_GAP, 0)
    else
        t:SetPoint("LEFT", p, "RIGHT", STAR_GAP, 0)
    end
    local ok = pcall(t.SetAtlas, t, STAR_ATLAS, false)
    if not ok then pcall(t.SetTexture, t, "Interface\\Common\\ReputationStar") end
    pcall(t.SetDesaturated, t, true)
    p[side] = t
    return t
end

-- The i-th pill of a frame, made when first needed. The row's anchors are set as it is
-- shown (showPills): where a pill stands depends on the stars its neighbours carry.
local function pill(f, i)
    local p = f.pills[i]
    if p then return p end
    local W = ns.W
    p = CreateFrame("Frame", nil, f.power)
    W.skin(p, W.COLOR.panel)
    p.text = W.fontString(p, "GameFontHighlightSmall", nil, PILL_TEXT)
    p.text:SetPoint("CENTER", p, "CENTER", 0, 0)
    p.text:SetJustifyH("CENTER")
    p.starL, p.starR = false, false
    f.pills[i] = p
    return p
end

-- How far a pill row hangs below the frame: half a pill, so the row straddles the bottom
-- edge, half on the frame and half off it.
local function pillHang(f)
    local h = pillMetrics(f)
    return floor(h / 2)
end

-- Shows one pill for each key, in order, and hides the rest. The row starts at the left of
-- the power bar and straddles the frame's bottom edge, half a pill below it; a pill with
-- stars has one on each side, outside the block, and the row leaves room for them.
local function showPills(f, keys)
    if not f.pills then return end
    local W = ns.W
    local h, at = pillMetrics(f)
    local starSize = at + 2
    local standard = type(STANDARD_TEXT_FONT) == "string" and STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF"
    local before = 0   -- room the previous pill's right star takes
    for i, key in ipairs(keys) do
        local t = TAGS[key]
        local p = pill(f, i)
        p.key = key
        pcall(p.text.SetFont, p.text, f.fontPath or standard, at, "")
        p.text:SetText(t[1])
        local okW, w = pcall(p.text.GetStringWidth, p.text)
        if not okW or type(w) ~= "number" or w <= 0 then w = #t[1] * at * 0.62 end
        p:SetSize(floor(w + PILL_PAD * 2 + 0.5), h)
        W.setBg(p, { t[2], t[3], t[4], 1 })
        W.setBorder(p, t[2] * 0.55, t[3] * 0.55, t[4] * 0.55, 1)
        local stars = t[5]
        local room = stars and (starSize + STAR_GAP) or 0
        for _, side in ipairs({ "starL", "starR" }) do
            if stars then
                local s = star(p, side)
                s:SetSize(starSize, starSize)
                pcall(s.SetVertexColor, s, stars[1], stars[2], stars[3], 1)
                s:Show()
            elseif p[side] then
                p[side]:Hide()
            end
        end
        p:ClearAllPoints()
        if i == 1 then
            p:SetPoint("BOTTOMLEFT", f.power, "BOTTOMLEFT", 3 + room, -(pillHang(f) + 1))
        else
            p:SetPoint("LEFT", f.pills[i - 1], "RIGHT", PILL_GAP + before + room, 0)
        end
        before = room
        p:Show()
    end
    for i = #keys + 1, #f.pills do f.pills[i]:Hide() end
end

local function updateTags(f)
    if f.pills then showPills(f, tagsOf(f.unit)) end
end

-- Once a second: the pet's mood is read again, on whichever frame carries it, in case the
-- client tells of a change under an event name this addon does not know.
function Units.RefreshMoods()
    if frames.pet and rawget(frames.pet, "_shown") ~= false and exists("pet") then
        if petOn() then updateTags(frames.pet) elseif frames.player then updateTags(frames.player) end
    end
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
    elseif f.def.percent or not f.def.auras then text = percentText(unit, cur, maxv, secret)   -- the small frames and the party: a percentage
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
    updateTags(f)
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
    local cfg = s[f.def.cfg or f.def.key]
    local set = f.auras[kind]
    local side = cfg and cfg[kind] or "off"
    local sample = Units.previewing and f.def.group and Units.SAMPLE_AURAS[kind] or nil
    if not SIDES[side] or side == "off" or (not sample and not exists(f.unit)) then
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
        local a
        if sample then a = sample[i] else a = auraAt(f.unit, i, filter) end
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
    local cfg = settings()[f.def.cfg or f.def.key]
    if not cfg then return end
    local used = {}
    for _, kind in ipairs({ "debuffs", "buffs" }) do
        local set = f.auras[kind]
        local side = cfg[kind]
        if set.shown and SIDES[side] and side ~= "off" then
            local gap = 4 + (used[side] or 0)
            set.frame:ClearAllPoints()
            if side == "above" then set.frame:SetPoint("BOTTOMLEFT", f, "TOPLEFT", 0, gap)
            elseif side == "below" then set.frame:SetPoint("TOPLEFT", f, "BOTTOMLEFT", 0, -gap - (f.pills and pillHang(f) or 0))
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
    if Units.previewing and f.def.group then
        f:Show()
        return
    end
    if f.unit == "pet" and not petOn() then
        f:Hide()
        return
    end
    if f.watched then return end
    if exists(f.unit) then f:Show() else f:Hide() end
end

local function onEvent(self, event, arg1)
    -- a frame showing a sample member keeps it whatever the real party does
    if Units.previewing and self.def.group then return end
    if event == "PLAYER_TARGET_CHANGED" then
        updateVisibility(self)
        updateAll(self)
        return
    end
    if event == "PLAYER_ENTERING_WORLD" or event == "GROUP_ROSTER_UPDATE" then
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
        if arg1 == "player" then
            if self.unit == "pet" then
                updateVisibility(self)
                updateAll(self)
                keepPetAway()
            elseif self.unit == "player" then
                updateTags(self)   -- the pet's mood on this frame, while the pet frame is off
            end
        end
        return
    end
    if event == "PLAYER_REGEN_DISABLED" or event == "PLAYER_REGEN_ENABLED" or event == "PLAYER_UPDATE_RESTING" or event == "UNIT_HAPPINESS" then
        updateTags(self)
        return
    end
    if arg1 ~= nil and arg1 ~= self.unit then return end
    if event == "UNIT_AURA" then updateAuras(self)
    elseif event == "UNIT_FLAGS" then updateTags(self)
    elseif event == "UNIT_PORTRAIT_UPDATE" or event == "UNIT_MODEL_CHANGED" then updatePortrait(self)
    elseif event == "UNIT_NAME_UPDATE" then updateName(self)
    elseif event == "UNIT_HEALTH" or event == "UNIT_MAXHEALTH" or event == "UNIT_HEALTH_FREQUENT" or event == "UNIT_FACTION" or event == "UNIT_CONNECTION" then
        updateHealth(self)
        if event == "UNIT_FACTION" then updateTags(self) end   -- the PvP flag comes and goes with this
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
    local function set(fs, at)
        if fs and type(fs.SetFont) == "function" then
            local ok, done = pcall(fs.SetFont, fs, path, at, "")
            if (not ok or done == false) and path ~= standard then pcall(fs.SetFont, fs, standard, at, "") end
        end
    end
    for _, fs in ipairs({ f.name, f.healthText, f.powerText }) do set(fs, size) end
    set(f.level, limited("levelSize"))   -- the level at its own, larger size
    f.fontPath, f.fontSize = path, size
end

---------------------------------------------------------------------------
-- A group of frames on one box (the party)
---------------------------------------------------------------------------

local groups = {}   -- group key -> the frame its members hang off, which the box moves

-- Whether a group's frames are to be seen at all: the party's are a setting, and stay out
-- of the way in a raid, where the game's raid frames show the same people.
local function partyOn()
    local party = settings().party
    return type(party) == "table" and party.enabled ~= false
end

local function groupWanted(key)
    if key == "party" then return partyOn() and (Units.previewing or not inRaid()) end
    return true
end

-- Not in combat: the holder's frames are secure, and the game does not let their parent be
-- shown or hidden then; Units.OnCombatEnd does it after.
local function showGroup(key)
    local holder = groups[key]
    if not holder then return end
    if InCombatLockdown and InCombatLockdown() then
        Units.pendingGroup = true
        return
    end
    if groupWanted(key) then holder:Show() else holder:Hide() end
end

local function groupHolder(key)
    local holder = groups[key]
    if holder then return holder end
    holder = CreateFrame("Frame", "MintCommunityTools" .. capitalize(key) .. "Frame", UIParent)
    holder.group = key
    holder:SetSize(1, 1)
    groups[key] = holder
    pcall(holder.RegisterEvent, holder, "GROUP_ROSTER_UPDATE")
    pcall(holder.RegisterEvent, holder, "PLAYER_ENTERING_WORLD")
    holder:SetScript("OnEvent", function(self) showGroup(self.group) end)
    return holder
end

-- The column: the group's frames one under the other on its holder, the holder and its box
-- the column's size. Not in combat (the frames are secure).
local function layoutGroup(key)
    local holder, g = groups[key], GROUPS[key]
    if not holder or not g then return end
    local w, h = limited(g.width), limited(g.height)
    local height = g.count * h + (g.count - 1) * GROUP_GAP
    holder:SetSize(w, height)
    local mover = ns.Overhaul.Mover(key, g.label, w, height, g.default)
    holder:ClearAllPoints()
    holder:SetPoint("TOPLEFT", mover, "TOPLEFT", 0, 0)
    for _, f in pairs(frames) do
        if f.def.group == key then
            f:ClearAllPoints()
            f:SetPoint("TOPLEFT", holder, "TOPLEFT", 0, -(f.def.index - 1) * (h + GROUP_GAP))
        end
    end
end

-- The party frames on or off: the game's party window put away or given back, the
-- addon's shown or hidden with their box.
local function applyParty()
    local O = ns.Overhaul
    local on = partyOn()
    for _, name in ipairs(PARTY_GAME) do
        local f = frame(name)
        if f then
            if on then O.HideBlizzard(f, true) else O.ShowBlizzard(f) end
        end
    end
    if on then layoutGroup("party") else O.HideMover("party") end
    showGroup("party")
end

-- The pet frame on or off: following its unit on its box, or hidden with the box put away;
-- the pet's mood moves to the player frame while it is off. Not in combat (a secure frame):
-- Units.OnCombatEnd does it afterwards.
local function applyPet()
    local f = frames.pet
    if not f then return false end
    if InCombatLockdown and InCombatLockdown() then
        Units.pendingPetFrame = true
        return false
    end
    local O = ns.Overhaul
    if petOn() then
        if f.def.watch and not f.watched and type(RegisterUnitWatch) == "function" and pcall(RegisterUnitWatch, f) then
            f.watched = true
        end
        local w, h = dims(f.def)
        local mover = O.Mover(f.def.key, f.def.label, w, h, f.def.default)
        f:ClearAllPoints()
        f:SetPoint("TOPLEFT", mover, "TOPLEFT", 0, 0)
        updateVisibility(f)
        updateAll(f)
    else
        if f.watched and type(UnregisterUnitWatch) == "function" then pcall(UnregisterUnitWatch, f) end
        f.watched = false
        f:Hide()
        O.HideMover("pet")
    end
    if frames.player then updateTags(frames.player) end
    return true
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
    if f.def.group then
        layoutGroup(f.def.group)
    else
        ns.Overhaul.Mover(f.def.key, f.def.label, w, h, f.def.default)
    end
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
    f.powerHeight = inner - healthH - 1
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
    f.portrait, f.model, f.auras, f.level, f.pills, f.powerText, f.watched = false, false, false, false, false, false, false

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
    -- The level stands first on the health bar, larger than the rest (a size of its own), in
    -- the game's difficulty colour, so it is read at a glance; the name follows it.
    if def.auras then
        f.level = W.fontString(f.health, "GameFontHighlightSmall")
        f.level:SetPoint("LEFT", f.health, "LEFT", 4, 0)
    end
    f.name = W.fontString(f.health, "GameFontHighlightSmall")
    if f.level then
        f.name:SetPoint("LEFT", f.level, "RIGHT", 4, 0)
    else
        f.name:SetPoint("LEFT", f.health, "LEFT", 4, 0)
    end
    f.name:SetPoint("RIGHT", f.healthText, "LEFT", -4, 0)
    if f.name.SetWordWrap then f.name:SetWordWrap(false) end
    if def.auras or def.pills then
        f.pills = {}   -- what the unit is (elite, PvP, in combat...), as pills on the power bar, made as needed
    end
    if def.auras then
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
    for _, ev in ipairs(STATE_EVENTS) do pcall(f.RegisterEvent, f, ev) end
    pcall(f.RegisterEvent, f, "PLAYER_ENTERING_WORLD")
    if def.watch then pcall(f.RegisterEvent, f, "PLAYER_TARGET_CHANGED") end
    if def.group then pcall(f.RegisterEvent, f, "GROUP_ROSTER_UPDATE") end
    f:SetScript("OnEvent", onEvent)

    if def.watch then
        if RegisterUnitWatch and pcall(RegisterUnitWatch, f) then
            f.watched = true
        else
            updateVisibility(f)
        end
    end

    frames[def.key] = f
    if def.group then
        f:SetParent(groupHolder(def.group))
        layoutGroup(def.group)
    else
        local width, height = dims(def)
        local mover = ns.Overhaul.Mover(def.key, def.label, width, height, def.default)
        f:ClearAllPoints()
        f:SetPoint("TOPLEFT", mover, "TOPLEFT", 0, 0)
    end
    updateAll(f)
    return f
end

---------------------------------------------------------------------------
-- The game's own frames
---------------------------------------------------------------------------

-- The target's cast bar, under the addon's target frame. When it shows, the game asks the
-- bar's parent (which it means to be the target frame) two things: whether the bar hangs
-- off the aura rows, and for the aura container, whose forbidden aspects the bar takes on.
-- The addon's target frame answers: no, and the game's own target frame's container (that
-- frame still exists, hidden). The game then anchors the bar under its parent in its own
-- way; it is put where the addon wants it right after, each time.
local function placeTargetCast()
    local cast = frame("TargetFrameSpellBar")
    if not cast or not frames.target then return end
    pcall(cast.ClearAllPoints, cast)
    -- under the frame: its text is on the bar when the cast bars are flat, in a box below
    -- it when they are the game's
    pcall(cast.SetPoint, cast, "TOP", frames.target, "BOTTOM", 0, ns.Overhaul.Active("cast") and -8 or -60)
end

local castHooked = false
local function keepTargetCast()
    local cast, mine = frame("TargetFrameSpellBar"), frames.target
    if not cast or not mine then return end
    local game = frame("TargetFrame")
    mine.ShouldAnchorSpellBarToAuraContainer = function() return false end
    mine.GetAuraContainer = function()
        if game and type(game.GetAuraContainer) == "function" then
            local ok, c = pcall(game.GetAuraContainer, game)
            if ok and type(c) == "table" then return c end
        end
        return mine
    end
    mine.GetInheritableForbiddenAspects = function() return {} end
    pcall(cast.SetParent, cast, mine)
    cast.ignoreFramePositionManager = true
    placeTargetCast()
    -- the game anchors the bar its own way as it shows (its OnShow): put back right after
    if not castHooked and type(cast.HookScript) == "function" then
        castHooked = true
        pcall(cast.HookScript, cast, "OnShow", placeTargetCast)
    end
end

local function hideBlizzard()
    local O = ns.Overhaul
    local combo = frame("ComboFrame")
    if combo and frames.target then
        pcall(combo.SetParent, combo, UIParent)
        pcall(combo.ClearAllPoints, combo)
        pcall(combo.SetPoint, combo, "BOTTOMRIGHT", frames.target, "TOPRIGHT", 0, 2)
    end
    keepTargetCast()
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
    watchPet()
    applyParty()
end

function Units.Apply()
    for _, def in ipairs(UNITS) do
        if not frames[def.key] then build(def) end
    end
    hideBlizzard()
    applyPet()
end

-- Settings changed: everything a frame shows is drawn again at once, whatever the setting
-- was: sizes (after combat, when in it), fonts, the bars' colours, the portrait and the aura
-- rows. A setting is not waited on until the next time the game says the unit changed.
function Units.OnSettingsChanged()
    for _, f in pairs(frames) do
        resize(f)
        applyFonts(f)
        layout(f)
        if exists(f.unit) then
            updateName(f)
            updateHealth(f)
            updatePower(f)
        end
        updatePortrait(f)
        updateAuras(f)
    end
    -- the party and the pet frame on or off: secure frames, so this too waits for combat to end
    if InCombatLockdown and InCombatLockdown() then
        Units.pendingResize = true
    else
        applyParty()
        applyPet()
    end
end

---------------------------------------------------------------------------
-- Sample members, for arranging the party frames without a party
---------------------------------------------------------------------------

-- While Mint edit mode is open the party frames show four made-up members (and a debuff or
-- two on the side the settings say), whoever is or is not in the party, so that the frames
-- can be placed, sized and set up alone. The real party is back when edit mode closes.
Units.SAMPLES = {
    { name = "Aldric Thornwood", class = "WARRIOR", health = 100, power = "RAGE", powerValue = 35, level = 60 },
    { name = "Bryn Ashvale", class = "PRIEST", health = 72, power = "MANA", powerValue = 80, level = 58 },
    { name = "Cael Duskmere", class = "ROGUE", health = 45, power = "ENERGY", powerValue = 100, level = 60, pvp = true },
    { name = "Dara Flintlock", class = "MAGE", health = 90, power = "MANA", powerValue = 55, level = 57 },
}
local SAMPLE_ICON = "Interface\\Icons\\INV_Misc_QuestionMark"
Units.SAMPLE_AURAS = {
    debuffs = { { name = "Sample debuff", icon = "Interface\\Icons\\Spell_Shadow_ShadowWordPain", dispel = "Magic", count = 2 },
                { name = "Sample debuff", icon = "Interface\\Icons\\Ability_Rogue_Rupture" } },
    buffs = { { name = "Sample buff", icon = "Interface\\Icons\\Spell_Holy_WordFortitude" } },
}
Units.previewing = false

local function showSample(f, sample)
    pcall(f.name.SetText, f.name, sample.name)
    pcall(f.health.SetMinMaxValues, f.health, 0, 100)
    pcall(f.health.SetValue, f.health, sample.health)
    local c = settings().classColor and RAID_CLASS_COLORS and RAID_CLASS_COLORS[sample.class]
    if type(c) == "table" and type(c.r) == "number" then f.health:SetStatusBarColor(c.r, c.g, c.b)
    else f.health:SetStatusBarColor(0.2, 0.7, 0.2) end
    pcall(f.healthText.SetText, f.healthText, sformat("%d%%", sample.health))
    pcall(f.power.SetMinMaxValues, f.power, 0, 100)
    pcall(f.power.SetValue, f.power, sample.powerValue)
    local pc = POWER_FALLBACK[sample.power] or POWER_FALLBACK.MANA
    f.power:SetStatusBarColor(pc[1], pc[2], pc[3])
    if f.powerText then pcall(f.powerText.SetText, f.powerText, "") end
    if f.level then pcall(f.level.SetText, f.level, tostring(sample.level)) end
    showPills(f, sample.pvp and { "pvp" } or {})
    if f.portrait then
        if f.model then f.model:Hide() end
        if settings().portrait then
            pcall(f.portrait.SetTexture, f.portrait, SAMPLE_ICON)
            f.portrait:Show()
        else
            f.portrait:Hide()
        end
    end
    updateAuras(f)
end

-- The sample members on or off. Off in combat waits for combat to end (showing and hiding
-- the frames is the game's to allow then).
function Units.Preview(on)
    on = on and true or false
    if on == Units.previewing then return true end
    if InCombatLockdown and InCombatLockdown() then
        Units.pendingPreview = on
        return false
    end
    Units.pendingPreview = nil
    Units.previewing = on
    for _, def in ipairs(UNITS) do
        local f = def.group and frames[def.key]
        if f then
            if on then
                if f.watched and type(UnregisterUnitWatch) == "function" then pcall(UnregisterUnitWatch, f) end
                f:Show()
                showSample(f, Units.SAMPLES[def.index] or Units.SAMPLES[1])
            else
                if f.watched and type(RegisterUnitWatch) == "function" then pcall(RegisterUnitWatch, f) end
                updateVisibility(f)
                if exists(f.unit) then
                    updateName(f)
                    updateHealth(f)
                    updatePower(f)
                end
                updatePortrait(f)
                updateAuras(f)
            end
        end
    end
    showGroup("party")
    return true
end

-- Mint edit mode opened or closed.
function Units.OnEdit(on)
    Units.Preview(on)
end

-- Combat is over: a size change, or a preview change, that had to wait is made now.
function Units.OnCombatEnd()
    if Units.pendingPet then
        Units.pendingPet = nil
        keepPetAway()
    end
    if Units.pendingPetFrame then
        Units.pendingPetFrame = nil
        applyPet()
    end
    if Units.pendingGroup then
        Units.pendingGroup = nil
        for key in pairs(groups) do showGroup(key) end
    end
    if Units.pendingPreview ~= nil then
        local want = Units.pendingPreview
        Units.pendingPreview = nil
        Units.Preview(want)
    end
    if not Units.pendingResize then return end
    Units.pendingResize = nil
    Units.OnSettingsChanged()
end

-- `/mint pet`: what this client says about the pet's mood, for finding the call on a client
-- that does not answer GetPetHappiness. Printed to the chat.
function Units.Report()
    local db = ns.DB()
    db.petReport = {}
    local function say(text)
        db.petReport[#db.petReport + 1] = text
        if ns.Say then ns.Say(text) else print(text) end
    end
    local function s(v)
        if isSecret(v) then return "secret" end
        local ok, r = pcall(tostring, v)
        return ok and r or "?"
    end
    local hasUI, hunter = call(HasPetUI)
    say(sformat("pet: exists %s, HasPetUI %s %s, name %s", s(exists("pet")), s(hasUI), s(hunter), s(call(UnitName, "pet"))))
    local a, b, c = call(GetPetHappiness)
    say(sformat("GetPetHappiness: %s -> %s, %s, %s", type(GetPetHappiness), s(a), s(b), s(c)))
    local cfn = type(C_PetInfo) == "table" and C_PetInfo.GetPetHappiness or nil
    local r1, r2, r3, r4 = call(cfn)
    say(sformat("C_PetInfo.GetPetHappiness: %s -> %s %s, %s, %s, %s; read as %s", type(cfn), type(r1), s(r1), s(r2), s(r3), s(r4), s(moodOf(r1))))
    if type(r1) == "table" then
        for k, v in pairs(r1) do say(sformat("    .%s = %s %s", s(k), type(v), s(v))) end
    end
    say(sformat("UnitPower(pet, 27 happiness) %s / %s", s(call(UnitPower, "pet", 27)), s(call(UnitPowerMax, "pet", 27))))
    local ind = frame("PetFrameHappiness")
    if ind then
        local tex = ind.texture or ind.Texture or frame("PetFrameHappinessTexture")
        say(sformat("PetFrameHappiness: shown %s, texture %s atlas %s coords %s,%s", s(call(ind.IsShown, ind)),
            tex and s(call(tex.GetTexture, tex)) or "-", tex and type(tex.GetAtlas) == "function" and s(call(tex.GetAtlas, tex)) or "-",
            tex and s((call(tex.GetTexCoord, tex))) or "-", tex and s((select(3, call(tex.GetTexCoord, tex)))) or "-"))
    end
    local enum = type(Enum) == "table" and type(Enum.PowerType) == "table" and Enum.PowerType.Happiness or nil
    local pt, ptName = call(UnitPowerType, "pet")
    say(sformat("Enum.PowerType.Happiness %s; UnitPowerType(pet) %s %s; UnitPower(pet, 4) %s / %s",
        s(enum), s(pt), s(ptName), s(call(UnitPower, "pet", 4)), s(call(UnitPowerMax, "pet", 4))))
    local found = 0
    for k, v in pairs(_G) do
        if type(k) == "string" then
            if k:lower():find("happ", 1, true) then
                found = found + 1
                say(sformat("  %s = %s%s", k, type(v), type(v) == "string" and (" " .. v) or ""))
            end
            if k:sub(1, 2) == "C_" and type(v) == "table" then
                for k2, v2 in pairs(v) do
                    if type(k2) == "string" and k2:lower():find("happ", 1, true) then
                        found = found + 1
                        say(sformat("  %s.%s = %s", k, k2, type(v2)))
                    end
                end
            end
        end
    end
    say(sformat("%d global names with 'happ' in them; the report is saved with the addon's data on the next /reload", found))
    local info = frame("PetPaperDollPetHappinessInfo")
    if info and type(info.GetRegions) == "function" then
        local ok, regions = pcall(function() return { info:GetRegions() } end)
        for _, r in ipairs(ok and regions or {}) do
            if type(r) == "table" and type(r.GetTexture) == "function" then
                local tex = call(r.GetTexture, r)
                local atlas = type(r.GetAtlas) == "function" and call(r.GetAtlas, r) or nil
                local l, _, t = call(r.GetTexCoord, r)
                say(sformat("  pet tab happiness texture: %s atlas %s coords %s,%s shown %s", s(tex), s(atlas), s(l), s(t), s(call(r.IsShown, r))))
            end
        end
    else
        say("no PetPaperDollPetHappinessInfo frame")
    end
    return found
end

-- The next side after `side`, for the Settings tab's cycle buttons.
function Units.NextSide(side)
    for i, s in ipairs(Units.SIDES) do
        if s == side then return Units.SIDES[i % #Units.SIDES + 1] end
    end
    return Units.SIDES[1]
end
