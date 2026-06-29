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

    if roll < 0.2 then
        -- KOTH slot. CTF lives on the KOTH point, so it only replaces KOTH and
        -- only when the map actually has one (TPG.CTF.IsSupported).
        if math.random() < (TPG.Config.ctfChanceWithinKoth or 0.5)
            and TPG.CTF and TPG.CTF.IsSupported and TPG.CTF.IsSupported() then
            return GAMEMODE_CTF
        end
        return GAMEMODE_KOTH
    elseif roll < 0.4 then
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