local addon, ns = ...

local mainFrameTitle = "|cffF5C842Transmorpher|r  |cff6a6050v1.1.0|r"

-- ============================================================
-- CUSTOM GOLDEN BUTTON STYLE
-- ============================================================
local function CreateGoldenButton(name, parent)
    local btn = CreateFrame("Button", name, parent)
    btn:SetNormalFontObject("GameFontNormal")
    btn:SetHighlightFontObject("GameFontHighlight")
    btn:SetDisabledFontObject("GameFontDisable")
    
    -- Normal texture (golden gradient)
    local normalTex = btn:CreateTexture(nil, "BACKGROUND")
    normalTex:SetAllPoints()
    normalTex:SetTexture("Interface\\ChatFrame\\ChatFrameBackground")
    normalTex:SetGradientAlpha("VERTICAL", 0.25, 0.18, 0.08, 1.0, 0.18, 0.12, 0.05, 1.0)
    btn:SetNormalTexture(normalTex)
    
    -- Highlight texture (brighter golden)
    local highlightTex = btn:CreateTexture(nil, "HIGHLIGHT")
    highlightTex:SetAllPoints()
    highlightTex:SetTexture("Interface\\ChatFrame\\ChatFrameBackground")
    highlightTex:SetGradientAlpha("VERTICAL", 0.35, 0.25, 0.12, 1.0, 0.28, 0.20, 0.08, 1.0)
    highlightTex:SetBlendMode("ADD")
    
    -- Pushed texture (darker)
    local pushedTex = btn:CreateTexture(nil, "ARTWORK")
    pushedTex:SetAllPoints()
    pushedTex:SetTexture("Interface\\ChatFrame\\ChatFrameBackground")
    pushedTex:SetGradientAlpha("VERTICAL", 0.12, 0.08, 0.03, 1.0, 0.08, 0.05, 0.02, 1.0)
    btn:SetPushedTexture(pushedTex)
    
    -- Disabled texture (gray)
    local disabledTex = btn:CreateTexture(nil, "ARTWORK")
    disabledTex:SetAllPoints()
    disabledTex:SetTexture("Interface\\ChatFrame\\ChatFrameBackground")
    disabledTex:SetVertexColor(0.15, 0.15, 0.15, 0.8)
    btn:SetDisabledTexture(disabledTex)
    
    -- Golden border
    btn:SetBackdrop({
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 12,
        insets = { left = 2, right = 2, top = 2, bottom = 2 }
    })
    btn:SetBackdropBorderColor(0.80, 0.65, 0.22, 1.0)
    
    -- Hover effect
    btn:SetScript("OnEnter", function(self)
        self:SetBackdropBorderColor(1.0, 0.82, 0.20, 1.0)
    end)
    btn:SetScript("OnLeave", function(self)
        self:SetBackdropBorderColor(0.80, 0.65, 0.22, 1.0)
    end)
    
    return btn
end

local sex = UnitSex("player")
local _, raceFileName = UnitRace("player")
local _, classFileName = UnitClass("player")

local previewSetupVersion = "classic"

local armorSlots = {"Head", "Shoulder", "Chest", "Wrist", "Hands", "Waist", "Legs", "Feet"}
local backSlot = "Back"
local miscellaneousSlots = {"Tabard", "Shirt"}
local mainHandSlot = "Main Hand"
local offHandSlot = "Off-hand"
local rangedSlot = "Ranged"

local chestSlots = {"Chest", "Tabard", "Shirt"}

local addonMessagePrefix = "Transmorpher"
local slotOrder = { "Head", "Shoulder", "Back", "Chest", "Shirt", "Tabard", "Wrist", "Hands", "Waist", "Legs", "Feet", "Main Hand", "Off-hand", "Ranged",}
local enchantSlotNames = { "Enchant MH", "Enchant OH" }

-- WoW equipment slot IDs for DLL morph calls
local slotToEquipSlotId = {
    ["Head"] = 1, ["Shoulder"] = 3, ["Back"] = 15, ["Chest"] = 5,
    ["Shirt"] = 4, ["Tabard"] = 19, ["Wrist"] = 9, ["Hands"] = 10,
    ["Waist"] = 6, ["Legs"] = 7, ["Feet"] = 8,
    ["Main Hand"] = 16, ["Off-hand"] = 17, ["Ranged"] = 18,
}

-- Reverse mapping: equipment slot ID -> slot name (for restoring UI from saved state)
local equipSlotIdToSlot = {}
for name, id in pairs(slotToEquipSlotId) do equipSlotIdToSlot[id] = name end

-- Forward-declare mainFrame so early functions (RestoreMorphedUI, SyncDressingRoom) can reference it.
local mainFrame
-- Forward-declare glow functions so RestoreMorphedUI (defined before the glow system) can capture them.
local ShowMorphGlow, HideMorphGlow
-- Forward-declare UpdatePreviewModel so special slots can use it
local UpdatePreviewModel

local slotTextures = {
    ["Head"] =      "Interface\\Paperdoll\\ui-paperdoll-slot-head",
    ["Shoulder"] =  "Interface\\Paperdoll\\ui-paperdoll-slot-shoulder",
    ["Back"] =      "Interface\\Paperdoll\\ui-paperdoll-slot-chest",
    ["Chest"] =     "Interface\\Paperdoll\\ui-paperdoll-slot-chest",
    ["Shirt"] =     "Interface\\Paperdoll\\ui-paperdoll-slot-shirt",
    ["Tabard"] =    "Interface\\Paperdoll\\ui-paperdoll-slot-tabard",
    ["Wrist"] =     "Interface\\Paperdoll\\ui-paperdoll-slot-wrists",
    ["Hands"] =     "Interface\\Paperdoll\\ui-paperdoll-slot-hands",
    ["Waist"] =     "Interface\\Paperdoll\\ui-paperdoll-slot-waist",
    ["Legs"] =      "Interface\\Paperdoll\\ui-paperdoll-slot-legs",
    ["Feet"] =      "Interface\\Paperdoll\\ui-paperdoll-slot-feet",
    ["Main Hand"] = "Interface\\Paperdoll\\ui-paperdoll-slot-mainhand",
    ["Off-hand"] =  "Interface\\Paperdoll\\ui-paperdoll-slot-secondaryhand",
    ["Ranged"] =    "Interface\\Paperdoll\\ui-paperdoll-slot-ranged",
}

local slotSubclasses = {}

do
    for i, slot in ipairs(armorSlots) do slotSubclasses[slot] = {"Cloth", "Leather", "Mail", "Plate"} end
    for i, slot in ipairs(miscellaneousSlots) do slotSubclasses[slot] = {"Miscellaneous", } end
    slotSubclasses[backSlot] = {"Cloth", }
    -- All weapon types available in all weapon slots (fully unrestricted)
    -- GetSubclassRecords has cross-slot fallback so items from any slot are found
    local allMeleeTypes = {
        "1H Axe", "1H Mace", "1H Sword", "1H Dagger", "1H Fist",
        "MH Axe", "MH Mace", "MH Sword", "MH Dagger", "MH Fist",
        "OH Axe", "OH Mace", "OH Sword", "OH Dagger", "OH Fist",
        "2H Axe", "2H Mace", "2H Sword", "Polearm", "Staff",
        "Shield", "Held in Off-hand",
        "Bow", "Crossbow", "Gun", "Wand", "Thrown",
    }
    slotSubclasses[mainHandSlot] = allMeleeTypes
    slotSubclasses[offHandSlot]  = allMeleeTypes
    slotSubclasses[rangedSlot]   = allMeleeTypes
end

local defaultSlot = "Head"

local defaultArmorSubclass = {
    ["MAGE"] = "Cloth", ["PRIEST"] = "Cloth", ["WARLOCK"] = "Cloth",
    ["DRUID"] = "Leather", ["ROGUE"] = "Leather",
    ["HUNTER"] = "Mail", ["SHAMAN"] = "Mail",
    ["PALADIN"] = "Plate", ["WARRIOR"] = "Plate", ["DEATHKNIGHT"] = "Plate"
}

local defaultSettings = {
    dressingRoomBackgroundColor = {0.6, 0.6, 0.6, 1},
    dressingRoomBackgroundTexture = {
        [GetRealmName()] = {
            [GetUnitName("player")] = classFileName == "DEATHKNIGHT" and classFileName or raceFileName,
        },
    },
    previewSetup = "classic",
    showDressMeButton = true,
    useServerTimeInReceivedAppearances = false,
    ignoreUIScaling = false,
    saveMorphState = true,
    saveMountMorph = true,
    savePetMorph = true,
    saveHunterPetMorph = true,
    saveCombatPetMorph = true,
    showDBWProc = true,
    morphInShapeshift = false,
}

local function GetSettings()
    local function copyTable(tableFrom)
        local result = {}
        for k, v in pairs(tableFrom) do
            if type(v) == "table" then result[k] = copyTable(v)
            else result[k] = v end
        end
        return result
    end
    if _G["TransmorpherSettings"] == nil then
        _G["TransmorpherSettings"] = copyTable(defaultSettings)
    else
        for k, v in pairs(defaultSettings) do
            if _G["TransmorpherSettings"][k] == nil then
                _G["TransmorpherSettings"][k] = type(v) == "table" and copyTable(v) or v
            end
        end
        if _G["TransmorpherSettings"].dressingRoomBackgroundTexture[GetRealmName()] == nil then
            _G["TransmorpherSettings"].dressingRoomBackgroundTexture[GetRealmName()] = {}
        end
        if _G["TransmorpherSettings"].dressingRoomBackgroundTexture[GetRealmName()][GetUnitName("player")] == nil then
            _G["TransmorpherSettings"].dressingRoomBackgroundTexture[GetRealmName()][GetUnitName("player")] = defaultSettings.dressingRoomBackgroundTexture[GetRealmName()][GetUnitName("player")]
        end
    end
    return _G["TransmorpherSettings"]
end

local function arrayHasValue(array, value)
    for i, v in ipairs(array) do
        if v == value then return true end
    end
    return false
end

---------------- MORPHER BRIDGE (STEALTH MODE) ----------------
-- Commands are sent via a global Lua variable that the C++ DLL
-- reads every 20ms. The DLL handles automatic morph persistence
-- via its MorphGuard system — no Lua-side burst loops needed.

TRANSMORPHER_CMD = ""  -- Global variable the DLL reads
TRANSMORPHER_DLL_LOADED = false  -- Global variable the DLL sets when loaded

-- Track whether the DLL has been told to suspend (model-changing form active)
local morphSuspended = false
local vehicleSuspended = false
local savedMountDisplayForVehicle = nil

-- Vehicle guard: track last known vehicle state for OnUpdate polling
local wasInVehicleLastFrame = false

local function IsModelChangingForm()
    -- If user wants morph to persist in shapeshift forms, never suspend
    if GetSettings().morphInShapeshift then return false end

    local form = GetShapeshiftForm()
    if form == 0 then return false end
    
    -- Only druid forms change the character model in a way that conflicts
    -- with display morphs.  Shaman Ghost Wolf and Warlock Metamorphosis
    -- are treated as normal display overrides — the morph display will
    -- persist through them so e.g. a morphed-to-orc player stays orc.
    if classFileName == "DRUID" then
        return true -- All druid forms (Bear, Cat, Travel, Moonkin, Tree, Aquatic)
    end
    
    return false
end

local function IsInVehicle()
    -- Check if player is in a vehicle (cannons, siege engines, etc.)
    return UnitInVehicle("player")
end

-- Deathbringer's Will proc spell IDs (Normal + Heroic)
-- These procs transform the player model; we suspend morph to show the proc form
local dbwProcIds = {
    [71484] = true, -- Strength of the Taunka (N)
    [71561] = true, -- Strength of the Taunka (H)
    [71486] = true, -- Power of the Taunka (N)
    [71558] = true, -- Power of the Taunka (H)
    [71485] = true, -- Agility of the Vrykul (N)
    [71556] = true, -- Agility of the Vrykul (H)
    [71492] = true, -- Speed of the Vrykul (N)
    [71560] = true, -- Speed of the Vrykul (H)
    [71491] = true, -- Aim of the Iron Dwarves (N)
    [71559] = true, -- Aim of the Iron Dwarves (H)
    [71487] = true, -- Precision of the Iron Dwarves (N)
    [71557] = true, -- Precision of the Iron Dwarves (H)
}

local dbwSuspended = false

local function HasDBWProc()
    for i = 1, 40 do
        local _, _, _, _, _, _, _, _, _, _, spellId = UnitBuff("player", i)
        if not spellId then break end
        if dbwProcIds[spellId] then return true end
    end
    return false
end

-- ============================================================
-- WEAPON SET SYSTEM - Save different morphs per weapon config
-- ============================================================
local function TrackMorphCommand(cmd)
    if not GetSettings().saveMorphState then return end
    if not TransmorpherCharacterState then TransmorpherCharacterState = {Items={}, Morph=nil, Scale=nil, MountDisplay=nil, PetDisplay=nil, HunterPetDisplay=nil, HunterPetScale=nil, EnchantMH=nil, EnchantOH=nil} end
    if not TransmorpherCharacterState.Items then TransmorpherCharacterState.Items = {} end

    for singleCmd in cmd:gmatch("[^|]+") do
        local parts = {strsplit(":", singleCmd)}
        local prefix = parts[1]
        
        if prefix == "ITEM" and parts[2] and parts[3] then
            local slotId = tonumber(parts[2])
            local itemId = tonumber(parts[3])
            TransmorpherCharacterState.Items[slotId] = itemId
        elseif prefix == "MORPH" and parts[2] then
            local val = tonumber(parts[2])
            if val and val > 0 then
                TransmorpherCharacterState.Morph = val
            else
                -- MORPH:0 means reset character morph only (not items)
                TransmorpherCharacterState.Morph = nil
            end
        elseif prefix == "SCALE" and parts[2] then
            TransmorpherCharacterState.Scale = tonumber(parts[2])
        elseif prefix == "MOUNT_MORPH" and parts[2] then
            if GetSettings().saveMountMorph then
                TransmorpherCharacterState.MountDisplay = tonumber(parts[2])
            end
        elseif prefix == "MOUNT_RESET" then
            TransmorpherCharacterState.MountDisplay = nil
        elseif prefix == "PET_MORPH" and parts[2] then
            if GetSettings().savePetMorph then
                TransmorpherCharacterState.PetDisplay = tonumber(parts[2])
            end
        elseif prefix == "PET_RESET" then
            TransmorpherCharacterState.PetDisplay = nil
        elseif prefix == "HPET_MORPH" and parts[2] then
            if GetSettings().saveCombatPetMorph or GetSettings().saveHunterPetMorph then
                TransmorpherCharacterState.HunterPetDisplay = tonumber(parts[2])
            end
        elseif prefix == "HPET_SCALE" and parts[2] then
            if GetSettings().saveCombatPetMorph or GetSettings().saveHunterPetMorph then
                TransmorpherCharacterState.HunterPetScale = tonumber(parts[2])
            end
        elseif prefix == "HPET_RESET" then
            TransmorpherCharacterState.HunterPetDisplay = nil
            TransmorpherCharacterState.HunterPetScale = nil
        elseif prefix == "ENCHANT_MH" and parts[2] then
            local val = tonumber(parts[2])
            if val and val > 0 then
                TransmorpherCharacterState.EnchantMH = val
            end
        elseif prefix == "ENCHANT_OH" and parts[2] then
            local val = tonumber(parts[2])
            if val and val > 0 then
                TransmorpherCharacterState.EnchantOH = val
            end
        elseif prefix == "ENCHANT_RESET_MH" then
            TransmorpherCharacterState.EnchantMH = nil
        elseif prefix == "ENCHANT_RESET_OH" then
            TransmorpherCharacterState.EnchantOH = nil
        elseif prefix == "ENCHANT_RESET" then
            TransmorpherCharacterState.EnchantMH = nil
            TransmorpherCharacterState.EnchantOH = nil
        elseif prefix == "RESET" and parts[2] then
            if parts[2] == "ALL" then
                TransmorpherCharacterState = {Items={}, Morph=nil, Scale=nil, MountDisplay=nil, PetDisplay=nil, HunterPetDisplay=nil, HunterPetScale=nil, EnchantMH=nil, EnchantOH=nil, WeaponSets={}}
            else
                local slotId = tonumber(parts[2])
                TransmorpherCharacterState.Items[slotId] = nil
                -- Clear from weapon set if it's a weapon slot
                if slotId == 16 or slotId == 17 then
                    local setKey = GetWeaponSetKey()
                    if TransmorpherCharacterState.WeaponSets[setKey] then
                        TransmorpherCharacterState.WeaponSets[setKey][slotId] = nil
                    end
                end
            end
        end
    end
end

local function SendMorphCommand(cmd)
    TrackMorphCommand(cmd)
    if TRANSMORPHER_CMD == "" then
        TRANSMORPHER_CMD = cmd
    else
        TRANSMORPHER_CMD = TRANSMORPHER_CMD .. "|" .. cmd
    end
end

-- Send a raw signal to the DLL (SUSPEND/RESUME) without tracking state
local function SendRawMorphCommand(cmd)
    if TRANSMORPHER_CMD == "" then
        TRANSMORPHER_CMD = cmd
    else
        TRANSMORPHER_CMD = TRANSMORPHER_CMD .. "|" .. cmd
    end
end

-- ================================================================
-- Creature ID lookup tables for textured 3D model preview
-- ================================================================
-- ================================================================
-- Icon helper — returns a spell icon texture path for a given spellID.
-- Falls back to a generic question-mark icon if the spell is unknown.
-- ================================================================
local FALLBACK_ICON = "Interface\\Icons\\INV_Misc_QuestionMark"
local function GetSpellIcon(spellID)
    if spellID and spellID > 0 then
        local _, _, icon = GetSpellInfo(spellID)
        if icon then return icon end
    end
    return FALLBACK_ICON
end

-- ================================================================
-- Icon helper for combat pets — returns icon based on family name
-- ================================================================
local combatPetFamilyIcons = {
    ["Bear"] = "Interface\\Icons\\Ability_Hunter_Pet_Bear",
    ["Boar"] = "Interface\\Icons\\Ability_Hunter_Pet_Boar",
    ["Cat"] = "Interface\\Icons\\Ability_Hunter_Pet_Cat",
    ["Carrion Bird"] = "Interface\\Icons\\Ability_Hunter_Pet_Vulture",
    ["Crab"] = "Interface\\Icons\\Ability_Hunter_Pet_Crab",
    ["Crocolisk"] = "Interface\\Icons\\Ability_Hunter_Pet_Crocolisk",
    ["Dragonhawk"] = "Interface\\Icons\\Ability_Hunter_Pet_Dragonhawk",
    ["Gorilla"] = "Interface\\Icons\\Ability_Hunter_Pet_Gorilla",
    ["Hyena"] = "Interface\\Icons\\Ability_Hunter_Pet_Hyena",
    ["Moth"] = "Interface\\Icons\\Ability_Hunter_Pet_Moth",
    ["Nether Ray"] = "Interface\\Icons\\Ability_Hunter_Pet_NetherRay",
    ["Raptor"] = "Interface\\Icons\\Ability_Hunter_Pet_Raptor",
    ["Ravager"] = "Interface\\Icons\\Ability_Hunter_Pet_Ravager",
    ["Scorpid"] = "Interface\\Icons\\Ability_Hunter_Pet_Scorpid",
    ["Serpent"] = "Interface\\Icons\\Ability_Hunter_Pet_WindSerpent",
    ["Spider"] = "Interface\\Icons\\Ability_Hunter_Pet_Spider",
    ["Sporebat"] = "Interface\\Icons\\Ability_Hunter_Pet_Sporebat",
    ["Tallstrider"] = "Interface\\Icons\\Ability_Hunter_Pet_Tallstrider",
    ["Turtle"] = "Interface\\Icons\\Ability_Hunter_Pet_Turtle",
    ["Warp Stalker"] = "Interface\\Icons\\Ability_Hunter_Pet_WarpStalker",
    ["Wasp"] = "Interface\\Icons\\Ability_Hunter_Pet_Wasp",
    ["Wolf"] = "Interface\\Icons\\Ability_Hunter_Pet_Wolf",
    ["Worm"] = "Interface\\Icons\\Ability_Hunter_Pet_Worm",
    ["Bat"] = "Interface\\Icons\\Ability_Hunter_Pet_Bat",
    ["Chimaera"] = "Interface\\Icons\\Ability_Hunter_Pet_Chimera",
    ["Core Hound"] = "Interface\\Icons\\Ability_Hunter_Pet_CoreHound",
    ["Devilsaur"] = "Interface\\Icons\\Ability_Hunter_Pet_Devilsaur",
    ["Rhino"] = "Interface\\Icons\\Ability_Hunter_Pet_Rhino",
    ["Silithid"] = "Interface\\Icons\\Ability_Hunter_Pet_Silithid",
    ["Demon"] = "Interface\\Icons\\Spell_Shadow_SummonFelHunter",
    ["Elemental"] = "Interface\\Icons\\Spell_Frost_SummonWaterElemental_2",
}

local function GetCombatPetIcon(familyName)
    return combatPetFamilyIcons[familyName] or "Interface\\Icons\\Ability_Hunter_BeastCall"
end

-- ================================================================
-- Update special slots (Mount, Pet, Combat Pet) with current morph state
-- ================================================================
local function UpdateSpecialSlots()
    if not mainFrame or not mainFrame.specialSlots then return end
    
    -- Mount slot
    if mainFrame.specialSlots.Mount then
        local mountSlot = mainFrame.specialSlots.Mount
        if TransmorpherCharacterState and TransmorpherCharacterState.MountDisplay then
            local mountEntry = nil
            for _, entry in ipairs(ns.mountsDB) do
                if entry[3] == TransmorpherCharacterState.MountDisplay then
                    mountEntry = entry
                    break
                end
            end
            if mountEntry then
                mountSlot.displayID = mountEntry[3]
                mountSlot.spellID = mountEntry[2]
                mountSlot.name = mountEntry[1]
                mountSlot.icon:SetTexture(GetSpellIcon(mountEntry[2]))
                mountSlot.icon:Show()
                ShowMorphGlow(mountSlot, "red")
            else
                mountSlot.displayID = nil
                mountSlot.spellID = nil
                mountSlot.name = nil
                mountSlot.icon:Hide()
                HideMorphGlow(mountSlot)
            end
        else
            mountSlot.displayID = nil
            mountSlot.spellID = nil
            mountSlot.name = nil
            mountSlot.icon:Hide()
            HideMorphGlow(mountSlot)
        end
    end
    
    -- Pet slot
    if mainFrame.specialSlots.Pet then
        local petSlot = mainFrame.specialSlots.Pet
        if TransmorpherCharacterState and TransmorpherCharacterState.PetDisplay then
            local petEntry = nil
            for _, entry in ipairs(ns.petsDB) do
                if entry[3] == TransmorpherCharacterState.PetDisplay then
                    petEntry = entry
                    break
                end
            end
            if petEntry then
                petSlot.displayID = petEntry[3]
                petSlot.spellID = petEntry[2]
                petSlot.name = petEntry[1]
                petSlot.icon:SetTexture(GetSpellIcon(petEntry[2]))
                petSlot.icon:Show()
                ShowMorphGlow(petSlot, "red")
            else
                petSlot.displayID = nil
                petSlot.spellID = nil
                petSlot.name = nil
                petSlot.icon:Hide()
                HideMorphGlow(petSlot)
            end
        else
            petSlot.displayID = nil
            petSlot.spellID = nil
            petSlot.name = nil
            petSlot.icon:Hide()
            HideMorphGlow(petSlot)
        end
    end
    
    -- Combat Pet slot
    if mainFrame.specialSlots.CombatPet then
        local combatPetSlot = mainFrame.specialSlots.CombatPet
        if TransmorpherCharacterState and TransmorpherCharacterState.HunterPetDisplay then
            local combatPetEntry = nil
            for _, entry in ipairs(ns.combatPetsDB) do
                if entry[3] == TransmorpherCharacterState.HunterPetDisplay then
                    combatPetEntry = entry
                    break
                end
            end
            -- Show icon and glow even if not found in database (for custom display IDs)
            combatPetSlot.displayID = TransmorpherCharacterState.HunterPetDisplay
            combatPetSlot.name = combatPetEntry and combatPetEntry[1] or ("Display ID: " .. TransmorpherCharacterState.HunterPetDisplay)
            -- Use family-specific icon if found, otherwise generic
            local iconPath = combatPetEntry and GetCombatPetIcon(combatPetEntry[2]) or "Interface\\Icons\\Ability_Hunter_BeastCall"
            combatPetSlot.icon:SetTexture(iconPath)
            combatPetSlot.icon:Show()
            ShowMorphGlow(combatPetSlot, "red")
        else
            combatPetSlot.displayID = nil
            combatPetSlot.name = nil
            combatPetSlot.icon:Hide()
            HideMorphGlow(combatPetSlot)
        end
    end
    
    -- Morph Form slot
    if mainFrame.specialSlots.MorphForm then
        local morphFormSlot = mainFrame.specialSlots.MorphForm
        if TransmorpherCharacterState and TransmorpherCharacterState.Morph then
            -- Find the morph entry in the database
            local morphEntry = nil
            if ns.creatureDisplayDB then
                local displayID = TransmorpherCharacterState.Morph
                local name = ns.creatureDisplayDB[displayID]
                if name then
                    morphEntry = { did = displayID, name = name }
                end
            end
            
            morphFormSlot.displayID = TransmorpherCharacterState.Morph
            morphFormSlot.name = morphEntry and morphEntry.name or ("Display ID: " .. TransmorpherCharacterState.Morph)
            
            -- Try to get race icon if it's a race morph, otherwise use purple charm/morph icon
            local iconPath = "Interface\\Icons\\Spell_Shadow_Charm"
            if morphEntry and morphEntry.name then
                -- Check if it's a race morph and use appropriate icon
                local nameLower = morphEntry.name:lower()
                if nameLower:find("human") then
                    iconPath = "Interface\\Icons\\Achievement_Character_Human_Male"
                elseif nameLower:find("orc") then
                    iconPath = "Interface\\Icons\\Achievement_Character_Orc_Male"
                elseif nameLower:find("dwarf") then
                    iconPath = "Interface\\Icons\\Achievement_Character_Dwarf_Male"
                elseif nameLower:find("night elf") or nameLower:find("nightelf") then
                    iconPath = "Interface\\Icons\\Achievement_Character_Nightelf_Male"
                elseif nameLower:find("scourge") or nameLower:find("undead") then
                    iconPath = "Interface\\Icons\\Achievement_Character_Undead_Male"
                elseif nameLower:find("tauren") then
                    iconPath = "Interface\\Icons\\Achievement_Character_Tauren_Male"
                elseif nameLower:find("gnome") then
                    iconPath = "Interface\\Icons\\Achievement_Character_Gnome_Male"
                elseif nameLower:find("troll") then
                    iconPath = "Interface\\Icons\\Achievement_Character_Troll_Male"
                elseif nameLower:find("blood elf") or nameLower:find("bloodelf") then
                    iconPath = "Interface\\Icons\\Achievement_Character_Bloodelf_Male"
                elseif nameLower:find("draenei") then
                    iconPath = "Interface\\Icons\\Achievement_Character_Draenei_Male"
                end
            end
            
            morphFormSlot.icon:SetTexture(iconPath)
            morphFormSlot.icon:Show()
            ShowMorphGlow(morphFormSlot, "purple")
        else
            morphFormSlot.displayID = nil
            morphFormSlot.name = nil
            morphFormSlot.icon:Hide()
            HideMorphGlow(morphFormSlot)
        end
    end
end

-- Flag: when true, the next SendFullMorphState prepends RESET:ALL so the
-- DLL wipe + restore happen in ONE atomic batch (single 20 ms poll).
-- Set on PLAYER_LOGIN so character-switch state bleed is impossible.
local needsCharacterReset = false

-- Send all current morph state to the DLL (used on login/zone change).
-- If needsCharacterReset is set, RESET:ALL is prepended so the whole
-- operation is one pipe-delimited string the DLL processes atomically.
-- Uses SendRawMorphCommand (not SendMorphCommand) because we are restoring
-- already-persisted state — no need to re-track into SavedVariables.
local function SendFullMorphState()
    -- ALWAYS send RESET:ALL on character login to clear DLL state from
    -- any previous character, even if saveMorphState is off.
    if needsCharacterReset then
        SendRawMorphCommand("RESET:ALL")
        needsCharacterReset = false
    end

    if not GetSettings().saveMorphState then
        return
    end
    if not TransmorpherCharacterState then
        return
    end
    if IsModelChangingForm() or dbwSuspended or vehicleSuspended then return end

    local cmdQueue = {}
    if TransmorpherCharacterState.Scale then table.insert(cmdQueue, "SCALE:"..TransmorpherCharacterState.Scale) end
    if TransmorpherCharacterState.Morph then table.insert(cmdQueue, "MORPH:"..TransmorpherCharacterState.Morph) end
    if TransmorpherCharacterState.MountDisplay and GetSettings().saveMountMorph then
        table.insert(cmdQueue, "MOUNT_MORPH:"..TransmorpherCharacterState.MountDisplay)
    end
    if TransmorpherCharacterState.PetDisplay and GetSettings().savePetMorph then
        table.insert(cmdQueue, "PET_MORPH:"..TransmorpherCharacterState.PetDisplay)
    end
    if TransmorpherCharacterState.HunterPetDisplay and (GetSettings().saveCombatPetMorph or GetSettings().saveHunterPetMorph) then
        table.insert(cmdQueue, "HPET_MORPH:"..TransmorpherCharacterState.HunterPetDisplay)
    end
    if TransmorpherCharacterState.HunterPetScale and (GetSettings().saveCombatPetMorph or GetSettings().saveHunterPetMorph) then
        table.insert(cmdQueue, "HPET_SCALE:"..TransmorpherCharacterState.HunterPetScale)
    end
    if TransmorpherCharacterState.EnchantMH then
        table.insert(cmdQueue, "ENCHANT_MH:"..TransmorpherCharacterState.EnchantMH)
    end
    if TransmorpherCharacterState.EnchantOH then
        table.insert(cmdQueue, "ENCHANT_OH:"..TransmorpherCharacterState.EnchantOH)
    end
    if TransmorpherCharacterState.Items then
        for slot, item in pairs(TransmorpherCharacterState.Items) do
            table.insert(cmdQueue, "ITEM:"..slot..":"..item)
        end
    end
    if #cmdQueue > 0 then
        SendRawMorphCommand(table.concat(cmdQueue, "|"))
    end
end

-- ============================================================
-- HELPER — returns the item ID the player actually has equipped
-- in a given slot, or nil if the slot is empty / unresolvable.
-- ============================================================
local function GetEquippedItemForSlot(slotName)
    local csn = slotName
    if csn == mainHandSlot then csn = "MainHand" end
    if csn == offHandSlot  then csn = "SecondaryHand" end
    if csn == rangedSlot    then csn = "Ranged" end
    if csn == backSlot      then csn = "Back" end
    local slotId = GetInventorySlotInfo(csn .. "Slot")
    local itemId = GetInventoryItemID("player", slotId)
    if itemId then
        local name = GetItemInfo(itemId)
        if name then return itemId end
    end
    return nil
end

-- ============================================================
-- DRESSING ROOM SYNC — central function that rebuilds the 3D
-- model from all current slot items. Call after any morph action.
-- ============================================================
local function SyncDressingRoom()
    if not mainFrame or not mainFrame.dressingRoom or not mainFrame.slots then return end
    mainFrame.dressingRoom:Undress()
    
    -- Check if main hand or off-hand weapons exist
    local hasMainHand = mainFrame.slots["Main Hand"] and mainFrame.slots["Main Hand"].itemId and mainFrame.slots["Main Hand"].itemId ~= 0 and not mainFrame.slots["Main Hand"].isHiddenSlot
    local hasOffHand = mainFrame.slots["Off-hand"] and mainFrame.slots["Off-hand"].itemId and mainFrame.slots["Off-hand"].itemId ~= 0 and not mainFrame.slots["Off-hand"].isHiddenSlot
    
    for _, slotName in pairs(slotOrder) do
        local slot = mainFrame.slots[slotName]
        if slot and slot.itemId and slot.itemId ~= 0 and not slot.isHiddenSlot then
            -- Skip ranged weapon if main hand or off-hand weapons exist
            if slotName == "Ranged" and (hasMainHand or hasOffHand) then
                -- Don't display ranged weapon when melee weapons are equipped
            else
                ns.QueryItem(slot.itemId, function(queriedItemId, success)
                    if success and slot.itemId == queriedItemId then
                        mainFrame.dressingRoom:TryOn(queriedItemId)
                    end
                end)
            end
        end
    end
    
    -- Update special slots
    UpdateSpecialSlots()
end

-- Restore UI (slots, glows, enchant slots, dressing room) from saved state.
-- Called once after PLAYER_LOGIN when persistence is active.
local function RestoreMorphedUI()
    if not GetSettings().saveMorphState then return end
    if not TransmorpherCharacterState then return end

    -- Wait until mainFrame.slots and mainFrame.enchantSlots are built.
    local restoreFrame = CreateFrame("Frame")
    restoreFrame.elapsed = 0
    restoreFrame:SetScript("OnUpdate", function(self, dt)
        self.elapsed = self.elapsed + dt
        if self.elapsed < 0.6 then return end
        self:Hide()
        self:SetScript("OnUpdate", nil)

        if not mainFrame or not mainFrame.slots then return end

        -- Step 1: populate EVERY slot with the real equipped item (no glow).
        -- This makes non-morphed gear visible so the user can see the
        -- difference: glow = morphed, no glow = real equipped item.
        for _, slotName in pairs(slotOrder) do
            local slot = mainFrame.slots[slotName]
            if slot then
                if slotName == rangedSlot and ("DRUIDSHAMANPALADINDEATHKNIGHT"):find(classFileName) then
                    slot:RemoveItem()
                else
                    local equippedId = GetEquippedItemForSlot(slotName)
                    if equippedId then
                        slot:SetItem(equippedId)
                    else
                        slot:RemoveItem()
                    end
                end
                -- Make sure no glow from a previous session leaks
                slot.isMorphed = false
                slot.morphedItemId = nil
                HideMorphGlow(slot)
            end
        end

        -- Step 2: overlay morphed items with golden glow on the slots
        -- that have saved morph state — but skip any slot where the
        -- morph item matches current equipped gear (not a real morph).
        if TransmorpherCharacterState.Items then
            for equipSlotId, itemId in pairs(TransmorpherCharacterState.Items) do
                local slotName = equipSlotIdToSlot[equipSlotId]
                if slotName and mainFrame.slots[slotName] then
                    local equippedId = GetEquippedItemForSlot(slotName)
                    if equippedId and equippedId == itemId then
                        -- Saved morph is same as equipped: skip (no glow)
                    else
                        local slot = mainFrame.slots[slotName]
                        slot:SetItem(itemId)
                        slot.isMorphed = true
                        slot.morphedItemId = itemId
                        ShowMorphGlow(slot)
                    end
                end
            end
        end

        -- Restore enchant slots
        if mainFrame.enchantSlots then
            if TransmorpherCharacterState.EnchantMH then
                local eid = TransmorpherCharacterState.EnchantMH
                local eName = tostring(eid)
                if ns.enchantDB and ns.enchantDB[eid] then eName = ns.enchantDB[eid] end
                local es = mainFrame.enchantSlots["Enchant MH"]
                es:SetEnchant(eid, eName)
                es.isMorphed = true
                ShowMorphGlow(es, "orange")
            end
            if TransmorpherCharacterState.EnchantOH then
                local eid = TransmorpherCharacterState.EnchantOH
                local eName = tostring(eid)
                if ns.enchantDB and ns.enchantDB[eid] then eName = ns.enchantDB[eid] end
                local es = mainFrame.enchantSlots["Enchant OH"]
                es:SetEnchant(eid, eName)
                es.isMorphed = true
                ShowMorphGlow(es, "orange")
            end
        end

        -- Pre-build the dressing room model with all restored morphed items
        SyncDressingRoom()
    end)
end

local function IsMorpherReady()
    -- Check if the DLL has set the loaded flag
    -- The DLL should set TRANSMORPHER_DLL_LOADED = true when it initializes
    -- For now, return true to allow morphing (DLL detection can be added later)
    return true
    -- return TRANSMORPHER_DLL_LOADED == true
end

local dressingRoomBorderBackdrop = {
    bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
    edgeFile = "Interface\\AddOns\\Transmorpher\\images\\mirror-border",
    tile = false, tileSize = 16, edgeSize = 32,
    insets = { left = 4, right = 4, top = 4, bottom = 4 }
}

---------------- MAIN FRAME ----------------

mainFrame = CreateFrame("Frame", addon, UIParent)
table.insert(UISpecialFrames, mainFrame:GetName())
do
    mainFrame:SetWidth(1045)
    mainFrame:SetHeight(505)
    mainFrame:SetPoint("CENTER")
    mainFrame:Hide()
    mainFrame:SetMovable(true)
    mainFrame:EnableMouse(true)
    mainFrame:RegisterForDrag("LeftButton")
    mainFrame:SetScript("OnDragStart", mainFrame.StartMoving)
    mainFrame:SetScript("OnDragStop", mainFrame.StopMovingOrSizing)
    mainFrame:SetScript("OnShow", function()
        PlaySound("igCharacterInfoOpen")
        -- Ensure every slot shows something: morphed items get glow,
        -- empty non-morphed slots get the real equipped item (no glow).
        if mainFrame.slots then
            for _, slotName in pairs(slotOrder) do
                local slot = mainFrame.slots[slotName]
                if slot then
                    if slot.isMorphed and slot.morphedItemId then
                        -- Morphed slot: make sure the glow is active
                        ShowMorphGlow(slot)
                    elseif not slot.itemId then
                        -- Empty non-morphed slot: fill with equipped gear
                        if not (slotName == rangedSlot and ("DRUIDSHAMANPALADINDEATHKNIGHT"):find(classFileName)) then
                            local equippedId = GetEquippedItemForSlot(slotName)
                            if equippedId then slot:SetItem(equippedId) end
                        end
                    end
                end
            end
        end
        if mainFrame.enchantSlots then
            for _, es in pairs(mainFrame.enchantSlots) do
                if es.isMorphed then ShowMorphGlow(es) end
            end
        end
    end)
    mainFrame:SetScript("OnHide", function() PlaySound("igCharacterInfoClose") end)

    local title = mainFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOP", 0, -8)
    title:SetText(mainFrameTitle)
    title:SetFont("Fonts\\FRIZQT__.TTF", 14, "OUTLINE")
    title:SetShadowColor(0, 0, 0, 0.8)
    title:SetShadowOffset(1, -1)

    local titleBg = mainFrame:CreateTexture(nil, "BACKGROUND")
    titleBg:SetTexture("Interface\\PaperDollInfoFrame\\UI-GearManager-Title-Background")
    titleBg:SetPoint("TOPLEFT", 10, -7)
    titleBg:SetPoint("BOTTOMRIGHT", mainFrame, "TOPRIGHT", -28, -24)
    titleBg:SetVertexColor(0.14, 0.11, 0.04, 1)

    local menuBg = mainFrame:CreateTexture(nil, "BACKGROUND")
    menuBg:SetTexture("Interface\\WorldStateFrame\\WorldStateFinalScoreFrame-TopBackground")
    menuBg:SetTexCoord(0, 1, 0, 0.8125)
    menuBg:SetPoint("TOPLEFT", 10, -26)
    menuBg:SetPoint("RIGHT", -6, 0)
    menuBg:SetHeight(48)
    menuBg:SetVertexColor(0.10, 0.08, 0.03, 1)

    local frameBg = mainFrame:CreateTexture(nil, "BACKGROUND")
    frameBg:SetTexture("Interface\\WorldStateFrame\\WorldStateFinalScoreFrame-TopBackground")
    frameBg:SetTexCoord(0, 0.5, 0, 0.8125)
    frameBg:SetPoint("TOPLEFT", menuBg, "BOTTOMLEFT")
    frameBg:SetPoint("TOPRIGHT", menuBg, "BOTTOMRIGHT")
    frameBg:SetPoint("BOTTOM", 0, 5)
    frameBg:SetVertexColor(0.07, 0.06, 0.03, 1)

    local topLeft = mainFrame:CreateTexture(nil, "BORDER")
    topLeft:SetTexture("Interface\\PaperDollInfoFrame\\UI-GearManager-Border")
    topLeft:SetTexCoord(0.5, 0.625, 0, 1)
    topLeft:SetWidth(64) topLeft:SetHeight(64) topLeft:SetPoint("TOPLEFT")
    topLeft:SetVertexColor(0.85, 0.70, 0.25, 1)

    local topRight = mainFrame:CreateTexture(nil, "BORDER")
    topRight:SetTexture("Interface\\PaperDollInfoFrame\\UI-GearManager-Border")
    topRight:SetTexCoord(0.625, 0.75, 0, 1)
    topRight:SetWidth(64) topRight:SetHeight(64) topRight:SetPoint("TOPRIGHT")
    topRight:SetVertexColor(0.85, 0.70, 0.25, 1)

    local top = mainFrame:CreateTexture(nil, "BORDER")
    top:SetTexture("Interface\\PaperDollInfoFrame\\UI-GearManager-Border")
    top:SetTexCoord(0.25, 0.37, 0, 1)
    top:SetPoint("TOPLEFT", topLeft, "TOPRIGHT")
    top:SetPoint("TOPRIGHT", topRight, "TOPLEFT")
    top:SetVertexColor(0.85, 0.70, 0.25, 1)

    local menuSepL = mainFrame:CreateTexture(nil, "BORDER")
    menuSepL:SetTexture("Interface\\PaperDollInfoFrame\\UI-GearManager-Border")
    menuSepL:SetTexCoord(0.5, 0.5546875, 0.25, 0.53125)
    menuSepL:SetPoint("TOPLEFT", topLeft, "BOTTOMLEFT")
    menuSepL:SetWidth(28) menuSepL:SetHeight(18)
    menuSepL:SetVertexColor(0.85, 0.70, 0.25, 1)

    local menuSepR = mainFrame:CreateTexture(nil, "BORDER")
    menuSepR:SetTexture("Interface\\PaperDollInfoFrame\\UI-GearManager-Border")
    menuSepR:SetTexCoord(0.7109375, 0.75, 0.25, 0.53125)
    menuSepR:SetPoint("TOPRIGHT", topRight, "BOTTOMRIGHT")
    menuSepR:SetWidth(20) menuSepR:SetHeight(18)
    menuSepR:SetVertexColor(0.85, 0.70, 0.25, 1)

    local menuSepC = mainFrame:CreateTexture(nil, "BORDER")
    menuSepC:SetTexture("Interface\\PaperDollInfoFrame\\UI-GearManager-Border")
    menuSepC:SetTexCoord(0.564453125, 0.671875, 0.25, 0.53125)
    menuSepC:SetPoint("TOPLEFT", menuSepL, "TOPRIGHT")
    menuSepC:SetPoint("BOTTOMRIGHT", menuSepR, "BOTTOMLEFT")
    menuSepC:SetVertexColor(0.85, 0.70, 0.25, 1)

    local botLeft = mainFrame:CreateTexture(nil, "BORDER")
    botLeft:SetTexture("Interface\\PaperDollInfoFrame\\UI-GearManager-Border")
    botLeft:SetTexCoord(0.75, 0.875, 0, 1)
    botLeft:SetPoint("BOTTOMLEFT") botLeft:SetWidth(64) botLeft:SetHeight(64)
    botLeft:SetVertexColor(0.85, 0.70, 0.25, 1)

    local left = mainFrame:CreateTexture(nil, "BORDER")
    left:SetTexture("Interface\\PaperDollInfoFrame\\UI-GearManager-Border")
    left:SetTexCoord(0, 0.125, 0, 1)
    left:SetPoint("TOPLEFT", menuSepL, "BOTTOMLEFT")
    left:SetPoint("BOTTOMRIGHT", botLeft, "TOPRIGHT")
    left:SetVertexColor(0.85, 0.70, 0.25, 1)

    local botRight = mainFrame:CreateTexture(nil, "BORDER")
    botRight:SetTexture("Interface\\PaperDollInfoFrame\\UI-GearManager-Border")
    botRight:SetTexCoord(0.875, 1, 0, 1)
    botRight:SetPoint("BOTTOMRIGHT") botRight:SetWidth(64) botRight:SetHeight(64)
    botRight:SetVertexColor(0.85, 0.70, 0.25, 1)

    local right = mainFrame:CreateTexture(nil, "BORDER")
    right:SetTexture("Interface\\PaperDollInfoFrame\\UI-GearManager-Border")
    right:SetTexCoord(0.125, 0.25, 0, 1)
    right:SetPoint("TOPRIGHT", menuSepR, "BOTTOMRIGHT", 4, 0)
    right:SetPoint("BOTTOMLEFT", botRight, "TOPLEFT", 4, 0)
    right:SetVertexColor(0.85, 0.70, 0.25, 1)

    local bot = mainFrame:CreateTexture(nil, "BORDER")
    bot:SetTexture("Interface\\PaperDollInfoFrame\\UI-GearManager-Border")
    bot:SetTexCoord(0.38, 0.45, 0, 1)
    bot:SetPoint("BOTTOMLEFT", botLeft, "BOTTOMRIGHT")
    bot:SetPoint("TOPRIGHT", botRight, "TOPLEFT")
    bot:SetVertexColor(0.85, 0.70, 0.25, 1)

    local separatorV = mainFrame:CreateTexture(nil, "BORDER")
    separatorV:SetTexture("Interface\\PaperDollInfoFrame\\UI-GearManager-Border")
    separatorV:SetTexCoord(0.23046875, 0.236328125, 0, 1)
    separatorV:SetPoint("TOPLEFT", 410, -72)
    separatorV:SetPoint("BOTTOM", 0, 32)
    separatorV:SetWidth(3)
    separatorV:SetVertexColor(0.85, 0.70, 0.25, 0.7)

    mainFrame.stats = CreateFrame("Frame", nil, mainFrame)
    local stats = mainFrame.stats
    stats:SetBackdrop({
        bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 16,
        insets = { left = 3, right = 3, top = 5, bottom = 3 }
    })
    stats:SetBackdropColor(0.05, 0.04, 0.02, 0.95)
    stats:SetBackdropBorderColor(0.80, 0.65, 0.22, 0.85)
    stats:SetPoint("BOTTOMLEFT", 410, 8)
    stats:SetPoint("BOTTOMRIGHT", -6, 8)
    stats:SetHeight(24)

    -- Morph status text
    mainFrame.morphStatus = stats:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    mainFrame.morphStatus:SetPoint("CENTER")
    mainFrame.morphStatus:SetText("")
    mainFrame.morphStatus:SetTextColor(1.0, 0.84, 0.40, 1)

    mainFrame.buttons = {}

    local close = CreateFrame("Button", nil, mainFrame, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", 2, 1)
    close:SetScript("OnClick", function(self) self:GetParent():Hide() end)
    mainFrame.buttons.close = close
end

---------------- DRESSING ROOM ----------------

mainFrame.dressingRoom = ns.CreateDressingRoom(nil, mainFrame)

do
    local dr = mainFrame.dressingRoom
    dr:SetPoint("TOPLEFT", 10, -74)
    dr:SetSize(400, 400)

    local border = CreateFrame("Frame", nil, dr)
    border:SetAllPoints()
    border:SetBackdrop(dressingRoomBorderBackdrop)
    border:SetBackdropColor(0, 0, 0, 0)
    border:SetBackdropBorderColor(0.80, 0.65, 0.22, 0.9)

    -- Race-specific background textures (from images/ folder)
    dr.backgroundTextures = {}
    local bgKeys = "human,nightelf,dwarf,gnome,draenei,orc,scourge,tauren,troll,bloodelf,deathknight,highelf"
    for s in bgKeys:gmatch("%w+") do
        dr.backgroundTextures[s] = dr:CreateTexture(nil, "BACKGROUND")
        dr.backgroundTextures[s]:SetTexture("Interface\\AddOns\\Transmorpher\\images\\"..s)
        dr.backgroundTextures[s]:SetAllPoints()
        dr.backgroundTextures[s]:Hide()
    end
    dr.backgroundTextures["color"] = dr:CreateTexture(nil, "BACKGROUND")
    dr.backgroundTextures["color"]:SetAllPoints()
    dr.backgroundTextures["color"]:SetTexture(1, 1, 1)
    dr.backgroundTextures["color"]:Hide()

    -- Map raceFileName → background texture key
    local raceToBgKey = {
        Human    = "human",
        NightElf = "nightelf",
        Dwarf    = "dwarf",
        Gnome    = "gnome",
        Draenei  = "draenei",
        Orc      = "orc",
        Scourge  = "scourge",
        Tauren   = "tauren",
        Troll    = "troll",
        BloodElf = "bloodelf",
    }

    -- Show the correct race background for the current character
    function dr:ShowRaceBackground()
        -- Hide all backgrounds first
        for key, tex in pairs(self.backgroundTextures) do
            tex:Hide()
        end
        -- Determine which background to use
        local settings = GetSettings()
        local bgKey = settings.dressingRoomBackgroundTexture[GetRealmName()]
            and settings.dressingRoomBackgroundTexture[GetRealmName()][GetUnitName("player")]
        -- If setting says DEATHKNIGHT, use deathknight bg
        if bgKey == "DEATHKNIGHT" then
            bgKey = "deathknight"
        else
            -- Map race filename to our texture key
            bgKey = raceToBgKey[bgKey] or raceToBgKey[raceFileName] or "human"
        end
        if self.backgroundTextures[bgKey] then
            self.backgroundTextures[bgKey]:Show()
            self.backgroundTextures[bgKey]:SetAlpha(0.4)
        end
    end

    -- Show background on dressing room show
    dr:HookScript("OnShow", function(self) self:ShowRaceBackground() end)

    local tip = dr:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    tip:SetPoint("BOTTOM", dr, "TOP", 0, 12)
    tip:SetWidth(dr:GetWidth())  -- Constrain to dressing room width
    tip:SetJustifyH("CENTER") tip:SetJustifyV("BOTTOM")
    tip:SetText("\124cffC8AA6ELeft Mouse:\124r rotate \124 \124cffC8AA6ERight Mouse:\124r pan\124n\124cffC8AA6EWheel\124r or \124cffC8AA6EAlt + Right Mouse:\124r zoom")
    tip:SetTextColor(0.75, 0.7, 0.6, 0.9)
    tip:SetShadowColor(0, 0, 0, 1)
    tip:SetShadowOffset(1, -1)

    local defaultLight = {1, 0, 0, 1, 0, 1, 0.7, 0.7, 0.7, 1, 0.8, 0.8, 0.64}
    local shadowformLight = {1, 0, 0, 1, 0, 1, 0.16, 0, 0.23, 0}
    dr.shadowformEnabled = false
    dr.EnableShadowform = function(self)
        self:SetLight(unpack(shadowformLight))
        self:SetModelAlpha(0.75)
        self.shadowformEnabled = true
    end
    dr.DisableShadowform = function(self)
        self:SetLight(unpack(defaultLight))
        self:SetModelAlpha(1)
        self.shadowformEnabled = false
    end
end

-- ============================================================
-- MORPHED SLOT GLOW SYSTEM — World-class multi-layer golden glow
-- 3-layer effect: inner highlight + border glow + outer pulse
-- ============================================================
local morphGlowAnimFrame = CreateFrame("Frame")
morphGlowAnimFrame:Hide()
local morphGlowSlots = {}
local morphGlowTimer = 0

morphGlowAnimFrame:SetScript("OnUpdate", function(self, dt)
    morphGlowTimer = morphGlowTimer + dt
    -- Primary pulse: smooth sine wave, 2 second cycle
    local pulse = 0.5 + 0.5 * math.sin(morphGlowTimer * 3.14159)
    -- Secondary shimmer: faster, subtler
    local shimmer = 0.5 + 0.5 * math.sin(morphGlowTimer * 5.2)
    for slot, layers in pairs(morphGlowSlots) do
        if layers.inner and layers.inner:IsShown() then
            -- Inner highlight: gentle constant glow with subtle shimmer
            layers.inner:SetAlpha(0.12 + 0.08 * shimmer)
            -- Border glow: medium pulse
            layers.border:SetAlpha(0.55 + 0.35 * pulse)
            -- Outer bloom: strong pulse, breathes in and out
            layers.outer:SetAlpha(0.25 + 0.45 * pulse)
        end
    end
end)

local function AddMorphGlow(slot, colorType)
    if slot.morphGlowLayers then return slot.morphGlowLayers end

    local layers = {}
    
    -- Color definitions: gold (default), orange (enchants), red (special slots), green (unused), purple (morph form)
    local colors = {
        gold = {
            inner = {1.0, 0.82, 0.20, 0.15},
            border = {1.0, 0.78, 0.10, 0.85},
            outer = {1.0, 0.65, 0.0, 0.5}
        },
        orange = {
            inner = {1.0, 0.50, 0.10, 0.15},
            border = {1.0, 0.45, 0.05, 0.85},
            outer = {0.95, 0.40, 0.0, 0.5}
        },
        red = {
            inner = {1.0, 0.20, 0.20, 0.15},
            border = {0.95, 0.15, 0.15, 0.85},
            outer = {0.85, 0.10, 0.10, 0.5}
        },
        green = {
            inner = {0.20, 1.0, 0.20, 0.15},
            border = {0.15, 0.95, 0.15, 0.85},
            outer = {0.10, 0.85, 0.10, 0.5}
        },
        purple = {
            inner = {0.70, 0.30, 1.0, 0.15},
            border = {0.65, 0.25, 0.95, 0.85},
            outer = {0.55, 0.20, 0.85, 0.5}
        }
    }
    
    local color = colors[colorType] or colors.gold

    -- Layer 1: Inner highlight — fills the slot with a colored wash
    local inner = slot:CreateTexture(nil, "OVERLAY", nil, 1)
    inner:SetPoint("TOPLEFT", -3, 3)
    inner:SetPoint("BOTTOMRIGHT", 3, -3)
    inner:SetTexture("Interface\\Buttons\\WHITE8X8")
    inner:SetBlendMode("ADD")
    inner:SetVertexColor(unpack(color.inner))
    inner:Hide()
    layers.inner = inner

    -- Layer 2: Border glow — crisp colored edge sized to match the item border
    local border = slot:CreateTexture(nil, "OVERLAY", nil, 2)
    border:SetPoint("TOPLEFT", -12, 12)
    border:SetPoint("BOTTOMRIGHT", 12, -12)
    border:SetTexture("Interface\\Buttons\\UI-ActionButton-Border")
    border:SetBlendMode("ADD")
    border:SetVertexColor(unpack(color.border))
    border:Hide()
    layers.border = border

    -- Layer 3: Outer bloom — larger, softer glow for depth
    local outer = slot:CreateTexture(nil, "OVERLAY", nil, 3)
    outer:SetPoint("TOPLEFT", -16, 16)
    outer:SetPoint("BOTTOMRIGHT", 16, -16)
    outer:SetTexture("Interface\\Buttons\\UI-ActionButton-Border")
    outer:SetBlendMode("ADD")
    outer:SetVertexColor(unpack(color.outer))
    outer:Hide()
    layers.outer = outer

    slot.morphGlowLayers = layers
    slot.glowColorType = colorType or "gold"
    return layers
end

ShowMorphGlow = function(slot, colorType)
    local layers = AddMorphGlow(slot, colorType)
    layers.inner:Show()
    layers.border:Show()
    layers.outer:Show()
    morphGlowSlots[slot] = layers
    morphGlowAnimFrame:Show()
end

HideMorphGlow = function(slot)
    if slot.morphGlowLayers then
        slot.morphGlowLayers.inner:Hide()
        slot.morphGlowLayers.border:Hide()
        slot.morphGlowLayers.outer:Hide()
    end
    morphGlowSlots[slot] = nil
    local hasAny = false
    for _ in pairs(morphGlowSlots) do hasAny = true; break end
    if not hasAny then morphGlowAnimFrame:Hide() end
end

---------------- BOTTOM BUTTONS ----------------

-- Apply All button (NEW - morphs all equipped preview items)
mainFrame.buttons.applyAll = CreateGoldenButton("$parentButtonApplyAll", mainFrame)
do
    local btn = mainFrame.buttons.applyAll
    btn:SetPoint("TOPLEFT", mainFrame.dressingRoom, "BOTTOMLEFT")
    btn:SetPoint("BOTTOM", mainFrame.stats, "BOTTOM", 0, 1)
    btn:SetWidth(mainFrame.dressingRoom:GetWidth()/4)
    btn:SetText("|cffF5C842Apply All|r")
    
    -- Modern button styling
    btn:SetBackdrop({
        bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = false, tileSize = 16, edgeSize = 12,
        insets = { left = 2, right = 2, top = 2, bottom = 2 }
    })
    btn:SetBackdropColor(0.12, 0.22, 0.10, 0.9)
    btn:SetBackdropBorderColor(0.4, 0.6, 0.25, 1)
    
    btn:SetScript("OnClick", function()
        if not IsMorpherReady() then
            SELECTED_CHAT_FRAME:AddMessage("|cffF5C842<Transmorpher>|r: |cffff0000Morpher DLL not loaded! Place wow_morpher.dll in your WoW folder.|r")
            return
        end
        for _, slotName in pairs(slotOrder) do
            local slot = mainFrame.slots[slotName]
            if slot.itemId ~= nil and slotToEquipSlotId[slotName] then
                local equippedId = GetEquippedItemForSlot(slotName)
                if equippedId and equippedId == slot.itemId then
                    -- Same as equipped: not a morph
                    slot.isMorphed = false
                    slot.morphedItemId = nil
                    HideMorphGlow(slot)
                else
                    SendMorphCommand("ITEM:" .. slotToEquipSlotId[slotName] .. ":" .. slot.itemId)
                    slot.isMorphed = true
                    slot.morphedItemId = slot.itemId
                    ShowMorphGlow(slot)
                end
            end
        end
        -- Apply enchant morphs
        if mainFrame.enchantSlots then
            if mainFrame.enchantSlots["Enchant MH"].enchantId then
                SendMorphCommand("ENCHANT_MH:" .. mainFrame.enchantSlots["Enchant MH"].enchantId)
                mainFrame.enchantSlots["Enchant MH"].isMorphed = true
                ShowMorphGlow(mainFrame.enchantSlots["Enchant MH"], "orange")
            end
            if mainFrame.enchantSlots["Enchant OH"].enchantId then
                SendMorphCommand("ENCHANT_OH:" .. mainFrame.enchantSlots["Enchant OH"].enchantId)
                mainFrame.enchantSlots["Enchant OH"].isMorphed = true
                ShowMorphGlow(mainFrame.enchantSlots["Enchant OH"], "orange")
            end
        end
        SyncDressingRoom()
        SELECTED_CHAT_FRAME:AddMessage("|cffF5C842<Transmorpher>|r: All slots morphed!")
        PlaySound("gsTitleOptionOK")
    end)
    btn:HookScript("OnEnter", function(self)
        self:SetBackdropColor(0.18, 0.30, 0.14, 0.95)
        self:SetBackdropBorderColor(0.55, 0.75, 0.35, 1)
        GameTooltip:SetOwner(self, "ANCHOR_TOPLEFT")
        GameTooltip:ClearLines()
        GameTooltip:AddLine("|cffF5C842Apply All|r", 1, 1, 1)
        GameTooltip:AddLine("Apply all previewed items as morph to your character.", 0.7, 0.9, 1, 1, true)
        GameTooltip:AddLine("Requires wow_morpher.dll in your WoW folder.", 0.6, 0.6, 0.6, 1, true)
        GameTooltip:Show()
    end)
    btn:HookScript("OnLeave", function(self)
        self:SetBackdropColor(0.12, 0.22, 0.10, 0.9)
        self:SetBackdropBorderColor(0.4, 0.6, 0.25, 1)
        GameTooltip:Hide()
    end)
end

-- Reset Morph button (NEW)
mainFrame.buttons.resetMorph = CreateGoldenButton("$parentButtonResetMorph", mainFrame)
do
    local btn = mainFrame.buttons.resetMorph
    btn:SetPoint("TOPLEFT", mainFrame.buttons.applyAll, "TOPRIGHT")
    btn:SetPoint("BOTTOM", mainFrame.buttons.applyAll, "BOTTOM")
    btn:SetWidth(mainFrame.buttons.applyAll:GetWidth())
    btn:SetText("|cffF5C842Reset Morph|r")
    
    -- Modern button styling
    btn:SetBackdrop({
        bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = false, tileSize = 16, edgeSize = 12,
        insets = { left = 2, right = 2, top = 2, bottom = 2 }
    })
    btn:SetBackdropColor(0.12, 0.10, 0.06, 0.9)
    btn:SetBackdropBorderColor(0.65, 0.52, 0.20, 1)
    
    btn:SetScript("OnClick", function()
        if IsMorpherReady() then
            SendMorphCommand("RESET:ALL")
            -- Clear all morph state, restore equipped gear (no glow)
            for _, slotName in pairs(slotOrder) do
                local slot = mainFrame.slots[slotName]
                slot.isMorphed = false
                slot.morphedItemId = nil
                slot.isHiddenSlot = false
                HideMorphGlow(slot)
                -- Reset eye button
                if slot.eyeButton then
                    slot.eyeButton.isHidden = false
                    slot.eyeButton.eyeTex:SetVertexColor(0.85, 0.75, 0.45, 0.8)
                    slot.eyeButton.hiddenTex:Hide()
                end
                if slotName == rangedSlot and ("DRUIDSHAMANPALADINDEATHKNIGHT"):find(classFileName) then
                    -- no ranged for these classes
                else
                    local equippedId = GetEquippedItemForSlot(slotName)
                    if equippedId then slot:SetItem(equippedId)
                    else slot.itemId = nil; slot.textures.empty:Show(); slot.textures.item:Hide() end
                end
            end
            if mainFrame.enchantSlots then
                for _, es in pairs(mainFrame.enchantSlots) do
                    es.isMorphed = false
                    es:RemoveEnchant()
                    HideMorphGlow(es)
                end
            end
            SyncDressingRoom()
            SELECTED_CHAT_FRAME:AddMessage("|cffF5C842<Transmorpher>|r: All morphs reset!")
        end
        PlaySound("gsTitleOptionOK")
    end)
    btn:HookScript("OnEnter", function(self)
        self:SetBackdropColor(0.18, 0.15, 0.08, 0.95)
        self:SetBackdropBorderColor(0.85, 0.68, 0.28, 1)
        GameTooltip:SetOwner(self, "ANCHOR_TOPLEFT")
        GameTooltip:ClearLines()
        GameTooltip:AddLine("|cffF5C842Reset Morph|r", 1, 1, 1)
        GameTooltip:AddLine("Revert all morphed slots back to your real equipped gear.", 0.7, 0.9, 1, 1, true)
        GameTooltip:Show()
    end)
    btn:HookScript("OnLeave", function(self)
        self:SetBackdropColor(0.12, 0.10, 0.06, 0.9)
        self:SetBackdropBorderColor(0.65, 0.52, 0.20, 1)
        GameTooltip:Hide()
    end)
end

-- Reset Preview button
mainFrame.buttons.reset = CreateGoldenButton("$parentButtonReset", mainFrame)
do
    local btn = mainFrame.buttons.reset
    btn:SetPoint("TOPLEFT", mainFrame.buttons.resetMorph, "TOPRIGHT")
    btn:SetPoint("BOTTOM", mainFrame.buttons.applyAll, "BOTTOM")
    btn:SetWidth(mainFrame.buttons.applyAll:GetWidth())
    btn:SetText("|cff8CB4D8Reset Preview|r")
    
    -- Modern button styling
    btn:SetBackdrop({
        bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = false, tileSize = 16, edgeSize = 12,
        insets = { left = 2, right = 2, top = 2, bottom = 2 }
    })
    btn:SetBackdropColor(0.08, 0.12, 0.20, 0.9)
    btn:SetBackdropBorderColor(0.3, 0.42, 0.6, 1)
    
    btn:SetScript("OnClick", function()
        mainFrame.dressingRoom:Reset()
        PlaySound("gsTitleOptionOK")
    end)
    btn:HookScript("OnEnter", function(self)
        self:SetBackdropColor(0.12, 0.18, 0.28, 0.95)
        self:SetBackdropBorderColor(0.4, 0.55, 0.8, 1)
    end)
    btn:HookScript("OnLeave", function(self)
        self:SetBackdropColor(0.08, 0.12, 0.20, 0.9)
        self:SetBackdropBorderColor(0.3, 0.42, 0.6, 1)
    end)
end

-- Undress button
mainFrame.buttons.undress = CreateGoldenButton("$parentButtonUndress", mainFrame)
do
    local btn = mainFrame.buttons.undress
    btn:SetPoint("TOPLEFT", mainFrame.buttons.reset, "TOPRIGHT")
    btn:SetPoint("TOPRIGHT", mainFrame.dressingRoom, "BOTTOMRIGHT")
    btn:SetPoint("BOTTOM", mainFrame.buttons.applyAll, "BOTTOM")
    btn:SetText("|cffF5C842Undress|r")
    
    -- Modern button styling
    btn:SetBackdrop({
        bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = false, tileSize = 16, edgeSize = 12,
        insets = { left = 2, right = 2, top = 2, bottom = 2 }
    })
    btn:SetBackdropColor(0.18, 0.13, 0.06, 0.9)
    btn:SetBackdropBorderColor(0.55, 0.45, 0.2, 1)
    
    btn:SetScript("OnClick", function()
        mainFrame.dressingRoom:Undress()
        PlaySound("gsTitleOptionOK")
    end)
    btn:HookScript("OnEnter", function(self)
        self:SetBackdropColor(0.25, 0.18, 0.08, 0.95)
        self:SetBackdropBorderColor(0.7, 0.58, 0.3, 1)
    end)
    btn:HookScript("OnLeave", function(self)
        self:SetBackdropColor(0.18, 0.13, 0.06, 0.9)
        self:SetBackdropBorderColor(0.55, 0.45, 0.2, 1)
    end)
end

---------------- TABS ----------------

local TAB_NAMES = {"Preview", "Loadouts", "Mounts", "Pets", "Combat Pets", "Morph", "Settings"}
mainFrame.tabs = {}

do
    local tabs = {}
    local selectedTabIdx = 1

    -- Compute total width available for tabs (right side of the frame)
    local TAB_AREA_LEFT = 412    -- where tabs start (matches separator)
    local TAB_AREA_RIGHT = 1045 - 10  -- mainFrame width minus right padding
    local TAB_AREA_WIDTH = TAB_AREA_RIGHT - TAB_AREA_LEFT
    local TAB_COUNT = #TAB_NAMES
    local TAB_H = 26
    local TAB_GAP = 0  -- no gap — tabs sit flush against each other
    local TAB_W = math.floor(TAB_AREA_WIDTH / TAB_COUNT)
    local TAB_TOP = -30  -- vertical position from mainFrame top

    local function UpdateTabAppearance()
        for i = 1, TAB_COUNT do
            local tabBtn = mainFrame.buttons["tab"..i]
            if i == selectedTabIdx then
                tabBtn.bg:SetTexture(0.12, 0.10, 0.07, 1)
                tabBtn.topLine:SetTexture(0.96, 0.78, 0.26, 1)
                tabBtn.topLine:Show()
                tabBtn.botLine:Hide()
                tabBtn:GetFontString():SetTextColor(0.96, 0.78, 0.26, 1)
            else
                tabBtn.bg:SetTexture(0.06, 0.05, 0.04, 0.95)
                tabBtn.topLine:Hide()
                tabBtn.botLine:SetTexture(0.35, 0.28, 0.14, 0.6)
                tabBtn.botLine:Show()
                tabBtn:GetFontString():SetTextColor(0.55, 0.50, 0.40, 1)
            end
        end
    end

    local function tab_OnClick(self)
        local prevTab = tabs[selectedTabIdx]
        if prevTab then prevTab:Hide() end
        selectedTabIdx = self:GetID()
        tabs[selectedTabIdx]:Show()
        PlaySound("gsTitleOptionOK")
        UpdateTabAppearance()
    end
    _G.tab_OnClick = tab_OnClick

    for i = 1, TAB_COUNT do
        local btn = CreateFrame("Button", "$parentTab"..i, mainFrame)
        mainFrame.buttons["tab"..i] = btn
        btn:SetID(i)
        btn:SetSize(TAB_W, TAB_H)

        if i == 1 then
            btn:SetPoint("TOPLEFT", mainFrame, "TOPLEFT", TAB_AREA_LEFT, TAB_TOP)
        else
            btn:SetPoint("LEFT", mainFrame.buttons["tab"..(i - 1)], "RIGHT", TAB_GAP, 0)
        end
        -- Last tab stretches to fill remaining space
        if i == TAB_COUNT then
            btn:SetPoint("RIGHT", mainFrame, "RIGHT", -10, 0)
        end

        -- Solid background
        local bg = btn:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints()
        bg:SetTexture(0.06, 0.05, 0.04, 0.95)
        btn.bg = bg

        -- Gold top line (active indicator, 2px)
        local topLine = btn:CreateTexture(nil, "OVERLAY")
        topLine:SetHeight(2)
        topLine:SetPoint("TOPLEFT", btn, "TOPLEFT", 0, 0)
        topLine:SetPoint("TOPRIGHT", btn, "TOPRIGHT", 0, 0)
        topLine:SetTexture(0.96, 0.78, 0.26, 1)
        topLine:Hide()
        btn.topLine = topLine

        -- Subtle bottom border (inactive indicator, 1px)
        local botLine = btn:CreateTexture(nil, "OVERLAY")
        botLine:SetHeight(1)
        botLine:SetPoint("BOTTOMLEFT", btn, "BOTTOMLEFT", 0, 0)
        botLine:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", 0, 0)
        botLine:SetTexture(0.35, 0.28, 0.14, 0.6)
        btn.botLine = botLine

        -- Left edge separator (skip first tab)
        if i > 1 then
            local sep = btn:CreateTexture(nil, "OVERLAY")
            sep:SetWidth(1)
            sep:SetPoint("TOPLEFT", btn, "TOPLEFT", 0, -3)
            sep:SetPoint("BOTTOMLEFT", btn, "BOTTOMLEFT", 0, 3)
            sep:SetTexture(0.3, 0.25, 0.15, 0.4)
        end

        -- Highlight on hover
        local htex = btn:CreateTexture(nil, "HIGHLIGHT")
        htex:SetAllPoints()
        htex:SetTexture(1, 1, 1, 0.06)
        btn:SetHighlightTexture(htex)

        -- Label
        local fs = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        fs:SetPoint("CENTER", 0, 0)
        fs:SetText(TAB_NAMES[i])
        fs:SetTextColor(0.55, 0.50, 0.40, 1)
        btn:SetFontString(fs)

        btn:SetScript("OnClick", tab_OnClick)

        -- Content frame for this tab (positioned below the tab row)
        local frame = CreateFrame("Frame", "$parentTab"..i.."Content", mainFrame)
        frame:SetPoint("TOPLEFT", TAB_AREA_LEFT, TAB_TOP - TAB_H)
        frame:SetPoint("BOTTOMRIGHT", -8, 36)
        frame:Hide()
        table.insert(tabs, frame)
    end

    -- Select first tab
    tab_OnClick(mainFrame.buttons["tab1"])
    mainFrame.tabs.preview = tabs[1]
    mainFrame.tabs.appearances = tabs[2]
    mainFrame.tabs.mounts = tabs[3]
    mainFrame.tabs.pets = tabs[4]
    mainFrame.tabs.combatPets = tabs[5]
    mainFrame.tabs.morph = tabs[6]
    mainFrame.tabs.settings = tabs[7]
end

---------------- SLOTS ----------------

mainFrame.slots = {}
mainFrame.selectedSlot = nil

local function getIndex(array, value)
    for i = 1, 10 do if array[i] == value then return i end end
    return nil
end

local function slot_OnShiftLeftClick(self)
    if self.itemId ~= nil then
        local _, link = GetItemInfo(self.itemId)
        if link then SELECTED_CHAT_FRAME:AddMessage("|cffF5C842<Transmorpher>|r: "..link.." ("..self.itemId..")")
        else SELECTED_CHAT_FRAME:AddMessage("|cffF5C842<Transmorpher>|r: Item cannot be used for transmogrification.") end
    end
end

local function slot_OnControlLeftClick(self)
    if self.itemId ~= nil then ns.ShowWowheadURLDialog(self.itemId) end
end

local function slot_OnLeftClick(self)
    local selectedSlot = mainFrame.selectedSlot
    if selectedSlot ~= nil then selectedSlot:UnlockHighlight() end
    -- Clear enchant slot highlight if any
    if mainFrame.selectedEnchantSlot then
        mainFrame.selectedEnchantSlot:UnlockHighlight()
        mainFrame.selectedEnchantSlot = nil
    end
    -- Clear enchant slot highlights
    if mainFrame.enchantSlots then
        for _, es in pairs(mainFrame.enchantSlots) do es:UnlockHighlight() end
    end
    -- Exit enchant browsing mode if active
    if mainFrame.tabs.preview.enchantMode then
        mainFrame.tabs.preview:ExitEnchantMode()
    end
    mainFrame.selectedSlot = self
    mainFrame.tabs.preview.subclassMenu:Update(self.slotName)
    -- Switch to Preview tab and show the item
    if self.itemId ~= nil then
        -- Explicitly switch to Preview tab using tab_OnClick
        tab_OnClick(mainFrame.buttons["tab1"])
        -- Try to find the item in the DB and update preview
        local found = false
        for subclass, items in pairs(ns.items[self.slotName] or {}) do
            for _, entry in ipairs(items) do
                local itemId = entry[1][1]
                if itemId == self.itemId then
                    mainFrame.tabs.preview.subclassMenu:Update(self.slotName)
                    mainFrame.tabs.preview.dropText:SetText(subclass)
                    mainFrame.tabs.preview:Update(self.slotName, subclass)
                    found = true
                    break
                end
            end
            if found then break end
        end
        -- Always try on the item in the dressing room
        mainFrame.dressingRoom:TryOn(self.itemId)
    end
    self:LockHighlight()
end

local function slot_OnRightClick(self)
    self:RemoveItem()
end

local function slot_OnClick(self, button)
    if button == "LeftButton" then
        if IsShiftKeyDown() then slot_OnShiftLeftClick(self)
        elseif IsControlKeyDown() then slot_OnControlLeftClick(self)
        else slot_OnLeftClick(self) end
        PlaySound("gsTitleOptionOK")
    elseif button == "RightButton" then slot_OnRightClick(self) end
end

local function slot_OnEnter(self)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    if self.isHiddenSlot then
        GameTooltip:AddLine(self.slotName)
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine("|cffFF6060Hidden (naked morph)|r", 1, 0.4, 0.4)
    elseif self.itemId == nil then
        GameTooltip:AddLine(self.slotName)
    else
        local _, link = GetItemInfo(self.itemId)
        if not link then
            GameTooltip:AddLine(self.slotName)
            GameTooltip:AddLine("Item #" .. self.itemId .. " (loading...)", 0.6, 0.6, 0.6)
        else
        GameTooltip:SetHyperlink(link)
        end
        if self.isMorphed then
            GameTooltip:AddLine(" ")
            GameTooltip:AddLine("|cffF5C842Transmogrified|r", 0.96, 0.78, 0.26)
        else
            local equippedId = GetEquippedItemForSlot(self.slotName)
            if equippedId and equippedId == self.itemId then
                GameTooltip:AddLine(" ")
                GameTooltip:AddLine("Equipped (not transmogrified)", 0.5, 0.5, 0.5)
            else
                GameTooltip:AddLine(" ")
                GameTooltip:AddLine("Previewing", 0.6, 0.8, 1.0)
            end
        end
    end
    GameTooltip:Show()
end

local function slot_OnLeave(self) GameTooltip:Hide() end

local function slot_Reset(self)
    -- If this slot is morphed, reset to the morphed item (with glow)
    if self.isMorphed and self.morphedItemId then
        self:SetItem(self.morphedItemId)
        ShowMorphGlow(self)
        return
    end
    -- Not morphed: show equipped gear (no glow)
    HideMorphGlow(self)
    local equippedId = GetEquippedItemForSlot(self.slotName)
    if equippedId then self:SetItem(equippedId) else self:RemoveItem() end
end

local function slot_RemoveItem(self)
    if self.itemId ~= nil then
        local wasMorphed = self.isMorphed
        self.isMorphed = false
        self.morphedItemId = nil
        HideMorphGlow(self)
        -- If this slot was actively morphed, tell the DLL to revert it
        if wasMorphed and slotToEquipSlotId[self.slotName] then
            local equippedId = GetEquippedItemForSlot(self.slotName)
            if equippedId then
                -- Morph slot back to equipped item (visually undoes the morph)
                SendMorphCommand("ITEM:" .. slotToEquipSlotId[self.slotName] .. ":" .. equippedId)
            end
            -- Also clear from saved state
            SendMorphCommand("RESET:" .. slotToEquipSlotId[self.slotName])
        end
        -- Restore the real equipped item in the UI
        local equippedId = GetEquippedItemForSlot(self.slotName)
        if equippedId then
            self:SetItem(equippedId)
        else
            self.itemId = nil
            self.textures.empty:Show() self.textures.item:Hide()
        end
        self:GetScript("OnEnter")(self)
        SyncDressingRoom()
    end
end

local function slot_SetItem(self, itemId)
    self.itemId = itemId
    ns.QueryItem(itemId, function(queriedItemId, success)
        if queriedItemId == self.itemId and success then
            local _, _, _, _, _, _, _, _, _, texture = GetItemInfo(queriedItemId)
            self.textures.empty:Hide()
            self.textures.item:SetTexture(texture)
            self.textures.item:Show()
            mainFrame.dressingRoom:TryOn(queriedItemId)
        end
    end)
end

-- Build slots
do
    for slotName, texturePath in pairs(slotTextures) do
        local slot = CreateFrame("Button", "$parentSlot"..slotName, mainFrame, "ItemButtonTemplate")
        slot:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        slot:SetFrameLevel(mainFrame.dressingRoom:GetFrameLevel() + 1)
        slot:SetScript("OnClick", function(self, button)
            -- Alt+click = apply morph for this slot
            if button == "LeftButton" and IsAltKeyDown() and self.itemId and slotToEquipSlotId[self.slotName] then
                if IsMorpherReady() then
                    -- Skip if the item is the same as equipped (not a real morph)
                    local equippedId = GetEquippedItemForSlot(self.slotName)
                    if equippedId and equippedId == self.itemId then
                        self.isMorphed = false
                        self.morphedItemId = nil
                        HideMorphGlow(self)
                        SELECTED_CHAT_FRAME:AddMessage("|cffF5C842<Transmorpher>|r: "..self.slotName.." already has this item equipped.")
                    else
                        SendMorphCommand("ITEM:" .. slotToEquipSlotId[self.slotName] .. ":" .. self.itemId)
                        self.isMorphed = true
                        self.morphedItemId = self.itemId
                        SELECTED_CHAT_FRAME:AddMessage("|cffF5C842<Transmorpher>|r: Morphed "..self.slotName.."!")
                        ShowMorphGlow(self)
                    end
                    SyncDressingRoom()
                else
                    SELECTED_CHAT_FRAME:AddMessage("|cffF5C842<Transmorpher>|r: |cffff0000DLL not loaded!|r")
                end
                PlaySound("gsTitleOptionOK")
                return
            end
            slot_OnClick(self, button)
        end)
        slot:SetScript("OnEnter", slot_OnEnter)
        slot:SetScript("OnLeave", slot_OnLeave)
        slot.slotName = slotName
        mainFrame.slots[slotName] = slot
        slot.textures = {}
        slot.textures.empty = slot:CreateTexture(nil, "BACKGROUND")
        slot.textures.empty:SetTexture(texturePath) slot.textures.empty:SetAllPoints()
        slot.textures.item = slot:CreateTexture(nil, "BACKGROUND")
        slot.textures.item:SetAllPoints() slot.textures.item:Hide()
        slot.Reset = slot_Reset
        slot.SetItem = slot_SetItem
        slot.RemoveItem = slot_RemoveItem
    end

    local slots = mainFrame.slots
    slots["Head"]:SetPoint("TOPLEFT", mainFrame.dressingRoom, "TOPLEFT", 16, -16)
    slots["Shoulder"]:SetPoint("TOP", slots["Head"], "BOTTOM", 0, -4)
    slots["Back"]:SetPoint("TOP", slots["Shoulder"], "BOTTOM", 0, -4)
    slots["Chest"]:SetPoint("TOP", slots["Back"], "BOTTOM", 0, -4)
    slots["Shirt"]:SetPoint("TOP", slots["Chest"], "BOTTOM", 0, -36)
    slots["Tabard"]:SetPoint("TOP", slots["Shirt"], "BOTTOM", 0, -4)
    slots["Wrist"]:SetPoint("TOP", slots["Tabard"], "BOTTOM", 0, -36)
    slots["Hands"]:SetPoint("TOPRIGHT", mainFrame.dressingRoom, "TOPRIGHT", -16, -16)
    slots["Waist"]:SetPoint("TOP", slots["Hands"], "BOTTOM", 0, -4)
    slots["Legs"]:SetPoint("TOP", slots["Waist"], "BOTTOM", 0, -4)
    slots["Feet"]:SetPoint("TOP", slots["Legs"], "BOTTOM", 0, -4)
    slots["Off-hand"]:SetPoint("BOTTOM", mainFrame.dressingRoom, "BOTTOM", 0, 16)
    slots["Main Hand"]:SetPoint("RIGHT", slots["Off-hand"], "LEFT", -4, 0)
    slots["Ranged"]:SetPoint("LEFT", slots["Off-hand"], "RIGHT", 4, 0)
end

-- ============================================================
-- SPECIAL SLOTS (Mount, Pet, Combat Pet) — vertical column under Feet
-- ============================================================
do
    mainFrame.specialSlots = {}
    local SLOT_SIZE = 37
    
    -- Helper function to create a special slot
    local function CreateSpecialSlot(slotName, tabIndex, emptyTexture)
        local slot = CreateFrame("Button", "$parentSpecialSlot"..slotName, mainFrame, "ItemButtonTemplate")
        slot:SetSize(SLOT_SIZE, SLOT_SIZE)
        slot:SetFrameLevel(mainFrame.dressingRoom:GetFrameLevel() + 1)
        slot.slotName = slotName
        slot.tabIndex = tabIndex
        
        -- Register for both left and right clicks
        slot:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        
        -- Empty slot texture
        slot.textures = {}
        slot.textures.empty = slot:CreateTexture(nil, "BACKGROUND")
        slot.textures.empty:SetTexture(emptyTexture)
        slot.textures.empty:SetAllPoints()
        
        -- Icon texture for morphed state
        slot.icon = slot:CreateTexture(nil, "ARTWORK")
        slot.icon:SetAllPoints()
        slot.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        slot.icon:Hide()
        
        -- Click handler to navigate to tab (left) or reset morph (right)
        slot:SetScript("OnClick", function(self, button)
            if button == "LeftButton" then
                tab_OnClick(mainFrame.buttons["tab"..self.tabIndex])
                PlaySound("gsTitleOptionOK")
            elseif button == "RightButton" then
                -- Right-click to reset this specific morph
                if IsMorpherReady() then
                    if self.slotName == "Mount" then
                        SendMorphCommand("MOUNT_RESET")
                        UpdateSpecialSlots()
                        SELECTED_CHAT_FRAME:AddMessage("|cffF5C842<Transmorpher>|r: Mount morph reset!")
                    elseif self.slotName == "Pet" then
                        SendMorphCommand("PET_RESET")
                        UpdateSpecialSlots()
                        SELECTED_CHAT_FRAME:AddMessage("|cffF5C842<Transmorpher>|r: Pet morph reset!")
                    elseif self.slotName == "Combat Pet" then
                        SendMorphCommand("HPET_RESET")
                        UpdateSpecialSlots()
                        SELECTED_CHAT_FRAME:AddMessage("|cffF5C842<Transmorpher>|r: Combat pet morph reset!")
                    elseif self.slotName == "Morph Form" then
                        SendMorphCommand("MORPH:0")
                        -- Immediately clear the state for instant visual update
                        if TransmorpherCharacterState then
                            TransmorpherCharacterState.Morph = nil
                        end
                        UpdatePreviewModel()
                        UpdateSpecialSlots()
                        SELECTED_CHAT_FRAME:AddMessage("|cffF5C842<Transmorpher>|r: Character morph reset!")
                    end
                    PlaySound("gsTitleOptionOK")
                end
            end
        end)
        
        -- Tooltip
        slot:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:ClearLines()
            if self.name then
                GameTooltip:AddLine(self.name, 1, 1, 1)
                if self.displayID then
                    GameTooltip:AddLine("Display ID: " .. self.displayID, 0.7, 0.7, 0.7)
                end
                GameTooltip:AddLine(" ")
                GameTooltip:AddLine("Left-click: Open " .. self.slotName .. " tab", 0.5, 0.8, 0.5)
                GameTooltip:AddLine("Right-click: Reset " .. self.slotName .. " morph", 1.0, 0.5, 0.5)
            else
                GameTooltip:AddLine("No " .. self.slotName .. " morphed", 0.7, 0.7, 0.7)
                GameTooltip:AddLine(" ")
                GameTooltip:AddLine("Click to open " .. self.slotName .. " tab", 0.5, 0.8, 0.5)
            end
            GameTooltip:Show()
        end)
        
        slot:SetScript("OnLeave", function(self)
            GameTooltip:Hide()
        end)
        
        return slot
    end
    
    -- Create the 4 special slots
    mainFrame.specialSlots.Mount = CreateSpecialSlot("Mount", 3, "Interface\\Icons\\Ability_Mount_RidingHorse")
    mainFrame.specialSlots.Pet = CreateSpecialSlot("Pet", 4, "Interface\\Icons\\INV_Box_PetCarrier_01")
    mainFrame.specialSlots.CombatPet = CreateSpecialSlot("Combat Pet", 5, "Interface\\Icons\\Ability_Hunter_BeastCall")
    mainFrame.specialSlots.MorphForm = CreateSpecialSlot("Morph Form", 6, "Interface\\Icons\\Spell_Shadow_Charm")
    
    -- Position them vertically under Feet slot with more spacing
    mainFrame.specialSlots.Mount:SetPoint("TOP", mainFrame.slots["Feet"], "BOTTOM", 0, -20)
    mainFrame.specialSlots.Pet:SetPoint("TOP", mainFrame.specialSlots.Mount, "BOTTOM", 0, -4)
    mainFrame.specialSlots.CombatPet:SetPoint("TOP", mainFrame.specialSlots.Pet, "BOTTOM", 0, -4)
    mainFrame.specialSlots.MorphForm:SetPoint("TOP", mainFrame.specialSlots.CombatPet, "BOTTOM", 0, -4)
end

-- ============================================================
-- EYE TOGGLE (HIDE SLOT) — eye icon at top-right corner of each slot.
-- Clicking hides the equipped item (naked morph for that slot).
-- Preserves morph state: unhiding restores the morph that was active.
-- ============================================================
do
    local EYE_SIZE = 18

    for _, slotName in pairs(slotOrder) do
        local slot = mainFrame.slots[slotName]
        if not slotToEquipSlotId[slotName] then break end -- safety

        local eyeBtn = CreateFrame("Button", nil, slot)
        eyeBtn:SetSize(EYE_SIZE, EYE_SIZE)
        eyeBtn:SetFrameLevel(slot:GetFrameLevel() + 5)

        -- Consistent position: top-right corner of every slot, overlapping outward
        eyeBtn:SetPoint("CENTER", slot, "TOPRIGHT", 2, 2)

        -- Dark circular backdrop for contrast
        local bg = eyeBtn:CreateTexture(nil, "BACKGROUND")
        bg:SetPoint("CENTER")
        bg:SetSize(EYE_SIZE + 4, EYE_SIZE + 4)
        bg:SetTexture("Interface\\CHARACTERFRAME\\TempPortraitAlphaMask")
        bg:SetVertexColor(0, 0, 0, 0.7)
        eyeBtn.bg = bg

        -- Eye icon texture (golden eye)
        local eyeTex = eyeBtn:CreateTexture(nil, "ARTWORK")
        eyeTex:SetPoint("CENTER")
        eyeTex:SetSize(EYE_SIZE, EYE_SIZE)
        eyeTex:SetTexture("Interface\\Minimap\\Tracking\\None")
        eyeTex:SetVertexColor(1, 0.85, 0.35, 1)
        eyeBtn.eyeTex = eyeTex

        -- Hidden overlay: red X (slightly larger for clarity)
        local hiddenTex = eyeBtn:CreateTexture(nil, "OVERLAY")
        hiddenTex:SetPoint("CENTER")
        hiddenTex:SetSize(EYE_SIZE + 4, EYE_SIZE + 4)
        hiddenTex:SetTexture("Interface\\RaidFrame\\ReadyCheck-NotReady")
        hiddenTex:Hide()
        eyeBtn.hiddenTex = hiddenTex

        eyeBtn.isHidden   = false
        eyeBtn.slotName   = slotName
        -- Saved morph state before hiding (so unhide restores it)
        eyeBtn.wasMorphed  = false
        eyeBtn.savedMorphId = nil

        eyeBtn:SetScript("OnClick", function(self)
            local parentSlot = mainFrame.slots[self.slotName]
            local equipSlotId = slotToEquipSlotId[self.slotName]
            if not equipSlotId then return end

            if not self.isHidden then
                -- ---- HIDE this slot ----
                if IsMorpherReady() then
                    -- Save whatever morph was active BEFORE hiding
                    self.wasMorphed  = parentSlot.isMorphed or false
                    self.savedMorphId = parentSlot.morphedItemId

                    SendMorphCommand("ITEM:" .. equipSlotId .. ":0")
                    parentSlot.isMorphed    = true
                    parentSlot.morphedItemId = 0
                    parentSlot.isHiddenSlot  = true
                    ShowMorphGlow(parentSlot)
                    self.isHidden = true
                    self.eyeTex:SetVertexColor(0.4, 0.4, 0.4, 0.5)
                    self.hiddenTex:Show()
                    SyncDressingRoom()
                    SELECTED_CHAT_FRAME:AddMessage("|cffF5C842<Transmorpher>|r: " .. self.slotName .. " hidden!")
                end
            else
                -- ---- SHOW this slot again ----
                if IsMorpherReady() then
                    parentSlot.isHiddenSlot = false

                    if self.wasMorphed and self.savedMorphId and self.savedMorphId ~= 0 then
                        -- Restore the morph that was active before hiding
                        SendMorphCommand("ITEM:" .. equipSlotId .. ":" .. self.savedMorphId)
                        parentSlot.isMorphed    = true
                        parentSlot.morphedItemId = self.savedMorphId
                        parentSlot:SetItem(self.savedMorphId)
                        ShowMorphGlow(parentSlot)
                        SELECTED_CHAT_FRAME:AddMessage("|cffF5C842<Transmorpher>|r: " .. self.slotName .. " morph restored!")
                    else
                        -- No morph was active — DLL's RESET writes g_origItems back
                        SendMorphCommand("RESET:" .. equipSlotId)
                        parentSlot.isMorphed    = false
                        parentSlot.morphedItemId = nil
                        HideMorphGlow(parentSlot)
                        local equippedId = GetEquippedItemForSlot(self.slotName)
                        if equippedId then
                            parentSlot:SetItem(equippedId)
                        end
                        SELECTED_CHAT_FRAME:AddMessage("|cffF5C842<Transmorpher>|r: " .. self.slotName .. " restored!")
                    end

                    self.wasMorphed   = false
                    self.savedMorphId = nil
                    self.isHidden = false
                    self.eyeTex:SetVertexColor(1, 0.85, 0.35, 1)
                    self.hiddenTex:Hide()
                    SyncDressingRoom()
                end
            end
            PlaySound("gsTitleOptionOK")
        end)

        eyeBtn:SetScript("OnEnter", function(self)
            self.eyeTex:SetVertexColor(1, 1, 0.6, 1)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            if self.isHidden then
                GameTooltip:AddLine("|cffF5C842Show " .. self.slotName .. "|r")
                GameTooltip:AddLine("Click to restore this slot's appearance", 0.7, 0.7, 0.7)
            else
                GameTooltip:AddLine("|cffF5C842Hide " .. self.slotName .. "|r")
                GameTooltip:AddLine("Click to hide this slot (naked morph)", 0.7, 0.7, 0.7)
            end
            GameTooltip:Show()
        end)
        eyeBtn:SetScript("OnLeave", function(self)
            if self.isHidden then
                self.eyeTex:SetVertexColor(0.4, 0.4, 0.4, 0.5)
            else
                self.eyeTex:SetVertexColor(1, 0.85, 0.35, 1)
            end
            GameTooltip:Hide()
        end)

        slot.eyeButton = eyeBtn
    end
end

-- ============================================================
-- Enchant icon mapper — picks a thematic icon based on name keywords
-- ============================================================
local ENCHANT_ICON_MAP = {
    { kw = "fiery",       icon = "Interface\\Icons\\Spell_Fire_FlameShock" },
    { kw = "fire",        icon = "Interface\\Icons\\Spell_Fire_FlameShock" },
    { kw = "sunfire",     icon = "Interface\\Icons\\Spell_Fire_SunKey" },
    { kw = "berserking",  icon = "Interface\\Icons\\Spell_Nature_Strength" },
    { kw = "mongoose",    icon = "Interface\\Icons\\Spell_Nature_Lightning" },
    { kw = "executioner", icon = "Interface\\Icons\\Ability_Warrior_Decisivestrike" },
    { kw = "icy",         icon = "Interface\\Icons\\Spell_Frost_FrostShock" },
    { kw = "frost",       icon = "Interface\\Icons\\Spell_Frost_FrostShock" },
    { kw = "deathfrost",  icon = "Interface\\Icons\\Spell_Frost_FrostBolt02" },
    { kw = "icebreaker",  icon = "Interface\\Icons\\Spell_Frost_FrostBolt02" },
    { kw = "lifestealing",icon = "Interface\\Icons\\Spell_Shadow_LifeDrain02" },
    { kw = "soulfrost",   icon = "Interface\\Icons\\Spell_Shadow_ChillTouch" },
    { kw = "unholy",      icon = "Interface\\Icons\\Spell_Shadow_ShadowBolt" },
    { kw = "shadow",      icon = "Interface\\Icons\\Spell_Shadow_ShadowBolt" },
    { kw = "fallen",      icon = "Interface\\Icons\\Spell_Shadow_AntiShadow" },
    { kw = "nerubian",    icon = "Interface\\Icons\\Spell_Shadow_AntiShadow" },
    { kw = "crusader",    icon = "Interface\\Icons\\Spell_Holy_HolyBolt" },
    { kw = "holy",        icon = "Interface\\Icons\\Spell_Holy_GreaterHeal" },
    { kw = "lifeward",    icon = "Interface\\Icons\\Spell_Holy_GreaterHeal" },
    { kw = "spellpower",  icon = "Interface\\Icons\\Spell_Holy_MindSooth" },
    { kw = "savagery",    icon = "Interface\\Icons\\Ability_Druid_Mangle2" },
    { kw = "agility",     icon = "Interface\\Icons\\Spell_Nature_Invisibilty" },
    { kw = "battlemaster",icon = "Interface\\Icons\\Spell_Holy_AshesToAshes" },
    { kw = "blood",       icon = "Interface\\Icons\\Spell_DeathKnight_BloodPresence" },
    { kw = "rune",        icon = "Interface\\Icons\\Spell_DeathKnight_FrostPresence" },
    { kw = "razorice",    icon = "Interface\\Icons\\Spell_Frost_FrostArmor" },
    { kw = "cinderglacier",icon = "Interface\\Icons\\Spell_Frost_ChainsOfIce" },
    { kw = "lichbane",    icon = "Interface\\Icons\\Spell_Shadow_SoulLeech_3" },
    { kw = "stoneskin",   icon = "Interface\\Icons\\Spell_DeathKnight_AntiMagicZone" },
    { kw = "swordbreaking",icon = "Interface\\Icons\\INV_Sword_62" },
    { kw = "spellshattering",icon = "Interface\\Icons\\Spell_Arcane_MassDispel" },
    { kw = "spellbreak",  icon = "Interface\\Icons\\Spell_Arcane_MassDispel" },
    { kw = "titanium",    icon = "Interface\\Icons\\INV_Ingot_Titanium" },
    { kw = "giant",       icon = "Interface\\Icons\\Ability_Warrior_Cleave" },
    { kw = "massacre",    icon = "Interface\\Icons\\Ability_Warrior_Bladestorm" },
    { kw = "demon",       icon = "Interface\\Icons\\Spell_Shadow_Metamorphosis" },
    { kw = "adamantite",  icon = "Interface\\Icons\\INV_Ingot_Adamantite" },
    { kw = "chain",       icon = "Interface\\Icons\\INV_Belt_13" },
    { kw = "plating",     icon = "Interface\\Icons\\INV_Shield_35" },
}
local ENCHANT_ICON_DEFAULT = "Interface\\Icons\\INV_Enchant_FormulaEpic_01"

local function GetEnchantIcon(enchantName)
    if not enchantName then return ENCHANT_ICON_DEFAULT end
    local lower = enchantName:lower()
    for _, entry in ipairs(ENCHANT_ICON_MAP) do
        if lower:find(entry.kw, 1, true) then return entry.icon end
    end
    return ENCHANT_ICON_DEFAULT
end

-- Build enchant slots (above Main Hand and Off-hand)
mainFrame.enchantSlots = {}
do
    local enchantSlotInfo = {
        ["Enchant MH"] = { anchor = "Main Hand", cmd = "ENCHANT_MH" },
        ["Enchant OH"] = { anchor = "Off-hand",  cmd = "ENCHANT_OH" },
    }

    for _, eName in ipairs(enchantSlotNames) do
        local info = enchantSlotInfo[eName]
        local eSlot = CreateFrame("Button", "$parentEnchant" .. eName:gsub(" ", ""), mainFrame, "ItemButtonTemplate")
        eSlot:SetSize(28, 28)
        eSlot:SetFrameLevel(mainFrame.dressingRoom:GetFrameLevel() + 2)
        eSlot:SetPoint("BOTTOM", mainFrame.slots[info.anchor], "TOP", 0, 2)
        eSlot.slotName = eName
        eSlot.cmd = info.cmd   -- "ENCHANT_MH" or "ENCHANT_OH" for DLL commands
        eSlot.enchantId = nil
        eSlot.enchantName = nil

        eSlot.textures = {}

        -- Background: empty slot icon (weapon silhouette, tinted purple)
        local emptyTex = eSlot:CreateTexture(nil, "BACKGROUND")
        emptyTex:SetAllPoints()
        emptyTex:SetTexture("Interface\\Paperdoll\\ui-paperdoll-slot-mainhand")
        emptyTex:SetVertexColor(0.6, 0.4, 1.0, 0.5)
        eSlot.textures.empty = emptyTex

        -- Enchant icon (shows the actual enchant spell icon when set)
        local enchIcon = eSlot:CreateTexture(nil, "ARTWORK")
        enchIcon:SetPoint("TOPLEFT", 2, -2)
        enchIcon:SetPoint("BOTTOMRIGHT", -2, 2)
        enchIcon:SetTexCoord(0.08, 0.92, 0.08, 0.92)  -- crop default icon border
        enchIcon:Hide()
        eSlot.textures.enchantIcon = enchIcon

        -- Overlay glow for when an enchant is set
        local glowTex = eSlot:CreateTexture(nil, "OVERLAY")
        glowTex:SetPoint("TOPLEFT", -4, 4)
        glowTex:SetPoint("BOTTOMRIGHT", 4, -4)
        glowTex:SetTexture("Interface\\Buttons\\UI-ActionButton-Border")
        glowTex:SetBlendMode("ADD")
        glowTex:SetVertexColor(0.85, 0.70, 0.25, 0.7)
        glowTex:Hide()
        eSlot.textures.glow = glowTex

        -- Label text
        local labelTex = eSlot:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        labelTex:SetPoint("TOP", eSlot, "BOTTOM", 0, -1)
        labelTex:SetText("|cffC0A060E|r")
        labelTex:SetFont("Fonts\\FRIZQT__.TTF", 8)
        eSlot.textures.label = labelTex

        eSlot.SetEnchant = function(self, enchantId, enchantName)
            self.enchantId = enchantId
            self.enchantName = enchantName
            -- Show the enchant-specific icon
            local iconPath = GetEnchantIcon(enchantName)
            self.textures.enchantIcon:SetTexture(iconPath)
            self.textures.enchantIcon:Show()
            self.textures.empty:Hide()
            self.textures.glow:Show()
        end

        eSlot.RemoveEnchant = function(self)
            self.enchantId = nil
            self.enchantName = nil
            self.textures.enchantIcon:Hide()
            self.textures.empty:SetVertexColor(0.6, 0.4, 1.0, 0.5)
            self.textures.empty:Show()
            self.textures.glow:Hide()
        end

        eSlot:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        eSlot:SetScript("OnClick", function(self, button)
            if button == "LeftButton" then
                if IsAltKeyDown() and self.enchantId then
                    -- Alt+click = apply enchant morph immediately
                    if IsMorpherReady() then
                        SendMorphCommand(info.cmd .. ":" .. self.enchantId)
                        self.isMorphed = true
                        SELECTED_CHAT_FRAME:AddMessage("|cffF5C842<Transmorpher>|r: Enchant applied to " .. eName .. "!")
                        ShowMorphGlow(self, "orange")
                    else
                        SELECTED_CHAT_FRAME:AddMessage("|cffF5C842<Transmorpher>|r: |cffff0000DLL not loaded!|r")
                    end
                    PlaySound("gsTitleOptionOK")
                    return
                end
                -- Regular click = select this enchant slot so Items Preview shows enchants
                local selectedSlot = mainFrame.selectedSlot
                if selectedSlot then selectedSlot:UnlockHighlight() end
                -- Unselect any enchant slot highlight
                for _, es in pairs(mainFrame.enchantSlots) do es:UnlockHighlight() end
                mainFrame.selectedSlot = nil
                mainFrame.selectedEnchantSlot = self
                self:LockHighlight()
                -- Switch to Items Preview tab and enter enchant mode
                tab_OnClick(mainFrame.buttons["tab1"])
                if mainFrame.tabs.preview:IsShown() then
                    mainFrame.tabs.preview:UpdateEnchantMode(eName)
                end
                PlaySound("gsTitleOptionOK")
            elseif button == "RightButton" then
                -- If this enchant was morphed, tell the DLL to revert just this hand
                if self.isMorphed then
                    if self.cmd == "ENCHANT_MH" then
                        SendMorphCommand("ENCHANT_RESET_MH")
                        -- Clear from weapon set
                        local setKey = GetWeaponSetKey()
                        if TransmorpherCharacterState.WeaponSets[setKey] then
                            TransmorpherCharacterState.WeaponSets[setKey].EnchantMH = nil
                        end
                    elseif self.cmd == "ENCHANT_OH" then
                        SendMorphCommand("ENCHANT_RESET_OH")
                        -- Clear from weapon set
                        local setKey = GetWeaponSetKey()
                        if TransmorpherCharacterState.WeaponSets[setKey] then
                            TransmorpherCharacterState.WeaponSets[setKey].EnchantOH = nil
                        end
                    end
                end
                self.isMorphed = false
                self:RemoveEnchant()
                HideMorphGlow(self)
                PlaySound("gsTitleOptionOK")
            end
        end)

        eSlot:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            if self.enchantId then
                GameTooltip:AddLine("|cffF5C842" .. (self.enchantName or "Enchant") .. "|r")
                GameTooltip:AddLine("Enchant ID: " .. self.enchantId, 0.7, 0.7, 0.7)
                GameTooltip:AddLine(" ")
                GameTooltip:AddLine("Alt+Click to apply enchant morph", 0.5, 0.8, 0.5)
                GameTooltip:AddLine("Right-click to remove", 0.8, 0.5, 0.5)
            else
                GameTooltip:AddLine(eName)
                GameTooltip:AddLine("Click to browse enchant effects", 0.7, 0.7, 0.7)
            end
            GameTooltip:Show()
        end)
        eSlot:SetScript("OnLeave", function() GameTooltip:Hide() end)

        mainFrame.enchantSlots[eName] = eSlot
    end
end

------- Hooks for slots and dressing room -------

local function btnReset_Hook()
    mainFrame.dressingRoom:Undress()
    for _, slot in pairs(mainFrame.slots) do
        if slot.slotName == rangedSlot and ("DRUIDSHAMANPALADINDEATHKNIGHT"):find(classFileName) then
            if not slot.isMorphed then slot:RemoveItem() end
        else slot:Reset() end  -- slot_Reset already respects .isMorphed
    end
    -- Rebuild dressing room from current slot state (morphed items preserved)
    for _, slot in pairs(mainFrame.slots) do
        if slot.itemId ~= nil then mainFrame.dressingRoom:TryOn(slot.itemId) end
    end
    if mainFrame.dressingRoom.shadowformEnabled then mainFrame.dressingRoom:EnableShadowform() end
end

local function btnUndress_Hook()
    for _, slot in pairs(mainFrame.slots) do
        slot.itemId = nil
        slot.textures.empty:Show() slot.textures.item:Hide()
        HideMorphGlow(slot)
    end
end

local function tryOnFromSlots(dressUpModel)
    for _, slot in pairs(mainFrame.slots) do
        if slot.itemId ~= nil then dressUpModel:TryOn(slot.itemId) end
    end
end

local function dressingRoom_OnShow(self)
    self:Reset()
    -- If any slot has a morphed item, show the morphed look; otherwise show equipped
    local hasMorphedItems = false
    for _, slot in pairs(mainFrame.slots) do
        if slot.isMorphed and slot.morphedItemId then
            hasMorphedItems = true
            break
        end
    end
    if hasMorphedItems then
        self:Undress()
        for _, slot in pairs(mainFrame.slots) do
            if slot.itemId then self:TryOn(slot.itemId) end
        end
    else
        self:Undress()
        tryOnFromSlots(self)
    end
    if self.shadowformEnabled then self:EnableShadowform() end
end

mainFrame.slots[defaultSlot]:SetScript("OnShow", function(self)
    self:SetScript("OnShow", nil)
    mainFrame.buttons.reset:HookScript("OnClick", btnReset_Hook)
    mainFrame.dressingRoom:HookScript("OnShow", dressingRoom_OnShow)
    dressingRoom_OnShow(mainFrame.dressingRoom)
    btnReset_Hook()
    mainFrame.buttons.undress:HookScript("OnClick", btnUndress_Hook)
    self:Click("LeftButton")
end)

---------------- PREVIEW TAB ----------------

mainFrame.tabs.preview.list = ns.CreatePreviewList(mainFrame.tabs.preview)
mainFrame.tabs.preview.slider = CreateFrame("Slider", "$parentSlider", mainFrame.tabs.preview, "UIPanelScrollBarTemplateLightBorder")

do
    local previewTab = mainFrame.tabs.preview
    local list = mainFrame.tabs.preview.list
    local slider = mainFrame.tabs.preview.slider

    -- ======== TOP TOOLBAR: Search bar (left) + Custom dropdown (right) ========

    -- Dropdown container (right side, fixed width)
    local dropContainer = CreateFrame("Frame", nil, previewTab)
    previewTab.dropContainer = dropContainer
    dropContainer:SetSize(170, 26)
    dropContainer:SetPoint("TOPRIGHT", -6, -2)
    dropContainer:SetBackdrop({
        bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 12,
        insets = { left = 3, right = 3, top = 3, bottom = 3 }
    })
    dropContainer:SetBackdropColor(0.06, 0.05, 0.03, 0.95)
    dropContainer:SetBackdropBorderColor(0.60, 0.50, 0.18, 0.8)

    -- Dropdown button (the clickable label + arrow inside the container)
    local dropBtn = CreateFrame("Button", "$parentSubDropBtn", dropContainer)
    previewTab.dropBtn = dropBtn
    dropBtn:SetAllPoints()
    dropBtn:EnableMouse(true)

    local dropText = dropBtn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    previewTab.dropText = dropText
    dropText:SetPoint("LEFT", 8, 0)
    dropText:SetPoint("RIGHT", -20, 0)
    dropText:SetJustifyH("LEFT")
    dropText:SetTextColor(0.95, 0.88, 0.65)
    dropText:SetText("Mail")

    local dropArrow = dropBtn:CreateTexture(nil, "OVERLAY")
    previewTab.dropArrow = dropArrow
    dropArrow:SetSize(14, 14)
    dropArrow:SetPoint("RIGHT", -4, 0)
    dropArrow:SetTexture("Interface\\ChatFrame\\ChatFrameExpandArrow")
    dropArrow:SetVertexColor(0.80, 0.65, 0.22)

    -- Hover highlight on dropdown
    dropBtn:SetScript("OnEnter", function(self)
        dropContainer:SetBackdropBorderColor(0.80, 0.65, 0.22, 1)
    end)
    dropBtn:SetScript("OnLeave", function(self)
        dropContainer:SetBackdropBorderColor(0.60, 0.50, 0.18, 0.8)
    end)

    -- Dropdown list (shown on click)
    local dropList = CreateFrame("Frame", "$parentSubDropList", previewTab)
    previewTab.dropList = dropList
    dropList:SetPoint("TOPLEFT", dropContainer, "BOTTOMLEFT", 0, 2)
    dropList:SetPoint("TOPRIGHT", dropContainer, "BOTTOMRIGHT", 0, 2)
    dropList:SetBackdrop({
        bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 12,
        insets = { left = 2, right = 2, top = 2, bottom = 2 }
    })
    dropList:SetBackdropColor(0.06, 0.05, 0.03, 0.97)
    dropList:SetBackdropBorderColor(0.80, 0.65, 0.22, 0.9)
    dropList:SetFrameStrata("DIALOG")
    dropList:Hide()

    local DROP_ROW_H = 20
    previewTab.DROP_ROW_H = DROP_ROW_H
    local dropListButtons = {}
    previewTab.dropListButtons = dropListButtons

    -- Search bar container (left side, flexible width)
    local searchContainer = CreateFrame("Frame", nil, previewTab)
    searchContainer:SetPoint("TOPLEFT", 6, -2)
    searchContainer:SetPoint("RIGHT", dropContainer, "LEFT", -6, 0)
    searchContainer:SetHeight(26)
    searchContainer:SetBackdrop({
        bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 12,
        insets = { left = 3, right = 3, top = 3, bottom = 3 }
    })
    searchContainer:SetBackdropColor(0.06, 0.05, 0.03, 0.95)
    searchContainer:SetBackdropBorderColor(0.60, 0.50, 0.18, 0.8)

    local searchIcon = searchContainer:CreateTexture(nil, "OVERLAY")
    searchIcon:SetSize(14, 14)
    searchIcon:SetPoint("LEFT", 6, 0)
    searchIcon:SetTexture("Interface\\Common\\UI-Searchbox-Icon")
    searchIcon:SetVertexColor(0.80, 0.65, 0.22)

    local searchBox = CreateFrame("EditBox", "$parentPreviewSearch", searchContainer)
    searchBox:SetPoint("LEFT", searchIcon, "RIGHT", 4, 0)
    searchBox:SetPoint("RIGHT", -24, 0)
    searchBox:SetHeight(18)
    searchBox:SetAutoFocus(false)
    searchBox:SetMaxLetters(60)
    searchBox:SetFont("Fonts\\FRIZQT__.TTF", 11)
    searchBox:SetTextColor(0.95, 0.88, 0.65)
    searchBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)

    local searchPlaceholder = searchBox:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    searchPlaceholder:SetPoint("LEFT", 2, 0)
    searchPlaceholder:SetText("Search by name or item ID...")
    searchBox:SetScript("OnEditFocusGained", function() searchPlaceholder:Hide() end)
    searchBox:SetScript("OnEditFocusLost", function(self)
        if self:GetText() == "" then searchPlaceholder:Show() end
    end)

    local searchClear = CreateFrame("Button", nil, searchContainer)
    searchClear:SetSize(14, 14)
    searchClear:SetPoint("RIGHT", -4, 0)
    searchClear:SetNormalTexture("Interface\\FriendsFrame\\ClearBroadcastIcon")
    searchClear:SetAlpha(0.5)
    searchClear:Hide()
    searchClear:SetScript("OnEnter", function(self) self:SetAlpha(1) end)
    searchClear:SetScript("OnLeave", function(self) self:SetAlpha(0.5) end)
    searchClear:SetScript("OnClick", function()
        searchBox:SetText("")
        searchBox:ClearFocus()
        searchPlaceholder:Show()
        searchClear:Hide()
        previewTab.searchQuery = ""
    end)

    -- Search state
    previewTab.searchQuery = ""
    previewTab.searchResults = nil  -- nil = no filter active

    list:SetPoint("TOPLEFT", 0, -30) list:SetSize(601, 367)

    local label = list:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    label:SetPoint("TOP", list, "BOTTOM", 0, -5)
    label:SetJustifyH("CENTER") label:SetHeight(10)
    label:SetTextColor(0.85, 0.70, 0.40)

    slider:SetPoint("TOPRIGHT", -6, -21) slider:SetPoint("BOTTOMRIGHT", -6, 21)
    slider:EnableMouseWheel(true)
    slider:SetScript("OnMouseWheel", function(self, delta) self:SetValue(self:GetValue() - delta) end)
    slider:SetScript("OnMinMaxChanged", function(self, min, max)
        label:SetText(("Page: %s/%s"):format(self:GetValue(), max))
    end)

    slider.buttons = {}
    slider.buttons.up = _G[slider:GetName() .. "ScrollUpButton"]
    slider.buttons.down = _G[slider:GetName() .. "ScrollDownButton"]
    slider.buttons.up:SetScript("OnClick", function() slider:SetValue(slider:GetValue() - 1) PlaySound("gsTitleOptionOK") end)
    slider.buttons.down:SetScript("OnClick", function() slider:SetValue(slider:GetValue() + 1) PlaySound("gsTitleOptionOK") end)

    list:EnableMouseWheel(true)
    list:SetScript("OnMouseWheel", function(self, delta) slider:SetValue(slider:GetValue() - delta) end)

    slider:SetScript("OnValueChanged", function(self, value)
        local _, max = self:GetMinMaxValues()
        label:SetText(("Page: %s/%s"):format(value, max))
    end)

    slider:SetMinMaxValues(0, 0) slider:SetValueStep(1)

---------------- Preview list logic ----------------

    local slotSubclassPage = {}
    for slot, _ in pairs(mainFrame.slots) do slotSubclassPage[slot] = {} end

    local currSlot, currSubclass = defaultSlot, defaultArmorSubclass[classFileName]
    local records

    -- Hair hiding functionality removed

    -- Core update function (with search filtering support)
    previewTab.Update = function(self, slot, subclass)
        slotSubclassPage[currSlot][currSubclass] = slider:GetValue() > 0 and slider:GetValue() or 1
        currSlot = slot currSubclass = subclass
        records = ns.GetSubclassRecords(slot, subclass)
        if not records then records = {} end

        -- Build filtered records based on search
        local query = previewTab.searchQuery or ""
        local filteredRecords = {}
        local filteredItemIds = {}
        local selectedItemId

        if query ~= "" then
            local lowerQ = query:lower()
            local numQ = tonumber(query)
            for i = 1, #records do
                local ids = records[i][1]
                local names = records[i][2]
                local match = false
                for j = 1, #ids do
                    if numQ and ids[j] == numQ then match = true; break end
                    if names[j] and names[j]:lower():find(lowerQ, 1, true) then match = true; break end
                end
                if match then
                    table.insert(filteredRecords, records[i])
                    table.insert(filteredItemIds, ids[1])
                    if selectedItemId == nil and mainFrame.slots[slot].itemId ~= nil and arrayHasValue(ids, mainFrame.slots[slot].itemId) then
                        selectedItemId = ids[1]
                    end
                end
            end
            -- Replace records reference for tooltip/click handlers
            records = filteredRecords
        else
            for i = 1, #records do
                local ids = records[i][1]
                table.insert(filteredItemIds, ids[1])
                if selectedItemId == nil and mainFrame.slots[slot].itemId ~= nil and arrayHasValue(ids, mainFrame.slots[slot].itemId) then
                    selectedItemId = ids[1]
                end
            end
        end

        list:SetItems(filteredItemIds)
        if selectedItemId ~= nil then list:SelectByItemId(selectedItemId) end

        -- Only setup model + paginate if there are items to show
        if #filteredItemIds > 0 then
            local setup = ns.GetPreviewSetup(previewSetupVersion, raceFileName, sex, slot, subclass)
            list:SetupModel(setup.width, setup.height, setup.x, setup.y, setup.z, setup.facing, setup.sequence)

            list:TryOn(nil)
            local page = 1
            if query == "" then
                page = slotSubclassPage[slot][subclass] ~= nil and slotSubclassPage[slot][subclass] or 1
            end
            local pageCount = list:GetPageCount()
            if pageCount < 1 then pageCount = 1 end
            if page > pageCount then page = pageCount end
            slider:SetMinMaxValues(1, pageCount)
            if slider:GetValue() ~= page then slider:SetValue(page)
            else list:SetPage(page) list:Update() end
        else
            slider:SetMinMaxValues(1, 1)
            slider:SetValue(1)
        end
    end

    previewTab:SetScript("OnShow", function(self) self:Update(currSlot, currSubclass) end)

    -- Search bar event handlers
    local searchTimer = CreateFrame("Frame")
    searchTimer:Hide()
    searchTimer.elapsed = 0
    searchTimer:SetScript("OnUpdate", function(self, dt)
        self.elapsed = self.elapsed + dt
        if self.elapsed >= 0.3 then
            self:Hide()
            previewTab:Update(currSlot, currSubclass)
        end
    end)

    searchBox:SetScript("OnTextChanged", function(self)
        local text = self:GetText()
        previewTab.searchQuery = text
        if text ~= "" then searchClear:Show(); searchPlaceholder:Hide()
        else searchClear:Hide() end
        -- Debounce: wait 0.3s after last keystroke
        searchTimer.elapsed = 0
        searchTimer:Show()
    end)
    searchBox:SetScript("OnEnterPressed", function(self)
        searchTimer:Hide()
        previewTab:Update(currSlot, currSubclass)
        self:ClearFocus()
    end)

    slider:HookScript("OnValueChanged", function(self, value)
        if previewTab.enchantMode then return end
        list:SetPage(value)
        if #list.itemIds > 0 then list:Update() end
    end)

    local selectedInRecord = {}
    local enteredButton
    local tabDummy = CreateFrame("Button", addon.."PreviewListTabDummy", previewTab)

    list.onEnter = function(self)
        local recordIndex = self:GetParent().itemIndex
        if not records or not records[recordIndex] then return end
        local ids = records[recordIndex][1]
        local names = records[recordIndex][2]
        GameTooltip:Hide() GameTooltip:SetOwner(self, "ANCHOR_TOPLEFT") GameTooltip:ClearLines()
        GameTooltip:AddLine("This appearance is provided by:", 1, 1, 1) GameTooltip:AddLine(" ")
        local selectedIndex = selectedInRecord[ids[1]] ~= nil and selectedInRecord[ids[1]] or 1
        local selSlotItemId = mainFrame.selectedSlot and mainFrame.selectedSlot.itemId
        for i, id in ipairs(ids) do
            GameTooltip:AddLine((i == selectedIndex and "> " or "- ")..names[i]..(id == selSlotItemId and " *"or ""))
        end
        GameTooltip:Show()
        SetOverrideBindingClick(tabDummy, true, "TAB", tabDummy:GetName(), "RightButton")
        enteredButton = self
    end

    list.onLeave = function(self)
        ClearOverrideBindings(tabDummy)
        GameTooltip:ClearLines() GameTooltip:Hide() enteredButton = nil
    end

    tabDummy:SetScript("OnClick", function()
        if enteredButton ~= nil then
            local recordIndex = enteredButton:GetParent().itemIndex
            local ids = records[recordIndex][1]
            if #ids > 1 then
                if selectedInRecord[ids[1]] == nil then selectedInRecord[ids[1]] = 2
                else selectedInRecord[ids[1]] = selectedInRecord[ids[1]] < #ids and selectedInRecord[ids[1]] + 1 or 1 end
            end
            list.onEnter(enteredButton)
        end
    end)

    list.onItemClick = function(self, button)
        local recordIndex = self:GetParent().itemIndex
        if not records or not records[recordIndex] then return end
        local ids = records[recordIndex][1]
        local selectedIndex = selectedInRecord[ids[1]] ~= nil and selectedInRecord[ids[1]] or 1
        local itemId = ids[selectedIndex]
        if IsShiftKeyDown() then
            local names = records[recordIndex][2]
            local color = names[selectedIndex]:sub(1, 10)
            local name = names[selectedIndex]:sub(11, -3)
            SELECTED_CHAT_FRAME:AddMessage("|cffF5C842<Transmorpher>|r: "..color.."\124Hitem:"..itemId..":::::::|h["..name.."]\124h\124r".." ("..itemId..")")
        elseif IsControlKeyDown() then
            ns.ShowWowheadURLDialog(itemId)
        else
            if mainFrame.selectedSlot then
                mainFrame.selectedSlot:SetItem(itemId)
                -- User is previewing a different item: temporarily hide the morph glow.
                -- Reset Preview will restore the morphed item + glow if still morphed.
                HideMorphGlow(mainFrame.selectedSlot)
            end
        end
        list.onEnter(self)
    end

    -- ============================================================
    -- ENCHANT BROWSING MODE
    -- When an enchant slot is selected, replace the item list
    -- with a grid of styled enchant cells (like item preview).
    -- Each cell shows the enchant name and ID in a small card.
    -- ============================================================

    previewTab.enchantMode = false
    previewTab.enchantSlotName = nil

    -- Enchant grid container (overlays the normal item list)
    local enchantContainer = CreateFrame("Frame", "$parentEnchantGrid", previewTab)
    enchantContainer:SetPoint("TOPLEFT", 0, -34)
    enchantContainer:SetSize(601, 367)
    enchantContainer:Hide()

    -- Grid layout constants
    local ECELL_W, ECELL_H = 145, 74
    local ECOLS = math.floor(601 / ECELL_W)  -- 4 columns
    local EROWS = math.floor(367 / ECELL_H)  -- 4 rows
    local EPER_PAGE = ECOLS * EROWS           -- 16 per page
    local EGAP_W = (601 - ECOLS * ECELL_W) / 2
    local EGAP_H = (367 - EROWS * ECELL_H) / 2

    local enchantCells = {}
    local enchantFilteredList = {}
    local enchantPage = 1
    local selectedEnchantCell = nil

    -- (Enchant icons now use the shared GetEnchantIcon mapper above)

    -- Enchant cell backdrop
    local enchantCellBackdrop = {
        bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 12,
        insets = { left = 2, right = 2, top = 2, bottom = 2 }
    }

    -- Create grid cells
    for row = 1, EROWS do
        for col = 1, ECOLS do
            local idx = (row - 1) * ECOLS + col
            local cell = CreateFrame("Button", nil, enchantContainer)
            cell:SetSize(ECELL_W - 4, ECELL_H - 4)
            cell:SetPoint("TOPLEFT", enchantContainer, "TOPLEFT",
                EGAP_W + (col - 1) * ECELL_W + 2,
                -(EGAP_H + (row - 1) * ECELL_H + 2))
            cell:SetBackdrop(enchantCellBackdrop)
            cell:SetBackdropColor(0.07, 0.06, 0.04, 0.95)
            cell:SetBackdropBorderColor(0.50, 0.42, 0.18, 0.9)

            -- Enchant icon
            local icon = cell:CreateTexture(nil, "ARTWORK")
            icon:SetSize(28, 28)
            icon:SetPoint("LEFT", 8, 0)
            icon:SetTexture("Interface\\Icons\\Spell_Holy_GreaterHeal")
            cell.icon = icon

            -- Enchant name
            local nameText = cell:CreateFontString(nil, "OVERLAY", "GameFontNormal")
            nameText:SetPoint("TOPLEFT", icon, "TOPRIGHT", 6, -2)
            nameText:SetPoint("RIGHT", cell, "RIGHT", -6, 0)
            nameText:SetJustifyH("LEFT")
            nameText:SetTextColor(1.0, 0.90, 0.55)
            nameText:SetWordWrap(true)
            cell.nameText = nameText

            -- Enchant ID
            local idText = cell:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            idText:SetPoint("BOTTOMLEFT", icon, "BOTTOMRIGHT", 6, 2)
            idText:SetJustifyH("LEFT")
            idText:SetTextColor(0.60, 0.55, 0.40)
            cell.idText = idText

            -- Check mark for selected
            local check = cell:CreateTexture(nil, "OVERLAY")
            check:SetSize(16, 16)
            check:SetPoint("TOPRIGHT", -4, -4)
            check:SetTexture("Interface\\Buttons\\UI-CheckBox-Check")
            check:SetVertexColor(1.0, 0.85, 0.20)
            check:Hide()
            cell.check = check

            -- Highlight
            cell:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square")
            cell:GetHighlightTexture():SetAlpha(0.15)

            cell.enchantData = nil

            cell:SetScript("OnClick", function(self)
                local data = self.enchantData
                if not data then return end
                local enchSlot = mainFrame.selectedEnchantSlot
                if enchSlot then
                    enchSlot:SetEnchant(data.id, data.name)
                    -- Deselect previous
                    if selectedEnchantCell and selectedEnchantCell ~= self then
                        selectedEnchantCell.check:Hide()
                        selectedEnchantCell:SetBackdropBorderColor(0.50, 0.42, 0.18, 0.9)
                        selectedEnchantCell.nameText:SetTextColor(1.0, 0.90, 0.55)
                    end
                    self.check:Show()
                    self:SetBackdropBorderColor(1.0, 0.82, 0.20, 1)
                    self.nameText:SetTextColor(1.0, 0.88, 0.30)
                    selectedEnchantCell = self
                    PlaySound("gsTitleOptionOK")
                end
            end)

            cell:SetScript("OnEnter", function(self)
                if not self.enchantData then return end
                self:SetBackdropColor(0.14, 0.12, 0.06, 0.95)
                GameTooltip:SetOwner(self, "ANCHOR_TOPLEFT")
                GameTooltip:ClearLines()
                GameTooltip:AddLine("|cffF5C842" .. self.enchantData.name .. "|r")
                GameTooltip:AddLine("Enchant ID: " .. self.enchantData.id, 0.7, 0.7, 0.7)
                GameTooltip:AddLine(" ")
                GameTooltip:AddLine("Click to set on enchant slot", 0.5, 0.8, 0.5)
                GameTooltip:AddLine("Alt+Click to apply immediately", 0.8, 0.8, 0.5)
                GameTooltip:Show()
            end)

            cell:SetScript("OnLeave", function(self)
                self:SetBackdropColor(0.07, 0.06, 0.04, 0.95)
                GameTooltip:Hide()
            end)

            cell:Hide()
            enchantCells[idx] = cell
        end
    end

    -- Mouse wheel on enchant container for paging
    enchantContainer:EnableMouseWheel(true)
    enchantContainer:SetScript("OnMouseWheel", function(self, delta)
        if delta > 0 and enchantPage > 1 then
            enchantPage = enchantPage - 1
            RefreshEnchantGrid()
        elseif delta < 0 then
            local maxPage = math.ceil(#enchantFilteredList / EPER_PAGE)
            if enchantPage < maxPage then
                enchantPage = enchantPage + 1
                RefreshEnchantGrid()
            end
        end
    end)

    function RefreshEnchantGrid()
        local query = (previewTab.searchQuery or ""):lower()
        wipe(enchantFilteredList)

        for _, entry in ipairs(ns.enchantSorted) do
            if query == "" or entry.nameLower:find(query, 1, true) or tostring(entry.id):find(query, 1, true) then
                table.insert(enchantFilteredList, entry)
            end
        end

        local maxPage = math.max(1, math.ceil(#enchantFilteredList / EPER_PAGE))
        if enchantPage > maxPage then enchantPage = maxPage end
        if enchantPage < 1 then enchantPage = 1 end

        -- Update slider to show page
        slider:SetMinMaxValues(1, maxPage)
        if slider:GetValue() ~= enchantPage then
            slider:SetValue(enchantPage)
        end

        local currentEnchantSlot = mainFrame.selectedEnchantSlot
        local currentId = currentEnchantSlot and currentEnchantSlot.enchantId
        selectedEnchantCell = nil

        local startIdx = (enchantPage - 1) * EPER_PAGE

        for i = 1, EPER_PAGE do
            local cell = enchantCells[i]
            local dataIdx = startIdx + i
            local entry = enchantFilteredList[dataIdx]

            if entry then
                cell.enchantData = entry
                cell.nameText:SetText(entry.name)
                cell.idText:SetText("ID: " .. entry.id)
                cell.icon:SetTexture(GetEnchantIcon(entry.name))

                if currentId and entry.id == currentId then
                    cell.check:Show()
                    cell:SetBackdropBorderColor(1.0, 0.82, 0.20, 1)
                    cell.nameText:SetTextColor(1.0, 0.88, 0.30)
                    selectedEnchantCell = cell
                else
                    cell.check:Hide()
                    cell:SetBackdropBorderColor(0.50, 0.42, 0.18, 0.9)
                    cell.nameText:SetTextColor(1.0, 0.90, 0.55)
                end
                cell:Show()
            else
                cell.enchantData = nil
                cell:Hide()
            end
        end

        -- Update page label
        label:SetText(("Page: %d/%d  (%d enchants)"):format(enchantPage, maxPage, #enchantFilteredList))
    end

    -- Enter enchant browsing mode
    previewTab.UpdateEnchantMode = function(self, enchantSlotName)
        self.enchantMode = true
        self.enchantSlotName = enchantSlotName

        -- Hide item preview elements, show enchant grid
        list:Hide()
        dropContainer:Hide()
        enchantContainer:Show()
        slider:Show()

        -- Update search placeholder
        searchPlaceholder:SetText("Search enchants...")
        searchBox:SetText("")
        previewTab.searchQuery = ""
        searchClear:Hide()
        searchPlaceholder:Show()

        enchantPage = 1
        RefreshEnchantGrid()
    end

    -- Exit enchant mode (return to item browsing)
    previewTab.ExitEnchantMode = function(self)
        if not self.enchantMode then return end
        self.enchantMode = false
        self.enchantSlotName = nil

        -- Show item preview elements, hide enchant grid
        list:Show()
        slider:Show()
        dropContainer:Show()
        enchantContainer:Hide()

        -- Restore search placeholder
        searchPlaceholder:SetText("Search by name or item ID...")
        searchBox:SetText("")
        previewTab.searchQuery = ""
        searchClear:Hide()
        searchPlaceholder:Show()
    end

    -- Override OnShow to handle enchant mode
    previewTab:SetScript("OnShow", function(self)
        if self.enchantMode then
            list:Hide()
            dropContainer:Hide()
            enchantContainer:Show()
            slider:Show()
            RefreshEnchantGrid()
        else
            self:Update(currSlot, currSubclass)
        end
    end)

    -- Override search to support enchant mode
    searchBox:SetScript("OnTextChanged", function(self)
        local text = self:GetText()
        previewTab.searchQuery = text
        if text ~= "" then searchClear:Show(); searchPlaceholder:Hide()
        else searchClear:Hide() end
        -- Debounce: wait 0.3s after last keystroke
        searchTimer.elapsed = 0
        searchTimer:Show()
    end)

    searchTimer:SetScript("OnUpdate", function(self, dt)
        self.elapsed = self.elapsed + dt
        if self.elapsed >= 0.3 then
            self:Hide()
            if previewTab.enchantMode then
                enchantPage = 1
                RefreshEnchantGrid()
            else
                previewTab:Update(currSlot, currSubclass)
            end
        end
    end)

    searchBox:SetScript("OnEnterPressed", function(self)
        searchTimer:Hide()
        if previewTab.enchantMode then
            enchantPage = 1
            RefreshEnchantGrid()
        else
            previewTab:Update(currSlot, currSubclass)
        end
        self:ClearFocus()
    end)

    searchClear:SetScript("OnClick", function()
        searchBox:SetText("")
        searchBox:ClearFocus()
        searchPlaceholder:Show()
        searchClear:Hide()
        previewTab.searchQuery = ""
        if previewTab.enchantMode then
            enchantPage = 1
            RefreshEnchantGrid()
        end
    end)

    -- Hook slider for enchant paging (via up/down buttons or direct drag)
    local enchantSliderUpdating = false
    slider:HookScript("OnValueChanged", function(self, value)
        if previewTab.enchantMode and not enchantSliderUpdating then
            local newPage = math.floor(value + 0.5)
            if newPage ~= enchantPage then
                enchantPage = newPage
                enchantSliderUpdating = true
                RefreshEnchantGrid()
                enchantSliderUpdating = false
            end
        end
    end)
end

---------------- SUBCLASS MENU (Custom Golden Dropdown) ----------------

-- Replaces UIDropDownMenuTemplate with a custom themed dropdown
-- Uses dropContainer, dropBtn, dropText, dropArrow, dropList, dropListButtons
-- created in the preview tab block above.
mainFrame.tabs.preview.subclassMenu = {}
do
    local previewTab = mainFrame.tabs.preview
    local menu = mainFrame.tabs.preview.subclassMenu

    -- Pull references from the preview tab scope
    local dropContainer = previewTab.dropContainer
    local dropBtn = previewTab.dropBtn
    local dropText = previewTab.dropText
    local dropArrow = previewTab.dropArrow
    local dropList = previewTab.dropList
    local dropListButtons = previewTab.dropListButtons
    local DROP_ROW_H = previewTab.DROP_ROW_H

    local slotSelectedSubclass = {}
    for i, slot in ipairs(armorSlots) do slotSelectedSubclass[slot] = defaultArmorSubclass[classFileName] end
    for i, slot in ipairs(miscellaneousSlots) do slotSelectedSubclass[slot] = "Miscellaneous" end
    slotSelectedSubclass[backSlot] = slotSubclasses[backSlot][1]
    slotSelectedSubclass[mainHandSlot] = slotSubclasses[mainHandSlot][1]
    slotSelectedSubclass[offHandSlot] = slotSubclasses[offHandSlot][1]
    slotSelectedSubclass[rangedSlot] = slotSubclasses[rangedSlot][1]

    menu.currentSlot = nil

    local function BuildDropList(slot)
        -- Hide any previous buttons
        for _, b in ipairs(dropListButtons) do b:Hide() end

        local subclasses = slotSubclasses[slot]
        if not subclasses then return end

        local totalH = 0
        for i, subclass in ipairs(subclasses) do
            local btn = dropListButtons[i]
            if not btn then
                btn = CreateFrame("Button", nil, dropList)
                btn:SetHeight(DROP_ROW_H)
                btn:SetPoint("TOPLEFT", 4, -4 - (i - 1) * DROP_ROW_H)
                btn:SetPoint("TOPRIGHT", -4, -4 - (i - 1) * DROP_ROW_H)
                btn:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
                btn:GetHighlightTexture():SetVertexColor(0.80, 0.65, 0.22, 0.3)
                btn.text = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
                btn.text:SetPoint("LEFT", 6, 0)
                btn.text:SetJustifyH("LEFT")
                btn.check = btn:CreateTexture(nil, "OVERLAY")
                btn.check:SetSize(12, 12)
                btn.check:SetPoint("RIGHT", -4, 0)
                btn.check:SetTexture("Interface\\Buttons\\UI-CheckBox-Check")
                btn.check:SetVertexColor(0.95, 0.80, 0.30)
                dropListButtons[i] = btn
            end

            local isSelected = (subclass == slotSelectedSubclass[slot])
            btn.text:SetText(subclass)
            if isSelected then
                btn.text:SetTextColor(1.0, 0.84, 0.40)
                btn.check:Show()
            else
                btn.text:SetTextColor(0.85, 0.78, 0.55)
                btn.check:Hide()
            end

            btn:SetScript("OnClick", function()
                slotSelectedSubclass[slot] = subclass
                dropText:SetText(subclass)
                dropList:Hide()
                previewTab:Update(slot, subclass)
            end)
            btn:Show()
            totalH = totalH + DROP_ROW_H
        end
        dropList:SetHeight(totalH + 8)
    end

    -- Toggle dropdown on click
    dropBtn:SetScript("OnClick", function()
        if dropList:IsShown() then
            dropList:Hide()
        else
            if menu.currentSlot then
                BuildDropList(menu.currentSlot)
            end
            dropList:Show()
        end
    end)

    -- Auto-close dropdown when mouse leaves both the button and the list
    dropList:SetScript("OnUpdate", function(self)
        if not self:IsShown() then return end
        if dropBtn:IsMouseOver() or self:IsMouseOver() then return end
        -- Check if hovering a row button
        for _, b in ipairs(dropListButtons) do
            if b:IsShown() and b:IsMouseOver() then return end
        end
        -- Not hovering anything — hide after a tiny grace period
        if not self.leaveTimer then self.leaveTimer = 0 end
        self.leaveTimer = self.leaveTimer + 0.02
        if self.leaveTimer > 0.35 then
            self:Hide()
            self.leaveTimer = nil
        end
    end)

    -- Reset timer when mouse re-enters
    dropList:HookScript("OnShow", function(self) self.leaveTimer = nil end)
    dropBtn:HookScript("OnEnter", function() dropList.leaveTimer = nil end)
    dropList:HookScript("OnEnter", function(self) self.leaveTimer = nil end)

    -- Update function called by slot_OnLeftClick
    menu.Update = function(self, slot)
        self.currentSlot = slot
        local subclass = slotSelectedSubclass[slot]
        dropText:SetText(subclass)
        dropList:Hide()

        -- Enable/disable appearance
        if #slotSubclasses[slot] > 1 then
            dropArrow:SetVertexColor(0.80, 0.65, 0.22)
            dropText:SetTextColor(0.95, 0.88, 0.65)
            dropBtn:Enable()
        else
            dropArrow:SetVertexColor(0.40, 0.35, 0.20)
            dropText:SetTextColor(0.50, 0.45, 0.30)
            dropBtn:Disable()
        end

        previewTab:Update(slot, subclass)
    end
end

---------------- LOADOUTS TAB (formerly Appearances) ----------------

mainFrame.tabs.appearances.saved = CreateFrame("Frame", "$parentSaved", mainFrame.tabs.appearances)
do
    local appearancesTab = mainFrame.tabs.appearances
    local frame = appearancesTab.saved

    -- List panel on the left side (narrower to make room for preview)
    frame:SetPoint("TOPLEFT", 0, -8) frame:SetPoint("BOTTOMLEFT", 0, 30) frame:SetWidth(180)
    frame:SetBackdrop({ bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", tile = true, tileSize = 16, edgeSize = 16,
        insets = { left = 3, right = 3, top = 3, bottom = 3 }})
    frame:SetBackdropColor(0.04, 0.03, 0.03, 0.95)
    frame:SetBackdropBorderColor(0.80, 0.65, 0.22, 0.85)

    local scrollFrame = CreateFrame("ScrollFrame", "$parentScrollFrame", frame)
    scrollFrame:SetPoint("TOPLEFT", 8, -72) scrollFrame:SetPoint("BOTTOMLEFT", 8, 8)
    scrollFrame:SetPoint("RIGHT", -8, 0)
    scrollFrame:EnableMouseWheel(true)
    scrollFrame:SetScript("OnMouseWheel", function(self, delta)
        local current = self:GetVerticalScroll()
        local maxScroll = self:GetVerticalScrollRange()
        local newScroll = math.max(0, math.min(maxScroll, current - (delta * 20)))
        self:SetVerticalScroll(newScroll)
    end)

    -- ============================================================
    -- Preview panel on the right side - shows all loadout slots
    -- ============================================================
    local previewFrame = CreateFrame("Frame", "$parentLoadoutPreview", appearancesTab)
    previewFrame:SetPoint("TOPLEFT", frame, "TOPRIGHT", 8, 0)
    previewFrame:SetPoint("BOTTOMLEFT", frame, "BOTTOMRIGHT", 8, 0)
    previewFrame:SetPoint("RIGHT", -6, 0)
    previewFrame:SetBackdrop({ bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", tile = true, tileSize = 16, edgeSize = 16,
        insets = { left = 3, right = 3, top = 3, bottom = 3 }})
    previewFrame:SetBackdropColor(0.04, 0.03, 0.03, 0.95)
    previewFrame:SetBackdropBorderColor(0.80, 0.65, 0.22, 0.85)

    -- Title
    local previewTitle = previewFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    previewTitle:SetPoint("TOP", 0, -8)
    previewTitle:SetText("|cffffd700Loadout Preview|r")

    -- Loadout name label
    local loadoutNameLabel = previewFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    loadoutNameLabel:SetPoint("TOP", previewTitle, "BOTTOM", 0, -4)
    loadoutNameLabel:SetText("|cff8a7d6aNo loadout selected|r")
    
    -- Dressing room model (left side, larger)
    local previewModel = CreateFrame("DressUpModel", "$parentPreviewModel", previewFrame)
    previewModel:SetPoint("TOPLEFT", -30, -45)
    previewModel:SetSize(200, 280)
    previewModel:SetUnit("player")
    previewModel:SetFacing(-0.4)
    previewModel:SetPosition(0, 0, 0)
    
    -- Model will use default pose (SetAnimation not available in 3.3.5a)
    
    -- Mouse rotation
    local previewRotating = false
    previewModel:EnableMouse(true)
    previewModel:SetScript("OnMouseDown", function(self, button)
        if button == "LeftButton" then previewRotating = true end
    end)
    previewModel:SetScript("OnMouseUp", function(self, button)
        if button == "LeftButton" then previewRotating = false end
    end)
    previewModel:SetScript("OnUpdate", function(self, dt)
        if previewRotating and IsMouseButtonDown("LeftButton") then
            local x, y = GetCursorPosition()
            local scale = UIParent:GetEffectiveScale()
            x = x / scale
            if self.lastX then
                local dx = x - self.lastX
                self:SetFacing(self:GetFacing() + dx * 0.02)
            end
            self.lastX = x
        else
            self.lastX = nil
        end
    end)
    previewModel:EnableMouseWheel(true)
    previewModel:SetScript("OnMouseWheel", function(self, delta)
        local x, y, z = self:GetPosition()
        x = x + delta * 0.3
        if x < -2 then x = -2 end
        if x > 4 then x = 4 end
        self:SetPosition(x, y, z)
    end)

    -- Create preview slots (mini versions of main slots)
    local previewSlots = {}
    local slotSize = 24
    local slotSpacing = 2
    
    -- Equipment slots layout (2 columns, right side of model)
    local equipSlots = {"Head", "Shoulder", "Back", "Chest", "Shirt", "Tabard", "Wrist", "Hands", "Waist", "Legs", "Feet"}
    
    local startX = 165
    local startY = -45
    local col1Slots = {"Head", "Shoulder", "Chest", "Wrist", "Waist"}
    local col2Slots = {"Back", "Shirt", "Tabard", "Hands", "Legs", "Feet"}
    
    local function CreatePreviewSlot(slotName, x, y)
        local slot = CreateFrame("Button", "$parentPreview"..slotName:gsub(" ", ""), previewFrame)
        slot:SetSize(slotSize, slotSize)
        slot:SetPoint("TOPLEFT", x, y)
        
        -- Background
        slot:SetNormalTexture(slotTextures[slotName] or "Interface\\Buttons\\UI-EmptySlot")
        slot:GetNormalTexture():SetTexCoord(0.15, 0.85, 0.15, 0.85)
        
        -- Item texture
        local itemTex = slot:CreateTexture(nil, "OVERLAY")
        itemTex:SetAllPoints()
        itemTex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        itemTex:Hide()
        slot.itemTex = itemTex
        
        -- Border
        slot:SetBackdrop({
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            edgeSize = 8,
            insets = { left = 1, right = 1, top = 1, bottom = 1 }
        })
        slot:SetBackdropBorderColor(0.4, 0.4, 0.4, 0.8)
        
        -- Label (smaller font)
        local label = slot:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        label:SetPoint("LEFT", slot, "RIGHT", 3, 0)
        label:SetText(slotName)
        label:SetTextColor(0.7, 0.7, 0.7)
        slot.label = label
        
        slot.slotName = slotName
        slot:EnableMouse(true)
        slot:SetScript("OnEnter", function(self)
            if self.itemId and self.itemId > 0 then
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                GameTooltip:SetHyperlink("item:"..self.itemId)
                GameTooltip:Show()
            end
        end)
        slot:SetScript("OnLeave", function() GameTooltip:Hide() end)
        
        return slot
    end
    
    -- Create equipment slots in 2 columns
    for i, slotName in ipairs(col1Slots) do
        previewSlots[slotName] = CreatePreviewSlot(slotName, startX, startY - (i-1) * (slotSize + slotSpacing))
    end
    for i, slotName in ipairs(col2Slots) do
        previewSlots[slotName] = CreatePreviewSlot(slotName, startX + 95, startY - (i-1) * (slotSize + slotSpacing))
    end
    
    -- Weapon slots (bottom, 3 in a row, more compact)
    local weaponY = startY - 7 * (slotSize + slotSpacing)
    previewSlots["Main Hand"] = CreatePreviewSlot("Main Hand", startX, weaponY)
    previewSlots["Off-hand"] = CreatePreviewSlot("Off-hand", startX + 85, weaponY)
    previewSlots["Ranged"] = CreatePreviewSlot("Ranged", startX + 170, weaponY)
    
    -- Enchant slots (below weapons)
    local enchantY = weaponY - (slotSize + slotSpacing + 4)
    local function CreateEnchantSlot(name, x, y)
        local slot = CreateFrame("Button", "$parentPreview"..name:gsub(" ", ""), previewFrame)
        slot:SetSize(slotSize, slotSize)
        slot:SetPoint("TOPLEFT", x, y)
        slot:SetNormalTexture("Interface\\Icons\\INV_Enchant_EssenceMagicLarge")
        slot:GetNormalTexture():SetTexCoord(0.08, 0.92, 0.08, 0.92)
        slot:SetBackdrop({
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            edgeSize = 8,
            insets = { left = 1, right = 1, top = 1, bottom = 1 }
        })
        slot:SetBackdropBorderColor(0.4, 0.4, 0.4, 0.8)
        local label = slot:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        label:SetPoint("LEFT", slot, "RIGHT", 3, 0)
        label:SetTextColor(0.7, 0.7, 0.7)
        slot.label = label
        slot.slotName = name
        return slot
    end
    
    previewSlots["Enchant MH"] = CreateEnchantSlot("Enchant MH", startX, enchantY)
    previewSlots["Enchant MH"].label:SetText("Ench MH")
    previewSlots["Enchant OH"] = CreateEnchantSlot("Enchant OH", startX + 85, enchantY)
    previewSlots["Enchant OH"].label:SetText("Ench OH")
    
    -- Special slots (below enchants, 2x2 grid)
    local specialY = enchantY - (slotSize + slotSpacing + 4)
    local function CreateSpecialSlot(name, icon, x, y)
        local slot = CreateFrame("Button", "$parentPreview"..name:gsub(" ", ""), previewFrame)
        slot:SetSize(slotSize, slotSize)
        slot:SetPoint("TOPLEFT", x, y)
        slot:SetNormalTexture(icon)
        slot:GetNormalTexture():SetTexCoord(0.08, 0.92, 0.08, 0.92)
        slot:SetBackdrop({
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            edgeSize = 8,
            insets = { left = 1, right = 1, top = 1, bottom = 1 }
        })
        slot:SetBackdropBorderColor(0.4, 0.4, 0.4, 0.8)
        local label = slot:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        label:SetPoint("LEFT", slot, "RIGHT", 3, 0)
        label:SetTextColor(0.7, 0.7, 0.7)
        slot.slotName = name
        slot.label = label
        return slot
    end
    
    previewSlots["Mount"] = CreateSpecialSlot("Mount", "Interface\\Icons\\Ability_Mount_RidingHorse", startX, specialY)
    previewSlots["Mount"].label:SetText("Mount")
    previewSlots["Pet"] = CreateSpecialSlot("Pet", "Interface\\Icons\\INV_Box_PetCarrier_01", startX + 85, specialY)
    previewSlots["Pet"].label:SetText("Pet")
    
    local specialY2 = specialY - (slotSize + slotSpacing)
    previewSlots["Combat Pet"] = CreateSpecialSlot("Combat Pet", "Interface\\Icons\\Ability_Hunter_BeastCall", startX, specialY2)
    previewSlots["Combat Pet"].label:SetText("C.Pet")
    previewSlots["Morph Form"] = CreateSpecialSlot("Morph Form", "Interface\\Icons\\Spell_Shadow_Charm", startX + 85, specialY2)
    previewSlots["Morph Form"].label:SetText("Morph")

    -- Function to update preview with loadout data
    local lookPreviewTimer = CreateFrame("Frame")
    lookPreviewTimer:Hide()
    
    local function UpdateLoadoutPreview(loadout)
        lookPreviewTimer:Hide()
        lookPreviewTimer:SetScript("OnUpdate", nil)
        
        if not loadout then
            loadoutNameLabel:SetText("|cff8a7d6aNo loadout selected|r")
            previewModel:SetUnit("player")
            previewModel:Undress()
            -- Clear all preview slots
            for slotName, slot in pairs(previewSlots) do
                if slot.itemTex then
                    slot.itemTex:Hide()
                end
                if slot.label then
                    local displayName = slot.slotName:match("^(%S+)") or slot.slotName
                    slot.label:SetText(displayName)
                    slot.label:SetTextColor(0.5, 0.5, 0.5)
                end
                slot.itemId = nil
                slot.displayId = nil
            end
            return
        end
        
        loadoutNameLabel:SetText("|cffffd700" .. (loadout.name or "Loadout") .. "|r")
        
        -- Update dressing room model
        previewModel:SetUnit("player")
        previewModel:Undress()
        
        local pendingItems = {}
        
        -- Update equipment slots
        for index, slotName in pairs(slotOrder) do
            local itemId = loadout.items and loadout.items[index]
            local slot = previewSlots[slotName]
            if slot then
                if itemId and itemId ~= 0 then
                    slot.itemId = itemId
                    -- Don't add ranged weapon to model display (show main-hand/off-hand instead)
                    if slotName ~= "Ranged" then
                        table.insert(pendingItems, itemId)
                    end
                    
                    -- Try to get item info immediately
                    local _, _, _, _, _, _, _, _, _, texture = GetItemInfo(itemId)
                    if texture then
                        slot.itemTex:SetTexture(texture)
                        slot.itemTex:Show()
                        slot.label:SetTextColor(1, 0.82, 0)
                    else
                        -- Item not cached, query it and update when ready
                        slot.itemTex:Hide()
                        slot.label:SetTextColor(0.7, 0.7, 0.7)
                        ns.QueryItem(itemId, function(qItemId, success)
                            if success and qItemId == itemId and slot.itemId == qItemId then
                                local _, _, _, _, _, _, _, _, _, tex = GetItemInfo(qItemId)
                                if tex then
                                    slot.itemTex:SetTexture(tex)
                                    slot.itemTex:Show()
                                    slot.label:SetTextColor(1, 0.82, 0)
                                end
                            end
                        end)
                    end
                else
                    slot.itemTex:Hide()
                    slot.itemId = nil
                    slot.label:SetTextColor(0.5, 0.5, 0.5)
                end
            end
        end
        
        -- Dress the model with items
        local function DressModel()
            for _, itemId in ipairs(pendingItems) do
                previewModel:TryOn(itemId)
            end
        end
        
        -- Check if items are cached
        local uncached = 0
        for _, itemId in ipairs(pendingItems) do
            local _, itemLink = GetItemInfo(itemId)
            if not itemLink then
                uncached = uncached + 1
                ns.QueryItem(itemId, nil)
            end
        end
        
        if uncached == 0 then
            DressModel()
        else
            DressModel()
            local retryCount = 0
            local retryMax = 15
            lookPreviewTimer.elapsed = 0
            lookPreviewTimer:SetScript("OnUpdate", function(self, dt)
                self.elapsed = self.elapsed + dt
                if self.elapsed >= 0.1 then
                    self.elapsed = 0
                    retryCount = retryCount + 1
                    local allCached = true
                    for _, itemId in ipairs(pendingItems) do
                        local _, itemLink = GetItemInfo(itemId)
                        if not itemLink then allCached = false; break end
                    end
                    if allCached or retryCount >= retryMax then
                        DressModel()
                        self:Hide()
                        self:SetScript("OnUpdate", nil)
                    end
                end
            end)
            lookPreviewTimer:Show()
        end
        
        -- Update enchant slots
        if loadout.enchantMH and loadout.enchantMH > 0 then
            previewSlots["Enchant MH"].label:SetText("MH:" .. loadout.enchantMH)
            previewSlots["Enchant MH"].label:SetTextColor(0.6, 1, 0.6)
        else
            previewSlots["Enchant MH"].label:SetText("Ench MH")
            previewSlots["Enchant MH"].label:SetTextColor(0.5, 0.5, 0.5)
        end
        
        if loadout.enchantOH and loadout.enchantOH > 0 then
            previewSlots["Enchant OH"].label:SetText("OH:" .. loadout.enchantOH)
            previewSlots["Enchant OH"].label:SetTextColor(0.6, 1, 0.6)
        else
            previewSlots["Enchant OH"].label:SetText("Ench OH")
            previewSlots["Enchant OH"].label:SetTextColor(0.5, 0.5, 0.5)
        end
        
        -- Update special slots
        if loadout.mountDisplay and loadout.mountDisplay > 0 then
            previewSlots["Mount"].label:SetText("M:" .. loadout.mountDisplay)
            previewSlots["Mount"].label:SetTextColor(1, 0.5, 0)
            previewSlots["Mount"].displayId = loadout.mountDisplay
        else
            previewSlots["Mount"].label:SetText("Mount")
            previewSlots["Mount"].label:SetTextColor(0.5, 0.5, 0.5)
            previewSlots["Mount"].displayId = nil
        end
        
        if loadout.petDisplay and loadout.petDisplay > 0 then
            previewSlots["Pet"].label:SetText("P:" .. loadout.petDisplay)
            previewSlots["Pet"].label:SetTextColor(1, 0.5, 0)
            previewSlots["Pet"].displayId = loadout.petDisplay
        else
            previewSlots["Pet"].label:SetText("Pet")
            previewSlots["Pet"].label:SetTextColor(0.5, 0.5, 0.5)
            previewSlots["Pet"].displayId = nil
        end
        
        if loadout.combatPetDisplay and loadout.combatPetDisplay > 0 then
            previewSlots["Combat Pet"].label:SetText("CP:" .. loadout.combatPetDisplay)
            previewSlots["Combat Pet"].label:SetTextColor(1, 0.5, 0)
            previewSlots["Combat Pet"].displayId = loadout.combatPetDisplay
        else
            previewSlots["Combat Pet"].label:SetText("C.Pet")
            previewSlots["Combat Pet"].label:SetTextColor(0.5, 0.5, 0.5)
            previewSlots["Combat Pet"].displayId = nil
        end
        
        if loadout.morphForm and loadout.morphForm > 0 then
            previewSlots["Morph Form"].label:SetText("MF:" .. loadout.morphForm)
            previewSlots["Morph Form"].label:SetTextColor(0.7, 0.3, 1)
            previewSlots["Morph Form"].displayId = loadout.morphForm
        else
            previewSlots["Morph Form"].label:SetText("Morph")
            previewSlots["Morph Form"].label:SetTextColor(0.5, 0.5, 0.5)
            previewSlots["Morph Form"].displayId = nil
        end
    end

    -- ============================================================
    -- Top buttons
    -- ============================================================
    local btnSaveAs = CreateGoldenButton("$parentButtonSaveAs", frame)
    btnSaveAs:SetSize(85, 22) btnSaveAs:SetPoint("TOPLEFT", frame, "TOPLEFT", 8, -8)
    btnSaveAs:SetText("Save As...")

    local btnSave = CreateGoldenButton("$parentButtonSave", frame)
    btnSave:SetSize(75, 22) btnSave:SetPoint("LEFT", btnSaveAs, "RIGHT", 4, 0)
    btnSave:SetText("Update") btnSave:Disable()

    local btnRemove = CreateGoldenButton("$parentButtonRemove", frame)
    btnRemove:SetSize(frame:GetWidth() - 16, 22) 
    btnRemove:SetPoint("TOPLEFT", frame, "TOPLEFT", 8, -34)
    btnRemove:SetText("Remove") btnRemove:Disable()

    local btnApplyLoadout = CreateGoldenButton("$parentButtonApplyLoadout", frame)
    btnApplyLoadout:SetSize(frame:GetWidth() - 16, 28) 
    btnApplyLoadout:SetPoint("BOTTOM", frame, "BOTTOM", 0, -28)
    btnApplyLoadout:SetText("|cffF5C842Apply Loadout|r")
    btnApplyLoadout:Disable()

    local listFrame = ns.CreateListFrame("$parentSavedLoadouts", nil, scrollFrame)
    listFrame:SetWidth(scrollFrame:GetWidth())
    listFrame:SetScript("OnShow", function(self)
        if self.selected == nil then
            btnRemove:Disable() btnSave:Disable() btnApplyLoadout:Disable()
            UpdateLoadoutPreview(nil)
        else
            btnRemove:Enable() btnSave:Enable() btnApplyLoadout:Enable()
        end
    end)
    listFrame.onSelect = function()
        btnRemove:Enable() btnSave:Enable() btnApplyLoadout:Enable()
        -- Update the preview with the selected loadout
        if listFrame:GetSelected() and _G["TransmorpherLoadoutsAccount"] then
            local id = listFrame.buttons[listFrame:GetSelected()]:GetID()
            local loadout = _G["TransmorpherLoadoutsAccount"][id]
            if loadout then
                UpdateLoadoutPreview(loadout)
            end
        end
    end

    -- Capture current state into a loadout
    local function CaptureCurrentLoadout()
        local loadout = {
            items = {},
            enchantMH = nil,
            enchantOH = nil,
            mountDisplay = nil,
            petDisplay = nil,
            combatPetDisplay = nil,
            morphForm = nil
        }
        
        -- Capture all item slots
        for index, slotName in pairs(slotOrder) do
            if mainFrame.slots[slotName].itemId ~= nil then 
                loadout.items[index] = mainFrame.slots[slotName].itemId
            else 
                loadout.items[index] = 0
            end
        end
        
        -- Capture enchants
        if mainFrame.enchantSlots["Enchant MH"].enchantId then
            loadout.enchantMH = mainFrame.enchantSlots["Enchant MH"].enchantId
        end
        if mainFrame.enchantSlots["Enchant OH"].enchantId then
            loadout.enchantOH = mainFrame.enchantSlots["Enchant OH"].enchantId
        end
        
        -- Capture special morphs from saved state
        if TransmorpherCharacterState then
            if TransmorpherCharacterState.MountDisplay then
                loadout.mountDisplay = TransmorpherCharacterState.MountDisplay
            end
            if TransmorpherCharacterState.PetDisplay then
                loadout.petDisplay = TransmorpherCharacterState.PetDisplay
            end
            if TransmorpherCharacterState.HunterPetDisplay then
                loadout.combatPetDisplay = TransmorpherCharacterState.HunterPetDisplay
            end
            if TransmorpherCharacterState.Morph then
                loadout.morphForm = TransmorpherCharacterState.Morph
            end
        end
        
        return loadout
    end

    local function buildList()
        local savedLoadouts = _G["TransmorpherLoadoutsAccount"]
        if not savedLoadouts then return end
        
        _G["TransmorpherLoadoutsAccount"] = {}
        local names, loadouts = {}, {}
        for _, loadout in pairs(savedLoadouts) do
            table.insert(names, loadout.name) 
            loadouts[loadout.name] = loadout
        end
        table.sort(names)
        for _, name in ipairs(names) do
            listFrame:AddItem(name)
            table.insert(_G["TransmorpherLoadoutsAccount"], loadouts[name])
        end
    end

    listFrame:RegisterEvent("ADDON_LOADED")
    listFrame:SetScript("OnEvent", function(self, event, addonName)
        if addonName == addon and event == "ADDON_LOADED" then
            if _G["TransmorpherLoadoutsAccount"] == nil then 
                _G["TransmorpherLoadoutsAccount"] = {} 
                SELECTED_CHAT_FRAME:AddMessage("|cffF5C842<Transmorpher>|r: Loadouts initialized (empty)")
            else
                SELECTED_CHAT_FRAME:AddMessage("|cffF5C842<Transmorpher>|r: Loaded " .. #_G["TransmorpherLoadoutsAccount"] .. " loadout(s)")
            end
            if _G["TransmorpherSavedLooks"] == nil then _G["TransmorpherSavedLooks"] = {} end
            if _G["TransmorpherMorphFavorites"] == nil then _G["TransmorpherMorphFavorites"] = {} end
            buildList()
            scrollFrame:SetScrollChild(listFrame)
        end
    end)

    -- Apply loadout button - applies ALL morphs from the loadout
    btnApplyLoadout:SetScript("OnClick", function()
        if not IsMorpherReady() then
            SELECTED_CHAT_FRAME:AddMessage("|cffF5C842<Transmorpher>|r: |cffff0000DLL not loaded!|r")
            return
        end
        
        local savedLoadouts = _G["TransmorpherLoadoutsAccount"]
        local id = listFrame.buttons[listFrame:GetSelected()]:GetID()
        local loadout = savedLoadouts[id]
        
        if not loadout then return end
        
        -- Create world-class animation overlay
        local animFrame = CreateFrame("Frame", nil, UIParent)
        animFrame:SetFrameStrata("FULLSCREEN_DIALOG")
        animFrame:SetAllPoints()
        animFrame:SetAlpha(0)
        
        -- Background darkening
        local darkBG = animFrame:CreateTexture(nil, "BACKGROUND")
        darkBG:SetAllPoints()
        darkBG:SetTexture(0, 0, 0, 0.7)
        
        -- Golden flash layers
        local flash1 = animFrame:CreateTexture(nil, "ARTWORK")
        flash1:SetAllPoints()
        flash1:SetTexture("Interface\\FullScreenTextures\\OutOfControl")
        flash1:SetBlendMode("ADD")
        flash1:SetVertexColor(1, 0.9, 0.3, 1)
        
        -- Center burst
        local burst = animFrame:CreateTexture(nil, "OVERLAY")
        burst:SetSize(512, 512)
        burst:SetPoint("CENTER")
        burst:SetTexture("Interface\\Spellbook\\UI-Glyph-Rune1")
        burst:SetBlendMode("ADD")
        burst:SetVertexColor(1, 0.85, 0.2, 1)
        
        -- Sparkle particles (using different texture)
        local sparkles = {}
        for i = 1, 30 do
            local sparkle = animFrame:CreateTexture(nil, "OVERLAY")
            local size = math.random(24, 48)
            sparkle:SetSize(size, size)
            sparkle:SetTexture("Interface\\Cooldown\\star4")
            sparkle:SetBlendMode("ADD")
            sparkle:SetVertexColor(1, 0.85, 0.3, 1)
            sparkle:SetAlpha(0)
            sparkles[i] = {
                tex = sparkle,
                angle = (i / 30) * math.pi * 2,
                speed = 0.8 + math.random() * 1.2,
                distance = 150 + math.random(250)
            }
        end
        
        -- Success text with shadow (centered)
        local successTextShadow = animFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
        successTextShadow:SetPoint("CENTER", 2, -2)
        successTextShadow:SetText("|cff000000LOADOUT APPLIED!|r")
        successTextShadow:SetAlpha(0)
        
        local successText = animFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
        successText:SetPoint("CENTER", 0, 0)
        successText:SetText("|cffffd700LOADOUT APPLIED!|r")
        successText:SetAlpha(0)
        
        -- Loadout name with shadow (centered below)
        local nameTextShadow = animFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        nameTextShadow:SetPoint("TOP", successText, "BOTTOM", 2, -12)
        nameTextShadow:SetText("|cff000000" .. loadout.name .. "|r")
        nameTextShadow:SetAlpha(0)
        
        local nameText = animFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        nameText:SetPoint("TOP", successText, "BOTTOM", 0, -10)
        nameText:SetText("|cffF5C842" .. loadout.name .. "|r")
        nameText:SetAlpha(0)
        
        -- Animation sequence
        local elapsed = 0
        local duration = 2.2
        animFrame:SetScript("OnUpdate", function(self, dt)
            elapsed = elapsed + dt
            local progress = elapsed / duration
            
            if progress < 0.1 then
                -- Instant flash
                local p = progress / 0.1
                animFrame:SetAlpha(1)
                darkBG:SetAlpha(p * 0.7)
                flash1:SetAlpha(p)
                burst:SetAlpha(p)
                burst:SetSize(512 * (1 - p * 0.3), 512 * (1 - p * 0.3))
            elseif progress < 0.3 then
                -- Burst expansion + sparkles explode
                local p = (progress - 0.1) / 0.2
                flash1:SetAlpha(1 - p * 0.8)
                burst:SetAlpha(1 - p * 0.4)
                burst:SetSize(512 * (0.7 + p * 1.5), 512 * (0.7 + p * 1.5))
                
                -- Sparkles burst out
                for i, s in ipairs(sparkles) do
                    local sp = math.min(1, p * 3)
                    s.tex:SetAlpha(sp)
                    local dist = s.distance * p
                    s.tex:SetPoint("CENTER", UIParent, "CENTER",
                        math.cos(s.angle) * dist,
                        math.sin(s.angle) * dist)
                end
            elseif progress < 0.5 then
                -- Text appears smoothly
                local p = (progress - 0.3) / 0.2
                local ease = p * p * (3 - 2 * p)
                successText:SetAlpha(ease)
                successTextShadow:SetAlpha(ease * 0.6)
                nameText:SetAlpha(ease)
                nameTextShadow:SetAlpha(ease * 0.6)
                
                -- Sparkles continue
                for i, s in ipairs(sparkles) do
                    s.tex:SetAlpha(1 - p * 0.3)
                    s.tex:SetPoint("CENTER", UIParent, "CENTER",
                        math.cos(s.angle + elapsed * s.speed) * s.distance,
                        math.sin(s.angle + elapsed * s.speed) * s.distance)
                end
                
                burst:SetAlpha(0.6 * (1 - p))
                flash1:SetAlpha(0.2 * (1 - p))
            elseif progress < 1.7 then
                -- Hold with gentle pulse
                local pulse = 0.95 + math.sin(elapsed * 3) * 0.05
                successText:SetAlpha(pulse)
                successTextShadow:SetAlpha(pulse * 0.6)
                nameText:SetAlpha(pulse)
                nameTextShadow:SetAlpha(pulse * 0.6)
                
                -- Sparkles orbit slowly
                for i, s in ipairs(sparkles) do
                    s.tex:SetAlpha(0.7 + math.sin(elapsed * 2 + i * 0.3) * 0.2)
                    s.tex:SetPoint("CENTER", UIParent, "CENTER",
                        math.cos(s.angle + elapsed * s.speed) * s.distance,
                        math.sin(s.angle + elapsed * s.speed) * s.distance)
                end
            else
                -- Smooth fade out everything with upward drift
                local p = (progress - 1.7) / 0.5
                local ease = 1 - (p * p * (3 - 2 * p))
                animFrame:SetAlpha(ease)
                
                -- Text fades up
                local drift = p * 50
                successText:SetPoint("CENTER", 0, drift)
                successTextShadow:SetPoint("CENTER", 2, drift - 2)
                successText:SetAlpha(ease)
                successTextShadow:SetAlpha(ease * 0.6)
                nameText:SetAlpha(ease)
                nameTextShadow:SetAlpha(ease * 0.6)
                
                -- Sparkles collapse inward and fade
                for i, s in ipairs(sparkles) do
                    s.tex:SetAlpha(ease * 0.5)
                    local collapseDist = s.distance * ease * 0.5
                    s.tex:SetPoint("CENTER", UIParent, "CENTER",
                        math.cos(s.angle + elapsed * s.speed) * collapseDist,
                        math.sin(s.angle + elapsed * s.speed) * collapseDist)
                end
            end
            
            if progress >= 1.0 then
                self:SetScript("OnUpdate", nil)
                self:Hide()
            end
        end)
        
        -- Play sound effect
        PlaySound("LevelUp")
        
        -- Apply all item morphs
        for index, slotName in pairs(slotOrder) do
            local itemId = loadout.items and loadout.items[index]
            if itemId and itemId ~= 0 and slotToEquipSlotId[slotName] then
                local equippedId = GetEquippedItemForSlot(slotName)
                local slot = mainFrame.slots[slotName]
                if equippedId and equippedId == itemId then
                    slot.isMorphed = false
                    slot.morphedItemId = nil
                    slot:SetItem(itemId)
                    HideMorphGlow(slot)
                else
                    SendMorphCommand("ITEM:" .. slotToEquipSlotId[slotName] .. ":" .. itemId)
                    slot.isMorphed = true
                    slot.morphedItemId = itemId
                    slot:SetItem(itemId)
                    ShowMorphGlow(slot)
                end
            end
        end
        
        -- Apply enchant morphs
        if loadout.enchantMH and loadout.enchantMH > 0 then
            SendMorphCommand("ENCHANT_MH:" .. loadout.enchantMH)
            local eName = tostring(loadout.enchantMH)
            if ns.enchantDB and ns.enchantDB[loadout.enchantMH] then 
                eName = ns.enchantDB[loadout.enchantMH] 
            end
            mainFrame.enchantSlots["Enchant MH"]:SetEnchant(loadout.enchantMH, eName)
            ShowMorphGlow(mainFrame.enchantSlots["Enchant MH"], "green")
        end
        if loadout.enchantOH and loadout.enchantOH > 0 then
            SendMorphCommand("ENCHANT_OH:" .. loadout.enchantOH)
            local eName = tostring(loadout.enchantOH)
            if ns.enchantDB and ns.enchantDB[loadout.enchantOH] then 
                eName = ns.enchantDB[loadout.enchantOH] 
            end
            mainFrame.enchantSlots["Enchant OH"]:SetEnchant(loadout.enchantOH, eName)
            ShowMorphGlow(mainFrame.enchantSlots["Enchant OH"], "green")
        end
        
        -- Apply mount morph or clear if not in loadout
        if loadout.mountDisplay and loadout.mountDisplay > 0 then
            SendMorphCommand("MOUNT_MORPH:" .. loadout.mountDisplay)
            if TransmorpherCharacterState then
                TransmorpherCharacterState.MountDisplay = loadout.mountDisplay
            end
        else
            SendMorphCommand("MOUNT_RESET")
            if TransmorpherCharacterState then
                TransmorpherCharacterState.MountDisplay = nil
            end
        end
        
        -- Apply pet morph or clear if not in loadout
        if loadout.petDisplay and loadout.petDisplay > 0 then
            SendMorphCommand("PET_MORPH:" .. loadout.petDisplay)
            if TransmorpherCharacterState then
                TransmorpherCharacterState.PetDisplay = loadout.petDisplay
            end
        else
            SendMorphCommand("PET_RESET")
            if TransmorpherCharacterState then
                TransmorpherCharacterState.PetDisplay = nil
            end
        end
        
        -- Apply combat pet morph or clear if not in loadout
        if loadout.combatPetDisplay and loadout.combatPetDisplay > 0 then
            SendMorphCommand("HPET_MORPH:" .. loadout.combatPetDisplay)
            if TransmorpherCharacterState then
                TransmorpherCharacterState.HunterPetDisplay = loadout.combatPetDisplay
            end
        else
            SendMorphCommand("HPET_RESET")
            if TransmorpherCharacterState then
                TransmorpherCharacterState.HunterPetDisplay = nil
            end
        end
        
        -- Apply morph form or clear if not in loadout
        if loadout.morphForm and loadout.morphForm > 0 then
            SendMorphCommand("MORPH:" .. loadout.morphForm)
            if TransmorpherCharacterState then
                TransmorpherCharacterState.Morph = loadout.morphForm
            end
        else
            SendMorphCommand("MORPH:0")
            if TransmorpherCharacterState then
                TransmorpherCharacterState.Morph = nil
            end
        end
        
        SyncDressingRoom()
        UpdateSpecialSlots()
        UpdatePreviewModel()
        SELECTED_CHAT_FRAME:AddMessage("|cffF5C842<Transmorpher>|r: Loadout '" .. loadout.name .. "' applied!")
    end)

    StaticPopupDialogs["Transmorpher_SAVE_LOADOUT_DIALOG"] = {
        text = "|cffffd700Enter loadout name:",
        button1 = "Save", button2 = CLOSE,
        timeout = 0, whileDead = true, hasEditBox = true, preferredIndex = 3,
        OnAccept = function(self)
            local loadoutName = self.editBox:GetText()
            if loadoutName ~= "" then
                local loadout = CaptureCurrentLoadout()
                loadout.name = loadoutName
                table.insert(_G["TransmorpherLoadoutsAccount"], loadout)
                listFrame:AddItem(loadoutName)
                SELECTED_CHAT_FRAME:AddMessage("|cffF5C842<Transmorpher>|r: Loadout '"..loadoutName.."' saved! (Total: " .. #_G["TransmorpherLoadoutsAccount"] .. ") Use /reload to persist.")
            end
        end,
        OnShow = function(self) self.editBox:SetText("") end,
    }

    btnSaveAs:SetScript("OnClick", function() 
        StaticPopup_Show("Transmorpher_SAVE_LOADOUT_DIALOG")
        PlaySound("gsTitleOptionOK")
    end)

    btnSave:SetScript("OnClick", function()
        if listFrame:GetSelected() then
            local id = listFrame.buttons[listFrame:GetSelected()]:GetID()
            local loadout = CaptureCurrentLoadout()
            loadout.name = _G["TransmorpherLoadoutsAccount"][id].name
            _G["TransmorpherLoadoutsAccount"][id] = loadout
            UpdateLoadoutPreview(loadout)
            SELECTED_CHAT_FRAME:AddMessage("|cffF5C842<Transmorpher>|r: Loadout updated!")
        end
        PlaySound("gsTitleOptionOK")
    end)

    btnRemove:SetScript("OnClick", function()
        if listFrame:GetSelected() then
            local id = listFrame.buttons[listFrame:GetSelected()]:GetID()
            table.remove(_G["TransmorpherLoadoutsAccount"], id)
            listFrame:RemoveItem(listFrame:GetSelected())
            btnRemove:Disable() btnSave:Disable() btnApplyLoadout:Disable()
            UpdateLoadoutPreview(nil)
        end
        PlaySound("gsTitleOptionOK")
    end)
end

---------------- MORPH TAB (Race/Display ID) ----------------

UpdatePreviewModel = function()
    local f = CreateFrame("Frame")
    f.timer = 0.5
    f:SetScript("OnUpdate", function(self, elapsed)
        self.timer = self.timer - elapsed
        if self.timer <= 0 then
            if mainFrame and mainFrame.dressingRoom then
                mainFrame.dressingRoom:SetUnit("player")
            end
            self:Hide()
            self:SetScript("OnUpdate", nil)
        end
    end)
    f:Show()
end

do
    local actualMorphTab = mainFrame.tabs.morph
    local scrollFrame = CreateFrame("ScrollFrame", "$parentScrollFrame", actualMorphTab, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", 0, -4)
    scrollFrame:SetPoint("BOTTOMRIGHT", -28, 4)
    
    local morphTab = CreateFrame("Frame", "$parentContent", scrollFrame)
    morphTab:SetSize(actualMorphTab:GetWidth() - 30, 1100) -- extra height for all morph sections
    scrollFrame:SetScrollChild(morphTab)

    -- Update size dynamically just in case
    morphTab:SetScript("OnSizeChanged", function(self, width, height)
        self:SetWidth(width)
    end)

    local yOff = -16

    -- Title
    local titleText = morphTab:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    titleText:SetPoint("TOPLEFT", 12, yOff)
    titleText:SetText("|cffF5C842Character Morph|r")
    yOff = yOff - 24

    local subtitleText = morphTab:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    subtitleText:SetPoint("TOPLEFT", 12, yOff)
    subtitleText:SetText("|cff998866Change your character model. Client-side only.|r")
    yOff = yOff - 24

    -- Race display IDs: [race][gender] = displayId
    -- gender: 1 = neutral/unknown, 2 = male, 3 = female
    -- EXACT working IDs verified in-game
    local raceDisplayIds = {
        ["Human"]      = { [2] = 19723, [3] = 19724 },  -- Exact from SimplyMorpher3
        ["Orc"]        = { [2] = 6785,  [3] = 20316 },  -- Male: verified working, Female: exact
        ["Dwarf"]      = { [2] = 20317, [3] = 13250 },  -- Male: exact, Female: first from SimplyMorpher3 list
        ["Night Elf"]  = { [2] = 20318, [3] = 2222  },  -- Male: exact, Female: verified working
        ["Undead"]     = { [2] = 28193, [3] = 23112 },  -- Both: first from SimplyMorpher3 lists
        ["Tauren"]     = { [2] = 20585, [3] = 20584 },  -- Both exact from SimplyMorpher3
        ["Gnome"]      = { [2] = 20580, [3] = 20581 },  -- Both exact from SimplyMorpher3
        ["Troll"]      = { [2] = 20321, [3] = 4358  },  -- Male: exact, Female: verified working
        ["Blood Elf"]  = { [2] = 20578, [3] = 20579 },  -- Both exact from SimplyMorpher3
        ["Draenei"]    = { [2] = 17155, [3] = 20323 },  -- Male: verified working, Female: exact
    }
    local raceOrder = {"Human", "Orc", "Dwarf", "Night Elf", "Undead", "Tauren", "Gnome", "Troll", "Blood Elf", "Draenei"}
    local raceIcons = {
        ["Human"]      = "Interface\\Glues\\CharacterCreate\\UI-CharacterCreate-Races",
        ["Orc"]        = "Interface\\Glues\\CharacterCreate\\UI-CharacterCreate-Races",
        ["Dwarf"]      = "Interface\\Glues\\CharacterCreate\\UI-CharacterCreate-Races",
        ["Night Elf"]  = "Interface\\Glues\\CharacterCreate\\UI-CharacterCreate-Races",
        ["Undead"]     = "Interface\\Glues\\CharacterCreate\\UI-CharacterCreate-Races",
        ["Tauren"]     = "Interface\\Glues\\CharacterCreate\\UI-CharacterCreate-Races",
        ["Gnome"]      = "Interface\\Glues\\CharacterCreate\\UI-CharacterCreate-Races",
        ["Troll"]      = "Interface\\Glues\\CharacterCreate\\UI-CharacterCreate-Races",
        ["Blood Elf"]  = "Interface\\Glues\\CharacterCreate\\UI-CharacterCreate-Races",
        ["Draenei"]    = "Interface\\Glues\\CharacterCreate\\UI-CharacterCreate-Races",
    }

    -- Section: Race Morph
    local raceLabel = morphTab:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    raceLabel:SetPoint("TOPLEFT", 10, yOff)
    raceLabel:SetText("|cffF5C842Race Morph|r")
    yOff = yOff - 20

    local btnWidth = 120
    local btnHeight = 22
    local col = 0
    local startY = yOff

    for i, raceName in ipairs(raceOrder) do
        local ids = raceDisplayIds[raceName]
        local safeRaceName = raceName:gsub("%s+", "")

        -- Male button
        local btnM = CreateGoldenButton("$parentRace"..safeRaceName.."M", morphTab)
        btnM:SetSize(btnWidth, btnHeight)
        local xM = 10 + col * (btnWidth + 5)
        btnM:SetPoint("TOPLEFT", xM, yOff - (math.ceil(i/2) - 1) * (btnHeight + 3))
        btnM:SetText(raceName .. " M")
        btnM:SetScript("OnClick", function()
            if IsMorpherReady() then
                SendMorphCommand("MORPH:" .. ids[2])
                UpdatePreviewModel()
                UpdateSpecialSlots()
                SELECTED_CHAT_FRAME:AddMessage("|cffF5C842<Transmorpher>|r: Morphed to " .. raceName .. " Male (" .. ids[2] .. ")")
            end
            PlaySound("gsTitleOptionOK")
        end)
        btnM:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:AddLine(raceName .. " Male")
            GameTooltip:AddLine("Display ID: " .. ids[2], 1, 1, 1)
            GameTooltip:Show()
        end)
        btnM:SetScript("OnLeave", function() GameTooltip:Hide() end)

        -- Female button
        local btnF = CreateGoldenButton("$parentRace"..safeRaceName.."F", morphTab)
        btnF:SetSize(btnWidth, btnHeight)
        local xF = 10 + (col + 1) * (btnWidth + 5)
        btnF:SetPoint("TOPLEFT", xF, yOff - (math.ceil(i/2) - 1) * (btnHeight + 3))
        btnF:SetText(raceName .. " F")
        btnF:SetScript("OnClick", function()
            if IsMorpherReady() then
                SendMorphCommand("MORPH:" .. ids[3])
                UpdatePreviewModel()
                UpdateSpecialSlots()
                SELECTED_CHAT_FRAME:AddMessage("|cffF5C842<Transmorpher>|r: Morphed to " .. raceName .. " Female (" .. ids[3] .. ")")
            end
            PlaySound("gsTitleOptionOK")
        end)
        btnF:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:AddLine(raceName .. " Female")
            GameTooltip:AddLine("Display ID: " .. ids[3], 1, 1, 1)
            GameTooltip:Show()
        end)
        btnF:SetScript("OnLeave", function() GameTooltip:Hide() end)

        if i % 2 == 0 then col = 0 else col = 2 end
    end

    local raceSectionHeight = math.ceil(#raceOrder / 2) * (btnHeight + 3) + 10
    yOff = yOff - raceSectionHeight - 10

    -- Separator
    local sep1 = morphTab:CreateTexture(nil, "ARTWORK")
    sep1:SetTexture("Interface\\Tooltips\\UI-Tooltip-Border")
    sep1:SetTexCoord(0.81, 0.94, 0.5, 1)
    sep1:SetPoint("TOPLEFT", 10, yOff)
    sep1:SetPoint("RIGHT", -10, 0)
    sep1:SetHeight(8)
    sep1:SetVertexColor(0.80, 0.65, 0.22)
    yOff = yOff - 14

    -- Section: Custom Display ID (with creature search)
    local customLabel = morphTab:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    customLabel:SetPoint("TOPLEFT", 10, yOff)
    customLabel:SetText("|cffF5C842Custom Display ID|r")
    yOff = yOff - 18

    local customDesc = morphTab:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    customDesc:SetPoint("TOPLEFT", 10, yOff)
    customDesc:SetText("|cff998866Search by creature name or enter a display ID directly:|r")
    yOff = yOff - 22

    -- Search bar container (modern dark box with golden accent)
    local searchContainer = CreateFrame("Frame", nil, morphTab)
    searchContainer:SetSize(370, 28)
    searchContainer:SetPoint("TOPLEFT", 10, yOff)
    searchContainer:SetBackdrop({
        bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 12,
        insets = { left = 3, right = 3, top = 3, bottom = 3 }
    })
    searchContainer:SetBackdropColor(0.06, 0.05, 0.03, 0.95)
    searchContainer:SetBackdropBorderColor(0.60, 0.50, 0.18, 0.8)

    local searchIcon = searchContainer:CreateTexture(nil, "OVERLAY")
    searchIcon:SetSize(14, 14)
    searchIcon:SetPoint("LEFT", 6, 0)
    searchIcon:SetTexture("Interface\\Common\\UI-Searchbox-Icon")
    searchIcon:SetVertexColor(0.80, 0.65, 0.22)

    -- Search/ID input (accepts both text and numbers)
    local editBox = CreateFrame("EditBox", "$parentMorphIdInput", searchContainer)
    editBox:SetSize(310, 18)
    editBox:SetPoint("LEFT", searchIcon, "RIGHT", 4, 0)
    editBox:SetAutoFocus(false)
    editBox:SetNumeric(false)
    editBox:SetMaxLetters(40)
    editBox:SetFont("Fonts\\FRIZQT__.TTF", 11)
    editBox:SetTextColor(0.95, 0.88, 0.65)

    local editHint = editBox:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    editHint:SetPoint("LEFT", 2, 0)
    editHint:SetText("Name or display ID...")

    -- Clear button
    local editClear = CreateFrame("Button", nil, searchContainer)
    editClear:SetSize(14, 14)
    editClear:SetPoint("RIGHT", -4, 0)
    editClear:SetNormalTexture("Interface\\FriendsFrame\\ClearBroadcastIcon")
    editClear:SetAlpha(0.5)
    editClear:Hide()
    editClear:SetScript("OnEnter", function(self) self:SetAlpha(1) end)
    editClear:SetScript("OnLeave", function(self) self:SetAlpha(0.5) end)

    -- Selected display from search results
    local selectedSearchID = nil
    local selectedSearchName = nil

    -- Search results dropdown (created BEFORE handlers that reference it)
    local searchDropBg = CreateFrame("Frame", "$parentMorphSearchDrop", actualMorphTab)
    searchDropBg:SetPoint("TOPLEFT", searchContainer, "BOTTOMLEFT", 0, 2)
    searchDropBg:SetSize(370, 1)
    searchDropBg:SetBackdrop({
        bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 12,
        insets = { left = 2, right = 2, top = 2, bottom = 2 }
    })
    searchDropBg:SetBackdropColor(0.06, 0.05, 0.03, 0.97)
    searchDropBg:SetBackdropBorderColor(0.80, 0.65, 0.22, 0.9)
    searchDropBg:SetFrameStrata("DIALOG")
    searchDropBg:Hide()

    -- Now set up handlers that use searchDropBg
    editBox:SetScript("OnEscapePressed", function(self)
        searchDropBg:Hide()
        self:ClearFocus()
    end)
    editBox:SetScript("OnEditFocusGained", function() editHint:Hide() end)
    editBox:SetScript("OnEditFocusLost", function(self)
        if self:GetText() == "" then editHint:Show(); editClear:Hide() end
        local hideTimer = CreateFrame("Frame")
        hideTimer.elapsed = 0
        hideTimer:SetScript("OnUpdate", function(f, dt)
            f.elapsed = f.elapsed + dt
            if f.elapsed >= 0.2 then
                f:Hide()
                f:SetScript("OnUpdate", nil)
                if not editBox:HasFocus() then searchDropBg:Hide() end
            end
        end)
    end)
    editClear:SetScript("OnClick", function()
        editBox:SetText("")
        editBox:ClearFocus()
        editHint:Show()
        editClear:Hide()
        searchDropBg:Hide()
        selectedSearchID = nil
        selectedSearchName = nil
    end)

    local btnApplyCustom = CreateGoldenButton("$parentBtnApplyCustom", morphTab)
    btnApplyCustom:SetSize(90, 22)
    btnApplyCustom:SetPoint("LEFT", searchContainer, "RIGHT", 8, 0)
    btnApplyCustom:SetText("|cffF5C842Apply|r")

    local searchDropScroll = CreateFrame("ScrollFrame", "$parentMorphSearchDropScroll", searchDropBg, "UIPanelScrollFrameTemplate")
    searchDropScroll:SetPoint("TOPLEFT", 4, -4)
    searchDropScroll:SetPoint("BOTTOMRIGHT", -22, 4)

    local searchDropContent = CreateFrame("Frame", "$parentMorphSearchDropContent", searchDropScroll)
    searchDropContent:SetSize(searchDropScroll:GetWidth(), 1)
    searchDropScroll:SetScrollChild(searchDropContent)

    local SEARCH_ROW_H = 20
    local MAX_SEARCH_ROWS = 10
    local searchResultButtons = {}

    -- Pre-build sorted creature list for morph search (reuse combat pet one if exists, else build own)
    local morphCreatureSorted = nil
    local function GetMorphCreatureSorted()
        if morphCreatureSorted then return morphCreatureSorted end
        morphCreatureSorted = {}
        local db = ns.creatureDisplayDB
        if not db then return morphCreatureSorted end
        for did, name in pairs(db) do
            table.insert(morphCreatureSorted, { did = did, name = name, nameLower = name:lower() })
        end
        table.sort(morphCreatureSorted, function(a, b) return a.name < b.name end)
        return morphCreatureSorted
    end

    local function ShowSearchResults(query)
        -- Clear old
        for _, b in ipairs(searchResultButtons) do b:Hide() end
        searchResultButtons = {}
        selectedSearchID = nil
        selectedSearchName = nil

        if not query or #query < 2 then
            searchDropBg:Hide()
            return
        end

        local q = query:lower()
        local results = {}
        local sorted = GetMorphCreatureSorted()
        local count = 0

        -- Check if it's a pure number (display ID search)
        local isNumericQuery = tonumber(query) ~= nil

        for _, entry in ipairs(sorted) do
            local match = false
            if isNumericQuery then
                match = tostring(entry.did):find(q, 1, true) ~= nil
            else
                match = entry.nameLower:find(q, 1, true) ~= nil
            end
            if match then
                table.insert(results, entry)
                count = count + 1
                if count >= MAX_SEARCH_ROWS * 5 then break end -- gather extra for scrolling
            end
        end

        if #results == 0 then
            searchDropBg:Hide()
            return
        end

        local visibleRows = math.min(#results, MAX_SEARCH_ROWS)
        local dropH = visibleRows * (SEARCH_ROW_H + 1) + 10
        searchDropBg:SetHeight(dropH)
        searchDropBg:Show()

        local bY = 0
        for idx, entry in ipairs(results) do
            local row = CreateFrame("Button", nil, searchDropContent)
            row:SetSize(searchDropContent:GetWidth() - 4, SEARCH_ROW_H)
            row:SetPoint("TOPLEFT", 2, -bY)

            local rowBg = row:CreateTexture(nil, "BACKGROUND")
            rowBg:SetAllPoints()
            if idx % 2 == 0 then
                rowBg:SetTexture(1, 1, 1, 0.03)
            else
                rowBg:SetTexture(0, 0, 0, 0)
            end

            local nameStr = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            nameStr:SetPoint("LEFT", 6, 0)
            nameStr:SetText("|cffffd700" .. entry.name .. "|r")
            nameStr:SetWidth(230)
            nameStr:SetJustifyH("LEFT")

            local idStr = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            idStr:SetPoint("RIGHT", -6, 0)
            idStr:SetText("|cff888888" .. entry.did .. "|r")

            row:SetScript("OnClick", function()
                selectedSearchID = entry.did
                selectedSearchName = entry.name
                editBox:SetText(entry.name .. " (" .. entry.did .. ")")
                editBox:SetCursorPosition(0)
                searchDropBg:Hide()
                editBox:ClearFocus()
            end)

            row:SetScript("OnEnter", function()
                rowBg:SetTexture(0.6, 0.48, 0.15, 0.25)
                GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
                GameTooltip:AddLine(entry.name)
                GameTooltip:AddLine("Display ID: " .. entry.did, 1, 1, 1)
                GameTooltip:AddLine("Click to select", 0.5, 0.5, 0.5)
                GameTooltip:Show()
            end)

            row:SetScript("OnLeave", function()
                if idx % 2 == 0 then
                    rowBg:SetTexture(1, 1, 1, 0.03)
                else
                    rowBg:SetTexture(0, 0, 0, 0)
                end
                GameTooltip:Hide()
            end)

            table.insert(searchResultButtons, row)
            bY = bY + SEARCH_ROW_H + 1
        end

        searchDropContent:SetHeight(math.max(1, bY))
    end

    -- Search debounce timer
    local morphSearchTimer = CreateFrame("Frame")
    morphSearchTimer:Hide()
    morphSearchTimer.elapsed = 0
    morphSearchTimer:SetScript("OnUpdate", function(self, dt)
        self.elapsed = self.elapsed + dt
        if self.elapsed >= 0.3 then
            self:Hide()
            local text = editBox:GetText()
            -- Don't search if user selected a result (text contains " (ID)")
            if text:find("%(", 1, true) then return end
            ShowSearchResults(text)
        end
    end)

    editBox:SetScript("OnTextChanged", function(self, userInput)
        if userInput then
            selectedSearchID = nil
            selectedSearchName = nil
            morphSearchTimer.elapsed = 0
            morphSearchTimer:Show()
            if self:GetText() ~= "" then editClear:Show() else editClear:Hide() end
        end
    end)

    editBox:SetScript("OnEnterPressed", function(self)
        -- If a search result was selected, apply it
        if selectedSearchID then
            if IsMorpherReady() then
                SendMorphCommand("MORPH:" .. selectedSearchID)
                UpdatePreviewModel()
                SELECTED_CHAT_FRAME:AddMessage("|cffF5C842<Transmorpher>|r: Morphed to " .. (selectedSearchName or "creature") .. " (" .. selectedSearchID .. ")")
            end
        else
            -- Try as numeric ID
            local text = self:GetText()
            -- Extract number from text like "Name (12345)"
            local id = tonumber(text:match("%((%d+)%)")) or tonumber(text)
            if id and id > 0 and IsMorpherReady() then
                SendMorphCommand("MORPH:" .. id)
                UpdatePreviewModel()
                SELECTED_CHAT_FRAME:AddMessage("|cffF5C842<Transmorpher>|r: Morphed to display ID " .. id)
            end
        end
        searchDropBg:Hide()
        self:ClearFocus()
    end)

    -- Apply button
    btnApplyCustom:SetScript("OnClick", function()
        if selectedSearchID then
            if IsMorpherReady() then
                SendMorphCommand("MORPH:" .. selectedSearchID)
                UpdatePreviewModel()
                UpdateSpecialSlots()
                SELECTED_CHAT_FRAME:AddMessage("|cffF5C842<Transmorpher>|r: Morphed to " .. (selectedSearchName or "creature") .. " (" .. selectedSearchID .. ")")
                PlaySound("gsTitleOptionOK")
            else
                SELECTED_CHAT_FRAME:AddMessage("|cffF5C842<Transmorpher>|r: |cffff0000DLL not loaded!|r")
            end
        else
            local text = editBox:GetText()
            local id = tonumber(text:match("%((%d+)%)")) or tonumber(text)
            if id and id > 0 and IsMorpherReady() then
                SendMorphCommand("MORPH:" .. id)
                UpdatePreviewModel()
                UpdateSpecialSlots()
                SELECTED_CHAT_FRAME:AddMessage("|cffF5C842<Transmorpher>|r: Morphed to display ID " .. id)
                PlaySound("gsTitleOptionOK")
            else
                SELECTED_CHAT_FRAME:AddMessage("|cffF5C842<Transmorpher>|r: Search for a creature or enter a valid display ID.")
            end
        end
        searchDropBg:Hide()
    end)

    -- Close dropdown when clicking elsewhere
    hooksecurefunc("CloseDropDownMenus", function() searchDropBg:Hide() end)

    yOff = yOff - 30

    -- Size (Scale) section
    local sizeLabel = morphTab:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    sizeLabel:SetPoint("TOPLEFT", 10, yOff)
    sizeLabel:SetText("|cffF5C842Character Size|r")
    yOff = yOff - 20

    local sizeEditBox = CreateFrame("EditBox", "$parentMorphSizeInput", morphTab, "InputBoxTemplate")
    sizeEditBox:SetSize(60, 20)
    sizeEditBox:SetPoint("TOPLEFT", 15, yOff)
    sizeEditBox:SetAutoFocus(false)
    sizeEditBox:SetNumeric(false) -- Allow decimals
    sizeEditBox:SetMaxLetters(4)
    sizeEditBox:SetText("1.0")
    sizeEditBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)

    local btnApplySize = CreateGoldenButton("$parentBtnApplySize", morphTab)
    btnApplySize:SetSize(90, 22)
    btnApplySize:SetPoint("LEFT", sizeEditBox, "RIGHT", 10, 0)
    btnApplySize:SetText("|cffF5C842Apply Size|r")
    btnApplySize:SetScript("OnClick", function()
        local scale = tonumber(sizeEditBox:GetText())
        if scale and scale > 0.1 and scale < 10.0 and IsMorpherReady() then
            SendMorphCommand("SCALE:" .. scale)
            SELECTED_CHAT_FRAME:AddMessage("|cffF5C842<Transmorpher>|r: Scaled character to " .. scale)
            PlaySound("gsTitleOptionOK")
        else
            SELECTED_CHAT_FRAME:AddMessage("|cffF5C842<Transmorpher>|r: Enter a valid scale (0.1 to 10.0).")
        end
    end)
    
    yOff = yOff - 40

    -- ============================================================
    -- Saved Morph Favorites
    -- ============================================================
    local favSep = morphTab:CreateTexture(nil, "ARTWORK")
    favSep:SetTexture("Interface\\Tooltips\\UI-Tooltip-Border")
    favSep:SetTexCoord(0.81, 0.94, 0.5, 1)
    favSep:SetPoint("TOPLEFT", 10, yOff)
    favSep:SetPoint("RIGHT", -10, 0)
    favSep:SetHeight(8)
    favSep:SetVertexColor(0.80, 0.65, 0.22)
    yOff = yOff - 14

    local favLabel = morphTab:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    favLabel:SetPoint("TOPLEFT", 10, yOff)
    favLabel:SetText("|cffF5C842Saved Morphs|r")
    yOff = yOff - 18

    local favDesc = morphTab:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    favDesc:SetPoint("TOPLEFT", 10, yOff)
    favDesc:SetText("|cff998866Save display IDs with a name for quick access. Use the search above to find IDs.|r")
    yOff = yOff - 18

    -- Save controls: [Name input] [ID input] [Save button]
    local favNameInput = CreateFrame("EditBox", "$parentFavNameInput", morphTab, "InputBoxTemplate")
    favNameInput:SetSize(130, 20)
    favNameInput:SetPoint("TOPLEFT", 15, yOff)
    favNameInput:SetAutoFocus(false)
    favNameInput:SetMaxLetters(24)
    favNameInput:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)

    local favNameHint = favNameInput:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    favNameHint:SetPoint("LEFT", 4, 0)
    favNameHint:SetText("Name")
    favNameInput:SetScript("OnEditFocusGained", function() favNameHint:Hide() end)
    favNameInput:SetScript("OnEditFocusLost", function(self)
        if self:GetText() == "" then favNameHint:Show() end
    end)

    local favIdInput = CreateFrame("EditBox", "$parentFavIdInput", morphTab, "InputBoxTemplate")
    favIdInput:SetSize(70, 20)
    favIdInput:SetPoint("LEFT", favNameInput, "RIGHT", 8, 0)
    favIdInput:SetAutoFocus(false)
    favIdInput:SetNumeric(true)
    favIdInput:SetMaxLetters(6)
    favIdInput:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)

    local favIdHint = favIdInput:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    favIdHint:SetPoint("LEFT", 4, 0)
    favIdHint:SetText("ID")
    favIdInput:SetScript("OnEditFocusGained", function() favIdHint:Hide() end)
    favIdInput:SetScript("OnEditFocusLost", function(self)
        if self:GetText() == "" then favIdHint:Show() end
    end)

    local btnFavSave = CreateGoldenButton("$parentBtnFavSave", morphTab)
    btnFavSave:SetSize(60, 20)
    btnFavSave:SetPoint("LEFT", favIdInput, "RIGHT", 8, 0)
    btnFavSave:SetText("|cffF5C842Save|r")

    local btnFavRemove = CreateGoldenButton("$parentBtnFavRemove", morphTab)
    btnFavRemove:SetSize(70, 20)
    btnFavRemove:SetPoint("LEFT", btnFavSave, "RIGHT", 4, 0)
    btnFavRemove:SetText("Remove")
    btnFavRemove:Disable()

    yOff = yOff - 26

    -- Favorites list area (scrollable)
    local favListBg = CreateFrame("Frame", "$parentFavListBg", morphTab)
    favListBg:SetPoint("TOPLEFT", 10, yOff)
    favListBg:SetSize(480, 100)
    favListBg:SetBackdrop({
        bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 12,
        insets = { left = 2, right = 2, top = 2, bottom = 2 }
    })
    favListBg:SetBackdropColor(0.04, 0.03, 0.03, 0.9)
    favListBg:SetBackdropBorderColor(0.80, 0.65, 0.22, 0.85)

    local favScroll = CreateFrame("ScrollFrame", "$parentFavScroll", favListBg, "UIPanelScrollFrameTemplate")
    favScroll:SetPoint("TOPLEFT", 4, -4)
    favScroll:SetPoint("BOTTOMRIGHT", -22, 4)

    local favContent = CreateFrame("Frame", "$parentFavContent", favScroll)
    favContent:SetSize(favScroll:GetWidth(), 1)
    favScroll:SetScrollChild(favContent)

    local favButtons = {}
    local favSelectedIdx = nil

    local function BuildFavButtons()
        -- Clear old buttons
        for _, b in ipairs(favButtons) do b:Hide() end
        favButtons = {}
        favSelectedIdx = nil
        btnFavRemove:Disable()

        if not _G["TransmorpherMorphFavorites"] then _G["TransmorpherMorphFavorites"] = {} end
        local favs = _G["TransmorpherMorphFavorites"]

        local bY = 0
        for idx, fav in ipairs(favs) do
            local row = CreateFrame("Button", nil, favContent)
            row:SetSize(favContent:GetWidth() - 4, 20)
            row:SetPoint("TOPLEFT", 2, -bY)

            local rowBg = row:CreateTexture(nil, "BACKGROUND")
            rowBg:SetAllPoints()
            rowBg:SetTexture(0, 0, 0, 0)

            local nameStr = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            nameStr:SetPoint("LEFT", 4, 0)
            nameStr:SetText("|cffffd700" .. fav.name .. "|r")
            nameStr:SetWidth(200)
            nameStr:SetJustifyH("LEFT")

            local idStr = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            idStr:SetPoint("LEFT", nameStr, "RIGHT", 8, 0)
            idStr:SetText("|cff8a7d6aID: " .. fav.id .. "|r")

            local useBtn = CreateGoldenButton("TransmorpherFavUseBtn"..idx, row)
            useBtn:SetSize(50, 18)
            useBtn:SetPoint("RIGHT", -2, 0)
            useBtn:SetText("|cffF5C842Use|r")
            useBtn:SetScript("OnClick", function()
                if IsMorpherReady() then
                    SendMorphCommand("MORPH:" .. fav.id)
                    UpdatePreviewModel()
                    UpdateSpecialSlots()
                    SELECTED_CHAT_FRAME:AddMessage("|cffF5C842<Transmorpher>|r: Morphed to " .. fav.name .. " (" .. fav.id .. ")")
                end
                PlaySound("gsTitleOptionOK")
            end)

            -- Selection highlight
            row:SetScript("OnClick", function()
                -- Deselect previous
                if favSelectedIdx and favButtons[favSelectedIdx] then
                    favButtons[favSelectedIdx].bg:SetTexture(0, 0, 0, 0)
                end
                favSelectedIdx = idx
                rowBg:SetTexture(0.6, 0.48, 0.15, 0.3)
                btnFavRemove:Enable()
            end)
            row:SetScript("OnEnter", function()
                if favSelectedIdx ~= idx then rowBg:SetTexture(1, 1, 1, 0.05) end
                GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
                GameTooltip:AddLine(fav.name)
                GameTooltip:AddLine("Display ID: " .. fav.id, 1, 1, 1)
                GameTooltip:AddLine("Click to select, Use to morph", 0.5, 0.5, 0.5)
                GameTooltip:Show()
            end)
            row:SetScript("OnLeave", function()
                if favSelectedIdx ~= idx then rowBg:SetTexture(0, 0, 0, 0) end
                GameTooltip:Hide()
            end)

            row.bg = rowBg
            table.insert(favButtons, row)
            bY = bY + 21
        end

        favContent:SetHeight(math.max(1, bY))
    end

    -- Save favorite
    btnFavSave:SetScript("OnClick", function()
        local name = favNameInput:GetText()
        local id = tonumber(favIdInput:GetText())
        if not name or name == "" then
            SELECTED_CHAT_FRAME:AddMessage("|cffF5C842<Transmorpher>|r: Enter a name for the morph.")
            return
        end
        if not id or id <= 0 then
            SELECTED_CHAT_FRAME:AddMessage("|cffF5C842<Transmorpher>|r: Enter a valid display ID.")
            return
        end
        if not _G["TransmorpherMorphFavorites"] then _G["TransmorpherMorphFavorites"] = {} end
        table.insert(_G["TransmorpherMorphFavorites"], { name = name, id = id })
        favNameInput:SetText("") favIdInput:SetText("")
        favNameHint:Show() favIdHint:Show()
        favNameInput:ClearFocus() favIdInput:ClearFocus()
        BuildFavButtons()
        SELECTED_CHAT_FRAME:AddMessage("|cffF5C842<Transmorpher>|r: Saved morph '" .. name .. "' (ID: " .. id .. ")")
        PlaySound("gsTitleOptionOK")
    end)

    -- Remove favorite
    btnFavRemove:SetScript("OnClick", function()
        if favSelectedIdx and _G["TransmorpherMorphFavorites"] then
            local fav = _G["TransmorpherMorphFavorites"][favSelectedIdx]
            if fav then
                table.remove(_G["TransmorpherMorphFavorites"], favSelectedIdx)
                SELECTED_CHAT_FRAME:AddMessage("|cffF5C842<Transmorpher>|r: Removed '" .. fav.name .. "'")
            end
            BuildFavButtons()
            PlaySound("gsTitleOptionOK")
        end
    end)

    -- Build on first show
    morphTab:HookScript("OnShow", function() BuildFavButtons() end)

    yOff = yOff - 110

    -- Separator before popular creatures
    local sep2 = morphTab:CreateTexture(nil, "ARTWORK")
    sep2:SetTexture("Interface\\Tooltips\\UI-Tooltip-Border")
    sep2:SetTexCoord(0.81, 0.94, 0.5, 1)
    sep2:SetPoint("TOPLEFT", 10, yOff)
    sep2:SetPoint("RIGHT", -10, 0)
    sep2:SetHeight(8)
    sep2:SetVertexColor(0.80, 0.65, 0.22)
    yOff = yOff - 14

    -- Current display info
    local infoLabel = morphTab:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    infoLabel:SetPoint("TOPLEFT", 10, yOff)
    infoLabel:SetText("")
    yOff = yOff - 16

    -- Popular creature morphs section
    local creaturesLabel = morphTab:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    creaturesLabel:SetPoint("TOPLEFT", 10, yOff)
    creaturesLabel:SetText("|cffF5C842Popular Creatures|r")
    yOff = yOff - 20

    local popularCreatures = {
        { name = "Lich King",     id = 22234 },
        { name = "Illidan",       id = 21135 },
        { name = "Sylvanas",      id = 28213 },
        { name = "Alexstrasza",   id = 28227 },
        
        { name = "Ragnaros",      id = 11121 },
        { name = "Brann Bronzebeard",        id = 22266 },
        { name = "Malygos",       id = 26752 },
        { name = "Tuskarr",    id = 24685 },
        
        { name = "Kel'Thuzad",    id = 15945 },
        { name = "Yogg-Saron",    id = 28817 },
        { name = "Kael'thas",     id = 20023 },
        { name = "Lady Vashj",    id = 20748 },
        
        { name = "Nefarian",      id = 11380 },
        { name = "Onyxia",        id = 8570  },
        { name = "Arthas",        id = 24949 },
        { name = "Uther",         id = 16929 },
        
        { name = "Evil Arthas",           id = 22235 },
        { name = "Velen",        id = 23749 },
        { name = "Dark Valkier",   id = 25517 },
        { name = "Penguin",          id = 24698 },
    }

    col = 0
    local creatureRow = 0
    for i, creature in ipairs(popularCreatures) do
        local btn = CreateGoldenButton("$parentCreature"..i, morphTab)
        btn:SetSize(btnWidth, btnHeight)
        btn:SetPoint("TOPLEFT", 10 + col * (btnWidth + 5), yOff - creatureRow * (btnHeight + 3))
        btn:SetText(creature.name)
        btn:SetScript("OnClick", function()
            if IsMorpherReady() then
                SendMorphCommand("MORPH:" .. creature.id)
                UpdatePreviewModel()
                UpdateSpecialSlots()
                SELECTED_CHAT_FRAME:AddMessage("|cffF5C842<Transmorpher>|r: Morphed to " .. creature.name .. " (" .. creature.id .. ")")
            end
            PlaySound("gsTitleOptionOK")
        end)
        btn:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:AddLine(creature.name)
            GameTooltip:AddLine("Display ID: " .. creature.id, 1, 1, 1)
            GameTooltip:Show()
        end)
        btn:SetScript("OnLeave", function() GameTooltip:Hide() end)

        col = col + 1
        if col >= 4 then col = 0; creatureRow = creatureRow + 1 end
    end

    local creatureSectionHeight = math.ceil(#popularCreatures / 4) * (btnHeight + 3) + 10
    yOff = yOff - creatureSectionHeight - 10

    -- Reset morph button (big, at bottom)
    local btnResetMorph = CreateGoldenButton("$parentBtnResetModel", morphTab)
    btnResetMorph:SetSize(200, 28)
    btnResetMorph:SetPoint("TOPLEFT", 10, yOff)
    btnResetMorph:SetText("|cffF5C842Reset Character Model|r")
    btnResetMorph:SetScript("OnClick", function()
        if IsMorpherReady() then
            SendMorphCommand("MORPH:0")
            -- Immediately clear the state for instant visual update
            if TransmorpherCharacterState then
                TransmorpherCharacterState.Morph = nil
            end
            UpdatePreviewModel()
            UpdateSpecialSlots()
            SELECTED_CHAT_FRAME:AddMessage("|cffF5C842<Transmorpher>|r: Character morph reset!")
        end
        PlaySound("gsTitleOptionOK")
    end)

    -- Update display info on show
    morphTab:SetScript("OnShow", function()
        infoLabel:SetText("|cff8a7d6aDisplay info not available in stealth mode.|r")
    end)
end

---------------- MOUNTS TAB ----------------

do
    local mountTab = mainFrame.tabs.mounts
    local ROW_HEIGHT = 32

    -- Search bar container
    local searchContainer = CreateFrame("Frame", nil, mountTab)
    searchContainer:SetPoint("TOPLEFT", 6, -6)
    searchContainer:SetPoint("RIGHT", -6, 0)
    searchContainer:SetHeight(26)
    searchContainer:SetBackdrop({
        bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 12,
        insets = { left = 3, right = 3, top = 3, bottom = 3 }
    })
    searchContainer:SetBackdropColor(0.06, 0.05, 0.03, 0.95)
    searchContainer:SetBackdropBorderColor(0.60, 0.50, 0.18, 0.8)

    local searchIcon = searchContainer:CreateTexture(nil, "OVERLAY")
    searchIcon:SetSize(14, 14)
    searchIcon:SetPoint("LEFT", 6, 0)
    searchIcon:SetTexture("Interface\\Common\\UI-Searchbox-Icon")
    searchIcon:SetVertexColor(0.80, 0.65, 0.22)

    local searchBox = CreateFrame("EditBox", "$parentMountSearch", searchContainer)
    searchBox:SetSize(480, 18)
    searchBox:SetPoint("LEFT", searchIcon, "RIGHT", 4, 0)
    searchBox:SetPoint("RIGHT", -24, 0)
    searchBox:SetAutoFocus(false)
    searchBox:SetMaxLetters(40)
    searchBox:SetFont("Fonts\\FRIZQT__.TTF", 11)
    searchBox:SetTextColor(0.95, 0.88, 0.65)
    searchBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)

    local searchHint = searchBox:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    searchHint:SetPoint("LEFT", 2, 0)
    searchHint:SetText("Search mounts...")
    searchBox:SetScript("OnEditFocusGained", function() searchHint:Hide() end)
    searchBox:SetScript("OnEditFocusLost", function(self)
        if self:GetText() == "" then searchHint:Show() end
    end)

    local searchClear = CreateFrame("Button", nil, searchContainer)
    searchClear:SetSize(14, 14)
    searchClear:SetPoint("RIGHT", -4, 0)
    searchClear:SetNormalTexture("Interface\\FriendsFrame\\ClearBroadcastIcon")
    searchClear:SetAlpha(0.5)
    searchClear:Hide()
    searchClear:SetScript("OnEnter", function(self) self:SetAlpha(1) end)
    searchClear:SetScript("OnLeave", function(self) self:SetAlpha(0.5) end)
    searchClear:SetScript("OnClick", function()
        searchBox:SetText("")
        searchBox:ClearFocus()
        searchHint:Show()
        searchClear:Hide()
    end)

    -- List background (full width)
    local listBg = CreateFrame("Frame", "$parentMountListBg", mountTab)
    listBg:SetPoint("TOPLEFT", 6, -32)
    listBg:SetPoint("BOTTOMRIGHT", -6, 38)
    listBg:SetBackdrop({
        bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 12,
        insets = { left = 2, right = 2, top = 2, bottom = 2 }
    })
    listBg:SetBackdropColor(0.04, 0.03, 0.03, 0.9)
    listBg:SetBackdropBorderColor(0.80, 0.65, 0.22, 0.85)

    local listScroll = CreateFrame("ScrollFrame", "$parentMountListScroll", listBg, "UIPanelScrollFrameTemplate")
    listScroll:SetPoint("TOPLEFT", 4, -4)
    listScroll:SetPoint("BOTTOMRIGHT", -22, 4)

    local listContent = CreateFrame("Frame", "$parentMountListContent", listScroll)
    listContent:SetSize(listScroll:GetWidth(), 1)
    listScroll:SetScrollChild(listContent)

    -- Bottom buttons
    local btnApplyMount = CreateGoldenButton("$parentBtnApplyMount", mountTab)
    btnApplyMount:SetSize(140, 26)
    btnApplyMount:SetPoint("BOTTOMLEFT", 10, 4)
    btnApplyMount:SetText("|cffF5C842Apply Mount Morph|r")
    btnApplyMount:Disable()

    local btnResetMount = CreateGoldenButton("$parentBtnResetMount", mountTab)
    btnResetMount:SetSize(120, 26)
    btnResetMount:SetPoint("LEFT", btnApplyMount, "RIGHT", 8, 0)
    btnResetMount:SetText("|cffF5C842Reset Mount|r")

    -- State
    local mountButtons = {}
    local mountSelectedIdx = nil
    local mountFilteredList = {}

    local function FilterMounts(query)
        mountFilteredList = {}
        local db = ns.mountsDB or {}
        if not query or query == "" then
            for i, entry in ipairs(db) do
                table.insert(mountFilteredList, { idx = i, name = entry[1], spellID = entry[2], displayID = entry[3], modelPath = entry[4] })
            end
        else
            local q = query:lower()
            for i, entry in ipairs(db) do
                if entry[1]:lower():find(q, 1, true) then
                    table.insert(mountFilteredList, { idx = i, name = entry[1], spellID = entry[2], displayID = entry[3], modelPath = entry[4] })
                end
            end
        end
        return mountFilteredList
    end

    local function BuildMountList()
        for _, b in ipairs(mountButtons) do b:Hide() end
        mountButtons = {}
        mountSelectedIdx = nil
        btnApplyMount:Disable()

        local bY = 0
        for idx, entry in ipairs(mountFilteredList) do
            local row = CreateFrame("Button", nil, listContent)
            row:SetSize(listContent:GetWidth() - 4, ROW_HEIGHT)
            row:SetPoint("TOPLEFT", 2, -bY)

            local rowBg = row:CreateTexture(nil, "BACKGROUND")
            rowBg:SetAllPoints()
            rowBg:SetTexture(0, 0, 0, 0)

            -- Icon
            local icon = row:CreateTexture(nil, "ARTWORK")
            icon:SetSize(ROW_HEIGHT - 4, ROW_HEIGHT - 4)
            icon:SetPoint("LEFT", 4, 0)
            icon:SetTexture(GetSpellIcon(entry.spellID))
            icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

            -- Icon border
            local iconBorder = row:CreateTexture(nil, "OVERLAY")
            iconBorder:SetSize(ROW_HEIGHT - 2, ROW_HEIGHT - 2)
            iconBorder:SetPoint("CENTER", icon, "CENTER", 0, 0)
            iconBorder:SetTexture("Interface\\Buttons\\UI-Quickslot2")
            iconBorder:SetTexCoord(0.2, 0.8, 0.2, 0.8)

            -- Name
            local nameStr = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
            nameStr:SetPoint("LEFT", icon, "RIGHT", 8, 0)
            nameStr:SetText("|cffffd700" .. entry.name .. "|r")
            nameStr:SetJustifyH("LEFT")

            -- Display ID on the right
            local idStr = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            idStr:SetPoint("RIGHT", -8, 0)
            idStr:SetText("|cff6a6050" .. entry.displayID .. "|r")

            row:SetScript("OnClick", function()
                if mountSelectedIdx and mountButtons[mountSelectedIdx] then
                    mountButtons[mountSelectedIdx].bg:SetTexture(0, 0, 0, 0)
                end
                mountSelectedIdx = idx
                rowBg:SetTexture(0.6, 0.48, 0.15, 0.3)
                btnApplyMount:Enable()
            end)

            row:SetScript("OnEnter", function()
                if mountSelectedIdx ~= idx then rowBg:SetTexture(1, 1, 1, 0.05) end
                GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
                GameTooltip:AddLine(entry.name)
                GameTooltip:AddLine("Display ID: " .. entry.displayID, 1, 1, 1)
                if entry.spellID > 0 then
                    GameTooltip:AddLine("Spell ID: " .. entry.spellID, 0.7, 0.7, 0.7)
                end
                GameTooltip:AddLine("Click to select, then Apply", 0.5, 0.5, 0.5)
                GameTooltip:Show()
            end)

            row:SetScript("OnLeave", function()
                if mountSelectedIdx ~= idx then rowBg:SetTexture(0, 0, 0, 0) end
                GameTooltip:Hide()
            end)

            row.bg = rowBg
            table.insert(mountButtons, row)
            bY = bY + ROW_HEIGHT + 1
        end

        listContent:SetHeight(math.max(1, bY))
    end

    -- Search debounce
    local mountSearchTimer = CreateFrame("Frame")
    mountSearchTimer:Hide()
    mountSearchTimer.elapsed = 0
    mountSearchTimer:SetScript("OnUpdate", function(self, dt)
        self.elapsed = self.elapsed + dt
        if self.elapsed >= 0.3 then
            self:Hide()
            FilterMounts(searchBox:GetText())
            BuildMountList()
        end
    end)
    searchBox:SetScript("OnTextChanged", function(self)
        mountSearchTimer.elapsed = 0
        mountSearchTimer:Show()
        if self:GetText() ~= "" then searchClear:Show() else searchClear:Hide() end
    end)

    -- Apply mount morph
    btnApplyMount:SetScript("OnClick", function()
        if mountSelectedIdx and mountFilteredList[mountSelectedIdx] then
            local entry = mountFilteredList[mountSelectedIdx]
            if IsMorpherReady() then
                SendMorphCommand("MOUNT_MORPH:" .. entry.displayID)
                UpdateSpecialSlots()
                SELECTED_CHAT_FRAME:AddMessage("|cffF5C842<Transmorpher>|r: Mount morphed to " .. entry.name .. " (" .. entry.displayID .. ")")
            else
                SELECTED_CHAT_FRAME:AddMessage("|cffF5C842<Transmorpher>|r: |cffff0000DLL not loaded!|r")
            end
            PlaySound("gsTitleOptionOK")
        end
    end)

    -- Reset mount morph
    btnResetMount:SetScript("OnClick", function()
        if IsMorpherReady() then
            SendMorphCommand("MOUNT_RESET")
            UpdateSpecialSlots()
            SELECTED_CHAT_FRAME:AddMessage("|cffF5C842<Transmorpher>|r: Mount appearance reset!")
        end
        PlaySound("gsTitleOptionOK")
    end)

    -- Initialize on show
    mountTab:SetScript("OnShow", function()
        if #mountFilteredList == 0 then
            FilterMounts("")
            BuildMountList()
        end
    end)
end

---------------- PETS TAB ----------------

do
    local petTab = mainFrame.tabs.pets
    local ROW_HEIGHT = 32

    -- Search bar container
    local searchContainer = CreateFrame("Frame", nil, petTab)
    searchContainer:SetPoint("TOPLEFT", 6, -6)
    searchContainer:SetPoint("RIGHT", -6, 0)
    searchContainer:SetHeight(26)
    searchContainer:SetBackdrop({
        bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 12,
        insets = { left = 3, right = 3, top = 3, bottom = 3 }
    })
    searchContainer:SetBackdropColor(0.06, 0.05, 0.03, 0.95)
    searchContainer:SetBackdropBorderColor(0.60, 0.50, 0.18, 0.8)

    local searchIcon = searchContainer:CreateTexture(nil, "OVERLAY")
    searchIcon:SetSize(14, 14)
    searchIcon:SetPoint("LEFT", 6, 0)
    searchIcon:SetTexture("Interface\\Common\\UI-Searchbox-Icon")
    searchIcon:SetVertexColor(0.80, 0.65, 0.22)

    local searchBox = CreateFrame("EditBox", "$parentPetSearch", searchContainer)
    searchBox:SetSize(480, 18)
    searchBox:SetPoint("LEFT", searchIcon, "RIGHT", 4, 0)
    searchBox:SetPoint("RIGHT", -24, 0)
    searchBox:SetAutoFocus(false)
    searchBox:SetMaxLetters(40)
    searchBox:SetFont("Fonts\\FRIZQT__.TTF", 11)
    searchBox:SetTextColor(0.95, 0.88, 0.65)
    searchBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)

    local searchHint = searchBox:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    searchHint:SetPoint("LEFT", 2, 0)
    searchHint:SetText("Search pets...")
    searchBox:SetScript("OnEditFocusGained", function() searchHint:Hide() end)
    searchBox:SetScript("OnEditFocusLost", function(self)
        if self:GetText() == "" then searchHint:Show() end
    end)

    local searchClear = CreateFrame("Button", nil, searchContainer)
    searchClear:SetSize(14, 14)
    searchClear:SetPoint("RIGHT", -4, 0)
    searchClear:SetNormalTexture("Interface\\FriendsFrame\\ClearBroadcastIcon")
    searchClear:SetAlpha(0.5)
    searchClear:Hide()
    searchClear:SetScript("OnEnter", function(self) self:SetAlpha(1) end)
    searchClear:SetScript("OnLeave", function(self) self:SetAlpha(0.5) end)
    searchClear:SetScript("OnClick", function()
        searchBox:SetText("")
        searchBox:ClearFocus()
        searchHint:Show()
        searchClear:Hide()
    end)

    -- List background (full width)
    local listBg = CreateFrame("Frame", "$parentPetListBg", petTab)
    listBg:SetPoint("TOPLEFT", 6, -32)
    listBg:SetPoint("BOTTOMRIGHT", -6, 38)
    listBg:SetBackdrop({
        bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 12,
        insets = { left = 2, right = 2, top = 2, bottom = 2 }
    })
    listBg:SetBackdropColor(0.04, 0.03, 0.03, 0.9)
    listBg:SetBackdropBorderColor(0.80, 0.65, 0.22, 0.85)

    local listScroll = CreateFrame("ScrollFrame", "$parentPetListScroll", listBg, "UIPanelScrollFrameTemplate")
    listScroll:SetPoint("TOPLEFT", 4, -4)
    listScroll:SetPoint("BOTTOMRIGHT", -22, 4)

    local listContent = CreateFrame("Frame", "$parentPetListContent", listScroll)
    listContent:SetSize(listScroll:GetWidth(), 1)
    listScroll:SetScrollChild(listContent)

    -- Bottom buttons
    local btnApplyPet = CreateGoldenButton("$parentBtnApplyPet", petTab)
    btnApplyPet:SetSize(130, 26)
    btnApplyPet:SetPoint("BOTTOMLEFT", 10, 4)
    btnApplyPet:SetText("|cffF5C842Apply Pet Morph|r")
    btnApplyPet:Disable()

    local btnResetPet = CreateGoldenButton("$parentBtnResetPet", petTab)
    btnResetPet:SetSize(110, 26)
    btnResetPet:SetPoint("LEFT", btnApplyPet, "RIGHT", 8, 0)
    btnResetPet:SetText("|cffF5C842Reset Pet|r")

    -- State
    local petButtons = {}
    local petSelectedIdx = nil
    local petFilteredList = {}

    local function FilterPets(query)
        petFilteredList = {}
        local db = ns.petsDB or {}
        if not query or query == "" then
            for i, entry in ipairs(db) do
                table.insert(petFilteredList, { idx = i, name = entry[1], spellID = entry[2], displayID = entry[3], modelPath = entry[4] })
            end
        else
            local q = query:lower()
            for i, entry in ipairs(db) do
                if entry[1]:lower():find(q, 1, true) then
                    table.insert(petFilteredList, { idx = i, name = entry[1], spellID = entry[2], displayID = entry[3], modelPath = entry[4] })
                end
            end
        end
        return petFilteredList
    end

    local function BuildPetList()
        for _, b in ipairs(petButtons) do b:Hide() end
        petButtons = {}
        petSelectedIdx = nil
        btnApplyPet:Disable()

        local bY = 0
        for idx, entry in ipairs(petFilteredList) do
            local row = CreateFrame("Button", nil, listContent)
            row:SetSize(listContent:GetWidth() - 4, ROW_HEIGHT)
            row:SetPoint("TOPLEFT", 2, -bY)

            local rowBg = row:CreateTexture(nil, "BACKGROUND")
            rowBg:SetAllPoints()
            rowBg:SetTexture(0, 0, 0, 0)

            -- Icon
            local icon = row:CreateTexture(nil, "ARTWORK")
            icon:SetSize(ROW_HEIGHT - 4, ROW_HEIGHT - 4)
            icon:SetPoint("LEFT", 4, 0)
            icon:SetTexture(GetSpellIcon(entry.spellID))
            icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

            -- Icon border
            local iconBorder = row:CreateTexture(nil, "OVERLAY")
            iconBorder:SetSize(ROW_HEIGHT - 2, ROW_HEIGHT - 2)
            iconBorder:SetPoint("CENTER", icon, "CENTER", 0, 0)
            iconBorder:SetTexture("Interface\\Buttons\\UI-Quickslot2")
            iconBorder:SetTexCoord(0.2, 0.8, 0.2, 0.8)

            -- Name
            local nameStr = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
            nameStr:SetPoint("LEFT", icon, "RIGHT", 8, 0)
            nameStr:SetText("|cffffd700" .. entry.name .. "|r")
            nameStr:SetJustifyH("LEFT")

            -- Display ID on the right
            local idStr = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            idStr:SetPoint("RIGHT", -8, 0)
            idStr:SetText("|cff6a6050" .. entry.displayID .. "|r")

            row:SetScript("OnClick", function()
                if petSelectedIdx and petButtons[petSelectedIdx] then
                    petButtons[petSelectedIdx].bg:SetTexture(0, 0, 0, 0)
                end
                petSelectedIdx = idx
                rowBg:SetTexture(0.6, 0.48, 0.15, 0.3)
                btnApplyPet:Enable()
            end)

            row:SetScript("OnEnter", function()
                if petSelectedIdx ~= idx then rowBg:SetTexture(1, 1, 1, 0.05) end
                GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
                GameTooltip:AddLine(entry.name)
                GameTooltip:AddLine("Display ID: " .. entry.displayID, 1, 1, 1)
                if entry.spellID > 0 then
                    GameTooltip:AddLine("Spell ID: " .. entry.spellID, 0.7, 0.7, 0.7)
                end
                GameTooltip:AddLine("Click to select, then Apply", 0.5, 0.5, 0.5)
                GameTooltip:Show()
            end)

            row:SetScript("OnLeave", function()
                if petSelectedIdx ~= idx then rowBg:SetTexture(0, 0, 0, 0) end
                GameTooltip:Hide()
            end)

            row.bg = rowBg
            table.insert(petButtons, row)
            bY = bY + ROW_HEIGHT + 1
        end

        listContent:SetHeight(math.max(1, bY))
    end

    -- Search debounce
    local petSearchTimer = CreateFrame("Frame")
    petSearchTimer:Hide()
    petSearchTimer.elapsed = 0
    petSearchTimer:SetScript("OnUpdate", function(self, dt)
        self.elapsed = self.elapsed + dt
        if self.elapsed >= 0.3 then
            self:Hide()
            FilterPets(searchBox:GetText())
            BuildPetList()
        end
    end)
    searchBox:SetScript("OnTextChanged", function(self)
        petSearchTimer.elapsed = 0
        petSearchTimer:Show()
        if self:GetText() ~= "" then searchClear:Show() else searchClear:Hide() end
    end)

    -- Apply pet morph
    btnApplyPet:SetScript("OnClick", function()
        if petSelectedIdx and petFilteredList[petSelectedIdx] then
            local entry = petFilteredList[petSelectedIdx]
            if IsMorpherReady() then
                SendMorphCommand("PET_MORPH:" .. entry.displayID)
                UpdateSpecialSlots()
                SELECTED_CHAT_FRAME:AddMessage("|cffF5C842<Transmorpher>|r: Pet morphed to " .. entry.name .. " (" .. entry.displayID .. ")")
            else
                SELECTED_CHAT_FRAME:AddMessage("|cffF5C842<Transmorpher>|r: |cffff0000DLL not loaded!|r")
            end
            PlaySound("gsTitleOptionOK")
        end
    end)

    -- Reset pet morph
    btnResetPet:SetScript("OnClick", function()
        if IsMorpherReady() then
            SendMorphCommand("PET_RESET")
            UpdateSpecialSlots()
            SELECTED_CHAT_FRAME:AddMessage("|cffF5C842<Transmorpher>|r: Pet appearance reset!")
        end
        PlaySound("gsTitleOptionOK")
    end)

    -- Initialize on show
    petTab:SetScript("OnShow", function()
        if #petFilteredList == 0 then
            FilterPets("")
            BuildPetList()
        end
    end)
end

---------------- COMBAT PETS TAB ----------------

do
    local hpetTab = mainFrame.tabs.combatPets
    local ROW_HEIGHT = 32

    -- ========== MODE TOGGLE (Curated / All Creatures) ==========
    local MODE_CURATED = 1
    local MODE_ALL = 2
    local currentMode = MODE_CURATED

    -- Row 1: Mode buttons + Display ID input
    local topBar = CreateFrame("Frame", nil, hpetTab)
    topBar:SetPoint("TOPLEFT", 6, -4)
    topBar:SetPoint("RIGHT", -6, 0)
    topBar:SetHeight(24)
    topBar:SetBackdrop({
        bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 12,
        insets = { left = 3, right = 3, top = 3, bottom = 3 }
    })
    topBar:SetBackdropColor(0.08, 0.06, 0.03, 0.9)
    topBar:SetBackdropBorderColor(0.60, 0.50, 0.18, 0.7)

    local btnModeCurated = CreateGoldenButton("$parentHPetModeCurated", topBar)
    btnModeCurated:SetSize(120, 20)
    btnModeCurated:SetPoint("LEFT", 4, 0)

    local btnModeAll = CreateGoldenButton("$parentHPetModeAll", topBar)
    btnModeAll:SetSize(120, 20)
    btnModeAll:SetPoint("LEFT", btnModeCurated, "RIGHT", 4, 0)

    -- Display ID input on the right
    local directIDLabel = topBar:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    directIDLabel:SetPoint("RIGHT", topBar, "RIGHT", -64, 0)
    directIDLabel:SetText("|cffC8AA6EDisplay ID:|r")

    local directIDBox = CreateFrame("EditBox", "$parentHPetDirectID", topBar)
    directIDBox:SetSize(56, 16)
    directIDBox:SetPoint("LEFT", directIDLabel, "RIGHT", 4, 0)
    directIDBox:SetAutoFocus(false)
    directIDBox:SetMaxLetters(6)
    directIDBox:SetNumeric(true)
    directIDBox:SetFont("Fonts\\FRIZQT__.TTF", 10)
    directIDBox:SetTextColor(0.95, 0.88, 0.65)
    do
        local idBg = directIDBox:CreateTexture(nil, "BACKGROUND")
        idBg:SetAllPoints()
        idBg:SetTexture(0, 0, 0, 0.5)
        local idBorder = directIDBox:CreateTexture(nil, "BORDER")
        idBorder:SetPoint("TOPLEFT", -1, 1)
        idBorder:SetPoint("BOTTOMRIGHT", 1, -1)
        idBorder:SetTexture(0.50, 0.42, 0.18, 0.6)
    end
    directIDBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    directIDBox:SetScript("OnEnterPressed", function(self)
        local id = tonumber(self:GetText())
        if id and id > 0 then
            if IsMorpherReady() then
                SendMorphCommand("HPET_MORPH:" .. id)
                UpdateSpecialSlots()
                SELECTED_CHAT_FRAME:AddMessage("|cffF5C842<Transmorpher>|r: Combat pet morphed to display ID " .. id)
            else
                SELECTED_CHAT_FRAME:AddMessage("|cffF5C842<Transmorpher>|r: |cffff0000DLL not loaded!|r")
            end
            PlaySound("gsTitleOptionOK")
        end
        self:ClearFocus()
    end)

    -- Row 2: Search bar (left) + Type filter (right), on the SAME row but separate containers
    local searchContainer = CreateFrame("Frame", nil, hpetTab)
    searchContainer:SetPoint("TOPLEFT", 6, -30)
    searchContainer:SetHeight(24)

    -- Type filter container (right side, fixed width)
    local typeContainer = CreateFrame("Frame", nil, hpetTab)
    typeContainer:SetPoint("TOPRIGHT", -6, -30)
    typeContainer:SetSize(200, 24)
    typeContainer:SetBackdrop({
        bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 12,
        insets = { left = 3, right = 3, top = 3, bottom = 3 }
    })
    typeContainer:SetBackdropColor(0.06, 0.05, 0.03, 0.95)
    typeContainer:SetBackdropBorderColor(0.60, 0.50, 0.18, 0.8)

    -- Search container fills to the left of type filter
    searchContainer:SetPoint("RIGHT", typeContainer, "LEFT", -4, 0)
    searchContainer:SetBackdrop({
        bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 12,
        insets = { left = 3, right = 3, top = 3, bottom = 3 }
    })
    searchContainer:SetBackdropColor(0.06, 0.05, 0.03, 0.95)
    searchContainer:SetBackdropBorderColor(0.60, 0.50, 0.18, 0.8)

    local hpSearchIcon = searchContainer:CreateTexture(nil, "OVERLAY")
    hpSearchIcon:SetSize(14, 14)
    hpSearchIcon:SetPoint("LEFT", 6, 0)
    hpSearchIcon:SetTexture("Interface\\Common\\UI-Searchbox-Icon")
    hpSearchIcon:SetVertexColor(0.80, 0.65, 0.22)

    local searchBox = CreateFrame("EditBox", "$parentHPetSearch", searchContainer)
    searchBox:SetPoint("LEFT", hpSearchIcon, "RIGHT", 4, 0)
    searchBox:SetPoint("RIGHT", -20, 0)
    searchBox:SetHeight(18)
    searchBox:SetAutoFocus(false)
    searchBox:SetMaxLetters(40)
    searchBox:SetFont("Fonts\\FRIZQT__.TTF", 11)
    searchBox:SetTextColor(0.95, 0.88, 0.65)
    searchBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)

    local searchHint = searchBox:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    searchHint:SetPoint("LEFT", 2, 0)
    searchHint:SetText("Search combat pets...")
    searchBox:SetScript("OnEditFocusGained", function() searchHint:Hide() end)
    searchBox:SetScript("OnEditFocusLost", function(self)
        if self:GetText() == "" then searchHint:Show() end
    end)

    local hpSearchClear = CreateFrame("Button", nil, searchContainer)
    hpSearchClear:SetSize(14, 14)
    hpSearchClear:SetPoint("RIGHT", -4, 0)
    hpSearchClear:SetNormalTexture("Interface\\FriendsFrame\\ClearBroadcastIcon")
    hpSearchClear:SetAlpha(0.5)
    hpSearchClear:Hide()
    hpSearchClear:SetScript("OnEnter", function(self) self:SetAlpha(1) end)
    hpSearchClear:SetScript("OnLeave", function(self) self:SetAlpha(0.5) end)
    hpSearchClear:SetScript("OnClick", function()
        searchBox:SetText("")
        searchBox:ClearFocus()
        searchHint:Show()
        hpSearchClear:Hide()
    end)

    -- ========== TYPE FILTER (inside typeContainer) ==========
    local familyLabel = typeContainer:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    familyLabel:SetPoint("LEFT", 6, 0)
    familyLabel:SetText("|cffC8AA6EType:|r")

    local allFamilies = {}
    local familySet = {}
    if ns.combatPetsDB then
        for _, entry in ipairs(ns.combatPetsDB) do
            if not familySet[entry[2]] then
                familySet[entry[2]] = true
                table.insert(allFamilies, entry[2])
            end
        end
        table.sort(allFamilies)
    end
    table.insert(allFamilies, 1, "All Types")

    local familyIdx = 1
    local familyBtn = CreateGoldenButton("$parentHPetFamilyBtn", typeContainer)
    familyBtn:SetSize(130, 18)
    familyBtn:SetPoint("LEFT", familyLabel, "RIGHT", 4, 0)
    familyBtn:SetText("|cffffd700All Types|r")

    -- Result count label (between search and list)
    local countLabel = hpetTab:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    countLabel:SetPoint("TOPRIGHT", -12, -56)
    countLabel:SetText("")

    -- ========== LIST AREA ==========
    local listBg = CreateFrame("Frame", "$parentHPetListBg", hpetTab)
    listBg:SetPoint("TOPLEFT", 6, -58)
    listBg:SetPoint("BOTTOMRIGHT", -6, 38)
    listBg:SetBackdrop({
        bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 12,
        insets = { left = 2, right = 2, top = 2, bottom = 2 }
    })
    listBg:SetBackdropColor(0.04, 0.03, 0.03, 0.9)
    listBg:SetBackdropBorderColor(0.80, 0.65, 0.22, 0.85)

    local listScroll = CreateFrame("ScrollFrame", "$parentHPetListScroll", listBg, "UIPanelScrollFrameTemplate")
    listScroll:SetPoint("TOPLEFT", 4, -4)
    listScroll:SetPoint("BOTTOMRIGHT", -22, 4)

    local listContent = CreateFrame("Frame", "$parentHPetListContent", listScroll)
    listContent:SetSize(listScroll:GetWidth(), 1)
    listScroll:SetScrollChild(listContent)

    -- ========== BOTTOM BUTTONS ==========
    local bottomBar = CreateFrame("Frame", nil, hpetTab)
    bottomBar:SetPoint("BOTTOMLEFT", 6, 2)
    bottomBar:SetPoint("BOTTOMRIGHT", -6, 2)
    bottomBar:SetHeight(34)
    bottomBar:SetBackdrop({
        bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 12,
        insets = { left = 3, right = 3, top = 3, bottom = 3 }
    })
    bottomBar:SetBackdropColor(0.08, 0.06, 0.03, 0.9)
    bottomBar:SetBackdropBorderColor(0.60, 0.50, 0.18, 0.7)

    local btnApplyHPet = CreateGoldenButton("$parentBtnApplyHPet", bottomBar)
    btnApplyHPet:SetSize(130, 24)
    btnApplyHPet:SetPoint("LEFT", 6, 0)
    btnApplyHPet:SetText("|cffF5C842Apply Morph|r")
    btnApplyHPet:Disable()

    local btnResetHPet = CreateGoldenButton("$parentBtnResetHPet", bottomBar)
    btnResetHPet:SetSize(100, 24)
    btnResetHPet:SetPoint("LEFT", btnApplyHPet, "RIGHT", 4, 0)
    btnResetHPet:SetText("|cffF5C842Reset|r")

    -- Separator line between reset and size
    local bottomSep = bottomBar:CreateTexture(nil, "ARTWORK")
    bottomSep:SetSize(1, 18)
    bottomSep:SetPoint("LEFT", btnResetHPet, "RIGHT", 8, 0)
    bottomSep:SetTexture(0.50, 0.42, 0.18, 0.5)

    -- Pet size controls
    local petSizeLabel = bottomBar:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    petSizeLabel:SetPoint("LEFT", bottomSep, "RIGHT", 8, 0)
    petSizeLabel:SetText("|cffC8AA6EScale:|r")

    local petSizeBox = CreateFrame("EditBox", "$parentHPetSizeInput", bottomBar)
    petSizeBox:SetSize(36, 16)
    petSizeBox:SetPoint("LEFT", petSizeLabel, "RIGHT", 4, 0)
    petSizeBox:SetAutoFocus(false)
    petSizeBox:SetMaxLetters(4)
    petSizeBox:SetText("1.0")
    petSizeBox:SetFont("Fonts\\FRIZQT__.TTF", 10)
    petSizeBox:SetTextColor(0.95, 0.88, 0.65)
    do
        local szBg = petSizeBox:CreateTexture(nil, "BACKGROUND")
        szBg:SetAllPoints()
        szBg:SetTexture(0, 0, 0, 0.5)
        local szBorder = petSizeBox:CreateTexture(nil, "BORDER")
        szBorder:SetPoint("TOPLEFT", -1, 1)
        szBorder:SetPoint("BOTTOMRIGHT", 1, -1)
        szBorder:SetTexture(0.50, 0.42, 0.18, 0.6)
    end
    petSizeBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)

    local btnPetSize = CreateGoldenButton("$parentBtnHPetSize", bottomBar)
    btnPetSize:SetSize(60, 22)
    btnPetSize:SetPoint("LEFT", petSizeBox, "RIGHT", 4, 0)
    btnPetSize:SetText("|cffF5C842Resize|r")
    btnPetSize:SetScript("OnClick", function()
        local scale = tonumber(petSizeBox:GetText())
        if scale and scale >= 0.1 and scale <= 10.0 and IsMorpherReady() then
            SendMorphCommand("HPET_SCALE:" .. scale)
            -- Force refresh by resetting and reapplying the morph
            if TransmorpherCharacterState and TransmorpherCharacterState.HunterPetDisplay and TransmorpherCharacterState.HunterPetDisplay > 0 then
                local displayID = TransmorpherCharacterState.HunterPetDisplay
                SendMorphCommand("HPET_RESET")
                -- Use OnUpdate timer as alternative (compatible with older WoW versions)
                local timerFrame = CreateFrame("Frame")
                timerFrame.elapsed = 0
                timerFrame:SetScript("OnUpdate", function(self, elapsed)
                    self.elapsed = self.elapsed + elapsed
                    if self.elapsed >= 0.1 then
                        SendMorphCommand("HPET_MORPH:" .. displayID)
                        SendMorphCommand("HPET_SCALE:" .. scale)
                        self:SetScript("OnUpdate", nil)
                    end
                end)
            end
            SELECTED_CHAT_FRAME:AddMessage("|cffF5C842<Transmorpher>|r: Combat pet scaled to " .. scale)
            PlaySound("gsTitleOptionOK")
        else
            SELECTED_CHAT_FRAME:AddMessage("|cffF5C842<Transmorpher>|r: Enter a valid size (0.1 - 10.0)")
        end
    end)
    petSizeBox:SetScript("OnEnterPressed", function(self)
        btnPetSize:GetScript("OnClick")()
        self:ClearFocus()
    end)

    -- ========== STATE ==========
    local hpetButtons = {}
    local hpetSelectedIdx = nil
    local hpetFilteredList = {}
    local MAX_RESULTS = 200 -- cap for All Creatures to avoid lag

    -- ========== FILTER: CURATED MODE ==========
    local function FilterCurated(query)
        hpetFilteredList = {}
        local db = ns.combatPetsDB or {}
        local selFamily = allFamilies[familyIdx]
        local filterFamily = (selFamily ~= "All Types")
        if not query or query == "" then
            for i, entry in ipairs(db) do
                if not filterFamily or entry[2] == selFamily then
                    table.insert(hpetFilteredList, { idx = i, name = entry[1], family = entry[2], displayID = entry[3], modelPath = entry[4], npcID = entry[5] })
                end
            end
        else
            local q = query:lower()
            for i, entry in ipairs(db) do
                if (not filterFamily or entry[2] == selFamily) and (entry[1]:lower():find(q, 1, true) or entry[2]:lower():find(q, 1, true) or tostring(entry[3]):find(q, 1, true)) then
                    table.insert(hpetFilteredList, { idx = i, name = entry[1], family = entry[2], displayID = entry[3], modelPath = entry[4], npcID = entry[5] })
                end
            end
        end
    end

    -- ========== FILTER: ALL CREATURES MODE ==========
    -- Pre-build sorted creature list once for performance
    local creatureSortedList = nil
    local function GetCreatureSortedList()
        if creatureSortedList then return creatureSortedList end
        creatureSortedList = {}
        local db = ns.creatureDisplayDB
        if not db then return creatureSortedList end
        for did, name in pairs(db) do
            table.insert(creatureSortedList, { did = did, name = name, nameLower = name:lower() })
        end
        table.sort(creatureSortedList, function(a, b) return a.name < b.name end)
        return creatureSortedList
    end

    local function FilterAllCreatures(query)
        hpetFilteredList = {}
        local sorted = GetCreatureSortedList()
        if not query or query == "" or #query < 2 then
            -- No search query: show first MAX_RESULTS creatures alphabetically
            local count = 0
            for _, entry in ipairs(sorted) do
                table.insert(hpetFilteredList, { idx = entry.did, name = entry.name, family = "Creature", displayID = entry.did })
                count = count + 1
                if count >= MAX_RESULTS then break end
            end
            return
        end
        local q = query:lower()
        local count = 0
        for _, entry in ipairs(sorted) do
            if entry.nameLower:find(q, 1, true) or tostring(entry.did):find(q, 1, true) then
                table.insert(hpetFilteredList, { idx = entry.did, name = entry.name, family = "Creature", displayID = entry.did })
                count = count + 1
                if count >= MAX_RESULTS then break end
            end
        end
    end

    -- ========== BUILD LIST UI ==========
    local function BuildHPetList()
        for _, b in ipairs(hpetButtons) do b:Hide() end
        hpetButtons = {}
        hpetSelectedIdx = nil
        btnApplyHPet:Disable()

        countLabel:SetText("")

        local bY = 0
        for idx, entry in ipairs(hpetFilteredList) do
            local row = CreateFrame("Button", nil, listContent)
            row:SetSize(listContent:GetWidth() - 4, ROW_HEIGHT)
            row:SetPoint("TOPLEFT", 2, -bY)

            local rowBg = row:CreateTexture(nil, "BACKGROUND")
            rowBg:SetAllPoints()
            rowBg:SetTexture(0, 0, 0, 0)

            -- Icon
            local icon = row:CreateTexture(nil, "ARTWORK")
            icon:SetSize(ROW_HEIGHT - 4, ROW_HEIGHT - 4)
            icon:SetPoint("LEFT", 4, 0)
            -- Different icons per type
            local iconTex = "Interface\\Icons\\Ability_Hunter_BeastCall"
            if entry.family == "Warlock" then
                iconTex = "Interface\\Icons\\Spell_Shadow_SummonImp"
            elseif entry.family == "Mage" then
                iconTex = "Interface\\Icons\\Spell_Frost_SummonWaterElemental_2"
            elseif entry.family == "Creature" then
                iconTex = "Interface\\Icons\\INV_Misc_Head_Dragon_01"
            end
            icon:SetTexture(iconTex)
            icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

            local iconBorder = row:CreateTexture(nil, "OVERLAY")
            iconBorder:SetSize(ROW_HEIGHT - 2, ROW_HEIGHT - 2)
            iconBorder:SetPoint("CENTER", icon, "CENTER", 0, 0)
            iconBorder:SetTexture("Interface\\Buttons\\UI-Quickslot2")
            iconBorder:SetTexCoord(0.2, 0.8, 0.2, 0.8)

            -- Name
            local nameStr = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
            nameStr:SetPoint("LEFT", icon, "RIGHT", 8, 0)
            nameStr:SetText("|cffffd700" .. entry.name .. "|r")
            nameStr:SetWidth(250)
            nameStr:SetJustifyH("LEFT")

            -- Type/Family
            local famStr = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            famStr:SetPoint("LEFT", nameStr, "RIGHT", 4, 0)
            famStr:SetText("|cff8a7d6a" .. entry.family .. "|r")
            famStr:SetWidth(100)
            famStr:SetJustifyH("LEFT")

            -- Display ID
            local idStr = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            idStr:SetPoint("RIGHT", -8, 0)
            idStr:SetText("|cff6a6050" .. entry.displayID .. "|r")

            row:SetScript("OnClick", function()
                if hpetSelectedIdx and hpetButtons[hpetSelectedIdx] then
                    hpetButtons[hpetSelectedIdx].bg:SetTexture(0, 0, 0, 0)
                end
                hpetSelectedIdx = idx
                rowBg:SetTexture(0.6, 0.48, 0.15, 0.3)
                btnApplyHPet:Enable()
            end)

            row:SetScript("OnEnter", function()
                if hpetSelectedIdx ~= idx then rowBg:SetTexture(1, 1, 1, 0.05) end
                GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
                GameTooltip:AddLine(entry.name)
                GameTooltip:AddLine("Type: " .. entry.family, 1, 0.82, 0.1)
                GameTooltip:AddLine("Display ID: " .. entry.displayID, 1, 1, 1)
                GameTooltip:AddLine("Click to select, then Apply", 0.5, 0.5, 0.5)
                GameTooltip:Show()
            end)

            row:SetScript("OnLeave", function()
                if hpetSelectedIdx ~= idx then rowBg:SetTexture(0, 0, 0, 0) end
                GameTooltip:Hide()
            end)

            row.bg = rowBg
            table.insert(hpetButtons, row)
            bY = bY + ROW_HEIGHT + 1
        end

        listContent:SetHeight(math.max(1, bY))
    end

    -- ========== REFRESH ==========
    local function RefreshList()
        local query = searchBox:GetText()
        if currentMode == MODE_CURATED then
            FilterCurated(query)
        else
            FilterAllCreatures(query)
        end
        BuildHPetList()
    end

    -- ========== MODE BUTTON VISUALS ==========
    local function UpdateModeButtons()
        if currentMode == MODE_CURATED then
            btnModeCurated:SetText("|cffffd700> Curated Pets|r")
            btnModeAll:SetText("|cff888888All Creatures|r")
            typeContainer:Show()
            -- Shrink search to make room for type filter
            searchContainer:SetPoint("RIGHT", typeContainer, "LEFT", -4, 0)
            searchHint:SetText("Search combat pets...")
        else
            btnModeCurated:SetText("|cff888888Curated Pets|r")
            btnModeAll:SetText("|cffffd700> All Creatures|r")
            typeContainer:Hide()
            -- Expand search to full width
            searchContainer:SetPoint("RIGHT", hpetTab, "RIGHT", -6, 0)
            searchHint:SetText("Search all creatures...")
        end
        if searchBox:GetText() == "" then
            searchHint:Show()
        end
    end

    btnModeCurated:SetScript("OnClick", function()
        currentMode = MODE_CURATED
        UpdateModeButtons()
        RefreshList()
    end)
    btnModeAll:SetScript("OnClick", function()
        currentMode = MODE_ALL
        UpdateModeButtons()
        RefreshList()
    end)

    -- ========== FAMILY FILTER CYCLING ==========
    familyBtn:SetScript("OnClick", function()
        familyIdx = familyIdx + 1
        if familyIdx > #allFamilies then familyIdx = 1 end
        familyBtn:SetText("|cffffd700" .. allFamilies[familyIdx] .. "|r")
        RefreshList()
    end)
    familyBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine("Click to cycle types")
        GameTooltip:AddLine("Right-click to reset to All", 0.7, 0.7, 0.7)
        GameTooltip:Show()
    end)
    familyBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
    familyBtn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    familyBtn:HookScript("OnClick", function(self, button)
        if button == "RightButton" then
            familyIdx = 1
            familyBtn:SetText("|cffffd700All Types|r")
            RefreshList()
        end
    end)

    -- ========== SEARCH DEBOUNCE ==========
    local hpetSearchTimer = CreateFrame("Frame")
    hpetSearchTimer:Hide()
    hpetSearchTimer.elapsed = 0
    hpetSearchTimer:SetScript("OnUpdate", function(self, dt)
        self.elapsed = self.elapsed + dt
        if self.elapsed >= 0.3 then
            self:Hide()
            RefreshList()
        end
    end)
    searchBox:SetScript("OnTextChanged", function(self)
        hpetSearchTimer.elapsed = 0
        hpetSearchTimer:Show()
        if self:GetText() ~= "" then hpSearchClear:Show() else hpSearchClear:Hide() end
    end)

    -- ========== APPLY BUTTON ==========
    btnApplyHPet:SetScript("OnClick", function()
        if hpetSelectedIdx and hpetFilteredList[hpetSelectedIdx] then
            local entry = hpetFilteredList[hpetSelectedIdx]
            if IsMorpherReady() then
                SendMorphCommand("HPET_MORPH:" .. entry.displayID)
                UpdateSpecialSlots()
                SELECTED_CHAT_FRAME:AddMessage("|cffF5C842<Transmorpher>|r: Combat pet morphed to " .. entry.name .. " (" .. entry.displayID .. ")")
            else
                SELECTED_CHAT_FRAME:AddMessage("|cffF5C842<Transmorpher>|r: |cffff0000DLL not loaded!|r")
            end
            PlaySound("gsTitleOptionOK")
        end
    end)

    -- ========== RESET BUTTON ==========
    btnResetHPet:SetScript("OnClick", function()
        if IsMorpherReady() then
            SendMorphCommand("HPET_RESET")
            UpdateSpecialSlots()
            SELECTED_CHAT_FRAME:AddMessage("|cffF5C842<Transmorpher>|r: Combat pet appearance reset!")
        end
        PlaySound("gsTitleOptionOK")
    end)

    -- ========== INIT ON SHOW ==========
    hpetTab:SetScript("OnShow", function()
        UpdateModeButtons()
        if #hpetFilteredList == 0 and currentMode == MODE_CURATED then
            RefreshList()
        end
    end)
end

---------------- SETTINGS TAB ----------------

do
    local settingsTab = mainFrame.tabs.settings
    
    -- Create a scrollable content area
    local scrollFrame = CreateFrame("ScrollFrame", "$parentSettingsScroll", settingsTab, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", 8, -8)
    scrollFrame:SetPoint("BOTTOMRIGHT", -28, 8)
    
    local scrollChild = CreateFrame("Frame", nil, scrollFrame)
    scrollChild:SetSize(scrollFrame:GetWidth(), 1)
    scrollFrame:SetScrollChild(scrollChild)
    
    local yOffset = -16
    
    -- Modern checkbox creation with golden theme
    local function createCheckbox(parent, label, settingKey, y, tooltip)
        local container = CreateFrame("Frame", nil, parent)
        container:SetPoint("TOPLEFT", 10, y)
        container:SetSize(parent:GetWidth() - 20, 32)
        
        -- Background on hover
        local bg = container:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints()
        bg:SetTexture("Interface\\ChatFrame\\ChatFrameBackground")
        bg:SetVertexColor(0.15, 0.12, 0.06, 0)
        
        local cb = CreateFrame("CheckButton", "$parentCB_"..settingKey, container)
        cb:SetPoint("LEFT", 8, 0)
        cb:SetSize(24, 24)
        cb:SetNormalTexture("Interface\\Buttons\\UI-CheckBox-Up")
        cb:SetPushedTexture("Interface\\Buttons\\UI-CheckBox-Down")
        cb:SetHighlightTexture("Interface\\Buttons\\UI-CheckBox-Highlight", "ADD")
        cb:SetCheckedTexture("Interface\\Buttons\\UI-CheckBox-Check")
        cb:SetDisabledCheckedTexture("Interface\\Buttons\\UI-CheckBox-Check-Disabled")
        
        -- Golden tint for checkbox
        cb:GetNormalTexture():SetVertexColor(0.80, 0.65, 0.22)
        cb:GetCheckedTexture():SetVertexColor(1.0, 0.82, 0.20)
        
        local labelText = container:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        labelText:SetPoint("LEFT", cb, "RIGHT", 8, 0)
        labelText:SetText(label)
        labelText:SetTextColor(0.95, 0.88, 0.65)
        
        cb:SetScript("OnClick", function(self)
            GetSettings()[settingKey] = self:GetChecked() == 1
            PlaySound("gsTitleOptionOK")
        end)
        
        cb:SetScript("OnShow", function(self)
            self:SetChecked(GetSettings()[settingKey])
        end)
        
        -- Hover effect
        container:SetScript("OnEnter", function(self)
            bg:SetVertexColor(0.15, 0.12, 0.06, 0.3)
            if tooltip then
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                GameTooltip:SetText(label, 1, 0.82, 0.20)
                GameTooltip:AddLine(tooltip, 1, 1, 1, true)
                GameTooltip:Show()
            end
        end)
        
        container:SetScript("OnLeave", function(self)
            bg:SetVertexColor(0.15, 0.12, 0.06, 0)
            GameTooltip:Hide()
        end)
        
        -- Make container clickable
        container:EnableMouse(true)
        container:SetScript("OnMouseDown", function(self)
            cb:Click()
        end)
        
        return cb, container
    end
    
    -- Section header function
    local function createSectionHeader(parent, title, y)
        local header = CreateFrame("Frame", nil, parent)
        header:SetPoint("TOPLEFT", 6, y)
        header:SetSize(parent:GetWidth() - 12, 28)
        
        -- Background
        header:SetBackdrop({
            bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            tile = true, tileSize = 16, edgeSize = 12,
            insets = { left = 3, right = 3, top = 3, bottom = 3 }
        })
        header:SetBackdropColor(0.12, 0.10, 0.06, 0.8)
        header:SetBackdropBorderColor(0.80, 0.65, 0.22, 0.6)
        
        local text = header:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        text:SetPoint("LEFT", 10, 0)
        text:SetText(title)
        text:SetTextColor(1.0, 0.82, 0.20)
        
        -- Decorative line
        local line = header:CreateTexture(nil, "ARTWORK")
        line:SetHeight(1)
        line:SetPoint("LEFT", text, "RIGHT", 8, 0)
        line:SetPoint("RIGHT", -8, 0)
        line:SetTexture("Interface\\ChatFrame\\ChatFrameBackground")
        line:SetGradientAlpha("HORIZONTAL", 0.80, 0.65, 0.22, 0.5, 0.80, 0.65, 0.22, 0)
        
        return header
    end
    
    -- ========== PERSISTENCE SECTION ==========
    createSectionHeader(scrollChild, "Persistence Settings", yOffset)
    yOffset = yOffset - 36
    
    createCheckbox(scrollChild, "Persist morph across sessions", "saveMorphState", yOffset, 
        "Automatically restore your character morph when you log in")
    yOffset = yOffset - 36
    
    createCheckbox(scrollChild, "Save mount morph per character", "saveMountMorph", yOffset,
        "Remember your mount morph for this character")
    yOffset = yOffset - 36
    
    createCheckbox(scrollChild, "Save pet morph per character", "savePetMorph", yOffset,
        "Remember your companion pet morph for this character")
    yOffset = yOffset - 36
    
    createCheckbox(scrollChild, "Save combat pet morph per character", "saveCombatPetMorph", yOffset,
        "Remember your hunter pet morph for this character")
    yOffset = yOffset - 48
    
    -- ========== BEHAVIOR SECTION ==========
    createSectionHeader(scrollChild, "Behavior Settings", yOffset)
    yOffset = yOffset - 36
    
    local dbwCheckbox = createCheckbox(scrollChild, "Show Deathbringer's Will proc form", "showDBWProc", yOffset,
        "Temporarily show the DBW proc transformation (suspend morph during proc)")
    -- When toggling the DBW setting, immediately update the suspend state
    dbwCheckbox:HookScript("OnClick", function(self)
        local enabled = self:GetChecked() == 1
        if not enabled and dbwSuspended then
            -- User turned it off while DBW was suspending: resume immediately
            dbwSuspended = false
            if not morphSuspended and not vehicleSuspended then
                SendRawMorphCommand("RESUME")
            end
        elseif enabled and not dbwSuspended and HasDBWProc() then
            -- User turned it on while a DBW proc is active: suspend immediately
            dbwSuspended = true
            if not morphSuspended and not vehicleSuspended then
                SendRawMorphCommand("SUSPEND")
            end
        end
    end)
    yOffset = yOffset - 36
    
    local shapeshiftCheckbox = createCheckbox(scrollChild, "Keep morph in shapeshift forms", "morphInShapeshift", yOffset,
        "Maintain your morph when shapeshifting (Druid forms, etc.)")
    -- When toggling shapeshift morph setting, immediately update suspend state
    shapeshiftCheckbox:HookScript("OnClick", function(self)
        local enabled = self:GetChecked() == 1
        if enabled and morphSuspended then
            -- User wants morph in shapeshift: resume immediately
            morphSuspended = false
            if not dbwSuspended and not vehicleSuspended then
                SendRawMorphCommand("RESUME")
            end
        elseif not enabled and IsModelChangingForm() and not morphSuspended then
            -- User turned it off while in a form: suspend immediately
            morphSuspended = true
            if not dbwSuspended and not vehicleSuspended then
                SendRawMorphCommand("SUSPEND")
            end
        end
    end)
    yOffset = yOffset - 48
    
    -- ========== STATUS SECTION ==========
    createSectionHeader(scrollChild, "System Status", yOffset)
    yOffset = yOffset - 36
    
    -- DLL Status Card
    local statusCard = CreateFrame("Frame", nil, scrollChild)
    statusCard:SetPoint("TOPLEFT", 10, yOffset)
    statusCard:SetSize(scrollChild:GetWidth() - 20, 80)
    statusCard:SetBackdrop({
        bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 12,
        insets = { left = 3, right = 3, top = 3, bottom = 3 }
    })
    statusCard:SetBackdropColor(0.04, 0.03, 0.03, 0.95)
    statusCard:SetBackdropBorderColor(0.60, 0.50, 0.18, 0.8)
    
    local statusIcon = statusCard:CreateTexture(nil, "ARTWORK")
    statusIcon:SetSize(32, 32)
    statusIcon:SetPoint("LEFT", 12, 0)
    
    local statusTitle = statusCard:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    statusTitle:SetPoint("TOPLEFT", statusIcon, "TOPRIGHT", 12, -2)
    
    local statusDesc = statusCard:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    statusDesc:SetPoint("TOPLEFT", statusTitle, "BOTTOMLEFT", 0, -4)
    statusDesc:SetPoint("RIGHT", -12, 0)
    statusDesc:SetJustifyH("LEFT")
    statusDesc:SetTextColor(0.8, 0.8, 0.8)
    
    -- Function to update DLL status display
    local function UpdateDLLStatus()
        if IsMorpherReady() then
            statusIcon:SetTexture("Interface\\RAIDFRAME\\ReadyCheck-Ready")
            statusTitle:SetText("|cff4ACC4AMorpher DLL: LOADED|r")
            statusDesc:SetText("The morpher is active and ready to transform your character.")
            statusCard:SetBackdropBorderColor(0.29, 0.80, 0.29, 0.8)
        else
            statusIcon:SetTexture("Interface\\RAIDFRAME\\ReadyCheck-NotReady")
            statusTitle:SetText("|cffff0000Morpher DLL: NOT LOADED|r")
            statusDesc:SetText("Place dinput8.dll in your WoW folder to enable morphing features.")
            statusCard:SetBackdropBorderColor(0.80, 0.29, 0.29, 0.8)
        end
    end
    
    -- Update status when tab is shown
    settingsTab:SetScript("OnShow", function()
        UpdateDLLStatus()
        -- Create periodic update timer (check every 2 seconds while tab is visible)
        if not settingsTab.statusUpdateTimer then
            settingsTab.statusUpdateTimer = 0
        end
    end)
    
    -- Periodic update while Settings tab is visible
    settingsTab:SetScript("OnUpdate", function(self, elapsed)
        if not self.statusUpdateTimer then return end
        self.statusUpdateTimer = self.statusUpdateTimer + elapsed
        if self.statusUpdateTimer >= 2 then
            UpdateDLLStatus()
            self.statusUpdateTimer = 0
        end
    end)
    
    -- Stop timer when tab is hidden
    settingsTab:SetScript("OnHide", function(self)
        self.statusUpdateTimer = nil
    end)
    
    yOffset = yOffset - 90
    
    -- ========== INFO SECTION ==========
    createSectionHeader(scrollChild, "About", yOffset)
    yOffset = yOffset - 36
    
    local infoCard = CreateFrame("Frame", nil, scrollChild)
    infoCard:SetPoint("TOPLEFT", 10, yOffset)
    infoCard:SetSize(scrollChild:GetWidth() - 20, 60)
    infoCard:SetBackdrop({
        bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 12,
        insets = { left = 3, right = 3, top = 3, bottom = 3 }
    })
    infoCard:SetBackdropColor(0.04, 0.03, 0.03, 0.95)
    infoCard:SetBackdropBorderColor(0.60, 0.50, 0.18, 0.8)
    
    local infoText = infoCard:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    infoText:SetPoint("TOPLEFT", 12, -12)
    infoText:SetPoint("BOTTOMRIGHT", -12, 12)
    infoText:SetJustifyH("LEFT")
    infoText:SetJustifyV("TOP")
    infoText:SetTextColor(0.95, 0.88, 0.65)
    infoText:SetText("Transmorpher v1.0.9\n\nA client-side transmog system for WotLK 3.3.5a.\nTransform your character appearance, equipment, mounts, and pets.\nRequires dinput8.dll to function.")
    
    yOffset = yOffset - 70
    
    -- Set scroll child height
    scrollChild:SetHeight(math.abs(yOffset) + 20)
end

---------------- EVENT LOOP & PERSISTENCE ----------------
-- Clean event-based system. The DLL's MorphGuard handles automatic
-- restoration of descriptors every 20ms. The addon only needs to:
--   1. Send morph state on login/zone change (once)
--   2. Signal SUSPEND when entering a model-changing form
--   3. Signal RESUME when leaving a model-changing form
-- No burst loops, no repeated CreateFrame, no flickering.

do
    mainFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
    mainFrame:RegisterEvent("ZONE_CHANGED_NEW_AREA")
    mainFrame:RegisterEvent("UNIT_MODEL_CHANGED")
    mainFrame:RegisterEvent("UPDATE_SHAPESHIFT_FORM")
    -- Smart Interaction Intervention: Kill morpher BEFORE interaction happens
    local function HandleSmartIntervention(unit)
        if unit and UnitExists(unit) then
            local name = UnitName(unit) or ""
            local isVehicle = false
            
            -- Automated Seat Detection (Covers Mammoths, Choppers, Raid Vehicles)
            local seatCount = UnitVehicleSeatCount(unit)
            if seatCount and seatCount > 0 then
                isVehicle = true
            end
            
            -- Keyword Detection (Covers Objects, Quest Vehicles, and non-seat interactions)
            if not isVehicle then
                local patterns = {
                    "Chopper", "Salvaged", "Demolisher", "Siege", "Engine", "Cannon", "Canon", "Harpoon",
                    "Turret", "Teleporter", "Drake", "Dragon", "Tank", "Golem", "Robot", "Machine", 
                    "Plane", "Ship", "Boat", "Zeppelin", "Bomber", "Steam", "Flame", 
                    "Leviathan", "Mimiron", "Gryphon", "Wyvern", "Bat", "Hawkstrider", "Catapult", 
                    "Car", "Shuttle", "Submarine", "Valkyrie", "Mammoth", "Motor", "Bike", "Cycle", 
                    "Rider", "Pilot", "Gunner", "Azure", "Amber", "Emerald", "Scion", "Proto-Drake", 
                    "Aerial", "Command", "Platform", "Guardian", "Sentinel", "Constructor", 
                    "Mechano", "Turbo", "Automatic", "Flying", "Hover", "Glider", "Sled", "Rocket", 
                    "Blimp", "Balloon", "Gnome", "Goblin", "Experimental", "Constructor", "Security", 
                    "Defense", "Assault", "War", "Combat", "Battle", "Transport", "Portal", 
                    "Focus", "Nexus", "Pulse", "Energy", "Beam", "Static", "Launcher", "Ram"
                }
                for _, p in ipairs(patterns) do
                    if name:find(p) then
                        isVehicle = true
                        break
                    end
                end
            end

            if isVehicle then
                if not vehicleSuspended then
                    vehicleSuspended = true
                    if TransmorpherCharacterState and TransmorpherCharacterState.MountDisplay then
                        savedMountDisplayForVehicle = TransmorpherCharacterState.MountDisplay
                        TRANSMORPHER_CMD = "MOUNT_RESET|SUSPEND"
                        TransmorpherCharacterState.MountDisplay = nil
                    else
                        SendRawMorphCommand("SUSPEND")
                    end
                end
            end
        end
    end

    WorldFrame:HookScript("OnMouseDown", function(_, button)
        if button == "RightButton" then
            HandleSmartIntervention("mouseover")
        end
    end)

    local origInteractUnit = InteractUnit
    InteractUnit = function(unit)
        HandleSmartIntervention(unit)
        return origInteractUnit(unit)
    end
    mainFrame:RegisterEvent("UNIT_AURA")
    mainFrame:RegisterEvent("CHAT_MSG_ADDON")
    mainFrame:RegisterEvent("PLAYER_LOGIN")
    mainFrame:RegisterEvent("UNIT_INVENTORY_CHANGED")
    mainFrame:RegisterEvent("UNIT_ENTERED_VEHICLE")
    mainFrame:RegisterEvent("UNIT_EXITED_VEHICLE")
    
    -- Track form state for edge detection (only act on transitions)
    local lastKnownForm = -1
    local lastKnownMounted = false
    
    -- Track weapon state for enchant persistence
    local lastMainHand = nil
    local lastOffHand = nil

    -- One-shot delayed send (reusable timer, no CreateFrame spam)
    local delayedSendTimer = CreateFrame("Frame")
    delayedSendTimer:Hide()
    delayedSendTimer:SetScript("OnUpdate", function(self, elapsed)
        self.remaining = self.remaining - elapsed
        if self.remaining <= 0 then
            self:Hide()
            SendFullMorphState()
        end
    end)

    local function ScheduleMorphSend(delay)
        delayedSendTimer.remaining = delay or 0.05
        delayedSendTimer:Show()
    end

    mainFrame:SetScript("OnEvent", function(self, event, ...)
        if event == "PLAYER_LOGIN" then
            -- Initialize per-character SavedVariables
            if not TransmorpherCharacterState then
                TransmorpherCharacterState = {Items={}, Morph=nil, Scale=nil, MountDisplay=nil, PetDisplay=nil, HunterPetDisplay=nil, HunterPetScale=nil, EnchantMH=nil, EnchantOH=nil}
            end
            if not TransmorpherCharacterState.Items then
                TransmorpherCharacterState.Items = {}
            end
            
            -- Initialize weapon tracking (assign to module-level variables)
            lastMainHand = GetInventoryItemLink("player", 16)
            lastOffHand = GetInventoryItemLink("player", 17)

            -- Flag: the next SendFullMorphState will prepend RESET:ALL so
            -- the DLL wipe + character-restore is one atomic batch.
            needsCharacterReset = true

            -- Immediately send RESET:ALL to the DLL so stale state from a
            -- previous character is cleared within the next 20ms tick.
            -- The full morph state will be sent after the delayed schedule.
            SendRawMorphCommand("RESET:ALL")

            -- Evaluate current form/proc state
            lastKnownForm = GetShapeshiftForm()
            lastKnownMounted = IsMounted() or false
            morphSuspended = IsModelChangingForm()
            dbwSuspended = GetSettings().showDBWProc and HasDBWProc() or false
            vehicleSuspended = IsInVehicle()
            
            -- If already in vehicle on login, clear mount morph immediately
            if vehicleSuspended and TransmorpherCharacterState and TransmorpherCharacterState.MountDisplay then
                savedMountDisplayForVehicle = TransmorpherCharacterState.MountDisplay
                SendMorphCommand("MOUNT_RESET")
            end
            
            if morphSuspended or dbwSuspended or vehicleSuspended then
                SendRawMorphCommand("SUSPEND")
            else
                -- PLAYER_ENTERING_WORLD will fire shortly and override this
                -- with a 0.05 s timer, but schedule a 0.4 s fallback just in case.
                ScheduleMorphSend(0.4)
            end

            -- Restore the UI (slots, glows, dressing room) from saved state
            RestoreMorphedUI()

        elseif event == "PLAYER_ENTERING_WORLD" or event == "ZONE_CHANGED_NEW_AREA" then
            -- Zone transition: re-evaluate all suspend reasons from scratch
            lastKnownForm = GetShapeshiftForm()
            lastKnownMounted = IsMounted() or false
            morphSuspended = IsModelChangingForm()
            dbwSuspended = GetSettings().showDBWProc and HasDBWProc() or false
            vehicleSuspended = IsInVehicle()
            
            -- If in vehicle after zone change, clear mount morph immediately
            if vehicleSuspended and TransmorpherCharacterState and TransmorpherCharacterState.MountDisplay then
                savedMountDisplayForVehicle = TransmorpherCharacterState.MountDisplay
                SendMorphCommand("MOUNT_RESET")
            end
            
            if morphSuspended or dbwSuspended or vehicleSuspended then
                SendRawMorphCommand("SUSPEND")
            else
                ScheduleMorphSend(0.05)
            end

        elseif event == "UPDATE_SHAPESHIFT_FORM" then
            -- Shapeshift form changed: detect enter/leave transitions
            local currentForm = GetShapeshiftForm()
            if currentForm == lastKnownForm then return end
            lastKnownForm = currentForm

            local inModelForm = IsModelChangingForm()
            if inModelForm and not morphSuspended then
                -- ENTERING a model-changing form
                morphSuspended = true
                if not dbwSuspended and not vehicleSuspended then
                    SendRawMorphCommand("SUSPEND")
                end
            elseif not inModelForm and morphSuspended then
                -- LEAVING a model-changing form
                morphSuspended = false
                if not dbwSuspended and not vehicleSuspended then
                    SendRawMorphCommand("RESUME")
                end
            end

        elseif event == "UNIT_MODEL_CHANGED" then
            local unit = ...
            if unit ~= "player" then return end
            -- Model changed externally (Deathbringer's Will proc end, etc.)
            -- The DLL's MorphGuard detects descriptor mismatches automatically.
            -- We only need to handle mount state transitions here.
            local currentMounted = IsMounted() or false
            if currentMounted ~= lastKnownMounted then
                lastKnownMounted = currentMounted
                -- Mount/dismount doesn't need suspend/resume —
                -- MorphGuard handles descriptor restoration automatically.
            end
            -- No action needed: DLL MorphGuard restores on next tick.

        elseif event == "UNIT_AURA" then
            local unit = ...
            if unit ~= "player" then return end
            -- Deathbringer's Will proc detection: suspend morph to show proc form
            -- Only active when showDBWProc setting is enabled
            local hasDBW = GetSettings().showDBWProc and HasDBWProc() or false
            if hasDBW and not dbwSuspended then
                -- DBW proc started: suspend morph so player sees the proc form
                dbwSuspended = true
                if not morphSuspended and not vehicleSuspended then
                    SendRawMorphCommand("SUSPEND")
                end
            elseif not hasDBW and dbwSuspended then
                -- DBW proc ended: resume morph if shapeshift isn't also suspending
                dbwSuspended = false
                if not morphSuspended and not vehicleSuspended then
                    SendRawMorphCommand("RESUME")
                end
            end

        elseif event == "UNIT_INVENTORY_CHANGED" then
            local unit = ...
            if unit ~= "player" then return end
            
            -- Check weapon changes to reapply enchants
            local currentMainHand = GetInventoryItemLink("player", 16)
            local currentOffHand = GetInventoryItemLink("player", 17)
            
            -- Detect weapon slot changes (fire if EITHER weapon changed)
            if currentMainHand ~= lastMainHand or currentOffHand ~= lastOffHand then
                -- Update tracked weapons
                lastMainHand = currentMainHand
                lastOffHand = currentOffHand
                
                -- Reapply saved enchants to the slots (regardless of which weapon is equipped)
                if TransmorpherCharacterState then
                    if TransmorpherCharacterState.EnchantMH and currentMainHand then
                        SendMorphCommand("ENCHANT_MH:" .. TransmorpherCharacterState.EnchantMH)
                        if mainFrame.enchantSlots and mainFrame.enchantSlots["Enchant MH"] then
                            local eid = TransmorpherCharacterState.EnchantMH
                            local eName = tostring(eid)
                            if ns.enchantDB and ns.enchantDB[eid] then eName = ns.enchantDB[eid] end
                            mainFrame.enchantSlots["Enchant MH"]:SetEnchant(eid, eName)
                            mainFrame.enchantSlots["Enchant MH"].isMorphed = true
                            ShowMorphGlow(mainFrame.enchantSlots["Enchant MH"], "orange")
                        end
                    end
                    
                    if TransmorpherCharacterState.EnchantOH and currentOffHand then
                        SendMorphCommand("ENCHANT_OH:" .. TransmorpherCharacterState.EnchantOH)
                        if mainFrame.enchantSlots and mainFrame.enchantSlots["Enchant OH"] then
                            local eid = TransmorpherCharacterState.EnchantOH
                            local eName = tostring(eid)
                            if ns.enchantDB and ns.enchantDB[eid] then eName = ns.enchantDB[eid] end
                            mainFrame.enchantSlots["Enchant OH"]:SetEnchant(eid, eName)
                            mainFrame.enchantSlots["Enchant OH"].isMorphed = true
                            ShowMorphGlow(mainFrame.enchantSlots["Enchant OH"], "orange")
                        end
                    end
                end
                
                -- Sync UI
                SyncDressingRoom()
            end

        elseif event == "UNIT_ENTERED_VEHICLE" then
            local unit = ...
            if unit ~= "player" then return end
            -- Rapid vehicle entry detection
            if not vehicleSuspended then
                vehicleSuspended = true
                if TransmorpherCharacterState and TransmorpherCharacterState.MountDisplay then
                    savedMountDisplayForVehicle = TransmorpherCharacterState.MountDisplay
                    TRANSMORPHER_CMD = "MOUNT_RESET|SUSPEND"
                    TransmorpherCharacterState.MountDisplay = nil
                else
                    SendRawMorphCommand("SUSPEND")
                end
            end

        elseif event == "UNIT_EXITED_VEHICLE" then
            local unit = ...
            if unit ~= "player" then return end
            -- Restore state on exit
            if vehicleSuspended then
                vehicleSuspended = false
                if savedMountDisplayForVehicle then
                    TransmorpherCharacterState.MountDisplay = savedMountDisplayForVehicle
                    TRANSMORPHER_CMD = "MOUNT_MORPH:" .. savedMountDisplayForVehicle .. "|RESUME"
                    savedMountDisplayForVehicle = nil
                    UpdateSpecialSlots()
                else
                    SendRawMorphCommand("RESUME")
                end
            end

        elseif event == "CHAT_MSG_ADDON" then
            local prefix, msg, channel, sender = ...
            if (prefix == addonMessagePrefix or prefix == "DressMe") then
                -- Reserved for future appearance sharing
            end
        end
    end)
end

---------------- VEHICLE SAFETY GUARD ----------------
-- Aggressive polling to prevent vehicle crashes
-- Checks every frame if player entered a vehicle and immediately clears ALL morphs
do
    local vehicleGuardFrame = CreateFrame("Frame")
    
    vehicleGuardFrame:SetScript("OnUpdate", function(self, elapsed)
        -- Check if DLL is loaded
        if not TRANSMORPHER_DLL_LOADED then return end
        
        -- Check vehicle state
        local inVehicle = UnitInVehicle("player")
        
        -- Smart Check for passenger seat mounts/units/objects
        if not inVehicle then
            local seatCount = UnitVehicleSeatCount("target")
            if seatCount and seatCount > 0 then
                inVehicle = true 
            else
                local name = UnitName("target") or ""
                local patterns = {
                    "Chopper", "Salvaged", "Demolisher", "Siege", "Engine", "Cannon", "Canon", "Harpoon",
                    "Turret", "Teleporter", "Drake", "Dragon", "Tank", "Golem", "Robot", "Machine", 
                    "Plane", "Ship", "Boat", "Zeppelin", "Bomber", "Steam", "Flame", 
                    "Leviathan", "Mimiron", "Gryphon", "Wyvern", "Bat", "Hawkstrider", "Catapult", 
                    "Car", "Shuttle", "Submarine", "Valkyrie", "Mammoth", "Motor", "Bike", "Cycle", 
                    "Rider", "Pilot", "Gunner", "Azure", "Amber", "Emerald", "Scion", "Proto-Drake", 
                    "Aerial", "Command", "Platform", "Guardian", "Sentinel", "Constructor", 
                    "Mechano", "Turbo", "Automatic", "Flying", "Hover", "Glider", "Sled", "Rocket", 
                    "Blimp", "Balloon", "Gnome", "Goblin", "Experimental", "Constructor", "Security", 
                    "Defense", "Assault", "War", "Combat", "Battle", "Transport", "Portal", 
                    "Focus", "Nexus", "Pulse", "Energy", "Beam", "Static", "Launcher", "Ram"
                }
                for _, p in ipairs(patterns) do
                    if name:find(p) then
                        inVehicle = true
                        break
                    end
                end
            end
        end
        
        if inVehicle and not wasInVehicleLastFrame then
            -- Transition: ENTERING vehicle
            wasInVehicleLastFrame = true
            if not vehicleSuspended then
                vehicleSuspended = true
                if TransmorpherCharacterState and TransmorpherCharacterState.MountDisplay then
                    savedMountDisplayForVehicle = TransmorpherCharacterState.MountDisplay
                    TRANSMORPHER_CMD = "MOUNT_RESET|SUSPEND"
                    TransmorpherCharacterState.MountDisplay = nil
                else
                    TRANSMORPHER_CMD = "SUSPEND"
                end
            end
        elseif not inVehicle and wasInVehicleLastFrame then
            -- Transition: EXITING vehicle
            wasInVehicleLastFrame = false
            if vehicleSuspended then
                vehicleSuspended = false
                if savedMountDisplayForVehicle then
                    TransmorpherCharacterState.MountDisplay = savedMountDisplayForVehicle
                    TRANSMORPHER_CMD = "MOUNT_MORPH:" .. savedMountDisplayForVehicle .. "|RESUME"
                    savedMountDisplayForVehicle = nil
                    UpdateSpecialSlots()
                else
                    TRANSMORPHER_CMD = "RESUME"
                end
            end
        end
    end)
end

---------------- SLASH COMMANDS ----------------

SLASH_Transmorpher1 = "/morph"
SLASH_Transmorpher2 = "/vm"
SLASH_Transmorpher3 = "/Transmorpher"

SlashCmdList["Transmorpher"] = function(msg)
    msg = msg:lower():trim()
    if msg == "reset" then
        if IsMorpherReady() then
            SendMorphCommand("RESET:ALL")
            -- Clear all morphed state and restore equipped gear
            if mainFrame.slots then
                for _, slotName in pairs(slotOrder) do
                    local slot = mainFrame.slots[slotName]
                    if slot then
                        slot.isMorphed = false
                        slot.morphedItemId = nil
                        slot.isHiddenSlot = false
                        HideMorphGlow(slot)
                        -- Reset eye button
                        if slot.eyeButton then
                            slot.eyeButton.isHidden = false
                            slot.eyeButton.eyeTex:SetVertexColor(0.85, 0.75, 0.45, 0.8)
                            slot.eyeButton.hiddenTex:Hide()
                        end
                        local equippedId = GetEquippedItemForSlot(slotName)
                        if equippedId then slot:SetItem(equippedId)
                        else slot.itemId = nil; slot.textures.empty:Show(); slot.textures.item:Hide() end
                    end
                end
            end
            if mainFrame.enchantSlots then
                for _, es in pairs(mainFrame.enchantSlots) do
                    es.isMorphed = false
                    es:RemoveEnchant()
                    HideMorphGlow(es)
                end
            end
            SyncDressingRoom()
            SELECTED_CHAT_FRAME:AddMessage("|cffF5C842<Transmorpher>|r: All morphs reset!")
        else
            SELECTED_CHAT_FRAME:AddMessage("|cffF5C842<Transmorpher>|r: |cffff0000DLL not loaded!|r")
        end
    elseif msg == "status" then
            SELECTED_CHAT_FRAME:AddMessage("|cffF5C842<Transmorpher>|r: |cff00ff00Stealth Mode Active|r\nCommunicating via memory buffer.")
    else
        if mainFrame:IsShown() then mainFrame:Hide() else mainFrame:Show() end
    end
end

---------------- PAPERDOLL BUTTON ----------------

do
    -------------------------------------------------------------------------
    -- Clean icon button embedded inside CharacterModelFrame (top-right).
    -- Uses native WoW textures only — guaranteed to render correctly.
    -------------------------------------------------------------------------
    local SIZE = 32

    local btn = CreateFrame("Button", "TransmorpherPaperDollButton", CharacterModelFrame)
    btn:SetSize(SIZE, SIZE)
    btn:SetPoint("TOPRIGHT", CharacterModelFrame, "TOPRIGHT", -4, -4)
    btn:SetFrameStrata("HIGH")
    btn:SetFrameLevel(CharacterModelFrame:GetFrameLevel() + 15)
    btn:RegisterForClicks("LeftButtonUp")
    btn:SetMovable(true)
    btn:SetClampedToScreen(true)
    btn:RegisterForDrag("RightButton")

    -- Drag handling — right-click drag to freely reposition
    local isDragging = false

    local function SaveButtonPosition()
        local parentL = CharacterModelFrame:GetLeft()
        local parentT = CharacterModelFrame:GetTop()
        local bL = btn:GetLeft()
        local bT = btn:GetTop()
        if not parentL or not parentT or not bL or not bT then return end
        local xOff = bL - parentL
        local yOff = bT - parentT
        btn:ClearAllPoints()
        btn:SetPoint("TOPLEFT", CharacterModelFrame, "TOPLEFT", xOff, yOff)
        -- Save per-character
        if not TransmorpherCharacterState then
            TransmorpherCharacterState = { Items = {}, Morph = nil, Scale = nil, MountDisplay = nil, PetDisplay = nil, HunterPetDisplay = nil, EnchantMH = nil, EnchantOH = nil, WeaponSets = {} }
        end
        TransmorpherCharacterState.paperdollButtonPos = { x = xOff, y = yOff }
    end

    btn:SetScript("OnDragStart", function(self)
        isDragging = true
        self:StartMoving()
    end)
    btn:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        SaveButtonPosition()
        isDragging = false
    end)

    -- Restore saved per-character position
    if TransmorpherCharacterState and TransmorpherCharacterState.paperdollButtonPos then
        local p = TransmorpherCharacterState.paperdollButtonPos
        btn:ClearAllPoints()
        btn:SetPoint("TOPLEFT", CharacterModelFrame, "TOPLEFT", p.x, p.y)
    end

    -- Dark square background
    local bg = btn:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetTexture(0, 0, 0, 0.55)

    -- Icon — INV_Chest_Chain_05 (chestplate = transmog / appearance)
    local icon = btn:CreateTexture(nil, "ARTWORK")
    icon:SetSize(SIZE - 4, SIZE - 4)
    icon:SetPoint("CENTER")
    icon:SetTexture("Interface\\Icons\\INV_Chest_Cloth_17")
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    -- Thin golden border (1px simulated with 4 edge textures)
    local function MakeEdge(anchor1, rel, anchor2, x, y, w, h)
        local e = btn:CreateTexture(nil, "OVERLAY")
        e:SetTexture(1, 0.82, 0.1, 0.8)
        e:SetSize(w, h)
        e:SetPoint(anchor1, btn, anchor2, x, y)
        return e
    end
    MakeEdge("TOPLEFT",    "TOPLEFT",     "TOPLEFT",     0,  0,  SIZE, 1)  -- top
    MakeEdge("BOTTOMLEFT", "BOTTOMLEFT",  "BOTTOMLEFT",  0,  0,  SIZE, 1)  -- bottom
    MakeEdge("TOPLEFT",    "TOPLEFT",     "TOPLEFT",     0,  0,  1, SIZE)  -- left
    MakeEdge("TOPRIGHT",   "TOPRIGHT",    "TOPRIGHT",    0,  0,  1, SIZE)  -- right

    -- Highlight on hover — additive white overlay
    local hl = btn:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints(icon)
    hl:SetTexture(1, 1, 1, 0.2)
    hl:SetBlendMode("ADD")

    -- Active indicator — thin golden underline when transmog window is open
    local activeMark = btn:CreateTexture(nil, "OVERLAY")
    activeMark:SetSize(SIZE - 6, 2)
    activeMark:SetPoint("BOTTOM", btn, "BOTTOM", 0, 2)
    activeMark:SetTexture(1, 0.82, 0.1, 1)
    activeMark:Hide()

    ---- State management ----
    local function UpdateState()
        if mainFrame and mainFrame:IsShown() then
            activeMark:Show()
            bg:SetTexture(0.1, 0.06, 0, 0.7)
        else
            activeMark:Hide()
            bg:SetTexture(0, 0, 0, 0.55)
        end
    end

    ---- Tooltip ----
    btn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOMRIGHT")
        GameTooltip:AddLine("|cffFFD100Transmogrifier|r")
        GameTooltip:AddLine("Change your appearance", 0.7, 0.7, 0.7, true)
        GameTooltip:AddLine("|cff888888Right-click drag to move|r", 0.5, 0.5, 0.5, true)
        GameTooltip:Show()
    end)
    btn:SetScript("OnLeave", function() GameTooltip:Hide() end)

    ---- Click ----
    btn:SetScript("OnClick", function()
        if mainFrame:IsShown() then mainFrame:Hide() else mainFrame:Show() end
        PlaySound("igCharacterInfoTab")
        UpdateState()
    end)

    ---- Press feel (only for left-click, skip during right-drag) ----
    btn:SetScript("OnMouseDown", function(self, button)
        if button == "LeftButton" and not isDragging then
            icon:SetPoint("CENTER", 1, -1)
        end
    end)
    btn:SetScript("OnMouseUp", function(self, button)
        if button == "LeftButton" then
            icon:SetPoint("CENTER", 0, 0)
        end
    end)

    ---- Keep state synced ----
    if mainFrame then
        mainFrame:HookScript("OnShow", UpdateState)
        mainFrame:HookScript("OnHide", UpdateState)
    end
end

-- Print load message
DEFAULT_CHAT_FRAME:AddMessage("|cffF5C842\226\154\148 Transmorpher|r v1.0.3 loaded \226\128\148 |cffC8AA6E/morph|r or click the button on your character model.")
