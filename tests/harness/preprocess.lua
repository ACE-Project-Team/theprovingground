--[[
    Make GMod Lua loadable by stock Lua 5.1.

    GMod runs a patched LuaJIT with a `continue` statement. Stock Lua has no
    such thing and refuses to compile the file at all, which would put every
    file that uses it -- `config/sh_weapons.lua`, among others -- out of reach
    of these tests.

    The rewrite is the standard one:

        for x in y do BODY-with-continue end
        -->
        for x in y do repeat BODY-with-break until true end

    A `repeat ... until true` body runs exactly once, so `break` inside it lands
    where `continue` was supposed to: at the end of this iteration.

    This is a source rewrite, not an interpreter, so it is only as trustworthy
    as its two guards -- and it fails loudly rather than quietly miscompiling:

      * a real `break` belonging to a loop that is being wrapped would be
        captured by the inserted `repeat`, turning "leave the loop" into
        "skip an iteration". Detected, and refused.
      * `continue` inside a `repeat` loop cannot use this trick at all, because
        breaking a `repeat` skips its `until` condition. Refused.

    Neither case exists in this repo today. If one appears, the test run stops
    with the file and line rather than testing something the game will not run.
]]

local lexer = require("harness.lexer")

local M = {}

-- Classify each word as opening a block, closing one, or neither, and note
-- which openers are loops. `then` only opens a block after `if` -- an `elseif`
-- shares the `if`'s single `end`, and counting it would desynchronise
-- everything after it.
local function structure(words)
    local st = {}
    local pendingIf, pendingDo = false, false

    for i, t in ipairs(words) do
        local w = t.word

        if w == "if" then
            pendingIf = true
        elseif w == "elseif" then
            pendingIf = false
        elseif w == "then" then
            if pendingIf then st[i] = { kind = "open" } end
            pendingIf = false
        elseif w == "for" or w == "while" then
            pendingDo = true
        elseif w == "do" then
            st[i] = { kind = "open", isLoop = pendingDo }
            pendingDo = false
        elseif w == "function" then
            st[i] = { kind = "open", isFunction = true }
        elseif w == "repeat" then
            st[i] = { kind = "open", isLoop = true, isRepeat = true }
        elseif w == "end" or w == "until" then
            st[i] = { kind = "close" }
        end
    end

    return st
end

local function lineOf(src, pos)
    local _, n = src:sub(1, pos):gsub("\n", "")
    return n + 1
end

-- Index of the loop opener enclosing words[i], walking outward through any
-- if/do blocks in between.
local function enclosingLoop(words, st, i, src, what)
    local depth = 0

    for j = i - 1, 1, -1 do
        local s = st[j]
        if s then
            if s.kind == "close" then
                depth = depth + 1
            elseif depth > 0 then
                depth = depth - 1
            elseif s.isFunction then
                error(("%s at line %d is inside a function, not a loop")
                    :format(what, lineOf(src, words[i].from)), 0)
            elseif s.isRepeat then
                error(("`continue` at line %d is inside a `repeat` loop, which this "
                    .. "rewrite cannot handle (breaking a repeat skips its `until`)")
                    :format(lineOf(src, words[i].from)), 0)
            elseif s.isLoop then
                return j
            end
        end
    end

    return nil
end

local function matchingClose(words, st, open)
    local depth = 0
    for j = open + 1, #words do
        local s = st[j]
        if s then
            if s.kind == "open" then
                depth = depth + 1
            elseif depth > 0 then
                depth = depth - 1
            else
                return j
            end
        end
    end
    return nil
end

--- Rewrite `continue` out of a chunk of GMod Lua.
-- @tparam string src
-- @tparam string name Shown in error messages.
-- @treturn string Source that stock Lua 5.1 will compile. Unchanged (and
--  unparsed beyond the scan) when the chunk has no `continue`.
function M.rewrite(src, name)
    if not src:find("continue", 1, true) then return src end

    local words = lexer.words(src)
    local st = structure(words)

    local loops, edits = {}, {}

    for i, t in ipairs(words) do
        if t.word == "continue" then
            local ok, open = pcall(enclosingLoop, words, st, i, src, "`continue`")
            if not ok then error(name .. ": " .. tostring(open), 0) end
            if not open then
                error(("%s: `continue` at line %d is not inside any loop")
                    :format(name, lineOf(src, t.from)), 0)
            end
            loops[open] = true
            edits[#edits + 1] = { from = t.from, to = t.to, text = "break" }
        end
    end

    if not next(loops) then return src end

    for open in pairs(loops) do
        local close = matchingClose(words, st, open)
        if not close then
            error(("%s: could not find the `end` of the loop at line %d")
                :format(name, lineOf(src, words[open].from)), 0)
        end

        -- A `break` that belongs to this loop would be swallowed by the
        -- `repeat` we are about to insert.
        for j = open + 1, close - 1 do
            if words[j].word == "break" then
                local ok, owner = pcall(enclosingLoop, words, st, j, src, "`break`")
                if ok and owner == open then
                    error(("%s: the loop at line %d uses both `continue` and `break`; "
                        .. "the repeat/until rewrite would turn that `break` (line %d) "
                        .. "into a `continue`. Rewrite the loop by hand.")
                        :format(name, lineOf(src, words[open].from),
                                lineOf(src, words[j].from)), 0)
                end
            end
        end

        edits[#edits + 1] = { from = words[open].to + 1, to = words[open].to, text = " repeat" }
        edits[#edits + 1] = { from = words[close].from, to = words[close].from - 1, text = "until true " }
    end

    -- Highest offset first, so earlier offsets stay valid.
    table.sort(edits, function(a, b) return a.from > b.from end)

    local out = src
    for _, e in ipairs(edits) do
        out = out:sub(1, e.from - 1) .. e.text .. out:sub(e.to + 1)
    end

    return out
end

return M
