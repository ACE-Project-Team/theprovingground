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

-- Retail SteamID64s are 17-digit strings in the 7656.. range. A listen-server
-- host (or any connection whose Steam auth hasn't settled) can briefly report
-- "0"/"NULL"/nil instead, and an older build banked the id in NUMERIC form --
-- which util.TableToJSON then serialised in scientific notation ("7.65..e+16"),
-- a key that is both lossy (can't be matched back to the player) and duplicated.
-- Reject anything that isn't a real SteamID64 so no junk key is ever created.
local function IsRealSteamID64(sid)
    return isstring(sid) and #sid == 17 and string.match(sid, "^7656%d+$") ~= nil
end

-- ── Storage ─────────────────────────────────────────────────────────────────
--[[
    Why this is an ARRAY on disk and not a map keyed by SteamID64.

    util.JSONToTable coerces any object key that parses as a number back into a
    Lua number -- and a SteamID64 is a 17-digit number, which a double cannot
    even represent exactly. So `{ ["76561198..."] = {...} }` does not survive a
    save/load round trip: it comes back keyed by a lossy float that can never be
    matched to a player again. The previous fix spotted the damaged rows and
    purged them, which turned "ratings are wrong after a restart" into "ratings
    are GONE after a restart" -- data/tpg/stats.json was being rewritten as {}.

    Values are not coerced, only keys. So the id lives in the record as a field
    and the file is a list; the map is rebuilt in memory on load.
]]
local FORMAT_VERSION = 2

--[[
    Crash safety.

    file.Write truncates and then writes, so a server that dies mid-write (or a
    disk that fills) leaves stats.json as a half-file. Nothing here used to
    notice: the parse just returned nil, the in-memory table stayed empty, and
    the next autosave wrote out ONLY the handful of players in that session --
    silently replacing the whole leaderboard with a fragment of it. A restart
    was all it took to lose everyone's lifetime record.

    So writes go to a temp file first and only replace the real one once they're
    complete, the previous good file is kept as .bak, and a file that fails to
    parse is preserved (never overwritten) so the ratings can be recovered by
    hand if the .bak is somehow bad too.
]]
local TMP = FILE .. ".tmp"
local BAK = FILE .. ".bak"

-- Read one candidate file into `data`. Returns how many records it yielded,
-- or nil if the file is unreadable/unparseable (as opposed to legitimately
-- empty, which is 0).
local function ReadInto(path)
    if not file.Exists(path, "DATA") then return nil end

    local body = file.Read(path, "DATA")
    if not body or body == "" then return nil end

    local raw = util.JSONToTable(body)
    if not istable(raw) then return nil end

    local count = 0

    if istable(raw.players) then
        for _, e in ipairs(raw.players) do
            local sid = e.sid and tostring(e.sid) or nil
            if IsRealSteamID64(sid) then
                e.sid = sid
                data[sid] = e
                count = count + 1
            end
        end
        return count
    end

    -- Legacy v1 file (keyed map). Whatever kept a usable string key is still
    -- readable; rows whose key was coerced to a float have genuinely lost the
    -- id and can't be recovered by anyone. Rewrite in v2 either way.
    for sid, e in pairs(raw) do
        if IsRealSteamID64(sid) and istable(e) then
            e.sid = sid
            data[sid] = e
            count = count + 1
        end
    end
    dirty = true
    return count
end

local function Load()
    -- A .tmp left behind means the last write never finished. The real file is
    -- still the last complete one, so the leftover is just noise -- but keep it
    -- rather than delete it, on the off chance it's the newer of the two.
    if file.Exists(TMP, "DATA") then
        file.Delete(FILE .. ".unfinished")
        file.Rename(TMP, FILE .. ".unfinished")
    end

    if not file.Exists(FILE, "DATA") then
        -- No main file, but a backup from a previous run is a complete file.
        if ReadInto(BAK) then
            print("[TPG] stats.json missing; recovered the leaderboard from stats.json.bak.")
            dirty = true
        end
        return
    end

    if ReadInto(FILE) then return end

    -- The main file exists and did not parse. Do not let it be overwritten --
    -- move it aside under a name nothing writes to, then fall back to .bak.
    local kept = FILE .. ".corrupt"
    file.Delete(kept)
    file.Rename(FILE, kept)

    print("[TPG] WARNING: data/tpg/stats.json is unreadable. Kept it as stats.json.corrupt.")

    if ReadInto(BAK) then
        print("[TPG] Recovered the leaderboard from stats.json.bak.")
    else
        print("[TPG] No usable backup either -- starting from an empty leaderboard.")
    end
    dirty = true
end

function TPG.Stats.Save()
    if not dirty then return end
    file.CreateDir("tpg")

    local out = { version = FORMAT_VERSION, players = {} }
    for sid, e in pairs(data) do
        e.sid = sid
        out.players[#out.players + 1] = e
    end

    -- Write the whole thing somewhere disposable first, so a write that dies
    -- half way through costs us the temp file and nothing else.
    file.Delete(TMP)
    file.Write(TMP, util.TableToJSON(out, true))

    if not file.Exists(TMP, "DATA") then
        print("[TPG] WARNING: could not write data/tpg/stats.json.tmp -- leaderboard NOT saved.")
        return   -- stay dirty; the next autosave tries again
    end

    -- Swap it in: current file becomes the backup, temp becomes current.
    if file.Exists(FILE, "DATA") then
        file.Delete(BAK)
        file.Rename(FILE, BAK)
    end
    file.Rename(TMP, FILE)

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
    if not IsRealSteamID64(sid) then return nil end

    if not data[sid] then
        data[sid] = {
            sid = sid, name = ply:Nick(), rating = 1000,
            kills = 0, deaths = 0, teamkills = 0,
            caps = 0, flags = 0, wins = 0, rounds = 0,
        }
        dirty = true   -- a brand new record is unsaved work too
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

-- Top N by rating, over everyone ever recorded. Duplicate display names are
-- collapsed to a single row (highest rating first, so the best one survives):
-- it keeps the same player from appearing more than once if older junk records
-- exist under a stale key. Two genuinely different players sharing a name is
-- rare enough that showing one of them in a top-N is an acceptable trade.
function TPG.Stats.GetLeaderboard(n)
    local list = {}
    for _, e in pairs(data) do
        list[#list + 1] = e
    end
    table.sort(list, function(a, b) return (a.rating or 0) > (b.rating or 0) end)

    local top, seen = {}, {}
    for _, e in ipairs(list) do
        local key = string.lower(e.name or "?")
        if not seen[key] then
            seen[key] = true
            top[#top + 1] = e
            if #top >= (n or 10) then break end
        end
    end
    return top
end

-- Wipe every lifetime record (admin tool for clearing corrupted test data).
function TPG.Stats.ResetAll()
    data = {}
    dirty = true
    TPG.Stats.Save()
end

-- ── Event hooks ─────────────────────────────────────────────────────────────
hook.Add("PlayerDeath", "TPG_StatsDeath", function(victim, _inflictor, attacker)
    -- A re-kit (the loadout menu's respawn button) isn't a death anyone earned,
    -- theirs or an enemy's, so it doesn't go on either record. See
    -- core/sv_commands.lua for tpg_rekit.
    if IsValid(victim) and TPG.State.GetPlayer(victim).rekit then return end

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

--[[
    Round result; called from TPG.Rounds.EndRound.

    Elo, not a flat +30/-10. Before applying the result we PREDICT it from the
    two teams' average ratings, and each player only moves by how far the real
    result was from that prediction: beating a stacked team is worth a lot,
    beating a team you were always going to beat is worth almost nothing, and
    losing a match you were expected to lose barely costs you.

    That's the "gets better as it builds up" property -- a flat +/- only ever
    measures how often you were on the winning side, which on a server with
    uneven teams mostly measures luck. This converges on actual effectiveness,
    and it's the number the scramble drafts on (player/sv_teams.lua), so the
    two systems improve together.
]]
local ELO_K = 40

local function TeamAverageRating(teamId)
    local total, count = 0, 0
    for _, ply in ipairs(team.GetPlayers(teamId)) do
        total = total + TPG.Stats.GetRating(ply)
        count = count + 1
    end
    if count == 0 then return 1000 end
    return total / count
end

function TPG.Stats.OnRoundEnd(winningTeam)
    local avg = {
        [TEAM_GREEN] = TeamAverageRating(TEAM_GREEN),
        [TEAM_RED]   = TeamAverageRating(TEAM_RED),
    }

    for _, ply in ipairs(player.GetAll()) do
        if TPG.Util.IsOnTeam(ply) then
            local e = entry(ply)
            if e then
                local own   = ply:Team()
                local enemy = TPG.GetEnemyTeam(own)
                local expected = 1 / (1 + 10 ^ (((avg[enemy] or 1000) - (avg[own] or 1000)) / 400))
                local actual   = (own == winningTeam) and 1 or 0

                e.rounds = e.rounds + 1
                if actual == 1 then e.wins = e.wins + 1 end
                addRating(e, ELO_K * (actual - expected))
            end
        end
    end
    TPG.Stats.Save()
end

-- How much of a player's record is objective play rather than fragging, as
-- captures+flags per round. The scramble uses this to make sure both sides get
-- people who actually stand on the point (see player/sv_teams.lua) -- rating
-- alone splits the good shooters evenly and can still hand one team every
-- capper on the server.
function TPG.Stats.GetObjectiveRate(ply)
    local e = entry(ply)
    if not e then return 0 end
    -- Under a handful of rounds there isn't a record yet, just noise.
    if (e.rounds or 0) < 3 then return 0 end
    return ((e.caps or 0) + (e.flags or 0)) / e.rounds
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
