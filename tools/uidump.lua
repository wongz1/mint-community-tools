--[[
    tools/uidump.lua - reads what /mint uidump recorded, out of the game's save file.

        luajit tools/uidump.lua list                         each group recorded: when, on which build
        luajit tools/uidump.lua show <group> [root] [depth]  a group's frames as a tree (one root, or all)
        luajit tools/uidump.lua keep <group>                 copy the group into tools/dumps/<group>-<build>.lua
        luajit tools/uidump.lua diff <group> <kept file>     what changed since that copy: frames added, gone,
                                                             resized, moved, re-anchored, or with other art
        luajit tools/uidump.lua art <group> [root] [depth]   the game's own pictures still showing under a root:
                                                             what the flat skin has not reached (its own
                                                             plain textures are left out)
    A record taken with a name (/mint uidump menus gameplay) is the group "menus:gameplay".
        --save <path>   the save file (default: MintCommunityTools/Saved.lua, the link to the game's)

    The flow after a client update: in the game, open the windows and type /mint uidump all,
    then /reload; here, "diff" each group against the copy kept from the previous build, fix
    what moved, then "keep" the new copies.
]]

local args = { ... }
local save = "MintCommunityTools/Saved.lua"
local rest = {}
local i = 1
while i <= #args do
    if args[i] == "--save" then
        save = args[i + 1]
        i = i + 2
    else
        rest[#rest + 1] = args[i]
        i = i + 1
    end
end
local cmd, group, arg3, arg4 = rest[1], rest[2], rest[3], rest[4]

local function usage()
    io.stderr:write("usage: luajit tools/uidump.lua [--save file] list | show <group> [root] [depth] | art <group> [root] [depth] | keep <group> | diff <group> <kept file>\n")
    os.exit(2)
end

local function load(path)
    local chunk, err = loadfile(path)
    if not chunk then
        io.stderr:write("cannot read " .. tostring(path) .. ": " .. tostring(err) .. "\n")
        os.exit(1)
    end
    local env = setmetatable({}, { __index = _G })
    setfenv(chunk, env)
    chunk()
    return env
end

local function dumps(db)
    local all = {}
    if type(db.uiDumps) == "table" then
        for k, v in pairs(db.uiDumps) do all[k] = v end
    end
    if type(db.uiDump) == "table" and db.uiDump.group and not all[db.uiDump.group] then all[db.uiDump.group] = db.uiDump end
    return all
end

local function r(v)
    if type(v) == "number" then return tostring(math.floor(v * 10 + 0.5) / 10) end
    return tostring(v)
end

local function label(n)
    return n.name or (n.key and "." .. n.key) or "(anon)"
end

local function regionLine(t)
    return ("~ %s %s%s %sx%s layer=%s atlas=%s tex=%s%s a=%s @%s"):format(t.type or "?", label(t), t.shown and "" or " HID", r(t.w), r(t.h),
        tostring(t.layer), tostring(t.atlas), tostring(t.texture), t.text and (" text=" .. tostring(t.text)) or "", tostring(t.alpha), tostring(t.point))
end

local function show(n, indent, depth)
    print(("%s%s [%s]%s %sx%s @%s lvl=%s strata=%s mouse=%s a=%s"):format(indent, label(n), n.type or "?", n.shown and "" or " HID",
        r(n.w), r(n.h), tostring(n.point), tostring(n.level), tostring(n.strata), tostring(n.mouse), tostring(n.alpha)))
    for _, t in ipairs(n.regions or {}) do print(indent .. "   " .. regionLine(t)) end
    if depth > 0 then
        for _, c in ipairs(n.children or {}) do show(c, indent .. "  ", depth - 1) end
    end
end

-- Every frame in a group as path -> a line that says what it is; textures summed up on
-- their frame, so that a changed atlas shows as a change to that frame.
local function flatten(d)
    local out = {}
    local function walk(n, path)
        local arts = {}
        for _, t in ipairs(n.regions or {}) do
            arts[#arts + 1] = (t.atlas or t.texture or (t.type == "FontString" and "text") or "?") .. (t.shown == false and "(hid)" or "")
        end
        table.sort(arts)
        out[path] = ("%s %sx%s @%s%s [%s]"):format(n.type or "?", r(n.w), r(n.h), tostring(n.point), n.shown and "" or " HID", table.concat(arts, " "))
        local seen = {}
        for _, c in ipairs(n.children or {}) do
            local name = label(c)
            seen[name] = (seen[name] or 0) + 1
            walk(c, path .. "/" .. name .. (seen[name] > 1 and ("#" .. seen[name]) or ""))
        end
    end
    local roots = {}
    for name in pairs(d.frames or {}) do roots[#roots + 1] = name end
    table.sort(roots)
    for _, name in ipairs(roots) do
        local n = d.frames[name]
        if n.error then out[name] = "error " .. tostring(n.error) else walk(n, name) end
    end
    return out
end

local function serialize(v, indent)
    local t = type(v)
    if t == "string" then return ("%q"):format(v) end
    if t == "number" or t == "boolean" then return tostring(v) end
    if t ~= "table" then return "nil" end
    local pad = indent .. "  "
    local parts = {}
    local n = #v
    for k = 1, n do parts[#parts + 1] = pad .. serialize(v[k], pad) end
    local keys = {}
    for k in pairs(v) do
        if not (type(k) == "number" and k >= 1 and k <= n and k == math.floor(k)) then keys[#keys + 1] = k end
    end
    table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
    for _, k in ipairs(keys) do
        local key = type(k) == "string" and k:match("^[%a_][%w_]*$") and k or ("[" .. serialize(k, "") .. "]")
        parts[#parts + 1] = pad .. key .. " = " .. serialize(v[k], pad)
    end
    if #parts == 0 then return "{}" end
    return "{\n" .. table.concat(parts, ",\n") .. "\n" .. indent .. "}"
end

if cmd == "list" then
    local db = load(save).MintCommunityToolsDB
    if not db then io.stderr:write("no MintCommunityToolsDB in " .. save .. "\n") os.exit(1) end
    local all = dumps(db)
    local names = {}
    for k in pairs(all) do names[#names + 1] = k end
    table.sort(names)
    if #names == 0 then print("nothing recorded: type /mint uidump all in the game, then /reload") end
    for _, name in ipairs(names) do
        local d = all[name]
        local roots = 0
        for _ in pairs(d.frames or {}) do roots = roots + 1 end
        print(("%-8s %s  build %s (%s)  addon %s  %d roots, %d frames and textures, %d missing"):format(name,
            os.date("%Y-%m-%d %H:%M", d.at or 0), tostring(d.build), tostring(d.version), tostring(d.addon), roots, d.count or 0, #(d.missing or {})))
    end
elseif cmd == "show" and group then
    local d = dumps(load(save).MintCommunityToolsDB or {})[group]
    if not d then io.stderr:write("no " .. group .. " dump in the save file\n") os.exit(1) end
    local depth = tonumber(arg4) or tonumber(arg3) or 6
    if arg3 and not tonumber(arg3) then
        local n = d.frames[arg3]
        if not n then io.stderr:write("no root named " .. arg3 .. " in the " .. group .. " dump\n") os.exit(1) end
        show(n, "", depth)
    else
        local roots = {}
        for name in pairs(d.frames) do roots[#roots + 1] = name end
        table.sort(roots)
        for _, name in ipairs(roots) do
            show(d.frames[name], "", depth)
            print("")
        end
        if #(d.missing or {}) > 0 then print("missing: " .. table.concat(d.missing, ", ")) end
    end
elseif cmd == "art" and group then
    local d = dumps(load(save).MintCommunityToolsDB or {})[group]
    if not d then io.stderr:write("no " .. group .. " dump in the save file\n") os.exit(1) end
    local depth = tonumber(arg4) or tonumber(arg3) or 6
    local function walk(n, path, left)
        if n.shown == false and path:find("/", 1, true) then return end
        for _, t in ipairs(n.regions or {}) do
            if t.type == "Texture" and t.shown ~= false and (t.alpha or 1) > 0 and (t.atlas or (t.texture and t.texture ~= "FileData ID 0" and t.texture ~= 130871)) then
                print(("%s/%s  %sx%s  %s"):format(path, label(t), r(t.w), r(t.h), tostring(t.atlas or t.texture)))
            end
        end
        if left > 0 then
            for _, c in ipairs(n.children or {}) do walk(c, path .. "/" .. label(c), left - 1) end
        end
    end
    local roots = {}
    if arg3 and not tonumber(arg3) then roots[1] = arg3 else
        for name in pairs(d.frames) do roots[#roots + 1] = name end
        table.sort(roots)
    end
    for _, name in ipairs(roots) do
        local n = d.frames[name]
        if n and not n.error then walk(n, name, depth) end
    end
    if d.gameMenu then print("game menu buttons (when it last opened): " .. table.concat(d.gameMenu.buttons or {}, ", ")) end
elseif cmd == "keep" and group then
    local d = dumps(load(save).MintCommunityToolsDB or {})[group]
    if not d then io.stderr:write("no " .. group .. " dump in the save file\n") os.exit(1) end
    local path = ("tools/dumps/%s-%s.lua"):format(group:gsub(":", "-"), tostring(d.build))
    local f = assert(io.open(path, "w"))
    f:write("-- /mint uidump " .. group .. " on build " .. tostring(d.build) .. " (" .. tostring(d.version) .. "), " .. os.date("%Y-%m-%d %H:%M", d.at or 0) .. "\nreturn " .. serialize(d, "") .. "\n")
    f:close()
    print("kept " .. path)
elseif cmd == "diff" and group and arg3 then
    local now = dumps(load(save).MintCommunityToolsDB or {})[group]
    if not now then io.stderr:write("no " .. group .. " dump in the save file\n") os.exit(1) end
    local then_ = dofile(arg3)
    local a, b = flatten(then_), flatten(now)
    local added, gone, changed = {}, {}, {}
    for path, line in pairs(b) do
        if a[path] == nil then added[#added + 1] = path .. "  " .. line
        elseif a[path] ~= line then changed[#changed + 1] = path .. "\n    was " .. a[path] .. "\n    now " .. line end
    end
    for path, line in pairs(a) do
        if b[path] == nil then gone[#gone + 1] = path .. "  " .. line end
    end
    table.sort(added) table.sort(gone) table.sort(changed)
    print(("%s: build %s -> %s"):format(group, tostring(then_.build), tostring(now.build)))
    print(("added %d, gone %d, changed %d"):format(#added, #gone, #changed))
    for _, l in ipairs(added) do print("+ " .. l) end
    for _, l in ipairs(gone) do print("- " .. l) end
    for _, l in ipairs(changed) do print("~ " .. l) end
    local missA, missB = {}, {}
    for _, n in ipairs(then_.missing or {}) do missA[n] = true end
    for _, n in ipairs(now.missing or {}) do if not missA[n] then missB[#missB + 1] = n end end
    if #missB > 0 then print("newly missing: " .. table.concat(missB, ", ")) end
else
    usage()
end
