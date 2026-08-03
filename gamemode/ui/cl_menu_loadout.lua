--[[
    Loadout Selection Menu

    A paperdoll and a grid. One pane shows WHO YOU ARE: the actual player model
    TPG will spawn you in (config/sh_armor.lua picks it from your armor tier),
    with the four slots under it holding what you've got. The other pane shows
    the one question you're currently asking -- the items for the slot you
    clicked -- as icon boxes, because a rifle is easier to recognise by shape
    than by which of six ACE naming conventions its name follows.

    Two rules the drawing code follows, both learned the hard way:

      Paint runs every frame, for every card on screen, so NOTHING that can be
      worked out in advance happens in there. Truncating a string costs a
      surface.GetTextSize per character tried; forty cards doing that (plus a
      price-table lookup each) every frame is what turned this menu into a
      framerate problem. Everything static is resolved once, at build time, into
      the card's own table; Paint only reads it and the live cooldown.

      The grid is laid out by hand rather than by DIconLayout. A DIconLayout
      docked inside a DScrollPanel sizes itself to its children, which resizes
      the canvas, which re-runs the layout -- a loop that can run every frame.
      Column count comes from arithmetic on a known width instead.
]]

local SLOTS = {
    { key = "Primary",   label = "PRIMARY",   cmd = 1, hint = "Your rifle." },
    { key = "Secondary", label = "SECONDARY", cmd = 2, hint = "Sidearm, grenades, binoculars." },
    { key = "Special",   label = "SPECIAL",   cmd = 3, hint = "Launchers and mines. This is your answer to a tank." },
    { key = "Armor",     label = "ARMOR",     cmd = 4, hint = "Sets your health, your armor and how fast you move." },
}

-- Each slot owns a colour, and it's the same colour on the paperdoll row, on
-- the panel header and on the border of every box in the grid. That's what
-- makes a selected box tell you WHICH slot it's selected in.
local function SlotColor(key)
    local C = TPG.Colors
    if key == "Primary"   then return C.Accent end
    if key == "Secondary" then return C.PurpleLight end
    if key == "Special"   then return C.Warn end
    return C.Good
end

local C = TPG.Colors

-- Menu-only shades, derived from the HUD's panel colour so the menu still reads
-- as the same gamemode. The HUD has no "hover" because it has nothing to hover.
local MC = {
    bg     = Color(18, 12, 28, 250),
    panel  = Color(28, 19, 44, 255),
    row    = Color(40, 28, 62, 255),
    hover  = Color(56, 40, 86, 255),
    sunken = Color(22, 15, 36, 255),
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
                group  = nil,
                model  = ArmorModel(armor.id),
                detail = data.health .. " health, " .. data.armor .. " armor",
                extra  = SpeedText(data.speedBonus),
                warn   = not data.canUseSeat and "Cannot use vehicle seats" or nil,
            }
        end
        return items
    end

    for _, wep in ipairs(TPG.GetWeaponList(slotKey)) do
        local entry = TPG.GetWeapon(slotKey, wep.id)
        items[#items + 1] = {
            id     = wep.id,
            kind   = "weapon",
            name   = wep.name,
            -- SWEP.SubCategory, carried through discovery. It's what the tab
            -- strip groups by, so a 40-entry Primary list stops being a scroll.
            group  = entry and entry.subCategory,
            model  = ItemModel(entry),
            detail = SpeedText(entry and entry.speedBonus),
            -- "how many will I get" -- worked out by the same rule the server
            -- hands them out with (config/sh_weapons.lua).
            extra  = entry and entry.rounds and (entry.rounds .. " rounds") or nil,
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
    local fw = math.min(S(1180), ScrW() * 0.94)
    local fh = math.min(S(720), ScrH() * 0.92)

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

    local headH  = S(58)
    local closeS = S(32)
    local closeM = S(14)

    -- Resolved once: the header line is static for as long as the menu is open
    -- apart from the wallet figure, and re-truncating it 60 times a second was
    -- pure waste.
    local headerFits = fw - closeM - closeS - S(18) - S(200)

    frame.Paint = function(_, w, h)
        draw.RoundedBox(S(8), 0, 0, w, h, MC.bg)
        draw.RoundedBox(0, 0, 0, w, headH, MC.panel)
        draw.RoundedBox(0, 0, headH - math.max(S(2), 1), w, math.max(S(2), 1), C.Purple)
        draw.SimpleText("LOADOUT", "TPG.Menu.Title", S(20), headH / 2, C.Text,
            TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)

        -- Which currency is in force this round, in the player's own terms.
        local mode, col
        if TPG.Gear.EconomyActive() then
            mode = "Per-player economy - you have " ..
                LocalPlayer():GetNWInt("TPG_Money", 0) .. " points to spend"
            col  = C.Neutral
        else
            mode = "Team budget round - premium gear is paid for with a cooldown, not points"
            col  = C.TextMuted
        end

        draw.SimpleText(TPG.UI.Truncate(mode, "TPG.Menu.Head", headerFits), "TPG.Menu.Head",
            w - closeM - closeS - S(18), headH / 2, col, TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
    end

    local close = vgui.Create("DButton", frame)
    close:SetSize(closeS, closeS)
    close:SetPos(fw - closeS - closeM, (headH - closeS) / 2)
    close:SetText("")
    close.Paint = function(self, w, h)
        draw.RoundedBox(S(4), 0, 0, w, h, self:IsHovered() and C.Red or MC.row)
        TPG.UI.TextInBox("X", "TPG.Menu.Head", 0, 0, w, h, C.Text)
    end
    close.DoClick = function() frame:Close() end

    -- ── Footer (docked first: a FILL panel takes whatever is left) ──────────
    local footer = vgui.Create("DPanel", frame)
    footer:Dock(BOTTOM)
    footer:SetTall(S(58))
    footer:DockMargin(S(14), 0, S(14), S(14))
    footer.Paint = function(_, w, h)
        draw.RoundedBox(S(5), 0, 0, w, h, MC.panel)

        local armor = TPG.GetArmor(picks.Armor or 1)
        local bonus = armor.speedBonus
            + (TPG.CalculateSpeedBonus(picks.Primary, picks.Secondary, picks.Special) or 0)
        local speed = TPG.Config.baseSpeedPercent + bonus

        draw.SimpleText(armor.health .. " health    " .. armor.armor .. " armor    " ..
            speed .. "% move speed", "TPG.Menu.Head", S(14), h / 2 - S(10), C.Text,
            TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
        draw.SimpleText("Picks are saved as you click them and take effect the next time you spawn.",
            "TPG.Menu.Small", S(14), h / 2 + S(12), C.TextMuted,
            TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
    end

    local respawn = vgui.Create("DButton", footer)
    respawn:Dock(RIGHT)
    respawn:DockMargin(0, S(9), S(9), S(9))
    respawn:SetWide(S(200))
    respawn:SetText("")
    respawn:SetTooltip("Doesn't count as a death, and doesn't re-charge you for gear you already bought this life.")
    respawn.Paint = function(self, w, h)
        draw.RoundedBox(S(4), 0, 0, w, h, self:IsHovered() and C.Purple or MC.row)
        TPG.UI.TextInBox("RESPAWN NOW", "TPG.Menu.Head", 0, 0, w, h, C.Text)
    end
    respawn.DoClick = function()
        LocalPlayer():EmitSound("common/wpn_hudoff.wav")
        -- tpg_rekit, not `kill`: see core/sv_commands.lua. Plain suicide put a
        -- death on your record and billed you twice for premium gear.
        RunConsoleCommand("tpg_rekit")
        frame:Close()
    end

    local body = vgui.Create("DPanel", frame)
    body:Dock(FILL)
    body:DockMargin(S(14), headH + S(10), S(14), S(8))
    body.Paint = nil

    local activeSlot = SLOTS[1]
    local activeGroup = nil      -- subcategory filter, nil = all
    local searchText  = ""
    local RefreshGrid, RefreshTabs   -- forward declarations

    -- Widths are arithmetic, not measured: docking hasn't happened yet when the
    -- grid is first built, so asking a panel how wide it is would return zero.
    local bodyW = fw - S(28)
    local dollW = math.min(S(330), bodyW * 0.30)
    local paneW = bodyW - dollW - S(10)
    local gridW = paneW - S(10) - S(6) - S(18)   -- margins + scrollbar

    -- ── Left: the paperdoll ────────────────────────────────────────────────
    local doll = vgui.Create("DPanel", body)
    doll:Dock(LEFT)
    doll:SetWide(dollW)
    doll:DockMargin(0, 0, S(10), 0)
    doll.Paint = function(_, w, h)
        draw.RoundedBox(S(5), 0, 0, w, h, MC.panel)
        draw.SimpleText("YOU", "TPG.Menu.Head", S(12), S(10), C.TextMuted)
        draw.SimpleText("drag to turn", "TPG.Menu.Tiny", w - S(12), S(14), C.TextMuted,
            TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
    end

    -- Slot rows live at the bottom of the pane; the model takes the rest.
    local rows = vgui.Create("DPanel", doll)
    rows:Dock(BOTTOM)
    rows:SetTall(S(4) + #SLOTS * S(50))
    rows:DockMargin(S(10), 0, S(10), S(10))
    rows.Paint = nil

    local model = vgui.Create("DModelPanel", doll)
    model:Dock(FILL)
    model:DockMargin(S(10), S(34), S(10), S(6))
    model:SetFOV(38)
    -- No animation, so the model holds its reference pose: the arms-out stance
    -- that shows the vest.
    model:SetAnimated(false)
    model:SetMouseInputEnabled(true)

    -- Facing the camera. The camera sits out along +X and a model at yaw 0
    -- faces +X, so the previous 205 pointed it directly away -- you got its
    -- back. 20 is enough of a turn to read as a three-quarter view.
    local modelYaw = 20

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
        model:SetCamPos(centre + Vector(height * 1.5, 0, height * 0.05))
    end

    model.LayoutEntity = function(_, ent)
        ent:SetAngles(Angle(0, modelYaw, 0))
    end

    ApplyDollModel()

    model.OnMousePressed = function(self)
        self.dragging, self.dragX = true, gui.MouseX()
        self:MouseCapture(true)
    end
    model.OnMouseReleased = function(self)
        self.dragging = false
        self:MouseCapture(false)
    end
    model.Think = function(self)
        if self.dragging then
            local x = gui.MouseX()
            modelYaw = (modelYaw + (x - self.dragX) * 0.6) % 360
            self.dragX = x
        end
        ApplyDollModel()
    end

    --[[
        The vest, over the model's chest, because that is where a player looks
        for armor. Drawn as corner brackets and always visible: an invisible
        hotspot didn't tell anyone it was there, and a filled box big enough to
        click covered the torso it was pointing at.
    ]]
    local vest = vgui.Create("DButton", model)
    vest:SetText("")
    vest:SetCursor("hand")
    vest:SetTooltip("Armor")
    vest.PerformLayout = function(self)
        local w, h = model:GetWide(), model:GetTall()
        self:SetSize(w * 0.26, h * 0.17)
        self:SetPos(w * 0.37, h * 0.31)
    end
    vest.Paint = function(self, w, h)
        local col = SlotColor("Armor")
        local hovered = self:IsHovered()
        local a = hovered and 255 or 130
        local t = math.max(S(2), 1)
        local arm = math.min(w, h) * 0.32

        surface.SetDrawColor(col.r, col.g, col.b, a)
        -- Corners only: enough to read as a target, little enough to see the
        -- armor it's framing.
        surface.DrawRect(0, 0, arm, t)              surface.DrawRect(0, 0, t, arm)
        surface.DrawRect(w - arm, 0, arm, t)        surface.DrawRect(w - t, 0, t, arm)
        surface.DrawRect(0, h - t, arm, t)          surface.DrawRect(0, h - arm, t, arm)
        surface.DrawRect(w - arm, h - t, arm, t)    surface.DrawRect(w - t, h - arm, t, arm)

        if hovered then
            draw.SimpleText("ARMOR", "TPG.Menu.Tiny", w / 2, h + S(4), col,
                TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP)
        end
    end
    vest.DoClick = function()
        surface.PlaySound("buttons/button14.wav")
        activeSlot = SLOTS[4]
        activeGroup, searchText = nil, ""
        RefreshTabs()
        RefreshGrid()
    end

    for _, slot in ipairs(SLOTS) do
        local col = SlotColor(slot.key)

        local row = vgui.Create("DButton", rows)
        row:Dock(TOP)
        row:DockMargin(0, 0, 0, S(4))
        row:SetTall(S(46))
        row:SetText("")
        row.Paint = function(self, w, h)
            local active = (activeSlot.key == slot.key)
            draw.RoundedBox(S(4), 0, 0, w, h,
                (active or self:IsHovered()) and MC.hover or MC.row)
            draw.RoundedBox(0, 0, 0, math.max(S(3), 1), h, col)
            if active then Outline(w, h, math.max(S(2), 1), col) end

            draw.SimpleText(slot.label, "TPG.Menu.Tiny", S(12), S(7), col)
            draw.SimpleText(TPG.UI.Truncate(EquippedName(slot.key), "TPG.Menu.Item", w - S(24)),
                "TPG.Menu.Item", S(12), S(23), C.Text)
        end
        row.DoClick = function()
            surface.PlaySound("buttons/button14.wav")
            activeSlot = slot
            activeGroup, searchText = nil, ""
            RefreshTabs()
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
            The plain-language answer to "what does this cost me and for how
            long". "cd" in a badge said none of it.
        ]]
        local rule
        if TPG.Gear.EconomyActive() then
            rule = "Marked items cost points, charged when you spawn with them. Yours for that whole life."
        else
            rule = "Marked items are yours for that whole life. The timer starts when you spawn with one, and until it runs out you spawn with the free equivalent instead."
        end
        draw.SimpleText(TPG.UI.Truncate(activeSlot.hint .. "  " .. rule, "TPG.Menu.Small", w - S(28)),
            "TPG.Menu.Small", S(14), S(34), C.TextMuted)
    end

    -- Tab strip + search share one row.
    local tools = vgui.Create("DPanel", pane)
    tools:Dock(TOP)
    tools:DockMargin(S(10), S(58), S(10), S(4))
    tools:SetTall(S(30))
    tools.Paint = nil

    local search = vgui.Create("DTextEntry", tools)
    search:Dock(RIGHT)
    search:SetWide(S(210))
    search:SetPlaceholderText("Search...")
    search:SetUpdateOnType(true)
    search:SetFont("TPG.Menu.Small")
    search.Paint = function(self, w, h)
        draw.RoundedBox(S(4), 0, 0, w, h, MC.sunken)
        Outline(w, h, 1, MC.row)
        self:DrawTextEntryText(C.Text, C.Purple, C.Text)
    end
    search.OnValueChange = function(_, value)
        searchText = string.lower(value or "")
        RefreshGrid()
    end

    local tabs = vgui.Create("DPanel", tools)
    tabs:Dock(FILL)
    tabs:DockMargin(0, 0, S(8), 0)
    tabs.Paint = nil

    local scroll = vgui.Create("DScrollPanel", pane)
    scroll:Dock(FILL)
    scroll:DockMargin(S(10), 0, S(6), S(10))

    -- Plain canvas; the grid positions its own children (see the header note on
    -- DIconLayout).
    local canvas = vgui.Create("DPanel", scroll)
    canvas:Dock(TOP)
    canvas:SetTall(1)
    canvas.Paint = nil

    local cardW, cardH = S(174), S(192)
    local gap = S(10)
    local cols = math.max(math.floor((gridW + gap) / (cardW + gap)), 1)

    --[[
        One card. Everything static -- the truncated strings, the price, whether
        it even HAS a badge -- is resolved here, once. Paint reads the results.
    ]]
    local function MakeCard(item, index)
        local col     = SlotColor(activeSlot.key)
        local dim     = Color(col.r, col.g, col.b, 60)
        local slotKey = activeSlot.key
        local cmd     = activeSlot.cmd
        local price   = TPG.Gear.Price(item.kind, item.id)

        local card = vgui.Create("DButton", canvas)
        card:SetSize(cardW, cardH)
        card:SetPos(((index - 1) % cols) * (cardW + gap),
                    math.floor((index - 1) / cols) * (cardH + gap))
        card:SetText("")
        card:SetTooltip(item.name)

        -- SpawnIcon renders a cached material of the model, which is what makes
        -- a grid of forty weapons affordable -- a DModelPanel each would render
        -- forty models every frame. Items without a usable model just get their
        -- name in the space the icon would have used.
        local iconS = S(104)
        if item.model then
            local icon = vgui.Create("SpawnIcon", card)
            icon:SetModel(item.model)
            icon:SetSize(iconS, iconS)
            icon:SetPos((cardW - iconS) / 2, S(26))
            icon:SetMouseInputEnabled(false)
        end

        local nameY  = item.model and (cardH - S(64)) or math.Round(cardH * 0.34)
        local name   = TPG.UI.Truncate(item.name, "TPG.Menu.Item", cardW - S(14))
        local detail = item.detail and TPG.UI.Truncate(item.detail, "TPG.Menu.Tiny", cardW - S(14))
        local extra  = item.extra and TPG.UI.Truncate(item.extra, "TPG.Menu.Tiny", cardW - S(14))

        -- The static half of the badge. The locked version is time-dependent and
        -- is the only one built in Paint.
        local badge, badgeCol
        if price then
            if TPG.Gear.EconomyActive() then
                badge, badgeCol = price.cost .. " pts", C.Neutral
            elseif (price.cooldown or 0) > 0 then
                badge, badgeCol = FormatTime(price.cooldown) .. " cooldown", C.Neutral
            end
        end

        local stripH = S(22)

        card.Paint = function(self, w, h)
            local selected = (picks[slotKey] == item.id)
            local left     = price and CooldownLeft(item.kind, item.id) or 0

            draw.RoundedBox(S(5), 0, 0, w, h, self:IsHovered() and MC.hover or MC.row)
            Outline(w, h, math.max(selected and S(2) or S(1), 1), selected and col or dim)

            draw.SimpleText(name, "TPG.Menu.Item", w / 2, nameY,
                left > 0 and C.TextMuted or C.Text, TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP)
            if detail then
                draw.SimpleText(detail, "TPG.Menu.Tiny", w / 2, nameY + S(21), C.TextMuted,
                    TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP)
            end
            if extra then
                draw.SimpleText(extra, "TPG.Menu.Tiny", w - S(8), S(8), C.TextMuted,
                    TEXT_ALIGN_RIGHT, TEXT_ALIGN_TOP)
            end

            -- Badge, top-left so it never lands on the icon's silhouette.
            local text, textCol = badge, badgeCol
            if left > 0 then
                text, textCol = "Locked " .. FormatTime(left), C.Red
            end
            if text then
                surface.SetFont("TPG.Menu.Tiny")
                local bw, bh = surface.GetTextSize(text)
                draw.RoundedBox(S(3), S(6), S(6), bw + S(10), bh + S(4), Color(0, 0, 0, 170))
                draw.SimpleText(text, "TPG.Menu.Tiny", S(11), S(8), textCol)

                -- A locked item also gets a bar showing how much of the wait is
                -- done, so "not yet" turns into "nearly".
                if left > 0 and (price.cooldown or 0) > 0 then
                    local frac = 1 - math.Clamp(left / price.cooldown, 0, 1)
                    local bx, by, barW = S(6), S(6) + bh + S(6), bw + S(10)
                    draw.RoundedBox(0, bx, by, barW, math.max(S(3), 1), MC.sunken)
                    draw.RoundedBox(0, bx, by, barW * frac, math.max(S(3), 1), col)
                end
            end

            -- "Did I purchase it or not" -- the answer, in words, on the item.
            if selected then
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
        canvas:Clear()

        local shown = 0
        for _, item in ipairs(BuildItems(activeSlot.key)) do
            local matchesGroup  = (not activeGroup) or item.group == activeGroup
            local matchesSearch = (searchText == "")
                or string.find(string.lower(item.name), searchText, 1, true) ~= nil

            if matchesGroup and matchesSearch then
                shown = shown + 1
                MakeCard(item, shown)
            end
        end

        local rowCount = math.ceil(shown / cols)
        canvas:SetTall(math.max(rowCount * (cardH + gap) - gap, 1))
    end

    --[[
        Tabs for the slot's subcategories.

        Rebuilt per slot rather than per keystroke, so typing in the search box
        never destroys the panel that has keyboard focus. Armor has no
        subcategories and gets no strip; neither does a slot whose weapons all
        come from one (a pack that tags nothing would otherwise get a lone "All"
        tab that does nothing).
    ]]
    RefreshTabs = function()
        tabs:Clear()

        local groups, seen = {}, {}
        for _, item in ipairs(BuildItems(activeSlot.key)) do
            if item.group and not seen[item.group] then
                seen[item.group] = true
                groups[#groups + 1] = item.group
            end
        end
        table.sort(groups)

        if #groups < 2 then return end
        table.insert(groups, 1, false)   -- the "All" tab

        local col = SlotColor(activeSlot.key)
        for _, group in ipairs(groups) do
            local label = group or "All"

            local tab = vgui.Create("DButton", tabs)
            tab:Dock(LEFT)
            tab:DockMargin(0, 0, S(6), 0)
            tab:SetText("")

            surface.SetFont("TPG.Menu.Small")
            tab:SetWide(surface.GetTextSize(label) + S(20))

            tab.Paint = function(self, w, h)
                local active = (activeGroup == (group or nil))
                draw.RoundedBox(S(4), 0, 0, w, h,
                    (active or self:IsHovered()) and MC.hover or MC.sunken)
                if active then draw.RoundedBox(0, 0, h - math.max(S(2), 1), w, math.max(S(2), 1), col) end
                TPG.UI.TextInBox(label, "TPG.Menu.Small", 0, 0, w, h,
                    active and C.Text or C.TextMuted)
            end
            tab.DoClick = function()
                surface.PlaySound("buttons/button14.wav")
                activeGroup = group or nil
                RefreshGrid()
            end
        end
    end

    RefreshTabs()
    RefreshGrid()
end

concommand.Add("tpg_menu_loadout", OpenLoadoutMenu)
