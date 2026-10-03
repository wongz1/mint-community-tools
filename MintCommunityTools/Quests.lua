--[[
    Quests.lua - the quest tracker: the quests you are tracking and what is left to do in
    each, as a plain list of the addon's own.

    A flat header strip ("Quests", and how many are tracked) with the list under it:
      - each quest's title, in the colour of its difficulty, with its level in front
        (the settings can leave the level out);
      - under it, its objectives: what is still to do in the text colour, what is done
        dimmed; "Ready to turn in" once the whole quest is complete, "Failed" if it failed.
    Click the header to fold the list away or bring it back. Click a quest to open it in
    the quest log; shift-click it to stop tracking it. The list sits on a mover, with an
    optional backdrop behind it, and stops growing at a set height ("+3 more" says what did
    not fit).

    The game's own tracker (ObjectiveTrackerFrame on a newer client, QuestWatchFrame on an
    older one) is hidden while this is on. What that also hides: anything else the game
    shows in its tracker besides quests, and its buttons for quest items. The game puts its
    tracker back where it keeps such frames some time after login (when its own edit mode
    layout arrives), so hiding it once is not enough: Quests.Check looks once a second, and
    whenever the quest log changes, and hides it again if it has been taken back.

    Which quests are tracked is the game's own list; this only draws it. Both ways of asking
    are supported: C_QuestLog on a newer client, GetNumQuestWatches and GetQuestLogTitle on
    an older one. Everything is feature-detected and run under pcall, and nothing read from
    the game is compared or counted without checking it is not a secret value first.
]]

local ADDON, ns = ...
local Quests = {}
ns.Quests = Quests

local ipairs, type, tostring, pcall = ipairs, type, tostring, pcall
local floor = math.floor

local HEADER_H = 18
local LINE = 14          -- one line of small text
local INDENT = 10        -- objectives sit in from the title
local QUEST_GAP = 4
local BLIZZARD = { "ObjectiveTrackerFrame", "QuestWatchFrame", "WatchFrame" }
local EVENTS = {
    "QUEST_LOG_UPDATE", "QUEST_WATCH_LIST_CHANGED", "QUEST_WATCH_UPDATE", "QUEST_ACCEPTED", "QUEST_REMOVED",
    "QUEST_TURNED_IN", "UNIT_QUEST_LOG_CHANGED", "PLAYER_ENTERING_WORLD", "PLAYER_LEVEL_UP", "EDIT_MODE_LAYOUTS_UPDATED",
}
local DONE = { 0.35, 0.85, 0.35 }
local FAILED = { 0.9, 0.3, 0.3 }

local ui = { titles = {}, lines = {} }     -- the widgets, also reached by the tests
Quests.ui = ui

local function settings()
    return ns.Overhaul.Settings().quests
end

local function frame(name)
    local f = _G[name]
    return type(f) == "table" and f or nil
end

local function isSecret(v)
    return issecretvalue ~= nil and issecretvalue(v) == true
end

-- A plain true or false out of what the game returned; a secret value counts as false.
local function flag(v)
    if isSecret(v) then return false end
    return v and true or false
end

-- Text there is something to show of: a secret string may be shown though not read.
local function hasText(s)
    return type(s) == "string" and (isSecret(s) or s ~= "")
end

local function call(fn, ...)
    if type(fn) ~= "function" then return nil end
    local ok, a, b, c, d, e, f, g, h = pcall(fn, ...)
    if ok then return a, b, c, d, e, f, g, h end
    return nil
end

---------------------------------------------------------------------------
-- The tracked quests
---------------------------------------------------------------------------

-- "modern" (C_QuestLog), "classic" (GetNumQuestWatches), or nil when this client has neither.
function Quests.Source()
    if type(C_QuestLog) == "table" and type(C_QuestLog.GetNumQuestWatches) == "function"
        and type(C_QuestLog.GetQuestIDForQuestWatchIndex) == "function" then
        return "modern"
    end
    if type(GetNumQuestWatches) == "function" and type(GetQuestIndexForWatch) == "function" and type(GetQuestLogTitle) == "function" then
        return "classic"
    end
    return nil
end

local function modernList()
    local Q = C_QuestLog
    local out = {}
    local n = call(Q.GetNumQuestWatches)
    if type(n) ~= "number" or isSecret(n) then return out end
    for i = 1, n do
        local id = call(Q.GetQuestIDForQuestWatchIndex, i)
        if type(id) == "number" and not isSecret(id) then
            local q = { id = id, index = false, level = false, objectives = {} }
            q.title = call(Q.GetTitleForQuestID, id)
            local index = call(Q.GetLogIndexForQuestID, id)
            if type(index) == "number" and not isSecret(index) then
                q.index = index
                local info = call(Q.GetInfo, index)
                if type(info) == "table" and not isSecret(info) then
                    if type(info.level) == "number" then q.level = info.level end
                    if not hasText(q.title) then q.title = info.title end
                end
            end
            if not q.level then
                local level = call(Q.GetQuestDifficultyLevel, id)
                if type(level) == "number" then q.level = level end
            end
            q.complete = flag(call(Q.IsComplete, id))
            q.failed = flag(call(Q.IsFailed, id))
            local objectives = call(Q.GetQuestObjectives, id)
            if type(objectives) == "table" and not isSecret(objectives) then
                for _, o in ipairs(objectives) do
                    if type(o) == "table" and hasText(o.text) then
                        q.objectives[#q.objectives + 1] = { text = o.text, done = flag(o.finished) }
                    end
                end
            end
            if hasText(q.title) then out[#out + 1] = q end
        end
    end
    return out
end

local function classicList()
    local out = {}
    local n = call(GetNumQuestWatches)
    if type(n) ~= "number" then return out end
    for i = 1, n do
        local index = call(GetQuestIndexForWatch, i)
        if type(index) == "number" and index > 0 then
            -- title, level, tag, isHeader, isCollapsed, isComplete, frequency, questID
            local title, level, _, isHeader, _, isComplete, _, id = call(GetQuestLogTitle, index)
            if hasText(title) and not flag(isHeader) then
                local q = { id = type(id) == "number" and id or false, index = index, title = title,
                            level = type(level) == "number" and level or false, objectives = {} }
                q.complete = isComplete == 1 or isComplete == true
                q.failed = isComplete == -1
                local count = call(GetNumQuestLeaderBoards, index)
                if type(count) == "number" then
                    for j = 1, count do
                        local text, _, finished = call(GetQuestLogLeaderBoard, j, index)
                        if hasText(text) then q.objectives[#q.objectives + 1] = { text = text, done = flag(finished) } end
                    end
                end
                out[#out + 1] = q
            end
        end
    end
    return out
end

-- The tracked quests, in the game's order: { id, index, title, level, complete, failed,
-- objectives = { { text, done }, ... } }.
function Quests.List()
    local source = Quests.Source()
    if source == "modern" then return modernList() end
    if source == "classic" then return classicList() end
    return {}
end

---------------------------------------------------------------------------
-- Clicking a quest
---------------------------------------------------------------------------

function Quests.Open(q)
    if type(q) ~= "table" then return false end
    if q.id and type(QuestMapFrame_OpenToQuestDetails) == "function" and pcall(QuestMapFrame_OpenToQuestDetails, q.id) then
        return true
    end
    if q.index and type(QuestLog_SetSelection) == "function" then
        local log = frame("QuestLogFrame")
        if log and type(ToggleQuestLog) == "function" and not flag(call(log.IsShown, log)) then pcall(ToggleQuestLog) end
        pcall(QuestLog_SetSelection, q.index)
        if type(QuestLog_Update) == "function" then pcall(QuestLog_Update) end
        return true
    end
    if type(ToggleQuestLog) == "function" then return pcall(ToggleQuestLog) end
    return false
end

function Quests.Untrack(q)
    if type(q) ~= "table" then return false end
    local done = false
    if q.id and type(C_QuestLog) == "table" and type(C_QuestLog.RemoveQuestWatch) == "function" then
        done = pcall(C_QuestLog.RemoveQuestWatch, q.id)
    elseif q.index and type(RemoveQuestWatch) == "function" then
        done = pcall(RemoveQuestWatch, q.index)
        if type(QuestWatch_Update) == "function" then pcall(QuestWatch_Update) end
    end
    Quests.Refresh()
    return done
end

---------------------------------------------------------------------------
-- Drawing
---------------------------------------------------------------------------

local function colorHex(c)
    return ("%02x%02x%02x"):format(floor(c[1] * 255 + 0.5), floor(c[2] * 255 + 0.5), floor(c[3] * 255 + 0.5))
end

-- "[12] The Jasperlode Mine" in the colour of the quest's difficulty.
function Quests.TitleText(q)
    local s = settings()
    local text = q.title
    if s.levels and type(q.level) == "number" then
        local ok, withLevel = pcall(string.format, "[%d] %s", q.level, q.title)
        if ok then text = withLevel end
    end
    local c
    if type(q.level) == "number" and not isSecret(q.level) then c = call(GetQuestDifficultyColor, q.level) end
    if type(c) == "table" and type(c.r) == "number" then
        local ok, colored = pcall(string.format, "|cff%s%s|r", colorHex({ c.r, c.g, c.b }), text)
        if ok then return colored end
    end
    return text
end

local function titleEnter(self)
    if not (GameTooltip and self.quest) then return end
    GameTooltip:SetOwner(self, "ANCHOR_LEFT")
    pcall(GameTooltip.SetText, GameTooltip, self.quest.title, 1, 0.82, 0)
    GameTooltip:AddLine("Click: open it in the quest log", 0.6, 0.6, 0.6)
    GameTooltip:AddLine("Shift-click: stop tracking it", 0.6, 0.6, 0.6)
    GameTooltip:Show()
end

local function titleLeave()
    if GameTooltip then GameTooltip:Hide() end
end

local function titleClick(self)
    if not self.quest then return end
    if IsShiftKeyDown and IsShiftKeyDown() then Quests.Untrack(self.quest) else Quests.Open(self.quest) end
end

local function titleRow(i)
    local row = ui.titles[i]
    if row then return row end
    local W = ns.W
    row = W.safeCreate("Button", nil, ui.body)
    row:SetHeight(LINE)
    row.text = W.fontString(row, "GameFontHighlightSmall")
    row.text:SetPoint("LEFT", row, "LEFT", 0, 0)
    row.text:SetPoint("RIGHT", row, "RIGHT", 0, 0)
    if row.text.SetWordWrap then row.text:SetWordWrap(false) end
    row.quest = false
    row:SetScript("OnClick", titleClick)
    row:SetScript("OnEnter", titleEnter)
    row:SetScript("OnLeave", titleLeave)
    ui.titles[i] = row
    return row
end

local function line(i)
    local fs = ui.lines[i]
    if fs then return fs end
    fs = ns.W.fontString(ui.body, "GameFontHighlightSmall")
    if fs.SetWordWrap then fs:SetWordWrap(true) end
    if fs.SetJustifyV then fs:SetJustifyV("TOP") end
    ui.lines[i] = fs
    return fs
end

-- Puts a line of text at `y` under the title and returns how tall it came out.
local function placeLine(n, text, color, y, width)
    local fs = line(n)
    fs:ClearAllPoints()
    fs:SetPoint("TOPLEFT", ui.body, "TOPLEFT", INDENT, y)
    fs:SetWidth(width - INDENT)
    pcall(fs.SetText, fs, text)
    fs:SetTextColor(color[1], color[2], color[3], 1)
    fs:Show()
    local h = fs.GetStringHeight and fs:GetStringHeight()
    if type(h) ~= "number" or h < LINE then h = LINE end
    return h
end

local function build()
    local W = ns.W
    local s = settings()
    ui.frame = W.safeCreate("Frame", "MintCommunityToolsQuestTracker", UIParent)
    ui.frame:SetFrameStrata("LOW")

    ui.backdrop = W.panel(ui.frame, W.COLOR.window)
    ui.backdrop:SetAllPoints(ui.frame)
    ui.backdrop:Hide()

    ui.header = W.safeCreate("Button", "MintCommunityToolsQuestHeader", ui.frame, W.template())
    W.skin(ui.header, W.COLOR.panel)
    ui.header:SetPoint("TOPLEFT", ui.frame, "TOPLEFT", 0, 0)
    ui.header:SetPoint("TOPRIGHT", ui.frame, "TOPRIGHT", 0, 0)
    ui.header:SetHeight(HEADER_H)
    ui.title = W.header(ui.header, "Quests")
    ui.title:SetPoint("LEFT", ui.header, "LEFT", 4, 0)
    ui.count = W.dim(ui.header, "")
    ui.count:SetPoint("RIGHT", ui.header, "RIGHT", -4, 0)
    ui.header:SetScript("OnClick", function()
        local st = settings()
        st.collapsed = not st.collapsed
        Quests.Refresh()
    end)
    ui.header:SetScript("OnEnter", function(self)
        W.setBorder(self, W.accent())
        if not GameTooltip then return end
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:SetText("Quests", 1, 0.82, 0)
        GameTooltip:AddLine("Click: fold the list away or bring it back", 0.6, 0.6, 0.6)
        GameTooltip:Show()
    end)
    ui.header:SetScript("OnLeave", function(self)
        local b = W.COLOR.border
        W.setBorder(self, b[1], b[2], b[3], b[4])
        if GameTooltip then GameTooltip:Hide() end
    end)

    ui.body = CreateFrame("Frame", nil, ui.frame)
    ui.body:SetPoint("TOPLEFT", ui.header, "BOTTOMLEFT", 4, -3)
    ui.body:SetPoint("TOPRIGHT", ui.header, "BOTTOMRIGHT", -4, -3)
    ui.body:SetHeight(1)

    -- The game tells of a change to the quest log several times over; the list is drawn
    -- again once, a moment later.
    ui.dirty, ui.elapsed, ui.sinceCheck = false, 0, 0
    for _, ev in ipairs(EVENTS) do pcall(ui.frame.RegisterEvent, ui.frame, ev) end
    ui.frame:SetScript("OnEvent", function() ui.dirty = true end)
    ui.frame:SetScript("OnUpdate", function(_, dt)
        dt = type(dt) == "number" and dt or 0
        -- Once a second: has the game taken its own tracker back?
        ui.sinceCheck = ui.sinceCheck + dt
        if ui.sinceCheck >= 1 then
            ui.sinceCheck = 0
            Quests.Check()
        end
        if not ui.dirty then return end
        ui.elapsed = ui.elapsed + dt
        if ui.elapsed < 0.1 then return end
        Quests.Refresh()
    end)
    ui.frame:SetSize(s.width, HEADER_H)
end

-- Draws the list from the game's tracked quests.
function Quests.Refresh()
    if not ui.frame then return end
    local W = ns.W
    local s = settings()
    ui.dirty, ui.elapsed = false, 0
    Quests.Check()
    local width = s.width
    local inner = width - 8
    local mover = ns.Overhaul.Mover("quests", "Quest tracker", width, 120)
    ui.frame:ClearAllPoints()
    ui.frame:SetPoint("TOPLEFT", mover, "TOPLEFT", 0, 0)

    local list = Quests.List()
    ui.list = list
    pcall(ui.count.SetText, ui.count, s.collapsed and (#list .. " tracked, folded") or (#list .. " tracked"))

    local titles, lines, y, shown = 0, 0, 0, 0
    if not s.collapsed then
        for i, q in ipairs(list) do
            -- Would this quest run past the height the list may take? Say how many are left out.
            local need = LINE + math.max(1, #q.objectives) * LINE
            if shown > 0 and -y + need > s.maxHeight then
                lines = lines + 1
                y = y - placeLine(lines, ("+%d more"):format(#list - shown), W.COLOR.dim, y, inner + INDENT) - QUEST_GAP
                break
            end
            titles = titles + 1
            local row = titleRow(titles)
            row.quest = q
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", ui.body, "TOPLEFT", 0, y)
            row:SetWidth(inner)
            pcall(row.text.SetText, row.text, Quests.TitleText(q))
            row:Show()
            y = y - LINE
            if q.failed then
                lines = lines + 1
                y = y - placeLine(lines, "Failed", FAILED, y, inner)
            elseif q.complete then
                lines = lines + 1
                y = y - placeLine(lines, "Ready to turn in", DONE, y, inner)
            else
                for _, o in ipairs(q.objectives) do
                    lines = lines + 1
                    y = y - placeLine(lines, o.text, o.done and W.COLOR.dim or W.COLOR.text, y, inner)
                end
            end
            y = y - QUEST_GAP
            shown = shown + 1
        end
        if #list == 0 then
            lines = lines + 1
            y = y - placeLine(lines, "Nothing tracked. Track a quest from the quest log.", W.COLOR.dim, y, inner + INDENT) - QUEST_GAP
        end
    end
    for i = titles + 1, #ui.titles do
        ui.titles[i].quest = false
        ui.titles[i]:Hide()
    end
    for i = lines + 1, #ui.lines do ui.lines[i]:Hide() end
    ui.shownQuests, ui.shownLines = shown, lines

    local bodyH = -y
    ui.body:SetHeight(bodyH > 0 and bodyH or 1)
    if s.collapsed then ui.body:Hide() else ui.body:Show() end
    ui.frame:SetSize(width, HEADER_H + (bodyH > 0 and bodyH + 3 or 0))
    if s.background and not s.collapsed then ui.backdrop:Show() else ui.backdrop:Hide() end
    ui.frame:Show()
end

---------------------------------------------------------------------------
-- The overhaul's hooks
---------------------------------------------------------------------------

local function hideBlizzard()
    Quests.hidden = 0
    for _, name in ipairs(BLIZZARD) do
        if ns.Overhaul.HideBlizzard(frame(name)) then Quests.hidden = Quests.hidden + 1 end
    end
end

-- Is the game's own tracker still where it was put (under the hidden frame)? If the game has
-- taken it back, it is hidden again. Returns how many frames had to be. Not in combat: the
-- game may not let its tracker be moved then; the next look after combat does it.
function Quests.Check()
    if not Quests.applied then return 0 end
    if InCombatLockdown and InCombatLockdown() then return 0 end
    local hider = ns.Overhaul.hider
    local fixed = 0
    for _, name in ipairs(BLIZZARD) do
        local f = frame(name)
        if f and type(f.GetParent) == "function" then
            local ok, parent = pcall(f.GetParent, f)
            if ok and parent ~= hider then
                ns.Overhaul.HideBlizzard(f)
                fixed = fixed + 1
            end
        end
    end
    return fixed
end

function Quests.Apply()
    if not Quests.Source() then error("this client has no list of tracked quests the addon can read") end
    if not ui.frame then build() end
    ns.Overhaul.Mover("quests", "Quest tracker", settings().width, 120, { "TOPRIGHT", -20, -270 })
    hideBlizzard()
    Quests.applied = true
    Quests.Refresh()
end

function Quests.OnEnteringWorld()
    Quests.Refresh()
end

function Quests.OnSettingsChanged(path)
    if path:match("^quests%.") then Quests.Refresh() end
end
