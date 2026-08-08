--[[--
    Loadout selection menu: a paperdoll and a grid.

    One pane shows WHO YOU ARE: the actual player model TPG will spawn you in
    (`config/sh_armor.lua` picks it from your armor tier), with the four slots
    under it holding what you've got. The other pane shows the one question
    you're currently asking -- the items for the slot you clicked -- as icon
    boxes, because a rifle is easier to recognise by shape than by which of six
    ACE naming conventions its name follows.

    Exports nothing; opened with `tpg_menu_loadout` (also bound to the F3 key
    via `cl_binds.lua`). Client state comes from a single net message,
    `TPG_GearState`: two parallel tables, `picks` (what the server has SAVED
    for next spawn) and `live` (what you are ACTUALLY carrying right now), plus
    a `cooldownEnds` table keyed by `TPG.Gear.Key(kind, id)`. The read order in
    the `net.Receive` handler is fixed and must match whatever the server-side
    gear system writes -- field names carry no self-description over the wire.
    Clicking an item card sends `tpg_loadout <slotCmd> <itemId>` via
    `RunConsoleCommand`; the server is the only thing that ever actually
    equips or charges for anything, this file only ever writes to its own
    local `picks` copy so the UI reflects the click immediately without
    waiting on a round trip.

    `picks` vs `live` matters because they diverge the instant you click
    anything and stay diverged until your next respawn: clicking a rifle used
    to paint "EQUIPPED" across the card while the old one was still in your
    hands, which read as "done" when it meant "next time". Every row and card
    in this menu shows both, distinctly, for exactly that reason.

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

    And one rule about WHEN things are built.

      The menu is constructed once per session and shown again afterwards, and
      each slot's cards are built the first time that slot is opened and then
      kept. Building it is 240 vgui.Create calls, a player model and forty spawn
      icons: measured on a client that had just joined, the first open cost
      ~330ms of hitch and every open after it ~70ms, with about 260ms of the
      first being models and materials loading for the first time. Nothing in
      here depends on state that only changes between opens -- every Paint reads
      the picks and cooldowns live -- so there is nothing a rebuild would fix.

    @module tpg.menu.loadout
    @realm client
]]

local SLOTS = {
    { key = "Primary",   label = "PRIMARY",   cmd = 1, hint = "Your rifle." },
    { key = "Secondary", label = "SECONDARY", cmd = 2, hint = "Sidearm, grenades, binoculars." },
    { key = "Special",   label = "SPECIAL",   cmd = 3, hint = "Launchers and mines. This is your answer to a tank." },
    { key = "Armor",     label = "ARMOR",     cmd = 4, hint = "Sets your health, your armor and how fast you move." },
}

--[[
    The plain-language answer to "what does this cost me and for how long".
    A "cd" badge said none of it.

    Both are kept because the round can flip from one currency to the other
    while the menu is open, and the description below the slot title has to be
    laid out for whichever is longer either way.
]]
local RULES = {
    economy = "Marked items cost points, charged when you spawn with them. " ..
              "Yours for that whole life.",
    budget  = "Marked items are yours for a run of lives -- the badge says how " ..
              "many. When the last one is spent, dying starts the timer, and " ..
              "until it runs out you spawn with your fallback instead.",
    -- Shown in FALLBACK mode instead of either currency rule: the question has
    -- changed, so the answer about prices no longer applies.
    fallback = "Pick what you get in this slot when your choice above is " ..
               "refused. It has to be free, so it can never be refused in turn.",
}

-- How many lines of description the panel will give up to the block above the
-- tab strip. Past this it is cut with an ellipsis, so no config text can push
-- the grid off the bottom of the panel.
local DESC_MAX_LINES = 3

-- Each slot owns a colour, and it's the same colour on the paperdoll row, on
-- the panel header and on the border of every box in the grid. That's what
-- makes a selected box tell you WHICH slot it's selected in.
-- How much of the panel the paperdoll fills, relative to a snug fit on the
-- model's render bounds. Under 1 leaves headroom.
local DOLL_ZOOM = 0.88

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

--[[
    Premium gear runs, keyed the same way the server keys them
    (`TPG.Gear.Key`). One entry per item the player has an OPEN run on:

        charges  lives left before the timer starts
        ends     SysTime the timer runs out, or 0 while none is running

    Built from the relative seconds the server sent rather than an absolute
    deadline, so the two clocks never have to agree. No entry means the item is
    untouched, which is not the same as `charges = 0` -- that one is a run with
    nothing left in it, waiting on the next death to start its timer.
]]
local gearRuns = {}

--[[
    Two different answers to "what have I got".

    `picks` is what the server has SAVED for you -- what you'll get next time you
    spawn. `live` is what you are carrying right now. They're the same right
    after a spawn and diverge the moment you click anything, and the menu has to
    show both: clicking a rifle used to paint "EQUIPPED" across it while the old
    one was still in your hands, which read as "done" when it meant "next time".

    Panels read these every frame, so a reply that lands after the menu is
    already open just makes the right things light up rather than needing the
    menu rebuilt.
]]
local picks = {}
local live  = {}

--[[
    And a third: what each slot resolves to when its pick is REFUSED -- run of
    lives spent with the timer still going, or the wallet short.

    Kept apart from `picks` rather than folded in as a second field per slot,
    because the grid shows one or the other and never both, and the mode
    (`showFallback` below) is what decides which. Armor is absent on purpose:
    its fallback is `TPG.Gear.FreeArmor`, the best free tier, and there is no
    better answer for a player to choose.
]]
local fallbacks = {}

-- Which question the grid is currently asking. False: "what do you want".
-- True: "what do you want when you cannot have it".
local showFallback = false

net.Receive("TPG_GearState", function()
    gearRuns = {}
    for _ = 1, net.ReadUInt(8) do
        local key     = net.ReadString()
        local charges = net.ReadUInt(8)
        local left    = net.ReadFloat()
        gearRuns[key] = { charges = charges, ends = left > 0 and (SysTime() + left) or 0 }
    end

    picks.Primary   = net.ReadString()
    picks.Secondary = net.ReadString()
    picks.Special   = net.ReadString()
    picks.Armor     = net.ReadUInt(8)

    -- Empty ids / -1 armor mean "hasn't spawned into this loadout yet", which
    -- is the honest state for anyone waiting on a respawn.
    live.Primary   = net.ReadString()
    live.Secondary = net.ReadString()
    live.Special   = net.ReadString()
    local armor    = net.ReadInt(9)
    live.Armor     = armor >= 0 and armor or nil

    fallbacks.Primary   = net.ReadString()
    fallbacks.Secondary = net.ReadString()
    fallbacks.Special   = net.ReadString()
end)

-- Is this exact item the one the player is actually carrying, as opposed to the
-- one they've selected for next time?
local function IsLive(slotKey, id)
    local held = live[slotKey]
    if held == nil or held == "" then return false end
    return held == id
end

-- How many slots hold a pick that hasn't been spawned into yet. Four table
-- lookups, so it's fine to ask every frame.
local function PendingCount()
    local n = 0
    for _, slot in ipairs(SLOTS) do
        local id = picks[slot.key]
        if id ~= nil and not IsLive(slot.key, id) then n = n + 1 end
    end
    return n
end

-- Seconds left on an item's timer, or 0 -- which is also what an item mid-run
-- reports, so it means "not waiting", not "ready in every sense".
local function CooldownLeft(kind, id)
    local run = gearRuns[TPG.Gear.Key(kind, id)]
    if not run or run.ends == 0 then return 0 end
    return math.max(run.ends - SysTime(), 0)
end

-- Lives left in an item's run, and whether the run has been opened at all. An
-- untouched item reports its full allowance so the menu can say "6 lives"
-- without knowing the difference.
local function LivesLeft(kind, id, price)
    local run = gearRuns[TPG.Gear.Key(kind, id)]
    if run then return run.charges, true end
    return price and price.lives or 0, false
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

    That check searches every mounted content path and there is one per weapon,
    so the answers are remembered. What is mounted cannot change while the game
    is running, which makes the cache good for the whole session.
]]
local modelExists = {}

local function ItemModel(entry)
    if not entry then return nil end

    local class = entry.class
    if not class and entry.multipleClasses then class = entry.multipleClasses[1] end
    if not class then return nil end

    local swep = weapons.GetStored(class)
    local model = swep and swep.WorldModel
    if not model or model == "" then return nil end

    if modelExists[model] == nil then
        modelExists[model] = file.Exists(model, "GAME")
    end
    if not modelExists[model] then return nil end
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

--[[
    BuildItems walks every SWEP in a slot and resolves a model for each, and
    both the tab strip and the grid want the same answer.

    Cached for the session rather than for the lifetime of one menu: the list
    comes from the config and from what SWEPs are installed, and neither of
    those changes after the client has loaded.
]]
local itemCache = {}

local function SlotItems(key)
    if not itemCache[key] then itemCache[key] = BuildItems(key) end
    return itemCache[key]
end

--[[
    Pull the models the menu is going to want into memory before anyone opens it.

    Measured on a client that had just landed on the server, the first open of
    this menu costs about 330ms and the second about 70ms. The difference is
    everything the paperdoll and the spawn icons need being loaded for the first
    time -- the part of the hitch that no amount of cheaper Lua can remove,
    because it is disk.

    Loading the lot in one pass is NOT the fix and was measured too: doing all
    of them together stalled the client for half a second, which is the hitch
    moved rather than removed. So it is one model per tick, started well after
    the join storm has died down, and it stops the moment the menu is opened --
    at that point the menu is loading them itself and a second copy of the work
    would only compete with it.

    The materials are asked for by name rather than left to the model: a
    ClientsideModel that is never drawn never loads its VMTs, and the icons are
    as much material as they are geometry.
]]
local function WarmModels()
    if not (TPG.GetArmorList and TPG.GetWeaponList) then return end

    local queue, seen = {}, {}

    local function want(model)
        if not model or model == "" or seen[model] then return end
        seen[model] = true
        queue[#queue + 1] = model
    end

    for _, armor in ipairs(TPG.GetArmorList()) do want(ArmorModel(armor.id)) end
    for _, slot in ipairs(SLOTS) do
        if slot.key ~= "Armor" then
            for _, item in ipairs(SlotItems(slot.key)) do want(item.model) end
        end
    end

    if #queue == 0 then return end

    timer.Create("TPG_LoadoutWarm", 0.15, #queue, function()
        local model = table.remove(queue)
        if not model then return end

        local ent = ClientsideModel(model, RENDERGROUP_OTHER)
        if not IsValid(ent) then return end

        ent:SetNoDraw(true)
        for _, mat in ipairs(ent:GetMaterials() or {}) do Material(mat) end
        ent:Remove()
    end)
end

hook.Add("InitPostEntity", "TPG_LoadoutWarm", function()
    timer.Simple(10, WarmModels)
end)

-- Name of whatever is currently in a slot, for the paperdoll rows.
local function EquippedName(slotKey)
    if slotKey == "Armor" then
        return TPG.GetArmor(picks.Armor or 1).name
    end
    local entry = TPG.GetWeapon(slotKey, picks[slotKey])
    return entry and entry.name or "None"
end

local function BuildLoadoutMenu()
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

    -- Closing hides it; see the note at the top of the file about why it is kept.
    frame:SetDeleteOnClose(false)
    frame.OnClose = function(self)
        -- A Remove would have handed the mouse and keyboard back on its own.
        self:SetKeyboardInputEnabled(false)
        self:SetMouseInputEnabled(false)
    end

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

        -- The line only says something reassuring when there IS nothing to do.
        -- The rest of the time it says the one thing the player needs to know.
        local pending = PendingCount()
        local line, lineCol
        if pending > 0 then
            line = pending .. (pending == 1 and " change is" or " changes are") ..
                " waiting -- you keep carrying what you've got until you respawn."
            lineCol = C.Neutral
        else
            line = "Everything selected here is what you're carrying right now."
            lineCol = C.TextMuted
        end

        draw.SimpleText(line, "TPG.Menu.Small", S(14), h / 2 + S(12), lineCol,
            TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
    end

    local respawn = vgui.Create("DButton", footer)
    respawn:Dock(RIGHT)
    respawn:DockMargin(0, S(9), S(9), S(9))
    respawn:SetWide(S(200))
    respawn:SetText("")
    respawn:SetTooltip("In your spawn zone, or anywhere you haven't taken fire for 8 " ..
        "seconds. Doesn't count as a death, and doesn't re-charge you for gear you " ..
        "already bought this life.")
    -- Lit up while there's something to apply, so the button is the answer to
    -- the footer line rather than a control you have to know about.
    respawn.Paint = function(self, w, h)
        local pending = PendingCount() > 0
        draw.RoundedBox(S(4), 0, 0, w, h,
            self:IsHovered() and C.Purple or (pending and MC.hover or MC.row))
        if pending then Outline(w, h, math.max(S(2), 1), C.Neutral) end
        TPG.UI.TextInBox(pending and "RESPAWN TO APPLY" or "RESPAWN NOW",
            "TPG.Menu.Head", 0, 0, w, h, C.Text)
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
    local RefreshGrid, RefreshTabs, LayoutGrid, RefreshModeButtons  -- forward declarations
    -- Declared up here because the slot buttons below are built before it and
    -- have to be able to clear it when you change slot.
    local search

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
        -- Pulled back so the model draws at DOLL_ZOOM of the size it otherwise
        -- would. Render bounds are the collision-ish box, not the silhouette, so
        -- the taller helmets sat a little proud of it and clipped through the
        -- top of the panel; the margin is cheaper than measuring hitboxes.
        model:SetCamPos(centre + Vector(height * 1.5 / DOLL_ZOOM, 0, height * 0.05))
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
    -- Changing slot is changing the question, so the filters that narrowed the
    -- last one don't carry over -- including the text still sitting in the box.
    local function SelectSlot(slot)
        surface.PlaySound("buttons/button14.wav")
        activeSlot = slot
        activeGroup, searchText = nil, ""
        if IsValid(search) then search:SetText("") end
        RefreshModeButtons()
        RefreshTabs()
        RefreshGrid()
    end

    vest.DoClick = function() SelectSlot(SLOTS[4]) end

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

            -- A row shows the PICK, so it needs to say when the pick isn't what
            -- you're holding -- otherwise the paperdoll claims you're already
            -- wearing the armor you just clicked.
            local id      = picks[slot.key]
            local pending = id ~= nil and not IsLive(slot.key, id)
            local nameW   = w - S(24) - (pending and S(64) or 0)

            if pending then
                draw.SimpleText("ON RESPAWN", "TPG.Menu.Tiny", w - S(12), S(25), C.Neutral,
                    TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
            end

            draw.SimpleText(TPG.UI.Truncate(EquippedName(slot.key), "TPG.Menu.Item", nameW),
                "TPG.Menu.Item", S(12), S(23), C.Text)
        end
        row.DoClick = function() SelectSlot(slot) end
    end

    --[[
        The description under the slot title: what this slot is for, then what
        the round's currency rule means for it.

        Wrapped, not truncated. On one line it ended at "...until it runs out
        you spawn with the fre-", which is the half of the sentence that doesn't
        answer anything, and it was re-truncated sixty times a second besides.

        All eight of them -- four slots, both currency modes -- are wrapped here
        and kept, so Paint only picks one, and so the tab strip below can be
        placed clear of the tallest and stay put when the round flips from a
        team budget to a per-player economy mid-menu.
    ]]
    local descX, descY = S(14), S(44)
    local descLH   = TPG.UI.LineHeight("TPG.Menu.Small")
    local descRows = 1
    local descLines = {}

    for _, slot in ipairs(SLOTS) do
        local wrapped = {}
        -- Order matters: Paint indexes this 1/2/3 for economy / team budget /
        -- fallback mode.
        for _, rule in ipairs({ RULES.economy, RULES.budget, RULES.fallback }) do
            local lines = TPG.UI.Wrap(slot.hint .. "  " .. rule, "TPG.Menu.Small",
                paneW - descX - S(14), DESC_MAX_LINES)
            wrapped[#wrapped + 1] = lines
            descRows = math.max(descRows, #lines)
        end
        descLines[slot.key] = wrapped
    end

    -- ── Right: the grid for the active slot ────────────────────────────────
    local pane = vgui.Create("DPanel", body)
    pane:Dock(FILL)
    pane.Paint = function(_, w, h)
        draw.RoundedBox(S(5), 0, 0, w, h, MC.panel)
        local col = SlotColor(activeSlot.key)
        draw.RoundedBox(0, S(10), 0, w - S(20), math.max(S(3), 1), col)
        local fbMode = showFallback and activeSlot.key ~= "Armor"

        draw.SimpleText(activeSlot.label .. (fbMode and " - FALLBACK" or ""),
            "TPG.Menu.Head", S(14), S(12), col)

        local lines = descLines[activeSlot.key][fbMode and 3
            or (TPG.Gear.EconomyActive() and 1 or 2)]
        for i = 1, #lines do
            draw.SimpleText(lines[i], "TPG.Menu.Small", descX, descY + (i - 1) * descLH,
                C.TextMuted)
        end
    end

    --[[
        Search lives in the header row, not next to the tabs.

        Sharing a row meant the tab strip's width was whatever was left over,
        and Derma doesn't clip children to their parent -- so the moment a slot
        had one tab too many, "Machine Guns" was drawn straight over the search
        box. Nothing on the tab row competes for space now, and the tabs wrap.
    ]]
    local searchW = S(206)
    search = vgui.Create("DTextEntry", pane)
    search:SetSize(searchW, S(28))
    search:SetPos(paneW - searchW - S(14), S(10))
    search:SetPlaceholderText("Search...")
    search:SetUpdateOnType(true)
    search:SetFont("TPG.Menu.Small")
    -- A dark box on a dark panel with a darker border was invisible. It reads
    -- as a field now: lighter than the panel it sits on, with a border that
    -- brightens to the slot colour while it has focus.
    search.Paint = function(self, w, h)
        draw.RoundedBox(S(4), 0, 0, w, h, MC.row)
        Outline(w, h, math.max(S(2), 1),
            self:HasFocus() and SlotColor(activeSlot.key) or C.PurpleLight)

        if self:GetText() == "" and not self:HasFocus() then
            draw.SimpleText("Search...", "TPG.Menu.Small", S(10), h / 2, C.TextMuted,
                TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
        end
        self:DrawTextEntryText(C.Text, C.Purple, C.Text)
    end
    search.OnValueChange = function(_, value)
        searchText = string.lower(value or "")
        LayoutGrid()
    end

    --[[
        PICK / FALLBACK.

        Two questions about the same slot -- "what do you want" and "what do you
        want when you can't have it" -- so they share one grid rather than
        getting a second one built beside it. Flipping the mode only changes
        what a card reads and what a click sends; nothing is rebuilt, which is
        the whole reason this is a mode and not a fifth slot.

        Hidden on Armor: its fallback is TPG.Gear.FreeArmor, the best free tier,
        and there is nothing better for a player to choose.
    ]]
    local modeW, modeH = S(96), S(28)
    local modeButtons = {}

    for i, mode in ipairs({ { label = "PICK", fb = false }, { label = "FALLBACK", fb = true } }) do
        local btn = vgui.Create("DButton", pane)
        btn:SetSize(modeW, modeH)
        btn:SetPos(paneW - searchW - S(14) - S(8) - (3 - i) * (modeW + S(4)), S(10))
        btn:SetText("")
        btn:SetTooltip(mode.fb
            and "What this slot gives you when your pick is refused -- its lives spent, or you can't afford it."
            or  "What you want in this slot.")

        btn.Paint = function(self, w, h)
            local active = (showFallback == mode.fb)
            local c = SlotColor(activeSlot.key)
            draw.RoundedBox(S(4), 0, 0, w, h,
                (active or self:IsHovered()) and MC.hover or MC.sunken)
            if active then
                draw.RoundedBox(0, 0, h - math.max(S(2), 1), w, math.max(S(2), 1), c)
            end
            TPG.UI.TextInBox(mode.label, "TPG.Menu.Small", 0, 0, w, h,
                active and C.Text or C.TextMuted)
        end

        btn.DoClick = function()
            if showFallback == mode.fb then return end
            surface.PlaySound("buttons/button14.wav")
            showFallback = mode.fb
        end

        modeButtons[#modeButtons + 1] = btn
    end

    -- Armor has no fallback to choose, so the toggle goes away with it -- and
    -- the mode goes back to PICK, or leaving Armor would land on a FALLBACK
    -- grid nobody asked for.
    RefreshModeButtons = function()
        local show = activeSlot.key ~= "Armor"
        if not show then showFallback = false end
        for _, btn in ipairs(modeButtons) do btn:SetVisible(show) end
    end

    local tabs = vgui.Create("DPanel", pane)
    tabs:Dock(TOP)
    -- Below the description, however many lines that turned out to be.
    tabs:DockMargin(S(10), descY + descRows * descLH + S(6), S(10), S(4))
    tabs:SetTall(1)
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
    local iconS = S(104)
    local gap = S(10)
    local cols = math.max(math.floor((gridW + gap) / (cardW + gap)), 1)

    --[[
        Icons arrive a frame at a time, not all together.

        A SpawnIcon costs about 12ms the first time one is made for a model the
        engine hasn't drawn yet -- it renders the thing to a texture. Nineteen of
        those in the frame you click a slot is a 225ms stall, which is what the
        first click on SECONDARY measured at. Making one per frame turns that
        into the grid filling in over a fifth of a second, which reads as the
        pictures loading rather than as the game stopping.

        A card whose turn hasn't come yet draws exactly like an item that has no
        model at all, and the name already sits where it will stay, so nothing
        moves when the picture appears.
    ]]
    local iconQueue, iconNext = {}, 1

    canvas.Think = function()
        while iconNext <= #iconQueue do
            local card = iconQueue[iconNext]
            iconNext = iconNext + 1

            if IsValid(card) and card.iconModel then
                local icon = vgui.Create("SpawnIcon", card)
                icon:SetModel(card.iconModel)
                icon:SetSize(iconS, iconS)
                icon:SetPos((cardW - iconS) / 2, S(26))
                icon:SetMouseInputEnabled(false)
                card.iconModel = nil
                return
            end
        end
    end

    --[[
        One card. Everything static -- the truncated strings, the price, the
        badge text for both currencies -- is resolved here, once. Paint only
        reads the results and asks which currency is in force.

        Position is NOT set here: cards are built once per slot and then moved
        around by LayoutGrid as the filter changes (see RefreshGrid).

        The slot is passed in rather than read from activeSlot because a card
        outlives the moment it was built -- every slot keeps its own, and they
        last as long as the menu does.
    ]]
    local function MakeCard(slot, item)
        local col     = SlotColor(slot.key)
        local dim     = Color(col.r, col.g, col.b, 60)
        local slotKey = slot.key
        local cmd     = slot.cmd
        local price   = TPG.Gear.Price(item.kind, item.id)

        local card = vgui.Create("DButton", canvas)
        card:SetSize(cardW, cardH)
        card:SetText("")
        card:SetTooltip(item.name)

        -- SpawnIcon renders a cached material of the model, which is what makes
        -- a grid of forty weapons affordable -- a DModelPanel each would render
        -- forty models every frame. Items without a usable model just get their
        -- name in the space the icon would have used. Queued rather than made
        -- here; see the note on iconQueue.
        if item.model then
            card.iconModel = item.model
            iconQueue[#iconQueue + 1] = card
        end

        local nameY  = item.model and (cardH - S(64)) or math.Round(cardH * 0.34)
        local name   = TPG.UI.Truncate(item.name, "TPG.Menu.Item", cardW - S(14))
        local detail = item.detail and TPG.UI.Truncate(item.detail, "TPG.Menu.Tiny", cardW - S(14))
        local extra  = item.extra and TPG.UI.Truncate(item.extra, "TPG.Menu.Tiny", cardW - S(14))

        -- What this item costs, in both currencies, worked out now. Which of the
        -- two applies is a question for Paint: the card outlives the round it
        -- was built in, and a round can end in either mode.
        local costBadge, livesBadge
        if price then
            costBadge = price.cost and (price.cost .. " pts") or nil
            if (price.cooldown or 0) > 0 then
                -- What an UNTOUCHED one is worth: the run you get, and the wait
                -- that follows it. Both, because either alone is half a price.
                livesBadge = price.lives .. (price.lives == 1 and " life, then " or " lives, then ") ..
                    FormatTime(price.cooldown)
            end
        end

        local stripH = S(22)

        -- Whether this card can be a fallback at all. Constant for the card's
        -- life: it turns on the item being free, which is config, not state.
        local fallbackOK = item.kind == "weapon" and TPG.Gear.FallbackAllowed(slotKey, item.id)

        card.Paint = function(self, w, h)
            local fbMode   = showFallback and slotKey ~= "Armor"
            local selected = fbMode and (fallbacks[slotKey] == item.id)
                or (not fbMode and picks[slotKey] == item.id)
            local left     = price and CooldownLeft(item.kind, item.id) or 0

            -- A card that cannot be chosen in the current mode stays on the
            -- grid and says why: "the Javelin is not on this list" reads as a
            -- bug, "the Javelin can't be a fallback" reads as the rule it is.
            -- It is not dimmed with an overlay, because the SpawnIcon is a
            -- child panel and draws AFTER Paint -- the picture would have
            -- stayed bright over a greyed card, which looks broken rather than
            -- disabled.
            local inert = fbMode and not fallbackOK

            draw.RoundedBox(S(5), 0, 0, w, h,
                (self:IsHovered() and not inert) and MC.hover or MC.row)
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

            --[[
                Badge, top-left so it never lands on the icon's silhouette.

                Under the team budget an item is in one of three states, and
                they are genuinely three different answers to "can I take this":

                  untouched   the full price -- "6 lives, then 4:00"
                  mid-run     what's left of it -- "3 lives left"
                  waiting     the timer -- "Locked 3:12", and you can't

                Only the last is a refusal, so only the last is red.
            ]]
            local text, textCol = costBadge, C.Neutral
            local frac

            if fbMode then
                -- In fallback mode the price is not the question -- whether it
                -- can be a fallback at all is.
                text, textCol = inert and "Not free" or nil, C.Red
            elseif not TPG.Gear.EconomyActive() and price then
                local lives, opened = LivesLeft(item.kind, item.id, price)

                if left > 0 then
                    text, textCol = "Locked " .. FormatTime(left), C.Red
                    -- How much of the wait is done, so "not yet" reads as
                    -- "nearly". Against the item's own cooldown, which is the
                    -- length this bar was filled from.
                    if (price.cooldown or 0) > 0 then
                        frac = 1 - math.Clamp(left / price.cooldown, 0, 1)
                    end
                elseif opened then
                    -- 0 left is a run that is spent but not yet waiting: the
                    -- next death starts the timer. Say so, rather than showing
                    -- "0 lives left" and letting it read as locked.
                    if lives <= 0 then
                        text, textCol = "Last life - dying starts the wait", C.Neutral
                    else
                        text = lives .. (lives == 1 and " life left" or " lives left")
                        frac = 1 - math.Clamp(lives / math.max(price.lives, 1), 0, 1)
                    end
                else
                    text = livesBadge
                end
            end

            if text then
                surface.SetFont("TPG.Menu.Tiny")
                local bw, bh = surface.GetTextSize(text)
                draw.RoundedBox(S(3), S(6), S(6), bw + S(10), bh + S(4), Color(0, 0, 0, 170))
                draw.SimpleText(text, "TPG.Menu.Tiny", S(11), S(8), textCol)

                if frac then
                    local bx, by, barW = S(6), S(6) + bh + S(6), bw + S(10)
                    draw.RoundedBox(0, bx, by, barW, math.max(S(3), 1), MC.sunken)
                    draw.RoundedBox(0, bx, by, barW * frac, math.max(S(3), 1),
                        left > 0 and col or C.Neutral)
                end
            end

            --[[
                "Did I purchase it or not" -- and, just as important, "do I have
                it yet". Selecting a weapon saves a preference; you keep carrying
                the old one until you respawn, and a card that just said
                EQUIPPED made that look like it had already happened.

                Green means it's in your hands. Amber means it isn't yet. The
                slot's own colour stays on the border, which is what says WHICH
                slot this is, so the strip is free to mean status instead.
            ]]
            if selected then
                -- A fallback is never something you are holding, so the
                -- equipped/pending distinction does not apply to it. It says
                -- what it is instead.
                if fbMode then
                    draw.RoundedBox(0, 0, h - stripH, w, stripH, col)
                    TPG.UI.TextInBox("FALLBACK", "TPG.Menu.Tiny", 0, h - stripH, w, stripH,
                        C.Contrast(col))
                else
                    local held = IsLive(slotKey, item.id)
                    local bar  = held and C.Good or C.Neutral
                    draw.RoundedBox(0, 0, h - stripH, w, stripH, bar)
                    TPG.UI.TextInBox(held and "EQUIPPED" or "RESPAWN TO EQUIP",
                        "TPG.Menu.Tiny", 0, h - stripH, w, stripH, C.Contrast(bar))
                end
            end
        end

        card.DoClick = function()
            if showFallback and slotKey ~= "Armor" then
                if not fallbackOK then
                    -- The server would refuse this anyway; saying so here means
                    -- the click explains itself instead of doing nothing.
                    surface.PlaySound("buttons/button10.wav")
                    chat.AddText(C.Red, "[TPG] A fallback has to be free -- it is what you " ..
                        "get when you cannot have the paid one.")
                    return
                end

                surface.PlaySound("buttons/button14.wav")
                fallbacks[slotKey] = item.id
                RunConsoleCommand("tpg_fallback", cmd, tostring(item.id))
                return
            end

            surface.PlaySound("buttons/button14.wav")
            picks[slotKey] = item.id
            RunConsoleCommand("tpg_loadout", cmd, tostring(item.id))

            if item.warn then
                chat.AddText(C.Red, "[TPG] " .. item.name .. ": " .. item.warn)
            end
        end

        return card
    end

    --[[
        Cards, built once and then hidden and moved -- never rebuilt.

        Rebuilding on every keystroke is what made typing in the search box lag:
        each pass destroyed forty panels and created forty more, and creating a
        SpawnIcon means asking the icon system for a render of a model it may not
        have cached yet. Filtering now only ever moves panels that already
        exist -- a SetVisible and a SetPos each -- so holding a key down costs
        nothing beyond a string compare per item.

        The same argument applies one level up, which is why the cards are kept
        PER SLOT rather than thrown away when you click a different one. Clicking
        Primary, then Secondary, then Primary again used to pay the full build
        cost three times; it now pays it twice and never again.
    ]]
    local slotCards = {}

    LayoutGrid = function()
        local shown = 0

        for _, entry in ipairs(slotCards[activeSlot.key] or {}) do
            local item = entry.item
            local matchesGroup  = (not activeGroup) or item.group == activeGroup
            local matchesSearch = (searchText == "")
                or string.find(string.lower(item.name), searchText, 1, true) ~= nil

            if matchesGroup and matchesSearch then
                entry.panel:SetPos((shown % cols) * (cardW + gap),
                                   math.floor(shown / cols) * (cardH + gap))
                entry.panel:SetVisible(true)
                shown = shown + 1
            else
                entry.panel:SetVisible(false)
            end
        end

        local rowCount = math.ceil(shown / cols)
        canvas:SetTall(math.max(rowCount * (cardH + gap) - gap, 1))

        -- Back to the top: the list under the scrollbar is a different list now,
        -- and staying halfway down someone else's results is disorienting.
        local bar = scroll:GetVBar()
        if IsValid(bar) then bar:SetScroll(0) end
    end

    -- Bring a slot's cards on screen, building them if this is the first time
    -- the slot has been looked at. Every other slot's cards go out of sight
    -- where they are; they share one canvas.
    RefreshGrid = function()
        if not slotCards[activeSlot.key] then
            local built = {}
            for _, item in ipairs(SlotItems(activeSlot.key)) do
                built[#built + 1] = { item = item, panel = MakeCard(activeSlot, item) }
            end
            slotCards[activeSlot.key] = built
        end

        for key, list in pairs(slotCards) do
            if key ~= activeSlot.key then
                for _, entry in ipairs(list) do entry.panel:SetVisible(false) end
            end
        end

        LayoutGrid()
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
        for _, item in ipairs(SlotItems(activeSlot.key)) do
            if item.group and not seen[item.group] then
                seen[item.group] = true
                groups[#groups + 1] = item.group
            end
        end

        -- Config order, not alphabetical: the strip reads rifle-to-launcher the
        -- way the slot itself does, instead of putting Anti-Air first because it
        -- starts with an A. SubCategoryTabs is the whole list of tabs that can
        -- exist (see sh_weapons_config.lua), so its indices are the order.
        local order = {}
        for i, name in ipairs(TPG.WeaponConfig.SubCategoryTabs or {}) do
            order[name] = i
        end
        table.sort(groups, function(a, b)
            local ia, ib = order[a] or math.huge, order[b] or math.huge
            if ia ~= ib then return ia < ib end
            return a < b
        end)

        if #groups < 2 then
            tabs:SetTall(1)
            return
        end
        table.insert(groups, 1, false)   -- the "All" tab

        -- Wrapped by hand. Docking LEFT just ran the strip off the end of the
        -- panel and over whatever was beside it.
        local col    = SlotColor(activeSlot.key)
        local tabH   = S(28)
        local gapX   = S(6)
        local stripW = paneW - S(20)
        local x, y   = 0, 0

        for _, group in ipairs(groups) do
            local label = group or "All"

            surface.SetFont("TPG.Menu.Small")
            local tabW = math.min(surface.GetTextSize(label) + S(20), stripW)

            if x > 0 and x + tabW > stripW then
                x, y = 0, y + tabH + S(5)
            end

            local tab = vgui.Create("DButton", tabs)
            tab:SetSize(tabW, tabH)
            tab:SetPos(x, y)
            tab:SetText("")
            x = x + tabW + gapX

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
                LayoutGrid()
            end
        end

        tabs:SetTall(y + tabH)
    end

    RefreshModeButtons()
    RefreshTabs()
    RefreshGrid()

    return frame
end

-- The one menu, and the UI scale it was built at.
local menu, menuScale

local function OpenLoadoutMenu()
    -- Ask for fresh cooldowns and the picks the server currently has for us.
    -- Every open, reused frame or not: this is the only thing that goes stale.
    net.Start("TPG_GearRequest")
    net.SendToServer()

    -- Whatever the warmer hasn't got to yet, the menu is about to load itself.
    timer.Remove("TPG_LoadoutWarm")

    --[[
        Shown again rather than rebuilt -- see the note at the top of the file.

        The exception is a resolution change: every font and every S() dimension
        underneath this menu is derived from the UI scale, so a menu built at the
        old one is wrong in a way no refresh can fix, and gets replaced.
    ]]
    if IsValid(menu) and menuScale == TPG.UI.scale then
        menu:SetVisible(true)
        menu:MakePopup()
        return
    end

    if IsValid(menu) then menu:Remove() end

    menu      = BuildLoadoutMenu()
    menuScale = TPG.UI.scale
end

concommand.Add("tpg_menu_loadout", OpenLoadoutMenu)
