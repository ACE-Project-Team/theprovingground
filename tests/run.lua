--[[
    Test runner. From the repo root:

        lua tests/run.lua              -- everything
        lua tests/run.lua gear maps    -- only suites whose name contains these

    Exits non-zero if anything failed, so it works as a gate.
]]

-- Locate the repo root from this script's own path, so the runner works from
-- any working directory.
local scriptPath = arg and arg[0] or "tests/run.lua"
local testsDir   = scriptPath:gsub("[\\/][^\\/]*$", "")
if testsDir == scriptPath then testsDir = "." end
local root = testsDir:gsub("[\\/][^\\/]*$", "")
if root == testsDir then root = "." end

package.path = testsDir .. "/?.lua;" .. package.path

local loader = require("harness.load")

-- Every suite, in load order. Explicit rather than globbed: stock Lua cannot
-- list a directory without an extra library, and a manifest also means a new
-- file is not silently skipped because of a typo in its name.
local SUITES = {
    "test_preprocess",
    "test_config",
    "test_teams",
    "test_armor",
    "test_ranks",
    "test_gametypes",
    "test_controlpoint",
    "test_gear",
    "test_weapons",
    "test_maps",
    "test_utils",
    "test_structure",
}

----------------------------------------------------------------- registry

local suites, current = {}, nil

function describe(name)
    current = { name = name, cases = {} }
    suites[#suites + 1] = current
end

function it(name, fn)
    if not current then describe("(unnamed)") end
    current.cases[#current.cases + 1] = { name = name, fn = fn }
end

--------------------------------------------------------------- assertions

local function render(v)
    if type(v) == "table" then
        if v.x and v.y and v.z then return tostring(v) end
        if v.r and v.g and v.b then
            return string.format("Color(%s, %s, %s, %s)", v.r, v.g, v.b, v.a)
        end
        local parts = {}
        for k, item in pairs(v) do
            parts[#parts + 1] = tostring(k) .. "=" .. tostring(item)
            if #parts >= 6 then parts[#parts + 1] = "..." break end
        end
        return "{ " .. table.concat(parts, ", ") .. " }"
    end
    return tostring(v)
end

local function fail(msg)
    error({ tpg_assert = msg }, 0)
end

expect = {}

function expect.eq(actual, wanted, msg)
    if actual ~= wanted then
        fail(string.format("%sexpected %s, got %s",
            msg and (msg .. ": ") or "", render(wanted), render(actual)))
    end
end

function expect.ne(actual, unwanted, msg)
    if actual == unwanted then
        fail(string.format("%sexpected anything but %s",
            msg and (msg .. ": ") or "", render(unwanted)))
    end
end

function expect.near(actual, wanted, tol, msg)
    tol = tol or 1e-9
    if type(actual) ~= "number" or math.abs(actual - wanted) > tol then
        fail(string.format("%sexpected %s +/- %s, got %s",
            msg and (msg .. ": ") or "", tostring(wanted), tostring(tol), render(actual)))
    end
end

function expect.truthy(v, msg)
    if not v then fail((msg and (msg .. ": ") or "") .. "expected a truthy value, got " .. render(v)) end
end

function expect.falsy(v, msg)
    if v then fail((msg and (msg .. ": ") or "") .. "expected a falsy value, got " .. render(v)) end
end

function expect.nils(v, msg)
    if v ~= nil then fail((msg and (msg .. ": ") or "") .. "expected nil, got " .. render(v)) end
end

--- Assert that `fn` raises. Returns the error, for asserting on the message.
function expect.raises(fn, msg)
    local ok, err = pcall(fn)
    if ok then fail((msg and (msg .. ": ") or "") .. "expected an error, but the call succeeded") end
    return err
end

------------------------------------------------------------------ harness

expect.load = loader
expect.root = root

------------------------------------------------------------------- running

local wanted = {}
for i = 1, #arg do wanted[#wanted + 1] = arg[i]:lower() end

local function selected(name)
    if #wanted == 0 then return true end
    for _, w in ipairs(wanted) do
        if name:lower():find(w, 1, true) then return true end
    end
    return false
end

-- Load the gamemode once; suites reset the mutable stub state per case.
local ok, err = pcall(loader.gamemode, root)
if not ok then
    io.write("FATAL: could not load the gamemode under the stubs\n  ", tostring(err), "\n")
    os.exit(2)
end

for _, suite in ipairs(SUITES) do
    if selected(suite) then
        local loaded, lerr = pcall(require, suite)
        if not loaded then
            io.write("FATAL: could not load ", suite, "\n  ", tostring(lerr), "\n")
            os.exit(2)
        end
    end
end

local passed, failures = 0, {}

for _, suite in ipairs(suites) do
    io.write(suite.name, "\n")

    for _, case in ipairs(suite.cases) do
        loader.reset()

        local good, e = xpcall(case.fn, function(caught)
            if type(caught) == "table" and caught.tpg_assert then return caught end
            return { tpg_assert = tostring(caught), traceback = debug.traceback("", 2) }
        end)

        if good then
            passed = passed + 1
            io.write("  ok    ", case.name, "\n")
        else
            failures[#failures + 1] = { suite = suite.name, case = case.name, err = e }
            io.write("  FAIL  ", case.name, "\n")
            io.write("        ", tostring(e.tpg_assert), "\n")
        end
    end
end

io.write(string.format("\n%d passed, %d failed\n", passed, #failures))

if #failures > 0 then
    io.write("\nFailures:\n")
    for _, f in ipairs(failures) do
        io.write("  ", f.suite, " / ", f.case, "\n    ", tostring(f.err.tpg_assert), "\n")
        if f.err.traceback then io.write(f.err.traceback, "\n") end
    end
    os.exit(1)
end

os.exit(0)
