--[[
    Game Type Definitions
]]

TPG.GameTypes = {
    [GAMEMODE_CP] = {
        id              = GAMEMODE_CP,
        name            = "Control Points",
        shortName       = "CP",
        description     = "Capture and hold control points",
        useDeathTickets = false,
        defaultCapMul   = 0.02,
    },
    [GAMEMODE_KOTH] = {
        id              = GAMEMODE_KOTH,
        name            = "King of the Hill",
        shortName       = "KOTH",
        description     = "Hold the central point",
        useDeathTickets = false,
        defaultCapMul   = 0.15,
    },
    [GAMEMODE_DM] = {
        id              = GAMEMODE_DM,
        name            = "Deathmatch",
        shortName       = "DM",
        description     = "Destroy enemy vehicles",
        useDeathTickets = true,
        defaultCapMul   = 0,
    },
    [GAMEMODE_CTF] = {
        id              = GAMEMODE_CTF,
        name            = "Capture the Flag",
        shortName       = "CTF",
        description     = "Steal the enemy flag, bring it back to your base",
        useDeathTickets = false,
        -- Scoring is handled by flag captures (objectives/sv_ctf.lua), not the
        -- passive control-point drain, so no cap multiplier here.
        defaultCapMul   = 0,
    },
}

-- Slot split: CTF 30% / KOTH 25% / DM 15% / CP 30%. CP and CTF share the
-- top, KOTH right after, DM deliberately rare. CTF is its own mode -- it
-- borrows the map's KOTH capture point as the flag's home
-- (TPG.CTF.GetFlagPoint), it does NOT replace a KOTH round. On a map that
-- can't host a flag, CTF's slice falls through to KOTH.
local function RollGameType()
    local roll = math.random()

    if roll < (TPG.Config.ctfChance or 0.30) then
        if TPG.CTF and TPG.CTF.IsSupported and TPG.CTF.IsSupported() then
            return GAMEMODE_CTF
        end
        return GAMEMODE_KOTH
    elseif roll < 0.55 then
        return GAMEMODE_KOTH
    elseif roll < 0.70 then
        return GAMEMODE_DM
    else
        return GAMEMODE_CP
    end
end

local lastGameType

function TPG.SelectRandomGameType()
    local picked = RollGameType()

    -- Anti-repeat: one reroll when the same mode comes up twice in a row, which
    -- halves the odds of a back-to-back repeat without ever forbidding it.
    if picked == lastGameType then
        picked = RollGameType()
    end

    lastGameType = picked
    return picked
end

function TPG.GetGameType(typeId)
    return TPG.GameTypes[typeId] or TPG.GameTypes[GAMEMODE_CP]
end

function TPG.GetGameTypeName(typeId)
    local gt = TPG.GetGameType(typeId)
    return gt.shortName
end