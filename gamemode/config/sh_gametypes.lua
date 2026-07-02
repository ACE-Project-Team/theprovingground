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

function TPG.SelectRandomGameType()
    local roll = math.random()

    -- Slot split: 0-0.15 CTF, 0.15-0.40 KOTH, 0.40-0.60 DM, 0.60-1.0 CP.
    -- CTF is its own mode now -- it just borrows the map's KOTH capture point as
    -- the flag's home (TPG.CTF.GetFlagPoint), it does NOT replace a KOTH round.
    -- On a map that can't host a flag, CTF's slice falls through to KOTH.
    if roll < (TPG.Config.ctfChance or 0.15) then
        if TPG.CTF and TPG.CTF.IsSupported and TPG.CTF.IsSupported() then
            return GAMEMODE_CTF
        end
        return GAMEMODE_KOTH
    elseif roll < 0.40 then
        return GAMEMODE_KOTH
    elseif roll < 0.60 then
        return GAMEMODE_DM
    else
        return GAMEMODE_CP
    end
end

function TPG.GetGameType(typeId)
    return TPG.GameTypes[typeId] or TPG.GameTypes[GAMEMODE_CP]
end

function TPG.GetGameTypeName(typeId)
    local gt = TPG.GetGameType(typeId)
    return gt.shortName
end