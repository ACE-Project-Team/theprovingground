--[[
    Loadout Selection Menu

    The old menu was four scrolling lists of text side by side. It showed
    everything at once, which sounds good until you use it: your own loadout was
    four green rows scattered across four columns, "green" was the only feedback
    a click gave you (so it read as "bought?" rather than "equipped"), and the
    numbers on the right -- a bare "cd", a bare "-15%" -- assumed you already
    knew what the gamemode charges you and in what currency.

    So it's a paperdoll now. One pane shows WHO YOU ARE: the actual player model
    TPG will spawn you in (config/sh_armor.lua picks it from your armor tier),
    with the four slots listed under it holding the names of what you've got.
    That pane is the answer to "what am I taking in". The other pane is the one
    question you're currently asking -- the items for the slot you clicked --
    laid out as icon boxes rather than a list, because a rifle is easier to
    recognise by shape than by which of six ACE naming conventions it uses.

    Everything the server will charge you (config/sh_gear.lua) is still shown up
    front, but spelled out rather than abbreviated, and the panel header says
    which currency this round is even using. Selection remains a preference --
    the charge happens at spawn (player/sv_loadout.lua) -- which is exactly what
    was unclear before, so the menu now says so in words.
]]

local SLOTS = {
    { key = "Primary",   label = "PRIMARY",   cmd = 1, hint = "Your rifle." },
    { key = "Secondary", label = "SECONDARY", cmd = 2, hint = "Sidearm, grenades, binoculars." },
    { key = "Special",   label = "SPECIAL",   cmd = 3, hint = "Launchers and mines. This is your answer to a tank." },
    { key = "Armor",     label = "ARMOR",     cmd = 4, hint = "Sets your health, your armor and how fast you move." },
}

-- Each slot owns a colour, and it's the same colour on the paperdoll row, on
-- the panel header and on the border of every box in the grid. That's what
-- makes a selected box tell you WHICH slot it's selected in -- the old menu's
-- one shade of green couldn't, and position in a column was the only clue.
local function SlotColor(key)
    local C = TPG.Colors
    if key == "Primary"   then return C.Accent end
    if key == "Secondary" then return C.PurpleLight end
    if key == "Special"   then return C.Warn end
    return C.Good
end

local C = TPG.Colors

-- Menu-only shades. The HUD palette has no "row" or "hover" because the HUD
-- has nothing to hover, but they're derived from its panel colour so the menu
-- still reads as the same gamemode.
local MC = {
    bg     = Color(18, 12, 28, 250),
    panel  = Color(28, 19, 44, 255),
    row    = Color(40, 28, 62, 255),
    hover  = Color(56, 40, 86, 255),
}

-- Cooldown ends, keyed the same way the server keys them. Stored as SysTime
-- deadlines built from the relative seconds the server sent, so the two clocks
-- never have to agree.
local cooldownEnds = {}

-- The player's current picks, as the server has them. Panels read this every
-- frame, so a reply that lands after the menu is already open just makes the
-- right things light up rather than needing the menu rebuilt.
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

-- Speed is shown as a signed percentage everywhere, but never bare: "-15%" on
-- its own was one of the numbers nobody could read. It always arrives attached
-- to the words "move speed".
local function SpeedText(bonus)
    if (bonus or 0) == 0 then return nil end
    return (bonus > 0 and "+" or "") .. bonus .. "% move speed"
end

--[[
    The model TPG will actually spawn you in for a given armor tier.

    GetArmorModel randomises the Group01/Group03 citizen skins, which is right
    for a spawn and wrong for a menu -- the paperdoll would reshuffle its face
    every time anything caused a rebuild. Same source of truth, first variant.
]]
local function ArmorModel(armorId)
    local model = TPG.GetArmor(armorId).model
    if string.find(model, "%%d") then return string.format(model, 1) end
    return model
end

--[[
    A world model to draw as this item's picture, or nil if it hasn't got one.

    Not every entry can have a picture and that's fine: "None" is a real choice
    with nothing to show, the virtual "Mines" entry is three SWEPs rather than
    one (so it borrows the first), and a pack SWEP is free to ship a WorldModel
    path that isn't mounted -- which renders as the giant ERROR model and would
    be worse than no icon at all. Hence the file.Exists check.
]]
local function ItemModel(entry)
    if not entry then return nil end

    local class = entry.class
    if not class and entry.multipleClasses then class = entry.multipleClasses[1] end
    if not class then return nil end

    local swep = weapons.GetStored(class)
    local model = swep and swep.WorldModel
    if not model or model == "" then return nil end
    if not file.Exists(model, "GAME") then return nil end
    return model
end

local function Outline(w, h, thickness, color)
    surface.SetDrawColor(color)
    surface.DrawRect(0, 0, w, thickness)
    surface.DrawRect(0, h - thickness, w, thickness)
    surface.DrawRect(0, 0, thickness, h)
    surface.DrawRect(w - thickness, 0, thickness, h)
end

--[[
    What goes in a slot's grid: the selectable items plus everything a box needs
    to draw itself. Armor is a different shape from weapons (numeric ids, a stat
    line, a vehicle-seat restriction), so it's normalised here rather than
    special-cased in the drawing code.
]]
local function BuildItems(slotKey)
    local items = {}

    if slotKey == "Armor" then
        for _, armor in ipairs(TPG.GetArmorList()) do
            local data = TPG.GetArmor(armor.id)
            items[#items + 1] = {
                id     = armor.id,
                kind   = "armor",
                name   = armor.name,
                model  = ArmorModel(armor.id),
                lines  = {
                    data.health .. " health, " .. data.armor .. " armor",
                    SpeedText(data.speedBonus),
                    not data.canUseSeat and "Cannot use vehicle seats" or nil,
                },
                warn   = not data.canUseSeat and "Cannot use vehicle seats" or nil,
            }
        end
        return items
    end

    for _, wep in ipairs(TPG.GetWeaponList(slotKey)) do
        local entry = TPG.GetWeapon(slotKey, wep.id)
        items[#items + 1] = {
            id    = wep.id,
            kind  = "weapon",
            name  = wep.name,
            model = ItemModel(entry),
            lines = { SpeedText(entry and entry.speedBonus) },
        }
    end
    return items
end

-- Name of whatever is currently in a slot, for the paperdoll rows.
local function EquippedName(slotKey)
    if slotKey == "Armor" then
        return TPG.GetArmor(picks.Armor or 1).name
    end
    local entry = TPG.GetWeapon(slotKey, picks[slotKey])
    return entry and entry.name or "None"
end

local function OpenLoadoutMenu()
    -- Ask for fresh cooldowns and the picks the server currently has for us.
    net.Start("TPG_GearRequest")
    net.SendToServer()

    local S = TPG.UI.S

    -- Sized against the screen, not at 940x560: that was wider than a 1280x720
    -- window and a postage stamp on a 4K one.
    local fw = math.min(S(1080), ScrW() * 0.94)
    local fh = math.min(S(660), ScrH() * 0.92)

    local frame = vgui.Create("DFrame")
    frame:SetSize(fw, fh)
    frame:Center()
    frame:SetTitle("")
    -- Derma's close button sits hard against the frame edge, which is what put
    -- it on top of the mode text. Ours is drawn with room around it and the
    -- header text stops short of it by design.
    frame:ShowCloseButton(false)
    frame:SetDraggable(false)
    frame:MakePopup()

    local headH  = S(56)
    local closeS = S(30)
    local closeM = S(13)

    frame.Paint = function(_, w, h)
        draw.RoundedBox(S(8), 0, 0, w, h, MC.bg)
        draw.RoundedBox(0, 0, 0, w, headH, MC.panel)
        draw.RoundedBox(0, 0, headH - math.max(S(2), 1), w, math.max(S(2), 1), C.Purple)
        draw.SimpleText("LOADOUT", "TPG.Menu.Title", S(20), headH / 2, C.Text,
            TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)

        -- Which currency is in force this round, in the player's own terms. The
        -- old header said "TEAM BUDGET - premium gear runs on a cooldown" and
        -- left the player to work out what a cooldown did to them.
        local mode, col
        if TPG.Gear.EconomyActive() then
            mode = "Per-player economy - you have " ..
                LocalPlayer():GetNWInt("TPG_Money", 0) .. " points to spend"
            col  = C.Neutral
        else
            mode = "Team budget round - premium gear is paid for with a cooldown, not points"
            col  = C.TextMuted
        end

        -- Stops well clear of the close button instead of running under it.
        local textRight = w - closeM - closeS - S(18)
        mode = TPG.UI.Truncate(mode, "TPG.Menu.Head", textRight - S(180))
        draw.SimpleText(mode, "TPG.Menu.Head", textRight, headH / 2, col,
            TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
    end

    local close = vgui.Create("DButton", frame)
    close:SetSize(closeS, closeS)
    close:SetPos(fw - closeS - closeM, (headH - closeS) / 2)
    close:SetText("")
    close.Paint = function(self, w, h)
        draw.RoundedBox(S(4), 0, 0, w, h, self:IsHovered() and C.Red or MC.row)
        draw.SimpleText("X", "TPG.Menu.Head", w / 2, h / 2, C.Text,
            TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
    end
    close.DoClick = function() frame:Close() end

    -- ── Footer (docked first: a FILL panel takes whatever is left) ──────────
    local footer = vgui.Create("DPanel", frame)
    footer:Dock(BOTTOM)
    footer:SetTall(S(56))
    footer:DockMargin(S(14), 0, S(14), S(14))
    footer.Paint = function(_, w, h)
        draw.RoundedBox(S(5), 0, 0, w, h, MC.panel)

        local armor = TPG.GetArmor(picks.Armor or 1)
        local bonus = armor.speedBonus
            + (TPG.CalculateSpeedBonus(picks.Primary, picks.Secondary, picks.Special) or 0)
        local speed = TPG.Config.baseSpeedPercent + bonus

        draw.SimpleText(armor.health .. " health    " .. armor.armor .. " armor    " ..
            speed .. "% move speed", "TPG.Menu.Head", S(14), h / 2 - S(9), C.Text,
            TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
        -- The single most important thing the old menu never said.
        draw.SimpleText("Your picks are saved as you click them and take effect the next time you spawn.",
            "TPG.Menu.Small", S(14), h / 2 + S(11), C.TextMuted,
            TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
    end

    local respawn = vgui.Create("DButton", footer)
    respawn:Dock(RIGHT)
    respawn:DockMargin(0, S(9), S(9), S(9))
    respawn:SetWide(S(160))
    respawn:SetText("")
    respawn.Paint = function(self, w, h)
        draw.RoundedBox(S(4), 0, 0, w, h, self:IsHovered() and C.Purple or MC.row)
        draw.SimpleText("RESPAWN NOW", "TPG.Menu.Head", w / 2, h / 2, C.Text,
            TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
    end
    respawn.DoClick = function()
        LocalPlayer():EmitSound("common/wpn_hudoff.wav")
        RunConsoleCommand("kill")
        frame:Close()
    end

    local body = vgui.Create("DPanel", frame)
    body:Dock(FILL)
    body:DockMargin(S(14), headH + S(10), S(14), S(8))
    body.Paint = nil

    local activeSlot = SLOTS[1]
    local RefreshGrid   -- forward declaration; the paperdoll rows call it

    -- ── Left: the paperdoll ────────────────────────────────────────────────
    local doll = vgui.Create("DPanel", body)
    doll:Dock(LEFT)
    doll:SetWide(math.min(S(320), fw * 0.32))
    doll:DockMargin(0, 0, S(10), 0)
    doll.Paint = function(_, w, h)
        draw.RoundedBox(S(5), 0, 0, w, h, MC.panel)
        draw.SimpleText("YOU", "TPG.Menu.Head", S(12), S(10), C.TextMuted)
    end

    -- Slot rows live at the bottom of the pane; the model takes the rest.
    local rows = vgui.Create("DPanel", doll)
    rows:Dock(BOTTOM)
    rows:SetTall(S(4) + #SLOTS * S(46))
    rows:DockMargin(S(10), 0, S(10), S(10))
    rows.Paint = nil

    local model = vgui.Create("DModelPanel", doll)
    model:Dock(FILL)
    model:DockMargin(S(10), S(32), S(10), S(6))
    model:SetFOV(38)
    -- No animation, so the model holds its reference pose: the arms-out stance
    -- the user asked for, and the one that shows the vest.
    model:SetAnimated(false)

    local dollModel
    local function ApplyDollModel()
        local want = ArmorModel(picks.Armor or 1)
        if want == dollModel then return end
        dollModel = want
        model:SetModel(want)

        local ent = model:GetEntity()
        if not IsValid(ent) then return end

        -- Frame the model from its own bounds rather than hardcoded numbers:
        -- these are player models from four different packs and a Combine super
        -- soldier is a good deal taller than a citizen.
        local mins, maxs = ent:GetRenderBounds()
        local height = maxs.z - mins.z
        local centre = Vector(0, 0, mins.z + height * 0.52)
        model:SetLookAt(centre)
        model:SetCamPos(centre + Vector(height * 1.55, 0, height * 0.08))
    end

    -- Hold a fixed three-quarter view. DModelPanel's default LayoutEntity spins
    -- an un-animated model on the spot, which makes a paperdoll you can't read.
    model.LayoutEntity = function(self, ent)
        ent:SetAngles(Angle(0, 205 + math.sin(SysTime() * 0.6) * 12, 0))
    end

    ApplyDollModel()
    model.Think = function()
        ApplyDollModel()
    end

    --[[
        The vest. Clicking the chest opens armor, because that is where a player
        looks for it -- the request was literally "clicking on the person inside
        the menu vest gives you armor options". It's an invisible hotspot rather
        than a drawn control so it doesn't clutter the model; the outline only
        appears on hover, which is what tells you it was clickable at all.
    ]]
    local vest = vgui.Create("DButton", model)
    vest:SetText("")
    vest:SetCursor("hand")
    vest:SetTooltip("Armor")
    vest.PerformLayout = function(self)
        local w, h = model:GetWide(), model:GetTall()
        self:SetSize(w * 0.30, h * 0.20)
        self:SetPos(w * 0.35, h * 0.30)
    end
    vest.Paint = function(self, w, h)
        if not self:IsHovered() then return end
        Outline(w, h, math.max(S(2), 1), SlotColor("Armor"))
        draw.SimpleText("ARMOR", "TPG.Menu.Tiny", w / 2, h + S(4), SlotColor("Armor"),
            TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP)
    end
    vest.DoClick = function()
        surface.PlaySound("buttons/button14.wav")
        activeSlot = SLOTS[4]
        RefreshGrid()
    end

    for _, slot in ipairs(SLOTS) do
        local col = SlotColor(slot.key)

        local row = vgui.Create("DButton", rows)
        row:Dock(TOP)
        row:DockMargin(0, 0, 0, S(4))
        row:SetTall(S(42))
        row:SetText("")
        row.Paint = function(self, w, h)
            local active = (activeSlot.key == slot.key)
            draw.RoundedBox(S(4), 0, 0, w, h,
                active and MC.hover or (self:IsHovered() and MC.hover or MC.row))
            -- The slot's own colour down the edge, so the four rows are told
            -- apart by colour and not just by reading them.
            draw.RoundedBox(0, 0, 0, math.max(S(3), 1), h, col)
            if active then Outline(w, h, math.max(S(2), 1), col) end

            draw.SimpleText(slot.label, "TPG.Menu.Tiny", S(12), S(7), col)
            draw.SimpleText(TPG.UI.Truncate(EquippedName(slot.key), "TPG.Menu.Item", w - S(24)),
                "TPG.Menu.Item", S(12), S(21), C.Text)
        end
        row.DoClick = function()
            surface.PlaySound("buttons/button14.wav")
            activeSlot = slot
            RefreshGrid()
        end
    end

    -- ── Right: the grid for the active slot ────────────────────────────────
    local pane = vgui.Create("DPanel", body)
    pane:Dock(FILL)
    pane.Paint = function(_, w, h)
        draw.RoundedBox(S(5), 0, 0, w, h, MC.panel)
        local col = SlotColor(activeSlot.key)
        draw.RoundedBox(0, S(10), 0, w - S(20), math.max(S(3), 1), col)
        draw.SimpleText(activeSlot.label, "TPG.Menu.Head", S(14), S(12), col)

        --[[
            The plain-language explanation of what this round charges you. "cd"
            in a badge told a player nothing; this says what the badge will
            actually do to them, once, at the top, in the currency in force.
        ]]
        local rule
        if TPG.Gear.EconomyActive() then
            rule = "Marked items cost points from your budget, charged when you spawn with them."
        else
            rule = "Marked items go on a personal cooldown: take one and you spawn with the free equivalent until the timer runs out."
        end
        draw.SimpleText(TPG.UI.Truncate(activeSlot.hint .. "  " .. rule, "TPG.Menu.Small", w - S(28)),
            "TPG.Menu.Small", S(14), S(32), C.TextMuted)
    end

    local scroll = vgui.Create("DScrollPanel", pane)
    scroll:Dock(FILL)
    scroll:DockMargin(S(10), S(52), S(6), S(10))

    -- Docked TOP, not FILL: inside a DScrollPanel the layout has to be free to
    -- grow past the visible height, which is the whole point of the scrollbar.
    -- It wraps to whatever width it's given, so the number of columns follows
    -- the window instead of being a hardcoded four.
    local layout = vgui.Create("DIconLayout", scroll)
    layout:Dock(TOP)
    layout:SetSpaceX(S(8))
    layout:SetSpaceY(S(8))

    local cardW, cardH = S(148), S(132)

    local function MakeCard(item)
        local col = SlotColor(activeSlot.key)
        local slotKey, cmd = activeSlot.key, activeSlot.cmd

        local card = layout:Add("DButton")
        card:SetSize(cardW, cardH)
        card:SetText("")
        card:SetTooltip(item.name)

        -- SpawnIcon renders a cached material of the model, which is what makes
        -- a grid of forty weapons affordable -- a DModelPanel each would render
        -- forty models every frame. Items without a usable model just get the
        -- name, centred, in the space the icon would have used.
        if item.model then
            local icon = vgui.Create("SpawnIcon", card)
            icon:SetModel(item.model)
            icon:SetSize(S(72), S(72))
            icon:SetPos(cardW / 2 - S(36), S(12))
            icon:SetMouseInputEnabled(false)
            icon:SetTooltip(nil)
        end

        card.Paint = function(self, w, h)
            local selected = (picks[slotKey] == item.id)
            local price    = TPG.Gear.Price(item.kind, item.id)
            local left     = price and CooldownLeft(item.kind, item.id) or 0

            draw.RoundedBox(S(5), 0, 0, w, h,
                self:IsHovered() and MC.hover or MC.row)
            Outline(w, h, math.max(selected and S(2) or S(1), 1),
                selected and col or Color(col.r, col.g, col.b, 60))

            local nameY = item.model and (h - S(46)) or (h / 2 - S(20))
            draw.SimpleText(TPG.UI.Truncate(item.name, "TPG.Menu.Item", w - S(14)),
                "TPG.Menu.Item", w / 2, nameY,
                left > 0 and C.TextMuted or C.Text, TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP)

            -- One detail line -- the first stat that changes how you play. A
            -- card this size can hold one, and a second would be the kind of
            -- number-soup the old menu was criticised for.
            local detail = item.lines[1]
            if detail then
                draw.SimpleText(TPG.UI.Truncate(detail, "TPG.Menu.Tiny", w - S(14)),
                    "TPG.Menu.Tiny", w / 2, nameY + S(17), C.TextMuted,
                    TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP)
            end

            -- Price / lock badge, top-left so it never lands on the icon's
            -- silhouette. Says what it means: "300 pts" or "Locked 1:20".
            local badge, badgeCol
            if left > 0 then
                badge, badgeCol = "Locked " .. FormatTime(left), C.Red
            elseif price then
                if TPG.Gear.EconomyActive() then
                    badge, badgeCol = price.cost .. " pts", C.Neutral
                elseif (price.cooldown or 0) > 0 then
                    badge, badgeCol = FormatTime(price.cooldown) .. " cooldown", C.Neutral
                end
            end
            if badge then
                surface.SetFont("TPG.Menu.Tiny")
                local bw, bh = surface.GetTextSize(badge)
                draw.RoundedBox(S(3), S(6), S(6), bw + S(10), bh + S(4), Color(0, 0, 0, 170))
                draw.SimpleText(badge, "TPG.Menu.Tiny", S(11), S(8), badgeCol)
            end

            -- "Did I purchase it or not" -- the answer, in words, on the item.
            if selected then
                local stripH = S(18)
                draw.RoundedBox(0, 0, h - stripH, w, stripH, col)
                TPG.UI.TextInBox("EQUIPPED", "TPG.Menu.Tiny", 0, h - stripH, w, stripH,
                    C.Contrast(col))
            end
        end

        card.DoClick = function()
            surface.PlaySound("buttons/button14.wav")
            picks[slotKey] = item.id
            RunConsoleCommand("tpg_loadout", cmd, tostring(item.id))

            if item.warn then
                chat.AddText(C.Red, "[TPG] " .. item.name .. ": " .. item.warn)
            end
        end
    end

    RefreshGrid = function()
        layout:Clear()
        for _, item in ipairs(BuildItems(activeSlot.key)) do
            MakeCard(item)
        end
    end

    RefreshGrid()
end

concommand.Add("tpg_menu_loadout", OpenLoadoutMenu)
