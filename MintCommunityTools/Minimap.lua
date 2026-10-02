--[[
    Minimap.lua - a button on the minimap.

    Left-click opens the Mint Community Tools window. Right-click shows or hides the loot
    watcher. Drag it around the minimap's edge; where you leave it is saved.

    /mint minimap            show or hide the button
    /mint minimap reset      back to its default place

    The button sits on the minimap's own edge (half the minimap's width, plus a little). It is
    drawn in the addon's flat skin (UI.lua): a 20px square in the panel colour with a 1px
    border, the icon inset 2px, and the accent colour on its border while the mouse is over it.
]]

local ADDON, ns = ...

local ICON = "Interface\\Icons\\INV_Misc_Note_01"
local DEFAULT_ANGLE = 200      -- degrees, counter-clockwise from the right; lower left

local button
ns.minimapButton = nil

local function settings()
    return ns.DB().minimap
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

local function place()
    local angle = math.rad(tonumber(settings().angle) or DEFAULT_ANGLE)
    local width = Minimap.GetWidth and Minimap:GetWidth()
    local radius = ((type(width) == "number" and width > 0 and width) or 140) / 2 + 5
    button:ClearAllPoints()
    button:SetPoint("CENTER", Minimap, "CENTER", math.cos(angle) * radius, math.sin(angle) * radius)
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
end

function ns.ResetMinimap()
    settings().angle = DEFAULT_ANGLE
    ns.SetMinimapShown(true)
end

-- Called at login, once the settings are in place.
function ns.InitMinimap()
    if settings().shown then ns.SetMinimapShown(true) end
end
