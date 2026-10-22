--[[--
    Bot corpse cleanup. NPC corpses are client-side ragdolls, which the
    server's SF_NPC_FADE_CORPSE spawnflag never reaches, so with
    `tpg_bots_corpses` off they piled up for good. A bot spawned with that
    convar off carries the `TPG_FadeCorpse` network bool (sv_bots.lua), and
    its ragdoll fades out a few seconds after death. Server ragdolls (with
    ai_serverragdolls on) are faded by sv_bots.lua instead.

    Exports nothing.

    @module tpg.bots.corpses
    @realm client
]]

local FADE_DELAY = 5   -- seconds a corpse stays before it starts fading
local FADE_TIME  = 1   -- seconds the fade takes
local FADE_STEP  = 0.05

hook.Add("CreateClientsideRagdoll", "TPG_BotCorpses", function(ent, rag)
    if not IsValid(ent) or not ent:GetNWBool("TPG_FadeCorpse", false) then return end

    -- Faded by hand: m_bFadingOut can't be relied on from Lua on the client.
    timer.Simple(FADE_DELAY, function()
        if not IsValid(rag) then return end
        rag:SetRenderMode(RENDERMODE_TRANSCOLOR)

        local steps = math.Round(FADE_TIME / FADE_STEP)
        local n = 0
        timer.Create("TPG_BotCorpse" .. tostring(rag), FADE_STEP, steps, function()
            if not IsValid(rag) then return end
            n = n + 1
            if n >= steps then
                rag:Remove()
            else
                rag:SetColor(Color(255, 255, 255, 255 * (1 - n / steps)))
            end
        end)
    end)
end)
