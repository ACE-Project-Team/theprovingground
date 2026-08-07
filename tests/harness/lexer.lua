--[[
    A deliberately small Lua scanner: enough to find keywords that are really
    code, and nothing more.

    It exists so `preprocess.lua` can rewrite GMod's `continue` without being
    fooled by the word turning up inside a comment or a string -- which it does,
    in this very repo's doc comments. So this skips comments (both forms, any
    long-bracket level) and string literals (both quote styles and long
    brackets), and reports every remaining word with the offsets it occupied.

    It is NOT a parser and does not validate anything. Numbers are consumed only
    so that `1e5` does not come back as the word `e5`.
]]

local M = {}

local function longBracket(src, i)
    -- At src[i] == '[', return the level and the offset just past the opener,
    -- or nil when this is an ordinary '['.
    local j, level = i + 1, 0
    while src:sub(j, j) == "=" do
        level = level + 1
        j = j + 1
    end
    if src:sub(j, j) ~= "[" then return nil end
    return level, j + 1
end

local function skipLongBracket(src, level, from)
    local close = "]" .. string.rep("=", level) .. "]"
    local e = src:find(close, from, true)
    if not e then return #src + 1 end
    return e + #close
end

--- Every code word in `src`, in order.
-- @tparam string src
-- @treturn table List of `{ word = string, from = number, to = number }`,
--  where `from`/`to` are 1-based inclusive byte offsets into `src`.
function M.words(src)
    local out, i, n = {}, 1, #src

    while i <= n do
        local c = src:sub(i, i)

        -- Comment. Long form first, so --[[ ]] is not read as a line comment.
        if c == "-" and src:sub(i + 1, i + 1) == "-" then
            local level, past = longBracket(src, i + 2)
            if level then
                i = skipLongBracket(src, level, past)
            else
                local e = src:find("\n", i, true)
                i = e and (e + 1) or (n + 1)
            end

        -- Long string.
        elseif c == "[" and longBracket(src, i) then
            local level, past = longBracket(src, i)
            i = skipLongBracket(src, level, past)

        -- Quoted string.
        elseif c == '"' or c == "'" then
            local j = i + 1
            while j <= n do
                local d = src:sub(j, j)
                if d == "\\" then
                    j = j + 2
                elseif d == c or d == "\n" then
                    j = j + 1
                    break
                else
                    j = j + 1
                end
            end
            i = j

        -- Word.
        elseif c:match("[%a_]") then
            local _, e = src:find("^[%w_]+", i)
            out[#out + 1] = { word = src:sub(i, e), from = i, to = e }
            i = e + 1

        -- Number: consumed whole so exponents/hex don't yield stray words.
        elseif c:match("%d") then
            local _, e = src:find("^[%w%.]+", i)
            i = e + 1

        else
            i = i + 1
        end
    end

    return out
end

--- `src` with every comment replaced by spaces of the same length.
-- Offsets and line numbers survive, so a pattern match against the result
-- still points at the right place in the original. Used to scan for real
-- `include("...")` calls without matching the ones inside doc comments.
-- @tparam string src
-- @treturn string
function M.stripComments(src)
    local out, i, n = {}, 1, #src

    local function blank(from, to)
        out[#out + 1] = (src:sub(from, to):gsub("[^\r\n]", " "))
    end

    while i <= n do
        local c = src:sub(i, i)

        if c == "-" and src:sub(i + 1, i + 1) == "-" then
            local level, past = longBracket(src, i + 2)
            local stop
            if level then
                stop = skipLongBracket(src, level, past) - 1
            else
                local e = src:find("\n", i, true)
                stop = e and (e - 1) or n
            end
            blank(i, stop)
            i = stop + 1

        elseif c == "[" and longBracket(src, i) then
            local level, past = longBracket(src, i)
            local stop = skipLongBracket(src, level, past) - 1
            out[#out + 1] = src:sub(i, stop)
            i = stop + 1

        elseif c == '"' or c == "'" then
            local j = i + 1
            while j <= n do
                local d = src:sub(j, j)
                if d == "\\" then j = j + 2
                elseif d == c or d == "\n" then j = j + 1 break
                else j = j + 1 end
            end
            out[#out + 1] = src:sub(i, j - 1)
            i = j

        else
            out[#out + 1] = c
            i = i + 1
        end
    end

    return table.concat(out)
end

return M
