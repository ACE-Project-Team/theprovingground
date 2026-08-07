--[[
    Load the gamemode's SHARED files under the stub API.

    Only the shared chain (`gamemode/shared.lua` and everything it includes) is
    loaded. The server files are hook and net plumbing whose behaviour is the
    engine calling them in an order this harness does not reproduce; pretending
    otherwise would produce tests that pass without meaning anything. What is
    in scope here is the part that is honest to test outside the game: the
    config tables, the lookups over them, and the pure functions.
]]

local preprocess = require("harness.preprocess")
local gmod       = require("harness.gmod")

local M = { gmod = gmod }

local function readFile(path)
    local fh, err = io.open(path, "rb")
    if not fh then error("cannot open " .. path .. " (" .. tostring(err) .. ")", 0) end
    local src = fh:read("*a")
    fh:close()
    return src
end

--- Compile and run one gamemode file under the stubs.
-- @tparam string path Absolute or cwd-relative path.
-- @return Whatever the chunk returns.
function M.dofile(path)
    local src = preprocess.rewrite(readFile(path), path)
    local chunk, err = loadstring(src, "@" .. path)
    if not chunk then error("syntax error in " .. path .. ": " .. tostring(err), 0) end
    return chunk()
end

--- Install the stubs and load the shared chain.
-- @tparam string root Repo root (the directory holding `gamemode/`).
-- @treturn table The `TPG` global, for convenience.
function M.gamemode(root)
    gmod.install()

    -- Inside a gamemode, include() resolves against the gamemode/ directory,
    -- not against the including file -- which is why shared.lua can say
    -- include("config/sh_config.lua") from any depth.
    _G.include = function(rel) return M.dofile(root .. "/gamemode/" .. rel) end

    M.dofile(root .. "/gamemode/shared.lua")
    return _G.TPG
end

--- Put the mutable stub state back to a known baseline between tests.
-- Re-registers the teams, since resetting drops the engine-side team table
-- that `sh_teams.lua` filled in at load time.
function M.reset()
    gmod.reset()
    if _G.TPG and _G.TPG.SetupTeams then
        _G.TPG._ownTeams = nil
        _G.TPG.SetupTeams()
    end
end

return M
