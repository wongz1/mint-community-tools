--[[
    UI.lua - the Mint Community Tools window.

    Opened with /mint or the minimap button. It shows your character and every equipment
    slot as the addon sees it (hover a row for the item's tooltip), a summary line, and the
    export string to paste on the website's Roster page. The list refreshes by itself when
    you change gear while the window is open.

    Frames are created defensively: a template that does not exist on this client falls back
    to a bare frame, and nothing here does arithmetic on values read back from frames, so the
    window also builds under the test harness's stub frames. The templates used (BackdropTemplate,
    UIPanelButtonTemplate, UIPanelCloseButton, UIPanelScrollFrameTemplate, GameTooltip) are the
    ones other addons already use on the WoW Forever beta client.
]]

local ADDON, ns = ...
local UI = {}
ns.UI = UI

local ipairs, type, tostring, pcall = ipairs, type, tostring, pcall
local sformat = string.format

local WIDTH, HEIGHT = 470, 690
local ROW_HEIGHT = 18
local LIST_TOP = -100
local NUM_ROWS = #ns.Collect.SLOTS

local QUALITY_COLOR = { [0] = "9d9d9d", [1] = "ffffff", [2] = "1eff00", [3] = "0070dd", [4] = "a335ee", [5] = "ff8000" }

local ui = {}   -- the widgets, also reached by the tests as ns.ui
ns.ui = ui

---------------------------------------------------------------------------
-- Widget helpers
---------------------------------------------------------------------------

-- CreateFrame, but falls back to a template-less frame if the template does not exist here.
local function safeCreate(frameType, name, parent, template)
    if template then
        local ok, f = pcall(CreateFrame, frameType, name, parent, template)
        if ok and f then return f end
    end
    return CreateFrame(frameType, name, parent)
end

local function button(parent, name, text, width, onClick)
    local b = safeCreate("Button", name, parent, "UIPanelButtonTemplate")
    b:SetSize(width, 22)
    b:SetText(text)
    b:SetScript("OnClick", onClick)
    return b
end

local function fontString(parent, template, width)
    local fs = parent:CreateFontString(nil, "OVERLAY", template or "GameFontHighlightSmall")
    if width then fs:SetWidth(width) end
    fs:SetJustifyH("LEFT")
    return fs
end

-- A fully opaque background, so the window reads the same over any part of the game world.
local function solidBackground(frame, inset, shade)
    local bg = frame:CreateTexture(nil, "BACKGROUND")
    bg:SetPoint("TOPLEFT", inset, -inset)
    bg:SetPoint("BOTTOMRIGHT", -inset, inset)
    if bg.SetColorTexture then bg:SetColorTexture(shade, shade, shade * 1.15, 1) else bg:SetTexture(shade, shade, shade * 1.15, 1) end
    return bg
end

local function clock(ts)
    if not ts then return "?" end
    return date and date("%H:%M", ts) or tostring(ts)
end

local function commas(n)
    local s = tostring(n or 0)
    local out = s:reverse():gsub("(%d%d%d)", "%1,"):reverse()
    return (out:gsub("^,", ""))
end

local function selectAll(editBox)
    editBox:SetFocus()
    editBox:HighlightText()
end

---------------------------------------------------------------------------
-- Text
---------------------------------------------------------------------------

local function characterLine(c)
    local name = c.name or "?"
    if c.lastName then name = name .. " " .. c.lastName end
    local parts = { "|cffffd100" .. name .. "|r" }
    local desc = {}
    if c.level then desc[#desc + 1] = "Level " .. tostring(c.level) end
    if c.race then desc[#desc + 1] = c.race end
    if c.class then desc[#desc + 1] = c.class end
    if #desc > 0 then parts[#parts + 1] = table.concat(desc, " ") end
    if c.realm then parts[#parts + 1] = c.realm .. (c.region and (" (" .. c.region .. ")") or "") end
    return table.concat(parts, "  |cff666666-|r  ")
end

local function guildLine(c)
    if not c.guild then return "|cff888888Not in a guild|r" end
    return "<" .. c.guild .. ">" .. (c.guildRank and ("  |cff888888" .. c.guildRank .. "|r") or "")
end

local function itemText(item)
    if not item then return "|cff555555(empty)|r" end
    local color = QUALITY_COLOR[item.quality or 1] or "ffffff"
    local extras = {}
    if item.enchant then extras[#extras + 1] = "enchanted" end
    if item.gems then extras[#extras + 1] = #item.gems .. (#item.gems == 1 and " gem" or " gems") end
    local text = "|cff" .. color .. (item.name or ("item " .. tostring(item.id))) .. "|r"
    if #extras > 0 then text = text .. "  |cff888888" .. table.concat(extras, ", ") .. "|r" end
    return text
end

local function summaryText(data)
    local s = ns.Collect.Summarize(data)
    local line = sformat("%d item%s equipped", s.items, s.items == 1 and "" or "s")
    if s.averageLevel then line = line .. sformat("  |cff666666-|r  average item level |cffffffff%d|r", s.averageLevel) end
    line = line .. sformat("  |cff666666-|r  %d enchanted", s.enchanted)
    if data.talents and #data.talents > 0 then
        local trees = {}
        for _, t in ipairs(data.talents) do trees[#trees + 1] = sformat("%s %d", t.name or "?", t.points or 0) end
        line = line .. "\nTalents: " .. table.concat(trees, "  |cff666666/|r  ")
    elseif data.talentsError then
        line = line .. "\n|cffff6666Talents could not be read.|r"
    end
    return line
end

local function setStatus(text, isError)
    ui.status:SetText(text or "")
    if isError then ui.status:SetTextColor(1, 0.4, 0.4) else ui.status:SetTextColor(0.6, 0.6, 0.6) end
end

---------------------------------------------------------------------------
-- Rows
---------------------------------------------------------------------------

local function rowEnter(row)
    if not (GameTooltip and row.item) then return end
    GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
    local ok = pcall(GameTooltip.SetInventoryItem, GameTooltip, "player", row.slot)
    if not ok then
        GameTooltip:SetText(row.item.name or "", 1, 1, 1)
    end
    GameTooltip:Show()
end

local function rowLeave()
    if GameTooltip then GameTooltip:Hide() end
end

---------------------------------------------------------------------------
-- Refresh: rescan and redraw
---------------------------------------------------------------------------

-- Draws a scan. `data` is nil when the character could not be read.
local function render(data, reason)
    ui.data = data
    if not data then
        ui.who:SetText("|cffff6666Could not read your character.|r")
        ui.guild:SetText(tostring(reason or ""))
        for _, row in ipairs(ui.rows) do row:Hide() end
        ui.summary:SetText("")
        return
    end

    ui.who:SetText(characterLine(data.char))
    ui.guild:SetText(guildLine(data.char))

    local bySlot = {}
    for _, item in ipairs(data.items) do bySlot[item.slot] = item end
    for i, row in ipairs(ui.rows) do
        local slot = ns.Collect.SLOTS[i]
        row.slot = slot
        row.item = bySlot[slot] or false   -- false, not nil: a frame answers a missing key with nil, a stub does not
        row.name:SetText(itemText(row.item or nil))
        row.level:SetText(row.item and row.item.ilvl and tostring(row.item.ilvl) or "")
        row:Show()
    end
    ui.summary:SetText(summaryText(data))

    if ui.exportedAt and ns.lastExport and ns.lastExport.signature ~= ns.Signature(data) then
        setStatus("Your gear changed since the last export. Export again before pasting.", true)
    end
end

-- Rescans and redraws.
function UI.Refresh()
    if not ui.frame then return end
    render(ns.Scan())
end

-- Called from Core when the client says equipment changed.
function UI.OnGearChanged()
    if ui.frame and ui.frame:IsShown() then UI.Refresh() end
end

---------------------------------------------------------------------------
-- Export
---------------------------------------------------------------------------

-- Puts the current export string (or the raw JSON, for debugging) in the copy box.
function UI.Export(rawJson)
    if not ui.frame then build() end
    if not ui.frame:IsShown() then ui.frame:Show() end   -- OnShow draws the current gear
    local text, data, reason = ns.Export(rawJson)
    if not text then
        setStatus(tostring(reason or "nothing to export"), true)
        return
    end
    render(data)   -- the list shows exactly what was exported
    ui.currentText = text
    ui.editBox:SetText(text)
    ui.exportedAt = data.ts
    selectAll(ui.editBox)
    -- Highlighting straight after SetText can be lost on some clients, so retry next frame.
    if C_Timer and C_Timer.After then
        C_Timer.After(0, function() if ui.currentText == text then selectAll(ui.editBox) end end)
    end
    setStatus(sformat("Exported at %s: %s characters, %d items. Press Ctrl+C now.",
        clock(data.ts), commas(#text), #data.items))
    if #data.items == 0 then
        setStatus("No equipped items were found. Type /mint debug and report the output.", true)
    end
end

---------------------------------------------------------------------------
-- Building the window
---------------------------------------------------------------------------

local function build()
    local f = safeCreate("Frame", "MintCommunityToolsFrame", UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
    ui.frame = f
    f:SetSize(WIDTH, HEIGHT)
    f:SetPoint("CENTER")
    f:SetFrameStrata("DIALOG")
    f:SetClampedToScreen(true)
    f:EnableMouse(true)
    f:SetMovable(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    solidBackground(f, 10, 0.07)
    if f.SetBackdrop then
        pcall(f.SetBackdrop, f, {
            edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
            tile = true, tileSize = 32, edgeSize = 32,
            insets = { left = 11, right = 12, top = 12, bottom = 11 },
        })
    end
    if UISpecialFrames then table.insert(UISpecialFrames, "MintCommunityToolsFrame") end   -- Escape closes it

    local title = fontString(f, "GameFontNormalLarge")
    title:SetPoint("TOP", 0, -14)
    title:SetText("Mint Community Tools  |cff888888v" .. ns.VERSION .. "|r")
    local close = safeCreate("Button", nil, f, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -6, -6)

    -- Who
    ui.who = fontString(f, "GameFontHighlight", WIDTH - 52)
    ui.who:SetPoint("TOPLEFT", 26, -42)
    ui.guild = fontString(f, "GameFontHighlightSmall", WIDTH - 52)
    ui.guild:SetPoint("TOPLEFT", 26, -60)

    -- Gear list
    local hSlot = fontString(f, "GameFontNormalSmall", 80)
    hSlot:SetPoint("TOPLEFT", 30, -82)
    hSlot:SetText("Slot")
    local hItem = fontString(f, "GameFontNormalSmall", 280)
    hItem:SetPoint("TOPLEFT", 108, -82)
    hItem:SetText("Item")
    local hLevel = fontString(f, "GameFontNormalSmall", 44)
    hLevel:SetPoint("TOPRIGHT", -30, -82)
    hLevel:SetJustifyH("RIGHT")
    hLevel:SetText("Level")

    ui.rows = {}
    for i = 1, NUM_ROWS do
        local row = CreateFrame("Frame", nil, f)
        row:SetSize(WIDTH - 48, ROW_HEIGHT)
        row:SetPoint("TOPLEFT", 24, LIST_TOP - (i - 1) * ROW_HEIGHT)
        if i % 2 == 1 then
            local bg = row:CreateTexture(nil, "BACKGROUND")
            bg:SetAllPoints()
            if bg.SetColorTexture then bg:SetColorTexture(1, 1, 1, 0.05) else bg:SetTexture(1, 1, 1, 0.05) end
        end
        row.slot = ns.Collect.SLOTS[i]
        row.item = false
        row.slotName = fontString(row, "GameFontDisableSmall", 76)
        row.slotName:SetPoint("LEFT", 6, 0)
        row.slotName:SetText(ns.Collect.SLOT_NAMES[ns.Collect.SLOTS[i]] or "")
        row.name = fontString(row, "GameFontHighlightSmall", 290)
        row.name:SetPoint("LEFT", 84, 0)
        row.name:SetHeight(ROW_HEIGHT)
        if row.name.SetWordWrap then row.name:SetWordWrap(false) end
        row.level = fontString(row, "GameFontHighlightSmall", 40)
        row.level:SetPoint("RIGHT", -6, 0)
        row.level:SetJustifyH("RIGHT")
        row:EnableMouse(true)
        row:SetScript("OnEnter", rowEnter)
        row:SetScript("OnLeave", rowLeave)
        ui.rows[i] = row
    end

    local listBottom = LIST_TOP - NUM_ROWS * ROW_HEIGHT - 8
    ui.summary = fontString(f, "GameFontHighlightSmall", WIDTH - 52)
    ui.summary:SetPoint("TOPLEFT", 26, listBottom)
    ui.summary:SetJustifyV("TOP")
    ui.summary:SetHeight(30)

    -- Actions
    local buttonsY = listBottom - 38
    ui.rescan = button(f, "MintCommunityToolsRescanButton", "Rescan", 90, function()
        UI.Refresh()
        setStatus("Rescanned your gear.")
    end)
    ui.rescan:SetPoint("TOPLEFT", 24, buttonsY)
    ui.export = button(f, "MintCommunityToolsExportButton", "Export for website", 170, function() UI.Export(false) end)
    ui.export:SetPoint("LEFT", ui.rescan, "RIGHT", 8, 0)

    ui.hint = fontString(f, "GameFontHighlightSmall", WIDTH - 52)
    ui.hint:SetPoint("TOPLEFT", 26, buttonsY - 30)
    ui.hint:SetText("Press |cffffffffCtrl+C|r (|cffffffffCmd+C|r on a Mac) to copy the string below, then paste it on the website's "
        .. "|cffffffffRoster|r page under |cffffffffAdd or update a character|r. Do this again whenever your gear changes.")

    -- The copy box: read-only, always fully selected
    local scroll = safeCreate("ScrollFrame", "MintCommunityToolsScroll", f, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 26, buttonsY - 64)
    scroll:SetPoint("BOTTOMRIGHT", -46, 44)
    local box = CreateFrame("EditBox", "MintCommunityToolsEditBox", scroll)
    ui.editBox = box
    box:SetMultiLine(true)
    box:SetAutoFocus(false)
    box:SetFontObject(ChatFontNormal or GameFontHighlightSmall)
    box:SetWidth(WIDTH - 90)
    box:SetMaxLetters(0)
    box:SetScript("OnEscapePressed", function() f:Hide() end)
    -- Typing or pasting restores the export, but selecting and copying still work.
    box:SetScript("OnTextChanged", function(self, userInput)
        if userInput and ui.currentText and self:GetText() ~= ui.currentText then
            self:SetText(ui.currentText)
            self:HighlightText()
        end
    end)
    box:SetScript("OnEditFocusGained", function(self) self:HighlightText() end)
    scroll:SetScrollChild(box)

    ui.selectAll = button(f, "MintCommunityToolsSelectAllButton", "Select all", 100, function()
        if ui.currentText then selectAll(ui.editBox) else setStatus("Nothing to select yet. Click Export for website first.", true) end
    end)
    ui.selectAll:SetPoint("BOTTOMLEFT", 24, 14)
    ui.status = fontString(f, "GameFontHighlightSmall", WIDTH - 170)
    ui.status:SetPoint("LEFT", ui.selectAll, "RIGHT", 8, 0)
    setStatus("")

    f:SetScript("OnShow", function() UI.Refresh() end)
    f:SetScript("OnHide", function() ui.editBox:ClearFocus() end)
    f:Hide()
end

function UI.Show()
    if not ui.frame then build() end
    if ui.frame:IsShown() then
        UI.Refresh()
    else
        ui.frame:Show()   -- OnShow refreshes
    end
end

function UI.Toggle()
    if not ui.frame then build() end
    if ui.frame:IsShown() then ui.frame:Hide() else UI.Show() end
end

---------------------------------------------------------------------------
-- Minimap button
---------------------------------------------------------------------------

-- A plain button on the edge of the minimap: click opens the window, drag moves it around
-- the rim. Hand-rolled rather than LibDBIcon so the addon has no library dependencies.
function UI.CreateMinimapButton()
    if not Minimap or ui.minimap then return end
    local b = CreateFrame("Button", "MintCommunityToolsMinimapButton", Minimap)
    ui.minimap = b
    b:SetSize(31, 31)
    b:SetFrameStrata("MEDIUM")
    b:SetFrameLevel(8)
    b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    b:RegisterForDrag("LeftButton")

    local icon = b:CreateTexture(nil, "BACKGROUND")
    icon:SetTexture("Interface\\Icons\\INV_Misc_Note_01")
    icon:SetSize(20, 20)
    icon:SetPoint("CENTER")
    local border = b:CreateTexture(nil, "OVERLAY")
    border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
    border:SetSize(53, 53)
    border:SetPoint("TOPLEFT")
    b:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")

    local function place()
        local angle = math.rad((MintCommunityToolsDB and MintCommunityToolsDB.minimapAngle) or 200)
        b:ClearAllPoints()
        b:SetPoint("CENTER", Minimap, "CENTER", math.cos(angle) * 80, math.sin(angle) * 80)
    end
    place()

    b:SetScript("OnClick", function() UI.Toggle() end)
    b:SetScript("OnDragStart", function(self)
        self:SetScript("OnUpdate", function()
            local mx, my = Minimap:GetCenter()
            local cx, cy = GetCursorPosition()
            local scale = Minimap:GetEffectiveScale()
            MintCommunityToolsDB = MintCommunityToolsDB or {}
            MintCommunityToolsDB.minimapAngle = math.deg(math.atan2(cy / scale - my, cx / scale - mx))
            place()
        end)
    end)
    b:SetScript("OnDragStop", function(self) self:SetScript("OnUpdate", nil) end)
    b:SetScript("OnEnter", function(self)
        if not GameTooltip then return end
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:AddLine("Mint Community Tools")
        GameTooltip:AddLine("Click to scan your gear and export it for the website.", 1, 1, 1)
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
end
