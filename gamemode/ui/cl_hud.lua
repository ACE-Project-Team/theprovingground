--[[
    Main HUD
]]

TPG.UI = TPG.UI or {}
TPG.UI.State = {
    scores = { [TEAM_GREEN] = 300, [TEAM_RED] = 300 },
    limits = { [TEAM_GREEN] = {}, [TEAM_RED] = {} },
    maxLimits = { props = 300, weight = 100000, points = 100000 },  -- Default max limits
    gameType = GAMEMODE_CP,
    objectives = {},
    mapVote = {},
    voteTally = {},
    voteEnd = 0,
}

-- Ask the server for the current round state as soon as the client is fully
-- in-game -- without this, joining mid-round left the HUD on the default
-- gametype until the next round's broadcast.
hook.Add("InitPostEntity", "TPG_RequestState", function()
    net.Start("TPG_RequestState")
    net.SendToServer()
end)

-- Receive state sync
net.Receive("TPG_SyncState", function()
    TPG.UI.State.gameType = net.ReadUInt(4)
    TPG.UI.State.scores[TEAM_GREEN] = net.ReadUInt(16)
    TPG.UI.State.scores[TEAM_RED] = net.ReadUInt(16)
end)

net.Receive("TPG_SyncScores", function()
    TPG.UI.State.scores[TEAM_GREEN] = net.ReadInt(16)
    TPG.UI.State.scores[TEAM_RED] = net.ReadInt(16)
end)

net.Receive("TPG_SyncLimits", function()
    -- Current usage
    TPG.UI.State.limits[TEAM_GREEN].props = net.ReadUInt(12)
    TPG.UI.State.limits[TEAM_RED].props = net.ReadUInt(12)
    TPG.UI.State.limits[TEAM_GREEN].weight = net.ReadUInt(13) * 500
    TPG.UI.State.limits[TEAM_RED].weight = net.ReadUInt(13) * 500
    TPG.UI.State.limits[TEAM_GREEN].points = net.ReadUInt(16)
    TPG.UI.State.limits[TEAM_RED].points = net.ReadUInt(16)
    
    -- Max limits
    TPG.UI.State.maxLimits.props = net.ReadUInt(12)
    TPG.UI.State.maxLimits.weight = net.ReadUInt(13) * 500
    TPG.UI.State.maxLimits.points = net.ReadUInt(20)
end)

net.Receive("TPG_SyncMapVote", function()
    local count = net.ReadUInt(4)
    local seconds = net.ReadUInt(8)

    local maps = {}
    for i = 1, count do
        maps[i] = {
            map         = net.ReadString(),
            displayName = net.ReadString(),
            category    = net.ReadUInt(2),
            points      = net.ReadUInt(20),
            weight      = net.ReadUInt(13),
            props       = net.ReadUInt(12),
            objectives  = net.ReadUInt(4),
        }
    end

    TPG.UI.State.mapVote = maps
    TPG.UI.State.voteTally = {}
    TPG.UI.State.voteEnd = CurTime() + seconds
end)

net.Receive("TPG_SyncVoteTally", function()
    local count = net.ReadUInt(4)
    local tally = {}
    for i = 1, count do
        tally[i] = net.ReadUInt(8)
    end
    TPG.UI.State.voteTally = tally
end)

net.Receive("TPG_ChatMessage", function()
    local color = net.ReadColor()
    local message = net.ReadString()
    chat.AddText(color, message)
end)

-- Live teammate positions (server pushes our own team's, so markers track
-- teammates even outside our PVS -- see TPG.Net.SyncTeamPositions).
TPG.UI.teamPositions = {}
net.Receive("TPG_TeamPositions", function()
    local n, t = net.ReadUInt(7), {}
    for _ = 1, n do
        local idx = net.ReadUInt(12)
        t[idx] = net.ReadVector()
    end
    TPG.UI.teamPositions = t
end)

-- Objective cache
local objectiveCache = {}
local lastCacheUpdate = 0

local function UpdateObjectiveCache()
    if CurTime() - lastCacheUpdate < 0.5 then return end
    lastCacheUpdate = CurTime()
    objectiveCache = ents.FindByClass("tpg_controlpoint")
end

--[[
    Shared top-HUD layout.

    Everything stacked down the middle (score bar, point pips, compass, overtime
    tag) and the two corner boxes are laid out from here, in one pass, so no
    element has to guess where another one ended. Each stacked element asks the
    one above it where it finished -- BelowObjectives(), BelowCompass() -- which
    is what stops the overtime tag printing through the point letters and the
    compass through the pips.

    All values are authored at 1080p and scaled through TPG.UI.S(). The score
    panel is the one exception: it also gets CLAMPED against the real screen
    width, because the corner boxes are anchored to the edges and a fixed 750px
    centre panel overlaps them below about 1500px of width.
]]
TPG.UI.Layout = {}

-- HUDPaint hooks run in an arbitrary order, so any of them may be the first to
-- need the layout this frame. Recomputing is cheap, but memoising on the frame
-- number means every element in one frame sees the same numbers even if the
-- window is being resized while they draw.
local layoutFrame = -1

function TPG.UI.ComputeLayout()
    local L = TPG.UI.Layout
    if layoutFrame == FrameNumber() then return L end
    layoutFrame = FrameNumber()

    local S  = TPG.UI.S
    local sw = ScrW()

    L.margin = S(20)
    L.sideW  = S(248)
    L.sideY  = S(14)
    L.sideH  = TPG.Config.useACEPoints and S(92) or S(70)

    L.scoreY = S(10)
    L.scoreH = S(58)

    -- Fit between the corner boxes, never under them, and never so narrow the
    -- ticket numbers have nowhere to sit.
    local free = sw - 2 * (L.sideW + L.margin + S(12))
    L.scoreW = math.max(math.min(S(750), free), S(360))
    L.scoreX = sw / 2 - L.scoreW / 2

    L.pipY    = L.scoreY + L.scoreH + S(8)
    L.pipSize = S(24)
    L.pipGap  = S(6)

    return L
end

-- Bottom of the point-pip row (or of the score panel when there are no points).
function TPG.UI.BelowObjectives()
    local L = TPG.UI.ComputeLayout()
    local hasPips = #objectiveCache > 0
    return L.pipY + (hasPips and (L.pipSize + TPG.UI.S(8)) or 0)
end

-- Main HUD paint
hook.Add("HUDPaint", "TPG_HUD", function()
    local ply = LocalPlayer()
    if not IsValid(ply) or not ply:Alive() then return end

    local C = TPG.Colors
    local S = TPG.UI.S
    local L = TPG.UI.ComputeLayout()

    local teamId = ply:Team()
    local teamColor = C.Team(teamId)

    local limits = TPG.UI.State.limits[teamId] or {}
    local maxLimits = TPG.UI.State.maxLimits

    local sw = ScrW()

    -- ── Top left: mode ────────────────────────────────────────────────────
    TPG.UI.Pill(TPG.GetGameTypeName(TPG.UI.State.gameType), "TPG.HUD.Label",
        L.margin, S(14), S(34), C.Accent, C.Text)

    -- Per-player economy indicator (secondary mode) -- makes clear it's not just
    -- "economy on" but that each player runs a personal budget this round.
    if GetGlobalBool("TPG_EconomyActive", false) then
        TPG.UI.Pill("PER-PLAYER ECONOMY", "TPG.HUD.Small", L.margin, S(52), S(26), C.Good, C.Good)
    end

    -- ── Top right: your team's build budget ───────────────────────────────
    -- The team colour is a 3px edge rather than the panel fill it used to be:
    -- white text on flat #00FF21 was close to unreadable, and a saturated block
    -- that size fought with everything else on screen.
    local pw, ph = L.sideW, L.sideH
    local px, py = sw - pw - L.margin, L.sideY
    TPG.UI.Panel(px, py, pw, ph, teamColor)
    draw.RoundedBox(0, px, py + S(8), math.max(S(3), 1), ph - S(16), teamColor)

    local function stat(row, label, value)
        local ry = py + S(12) + row * S(24)
        draw.SimpleText(label, "TPG.HUD.Small", px + S(16), ry, C.TextMuted, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)
        draw.SimpleText(value, "TPG.HUD.Small", px + pw - S(16), ry, C.Text, TEXT_ALIGN_RIGHT, TEXT_ALIGN_TOP)
    end

    stat(0, "PROPS",  (limits.props or 0) .. " / " .. maxLimits.props)
    stat(1, "WEIGHT", math.floor((limits.weight or 0) / 1000) .. "T / " ..
                      math.floor(maxLimits.weight / 1000) .. "T")
    if TPG.Config.useACEPoints then
        stat(2, "POINTS", (limits.points or 0) .. " / " .. maxLimits.points)
    end

    -- ── Top centre: tickets ───────────────────────────────────────────────
    local sx = L.scoreX
    TPG.UI.Panel(sx, L.scoreY, L.scoreW, L.scoreH)

    local greenScore = TPG.UI.State.scores[TEAM_GREEN] or 300
    local redScore   = TPG.UI.State.scores[TEAM_RED] or 300
    local maxScore   = math.max(TPG.Config.startingTickets, 1)

    --[[
        Bar geometry is derived, not hardcoded. The ticket counts sit OUTSIDE
        their bars (right-aligned on the left, left-aligned on the right), so a
        hand-picked bar width silently decides whether the number still fits
        inside the panel -- pick 300 and the green count hangs off the left
        edge. Working inward from the panel edge by a text budget instead means
        the numbers are always inside it.
    ]]
    local PAD, NUMW, GAP, HALFGAP = S(16), S(48), S(8), S(26)
    local barH = S(22)
    local barY = L.scoreY + S(20)
    local gx   = sx + PAD + NUMW + GAP
    local barW = (sw / 2 - HALFGAP) - gx
    local rx   = sw / 2 + HALFGAP
    local barR = S(4)

    -- Troughs first, so a team on its last few tickets still shows a bar
    -- against something instead of vanishing into the panel.
    draw.RoundedBox(barR, gx, barY, barW, barH, C.Trough)
    draw.RoundedBox(barR, rx, barY, barW, barH, C.Trough)

    local gW = math.max(math.Clamp(greenScore / maxScore, 0, 1) * barW, 2)
    local rW = math.max(math.Clamp(redScore   / maxScore, 0, 1) * barW, 2)
    -- Both bars grow away from the centre divider and shrink back toward it, so
    -- "who is winning" reads as which side of the middle is fuller.
    draw.RoundedBox(barR, gx + barW - gW, barY, gW, barH, C.Green)
    draw.RoundedBox(barR, rx, barY, rW, barH, C.Red)

    draw.SimpleText(math.floor(greenScore), "TPG.HUD.Num", gx - GAP, barY + barH / 2,
        C.GreenText, TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
    draw.SimpleText(math.floor(redScore), "TPG.HUD.Num", rx + barW + GAP, barY + barH / 2,
        C.RedText, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
    draw.SimpleText("VS", "TPG.HUD.Small", sw / 2, barY + barH / 2,
        C.TextMuted, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)

    -- ── Point pips ────────────────────────────────────────────────────────
    UpdateObjectiveCache()

    local pointCount = #objectiveCache
    if pointCount > 0 then
        local pitch  = L.pipSize + L.pipGap
        local rowW   = pointCount * pitch - L.pipGap
        local startX = sw / 2 - rowW / 2

        for i, obj in ipairs(objectiveCache) do
            if IsValid(obj) then
                local pointColor = obj:GetColor()
                local pointName  = obj:GetNWString("PointName", "?")
                local initial    = string.upper(string.sub(pointName, 1, 1))

                local bx = startX + (i - 1) * pitch
                local by = L.pipY
                local edge = math.max(S(2), 1)

                draw.RoundedBox(S(4), bx - edge, by - edge, L.pipSize + edge * 2, L.pipSize + edge * 2, C.Shadow)
                draw.RoundedBox(S(3), bx, by, L.pipSize, L.pipSize, pointColor)
                TPG.UI.TextInBox(initial, "TPG.HUD.Pip", bx, by, L.pipSize, L.pipSize,
                    C.Contrast(pointColor))
            end
        end
    end

    -- Draw teammates
    TPG.UI.DrawTeammates(ply, teamId, teamColor)
end)

function TPG.UI.DrawTeammates(ply, teamId, teamColor)
    local positions = TPG.UI.teamPositions or {}
    for _, teammate in ipairs(team.GetPlayers(teamId)) do
        if teammate == ply then continue end

        -- Prefer the server-pushed position (accurate even out of PVS); fall
        -- back to the entity's own position if we haven't got one yet.
        local pos = positions[teammate:EntIndex()]
        if pos then
            pos = pos + Vector(0, 0, 50)
        else
            pos = teammate:GetPos() + teammate:OBBCenter()
        end

        local screenPos = pos:ToScreen()

        if screenPos.visible then
            local dot = math.max(TPG.UI.S(6), 3)
            surface.SetDrawColor(teamColor)
            surface.DrawRect(screenPos.x - dot / 2, screenPos.y - dot / 2, dot, dot)
            draw.SimpleText(teammate:Nick(), "TPG.HUD.Small", screenPos.x, screenPos.y + dot + TPG.UI.S(4),
                color_white, TEXT_ALIGN_CENTER)
        end
    end
end

-- Hide default HUD elements.
-- NOTE: CHudBattery (the suit-armour panel) is intentionally NOT hidden --
-- armour tiers hand out real armour (Light 50 ... Juggernaut 999999) and this
-- is the only thing that draws it, so hiding it made players think they got
-- none. Health uses the default CHudHealth, so this keeps the two consistent.
local hideElements = {
}

hook.Add("HUDShouldDraw", "TPG_HideHUD", function(name)
    if hideElements[name] then return false end
end)