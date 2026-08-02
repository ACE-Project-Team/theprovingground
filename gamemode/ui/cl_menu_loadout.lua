--[[
    Loadout Selection Menu

    Four columns, one per slot, because the interesting question is "what does
    this cost me and what do I give up", and four dropdowns could only answer it
    one slot at a time -- you couldn't see your own loadout without opening every
    box in turn, and nothing told you an item was premium until you spawned
    without it.

    Everything the server will charge you (config/sh_gear.lua) is shown up front:
    the price under the economy, the cooldown otherwise, and a live countdown on
    anything you can't take yet. Selection is still just a preference -- the
    charge happens at spawn (player/sv_loadout.lua) -- so the menu never has to
    ask the server whether a click is allowed.
]]

local COLS = {
    { key = "Primary",   label = "PRIMARY",   cmd = 1 },
    { key = "Secondary", label = "SECONDARY", cmd = 2 },
    { key = "Special",   label = "SPECIAL",   cmd = 3 },
    { key = "Armor",     label = "ARMOR",     cmd = 4 },
}

local C = {
    bg       = Color(24, 26, 30),
    panel    = Color(32, 35, 40),
    row      = Color(41, 45, 52),
    rowHover = Color(54, 59, 68),
    rowSel   = Color(62, 74, 62),
    text     = Color(226, 230, 235),
    dim      = Color(140, 148, 158),
    gold     = Color(226, 184, 90),
    locked   = Color(214, 110, 90),
    good     = Color(140, 210, 130),
}

surface.CreateFont("TPG_LoadoutTitle", { font = "Roboto", size = 22, weight = 700 })
surface.CreateFont("TPG_LoadoutHead",  { font = "Roboto", size = 15, weight = 700 })
surface.CreateFont("TPG_LoadoutItem",  { font = "Roboto", size = 16, weight = 500 })
surface.CreateFont("TPG_LoadoutSmall", { font = "Roboto", size = 13, weight = 500 })

-- Cooldown ends, keyed the same way the server keys them. Stored as SysTime
-- deadlines built from the relative seconds the server sent, so the two clocks
-- never have to agree.
local cooldownEnds = {}

-- The player's current picks, as the server has them. Rows read this every
-- frame, so a reply that lands after the menu is already open just makes the
-- right rows light up rather than needing the menu rebuilt.
local picks = {}

net.Receive("TPG_GearState", function()
    cooldownEnds = {}
    for _ = 1, net.ReadUInt(8) do
        local key = net.ReadString()
        cooldownEnds[key] = SysTime() + net.ReadFloat()
    end

    picks.Primary   = net.ReadString()
    picks.Secondary = net.ReadString()
    picks.Special   = net.ReadString()
    picks.Armor     = net.ReadUInt(8)
end)

local function CooldownLeft(kind, id)
    local ends = cooldownEnds[TPG.Gear.Key(kind, id)]
    if not ends then return 0 end
    return math.max(ends - SysTime(), 0)
end

local function FormatTime(seconds)
    seconds = math.ceil(seconds)
    if seconds < 60 then return seconds .. "s" end
    return string.format("%d:%02d", math.floor(seconds / 60), seconds % 60)
end

--[[
    What goes in a column: the selectable items plus everything the row needs to
    draw itself. Armor is a different shape from weapons (numeric ids, stat line
    instead of a speed bonus), so it's normalised here rather than special-cased
    three times further down.
]]
local function BuildItems(colKey)
    local items = {}

    if colKey == "Armor" then
        for _, armor in ipairs(TPG.GetArmorList()) do
            local data = TPG.GetArmor(armor.id)
            items[#items + 1] = {
                id      = armor.id,
                kind    = "armor",
                name    = armor.name,
                detail  = data.health .. " HP  " .. data.armor .. " AP",
                speed   = data.speedBonus,
                warn    = not data.canUseSeat and "no vehicle seats" or nil,
            }
        end
        return items
    end

    for _, wep in ipairs(TPG.GetWeaponList(colKey)) do
        local entry = TPG.GetWeapon(colKey, wep.id)
        items[#items + 1] = {
            id     = wep.id,
            kind   = "weapon",
            name   = wep.name,
            speed  = entry and entry.speedBonus or 0,
        }
    end
    return items
end

-- One selectable item. Draws its own price/cooldown badge and keeps the
-- countdown live without a timer.
local function MakeRow(parent, item, selected, onPick)
    local row = vgui.Create("DButton", parent)
    row:Dock(TOP)
    row:DockMargin(0, 0, 0, 3)
    row:SetTall(item.detail and 40 or 30)
    row:SetText("")

    row.DoClick = function()
        surface.PlaySound("buttons/button14.wav")
        onPick(item)
    end

    row.Paint = function(self, w, h)
        local isSel  = selected() == item.id
        local price  = TPG.Gear.Price(item.kind, item.id)
        local left   = price and CooldownLeft(item.kind, item.id) or 0

        draw.RoundedBox(4, 0, 0, w, h,
            isSel and C.rowSel or (self:IsHovered() and C.rowHover or C.row))

        if isSel then
            surface.SetDrawColor(C.good)
            surface.DrawRect(0, 0, 3, h)
        end

        local textCol = left > 0 and C.dim or C.text
        draw.SimpleText(item.name, "TPG_LoadoutItem", 10, item.detail and 6 or h / 2 - 8,
            textCol)

        if item.detail then
            draw.SimpleText(item.detail, "TPG_LoadoutSmall", 10, 22, C.dim)
        end

        -- Badge: what this costs, or how long until you can have it.
        local badge, badgeCol
        if left > 0 then
            badge, badgeCol = FormatTime(left), C.locked
        elseif price then
            if TPG.Gear.EconomyActive() then
                badge, badgeCol = price.cost .. " pts", C.gold
            elseif (price.cooldown or 0) > 0 then
                badge, badgeCol = FormatTime(price.cooldown) .. " cd", C.gold
            end
        end

        if badge then
            draw.SimpleText(badge, "TPG_LoadoutSmall", w - 10, item.detail and 6 or h / 2 - 7,
                badgeCol, TEXT_ALIGN_RIGHT)
        end

        if item.warn then
            draw.SimpleText(item.warn, "TPG_LoadoutSmall", w - 10, 22, C.locked, TEXT_ALIGN_RIGHT)
        elseif (item.speed or 0) ~= 0 and not item.detail then
            local s = (item.speed > 0 and "+" or "") .. item.speed .. "%"
            draw.SimpleText(s, "TPG_LoadoutSmall", w - (badge and 70 or 10), h / 2 - 7,
                item.speed > 0 and C.good or C.dim, TEXT_ALIGN_RIGHT)
        end
    end

    return row
end

local function OpenLoadoutMenu()
    -- Ask for fresh cooldowns and the picks the server currently has for us.
    net.Start("TPG_GearRequest")
    net.SendToServer()

    local frame = vgui.Create("DFrame")
    frame:SetSize(940, 560)
    frame:Center()
    frame:SetTitle("")
    frame:ShowCloseButton(true)
    frame:SetDraggable(false)
    frame:MakePopup()
    frame.Paint = function(_, w, h)
        draw.RoundedBox(6, 0, 0, w, h, C.bg)
        draw.RoundedBox(0, 0, 0, w, 46, C.panel)
        draw.SimpleText("LOADOUT", "TPG_LoadoutTitle", 18, 12, C.text)

        -- Which price is in force right now, in the player's own terms.
        local mode, col
        if TPG.Gear.EconomyActive() then
            mode = "ECONOMY  -  " .. LocalPlayer():GetNWInt("TPG_Money", 0) .. " pts"
            col  = C.gold
        else
            mode = "TEAM BUDGET  -  premium gear runs on a cooldown"
            col  = C.dim
        end
        draw.SimpleText(mode, "TPG_LoadoutHead", w - 46, 16, col, TEXT_ALIGN_RIGHT)
    end

    -- Footer first: a FILL panel claims whatever is left, so it has to be the
    -- last thing docked or it eats the footer's row.
    local footer = vgui.Create("DPanel", frame)
    footer:Dock(BOTTOM)
    footer:SetTall(52)
    footer:DockMargin(12, 0, 12, 12)
    footer.Paint = function(_, w, h)
        draw.RoundedBox(4, 0, 0, w, h, C.panel)

        local armor = TPG.GetArmor(picks.Armor or 1)
        local bonus   = armor.speedBonus
            + (TPG.CalculateSpeedBonus(picks.Primary, picks.Secondary, picks.Special) or 0)
        local speed   = TPG.Config.baseSpeedPercent + bonus

        draw.SimpleText(
            armor.health .. " HP    " .. armor.armor .. " AP    " .. speed .. "% speed",
            "TPG_LoadoutHead", 14, h / 2 - 8, C.text)
    end

    local respawn = vgui.Create("DButton", footer)
    respawn:Dock(RIGHT)
    respawn:DockMargin(0, 8, 8, 8)
    respawn:SetWide(150)
    respawn:SetText("")
    respawn.Paint = function(self, w, h)
        draw.RoundedBox(4, 0, 0, w, h, self:IsHovered() and C.rowHover or C.row)
        draw.SimpleText("RESPAWN", "TPG_LoadoutHead", w / 2, h / 2 - 8, C.text, TEXT_ALIGN_CENTER)
    end
    respawn.DoClick = function()
        LocalPlayer():EmitSound("common/wpn_hudoff.wav")
        RunConsoleCommand("kill")
        frame:Close()
    end

    local body = vgui.Create("DPanel", frame)
    body:Dock(FILL)
    body:DockMargin(12, 52, 12, 8)
    body.Paint = nil

    -- Columns.
    local colWide = (940 - 24 - 3 * 8) / 4

    for _, col in ipairs(COLS) do
        local panel = vgui.Create("DPanel", body)
        panel:Dock(LEFT)
        panel:SetWide(colWide)
        panel:DockMargin(0, 0, 8, 0)
        panel.Paint = function(_, w, h)
            draw.RoundedBox(4, 0, 0, w, h, C.panel)
            draw.SimpleText(col.label, "TPG_LoadoutHead", 10, 10, C.dim)
        end

        local scroll = vgui.Create("DScrollPanel", panel)
        scroll:Dock(FILL)
        scroll:DockMargin(8, 32, 8, 8)

        local function selected() return picks[col.key] end

        for _, item in ipairs(BuildItems(col.key)) do
            MakeRow(scroll, item, selected, function(picked)
                picks[col.key] = picked.id
                RunConsoleCommand("tpg_loadout", col.cmd, tostring(picked.id))

                if picked.kind == "armor" and picked.warn then
                    chat.AddText(C.locked, "[TPG] " .. picked.name ..
                        " cannot use vehicle seats.")
                end
            end)
        end
    end
end

concommand.Add("tpg_menu_loadout", OpenLoadoutMenu)
