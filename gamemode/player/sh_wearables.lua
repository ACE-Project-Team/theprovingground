--[[
    TPG's extra ACE wearable slots, registered shared.

    The slot table lives in ACE (ACE.Wearables.Slots) and is read on both
    realms - the server resolves bullet paths against it, the client
    bonemerges every entry a player wears. TPG adds its slot here rather than
    in ACE so the gamemode's tuning stays out of the addon.

    ACE loads from autorun before the gamemode, so the table exists by the
    time this file runs. If it doesn't (ACE missing or wearables disabled),
    TPG.Wearables.Available already reports false and nothing equips.
]]

if ACE and ACE.Wearables and ACE.Wearables.Slots then
    ACE.Wearables.Slots.helmet_heavy = {
        Model = "models/ace/wearables/helmet.mdl",
        Bone  = "ValveBiped.Bip01_Head1",
        Fit   = { ["ValveBiped.Bip01_Head1"] = "Head" },
        Shape = "Shell",
        -- Twice the plate and twice the energy budget of the base helmet
        Durability = 6000,
        BreakSound = "physics/plastic/plastic_box_break2.wav",
        Layers = {
            -- Double-thick aramid shell, about 10.8 mm RHA square on: rifle ball stops
            -- mattering except up close; AP and magnum loads still punch through on the
            -- first hit. Same high cut as the base helmet, so the face is open either way.
            [HITGROUP_HEAD] = { Coverage = 0.7, { Material = "Aramid", Armour = 20 } },
        },
    }
end
