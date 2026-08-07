--[[
    The load-order checks.

    `AddCSLuaFile` only SENDS a file to clients; `include` runs it. A shared
    file needs both, and forgetting the AddCSLuaFile gives you a server that
    works and clients that error on a nil table -- which is the single most
    common way to break this gamemode, and one nothing in the game will tell
    you about until a player connects.

    These read the two entry points as text rather than running them, so they
    check what will actually ship.
]]

local lexer = require("harness.lexer")

local ROOT = expect.root
local GAMEMODE = ROOT .. "/gamemode"

local function read(path)
    local fh = io.open(path, "rb")
    if not fh then return nil end
    local src = fh:read("*a")
    fh:close()
    return src
end

-- Comments are blanked first so a doc comment that mentions include("x") is
-- not mistaken for a real call.
local function calls(path, fn)
    local src = read(path)
    if not src then error("cannot read " .. path, 0) end

    local code, out = lexer.stripComments(src), {}
    for arg in code:gmatch(fn .. "%s*%(%s*[\"']([^\"']+)[\"']") do
        out[#out + 1] = arg
    end
    return out
end

local function exists(rel)
    local fh = io.open(GAMEMODE .. "/" .. rel, "rb")
    if fh then fh:close() return true end
    return false
end

local function toSet(list)
    local set = {}
    for _, v in ipairs(list) do set[v] = true end
    return set
end

local shipped   = toSet(calls(GAMEMODE .. "/init.lua", "AddCSLuaFile"))
local serverRan = toSet(calls(GAMEMODE .. "/init.lua", "include"))
local clientRan = toSet(calls(GAMEMODE .. "/cl_init.lua", "include"))
local sharedRan = toSet(calls(GAMEMODE .. "/shared.lua", "include"))

describe("structure: the lists point at real files")

it("ships only files that exist", function()
    for path in pairs(shipped) do
        expect.truthy(exists(path), "init.lua AddCSLuaFile's " .. path .. ", which is not there")
    end
end)

it("includes only files that exist, on every realm", function()
    for path in pairs(serverRan) do
        expect.truthy(exists(path), "init.lua includes " .. path .. ", which is not there")
    end
    for path in pairs(clientRan) do
        expect.truthy(exists(path), "cl_init.lua includes " .. path .. ", which is not there")
    end
    for path in pairs(sharedRan) do
        expect.truthy(exists(path), "shared.lua includes " .. path .. ", which is not there")
    end
end)

it("found the lists at all", function()
    -- A guard on the scan itself: if the pattern ever stops matching, every
    -- other test in this file would pass vacuously.
    expect.truthy(table.Count(shipped) > 10, "AddCSLuaFile scan found almost nothing")
    expect.truthy(table.Count(serverRan) > 10, "server include scan found almost nothing")
    expect.truthy(table.Count(clientRan) > 5, "client include scan found almost nothing")
    expect.truthy(table.Count(sharedRan) > 5, "shared include scan found almost nothing")
end)

describe("structure: every file the client runs was sent to it")

it("ships everything cl_init.lua includes", function()
    for path in pairs(clientRan) do
        expect.truthy(shipped[path],
            "cl_init.lua includes " .. path .. " but init.lua never AddCSLuaFile's it; " ..
            "clients will fail to load it with a file-not-found")
    end
end)

it("ships everything shared.lua includes", function()
    -- shared.lua runs on both realms, so its whole include list has to reach
    -- the client too.
    for path in pairs(sharedRan) do
        expect.truthy(shipped[path],
            "shared.lua includes " .. path .. " but init.lua never AddCSLuaFile's it")
    end
end)

it("ships the two entry points themselves", function()
    expect.truthy(shipped["shared.lua"], "clients need shared.lua before anything else")
    expect.truthy(shipped["cl_init.lua"], "clients need their own entry point")
end)

describe("structure: the realm prefixes mean what they say")

it("never runs a client file on the server", function()
    for path in pairs(serverRan) do
        expect.falsy(path:match("cl_[^/]*%.lua$"),
            "init.lua includes " .. path .. ", a cl_ file, on the server")
    end
end)

it("never runs a server file on the client", function()
    for path in pairs(clientRan) do
        expect.falsy(path:match("sv_[^/]*%.lua$"),
            "cl_init.lua includes " .. path .. ", an sv_ file, on the client")
    end
    for path in pairs(sharedRan) do
        expect.falsy(path:match("sv_[^/]*%.lua$"),
            "shared.lua includes " .. path .. ", an sv_ file, and runs on both realms")
    end
end)

it("never sends a server file to clients", function()
    for path in pairs(shipped) do
        expect.falsy(path:match("sv_[^/]*%.lua$"),
            "init.lua ships " .. path .. " to clients; sv_ files are server-only")
    end
end)

describe("structure: nothing is included twice or left unrun")

it("does not include the same file on both realms", function()
    -- A shared file belongs in shared.lua's list, included once from there --
    -- not in init.lua's and cl_init.lua's lists separately.
    for path in pairs(sharedRan) do
        expect.falsy(serverRan[path], path .. " is included by both shared.lua and init.lua")
        expect.falsy(clientRan[path], path .. " is included by both shared.lua and cl_init.lua")
    end
end)

it("runs every shared file it ships, on at least one realm", function()
    for path in pairs(shipped) do
        if path:match("sh_[^/]*%.lua$") then
            expect.truthy(sharedRan[path] or serverRan[path] or clientRan[path],
                path .. " is sent to clients but never included anywhere, so it never runs")
        end
    end
end)

it("runs every client file it ships", function()
    for path in pairs(shipped) do
        if path:match("cl_[^/]*%.lua$") and path ~= "cl_init.lua" then
            expect.truthy(clientRan[path],
                path .. " is sent to clients but cl_init.lua never includes it, " ..
                "so it reaches them and is never executed")
        end
    end
end)

describe("structure: files on disk that nothing loads")

--[[
    Known-unwired files. Each needs a reason, because the point of the check is
    that an entry here is a deliberate decision rather than an oversight.

    gamemode/voting/cl_voting.lua is empty (a single line ending) and is
    referenced by nothing: the client voting UI actually lives in
    ui/cl_menu_voting.lua. It is listed rather than deleted because removing a
    file is a call for the repo's owner, not for a test.
]]
local KNOWN_UNWIRED = {
    ["voting/cl_voting.lua"] = "empty; the real client voting UI is ui/cl_menu_voting.lua",
}

-- Stock Lua cannot list a directory, so this shells out. If that fails the
-- test says so rather than passing vacuously.
local function listLuaFiles()
    local cmd = package.config:sub(1, 1) == "\\"
        and ('dir /b /s "' .. GAMEMODE:gsub("/", "\\") .. '\\*.lua" 2>nul')
        or  ("find '" .. GAMEMODE .. "' -name '*.lua' 2>/dev/null")

    local pipe = io.popen(cmd)
    if not pipe then return nil end

    local found = {}
    for line in pipe:lines() do
        local path = line:gsub("\\", "/"):gsub("%s+$", "")
        local rel = path:match("/gamemode/(.+)$")
        if rel then found[#found + 1] = rel end
    end
    pipe:close()

    if #found == 0 then return nil end
    return found
end

it("has no client or shared file that nothing loads", function()
    local files = listLuaFiles()
    expect.truthy(files, "could not list " .. GAMEMODE .. "; this check needs a shell")

    for _, rel in ipairs(files) do
        local isRealmFile = rel:match("cl_[^/]*%.lua$") or rel:match("sh_[^/]*%.lua$")
        local isEntryPoint = (rel == "cl_init.lua" or rel == "init.lua" or rel == "shared.lua")

        if isRealmFile and not isEntryPoint and not KNOWN_UNWIRED[rel] then
            expect.truthy(shipped[rel],
                rel .. " exists but init.lua never AddCSLuaFile's it. Add it to both " ..
                "lists, or record it in KNOWN_UNWIRED with a reason.")
        end
    end
end)

it("keeps the known-unwired list honest", function()
    -- An entry that has since been wired up (or deleted) should not linger
    -- here pretending to be an exception.
    for rel, reason in pairs(KNOWN_UNWIRED) do
        expect.truthy(exists(rel), "KNOWN_UNWIRED lists " .. rel .. ", which no longer exists")
        expect.falsy(shipped[rel], "KNOWN_UNWIRED lists " .. rel .. ", which is now shipped; drop the entry")
        expect.truthy(#reason > 0)
    end
end)

describe("structure: the entity and weapon folders")

it("gives every scripted entity all three realm files", function()
    for _, name in ipairs({ "tpg_controlpoint", "tpg_flag", "tpg_safezonemarker" }) do
        for _, part in ipairs({ "init.lua", "cl_init.lua", "shared.lua" }) do
            local path = ROOT .. "/entities/entities/" .. name .. "/" .. part
            local fh = io.open(path, "rb")
            expect.truthy(fh, name .. " is missing " .. part)
            if fh then fh:close() end
        end
    end
end)

it("keeps the disposable AT the class the config names", function()
    -- sv_loadout hands this out by class name from TPG.Config; a rename on
    -- either side breaks the free anti-tank tube silently.
    local class = TPG.Config.disposableATClass
    expect.truthy(#class > 0, "disposableATClass is empty, which disables the bonus tube")

    local fh = io.open(ROOT .. "/entities/weapons/" .. class .. "/shared.lua", "rb")
    expect.truthy(fh, "TPG.Config.disposableATClass is '" .. class ..
        "' but there is no SWEP folder by that name")
    if fh then fh:close() end
end)
