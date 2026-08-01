--[[
    Player Spawning
]]

TPG.Spawning = TPG.Spawning or {}

--[[
    Where a player is allowed to end up.

    A fresh server spends its first stretch with no round: GM:Initialize waits
    3s, then TPG.Rounds.BeginInitialWait holds off the first round for up to
    waitMaxTotal (90s) while people load in. Everyone who joins in that window
    spawns before TPG.Rounds.Setup has ever published TPG.State.spawns.

    That used to be fatal. spawns defaulted to Vector(0, 0, 0), `if spawnPos`
    passed (a zero Vector is truthy), and every player on a team was teleported
    to the map origin -- inside the world on most maps, and under it on the
    rest. Falling out of the world kills you THROUGH god mode, so they died,
    respawned at the origin, and died again on a loop until the round finally
    started. Players with no team had the mirror-image bug: nothing positioned
    them at all, so on a map with no info_player_start the engine dropped them
    at the origin too, with the same result.

    So: never move anyone to a position we haven't checked, and check where
    they landed even when we didn't move them.
]]
local function IsUsablePos(pos)
    return isvector(pos) and not pos:IsZero() and util.IsInWorld(pos)
end

--[[
    Map-authored spawn entity classes we'll accept as a last-resort position.

    GMod itself keeps an unordered SET of these (SpawnPointEntityClasses in
    gamemodes/base/gamemode/player.lua) and picks a RANDOM valid one -- it has
    no preference between classes. This list is ordered only because we return
    the first usable entity we find and want that choice to be stable across
    restarts, so a bad fallback spot is reproducible instead of intermittent.
    info_player_start leads because it's the one class virtually every map has.

    Superset of GMod's list on purpose: it covers the CS/DM classes that
    gmod_player_start registers at runtime, which we can't rely on having been
    loaded yet when this runs.
]]
local SPAWN_CLASSES = {
    "info_player_start",
    "gmod_player_start",
    "info_player_deathmatch",
    "info_player_combine",
    "info_player_rebel",
    "info_player_teamspawn",
    "info_player_counterterrorist",
    "info_player_terrorist",
}

local function FindMapSpawn()
    for _, class in ipairs(SPAWN_CLASSES) do
        for _, ent in ipairs(ents.FindByClass(class)) do
            if IsValid(ent) then
                local pos = ent:GetPos() + Vector(0, 0, 16)
                if IsUsablePos(pos) then return pos end
            end
        end
    end
end

-- A position that is definitely not the void, for someone we have nowhere
-- better to put. Preference order: this round's team spawns, then the map
-- config's spawns (which TPG.Maps.Get loads on demand, so this works before
-- the first round), then whatever spawn entities the map ships.
function TPG.Spawning.FallbackPos(ply)
    local preferred = IsValid(ply) and ply:Team() or nil

    for _, teamId in ipairs({ preferred, TEAM_GREEN, TEAM_RED }) do
        if teamId then
            local pos = TPG.State.GetSpawn(teamId)
            if pos and IsUsablePos(pos) then return pos end
        end
    end

    local mapConfig = TPG.Maps and TPG.Maps.Get and TPG.Maps.Get()
    if istable(mapConfig) and istable(mapConfig.spawns) then
        for _, teamId in ipairs({ preferred, TEAM_GREEN, TEAM_RED }) do
            if teamId then
                local pos = mapConfig.spawns[teamId]
                if IsUsablePos(pos) then return pos end
            end
        end
    end

    return FindMapSpawn()
end

-- Last line of defence, run on every spawn: if wherever the player ended up
-- isn't inside the world, move them somewhere that is. Cheap (one trace-free
-- bounds check) and it can't misfire, since a legitimate spawn is always in
-- the world and never exactly at the origin.
function TPG.Spawning.EnsureInWorld(ply)
    if not IsValid(ply) then return end
    if IsUsablePos(ply:GetPos()) then return end

    local pos = TPG.Spawning.FallbackPos(ply)
    if pos then
        ply:SetPos(pos)
        return
    end

    -- No usable spawn anywhere on the map. Nothing left to do but say so --
    -- loudly, once per map, because it means this map is unplayable as
    -- configured and the fix is a map config, not a code change.
    if not TPG.Spawning.WarnedNoSpawn then
        TPG.Spawning.WarnedNoSpawn = true
        print("[TPG] WARNING: no usable spawn point found on " .. game.GetMap() ..
            " (no round spawns, no map config spawns, no info_player_* entities).")
        print("[TPG] Players will spawn wherever the engine puts them and may die on spawn.")
    end
end

function GM:PlayerSpawn(ply)
    self.BaseClass:PlayerSpawn(ply)

    local teamId = ply:Team()

    if TPG.Util.IsOnTeam(ply) then
        -- Only move them once the round has published a real spawn. Before
        -- that, the engine's own choice of spawn point is a far better guess
        -- than anything we have.
        local spawnPos = TPG.State.GetSpawn(teamId)
        if spawnPos then
            ply:SetPos(spawnPos)
        end

        -- Apply team colors
        local teamData = TPG.GetTeamData(teamId)
        ply:SetPlayerColor(teamData.vector)
        ply:SetWeaponColor(teamData.vector)

        -- Enable spawn protection (longer while your team is the underdog)
        local pState = TPG.State.GetPlayer(ply)
        pState.spawnProtection = (TPG.Underdog and TPG.Underdog.GetProtectionTime)
            and TPG.Underdog.GetProtectionTime(ply)
            or TPG.Config.spawnProtectionTime
        ply:GodEnable()
    else
        -- Spectators are permanently invulnerable non-combatants; their damage
        -- output is blocked in sv_protection (TPG_SpectatorNoDamage).
        ply:GodEnable()
    end

    TPG.Spawning.EnsureInWorld(ply)

    -- Apply loadout
    TPG.Loadout.Apply(ply)
end

function GM:PlayerSetModel(ply)
    local armorId = TPG.Util.GetPData(ply, "Armor", 1)
    local model = TPG.GetArmorModel(armorId)
    ply:SetModel(model)
end

-- Initial spawn
hook.Add("PlayerInitialSpawn", "TPG_InitialSpawn", function(ply)
    -- Auto-assign to team
    local greenCount = team.NumPlayers(TEAM_GREEN)
    local redCount = team.NumPlayers(TEAM_RED)

    if greenCount < redCount then
        ply:SetTeam(TEAM_GREEN)
    elseif redCount < greenCount then
        ply:SetTeam(TEAM_RED)
    else
        ply:SetTeam(TEAM_UNASSIGNED)
        ply:ConCommand("tpg_menu_team")
    end

    TPG.Util.ChatMessage(ply, "[TPG] F2 teams / profile / manual, F3 loadout, F4 enter vehicle.", Color(0, 255, 0))
    TPG.Util.PlaySound(ply, "garrysmod/save_load1.wav")
end)
