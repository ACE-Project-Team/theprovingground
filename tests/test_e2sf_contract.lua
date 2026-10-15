--[[
    What the E2/Starfall addon (tpg_e2sf) reads from TPG.

    That addon lives in its own repository and ships on its own, so nothing
    stops TPG renaming something it depends on -- and none of it would error.
    Every read on the other side has a fallback: a missing armour tier shows
    as "Unknown", a renamed PData key as "", a missing team as "not on a
    team". The chip keeps running and quietly reports nothing. These tests
    are the other half of that contract, so the rename fails here instead.

    The full list of what it touches:

        TEAM_GREEN, TEAM_RED                   the own-team gate
        TPG.GetTeamData(t).name                tpgTeamName / getTeamName
        TPG.Armor[id].name                     armour display name
        PData "TPG_Armor", default 1           armour tier id
        PData "TPG_Primary" / "TPG_Secondary" / "TPG_Special"
                                               teammate loadout

    The PData keys are spelled out with their prefix on the addon side; it
    cannot call TPG.Util.GetPData, because it has to work in plain sandbox
    where TPG never loads. So the prefix is part of the contract too.
]]

local gmod = expect.load.gmod

describe("e2sf contract: teams")

it("exposes both team ids as distinct numbers", function()
    expect.eq(type(TEAM_GREEN), "number")
    expect.eq(type(TEAM_RED), "number")
    expect.ne(TEAM_GREEN, TEAM_RED)
end)

it("names both teams through GetTeamData", function()
    for _, t in ipairs({ TEAM_GREEN, TEAM_RED }) do
        local data = TPG.GetTeamData(t)
        expect.eq(type(data), "table")
        expect.eq(type(data.name), "string")
        expect.ne(data.name, "", "an empty name reads as 'not on a team' to a chip")
    end
end)

describe("e2sf contract: armour")

it("names every armour tier", function()
    for id, tier in pairs(TPG.Armor) do
        expect.eq(type(tier.name), "string", "tier " .. tostring(id))
    end
end)

it("has a real tier at the addon's default id", function()
    -- The addon reads GetPData("TPG_Armor", 1); a player who never chose
    -- comes back as 1, which has to be a tier rather than "Unknown".
    expect.truthy(TPG.Armor[1], "tier 1 is the addon's default")
end)

describe("e2sf contract: what is stored where")

it("stores armour under TPG_Armor as a number the addon can index with", function()
    local ply = gmod.player(TEAM_GREEN)
    TPG.Util.SetPData(ply, "Armor", 3)
    local raw = ply:GetPData("TPG_Armor", 1)
    expect.truthy(TPG.Armor[tonumber(raw)], "TPG_Armor = " .. tostring(raw))
end)

it("stores loadout picks under TPG_<category>", function()
    local ply = gmod.player(TEAM_GREEN)
    for _, cat in ipairs({ "Primary", "Secondary", "Special" }) do
        TPG.Util.SetPData(ply, cat, "weapon_x")
        expect.eq(ply:GetPData("TPG_" .. cat, ""), "weapon_x", cat)
    end
end)

it("still calls its loadout categories Primary, Secondary and Special", function()
    -- These names are what the loadout command stores PData under, so they
    -- are the keys the addon has to ask for. Pin them through the real
    -- category tables rather than a copied list.
    TPG.Weapons.Discover()
    for _, cat in ipairs({ "Primary", "Secondary", "Special" }) do
        expect.eq(type(TPG.Weapons[cat]), "table", cat .. " is not a loadout category")
    end
end)
