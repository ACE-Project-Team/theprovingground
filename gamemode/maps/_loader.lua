--[[
    Map Configuration Loader
]]

TPG.Maps = TPG.Maps or {}

-- Default map configuration (used as fallback)
TPG.Maps.Default = {
    spawns = {
        [TEAM_GREEN] = Vector(0, 500, 100),
        [TEAM_RED]   = Vector(0, -500, 100),
    },
    limits = {
        weight = 200,
        props = 300,
        points = 100000,
    },
    safezoneRadius = 750,
    winsToMapVote = 2,
    
    [GAMEMODE_CP] = {
        capMultiplier = 0.02,
        objectives = {
            { pos = Vector(0, 0, 100), name = "Center Point" },
        },
    },
    [GAMEMODE_KOTH] = {
        capMultiplier = 0.15,
        objectives = {
            { pos = Vector(0, 0, 100), name = "The Hill" },
        },
    },
    [GAMEMODE_DM] = {
        capMultiplier = 0,
        objectives = {},
    },
}

-- Inline map configurations (no separate files needed)
TPG.Maps.Configs = {
    ["gm_construct"] = {
        spawns = {
            [TEAM_GREEN] = Vector(727, 548, -143),
            [TEAM_RED]   = Vector(-4970, -3434, 251),
        },
        limits = {
            weight = 120,
            props = 200,
            points = 100000,
        },
        safezoneRadius = 750,
        winsToMapVote = 5,
        
        [GAMEMODE_CP] = {
            capMultiplier = 0.15,
            objectives = {
                { pos = Vector(-2563, -1217, 240), name = "Roof" },
                { pos = Vector(-2563, -417, 240),  name = "Roof Side" },
            },
        },
        [GAMEMODE_KOTH] = {
            capMultiplier = 0.15,
            objectives = {
                { pos = Vector(-2563, -1217, 240), name = "The Hill" },
            },
        },
        [GAMEMODE_DM] = {
            capMultiplier = 0,
            objectives = {},
        },
    },
    
    ["gm_flatgrass"] = {
        spawns = {
            [TEAM_GREEN] = Vector(0, 2000, 100),
            [TEAM_RED]   = Vector(0, -2000, 100),
        },
        limits = {
            weight = 100,
            props = 300,
            points = 5000,
        },
        safezoneRadius = 750,
        
        [GAMEMODE_CP] = {
            capMultiplier = 0.02,
            objectives = {
                { pos = Vector(2000, 0, 100), name = "East Point" },
                { pos = Vector(0, 0, 100), name = "Center" },
                { pos = Vector(-2000, 0, 100), name = "West Point" },
            },
        },
        [GAMEMODE_KOTH] = {
            capMultiplier = 0.15,
            objectives = {
                { pos = Vector(0, 0, 100), name = "The Hill" },
            },
        },
        [GAMEMODE_DM] = {
            capMultiplier = 0,
            objectives = {},
        },
    },
    
    ["gm_baik_citycentre_v3"] = {
        spawns = {
            [TEAM_GREEN] = Vector(5280, 4760, 256),
            [TEAM_RED]   = Vector(-5280, -4760, 256),
        },
        limits = {
            weight = 60,
            props = 150,
            points = 2500,
        },
        safezoneRadius = 750,
        
        [GAMEMODE_CP] = {
            capMultiplier = 0.02,
            objectives = {
                { pos = Vector(3400, -1928, 16), name = "Green Park" },
                { pos = Vector(-3400, 1928, 16), name = "Red Park" },
            },
        },
        [GAMEMODE_KOTH] = {
            capMultiplier = 0.15,
            objectives = {
                { pos = Vector(0, 0, 16), name = "The Hill" },
            },
        },
        [GAMEMODE_DM] = {
            capMultiplier = 0,
            objectives = {},
        },
    },
    
    ["gm_baik_coast_03"] = {
        spawns = {
            [TEAM_GREEN] = Vector(-4678, -5985, 501),
            [TEAM_RED]   = Vector(7312, 4011, 295),
        },
        limits = {
            weight = 120,
            props = 300,
            points = 5000,
        },
        safezoneRadius = 750,
        
        [GAMEMODE_CP] = {
            capMultiplier = 0.025,
            objectives = {
                { pos = Vector(-5137, 3755, 256), name = "Beach House" },
                { pos = Vector(-217, 8201, 62), name = "Docks" },
            },
        },
        [GAMEMODE_KOTH] = {
            capMultiplier = 0.15,
            objectives = {
                { pos = Vector(-6480, 10373, 219), name = "The Hill" },
            },
        },
        [GAMEMODE_DM] = {
            capMultiplier = 0,
            objectives = {},
        },
    },
    
    ["gm_baik_construct_draft1"] = {
        spawns = {
            [TEAM_GREEN] = Vector(-3038, 3038, 17),
            [TEAM_RED]   = Vector(3038, -3038, 17),
        },
        limits = {
            weight = 40,
            props = 150,
            points = 2000,
        },
        safezoneRadius = 750,
        
        [GAMEMODE_CP] = {
            capMultiplier = 0.02,
            objectives = {
                { pos = Vector(2802, 3016, 4), name = "Parking Lot A" },
                { pos = Vector(0, 0, 424), name = "Parking Garage" },
                { pos = Vector(-2802, -3016, 4), name = "Parking Lot B" },
            },
        },
        [GAMEMODE_KOTH] = {
            capMultiplier = 0.15,
            objectives = {
                { pos = Vector(0, 0, 2), name = "The Hill" },
            },
        },
        [GAMEMODE_DM] = {
            capMultiplier = 0,
            objectives = {},
        },
    },
    
    ["gm_de_port_opened_v2"] = {
        spawns = {
            [TEAM_GREEN] = Vector(-1920, 3944, 513),
            [TEAM_RED]   = Vector(2245, -3674, 777),
        },
        limits = {
            weight = 40,
            props = 150,
            points = 2000,
        },
        safezoneRadius = 750,
        
        [GAMEMODE_CP] = {
            capMultiplier = 0.02,
            objectives = {
                { pos = Vector(-1022, 137, 512), name = "Warehouse" },
                { pos = Vector(1119, 190, 642), name = "Oil" },
                { pos = Vector(2212, 1339, 512), name = "Coast" },
            },
        },
        [GAMEMODE_KOTH] = {
            capMultiplier = 0.15,
            objectives = {
                { pos = Vector(1119, 190, 642), name = "The Hill" },
            },
        },
        [GAMEMODE_DM] = {
            capMultiplier = 0,
            objectives = {},
        },
    },
    
    ["gm_emp_arid"] = {
        spawns = {
            [TEAM_GREEN] = Vector(13127, -11026, 513),
            [TEAM_RED]   = Vector(-11004, 12164, 537),
        },
        limits = {
            weight = 120,
            props = 300,
            points = 5000,
        },
        safezoneRadius = 750,
        
        [GAMEMODE_CP] = {
            capMultiplier = 0.02,
            objectives = {
                { pos = Vector(-1065, -12302, 512), name = "Bunker" },
                { pos = Vector(-604, -874, 359), name = "Bridge" },
                { pos = Vector(-4341, 6071, 472), name = "Small Hill" },
            },
        },
        [GAMEMODE_KOTH] = {
            capMultiplier = 0.15,
            objectives = {
                { pos = Vector(-604, -874, 359), name = "The Hill" },
            },
        },
        [GAMEMODE_DM] = {
            capMultiplier = 0,
            objectives = {},
        },
    },
    
    ["gm_emp_manticore"] = {
        spawns = {
            [TEAM_GREEN] = Vector(-6670, -3958, 1760),
            [TEAM_RED]   = Vector(10288, 2047, 1761),
        },
        limits = {
            weight = 80,
            props = 250,
            points = 4000,
        },
        safezoneRadius = 750,
        
        [GAMEMODE_CP] = {
            capMultiplier = 0.02,
            objectives = {
                { pos = Vector(3897, -4170, 1744), name = "Brick Factory" },
                { pos = Vector(12, 251, 2048), name = "Bridge" },
                { pos = Vector(-3988, 4155, 1744), name = "Office" },
            },
        },
        [GAMEMODE_KOTH] = {
            capMultiplier = 0.15,
            objectives = {
                { pos = Vector(12, 251, 2048), name = "The Hill" },
            },
        },
        [GAMEMODE_DM] = {
            capMultiplier = 0,
            objectives = {},
        },
    },
    
    ["gm_emp_midbridge"] = {
        spawns = {
            [TEAM_GREEN] = Vector(632, -9715, 2081),
            [TEAM_RED]   = Vector(-628, 9755, 2081),
        },
        limits = {
            weight = 160,
            props = 300,
            points = 6000,
        },
        safezoneRadius = 750,
        
        [GAMEMODE_CP] = {
            capMultiplier = 0.01,
            objectives = {
                { pos = Vector(7931, -3408, 32), name = "A Ruins" },
                { pos = Vector(-7909, 3435, 32), name = "B Ruins" },
                { pos = Vector(0, 0, 2048), name = "Hell aBridged" },
                { pos = Vector(0, 0, -255), name = "Under the Bridge" },
            },
        },
        [GAMEMODE_KOTH] = {
            capMultiplier = 0.15,
            objectives = {
                { pos = Vector(0, 0, -255), name = "The Hill" },
            },
        },
        [GAMEMODE_DM] = {
            capMultiplier = 0,
            objectives = {},
        },
    },
    
    ["gm_emp_palmbay"] = {
        spawns = {
            [TEAM_GREEN] = Vector(-6577, -8994, -2331),
            [TEAM_RED]   = Vector(8857, 10746, -2331),
        },
        limits = {
            weight = 80,
            props = 250,
            points = 4000,
        },
        safezoneRadius = 750,
        
        [GAMEMODE_CP] = {
            capMultiplier = 0.02,
            objectives = {
                { pos = Vector(-7173, 11422, -2884), name = "Island" },
                { pos = Vector(313, -499, -2953), name = "Beach House" },
                { pos = Vector(3801, -9546, -2575), name = "Grassland" },
            },
        },
        [GAMEMODE_KOTH] = {
            capMultiplier = 0.15,
            objectives = {
                { pos = Vector(313, -499, -2953), name = "The Hill" },
            },
        },
        [GAMEMODE_DM] = {
            capMultiplier = 0,
            objectives = {},
        },
    },
    
    ["gm_greenchoke"] = {
        spawns = {
            [TEAM_GREEN] = Vector(-9156, 10610, 1038),
            [TEAM_RED]   = Vector(9055, -10722, 1038),
        },
        limits = {
            weight = 100,
            props = 250,
            points = 4500,
        },
        safezoneRadius = 750,
        
        [GAMEMODE_CP] = {
            capMultiplier = 0.01,
            objectives = {
                { pos = Vector(6295, 2018, 1043), name = "Mountain Outpost" },
                { pos = Vector(-5961, 2032, 929), name = "Town Outpost" },
                { pos = Vector(495, -1037, 1184), name = "Bridge" },
                { pos = Vector(-85, 3492, 910), name = "Island A" },
                { pos = Vector(175, -5296, 844), name = "Island B" },
            },
        },
        [GAMEMODE_KOTH] = {
            capMultiplier = 0.15,
            objectives = {
                { pos = Vector(495, -1037, 1184), name = "The Hill" },
            },
        },
        [GAMEMODE_DM] = {
            capMultiplier = 0,
            objectives = {},
        },
    },
    
    ["gm_baik_frontline"] = {
        spawns = {
            [TEAM_GREEN] = Vector(-9284, 357, -20),
            [TEAM_RED]   = Vector(6748, 485, -21),
        },
        limits = {
            weight = 60,
            props = 200,
            points = 3000,
        },
        safezoneRadius = 750,
        
        [GAMEMODE_CP] = {
            capMultiplier = 0.02,
            objectives = {
                { pos = Vector(1718, 30, -45), name = "No Mans Land A" },
                { pos = Vector(-1260, 409, 79), name = "Fort Center" },
                { pos = Vector(-4932, 142, -49), name = "No Mans Land B" },
            },
        },
        [GAMEMODE_KOTH] = {
            capMultiplier = 0.15,
            objectives = {
                { pos = Vector(-1260, 409, 79), name = "The Hill" },
            },
        },
        [GAMEMODE_DM] = {
            capMultiplier = 0,
            objectives = {},
        },
    },
    
    ["gm_baik_stalingrad"] = {
        spawns = {
            [TEAM_GREEN] = Vector(-1360, -8207, 1),
            [TEAM_RED]   = Vector(-1428, 2101, 1),
        },
        limits = {
            weight = 80,
            props = 250,
            points = 4000,
        },
        safezoneRadius = 750,
        
        [GAMEMODE_CP] = {
            capMultiplier = 0.02,
            objectives = {
                { pos = Vector(-7549, -2147, 0), name = "Railroad" },
                { pos = Vector(-2254, -2538, -56), name = "Factory Ruins" },
                { pos = Vector(1516, -2438, 448), name = "Office Ruins" },
            },
        },
        [GAMEMODE_KOTH] = {
            capMultiplier = 0.15,
            objectives = {
                { pos = Vector(-2254, -2538, -56), name = "The Hill" },
            },
        },
        [GAMEMODE_DM] = {
            capMultiplier = 0,
            objectives = {},
        },
    },
    
    ["gm_baik_trenches"] = {
        spawns = {
            [TEAM_GREEN] = Vector(3852, 0, 102),
            [TEAM_RED]   = Vector(-3852, 0, 102),
        },
        limits = {
            weight = 60,
            props = 200,
            points = 3000,
        },
        safezoneRadius = 750,
        
        [GAMEMODE_CP] = {
            capMultiplier = 0.02,
            objectives = {
                { pos = Vector(-2874, 2570, 201), name = "Corner Hill A" },
                { pos = Vector(0, 0, 3), name = "No-Mans Land" },
                { pos = Vector(2647, -2775, 194), name = "Corner Hill B" },
            },
        },
        [GAMEMODE_KOTH] = {
            capMultiplier = 0.15,
            objectives = {
                { pos = Vector(0, 0, 3), name = "The Hill" },
            },
        },
        [GAMEMODE_DM] = {
            capMultiplier = 0,
            objectives = {},
        },
    },
    
    ["gm_baik_valley_split"] = {
        spawns = {
            [TEAM_GREEN] = Vector(-6285, -5632, 7),
            [TEAM_RED]   = Vector(6193, 723, 8),
        },
        limits = {
            weight = 80,
            props = 200,
            points = 4000,
        },
        safezoneRadius = 750,
        
        [GAMEMODE_CP] = {
            capMultiplier = 0.02,
            objectives = {
                { pos = Vector(6011, -5034, 3), name = "Red Camp" },
                { pos = Vector(0, -2559, 2), name = "The Center" },
                { pos = Vector(-5958, -95, 3), name = "Green Camp" },
            },
        },
        [GAMEMODE_KOTH] = {
            capMultiplier = 0.15,
            objectives = {
                { pos = Vector(0, -2559, 2), name = "The Hill" },
            },
        },
        [GAMEMODE_DM] = {
            capMultiplier = 0,
            objectives = {},
        },
    },
    
    ["gm_bigcity_improved"] = {
        spawns = {
            [TEAM_GREEN] = Vector(-10163, 11922, -11136),
            [TEAM_RED]   = Vector(11937, -7932, -11136),
        },
        limits = {
            weight = 120,
            props = 300,
            points = 5000,
        },
        safezoneRadius = 750,
        
        [GAMEMODE_CP] = {
            capMultiplier = 0.025,
            objectives = {
                { pos = Vector(-983, -949, -11140), name = "Park" },
                { pos = Vector(5060, 6094, -11144), name = "Sludge" },
            },
        },
        [GAMEMODE_KOTH] = {
            capMultiplier = 0.15,
            objectives = {
                { pos = Vector(-983, -949, -11140), name = "The Hill" },
            },
        },
        [GAMEMODE_DM] = {
            capMultiplier = 0,
            objectives = {},
        },
    },
    
    ["gm_diprip_refinery"] = {
        spawns = {
            [TEAM_GREEN] = Vector(-7754, 6833, 161),
            [TEAM_RED]   = Vector(4141, -5520, 320),
        },
        limits = {
            weight = 120,
            props = 300,
            points = 5000,
        },
        safezoneRadius = 750,
        
        [GAMEMODE_CP] = {
            capMultiplier = 0.02,
            objectives = {
                { pos = Vector(5874, 6349, 320), name = "Rail Tunnels" },
                { pos = Vector(128, 128, 480), name = "Shipping and Handling" },
                { pos = Vector(-5389, -5864, 320), name = "Dock Cranes" },
            },
        },
        [GAMEMODE_KOTH] = {
            capMultiplier = 0.15,
            objectives = {
                { pos = Vector(128, 128, 480), name = "The Hill" },
            },
        },
        [GAMEMODE_DM] = {
            capMultiplier = 0,
            objectives = {},
        },
    },
    
    ["gm_diprip_village"] = {
        spawns = {
            [TEAM_GREEN] = Vector(5974, 3971, 7),
            [TEAM_RED]   = Vector(-8421, -11827, 185),
        },
        limits = {
            weight = 60,
            props = 200,
            points = 3000,
        },
        safezoneRadius = 750,
        
        [GAMEMODE_CP] = {
            capMultiplier = 0.02,
            objectives = {
                { pos = Vector(-9910, -331, 32), name = "Sawmill" },
                { pos = Vector(-449, -3181, 48), name = "Coal Mine" },
                { pos = Vector(5456, -10558, -32), name = "Silos" },
            },
        },
        [GAMEMODE_KOTH] = {
            capMultiplier = 0.15,
            objectives = {
                { pos = Vector(-449, -3181, 48), name = "The Hill" },
            },
        },
        [GAMEMODE_DM] = {
            capMultiplier = 0,
            objectives = {},
        },
    },
    
    ["gm_emp_bush"] = {
        spawns = {
            [TEAM_GREEN] = Vector(-11392, -11104, -3333),
            [TEAM_RED]   = Vector(10060, 11788, -3327),
        },
        limits = {
            weight = 160,
            props = 300,
            points = 6000,
        },
        safezoneRadius = 750,
        
        [GAMEMODE_CP] = {
            capMultiplier = 0.02,
            objectives = {
                { pos = Vector(-10196, 9406, -3320), name = "Green Field" },
                { pos = Vector(72, -286, -3449), name = "Fort Center" },
                { pos = Vector(8196, -8603, -2994), name = "Corner Hill" },
            },
        },
        [GAMEMODE_KOTH] = {
            capMultiplier = 0.15,
            objectives = {
                { pos = Vector(72, -286, -3449), name = "The Hill" },
            },
        },
        [GAMEMODE_DM] = {
            capMultiplier = 0,
            objectives = {},
        },
    },
    
    ["gm_emp_commandergrad"] = {
        spawns = {
            [TEAM_GREEN] = Vector(3216, 12558, 9),
            [TEAM_RED]   = Vector(-7078, -13608, 9),
        },
        limits = {
            weight = 120,
            props = 250,
            points = 5000,
        },
        safezoneRadius = 750,
        
        [GAMEMODE_CP] = {
            capMultiplier = 0.02,
            objectives = {
                { pos = Vector(7137, 4178, 1094), name = "Mansion" },
                { pos = Vector(-1574, -714, 624), name = "City Center" },
                { pos = Vector(-10160, -4701, 1112), name = "Haunted House" },
            },
        },
        [GAMEMODE_KOTH] = {
            capMultiplier = 0.15,
            objectives = {
                { pos = Vector(-1574, -714, 624), name = "The Hill" },
            },
        },
        [GAMEMODE_DM] = {
            capMultiplier = 0,
            objectives = {},
        },
    },
    
    ["gm_freedom_city"] = {
        spawns = {
            [TEAM_GREEN] = Vector(-10769, 3232, 34),
            [TEAM_RED]   = Vector(6398, 1988, 464),
        },
        limits = {
            weight = 100,
            props = 300,
            points = 4500,
        },
        safezoneRadius = 750,
        
        [GAMEMODE_CP] = {
            capMultiplier = 0.02,
            objectives = {
                { pos = Vector(1943, -9289, 21), name = "Trainstop" },
                { pos = Vector(-9000, -3721, 33), name = "City Trainstop" },
                { pos = Vector(-2534, -434, 21), name = "The Crossroad" },
            },
        },
        [GAMEMODE_KOTH] = {
            capMultiplier = 0.15,
            objectives = {
                { pos = Vector(166, -4929, 33), name = "The Hill" },
            },
        },
        [GAMEMODE_DM] = {
            capMultiplier = 0,
            objectives = {},
        },
    },
    
    ["gm_greenland"] = {
        spawns = {
            [TEAM_GREEN] = Vector(-3461, -10270, 2),
            [TEAM_RED]   = Vector(3461, 10270, 2),
        },
        limits = {
            weight = 120,
            props = 300,
            points = 5000,
        },
        safezoneRadius = 750,
        
        [GAMEMODE_CP] = {
            capMultiplier = 0.02,
            objectives = {
                { pos = Vector(-3429, 8739, 183), name = "Oil Well" },
                { pos = Vector(78, 2053, 576), name = "Railroad Tracks" },
                { pos = Vector(3694, -5634, 192), name = "The Forest" },
            },
        },
        [GAMEMODE_KOTH] = {
            capMultiplier = 0.15,
            objectives = {
                { pos = Vector(78, 2053, 576), name = "The Hill" },
            },
        },
        [GAMEMODE_DM] = {
            capMultiplier = 0,
            objectives = {},
        },
    },
    
    ["gm_islandrain_v3"] = {
        spawns = {
            [TEAM_GREEN] = Vector(-3831, 10741, -1200),
            [TEAM_RED]   = Vector(8391, -9920, -1175),
        },
        limits = {
            weight = 80,
            props = 200,
            points = 4000,
        },
        safezoneRadius = 750,
        
        [GAMEMODE_CP] = {
            capMultiplier = 0.02,
            objectives = {
                { pos = Vector(-10637, -10705, -1161), name = "Beach" },
                { pos = Vector(6302, 4246, 1122), name = "The Mountain" },
                { pos = Vector(9443, 9233, -981), name = "Waterside Cliff" },
            },
        },
        [GAMEMODE_KOTH] = {
            capMultiplier = 0.15,
            objectives = {
                { pos = Vector(6302, 4246, 1122), name = "The Hill" },
            },
        },
        [GAMEMODE_DM] = {
            capMultiplier = 0,
            objectives = {},
        },
    },
    
    ["gm_pacific_island_a3"] = {
        spawns = {
            [TEAM_GREEN] = Vector(13995, 8546, -10539),
            [TEAM_RED]   = Vector(636, 13393, -10612),
        },
        limits = {
            weight = 60,
            props = 200,
            points = 3000,
        },
        safezoneRadius = 750,
        
        [GAMEMODE_CP] = {
            capMultiplier = 0.02,
            objectives = {
                { pos = Vector(5744, 7011, -10578), name = "Beachside Bunker" },
                { pos = Vector(8721, 11872, -9559), name = "The Tower" },
                { pos = Vector(13502, 11900, -10752), name = "End of the Line" },
            },
        },
        [GAMEMODE_KOTH] = {
            capMultiplier = 0.15,
            objectives = {
                { pos = Vector(8721, 11872, -9559), name = "The Hill" },
            },
        },
        [GAMEMODE_DM] = {
            capMultiplier = 0,
            objectives = {},
        },
    },
    
    ["gm_toysoldiers"] = {
        spawns = {
            [TEAM_GREEN] = Vector(-5186, 5086, -383),
            [TEAM_RED]   = Vector(5186, -5086, -383),
        },
        limits = {
            weight = 80,
            props = 300,
            points = 4000,
        },
        safezoneRadius = 750,
        
        [GAMEMODE_CP] = {
            capMultiplier = 0.02,
            objectives = {
                { pos = Vector(-5250, -5132, -440), name = "The Darkest Corner" },
                { pos = Vector(4908, 4919, -430), name = "The Lighter Side" },
                { pos = Vector(1787, 790, -430), name = "Confused Boat" },
            },
        },
        [GAMEMODE_KOTH] = {
            capMultiplier = 0.15,
            objectives = {
                { pos = Vector(1787, 790, -430), name = "The Hill" },
            },
        },
        [GAMEMODE_DM] = {
            capMultiplier = 0,
            objectives = {},
        },
    },
    
    ["gm_yanov"] = {
        spawns = {
            [TEAM_GREEN] = Vector(-4246, -4855, 65),
            [TEAM_RED]   = Vector(-3856, 1488, 65),
        },
        limits = {
            weight = 40,
            props = 150,
            points = 2000,
        },
        safezoneRadius = 750,
        
        [GAMEMODE_CP] = {
            capMultiplier = 0.02,
            objectives = {
                { pos = Vector(-1968, -1324, -74), name = "Extremely Confused Boat" },
                { pos = Vector(2609, -2517, 40), name = "Broken Car" },
                { pos = Vector(1728, 918, 64), name = "Garage" },
            },
        },
        [GAMEMODE_KOTH] = {
            capMultiplier = 0.15,
            objectives = {
                { pos = Vector(2173, -763, 72), name = "The Hill" },
            },
        },
        [GAMEMODE_DM] = {
            capMultiplier = 0,
            objectives = {},
        },
    },
}

-- Currently loaded map config
TPG.Maps.Current = nil

-- Load map configuration
function TPG.Maps.Load(mapName)
    mapName = mapName or game.GetMap()
    
    -- Check if we have an inline config for this map
    if TPG.Maps.Configs[mapName] then
        TPG.Maps.Current = table.Merge(table.Copy(TPG.Maps.Default), TPG.Maps.Configs[mapName])
        
        -- Debug: verify limits loaded correctly
        local limits = TPG.Maps.Current.limits
        print("[TPG] Loaded map config: " .. mapName)
        print("[TPG] Limits - Props: " .. limits.props .. ", Weight: " .. limits.weight .. "T, Points: " .. limits.points)
        
        return TPG.Maps.Current
    end
    
    -- Fall back to defaults
    print("[TPG] No config for " .. mapName .. ", using defaults")
    TPG.Maps.Current = table.Copy(TPG.Maps.Default)
    return TPG.Maps.Current
end

-- Get current map config (load if not loaded)
function TPG.Maps.Get()
    if not TPG.Maps.Current then
        TPG.Maps.Load()
    end
    return TPG.Maps.Current
end

-- Get spawn position for team
function TPG.Maps.GetSpawn(teamId)
    local config = TPG.Maps.Get()
    return config.spawns[teamId] or Vector(0, 0, 0)
end

-- Get objectives for current gametype
function TPG.Maps.GetObjectives(gameType)
    local config = TPG.Maps.Get()
    local gtConfig = config[gameType]
    
    if gtConfig and gtConfig.objectives then
        return gtConfig.objectives
    end
    
    return {}
end

-- Get limits (weight, props, points)
function TPG.Maps.GetLimits()
    local config = TPG.Maps.Get()
    return config.limits
end