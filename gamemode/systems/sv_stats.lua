--[[
    Persistent Player Stats & Rating (server)

    Lifetime stats across all maps/sessions, stored in data/tpg/stats.json
    keyed by SteamID64 (PData would work per-player, but a file gives us a
    leaderboard over everyone who's ever played, online or not).

    Rating drives the rank ladder (config/sh_ranks.lua) and the skill-based
    team scramble (sv_teams.lua). Everyone starts at 1000.

        kill          +10 (+ up to +20 scaled by the victim's vehicle value)
        death         -4
        teamkill      -15
        CP capture    +15 (each player on the point)
        flag delivery +25
        round win/loss +30 / -10 (everyone on the team, plus rounds++)

    The profile menu (ui/cl_menu_profile.lua) requests data over TPG_ProfileData.
]]

TPG.Stats = TPG.Stats or {}

local FILE = "tpg/stats.json"

local data  = {}     -- [sid64] = { name, rating, kills, deaths, teamkills, caps, flags, wins, rounds }
local dirty = false

-- ── Storage ─────────────────────────────────────────────────────────────────
local function Load()
    if not file.Exists(FILE, "DATA") then return end
    data = util.JSONToTable(file.Read(FILE, "DATA") or "") or {}
end

function TPG.Stats.Save()
    if not dirty then return end
    file.CreateDir("tpg")
    file.Write(FILE, util.TableToJSON(data, true))
    dirty = false
end

Load()
timer.Create("TPG_StatsAutosave", 60, 0, TPG.Stats.Save)
hook.Add("ShutDown", "TPG_StatsSave", TPG.Stats.Save)
hook.Add("PlayerDisconnected", "TPG_StatsSaveOnLeave", function() TPG.Stats.Save() end)

-- ── Accessors ───────────────────────────────────────────────────────────────
local function entry(ply)
    if not (IsValid(ply) and ply:IsPlayer()) or ply:IsBot() then return nil end
    local sid = ply:SteamID64()
    if not sid then return nil end

    if not data[sid] then
        data[sid] = {
            name = ply:Nick(), rating = 1000,
            kills = 0, deaths = 0, teamkills = 0,
            caps = 0, flags = 0, wins = 0, rounds = 0,
        }
    end
    data[sid].name = ply:Nick()
    return data[sid]
end

function TPG.Stats.Get(ply)
    return entry(ply)
end

function TPG.Stats.GetRating(ply)
    local e = entry(ply)
    return e and e.rating or 1000
end

local function addRating(e, amount)
    e.rating = math.max(math.floor(e.rating + amount), 100)
    dirty = true
end

-- Top N by rating, over everyone ever recorded.
function TPG.Stats.GetLeaderboard(n)
    local list = {}
    for _, e in pairs(data) do
        list[#list + 1] = e
    end
    table.sort(list, function(a, b) return (a.rating or 0) > (b.rating or 0) end)

    local top = {}
    for i = 1, math.min(n or 10, #list) do top[i] = list[i] end
    return top
end

-- ── Event hooks ─────────────────────────────────────────────────────────────
hook.Add("PlayerDeath", "TPG_StatsDeath", function(victim, _inflictor, attacker)
    local ve = entry(victim)
    if ve then
        ve.deaths = ve.deaths + 1
        -- Only lose rating to an actual enemy, not to drowning/falls/suicide.
        if IsValid(attacker) and attacker:IsPlayer() and attacker ~= victim
            and attacker:Team() ~= victim:Team() then
            addRating(ve, -4)
        end
        dirty = true
    end

    if not (IsValid(attacker) and attacker:IsPlayer()) or attacker == victim then return end
    local ae = entry(attacker)
    if not ae then return end

    if attacker:Team() == victim:Team() then
        ae.teamkills = ae.teamkills + 1
        addRating(ae, -15)
        return
    end

    ae.kills = ae.kills + 1
    local vehValue = (TPG.ACE and TPG.ACE.GetPlayerPoints and TPG.ACE.GetPlayerPoints(victim)) or 0
    addRating(ae, 10 + math.min(vehValue / 1000, 20))
end)

-- Control-point capture credit; called from TPG.Objectives.OnCapture per player.
function TPG.Stats.OnCapture(ply)
    local e = entry(ply)
    if not e then return end
    e.caps = e.caps + 1
    addRating(e, 15)
end

-- Flag delivery; called from TPG.CTF.OnCapture.
function TPG.Stats.OnFlagCapture(ply)
    local e = entry(ply)
    if not e then return end
    e.flags = e.flags + 1
    addRating(e, 25)
end

-- Round result; called from TPG.Rounds.EndRound.
function TPG.Stats.OnRoundEnd(winningTeam)
    for _, ply in ipairs(player.GetAll()) do
        if TPG.Util.IsOnTeam(ply) then
            local e = entry(ply)
            if e then
                e.rounds = e.rounds + 1
                if ply:Team() == winningTeam then e.wins = e.wins + 1 end
                addRating(e, ply:Team() == winningTeam and 30 or -10)
            end
        end
    end
    TPG.Stats.Save()
end

-- ── Profile networking ──────────────────────────────────────────────────────
util.AddNetworkString("TPG_ProfileData")

local LEADERBOARD_N = 10

net.Receive("TPG_ProfileData", function(_, ply)
    local e = entry(ply)
    if not e then return end

    local top = TPG.Stats.GetLeaderboard(LEADERBOARD_N)

    net.Start("TPG_ProfileData")
        net.WriteUInt(e.rating, 16)
        net.WriteUInt(e.kills, 24)
        net.WriteUInt(e.deaths, 24)
        net.WriteUInt(e.teamkills, 16)
        net.WriteUInt(e.caps, 16)
        net.WriteUInt(e.flags, 16)
        net.WriteUInt(e.wins, 16)
        net.WriteUInt(e.rounds, 16)

        net.WriteUInt(#top, 4)
        for _, t in ipairs(top) do
            net.WriteString(string.sub(t.name or "?", 1, 32))
            net.WriteUInt(t.rating or 1000, 16)
        end
    net.Send(ply)
end)
