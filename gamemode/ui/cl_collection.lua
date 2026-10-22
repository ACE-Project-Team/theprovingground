--[[--
    The map collection hint, client side: a chat line and a small popup when the
    server has few TPG maps installed. Sent by @{tpg.collection.server} only to
    superadmins and the listen-server host.

    `tpg_collection_hint` 0 turns it off for this client, and the popup's
    "Don't show again" button sets it.

    @module tpg.collection
    @realm client
]]

local COLLECTION_ID = "3645840394"
local COLLECTION_URL = "https://steamcommunity.com/sharedfiles/filedetails/?id=" .. COLLECTION_ID

local cvHint = CreateClientConVar("tpg_collection_hint", "1", true, false,
    "Show the TPG map collection hint when this server has few TPG maps installed (0 = never).")

local TPG_RED = Color(200, 30, 30)

local function openCollection()
    if steamworks and steamworks.ViewFile then
        steamworks.ViewFile(COLLECTION_ID)
    else
        gui.OpenURL(COLLECTION_URL)
    end
end

local hintFrame

local function showPopup(count, threshold)
    if IsValid(hintFrame) then hintFrame:Remove() end

    local S = TPG.UI.S
    local w, h = S(420), S(190)

    local frame = vgui.Create("DFrame")
    hintFrame = frame
    frame:SetTitle("The Proving Ground - maps")
    frame:SetSize(w, h)
    frame:Center()
    frame:MakePopup()
    frame:SetDeleteOnClose(true)

    local plural = count == 1 and "map" or "maps"
    local text = string.format(
        "This server has %d %s set up for TPG installed (it wants at least %d). "
        .. "Subscribe the server to the official TPG map collection to get more.\n\n"
        .. "On a dedicated server the collection must be added to the server's workshop "
        .. "collection (host_workshop_collection) for its maps to download.",
        count, plural, threshold)

    local label = vgui.Create("DLabel", frame)
    label:SetPos(S(16), S(36))
    label:SetSize(w - S(32), S(92))
    label:SetWrap(true)
    label:SetFont("TPG.HUD.Small")
    label:SetText(text)

    local gap = S(8)
    local bw = math.floor((w - S(32) - gap * 2) / 3)
    local by = h - S(44)

    local open = vgui.Create("DButton", frame)
    open:SetPos(S(16), by)
    open:SetSize(bw, S(30))
    open:SetText("Open collection")
    open.DoClick = function()
        openCollection()
    end

    local dismiss = vgui.Create("DButton", frame)
    dismiss:SetPos(S(16) + bw + gap, by)
    dismiss:SetSize(bw, S(30))
    dismiss:SetText("Don't show again")
    dismiss.DoClick = function()
        RunConsoleCommand("tpg_collection_hint", "0")
        frame:Close()
    end

    local close = vgui.Create("DButton", frame)
    close:SetPos(S(16) + (bw + gap) * 2, by)
    close:SetSize(bw, S(30))
    close:SetText("Close")
    close.DoClick = function()
        frame:Close()
    end
end

net.Receive("TPG_CollectionHint", function()
    local count = net.ReadUInt(8)
    local threshold = net.ReadUInt(8)
    net.ReadString() -- the collection id; the client already has it

    if not cvHint:GetBool() then return end

    chat.AddText(
        TPG_RED, "[TPG] ",
        color_white, string.format("Only %d supported map(s) are installed on this server (it wants %d). The official TPG map collection adds more: %s",
            count, threshold, COLLECTION_URL))

    showPopup(count, threshold)
end)
