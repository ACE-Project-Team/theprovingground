--[[
    Capture the Flag (one neutral flag)

    CTF is only available on maps that define a KOTH point; the single flag
    spawns on that point. Whoever carries it drains the enemy's tickets, so the
    win resolves through the normal ticket check -- no base delivery, no spawns
    used as objectives. Admins can override the flag spot with the point tool.

    Per-flag mechanics (pickup / drop / return / drain) live on the tpg_flag
    entity; this module owns spawning and home resolution.
]]

TPG.CTF = TPG.CTF or {}
TPG.CTF.Flag = nil

-- Does the current map support CTF? (i.e. is there a KOTH point to host it?)
function TPG.CTF.IsSupported()
    return TPG.CTF.GetFlagPoint() ~= nil
end

-- Resolve the flag's home: a custom-placed CTF point, else the map's KOTH point.
function TPG.CTF.GetFlagPoint()
    local custom = TPG.Maps.GetCustomFlagPoint and TPG.Maps.GetCustomFlagPoint()
    if custom then return custom end

    local koth = TPG.Maps.Get()[GAMEMODE_KOTH]
    local objs = koth and koth.objectives
    if objs and objs[1] then return objs[1].pos end

    return nil
end

function TPG.CTF.Cleanup()
    if IsValid(TPG.CTF.Flag) then TPG.CTF.Flag:Remove() end
    TPG.CTF.Flag = nil
end

function TPG.CTF.SpawnFlags()
    TPG.CTF.Cleanup()
    if TPG.State.gameType ~= GAMEMODE_CTF then return end

    local point = TPG.CTF.GetFlagPoint()
    if not point then
        print("[TPG] CTF: no KOTH point on this map, cannot spawn flag")
        return
    end

    local pos  = point + Vector(0, 0, 5)
    local flag = ents.Create("tpg_flag")
    if not IsValid(flag) then return end

    flag.HomePos = pos
    flag:SetPos(pos)
    flag:Spawn()
    flag:SetHome(pos)

    TPG.CTF.Flag = flag
    print("[TPG] CTF: spawned the flag")
end
