--[[
    Weapon Admin Panel (admin-only) + client weapon-state receiver.
    Open with the console command: tpg_menu_weapons
]]

-- Apply server-pushed enable/override state so loadout menus match the rules.
net.Receive("TPG_WeaponState", function()
    local state = util.JSONToTable(net.ReadString() or "") or {}
    if TPG.Weapons and TPG.Weapons.ApplyState then
        TPG.Weapons.ApplyState(state)
    end
end)

local CATS = { "Primary", "Secondary", "Special" }

local function OpenWeaponAdmin()
    if not LocalPlayer():IsAdmin() then
        chat.AddText(Color(255, 0, 0), "[TPG] Weapon configuration is admin-only.")
        return
    end

    -- Working copy of the saved state; edited live, sent on Save.
    local work = table.Copy(TPG.Weapons._state or {})
    work.bases   = work.bases or {}
    work.weapons = work.weapons or {}

    local frame = vgui.Create("DFrame")
    frame:SetSize(440, 580)
    frame:Center()
    frame:SetTitle("The Proving Ground - Weapon Configuration (Admin)")
    frame:MakePopup()

    -- Save button (bottom)
    local save = vgui.Create("DButton", frame)
    save:Dock(BOTTOM)
    save:DockMargin(8, 6, 8, 8)
    save:SetTall(34)
    save:SetText("Save (persists across maps)")
    save.DoClick = function()
        net.Start("TPG_WeaponStateSet")
            net.WriteString(util.TableToJSON(work))
        net.SendToServer()
        surface.PlaySound("buttons/button14.wav")
        frame:Close()
    end

    -- Base (weapon pack) toggles
    local baseHeader = vgui.Create("DLabel", frame)
    baseHeader:Dock(TOP)
    baseHeader:DockMargin(8, 6, 8, 0)
    baseHeader:SetText("Weapon packs (toggle a whole base on/off):")
    baseHeader:SetTextColor(Color(255, 255, 0))

    local basePanel = vgui.Create("DPanel", frame)
    basePanel:Dock(TOP)
    basePanel:DockMargin(8, 2, 8, 4)

    local bases = (TPG.Weapons.GetDiscoveredBases and TPG.Weapons.GetDiscoveredBases()) or {}
    local baseList = {}
    for b in pairs(bases) do baseList[#baseList + 1] = b end
    table.sort(baseList)
    basePanel:SetTall(math.max(#baseList, 1) * 22 + 8)

    local by = 4
    for _, b in ipairs(baseList) do
        local cb = vgui.Create("DCheckBoxLabel", basePanel)
        cb:SetPos(6, by); by = by + 22
        cb:SetText(b)
        cb:SetTextColor(Color(220, 220, 220))
        cb:SetValue(work.bases[b] ~= false)
        cb.OnChange = function(_, val) work.bases[b] = val and true or false end
    end

    -- Search
    local search = vgui.Create("DTextEntry", frame)
    search:Dock(TOP)
    search:DockMargin(8, 0, 8, 4)
    search:SetTall(24)
    search:SetUpdateOnType(true)
    search:SetPlaceholderText("Search weapons...")

    -- Weapon checkboxes
    local scroll = vgui.Create("DScrollPanel", frame)
    scroll:Dock(FILL)
    scroll:DockMargin(8, 0, 8, 0)

    local function populate(filter)
        scroll:Clear()
        filter = string.lower(filter or "")

        for _, cat in ipairs(CATS) do
            local header
            for _, w in ipairs(TPG.GetWeaponList(cat, true)) do  -- include disabled
                if w.id ~= "none"
                    and (filter == "" or string.find(string.lower(w.name .. " " .. w.id), filter, 1, true)) then

                    if not header then
                        header = scroll:Add("DLabel")
                        header:Dock(TOP); header:DockMargin(0, 6, 0, 2)
                        header:SetText(cat)
                        header:SetFont("DermaDefaultBold")
                        header:SetTextColor(Color(120, 200, 255))
                    end

                    local enabled = w.enabled
                    if work.weapons[w.id] ~= nil then enabled = work.weapons[w.id] end

                    local cb = scroll:Add("DCheckBoxLabel")
                    cb:Dock(TOP); cb:DockMargin(10, 1, 0, 1)
                    cb:SetText(w.name .. "  (" .. w.id .. ")")
                    cb:SetTextColor(Color(220, 220, 220))
                    cb:SetValue(enabled and true or false)
                    cb.OnChange = function(_, val) work.weapons[w.id] = val and true or false end
                end
            end
        end
    end

    search.OnValueChange = function(_, val) populate(val) end
    populate("")
end

concommand.Add("tpg_menu_weapons", OpenWeaponAdmin)
