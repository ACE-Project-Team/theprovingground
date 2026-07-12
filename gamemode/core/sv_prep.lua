--[[
    Preparation Period (per round)

    Every round opens with a staging window: once at least prepMinPlayers players
    are split across BOTH teams, a prepTime-second countdown starts during which
    everyone is confined to their own safezone -- wander out and you're teleported
    straight back. It gives both sides a fair moment to build and stage in spawn
    instead of one team already rolling out onto the map.

    Before both teams are present there's no countdown and no confinement, so a
    lone player (or an empty enemy team) can still move around freely.

    State is mirrored to clients through two globals for the HUD countdown:
        TPG_PrepActive (bool)  -- the round is in its prep window
        TPG_PrepEnd    (float) -- CurTime the confinement lifts (0 = not counting)
]]

TPG.Prep = TPG.Prep or {}

local prepActive = false
local prepEnd    = 0        -- 0 until both teams are present and the clock starts
local nextTick   = 0
local lastWarn   = {}

local function BothTeamsPresent()
    local g = team.NumPlayers(TEAM_GREEN)
    local r = team.NumPlayers(TEAM_RED)
    return g >= 1 and r >= 1 and (g + r) >= (TPG.Config.prepMinPlayers or 2)
end

-- Is the confinement currently in force? (Used by other systems if needed.)
function TPG.Prep.IsConfining()
    return prepActive and prepEnd > 0 and CurTime() < prepEnd
end

-- Yank a player back into their safezone.
local function ConfineToSpawn(ply, silent)
    local spawn = TPG.State.spawns[ply:Team()]
    if not spawn then return end

    if ply:InVehicle() then ply:ExitVehicle() end
    ply:SetPos(spawn + Vector(math.Rand(-150, 150), math.Rand(-150, 150), 10))
    ply:SetVelocity(-ply:GetVelocity())

    if not silent and (lastWarn[ply] or 0) < CurTime() then
        lastWarn[ply] = CurTime() + 2   -- throttle so boundary-humping doesn't spam
        TPG.Util.ChatMessage(ply, "[TPG] Preparation period -- stay in spawn until it ends.",
            Color(255, 200, 80))
        TPG.Util.PlaySound(ply, "buttons/button10.wav")
    end
end

-- Called from TPG.Rounds.Setup at the start of each round.
function TPG.Prep.Begin()
    prepActive = true
    prepEnd    = 0
    lastWarn   = {}
    SetGlobalBool("TPG_PrepActive", true)
    SetGlobalFloat("TPG_PrepEnd", 0)
end

local function EndPrep()
    prepActive = false
    prepEnd    = 0
    SetGlobalBool("TPG_PrepActive", false)
    SetGlobalFloat("TPG_PrepEnd", 0)
    TPG.Util.ChatBroadcast("[TPG] GO! Preparation over -- move out!", Color(120, 230, 120))
end

hook.Add("Think", "TPG_PrepThink", function()
    if not prepActive then return end
    local now = CurTime()

    -- Waiting for a real matchup: start the clock the moment both teams are in.
    if prepEnd == 0 then
        if BothTeamsPresent() then
            prepEnd = now + (TPG.Config.prepTime or 30)
            SetGlobalFloat("TPG_PrepEnd", prepEnd)
            for _, ply in ipairs(player.GetAll()) do
                if IsValid(ply) and ply:Alive() and TPG.Util.IsOnTeam(ply) then
                    ConfineToSpawn(ply, true)
                end
            end
            TPG.Util.ChatBroadcast("[TPG] PREPARATION: " .. (TPG.Config.prepTime or 30) ..
                "s to build and stage in spawn -- you can't leave yet.", Color(255, 200, 80))
        end
        return
    end

    if now >= prepEnd then
        EndPrep()
        return
    end

    -- Confinement sweep (a few times a second is enough, and cheap).
    if now < nextTick then return end
    nextTick = now + 0.1
    for _, ply in ipairs(player.GetAll()) do
        if IsValid(ply) and ply:Alive() and TPG.Util.IsOnTeam(ply)
            and not TPG.Protection.IsInSafezone(ply) then
            ConfineToSpawn(ply)
        end
    end
end)

hook.Add("PlayerDisconnected", "TPG_PrepCleanup", function(ply)
    lastWarn[ply] = nil
end)
