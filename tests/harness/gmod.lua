--[[
    A stand-in for the parts of the GMod API the shared TPG files touch.

    This is a stub, not an emulator, and the distinction matters when reading a
    test failure: a test proves the gamemode's own logic, not that GMod behaves
    the way this file says it does. Anything here that is a real GMod behaviour
    rather than an obvious no-op is commented with why it is written that way,
    because those are the places where the stub could silently drift away from
    the engine and make a passing test meaningless.

    Realm: SERVER. `config/sh_palette.lua` returns early when CLIENT is unset,
    which keeps the whole VGUI/surface/draw surface out of scope -- the client
    HUD is drawing code with no return values to assert on, and stubbing enough
    of `surface` to run it would be testing the stub.
]]

local M = {}

--- Install the stubs as globals.
-- Idempotent, and safe to call before loading any gamemode file.
function M.install()
    SERVER = true
    CLIENT = false
    GM = GM or {}
    GAMEMODE = GM

    ------------------------------------------------------------------ types

    -- GMod's Vector is userdata; the handful of methods used by the shared
    -- files are all this needs to stand in for it.
    local VectorMeta = {}
    VectorMeta.__index = VectorMeta

    function VectorMeta:Distance(other)
        return math.sqrt(self:DistToSqr(other))
    end

    function VectorMeta:DistToSqr(other)
        local dx, dy, dz = self.x - other.x, self.y - other.y, self.z - other.z
        return dx * dx + dy * dy + dz * dz
    end

    function VectorMeta:Length()
        return math.sqrt(self.x ^ 2 + self.y ^ 2 + self.z ^ 2)
    end

    function VectorMeta:Unpack() return self.x, self.y, self.z end

    VectorMeta.__eq = function(a, b)
        return a.x == b.x and a.y == b.y and a.z == b.z
    end

    VectorMeta.__tostring = function(v)
        return string.format("[%g %g %g]", v.x, v.y, v.z)
    end

    function Vector(x, y, z)
        return setmetatable({ x = x or 0, y = y or 0, z = z or 0 }, VectorMeta)
    end

    -- Unlike Vector, GMod's Color really is a plain table, so istable(Color(...))
    -- is true there and here.
    local ColorMeta = { __index = {} }
    ColorMeta.__eq = function(a, b)
        return a.r == b.r and a.g == b.g and a.b == b.b and a.a == b.a
    end

    function Color(r, g, b, a)
        return setmetatable({ r = r or 0, g = g or 0, b = b or 0, a = a or 255 }, ColorMeta)
    end

    color_white = Color(255, 255, 255)
    color_black = Color(0, 0, 0)

    function IsColor(v)
        return type(v) == "table" and getmetatable(v) == ColorMeta
    end

    -- istable is false for a Vector in GMod because a Vector is userdata there.
    -- table.Copy branches on exactly this, and TPG.Maps.Load copies map configs
    -- full of Vectors, so getting it wrong here would change what the tests see.
    function istable(v)
        return type(v) == "table" and getmetatable(v) ~= VectorMeta
    end

    function isstring(v) return type(v) == "string" end
    function isnumber(v) return type(v) == "number" end
    function isfunction(v) return type(v) == "function" end
    function isbool(v) return type(v) == "boolean" end
    function isvector(v) return getmetatable(v) == VectorMeta end

    function IsValid(v)
        if not v then return false end
        if type(v) == "table" and v.IsValid then return v:IsValid() end
        return false
    end

    ------------------------------------------------------------------- math

    function math.Clamp(v, lo, hi)
        if v < lo then return lo end
        if v > hi then return hi end
        return v
    end

    -- GMod rounds half away from zero, which is not what a naive
    -- math.floor(x + 0.5) does for negatives.
    function math.Round(v, decimals)
        local mult = 10 ^ (decimals or 0)
        if v >= 0 then
            return math.floor(v * mult + 0.5) / mult
        end
        return math.ceil(v * mult - 0.5) / mult
    end

    function math.Approach(cur, target, inc)
        inc = math.abs(inc)
        if cur < target then return math.min(cur + inc, target) end
        if cur > target then return math.max(cur - inc, target) end
        return target
    end

    function math.Remap(v, inMin, inMax, outMin, outMax)
        return outMin + (v - inMin) * (outMax - outMin) / (inMax - inMin)
    end

    ------------------------------------------------------------------ table

    -- Deep copy, following GMod's implementation: shared subtables are copied
    -- once and reused, and the metatable comes along (which is what keeps a
    -- copied Vector a Vector).
    function table.Copy(t, lookup)
        if t == nil then return nil end
        local copy = setmetatable({}, getmetatable(t))
        for k, v in pairs(t) do
            if not istable(v) then
                copy[k] = v
            else
                lookup = lookup or {}
                lookup[t] = copy
                copy[k] = lookup[v] or table.Copy(v, lookup)
            end
        end
        return copy
    end

    -- Recursive by default: a table value merges into an existing table value
    -- rather than replacing it. TPG.Maps.Load relies on that -- a map that
    -- overrides only `limits.weight` must keep the default's other fields.
    function table.Merge(dest, source, forceOverride)
        for k, v in pairs(source) do
            if not forceOverride and istable(v) and istable(dest[k]) then
                table.Merge(dest[k], v)
            else
                dest[k] = v
            end
        end
        return dest
    end

    function table.HasValue(t, val)
        for _, v in pairs(t) do
            if v == val then return true end
        end
        return false
    end

    function table.Count(t)
        local n = 0
        for _ in pairs(t) do n = n + 1 end
        return n
    end

    function table.GetKeys(t)
        local keys = {}
        for k in pairs(t) do keys[#keys + 1] = k end
        return keys
    end

    function table.Random(t)
        local keys = table.GetKeys(t)
        if #keys == 0 then return nil end
        local k = keys[math.random(#keys)]
        return t[k], k
    end

    function table.Add(dest, source)
        for _, v in ipairs(source) do dest[#dest + 1] = v end
        return dest
    end

    ----------------------------------------------------------------- string

    function string.Explode(sep, str)
        local out = {}
        for piece in string.gmatch(str, "([^" .. sep .. "]+)") do
            out[#out + 1] = piece
        end
        return out
    end

    function string.Trim(s)
        return (string.gsub(s, "^%s*(.-)%s*$", "%1"))
    end

    ------------------------------------------------------------------ hooks

    M.hooks = {}
    hook = {
        Add = function(event, name, fn)
            M.hooks[event] = M.hooks[event] or {}
            M.hooks[event][name] = fn
        end,
        Remove = function(event, name)
            if M.hooks[event] then M.hooks[event][name] = nil end
        end,
        GetTable = function() return M.hooks end,
        Run = function(event, ...)
            for _, fn in pairs(M.hooks[event] or {}) do
                local r = fn(...)
                if r ~= nil then return r end
            end
        end,
    }
    hook.Call = function(event, _, ...) return hook.Run(event, ...) end

    ------------------------------------------------------------------ teams

    M.teams = {}
    M.players = {}

    team = {
        SetUp = function(id, name, color)
            M.teams[id] = { name = name, color = color, players = {} }
        end,
        Valid = function(id) return M.teams[id] ~= nil end,
        GetName = function(id) return M.teams[id] and M.teams[id].name or "" end,
        GetColor = function(id) return M.teams[id] and M.teams[id].color end,
        GetAllTeams = function() return M.teams end,
        GetPlayers = function(id)
            local out = {}
            for _, p in ipairs(M.players) do
                if p:Team() == id then out[#out + 1] = p end
            end
            return out
        end,
        NumPlayers = function(id) return #team.GetPlayers(id) end,
    }

    player = {
        GetAll = function() return M.players end,
        GetCount = function() return #M.players end,
    }

    ---------------------------------------------------------------- globals

    M.globals = {}
    function GetGlobalBool(k, d)
        local v = M.globals[k]
        if v == nil then return d end
        return v
    end
    function SetGlobalBool(k, v) M.globals[k] = v end
    function GetGlobalInt(k, d) local v = M.globals[k]; if v == nil then return d end; return v end
    function SetGlobalInt(k, v) M.globals[k] = v end
    function GetGlobalFloat(k, d) local v = M.globals[k]; if v == nil then return d end; return v end
    function SetGlobalFloat(k, v) M.globals[k] = v end
    function GetGlobalString(k, d) local v = M.globals[k]; if v == nil then return d end; return v end
    function SetGlobalString(k, v) M.globals[k] = v end

    ------------------------------------------------------------------ misc

    -- Console output is swallowed by default: loading the gamemode prints a
    -- dozen banner lines that would bury the test results. M.output collects
    -- them so a test can still assert on a warning being printed.
    M.output = {}
    M.quiet = true

    local function record(...)
        local parts = {}
        for i = 1, select("#", ...) do parts[#parts + 1] = tostring((select(i, ...))) end
        local line = table.concat(parts, "\t")
        M.output[#M.output + 1] = line
        if not M.quiet then io.write(line, "\n") end
    end

    print = record
    Msg = record
    MsgN = record
    MsgC = record
    ErrorNoHalt = record
    ErrorNoHaltWithStack = record

    M.map = "gm_flatgrass"
    game = {
        GetMap = function() return M.map end,
        SinglePlayer = function() return false end,
        MaxPlayers = function() return 32 end,
    }

    M.curtime = 0
    function CurTime() return M.curtime end
    function RealTime() return M.curtime end
    function SysTime() return M.curtime end
    function UnPredictedCurTime() return M.curtime end
    function FrameTime() return 1 / 66 end

    timer = {
        Simple = function() end,
        Create = function() end,
        Remove = function() end,
        Exists = function() return false end,
        Adjust = function() end,
    }

    concommand = { Add = function() end, Remove = function() end }

    M.convars = {}
    function CreateConVar(name, default)
        M.convars[name] = default
        return {
            GetInt = function() return tonumber(M.convars[name]) or 0 end,
            GetBool = function() return tostring(M.convars[name]) ~= "0" end,
            GetFloat = function() return tonumber(M.convars[name]) or 0 end,
            GetString = function() return tostring(M.convars[name]) end,
        }
    end
    function GetConVar(name)
        if M.convars[name] == nil then return nil end
        return CreateConVar(name, M.convars[name])
    end

    -- No filesystem: the shared files only use file.Exists to detect whether
    -- the E2/Starfall sandbox addon is mounted, and a test server has no view
    -- of that anyway.
    M.files = {}
    file = {
        Exists = function(path) return M.files[path] ~= nil end,
        Read = function(path) return M.files[path] end,
        Write = function(path, data) M.files[path] = data end,
        Delete = function(path) M.files[path] = nil end,
        CreateDir = function() end,
        Find = function() return {}, {} end,
    }

    util = {
        TableToJSON = function() return "{}" end,
        JSONToTable = function() return {} end,
        AddNetworkString = function(s) return s end,
    }

    net = {
        Start = function() end, Send = function() end, Broadcast = function() end,
        SendToServer = function() end, Receive = function() end,
        WriteString = function() end, WriteInt = function() end,
        WriteUInt = function() end, WriteBool = function() end,
        WriteFloat = function() end, WriteColor = function() end,
        WriteEntity = function() end, WriteVector = function() end,
        WriteTable = function() end,
        ReadString = function() return "" end, ReadInt = function() return 0 end,
        ReadUInt = function() return 0 end, ReadBool = function() return false end,
        ReadFloat = function() return 0 end, ReadColor = function() return color_white end,
        ReadEntity = function() return nil end, ReadVector = function() return Vector() end,
        ReadTable = function() return {} end,
    }

    resource = { AddFile = function() end, AddWorkshop = function() end }
    scripted_ents = { Register = function() end, Get = function() end }
    list = { Set = function() end, Get = function() return {} end }
    umsg = { Start = function() end, End = function() end }
    duplicator = { RegisterEntityClass = function() end }
    properties = { Add = function() end }
    cvars = { AddChangeCallback = function() end }

    M.sweps = {}
    weapons = {
        GetList = function() return M.sweps end,
        Register = function(swep, class) swep.ClassName = class; M.sweps[#M.sweps + 1] = swep end,
        Get = function(class)
            for _, s in ipairs(M.sweps) do
                if s.ClassName == class then return s end
            end
        end,
    }

    function DeriveGamemode() end
    function AddCSLuaFile() end
    function CreateClientConVar(name, default) return CreateConVar(name, default) end
    function Entity() return nil end
    function ents_Create() return nil end
    ents = { Create = function() return nil end, FindByClass = function() return {} end,
             GetAll = function() return {} end, FindInSphere = function() return {} end }

    return M
end

--- Reset the mutable parts between tests, leaving loaded gamemode state alone.
function M.reset()
    M.teams, M.players, M.globals, M.output = {}, {}, {}, {}
    M.sweps, M.files, M.hooks = {}, {}, {}
    M.curtime = 0
    M.map = "gm_flatgrass"
end

--- A fake player, good enough for the team and utility helpers.
-- @tparam number teamId
-- @tparam[opt] table fields Extra fields/methods merged onto the player.
function M.player(teamId, fields)
    local ply = {
        _team = teamId,
        _pdata = {},
        Team = function(self) return self._team end,
        SetTeam = function(self, t) self._team = t end,
        IsValid = function() return true end,
        IsConnected = function() return true end,
        IsFullyAuthenticated = function() return true end,
        IsSuperAdmin = function() return false end,
        IsAdmin = function() return false end,
        Nick = function() return "TestPlayer" end,
        SteamID = function() return "STEAM_0:0:1" end,
        GetPos = function(self) return self._pos or Vector(0, 0, 0) end,
        SetPos = function(self, p) self._pos = p end,
        GetPData = function(self, k, d) local v = self._pdata[k]; if v == nil then return d end; return v end,
        SetPData = function(self, k, v) self._pdata[k] = tostring(v) end,
        SendLua = function() end,
        EmitSound = function() end,
        Kick = function(self) self._kicked = true end,
    }

    for k, v in pairs(fields or {}) do ply[k] = v end

    M.players[#M.players + 1] = ply
    return ply
end

return M
