local addon, ns = ...

-- ============================================================
-- TRANSMORPHER CONSTANTS
-- Centralized color palette, dimensions, slot data, race data
-- ============================================================

ns.VERSION = "3.0.0"
ns.ADDON_PREFIX = "Transmorpher"

-- ============================================================
-- COLOR PALETTE
-- ============================================================
ns.Colors = {
    -- Primary gold accents
    gold        = { 1.00, 0.82, 0.20 },
    goldDark    = { 0.80, 0.65, 0.22 },
    goldLight   = { 0.95, 0.88, 0.65 },
    goldMuted   = { 0.60, 0.50, 0.18 },
    goldText    = { 0.95, 0.93, 0.88 },
    goldOrange  = { 0.96, 0.78, 0.26 },

    -- Backgrounds
    bgDark      = { 0.04, 0.03, 0.03 },
    bgMedium    = { 0.08, 0.06, 0.03 },
    bgLight     = { 0.12, 0.10, 0.06 },
    bgPanel     = { 0.06, 0.05, 0.03 },

    -- Text
    textWhite   = { 1.00, 1.00, 1.00 },
    textGray    = { 0.70, 0.70, 0.70 },
    textMuted   = { 0.50, 0.50, 0.50 },
    textDesc    = { 0.60, 0.53, 0.40 },
    textLore    = { 0.53, 0.49, 0.42 },

    -- Glow colors (for morphed slots)
    glowGold    = { 1.00, 0.85, 0.20, 0.60 },
    glowGreen   = { 0.20, 1.00, 0.20, 0.50 },
    glowOrange  = { 1.00, 0.50, 0.00, 0.55 },
    glowRed     = { 1.00, 0.20, 0.20, 0.55 },
    glowPurple  = { 0.70, 0.30, 1.00, 0.55 },

    -- Status
    statusGreen = { 0.29, 0.80, 0.29 },
    statusRed   = { 0.80, 0.29, 0.29 },

    -- ============================================================
    -- DESIGN-SYSTEM PALETTE EXTENSIONS (Phase 1 UI overhaul)
    -- Single source of truth for the refined dark-premium-gold theme.
    -- All values are RGB(A) 0..1 tuples consumed by the Theme factories.
    -- ============================================================
    -- Surface tiers (darkest -> lightest). Window > card > well.
    surfaceShell   = { 0.030, 0.025, 0.020, 0.985 },
    surfaceCard    = { 0.055, 0.045, 0.032, 0.96  },
    surfaceWell    = { 0.022, 0.018, 0.014, 0.98  },
    surfaceInset   = { 0.045, 0.038, 0.028, 0.95  },

    -- Hairlines & borders. "Hair" = default 1px; "Line" = structural; "Glow" = accent.
    borderHair     = { 0.62, 0.49, 0.16, 0.85 },
    borderHairDim  = { 0.40, 0.34, 0.16, 0.55 },
    borderLine     = { 0.52, 0.39, 0.12, 0.75 },
    borderAccent   = { 0.96, 0.78, 0.26, 1.00 },
    borderGlow     = { 1.00, 0.82, 0.20, 1.00 },
    borderHover    = { 0.80, 0.65, 0.22, 1.00 },

    -- Row states for list rows (rgba, applied as SetTexture vertex color).
    rowRest        = { 0.04, 0.035, 0.025, 0.0   },
    rowStripe      = { 1.00, 1.00,  1.00,  0.018 },
    rowHover       = { 0.30, 0.25,  0.10,  0.22  },
    rowSelected    = { 0.60, 0.48,  0.15,  0.30  },

    -- Text states (consumed directly via SetTextColor).
    textPrimary    = { 0.96, 0.90, 0.72 },
    textSecondary  = { 0.85, 0.78, 0.55 },
    textMutedGold  = { 0.58, 0.52, 0.40 },
    textAccent     = { 1.00, 0.84, 0.40 },
    textHighlight  = { 1.00, 0.92, 0.64 },

    -- Control backgrounds.
    inputRest      = { 0.045, 0.040, 0.030, 0.96 },
    inputFocus     = { 0.07,  0.06,  0.035, 0.98 },
    buttonRest     = { 0.125, 0.085, 0.025, 0.99 },
    buttonHover    = { 0.205, 0.145, 0.042, 1.00 },
}

-- ============================================================
-- DIMENSIONS
-- ============================================================
ns.Dimensions = {
    mainWidth   = 1045,
    mainHeight  = 584,
    tabHeight   = 30,
    slotSize    = 40,
    slotGap     = 3,
    dressingW   = 350,
    dressingH   = 430,
}

-- ============================================================
-- SLOT DEFINITIONS
-- ============================================================

ns.armorSlots = {"Head", "Shoulder", "Chest", "Wrist", "Hands", "Waist", "Legs", "Feet"}
ns.backSlot = "Back"
ns.miscSlots = {"Tabard", "Shirt"}
ns.mainHandSlot = "Main Hand"
ns.offHandSlot = "Off-hand"
ns.rangedSlot = "Ranged"
ns.chestSlots = {"Chest", "Tabard", "Shirt"}

ns.slotOrder = {
    "Head", "Shoulder", "Back", "Chest", "Shirt", "Tabard",
    "Wrist", "Hands", "Waist", "Legs", "Feet",
    "Main Hand", "Off-hand", "Ranged",
}

ns.enchantSlotNames = { "Enchant MH", "Enchant OH" }

-- WoW equipment slot IDs for DLL morph calls
ns.slotToEquipSlotId = {
    ["Head"] = 1, ["Shoulder"] = 3, ["Back"] = 15, ["Chest"] = 5,
    ["Shirt"] = 4, ["Tabard"] = 19, ["Wrist"] = 9, ["Hands"] = 10,
    ["Waist"] = 6, ["Legs"] = 7, ["Feet"] = 8,
    ["Main Hand"] = 16, ["Off-hand"] = 17, ["Ranged"] = 18,
}

-- Reverse mapping
ns.equipSlotIdToSlot = {}
for name, id in pairs(ns.slotToEquipSlotId) do
    ns.equipSlotIdToSlot[id] = name
end

-- Morph-slot index (1..19) used by DLL item commands (ITEM / ITEM_RETEX_SLOT) is the
-- SAME indexing as the equip-slot id above (Head=1, Shoulder=3, Chest=5, Back=15,
-- MainHand=16, OffHand=17, Ranged=18, Tabard=19, ...). SkinTab relies on this map for
-- slot-based skinning; it was referenced but never defined, which silently broke ALL
-- item skins (idx=nil -> ApplySlot returned early, no command sent). Alias it here.
ns.slotToMorphSlot = ns.slotToEquipSlotId

-- Slot background textures
ns.slotTextures = {
    ["Head"]       = "Interface\\Paperdoll\\ui-paperdoll-slot-head",
    ["Shoulder"]   = "Interface\\Paperdoll\\ui-paperdoll-slot-shoulder",
    ["Back"]       = "Interface\\Paperdoll\\ui-paperdoll-slot-chest",
    ["Chest"]      = "Interface\\Paperdoll\\ui-paperdoll-slot-chest",
    ["Shirt"]      = "Interface\\Paperdoll\\ui-paperdoll-slot-shirt",
    ["Tabard"]     = "Interface\\Paperdoll\\ui-paperdoll-slot-tabard",
    ["Wrist"]      = "Interface\\Paperdoll\\ui-paperdoll-slot-wrists",
    ["Hands"]      = "Interface\\Paperdoll\\ui-paperdoll-slot-hands",
    ["Waist"]      = "Interface\\Paperdoll\\ui-paperdoll-slot-waist",
    ["Legs"]       = "Interface\\Paperdoll\\ui-paperdoll-slot-legs",
    ["Feet"]       = "Interface\\Paperdoll\\ui-paperdoll-slot-feet",
    ["Main Hand"]  = "Interface\\Paperdoll\\ui-paperdoll-slot-mainhand",
    ["Off-hand"]   = "Interface\\Paperdoll\\ui-paperdoll-slot-secondaryhand",
    ["Ranged"]     = "Interface\\Paperdoll\\ui-paperdoll-slot-ranged",
}

-- ============================================================
-- SUBCLASS DATA (weapon/armor types per slot)
-- ============================================================
ns.slotSubclasses = {}

do
    for _, slot in ipairs(ns.armorSlots) do
        ns.slotSubclasses[slot] = {"Cloth", "Leather", "Mail", "Plate"}
    end
    for _, slot in ipairs(ns.miscSlots) do
        ns.slotSubclasses[slot] = {"Miscellaneous"}
    end
    ns.slotSubclasses[ns.backSlot] = {"Cloth"}

    local allWeaponTypes = {
        "1H Axe", "1H Mace", "1H Sword", "1H Dagger", "1H Fist",
        "MH Axe", "MH Mace", "MH Sword", "MH Dagger", "MH Fist",
        "OH Axe", "OH Mace", "OH Sword", "OH Dagger", "OH Fist",
        "2H Axe", "2H Mace", "2H Sword", "Polearm", "Staff",
        "Shield", "Held in Off-hand",
        "Bow", "Crossbow", "Gun", "Wand", "Thrown",
    }
    ns.slotSubclasses[ns.mainHandSlot] = allWeaponTypes
    ns.slotSubclasses[ns.offHandSlot]  = allWeaponTypes
    ns.slotSubclasses[ns.rangedSlot]   = allWeaponTypes
end

-- Default armor subclass per class
ns.defaultArmorSubclass = {
    ["MAGE"] = "Cloth", ["PRIEST"] = "Cloth", ["WARLOCK"] = "Cloth",
    ["DRUID"] = "Leather", ["ROGUE"] = "Leather",
    ["HUNTER"] = "Mail", ["SHAMAN"] = "Mail",
    ["PALADIN"] = "Plate", ["WARRIOR"] = "Plate", ["DEATHKNIGHT"] = "Plate",
}

-- ============================================================
-- RACE MORPH DISPLAY IDs
-- ============================================================
ns.raceDisplayIds = {
    ["Human"]      = { [2] = 19723, [3] = 19724 },
    ["Orc"]        = { [2] = 6785,  [3] = 20316 },
    ["Dwarf"]      = { [2] = 20317, [3] = 13250 },
    ["Night Elf"]  = { [2] = 20318, [3] = 2222  },
    ["Undead"]     = { [2] = 28193, [3] = 23112 },
    ["Tauren"]     = { [2] = 20585, [3] = 20584 },
    ["Gnome"]      = { [2] = 20580, [3] = 20581 },
    ["Troll"]      = { [2] = 20321, [3] = 4358  },
    ["Blood Elf"]  = { [2] = 20578, [3] = 20579 },
    ["Draenei"]    = { [2] = 17155, [3] = 20323 },
}
ns.raceOrder = {"Human", "Orc", "Dwarf", "Night Elf", "Undead", "Tauren", "Gnome", "Troll", "Blood Elf", "Draenei"}

-- ============================================================
-- POPULAR CREATURES (for Morph tab quick buttons)
-- ============================================================
ns.popularCreatures = {
    { name = "Lich King",     id = 22234 },
    { name = "Illidan",       id = 21135 },
    { name = "Sylvanas",      id = 28213 },
    { name = "Alexstrasza",   id = 28227 },
    { name = "Ragnaros",      id = 11121 },
    { name = "Brann Bronzebeard", id = 22266 },
    { name = "Malygos",       id = 26752 },
    { name = "Tuskarr",       id = 24685 },
    { name = "Kel'Thuzad",    id = 15945 },
    { name = "Yogg-Saron",    id = 28817 },
    { name = "Kael'thas",     id = 20023 },
    { name = "Lady Vashj",    id = 20748 },
    { name = "Nefarian",      id = 11380 },
    { name = "Onyxia",        id = 8570  },
    { name = "Arthas",        id = 24949 },
    { name = "Uther",         id = 16929 },
    { name = "Evil Arthas",   id = 22235 },
    { name = "Velen",         id = 23749 },
    { name = "Dark Valkier",  id = 25517 },
    { name = "Penguin",       id = 24698 },
}

-- ============================================================
-- COMBAT PET FAMILY ICONS
-- ============================================================
ns.combatPetFamilyIcons = {
    ["Bear"]          = "Interface\\Icons\\Ability_Hunter_Pet_Bear",
    ["Boar"]          = "Interface\\Icons\\Ability_Hunter_Pet_Boar",
    ["Cat"]           = "Interface\\Icons\\Ability_Hunter_Pet_Cat",
    ["Carrion Bird"]  = "Interface\\Icons\\Ability_Hunter_Pet_Vulture",
    ["Crab"]          = "Interface\\Icons\\Ability_Hunter_Pet_Crab",
    ["Crocolisk"]     = "Interface\\Icons\\Ability_Hunter_Pet_Crocolisk",
    ["Dragonhawk"]    = "Interface\\Icons\\Ability_Hunter_Pet_Dragonhawk",
    ["Gorilla"]       = "Interface\\Icons\\Ability_Hunter_Pet_Gorilla",
    ["Hyena"]         = "Interface\\Icons\\Ability_Hunter_Pet_Hyena",
    ["Moth"]          = "Interface\\Icons\\Ability_Hunter_Pet_Moth",
    ["Nether Ray"]    = "Interface\\Icons\\Ability_Hunter_Pet_NetherRay",
    ["Raptor"]        = "Interface\\Icons\\Ability_Hunter_Pet_Raptor",
    ["Ravager"]       = "Interface\\Icons\\Ability_Hunter_Pet_Ravager",
    ["Scorpid"]       = "Interface\\Icons\\Ability_Hunter_Pet_Scorpid",
    ["Serpent"]        = "Interface\\Icons\\Ability_Hunter_Pet_WindSerpent",
    ["Spider"]        = "Interface\\Icons\\Ability_Hunter_Pet_Spider",
    ["Sporebat"]      = "Interface\\Icons\\Ability_Hunter_Pet_Sporebat",
    ["Tallstrider"]   = "Interface\\Icons\\Ability_Hunter_Pet_Tallstrider",
    ["Turtle"]        = "Interface\\Icons\\Ability_Hunter_Pet_Turtle",
    ["Warp Stalker"]  = "Interface\\Icons\\Ability_Hunter_Pet_WarpStalker",
    ["Wasp"]          = "Interface\\Icons\\Ability_Hunter_Pet_Wasp",
    ["Wolf"]          = "Interface\\Icons\\Ability_Hunter_Pet_Wolf",
    ["Worm"]          = "Interface\\Icons\\Ability_Hunter_Pet_Worm",
    ["Bat"]           = "Interface\\Icons\\Ability_Hunter_Pet_Bat",
    ["Chimaera"]      = "Interface\\Icons\\Ability_Hunter_Pet_Chimera",
    ["Core Hound"]    = "Interface\\Icons\\Ability_Hunter_Pet_CoreHound",
    ["Devilsaur"]     = "Interface\\Icons\\Ability_Hunter_Pet_Devilsaur",
    ["Rhino"]         = "Interface\\Icons\\Ability_Hunter_Pet_Rhino",
    ["Silithid"]      = "Interface\\Icons\\Ability_Hunter_Pet_Silithid",
    ["Demon"]         = "Interface\\Icons\\Spell_Shadow_SummonFelHunter",
    ["Elemental"]     = "Interface\\Icons\\Spell_Frost_SummonWaterElemental_2",
}

-- ============================================================
-- DEFAULT SETTINGS
-- ============================================================
ns.defaultSettings = {
    dressingRoomBackgroundColor = {0.6, 0.6, 0.6, 1},
    previewSetup = "classic",
    showDressMeButton = true,
    useServerTimeInReceivedAppearances = false,
    ignoreUIScaling = false,
    saveMorphState = true,
    saveMountMorph = true,
    savePetMorph = true,
    saveHunterPetMorph = true,
    saveCombatPetMorph = true,
    showMetamorphosis = true,
    showDBWProc = false,
    morphInShapeshift = false,
    worldTime = nil,
    enableWorldSync = true,
    worldFogEnabled = false,
    worldFogColor = "#AAAAAA",
    worldFogStart = 500,
    worldFogEnd = 2500,
    worldFarClipEnabled = false,
    worldFarClip = 2666,
    worldRenderLiquidSurface = true,
    worldRenderLiquidParticles = true,
    worldRenderWireframe = false,
    worldRenderNormals = false,
    worldRenderTerrain = true,
    worldRenderTerrainCulling = true,
    worldRenderM2 = true,
    worldRenderM2WmoShadow = true,
    worldRenderWmo = true,
    worldRenderWmoLighting = true,
    worldRenderFootprints = true,
    worldRenderWmoTextures = true,
    worldRenderWmoPortals = false,
    worldRenderOccluders = false,
    worldRenderM2Fade = true,
    worldRenderGroundClutter = true,
    worldRenderCollision = false,
    worldRenderMountains = true,
    worldRenderSpecularLighting = true,
    worldRenderObjectShadow = true,
    worldRenderSmoothTextures = false,
    worldRenderSmoothTexturesBias = 1.25,
    miscHdFontMode = 0,
    talentLoadoutBindings = {},
    maxVisiblePlayers = 0,
    showMinimapButton = true,
    hidePaperdollButton = false,
    windowWidth = 1045,
    windowHeight = 584,
    -- Distance culling: make far objects "not exist" for FPS (never the local player).
    -- hidePlayersEnabled is the master switch; the rest pick what gets culled.
    hidePlayersEnabled       = false,   -- master
    hidePlayersDistance      = 30,
    hideCatPlayers           = true,    -- other players' bodies
    hideCatPets              = true,    -- their pets / summons / totems / guardians
    hideCatNpcs              = false,   -- all other creatures (max FPS in cities/raids)
    hideCatObjects           = false,   -- game objects + ground AoE effects ("traces")
    hideCatCorpses           = false,   -- corpses
    hideShowGroup            = true,    -- never cull party/raid member character models; pets/summons can still hide
    hideShadows              = false,   -- disable all ground/character shadows (global, FPS)
    hideNameplates           = false,   -- hide ALL nameplates (enemy+friendly, players/NPCs/totems/pets/guardians CVars)
    hideChatBubbles          = false,   -- hide say/yell speech bubbles (chatBubbles CVar)
    hideOtherSounds          = false,   -- mute ONLY other players' sounds (DLL MUTE_PLAYER_SOUNDS; keeps self/NPC/UI/music)
    -- Optimization (Spell Visibility)
    hideOtherSwing           = false,   -- hide other players' attack ANIMATION/swing (DLL SC_SWING)
    hideAllSpells            = false,
    showOwnSpells            = false,
    hidePrecast              = false,
    hideCast                 = false,
    hideChannel              = false,
    hideAuraStart            = false,
    hideAuraEnd              = false,
    hideImpact               = false,
    hideImpactCaster         = false,
    hideTargetImpact         = false,
    hideAreaInstant          = false,
    hideAreaImpact           = false,
    hideAreaPersistent       = false,
    hideMissile              = false,
    hideMissileMarker        = false,
    hideSoundMissile         = false,
    hideSoundEvent           = false,
    protectTierT10           = false,
    protectTierT9            = false,
    protectTierT8            = false,
    protectTierT7            = false,
    protectTierVOA           = false,
    whiteCardSpells          = {},
    -- Per-character skin (donor item id + tint) keyed by slot name. Set by
    -- the Skin sub-tab and read by loadouts / character-select doll / C++
    -- persistent state. Mirrored to the DLL via ITEM_SKIN_PERSIST.
    slotRecolor              = {},
}

ns.optimizationTierOptions = {
    { key = "T10", settingKey = "protectTierT10", label = "T10", raids = "ICC + RS" },
    { key = "T9",  settingKey = "protectTierT9",  label = "T9",  raids = "TOC + Onyxia" },
    { key = "T8",  settingKey = "protectTierT8",  label = "T8",  raids = "Ulduar" },
    { key = "T7",  settingKey = "protectTierT7",  label = "T7",  raids = "OS + Naxx + EoE" },
    { key = "VOA", settingKey = "protectTierVOA", label = "VOA", raids = "Vault of Archavon" },
}

-- ============================================================
-- DEATHBRINGER'S WILL PROC IDs
-- ============================================================
ns.dbwProcIds = {
    [71484] = true, [71561] = true,
    [71486] = true, [71558] = true,
    [71485] = true, [71556] = true,
    [71492] = true, [71560] = true,
    [71491] = true, [71559] = true,
    [71487] = true, [71557] = true,
}

-- ============================================================
-- TAB CONFIGURATION
-- ============================================================
ns.tabConfig = {
    { key = "preview",    label = "Preview",     icon = "Interface\\Icons\\INV_Chest_Cloth_17" },
    { key = "appearances",label = "Loadouts",    icon = "Interface\\Icons\\INV_Misc_Book_11" },
    { key = "mounts",     label = "Mounts",      icon = "Interface\\Icons\\Ability_Mount_RidingHorse" },
    { key = "pets",       label = "Pets",         icon = "Interface\\Icons\\INV_Box_PetCarrier_01" },
    { key = "combatPets", label = "CPets",        icon = "Interface\\Icons\\Ability_Hunter_BeastCall" },
    { key = "morph",      label = "Morph",        icon = "Interface\\Icons\\Spell_Shadow_Charm" },
    { key = "color",      label = "Color",        icon = "Interface\\Icons\\INV_Misc_Gem_Pearl_06" },
    { key = "env",        label = "Misc",         icon = "Interface\\Icons\\Spell_Nature_EarthBind" },
    { key = "settings",   label = "Settings",     icon = "Interface\\Icons\\INV_Misc_Gear_01" },
}

-- ============================================================
-- BACKDROP TEMPLATES
-- ============================================================
ns.Backdrops = {
    panel = {
        bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 16,
        insets = { left = 3, right = 3, top = 3, bottom = 3 },
    },
    panelSmall = {
        bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 12,
        insets = { left = 3, right = 3, top = 3, bottom = 3 },
    },
    button = {
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 12,
        insets = { left = 2, right = 2, top = 2, bottom = 2 },
    },
    dressingRoom = {
        bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
        edgeFile = "Interface\\AddOns\\Transmorpher\\images\\mirror-border",
        tile = false, tileSize = 16, edgeSize = 32,
        insets = { left = 4, right = 4, top = 4, bottom = 4 },
    },
}

-- ============================================================
-- VEHICLE DETECTION KEYWORDS
-- ============================================================
ns.vehicleKeywords = {
    "Chopper", "Salvaged", "Demolisher", "Siege", "Engine", "Cannon", "Canon", "Harpoon",
    "Turret", "Teleporter", "Drake", "Dragon", "Tank", "Golem", "Robot", "Machine",
    "Plane", "Ship", "Boat", "Zeppelin", "Bomber", "Steam", "Flame",
    "Leviathan", "Mimiron", "Gryphon", "Wyvern", "Bat", "Hawkstrider", "Catapult",
    "Car", "Shuttle", "Submarine", "Valkyrie", "Mammoth", "Motor", "Bike", "Cycle",
    "Rider", "Pilot", "Gunner", "Azure", "Amber", "Emerald", "Scion", "Proto-Drake",
    "Aerial", "Command", "Platform", "Guardian", "Sentinel", "Constructor",
    "Mechano", "Turbo", "Automatic", "Flying", "Hover", "Glider", "Sled", "Rocket",
    "Blimp", "Balloon", "Gnome", "Goblin", "Experimental", "Security",
    "Defense", "Assault", "War", "Combat", "Battle", "Transport", "Portal",
    "Focus", "Nexus", "Pulse", "Energy", "Beam", "Static", "Launcher", "Ram",
    "Stabled Thunder Bluff Kodo", "Stabled Darkspear Raptor", "Stabled Forsaken Warhorse",
    "Stabled Orgrimmar Wolf", "Stabled Silvermoon Hawkstrider", "Stabled Sunreaver Hawkstrider",
    "Stabled Argent Warhorse",
}

-- ============================================================
-- DESIGN SYSTEM — SPACING, THEME, ASSETS  (Phase 1 UI overhaul)
-- Centralized spacing scale, named backdrop templates, and a single
-- registry of every addon texture path. These are ADDITIVE: existing
-- ns.Backdrops / ns.Dimensions / hard-coded textures are untouched.
-- All factories in UI\Theme.lua read from here.
-- ============================================================

-- 4px base spacing scale. Use these instead of magic offsets so padding
-- is consistent across panels.
ns.Spacing = {
    none  = 0,
    xs    = 2,
    sm    = 4,
    md    = 6,
    lg    = 8,
    xl    = 12,
    xxl   = 16,
    panel = 10,   -- standard inner padding for scrollform panels
    list  = 6,    -- standard gap around list wells
}

-- Standard control heights. Tab heights etc. live in ns.Dimensions.
ns.Heights = {
    row        = 28,   -- standard list row (Mounts/Pets/CPets)
    rowCompact = 20,   -- dropdown / search-result rows
    search     = 26,   -- search field
    chip       = 18,   -- filter chip
    button     = 26,   -- standard golden button
    sectionGap = 14,   -- vertical gap between sections
}

-- Single registry of addon texture paths. NEVER inline these strings in
-- factory code — reference ns.Assets.* so a path only ever lives in one place.
ns.Assets = {
    -- Procedural fill / 1px line textures shipped with the WoW client.
    bgSolid      = "Interface\\ChatFrame\\ChatFrameBackground",
    white        = "Interface\\Buttons\\WHITE8X8",
    whiteLo      = "Interface\\Buttons\\WHITE8x8", -- casing used elsewhere in the codebase

    -- Addon-provided item tiles (retail wardrobe feel). Three states.
    tileNormal   = "Interface\\AddOns\\Transmorpher\\Textures\\item_bg_normal",
    tileHover    = "Interface\\AddOns\\Transmorpher\\Textures\\item_bg_highlight",
    tileSelected = "Interface\\AddOns\\Transmorpher\\Textures\\item_bg_selected",

    -- Tab chrome.
    tabActive    = "Interface\\AddOns\\Transmorpher\\Textures\\tab_active",
    tabInactive  = "Interface\\AddOns\\Transmorpher\\Textures\\tab_inactive",

    -- Decorative borders.
    borderFull   = "Interface\\AddOns\\Transmorpher\\Textures\\border_full",
    borderHi     = "Interface\\AddOns\\Transmorpher\\Textures\\border_highlight",
    border2      = "Interface\\AddOns\\Transmorpher\\Textures\\border_2",
    mirrorBorder = "Interface\\AddOns\\Transmorpher\\images\\mirror-border",
    transmogBorder = "Interface\\AddOns\\Transmorpher\\Textures\\transmog_border",

    -- Search / clear icons (addon-provided, sharper than the client ones).
    searchIcon   = "Interface\\AddOns\\Transmorpher\\Textures\\ui-searchbox-icon",
    searchClear  = "Interface\\AddOns\\Transmorpher\\Textures\\UI-SearchBox-Clear",

    -- Client-side helpers reused by the theme.
    highlightBand = "Interface\\QuestFrame\\UI-QuestTitleHighlight",
    buttonHilight = "Interface\\Buttons\\ButtonHilight-Square",
    checkBoxCheck = "Interface\\Buttons\\UI-CheckBox-Check",
}

-- Named backdrop templates. ns.Backdrops above stays as-is for back-compat;
-- ns.Theme is the new canonical set consumed by the Theme factories.
ns.Theme = {
    -- Solid dark fill with a 1px gold hairline border. The default for cards,
    -- wells, headers, search fields. edgeSize=1 keeps it crisp at any DPI.
    panel = {
        bgFile = ns.Assets.bgSolid,
        edgeFile = ns.Assets.white,
        tile = false, tileSize = 0, edgeSize = 1,
        insets = { left = 1, right = 1, top = 1, bottom = 1 },
    },
    -- Inset well — darker fill, same hairline. Used behind list contents.
    well = {
        bgFile = ns.Assets.bgSolid,
        edgeFile = ns.Assets.white,
        tile = false, tileSize = 0, edgeSize = 1,
        insets = { left = 1, right = 1, top = 1, bottom = 1 },
    },
    -- Tooltip-style golden border for prominent frames (selector dialogs etc.).
    gilded = {
        bgFile = ns.Assets.bgSolid,
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 12,
        insets = { left = 3, right = 3, top = 3, bottom = 3 },
    },
    -- Flat solid button: 1px gold border, fill supplied by the caller.
    buttonFlat = {
        bgFile = ns.Assets.white,
        edgeFile = ns.Assets.white,
        tile = false, tileSize = 0, edgeSize = 1,
        insets = { left = 1, right = 1, top = 1, bottom = 1 },
    },
    -- Borderless inset for search/edit fields (border drawn as a texture so we
    -- can animate its color via the smooth-hover system without SetBackdrop).
    input = {
        bgFile = ns.Assets.bgSolid,
        tile = false, tileSize = 0, edgeSize = 0,
        insets = { left = 0, right = 0, top = 0, bottom = 0 },
    },
}

-- Named font styles. Returns nothing at load time; callers pass these strings
-- to SetFont(). Centralized so font tuning lives in one place.
ns.Fonts = {
    title       = { "Fonts\\FRIZQT__.TTF", 16, "OUTLINE" },
    sectionHead = { "Fonts\\FRIZQT__.TTF", 13, "OUTLINE" },
    body        = { "Fonts\\FRIZQT__.TTF", 12 },
    bodySmall   = { "Fonts\\FRIZQT__.TTF", 11 },
    bodyTiny    = { "Fonts\\FRIZQT__.TTF", 10 },
    input       = { "Fonts\\FRIZQT__.TTF", 11 },
}
