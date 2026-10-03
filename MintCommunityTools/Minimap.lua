--[[
    Minimap.lua - a button on the minimap.

    Left-click opens the Mint Community Tools window. Right-click shows or hides the loot
    watcher. Drag it around the minimap's edge; where you leave it is saved.

    /mint minimap                          show or hide the button
    /mint minimap reset                    back to its default place
    /mint minimap round | square | auto    the shape of the minimap it sits around

    Round puts the button on the circle just outside a round minimap. Square puts it on the
    square just outside a square one, in the same direction from the centre, and clear of the
    strips this addon puts above and below its map. Auto, the default, follows the minimap:
    square when this addon's square minimap is on (Map.lua), or when another addon that squares
    the minimap says so through the global function GetMinimapShape() ("SQUARE" or "ROUND");
    round otherwise. Another addon may also say how much room it has taken above, below, left
    and right of the map through GetMinimapEdgeInsets(). The button looks again once a second,
    so it follows the map when something changes it. The same choice is on the Settings tab.

    The button sits on the minimap's own edge (half the minimap's width, plus a little). It is
    drawn in the addon's flat skin (UI.lua): a 20px square in the panel colour with a 1px
    border, the icon inset 2px, and the accent colour on its border while the mouse is over it.
]]

local ADDON, ns = ...

local ICON = "Interface\\Icons\\INV_Misc_Note_01"
local DEFAULT_ANGLE = 200      -- degrees, counter-clockwise from the right; lower left
local SHAPES = { auto = true, round = true, square = true }
local NEXT_SHAPE = { auto = "round", round = "square", square = "auto" }

local button, watcher
local placed            -- what the last placement was worked out from, to notice a change
ns.minimapButton = nil

local function settings()
    local m = ns.DB().minimap
    if not SHAPES[m.shape] then m.shape = "auto" end
    return m
end

-- What the tooltip shows, as { left, right } pairs. Also used by the tests.
function ns.MinimapLines()
    local drops, items = ns.Loot.Counts()
    local commas = ns.W and ns.W.commas or tostring
    return {
        { "Drops in the loot log", commas(drops) },
        { "Items seen", commas(items) },
        { "New items to export", commas(ns.Loot.PendingCount()) },
    }
end

local function showTooltip(self)
    if not GameTooltip then return end
    GameTooltip:SetOwner(self, "ANCHOR_LEFT")
    GameTooltip:SetText("Mint Community Tools", 1, 0.82, 0)
    for _, line in ipairs(ns.MinimapLines()) do
        if GameTooltip.AddDoubleLine then
            GameTooltip:AddDoubleLine(line[1], line[2], 1, 1, 1, 1, 0.82, 0)
        else
            GameTooltip:AddLine(line[1] .. ": " .. line[2], 1, 1, 1)
        end
    end
    GameTooltip:AddLine(" ")
    GameTooltip:AddLine("Left-click: open the window", 0.6, 0.6, 0.6)
    GameTooltip:AddLine("Right-click: show or hide the loot watcher", 0.6, 0.6, 0.6)
    GameTooltip:AddLine("Drag: move around the minimap", 0.6, 0.6, 0.6)
    GameTooltip:Show()
end

-- "round" or "square": the setting, or with auto what the minimap is. This addon's own square
-- map counts first; after that, whatever another addon says through GetMinimapShape().
function ns.MinimapShape()
    local want = settings().shape
    if want == "round" or want == "square" then return want end
    if ns.Map and ns.Map.Active() then return "square" end
    if type(GetMinimapShape) == "function" then
        local ok, shape = pcall(GetMinimapShape)
        if ok and shape == "SQUARE" then return "square" end
    end
    return "round"
end

-- The room taken above, below, left and right of a square minimap: this addon's own strips
-- when its map is on, otherwise whatever another addon reports.
local function insets()
    if ns.Map and ns.Map.applied then
        local above, below = ns.Map.Insets()
        return above, below, 0, 0
    end
    if type(GetMinimapEdgeInsets) ~= "function" then return 0, 0, 0, 0 end
    local function n(v) return type(v) == "number" and v > 0 and v or 0 end
    local ok, top, bottom, left, right = pcall(GetMinimapEdgeInsets)
    if not ok then return 0, 0, 0, 0 end
    return n(top), n(bottom), n(left), n(right)
end

-- Everything a placement depends on other than the angle.
local function layout()
    local width = Minimap.GetWidth and Minimap:GetWidth()
    if type(width) ~= "number" or width <= 0 then width = 140 end
    local shape = ns.MinimapShape()
    if shape == "square" then return shape, width, insets() end
    return shape, width, 0, 0, 0, 0
end

-- The button's centre, from the minimap's centre: on the circle just outside a round map; on
-- the square just outside a square one, in the same direction, clear of the strips.
local function offset(angle, shape, width, top, bottom, left, right)
    local x, y = math.cos(angle), math.sin(angle)
    if shape ~= "square" then
        local radius = width / 2 + 5
        return x * radius, y * radius
    end
    local half = width / 2 + 12
    local m = math.max(math.abs(x), math.abs(y))
    x, y = x / m * half, y / m * half
    if y >= half - 0.001 then y = y + top elseif y <= -half + 0.001 then y = y - bottom end
    if x >= half - 0.001 then x = x + right elseif x <= -half + 0.001 then x = x - left end
    return x, y
end

local function place()
    local shape, width, top, bottom, left, right = layout()
    local angle = math.rad(tonumber(settings().angle) or DEFAULT_ANGLE)
    local x, y = offset(angle, shape, width, top, bottom, left, right)
    button:ClearAllPoints()
    button:SetPoint("CENTER", Minimap, "CENTER", x, y)
    placed = table.concat({ shape, width, top, bottom, left, right }, ":")
end

-- Once a second: has the minimap changed shape or size since the button was put there?
local function look()
    if placed ~= table.concat({ layout() }, ":") then place() end
end

-- While dragging, the button follows the cursor's direction from the minimap's centre.
local function followCursor()
    local mx, my = Minimap:GetCenter()
    local px, py = GetCursorPosition()
    local scale = Minimap.GetEffectiveScale and Minimap:GetEffectiveScale()
    if type(scale) ~= "number" or scale <= 0 then scale = 1 end
    if not (type(mx) == "number" and type(my) == "number" and type(px) == "number" and type(py) == "number") then return end
    local angle = math.deg(math.atan2(py / scale - my, px / scale - mx))
    settings().angle = (angle + 360) % 360
    place()
end

local function build()
    local W = ns.W
    button = W.safeCreate("Button", "MintCommunityToolsMinimapButton", Minimap, W.template())
    ns.minimapButton = button
    button:SetSize(20, 20)
    button:SetFrameStrata("MEDIUM")
    button:SetFrameLevel(8)
    button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    button:RegisterForDrag("LeftButton")
    W.skin(button, W.COLOR.panel)

    local icon = button:CreateTexture(nil, "ARTWORK")
    icon:SetPoint("TOPLEFT", 2, -2)
    icon:SetPoint("BOTTOMRIGHT", -2, 2)
    icon:SetTexture(ICON)
    if icon.SetTexCoord then icon:SetTexCoord(0.08, 0.92, 0.08, 0.92) end

    button:SetScript("OnClick", function(_, mouseButton)
        if mouseButton == "RightButton" then
            ns.LootUI.ToggleWatch()
        else
            ns.UI.Toggle()
        end
    end)
    button:SetScript("OnEnter", function(self)
        W.setBorder(self, W.accent())
        showTooltip(self)
    end)
    button:SetScript("OnLeave", function(self)
        local b = W.COLOR.border
        W.setBorder(self, b[1], b[2], b[3], b[4])
        if GameTooltip then GameTooltip:Hide() end
    end)
    button:SetScript("OnDragStart", function(self)
        if GameTooltip then GameTooltip:Hide() end
        self:SetScript("OnUpdate", followCursor)
    end)
    button:SetScript("OnDragStop", function(self)
        self:SetScript("OnUpdate", nil)
    end)

    -- A child of the button, so it only runs while the button is shown.
    watcher = W.safeCreate("Frame", "MintCommunityToolsMinimapWatcher", button)
    local elapsed = 0
    watcher:SetScript("OnUpdate", function(_, dt)
        elapsed = elapsed + (type(dt) == "number" and dt or 0)
        if elapsed < 1 then return end
        elapsed = 0
        look()
    end)
end

function ns.SetMinimapShown(shown)
    settings().shown = shown and true or false
    if shown then
        if not Minimap then return end
        if not button then build() end
        place()
        button:Show()
    elseif button then
        button:Hide()
    end
    if ns.SettingsUI and ns.SettingsUI.Refresh then ns.SettingsUI.Refresh() end
end

function ns.ResetMinimap()
    settings().angle = DEFAULT_ANGLE
    ns.SetMinimapShown(true)
end

function ns.NextMinimapShape()
    return NEXT_SHAPE[settings().shape] or "auto"
end

-- "auto", "round" or "square"; anything else is refused.
function ns.SetMinimapShape(shape)
    if not SHAPES[shape] then return false end
    settings().shape = shape
    if button then place() end
    if ns.SettingsUI and ns.SettingsUI.Refresh then ns.SettingsUI.Refresh() end
    return true
end

-- "Button shape: auto (round now)", for the Settings tab's button.
function ns.MinimapShapeLabel()
    local shape = settings().shape
    if shape == "auto" then return ("Button shape: auto (%s now)"):format(ns.MinimapShape()) end
    return "Button shape: " .. shape
end

-- Called at login, once the settings are in place.
function ns.InitMinimap()
    if settings().shown then ns.SetMinimapShown(true) end
end
