-- CombatPetsDB.lua — All combat pet creatures for WoW 3.3.5a (build 12340)
-- Includes: Hunter pets, Warlock demons, Frost Mage water elemental
-- Format: { "Name", familyName, displayID, "model\\path.m2", npcID }
-- familyName is used for category/type filtering in the UI
-- npcID (optional, 5th field) = creature_template NPC ID for SetCreature() textured preview
--   If npcID is present and > 0, the preview uses SetCreature(npcID) for a fully textured model.
--   If npcID is absent or 0, the preview falls back to SetModel(path) (geometry only).

local _, ns = ...

ns.combatPetsDB = {

    -- ==============================
    -- WOLFS
    -- ==============================
    { "Wolf (Wolfskinbluebrown)", "Wolf", 18063, "Creature\\Wolf\\Wolf.m2" },
    { "Wolf (Wolfskinbrown)", "Wolf", 17079, "Creature\\Wolf\\Wolf.m2" },
    { "Wolf (Wolfskindarkblack)", "Wolf", 741, "Creature\\Wolf\\Wolf.m2" },
    { "Wolf (Wolfskindarkgrey)", "Wolf", 11414, "Creature\\Wolf\\Wolf.m2" },
    { "Wolf (Wolfskinlightblue)", "Wolf", 11412, "Creature\\Wolf\\Wolf.m2" },
    { "Wolf (Wolfskinlightgrey)", "Wolf", 11415, "Creature\\Wolf\\Wolf.m2" },
    { "Wolf (Wolfskinreddishbrown)", "Wolf", 9372, "Creature\\Wolf\\Wolf.m2" },
    { "Wolf (Dragonwhelpskinblack)", "Wolf", 6288, "Creature\\Wolf\\Wolf.m2" },
    { "Wolf (Magehunterred)", "Wolf", 25785, "Creature\\Wolf\\Wolf.m2" },
    { "Wolf (Pvpridingdirewolfskindarkblack)", "Wolf", 14334, "Creature\\Wolf\\Wolf.m2" },
    { "Wolf (_ghost)", "Wolf", 22130, "Creature\\Wolf\\Wolf.m2" },
    { "Wolf (Arctic)", "Wolf", 801, "Creature\\Wolf\\Wolf.m2" },
    { "Wolf (Arcticalpha)", "Wolf", 868, "Creature\\Wolf\\Wolf.m2" },
    { "Wolf (Black)", "Wolf", 781, "Creature\\Wolf\\Wolf.m2" },
    { "Wolf (Coyote)", "Wolf", 161, "Creature\\Wolf\\Wolf.m2" },
    { "Wolf (Diseased)", "Wolf", 31048, "Creature\\Wolf\\Wolf.m2" },
    { "Wolf (Timber)", "Wolf", 903, "Creature\\Wolf\\Wolf.m2" },
    { "Wolf (Worgblack)", "Wolf", 22003, "Creature\\Worg\\Worg.m2" },
    { "Wolf (Worgbrown)", "Wolf", 22502, "Creature\\Worg\\Worg.m2" },
    { "Wolf (Worggray)", "Wolf", 22501, "Creature\\Worg\\Worg.m2" },
    { "Wolf (Worgwhite)", "Wolf", 22089, "Creature\\Worg\\Worg.m2" },

    -- ==============================
    -- CATS
    -- ==============================
    { "Cat (Lionessskingold)", "Cat", 1933, "Creature\\Lion\\Lion.m2" },
    { "Cat (Lionskinblack)", "Cat", 4424, "Creature\\Lion\\Lion.m2" },
    { "Cat (Lionskingold)", "Cat", 1977, "Creature\\Lion\\Lion.m2" },
    { "Cat (Lionskinwhite)", "Cat", 1934, "Creature\\Lion\\Lion.m2" },
    { "Cat (Lynxskinred)", "Cat", 15507, "Creature\\Lynx\\Lynx.m2" },
    { "Cat (Lynxskinyellow)", "Cat", 18167, "Creature\\Lynx\\Lynx.m2" },
    { "Cat (Tigerskinaqua)", "Cat", 10054, "Creature\\Tiger\\Tiger.m2" },
    { "Cat (Tigerskinlavender)", "Cat", 9954, "Creature\\Tiger\\Tiger.m2" },
    { "Cat (Tigerskinyellownosaddle)", "Cat", 25005, "Creature\\Tiger\\Tiger.m2" },
    { "Cat (Tigerskinblack)", "Cat", 2437, "Creature\\Tiger\\Tiger.m2" },
    { "Cat (Tigerskinblackgem)", "Cat", 19607, "Creature\\Tiger\\Tiger.m2" },
    { "Cat (Tigerskinblackspotted)", "Cat", 18416, "Creature\\Tiger\\Tiger.m2" },
    { "Cat (Tigerskinblackstriped)", "Cat", 321, "Creature\\Tiger\\Tiger.m2" },
    { "Cat (Tigerskinbrown)", "Cat", 1059, "Creature\\Tiger\\Tiger.m2" },
    { "Cat (Tigerskindark)", "Cat", 11454, "Creature\\Tiger\\Tiger.m2" },
    { "Cat (Tigerskinnostripewhite)", "Cat", 9958, "Creature\\Tiger\\Tiger.m2" },
    { "Cat (Tigerskinred)", "Cat", 598, "Creature\\Tiger\\Tiger.m2" },
    { "Cat (Tigerskinsnow)", "Cat", 748, "Creature\\Tiger\\Tiger.m2" },
    { "Cat (Tigerskinwhite)", "Cat", 616, "Creature\\Tiger\\Tiger.m2" },
    { "Cat (Tigerskinyellow)", "Cat", 632, "Creature\\Tiger\\Tiger.m2" },

    -- ==============================
    -- SPIDERS
    -- ==============================
    { "Spider (Bonespider_grey)", "Spider", 26774, "Creature\\Spider\\Spider.m2" },
    { "Spider (Giantspider)", "Spider", 17346, "Creature\\Spider\\Spider.m2" },
    { "Spider (Giantspiderblack)", "Spider", 17180, "Creature\\Spider\\Spider.m2" },
    { "Spider (Giantspiderorange)", "Spider", 18043, "Creature\\Spider\\Spider.m2" },
    { "Spider (Minespiderskinblood)", "Spider", 963, "Creature\\Spider\\Spider.m2" },
    { "Spider (Minespiderskincave)", "Spider", 955, "Creature\\Spider\\Spider.m2" },
    { "Spider (Minespiderskincrystal)", "Spider", 4456, "Creature\\Spider\\Spider.m2" },
    { "Spider (Minespiderskingreen)", "Spider", 2541, "Creature\\Spider\\Spider.m2" },
    { "Spider (Minespiderskinjungle)", "Spider", 2536, "Creature\\Spider\\Spider.m2" },
    { "Spider (Minespiderskinolive)", "Spider", 513, "Creature\\Spider\\Spider.m2" },
    { "Spider (Minespiderskinsteel)", "Spider", 368, "Creature\\Spider\\Spider.m2" },
    { "Spider (Minespiderskinviolet)", "Spider", 15937, "Creature\\Spider\\Spider.m2" },
    { "Spider (Minespiderskinwetlands)", "Spider", 711, "Creature\\Spider\\Spider.m2" },
    { "Spider (Tarantulaskinbrown)", "Spider", 520, "Creature\\Spider\\Spider.m2" },
    { "Spider (Tarantulaskingreen)", "Spider", 336, "Creature\\Spider\\Spider.m2" },
    { "Spider (Tarantulaskingrey)", "Spider", 1091, "Creature\\Spider\\Spider.m2" },
    { "Spider (Tarantulaskinmagma)", "Spider", 4457, "Creature\\Spider\\Spider.m2" },
    { "Spider (Tarantulaskinorange)", "Spider", 382, "Creature\\Spider\\Spider.m2" },

    -- ==============================
    -- BEARS
    -- ==============================
    { "Bear (Black)", "Bear", 8843, "Creature\\Bear\\Bear.m2" },
    { "Bear (Blackdiseased)", "Bear", 1082, "Creature\\Bear\\Bear.m2" },
    { "Bear (Blue)", "Bear", 8840, "Creature\\Bear\\Bear.m2" },
    { "Bear (Brown)", "Bear", 1006, "Creature\\Bear\\Bear.m2" },
    { "Bear (Drkbrown)", "Bear", 820, "Creature\\Bear\\Bear.m2" },
    { "Bear (Drkbrowndiseased)", "Bear", 1083, "Creature\\Bear\\Bear.m2" },
    { "Bear (White)", "Bear", 913, "Creature\\Bear\\Bear.m2" },
    { "Bear (Whitediseased)", "Bear", 23966, "Creature\\Bear\\Bear.m2" },

    -- ==============================
    -- BOARS
    -- ==============================
    { "Boar (Blue)", "Boar", 381, "Creature\\Boar\\Boar.m2" },
    { "Boar (Bluearmored)", "Boar", 4714, "Creature\\Boar\\Boar.m2" },
    { "Boar (Brown)", "Boar", 703, "Creature\\Boar\\Boar.m2" },
    { "Boar (Brownarmored)", "Boar", 4713, "Creature\\Boar\\Boar.m2" },
    { "Boar (Crimson)", "Boar", 3027, "Creature\\Boar\\Boar.m2" },
    { "Boar (Ivory)", "Boar", 503, "Creature\\Boar\\Boar.m2" },
    { "Boar (Ivoryarmored)", "Boar", 2453, "Creature\\Boar\\Boar.m2" },
    { "Boar (Undead)", "Boar", 6121, "Creature\\Boar\\Boar.m2" },
    { "Boar (Yellow)", "Boar", 8871, "Creature\\Boar\\Boar.m2" },

    -- ==============================
    -- CROCOLISKS
    -- ==============================
    { "Crocolisk (Crocodileskinalbino)", "Crocolisk", 2850, "Creature\\Crocolisk\\Crocolisk.m2" },
    { "Crocolisk (Crocodileskinmarsh)", "Crocolisk", 2548, "Creature\\Crocolisk\\Crocolisk.m2" },
    { "Crocolisk (Crocodileskinriver)", "Crocolisk", 1039, "Creature\\Crocolisk\\Crocolisk.m2" },
    { "Crocolisk (Crocodileskinswamp)", "Crocolisk", 807, "Creature\\Crocolisk\\Crocolisk.m2" },

    -- ==============================
    -- CARRION BIRDS
    -- ==============================
    { "Carrion Bird (Arcticcondorblue)", "Carrion Bird", 23962, "Creature\\Vulture\\Vulture.m2" },
    { "Carrion Bird (Arcticcondorwhite)", "Carrion Bird", 23483, "Creature\\Vulture\\Vulture.m2" },
    { "Carrion Bird (Carrionbirdskin)", "Carrion Bird", 1105, "Creature\\Vulture\\Vulture.m2" },
    { "Carrion Bird (Carrionbirdskinblue)", "Carrion Bird", 507, "Creature\\Vulture\\Vulture.m2" },
    { "Carrion Bird (Carrionbirdskinbrown)", "Carrion Bird", 410, "Creature\\Vulture\\Vulture.m2" },
    { "Carrion Bird (Carrionbirdskinoutland)", "Carrion Bird", 16880, "Creature\\Vulture\\Vulture.m2" },
    { "Carrion Bird (Carrionbirdskinoutlandwhite)", "Carrion Bird", 20348, "Creature\\Vulture\\Vulture.m2" },
    { "Carrion Bird (Carrionbirdskinred)", "Carrion Bird", 490, "Creature\\Vulture\\Vulture.m2" },
    { "Carrion Bird (Owlarrokoagreen)", "Carrion Bird", 21003, "Creature\\Vulture\\Vulture.m2" },
    { "Carrion Bird (Stormcrowdruidskin)", "Carrion Bird", 20857, "Creature\\Vulture\\Vulture.m2" },
    { "Carrion Bird (Stormcrowskin)", "Carrion Bird", 20013, "Creature\\Vulture\\Vulture.m2" },

    -- ==============================
    -- CRABS
    -- ==============================
    { "Crab (Bronze)", "Crab", 342, "Creature\\Crab\\Crab.m2" },
    { "Crab (Ivory)", "Crab", 999, "Creature\\Crab\\Crab.m2" },
    { "Crab (Saphire)", "Crab", 979, "Creature\\Crab\\Crab.m2" },
    { "Crab (Vermillian)", "Crab", 1307, "Creature\\Crab\\Crab.m2" },

    -- ==============================
    -- GORILLAS
    -- ==============================
    { "Gorilla (Black)", "Gorilla", 845, "Creature\\Gorilla\\Gorilla.m2" },
    { "Gorilla (Grey)", "Gorilla", 843, "Creature\\Gorilla\\Gorilla.m2" },
    { "Gorilla (Red)", "Gorilla", 3186, "Creature\\Gorilla\\Gorilla.m2" },
    { "Gorilla (Silver)", "Gorilla", 837, "Creature\\Gorilla\\Gorilla.m2" },
    { "Gorilla (White)", "Gorilla", 8129, "Creature\\Gorilla\\Gorilla.m2" },

    -- ==============================
    -- RAPTORS
    -- ==============================
    { "Raptor (Raptor_outlandblack)", "Raptor", 20093, "Creature\\Raptor\\Raptor.m2" },
    { "Raptor (Raptor_outlandgreen)", "Raptor", 19742, "Creature\\Raptor\\Raptor.m2" },
    { "Raptor (Raptor_outlandred)", "Raptor", 19735, "Creature\\Raptor\\Raptor.m2" },
    { "Raptor (Raptor_outlandyellow)", "Raptor", 19758, "Creature\\Raptor\\Raptor.m2" },
    { "Raptor (Grey)", "Raptor", 1746, "Creature\\Raptor\\Raptor.m2" },
    { "Raptor (Mottledbluegreen)", "Raptor", 8472, "Creature\\Raptor\\Raptor.m2" },
    { "Raptor (Mottleddarkgreen)", "Raptor", 615, "Creature\\Raptor\\Raptor.m2" },
    { "Raptor (Orange)", "Raptor", 788, "Creature\\Raptor\\Raptor.m2" },
    { "Raptor (Red)", "Raptor", 2571, "Creature\\Raptor\\Raptor.m2" },
    { "Raptor (Violet)", "Raptor", 11317, "Creature\\Raptor\\Raptor.m2" },
    { "Raptor (Yellow)", "Raptor", 11316, "Creature\\Raptor\\Raptor.m2" },
    { "Raptor (Raptorskinobsidian)", "Raptor", 5291, "Creature\\Raptor\\Raptor.m2" },

    -- ==============================
    -- TALLSTRIDERS
    -- ==============================
    { "Tallstrider (Brown)", "Tallstrider", 1042, "Creature\\Tallstrider\\Tallstrider.m2" },
    { "Tallstrider (Gray)", "Tallstrider", 1220, "Creature\\Tallstrider\\Tallstrider.m2" },
    { "Tallstrider (Ivory)", "Tallstrider", 1221, "Creature\\Tallstrider\\Tallstrider.m2" },
    { "Tallstrider (Pink)", "Tallstrider", 1961, "Creature\\Tallstrider\\Tallstrider.m2" },
    { "Tallstrider (Purple)", "Tallstrider", 21268, "Creature\\Tallstrider\\Tallstrider.m2" },
    { "Tallstrider (Turquoise)", "Tallstrider", 38, "Creature\\Tallstrider\\Tallstrider.m2" },

    -- ==============================
    -- SCORPIDS
    -- ==============================
    { "Scorpid (Scorpionskinbeige)", "Scorpid", 2485, "Creature\\Scorpid\\Scorpid.m2" },
    { "Scorpid (Scorpionskinblack)", "Scorpid", 2488, "Creature\\Scorpid\\Scorpid.m2" },
    { "Scorpid (Scorpionskinblue)", "Scorpid", 2730, "Creature\\Scorpid\\Scorpid.m2" },
    { "Scorpid (Scorpionskingolden)", "Scorpid", 2729, "Creature\\Scorpid\\Scorpid.m2" },
    { "Scorpid (Scorpionskinpink)", "Scorpid", 2414, "Creature\\Scorpid\\Scorpid.m2" },
    { "Scorpid (Scorpionskinred)", "Scorpid", 3247, "Creature\\Scorpid\\Scorpid.m2" },
    { "Scorpid (Scorpionskinsilver)", "Scorpid", 10988, "Creature\\Scorpid\\Scorpid.m2" },
    { "Scorpid (Scorpionskinyellow)", "Scorpid", 2487, "Creature\\Scorpid\\Scorpid.m2" },

    -- ==============================
    -- TURTLES
    -- ==============================
    { "Turtle (Seaturtleskin)", "Turtle", 1244, "Creature\\Turtle\\Turtle.m2" },
    { "Turtle (Seaturtleskinblue)", "Turtle", 6368, "Creature\\Turtle\\Turtle.m2" },
    { "Turtle (Seaturtleskingrey)", "Turtle", 4829, "Creature\\Turtle\\Turtle.m2" },
    { "Turtle (Seaturtleskinred)", "Turtle", 5027, "Creature\\Turtle\\Turtle.m2" },
    { "Turtle (Seaturtleskinwhite)", "Turtle", 5052, "Creature\\Turtle\\Turtle.m2" },

    -- ==============================
    -- BATS
    -- ==============================
    { "Bat (01)", "Bat", 1955, "Creature\\Bat\\Bat.m2" },
    { "Bat (Brown01)", "Bat", 4732, "Creature\\Bat\\Bat.m2" },
    { "Bat (Violet01)", "Bat", 8808, "Creature\\Bat\\Bat.m2" },
    { "Bat (White01)", "Bat", 4735, "Creature\\Bat\\Bat.m2" },

    -- ==============================
    -- HYENAS
    -- ==============================
    { "Hyena (Default)", "Hyena", 1536, "Creature\\Hyena\\Hyena.m2" },
    { "Hyena (Black)", "Hyena", 2726, "Creature\\Hyena\\Hyena.m2" },
    { "Hyena (Blue)", "Hyena", 2713, "Creature\\Hyena\\Hyena.m2" },
    { "Hyena (Oarnge)", "Hyena", 1535, "Creature\\Hyena\\Hyena.m2" },
    { "Hyena (Red)", "Hyena", 2709, "Creature\\Hyena\\Hyena.m2" },
    { "Hyena (White)", "Hyena", 2716, "Creature\\Hyena\\Hyena.m2" },
    { "Hyena (Yellow)", "Hyena", 2710, "Creature\\Hyena\\Hyena.m2" },

    -- ==============================
    -- BIRD OF PREYS
    -- ==============================
    { "Bird of Prey (Browneagle)", "Bird of Prey", 22321, "Creature\\Eagle\\Eagle.m2" },
    { "Bird of Prey (Carrionbirdskinoutlandblue)", "Bird of Prey", 20300, "Creature\\Eagle\\Eagle.m2" },
    { "Bird of Prey (Eagle)", "Bird of Prey", 22106, "Creature\\Eagle\\Eagle.m2" },
    { "Bird of Prey (Owlarrokoagreen)", "Bird of Prey", 20725, "Creature\\Eagle\\Eagle.m2" },
    { "Bird of Prey (Owlarrokoapurple)", "Bird of Prey", 20738, "Creature\\Eagle\\Eagle.m2" },
    { "Bird of Prey (Owlarrokoared)", "Bird of Prey", 20730, "Creature\\Eagle\\Eagle.m2" },
    { "Bird of Prey (Owlblack)", "Bird of Prey", 6299, "Creature\\Eagle\\Eagle.m2" },
    { "Bird of Prey (Owlbrown)", "Bird of Prey", 4615, "Creature\\Eagle\\Eagle.m2" },
    { "Bird of Prey (Owlgrey)", "Bird of Prey", 10832, "Creature\\Eagle\\Eagle.m2" },
    { "Bird of Prey (Owljade)", "Bird of Prey", 24453, "Creature\\Eagle\\Eagle.m2" },
    { "Bird of Prey (Owlwhite)", "Bird of Prey", 6212, "Creature\\Eagle\\Eagle.m2" },
    { "Bird of Prey (Parrotskinblue)", "Bird of Prey", 27975, "Creature\\Eagle\\Eagle.m2" },
    { "Bird of Prey (Snowyeagle)", "Bird of Prey", 25925, "Creature\\Eagle\\Eagle.m2" },
    { "Bird of Prey (Stormcrowdruidskin_brown)", "Bird of Prey", 22633, "Creature\\Eagle\\Eagle.m2" },

    -- ==============================
    -- SERPENTS
    -- ==============================
    { "Serpent (Windserpentskin)", "Serpent", 1742, "Creature\\WindSerpent\\WindSerpent.m2" },
    { "Serpent (Windserpentskinblack)", "Serpent", 3006, "Creature\\WindSerpent\\WindSerpent.m2" },
    { "Serpent (Windserpentskingreen)", "Serpent", 4091, "Creature\\WindSerpent\\WindSerpent.m2" },
    { "Serpent (Windserpentskinoarnge)", "Serpent", 19793, "Creature\\WindSerpent\\WindSerpent.m2" },
    { "Serpent (Windserpentskinoutland)", "Serpent", 20838, "Creature\\WindSerpent\\WindSerpent.m2" },
    { "Serpent (Windserpentskinoutland3)", "Serpent", 20094, "Creature\\WindSerpent\\WindSerpent.m2" },
    { "Serpent (Windserpentskinoutland4)", "Serpent", 19788, "Creature\\WindSerpent\\WindSerpent.m2" },
    { "Serpent (Windserpentskinoutland5)", "Serpent", 25460, "Creature\\WindSerpent\\WindSerpent.m2" },
    { "Serpent (Windserpentskinred)", "Serpent", 2699, "Creature\\WindSerpent\\WindSerpent.m2" },
    { "Serpent (Windserpentskinwhite)", "Serpent", 2705, "Creature\\WindSerpent\\WindSerpent.m2" },

    -- ==============================
    -- DRAGONHAWKS
    -- ==============================
    { "Dragonhawk (Default)", "Dragonhawk", 17547, "Creature\\DragonHawk\\DragonHawk.m2" },
    { "Dragonhawk (01)", "Dragonhawk", 17545, "Creature\\DragonHawk\\DragonHawk.m2" },
    { "Dragonhawk (03)", "Dragonhawk", 19299, "Creature\\DragonHawk\\DragonHawk.m2" },
    { "Dragonhawk (05)", "Dragonhawk", 19685, "Creature\\DragonHawk\\DragonHawk.m2" },

    -- ==============================
    -- RAVAGERS
    -- ==============================
    { "Ravager (Crawlerelite_green)", "Ravager", 20297, "Creature\\Ravager\\Ravager.m2" },
    { "Ravager (Crawlerelite_orange)", "Ravager", 20309, "Creature\\Ravager\\Ravager.m2" },
    { "Ravager (Crawlerelite_purple)", "Ravager", 20308, "Creature\\Ravager\\Ravager.m2" },
    { "Ravager (Crawlergreen)", "Ravager", 17061, "Creature\\Ravager\\Ravager.m2" },
    { "Ravager (Crawlerorange)", "Ravager", 16887, "Creature\\Ravager\\Ravager.m2" },
    { "Ravager (Crawlerpurple)", "Ravager", 17086, "Creature\\Ravager\\Ravager.m2" },
    { "Ravager (Crawlervar1)", "Ravager", 19844, "Creature\\Ravager\\Ravager.m2" },
    { "Ravager (Crawlervar5)", "Ravager", 20062, "Creature\\Ravager\\Ravager.m2" },
    { "Ravager (Crawlervar8)", "Ravager", 20063, "Creature\\Ravager\\Ravager.m2" },

    -- ==============================
    -- WARP STALKERS
    -- ==============================
    { "Warp Stalker (Warpstalkerskinblack)", "Warp Stalker", 19996, "Creature\\WarpStalker\\WarpStalker.m2" },
    { "Warp Stalker (Warpstalkerskinblue)", "Warp Stalker", 18719, "Creature\\WarpStalker\\WarpStalker.m2" },
    { "Warp Stalker (Warpstalkerskingreen)", "Warp Stalker", 19369, "Creature\\WarpStalker\\WarpStalker.m2" },
    { "Warp Stalker (Warpstalkerskinred)", "Warp Stalker", 20142, "Creature\\WarpStalker\\WarpStalker.m2" },
    { "Warp Stalker (Warpstalkerskinturquiose)", "Warp Stalker", 19979, "Creature\\WarpStalker\\WarpStalker.m2" },
    { "Warp Stalker (Warpstalkerskinwhite)", "Warp Stalker", 20025, "Creature\\WarpStalker\\WarpStalker.m2" },

    -- ==============================
    -- SPOREBATS
    -- ==============================
    { "Sporebat (Sporebatblue)", "Sporebat", 17751, "Creature\\Sporebat\\Sporebat.m2" },
    { "Sporebat (Sporebatgreen)", "Sporebat", 17752, "Creature\\Sporebat\\Sporebat.m2" },
    { "Sporebat (Sporebatyellow)", "Sporebat", 18029, "Creature\\Sporebat\\Sporebat.m2" },

    -- ==============================
    -- NETHER RAYS
    -- ==============================
    { "Nether Ray (Netherrayskinblack)", "Nether Ray", 19403, "Creature\\NetherRay\\NetherRay.m2" },
    { "Nether Ray (Netherrayskinblue)", "Nether Ray", 19405, "Creature\\NetherRay\\NetherRay.m2" },
    { "Nether Ray (Netherrayskingreen)", "Nether Ray", 19404, "Creature\\NetherRay\\NetherRay.m2" },
    { "Nether Ray (Netherrayskinred)", "Nether Ray", 20596, "Creature\\NetherRay\\NetherRay.m2" },
    { "Nether Ray (Netherwyrmskin)", "Nether Ray", 19401, "Creature\\NetherRay\\NetherRay.m2" },

    -- ==============================
    -- SNAKES
    -- ==============================
    { "Snake (Serpantskinblue)", "Snake", 4317, "Creature\\Cobra\\Cobra.m2" },
    { "Snake (Serpantskinbrown)", "Snake", 15182, "Creature\\Cobra\\Cobra.m2" },
    { "Snake (Serpantskingreen)", "Snake", 4768, "Creature\\Cobra\\Cobra.m2" },
    { "Snake (Serpantskinpurple)", "Snake", 4312, "Creature\\Cobra\\Cobra.m2" },
    { "Snake (Serpantskinwhite)", "Snake", 4305, "Creature\\Cobra\\Cobra.m2" },

    -- ==============================
    -- MOTHS
    -- ==============================
    { "Moth (Beige)", "Moth", 17574, "Creature\\Moth\\Moth.m2" },
    { "Moth (Blue)", "Moth", 17709, "Creature\\Moth\\Moth.m2" },
    { "Moth (Red)", "Moth", 17795, "Creature\\Moth\\Moth.m2" },
    { "Moth (White)", "Moth", 23237, "Creature\\Moth\\Moth.m2" },
    { "Moth (Yellow)", "Moth", 17798, "Creature\\Moth\\Moth.m2" },

    -- ==============================
    -- CHIMERAS
    -- ==============================
    { "Chimera (01)", "Chimera", 8015, "Creature\\HydraMount\\HydraMount.m2" },
    { "Chimera (Blue_01)", "Chimera", 10807, "Creature\\HydraMount\\HydraMount.m2" },
    { "Chimera (Outlandgreen_01)", "Chimera", 17091, "Creature\\HydraMount\\HydraMount.m2" },
    { "Chimera (Outlandpurple_01)", "Chimera", 19913, "Creature\\HydraMount\\HydraMount.m2" },

    -- ==============================
    -- DEVILSAURS
    -- ==============================
    { "Devilsaur (Trexskinblack)", "Devilsaur", 5238, "Creature\\Devilsaur\\Devilsaur.m2" },
    { "Devilsaur (Trexskingreen)", "Devilsaur", 28052, "Creature\\Devilsaur\\Devilsaur.m2" },
    { "Devilsaur (Trexskinred)", "Devilsaur", 5240, "Creature\\Devilsaur\\Devilsaur.m2" },
    { "Devilsaur (Trexskinwhite)", "Devilsaur", 5239, "Creature\\Devilsaur\\Devilsaur.m2" },

    -- ==============================
    -- SILITHIDS
    -- ==============================
    { "Silithid (Silithidtankskinblue)", "Silithid", 3195, "Creature\\SilithidTank\\SilithidTank.m2" },
    { "Silithid (Silithidtankskingolden)", "Silithid", 11087, "Creature\\SilithidTank\\SilithidTank.m2" },
    { "Silithid (Silithidtankskintan)", "Silithid", 11099, "Creature\\SilithidTank\\SilithidTank.m2" },
    { "Silithid (Silithidtankskinviolet)", "Silithid", 11079, "Creature\\SilithidTank\\SilithidTank.m2" },

    -- ==============================
    -- WORMS
    -- ==============================
    { "Worm (Jormungarlarvablue)", "Worm", 24564, "Creature\\Jormungar\\Jormungar.m2" },
    { "Worm (Blue)", "Worm", 12333, "Creature\\Jormungar\\Jormungar.m2" },
    { "Worm (Brown)", "Worm", 8182, "Creature\\Jormungar\\Jormungar.m2" },
    { "Worm (Gray)", "Worm", 15386, "Creature\\Jormungar\\Jormungar.m2" },
    { "Worm (Green)", "Worm", 12335, "Creature\\Jormungar\\Jormungar.m2" },
    { "Worm (White)", "Worm", 7549, "Creature\\Jormungar\\Jormungar.m2" },
    { "Worm (Yellow)", "Worm", 12336, "Creature\\Jormungar\\Jormungar.m2" },

    -- ==============================
    -- WARLOCK DEMONS
    -- ==============================
    { "Imp",                   "Warlock",      4449,  "Creature\\Imp\\Imp.m2", 416 },
    { "Imp (Flame)",           "Warlock",      12472, "Creature\\Imp\\Imp.m2" },
    { "Voidwalker",            "Warlock",      1132,  "Creature\\VoidWalker\\VoidWalker.m2", 1860 },
    { "Voidwalker (Dark)",     "Warlock",      23705, "Creature\\VoidWalker\\VoidWalker.m2" },
    { "Succubus",              "Warlock",      4162,  "Creature\\Succubus\\Succubus.m2", 1863 },
    { "Felhunter",             "Warlock",      850,   "Creature\\FelHunter\\FelHunter.m2", 417 },
    { "Felguard",              "Warlock",      18462, "Creature\\FelGuard\\FelGuard.m2", 17252 },
    { "Felguard (Armored)",    "Warlock",      18483, "Creature\\FelGuard\\FelGuard.m2" },
    { "Infernal",              "Warlock",      169,   "Creature\\Infernal\\Infernal.m2", 89 },
    { "Infernal (Abyssal)",    "Warlock",      15654, "Creature\\Infernal\\Infernal.m2" },
    { "Doomguard",             "Warlock",      11380, "Creature\\DoomGuard\\DoomGuard.m2" },
    { "Doomguard (Felfire)",   "Warlock",      21072, "Creature\\DoomGuard\\DoomGuard.m2" },
    { "Fel Stalker",           "Warlock",      15200, "Creature\\FelHunter\\FelHunter.m2" },

    -- ==============================
    -- MAGE PETS
    -- ==============================
    { "Water Elemental",       "Mage",         525,   "Creature\\WaterElemental\\WaterElemental.m2", 510 },
    { "Water Elemental (Large)","Mage",        5765,  "Creature\\WaterElemental\\WaterElemental.m2" },
    { "Water Elemental (Glacial)", "Mage",      28232, "Creature\\WaterElemental\\WaterElemental.m2" },
    { "Frost Elemental",       "Mage",         26428, "Creature\\FrostElemental\\FrostElemental.m2" },
    { "Bound Water Elemental", "Mage",         16942, "Creature\\WaterElemental\\WaterElemental.m2" },
}
