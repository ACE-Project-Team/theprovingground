--[[
    Premium Gear (server)

    Charges for the items listed in config/sh_gear.lua and tells the client what
    it's allowed to take. Nothing here decides what an item costs -- that's the
    config -- this only enforces it and reports it.

    Cooldowns run on CurTime and are stored per player (and stashed across a
    reconnect in core/sv_gamestate.lua, so dropping out isn't a way to clear
    one). They are NOT reset between rounds: a cooldown is a rate limit on a
    strong item, and a round boundary landing mid-cooldown shouldn't hand
    everyone a free Javelin.
]]

TPG.Gear = TPG.Gear or {}

util.AddNetworkString("TPG_GearState")     -- server -> client (cooldowns)
util.AddNetworkString("TPG_GearRequest")   -- client -> server (menu opened)

-- Seconds left on an item, or 0 if it's ready.
function TPG.Gear.Remaining(ply, kind, id)
    if not IsValid(ply) then return 0 end
    local cds = TPG.State.GetPlayer(ply).gearCooldowns
    if not cds then return 0 end
    return math.max((cds[TPG.Gear.Key(kind, id)] or 0) - CurTime(), 0)
end

--[[
    Take an item, paying whatever this round's price is.

    Returns true on success. On failure returns false plus a reason
    ("cooldown" / "afford") and the number that goes with it (seconds left, or
    the cost), so the caller can say something useful instead of "denied".

    Free items always succeed and cost nothing, so callers can run every pick
    through here without checking first.
]]
function TPG.Gear.Claim(ply, kind, id)
    if not IsValid(ply) then return false, "invalid", 0 end

    local price = TPG.Gear.Price(kind, id)
    if not price then return true end

    -- Per-player economy: pay points, no cooldown.
    if TPG.Economy and TPG.Economy.Active then
        local cost = price.cost or 0
        if cost <= 0 then return true end
        if not TPG.Economy.Charge(ply, cost, "gear") then
            return false, "afford", cost
        end
        return true
    end

    -- Team budget: pay time.
    local cooldown = price.cooldown or 0
    if cooldown <= 0 then return true end

    local left = TPG.Gear.Remaining(ply, kind, id)
    if left > 0 then return false, "cooldown", left end

    local pState = TPG.State.GetPlayer(ply)
    pState.gearCooldowns = pState.gearCooldowns or {}
    pState.gearCooldowns[TPG.Gear.Key(kind, id)] = CurTime() + cooldown
    return true
end

-- Push the player's live cooldowns, plus the picks the server actually has on
-- record, so the menu shows what they're really set to rather than what they
-- last clicked in this session. Expired cooldowns are dropped on the way out,
-- which is also the only cleanup that table ever needs.
function TPG.Gear.Sync(ply)
    if not IsValid(ply) then return end

    local pState = TPG.State.GetPlayer(ply)
    local cds    = pState.gearCooldowns or {}
    local live   = {}

    for key, ends in pairs(cds) do
        if ends > CurTime() then
            live[key] = ends
        else
            cds[key] = nil
        end
    end

    local dl = TPG.WeaponConfig.DefaultLoadout

    local function pick(key, default)
        local v = TPG.Util.GetPData(ply, key, default)
        return isstring(v) and v or default
    end

    net.Start("TPG_GearState")
        net.WriteUInt(table.Count(live), 8)
        for key, ends in pairs(live) do
            net.WriteString(key)
            net.WriteFloat(ends - CurTime())   -- relative: client clocks differ
        end

        net.WriteString(pick("Primary",   dl.Primary))
        net.WriteString(pick("Secondary", dl.Secondary))
        net.WriteString(pick("Special",   dl.Special))
        net.WriteUInt(math.Clamp(tonumber(TPG.Util.GetPData(ply, "Armor", 1)) or 1, 0, 255), 8)
    net.Send(ply)
end

net.Receive("TPG_GearRequest", function(_, ply)
    TPG.Gear.Sync(ply)
end)
