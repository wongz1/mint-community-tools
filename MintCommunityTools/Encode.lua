--[[
    Encode.lua - JSON serializer, Base64, Adler-32, and export-string packing.

    Pure Lua 5.1, no third-party libraries, no bit operations (arithmetic only),
    so it behaves the same on every WoW client and can be unit tested outside the game.

    String format (v1):   GAE1:<base64 of UTF-8 JSON>:<adler32 of the JSON, 8 hex chars>
    See docs/export-string-format-v1.md for the full contract.
]]

local ADDON, ns = ...
local Encode = {}
ns.Encode = Encode

local floor  = math.floor
local concat = table.concat
local sort   = table.sort
local sbyte, schar, sformat, sgsub, ssub = string.byte, string.char, string.format, string.gsub, string.sub
local type, pairs, ipairs, tostring, error = type, pairs, ipairs, tostring, error

Encode.PREFIX = "GAE1"

---------------------------------------------------------------------------
-- JSON encoding
---------------------------------------------------------------------------

local escapes = {
    ['"']  = '\\"',
    ['\\'] = '\\\\',
    ['\b'] = '\\b',
    ['\f'] = '\\f',
    ['\n'] = '\\n',
    ['\r'] = '\\r',
    ['\t'] = '\\t',
}

local function escapeChar(c)
    return escapes[c] or sformat("\\u%04x", sbyte(c))
end

local function encodeString(s)
    -- %c = control characters. Bytes >= 128 (UTF-8 multibyte) pass through untouched.
    local escaped = sgsub(s, '[%c"\\]', escapeChar)
    return '"' .. escaped .. '"'
end

local function encodeNumber(n)
    if n ~= n or n == math.huge or n == -math.huge then
        return "null"
    end
    if n == floor(n) and n > -1e15 and n < 1e15 then
        return sformat("%d", n)
    end
    return sformat("%.14g", n)
end

-- Returns true, length when t is a dense 1..n list (an empty table counts as an empty list).
local function isArray(t)
    local n = 0
    for k in pairs(t) do
        if type(k) ~= "number" or k < 1 or k ~= floor(k) then
            return false
        end
        if k > n then n = k end
    end
    for i = 1, n do
        if t[i] == nil then return false end
    end
    return true, n
end

local encodeValue
encodeValue = function(v, buf, depth)
    local tv = type(v)
    if tv == "string" then
        buf[#buf + 1] = encodeString(v)
    elseif tv == "number" then
        buf[#buf + 1] = encodeNumber(v)
    elseif tv == "boolean" then
        buf[#buf + 1] = v and "true" or "false"
    elseif tv == "table" then
        if depth > 12 then
            error("GAE JSON: nesting too deep")
        end
        local arr, n = isArray(v)
        if arr then
            buf[#buf + 1] = "["
            for i = 1, n do
                if i > 1 then buf[#buf + 1] = "," end
                encodeValue(v[i], buf, depth + 1)
            end
            buf[#buf + 1] = "]"
        else
            local keys = {}
            for k in pairs(v) do
                if type(k) ~= "string" then
                    error("GAE JSON: object keys must be strings, got " .. type(k))
                end
                keys[#keys + 1] = k
            end
            sort(keys) -- deterministic output makes strings diffable and testable
            buf[#buf + 1] = "{"
            for i, k in ipairs(keys) do
                if i > 1 then buf[#buf + 1] = "," end
                buf[#buf + 1] = encodeString(k)
                buf[#buf + 1] = ":"
                encodeValue(v[k], buf, depth + 1)
            end
            buf[#buf + 1] = "}"
        end
    else
        error("GAE JSON: cannot encode value of type " .. tv)
    end
end

function Encode.JSON(value)
    local buf = {}
    encodeValue(value, buf, 0)
    return concat(buf)
end

---------------------------------------------------------------------------
-- Base64 (RFC 4648, standard alphabet, '=' padding)
---------------------------------------------------------------------------

local ALPHABET = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
local encodeChars = {}   -- [0..63] -> char
local decodeChars = {}   -- char -> 0..63
for i = 0, 63 do
    local c = ssub(ALPHABET, i + 1, i + 1)
    encodeChars[i] = c
    decodeChars[c] = i
end

function Encode.Base64Encode(s)
    local out = {}
    local len = #s
    local i = 1
    while i <= len do
        local b1, b2, b3 = sbyte(s, i, i + 2)
        local n = b1 * 65536 + (b2 or 0) * 256 + (b3 or 0)
        local c1 = floor(n / 262144)
        local c2 = floor(n / 4096) % 64
        local c3 = floor(n / 64) % 64
        local c4 = n % 64
        out[#out + 1] = encodeChars[c1]
            .. encodeChars[c2]
            .. (b2 and encodeChars[c3] or "=")
            .. (b3 and encodeChars[c4] or "=")
        i = i + 3
    end
    return concat(out)
end

-- Returns the decoded string, or nil plus an error message.
function Encode.Base64Decode(s)
    s = sgsub(s, "%s", "")
    if #s % 4 ~= 0 then
        return nil, "base64 length is not a multiple of 4"
    end
    local out = {}
    for i = 1, #s, 4 do
        local c1, c2, c3, c4 = ssub(s, i, i), ssub(s, i + 1, i + 1), ssub(s, i + 2, i + 2), ssub(s, i + 3, i + 3)
        local v1, v2 = decodeChars[c1], decodeChars[c2]
        if not v1 or not v2 then
            return nil, "invalid base64 character"
        end
        local v3 = (c3 ~= "=") and decodeChars[c3] or nil
        local v4 = (c4 ~= "=") and decodeChars[c4] or nil
        if (c3 ~= "=" and not v3) or (c4 ~= "=" and not v4) or (c3 == "=" and v4) then
            return nil, "invalid base64 character"
        end
        local n = v1 * 262144 + v2 * 4096 + (v3 or 0) * 64 + (v4 or 0)
        out[#out + 1] = schar(floor(n / 65536))
        if v3 then out[#out + 1] = schar(floor(n / 256) % 256) end
        if v4 then out[#out + 1] = schar(n % 256) end
    end
    return concat(out)
end

---------------------------------------------------------------------------
-- Adler-32 checksum, returned as 8 lowercase hex characters
---------------------------------------------------------------------------

function Encode.Adler32(s)
    local a, b = 1, 0
    for i = 1, #s do
        a = (a + sbyte(s, i)) % 65521
        b = (b + a) % 65521
    end
    -- two %04x halves instead of one %08x, which is unreliable for values >= 2^31 on some builds
    return sformat("%04x%04x", b, a)
end

---------------------------------------------------------------------------
-- Export string packing
---------------------------------------------------------------------------

-- Returns exportString, json
function Encode.Pack(data)
    local json = Encode.JSON(data)
    return Encode.PREFIX .. ":" .. Encode.Base64Encode(json) .. ":" .. Encode.Adler32(json), json
end

-- Returns json on success, or nil plus an error message. (JSON parsing is left to the website.)
function Encode.Unpack(str)
    str = sgsub(str or "", "^%s+", "")
    str = sgsub(str, "%s+$", "")
    local prefix, body, sum = str:match("^(%u+%d+):([A-Za-z0-9%+/=]+):(%x%x%x%x%x%x%x%x)$")
    if not prefix then
        return nil, "not a Guild Armory export string"
    end
    if prefix ~= Encode.PREFIX then
        return nil, "unsupported string version " .. prefix
    end
    local json, err = Encode.Base64Decode(body)
    if not json then
        return nil, err
    end
    if Encode.Adler32(json) ~= sum:lower() then
        return nil, "checksum mismatch (string was truncated or edited)"
    end
    return json
end
