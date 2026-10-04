--[[
    LootUI.lua - the Loot tab and the loot watcher.

    Both show the loot log (Loot.lua), newest first: the item's icon, its name in the colour
    of its quality, the name of whoever received it (your own character's name for your own
    loot, in the addon's green) and when. Hover a row for the item's own tooltip, with
    its stats. Shift-click a row to link the item in chat, as if it were in your bags;
    Ctrl-click to try it on.

      Loot tab       in the main window: the whole log with paging and a quality filter, and
                     the items seen as strings to paste on the website: Export new items
                     gives what is new since the last export, a hundred items to a string,
                     and Next part / Done says "I pasted that one".
      Loot watcher   a small window of its own for the latest drops, to leave open while
                     you play. /mint watch, or right-click the minimap button. The mouse
                     wheel scrolls it back through the last 100 drops; Latest returns to the
                     newest. While it is scrolled back, new loot does not move what you are
                     looking at.
]]

local ADDON, ns = ...
local LootUI = {}
ns.LootUI = LootUI
local W = ns.W

local ipairs, type, tostring, pcall = ipairs, type, tostring, pcall
local sformat = string.format

local WIDTH, PAD, GAP, BUTTON_H, STRIP_H, TITLE_H = W.WIDTH, W.PAD, W.GAP, W.BUTTON_H, W.STRIP_H, W.TITLE_H
local ROWS, ROW_HEIGHT = 18, 22
local WATCH_WIDTH, WATCH_ROWS, WATCH_ROW_HEIGHT = 340, 8, 20
local WATCH_MAX = 100          -- how far back the watcher scrolls; the Loot tab has the whole log
local WATCH_WHEEL = 2          -- rows per notch of the mouse wheel
local UNKNOWN_ICON = "Interface\\Icons\\INV_Misc_QuestionMark"

local FILTERS = { 0, 2, 3, 4 }
local FILTER_LABEL = { [0] = "Everything", [2] = "Uncommon and better", [3] = "Rare and better", [4] = "Epic and better" }

local lui = {}   -- the widgets, also reached by the tests as ns.lootui
ns.lootui = lui
local offset = 0   -- index of the first entry shown on the tab
local watchOffset = 0   -- the same for the watcher
local watchTop          -- the drop at the top of the watcher while it is scrolled back

local function settings()
    return ns.DB().loot
end

---------------------------------------------------------------------------
-- Rows
---------------------------------------------------------------------------

local function nameText(e)
    local color = W.QUALITY_COLOR[e.q or 1] or "ffffff"
    local text = "|cff" .. color .. (e.name or ("item " .. tostring(e.id))) .. "|r"
    if e.n and e.n > 1 then text = text .. " |cffffffffx" .. e.n .. "|r" end
    return text
end

-- Who received it, by name: your own character's in the addon's green.
local function whoText(e)
    if e.mine then return "|cff7fe5a8" .. (e.to or "You") .. "|r" end
    if e.to then return e.to end
    return "|cff888888not looted|r"
end

-- "item:16800:0:0..." from a full link; what the tooltip and the dressing room take.
local function hyperlink(link)
    return link and (link:match("|H(item:[^|]+)|h") or link) or nil
end

local function rowEnter(row)
    local e = row.entry
    if not (GameTooltip and e and e.link) then return end
    GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
    local ok = pcall(GameTooltip.SetHyperlink, GameTooltip, hyperlink(e.link))
    if not ok then GameTooltip:SetText(e.name or "", 1, 1, 1) end
    GameTooltip:AddLine(" ")
    local where = e.zone and (" in " .. e.zone) or ""
    if e.to then
        GameTooltip:AddLine(sformat("%s looted this at %s%s.", e.to, W.clock(e.at or e.t), where), 0.6, 0.6, 0.6, true)
    elseif e.mine then
        GameTooltip:AddLine(sformat("You looted this at %s%s.", W.clock(e.at or e.t), where), 0.6, 0.6, 0.6, true)
    else
        GameTooltip:AddLine(sformat("Dropped at %s%s. Nobody has looted it.", W.clock(e.t), where), 0.6, 0.6, 0.6, true)
    end
    GameTooltip:AddLine("Shift-click to link it in chat.", 0.6, 0.6, 0.6)
    GameTooltip:Show()
end

local function rowLeave()
    if GameTooltip then GameTooltip:Hide() end
end

local function modified(action, keyDown)
    if IsModifiedClick then
        local ok, yes = pcall(IsModifiedClick, action)
        if ok then return yes and true or false end
    end
    return keyDown and keyDown() and true or false
end

-- Shift-click links the item in chat, exactly as a click on an item in your bags would.
local function rowClick(row)
    local link = row.entry and row.entry.link
    if not link then return end
    if modified("CHATLINK", IsShiftKeyDown) then
        local inserted = ChatEdit_InsertLink and ChatEdit_InsertLink(link)
        if not inserted and ChatFrame_OpenChat then ChatFrame_OpenChat(link) end
    elseif modified("DRESSUP", IsControlKeyDown) then
        if DressUpItemLink then pcall(DressUpItemLink, link) end
    end
end

-- A row on a list panel (W.list): icon, name in its quality colour, who, time.
local function makeRow(list, index, width, height, nameWidth, whoWidth)
    local row = CreateFrame("Button", nil, list)
    W.listRow(list, row, index, width, height)
    row.entry = false
    if row.RegisterForClicks then row:RegisterForClicks("LeftButtonUp") end

    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetSize(height - 4, height - 4)
    row.icon:SetPoint("LEFT", 4, 0)
    if row.icon.SetTexCoord then row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92) end

    row.name = W.fontString(row, "GameFontHighlightSmall", nameWidth)
    row.name:SetPoint("LEFT", height + 6, 0)
    row.name:SetHeight(height)
    if row.name.SetWordWrap then row.name:SetWordWrap(false) end

    row.time = W.dim(row, "", 36)
    row.time:SetPoint("RIGHT", -6, 0)
    row.time:SetJustifyH("RIGHT")

    row.who = W.fontString(row, "GameFontHighlightSmall", whoWidth)
    row.who:SetPoint("RIGHT", -46, 0)
    row.who:SetJustifyH("RIGHT")
    row.who:SetHeight(height)
    if row.who.SetWordWrap then row.who:SetWordWrap(false) end

    row:SetScript("OnEnter", rowEnter)
    row:SetScript("OnLeave", rowLeave)
    row:SetScript("OnClick", rowClick)
    return row
end

local function fillRow(row, e)
    row.entry = e or false
    if not e then
        row:Hide()
        return
    end
    row.icon:SetTexture(e.icon or UNKNOWN_ICON)
    row.name:SetText(nameText(e))
    row.who:SetText(whoText(e))
    row.time:SetText(W.clock(e.at or e.t))
    row:Show()
end

---------------------------------------------------------------------------
-- The Loot tab
---------------------------------------------------------------------------

local function setStatus(text, isError)
    lui.status:SetText(text or "")
    local c = isError and W.COLOR.error or W.COLOR.dim
    lui.status:SetTextColor(c[1], c[2], c[3], c[4])
end

local function scroll(delta)
    offset = offset + delta
    LootUI.Refresh()
end

local function nextFilter()
    local s = settings()
    local at = 1
    for i, q in ipairs(FILTERS) do
        if q == s.minQuality then at = i end
    end
    s.minQuality = FILTERS[at % #FILTERS + 1]
    offset = 0
    LootUI.Refresh()
end

---------------------------------------------------------------------------
-- Exporting items for the website: one string per hundred items, a part at a time
---------------------------------------------------------------------------

local exporting   -- { parts = , index = , total = } while an export is being copied out

local function showPart()
    local part = exporting.parts[exporting.index]
    local last = exporting.index == #exporting.parts
    lui.box.Set(part.str)
    lui.confirm:SetText(last and "Done" or "Next part")
    lui.confirm:Show()
    local what = sformat("%d item%s", part.count, part.count == 1 and "" or "s")
    if #exporting.parts > 1 then what = sformat("Part %d of %d, %s", exporting.index, #exporting.parts, what) end
    setStatus(sformat("%s. Press Ctrl+C, paste it on the website's Items page, then click %s.", what, last and "Done" or "Next part"))
end

local function exportItems(all)
    local parts, total = ns.Loot.BuildExport(all)
    if total == 0 then
        exporting = nil
        lui.box.Set(nil)
        lui.confirm:Hide()
        local _, seen = ns.Loot.Counts()
        if seen == 0 then
            setStatus("No items seen yet. Loot something, or open a corpse.", true)
        else
            setStatus("Nothing new to export. Export all sends every item again.")
        end
        return
    end
    exporting = { parts = parts, index = 1, total = total }
    showPart()
end

-- The part in the box has been pasted: remember that, and move on.
local function confirmPart()
    if not exporting then return end
    ns.Loot.MarkExported(exporting.parts[exporting.index])
    if exporting.index < #exporting.parts then
        exporting.index = exporting.index + 1
        showPart()
        return
    end
    local total = exporting.total
    exporting = nil
    lui.box.Set(nil)
    lui.confirm:Hide()
    setStatus(sformat("Exported %s item%s. They wait for an officer's approval on the website.", W.commas(total), total == 1 and "" or "s"))
    LootUI.Refresh()
end

local function confirmClear()
    if StaticPopupDialogs and StaticPopup_Show then
        StaticPopupDialogs["MINTCOMMUNITYTOOLS_CLEAR_LOOT"] = StaticPopupDialogs["MINTCOMMUNITYTOOLS_CLEAR_LOOT"] or {
            text = "Clear the loot log? The items seen are kept for the website's item database.",
            button1 = YES or "Yes",
            button2 = NO or "No",
            OnAccept = function() ns.Loot.Clear() end,
            timeout = 0, whileDead = true, hideOnEscape = true,
        }
        StaticPopup_Show("MINTCOMMUNITYTOOLS_CLEAR_LOOT")
    else
        ns.Loot.Clear()
    end
end

-- Lays the Loot tab out top to bottom; returns the height the panel needs.
function LootUI.Build(panel, frame)
    lui.panel = panel
    local CW = WIDTH - 2 * PAD   -- content width
    local y = -2

    lui.filter = W.button(panel, "MintCommunityToolsLootFilterButton", "", 170, nextFilter)
    lui.filter:SetPoint("TOPLEFT", PAD, y)
    lui.count = W.dim(panel, "", CW - 170 - 6)
    lui.count:SetPoint("LEFT", lui.filter, "RIGHT", 6, 0)
    y = y - BUTTON_H - GAP

    local strip = W.strip(panel, y)
    local hItem = W.header(strip, "Item")
    hItem:SetPoint("LEFT", strip, "LEFT", ROW_HEIGHT + 4, 0)
    hItem:SetWidth(200)
    hItem:SetJustifyH("LEFT")
    local hWho = W.header(strip, "Looted by")
    hWho:SetPoint("RIGHT", strip, "RIGHT", -46, 0)
    hWho:SetWidth(120)
    hWho:SetJustifyH("RIGHT")
    local hTime = W.header(strip, "Time")
    hTime:SetPoint("RIGHT", strip, "RIGHT", -4, 0)
    hTime:SetWidth(40)
    hTime:SetJustifyH("RIGHT")
    y = y - STRIP_H

    local list = W.list(panel, y, ROWS, ROW_HEIGHT)
    lui.list = list
    lui.rows = {}
    for i = 1, ROWS do
        lui.rows[i] = makeRow(list, i, CW, ROW_HEIGHT, 230, 120)
    end
    lui.empty = W.dim(list, "", CW - 40)
    lui.empty:SetPoint("TOP", list, "TOP", 0, -60)
    lui.empty:SetJustifyH("CENTER")
    y = y + 1 - (ROWS * ROW_HEIGHT + 4) - GAP

    panel:EnableMouseWheel(true)
    panel:SetScript("OnMouseWheel", function(_, delta)
        if type(delta) == "number" then scroll(-delta * 3) end
    end)

    lui.page = W.dim(panel, "", 200)
    lui.page:SetPoint("TOPLEFT", PAD, y - 4)
    lui.next = W.button(panel, "MintCommunityToolsLootNextButton", ">", 24, function() scroll(ROWS) end)
    lui.next:SetPoint("TOPRIGHT", -PAD, y)
    lui.prev = W.button(panel, "MintCommunityToolsLootPrevButton", "<", 24, function() scroll(-ROWS) end)
    lui.prev:SetPoint("RIGHT", lui.next, "LEFT", -2, 0)
    y = y - BUTTON_H - GAP

    lui.watch = W.button(panel, "MintCommunityToolsLootWatchButton", "Show loot watcher", 130, function() LootUI.ToggleWatch() end)
    lui.watch:SetPoint("TOPLEFT", PAD, y)
    lui.exportNew = W.button(panel, "MintCommunityToolsLootExportButton", "Export new items", 120, function() exportItems(false) end)
    lui.exportNew:SetPoint("LEFT", lui.watch, "RIGHT", GAP, 0)
    lui.exportAll = W.button(panel, "MintCommunityToolsLootExportAllButton", "Export all", 80, function() exportItems(true) end)
    lui.exportAll:SetPoint("LEFT", lui.exportNew, "RIGHT", GAP, 0)
    lui.clear = W.button(panel, "MintCommunityToolsLootClearButton", "Clear", 56, confirmClear)
    lui.clear:SetPoint("LEFT", lui.exportAll, "RIGHT", GAP, 0)
    y = y - BUTTON_H - GAP

    lui.hint = W.dim(panel, "", CW)
    lui.hint:SetPoint("TOPLEFT", PAD, y)
    lui.hint:SetJustifyV("TOP")
    lui.hint:SetHeight(26)
    y = y - 26 - GAP

    -- The copy box takes what is left above the bottom row of controls.
    local bottomRow = PAD + BUTTON_H + GAP
    lui.box = W.copyBox(panel, "MintCommunityToolsLoot", PAD, y, -PAD, bottomRow, function() frame:Hide() end)
    lui.selectAll = W.button(panel, "MintCommunityToolsLootSelectAllButton", "Select all", 90, function()
        if lui.box.text then lui.box.SelectAll() else setStatus("Nothing to select yet. Click Export new items first.", true) end
    end)
    lui.selectAll:SetPoint("BOTTOMLEFT", PAD, PAD)
    lui.confirm = W.button(panel, "MintCommunityToolsLootConfirmButton", "Done", 90, confirmPart)
    lui.confirm:SetPoint("LEFT", lui.selectAll, "RIGHT", GAP, 0)
    lui.confirm:Hide()
    lui.status = W.fontString(panel, "GameFontHighlightSmall", CW - 2 * 90 - GAP - 6)
    lui.status:SetPoint("LEFT", lui.confirm, "RIGHT", 6, 0)
    setStatus("")

    return -y + W.MIN_BOX_H + bottomRow
end

local function refreshTab()
    if not lui.panel then return end
    local s = settings()
    local list = ns.Loot.Entries(s.minQuality)
    local total = ns.Loot.Counts()
    if offset > #list - ROWS then offset = #list - ROWS end
    if offset < 0 then offset = 0 end

    for i, row in ipairs(lui.rows) do fillRow(row, list[offset + i]) end

    lui.filter:SetText("Showing: " .. (FILTER_LABEL[s.minQuality] or FILTER_LABEL[0]))
    if #list == total then
        lui.count:SetText(sformat("%s drop%s", W.commas(total), total == 1 and "" or "s"))
    else
        lui.count:SetText(sformat("%s of %s drops", W.commas(#list), W.commas(total)))
    end
    if #list > ROWS then
        lui.page:SetText(sformat("%d-%d of %d", offset + 1, math.min(offset + ROWS, #list), #list))
    else
        lui.page:SetText("")
    end
    if offset > 0 then lui.prev:Enable() else lui.prev:Disable() end
    if offset + ROWS < #list then lui.next:Enable() else lui.next:Disable() end
    if #list == 0 then
        lui.empty:SetText(total == 0 and "Nothing has dropped yet.\nLoot shows up here as you and your group find it."
            or "Nothing of that quality has dropped.")
        lui.empty:Show()
    else
        lui.empty:Hide()
    end
    lui.watch:SetText(s.watch and "Hide loot watcher" or "Show loot watcher")
    local pending = ns.Loot.PendingCount()
    lui.hint:SetText("Hover an item for its tooltip. |cffffffffShift-click|r links it in chat.\n"
        .. (pending == 0 and "No new items to export for the website's item database."
            or sformat("|cffffffff%s new item%s|r to export for the website's item database.", W.commas(pending), pending == 1 and "" or "s")))
end

---------------------------------------------------------------------------
-- The loot watcher
---------------------------------------------------------------------------

local function refreshWatch()
    local f = lui.watchFrame
    if not (f and f:IsShown()) then return end
    local list = ns.Loot.Entries(settings().minQuality)
    local count = math.min(#list, WATCH_MAX)

    -- Scrolled back: stay on the same drops as new ones arrive above them.
    if watchOffset > 0 and watchTop then
        for i = 1, count do
            if list[i] == watchTop then watchOffset = i - 1 break end
        end
    end
    if watchOffset > count - WATCH_ROWS then watchOffset = count - WATCH_ROWS end
    if watchOffset < 0 then watchOffset = 0 end
    watchTop = watchOffset > 0 and list[watchOffset + 1] or nil

    for i, row in ipairs(lui.watchRows) do
        fillRow(row, watchOffset + i <= count and list[watchOffset + i] or nil)
    end
    if count > WATCH_ROWS then
        lui.watchPosition:SetText(sformat("%d-%d of %d", watchOffset + 1, watchOffset + WATCH_ROWS, count))
    else
        lui.watchPosition:SetText("")
    end
    if watchOffset > 0 then lui.watchLatest:Show() else lui.watchLatest:Hide() end
    if count == 0 then lui.watchEmpty:Show() else lui.watchEmpty:Hide() end
end

local function scrollWatch(rows)
    watchOffset = watchOffset + rows
    watchTop = nil   -- the wheel decides where the view is, not the drop that was on top
    if GameTooltip then GameTooltip:Hide() end   -- the row under the pointer is about to change
    refreshWatch()
end

local function buildWatch()
    local listHeight = WATCH_ROWS * WATCH_ROW_HEIGHT + 4
    local height = TITLE_H + GAP + listHeight + PAD
    local f = W.window("MintCommunityToolsLootWatch", WATCH_WIDTH, height, "MEDIUM", "Loot")
    lui.watchFrame = f

    local pos = settings().watchAt
    if type(pos) == "table" and type(pos[1]) == "string" and type(pos[2]) == "number" and type(pos[3]) == "number" then
        f:ClearAllPoints()
        f:SetPoint(pos[1], UIParent, pos[1], pos[2], pos[3])
    end
    f:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local point, _, _, x, y = self:GetPoint()
        if type(point) == "string" and type(x) == "number" and type(y) == "number" then
            settings().watchAt = { point, x, y }
        end
    end)
    -- Closing it with its own X is turning it off, so it stays off at the next login.
    f.close:SetScript("OnClick", function() LootUI.SetWatchShown(false) end)

    -- The title strip: "Loot", where the view is while scrolled back, and Latest.
    lui.watchPosition = f.subtitle
    lui.watchLatest = W.button(f.titleBar, "MintCommunityToolsLootWatchLatestButton", "Latest", 50, function()
        watchOffset = 0
        scrollWatch(0)
    end)
    lui.watchLatest:SetHeight(TITLE_H - 4)
    lui.watchLatest:SetPoint("RIGHT", f.close, "LEFT", -2, 0)
    lui.watchLatest:Hide()

    -- The wheel over a row reaches the window: rows do not take the wheel themselves.
    f:EnableMouseWheel(true)
    f:SetScript("OnMouseWheel", function(_, delta)
        if type(delta) == "number" then scrollWatch(-delta * WATCH_WHEEL) end
    end)

    -- W.list sits 1px above the y it is given (to share a header strip's border); there is
    -- no strip here, so hand it 1px lower and the list starts a GAP under the title strip.
    local list = W.list(f, -(TITLE_H + GAP) - 1, WATCH_ROWS, WATCH_ROW_HEIGHT)
    lui.watchList = list
    lui.watchRows = {}
    for i = 1, WATCH_ROWS do
        lui.watchRows[i] = makeRow(list, i, WATCH_WIDTH - 2 * PAD, WATCH_ROW_HEIGHT, 170, 84)
    end
    lui.watchEmpty = W.dim(list, "Nothing has dropped yet.", WATCH_WIDTH - 60)
    lui.watchEmpty:SetPoint("CENTER", list, "CENTER", 0, 0)
    lui.watchEmpty:SetJustifyH("CENTER")
    f:Hide()
end

function LootUI.SetWatchShown(shown)
    settings().watch = shown and true or false
    if shown then
        if not lui.watchFrame then buildWatch() end
        watchOffset, watchTop = 0, nil   -- it opens on the newest drops
        lui.watchFrame:Show()
    elseif lui.watchFrame then
        lui.watchFrame:Hide()
    end
    LootUI.Refresh()
end

function LootUI.ToggleWatch()
    LootUI.SetWatchShown(not settings().watch)
end

-- Called at login, once the settings are in place.
function LootUI.InitWatch()
    if settings().watch then LootUI.SetWatchShown(true) end
end

---------------------------------------------------------------------------
-- Refresh: both views
---------------------------------------------------------------------------

function LootUI.Refresh()
    if lui.panel and ns.ui.frame and ns.ui.frame:IsShown() and ns.UI.CurrentTab() == "loot" then refreshTab() end
    refreshWatch()
end

-- Opens the main window on the Loot tab and starts an export: what is new, or everything.
function LootUI.ExportItems(all)
    ns.UI.Show("loot")
    exportItems(all)
end
