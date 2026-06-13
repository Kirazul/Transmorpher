local addon, ns = ...

-- WoW 3.3.5a Companion Pet (Critter) Database
-- Format: { name, spellID, displayID, "model\\path.m2" }
-- displayID = CreatureDisplayInfo ID used to overwrite the critter's UNIT_FIELD_DISPLAYID
-- modelPath = M2 model file for 3D preview

ns.petsDB = {
    ---------------------------------------------------------------------------
    -- CATS
    ---------------------------------------------------------------------------
    { "Black Tabby Cat",            10675,  5554,   "Creature\\Cat\\Cat.m2" },  -- Fixed: was 6368 (turtle)
    { "Bombay Cat", 10673, 5556, "Creature\\Cat\\Cat.m2" },
    { "Calico Cat", 65358, 11709, "Creature\\Cat\\Cat.m2" },
    { "Cornish Rex Cat",            10676,  5586,   "Creature\\Cat\\Cat.m2" },
    { "Orange Tabby Cat", 10680, 5554, "Creature\\Cat\\Cat.m2" },
    { "Siamese Cat",                10677,  5554,   "Creature\\Cat\\Cat.m2" },  -- Fixed: was 7380 (Boom Bot)
    { "Silver Tabby Cat", 10678, 5555, "Creature\\Cat\\Cat.m2" },
    { "White Kitten", 10679, 9989, "Creature\\Cat\\Cat.m2" },

    ---------------------------------------------------------------------------
    -- SNAKES
    ---------------------------------------------------------------------------
    { "Black Kingsnake",            10714,  1206,   "Creature\\Snake\\Snake.m2" },  -- Fixed: was 6200 (invalid)
    { "Brown Snake",                10716,  2957,   "Creature\\Snake\\Snake.m2" },  -- Fixed: was 6202 (invalid)
    { "Crimson Snake",              10717,  6303,   "Creature\\Snake\\Snake.m2" },  -- Fixed: was 6201 (invalid)
    { "Albino Snake",               10713,  2955,   "Creature\\Snake\\Snake.m2" },  -- Fixed: was 7556 (invalid)

    ---------------------------------------------------------------------------
    -- BIRDS / OWLS / PARROTS
    ---------------------------------------------------------------------------
    { "Cockatiel", 10683, 6191, "Creature\\Parrot\\Parrot.m2" },
    { "Green Wing Macaw",           10684,  8816,   "Creature\\Parrot\\Parrot.m2" },  -- Fixed: was 7387 (invalid)
    { "Hyacinth Macaw", 10682, 6192, "Creature\\Parrot\\Parrot.m2" },
    { "Senegal", 10684, 6190, "Creature\\Parrot\\Parrot.m2" },
    { "Hawk Owl",                   10706,  6300,   "Creature\\Owl\\Owl.m2" },  -- Fixed: was 7555 (Atal'ai Skeleton)
    { "Great Horned Owl",           10707,  10832,  "Creature\\Owl\\Owl.m2" },  -- Fixed: was 7553 (Dreamtracker)
    { "Westfall Chicken",           10685,  304,    "Creature\\Chicken\\Chicken.m2" },  -- OK: White Plymouth Rock
    { "Ancona Chicken",             10685,  304,    "Creature\\Chicken\\Chicken.m2" },  -- Fixed: was 2512 (Scarlet Magician)
    { "Plucky Johnson",             12243,  5369,   "Creature\\Chicken\\Chicken.m2" },  -- Fixed: was 303 (invalid)

    ---------------------------------------------------------------------------
    -- RABBITS / RODENTS
    ---------------------------------------------------------------------------
    { "Snowshoe Rabbit",            10711,  6302,   "Creature\\Rabbit\\Rabbit.m2" },  -- Fixed: was 328 (wrong)
    { "Spring Rabbit",              61725,  23922,  "Creature\\Rabbit\\Rabbit.m2" },  -- Fixed: was 28905 (Brollen Wheatbeard)
    { "Brown Prairie Dog",          10709,  1072,   "Creature\\PrairieDog\\PrairieDog.m2" },  -- Fixed: was 1155 (invalid)
    { "Black Prairie Dog",          10709,  1072,   "Creature\\PrairieDog\\PrairieDog.m2" },  -- Fixed: was 1155 (invalid)
    { "Squirrel",	10709,	4466,    "Creature\\Squirrel\\Squirrel.m2" },
    { "Rat",                        10709,  2176,   "Creature\\Rat\\Rat.m2" },
    { "Undercity Cockroach",        10688,  3233,   "Creature\\Cockroach\\Cockroach.m2" },  -- Fixed: was 6534 (invalid)

    ---------------------------------------------------------------------------
    -- FROGS / TOADS / CRITTERS
    ---------------------------------------------------------------------------
    { "Tree Frog",                  10695,  6295,   "Creature\\Frog\\Frog.m2" },  -- Fixed: was 865 (Shardtooth Bear)
    { "Wood Frog",                  10696,  6297,   "Creature\\Frog\\Frog.m2" },  -- Fixed: was 864 (Living Grove Defender)
    { "Mojo", 43918, 22459, "Creature\\Frog\\Frog.m2" },
    { "Jubling", 23811, 14938, "Creature\\Frog\\Frog.m2" },

    ---------------------------------------------------------------------------
    -- BUGS / INSECTS
    ---------------------------------------------------------------------------
    { "Firefly", 36034, 20042, "Creature\\Firefly\\Firefly.m2" },
    { "Bombadier Beetle",           61688,  15467,  "Creature\\Beetle\\Beetle.m2" },  -- Fixed: was 27690 (Tamable Turtle)
    { "Dung Beetle",                61689,  15467,  "Creature\\Beetle\\Beetle.m2" },  -- Fixed: was 27691 (invalid)
    { "Gold Beetle", 61690, 15467, "Creature\\Beetle\\Beetle.m2" },

    ---------------------------------------------------------------------------
    -- MECHANICAL
    ---------------------------------------------------------------------------
    { "Mechanical Squirrel", 4055, 7937, "Creature\\Squirrel\\Squirrel.m2" },
    { "Pet Bombling", 15048, 8909, "Creature\\BombBot\\BombBot.m2" },
    { "Lil' Smoky",                 15049,  8909,   "Creature\\SmallSmoke\\SmallSmoke.m2" },  -- Fixed: was 8986 (invalid)
    { "Mechanical Chicken",	12243,	7920,   "Creature\\MechanicalChicken\\MechanicalChicken.m2" },
    { "Clockwork Rocket Bot", 54187, 22776, "Creature\\RocketBot\\RocketBot.m2" },
    { "Blue Clockwork Rocket Bot",  75134,  22776,  "Creature\\RocketBot\\RocketBot.m2" },  -- Fixed: was 31690 (invalid)
    { "Tranquil Mechanical Yeti", 26010, 10269, "Creature\\Yeti\\Yeti.m2" },
    { "Lifelike Mechanical Toad",   19772,  6297,   "Creature\\Frog\\Frog.m2" },
    { "Lil' XT", 75906, 32031, "Creature\\Xt002\\Xt002.m2" },

    ---------------------------------------------------------------------------
    -- DRAGONS / WHELPS
    ---------------------------------------------------------------------------
    { "Azure Whelpling", 10696, 6293, "Creature\\FaerieDragon\\FaerieDragon.m2" },
    { "Crimson Whelpling", 10697, 6290, "Creature\\WhelpRed\\WhelpRed.m2" },
    { "Dark Whelpling",             10695,  387,    "Creature\\WhelpBlack\\WhelpBlack.m2" },  -- Fixed: was 4543 (Kranal Fiss)
    { "Emerald Whelpling", 10698, 6291, "Creature\\WhelpGreen\\WhelpGreen.m2" },
    { "Onyxian Whelpling", 69002, 30356, "Creature\\WhelpBlack\\WhelpBlack.m2" },
    { "Sprite Darter Hatchling", 15067, 6294, "Creature\\FaerieDragon\\FaerieDragon.m2" },
    { "Proto-Drake Whelp", 61350, 28217, "Creature\\ProtoDrakeWhelp\\ProtoDrakeWhelp.m2" },
    { "Nether Ray Fry", 51716, 25457, "Creature\\NetherRay\\NetherRay.m2" },

    ---------------------------------------------------------------------------
    -- MOTHS
    ---------------------------------------------------------------------------
    { "Blue Moth", 35907, 19987, "Creature\\Moth\\Moth.m2" },
    { "Red Moth", 35909, 19986, "Creature\\Moth\\Moth.m2" },
    { "White Moth", 35911, 19999, "Creature\\Moth\\Moth.m2" },
    { "Yellow Moth", 35910, 19985, "Creature\\Moth\\Moth.m2" },

    ---------------------------------------------------------------------------
    -- DRAGONHAWKS
    ---------------------------------------------------------------------------
    { "Golden Dragonhawk Hatchling", 36027, 20026, "Creature\\DragonHawk\\DragonHawk.m2" },
    { "Red Dragonhawk Hatchling", 36028, 20027, "Creature\\DragonHawk\\DragonHawk.m2" },
    { "Silver Dragonhawk Hatchling", 36029, 20037, "Creature\\DragonHawk\\DragonHawk.m2" },
    { "Blue Dragonhawk Hatchling", 36031, 20029, "Creature\\DragonHawk\\DragonHawk.m2" },

    ---------------------------------------------------------------------------
    -- DOGS / WOLVES
    ---------------------------------------------------------------------------
    { "Worg Pup",	15999,	9563,  "Creature\\Worg\\Worg.m2" },
    { "Perky Pug", 70613, 31174, "Creature\\Pug\\Pug.m2" },

    ---------------------------------------------------------------------------
    -- SCORPIONS
    ---------------------------------------------------------------------------
    { "Scorpid",	10709,	2414,   "Creature\\Scorpion\\Scorpion.m2" },

    ---------------------------------------------------------------------------
    -- TURTLES
    ---------------------------------------------------------------------------
    { "Speedy",                     10709,  27881,  "Creature\\Turtle\\Turtle.m2" },  -- Fixed: was 6125 (invalid)
    { "Loggerhead Snapjaw", 10709, 14657, "Creature\\Turtle\\Turtle.m2" },
    { "Turtle (normal)",            10709,  27881,  "Creature\\Turtle\\Turtle.m2" },  -- Fixed: was 6127 (invalid)

    ---------------------------------------------------------------------------
    -- SPOREBATS / OUTLAND
    ---------------------------------------------------------------------------
    { "Tiny Sporebat", 45082, 22855, "Creature\\SporeBat\\SporeBat.m2" },
    { "Mana Wyrmling",              35156,  21362,  "Creature\\ManaWyrm\\ManaWyrm.m2" },  -- Fixed: was 19737 (Herald Amorlin)

    ---------------------------------------------------------------------------
    -- NORTHREND
    ---------------------------------------------------------------------------
    { "Tickbird Hatchling", 61348, 28214, "Creature\\Tickbird\\Tickbird.m2" },
    { "White Tickbird Hatchling", 61349, 28215, "Creature\\Tickbird\\Tickbird.m2" },
    { "Cobra Hatchling", 61351, 28084, "Creature\\CobraHatchling\\CobraHatchling.m2" },
    { "Pengu", 61357, 28216, "Creature\\Penguin\\Penguin.m2" },
    { "Kirin Tor Familiar", 61472, 14273, "Creature\\ArcaneGuardian\\ArcaneGuardian.m2" },
    { "Ghostly Skull", 53316, 28089, "Creature\\SkeletonMage\\SkeletonMage.m2" },

    ---------------------------------------------------------------------------
    -- TCG / PROMO / BLIZZCON
    ---------------------------------------------------------------------------
    { "Bananas (Monkey)",           30156,  21362,  "Creature\\Monkey\\Monkey.m2" },  -- Fixed: was 17310 (Ashyen)
    { "Egbert (Hawkstrider)",       40614,  19478,  "Creature\\Hawkstrider\\Hawkstrider.m2" },  -- Fixed: was 17510 (Ven)
    { "Peanut (Elekk)",             40634,  17063,  "Creature\\Elekk\\Elekk.m2" },  -- Fixed: was 17512 (Yil)
    { "Willy (Sleepy Willy)",       40613,  15393,  "Creature\\WillyBlinky\\WillyBlinky.m2" },  -- Fixed: was 17282 (invalid)
    { "Lurky (Murloc)",             24988,  15393,  "Creature\\BabyMurloc\\BabyMurloc.m2" },  -- Fixed: was 15357 (Arakis)
    { "Murky (Murloc)",             24696,  15394,  "Creature\\BabyMurloc\\BabyMurloc.m2" },  -- Fixed: was 15361 (invalid)
    { "Gurky (Murloc)",             24697,  15396,  "Creature\\BabyMurloc\\BabyMurloc.m2" },  -- Fixed: was 15360 (invalid)
    { "Terky (Murloc)",             24988,  15397,  "Creature\\BabyMurloc\\BabyMurloc.m2" },  -- Fixed: was 15357 (Arakis)
    { "Murloc Costume (Murloc)",    24696,  21723,  "Creature\\BabyMurloc\\BabyMurloc.m2" },  -- Fixed: was 15362 (Vekniss Hatchling)
    { "Grunty (Murloc Marine)",     66030,  29348,  "Creature\\BabyMurloc\\BabyMurloc.m2" },
    { "Deathy (Murloc Deathwing)",  75906,  31957,  "Creature\\BabyMurloc\\BabyMurloc.m2" },
    { "Baby Blizzard Bear", 61855, 16189, "Creature\\Bear2\\Bear2.m2" },
    { "Frosty (Frost Wyrm)",        52615,  25511,  "Creature\\FrostWyrm\\FrostWyrm.m2" },  -- Fixed: was 25652 (invalid)
    { "Mini Tyrael", 39656, 25900, "Creature\\Tyrael\\Tyrael.m2" },
    { "Spirit of Competition", 48406, 24393, "Creature\\Hippogryph\\Hippogryph.m2" },
    { "Netherwhelp", 32298, 17723, "Creature\\WhelpNether\\WhelpNether.m2" },
    { "Pandaren Monk", 69541, 30414, "Creature\\PandarenMonk\\PandarenMonk.m2" },
    { "Lil' K.T.",                  69677,  30507,  "Creature\\LichKing\\LichKing.m2" },

    ---------------------------------------------------------------------------
    -- ORPHAN WEEK
    ---------------------------------------------------------------------------
    { "Curious Oracle Hatchling", 65381, 25173, "Creature\\WolvarPup\\WolvarPup.m2" },
    { "Curious Wolvar Pup", 65382, 25384, "Creature\\WolvarPup\\WolvarPup.m2" },

    ---------------------------------------------------------------------------
    -- ARGENT TOURNAMENT
    ---------------------------------------------------------------------------
    { "Argent Squire", 62609, 28946, "Creature\\Humanmale\\HumanMale.m2" },
    { "Argent Gruntling", 62746, 28948, "Creature\\OrcMaleChild\\OrcMaleChild.m2" },
    { "Mechanopeep", 62674, 28539, "Creature\\Mechanostrider\\Mechanostrider.m2" },
    { "Shimmering Wyrmling", 66096, 29372, "Creature\\ManaWyrm\\ManaWyrm.m2" },
    { "Sen'jin Fetish", 63712, 29189, "Creature\\FetishTroll\\FetishTroll.m2" },
    { "Tirisfal Batling", 62510, 4732, "Creature\\Bat\\Bat.m2" },
    { "Dun Morogh Cub", 62508, 28489, "Creature\\Bear2\\Bear2.m2" },
    { "Teldrassil Sproutling", 62491, 28482, "Creature\\TreantWardling\\TreantWardling.m2" },
    { "Elwynn Lamb",                62516,  857,    "Creature\\Sheep\\Sheep.m2" },  -- Fixed: was 28520 (invalid)
    { "Durotar Scorpion", 62513, 15470, "Creature\\Scorpion\\Scorpion.m2" },
    { "Mulgore Hatchling", 62542, 28502, "Creature\\Tallstrider\\Tallstrider.m2" },
    { "Ammen Vale Lashling", 62562, 28493, "Creature\\LashVine\\LashVine.m2" },
    { "Enchanted Broom", 62564, 16910, "Creature\\EnchantedBroom\\EnchantedBroom.m2" },

    ---------------------------------------------------------------------------
    -- VARIOUS / SEASONAL
    ---------------------------------------------------------------------------
    { "Disgusting Oozeling", 25162, 15436, "Creature\\Ooze\\Ooze.m2" },
    { "Tiny Crimson Whelpling",     10697,  1206,   "Creature\\WhelpRed\\WhelpRed.m2" },
    { "Sinister Squashling", 42609, 21900, "Creature\\PumpkinSoldier\\PumpkinSoldier.m2" },
    { "Vampiric Batling", 51851, 4185, "Creature\\Bat\\Bat.m2" },
    { "Phoenix Hatchling", 46599, 23574, "Creature\\Phoenix\\Phoenix.m2" },
    { "Magical Crawdad", 33050, 18269, "Creature\\Lobster\\Lobster.m2" },
    { "Mr. Wiggles (Pig)",          10709,  27680,  "Creature\\Boar\\Boar.m2" },  -- Fixed: was 4928 (Takar the Seer)
    { "Whiskers the Rat",           10709,  2176,   "Creature\\Rat\\Rat.m2" },
    { "Stinker (Skunk)",            40990,  16633,  "Creature\\Skunk\\Skunk.m2" },  -- Fixed: was 21510 (invalid)
    { "Smolderweb Hatchling", 10709, 9997, "Creature\\Spider\\Spider.m2" },
    { "Willy (Sleepy Eye)",         40613,  15393,  "Creature\\WillyBlinky\\WillyBlinky.m2" },  -- Fixed: was 17282 (invalid)
    { "Wolpertinger",	39709,	22349,  "Creature\\Wolpertinger\\Wolpertinger.m2" },
    { "Little Fawn", 61991, 28397, "Creature\\Deer\\Deer.m2" },
    { "Leaping Hatchling", 67416, 29802, "Creature\\Raptor\\Raptor.m2" },
    { "Darting Hatchling", 67413, 29805, "Creature\\Raptor\\Raptor.m2" },
    { "Deviate Hatchling", 67414, 29807, "Creature\\Raptor\\Raptor.m2" },
    { "Ravasaur Hatchling", 67418, 29810, "Creature\\Raptor\\Raptor.m2" },
    { "Razormaw Hatchling", 67419, 29808, "Creature\\Raptor\\Raptor.m2" },
    { "Razzashi Hatchling", 67420, 29806, "Creature\\Raptor\\Raptor.m2" },
    { "Obsidian Hatchling", 67417, 29809, "Creature\\Raptor\\Raptor.m2" },
    { "Captured Firefly",           36034,  20029,  "Creature\\Firefly\\Firefly.m2" },
    { "Strand Crawler", 62561, 28507, "Creature\\Crab\\Crab.m2" },
    { "Giant Sewer Rat", 59250, 27627, "Creature\\Rat\\Rat.m2" },
    { "Chuck (Crocodile)",          46426,  1037,   "Creature\\BabyCrocolisk\\BabyCrocolisk.m2" },  -- Fixed: was 22095 (Captured Valgarde Priest)
    { "Muckbreath (Crocodile)",     43698,  1037,   "Creature\\BabyCrocolisk\\BabyCrocolisk.m2" },  -- Fixed: was 22087 (invalid)
    { "Snarly (Crocodile)",         46425,  1037,   "Creature\\BabyCrocolisk\\BabyCrocolisk.m2" },  -- Fixed: was 22094 (Captured Valgarde Prisoner)
    { "Toothy (Crocodile)",         43697,  1037,   "Creature\\BabyCrocolisk\\BabyCrocolisk.m2" },  -- Fixed: was 22089 (invalid)

    ---------------------------------------------------------------------------
    -- ICC PETS
    ---------------------------------------------------------------------------
    { "Core Hound Pup", 69452, 30462, "Creature\\LavaSpawn\\LavaSpawn.m2" },
    { "Toxic Wasteling", 71840, 31073, "Creature\\Ooze\\Ooze.m2" },
    { "Frigid Frostling", 74932, 31722, "Creature\\WaterElemental\\WaterElemental.m2" },
}
