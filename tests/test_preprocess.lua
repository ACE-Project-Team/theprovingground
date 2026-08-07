--[[
    The `continue` rewrite is harness code, but it edits gamemode source before
    anything else sees it, so a bug here would quietly change what every other
    suite is testing. These run first for that reason.
]]

local preprocess = require("harness.preprocess")

local function run(src)
    local chunk = assert(loadstring(preprocess.rewrite(src, "<test>"), "@<test>"))
    return chunk()
end

describe("preprocess: the continue rewrite")

it("skips the rest of the iteration, like GMod's continue", function()
    local kept = run([[
        local kept = {}
        for i = 1, 5 do
            if i % 2 == 0 then continue end
            kept[#kept + 1] = i
        end
        return table.concat(kept, ",")
    ]])
    expect.eq(kept, "1,3,5")
end)

it("does not end the loop early", function()
    local n = run([[
        local n = 0
        for i = 1, 10 do
            if i < 8 then continue end
            n = n + 1
        end
        return n
    ]])
    expect.eq(n, 3, "iterations after the last continue must still run")
end)

it("handles a continue nested inside an if/else chain", function()
    local out = run([[
        local out = {}
        for i = 1, 6 do
            if i == 1 then
                out[#out + 1] = "a"
            elseif i == 2 then
                continue
            elseif i == 3 then
                out[#out + 1] = "c"
            else
                if i == 5 then continue end
                out[#out + 1] = "d"
            end
        end
        return table.concat(out, "")
    ]])
    expect.eq(out, "acdd")
end)

it("rewrites the inner loop only, when loops are nested", function()
    local out = run([[
        local out = {}
        for i = 1, 3 do
            for j = 1, 3 do
                if j == 2 then continue end
                out[#out + 1] = i .. ":" .. j
            end
        end
        return table.concat(out, " ")
    ]])
    expect.eq(out, "1:1 1:3 2:1 2:3 3:1 3:3")
end)

it("rewrites the outer loop when that is where the continue is", function()
    local out = run([[
        local out = {}
        for i = 1, 3 do
            if i == 2 then continue end
            for j = 1, 2 do
                out[#out + 1] = i .. ":" .. j
            end
        end
        return table.concat(out, " ")
    ]])
    expect.eq(out, "1:1 1:2 3:1 3:2")
end)

it("leaves a nested loop's own break alone", function()
    local out = run([[
        local out = {}
        for i = 1, 3 do
            if i == 2 then continue end
            for j = 1, 5 do
                if j == 3 then break end
                out[#out + 1] = i .. ":" .. j
            end
        end
        return table.concat(out, " ")
    ]])
    expect.eq(out, "1:1 1:2 3:1 3:2")
end)

it("works in a while loop", function()
    local out = run([[
        local out, i = {}, 0
        while i < 5 do
            i = i + 1
            if i == 3 then continue end
            out[#out + 1] = i
        end
        return table.concat(out, ",")
    ]])
    expect.eq(out, "1,2,4,5")
end)

describe("preprocess: what it must not touch")

it("ignores the word inside a line comment", function()
    local src = "-- continue here\nreturn 1"
    expect.eq(preprocess.rewrite(src, "<test>"), src)
end)

it("ignores the word inside a block comment", function()
    local src = "--[[ we continue after this ]]\nreturn 1"
    expect.eq(preprocess.rewrite(src, "<test>"), src)
end)

it("ignores the word inside a string", function()
    local src = 'return "continue"'
    expect.eq(preprocess.rewrite(src, "<test>"), src)
    expect.eq(run(src), "continue")
end)

it("ignores the word inside a long string", function()
    local src = 'return [[press to continue]]'
    expect.eq(run(src), "press to continue")
end)

it("leaves a file with no continue byte-identical", function()
    local src = "local a = 1\nfor i = 1, 3 do a = a + i end\nreturn a"
    expect.eq(preprocess.rewrite(src, "<test>"), src)
end)

describe("preprocess: refuses what it cannot do safely")

it("refuses a loop that mixes continue and its own break", function()
    -- The inserted `repeat` would capture the break and turn "leave the loop"
    -- into "skip an iteration" -- a silent behaviour change.
    local err = expect.raises(function()
        preprocess.rewrite([[
            for i = 1, 5 do
                if i == 2 then continue end
                if i == 4 then break end
            end
        ]], "<test>")
    end)
    expect.truthy(tostring(err):find("continue", 1, true))
    expect.truthy(tostring(err):find("break", 1, true))
end)

it("refuses continue inside a repeat loop", function()
    local err = expect.raises(function()
        preprocess.rewrite([[
            repeat
                if x then continue end
            until true
        ]], "<test>")
    end)
    expect.truthy(tostring(err):lower():find("repeat", 1, true))
end)

it("refuses continue that is not in a loop at all", function()
    expect.raises(function()
        preprocess.rewrite("local function f() continue end", "<test>")
    end)
end)

describe("preprocess: the real file it exists for")

it("makes config/sh_weapons.lua compile under stock Lua", function()
    local path = expect.root .. "/gamemode/config/sh_weapons.lua"
    local fh = assert(io.open(path, "rb"), "cannot open " .. path)
    local src = fh:read("*a")
    fh:close()

    expect.truthy(src:find("continue", 1, true), "this test is pointless if the file stopped using continue")
    expect.falsy(loadstring(src), "stock Lua should reject the file as written")

    local rewritten = preprocess.rewrite(src, path)
    local chunk, err = loadstring(rewritten, "@" .. path)
    expect.truthy(chunk, "rewritten source should compile: " .. tostring(err))
end)
