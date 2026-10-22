--[[--
    Bot corpse cleanup. NPC corpses are client-side ragdolls, which the
    server's SF_NPC_FADE_CORPSE spawnflag never reaches, so with
    `tpg_bots_corpses` off they piled up for good. A bot spawned with that
    convar off carries the `TPG_FadeCorpse` network bool (sv_bots.lua), and
    its ragdoll fades out a few seconds after death.

    Exports nothing.

    @module tpg.bots.corpses
    @realm client
]]

local FADE_DELAY = 5 -- seconds a corpse stays before it starts fading

hook.Add("CreateClientsideRagdoll", "TPG_BotCorpses", function(ent, rag)
    if not IsValid(ent) or not ent:GetNWBool("TPG_FadeCorpse", false) then return end

    timer.Simple(FADE_DELAY, function()
        if IsValid(rag) then rag:SetSaveValue("m_bFadingOut", true) end
    end)
end)
