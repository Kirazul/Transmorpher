local addon, ns = ...

-- WoW 3.3.5a Mount Database
-- Format: { name, spellID, displayID, "model\\path.m2" }
-- Sources: Spell.dbc, CreatureDisplayInfo.dbc, CreatureModelData.dbc
-- displayID = CreatureDisplayInfo ID used by UNIT_FIELD_MOUNTDISPLAYID
-- modelPath = M2 model file for 3D preview

ns.mountsDB = {
    ---------------------------------------------------------------------------
    -- HORSES (Alliance)
    ---------------------------------------------------------------------------
    { "Brown Horse",                    458,    2404,   "Creature\\Horse\\Horse.m2" },
    { "Black Stallion",                 470,    2402,   "Creature\\Horse\\Horse.m2" },
    { "Chestnut Mare",                  6648,   2405,   "Creature\\Horse\\Horse.m2" },
    { "Pinto",                          472,    2409,   "Creature\\Horse\\Horse.m2" },
    { "Palomino",                       6649,   2408,   "Creature\\Horse\\Horse.m2" },
    { "White Stallion",                 6650,   2410,   "Creature\\Horse\\Horse.m2" },
    { "Swift Brown Steed", 23229, 14583, "Creature\\Horse\\Horse.m2" },
    { "Swift Palomino", 23227, 14583, "Creature\\Horse\\Horse.m2" },
    { "Swift White Steed", 23228, 14338, "Creature\\Horse\\Horse.m2" },

    ---------------------------------------------------------------------------
    -- RAMS (Dwarf)
    ---------------------------------------------------------------------------
    { "Brown Ram", 6899, 2785, "Creature\\Ram\\Ram.m2" },
    { "Gray Ram", 6777, 2736, "Creature\\Ram\\Ram.m2" },
    { "White Ram",                      6898,   2786,   "Creature\\Ram\\Ram.m2" },
    { "Swift Brown Ram",                23238,  14347,  "Creature\\Ram\\Ram.m2" },
    { "Swift Gray Ram", 23239, 14576, "Creature\\Ram\\Ram.m2" },
    { "Swift White Ram",                23240,  14346,  "Creature\\Ram\\Ram.m2" },
    { "Brewfest Ram",                   43899,  22265,  "Creature\\Ram\\Ram.m2" },
    { "Swift Brewfest Ram",             43900,  22350,  "Creature\\Ram\\Ram.m2" },

    ---------------------------------------------------------------------------
    -- MECHANOSTRIDERS (Gnome)
    ---------------------------------------------------------------------------
    { "Blue Mechanostrider",            10969,  6569,   "Creature\\Mechanostrider\\Mechanostrider.m2" },
    { "Green Mechanostrider", 17453, 10661, "Creature\\Mechanostrider\\Mechanostrider.m2" },
    { "Red Mechanostrider", 10873, 9473, "Creature\\Mechanostrider\\Mechanostrider.m2" },
    { "Unpainted Mechanostrider",       17454,  9475,   "Creature\\Mechanostrider\\Mechanostrider.m2" },
    { "Swift Green Mechanostrider", 23225, 14374, "Creature\\Mechanostrider\\Mechanostrider.m2" },
    { "Swift White Mechanostrider",     23223,  14376,  "Creature\\Mechanostrider\\Mechanostrider.m2" },
    { "Swift Yellow Mechanostrider",    23222,  14377,  "Creature\\Mechanostrider\\Mechanostrider.m2" },

    ---------------------------------------------------------------------------
    -- SABERS (Night Elf)
    ---------------------------------------------------------------------------
    { "Spotted Frostsaber",             8394,   6448,   "Creature\\NightElfMount\\NightElfMount.m2" },
    { "Striped Frostsaber",             8395,   6444,   "Creature\\NightElfMount\\NightElfMount.m2" },
    { "Striped Nightsaber",             10793,  6443,   "Creature\\NightElfMount\\NightElfMount.m2" },
    { "Reins of the Ancient Frostsaber", 12302, 6444,   "Creature\\NightElfMount\\NightElfMount.m2" },
    { "Reins of the Nightsaber",        12303,  6443,   "Creature\\NightElfMount\\NightElfMount.m2" },
    { "Swift Frostsaber", 23221, 14331, "Creature\\NightElfMount\\NightElfMount.m2" },
    { "Swift Mistsaber",                23219,  14332,  "Creature\\NightElfMount\\NightElfMount.m2" },
    { "Swift Stormsaber",               23338,  14632,  "Creature\\NightElfMount\\NightElfMount.m2" },

    ---------------------------------------------------------------------------
    -- ELEKKS (Draenei)
    ---------------------------------------------------------------------------
    { "Brown Elekk", 34406, 17063, "Creature\\Elekk\\Elekk.m2" },
    { "Gray Elekk", 35710, 19869, "Creature\\Elekk\\Elekk.m2" },
    { "Purple Elekk", 35711, 19870, "Creature\\Elekk\\Elekk.m2" },
    { "Great Blue Elekk",               35713,  19871,  "Creature\\Elekk\\Elekk.m2" },
    { "Great Green Elekk", 35712, 19873, "Creature\\Elekk\\Elekk.m2" },
    { "Great Purple Elekk",             35714,  19870,  "Creature\\Elekk\\Elekk.m2" },  -- Fixed: was 19902 (Infernal Animus)

    ---------------------------------------------------------------------------
    -- WOLVES (Orc)
    ---------------------------------------------------------------------------
    { "Timber Wolf",                    580,    247,    "Creature\\Wolf\\Wolf.m2" },
    { "Dire Wolf", 6653, 17283, "Creature\\Wolf\\Wolf.m2" },
    { "Brown Wolf",                     6654,   2328,   "Creature\\Wolf\\Wolf.m2" },
    { "Red Wolf",                       16080,  2326,   "Creature\\Wolf\\Wolf.m2" },
    { "Arctic Wolf",                    16081,  1166,   "Creature\\Wolf\\Wolf.m2" },
    { "Swift Brown Wolf",               23250,  14573,  "Creature\\Wolf\\Wolf.m2" },
    { "Swift Gray Wolf",                23252,  14574,  "Creature\\Wolf\\Wolf.m2" },
    { "Swift Timber Wolf",              23251,  14575,  "Creature\\Wolf\\Wolf.m2" },

    ---------------------------------------------------------------------------
    -- RAPTORS (Troll)
    ---------------------------------------------------------------------------
    { "Emerald Raptor",                 8395,   4806,   "Creature\\Raptor\\Raptor.m2" },
    { "Turquoise Raptor",               10796,  6472,   "Creature\\Raptor\\Raptor.m2" },
    { "Violet Raptor",                  10799,  6473,   "Creature\\Raptor\\Raptor.m2" },
    { "Swift Blue Raptor",              23241,  14339,  "Creature\\Raptor\\Raptor.m2" },
    { "Swift Olive Raptor",             23242,  14344,  "Creature\\Raptor\\Raptor.m2" },
    { "Swift Orange Raptor",            23243,  14342,  "Creature\\Raptor\\Raptor.m2" },

    ---------------------------------------------------------------------------
    -- KODOS (Tauren)
    ---------------------------------------------------------------------------
    { "Brown Kodo",                     18990,  11641,  "Creature\\Kodo\\Kodo.m2" },
    { "Gray Kodo",                      18989,  11642,  "Creature\\Kodo\\Kodo.m2" },
    { "White Kodo",                     64657,  14349,  "Creature\\Kodo\\Kodo.m2" },  -- Fixed: was 12246 (Gray Riding Kodo)
    { "Great Brown Kodo",               23249,  14578,  "Creature\\Kodo\\Kodo.m2" },
    { "Great Gray Kodo",                23248,  14579,  "Creature\\Kodo\\Kodo.m2" },
    { "Great White Kodo",               23247,  14349,  "Creature\\Kodo\\Kodo.m2" },
    { "Green Kodo", 18991, 12245, "Creature\\Kodo\\Kodo.m2" },

    ---------------------------------------------------------------------------
    -- UNDEAD HORSES (Undead)
    ---------------------------------------------------------------------------
    { "Black Skeletal Horse", 64977, 5228, "Creature\\SkeletalHorse\\SkeletalHorse.m2" },
    { "Blue Skeletal Horse", 17463, 10671, "Creature\\SkeletalHorse\\SkeletalHorse.m2" },
    { "Brown Skeletal Horse",           17464,  10672,  "Creature\\SkeletalHorse\\SkeletalHorse.m2" },
    { "Red Skeletal Horse", 17462, 10670, "Creature\\SkeletalHorse\\SkeletalHorse.m2" },
    { "Green Skeletal Warhorse",        17465,  10720,  "Creature\\SkeletalHorse\\SkeletalHorse.m2" },  -- Fixed: was 14566 (Gorzeeki Wildeyes)
    { "Purple Skeletal Warhorse", 23246, 10721, "Creature\\SkeletalHorse\\SkeletalHorse.m2" },
    { "Ochre Skeletal Warhorse", 66846, 29754, "Creature\\SkeletalHorse\\SkeletalHorse.m2" },

    ---------------------------------------------------------------------------
    -- HAWKSTRIDERS (Blood Elf)
    ---------------------------------------------------------------------------
    { "Black Hawkstrider", 35022, 19478, "Creature\\Hawkstrider\\Hawkstrider.m2" },
    { "Blue Hawkstrider", 35020, 19480, "Creature\\Hawkstrider\\Hawkstrider.m2" },
    { "Purple Hawkstrider", 35018, 19479, "Creature\\Hawkstrider\\Hawkstrider.m2" },
    { "Red Hawkstrider", 34795, 18696, "Creature\\Hawkstrider\\Hawkstrider.m2" },
    { "Swift Green Hawkstrider", 35025, 19484, "Creature\\Hawkstrider\\Hawkstrider.m2" },
    { "Swift Purple Hawkstrider", 35027, 19482, "Creature\\Hawkstrider\\Hawkstrider.m2" },
    { "Swift Pink Hawkstrider",         33660,  18697,  "Creature\\Hawkstrider\\Hawkstrider.m2" },
    { "Swift White Hawkstrider", 46628, 19483, "Creature\\Hawkstrider\\Hawkstrider.m2" },

    ---------------------------------------------------------------------------
    -- PVP MOUNTS
    ---------------------------------------------------------------------------
    { "Black War Steed",                22717,  14337,  "Creature\\Horse\\Horse.m2" },
    { "Black War Ram",                  22720,  14577,  "Creature\\Ram\\Ram.m2" },
    { "Black War Tiger",                22723,  14330,  "Creature\\NightElfMount\\NightElfMount.m2" },
    { "Black War Mechanostrider",       22719,  14377,  "Creature\\Mechanostrider\\Mechanostrider.m2" },
    { "Black War Elekk", 48027, 23928, "Creature\\Elekk\\Elekk.m2" },
    { "Black War Wolf",                 22724,  14575,  "Creature\\Wolf\\Wolf.m2" },
    { "Black War Raptor", 22721, 14388, "Creature\\Raptor\\Raptor.m2" },
    { "Black War Kodo", 22718, 14348, "Creature\\Kodo\\Kodo.m2" },
    { "Red Skeletal Warhorse",          22722,  10719,  "Creature\\SkeletalHorse\\SkeletalHorse.m2" },
    { "Black War Hawkstrider",          66091,  19478,  "Creature\\Hawkstrider\\Hawkstrider.m2" },  -- Fixed: was 29220 (invalid)

    ---------------------------------------------------------------------------
    -- PALADIN / WARLOCK CLASS MOUNTS
    ---------------------------------------------------------------------------
    { "Warhorse (Paladin)",             13819,  28918,  "Creature\\Horse\\Horse.m2" },  -- Fixed: was 9991 (Jaelyne Evensong's Mount)
    { "Charger (Paladin)",              23214,  14584,  "Creature\\Horse\\Horse.m2" },
    { "Thalassian Warhorse",            34767,  19085,  "Creature\\Horse\\Horse.m2" },
    { "Thalassian Charger", 34769, 19085, "Creature\\Horse\\Horse.m2" },
    { "Felsteed (Warlock)",             5784,   2346,   "Creature\\NightmareHorse\\NightmareHorse.m2" },
    { "Dreadsteed (Warlock)",           23161,  14554,  "Creature\\NightmareHorse\\NightmareHorse.m2" },

    ---------------------------------------------------------------------------
    -- DEATH KNIGHT
    ---------------------------------------------------------------------------
    { "Acherus Deathcharger",           48778,  25280,  "Creature\\SkeletalHorse\\SkeletalHorse.m2" },
    { "Winged Steed of the Ebon Blade", 54729,  28108,  "Creature\\SkeletalHorse\\SkeletalHorse.m2" },

    ---------------------------------------------------------------------------
    -- SPECIAL / RARE GROUND MOUNTS
    ---------------------------------------------------------------------------
    { "Deathcharger's Reins",           17481,  10718,  "Creature\\SkeletalHorse\\SkeletalHorse.m2" },
    { "Fiery Warhorse",                 36702,  19250,  "Creature\\NightmareHorse\\NightmareHorse.m2" },
    { "Swift Razzashi Raptor", 24242, 15289, "Creature\\Raptor\\Raptor.m2" },
    { "Swift Zulian Tiger",             24252,  15290,  "Creature\\NightElfMount\\NightElfMount.m2" },
    { "Amani War Bear", 43688, 22464, "Creature\\Bear2\\Bear2.m2" },
    { "Black War Bear (Alliance)", 60118, 27818, "Creature\\Bear2\\Bear2.m2" },
    { "Black War Bear (Horde)", 60119, 27818, "Creature\\Bear2\\Bear2.m2" },
    { "White Polar Bear",               54753,  28428,  "Creature\\Bear2\\Bear2.m2" },
    { "Big Battle Bear", 51412, 25335, "Creature\\Bear2\\Bear2.m2" },
    { "Winterspring Frostsaber",        17229,  10426,  "Creature\\NightElfMount\\NightElfMount.m2" },
    { "Venomhide Ravasaur",             64659,  29102,  "Creature\\Raptor\\Raptor.m2" },  -- Fixed: was 5291 (wrong model)
    { "Black Qiraji Battle Tank", 26656, 15676, "Creature\\QirajiMount\\QirajiMount.m2" },
    { "Blue Qiraji Battle Tank", 25953, 15672, "Creature\\QirajiMount\\QirajiMount.m2" },
    { "Green Qiraji Battle Tank", 26056, 15679, "Creature\\QirajiMount\\QirajiMount.m2" },
    { "Red Qiraji Battle Tank", 26054, 15681, "Creature\\QirajiMount\\QirajiMount.m2" },
    { "Yellow Qiraji Battle Tank", 26055, 15680, "Creature\\QirajiMount\\QirajiMount.m2" },
    { "Sea Turtle",                     64731,  29161,  "Creature\\Turtle\\Turtle.m2" },
    { "White War Talbuk", 34896, 19377, "Creature\\Talbuk\\Talbuk.m2" },
    { "Cobalt War Talbuk", 34899, 19375, "Creature\\Talbuk\\Talbuk.m2" },
    { "Silver War Talbuk", 34898, 19378, "Creature\\Talbuk\\Talbuk.m2" },
    { "Tan War Talbuk", 34897, 19376, "Creature\\Talbuk\\Talbuk.m2" },
    { "Dark War Talbuk", 34790, 19303, "Creature\\Talbuk\\Talbuk.m2" },
    { "Cobalt Riding Talbuk",           39315,  21073,  "Creature\\Talbuk\\Talbuk.m2" },
    { "Silver Riding Talbuk", 39316, 21075, "Creature\\Talbuk\\Talbuk.m2" },
    { "Tan Riding Talbuk", 39317, 21077, "Creature\\Talbuk\\Talbuk.m2" },
    { "White Riding Talbuk", 39318, 21076, "Creature\\Talbuk\\Talbuk.m2" },
    { "Dark Riding Talbuk",             39319,  21074,  "Creature\\Talbuk\\Talbuk.m2" },
    { "Traveler's Tundra Mammoth (A)", 61425, 27237, "Creature\\Mammoth\\Mammoth.m2" },
    { "Traveler's Tundra Mammoth (H)", 61447, 27237, "Creature\\Mammoth\\Mammoth.m2" },
    { "Grand Ice Mammoth (A)", 61470, 27239, "Creature\\Mammoth\\Mammoth.m2" },
    { "Grand Ice Mammoth (H)", 61469, 27239, "Creature\\Mammoth\\Mammoth.m2" },
    { "Grand Black War Mammoth (A)", 61465, 27240, "Creature\\Mammoth\\Mammoth.m2" },
    { "Grand Black War Mammoth (H)", 61467, 27240, "Creature\\Mammoth\\Mammoth.m2" },
    { "Wooly Mammoth (A)", 59793, 27243, "Creature\\Mammoth\\Mammoth.m2" },
    { "Wooly Mammoth (H)", 59793, 27243, "Creature\\Mammoth\\Mammoth.m2" },
    { "Black Mammoth", 59788, 26510, "Creature\\Mammoth\\Mammoth.m2" },
    { "Ice Mammoth",                    59797,  27246,  "Creature\\Mammoth\\Mammoth.m2" },
    { "Mechano-Hog",                    55531,  25871,  "Creature\\GoblinTrike\\GoblinTrike.m2" },
    { "Mekgineer's Chopper",            60424,  25870,  "Creature\\GoblinTrike\\GoblinTrike.m2" },

    ---------------------------------------------------------------------------
    -- FLYING MOUNTS — GRYPHONS
    ---------------------------------------------------------------------------
    { "Ebon Gryphon",                   32239,  17694,  "Creature\\Gryphon\\Gryphon.m2" },
    { "Golden Gryphon",                 32235,  17697,  "Creature\\Gryphon\\Gryphon.m2" },
    { "Snowy Gryphon", 32240, 17696, "Creature\\Gryphon\\Gryphon.m2" },
    { "Swift Blue Gryphon",             32242,  17759,  "Creature\\Gryphon\\Gryphon.m2" },  -- Fixed: was 17700 (Blue Wind Rider)
    { "Swift Green Gryphon",            32290,  17703,  "Creature\\Gryphon\\Gryphon.m2" },  -- Fixed: was 17701 (Old Crappy McWeaksauce)
    { "Swift Purple Gryphon",           32292,  17703,  "Creature\\Gryphon\\Gryphon.m2" },
    { "Swift Red Gryphon",              32289,  17717,  "Creature\\Gryphon\\Gryphon.m2" },  -- Fixed: was 17702 (UNUSED Outland Wyvern Mount), using Swift Purple as placeholder

    ---------------------------------------------------------------------------
    -- FLYING MOUNTS — WIND RIDERS
    ---------------------------------------------------------------------------
    { "Tawny Wind Rider",               32243,  17719,  "Creature\\Wyvern\\Wyvern.m2" },  -- Fixed: was 17704 (Spawn of Dimensius)
    { "Blue Wind Rider", 32244, 17700, "Creature\\Wyvern\\Wyvern.m2" },
    { "Green Wind Rider",               32245,  17720,  "Creature\\Wyvern\\Wyvern.m2" },  -- Fixed: was 17711 (Royal Blue Flutterer)
    { "Swift Green Wind Rider",         32295,  17720,  "Creature\\Wyvern\\Wyvern.m2" },
    { "Swift Purple Wind Rider", 32297, 17721, "Creature\\Wyvern\\Wyvern.m2" },
    { "Swift Red Wind Rider",           32246,  17719,  "Creature\\Wyvern\\Wyvern.m2" },
    { "Swift Yellow Wind Rider",        32296,  17721,  "Creature\\Wyvern\\Wyvern.m2" },

    ---------------------------------------------------------------------------
    -- FLYING MOUNTS — NETHERDRAKES
    ---------------------------------------------------------------------------
    { "Azure Netherwing Drake",          41514,  21521,  "Creature\\NetherwingDrake\\NetherwingDrake.m2" },
    { "Cobalt Netherwing Drake",         41515,  21525,  "Creature\\NetherwingDrake\\NetherwingDrake.m2" },
    { "Onyx Netherwing Drake",           41513,  21520,  "Creature\\NetherwingDrake\\NetherwingDrake.m2" },
    { "Purple Netherwing Drake",         41516,  21523,  "Creature\\NetherwingDrake\\NetherwingDrake.m2" },
    { "Veridian Netherwing Drake",       41517,  21522,  "Creature\\NetherwingDrake\\NetherwingDrake.m2" },
    { "Violet Netherwing Drake",         41518,  21524,  "Creature\\NetherwingDrake\\NetherwingDrake.m2" },

    ---------------------------------------------------------------------------
    -- FLYING MOUNTS — NETHER RAYS
    ---------------------------------------------------------------------------
    { "Blue Riding Nether Ray",          39803,  21156,  "Creature\\NetherRay\\NetherRay.m2" },
    { "Green Riding Nether Ray",         39798,  21152,  "Creature\\NetherRay\\NetherRay.m2" },
    { "Purple Riding Nether Ray",        39801,  21155,  "Creature\\NetherRay\\NetherRay.m2" },
    { "Red Riding Nether Ray",           39800,  21158,  "Creature\\NetherRay\\NetherRay.m2" },
    { "Silver Riding Nether Ray",        39802,  21157,  "Creature\\NetherRay\\NetherRay.m2" },

    ---------------------------------------------------------------------------
    -- FLYING MOUNTS — PROTO-DRAKES
    ---------------------------------------------------------------------------
    { "Blue Proto-Drake",                59996,  28041,  "Creature\\ProtoDrake\\ProtoDrake.m2" },
    { "Green Proto-Drake",               61294,  28053,  "Creature\\ProtoDrake\\ProtoDrake.m2" },
    { "Red Proto-Drake",                 59961,  28044,  "Creature\\ProtoDrake\\ProtoDrake.m2" },
    { "Time-Lost Proto-Drake",           60002,  28045,  "Creature\\ProtoDrake\\ProtoDrake.m2" },
    { "Violet Proto-Drake",              60024,  28043,  "Creature\\ProtoDrake\\ProtoDrake.m2" },
    { "Plagued Proto-Drake",             60021,  28042,  "Creature\\ProtoDrake\\ProtoDrake.m2" },
    { "Black Proto-Drake",               59976,  28040,  "Creature\\ProtoDrake\\ProtoDrake.m2" },
    { "Ironbound Proto-Drake", 63956, 28953, "Creature\\ProtoDrake\\ProtoDrake.m2" },
    { "Rusted Proto-Drake", 63963, 28954, "Creature\\ProtoDrake\\ProtoDrake.m2" },

    ---------------------------------------------------------------------------
    -- FLYING MOUNTS — DRAKES
    ---------------------------------------------------------------------------
    { "Albino Drake", 60025, 25836, "Creature\\Drake\\Drake.m2" },
    { "Black Drake", 59650, 25831, "Creature\\Drake\\Drake.m2" },
    { "Blue Drake",                      59568,  25832,  "Creature\\Drake\\Drake.m2" },
    { "Bronze Drake", 59569, 25852, "Creature\\Drake\\Drake.m2" },
    { "Red Drake", 59570, 25854, "Creature\\Drake\\Drake.m2" },
    { "Twilight Drake",                  59571,  27796,  "Creature\\Drake\\Drake.m2" },

    ---------------------------------------------------------------------------
    -- FLYING MOUNTS — ULDUAR / ICC / TOURNAMENT
    ---------------------------------------------------------------------------
    { "Mimiron's Head",                  63796,  28890,  "Creature\\MimironsHead\\MimironsHead.m2" },
    { "Invincible",                      72286,  31007,  "Creature\\SkeletalHorse\\SkeletalHorse.m2" },
    { "Ashes of Al'ar",                  40192,  17890,  "Creature\\Phoenix\\Phoenix.m2" },
    { "Swift Nether Drake",              37015,  20344,  "Creature\\NetherwingDrake\\NetherwingDrake.m2" },
    { "Merciless Nether Drake",          44744,  22620,  "Creature\\NetherwingDrake\\NetherwingDrake.m2" },
    { "Vengeful Nether Drake",           49193,  24725,  "Creature\\NetherwingDrake\\NetherwingDrake.m2" },
    { "Brutal Nether Drake",             58615,  27507,  "Creature\\NetherwingDrake\\NetherwingDrake.m2" },
    { "Deadly Gladiator's Frostw. Drake",64927, 25511,  "Creature\\FrostWyrm\\FrostWyrm.m2" },  -- Fixed: was 29130 (Black Skeletal Horse)
    { "Furious Gladiator's Frostw. Drake",65439,25593,  "Creature\\FrostWyrm\\FrostWyrm.m2" },  -- Fixed: was 29404 (Macabre Marionette)
    { "Relentless Gladiator's Frostw. Drake",67336,29794,"Creature\\FrostWyrm\\FrostWyrm.m2" },  -- Fixed: was 29682 (Firehawk Mariner Male Dead)
    { "Wrathful Gladiator's Frostw. Drake",71810,31047,  "Creature\\FrostWyrm\\FrostWyrm.m2" },
    { "Black Frostwyrm (ICC 10)",        72807,  31154,  "Creature\\FrostWyrm\\FrostWyrm.m2" },

    ---------------------------------------------------------------------------
    -- FLYING MOUNTS — SPECIAL / STORE
    ---------------------------------------------------------------------------
    { "Magnificent Flying Carpet",       61309,  28060,  "Creature\\FlyingCarpet\\FlyingCarpet.m2" },
    { "Flying Carpet",                   61451,  28082,  "Creature\\FlyingCarpet\\FlyingCarpet.m2" },  -- Fixed: was 27837 (invalid), using Amazing Flying Carpet
    { "Frosty Flying Carpet",            75596,  28061,  "Creature\\FlyingCarpet\\FlyingCarpet.m2" },  -- Fixed: was 31837 (Tiny Mooncloth Carpet), using Swift Shadoweave Carpet
    { "Celestial Steed", 75614, 31957, "Creature\\EtherealMount\\EtherealMount.m2" },
    { "X-53 Touring Rocket",             75973,  31992,  "Creature\\RocketMount\\RocketMount.m2" },

    ---------------------------------------------------------------------------
    -- FLYING MOUNTS — HIPPOGRYPHS / MISC
    ---------------------------------------------------------------------------
    { "Silver Covenant Hippogryph",      66087,  22472,  "Creature\\Hippogryph\\Hippogryph.m2" },  -- Fixed: was 29198 (invalid), using Blue Riding Hippogryph
    { "Cenarion War Hippogryph",         43927,  22473,  "Creature\\Hippogryph\\Hippogryph.m2" },
    { "Argent Hippogryph",               63844,  29627,  "Creature\\Hippogryph\\Hippogryph.m2" },  -- Fixed: was 28889 (Stabled Sunreaver Hawkstrider)

    ---------------------------------------------------------------------------
    -- TOURNAMENT MOUNTS (Argent Tournament)
    ---------------------------------------------------------------------------
    { "Argent Warhorse",                 67466,  28918,  "Creature\\Horse\\Horse.m2" },
    { "Argent Charger",                  66906,  28919,  "Creature\\Horse\\Horse.m2" },
    { "Sunreaver Hawkstrider",           66091,  28889,  "Creature\\Hawkstrider\\Hawkstrider.m2" },  -- Fixed: was 26877 (Sunreaver Hawkrider), using Stabled version
    { "Quel'dorei Steed",               66090,  28888,  "Creature\\Horse\\Horse.m2" },  -- Fixed: was 29231 (Cheerful Night Elf Spirit)
    { "Swift Horde Wolf", 68056, 30070, "Creature\\Wolf\\Wolf.m2" },
    { "Swift Alliance Steed", 68057, 29284, "Creature\\Horse\\Horse.m2" },
    { "Darnassian Nightsaber",           63637,  29256,  "Creature\\NightElfMount\\NightElfMount.m2" },
    { "Exodar Elekk",                    63639,  29257,  "Creature\\Elekk\\Elekk.m2" },
    { "Gnomeregan Mechanostrider",       63638,  28571,  "Creature\\Mechanostrider\\Mechanostrider.m2" },
    { "Ironforge Ram",                   63636,  29258,  "Creature\\Ram\\Ram.m2" },
    { "Stormwind Steed",                 63232,  28912,  "Creature\\Horse\\Horse.m2" },
    { "Darkspear Raptor",                63635,  29261,  "Creature\\Raptor\\Raptor.m2" },
    { "Orgrimmar Wolf",                  63640,  29260,  "Creature\\Wolf\\Wolf.m2" },
    { "Silvermoon Hawkstrider",          63642,  29262,  "Creature\\Hawkstrider\\Hawkstrider.m2" },
    { "Thunder Bluff Kodo",              63641,  29259,  "Creature\\Kodo\\Kodo.m2" },
    { "Forsaken Warhorse",               63643,  29257,  "Creature\\SkeletalHorse\\SkeletalHorse.m2" },  -- Fixed: was 29263 (invalid)
    { "Sen'jin Fetish (Raptor)",         63635,  29261,  "Creature\\Raptor\\Raptor.m2" },

    ---------------------------------------------------------------------------
    -- WINTERGRASP / DALARAN
    ---------------------------------------------------------------------------
    { "Black War Mammoth (A)", 59785, 27245, "Creature\\Mammoth\\Mammoth.m2" },
    { "Black War Mammoth (H)", 59788, 27245, "Creature\\Mammoth\\Mammoth.m2" },

    ---------------------------------------------------------------------------
    -- MISCELLANEOUS / RARE
    ---------------------------------------------------------------------------
    { "Headless Horseman's Mount",       48025,  22653,  "Creature\\FlyingHorse\\FlyingHorse.m2" },
    { "Magic Rooster",                   65917,  29344,  "Creature\\Rooster\\Rooster.m2" },
    { "Big Blizzard Bear", 58983, 27567, "Creature\\Bear2\\Bear2.m2" },
    { "Riding Turtle",                  30174,  17158,  "Creature\\Turtle\\Turtle.m2" },
    { "Spectral Tiger",                 42776,  21973,  "Creature\\SpectralTiger\\SpectralTiger.m2" },
    { "Swift Spectral Tiger",           49322,  21974,  "Creature\\SpectralTiger\\SpectralTiger.m2" },
    { "White Kodo (BrewFest)",          49379,  14349,  "Creature\\Kodo\\Kodo.m2" },
    { "Great Brewfest Kodo", 49379, 24757, "Creature\\Kodo\\Kodo.m2" },
    { "Swift Zhevra",                    49322,  24693,  "Creature\\Zhevra\\Zhevra.m2" },
}
