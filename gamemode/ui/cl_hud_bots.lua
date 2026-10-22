--[[--
    Friendly bot markers: a small diamond over each NPC bot on the local
    player's team, so teammates are easy to pick out at range. Bots are the
    `npc_*` entities that carry the `TPG_BotTeam` network int (sv_bots.lua).

    The bot list is cached once a second rather than searched every frame.
    Markers fade from 140 alpha up close to 40 at 4000 units. A bot off screen
    gets no marker. Nothing is traced, so walls do not hide a marker, and the
    check stays cheap however many bots there are.

    Q-menu toggle: `tpg_hud_bots` (Utilities > The Proving Ground > Player).

    Exports nothing.

    @module tpg.hud.bots
    @realm client
]]

local MAX_DIST     = 4000   -- units; no marker beyond this
local NEAR_ALPHA   = 140
local FAR_ALPHA    = 40
local MARKER_LIFT  = 80     -- units above the bot's origin, roughly over the head
local MARKER_SIZE  = 5      -- half-width of the diamond, px
local CACHE_EVERY  = 1      -- seconds between bot list refreshes

CreateClientConVar("tpg_hud_bots", "1", true, false,
    "Show a marker over friendly bots. 0 = hidden.", 0, 1)

local friendly  = {}
local nextScan  = 0

-- Rebuild the list of bots on the local player's team.
local function scanBots()
    friendly = {}
    local me = LocalPlayer()
    if not IsValid(me) then return end

    local team = me:Team()
    for _, ent in ipairs(ents.FindByClass("npc_*")) do
        if ent:GetNWInt("TPG_BotTeam", 0) == team then
            friendly[#friendly + 1] = ent
        end
    end
end

hook.Add("HUDPaint", "TPG_BotMarkers", function()
    if GetConVar("tpg_hud_bots"):GetInt() == 0 then return end

    local me = LocalPlayer()
    if not IsValid(me) or not TPG.Util.IsOnTeam(me) then return end

    local now = CurTime()
    if now >= nextScan then
        nextScan = now + CACHE_EVERY
        scanBots()
    end

    local col    = team.GetColor(me:Team())
    local origin = me:GetPos()

    for _, ent in ipairs(friendly) do
        -- NPC health is not networked, so Health() reads 0 here. A dead bot
        -- is removed (its corpse is a separate ragdoll), so IsValid is enough.
        if IsValid(ent) then
            local pos  = ent:GetPos()
            local dist = pos:Distance(origin)

            if dist <= MAX_DIST then
                local sp = (pos + Vector(0, 0, MARKER_LIFT)):ToScreen()
                if sp.visible then
                    local alpha = Lerp(dist / MAX_DIST, NEAR_ALPHA, FAR_ALPHA)
                    local x, y, s = sp.x, sp.y, MARKER_SIZE

                    surface.SetDrawColor(col.r, col.g, col.b, alpha)
                    surface.DrawPoly({
                        { x = x,     y = y - s },
                        { x = x + s, y = y     },
                        { x = x,     y = y + s },
                        { x = x - s, y = y     },
                    })
                end
            end
        end
    end
end)
